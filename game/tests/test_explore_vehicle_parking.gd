# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A vehicle in a valid spot stays exactly where it is when the walker gets in
## or out; only vehicles with no valid pose are placed on a route.
extends "res://tests/exploration/vehicle_selection_case.gd"

const ROAD_Y := 20

func _road_city() -> City:
	var city := flat_city()
	for x in range(18,34): city.building.put(x,ROAD_Y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	return city

## A stopped ambient car part way along an eastbound lane, away from cell centers.
func _ambient_car(cell_x: int, t: float) -> Dictionary:
	var record := {"id":900+cell_x,"type":&"road","kind":&"car","domain":&"road","cell":Vector2i(cell_x,ROAD_Y),
		"previous":Vector2i(cell_x-1,ROAD_Y),"next":Vector2i(cell_x+1,ROAD_Y),"lane":0,"t":t,"variant":0,
		"turns":0,"side":1.0,"speed":1.05,"length":CityTrafficCatalog.dimensions(&"car").z,"stopped":true}
	view.traffic.actors.append(record)
	return record

func _park_session_vehicles_away() -> void:
	session.car.global_position += Vector3(0,0,6)
	session.helicopter.global_position += Vector3(0,0,-6)

func _yaw_gap(a: float, b: float) -> float: return absf(angle_difference(a,b))

func test_borrowed_car_keeps_its_pose_on_entry_and_exit() -> void:
	if not await _setup(_road_city(),Vector3(26.5,.5,20.5)): return
	_park_session_vehicles_away()
	var record := _ambient_car(27,.3)
	var ambient := view.traffic.actor_pose(record)
	session.pedestrian.global_position = ambient.origin+Vector3(0,0,.2)
	check(session.request_interaction(),"walker boards the nearby ambient car")
	var car: CharacterBody3D = session.occupied
	check(car is ExploreCar and car == session.selected_vehicle,"the borrowed car is occupied")
	if not car is ExploreCar: return
	check_lt(Vector2(car.global_position.x-ambient.origin.x,car.global_position.z-ambient.origin.z).length(),.005,
		"boarding keeps the car's lane position instead of a road-cell center")
	check_lt(_yaw_gap(car.global_basis.get_euler().y,ambient.basis.get_euler().y),.01,"boarding keeps the car's heading")
	check(session._valid_actor(car),"the kept pose is a valid driving pose")
	await physics_frame
	car.step(ExploreInputFrame.idle(),0,.016)
	var parked := car.global_transform
	check(session.request_interaction(),"stopped borrowed car exits safely")
	check_eq(session.occupied,session.pedestrian)
	check(is_instance_valid(car) and session.selected_vehicle == car,"the borrowed car stays parked after exit")
	if not is_instance_valid(car): return
	check_eq(car.global_transform,parked,"exit leaves the car exactly where it stopped")
	check(view.traffic._claims.has(record.id),"the parked car stays held from ambient traffic")
	check_eq(float(record.t),.3,"the ambient copy has not been snapped onto a lane")
	check(session.request_interaction(),"walker gets back into the parked car")
	check_eq(session.occupied,car,"re-entry uses the same parked car")
	check_eq(car.global_transform,parked,"re-entry does not move the car")
	await physics_frame
	car.step(ExploreInputFrame.idle(),0,.016)
	check(session.request_interaction(),"second exit is also safe")
	session.leave()
	check(view.traffic._claims.is_empty(),"ending Explore hands the car back to traffic")
	var returned := view.traffic.actor_pose(record)
	check_lt(Vector2(returned.origin.x-parked.origin.x,returned.origin.z-parked.origin.z).length(),.01,
		"the traffic car resumes from where it was parked")
	check_gt((-returned.basis.z).dot(-parked.basis.z),.99,"and keeps facing the same way")

func test_helicopter_keeps_and_another_car_returns_the_parked_borrowed_car() -> void:
	if not await _setup(_road_city(),Vector3(26.5,.5,20.5)): return
	_park_session_vehicles_away()
	var record := _ambient_car(27,.3)
	session.pedestrian.global_position = view.traffic.actor_pose(record).origin+Vector3(0,0,.2)
	check(session.request_interaction())
	var borrowed: CharacterBody3D = session.occupied
	await physics_frame
	borrowed.step(ExploreInputFrame.idle(),0,.016)
	check(session.request_interaction())
	var parked := borrowed.global_transform
	# Flying the session helicopter leaves the car where it was parked.
	session.helicopter.global_position = session.pedestrian.global_position+Vector3(-.5,0,0)
	var support := session.traversal.support_near(session.helicopter.global_position,.1,.2,[session.helicopter.get_rid()])
	if not support.is_empty(): session.helicopter.global_position = support.position+Vector3.UP*.002
	session.suspend()
	check(session.select_vehicle(&"helicopter"),"helicopter is still selectable")
	check_eq(session.occupied,session.helicopter)
	check(is_instance_valid(borrowed) and borrowed.global_transform == parked,"the borrowed car stays parked in place")
	check(view.traffic._claims.has(record.id),"and stays held from traffic")
	await physics_frame
	session.helicopter.step(ExploreInputFrame.idle(),0,.016)
	check(session.request_interaction(),"landed helicopter exits")
	check(is_instance_valid(borrowed) and borrowed.global_transform == parked,"leaving the helicopter does not move the car")
	check(view.traffic._claims.has(record.id))
	# Choosing another car hands the borrowed one back instead of duplicating it.
	session.pedestrian.global_position = parked.origin+Vector3(0,0,.2)
	session.suspend()
	check(session.select_vehicle(&"bus"),"another road vehicle is selectable")
	check(not is_instance_valid(borrowed),"the parked borrowed car is not duplicated")
	check(not view.traffic._claims.has(record.id),"its ambient record rejoins traffic")
	session.leave()

func test_blocked_claimed_pose_falls_back_to_the_route() -> void:
	if not await _setup(_road_city(),Vector3(26.5,.5,20.5)): return
	_park_session_vehicles_away()
	var record := _ambient_car(27,.3)
	var ambient := view.traffic.actor_pose(record)
	# The session car sits across the claimed pose, so the car is placed on its route.
	session.car.global_transform = Transform3D(Basis(Vector3.UP,ambient.basis.get_euler().y),ambient.origin+Vector3.UP*.002)
	session.pedestrian.global_position = ambient.origin+Vector3(0,0,.2)
	await physics_frame
	check(session._board_ambient(),"a blocked ambient pose still offers its route")
	check(session.occupied is ExploreCar and session.occupied != session.car)
	if session.occupied is ExploreCar and session.occupied != session.car:
		check_gt(session.occupied.global_position.distance_to(ambient.origin),.05,"the blocked pose is not reused")
		check(session._valid_actor(session.occupied))
	session.leave()

func _ambient(type: StringName, kind: StringName, cell: Vector2i, t: float) -> Dictionary:
	var record := {"id":800+cell.x,"type":type,"kind":kind,"domain":type,"cell":cell,
		"previous":cell+Vector2i.LEFT,"next":cell+Vector2i.RIGHT,"lane":0,"t":t,"variant":0,"turns":0,"side":1.0,
		"speed":1.2 if type == &"rail" else .6,"length":CityTrafficCatalog.dimensions(kind).z,"stopped":false}
	view.traffic.actors.append(record)
	return record

func _flat_gap(a: Vector3, b: Vector3) -> float: return Vector2(a.x-b.x,a.z-b.z).length()

func test_boarded_boat_keeps_its_pose_and_stays_moored() -> void:
	var city := flat_city()
	for y in range(20,24):
		for x in range(20,24):
			city.terrain.put(x,y,Terrain.SUBMERGED)
			city.set_heights(x,y,2,4)
	if not await _setup(city,Vector3(24.5,2.5,21.5)): return
	view.traffic.graph.refresh()
	var record := _ambient(&"water",&"sailboat",Vector2i(21,21),.3)
	var ambient := view.traffic.actor_pose(record)
	session.pedestrian.global_position = ambient.origin+Vector3(0,0,.2)
	check(session._board_ambient(),"the nearby ambient boat can be boarded")
	var boat: CharacterBody3D = session.occupied
	check(boat is ExploreRouteVehicle,"the boat is occupied")
	if not boat is ExploreRouteVehicle: return
	check_lt(_flat_gap(boat.global_position,ambient.origin),.005,"boarding keeps the boat where it floats")
	check_lt(_yaw_gap(boat.global_basis.get_euler().y,ambient.basis.get_euler().y),.01,"boarding keeps the boat's heading")
	check(session._valid_actor(boat),"the kept pose floats over water")
	var moored := boat.global_transform
	session._leave_vehicle(Transform3D(Basis.IDENTITY,Vector3(24.3,boat.global_position.y,21.5)))
	check(is_instance_valid(boat) and boat.global_transform == moored,"getting out leaves the boat where it is")
	check(view.traffic._claims.has(record.id),"the moored boat stays held from ambient traffic")
	session.leave()

func test_boarded_train_keeps_its_place_and_rejoins_service_where_stopped() -> void:
	if not await _setup(TransitFixtures.rail_city(),Vector3(20.5,2.5,20.8)): return
	view.traffic.graph.refresh()
	var record := _ambient(&"rail",&"train",Vector2i(25,20),.3)
	var ambient := view.traffic.actor_pose(record)
	session.pedestrian.global_position = ambient.origin+Vector3(0,0,.2)
	check(session._board_ambient(),"the nearby ambient train can be boarded")
	var train: CharacterBody3D = session.occupied
	check(train is ExploreRouteVehicle,"the train is occupied")
	if not train is ExploreRouteVehicle: return
	check_lt(_flat_gap(train.global_position,ambient.origin),.005,"boarding keeps the train where it stands on the track")
	check_gt((-train.global_basis.z).dot(-ambient.basis.z),.99,"boarding keeps the train's direction")
	check(session._valid_actor(train))
	await physics_frame
	var frame := ExploreInputFrame.new()
	frame.move = Vector2(0,-1)
	for i in 12: train.step(frame,0,.05)
	frame.move = Vector2.ZERO
	frame.brake = true
	for i in 40: train.step(frame,0,.05)
	var stopped := train.global_transform
	check_gt(_flat_gap(stopped.origin,ambient.origin),.05,"the train was driven along the line")
	session._leave_vehicle(Transform3D(Basis.IDENTITY,stopped.origin+Vector3(0,0,.5)))
	check(view.traffic._claims.is_empty(),"the train goes back to ambient service")
	check(view.traffic._reserved_rail.is_empty(),"its manual reservation is released")
	var resumed := view.traffic.actor_pose(record)
	check_lt(_flat_gap(resumed.origin,stopped.origin),.01,"service resumes from where the train stopped")
	check_gt((-resumed.basis.z).dot(-stopped.basis.z),.99,"facing the way it was driven")
	session.leave()
