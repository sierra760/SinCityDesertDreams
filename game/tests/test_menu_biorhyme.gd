# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func settle() -> void:
	for frame in 8: await process_frame

func test_body_controls_use_biorhyme() -> void:
	var panel := UIFactory.make_panel()
	root.add_child(panel)
	for widget: Control in [UIFactory.make_label("City treasury"),UIFactory.make_button("Save City"),LineEdit.new(),RichTextLabel.new(),TabBar.new()]:
		panel.add_child(widget)
		var key := "normal_font" if widget is RichTextLabel else "font"
		check_eq(widget.get_theme_font(key),UITheme.DISPLAY_FONT,"BioRhyme on "+widget.get_class())
	panel.free()

func test_menu_targets_fit_the_reserved_bar_height() -> void:
	var bar := GameMenuBar.new()
	root.add_child(bar)
	for phone: bool in [false,true]:
		bar.set_phone_layout(phone)
		for tools_open: bool in [false,true]:
			bar.set_phone_build_available(true,tools_open)
			bar.size = Vector2(320 if phone else 640,GameMenuBar.BAR_HEIGHT)
			await settle()
			check_eq(bar.size.y,float(GameMenuBar.BAR_HEIGHT),"menu surface stays in its reserved height")
			if phone:
				for button: Button in [bar.phone_tools_button,bar.phone_inspect_button,bar._phone_menu]:
					check(bar.get_global_rect().encloses(button.get_global_rect()),"phone action fits "+button.text)
					check_ge(button.size.y,44.0,"phone action retains touch height")
	bar.free()

func test_all_tool_buttons_fit_the_sidebar_with_complete_captions() -> void:
	var toolbar := Toolbar.new()
	root.add_child(toolbar)
	for compact: bool in [false,true]:
		toolbar.apply_layout(compact)
		toolbar.size = Vector2(toolbar.custom_minimum_size.x,700)
		await settle()
		check_eq(toolbar.size.x,toolbar.custom_minimum_size.x,"sidebar retains declared width")
		var scroll := toolbar.get_node("Shell/Scroll") as ScrollContainer
		var column := scroll.get_child(0) as Control
		var width := scroll.size.x - (scroll.get_v_scroll_bar().size.x if scroll.get_v_scroll_bar().visible else 0.0)
		check(column.size.x <= width,"tool column fits scroll viewport")
		for tool: int in Tools.all():
			var button := toolbar.button_for(tool)
			var font := button.get_theme_font("font")
			var padding := button.get_theme_stylebox("normal").get_minimum_size().x
			for line: String in button.text.split("\n"):
				check(font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x <= button.size.x-padding,"complete caption: "+line)
			check_ge(button.size.x,44.0)
			check_ge(button.size.y,44.0)
	toolbar.free()

func test_explore_menu_buttons_fit_the_menu_width() -> void:
	for dimensions: Vector2i in [Vector2i(640,400),Vector2i(320,568),Vector2i(667,375)]:
		root.size = dimensions
		var layout := DisplayLayout.new()
		root.add_child(layout)
		layout.bind(root)
		layout.refresh_with_mobile_metrics(dimensions,1.0,Rect2i())
		var hud := ExploreHUD.new()
		root.add_child(hud)
		hud.bind_layout(layout)
		hud.set_touch_controls_enabled(true)
		hud.set_chrome_insets(44,109)
		hud.show_session(true)
		hud.set_suspended(true)
		await settle()
		for button: Button in hud._panel.find_children("*","Button",true,false):
			check(button.get_global_rect().position.x >= hud._panel.global_position.x,"menu action starts inside panel")
			check(button.get_global_rect().end.x <= hud._panel.get_global_rect().end.x,"menu action ends inside panel: "+button.text)
		check(layout.logical_rect().encloses(hud._panel.get_global_rect()),"Explore menu fits "+str(dimensions))
		hud.free()
		layout.free()

func test_small_phone_reports_fit_their_visible_body_width() -> void:
	root.size = Vector2i(320,568)
	var host: GameHost = load("res://scenes/main.tscn").instantiate()
	host.preferences_path = "user://menu-biorhyme-reports.cfg"
	root.add_child(host)
	host.display_layout.set_ui_scale(100)
	host.display_layout.refresh_with_mobile_metrics(root.size,1.0,Rect2i())
	host.begin_city(flat_city(),{},123,null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	for name: String in ["budget","graphs","population","options"]:
		var window := host.open_window(name)
		await settle()
		var panel: Control = window.get("panel") if name=="options" else window.get("_root")
		var scroll: ScrollContainer = panel.get_meta("window_chrome").body_scroll
		check(scroll.get_h_scroll_bar().max_value<=scroll.get_h_scroll_bar().page+1.0,"BioRhyme report has no sideways reading: "+name)
		if scroll.get_h_scroll_bar().max_value>scroll.get_h_scroll_bar().page+1.0:
			for control: Control in (scroll.get_child(0) as Control).find_children("*","Control",true,false):
				if control.get_combined_minimum_size().x > scroll.size.x: print("OVERFLOW ",control.get_path()," min ",control.get_combined_minimum_size()," available ",scroll.size)
		host.window_manager.close_all()
	host.free()
