# Animated disaster models

Seven stylized models live in `assets/disaster-models/` as
editable Blender masters. Runtime GLBs are in `game/assets/desert-dreams-disasters/`.
Every model includes an authored eight-second `Incident_loop` animation.

| Model | Geometry and animation |
| --- | --- |
| Tornado | Sculpted twisting funnel and fused cloud canopy, deforming dust, rising and tumbling debris |
| Hurricane | Irregular rotating cloud banks, deep open eye, changing cloud shapes and rain curtains |
| Tsawhawbitts | Hulking canyon giant with shaggy hair, large hands and woven carrying basket; articulated stride, searching head, grasp and basket motion |
| Microwave beam | Hot core, braided energy strands, changing jagged arcs, moving packets and impact flare |
| Riot | Seven distinct skinned characters with independent marching phases, articulated gestures and hand-bound placards |
| Crash aircraft | Refined twin-engine airliner with banking motion, hinged ailerons, spinning turbines, flame and advancing smoke |
| Fire | Eleven deforming flame tongues, rising and expanding smoke, drifting embers and coal bed |

## Tsawhawbitts

The game's monster is Tsawhawbitts. [Travel Nevada's account of the
Jarbidge legend](https://travelnevada.com/ghost-town/journey-to-jarbidge/) describes
a giant associated with Shoshone stories who carries a large basket. Our visual
appearance, proportions, clothing and animation are original artistic choices;
this model is not presented as an authoritative traditional depiction. The
basket is empty.

## Playback and budgets

The masters preserve separate editable mesh pieces, UVs, vertex colors,
armatures, shape keys and animation curves. Every closed piece has outward
winding. Each asset stays below 16,000 triangles and at most eight materials.
Exact counts, sampled animation envelopes, skeleton/morph/channel counts and
source/runtime SHA-256 hashes are recorded in `provenance.json` and each master's
`*-metrics.json`. These are art budgets, not a guarantee of frame rate.

Blender's scene animation export combines active actions into one clip. Godot
imports the `_loop` suffix as looping playback. Six effects use their imported
skeleton, morph and transform tracks directly. Every instance has independent
playback while sharing immutable meshes, clips and materials.

Fire also has a fully animated standalone GLB, consolidated to one surface with
30 motion bones and six phase-basis morph targets. Those six channels reconstruct
the independent timing of eleven flames. For game playback, 481 Blender poses
are baked at 60fps into shared position and normal atlases. A vertex shader reads
those poses on a shared static mesh; each incident's eight-second AnimationPlayer
controls its own material time. This avoids per-instance OpenGL transform-feedback
work during a large firestorm. The two half-float atlases occupy approximately
39.4MB of shared GPU data; copies are not made per incident.

UV0 addresses the atlas; UV2 holds emission strength and inverted roughness after
glTF V conversion. The shared shader restores the authored warm palettes and
matte smoke. Data import disables color conversion, lossy/automatic compression,
alpha-border repair and mipmaps. Atlas sampling interpolates adjacent poses and
normalizes normals. Expanded bounds include the whole animated envelope.

The source-to-batch conversion compares every authored frame and half-frame.
Atlas quantization and between-frame errors are measured separately in the
provenance: maximum half-float position error is about 0.00815 source meters;
intermediate-pose error is about 0.02146 source meters, or 0.00134 tile units.
The editable fire master keeps all its separate pieces, curves and UVs.

Source coordinates are meters with +Y forward and +Z up. glTF converts to
Godot -Z forward and +Y up; the visual applies one 1/16 scale. The simulation
sets each incident's position and heading. The animation is cosmetic and runs on
wall-clock time, so it keeps moving while the city clock is paused.
The art adds no collision, save fields or simulation RNG calls.

Fires receive deterministic location-based animation phases. Ongoing fire nodes
and playback survive other marker changes; extinguished fires disappear.
Fires sit on building foundations and roofs, including sloped and multi-tile
lots, and follow terrain edits and demolition.

All geometry, UVs, vertex-color variation, materials and animation were made for
this project; no outside meshes or textures were used. Constant warm emission keeps the fire orange and gold after export.
The export presets include the provenance file, and scene references pull in every GLB.

## Editing and rebuilding

Authoring modules are in `tools/disaster_art/`: shared mesh/animation helpers,
weather effects, creatures, aircraft, the fire export batcher and atlas baker. `tools/build_disaster_models.py` builds,
checks, saves, batches, exports and renders them. From the repository root:

```sh
blender --factory-startup --background --python-exit-code 1 \
  --python tools/build_disaster_models.py
```

Use `-- --only monster` for one asset, `-- --skip-render` to omit studio renders,
`-- --render-only` to render saved masters, and `-- --frames` for an optional
96-frame Blender sequence. Preserve manual master edits before rebuilding.

```sh
blender --factory-startup --background --python-exit-code 1 \
  --python tools/build_disaster_models.py -- --verify
```

Verification reopens every master, checks hashes and rest metrics, validates
closed/outward geometry and UV/color attributes, samples evaluated skin/morph
motion and loop closure, and checks exported attributes and animation channels.
