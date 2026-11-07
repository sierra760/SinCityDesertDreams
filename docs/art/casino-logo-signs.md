# Casino logo signs

All fourteen resorts have original illustrated logo signs on shaped, shallow metal cabinets. Lettering, emblem relief, enamel detail and pinstriping come from individual sign-face illustrations; the cabinet, neon rim, brackets and posts are modeled geometry. Each sign has a different silhouette and composition. Daylight shows painted enamel; night mode lights selected lettering, colored glass and trim through a matching emission map.

| Code | Resort | Sign identity |
|---|---|---|
| 251 | Comstock Grand | Ruby Western crest, silver prospector medallion and crossed picks |
| 252 | Silver Junction | Green railway ticket badge, locomotive and station clock |
| 253 | Boulder Crown | Cobalt Art Deco dam, turbine and lightning crown |
| 254 | Desert Orbit | Pink/cyan atomic swoosh, Saturn, rocket and star |
| 256 | The Fix | Emerald/black casino-noir vault and keyhole |
| 257 | Six-Week Alibi | Rose/mint luggage label, rings, rose and suitcase |
| 258 | Velvet Wardrobe | Oxblood cabaret marquee, golden fan and keyhole |
| 259 | The Afterglow | Tangerine/plum boomerang and sunset rays |
| 260 | Last Resort | Western timber, turquoise diamond and desert owl |
| 261 | Dust Republic | Violet/ochre roadside pennant and compass prism |
| 262 | Boddy's | Friendly ivory script, pink/mint scallops, cat and coffee |
| 263 | Woolier Days | Basque boardinghouse arch, sheep and red/green trim |
| 264 | Stockgrowers | Ranch brand, steer, horns and horseshoe |
| 265 | Fremont Palace | Red/gold downtown Deco crown and bulb-edged marquee |

## Authoring and packaging

`tools/casino_signs.json` defines identities, dimensions, mounting and exact selection of superseded names. `tools/prepare_casino_sign_textures.py` prepares one 1024 × 512 color map, one matching light map and a smoothed cabinet contour per sign. Original illustrations and built-in image-generation prompts remain locally under `assets/casino-signs/illustrations/` and `assets/casino-signs/generation.json`.

`tools/blender_exploration/build_casino_logo_signs.py` creates editable `.blend` masters and standalone sign GLBs under `assets/casino-signs/models/`. The source art supplies the lettering; the signs do not embed font files or use runtime text nodes. The cabinet contour follows the artwork without stretching its lettering. Each post reaches the actual lower outline at its own x position and extends 0.12 m into the backing. The six freestanding frontage signs stand ahead of the entrance canopies, within their own lots.

`tools/casino_sign_models.py` appends the new resources to the current building GLBs. It removes only guarded, explicitly selected old-name triangles, preserves collision attributes exactly, retains the input models locally under `assets/casino-signs/originals/`, and refuses changed inputs or duplicate application. The catalog, landscaping hashes, material counts and preceding repair/palm records follow the packaged bytes. `docs/art/casino-logo-signs.json` records the per-model input/output hashes, dimensions, collision hash and budgets.

Run from the project root:

```sh
python3 tools/prepare_casino_sign_textures.py
blender --background --factory-startup --python-exit-code 1 --python tools/blender_exploration/build_casino_logo_signs.py
python3 tools/casino_sign_models.py
```

The normal GLB import extracts each sign's two images beside its building model. Keep those PNGs and their `.import` files with the GLB: they use GPU compression and generated mipmaps. Godot documents this extraction behavior in [GLTFState's image handling modes](https://docs.godotengine.org/en/4.7/classes/class_gltfstate.html). Wait for imports to finish before compiling or visually reviewing changed models.

## Night mode and runtime

Only `sign_logo_letters`, `sign_logo_neon_a`, `sign_logo_neon_b` and `sign_logo_bulbs` have the dedicated `CityNightMode.Role.LOGO`; painted cabinets stay unlit. The illustrated face uses a selective light texture. The existing night fade moves from the imported daytime emission to the intended texture gain or glass color and restores the exact original settings by day. Casino architectural neon reserves the whole sign cabinet, including the interior of a low-triangle textured face.

Silver Junction lights both complete words, including the shaded silver enamel. Six-Week Alibi also lights the burgundy SIX-WEEK lettering on its mint ribbon. Woolier Days lights a traced sheep silhouette and smiling face; the emission paths follow the original painted ears. These masks leave the ribbon, wool and enamel backgrounds dark.

Woolier’s Basque flag uses the dedicated `FLAG` material role, with gentle emission on the original red, green and white cloth surfaces and exact restoration by day. It does not use additive feature copies: those would blend the red field over the narrow green saltire and leave the white cross dominant.

Signs use static transforms and merge with the existing building compilation. There are no per-letter or per-bulb nodes, added dynamic lights, or per-frame geometry. Each final sign adds 562–1,290 visible triangles; all fourteen completed exteriors remain below 40,000. The emitted GLBs, extracted images and normal compiled cache work in both Build and Explore.

`game/tests/test_casino_logo_signs.gd` checks roles, color/fade restoration, newly built signs, demolition, all four lot facings, compilation and all fourteen persistent cache round trips including both image channels. The Python asset suite checks resource remapping, guarded name removal, collision preservation, budgets, canopy clearance and both supports touching the real cabinet outline.

`tools/tests/test_casino_sign_textures.py` checks filled letter coverage, every upper-ribbon letter and hyphen, sheep outline/expression, the corrected right ear, unlit backgrounds and exact authored/runtime light-map agreement. The actual-model night suite checks all three flag colors, their direct lighting, absence of additive flag geometry and exact day restoration.
