# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/explore_session_case.gd"

var reports: Array[String] = []

func before_each() -> void:
	reports.clear()

func _house_city() -> City:
	var value := flat_city()
	value.stamp_building(20,20,Buildings.MAYORS_RESIDENCE)
	# Imported cities may contain another house; still only one mayoral fleet.
	value.stamp_building(26,26,Buildings.MAYORS_RESIDENCE)
	for x in range(18,30): value.building.put(x,22,30)
	return value

func test_one_mayormobile_replaces_house_car_and_menu_reuses_it() -> void:
	if not _setup(_house_city()): return
	view.buildings.rebuild(city,view.catalog)
	await physics_frame
	check(session.enter(city,Vector3(21,GROUND,22.5),true))
	session.set_physics_process(false)
	check_eq(session.owned_vehicles.size(),4,"replacement keeps the four parking spaces")
	check(session.car != null)
	if session.car == null: return
	check_eq(session.car.kind,&"mayormobile","the mayor's bay contains the unique SUV")
	var count := 0
	for vehicle in session.owned_vehicles:
		if vehicle is ExploreCar and vehicle.kind == &"mayormobile": count += 1
	check_eq(count,1,"duplicate houses never create a second SUV")
	var parked: Transform3D = session.car.global_transform
	session.pedestrian.global_position = parked.origin+Vector3(-.21,0,0)
	session.suspend()
	check(session.select_vehicle(&"mayormobile"),"menu boards the existing vehicle")
	check_eq(session.occupied,session.car)
	check_eq(session.car.global_transform,parked,"selection does not teleport the SUV")
	check(session.selected_vehicle == null,"selection creates no duplicate")

func test_menu_cannot_create_a_mayormobile_without_a_house() -> void:
	if not _setup(): return
	await physics_frame
	check(session.enter(city,Vector3(22.5,GROUND,20.5)))
	session.suspend()
	check(not session.select_vehicle(&"mayormobile"))
	check(session.car == null and session.selected_vehicle == null)
	check(not CityTrafficCatalog.is_vehicle_kind(&"mayormobile"),"unique SUV is outside ambient and mod traffic kinds")

func _vehicle(kind: StringName, at: Vector3) -> ExploreCar:
	var road := ExploreCar.new()
	view.world.add_child(road)
	road.bind(session.traversal)
	road.route_graph = view.traffic.graph
	road.recovery_requested.connect(func(reason: String) -> void: reports.append(reason))
	check(road.configure_kind(kind),"requested vehicle can be configured")
	road.apply_safe_pose(Transform3D(Basis.IDENTITY,at))
	session.owned_vehicles.append(road)
	return road

func _drive(road: ExploreCar, ticks: int) -> void:
	var forward := ExploreInputFrame.idle()
	forward.move = Vector2(0,-1)
	for tick in ticks:
		road.step(forward,0,1.0/60.0)
		await physics_frame

func test_only_mayormobile_drives_across_dry_offroad_ground() -> void:
	if not _setup(): return
	await physics_frame
	check(session.enter(city,Vector3(22.5,GROUND,20.5)))
	session.set_physics_process(false)
	var suv := _vehicle(&"mayormobile",Vector3(24.5,GROUND+.002,25.5))
	var ordinary := _vehicle(&"car",Vector3(26.5,GROUND+.002,25.5))
	await physics_frame
	await _drive(suv,150)
	await _drive(ordinary,150)
	check_lt(suv.global_position.z,24.0,"SUV physically crosses an unpaved tile boundary")
	check_gt(ordinary.global_position.z,25.4,"ordinary car remains road restricted")
	check(session._valid_actor(suv,true),"offroad SUV is a valid recoverable session actor")
	check_eq(CityTrafficCatalog.display_name(suv.kind),"Mayormobile")
	check(reports.is_empty(),"dry terrain does not request recovery")

func test_shoreline_stops_full_vehicle_before_water_in_forward_and_reverse() -> void:
	var value := flat_city()
	value.building.put(22,20,30)
	for x in range(23,27):
		value.terrain.put(x,23,Terrain.SUBMERGED)
		value.set_heights(x,23,2,4)
	if not _setup(value): return
	await physics_frame
	check(session.enter(city,Vector3(22.5,GROUND,20.5)))
	session.set_physics_process(false)
	var suv := _vehicle(&"mayormobile",Vector3(24.5,GROUND+.002,25.1))
	await physics_frame
	await _drive(suv,240)
	check_between(suv.global_position.z,24.14,24.45,"front bumper stops at dry shore")
	check(suv.on_drivable_ground() and suv.has_support())
	check(reports.is_empty(),"shoreline stops driving without relocating the player")
	var reverse := ExploreInputFrame.idle()
	reverse.move = Vector2(0,1)
	for tick in 90:
		suv.step(reverse,0,1.0/60.0)
		await physics_frame
	check_gt(suv.global_position.z,24.5,"driver can back away from water")
	# Back toward the same shore with the rear bumper; the full body rule is
	# symmetric and does not depend on the driver's direction of travel.
	suv.apply_safe_pose(Transform3D(Basis(Vector3.UP,PI),Vector3(25.5,GROUND+.002,24.7)))
	for tick in 180:
		suv.step(reverse,0,1.0/60.0)
		await physics_frame
	check_between(suv.global_position.z,24.14,24.4,"rear bumper also stops on dry ground")
	check(reports.is_empty())

func test_mayormobile_keeps_solid_obstacle_collisions() -> void:
	if not _setup(): return
	await physics_frame
	check(session.enter(city,Vector3(22.5,GROUND,20.5)))
	session.set_physics_process(false)
	var suv := _vehicle(&"mayormobile",Vector3(24.5,GROUND+.002,25.5))
	Fixture.box(view.world,Vector3(24.5,GROUND+.3,24.5),Vector3(1,.6,.15),ExploreActorProfile.OBSTACLE)
	await physics_frame
	await _drive(suv,180)
	check_between(suv.global_position.z,24.7,25.1,"SUV stops against an actual solid wall")
	check(suv.on_drivable_ground() and suv.has_support())

func test_mayormobile_climbs_and_descends_the_actual_dry_terrain_mesh() -> void:
	var value := flat_city()
	value.building.put(22,20,30)
	var surface := TerrainSurface.new(4)
	for x in range(24,28):
		for z in range(20,28): surface.set_vertex(x,z,12 if z<=25 else 8 if z==26 else 4)
	surface.project(value)
	if not _setup(value): return
	var saved := SaveFormat.encode_city(city).duplicate(true)
	await physics_frame
	check(session.enter(city,Vector3(22.5,GROUND,20.5)))
	session.set_physics_process(false)
	var suv := _vehicle(&"mayormobile",Vector3(25.5,GROUND+.002,27.5))
	await physics_frame
	# Speed is along the surface: two 68-degree tiles are over five tiles of
	# actual travel. Drive to the plateau, with a bounded ten-second deadline.
	var forward := ExploreInputFrame.idle()
	forward.move = Vector2(0,-1)
	for tick in 600:
		suv.step(forward,0,1.0/60.0)
		await physics_frame
		if suv.global_position.z<24.6: break
	suv.stop_input()
	for tick in 30:
		suv.step(ExploreInputFrame.idle(),0,1.0/60.0)
		await physics_frame
	check_lt(suv.global_position.z,24.9,"vehicle crosses both uphill tiles onto the plateau")
	check_between(suv.global_position.y,12*CityGeometry3D.HEIGHT-.01,12*CityGeometry3D.HEIGHT+.01,"vehicle physically gains eight terrain levels")
	check(session._valid_actor(suv),"plateau retains fresh support")
	suv.stop_input()
	var reverse := ExploreInputFrame.idle()
	reverse.move = Vector2(0,1)
	for tick in 1200:
		suv.step(reverse,0,1.0/60.0)
		await physics_frame
		if suv.global_position.z>26.25: break
	check_gt(suv.global_position.z,26.1,"vehicle backs down the hill")
	check_lt(suv.global_position.y,12*CityGeometry3D.HEIGHT-.03,"descent follows actual terrain height")
	check(reports.is_empty(),"hill is traversed without recovery or teleport")
	check_eq(SaveFormat.encode_city(city),saved,"offroad movement never edits terrain or city")

func test_suv_art_fits_its_body_and_all_four_wheels_animate_at_tire_radius() -> void:
	var visual := CityTrafficCatalog.make_detailed_visual(&"mayormobile")
	root.add_child(visual)
	visual.set_motion(.42/16.0,1.0,false)
	visual.advance_visual(.1)
	var phases: Dictionary = visual.debug_state().wheel_phases
	check_eq(phases.size(),4,"each authored road wheel has motion metadata")
	for name: String in phases:
		check_between(float(phases[name]),-.10001,-.09999,"physical 42 cm tires roll the measured distance")
		var wheel := visual.find_child(name,true,false) as Node3D
		if name.begins_with("WheelFront"): check(wheel.rotation.y>0,"front wheels steer")
		else: check(wheel.rotation.is_zero_approx(),"rear axle stays fixed")
	var envelope := CityTrafficCatalog.visual_bounds(&"mayormobile").grow(.00001)
	for part: Node in visual.find_children("*","MeshInstance3D",true,false):
		var mesh := part as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var fits := true
			for vertex: Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if not envelope.has_point(mesh.global_transform*vertex): fits = false
			check(fits,"visible model including steering fits physical body")
	visual.set_motion(-.42/16.0,0,false)
	visual.advance_visual(.1)
	for phase in visual.debug_state().wheel_phases.values(): check(absf(float(phase))<.00001,"reverse unwinds every tire")
	visual.free()

func test_bridge_over_water_remains_drivable_and_oblique_shore_contact_is_wet() -> void:
	if not _setup(Fixture.bridge_city()): return
	await physics_frame
	check(session.enter(city,Vector3(20.5,GROUND+.12,20.5)))
	session.set_physics_process(false)
	var suv := _vehicle(&"mayormobile",Vector3(22.5,GROUND+.122,20.5))
	await physics_frame
	check(suv.on_drivable_ground(),"bridge deck above the water is dry")
	var water := session.traversal as CityTraversalWorld3D
	# Inject no geometry: these checks use the same retained physical bridge
	# water polygons, comparing actual deck height to water contact height.
	var wet := Transform3D(Basis(Vector3.UP,PI*.25),Vector3(21.04,GROUND+.068,20.95))
	check(water.touches_water_footprint(wet,Vector3(.144,.1375,.319)),"rotated body intersects a wet corner even with dry centre")

func test_offroad_recovery_uses_checked_dry_safe_pose_far_from_roads() -> void:
	if not _setup(): return
	await physics_frame
	check(session.enter(city,Vector3(22.5,GROUND,20.5)))
	session.set_physics_process(false)
	var safe := Transform3D(Basis.IDENTITY,Vector3(30.5,GROUND+.002,30.5))
	var suv := _vehicle(&"mayormobile",safe.origin)
	await physics_frame
	check(session._valid_actor(suv),"far-offroad saved pose has actual dry support")
	session._last_safe[suv.get_instance_id()] = safe
	suv.global_position.y += .3
	check(not suv.has_support(),"reproduce lost support at a dry ledge")
	check(session._recover_actor(suv),"recovery uses dry safe ground without requiring a road")
	check_lt(suv.global_position.distance_to(safe.origin),.01,"existing SUV returns to checked safe pose")
	check_eq(session.owned_vehicles.size(),1,"recovery creates no duplicate")
