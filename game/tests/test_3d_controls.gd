# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Alternate presentation uses the same construction and modal input owners.
extends "res://tests/test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
const PREFS := "user://test_3d_controls.cfg"
const SAVE := "user://test_3d_controls.sc2d"
var host: GameHost

## Deterministic projection double: routing tests do not depend on a physics tick.
class PickView extends CityView3D:
	var chosen := Vector2i(40, 40)
	var purposes: Array[int] = []

	func pick_cell(_point: Vector2, purpose: int = 0) -> Vector2i:
		purposes.append(purpose)
		return chosen

	func project_cell(_cell: Vector2i) -> Vector2:
		return Vector2(400, 300)


func before_all() -> void:
	# Headless SceneTree scripts begin with a 64px dummy window. Match the
	# playable viewport before asserting physical zoom and camera handoff.
	root.size = Vector2i(1280, 800)


func before_each() -> void:
	ViewPreferences.write({}, PREFS)
	host = MainScene.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)
	var city := flat_city()
	city.name = "Diorama Test"
	host.start_new_city({"name": city.name, "seed": 4123, "difficulty": City.Difficulty.EASY}, city)
	host.found_city()
	host.sim.set_speed(GameClock.Speed.PAUSED)


func after_each() -> void:
	_release_host()
	host = null
	for path: String in [PREFS, SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _release_host() -> void:
	# Break the fixture's existing system/context ownership cycle only after
	# every gameplay assertion, then release its scene normally.
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	root.remove_child(host)
	host.free()


func _click(pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = Vector2(400, 300)
	host.presentation._unhandled_input(event)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


func test_display_size_preserves_camera_city_and_simulation() -> void:
	host.city_view_3d.set_camera_state(Vector3(45.5,0,51.5),2,27.0)
	var before_sim := host.sim.snapshot().duplicate(true)
	var before_city := SaveFormat.encode_city(host.sim.city).duplicate(true)
	host.display_layout.refresh_with_metrics(Vector2i(2560,1600),2.0)
	host.set_option(&"ui_scale",200)
	check(host.city_view_3d.active)
	check_eq(host.city_view_3d.camera_size,27.0)
	check_eq(host.city_view_3d.quarter_turn,2)
	check_eq(Vector2(host.city_view_3d.center.x,host.city_view_3d.center.z),Vector2(45.5,51.5))
	check_eq(host.city_view_3d.viewport.size,Vector2i(2560,1600))
	check_eq(host.sim.snapshot(),before_sim)
	check_eq(SaveFormat.encode_city(host.sim.city),before_city)

func test_elevated_shore_focus_survives_analytical_views() -> void:
	var city := host.sim.city
	var focus := Vector2i(104,15)
	city.set_heights(focus.x,focus.y,21,21)
	host.city_view_3d.set_center_cell(focus)
	var center := host.city_view_3d.center
	var before := SaveFormat.encode_city(city).duplicate(true)
	var simulation := host.sim.snapshot().duplicate(true)
	host.menu_bar.press(&"overlay",&"crime")
	host.select_tool(Tools.Kind.SUBWAY)
	host.select_tool(Tools.Kind.QUERY)
	check(host.city_view_3d.active)
	check_eq(host.city_view_3d.center,center)
	check_eq(SaveFormat.encode_city(city),before)
	check_eq(host.sim.snapshot(),simulation)

func test_camera_controls_use_only_the_3d_view() -> void:
	var size := host.city_view_3d.camera_size
	host.menu_bar.press(&"zoom_in")
	check_lt(host.city_view_3d.camera_size,size)
	host.menu_bar.press(&"rotate")
	check_eq(host.city_view_3d.quarter_turn,1)
	host.menu_bar.press(&"zoom",4)
	check_eq(host.city_view_3d.zoom_level(),4)
	host.menu_bar.press(&"recenter")
	check_eq(Vector2(host.city_view_3d.center.x,host.city_view_3d.center.z),Vector2(64.5,64.5))
	check(host.get_node_or_null("CameraController") == null)

func test_picking_routes_real_host_build_query_and_demolition() -> void:
	var pick := PickView.new()
	pick.active = true
	host.presentation.view = pick
	var city := host.sim.city
	var funds := city.funds
	host.select_tool(Tools.Kind.ROAD)
	_click(true)
	_click(false)
	check(Buildings.is_road_like(city.building.at(40, 40)), "screen click reaches the Builder")
	check_eq(city.funds, funds - Tools.cost(Tools.Kind.ROAD))
	check_eq(pick.purposes, [0, 0] as Array[int], "placement uses terrain")
	pick.purposes.clear()
	_click(true, MOUSE_BUTTON_RIGHT)
	_click(false, MOUSE_BUTTON_RIGHT)
	check(host.query_panel.is_open())
	check_eq(host.query_panel.tile, Vector2i(40, 40))
	check_eq(pick.purposes, [1, 1] as Array[int], "right click inspects buildings even with a construction tool")
	host.query_panel.close()
	pick.purposes.clear()
	host.select_tool(Tools.Kind.BULLDOZE)
	_click(true)
	_click(false)
	check_eq(city.building.at(40, 40), Buildings.NONE)
	check_eq(pick.purposes, [1, 1] as Array[int], "demolition picks the visible building")
	host.presentation.view = host.city_view_3d
	pick.free()


func test_modal_cancels_drag_and_blocks_camera_minimap_and_fullscreen_keys() -> void:
	var pick := PickView.new()
	pick.active = true
	host.presentation.view = pick
	host.select_tool(Tools.Kind.ROAD)
	_click(true)
	check(host._drag_active)
	host.city_view_3d._panning = true
	host.files.open_save_dialog()
	check(not host._drag_active)
	check(not host.city_view_3d._panning)
	var funds := host.sim.city.funds
	var center := host.city_view_3d.center
	var fullscreen := host.display_layout.fullscreen
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = Vector2(120,120)
	host.mini_map._on_click(click)
	host._unhandled_key_input(_key(KEY_F11))
	host.menu_bar.press(&"rotate")
	check_eq(host.city_view_3d.center,center)
	check_eq(host.display_layout.fullscreen,fullscreen)
	check(host.city_view_3d.active)
	_click(false)
	host.save_dialog.close()
	_click(false)
	check_eq(host.sim.city.funds,funds)
	check_eq(host.sim.city.building.at(40,40),Buildings.NONE)
	host.presentation.view = host.city_view_3d
	pick.free()

func test_editor_overlays_and_subway_remain_3d() -> void:
	host.start_new_city({"name":"Draft","seed":22},flat_city())
	var funds := host.sim.city.funds
	check(host.city_view_3d.active)
	check_eq(host.stage,GameHost.Stage.EDITING)
	check_eq(host.sim.speed,GameClock.Speed.PAUSED)
	host.select_tool(Tools.Kind.RAISE_LAND)
	var result := host.handle_drag(Vector2i(35,35),Vector2i(35,35))
	check(bool(result["ok"]))
	check_eq(host.sim.city.funds,funds)
	check(host.found_city())
	host.menu_bar.press(&"overlay",&"crime")
	check(host.city_view_3d.active)
	check_eq(host.presentation.get_overlay(),&"crime")
	host.select_tool(Tools.Kind.SUBWAY)
	check(host.city_view_3d.active)
	check(host.presentation.is_underground())
	check_eq(host.tool,Tools.Kind.SUBWAY)
	host.select_tool(Tools.Kind.ROAD)
	check(not host.presentation.is_underground())
	check_eq(host.presentation.get_overlay(),&"crime")

func test_cursor_and_minimap_follow_3d_rotation() -> void:
	host.select_tool(Tools.Kind.ROAD)
	var before := host.sim.city.funds
	var quote := host.construction.preview_drag(Vector2i(44, 44), Vector2i(47, 44))
	check(bool(quote["ok"]))
	check(host.presentation.preview.is_showing())
	check(host.cursor_caption_3d.visible)
	check_eq(host.cursor_caption_3d.text, "$" + UIFactory.commafy(int(quote["cost"])))
	check_gt(host.city_view_3d.cursor.get_child_count(), 0)
	check_eq(host.sim.city.funds, before, "preview does not charge")
	for turn: int in 4:
		host.city_view_3d.set_camera_state(host.city_view_3d.center, turn, 64.0)
		check_eq(host.mini_map.display_rotation(), posmod(turn, 4))
		var click := InputEventMouseButton.new()
		click.pressed = true
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = Vector2(100, 75)
		host.mini_map._on_click(click)
		var data := RotationMapper.screen_to_data(85, 64, posmod(turn, 4))
		check_eq(Vector2(host.city_view_3d.center.x, host.city_view_3d.center.z), Vector2(data) + Vector2(0.5, 0.5))
	host.select_tool(Tools.Kind.QUERY)
	check(not host.cursor_caption_3d.visible)
	check_eq(host.city_view_3d.cursor.get_child_count(), 0)


func test_native_reload_binds_new_city_and_keeps_view_preferences_separate() -> void:
	host.select_tool(Tools.Kind.ROAD)
	host.handle_drag(Vector2i(41, 41), Vector2i(43, 41))
	var original_city := host.sim.city
	var expected := host.sim.snapshot().duplicate(true)
	check_eq(SaveFormat.save(SAVE, original_city, expected), OK)
	host.start_new_city({"name": "Other", "seed": 2}, flat_city())
	check_ne(host.city_view_3d.city, original_city)
	check(host.load_city(SAVE))
	check(host.city_view_3d.active)
	check_eq(host.city_view_3d.city, host.sim.city)
	check(Buildings.is_road_like(host.sim.city.building.at(42, 41)))
	check_eq(host.sim.snapshot(), expected)
	var prefs := ViewPreferences.read(PREFS)
	check(not prefs.has("mode_3d"))
	check(not SaveFormat.load(SAVE).has("mode_3d"), "view choice belongs to display preferences")


func test_preferences_validate_and_round_trip_independent_3d_camera() -> void:
	var path := "user://test_3d_validation.cfg"
	var clean := ViewPreferences.sanitize({"mode_3d": "yes", "size_3d": NAN, "rotation_3d": INF,
		"center_3d": Vector3(NAN, 10, INF)})
	check(not clean.has("mode_3d"))
	check_eq(clean["size_3d"], 72.0)
	check_eq(clean["rotation_3d"], 0)
	check_eq(clean["center_3d"], Vector3(64, 0, 64))
	check_eq(ViewPreferences.write({"mode_3d": true, "size_3d": 9000, "rotation_3d": -1,
		"center_3d": Vector3(-20, 6, 200)}, path), OK)
	var back := ViewPreferences.read(path)
	check(not back.has("mode_3d"))
	check_eq(back["size_3d"], 2048.0)
	check_eq(back["rotation_3d"], 3)
	check_eq(back["center_3d"], Vector3(0, 0, 128))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_saved_view_restores_when_the_next_host_opens_a_city() -> void:
	host.city_view_3d.set_camera_state(Vector3(34.5, 0, 82.5), 2, 27.0)
	_release_host()
	host = MainScene.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)
	host.start_new_city({"name": "Restored view", "seed": 33}, flat_city())
	check(host.city_view_3d.active)
	check_eq(host.stage, GameHost.Stage.EDITING)
	check_eq(host.city_view_3d.camera_size, 27.0)
	check_eq(host.city_view_3d.quarter_turn, 2)
	check_eq(Vector2(host.city_view_3d.center.x, host.city_view_3d.center.z), Vector2(34.5, 82.5))
	check_eq(host.files.write_save(SAVE), OK)
	check(host.load_city(SAVE))
	check(host.city_view_3d.active)
	check_eq(host.stage, GameHost.Stage.EDITING)
	check_eq(host.city_view_3d.city, host.sim.city)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)


func test_temporary_bulldoze_preserves_a_drag_in_both_release_orders() -> void:
	var pick := PickView.new()
	pick.active = true
	host.presentation.view = pick
	host.select_tool(Tools.Kind.ROAD)
	check(bool(host.handle_drag(Vector2i(40, 40), Vector2i(42, 40))["ok"]))
	_click(true)
	pick.chosen = Vector2i(42, 40)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(420, 300)
	host.presentation._unhandled_input(move)
	host._unhandled_key_input(_key(KEY_B))
	check(host._drag_active, "pressing B retains the active gesture")
	check_eq(host.presentation._drag_from, Vector2i(40, 40))
	check_eq(host.presentation._drag_to, Vector2i(42, 40))
	check_eq(host.tool, Tools.Kind.BULLDOZE)
	_click(false)
	for x: int in range(40, 43):
		check_eq(host.sim.city.building.at(x, 40), Buildings.NONE, "release with B held demolishes the whole drag")
	var release := _key(KEY_B)
	release.pressed = false
	host._unhandled_key_input(release)
	check_eq(host.tool, Tools.Kind.ROAD)
	check(bool(host.handle_drag(Vector2i(45, 40), Vector2i(47, 40))["ok"]))
	pick.chosen = Vector2i(45, 40)
	_click(true)
	pick.chosen = Vector2i(47, 40)
	host.presentation._unhandled_input(move)
	host._unhandled_key_input(_key(KEY_B))
	host._unhandled_key_input(release)
	check(host._drag_active, "releasing B before the mouse retains the gesture")
	check_eq(host.tool, Tools.Kind.ROAD)
	_click(false)
	for x: int in range(45, 48):
		check_eq(host.sim.city.building.at(x, 40), Buildings.NONE, "a bulldoze drag stays a bulldoze drag after B is released")
	# Holding B before pressing, then releasing it first, never builds or charges.
	var funds := host.sim.city.funds
	host._unhandled_key_input(_key(KEY_B))
	check_eq(host.tool, Tools.Kind.BULLDOZE)
	pick.chosen = Vector2i(50, 40)
	_click(true)
	pick.chosen = Vector2i(52, 40)
	host.presentation._unhandled_input(move)
	host._unhandled_key_input(release)
	check_eq(host.tool, Tools.Kind.ROAD)
	_click(false)
	for x: int in range(50, 53):
		check_eq(host.sim.city.building.at(x, 40), Buildings.NONE, "the latched bulldoze does not become a road")
	check_eq(host.sim.city.funds, funds, "nothing is charged for an empty bulldoze drag")
	# The next ordinary drag uses the selected tool again.
	pick.chosen = Vector2i(55, 40)
	_click(true)
	pick.chosen = Vector2i(57, 40)
	host.presentation._unhandled_input(move)
	_click(false)
	for x: int in range(55, 58):
		check(Buildings.is_road_like(host.sim.city.building.at(x, 40)), "a fresh drag builds with the selected tool")
	host.presentation.view = host.city_view_3d
	pick.free()


func test_all_named_zoom_levels_are_ordered_and_preserved_by_ui_scale() -> void:
	var previous := INF
	for level: int in CityView3D.ZOOM_COUNT:
		host.city_view_3d.set_zoom_level(level)
		check_eq(host.city_view_3d.zoom_level(),level)
		check_lt(host.city_view_3d.camera_size,previous)
		previous = host.city_view_3d.camera_size
		var before := host.city_view_3d.camera_size
		host.set_option(&"ui_scale",150)
		check_eq(host.city_view_3d.camera_size,before)
		host.set_option(&"ui_scale",100)

func test_explicit_view_menu_action_works_after_toolbar_focus() -> void:
	host.toolbar.button_for(Tools.Kind.ROAD).grab_focus()
	check(host.display_layout.blocks_city_keyboard())
	var turn := host.city_view_3d.quarter_turn
	host.menu_bar.press(&"rotate")
	check_eq(host.city_view_3d.quarter_turn,posmod(turn+1,4),"explicit menu action is not a keyboard shortcut")

func test_compact_shell_width_and_long_caption_stay_inside_display() -> void:
	host.display_layout.refresh_with_metrics(Vector2i(1280,800),1.0)
	host.set_option(&"ui_scale",200)
	check_eq(host.toolbar.offset_right,196.0,"compact palette uses two-column width")
	var cells: Array[Vector2i] = [Vector2i(64,64)]
	host.presentation.preview.show_footprint(cells,false,"This is a long refusal explaining why the intended building cannot be constructed on this site. ".repeat(4))
	host.sync_3d_cursor()
	check(host.cursor_caption_3d.get_global_rect().end.x <= host.display_layout.logical_rect().end.x)
	check(host.cursor_caption_3d.get_global_rect().end.y <= host.display_layout.logical_rect().end.y)

func test_temporary_bulldoze_keeps_underground_drag_in_both_release_orders() -> void:
	var pick := PickView.new()
	pick.active = true
	host.presentation.view = pick
	host.select_tool(Tools.Kind.WATER_PIPE)
	check(bool(host.handle_drag(Vector2i(40,40),Vector2i(42,40))["ok"]))
	_click(true)
	pick.chosen = Vector2i(42,40)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(420,300)
	host.presentation._unhandled_input(motion)
	host._unhandled_key_input(_key(KEY_B))
	check_eq(host.presentation._drag_from,Vector2i(40,40))
	check(host.presentation.is_underground())
	_click(false)
	for x in range(40,43): check_eq(host.sim.city.underground.at(x,40),0)
	var release := _key(KEY_B)
	release.pressed = false
	host._unhandled_key_input(release)
	check(bool(host.handle_drag(Vector2i(45,40),Vector2i(47,40))["ok"]))
	pick.chosen = Vector2i(45,40)
	_click(true)
	pick.chosen = Vector2i(47,40)
	host.presentation._unhandled_input(motion)
	host._unhandled_key_input(_key(KEY_B))
	host._unhandled_key_input(release)
	check_eq(host.presentation._drag_from,Vector2i(45,40))
	_click(false)
	for x in range(45,48): check_eq(host.sim.city.underground.at(x,40),0,"a bulldoze drag stays a bulldoze drag after B is released")
	host.presentation.view = host.city_view_3d
	pick.free()
