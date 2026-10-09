# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Actual Explore entry, all six machines, camera, exit and replacement.
extends "res://tests/exploration/explore_session_case.gd"

const Access := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")
const ANCHOR := Vector2i(20,18)
const ROAD := Vector2i(20,19)
const STORE := &"com_corner_store"

func after_all() -> void:
	ExploreResortService.transition_seconds = .3

func _start() -> bool:
	ExploreResortService.transition_seconds = 0.0
	var value := flat_city()
	value.stamp_building(ANCHOR.x,ANCHOR.y,126)
	value.building.putv(ROAD,30)
	value.building.putv(ROAD+Vector2i.RIGHT,30)
	if not _setup(value): return false
	return await _enter(Vector3(ROAD.x+.5,GROUND,ROAD.y+.5))

func _walk_to(point: Vector3) -> void:
	session.pedestrian.clear_support_frame()
	session.pedestrian.global_position = point+Vector3.UP*.002
	session.pedestrian.stop_input()
	await physics_frame
	await physics_frame

func _go_inside() -> bool:
	await _walk_to(Access.threshold(city,ANCHOR,126).origin)
	var found := Access.nearby(city,session.pedestrian.global_position)
	check_eq(found.get("key",&""),STORE)
	check(session.request_interaction(),"store door enters through actual Explore")
	await physics_frame
	await physics_frame
	return session.resort_service.is_inside()

func test_early_store_entry_every_machine_and_exit() -> void:
	if not await _start(): return
	var before := SaveFormat.encode_city(city)
	check_lt(city.funds,100000,"store works before city can afford Comstock")
	check(await _go_inside())
	var service: ExploreResortService = session.resort_service
	var world := service.world_for({"anchor":ANCHOR,"code":126,"key":STORE})
	check(service.contains(session.pedestrian.global_position))
	check(not service.support_for(session.pedestrian.global_position).is_empty())
	for i in 20: await physics_frame
	check(service.is_inside(),"physics keeps player inside small store")
	check(session._valid_actor(session.pedestrian,true))
	check(service.contains(session.camera_rig.camera.global_position),"follow camera remains inside store")
	var requests: Array = []
	session.casino_table_requested.connect(func(venue: StringName,kind: StringName,table: Dictionary) -> void: requests.append([venue,kind,table]))
	for table: Dictionary in world.tables():
		await _walk_to(table.seat)
		check(service.prompt(session.pedestrian.global_position).ends_with("· $1 minimum"),"machine shows low minimum")
		check(session.request_interaction(),"every seat requests its own machine")
		var pose: Transform3D = session.casino_table_pose(table)
		check(service.contains(pose.origin),"seated view inside store")
	check_eq(requests.size(),6)
	for request: Array in requests:
		check_eq(request[0],STORE)
		check(request[1] in [&"slots",&"video_poker"])
	await _walk_to(world.mat_transform().origin)
	check_eq(service.prompt(session.pedestrian.global_position),"F to step outside")
	check(session.request_interaction())
	await physics_frame
	await physics_frame
	check(not service.is_inside())
	check_gt(session.pedestrian.global_position.y,0.0,"returns above ground")
	check_lt(session.pedestrian.global_position.distance_to(Access.threshold(city,ANCHOR,126).origin),.08)
	check_eq(SaveFormat.encode_city(city),before,"entry and exit do not edit city")

func test_replaced_store_ejects_player_and_clears_cached_hall() -> void:
	if not await _start(): return
	check(await _go_inside())
	city.building.putv(ANCHOR,0)
	view.sample_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,16,16))]
	view.revision += 1
	view.geometry_rebuilt.emit(view.revision)
	await physics_frame
	await physics_frame
	check(not session.resort_service.is_inside())
	check_gt(session.pedestrian.global_position.y,0.0)
	check(String(session._message).contains("Despicable's"))
