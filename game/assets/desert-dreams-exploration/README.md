# Desert Dreams exploration actors

These original Blender models were made for Sin City: Desert Dreams: the
playable woman and man (October 6, 2026) and the vehicles (October 3, 2026).
Their warm sandstone, copper, cream and teal materials match the city's art. No downloaded geometry, external textures or
commercial reference pixels are included. The GLBs contain their geometry and
materials.

Editable masters and generation commands are in `assets/blender-exploration/`
at the repository root. The `.tscn` wrappers import the GLBs at scale 1/16:
sixteen authored meters equal one city tile. Blender +Y forward becomes Godot
-Z forward; feet and tires start at ground height. Keep revisions within the
physical dimensions in `explore_actor_profile.gd`.

Each character is one skinned mesh with an 18-joint skeleton and
Blender-authored in-place `idle`, `walk`, `run` and `jump` clips. The woman wears
a cream blouse with cap sleeves, a copper scarf, teal capris and a chin-length
bob with a copper headband; the man wears a teal camp shirt, copper trousers
and a cropped side part. Walking and running include settled stance-foot
contact. Vehicle motion uses Blender-authored pivots: four `Wheel*` parents with
local `Spin` children, `MainRotor`, and `TailRotor`. The runtime manually advances
clips and pivots with the occupied actor's movement; suspended actors do not
animate autonomously. Front wheels steer about Y, tires roll about X at the
authored .24 meter radius, and helicopter rotors turn about Y and X respectively.

`explore_actor_visual.gd` owns presentation only. Physics bodies, collisions,
movement, saved city data and session lifecycle remain separate runtime owners.

The Mayormobile (November 8, 2026) is a separate original luxury trail SUV used
only by the Mayor's House fleet. Its editable source and five studio previews
are in `assets/mayormobile/`; its builder and exact hashes are recorded in
`docs/art/mayormobile.json`. The `mayormobile.tscn` wrapper uses the same 1/16
conversion with a 2.30 × 2.20 × 5.10 m physical envelope. Four 0.42 m tires
use motion metadata; the tailgate spare stays fixed. Ordinary traffic retains
the Desert Cruiser. See `docs/design/explore-spawns.md` for unique spawning and
dry-terrain driving rules.

These sources are separate from the 144 building masters and their export pairs.
