# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Exact units for flexible low-density parcels. Legacy lot balance stays separate.
class_name AgriculturalParcelParams
extends RefCounted

const AREA_DENOMINATOR := 36
const STOCK_DENOMINATOR := 9
const MAX_AREA := 64
const MAX_SPAN := 12
const MAX_STOCK_UNITS := 108
const JOB_UNITS_PER_TILE := {&"vegetables":144,&"alfalfa":54,&"grain":36,&"cattle_range":24,&"sheep_pasture":20}
const STOCK_UNITS_PER_TILE := {&"cattle_range":8,&"sheep_pasture":10}
const ACTIVE_CODES := {&"vegetables":282,&"alfalfa":283,&"grain":284,&"cattle_range":285,&"sheep_pasture":286}
const PREPARED := 287
const DORMANT := 288


static func cell_id(archetype: StringName, state: StringName) -> int:
	if not ACTIVE_CODES.has(archetype): return Buildings.NONE
	if state == &"prepared": return PREPARED
	if state == &"dormant": return DORMANT
	return ACTIVE_CODES.get(archetype, Buildings.NONE) if state == &"active" else Buildings.NONE


static func archetype_for_id(id: int) -> StringName:
	for key in ACTIVE_CODES:
		if ACTIVE_CODES[key] == id: return key
	return &""


static func job_units(archetype: StringName, area: int) -> int:
	return JOB_UNITS_PER_TILE.get(archetype, 0) * area


static func stock_rate(archetype: StringName) -> int:
	return STOCK_UNITS_PER_TILE.get(archetype, 0)


## Every livestock member has an entry, including exhausted zero tokens. Keeping
## those zeros distinguishes retained empty entitlement from newly added land.
static func stock_units(archetype: StringName, members: PackedInt32Array, existing: Dictionary = {}) -> Dictionary:
	var rate := stock_rate(archetype)
	var result := {}
	if rate == 0: return result
	var ordered := members.duplicate()
	ordered.sort()
	var remaining := MAX_STOCK_UNITS
	for i in ordered:
		if existing.has(i):
			result[i] = existing[i]
			remaining -= int(existing[i])
	for i in ordered:
		if not existing.has(i):
			result[i] = mini(rate, maxi(0, remaining))
			remaining -= int(result[i])
	return result
