# App icon

The game's icon is a flat Googie city emblem. The square master holds the flat vector shapes and palette; the editable sources are under `assets/branding/app-icon/source/`.

| Target | Active Godot icon source |
| --- | --- |
| Editor, Linux and shared fallback | `game/assets/ui/app_icon.svg` |
| Windows file, taskbar and console wrapper | `game/assets/ui/app-icon/desktop/windows.ico`, with 16/24/32/48/64/128/256-pixel frames |
| macOS file and Dock | `game/assets/ui/app-icon/desktop/macos.icns`, with standard and Retina representations up to 1024 pixels |
| iOS/iPadOS | Opaque 1024-pixel default, dark and grayscale tinted base images, plus explicit App Store slots |
| Android | 192-pixel legacy icon and 432-pixel adaptive foreground/background/monochrome layers |
| Web | `html/export_icon=true` uses the shared project icon for Godot’s generated favicon |

The iOS preset targets both iPhone and iPad, and its icon set covers both device families. Having an icon configured for a platform does not mean the game has been tested there.

The Android foreground and monochrome layers keep the complete emblem inside the central 66-dp circular safe area. See [Android adaptive-icon guidance](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive?hl=en). The shared master and other platform artwork use the same composition.

The export filters include the native desktop icon files (ICO/ICNS) and the icon provenance record.

## Editable sources and generation

`assets/branding/app-icon/source/master.svg` is the editable square vector master. `approved-master.png` is the reference bitmap. Numbered transparent vector layers hold the sun, the architecture and street, and the sparkle. The runtime master PNG is an exact copy of the reference bitmap.

Generate all platform derivatives with Node.js and Sharp:

```sh
node tools/build_app_icon.cjs
```

If Sharp is installed somewhere outside this repository, pass its module directory with `--sharp-module /path/to/sharp`. On macOS, `--native-iconutil` re-encodes the ICNS with Apple’s `iconutil`; the default ICNS writer works without it and its output decodes with Apple's tools. The generator never changes export presets or exports a game.

`game/assets/ui/app-icon/provenance.json` records generated file metadata and hashes. No third-party images, game artwork, fonts or logos are used in the icon.

## Apple artwork

The Apple base images are unmasked 1024 × 1024 canvases. Their backgrounds are opaque; flat foreground vector layers have transparent surrounds and no baked lighting effects. Classic ICNS container images receive a rounded tile with desktop padding. This native presentation is separate from the unmasked artwork sources.

The optional `application/liquid_glass_icon` field is empty because no Icon Composer document has been made yet. The ICNS icon works without it. Godot 4.6’s iOS exporter uses the default/dark/tinted image catalog.

See [Apple icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons/), [Godot macOS icon options](https://docs.godotengine.org/en/4.6/classes/class_editorexportplatformmacos.html), [iOS icon options](https://docs.godotengine.org/en/4.6/classes/class_editorexportplatformios.html), [Android icon implementation](https://github.com/godotengine/godot/blob/4.6.1-stable/platform/android/export/export_plugin.cpp), and [Web icon options](https://docs.godotengine.org/en/4.6/classes/class_editorexportplatformweb.html).

## Known gaps

The icon has been checked as source files and static previews. It has not yet been checked in exported apps on each platform, in a browser tab, in the App Store, or in Icon Composer's dark, clear and tinted appearances.
