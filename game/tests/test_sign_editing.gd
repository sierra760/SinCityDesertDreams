# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Exercise visible-label targeting through the real map input and inspector.
extends "res://tests/exploration/async_test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
const SIGN_CELL := Vector2i(62, 62)
var host: GameHost


func before_each() -> void:
	root.size = Vector2i(1152, 720)
	host = MainScene.instantiate()
	root.add_child(host)
	var city := flat_city()
	city.founded_year = 2000
	city.signs[SIGN_CELL] = "Desert Avenue"
	host.start_new_city({"name":"Sign Test", "seed":9, "founded_year":2000}, city)
	host.found_city()
	host.city_view_3d.set_center_cell(SIGN_CELL)
	host.city_view_3d.set_zoom_level(4)
	host.set_option(&"labels", true)
	await physics_frame
	await process_frame
	await process_frame


func after_each() -> void:
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	host.free()
	host = null
	await process_frame


func _label_point() -> Vector2:
	var label: Label = host.city_view_3d._label_nodes[SIGN_CELL]
	return label.get_global_rect().get_center()


func _mouse(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = true
	host.presentation._unhandled_input(event)
	event.pressed = false
	host.presentation._unhandled_input(event)


func test_sign_tool_edits_visible_label_in_all_rotations() -> void:
	host.select_tool(Tools.Kind.SIGN)
	for rotation: int in 4:
		host.city_view_3d.set_camera_state(host.city_view_3d.center, rotation, 16.0)
		await physics_frame
		await process_frame
		_mouse(_label_point())
		check(host.notice_dialog.is_open(), "clicking the label opens the editor")
		check_eq(host.notice_dialog.line_edit.text, "Desert Avenue", "visible text targets its stored sign, not the ground behind it")
		host.notice_dialog.line_edit.text = "Cancelled draft"
		host.notice_dialog.dismiss()
		check_eq(host.sim.city.signs[SIGN_CELL], "Desert Avenue", "cancel preserves the sign")
	check_eq(host.sim.city.signs.size(), 1, "label clicks never add signs on neighboring tiles")


func test_touch_sign_label_updates_existing_sign_and_restores_speed() -> void:
	host.select_tool(Tools.Kind.SIGN)
	var speed := host.sim.speed
	var event := InputEventScreenTouch.new()
	event.index = 7
	event.position = _label_point()
	event.pressed = true
	host.presentation._input(event)
	check_eq(host.notice_dialog.line_edit.text, "Desert Avenue", "touch edits the displayed sign")
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "editing pauses the city")
	event.pressed = false
	host.presentation._input(event)
	host.notice_dialog.line_edit.text = "New Avenue"
	host.notice_dialog.line_edit.text_submitted.emit("New Avenue")
	check_eq(host.sim.city.signs.get(SIGN_CELL), "New Avenue")
	check_eq(host.sim.city.signs.size(), 1)
	check_eq(host.sim.speed, speed)
	check_eq((host.city_view_3d._label_nodes[SIGN_CELL] as Label).text, "New Avenue")


func test_right_click_label_offers_edit_and_blank_removes_it() -> void:
	host.select_tool(Tools.Kind.ROAD)
	_mouse(_label_point(), MOUSE_BUTTON_RIGHT)
	check_eq(host.query_panel.tile, SIGN_CELL, "right-click inspects the sign's tile")
	var button := host.query_panel.get("sign_button") as Button
	check(button != null and button.visible, "inspector offers Edit Sign")
	if button == null or not button.visible: return
	button.pressed.emit()
	check_eq(host.notice_dialog.line_edit.text, "Desert Avenue")
	host.notice_dialog.line_edit.text = ""
	host.notice_dialog.dismiss(&"submit")
	check(not host.sim.city.signs.has(SIGN_CELL), "blank submission deletes the selected sign")
	check(not host.query_panel.info.has("Sign"), "inspector refreshes after deletion")
	check(not button.visible, "the removed sign has no edit action")
	check_eq(host.city_view_3d._labels.get_child_count(), 0)


func test_sign_text_does_not_redirect_construction_or_hidden_label_picks() -> void:
	var point := _label_point()
	var ground := host.city_view_3d.pick_cell(point, 0)
	check_ne(ground, SIGN_CELL, "fixture text is offset from its stored tile")
	host.select_tool(Tools.Kind.ROAD)
	check_eq(host.presentation.tile_at_screen(point), ground, "construction targets ground")
	host.select_tool(Tools.Kind.BULLDOZE)
	check_eq(host.presentation.tile_at_screen(point), host.city_view_3d.pick_cell(point, 1), "demolition retains physical targeting")
	var clicks: Array[Vector2i] = []
	host.presentation.tile_clicked.connect(func(cell: Vector2i, _button: int) -> void: clicks.append(cell))
	_mouse(point)
	check_eq(clicks, [ground], "mouse demolition cannot be redirected to a sign")
	host.set_option(&"labels", false)
	host.select_tool(Tools.Kind.SIGN)
	check_eq(host.presentation.tile_at_screen(point), ground, "hidden labels cannot intercept input")
	host.set_option(&"labels", true)
	host.city_view_3d.set_active(false)
	check_eq(host.presentation.tile_at_screen(point), Vector2i(-1, -1), "inactive map cannot select labels")


func test_inspect_targets_label_after_display_scaling() -> void:
	host.select_tool(Tools.Kind.QUERY)
	for percent: int in [100, 150, 200]:
		host.display_layout.ui_scale = percent
		host.display_layout.refresh_with_metrics(Vector2i(1280, 800), 2.0)
		await process_frame
		await physics_frame
		_mouse(_label_point())
		check_eq(host.query_panel.tile, SIGN_CELL, "Inspect follows the label at UI scale %d" % percent)
		check_eq(host.query_panel.info.get("Sign"), "Desert Avenue")
		host.query_panel.close()
