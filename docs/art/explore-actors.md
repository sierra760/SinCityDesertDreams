# Explore actor artwork

Project-authored models and textures use CC BY-NC-SA 4.0; generator and runtime
code use GPL-3.0-or-later. See [licensing scope](../../LICENSING.md). These models are authored with the Blender generators below.

## Sources and runtime files

`tools/build_traffic_models.py` builds the catalog through shared
`tools/model_art/{contracts,common,vehicles,pedestrians}.py`. The stable runtime stems and physical
metadata are in `game/assets/desert-dreams-traffic/catalog.json`.

The eighteen vehicle stems are car, compact, sedan, taxi, pickup, van, bus,
truck, police, fire_engine, ambulance, military, train, subway, ship, sailboat,
helicopter and plane. The sixteen crowd stems are pedestrian_00 through
pedestrian_15. Each has `<stem>.glb` (middle), `<stem>_far.glb` (far) and
`<stem>_detail.glb` (near). Existing IDs, driving permissions, domains and
catalog physical dimensions remain authoritative; visual bounds never become
new collision shapes.

`tools/blender_exploration/build_pedestrian.py` rebuilds the accepted Woman and
Man through the same body/rig helper, retaining their faces, clothes and prior
clips. The corresponding car/helicopter generator wrappers retain their public
source/export paths. Desert Transit cabin finishes remain separate authored
resources and are not replaced by the exterior tier meshes.

## Units, limits and motion

Authoring coordinates use metres, +Y forward and +Z up. Imported Godot scenes use -Z
forward and +Y up. Runtime conversion happens exactly once at 16 metres per
tile. Roots are feet, tire contact or waterline as appropriate. Catalog
`original_envelope`, per-tier bounds, contact errors, material names and motion
metadata retain the authoring contract.

| Actor | Near triangles/materials | Middle triangles/materials | Far triangles/materials |
| --- | ---: | ---: | ---: |
| Pedestrian | 13,000 / 12 | 3,500 / 6 | 1,500 / 6 |
| Road vehicle | 16,000 / 12 | 6,000 / 6 | 2,000 / 6 |
| Rail, boat, aircraft | 24,000 / 12 | 8,000 / 6 | 3,000 / 6 |

These are ceilings, not targets. Cheaper middle meshes are retained. Pedestrians
have eighteen bones and idle, walk, run, jump and wave clips. Crowd gait keys are
linear at 240 Hz; imported contact coverage samples at 960 Hz, with a 3 mm
stance tolerance. Airborne jump intervals are intentionally excluded from that
stance test. The player models retain their existing animation and appearance.

Only the owning session or traffic tick advances motion. Render selection never
advances a second clock. Absolute distance drives each wheel using its declared
radius and axis, including reverse travel. Absolute gait/gesture phase survives
detail swaps. Shared animation resources are not mutated in place.

Vehicles use their authored detailed scenes within 192 m and retain them until
beyond 256 m. Every visible vehicle in range receives detail, independently of
pedestrian counts and proximity ranking. This includes port and emergency
vehicles. Pedestrian promotion begins within 18 m and demotion beyond 26 m,
with at most 16 full rigs, ordered nearest first with stable ID ties. The pool
retains up to 24 inactive/reusable allocations when fewer actors are selected;
player and occupied transit retain their separate allocation.
The population caps remain 384 vehicles, 512 pedestrians and 64 external
records. Models and ordinary walking, driving and transit work independently of optional
scripting extensions.

## Verification

`tools/tests/test_explore_model_contracts.py` and the vehicle-manifest test
validate metadata. Godot suites `test_explore_crowd_models.gd`,
`test_explore_visual_contract.gd` and `test_explore_actor_detail_tiers.gd` verify
imported geometry/motion and bounded runtime selection. Use real Godot import;
retain import settings and generated UID sidecars.

## Generator entry points

Run Blender in background mode with `--python tools/build_traffic_models.py --
--vehicles-only --skip-render --stage /tmp/traffic-models` for vehicles, or use
`--pedestrians-only` for the crowd. `--only KIND` limits the selected roster.
The player wrappers are `tools/blender_exploration/build_vehicles.py` and
`tools/blender_exploration/build_pedestrian.py`; the latter accepts
`--character man|woman`. Choose a staging directory to inspect generated assets
before replacing runtime files.
