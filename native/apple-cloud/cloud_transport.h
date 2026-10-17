// SPDX-License-Identifier: GPL-3.0-or-later
#import <CloudKit/CloudKit.h>
#import <Foundation/Foundation.h>
// Injected tests construct operation objects but never construct CKContainer.
@protocol SCDDCloudOperationFactory <NSObject>
- (CKDatabaseOperation *)operation:(Class)kind;
// Returns nil once the operation is owned by CloudKit. An error means the
// operation was never added and none of its callbacks will run.
- (NSError *)submit:(CKDatabaseOperation *)operation;
- (void)cancelAccountRequests;
- (void)account:(void (^)(NSString *, NSError *))completion;
@end
@interface SCDDCloudTransport : NSObject
- (instancetype)initWithFactory:(id<SCDDCloudOperationFactory>)factory
                      container:(NSString *)container
                    stagingRoot:(NSString *)root;
- (BOOL)startRequest:(NSDictionary *)request;
- (NSArray<NSDictionary *> *)drainCompletions;
- (void)cancelAll;
@end
id<SCDDCloudOperationFactory> SCDDCreateRealFactory(NSString *container);
BOOL SCDDCloudRuntimeConfigured(NSString *container);
BOOL SCDDCloudConfigurationAllows(NSDictionary *info, NSString *container);
BOOL SCDDCloudEntitlementsAllow(id entitlements, NSString *container);
