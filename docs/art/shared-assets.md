# Shared art assets

The city is drawn only in 3D. Building, vehicle, disaster and station art are
Blender models described in [3D models](3d-models.md) and the related model
guides. This page covers the remaining shared images and the street-name sign
models.

- `game/assets/desert-dreams-3d/textures/` holds the ground albedo textures
  (sand, rock, road grain), recorded with their hashes in
  [ground-textures.json](ground-textures.json), and the connected-material grain
  sheet that terrain and network materials sample for fine surface detail. Its
  source and hash are recorded in `provenance.json` beside it.
- `game/assets/desert-dreams-3d/surfaces/` holds the content-addressed images
  shared by the building models, recorded in
  [building-materials.json](building-materials.json).
- Tool icons live under `game/assets/ui/tool-icons/` and are resolved from tool keys
  at runtime, so the export must include every imported resource rather than
  only the ones reached by static loads.
- `game/assets/ui/oro-canyon-splash.png` is the main-menu artwork, an in-game
  Explore render of Oro Canyon. `boot-splash.png` beside it is a reduced copy
  that `project.godot` uses as the boot splash. `desert-city-splash.png` and
  `desert-postcard.svg` are earlier menu artwork that the game no longer loads.
  Each image has a `.provenance.json` beside it; the app icon sources and their
  provenance are in `app-icon/`.
- `game/assets/street-name-signs/` holds the street-post, street-blade and
  highway-exit GLBs used for Explore street signs, their brass, deep-teal and
  ivory texture swatches, `templates.json` (board sizes and safe lettering
  faces) and `provenance.json`. Street names are lettered at runtime in
  BioRhyme Medium.

## Asset changes

Use artwork made for this project and keep its prompt and hash provenance.
Do not copy commercial reference pixels. Model catalog codes, footprints and
ground pivots are the reference for new building art.

Run `python3 tools/check_provenance.py` and `python3 tools/check_3d_assets.py`
after an asset change, then the affected view and UI tests. Previews and
captures use this game's own city fixtures.
