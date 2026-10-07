# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
var host: GameHost

func before_each() -> void:
	host = MainScene.instantiate()
	host.preferences_path = "user://ipad-layout.cfg"
	root.add_child(host)
	host.begin_city(flat_city(), {}, 123, null)
	host.sim.set_speed(GameClock.Speed.PAUSED)

func after_each() -> void:
	host.free()
	await process_frame

func test_touch_ownership_uses_visible_chrome_and_modal_geometry() -> void:
	await process_frame
	check(host.touch_ui_owned(host.toolbar.get_global_rect().get_center()))
	check(host.touch_ui_owned(host.menu_bar.get_global_rect().get_center()))
	check(host.touch_ui_owned(host.status_bar.get_global_rect().get_center()))
	check(not host.touch_ui_owned(Vector2(600, 350)), "clear city space remains usable")
	host.files.open_save_dialog()
	check(host.touch_ui_owned(Vector2(600, 350)), "modal owns the whole city")

func test_safe_area_and_keyboard_bound_every_shell_control() -> void:
	host.display_layout.refresh_with_mobile_metrics(Vector2i(2048,1536), 2.0, Rect2i(48,32,1952,1472), 512)
	await process_frame
	await process_frame
	var usable := host.display_layout.logical_rect()
	for control: Control in [host.menu_bar, host.status_bar, host.toolbar]:
		var rect := control.get_global_rect()
		check(usable.grow(.1).encloses(rect), "%s fits safe/keyboard region: %s in %s" % [control.name, rect, usable])
	check_eq(host.menu_bar.position, usable.position)
	check(host.touch_ui_owned(Vector2(8,8)), "unsafe screen edge never starts a city gesture")
	check(host.touch_ui_owned(Vector2(700,650)), "keyboard region never starts a city gesture")

func test_focused_toolbar_does_not_own_clear_city_space() -> void:
	await process_frame
	host.toolbar.button_for(Tools.Kind.ROAD).grab_focus()
	check(host.display_layout.blocks_city_keyboard(), "fixture retains toolbar keyboard focus")
	check(not host.touch_ui_owned(Vector2(600,350)), "a tool tap must allow the next city touch")

func test_touch_explore_actions_remain_visible_and_unobstructed() -> void:
	var city := flat_city()
	for x in range(50,80): city.building.put(x,61,Buildings.ROAD_FIRST+NetworkShapes.SHAPE_EW)
	host.begin_city(city,{},123,null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	await process_frame
	await process_frame
	host.city_view_3d.set_camera_state(Vector3(64,2.4,61),0,48)
	host.exploration.set_touch_controls_enabled(true)
	check(host.enter_explore(), "road-supported touch session")
	if not host.exploration.is_active(): return
	host.exploration.set_physics_process(false)
	check(not host.mini_map.visible, "touch actions own the lower right corner")
	for mode: int in [0,1,2]:
		host.explore_hud.set_suspended(false)
		host.explore_hud.set_status({"mode":mode})
		await process_frame
		await process_frame
		var controls := host.explore_hud.touch_controls
		for action: StringName in controls._mode_actions():
			check(controls._buttons[action].is_visible_in_tree(), "context action is visible: "+str(action))
			check(not host.touch_ui_owned(controls.control_rect(action).get_center()), "city chrome does not intercept %s at %s above footer %s" % [action,controls.control_rect(action),host.status_bar.get_global_rect()])
	host.set_option(&"minimap",true)
	check(not host.mini_map.visible, "minimap preference cannot cover active touch controls")
	host.return_to_build()
	check(host.mini_map.visible, "return to Build restores the minimap preference")
