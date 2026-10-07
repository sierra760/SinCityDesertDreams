# Transport maintenance and wear

## Purpose

The wear system makes underfunded transport networks fall apart. Each of
the six transport categories has a funding slider; below full funding the
category accrues wear every month, and once enough has built up a random
piece of that network is lost: a road, rail or tunnel tile turns to rubble,
a block of highway is torn out, a subway segment caves in, or a whole bridge
collapses. Full funding stops the decay but never repairs anything; the
player pays to rebuild. The system also tells the budget what each category
costs to maintain and how many tiles it has.

## Inputs

- `building` layer: roads, highways, ramps, bridges, tunnel entrances, rail
  and subway portals.
- `underground` layer: subway tunnels, pipe/subway crossings and station
  links.
- `terrain` layer: whether a lost tile stands over water (it leaves no
  rubble there).
- `stats.funding`: the percentages under `roads`, `highways`, `bridges`,
  `rail`, `subway` and `tunnels`.
- `ctx.rng`: jitter on monthly wear and the choice of which tile is lost.

## Outputs

- `building` layer: lost tiles become rubble (`RUBBLE_1`–`RUBBLE_4`), or
  open ground over water.
- `underground` layer: a lost subway segment becomes `0`.
- `flags` layer: `CONDUCTS_POWER` and `POWERED` are cleared on lost tiles
  (a crossing under a power line no longer carries it).
- `ctx.events.mark_dirty` for every changed tile.
- News: `road_decay` `{x, y, category}` for a lost road, highway block or
  tunnel entrance; `rail_decay` `{x, y, category}` for a lost rail tile or
  subway segment; `bridge_collapse` `{x, y, tiles}` for a collapsed bridge.
- Getters:

  | Method | Meaning |
  |---|---|
  | `network_counts() -> Dictionary` | tiles per category, keyed by the six category names |
  | `maintenance_cost(category, funding_percent = 100) -> int` | yearly upkeep in dollars of one category at that funding level; the budget calls it with the default and applies the slider itself |
  | `maintenance_total(funding = true) -> int` | all six categories together, at current funding or at full funding |
  | `wear_percent(category) -> int` | how close the category is to its next loss, 0–100 |
  | `losses() -> Dictionary` | tiles lost so far per category |

## Timing

- `setup`: count the networks.
- Monthly, day 18: accrue wear and apply losses (rules 3–6).
- `networks_changed`: forget the cached counts; they are recounted on the
  next call that needs them. The counts are also recounted whenever the
  building or underground layer differs from the last count, so disasters,
  ports, rewards and growth that edit the map never leave upkeep or losses
  working from a stale network.
- Nothing runs daily or yearly.

## Rules

1. **Categories.** Every network tile belongs to exactly one category:

   | Category | Tiles |
   |---|---|
   | `roads` | roads, roads under power lines, level crossings of every kind |
   | `highways` | highway lanes, slopes, corners, interchanges, ramps, highway-over-road, highway-over-rail, highway-under-power, reinforced (highway) bridges |
   | `bridges` | suspension, lift, causeway and rail bridge tiles |
   | `rail` | rail, rail with power line, rail under power lines, subway portals |
   | `subway` | every underground code that carries a subway: tunnels, pipe/subway crossings and station links |
   | `tunnels` | tunnel entrances |

   Elevated power lines are not transport and belong to no category.
2. **Upkeep.** `maintenance_cost(category, funding)` is
   `count × UPKEEP_CENTS[category] / 100 × funding / 100` dollars per year.
   Roads are the cheapest per tile; bridges, subways and tunnels the
   dearest.
3. **Accrual.** On day 18 each category with at least one tile and funding
   below 100 gains `count × (100 − funding)` wear points, jittered by a
   random factor between `100 − WEAR_JITTER_PERCENT` and
   `100 + WEAR_JITTER_PERCENT` percent. A category at full funding gains
   nothing, and a category with no tiles has its wear reset to zero.
4. **Losses.** While a category's wear is at least `WEAR_THRESHOLD[category]`
   and the category still has losable tiles, the threshold is subtracted and
   one loss happens at a tile chosen uniformly at random from that
   category. A chosen tile that an earlier loss in the same pass already
   removed (part of a collapsed bridge or a lost highway block) is dropped
   without using any wear and without a story. Wear left below the threshold carries over to the next month,
   even after funding is restored, so restoring funding stops further loss
   but does not undo the damage or clear the accrued wear.
5. **What a loss removes.**
   - `roads`, `rail`, `tunnels`: the chosen tile becomes rubble. Rail loss
     never picks a subway portal.
   - `highways`: the 2×2 block aligned to even coordinates that contains the
     chosen tile loses every highway tile in it; each becomes rubble, or open
     ground when it stands over water.
   - `bridges`: every bridge tile connected to the chosen one through other
     bridge tiles (four neighbors) is removed, leaving open ground. The story
     reports the number of tiles lost.
   - `subway`: the chosen tunnel segment's underground code becomes `0`.
     Pipe/subway crossings and station links are counted for upkeep but are
     never chosen, so the pipe beneath is never damaged by subway wear.
6. **Aftermath.** Every lost tile is reported through `mark_dirty`, the
   cached counts are dropped, and a story is queued (`road_decay`,
   `rail_decay` or `bridge_collapse`). Lost tiles stay lost until the player
   rebuilds them.

## Parameters

| Name | Value | Tunes |
|---|---|---|
| `WEAR_THRESHOLD[roads]` | 20000 | Wear points per lost road tile; at zero funding about half a percent of the roads are lost each month. |
| `WEAR_THRESHOLD[highways]` | 40000 | Wear points per lost highway block (four tiles). |
| `WEAR_THRESHOLD[bridges]` | 5000 | Wear points per collapsed bridge; bridges fail fastest. |
| `WEAR_THRESHOLD[rail]` | 15000 | Wear points per lost rail tile. |
| `WEAR_THRESHOLD[subway]` | 20000 | Wear points per lost subway segment. |
| `WEAR_THRESHOLD[tunnels]` | 20000 | Wear points per lost tunnel entrance. |
| `WEAR_JITTER_PERCENT` | 25 | Random spread applied to each month's accrual. |
| `UPKEEP_CENTS[roads]` | 10 | Yearly upkeep per road tile at full funding, in cents. |
| `UPKEEP_CENTS[highways]` | 30 | Per highway tile. |
| `UPKEEP_CENTS[bridges]` | 40 | Per bridge tile. |
| `UPKEEP_CENTS[rail]` | 25 | Per rail tile. |
| `UPKEEP_CENTS[subway]` | 50 | Per subway tile. |
| `UPKEEP_CENTS[tunnels]` | 50 | Per tunnel entrance. |

## Save state

`save()` returns `{"wear": {category: points}, "losses": {category: tiles
lost}}`. Counts are recomputed from the map.
