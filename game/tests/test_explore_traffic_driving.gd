# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func test_catalog_selection_and_route_actor_contract() -> void:
	var hud := ExploreHUD.new()
	check(hud.has_signal("vehicle_requested"),"suspended HUD can request a vehicle")
	hud.free()
	var actor := ExploreRouteVehicle.new()
	root.add_child(actor)
	check(not actor.configure(&"plane",null,{}),"airplanes cannot be occupied")
	check(not actor.configure(&"ship",null,{}),"boats require a water route")
	check(not actor.configure(&"train",null,{}),"trains require a connected rail route")
	actor.free()
	await physics_frame

func test_car_variant_has_actual_collision_dimensions() -> void:
	var car := ExploreCar.new()
	root.add_child(car)
	check(car.configure_kind(&"bus"),"bus can be driven")
	check(car.vehicle_size().z > .28,"bus physical length is larger than car")
	check(not car.configure_kind(&"plane"),"car cannot become a plane")
	car.free()
	await physics_frame

func test_all_road_catalog_variants_keep_physical_dimensions() -> void:
	for kind: StringName in CityTrafficCatalog.vehicle_kinds():
		if CityTrafficCatalog.domain(kind)!=&"road": continue
		var car := ExploreCar.new()
		root.add_child(car)
		check(car.configure_kind(kind),"drivable road variant "+String(kind))
		check_eq(car.vehicle_size(),CityTrafficCatalog.dimensions(kind),"collider matches authored extent "+String(kind))
		check(car.vehicle_size().x>0 and car.vehicle_size().y>0 and car.vehicle_size().z>0)
		car.free()
	await physics_frame

func _rail_city() -> City:
	var city := flat_city()
	for x in range(20,28): city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
	return city

func test_train_motion_stays_on_connected_rail_and_stops_after_removal() -> void:
	var city := _rail_city()
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var points: Array[Vector3] = []
	for x in range(20,28): points.append(graph.point(Vector2i(x,20),&"rail"))
	var actor := ExploreRouteVehicle.new()
	root.add_child(actor)
	check(actor.configure(&"train",graph,{"points":points}))
	var initial := actor.global_position
	var frame := ExploreInputFrame.idle()
	frame.move = Vector2(1,-1)
	for i in 30: actor.step(frame,0,.1)
	check(actor.global_position.x>initial.x+.2,"train moves with throttle")
	check_between(actor.global_position.z,20.499,20.501,"steering cannot leave rails")
	frame.brake = true
	for i in 30: actor.step(frame,0,.1)
	check(absf(actor.speed())<.0001,"Space brake overrides throttle")
	var current := Vector2i(floori(actor.global_position.x),floori(actor.global_position.z))
	city.building.put(current.x,current.y,0)
	graph.refresh()
	var reports: Array[String] = []
	actor.recovery_requested.connect(func(reason: String) -> void: reports.append(reason))
	actor.step(frame,0,.1)
	check(not actor.has_support(),"removed rail cannot support train")
	check_eq(reports.size(),1,"removed route requests safe recovery")
	actor.free()
	await physics_frame

func test_boat_remains_water_bound_and_land_spawn_is_rejected() -> void:
	var city := flat_city()
	for y in range(20,24):
		for x in range(20,24):
			city.terrain.put(x,y,Terrain.SUBMERGED)
			city.set_heights(x,y,2,4)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var points: Array[Vector3] = [graph.point(Vector2i(21,21),&"water"),graph.point(Vector2i(22,21),&"water")]
	for kind: StringName in [&"ship",&"sailboat"]:
		var boat := ExploreRouteVehicle.new()
		root.add_child(boat)
		check(boat.configure(kind,graph,{"points":points}),"water admission "+String(kind))
		var frame := ExploreInputFrame.idle()
		frame.move = Vector2(0,-1)
		for i in 120: boat.step(frame,0,.1)
		check(boat.has_support(),"boat stops with all hull corners over water")
		check(boat.global_position.x<24 and boat.global_position.z<24)
		var land_points: Array[Vector3] = [Vector3(18.5,.35,18.5),Vector3(19.5,.35,18.5)]
		check(not boat.configure(kind,graph,{"points":land_points}),"boat cannot spawn on dry land")
		boat.free()
	await physics_frame

func test_moving_carriage_frame_applies_once_and_preserves_relative_pose() -> void:
	var walker := ExplorePedestrian.new()
	var carriage := Node3D.new()
	root.add_child(carriage)
	root.add_child(walker)
	carriage.position = Vector3(22,.4,22)
	walker.global_position = carriage.global_position+Vector3(.025,.025,.1)
	walker._support_frame = carriage
	walker._support_transform = carriage.global_transform
	var local := carriage.global_transform.affine_inverse()*walker.global_position
	for index in 180:
		carriage.position += Vector3(.003,.0001,.002)
		carriage.rotation.y += .004
		walker._apply_support_motion()
		var once := walker.global_transform
		walker._apply_support_motion()
		check(walker.global_transform.is_equal_approx(once),"same-frame transport never doubles")
	check((carriage.global_transform.affine_inverse()*walker.global_position).distance_to(local)<.0001,"turning/sloping frame retains local position without drift")
	walker.clear_support_frame()
	var before := walker.global_position
	carriage.position += Vector3.ONE
	walker._apply_support_motion()
	check_eq(walker.global_position,before,"alighting clears carriage transport")
	walker.free()
	carriage.free()
	await physics_frame

class RaisedTransitSupport extends Node3D:
	func support_for(feet: Vector3) -> Dictionary:
		return {"position":feet+Vector3.UP*.03,"normal":Vector3.UP}
	func contains(_feet: Vector3) -> bool: return true

func test_transit_support_honors_rise_and_drop_separately() -> void:
	var fixture: Node3D = preload("res://tests/exploration/traversal_fixture.gd").attach(self,flat_city())
	var walker := ExplorePedestrian.new()
	fixture.add_child(walker)
	walker.bind(fixture.get_node("traversal"))
	var provider := RaisedTransitSupport.new()
	fixture.add_child(provider)
	walker.transit_support = provider
	walker.global_position = Vector3(22.5,4*CityGeometry3D.HEIGHT+.002,20.5)
	await physics_frame
	var ordinary := walker._support_near(walker.global_position,.004,.048)
	check(not ordinary.is_empty())
	check(absf(float(ordinary.position.y)-4*CityGeometry3D.HEIGHT)<.003,"ordinary foot query cannot accept a tread above its rise budget")
	var step := walker._support_near(walker.global_position,.047,.003)
	check(absf(float(step.position.y)-walker.global_position.y-.03)<.0001,"explicit step-up query can accept that raised tread")
	fixture.free()
	await physics_frame
