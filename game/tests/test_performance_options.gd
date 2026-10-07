# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func test_graphics_preferences_validate_and_persist() -> void:
	var clean := ViewPreferences.sanitize({"render_quality":"performance", "render_scale":75})
	check_eq(clean.get("render_quality"), "performance", "graphics profile retained")
	check_eq(clean.get("render_scale"), 75, "render resolution retained separately from UI")
	var bad := ViewPreferences.sanitize({"render_quality":"invalid", "render_scale":NAN})
	check_eq(bad.get("render_quality"), "high")
	check_eq(bad.get("render_scale"), 100)
	var path := "user://performance-options-test.cfg"
	check_eq(ViewPreferences.write(clean,path), OK)
	check_eq(ViewPreferences.read(path),clean)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_options_graphics_roundtrip_is_silent() -> void:
	var options := OptionsWindow.new()
	var emitted: Array = []
	options.option_changed.connect(func(key,value): emitted.append([key,value]))
	options.set_values({"render_quality":"balanced","render_scale":75})
	check_eq(options.values().get("render_quality"),"balanced")
	check_eq(options.values().get("render_scale"),75)
	check(emitted.is_empty(),"reflecting preferences must not send changes")
	options.free()
