# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

# Await layout frames: this suite measures the containers that players use.
func _run_all() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_factor = 1.0
	root.size = Vector2i(1280,800)
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

func test_readable_tiers_and_targets() -> void:
	check_eq(UITheme.FONT_BODY,16)
	check_eq(UITheme.FONT_SMALL,14)
	check_eq(UITheme.FONT_HEADER,18)
	check_eq(UITheme.FONT_TITLE,22)
	var chrome := UIFactory.make_window_chrome("A long but readable title")
	check(chrome.has("body_scroll"))
	check(chrome.has("actions"))
	check_ge(chrome["close_button"].custom_minimum_size.x,44)
	check_ge(chrome["close_button"].custom_minimum_size.y,44)
	var button := UIFactory.make_button("Build")
	check_ge(button.custom_minimum_size.y,44)
	button.free()
	chrome["root"].free()
func test_palette_compact_and_selected_identity() -> void:
	var toolbar := Toolbar.new()
	toolbar.apply_layout(false)
	for group in toolbar._grids:
		check_eq(toolbar._grids[group].columns,2)
	toolbar.apply_layout(true)
	for group in toolbar._grids:
		check_eq(toolbar._grids[group].columns,2)
	for tool in Tools.all():
		check(toolbar.button_for(tool) != null)
		check_ge(toolbar.button_for(tool).custom_minimum_size.x,44)
		check_ge(toolbar.button_for(tool).custom_minimum_size.y,44)
	toolbar.set_active(Tools.Kind.SUBWAY)
	check(toolbar.selected_label.text.contains(Tools.display_name(Tools.Kind.SUBWAY)))
	toolbar.free()
func test_large_status_and_refusal_text() -> void:
	var bar := StatusBar.new()
	bar.set_funds(2147483647)
	bar.set_population(2147483647)
	bar.set_tool_text("Subway Station")
	bar.set_message("Cannot build here: " + "steep terrain near the waterfront ".repeat(10))
	check(bar.funds_label.text.contains("2,147,483,647"))
	check(bar.population_label.text.contains("2,147,483,647"))
	check_eq(bar.message_label.autowrap_mode,TextServer.AUTOWRAP_WORD_SMART)
	for width in [1280,1000,640]:
		bar.apply_layout(width)
		check(bar.speed_label.get_parent() == bar._metrics_row,"speed shares the city metrics row")
		check_eq(bar.find_children("*","Button",true,false), [bar.emergency_button], "emergency navigation is the only footer action; speed stays in its menu")
	bar.free()
func test_fit_three_logical_sizes() -> void:
	for size in [Vector2(1280,800),Vector2(1000,640),Vector2(640,400)]:
		var fitted := DisplayLayout.fit_window_rect(Rect2(900,900,900,800),Rect2(Vector2.ZERO,size),44)
		check(Rect2(Vector2.ZERO,size).encloses(fitted))
		check_ge(fitted.size.y,44)

func _settle() -> void:
	for frame in 4:
		await process_frame

func test_live_chrome_resize_recovery_and_scrolling() -> void:
	root.size = Vector2i(1440,900)
	var holder := Control.new()
	root.add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var chrome := UIFactory.make_window_chrome("Treasury and city statistics")
	var panel: Control = chrome["root"]
	holder.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -440
	panel.offset_right = 440
	panel.offset_top = -300
	panel.offset_bottom = 300
	var body: VBoxContainer = chrome["body"]
	for row in 40:
		body.add_child(UIFactory.make_label("Statistics row %d: 2,147,483,647" % row))
	var action := UIFactory.make_button("Done")
	chrome["actions"].add_child(action)
	await _settle()
	panel.position = Vector2(1100,700)
	for dimensions in [Vector2i(1280,800),Vector2i(1000,640),Vector2i(640,400)]:
		root.size = dimensions
		await _settle()
		var available := Rect2(Vector2.ZERO,Vector2(dimensions))
		check(available.encloses(panel.get_global_rect()),"panel recovers inside %s: %s" % [dimensions,panel.get_global_rect()])
		check(available.encloses(chrome["close_button"].get_global_rect()),"close stays reachable")
		check(available.encloses(action.get_global_rect()),"fixed action stays reachable")
		check_lt(chrome["body_scroll"].size.y,body.size.y,"large body scrolls internally")
	holder.free()

func test_live_status_controls_never_overlap() -> void:
	var bar := StatusBar.new()
	root.add_child(bar)
	bar.set_funds(2147483647)
	bar.set_population(2147483647)
	bar.set_date("December 31, 2050")
	bar.set_tool_text("Subway Station")
	bar.set_message("Cannot build here: " + "steep terrain near the waterfront ".repeat(10))
	for dimensions in [Vector2i(1280,800),Vector2i(1000,640),Vector2i(640,400)]:
		root.size = dimensions
		bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = -220
		bar.apply_layout(dimensions.x)
		for emergency in [false,true]:
			bar.set_emergency_available(emergency)
			await _settle()
			var controls := bar._metrics_row.get_children().filter(func(control: Control) -> bool: return control.visible)
			for i in controls.size():
				for j in range(i+1,controls.size()):
					check(not controls[i].get_global_rect().intersects(controls[j].get_global_rect()),"visible status metrics do not overlap")
			check_le_rect(bar.funds_label.get_global_rect(),Rect2(Vector2.ZERO,Vector2(dimensions)),"treasury fits")
			check_le_rect(bar.population_label.get_global_rect(),Rect2(Vector2.ZERO,Vector2(dimensions)),"population fits")
			check_le_rect(bar.speed_label.get_global_rect(),Rect2(Vector2.ZERO,Vector2(dimensions)),"speed status fits")
			if emergency:
				check_le_rect(bar.emergency_button.get_global_rect(),Rect2(Vector2.ZERO,Vector2(dimensions)),"emergency action fits")
	bar.free()

func check_le_rect(rect: Rect2, available: Rect2, message: String) -> void:
	check(available.encloses(rect),message + ": " + str(rect))

func test_new_city_stacks_and_inspector_actions_are_fixed() -> void:
	root.size = Vector2i(640,400)
	var dialog := NewCityDialog.new()
	root.add_child(dialog)
	dialog.apply_layout(true)
	dialog.visible = true
	await _settle()
	check_eq(dialog.form_columns.columns,1)
	check(Rect2(0,0,640,400).encloses(dialog.start_button.get_global_rect()))
	check(Rect2(0,0,640,400).encloses(dialog.cancel_button.get_global_rect()))
	dialog.free()
	var query := QueryPanel.new()
	root.add_child(query)
	query.size = Vector2(320,300)
	var city := flat_city()
	city.add_facility(Vector2i(10,10),{"name":"Sandstone " + "Civic Center ".repeat(12)})
	query.show_tile(city,null,Vector2i(10,10))
	await _settle()
	check(query.lines().any(func(line: String) -> bool: return line.contains("Civic Center")))
	check(query.rename_button.get_global_rect().position.y >= query.body_scroll.get_global_rect().end.y)
	check(query.demolish_button.get_global_rect().position.y >= query.body_scroll.get_global_rect().end.y)
	check_lt(query.body_scroll.size.y,query.rows.size.y)
	query.free()

func test_every_information_window_keeps_its_close_control_visible() -> void:
	for dimensions in [Vector2i(1280,800),Vector2i(1000,640),Vector2i(640,400)]:
		root.size = dimensions
		for window in [BudgetWindow.new(),GraphsWindow.new(),PopulationWindow.new(),IndustriesWindow.new(),OrdinancesWindow.new(),NewspaperWindow.new(),NeighborsWindow.new(),HelpWindow.new(),OptionsWindow.new()]:
			root.add_child(window)
			window.bind(null)
			window.open()
			await _settle()
			var panel: Control = window.get("panel") if window is HelpWindow or window is OptionsWindow else window.get("_root")
			var chrome: Dictionary = panel.get_meta("window_chrome")
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(panel.get_global_rect()),"%s panel fits %s" % [window.get_class(),dimensions])
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(chrome["close_button"].get_global_rect()),"close stays visible")
			window.free()
