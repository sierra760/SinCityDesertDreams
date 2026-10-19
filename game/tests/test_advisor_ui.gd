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

func text_of(window: NewspaperWindow) -> String:
	var lines := PackedStringArray()
	for node in window._advice_box.get_children():
		if node is Label: lines.append(node.text)
	return " ".join(lines)

func test_empty_states_distinguish_new_city_and_early_reports() -> void:
	var window := host.open_window("newspaper") as NewspaperWindow
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
		var window := host.open_window("newspaper") as NewspaperWindow
		await Fixture.settle(self,10)
		var chrome: Dictionary = window._root.get_meta("window_chrome")
		var scroll := chrome.body_scroll as ScrollContainer
		check(host.display_layout.logical_rect().grow(1).encloses(window._root.get_global_rect()), "panel fits " + str(size))
		check(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page+1, "no horizontal pan " + str(size))
		check(text_of(window).contains("network connections"))
		window.show_issue(0)
		check_eq(window.date_text(),"January 1900")
		check(text_of(window).contains("network connections"), "old issue keeps current city advice")
		stats.unpowered_buildings = 0
		window.refresh()
		check(not text_of(window).contains("network connections"), "resolved need clears in historical view")
		stats.unpowered_buildings = 1
		window.refresh()
		var directory := OS.get_environment("ADVISOR_CAPTURE_DIR")
		if not directory.is_empty():
			for position in ["top", "advice", "last"]:
				if position == "top": scroll.scroll_vertical = 0
				elif position == "advice": scroll.ensure_control_visible(window._advice_box.get_child(0))
				else: scroll.ensure_control_visible(window._advice_box.get_child(window._advice_box.get_child_count()-1))
				await Fixture.settle(self,4)
				RenderingServer.force_draw(false)
				RenderingServer.force_sync()
				await Fixture.settle(self,3)
				RenderingServer.force_draw(false)
				var image := root.get_texture().get_image()
				check_eq(image.save_png(directory.path_join("advisors-%dx%d-%s.png" % [size.x,size.y,position])),OK)

		host.window_manager.close_all()
