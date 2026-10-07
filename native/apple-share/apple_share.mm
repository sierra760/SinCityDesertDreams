// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Original share-sheet adapter. No accounts, contacts, network calls or analytics.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif
using namespace godot;
static bool share_busy = false;
static int share_status = -1;
#if !TARGET_OS_IPHONE
@interface SCDDShareDelegate : NSObject <NSSharingServicePickerDelegate, NSSharingServiceDelegate>
@property(nonatomic, strong) NSSharingServicePicker *picker;
@end
static SCDDShareDelegate *share_delegate;
@implementation SCDDShareDelegate
- (void)sharingServicePicker:(NSSharingServicePicker *)picker didChooseSharingService:(NSSharingService *)service {
    if (!service) { share_busy = false; share_status = 0; self.picker = nil; }
}
- (id<NSSharingServiceDelegate>)sharingServicePicker:(NSSharingServicePicker *)picker delegateForSharingService:(NSSharingService *)service { return self; }
- (void)sharingService:(NSSharingService *)service didShareItems:(NSArray *)items { share_busy = false; share_status = 1; self.picker = nil; }
- (void)sharingService:(NSSharingService *)service didFailToShareItems:(NSArray *)items error:(NSError *)error { share_busy = false; share_status = -2; self.picker = nil; }
- (NSWindow *)sharingService:(NSSharingService *)service sourceWindowForShareItems:(NSArray *)items sharingContentScope:(NSSharingContentScope *)scope { return NSApp.mainWindow ?: NSApp.keyWindow; }
@end
#endif
class SCDDNativeShare : public RefCounted {
    GDCLASS(SCDDNativeShare, RefCounted)
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("is_available"), &SCDDNativeShare::is_available);
        ClassDB::bind_method(D_METHOD("is_busy"), &SCDDNativeShare::is_busy);
        ClassDB::bind_method(D_METHOD("completion_status"), &SCDDNativeShare::completion_status);
        ClassDB::bind_method(D_METHOD("share_file", "path", "title", "message"), &SCDDNativeShare::share_file);
    }
public:
    bool is_available() const {
#if TARGET_OS_IPHONE
        return UIApplication.sharedApplication != nil;
#else
        return NSApp != nil;
#endif
    }
    bool is_busy() const { return share_busy; }
    int completion_status() const { return share_status; }
    int share_file(String path, String title, String message) {
        if (![NSThread isMainThread]) return 2; // ERR_UNAVAILABLE
        if (share_busy) return 44; // ERR_BUSY
        NSString *filename = [NSString stringWithUTF8String:path.utf8().get_data()];
        NSString *subject = [NSString stringWithUTF8String:title.utf8().get_data()];
        NSString *body = [NSString stringWithUTF8String:message.utf8().get_data()];
        BOOL directory = NO;
        if (!filename || ![filename.pathExtension.lowercaseString isEqualToString:@"sc2d"] || ![[NSFileManager defaultManager] fileExistsAtPath:filename isDirectory:&directory] || directory) return 31; // ERR_INVALID_PARAMETER
        NSURL *url = [NSURL fileURLWithPath:filename];
#if TARGET_OS_IPHONE
        UIWindow *window = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow) { window = candidate; break; }
            }
            if (window) break;
        }
        // Godot templates may use the UIApplicationDelegate window instead of scenes.
        if (!window) {
            id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
            if ([delegate respondsToSelector:@selector(window)]) window = delegate.window;
        }
        UIViewController *presenter = window.rootViewController;
        while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) presenter = presenter.presentedViewController;
        if (!presenter || !presenter.view.window || presenter.isBeingDismissed || presenter.isBeingPresented) return 2;
        UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[body,url] applicationActivities:nil];
        [sheet setValue:subject forKey:@"subject"];
        // iPad requires a popover source, including portrait/split-screen windows.
        sheet.popoverPresentationController.sourceView = presenter.view;
        CGRect bounds = presenter.view.bounds;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(bounds),CGRectGetMidY(bounds),1,1);
        sheet.popoverPresentationController.permittedArrowDirections = 0;
        sheet.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *returnedItems, NSError *error) {
            share_status = error ? -2 : (completed ? 1 : 0);
            share_busy = false;
        };
        share_status = -1; share_busy = true;
        [presenter presentViewController:sheet animated:YES completion:nil];
#else
        NSWindow *window = NSApp.mainWindow ?: NSApp.keyWindow;
        if (!window.contentView) return 2;
        share_delegate = [[SCDDShareDelegate alloc] init];
        NSSharingServicePicker *picker = [[NSSharingServicePicker alloc] initWithItems:@[body,url]];
        picker.delegate = share_delegate;
        share_delegate.picker = picker;
        share_status = -1; share_busy = true;
        NSView *view = window.contentView;
        [picker showRelativeToRect:NSMakeRect(NSMidX(view.bounds),NSMidY(view.bounds),1,1) ofView:view preferredEdge:NSRectEdgeMinY];
#endif
        return 0;
    }
};
static void initialize_share(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<SCDDNativeShare>();
}
extern "C" GDExtensionBool GDE_EXPORT scdd_share_init(GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address,library,initialization);
    init.register_initializer(initialize_share);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
