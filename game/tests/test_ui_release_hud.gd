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
	var first := toolbar.button_for(Tools.Kind.ARCOLOGY_BODDY)
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

func test_inspector_refresh_clamps_to_the_completed_shorter_content() -> void:
	root.size = Vector2i(640,400)
	var query := QueryPanel.new()
	root.add_child(query)
	query.set_meta("display_usable_rect",Rect2(0,0,640,400))
	query.size = Vector2(320,240)
	var city := flat_city()
	var at := Vector2i(20,20)
	city.signs[at] = "W".repeat(Builder.SIGN_TEXT_MAX)
	query.show_tile(city,null,at)
	await _settle()
	query.body_scroll.scroll_vertical = 10000
	var reading := query.body_scroll.scroll_vertical
	check_gt(reading,0,"long content provides a real reading offset")
	city.signs[at] = "Short note"
	query.refresh(city,null)
	await _settle()
	var bar := query.body_scroll.get_v_scroll_bar()
	var final_limit := maxi(0,int(bar.max_value-bar.page))
	check_gt(reading,final_limit,"the settled shorter content cannot retain the old offset")
	check_eq(query.body_scroll.scroll_vertical,mini(reading,final_limit),"restoration clamps only to the final scroll range")
	query.free()

func test_inspector_delayed_restore_cannot_override_a_new_tile_or_close() -> void:
	root.size = Vector2i(640,400)
	var query := QueryPanel.new()
	root.add_child(query)
	query.set_meta("display_usable_rect",Rect2(0,0,640,400))
	query.size = Vector2(320,240)
	var city := flat_city()
	var at := Vector2i(20,20)
	city.signs[at] = "W".repeat(Builder.SIGN_TEXT_MAX)
	query.show_tile(city,null,at)
	await _settle()
	query.body_scroll.scroll_vertical = 10000
	check_gt(query.body_scroll.scroll_vertical,0,"fixture has an old reading position")
	city.signs[at] = "West Ridge Distribution"
	query.refresh(city,null)
	query.show_tile(city,null,Vector2i(21,20))
	await process_frame
	check(query.is_processing_input(),"an older restore cannot disable tracking for the new revision")
	await _settle()
	check_eq(query.tile,Vector2i(21,20),"new selection supersedes the pending refresh")
	check_eq(query.body_scroll.scroll_vertical,0,"old revision cannot scroll the new selection")
	query.show_tile(city,null,at)
	await _settle()
	city.signs[at] = "East Ridge Distribution"
	query.refresh(city,null)
	query.close()
	check(not query.is_processing_input(),"closing cancels pending input tracking immediately")
	await _settle()
	check(not query.visible,"a pending restoration cannot reopen the inspector")
	query.show_tile(city,null,Vector2i(21,20))
	await _settle()
	check_eq(query.body_scroll.scroll_vertical,0,"reopening a new tile starts at the top")
	city.signs[Vector2i(21,20)] = "Pending at removal"
	query.refresh(city,null)
	query.free()
	await _settle()

func test_inspector_pending_restore_preserves_newer_user_scrolling() -> void:
	for kind in ["wheel","keyboard","touch","pan","scrollbar"]:
		root.size = Vector2i(640,400)
		var query := QueryPanel.new()
		root.add_child(query)
		query.set_meta("display_usable_rect",Rect2(0,0,640,400))
		query.size = Vector2(320,240)
		var city := flat_city()
		var at := Vector2i(20,20)
		city.signs[at] = "W".repeat(Builder.SIGN_TEXT_MAX)
		query.show_tile(city,null,at)
		if kind == "touch": IOSGestureScroll._install(query.body_scroll)
		await _settle()
		check(not query.is_processing_input(),"idle inspector does not monitor input")
		if kind == "keyboard": query.close_button.grab_focus()
		query.body_scroll.scroll_vertical = 0
		city.signs[at] = "V"+"W".repeat(Builder.SIGN_TEXT_MAX-1)
		query.refresh(city,null)
		if kind == "keyboard":
			# Give Tab an actual reading target inside the scroll body without
			# depending on which optional inspector actions are currently shown.
			var reading_target := Button.new()
			reading_target.text = "Read this site"
			query.rows.add_child(reading_target)
		await process_frame
		var point := query.body_scroll.get_global_rect().get_center()
		var bar := query.body_scroll.get_v_scroll_bar()
		if kind == "wheel" or kind == "scrollbar":
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_WHEEL_DOWN if kind == "wheel" else MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = point if kind == "wheel" else bar.get_global_rect().end-Vector2(4,4)
			press.global_position = press.position
			root.push_input(press,true)
			var release := press.duplicate() as InputEventMouseButton
			release.pressed = false
			root.push_input(release,true)
		elif kind == "keyboard":
			var press := InputEventKey.new()
			press.keycode = KEY_TAB
			press.pressed = true
			root.push_input(press,true)
			var release := press.duplicate() as InputEventKey
			release.pressed = false
			root.push_input(release,true)
		elif kind == "pan":
			var pan := InputEventPanGesture.new()
			pan.position = point
			pan.delta = Vector2(0,1)
			root.push_input(pan,true)
		else:
			var press := InputEventScreenTouch.new()
			press.pressed = true
			press.position = point
			root.push_input(press,true)
			var drag := InputEventScreenDrag.new()
			drag.position = point-Vector2(0,12)
			drag.relative = Vector2(0,-12)
			root.push_input(drag,true)
			var release := press.duplicate() as InputEventScreenTouch
			release.pressed = false
			release.canceled = true
			release.position = drag.position
			root.push_input(release,true)
		var requested := query.body_scroll.scroll_vertical
		check_gt(requested,0,kind+" really moves the reading position")
		await _settle()
		check_eq(query.body_scroll.scroll_vertical,requested,kind+" supersedes the older refresh offset")
		check(not query.is_processing_input(),kind+" leaves no idle input monitor")
		query.close()
		check(not query.is_processing_input(),"closed inspector does not monitor input")
		query.free()

func test_inspector_preserves_an_existing_scrollbar_drag_outside_the_body() -> void:
	root.size = Vector2i(640,400)
	var query := QueryPanel.new()
	root.add_child(query)
	query.set_meta("display_usable_rect",Rect2(0,0,640,400))
	query.size = Vector2(320,240)
	var city := flat_city()
	var at := Vector2i(20,20)
	city.signs[at] = "W".repeat(Builder.SIGN_TEXT_MAX)
	query.show_tile(city,null,at)
	await _settle()
	var bar := query.body_scroll.get_v_scroll_bar()
	query.body_scroll.scroll_vertical = 0
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = bar.get_global_position()+Vector2(bar.size.x*0.5,bar.get_theme_icon("decrement").get_height()+5)
	press.global_position = press.position
	root.push_input(press,true)
	city.signs[at] = "V"+"W".repeat(Builder.SIGN_TEXT_MAX-1)
	query.refresh(city,null)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = bar.get_global_rect().end+Vector2(0,20)
	motion.relative = motion.position-press.position
	root.push_input(motion,true)
	var requested := query.body_scroll.scroll_vertical
	check_gt(requested,0,"a thumb drag outside the rectangle still scrolls")
	await _settle()
	check_eq(query.body_scroll.scroll_vertical,requested,"the active drag supersedes a later refresh restore")
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.position = motion.position
	root.push_input(release,true)
	query.free()

func test_inspector_keyboard_close_retires_a_pending_restore() -> void:
	root.size = Vector2i(640,400)
	var query := QueryPanel.new()
	root.add_child(query)
	query.set_meta("display_usable_rect",Rect2(0,0,640,400))
	query.size = Vector2(320,240)
	var city := flat_city()
	var at := Vector2i(20,20)
	city.signs[at] = "W".repeat(Builder.SIGN_TEXT_MAX)
	query.show_tile(city,null,at)
	await _settle()
	query.close_button.grab_focus()
	city.signs[at] = "V"+"W".repeat(Builder.SIGN_TEXT_MAX-1)
	query.refresh(city,null)
	var press := InputEventKey.new()
	press.keycode = KEY_ENTER
	press.pressed = true
	root.push_input(press,true)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release,true)
	check(not query.visible,"Enter closes the inspector before the deferred restore starts")
	await _settle()
	check(not query.is_processing_input(),"keyboard close leaves no idle input monitor")
	query.free()

func test_inspector_refresh_preserves_existing_touch_momentum() -> void:
	var previous_fps := Engine.max_fps
	Engine.max_fps = 60
	root.size = Vector2i(640,400)
	var query := QueryPanel.new()
	root.add_child(query)
	query.set_meta("display_usable_rect",Rect2(0,0,640,400))
	query.size = Vector2(320,240)
	var city := flat_city()
	var at := Vector2i(20,20)
	city.signs[at] = "W".repeat(Builder.SIGN_TEXT_MAX)
	query.show_tile(city,null,at)
	IOSGestureScroll._install(query.body_scroll)
	await _settle()
	query.body_scroll.scroll_vertical = 0
	var press := InputEventScreenTouch.new()
	press.pressed = true
	press.position = query.body_scroll.get_global_rect().get_center()
	root.push_input(press,true)
	var drag := InputEventScreenDrag.new()
	drag.position = press.position-Vector2(0,20)
	drag.relative = Vector2(0,-20)
	drag.velocity = Vector2(0,-600)
	root.push_input(drag,true)
	var release := press.duplicate() as InputEventScreenTouch
	release.pressed = false
	release.position = drag.position
	root.push_input(release,true)
	check(query.body_scroll.get_node("IOSGestureScroll").is_processing(),"touch release starts a real glide")
	city.signs[at] = "V"+"W".repeat(Builder.SIGN_TEXT_MAX-1)
	query.refresh(city,null)
	var previous := query.body_scroll.scroll_vertical
	for frame in 8:
		await process_frame
		check_ge(query.body_scroll.scroll_vertical,previous,"refresh never rewinds existing touch momentum")
		previous = query.body_scroll.scroll_vertical
	check(not query.is_processing_input(),"a glide does not leave a pending restoration monitor")
	query.free()
	Engine.max_fps = previous_fps
