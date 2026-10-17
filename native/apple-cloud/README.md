# Apple private CloudKit save transport

The original `SCDDAppleCloud` GDExtension supplies asynchronous transport for the
cloud-save coordinator. It uses only the private database, custom zone
`SCDDCloudSavesV1` and record type `SCDDCitySaveV1`. It has no Game Center,
analytics, public database, publisher server, UI or portable-save-format role.

## Build and offline verification

Requires Xcode with macOS/iPhoneOS SDKs, SCons, and official godot-cpp revision
`e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77` (Godot 4.5 stable compatible bindings).
Use a dedicated checkout because SCons writes generated bindings and objects.

```
python3 native/apple-cloud/build.py --test-only
python3 native/apple-cloud/build.py --godot-cpp "$SCDD_GODOT_CPP" --scons "$SCDD_SCONS"
python3 tools/run_tests.py test_apple_cloud_platform.gd 'test_cloud_save_*.gd'
```

`--test-only` builds and runs the same injected-operation harness under arm64 and
x86_64. The real factory is excluded at compile time: no CKContainer is created
and no account or network request is sent. Tests configure real CK operation
objects and invoke their callbacks through the fake operation factory. A clean
run prints `Results: N passed, 0 failed` for each architecture. Rosetta is needed
to execute x86_64 on Apple Silicon. Actual opaque server tokens and change tags,
server authorization, network cancellation and signed-device behavior still
require the separately authorized device checks.

Normal builds produce `game/addons/apple_cloud/bin/libSCDDAppleCloud.dylib`
(universal macOS, minimum 12.0) and `SCDDAppleCloud.framework` (arm64 iOS,
minimum 17.0). They are not developer-signed or exported application packages.
The build maps product and godot-cpp paths out of source/debug references and
copies the binding license beside the source and installed binaries.

## Enabling and signing contract

Default is disabled. The adapter explicitly loads `apple_cloud.cfg` only on a
configured macOS/iOS runtime. Editor-feature executables, editor mode, headless
execution and other platforms return unavailable before requesting any account.
The extension independently checks these same runtime gates.

Both Godot settings must be configured:

- `apple_cloud/enabled = true`
- `apple_cloud/container_id = "iCloud.com.sierraburkhart.sincitydesertdreams"`

Both **main application bundle** Info.plist fields must also be sealed by the
validated signing/export process:

- `SCDDCloudKitEnabled`: Boolean `true` (a string or number is not accepted).
- `SCDDCloudKitContainer`: the same exact proposed container identifier.

macOS additionally checks its executable's signature with public Security APIs,
rejects ad-hoc signatures, and requires the CloudKit service and matching
container entitlements. iOS simulator execution is disabled. On physical iOS,
mandatory OS code signing plus the sealed explicit bundle flags provide the
runtime gate; public iOS APIs do not inspect the application's CloudKit signing
entitlements. The exporter/release checker must verify the signed application's
actual CloudKit entitlements, environment, container registration, provisioning
and Production schema before setting those flags. No provisioning-profile
parsing, receipt heuristic or private Security API is used.

`configure(container_id, staging_root) -> Error` requires a generated staging
location below Godot's user-data directory. It checks configuration and creates
only the lazy factory and an owned staging directory; it does not instantiate
CKContainer or query an account. The first accepted request uses the factory.

## Boundary and record schema

Public methods are `available() -> bool`, `start_request(Dictionary) -> Error`,
`drain_completions() -> Array`, `cancel_all()`, and `configure(String, String)`.
Requests are `{id, epoch, op, args}`; completions echo `{id, epoch, op}` and add
`{ok, code, result, retry_after_ms}`. Supported operations are `account`,
`prepare_zone`, `changes`, `fetch_record`, `download`, and `save`. The coordinator
owns scheduling, account namespaces, retries, reconciliation and publication.
All dictionary keys crossing Godot are Strings.

A record's name is its slot ID. Fields are `commit_id`, `continuation_sha256`,
`manual_sha256`, `tombstone`, `metadata` (bounded JSON Data), `continuation` and
`manual` (CKAssets when present). Metadata accepts at most 64 bounded scalar
entries, with finite numbers. System-field archives and change-token archives
are opaque secure archives, each bounded to 1 MiB. Inventory/fetch desired keys
exclude both assets. Change inventory uses one explicit page of at most 256
records/deletions and returns the opaque cursor and `more` flag. A record that
arrives but fails validation (wrong type, missing or oversized fields) is
skipped rather than failing the page, so one bad record cannot stop every
device's inventory; skipped items still count toward the 256-item bound. A
CloudKit error for any item still fails the whole page and keeps the cursor.

A save decodes the actual baseline's system fields, checks its slot, zone, type
and change tag, and uses `CKRecordSaveIfServerRecordUnchanged`. New slots have no
baseline. Metadata whose JSON encoding exceeds 64 KiB, the bound every reader
applies, is refused before upload. Assets are copied from validated, bounded,
hash-checked regular files
into immutable private uploads asynchronously. Each asset is at most 64 MiB.
Tombstones clear continuation and may retain the manual asset. A conflict
returns the actual server Remote; device timestamps never select a winner.

Downloads compare the fetched commit, tag, hashes and tombstone with the
requested Remote. A changed version produces a conflict before asset copying.
Ephemeral CKAsset files are streamed into generated private files **inside the
per-record completion lifetime**, bounded before reading and verified by hash.
Paths returned by a drain survive until the next drain or cancellation. Only
owned generated copies are cleaned; source payloads and user saves are untouched.

## Ownership and cancellation

CloudKit callbacks use Foundation values and weak transport references. Godot
Variants are constructed only when the main thread drains the queue. Locks
protect requests, operation ownership, generations and queue draining; duplicate
or stale callbacks cannot complete a retired request. Destruction cancels CK
operations and removes only the instance's generated staging child directory.

At most 8 requests are outstanding, and outstanding requests plus queued
completions stay below 64 (one adapter drain) with room for the single
account-change event; repeated notifications cancel the queue and leave one
event. A factory that cannot add an operation (CKContainer raises without the
container entitlement, or the database refuses it) settles the request at once
with `permission` or `invalid` instead of raising or stranding it. macOS
entitlement values are type-checked before use, so a malformed signature fails
closed.

`CKAccountChangedNotification` immediately invalidates/cancels current work and
blocks new ordinary requests until a newer-epoch account query succeeds and
queues `{id:"", epoch:current_epoch, op:"account_changed", ok:true, code:"",
result:{}, retry_after_ms:0}`. The coordinator handles this event before ordinary
results. Account identity is returned only as a SHA-256 digest scoped to the
container. Raw identity and save contents are never logged. CKContainer account
callbacks are not cancellable API objects; generation checks suppress late
results and prevent a cancelled status lookup from starting a subsequent user-ID
lookup. Actual CK database operations receive `cancel` immediately.

Errors use the shared stable codes: unavailable, signed_out, transient, quota,
conflict, token_expired, cancelled, invalid, permission, zone_missing,
zone_deleted and record_missing. Single-record partial errors are unwrapped;
server Retry-After is preserved with saturating arithmetic. Only an
authoritative unknown-item fetch becomes an empty Remote; an unknown item on a
save or download is `record_missing`, which the coordinator answers with an
authoritative fetch rather than a retry of the same request. `zone_missing`
(CKErrorZoneNotFound) makes the coordinator prepare the zone again and refetch
from an empty cursor. `zone_deleted` (CKErrorUserDeletedZone) means the person
deleted the data in Settings; the zone is not recreated until they turn iCloud
saves off and on again (see the design notes).
