# Agriculture

Agriculture is an independent land-use family with low-density ($2/tile,
zone 10) and high-density ($5/tile, zone 11) tools. Light olive `#b7c985` and
deep olive `#71884a` identify density in tool icons, ground, zoning overlay
and key, and both Build and Explore maps. Transport symbols keep precedence.
The two densities are available from founding without an invention roll.

## Controls and requirements

The A demand bar sits beside R/C/I. Budget → Agriculture starts at 7% and
accepts 0–20%; its rate and `taxes_agricultural` account are independent of
RCI. Graphs offers demand, active jobs, “Active farms and parcels” and
agricultural tax history. Inspect shows Zoned, Prepared, Active or Dormant, agricultural
density and archetype, field or pasture, actual member area, assigned jobs and
livestock, requested water/power units and whether all members receive their
full load. It also explains what is delaying development. Older square farms
show their original footprint dimensions. Supply labels describe complete
service, not a partial supplied count.

Farm footprints must be flat at one ground height, dry, the same density,
clear of protected/contaminated/burning land, and outside the two-tile city
boundary margin. Road or station access must be within three tiles. All
farms need water. Low-density farms need no power; high-density farms do.
Connected low-density farmland is the search area for automatic parcels, not
one oversized farm. A new parcel has at most 64 member tiles and spans no more
than 12 tiles in either direction. Fields may occupy one tile. New pastures
need at least four connected tiles and a safe connected animal enclosure.
Roads, rail, buildings, water, protected or contaminated land, fire, density
changes and height changes stop growth; touching at a corner does not connect
two members. Holes inside a parcel's bounds remain ordinary city land.

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

The table describes the original fixed-size farms and high-density lots. New
low-density parcels scale jobs by member area using exact units with a
denominator of 36; city employment allocates whole jobs across active parcels
without minting jobs when one splits. Cattle and sheep stock use respectively
8 and 10 units per member tile, with nine units per animal. Saved entitlement
is capped at 108 units per parcel (12 animals), and the enclosure can further
limit the live herd. A split divides the retained per-cell tokens without
refilling them and keeps its failure history. Only newly admitted members can
add entitlement, subject to the same total cap. A large pasture does not bank
extra animals for later splits. Utility loads use the actual member count,
not the bounding rectangle. Prepared/dormant plots consume zero and provide no
jobs or tax; their Inspect requests describe the chosen archetype's recovery
requirements. Full-member utility previews allocate against current source
capacity without changing live networks, storage, facility output or RNG.

## Monthly lifecycle and demand

On days 5 and 6, after RCI growth, eligible land prepares and develops as
parcels. Some parcels use the original square form where it fits; others grow
around obstacles within the size limits. Development waits during emergencies
and when demand is not positive. An active farm tolerates two consecutive failed
months and becomes dormant on the third; service recovery allows it to
prepare and reactivate. Inspect gives the current land/access/service reason.

Each half-city phase shares at most 16 development attempts. One attempt is
reserved for new preparation and, when healthy flexible farms are available,
one for extension; failed waiting activations cannot consume those turns.
Extensions rotate their first candidate by saved month. New preparation gives
low and high density first priority in alternating months, so either density
gets a preparation opportunity within two scheduled months under persistent
waiting-farm pressure. This guarantees an opportunity, not utility service or
a suitable footprint. The existing 33 service-projection and 4,096 frontier-work
ceilings remain. Private RNG and the saved month preserve exact continuation.

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
destinations. Every accessible member frontage of a flexible parcel is a route
to its single assigned job capacity, including disconnected road approaches.
They do not become industrial labor or sector output. Each active
job assesses $100 for the independent tax account; income follows the ordinary
monthly accrual and annual settlement. Prepared/dormant farms have no income.

Each new or migrated low-density parcel has a stable positive ID and an exact
set of member cells. The city saves those members, lifecycle state, stock
entitlement, layout and identity in a versioned parcel store. The agricultural
system saves its demand, phase guards and private RNG; high-density lots keep
their existing path. Older square farms retain their cells, model and enclosure
when loaded. The native format still reads v1 and v2 saves; older executables
are not expected to read the new occupancy codes and parcel records. Monthly
histories use the standard 100-year retention. Rendering and controls do not
perform a render-time census;
Inspect refreshes on selection and completed map/day updates.
