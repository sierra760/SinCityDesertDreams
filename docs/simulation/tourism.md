# Tourism and visitor taxes

`TourismSystem` owns current attendance, completed monthly visitor business and
pure forecasts. `TourismState` owns one record per canonical standing venue
instance. `TourismDemand` supplies deterministic allocation and turnover;
`TourismParams` names the constants. Budget owns all tax accrual and settlement.

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
final integer division. Tourist Advertising adds ten appeal points and Annual
Carnival five, capped at 100.

Occupancy and gaming rates are independently 0–20%, default 7%. Their demand
factors are `max(0,100-4*occupancy_rate)` and `max(0,100-3*gaming_rate)` percent.
Overnight demand uses both; day visitors use gaming only. Factors apply to both
the city pool and local capacity-derived desired counts. Desired attendance is
proportionally reduced to the finite pool, with integer remainder assignment in
canonical anchor order. No shared/global RNG draws are consumed.

On day 17 of each 25-day month, half the current guests depart, rounded upward.
Admissions move survivors toward the allocated target, capped at half the target
rounded upward. Day visitors refresh to target immediately. An even overnight
target approached from below can settle one guest short. The forecast preserves
current fields and labels its separate target and settled projection.

Power and water throughout the footprint, no fire, and road/station access
within three tiles are required. Reconciliation clears current invalid visitors;
service recovery waits for the next day 17. Completed business survives closure
or replacement. Reports explain the limiting reason.

## Business and money

For opening guests `O`, closing guests `C`, and current day visitors `D`, lodging
is `(O+C)*50` cents; gaming after payouts is `(O+C)*25 + D*50` cents. Thus lodging
earns $1 per average guest-month and gaming $0.50 per visitor-month. These are
business bases, not gross wagers or treasury credits. Mayor gambling stays in
the separate casino ledger and never changes these bases or visitors' odds.

Day 18 books the completed month once into `taxes_occupancy` and `taxes_gaming`
at the current rates. Exact accumulator units are `base_cents*rate*12/100`;
bases are divisible by25. Annual settlement converts twelfths of cents to dollars
and retains residues. Zero rate yields zero applicable tax. A store always has
zero lodging tax and keeps its ordinary commercial property tax. Resorts have
no duplicate residential or commercial property assessment.

Budget groups the two tourism rates with current and settled forecast attendance,
operating/total guest beds, and estimated annual **city tax income** from Budget's
existing estimated ledger. Business taxable bases are not city receipts. A
collapsed, keyboard/touch-accessible Details control exposes accrued taxes,
completed monthly bases, allocation targets and the demand explanation. It keeps
its state through refresh, and reads/disclosure never advance simulation.
The Books section retains year-to-date, previous-year and twelve-month estimates.
A rate change affects future bookings, never already-booked money. Forecast,
report, setup, hall entry and pause do not admit guests or book tax. Statistics
samples current tourists/occupancy and latest booked monthly tax dollars on day22.

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

Tourism block/state schema 2 writes the cost-scaled roster. Schema 1 attendance
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
rate at7. Every independent rate 0–20 runs24 settling months plus12 measured
months. Amounts below are exact annual tax equivalents before display rounding.
Coefficients remain occupancy4/gaming3; these examples do not establish a
universal optimum under changing services, appeal, population or ordinances.

| Scenario | Operating guest beds | Residents | Occupancy tax at 12% /20% | Best tested intermediate gaming rate | Gaming tax at that rate /20% |
|---|---:|---:|---:|---:|---:|
| Founding, one Boddy's | 80 | 0 | $44.64 /$26.40 | 16% | $35.52 /$34.80 |
| One Despicable's | 0 | 0 | $0 /$0 | 18% | $11.88 /$10.80 |
| One of every resort tier | 20,040 | 0 | $141.12 /$86.40 | 17% | $126.48 /$118.80 |
| Same tiers, large city | 20,040 | 200,000 | $11,831.04 /$7,574.40 | 17% | $7,429.68 /$7,135.20 |
| 100 Boddy's, oversupply | 8,000 | 0 | $144.00 /$93.60 | 16% | $130.56 /$126.00 |
| All tiers, service collapse | 0 | 0 | $0 /$0 | No receipts | $0 /$0 |

Whole-person integer rounding changes the best intermediate point for small
venues. At Boddy's, gaming 17% earns $34.68, slightly below gaming 20%'s$34.80;
gaming 16% earns $35.52. The sweep checks every rate 0–20 and requires some positive
intermediate to outperform 20%; it does not impose a universal 17% optimum.
Demand, turnover, money coefficients and settlement timing remain unchanged.

At 7%/7%, founding Boddy's settles 45 guests +12 day visitors and $61.74 combined
annual visitor taxes against its $8,000 construction cost: 129.58 years simple
tax-only payback. The 200,000-resident all-tier case yields 11,386 guests +372 day
visitors, $14,502.60/year and 138.18 years against $2,004,000 construction cost.
All tiers in a zero-resident city instead yield 137 guests +65 day visitors,
$199.92/year and 10,024.01 years. These ratios omit infrastructure, upkeep, other
revenue, demand changes and construction time. Despicable's grows from zoning,
so a zero direct building price is not a meaningful municipal payback estimate.

## Work bounds

Venue discovery caches building/zone layer snapshots and canonical anchors.
Unchanged native layer equality avoids another discovery; forecast/report reads
do not run discovery at all. Reconciliation and monthly activity visit venues
and footprints, not individuals, and tourism has no per-frame census callback.
Forecast returns defensive copies and recomputes per-venue attraction/allocation;
it is not a memoized result. Model/allocation counts remain bounded by venues.

Tests cover zero,100 and 16384 one-tile stores (the maximum geometric fit), plus
12288 served stores with every fourth row reserved for roads. The dense service
flags are a synthetic stress fixture; actual paid infrastructure/service behavior
is covered separately by host journeys. Timing/allocation observations are machine
measurements, not FPS guarantees. See `test_tourism_work_budget.gd` for stable
cache-miss, per-venue operation and activity-record assertions.
