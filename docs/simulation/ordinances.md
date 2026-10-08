# Ordinances

## Purpose

Ordinances are city-wide policies the player switches on and off. Each one
either raises money from residents or costs the city a program fee, and every
one also changes how another system behaves: the tax rate a family feels,
crime, cleaner air, health, education, the March vote, a ban on nuclear
plants, and so on. No policy is money only. The ordinance system owns the
switches, prices the policies and publishes the flags; the systems that feel
the effects read the flags.

## Inputs

- `stats.population` and `stats.arcology_population`: fees and program costs
  scale with the number of residents.
- `city.funds` and `stats.disasters_enabled`: the city council only enacts
  policies on its own when the city is rich and the world is eventful.

## Outputs

- `stats.ordinances`: one boolean per ordinance key, always present.
- `stats.ordinance_income`, `stats.ordinance_cost`: yearly dollars at the
  current population, refreshed every month and whenever a switch changes.
- `yearly_totals()`: `{income, cost}` in yearly dollars for the enabled
  ordinances, read by the budget when it books the month.
- `OrdinanceSystem.effective_rates(stats)`: the residential, commercial and
  industrial tax rates the city feels, read by zone demand and the March vote
  (Rule 4).
- News `&"ordinance_enacted"` with `{key, name}` when the council enacts a
  policy on its own.

## Timing

- Scheduled day 18 of every month, after the budget has booked the month.
- Nothing daily or yearly.

## Rules

1. **Catalog.** There are twenty ordinances in three groups.
   Finance: sales tax, income tax, parking fines, legalized gambling, tourist
   advertising, business advertising. Safety and health: volunteer fire
   department, public smoking ban, free clinics, junior sports, anti-drug
   campaign, neighborhood watch, CPR training. City: pollution controls,
   energy conservation, nuclear free zone, homeless shelters, pro-reading
   campaign, tree planting, annual carnival.
2. **Fees.** Every ordinance has a yearly rate in dollars per
   `PER_CAPITA_UNIT` residents (positive for income, negative for a program
   cost). Its yearly amount is `total_population × rate / PER_CAPITA_UNIT`,
   truncated toward zero. The sum of the positive amounts of the enabled
   ordinances is `ordinance_income`; the sum of the negative amounts, made
   positive, is `ordinance_cost`. The budget books one twelfth of each every
   month, so switching an ordinance mid-year changes only the months that
   follow.
3. **Switching.** `set_enabled(key, on)` flips a switch at once and refreshes
   the yearly totals. Unknown keys are ignored.
4. **Felt tax rates.** `effective_rates(stats)` starts from the player's
   three rates and adds the one-point shift in `DEMAND_TAX_SHIFT` for every
   enabled ordinance in that table, never going below zero. Zone demand uses
   these felt rates for its tax pressure, and the March vote uses the felt
   residential rate for the taxes complaint. Property tax always charges the
   player's own rates; no ordinance changes `stats.tax_*`.
5. **Effects.** The systems that feel an ordinance read its flag in
   `stats.ordinances` at their own scheduled step. Every effect, with its
   size, is listed under "Effects by ordinance" below; the sizes are
   parameters of the reading systems, not of this one. A test scans the
   simulation sources and fails if any catalog key is read by nothing.
6. **Nuclear free zone.** While `stats.ordinances[&"nuclear_free_zone"]` is
   on, `Tools.locked_reason` locks the nuclear power plant tool with "the
   Nuclear Free Zone ordinance forbids nuclear plants". The toolbar shows the
   tool locked with that reason, and every `Builder` preview and apply of it
   fails with the same reason and charges nothing. Nuclear plants already
   standing keep running, and switching the ordinance off (or the council
   enacting it) takes effect at the next toolbar refresh and the next
   placement.
7. **Council enactment.** Each month, with probability
   `1 / COUNCIL_CHANCE_DENOMINATOR`, when disasters are enabled and the
   treasury exceeds `COUNCIL_RICH_FUNDS` plus a random amount up to
   `COUNCIL_RICH_SPREAD`, the council picks one ordinance at random from those
   not yet in force and enacts it, and the newspaper reports it. When every
   ordinance is already in force the council does nothing.

### Effects by ordinance

The rate is `YEARLY_RATE`: dollars a year per `PER_CAPITA_UNIT` (10,000)
residents, positive for income and negative for a program cost. The reading
system is named in parentheses; see its page for the full rule.

| Ordinance | Rate | Effect beyond its money |
|---|---|---|
| Sales Tax | +40 | commercial felt rate +1 (zones) |
| Income Tax | +133 | residential felt rate +1: weaker residential demand and a louder taxes complaint in the March vote (zones, population) |
| Parking Fines | +67 | adds `VOTE_PARKING_FINES_WEIGHT` (3) to the taxes complaint in the March vote (population) |
| Legalized Gambling | +80 | adds `GAMBLING_CRIME` (16) to the base crime of every developed block (environment) |
| Tourist Advertising | −40 | commercial felt rate −1 (zones) |
| Business Advertising | −40 | industrial felt rate −1 (zones) |
| Volunteer Fire Department | −44 | adds `VOLUNTEER_FIRE_COVERAGE` (8) to the fire cover of every cell, up to 255 (services) |
| Public Smoking Ban | −7 | adds `HEALTH_ORDINANCE_BONUS` (5) to the health of each newborn served by a hospital place and `LE_ORDINANCE_BONUS` (1) to life expectancy (population) |
| Free Clinics | −67 | adds one hospital place per `FREE_CLINIC_DIVISOR` (400) residents and `LE_ORDINANCE_BONUS` (1) to life expectancy (population) |
| Junior Sports | −33 | subtracts `JUNIOR_SPORTS_CRIME_RELIEF` (4) from the base crime of every developed block (environment); children aging into a school cohort gain `JUNIOR_SPORTS_EQ_GAIN` (2) education each (population) |
| Anti-Drug Campaign | −27 | the same health effects as the public smoking ban (population); subtracts `ANTI_DRUG_CRIME_RELIEF` (4) from the base crime of every developed block (environment) |
| Neighborhood Watch | −44 | subtracts `WATCH_CRIME_RELIEF` (8) from the base crime of every developed block (environment) |
| CPR Training | −22 | prevents `CPR_MORTALITY_RELIEF` (10) percent of the deaths left after hospital relief (population) |
| Pollution Controls | −40 | cuts industrial emission by `POLLUTION_CONTROLS_PERCENT` (25%) (environment); industrial felt rate +1 (zones); scales the heavy sectors' weights by `POLLUTION_CONTROL_SCALE` (0.9) (economy) |
| Energy Conservation | −133 | adds `capacity / CONSERVATION_BONUS_DIVISOR` (one twelfth) to every power network's budget (power) |
| Nuclear Free Zone | 0 | locks the nuclear plant tool (Rule 6) |
| Homeless Shelters | −67 | commercial felt rate −1 (zones); adds `VOTE_SHELTER_CONTENT` (10) to the contentment weight of the March vote (population) |
| Pro-Reading Campaign | −22 | adds `READING_NUDGE` (25) to residential demand each month (zones); residents moving up an age cohort keep their education instead of losing `EQ_DECAY` (1) (population) |
| Tree Planting | −33 | residential felt rate −1 (zones); every ordinary street tile absorbs `STREET_TREE_ABSORPTION` (1) pollution (environment) |
| Annual Carnival | −7 | commercial felt rate −1 (zones) |

One felt-rate point is worth `TAX_BELOW_PER_POINT` or the matching penalty
(25 to 50) of monthly demand change, depending on how far the rate is from
neutral (see zones.md).

## Parameters

| Name | Tunes |
|---|---|
| `PER_CAPITA_UNIT` | the number of residents each yearly rate is quoted against |
| `DEMAND_TAX_SHIFT` | the one-point felt-rate shift each ordinance applies to residential, commercial and industrial |
| `YEARLY_RATE` | dollars per `PER_CAPITA_UNIT` residents for each ordinance |
| `COUNCIL_CHANCE_DENOMINATOR` | how rarely the council acts on its own |
| `COUNCIL_RICH_FUNDS`, `COUNCIL_RICH_SPREAD` | how rich the city must be before the council spends |

## Save state

Ordinance switches live in `stats.ordinances` and are saved with `CityStats`.
The system's own `save()` is empty; `load()` only re-publishes the flags and
totals.
