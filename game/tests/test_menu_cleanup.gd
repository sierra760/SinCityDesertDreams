# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func test_navigation_groups_retain_actions_and_popup_suspension() -> void:
	var menu := GameMenuBar.new()
	check_eq(menu.menu_titles(),["City","Speed","View","Reports","Disasters","Help"] as Array[String])
	check(menu._menus["View"].item_count<=12,"primary view menu stays short")
	check(menu._entries[menu._key(&"options",null)].menu == menu._menus["City"])
	check(not menu.has_action(&"auto_budget"),"Budget owns auto budget")
	var events: Array = []
	menu.popup_opened.connect(func(): events.append("popup"))
	menu.action_requested.connect(func(action,value): events.append([action,value]))
	var popup: PopupMenu = menu._entries[menu._key(&"overlay",&"traffic")].menu
	popup.about_to_popup.emit()
	menu.press(&"overlay",&"traffic")
	check_eq(events[0],"popup","nested menu suspends Explore before action")
	check_eq(events[1],[&"overlay",&"traffic"])
	menu.set_enabled(&"overlay",false,&"traffic")
	menu.press(&"overlay",&"traffic")
	check_eq(events.size(),2,"disabled nested action is inert")
	menu.free()

func test_options_has_one_home_for_each_preference() -> void:
	var options := OptionsWindow.new()
	check_eq(options.checks.keys(),[&"pause_in_background",&"fullscreen",&"tile_grid",&"water_animation"])
	var menu := GameMenuBar.new()
	for action: StringName in options.checks.keys():
		check(not menu.has_action(action),"Options alone owns " + String(action))
	menu.free()
	check(not options.values().has("zoom"))
	check(options.quality_button != null and options.resolution_button != null and options.scale_button != null)
	options.free()

func test_file_shortcuts_reach_the_menu_actions() -> void:
	var menu := GameMenuBar.new()
	root.add_child(menu)
	var events: Array = []
	menu.action_requested.connect(func(action,value): events.append(action))
	for case: Array in [[KEY_S,false,&"city_save"],[KEY_S,true,&"city_save_as"],[KEY_N,false,&"city_new"],[KEY_O,false,&"city_load"]]:
		var key := InputEventKey.new()
		key.keycode = case[0]
		key.pressed = true
		key.shift_pressed = case[1]
		if OS.get_name() == "macOS": key.meta_pressed = true
		else: key.ctrl_pressed = true
		var popup: PopupMenu = menu._entries[menu._key(case[2],null)].menu
		check(popup.activate_item_by_event(key,false),"%s has a keyboard shortcut" % String(case[2]))
		check_eq(events.back(),case[2])
	menu.free()
