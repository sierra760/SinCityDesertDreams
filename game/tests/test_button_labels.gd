# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const PREFS := "user://button-labels-test.cfg"
const MainScene := preload("res://scenes/main.tscn")

func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))

func test_old_and_invalid_preferences_keep_labels_and_false_survives_reload() -> void:
	check_eq(ViewPreferences.sanitize({}).get("button_labels"), true)
	for invalid: Variant in [0, 1, "false", null]:
		check_eq(ViewPreferences.sanitize({"button_labels":invalid}).get("button_labels"), true)
	check_eq(ViewPreferences.write({"button_labels":false,"labels":false}, PREFS), OK)
	check_eq(ViewPreferences.read(PREFS).get("button_labels"), false)
	check_eq(ViewPreferences.read(PREFS).labels, false, "map labels remain a separate preference")

func test_icon_only_layout_saves_space_and_preserves_tool_identity_and_focus() -> void:
	var toolbar := Toolbar.new()
	root.add_child(toolbar)
	for compact: bool in [false,true]:
		toolbar.apply_layout(compact)
		toolbar.size = Vector2(toolbar.custom_minimum_size.x,350)
		var labeled_width := toolbar.custom_minimum_size.x
		var labeled_height := toolbar.button_for(Tools.Kind.ROAD).custom_minimum_size.y
		toolbar.set_active(Tools.Kind.ROAD)
		var focused := toolbar.button_for(Tools.Kind.PLACE_WATER)
		focused.grab_focus()
		toolbar.set_button_labels_visible(false)
		toolbar.apply_layout(compact)
		toolbar.size.x = toolbar.custom_minimum_size.x
		for frame in 8: await process_frame
		check_lt(toolbar.size.x, labeled_width, "hiding captions narrows the sidebar")
		for tool: int in Tools.all():
			var button := toolbar.button_for(tool)
			check(button.text.is_empty(), "all captions hidden")
			check(button.icon != null and button.tooltip_text.contains(Tools.display_name(tool)), "icon and tooltip retained")
			check_lt(button.size.y, labeled_height, "rows get shorter")
			check_ge(button.size.y,44,"usable target retained")
		check_eq(toolbar.active_tool,Tools.Kind.ROAD)
		check(toolbar.selected_label.text.contains("Road"))
		check(focused.has_focus(),"toggle preserves keyboard focus")
		check((toolbar.get_node("Shell/Scroll") as ScrollContainer).get_global_rect().encloses(focused.get_global_rect()), "focus stays reachable after reflow")
		toolbar.set_button_labels_visible(true)
		check_eq(toolbar.custom_minimum_size.x,labeled_width)
		check_eq(toolbar.button_for(Tools.Kind.ROAD).text,"Road\n")
		check_eq(toolbar.button_for(Tools.Kind.WATER_PIPE).text,"Water\npipe")
	toolbar.free()
	await process_frame

func test_view_menu_updates_live_toolbar_and_restores_on_new_host() -> void:
	ViewPreferences.write({},PREFS)
	root.size = Vector2i(1280,800)
	var host: GameHost = MainScene.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)
	check(host.menu_bar.has_action(&"button_labels"),"View menu offers button labels")
	if not host.menu_bar.has_action(&"button_labels"):
		host.free()
		return
	check(host.menu_bar.is_checked(&"button_labels"),"labels start enabled")
	var entry: Dictionary = host.menu_bar._entries[host.menu_bar._key(&"button_labels",null)]
	check(entry.menu == host.menu_bar._menus["View"],"toggle is directly in View")
	var labeled_width := host.toolbar.custom_minimum_size.x
	var map_labels := host.city_view_3d.labels_visible
	host.menu_bar.press(&"button_labels")
	for frame in 8: await process_frame
	check(host.toolbar.button_for(Tools.Kind.ROAD).text.is_empty())
	check_lt(host.toolbar.size.x,labeled_width)
	check_eq(host.toolbar.offset_right,host.toolbar.custom_minimum_size.x,"host uses reduced width")
	check_eq(host.city_view_3d.labels_visible,map_labels,"map label visibility unchanged")
	check_eq(ViewPreferences.read(PREFS).get("button_labels"),false)
	host.free()
	await process_frame
	host = MainScene.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)
	for frame in 8: await process_frame
	check(not host.menu_bar.is_checked(&"button_labels"))
	check(host.toolbar.button_for(Tools.Kind.ROAD).text.is_empty(),"new host restores icon-only setting")
	host.toolbar.set_stage(Toolbar.Stage.EDITING)
	check(host.toolbar.found_button.text == "Found City","editor actions retain clear instructions")
	host.toolbar.set_stage(Toolbar.Stage.PLAY)
	check(host.toolbar.button_for(Tools.Kind.ROAD).text.is_empty(),"stage changes preserve setting")
	host.menu_bar.press(&"button_labels")
	check_eq(host.toolbar.button_for(Tools.Kind.ROAD).text,"Road\n")
	check_eq(ViewPreferences.read(PREFS).get("button_labels"),true)
	host.free()
	await process_frame
