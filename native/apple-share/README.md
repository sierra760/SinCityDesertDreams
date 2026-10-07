# Apple city sharing

Objective-C++ adapter using `UIActivityViewController` on iOS and
`NSSharingServicePicker` on macOS. It presents only after the player presses
Share. Available apps and services are chosen by the OS. No authentication,
contact access, analytics, network service or Game Center account is involved.

`CityShare` writes a separate playable `.sc2d` copy. Native saves keep the city's
mayor credit. Copies live in
`user://shared-cities/<unique folder>/<city name>.sc2d` (the name cleaned like
a save name, `City` when empty), so a new share never overwrites an earlier
attachment. Only the five newest copies are kept: after each new copy, older
share-copy folders are deleted automatically. Sharing does not change the
city's save path or mark it as saved. iOS Files fallback depends on the
Files/Document Sharing export options. Android sharing is currently unavailable.

The editor addon includes the native libraries beside the executable in Apple
builds. The `.cfg` extension descriptor is loaded explicitly on Apple
platforms so Linux/Windows do not attempt to load an unsupported native library.
iOS uses a dynamic arm64 framework embedded by `add_ios_embedded_framework`;
macOS uses a universal arm64/x86_64 dylib. Deployment minima: iOS 16/macOS 12.
Sharing needs no extra signing or entitlement settings.

## Rebuild the libraries

Requires Xcode and Python/SCons on macOS. Clone official godot-cpp at
`godot-4.5-stable` (commit `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`), which is
compatible with the game's Godot 4.6.1. Its MIT license is copied here and into
the addon. Run from the repository root:

```sh
python3 native/apple-share/build.py --godot-cpp /path/to/godot-cpp --scons /path/to/scons
```

Simulator frameworks are not built.

## Sharing and receiving a city

Set your name in Settings → General → Mayor. Your title greeting and new or
classic-imported cities use it. Native saves keep their saved mayor until you
change the Settings name with that city open. Blank means Mayor.

Choose City → Share City for a current snapshot, or Load City → Share for an
existing save. The review dialog shows the city and mayor before system sharing.
Mail, Messages and AirDrop depend on OS availability; Game Center's saved-game
API is personal iCloud storage rather than file sharing between players.
On Windows/Linux, Show File reveals the attachment for manual delivery.
Recipients save the attachment, then use Load City → Browse to open it. On iPad,
first place the file in the game's Files folder for the sandbox Browse picker.
