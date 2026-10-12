# Explore source packs — API 1

Open **Settings → Explore Mods**, or **Explore menu → Explore Mods**. The three
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

Actor functions spawn, inspect, navigate, wait, wave and remove catalog actors.
Successful spawn completion contains `{id,position}`; position is the actual
admitted copied actor pose in tile coordinates, including its supported height.
For pedestrians, `near_player=true` searches for a vacant supported road slot
around `options.position` when provided, otherwise around the copied player
position. The anchor must itself have valid support and matching height (within
0.15 tile). Search is breadth first, anchor first, in the road graph's stable
neighbor order, within four connected road edges and at most 32 inspected cells.
Every inspected cell consumes the shared 256-node step budget. Exhaustion returns
quota_exceeded; no safe slot returns no_route. It never crosses unsupported cells
or bypasses traffic occupancy, owner/global/shared actor caps. A provided
position without this opt-in retains the existing exact cell/height admission;
no nearby substitution occurs. Vehicle admission remains unchanged.
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
most 32 callbacks/64 commands per session tick, 20,000 instructions per callback,
100,000 instructions and 1.5 ms aggregate script work per tick. Deadlines are
checked every 200 instructions. Each VM has 8 MiB. There are at most eight live
VMs, including candidate validation; no temporary ninth VM is allowed.

Per pack: 16 actors/timers/interactions, 8 objectives, 32 pending commands,
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
settles into safe failure. This keeps the existing far-to-near stops from blocking
the leading walker. A failed spawn has one delayed retry, never a frame loop.

Parcel Delivery offers acceptance/decline, lends a catalog car, tracks player
arrival on a connected route, and saves accepted/completed phase only. Reentry
recreates safe actors without offering an already accepted task again. It never
awards or spends city funds. Missing landmarks leave the mission safely idle.
Recipient admission may choose a nearby supported vacant slot around the landmark;
guidance and arrival refer to that actual recipient location. Transient startup
refusals retry missing resources twice, after 3 then 6 active seconds. Exhausted
recovery explains how to try a clear connected street and restart the pack while
keeping accepted/completed progress. Unchanged Resume preserves the live VM and
does not restart or reset recovery. Acceptance removes only Delivery's courier;
completion removes only its recipient, freeing shared sidewalk slots. The three
built-ins can coexist at one entry; walkers may wait safely behind the mission's
actors until these normal handoffs clear the street. A stationary blocker or
absent route is never bypassed or silently removed by another pack.
The Weather Effects pack blends dusk/haze intensity using active seconds and alternates
bounded dust/rain on an active timer; interiors mask effects and disable restores
baseline appearance.

Native targets are macOS universal and Windows x64. The panel explicitly labels
unsupported platforms or a missing runtime; ordinary Explore and source pack
configuration remain usable. A cross-built Windows library still requires runtime verification on Windows. Mobile/web native execution is unavailable. Custom model formats and additional platform runtimes are future extensions
outside API 1.
