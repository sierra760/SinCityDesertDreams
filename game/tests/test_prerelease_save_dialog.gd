# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

var dialog: SaveDialog

func before_each() -> void:
	dialog = SaveDialog.new()
	root.add_child(dialog)

func after_each() -> void:
	dialog.free()
	await process_frame

func test_pasted_save_extension_is_not_part_of_the_name() -> void:
	for entered in ["Desert Springs.sc2d", " Desert Springs.SC2D "]:
		dialog.open(entered)
		check_eq(dialog.filename_label.text, "File: Desert Springs.sc2d")
		var names: Array[String] = []
		var collect := func(value: String) -> void: names.append(value)
		dialog.save_requested.connect(collect)
		dialog.confirm()
		check_eq(names, ["Desert Springs"] as Array[String])
		dialog.save_requested.disconnect(collect)

func test_empty_extension_still_requires_a_name() -> void:
	dialog.open(".sc2d")
	dialog.confirm()
	check(dialog.is_open())
	check(dialog.hint_label.text.contains("Type a name"))

func test_save_location_is_a_real_folder_path() -> void:
	var folder := ProjectSettings.globalize_path(SaveFormat.default_dir())
	dialog.open("Town")
	check(dialog.hint_label.text.contains(SaveDialog.display_folder(folder)))
	check_eq(dialog.hint_label.tooltip_text, folder, "the full folder stays one hover away")
	check(not dialog.hint_label.text.contains("user://"))
	var home := OS.get_environment("HOME")
	if not home.is_empty() and folder.begins_with(home + "/"):
		check(not dialog.hint_label.text.contains(home), "the home folder is shortened to ~")
		check(dialog.hint_label.text.contains("~" + folder.substr(home.length())))
	dialog.close()
	dialog.open("Other Town")
	check(dialog.hint_label.text.contains(SaveDialog.display_folder(folder)))

func test_picker_title_explains_the_requested_city_file() -> void:
	var host: GameHost = load("res://scenes/main.tscn").instantiate()
	host.preferences_path = "user://prerelease-picker.cfg"
	root.add_child(host)
	for frame in 4: await process_frame
	for title in ["Import Classic City", "Open Saved City"]:
		var picker := host.files._make_city_picker(title, "*.sc2d ; Saved city")
		check_eq(picker.title, title)
		check_eq(picker.use_native_dialog, DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE), "actual city picker follows the current backend capability")
		host.remove_child(picker)
		picker.free()
	host.free()
	await process_frame
