# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Grid preferences reach the live view without changing the physical city.
extends "res://tests/exploration/async_test_case.gd"

func test_grid_preference_defaults_and_validation() -> void:
	check_eq(ViewPreferences.sanitize({}).get("tile_grid"), true, "existing profiles receive the subtle grid")
	check_eq(ViewPreferences.sanitize({"tile_grid": false}).get("tile_grid"), false)
	for invalid: Variant in ["false", 0, null]:
		check_eq(ViewPreferences.sanitize({"tile_grid": invalid}).get("tile_grid"), true, "invalid settings retain the default")

func test_main_checkbox_persists_and_restores_grid() -> void:
	var path := "user://tile-grid-test.cfg"
	check_eq(ViewPreferences.write({"tile_grid": false}, path), OK)
	var host := (load("res://scenes/main.tscn") as PackedScene).instantiate() as GameHost
	host.preferences_path = path
	root.add_child(host)
	var options := host.open_window("options") as OptionsWindow
	check(options.checks.has(&"tile_grid"), "Options exposes the tile grid")
	if options.checks.has(&"tile_grid"):
		var view := host.city_view_3d
		check_eq(view.water_style.material.get_shader_parameter("tile_grid_enabled"), false, "Main restores the saved off setting")
		options.checks[&"tile_grid"].button_pressed = true
		check_eq(view.water_style.material.get_shader_parameter("tile_grid_enabled"), true, "checkbox reaches the terrain material")
		check_eq(ViewPreferences.read(path).get("tile_grid"), true, "Main saves the change")
		view.bind_city(flat_city())
		view.set_active(true)
		var encoded := SaveFormat.encode_city(view.city)
		var revision: int = view.traversal_snapshot().revision
		var chunk_id := view.chunks.get_child(0).get_instance_id()
		var faces: PackedVector3Array = view.traversal_snapshot().chunks[0].faces.duplicate()
		options.checks[&"tile_grid"].button_pressed = false
		for quality: String in ["high", "balanced", "performance"]:
			view.set_render_options(quality, 50)
			check_eq(view.water_style.material.get_shader_parameter("tile_grid_enabled"), false, "quality preserves the toggle")
		check_eq(view.traversal_snapshot().revision, revision, "grid does not rebuild physical geometry")
		check_eq(view.chunks.get_child(0).get_instance_id(), chunk_id, "grid reuses terrain chunks")
		check_eq(view.traversal_snapshot().chunks[0].faces, faces, "picking and physical faces are unchanged")
		check_eq(SaveFormat.encode_city(view.city), encoded, "grid does not change saved city data")
		check_eq(ViewPreferences.read(path).get("tile_grid"), false, "off setting is persisted")
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	host.free()
	DirAccess.remove_absolute(path)
