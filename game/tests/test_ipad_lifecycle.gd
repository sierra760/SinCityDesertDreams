# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
const RECOVERY := "user://recovery/suspended.sc2d"
const MANUAL := "user://saves/suspended.sc2d"
var host: GameHost

func before_each() -> void:
	host = MainScene.instantiate()
	host.preferences_path = "user://ipad-lifecycle.cfg"
	root.add_child(host)
	var city := flat_city()
	city.name = "iPad lifecycle fixture"
	host.begin_city(city, {}, 123, null)
	host.sim.set_speed(GameClock.Speed.PAUSED)

func after_each() -> void:
	host.free()
	for path in [RECOVERY, MANUAL, "user://autosaves/autosave.sc2d"]:
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://recovery/blocked.sc2d")
	await process_frame

func _available() -> bool:
	var available := host.has_method("suspend_for_background") and host.has_method("resume_from_background")
	check(available, "host supports explicit, testable mobile suspension")
	return available

func test_background_preserves_named_save_and_annual_backup() -> void:
	if not _available(): return
	check_eq(host.files.save_city_as("suspended"), MANUAL)
	check_eq(host.autosave(), OK)
	var manual := FileAccess.get_file_as_bytes(MANUAL)
	var annual := FileAccess.get_file_as_bytes(CityFileFlow.autosave_path())
	host.sim.city.funds -= 77
	var expected := host.sim.city.funds
	host.sim.set_speed(GameClock.Speed.FAST)
	host._drag_active = true
	check_eq(host.call("suspend_for_background"), OK)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	check(not host._drag_active, "background cannot complete an unfinished stroke")
	check_eq(host.save_path, MANUAL)
	check(host.files.has_unsaved_changes(), "recovery does not mark named save current")
	check_eq(FileAccess.get_file_as_bytes(MANUAL), manual)
	check_eq(FileAccess.get_file_as_bytes(CityFileFlow.autosave_path()), annual)
	var result := SaveFormat.load(RECOVERY)
	check(result.ok, "separate verified recovery is readable")
	if result.ok: check_eq((result.city as City).funds, expected)

func test_background_is_idempotent_and_resume_requires_deliberate_speed() -> void:
	if not _available(): return
	check_eq(host.call("suspend_for_background"), OK)
	var bytes := FileAccess.get_file_as_bytes(RECOVERY)
	check_eq(host.call("suspend_for_background"), OK)
	check_eq(FileAccess.get_file_as_bytes(RECOVERY), bytes)
	check(host.is_input_blocked(), "background owns input")
	host.call("resume_from_background")
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	check(not host.is_input_blocked())
	host.push_modal()
	host.pop_modal()
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "closing a modal cannot resurrect pre-background speed")

func test_recovery_list_and_load_do_not_target_managed_file() -> void:
	if not _available(): return
	check_eq(host.call("suspend_for_background"), OK)
	# The copy is listed while the app is away (or after it was closed there);
	# a clean return discards it.
	host.files.open_load_dialog()
	var index := host.load_dialog.paths.find(RECOVERY)
	check(index >= 0, "Load exposes background recovery")
	if index >= 0:
		check(host.load_dialog.item_list.get_item_text(index).contains(LoadDialog.RECOVERY_LABEL))
	host.load_dialog.close()
	check(host.load_city(ProjectSettings.globalize_path(RECOVERY)))
	host.call("resume_from_background")
	check_eq(host.save_path, "", "recovery must use Save As for a named save")
	check_eq(host.files.save_city_as("suspended"), MANUAL, "matching manual basename remains separate")

func test_unfounded_map_recovers_as_editing() -> void:
	if not _available(): return
	host.stage = GameHost.Stage.EDITING
	host.editing_params = {"name":"Touch terrain","seed":42}
	check_eq(host.call("suspend_for_background"), OK)
	var result := SaveFormat.load(RECOVERY)
	check(result.ok)
	if result.ok:
		check_eq(result.stage, SaveFormat.STAGE_EDITING)
		check_eq(result.generator.keys(), host.editing_params.keys())
		check_eq(result.generator.name, host.editing_params.name)
		check_eq(int(result.generator.seed), host.editing_params.seed)

func test_recovery_failure_is_returned_and_reported_after_resume() -> void:
	if not _available(): return
	var blocked := "user://recovery/blocked.sc2d"
	DirAccess.make_dir_recursive_absolute(blocked)
	var error: Error = host.call("suspend_for_background", blocked)
	check_ne(error, OK)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	check_eq(host.save_path, "")
	host.call("resume_from_background")
	check(host.notice_dialog.is_open(), "failed background backup is visible on return")

func test_no_city_suspend_is_inert() -> void:
	if not _available(): return
	host.stage = GameHost.Stage.NONE
	host.in_game = false
	var bytes := SaveFormat.encode_city(host.sim.city)
	check_eq(host.call("suspend_for_background"), ERR_UNAVAILABLE)
	host.call("resume_from_background")
	check_eq(SaveFormat.encode_city(host.sim.city), bytes)
	check(not host.notice_dialog.is_open())
