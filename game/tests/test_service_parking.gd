# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/explore_session_case.gd"

func _service_city(code: int, front: Vector2i = Vector2i.DOWN) -> City:
	var value := flat_city()
	value.stamp_building(20,20,code)
	for i in range(18,26):
		var cell := Vector2i(i,23) if front == Vector2i.DOWN else Vector2i(i,19) if front == Vector2i.UP else Vector2i(23,i) if front == Vector2i.RIGHT else Vector2i(19,i)
		value.building.putv(cell,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10 if front.y != 0 else 5))
	return value

func _slots() -> Array[Node]:
	return view.buildings.find_children("ServiceSlot*","Node3D",true,false)

func test_service_lots_supply_static_shared_vehicles_without_actors() -> void:
	for pair: Array in [[209,1,"ambulance"],[210,2,"police"],[211,2,"fire_engine"]]:
		if not _setup(_service_city(pair[0])): return
		view.buildings.rebuild(city,view.catalog)
		view.traffic.visible = false
		view.traffic.actors.clear()
		var slots := _slots()
		check_eq(slots.size(),pair[1],"each service lot has its appropriate fleet")
		if slots.is_empty(): return
		var first_mesh: Mesh
		for slot: Node3D in slots:
			check_eq(String(slot.get_meta("kind","")),pair[2])
			check(not slot.is_processing() and not slot.is_physics_processing(),"static parking has no clock")
			var mesh := slot.get_node("Vehicle") as MeshInstance3D
			if first_mesh == null: first_mesh = mesh.mesh
			check_eq(mesh.mesh,first_mesh,"repeated vehicles share their mesh")
		check_eq(view.world.find_children("*","CharacterBody3D",true,false).size(),0,"parking creates no driven actors")
		await physics_frame
		check(session.enter(city,Vector3(21.5,GROUND,23.5)))
		check_eq(session.owned_vehicles.size(),0,"unvisited service parking remains static in Explore")
		await after_each()

func test_every_street_facing_has_boardable_parking_and_bounded_driveway() -> void:
	for code in [209,210,211]:
		for front: Vector2i in [Vector2i.DOWN,Vector2i.RIGHT,Vector2i.UP,Vector2i.LEFT]:
			if not _setup(_service_city(code,front)): return
			view.buildings.rebuild(city,view.catalog)
			await physics_frame
			var entry := Vector3(21.5,GROUND,21.5)+Vector3(front.x,0,front.y)*2.0
			check(session.enter(city,entry))
			session.set_physics_process(false)
			var slots := _slots()
			check(not slots.is_empty())
			if slots.is_empty(): return
			var slot: Node3D = slots[0]
			var forward := -slot.global_basis.z
			check_gt(forward.dot(Vector3(front.x,0,front.y)),.999,"parking follows the actual adjoining street")
			session.pedestrian.global_position = slot.global_position+slot.global_basis.x*.22
			session.suspend()
			check(session.select_vehicle(slot.get_meta("kind")),"paused menu boards the actual nearby service vehicle")
			var actor := session.occupied as ExploreCar
			check(actor!=null)
			if actor == null: return
			check(session._valid_actor(actor,true),"full vehicle support and clearance in every facing")
			var parked := actor.global_transform
			var outside := parked
			outside.origin = Vector3(21.5,parked.origin.y,21.5)-Vector3(front.x,0,front.y)*2.0
			actor.apply_safe_pose(outside)
			check(not actor.on_drivable_ground(),"service driveway never grants general off-road driving")
			actor.apply_safe_pose(parked)
			var drive := ExploreInputFrame.idle()
			drive.move = Vector2(0,-1)
			for tick in 130:
				actor.step(drive,0,1.0/60.0)
				await physics_frame
			var center := Vector3(21.5,actor.global_position.y,21.5)
			check_gt((actor.global_position-center).dot(Vector3(front.x,0,front.y)),1.6,"every facing can physically reach the street")
			actor.stop_input()
			drive.move = Vector2(0,1)
			# Reverse is intentionally slower than forward driving (.3 tiles/s).
			for tick in 250:
				actor.step(drive,0,1.0/60.0)
				await physics_frame
			check_lt((actor.global_position-center).dot(Vector3(front.x,0,front.y)),1.4,"every facing can return to its forecourt")
			await after_each()

func test_menu_reenters_the_nearby_acquired_vehicle_when_two_share_a_kind() -> void:
	for code in [210,211]:
		if not _setup(_service_city(code)): return
		view.buildings.rebuild(city,view.catalog)
		await physics_frame
		check(session.enter(city,Vector3(21.5,GROUND,23.5)))
		session.set_physics_process(false)
		var slots := _slots()
		check_eq(slots.size(),2)
		if slots.size() != 2: return
		for slot: Node3D in slots:
			session.pedestrian.global_position = slot.global_position+slot.global_basis.x*.22
			check(session.request_interaction())
			check(session.request_interaction(),"exit each acquired vehicle")
		var second: CharacterBody3D = session.owned_vehicles[1]
		session.pedestrian.global_position = second.global_position+second.global_basis.x*.22
		session.suspend()
		check(session.select_vehicle(second.kind),"a distant first cruiser/engine never blocks the nearby second one")
		check_eq(session.occupied,second)
		await after_each()

func test_obstructed_slot_refuses_boarding_and_restores_its_static_body() -> void:
	if not _setup(_service_city(211)): return
	view.buildings.rebuild(city,view.catalog)
	await physics_frame
	check(session.enter(city,Vector3(21.5,GROUND,23.5)))
	session.set_physics_process(false)
	var slots := _slots()
	check(not slots.is_empty())
	if slots.is_empty(): return
	var slot: Node3D = slots[0]
	Fixture.box(view.world,slot.global_position+Vector3.UP*.08,Vector3(.10,.14,.12),ExploreActorProfile.OBSTACLE)
	session.pedestrian.global_position = slot.global_position+slot.global_basis.x*.22
	await physics_frame
	check(not session.request_interaction(),"a blocked actual parking space cannot materialize its driver")
	check_eq(session.occupied,session.pedestrian)
	check_eq(session.owned_vehicles.size(),0)
	check_eq((slot.get_node("Body") as StaticBody3D).collision_layer,4)
	check(not slot.get_meta("claimed",false))

func test_walker_pressed_against_a_parked_vehicle_can_board_it() -> void:
	for code in [209,210,211]:
		if not _setup(_service_city(code)): return
		view.buildings.rebuild(city,view.catalog)
		await physics_frame
		check(session.enter(city,Vector3(21.5,GROUND,23.5)))
		session.set_physics_process(false)
		var slots := _slots()
		check(not slots.is_empty())
		if slots.is_empty(): return
		var slot: Node3D = slots[0]
		for side: float in [1.0,-1.0]:
			# Start beside the vehicle and walk straight into its flank.
			session.pedestrian.place(Transform3D(Basis.IDENTITY,slot.global_position+slot.global_basis.x*.16*side))
			await physics_frame
			var frame := ExploreInputFrame.idle()
			var toward: Vector3 = -slot.global_basis.x*side
			frame.move = Vector2(toward.x,toward.z)
			for tick in 90:
				session.pedestrian.step(frame,0.0,1.0/60.0)
				await physics_frame
			var found := CityServiceParking.nearest(view.buildings,session.pedestrian.global_position,.25)
			check(not found.is_empty(),"the walker reached the vehicle")
			if found.is_empty(): return
			check_lt(float(found.gap),.004,"the walker is touching the vehicle")
			check(session.request_interaction(),"a walker touching the vehicle is not its obstruction")
			check(session.occupied is ExploreCar)
			if not session.occupied is ExploreCar: return
			check_eq(session.occupied.global_transform,slot.global_transform,"boarding keeps the parked pose")
			check(session.request_interaction(),"the driver can step out again")
			check_eq(session.occupied,session.pedestrian)
			if side > 0:
				# Hand the vehicle back so the other flank is tried from static parking.
				session.leave()
				await physics_frame
				check(session.enter(city,Vector3(21.5,GROUND,23.5)))
				session.set_physics_process(false)
		await after_each()

func test_boarding_with_a_movement_key_held_keeps_explore_running() -> void:
	if not _setup(_service_city(210)): return
	view.buildings.rebuild(city,view.catalog)
	await physics_frame
	check(session.enter(city,Vector3(21.5,GROUND,23.5)))
	var slots := _slots()
	check(not slots.is_empty())
	if slots.is_empty(): return
	var slot: Node3D = slots[0]
	for tick in 3: await physics_frame
	session.pedestrian.place(Transform3D(Basis.IDENTITY,slot.global_position+slot.global_basis.x*.22))
	await _physical_key(KEY_W,true)
	session.handle_event(_key(KEY_W,true))
	check(session.request_interaction(),"boards with the walking key still down")
	var vehicle := session.occupied as ExploreCar
	check(vehicle != null)
	if vehicle == null: return
	var parked := vehicle.global_position
	var published: Array[int] = [0]
	session.status_changed.connect(func(_status: Dictionary) -> void: published[0] += 1)
	var camera_before: Transform3D = session.camera_rig.camera.global_transform
	for tick in 12: await physics_frame
	check_gt(published[0],8,"Explore keeps running while the key is still down")
	check(not session.camera_rig.camera.global_transform.is_equal_approx(camera_before),"the camera settles behind the vehicle")
	check_lt(vehicle.global_position.distance_to(parked),.002,"the key held since before boarding does not drive the vehicle")
	await _physical_key(KEY_W,false)
	session.handle_event(_key(KEY_W,false))
	for tick in 3: await physics_frame
	await _physical_key(KEY_W,true)
	session.handle_event(_key(KEY_W,true))
	for tick in 40: await physics_frame
	check_gt(vehicle.global_position.distance_to(parked),.02,"a fresh press drives")

func test_incremental_replacement_moves_interaction_to_the_new_lot_only() -> void:
	if not _setup(_service_city(210)): return
	view.buildings.rebuild(city,view.catalog)
	var old_slots := _slots()
	check_eq(old_slots.size(),2)
	if old_slots.size()!=2: return
	var old_feet := (old_slots[0] as Node3D).global_position+Vector3(.2,0,0)
	check(not CityServiceParking.nearest(view.buildings,old_feet,.25).is_empty())
	city.clear_footprint(20,20)
	city.stamp_building(25,20,211)
	view.buildings.update_regions(city,view.catalog,[Rect2i(20,20,8,3)])
	check(CityServiceParking.nearest(view.buildings,old_feet,.25).is_empty(),"removed parking is no longer reachable")
	var replacements := _slots()
	check_eq(replacements.size(),2)
	if replacements.size()!=2: return
	var new_feet := (replacements[0] as Node3D).global_position+Vector3(.2,0,0)
	var found := CityServiceParking.nearest(view.buildings,new_feet,.25)
	check(not found.is_empty(),"new service parking joins the local interaction lookup")
	if not found.is_empty(): check_eq(found.service.get_meta("kind"),&"fire_engine")
	view.buildings.clear()
	check(CityServiceParking.nearest(view.buildings,new_feet,.25).is_empty(),"clearing the projection releases all parking entries")

func test_claim_rebinds_on_projection_replacement_and_releases_on_demolition() -> void:
	if not _setup(_service_city(210)): return
	view.buildings.rebuild(city,view.catalog)
	await physics_frame
	check(session.enter(city,Vector3(21.5,GROUND,23.5)))
	session.set_physics_process(false)
	var slots := _slots()
	check(not slots.is_empty())
	if slots.is_empty(): return
	var slot: Node3D = slots[0]
	session.pedestrian.global_position = slot.global_position+slot.global_basis.x*.22
	check(session.request_interaction())
	var actor := session.occupied as ExploreCar
	check(actor!=null)
	if actor == null: return
	var start := actor.global_transform
	view.buildings.rebuild(city,view.catalog)
	session._on_geometry_rebuilt(2)
	check(session._reconcile_revision())
	var replacement: Node3D = _slots()[0]
	check(replacement != slot,"a new projected lot replaces the original")
	check_eq((replacement.get_node("Body") as StaticBody3D).collision_layer,0,"replacement slot remains claimed")
	check_eq(actor.global_transform,start,"refresh does not move the driven car")
	check_eq(session.owned_vehicles.size(),1)
	# Removing the building revokes its forecourt immediately, even before refresh.
	city.clear_footprint(20,20)
	check(not actor.on_drivable_ground(),"demolition revokes the driveway")
	view.buildings.rebuild(city,view.catalog)
	session._on_geometry_rebuilt(3)
	check(session._reconcile_revision(),"removed forecourt recovers its driver to a real road")
	check(actor.on_drivable_ground())
	check(actor.service_driveway.is_empty())
	session.leave()
	check_eq(_slots().size(),0,"demolition cannot resurrect a parked copy")

func test_board_drive_exit_and_return_preserve_city_and_do_not_duplicate() -> void:
	for code in [209,210,211]:
		if not _setup(_service_city(code)): return
		view.buildings.rebuild(city,view.catalog)
		var saved := SaveFormat.encode_city(city).duplicate(true)
		await physics_frame
		check(session.enter(city,Vector3(21.5,GROUND,23.5)))
		session.set_physics_process(false)
		var slots := _slots()
		check(not slots.is_empty(),"a real static service vehicle exists")
		if slots.is_empty(): return
		var slot: Node3D = slots[0]
		var at := slot.global_transform
		session.pedestrian.global_position = at.origin+at.basis.x*.22
		check(session.request_interaction(),"walk up and board the service vehicle")
		var vehicle := session.occupied as ExploreCar
		check(vehicle != null,"service parking supplies a real ExploreCar")
		if vehicle == null: return
		check_eq(vehicle.global_transform,at,"boarding preserves exact parked pose")
		check_eq((slot.get_node("Body") as StaticBody3D).collision_layer,0,"static collision leaves with its occupant")
		check(vehicle.on_drivable_ground(),"forecourt is drivable")
		var forward := ExploreInputFrame.idle()
		forward.move = Vector2(0,-1)
		for tick in 130:
			vehicle.step(forward,0,1.0/60.0)
			await physics_frame
		check_gt(vehicle.global_position.z,23.1,"vehicle actually drives out onto the street")
		vehicle.stop_input()
		check(session.request_interaction(),"driver exits safely")
		var parked := vehicle.global_transform
		check(session.request_interaction(),"driver boards the same parked vehicle again")
		check_eq(session.occupied,vehicle)
		check_eq(vehicle.global_transform,parked)
		check_eq(session.owned_vehicles.size(),1,"one actor for the vehicle actually acquired")
		session.leave()
		check_eq((slot.get_node("Body") as StaticBody3D).collision_layer,4,"static parking restores on leaving Explore")
		check_eq(view.world.find_children("*","CharacterBody3D",true,false).size(),0)
		check_eq(SaveFormat.encode_city(city),saved,"service parking never changes saved city data")
		await physics_frame
		check(session.enter(city,Vector3(21.5,GROUND,23.5)),"a second visit uses the restored static fleet")
		session.set_physics_process(false)
		session.pedestrian.global_position = at.origin+at.basis.x*.22
		check(session.request_interaction(),"the same slot can be acquired on another visit")
		check_eq(session.owned_vehicles.size(),1)
		session.leave()
		check_eq((slot.get_node("Body") as StaticBody3D).collision_layer,4)
		check_eq(SaveFormat.encode_city(city),saved)
		await after_each()
