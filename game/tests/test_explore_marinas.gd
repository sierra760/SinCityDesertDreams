# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/vehicle_selection_case.gd"
const MarinaFixtureAccess := preload("res://scripts/exploration/explore_marina_access.gd")

func _marina_city(shore: Vector2i = Vector2i.RIGHT) -> City:
	var city := flat_city()
	for y: int in range(16,32):
		for x: int in range(16,36):
			if (x-21)*shore.x+(y-21)*shore.y>=1: continue
			city.terrain.put(x,y,Terrain.SUBMERGED)
			city.set_heights(x,y,2,4)
	city.stamp_building(20,20,Buildings.MARINA)
	return city

func _marina_setup(shore: Vector2i = Vector2i.RIGHT) -> bool:
	var origin := Vector3(21.5,4*CityGeometry3D.HEIGHT,21.5)+Vector3(shore.x,0,shore.y)*2
	if not await _setup(_marina_city(shore),origin): return false
	# Put only the pedestrian at the marina access; nearby parking must not
	# silently turn the marina action into car/helicopter boarding.
	session.pedestrian.global_position = origin+Vector3.UP*.002
	if is_instance_valid(session.car): session.car.global_position += Vector3(10,0,0)
	if is_instance_valid(session.helicopter): session.helicopter.global_position += Vector3(10,0,0)
	await physics_frame
	return true

func test_marina_interaction_launches_on_each_shore_without_editing_city() -> void:
	for shore: Vector2i in [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]:
		if not await _marina_setup(shore): return
		var before := SaveFormat.encode_city(view.city)
		session._publish_status()
		check(hud._prompt_label.text.contains("marina"),"nearby marina advertises boarding")
		check(session.request_interaction(),"launch at shore "+str(shore))
		check(session.occupied is ExploreRouteVehicle,"marina boards an actual boat")
		if session.occupied is ExploreRouteVehicle:
			check_eq(session.occupied.domain,&"water")
			check(session.occupied.has_support(),"whole hull has navigable water")
			check(session.occupied.global_position.distance_to(Vector3(21.5,session.occupied.global_position.y,21.5))<3.0,"launch belongs to this marina")
		check_eq(SaveFormat.encode_city(view.city),before)
		await after_each()

func test_marina_boat_drives_brakes_and_returns_to_its_dry_access() -> void:
	if not await _marina_setup(): return
	var landing := session.pedestrian.global_position
	check(session.request_interaction(),"marina launch")
	if not session.occupied is ExploreRouteVehicle: return
	var boat: ExploreRouteVehicle = session.occupied
	var berth := boat.global_transform
	var drive := ExploreInputFrame.idle()
	drive.move=Vector2(0,-1)
	for tick: int in 30: boat.step(drive,0,.1)
	check_gt(boat.global_position.distance_to(berth.origin),.1,"throttle moves boat")
	check(not session.request_interaction(),"moving boat cannot disembark")
	boat.stop_input()
	boat.global_position=Vector3(17.5,berth.origin.y,18.5)
	check(not session.request_interaction(),"open water has no pedestrian exit")
	check_eq(session.occupied,boat)
	boat.global_transform=berth
	await physics_frame
	check(session.request_interaction(),"stopped boat returns through marina access")
	check_eq(session.occupied,session.pedestrian)
	check(session.pedestrian.visible)
	check(session.pedestrian.global_position.distance_to(landing)<.05,"return uses supported dry access")
	check(not session.traversal.touches_water(session.pedestrian.global_position))

func test_marina_with_no_connected_outlet_does_not_use_distant_water() -> void:
	var city := flat_city()
	city.stamp_building(20,20,Buildings.MARINA)
	for x: int in range(20,22):
		for y: int in range(20,23):
			city.terrain.put(x,y,Terrain.SUBMERGED)
			city.set_heights(x,y,2,4)
	# A separate lake is within the generic vehicle picker's eight-tile radius.
	for x: int in range(26,30):
		for y: int in range(20,24):
			city.terrain.put(x,y,Terrain.SUBMERGED)
			city.set_heights(x,y,2,4)
	if not await _setup(city,Vector3(23.5,4*CityGeometry3D.HEIGHT,21.5)): return
	if is_instance_valid(session.car): session.car.global_position+=Vector3(10,0,0)
	if is_instance_valid(session.helicopter): session.helicopter.global_position+=Vector3(10,0,0)
	var before := SaveFormat.encode_city(city)
	check(not session.request_interaction(),"enclosed marina cannot launch into unrelated lake")
	check_eq(session.occupied,session.pedestrian)
	check(session._message.contains("marina"),"blocked launch explains the marina problem")
	check_eq(SaveFormat.encode_city(city),before)

func test_water_picker_at_marina_uses_its_berth_for_each_boat_kind() -> void:
	if not await _marina_setup(): return
	for kind: StringName in [&"ship",&"sailboat"]:
		session.suspend()
		check(session.select_vehicle(kind),"marina selection "+str(kind))
		if not session.occupied is ExploreRouteVehicle: return
		check_eq(session.occupied.kind,kind)
		check(session.occupied.has_support())
		session.resume()
		await physics_frame
		check(session.request_interaction(),"picker launch retains safe marina return")

func test_touch_interaction_launches_and_brake_stops_the_marina_boat() -> void:
	if not await _marina_setup(): return
	session.set_touch_controls_enabled(true)
	session._touch_hardware_quarantine.clear()
	var touch: ExploreTouchControls=hud.touch_controls
	var finger := InputEventScreenTouch.new()
	finger.index=0
	finger.position=touch.control_rect(&"interact").get_center()
	finger.pressed=true
	session.handle_event(finger)
	session._physics_process(.016)
	check(session.occupied is ExploreRouteVehicle,"touch Interact reaches marina boarding")
	if not session.occupied is ExploreRouteVehicle: return
	check_eq(session.mode,ExploreActorProfile.Mode.DRIVE)
	check_eq(touch.sample_frame().move,Vector2.ZERO,"boarding releases previous touch input")
	check(hud._prompt_label.text.contains("Interact"),"touch-friendly exit caption")
	finger.pressed=false
	session.handle_event(finger)
	var drive := ExploreInputFrame.idle()
	drive.move=Vector2(0,-1)
	for tick: int in 10: session.occupied.step(drive,0,.1)
	finger.index=1
	finger.position=touch.control_rect(&"brake").get_center()
	finger.pressed=true
	session.handle_event(finger)
	for tick: int in 10: session._physics_process(.1)
	check_eq(session.occupied.speed(),0.0,"touch brake stops boat")

func test_removed_marina_cannot_supply_a_remote_docking_exit() -> void:
	if not await _marina_setup(): return
	check(session.request_interaction())
	if not session.occupied is ExploreRouteVehicle: return
	view.city.clear_footprint(20,20)
	_refresh_fixture_geometry()
	await physics_frame
	check(not session.request_interaction(),"removed marina invalidates remembered access")
	check(session.occupied is ExploreRouteVehicle)

func test_distant_marina_never_advertises_or_boards_from_land() -> void:
	if not await _marina_setup(): return
	session.pedestrian.global_position+=Vector3(3,0,0)
	session._ambient_prompt_at=0
	session._publish_status()
	check(not hud._prompt_label.text.contains("marina"),"marina action stays local")
	check(not session.request_interaction())
	check_eq(session.occupied,session.pedestrian)

func test_marina_raised_bank_can_launch_and_return_through_its_landing() -> void:
	var city := _marina_city()
	for y: int in range(16,32):
		for x: int in range(22,36): city.set_heights(x,y,5,0)
	if not await _setup(city,Vector3(23.5,5*CityGeometry3D.HEIGHT,21.5)): return
	if is_instance_valid(session.car): session.car.global_position+=Vector3(10,0,0)
	if is_instance_valid(session.helicopter): session.helicopter.global_position+=Vector3(10,0,0)
	check(session.request_interaction(),"marina gangway connects the raised shore to its water berth")
	if not session.occupied is ExploreRouteVehicle: return
	await physics_frame
	check(session.request_interaction(),"marina returns to the supported raised landing")
	check_eq(session.occupied,session.pedestrian)
	check_gt(session.pedestrian.global_position.y,5*CityGeometry3D.HEIGHT)

func test_physically_blocked_berths_do_not_replace_the_walker() -> void:
	if not await _marina_setup(): return
	var wall := StaticBody3D.new()
	wall.collision_layer=ExploreActorProfile.OBSTACLE
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(5,1,5)
	shape.shape=box
	wall.add_child(shape)
	view.world.add_child(wall)
	wall.global_position=Vector3(21.5,4*CityGeometry3D.HEIGHT+.5,21.5)
	await physics_frame
	var before := session.pedestrian.global_transform
	check(not session.request_interaction(),"all berths are physically obstructed")
	check_eq(session.occupied,session.pedestrian)
	check_eq(session.pedestrian.global_transform,before)
	check(session.pedestrian.visible)
	wall.free()

func test_marina_does_not_treat_a_high_cliff_as_a_landing() -> void:
	var city := _marina_city()
	for y: int in range(16,32):
		for x: int in range(22,36): city.set_heights(x,y,8,0)
	if not await _setup(city,Vector3(23.5,8*CityGeometry3D.HEIGHT,21.5)): return
	if is_instance_valid(session.car): session.car.global_position+=Vector3(10,0,0)
	if is_instance_valid(session.helicopter): session.helicopter.global_position+=Vector3(10,0,0)
	check(not session.request_interaction(),"cliff access stays unavailable")
	check_eq(session.occupied,session.pedestrian)

func test_obstructed_landing_refuses_docking_until_the_shore_is_clear() -> void:
	if not await _marina_setup(): return
	check(session.request_interaction())
	if not session.occupied is ExploreRouteVehicle: return
	var wall := StaticBody3D.new()
	wall.collision_layer=ExploreActorProfile.OBSTACLE
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=Vector3(2,1,5)
	shape.shape=box
	wall.add_child(shape)
	view.world.add_child(wall)
	wall.global_position=Vector3(23.5,4*CityGeometry3D.HEIGHT+.5,21.5)
	await physics_frame
	check(not session.request_interaction(),"blocked dry access keeps player in boat")
	check(session.occupied is ExploreRouteVehicle)
	wall.free()
	await physics_frame
	check(session.request_interaction(),"clearing the physical obstruction restores docking")
	check_eq(session.occupied,session.pedestrian)

func test_destination_marina_docks_on_the_actual_sloped_bank_floor() -> void:
	var city := _marina_city()
	for y: int in range(20,23): city.terrain.put(23,y,Terrain.SLOPE_E)
	# The only dry outside access is the sloped east bank.
	for y: int in [19,23]:
		city.terrain.put(22,y,Terrain.SUBMERGED)
		city.set_heights(22,y,2,4)
	var surface := TerrainSurface.from_city(city)
	for y: int in range(20,24):
		surface.set_vertex(23,y,4)
		surface.set_vertex(24,y,5)
	surface.project(city)
	var sampled := false
	for point: Vector3 in MarinaFixtureAccess.landings(city,Rect2i(20,20,3,3)):
		if absf(point.x-23.18)<.00001 and absf(point.z-21.5)<.00001:
			sampled=true
			check(absf(point.y-4.18*CityGeometry3D.HEIGHT)<.00001,"landing samples the actual .18 bank offset, not the center")
	check(sampled,"destination exposes the intended bank landing")
	if not await _setup(city,Vector3(28.5,4*CityGeometry3D.HEIGHT,21.5)): return
	session.pedestrian.global_position=Vector3(23.5,4.5*CityGeometry3D.HEIGHT+.002,21.5)
	if is_instance_valid(session.car): session.car.global_position+=Vector3(10,0,0)
	if is_instance_valid(session.helicopter): session.helicopter.global_position+=Vector3(10,0,0)
	check(session.request_interaction(),"launch from supported sloped bank")
	if not session.occupied is ExploreRouteVehicle: return
	# A boat arriving here has no remembered departure pose.
	session._marina_dock.clear()
	await physics_frame
	check(session.request_interaction(),"destination docking samples bank at the landing's actual x/z")
	check_eq(session.occupied,session.pedestrian)
	if session.occupied==session.pedestrian:
		check_gt(session.pedestrian.global_position.x,23.0)
		check_lt(session.pedestrian.global_position.y,4.3*CityGeometry3D.HEIGHT)

func test_marina_boat_accelerates_at_sixty_physics_ticks_per_second() -> void:
	if not await _marina_setup(): return
	check(session.request_interaction())
	if not session.occupied is ExploreRouteVehicle: return
	var before := session.occupied.global_position
	var drive := ExploreInputFrame.idle()
	drive.move=Vector2(0,-1)
	for tick: int in 120: session.occupied.step(drive,0,1.0/60.0)
	check_gt(session.occupied.global_position.distance_to(before),.1,"small valid motion must accumulate into normal boat speed")
	check_gt(session.occupied.speed(),.1,"acceleration survives small physics steps")
