# Economy

## Purpose

The economy system models the world outside the city walls and the shape of
the city's industry. It drifts a national economic phase (recession, slow
growth, growth, boom) that colors demand for years at a time, splits the
city's industrial base into eleven sectors whose popularity follows the era
and the per-sector taxes the player sets, values the city's buildings for the
bond market, and decides in which year each new technology becomes available
to build.

## Inputs

Read on the scheduled day:

- `City.building` and `City.zone` layers for the city value and, when no
  population system is registered, for the industrial census.
- `City.founded_year` and the clock year for the era curve and inventions.
- `CityStats.population`: growth from month to month favours construction.
- `CityStats.education_quotient`: a well-educated workforce attracts
  high-technology sectors and a poorly educated one repels them.
- `CityStats.sector_taxes`: eleven rates, 0–20, indexed like the sectors.
- `CityStats.ordinances[&"pollution_controls"]`: discourages dirty sectors.
- The population system's `industrial_units()` when present.

## Outputs

- `CityStats.economy_phase`: 0 recession, 1 slow growth, 2 growth, 3 boom.
- `CityStats.sector_shares`: eleven fractions summing to 1.
- `CityStats.city_value`: total value of everything built.
- `CityStats.tax_industrial`: the aggregate industrial rate (rule 4.6), which
  the budget charges and zone demand feels. A rate written there directly (the
  Budget window, an import) moves every sector rate by the same points.
- `CityStats.sector_taxes`: shifted with that aggregate (rule 4.6).
- `CityStats.inventions`: technology key → first year it can be built.
- Events:
  - `&"economy_shift"` `{phase, previous, name}` when the national phase
    changes.
  - `&"invention"` `{technology, name, year}` in the month a technology
    becomes available; every technology is announced once.

Getters for other systems and the UI:

- `industrial_demand_modifier() -> int`: percentage points the zone system
  adds to its industrial target factor when one sector dominates the city.
- `pollution_modifier() -> int`: how dirty the industrial mix is; negative
  when heavy industry is a small share.
- `sector_report() -> Array[Dictionary]`: one row per sector for the
  Industries window: `{index, key, name, demand, tax, units, share, heavy}`.
- `sector_name(i) -> String`.
- `phase_name(phase) -> String`.
- `available_year(technology) -> int`: the rolled year, or the base year when
  none was rolled.
- `national_population() -> int`, `national_product() -> int`.

## Timing

- `setup` and `load`: roll a year for every technology missing from
  `CityStats.inventions`; seed
  the national figures if they are unset.
- `monthly`, day 16: national drift, sectors, city value, inventions.
- The next scheduled growth pass (day 5) reads the last computed demand
  modifier; the next environment pass (day 10) reads the pollution modifier.
  Both modifiers already persist in the economy's saved state.
- `daily`, `yearly`, `networks_changed`: nothing.

## Rules

### 1. National economy

1. The nation has a population and a product. Each month the population grows
   by `phase / GROWTH_SCALE` of itself and the product by
   `PRODUCT_RATE[phase] / GROWTH_SCALE` of itself. Above `NATION_POPULATION_CAP`
   or `NATION_PRODUCT_CAP` the magnitude of the same rate shrinks the figure
   instead, even when the rate is negative, so the pair keeps circling.
2. With chance `1 / REVIEW_CHANCE` in a month the nation is reviewed:
   `ratio = 100 × product / population`. With chance `1 / PHASE_CHANGE_CHANCE`
   the phase becomes the band the ratio falls in: below `RATIO_SLOW` is
   recession, below `RATIO_GROWTH` is slow growth, below `RATIO_BOOM` is growth,
   otherwise boom. A changed phase is reported as `&"economy_shift"`.
3. A city founded later starts with a larger nation:
   `NATION_START_POPULATION` by founding era. The product starts at the middle
   of the current phase's ratio band so the phase holds for a while.

### 2. Era demand curve

1. `ERA_DEMAND` gives each sector's baseline appeal at `ERA_START` and every
   `ERA_LENGTH` years after. Between rows the baseline is interpolated by the
   fraction of the era elapsed; after the last row it holds.

### 3. Sector demand and weights

1. Each sector keeps a running demand: `demand = (3 × demand + baseline ×
   noise) / 4`, where `noise` is the mean of four random draws in 0–2, so the
   demand wanders around the baseline.
2. The month's weight starts at the demand and is then adjusted:
   - `&"pollution_controls"` scales `HEAVY_SECTORS` by `POLLUTION_CONTROL_SCALE`;
   - a city that grew since last month scales `CONSTRUCTION_SECTOR` by
     `GROWTH_CONSTRUCTION_SCALE`;
   - education quotient above `EQ_HIGH_TECH` scales `HIGH_TECH_SECTORS` by
     `HIGH_TECH_SCALE`; above `EQ_TECH` scales `TECH_SECTORS` by `TECH_SCALE`;
     below `EQ_LOW` scales `HIGH_TECH_SECTORS` by `LOW_EQ_SCALE`;
   - the sector's tax rate is subtracted; the weight never goes below zero.

### 4. Sector allocation

1. `units` is the industrial capacity from the census. Each sector holds a
   number of local units.
2. If the local total exceeds `units`, every sector sheds its proportional
   share of the surplus. Otherwise the shortfall is dealt out in proportion to
   the weights, with fractional remainders settled by random draws.
3. `sector_shares[i] = local[i] / total`; when nothing is built the shares
   follow the weights so the Industries window still shows the mix.
4. `pollution_modifier`: with `heavy` the percent of units in
   `HEAVY_SECTORS`, the result is `-1` below `HEAVY_CLEAN_PERCENT`, otherwise
   `(heavy − HEAVY_CLEAN_PERCENT) / HEAVY_DIRTY_STEP`.
5. `industrial_demand_modifier`: with `largest` the percent held by the
   biggest sector, the result is `0` below `DOMINANT_PERCENT`, otherwise
   `(largest − DOMINANT_PERCENT) / DOMINANT_STEP`.
6. **Industrial tax.** `aggregate_industrial_rate(stats)` is the sector rates
   weighted by `sector_shares` (a plain mean when every share is zero),
   rounded. At setup, load and the start of each monthly pass the system
   compares `stats.tax_industrial` with the aggregate it last published; a
   difference is a direct change (the Budget window's slider, an import), and
   every sector rate moves by that many points, clamped to 0..`SECTOR_TAX_MAX`.
   After the sectors are allocated it publishes the new aggregate to
   `stats.tax_industrial`. The Industries window calls
   `sector_taxes_changed()` after the player edits a sector so the aggregate
   follows at once. A save from before this rule has no published aggregate,
   so its sector rates line up with the player's industrial rate on load.

### 5. City value

1. Every anchor on the map contributes: zone buildings by footprint
   (`LOT_VALUE`), abandoned lots a quarter of that, construction sites nothing,
   reward buildings `LANDMARK_VALUE`, and everything else its catalog cost.
2. The sum is `city_value`, also available as `assessed_value()`.

### 6. Inventions

1. Every technology in `TECHNOLOGIES` has a base year. On the first setup the
   available year is the base year plus a random offset below
   `INVENTION_SPREAD`; a technology whose year is at or before the founding
   year is available from the start and is not announced. A loaded city that
   lacks a year for a technology (saved before it joined the table) gets one
   rolled the same way; if that year is already past, it is treated as known
   and not announced. A city whose economy has never run (an imported classic
   city, or an included city saved straight after import) treats every
   technology available by the current year as known: history, not news.
2. Each month every technology whose year has arrived and which has not been
   announced yet is reported once as `&"invention"`.
3. The toolbar gates its tools on these same keys and years
   (`Tools.available_year`), so a tool unlocks in the year its invention is
   announced. Without a rolled year a tool waits for the technology's base
   year. Wind power is a technology like the others.

## Parameters

| Name | Value | Tunes |
|---|---|---|
| `GROWTH_SCALE` | 1200 | divisor turning a phase rate into monthly growth |
| `PRODUCT_RATE` | 6, 3, 0, −3 | monthly product rate per phase |
| `NATION_POPULATION_CAP`, `NATION_PRODUCT_CAP` | 5,000,000; 3,500,000 | where growth turns to shrinkage |
| `REVIEW_CHANCE` | 10 | one review per this many months on average |
| `PHASE_CHANGE_CHANCE` | 3 | reviews per phase re-evaluation on average |
| `RATIO_SLOW`, `RATIO_GROWTH`, `RATIO_BOOM` | 45, 60, 75 | product-per-head bands |
| `NATION_START_POPULATION` | by founding era | starting national population |
| `ERA_START`, `ERA_LENGTH` | 1900, 50 | first row year and years per row |
| `ERA_DEMAND` | 5 rows × 11 sectors | baseline appeal of each sector by era |
| `HEAVY_SECTORS` | steel, textiles, petrochemical, automotive | polluting sectors |
| `TECH_SECTORS` | petrochemical, automotive, finance, media, aerospace, electronics | sectors that like an educated workforce |
| `HIGH_TECH_SECTORS` | aerospace, electronics | sectors that need one |
| `CONSTRUCTION_SECTOR` | construction | sector that likes a growing city |
| `POLLUTION_CONTROL_SCALE` | 0.9 | heavy-sector weight under pollution controls |
| `GROWTH_CONSTRUCTION_SCALE` | 1.1 | construction weight in a growing city |
| `EQ_HIGH_TECH`, `EQ_TECH`, `EQ_LOW` | 130, 100, 60 | education thresholds |
| `HIGH_TECH_SCALE`, `TECH_SCALE`, `LOW_EQ_SCALE` | 1.2, 1.1, 0.8 | education effects |
| `HEAVY_CLEAN_PERCENT`, `HEAVY_DIRTY_STEP` | 20, 30 | pollution modifier curve |
| `DOMINANT_PERCENT`, `DOMINANT_STEP` | 20, 5 | demand bonus curve |
| `LOT_VALUE` | 1×1: 50, 2×2: 400, 3×3: 1500 | value of a developed lot |
| `LANDMARK_VALUE` | 5000 | value of a reward building |
| `TECHNOLOGIES` | key → base year | technology roster |
| `INVENTION_SPREAD` | 20 | random years added to a base year |

## Save state

`save()` returns the national population and product, the eleven sector
demands, weights and local unit counts, the previous resident count, the two
derived modifiers, the last assessed value, the set of announced
technologies and the last published industrial aggregate
(`published_industrial`). Phase, shares, value and
invention years live in `CityStats`. `load()` tolerates missing keys.
