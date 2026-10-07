# Traffic and transit

## Purpose

The transport system decides whether the city's residents can get to work
and shops, how crowded the roads become while they try, and how many of
them ride the bus, the train or the subway. Once a month it sends a trip
from residential lots toward the nearest commercial or industrial lot over
the road, highway, rail and subway networks. Trips that arrive leave
congestion on the road tiles they drove along and are counted as riders on
any transit they used. Trips that cannot arrive are counted as unreachable,
which the zone system reads as monthly city-wide pressure on residential growth
and reoccupation and as increased risk of residential decline. Successful bus,
rail and subway trips remove this pressure just as successful road trips do.

## Inputs

- `building` layer: roads, highways, ramps, bridges, tunnel entrances, rail,
  subway portals, bus depots, rail stations, subway stations, and the
  residential, commercial and industrial lots that trips start from and end
  at.
- `zone` layer: footprint corner flags, used to find lot anchors.
- `underground` layer: subway tunnels, pipe/subway crossings and station
  links (the code table is defined in `docs/simulation/water.md` and exposed
  by `UtilityParams`).
- `altitude` layer: tunnel bits, which make the tiles under a hill passable
  between two tunnel entrances.
- `traffic` layer: last month's congestion, decayed before new trips are
  added.

## Outputs

- `traffic` layer (64×64, one byte per 2×2 block): congestion, 0–255.
- `stats.average_traffic`: mean congestion of the blocks that carry any
  traffic at all, 0 when no block does.
- `stats.history[&"riders_bus"]`, `[&"riders_rail"]`, `[&"riders_subway"]`:
  one sample per year with that year's rider totals, written in `yearly()`.
- Getters other systems and the UI call:

  | Method | Meaning |
  |---|---|
  | `unreachable_ratio() -> float` | share of last month's trips that failed to arrive, 0.0–1.0 |
  | `ridership() -> Dictionary` | `{bus, rail, subway}` riders so far this year |
  | `monthly_ridership() -> int` | riders of all kinds carried by last month's pass; the budget system charges a fare per rider |
  | `monthly_riders_by_mode() -> Dictionary` | `{bus, rail, subway}` for last month's pass |
  | `trips_attempted() -> int`, `trips_completed() -> int` | last month's counts |
  | `states_searched() -> int` | search work of last month's pass |
  | `trace_trip(city, anchor) -> Dictionary` | route one trip from a lot without touching the map: `{reached, cost, tiles, highway, bus, rail, subway}` |
  | `reachable(city, anchor) -> bool` | shorthand for `trace_trip(...).reached` |

- News: `traffic_jam` `{average}` when `stats.average_traffic` reaches
  `JAM_LEVEL`, at most once every `JAM_COOLDOWN_MONTHS`.

## Timing

- Monthly, day 8: decay congestion (rule 8), then route trips (rules 1–7),
  then publish `stats.average_traffic` and the jam story.
- Yearly: record the three rider series into `stats.history` and reset the
  yearly counters.
- Nothing runs daily or on `networks_changed`; trips always read the current
  map.
- Growth on days 5 and 6 reads the preceding day-8 result. A route repair is
  reflected by the next transport pass, then by the following growth pass.
  This sampled aggregate pressure does not assign a separate failure to every
  household. Unattempted origins are not counted as failed trips.

## Rules

1. **Origins.** Every developed residential lot (any building of the
   residential category, picked once by its north-west corner flag) is a trip
   origin, starting from the lot's anchor (`City.anchor_of`); a city saved at
   another rotation carries that flag on another corner of the lot. When there are more than `TRIPS_PER_PASS` origins the pass routes
   an evenly spaced sample of `TRIPS_PER_PASS` of them, starting from an
   offset that advances by one each month so every lot is routed in turn.
   Each trip in a sampled pass carries weight `min(SAMPLE_WEIGHT_CAP,
   ceil(origins / sampled))` times the lot's weight (rule 6) so congestion
   stays representative of the whole city.
2. **Entrance.** A trip starts on the first tile, searched ring by ring out to
   `ENTRANCE_REACH` tiles around the lot's footprint, that holds a road, a
   road bridge, a tunnel entrance, a level crossing, a highway ramp, a bus
   depot, a rail station or a subway station. Plain highway lanes and plain
   rail do not admit a trip. A lot with no entrance fails without searching.
3. **Travel modes and steps.** A trip is a search over (tile, mode) states.
   Each step onto a neighboring tile (four cardinal directions) costs the
   step price of the mode it arrives in; a trip may spend at most
   `TRIP_BUDGET`. The search always expands the cheapest pending state first,
   so the first arrival is the nearest destination by travel cost.

   | Mode | Moves onto | Step price |
   |---|---|---|
   | car | road, road bridge, tunnel entrance, level crossing, highway-over-road, tile with tunnel bits | `ROAD_STEP` |
   | car | highway ramp | `RAMP_STEP` |
   | highway | highway lane, highway bridge, highway slope or corner, interchange | `HIGHWAY_STEP` |
   | highway | highway ramp | `RAMP_STEP` |
   | bus | anything a car may drive on, except that a ramp is just road | `BUS_STEP` |
   | rail | rail, rail bridge, rail crossing, subway portal | `RAIL_STEP` |
   | subway | underground subway tunnel, pipe/subway crossing, station link | `SUBWAY_STEP` |
   | station | any tile of a bus depot, rail station or subway station | `STATION_STEP` when entering from outside, `PLATFORM_STEP` between tiles of the same building |

   Mode changes happen at junction tiles:
   - A car on a ramp may leave onto a highway lane as `highway`; a highway
     driver on a ramp may leave onto a road as `car`. A ramp is the only
     place a car changes decks.
   - A car, bus, train or subway rider next to a station of the matching
     kind (any station for road travellers, a rail station for trains, a
     subway station for subway riders) may enter it as `station`.
   - From a bus depot a traveller leaves onto the road as `bus`; from any
     other station onto the road as `car`; from a rail station onto rail as
     `rail`; from a subway station down onto the tunnels as `subway`.
     Stepping from one station directly into a different station is a
     transfer and costs `STATION_STEP`.
   - A train at a subway portal may continue into the tunnels as `subway`,
     and a subway rider may surface at a portal as `rail`.
4. **Destinations.** A trip arrives when a `car`, `bus` or `station` state is
   next to any tile of a developed commercial or industrial lot. Highway
   lanes, rail and subway tunnels never touch a destination directly; the
   trip must leave them first. A `car`, `highway` or `rail` state on a tile
   at the edge of the map also arrives: the network continues into a
   neighboring city.
5. **Failure.** A trip fails when it has no entrance, or when the search
   exhausts `TRIP_BUDGET` without arriving. `unreachable_ratio()` is failed
   trips divided by attempted trips for the last pass (0 when no trip was
   attempted).
6. **Congestion.** The weight of a trip is the side of its lot's footprint
   (1 for a 1×1 lot, 2 for 2×2, 3 for 3×3) times the sampling factor of
   rule 1. When a trip arrives, every `car` and `highway` state on its path
   adds the weight to the `traffic` block under that tile, saturating at
   `TRAFFIC_MAX`. Several tiles of the path in the same 2×2 block each add
   to it. Bus, rail, subway and station tiles add nothing: transit keeps
   cars off the road.
7. **Riders.** When a trip arrives, its weight is added once to the bus
   counter if any state on the path was `bus`, once to the rail counter if
   any was `rail`, and once to the subway counter if any was `subway`. A
   single trip can count toward all three. The counters accumulate for the
   year and are published and reset in `yearly()`.
8. **Decay.** Before the month's trips, every traffic byte loses
   `value >> TRAFFIC_DECAY_SHIFT` (a quarter, rounded down), so a value of
   1–3 lingers until it is refreshed and a road that is closed empties over a
   few months rather than instantly.
9. **Traffic jam.** After the pass, `stats.average_traffic` is the mean of
   the nonzero traffic blocks. When it reaches `JAM_LEVEL` the system reports
   `traffic_jam` and then stays silent for `JAM_COOLDOWN_MONTHS` passes.
10. **Bound on work.** The search keeps a visited stamp per (tile, mode) so
    no state is expanded twice in one trip, stops at the first arrival, and
    never spends more than `TRIP_BUDGET` per trip. The pass also counts the
    states it has expanded and stops routing once `PASS_SEARCH_BUDGET` is
    spent; origins not reached this month wait for a later one. With the
    sampling of rule 1 the pass is bounded regardless of city size, and
    `states_searched()` reports what the last pass used.

## Parameters

| Name | Value | Tunes |
|---|---|---|
| `TRIP_BUDGET` | 100 | Travel cost a trip may spend before it gives up. |
| `ROAD_STEP` | 3 | Cost of one road tile by car. |
| `HIGHWAY_STEP` | 1 | Cost of one highway tile; highways are three times faster than roads. |
| `RAMP_STEP` | 2 | Cost of crossing a ramp. |
| `BUS_STEP` | 2 | Cost of one road tile by bus. |
| `RAIL_STEP` | 1 | Cost of one rail tile. |
| `SUBWAY_STEP` | 1 | Cost of one subway tile. |
| `STATION_STEP` | 4 | Cost of entering or transferring between stations. |
| `PLATFORM_STEP` | 1 | Cost of walking between tiles of one station. |
| `ENTRANCE_REACH` | 3 | Rings searched around a lot for its entrance. |
| `TRIPS_PER_PASS` | 160 | Most origins routed in one monthly pass; larger cities are sampled. |
| `SAMPLE_WEIGHT_CAP` | 8 | Largest factor a sampled trip's weight is scaled by. |
| `PASS_SEARCH_BUDGET` | 32000 | States one monthly pass may search before the remaining origins wait a month. |
| `TRAFFIC_MAX` | 255 | Saturation of a traffic block. |
| `TRAFFIC_DECAY_SHIFT` | 2 | Monthly decay: a block loses its value shifted right by this. |
| `JAM_LEVEL` | 128 | Average traffic that produces a traffic jam story. |
| `JAM_COOLDOWN_MONTHS` | 6 | Passes to wait before another jam story. |

## Save state

`save()` returns `{"riders_year": {bus, rail, subway}, "riders_month":
{bus, rail, subway}, "unreachable": float, "attempted": int, "completed":
int, "cursor": int, "jam_cooldown": int}`. The `traffic` layer is saved with
the city.
