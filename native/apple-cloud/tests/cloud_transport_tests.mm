// SPDX-License-Identifier: GPL-3.0-or-later
#import "../cloud_transport.h"
#import <CommonCrypto/CommonDigest.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
@interface FakeFactory : NSObject <SCDDCloudOperationFactory>
@property NSMutableArray<CKDatabaseOperation *> *operations;
@property(copy) void (^accountCompletion)(NSString *, NSError *);
@property NSError *submitError;
@property BOOL submitThrows;
@end
@implementation FakeFactory
- (instancetype)init {
  if ((self = [super init]))
    _operations = [NSMutableArray new];
  return self;
}
- (CKDatabaseOperation *)operation:(Class)kind {
  return [kind new];
}
- (NSError *)submit:(CKDatabaseOperation *)operation {
  if (_submitThrows)
    [NSException raise:NSInternalInconsistencyException format:@"refused"];
  if (_submitError)
    return _submitError;
  @synchronized(self) {
    [_operations addObject:operation];
  }
  return nil;
}
- (void)cancelAccountRequests {
}
- (void)account:(void (^)(NSString *, NSError *))completion {
  self.accountCompletion = completion;
}
@end
static int passed = 0, failed = 0;
#define CHECK(x)                                                               \
  do {                                                                         \
    if (x)                                                                     \
      passed++;                                                                \
    else {                                                                     \
      failed++;                                                                \
      fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x);                     \
    }                                                                          \
  } while (0)
static long long testEpoch = 7;
static NSDictionary *request(NSString *op, NSDictionary *args) {
  return @{
    @"id" : NSUUID.UUID.UUIDString,
    @"epoch" : @(testEpoch),
    @"op" : op,
    @"args" : args
  };
}
static CKRecordZoneID *zone() {
  return [[CKRecordZoneID alloc] initWithZoneName:@"SCDDCloudSavesV1"
                                        ownerName:CKCurrentUserDefaultName];
}
static CKRecord *record() {
  CKRecord *r = [[CKRecord alloc]
      initWithRecordType:@"SCDDCitySaveV1"
                recordID:[[CKRecordID alloc] initWithRecordName:@"slot"
                                                         zoneID:zone()]];
  r[@"commit_id"] = @"commit";
  r[@"continuation_sha256"] = [@"a" stringByPaddingToLength:64
                                                 withString:@"a"
                                            startingAtIndex:0];
  r[@"manual_sha256"] = @"";
  r[@"tombstone"] = @NO;
  r[@"metadata"] = [NSJSONSerialization dataWithJSONObject:@{@"name" : @"Test"}
                                                   options:0
                                                     error:nil];
  return r;
}
static NSData *fields(CKRecord *r) {
  NSKeyedArchiver *a = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
  [r encodeSystemFieldsWithCoder:a];
  [a finishEncoding];
  return a.encodedData;
}
static NSString *hash(NSData *d) {
  unsigned char digest[32];
  CC_SHA256(d.bytes, (CC_LONG)d.length, digest);
  NSMutableString *s = [NSMutableString new];
  for (int i = 0; i < 32; i++)
    [s appendFormat:@"%02x", digest[i]];
  return s;
}
static CKDatabaseOperation *last(FakeFactory *f) {
  for (int i = 0; i < 500; i++) {
    @synchronized(f) {
      if (f.operations.count)
        return f.operations.lastObject;
    }
    usleep(1000);
  }
  return nil;
}
static NSDictionary *next(SCDDCloudTransport *t) {
  for (int i = 0; i < 500; i++) {
    NSArray *a = [t drainCompletions];
    if (a.count)
      return a.firstObject;
    usleep(1000);
  }
  return nil;
}
static NSError *error(NSInteger c) {
  return [NSError errorWithDomain:CKErrorDomain code:c userInfo:nil];
}
static NSError *partial(CKRecordID *rid, NSError *child) {
  return [NSError errorWithDomain:CKErrorDomain
                             code:CKErrorPartialFailure
                         userInfo:@{CKPartialErrorsByItemIDKey : @{rid : child}}];
}
static CKRecord *named(NSString *name) {
  CKRecord *r = [[CKRecord alloc]
      initWithRecordType:@"SCDDCitySaveV1"
                recordID:[[CKRecordID alloc] initWithRecordName:name
                                                         zoneID:zone()]];
  CKRecord *base = record();
  for (NSString *k in base.allKeys)
    r[k] = base[k];
  return r;
}
static SCDDCloudTransport *transport(FakeFactory *f, NSString *root) {
  return [[SCDDCloudTransport alloc] initWithFactory:f
                                           container:@"test.container"
                                         stagingRoot:root];
}
int main() {
  @autoreleasepool {
    NSString *root = [NSTemporaryDirectory()
        stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    FakeFactory *f = [FakeFactory new];
    SCDDCloudTransport *t = transport(f, root);
    CHECK([t startRequest:request(@"account", @{})]);
    CHECK(f.accountCompletion != nil);
    if (f.accountCompletion) {
      f.accountCompletion(@"opaque-user", nil);
      NSDictionary *c = next(t);
      CHECK([c[@"result"][@"owner"] length] == 64);
      CHECK([c[@"epoch"] intValue] == 7);
      CHECK([c[@"ok"] boolValue]);
    }
    CHECK(![t startRequest:@{}]);
    CHECK(![t startRequest:request(@"unknown", @{})]);
    CHECK([t startRequest:request(
                              @"changes",
                              @{@"token" : [NSData data],
                                @"limit" : @256})]);
    CKFetchRecordZoneChangesOperation *op = (id)last(f);
    CHECK(op != nil);
    if (op) {
      CHECK(!op.fetchAllChanges);
      CHECK(
          op.configurationsByRecordZoneID.allValues.firstObject.resultsLimit ==
          256);
      CHECK(![op.configurationsByRecordZoneID.allValues.firstObject.desiredKeys
          containsObject:@"continuation"]);
      op.recordWasChangedBlock(record().recordID, record(), nil);
      op.recordWithIDWasDeletedBlock(
          [[CKRecordID alloc] initWithRecordName:@"removed" zoneID:zone()],
          @"SCDDCitySaveV1");
      op.recordZoneFetchCompletionBlock(zone(), nil, nil, YES, nil);
      op.fetchRecordZoneChangesCompletionBlock(nil);
      NSDictionary *c = next(t);
      CHECK([c[@"ok"] boolValue]);
      CHECK([c[@"result"][@"records"] count] == 1);
      CHECK([c[@"result"][@"deleted_ids"] count] == 1);
      CHECK([c[@"result"][@"more"] boolValue]);
    }
    [f.operations removeAllObjects];
    CHECK([t startRequest:request(@"fetch_record", @{@"slot_id" : @"slot"})]);
    CKFetchRecordsOperation *fetch = (id)last(f);
    if (fetch) {
      CHECK(![fetch.desiredKeys containsObject:@"continuation"]);
      fetch.perRecordCompletionBlock(nil, fetch.recordIDs.firstObject,
                                     error(CKErrorUnknownItem));
      fetch.fetchRecordsCompletionBlock(
          nil, [NSError errorWithDomain:CKErrorDomain
                                   code:CKErrorPartialFailure
                               userInfo:@{
                                 CKPartialErrorsByItemIDKey : @{
                                   fetch.recordIDs.
                                   firstObject : error(CKErrorUnknownItem)
                                 }
                               }]);
      NSDictionary *c = next(t);
      CHECK([c[@"ok"] boolValue]);
      CHECK([c[@"result"][@"remote"] count] == 0);
    }
    [f.operations removeAllObjects];
    [t startRequest:request(@"fetch_record", @{@"slot_id" : @"slot"})];
    fetch = (id)last(f);
    if (fetch) {
      fetch.fetchRecordsCompletionBlock(nil, error(CKErrorPermissionFailure));
      NSDictionary *c = next(t);
      CHECK(![c[@"ok"] boolValue]);
      CHECK([c[@"code"] isEqual:@"permission"]);
    }
    // A real conditional-save operation uses the baseline system-field archive.
    NSString *source = [root stringByAppendingPathComponent:@"source.sc2d"];
    [[NSFileManager defaultManager] createDirectoryAtPath:root
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSData *bytes = [@"synthetic save" dataUsingEncoding:NSUTF8StringEncoding];
    [bytes writeToFile:source atomically:YES];
    NSDictionary *payload = @{
      @"path" : source,
      @"sha256" : hash(bytes),
      @"bytes" : @(bytes.length)
    };
    NSMutableDictionary *pending = [@{
      @"slot_id" : @"slot",
      @"commit_id" : @"next",
      @"parent_commit_id" : @"commit",
      @"generation" : @1,
      @"owner" : @"owner",
      @"baseline" : fields(record()),
      @"baseline_tag" : @"",
      @"continuation" : payload,
      @"manual" : @{},
      @"tombstone" : @NO
    } mutableCopy];
    [f.operations removeAllObjects];
    CHECK([t startRequest:request(
                              @"save", @{
                                @"pending" : pending,
                                @"metadata" : @{@"name" : @"Test"}
                              })]);
    CKModifyRecordsOperation *save = (id)last(f);
    CHECK(save != nil);
    if (save) {
      CHECK(save.savePolicy == CKRecordSaveIfServerRecordUnchanged);
      CHECK(save.atomic);
      CHECK(
          [save.recordsToSave.firstObject.recordID.recordName isEqual:@"slot"]);
      CKAsset *asset = save.recordsToSave.firstObject[@"continuation"];
      CHECK(asset != nil);
      CHECK(![asset.fileURL.path isEqual:source]);
      CHECK([[NSData dataWithContentsOfURL:asset.fileURL] isEqual:bytes]);
      NSError *conflict =
          [NSError errorWithDomain:CKErrorDomain
                              code:CKErrorServerRecordChanged
                          userInfo:@{
                            CKRecordChangedErrorServerRecordKey : record(),
                            CKErrorRetryAfterKey : @123
                          }];
      save.modifyRecordsCompletionBlock(
          nil, nil,
          [NSError
              errorWithDomain:CKErrorDomain
                         code:CKErrorPartialFailure
                     userInfo:@{
                       CKPartialErrorsByItemIDKey :
                           @{save.recordsToSave.firstObject.recordID : conflict}
                     }]);
      NSDictionary *c = next(t);
      CHECK([c[@"code"] isEqual:@"conflict"]);
      CHECK([c[@"retry_after_ms"] integerValue] == 123000);
      CHECK([c[@"result"][@"remote"][@"commit_id"] isEqual:@"commit"]);
    }
    // Cancellation and account transitions invalidate in-flight and queued
    // callbacks.
    [f.operations removeAllObjects];
    [t startRequest:request(@"fetch_record", @{@"slot_id" : @"slot"})];
    fetch = (id)last(f);
    [t cancelAll];
    CHECK(fetch.cancelled);
    if (fetch)
      fetch.fetchRecordsCompletionBlock(@{record().recordID : record()}, nil);
    CHECK([t drainCompletions].count == 0);
    [f.operations removeAllObjects];
    [t startRequest:request(@"fetch_record", @{@"slot_id" : @"slot"})];
    fetch = (id)last(f);
    [[NSNotificationCenter defaultCenter]
        postNotificationName:CKAccountChangedNotification
                      object:nil];
    CHECK(fetch.cancelled);
    if (fetch)
      fetch.fetchRecordsCompletionBlock(@{record().recordID : record()}, nil);
    CHECK(![t startRequest:request(
                               @"save",
                               @{@"pending" : pending,
                                 @"metadata" : @{}})]);
    CHECK(![t startRequest:request(@"account", @{})]);
    CHECK(![t startRequest:request(@"fetch_record", @{@"slot_id" : @"slot"})]);
    NSArray *events = [t drainCompletions];
    CHECK(events.count == 1);
    if (events.count) {
      CHECK([events[0][@"op"] isEqual:@"account_changed"]);
      CHECK([events[0][@"epoch"] intValue] == 7);
    }
    testEpoch++;
    CHECK([t startRequest:request(@"account", @{})]);
    if (f.accountCompletion)
      f.accountCompletion(nil, error(CKErrorAccountTemporarilyUnavailable));
    CHECK([next(t)[@"code"] isEqual:@"unavailable"]);
    CHECK(![t startRequest:request(
                               @"save",
                               @{@"pending" : pending,
                                 @"metadata" : @{}})]);
    CHECK([t startRequest:request(@"account", @{})]);
    if (f.accountCompletion)
      f.accountCompletion(@"new-account", nil);
    CHECK([next(t)[@"ok"] boolValue]);
    // Destruction cannot leave callbacks dereferencing a dead
    // extension/transport.
    @autoreleasepool {
      SCDDCloudTransport *gone =
          transport(f, [root stringByAppendingPathComponent:@"gone"]);
      [gone startRequest:request(@"account", @{})];
    }
    if (f.accountCompletion)
      f.accountCompletion(@"late-user", nil);
    CHECK(YES);
    // Download version matching, copied-asset lifetime and account change
    // cleanup.
    CKRecord *downloadRecord = record();
    downloadRecord[@"continuation_sha256"] = hash(bytes);
    downloadRecord[@"continuation"] =
        [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:source]];
    NSDictionary *expected = @{
      @"slot_id" : @"slot",
      @"commit_id" : @"commit",
      @"change_tag" : @"",
      @"system_fields" : fields(downloadRecord),
      @"continuation_sha256" : hash(bytes),
      @"manual_sha256" : @"",
      @"tombstone" : @NO,
      @"metadata" : @{@"name" : @"Test"}
    };
    [t cancelAll];
    [f.operations removeAllObjects];
    [t startRequest:request(
                        @"download",
                        @{@"remote" : expected,
                          @"max_bytes" : @67108864})];
    fetch = (id)last(f);
    CHECK([fetch.desiredKeys containsObject:@"continuation"]);
    if (fetch) {
      fetch.perRecordCompletionBlock(downloadRecord, downloadRecord.recordID,
                                     nil);
      fetch.fetchRecordsCompletionBlock(
          @{downloadRecord.recordID : downloadRecord}, nil);
      NSDictionary *c = next(t);
      CHECK([c[@"ok"] boolValue]);
      NSString *copied = c[@"result"][@"downloaded"][@"continuation"];
      CHECK(copied != nil);
      if (copied) {
        CHECK(![copied isEqual:source]);
        CHECK([[NSData dataWithContentsOfFile:copied] isEqual:bytes]);
        [t drainCompletions];
        CHECK(![[NSFileManager defaultManager] fileExistsAtPath:copied]);
      }
    }
    [f.operations removeAllObjects];
    [t startRequest:request(
                        @"download",
                        @{@"remote" : expected,
                          @"max_bytes" : @67108864})];
    fetch = (id)last(f);
    if (fetch) {
      downloadRecord[@"commit_id"] = @"changed";
      fetch.perRecordCompletionBlock(downloadRecord, downloadRecord.recordID,
                                     nil);
      fetch.fetchRecordsCompletionBlock(nil, nil);
      NSDictionary *c = next(t);
      CHECK([c[@"code"] isEqual:@"conflict"]);
      CHECK([c[@"result"][@"remote"][@"commit_id"] isEqual:@"changed"]);
      downloadRecord[@"commit_id"] = @"commit";
    }
    [f.operations removeAllObjects];
    [t startRequest:request(
                        @"download",
                        @{@"remote" : expected,
                          @"max_bytes" : @67108864})];
    fetch = (id)last(f);
    if (fetch) {
      fetch.perRecordCompletionBlock(downloadRecord, downloadRecord.recordID,
                                     nil);
      fetch.fetchRecordsCompletionBlock(nil, nil);
      [[NSNotificationCenter defaultCenter]
          postNotificationName:CKAccountChangedNotification
                        object:nil];
      NSArray *batch = [t drainCompletions];
      CHECK(batch.count == 1);
      CHECK([batch.firstObject[@"op"] isEqual:@"account_changed"]);
      NSDirectoryEnumerator *items =
          [[NSFileManager defaultManager] enumeratorAtPath:root];
      NSUInteger count = 0;
      for (NSString *file in items)
        if ([file.pathExtension isEqual:@"sc2d"])
          count++;
      CHECK(count == 1);
    }
    testEpoch++;
    CHECK([t startRequest:request(@"account", @{})]);
    if (f.accountCompletion)
      f.accountCompletion(@"third-account", nil);
    CHECK([next(t)[@"ok"] boolValue]);
    // Malformed archives reject without dispatch, rather than creating a new
    // root.
    [f.operations removeAllObjects];
    pending[@"baseline"] = [@"invalid" dataUsingEncoding:NSUTF8StringEncoding];
    [t startRequest:request(
                        @"save",
                        @{@"pending" : pending,
                          @"metadata" : @{}})];
    NSDictionary *bad = next(t);
    CHECK([bad[@"code"] isEqual:@"invalid"]);
    CHECK(f.operations.count == 0);
    pending[@"baseline"] = fields(record());
    [f.operations removeAllObjects];
    [t startRequest:request(
                        @"changes", @{
                          @"token" : [@"invalid"
                              dataUsingEncoding:NSUTF8StringEncoding],
                          @"limit" : @256
                        })];
    bad = next(t);
    CHECK([bad[@"code"] isEqual:@"invalid"]);
    CHECK(f.operations.count == 0);
    // Sparse oversized assets are refused before any large allocation or copy.
    NSString *large = [root stringByAppendingPathComponent:@"oversized"];
    int fd = open(large.fileSystemRepresentation, O_CREAT | O_WRONLY, 0600);
    ftruncate(fd, 67108865);
    close(fd);
    downloadRecord[@"continuation"] =
        [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:large]];
    [f.operations removeAllObjects];
    [t startRequest:request(
                        @"download",
                        @{@"remote" : expected,
                          @"max_bytes" : @67108864})];
    fetch = (id)last(f);
    if (fetch) {
      fetch.perRecordCompletionBlock(downloadRecord, downloadRecord.recordID,
                                     nil);
      fetch.fetchRecordsCompletionBlock(nil, nil);
      CHECK([next(t)[@"code"] isEqual:@"invalid"]);
    }
    BOOL threw = NO;
    @try {
      [t startRequest:request(
                          @"download", @{
                            @"remote" : @"malformed",
                            @"max_bytes" : @67108864
                          })];
    } @catch (NSException *) {
      threw = YES;
    }
    CHECK(!threw);
    // Disabled and mismatched sealed configuration never authorizes a factory.
    CHECK(!SCDDCloudConfigurationAllows(
        @{}, @"iCloud.com.sierraburkhart.sincitydesertdreams"));
    CHECK(!SCDDCloudConfigurationAllows(
        @{@"SCDDCloudKitEnabled" : @YES,
          @"SCDDCloudKitContainer" : @"wrong"},
        @"iCloud.com.sierraburkhart.sincitydesertdreams"));
    CHECK(!SCDDCloudRuntimeConfigured(
        @"iCloud.com.sierraburkhart.sincitydesertdreams"));
    CHECK(SCDDCloudConfigurationAllows(
        @{
          @"SCDDCloudKitEnabled" : @YES,
          @"SCDDCloudKitContainer" :
              @"iCloud.com.sierraburkhart.sincitydesertdreams"
        },
        @"iCloud.com.sierraburkhart.sincitydesertdreams"));
    // Malformed server conflicts must always deliver a terminal completion.
    [t cancelAll];
    [f.operations removeAllObjects];
    NSDictionary *tombstone = @{
      @"slot_id" : @"slot",
      @"commit_id" : @"commit",
      @"tombstone" : @YES,
      @"baseline" : [NSData data],
      @"baseline_tag" : @"",
      @"manual" : @{}
    };
    [t startRequest:request(
                        @"save",
                        @{@"pending" : tombstone,
                          @"metadata" : @{}})];
    CKModifyRecordsOperation *badSave = (id)last(f);
    CKRecord *badServer = [[CKRecord alloc]
        initWithRecordType:@"SCDDCitySaveV1"
                  recordID:badSave.recordsToSave.firstObject.recordID];
    NSError *badConflict = [NSError
        errorWithDomain:CKErrorDomain
                   code:CKErrorServerRecordChanged
               userInfo:@{CKRecordChangedErrorServerRecordKey : badServer}];
    badSave.modifyRecordsCompletionBlock(nil, nil, badConflict);
    NSDictionary *terminal = next(t);
    CHECK([terminal[@"code"] isEqual:@"invalid"]);
    CHECK(![terminal[@"ok"] boolValue]);
    const char *fixture = getenv("SCDD_NATIVE_CONFLICT_FIXTURE");
    if (fixture) {
      NSData *json = [NSJSONSerialization dataWithJSONObject:terminal
                                                     options:0
                                                       error:nil];
      CHECK([json writeToFile:[NSString stringWithUTF8String:fixture]
                   atomically:YES]);
    }
    // Keep semantic leaf errors plus the longest applicable callback hint.
    NSError *shortQuota = [NSError errorWithDomain:CKErrorDomain
                                              code:CKErrorQuotaExceeded
                                          userInfo:@{
                                            CKErrorRetryAfterKey : @2
                                          }];
    for (NSString *kind in @[ @"fetch_record", @"download" ]) {
      [f.operations removeAllObjects];
      [t startRequest:request(kind, [kind isEqual:@"download"]
                                        ? @{
                                            @"remote" : expected,
                                            @"max_bytes" : @67108864
                                          }
                                        : @{@"slot_id" : @"slot"})];
      CKFetchRecordsOperation *retryFetch = (id)last(f);
      NSError *longParent =
          [NSError errorWithDomain:CKErrorDomain
                              code:CKErrorPartialFailure
                          userInfo:@{
                            CKErrorRetryAfterKey : @120,
                            CKPartialErrorsByItemIDKey :
                                @{retryFetch.recordIDs.firstObject : shortQuota}
                          }];
      retryFetch.perRecordCompletionBlock(nil, retryFetch.recordIDs.firstObject,
                                          shortQuota);
      retryFetch.fetchRecordsCompletionBlock(nil, longParent);
      NSDictionary *completion = next(t);
      CHECK([completion[@"code"] isEqual:@"quota"]);
      CHECK([completion[@"retry_after_ms"] longLongValue] == 120000);
    }
    [f.operations removeAllObjects];
    [t startRequest:request(
                        @"download",
                        @{@"remote" : expected,
                          @"max_bytes" : @67108864})];
    CKFetchRecordsOperation *retryConflict = (id)last(f);
    NSError *serverConflict =
        [NSError errorWithDomain:CKErrorDomain
                            code:CKErrorServerRecordChanged
                        userInfo:@{
                          CKErrorRetryAfterKey : @2,
                          CKRecordChangedErrorServerRecordKey : record()
                        }];
    retryConflict.perRecordCompletionBlock(
        nil, retryConflict.recordIDs.firstObject, serverConflict);
    retryConflict.fetchRecordsCompletionBlock(
        nil, [NSError errorWithDomain:CKErrorDomain
                                 code:CKErrorServiceUnavailable
                             userInfo:@{
                               CKErrorRetryAfterKey : @120
                             }]);
    NSDictionary *preserved = next(t);
    CHECK([preserved[@"code"] isEqual:@"conflict"]);
    CHECK([preserved[@"result"][@"remote"][@"commit_id"] isEqual:@"commit"]);
    CHECK([preserved[@"retry_after_ms"] longLongValue] == 120000);
    for (NSNumber *recordDelay in @[ @2, @180 ]) {
      [f.operations removeAllObjects];
      [t startRequest:request(
                          @"changes",
                          @{@"token" : [NSData data],
                            @"limit" : @256})];
      CKFetchRecordZoneChangesOperation *page = (id)last(f);
      NSError *item =
          [NSError errorWithDomain:CKErrorDomain
                              code:CKErrorServiceUnavailable
                          userInfo:@{CKErrorRetryAfterKey : recordDelay}];
      page.recordWasChangedBlock(record().recordID, nil, item);
      page.recordZoneFetchCompletionBlock(zone(), nil, nil, NO, shortQuota);
      page.fetchRecordZoneChangesCompletionBlock([NSError
          errorWithDomain:CKErrorDomain
                     code:CKErrorServiceUnavailable
                 userInfo:@{
                   CKErrorRetryAfterKey : @120
                 }]);
      NSDictionary *completion = next(t);
      CHECK([completion[@"code"] isEqual:@"quota"]);
      CHECK([completion[@"retry_after_ms"] longLongValue] ==
            MAX(120000, recordDelay.longLongValue * 1000));
    }
    // Queue synchronization under simultaneous off-main completion and
    // draining.
    [t cancelAll];
    dispatch_group_t group = dispatch_group_create();
    NSUInteger received = 0;
    for (int i = 0; i < 8; i++) {
      [f.operations removeAllObjects];
      CHECK([t startRequest:request(@"fetch_record", @{@"slot_id" : @"slot"})]);
      CKFetchRecordsOperation *item = (id)last(f);
      if (item)
        dispatch_group_async(
            group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
              item.fetchRecordsCompletionBlock(@{record().recordID : record()},
                                               nil);
              item.fetchRecordsCompletionBlock(@{record().recordID : record()},
                                               nil);
            });
      received += [t drainCompletions].count;
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    received += [t drainCompletions].count;
    CHECK(received == 8);
    // A missing or Settings-deleted zone has its own codes, so the coordinator
    // can prepare the zone again (or ask first) instead of retrying forever.
    [t cancelAll];
    [f.operations removeAllObjects];
    [t startRequest:request(@"changes",
                            @{@"token" : [NSData data], @"limit" : @256})];
    CKFetchRecordZoneChangesOperation *gone = (id)last(f);
    if (gone) {
      gone.recordZoneFetchCompletionBlock(zone(), nil, nil, NO,
                                          error(CKErrorZoneNotFound));
      gone.fetchRecordZoneChangesCompletionBlock(
          [NSError errorWithDomain:CKErrorDomain
                              code:CKErrorPartialFailure
                          userInfo:@{
                            CKPartialErrorsByItemIDKey :
                                @{zone() : error(CKErrorZoneNotFound)}
                          }]);
      NSDictionary *c = next(t);
      CHECK(![c[@"ok"] boolValue]);
      CHECK([c[@"code"] isEqual:@"zone_missing"]);
    }
    pending[@"baseline"] = fields(record());
    for (NSArray *pair in @[
           @[ @(CKErrorZoneNotFound), @"zone_missing" ],
           @[ @(CKErrorUserDeletedZone), @"zone_deleted" ],
           @[ @(CKErrorUnknownItem), @"record_missing" ]
         ]) {
      [f.operations removeAllObjects];
      CHECK([t startRequest:request(@"save", @{
                 @"pending" : pending,
                 @"metadata" : @{@"name" : @"Test"}
               })]);
      CKModifyRecordsOperation *op = (id)last(f);
      CHECK(op != nil);
      if (!op)
        continue;
      op.modifyRecordsCompletionBlock(
          nil, nil,
          partial(op.recordsToSave.firstObject.recordID,
                  error([pair[0] integerValue])));
      NSDictionary *c = next(t);
      CHECK([c[@"code"] isEqual:pair[1]]);
      CHECK([c[@"result"] count] == 0);
    }
    // A download whose record vanished after inventory listed it.
    CKRecord *listed = record();
    listed[@"continuation_sha256"] = hash(bytes);
    listed[@"continuation"] =
        [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:source]];
    [f.operations removeAllObjects];
    [t startRequest:request(@"download", @{
         @"remote" : expected,
         @"max_bytes" : @67108864
       })];
    CKFetchRecordsOperation *vanished = (id)last(f);
    if (vanished) {
      CKRecordID *rid = vanished.recordIDs.firstObject;
      vanished.perRecordCompletionBlock(nil, rid, error(CKErrorUnknownItem));
      vanished.fetchRecordsCompletionBlock(
          nil, partial(rid, error(CKErrorUnknownItem)));
      NSDictionary *c = next(t);
      CHECK(![c[@"ok"] boolValue]);
      CHECK([c[@"code"] isEqual:@"record_missing"]);
      CHECK(c[@"result"][@"downloaded"] == nil);
    }
    // One record that fails validation is skipped; the rest of the page and
    // its token still arrive. CloudKit item errors still fail the page.
    [f.operations removeAllObjects];
    [t startRequest:request(@"changes",
                            @{@"token" : [NSData data], @"limit" : @256})];
    CKFetchRecordZoneChangesOperation *mixed = (id)last(f);
    if (mixed) {
      CKRecord *big = named(@"big");
      big[@"metadata"] = [NSMutableData dataWithLength:65537];
      CKRecord *untyped = named(@"untyped");
      untyped[@"commit_id"] = nil;
      CKRecord *foreign = [[CKRecord alloc]
          initWithRecordType:@"Other"
                    recordID:[[CKRecordID alloc] initWithRecordName:@"other"
                                                             zoneID:zone()]];
      mixed.recordWasChangedBlock(big.recordID, big, nil);
      mixed.recordWasChangedBlock(untyped.recordID, untyped, nil);
      mixed.recordWasChangedBlock(foreign.recordID, foreign, nil);
      mixed.recordWasChangedBlock(named(@"elsewhere").recordID, record(), nil);
      mixed.recordWasChangedBlock(named(@"good").recordID, named(@"good"), nil);
      mixed.recordWithIDWasDeletedBlock(
          [[CKRecordID alloc] initWithRecordName:@"other-type" zoneID:zone()],
          @"Other");
      mixed.recordWithIDWasDeletedBlock(
          [[CKRecordID alloc] initWithRecordName:@"removed" zoneID:zone()],
          @"SCDDCitySaveV1");
      CKServerChangeToken *token = nil;
      mixed.recordZoneFetchCompletionBlock(zone(), token, nil, NO, nil);
      mixed.fetchRecordZoneChangesCompletionBlock(nil);
      NSDictionary *c = next(t);
      CHECK([c[@"ok"] boolValue]);
      CHECK([c[@"result"][@"records"] count] == 1);
      CHECK([[c[@"result"][@"records"] firstObject][@"slot_id"]
          isEqual:@"good"]);
      CHECK([c[@"result"][@"deleted_ids"] isEqual:@[ @"removed" ]]);
    }
    [f.operations removeAllObjects];
    [t startRequest:request(@"changes",
                            @{@"token" : [NSData data], @"limit" : @256})];
    CKFetchRecordZoneChangesOperation *twice = (id)last(f);
    if (twice) {
      twice.recordWasChangedBlock(named(@"good").recordID, named(@"good"), nil);
      twice.recordWasChangedBlock(named(@"good").recordID, named(@"good"), nil);
      twice.recordZoneFetchCompletionBlock(zone(), nil, nil, NO, nil);
      twice.fetchRecordZoneChangesCompletionBlock(nil);
      CHECK([next(t)[@"code"] isEqual:@"invalid"]);
    }
    // Skipped records still count toward the 256-item page bound.
    [f.operations removeAllObjects];
    [t startRequest:request(@"changes",
                            @{@"token" : [NSData data], @"limit" : @256})];
    CKFetchRecordZoneChangesOperation *flood = (id)last(f);
    if (flood) {
      CKRecord *bad = named(@"bad");
      bad[@"commit_id"] = nil;
      for (int i = 0; i < 256; i++)
        flood.recordWasChangedBlock(bad.recordID, bad, nil);
      flood.recordWasChangedBlock(named(@"good").recordID, named(@"good"), nil);
      flood.recordZoneFetchCompletionBlock(zone(), nil, nil, NO, nil);
      flood.fetchRecordZoneChangesCompletionBlock(nil);
      CHECK([next(t)[@"code"] isEqual:@"invalid"]);
    }
    // Metadata that remote() would refuse on every device is never uploaded.
    // Control characters are one UTF-8 byte but six bytes once JSON-escaped.
    NSMutableDictionary *wide = [NSMutableDictionary new];
    NSString *escaped = [@"" stringByPaddingToLength:256
                                          withString:@"\x01"
                                     startingAtIndex:0];
    for (int i = 0; i < 64; i++)
      wide[[NSString stringWithFormat:@"key%02d", i]] = escaped;
    [f.operations removeAllObjects];
    CHECK([t startRequest:request(@"save",
                                  @{@"pending" : pending, @"metadata" : wide})]);
    NSDictionary *tooWide = next(t);
    CHECK([tooWide[@"code"] isEqual:@"invalid"]);
    CHECK(f.operations.count == 0);
    [wide removeObjectsForKeys:[wide.allKeys subarrayWithRange:NSMakeRange(0, 32)]];
    [f.operations removeAllObjects];
    CHECK([t startRequest:request(@"save",
                                  @{@"pending" : pending, @"metadata" : wide})]);
    CHECK(last(f) != nil);
    [t cancelAll];
    // An operation the factory cannot add settles its request instead of
    // stranding it or raising through the caller.
    f.submitError = error(CKErrorMissingEntitlement);
    [f.operations removeAllObjects];
    CHECK([t startRequest:request(@"fetch_record", @{@"slot_id" : @"slot"})]);
    NSDictionary *refused = next(t);
    CHECK([refused[@"code"] isEqual:@"permission"]);
    CHECK(f.operations.count == 0);
    f.submitError = nil;
    f.submitThrows = YES;
    threw = NO;
    @try {
      CHECK([t startRequest:request(@"prepare_zone", @{})]);
    } @catch (NSException *) {
      threw = YES;
    }
    CHECK(!threw);
    CHECK([next(t)[@"code"] isEqual:@"invalid"]);
    f.submitThrows = NO;
    // Entitlement values come from the signature and may have any type.
    NSString *cloud = @"iCloud.com.sierraburkhart.sincitydesertdreams";
    CHECK(SCDDCloudEntitlementsAllow(@{
      @"com.apple.developer.icloud-services" : @[ @"CloudKit" ],
      @"com.apple.developer.icloud-container-identifiers" : @[ cloud ]
    },
                                     cloud));
    for (id services in @[ @"CloudKit", @1, @{@"CloudKit" : @YES}, NSNull.null ])
      CHECK(!SCDDCloudEntitlementsAllow(@{
        @"com.apple.developer.icloud-services" : services,
        @"com.apple.developer.icloud-container-identifiers" : @[ cloud ]
      },
                                        cloud));
    CHECK(!SCDDCloudEntitlementsAllow(@{
      @"com.apple.developer.icloud-services" : @[ @"CloudKit" ],
      @"com.apple.developer.icloud-container-identifiers" : cloud
    },
                                      cloud));
    CHECK(!SCDDCloudEntitlementsAllow(@[ @"CloudKit" ], cloud));
    CHECK(!SCDDCloudEntitlementsAllow(nil, cloud));
    CHECK(!SCDDCloudEntitlementsAllow(@{}, cloud));
    // Completions stay within one adapter drain: accepted work plus queued
    // results leave room for exactly one coalesced account_changed event.
    [t cancelAll];
    NSUInteger accepted = 0;
    for (int i = 0; i < 100; i++) {
      [f.operations removeAllObjects];
      if (![t startRequest:request(@"fetch_record", @{@"slot_id" : @"slot"})])
        break;
      accepted++;
      CKFetchRecordsOperation *op = (id)last(f);
      if (op)
        op.fetchRecordsCompletionBlock(@{record().recordID : record()}, nil);
    }
    CHECK(accepted == 63);
    NSArray *full = [t drainCompletions];
    CHECK(full.count == 63);
    for (int i = 0; i < 8; i++)
      CHECK([t startRequest:request(@"fetch_record", @{@"slot_id" : @"slot"})]);
    CHECK(![t startRequest:request(@"fetch_record", @{@"slot_id" : @"slot"})]);
    for (int i = 0; i < 100; i++)
      [[NSNotificationCenter defaultCenter]
          postNotificationName:CKAccountChangedNotification
                        object:nil];
    NSArray *changed = [t drainCompletions];
    CHECK(changed.count == 1);
    CHECK([changed.firstObject[@"op"] isEqual:@"account_changed"]);
    testEpoch++;
    CHECK([t startRequest:request(@"account", @{})]);
    if (f.accountCompletion)
      f.accountCompletion(@"fourth-account", nil);
    CHECK([next(t)[@"ok"] boolValue]);
    [t cancelAll];
    [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
    printf("Results: %d passed, %d failed\n", passed, failed);
    return failed ? 1 : 0;
  }
}
