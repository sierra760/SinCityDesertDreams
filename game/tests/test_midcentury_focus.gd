# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func settle() -> void:
	for frame in 8: await process_frame

func fixture() -> Toolbar:
	root.size = Vector2i(640,400)
	var toolbar := Toolbar.new()
	root.add_child(toolbar)
	toolbar.size = Vector2(224,340)
	var city := flat_city()
	city.founded_year = 1900
	toolbar.refresh(city,CityStats.new())
	return toolbar

func test_locked_tool_focus_stays_visible_after_details_shrink_the_palette() -> void:
	var toolbar := fixture()
	await settle()
	var locked: Button = toolbar.button_for(Tools.Kind.SUBWAY).get_node("LockInfo")
	locked.grab_focus()
	await settle()
	locked.pressed.emit()
	await settle()
	var scroll := toolbar.get_node("Shell/Scroll") as ScrollContainer
	check(locked.has_focus(), "explaining a lock retains action focus")
	check(scroll.get_global_rect().encloses(locked.get_global_rect()), "focused lock remains visible after the details panel reduces the viewport")
	toolbar.free()

func test_compact_explore_keeps_controls_clear_and_restores_minimap_preference() -> void:
	var host: GameHost = preload("res://scenes/main.tscn").instantiate()
	host.preferences_path = "user://midcentury-focus.cfg"
	root.add_child(host)
	var city := flat_city()
	for x in range(50,80): city.building.put(x,61,Buildings.ROAD_FIRST+NetworkShapes.SHAPE_EW)
	host.begin_city(city,{},123,null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.display_layout.refresh_with_metrics(Vector2i(1280,800),1.0)
	await settle()
	host.city_view_3d.set_camera_state(Vector3(64,2.4,61),0,48)
	check(host.enter_explore(),"real road-supported session")
	host.exploration.set_physics_process(false)
	check(host.mini_map.visible,"roomy desktop Explore retains minimap")
	host.display_layout.refresh_with_metrics(Vector2i(640,400),1.0)
	await settle()
	check(not host.mini_map.visible,"compact Explore controls own the minimap corner")
	check(bool(host.preferences.get("minimap",false)),"temporary compact policy preserves the saved choice")
	host.set_option(&"minimap",true)
	check(not host.mini_map.visible,"changing preference cannot cover compact controls")
	host.display_layout.refresh_with_metrics(Vector2i(1280,800),1.0)
	await settle()
	check(host.mini_map.visible,"resizing restores roomy minimap")
	host.set_option(&"minimap",false)
	host.return_to_build()
	check(not host.mini_map.visible,"Build respects disabled preference")
	host.set_option(&"minimap",true)
	check(host.mini_map.visible,"Build restores enabled preference")
	host.free()
	await process_frame

func test_closing_lock_details_restores_visible_action_focus() -> void:
	var toolbar := fixture()
	await settle()
	var locked: Button = toolbar.button_for(Tools.Kind.SUBWAY).get_node("LockInfo")
	locked.grab_focus()
	locked.pressed.emit()
	await settle()
	var close: Button = toolbar.get_node("Shell/LockDetails/Body/Close")
	close.grab_focus()
	close.pressed.emit()
	await settle()
	check(locked.has_focus(), "closing lock details returns to the explained tool")
	check((toolbar.get_node("Shell/Scroll") as ScrollContainer).get_global_rect().encloses(locked.get_global_rect()), "restored focus is reachable")
	toolbar.free()
