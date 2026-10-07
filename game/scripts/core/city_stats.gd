# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## City-wide scalar state shared by the systems and read by the UI.
##
## Every field is typed. Systems keep private working state in their own
## objects; only values another system or the UI needs belong here.
class_name CityStats
extends RefCounted

# ── Demand and population ────────────────────────────────────────────────
## Residential, commercial and industrial demand, each in [-999, 999].
var demand := Vector3i.ZERO
var population := 0            ## ordinary residents (arcologies excluded)
var arcology_population := 0
## Twenty cohorts of five years each.
var cohorts := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var jobs := 0
var employment_rate := 100.0

# ── Utilities ────────────────────────────────────────────────────────────
var power_capacity := 0
var power_demand := 0
var unpowered_buildings := 0
var water_capacity := 0
var water_demand := 0
var unwatered_buildings := 0
var water_stored := 0          ## towers
var water_storage_capacity := 0

# ── Quality indices ──────────────────────────────────────────────────────
var life_expectancy := 50
var education_quotient := 100
var average_crime := 0         ## 0..255
var average_pollution := 0
var average_land_value := 0
var average_traffic := 0
var approval := 50             ## percent, set by the March vote
var health_index := 0
var unemployment := 0

# ── Taxes and funding ────────────────────────────────────────────────────
var tax_residential := 7
var tax_commercial := 7
var tax_industrial := 7
## Per-sector industrial tax rates, indexed like IndustrySectors.
var sector_taxes := PackedInt32Array([7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7])
## Funding percentages 0..100.
var funding: Dictionary = {
	&"police": 100, &"fire": 100, &"health": 100, &"schools": 100, &"colleges": 100,
	&"roads": 100, &"highways": 100, &"bridges": 100, &"rail": 100, &"subway": 100, &"tunnels": 100,
}
var auto_budget := false

# ── Finance ──────────────────────────────────────────────────────────────
## Outstanding bonds, oldest first: {"principal": int, "rate": int}.
var bonds: Array[Dictionary] = []
var prime_rate := 7
var city_value := 0
## Year-to-date accounts, settled at the January budget review.
var ledger: Dictionary = {}
var last_year_ledger: Dictionary = {}
var bankrupt := false

# ── Ordinances ───────────────────────────────────────────────────────────
var ordinances: Dictionary = {}   ## key -> bool
var ordinance_income := 0
var ordinance_cost := 0

# ── Economy ──────────────────────────────────────────────────────────────
var economy_phase := 1            ## national trend: 0 recession .. 3 boom
var sector_shares := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var neighbor_populations := PackedInt32Array([0, 0, 0, 0])

# ── Events and options ───────────────────────────────────────────────────
var disasters_enabled := true
var active_fires := 0
var active_disaster: StringName = &""
var rewards_offered: Dictionary = {}   ## building key -> true once unlocked
var rewards_built: Dictionary = {}
var inventions: Dictionary = {}        ## technology key -> year available

# ── Histories for the graph windows ──────────────────────────────────────
## Series name -> PackedInt32Array of monthly samples (newest last).
var history: Dictionary = {}
var newspaper_archive: Array[Dictionary] = []


func record(series: StringName, value: int, keep: int = 1200) -> void:
	var arr: PackedInt32Array = history.get(series, PackedInt32Array())
	arr.append(value)
	if arr.size() > keep:
		arr = arr.slice(arr.size() - keep)
	history[series] = arr


func funding_of(service: StringName) -> int:
	return int(funding.get(service, 100))


func set_funding(service: StringName, percent: int) -> void:
	funding[service] = clampi(percent, 0, 100)


func total_population() -> int:
	return population + arcology_population


func to_dict() -> Dictionary:
	var out := {}
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var v = get(p.name)
		match typeof(v):
			TYPE_VECTOR3I:
				out[p.name] = [v.x, v.y, v.z]
			TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
				out[p.name] = Array(v)
			TYPE_DICTIONARY:
				out[p.name] = _dict_to_json(v)
			_:
				out[p.name] = v
	return out


func from_dict(data: Dictionary) -> void:
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		if not data.has(p.name):
			continue
		var current = get(p.name)
		var v = data[p.name]
		match typeof(current):
			TYPE_VECTOR3I:
				set(p.name, Vector3i(int(v[0]), int(v[1]), int(v[2])))
			TYPE_PACKED_INT32_ARRAY:
				set(p.name, PackedInt32Array(v))
			TYPE_PACKED_FLOAT32_ARRAY:
				set(p.name, PackedFloat32Array(v))
			TYPE_INT:
				set(p.name, int(v))
			TYPE_FLOAT:
				set(p.name, float(v))
			TYPE_BOOL:
				set(p.name, bool(v))
			TYPE_DICTIONARY:
				set(p.name, _dict_from_json(v, current))
			TYPE_ARRAY:
				# Typed arrays keep their type when mutated in place.
				var arr: Array = get(p.name)
				arr.clear()
				for item in v:
					arr.append(item)
			_:
				set(p.name, v)


static func _dict_to_json(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var v = d[k]
		if typeof(v) == TYPE_PACKED_INT32_ARRAY or typeof(v) == TYPE_PACKED_FLOAT32_ARRAY:
			out[String(k)] = Array(v)
		elif typeof(v) == TYPE_DICTIONARY:
			out[String(k)] = _dict_to_json(v)
		else:
			out[String(k)] = v
	return out


static func _dict_from_json(v: Dictionary, template: Dictionary) -> Dictionary:
	var out := {}
	for k in v:
		var val = v[k]
		var sample = template.get(StringName(k), template.get(k, null))
		if typeof(sample) == TYPE_PACKED_INT32_ARRAY or (typeof(val) == TYPE_ARRAY and not val.is_empty() and typeof(val[0]) == TYPE_FLOAT and template.is_empty()):
			out[StringName(k)] = PackedInt32Array(val)
		elif typeof(sample) == TYPE_INT:
			out[StringName(k)] = int(val)
		elif typeof(sample) == TYPE_BOOL:
			out[StringName(k)] = bool(val)
		elif typeof(val) == TYPE_ARRAY:
			out[StringName(k)] = PackedInt32Array(val)
		else:
			out[StringName(k)] = val
	return out
