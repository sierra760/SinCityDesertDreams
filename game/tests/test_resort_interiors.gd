# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Explore on a gaming resort floor: the door, the third-person camera,
## table prompts and requests, stepping outside, the marina guard and closing.
extends "res://tests/exploration/explore_session_case.gd"

const ANCHOR := Vector2i(20,18)
const ROAD := Vector2i(22,24)
const Access := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")

func _resort_city(code: int = Buildings.ARCOLOGY_COMSTOCK, marina: bool = false) -> City:
	var value := flat_city()
	value.stamp_building(ANCHOR.x,ANCHOR.y,code)
	value.building.putv(ROAD,30)
	value.building.putv(ROAD+Vector2i.RIGHT,30)
	if marina: value.stamp_building(ANCHOR.x+4,ANCHOR.y+1,Buildings.MARINA)
	return value

## Tests run doors instantly; restore the shipped fade for later suites.
func after_all() -> void:
	ExploreResortService.transition_seconds = .3

func _halls() -> Array[Node]:
	var halls: Array[Node] = []
	for child: Node in session.resort_service.get_children():
		if child is ResortInteriorWorld3D and not child.is_queued_for_deletion(): halls.append(child)
	return halls

func _remove_resort() -> void:
	for y: int in range(ANCHOR.y,ANCHOR.y+4):
		for x: int in range(ANCHOR.x,ANCHOR.x+4): city.building.put(x,y,0)
	view.sample_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,16,16))]
	view.revision += 1
	view.geometry_rebuilt.emit(view.revision)

func _start(code: int = Buildings.ARCOLOGY_COMSTOCK, marina: bool = false) -> bool:
	ExploreResortService.transition_seconds = 0.0
	if not _setup(_resort_city(code,marina)): return false
	return await _enter(Vector3(ROAD.x+.5,GROUND,ROAD.y+.5))

func _walk_to(point: Vector3) -> void:
	session.pedestrian.clear_support_frame()
	session.pedestrian.global_position = point+Vector3.UP*.002
	session.pedestrian.stop_input()
	await physics_frame
	await physics_frame

func _status() -> Dictionary:
	var captured: Array[Dictionary] = []
	var listener := func(status: Dictionary) -> void: captured.append(status)
	session.status_changed.connect(listener)
	session._publish_status()
	session.status_changed.disconnect(listener)
	return captured[0] if not captured.is_empty() else {}

func _go_inside() -> bool:
	var threshold := Access.threshold(city,ANCHOR)
	await _walk_to(threshold.origin)
	var status := _status()
	check_eq(String(status.get("prompt","")),"F to enter Comstock Grand","door prompt names the resort")
	check(session.request_interaction(),"F at the door enters")
	await physics_frame
	await physics_frame
	return session.resort_service.is_inside()

func test_enter_supports_walker_with_third_person_camera_and_city_unchanged() -> void:
	if not await _start(): return
	var before := SaveFormat.encode_city(city)
	check(await _go_inside(),"walker is on the casino floor")
	var service: ExploreResortService = session.resort_service
	var feet: Vector3 = session.pedestrian.global_position
	var hall := ResortInteriorLayouts.hall_origin(ANCHOR)
	check_lt(feet.distance_to(hall+ResortInteriorLayouts.layout(&"arcology_comstock").entrance.mat.origin),.02,"entry lands on the mat")
	check(service.contains(feet),"pocket contains the walker")
	check(not service.support_for(feet).is_empty(),"floor supports the walker")
	check(session._valid_actor(session.pedestrian,true),"walker on the floor is a valid actor")
	for frame: int in 20: await physics_frame
	feet = session.pedestrian.global_position
	check(service.is_inside(),"stays inside after physics")
	check_lt(absf(feet.y-hall.y),.01,"walker rests on the hall floor")
	check_eq(String(session._message),"","no recovery message")
	check(not session.camera_rig.interior_active,"resort floors use the third-person camera")
	check(not session.camera_rig.cabin_active)
	check(service.contains(session.camera_rig.camera.global_position),"camera stays inside the hall")
	var status := _status()
	check(bool(status.get("resort",{}).get("inside",false)),"status reports the floor")
	check_eq(String(status.resort.floor),"The Assay Office")
	check_eq(SaveFormat.encode_city(city),before,"entering never edits the city")

func test_table_prompt_and_request_and_door_returns_to_threshold() -> void:
	if not await _start(): return
	var before := SaveFormat.encode_city(city)
	check(await _go_inside())
	var service: ExploreResortService = session.resort_service
	var world := service.world_for({"anchor": ANCHOR, "code": Buildings.ARCOLOGY_COMSTOCK, "key": &"arcology_comstock"})
	var requests: Array = []
	session.casino_table_requested.connect(func(resort: StringName, game: StringName, table: Dictionary) -> void:
		requests.append([resort,game,table]))
	var seen := {}
	for table: Dictionary in world.tables():
		await _walk_to(table.seat)
		var prompt := String(_status().get("prompt",""))
		check(prompt.begins_with("F to play "+String(table.name)),"seat prompt names "+String(table.name))
		check(prompt.ends_with("· $100 minimum"),"seat prompt shows the table minimum")
		check(session.request_interaction(),"F at a seat requests the table")
		seen[table.game] = true
	check_eq(requests.size(),world.tables().size(),"every seat requests its table")
	for game: StringName in [&"blackjack",&"roulette",&"slots",&"money_wheel",&"video_poker",&"faro"]:
		check(seen.has(game),"seat for "+String(game))
	if not requests.is_empty():
		var request: Array = requests[0]
		check_eq(request[0],&"arcology_comstock")
		var pose: Transform3D = session.casino_table_pose(request[2])
		check(pose.is_finite() and service.contains(pose.origin),"table view is inside the hall")
		check(_status().has("table_camera"),"status exposes the held table view")
		session.hold_casino_table_view(request[2],0.0)
		check(session.camera_rig.camera.global_transform.is_equal_approx(pose),"camera holds the table view")
		session.camera_rig.update_follow(.1)
		check(session.camera_rig.camera.global_transform.is_equal_approx(pose),"follow respects the held view")
		session.release_casino_table_view()
		check(not Dictionary(request[2]).is_empty(),"releasing the view leaves the requested table record intact")
		check(not _status().has("table_camera"),"released view leaves the status")
		check(not session.camera_rig.table_view_active)
	# Walk back up to the door from inside the hall, as a player does, so the
	# model is turned toward the door (+Z) when the door is used.
	await _walk_to(world.mat_transform().origin+Vector3(0,0,-.6))
	var toward_door := ExploreInputFrame.idle()
	toward_door.move = Vector2(0,1)
	for _i in 24:
		session.pedestrian.step(toward_door,0.0,1.0/60.0)
		await physics_frame
	check_gt((session.pedestrian._visual.global_basis*Vector3.FORWARD).z,.9,"the model faces the door while walking up to it")
	await _walk_to(world.mat_transform().origin)
	check_eq(String(_status().get("prompt","")),"F to step outside","mat offers the door")
	check(session.request_interaction(),"F at the mat leaves")
	await physics_frame
	await physics_frame
	var threshold := Access.threshold(city,ANCHOR)
	var feet: Vector3 = session.pedestrian.global_position
	check(not service.is_inside(),"walker is outside")
	check_lt(Vector2(feet.x-threshold.origin.x,feet.z-threshold.origin.z).length(),.35,"door returns to the threshold")
	check_lt(absf(feet.y-threshold.origin.y),.02,"threshold is on the ground")
	check_gt((session.pedestrian.global_basis*Vector3.FORWARD).z,.9,"walker faces the street")
	# The visible model turns with the walker's motion; stepping out must turn
	# it to the street too, not leave it facing the door it walked up to.
	check_gt((session.pedestrian._visual.global_basis*Vector3.FORWARD).z,.9,"the model faces the street as well")
	check_eq(SaveFormat.encode_city(city),before,"playing never edits the city")

func test_marina_beside_resort_never_prompts_inside() -> void:
	if not await _start(Buildings.ARCOLOGY_COMSTOCK,true): return
	check(await _go_inside())
	var hall := ResortInteriorLayouts.hall_origin(ANCHOR)
	# The hall's east wall sits beside the marina lot overhead.
	await _walk_to(hall+Vector3(1.355,0,.6))
	check(session.resort_service.contains(session.pedestrian.global_position))
	var marina_access := preload("res://scripts/exploration/explore_marina_access.gd")
	check(not marina_access.nearby(city,session.pedestrian.global_position).is_empty(),"fixture: the marina lot is within reach in plan")
	var prompt := String(_status().get("prompt",""))
	check(not prompt.contains("marina") and not prompt.contains("vehicle"),"no marina or vehicle prompt inside")
	check(not session.request_interaction(),"F away from a seat does nothing inside")
	check_eq(session.occupied,session.pedestrian,"never boards a boat from the casino floor")
	check(session.resort_service.is_inside())

func test_removed_resort_ejects_the_walker() -> void:
	if not await _start(): return
	check(await _go_inside())
	var messages: Array[String] = []
	session.resort_service.ejected.connect(func(message: String) -> void: messages.append(message))
	_remove_resort()
	for frame: int in 4: await physics_frame
	check_eq(messages,["Comstock Grand is gone; you're back on the street."],"closing names the resort and where the walker is")
	check(_halls().is_empty(),"the closed hall is freed")
	check(not session.resort_service.fill.visible,"the shared fill is off once ejected")
	check(not session.resort_service.is_inside(),"walker no longer inside")
	var feet: Vector3 = session.pedestrian.global_position
	check_gt(feet.y,0.0,"walker is back above ground")
	check(session._valid_actor(session.pedestrian),"walker stands on outdoor ground")
	check(session.is_active(),"Explore continues")

func test_removed_resort_never_drops_the_walker_into_water_or_an_obstruction() -> void:
	if not await _start(): return
	check(await _go_inside())
	var door := Access.threshold(city,ANCHOR)
	var door_cell := Vector2i(floori(door.origin.x),floori(door.origin.z))
	# The resort is replaced by a flooded lot reaching the old front door.
	for y: int in range(ANCHOR.y,door_cell.y+2):
		for x: int in range(ANCHOR.x-1,ANCHOR.x+5):
			city.building.put(x,y,0)
			city.terrain.put(x,y,Terrain.SUBMERGED)
			city.set_heights(x,y,2,4)
	view.sample_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,16,16))]
	view.revision += 1
	view.geometry_rebuilt.emit(view.revision)
	for frame: int in 4: await physics_frame
	check(session.is_active(),"Explore continues")
	check(not session.resort_service.is_inside(),"walker no longer inside")
	check(not session.resort_service.ejection_pending(),"the ejection was settled against the rebuilt world")
	check(not session.traversal.touches_water(session.pedestrian.global_position),"the walker is not left in the new water")
	check(session._valid_actor(session.pedestrian,true),"the walker stands supported with full-body clearance")
	var feet: Vector3 = session.pedestrian.global_position
	check(Vector2(feet.x-door.origin.x,feet.z-door.origin.z).length()>.3,"the walker is not left on the flooded threshold")

func test_recover_from_inside_reaches_road_and_marks_outside() -> void:
	if not await _start(): return
	check(await _go_inside())
	check(session.recover(),"Recover from the casino floor")
	await physics_frame
	await physics_frame
	check(not session.resort_service.is_inside(),"containment watch notices the walker left")
	check_gt(session.pedestrian.global_position.y,0.0)

func test_one_shared_fill_and_only_the_occupied_hall_shows() -> void:
	if not await _start(): return
	var service: ExploreResortService = session.resort_service
	check(is_instance_valid(service.fill),"the service owns the fill")
	check(not service.fill.visible,"no fill before entering")
	check(await _go_inside())
	var fills := service.find_children("*","DirectionalLight3D",true,false)
	check_eq(fills.size(),1,"one directional fill for every hall")
	check(service.fill.visible,"the fill is on inside")
	check_eq(service.fill.light_cull_mask,ResortInteriorWorld3D.LAYER,"the fill lights only layer 21")
	check(not service.fill.shadow_enabled,"the fill casts no shadow")
	var halls := _halls()
	check_eq(halls.size(),1,"one hall built")
	if halls.is_empty(): return
	var hall: ResortInteriorWorld3D = halls[0]
	check(hall.visible,"the occupied hall is visible with its lamps")
	check_eq(hall.find_children("*","DirectionalLight3D",true,false).size(),0,"a hall adds no directional light")
	check_between(hall.find_children("*","OmniLight3D",true,false).size(),1,6,"at most six lamps per hall")
	await _walk_to(hall.mat_transform().origin)
	check(session.request_interaction(),"F at the mat leaves")
	await physics_frame
	check(not service.is_inside())
	check(not hall.visible,"the hall hides after leaving")
	check(not service.fill.visible,"the fill is off outside")
	check(not service.contains(hall.mat_transform().origin),"a hidden hall is not consulted for containment")
	check(not service.recover_pose(hall.mat_transform().origin).is_empty(),"recovery may still use the last hall")
	check(await _go_inside(),"the hall is entered again")
	check(hall.visible and service.fill.visible,"re-entering shows the cached hall")

func test_hall_closed_mid_fade_cancels_the_door() -> void:
	ExploreResortService.transition_seconds = .3
	if not _setup(_resort_city()): return
	if not await _enter(Vector3(ROAD.x+.5,GROUND,ROAD.y+.5)): return
	var threshold := Access.threshold(city,ANCHOR)
	await _walk_to(threshold.origin)
	check(session.request_interaction(),"door accepted")
	check(session.resort_service.is_transitioning(),"door fades")
	_remove_resort()
	for frame: int in 4: await physics_frame
	check(not session.resort_service.is_transitioning(),"the fade is cancelled with the hall")
	await create_timer(.5).timeout
	check(not session.resort_service.is_inside(),"the walker never enters a closed hall")
	check(_halls().is_empty(),"the closed hall is freed")
	check_gt(session.pedestrian.global_position.y,0.0,"the walker stays outdoors")
	check(session.is_active(),"Explore continues")
	ExploreResortService.transition_seconds = 0.0

func test_fade_transition_moves_walker_at_black() -> void:
	ExploreResortService.transition_seconds = .3
	if not _setup(_resort_city()): return
	if not await _enter(Vector3(ROAD.x+.5,GROUND,ROAD.y+.5)): return
	var threshold := Access.threshold(city,ANCHOR)
	await _walk_to(threshold.origin)
	check(session.request_interaction(),"door accepted")
	check(session.resort_service.is_transitioning(),"door fades first")
	check(not session.request_interaction(),"no second request mid-fade")
	await create_timer(.6).timeout
	check(not session.resort_service.is_transitioning(),"fade finished")
	check(session.resort_service.is_inside(),"walker inside after the fade")
	ExploreResortService.transition_seconds = 0.0
