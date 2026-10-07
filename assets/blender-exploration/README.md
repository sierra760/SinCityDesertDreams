# Explore model sources

Stylized assets for the playable woman and man, the desert cruiser and the
scout helicopter. Open `pedestrian_woman.blend`, `pedestrian.blend`, `car.blend`
or `helicopter.blend` to edit meshes, materials, skeleton, clips and preview
lighting. The characters' four actions are kept in named NLA tracks; select
one action to preview it. The vehicle masters keep their movable wheel and
rotor hierarchies.

The generators reproduce the models, GLB exports, measured bounds and studio
renders using Blender 5.2.2. Run from the repository root (use the full path to
the Blender executable if `blender` is not on your PATH):

```sh
blender --background --factory-startup --python-exit-code 1 --python tools/blender_exploration/build_pedestrian.py -- --character woman
blender --background --factory-startup --python-exit-code 1 --python tools/blender_exploration/build_pedestrian.py -- --character man
blender --background --factory-startup --python-exit-code 1 --python tools/blender_exploration/build_vehicles.py
```

The character generator accepts `--stage DIR` to write a trial build under a
separate directory, `--skip-render` to omit the Cycles previews and
`--debug-colors` to give every construction part a flat color for attributing
artifacts. The vehicle generator accepts `-- --only car` or `-- --only helicopter`.
Generation overwrites these masters and exports; preserve hand edits before
regenerating. Studio cameras, lights and ground are excluded from GLB exports.
No external images or model assets are required. Previews are native Blender
Cycles renders.

## Character construction

Each character is one skinned mesh assembled from named parts:

- **Body skin**: a skin-modifier graph with a vertex per joint and a
  cross-section radius, grown into one closed surface and subdivided once.
  Faces hidden under clothing are removed so nothing pokes through cloth.
- **Clothing shells**: the shirt or blouse (subdivided twice, with a local
  circular neck opening under the collar band or scarf), separate sleeve tubes
  that taper to a point inside the torso, and trousers or capris with planar
  waist and cuff cuts. Open edges that show get a solidified fabric thickness.
- **Head**: an egg-shaped skull with eyes, irises, brows, nose, ears and mouth.
  Hair is built from ellipsoid caps trimmed by bisecting planes, so hairlines
  are clean curves, and solidified for a visible rim. The man's crop has no
  added hair pieces beyond sideburns.
- **Details**: belt and buckle, collar band, placket and buttons, chest pocket,
  scarf and knot, headband, earrings, shoes with welts and ankle straps.

Skinning is distance based: every vertex takes up to four influences from the
bones its part lists, weighted by a smooth falloff from each bone segment and
normalized. Proportions live in one dictionary per character at the top of the
generator; the eighteen-bone rig derives from it.

Clips are keyed every frame from closed-form gaits: idle breathing and weight
shift (48 frames), walk (24), run (14) and a crouch/launch/tuck/land jump (21),
at 24 fps. The Root never moves. After keying, the lower shoe is settled onto
the ground on every frame by solving the Hips height; airborne jump frames keep
the launch height so the tucked feet leave the ground.

Blender gives successive wheel children names such as `Spin.001`. The vehicle
generator's `normalize_glb_pivots()` post-export step renames those empties to
`Spin` under their separate wheel parents. A manual GLB re-export must apply
that step too; the runtime expects each wheel's child to have that exact name.

Author in meters with Blender +Y forward and Z up. glTF converts to Godot -Z
forward and Y up; scene wrappers apply 1/16 scale. Keep the actor root fixed.
Character clips move bones in place; gameplay owns world motion and jumps.
Vehicles use runtime pivot motion tied to actual speed and steering, rather
than baked driving clips.

Budgets: woman 12,800 triangles, man 10,244 triangles, ten shared materials
each and a rest pose inside the 0.576 × 1.84 m actor profile; car 5,528
triangles and nine used materials; helicopter 1,764 triangles and nine used
materials. Static vehicle parts are merged by material while movable pivots
remain separate. Foot contact, pose bounds, car steering bounds and rotor
sweeps are measured in the preview JSON files; Godot asset tests verify the
imported resources and runtime animation contract.
