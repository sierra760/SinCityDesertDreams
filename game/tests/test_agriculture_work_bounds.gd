# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
## Work counts, not wall time: edits, lifecycle changes and herd routing must
## not scale with every parcel or navigation node, and must equal the full paths.
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")

class CountedStore extends AgriculturalParcels:
	var record_copies := 0
	var canonical_copies := 0
	func _capture_canonical_proof() -> void:
		canonical_copies += 1
		super._capture_canonical_proof()
	func records() -> Array[Dictionary]:
		record_copies += 1
		return super.records()

## Never trusts the canonical proof, so every update takes the whole-store path.
class FullStore extends AgriculturalParcels:
	func _canonical_matches() -> bool:
		return false

## Herd motion driven by the original exhaustive nearest-node scan.
class ReferenceMotion extends LivestockMotion:
	func _route(from: Vector2, to: Vector2, pen_index: int) -> PackedVector2Array:
		return exhaustive_route(from,to,pen_index)

	## The original exhaustive choice: nearest straight-reachable point, ties to
	## the earliest point in iteration order.
	func exhaustive_route(from: Vector2, to: Vector2, pen_index: int) -> PackedVector2Array:
		var catalog := AgricultureAssetCatalog.new()
		var pen: Dictionary = _profile["pens"][pen_index]
		var radius: float = _radius
		if catalog.navigation_segment(from,to,pen,radius): return PackedVector2Array([to])
		var graph: AStar2D = _graphs[pen_index]
		var a := -1;var b := -1;var da := INF;var db := INF
		for id: int in graph.get_point_ids():
			var p := graph.get_point_position(id)
			var d := from.distance_squared_to(p)
			if d < da and catalog.navigation_segment(from,p,pen,radius): a = id;da = d
			d = to.distance_squared_to(p)
			if d < db and catalog.navigation_segment(to,p,pen,radius): b = id;db = d
		if a < 0 or b < 0: return PackedVector2Array()
		var path := graph.get_point_path(a,b)
		if not path.is_empty(): path.append(to)
		return path

class CountingCatalog extends AgricultureAssetCatalog:
	var segments := 0
	func navigation_segment(from: Vector2, to: Vector2, pen: Dictionary, radius: float) -> bool:
		segments += 1
		return super.navigation_segment(from,to,pen,radius)


func pastures(store: AgriculturalParcels, count: int) -> City:
	var city := flat_city(1000000)
	city.agricultural_parcels = store
	var id := 1
	for gy in range(4,119,5):
		for gx in range(4,119,5):
			if id > count: break
			var members := F.square(4,Vector2i(gx,gy))
			F.zone(city,members)
			check_eq(store.put(city,F.record(id,members,&"cattle_range",&"active")),OK)
			id += 1
	return city


func layers(city: City) -> Array:
	return [city.agricultural_parcels.to_dict(),city.building.data,city.zone.data,city.flags.data,
		city.agricultural_parcels.get("_owners"),city.agricultural_parcels.get("_next_id")]


func test_cut_replays_only_changed_layouts() -> void:
	var count := AgriculturalParcelGeometry.LAYOUT_CACHE_LIMIT*2
	var city := pastures(AgriculturalParcels.new(),count)
	check_eq(city.agricultural_parcels.records().size(),count)
	var reference := city.duplicate_city()
	# Without proofs the same transaction replays every retained layout.
	reference.agricultural_parcels.set("_layout_proofs",{})
	var cell: int = city.agricultural_parcels.record(3).members[5]
	var before: int = AgriculturalParcelGeometry._compilations
	var change := city.agricultural_parcels.remove_cells(city,PackedInt32Array([cell]))
	var work: int = AgriculturalParcelGeometry._compilations-before
	check(change.ok,"edit accepted")
	check(work <= 4,"one cut must not recompile every retained pasture: %d" % work)
	var expected := reference.agricultural_parcels.remove_cells(reference,PackedInt32Array([cell]))
	check_eq(change,expected)
	check(layers(city) == layers(reference),"proof reuse publishes the full replay's result")
	check(AgriculturalParcels.validate(city,city.agricultural_parcels.records()).ok)
	# A retained record's land is still checked even though its layout is proven.
	var other: int = city.agricultural_parcels.record(9).members[0]
	city.zone.data[other] = Zones.RES_LOW
	var snapshot := layers(city)
	var refused := city.agricultural_parcels.remove_cells(city,PackedInt32Array([city.agricultural_parcels.record(12).members[0]]))
	check(not refused.ok,"invalid retained land refuses the edit")
	check_eq(refused.error,"Invalid parcel density.")
	check(layers(city) == snapshot,"refusal commits nothing")


func test_state_changes_avoid_whole_store_work() -> void:
	var count := 60
	var counted := CountedStore.new()
	var city := pastures(counted,count)
	var full := pastures(FullStore.new(),count)
	var events: Array = []
	var full_events: Array = []
	counted.changed.connect(func(change: Dictionary) -> void: events.append(change))
	full.agricultural_parcels.changed.connect(func(change: Dictionary) -> void: full_events.append(change))
	counted.record_copies = 0
	counted.canonical_copies = 0
	var initial: int = counted.get("_data_validations")
	for id in range(1,count+1):
		for target in [city,full]:
			var r: Dictionary = target.agricultural_parcels.record(id)
			r.state = [&"dormant",&"prepared",&"active"][id%3]
			r.failed_months = id%4
			r.last_month = id
			var store: AgriculturalParcels = target.agricultural_parcels
			check_eq(store.put_lifecycle(target,r) if target == city else store.put(target,r),OK)
	check_eq(counted.record_copies,0,"state changes must avoid whole-store copies")
	check_eq(counted.canonical_copies,0,"state changes must not re-encode the whole canonical proof")
	check(counted.get("_data_validations")-initial <= count*2,"each change validates only its own record")
	check(layers(city) == layers(full),"lifecycle updates equal the whole-store transaction")
	check_eq(events,full_events)
	# A raw edit elsewhere still forces the full transaction and its refusal.
	city.building.data[counted.record(5).members[0]] = Buildings.NONE
	var r := counted.record(6)
	r.state = &"dormant"
	check_eq(counted.put_lifecycle(city,r),ERR_INVALID_DATA)
	check(AgriculturalParcels.decode(full.agricultural_parcels.to_dict(),full).ok)


func test_concave_routes_match_exhaustive_scan_with_bounded_tests() -> void:
	var members := PackedInt32Array()
	for y in range(20,28):
		for x in range(20,28):
			if x >= 22 and y >= 22 and y < 26: continue
			members.append(y*128+x)
	var city := flat_city()
	F.zone(city,members)
	check_eq(city.agricultural_parcels.put(city,F.record(1,members,&"cattle_range",&"active")),OK)
	var profile: Dictionary = AgriculturalParcelGeometry.plan(city.agricultural_parcels.record(1)).profile
	check(not profile.is_empty(),"concave pasture is stocked")
	if profile.is_empty(): return
	var motion := LivestockMotion.new()
	var catalog := CountingCatalog.new()
	motion._catalog = catalog
	motion.configure(profile,7)
	var exhaustive := ReferenceMotion.new()
	exhaustive.configure(profile,7)
	var graph: AStar2D = motion._graphs[0]
	var nodes := graph.get_point_count()
	check_gt(nodes,1000)
	var bounds: Array = profile.pens[0].navigation_bounds
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var mismatches := 0
	var detours := 0
	var worst := 0
	for k in 120:
		var from := Vector2(rng.randf_range(bounds[0],bounds[2]),rng.randf_range(bounds[1],bounds[3]))
		var to := graph.get_point_position(rng.randi_range(0,nodes-1))
		# Lattice midpoints have several equally distant nodes: exercise ties.
		if k%3 == 0: from = from.snapped(Vector2(2,2))+Vector2(1,1)
		catalog.segments = 0
		var path := motion._route(from,to,0)
		worst = maxi(worst,catalog.segments)
		if path != exhaustive.exhaustive_route(from,to,0): mismatches += 1
		if path.size() > 1: detours += 1
	check_eq(mismatches,0,"identical route choices")
	check_gt(detours,10,"fixture exercises routes around the concave corner")
	check(worst < nodes/8,"route choice tests only nearby nodes: %d of %d" % [worst,nodes])
	# Identical choices give identical herd motion, including player avoidance.
	var actual := LivestockMotion.new()
	actual.configure(profile,7)
	var reference := ReferenceMotion.new()
	reference.configure(profile,7)
	for frame in 900:
		var player := Vector3.INF
		if frame > 300 and frame < 600: player = Vector3(lerpf(bounds[0],bounds[2],frame/900.0),0,(bounds[1]+bounds[3])*.5)
		actual.advance(1.0/60.0,player)
		reference.advance(1.0/60.0,player)
	check_eq(var_to_bytes(actual.states()),var_to_bytes(reference.states()),"identical herd motion")
