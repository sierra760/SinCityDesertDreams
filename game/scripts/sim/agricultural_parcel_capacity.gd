# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Pure integer publication: city totals and each destination share one rounding.
class_name AgriculturalParcelCapacity
extends RefCounted


static func allocate(records: Array[Dictionary]) -> Dictionary:
	var by_id := {}
	var remainders: Array[Dictionary] = []
	var total_units := 0
	var base_jobs := 0
	var active_count := 0
	for r in records:
		var id: int = r.id
		by_id[id] = 0
		if r.state != &"active": continue
		active_count += 1
		var units := AgriculturalParcelParams.job_units(r.archetype, r.members.size())
		if r.mode == &"legacy":
			units = AgricultureParams.jobs_of(r.legacy_code) * AgriculturalParcelParams.AREA_DENOMINATOR
		var jobs := units / AgriculturalParcelParams.AREA_DENOMINATOR
		by_id[id] = jobs
		base_jobs += jobs
		total_units += units
		remainders.append({"id":id,"remainder":units % AgriculturalParcelParams.AREA_DENOMINATOR})
	remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.remainder > b.remainder if a.remainder != b.remainder else a.id < b.id)
	var total_jobs := total_units / AgriculturalParcelParams.AREA_DENOMINATOR
	for i in total_jobs - base_jobs:
		by_id[remainders[i].id] += 1
	return {"jobs":total_jobs,"by_id":by_id,"active_count":active_count}


## One deterministic, actual member tile for every parcel with allocated jobs.
## A zero-job parcel cannot receive a commute merely for having an active marker.
static func destinations(records: Array[Dictionary], allocation: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var by_id: Dictionary = allocation.get("by_id",{})
	for r in records:
		var jobs := int(by_id.get(r.id,0))
		var members: PackedInt32Array = r.members
		if jobs <= 0 or members.is_empty(): continue
		var index := members[0]
		@warning_ignore("integer_division")
		result.append({"tile":Vector2i(index % City.WIDTH,index / City.WIDTH),"jobs":jobs,"parcel_id":int(r.id)})
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.parcel_id < b.parcel_id)
	return result


## Nonnegative emissions retain the same denominator as area capacity until
## the half-resolution environment block has gathered all of its members.
static func emission_units(records: Array[Dictionary]) -> Dictionary:
	var result := {}
	for r in records:
		if r.state != &"active" or r.mode == &"legacy": continue
		var rate := 0
		match r.archetype:
			&"vegetables": rate = 36
			&"alfalfa",&"grain": rate = 9
		if rate == 0: continue
		for i in r.members: result[i] = int(result.get(i,0)) + rate
	return result
