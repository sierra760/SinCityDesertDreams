# Statistics

## Purpose

The statistics system keeps the monthly histories behind the Graphs window
and the short city-status summary shown in the status bar and the newspaper
masthead. It samples once a month, keeps a century of samples per series, and
hands back any window of the last 1, 10 or 100 years on request. It never
changes the map or the simulation; it only observes.

## Inputs

Read on the sampling day:

- `City.building` and `City.zone` layers: developed residential, commercial
  and industrial tiles, counted per tile of each occupied lot.
- `City.funds`, `City.status`, `City.name`.
- `CityStats`: `population`, `arcology_population`, `demand`, `jobs`,
  `average_crime`, `average_pollution`, `average_land_value`,
  `average_traffic`, `power_capacity`, `power_demand`, `water_capacity`,
  `water_demand`, `unemployment`, `life_expectancy`, `education_quotient`,
  `approval`.
- `GameClock` for the date stamped on status lines.

## Outputs

- `CityStats.history[series]` receives one sample per series per month
  through `CityStats.record`. Series names, in Graphs-window order:

  | Series | Sample |
  |---|---|
  | `population` | ordinary residents plus arcology residents |
  | `residents` | developed residential tiles |
  | `commercial` | developed commercial tiles |
  | `industrial` | developed industrial tiles |
  | `money` | city funds, clamped to the signed 32-bit range |
  | `crime` | average crime index |
  | `pollution` | average pollution index |
  | `land_value` | average land value index |
  | `traffic` | average traffic index |
  | `power_percent` | unused generating capacity, 0–100 |
  | `water_percent` | unused pumping capacity, 0–100 |
  | `unemployment` | unemployment percent |
  | `health` | life expectancy |
  | `education` | education quotient |
  | `demand_residential` | residential demand, −999..999 |
  | `demand_commercial` | commercial demand |
  | `demand_industrial` | industrial demand |

- The status headline lines (`status_lines()`): the settlement class name,
  the date, population, funds, employment and approval, one line each.
- No events are reported. Status changes are reported by the population
  system; this system only labels them.

## Timing

- `monthly`, day 22: take one sample of every series and refresh the status
  lines.
- `daily`: nothing.
- `yearly`: nothing.
- `networks_changed`: nothing.

## Rules

1. One sample per series per sampling day. Samples are integers. Every series
   in the table above receives a sample every month, even when the value is
   zero, so all series stay the same length.
2. `population` is `CityStats.total_population()`.
3. `residents`, `commercial`, `industrial` count every tile whose building is
   a residential, commercial or industrial zone building
   (`Buildings.is_zone_building`). Construction sites and abandoned lots do
   not count.
4. `power_percent` is `100 − power_demand × 100 / power_capacity`, clamped to
   0..100; it is 0 when capacity is zero. `water_percent` is the same with the
   water capacity and demand.
5. `money` is `City.funds` clamped to `MONEY_MIN..MONEY_MAX`
   (`StatisticsParams`).
6. `history` keeps at most `KEEP_MONTHS` samples per series (100 years). The
   oldest sample drops when a new one is added past the limit.
7. `series(name, years)` returns the newest `years × 12` samples, oldest
   first. `years` is rounded up to the nearest offered window
   (`WINDOWS` = 1, 10, 100). Unknown series return an empty array.
8. `names()` lists the series in the order of the table.
9. Status lines use `STATUS_NAMES[City.status]`; a status beyond the table
   uses the last name.
10. `samples_taken()` counts the months sampled since founding and is
    persisted so a loaded city keeps its place.

## Parameters

| Name | Value | Tunes |
|---|---|---|
| `KEEP_MONTHS` | 1200 | Samples kept per series (100 years) |
| `WINDOWS` | 1, 10, 100 | The year spans offered by the Graphs window |
| `MONEY_MIN` / `MONEY_MAX` | −2 147 483 648 / 2 147 483 647 | Clamp for the funds series |
| `STATUS_NAMES` | Village … Megalopolis | Settlement class labels by `City.status` |

## Save state

`save()` returns `{"samples": int, "status_lines": [String], "last_status": int}`.
The series themselves are part of `CityStats.history`, which the city save
already carries. `load()` restores the three fields and tolerates missing ones.
