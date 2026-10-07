# Neighbors

## Purpose

Four neighboring towns sit beyond the map edges, one per edge. They grow and
shrink with the national economy, they grow faster when the player's roads and
rails reach them, and they buy the city's surplus power and water (or sell the
city what it lacks) when a line or pipe reaches the edge. The neighbor window
compares the city with them.

## Inputs

- `city.building`, `city.flags`, `city.underground` along the four border
  lines: which networks reach each edge.
- `stats.economy_phase`: the national trend, 0 (recession) to 3 (boom).
- `stats.power_capacity`, `stats.power_demand`, `stats.water_capacity`,
  `stats.water_demand`: the city's utility balance for trade.
- `ctx.rng`: founding populations, growth jitter and shocks.

## Outputs

- `stats.neighbor_populations`: four populations, indexed by edge
  (0 north, 1 east, 2 south, 3 west).
- `stats.ledger[&"neighbor_trade"]`: year-to-date trade balance in dollars,
  positive when the city sells more than it buys. The budget settles it as an
  income account.
- `neighbor_report()`: one entry per neighbor with name, edge, population,
  output, connections and this year's trade.
- News `&"neighbor_shock"` with `{name, edge}` when a neighbor's economy
  collapses.
- News `&"neighbor_connection"` with `{name, edge, kind}` when the player
  accepts and builds a road, rail, power or water link onto an edge
  (`record_connection(edge, kind)`, called by the builder). The flag is set at
  once; the next scan keeps it current.

## Timing

- Setup: found the four towns the first time a city is simulated.
- Scheduled day 24 of every month: rescan connections, grow, trade.
- Yearly: reset the trade carry after the budget has settled it.
- `networks_changed`: rescan connections so the window is current.

## Rules

1. **Founding.** Each neighbor takes a distinct name from `NAME_POOL` and a
   population equal to the smallest of three draws of
   `FOUNDING_MIN + rng.below(FOUNDING_SPREAD)`. Its output starts at the
   population divided by `1 + rng.below(OUTPUT_DIVISOR_SPREAD)`.
2. **Connections.** A neighbor is road-connected when a road, highway or
   crossing tile lies on its edge; rail-connected when a rail or subway
   portal tile does; power-connected when a tile on the edge conducts power
   or is a power line; water-connected when a tile on the edge conducts
   water or has any code in the underground layer.
3. **Growth.** Each month every neighbor with a nonzero population draws a
   rate of `economy_phase + rng.below(GROWTH_JITTER)`, plus
   `LINK_GROWTH_BONUS` for each of its road and rail links. The change is
   `population × rate / GROWTH_DIVISOR`, truncated. Populations above
   `POPULATION_CEILING` shrink by the change instead of growing. A zero
   change adds `rng.below(2)` so tiny towns still drift.
4. **Output.** Output follows the population with its own rate:
   `PHASE_OUTPUT_RATE[economy_phase] + rng.below(OUTPUT_JITTER)`, applied as
   `output × rate / GROWTH_DIVISOR`, shrinking above `OUTPUT_CEILING`. Output
   never falls below zero.
5. **Shocks.** After all four have grown, with probability
   `1 / SHOCK_CHANCE_DENOMINATOR`, one neighbor chosen at random keeps
   `SHOCK_POPULATION_PERCENT` percent of its population and
   `SHOCK_OUTPUT_PERCENT` percent of its output, and the newspaper reports it.
6. **Trade.** For each utility, when at least one edge is connected: a
   surplus (capacity minus demand, capped at `TRADE_UNIT_CAP`) earns
   `EXPORT_CENTS[utility]` per unit per year; a deficit costs
   `IMPORT_CENTS[utility]` per unit per year. One twelfth is booked each
   month, with fractions carried in cents, into `neighbor_trade`. Trade needs
   a connection; a surplus with no line to the edge earns nothing.
7. **Demand.** Links add nothing to demand. The zone system counts every
   neighbor with people toward the commercial market and cap, linked or not
   (see zones.md). `commercial_demand_bonus()` (links × `DEMAND_PER_LINK`)
   has no callers.

## Parameters

| Name | Tunes |
|---|---|
| `NAME_POOL` | the names neighbors are drawn from |
| `FOUNDING_MIN`, `FOUNDING_SPREAD` | founding population range |
| `OUTPUT_DIVISOR_SPREAD` | how far founding output lags population |
| `GROWTH_JITTER`, `GROWTH_DIVISOR` | monthly population growth speed and noise |
| `LINK_GROWTH_BONUS` | growth added per road or rail link |
| `POPULATION_CEILING` | population above which neighbors shrink |
| `PHASE_OUTPUT_RATE`, `OUTPUT_JITTER`, `OUTPUT_CEILING` | output growth by national phase |
| `SHOCK_CHANCE_DENOMINATOR`, `SHOCK_POPULATION_PERCENT`, `SHOCK_OUTPUT_PERCENT` | rarity and depth of a regional collapse |
| `EXPORT_CENTS`, `IMPORT_CENTS`, `TRADE_UNIT_CAP` | utility trade prices and the export cap |
| `DEMAND_PER_LINK` | per-link figure of `commercial_demand_bonus()`, which nothing reads |

## Save state

`save()` stores the four name indices, outputs, connection flags, the trade
carry in cents and this year's trade per neighbor. Populations are saved in
`stats.neighbor_populations` with `CityStats`.
