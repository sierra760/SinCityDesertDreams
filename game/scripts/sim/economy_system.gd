# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The world outside the city and the shape of its industry: the national
## phase cycle, eleven industry sectors, the city's assessed value and the
## years new technologies arrive. Rules are in docs/simulation/economy.md.
class_name EconomySystem
extends SimSystem

## Product-per-head ratio a freshly seeded nation starts at, per phase, so the
## opening phase holds for a while before the cycle moves on.
const START_RATIOS: Array[int] = [35, 52, 67, 85]
## Random draws averaged into the monthly demand noise.
const NOISE_DRAWS := 4
const NOISE_RANGE := 128

var _assessment := PackedInt32Array()

var _nation_population := 0
var _nation_product := 0
var _demand: Array[int] = []
var _weights: Array[int] = []
var _local: Array[int] = []
var _previous_residents := -1
var _pollution_modifier := 0
var _demand_bonus := 0
var _city_value := 0
## Technology key -> true once its arrival has been reported.
var _announced: Dictionary = {}
var _stats: CityStats


func _init() -> void:
	key = &"economy"
	_assessment.resize(Buildings.COUNT)
	for id: int in Buildings.COUNT:
		var edge := Buildings.size(id).x
		match Buildings.category(id):
			Buildings.Category.RESIDENTIAL, Buildings.Category.COMMERCIAL, Buildings.Category.INDUSTRIAL:
				_assessment[id] = EconomyParams.LOT_VALUE[mini(edge, EconomyParams.LOT_VALUE.size() - 1)]
			Buildings.Category.ABANDONED:
				_assessment[id] = EconomyParams.LOT_VALUE[mini(edge, EconomyParams.LOT_VALUE.size() - 1)] / EconomyParams.ABANDONED_VALUE_DIVISOR
			Buildings.Category.CONSTRUCTION, Buildings.Category.RUBBLE, Buildings.Category.NONE:
				pass
			Buildings.Category.REWARD:
				_assessment[id] = EconomyParams.LANDMARK_VALUE
			_:
				_assessment[id] = Buildings.cost(id)
	_demand.resize(EconomyParams.SECTOR_COUNT)
	_weights.resize(EconomyParams.SECTOR_COUNT)
	_local.resize(EconomyParams.SECTOR_COUNT)
	_demand.fill(0)
	_weights.fill(0)
	_local.fill(0)


func setup(ctx: SimContext) -> void:
	var stats := ctx.stats
	_stats = stats
	_roll_inventions(ctx)
	if stats.sector_taxes.size() != EconomyParams.SECTOR_COUNT:
		var fixed := PackedInt32Array()
		fixed.resize(EconomyParams.SECTOR_COUNT)
		fixed.fill(stats.tax_industrial)
		for i in mini(fixed.size(), stats.sector_taxes.size()):
			fixed[i] = stats.sector_taxes[i]
		stats.sector_taxes = fixed
	if stats.sector_shares.size() != EconomyParams.SECTOR_COUNT:
		var shares := PackedFloat32Array()
		shares.resize(EconomyParams.SECTOR_COUNT)
		stats.sector_shares = shares
	stats.economy_phase = clampi(stats.economy_phase, 0, EconomyParams.PHASE_NAMES.size() - 1)
	if _nation_population <= 0:
		_nation_population = EconomyParams.nation_start_population(ctx.city.founded_year)
		@warning_ignore("integer_division")
		_nation_product = _nation_population * START_RATIOS[stats.economy_phase] / 100
	var seeded := false
	for d in _demand:
		seeded = seeded or d != 0
	if not seeded:
		_demand = EconomyParams.era_demand(ctx.year())
		_weights = _demand.duplicate()


func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_stats = ctx.stats
	_advance_nation(ctx)
	_advance_sectors(ctx)
	_assess_city(ctx)
	_announce_inventions(ctx)


# ── Getters ──────────────────────────────────────────────────────────────

## Percentage points the zone system adds to the industrial target factor
## when one sector dominates the city's industry.
func industrial_demand_modifier() -> int:
	return _demand_bonus


## How dirty the industrial mix is: -1 when heavy industry is a small share,
## rising as it grows.
func pollution_modifier() -> int:
	return _pollution_modifier


func national_population() -> int:
	return _nation_population


## Assessed value of everything built, as of the last monthly assessment.
func assessed_value() -> int:
	return _city_value


func national_product() -> int:
	return _nation_product


static func sector_name(index: int) -> String:
	if index < 0 or index >= EconomyParams.SECTOR_COUNT:
		return ""
	return EconomyParams.SECTOR_NAMES[index]


static func phase_name(phase: int) -> String:
	return EconomyParams.phase_name(phase)


## One row per sector for the Industries window.
func sector_report() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var total := 0
	for units in _local:
		total += units
	for i in EconomyParams.SECTOR_COUNT:
		var share := 0.0
		if _stats != null and i < _stats.sector_shares.size():
			share = _stats.sector_shares[i]
		var tax := 0
		if _stats != null and i < _stats.sector_taxes.size():
			tax = _stats.sector_taxes[i]
		out.append({
			"index": i,
			"key": EconomyParams.SECTOR_KEYS[i],
			"name": EconomyParams.SECTOR_NAMES[i],
			"demand": _weights[i],
			"tax": tax,
			"units": _local[i],
			"share": share,
			"heavy": i in EconomyParams.HEAVY_SECTORS,
		})
	return out


## Technology a building needs, or an empty name.
static func technology_for(building_key: StringName) -> StringName:
	return EconomyParams.technology_for(building_key)


## First year a technology can be built.
func available_year(technology: StringName) -> int:
	if _stats != null and _stats.inventions.has(technology):
		return int(_stats.inventions[technology])
	if EconomyParams.TECHNOLOGIES.has(technology):
		return int(EconomyParams.TECHNOLOGIES[technology])
	return 0


func is_available(building_key: StringName, year: int) -> bool:
	var tech := technology_for(building_key)
	if tech == &"":
		return true
	return year >= available_year(tech)


# ── National economy ─────────────────────────────────────────────────────

@warning_ignore("integer_division")
static func _grow(value: int, rate: int, cap: int) -> int:
	var delta := value * rate / EconomyParams.GROWTH_SCALE
	if value > cap:
		# Above the cap the figure always shrinks, whatever the sign of the rate.
		delta = -absi(delta)
	return maxi(0, value + delta)


static func _phase_for_ratio(ratio: int) -> int:
	if ratio < EconomyParams.RATIO_SLOW:
		return 0
	if ratio < EconomyParams.RATIO_GROWTH:
		return 1
	if ratio < EconomyParams.RATIO_BOOM:
		return 2
	return 3


@warning_ignore("integer_division")
func _advance_nation(ctx: SimContext) -> void:
	var stats := ctx.stats
	var phase := clampi(stats.economy_phase, 0, EconomyParams.PHASE_NAMES.size() - 1)
	_nation_population = _grow(_nation_population, phase, EconomyParams.NATION_POPULATION_CAP)
	_nation_product = _grow(_nation_product, EconomyParams.PRODUCT_RATE[phase], EconomyParams.NATION_PRODUCT_CAP)
	if ctx.rng.below(EconomyParams.REVIEW_CHANCE) != 0:
		return
	var ratio := 100 * _nation_product / (_nation_population + 1)
	if ctx.rng.below(EconomyParams.PHASE_CHANGE_CHANCE) != 0:
		return
	var next := _phase_for_ratio(ratio)
	if next == phase:
		return
	stats.economy_phase = next
	ctx.events.report(&"economy_shift", {
		"phase": next,
		"previous": phase,
		"name": EconomyParams.phase_name(next),
	}, 2)


# ── Sectors ──────────────────────────────────────────────────────────────

func _industrial_units(ctx: SimContext) -> int:
	var population := ctx.system(&"population")
	if population != null and population.has_method("industrial_units"):
		return int(population.call("industrial_units"))
	var city := ctx.city
	var zones := ctx.system(&"zones")
	var asks_zones := zones != null and zones.has_method("population_of")
	var units := 0
	var data := city.building.data
	for i in data.size():
		var id := data[i]
		if id == Buildings.NONE or Buildings.category(id) != Buildings.Category.INDUSTRIAL:
			continue
		var x := i % City.WIDTH
		var y := i / City.WIDTH
		if Buildings.is_multi_tile(id) and not (Zones.corners(city.zone.at(x, y)) & Zones.CORNER_NW):
			continue
		var v := 0
		if asks_zones:
			v = int(zones.call("population_of", id))
		if v <= 0:
			v = PopulationParams.lot_capacity(id)
		units += v
	return units


static func _scale(values: Array[int], indices: Array[int], factor: float) -> void:
	for i in indices:
		values[i] = int(values[i] * factor)


@warning_ignore("integer_division")
func _advance_sectors(ctx: SimContext) -> void:
	var stats := ctx.stats
	var rng := ctx.rng
	var baseline := EconomyParams.era_demand(ctx.year())
	var growing := _previous_residents >= 0 and stats.population > _previous_residents
	_previous_residents = stats.population
	var units := _industrial_units(ctx)
	var pollution_controls := bool(stats.ordinances.get(&"pollution_controls", false))
	var eq := stats.education_quotient

	# Demand wanders around the era baseline; weights add the city's influence.
	var weights: Array[int] = []
	weights.resize(EconomyParams.SECTOR_COUNT)
	var denominator := 0
	for i in EconomyParams.SECTOR_COUNT:
		var noise := 0
		for _d in NOISE_DRAWS:
			noise += rng.below(NOISE_RANGE)
		_demand[i] = (3 * _demand[i] + baseline[i] * noise / (NOISE_DRAWS * NOISE_RANGE / 2)) / 4
		weights[i] = _demand[i]
	if pollution_controls:
		_scale(weights, EconomyParams.HEAVY_SECTORS, EconomyParams.POLLUTION_CONTROL_SCALE)
	if growing:
		var construction: Array[int] = [EconomyParams.CONSTRUCTION_SECTOR]
		_scale(weights, construction, EconomyParams.GROWTH_CONSTRUCTION_SCALE)
	if eq > EconomyParams.EQ_HIGH_TECH:
		_scale(weights, EconomyParams.HIGH_TECH_SECTORS, EconomyParams.HIGH_TECH_SCALE)
	elif eq > EconomyParams.EQ_TECH:
		_scale(weights, EconomyParams.TECH_SECTORS, EconomyParams.TECH_SCALE)
	elif eq < EconomyParams.EQ_LOW:
		_scale(weights, EconomyParams.HIGH_TECH_SECTORS, EconomyParams.LOW_EQ_SCALE)
	for i in EconomyParams.SECTOR_COUNT:
		var tax := stats.sector_taxes[i] if i < stats.sector_taxes.size() else 0
		weights[i] = maxi(0, weights[i] - tax)
		denominator += weights[i]
	_weights = weights

	# Allocate the industrial units among the sectors.
	var existing := 0
	for u in _local:
		existing += u
	if existing > units:
		var surplus100 := (existing - units) * 100
		for i in EconomyParams.SECTOR_COUNT:
			var share := surplus100 * _local[i] / existing
			var lost := share / 100
			if rng.below(100) < share % 100:
				lost += 1
			_local[i] = maxi(0, _local[i] - lost)
	elif denominator > 0 and existing < units:
		var shortfall100 := (units - existing) * 100
		for i in EconomyParams.SECTOR_COUNT:
			if weights[i] == 0:
				continue
			var share := shortfall100 * weights[i] / denominator
			var gained := share / 100
			if rng.below(100) < share % 100:
				gained += 1
			_local[i] += gained

	# Shares, then the two modifiers other systems read.
	var total := 0
	for u in _local:
		total += u
	var shares := PackedFloat32Array()
	shares.resize(EconomyParams.SECTOR_COUNT)
	if total > 0:
		for i in EconomyParams.SECTOR_COUNT:
			shares[i] = float(_local[i]) / float(total)
	elif denominator > 0:
		for i in EconomyParams.SECTOR_COUNT:
			shares[i] = float(weights[i]) / float(denominator)
	else:
		shares.fill(1.0 / float(EconomyParams.SECTOR_COUNT))
	stats.sector_shares = shares
	var heavy := 0
	for i in EconomyParams.HEAVY_SECTORS:
		heavy += _local[i]
	var heavy_percent := heavy * 100 / (total + 1)
	if heavy_percent < EconomyParams.HEAVY_CLEAN_PERCENT:
		_pollution_modifier = -1
	else:
		_pollution_modifier = (heavy_percent - EconomyParams.HEAVY_CLEAN_PERCENT) / EconomyParams.HEAVY_DIRTY_STEP
	var largest := 0
	for u in _local:
		largest = maxi(largest, u * 100 / (total + 1))
	if largest < EconomyParams.DOMINANT_PERCENT:
		_demand_bonus = 0
	else:
		_demand_bonus = (largest - EconomyParams.DOMINANT_PERCENT) / EconomyParams.DOMINANT_STEP


# ── City value ───────────────────────────────────────────────────────────

@warning_ignore("integer_division")
func _assess_city(ctx: SimContext) -> void:
	var city := ctx.city
	var value := 0
	var data := city.building.data
	var zones := city.zone.data
	var multi := UtilityParams.multi_tile_table()
	for i: int in data.size():
		var id := data[i]
		if id == Buildings.NONE or (multi[id] and not (zones[i] & Zones.CORNER_NW)):
			continue
		value += _assessment[id]
	_city_value = value
	ctx.stats.city_value = value


# ── Inventions ───────────────────────────────────────────────────────────

func _roll_inventions(ctx: SimContext) -> void:
	var stats := ctx.stats
	var founded := ctx.city.founded_year
	if stats.inventions.is_empty():
		for tech in EconomyParams.TECHNOLOGIES:
			var year: int = int(EconomyParams.TECHNOLOGIES[tech]) + ctx.rng.below(EconomyParams.INVENTION_SPREAD)
			stats.inventions[tech] = year
	for tech in stats.inventions:
		if int(stats.inventions[tech]) <= founded:
			_announced[StringName(tech)] = true


func _announce_inventions(ctx: SimContext) -> void:
	var year := ctx.year()
	for tech in ctx.stats.inventions:
		var name := StringName(tech)
		if _announced.has(name):
			continue
		var available := int(ctx.stats.inventions[tech])
		if available > year:
			continue
		_announced[name] = true
		ctx.events.report(&"invention", {
			"technology": name,
			"name": String(EconomyParams.TECHNOLOGY_NAMES.get(name, String(name))),
			"year": available,
		}, 2)


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	var announced: Array = []
	for tech in _announced:
		announced.append(String(tech))
	return {
		"nation_population": _nation_population,
		"nation_product": _nation_product,
		"demand": _demand.duplicate(),
		"weights": _weights.duplicate(),
		"local": _local.duplicate(),
		"previous_residents": _previous_residents,
		"pollution_modifier": _pollution_modifier,
		"demand_bonus": _demand_bonus,
		"city_value": _city_value,
		"announced": announced,
	}


func load(data: Dictionary) -> void:
	_nation_population = int(data.get("nation_population", _nation_population))
	_nation_product = int(data.get("nation_product", _nation_product))
	_load_row(_demand, data.get("demand", []))
	_load_row(_weights, data.get("weights", []))
	_load_row(_local, data.get("local", []))
	_previous_residents = int(data.get("previous_residents", -1))
	_pollution_modifier = int(data.get("pollution_modifier", 0))
	_demand_bonus = int(data.get("demand_bonus", 0))
	_city_value = int(data.get("city_value", 0))
	_announced.clear()
	var announced: Array = data.get("announced", [])
	for tech in announced:
		_announced[StringName(String(tech))] = true


static func _load_row(target: Array[int], source: Array) -> void:
	for i in target.size():
		target[i] = int(source[i]) if i < source.size() else 0
