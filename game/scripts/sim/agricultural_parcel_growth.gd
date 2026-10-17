# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
class_name AgriculturalParcelGrowth
extends RefCounted
## One phase mask, then bounded local frontiers. No component-wide flood fills.
const Params := preload("res://scripts/sim/data/agricultural_parcel_params.gd")
const STEPS := [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
var _city: City
var _eligible := PackedByteArray()
var _heights := PackedInt32Array()
var eligible_cells := 0

func prepare(city: City, fires: Array = []) -> void:
	_city = city
	_eligible.resize(City.WIDTH*City.HEIGHT)
	_eligible.fill(0)
	_heights.resize(_eligible.size())
	var burning := {}
	for p in fires: burning[p] = true
	eligible_cells = 0
	eligible_cells = _eligible.size()
	var zn := city.zone.data
	var bld := city.building.data
	for i in _eligible.size():
		# Heights are read only for eligible cells (_available/candidate).
		if (zn[i] & Zones.KIND_MASK) != Zones.AGR_LOW or bld[i] != Buildings.NONE: continue
		var p := AgriculturalParcels.tile(i)
		if p.x < 2 or p.y < 2 or p.x >= 126 or p.y >= 126: continue
		if city.agricultural_parcels.id_at(p) != 0 or burning.has(p): continue
		if city.is_water(p.x,p.y) or not city.is_flat(p.x,p.y) or city.flood_overlay.has(p): continue
		if city.flags.has_bits(p.x,p.y,TileFlags.LANDMARK): continue
		_heights[i] = city.ground_height(p.x,p.y)
		_eligible[i] = 1

func eligible(at: Vector2i) -> bool:
	return _city != null and _city.in_bounds(at.x,at.y) and _eligible[AgriculturalParcels.cell(at)] != 0 and _city.agricultural_parcels.id_at(at) == 0

## Reserve detached extension acreage while other preparations use this phase mask.
func reserve(members: PackedInt32Array) -> void:
	for i in members: _eligible[i] = 0

func _available(i: int, height: int) -> bool:
	return i >= 0 and i < _eligible.size() and _eligible[i] != 0 and _heights[i] == height and _city.agricultural_parcels.id_at(AgriculturalParcels.tile(i)) == 0

static func _target(rng: SimRng) -> int:
	var band := rng.below(100)
	if band < 15: return rng.range_int(1,4)
	if band < 50: return rng.range_int(5,16)
	if band < 85: return rng.range_int(17,36)
	return rng.range_int(37,64)

func candidate(city: City, start: Vector2i, archetype: StringName, target: int, rng: SimRng) -> Dictionary:
	if _city != city: prepare(city)
	var result := {"ok":false,"members":PackedInt32Array(),"evaluations":0,"admissions":0,"mode":&"generated","target_area":0}
	if not eligible(start) or not Params.ACTIVE_CODES.has(archetype): return result
	var square_attempt := rng.below(5) == 0
	if target <= 0: target = _target(rng)
	target = clampi(target,4 if Params.stock_rate(archetype)>0 else 1,Params.MAX_AREA)
	result.target_area = target
	var first := AgriculturalParcels.cell(start)
	var height := _heights[first]
	if square_attempt:
		var side: int = AgricultureParams.ROSTER[archetype][0]
		var square := PackedInt32Array()
		for y in range(start.y,start.y+side):
			for x in range(start.x,start.x+side):
				if x < 128 and y < 128 and _available(y*128+x,height): square.append(y*128+x)
		if square.size() == side*side:
			result.members = square
			result.mode = &"square"
			result.target_area = maxi(target,square.size())
			result.admissions = square.size()
			result.ok = true
			return result
	var grown := _frontier(PackedInt32Array([first]),target,height,rng)
	result.merge(grown,true)
	result.admissions += 1
	result.ok = result.members.size() >= (4 if Params.stock_rate(archetype)>0 else 1)
	return result

## Existing members and modules are untouched; new acreage is only a proposal.
func extension(city: City, record: Dictionary, rng: SimRng) -> Dictionary:
	if _city != city: prepare(city)
	var result := {"ok":false,"members":record.members.duplicate(),"evaluations":0,"admissions":0,"record":record.duplicate(true)}
	if record.mode == &"legacy" or record.members.size() >= record.target_area: return result
	var grown := _frontier(record.members,record.target_area,record.height,rng)
	result.merge(grown,true)
	if grown.members.size() <= record.members.size(): return result
	var proposed: Dictionary = record.duplicate(true)
	proposed.members = grown.members
	proposed.mode = &"generated"
	proposed.legacy_code = 0
	proposed.stock_units = Params.stock_units(proposed.archetype,proposed.members,record.stock_units)
	var layout := AgriculturalParcelGeometry.plan(proposed,record.modules)
	if not layout.ok and record.state == &"active": return result
	proposed.modules = layout.modules
	result.record = proposed
	result.ok = true
	return result

func _frontier(initial: PackedInt32Array, target: int, height: int, rng: SimRng) -> Dictionary:
	var owned := {}
	var frontier := {}
	var members := initial.duplicate()
	var box := AgriculturalParcels.bounds(members)
	var evaluations := 0
	# Each admitted/retained cell contributes exactly four neighbor inspections.
	# Frontier scores are incremented from those edges, never recomputed by scans.
	var cursor := 0
	while true:
		while cursor < members.size():
			var p := AgriculturalParcels.tile(members[cursor])
			owned[members[cursor]] = true
			cursor += 1
			for step: Vector2i in STEPS:
				evaluations += 1
				var q := p+step
				if not _city.in_bounds(q.x,q.y): continue
				var index := AgriculturalParcels.cell(q)
				if index in initial or owned.has(index) or not _available(index,height): continue
				frontier[index] = int(frontier.get(index,0))+1
		if members.size() >= target or frontier.is_empty(): break
		var choices := frontier.keys()
		choices.sort()
		var weights := 0
		for i in choices:
			var enlarged := box.expand(AgriculturalParcels.tile(i))
			if enlarged.size.x > Params.MAX_SPAN or enlarged.size.y > Params.MAX_SPAN:
				frontier.erase(i)
			else: weights += int(frontier[i])*int(frontier[i])
		if weights == 0: break
		var draw := rng.below(weights)
		for i in choices:
			if not frontier.has(i): continue
			draw -= int(frontier[i])*int(frontier[i])
			if draw < 0:
				members.append(i)
				frontier.erase(i)
				box = box.expand(AgriculturalParcels.tile(i))
				break
	members.sort()
	return {"members":members,"evaluations":evaluations,"admissions":members.size()-initial.size()}
