# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Captions and hints name keys only where a keyboard is in use.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const PREFERENCES := "user://test-touch-key-hints.cfg"
const SAVE_NAME := "touch-key-hints"
const TOUCH_ONLY := {"os_name": "iOS", "hardware_keyboard": false}
const TOUCH_WITH_KEYBOARD := {"os_name": "iOS", "hardware_keyboard": true}

var host: GameHost


func before_each() -> void:
	root.size = Vector2i(1280, 800)
	host = MAIN.instantiate()
	host.preferences_path = PREFERENCES
	root.add_child(host)
	await process_frame


func after_each() -> void:
	host.free()
	for path in [PREFERENCES, CityFileFlow.save_path_for(SAVE_NAME)]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await physics_frame


func _begin(environment: Dictionary) -> void:
	host.menu_bar.key_hint_environment = environment
	host.begin_city(flat_city(20000), {}, 7, CityStats.new())
	await process_frame


func test_touch_only_device_names_no_keys() -> void:
	await _begin(TOUCH_ONLY)
	check(not host.key_hints_shown())
	check_eq(host.toolbar.selected_label.text, "Tool: Inspect — free", "the selected tool names no key")
	check_eq(host.toolbar.button_for(Tools.Kind.QUERY).tooltip_text, "Inspect — free")
	check(not host.toolbar.button_for(Tools.Kind.BULLDOZE).tooltip_text.contains("["), host.toolbar.button_for(Tools.Kind.BULLDOZE).tooltip_text)
	check(not host.status_bar.speed_label.tooltip_text.contains("pauses or resumes"), host.status_bar.speed_label.tooltip_text)
	var path := host.files.save_city_as(SAVE_NAME)
	check(host.load_city(path))
	check_eq(host.status_bar.message_label.text, "Loaded %s. Paused — choose a speed (Speed menu) to start." % host.sim.city.name)
	host.select_tool(Tools.Kind.BULLDOZE)
	check(not host.toolbar.selected_label.text.contains("["), host.toolbar.selected_label.text)


func test_attached_keyboard_brings_the_key_names_back() -> void:
	await _begin(TOUCH_ONLY)
	host.menu_bar.key_hint_environment = TOUCH_WITH_KEYBOARD
	host.refresh_toolbar()
	check(host.key_hints_shown())
	check_eq(host.toolbar.selected_label.text, "Tool: Inspect — free [Q]")
	check(host.toolbar.button_for(Tools.Kind.BULLDOZE).tooltip_text.contains("[hold B]"))
	check(host.status_bar.speed_label.tooltip_text.contains("P pauses or resumes"), host.status_bar.speed_label.tooltip_text)


func test_desktop_keeps_its_key_names() -> void:
	await _begin({})
	check(host.key_hints_shown())
	check_eq(host.toolbar.selected_label.text, "Tool: Inspect — free [Q]")
	var path := host.files.save_city_as(SAVE_NAME)
	check(host.load_city(path))
	check_eq(host.status_bar.message_label.text, "Loaded %s. Paused — choose a speed (Speed menu or P) to start." % host.sim.city.name)
