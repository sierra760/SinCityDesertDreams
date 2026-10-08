# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Counts residents and jobs, ages the twenty five-year cohorts through
## births, deaths and migration, and publishes the headline population,
## education, health, employment, settlement class and approval figures.
## Rules are described in docs/simulation/population.md.
class_name PopulationSystem
extends SimSystem

const ScanTables := preload("res://scripts/sim/data/public_scan_tables.gd")

const COHORTS := 20
const YEARS_PER_COHORT := 5
const MONTHS_PER_COHORT := 60
const VOTE_MONTH := 3

## Pooled education and health scores per cohort (sums over its people).
var _education := PackedInt64Array()
var _health := PackedInt64Array()
## Most births seen in one month, for the record-birth story.
var _record_births := 0
## True while a reported exodus is still under way, so it is news once.
var _exodus_reported := false
## Complaint ranking of the last vote: {key, name, votes}, best first.
var _complaints: Array[Dictionary] = []
## Last census: residents, commercial, industrial, abandoned, schools, colleges,
## hospitals, libraries, museums.
var _census: Dictionary = {}


func _init() -> void:
	key = &"population"
	_education.resize(COHORTS)
	_health.resize(COHORTS)
	_census = _empty_census()


func setup(ctx: SimContext) -> void:
	var stats := ctx.stats
	if stats.cohorts.size() != COHORTS:
		var fixed := PackedInt32Array()
		fixed.resize(COHORTS)
		for i in mini(COHORTS, stats.cohorts.size()):
			fixed[i] = stats.cohorts[i]
		stats.cohorts = fixed
	# Pools that were never filled inherit the headline scores per head.
	var pooled := 0
	for i in COHORTS:
		pooled += _education[i] + _health[i]
	if pooled == 0:
		for i in COHORTS:
			_education[i] = stats.cohorts[i] * stats.education_quotient
			_health[i] = stats.cohorts[i] * stats.life_expectancy


func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_run_census(ctx)
	var services := _service_capacity(ctx)
	_advance_demographics(ctx, services)
	_publish_scores(ctx, services)
	_update_employment(ctx)
	_update_status(ctx)
	if ctx.month() == VOTE_MONTH:
		_hold_vote(ctx)


# ── Getters ──────────────────────────────────────────────────────────────

func residents() -> int:
	return int(_census.get("residents", 0))


func commercial_units() -> int:
	return int(_census.get("commercial", 0))


func industrial_units() -> int:
	return int(_census.get("industrial", 0))


## Abandoned capacity in census units of CENSUS_UNIT people.
func abandoned_units() -> int:
	return int(_census.get("abandoned", 0))


## Average education of one cohort.
func cohort_education(index: int, stats: CityStats) -> int:
	if index < 0 or index >= COHORTS or stats.cohorts[index] <= 0:
		return 0
	return int(_education[index] / stats.cohorts[index])


## Average health of one cohort.
func cohort_health(index: int, stats: CityStats) -> int:
	if index < 0 or index >= COHORTS or stats.cohorts[index] <= 0:
		return 0
	return int(_health[index] / stats.cohorts[index])


## Complaint ranking of the last March vote, most votes first.
func complaints() -> Array[Dictionary]:
	return _complaints.duplicate(true)


static func status_name(status: int) -> String:
	return PopulationParams.status_name(status)


# ── Census ───────────────────────────────────────────────────────────────

static func _empty_census() -> Dictionary:
	return {
		"residents": 0, "commercial": 0, "industrial": 0, "abandoned": 0,
		"schools": 0, "colleges": 0, "hospitals": 0, "libraries": 0, "museums": 0,
	}


@warning_ignore("integer_division")
func _run_census(ctx: SimContext) -> void:
	var city := ctx.city
	var zones := ctx.system(&"zones")
	var asks_zones := zones != null and zones.has_method("population_of")
	var native_zones: bool = asks_zones and zones.get_script() == preload("res://scripts/sim/zone_system.gd")
	var table_capacity: bool = not asks_zones or native_zones
	var capacities := ScanTables.capacities(native_zones)
	var abandoned_capacities := ScanTables.capacities(false)
	var c := _empty_census()
	var abandoned_capacity := 0
	var data := city.building.data
	var zone_data := city.zone.data
	var flags := city.flags.data
	var multi := UtilityParams.multi_tile_table()
	var categories := ScanTables.categories()
	for i in data.size():
		var id := data[i]
		if id == Buildings.NONE:
			continue
		if multi[id] and not (zone_data[i] & Zones.CORNER_NW):
			continue
		match categories[id]:
			Buildings.Category.RESIDENTIAL:
				c["residents"] += capacities[id] if table_capacity else _lot_capacity(zones, asks_zones, id)
			Buildings.Category.COMMERCIAL:
				c["commercial"] += capacities[id] if table_capacity else _lot_capacity(zones, asks_zones, id)
			Buildings.Category.INDUSTRIAL:
				c["industrial"] += capacities[id] if table_capacity else _lot_capacity(zones, asks_zones, id)
			Buildings.Category.ABANDONED:
				abandoned_capacity += abandoned_capacities[id]
			Buildings.Category.CIVIC:
				# Power is read at the lot's anchor. The CORNER_NW tile counts
				# each lot once, but a city saved at another rotation carries
				# that flag on another corner.
				var at := i
				if multi[id]:
					var a := City.footprint_anchor(data, zone_data, i % City.WIDTH, i / City.WIDTH)
					at = a.y * City.WIDTH + a.x
				if flags[at] & TileFlags.POWERED:
					match id:
						Buildings.SCHOOL: c["schools"] += 1
						Buildings.COLLEGE: c["colleges"] += 1
						Buildings.HOSPITAL: c["hospitals"] += 1
						Buildings.LIBRARY: c["libraries"] += 1
						Buildings.MUSEUM: c["museums"] += 1
	c["abandoned"] = abandoned_capacity / PopulationParams.CENSUS_UNIT
	_census = c
	var jobs := int(c["commercial"]) + int(c["industrial"])
	var ports := ctx.system(&"ports")
	if ports != null and ports.has_method("jobs"):
		jobs += int(ports.call("jobs"))
	ctx.stats.jobs = jobs


static func _lot_capacity(zones: SimSystem, asks_zones: bool, id: int) -> int:
	if asks_zones:
		var v := int(zones.call("population_of", id))
		if v > 0:
			return v
	return PopulationParams.lot_capacity(id)


# ── Service capacity ─────────────────────────────────────────────────────

@warning_ignore("integer_division")
func _service_capacity(ctx: SimContext) -> Dictionary:
	var stats := ctx.stats
	var people := residents()
	var hospital := int(_census["hospitals"]) * PopulationParams.HOSPITAL_PLACES * stats.funding_of(&"health") / 100
	if _ordinance(stats, PopulationParams.ORDINANCE_FREE_CLINICS):
		hospital += people / PopulationParams.FREE_CLINIC_DIVISOR
	var newborn_health := PopulationParams.NEWBORN_HEALTH_SERVED
	var health_ordinances := 0
	for o in [PopulationParams.ORDINANCE_ANTI_DRUG, PopulationParams.ORDINANCE_SMOKING_BAN]:
		if _ordinance(stats, o):
			newborn_health += PopulationParams.HEALTH_ORDINANCE_BONUS
			health_ordinances += 1
	if _ordinance(stats, PopulationParams.ORDINANCE_FREE_CLINICS):
		health_ordinances += 1
	var health_index := 0
	if people > 0:
		health_index = mini(100, hospital * 100 / people)
	elif hospital > 0:
		health_index = 100
	return {
		"school": int(_census["schools"]) * PopulationParams.SCHOOL_PLACES * stats.funding_of(&"schools") / 100,
		"college": int(_census["colleges"]) * PopulationParams.COLLEGE_PLACES * stats.funding_of(&"colleges") / 100,
		"hospital": hospital,
		"culture": int(_census["libraries"]) * PopulationParams.LIBRARY_PLACES
			+ int(_census["museums"]) * PopulationParams.MUSEUM_PLACES,
		"newborn_health": newborn_health,
		"health_ordinances": health_ordinances,
		"pollution_penalty": mini(PopulationParams.POLLUTION_PENALTY_MAX,
			stats.average_pollution / PopulationParams.POLLUTION_PENALTY_DIVISOR)
			+ (PopulationParams.UNTREATED_WATER_PENALTY if _untreated_water(ctx) else 0),
		"health_index": health_index,
		"pro_reading": _ordinance(stats, PopulationParams.ORDINANCE_PRO_READING),
		"junior_sports": _ordinance(stats, PopulationParams.ORDINANCE_JUNIOR_SPORTS),
		"cpr": _ordinance(stats, PopulationParams.ORDINANCE_CPR),
	}


## True when the city drinks more water than its treatment plants can clean,
## once treatment plants exist to build.
static func _untreated_water(ctx: SimContext) -> bool:
	if ctx.year() < Tools.available_year(Tools.Kind.WATER_TREATMENT, ctx.stats):
		return false
	var water := ctx.system(&"water")
	return water != null and water.has_method("treatment_adequate") \
		and not bool(water.call("treatment_adequate"))


static func _ordinance(stats: CityStats, ordinance: StringName) -> bool:
	return bool(stats.ordinances.get(ordinance, false))


# ── Demographics ─────────────────────────────────────────────────────────

## Whole part of numerator/denominator, with the remainder settled by chance.
static func _settle(numerator: int, denominator: int, rng: SimRng) -> int:
	if denominator <= 0:
		return 0
	@warning_ignore("integer_division")
	var whole := numerator / denominator
	if rng.below(denominator) < numerator % denominator:
		whole += 1
	return whole


@warning_ignore("integer_division")
func _advance_demographics(ctx: SimContext, services: Dictionary) -> void:
	var stats := ctx.stats
	var rng := ctx.rng
	var target := residents()
	var p: Array[int] = []
	p.assign(Array(stats.cohorts))
	var previous := 0
	for i in COHORTS:
		previous += p[i]
	if target == 0:
		_education.fill(0)
		_health.fill(0)
		stats.cohorts.fill(0)
		stats.population = 0
		return
	var incoming := maxi(0, target - previous)
	var outgoing := maxi(0, previous - target)
	var penalty := int(services["pollution_penalty"])
	var health_index := int(services["health_index"])

	# Deaths: a cohort whose average health falls short of its age loses people.
	var deaths := 0
	for i in range(1, COHORTS):
		var n := p[i]
		if n == 0:
			continue
		var age := i * YEARS_PER_COHORT
		var avg_health := int(_health[i] / n)
		if avg_health >= age:
			continue
		var shortfall := 100 - avg_health * 100 / age
		var hundredths := n * shortfall / PopulationParams.MORTALITY_MONTHS
		var dead := _settle(hundredths, 100, rng)
		dead -= dead * PopulationParams.HOSPITAL_MORTALITY_RELIEF * health_index / 10000
		if bool(services["cpr"]):
			dead -= dead * PopulationParams.CPR_MORTALITY_RELIEF / 100
		dead = mini(dead, n)
		if dead <= 0:
			continue
		_education[i] -= _education[i] * dead / n
		_health[i] -= _health[i] * dead / n
		p[i] = n - dead
		deaths += dead
	incoming += deaths

	# Aging: one sixtieth of every cohort moves up, oldest first.
	for dest in range(COHORTS - 1, 0, -1):
		var source := dest - 1
		var n := p[source]
		if n == 0:
			continue
		var movers := mini(n, _settle(n, MONTHS_PER_COHORT, rng))
		if movers == 0:
			continue
		var moved_eq := _education[source] * movers / n
		_education[source] -= moved_eq
		if dest <= PopulationParams.SCHOOL_COHORT_MAX:
			moved_eq += mini(int(services["school"]), movers) * PopulationParams.SCHOOL_EQ_GAIN
			if bool(services["junior_sports"]):
				moved_eq += movers * PopulationParams.JUNIOR_SPORTS_EQ_GAIN
		elif dest >= PopulationParams.COLLEGE_COHORT_MIN and dest <= PopulationParams.COLLEGE_COHORT_MAX:
			moved_eq += (mini(int(services["college"]), movers) * moved_eq / movers) / 2
		else:
			moved_eq += mini(int(services["culture"]), movers) * PopulationParams.CULTURE_EQ_GAIN
		if not bool(services["pro_reading"]):
			moved_eq = maxi(0, moved_eq - movers * PopulationParams.EQ_DECAY)
		_education[dest] += moved_eq
		var moved_health := _health[source] * movers / n
		_health[source] -= moved_health
		_health[dest] += maxi(0, moved_health - movers * penalty)
		p[source] = n - movers
		p[dest] += movers

	# Births from the child-bearing cohorts.
	var parents := 0
	for i in range(PopulationParams.PARENT_COHORT_MIN, PopulationParams.PARENT_COHORT_MAX + 1):
		parents += p[i]
	var births := parents / PopulationParams.BIRTH_DIVISOR
	var remainder := parents % PopulationParams.BIRTH_DIVISOR - penalty * PopulationParams.BIRTH_POLLUTION_STEP
	if rng.below(PopulationParams.BIRTH_DIVISOR) < remainder:
		births += 1
	if births > 0:
		var served := mini(int(services["hospital"]), births)
		_health[0] += (births - served) * PopulationParams.NEWBORN_HEALTH_UNSERVED \
			+ served * int(services["newborn_health"])
		_education[0] += births * stats.education_quotient / PopulationParams.NEWBORN_EQ_DIVISOR
		p[0] += births
		outgoing += births
		if births > _record_births:
			_record_births = births
			if births >= PopulationParams.NEWS_BIRTHS_MIN:
				ctx.events.report(&"birth_record", {"births": births})

	# Migration closes the gap between homes and people.
	if incoming > outgoing:
		_immigrate(p, incoming - outgoing)
	elif outgoing > incoming:
		_emigrate(p, outgoing - incoming, target, rng)
	_report_exodus(ctx, previous, maxi(0, outgoing - incoming))
	stats.cohorts = PackedInt32Array(p)
	var total := 0
	for i in COHORTS:
		total += p[i]
	stats.population = total


## A month in which a large share of the city moves away is news once.
func _report_exodus(ctx: SimContext, previous: int, leavers: int) -> void:
	var big := previous > 0 and leavers >= PopulationParams.EXODUS_MIN_PEOPLE \
		and leavers * 100 >= previous * PopulationParams.EXODUS_PERCENT
	if big and not _exodus_reported:
		@warning_ignore("integer_division")
		ctx.events.report(&"exodus", {"count": maxi(1, leavers / PopulationParams.PEOPLE_PER_FAMILY)}, 2)
	_exodus_reported = big


func _immigrate(p: Array[int], left: int) -> void:
	while left > 0:
		var step := (left >> 4) + 1
		for i in PopulationParams.IMMIGRATION_ORDER:
			if left <= 0:
				break
			var count := mini(step, left)
			var eq_each := PopulationParams.IMMIGRANT_EQ_ADULT_BASE - i
			if i < 3:
				eq_each = PopulationParams.IMMIGRANT_EQ_CHILD_BASE + PopulationParams.IMMIGRANT_EQ_CHILD_STEP * i
			_health[i] += count * (PopulationParams.IMMIGRANT_HEALTH_BASE - i)
			_education[i] += count * eq_each
			p[i] += count
			left -= count


@warning_ignore("integer_division")
func _emigrate(p: Array[int], left: int, target: int, rng: SimRng) -> void:
	var total := 0
	for i in COHORTS:
		total += p[i]
	left = mini(left, total)
	var passes := 0
	while left > 0 and passes < 64:
		passes += 1
		var pass_total := left
		for i in COHORTS:
			var n := p[i]
			if n == 0 or left == 0:
				continue
			var removed := pass_total * n / (target + left)
			if removed == 0 and rng.below(4) == 0:
				removed = 1
			removed = mini(removed, mini(n, left))
			if removed == 0:
				continue
			_education[i] -= _education[i] * removed / n
			_health[i] -= _health[i] * removed / n
			p[i] = n - removed
			left -= removed
	# Whatever chance left behind leaves from the largest cohort.
	while left > 0:
		var largest := 0
		for i in COHORTS:
			if p[i] > p[largest]:
				largest = i
		if p[largest] == 0:
			break
		var removed := mini(p[largest], left)
		_education[largest] -= _education[largest] * removed / p[largest]
		_health[largest] -= _health[largest] * removed / p[largest]
		p[largest] -= removed
		left -= removed


# ── Headline scores ──────────────────────────────────────────────────────

@warning_ignore("integer_division")
func _publish_scores(ctx: SimContext, services: Dictionary) -> void:
	var stats := ctx.stats
	var people := residents()
	var health_index := int(services["health_index"])
	stats.health_index = health_index
	var working := 0
	var eq_sum := 0
	var health_sum := 0
	for i in range(PopulationParams.WORK_COHORT_MIN, PopulationParams.WORK_COHORT_MAX + 1):
		working += stats.cohorts[i]
		eq_sum += _education[i]
		health_sum += _health[i]
	if working == 0:
		return
	var culture := mini(int(services["culture"]), people)
	var culture_bonus := PopulationParams.CULTURE_EQ_BONUS * culture / maxi(people, 1)
	stats.education_quotient = clampi(eq_sum / working + culture_bonus, 0, PopulationParams.EQ_MAX)
	var hospital_bonus := PopulationParams.HOSPITAL_LE_BONUS * health_index / 100
	var ordinance_bonus := int(services["health_ordinances"]) * PopulationParams.LE_ORDINANCE_BONUS
	var le := health_sum / working + hospital_bonus + ordinance_bonus - int(services["pollution_penalty"])
	stats.life_expectancy = clampi(le, 0, PopulationParams.LE_MAX)


# ── Employment ───────────────────────────────────────────────────────────

@warning_ignore("integer_division")
func _update_employment(ctx: SimContext) -> void:
	var stats := ctx.stats
	# Lost jobs: abandoned lots are jobs and homes that closed.
	var idle := abandoned_units()
	var lost := idle * 100 / (residents() / PopulationParams.CENSUS_UNIT + idle + 1)
	# Too few jobs: working-age residents beyond the jobs they can reach.
	var shortfall := job_shortfall_percent(stats, reachable_jobs(ctx))
	stats.unemployment = clampi(maxi(lost, shortfall), 0, 100)
	stats.employment_rate = float(100 - stats.unemployment)


## Jobs residents can reach: the city's own (`stats.jobs`) plus commuting
## places in neighbor towns over road and rail links.
static func reachable_jobs(ctx: SimContext) -> int:
	var jobs := ctx.stats.jobs
	var neighbors := ctx.system(&"neighbors")
	if neighbors != null and neighbors.has_method("link_count"):
		jobs += int(neighbors.call("link_count")) * PopulationParams.COMMUTE_JOBS_PER_LINK
	return jobs


## Percent of working-age residents (cohorts WORK_COHORT_MIN..MAX) without a
## job within reach.
static func job_shortfall_percent(stats: CityStats, jobs: int) -> int:
	var workers := 0
	for i in range(PopulationParams.WORK_COHORT_MIN, mini(PopulationParams.WORK_COHORT_MAX + 1, stats.cohorts.size())):
		workers += stats.cohorts[i]
	if workers <= 0 or jobs >= workers:
		return 0
	@warning_ignore("integer_division")
	return (workers - jobs) * 100 / workers


# ── Settlement class ─────────────────────────────────────────────────────

func _update_status(ctx: SimContext) -> void:
	var city := ctx.city
	var total := ctx.stats.total_population()
	var last := PopulationParams.STATUS_THRESHOLDS.size() - 1
	if city.status < 0:
		city.status = 0
	if city.status >= last:
		return
	if total > PopulationParams.STATUS_THRESHOLDS[city.status + 1]:
		city.status += 1
		ctx.events.report(&"status_upgrade", {
			"status": city.status,
			"name": PopulationParams.status_name(city.status),
			"population": total,
		}, 2)


# ── March vote ───────────────────────────────────────────────────────────

## The March vote's weights: `complaints` in `COMPLAINT_KEYS` order and the
## `content` weight that counts as approval.
static func vote_weights(stats: CityStats) -> Dictionary:
	# Residents complain about the rate they feel, ordinances included.
	var tax_weight := OrdinanceSystem.effective_rates(stats).x * PopulationParams.VOTE_TAX_WEIGHT
	if _ordinance(stats, PopulationParams.ORDINANCE_PARKING_FINES):
		tax_weight += PopulationParams.VOTE_PARKING_FINES_WEIGHT
	var complaints: Array[int] = [
		stats.average_traffic,
		stats.average_pollution,
		stats.average_crime,
		tax_weight,
		stats.unemployment,
		100 - stats.education_quotient if stats.education_quotient <= 100 else 0,
		PopulationParams.VOTE_HEALTH_TARGET - stats.life_expectancy if stats.life_expectancy <= PopulationParams.VOTE_HEALTH_TARGET else 0,
	]
	var content := stats.average_land_value + PopulationParams.VOTE_CONTENT_BASE
	if _ordinance(stats, PopulationParams.ORDINANCE_SHELTERS):
		content += PopulationParams.VOTE_SHELTER_CONTENT
	return {"complaints": complaints, "content": content}


func _hold_vote(ctx: SimContext) -> void:
	var stats := ctx.stats
	if residents() < PopulationParams.VOTE_MIN_POPULATION:
		return
	var weighed := vote_weights(stats)
	var weights: Array[int] = weighed["complaints"]
	var total := int(weighed["content"])
	for w in weights:
		total += w
	if total <= 0:
		return
	var votes: Array[int] = [0, 0, 0, 0, 0, 0, 0]
	var approve := 0
	for _voter in PopulationParams.VOTE_COUNT:
		var draw := ctx.rng.below(total)
		var index := 0
		while index < weights.size():
			if draw < weights[index]:
				break
			draw -= weights[index]
			index += 1
		if index == weights.size():
			approve += 1
		else:
			votes[index] += 1
	var ranking: Array[Dictionary] = []
	for i in weights.size():
		ranking.append({
			"key": PopulationParams.COMPLAINT_KEYS[i],
			"name": PopulationParams.COMPLAINT_NAMES[i],
			"votes": votes[i],
		})
	ranking.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["votes"]) > int(b["votes"]))
	_complaints = ranking
	var previous := stats.approval
	stats.approval = approve
	ctx.events.report(&"approval_vote", {
		"approval": approve,
		"previous": previous,
		"complaint": ranking[0]["key"],
		"complaint_name": ranking[0]["name"],
	}, 2)
	if previous < PopulationParams.APPROVAL_MILESTONE and approve >= PopulationParams.APPROVAL_MILESTONE:
		ctx.events.notify(&"approval_milestone", {"approval": approve})


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	var complaint_rows: Array = []
	for row in _complaints:
		complaint_rows.append({"key": String(row["key"]), "name": row["name"], "votes": int(row["votes"])})
	return {
		"education": Array(_education),
		"health": Array(_health),
		"record_births": _record_births,
		"exodus_reported": _exodus_reported,
		"complaints": complaint_rows,
		"census": _census.duplicate(),
	}


func load(data: Dictionary) -> void:
	var education: Array = data.get("education", [])
	var health: Array = data.get("health", [])
	for i in COHORTS:
		_education[i] = int(education[i]) if i < education.size() else 0
		_health[i] = int(health[i]) if i < health.size() else 0
	_record_births = int(data.get("record_births", 0))
	_exodus_reported = bool(data.get("exodus_reported", false))
	_complaints.clear()
	var rows: Array = data.get("complaints", [])
	for row in rows:
		var r: Dictionary = row
		_complaints.append({"key": StringName(String(r.get("key", ""))), "name": String(r.get("name", "")), "votes": int(r.get("votes", 0))})
	_census = _empty_census()
	var saved: Dictionary = data.get("census", {})
	for k in _census:
		_census[k] = int(saved.get(k, 0))
