# Tourism and visitor taxes

`TourismSystem` owns current attendance, completed monthly visitor business and
pure forecasts. `TourismState` owns one record per canonical standing venue
instance. `TourismDemand` supplies deterministic allocation and turnover;
`TourismParams` names common constants; `TourismMarkets` owns finite segments and the immutable weighted business profile. Budget owns all tax accrual and settlement.

## People and capacities

Permanent population means residential residents and cohorts. Tourists are
current overnight guests plus mutually exclusive day visitors. A guest who
also gambles is counted once. Arrivals, departures, activity and rendered crowd
models are not extra population. Tourists do not supply workforce, votes,
educational attainment, settlement class or resident milestones.

Canonical overnight capacity is measured in **guests**, not rooms or permanent
residents. These design capacities scale as unchanged construction cost /100;
roughly two guests per room gives their intended scale without a room-count
subsystem. Footprints, construction costs, unlocks and identities are unchanged.

| Resort key | Construction cost | Overnight guests |
|---|---:|---:|
| `arcology_boddy` | $8,000 | 80 |
| `arcology_woolier` | $16,000 | 160 |
| `arcology_stockgrowers` | $30,000 | 300 |
| `arcology_fremont` | $45,000 | 450 |
| `arcology_last` | $60,000 | 600 |
| `arcology_dust` | $95,000 | 950 |
| `arcology_comstock` | $100,000 | 1,000 |
| `arcology_junction` | $120,000 | 1,200 |
| `arcology_alibi` | $140,000 | 1,400 |
| `arcology_boulder` | $150,000 | 1,500 |
| `arcology_orbit` | $200,000 | 2,000 |
| `arcology_velvet` | $220,000 | 2,200 |
| `arcology_fix` | $320,000 | 3,200 |
| `arcology_afterglow` | $500,000 | 5,000 |

Day capacity is `clamp(floor(sqrt(guest_capacity)),16,300)`.
Each Despicable's has zero beds and 24 concurrent day places. Counts stay within
venue capacity and citywide finite demand; unused beds cannot create visitors.

## Demand and turnover

The unadjusted overnight pool is `250 + population/2 + min(50000,neighbors/100)`.
National recession-to-boom multipliers are 70%,90%,100%,115%. Day demand starts
at one third of the economy-adjusted pool. City and local appeal each use
`clamp(70 + land_value/8 - crime/8 - pollution/8 - traffic/16,10,100)` with one
final integer division. Tourist Advertising adds ten appeal points, capped at 100. Annual Carnival
is a separately announced April segment-demand event, not a permanent appeal bonus.

Occupancy and gaming rates are independently 0–20%, default 7%. The finite
city pools split into budget/leisure/luxury/business segments with overnight
weights45/30/15/10 and day weights55/25/5/15. Integer remainders follow canonical
segment and venue order. Per-rate-point occupancy discouragement is5/4/3/3%,
and gaming discouragement4/3/2/3%; factors clamp at zero. Overnight demand uses
both factors; day visitors use gaming only. Factors apply to each segment's
finite pool and its local capacity-derived desired attendance.

Each venue partitions its appeal-adjusted guest/day capacity by segment weights
and preferences. Budget visitors favor budget venues, luxury visitors premium
venues with safety/low congestion, leisure visitors varied districts, and business
visitors standard venues with rail/airport access. All cross-tier preferences are
positive. Segment venue requests share one finite segment pool, and their totals
jointly fit each venue's capacity; no segment gets another copy of its beds.
Shared gateway reservations subsequently constrain new admissions and external
day visits. No shared/global RNG draws are consumed.

On day 17 of each 25-day month, half the current guests depart, rounded upward.
Admissions move survivors toward the allocated target, capped at half the target
rounded upward. Day visitors refresh to target immediately. An even overnight
target approached from below can settle one guest short. The forecast preserves
current fields and labels separate target and projected attendance. Departing
and surviving guests retain their segment; only new admissions use target shares.
Integer remainder assignment can produce a different settled segment mix from
those target shares. Business forecasts run the same pure turnover/remainder rule
to project that mix under fixed current settings. A derived cache keys opening
mix, target mix, projected scalar count and arrival reservation. It retains at
most16,384entries and runs at most32steps per miss; zero overnight projections
do no work, and hits perform no turnover steps. When the existing scalar forecast
represents a restricted gateway's next surviving cohort rather than a distant
equilibrium, its matching actual step supplies the mix. A defensive unresolved
projection explicitly reports approximate target shares instead. Actual completed
business always uses the real opening/closing mix; no forecast admits visitors.

Power and water throughout the footprint, no fire, and road/station access
within three tiles are required. Reconciliation clears current invalid visitors;
service recovery waits for the next day 17. Completed business survives closure
or replacement. Reports explain the limiting reason.

## Business and money

For segment `s`, opening guests `O_s`, closing guests `C_s` and day visitors
`D_s`, the new `segments_20261015` profile computes cent numerators:

- Lodging: `sum((O_s+C_s)*50*lodging_tier*segment_spend)`.
- Gaming after payouts: `sum(((O_s+C_s)*25+D_s*50)*gaming_tier*segment_spend)`.

Both use denominator10,000. Budget/standard/premium lodging factors are
100/130/180 and gaming factors100/120/150; budget/leisure/luxury/business
spending factors are85/100/150/110. Tier membership and the profile's formulas
are code-owned, not mutable saved price tables. The unweighted base is $1 per
average guest-month lodging and $0.50 per visitor-month gaming. These are business
bases, not gross wagers or treasury credits. Mayor gambling stays in the separate
casino ledger and never changes these bases or visitors' odds.

Day18 books completed activity once at the current rates. Exact twelfth-cent
units plus subunit residue are obtained from
`(business_numerator*rate*12+opening_residue)/1000000`. Quotient enters existing
Budget carry; remainder0–999,999 is saved separately per tax and persists through
annual settlement. Display cents never feed accounting. Annual settlement
converts1,200twelfth-cents to a dollar and retains both layers of residue.
Historical rates and opening/closing residue are recorded with a defensive copy
of immutable per-segment half-guest/day activity. Validation recomputes the
business and exact transition, even while the next month's activity is pending.
A zero rate adds no new tax. Stores retain zero lodging tax and their ordinary
commercial property tax; resorts have no duplicate property assessment.

The old `cost_scaled_20261015` and `roster_20261014` business profiles retain
unweighted50/25/50-cent formulas, their completed amounts and their six/three
unit occupancy/gaming quantum checks. Only a valid segmented booking permits
the finer money profile; old schema validation is not globally relaxed.

Budget groups the two tourism rates, current/forecast attendance and occupancy,
physical beds, the last accepted guest/day support, current-month annualized city
tax estimate and one primary limiter. Details organizes actual accrued/completed
business, supported estimates, visitor mix, staff, access/services, reputation/events
and explicit Casino Safety Program costs. Static mechanics live in Help. There is
one ordinary outer vertical scroll and no separate tourism scroll region.

## Identity, restoration and city effects

A monotonically allocated facility instance distinguishes demolition/rebuild at
the same anchor. Occupancy never transfers to a replacement. The system retains
last completed per-instance activity even after that lot disappears, so earned
pending tax is neither lost nor replayed. Save validation rejects unsafe types,
counts, duplicate identities, impossible periods and inconsistent financial
state before replacing the active city. Stale attendance may be dropped.

Legacy resort residents migrate after final snapshot restoration into bounded
guests; day visitors start at zero. Ordinary resident cohorts, legacy facility
metadata, historical books/samples and earned unlocks remain intact. Repeated
load/save is idempotent. New headers expose population and tourists separately;
unresolved legacy headers say Legacy population and omit unknown tourists.
Historical population samples may include old resort occupants and are retained.

Tourism block/state schema 3 retains the cost-scaled schema-2 roster and adds
validated optional feature blocks with explicit neutral defaults. `features.markets`
tags accepted segmented activity. Current state stores four guest counts and four
day counts with exact respective sums; earlier unsegmented state deterministically
partitions its existing canonical totals without changing those totals. Schema 1 attendance
is first validated against the exact previous guest/day capacity profile, then
normalized to current capacities. Invalid counts or capacity assertions reject
before city replacement. The independent legacy `facility.capacity` remains
preserved metadata, never attendance authority. Schema 1 completed activity uses
the immutable `roster_20261014` profile, including demolished venues with no
surviving attendance. Normalized saves retain that activity profile until the
next completed month; all activity rows, pending business, booked tax, carry,
history, cohorts, unlocks, Mayor ledgers and earned settlement class survive.
Financial defensive bounds retain the previously valid maximum because old-year
carry can coexist with current-profile activity. No retrospective admissions or
business are generated, and repeated normalized saves are idempotent.

Current tourists supply existing resort pollution/crime loads, spread across the
footprint, without duplicate resident loads. Existing utility demand/capacities
remain in force. Desert Orbit's departure removes tourists, retains resident
population, and preserves its trigger, rubble and occupied-venue refund rules.

Hall crowds are bounded representatives of the selected venue's attendance,
never more than its existing model budget. Empty means no patrons. Cache refresh
handles equal-city-total redistribution and releases removed/replaced halls.

## Measured fixed-environment balance

These synthetic scenarios hold appeal100, economy100%, neighbors0 and the other
rate at7. Every independent rate0–20 runs24 settling months plus12 measured
months. The measured revenue oracle uses actual opening/closing segments and
literal tier/spending factors, independently of the production money helper.
Amounts below are exact annual tax equivalents before display rounding.

| Scenario | Guest beds | Residents | Best occupancy rate | Occupancy tax at best /20% | Best gaming rate | Gaming tax at best /20% |
|---|---:|---:|---:|---:|---:|---:|
| Founding, one Boddy's |80|0|12%|$36.504 /$12.24|14%|$25.83 /$20.70|
| One Despicable's |0|0|No lodging|$0 /$0|14%|$8.442 /$5.46|
| One of every resort |20,040|0|11%|$210.6522 /$120.552|14%|$151.1034 /$130.782|
| Same resorts, large city |20,040|200,000|13%|$20,557.5006 /$14,808.096|17%|$10,803.1719 /$10,418.016|
|100Boddy's, oversupply |8,000|0|14%|$93.576 /$72|17%|$81.192 /$72.54|
| All resorts, service collapse |0|0|None|$0 /$0|None|$0 /$0|

At7%/7%, founding Boddy's settles39guests+10day visitors and$49.56 combined
annual tax against its$8,000 cost, a161.42-year simple tax-only payback.
The200,000-resident all-resort case has11,200guests+336day visitors,
$23,261.4942/year and86.15years against$2,004,000. The zero-resident all-resort
case has128guests+61day visitors,$274.1634/year and7,309.51years. These ratios
omit infrastructure, upkeep, other revenue, changing demand and construction time.
They are fixed-environment measurements, not full-city profitability forecasts.

Integer rounding requires projecting the actual mix, not multiplying target
shares by projected attendance. For example,35target Boddy guests at90%appeal
and7%/7%rates have target shares19/11/2/3; actual turnover settles21/12/1/1.
Target-share lodging would incorrectly estimate3345c/month. The cached turnover
projection correctly returns3245c/month, equal to actual completed business.
Every one of the252 independent measured sweep rows now matches projected and
actual annual lodging/gaming numerators exactly. This verifies fixed-environment
projection; changing services, access, events or demand can still change future
receipts. Current attendance, accrued books and completed business remain the
authority for what actually happened.

## Work bounds

Venue discovery caches building/zone layer snapshots and canonical anchors.
Unchanged native layer equality avoids another discovery; forecast/report reads
do not run discovery at all. Reconciliation and monthly activity visit venues
and footprints, not individuals, and tourism has no per-frame census callback.
Forecast returns defensive copies and caches derived results by exact current inputs.
A changed input recomputes per-venue attraction/allocation; warm summary reads omit
venue rows. The pure rounded-mix projection has its own bounded cache. Allocation
counts remain bounded by venues.

Tests cover zero,100 and 16384 one-tile stores (the maximum geometric fit), plus
12288 served stores with every fourth row reserved for roads. The dense service
flags are a synthetic stress fixture; actual paid infrastructure/service behavior
is covered separately by host journeys. Timing/allocation observations are machine
measurements, not FPS guarantees. See `test_tourism_work_budget.gd` for stable
cache-miss, per-venue operation and activity-record assertions.

## Operating destinations and commercial support

`TourismDistricts` derives complete canonical footprints from building/zone
layers, including imported corner rotations and missing facility metadata.
Pocket/City Parks are outdoors; Museum/Monument culture; Zoo/Marina recreation;
Stadium/Neon Dome entertainment. Libraries retain their civic role. Every
attraction needs nearby road/station access and no fire anywhere on its lot.
Parks and monuments need dry usable ground; staffed attractions need power and
water throughout their footprint. Marina additionally needs adjacent open water.
None of these attractions has a separate existing funding requirement.

Within sixteen tiles of a venue's footprint, each operating category awards
4 points for its first attraction, 2 for its second and 1 for later copies,
limited to 5 per category and 20 overall. Distinct other operating resort
identities add 1 each, capped at 5; copies of the venue's own identity do not.
These are local appeal points within the existing 100% appeal ceiling, not an
addition to the finite regional visitor pool. Both lots must satisfy the existing
three-tile road/station entrance rule plus an exact transport route between the
footprints. All frontage entrances participate; a disconnected road island does
not connect attractions or shops.

Current operating attendance produces a finite business opportunity index:
20 cents per guest-month and 10 cents per day-visitor-month, weighted once by the segment spending factors85/100/150/110%, with one final cent floor per venue. It never enters
municipal cash, tax accrual or the Mayor's gaming ledger. Each source distributes
its available cents once among reachable ordinary commercial sites within twelve
tiles, ordered by canonical anchor, proportionally to remaining recipient limits.
A recipient accepts at most 1,000 cents across all venues. Ordinary Despicable's
shops are eligible; resort lots are excluded. Powered accessible vacant commercial
sites are eligible to develop, alongside standing shops. Local preference is one
growth point per 100 allocated cents, capped at 10 per site. This adds to the
existing commercial growth score only; agriculture and residential growth retain
their existing rules. Unallocated cents remain unallocated: available equals
allocated plus unallocated, even when no shops exist or local sites saturate.

The separate market-size nudge is one commercial demand point per 100 available
cents, capped at 100 citywide. It can encourage shops to develop before any are
present, without a fictional payment or duplicated visitor spending. Property tax
changes only if real businesses develop. Losing current attendance removes this
ongoing opportunity. Earlier monthly zone passes consume the last published
attendance; day 17 publishes new attendance for later consumers.

Discovery and service gating rebuild in simulation/edit reconciliation hooks
using native packed-layer comparisons, including raw edits and fire sets. Spatial
bins bound attraction, identity and commercial candidate lookups; attendance
identity/distribution invalidates influence even when the city total is unchanged.
`venue_inputs`, `commercial_bonus`, `commercial_demand_bonus`, Details and Inspect
read copied caches. They do not scan attractions, allocate spending, consume RNG,
book money or change persistence. Derived maps are rebuilt after restore and are
not serialized into the reserved schema-3 feature blocks. Per-resort snapshots
add categories, appeal/identity bonuses and available/allocated commercial cents;
Details separately explains market size, local preference and unallocated support.


## Accepted employment and resident commuting

Day 17 plans prospective work from finite market demand and gateway access,
then caps that demand with the same detached, joint component power/water
budgets used for visitor admission. It assigns the shared resident labor pool
and capped incoming allowance once after this feasibility pass. A resort with
ordinary building service but no visitor headroom retains only its two base
positions; Despicable's has no extra base positions. Infeasible variable work
cannot consume workers that could serve another venue. An empty resort can
start or recover because this plan uses prospective demand, not current guests.

Accepted `planned_guests` and `planned_day_visitors` describe utility-feasible
opportunities. `supported_capacity` and `supported_day_capacity` further apply
filled staffing to those opportunities. They are distinct from actual closing
visitors: ordinary turnover, bounded arrivals and resource evacuation determine
closing attendance in a second pure reservation pass. Both passes reuse one
pair of budgets; only the final atomic publication triggers at most one
established power and water reallocation. No weather, storage or RNG tick is
added. The ordinary `forecast()` remains a graph-free counterfactual market and
staffing quote; Budget's supported estimate retains its accepted-support policy.

Both replacing censuses and intervening deltas consume accepted positions once.
The resident transport pass also consumes these accepted opportunities through
`TourismSystem.job_tiles()`, verifying the current standing venue instance and
all usable footprint frontages. Resorts with no accepted jobs, closed venues,
demolished footprints and replacement instances cannot become permanent route
targets merely because they have an arcology building code. A reopened resort
waits for its next accepted plan. Existing ordinary workplaces and agricultural
parcel destinations retain their behavior. These destinations do not create
additional resident origins, tourists, incoming workers or fares; successful
resident trips feed the existing residential commute-growth factor.

The saved staffing shape and exact integer validation remain unchanged: positions
are derived from planned demand, filled totals stay within the shared pools,
and staff-supported capacity derives from filled positions. Utility rows still
validate actual closing attendance and exact rounded requests. Restore never
reconstructs completed money from current feasibility or renews migration grace.


## Connected arrival gateways

Regional overnight arrivals require a real route to a civilian gateway. Routing
shares resident mode/station/tunnel transitions, but its explicit target policy
never stops at an ordinary shop. All valid frontage entrances are considered.
Road/highway/rail borders contribute 500/1,500/2,000 monthly arrival seats per
side and kind; overlapping road/highway mouths use the stronger capacity while
accepting both valid modes. Each operating civilian airport adds 6,000 seats
only with an actual member frontage; each harbor adds 1,500 only with landside
access and navigable water from a real crane berth to the map edge. Military
ports, sealed water and a bounding rectangle without a real entrance do not
qualify. Discovery never spawns vehicles or draws random numbers.

Connected rail, airport and harbor types increase the finite regional pool by
25%, then another 15%, then another 10% (maximum 50%). Duplicate gateways of a
type add their real capacity but no further pool multiplier. The existing
regional road floor keeps a founding roadside casino viable. Resident day
visits require a connected residential neighborhood and use a separate finite
population-derived allocation; they cannot create overnight guests.

Canonical weighted reservations share each gateway's seats between venues and
between new overnight admissions and external day visits. Capacity limits new
arrivals, never guests already staying. Ordinary turnover continues after a
route is cut. Completed monthly access records in schema-3 `features.access`
retain unique venue instances, overnight admissions, local/external day counts
and gateway counts even after a road, port or venue disappears. Detached restore
validates exact totals, known completed identities, month, numeric bounds and
shared gateway capacities. Missing earlier-phase ledgers remain empty; graph,
route and influence caches are rebuilt from city data. Completed financial
business is never recalculated from today's route.

`TourismAccess.refresh` owns discovery and cached reachability. The graph has at
most six states per map tile; iterative strongly connected components share
work between all entrances. Reachability is capped at 32,768 component visits
per refresh, with at most eight active incremental searches, older pending
requests first, and a 1,048,576-entry completed cache. An unfinished search is
reported as pending and is retried; it is not a proof of disconnection. Layer
comparisons include raw surface, subway, tunnel, zone, service, terrain and
canonical temporary-water membership changes. Unchanged refreshes and ordinary
report/forecast reads reuse evidence. Explicit bounded path evidence is available
to the scheduled transport consumer.


## Accepted visitor journeys

The day-8 Transport pass consumes the previous completed accepted access
ledger. It never reserves forecast admissions again. Resident origins, their
160-origin sample, 32,000-state allowance and unreachable denominator stay
separate. Both consumers share the existing single traffic decay and map
publication. Traffic maps therefore include real visitor road journeys.

Tourist routing samples at most 1,024 origin cohorts with an independent
131,072 expanded-state allowance plus 131,072 path nodes per pass. Cohorts
partition actual accepted counts
within each canonical gateway (and a separate local-day group); their weights
sum exactly to that group's admitted source. A representative venue's current
explicit route carries its cohort weight. Station frontages are preferred when
they reach the target; valid road frontages remain a fallback. The same physical
road mouth or residential frontage can accept a bus alighting there. Each
completed transit mode contributes its actual weighted ridership through the
existing Budget fare conversion. Fares are claimed once; forecasts and reports
never create traffic, riders or money. Excursions remain optional and currently
zero, rather than creating additional visitors.

Samples allocate space among gateway groups in proportion to their eligible
origins, with at least one representative for each selected group. Saved gateway
and per-group representative cursors rotate selection. Unstarted cohorts after
the work/queue limit are explicitly **unsampled**, distinct from **pending**
search work. At most 32 started accepted jobs remain pending, serviced oldest
first before new work. Intake shrinks when that queue fills; queued jobs are
never silently removed. A pending job retains its original accepted period,
instance, footprint identity, gateway and conserved source weight. Demolition,
closure or loss of a current route may cancel/fail its live journey without
rewriting completed tourism business. A single route's full graph is bounded
by 98,304 states, below the per-pass allowance, so the oldest job can always
make progress even after derived caches are rebuilt.

Reverse route frontiers share work within a pass. At most eight trees retain
frontiers and their reserved total state space cannot exceed 262,144 entries.
These caches clear at every scheduled pass and every raw network edit; neither
frontiers nor graph maps are serialized. Pass-local sharing makes uninterrupted and locally restored continuations
perform identical bounded work from the same source state. Schema-3 `features.access.transport` owns the
saved processing/period/fare guards, bounded queue and cursor state. Fare claims
are established by completed period evidence, not a free-standing pending
number: the latest twelve period records retain completed trips, transit mode
usage and claimed usage; older unpaid records compact into one ordered month
range with exact totals. Pending fares equal earned transit usage minus claims.
The latest evidence must match the processed report, and an unprocessed state
cannot contain earned fares. Claimed older records are pruned without resetting
unpaid trips. Detached validation checks exact types/ranges, source conservation,
identities, periods, nonoverlapping fare ranges, claim equations, queue ordering
and report totals before installation. Historical queued
instances may legitimately be absent from current attendance.

Budget's Transportation condition retains detailed visitor work and modes;
compact Tourism Details shows completed and deferred weighted trips. Statistics includes actual visitor transit use while
resident commute failures remain exclusively residential. These are aggregate
weighted journeys, not an extra attendance census or an individual traveler
simulation. The work limits bound searches and retained state; they do not
guarantee smooth frame times in maximum-size cities.

## Completed visitor experience and destination reputation

New and migrated destinations start at 60 out of 100. Only an accepted monthly
visitor transaction advances reputation. Opening reputation controls the current
month's finite guest and day-visitor demand pools; completed experience first
changes a following month's factor. The factor is
`clamp(100 + (reputation - 60) / 2, 75, 120)` percent. Reads, pause, reports,
forecasting and restoration cannot earn experience or advance its period.

Experience uses fulfilled needs, independent of prices or spending yields. The
named `TourismParams.EXPERIENCE_*` vectors sum 100:

| Segment | Safety | Access | Attractions | Staffing | Services |
| --- | ---: | ---: | ---: | ---: | ---: |
| Budget | 30 | 25 | 10 | 15 | 20 |
| Leisure | 20 | 20 | 30 | 10 | 20 |
| Luxury | 20 | 15 | 25 | 20 | 20 |
| Business | 20 | 30 | 10 | 20 | 20 |

Published local crime and city congestion reduce safety and access fulfillment;
access must be connected. Cached connected attraction bonus contributes up to 20
points, mapped to full attraction fulfillment. Filled staff are compared with
requirements for actual opening/closing guests and accepted day attendance,
rather than hypothetical positions. Services measure retention of natural
survivors after forced resource departures. Natural departures and unadmitted
future demand are excluded from that reliability calculation.

The named essential-service ceiling caps a venue's weighted score at the share
of natural survivors actually served. With 100 opening guests, 50 natural
departures and 30 forced resource departures, only 20 of 50 survivors retain
service: experience is at most 40. This takes neutral reputation 60 to 55; a
previous 90 falls to 82 under the monthly cap. Safe, accessible budget stays with
adequate staff/service and no attractions can score 90 for budget visitors.
Luxury prices alone award no experience.

Accepted guest segments contribute opening plus closing guest counts; accepted
day segments contribute twice their counts. These are **experience weights**,
not unique people or added residents. Each venue/segment score is weighted by
that actual exposure. Arrivals, staff and transport journeys never add to it.
Completed experience stays historical after a later closure, just like completed
business; live effects and attendance clear. Closure before acceptance with no
accepted visitor activity yields no experience. This is a monthly snapshot
model, not a daily incident journal.

Reputation moves one quarter toward completed experience, capped at +3 or −8
points per month. Milli-point state retains signed quarter-division remainder;
progress beyond a cap is discarded. Three empty accepted months leave the score
unchanged. Later empty months move at most one point toward neutral 60, without
crossing it; they never invent a good experience score.

The optional schema 3 `features.reputation` block stores the fixed-point score,
opening score/remainders, accepted period, activation period, empty counters,
completed experience and conserved exposure weight. Missing earlier blocks and
the exact old neutral placeholder initialize 60 without repricing or replaying
completed business, taxes, calendar events or migration grace. Detached native
validation checks bounded integral fields, periods, exposure against
completed activity, and exact transition consistency before installation.

Budget Details and Inspect share authoritative current/following-factor and
completed-experience reporting. The monthly graph stores milli-points and
presents 0–100 scores. Residents receive tourism's existing jobs, nearby commercial
support, real traffic/fares, crime and local nightlife consequences through their
ordinary systems. There is no additional global tourism happiness penalty,
resident population increment, vote, or direct retail/gaming cash credit.


## Supported estimates and derived read caches

The simulation's `forecast()` remains conditional demand and staffing potential.
`TourismSystem.supported_forecast()` is the separate Budget estimate: when a venue
was utility-limited, its projected counts cannot exceed current accepted counts
or lower new demand. Capped counts use a deterministic share of the actual current
segment mix. A fresh, empty, closed or reopened venue with zero accepted visitor support
has zero supported estimate until the next monthly admission. Physical beds remain
visible while it awaits that plan. New network headroom
is deliberately not promised by a report; its benefit appears after acceptance.
Actual completed opening/closing business and accrued taxes remain untouched.
Annual estimates multiply the current month's pace by twelve, holding its season,
event and opening reputation fixed; they are not a twelve-season prediction.

Forecast results are derived, defensive copies. Publication/restore, state revision,
rates, clock month, labor and other jobs, resident/neighbor demand, environment
averages, ordinances, reputation/calendar, access version, raw building/zone/service
and local land-value/crime/pollution layers and fires invalidate their inputs.
Summary reads omit per-venue rows; collapsed Budget Details avoids constructing
those reports. Neither cache advances graphs, admissions, events, money or RNG.
The segment projection cache uses a bounded FIFO ring, including saturated misses.
Calendar reads without a City Hall do not scan all venues for business gateways.
