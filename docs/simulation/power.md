# Power

## Purpose

The power system decides which tiles receive electricity each month. Power
plants generate a budget measured in tiles; the budget flows through the
electrical network (lines, crossings and developed lots) to every building it
can reach. Networks that cannot cover their load brown out. Plants wear out
after a fixed lifetime and must be replaced.

The system owns the `CONDUCTS_POWER` and `POWERED` bits of the `flags` layer
and the facility records of power plants.

## Inputs

- `building` layer: plant footprints, consumers and conduits.
- `zone` layer: footprint corners, used to find anchors.
- `altitude` layer: ground height at wind turbines.
- `terrain` layer: hydro dams only generate on a waterfall tile.
- `flags` layer: `CONDUCTS_POWER` (rebuilt from the building layer, see rule 1).
- `city.facilities`: plant records (`age_years`).
- `city.funds`, `stats.disasters_enabled`: automatic replacement of a retired
  plant.
- `stats.ordinances[&"energy_conservation"]`: stretches every network budget.
- Weather: precipitation and wind speed. Read from a system that exposes
  `precipitation()` and `wind_speed()` (looked up under the keys `environment`,
  `weather`, `disasters`); when none exists the defaults in the parameter
  table apply.

## Outputs

- `flags` layer: `CONDUCTS_POWER` and `POWERED` bits.
- `stats.power_capacity`: total generation of every plant on the map, in tiles.
- `stats.power_demand`: total load of every consumer on the map, in tiles,
  whether or not it is connected to a plant.
- `stats.unpowered_buildings`: number of consumer buildings (anchors) with no
  powered tile in their footprint.
- `city.facilities[anchor]` for every plant: `key`, `built_day`, `age_years`,
  `capacity` (last computed generation), `warned` (true once the aging notice
  has been given).
- News: `power_shortage` `{unpowered, demand, capacity}` when a network first
  fails to cover its load; `power_restored` `{}` when no network is short any
  more; `plant_aging` `{key, name, anchor, age_years}` once when a plant passes
  `PLANT_WARNING_YEARS`; `plant_retired` `{key, name, anchor}` when a plant is
  torn down; `plant_replaced` `{key, name, anchor, cost}` when the treasury
  pays for a new one in place.
- Notice: `plant_retired` `{key, name, anchor}` (the player must act).
- `ctx.events.mark_dirty` over every retired footprint.

## Timing

- `setup`: rebuild conduction flags for the whole map, register plant records,
  then run a distribution so a loaded city starts with correct service bits.
- Monthly, day 1: rebuild conduction flags for the whole map, register plant
  records, distribute.
- `networks_changed(rect)`: rebuild conduction flags inside `rect`, register
  plant records, distribute over the whole map.
- Yearly (last day of December): every plant ages one year; warnings,
  retirements and replacements happen here and only here. Loading a city or
  redistributing never ages a plant.

## Rules

Zoned land conducts power even while empty: a line touching any tile of a zoned block powers the whole block, which is what lets a fresh zone develop without lines on every lot.

Standalone power-line tiles can be zoned, rezoned and dezoned without removing
their lines. Buildings replace standalone lines within their footprint at the
normal placement price; neighboring lines reconnect using the existing network
rules. Road, rail and highway crossings and elevated power spans remain occupied
transport tiles. Ordinary terrain, shoreline and protected-land restrictions
still apply. Zoned line tiles can develop into buildings through normal growth.


1. **Conduction.** A tile conducts power when its building is a power line, a
   rail or road or highway piece that carries a line, a bridge, or a
   developed lot (any zone building, construction site, abandoned building,
   plant, civic, utility, transit, port, military, reward or arcology
   building). Roads, rail, highways without a line, trees, parks, rubble and
   empty ground do not conduct. The flag is derived from the building layer
   whenever the system runs. Imported cities also keep the explicit conductive
   links stored in the `.sc2` file's per-tile flag layer, including links across
   open ground or road approaches that cannot be inferred from their visible
   tile IDs. These links survive native saves and expire when their
   building/zone changes or the tile is explicitly cleared. Newly placed
   ordinary roads remain nonconductive. In that flag layer, bit `0x80` marks a
   conductor and `0x40` marks a powered tile.
2. **Consumers.** Every tile of a developed lot that is not a power plant
   draws `LOAD_PER_TILE` units. A 3×3 office block therefore draws nine units
   and a 1×1 house draws one. Lines and crossings draw nothing.
3. **Generation.** Each plant anchor contributes the generation for its kind:
   - Fixed plants: `PLANT_OUTPUT[key]` (coal, gas, oil, nuclear, microwave,
     fusion) and `HYDRO_OUTPUT` for a dam standing on a waterfall tile. A dam
     on any other terrain generates nothing.
   - Wind turbine: `floor((ground_height + r) / 2)` where `r` is a random
     integer in `[0, floor(wind / WIND_DIVISOR)]`. Higher, windier sites
     produce more.
   - Solar farm: for each of its `SOLAR_TILES` tiles, `SOLAR_BASE + r` where
     `r` is a random integer in `[0, floor((100 - rain) / SOLAR_RAIN_DIVISOR) - 1]`
     (zero when that range is empty). Rain reduces output.
   The random draws come from `ctx.rng`, once per turbine and once per solar
   tile, in scan order.
4. **Networks.** The map is scanned column by column (x outer, y inner). Each
   plant tile that is not yet part of a network seeds a flood fill through
   conducting tiles using the four cardinal neighbors. The fill order is
   breadth-first from the seed and is the order used in rule 6.
5. **Budget.** A network's capacity is the sum of the generation of the plants
   in it. Its budget is the capacity, plus `floor(capacity / CONSERVATION_BONUS_DIVISOR)`
   when the energy conservation ordinance is on. Its demand is the sum of its
   consumers' loads.
6. **Distribution.** Walk the network in fill order. Plant tiles are always
   powered and cost nothing. Every other tile is powered while the budget is
   positive; a consumer tile spends `LOAD_PER_TILE` from the budget, a conduit
   tile spends nothing. When the budget runs out the remaining tiles stay dark.
   A network whose demand exceeds its budget is short; consumers on it beyond
   the budget brown out in fill order, farthest from the seed last.
7. **Reporting.** Capacity and demand are summed over the whole map (rules 3
   and 2, all plants and all consumers, connected or not). A building counts as
   unpowered when no tile of its footprint is powered. `usage_percent()` is
   `min(100, consumed * 100 / capacity)`, or 100 with no capacity, where
   consumed is the load actually served.
8. **Aging.** At year end every plant record's `age_years` rises by one, except
   `AGELESS_PLANTS` (hydro dams and wind turbines never wear out). When the age
   exceeds `PLANT_WARNING_YEARS` and the record has not warned yet, report
   `plant_aging` and mark it warned. When the age exceeds `PLANT_LIFETIME_YEARS`
   the plant retires:
   - If disasters are disabled and `city.funds` covers the plant's build cost,
     the cost is debited, the age returns to zero, `warned` clears and
     `plant_replaced` is reported.
   - Otherwise the footprint is cleared: rubble on flat tiles, bare ground on
     slopes, power and water service bits cleared, underground pipes kept, the
     record removed, `plant_retired` reported and noticed, and the rect marked
     dirty.
9. **Records.** A plant record is created the first time the system sees a
   plant anchor without one (`age_years` 0, `built_day` = current day). Records
   whose anchor no longer holds that plant are removed. Other systems' records
   are never touched.

## Parameters

| Name | Value | Tunes |
|---|---|---|
| `LOAD_PER_TILE` | 1 | Units drawn by one developed tile. |
| `PLANT_OUTPUT` | coal 704, gas 176, oil 768, nuclear 1776, microwave 5680, fusion 8880 | Tiles a whole plant can supply. |
| `HYDRO_OUTPUT` | 40 | Tiles one dam on a waterfall supplies. |
| `WIND_DIVISOR` | 8 | How strongly wind speed raises turbine output. |
| `SOLAR_TILES` | 16 | Collector tiles per solar farm. |
| `SOLAR_BASE` | 5 | Guaranteed output per collector tile. |
| `SOLAR_RAIN_DIVISOR` | 10 | How strongly rain limits the solar bonus. |
| `CONSERVATION_BONUS_DIVISOR` | 12 | Extra budget share from the energy conservation ordinance (one twelfth). |
| `PLANT_WARNING_YEARS` | 48 | Age after which the aging warning is given. |
| `PLANT_LIFETIME_YEARS` | 50 | Age after which a plant retires. |
| `AGELESS_PLANTS` | hydro, wind | Plants that never wear out. |
| `DEFAULT_WIND` | 10 | Wind speed used when no weather system is present. |
| `DEFAULT_RAIN` | 15 | Precipitation used when no weather system is present. |

## Save state

`save()` returns `{"shortage": bool, "consumed": int}`. Plant ages live in
`city.facilities` and the service bits in the `flags` layer, both saved with
the city.
