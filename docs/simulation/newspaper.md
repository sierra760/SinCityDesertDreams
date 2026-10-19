# Newspaper and advisors

## Purpose

The newspaper turns the happenings the other systems report into a monthly
issue of *The Desert Dispatch*, with a lead story, a few smaller stories and
human-interest fillers. Big news breaks as an extra edition the same day. The
same system answers the advisor panel: a short, prioritized list of what the
city is short of, written in the advisors' voice.

## Inputs

- `CityEvents.news`: entries `{kind, args, priority}` queued by the other
  systems during the day. The simulation clears that list after every day,
  so the newspaper copies new entries into its own pending queue during its
  `daily` call and again on its scheduled day.
- `City.name`, `City.mayor`, the clock's year and month.
- `CityStats`: `power_capacity`, `power_demand`, `water_capacity`,
  `water_demand`, `unemployment`, `average_pollution`, `average_traffic`,
  `average_crime`, `tax_residential`, `tax_commercial`, `tax_industrial`,
  `approval`, `active_fires`.
- Current building, zone, service flags and underground layers, scanned once
  by `advisor_city_snapshot.gd`; current coverage is projected onto temporary
  grids using the actual service stamp rules.
- Read-only transport, population, utility, budget, port and accepted tourism
  observations when their systems are present.
- Written historical content: `NewsStories`, `AdvisorLines`. The sidebar uses
  evidence-specific text in the advisor assessment modules.

## Outputs

- `CityStats.newspaper_archive`: the issues, oldest first, at most
  `ARCHIVE_ISSUES`.
- `ctx.events.notify(&"newspaper", issue)` for every monthly issue and every
  extra edition.
- Getters: `latest_issue()`, `archive()`, `pending()`, `advice()`.

An issue is a JSON-safe Dictionary:

```
{
  "title": "The Desert Dispatch",
  "date": "March 1952", "year": 1952, "month": 3, "day": 22,
  "extra": false,
  "stories": [ {"kind": "zone_boom", "headline": "...", "body": "...",
                "priority": 360, "filler": false}, ... ]
}
```

`stories[0]` is the lead. Fillers carry `"filler": true` and an empty kind.

## Timing

- `daily`: copy new reports into the pending queue. If any of them is an
  `EXTRA_PRIORITY` story, publish an extra edition at once.
- `monthly`, day 22: copy anything reported since the daily call, publish the
  monthly issue, decay the pending queue.
- `networks_changed`: copy new reports (construction can report too).
- `yearly`: nothing.

## Rules

1. Every report becomes a pending story `{kind, args, priority, born_day}`.
   Its priority is the story template's `priority` from `NewsStories`, raised
   to a floor set by the report's own importance argument (0–3): importance
   2 guarantees at least `PRIORITY_MAJOR`, importance 3 at least
   `PRIORITY_URGENT`; 0 and 1 leave the template's value. Kinds listed in
   `NewsStories.ALIASES` use the template they alias; unknown kinds use the
   generic template and `PRIORITY_MINOR`.
2. The pending queue holds at most `QUEUE_SIZE` stories, kept sorted by
   priority, highest first; ties keep the older story first. When the queue
   is full, a new story replaces the lowest-priority story only if it has a
   higher priority; otherwise it is discarded.
3. A report identical to a pending story (same kind, same place and count)
   refreshes that story's priority instead of adding a second copy.
4. Publishing an issue takes the `LEAD_COUNT` highest stories as lead and
   secondary stories, formats each through `NewsStories`, then adds fillers
   until the issue has `ISSUE_STORIES` stories. Published stories leave the
   queue. When nothing is pending, the lead is a `quiet_month` story.
5. After every monthly issue each remaining pending story loses its
   template's `decay`. Stories at zero or below are dropped. So a minor story
   lasts a few months and a disaster is either printed the month it happens
   or forgotten.
6. An extra edition is published from `daily` when a newly absorbed story has
   priority at or above `EXTRA_PRIORITY`. It uses the same layout, flagged
   `extra: true`, and consumes the stories it prints. At most one extra per
   day.
7. Placeholders in story text are `{city}`, `{mayor}`, `{year}`, `{count}`,
   `{place}` and `{kind}`. `count` comes from the first present of the
   report's `count`, `amount`, `population`, `value`, `unpowered`,
   `unwatered`, `tiles`, `births`, `approval`, `residents`, `age_years`,
   `level`, `average`, `funds` or `cost` argument, or "several". Numbers in
   `amount`, `funds` and `cost` print as money (`$1,234`, or `-$1,234` when
   negative); other numbers print with thousands separators, and text prints
   as written. `place` comes from a `place` string, from `x`/`y` integers, or
   from an `at`/`center`/`tile`/`anchor` position (a `Vector2i`, an `[x, y]`
   array or an `"x,y"` string) turned into a district name by thirds of the
   map (`place_name`). A `name` string is the place only when none of those
   locate the report. Otherwise the city-wide kinds (`zone_boom`,
   `crime_wave`, `pollution_alert`, `traffic_jam`, `abandonment_wave`) happen
   in the city itself, printed as its name, and every other kind (or a city
   with a blank name) happens at "the edge of town".
   `kind` is the advisor title for a `need` argument, else the first present
   of `kind`, `name`, `key`, `family`, `technology` or `category` as a
   readable label (underscores to spaces, words capitalized; a `name` string
   is used as written, a `key` prints its gift's building name or "Military
   Base", a numeric port `kind` prints the zone's name and disaster kinds use
   their display names), else the story kind's label.
8. `disaster_started` reports pick the template for their disaster kind
   (`disaster_fire`, `disaster_flood`, ...) when one exists, otherwise the
   generic `disaster_started` template. `military_base` reports pick
   `military_base_accepted` or `military_base_declined` by their `accepted`
   argument.
9. The archive keeps the newest `ARCHIVE_ISSUES` issues.
10. Fillers are chosen at random from `NewsStories.FILLERS` without repeating
    inside one issue.
11. `advice()` delegates to a fresh read-only assessment and returns records
    with `{kind, title, text, urgent, reason, priority}`. It does not consult
    the disaster system's saved monthly needs list. That list continues to
    generate historical `advisor_need` news under its existing rules.

### Current advisor diagnoses

- Power/water distinguish capacity shortfall, low reserve and local service
  failure despite aggregate spare capacity. The last allocation can reveal
  shortage on a separate network; city-wide surplus does not disprove it.
  Matching allocator reports supply usable capacity, including power
  conservation’s component-local rounding, instead of raw generation.
- Police/fire coverage uses current station positions, footprint power and
  funding through `ServicesSystem.projected_coverage()`, without publishing
  new coverage maps. Prisons are effectiveness modifiers, never stations.
  Active fires and disasters lead; a fire does not prove a station shortage.
- Schools compare funded, anchor-powered capacity with the expected largest
  relevant monthly aging cohort. The same capacity serves each cohort
  separately. Hospitals distinguish missing facilities, power/funding loss
  and poor measured health. Funded care includes the actual Free Clinics
  contribution; insufficient capacity is distinguished from poor health despite
  sufficient care. Available water-treatment readings supply a
  separate health action when treatment has been invented.
- Transport uses actual attempts/completions and measured congestion. No
  resident-to-transit-building quota remains in the sidebar. Job advice uses
  the authoritative job total plus neighbor commuting, without adding farm,
  port or visitor jobs a second time. Aggregate sufficiency does not establish
  household access or rule out abandonment.
- Tax advice identifies affected existing RCI, agricultural and visitor
  sectors. RCI uses felt rates and weak measured demand; nonexistent sectors
  do not create a warning. Treasury trouble qualifies any tax-cut suggestion.
- `BudgetSystem.advisor_outlook()` derives a read-only annual pace from the
  shared scan, current service/transport/debt costs, published agricultural
  jobs and the latest completed visitor booking. It does not call the Budget
  window's tourism forecast, reconcile agriculture/wear or claim fares. It is
  explicitly an outlook at current settings and recent business, not the
  window's seasonal/event forecast or a promise of year-end cash.
- Approval quotes the last actual poll and its recorded leading complaint,
  never an invented current grievance. Pollution advice names the measured
  index and implemented remedies without inventing its source or a trend.
- Development opportunities use the actual residential recreation,
  commercial market/station and industrial station/crane limits. Large parks,
  zoos, stadia and marinas raise the residential cap; small parks do not.
  Existing port zones are reviewed before expansion. The read-only port
  accessor revisits current pieces/power inside already-discovered zones;
  unknown topology is not claimed to be operational. No inland-water or dry
  map is assumed to have navigable shipping access.
- Tourism uses accepted staffing and utility plans only. Low occupancy alone
  is not evidence for another resort, airport or a tax cut.

### Priority, timing and reading cost

Emergencies precede loss of essential supply, serious civic/financial problems,
ordinary warnings and growth opportunities; stable kind ordering breaks ties.
Only active emergencies and essential utility service loss are red. Each kind
appears once; explanatory references between departments avoid prescribing
another round of the same construction.

Every panel refresh rechecks current construction, power and funding. Traffic,
employment, health, supply and poll readings retain their simulation sampling
schedule and are identified as measurements. The sidebar remains current when
browsing an old issue; its caption explicitly separates it from the archive.
Empty states distinguish no city, no residents, early readings and a measured
city without detected warnings.

Assessment performs one full map scan plus bounded station stamping, developed
site checks and already-discovered port-member inspection. It never advances
simulation, samples RNG, allocates utilities, searches a route, forecasts
visitors, changes system caches or writes city/events/save state. There is no
new daily job or saved advisor state. The historical content templates and
monthly disaster needs remain unchanged.

Policy parameters live in `data/advisor_params.gd`: 2% reserve; weak station
coverage below 32/255 on at least 20% of developed sites; route failures at
20% of attempted trips; poor health below 50 years; high sector rates at 12%;
growth opportunities at 90% of the relevant cap. These tune advice, not
simulation balance. Coverage 32 is below the fully funded outer ring (50),
so ordinary peripheral service does not automatically demand another station.

## Historical newspaper parameters

| Name | Value | Tunes |
|---|---|---|
| `TITLE` | "The Desert Dispatch" | Masthead |
| `QUEUE_SIZE` | 9 | Pending stories kept |
| `LEAD_COUNT` | 3 | Reported stories printed per issue |
| `ISSUE_STORIES` | 6 | Total stories per issue including fillers |
| `ARCHIVE_ISSUES` | 60 | Issues kept in the archive (five years) |
| `EXTRA_PRIORITY` | 1000 | Priority that breaks an extra edition |
| `PRIORITY_MINOR` / `NOTABLE` / `MAJOR` / `URGENT` | 200 / 360 / 500 / 1000 | Story importance classes |
| `DECAY_SLOW` / `DECAY_FAST` / `DECAY_ONCE` | 50 / 250 / 1000 | Monthly priority loss classes |
| `SHORTAGE_MARGIN` | 2 | Percent of unused capacity below which a shortage is advised |
| `UNEMPLOYMENT_WARNING` | 10 | Percent |
| `POLLUTION_WARNING` | 100 | Average pollution index |
| `TRAFFIC_WARNING` | 100 | Average traffic index |
| `CRIME_WARNING` | 100 | Average crime index |
| `TAX_WARNING` | 12 | Tax rate percent |
| `APPROVAL_WARNING` | 40 | Approval percent |

## Save state

`save()` returns `{"queue": [ {kind, args, priority, born_day, seq} ],
"seq": int, "extra_day": int}`. Args are stored with string keys and
JSON-safe values (positions as `"x,y"`, names as strings). `load()` turns
whole-number arguments, which JSON reads back as floats, into ints again, so a
story printed after a load reads like one printed before it. The archive is part
of `CityStats`, so the latest issue is recovered from it after a load.
`load()` restores the queue and counters and tolerates missing fields.
