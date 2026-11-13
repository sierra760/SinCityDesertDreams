# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A city opened after a recall sent the mayor back to the title keeps time.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const COMSTOCK := &"arcology_comstock"
const PREFERENCES := "user://test-recall-title-clock.cfg"
const LATER_NAME := "recall-title-later"

var host: GameHost


func before_each() -> void:
	host = MAIN.instantiate()
	host.preferences_path = PREFERENCES
	root.add_child(host)


func after_each() -> void:
	host.free()
	for path in [PREFERENCES, CityFileFlow.save_path_for(LATER_NAME), CityFileFlow.autosave_path()]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await physics_frame


func _lose_recall_and_return_to_title() -> void:
	host.begin_city(flat_city(20000), {}, 7, CityStats.new())
	host.sim.city.name = "Recalled And Never Saved"
	host.sim.set_speed(GameClock.Speed.FAST)
	host.sim.casino_begin_visit(COMSTOCK)
	check(host.sim.casino_commit(COMSTOCK, &"blackjack", 11000))
	host.sim.casino_settle(COMSTOCK, &"blackjack", 11000, 0)
	host.sim.casino_end_visit()
	host.notices.clear_pending()
	host.notice_dialog.dismiss()
	host.sim.clock.day = 150
	host.sim.city.day = 150
	host.sim.stats.approval = 0
	var saved := host.sim.casino().recall.save()
	saved.rng_state = str(SimRng.new(0).state())
	host.sim.casino().recall.load(saved)
	host.sim.advance_day()
	check(host.sim.is_mayor_dismissed(), "the recall removed the mayor")
	host.recall_flow.sync()
	host.windows.newspaper.close()
	check_eq(host.notice_dialog.title_label.text, "Removed From Office")
	host.notice_dialog.dismiss(&"title")
	check(host.title_screen.visible, "the title screen is back")
	check(not host.in_game)


func _days_in_frames(frames: int) -> int:
	var start: int = host.sim.clock.day
	for i in frames: await process_frame
	return host.sim.clock.day - start


func test_new_city_after_recall_title_advances() -> void:
	_lose_recall_and_return_to_title()
	check(host.start_new_city({"name": "Fresh Start", "seed": 4123}, flat_city()) != null)
	check(host.found_city())
	host.sim.set_speed(GameClock.Speed.FAST)
	check(await _days_in_frames(120) > 0, "a new city's days pass after a recall")


func test_loaded_city_after_recall_title_advances() -> void:
	host.begin_city(flat_city(20000), {}, 11, CityStats.new())
	var path := host.files.save_city_as(LATER_NAME)
	check(not path.is_empty())
	_lose_recall_and_return_to_title()
	check(host.load_city(path))
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "a loaded city opens paused")
	host.sim.set_speed(GameClock.Speed.FAST)
	check(await _days_in_frames(120) > 0, "a loaded city's days pass after a recall")


func test_loading_screen_city_after_recall_title_advances() -> void:
	_lose_recall_and_return_to_title()
	var city := flat_city()
	await host.run_loading("Starting…", "", host.start_new_city.bind({"name": "Covered Start", "seed": 9}, city))
	await host.run_loading("Founding…", "", host.found_city)
	check_eq(host.stage, GameHost.Stage.PLAY)
	host.sim.set_speed(GameClock.Speed.FAST)
	check(await _days_in_frames(120) > 0, "days pass in a city started behind the loading screen")


func test_stale_stopped_clock_is_repaired_when_a_city_begins() -> void:
	host.sim.set_process(false)
	host.begin_city(flat_city(20000), {}, 7, CityStats.new())
	host.sim.set_speed(GameClock.Speed.FAST)
	check(await _days_in_frames(120) > 0, "beginning a city always leaves its clock able to run")


func test_title_after_recall_does_not_run_the_old_city() -> void:
	_lose_recall_and_return_to_title()
	var day: int = host.sim.clock.day
	for i in 30: await process_frame
	check_eq(host.sim.clock.day, day, "no day passes at the title")
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
