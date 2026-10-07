# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Main keeps its menu shortcuts and restores temporary tools correctly.
extends "res://tests/test_case.gd"
const MainScene := preload("res://scenes/main.tscn")
const PREFS := "user://test_main_shortcut_safety.cfg"
var host: GameHost

func before_all() -> void:
	root.size = Vector2i(1280, 800)

func before_each() -> void:
	ViewPreferences.write({}, PREFS)
	host = MainScene.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)
	host.start_new_city({"name":"Shortcut test", "seed":4123}, flat_city())
	host.found_city()
	host.sim.set_speed(GameClock.Speed.SLOW)
	host.display_layout.release_city_focus()

func after_each() -> void:
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	root.remove_child(host)
	host.free()
	host = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))

func _key(code: int, pressed: bool = true, modifier: String = "") -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = pressed
	if not modifier.is_empty(): key.set(modifier, true)
	return key

func test_modified_gameplay_keys_do_not_change_city_controls() -> void:
	for modifier in ["ctrl_pressed", "meta_pressed", "alt_pressed"]:
		for code in [KEY_P, KEY_B, KEY_Q, KEY_U, KEY_EQUAL, KEY_PLUS, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
			host.select_tool(Tools.Kind.ROAD)
			host.sim.set_speed(GameClock.Speed.SLOW)
			var underground := host.presentation.is_underground()
			host._unhandled_key_input(_key(code, true, modifier))
			check_eq(host.tool, Tools.Kind.ROAD, "%s + %d keeps tool" % [modifier, code])
			check_eq(host.sim.speed, GameClock.Speed.SLOW, "%s + %d keeps speed" % [modifier, code])
			check_eq(host.presentation.is_underground(), underground, "%s + %d keeps layer" % [modifier, code])
			host._unhandled_key_input(_key(code, false, modifier))

func test_plain_shortcuts_and_shift_plus_still_work() -> void:
	host._unhandled_key_input(_key(KEY_P))
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	host._unhandled_key_input(_key(KEY_PLUS, true, "shift_pressed"))
	check_eq(host.sim.speed, GameClock.Speed.SLOW)
	host._unhandled_key_input(_key(KEY_MINUS))
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	host._unhandled_key_input(_key(KEY_Q))
	check_eq(host.tool, Tools.Kind.QUERY)
	host._unhandled_key_input(_key(KEY_U))
	check(host.presentation.is_underground())

func test_temporary_bulldoze_restores_no_tool() -> void:
	host.select_tool(GameHost.NO_TOOL)
	host._unhandled_key_input(_key(KEY_B))
	check_eq(host.tool, Tools.Kind.BULLDOZE)
	host._unhandled_key_input(_key(KEY_B, false))
	check_eq(host.tool, GameHost.NO_TOOL, "release restores empty selection")

func test_window_focus_loss_restores_tool_and_cancels_drag() -> void:
	host.select_tool(Tools.Kind.ROAD)
	host._unhandled_key_input(_key(KEY_B))
	host._drag_active = true
	root.focus_exited.emit()
	check_eq(host.tool, Tools.Kind.ROAD, "losing app focus cannot leave bulldoze held")
	check(not host._drag_active, "focus loss cancels destructive gesture")
	host._unhandled_key_input(_key(KEY_B, false))
	check_eq(host.tool, Tools.Kind.ROAD)

func test_modal_entry_restores_tool_before_release_is_swallowed() -> void:
	host.select_tool(Tools.Kind.ROAD)
	host._unhandled_key_input(_key(KEY_B))
	host.files.open_save_dialog()
	check_eq(host.tool, Tools.Kind.ROAD, "save text entry cannot retain temporary bulldoze")
	host.save_dialog.close()
	host._unhandled_key_input(_key(KEY_B, false))
	check_eq(host.tool, Tools.Kind.ROAD)

func test_gui_consumed_release_still_restores_tool() -> void:
	host.select_tool(Tools.Kind.ROAD)
	host._unhandled_key_input(_key(KEY_B))
	var edit := LineEdit.new()
	host.add_child(edit)
	edit.grab_focus()
	edit.gui_input.connect(func(_event: InputEvent): edit.accept_event())
	root.push_input(_key(KEY_B, false, "meta_pressed"))
	check_eq(host.tool, Tools.Kind.ROAD, "release cleanup precedes GUI consumption and modifier guard")
	edit.free()

func test_explicit_tool_selection_supersedes_temporary_bulldoze() -> void:
	host.select_tool(Tools.Kind.ROAD)
	host._unhandled_key_input(_key(KEY_B))
	host.select_tool(Tools.Kind.QUERY)
	host._unhandled_key_input(_key(KEY_B, false))
	check_eq(host.tool, Tools.Kind.QUERY, "late B release must not undo explicit selection")

func test_city_replacement_discards_held_tool() -> void:
	host.select_tool(Tools.Kind.ROAD)
	host._unhandled_key_input(_key(KEY_B))
	host.start_new_city({"name":"Replacement", "seed":123}, flat_city())
	host._unhandled_key_input(_key(KEY_B, false))
	check_eq(host.stage, GameHost.Stage.EDITING)
	check_eq(host.tool, GameHost.NO_TOOL, "old release cannot restore a tool in replacement editor")

func test_menu_entry_restores_tool_without_key_release() -> void:
	host.select_tool(Tools.Kind.ROAD)
	host._unhandled_key_input(_key(KEY_B))
	var popup: PopupMenu = host.menu_bar._menus["View"]
	popup.popup(Rect2i(160, 80, 300, 400))
	check_eq(host.tool, Tools.Kind.ROAD, "menu window may consume the eventual release")
	popup.hide()

func test_explicit_bulldoze_is_not_released_as_temporary() -> void:
	host.select_tool(Tools.Kind.BULLDOZE)
	host._unhandled_key_input(_key(KEY_B))
	host._unhandled_key_input(_key(KEY_B, false))
	root.focus_exited.emit()
	check_eq(host.tool, Tools.Kind.BULLDOZE, "explicit bulldoze selection persists")

func test_explore_roundtrip_preserves_empty_selection_while_b_held() -> void:
	host.sim.city.building.put(22,20,30)
	host.city_view_3d.refresh(true)
	host.select_tool(GameHost.NO_TOOL)
	host._unhandled_key_input(_key(KEY_B))
	check(host.enter_explore(), "flat fixture enters Explore")
	host._unhandled_key_input(_key(KEY_B, false))
	host.return_to_build()
	check_eq(host.tool, GameHost.NO_TOOL, "Explore snapshot restores the original empty selection")
