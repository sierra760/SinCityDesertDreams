# Population

## Purpose

The population system counts who lives and works in the city, ages them,
lets them be born and die, and tracks how educated and how healthy they are.
It publishes the headline numbers the rest of the game reacts to: the
population total, the education quotient, life expectancy, the employment
picture, the settlement class (village through megalopolis) and, once a
year, the mayor's approval rating.

Residents are not simulated one by one. The city keeps twenty five-year age
cohorts (ages 0–4, 5–9, … 95–99). Every cohort carries a head count, a pooled
education score and a pooled health score. The pooled scores are sums over the
people in the cohort, so the average education or health of a cohort is the
pool divided by the head count. Headline education and health are the averages
over the working-age cohorts (ages 20–54).

## Inputs

Read on the scheduled day:

- `City.building` and `City.zone` layers: every developed residential lot
  supplies homes, every developed commercial or industrial lot supplies jobs,
  every abandoned lot counts as lost jobs. Capacity per lot comes from the
  zone system's `population_of(id)` when it is present, otherwise from the
  footprint rule in `PopulationParams`.
- `City.flags`: a civic building only serves when its anchor tile is powered.
- `City.status`: the current settlement class.
- `CityStats.arcology_population`: written by the reward system; added to the
  published total but not aged (arcology residents keep their own records).
- `CityStats.funding[&"schools"]`, `[&"colleges"]`, `[&"health"]`: funding
  scales the service capacity of schools, colleges and hospitals.
- `CityStats.ordinances`: `&"pro_reading_campaign"`, `&"free_clinics"`,
  `&"anti_drug_campaign"`, `&"public_smoking_ban"` (the ordinance catalog keys).
- `CityStats.average_pollution`: dirty air shortens lives.
- For the March vote: `CityStats.tax_residential`, `average_traffic`,
  `average_pollution`, `average_crime`, `average_land_value`, `unemployment`,
  `education_quotient`, `life_expectancy`.

## Outputs

- `CityStats.population`: ordinary residents (sum of the cohorts).
- `CityStats.cohorts`: the twenty head counts, youngest first.
- `CityStats.jobs`: commercial plus industrial job units.
- `CityStats.employment_rate`, `CityStats.unemployment`: percent.
- `CityStats.education_quotient`: 0–150.
- `CityStats.life_expectancy`: years, 0–90.
- `CityStats.health_index`: percent of residents a funded hospital can serve,
  0–100.
- `CityStats.approval`: percent, refreshed by the March vote.
- `City.status`: raised when the total population passes a threshold.
- Events:
  - `&"status_upgrade"` `{status, name, population}` when the settlement
    class rises.
  - `&"approval_vote"` `{approval, complaint, complaint_name, previous}` after
    each March vote.
  - `&"birth_record"` `{births}` in a month with a record number of births
    (only when at least `NEWS_BIRTHS_MIN` babies were born).
  - Notice `&"approval_milestone"` `{approval}` the first March the rating
    climbs from below `APPROVAL_MILESTONE` to at or above it.

Getters for other systems and the UI:

- `residents() -> int`, `industrial_units() -> int`,
  `commercial_units() -> int`, `abandoned_units() -> int`.
- `cohort_education(i) -> int`, `cohort_health(i) -> int`: average scores of
  one cohort.
- `complaints() -> Array[Dictionary]`: the last vote's complaint ranking,
  `{key, name, votes}` sorted by votes descending.
- `status_name(status) -> String`.

## Timing

- `monthly`, day 14: census, demographics, employment, settlement class, and
  in March the approval vote.
- `daily`, `yearly`, `networks_changed`: nothing.

## Rules

Numbers in capitals are parameters listed below.

### 1. Census

1. Walk the map once. A lot is counted once, at the tile carrying its
   north-west corner flag; a civic building's power is read at its anchor
   (`City.anchor_of`), which in a city saved at another rotation is a
   different corner of the lot.
2. A residential lot adds its capacity to `residents`. Commercial and
   industrial lots add theirs to `commercial_units` and `industrial_units`.
   Abandoned lots add their former capacity, divided by `CENSUS_UNIT`, to
   `abandoned_units`.
3. Capacity is the zone system's `population_of(id)` when a zone system is
   registered. Otherwise a 1×1 lot holds `LOT_CAPACITY[1]`, a 2×2 lot holds
   `LOT_CAPACITY[2]` (the later half of the 2×2 roster, the taller buildings,
   holds `LOT_CAPACITY_TALL_2X2`), and a 3×3 lot holds `LOT_CAPACITY[3]`.
   Abandoned lots use the same footprint rule.
4. Civic buildings are counted when their anchor tile is powered: schools,
   colleges, hospitals, libraries, museums.
5. `jobs = commercial_units + industrial_units`.

### 2. Service capacity

1. `school_places = schools × SCHOOL_PLACES × funding(schools) / 100`.
2. `college_places = colleges × COLLEGE_PLACES × funding(colleges) / 100`.
3. `hospital_places = hospitals × HOSPITAL_PLACES × funding(health) / 100`;
   `&"free_clinics"` adds `residents / FREE_CLINIC_DIVISOR`.
4. `culture_places = libraries × LIBRARY_PLACES + museums × MUSEUM_PLACES`.
5. `newborn_health = NEWBORN_HEALTH_SERVED + HEALTH_ORDINANCE_BONUS` for each
   of `&"anti_drug_campaign"` and `&"public_smoking_ban"` enabled.
6. `pollution_penalty = min(POLLUTION_PENALTY_MAX, average_pollution /
   POLLUTION_PENALTY_DIVISOR)`.
7. `health_index = min(100, hospital_places × 100 / max(residents, 1))`.

### 3. Deaths

For every cohort older than the first, with head count `n > 0` and average
health `h` (the pooled health divided by `n`), against the cohort's age
`age = index × 5`:

1. If `h ≥ age` nobody in the cohort dies this month.
2. Otherwise the shortfall fraction is `1 − h / age`, and the expected deaths
   are `n × shortfall / MORTALITY_MONTHS`. The fractional remainder is settled
   with one random draw, so small cohorts still lose people over time.
3. Hospital coverage (`health_index` percent) removes up to
   `HOSPITAL_MORTALITY_RELIEF` percent of those deaths.
4. The dead take their share of the cohort's education and health pools with
   them. Every death frees a home, so deaths add to this month's immigration.

### 4. Aging

Cohorts age from oldest to youngest so a person moves at most once a month.
One sixtieth of each cohort (a fifth of the cohort per year) moves up to the
next cohort, with the remainder settled by a random draw. The movers carry
their share of the education and health pools, then:

1. Movers entering the school-age cohorts (`SCHOOL_COHORT_MAX` and below)
   gain `SCHOOL_EQ_GAIN` education each, for as many movers as
   `school_places` covers.
2. Movers entering the college cohorts (`COLLEGE_COHORT_MIN` to
   `COLLEGE_COHORT_MAX`) covered by `college_places` add half of their own
   average education again.
3. Movers entering adult cohorts covered by `culture_places` gain
   `CULTURE_EQ_GAIN` each.
4. Unless `&"pro_reading_campaign"` is enabled, every mover forgets `EQ_DECAY` points.
5. Every mover loses `pollution_penalty` health.

### 5. Births

1. Parents are the cohorts from `PARENT_COHORT_MIN` to `PARENT_COHORT_MAX`
   (ages 20–44). Births per month are `parents / BIRTH_DIVISOR`, with the
   remainder settled by one random draw that pollution makes less likely.
2. Newborns served by `hospital_places` start with `newborn_health`; the rest
   start with `NEWBORN_HEALTH_UNSERVED`.
3. Newborns start with `education_quotient / NEWBORN_EQ_DIVISOR` education.
4. Every birth fills a home, so births add to this month's emigration.

### 6. Migration

1. With `previous` the cohort total before this month's deaths and births:
   `incoming = max(0, residents − previous) + deaths`;
   `outgoing = max(0, previous − residents) + births`.
2. If `incoming > outgoing`, the difference immigrates. Immigrants are dealt
   out in `IMMIGRATION_ORDER` (young adults first, then children, then the
   whole working range) in slices of one sixteenth plus one. An immigrant
   entering cohort `i` brings `IMMIGRANT_HEALTH_BASE − i` health and
   `IMMIGRANT_EQ_CHILD_BASE + IMMIGRANT_EQ_CHILD_STEP × i` education when
   `i < 3`, otherwise `IMMIGRANT_EQ_ADULT_BASE − i`.
3. If `outgoing > incoming`, the difference emigrates, taken from every cohort
   in proportion to its size, repeating until the count is met.
4. After migration the cohorts sum to `residents` exactly.
5. When `residents` is zero the cohorts and pools are cleared and the headline
   scores keep their last values.

### 7. Headline scores

1. `working = sum of cohorts WORK_COHORT_MIN..WORK_COHORT_MAX` (ages 20–54).
2. `education_quotient = clamp(pooled education of those cohorts / working
   + culture_bonus, 0, EQ_MAX)` where `culture_bonus = CULTURE_EQ_BONUS ×
   min(1, culture_places / residents)`.
3. `life_expectancy = clamp(pooled health of those cohorts / working
   + hospital_bonus + ordinance_bonus − pollution_penalty, 0, LE_MAX)` where
   `hospital_bonus = HOSPITAL_LE_BONUS × health_index / 100` and
   `ordinance_bonus = LE_ORDINANCE_BONUS` for each of `&"free_clinics"`,
   `&"anti_drug_campaign"`, `&"public_smoking_ban"`.
4. With no working-age residents the headline scores keep their previous
   values.

### 8. Employment

1. `unemployment = abandoned_units × 100 / (residents / CENSUS_UNIT +
   abandoned_units + 1)`, clamped to 0–100. Abandoned lots are the visible
   sign of lost jobs; a city without abandonment reports full employment.
2. `employment_rate = 100 − unemployment`.

### 9. Settlement class

1. `total = residents + arcology_population`.
2. While `City.status` is below the last class and `total >
   STATUS_THRESHOLDS[status + 1]`, the status rises by one step per month and
   `&"status_upgrade"` is reported. The class never falls.

### 10. Approval vote (March only)

1. Skip the vote, keeping the previous approval, when `residents <
   VOTE_MIN_POPULATION`.
2. Complaint weights, in order: traffic (`average_traffic`), pollution
   (`average_pollution`), crime (`average_crime`), taxes
   (`tax_residential × VOTE_TAX_WEIGHT`), unemployment (`unemployment`),
   education (`100 − education_quotient` when at or below 100, else 0),
   health (`VOTE_HEALTH_TARGET − life_expectancy` when at or below it, else 0).
3. Contentment weight: `average_land_value + VOTE_CONTENT_BASE`.
4. Each of `VOTE_COUNT` voters draws a random number below the total weight
   and walks the complaint list; a draw past every complaint is a vote of
   approval. `approval` is the number of approving voters.
5. Complaints are ranked by votes for the UI. `&"approval_vote"` is reported
   with the leading complaint. A rating that climbs from below
   `APPROVAL_MILESTONE` to at or above it raises the `&"approval_milestone"`
   notice.

## Parameters

| Name | Value | Tunes |
|---|---|---|
| `LOT_CAPACITY` | 1×1: 10, 2×2: 80, 3×3: 360 | residents or jobs per lot by footprint (fallback rule) |
| `LOT_CAPACITY_TALL_2X2` | 120 | the taller half of the 2×2 roster |
| `CENSUS_UNIT` | 10 | residents per census unit used by the unemployment ratio |
| `SCHOOL_PLACES` | 15 | pupils one funded school educates per aging step |
| `COLLEGE_PLACES` | 50 | students one funded college serves |
| `HOSPITAL_PLACES` | 25 | patients one funded hospital serves |
| `LIBRARY_PLACES`, `MUSEUM_PLACES` | 40, 25 | adults one library or museum enriches |
| `FREE_CLINIC_DIVISOR` | 400 | residents per extra hospital place from free clinics |
| `SCHOOL_EQ_GAIN` | 35 | education gained per schooled pupil per step |
| `CULTURE_EQ_GAIN` | 2 | education gained per adult mover with library access |
| `EQ_DECAY` | 1 | education forgotten per aging step without the reading campaign |
| `SCHOOL_COHORT_MAX` | 2 | last cohort index that counts as school age |
| `COLLEGE_COHORT_MIN`, `COLLEGE_COHORT_MAX` | 3, 4 | college-age cohorts |
| `MORTALITY_MONTHS` | 24 | months over which a full health shortfall empties a cohort |
| `HOSPITAL_MORTALITY_RELIEF` | 25 | percent of deaths hospitals prevent at full coverage |
| `PARENT_COHORT_MIN`, `PARENT_COHORT_MAX` | 4, 8 | child-bearing cohorts |
| `BIRTH_DIVISOR` | 300 | parents per birth per month |
| `NEWBORN_HEALTH_SERVED` | 85 | health of a baby born with hospital care |
| `NEWBORN_HEALTH_UNSERVED` | 35 | health of a baby born without |
| `HEALTH_ORDINANCE_BONUS` | 5 | newborn health per health ordinance |
| `NEWBORN_EQ_DIVISOR` | 5 | newborn education as a share of the city quotient |
| `POLLUTION_PENALTY_DIVISOR`, `POLLUTION_PENALTY_MAX` | 40, 3 | health lost per aging step from dirty air |
| `IMMIGRATION_ORDER` | 4,5,6,7,0,1,2,3,4…11 | cohorts immigrants fill, in order |
| `IMMIGRANT_HEALTH_BASE` | 65 | immigrant health minus cohort index |
| `IMMIGRANT_EQ_CHILD_BASE`, `IMMIGRANT_EQ_CHILD_STEP` | 17, 35 | child immigrant education |
| `IMMIGRANT_EQ_ADULT_BASE` | 90 | adult immigrant education minus cohort index |
| `WORK_COHORT_MIN`, `WORK_COHORT_MAX` | 4, 10 | working-age cohorts for headlines |
| `EQ_MAX`, `LE_MAX` | 150, 90 | headline ceilings |
| `CULTURE_EQ_BONUS` | 10 | headline education bonus at full library coverage |
| `HOSPITAL_LE_BONUS` | 10 | headline life expectancy bonus at full hospital coverage |
| `LE_ORDINANCE_BONUS` | 1 | life expectancy per health ordinance |
| `STATUS_THRESHOLDS` | 2000, 10000, 50000, 100000, 500000 | population that ends each settlement class |
| `STATUS_NAMES` | Village … Megalopolis | class labels |
| `VOTE_MIN_POPULATION` | 100 | residents needed for a vote |
| `VOTE_COUNT` | 100 | voters polled |
| `VOTE_TAX_WEIGHT` | 3 | complaint weight per point of residential tax |
| `VOTE_HEALTH_TARGET` | 70 | life expectancy below which health is a complaint |
| `VOTE_CONTENT_BASE` | 50 | baseline contentment added to land value |
| `APPROVAL_MILESTONE` | 80 | approval that triggers the milestone notice |
| `NEWS_BIRTHS_MIN` | 10 | births before a record month is news |

## Save state

`save()` returns the twenty pooled education scores, the twenty pooled health
scores, the record birth count, the complaint ranking of the last vote, and
the last census counts. Head counts,
headline scores and approval live in `CityStats` and are saved with it.
`load()` restores everything and tolerates missing keys.
