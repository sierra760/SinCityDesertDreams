# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost

func before_each() -> void:
	host = Fixture.make_host(self, "tourism-status-tests")
	host.sim.set_process(false)

func after_each() -> void:
	host.free()
	await process_frame

func _tourists() -> Label:
	return host.status_bar.get("tourists_label") as Label

func _check_counts(bounds: Rect2) -> void:
	var pop := host.status_bar.population_label
	var tourists := _tourists()
	check(tourists != null, "tourist counter exists beside residents")
	if tourists == null: return
	for label: Label in [pop, tourists]:
		check(label.is_visible_in_tree(), "both current counts are visible without Details")
		var rect := label.get_global_rect()
		check(bounds.grow(.1).encloses(rect), "counter fits usable display: " + label.text)
		check(host.status_bar.get_global_rect().grow(.1).encloses(rect), "counter fits status face")
		var ink := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size"))
		check_ge(rect.size.x + .1, ink.x, "counter has its full text width")
		check_ge(rect.size.y + .1, ink.y, "counter has its full text height")
	check(absf(pop.global_position.y-tourists.global_position.y)<1, "counts share the same visible row")
	check(pop.get_global_rect().end.x <= tourists.global_position.x, "resident and tourist text do not overlap")
	check(tourists.global_position.x-pop.get_global_rect().end.x <= 20, "counters stay adjacent")
	if host.shell.phone_layout:
		check(not host.status_bar._phone_row.get_global_rect().intersects(pop.get_global_rect()), "funds/date/tool have a separate row")
		check_ge(host.status_bar._details_button.size.x,44)
		check_ge(host.status_bar._details_button.size.y,44)

func test_population_and_tourists_are_adjacent_without_details() -> void:
	for profile: Array in [[Vector2i(320,568),Rect2i(0,20,320,548)], [Vector2i(390,844),Rect2i(0,47,390,763)], [Vector2i(844,390),Rect2i(47,0,750,369)], [Vector2i(768,1024),Rect2i(0,24,768,980)], [Vector2i(1024,768),Rect2i(0,24,1024,724)], [Vector2i(1440,900),Rect2i(0,0,1440,900)]]:
		root.size = profile[0]
		host.display_layout.refresh_with_mobile_metrics(root.size,1,profile[1])
		host.status_bar.set_message("")
		for amount in [0, 1234567, 2147483647]:
			for speed in [GameClock.Speed.PAUSED, GameClock.Speed.SLOW]:
				host.sim.stats.population = amount
				host.sim.stats.tourists = amount
				host.status_bar.refresh(host.sim)
				host.sim.set_speed(speed)
				await Fixture.settle(self,8)
				_check_counts(host.display_layout.logical_rect())
				if _tourists()!=null:
					check(_tourists().tooltip_text.contains(UIFactory.commafy(amount)), "tourist tooltip retains exact count")
					check(host.status_bar.population_label.tooltip_text.contains(UIFactory.commafy(amount)), "resident tooltip retains exact count")
					host.status_bar.set_population(7654321)
					host.status_bar.call("set_tourists",2345678)
					await Fixture.settle(self,6)
					_check_counts(host.display_layout.logical_rect())
					check(_tourists().tooltip_text.contains("2,345,678"), "updates refresh closed Details face")

func test_editing_founding_and_phone_tablet_switch_clear_old_counts() -> void:
	for display in [Vector2i(390,844),Vector2i(1024,768),Vector2i(320,568)]:
		root.size = display
		host.display_layout.refresh_with_mobile_metrics(display,1,Rect2i(Vector2i.ZERO,display))
		host.status_bar.set_population(1234567)
		if _tourists()!=null: host.status_bar.call("set_tourists",1234567)
		host.start_new_city({"seed":7,"name":"New desert","speed":GameClock.Speed.SLOW},flat_city())
		await Fixture.settle(self,8)
		if _tourists()!=null: check(not _tourists().is_visible_in_tree(), "terrain editing has no tourism economy")
		check(host.found_city(), "founding succeeds")
		host.sim.set_speed(GameClock.Speed.PAUSED)
		await Fixture.settle(self,8)
		_check_counts(host.display_layout.logical_rect())
		if _tourists()!=null: check_eq(_tourists().text,"Tourists: 0", "founding immediately clears previous visitors")

func test_month_demolition_restore_and_replacement_refresh_signal_counts() -> void:
	root.size = Vector2i(390,844)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,47,390,763))
	var city := flat_city()
	var anchor := Vector2i(10,10)
	TourismFixture.venue(city,&"arcology_boddy",anchor)
	city.stamp_building(9,10,Buildings.ROAD_FIRST)
	host.begin_city(city,{},7,null)
	TourismFixture.set_served(city,anchor,true,true)
	host.sim.clock.day = 16
	host.sim.advance_day()
	await Fixture.settle(self,8)
	check_gt(host.sim.stats.tourists,0,"monthly attendance exists")
	if _tourists()!=null: check_eq(_tourists().text,"Tourists: "+UIFactory.commafy(host.sim.stats.tourists),"monthly publication updates face")
	var attended := host.sim.stats.tourists
	var snapshot := host.sim.snapshot()
	var clone := city.duplicate_city()
	clone.restored_layers["flags"] = true
	var removed := host.builder.apply(Tools.Kind.BULLDOZE,anchor)
	check(removed.get("ok",false),"actual Builder demolishes venue")
	await Fixture.settle(self,8)
	if _tourists()!=null: check_eq(_tourists().text,"Tourists: 0","demolition signal clears face")
	host.begin_city(clone,snapshot,7,CityStats.new())
	await Fixture.settle(self,8)
	check_eq(host.sim.stats.tourists,attended,"restoration preserves current attendance before publication")
	if _tourists()!=null: check_eq(_tourists().text,"Tourists: "+UIFactory.commafy(host.sim.stats.tourists),"restore reads normalized counts")
	host.begin_city(flat_city(),{},8,null)
	await Fixture.settle(self,8)
	if _tourists()!=null: check_eq(_tourists().text,"Tourists: 0","city replacement cannot retain visitors")
	_check_counts(host.display_layout.logical_rect())

func test_summary_keeps_residents_separate_from_tourists() -> void:
	host.status_bar.set_population(1234567)
	check(host.status_bar.has_method("set_tourists"), "bar accepts tourist scalar")
	if not host.status_bar.has_method("set_tourists"): return
	host.status_bar.call("set_tourists",2345678)
	check(host.status_bar.summary().contains("Pop: 1,234,567"))
	check(host.status_bar.summary().contains("Tourists: 2,345,678"))

func test_live_scalar_updates_do_not_wait_for_full_refresh() -> void:
	root.size = Vector2i(320,568)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,20,320,548))
	host.status_bar.set_details_open(false)
	host.sim.stats.population = 1234567
	host.sim.stats.tourists = 2345678
	host.sim._emit_scalars()
	await Fixture.settle(self,8)
	check(_tourists()!=null,"live tourist scalar has a visible consumer")
	if _tourists()==null: return
	check(host.status_bar.population_label.tooltip_text.contains("1,234,567"),"population signal reaches compact face")
	check(_tourists().tooltip_text.contains("2,345,678"),"tourist signal reaches compact face without daily refresh")
	_check_counts(host.display_layout.logical_rect())
