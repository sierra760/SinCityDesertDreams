# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Passengers using the local Explore train: waiting on platforms, seated in
## the carriage, stepping off and boarding at stops, giving way to the player.
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

func test_platforms_and_carriage_have_riders_on_real_floors() -> void:
	for subway: bool in [false,true]:
		await _setup(subway)
		var label := "subway " if subway else "rail "
		for i: int in 3: service.step(.1,walker)
		check(is_instance_valid(service.riders),label+"service owns a rider crowd")
		var states := service.riders.states()
		var riding := 0
		var waiting := {}
		for state: Dictionary in states:
			var at: Vector3 = state.position
			if state.in_train:
				riding += 1
				check(service.train.contains(at),label+"carriage rider is inside the cabin")
			else:
				waiting[state.station] = int(waiting.get(state.station,0))+1
				check(not service.world.support_for(at+Vector3.UP*.002).is_empty(),label+"waiting rider stands on platform support "+str(at))
				for station: Dictionary in service.world.active_stations:
					var local := Transform3D(Basis(Vector3.UP,float(station.yaw)),station.position).affine_inverse()*at
					if absf(local.x)>.5 or absf(local.z)>.5: continue
					check(absf(local.z)>.11 or absf(local.x)>.3,label+"boarding aperture stays clear "+str(local))
					check(absf(local.x)>=.18,label+"riders stand behind the yellow edge "+str(local))
		check(riding>=3 and riding<=6,label+"carriage starts with a few seated riders: "+str(riding))
		check_eq(waiting.size(),service.world.active_stations.size(),label+"every prepared platform has people waiting")
		for station: String in waiting: check(int(waiting[station])>=2,label+"at least two wait at "+station)
		await after_each()

func test_riders_get_off_and_board_at_a_stop_then_ride_with_the_train() -> void:
	await _setup()
	check(_wait_boarding())
	var before := service.riders.states()
	# Skip the ordinary dwell: the doors must still wait for the boarders.
	service._timer = ExploreTransitTrain.DWELL
	service.step(.1,walker)
	service.step(.1,walker)
	check(service.riders.doorway_busy(),"riders are on their way through the doors")
	check_eq(service.state,"boarding","doors stay open for boarding riders")
	var steps := 0
	while service.state in ["boarding","closing","opening"] and steps<400:
		service.step(.1,walker)
		steps += 1
	check(steps<400,"the stop ends in bounded time: "+str(steps))
	check_eq(service.state,"departing")
	var ids := {}
	for state: Dictionary in service.riders.states(): ids[int(state.id)] = state
	var boarded := 0
	var boarders: Array[int] = []
	for state: Dictionary in before:
		var id := int(state.id)
		if not state.in_train and ids.has(id) and ids[id].in_train:
			boarded += 1
			check(service.train.contains(ids[id].position),"boarder is inside the carriage")
			boarders.append(id)
		if state.in_train and ids.has(id) and not ids[id].in_train:
			check(not service.train.contains(ids[id].position),"a rider who got off is outside the carriage")
	check(boarded>=1,"at least one waiting rider boarded")
	for state: Dictionary in service.riders.states():
		check(not (state.goal=="board" and not state.in_train),"no boarder chases a departed train")
		check(not (state.goal=="leave" and state.in_train),"no rider leaving is carried away")
	# Seated riders move with the carriage.
	var locals := {}
	for state: Dictionary in service.riders.states():
		if state.in_train and not state.moving: locals[state.id] = service.train.global_transform.affine_inverse()*Vector3(state.position)
	check(not locals.is_empty(),"riders are seated aboard")
	for i: int in 20: service.step(.1,walker)
	check(service.speed>0.0,"train is under way")
	for state: Dictionary in service.riders.states():
		if locals.has(state.id):
			var local: Vector3 = service.train.global_transform.affine_inverse()*Vector3(state.position)
			check(local.distance_to(locals[state.id])<.0005,"seated rider stays in place in the moving carriage")
	# Anyone still finding a place when the doors closed settles on the way.
	for i: int in 80: service.step(.1,walker)
	for id: int in boarders:
		var state := _state(id)
		check(not state.moving and (state.seated or int(state.cabin)>=ExploreTransitRiders.SEATS),"boarder took a seat or a standing place "+str(state)+" local "+str(service.train.global_transform.affine_inverse()*Vector3(state.position)))
		check(service.train.contains(state.position),"settled boarder rides inside the cabin")

func test_riders_yield_to_the_player_and_never_strand_the_train() -> void:
	await _setup()
	check(_wait_boarding())
	service._timer = ExploreTransitTrain.DWELL
	service.step(.1,walker)
	var boarder: Dictionary = {}
	for state: Dictionary in service.riders.states():
		if state.goal=="board" and not state.in_train: boarder = state
	check(not boarder.is_empty(),"a waiting rider sets off to board")
	# The player stands right where that rider waits.
	walker.global_position = Vector3(boarder.position)+Vector3.UP*.002
	for i: int in 10: service.step(.1,walker)
	var held := _state(int(boarder.id))
	check(Vector3(held.position).distance_to(boarder.position)<.001,"rider gives way instead of walking through the player")
	var steps := 0
	while service.state!="departing" and steps<300:
		service.step(.1,walker)
		steps += 1
	check_eq(service.state,"departing","a blocked rider stops holding the doors")
	var after := _state(int(boarder.id))
	check(not after.is_empty() and not after.in_train,"the blocked rider stays on the platform")
	check_eq(after.get("goal",""),"wait","and goes back to waiting")
	check(not service.world.support_for(Vector3(after.position)+Vector3.UP*.002).is_empty(),"on real platform support")

func test_subway_riders_board_and_never_stand_inside_the_bench() -> void:
	await _setup(true)
	var seen_seated := false
	var boarded := false
	var waiting_before := {}
	for state: Dictionary in service.riders.states(): if not state.in_train: waiting_before[state.id] = true
	for i: int in 600:
		service.step(.1,walker)
		for state: Dictionary in service.riders.states():
			if state.in_train:
				if waiting_before.has(state.id): boarded = true
				continue
			for station: Dictionary in service.world.active_stations:
				var s := float(station.side)
				var local := Transform3D(Basis(Vector3.UP,float(station.yaw)),station.position).affine_inverse()*Vector3(state.position)
				var on_bench := local.x*s>.278 and local.x*s<.325 and local.z*s>.30 and local.z*s<.45 and absf(local.y-.025)<.05
				if not on_bench: continue
				if state.seated: seen_seated = true
				else: check(false,"a standing rider is inside the platform bench "+str(local))
		if boarded and i>200: break
	check(boarded,"a subway rider boarded")

func _state(id: int) -> Dictionary:
	for state: Dictionary in service.riders.states():
		if int(state.id)==id: return state
	return {}

func test_riders_are_presentation_only() -> void:
	await _setup(true)
	var bytes := SaveFormat.encode_city(view.city)
	check(_wait_boarding())
	for i: int in 120: service.step(.1,walker)
	check_eq(SaveFormat.encode_city(view.city),bytes,"riders never change the city")
	check(service.riders.find_children("*","CollisionObject3D",true,false).is_empty(),"riders have no collision")
	check(service.riders.count()<=ExploreTransitRiders.LIMIT,"bounded crowd")
	service.clear()
	check(not is_instance_valid(service.riders),"riders are freed with the service")

func _setup(subway: bool = false) -> void:
	var city := Fixtures.subway_city() if subway else Fixtures.rail_city()
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
