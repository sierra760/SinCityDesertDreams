# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
const MainScene := preload("res://scenes/main.tscn")
var host: GameHost

func after_each() -> void:
	if host != null:
		host.sim._ctx.systems.clear()
		host.sim.systems.clear()
		host.sim._system_index.clear()
		host.free()
		host = null
	await process_frame

func start_host(size: Vector2i) -> City:
	root.size = size
	host = MainScene.instantiate()
	host.preferences_path = "user://underground-water-host.cfg"
	root.add_child(host)
	host.display_layout.set_ui_scale(100)
	root.size = size
	if size.x < 600:
		host.display_layout.refresh_with_mobile_metrics(size,1.0,Rect2i(0,24,size.x,size.y-48))
	else:
		host.display_layout.refresh_with_metrics(size,1.0)
	var city := flat_city(100000)
	city.founded_year = 2000
	city.stamp_building(60,60,Buildings.COAL_PLANT)
	city.stamp_building(64,60,Buildings.WATER_PUMP)
	city.stamp_building(70,60,Buildings.RES_1X1_FIRST)
	city.building.put(67,60,Buildings.ROAD_FIRST)
	host.begin_city(city,{},7,null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	return city

func test_pipe_drag_query_bulldoze_and_rejoin_through_the_game_host() -> void:
	var city := start_host(Vector2i(1280,800))
	host.select_tool(Tools.Kind.WATER_PIPE)
	check(host.presentation.is_underground())
	var built := host.handle_drag(Vector2i(65,60),Vector2i(69,60))
	check(built.applied)
	check(city.is_watered(70,60))
	for frame in 3: await process_frame
	var renderer := host.city_view_3d.underground
	check(renderer.visible and renderer.mesh_instance.mesh != null)
	var mesh := renderer.mesh_instance.mesh
	host.open_query(Vector2i(64,60))
	check(host.query_panel.info.get("Building","").contains("Pump"),"pump is identifiable underground")
	host.query_panel.close()
	host.select_tool(Tools.Kind.BULLDOZE)
	check(host.presentation.is_underground())
	check(host.handle_drag(Vector2i(67,60),Vector2i(67,60)).applied)
	check_eq(city.building_at(67,60),Buildings.ROAD_FIRST)
	check(not city.is_watered(70,60))
	for frame in 3: await process_frame
	check_ne(renderer.mesh_instance.mesh,mesh,"pipe removal refreshes visible service")
	host.select_tool(Tools.Kind.WATER_PIPE)
	check(host.handle_drag(Vector2i(67,60),Vector2i(67,60)).applied)
	check(city.is_watered(70,60))
	host.select_tool(Tools.Kind.ROAD)
	check(not host.presentation.is_underground())

func test_underground_key_is_visible_on_desktop_and_phone_without_blocking_map_input() -> void:
	start_host(Vector2i(390,844))
	host.select_tool(Tools.Kind.WATER_PIPE)
	for frame in 4: await process_frame
	var legend := host.city_view_3d.get_node_or_null("UndergroundLegend") as Label
	check(legend != null,"underground supplies an on-screen color and facility key")
	if legend == null: return
	check(legend.visible)
	check_eq(legend.mouse_filter,Control.MOUSE_FILTER_IGNORE,"legend cannot consume map gestures")
	check(legend.text.to_lower().contains("blue") and legend.text.to_lower().contains("dry"))
	var usable := host.display_layout.logical_rect()
	check(usable.encloses(legend.get_global_rect()),"legend fits phone usable area")
	host.presentation.set_view_mode(CityPresentationController.ViewMode.SURFACE)
	check(not legend.visible,"key disappears with underground view")
	root.size = Vector2i(1280,800)
	host.display_layout.refresh_with_metrics(root.size,1.0)
	host.presentation.set_view_mode(CityPresentationController.ViewMode.UNDERGROUND)
	for frame in 4: await process_frame
	check(host.display_layout.logical_rect().encloses(legend.get_global_rect()),"legend fits desktop usable area")
