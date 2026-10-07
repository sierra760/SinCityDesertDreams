# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Model catalog admission, footprint ownership and collision isolation.
extends "res://tests/test_case.gd"


func _entry(code: int = Buildings.RES_1X1_FIRST) -> Dictionary:
	var size := Buildings.size(code)
	return {"code": code, "path": CityModelCatalog.ROOT + "%d-blender.glb" % code,
		"scale": 0.0625, "pivot": [0, 0, 0], "yaw": 0, "height": 1.25, "footprint": [size.x, size.y]}


func test_adjacent_lots_deduplicate_for_all_corner_rotations() -> void:
	for rotation: int in 4:
		var city := flat_city()
		var code := Buildings.RES_2X2_FIRST
		city.stamp_building(10, 10, code, Zones.RES_HIGH)
		city.stamp_building(12, 10, code, Zones.RES_HIGH)
		var ring := [Zones.CORNER_NW, Zones.CORNER_NE, Zones.CORNER_SE, Zones.CORNER_SW]
		for anchor: Vector2i in [Vector2i(10, 10), Vector2i(12, 10)]:
			var cells: Array[Vector2i] = [anchor, anchor + Vector2i(1, 0), anchor + Vector2i.ONE, anchor + Vector2i(0, 1)]
			for i: int in 4:
				city.zone.putv(cells[i], Zones.make(Zones.RES_HIGH, ring[(i + rotation) % 4]))
		var before := var_to_bytes([city.building.data, city.zone.data])
		var records := CityBuildings3D.collect(city)
		check_eq(records.size(), 2, "rotation %d retains adjacent identical lots" % rotation)
		check_eq(records[0].footprint, Rect2i(10, 10, 2, 2))
		check_eq(records[1].footprint, Rect2i(12, 10, 2, 2))
		check_eq(var_to_bytes([city.building.data, city.zone.data]), before)


func test_catalog_rejects_paths_nonfinite_transforms_and_wrong_footprints() -> void:
	var catalog := CityModelCatalog.new()
	check(catalog.valid_entry(_entry()))
	var invalid: Array[Dictionary] = [
		{"path": "res://elsewhere/112-blender.glb"}, {"path": CityModelCatalog.ROOT + "../112-blender.glb"},
		{"path": CityModelCatalog.ROOT + "113-blender.glb"}, {"code": 112.5}, {"code": -1},
		{"scale": 0}, {"scale": INF}, {"scale": "0.0625"}, {"pivot": [0, NAN, 0]},
		{"pivot": [0, 0]}, {"height": -1}, {"height": INF}, {"yaw": NAN},
		{"footprint": [2, 2]}, {"footprint": [1.5, 1]}, {"footprint": [true, 1]},
	]
	for change: Dictionary in invalid:
		var entry := _entry()
		entry.merge(change, true)
		check(not catalog.valid_entry(entry), "reject %s" % str(change))


func test_manifest_duplicates_are_rejected_and_reload_clears_state() -> void:
	var catalog := CityModelCatalog.new()
	var path := "user://test_city_3d_catalog.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"entries": [_entry(), _entry(), _entry()]}))
	file.close()
	check_eq(catalog.load_manifest(path), OK)
	check(not catalog.entries.has(Buildings.RES_1X1_FIRST), "no ambiguous duplicate identity is admitted")
	check_ge(catalog.errors.size(), 2)
	check_eq(catalog.load_manifest("user://absent_city_3d_catalog.json"), ERR_FILE_NOT_FOUND)
	check(catalog.entries.is_empty() and catalog.errors.is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_full_runtime_catalog_contains_every_authored_model() -> void:
	var catalog := CityModelCatalog.new()
	check_eq(catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json"), OK)
	check_eq(catalog.errors, PackedStringArray())
	check_eq(catalog.entries.size(), Buildings.COUNT - Buildings.RES_1X1_FIRST)
	for code: int in range(Buildings.RES_1X1_FIRST, Buildings.COUNT):
		check(catalog.entries.has(code), "model %d is shipped" % code)
		if catalog.entries.has(code):
			check(catalog.valid_entry(catalog.entries[code]))


func test_nested_import_colliders_cannot_intercept_city_queries() -> void:
	var wrapper := Node3D.new()
	var nested := Node3D.new()
	wrapper.add_child(nested)
	var shell := StaticBody3D.new()
	shell.collision_layer = 7
	shell.collision_mask = 7
	nested.add_child(shell)
	var area := Area3D.new()
	area.collision_layer = 3
	nested.add_child(area)
	CityModelCatalog.configure_physical_collisions(wrapper)
	check_eq(shell.collision_layer, 4)
	check_eq(shell.collision_mask, 0)
	check_eq(area.collision_layer, 4)
	check(not area.monitoring and not area.monitorable)
	wrapper.free()


func test_model_pivot_follows_yaw_and_scale() -> void:
	var catalog := CityModelCatalog.new()
	var entry := _entry()
	entry.scale = 2.0
	entry.yaw = 90.0
	entry.pivot = [1, 0, 0]
	catalog.entries[112] = entry
	var source := Node3D.new()
	var packed := PackedScene.new()
	check_eq(packed.pack(source), OK)
	source.free()
	catalog.scenes[112] = packed
	var wrapper := catalog.instantiate_model(112)
	var model: Node3D = wrapper.get_child(0)
	check((model.transform * Vector3(1, 0, 0)).is_equal_approx(Vector3.ZERO), "chosen model pivot sits at the lot center")
	wrapper.free()


func test_missing_models_still_have_one_canonical_query_proxy() -> void:
	var city := flat_city()
	city.stamp_building(10, 10, Buildings.RES_2X2_FIRST)
	var before := var_to_bytes([city.altitude.data, city.building.data, city.zone.data, city.funds, city.day])
	var layer := CityBuildings3D.new()
	layer.rebuild(city)
	check_eq(layer.get_child_count(), 1)
	check_eq(layer.missing.get(Buildings.RES_2X2_FIRST), 1)
	var model: Node3D = layer.get_child(0)
	var proxy: StaticBody3D = model.get_node("BuildingQuery")
	check_eq(proxy.get_meta("cell"), Vector2i(10, 10))
	check_eq(proxy.collision_layer, 2)
	check_eq(proxy.collision_mask, 0)
	check_eq(var_to_bytes([city.altitude.data, city.building.data, city.zone.data, city.funds, city.day]), before)
	layer.free()


func test_water_lots_and_queries_sit_above_the_water_surface() -> void:
	for water: int in [3, 6]:
		var city := flat_city()
		city.terrain.put(10, 10, Terrain.SURFACE)
		city.set_heights(10, 10, 2, water)
		city.stamp_building(10, 10, Buildings.PIER)
		var layer := CityBuildings3D.new()
		layer.rebuild(city)
		var model: Node3D = layer.get_child(0)
		check(is_equal_approx(model.position.y, water * CityGeometry3D.HEIGHT + 0.025), "water depth %d keeps the pier visible" % water)
		var proxy: StaticBody3D = model.get_node("BuildingQuery")
		check_eq(proxy.get_meta("cell"), Vector2i(10, 10))
		check(is_equal_approx(CityGeometry3D.ground_height(city, Vector2i(10, 10)), 2 * CityGeometry3D.HEIGHT), "seabed remains unchanged")
		layer.free()
