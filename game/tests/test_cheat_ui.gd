# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
var host: GameHost

func before_each() -> void:
	host = MAIN.instantiate()
	host.preferences_path = "user://cheat-ui.cfg"
	root.add_child(host)

func after_each() -> void:
	host.free()
	if FileAccess.file_exists("user://cheat-ui.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://cheat-ui.cfg"))
	await physics_frame

func open_code() -> void:
	host.open_cheat_dialog()

func found() -> void:
	host.begin_city(flat_city(), {}, 7, CityStats.new())
	host.sim.set_speed(GameClock.Speed.FAST)

func test_dialog_pauses_cancel_restores_and_does_not_apply() -> void:
	found()
	var before := host.sim.snapshot().duplicate(true)
	open_code()
	check(host.notice_dialog.is_open())
	check(host.notice_dialog.line_edit.visible)
	check(host.is_input_blocked())
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	check_eq(root.gui_get_focus_owner(), host.notice_dialog.line_edit)
	host.notice_dialog.line_edit.text = "highroller"
	host.escape()
	check_eq(host.sim.speed, GameClock.Speed.FAST)
	check_eq(host.sim.snapshot(), before)
	check_eq(host.modal_depth, 0)

func test_submit_changes_paused_city_refreshes_tools_then_restores() -> void:
	found()
	host.sim.set_speed(GameClock.Speed.PAUSED)
	open_code()
	host.notice_dialog.line_edit.text = "  HIGHROLLER  "
	host.notice_dialog.line_edit.text_submitted.emit("  HIGHROLLER  ")
	check_eq(host.sim.city.funds, 520000)
	check(host.notice_dialog.is_open(), "feedback remains modal")
	check(not host.toolbar.is_locked(Tools.Kind.FUSION_PLANT))
	check(not host.toolbar.is_locked(Tools.Kind.REWARD_MONUMENT))
	for i in 10:
		if host.notice_dialog.is_open(): host.notice_dialog.dismiss()
	check_eq(host.modal_depth, 0)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)

func test_menu_and_chord_open_but_title_editor_modal_do_not() -> void:
	check(host.menu_bar.has_action(&"cheats"))
	open_code()
	check(not host.notice_dialog.is_open(), "title cannot mutate nonexistent city")
	found()
	var key := InputEventKey.new()
	key.keycode = KEY_C
	key.pressed = true
	key.ctrl_pressed = true
	key.shift_pressed = true
	key.alt_pressed = true
	host._input(key)
	check(host.notice_dialog.is_open())
	var depth := host.modal_depth
	host._input(key)
	check_eq(host.modal_depth, depth, "no nesting while modal")
	host.escape()
	host.stage = GameHost.Stage.EDITING
	host.menu_bar.press(&"cheats")
	check(not host.notice_dialog.is_open())
	host.stage = GameHost.Stage.PLAY
	host.menu_bar.press(&"cheats")
	check(host.notice_dialog.is_open())

func test_unknown_feedback_is_harmless() -> void:
	found()
	var funds := host.sim.city.funds
	open_code()
	host.notice_dialog.line_edit.text = "highroller!"
	host.notice_dialog.dismiss(&"submit")
	check_eq(host.sim.city.funds, funds)
	check(host.notice_dialog.body_label.text.contains("No such game"))
	host.escape()
	check_eq(host.sim.speed, GameClock.Speed.FAST)

func test_explore_cheat_entry_suspends_actor_and_cancels_safely() -> void:
	found()
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.select_tool(Tools.Kind.ROAD)
	host.handle_drag(Vector2i(22,20),Vector2i(24,20))
	await physics_frame
	host.city_view_3d.set_camera_state(Vector3(22.5,2.4,20.5),0,48)
	check(host.enter_explore(), "fixture enters on outdoor road")
	if not host.is_exploring(): return
	await physics_frame
	open_code()
	check(host.exploration.is_suspended(), "typing cannot move the actor")
	check_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)
	var feet: Vector3 = host.exploration.pedestrian.global_position
	var tool := host.tool
	host.notice_dialog.line_edit.text = "PBuQ"
	for letter in [KEY_P,KEY_B,KEY_U,KEY_Q]:
		var key := InputEventKey.new()
		key.keycode = letter
		key.pressed = true
		host._unhandled_key_input(key)
	await physics_frame
	check_eq(host.exploration.pedestrian.global_position, feet)
	check_eq(host.tool, tool)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	host.escape()
	check(host.exploration.is_suspended(), "Explore resumes only by explicit Resume")
	check_eq(host.modal_depth,0)
