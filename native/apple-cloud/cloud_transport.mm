// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
#import "cloud_transport.h"
#import <CommonCrypto/CommonDigest.h>
#include <cmath>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
static const NSUInteger MAX_ASSET = 67108864, MAX_ARCHIVE = 1048576;
static NSString *const ZONE = @"SCDDCloudSavesV1", *const TYPE =
                                                       @"SCDDCitySaveV1";
static BOOL string(id x, NSUInteger bound, BOOL empty = NO) {
  return [x isKindOfClass:NSString.class] &&
         [x lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= bound &&
         (empty || [x length] > 0);
}
static BOOL identifier(id x) {
  return string(x, 128) &&
         [x rangeOfCharacterFromSet:[[NSCharacterSet
                                        characterSetWithCharactersInString:
                                            @"abcdefghijklmnopqrstuvwxyzABCDEFG"
                                            @"HIJKLMNOPQRSTUVWXYZ0123456789_-"]
                                        invertedSet]]
                 .location == NSNotFound;
}
static BOOL digest(id x, BOOL empty = NO) {
  return string(x, 64, empty) &&
         ((empty && [x length] == 0) ||
          ([x length] == 64 &&
           [x rangeOfCharacterFromSet:[[NSCharacterSet
                                          characterSetWithCharactersInString:
                                              @"0123456789abcdef"] invertedSet]]
                   .location == NSNotFound));
}
static BOOL boolean(id x) {
  return x && CFGetTypeID((__bridge CFTypeRef)x) == CFBooleanGetTypeID();
}
static BOOL integer(id x) {
  return [x isKindOfClass:NSNumber.class] && !boolean(x) &&
         strchr("cCsSiIlLqQ", [x objCType][0]);
}
static BOOL metadata(id x) {
  if (![x isKindOfClass:NSDictionary.class] || [x count] > 64)
    return NO;
  for (id k in x) {
    id v = x[k];
    if (!string(k, 128, YES))
      return NO;
    if ([v isKindOfClass:NSString.class]) {
      if (!string(v, 256, YES))
        return NO;
    } else if (![v isKindOfClass:NSNumber.class] ||
               !std::isfinite([v doubleValue]))
      return NO;
  }
  return YES;
}
static CKRecordZoneID *zoneID() {
  return [[CKRecordZoneID alloc] initWithZoneName:ZONE
                                        ownerName:CKCurrentUserDefaultName];
}
static BOOL sameZone(CKRecordID *r) {
  return [r.zoneID isEqual:zoneID()] && identifier(r.recordName);
}
static NSArray *keys() {
  return @[
    @"commit_id", @"continuation_sha256", @"manual_sha256", @"tombstone",
    @"metadata"
  ];
}
static NSString *hex(const unsigned char *d) {
  NSMutableString *s = [NSMutableString new];
  for (int i = 0; i < 32; i++)
    [s appendFormat:@"%02x", d[i]];
  return s;
}
static NSString *hash(NSData *d) {
  unsigned char bytes[32];
  CC_SHA256(d.bytes, (CC_LONG)d.length, bytes);
  return hex(bytes);
}
static NSData *archiveRecord(CKRecord *record) {
  @try {
    NSKeyedArchiver *a =
        [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
    [record encodeSystemFieldsWithCoder:a];
    [a finishEncoding];
    return a.encodedData.length <= MAX_ARCHIVE ? a.encodedData : nil;
  } @catch (NSException *) {
    return nil;
  }
}
static CKRecord *decodeRecord(NSData *data) {
  if (![data isKindOfClass:NSData.class] || !data.length ||
      data.length > MAX_ARCHIVE)
    return nil;
  @try {
    NSKeyedUnarchiver *u =
        [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:nil];
    u.requiresSecureCoding = YES;
    u.decodingFailurePolicy = NSDecodingFailurePolicySetErrorAndReturn;
    CKRecord *r = [[CKRecord alloc] initWithCoder:u];
    [u finishDecoding];
    return u.error ? nil : r;
  } @catch (NSException *) {
    return nil;
  }
}
static NSDictionary *remote(CKRecord *r) {
  if (![r isKindOfClass:CKRecord.class] || ![r.recordType isEqual:TYPE] ||
      !sameZone(r.recordID) || !identifier(r[@"commit_id"]) ||
      ![r[@"tombstone"] isKindOfClass:NSNumber.class] ||
      !digest(r[@"continuation_sha256"], [r[@"tombstone"] boolValue]) ||
      !digest(r[@"manual_sha256"], YES) ||
      !string(r.recordChangeTag ?: @"", 128, YES))
    return nil;
  NSData *data = r[@"metadata"];
  if (![data isKindOfClass:NSData.class] || data.length > 65536)
    return nil;
  NSDictionary *m = [NSJSONSerialization JSONObjectWithData:data
                                                    options:0
                                                      error:nil];
  NSData *fields = archiveRecord(r);
  if (!metadata(m) || !fields)
    return nil;
  return @{
    @"slot_id" : r.recordID.recordName,
    @"commit_id" : r[@"commit_id"],
    @"change_tag" : r.recordChangeTag ?: @"",
    @"system_fields" : fields,
    @"continuation_sha256" : r[@"continuation_sha256"],
    @"manual_sha256" : r[@"manual_sha256"],
    @"tombstone" : @([r[@"tombstone"] boolValue]),
    @"metadata" : m
  };
}
static NSError *invalid() {
  return [NSError errorWithDomain:@"SCDDCloud" code:1 userInfo:nil];
}
// A single-item operation's partial failure has exactly one meaningful leaf.
static NSError *leaf(NSError *e) {
  for (int i = 0; i < 8 && [e.domain isEqual:CKErrorDomain] &&
                  e.code == CKErrorPartialFailure;
       i++) {
    NSDictionary *items = e.userInfo[CKPartialErrorsByItemIDKey];
    if (![items isKindOfClass:NSDictionary.class] || items.count != 1)
      break;
    id child = items.allValues.firstObject;
    if (![child isKindOfClass:NSError.class])
      break;
    e = child;
  }
  return e;
}
static NSString *code(NSError *e) {
  e = leaf(e);
  if (![e.domain isEqual:CKErrorDomain])
    return [e.domain isEqual:@"SCDDCloud"] ? @"invalid" : @"transient";
  switch (e.code) {
  case CKErrorNotAuthenticated:
    return @"signed_out";
  case CKErrorPermissionFailure:
  case CKErrorMissingEntitlement:
    return @"permission";
  case CKErrorQuotaExceeded:
    return @"quota";
  case CKErrorServerRecordChanged:
    return @"conflict";
  case CKErrorChangeTokenExpired:
    return @"token_expired";
  case CKErrorOperationCancelled:
    return @"cancelled";
  case CKErrorInvalidArguments:
  case CKErrorBadContainer:
  case CKErrorBadDatabase:
    return @"invalid";
  case CKErrorAccountTemporarilyUnavailable:
    return @"unavailable";
  default:
    return @"transient";
  }
}
static NSNumber *retry(NSError *e) {
  double seconds = [e.userInfo[CKErrorRetryAfterKey] doubleValue];
  double child = [leaf(e).userInfo[CKErrorRetryAfterKey] doubleValue];
  seconds = fmax(seconds, child);
  if (!std::isfinite(seconds) || seconds <= 0)
    return @0;
  if (seconds >= (double)LLONG_MAX / 1000.0)
    return @(LLONG_MAX);
  return @((long long)ceil(seconds * 1000));
}
// Open and bound the source before reading. A unique private destination is
// never returned until its bytes and hash match. Uploads use the same immutable
// copy.
static NSString *copyAsset(NSString *path, NSString *directory,
                           NSString *expected, NSNumber *size) {
  if (!string(path, 4096) || !digest(expected))
    return nil;
  int input =
      open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (input < 0)
    return nil;
  struct stat st;
  if (fstat(input, &st) || !S_ISREG(st.st_mode) || st.st_size <= 0 ||
      st.st_size > MAX_ASSET || (size && st.st_size != size.longLongValue)) {
    close(input);
    return nil;
  }
  NSString *target = [directory
      stringByAppendingPathComponent:[NSUUID.UUID.UUIDString
                                         stringByAppendingString:@".sc2d"]];
  int output = open(target.fileSystemRepresentation,
                    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (output < 0) {
    close(input);
    return nil;
  }
  CC_SHA256_CTX ctx;
  CC_SHA256_Init(&ctx);
  char buffer[65536];
  off_t total = 0;
  BOOL ok = YES;
  while (YES) {
    ssize_t n = read(input, buffer, sizeof(buffer));
    if (n < 0) {
      ok = NO;
      break;
    }
    if (!n)
      break;
    total += n;
    if (total > st.st_size || total > MAX_ASSET) {
      ok = NO;
      break;
    }
    CC_SHA256_Update(&ctx, buffer, (CC_LONG)n);
    ssize_t written = 0;
    while (written < n) {
      ssize_t m = write(output, buffer + written, n - written);
      if (m <= 0) {
        ok = NO;
        break;
      }
      written += m;
    }
    if (!ok)
      break;
  }
  unsigned char d[32];
  CC_SHA256_Final(d, &ctx);
  close(input);
  if (close(output))
    ok = NO;
  if (!ok || total != st.st_size || ![hex(d) isEqual:expected]) {
    unlink(target.fileSystemRepresentation);
    return nil;
  }
  return target;
}
@interface SCDDCloudTransport ()
@property id<SCDDCloudOperationFactory> factory;
@property NSString *container;
@property NSString *directory;
@property NSMutableDictionary<NSString *, NSDictionary *> *requests;
@property NSMutableDictionary<NSString *, CKDatabaseOperation *> *operations;
@property NSMutableArray<NSDictionary *> *queue;
@property NSMutableArray<NSString *> *retiredFiles;
@property NSMutableDictionary<NSString *, NSMutableArray<NSString *> *>
    *requestFiles;
@property NSUInteger generation;
@property long long epoch;
@property BOOL requiresAccount;
@property long long invalidatedEpoch;
@property id observer;
@end
@implementation SCDDCloudTransport
- (instancetype)initWithFactory:(id<SCDDCloudOperationFactory>)factory
                      container:(NSString *)container
                    stagingRoot:(NSString *)root {
  if (!(self = [super init]))
    return nil;
  _factory = factory;
  _container = [container copy];
  _requests = [NSMutableDictionary new];
  _operations = [NSMutableDictionary new];
  _queue = [NSMutableArray new];
  _retiredFiles = [NSMutableArray new];
  _requestFiles = [NSMutableDictionary new];
  // Reject symlinked roots/ancestors; own only a newly generated child
  // directory.
  if (!root.isAbsolutePath || ![root.stringByStandardizingPath
                                  isEqual:root.stringByResolvingSymlinksInPath])
    return nil;
  if (![[NSFileManager defaultManager]
                createDirectoryAtPath:root
          withIntermediateDirectories:YES
                           attributes:@{NSFilePosixPermissions : @0700}
                                error:nil])
    return nil;
  _directory = [root stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  if (mkdir(_directory.fileSystemRepresentation, 0700))
    return nil;
  __weak SCDDCloudTransport *weak = self;
  _observer = [[NSNotificationCenter defaultCenter]
      addObserverForName:CKAccountChangedNotification
                  object:nil
                   queue:nil
              usingBlock:^(NSNotification *) {
                SCDDCloudTransport *s = weak;
                if (!s)
                  return;
                @synchronized(s) {
                  [s cancelAll];
                  s.requiresAccount = YES;
                  s.invalidatedEpoch = s.epoch;
                  [s.queue addObject:@{
                    @"id" : @"",
                    @"epoch" : @(s.epoch),
                    @"op" : @"account_changed",
                    @"ok" : @YES,
                    @"code" : @"",
                    @"result" : @{},
                    @"retry_after_ms" : @0
                  }];
                }
              }];
  return self;
}
- (void)dealloc {
  if (_observer)
    [[NSNotificationCenter defaultCenter] removeObserver:_observer];
  for (CKDatabaseOperation *o in _operations.allValues)
    [o cancel];
  if (_directory)
    [[NSFileManager defaultManager] removeItemAtPath:_directory error:nil];
}
- (void)cancelAll {
  @synchronized(self) {
    _generation++;
    [_factory cancelAccountRequests];
    for (CKDatabaseOperation *o in _operations.allValues)
      [o cancel];
    [_operations removeAllObjects];
    [_requests removeAllObjects];
    for (NSDictionary *c in _queue)
      for (NSString *path in [c[@"result"][@"downloaded"] allValues])
        unlink(path.fileSystemRepresentation);
    [_queue removeAllObjects];
    for (NSString *p in _retiredFiles)
      unlink(p.fileSystemRepresentation);
    [_retiredFiles removeAllObjects];
    for (NSArray *files in _requestFiles.allValues)
      for (NSString *p in files)
        unlink(p.fileSystemRepresentation);
    [_requestFiles removeAllObjects];
  }
}
- (NSArray *)drainCompletions {
  @synchronized(self) {
    for (NSString *p in _retiredFiles)
      unlink(p.fileSystemRepresentation);
    [_retiredFiles removeAllObjects];
    NSArray *result = [_queue copy];
    [_queue removeAllObjects];
    for (NSDictionary *c in result) {
      NSDictionary *paths = c[@"result"][@"downloaded"];
      if ([paths isKindOfClass:NSDictionary.class])
        [_retiredFiles addObjectsFromArray:paths.allValues];
    }
    return result;
  }
}
- (BOOL)active:(NSDictionary *)r generation:(NSUInteger)g {
  return g == _generation && _requests[r[@"id"]] != nil;
}
- (void)finish:(NSDictionary *)r
    generation:(NSUInteger)g
        result:(NSDictionary *)result
         error:(NSError *)error {
  [self finish:r generation:g result:result error:error retryAfter:@0];
}
- (void)finish:(NSDictionary *)r
    generation:(NSUInteger)g
        result:(NSDictionary *)result
         error:(NSError *)error
    retryAfter:(NSNumber *)retryAfter {
  @synchronized(self) {
    if (![self active:r generation:g])
      return;
    if (!error && [r[@"op"] isEqual:@"account"])
      _requiresAccount = NO;
    NSString *c = error ? code(error) : @"";
    if ([c isEqual:@"conflict"]) {
      NSDictionary *fresh =
          remote(leaf(error).userInfo[CKRecordChangedErrorServerRecordKey]);
      if (fresh) {
        result = @{@"remote" : fresh};
      } else {
        // Every accepted request must deliver a schema-valid terminal result.
        // Never strand the adapter's lane with an unrepresentable conflict.
        c = @"invalid";
        result = @{};
      }
    }
    [_queue addObject:@{
      @"id" : r[@"id"],
      @"epoch" : r[@"epoch"],
      @"op" : r[@"op"],
      @"ok" : @(!error),
      @"code" : c,
      @"result" : result ?: @{},
      @"retry_after_ms" :
          @(MAX(retry(error).longLongValue, retryAfter.longLongValue))
    }];
    for (NSString *p in _requestFiles[r[@"id"]]) {
      if (![result[@"downloaded"] allValues] ||
          ![[result[@"downloaded"] allValues] containsObject:p])
        unlink(p.fileSystemRepresentation);
    }
    [_requestFiles removeObjectForKey:r[@"id"]];
    [_requests removeObjectForKey:r[@"id"]];
    [_operations removeObjectForKey:r[@"id"]];
  }
}
- (void)submit:(CKDatabaseOperation *)operation
       request:(NSDictionary *)r
    generation:(NSUInteger)g {
  @synchronized(self) {
    if (![self active:r generation:g]) {
      [operation cancel];
      return;
    }
    _operations[r[@"id"]] = operation;
    operation.configuration.qualityOfService = NSQualityOfServiceUtility;
    [_factory submit:operation];
  }
}
- (BOOL)startRequest:(NSDictionary *)incoming {
  if (![incoming isKindOfClass:NSDictionary.class] ||
      !identifier(incoming[@"id"]) || !integer(incoming[@"epoch"]) ||
      [incoming[@"epoch"] longLongValue] < 0 ||
      ![incoming[@"args"] isKindOfClass:NSDictionary.class] || ![@[
        @"account", @"prepare_zone", @"changes", @"fetch_record", @"download",
        @"save"
      ] containsObject:incoming[@"op"]])
    return NO;
  NSDictionary *r = CFBridgingRelease(CFPropertyListCreateDeepCopy(
      kCFAllocatorDefault, (__bridge CFPropertyListRef)incoming,
      kCFPropertyListImmutable));
  if (!r)
    return NO;
  NSDictionary *a = r[@"args"];
  NSString *op = r[@"op"];
  NSUInteger g;
  @synchronized(self) {
    if (_requiresAccount && (![op isEqual:@"account"] ||
                             [r[@"epoch"] longLongValue] <= _invalidatedEpoch))
      return NO;
    if (_requests.count >= 8 || _queue.count >= 64 || _requests[r[@"id"]] ||
        [r[@"epoch"] longLongValue] < _epoch)
      return NO;
    if ([r[@"epoch"] longLongValue] > _epoch) {
      [self cancelAll];
      _epoch = [r[@"epoch"] longLongValue];
    }
    g = _generation;
    _requests[r[@"id"]] = r;
    _requestFiles[r[@"id"]] = [NSMutableArray new];
  }
  __weak SCDDCloudTransport *weak = self;
  if ([op isEqual:@"account"]) {
    @synchronized(self) {
      if (![self active:r generation:g])
        return YES;
      [_factory account:^(NSString *identity, NSError *e) {
        SCDDCloudTransport *s = weak;
        if (!s)
          return;
        NSString *owner =
            string(identity, 4096)
                ? hash([[NSString
                      stringWithFormat:@"%@\n%@", s.container, identity]
                      dataUsingEncoding:NSUTF8StringEncoding])
                : nil;
        [s finish:r
            generation:g
                result:owner ? @{@"owner" : owner} : @{}
                 error:e
                           ?: (!owner
                                   ? [NSError
                                         errorWithDomain:CKErrorDomain
                                                    code:CKErrorNotAuthenticated
                                                userInfo:nil]
                                   : nil)];
      }];
    }
  } else if ([op isEqual:@"prepare_zone"]) {
    CKModifyRecordZonesOperation *o =
        (id)[_factory operation:CKModifyRecordZonesOperation.class];
    o.recordZonesToSave = @[ [[CKRecordZone alloc] initWithZoneID:zoneID()] ];
    o.modifyRecordZonesCompletionBlock =
        ^(NSArray *saved, NSArray *deleted, NSError *e) {
          BOOL found = NO;
          for (CKRecordZone *z in saved)
            if ([z.zoneID isEqual:zoneID()])
              found = YES;
          [weak finish:r
              generation:g
                  result:@{}
                   error:e ?: (!found ? invalid() : nil)];
        };
    [self submit:o request:r generation:g];
  } else if ([op isEqual:@"changes"]) {
    [self changes:r generation:g];
  } else if ([op isEqual:@"fetch_record"] || [op isEqual:@"download"]) {
    [self fetch:r generation:g];
  } else { // File validation and immutable upload copies must not block the
           // frame.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
      SCDDCloudTransport *s = weak;
      if (s)
        [s save:r generation:g];
    });
  }
  return YES;
}
- (void)changes:(NSDictionary *)r generation:(NSUInteger)g {
  NSDictionary *a = r[@"args"];
  NSData *data = a[@"token"];
  if (![data isKindOfClass:NSData.class] || data.length > MAX_ARCHIVE ||
      !integer(a[@"limit"]) || [a[@"limit"] integerValue] != 256) {
    [self finish:r generation:g result:nil error:invalid()];
    return;
  }
  CKServerChangeToken *token = nil;
  @try {
    if (data.length)
      token =
          [NSKeyedUnarchiver unarchivedObjectOfClass:CKServerChangeToken.class
                                            fromData:data
                                               error:nil];
  } @catch (NSException *) {
  }
  if (data.length && !token) {
    [self finish:r generation:g result:nil error:invalid()];
    return;
  }
  CKFetchRecordZoneChangesConfiguration *config =
      [CKFetchRecordZoneChangesConfiguration new];
  config.previousServerChangeToken = token;
  config.resultsLimit = 256;
  config.desiredKeys = keys();
  CKFetchRecordZoneChangesOperation *o =
      (id)[_factory operation:CKFetchRecordZoneChangesOperation.class];
  o.recordZoneIDs = @[ zoneID() ];
  o.configurationsByRecordZoneID = @{zoneID() : config};
  o.fetchAllChanges = NO;
  NSMutableArray *records = [NSMutableArray new],
                 *deleted = [NSMutableArray new];
  NSMutableSet *ids = [NSMutableSet new];
  __block NSError *pageError = nil;
  __block long long pageRetryAfter = 0;
  __block NSData *nextToken = [NSData data];
  __block BOOL more = NO, zoneFinished = NO;
  NSObject *pageLock = [NSObject new];
  __weak SCDDCloudTransport *weak = self;
  o.recordWasChangedBlock = ^(CKRecordID *rid, CKRecord *record, NSError *e) {
    @synchronized(pageLock) {
      pageRetryAfter = MAX(pageRetryAfter, retry(e).longLongValue);
      NSDictionary *value = remote(record);
      if (e || !value || ![rid isEqual:record.recordID] ||
          [ids containsObject:rid.recordName] || ids.count >= 256) {
        pageError = e ?: invalid();
        return;
      }
      [ids addObject:rid.recordName];
      [records addObject:value];
    }
  };
  o.recordWithIDWasDeletedBlock = ^(CKRecordID *rid, NSString *type) {
    @synchronized(pageLock) {
      if (!sameZone(rid) || ![type isEqual:TYPE] ||
          [ids containsObject:rid.recordName] || ids.count >= 256) {
        pageError = invalid();
        return;
      }
      [ids addObject:rid.recordName];
      [deleted addObject:rid.recordName];
    }
  };
  o.recordZoneFetchCompletionBlock =
      ^(CKRecordZoneID *z, CKServerChangeToken *t, NSData *client,
        BOOL moreComing, NSError *e) {
        @synchronized(pageLock) {
          zoneFinished = YES;
          pageRetryAfter = MAX(pageRetryAfter, retry(e).longLongValue);
          more = moreComing;
          if (e)
            pageError = e;
          if (![z isEqual:zoneID()])
            pageError = invalid();
          if (t) {
            @try {
              nextToken = [NSKeyedArchiver archivedDataWithRootObject:t
                                                requiringSecureCoding:YES
                                                                error:nil];
            } @catch (NSException *) {
              nextToken = nil;
            }
            if (!nextToken || nextToken.length > MAX_ARCHIVE)
              pageError = invalid();
          }
        }
      };
  o.fetchRecordZoneChangesCompletionBlock = ^(NSError *e) {
    @synchronized(pageLock) {
      [weak finish:r generation:g result:@{@"records":[records copy],@"deleted_ids":[deleted copy],@"token":nextToken?:[NSData data],@"more":@(more)} error:pageError?:e?:(!zoneFinished?invalid():nil) retryAfter:@(MAX(pageRetryAfter, retry(e).longLongValue))];
    }
  };
  [self submit:o request:r generation:g];
}
- (void)fetch:(NSDictionary *)r generation:(NSUInteger)g {
  BOOL download = [r[@"op"] isEqual:@"download"];
  NSDictionary *a = r[@"args"], *expected = download ? a[@"remote"] : nil;
  if (download && ![expected isKindOfClass:NSDictionary.class]) {
    [self finish:r generation:g result:nil error:invalid()];
    return;
  }
  NSString *slot = download ? expected[@"slot_id"] : a[@"slot_id"];
  if (!identifier(slot) ||
      (download && (![expected isKindOfClass:NSDictionary.class] ||
                    !integer(a[@"max_bytes"]) ||
                    [a[@"max_bytes"] unsignedLongLongValue] != MAX_ASSET))) {
    [self finish:r generation:g result:nil error:invalid()];
    return;
  }
  CKRecordID *rid = [[CKRecordID alloc] initWithRecordName:slot
                                                    zoneID:zoneID()];
  CKFetchRecordsOperation *o =
      (id)[_factory operation:CKFetchRecordsOperation.class];
  o.recordIDs = @[ rid ];
  o.desiredKeys =
      download
          ? [keys()
                arrayByAddingObjectsFromArray:@[ @"continuation", @"manual" ]]
          : keys();
  __block NSError *itemError = nil;
  __block CKRecord *fetched = nil;
  __block NSDictionary *downloadResult = nil;
  NSObject *itemLock = [NSObject new];
  __weak SCDDCloudTransport *weak = self;
  o.perRecordCompletionBlock =
      ^(CKRecord *record, CKRecordID *recordID, NSError *e) {
        @synchronized(itemLock) {
          itemError = e;
          fetched = record;
          if (![recordID isEqual:rid]) {
            itemError = invalid();
            return;
          }
          if (download && record && !e) {
            SCDDCloudTransport *s = weak;
            if (s)
              downloadResult = [s copyDownload:record
                                      expected:expected
                                       request:r
                                    generation:g
                                         error:&itemError];
          }
        }
      };
  o.fetchRecordsCompletionBlock = ^(NSDictionary *records, NSError *e) {
    @synchronized(itemLock) {
      NSError *failure = itemError ?: e;
      NSNumber *retryAfter =
          @(MAX(retry(itemError).longLongValue, retry(e).longLongValue));
      CKRecord *record = fetched ?: records[rid];
      if (failure && [leaf(failure).domain isEqual:CKErrorDomain] &&
          leaf(failure).code == CKErrorUnknownItem && !download) {
        [weak finish:r generation:g result:@{@"remote" : @{}} error:nil];
        return;
      }
      if (download) { // CKAsset files must already have been copied in the
                      // per-record callback.
        [weak finish:r
            generation:g
                result:downloadResult
                 error:failure
                           ?: (!downloadResult ? invalid() : nil)retryAfter
                      :retryAfter];
        return;
      }
      NSDictionary *value = remote(record);
      [weak finish:r
          generation:g
              result:value ? @{@"remote" : value} : nil
               error:failure
                         ?: (!value ? invalid() : nil)retryAfter:retryAfter];
    }
  };
  [self submit:o request:r generation:g];
}
- (NSDictionary *)copyDownload:(CKRecord *)record
                      expected:(NSDictionary *)expected
                       request:(NSDictionary *)r
                    generation:(NSUInteger)g
                         error:(NSError **)error {
  NSDictionary *actual = remote(record);
  if (!actual) {
    *error = invalid();
    return nil;
  }
  for (NSString *k in @[
         @"slot_id", @"commit_id", @"change_tag", @"continuation_sha256",
         @"manual_sha256", @"tombstone"
       ]) {
    if (![actual[k] isEqual:expected[k]]) {
      *error = [NSError
          errorWithDomain:CKErrorDomain
                     code:CKErrorServerRecordChanged
                 userInfo:@{CKRecordChangedErrorServerRecordKey : record}];
      return nil;
    }
  }
  NSMutableDictionary *paths = [NSMutableDictionary new];
  for (NSString *k in @[ @"continuation", @"manual" ]) {
    NSString *sha = actual[[k stringByAppendingString:@"_sha256"]];
    if (!sha.length)
      continue;
    CKAsset *asset = record[k];
    if (![asset isKindOfClass:CKAsset.class]) {
      *error = invalid();
      return nil;
    }
    NSString *path = copyAsset(asset.fileURL.path, _directory, sha, nil);
    if (!path) {
      *error = invalid();
      return nil;
    }
    @synchronized(self) {
      if (![self active:r generation:g]) {
        unlink(path.fileSystemRepresentation);
        *error = [NSError errorWithDomain:CKErrorDomain
                                     code:CKErrorOperationCancelled
                                 userInfo:nil];
        return nil;
      }
      [_requestFiles[r[@"id"]] addObject:path];
    }
    paths[k] = path;
  }
  return @{@"downloaded" : paths};
}
- (void)save:(NSDictionary *)r generation:(NSUInteger)g {
  @synchronized(self) {
    if (![self active:r generation:g])
      return;
  }
  NSDictionary *p = r[@"args"][@"pending"], *m = r[@"args"][@"metadata"];
  if (![p isKindOfClass:NSDictionary.class] || !identifier(p[@"slot_id"]) ||
      !identifier(p[@"commit_id"]) || !boolean(p[@"tombstone"]) ||
      !metadata(m) || ![p[@"baseline"] isKindOfClass:NSData.class] ||
      [p[@"baseline"] length] > MAX_ARCHIVE ||
      !string(p[@"baseline_tag"], 128, YES) ||
      ![p[@"manual"] isKindOfClass:NSDictionary.class]) {
    [self finish:r generation:g result:nil error:invalid()];
    return;
  }
  NSData *baseline = p[@"baseline"];
  CKRecord *record =
      baseline.length
          ? decodeRecord(baseline)
          : [[CKRecord alloc]
                initWithRecordType:TYPE
                          recordID:[[CKRecordID alloc]
                                       initWithRecordName:p[@"slot_id"]
                                                   zoneID:zoneID()]];
  if (!record || !sameZone(record.recordID) ||
      ![record.recordID.recordName isEqual:p[@"slot_id"]] ||
      ![record.recordType isEqual:TYPE] ||
      ![(record.recordChangeTag ?: @"") isEqual:p[@"baseline_tag"]]) {
    [self finish:r generation:g result:nil error:invalid()];
    return;
  }
  record[@"commit_id"] = p[@"commit_id"];
  record[@"tombstone"] = p[@"tombstone"];
  record[@"metadata"] = [NSJSONSerialization dataWithJSONObject:m
                                                        options:0
                                                          error:nil];
  for (NSString *key in @[ @"continuation", @"manual" ]) {
    NSDictionary *payload = p[key];
    BOOL absent =
        ([key isEqual:@"continuation"] && [p[@"tombstone"] boolValue]) ||
        ([key isEqual:@"manual"] &&
         [payload isKindOfClass:NSDictionary.class] && payload.count == 0);
    NSString *shaKey = [key stringByAppendingString:@"_sha256"];
    if (absent) {
      record[key] = nil;
      record[shaKey] = @"";
      continue;
    }
    if (![payload isKindOfClass:NSDictionary.class] ||
        !integer(payload[@"bytes"]) || [payload[@"bytes"] longLongValue] <= 0 ||
        [payload[@"bytes"] unsignedLongLongValue] > MAX_ASSET) {
      [self finish:r generation:g result:nil error:invalid()];
      return;
    }
    NSString *copy = copyAsset(payload[@"path"], _directory, payload[@"sha256"],
                               payload[@"bytes"]);
    if (!copy) {
      [self finish:r generation:g result:nil error:invalid()];
      return;
    }
    @synchronized(self) {
      if (![self active:r generation:g]) {
        unlink(copy.fileSystemRepresentation);
        return;
      }
      [_requestFiles[r[@"id"]] addObject:copy];
    }
    record[key] =
        [[CKAsset alloc] initWithFileURL:[NSURL fileURLWithPath:copy]];
    record[shaKey] = payload[@"sha256"];
  }
  CKModifyRecordsOperation *o =
      (id)[_factory operation:CKModifyRecordsOperation.class];
  o.recordsToSave = @[ record ];
  o.savePolicy = CKRecordSaveIfServerRecordUnchanged;
  o.atomic = YES;
  __weak SCDDCloudTransport *weak = self;
  o.modifyRecordsCompletionBlock =
      ^(NSArray *saved, NSArray *deleted, NSError *e) {
        CKRecord *ack = saved.count == 1 ? saved.firstObject : nil;
        NSDictionary *value = remote(ack);
        BOOL valid = value && [value[@"slot_id"] isEqual:p[@"slot_id"]] &&
                     [value[@"commit_id"] isEqual:p[@"commit_id"]];
        [weak finish:r
            generation:g
                result:valid ? @{
                  @"commit_id" : value[@"commit_id"],
                  @"change_tag" : value[@"change_tag"],
                  @"system_fields" : value[@"system_fields"]
                }
                             : nil
                 error:e ?: (!valid ? invalid() : nil)];
      };
  [self submit:o request:r generation:g];
}
@end

#import <TargetConditionals.h>
#if !TARGET_OS_IPHONE
#import <Security/Security.h>
#endif
BOOL SCDDCloudConfigurationAllows(NSDictionary *info, NSString *container) {
  return [container isEqual:@"iCloud.com.sierraburkhart.sincitydesertdreams"] &&
         boolean(info[@"SCDDCloudKitEnabled"]) &&
         [info[@"SCDDCloudKitEnabled"] boolValue] &&
         [info[@"SCDDCloudKitContainer"] isEqual:container];
}
BOOL SCDDCloudRuntimeConfigured(NSString *container) {
  if (!SCDDCloudConfigurationAllows(NSBundle.mainBundle.infoDictionary,
                                    container))
    return NO;
#if TARGET_OS_SIMULATOR
  return NO;
#elif TARGET_OS_IPHONE
  // iOS device execution requires OS-enforced code signing. The exporter must
  // verify CloudKit entitlements before sealing these explicit bundle flags.
  return YES;
#else
  SecCodeRef codeRef = nullptr;
  CFDictionaryRef infoRef = nullptr;
  if (SecCodeCopySelf(kSecCSDefaultFlags, &codeRef) != errSecSuccess)
    return NO;
  OSStatus valid = SecCodeCheckValidity(codeRef, kSecCSStrictValidate, nullptr);
  OSStatus status = SecCodeCopySigningInformation(
      codeRef, kSecCSSigningInformation, &infoRef);
  CFRelease(codeRef);
  if (status != errSecSuccess || !infoRef)
    return NO;
  NSDictionary *info = CFBridgingRelease(infoRef);
  NSDictionary *entitlements =
      info[(__bridge NSString *)kSecCodeInfoEntitlementsDict];
  NSNumber *flags = info[(__bridge NSString *)kSecCodeInfoFlags];
  return valid == errSecSuccess && flags &&
         !(flags.unsignedIntValue & kSecCodeSignatureAdhoc) &&
         [entitlements[@"com.apple.developer.icloud-services"]
             containsObject:@"CloudKit"] &&
         [entitlements[@"com.apple.developer.icloud-container-identifiers"]
             containsObject:container];
#endif
}
#ifndef SCDD_CLOUD_TEST_ONLY
@interface SCDDRealCloudFactory : NSObject <SCDDCloudOperationFactory>
@property NSString *identifier;
@property CKContainer *container;
@property NSUInteger accountGeneration;
@end
@implementation SCDDRealCloudFactory
- (CKContainer *)activeContainer {
  @synchronized(self) {
    if (!_container)
      _container = [CKContainer containerWithIdentifier:_identifier];
    return _container;
  }
}
- (CKDatabaseOperation *)operation:(Class)kind {
  return [kind new];
}
- (void)submit:(CKDatabaseOperation *)operation {
  [[self activeContainer].privateCloudDatabase addOperation:operation];
}
- (void)cancelAccountRequests {
  @synchronized(self) {
    _accountGeneration++;
  }
}
- (void)account:(void (^)(NSString *, NSError *))completion {
  NSUInteger generation;
  @synchronized(self) {
    generation = _accountGeneration;
  }
  CKContainer *container = [self activeContainer];
  [container accountStatusWithCompletionHandler:^(CKAccountStatus status,
                                                  NSError *error) {
    @synchronized(self) {
      if (generation != self.accountGeneration)
        return;
    }
    if (error) {
      completion(nil, error);
      return;
    }
    if (status != CKAccountStatusAvailable) {
      NSInteger code = status == CKAccountStatusNoAccount
                           ? CKErrorNotAuthenticated
                           : (status == CKAccountStatusRestricted
                                  ? CKErrorPermissionFailure
                                  : CKErrorAccountTemporarilyUnavailable);
      completion(nil, [NSError errorWithDomain:CKErrorDomain
                                          code:code
                                      userInfo:nil]);
      return;
    }
    @synchronized(self) {
      if (generation != self.accountGeneration)
        return;
      [container fetchUserRecordIDWithCompletionHandler:^(CKRecordID *recordID,
                                                          NSError *e) {
        @synchronized(self) {
          if (generation != self.accountGeneration)
            return;
        }
        completion(recordID.recordName, e);
      }];
    }
  }];
}
@end
id<SCDDCloudOperationFactory> SCDDCreateRealFactory(NSString *container) {
  if (!SCDDCloudRuntimeConfigured(container))
    return nil;
  SCDDRealCloudFactory *factory = [SCDDRealCloudFactory new];
  factory.identifier = container;
  return factory;
}
#endif
