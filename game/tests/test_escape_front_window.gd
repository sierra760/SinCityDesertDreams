# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Escape closes whatever is in front, one thing at a time, and never a
## report hidden behind Help or Settings.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const PREFERENCES := "user://test-escape-front-window.cfg"
## Reports that close themselves on Escape when shown without a host.
const REPORTS: Array[String] = ["budget", "population", "newspaper", "graphs", "industries", "neighbors",
	"ordinances", "tourism", "advisors", "city_maps", "vegetation"]
## Windows without an Escape handler of their own.
const COVERS: Array[String] = ["help", "options", "privacy", "license"]

var host: GameHost


func before_each() -> void:
	root.size = Vector2i(1280, 800)
	host = MAIN.instantiate()
	host.preferences_path = PREFERENCES
	root.add_child(host)
	host.begin_city(flat_city(20000), {}, 7, CityStats.new())
	host.sim.set_speed(GameClock.Speed.SLOW)
	await process_frame
	await process_frame


func after_each() -> void:
	host.free()
	if FileAccess.file_exists(PREFERENCES): DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFERENCES))
	await physics_frame


func _escape() -> void:
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.physical_keycode = KEY_ESCAPE
		key.pressed = pressed
		root.push_input(key)


func _begin_january_review() -> void:
	host.sim.stats.auto_budget = false
	host.sim.clock.day = GameClock.DAYS_PER_YEAR - 1
	host.sim.city.day = host.sim.clock.day
	host.sim.advance_day()
	await process_frame
	check(host.sim.budget_review_pending, "the January review is open")
	check(host.window_manager.is_open("budget"))


func test_escape_closes_only_the_window_in_front_of_each_report() -> void:
	for report: String in REPORTS:
		for cover: String in COVERS:
			check(host.window_manager.open(report) != null, report)
			await process_frame
			check(host.window_manager.open(cover) != null, cover)
			await process_frame
			_escape()
			await process_frame
			check(not host.window_manager.is_open(cover), "%s closes in front of %s" % [cover, report])
			check(host.window_manager.is_open(report), "%s stays open behind %s" % [report, cover])
			_escape()
			await process_frame
			check(not host.window_manager.is_open(report), "the next Escape closes %s" % report)
			host.window_manager.close_all()
			await process_frame


func test_escape_closes_the_front_report_first() -> void:
	host.window_manager.open("graphs")
	await process_frame
	host.window_manager.open("budget")
	await process_frame
	_escape()
	await process_frame
	check(not host.window_manager.is_open("budget"), "the front report closes")
	check(host.window_manager.is_open("graphs"), "the one behind stays")
	# Bringing the older report forward makes it the next to close.
	host.window_manager.open("budget")
	await process_frame
	host.window_manager.open("graphs")
	await process_frame
	_escape()
	await process_frame
	check(not host.window_manager.is_open("graphs"))
	check(host.window_manager.is_open("budget"))


func test_escape_in_help_never_settles_the_january_review() -> void:
	await _begin_january_review()
	for cover: String in COVERS:
		host.window_manager.open(cover)
		await process_frame
		await process_frame
		_escape()
		await process_frame
		check(not host.window_manager.is_open(cover), "%s closes" % cover)
		check(host.sim.budget_review_pending, "the year is not settled by closing %s" % cover)
		check(host.window_manager.is_open("budget"), "the review stays open behind %s" % cover)
		check_eq(host.modal_depth, 1, "the review still holds the city")
		check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	_escape()
	await process_frame
	check(not host.sim.budget_review_pending, "Escape on the review itself finishes it")
	check_eq(host.modal_depth, 0)
	check_eq(host.sim.speed, GameClock.Speed.SLOW, "and the city resumes")


func test_a_notice_takes_escape_before_the_report_under_it() -> void:
	host.window_manager.open("budget")
	await process_frame
	host.notices.show("Notice", "Read me first.")
	await process_frame
	_escape()
	await process_frame
	check(not host.notice_dialog.is_open(), "the notice closes")
	check(host.window_manager.is_open("budget"), "the report under it stays")


func test_a_report_shown_on_its_own_still_closes_on_escape() -> void:
	var window := BudgetWindow.new()
	root.add_child(window)
	window.bind(host.sim)
	window.open()
	await process_frame
	check(window.visible)
	_escape()
	await process_frame
	check(not window.visible, "a stand-alone report answers Escape itself")
	window.free()
