# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_casino_host.gd"

const PRIOR_NAME := "recall-prior"
const BLOCKED_PATH := "user://saves/recall-blocked.sc2d"

func after_each() -> void:
	for path in [CityFileFlow.save_path_for(PRIOR_NAME), BLOCKED_PATH, CityFileFlow.application_recovery_path(), CityFileFlow.autosave_path()]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await super.after_each()

func _seed_recall(seed: int) -> void:
	var saved := host.sim.casino().recall.save()
	saved.rng_state = str(SimRng.new(seed).state())
	host.sim.casino().recall.load(saved)

func _dismiss_mayor() -> void:
	host.sim.casino_begin_visit(COMSTOCK)
	check(host.sim.casino_commit(COMSTOCK, &"blackjack", 11000))
	host.sim.casino_settle(COMSTOCK, &"blackjack", 11000, 0)
	host.sim.casino_end_visit()
	host.notices.clear_pending()
	host.notice_dialog.dismiss()
	host.sim.clock.day = 150
	host.sim.city.day = 150
	host.sim.stats.approval = 0
	_seed_recall(0)
	host.sim.advance_day()
	check(host.sim.is_mayor_dismissed())

func test_dismissed_run_cannot_write_any_save_or_construct() -> void:
	found(20000)
	var previous := host.files.save_city_as(PRIOR_NAME)
	check(not previous.is_empty())
	check_eq(SaveFormat.save(CityFileFlow.application_recovery_path(), host.sim.city, host.sim.snapshot()), OK)
	check_eq(SaveFormat.save(CityFileFlow.autosave_path(), host.sim.city, host.sim.snapshot()), OK)
	var hashes: Dictionary = {}
	for path in [previous, CityFileFlow.application_recovery_path(), CityFileFlow.autosave_path()]: hashes[path] = FileAccess.get_sha256(path)
	_dismiss_mayor()
	check_eq(host.save_city(), ERR_UNAVAILABLE)
	check_eq(host.files.save_city_as("recall-blocked"), "")
	check_eq(host.files.write_save(BLOCKED_PATH), ERR_UNAVAILABLE)
	check_eq(host.autosave(), ERR_UNAVAILABLE)
	check_eq(host.cloud_saves.capture_background(), ERR_UNAVAILABLE)
	check_eq(host.suspend_for_background(), ERR_UNAVAILABLE)
	for path in hashes: check_eq(FileAccess.get_sha256(path), hashes[path], "last good save survives dismissal")
	check(host.is_input_blocked())
	host.tool = Tools.Kind.ROAD
	var before := host.sim.city.funds
	var outcome := host.handle_drag(Vector2i(3,3),Vector2i(4,3))
	check(not outcome.ok)
	check_eq(host.sim.city.funds, before)

func test_result_newspaper_then_dismissal_and_reload() -> void:
	found(20000)
	var previous := host.files.save_city_as(PRIOR_NAME)
	var saved_hash := FileAccess.get_sha256(previous)
	_dismiss_mayor()
	var flow: Variant = host.get("recall_flow")
	check(flow != null, "host owns dismissal flow")
	if flow == null: return
	flow.sync()
	check(host.windows.has("newspaper") and host.windows.newspaper.visible, "result newspaper is shown first")
	check(String(host.windows.newspaper.headline_text()).contains("Removed"))
	host.windows.newspaper.close()
	check_eq(host.notice_dialog.title_label.text,"Removed From Office")
	check(host.notice_dialog.body_label.text.contains("unsaved"))
	check_eq(flow.latest_save(), previous)
	host.notice_dialog.dismiss(&"reload")
	check(not host.sim.is_mayor_dismissed(), "reload restores saved mayor")
	check_eq(host.sim.city.funds,20000)
	check_eq(FileAccess.get_sha256(previous), saved_hash)

func test_failed_reload_keeps_dismissal_and_escape_cannot_resume() -> void:
	found(20000)
	_dismiss_mayor()
	var flow: Variant = host.get("recall_flow")
	check(flow != null, "host owns dismissal flow")
	if flow == null: return
	flow.sync()
	host.windows.newspaper.close()
	flow.reload_path = "user://missing-recall.sc2d"
	host.notice_dialog.dismiss(&"reload")
	check(host.sim.is_mayor_dismissed())
	check(host.is_input_blocked())
	host.notice_dialog.dismiss()
	await physics_frame
	flow.sync()
	check(host.notice_dialog.is_open(), "dismissal cannot be escaped back into city")

func test_surviving_recall_keeps_authority_and_save_available() -> void:
	found(20000)
	host.sim.casino_begin_visit(COMSTOCK)
	host.sim.casino_commit(COMSTOCK, &"blackjack", 11000)
	host.sim.casino_settle(COMSTOCK, &"blackjack", 11000, 0)
	host.sim.casino_end_visit()
	host.notices.clear_pending()
	host.notice_dialog.dismiss()
	host.sim.clock.day = 150
	host.sim.city.day = 150
	host.sim.stats.approval = 100
	_seed_recall(1)
	host.sim.advance_day()
	check(not host.sim.is_mayor_dismissed())
	check_ne(host.files.save_city_as(PRIOR_NAME), "")

func test_no_save_explains_new_city_and_return_to_title() -> void:
	found(20000)
	host.sim.city.name = "Never Saved Recall City"
	_dismiss_mayor()
	var flow: Variant = host.get("recall_flow")
	if flow == null:
		check(false,"recall flow")
		return
	flow.sync()
	host.windows.newspaper.close()
	check_eq(flow.latest_save(), "")
	check(host.notice_dialog.body_label.text.contains("No saved copy"))
	host.notice_dialog.dismiss(&"title")
	check(host.title_screen.visible)
	check(not host.in_game)
	check_eq(host.stage, GameHost.Stage.NONE)
	# The removed mayor's city is closed: the title's actions must work again.
	host.title_screen.new_city_requested.emit()
	check(host.new_city_dialog.is_open(), "New City opens from the title after a recall")

func test_restored_dismissal_still_blocks_and_reopens_result() -> void:
	found(20000)
	_dismiss_mayor()
	var snapshot := host.sim.snapshot()
	var city: City = SaveFormat.decode_city(SaveFormat.encode_city(host.sim.city)).city
	check(host.begin_city(city, snapshot, 7, null))
	check(host.sim.is_mayor_dismissed())
	host.recall_flow.sync()
	check(host.windows.newspaper.visible)
	check_eq(host.save_city(), ERR_UNAVAILABLE)

func test_direct_table_entry_owns_one_visit_and_refuses_after_removal() -> void:
	found(20000)
	check(host.open_casino_table(COMSTOCK, &"blackjack"))
	check_eq(host.sim.casino().recall.entry_funds,20000)
	host.force_close_casino()
	check_eq(host.sim.casino().recall.visit_resort,&"")
	_dismiss_mayor()
	check(not host.open_casino_table(COMSTOCK, &"blackjack"))
	check(not host.builder.place_sign(Vector2i(3,3),"After recall").ok)

func test_newer_same_named_city_cannot_replace_this_citys_last_save() -> void:
	found(20000)
	var previous := host.files.save_city_as(PRIOR_NAME)
	var foreign_path := CityFileFlow.application_recovery_path()
	var foreign := make_simulation(flat_city(12345),99)
	foreign.city.name = host.sim.city.name
	foreign.city.mayor = host.sim.city.mayor
	foreign.city.founded_year = host.sim.city.founded_year
	check_eq(SaveFormat.save(foreign_path, foreign.city, foreign.snapshot()),OK)
	foreign.free()
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(foreign_path))
	document.header.saved_at = int(Time.get_unix_time_from_system()) + 1000
	check_eq(SaveFormat._write_replacement(foreign_path,JSON.stringify(document).to_utf8_buffer()),OK)
	check_eq(host.recall_flow.latest_save(),previous,"a newer different city with the same name and mayor is never selected")

func test_loading_at_risk_visit_finishes_it_outside_without_overwriting_save() -> void:
	found(20000)
	host.sim.casino_begin_visit(COMSTOCK)
	check(host.sim.casino_commit(COMSTOCK,&"blackjack",11000))
	host.sim.casino_settle(COMSTOCK,&"blackjack",11000,0)
	check_eq(host.sim.casino().recall.due_day,-1)
	host.notice_dialog.dismiss()
	var path := host.files.save_city_as(PRIOR_NAME)
	check(not path.is_empty())
	var saved_hash := FileAccess.get_sha256(path)
	check(host.load_city(path))
	check_eq(host.sim.casino().recall.visit_resort,&"","loaded city opens outside the casino")
	check_eq(host.sim.casino().recall.due_day,150,"loading outside cannot wipe an unfinished losing visit")
	check_eq(FileAccess.get_sha256(path),saved_hash,"loading preserves the saved file")
