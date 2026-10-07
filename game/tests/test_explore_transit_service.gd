# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
const Fixtures := preload("res://tests/test_explore_transit_network.gd")
const Service := preload("res://scripts/exploration/transit/explore_transit_service.gd")

class SnapshotView extends CityView3D:
	var snapshot_chunks: Array[Dictionary] = []
	var snapshot_networks: Dictionary = {}
	func traversal_snapshot() -> Dictionary:
		return {"chunks":snapshot_chunks,"networks":snapshot_networks,"revision":_geometry_revision,"city":city}

var view: SnapshotView
var traversal: CityTraversalWorld3D
var walker: ExplorePedestrian
var service: ExploreTransitService

func test_platform_guidance_tracks_doors_and_the_actual_next_departure() -> void:
	await _setup()
	check(_wait_boarding())
	var origin := service.network.stations[0]
	var destination := service.network.stations[1]
	var status := service.status()
	check_eq(status.get("current_stop"),origin.name,"stopped train reports its current platform")
	check_eq(status.next_stop,destination.name,"next means the next departure, not the platform beneath the train")
	check_eq(status.destination,destination.name,"terminus reversal is reflected before departure")
	check_eq(status.get("selected_destination"),destination.id,"picker reports the actual prepared route")
	for i: int in 81: service.step(.1,walker)
	check_eq(service.state,"closing")
	check(service.status().message.contains("closing"),"platform tells users not to board closing doors")
	check(not service.status().message.contains("open doorway"),"old boarding invitation cannot survive door closure")
	for i: int in 20: service.step(.1,walker)
	check(service.status().message.contains("depart"),"platform reports the departing train")

func test_destination_control_is_locked_only_while_occupying_a_train_or_lift() -> void:
	await _setup(true)
	check(_wait_boarding())
	check(bool(service.status().get("can_choose_destination",false)),"waiting passenger can choose service")
	walker.global_position=service.train.global_transform*Vector3(0,.027,0)
	check(not bool(service.status().get("can_choose_destination",true)),"riding passenger cannot select an unapplied route")
	check_eq(service.status().get("transit_kind"),"subway")
	var lift: Node3D=service.world.elevators[0]
	walker.global_position=lift.cabin.global_position+Vector3.UP*.002
	check(not bool(service.status().get("can_choose_destination",true)),"occupied lift cannot rebuild its own shaft")
	check(not service.choose_destination(0,1),"rejected lift choice is not queued silently")

func _setup(subway: bool = false, supplied: City = null) -> void:
	var city := supplied if supplied != null else Fixtures.subway_city() if subway else Fixtures.rail_city()
	view = SnapshotView.new()
	root.add_child(view)
	view.bind_city(city)
	view._geometry_revision = 1
	view.networks.rebuild(city)
	view.snapshot_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,24,16))]
	view.snapshot_networks = view.networks.physical_data()
	traversal = CityTraversalWorld3D.new()
	view.world.add_child(traversal)
	traversal.rebuild(city,view.snapshot_chunks,view.snapshot_networks,1)
	walker = ExplorePedestrian.new()
	view.world.add_child(walker)
	walker.bind(traversal)
	service = Service.new()
	view.world.add_child(service)
	service.bind(view,traversal,walker)
	var station: Dictionary = service.network.stations[0]
	walker.global_position = Vector3(station.anchor.x+.5,station.surface+.002,station.anchor.y+.5)
	service.step(.016,walker)
	await physics_frame
	await physics_frame

func after_each() -> void:
	if is_instance_valid(service): service.clear()
	if is_instance_valid(view): view.free()
	view = null
	service = null
	walker = null
	traversal = null
	await physics_frame

func _wait_boarding() -> bool:
	for i: int in 180:
		service.step(.1,walker)
		if service.state == "boarding": return true
	return false

func test_service_approach_doors_dwell_and_obstruction() -> void:
	await _setup()
	check_eq(service.state,"approaching")
	check(_wait_boarding(),"automatic arrival bounded to 18 active seconds")
	check_eq(service.speed,0.0)
	check_eq(service.train.door_fraction,1.0)
	var pose := service.train.global_transform
	for i: int in 79: service.step(.1,walker)
	check_eq(service.state,"boarding","eight seconds fully open")
	check_eq(service.train.global_transform,pose)
	walker.global_position = service.train.global_transform*Vector3(service.train.door_side*.12,.027,0)
	for i: int in 30: service.step(.1,walker)
	check_eq(service.state,"boarding","doorway obstruction holds stop indefinitely")
	walker.global_position += service.train.global_basis.x*service.train.door_side*.2
	service.step(.1,walker)
	check_eq(service.state,"closing")
	walker.global_position = service.train.global_transform*Vector3(service.train.door_side*.12,.027,0)
	service.step(.1,walker)
	check_eq(service.state,"opening","obstruction reopens closing doors")

func test_pause_network_edit_and_city_immutability() -> void:
	await _setup()
	var bytes := SaveFormat.encode_city(view.city)
	check(_wait_boarding())
	var before := service.train.global_transform
	service.set_suspended(true)
	for i: int in 30: service.step(.1,walker)
	check_eq(service.train.global_transform,before)
	check_eq(service.state,"boarding")
	service.set_suspended(false)
	check_eq(SaveFormat.encode_city(view.city),bytes)
	view.city.building.put(25,20,Buildings.NONE)
	view._geometry_revision += 1
	service.step(.016,walker)
	check_eq(service.state,"idle","changed route retires before another movement")
	check(service.network.destinations(0).is_empty())

func test_subway_support_and_cabin_are_explicit_and_bounded() -> void:
	await _setup(true)
	check(_wait_boarding())
	var station: Dictionary = service.network.stations[0]
	check(service.contains(station.platform+Vector3.UP*.002))
	check(not service.contains(Vector3(5,-5,5)),"below-world position is not a tunnel")
	var inside := service.train.global_transform*Vector3(0,.027,0)
	var support := service.support_for(inside)
	check_eq(support.get("frame"),service.train,"only cabin has moving support")
	check(not service.support_for(station.platform).has("frame"))
	check_eq(service.status().station_id,0)
	check(not service.status().message.contains("F to"),"boarding has no key")

func test_walk_through_open_door_and_carry_without_drift() -> void:
	await _setup()
	check(_wait_boarding())
	walker.transit_support = service
	var station: Dictionary = service.network.stations[0]
	walker.global_position = station.platform+Vector3.UP*.002
	await physics_frame
	var local_move := -Vector3(station.normal)
	var frame := ExploreInputFrame.idle()
	frame.move = Vector2(local_move.x,local_move.z)
	var boarded := false
	for i: int in 180:
		service.step(1.0/60.0,walker)
		walker.step(frame,0,1.0/60.0)
		await physics_frame
		if service.train.contains(walker.global_position):
			boarded = true
			break
	check(boarded,"actual walking crosses the open doorway without F/E")
	if not boarded:
		print("BOARDING_STATE ",walker.global_position," platform ",station.platform," train ",service.train.global_transform)
		return
	# Walk farther inside before doors close, then coast to zero relative speed.
	for i: int in 35:
		service.step(1.0/60.0,walker)
		walker.step(frame,0,1.0/60.0)
		await physics_frame
	for i: int in 20:
		service.step(1.0/60.0,walker)
		walker.step(ExploreInputFrame.idle(),0,1.0/60.0)
		await physics_frame
	var inside: Vector3 = service.train.global_transform.affine_inverse()*walker.global_position
	var moved := false
	for i: int in 650:
		service.step(1.0/60.0,walker)
		walker.step(ExploreInputFrame.idle(),0,1.0/60.0)
		await physics_frame
		if service.speed>.1: moved = true
	var after: Vector3 = service.train.global_transform.affine_inverse()*walker.global_position
	check(moved,"service departed with passenger")
	check_lt(Vector2(after.x-inside.x,after.z-inside.z).length(),.002,"carriage motion applied exactly once; stationary rider has no drift")
	check(service.train.contains(walker.global_position),"passenger retained in cabin")
	frame = ExploreInputFrame.idle()
	frame.move = Vector2(0,-1)
	for i: int in 50:
		service.step(1.0/60.0,walker)
		walker.step(frame,service.train.global_rotation.y,1.0/60.0)
		await physics_frame
	var walking: Vector3 = service.train.global_transform.affine_inverse()*walker.global_position
	check_lt(walking.z,after.z-.04,"passenger can walk along the cabin while train moves")
	check(service.train.contains(walker.global_position),"walking rider stays inside moving carriage")

func test_closed_door_is_physical_and_platform_side_only() -> void:
	await _setup()
	check(_wait_boarding())
	await physics_frame
	var train := service.train
	var inside := train.global_transform*Vector3(0,.027,0)
	var pose := Transform3D(Basis.IDENTITY,inside)
	var side := float(train.door_side)
	check(walker.test_move(pose,train.global_basis.x*(-side*.22)),"far door stays physically shut")
	train.set_doors(0,service.network.stations[0].normal)
	await physics_frame
	check(walker.test_move(pose,train.global_basis.x*(side*.22)),"closed platform door blocks walking")
	train.set_doors(1,service.network.stations[0].normal)
	await physics_frame
	check(not walker.test_move(pose,train.global_basis.x*(side*.20)),"open doorway permits actual capsule motion")

func test_subway_elevator_walks_down_and_back_to_surface() -> void:
	await _setup(true)
	walker.transit_support = service
	var station: Dictionary = service.network.stations[0]
	station = service.network.station_for_route(service.route_data,0)
	var points := service.world.access_waypoints(station)
	walker.global_position = points[0]
	var recoveries: Array = []
	walker.recovery_requested.connect(func(reason): recoveries.append(reason))
	for journey: int in 2:
		for destination: Vector3 in points:
			if absf(destination.y-walker.global_position.y)>.10 and Vector2(destination.x-walker.global_position.x,destination.z-walker.global_position.z).length()<.012 and service.world.in_elevator(walker.global_position):
				check(service.interact_elevator(),"request physical elevator ride")
			for i: int in 1200:
				var delta := Vector2(destination.x-walker.global_position.x,destination.z-walker.global_position.z)
				if delta.length()<.008 and absf(destination.y-walker.global_position.y)<.025 or walker._reported: break
				if service.world.elevator_prompt(walker.global_position)=="F to call elevator": service.interact_elevator()
				service.step(1.0/60.0,walker)
				var frame := ExploreInputFrame.idle()
				frame.move = delta.normalized()*clampf(delta.length()/.03,0,1.0) if delta.length()>.008 else Vector2.ZERO
				walker.step(frame,0,1.0/60.0)
				await physics_frame
			check_lt(Vector2(destination.x-walker.global_position.x,destination.z-walker.global_position.z).length(),.025,"walk reaches lift/lobby waypoint "+str(destination)+" actual "+str(walker.global_position))
			check_lt(absf(walker.global_position.y-destination.y),.025,"walk reaches the actual lift/lobby height")
		if journey==0: check_lt(absf(walker.global_position.y-station.platform.y),.012,"walk actually descends to the underground platform")
		points.reverse()
	check(recoveries.is_empty(),"continuous support across both landings and the moving elevator")
	check_lt(absf(walker.global_position.y-station.surface),.01,"walk climbs back onto surface")

func test_track_intrusion_emergency_stop_respects_front_overhang() -> void:
	await _setup()
	service.distance = 4.0
	service.direction = 1
	service.stop_index = 1
	service.state = "departing"
	service.speed = .75
	service.train.global_transform = ExploreTransitNetwork.sample(service.route_data,service.distance)
	walker.global_position = service.train.global_transform*Vector3(0,.028,-.55)
	var before := service.train.global_transform
	service.step(.1,walker)
	check_eq(service.speed,0.0,"unexpected intrusion stops before front overhang can hit walker")
	check_eq(service.train.global_transform,before,"no braking creep through pedestrian")
	walker.global_position += service.train.global_basis.x*.25
	service.step(.1,walker)
	check_gt(service.speed,0.0,"clear track resumes service")

func test_manual_surface_train_reserves_track_and_releases_service() -> void:
	await _setup()
	check(is_instance_valid(service.train))
	var cells: Array[Vector2i] = [Vector2i(20,20),Vector2i(21,20),Vector2i(22,20)]
	service.begin_surface_drive_route(cells)
	check_eq(service.state,"driving")
	check(not is_instance_valid(service.train),"no simultaneous passenger train on controlled track")
	check_eq(view.traffic._reserved_rail.size(),3)
	check(not service.status().passenger,"driving route has safe status without passenger stops")
	service.end_drive_route()
	check_eq(service.state,"idle")
	check(view.traffic._reserved_rail.is_empty())

func test_city_edit_discards_stale_destination_ids() -> void:
	await _setup()
	service._choices[0] = 99
	view._geometry_revision += 1
	service.step(.016,walker)
	check(service._choices.is_empty(),"rebuilt station IDs cannot retain stale destination choice")
	service.step(.016,walker)
	check_eq(service.state,"approaching","connected service resumes after reindexing")

func test_manual_subway_survives_unrelated_revision_and_holds_support_for_invalid_handoff() -> void:
	await _setup(true)
	var route := service.prepare_drive_route(walker.global_position,true)
	check(not route.is_empty())
	var points: PackedVector3Array = route.points
	view._geometry_revision += 1
	service.refresh_geometry()
	check_eq(service.state,"driving","unrelated city edit preserves occupied manual service")
	check(not service.manual_route_invalidated)
	check_eq(service.route_data.points,points)
	check(not service.world.route_data.is_empty(),"manual tunnel projection remains available")
	view.city.underground.put(25,20,0)
	view._geometry_revision += 1
	service.refresh_geometry()
	check(service.manual_route_invalidated,"controller must recover before another driving step")
	check(not service.world.route_data.is_empty(),"retain current support until controller handoff")

func test_destination_changes_preserve_waiting_underground_support() -> void:
	var city := Fixtures.subway_city()
	city.building.put(24,20,Buildings.SUBWAY_STATION)
	city.underground.put(24,20,NetworkShapes.STATION_LINK)
	await _setup(true,city)
	check(service.choose_destination(0,2),"queue branch selection while approaching")
	check(_wait_boarding())
	check_eq(service.route_data.to,2,"choice applied before doors open")
	walker.transit_support = service
	walker.global_position = service.network.station(0).platform+Vector3.UP*.002
	var train_id := service.train.get_instance_id()
	check(service.choose_destination(0,1))
	check_eq(service.train.get_instance_id(),train_id,"same carriage reroutes at the stop")
	check_eq(service.route_data.to,1)
	check(service.world.contains(walker.global_position),"destination change cannot erase waiting platform")

func test_unoccupied_local_service_follows_a_different_station_network() -> void:
	var city := Fixtures.rail_city()
	for x: int in range(18,34): city.building.put(x,26,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
	for anchor: Vector2i in [Vector2i(20,27),Vector2i(29,27)]:
		for y: int in range(anchor.y,anchor.y+2):
			for x: int in range(anchor.x,anchor.x+2): city.building.put(x,y,Buildings.RAIL_STATION)
	await _setup(false,city)
	walker.global_position = Vector3(20.5,CityGeometry3D.ground_height(city,Vector2i(20,27))+.002,27.5)
	service.step(.1,walker)
	check_eq(service.state,"approaching")
	check_eq(service.network.station(int(service.route_data.from)).anchor,Vector2i(20,27),"approaching a different network prepares its local train")
