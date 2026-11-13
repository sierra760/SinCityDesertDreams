# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A city opened with Load City → Browse saves into the game's own saved
## cities, never beside the picked file. A recovered city that was never saved
## stays unsaved and keeps its recovery copy until it is saved.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const PREFERENCES := "user://test-browsed-recovered.cfg"
const OUTSIDE_DIR := "user://picked-elsewhere"
const OUTSIDE := "user://picked-elsewhere/Browsed Town.sc2d"
const LIBRARY_NAME := "browsed-town-kept"
const INSIDE_NAME := "browsed-inside-library"
const RECOVERED_NAME := "recovered-and-kept"

var host: GameHost


func before_each() -> void:
	await _new_host()


func after_each() -> void:
	host.free()
	_remove_files()
	await physics_frame


func _new_host() -> void:
	host = MAIN.instantiate()
	host.preferences_path = PREFERENCES
	root.add_child(host)
	for i in 3: await process_frame


func _remove_files() -> void:
	for path in [PREFERENCES, OUTSIDE, CityFileFlow.save_path_for(LIBRARY_NAME), CityFileFlow.save_path_for(INSIDE_NAME),
			CityFileFlow.save_path_for(RECOVERED_NAME), CityFileFlow.application_recovery_path(),
			CityFileFlow.application_recovery_fallback_path(), CityFileFlow.recovery_destination_path()]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var outside := ProjectSettings.globalize_path(OUTSIDE_DIR)
	if DirAccess.dir_exists_absolute(outside):
		for name: String in DirAccess.get_directories_at(outside):
			for file: String in DirAccess.get_files_at(outside.path_join(name)): DirAccess.remove_absolute(outside.path_join(name).path_join(file))
			DirAccess.remove_absolute(outside.path_join(name))
		DirAccess.remove_absolute(outside)


func _wait_for_loading() -> void:
	for i in 4: await process_frame
	for i in 120:
		if not host.loading_screen.visible: break
		await process_frame
	await process_frame


func _write_city(path: String, city_name: String, founded: bool = true) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var city := flat_city(31000)
	city.name = city_name
	city.mayor = "Mayor Elsewhere"
	if founded:
		var sim := Simulation.new()
		sim.setup(city, 11, CityStats.new())
		sim.advance_days(3)
		check_eq(SaveFormat.save(path, city, sim.snapshot()), OK)
		sim.free()
	else:
		check_eq(SaveFormat.save(path, city, {}, SaveFormat.STAGE_EDITING, {"name": city_name, "seed": 5}), OK)


## Pick `path` in the file picker that Load City → Browse opens.
func _browse(path: String) -> void:
	host.files.open_native_load_dialog()
	check(host.files.picker_modal, "the file picker is open")
	host.files.native_load_dialog.hide()
	host.files.native_load_dialog.file_selected.emit(ProjectSettings.globalize_path(path))
	await _wait_for_loading()


func _outside_entries() -> Array:
	var absolute := ProjectSettings.globalize_path(OUTSIDE_DIR)
	var names: Array = Array(DirAccess.get_files_at(absolute))
	var directory := DirAccess.open(absolute)
	directory.include_hidden = true
	names.append_array(Array(directory.get_directories()))
	names.sort()
	return names


func test_browsed_city_saves_into_the_saved_cities_folder() -> void:
	_write_city(OUTSIDE, "Browsed Town")
	var picked := FileAccess.get_sha256(OUTSIDE)
	await _browse(OUTSIDE)
	check(host.in_game and host.sim.city.name == "Browsed Town", "the picked city opens")
	check_eq(host.sim.city.mayor, "Mayor Elsewhere", "it keeps its mayor")
	check_eq(host.save_path, "", "the picked file is not the save destination")
	check(not host.files.has_unsaved_changes(), "an unchanged browsed city has nothing to save")
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "it opens paused")
	check(host.status_bar.message_label.text.begins_with("Opened Browsed Town."), host.status_bar.message_label.text)
	# City → Save asks for a name, as Save As does.
	host.menu_bar.press(&"city_save")
	await process_frame
	check(host.save_dialog.is_open(), "the first Save asks for a name")
	check_eq(FileAccess.get_sha256(OUTSIDE), picked, "nothing is written beside the picked file")
	host.save_dialog.close()
	await process_frame
	host.sim.city.funds -= 500
	check(host.files.has_unsaved_changes())
	var saved := host.files.save_city_as(LIBRARY_NAME)
	check_eq(saved, CityFileFlow.save_path_for(LIBRARY_NAME), "the city is saved with the player's cities")
	check_eq(host.save_path, saved)
	check_eq(FileAccess.get_sha256(OUTSIDE), picked, "the picked file is untouched")
	check_eq(_outside_entries(), ["Browsed Town.sc2d"], "no working folder is left beside the picked file")
	var listed := false
	for row: Dictionary in SaveFormat.list_saves():
		if String(row.path) == saved: listed = true
	check(listed, "Load City lists the saved city")
	# Later saves go to the same place.
	host.sim.city.funds -= 500
	check_eq(host.save_city(), OK)
	check_eq(FileAccess.get_sha256(OUTSIDE), picked)
	check_eq(int((SaveFormat.load(saved).city as City).funds), 30000)


func test_changed_browsed_city_asks_before_leaving_and_saves_by_name() -> void:
	_write_city(OUTSIDE, "Browsed Town")
	await _browse(OUTSIDE)
	host.sim.city.funds -= 1
	host.files.request_city_action(&"new")
	await process_frame
	check_eq(host.notice_dialog.title_label.text, "Save Your City?")
	host.notice_dialog.dismiss(&"save")
	await process_frame
	check(host.save_dialog.is_open(), "Save asks for a name instead of writing to the picked file")
	host.save_dialog.close()
	await process_frame


func test_browsed_unfounded_map_also_saves_into_the_saved_cities_folder() -> void:
	_write_city(OUTSIDE, "Browsed Land", false)
	var picked := FileAccess.get_sha256(OUTSIDE)
	await _browse(OUTSIDE)
	check_eq(host.stage, GameHost.Stage.EDITING)
	check_eq(host.save_path, "")
	check(host.status_bar.message_label.text.begins_with("Opened Browsed Land."), host.status_bar.message_label.text)
	check_eq(host.files.save_city_as(LIBRARY_NAME), CityFileFlow.save_path_for(LIBRARY_NAME))
	check_eq(FileAccess.get_sha256(OUTSIDE), picked)


func test_browsing_into_the_saved_cities_folder_is_an_ordinary_load() -> void:
	var inside := CityFileFlow.save_path_for(INSIDE_NAME)
	_write_city(inside, "Inside Town")
	await _browse(inside)
	check_eq(host.sim.city.name, "Inside Town")
	check_eq(ProjectSettings.globalize_path(host.save_path), ProjectSettings.globalize_path(inside), "its own file stays its save")
	check(host.status_bar.message_label.text.begins_with("Loaded Inside Town."), host.status_bar.message_label.text)


func test_unreadable_browsed_file_leaves_the_open_city_alone() -> void:
	host.begin_city(flat_city(20000), {}, 7, CityStats.new())
	var open_city := host.sim.city
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTSIDE_DIR))
	var file := FileAccess.open(OUTSIDE, FileAccess.WRITE)
	file.store_string("{\"format\": \"something else\"}")
	file.close()
	await _browse(OUTSIDE)
	check_eq(host.sim.city, open_city)
	check_eq(host.notice_dialog.title_label.text, "Cannot Load")
	host.notice_dialog.dismiss()


func _recover_never_saved_city() -> String:
	var recovery := CityFileFlow.application_recovery_path()
	var city := flat_city(20000)
	city.name = "Never Saved"
	host.begin_city(city, {}, 77, null)
	host.sim.advance_days(40)
	check_eq(host.save_path, "")
	check_eq(host.suspend_for_background(), OK)
	check(FileAccess.file_exists(recovery), "leaving the app writes the recovery copy")
	# The app is closed while it is away; the next launch starts afresh.
	host.free()
	await process_frame
	await _new_host()
	check(host.session.load_city(recovery), "the recovery copy loads")
	check_eq(host.sim.city.name, "Never Saved")
	return recovery


func test_recovered_never_saved_city_stays_unsaved_and_keeps_its_copy() -> void:
	var recovery := await _recover_never_saved_city()
	check_eq(host.save_path, "", "it has no named save")
	check(host.files.has_unsaved_changes(), "a recovered city that was never saved is unsaved")
	check(host.status_bar.message_label.text.begins_with("Recovered Never Saved. Save it to keep it."), host.status_bar.message_label.text)
	# A short trip away and back.
	check_eq(host.suspend_for_background(), OK)
	host.resume_from_background()
	check(FileAccess.file_exists(recovery), "returning does not remove the only copy")
	check(host.files.has_unsaved_changes())
	# Leaving asks first.
	host.files.request_city_action(&"load")
	await process_frame
	check_eq(host.notice_dialog.title_label.text, "Save Your City?", "leaving the recovered city asks to save it")
	check(not host.load_dialog.is_open())
	host.notice_dialog.dismiss(&"cancel")
	await process_frame
	check(FileAccess.file_exists(recovery))
	# Saving it under a name makes the copy unnecessary.
	check_eq(host.files.save_city_as(RECOVERED_NAME), CityFileFlow.save_path_for(RECOVERED_NAME))
	check(not host.files.has_unsaved_changes())
	check(not FileAccess.file_exists(recovery), "a named save replaces the recovery copy")
	check_eq(host.suspend_for_background(), OK)
	host.resume_from_background()
	check(not FileAccess.file_exists(recovery), "a saved city's copy is removed on return as usual")


func test_recovered_city_declined_on_leaving_stays_in_the_load_list() -> void:
	var recovery := await _recover_never_saved_city()
	host.files.request_city_action(&"new")
	await process_frame
	check_eq(host.notice_dialog.title_label.text, "Save Your City?")
	host.notice_dialog.dismiss(&"discard")
	await process_frame
	check(host.new_city_dialog.is_open(), "Don't Save goes on to New City")
	host.new_city_dialog.close()
	check(FileAccess.file_exists(recovery), "the copy is still there to load")


func test_ordinary_city_copy_is_removed_on_a_clean_return() -> void:
	var recovery := CityFileFlow.application_recovery_path()
	host.begin_city(flat_city(20000), {}, 7, CityStats.new())
	check_eq(host.suspend_for_background(), OK)
	check(FileAccess.file_exists(recovery))
	host.resume_from_background()
	check(not FileAccess.file_exists(recovery), "a city still open after a clean return needs no recovery copy")
