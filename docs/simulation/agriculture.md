# Agriculture

Agriculture is an independent land-use family with low-density ($2/tile,
zone 10) and high-density ($5/tile, zone 11) tools. Light olive `#b7c985` and
deep olive `#71884a` identify density in tool icons, ground, zoning overlay
and key, and both Build and Explore maps. Transport symbols keep precedence.
The two densities are available from founding without an invention roll.

## Controls and requirements

The A demand bar sits beside R/C/I. Budget → Agriculture starts at 7% and
accepts 0–20%; its rate and `taxes_agricultural` account are independent of
RCI. Graphs offers demand, active jobs, active lot count and agricultural tax
history. Inspect shows Zoned, Prepared, Active or Dormant, agricultural
density and archetype, active jobs, requested water/power units and whether
all tiles receive their full load, plus the live development reason. Supply
labels describe full-footprint service; they are not partial supplied counts.

Farm footprints must be flat at one ground height, dry, the same density,
clear of protected/contaminated/burning land, and outside the two-tile city
boundary margin. Road or station access must be within three tiles. All
farms need water. Low-density farms need no power; high-density farms do.

| Density | Archetype | Footprint | Jobs | Water/tile | Power/tile |
| --- | --- | --- | --- | --- | --- |
| Low | Irrigated vegetables | 1×1 | 4 | 3 | 0 |
| Low | Alfalfa and hay | 2×2 | 6 | 3 | 0 |
| Low | Grain | 2×2 | 4 | 1 | 0 |
| Low | Cattle range | 3×3 | 6 | 1 | 0 |
| Low | Sheep pasture | 3×3 | 5 | 1 | 0 |
| High | Greenhouse | 1×1 | 10 | 2 | 2 |
| High | Nursery | 2×2 | 24 | 2 | 1 |
| High | Dairy | 3×3 | 40 | 3 | 1 |
| High | Feedlot | 3×3 | 32 | 2 | 1 |
| High | Market garden | 2×2 | 24 | 3 | 1 |

Jobs are per lot, utility loads per tile. Multiply each load by footprint area
for the requested total. Prepared/dormant plots consume zero and provide no
jobs or tax; their Inspect requests describe the chosen archetype's recovery
requirements. Full-footprint utility previews allocate against current source
capacity without changing live networks, storage, facility output or RNG.

## Monthly lifecycle and demand

On days 5 and 6, after RCI growth, eligible land prepares, develops or combines
into larger same-density lots. Development waits during emergencies and when
demand is not positive. An active farm tolerates two consecutive failed
months and becomes dormant on the third; service recovery allows it to
prepare and reactivate. Inspect gives the current land/access/service reason.

Raw agricultural demand starts at 1000 and clamps to −2000…2000. Target jobs
are `clamp(20 + ordinary_population / 40 + connected_city_links * 40, 20, 2000)`.
Once per month, demand changes by
`clamp((target_jobs - active_agricultural_jobs) * 8, -400, 400)` plus the
existing tax-pressure curve evaluated at the independent agricultural rate.
Display demand is `raw * 999 / 2000`, truncated toward zero. Saved RCI demand
remains a three-component value; the fourth display bar reads a separate
scalar. Farm growth uses a private saved RNG and never draws shared simulation
randomness. Cosmetic animal motion cannot change growth, funds or city layers.

## Employment, income and persistence

Active jobs contribute once to shared employment, housing demand and commute
destinations. They do not become industrial labor or sector output. Each active
job assesses $100 for the independent tax account; income follows the ordinary
monthly accrual and annual settlement. Prepared/dormant farms have no income.

Farm state, archetype, anchors, failure counters, raw demand and private RNG
state persist through the agricultural system. Existing native save v2 uses
16-bit building codes and still reads v1. Monthly histories use the standard
100-year retention. Rendering and controls do not perform a render-time census;
Inspect refreshes on selection and completed map/day updates.
