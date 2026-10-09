# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
const MANUAL := "user://saves/autosave.sc2d"
const BACKUP := "user://autosaves/autosave.sc2d"
var host: GameHost

func before_each() -> void:
	host = MainScene.instantiate()
	host.preferences_path = "user://autosave-safety.cfg"
	root.add_child(host)
	var city := flat_city()
	city.name = "Recovery fixture"
	host.begin_city(city, {}, 123, null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.save_path = ""

func after_each() -> void:
	host.free()
	for path in [MANUAL, BACKUP, "user://saves/Recovered.sc2d"]:
		DirAccess.remove_absolute(path)
	await process_frame

func test_automatic_backup_preserves_manually_named_autosave() -> void:
	check_eq(host.files.save_city_as("autosave"), MANUAL)
	var before := FileAccess.get_file_as_bytes(MANUAL)
	host.sim.city.funds -= 123
	var expected_funds := host.sim.city.funds
	check_eq(host.autosave(), OK)
	check(FileAccess.get_file_as_bytes(MANUAL) == before, "automatic backup must not overwrite a manual save called autosave")
	check_eq(host.save_path, MANUAL)
	check(host.files.has_unsaved_changes(), "automatic backup does not mark manual save current")
	check(FileAccess.file_exists(BACKUP), "backup has a separate storage location")
	if FileAccess.file_exists(BACKUP):
		var result := SaveFormat.load(BACKUP)
		check(result.ok)
		check_eq((result.city as City).funds, expected_funds)

func test_backup_is_listed_and_recovers_through_save_as() -> void:
	check_eq(host.files.save_city_as("autosave"), MANUAL)
	check_eq(SaveFormat.save(BACKUP, host.sim.city, host.sim.snapshot()), OK)
	host.files.open_load_dialog()
	var index := host.load_dialog.paths.find(BACKUP)
	check(index >= 0, "default Load includes managed automatic backup")
	check(host.load_dialog.paths.has(MANUAL), "legacy/manual autosave remains loadable")
	if index >= 0:
		check(host.load_dialog.item_list.get_item_text(index).contains("Automatic backup"))
		host.load_dialog.select(index)
		check(host.load_dialog.details_label.text.contains("Automatic backup"))
	host.load_dialog.close()
	check(host.load_city(ProjectSettings.globalize_path(BACKUP)), "native picker absolute path recovers backup")
	check_eq(host.save_path, "", "recovered backup must not become manual save target")
	var before := FileAccess.get_file_as_bytes(BACKUP)
	host.sim.city.funds -= 50
	host._on_menu_action(&"city_save", null)
	check(host.save_dialog.is_open(), "Save on a recovered backup requests a manual name")
	if host.save_dialog.is_open():
		host.save_dialog.name_edit.text = "Recovered"
		host.save_dialog.confirm()
		await process_frame
		while host.loading_screen.visible: await process_frame
		check_eq(host.save_path, "user://saves/Recovered.sc2d")
	check(FileAccess.get_file_as_bytes(BACKUP) == before, "recovery Save leaves backup unchanged")
	check(host.load_city(MANUAL))
	check_eq(host.save_path, MANUAL, "legacy autosave behaves as an ordinary manual save")

# Guards against: a stale background recovery copy listed forever after the
# city was saved or the app came back.
func test_recovery_copy_is_discarded_when_no_longer_needed() -> void:
	var recovery := CityFileFlow.application_recovery_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(recovery.get_base_dir()))
	check_eq(SaveFormat.save(recovery, host.sim.city, host.sim.snapshot()), OK)
	host.files.open_load_dialog()
	var index := host.load_dialog.paths.find(recovery)
	check(index >= 0, "the recovery copy is listed")
	if index >= 0:
		check(host.load_dialog.item_list.get_item_text(index).contains(LoadDialog.RECOVERY_LABEL))
		host.load_dialog.select(index)
		check(host.load_dialog.details_label.text.begins_with(LoadDialog.RECOVERY_LABEL))
	host.load_dialog.close()
	# Saving another city keeps it.
	var other := flat_city()
	other.name = "Another town"
	check_eq(SaveFormat.save(recovery, other, {}), OK)
	check_eq(host.files.save_city_as("Recovered"), "user://saves/Recovered.sc2d")
	check(FileAccess.file_exists(recovery), "another city's recovery copy stays")
	# A named save of the city opened from the copy supersedes it.
	check_eq(SaveFormat.save(recovery, host.sim.city, host.sim.snapshot()), OK)
	check(host.load_city(recovery), "the recovery copy opens")
	check_eq(host.files.save_city_as("Recovered"), "user://saves/Recovered.sc2d")
	check(not FileAccess.file_exists(recovery), "saving the city removes its recovery copy")
	host.files.open_load_dialog()
	check(host.load_dialog.paths.find(recovery) < 0, "no recovery row afterwards")
	host.load_dialog.close()
	# A clean return from the background removes it as well.
	check_eq(SaveFormat.save(recovery, other, {}), OK)
	host.files.discard_recovery_copy()
	check(not FileAccess.file_exists(recovery))

# Guards against: a newer recovery copy (left when the OS closed the app in
# the background) deleted because an older manual save of the same city was
# opened and saved instead.
func test_saving_an_older_save_of_the_same_city_keeps_a_newer_recovery_copy() -> void:
	var recovery := CityFileFlow.application_recovery_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(recovery.get_base_dir()))
	var manual := "user://saves/Recovered.sc2d"
	check_eq(host.files.save_city_as("Recovered"), manual)
	host.sim.city.funds -= 777
	var newer_funds := host.sim.city.funds
	# An earlier session's newer copy of the same city.
	check_eq(SaveFormat.save(recovery, host.sim.city, host.sim.snapshot()), OK)
	check(host.load_city(manual), "the older manual save opens")
	check_eq(host.sim.city.name, "Recovery fixture", "same city name as the recovery copy")
	check_eq(host.files.save_city(), OK)
	check(FileAccess.file_exists(recovery), "the newer recovery copy survives the older save")
	var result := SaveFormat.load(recovery)
	check(result.ok)
	if result.ok: check_eq((result.city as City).funds, newer_funds, "the recovery copy keeps its newer progress")
	host.files.discard_recovery_copy()
