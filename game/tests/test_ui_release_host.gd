# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
class ReleaseHost extends GameHost:
	var fail_autosave := false
	func autosave() -> Error:
		return ERR_CANT_CREATE if fail_autosave else OK

class ReleaseFiles extends CityFileFlow:
	var fail_save := false
	var quit_count := 0
	func write_save(path: String) -> Error:
		return ERR_CANT_CREATE if fail_save else super.write_save(path)
	func _quit_now() -> void:
		quit_count += 1

var host: ReleaseHost
var files: ReleaseFiles
var cleanup_paths: Array[String] = []

func before_each() -> void:
	var instance := MainScene.instantiate()
	instance.set_script(ReleaseHost)
	host = instance
	files = ReleaseFiles.new(host)
	host.files = files
	host.preferences_path = "user://ui-release-tests.cfg"
	root.add_child(host)
	var city := flat_city()
	city.name = "Release fixture"
	host.begin_city(city, {}, 123, null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.save_path = ""

func after_each() -> void:
	await _wait_for_loading()
	host.free()
	for path in cleanup_paths: DirAccess.remove_absolute(path)
	cleanup_paths.clear()
	await process_frame

func _wait_for_loading() -> void:
	for frame in 20:
		if not host.loading_screen.visible: return
		await process_frame
	check(false,"loading completes before checking continuation or freeing Main")

func test_destructive_action_cancel_and_discard() -> void:
	var city := host.sim.city
	host.files.request_city_action(&"new")
	check(host.notice_dialog.is_open())
	check(not host.new_city_dialog.is_open())
	host.escape()
	check_eq(host.sim.city, city)
	check(not host.new_city_dialog.is_open(), "Escape cancels replacement")
	host.files.request_city_action(&"new")
	host.notice_dialog.dismiss(&"discard")
	check(host.new_city_dialog.is_open())
	host.new_city_dialog.close()
	check_eq(host.modal_depth, 0)

func test_save_checkpoint_detects_gameplay_but_not_pause() -> void:
	var path := CityFileFlow.save_path_for("ui-release-checkpoint")
	cleanup_paths.append(path)
	check_eq(host.files.save_city_as("ui-release-checkpoint"), path)
	check(not host.files.has_unsaved_changes())
	host.sim.set_speed(GameClock.Speed.FAST)
	check(not host.files.has_unsaved_changes(), "speed alone does not discard city work")
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.sim.city.funds -= 1
	check(host.files.has_unsaved_changes())

func test_save_as_collision_cancel_preserves_file() -> void:
	var path := CityFileFlow.save_path_for("ui-release-collision")
	cleanup_paths.append(path)
	check_eq(host.files.save_city_as("ui-release-collision"), path)
	var before := FileAccess.get_file_as_bytes(path)
	# The open city now has another file; saving over its own file never asks.
	var other := CityFileFlow.save_path_for("ui-release-collision-other")
	cleanup_paths.append(other)
	check_eq(host.files.save_city_as("ui-release-collision-other"), other)
	host.sim.city.funds -= 100
	host.files.request_save_as("ui-release-collision?")
	check(host.notice_dialog.is_open())
	host.escape()
	check_eq(FileAccess.get_file_as_bytes(path), before)
	host.files.request_save_as("ui-release-collision")
	host.notice_dialog.dismiss(&"replace")
	check_ne(FileAccess.get_file_as_bytes(path), before)

func test_import_cancel_restores_speed() -> void:
	host.sim.set_speed(GameClock.Speed.FAST)
	host.files.open_import_dialog()
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	check_eq(host.modal_depth, 1)
	host.files.import_dialog.canceled.emit()
	check_eq(host.sim.speed, GameClock.Speed.FAST)
	check_eq(host.modal_depth, 0)
	host.files.import_dialog.hide()

func test_reopened_window_is_escape_target() -> void:
	var help := host.open_window("help")
	var options := host.open_window("options")
	host.open_window("help")
	host.escape()
	check(not help.visible)
	check(options.visible)

func test_transient_feedback_uses_visible_seconds() -> void:
	host.show_message("Saved city.")
	for i in 8: host._on_day_advanced(1950,1,i)
	check_eq(host.status_bar.message_label.text, "Saved city.", "fast days cannot erase a message")
	host._process(9.0)
	check(host.status_bar.message_label.text != "Saved city.")

func test_save_then_leave_and_cancel_save_dialog() -> void:
	var name := "ui-release-continuation"
	cleanup_paths.append(CityFileFlow.save_path_for(name))
	host.files.request_city_action(&"new")
	host.notice_dialog.dismiss(&"save")
	check(host.save_dialog.is_open())
	host.save_dialog.close()
	check(not host.new_city_dialog.is_open())
	check_eq(host.modal_depth, 0)
	host.files.request_city_action(&"new")
	host.notice_dialog.dismiss(&"save")
	host.save_dialog.name_edit.text = name
	host.save_dialog.confirm()
	await process_frame
	await _wait_for_loading()
	check(FileAccess.file_exists(CityFileFlow.save_path_for(name)))
	check(host.new_city_dialog.is_open(), "replacement only continues after save succeeds")
	host.new_city_dialog.close()
	check_eq(host.modal_depth, 0)

func test_failed_save_never_continues_or_changes_save_path() -> void:
	files.fail_save = true
	check_ne(host.save_city(), OK)
	check_eq(host.save_path, "", "failed first save does not claim a path")
	host.save_path = "user://ui-failed-existing.sc2d"
	host.files.request_city_action(&"new")
	host.notice_dialog.dismiss(&"save")
	await _wait_for_loading()
	check(not host.new_city_dialog.is_open())
	check_eq(host.files._after_save_action, &"")
	check(host.files.has_unsaved_changes())

func test_native_close_obeys_cancel_then_discard() -> void:
	root.close_requested.emit()
	check_eq(files.quit_count, 0)
	host.escape()
	check_eq(files.quit_count, 0)
	root.close_requested.emit()
	host.notice_dialog.dismiss(&"discard")
	check_eq(files.quit_count, 1)

func test_title_settings_and_help_are_above_title() -> void:
	host.in_game = false
	host._show_title()
	host.title_screen.settings_requested.emit()
	check(host.window_manager.is_open("options"))
	check_eq(host.windows.options.get_parent(), host.modal_layer)
	host.escape()
	check(not host.window_manager.is_open("options"))
	host.menu_bar.press(&"help")
	check(host.window_manager.is_open("help"))
	check_eq(host.windows.help.get_parent(), host.modal_layer)

func test_open_inspector_refreshes_after_simulation_signal() -> void:
	host.open_query(Vector2i(40,40))
	host.sim.city.signs[Vector2i(40,40)] = "Updated by simulation"
	host.sim.map_changed.emit(Rect2i(40,40,1,1))
	host._process(0.0)
	check_eq(host.query_panel.info.get("Sign"), "Updated by simulation")

func test_native_close_during_save_does_not_nest_modal() -> void:
	host.files.open_save_dialog()
	root.close_requested.emit()
	# Save As is closed as Cancel would close it; the close goes straight on.
	check(not host.save_dialog.is_open(), "the simple dialog closes")
	check(host.notice_dialog.is_open(), "the close continues with the unsaved-changes prompt")
	check_eq(host.modal_depth, 1, "only the prompt holds input; nothing is nested")
	check_eq(files.quit_count, 0, "nothing quits before the player answers")
	host._process(0.0)
	check_eq(host.modal_depth, 1, "no second prompt is stacked")
	host.notice_dialog.dismiss(&"discard")
	check_eq(files.quit_count, 1)

func test_native_close_held_by_a_dialog_can_still_be_cancelled() -> void:
	host.files.open_save_dialog()
	root.close_requested.emit()
	root.close_requested.emit()
	host.save_dialog.cancel_button.pressed.emit()
	host._process(0.0)
	check(host.notice_dialog.is_open())
	host.escape()
	host._process(0.0)
	check(not host.notice_dialog.is_open(), "a cancelled close is not asked again")
	check_eq(files.quit_count, 0)

func test_title_settings_cannot_cover_new_city_modal() -> void:
	host.in_game = false
	host._show_title()
	host.title_screen.settings_requested.emit()
	host.title_screen.new_city_requested.emit()
	check(not host.window_manager.is_open("options"))
	check(host.new_city_dialog.is_open())
	check_eq(host.new_city_dialog.get_index(), host.modal_layer.get_child_count()-1)

func test_checkpoint_has_no_mutable_runtime_aliases() -> void:
	var path := CityFileFlow.save_path_for("ui-release-nested")
	cleanup_paths.append(path)
	host.sim.stats.bonds.append({"principal":10000,"rate":5})
	host.files.save_city_as("ui-release-nested")
	check(not host.files.has_unsaved_changes())
	host.sim.stats.bonds[0]["rate"] = 6
	check(host.files.has_unsaved_changes(), "nested runtime edits do not rewrite saved baseline")

func test_autosave_failure_and_budget_review_balance_holds() -> void:
	for automatic in [false,true]:
		host.fail_autosave = true
		host.sim.stats.auto_budget = automatic
		host.sim.budget_review_pending = true
		host.sim.set_speed(GameClock.Speed.FAST)
		host._on_budget_review_due(1950)
		check_eq(host.notice_dialog.title_label.text, "Automatic Backup Failed")
		check_eq(host.sim.speed, GameClock.Speed.PAUSED)
		check_eq(host.modal_depth, 1 if automatic else 2)
		host.notice_dialog.dismiss()
		if not automatic:
			check_eq(host.modal_depth, 1)
			check_eq(host.sim.speed, GameClock.Speed.PAUSED)
			host.windows.budget.close()
		check_eq(host.modal_depth, 0)
		check_eq(host.sim.speed, GameClock.Speed.FAST)
		check(not host.sim.budget_review_pending)


func test_city_saved_during_budget_review_reopens_review_on_load() -> void:
	var path := CityFileFlow.save_path_for("ui-release-review")
	cleanup_paths.append(path)
	host.sim.stats.auto_budget = false
	var year_end := GameClock.DAYS_PER_YEAR - 1
	host.sim.clock.day = year_end
	host.sim.city.day = year_end
	host.sim.set_speed(GameClock.Speed.FAST)
	# The automatic backup is written while the year-end day is being reported.
	host.sim.budget_review_pending = true
	check_eq(host.files.save_city_as("ui-release-review"), path)
	host.sim.budget_review_pending = false
	check(host.load_city(path))
	check(host.sim.budget_review_pending, "loaded city is still in its January review")
	check_eq(host.sim.clock.day, year_end + 1, "the year-end day that already ran is not run again")
	check(host.windows.has("budget") and host.windows.budget.visible, "the review reopens on load")
	if not host.windows.has("budget"): return
	check_eq(host.modal_depth, 1)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	host.windows.budget.close()
	check(not host.sim.budget_review_pending, "closing the reopened review resumes time")
	check_eq(host.modal_depth, 0)
	check_eq(host.sim.speed, GameClock.Speed.FAST)
