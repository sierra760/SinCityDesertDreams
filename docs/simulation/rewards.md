# Rewards, arcologies and the military base

System key: `rewards` (`game/scripts/sim/reward_system.gd`).
Parameters: `game/scripts/sim/data/reward_params.gd` (`RewardParams`).

## Purpose

Rewards are the city's civic prizes. As the ordinary population passes a series
of milestones the city is offered gift buildings it can place for free, and at
one milestone the nation proposes a military base. The same system owns the
resort unlocks and the endgame in which a fleet of Desert Orbit resorts
leaves the city. TourismSystem owns all guest/day attendance.

## Inputs

- `stats.population` – ordinary residents (arcology residents excluded). This
  is the number the milestones test.
- `stats.inventions` – when the economy system fills it, the year an arcology
  design becomes available is read from here under the design's
  `technology` (`resorts_midcentury` or `resorts_millennium`). Otherwise the
  years in `RewardParams` apply. The four neighborhood resorts have no
  technology and year 0.
- Layers `building`, `zone`, `flags`, `pollution`, `crime`, `land_value`,
  `terrain`, `altitude`, `underground` – arcology footprints and their
  surroundings; candidate ground for the military site.
- `city.facilities` – one record per placed arcology, keyed by its anchor tile.

## Outputs

- `stats.rewards_offered[key] = true` once a gift has been offered.
- `stats.rewards_built[key] = true` while a civic gift stands in the city;
  an existing military base keeps this flag because its proposal is one-time.
- `city.facilities[anchor]` retains resort identity, legacy `capacity`,
  `built_year` and `condition` metadata. Current attendance lives only in tourism.
- `arcology_population` stays zero; no resort residents are grown or published.
- Zone layer: accepting the military offer writes `Zones.MILITARY` over the
  chosen site. The port system develops that zone.
- Building layer: launching arcologies become rubble.
- `city.funds` – the launch compensation is credited.

Events:

| Call | Kind | Payload / args |
|---|---|---|
| `notify` | `reward_offered` | `{key}` for gifts; `{key: "military_base", kind, site: [x, y, w, h], sites: [[x, y, w, h], ...]}` for the base |
| `report` | `city_milestone` | `{key, population}` |
| `report` | `military_base` | `{kind, accepted}` |
| `notify` | `exodus` | `{resorts, residents, refund}`: `resorts` is the number of launching arcologies, `residents` a compatibility alias for tourists aboard; `tourists` is explicit |
| `report` | `resort_launch` | `{resorts, residents, refund}` |

## Timing

- **Setup and native restore**: standing rewards are reconciled from the map,
  including older imported saves without reward-system state.
- **Monthly, day 25**: reconciliation of standing rewards, milestone check
  (at most one new offer per month).
- **Yearly** (last day of December): launch check; no annual resident intake or RNG draws.
- **On `networks_changed`**: gifts and arcologies are re-counted from the map
  so that placing or demolishing one takes effect immediately.

## Rules

1. **Milestones.** `RewardParams.MILESTONES` is an ordered list of
   `{key, population}`. The system remembers how many milestones have been
   passed. On day 25, if the next milestone's population is at most
   `stats.population`, that milestone is passed: the key is marked in
   `stats.rewards_offered`, `reward_offered` is notified, `city_milestone` is
   reported. Already earned keys are skipped without another notice or story.
   Only one new reward is offered per month, so a sudden jump still presents
   missing prizes in order. A milestone is never offered twice.
2. **Gifts.** `available()` lists the gift keys that are offered but not
   built. A gift counts as built while at least one tile of its building is
   on the map, or after `mark_built(key)` until the map shows it gone. Demolishing
   a gift makes it available again. Standing imported gifts also mark their
   keys as already offered, even below their population thresholds, so they
   do not generate duplicate offers and remain replaceable after demolition.
3. **Military offer.** The `military_base` milestone does not offer a building.
   The system searches for a site and stores a proposal, readable through
   `military_offer()`. An existing military zone or a building belonging to
   the military category consumes the proposal and locks the reward tool;
   shared civilian airport/seaport pieces alone do not. Detection does not
   infer a base subtype or change its existing development rules:
   - `RewardParams.MILITARY_SITE_ATTEMPTS` random `MILITARY_SITE_SIZE`-square
     origins are tried. A tile is *usable* when it is unzoned, dry, carries
     nothing but rubble or trees, and has no pipe or subway under it. A site
     is accepted when it holds at least `MILITARY_SITE_MIN_USABLE` usable
     tiles. If every usable tile shares the origin's ground height the base is
     an `army` base; otherwise it is an `air` base.
   - Before the land search, if the map has open water and a coin flip
     succeeds, a `naval` site is sought: a square that holds at least
     `MILITARY_SITE_MIN_USABLE` usable tiles and at least
     `MILITARY_NAVAL_MIN_SHORE` usable tiles adjacent to open water.
   - If no square site is found, up to `MILITARY_MISSILE_SITES` separate
     `MILITARY_MISSILE_SITE_SIZE`-squares of usable, level ground are collected
     for a `missile` base; at least one must be found.
   - If nothing suits, the offer is withdrawn (`kind = "none"`) and the
     milestone still counts as passed.
4. **Answering.** `accept_military(rect)` zones every usable tile inside
   `rect` as `Zones.MILITARY` (an empty `rect` uses the proposed site or
   sites), records the base kind and marks the offer answered. The port
   system then develops the zone on its own into runways, hangars, towers,
   motor pools, restricted facilities, piers or silos according to the kind.
   `decline_military()` marks the offer answered with no zoning. Either answer
   is final: the offer never returns.
5. **Arcology availability.** `arcology_available(key)` is true from the
   design's year onward. The year is `stats.inventions[technology]` when
   present, else the year in `RewardParams.ARCOLOGIES`.
   `available_arcologies()` lists the keys currently buildable.
6. **Venue records and attendance.** TourismState discovers canonical standing
   footprints at their actual sizes/rotations, gives each facility a unique
   instance and initializes absent metadata. TourismSystem admits temporary
   guests and day visitors on day 17. Reports, environment loads and current
   counts use that authority; see [Tourism](tourism.md).
7. **Compatibility report.** `arcology_report()` delegates to tourism and
   filters resorts. Its deprecated `residents` field means tourists only;
   it must never be added to permanent population. New consumers use tourism.
8. **Exodus.** On the last day of a year at or after `LAUNCH_YEAR`, if the
   city holds at least `LAUNCH_COUNT` Desert Orbit resorts, all launch and
   become rubble. Current tourists leave immediately; permanent residents
   remain. `LAUNCH_REFUND` is credited for each launching venue with tourists.
   Events include `tourists` and the compatibility alias `residents`.

## Parameters

| Name | Meaning |
|---|---|
| `MILESTONES` | ordered gift keys and the ordinary population that unlocks each |
| `MILITARY_KEY` | the milestone key that proposes a base instead of a gift |
| `MILITARY_SITE_SIZE` | side of the square site sought for land and naval bases |
| `MILITARY_SITE_ATTEMPTS` | random origins tried for a square site |
| `MILITARY_SITE_MIN_USABLE` | usable tiles a square site must contain |
| `MILITARY_NAVAL_MIN_SHORE` | usable shore tiles a naval site must contain |
| `MILITARY_MISSILE_SITES` | number of silo squares sought for a missile base |
| `MILITARY_MISSILE_SITE_SIZE` | side of each silo square |
| `MILITARY_MISSILE_ATTEMPTS` | random origins tried for silo squares |
| `ARCOLOGIES` | building key → `{year, capacity}`; capacity is overnight guests, construction cost /100 (see [Tourism](tourism.md)) |
| `POLLUTION_PER_THOUSAND`, `CRIME_PER_THOUSAND` | pollution and crime per thousand current tourists in tourism reports, applied by the environment system |
| `LAUNCH_KEY`, `LAUNCH_COUNT`, `LAUNCH_YEAR`, `LAUNCH_REFUND` | the exodus design, the fleet size, the earliest year and the compensation per occupied resort |

## Save state

`save()` returns `milestones_passed`, `military` (`{kind, answered, accepted,
site, sites}`), `seen_standing` (the gifts last seen on the map, so their
demolition is noticed after a reload) and an `arcologies` map of
`tile_key → {capacity, built_year, condition}`.
`load()` restores the private state and merges the arcology records back into
`city.facilities` for footprints that still stand, then reconciles standing
rewards against the restored stats. If an older native snapshot has no reward
system entry, `Simulation.restore()` loads empty reward state to perform that
same map reconciliation before the toolbar is refreshed.

## Public interface

```
available() -> Array[StringName]
mark_built(key: StringName) -> void
military_offer() -> Dictionary        # {kind, pending, answered, accepted, site, sites}
military_kind() -> StringName         # "" until a base is accepted
accept_military(rect: Rect2i = Rect2i()) -> bool
decline_military() -> void
arcology_available(key: StringName) -> bool
available_arcologies() -> Array[StringName]
arcology_report() -> Array[Dictionary] # deprecated tourism adapter; residents aliases tourists
```

Legacy resident records are adopted only after final snapshot restoration,
clamped to roster guest capacity, then removed from facilities. This preserves
ordinary resident cohorts, condition/capacity metadata, old histories and earned
unlocks. Repeated save/load is idempotent. Canonical tourism capacity always
comes from the roster, even when preserved legacy capacity metadata differs.
