# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## During the January budget review the menus either work or say why they
## wait, a Pause chosen there is kept, and the yearly backup opens paused.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const PREFERENCES := "user://test-january-review-actions.cfg"
const SAVE_NAME := "january-review-actions"

var host: GameHost


func before_each() -> void:
	root.size = Vector2i(1280, 800)
	host = MAIN.instantiate()
	host.preferences_path = PREFERENCES
	root.add_child(host)
	var city := flat_city()
	city.building.put(10, 10, 30)
	host.begin_city(city, {}, 4242, CityStats.new())
	host.sim.set_speed(GameClock.Speed.FAST)
	await process_frame


func after_each() -> void:
	host.free()
	for path in [PREFERENCES, CityFileFlow.save_path_for(SAVE_NAME), CityFileFlow.autosave_path()]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await physics_frame


func _end_year(auto_budget: bool) -> void:
	host.sim.stats.auto_budget = auto_budget
	host.sim.clock.day = GameClock.DAYS_PER_YEAR - 1
	host.sim.city.day = host.sim.clock.day
	host.sim.advance_day()
	await process_frame


func _begin_review() -> void:
	await _end_year(false)
	check(host.sim.budget_review_pending, "the review is open")
	check(host.window_manager.is_open("budget"))
	check_eq(host.modal_depth, 1)
	host.status_bar.set_message("")


func _message() -> String:
	return host.status_bar.message_label.text


func test_save_works_during_the_review() -> void:
	await _begin_review()
	host.save_path = CityFileFlow.save_path_for(SAVE_NAME)
	host.menu_bar.press(&"city_save")
	for i in 6: await process_frame
	check(FileAccess.file_exists(host.save_path), "City → Save writes the city")
	check(_message().begins_with("Saved"), _message())
	check(host.sim.budget_review_pending, "saving does not settle the year")
	check(host.window_manager.is_open("budget"))
	check_eq(host.modal_depth, 1)
	var saved := SaveFormat.load(host.save_path)
	check(bool(saved.ok))
	check(bool(saved.snapshot.get("budget_review_pending", false)), "the save reopens in the review")


func test_save_as_opens_during_the_review_and_returns_to_it() -> void:
	await _begin_review()
	host.menu_bar.press(&"city_save_as")
	await process_frame
	check(host.save_dialog.is_open(), "Save As asks for a name")
	host.save_dialog.close()
	await process_frame
	check(host.sim.budget_review_pending)
	check_eq(host.modal_depth, 1, "the review still holds the city")
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)


func test_settings_and_help_open_during_the_review() -> void:
	await _begin_review()
	host.menu_bar.press(&"options")
	await process_frame
	check(host.window_manager.is_open("options"), "Settings opens")
	host.menu_bar.press(&"help")
	await process_frame
	check(host.window_manager.is_open("help"), "Help opens")
	check(host.sim.budget_review_pending)


func test_actions_that_must_wait_say_so() -> void:
	await _begin_review()
	for action: StringName in [&"city_load", &"city_new", &"city_import", &"explore", &"street_names", &"rotate"]:
		host.status_bar.set_message("")
		var turn := host.city_view_3d.quarter_turn
		host.menu_bar.press(action)
		for i in 3: await process_frame
		check_eq(_message(), GameHost.REVIEW_HELD_MESSAGE, "%s explains why it waits" % action)
		check(not host.load_dialog.is_open() and not host.new_city_dialog.is_open() and not host.files.picker_modal, "%s opens nothing" % action)
		check(not host.is_exploring() and not host.street_names.is_active())
		check_eq(host.city_view_3d.quarter_turn, turn)
		check(host.sim.budget_review_pending)
		check_eq(host.modal_depth, 1)
	host.status_bar.set_message("")
	host.menu_bar.press(&"disaster", &"fire")
	check_eq(_message(), GameHost.REVIEW_HELD_MESSAGE)
	check(not (host.sim.get_system(&"disasters") as DisasterSystem).is_emergency(), "no disaster starts during the review")


func test_a_dialog_over_the_review_still_blocks_the_menus() -> void:
	await _begin_review()
	host.save_path = CityFileFlow.save_path_for(SAVE_NAME)
	host.notices.show("Notice", "Read me first.")
	await process_frame
	host.menu_bar.press(&"city_save")
	host.menu_bar.press(&"options")
	for i in 4: await process_frame
	check(not FileAccess.file_exists(host.save_path), "a dialog in front keeps Save from running")
	check(not host.window_manager.is_open("options"))
	host.notice_dialog.dismiss()


func test_pause_chosen_during_the_review_is_kept() -> void:
	await _begin_review()
	host.menu_bar.press(&"speed", GameClock.Speed.PAUSED)
	host.windows.budget.close()
	await process_frame
	check(not host.sim.budget_review_pending)
	check_eq(host.modal_depth, 0)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "the city stays paused after the review")
	var day: int = host.sim.clock.day
	for i in 30: await process_frame
	check_eq(host.sim.clock.day, day)


func test_speed_chosen_during_the_review_is_kept() -> void:
	await _begin_review()
	host.menu_bar.press(&"speed", GameClock.Speed.PAUSED)
	host.menu_bar.press(&"speed", GameClock.Speed.SLOW)
	host.windows.budget.close()
	await process_frame
	check_eq(host.sim.speed, GameClock.Speed.SLOW, "the last speed chosen applies")


func test_untouched_review_resumes_the_running_speed() -> void:
	await _begin_review()
	host.windows.budget.close()
	await process_frame
	check_eq(host.sim.speed, GameClock.Speed.FAST)


func test_yearly_backup_with_auto_budget_opens_paused() -> void:
	await _end_year(true)
	check(not host.sim.budget_review_pending, "automatic budgeting settles the year at once")
	check(FileAccess.file_exists(CityFileFlow.autosave_path()), "the yearly backup is written")
	check_eq(host.sim.speed, GameClock.Speed.FAST)
	check(host.load_city(CityFileFlow.autosave_path()))
	await process_frame
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "the backup opens paused")
	check_eq(host.modal_depth, 0)
	check(not host.sim.budget_review_pending)
	check(_message().contains("Paused"), _message())
	var day: int = host.sim.clock.day
	for i in 60: await process_frame
	check_eq(host.sim.clock.day, day, "no day passes until a speed is chosen")
	host._unhandled_key_input(_key(KEY_P))
	check_eq(host.sim.speed, GameClock.Speed.FAST, "P resumes the saved speed")
	for i in 60: await process_frame
	check(host.sim.clock.day > day, "and the city runs")


func test_yearly_backup_without_auto_budget_reopens_the_review() -> void:
	await _end_year(false)
	host.windows.budget.close()
	check(host.load_city(CityFileFlow.autosave_path()))
	await process_frame
	check(host.sim.budget_review_pending, "the review reopens")
	check(host.window_manager.is_open("budget"))
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	host.windows.budget.close()
	check_eq(host.sim.speed, GameClock.Speed.FAST, "closing it continues at the saved speed")


func _key(code: int) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	return key
