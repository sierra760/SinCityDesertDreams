# Architecture

Sin City: Desert Dreams is a Godot 4.6 project. Everything that matters lives
under `game/`. This document describes the layers, the data model and the
contract between the simulation and the rest of the game. Read it before adding
a system or touching the save format.

## Layers

```
game/scripts/
  core/      city model, catalogs, clock, RNG, the Simulation node, system base
  sim/       one file per simulation system; sim/data holds authored parameters
  content/   written content: news stories, advisor lines, names
  io/        .sc2d save format, .sc2 import, city generator hand-off
  terrain/   terrain surface, generation, editing
  view/      3D city presentation, analytical geometry, shared materials, minimap
  traffic/   ambient vehicles and pedestrians, the read-only traffic graph, vehicle catalog
  exploration/  session actors, physical traversal, input and third-person camera
  input/     ControlBindings: rebindable keyboard bindings shared by Build and Explore
  platform/  MobilePlatform (display readings, file pickers, first-run defaults),
             CitySharePlatform (system share sheet)
  ui/        toolbar, menus, windows, dialogs
```

Dependencies point downward only. `sim/` never imports `view/` or `ui/`.
`view/` reads the city model but never mutates it. `ui/` talks to the
simulation through `Simulation` and `CityStats`, and to construction through
`Builder`.

## The city model (`core/city.gd`, class `City`)

A `City` is a plain `RefCounted` holding the map and its metadata. The map is
128×128 tiles. Layers are flat arrays indexed `y * width + x`: byte layers are
`PackedByteArray`s wrapped by `Grid8`, and `altitude` is a `Grid16` (16-bit
values held in a `PackedInt32Array`).

| Layer | Resolution | Meaning |
|---|---|---|
| `terrain` | 128² | slope shape (low nibble) and water kind (high nibble); see `Terrain` |
| `altitude` | 128² | ground height 0–31 in the low five bits, water height in the next five, tunnel bits above |
| `building` | 128² | building id from `Buildings`, `0` = nothing; every tile of a footprint carries the id |
| `zone` | 128² | zone kind (low nibble) and footprint corner flags (high nibble); see `Zones` |
| `flags` | 128² | service bits: powered, watered, conducts power, conducts water, salt water, protected |
| `underground` | 128² | pipe/subway network code, `0` = nothing |
| `traffic`, `pollution`, `land_value`, `crime` | 64² | one byte per 2×2 block |
| `police`, `fire_cover`, `density`, `growth` | 32² | one byte per 4×4 block |

Metadata: `name`, `mayor`, `founded_year`, `day` (days since founding),
`funds`, `difficulty`, `rotation`, `sea_level`, `status` (settlement class),
`signs` (tile → text), `street_naming` (applied street names and automatic
station names), and `terrain_surface` (the shared-vertex lattice used by
terrain editing). Optional `imported_power_links` keep conductive links from
imported classic cities, and `terrain_origin` records where real-world terrain
came from.

`City` also owns the persistent **facility records**: one `Dictionary` per
placed civic building (power plants, stations, service buildings, arcologies)
keyed by anchor tile, holding age, capacity and per-building counters. Systems
store per-building state here rather than in parallel arrays.

The model has no simulation logic. It has accessors, footprint helpers and
nothing else.

## Catalogs (`core/`)

- `Buildings` – the building roster. Ids are stable small integers. Each entry
  has a `key` (StringName), display `name`, `size`, `category`, `cost` and the
  simulation parameters the systems read (population capacity, power draw,
  pollution output, land-value effect, flammability, service radius...).
- `Zones`, `Terrain`, `TileFlags` – enums and bit helpers.
- `Tools` – the construction tool list used by the toolbar and `Builder`.

Building ids are stored in saves and imported cities and key the 3D model
catalog (`game/assets/desert-dreams-3d/catalog.json`), so they never change.

## Time (`core/game_clock.gd`)

A year has 12 months of 25 days (300 days). The clock advances one day at a
time; the `Simulation` decides what runs on which day. Speeds are
`PAUSED`, `SLOW`, `MEDIUM`, `FAST`, `FASTEST`.

## Simulation (`core/simulation.gd`, class `Simulation`, a `Node`)

The only object the UI drives. It owns a `City`, a `CityStats`, a `SimRng`, the
clock and an ordered list of `SimSystem` instances.

Public methods:

```
setup(city: City, seed: int = -1, stats: CityStats = null,
      restored_snapshot: Dictionary = {}) -> void   # a save's snapshot; power sets up from it
advance_day() -> void            # one day, synchronous
set_speed(speed: int) -> void
get_system(key: StringName) -> SimSystem
networks_changed(rect: Rect2i = Rect2i()) -> void   # after construction
request_disaster(kind: StringName, at: Vector2i = Vector2i(-1,-1)) -> bool
snapshot() -> Dictionary         # everything needed to resume, JSON-safe
restore(data: Dictionary) -> void
```

Signals:

```
day_advanced(year, month, day)
month_ended(year, month)
year_ended(year)
funds_changed(funds)
population_changed(population)
budget_review_due(year)          # January, pauses until UI calls finish_budget_review()
news_published(story: Dictionary)
notice_raised(kind: StringName, payload: Dictionary)
disaster_started(kind, center)
disaster_ended(kind)
map_changed(rect)                # buildings or terrain changed by the sim
speed_changed(speed)
```

### Daily schedule

Each day the simulation calls `daily(ctx)` on every system, then runs the
scheduled monthly jobs. The month is 25 days; jobs are spread over it so no
single day stalls the frame:

| Day of month | Job |
|---|---|
| 1 | power distribution |
| 3 | water distribution |
| 5 | zone growth, first half of the map |
| 6 | zone growth, second half |
| 8 | traffic and transit routing |
| 10 | pollution, land value, crime maps |
| 12 | service coverage (police, fire) |
| 14 | population, education, health |
| 16 | economy: demand, industry sectors, national trends |
| 18 | budget accrual, ordinances, transport wear |
| 20 | disasters roll |
| 22 | statistics, graphs, newspaper |
| 24 | neighbors and regional |
| 25 | rewards, ports |

`monthly(ctx, phase)` runs on each day listed for that system; `phase` is 0 on
the first listed day and 1 on the second, which is how zone growth splits the
map. `yearly(ctx)` runs on the last day of December before the budget review.

### `SimContext`

Passed to every system call. Holds `city`, `stats`, `rng`, `clock`, `events`
and `systems`, so a system can look another up with `ctx.system(key)`. Tiles
the renderer must refresh are marked with `events.mark_dirty(rect)`.

### `CityStats` (`core/city_stats.gd`)

Typed scalar state: demand, population, cohort array, utility totals, the
quality indices, tax rates, funding levels, bonds, ordinance flags, the
budget ledger, histories for the graph windows. Every field is a real property.
There is no untyped grab-bag dictionary; if a system needs state, it adds a
typed field (or keeps private state in its own `save()`/`load()`).

### `SimSystem` (`core/sim_system.gd`)

```
var key: StringName
func setup(ctx: SimContext) -> void
func daily(ctx: SimContext) -> void
func monthly(ctx: SimContext, phase: int = 0) -> void
func yearly(ctx: SimContext) -> void
func networks_changed(ctx: SimContext, rect: Rect2i) -> void
func save() -> Dictionary
func load(data: Dictionary) -> void
```

Systems must be deterministic given the same `City`, `CityStats`, seed and
input sequence. They draw randomness only from `ctx.rng`.

### Events (`core/city_events.gd`)

A small queue on `SimContext`. Systems push `report(kind, args, priority)` and
`notify(kind, payload)`; the `Simulation` drains the queue after each day and
emits the corresponding signals. The newspaper system turns news events into
stories using `content/`.

## Construction (`core/builder.gd`, class `Builder`)

All player edits go through `Builder`: it validates, prices, applies the change
to the `City`, debits funds, records facilities, and calls
`Simulation.networks_changed`. `preview` and `apply` return a plan Dictionary
with `ok`, `cost`, `tiles`, `rect` and `reason`; `apply` adds `applied`, and a
plan that needs the player's answer first comes back with `needs_confirmation`
and nothing charged. The UI never writes to grids directly.

## Persistence (`io/save_format.gd`)

Native saves are `.sc2d`: a JSON document with a `format`, `version` and
`stage`, a header for the load list, the city (metadata, each layer as base64
of a deflate-compressed buffer, facilities, signs, `street_naming` and
terrain), and `snapshot` from `Simulation.snapshot()`, which holds `stats` and
one entry per system from `SimSystem.save()`. A save without a valid `stage`,
`street_naming` or terrain fails to load. Loading calls `restore` and the
systems' `load`. Unknown system keys are ignored; missing keys get defaults.
See [File formats](file-formats.md).

`.sc2` city files can be imported into a `City` by `io/sc2_import.gd`. Export
back to `.sc2` is not supported.

## Presentation (`view/`)

`CityPresentationController` owns map gestures, tool selection, data-layer and
surface/underground state. Its cursor preview is plain state rather than a
hidden canvas renderer. `ConstructionFlow` (`ui/construction_flow.gd`) applies
completed drags through `Builder` or, before founding, `TerrainEditor`, and
runs the bridge/tunnel, neighbor-link and objection prompts.

`CityView3D` reads the city to build terrain, networks and buildings from the model catalog.
Static buildings and networks use separate mesh-batching visibility domains.
`CityOverlaySampler` reads the eleven city data layers; `CityOverlay3D` and
`CityUnderground3D` draw batched analytical geometry. These views change visibility
and picking without mutating the city. `CityFeedback3D` reads normalized entity
records for vehicles, disasters and crews, and draws selection feedback and labels.

`DisplayLayout` is the single display-scale owner. UI coordinates are logical;
the full-window 3D texture uses drawable pixels. Projection and picking convert
through this owner once. `MiniMap` binds directly to the city and 3D view, and
fits inside the measured menu, status and toolbar margins.

The player scene has no 2D city renderer or 2D camera. `MiniMap` colors one
pixel per tile, and `RotationMapper` converts between its rotated grid and city
tiles. Display preferences live outside city saves.

## Exploration (`exploration/`)

Exploration reuses the CityView3D world, render target, lighting and model
catalog. It adds session-only actors without a second city or simulation.

`ExploreModeSwitch` (`ui/explore_mode_switch.gd`) owns entry from
**View → Explore City**, cancels construction gestures and captures the builder
camera, tool and analytical presentation. It applies the
usual modal rules and gates construction, aerial navigation and data-layer
changes during Explore. Returning to Build restores that snapshot. The
CityPresentationController suspends construction input; CityView3D hands the
camera over to the perspective exploration camera so aerial refresh/resize does not
overwrite it.

| Owner | Responsibility |
| --- | --- |
| `CityExplorationController` | Walk/Drive/Fly session transitions, native input ownership, nearby-vehicle interaction, safe exits, automatic recovery to nearby support, the Recover action (always the nearest outdoor road; the player leaves a vehicle that cannot fit there), actor disposal and explicit suspension/resume. |
| `CityTraversalWorld3D` | Physical terrain/network projection, support and clearance queries, water-volume classification and bounded safe-position searches. Geometry follows city revisions rather than rebuilding each render frame. |
| `ExplorePedestrian`, `ExploreCar`, `ExploreHelicopter` | Swept actor movement and each actor's visual model. They read traversal geometry and input frames and never touch the simulation or the save. |
| `ExploreRouteVehicle`, `explore_marina_access.gd` | Player-driven trains, subways and boats along routes from the read-only traffic graph; boarding a boat at a marina and leaving it beside the marina or a clear shoreline. |
| `exploration/transit/` (`ExploreTransitService`, `ExploreTransitWorld3D`, `ExploreTransitTrain`, `ExploreStationInterior`) | Riding a local train or subway as a passenger: station platforms, lifts and tunnel space, carriages with walkable floors and doors, station furnishings and destination choice. Boarding is by walking aboard, not a key. |
| `CityExploreCamera3D` | Third-person follow, mouse orbit, recentering and physical obstruction handling. |
| `ExploreHUD` | Fixed mode/speed/flight-altitude/F prompts, separately scrolling feedback, and a compact side panel laid out through DisplayLayout: Resume, Recover, Return to Build, Reset camera, a vehicle picker, a destination picker while waiting at a station, and Control settings. Look sensitivity and invert-Y are in Settings → Controls. |

Terrain queries use mask 1 and lot queries mask 2. Movement
uses building shells on 4, physical floors on 8 and additional obstacles
on 16; exploration actors occupy 32. Floor support and water checks use actor
height, allowing a supported bridge crossing or flight above water. Where the floor
height jumps by more than the step allowance, the actor is recovered to a safe
spot rather than given a larger step, and the city geometry is left alone. Collision rebuild timing
fields are observational and never feed geometry or movement decisions.

Apart from Escape, the keys below are defaults that `ControlBindings` lets the
player rebind in Settings → Controls; the arrow keys are alternates for WASD
movement.
Walking uses camera-relative WASD, Shift sprint and Space jump. Driving uses W
acceleration, S braking/reverse, A/D steering and Space handbrake. Flight uses
WASD horizontal motion, Q climb and E descent. F enters a nearby vehicle
or requests a stopped/landed exit with clearance. Mouse motion orbits; Escape
releases capture and opens the panel, and pressing it again resumes. Focus
loss, menus and dialogs clear held movement. A notice or dialog that suspended
the session resumes it automatically once it closes, unless a report or
Settings window is still open; after Escape, the touch Menu, focus loss or a
menu-bar menu, Explore waits for Resume. F11 is still handled by Main, and
Escape in Explore does not exit fullscreen. Critical mode, speed, flight altitude
and F interaction prompts stay outside the message scroll container so they
remain readable while pointer capture prevents scrolling. Longer feedback can
scroll independently; the controls use a compact side panel.

Simulation speed is independent of actor movement. While the city is paused,
exploring leaves the city, simulation state and random numbers exactly as they
were; actors never write to them. City saves use the normal format and never
store actor poses. Saving can occur in Explore; loading, importing, founding or closing a
city disposes the session and returns to Build. Exploration camera transforms do
not replace saved builder preferences. Sensitivity and invert-Y remain ordinary
display preferences outside the city save.
