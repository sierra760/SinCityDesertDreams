# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Collision and actual catalog-car traversal of wet highway spans.
extends "res://tests/exploration/async_test_case.gd"
const Spans := preload("res://tests/test_highway_bridge_spans.gd")
const Driving := preload("res://tests/test_highway_access.gd")
var fixture: Node3D
func after_each() -> void:
	if is_instance_valid(fixture):fixture.free()
	await physics_frame

func _world(city: City, start: Vector2i, length: int, ew: bool) -> Dictionary:
	var graph := CityTrafficGraph.new();graph.bind_city(city)
	var d := Vector2i.RIGHT if ew else Vector2i.DOWN
	var near: Dictionary = graph._approaches.get(start-d,{})
	var far: Dictionary = graph._approaches.get(start+d*length,{})
	var low := -int(near.get("length",0))
	var high := length+int(far.get("length",0))
	# Extend only through real straight highway mouths. A neighboring 2x2
	# bend does not contain the straight lane-center endpoint used below.
	var mask := 10 if ew else 5
	var first := start+d*(low-1)
	var last := start+d*high
	if city.in_bounds(first.x,first.y) and CityNetworks3D.network_mask(city.building.atv(first),NetworkShapes.Family.HIGHWAY)==mask:low -= 1
	if city.in_bounds(last.x,last.y) and CityNetworks3D.network_mask(city.building.atv(last),NetworkShapes.Family.HIGHWAY)==mask:high += 1
	var bounds := Rect2i(start+d*low,Vector2i(high-low,2) if ew else Vector2i(2,high-low)).grow(1).intersection(Rect2i(0,0,City.WIDTH,City.HEIGHT))
	fixture = Node3D.new();root.add_child(fixture)
	var networks := CityNetworks3D.new();fixture.add_child(networks)
	networks._prepare_bridge_decks(city);networks._build_region(city,bounds)
	var world := CityTraversalWorld3D.new();fixture.add_child(world)
	var chunks: Array[Dictionary] = [CityGeometry3D.build_chunk(city,bounds)]
	world.rebuild(city,chunks,networks.physical_data(),1)
	await physics_frame
	return {"graph":graph,"world":world,"networks":networks,"low":low,"high":high}

func test_every_valle_highway_bridge_and_approach_has_matching_real_collision() -> void:
	var loaded := Sc2Import.load("res://assets/cities/Valle del Mar.sc2")
	check(loaded.ok,"actual imported city");if not loaded.ok:return
	var city: City = loaded.city
	var encoded := var_to_bytes(SaveFormat.encode_city(city))
	var contacts := 0;var missing := 0;var error := .0
	var no_exclusions: Array[RID] = []
	for span: Array in [[86,104,5,false],[8,112,7,false],[86,114,4,false],[14,122,18,true],[55,122,27,true],[92,122,12,true]]:
		var start := Vector2i(span[0],span[1]);var ew: bool = span[3]
		var d := Vector2i.RIGHT if ew else Vector2i.DOWN
		var transverse := Vector2i.DOWN if ew else Vector2i.RIGHT
		var context := await _world(city,start,span[2],ew)
		for lane: int in 2:
			for across: float in [.05,.28,.72,.95]:
				for step: int in (context.high-context.low)*16:
					var along: float = context.low+(step+.37)/16.0
					var p: Vector2 = Vector2(start+transverse*lane)+Vector2(d)*along+(Vector2(0,across) if ew else Vector2(across,0))
					var cell := Vector2i(floori(p.x),floori(p.y))
					if not city.in_bounds(cell.x,cell.y) or not NetworkShapes.is_highway(city.building.atv(cell)):continue
					var traffic: Vector3 = context.graph.point(cell,&"highway",p-Vector2(cell))
					var hit: Dictionary = context.world.support_near(traffic,.004,.006,no_exclusions)
					if hit.is_empty():missing += 1;continue
					contacts += 1;error=maxf(error,absf(hit.position.y-traffic.y))
		fixture.free();await physics_frame
	check_eq(missing,0,"all four highway lanes and pavement edges have physical floors")
	check_gt(contacts,12000,"real collision tested throughout all six spans and their dry approaches")
	check_lt(error,.0015,"physical floor and traffic agree between tessellation vertices")
	check_eq(var_to_bytes(SaveFormat.encode_city(city)),encoded,"collision projection preserves original city")
	print("VALLE_CONTACTS contacts=%d missing=%d maximum_error=%.8f"%[contacts,missing,error])

func test_catalog_car_drives_all_six_valle_crossings_in_their_directed_lanes() -> void:
	var city: City = Sc2Import.load("res://assets/cities/Valle del Mar.sc2").city
	var encoded := var_to_bytes(SaveFormat.encode_city(city))
	var journeys := 0;var maximum_pitch := .0
	for span: Array in [[86,104,5,false],[8,112,7,false],[86,114,4,false],[14,122,18,true],[55,122,27,true],[92,122,12,true]]:
		var start := Vector2i(span[0],span[1]);var ew: bool = span[3]
		var d := Vector2i.RIGHT if ew else Vector2i.DOWN
		var transverse := Vector2i.DOWN if ew else Vector2i.RIGHT
		var context := await _world(city,start,span[2],ew)
		for carriageway: int in 2:
			for lane: float in [.28,.72]:
				var route: Array[Vector3] = []
				for step: int in (context.high-context.low-1)*4+1:
					var p: Vector2 = Vector2(start+transverse*carriageway)+Vector2(d)*(context.low+.5+step*.25)+(Vector2(0,lane) if ew else Vector2(lane,0))
					var cell := Vector2i(floori(p.x),floori(p.y))
					route.append(context.graph.point(cell,&"highway",p-Vector2(cell)))
				if carriageway==(0 if ew else 1):route.reverse()
				var car := ExploreCar.new();fixture.add_child(car)
				check(car.configure_kind(&"car"),"real catalog highway car")
				car.bind(context.world);car.route_graph=context.graph;car.position=route[0]
				var forward := route[1]-route[0];car.rotation.y=atan2(-forward.x,-forward.z)
				var recoveries: Array[String] = []
				car.recovery_requested.connect(func(reason: String) -> void:recoveries.append(reason))
				await physics_frame
				for tick: int in 30:car.step(ExploreInputFrame.idle(),0,1.0/60.0);await physics_frame
				var driver := Driving.Driver.new();driver.car=car;driver.route=route;driver.throttle=.3
				driver.max_ticks=(context.high-context.low+3)*240
				driver.previous_up=car.collision_pose().basis.y.normalized();fixture.add_child(driver)
				await driver.completed;await process_frame
				journeys += 1;maximum_pitch=maxf(maximum_pitch,driver.maximum_pitch_step)
				check_eq(driver.route_index,route.size()-1,"car completes bank/span/bank journey")
				check_lt(car.position.distance_to(route[-1]),.12,"car reaches adjoining dry highway")
				check(recoveries.is_empty(),"no highway bridge recovery")
				check(car.has_support(),"destination has physical support")
				check_lt(driver.maximum_pitch_step,4.0,"bridge driving pitch changes gradually")
				print("VALLE_DRIVE start=%s carriageway=%d lane=%.2f waypoint=%d/%d pitch=%.4f recoveries=%s"%[start,carriageway,lane,driver.route_index,route.size()-1,driver.maximum_pitch_step,recoveries])
				driver.free();car.free();await physics_frame
		fixture.free();await physics_frame
	check_eq(journeys,24,"both lanes of both carriageways across every Valle bridge")
	check_eq(var_to_bytes(SaveFormat.encode_city(city)),encoded,"driving preserves original city")
	print("VALLE_DRIVES journeys=%d maximum_pitch=%.4f"%[journeys,maximum_pitch])
