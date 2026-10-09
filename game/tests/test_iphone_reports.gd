# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Phone reports must expose their controls without a horizontal pan.
extends "res://tests/exploration/async_test_case.gd"
const HostFixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost
func before_each() -> void:
	host = HostFixture.make_host(self, "iphone-reports-tests")
func after_each() -> void:
	host.free()
	await process_frame
func test_phone_report_bodies_fit_without_horizontal_scrolling() -> void:
	root.size = Vector2i(375,667)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,20,375,647))
	await HostFixture.settle(self, 10)
	for window_name in ["budget","graphs","population","industries","ordinances","newspaper","city_maps","neighbors","options","help","license"]:
		var window := host.open_window(window_name)
		await HostFixture.settle(self, 10)
		var panel: Control = window.get("panel") if window_name in ["options","help","license"] else window.get("_root")
		var chrome: Dictionary = panel.get_meta("window_chrome")
		var scroll: ScrollContainer = chrome.body_scroll
		check(host.display_layout.logical_rect().grow(.1).encloses(panel.get_global_rect()),window_name+" bounds")
		check(scroll.get_h_scroll_bar().max_value<=scroll.get_h_scroll_bar().page+1.0,window_name+" requires no sideways reading")
		if scroll.get_h_scroll_bar().max_value>scroll.get_h_scroll_bar().page+1.0:
			for control: Control in (chrome.body as Control).find_children("*","Control",true,false):
				if control.get_combined_minimum_size().x > scroll.size.x:
					print("OVERFLOW ",control.get_path()," minimum=",control.get_combined_minimum_size()," available=",scroll.size)
		check_ge((chrome.close_button as Control).size.y,44)
		host.window_manager.close_all()
func test_phone_dialogs_keep_actions_inside_notch_and_keyboard_rect() -> void:
	for display: Dictionary in [
		{"size":Vector2i(320,568),"safe":Rect2i(0,20,320,548),"keyboard":216},
		{"size":Vector2i(667,375),"safe":Rect2i(0,0,667,375),"keyboard":150},
		{"size":Vector2i(844,390),"safe":Rect2i(47,0,750,369),"keyboard":0}]:
		root.size = display.size
		host.display_layout.refresh_with_mobile_metrics(root.size,1,display.safe,display.keyboard)
		await HostFixture.settle(self, 10)
		for dialog: Control in [host.new_city_dialog,host.save_dialog,host.load_dialog,host.share_dialog]:
			if dialog == host.load_dialog: host.load_dialog.open([] as Array[Dictionary])
			elif dialog == host.share_dialog:
				host.push_modal()
				host.share_dialog.open({"name":"Desert Springs","mayor":"Mayor","path":"user://fixture.sc2d","message":""})
			else: dialog.call("open")
			await HostFixture.settle(self, 10)
			var panel: Control = dialog.get("panel")
			var chrome: Dictionary = panel.get_meta("window_chrome")
			check(host.display_layout.logical_rect().grow(.1).encloses(panel.get_global_rect()),dialog.name+" fits physical occlusion")
			var scroll: ScrollContainer = chrome.body_scroll
			check(scroll.get_h_scroll_bar().max_value<=scroll.get_h_scroll_bar().page+1.0,dialog.name+" fits narrow content")
			for button: BaseButton in (chrome.actions as Control).find_children("*","BaseButton",true,false):
				check(host.display_layout.logical_rect().grow(.1).encloses(button.get_global_rect()),"persistent "+button.text)
				check_ge(button.size.y,44)
			dialog.call("close")
func test_narrow_report_controls_still_write_normal_simulation_fields() -> void:
	root.size=Vector2i(375,667)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,20,375,647))
	var budget := host.open_window("budget") as BudgetWindow
	await HostFixture.settle(self, 10)
	budget._tax_spinners[&"residential"]._plus.pressed.emit()
	check_eq(host.sim.stats.tax_residential,8,"reflow retains real tax field")
	budget.set_funding(&"roads",40)
	check_eq(host.sim.stats.funding_of(&"roads"),40,"reflow retains real funding")
	host.window_manager.close_all()
	var industries := host.open_window("industries") as IndustriesWindow
	await HostFixture.settle(self, 10)
	var spinner := industries._sector_rows[0][4] as TouchNumberField
	spinner._plus.pressed.emit()
	check_eq(host.sim.stats.sector_taxes[0],8,"sector card retains live tax signal")

func test_month_refresh_keeps_a_tax_rate_being_typed() -> void:
	var budget := host.open_window("budget") as BudgetWindow
	await HostFixture.settle(self, 10)
	var tax := budget._tax_spinners[&"residential"] as TouchNumberField
	var edit := tax.get_line_edit()
	edit.grab_focus()
	edit.text = "1"
	edit.text_changed.emit(edit.text)
	budget._on_month_ended(1900, 2)
	check_eq(edit.text, "1", "budget refresh leaves the half-typed rate alone")
	edit.text = "12"
	edit.text_changed.emit(edit.text)
	budget._on_month_ended(1900, 3)
	check_eq(edit.text, "12")
	edit.text_submitted.emit(edit.text)
	check_eq(host.sim.stats.tax_residential, 12, "the typed rate commits")
	check_eq(edit.text, "12")
	host.sim.stats.tax_residential = 9
	budget._on_month_ended(1900, 4)
	check_eq(edit.text, "9", "committed fields follow the simulation again")
	host.window_manager.close_all()
	var industries := host.open_window("industries") as IndustriesWindow
	await HostFixture.settle(self, 10)
	var sector := industries._sector_rows[0][4] as TouchNumberField
	sector.get_line_edit().grab_focus()
	sector.get_line_edit().text = "1"
	sector.get_line_edit().text_changed.emit("1")
	industries._on_month_ended(1900, 5)
	check_eq(sector.get_line_edit().text, "1", "industries refresh leaves typing alone")

func test_narrow_numeric_rows_keep_their_labels_readable() -> void:
	root.size=Vector2i(375,667)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,20,375,647))
	var budget := host.open_window("budget") as BudgetWindow
	await HostFixture.settle(self, 10)
	var tax := budget._tax_spinners[&"residential"] as TouchNumberField
	var caption := tax.get_parent().get_child(0) as Label
	check_eq(caption.text,"Rate")
	check_eq(caption.get_line_count(),1,"Rate stays a word, not a vertical letter column")
	check(tax.size.y<=64.0,"numeric action row keeps natural touch height")
	host.window_manager.close_all()
	var industries := host.open_window("industries") as IndustriesWindow
	await HostFixture.settle(self, 10)
	var demand := industries._sector_rows[0][1] as Label
	caption=demand.get_parent().get_child(0) as Label
	check_eq(caption.text,"Demand")
	check_eq(caption.get_line_count(),1,"Demand stays readable beside its value")

func test_resized_moved_report_returns_inside_the_phone_safe_area() -> void:
	root.size=Vector2i(390,844)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,47,390,763))
	var budget := host.open_window("budget") as BudgetWindow
	await HostFixture.settle(self, 10)
	budget._root.position=Vector2(0,0)
	budget._root.resized.emit()
	await HostFixture.settle(self, 10)
	check(host.display_layout.logical_rect().grow(.1).encloses(budget._root.get_global_rect()),"drag resize recovery honors notch bounds")

func test_population_legend_keeps_words_and_compact_color_keys() -> void:
	var population := host.open_window("population") as PopulationWindow
	for display_size: Vector2i in [Vector2i(320,568),Vector2i(375,667),Vector2i(667,375),Vector2i(844,390),Vector2i(1194,834)]:
		root.size=display_size
		host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(Vector2i.ZERO,root.size))
		await HostFixture.settle(self, 10)
		for label: Label in population._body.find_children("*","Label",true,false):
			if label.text not in ["People","Education","Health"] or not label.get_parent() is HBoxContainer: continue
			check_eq(label.get_line_count(),1,"legend caption remains a readable word at "+str(display_size))
			var swatch := label.get_parent().get_child(0) as ColorRect
			check(swatch.size.y<=10.0,"color key stays compact")
		var scroll: ScrollContainer=population._root.get_meta("window_chrome").body_scroll
		check(scroll.get_h_scroll_bar().max_value<=scroll.get_h_scroll_bar().page+1.0,"legend fits narrow body")
		if scroll.get_h_scroll_bar().max_value>scroll.get_h_scroll_bar().page+1.0:
			print("POPULATION SCROLL ",scroll.size," max/page ",scroll.get_h_scroll_bar().max_value,"/",scroll.get_h_scroll_bar().page)
			for control: Control in population._body.find_children("*","Control",true,false):
				if control is BoxContainer or control is GridContainer or control is HFlowContainer:
					print(control.get_path()," rect=",control.get_rect()," min=",control.get_combined_minimum_size())

func test_scrolled_graph_range_caption_and_actions_remain_compact() -> void:
	root.size=Vector2i(375,667)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,20,375,647))
	var graphs := host.open_window("graphs") as GraphsWindow
	await HostFixture.settle(self, 10)
	var span: Label
	for label: Label in graphs._body.find_children("*","Label",true,false):
		if label.text=="Span": span=label
	check(span!=null,"range caption remains present")
	if span!=null: check_eq(span.get_line_count(),1,"Span stays a word beside its actions")
	for button: Button in graphs._range_buttons.values():
		check(button.size.y<=64,"range actions retain natural touch height")

func test_fresh_short_landscape_population_has_no_sideways_reading() -> void:
	host.sim.city.stamp_building(54,65,252)
	host.sim.city.stamp_building(65,66,253)
	root.size=Vector2i(667,375)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(Vector2i.ZERO,root.size))
	await HostFixture.settle(self, 10)
	var population := host.open_window("population") as PopulationWindow
	await HostFixture.settle(self, 10)
	var scroll: ScrollContainer=population._root.get_meta("window_chrome").body_scroll
	check(scroll.get_h_scroll_bar().max_value<=scroll.get_h_scroll_bar().page+1.0,"fresh landscape narrative fits")

func test_phone_row_and_table_labels_never_stack_letters() -> void:
	root.size=Vector2i(390,844)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,47,390,763))
	await HostFixture.settle(self, 10)
	var budget := host.open_window("budget") as BudgetWindow
	await HostFixture.settle(self, 10)
	var amount: Label
	for label: Label in budget._root.get_meta("window_chrome").body.find_children("*","Label",true,false):
		if label.text=="Amount": amount=label
	check(amount!=null,"bond amount caption is present")
	if amount!=null:
		check_eq(amount.get_line_count(),1,"Amount stays one word beside the bond stepper")
		check(amount.size.y<=40.0,"Amount keeps a single line's height")
	host.window_manager.close_all()
	var population := host.open_window("population") as PopulationWindow
	await HostFixture.settle(self, 10)
	var ages := 0
	for label: Label in population._body.find_children("*","Label",true,false):
		if label.get_parent() is GridContainer and label.text.contains("-") and not label.text.contains(" "):
			ages += 1
			check_eq(label.get_line_count(),1,"age band %s reads on one line" % label.text)
	check(ages>=10,"age table rows are present")
	var scroll: ScrollContainer=population._root.get_meta("window_chrome").body_scroll
	check(scroll.get_h_scroll_bar().max_value<=scroll.get_h_scroll_bar().page+1.0,"age table fits without sideways reading")

func test_notice_body_fits_its_content_and_keeps_the_prompt_field_visible() -> void:
	var notice: NoticeDialog = host.notice_dialog
	var text := ""
	for line in 4: text += "Line %d of a short notice.\n" % line
	for display: Dictionary in [{"size":Vector2i(1440,900),"mobile":false},{"size":Vector2i(390,844),"mobile":true}]:
		root.size=display.size
		if display.mobile: host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,47,390,763))
		else: host.display_layout.refresh_with_metrics(root.size,1)
		await HostFixture.settle(self, 10)
		notice.show_notice("Secret codes",text,[["Submit",&"submit"],["Never mind",&"cancel"]],true,"")
		await HostFixture.settle(self, 10)
		var chrome: Dictionary=notice.panel.get_meta("window_chrome")
		var scroll: ScrollContainer=chrome.body_scroll
		var bounds := host.display_layout.logical_rect().grow(.1)
		check(bounds.encloses(notice.panel.get_global_rect()),"notice stays inside the usable rect at %s" % [display.size])
		check(scroll.get_v_scroll_bar().max_value<=scroll.size.y+1.0,"a notice that fits shows all its text without scrolling at %s" % [display.size])
		check(scroll.get_global_rect().grow(.5).encloses(notice.line_edit.get_global_rect()),"prompt field is not clipped at %s" % [display.size])
		for button: Button in notice.choice_buttons:
			check(bounds.encloses(button.get_global_rect()),"choice %s stays reachable" % button.text)
		notice.dismiss(&"cancel")
		await HostFixture.settle(self, 2)
	# Content taller than the display scrolls inside the body; actions stay put.
	var long_text := ""
	for line in 80: long_text += "Paragraph %d of a very long notice.\n" % line
	notice.show_notice("Long",long_text)
	await HostFixture.settle(self, 10)
	var long_scroll: ScrollContainer=notice.panel.get_meta("window_chrome").body_scroll
	check(long_scroll.get_v_scroll_bar().max_value>long_scroll.size.y+1.0,"long notice scrolls inside its body")
	check(host.display_layout.logical_rect().grow(.1).encloses(notice.panel.get_global_rect()),"long notice stays inside the usable rect")
	for button: Button in notice.choice_buttons:
		check(host.display_layout.logical_rect().grow(.1).encloses(button.get_global_rect()),"long notice action stays reachable")
	notice.dismiss()

# Guards against: Help opened on the title and then in a city moves between UI
# layers; the move must not make its narrow table forget its cards, which
# left captions unfitted (one letter per line) and stale cards behind.
func test_help_moved_from_the_title_to_a_city_keeps_its_fitted_captions() -> void:
	root.size=Vector2i(375,667)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,20,375,647))
	await HostFixture.settle(self, 10)
	var was_in_game := host.in_game
	host.in_game = false
	var help := host.open_window("help")
	await HostFixture.settle(self, 10)
	check(help.get_parent()==host.modal_layer,"Help from the title sits on the title layer")
	var tables: Array = help.find_children("*","GridContainer",true,false).filter(func(n: Node) -> bool: return n is UIFactory.ResponsiveTable)
	check(not tables.is_empty(),"Help has a responsive table")
	var before: Array[int] = []
	for table: Node in tables: before.append(table.get_child_count())
	host.window_manager.close_all()
	host.in_game = true
	help = host.open_window("help")
	await HostFixture.settle(self, 10)
	check(help.get_parent()==host.ui_layer,"Help in a city moves to the city layer")
	root.size=Vector2i(390,844)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,47,390,763))
	await HostFixture.settle(self, 10)
	for i in tables.size():
		var table: Node = tables[i]
		check_eq(table.get_child_count(),before[i],"the move leaves no stale cards in the table")
		var cards: Array = table.get("_cards")
		check(not cards.is_empty(),"the narrow table still lays out its cards")
		for card: Node in cards:
			for row: Node in card.get_children():
				if not row is HBoxContainer or row.get_child_count()<2: continue
				var caption := row.get_child(0) as Label
				if caption==null or caption.text.is_empty(): continue
				check(caption.get_line_count()<=caption.text.split(" ").size(),"caption '%s' keeps whole words on a line" % caption.text)
	host.window_manager.close_all()
	host.in_game = was_in_game
