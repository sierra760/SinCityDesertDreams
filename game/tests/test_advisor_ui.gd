# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost

func before_each() -> void:
	host = Fixture.make_host(self,"advisor-ui")

func after_each() -> void:
	host.free()
	await process_frame

func text_of(window: AdvisorsWindow) -> String:
	return window.advice_text()

func body_text(window: Control) -> String:
	var lines := PackedStringArray()
	for label: Label in (window.get("_body") as Control).find_children("*","Label",true,false): lines.append(label.text)
	return " ".join(lines)

func test_empty_states_distinguish_new_city_and_early_reports() -> void:
	var window := host.open_window("advisors") as AdvisorsWindow
	await Fixture.settle(self,6)
	check(text_of(window).contains("No residents yet"))
	host.sim.stats.population = 10
	window.refresh()
	check(text_of(window).contains("Monthly reports"))
	host.sim.stats.history[&"population"] = PackedInt32Array([10])
	window.refresh()
	check(text_of(window).contains("No pressing problems detected"))
	window.bind(null)
	check(text_of(window).contains("Load a city"))

func test_reports_menu_opens_advisors_separately_from_newspaper() -> void:
	var entry: Dictionary = host.menu_bar._entries.get("window|advisors", {})
	check(not entry.is_empty(), "Reports menu lists Advisors")
	var menu := entry.get("menu") as PopupMenu
	check_eq(menu.get_item_text(menu.get_item_index(int(entry["id"]))), "Advisors")
	host.menu_bar._on_id_pressed(int(entry["id"]), menu)
	await Fixture.settle(self,6)
	check(host.window_manager.is_open("advisors"), "menu item opens the Advisors window")
	check(not host.window_manager.is_open("newspaper"), "newspaper stays closed")
	check(host.window_manager.window("advisors") is AdvisorsWindow)
	host.window_manager.close_all()

func test_populated_advice_fits_phone_landscape_and_desktop_and_remains_current_in_archive() -> void:
	var stats := host.sim.stats
	stats.population = 5000
	stats.cohorts[0] = 1200
	stats.cohorts[4] = 1000
	stats.jobs = 400
	stats.unemployment = 60
	stats.power_capacity = 1000
	stats.power_demand = 100
	stats.unpowered_buildings = 1
	stats.average_crime = 120
	stats.average_pollution = 110
	stats.average_traffic = 110
	stats.newspaper_archive = [
		{"date":"January 1900","extra":false,"stories":[{"headline":"An old issue","body":"The archive stays historical."}]},
		{"date":"February 1900","extra":false,"stories":[{"headline":"A later issue","body":"Reports from last month."}]},
	]
	host.sim.city.stamp_building(40,40,Buildings.RES_1X1_FIRST)
	for size in [Vector2i(320,568),Vector2i(844,390),Vector2i(1280,800)]:
		root.min_size = Vector2i.ONE
		root.size = size
		host.display_layout.refresh_with_mobile_metrics(size,1,Rect2i(Vector2i.ZERO,size),0,"iOS" if size.x<1000 else "macOS")
		await Fixture.settle(self,8)
		var window := host.open_window("advisors") as AdvisorsWindow
		await Fixture.settle(self,10)
		var chrome: Dictionary = window._root.get_meta("window_chrome")
		var scroll := chrome.body_scroll as ScrollContainer
		check(host.display_layout.logical_rect().grow(1).encloses(window._root.get_global_rect()), "panel fits " + str(size))
		check(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page+1, "no horizontal pan " + str(size))
		check(text_of(window).contains("network connections"))
		check(body_text(window).contains("Current city"), "readings identified as current")
		var paper := host.open_window("newspaper") as NewspaperWindow
		await Fixture.settle(self,6)
		paper.show_issue(0)
		check_eq(paper.date_text(),"January 1900")
		check(not body_text(paper).contains("network connections"), "newspaper shows only its stories")
		check(not body_text(paper).contains("Advisors"), "no advisor section in the newspaper")
		check(text_of(window).contains("network connections"), "browsing an old issue keeps current city advice")
		stats.unpowered_buildings = 0
		window.refresh()
		check(not text_of(window).contains("network connections"), "resolved need clears")
		stats.unpowered_buildings = 1
		window.refresh()
		paper.close()
		host.window_manager.open("advisors")
		await Fixture.settle(self,6)
		var directory := OS.get_environment("ADVISOR_CAPTURE_DIR")
		if not directory.is_empty():
			for department in ["utilities","finance","transport","safety","community","planning"]:
				window.select_department(department)
				scroll.scroll_vertical = 0
				await Fixture.settle(self,5)
				RenderingServer.force_draw(false)
				RenderingServer.force_sync()
				await Fixture.settle(self,3)
				RenderingServer.force_draw(false)
				check_eq(root.get_texture().get_image().save_png(directory.path_join("advisors-%dx%d-%s.png" % [size.x,size.y,department])),OK)
			window.select_department("utilities")

			window.close()
			paper = host.open_window("newspaper") as NewspaperWindow
			paper.show_issue(paper.issue_count()-1)
			await Fixture.settle(self,6)
			RenderingServer.force_draw(false)
			RenderingServer.force_sync()
			await Fixture.settle(self,3)
			RenderingServer.force_draw(false)
			check_eq(root.get_texture().get_image().save_png(directory.path_join("newspaper-%dx%d.png" % [size.x,size.y])),OK)

		host.window_manager.close_all()

# Missing portraits or replacing the diagnosis with a joke must fail through the real window.
func test_personalities_keep_current_evidence_and_show_readable_portraits() -> void:
	host.sim.stats.power_capacity = 100
	host.sim.stats.power_demand = 101
	var paper := host.sim.get_system(&"newspaper")
	var before: Array = paper.advice().duplicate(true)
	var rng_before := host.sim._ctx.rng.state()
	var window := host.open_window("advisors") as AdvisorsWindow
	await Fixture.settle(self,8)
	var portraits := window._advice_box.find_children("AdvisorPortrait", "TextureRect", true, false)
	check_eq(portraits.size(), 1, "one portrait for the selected department")
	check_gt(portraits.size(), 0)
	check(text_of(window).contains("Ray Navarro"), "utility advisor identifies himself")
	for entry: Dictionary in before:
		check(text_of(window).contains(String(entry.text)), "complete factual diagnosis remains visible")
	for portrait: TextureRect in portraits:
		check(portrait.texture != null)
		check_ge(portrait.size.x, 64.0)
		check_ge(portrait.size.y, 64.0)
	check_eq(paper.advice(), before)
	check_eq(host.sim._ctx.rng.state(), rng_before)

# Switching departments must expose their original findings, never duplicate advisors.
func test_six_department_navigation_retains_focus_and_selection_on_refresh() -> void:
	root.size = Vector2i(1280,800)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(Vector2i.ZERO,root.size),0,"macOS")
	var window := host.open_window("advisors") as AdvisorsWindow
	await Fixture.settle(self,8)
	check(window.has_method("select_department"), "department navigation exists")
	if not window.has_method("select_department"): return
	var buttons: Dictionary = window.get("_buttons")
	check_eq(buttons.size(), 6)
	var button := buttons["community"] as Button
	button.pressed.emit()
	button.grab_focus()
	await Fixture.settle(self,4)
	check(text_of(window).contains("Elaine Park"))
	window.refresh()
	await Fixture.settle(self,4)
	check(text_of(window).contains("Elaine Park"), "refresh retains the chosen advisor")
	check_eq(root.gui_get_focus_owner(),button,"monthly refresh keeps navigation focus")
	window.select_department("unknown_department")
	check(text_of(window).contains("Elaine Park"), "invalid selection preserves the briefing")

func test_narrow_picker_switches_advisors_and_mood_portrait_recovers_with_service() -> void:
	root.min_size = Vector2i.ONE
	root.size = Vector2i(320,568)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(Vector2i.ZERO,root.size),0,"iOS")
	host.sim.stats.power_capacity = 100
	host.sim.stats.power_demand = 101
	var window := host.open_window("advisors") as AdvisorsWindow
	await Fixture.settle(self,10)
	check(window.has_method("select_department"), "department navigation exists")
	if not window.has_method("select_department"): return
	var picker := window.get("_picker") as OptionButton
	check(picker.is_visible_in_tree())
	check_eq(picker.item_count,6)
	check(not (window.get("_roster") as Control).is_visible_in_tree())
	window.select_department("utilities")
	await Fixture.settle(self,4)
	var portrait := window._advice_box.find_child("AdvisorPortrait",true,false) as TextureRect
	check(portrait.texture.resource_path.ends_with("utilities-critical.png"))
	host.sim.stats.power_capacity = 150
	window.refresh()
	await Fixture.settle(self,4)
	portrait = window._advice_box.find_child("AdvisorPortrait",true,false) as TextureRect
	check(portrait.texture.resource_path.ends_with("utilities-pleased.png"), "resolved supply immediately changes the face")
	for i in picker.item_count:
		if picker.get_item_metadata(i) == "finance":
			picker.item_selected.emit(i)
			break
	await Fixture.settle(self,4)
	check(text_of(window).contains("Dana Mercer"), "compact department picker is wired")

func test_layout_changes_move_navigation_focus_to_the_visible_control() -> void:
	root.min_size = Vector2i.ONE
	root.size = Vector2i(1280,800)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(Vector2i.ZERO,root.size),0,"macOS")
	var window := host.open_window("advisors") as AdvisorsWindow
	await Fixture.settle(self,10)
	window.select_department("transport")
	var buttons: Dictionary = window.get("_buttons")
	(buttons["transport"] as Button).grab_focus()
	root.size = Vector2i(320,568)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(Vector2i.ZERO,root.size),0,"iOS")
	await Fixture.settle(self,12)
	check_eq(root.gui_get_focus_owner(),window.get("_picker"),"narrow navigation stays focused")
	check(text_of(window).contains("Marcus Reed"))
	root.size = Vector2i(1280,800)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(Vector2i.ZERO,root.size),0,"macOS")
	await Fixture.settle(self,12)
	check_eq(root.gui_get_focus_owner(),buttons["transport"],"wide navigation restores selected advisor focus")
