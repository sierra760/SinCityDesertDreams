# Water

## Purpose

The water system decides which tiles receive water each month. Pumps draw on
the water table and nearby fresh water, desalination plants draw on salt
water, towers store a buffer that carries a district through a shortfall, and
treatment plants clean what the city consumes. Water flows through pipes in
the `underground` layer and through developed lots.

The system owns the `CONDUCTS_WATER` and `WATERED` bits of the `flags` layer
and the facility records of pumps, towers, treatment and desalination plants.
It also owns the code table of the `underground` layer (see Parameters), which
the construction tools follow when they lay pipes and subways.

## Inputs

- `building` layer: water facilities, consumers and conducting lots.
- `underground` layer: pipes and pipe/subway crossings.
- `zone` layer: footprint corners, used to find anchors.
- `terrain` layer: fresh water tiles around pumps.
- `flags` layer: `POWERED` (from the power pass two days earlier),
  `SALT_WATER` on water tiles, `CONDUCTS_WATER` (rebuilt, rule 1), and
  `WATERED` on tower tiles, which records stored water (rule 5).
- `city.sea_level`: the water table.
- Weather: precipitation, read from a system exposing `precipitation()`
  (looked up under `environment`, `weather`, `disasters`); the environment
  system rolls it each month around the desert seasons (see environment.md).
  `DEFAULT_RAIN` applies only when no such system is loaded.

## Outputs

- `flags` layer: `CONDUCTS_WATER` and `WATERED` bits.
- `stats.water_capacity`: units produced this month by pumps and desalination
  plants plus units released from towers.
- `stats.water_demand`: total load of every consumer on the map, connected or
  not.
- `stats.unwatered_buildings`: consumer buildings with no watered tile.
- `stats.water_stored`, `stats.water_storage_capacity`: units held in towers
  after this pass and the total they could hold; shown in the statistics
  status lines.
- `city.facilities[anchor]` for every water facility: `key`, `built_day`,
  plus `output` (pumps and desalination), `stored` (towers).
- News: `water_shortage` `{unwatered, demand, capacity}` when a network first
  fails to cover its load; `water_restored` `{}` when no network is short any
  more.

## Timing

- `setup`: rebuild conduction flags for the whole map, register records, run a
  distribution. A city loaded from a save instead keeps its saved service
  flags and tower contents until the next scheduled pass: the summary for the
  Water window is rebuilt from the saved flags, facility records and saved
  stats, so it reads exactly what was saved. (Distributing at load would also
  run before the weather is restored.)
- Monthly, day 3: rebuild conduction flags, register records, distribute.
- `networks_changed(rect)`: rebuild conduction flags inside `rect`, register
  records, distribute over the whole map. Towers charge or discharge on this
  pass exactly as on the monthly one.
- Nothing runs daily or yearly.

## Rules

1. **Conduction.** A tile conducts water when its `underground` code is a pipe
   or a pipe/subway crossing, or when its building is a developed lot (zone
   building, construction site, abandoned building, plant, civic, utility,
   transit, port, military, reward or arcology). Power lines, roads, rail,
   trees, parks and rubble do not conduct. The flag is derived from the two
   layers whenever the system runs.
2. **Consumers.** Every tile of a developed lot draws `LOAD_PER_TILE` units,
   except the four water facilities (pump, tower, treatment, desalination),
   which draw nothing. Power plants do consume water. Pipes draw nothing.
3. **Sources.** A source only runs when its anchor tile is `POWERED`.
   - Pump: `WATER_TABLE_FACTOR * water_table + floor(rain / RAIN_DIVISOR)`
     plus `FRESH_NEIGHBOR_YIELD` for every fresh (non-salt) water tile among
     the eight neighbors of the pump. `water_table` is `city.sea_level`, or
     `DEFAULT_WATER_TABLE` when the city has no global water level.
   - Desalination plant: `SALT_NEIGHBOR_YIELD` for every salt-water tile in the
     ring one tile wide around its footprint. Salt water yields nothing to a
     pump; it needs a desalination plant.
   - Treatment plants produce no water.
4. **Networks.** The map is scanned column by column. Each powered pump or
   desalination anchor, and each tower tile that holds water, seeds a
   breadth-first flood fill through conducting tiles (four cardinal
   neighbors). Tiles already assigned to a network are skipped, so each
   network is walked once. A tower with stored water can therefore keep
   serving its district when its pumps lose power.
5. **Storage.** Each tower tile holds `TOWER_UNITS_PER_TILE` units; a 2×2 tower
   holds four times that. A tile's `WATERED` bit records that it is full. When
   a network is walked, every full tower tile releases its units into the
   network's capacity and empties. After demand is served the surplus refills
   towers: `filled = floor((min(surplus, storage) + TOWER_UNITS_PER_TILE / 2) / TOWER_UNITS_PER_TILE)`
   tower tiles are marked full again, in fill order, but only tiles that are
   `POWERED` (an unpowered tower can empty but cannot refill).
6. **Distribution.** Capacity is sources plus released storage; consumed is
   `min(demand, capacity)`. Walk the network in fill order: source and
   treatment tiles are watered when powered; every other tile is watered while
   consumed units remain, a consumer tile spending `LOAD_PER_TILE`, a pipe or
   conduit spending nothing. Consumers past the budget stay dry, farthest from
   the seed last.
7. **Treatment.** The city's consumption counts as treated when
   `treatment_plants * TREATMENT_COVERAGE >= consumed` (zero consumption
   is always treated). `treatment_adequate()` and the network summary expose
   the result; the population system counts untreated water against health
   once treatment has been invented (see population.md). Treatment plants soften
   pollution through the environment system instead: each powered plant
   raises the pollution divisor of the blocks around it (see environment.md,
   Pollution rule 7).
8. **Reporting.** Capacity, demand, stored and storage capacity are summed over
   the whole map. A building counts as unwatered when no tile of its footprint
   is watered. `usage_percent()` is `min(100, consumed * 100 / capacity)`, or
   100 with no capacity.
9. **Records.** A facility record is created the first time the system sees a
   pump, tower, treatment or desalination anchor without one. Records whose
   anchor no longer holds that facility are removed. Other systems' records
   are never touched.

## Parameters

| Name | Value | Tunes |
|---|---|---|
| `LOAD_PER_TILE` | 1 | Units drawn by one developed tile. |
| `WATER_TABLE_FACTOR` | 5 | Pump output per level of the global water table. |
| `RAIN_DIVISOR` | 2 | Pump output from precipitation (half the rain value). |
| `FRESH_NEIGHBOR_YIELD` | 10 | Pump output per adjacent fresh water tile. |
| `SALT_NEIGHBOR_YIELD` | 20 | Desalination output per adjacent salt water tile. |
| `DEFAULT_WATER_TABLE` | 4 | Water table used when the city has no global level. |
| `TOWER_UNITS_PER_TILE` | 100 | Storage per tower tile. |
| `TREATMENT_COVERAGE` | 2000 | Consumption one treatment plant can clean. |
| `DEFAULT_RAIN` | 15 | Precipitation used when no weather system is present. |

### Underground layer codes

| Code | Meaning |
|---|---|
| 0 | nothing |
| 1–15 | pipe; the code is the connection mask (N=1, E=2, S=4, W=8) |
| 16–30 | subway tunnel; code minus 15 is the connection mask |
| 31 | pipe N–S crossing under subway E–W |
| 32 | pipe E–W crossing under subway N–S |
| 33 | pipe N–S crossing over subway E–W |
| 34 | pipe E–W crossing over subway N–S |
| 35 | subway station link (subway only) |

Codes 1–15 and 31–34 conduct water. `UtilityParams` exposes `is_pipe`,
`pipe_mask`, `pipe_code`, `is_subway`, `subway_mask`, `subway_code` and
`conducts_water_code` so every system reads the table the same way.

## Save state

`save()` returns `{"shortage": bool, "consumed": int, "treatment_adequate": bool}`.
Tower contents live in the `flags` layer and facility records in the city,
both saved with the city. Capacity, demand, unserved buildings and storage
are read back from the saved `CityStats`.
