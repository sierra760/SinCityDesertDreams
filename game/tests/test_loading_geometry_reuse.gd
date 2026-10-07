# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
var view: CityView3D
func after_each() -> void:
	if is_instance_valid(view): view.free()
	await process_frame

func _city() -> City:
	var city := flat_city()
	city.stamp_building(24,24,112)
	city.building.put(25,24,29)
	return city

func _clone(city: City) -> City:
	return SaveFormat.decode_city(SaveFormat.encode_city(city)).city

func _bind(city: City) -> void:
	view=CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)

func test_native_reload_reuses_only_exact_matching_projection() -> void:
	var city := _city()
	_bind(city)
	var old_lot := view.buildings.get_child(0).get_instance_id()
	var old_terrain := view.chunks.get_child(0).get_instance_id()
	var old_network: int = view.networks._regions[Vector2i(16,16)].get_instance_id()
	var original := view.traversal_snapshot()
	var revision := view._geometry_revision
	var next := _clone(city)
	next.name="Another city name"
	next.funds+=100
	next.day+=30
	next.flags.put(24,24,next.flags.at(24,24)|TileFlags.POWERED|TileFlags.WATERED)
	var before := SaveFormat.encode_city(next)
	view.bind_city(next)
	check_eq(view.buildings.get_child(0).get_instance_id(),old_lot,"same geometry retains the exact lot nodes")
	check_eq(view.chunks.get_child(0).get_instance_id(),old_terrain,"same geometry retains the exact terrain bodies")
	check_eq(view.networks._regions[Vector2i(16,16)].get_instance_id(),old_network,"same geometry retains the exact road meshes")
	check_eq(view._geometry_revision,revision,"same geometry retains its completed physical revision")
	check_eq(view.traversal_snapshot().networks,original.networks,"same geometry retains its resolved collision snapshot")
	check(view.traffic.graph.city==next and view.feedback.city==next and view.water_style._city==next,"live presentation owners bind the new City")
	check_eq(SaveFormat.encode_city(next),before,"retention never changes city/save data")

func test_changed_city_inputs_cannot_reuse_a_stale_projection() -> void:
	var city := _city()
	_bind(city)
	for kind: int in 6:
		var original := view.buildings.get_child(0).get_instance_id()
		var next := _clone(city)
		match kind:
			0: next.altitude.put(25,24,6)
			1: next.building.put(24,24,113)
			2: next.zone.put(24,24,2)
			3: next.flags.put(25,24,next.flags.at(25,24)|RotationMapper.AXIS_FLAG)
			4: next.flood_overlay[Vector2i(25,24)]=1
			5: next.terrain_surface=TerrainSurface.new(4)
		view.bind_city(next)
		check_ne(view.buildings.get_child(0).get_instance_id(),original,"changed altitude/building/zone/axis/flood/lattice uses a fresh projection: %d"%kind)
		check_eq(view.city,next)
		view.bind_city(city)

func test_actual_main_matching_native_reload_enters_with_new_city_owner() -> void:
	var host: GameHost = load("res://scenes/main.tscn").instantiate()
	host.preferences_path="user://test_loading_reuse.cfg"
	root.add_child(host)
	var city := _city()
	city.building.put(10,10,30)
	host.begin_city(city,{},4242,CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	view=host.city_view_3d
	var previous := view.traversal_snapshot()
	var old_lot := view.buildings.get_child(0).get_instance_id()
	var before := SaveFormat.encode_city(host.sim.city)
	host.save_path="user://test_loading_reuse.scity"
	check_eq(host.save_city(),OK)
	check(host.load_city(host.save_path),"Main restores its private native save")
	check_ne(host.sim.city,city,"native load creates a new numerical owner")
	check_eq(view.buildings.get_child(0).get_instance_id(),old_lot,"Main keeps identical geometry")
	check_eq(view.traversal_snapshot().revision,previous.revision)
	check_eq(view.traversal_snapshot().city,host.sim.city)
	view.set_center_cell(Vector2i(10,10))
	await physics_frame
	check(host.enter_explore(),"Explore enters after a matching native reload")
	if host.exploration.is_active():
		check_eq(host.exploration.traversal.revision,previous.revision)
		check_eq(view.traffic.graph.city,host.sim.city)
		host.return_to_build()
	check_eq(SaveFormat.encode_city(host.sim.city),before)
	host.sim._ctx.systems.clear();host.sim.systems.clear();host.free()
	view=null
	await process_frame
