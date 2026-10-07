# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Rail and subway station names: a custom name when the player gave one,
## otherwise an automatic name from the streets the station opens onto.
## Allocation is deterministic; renderers only read the published names.
class_name StationNameResolver
extends RefCounted
const Access := preload("res://scripts/core/naming/station_street_access.gd")
const Codec := preload("res://scripts/core/naming/street_naming_codec.gd")

static func _fallback(anchor: Vector2i, subway: bool) -> String:
	return ("Subway" if subway else "Rail")+" %d,%d" % [anchor.x,anchor.y]

static func display_name(city: City, anchor: Vector2i, subway: bool) -> String:
	var custom := String(city.facilities.get(anchor,{}).get("name",""))
	if not custom.is_empty(): return custom
	return String(city.street_naming.station_auto.get(anchor,{}).get("display_name",_fallback(anchor,subway)))

## &"custom" when the player named the station, otherwise &"automatic" (a
## station still showing its coordinate fallback counts as automatic).
static func name_mode(city: City, anchor: Vector2i) -> StringName:
	if not String(city.facilities.get(anchor,{}).get("name","")).is_empty(): return &"custom"
	return &"automatic"

static func _comparison(text: String) -> String:
	# Generated and legacy custom names use the street whitespace/case rules,
	# with no player-input length limit on complete station titles.
	return String(Codec._normalized(text,2147483647).comparison)

static func _before(a: Vector2i,b: Vector2i) -> bool:
	return a.y<b.y or (a.y==b.y and a.x<b.x)

static func _stations(city: City) -> Array[Vector2i]:
	var anchors: Array[Vector2i] = []
	# Station cells in row-major order, found natively.
	var codes := city.building.data
	var found := PackedInt32Array()
	for station_code: int in [Buildings.RAIL_STATION,Buildings.SUBWAY_STATION]:
		var at := codes.find(station_code)
		while at >= 0:
			found.append(at)
			at = codes.find(station_code,at+1)
	found.sort()
	for at: int in found:
		var anchor := Vector2i(at % City.WIDTH,at / City.WIDTH)
		if city.anchor_of(anchor.x,anchor.y)!=anchor: continue
		anchors.append(anchor)
	return anchors

static func _candidate(city: City, topology: StreetTopology, anchor: Vector2i, metadata: Dictionary) -> Dictionary:
	var neighbors := Access.neighbors(city,topology,anchor,metadata)
	var junctions: Dictionary = {}
	for approach: Dictionary in neighbors:
		if int(approach.degree)<3: continue
		if not junctions.has(approach.cell): junctions[approach.cell] = []
		junctions[approach.cell].append(approach)
	var eligible: Array[Dictionary] = []
	for cell: Vector2i in junctions:
		var approaches: Array = junctions[cell]
		approaches.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			if a.approach_distance!=b.approach_distance: return a.approach_distance<b.approach_distance
			return a.direction<b.direction if a.direction!=b.direction else a.key<b.key)
		var ids: Array[int] = []
		for approach: Dictionary in approaches:
			if not ids.has(approach.street_id): ids.append(approach.street_id)
			if ids.size()==2: break
		if ids.size()==2:
			ids.sort()
			eligible.append({"cell":cell,"distance":approaches[0].junction_distance,"ids":ids})
	var ids: Array[int] = []
	if not eligible.is_empty():
		eligible.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.distance<b.distance if a.distance!=b.distance else _before(a.cell,b.cell))
		ids.assign(eligible[0].ids)
	elif not neighbors.is_empty():
		neighbors.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.distance<b.distance if a.distance!=b.distance else a.key<b.key)
		ids.append(neighbors[0].street_id)
	var names := PackedStringArray()
	for id: int in ids: names.append(metadata.streets[id])
	return {"ids":ids,"base":" & ".join(names)}

static func _record(candidate: Dictionary, suffix: int) -> Dictionary:
	return {"source_street_ids":candidate.ids.duplicate(),"base_name":candidate.base,"suffix":suffix,"display_name":candidate.base if suffix==0 else candidate.base+" "+str(suffix)}

static func reconcile(city: City, topology: StreetTopology, metadata: Dictionary) -> Dictionary:
	# Station access samples the same ground repeatedly; one read-only sampling
	# scope spans this synchronous call (an open scope for this city is reused).
	var sampling: Dictionary = {}
	if city != null and not CityGeometry3D.is_sampling_ground(city):
		sampling = CityGeometry3D.begin_ground_sampling(city)
	var result := _reconcile(city,topology,metadata)
	if not sampling.is_empty(): CityGeometry3D.end_ground_sampling(sampling)
	return result

static func _reconcile(city: City, topology: StreetTopology, metadata: Dictionary) -> Dictionary:
	if city==null or topology==null or not topology.is_bound_to(city): return {"ok":false,"error":"Station naming requires the current city topology.","station_auto":{},"changed_anchors":[]}
	var anchors := _stations(city)
	var candidates: Dictionary = {}
	var reserved: Dictionary = {}
	var automatic: Dictionary = {}
	for anchor: Vector2i in anchors:
		var candidate := _candidate(city,topology,anchor,metadata)
		var custom := String(city.facilities.get(anchor,{}).get("name",""))
		if not custom.is_empty(): reserved[_comparison(custom)] = true
		elif candidate.ids.is_empty(): reserved[_comparison(_fallback(anchor,city.building.atv(anchor)==Buildings.SUBWAY_STATION))] = true
		else: candidates[anchor] = candidate
	# Reserve surviving source identities first, including spelling updates.
	for anchor: Vector2i in anchors:
		if not candidates.has(anchor) or not metadata.station_auto.has(anchor): continue
		var prior: Dictionary = metadata.station_auto[anchor]
		if prior.source_street_ids!=candidates[anchor].ids: continue
		var current := _record(candidates[anchor],int(prior.suffix))
		var key := _comparison(current.display_name)
		if not reserved.has(key): automatic[anchor] = current; reserved[key] = true
	for anchor: Vector2i in anchors:
		if not candidates.has(anchor) or automatic.has(anchor): continue
		var suffix := 0
		var current := _record(candidates[anchor],suffix)
		while reserved.has(_comparison(current.display_name)):
			suffix = 2 if suffix==0 else suffix+1
			current = _record(candidates[anchor],suffix)
		automatic[anchor] = current
		reserved[_comparison(current.display_name)] = true
	var changed: Array[Vector2i] = []
	for anchor: Vector2i in metadata.station_auto:
		if metadata.station_auto[anchor]!=automatic.get(anchor): changed.append(anchor)
	for anchor: Vector2i in automatic:
		if automatic[anchor]!=metadata.station_auto.get(anchor) and not changed.has(anchor): changed.append(anchor)
	changed.sort_custom(_before)
	return {"ok":true,"error":"","station_auto":automatic,"changed_anchors":changed}
