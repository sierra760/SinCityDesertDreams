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
