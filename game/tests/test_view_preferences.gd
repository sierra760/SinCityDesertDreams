# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Display preferences survive a write and read; unknown keys are ignored.
extends "res://tests/test_case.gd"


func test_preferences_round_trip() -> void:
	var path := "user://test_display.cfg"
	check_eq(ViewPreferences.write({"labels": false, "overlay": &"crime"}, path), OK)
	var back := ViewPreferences.read(path)
	check_eq(back["labels"], false)
	check_eq(back["overlay"], "crime")
	check_eq(back["water_animation"], true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_unknown_keys_load_and_are_dropped_on_write() -> void:
	var path := "user://test_display_unknown.cfg"
	var config := ConfigFile.new()
	config.set_value(ViewPreferences.SECTION, "zoom", 3)
	config.set_value(ViewPreferences.SECTION, "labels", false)
	check_eq(config.save(path), OK)
	var back := ViewPreferences.read(path)
	check(not back.has("zoom"))
	check_eq(back["labels"], false)
	check_eq(ViewPreferences.write(back, path), OK)
	config = ConfigFile.new()
	check_eq(config.load(path), OK)
	check(not config.has_section_key(ViewPreferences.SECTION, "zoom"))
	check_eq(config.get_value(ViewPreferences.SECTION, "labels"), false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
