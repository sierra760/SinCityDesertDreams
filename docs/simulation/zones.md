# Zones

## Purpose

The zone system is the city's growth engine. Players zone land as light or
dense residential, commercial and industrial; the system decides, once a
month, which zoned lots develop, which grow into bigger buildings, which
decay and which are abandoned. It also keeps the three demand meters (RCI)
that tell the player what the city wants next, the per-building population
and job counts that the population and budget systems read, and the density
and growth overlay maps.

## Inputs

Read during the monthly pass:

- `City.zone`: zone kind of every tile (`Zones.RES_LOW` .. `Zones.IND_HIGH`)
  and the footprint corner flags that locate a lot's anchor.
- `City.building`: what stands on each tile.
- `City.flags`: `TileFlags.POWERED` and `TileFlags.WATERED`.
- `City.altitude` (ground height): multi-tile lots need level ground.
- `City.land_value`, `City.pollution`, `City.crime` (half-resolution maps).
- `City.difficulty`.
- `City.building` census: recreation buildings (city parks, stadiums,
  zoos, marinas), transit stations, cranes and chapels are counted from the
  building layer for the demand caps and the chapel rule.
- `CityStats.tax_residential`, `tax_commercial`, `tax_industrial`.
- `CityStats.ordinances`: `business_advertising`, `tourist_advertising`,
  `pro_reading_campaign`, `pollution_controls`.
- `CityStats.economy_phase` (0 recession .. 3 boom).
- `CityStats.neighbor_populations`: the external market.
- Transport's `unreachable_ratio()`: failed share of the last monthly trip pass.
- Economy's `industrial_demand_modifier()`: percentage points added to the
  industrial target factor.

## Outputs

- `City.building` and `City.zone`: construction sites, finished buildings,
  abandoned buildings and chapels are stamped into the map; every changed
  footprint is passed to `ctx.events.mark_dirty`.
- `City.flags`: newly built lots get `CONDUCTS_POWER` and `CONDUCTS_WATER`.
- `City.density` (quarter map): residents plus jobs per 4×4 block, one byte
  per `DENSITY_PEOPLE_PER_STEP` people.
- `City.growth` (quarter map): change in residents plus jobs per 4×4 block
  since last month, centered on 128 and scaled by `GROWTH_PEOPLE_PER_STEP`.
- `CityStats.demand`: the three demand meters, each in −999..999.
- `CityStats.jobs`: jobs offered by finished commercial and industrial
  buildings.
- `City.facilities`: one record per chapel (`key` = `chapel`, `built_day`).
- Events (`ctx.events.report`):

  | kind | args |
  |---|---|
  | `zone_boom` | `family` (`residential` / `commercial` / `industrial`), `count` of lots that finished construction this month |
  | `abandonment_wave` | `count` of lots that declined this month |
  | `chapel_built` | `at` (anchor tile as `[x, y]`) |

- Getters other systems call:

  | method | meaning |
  |---|---|
  | `population_of(id) -> int` | residents housed by one finished residential building of that id |
  | `jobs_of(id) -> int` | jobs offered by one finished commercial or industrial building |
  | `occupied_units() -> Vector3i` | finished residential, commercial and industrial units counted at the last pass |
  | `residents() -> int` | ordinary residents (units × `PEOPLE_PER_UNIT`), arcologies excluded |
  | `raw_demand() -> Vector3i` | the full-precision demand accumulators, each in −2000..2000 |
  | `stage_of(id) -> int` | development stage of a zone building, 0 for open ground, −1 for anything else |
  | `has_access(city, rect) -> bool` | whether a lot has road access under rule 4 |

## Timing

- `monthly`, phase 0 (day 5): take the census, recompute demand, then run
  the growth pass over the west half of the map (anchor column 0..63).
- `monthly`, phase 1 (day 6): run the growth pass over the east half
  (anchor column 64..127), then refresh the density and growth maps,
  `CityStats.jobs` and report the month's news.
- `daily`, `yearly`, `networks_changed`: nothing. Player construction takes
  effect at the next pass.

## Rules

### Stages and buildings

1. Every zoned lot is at a **stage**: 0 is open ground; stage 1 is a 1×1
   building; stages 2 and 3 are 2×2 buildings (the lower and upper half of
   the family's 2×2 roster); stage 4 is a 3×3 building. Light zones
   (`RES_LOW`, `COM_LOW`, `IND_LOW`) never pass stage 1. Dense zones can
   reach stage 4. `STAGE_FOOTPRINT` and `STAGE_UNITS` give the footprint and
   the occupancy of each stage.
2. A finished building of stage *s* houses (residential) or employs
   (commercial, industrial) `STAGE_UNITS[s] × PEOPLE_PER_UNIT` people.
   Construction sites and abandoned buildings house nobody and count for
   nothing. Only finished residential units count as residents; commercial
   and industrial units count as jobs.
3. Open ground for development is nothing, rubble, trees or a power line.
   Contaminated ground, parks and anything the player built never develop.
   A power line inside a lot is absorbed: the finished building conducts.

### Eligibility

4. **Road access.** A lot has access when any tile within `ACCESS_RADIUS`
   tiles of its footprint holds a road, a road tunnel, a road bridge, a
   level crossing, a highway ramp, a bus depot, a rail station or a subway
   station. Plain highway lanes and plain rail do not count; those serve
   lots only through ramps and stations.
5. A lot is **connected** when its anchor tile is powered and the lot has
   road access. Open ground develops only when connected. A developed lot
   that loses power or access has zero growth points (rule 7) and is likely
   to decline.

### Demand

6. Demand is recomputed at the start of each monthly pass from the census of
   finished buildings, in occupied units per family: R, C, I. With
   `jobs = C + I` and `labor_ratio = R_previous / (jobs + 1)`:
   - residential target = min(max(`RES_TARGET_FLOOR`,
     `jobs + R / RES_SELF_GROWTH_DIVISOR`),
     `C × RES_PER_COMMERCIAL + RES_BASE_TARGET`, residential cap), where the
     residential cap is `(RES_CAP_BASE + recreation) × RES_CAP_STEP` and
     recreation counts city parks, stadiums, zoos and marinas;
   - commercial target = min(`market × I × labor_ratio`, commercial cap),
     where `market = (people + MARKET_BASE) / MARKET_SCALE`, people being
     residents plus jobs (`(R + C + I) × PEOPLE_PER_UNIT`), plus
     `EXTERNAL_MARKET_PER_NEIGHBOR` for each neighbor city with people, and
     the commercial cap is `(COM_CAP_BASE + stations / COM_STATIONS_PER_STEP +
     neighbors with people) × COM_CAP_STEP`;
   - industrial target = min(max(`IND_TARGET_FLOOR`, `industry × I ×
     labor_ratio`), industrial cap), where `industry` is
     `INDUSTRY_BY_DIFFICULTY[difficulty] + INDUSTRY_BY_PHASE[economy_phase]`
     `+ industrial_demand_modifier / 100`
     and the industrial cap is `(IND_CAP_BASE + rail stations + cranes) ×
     IND_CAP_STEP`.

   For each family the accumulator moves by
   `DEMAND_GAIN × (target / (units + 1) − 1) + tax_pressure + ordinance nudge`
   and is clamped to ±`DEMAND_RAW_LIMIT`. `CityStats.demand` shows it
   rescaled to ±999. A new city starts with every accumulator at its
   positive limit.

   `tax_pressure`: `TAX_NEUTRAL` percent is neutral; each point below adds
   `TAX_BELOW_PER_POINT`; the first `TAX_MILD_POINTS` points above subtract
   `TAX_MILD_PER_POINT` each and every further point subtracts
   `TAX_STEEP_PER_POINT`.

   Ordinances: `business_advertising` adds `ORDINANCE_NUDGE_LARGE` to
   commercial, `tourist_advertising` adds `ORDINANCE_NUDGE_SMALL` to
   commercial, `pro_reading_campaign` adds `ORDINANCE_NUDGE_SMALL` to residential,
   `pollution_controls` subtracts `ORDINANCE_NUDGE_LARGE` from industrial.

### Growth points and desirability

7. A connected lot's **growth points** start at `raw demand +
   DEMAND_RAW_LIMIT` (so 0..4000) for its family, then local conditions
   adjust them, and the result is clamped to 0..`GROWTH_POINTS_MAX`:
   - residential and commercial lots add `land value × LAND_VALUE_WEIGHT`;
   - pollution above `POLLUTION_TOLERANCE` subtracts the excess times
     `POLLUTION_WEIGHT[family]`;
   - crime above `CRIME_TOLERANCE` subtracts the excess times
     `CRIME_WEIGHT[family]`.
   A lot that is not connected has 0 growth points. After the local result is
   clamped, residential growth points are multiplied by
   `1 - clamp(unreachable_ratio, 0, 1)` and truncated to an integer. This is
   monthly city-wide commute pressure: a failed share of 0 leaves residential
   conditions unchanged; a share of 1 prevents upgrades and reoccupation and
   raises decline risk. Commercial and industrial growth points are not scaled.
   New cities have no failed trips until transport first runs. Reconnection or
   new transit removes the pressure after the next transport pass. Without a
   transport system, the factor is 1. Non-finite failure data is ignored.
8. Every decision is a draw of `ROLL_SPAN` outcomes compared with a
   threshold; thresholds below are out of `ROLL_SPAN`.
9. **Decline.** A finished building of stage *s* declines when the draw is
   below `(GROWTH_POINTS_MAX − growth) / s`. Full demand in good conditions
   means no decline; no power, no access, oversupply, heavy pollution or
   crime or failed commuting make decline likely. A coin flip decides whether the lot splits:
   - stage 1 becomes an abandoned 1×1;
   - stage 2 splits into four abandoned 1×1 lots, or becomes an abandoned
     stage-2 lot;
   - stage 3 splits down to an abandoned stage-2 lot, or becomes an
     abandoned stage-3 lot;
   - stage 4 splits into eight abandoned 1×1 lots around the rim with an
     abandoned stage-3 lot dropped on a random quadrant, or becomes an
     abandoned 3×3.
10. **Construction.** A construction site of stage *s* finishes when the
    draw is below `CONSTRUCTION_FINISH / s`. When it finishes, a residential
    2×2 site becomes a chapel instead of housing if the city has fewer
    chapels than one per `RESIDENTS_PER_CHAPEL` residents (evaluated once
    per pass). Lacking water halves the finishing chance
    (`WATER_SHORTAGE_NUMERATOR` / `WATER_SHORTAGE_DENOMINATOR`).
11. **Reoccupation.** An abandoned lot of stage *s* becomes a finished
    building again when the draw is below `growth × REBUILD_FACTOR / s`.
12. **Upgrade.** Open ground and finished buildings below their zone's top
    stage upgrade when the draw is below
    `growth × UPGRADE_FACTOR / (s + 1)`, halved without water. Residential
    and commercial lots also need land value of at least
    `UPGRADE_LAND_VALUE[s]` to leave stage *s* (industry ignores land
    value). An upgrade stamps a construction site of the next stage:
    - stage 0 → 1 on the tile itself;
    - stage 1 → 2 on the first of the four 2×2 squares containing the tile
      whose tiles are all the same zone kind, level with each other, at
      least `EDGE_MARGIN` tiles from the map edge and hold only open ground
      or stage-1 lots;
    - stage 2 → 3 in place;
    - stage 3 → 4 on the first of the four 3×3 squares containing the lot
      whose tiles meet the 2×2 conditions with stage ≤ 3 allowed, and that
      touch a road tile along their rim. Other 2×2 lots overlapping the
      square are first broken into abandoned 1×1 lots so their leftover
      tiles stay consistent.
13. A residential 1×1 that finishes construction picks its look by land
    value: one of three classes every `RES_CLASS_LAND_VALUE_STEP` points.
    Other finished buildings pick a random variant of their stage.
14. Lots changed during a pass are not revisited in the same pass.

### Maps and news

15. After the east half is scanned, each 4×4 block's density byte is
    `people / DENSITY_PEOPLE_PER_STEP` (clamped to 255) and its growth byte
    is `128 + (people − last month's people) / GROWTH_PEOPLE_PER_STEP`
    (clamped to 0..255), where people is residents plus jobs of lots
    anchored in the block.
16. `zone_boom` is reported for a family when its demand meter is above
    `BOOM_DEMAND` and at least `BOOM_DEVELOPMENTS` of its lots finished
    construction this month. `abandonment_wave` is reported when at least
    `WAVE_DECLINES` lots declined this month.

## Parameters

All constants live in `game/scripts/sim/data/zone_params.gd`.

| name | value | tunes |
|---|---|---|
| `PEOPLE_PER_UNIT` | 10 | residents or jobs per occupied unit |
| `STAGE_FOOTPRINT` | 1, 2, 2, 3 | footprint side of stages 1..4 |
| `STAGE_UNITS` | 1, 8, 12, 36 | occupied units of a finished stage 1..4 building |
| `LIGHT_ZONE_MAX_STAGE` / `DENSE_ZONE_MAX_STAGE` | 1 / 4 | top stage per zone density |
| `UPGRADE_LAND_VALUE` | 0, 32, 96, 192 | land value needed to leave stages 0..3 (residential, commercial) |
| `RES_CLASS_LAND_VALUE_STEP` | 64 | land value per residential 1×1 look class |
| `ACCESS_RADIUS` | 3 | how far a lot looks for a road |
| `EDGE_MARGIN` | 2 | tiles a multi-tile lot keeps from the map edge |
| `DEMAND_RAW_LIMIT` | 2000 | accumulator range; meters show ±999 |
| `DEMAND_GAIN` | 600 | accumulator change per unit of target/supply mismatch |
| `RES_SELF_GROWTH_DIVISOR` | 50 | residential target grows by 1 per this many residents units |
| `RES_PER_COMMERCIAL` / `RES_BASE_TARGET` | 4 / 500 | residential target limit from commerce |
| `RES_CAP_BASE` / `RES_CAP_STEP` | 10 / 150 | residential cap: base steps plus one per recreation building |
| `MARKET_BASE` / `MARKET_SCALE` | 50000 / 150000 | how city size lifts the commercial market |
| `EXTERNAL_MARKET_PER_NEIGHBOR` | 0.1 | market lift per populated neighbor |
| `COM_CAP_BASE` / `COM_STATIONS_PER_STEP` / `COM_CAP_STEP` | 1 / 5 / 1500 | commercial cap from transit and neighbors |
| `IND_TARGET_FLOOR` | 15 | industry always wanted in a new city |
| `INDUSTRY_BY_DIFFICULTY` | 1.2, 1.1, 0.95 | industrial pull on easy, medium, hard |
| `INDUSTRY_BY_PHASE` | −0.15, 0, 0.1, 0.2 | industrial pull by national phase |
| `IND_CAP_BASE` / `IND_CAP_STEP` | 1 / 1500 | industrial cap from rail stations and cranes |
| `TAX_NEUTRAL` | 7 | neutral tax rate |
| `TAX_BELOW_PER_POINT` | 25 | demand gained per point below neutral |
| `TAX_MILD_POINTS` / `TAX_MILD_PER_POINT` | 2 / 25 | gentle penalty just above neutral |
| `TAX_STEEP_PER_POINT` | 50 | penalty per further point |
| `ORDINANCE_NUDGE_SMALL` / `ORDINANCE_NUDGE_LARGE` | 25 / 50 | ordinance effects on demand |
| `GROWTH_POINTS_MAX` | 4000 | growth point range |
| `LAND_VALUE_WEIGHT` | 2 | growth points per land value point |
| `POLLUTION_TOLERANCE` / `POLLUTION_WEIGHT` | 64 / 8, 4, 0 | pollution the families ignore, and the penalty per excess point |
| `CRIME_TOLERANCE` / `CRIME_WEIGHT` | 64 / 6, 6, 2 | same for crime |
| `ROLL_SPAN` | 65536 | outcomes per decision draw |
| `CONSTRUCTION_FINISH` | 16384 | construction finishing threshold at stage 1 |
| `REBUILD_FACTOR` | 15 | reoccupation threshold per growth point |
| `UPGRADE_FACTOR` | 3 | upgrade threshold per growth point |
| `WATER_SHORTAGE_NUMERATOR` / `_DENOMINATOR` | 1 / 2 | growth slowdown without water |
| `RESIDENTS_PER_CHAPEL` | 2500 | residents that justify one more chapel |
| `DENSITY_PEOPLE_PER_STEP` / `GROWTH_PEOPLE_PER_STEP` | 4 / 4 | overlay map scaling |
| `BOOM_DEMAND` / `BOOM_DEVELOPMENTS` | 500 / 12 | zone_boom thresholds |
| `WAVE_DECLINES` | 8 | abandonment_wave threshold |

## Save state

`save()` returns:

- `raw_demand`: the three accumulators;
- `previous_residential_units`: last pass's residential units (labor ratio);
- `units`: the last census as three integers;
- `block_people`: 1024 integers, last month's people per 4×4 block;
- `chapel_eligible` and `chapels`: whether a chapel may replace a
  residential 2×2 in the pending east-half pass, and how many chapels the
  city had when that was decided;
- `finished` and `declines`: monthly completion counts per family and the
  decline count, retained between the western and eastern phases so that
  loading cannot discard the first half's boom or abandonment reports.

Snapshots without the news counters load with zero totals. Saved counters are
restored exactly; the next western phase resets both for the new month.

Everything else is recomputed from the map at the next pass.
