# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func _settle() -> void:
	for frame in 4: await process_frame

func test_selected_identity_reflow_keeps_focused_tool_reachable() -> void:
	for compact in [false,true]:
		var toolbar := Toolbar.new()
		root.add_child(toolbar)
		toolbar.apply_layout(compact)
		toolbar.size = Vector2(toolbar.custom_minimum_size.x,300)
		toolbar.set_active(Tools.Kind.QUERY)
		await _settle()
		var button := toolbar.button_for(Tools.Kind.NUCLEAR_PLANT)
		var scroll: ScrollContainer = toolbar.get_node("Shell/Scroll")
		button.grab_focus()
		scroll.ensure_control_visible(button)
		await _settle()
		toolbar.set_active(Tools.Kind.NUCLEAR_PLANT)
		await _settle()
		check(scroll.get_global_rect().encloses(button.get_global_rect()), "wrapped selected name keeps focused tool inside viewport")
		var last := toolbar.button_for(Tools.Kind.PLANT_TREE)
		last.grab_focus()
		scroll.ensure_control_visible(last)
		await _settle()
		toolbar.size.y -= 23
		await _settle()
		check(scroll.get_global_rect().encloses(last.get_global_rect()), "last row follows updated scroll range when status text grows")
		toolbar.free()

func test_category_jump_reveals_tools_without_selecting_or_building() -> void:
	var toolbar := Toolbar.new()
	root.add_child(toolbar)
	toolbar.apply_layout(true)
	toolbar.size = Vector2(196,300)
	await _settle()
	var picked: Array[int] = []
	toolbar.tool_selected.connect(func(tool: int) -> void: picked.append(tool))
	var index := toolbar.section_picker.get_item_index(Tools.Group.ARCOLOGY)
	toolbar.section_picker.select(index)
	toolbar.section_picker.item_selected.emit(index)
	await _settle()
	var first := toolbar.button_for(Tools.Kind.ARCOLOGY_LAST)
	var scroll: ScrollContainer = toolbar.get_node("Shell/Scroll")
	check(scroll.get_global_rect().encloses(first.get_global_rect()), "category jump reveals the cheapest resort first")
	check(first.has_focus(), "keyboard focus enters chosen category")
	check(picked.is_empty(), "navigation does not select a construction tool")
	toolbar.set_stage(Toolbar.Stage.EDITING)
	check(not toolbar.section_picker.visible, "editor shows only its terrain tools")
	toolbar.free()

func test_toolbar_keyboard_reveals_tools_and_keeps_price_identity() -> void:
	var toolbar := Toolbar.new()
	root.add_child(toolbar)
	toolbar.apply_layout(true)
	toolbar.size = Vector2(196,300)
	await _settle()
	var scroll: ScrollContainer = toolbar.get_node("Shell/Scroll")
	var button: Button = toolbar.button_for(Tools.Kind.RAISE_LAND)
	# Use the last actual enabled tool, independently of catalog order.
	for group: int in Toolbar.GROUP_ORDER:
		for child: Node in toolbar._grids[group].get_children():
			if child is Button and not child.disabled: button = child
	button.grab_focus()
	await _settle()
	check(scroll.get_global_rect().encloses(button.get_global_rect()),"keyboard focus scrolls the last tool into view")
	toolbar.set_active(Tools.Kind.ROAD)
	check(toolbar.selected_label.text.contains("$10"),"selected tool keeps its price visible")
	var road: Button = toolbar.button_for(Tools.Kind.ROAD)
	check_ne(road.get_theme_stylebox("hover").bg_color,toolbar.button_for(Tools.Kind.RAIL).get_theme_stylebox("hover").bg_color,"hover preserves selected identity")
	toolbar.free()

func test_speed_status_demand_text_and_compact_layout() -> void:
	root.size = Vector2i(640,400)
	var bar := StatusBar.new()
	root.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -220
	bar.apply_layout(640)
	bar.set_funds(2147483647)
	bar.set_population(2147483647)
	bar.set_demand(Vector3i(100,-50,0))
	for speed: int in GameClock.Speed.values():
		bar.set_speed(speed)
		check_eq(bar.speed_label.text,GameClock.SPEED_NAMES[speed],"current menu speed remains visible")
	check_eq(bar.find_children("*","Button",true,false), [bar.emergency_button], "footer retains emergency navigation without duplicate speed buttons")
	check(bar.demand_meter.tooltip_text.contains("100") and bar.demand_meter.tooltip_text.contains("-50"),"demand has readable numeric meaning")
	check_ne(bar.demand_meter.mouse_filter,Control.MOUSE_FILTER_IGNORE,"demand explanation can be hovered")
	await _settle()
	check(Rect2(0,0,640,400).encloses(bar.speed_label.get_global_rect()),"compact speed status visible")
	bar.free()

func test_inspector_refresh_keeps_rows_and_scroll_but_new_tile_starts_at_top() -> void:
	var query := QueryPanel.new()
	root.add_child(query)
	query.size = Vector2(320,280)
	var city := flat_city()
	query.show_tile(city,null,Vector2i(20,20))
	await _settle()
	query.body_scroll.scroll_vertical = 150
	await _settle()
	var scroll := query.body_scroll.scroll_vertical
	var first := query.rows.get_child(0).get_instance_id()
	query.show_tile(city,null,Vector2i(20,20))
	await _settle()
	check_eq(query.rows.get_child(0).get_instance_id(),first,"unchanged description retains widgets")
	check_eq(query.body_scroll.scroll_vertical,scroll,"same tile retains reading position")
	city.signs[Vector2i(20,20)] = "New service district"
	query.refresh(city,null)
	await _settle()
	check_eq(query.info.get("Sign",""),"New service district","refresh reads current tile")
	check_eq(query.body_scroll.scroll_vertical,scroll,"changed same-tile rows preserve reading position")
	query.show_tile(city,null,Vector2i(21,20))
	await _settle()
	check_eq(query.body_scroll.scroll_vertical,0,"new tile exposes site identity first")
	query.close()
	query.refresh(city,null)
	check(not query.visible,"background refresh never reopens inspector")
	query.free()

func test_menu_hints_do_not_register_duplicate_shortcuts() -> void:
	var menu := GameMenuBar.new()
	for action: StringName in [&"rotate",&"underground"]:
		var entry: Dictionary = menu._entries[menu._key(action,null)]
		var popup: PopupMenu = entry.menu
		var index := popup.get_item_index(entry.id)
		check(popup.get_item_text(index).contains("[R]" if action == &"rotate" else "[U]"),"menu advertises existing shortcut")
		check_eq(popup.get_item_accelerator(index),0,"Main retains shortcut ownership")
	menu.free()
