# Apple cloud-save distribution

The checked-in configuration is deliberately **unprovisioned and disabled**.
Source checks do not register a container, deploy a schema or prove signing.
A correctly provisioned shipping build enables `apple_cloud/enabled`; its
existing `icloud_saves` preference defaults true, with an Options switch and
local/offline saving available. No player-specific setup within the game is
required beyond an available signed-in Apple account.

## Account-owner prerequisites

Use the developer team's Apple account through Xcode signing/capabilities; do
not store account credentials, certificates' private keys or provisioning
profiles in this repository. The proposed shared container is
`iCloud.com.sierraburkhart.sincitydesertdreams`, bundle identifier
`com.sierraburkhart.sincitydesertdreams`, team `2LK9LNU9V8`. Registration and
current authentication must be verified, not inferred from these strings.

1. Register/confirm that explicit App ID and the shared iCloud container for
   both iOS and macOS; enable the iCloud **CloudKit** service. Associate both
   platform App IDs with this same container in Xcode/the developer account.
2. Create matching Apple Development profiles for Development device testing;
   Developer ID provisioning for the direct-download Mac route; Mac App Store
   and iOS App Store distribution profiles for their Production routes. Confirm
   certificate, team, exact container/service, expiry and environment in the
   downloaded profile. A profile without CloudKit is insufficient.
3. In CloudKit Development, establish the private custom zone
   `SCDDCloudSavesV1` and record type `SCDDCitySaveV1` with the fields below.
   Test with disposable synthetic cities and authorized test accounts/devices.
   Deploy the record schema to **Production**, then independently test a
   Production-signed build. Do not copy user records across environments.
4. Enable a private export configuration only after those prerequisites. Keep
   unsigned, editor, headless, simulator and unconfigured execution unavailable.

Official setup: [Xcode iCloud services](https://developer.apple.com/documentation/xcode/configuring-icloud-services),
[CloudKit enablement](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app),
[Production deployment](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema).

## Actual schema and save inventory

The transport uses **only the private database**. A record name is a random
slot UUID in the custom zone; CloudKit provides record identifiers, change tags,
creation/modification metadata and system fields.

| Application field | CloudKit type | Value |
| --- | --- | --- |
| `commit_id` | String | Random revision UUID |
| `continuation_sha256` | String | SHA-256 of continuation, or empty when absent |
| `manual_sha256` | String | SHA-256 of last manual save, or empty when absent |
| `tombstone` | Int64 | Boolean deletion/discard marker represented by NSNumber |
| `metadata` | Bytes | Bounded UTF-8 JSON NSData described below |
| `continuation` | Asset | Optional immutable validated `.sc2d` continuation |
| `manual` | Asset | Optional immutable validated last manual `.sc2d` save |

`metadata` contains `name`, `mayor`, `date_text`, `population`, `year`, `day`,
`funds`, `stage`, `saved_at`, `application_save_version`, `schema_version`,
`source_device` (random installation UUID), `source_device_label` (coarse
platform only), and optional `conflict_origin` (slot UUID). Assetless tombstones
have version/schema/source metadata without a city header. The latter display
fields are JSON members, **not additional CKRecord fields**. Paths are removed
before upload. Parent record archives/tokens and hashed account identity stay
in the local sync journal, outside portable `.sc2d` files.

The unchanged version-2 `.sc2d` document carries city/mayor names, terrain,
layout, facilities, custom signs/street names, simulation/financial/gameplay
history, and saved mod progress when present. Assets are limited to 64 MiB
(67,108,864 bytes) each. Changed foreground play checkpoints every 60 seconds;
visible library refresh uses 30 seconds. There is one upload and one download
lane. Local Save never waits for the network. Turning sync off retains existing
cloud copies; there is no automatic cloud-slot expiry. Unresolved branches are
preserved. See the matching offline privacy text and publication draft; do not
promise end-to-end encryption, zero Apple retention or local deletion of cloud
copies.

Application suspension stores a local journal receipt outside `.sc2d` files.
It binds the exact managed recovery path and bytes to the captured owner,
immutable conditional generation and separate manual baseline. A cold load
continues the captured slot only with pending-commit or acknowledgement proof;
a later local or remote head is preserved and the older recovery becomes a
separate branch. Foreign-owner recovery stays parked until that account is
verified. Missing, corrupt, replaced or legacy receipts retain the existing
fresh-personal recovery behavior; annual backups still start personal sessions.
If identity metadata cannot be invalidated, or the owner is absent, latest
local progress uses the bounded `recovery/suspended-untracked.sc2d` fallback
shown in Load. The authenticated older copy remains intact. A newer canonical
recovery retires the fallback only after local data and identity publication
succeed; cleanup targets the recovery actually loaded by that city.

## Private export configuration

Make a disposable copy of `game/`, excluding `.godot` and local export outputs,
and give that copy a unique `application/config/custom_user_dir_name`. Never
run a verification export against a player's directory. Keep signing inputs
outside `res://` and outside version control.

In that private copy, set these two ProjectSettings together:

```ini
[apple_cloud]
enabled=true
container_id="iCloud.com.sierraburkhart.sincitydesertdreams"
```

For the selected preset, set `application/additional_plist_content` to this
XML **fragment** (encode as a Godot string, not a standalone plist):

```xml
<key>SCDDCloudKitEnabled</key><true/>
<key>SCDDCloudKitContainer</key><string>iCloud.com.sierraburkhart.sincitydesertdreams</string>
```

Both keys must be in the sealed **main application** Info.plist. Framework
flags do not count. Do not modify already signed bundles: configure, export,
sign, inspect, then launch only after the product gate passes.

### Developer ID DMG

Preserve preset `macOS`, `export/distribution_type=1`, universal architecture,
Developer ID Application signing and notarization. Copy the selected
`platform/apple-cloud/developer-id.entitlements` to a disposable private file
outside the project. Point `codesign/entitlements/custom_file` at that copy.
Never point it at the tracked template: Godot 4.7.2's unsandboxed helper cleanup
can delete the referenced custom file. Retain the original private template
and recreate the disposable copy for **every** export.

The engine auto-embeds `codesign/provisioning_profile` only for distribution 2.
For Developer ID, copy the validated matching profile into a private directory
under the exact basename `embedded.provisionprofile`, and set the process
environment variable `SCDD_APPLE_CLOUD_PROFILE` to its absolute path. The cloud
export plugin queues it with `add_shared_object(path, ["macos"], "Contents")`;
the engine copies it into `.app/Contents/embedded.provisionprofile` **before**
bundle signing. This input is not a Godot runtime setting. Never put it in the
PCK. Empty or invalid/missing embedding fails the signed-product gate.

### Mac App Store PKG

Use the separate `macOS App Store` preset, distribution 2, sandbox, outgoing
network access, user-selected read/write files, universal architecture and
matching Application/Installer distribution identities. Supply the validated
profile via `codesign/provisioning_profile`. Use a disposable copy of
`mac-app-store.entitlements` as the custom entitlement file. Confirm the actual
certificate names available to the account; checked-in identity labels do not
prove installation. Notarization is retained for Developer ID, not this route.

### iOS Xcode project

Keep arm64, iOS 17, iPhone+iPad and the existing Files/share behavior. The export
plugin links and embeds `SCDDAppleCloud.framework` outside the PCK. The public
preset uses automatic signing, empty profile specifiers, and Apple Development
for both Debug and Release. Archive with Xcode, then let Organizer re-sign for
distribution when exporting the archive.

For a separate private configuration with an explicit provisioning profile, fill
`application/provisioning_profile_specifier_debug|release` with the corresponding
profile. Godot generates manual signing when the explicit profile is supplied;
use Apple Development for Debug and Apple Distribution for a Production Release
with its matching distribution profile. A generic Apple Distribution identity
alone does not switch an otherwise automatic project to manual signing.
Set `entitlements/additional` to an XML fragment with these three keys:

```xml
<key>com.apple.developer.icloud-container-identifiers</key><array><string>iCloud.com.sierraburkhart.sincitydesertdreams</string></array>
<key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array>
<key>com.apple.developer.icloud-container-environment</key><string>Production</string>
```

Use **Development** instead of Production for the separate private debug
configuration and matching profile. The macOS `*-development.entitlements`
templates document that separate environment; do not use a Development profile
with Production entitlements or vice versa. Device capability strings are not
CloudKit entitlements. iOS export generates a project, not a signed app; Xcode
must archive/sign it. Repeat `tools/clean_ios_usage_descriptions.py` after every
iOS export as required by the existing release process.

## Verification gates

### Mac main-executable CloudKit dependency

Both Mac signing routes require a direct, strong CloudKit framework load command
in **each main-executable architecture**. Linking only the dynamically loaded
native bridge is insufficient for App Sandbox's CloudKit service access. See
[Apple DTS's framework-linkage explanation](https://developer.apple.com/forums/thread/835400).
The product checker now verifies this independently of native-bridge linkage.

For the official Godot4.7.2 Mac template, prepare a **separate private ZIP before
export**, then let Godot perform its normal final signing. Keep installed
templates and tracked project/preset flags unchanged. Obtain and verify the
official template archive first; the explicit SHA below must be the expected
digest of its verified `macos.zip`, not a hash taken from an unknown download.

```sh
python3 tools/prepare_apple_cloud_macos_template.py \
  --input /private/verified-templates/macos.zip \
  --input-sha256 EXPECTED_VERIFIED_MACOS_ZIP_SHA256 \
  --output /private/export-inputs/cloud-macos.zip \
  --manifest /private/export-inputs/cloud-macos-manifest.json
```

In the **private** Mac export preset, set both `custom_template/debug` and
`custom_template/release` to that output ZIP. Godot's
[4.7.2 Mac exporter](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/export/export_plugin.cpp)
selects the corresponding executable from the ZIP. The preparer requires
`macos_template.app/Contents/MacOS/godot_macos_debug.universal` and
`macos_template.app/Contents/MacOS/godot_macos_release.universal`.

The tool bounds compressed/expanded bytes, entries, paths and Mach-O structures;
rejects traversal, duplicates, links, signing inputs, unsupported architectures
or layouts, existing/weak/ambiguous CloudKit dependencies and insufficient zero
header padding. It appends one `LC_LOAD_DYLIB` per slice for
`/System/Library/Frameworks/CloudKit.framework/Versions/A/CloudKit`, changing only
the command counters and previously unused header bytes. Existing command order,
dylib ordinals, sections, other member contents and permissions are preserved.
The manifest records exact before/after byte ranges and hashes. Repeating with
the same input and Python/zlib runtime produces identical ZIP/manifest bytes;
existing outputs are never overwritten. For a changed upstream layout, stop and
review it rather than removing these guards.

**Intermediate executable signatures are stale. Never launch them or patch a
finished signed app/archive.** Use the prepared ZIP as input to normal Godot
export/signing, then run the full actual-product checker below. The preparer
does not sign, notarize, register accounts, enable cloud or establish device sync.

```sh
python3 -m unittest discover -s tools/tests -p test_apple_cloud_export.py -v
python3 -m unittest discover -s tools/tests -p test_apple_cloud_macos_template.py -v
python3 tools/check_apple_cloud_export.py --source
python3 tools/check_apple_cloud_export.py --product /private/path/Game.app --distribution developer-id
python3 tools/check_apple_cloud_export.py --product /private/path/Game.app --distribution mac-app-store
python3 tools/check_apple_cloud_export.py --product /private/path/Game.app --distribution ios
```

Extract an actual app from the DMG/PKG/IPA first. Development checks explicitly
add `--environment Development`; default is Production. The product checker
uses `codesign` strict verification, authority/team and entitlements, the
embedded CMS profile's team/expiry/CloudKit environment and signing certificate,
and packaged native `lipo`/`vtool` architecture/platform/minimum-OS evidence.
It reads the **actual packaged `project.binary` inside the PCK** and requires
matching enabled/container values; it rejects native/signing inputs inside the
pack. It also rejects packed `override.cfg`, `override.cfg` beside the executable
or PCK, and every nonempty `application/config/project_settings_override`
selector (including feature-qualified variants). This fail-closed packaging
policy follows the [Godot 4.7.2 settings loader](https://github.com/godotengine/godot/blob/4.7.2-stable/core/config/project_settings.cpp#L638-L813):
override files can otherwise change effective settings after `project.binary`.
The checker does not execute or read custom override targets and does not alter
the game's global override behavior. This is independent of Info.plist. Unsupported encrypted/sparse packs
fail closed. No game or account is launched by inspection.

The checker targets pre-submission products with their embedded profiles.
Apple may remove profiles during App Store distribution; a missing profile in
a store-delivered app is not proof of an invalid installation, but cannot pass
this pre-submission evidence gate. iOS uses mandatory OS signing plus sealed
flags at runtime; no private entitlement API or runtime profile parser is used.
See [Apple TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).

A source pass, unsigned packaging pass, signed-product pass, authenticated
account, deployed Production schema and physical-device sync acceptance are
separate facts. Verify account switches, two-device continuation/manual/conflict
behavior, offline retry, interrupted upload/download, quota and disabled sync
on authorized devices before release. Private exports are verification artifacts;
no release upload, publishing, licensing change or privacy declaration follows
a source/test pass. Existing policy URL/contact/provider-retention questions
remain open. Proposed commit boundary: `build: configure Apple cloud-save distribution`.
