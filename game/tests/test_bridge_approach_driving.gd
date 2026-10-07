# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Catalog car journeys over rendered/physical bridge surfaces.
extends "res://tests/exploration/async_test_case.gd"
const Banks := preload("res://tests/test_bridge_approaches.gd")
const Driving := preload("res://tests/test_highway_access.gd")
var fixture: Node3D
var journey_count := 0
var maximum_pitch := .0

func after_each() -> void:
	if is_instance_valid(fixture): fixture.free()
	await physics_frame

func _span(city: City, graph: CityTrafficGraph, start: Vector2i, length: int, ew: bool) -> void:
	fixture = Node3D.new()
	root.add_child(fixture)
	var direction := Vector2i.RIGHT if ew else Vector2i.DOWN
	var near: Dictionary = graph._approaches.get(start-direction,{})
	var far: Dictionary = graph._approaches.get(start+direction*length,{})
	var low := -float(near.length)+.5 if not near.is_empty() else -.5
	var high := length+float(far.length)-.5 if not far.is_empty() else length+.5
	var axis_mask := 10 if ew else 5
	# Bound the straight crossing to connected pavement. Imported bends and
	# portals can occupy the next cell without offering a straight road mouth.
	var first := start+direction*floori(low)
	var last := start+direction*floori(high)
	var first_mask := CityNetworks3D.network_mask(city.building.atv(first),NetworkShapes.Family.ROAD)
	var last_mask := CityNetworks3D.network_mask(city.building.atv(last),NetworkShapes.Family.ROAD)
	if (first_mask&axis_mask)!=axis_mask:
		low = floorf(low)+.75
	elif first-direction in graph.neighbors(first,&"road") and (CityNetworks3D.network_mask(city.building.atv(first-direction),NetworkShapes.Family.ROAD)&axis_mask)==axis_mask:
		low -= 1
	if (last_mask&axis_mask)!=axis_mask:
		high = floorf(high)+.25
	elif last+direction in graph.neighbors(last,&"road") and (CityNetworks3D.network_mask(city.building.atv(last+direction),NetworkShapes.Family.ROAD)&axis_mask)==axis_mask:
		high += 1
	var width := ceili(high)-floori(low)+1
	var bounds := Rect2i(start+direction*floori(low),Vector2i(width,1) if ew else Vector2i(1,width)).grow(1)
	var networks := CityNetworks3D.new()
	fixture.add_child(networks)
	networks._prepare_bridge_decks(city)
	networks._build_region(city,bounds)
	var world := CityTraversalWorld3D.new()
	fixture.add_child(world)
	var chunks: Array[Dictionary] = [CityGeometry3D.build_chunk(city,bounds)]
	world.rebuild(city,chunks,networks.physical_data(),1)
	await physics_frame
	# Both actual road lanes are checked; there are no stand-in landing pads.
	for reverse: bool in [false,true]:
		var route: Array[Vector3] = []
		var across := .65 if reverse else .35
		for step: int in roundi((high-low)*4)+1:
			var p := Vector2(start)+Vector2(direction)*(low+step*.25)
			p += Vector2(0,across) if ew else Vector2(across,0)
			var cell := Vector2i(floori(p.x),floori(p.y))
			route.append(graph.point(cell,&"road",p-Vector2(cell)))
		if reverse: route.reverse()
		var car := ExploreCar.new()
		fixture.add_child(car)
		check(car.configure_kind(&"car"),"catalog car collision and visual")
		car.bind(world)
		car.route_graph = graph
		car.position = route[0]
		var forward := route[1]-route[0]
		car.rotation.y = atan2(-forward.x,-forward.z)
		var recoveries: Array[String] = []
		car.recovery_requested.connect(func(reason: String) -> void: recoveries.append(reason))
		await physics_frame
		# Let the real chassis settle onto its initial floor before measuring
		# driving pitch. This does not move or recover the car along the route.
		for tick: int in 30:
			car.step(ExploreInputFrame.idle(),0,1.0/60.0)
			await physics_frame
		var driver := Driving.Driver.new()
		driver.car = car
		driver.previous_up = car.collision_pose().basis.y.normalized()
		driver.route = route
		driver.throttle = .3
		driver.max_ticks = roundi((high-low+3)*220)
		fixture.add_child(driver)
		await driver.completed
		await process_frame
		journey_count += 1
		maximum_pitch = maxf(maximum_pitch,driver.maximum_pitch_step)
		print("BRIDGE_DRIVE start=%s length=%d ew=%s reverse=%s waypoint=%d/%d ticks=%d pitch=%.4f feet=%s target=%s recovery=%s"%[start,length,ew,reverse,driver.route_index,route.size()-1,driver.ticks,driver.maximum_pitch_step,car.position,route[-1],recoveries])
		check_eq(driver.route_index,route.size()-1,"completes actual bank/span/bank journey")
		check(car.position.distance_to(route[-1])<.12,"finishes on actual adjoining road")
		check(recoveries.is_empty(),"bridge journey needs no recovery")
		check(car.has_support(),"destination has real physical support")
		check_lt(driver.maximum_pitch_step,4.0,"chassis follows continuous bridge grade")
		driver.free()
		car.free()
		await physics_frame
	fixture.free()
	await physics_frame

func test_car_crosses_short_and_long_sloping_bank_bridges_on_both_axes() -> void:
	for ew: bool in [false,true]:
		for length: int in [1,2,6]:
			var city := Banks.bank_city(ew,length)
			var graph := CityTrafficGraph.new()
			graph.bind_city(city)
			await _span(city,graph,Vector2i(22,22),length,ew)
	check_eq(journey_count,12,"both directions through all portable bank cases")

# Driving every span of a whole city is slow, so this runs only when
# BRIDGE_APPROACH_CITY names a city file to drive.
func test_car_crosses_every_road_bridge_of_a_city_in_both_directions() -> void:
	var path := OS.get_environment("BRIDGE_APPROACH_CITY")
	if path.is_empty():
		print("BRIDGE_APPROACH_CITY not set; skipping whole-city bridge drive")
		return
	var loaded := Sc2Import.load(path)
	check(loaded.ok,"read-only import of "+path)
	if not loaded.ok: return
	var city: City = loaded.city
	var before := var_to_bytes(SaveFormat.encode_city(city))
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var before_count := journey_count
	var spans := 0
	for start: Vector2i in graph._decks:
		var p: Dictionary = graph._decks[start]
		if p.index!=0 or not NetworkShapes.is_road_bridge(city.building.atv(start)): continue
		spans += 1
		await _span(city,graph,start,p.length,p.ew)
	check_gt(spans,0,"the city has road bridge spans")
	check_eq(journey_count-before_count,2*spans,"both directions through every road span")
	check_eq(var_to_bytes(SaveFormat.encode_city(city)),before,"driving leaves the city save bytes unchanged")
	print("ALL_BRIDGE_DRIVES journeys=%d maximum_pitch_step=%.4f"%[journey_count,maximum_pitch])
