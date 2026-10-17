// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
#import "cloud_transport.h"
#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
using namespace godot;
static NSString *ns(const String &s) {
  CharString c = s.utf8();
  return [[NSString alloc] initWithBytes:c.get_data()
                                  length:c.length()
                                encoding:NSUTF8StringEncoding];
}
static String gd(NSString *s) { return String::utf8(s.UTF8String); }
// Conversion is bounded and occurs only on the main thread. No Godot objects or
// Variants cross into a CloudKit block, operation, notification or worker
// queue.
static id foundation(const Variant &v, int depth, size_t &budget) {
  if (depth > 12 || budget == 0)
    return nil;
  budget--;
  switch (v.get_type()) {
  case Variant::STRING: {
    NSString *s = ns(v);
    NSUInteger bytes = [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (!s || bytes > budget)
      return nil;
    budget -= bytes;
    return s;
  }
  case Variant::BOOL:
    return @((bool)v);
  case Variant::INT:
    return @((int64_t)v);
  case Variant::FLOAT: {
    double n = v;
    return std::isfinite(n) ? @(n) : nil;
  }
  case Variant::PACKED_BYTE_ARRAY: {
    PackedByteArray a = v;
    if (a.size() > 1048576 || (size_t)a.size() > budget)
      return nil;
    budget -= a.size();
    return [NSData dataWithBytes:a.ptr() length:a.size()];
  }
  case Variant::DICTIONARY: {
    Dictionary d = v;
    if (d.size() > 128)
      return nil;
    NSMutableDictionary *out = [NSMutableDictionary new];
    Array keys = d.keys();
    for (int i = 0; i < keys.size(); i++) {
      if (keys[i].get_type() != Variant::STRING)
        return nil;
      id k = foundation(keys[i], depth + 1, budget),
         value = foundation(d[keys[i]], depth + 1, budget);
      if (!k || !value)
        return nil;
      out[k] = value;
    }
    return out;
  }
  case Variant::ARRAY: {
    Array a = v;
    if (a.size() > 256)
      return nil;
    NSMutableArray *out = [NSMutableArray new];
    for (int i = 0; i < a.size(); i++) {
      id value = foundation(a[i], depth + 1, budget);
      if (!value)
        return nil;
      [out addObject:value];
    }
    return out;
  }
  default:
    return nil;
  }
}
static Variant variant(id value) {
  if ([value isKindOfClass:NSString.class])
    return gd(value);
  if ([value isKindOfClass:NSData.class]) {
    PackedByteArray b;
    b.resize([value length]);
    if (b.size())
      memcpy(b.ptrw(), [value bytes], b.size());
    return b;
  }
  if ([value isKindOfClass:NSNumber.class]) {
    if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
      return (bool)[value boolValue];
    const char *type = [value objCType];
    if (strchr("fd", type[0]))
      return [value doubleValue];
    return (int64_t)[value longLongValue];
  }
  if ([value isKindOfClass:NSDictionary.class]) {
    Dictionary d;
    for (NSString *k in value)
      d[gd(k)] = variant(value[k]);
    return d;
  }
  if ([value isKindOfClass:NSArray.class]) {
    Array a;
    for (id item in value)
      a.push_back(variant(item));
    return a;
  }
  return Variant();
}
class SCDDAppleCloud : public RefCounted {
  GDCLASS(SCDDAppleCloud, RefCounted)
  SCDDCloudTransport *__strong transport = nil;
  static bool environment() {
    return [NSThread isMainThread] && Engine::get_singleton() &&
           !Engine::get_singleton()->is_editor_hint() && OS::get_singleton() &&
           !OS::get_singleton()->has_feature("editor") &&
           DisplayServer::get_singleton() &&
           DisplayServer::get_singleton()->get_name() != String("headless");
  }

protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "container_id", "staging_root"),
                         &SCDDAppleCloud::configure);
    ClassDB::bind_method(D_METHOD("available"), &SCDDAppleCloud::available);
    ClassDB::bind_method(D_METHOD("start_request", "request"),
                         &SCDDAppleCloud::start_request);
    ClassDB::bind_method(D_METHOD("drain_completions"),
                         &SCDDAppleCloud::drain_completions);
    ClassDB::bind_method(D_METHOD("cancel_all"), &SCDDAppleCloud::cancel_all);
  }

public:
  ~SCDDAppleCloud() {
    [transport cancelAll];
    transport = nil;
  }
  int configure(String container_id, String staging_root) {
    if (!environment())
      return ERR_UNAVAILABLE;
    ProjectSettings *settings = ProjectSettings::get_singleton();
    if (!(bool)settings->get_setting("apple_cloud/enabled", false) ||
        String(settings->get_setting("apple_cloud/container_id", String())) !=
            container_id)
      return ERR_UNAVAILABLE;
    NSString *container = ns(container_id), *root = ns(staging_root),
             *user = ns(OS::get_singleton()->get_user_data_dir());
    if (!root.isAbsolutePath ||
        ![root.stringByStandardizingPath
            hasPrefix:[user.stringByStandardizingPath
                          stringByAppendingString:@"/"]])
      return ERR_INVALID_PARAMETER;
    id<SCDDCloudOperationFactory> factory = SCDDCreateRealFactory(container);
    if (!factory)
      return ERR_UNAVAILABLE;
    [transport cancelAll];
    transport = [[SCDDCloudTransport alloc] initWithFactory:factory
                                                  container:container
                                                stagingRoot:root];
    return transport ? OK : ERR_CANT_CREATE;
  }
  bool available() const { return environment() && transport != nil; }
  int start_request(Dictionary request) {
    if (!available())
      return ERR_UNAVAILABLE;
    size_t budget = 2097152;
    id input = foundation(request, 0, budget);
    if (!input)
      return ERR_INVALID_PARAMETER;
    return [transport startRequest:input] ? OK : ERR_INVALID_PARAMETER;
  }
  Array drain_completions() {
    if (![NSThread isMainThread] || !transport)
      return Array();
    return variant([transport drainCompletions]);
  }
  void cancel_all() { [transport cancelAll]; }
};
static void initialize_cloud(ModuleInitializationLevel level) {
  if (level == MODULE_INITIALIZATION_LEVEL_SCENE)
    ClassDB::register_class<SCDDAppleCloud>();
}
extern "C" GDExtensionBool GDE_EXPORT
scdd_apple_cloud_init(GDExtensionInterfaceGetProcAddress get_proc_address,
                      GDExtensionClassLibraryPtr library,
                      GDExtensionInitialization *initialization) {
  GDExtensionBinding::InitObject init(get_proc_address, library,
                                      initialization);
  init.register_initializer(initialize_cloud);
  init.set_minimum_library_initialization_level(
      MODULE_INITIALIZATION_LEVEL_SCENE);
  return init.init();
}
