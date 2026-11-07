# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## In Explore, ambient vehicles and pedestrians are solid: the player's car
## stops against them instead of passing through, ambient traffic stops short
## of the player's actors, their bodies match the authored models, and the
## walker's reach to a vehicle is measured to its body, so a building entrance
## beside it never takes precedence over getting in.
extends "res://tests/exploration/vehicle_selection_case.gd"

const Access := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")
const ROAD_Y := 20
const GROUND := 4*CityGeometry3D.HEIGHT
const RESORT := Vector2i(20,16)

class Driver extends Node:
	signal completed
	var session: CityExplorationController
	var ticks := 0
	var limit := 150
	var throttle := -1.0
	var check_tick: Callable
	func _physics_process(delta: float) -> void:
		session._sync_traffic_collision()
		var frame := ExploreInputFrame.idle()
		frame.move.y = throttle
		session.occupied.step(frame,0,delta)
		if check_tick.is_valid(): check_tick.call()
		ticks += 1
		if ticks >= limit:
			set_physics_process(false)
			completed.emit()

func _road_city() -> City:
	var city := flat_city()
	for x in range(18,34): city.building.put(x,ROAD_Y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	return city

func _ambient(kind: StringName, cell_x: int, t: float, stopped: bool = true) -> Dictionary:
	var type := &"pedestrian" if kind == &"pedestrian" else &"road"
	var record := {"id":700+cell_x,"type":type,"kind":kind,"domain":&"road","cell":Vector2i(cell_x,ROAD_Y),
		"previous":Vector2i(cell_x-1,ROAD_Y),"next":Vector2i(cell_x+1,ROAD_Y),"lane":0,"t":t,"variant":0,
		"turns":0,"side":1.0,"speed":.09 if kind == &"pedestrian" else 1.05,"length":CityTrafficCatalog.dimensions(kind).z,"stopped":stopped}
	view.traffic.actors.append(record)
	return record

func _park_session_vehicles_away() -> void:
	session.car.global_position += Vector3(0,0,6)
	session.helicopter.global_position += Vector3(0,0,-6)

## Centre pose and half extents of an ambient record's authored body.
func _ambient_box(record: Dictionary) -> Array:
	var bounds := CityTraffic3D.body_bounds(StringName(record.kind))
	return [view.traffic.actor_pose(record)*Transform3D(Basis.IDENTITY,bounds.get_center()),bounds.size*.5]

func _car_box(car: ExploreCar) -> Array:
	return [car.collision_pose(),car.vehicle_size()*.5]

## The session car, occupied and placed on the ambient record's lane `behind`
## tiles back, facing the same way.
func _player_car_behind(record: Dictionary, behind: float) -> ExploreCar:
	var car := session.car as ExploreCar
	check(car != null,"the session has a car")
	if car == null: return null
	var pose := view.traffic.actor_pose(record)
	var forward := -pose.basis.z
	car.apply_safe_pose(Transform3D(pose.basis,pose.origin-forward*behind+Vector3.UP*.002))
	session._occupy(car)
	return car

func test_player_car_stops_against_a_stopped_ambient_car() -> void:
	if not await _setup(_road_city(),Vector3(24.5,.5,20.5)): return
	_park_session_vehicles_away()
	var record := _ambient(&"car",29,.5)
	var car := _player_car_behind(record,1.2)
	if car == null: return
	await physics_frame
	session._sync_traffic_collision()
	check_eq(session._traffic_bodies.count(),1,"the nearby ambient car has a body")
	var target := _ambient_box(record)
	var overlaps: Array[int] = [0]
	var driver := Driver.new()
	driver.session = session
	driver.limit = 180
	driver.check_tick = func() -> void:
		var own := _car_box(car)
		if CityTraffic3D.boxes_overlap(own[0],own[1],target[0],target[1]): overlaps[0] += 1
	root.add_child(driver)
	await driver.completed
	driver.queue_free()
	check_eq(overlaps[0],0,"the player's car never enters the ambient car")
	var own := _car_box(car)
	var gap: float = (own[0].origin-target[0].origin).length()-own[1].z-target[1].z
	check_lt(gap,.03,"the player's car drove right up to the ambient car")
	check_gt(gap,-.001,"and stopped at its bumper")
	check_lt(absf(car.speed()),.05,"head-on contact takes the car's speed away")
	check(view.traffic.actor_pose(record).origin.is_equal_approx(target[0].origin-target[0].basis*CityTraffic3D.body_bounds(&"car").get_center()),"the ambient car was not moved")

func test_without_traffic_bodies_the_car_would_have_passed_through() -> void:
	# Control for the test above: with the bodies released the same drive
	# overlaps the ambient car, so the body is what stops it.
	if not await _setup(_road_city(),Vector3(24.5,.5,20.5)): return
	_park_session_vehicles_away()
	var record := _ambient(&"car",29,.5)
	var car := _player_car_behind(record,1.2)
	if car == null: return
	session._traffic_bodies.clear()
	session._traffic_bodies.traffic = null
	await physics_frame
	var target := _ambient_box(record)
	var overlaps: Array[int] = [0]
	var driver := Driver.new()
	driver.session = session
	driver.limit = 180
	driver.check_tick = func() -> void:
		var own := _car_box(car)
		if CityTraffic3D.boxes_overlap(own[0],own[1],target[0],target[1]): overlaps[0] += 1
	root.add_child(driver)
	await driver.completed
	driver.queue_free()
	check_gt(overlaps[0],0,"without a body the car drives into the ambient car")

func test_ambient_traffic_stops_short_of_the_players_car() -> void:
	if not await _setup(_road_city(),Vector3(24.5,.5,20.5)): return
	_park_session_vehicles_away()
	view.traffic.graph.refresh()
	var ahead := _ambient(&"car",29,.5)
	var car := _player_car_behind(ahead,0.0)
	if car == null: return
	view.traffic.actors.erase(ahead)
	await physics_frame
	var follower := _ambient(&"car",26,.2,false)
	session._sync_traffic_collision()
	var own := _car_box(car)
	var bounds := CityTraffic3D.body_bounds(&"car")
	var overlaps := 0
	for tick: int in 120:
		view.traffic._step_clock(CityTraffic3D.STEP,false)
		var box := _ambient_box(follower)
		if CityTraffic3D.boxes_overlap(box[0],box[1],own[0],own[1]): overlaps += 1
	check_eq(overlaps,0,"the ambient car never drives into the player's car")
	check(bool(follower.stopped),"it waits behind the player's car")
	var box := _ambient_box(follower)
	var gap: float = (box[0].origin-own[0].origin).length()-bounds.size.z*.5-own[1].z
	check_lt(gap,CityTraffic3D.YIELD_GAP+.04,"it closes up to a car length's gap")
	# Leaving Explore lifts the hold.
	session.leave()
	var held: Vector3 = view.traffic.actor_pose(follower).origin
	for tick: int in 30: view.traffic._step_clock(CityTraffic3D.STEP,false)
	check_gt(view.traffic.actor_pose(follower).origin.distance_to(held),.1,"without Explore obstacles traffic moves on")

func test_ambient_bodies_match_models_and_follow_claims() -> void:
	if not await _setup(_road_city(),Vector3(24.5,.5,20.5)): return
	_park_session_vehicles_away()
	var bus := _ambient(&"bus",25,.5)
	var person := _ambient(&"pedestrian",23,.5)
	var far := _ambient(&"truck",32,.5)
	session._sync_traffic_collision()
	var bodies: Dictionary = session._traffic_bodies.bodies()
	check(bodies.has("a:"+str(bus.id)),"a nearby bus has a body")
	check(bodies.has("a:"+str(person.id)),"a nearby pedestrian has a body")
	check(not bodies.has("a:"+str(far.id)),"distant traffic has none")
	if not bodies.has("a:"+str(bus.id)) or not bodies.has("a:"+str(person.id)): return
	var bus_body: StaticBody3D = bodies["a:"+str(bus.id)]
	var bus_shape := (bus_body.get_child(0) as CollisionShape3D).shape as BoxShape3D
	check(bus_shape != null and bus_shape.size.is_equal_approx(CityTrafficCatalog.dimensions(&"bus")),"the bus body is the bus model's size")
	check(bus_body.global_transform.is_equal_approx(view.traffic.actor_pose(bus)),"and stands at its displayed pose")
	check_eq(bus_body.collision_layer,ExploreActorProfile.ACTOR,"on the actor layer")
	var person_body: StaticBody3D = bodies["a:"+str(person.id)]
	var capsule := (person_body.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
	var size := CityTrafficCatalog.dimensions(&"pedestrian")
	check(capsule != null and is_equal_approx(capsule.height,size.y) and is_equal_approx(capsule.radius,minf(size.x,size.z)*.5),"a person is a model-sized capsule")
	await physics_frame
	# Nothing may be placed inside an ambient body.
	var inside := Transform3D(Basis.IDENTITY,view.traffic.actor_pose(bus).origin+Vector3.UP*.06)
	check(not session.traversal.has_clearance(inside,ExploreActorProfile.shape(0),[session.pedestrian.get_rid()]),"a walker cannot be placed inside the bus")
	# A claimed (boarded) record leaves traffic and so does its body.
	var claim := view.traffic.claim_vehicle(int(bus.id))
	check(not claim.is_empty(),"the bus can be claimed by id")
	session._sync_traffic_collision()
	check(not session._traffic_bodies.bodies().has("a:"+str(bus.id)),"a claimed vehicle's body is released")
	check_eq(bus_body.collision_layer,0,"its pooled body no longer collides")
	view.traffic.release_vehicle(claim,claim.position,float(claim.yaw))
	session.leave()
	check(not is_instance_valid(bus_body),"leaving Explore frees the bodies")

func test_entry_reach_is_measured_to_the_vehicle_body() -> void:
	if not await _setup(_road_city(),Vector3(24.5,.5,20.5)): return
	_park_session_vehicles_away()
	var bus := _ambient(&"bus",29,.5)
	var compact := _ambient(&"compact",25,.5)
	var reach := ExploreActorProfile.VEHICLE_REACH
	for record: Dictionary in [bus,compact]:
		var pose := view.traffic.actor_pose(record)
		var size := CityTrafficCatalog.dimensions(StringName(record.kind))
		var side := pose.basis.x.normalized()
		var forward := -pose.basis.z.normalized()
		var label := String(record.kind)
		# Beside the door, behind the rear and ahead of the nose: all judged
		# from the body's surface, so the bus is no harder to reach than the car.
		for offset: Vector3 in [side*(size.x*.5+ExploreActorProfile.WALK_RADIUS+reach-.01),forward*(size.z*.5+ExploreActorProfile.WALK_RADIUS+reach-.01),-forward*(size.z*.5+ExploreActorProfile.WALK_RADIUS+reach-.01)]:
			session.pedestrian.global_position = pose.origin+offset
			var found := view.traffic.nearest_vehicle_by_body(session.pedestrian.global_position,reach)
			check_eq(int(found.get("id",-1)),int(record.id),label+": just inside reach of its body")
		session.pedestrian.global_position = pose.origin+side*(size.x*.5+ExploreActorProfile.WALK_RADIUS+reach+.01)
		check(view.traffic.nearest_vehicle_by_body(session.pedestrian.global_position,reach).is_empty(),label+": just beyond reach")
		session.pedestrian.global_position = pose.origin+side*(size.x*.5+.05)+Vector3.UP*(size.y+.2)
		check(view.traffic.nearest_vehicle_by_body(session.pedestrian.global_position,reach).is_empty(),label+": not from a deck far above")
	# The old centre radius let a walker five metres beside a car get in.
	var pose := view.traffic.actor_pose(compact)
	session.pedestrian.global_position = pose.origin+pose.basis.x.normalized()*.35
	check(view.traffic.nearest_vehicle_by_body(session.pedestrian.global_position,reach).is_empty(),"0.35 tiles from the centre of a compact is out of reach")
	session.pedestrian.global_position = pose.origin+pose.basis.x.normalized()*.15
	check(session.request_interaction(),"the walker gets into the compact beside it")
	check(session.occupied == session.selected_vehicle and session.selected_vehicle is ExploreCar,"the borrowed compact is occupied")

func _resort_city() -> City:
	var city := _road_city()
	city.stamp_building(RESORT.x,RESORT.y,Buildings.ARCOLOGY_JUNCTION)
	return city

func test_a_vehicle_beside_a_resort_door_is_still_enterable() -> void:
	var city := _resort_city()
	if not await _setup(city,Vector3(22.5,.5,20.5)): return
	var threshold := Access.threshold(city,RESORT)
	session.helicopter.global_position += Vector3(0,0,-8)
	session.pedestrian.global_position = threshold.origin+Vector3.UP*.002
	session.car.global_position = Vector3(30.5,session.car.global_position.y,24.5)
	check(not Access.nearby(city,session.pedestrian.global_position).is_empty(),"the walker stands at the resort door")
	check_eq(_prompt(),"F to enter Silver Junction","with no vehicle near, the door is offered")
	# Park the session car right beside the walker at the door.
	var side := threshold.basis.x.normalized()
	session.car.global_transform = Transform3D(threshold.basis,threshold.origin+side*(ExploreActorProfile.geometry(1).size.x*.5+.08)+Vector3.UP*.002)
	session._publish_status()
	check_eq(_prompt(),"F to enter nearby vehicle","a vehicle in reach is offered before the door")
	check(session.request_interaction(),"F gets into the vehicle")
	check_eq(session.occupied,session.car,"the car is occupied, not the resort entered")
	check(not session.resort_service.is_inside(),"the walker did not go through the door")

func test_resort_door_reach_is_close_to_the_door() -> void:
	var city := _resort_city()
	var threshold := Access.threshold(city,RESORT)
	var side := threshold.basis.x.normalized()
	check(not Access.nearby(city,threshold.origin+side*(Access.REACH-.02)).is_empty(),"inside the door's reach")
	check(Access.nearby(city,threshold.origin+side*(Access.REACH+.02)).is_empty(),"the door is not offered from across the street")
	check_lt(Access.REACH,.5,"door reach is under eight metres")

func _prompt() -> String:
	var statuses: Array[Dictionary] = []
	var listener := func(value: Dictionary) -> void: statuses.append(value)
	session.status_changed.connect(listener)
	session._publish_status()
	session.status_changed.disconnect(listener)
	return String(statuses[-1].get("prompt","")) if not statuses.is_empty() else ""
