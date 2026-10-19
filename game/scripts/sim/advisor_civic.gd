# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends RefCounted

const Params := preload("res://scripts/sim/data/advisor_params.gd")

## Collect diagnoses rather than presentation variants: every claim has a
## current observation and does not consume the newspaper's random stream.
static func _add(out: Array[Dictionary], kind: StringName, title: String, reason: String, text: String, priority: int = Params.WARNING) -> void:
	for item in out:
		if item.kind == kind: return
	out.append({"kind": kind, "title": title, "reason": reason, "text": text, "priority": priority, "urgent": false})

static func assess(ctx: SimContext, observed: RefCounted, out: Array[Dictionary]) -> void:
	var service := ServicesSystem.new()
	var existing := ctx.system(&"services")
	var modifier := int(existing.call("police_modifier")) if existing != null and existing.has_method("police_modifier") else 0
	var coverage := service.projected_coverage(ctx.stats, observed.stations, modifier)
	_station(ctx, observed, out, Buildings.POLICE_STATION, &"police", "Police", &"police", coverage.police)
	_station(ctx, observed, out, Buildings.FIRE_STATION, &"fire_protection", "Fire", &"fire", coverage.fire)
	_education(ctx, observed, out)
	_health(ctx, observed, out)

static func _station(ctx: SimContext, observed: RefCounted, out: Array[Dictionary], id: int, kind: StringName, title: String, funding_key: StringName, coverage: Grid8) -> void:
	if observed.occupied.is_empty(): return
	var gaps := 0
	for at: Vector2i in observed.occupied:
		if coverage.at(at.x >> 2, at.y >> 2) < Params.COVERAGE_STRENGTH: gaps += 1
	var crime := kind == &"police" and ctx.stats.average_crime >= NewspaperParams.CRIME_WARNING
	var unpowered := _unpowered_stations(observed.stations[id])
	if gaps * 100 < observed.occupied.size() * Params.COVERAGE_GAP_PERCENT and not crime and unpowered == 0: return
	var total := int(observed.counts[id])
	var funding := ctx.stats.funding_of(funding_key)
	var station := "police station" if kind == &"police" else "fire station"
	var observation := "Weak %s coverage at %d of %d developed sites with current funding and power." % [title.to_lower(), gaps, observed.occupied.size()]
	if total == 0:
		_add(out, kind, title, "missing", "%s Build a %s near the uncovered development." % [observation, station], Params.SERIOUS)
	elif funding < 100 and (gaps * 100 >= observed.occupied.size() * Params.COVERAGE_GAP_PERCENT or crime):
		_add(out, kind, title, "funding", "%s Funding is %d%%; restore the existing service before deciding where another %s is needed." % [observation, funding, station], Params.SERIOUS)
	elif unpowered > 0:
		_add(out, kind, title, "power", "%d existing %s%s %s unpowered and operating at half strength. Restore power, then inspect remaining gaps on the coverage map." % [unpowered, station, "" if unpowered == 1 else "s", "is" if unpowered == 1 else "are"], Params.SERIOUS)
	elif gaps * 100 >= observed.occupied.size() * Params.COVERAGE_GAP_PERCENT:
		_add(out, kind, title, "coverage", "%s Use the coverage map to place stations near those gaps." % observation, Params.SERIOUS)
	elif crime:
		_add(out, kind, title, "crime", "Last measured crime is %d/255 despite broad coverage. Inspect high-crime blocks and nearby crime sources before adding stations." % ctx.stats.average_crime, Params.SERIOUS)

static func _unpowered_stations(entries: Array) -> int:
	var total := 0
	for item: Dictionary in entries:
		if not bool(item.powered): total += 1
	return total

static func _education(ctx: SimContext, observed: RefCounted, out: Array[Dictionary]) -> void:
	var movers := 0
	# Each age cohort uses the same school capacity separately, not the sum.
	for source in PopulationParams.SCHOOL_COHORT_MAX:
		movers = maxi(movers, ceili(float(ctx.stats.cohorts[source]) / PopulationSystem.MONTHS_PER_COHORT))
	if movers == 0: return
	var total := int(observed.counts[Buildings.SCHOOL])
	var powered := int(observed.powered[Buildings.SCHOOL])
	var fund := ctx.stats.funding_of(&"schools")
	@warning_ignore("integer_division")
	var places := powered * PopulationParams.SCHOOL_PLACES * fund / 100
	if places >= movers: return
	var observation := "Schools provide %d places per aging cohort; about %d children in the largest relevant cohort advance each month." % [places, movers]
	if total == 0:
		_add(out, &"schools", "Education", "missing", "%s Build and power a school." % observation)
	elif powered < total:
		_add(out, &"schools", "Education", "power", "%s Restore power to existing schools before expanding." % observation)
	elif fund < 100:
		_add(out, &"schools", "Education", "funding", "%s School funding is %d%%; raise it before paying for another school." % [observation, fund])
	else:
		_add(out, &"schools", "Education", "capacity", "%s Another funded school would increase that capacity." % observation)

static func _health(ctx: SimContext, observed: RefCounted, out: Array[Dictionary]) -> void:
	if ctx.stats.population <= 0: return
	var total := int(observed.counts[Buildings.HOSPITAL])
	var powered := int(observed.powered[Buildings.HOSPITAL])
	var fund := ctx.stats.funding_of(&"health")
	var poor := ctx.stats.life_expectancy < Params.POOR_HEALTH
	# Population's care calculation uses housing census residents, not school
	# cohorts or a building quota. Before any housing exists, the last published
	# headcount is the only available denominator (e.g. a partial context).
	var people := int(observed.units.x) * ZoneParams.PEOPLE_PER_UNIT
	if people <= 0: people = ctx.stats.population
	@warning_ignore("integer_division")
	var places := powered * PopulationParams.HOSPITAL_PLACES * fund / 100
	if bool(ctx.stats.ordinances.get(&"free_clinics", false)):
		@warning_ignore("integer_division")
		places += people / PopulationParams.FREE_CLINIC_DIVISOR
	var observation := "Current care capacity: %d places for %d residents, including any Free Clinics." % [places, people]
	if total > 0 and powered < total:
		_add(out, &"hospitals", "Health", "power", "%s Restore power to the %d unpowered hospital%s so existing funding can provide care." % [observation, total - powered, "" if total - powered == 1 else "s"])
	elif total > 0 and fund < 100 and places < people and (poor or fund == 0):
		_add(out, &"hospitals", "Health", "funding", "%s Health funding is %d%%; restore funding before building more hospitals, then review the next monthly health reading." % [observation, fund])
	elif total == 0 and (poor or ctx.stats.population >= DisasterParams.ADVICE_POPULATION_2):
		_add(out, &"hospitals", "Health", "missing", "%s There is no hospital; a powered, funded hospital adds care. Review the Population report for monthly health outcomes." % observation)
	elif poor and places < people:
		_add(out, &"hospitals", "Health", "capacity", "%s Last measured life expectancy is %d years; additional funded care can help, alongside pollution reduction and clean drinking water." % [observation, ctx.stats.life_expectancy])
	elif poor:
		_add(out, &"hospitals", "Health", "health", "%s Last measured life expectancy is %d years despite sufficient care capacity; investigate pollution and drinking-water treatment before adding hospitals." % [observation, ctx.stats.life_expectancy])
