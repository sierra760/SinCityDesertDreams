# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/explore_session_case.gd"

func test_failure_keeps_aerial_owner_and_creates_no_actors() -> void:
	if not _setup(): return
	view.sample_chunks.clear()
	check(not session.enter(city,Vector3(22.5,GROUND,20.5)))
	check(not session.is_active())
	check(view.aerial_controls_enabled and view.camera.current)
	check_eq(view.world.find_children("Explore*","CharacterBody3D",true,false).size(),0)
	check_eq(Input.mouse_mode,Input.MOUSE_MODE_VISIBLE)

func test_enter_leave_is_repeatable_and_never_changes_city() -> void:
	if not _setup(): return
	var encoded := SaveFormat.encode_city(city).duplicate(true)
	for cycle in 2:
		if not await _enter(): return
		check(session.is_active() and not session.is_suspended())
		check(not view.aerial_controls_enabled)
		check(session.get("pedestrian") != null and session.get("car") != null and session.get("helicopter") != null)
		session.leave()
		check(view.aerial_controls_enabled and view.camera.current)
		check_eq(view.world.find_children("Explore*","CharacterBody3D",true,false).size(),0)
		check_eq(SaveFormat.encode_city(city),encoded)
		check_eq(Input.mouse_mode,Input.MOUSE_MODE_VISIBLE)

func test_boundary_spawn_keeps_all_actor_shapes_clear() -> void:
	var edge := flat_city()
	edge.building.put(0,0,30)
	if not _setup(edge): return
	view.sample_chunks = [CityGeometry3D.build_chunk(city,Rect2i(0,0,16,16))]
	if not await _enter(Vector3(.5,GROUND,.5)): return
	session.set_physics_process(false)
	var world: CityTraversalWorld3D = session.get("traversal")
	for actor: CharacterBody3D in [session.get("pedestrian"),session.get("car"),session.get("helicopter")]:
		check(is_instance_valid(actor),"all three actors find boundary parking")
		if not is_instance_valid(actor): continue
		var own_only: Array[RID] = [actor.get_rid()]
		var collider: CollisionShape3D
		for child: Node in actor.get_children():
			if child is CollisionShape3D: collider = child
		check(collider != null,"actor exposes its physical collision shape")
		if collider == null: continue
		check(world.has_clearance(collider.global_transform,collider.shape,own_only),"boundary spawn clears every other actor: "+actor.name)
		check(not world.support_near(actor.feet_position(),.01,.01,own_only).is_empty(),"boundary spawn has current dry support: "+actor.name)
		check(not world.touches_water(actor.feet_position()))

func test_edge_parked_helicopter_can_take_off_and_recover_without_bounds_loop() -> void:
	var edge := flat_city()
	edge.building.put(0,2,29)
	if not _setup(edge): return
	view.sample_chunks = [CityGeometry3D.build_chunk(city,Rect2i(0,0,16,16))]
	if not await _enter(Vector3(.77,GROUND,2.5)): return
	var helicopter: ExploreHelicopter = session.get("helicopter")
	check(helicopter != null,"edge neighborhood parks helicopter")
	if helicopter == null: return
	check_between(helicopter.global_position.x,.269,.271,"upright parked root is inside its physical box margin")
	var world: CityTraversalWorld3D = session.get("traversal")
	var exclude: Array[RID] = [helicopter.get_rid()]
	var collider := helicopter.get_child(0) as CollisionShape3D
	check(world.has_clearance(collider.global_transform,collider.shape,exclude),"edge helicopter shape clears city boundary")
	check(helicopter._inside(),"upright edge pose is admitted by movement")
	helicopter.rotation.y = PI*.25
	check(not helicopter._inside(),"same root cannot rotate its wider box outside the city")
	helicopter.rotation.y = 0.0
	var reports: Array[String] = []
	helicopter.recovery_requested.connect(func(reason: String) -> void: reports.append(reason))
	var pedestrian: CharacterBody3D = session.get("pedestrian")
	pedestrian.global_position = helicopter.global_position + Vector3(.30,0,0)
	check(session.request_interaction(),"player enters edge-parked helicopter")
	check_eq(session.get("occupied"),helicopter)
	session.handle_event(_key(KEY_Q,true))
	for tick in 20: await physics_frame
	session.handle_event(_key(KEY_Q,false))
	check_eq(reports,[] as Array[String],"legal edge takeoff never requests bounds recovery")
	check(helicopter.global_position.y > GROUND+.01,"edge helicopter genuinely ascends")
	session.suspend()
	check(session.recover(),"Recover lands the edge helicopter on its outdoor road")
	check_eq(Vector2i(floori(helicopter.global_position.x),floori(helicopter.global_position.z)),Vector2i(0,2),"recovered aircraft rests on the edge road tile")
	check(helicopter._inside(),"recovered root retains a legal boundary pose")
	session.resume()
	for tick in 4: await physics_frame
	check_eq(reports,[] as Array[String],"post-Recover movement does not repeat bounds rejection")

func test_pitched_car_revision_checks_actual_shape_and_recovery_resets_tilt() -> void:
	if not _setup() or not await _enter(): return
	session.set_physics_process(false)
	check(session.request_interaction())
	var car: CharacterBody3D = session.get("car")
	check_eq(session.get("occupied"),car)
	var world: CityTraversalWorld3D = session.get("traversal")
	var collider: CollisionShape3D
	for child: Node in car.get_children():
		if child is CollisionShape3D: collider = child
	if collider == null:
		check(false,"car physical shape exists")
		return
	# Synthetic post-slope chassis pose: raised root, pitched child collider.
	# Its forward roof enters an obstruction above the nominal upright box.
	var parked_y := car.global_position.y
	car.global_position.y += .08
	collider.basis = Basis(Vector3.RIGHT,deg_to_rad(30))
	collider.position = collider.basis.y*.04
	Fixture.box(view.world,Vector3(car.global_position.x,parked_y+.20,car.global_position.z-.10),Vector3(.04,.04,.04),ExploreActorProfile.OBSTACLE)
	await physics_frame
	var own_only: Array[RID] = [car.get_rid()]
	var nominal := car.global_transform
	nominal.origin.y += .04
	check(world.has_clearance(nominal,collider.shape,own_only),"nominal upright pose misses raised obstruction")
	check(not world.has_clearance(collider.global_transform,collider.shape,own_only),"actual pitched chassis intersects obstruction")
	check(not session._valid_actor(car,true),"revision validation uses actual chassis shape")
	session.suspend()
	check(session.recover(),"supported saved car pose can recover while suspended")
	check(collider.basis.is_equal_approx(Basis.IDENTITY),"recovery removes old chassis pitch")
	check(collider.position.is_equal_approx(Vector3(0,.04,0)),"recovery restores upright collider center")
	check(world.has_clearance(collider.global_transform,collider.shape,own_only),"actual recovered chassis clears current geometry")
	_check_supported_clear(car,1)
	check(session.is_suspended())

func test_held_entry_and_resume_wait_for_release_then_move() -> void:
	if not _setup(): return
	await _physical_key(KEY_W,true)
	if not await _enter(): return
	var actor: CharacterBody3D = session.get("occupied")
	var start := actor.global_position
	for tick in 20: await physics_frame
	check(actor.global_position.distance_to(start)<.005,"held entry key never starts movement")
	await _physical_key(KEY_W,false)
	for tick in 2: await physics_frame
	session.handle_event(_key(KEY_W,true))
	for tick in 30: await physics_frame
	check(actor.global_position.distance_to(start)>.02,"released and fresh input moves while simulation independent")
	session.suspend()
	check_eq(Input.mouse_mode,Input.MOUSE_MODE_VISIBLE)
	var paused := actor.global_position
	await _physical_key(KEY_W,true)
	session.resume()
	for tick in 20: await physics_frame
	check(actor.global_position.distance_to(paused)<.005,"resume requires physical key release")

func test_blocked_policy_is_checked_each_tick_and_requires_resume() -> void:
	if not _setup() or not await _enter(): return
	var blocked := [false]
	session.input_blocked = func() -> bool: return blocked[0]
	session.handle_event(_key(KEY_W,true))
	for tick in 10: await physics_frame
	blocked[0] = true
	await physics_frame
	check(session.is_suspended())
	check_eq(Input.mouse_mode,Input.MOUSE_MODE_VISIBLE)
	# A blocked tick suspends once; later blocked ticks do not redo the
	# suspension work (input reset, HUD reflow) every physics frame.
	session._held[KEY_Q] = false
	await physics_frame
	check(session._held.has(KEY_Q),"an already suspended session is not suspended again while blocked")
	session._held.clear()
	var actor: CharacterBody3D = session.get("occupied")
	var pose := actor.global_transform
	blocked[0] = false
	for tick in 10: await physics_frame
	check(session.is_suspended())
	check_eq(actor.global_transform,pose)
	session.resume()
	check(not session.is_suspended())

func test_nearest_vehicle_enter_and_clear_exit() -> void:
	if not _setup() or not await _enter(): return
	check(session.request_interaction())
	check_eq(session.get("mode"),ExploreActorProfile.Mode.DRIVE)
	var pedestrian: CharacterBody3D = session.get("pedestrian")
	var car: CharacterBody3D = session.get("car")
	check(not pedestrian.visible and pedestrian.collision_layer == 0)
	for tick in 3: await physics_frame
	check(session.request_interaction())
	check_eq(session.get("mode"),ExploreActorProfile.Mode.WALK)
	check(pedestrian.visible and pedestrian.collision_layer == ExploreActorProfile.ACTOR)
	check(pedestrian.global_position.distance_to(car.global_position)>.078)
	var traversal: CityTraversalWorld3D = session.get("traversal")
	var excludes: Array[RID] = [pedestrian.get_rid()]
	check(traversal.has_clearance(Transform3D(Basis.IDENTITY,pedestrian.global_position+Vector3.UP*.0575),ExploreActorProfile.shape(0),excludes))

func test_moving_car_and_blocked_exits_remain_occupied() -> void:
	if not _setup() or not await _enter(): return
	check(session.request_interaction())
	session.handle_event(_key(KEY_W,true))
	for tick in 30: await physics_frame
	var car: CharacterBody3D = session.get("car")
	check(absf(float(car.speed()))>.01)
	check(not session.request_interaction(),"moving car refuses exit")
	check_eq(session.get("occupied"),car)
	session.handle_event(_key(KEY_W,false))
	car.stop_input()
	session.set_physics_process(false)
	for offset: Vector3 in [Vector3(.12,.06,0),Vector3(-.12,.06,0),Vector3(0,.06,.20),Vector3(0,.06,-.20)]:
		Fixture.box(view.world,car.global_position+offset,Vector3(.08,.14,.08),16)
	await physics_frame
	check(not session.request_interaction(),"all four exit candidates blocked")
	check_eq(session.get("occupied"),car)

func test_flight_exit_waits_for_supported_landing() -> void:
	if not _setup() or not await _enter(): return
	var pedestrian: CharacterBody3D = session.get("pedestrian")
	var helicopter: CharacterBody3D = session.get("helicopter")
	pedestrian.global_position = helicopter.global_position+Vector3(.30,0,0)
	check(session.request_interaction())
	check_eq(session.get("mode"),ExploreActorProfile.Mode.FLY)
	session.handle_event(_key(KEY_Q,true))
	for tick in 35: await physics_frame
	check(not helicopter.landed())
	check(not session.request_interaction(),"airborne aircraft refuses exit")
	session.handle_event(_key(KEY_Q,false))
	session.handle_event(_key(KEY_E,true))
	for tick in 100: await physics_frame
	session.handle_event(_key(KEY_E,false))
	for tick in 30: await physics_frame
	check(helicopter.landed(),"descend reaches a supported floor")
	check(session.request_interaction())
	check_eq(session.get("mode"),ExploreActorProfile.Mode.WALK)

func test_revision_revalidates_occupied_and_parked_actors() -> void:
	if not _setup(Fixture.bridge_city()): return
	if not await _enter(Vector3(22.5,GROUND+.12,20.5)): return
	for x: int in range(20,24): city.building.put(x,20,0)
	view.networks.rebuild(city)
	view.sample_networks = view.networks.physical_data()
	view.sample_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,16,16))]
	view.revision += 1
	view.geometry_rebuilt.emit(view.revision)
	await physics_frame
	if not session.is_active(): return
	var world: CityTraversalWorld3D = session.get("traversal")
	check_eq(world.revision,view.revision)
	for actor: CharacterBody3D in [session.get("pedestrian"),session.get("car"),session.get("helicopter")]:
		if not is_instance_valid(actor): continue
		check(actor.global_position.is_finite())
		check(not world.touches_water(actor.feet_position()),"removed bridge recovery reaches dry support")

func test_never_occupied_parked_helicopter_recovers_removed_bridge() -> void:
	if not _setup(Fixture.bridge_city()) or not await _enter(Vector3(22.5,GROUND+.12,20.5)): return
	session.set_physics_process(false)
	var helicopter: CharacterBody3D = session.get("helicopter")
	check(helicopter != null,"bridge has helicopter parking")
	if helicopter == null: return
	_check_supported_clear(helicopter,2)
	var parked := helicopter.global_position
	var returned := [false]
	session.return_requested.connect(func() -> void: returned[0] = true)
	_remove_bridge_and_publish()
	session._physics_process(1.0/60.0)
	if returned[0]: return
	check(helicopter.global_position.distance_to(parked)>.01,"untouched parked aircraft cannot hover over removed bridge")
	_check_supported_clear(helicopter,2)

func test_occupied_genuine_flight_survives_support_revision() -> void:
	if not _setup() or not await _enter(): return
	var pedestrian: CharacterBody3D = session.get("pedestrian")
	var helicopter: CharacterBody3D = session.get("helicopter")
	pedestrian.global_position = helicopter.global_position+Vector3(.30,0,0)
	check(session.request_interaction())
	session.handle_event(_key(KEY_Q,true))
	for tick in 40: await physics_frame
	session.handle_event(_key(KEY_Q,false))
	for tick in 25: await physics_frame
	session.set_physics_process(false)
	var airborne := helicopter.global_position
	check(not helicopter.landed() and airborne.y>GROUND+.15,"ordinary occupied input produces genuine flight")
	view.revision += 1
	view.geometry_rebuilt.emit(view.revision)
	session._physics_process(1.0/60.0)
	check(helicopter.global_position.distance_to(airborne)<.01,"revision keeps genuinely airborne occupied aircraft aloft")
	check(not helicopter.landed())

func test_suspended_recover_rebuilds_removed_support_before_query() -> void:
	if not _setup(Fixture.bridge_city()) or not await _enter(Vector3(22.5,GROUND+.12,20.5)): return
	session.suspend()
	var actor: CharacterBody3D = session.get("occupied")
	var before := actor.global_position
	var world: CityTraversalWorld3D = session.get("traversal")
	var old_count := world.rebuild_count
	# Recover always targets outdoor pavement; supply a dry road off the bridge.
	city.building.put(26,23,30)
	_remove_bridge_and_publish()
	await physics_frame
	check(session.is_suspended())
	check(session.recover(),"visible Recover action succeeds without Resume")
	check_eq(Vector2i(floori(actor.global_position.x),floori(actor.global_position.z)),Vector2i(26,23),"Recover reaches the remaining outdoor road")
	check_eq(world.revision,view.revision,"Recover queries latest geometry revision")
	check_eq(world.rebuild_count,old_count+1,"pending geometry rebuilt once before recovery")
	check(actor.global_position.distance_to(before)>.01,"Recover leaves removed bridge pose")
	_check_supported_clear(actor,0)
	check(session.is_suspended(),"recovery preserves suspension")
	check_eq(Input.mouse_mode,Input.MOUSE_MODE_VISIBLE)

func test_recovery_revalidates_last_safe_floor_height() -> void:
	if not _setup() or not await _enter(): return
	session.set_physics_process(false)
	var actor: CharacterBody3D = session.get("pedestrian")
	var stale := actor.global_transform
	stale.origin.y += .06
	var safe: Dictionary = session.get("_last_safe")
	safe[actor.get_instance_id()] = stale
	actor.global_position = Vector3(25.5,GROUND+.2,25.5)
	check(session._recover_nearby(),"automatic recovery keeps the nearest supported floor")
	check(absf(actor.global_position.y-(GROUND+.042))<.003,"recovery uses current pavement support rather than hovering at stale height")

