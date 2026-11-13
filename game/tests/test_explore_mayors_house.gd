# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/explore_session_case.gd"

func test_street_start_creates_only_the_walker_and_preserves_city() -> void:
	if not _setup(): return
	var saved := SaveFormat.encode_city(city).duplicate(true)
	await physics_frame
	check(session.enter(city,Vector3(22.5,GROUND,20.5)))
	check(session.car == null,"street start has no Desert Cruiser")
	check(session.helicopter == null,"street start has no helicopter")
	check_eq(view.world.find_children("Explore*","CharacterBody3D",true,false).size(),1,"only the walker is created without a house")
	check_eq(SaveFormat.encode_city(city),saved)
	session.leave()
	check_eq(view.world.find_children("Explore*","CharacterBody3D",true,false).size(),0)

func test_menu_says_plainly_that_a_city_without_the_house_has_no_helicopter() -> void:
	if not _setup(): return
	await physics_frame
	check(session.enter(city,Vector3(22.5,GROUND,20.5)))
	check(session.available_helicopter() == null,"no helicopter can be flown in this city")
	session.suspend()
	check(not session.select_vehicle(&"helicopter"))
	check(session._message.contains("has no helicopter"),session._message)
	check(session._message.contains("the city has none"),"the message does not send the player to a house that does not exist: "+session._message)
	check(not session.select_vehicle(&"mayormobile"))
	check(session._message.contains("this city has none"),session._message)
	check(not session._message.contains("Walk to it"),"nothing to walk to: "+session._message)
	check_eq(session.occupied,session.pedestrian)

func _house_city(front: Vector2i = Vector2i.DOWN) -> City:
	var result := flat_city()
	result.stamp_building(20,20,Buildings.MAYORS_RESIDENCE)
	for i: int in range(18,25):
		var cell := Vector2i(i,22) if front == Vector2i.DOWN else Vector2i(i,19) if front == Vector2i.UP else Vector2i(22,i) if front == Vector2i.RIGHT else Vector2i(19,i)
		result.building.putv(cell,30)
	return result

func test_house_has_four_ground_vehicles_in_every_street_facing() -> void:
	for front: Vector2i in [Vector2i.DOWN,Vector2i.RIGHT,Vector2i.UP,Vector2i.LEFT]:
		if not _setup(_house_city(front)): return
		view.buildings.rebuild(city,view.catalog)
		await physics_frame
		check(session.enter(city,Vector3(21,GROUND,22.5),true))
		check_eq(session.owned_vehicles.size(),4,"one fleet in each facing")
		for actor: CharacterBody3D in session.owned_vehicles:
			check(not actor.is_physics_processing() and not actor.is_processing(),"parked actors do not tick")
			check(session._valid_actor(actor,true),"parked vehicle has actual support and clearance")
			check_between(actor.global_position.y,GROUND+.01,GROUND+.025,"ground-level parking")
		var expected_yaw := atan2(float(front.x),float(front.y))
		check_lt(absf(angle_difference(session._house.yaw,expected_yaw)),.001)
		check_eq(session.occupied,session.pedestrian)
		await after_each()

func test_menu_uses_the_parked_police_cruiser_without_moving_or_replacing_it() -> void:
	if not _setup(_house_city()): return
	view.buildings.rebuild(city,view.catalog)
	await physics_frame
	check(session.enter(city,Vector3(21,GROUND,22.5),true))
	check_eq(session.owned_vehicles.size(),4)
	if session.owned_vehicles.size()!=4: return
	var police: CharacterBody3D = session.owned_vehicles[1]
	var pose := police.global_transform
	session.pedestrian.global_position = police.global_position+Vector3(-.19,0,0)
	session.suspend()
	check(session.select_vehicle(&"police"))
	check_eq(session.occupied,police,"existing house vehicle is selected")
	check_eq(police.global_transform,pose,"selection never teleports it")
	check(session.selected_vehicle == null,"no replacement actor")
	check_eq(session.owned_vehicles.size(),4)

func test_fire_engine_can_leave_the_motor_court_and_return_but_not_drive_across_the_garden() -> void:
	if not _setup(_house_city()): return
	view.buildings.rebuild(city,view.catalog)
	await physics_frame
	check(session.enter(city,Vector3(21,GROUND,22.5),true))
	session.set_physics_process(false)
	if session.owned_vehicles.size()!=4: check(false,"complete fleet needed for drive"); return
	var truck := session.owned_vehicles[2] as ExploreCar
	var start := truck.global_transform
	session._occupy(truck)
	var forward := ExploreInputFrame.idle()
	forward.move = Vector2(0,-1)
	for tick in 120:
		truck.step(forward,0,1.0/60.0)
		await physics_frame
	check_gt(truck.global_position.z,22.08,"truck physically reaches the adjoining street")
	check(truck.on_drivable_ground())
	truck.stop_input()
	var reverse := ExploreInputFrame.idle()
	reverse.move = Vector2(0,1)
	for tick in 170:
		truck.step(reverse,0,1.0/60.0)
		await physics_frame
	check_lt(truck.global_position.z,21.75,"truck physically returns into the apron")
	check(truck.on_drivable_ground())
	truck.apply_safe_pose(start)
	var outside := start
	outside.origin = Vector3(22.6,start.origin.y,21)
	truck.apply_safe_pose(outside)
	check(not truck.on_drivable_ground(),"driveway cannot grant arbitrary off-road travel")
	truck.apply_safe_pose(start)
	check(session._valid_actor(truck,true))

func test_nearby_grounded_ambient_helicopter_can_be_claimed_without_any_starter() -> void:
	if not _setup(): return
	await physics_frame
	check(session.enter(city,Vector3(22.5,GROUND,20.5)))
	session.set_physics_process(false)
	check(session.helicopter==null)
	var claim := {"id":9999,"kind":&"helicopter","position":Vector3(24,GROUND+.002,23),"yaw":0.0}
	check(session._select_vehicle(&"helicopter",claim),"a real claim supplies the aircraft")
	check(session.occupied is ExploreHelicopter)
	check_eq(session.occupied,session.selected_vehicle,"borrowed aircraft stays separately owned")
	check(session.helicopter==null,"claim never invents a house helicopter")
	check_lt(session.occupied.global_position.distance_to(claim.position),.01)

func test_blocked_bay_is_skipped_without_relocating_its_vehicle() -> void:
	if not _setup(_house_city()): return
	view.buildings.rebuild(city,view.catalog)
	Fixture.box(view.world,Vector3(21.1375,GROUND+.10,21.3),Vector3(.15,.18,.3),ExploreActorProfile.OBSTACLE)
	await physics_frame
	check(session.enter(city,Vector3(21,GROUND,22.5),true))
	check_eq(session.owned_vehicles.size(),3,"only the obstructed bay is skipped")
	check(session.car==null,"blocked Desert Cruiser is not moved elsewhere")
	check(session.helicopter!=null)
	check(session._message.contains("obstructed"))
	check_eq(session.available_helicopter(),session.helicopter,"the house helicopter is the one to fly")
	session.suspend()
	check(not session.select_vehicle(&"mayormobile"))
	check(session._message.contains("obstructed"),"a blocked bay is named as the reason: "+session._message)

func test_house_aircraft_takes_off_lands_and_leaves_other_vehicles_unchanged() -> void:
	if not _setup(_house_city()): return
	view.buildings.rebuild(city,view.catalog)
	await physics_frame
	check(session.enter(city,Vector3(21,GROUND,22.5),true))
	session.set_physics_process(false)
	var heli := session.helicopter as ExploreHelicopter
	check(heli!=null)
	if heli==null: return
	var others: Array[Transform3D] = []
	for i in 3: others.append(session.owned_vehicles[i].global_transform)
	session._occupy(heli)
	var up := ExploreInputFrame.idle()
	up.vertical = 1
	for tick in 90:
		heli.step(up,0,1.0/60.0)
		await physics_frame
	check_gt(heli.global_position.y,GROUND+.25,"actual piloted aircraft clears the pad")
	var down := ExploreInputFrame.idle()
	down.vertical = -1
	for tick in 190:
		heli.step(down,0,1.0/60.0)
		await physics_frame
	check(heli.landed(),"skids land on ground-level pad")
	check(session.request_interaction(),"walker exits the landed aircraft")
	for i in 3: check_eq(session.owned_vehicles[i].global_transform,others[i],"parked fleet does not move")
	for frame in 4: await physics_frame
	for frame in 60: heli._process(.1)
	check(not heli.is_processing(),"rotor clock switches off after wind-down")

func test_repeat_visits_preserve_city_and_release_all_four_vehicles() -> void:
	if not _setup(_house_city()): return
	view.buildings.rebuild(city,view.catalog)
	view.traffic.visible = false
	view.traffic.actors.clear()
	var saved := SaveFormat.encode_city(city).duplicate(true)
	for visit in 3:
		await physics_frame
		check(session.enter(city,Vector3(21,GROUND,22.5),visit%2==0))
		check_eq(session.owned_vehicles.size(),4,"fleet does not depend on ambient traffic")
		session.leave()
		check_eq(session.owned_vehicles.size(),0)
		check_eq(view.world.find_children("Explore*","CharacterBody3D",true,false).size(),0,"all session bodies released")
		check_eq(SaveFormat.encode_city(city),saved)

func test_house_choice_works_without_a_road_and_does_not_invent_one() -> void:
	var value := flat_city()
	value.stamp_building(20,20,Buildings.MAYORS_RESIDENCE)
	if not _setup(value): return
	view.buildings.rebuild(city,view.catalog)
	await physics_frame
	check(session.enter(city,Vector3(64,0,64),true),"safe ground-level house start does not need a road search result")
	check_eq(session.owned_vehicles.size(),4)
	check_eq(city.building.at(21,22),Buildings.NONE,"no connecting road is added")
	check(session._message.contains("no adjacent ground-level road"),"missing street access is explained")

func test_incremental_road_edit_turns_the_displayed_house_with_its_parking() -> void:
	if not _setup(_house_city()): return
	view.set_active(true)
	await process_frame
	await physics_frame
	var old: Node3D
	for lot: Node3D in view.buildings.get_children():
		if int(lot.get_meta("code",-1))==Buildings.MAYORS_RESIDENCE: old=lot
	check(old!=null)
	if old==null:return
	check_lt(absf(old.rotation.y),.001)
	for x in range(18,25):city.building.put(x,22,0)
	for y in range(18,25):city.building.put(22,y,30)
	view.refresh()
	await process_frame
	var turned: Node3D
	for lot: Node3D in view.buildings.get_children():
		if int(lot.get_meta("code",-1))==Buildings.MAYORS_RESIDENCE:turned=lot
	check(turned!=null)
	if turned==null:return
	check_lt(absf(angle_difference(turned.rotation.y,PI*.5)),.001,"incremental projection follows new eastern road")
	check_lt(absf(angle_difference(turned.rotation.y,ExploreMayorsHouse.find(city).yaw)),.001,"displayed model and parking share exact facing")

func test_six_side_garden_anchors_use_the_global_elevation_vegetation() -> void:
	for level in [4,10,22]:
		var value := flat_city(20000,level)
		value.vegetation = VegetationZones.make([true,true,true],[8,16])
		value.stamp_building(20,20,Buildings.MAYORS_RESIDENCE)
		if not _setup(value): return
		view.buildings.rebuild(city,view.catalog)
		var lot := view.buildings.get_child(0)
		var trees := lot.get_node_or_null("LotTrees")
		check(trees!=null,"house uses the existing shared planting projection")
		if trees==null:return
		check_eq(trees.get_child_count(),6,"exactly two side rows of three")
		var index := 0
		for x: float in [-12.2,12.2]:
			for z: float in [-11.5,-8.3,-5.1]:
				var tree := trees.get_child(index) as Node3D
				check(tree.position.is_equal_approx(Vector3(x,.21,z)/16.0),"approved garden anchor stays fixed")
				check(tree.has_node("PalmTrunk") if level==4 else tree.has_node("TreeTrunk"),"elevation replaces the global tree species")
				if level>4:
					var species: int = index%2 if level==10 else 2+index%2
					var expected := preload("res://scripts/view/city_conifer_3d.gd").create(species,(index/2)%3)
					check_eq((tree.get_child(0) as MeshInstance3D).mesh,(expected.get_child(0) as MeshInstance3D).mesh,"same shared global species mesh at this elevation")
					expected.free()
				index += 1
		await after_each()
