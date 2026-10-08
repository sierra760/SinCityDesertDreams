# Disasters

## Purpose

The disaster system is the source of every catastrophe in the city: fires,
floods, riots, earthquakes, tornadoes, monsters, plant accidents, volcanoes,
hurricanes and plane crashes. It decides when nature strikes, plays each event
out day by day, turns what it touches into rubble, fire, flood water or
contaminated ground, and lets the player fight back with emergency crews. It
also owns the monthly advisor line that tells the mayor what the city needs
most.

## Inputs

Layers read: `building`, `zone`, `terrain`, `altitude`, `flags`, `pollution`,
`police`, `fire_cover`, plus `city.flood_overlay` and `city.facilities`.

Stats read: `disasters_enabled`, `population`, `average_crime`, `approval`,
`power_capacity`, `power_demand`, `water_capacity`, `water_demand`,
`unpowered_buildings`, `unwatered_buildings`, `city.difficulty`, `city.day`.

Other systems: when a `services` system is registered and exposes
`fire_strength_at(x, y)` / `police_strength_at(x, y)`, those are used for
suppression; otherwise the `fire_cover` and `police` layers are read directly.

Randomness comes only from `ctx.rng`.

## Outputs

Layers written: `building` (rubble, contaminated ground, cleared footprints),
`zone` (corner flags cleared with the footprint), `flags` (service bits cleared
on wrecked tiles), `altitude` and `terrain` (volcano cone),
`city.flood_overlay` (temporary flood water), `city.facilities` (records of
wrecked facilities removed).

Stats written: `active_fires`, `active_disaster`.

Events:

| Call | When |
|---|---|
| `report(&"disaster_started", {kind, x, y})` | a disaster begins |
| `notify(&"disaster", {kind, x, y})` | same moment, for the modal notice |
| `report(&"disaster_ended", {kind, x, y, wrecked, burned})` | the disaster is over |
| `report(&"fire_reported", {x, y})` | fires break out in a city that had none |
| `notify(&"national_guard", {})` | the city has no crews of its own and the guard sends one |
| `report(&"advisor_need", {need})` | the monthly advisor picks a need |

`mark_dirty` is called for every map change.

Public methods:

```
request(ctx, kind: StringName, at: Vector2i = (-1,-1)) -> bool
dispatch(kind: StringName, at: Vector2i) -> bool     # &"fire", &"police", &"military"
crews() -> Array[Dictionary]                          # {kind, x, y, pos}
crews_available(kind: StringName) -> int
entities() -> Array[Dictionary]                       # {kind, x, y, pos, heading, frame}; kinds tornado, monster, hurricane, plane, beam
fires() -> Array[Vector2i]
flooded() -> Array[Vector2i]
advice() -> Array[StringName]
is_emergency() -> bool
emergency_target() -> Vector2i                         # current hazard or (-1,-1); read-only
riots() -> Array[Vector2i]
active() -> Dictionary                                # copy of the running major disaster, or {}
```

## Timing

- **Daily**: every active hazard advances one step (see Rules 4–14), crews
  act, the running disaster is checked for its end.
- **Day 20 (monthly)**: the advisor need is computed, then the natural
  disaster roll is made.
- **Yearly**: contaminated ground slowly clears.
- **On networks_changed**: fires and riots on tiles that no longer hold
  anything burnable or walkable are dropped.

## Rules

### 1. Kinds

Sixteen kinds exist: `fire`, `flood`, `riot`, `hazard`, `earthquake`,
`tornado`, `monster`, `meltdown`, `microwave`, `volcano`, `firestorm`,
`mass_riots`, `major_flood`, `chemical_spill`, `hurricane`, `plane_crash`.

`fire` and `firestorm` only light fires; they never block anything and may
start while another disaster runs. Every other kind is a *major* disaster and
only one major disaster runs at a time. `stats.active_disaster` names the
running major disaster, `&"fire"` while only fires burn, and `&""` when the
city is quiet. The status bar names it in its Emergency alert.

### 2. Natural selection (day 20)

Nothing rolls while `stats.disasters_enabled` is false, while a major
disaster runs, or before the city is `NATURAL_ODDS_BY_DIFFICULTY[difficulty]`
months old. Otherwise the month has a `chance` in
`NATURAL_ODDS_BY_DIFFICULTY[difficulty]` chance of a disaster, where
`chance = 1 + population / POPULATION_PER_EXTRA_CHANCE`. On success, one kind is
drawn from `NATURAL_WEIGHTS` restricted to the kinds whose precondition holds:

| Kind | Precondition |
|---|---|
| fire, firestorm | any flammable tile |
| flood, major_flood, hurricane | shoreline (dry land touching water) |
| riot | `average_crime >= RIOT_CRIME` or `approval <= RIOT_APPROVAL` |
| mass_riots | riot precondition and `population >= MASS_RIOT_POPULATION` |
| hazard | a pollution cell at or above `HAZARD_POLLUTION` |
| earthquake, tornado | always |
| monster | `population >= MONSTER_POPULATION` |
| meltdown | a nuclear plant exists |
| microwave | a microwave receiver exists |
| volcano | ground at or above `VOLCANO_MIN_PEAK` somewhere |
| chemical_spill | any industrial building |
| plane_crash | a runway exists or `population >= PLANE_CRASH_POPULATION` |

`request` ignores `disasters_enabled`, the age gate and the city-condition
gates (crime, approval, population, pollution, high ground); it needs only the
physical ingredients (fuel, shoreline, a road, a plant, an industrial building)
and returns false when a major disaster is already running and the requested
kind is major, when the ingredient is missing, or when no place can be found
(a `hazard` with no requested point needs a polluted cell).

### 3. Damage

*Wrecking* a tile clears the whole footprint of whatever stands there
(`city.clear_footprint`), removes its facility record, clears its service
bits, and leaves rubble (`RUBBLE_1..RUBBLE_4`, chosen by rng) on every dry
tile of the footprint. Trees wrecked by wind are cleared to open ground rather
than rubble. Rubble, contaminated ground, water and open ground cannot be
wrecked again. Fires on wrecked tiles go out.

*Igniting* a tile starts a fire if the tile's spread odds are above zero and it
is not already burning.

### 4. Fires

A fire is a burning tile with an intensity (days of fuel left). Spread odds
by category come from `SPREAD_ODDS_BY_CATEGORY` (out of `SPREAD_DENOMINATOR`),
lowered by `SPREAD_FOOTPRINT_PENALTY` per tile of footprint width above one;
trees and small homes burn most readily, concrete civic buildings and
arcologies least, and roads, rails, power lines, rubble, contaminated ground
and water never burn. Fuel comes from `FUEL_DAYS_BY_FOOTPRINT` (trees use
`FUEL_DAYS_TREES`).

Each day, for each fire:

1. Fuel drops by one. At zero the tile burns out: it is wrecked.
2. Otherwise the fire may be put out. The chance out of 256 is
   `FIRE_SELF_EXTINGUISH + fire_strength / FIRE_COVER_DIVISOR`, plus
   `CREW_FIRE_ODDS` (fire crew) or `CREW_MILITARY_ODDS` (military crew) when a
   crew stands within `CREW_RADIUS`. A fire put out this way leaves the
   building standing.
3. Otherwise it tries each of the four neighbors: a neighbor ignites with its
   own spread odds.

`stats.active_fires` is the number of burning tiles. When it rises from zero,
`fire_reported` is reported once.

### 5. Riots

A riot is a tile on a road or rubble with a heading. Each day a riot with
police strength at or above `RIOT_POLICE_SUPPRESS` disperses with chance
`RIOT_DISPERSE_ODDS` (out of 256); a police crew within `CREW_RADIUS` disperses
it with `CREW_POLICE_ODDS`, a military crew with `CREW_MILITARY_ODDS`. A riot
that is not dispersed:

1. wrecks a random adjacent zone building with chance 1 in `RIOT_WRECK_ODDS`;
2. else lights a random adjacent building with chance 1 in `RIOT_IGNITE_ODDS`;
3. else moves one tile along a road or rubble (preferring its heading), with a
   1 in `RIOT_SPLIT_ODDS` chance of leaving a rioting tile behind;
4. dies on its own with chance 1 in `RIOT_FADE_ODDS`.

A `riot` seeds one riot on the nearest road to its point; `mass_riots` seeds
`MASS_RIOT_SEEDS` around it. The disaster ends when no riot remains or after
`RIOT_DAYS` / `MASS_RIOT_DAYS`, whichever is first.

### 6. Earthquake

On the first day every tile inside a square of half-width
`EARTHQUAKE_RADIUS` around the epicenter has a 1 in `EARTHQUAKE_HIT_ODDS` chance
of being struck; a struck built tile is wrecked, except 1 in
`EARTHQUAKE_FIRE_ODDS` which ignites instead. For `EARTHQUAKE_AFTERSHOCK_DAYS`
afterwards, each day has a 1 in 2 chance of wrecking one random developed tile.

### 7. Tornado

A tornado entity has a heading (eight directions). Each day it wrecks its tile,
then moves `TORNADO_STEP` tiles one at a time, wrecking each tile it crosses
(trees are simply cleared), changing heading by one step with chance 1 in 3
before moving. It ends when it leaves the map, after `TORNADO_DAYS`, or with
chance 1 in `TORNADO_VANISH_ODDS` each day.

### 8. Tsawhawbitts

Tsawhawbitts appears at a map edge and walks `MONSTER_STEP` tiles a day toward
the developed center of the city; once within `MONSTER_HOVER_RADIUS` it wanders
randomly. Each day every built tile within one tile of it is wrecked with
chance 1 in `MONSTER_WRECK_ODDS`, or ignited with chance 1 in
`MONSTER_IGNITE_ODDS`. It leaves after `MONSTER_DAYS`, or once wandering with
chance 1 in `MONSTER_LEAVE_ODDS` per day.

### 9. Floods

A flood begins at shoreline tiles near its point (`FLOOD_SEEDS`; `major_flood`
uses `MAJOR_FLOOD_SEEDS`). Flooded tiles are recorded in `city.flood_overlay`
and count as water for everything else. While the flood's remaining days exceed
`FLOOD_RECEDE_DAYS`, each flooded tile spreads each day with chance 1 in
`FLOOD_SPREAD_ODDS` to a random cardinal land neighbor that is no higher than
itself; a developed building on a flooded tile is wrecked with chance 1 in
`FLOOD_WRECK_ODDS` per day. During the last `FLOOD_RECEDE_DAYS` each flooded tile
drains with chance 1 in `FLOOD_DRAIN_ODDS` per day, and everything drains on the
final day. The disaster ends when the overlay is empty. Durations are
`FLOOD_DAYS` and `MAJOR_FLOOD_DAYS`.

### 10. Hurricane

The eye enters at a random shoreline tile and moves one tile a day toward the
developed center (heading drifts with chance 1 in 4) for `HURRICANE_DAYS`.
Each day, built tiles within `HURRICANE_RADIUS` of the eye are wrecked with
chance 1 in `HURRICANE_WRECK_ODDS` (trees cleared), and up to
`HURRICANE_FLOOD_SEEDS` shoreline tiles within `HURRICANE_FLOOD_RADIUS` of the
eye flood. The flood then behaves as Rule 9 with `HURRICANE_FLOOD_DAYS` and the
disaster ends when the water has drained.

### 11. Meltdown, chemical spill, hazard, contamination

*Contaminated ground* is the `CONTAMINATION` building id. Some contaminated
tiles are *hot* for a number of days: each day a hot tile, with chance 1 in 2,
contaminates its lowest cardinal land neighbor (wrecking whatever stood there);
the new tile is hot for one day less. Contaminated ground clears in the yearly
pass with chance 1 in `CONTAMINATION_CLEAR_ODDS` per tile, so a spill lingers
for years.

- `meltdown` needs a nuclear plant. The plant footprint is wrecked and every
  tile of it contaminated and hot for `CONTAMINATION_SPREAD_DAYS`. Every tile
  inside a square of half-width `MELTDOWN_RADIUS` is struck with chance 1 in
  `MELTDOWN_HIT_ODDS`: 1 in `MELTDOWN_FIRE_ODDS` ignite, the rest are wrecked
  and half of those contaminated. The disaster lasts `MELTDOWN_DAYS`.
- `chemical_spill` picks an industrial building, wrecks it, contaminates its
  footprint (hot) and `SPILL_SCATTER` random tiles within `SPILL_RADIUS`.
- `hazard` strikes the most polluted place (or the requested point): the
  building there is wrecked and contaminated, and its four neighbors ignite.

### 12. Microwave beam miss

Needs a microwave receiver. A beam entity starts at the receiver with a random
heading and advances `BEAM_STEP` tiles a day for `BEAM_DAYS`, igniting every
tile it crosses and wrecking built tiles that cannot burn. It ends at the map
edge or when its days run out.

### 13. Volcano

At the requested point, or the highest ground on the map, the vent rises by
`VOLCANO_RISE` levels (capped at 31) and the ground around it is pulled up
into a cone one level per ring, with slope shapes recomputed, so the cone
reaches `VOLCANO_RISE` tiles out. Everything standing on the cone is cleared.
On a city with a ground lattice the vent's corners are raised on the lattice
itself, which pulls its neighbors into the cone and is re-projected, so the
3D ground and saved vertices carry the cone; imported per-tile terrain
changes its heights directly.
For `VOLCANO_DAYS` the vent throws `VOLCANO_FIRES_PER_DAY` embers each day at
random tiles within `VOLCANO_EMBER_RADIUS`, igniting them.

### 14. Plane crash, firestorm

`plane_crash`: a plane entity enters at a map edge and flies `PLANE_STEP`
tiles a day toward the crash point (the requested point or a random developed
tile). On arrival the 2×2 there is wrecked and the ring around it ignited.

`firestorm`: `FIRESTORM_FIRES` ignitions are made in a spiral around the point.

### 15. Emergency crews

`dispatch(kind, at)` places a crew while `is_emergency()` (fires, riots or a
major disaster). Available crews: `fire` = number of fire stations capped at
`MAX_CREWS`; `police` = police stations capped at `MAX_CREWS`; `military` =
`MILITARY_CREWS` when any military building exists. When the city has no crews
at all the national guard grants one `military` crew and `national_guard` is
notified. Placing a crew beyond the limit moves the oldest crew of that kind.
A target must be a dry tile on the map. Crews act as in Rules 4 and 5 and are
all released when the emergency ends.

### 16. Advisor need (day 20)

The first matching line is the need; `advice()` returns every matching line in
this order:

1. `needs_power`: power demand exceeds `USAGE_WARNING_PERCENT` of capacity, or
   buildings are unpowered.
2. `needs_transit`: transit tiles (bus depots, rail and subway stations) are
   fewer than `population / TRANSIT_PER_RESIDENT`.
3. (population below `ADVICE_POPULATION_1`: stop)
4. `needs_police`: police stations plus prisons are no more than
   `population / POLICE_PER_RESIDENT`.
5. `needs_fire_protection`: fire stations are no more than
   `population / FIRE_PER_RESIDENT`.
6. `needs_water`: water demand exceeds `USAGE_WARNING_PERCENT` of capacity, or
   buildings are unwatered.
7. (population below `ADVICE_POPULATION_2`: stop)
8. `needs_hospital`: hospitals no more than `population / HOSPITAL_PER_RESIDENT`.
9. `needs_school`: schools no more than `population / SCHOOL_PER_RESIDENT`.
10. (population below `ADVICE_POPULATION_3`: stop)
11. `needs_seaport`: industrial tiles at least `SEAPORT_INDUSTRY_TILES` and no
    crane. On a map with no water the need is `needs_industry_connections`
    instead, and only while no road or rail reaches a neighbor (the neighbor
    system's `link_count()` is zero).
12. `needs_airport`: commercial tiles at least `AIRPORT_COMMERCE_TILES` and no
    runway.
13. `needs_recreation`: city parks + stadiums + zoos + marinas (the venues in
    `ZoneParams.RECREATION_KEYS` that raise the residential cap) fewer than
    `population / RECREATION_PER_RESIDENT`. Pocket parks do not count.

## Parameters

All values live in `DisasterParams` (`game/scripts/sim/data/disaster_params.gd`).

| Name | Tunes |
|---|---|
| `NATURAL_ODDS_BY_DIFFICULTY` | grace months and monthly odds per difficulty |
| `POPULATION_PER_EXTRA_CHANCE` | how much population adds one extra chance |
| `NATURAL_WEIGHTS` | relative frequency of each kind |
| `RIOT_CRIME`, `RIOT_APPROVAL`, `MASS_RIOT_POPULATION` | riot preconditions |
| `HAZARD_POLLUTION`, `MONSTER_POPULATION`, `PLANE_CRASH_POPULATION`, `VOLCANO_MIN_PEAK` | other preconditions |
| `SPREAD_ODDS_BY_CATEGORY`, `SPREAD_DENOMINATOR`, `SPREAD_FOOTPRINT_PENALTY` | fire spread |
| `FUEL_DAYS_BY_FOOTPRINT`, `FUEL_DAYS_TREES` | how long a tile burns |
| `FIRE_SELF_EXTINGUISH`, `FIRE_COVER_DIVISOR` | fire suppression by coverage |
| `CREW_RADIUS`, `CREW_FIRE_ODDS`, `CREW_POLICE_ODDS`, `CREW_MILITARY_ODDS` | crew effect |
| `MAX_CREWS`, `MILITARY_CREWS` | crew limits |
| `RIOT_*`, `MASS_RIOT_*` | riot behavior |
| `EARTHQUAKE_*` | earthquake area, hit odds, aftershocks |
| `TORNADO_*`, `MONSTER_*`, `HURRICANE_*`, `PLANE_STEP`, `BEAM_*` | moving disasters |
| `FLOOD_*`, `MAJOR_FLOOD_*`, `HURRICANE_FLOOD_*` | flood extent and timing |
| `MELTDOWN_*`, `SPILL_*`, `CONTAMINATION_*` | contamination |
| `VOLCANO_*` | cone size and ember rain |
| `FIRESTORM_FIRES` | firestorm size |
| `USAGE_WARNING_PERCENT`, `*_PER_RESIDENT`, `ADVICE_POPULATION_*`, `SEAPORT_INDUSTRY_TILES`, `AIRPORT_COMMERCE_TILES` | advisor thresholds |

## Save state

`save()` returns: `fires` (tile key → fuel), `riots` (tile key → heading),
`hot` (tile key → days), `flood` (tile key → depth), `flood_remaining`,
`flood_total`, `active` (kind, x, y, remaining, wrecked, burned and any
per-kind fields), `entities` (list of kind/x/y/frame/heading/target),
`crews` (list of kind/x/y/day), `advice` (list of strings) and
`outbreak_reported`. `load()` restores all of it and rebuilds
`city.flood_overlay` from `flood`.

Native JSON preserves dictionary insertion order. Daily hazard workers use that
order to assign draws from the shared random stream; sorting tile keys would
change fire, flood and contamination progression after reload.

## Finding and displaying an emergency

The footer's **Go to emergency** button and the same action in **Disasters**
center Build on a live incident. Moving entities take precedence, followed by
riot, fire, flooded and hot tiles, then a stationary disaster's epicenter.
Invalid off-map records are skipped. With no destination, the footer button is
hidden and the menu action disabled; terrain editing and blocking dialogs cannot
navigate. Explore returns to Build,
and underground/data overlays clear so the incident is visible. The action
preserves simulation speed, the selected construction tool, city data and RNG.

The 3D feedback layer uses editable Blender models made for this game for
tornadoes, monsters, hurricanes, microwave beams, riot crowds, crash aircraft
and fires. The stylized geometry shares imported mesh/material resources. Authored
eight-second Blender clips animate skeletons, morphs and local transforms with
independent playback; the monster is an original interpretation of Tsawhawbitts.
Fire uses a shared Blender-baked vertex timeline for efficient rendering of many
simultaneous fires; the standalone fire GLB retains its rig and morph animation.
The simulation retains the root position and heading. Cosmetic animation uses
wall-clock time, including while the city clock is paused. Ongoing fire playback
is retained across unrelated marker changes, with deterministic location-based
phase offsets that consume no RNG. Fire starts above the rendered building
foundation and roof, including sloped and
multi-tile lots, and follows terrain edits and demolition.
Incident geometry follows live records, reuses nodes and disappears on cleanup.
It adds no collision and consumes no simulation randomness. Crash aircraft are
kept separate from ordinary traffic, and hiding traffic does not hide disasters.
See [disaster model authoring](../art/disaster-models.md) for masters, export
conventions and source verification.
