# Budget

## Purpose

The budget system keeps the city's books. Income and expenses accrue during
the year and are settled against the treasury once, at the January budget
review. It also runs the bond market (borrowing and repayment), moves the
prime rate, and decides when the city is in fiscal crisis or bankrupt.

## Inputs

- `city.building` and `city.zone`: the developed zone buildings that are
  assessed for property tax, the civic buildings whose upkeep is charged, and
  the network tiles whose maintenance is charged when no wear system answers.
- `city.funds`: the treasury.
- `stats.tax_residential`, `stats.tax_commercial`, `stats.tax_industrial`:
  tax rates in percent, set by the player.
- `stats.funding`: per-service funding percentages (police, fire, health,
  schools, colleges, roads, highways, bridges, rail, subway, tunnels).
- `stats.bonds`: outstanding bonds, oldest first.
- `stats.prime_rate`, `stats.economy_phase`: the national lending climate.
- `stats.auto_budget`: whether the player has delegated the review.
- The ordinance system (`ctx.system(&"ordinances")`), when present, answers
  `yearly_totals()` with the fees and costs of the enabled ordinances.
- The transport system (`ctx.system(&"transport")`), when present, answers
  `monthly_ridership()` with the number of fares collected this month.
- The wear system (`ctx.system(&"wear")`), when present, answers
  `maintenance_cost(category)` with the yearly upkeep in dollars, at full
  funding, of one transport category.

## Outputs

- `stats.ledger`: year-to-date dollars per account (see Rules 1 and 2).
- `stats.last_year_ledger`: the ledger of the year most recently settled.
- `stats.city_value`: the assessed value of everything the city has built,
  used for credit.
- `stats.bonds`: updated on issue, repayment and every settlement.
- `stats.prime_rate`: drifts once a year.
- `stats.auto_budget`: cleared by a fiscal crisis.
- `stats.bankrupt`: set when the treasury collapses.
- `city.funds`: changed only at settlement and by bond transactions.
- Events: news `&"treasury_deficit"` (first settlement that leaves the
  treasury negative), notice `&"fiscal_crisis"` (same moment, once per year),
  notice and news `&"bankruptcy"` (once, when the city goes bankrupt), news
  `&"bond_issued"` `{amount, rate}` for every bond issued, and news
  `&"tax_change"` `{count, family, previous}` on the first booking day after
  the player changes a tax rate (the first changed family, residential first).
  The rates last reported are saved, so a reload repeats nothing.

## Timing

- Scheduled day 18 of every month: accrue one month of every account.
- Yearly (last day of December, before the review): settle, copy the books,
  age the bonds, move the prime rate, check for crisis and bankruptcy.
- `networks_changed`: nothing; assessments are re-counted at the next accrual.

## Rules

1. **Accounts.** The ledger has income accounts `taxes_residential`,
   `taxes_commercial`, `taxes_industrial`, `transit_fares`,
   `ordinance_income` and `neighbor_trade` (the last is written by the
   neighbor system and may be negative), and expense accounts
   `ordinance_cost`, `police`, `fire`, `health`, `education`, `transport`,
   `bond_interest` and `other`. Every account is stored in whole dollars,
   truncated toward zero. Income accounts add to the settlement; expense
   accounts subtract.
2. **Monthly accrual.** On day 18 each account earns one twelfth of its
   yearly amount at the settings in force that month. Changing a tax rate or a
   funding level therefore affects the months that follow, never the months
   already booked. Fractions carry over inside the system, so twelve months at
   a steady rate always add up to the yearly amount.
3. **Property tax.** Every developed zone building is assessed at
   `zone_value(category, footprint) × stage_multiplier(stage)`, where the
   footprint is 1, 2 or 3 tiles on a side and the stage is the building's
   position within its footprint group (1 for the plainest, up to
   `STAGES_PER_FOOTPRINT`). An arcology is assessed at `ARCOLOGY_VALUE` as
   residential property. Yearly tax for a category is the summed assessment
   times that category's rate, divided by 100. Construction sites, abandoned
   buildings and rubble are not assessed.
4. **Service upkeep.** Each police station, fire station, hospital, school and
   college costs its `SERVICE_UPKEEP` per year, scaled by that service's
   funding percentage. Schools and colleges share the `education` account.
5. **Transport upkeep.** Roads, highways, bridges, rail, subway and tunnels
   are charged per tile per year at `TRANSPORT_UPKEEP_CENTS`, scaled by the
   category's funding percentage. When a wear system is present its
   `maintenance_cost(category)` replaces the per-tile count so that both
   systems see the same bill. Level crossings count as roads; rail under a
   power line counts as rail; ramps and interchanges count as highways;
   subway portals count as rail and subway stations as subway. Underground
   subway tunnels are billed only when the wear system reports them.
6. **Transit fares.** When the transport system reports a monthly ridership,
   every rider pays `FARE_CENTS`.
7. **Ordinances.** The ordinance system's `yearly_totals()` supplies the
   yearly fee income and program cost of the enabled ordinances. One twelfth
   of each is booked every month.
8. **Bond interest.** Every outstanding bond accrues
   `principal × rate / 100 / 12` each month into `bond_interest`.
9. **Settlement.** On the last day of December the treasury changes by the
   sum of the income accounts minus the sum of the expense accounts. The
   ledger is copied to `last_year_ledger` and cleared. Every bond gains one
   year of age. The simulation then pauses for the review; when
   `stats.auto_budget` is set the review needs no attention and the settings
   simply carry over.
10. **Prime rate.** After settlement the prime rate moves by one point toward
    the direction the national economy pulls: a recession (phase 0) lowers
    it, a boom (phase 3) raises it, and the middle phases move it down, up
    or not at all, chosen at random. It stays inside `PRIME_MIN..PRIME_MAX`.
11. **Borrowing.** A bond may be issued for any amount from `BOND_MIN` to
    `BOND_MAX` while fewer than `MAX_BONDS` are outstanding and the credit
    index is below `CREDIT_LIMIT`. The credit index is
    `total_debt × DEBT_WEIGHT / (city_value + 1)`, where city value is the
    summed construction cost of every network tile, plant, civic building,
    utility, transit building, port piece, reward and arcology. The bond's
    rate is `prime_rate + credit_index + 1` percent and never changes once
    issued. The principal is added to the treasury immediately.
12. **Repayment.** Only the oldest bond can be repaid, and only when the
    treasury holds at least its principal. The principal leaves the treasury
    at once; interest already booked this year stays booked.
13. **Fiscal crisis.** When a settlement leaves the treasury below zero the
    city is in fiscal crisis: auto-budget is switched off, the player is
    notified, and the newspaper reports the deficit.
14. **Bankruptcy.** When the treasury is below `BANKRUPTCY_FUNDS` at a
    settlement or at a monthly accrual, `stats.bankrupt` becomes true and the
    player is notified once. The books keep running so the review can still
    show the damage. When a later check finds the treasury back at or above
    `BANKRUPTCY_FUNDS`, the flag clears and a further collapse notifies again.
15. **Estimates.** `estimated_income()` and `estimated_expenses()` are twelve
    months at the current settings and counts, computed on demand, so the
    budget window updates as the player drags a slider. The map survey behind
    them (assessed value, service buildings, transport tiles) is reused while
    the building and zone layers are unchanged, so several estimates per
    slider tick cost one survey.

## Parameters

| Name | Tunes |
|---|---|
| `ZONE_VALUE` | assessed base value of a zone building by category and footprint |
| `STAGE_MULTIPLIER` | how much each development stage adds to the base value |
| `STAGES_PER_FOOTPRINT` | number of stages a footprint group is divided into |
| `ARCOLOGY_VALUE` | assessed residential value of one arcology |
| `SERVICE_UPKEEP` | yearly dollars per police/fire/hospital/school/college at full funding |
| `TRANSPORT_UPKEEP_CENTS` | yearly cents per tile for each transport category at full funding |
| `FARE_CENTS` | cents earned per transit rider |
| `BOND_MIN`, `BOND_MAX`, `BOND_DEFAULT` | allowed bond sizes |
| `MAX_BONDS` | how many bonds may be outstanding at once |
| `DEBT_WEIGHT` | how strongly existing debt raises the credit index |
| `CREDIT_LIMIT` | credit index at which the bank refuses to lend |
| `PRIME_MIN`, `PRIME_MAX` | range of the prime rate |
| `BANKRUPTCY_FUNDS` | treasury level below which the city is bankrupt |

## Save state

`save()` stores the exact per-account year-to-date amount (in twelfths of a
yearly cent, so a city loaded mid-year books exactly what it would have
booked), the year of the last settlement, and the crisis flags
(`deficit_reported`, `bankruptcy_reported`).
`stats.ledger`, `stats.last_year_ledger`, `stats.bonds`, `stats.prime_rate`,
`stats.city_value`, `stats.auto_budget` and `stats.bankrupt` are saved with
`CityStats`.
