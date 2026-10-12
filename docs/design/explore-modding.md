# Explore source packs — API 1

Open **Settings → Explore Mods**, or **Explore menu → Explore Mods**. The five
built-in packs are disabled initially. Import a source folder or a `.scddmod`
ZIP archive by entering its path; `.zip` archives are also supported. Each pack
must contain manifest.json at its root. Imports stay disabled. Select
Enable, close the window, then Resume Explore (or enter Explore from Build).
Only your local preferences choose packs; loading a saved city never enables one.
Eight packs can be enabled. A ninth Enable reports the session limit.

The panel lists names, versions, states and runtime availability. Reload reads
the selected pack's edited source while Explore is suspended, validates a whole
snapshot, then publishes a fresh version directory. Other packs keep their VM,
actors and timer phase. A malformed edit preserves the prior installed snapshot;
Resume restarts that snapshot if validation had freed its VM slot. Old handles
are invalid. A pack with no live slot cannot validate a reload while all eight
other VMs are live. Disabled source import still works at capacity. An import
validates files; Lua is compiled only on explicit activation/reload.

Reset progress requires a second Confirm reset click and clears only that
pack's committed state in the current city. It uses the same progress object as
Save, autosave, recovery and Share. Save the city afterward to retain that reset.
Disable removes that owner's actors, interactions, objectives, queries, timers,
effects and pending callbacks. An occupied vehicle transfers safely until exit.
Copy diagnostics gives a bounded text report. Never include secrets in logs.

## A pack

```json
{"id":"my_walk","name":"My Walk","version":"1.0.0","api_version":1,
 "state_version":1,"entry":"main.lua","priority":0,
 "description":"An outdoor walk."}
```

IDs use lowercase ASCII letters, digits, dots and underscores, at most 64
characters. Versions use semantic version syntax. State versions are positive
integers. Priority is an integer 0–100. Duplicate IDs are refused/disabled with a
diagnostic; no arbitrary winner runs. Only UTF-8 .lua and .json files are allowed.
No bytecode, symlinks, traversal, ambiguous ZIP paths or Godot resource packs.
Manifest ≤16 KiB, each file ≤128 KiB, ≤32 files and ≤1 MiB uncompressed per pack.

```lua
return {
  on_start = function(api)
    api.objective.set("hello", "Enjoy your walk.", "active")
  end,
  on_event = function(api, event)
    if event.kind == "timer" and event.key == "hello" then
      api.utility.log("Active Explore time passed")
    end
  end
}
```

Entry returns optional on_start, on_tick, on_event, on_resume and on_stop
functions. Handlers return nil. on_tick(api,context) receives context.delta in
active Explore seconds; on_event(api,event,context) also accepts a third argument.
All Lua modules compile before start; require resolves only the immutable pack
snapshot. Cycles fault. JSON is inert data, not a dynamic loading API. Dot calls
are required. The accompanying **api_v1.lua** lists every exact function and
argument/result shape. It is documentation, outside individual source packs.

## Results, ownership and coordinates

Queued calls return `{ok=true,code="pending",request_id=n}`. Match completions by
request_id in on_event: action_completed/action_failed/query_completed contain
code, data and optional logical key. Immediate rejection is `{ok=false,code=...}`.
World queries may return cached `{ok=true,code="ok",data=...}` immediately, so
handle both shapes when reissuing queries. Errors include no_route, unavailable,
invalid_argument, quota_exceeded, stale_id, wrong_owner, player_controlled and
stale_geometry. Failure is ordinary data; leave a useful objective and idle when
no connected route exists. Do not retry every frame.

Positions are copied `{x,y,z,coordinate_space="tile",geometry_revision=n}` points.
One tile is sixteen source-model metres. Engine support, collision and connected
road/rail/water/air routes are authoritative. Query lists contain at most 64
items. Queries inspect ≤256 nodes per step and ≤4,096 total. Handles belong to
one owner and session; retain logical keys in saved progress, never actor handles,
world poses, pending requests or transaction state. Player-controlled vehicles
refuse scripted movement. Script actors share ordinary traffic admission caps.
No custom-model or marketplace API exists in API 1.

`world.find_landmark(kind, options)` searches the connected route graph breadth
first. Kinds are road_destination/road/sidewalk (a road cell at least three tiles
away), park and station (a road cell beside one). Optional fields: `kind` selects
the actor domain (default pedestrian); `from` starts at a supported point instead
of the copied player; `min_distance` (0–40 tiles, straight-line from the start)
asks for a farther stop; `away_from` (a point) requires the stop to be at least
half that distance farther from it than the start is, so chained stops keep
moving outward; `skip` (integer 0–32) passes over that many earlier matches to
vary destinations. Success data adds `distance`, the route length in tiles.
Results are cached per exact arguments until geometry changes, so pass an
explicit `from` when the start moves. An unreachable request returns no_route.

`world.player()` returns the copied player point plus `mode` (0 on foot, 1 road
vehicle, 2 aircraft), `vehicle` (this pack's own handle when the player drives a
vehicle it spawned, otherwise ""), `speed` (horizontal tiles per active second)
and `heading` (`{x,z}`, the camera's level view direction). Compare a target's
offset with heading to phrase guidance as ahead/left/right on screen.

Actor functions spawn, inspect, navigate, wait, wave and remove catalog actors.
Interactions register proximity prompts. The nearest target wins; exact distance
ties use pack ID, then interaction key, in lexical order. Dialogue supports at
most eight choices.
Objectives use active/completed/failed; complete with objective.set, not a
separate complete function. Timers run after 0.1–86,400 active Explore seconds.
Environment channels are daylight (day/dawn/dusk/night), haze (clear/desert/fog),
wind (calm/breeze/gust), precipitation (none/dust/rain); intensity is finite 0–1.
Highest priority wins each channel, lexical ID breaks ties. Interior masking
preserves outdoor requests. Disable/leave restores baseline visuals. Effects never
write simulation weather, city grids, funds, statistics, incidents or RNG.

## Clocks, limits and saved progress

City simulation time, active Explore time and visual rendering time are distinct.
City pause does not stop scripts. Explore pause, menus, dialogue, focus loss and
backgrounding freeze script timers and callbacks. Scripts run at 10 Hz with at
most 32 callbacks/64 commands per session tick, 20,000 instructions per callback
and 100,000 instructions per tick. Each tick has a 1.5 ms window for starting
callbacks: a callback starts only while at least 400 µs of it remain, and the
rest waits for the next tick. Once started, a callback is limited by its own
thread CPU time (1.5 ms), not by the window, so time the operating system
spends elsewhere (preemption, a loaded machine) never faults a healthy pack. A
50 ms wall-time backstop still ends any callback that stalls. Limits are checked
every 200 instructions and at each API call; exceeding a time limit faults with
`deadline`. On Windows, per-thread CPU time is too coarse to enforce, so only the
instruction limits and the wall backstop apply there. Each VM has 8 MiB. There
are at most eight live VMs, including candidate validation; no temporary ninth
VM is allowed.

Per pack: 16 actors/timers/interactions/markers, 8 objectives, 32 pending commands,
128 queued events, 64 KiB progress. Globally: 64 script actors within the existing
384-vehicle/512-pedestrian and 64-external-record caps. Payloads ≤8 KiB/1,024 nested
entries, strings ≤4 KiB, dialogue ≤2 KiB, JSON depth ≤8. Progress total ≤512 KiB/64
owners. state.set stages top-level replacements; only host-accepted writes are
saved. Disabled/missing pack progress remains inert. A state_version mismatch
preserves data but refuses start until explicit Reset; no implicit migrations.
Normal on_stop permits only state.get/state.set/utility.log. Faults discard the
failing callback's output and clean up without calling on_stop.

Lua has no OS, IO, package, debug, coroutine, bytecode, dynamic loader, metatable
mutation or protected-call helpers. String/pattern/sort operations are restricted;
see the exact reference. utility.random uses a private deterministic generator,
not the city random stream. Never attempt network/filesystem access from Lua.

## Examples and supported targets

The Pedestrians pack creates three distinct walkers in sequence, requests outdoor destinations,
walks, waits and requests a wave, and offers a greeting. Missing routes leave it
idle with an objective. Nearby detailed walkers perform the wave on their owned
Explore clock; demotion and promotion retain the sampled gesture phase. The
three-wave routine and greeting preserve city simulation and RNG state.
Each follower starts after the preceding walker reaches its stop and waits, or
settles into safe failure. Followers set out from the leader's starting point,
not wherever the player has since gone, so the far-to-near stops stay in order.
A failed spawn has one delayed retry, never a frame loop.

Desert Dispatch (`desert_delivery`) runs delivery shifts. Marisol, the
dispatcher, offers an easy shift (three parcels at your own pace) or an express
shift (each parcel on a clock set by its route length, with bigger tips), and
lends a Delivery Van. Each parcel has a recipient, a thank-you line and
sometimes a rule: fragile parcels lose tip for hard braking or collisions, hot
parcels are always timed, and steady parcels lose tip for driving flat out.
Addresses are measured from the van and grow farther each parcel (about 10, 14
and 18 tiles, falling back to nearer stops on small road networks); later stops
continue away from the previous one. The tracked objective shows the parcel,
straight-line distance and screen-relative direction, the clock and any penalty.
Arriving in the van opens the recipient's thanks with the tip breakdown. Tips,
courier ranks (Rookie Runner to Desert Legend) and shift records are saved per
city; a shift in progress is not, so reentry offers a fresh shift. Version 1
progress counts as one delivery. If no van space is free beside the player, the
van parks a few tiles down the road. Transient startup refusals retry twice,
after 3 then 6 active seconds; exhausted recovery explains how to restart while
keeping the record. Acceptance removes only Dispatch's courier; each recipient
waves and leaves after delivery, freeing shared sidewalk slots. It never awards
or spends city funds.

Neon Rally (`neon_rally`) is a checkpoint time trial. Flagger Fran offers a
Sprint (three checkpoints) or a Grand Tour (five), places a waving marshal at
each chained checkpoint and lends a Desert Cruiser. The countdown starts when
the player is driving; rolling early costs two seconds. Dusty Dan races the same
course in a scripted pickup through ordinary traffic rules; the objective shows
the next checkpoint, distance, direction, race clock and place. Par comes from
the course's route length; 100% of par earns gold, 80% silver, 62% bronze.
Medals, best run and the record against Dan are saved per city.

Find the Crooner (`crooner_hunt`) is on-foot hide-and-seek. Lou Lamarr's
headliner hides on a nearby sidewalk; the objective reports how warm the search
is, whether you are getting warmer or colder, finds so far and the time left in
a three-minute show. Every 35 seconds a fan hints at his direction. Catching
him (interaction on foot) adds ten seconds and he hides again a little farther
away; after the first find he may spot you and walk off to a new spot. Best
show and totals are saved per city.

The five built-ins can coexist at one entry; walkers may wait safely behind the
other packs' actors until normal handoffs clear the street. A stationary blocker
or absent route is never bypassed or silently removed by another pack. Packs
with no usable route explain that in a failed objective and offer nothing.
The Weather Effects pack blends dusk/haze intensity using active seconds and alternates
bounded dust/rain on an active timer; interiors mask effects and disable restores
baseline appearance.

Native targets are macOS universal and Windows x64. The panel explicitly labels
unsupported platforms or a missing runtime; ordinary Explore and source pack
configuration remain usable. A cross-built Windows library still requires runtime verification on Windows. Mobile/web native execution is unavailable. Custom model formats and additional platform runtimes are future extensions
outside API 1.


## Development checks

Run focused tests from the repository root with the Godot executable selected
through `GODOT`. The runner copies the game to a temporary project with unique
user data and performs a real import. `TEST_LOG_DIR` retains diagnostic logs.
Each suite requires a nonempty zero-failure Results summary, successful exit,
and no engine, script or resource diagnostics.

```sh
GODOT="$SCDD_GODOT" python3 tools/run_tests.py test_explore_mod_ test_explore_actor_gestures.gd test_explore_actor_detail_tiers.gd
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -p no:cacheprovider tools/tests/test_explore_lua_source_lock.py tools/tests/test_run_tests.py
```

The mod suites exercise restricted Lua, pack validation, scheduling, ownership,
navigation, environment restoration, management, persistence and the five
examples; `test_explore_mod_minigames.gd` plays a full Dispatch shift, a rally
and a Crooner search on a road loop. `test_explore_mod_boundary.gd` checks simulation and RNG isolation;
`test_explore_mod_save_paths.gd` checks manual, autosave, background and shared
copies. Existing Explore, traffic and save suites cover integration regressions.
Headless tests complement actual walking, driving, dialogue and visual-effect
checks in both Mobile and Compatibility renderers. Native runtime verification
must exercise both macOS architectures and actual Windows execution; a successful
cross-build alone does not verify the Windows runtime.


## Navigation markers

Explore's north-up corner map follows the player at a street-level zoom, with
heading, a distance scale and pins for nearby or tracked targets. **Map** (default
**M**, rebindable in Controls) opens a larger map. Explore movement, script
callbacks and game timers pause while browsing; the city clock keeps its current
speed. Drag to pan, wheel/pinch or **− / +** to zoom, **Find me** to center on the
player, and **Whole city** for the overview. Close, the map key or Escape returns
to the prior Explore pause state. Phones keep a Map button even when the small
map cannot fit or View → Minimap is off.

```lua
-- After an actor.spawn completion gives this pack its own actor handle:
api.marker.set("recipient", {
  target = {id = recipient_id}, label = "Parcel recipient", icon = "objective"
})
-- Fixed locations, including a building/object's known tile point:
api.marker.set("gate", {
  target = {x = 20.5, y = 1.2, z = 30.5},
  label = "Finish gate", icon = "checkpoint", height = 0.5
})
api.marker.remove("recipient")
```

`marker.set(key, options)` and `marker.remove(key)` use ordinary queued action
results/completions. Keys are nonempty, at most 128 UTF-8 bytes, scoped to the
pack. Setting a key replaces its pin; removing it is idempotent. `target` is an
owned live actor `{id=handle}` or a finite tile point inside the map (`x/z`
0–128, `y` within −1024–1024). Bad handles return stale_id; another owner's
handle returns wrong_owner. Fixed positions can mark any known object or
objective without giving Lua scene access.

Options: `label` (default empty, at most 192 UTF-8 bytes), `icon` (objective,
person, vehicle or checkpoint; default objective), `map` and `world` (booleans,
default true), `max_distance` (0–2048 tiles, default 2048), `height` (additional
0–8 tiles of vertical lift, default 0). Range is measured from the occupied
player and applies to both map and overhead display, including the expanded
map. Shapes distinguish pin types as well as their colors. Overhead pins show
distance in metres/kilometres, stay legible over geometry and follow model tops;
behind-camera targets remain on the map. World labels are bounded and placed
nearest first to avoid covering the HUD. Outdoor markers are hidden indoors.
A player-occupied vehicle temporarily hides its own pin until exit.

Each pack may keep 16 markers, with 128 across the session. Actor pins resolve
their actual pose in the host every rendered frame; scripts do not poll to keep
them aligned. Actor removal, disable, fault, reload, city replacement and leaving
Explore remove transient pins. Save logical keys/progress, never marker poses or
handles. Resource diagnostics include the marker count.

Desert Dispatch marks Marisol, the Delivery Van and the current recipient. Neon
Rally marks Fran, the cruiser and only the next checkpoint. Find the Crooner
marks Lou and reveals the headliner only within two tiles (32 metres), preserving
the hot/cold search even when the player opens the full map.
