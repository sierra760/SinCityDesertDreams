# Windows

The information windows under `game/scripts/ui/` are the mayor's reports:
Budget, Tourism, Graphs, Population, Industries, Ordinances, Newspaper, City Maps and
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

Fixed Summary / Taxes / Funding / Debt tabs use `ReportPages` above the single
scroll body. Treasury and any annual-review notice remain visible; Auto budget
and Done stay in the footer. The initial Summary aligns estimated annual income,
expenses and balance in three compact rows. The previous settled year's balance
appears only when books exist. Treasury colors follow positive, zero and negative
cash, including daily balance changes. Account breakdown is
collapsed initially; its period selector shows Year to date, Previous year, or
Year-end estimate with one amount column and income/expense subtotals.

Taxes groups four property rates and the independent occupancy/gaming rates,
all 0–20%, with links to Tourism and industry-sector taxes. Funding selects
Services or Transportation and retains existing sliders and condition reporting.
Debt shows principal, annual interest, the quote and issue/repay actions. The quote
keeps the offered amount, rate and annual interest, without repeating the prime rate.

The January review explicitly starts on Summary and remains held while following
report links or changing pages. Only Budget's existing close/Done behavior
finishes it. Report instances, tab selection, and page scroll are reused.
Existing financial helpers remain; `select_page(name)` and `selected_page()`
provide named navigation. Short landscape displays put the three Summary
headings above their amounts so the complete balance is immediately visible.

## Tourism (`TourismWindow`)

Reports → Tourism presents current monthly attendance beside its supported
forecast, occupancy, physical beds, estimated annual city taxes, the main limit,
and the next announced event. Collapsed Visitors and jobs, Access and utilities,
Reputation and events, and Income sections contain selected useful results.
Only one section opens at once. Accrued taxes and completed business tax bases
are distinct from projections and city cash. Reads do not advance the simulation.
Visitor taxes returns to Budget → Taxes; Ordinances opens policy controls.

An empty tourism economy uses a small empty state instead of rows of zeros.
Past attendance or accrued visitor taxes keep the full report available even
after the last venue is removed. Event text appears only for an announced event.
Optional sections show filled jobs, gateway capacity, waiting trips when present,
reputation and city taxes owed. Business tax-base calculations and retail
bookkeeping stay out of this report. The safety-program annual quote remains
explicitly conditional on enabling the policy; completed spending is separate.

## Graphs (`GraphsWindow`)

- The chart and range buttons (1 / 10 / 100 years) lead. **Choose data**
  expands the series picker, with one `CheckBox` per name from
  `statistics.names()`; several may be on at once. Selection and disclosure
  survive refreshes; collapsing returns keyboard focus to the disclosure.
  Migration and fractional-accounting notes do not precede the chart.
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
  health (brass) ticks per bar. The collapsed **Age breakdown** lists age range in a twenty-row table,
  people, education and health from `population.cohort_education(i, stats)`
  and `cohort_health(i, stats)`.
- Residents’ concerns: the March vote ranking from `population.complaints()`,
  ahead of the age chart. A zero tourism-jobs suffix is omitted.
- **Resort occupancy** is collapsed and appears only when venues or visitors
  exist. Its rows retain occupancy and closed-venue reasons without coordinates
  or a repeated tourism explanation. Both disclosures retain their state.
- Helpers: `cohort_text(i)`, `complaint_text(rank)`, `headline_text()`.

## Industries (`IndustriesWindow`)

- Header: national phase (`EconomySystem.phase_name(stats.economy_phase)`),
  city value (`stats.city_value`) and the city's industry tax. The national
  simulation population and weighting terminology are omitted.
- Table from `economy.sector_report()`: sector, demand, units, share
  percentage and a tax `TouchNumberField` 0..`EconomyParams.SECTOR_TAX_MAX`
  writing `stats.sector_taxes[i]` (the packed array is copied, changed and
  assigned back so the write always lands). Heavy sectors are marked.
- Helpers: `set_sector_tax(i, rate)`, `sector_text(i)`, `phase_text()`,
  `value_text()`.

## Ordinances (`OrdinancesWindow`)

Fixed Finance / Safety / City tabs show one category. Enacted only filters its
rows without changing the fixed net annual total for all enacted city policies.
The income and cost components remain in its tooltip. Compact
rows show a labelled switch, full policy name, signed yearly amount and short
effect. A disclosure opens one full description at a time. Empty filtered
categories offer Show all policies. Policy application and yearly settlement are
unchanged; `select_group`, `set_enacted_only` and existing helpers support callers.

## Query (`QueryPanel`)

The inspector shows an explicit summary selected for the tile type, typically
four to eight useful facts. Local service and development blockers stay visible.
More details offers a curated secondary set; arbitrary numeric facility record
fields never appear. Citywide counters, raw scoring and tourism bookkeeping do
not enter the ordinary Query interface. `describe` and `info` retain full factual
readers for diagnostics and tests; `lines` reflects player-facing content.

The panel sizes to its content, capped at the host's safe bounds, with fixed
close and available edit/demolition actions. Same-tile updates preserve reading
state; new selections collapse details. Surface/underground targeting, sign
editing and naming retain their established behavior.

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
- Police and Fire use short button labels, with full coverage names available
  to tooltips and accessibility. The two-column picker fits small phones.
- Legends come from the analytical sampler, including utility states, zone tints
  and growth direction. Layers draw directly in the 3D city view.
- Helpers: `select_overlay(kind)`, `selected_overlay()`, `legend_text()`.

## Neighbors (`NeighborsWindow`)

- A three-by-three grid: north on top, west and east on the sides, south at
  the bottom, a compass rose in the center with the city's own name, without repeating
  population and tourist counts from the main status bar.
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
interface size (with feedback when it is capped) and fullscreen; tool labels,
signs, traffic and the minimap are toggled from View → Show. Choose Tool Labels
to show or hide the toolbar captions.
All nine reports share the menu-adjusted usable bounds. Titles and close buttons
stay below the main menu after opening, rotation, resizing or menu visibility
changes. Non-report dialogs retain their own placement rules.
Sizes are logical UI pixels; the 3D texture remains drawable-sized.

## Report focus refinement

Reports use the date as context without repeating a long city name. Keep
important causes, financial periods, units, refusal reasons and controls visible.
Do not replace a useful short warning with an empty state, or hide accrued money
just because current capacity is zero. `test_report_focus.gd` covers empty-state
transitions, read purity, disclosure persistence, keyboard focus and treasury
colors; the layout suite checks that all three Budget headline figures fit
without an initial scroll.
