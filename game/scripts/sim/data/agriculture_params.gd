# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Agricultural balance is independent of the RCI stage and family tables.
class_name AgricultureParams
extends RefCounted

const DEMAND_INITIAL := 1000
const DEMAND_RAW_LIMIT := 2000
const DEMAND_DISPLAY_LIMIT := 999
const TARGET_BASE_JOBS := 20
const RESIDENTS_PER_TARGET_JOB := 40
const TARGET_JOBS_PER_CITY_LINK := 40
const TARGET_JOBS_LIMIT := 2000
const DEMAND_GAIN := 8
const DEMAND_MONTHLY_LIMIT := 400
const FAILURE_MONTHS := 3
const TAX_DEFAULT := 7
const TAX_MIN := 0
const TAX_MAX := 20
const ASSESSMENT_PER_JOB := 100
const ACCESS_RADIUS := 3
const EDGE_MARGIN := 2

const LOW_ARCHETYPES: Array[StringName] = [
	&"vegetables", &"alfalfa", &"grain", &"cattle_range", &"sheep_pasture",
]
const HIGH_ARCHETYPES: Array[StringName] = [
	&"greenhouse", &"nursery", &"dairy", &"feedlot", &"market_garden",
]

## [side, jobs/lot, water/tile, power/tile, livestock/lot, species, pollution]
const ROSTER := {
	&"vegetables": [1, 4, 3, 0, 0, &"", 1],
	&"alfalfa": [2, 6, 3, 0, 0, &"", 1],
	&"grain": [2, 4, 1, 0, 0, &"", 1],
	&"cattle_range": [3, 6, 1, 0, 8, &"beef_cattle", 0],
	&"sheep_pasture": [3, 5, 1, 0, 10, &"sheep", 0],
	&"greenhouse": [1, 10, 2, 2, 0, &"", 0],
	&"nursery": [2, 24, 2, 1, 0, &"", 0],
	&"dairy": [3, 40, 3, 1, 8, &"dairy_cattle", 4],
	&"feedlot": [3, 32, 2, 1, 12, &"beef_cattle", 6],
	&"market_garden": [2, 24, 3, 1, 0, &"", 1],
}


static func archetypes(dense: bool) -> Array[StringName]:
	return HIGH_ARCHETYPES.duplicate() if dense else LOW_ARCHETYPES.duplicate()


static func building_id(key: StringName) -> int:
	if not ROSTER.has(key):
		return Buildings.NONE
	return Buildings.id_of(StringName("ag_" + String(key)))


static func archetype_for_id(id: int) -> StringName:
	if Buildings.is_agricultural_cell(id):
		return AgriculturalParcelParams.archetype_for_id(id)
	if not Buildings.is_agricultural(id):
		return &""
	var key := StringName(String(Buildings.key(id)).trim_prefix("ag_"))
	return key if ROSTER.has(key) else &""


static func jobs_of(id: int) -> int:
	return _value(id, 1)


static func assessment_of(id: int) -> int:
	return jobs_of(id) * ASSESSMENT_PER_JOB


## Per-tile active consumption. Prepared and dormant plots draw zero.
static func water_load(id: int) -> int:
	return _value(id, 2)


static func power_load(id: int) -> int:
	return _value(id, 3)


static func pollution_of(id: int) -> int:
	return _value(id, 6)


static func state_id(state: StringName, side: int) -> int:
	if state not in [&"prepared", &"dormant"] or side < 1 or side > 3:
		return Buildings.NONE
	return Buildings.id_of(StringName("ag_%s_%dx%d" % [state, side, side]))


static func _value(id: int, column: int) -> int:
	if Buildings.is_agricultural_cell(id) and column == 1: return 0
	var key := archetype_for_id(id)
	return int(ROSTER[key][column]) if ROSTER.has(key) else 0
