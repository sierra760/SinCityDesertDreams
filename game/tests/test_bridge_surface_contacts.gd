# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Exact emitted physical surfaces agree with the shared road/rail traffic heights.
extends "res://tests/exploration/async_test_case.gd"
const Banks := preload("res://tests/test_bridge_approaches.gd")
var fixture: Node3D
func after_each() -> void:
	if is_instance_valid(fixture): fixture.free()
	await physics_frame
func test_imported_road_and_rail_surfaces_support_the_shared_traffic_profile() -> void:
	var total := 0
	for path: String in Banks.bridge_cities():
		total += await _check_city(path)
	check_gt(total,0,"the checked cities contain road or rail bridge spans")

func _check_city(path: String) -> int:
	var loaded := Sc2Import.load(path)
	check(loaded.ok,"read-only import of "+path)
	if not loaded.ok: return 0
	var city: City = loaded.city
	var encoded := var_to_bytes(SaveFormat.encode_city(city))
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var spans := 0
	var samples := 0
	var maximum_error := .0
	var off_pavement := 0
	var lowest_clearance := INF
	for start: Vector2i in graph._decks:
		var p: Dictionary = graph._decks[start]
		var code := city.building.atv(start)
		# Highway decks join highway approaches and are covered by the highway bridge tests.
		if p.index!=0 or code==92 or not (NetworkShapes.is_road_bridge(code) or NetworkShapes.is_rail_bridge(code)): continue
		spans += 1
		var rail := city.building.atv(start) in [90,91]
		var direction := Vector2i.RIGHT if p.ew else Vector2i.DOWN
		fixture = Node3D.new()
		root.add_child(fixture)
		var networks := CityNetworks3D.new()
		fixture.add_child(networks)
		networks._prepare_bridge_decks(city)
		var near: Dictionary = graph._approaches.get(start-direction,{})
		var far: Dictionary = graph._approaches.get(start+direction*int(p.length),{})
		var low := -int(near.length) if not near.is_empty() else 0
		var high := int(p.length)+(int(far.length) if not far.is_empty() else 0)
		var bounds := Rect2i(start+direction*low,Vector2i(high-low,1) if p.ew else Vector2i(1,high-low))
		networks._build_region(city,bounds)
		var world := CityTraversalWorld3D.new()
		fixture.add_child(world)
		world.rebuild(city,[],networks.physical_data(),1)
		var floors := {}
		for patch: Dictionary in networks.physical_patches_in(Rect2i(0, 0, City.WIDTH, City.HEIGHT)):
			if patch.role!=CityNetworks3D.PhysicalRole.FLOOR: continue
			if not floors.has(patch.cell): floors[patch.cell] = []
			floors[patch.cell].append(patch.triangle)
		await physics_frame
		for across: float in [.215,.35,.65,.785]:
			for step: int in (high-low)*16:
				var along := low+(step+.37)/16.0
				var pos := Vector2(start)+Vector2(direction)*along+(Vector2(0,across) if p.ew else Vector2(across,0))
				var cell := Vector2i(floori(pos.x),floori(pos.y))
				if CityNetworks3D.network_mask(city.building.atv(cell),NetworkShapes.Family.RAIL if rail else NetworkShapes.Family.ROAD) not in [5,10] and not _paved(floors.get(cell,[]),pos):
					off_pavement += 1
					continue
				var traffic := graph.point(cell,&"rail" if rail else &"road",pos-Vector2(cell))
				var hit := world.support_near(traffic,.004,.006,[])
				check(not hit.is_empty(),"bridge/land-approach contact %s %s"%[path.get_file(),cell])
				if hit.is_empty(): continue
				maximum_error = maxf(maximum_error,absf(hit.position.y-traffic.y))
				if along>=0 and along<p.length: lowest_clearance = minf(lowest_clearance,hit.position.y-CityGeometry3D.water_surface_height(city,cell))
				samples += 1
		fixture.free()
		await physics_frame
	check_lt(maximum_error,.0015,"%s: bridge and approach collision follows traffic height between tessellation vertices"%path.get_file())
	check_gt(lowest_clearance,.08,"%s: road/rail decks keep water clearance"%path.get_file())
	check_eq(var_to_bytes(SaveFormat.encode_city(city)),encoded,"%s: contact projection leaves the city's save bytes unchanged"%path.get_file())
	print("BRIDGE_CONTACTS %s spans=%d contacts=%d max_error=%.8f min_water_clearance=%.6f off_pavement=%d"%[path.get_file(),spans,samples,maximum_error,lowest_clearance,off_pavement])
	return spans

func _paved(triangles: Array, p: Vector2) -> bool:
	for triangle: PackedVector3Array in triangles:
		var a := Vector2(triangle[0].x,triangle[0].z)
		var ab := Vector2(triangle[1].x,triangle[1].z)-a
		var ac := Vector2(triangle[2].x,triangle[2].z)-a
		var area := ab.cross(ac)
		if absf(area)<.000000001: continue
		var ap := p-a
		var v := ap.cross(ac)/area
		var w := ab.cross(ap)/area
		if v>=-.00001 and w>=-.00001 and v+w<=1.00001: return true
	return false
