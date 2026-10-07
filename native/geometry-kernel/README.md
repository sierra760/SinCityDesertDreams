# Geometry kernel

Native C++ (GDExtension) port of the exact physical surface extraction in
`game/scripts/view/city_network_physics.gd` (`resolve`). It exists only for
speed: La Presa's 509,402 patches take about 21 seconds in GDScript and well
under a second natively. The output must be byte-identical to the GDScript
resolver; `game/tests/test_native_network_physics.gd` checks that on
synthetic fixtures and on La Presa and Valle del Mar.

How exactness is kept:

- GDScript `float` is double, while the engine's vector methods compute in
  float32. The kernel uses godot-cpp `Vector2`/`Vector3`/`Rect2` for component
  arithmetic and spells `cross`, `dot`, `length`, `normalized` and `lerp`
  exactly as the engine source does. The official 4.6.1 arm64 engine performs
  no FMA contraction in those methods (verified empirically on 40,000 random
  inputs per operation), so the library is built with `-ffp-contract=off`.
- Scalar expressions that GDScript evaluates in double are written with
  explicit `(double)` operands in the same association order.
- Dictionary insertion order and Godot's introsort (`scdd_sort_array.hpp`, an
  MIT-licensed adaptation of `core/templates/sort_array.h`) govern output
  order; equal-role patches reorder exactly as `Array.sort_custom` does.
- The partition cache reproduces the engine's `hash()` of
  `Array[PackedVector2Array]` and its single slot per hash; reuse happens only
  on exact `==` equality, so the cache never changes output.

Measured on an M4 Max (packed entry, kernel only, timings vary with machine
load): La Presa 509,402 patches 18.8 s GDScript → about 0.44 s; Valle del Mar
954,038 patches 29.6 s → about 0.9–1.15 s; Lawndale 1,089,658 patches 43.9 s →
about 1.3 s; Salton Shores 1.3 s → 0.03 s. The eight classic included cities
produce identical SHA-256 output through both entry points. The dictionary entry adds
the GDScript packing cost (about 0.4 s for La Presa).

The runtime dispatcher `game/scripts/view/city_network_physics_native.gd` loads
`res://addons/scdd_geometry/scdd_geometry.cfg` explicitly on macOS/iOS and
falls back to the GDScript resolver elsewhere or when the library is missing.
Boxes stay in GDScript as a pass-through copy.

## Incremental resolution

`resolve_detailed` returns the same resolution split into per-group blocks
(group keys, first/last input patch, floor, deck bottoms, deck triangles with
one depth each, deck XZ bounds and the walls whose quantized segment key first
appears in each group); `floor` equals `physical_floor_faces` and inputs +
`bottoms` + `walls` equal `physical_obstacle_faces`. `resolve_boundaries`
recomputes the walls of an ordered group subset, `diff_groups` compares two
patch sets group by group bit for bit, and `splice_vector3`/`splice_float64`
concatenate ranges. `game/scripts/view/city_network_physics_incremental.gd`
uses them to re-resolve only what an edit can reach; `resolve_packed` is
unchanged. `game/tests/test_network_physics_incremental.gd` compares the
incremental result with a full resolution after every edit, on both paths.

## Rebuild the libraries

Requires Xcode on macOS and the pinned official godot-cpp checkout at
`godot-4.5-stable` (commit `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`, compatible
with Godot 4.6.1) with its `template_release` static libraries already built
using `native/apple-share/build_profile.json`. Run from the repository root:

```sh
python3 native/geometry-kernel/build.py --godot-cpp /path/to/godot-cpp
```

Pass `--scons /path/to/scons` only when a static library is missing. The
macOS dylib is universal arm64/x86_64; iOS is an arm64 dynamic framework.
Matching output has been verified on arm64 macOS; the x86_64 slice is built
with the same uncontracted arithmetic.
