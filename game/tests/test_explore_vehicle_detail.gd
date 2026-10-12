# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/vehicle_selection_case.gd"

func check_detail(actor: CharacterBody3D, kind: StringName) -> void:
	check(actor._visual is ExploreActorVisual,"driven "+String(kind)+" exposes its owned detailed animation")
	if not actor._visual is ExploreActorVisual: return
	var visual: ExploreActorVisual = actor._visual
	check(visual.find_children("*","MeshInstance3D",true,false).size()>1,"driven "+String(kind)+" retains separate detailed parts")
	check(visual.find_child("CatalogModel",true,false)==null,"driven actor does not use a merged traffic mesh")
	if CityTrafficCatalog.domain(kind)==&"road" or kind==&"train":
		check(not visual.debug_state().wheel_phases.is_empty() or visual.find_child("WheelFrontLeft",true,false)!=null,"driven wheels remain articulated")

func test_every_menu_road_vehicle_uses_detail_and_motion() -> void:
	var city := flat_city()
	for x in range(18,34): city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	if not await _setup(city): return
	for kind: StringName in CityTrafficCatalog.vehicle_kinds():
		if CityTrafficCatalog.domain(kind)!=&"road": continue
		session.suspend()
		check(session.select_vehicle(kind),"menu selects "+String(kind))
		if session.occupied==session.pedestrian: continue
		var actor: ExploreCar=session.occupied
		check_detail(actor,kind)
		check_eq(actor.vehicle_size(),CityTrafficCatalog.dimensions(kind),"detail preserves physical size")
		session.resume()
		await physics_frame
		var before: Dictionary=actor._visual.debug_state()
		var frame:=ExploreInputFrame.idle()
		frame.move=Vector2(0,-1)
		actor.step(frame,0,.016)
		check(actor._visual.debug_state().wheel_phase!=before.wheel_phase,"owner motion advances detailed wheels")
		actor.stop_input()
		check(session.request_interaction(),"exit remains supported")

func test_menu_train_uses_detail_and_owner_clock() -> void:
	var city:=TransitFixtures.rail_city()
	if not await _setup(city,Vector3(20.5,2.5,20.8)): return
	session.pedestrian.global_position=session.transit_service.network.stations[0].platform+Vector3.UP*.003
	session.suspend()
	check(session.select_vehicle(&"train"))
	if session.occupied==session.pedestrian: return
	var actor: ExploreRouteVehicle=session.occupied
	check_detail(actor,&"train")
	if not actor._visual is ExploreActorVisual: return
	var visual: ExploreActorVisual=actor._visual
	var before:=visual.debug_state()
	for i in 3: await process_frame
	check_eq(visual.debug_state(),before,"render frames keep driven train frozen")
	var frame:=ExploreInputFrame.idle()
	frame.move=Vector2(0,-1)
	actor.step(frame,0,.1)
	check(visual.debug_state().wheel_phases!=before.wheel_phases,"driving advances authored train wheels")
	before=visual.debug_state()
	actor.step(frame,0,0)
	check_eq(visual.debug_state(),before,"zero delta does not animate")
	actor.stop_input()
	check_eq(visual.debug_state().speed,0.0,"stopping input stops visual motion")

func test_menu_water_vehicles_keep_detailed_hulls() -> void:
	var city:=flat_city()
	for y in range(20,24):
		for x in range(20,24):
			city.terrain.put(x,y,Terrain.SUBMERGED)
			city.set_heights(x,y,2,4)
	if not await _setup(city,Vector3(24.5,2.5,21.5)): return
	for kind: StringName in [&"ship",&"sailboat"]:
		session.suspend()
		check(session.select_vehicle(kind))
		if session.occupied==session.pedestrian: continue
		check_detail(session.occupied,kind)
		check_eq(session.occupied.vehicle_size(),CityTrafficCatalog.dimensions(kind))
		check(session.recover(),"return to the supported roadside walker")
