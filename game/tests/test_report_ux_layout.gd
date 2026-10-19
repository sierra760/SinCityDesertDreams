# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"

const Fixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost

func before_each() -> void:
	host = Fixture.make_host(self, "report-ux-layout")

func after_each() -> void:
	host.free()
	await process_frame

func profile(size: Vector2i) -> void:
	root.min_size = Vector2i(1,1) # Clear desktop backing-scale minimum for injected phone renders.
	root.size = size
	var safe := Rect2i(Vector2i.ZERO, size)
	if size == Vector2i(390,844): safe = Rect2i(0,47,390,763)
	if size == Vector2i(844,390): safe = Rect2i(47,0,750,369)
	host.display_layout.refresh_with_mobile_metrics(size, 1, safe, 0, "iOS" if size.x < 1200 else "macOS")
	await Fixture.settle(self, 10)

func fits(w: Control, label: String) -> void:
	var panel := w.get("_root") as Control
	var chrome: Dictionary = panel.get_meta("window_chrome")
	var scroll := chrome.body_scroll as ScrollContainer
	check(host.display_layout.logical_rect().grow(0.5).encloses(panel.get_global_rect()), label + " panel fits safe bounds")
	check(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page + 1, label + " needs no horizontal pan")
	check_ge((chrome.close_button as Control).size.y, 44)
	for button: BaseButton in (chrome.actions as Node).find_children("*", "BaseButton", true, false):
		if button.is_visible_in_tree():
			check(host.display_layout.logical_rect().grow(0.5).encloses(button.get_global_rect()), label + " footer reachable")

func capture(name: String) -> void:
	var directory := OS.get_environment("REPORT_CAPTURE_DIR")
	if directory.is_empty(): return
	await RenderingServer.frame_post_draw
	check_eq(root.get_texture().get_image().save_png(directory.path_join(name + ".png")), OK)

func test_overlay_buttons_fit_small_phones_without_sideways_panning() -> void:
	for size in [Vector2i(320,568), Vector2i(390,844)]:
		await profile(size)
		var maps := host.open_window("city_maps") as CityMapsWindow
		await Fixture.settle(self, 10)
		fits(maps, "map overlays " + str(size))
		var scroll := UIFactory.report_scroll(maps._buttons[&"power"])
		for button: Button in maps._buttons.values():
			scroll.ensure_control_visible(button)
			await Fixture.settle(self, 2)
			check(scroll.get_global_rect().grow(0.5).encloses(button.get_global_rect()), "the complete overlay target can be revealed")
		maps.select_overlay(&"power")
		check_eq(maps.selected_overlay(), &"power")
		check(not maps.legend_text().is_empty(), "the useful map legend remains")
		maps.close()

func test_all_report_titles_stay_clear_of_the_main_menu() -> void:
	for size in [Vector2i(1280,800), Vector2i(390,844), Vector2i(320,568), Vector2i(844,390), Vector2i(768,1024), Vector2i(1024,768)]:
		await profile(size)
		for name: String in GameMenuBar.WINDOW_NAMES:
			var w := host.open_window(name)
			await Fixture.settle(self, 8)
			var panel := w.get("_root") as Control
			var chrome: Dictionary = panel.get_meta("window_chrome")
			check_ge((chrome.title_bar as Control).get_global_rect().position.y, host.menu_bar.get_global_rect().end.y, name + " title clears the menu: " + str(size))
			fits(w, name + " title bounds " + str(size))
			host.window_manager.close_all()

func test_budget_tabs_and_ordinance_categories_fit_all_profiles() -> void:
	TourismFixture.venue(host.sim.city, &"arcology_boddy", Vector2i(10, 10))
	host.sim.tourism().reconcile_now()
	for size in [Vector2i(1280,800), Vector2i(390,844), Vector2i(320,568), Vector2i(844,390), Vector2i(768,1024), Vector2i(1024,768)]:
		await profile(size)
		var budget := host.open_window("budget") as BudgetWindow
		host.sim.city.name = "A city with a very long descriptive name"
		host.sim.city.funds = 1234567890
		host.sim.stats.ledger[&"taxes_occupancy"] = 987654321
		for page in ["Summary", "Taxes", "Funding", "Debt"]:
			budget.select_page(page)
			budget.refresh()
			await Fixture.settle(self, 8)
			fits(budget, page + str(size))
			if page == "Summary":
				var scroll := UIFactory.report_scroll(budget._summary_values[0])
				for amount: Label in budget._summary_values:
					check(scroll.get_global_rect().grow(0.5).encloses(amount.get_global_rect()), "all three headline figures are visible immediately: " + str(size))
			if size.x >= 1200: check(budget._root.size.y <= 520, "temporary table minima never inflate the preferred window")
			var tabs := budget._pages.tabs
			check_eq(tabs.tab_count, 4)
			for i in 4:
				check(tabs.get_tab_rect(i).end.x <= tabs.size.x + 0.5, "all four tabs fit without arrows")
			await capture("%dx%d-budget-%s" % [size.x, size.y, page])
		budget.close()
		var ordinances := host.open_window("ordinances") as OrdinancesWindow
		host.sim.stats.population = 50000
		ordinances.set_ordinance(&"sales_tax", true)
		ordinances.set_ordinance(&"free_clinics", true)
		for group in ["Finance", "Safety", "City"]:
			ordinances.select_group(group)
			await Fixture.settle(self, 8)
			fits(ordinances, group + str(size))
			await capture("%dx%d-ordinances-%s" % [size.x, size.y, group])
		ordinances.close()
		var tourism := host.open_window("tourism") as TourismWindow
		await Fixture.settle(self, 8)
		fits(tourism, "Tourism" + str(size))
		for metric in ["Guests", "Day", "Occupancy"]:
			var caption := tourism.find_child("TourismMetric" + metric, true, false) as Label
			for word: String in caption.text.split(" "):
				check(caption.size.x >= caption.get_theme_font("font").get_string_size(word,HORIZONTAL_ALIGNMENT_LEFT,-1,caption.get_theme_font_size("font_size")).x, "tourism metric words remain readable" + str(size))
		for pair: Array in tourism._tourism_values.values():
			for value: Label in pair:
				value.text = "987,654,321"
		await Fixture.settle(self, 8)
		fits(tourism, "Tourism large attendance" + str(size))
		for pair: Array in tourism._tourism_values.values():
			for value: Label in pair:
				check(value.size.x >= value.get_theme_font("font").get_string_size(value.text,HORIZONTAL_ALIGNMENT_LEFT,-1,value.get_theme_font_size("font_size")).x, "attendance numbers fit without broken digits")
		await capture("%dx%d-tourism-large" % [size.x, size.y])
		tourism.refresh()
		await Fixture.settle(self, 8)
		await capture("%dx%d-tourism" % [size.x, size.y])
		(tourism._buttons["Income"] as Button).button_pressed = true
		await Fixture.settle(self, 6)
		fits(tourism, "Tourism income" + str(size))
		await capture("%dx%d-tourism-income" % [size.x, size.y])
		(tourism._buttons["Income"] as Button).button_pressed = false
		host.window_manager.close_all()

func test_links_reuse_windows_and_hold_the_annual_review() -> void:
	await profile(Vector2i(1280,800))
	host.sim.stats.auto_budget = false
	host.sim.advance_days(GameClock.DAYS_PER_YEAR)
	check(host.sim.budget_review_pending)
	var budget := host.window_manager.window("budget") as BudgetWindow
	check_eq(budget.selected_page(), "Summary")
	budget.select_page("Taxes")
	var before := host.sim.snapshot().duplicate(true)
	for i in 3:
		budget.report_requested.emit("tourism", "")
		var tourism := host.window_manager.window("tourism") as TourismWindow
		check_eq(host.window_manager.front(), tourism)
		tourism.report_requested.emit("budget", "Taxes")
		check_eq(host.window_manager.front(), budget)
		check_eq(budget.selected_page(), "Taxes")
		check_eq(host.window_manager.open_windows.size(), 2)
		check(host.sim.budget_review_pending)
	check_eq(host.sim.snapshot(), before, "links cannot settle or advance the annual review")
	(host.window_manager.window("tourism") as TourismWindow).close()
	check(host.sim.budget_review_pending)
	budget.close()
	check(not host.sim.budget_review_pending)

func test_query_is_short_and_preserves_actions_in_portrait_and_landscape() -> void:
	for size in [Vector2i(1280,800), Vector2i(390,844), Vector2i(844,390), Vector2i(768,1024)]:
		await profile(size)
		for key in ["ground", "home", "resort", "plant", "farm", "station"]:
			var at: Vector2i = {"ground":Vector2i(10,10), "home":Vector2i(20,20), "resort":Vector2i(40,40), "plant":Vector2i(60,40), "farm":Vector2i(20,60), "station":Vector2i(60,60)}[key]
			if key == "home": host.sim.city.stamp_building(at.x,at.y,Buildings.RES_1X1_FIRST,Zones.RES_LOW)
			if key == "resort": host.sim.city.stamp_building(at.x,at.y,Buildings.id_of(&"arcology_boddy"))
			if key == "plant": host.sim.city.stamp_building(at.x,at.y,Buildings.COAL_PLANT)
			if key == "station": host.sim.city.stamp_building(at.x,at.y,Buildings.RAIL_STATION)
			if key == "farm":
				var f := preload("res://tests/helpers/agricultural_parcel_fixture.gd")
				var members := f.mask([[20,60],[21,60],[20,61]])
				f.zone(host.sim.city,members)
				check_eq(host.sim.city.agricultural_parcels.put(host.sim.city,f.record(1,members,&"grain",&"prepared")),OK)
			host.sim.tourism().reconcile_now()
			host.open_query(at)
			await Fixture.settle(self, 10)
			var panel := host.query_panel
			check(panel.lines().size() <= 10, "compact query for " + key)
			for button in [panel.close_button, panel.demolish_button, panel.rename_button]:
				check_ge(button.size.y, 44)
				check(host.display_layout.logical_rect().grow(0.5).encloses(button.get_global_rect()), "query actions fit")
			check(panel.get_global_rect().end.y <= host.status_bar.get_global_rect().position.y + 0.5)
			await capture("%dx%d-query-%s" % [size.x, size.y, key])
			panel.set_details(true)
			await Fixture.settle(self, 6)
			await capture("%dx%d-query-%s-details" % [size.x, size.y, key])
			panel.close()

func test_budget_restores_page_scroll_and_moves_focus_out_of_hidden_controls() -> void:
	await profile(Vector2i(390,844))
	var budget := host.open_window("budget") as BudgetWindow
	budget.select_page("Taxes")
	await Fixture.settle(self, 8)
	var scroll := UIFactory.report_scroll(budget._tax_spinners[&"gaming"])
	scroll.scroll_vertical = 200
	await Fixture.settle(self, 4)
	budget._tax_spinners[&"gaming"].get_line_edit().grab_focus()
	await Fixture.settle(self, 4)
	var offset := scroll.scroll_vertical
	budget.select_page("Debt")
	await Fixture.settle(self, 4)
	check_eq(root.gui_get_focus_owner(), budget._pages.tabs)
	budget.select_page("Taxes")
	await Fixture.settle(self, 8)
	check_eq(scroll.scroll_vertical, offset, "each page retains its reading position")

func test_unenacting_a_filtered_policy_keeps_a_visible_keyboard_target() -> void:
	await profile(Vector2i(390,844))
	var ordinances := host.open_window("ordinances") as OrdinancesWindow
	ordinances.set_ordinance(&"sales_tax", true)
	ordinances.set_enacted_only(true)
	var box := ordinances._rows[&"sales_tax"].box as CheckBox
	box.grab_focus()
	box.button_pressed = false
	await Fixture.settle(self, 4)
	check_eq(root.gui_get_focus_owner(), ordinances._enacted_only)
	check(ordinances._enacted_only.is_visible_in_tree())
	var clear_filter := ordinances._body.get_node("ClearPolicyFilter") as Button
	check(clear_filter.is_visible_in_tree())
	clear_filter.grab_focus()
	clear_filter.pressed.emit()
	await Fixture.settle(self, 4)
	check_eq(root.gui_get_focus_owner(), ordinances._enacted_only, "clearing an empty filter also keeps focus visible")

func test_expanded_financial_and_tourism_details_remain_fully_reachable() -> void:
	for size in [Vector2i(1280,800), Vector2i(320,568)]:
		await profile(size)
		var budget := host.open_window("budget") as BudgetWindow
		budget.select_page("Summary")
		(budget.find_child("AccountBreakdown",true,false) as Button).button_pressed = true
		host.sim.stats.ledger[&"taxes_occupancy"] = 987654321
		host.sim.stats.last_year_ledger[&"taxes_occupancy"] = 123456789
		budget.refresh()
		var scroll := UIFactory.report_scroll(budget._ledger_subtotals[true])
		for period in 3:
			budget._ledger_period.item_selected.emit(period)
			await Fixture.settle(self, 8)
			scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
			await Fixture.settle(self, 4)
			var last := budget._ledger_subtotals[true] as Label
			check(last.get_global_rect().end.y <= scroll.get_global_rect().end.y + 0.5, "ledger's final total can be reached")
			fits(budget, "Expanded ledger" + str(size))
			await capture("%dx%d-ledger-period-%d" % [size.x,size.y,period])
		budget.select_page("Funding")
		budget.select_funding(1)
		await Fixture.settle(self, 8)
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await Fixture.settle(self, 4)
		check((budget._funding_sliders[&"tunnels"] as Control).get_global_rect().end.y <= scroll.get_global_rect().end.y + 0.5)
		budget.close()
		var tourism := host.open_window("tourism") as TourismWindow
		(tourism._buttons["Income"] as Button).button_pressed = true
		await Fixture.settle(self, 8)
		scroll = UIFactory.report_scroll(tourism._tourism_accrued)
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await Fixture.settle(self, 4)
		check(tourism._tourism_accrued.get_global_rect().end.y <= scroll.get_global_rect().end.y + 0.5, "expanded income details can be reached")
		host.window_manager.close_all()
