# Environment: pollution, land value and crime

## Purpose

The environment system produces the three half-resolution quality maps that
the zone, population and land-use systems read: `pollution`, `land_value` and
`crime`. Each map has one byte per 2×2 block of tiles. The system also publishes
the city-wide averages shown in the graph windows, raises the two related
news events and rolls the month's weather (rain and wind) for the power and
water systems.

## Inputs

Layers: `building`, `zone`, `flags` (powered, watered bits), `terrain`,
`altitude`, `traffic` (half), `density` (quarter), `police` (quarter), and
the previous month's `pollution` and `crime` maps.

Metadata: `sea_level`.

Stats: `ordinances` for `pollution_controls`, `tree_planting`,
`legalized_gambling`, `neighborhood_watch`, `anti_drug_campaign` and
`junior_sports`.

The clock month and `ctx.rng` for the weather.

Economy's `pollution_modifier()`: the industrial mix's contribution to the
city-wide diffusion divisor. An absent economy system contributes 0.

## Outputs

Layers written: `pollution`, `land_value`, `crime` (all 64×64).

Stats written: `average_pollution`, `average_land_value`, `average_crime`
(each 0..255, averaged over developed blocks only).

News reported: `pollution_alert` (`{"level": n}`) when the pollution average
first rises to `POLLUTION_ALERT_LEVEL`; `crime_wave` (`{"level": n}`) when the
crime average first rises to `CRIME_WAVE_LEVEL`. Each is reported on the month
the average crosses the threshold, then again only after it has dropped below.

Getters for other systems: `pollution_total()`, `land_value_total()`,
`crime_total()`, `developed_blocks()`, and the weather: `precipitation()`
(0..100) and `wind_speed()`, read by power and water through
`UtilityParams.weather`.

## Timing

Scheduled monthly job on day 10, in the order weather, pollution, land value,
crime. The power (day 1) and water (day 3) passes therefore use the weather
rolled the month before; a new city starts with the founding month's seasonal
means.
Land value therefore sees this month's pollution and last month's crime; crime
sees this month's land value and the coverage map from the previous services
pass (day 12). Nothing runs daily. Construction does not trigger a recompute;
the next monthly pass picks the change up.

## Rules

A **block** is one 2×2 tile cell of the half-resolution maps. A block is
**developed** when any of its four tiles is zoned or carries a building that
is not open ground, rubble, a tree, a park or a power line.

### Pollution

1. Every tile emits pollution according to its building. The amount comes
   from a small table keyed by category and footprint size, with a few named
   exceptions (see the parameters). Industrial buildings emit the most and
   grow with footprint size; dense commercial emits a little; coal and oil
   plants emit heavily, gas moderately, nuclear and fusion a trace; solar,
   wind, hydro and microwave plants emit nothing. A contamination tile emits
   `CONTAMINATION_EMISSION`. Airport, seaport and military pieces emit
   `PortParams.POLLUTION_PER_TILE` for their tile's zone kind (a piece outside
   a port zone uses its category's: military, else seaport), and each also adds
   `PortParams.CRIME_PER_TILE` to its block's base crime (rule 17). Every
   arcology in the reward system's `arcology_report()` adds its resident-scaled
   `pollution` and `crime` (see rewards.md) spread evenly over the blocks of its
   footprint.
2. Industrial emissions are reduced by `POLLUTION_CONTROLS_PERCENT` while the
   `pollution_controls` ordinance is enabled.
3. Each block also receives `traffic / TRAFFIC_POLLUTION_DIVISOR` from the
   traffic map.
4. Trees and parks absorb pollution: each tree tile removes `TREE_ABSORPTION`,
   each park tile removes `PARK_ABSORPTION` from the block's carried value.
   While the `tree_planting` ordinance is enabled every ordinary street tile
   (not highways, bridges or tunnels) removes `STREET_TREE_ABSORPTION`.
5. The block's working value is last month's pollution plus emissions and
   traffic minus absorption, never below zero.
6. The new value is a weighted average of the block and its four cardinal
   neighbors: `(2 × own + sum of neighbors) / (max(1, DIFFUSION_DIVISOR -
   pollution_modifier) + treatment bonus + neighbor count)`. A cleaner mix
   has a negative modifier and clears pollution faster; a heavier mix has a
   positive modifier and retains more pollution. With modifier 0, no treatment,
   four neighbors and no sources, a uniform level decays by a quarter each
   month. The positive base-divisor floor also applies to loaded modifiers.
7. A powered water treatment plant raises the divisor by
   `TREATMENT_DIVISOR_BONUS` for every block within `TREATMENT_RADIUS` blocks
   of its anchor, up to `TREATMENT_MAX_BONUS` for overlapping plants.
8. Values clamp to 255. The average is the total over developed blocks
   divided by the developed block count.

### Land value

9. Undeveloped blocks have land value 0.
10. An **amenity score** is summed for every quarter cell (4×4 tiles) from its
    sixteen tiles: open water `AMENITY_WATER`, empty dry ground
    `AMENITY_OPEN_GROUND`, tree `AMENITY_TREE`, park `AMENITY_PARK` (large
    park tiles `AMENITY_LARGE_PARK`), civic attractions (`Buildings.LIBRARY`,
    `MUSEUM`, `MARINA`, `ZOO`, `CITY_HALL`, `MONUMENT`, `MAYORS_RESIDENCE`,
    `NEON_DOME`)
    `AMENITY_CIVIC`, rubble and contamination `AMENITY_RUBBLE` (negative),
    watered tiles `AMENITY_WATERED`, sloped dry ground `AMENITY_SLOPE`, and
    altitude above sea level `(ground - sea) / ALTITUDE_DIVISOR` per tile,
    capped at `ALTITUDE_CAP` levels.
11. A block's base value is the mean amenity of its quarter cell and that
    cell's cardinal neighbors, so parks and water lift the surrounding area.
12. The **center** of the city is the centroid of dense commercial tiles, or
    of all developed tiles when there are none. `d` is the Manhattan distance
    from the block to the center in blocks. Blocks gain `(CENTRE_REACH - d)`
    (never below 0) scaled by zone: full for commercial, half for
    residential and other developed land, a quarter for industrial.
13. Zone adjustments, using the block's zone (industrial, commercial, or
    residential/other):
    - industrial: `+ INDUSTRIAL_DENSE_BONUS` if dense industrial,
      `- pollution / IND_POLLUTION_DIVISOR - crime / IND_CRIME_DIVISOR`;
    - commercial: `- pollution / COM_POLLUTION_DIVISOR - crime /
      COM_CRIME_DIVISOR + density / COM_DENSITY_DIVISOR`;
    - residential and other: `+ QUIET_BONUS` when density is below
      `QUIET_DENSITY`, `- pollution / RES_POLLUTION_DIVISOR - crime /
      RES_CRIME_DIVISOR - traffic / RES_TRAFFIC_DIVISOR`.
14. A block whose anchor tile holds an abandoned building keeps half its value.
15. Values clamp to 0..255. The average is over developed blocks.

### Crime

16. Undeveloped blocks have crime 0.
17. Base crime for a developed block is `density - police / POLICE_CRIME_DIVISOR
    - land_value / VALUE_CRIME_DIVISOR`, plus `GAMBLING_CRIME` while
    `legalized_gambling` is enabled, minus `WATCH_CRIME_RELIEF` while
    `neighborhood_watch` is enabled, minus `ANTI_DRUG_CRIME_RELIEF` while
    `anti_drug_campaign` is enabled, minus `JUNIOR_SPORTS_CRIME_RELIEF` while
    `junior_sports` is enabled, plus the port, base and arcology crime of rule 1.
18. The published value is the mean of the block's base crime and its cardinal
    neighbors' base crime, clamped to 0..255, so crime bleeds across block
    edges.
19. The average is over developed blocks.

### Weather

20. At the start of each monthly pass, precipitation is
    `RAIN_BY_MONTH[month] + rng.below(2 × RAIN_SPREAD + 1) − RAIN_SPREAD`,
    clamped to 0..100, and wind speed is `WIND_BY_MONTH[month] +
    rng.below(2 × WIND_SPREAD + 1) − WIND_SPREAD`, never below zero. The
    seasonal tables give wet winters, a dry late spring, a short late-summer
    monsoon and windy springs; their yearly means equal the utilities'
    `DEFAULT_RAIN` and `DEFAULT_WIND`. Rain feeds pump output and limits the
    solar bonus; wind drives turbine output (see water.md and power.md).
21. The wind also has a direction, rolled each month: from
    `PREVAILING_WIND_FROM` (west) with probability `PREVAILING_WIND_PERCENT`,
    otherwise from any of the four directions. In a month whose wind speed is
    at least `WIND_DRIFT_SPEED`, the pollution average (rule 6) takes one of
    the block's two own shares from its upwind neighbour instead, so smoke
    settles downwind of its source. The total weight is unchanged, so a
    uniform level decays exactly as in calm air.

## Parameters

| Name | Default | Tunes |
|---|---|---|
| `INDUSTRIAL_EMISSION` | 1×1: 6, 2×2: 14, 3×3: 24 | industrial emission per tile by footprint |
| `COMMERCIAL_EMISSION` | 1×1: 0, 2×2: 3, 3×3: 5 | dense commercial emission per tile |
| `PLANT_EMISSION` | coal 50, oil 25, gas 10, nuclear 2, fusion 2 | power plant emission per tile |
| `CATEGORY_EMISSION` | arcology 15, transit 4 | flat per-tile emission by category |
| `SPECIAL_EMISSION` | prison 10, stadium 4, pump 2, treatment 10 | named civic/utility emitters |
| `CONTAMINATION_EMISSION` | 200 | a contaminated tile |
| `TRAFFIC_POLLUTION_DIVISOR` | 5 | traffic contribution per block |
| `POLLUTION_CONTROLS_PERCENT` | 25 | industrial reduction under the ordinance |
| `TREE_ABSORPTION`, `PARK_ABSORPTION` | 4, 6 | absorption per tree or park tile |
| `STREET_TREE_ABSORPTION` | 1 | absorption per street tile under the tree planting ordinance |
| `DIFFUSION_DIVISOR` | 4 | base diffusion divisor (decay rate) |
| `TREATMENT_DIVISOR_BONUS`, `TREATMENT_MAX_BONUS`, `TREATMENT_RADIUS` | 1, 3, 8 | treatment plant effect |
| `POLLUTION_ALERT_LEVEL`, `CRIME_WAVE_LEVEL` | 100, 80 | news thresholds |
| `AMENITY_*` | see file | amenity score per tile kind |
| `ALTITUDE_DIVISOR`, `ALTITUDE_CAP` | 8, 16 | altitude bonus |
| `CENTRE_REACH` | 64 | blocks over which centrality fades |
| `INDUSTRIAL_DENSE_BONUS`, `QUIET_BONUS`, `QUIET_DENSITY` | 21, 21, 64 | zone bonuses |
| `*_POLLUTION_DIVISOR`, `*_CRIME_DIVISOR`, `COM_DENSITY_DIVISOR`, `RES_TRAFFIC_DIVISOR` | see file | penalty weights |
| `POLICE_CRIME_DIVISOR`, `VALUE_CRIME_DIVISOR` | 2, 4 | crime relief from coverage and value |
| `GAMBLING_CRIME`, `WATCH_CRIME_RELIEF`, `ANTI_DRUG_CRIME_RELIEF`, `JUNIOR_SPORTS_CRIME_RELIEF` | 16, 8, 4, 4 | ordinance crime effects |
| `RAIN_BY_MONTH`, `WIND_BY_MONTH` | see file | seasonal weather means, January first |
| `RAIN_SPREAD`, `WIND_SPREAD` | 8, 4 | how far a month's weather wanders from the mean |
| `WIND_DIRECTIONS`, `PREVAILING_WIND_FROM`, `PREVAILING_WIND_PERCENT`, `WIND_DRIFT_SPEED` | four steps, west, 70, 5 | wind direction and how strongly it carries smoke |

## Save state

`pollution_total`, `land_value_total`, `crime_total`, `developed_blocks`,
the two news latches `pollution_alerted`, `crime_alerted`, and this month's
weather `rain`, `wind` and `wind_from` (a save without them keeps the
seasonal means and the prevailing direction). The maps
themselves are saved with the city layers.
