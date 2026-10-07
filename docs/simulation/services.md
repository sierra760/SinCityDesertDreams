# Services: police, fire, prisons and civic facilities

## Purpose

The services system turns funded, powered service buildings into the
quarter-resolution `police` and `fire_cover` maps, runs the prisons, and
exposes the civic facility counts (hospitals, schools, colleges, libraries,
museums) that the population system needs.

## Inputs

Layers: `building`, `zone` (footprint corner flags locate anchors), `flags`
(powered bit), `crime` (half) for arrests.

Stats: `funding` for `police`, `fire`, `health`, `schools`, `colleges`;
`ordinances` for `volunteer_fire`.

Facilities: prison records in `city.facilities` are updated in place when
present.

## Outputs

Layers written: `police`, `fire_cover` (both 32×32, 0..255). During an escape
the `crime` map near the prison is raised.

News reported: `prison_escape` (`{"count": n, "x": ax, "y": ay}`) for each
prison that loses inmates in a month.

Getters:

- `police_strength_at(x, y) -> int` and `fire_strength_at(x, y) -> int`:
  coverage at a tile, 0..255.
- `prison_report() -> Dictionary`: `prisons`, `inmates`, `guards`,
  `capacity`, `utilization` (percent), `escapes` (this year), `modifier`
  (0 or 1) and `records` (one dictionary per prison with `x`, `y`,
  `inmates`, `guards`, `capacity`, `utilization`, `escapes`, `powered`).
- `service_counts() -> Dictionary`: keyed by building key (`hospital`,
  `school`, `college`, `library`, `museum`); each `{"count": n, "powered": m,
  "funding": percent}`. Counts are refreshed monthly and after construction.
- `police_modifier() -> int`: the prison modifier applied to police coverage.

## Timing

Scheduled monthly job on day 12: facility scan, prison update, then coverage
maps. The environment pass on day 10 of the following month reads the
resulting coverage. `yearly` resets the escape counters. Nothing runs daily.

## Rules

A service building is **powered** when any tile of its footprint carries the
powered flag. Stations are located by their footprint anchor
(`City.anchor_of`), also in imported cities saved at another rotation, whose
north-west corner flag sits on another corner of the lot.

### Coverage maps

1. Both maps are cleared and rebuilt every pass.
2. A police station's strength is `funding_police × (POLICE_BASE_EFFECT +
   police modifier) / 2`; a fire station's is `funding_fire ×
   FIRE_BASE_EFFECT / 2`. An unpowered station has half strength.
3. Strength is stamped on the quarter cell under the station's center and
   spreads outward in rings: the center cell at `RING_PERCENT[0]`, the four
   cardinal neighbors at `RING_PERCENT[1]`, the four diagonals at
   `RING_PERCENT[2]`, the twelve cells two steps away at `RING_PERCENT[3]`
   and the sixteen cells three steps away at `RING_PERCENT[4]`. Only rings up
   to `1 + funding × MAX_RING / 100` are stamped, so underfunding shrinks the
   radius as well as the strength.
4. Overlapping stations add; cells clamp to 255.
5. While `volunteer_fire` is enabled, every fire cell gains
   `VOLUNTEER_FIRE_COVERAGE` after stamping.

### Prisons

6. Each prison has a record with inmates, guards, escapes and utilization.
   Guards are `funding_police × GUARDS_PER_FUNDING_POINT`. Capacity is
   `max(guards, MIN_GUARDS) × INMATES_PER_GUARD`.
7. Each month the city's arrests are the crime map total divided by
   `CRIME_PER_ARREST`, split evenly across prisons. Each prison releases
   `inmates / RELEASE_DIVISOR` and admits its share of arrests. Inmates never
   exceed `MAX_INMATES`.
8. Utilization is `inmates × 100 / capacity`. When it exceeds
   `ESCAPE_UTILIZATION`, between 1 and `utilization - ESCAPE_UTILIZATION +
   (100 - funding) / 10` inmates escape (a random draw), the news is
   reported, the escaped inmates leave the record, and every developed crime
   block within `ESCAPE_CRIME_RADIUS` blocks of the prison anchor gains
   `ESCAPE_CRIME_BUMP`.
9. The **police modifier** is 1 when at least one powered prison exists and
   the mean utilization is below `STRAINED_UTILIZATION`, otherwise 0. It
   raises the police strength formula above.

### Civic facilities

10. Hospitals, schools, colleges, libraries and museums are counted by
    anchor; the powered count uses the same footprint rule. Funding for the
    count report is `health` for hospitals, `schools` for schools, `colleges`
    for colleges, and 100 for libraries and museums.

## Parameters

| Name | Default | Tunes |
|---|---|---|
| `POLICE_BASE_EFFECT`, `FIRE_BASE_EFFECT` | 5, 5 | strength at full funding (× 100 / 2 = 250) |
| `RING_PERCENT` | 100, 80, 60, 40, 20 | falloff per ring |
| `MAX_RING` | 3 | rings beyond the center added by full funding |
| `VOLUNTEER_FIRE_COVERAGE` | 8 | baseline fire cover under the ordinance |
| `GUARDS_PER_FUNDING_POINT` | 3 | guards at a funding level (300 at 100) |
| `MIN_GUARDS` | 30 | skeleton staff when funding is cut |
| `INMATES_PER_GUARD` | 33 | prison capacity per guard |
| `CRIME_PER_ARREST` | 500 | crime map total per monthly arrest |
| `RELEASE_DIVISOR` | 48 | share of inmates released each month |
| `MAX_INMATES` | 10000 | hard cap per prison |
| `ESCAPE_UTILIZATION` | 90 | utilization above which escapes happen |
| `STRAINED_UTILIZATION` | 80 | utilization at which the police modifier is lost |
| `ESCAPE_CRIME_BUMP`, `ESCAPE_CRIME_RADIUS` | 32, 6 | crime raised near an escape |

## Save state

Prison records keyed by anchor tile key, the current police modifier and the
last arrest count. The coverage maps are saved with the city layers.
