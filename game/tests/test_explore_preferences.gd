# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func test_camera_options_are_bounded_and_not_city_state() -> void:
	var clean := ViewPreferences.sanitize({"explore_sensitivity":NAN,"explore_invert_y":"bad"})
	check(clean.has("explore_sensitivity") and clean.has("explore_invert_y"),"exploration display options exist")
	if not clean.has("explore_sensitivity"): return
	check_eq(clean.explore_sensitivity,1.0)
	check_eq(clean.explore_invert_y,false)
	for value: float in [INF,-INF]:
		check_eq(ViewPreferences.sanitize({"explore_sensitivity":value}).explore_sensitivity,1.0)
	for value: Variant in [1,0,"true",1.0]:
		check_eq(ViewPreferences.sanitize({"explore_invert_y":value}).explore_invert_y,false)
	check_eq(ViewPreferences.sanitize({"explore_sensitivity":100.0}).explore_sensitivity,3.0)
	check_eq(ViewPreferences.sanitize({"explore_sensitivity":-.1}).explore_sensitivity,.25)
	var path := "user://test_explore_preferences.cfg"
	check_eq(ViewPreferences.write({"explore_sensitivity":1.5,"explore_invert_y":true},path),OK)
	var restored := ViewPreferences.read(path)
	check_eq(restored.explore_sensitivity,1.5)
	check_eq(restored.explore_invert_y,true)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
