# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

# These checks catch physical target shrinkage, inaccessible desktop-only
# options, and unpolished fallback picker controls at their real UI boundary.
func _run_all() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_factor = 1.0
	root.size = Vector2i(500,800)
	for method in get_method_list():
		if String(method.name).begins_with("test_"):
			_current = method.name
			var before := _failed
			await call(method.name)
			if _failed == before:
				_passed += 1
			else:
				print("  FAIL ",method.name)
	print("Results: %d passed, %d failed" % [_passed,_failed])
	quit(0 if _failed == 0 else 1)

func _settle() -> void:
	for frame in 4:
		await process_frame

func test_mobile_compact_window_keeps_point_targets_at_both_backing_scales() -> void:
	for backing in [1.0,2.0]:
		var layout := DisplayLayout.new()
		layout.refresh_with_mobile_metrics(Vector2i(Vector2(500,800) * backing),backing,Rect2i())
		check_eq(layout.logical_rect().size,Vector2(500,800),"compact mobile uses the real point canvas")
		for percent in [0,100,125,200]:
			layout.set_ui_scale(percent)
			check_ge(float(layout.metrics.scale) / backing * 44.0,44.0,"44-unit targets retain 44 physical points")
		check_eq(layout.metrics.get("mobile",false),true,"mobile display policy reaches option windows")
		layout.free()

func test_desktop_compact_scaling_still_uses_existing_canvas_cap() -> void:
	var layout := DisplayLayout.new()
	layout.refresh_with_metrics(Vector2i(500,800),1.0)
	check_eq(layout.metrics.scale,0.78125)
	check_eq(layout.logical_rect().size,Vector2(640,1024))
	layout.free()

func test_options_fullscreen_tracks_injected_platform_without_emitting() -> void:
	var options := OptionsWindow.new()
	var changes: Array = []
	options.option_changed.connect(func(key,value): changes.append([key,value]))
	options.set_display_metrics({"mobile":true,"requested_percent":0,"effective_percent":100.0})
	var fullscreen: CheckBox = options.checks[&"fullscreen"]
	check(not fullscreen.visible,"mobile cannot present the nonfunctional fullscreen action")
	check(fullscreen.disabled,"hidden mobile action is also disabled")
	options.set_values({"ui_scale":125,"effective_percent":100.0})
	check(not fullscreen.visible,"preference reflection retains the injected mobile policy")
	check(fullscreen.disabled,"partial scale readings cannot reenable fullscreen")
	options.set_display_metrics({"mobile":false,"requested_percent":0,"effective_percent":100.0})
	check(fullscreen.visible,"desktop keeps fullscreen")
	check(not fullscreen.disabled)
	check(changes.is_empty(),"display readings do not change preferences")
	options.free()

func test_popup_rows_have_touch_height() -> void:
	var popup := PopupMenu.new()
	popup.theme = UITheme.control_theme()
	root.add_child(popup)
	for text in ["Paused","Slow","Medium","Fast","Fastest"]:
		popup.add_item(text)
	popup.popup(Rect2i(8,8,240,300))
	await _settle()
	var panel_height := popup.get_theme_stylebox("panel").get_minimum_size().y
	var row_height := (popup.get_contents_minimum_size().y - panel_height) / 5.0
	check_ge(row_height,44.0,"actual popup content allocates at least 44 units per row")
	popup.free()

func test_menu_bar_uses_shared_surface_and_readable_states() -> void:
	var bar := MenuBar.new()
	bar.theme = UITheme.control_theme()
	root.add_child(bar)
	var popup := PopupMenu.new()
	popup.name = "City"
	bar.add_child(popup)
	await _settle()
	check_eq((bar.get_theme_stylebox("normal") as StyleBoxFlat).bg_color,UITheme.BUTTON_FACE)
	check_eq((bar.get_theme_stylebox("hover") as StyleBoxFlat).bg_color,UITheme.BEVEL_LIGHT)
	check_eq((bar.get_theme_stylebox("pressed") as StyleBoxFlat).bg_color,UITheme.TITLE_BAR)
	check_eq(bar.get_theme_color("font_color"),UITheme.TEXT_PRIMARY)
	check_eq(bar.get_theme_color("font_pressed_color"),UITheme.TITLE_TEXT)
	check_ge(bar.get_combined_minimum_size().y,44.0,"top-level menu targets retain touch height")
	bar.free()

func _visible_controls(node: Node, found: Array[Control]) -> void:
	for child: Node in node.get_children(true):
		if child is Window:
			continue
		if child is Control and child.is_visible_in_tree():
			found.append(child)
		_visible_controls(child,found)

func test_sandbox_file_picker_has_themed_reachable_touch_controls_and_rows() -> void:
	var files_dir := "user://ui-polish-files"
	DirAccess.make_dir_recursive_absolute(files_dir)
	for filename in ["Touch One.sc2","Touch Two.sc2","Touch Three.sc2"]:
		var output := FileAccess.open(files_dir.path_join(filename),FileAccess.WRITE)
		output.store_string("placeholder")
		output.close()
	var picker := FileDialog.new()
	var factory := UIFactory.new()
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.sc2 ; Classic city"])
	MobilePlatform.configure_file_picker(picker,{"os_name":"iOS","native_file_dialog":false})
	picker.current_dir = files_dir
	root.add_child(picker)
	factory.polish_file_picker(picker)
	picker.popup(Rect2i(8,8,484,750))
	await _settle()
	check_eq(picker.access,FileDialog.ACCESS_USERDATA,"touch polish retains sandbox confinement")
	check(not picker.use_native_dialog,"custom picker remains the unsupported-native fallback")
	check_eq(picker.theme,UITheme.control_theme(),"fallback uses the shared stone and teal theme")
	check_eq((picker.get_theme_stylebox("panel") as StyleBoxFlat).bg_color,UITheme.PANEL_FACE)
	var found: Array[Control] = []
	_visible_controls(picker,found)
	var button_count := 0
	var field_count := 0
	var row_count := 0
	for control: Control in found:
		if control is BaseButton:
			button_count += 1
			check_ge(control.size.x,44.0,"picker action width: %s" % control.tooltip_text)
			check_ge(control.size.y,44.0,"picker action height: %s" % control.tooltip_text)
		elif control is LineEdit:
			field_count += 1
			check_ge(control.size.y,44.0,"path and filename fields retain touch height")
		elif control is ItemList:
			for item in control.item_count:
				row_count += 1
				check_ge(control.get_item_rect(item).size.y,44.0,"file selection rows retain touch height")
	check_ge(button_count,5,"navigation and Open/Cancel were measured")
	check_ge(field_count,2,"path and filename were measured")
	check_eq(row_count,3,"the real file list contains the placeholder files")
	check(Rect2(0,0,500,800).encloses(Rect2(Vector2(picker.position),Vector2(picker.size))),"picker fits 500-point width")
	picker.free()
	for filename in ["Touch One.sc2","Touch Two.sc2","Touch Three.sc2"]:
		DirAccess.remove_absolute(files_dir.path_join(filename))
	DirAccess.remove_absolute(files_dir)

func test_native_picker_policy_survives_shared_polish() -> void:
	var picker := FileDialog.new()
	var factory := UIFactory.new()
	MobilePlatform.configure_file_picker(picker,{"os_name":"iOS","native_file_dialog":true})
	var directory := picker.current_dir
	factory.polish_file_picker(picker)
	check(picker.use_native_dialog,"supported native picker stays owned by the OS")
	check_eq(picker.access,FileDialog.ACCESS_FILESYSTEM)
	check_eq(picker.current_dir,directory)
	picker.free()

func test_fallback_picker_updates_shortcuts_when_host_resizes() -> void:
	root.size = Vector2i(500,800)
	var picker := FileDialog.new()
	picker.use_native_dialog = false
	picker.favorites_enabled = true
	picker.recent_list_enabled = false
	root.add_child(picker)
	var factory := UIFactory.new()
	factory.polish_file_picker(picker)
	await _settle()
	check(not picker.favorites_enabled,"compact layout yields shortcut width to file entries")
	root.size = Vector2i(1280,800)
	await _settle()
	check(picker.favorites_enabled,"wide layout restores the owner's favorites setting")
	check(not picker.recent_list_enabled,"owner-disabled recents stay disabled")
	root.size = Vector2i(500,800)
	await _settle()
	check(not picker.favorites_enabled,"shrinking restores compact browsing")
	picker.free()
