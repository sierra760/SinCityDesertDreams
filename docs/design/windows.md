# Windows

The information windows under `game/scripts/ui/` are the mayor's reports:
Budget, Graphs, Population, Industries, Ordinances, Newspaper, City Maps and
Neighbors. They read the simulation through `Simulation`, `CityStats` and the
system getters, write only the settings the player owns (tax rates, funding
levels, sector taxes, ordinance switches, bonds, auto-budget) and never touch
the map.

## Shared contract

Every window is `class_name <Name>Window extends Control`, built entirely in
code and headless-safe. The host relies on these members:

| Member | Behavior |
|---|---|
| `_ready()` | Builds the chrome with `UIFactory.make_window_chrome(title)`, wires `WindowDrag` to the title bar, fills the window to its parent with `PRESET_FULL_RECT` and `MOUSE_FILTER_IGNORE` (so the map behind it still takes clicks), fits the panel to logical bounds, then hides itself. Window titles and actions stay fixed while the body scrolls. |
| `bind(sim: Simulation)` | Stores the simulation and connects `month_ended` / `year_ended` to a refresh that runs only while the window is visible. Rebinding disconnects the previous simulation. |
| `refresh()` | Re-reads the data and rebuilds the labels. Safe with no simulation, with a simulation that has no city yet, and with a missing system (`get_system` returning null). |
| `open()` | `show()` then `refresh()`. |
| `close()` | `hide()` then emits `closed`. The X button, the Done button and the Escape key all go through `close()`. |
| `signal closed` | Emitted once per close. |

Escape is handled in `_unhandled_key_input` while the window is visible and
marks the event handled, so one press closes one window. No window awaits
anything; every rebuild is synchronous.

Controls that carry state (number fields, sliders, check boxes) are created once
in `_ready` and synchronized in `refresh()` behind a `_syncing` flag, so
pushing a value into a control never writes it back into the simulation.
Tables whose row count varies (bonds, complaints, stories, gaming resorts) live in
their own container that is emptied and refilled on every refresh.

## Budget (`BudgetWindow`)

- Title "Budget". Treasury and date at the top; a note beginning "Year-end
  budget review for <year>" appears while `Simulation.budget_review_pending`
  is set.
- Tax rates: three `TouchNumberField` controls (minus, value, plus) 0..20
  writing `stats.tax_residential`, `stats.tax_commercial` and
  `stats.tax_industrial`.
- Funding: one `HSlider` 0..100 per service, grouped as Services (police,
  fire, health, schools, colleges) and Transportation (roads, highways,
  bridges, rail, subway, tunnels), each writing `stats.set_funding(key, pct)`.
- Books: a three-column table (Account, Year to date, Year-end estimate).
  Year to date comes from `stats.ledger`; the estimate from
  `budget.estimated_ledger()`. Income and expense totals, last year's net and
  the estimated net come from `budget.review_summary()`.
- Bonds: a table of outstanding bonds (principal, rate, issued year), an
  amount `TouchNumberField` (bond minimum..maximum, step 1000) whose quote
  label reads `budget.bond_quote(amount)` live, an Issue button
  (`budget.issue_bond`), and a "Repay oldest" button (`budget.repay_bond(0)`)
  enabled only when the treasury covers the oldest principal.
- "Auto budget" `CheckBox` writing `stats.auto_budget`.
- Done button: `close()`. The host connects `closed` to
  `sim.finish_budget_review()` for the January review.

Public helpers for the host and tests: `set_tax(kind, rate)`,
`set_funding(service, pct)`, `set_bond_amount(amount)`, `issue_bond()`,
`repay_oldest()`, `set_auto_budget(on)`, `ledger_text(account)`,
`quote_text()`, `funds_text()`, `totals_text()`.

## Graphs (`GraphsWindow`)

- Series picker: one `CheckBox` per name from `statistics.names()`;
  several may be on at once. Range buttons 1 / 10 / 100 years.
- The plot is an inner `GraphCanvas` control: axes, a horizontal grid, one
  polyline per selected series (palette of eight colors, cycling), the
  current value at the right end of each line, and a legend. One series is
  drawn against a labelled axis (dollars for Funds). With several, each line
  uses its own scale, the shared axis numbers are hidden and a caption under
  the plot says so. The polyline geometry is computed by `points_for(name)`
  so tests can check it without a display.
- Helpers: `set_series_enabled(name, on)`, `selected_series()`,
  `set_range_years(years)`, `range_years()`, `legend_text()`,
  `scale_caption()` (the own-scale caption, or "" with one shared axis).

## Population (`PopulationWindow`)

- Headline: total population, ordinary residents, gaming resort residents,
  settlement class (`PopulationSystem.status_name(city.status)`), employment,
  approval, education quotient and life expectancy.
- Cohort chart: an inner `CohortChart` control drawing twenty bars (one per
  five-year cohort) scaled to the largest cohort, with education (teal) and
  health (brass) ticks per bar. A twenty-row table beside it lists age range,
  people, education and health from `population.cohort_education(i, stats)`
  and `cohort_health(i, stats)`.
- Complaints: the March vote ranking from `population.complaints()`.
- Gaming Resorts: one row per standing design from `rewards.arcology_report()`.
- Helpers: `cohort_text(i)`, `complaint_text(rank)`, `headline_text()`.

## Industries (`IndustriesWindow`)

- Header: national phase (`EconomySystem.phase_name(stats.economy_phase)`),
  national population, city value (`stats.city_value`).
- Table from `economy.sector_report()`: sector, demand, units, share
  percentage and a tax `TouchNumberField` 0..`EconomyParams.SECTOR_TAX_MAX`
  writing `stats.sector_taxes[i]` (the packed array is copied, changed and
  assigned back so the write always lands). Heavy sectors are marked.
- Helpers: `set_sector_tax(i, rate)`, `sector_text(i)`, `phase_text()`,
  `value_text()`.

## Ordinances (`OrdinancesWindow`)

- Three groups (Finance, Safety, City) from `ordinances.catalog()`, each row a
  `CheckBox` with the ordinance name, a muted description and its estimated
  yearly amount (income positive, cost negative). Toggling calls
  `ordinances.set_enabled(key, on)`.
- Totals: yearly income, yearly cost and net from `stats.ordinance_income`
  and `stats.ordinance_cost`.
- Helpers: `set_ordinance(key, on)`, `is_checked(key)`, `totals_text()`.

## Newspaper (`NewspaperWindow`)

- Masthead "The Desert Dispatch" with the issue date; extras are marked.
- The lead story (first entry of `issue.stories`) in the header size, then
  the remaining stories and fillers in body size.
- Previous / Next buttons walk `newspaper.archive()`; opening the window
  jumps to the latest issue.
- Advisor panel: entries from `newspaper.advice()`, urgent ones in the
  warning color.
- Helpers: `show_issue(index)`, `show_previous()`, `show_next()`,
  `current_index()`, `issue_count()`, `headline_text()`, `date_text()`,
  `story_count()`, `advice_count()`.

## City Maps (`CityMapsWindow`)

- One button per `CityOverlaySampler.LAYERS` kind plus None: zones, power,
  water, crime, pollution, land value, traffic, police, fire, density and growth.
  `bind_presentation(controller)` attaches the 3D view; the selection is kept
  until one is attached.
- Legends come from the analytical sampler, including utility states, zone tints
  and growth direction. Layers draw directly in the 3D city view.
- Helpers: `select_overlay(kind)`, `selected_overlay()`, `legend_text()`.

## Neighbors (`NeighborsWindow`)

- A three-by-three grid: north on top, west and east on the sides, south at
  the bottom, a compass rose in the center with the city's own name.
- Each card from `neighbors.neighbor_report()`: name, edge, population,
  connections (road, rail, power, water) and this year's trade balance.
- Helpers: `card_text(edge)`.

## Tests

`game/tests/test_windows.gd` builds one small town with the `Builder`, runs
it fourteen months (so a January settlement and a newspaper issue exist),
then for each window: constructs it, `bind`, `open`, `refresh`, asserts the
key labels contain the expected numbers, changes a control through code and
checks the stat moved, and confirms `close` emits `closed` exactly once. It
also opens every window against a simulation with no city and against no
simulation at all.

## Display and compact layouts

Shared chrome has fixed titles and actions with a scrolling body. Controls use
16/14/18/22 font tiers and 44-pixel primary targets; dense tables may use 40-pixel
rows and horizontal scrolling. `DisplayLayout` fits windows after display changes.
`WindowDrag` clamps movement and cancels on release or focus loss. The inspector
keeps Rename and Demolish reachable while long details scroll. Settings offers
interface size (with feedback when it is capped) and fullscreen; signs, traffic
and the minimap are toggled from View → Show.
Sizes are logical UI pixels; the 3D texture remains drawable-sized.
