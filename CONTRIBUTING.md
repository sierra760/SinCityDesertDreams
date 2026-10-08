# Contributing

Use Godot 4.6.1 standard and Python 3.10 or later. Set `GODOT=/path/to/godot`
if the engine is not on your PATH. The checks below need only the Python
standard library.

The optional asset build scripts have extra requirements:
`tools/build_disaster_models.py`, `tools/build_traffic_models.py` and the
scripts in `tools/blender_exploration/` run inside Blender 5.2;
`tools/build_bundled_cities.py` runs Godot; and `tools/build_app_icon.cjs` needs
Node.js with the `sharp` package.

## Checks

```sh
python3 tools/check_provenance.py
python3 tools/check_3d_assets.py
python3 tools/check_resort_assets.py
python3 tools/run_tests.py
python3 -m unittest discover -s tools/tests -v
```

A test file passes only when it reports zero failures and the engine prints no
script, engine or resource errors. If a test leaks resources at shutdown, free
what it created rather than silencing the warning. Add focused coverage for
behavior changes and update the relevant design or simulation document. Read [Content provenance](docs/design/provenance-policy.md)
before proposing assets or interoperability changes.

## Code

- Use statically typed GDScript and tabs. Declare types explicitly when values
  can be Variant. Document public methods with `##` comments.
- Keep simulation systems under `game/scripts/sim/`, named parameters under
  `game/scripts/sim/data/`, and written content under `game/scripts/content/`.
- The view reads the city. Construction writes through `Builder`; unfounded
  terrain editing writes through `TerrainEditor`. Display changes must preserve
  simulation state and native saves.
- Keep the player scene 3D-only. Small map images such as the minimap and
  terrain previews are fine; a second playable 2D city view is not.
- Follow the existing conventional commit subjects, for example
  `fix(view): keep utility selection visible`.

## Art and publication

The editable 3D model is the source of truth for future building artwork.
Keep stable building codes, footprints, pivots and import sidecars. Runtime GLBs
share six surface images; model and material provenance records must agree.
See [3D models](docs/art/3d-models.md) and [shared art assets](docs/art/shared-assets.md).

Submit only work you own or have clear rights to contribute. Keep prompt and
hash records for generated art. Project-authored code is licensed under
GPLv3-or-later; submit code contributions under those same terms and preserve
copyright and SPDX notices. Contributed art and assets are licensed under
CC BY-NC-SA 4.0. Contributors retain copyright in their own work. The code
license does not relicense art or third-party material; see
[Licensing scope](LICENSING.md).
