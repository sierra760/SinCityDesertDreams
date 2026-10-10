# Model-first 3D art

The 3D city view uses 150 low-poly building models, covering every building
identity from 112 through 261. Each was modeled in Blender for this project.
Warm sandstone, teal and copper are the base palette; selective mid-century
signs add coral, amber and emissive tubing.

The complete runtime package lives in `game/assets/desert-dreams-3d/`. GLBs
contain their geometry, UVs and materials. Six content-addressed images
in `surfaces/` are shared across the runtime catalog. Standalone authoring GLBs
keep their packed textures; runtime repacking leaves the geometry buffers intact.
`catalog.json` maps each building identity to its model, lot size, uniform
scale, height and content hash. The renderer reads the city as it is;
surface, analytical and underground views share its simulation and save format.

The orthographic camera uses a 2:1 tile projection with matching terrain
relief. Roads use the same network connections, asphalt width, shoulders and
palette. Palm groves follow the tile families' planting layouts. Supplemental
lot planting is recorded in `landscaping.json`, bound to each model's content
hash, and kept inside its footprint. A model keeps its building code and lot
size when it is revised, and its supplemental planting is rechecked for
clearance.

## Building surfaces and identity

The catalog uses real UV-mapped stucco, limestone and concrete albedo,
alongside the existing sand, rock and asphalt images for incorporated ground.
Glass, metals, foliage, painted markings and sign lettering keep their authored
materials. Roughness and metalness remain material properties; lighting is not
baked into the images. Asphalt detail repeats every 3.3 meters on model lots.

Fifteen original commercial/casino identities and the six additional resorts
have their own signs. The
subway entrance, both fuel stations, civilian and military parking compounds,
City Hall, Museum, Library and desalination plant have their own functional or
architectural details. Station 233 has a solid plaza and a small, open
entrance pavilion; Explore replaces its hidden display cabin with a working
elevator and enclosed platform access. Rail station 237 (24,676 triangles) is
the Desert Transit rail hall: a glazed ticket hall with fluted sandstone piers
under a butterfly roof, a teal platform canopy on brass columns and a name
fascia. Both station lots carry the same freestanding DT (Desert Transit) pylon.
Station lettering uses the same bundled BioRhyme Medium font as runtime mounted
wayfinding plaques; see [typography and notices](station-typography.md).

[Building material provenance](building-materials.json) binds every master,
standalone GLB, runtime GLB and shared image hash. The three architectural
maps were made for this project; their
[prompts](building-texture-prompts.json) are recorded.

## Six additional resort exteriors

Buildings 256–261 add The Fix, Six-Week Alibi, Velvet Wardrobe, The Afterglow,
Last Resort and Dust Republic on 4 × 4 lots. Their original Blender geometry
preserves the concept silhouettes: an obsidian/brass vault hotel, split
blush/mint wings with wedding rings, an oxblood cabaret/keyhole, an ivory
observation hotel and sunburst, a weathered bank/bottle-glass base with a clean
turquoise tower, and rust stacks with tensile sails and an original light
sculpture. Each has a street-facing entrance, grounded plaza and conservative
collision shells.

Every visible part is supported: columns, piers and fins reach a footing or the
structure above, penthouses and lounges stand on their roofs, and ornaments are
seated on a wall or pylon. Windows are placed after the massing, and any pane that
a lobby, wing, belt course, parapet or sail would cross is omitted rather than
drawn behind it.

Each resort has its own facade swatch, applied with metre-scale box-projected
UVs and multiplied by its authored palette: polished granite panels (The Fix),
scored sand-float stucco (Six-Week Alibi), face brick (Velvet Wardrobe),
board-formed concrete (The Afterglow), rusticated sandstone (Last Resort) and
corrugated weathering steel (Dust Republic). All six share terrazzo plaza paving
and gravel-ballast roof membranes. The runtime swatches are content-addressed JPEGs in `surfaces/`, listed in
[building-materials.json](building-materials.json).

`tools/blender_exploration/build_six_resort_exteriors.py` writes only the six
new `256-blender.glb` … `261-blender.glb` models and appends their catalog
records. Editable masters are retained locally outside the public package.
The original 144 building models retain their identities. Walkable themed
halls are separate Explore assets; see [Resort interiors](resort-interiors.md).

## Ground materials

Three color textures were made for this project. They are saved under
`game/assets/desert-dreams-3d/textures/`:

- `desert-sand.png`: fine warm sand for flat ground.
- `desert-rock.png`: sandstone chips and gravel, blended onto slopes.
- `road-grain.png`: fine aggregate for asphalt and paved surfaces.

The [prompts](ground-texture-prompts.json) and
[source hashes and image metadata](ground-textures.json) are recorded, and the
source images are used unedited. The renderer normalizes their RGB variation
to the terrain palette, maps them continuously across the city, and mirrors sampling to avoid
opposing-edge seams. Rock uses triplanar mapping on steep faces. Mipmaps and
anisotropic filtering keep the detail stable as the camera moves and zooms.

The same folder holds `connected-materials.png`, a fine grain sheet sampled by
the terrain and network materials; its source and hash are recorded in the
folder's `provenance.json`.

## Import contract

- Blender authoring uses 16 meters per tile. A uniform scale of 1/16 converts
  each model into the game's tile coordinates, with a grounded, central pivot.
- Commit the `.glb.import` sidecars with the GLBs. They hold the import settings
  and stable resource identifiers.
- Imported physical shells use collision layer 4. Terrain picking uses layer 1;
  building query proxies use layer 2. Physical decoration must not intercept
  construction rays.
- Godot generates mesh LODs. Model 203 keeps a zero-degree normal merge
  angle on its hollow cooling shell. Models 222 and 230 are already minimal
  paving at 124 and 286 triangles and do not need additional simplification.
- Every export preset explicitly includes the catalog and landscaping JSON.
  Godot's resource export does not automatically include arbitrary JSON files.

Run `python3 tools/check_3d_assets.py` to verify package coverage, hashes,
GLBs and allowed shared images, physical shell declarations, import settings
and export inclusion. The Godot tests additionally check the renderer and game controls.

The default mode is aerial city building. The models have finished backs, roofs
and street-level detail for Explore mode, where you can walk, drive and fly
through the city. See the README for controls.

## Building a package

Use Godot 4.6.1 with its matching export templates. From the repository root:

```sh
godot --headless --path game --import
python3 tools/check_provenance.py
python3 tools/check_3d_assets.py
python3 tools/run_tests.py
mkdir -p game/export
godot --headless --path game --export-release macOS export/SinCityDesertDreams-3D.zip
```

Output goes to the git-ignored `game/export/` directory. These commands do not
upload anything. The macOS preset signs the app with the maintainer's Developer
ID and does not notarize it; change the preset's code-signing options to sign
with your own identity or to build unsigned.

## What is in this repository

This repository contains the 150 GLBs, import sidecars, catalog and landscaping
JSON, fourteen shared surface images, three ground textures, the connected-material
grain sheet, and prompt/material provenance. Editable building masters are retained locally outside this repository.

These models and textures are licensed under CC BY-NC-SA 4.0, not the GPL;
see the [licensing scope](../../LICENSING.md).
