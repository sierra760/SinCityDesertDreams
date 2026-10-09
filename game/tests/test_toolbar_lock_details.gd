# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

var toolbar: Toolbar

func before_each() -> void:
	root.size = Vector2i(640,480)
	toolbar = Toolbar.new()
	root.add_child(toolbar)
	toolbar.size = Vector2(224,440)
	toolbar.set_active(Tools.Kind.ROAD)
	var city := flat_city()
	city.founded_year = 1900
	toolbar.refresh(city,CityStats.new())

func after_each() -> void:
	if is_instance_valid(toolbar): toolbar.free()
	toolbar = null
	await process_frame

func test_tapping_locked_tools_explains_without_selecting_in_both_layouts() -> void:
	var picked: Array[int] = []
	toolbar.tool_selected.connect(func(tool: int) -> void: picked.append(tool))
	for labeled: bool in [true,false]:
		toolbar.set_button_labels_visible(labeled)
		toolbar.size.x = toolbar.custom_minimum_size.x
		await _settle()
		var subway := toolbar.button_for(Tools.Kind.SUBWAY)
		check(subway.disabled,"locked construction button remains disabled")
		var scroll := toolbar.get_node("Shell/Scroll") as ScrollContainer
		scroll.ensure_control_visible(subway)
		await _settle()
		await _click(subway.get_global_rect().get_center())
		var details := toolbar.get_node_or_null("Shell/LockDetails") as Control
		check(details != null and details.visible,"tap opens visible lock details without requiring hover")
		check(picked.is_empty(),"locked tap never emits a construction selection")
		check_eq(toolbar.active_tool,Tools.Kind.ROAD,"lock explanation preserves the active tool")
		if details == null: continue
		var text := details.get_node("Body/Reason") as Label
		check(text.text.contains("Not available until") and text.text.contains("1910"),"explanation includes the actual unlock condition")
		var title := details.get_node("Body/Identity") as Label
		check(title.text.contains(Tools.display_name(Tools.Kind.SUBWAY)),"icon-only details name the tool")
		var close := details.get_node("Body/Close") as Button
		check_ge(close.size.y,44,"dismissal remains a usable touch target")
		check(toolbar.get_global_rect().encloses(details.get_global_rect()),"details fit within the sidebar")
		await _click(close.get_global_rect().get_center())
		check(not details.visible,"details can be dismissed by a tap")

func test_locked_programmatic_press_cannot_bypass_and_unlock_closes_stale_details() -> void:
	var picked: Array[int] = []
	toolbar.tool_selected.connect(func(tool: int) -> void: picked.append(tool))
	var subway := toolbar.button_for(Tools.Kind.SUBWAY)
	subway.pressed.emit()
	check(picked.is_empty(),"lock guard also protects signal/programmatic activation")
	await _settle()
	(toolbar.get_node("Shell/Scroll") as ScrollContainer).ensure_control_visible(subway)
	await _settle()
	await _click(subway.get_global_rect().get_center())
	var details := toolbar.get_node_or_null("Shell/LockDetails") as Control
	check(details != null and details.visible,"locked tap supplies the reason panel")
	var city := flat_city()
	city.founded_year = 1920
	toolbar.refresh(city,CityStats.new())
	check(not subway.disabled and not toolbar.is_locked(Tools.Kind.SUBWAY),"unlock retains normal availability")
	if details != null: check(not details.visible,"unlock removes the stale lock explanation")
	subway.pressed.emit()
	check_eq(picked,[Tools.Kind.SUBWAY] as Array[int],"unlocked tool keeps its normal signal route")

func test_lock_details_track_current_reason_and_stage_without_changing_city() -> void:
	await _settle()
	var dispatch := toolbar.button_for(Tools.Kind.DISPATCH_FIRE)
	(toolbar.get_node("Shell/Scroll") as ScrollContainer).ensure_control_visible(dispatch)
	await _settle()
	await _click(dispatch.get_global_rect().get_center())
	var details := toolbar.get_node_or_null("Shell/LockDetails") as Control
	check(details != null and details.visible,"emergency tool lock has a tap explanation")
	if details == null: return
	check((details.get_node("Body/Reason") as Label).text.contains("only during an emergency"),"details use current emergency availability")
	toolbar.set_stage(Toolbar.Stage.EDITING)
	check(not details.visible,"terrain editor removes irrelevant construction details")
	check_eq(toolbar.active_tool,Tools.Kind.ROAD)

func test_locked_category_can_explain_from_keyboard_without_selecting() -> void:
	await _settle()
	var picked: Array[int] = []
	toolbar.tool_selected.connect(func(tool: int) -> void: picked.append(tool))
	var index := toolbar.section_picker.get_item_index(Tools.Group.ARCOLOGY)
	toolbar.section_picker.select(index)
	toolbar.section_picker.item_selected.emit(index)
	await _settle()
	var info := toolbar.button_for(Tools.Kind.ARCOLOGY_COMSTOCK).get_node("LockInfo") as Button
	check(info.has_focus(),"an entirely locked category offers keyboard access to its first explanation")
	for pressed: bool in [true,false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER
		key.pressed = pressed
		root.push_input(key)
		await process_frame
	await _settle()
	var details := toolbar.get_node("Shell/LockDetails") as Control
	check(details.visible,"keyboard activation opens the same lock explanation")
	check(picked.is_empty(),"information keyboard route never selects construction")
	check_eq(toolbar.active_tool,Tools.Kind.ROAD)

func _settle() -> void:
	for frame in 8: await process_frame

func _click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)
		await process_frame
	await _settle()
