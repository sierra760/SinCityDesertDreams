# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Choosing a tool with the mouse leaves the map's pointer and key controls
## working; keyboard navigation, text fields and dialogs keep their input.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const PREFERENCES := "user://test-map-input-focus.cfg"
const MAP_POINT := Vector2(800, 400)

var host: GameHost


func before_each() -> void:
	root.size = Vector2i(1280, 800)
	host = MAIN.instantiate()
	host.preferences_path = PREFERENCES
	root.add_child(host)
	host.begin_city(flat_city(20000), {}, 7, CityStats.new())
	host.sim.set_speed(GameClock.Speed.SLOW)
	for i in 4: await process_frame


func after_each() -> void:
	host.free()
	if FileAccess.file_exists(PREFERENCES): DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFERENCES))
	await physics_frame


func _move(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion)


func _button(at: Vector2, index: int, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.factor = 1.0
	event.position = at
	event.global_position = at
	event.button_mask = (MOUSE_BUTTON_MASK_MIDDLE if index == MOUSE_BUTTON_MIDDLE else MOUSE_BUTTON_MASK_LEFT) if pressed else 0
	root.push_input(event)


func _click(at: Vector2) -> void:
	_move(at)
	_button(at, MOUSE_BUTTON_LEFT, true)
	_button(at, MOUSE_BUTTON_LEFT, false)


func _wheel(at: Vector2, index: int = MOUSE_BUTTON_WHEEL_UP) -> void:
	_move(at)
	_button(at, index, true)
	_button(at, index, false)


func _press(code: int) -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = code
		key.physical_keycode = code
		key.pressed = pressed
		root.push_input(key)


func _tool_button(tool: int) -> Button:
	var button := host.toolbar.button_for(tool)
	(host.toolbar.get_node("Shell/Scroll") as ScrollContainer).ensure_control_visible(button)
	return button


func _choose_with_mouse(tool: int) -> void:
	var button := _tool_button(tool)
	await process_frame
	_click(button.get_global_rect().get_center())
	await process_frame
	await process_frame


func _chrome_focus() -> Control:
	var focused := root.gui_get_focus_owner()
	return focused if focused != null and host.toolbar.is_ancestor_of(focused) else null


func test_pointer_reaches_the_map_after_a_mouse_tool_choice() -> void:
	await _choose_with_mouse(Tools.Kind.ROAD)
	check_eq(host.tool, Tools.Kind.ROAD, "the click chose the tool")
	var view := host.city_view_3d
	var size := view.camera_size
	_wheel(MAP_POINT)
	check(view.camera_size < size, "the wheel zooms in")
	size = view.camera_size
	var magnify := InputEventMagnifyGesture.new()
	magnify.position = MAP_POINT
	magnify.factor = 1.25
	root.push_input(magnify)
	check(view.camera_size < size, "a pinch zooms in")
	var center := view.center
	var pan := InputEventPanGesture.new()
	pan.position = MAP_POINT
	pan.delta = Vector2(4, 0)
	root.push_input(pan)
	check(not view.center.is_equal_approx(center), "a two-finger scroll pans")
	center = view.center
	_move(MAP_POINT)
	_button(MAP_POINT, MOUSE_BUTTON_MIDDLE, true)
	check(view._panning, "a middle press starts a pan")
	var drag := InputEventMouseMotion.new()
	drag.position = MAP_POINT + Vector2(40, 0)
	drag.global_position = drag.position
	drag.relative = Vector2(40, 0)
	drag.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	root.push_input(drag)
	_button(MAP_POINT + Vector2(40, 0), MOUSE_BUTTON_MIDDLE, false)
	check(not view.center.is_equal_approx(center), "a middle drag pans")


func test_city_keys_work_after_a_mouse_tool_choice() -> void:
	await _choose_with_mouse(Tools.Kind.ROAD)
	check_eq(host.tool, Tools.Kind.ROAD)
	check(_chrome_focus() == null, "the pressed tool button does not keep the keyboard")
	check(not host.is_camera_input_blocked(), "city keys are free")
	_press(KEY_P)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "P pauses")
	_press(KEY_P)
	check_eq(host.sim.speed, GameClock.Speed.SLOW, "P resumes")
	var turn := host.city_view_3d.quarter_turn
	_press(KEY_R)
	check_eq(host.city_view_3d.quarter_turn, posmod(turn + 1, 4), "R rotates")
	_press(KEY_1)
	check_eq(host.city_view_3d.zoom_level(), 0, "1 picks the first zoom level")
	_press(KEY_4)
	check_eq(host.city_view_3d.zoom_level(), 3, "4 picks the fourth zoom level")
	_press(KEY_DOWN)
	await process_frame
	check(_chrome_focus() == null, "an arrow key does not walk the toolbar")
	check_eq(host.tool, Tools.Kind.ROAD, "the tool stays chosen")


func test_a_mouse_press_on_the_footer_or_inspector_leaves_city_keys_free() -> void:
	host.open_query(Vector2i(10, 10))
	await process_frame
	await process_frame
	var pressed: Button
	for button: Button in host.query_panel.find_children("*", "Button", true, false):
		if not button.is_visible_in_tree() or button.disabled or button.focus_mode != Control.FOCUS_ALL: continue
		if button.text.to_lower().contains("close") or button.text.to_lower().contains("demolish") or button.text.to_lower().contains("rename"): continue
		pressed = button
		break
	check(pressed != null, "the inspector offers a button to press")
	if pressed == null: return
	_move(pressed.get_global_rect().get_center())
	_button(pressed.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, true)
	check_eq(root.gui_get_focus_owner(), pressed, "the press reaches the button")
	_button(pressed.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, false)
	await process_frame
	await process_frame
	var focused := root.gui_get_focus_owner()
	check(focused == null or not host.query_panel.is_ancestor_of(focused), "an inspector button does not keep the keyboard")
	_press(KEY_P)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "P pauses after pressing an inspector button")


func test_keyboard_navigation_keeps_the_toolbar() -> void:
	_press(KEY_TAB)
	await process_frame
	var road := _tool_button(Tools.Kind.ROAD)
	road.grab_focus()
	await process_frame
	await process_frame
	check_eq(root.gui_get_focus_owner(), road, "a tool focused from the keyboard keeps focus")
	check(host.is_camera_input_blocked(), "typing belongs to the focused control")
	_press(KEY_P)
	check_eq(host.sim.speed, GameClock.Speed.SLOW, "P is not a city key while navigating the toolbar")
	_press(KEY_ENTER)
	await process_frame
	await process_frame
	check_eq(host.tool, Tools.Kind.ROAD, "Enter chooses the focused tool")
	check_eq(root.gui_get_focus_owner(), road, "and focus stays for more navigation")
	_press(KEY_RIGHT)
	await process_frame
	var next := root.gui_get_focus_owner()
	check(next != null and next != road and host.toolbar.is_ancestor_of(next), "arrows move between tools")
	# The pointer over the map still zooms; it does not take the keyboard.
	var size := host.city_view_3d.camera_size
	_wheel(MAP_POINT)
	check(host.city_view_3d.camera_size < size, "the wheel over the map zooms while a tool has focus")
	check_eq(root.gui_get_focus_owner(), next, "the wheel leaves keyboard focus alone")


func test_tab_after_a_mouse_choice_returns_to_keyboard_navigation() -> void:
	await _choose_with_mouse(Tools.Kind.ROAD)
	check(_chrome_focus() == null)
	_press(KEY_TAB)
	await process_frame
	await process_frame
	var focused := root.gui_get_focus_owner()
	check(focused != null, "Tab focuses a control")
	_press(KEY_TAB)
	await process_frame
	await process_frame
	check(root.gui_get_focus_owner() != null and root.gui_get_focus_owner() != focused, "Tab moves on")


func test_dialogs_and_text_fields_keep_their_input() -> void:
	await _choose_with_mouse(Tools.Kind.ROAD)
	host.notices.show("Notice", "A dialog is open.")
	await process_frame
	var size := host.city_view_3d.camera_size
	_wheel(MAP_POINT)
	check_eq(host.city_view_3d.camera_size, size, "a dialog blocks the wheel")
	var magnify := InputEventMagnifyGesture.new()
	magnify.position = MAP_POINT
	magnify.factor = 1.25
	root.push_input(magnify)
	check_eq(host.city_view_3d.camera_size, size, "a dialog blocks a pinch")
	_button(MAP_POINT, MOUSE_BUTTON_MIDDLE, true)
	check(not host.city_view_3d._panning, "a dialog blocks a middle drag")
	_button(MAP_POINT, MOUSE_BUTTON_MIDDLE, false)
	host.notice_dialog.dismiss()
	await process_frame
	host.session.prompt_rename()
	await process_frame
	await process_frame
	var field := host.notice_dialog.line_edit
	_click(field.get_global_rect().get_center())
	await process_frame
	await process_frame
	check_eq(root.gui_get_focus_owner(), field, "a clicked text field keeps the keyboard")
	_press(KEY_P)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "the prompt holds the city; P types, it does not resume")
	host.notice_dialog.dismiss(&"cancel")
	await process_frame
	check_eq(host.sim.speed, GameClock.Speed.SLOW, "closing the prompt restores the speed")
