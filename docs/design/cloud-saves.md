# Cloud city saves

Apple cloud saves keep a city's latest continuation and its last manual save
available across configured macOS and iOS builds. Local Save succeeds without
waiting for the network. The portable `.sc2d` format remains version 2; account
identity, cloud ancestry and synchronization receipts live outside that file.

## Availability and preferences

The checked-in project keeps `apple_cloud/enabled=false`. Both project settings
and the sealed main application's cloud configuration must be enabled before
the native adapter is available. Editor, headless, unsupported-platform and iOS
simulator execution cannot use the transport. The `icloud_saves` preference
defaults true when support is available and can be changed in Options. Turning
it off retains existing cloud copies and local/offline saving remains available.

While synchronization is unsupported or off, the cloud session does no capture,
copy or validation work: ordinary saves and recovery behave as plain local
files. The open city and any save made meanwhile join the library when
synchronization is turned on. A suspension recovery copy remembers its named
save destination in a small local note (path and hash) so a reopened recovery
keeps it without the journal.

The transport uses the private CloudKit database in the configured shared
container. It does not use a public database, Game Center, analytics or a
publisher-operated save server. Account and network availability can change
while the application is running; synchronization status is separate from a
successful local save.

## Components and ownership

- `CloudSaveSession` connects ordinary city loading, manual saves, discard,
  foreground checkpoints and application recovery to the cloud library.
- `CloudSaveStore` owns immutable validated payloads, the atomic journal,
  installation identity, account-separated libraries and recovery receipts.
- `CloudSaveCoordinator` schedules account checks, inventory, transfers,
  conditional writes, retries and publication of accepted results.
- `CloudSavePolicy` chooses reconciliation actions from ancestry and content.
- `AppleCloudPlatform` validates requests and completions on the Godot thread.
  The native `SCDDAppleCloud` bridge performs asynchronous CloudKit transport.

Each request carries an identifier, operation and account epoch. Stale or
cancelled completions cannot update a replacement account's library. The
native side handles Foundation values in callbacks; Godot values are created
when the main thread drains completions. Generated staging files belong to the
transport; cleanup does not remove source payloads or personal save files.

## Save identity, conflicts and recovery

A slot has a random UUID and each revision has a separate random commit UUID.
Conditional writes use the server's actual system fields and change tag with
`CKRecordSaveIfServerRecordUnchanged`. Device timestamps never select a winner.
Divergent work is preserved as branches rather than silently overwritten.

A continuation and a manual save serve different purposes: the continuation
keeps recent play, while the manual asset retains the explicit save baseline.
Choosing Don't Save drops only the current session's changes. A slot that has
not changed since it was opened is left alone. A slot that existed before the
session returns to the state it was opened in. A slot created during the
session returns to its manual save, or, with no manual save and nothing
acknowledged by the server, records a tombstone. If the player then cancels the
Load, New or Import dialog and returns to the same city, the discard is undone
and checkpoints resume. Saving As onto a name another city has reserved moves
that reservation to a free name instead of taking the other city's slot.
Unresolved branches remain available and cloud slots have no automatic expiry.

Application suspension stores local recovery bytes with a journal-owned receipt
binding the exact path and hash to its captured owner, conditional generation
and manual baseline. Recovery continues that identity only with pending-commit
or acknowledgement proof. A later local or remote head is preserved and older
work becomes a separate branch. Foreign-owner recovery waits for that account;
missing or invalid receipts retain personal recovery behavior. Annual backups
start personal sessions.

## Cloud record and data inventory

The private custom zone is `SCDDCloudSavesV1` and its record type is
`SCDDCitySaveV1`. A record's name is its slot UUID.

| Field | Type | Contents |
| --- | --- | --- |
| `commit_id` | String | Revision UUID |
| `continuation_sha256` | String | Continuation hash, or empty when absent |
| `manual_sha256` | String | Manual-save hash, or empty when absent |
| `tombstone` | Int64 | Deletion/discard marker |
| `metadata` | Bytes | Bounded JSON display and version metadata |
| `continuation` | Asset | Optional immutable validated `.sc2d` continuation |
| `manual` | Asset | Optional immutable validated manual `.sc2d` save |

Display metadata includes city/mayor names, date, population, funds, stage,
saved time and actual application save version. It also contains schema version,
a random installation UUID, a coarse platform label and an optional conflict
origin slot UUID. Paths are removed before upload. CloudKit supplies record
identifiers, change tags, timestamps and system fields. Local account identity
is a container-scoped hash; raw account identity and save contents are not logged.

The save assets include city/mayor names, terrain, layout, facilities, custom
signs and street names, simulation and financial history, gameplay state and
saved mod progress when present. Local synchronization journals retain parent
archives, change tokens and account-separated state outside portable saves.
If the private zone disappears (CloudKit reports it missing), it is created
again and inventory restarts from an empty cursor; pending work on this device
then uploads normally. If the player deleted this game's iCloud data in
Settings, the zone is not recreated automatically, because that would upload
again the data they chose to remove: syncing pauses, recorded per account so a
relaunch keeps the pause, Load City says the iCloud saves were deleted, and
local saves keep working. Turning iCloud saves off and on again is the consent
that lets the next verified account recreate the zone. A save or download whose
record no longer exists is resolved by fetching the authoritative record, not by
retrying the request.

Turning synchronization off does not delete cloud data. The application makes
no end-to-end encryption or Apple retention guarantee.

## Bounds and scheduling

Changed foreground play checkpoints every 60 seconds; a visible library refreshes
every 30 seconds. There is one upload lane and one download lane. Each asset is
limited to 64 MiB (67,108,864 bytes), inventory pages to 256 records/deletions,
metadata to 64 bounded scalar entries, and opaque server archives to 1 MiB.
Payloads are size/hash/format validated before publication. Opening a
library checks each payload's size and SHA-256 against its journal descriptor
rather than decoding it; a payload whose descriptor exists was format-validated
when it was copied, and decoding for metadata happens on use. A manual save
identical to its continuation shares one payload file. Load City lists local
saves from their headers, so a save with a damaged body is still listed.
Personal saves are migrated once per verified account epoch and afterwards only
when a file changes. Signed-out, quota and permission failures back off up to
15 minutes (other failures up to 60 seconds); foregrounding, opening Load City
or saving can retry sooner, at most once a minute and never before a
server-requested delay. Downloaded assets
must match the requested remote revision before becoming usable local copies.

## Native build support

The original bridge source, offline injected-operation harness, pinned binding
revision and build command are documented in
[`native/apple-cloud/README.md`](../../native/apple-cloud/README.md). Installed
runtime libraries target universal macOS 12.0 and arm64 iOS 17.0; their binding
license is included beside both source and runtime resources.

`tools/prepare_apple_cloud_macos_template.py` prepares a separate verified Godot
Mac template with a strong CloudKit load command in both main-executable slices.
It bounds ZIP and Mach-O structures, preserves existing payloads and writes a
hash manifest. It does not sign an application; intermediate signatures become
stale and normal export/signing must follow before use.

`tools/check_apple_cloud_export.py` checks disabled source configuration or an
actual signed product. It inspects the packaged settings, native architecture,
main-executable framework linkage and signing contract. Its Python tests use
synthetic packages and template structures. Source checks, product inspection
and actual account/device behavior establish separate properties; a source
pass does not enable cloud support or establish release acceptance.
