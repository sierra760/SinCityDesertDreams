# Ordinances

## Purpose

Ordinances are city-wide policies the player switches on and off. Each one
either raises money from residents or costs the city a program fee. Twelve of
them also change how another system behaves: more or less crime, cleaner air,
stronger demand, a ban on nuclear plants, and so on. The other eight change
nothing but the treasury. The ordinance system owns the switches, prices the
policies and publishes the flags; the systems that feel the effects read the
flags.

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
4. **Effects.** The systems that feel an ordinance read its flag in
   `stats.ordinances` at their own scheduled step. Every effect, with its
   size, is listed under "Effects by ordinance" below; the sizes are
   parameters of the reading systems, not of this one. No ordinance changes
   the tax rates themselves: property tax and the zones' tax pressure always
   use the player's rates.
5. **Money only.** Sales tax, income tax, parking fines, junior sports, CPR
   training, homeless shelters, tree planting and the annual carnival have
   no effect beyond their fee or program cost. No system reads their flags.
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
   `COUNCIL_RICH_SPREAD`, the council picks one ordinance at random and
   enacts it. The newspaper reports the enactment even when the policy was
   already in force.

### Effects by ordinance

The rate is `YEARLY_RATE`: dollars a year per `PER_CAPITA_UNIT` (10,000)
residents, positive for income and negative for a program cost. The reading
system is named in parentheses; see its page for the full rule.

| Ordinance | Rate | Effect beyond its money |
|---|---|---|
| Sales Tax | +40 | none |
| Income Tax | +133 | none |
| Parking Fines | +67 | none |
| Legalized Gambling | +80 | adds `GAMBLING_CRIME` (16) to the base crime of every developed block (environment) |
| Tourist Advertising | −40 | adds `ORDINANCE_NUDGE_SMALL` (25) to commercial demand each month (zones) |
| Business Advertising | −40 | adds `ORDINANCE_NUDGE_LARGE` (50) to commercial demand each month (zones) |
| Volunteer Fire Department | −44 | adds `VOLUNTEER_FIRE_COVERAGE` (8) to the fire cover of every cell, up to 255 (services) |
| Public Smoking Ban | −7 | adds `HEALTH_ORDINANCE_BONUS` (5) to the health of each newborn served by a hospital place and `LE_ORDINANCE_BONUS` (1) to life expectancy (population) |
| Free Clinics | −67 | adds one hospital place per `FREE_CLINIC_DIVISOR` (400) residents and `LE_ORDINANCE_BONUS` (1) to life expectancy (population) |
| Junior Sports | −33 | none |
| Anti-Drug Campaign | −27 | the same health effects as the public smoking ban (population); no effect on crime |
| Neighborhood Watch | −44 | subtracts `WATCH_CRIME_RELIEF` (8) from the base crime of every developed block (environment) |
| CPR Training | −22 | none |
| Pollution Controls | −40 | cuts industrial emission by `POLLUTION_CONTROLS_PERCENT` (25%) (environment); subtracts `ORDINANCE_NUDGE_LARGE` (50) from industrial demand each month (zones); scales the heavy sectors' weights by `POLLUTION_CONTROL_SCALE` (0.9) (economy) |
| Energy Conservation | −133 | adds `capacity / CONSERVATION_BONUS_DIVISOR` (one twelfth) to every power network's budget (power) |
| Nuclear Free Zone | 0 | locks the nuclear plant tool (Rule 6) |
| Homeless Shelters | −67 | none |
| Pro-Reading Campaign | −22 | adds `ORDINANCE_NUDGE_SMALL` (25) to residential demand each month (zones); residents moving up an age cohort keep their education instead of losing `EQ_DECAY` (1) (population) |
| Tree Planting | −33 | none |
| Annual Carnival | −7 | none |

## Parameters

| Name | Tunes |
|---|---|
| `PER_CAPITA_UNIT` | the number of residents each yearly rate is quoted against |
| `YEARLY_RATE` | dollars per `PER_CAPITA_UNIT` residents for each ordinance |
| `COUNCIL_CHANCE_DENOMINATOR` | how rarely the council acts on its own |
| `COUNCIL_RICH_FUNDS`, `COUNCIL_RICH_SPREAD` | how rich the city must be before the council spends |

`DEMAND_TAX_SHIFT` and `ENERGY_CONSERVATION_BONUS_TWELFTHS` remain in
`OrdinanceParams` but only feed the helper queries `effective_tax_rates()` and
`power_capacity_bonus()`, which nothing in the game calls. Energy conservation
is sized by the power system's `CONSERVATION_BONUS_DIVISOR`.

## Save state

Ordinance switches live in `stats.ordinances` and are saved with `CityStats`.
The system's own `save()` is empty; `load()` only re-publishes the flags and
totals.
