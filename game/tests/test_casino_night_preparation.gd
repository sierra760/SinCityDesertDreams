# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The first night must not rasterize every resort's roofs on the main thread.
extends "res://tests/test_case.gd"

const Edges := preload("res://scripts/view/casino_neon_edges.gd")
const CODES := [126,251,252,253,254,256,257,258,259,260,261,262,263,264,265]

func test_first_use_is_prepared_and_matches_live_geometry() -> void:
	var catalog := CityModelCatalog.new()
	catalog.compiled_cache_enabled = false
	check_eq(catalog.load_manifest(CityModelCatalog.ROOT+"catalog.json"),OK)
	var models: Array[Node3D] = []
	for code: int in CODES:
		var wrapper := catalog.instantiate_model(code)
		root.add_child(wrapper)
		models.append(wrapper)
	Edges.clear_cache()
	var prepared: Array[Dictionary] = []
	var start := Time.get_ticks_usec()
	for i: int in CODES.size(): prepared.append(Edges.of(CODES[i],models[i].get_child(0)))
	var elapsed := (Time.get_ticks_usec()-start)/1000.0
	print("FIRST_NIGHT_EDGES_MS: ",elapsed)
	check_lt(elapsed,500.0,"all fifteen casinos prepare without the multi-second first-night roof scan")
	for i: int in CODES.size():
		var live := Edges._extract(models[i].get_child(0))
		check_eq(prepared[i],live,"prepared rooflines, lettering gaps and roof anchors match the actual model %d"%CODES[i])
		models[i].free()
	Edges.clear_cache()

func test_prepared_geometry_is_current() -> void:
	var prepared: Resource = load("res://assets/desert-dreams-3d/casino-night-geometry.res")
	check_eq(prepared.get_meta("extractor_sha256"),FileAccess.get_sha256("res://scripts/view/casino_neon_edges.gd"),"regenerate after changing the lighting extractor")

func _box(size: Vector3) -> Node3D:
	var model := Node3D.new()
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var wall := StandardMaterial3D.new()
	wall.resource_name = "cream"
	mesh.material = wall
	instance.mesh = mesh
	model.add_child(instance)
	root.add_child(model)
	return model

func test_custom_or_changed_models_fall_back_without_sharing_by_code() -> void:
	Edges.clear_cache()
	var tall := _box(Vector3(4,6,8))
	var low := _box(Vector3(10,2,6))
	# A changed source under a known code must never borrow the shipped roof.
	tall.set_meta("night_geometry_source","changed-source:2")
	var first := Edges.of(251,tall)
	check_eq(first.height,6.0,"changed model is measured")
	check_eq(first.base,-3.0)
	var second := Edges.of(251,low)
	check_eq(second.height,2.0,"an untagged model with the same code has its own geometry")
	check_eq(second.base,-1.0)
	check_eq(Edges.of(251,tall),first,"repeat lookup retains the correct model")
	tall.free()
	low.free()
	Edges.clear_cache()

func test_disk_cached_models_use_the_same_prepared_geometry() -> void:
	var writer := CityModelCatalog.new()
	check_eq(writer.load_manifest(CityModelCatalog.ROOT+"catalog.json"),OK)
	var first := writer.instantiate_model(251)
	root.add_child(first)
	var expected := Edges.of(251,first.get_child(0))
	var reader := CityModelCatalog.new()
	check_eq(reader.load_manifest(CityModelCatalog.ROOT+"catalog.json"),OK)
	var cached := reader.instantiate_model(251)
	root.add_child(cached)
	check_eq(reader.compiled_cache_hits,1,"the persistent compiled scene is used")
	check(not reader.scenes.has(251),"source scene was not loaded")
	Edges.clear_cache()
	var start := Time.get_ticks_usec()
	var actual := Edges.of(251,cached.get_child(0))
	check_lt((Time.get_ticks_usec()-start)/1000.0,100.0,"a disk-cache hit still uses prepared roof geometry")
	check_eq(actual,expected)
	first.free()
	cached.free()
	Edges.clear_cache()
