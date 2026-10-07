# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Compiled model scenes cached on disk must instantiate the same node tree,
## geometry, materials and collision as a fresh compilation, and a cache hit
## must not touch the source model or the compiler.
extends "res://tests/test_case.gd"

const Catalog := preload("res://scripts/view/city_model_catalog.gd")

func _describe(node: Node, out: Array) -> void:
	var line: Array = [node.name, node.get_class(), node.get_meta_list()]
	if node is Node3D: line.append(node.transform)
	if node is MeshInstance3D and node.mesh != null:
		line.append(node.cast_shadow)
		line.append(node.layers)
		line.append(node.mesh.get_surface_count())
		line.append(node.mesh.shadow_mesh != null)
		for surface: int in node.mesh.get_surface_count():
			line.append(var_to_bytes(node.mesh.surface_get_arrays(surface)))
			line.append(node.mesh.get("_surfaces")[surface].get("lods", []))
			var material: Material = node.get_active_material(surface)
			if material is BaseMaterial3D:
				line.append([material.albedo_color, material.roughness, material.metallic, material.cull_mode, material.transparency,
					material.albedo_texture.get_image().get_data() if material.albedo_texture != null and material.albedo_texture.get_image() != null else PackedByteArray()])
			else:
				line.append(material.get_class() if material != null else "")
	if node is CollisionShape3D and node.shape != null:
		line.append(node.shape.get_class())
		if node.shape is ConcavePolygonShape3D: line.append(node.shape.get_faces())
		if node.shape is BoxShape3D: line.append(node.shape.size)
	if node is CollisionObject3D: line.append([node.collision_layer, node.collision_mask])
	out.append(line)
	for child: Node in node.get_children(): _describe(child, out)

func _tree(scene: PackedScene) -> PackedByteArray:
	var root := scene.instantiate()
	var lines: Array = []
	_describe(root, lines)
	root.free()
	return var_to_bytes(lines)

func test_cached_scene_equals_fresh_compilation_and_skips_the_compiler() -> void:
	var fresh := Catalog.new()
	fresh.compiled_cache_enabled = false
	check_eq(fresh.load_manifest(Catalog.ROOT + "catalog.json"), OK, "catalog loads")
	var codes: Array = fresh.entries.keys()
	codes.sort()
	var sample: Array = [codes[0], codes[codes.size() / 2], codes[-1]]
	var writer := Catalog.new()
	writer.load_manifest(Catalog.ROOT + "catalog.json")
	for code: int in sample:
		var path: String = writer.compiled_cache_path(code, true)
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		var model := writer.instantiate_model(code)
		check(model != null, "model %d instantiates while writing the cache" % code)
		if model != null: model.free()
		check(FileAccess.file_exists(path), "compiling model %d wrote its cache entry" % code)
	check_eq(writer.compiled_cache_misses, sample.size(), "every sampled model compiled once")
	check_eq(writer.compiled_cache_hits, 0, "a cold cache has no hits")
	var reader := Catalog.new()
	reader.load_manifest(Catalog.ROOT + "catalog.json")
	for code: int in sample:
		var model := reader.instantiate_model(code)
		check(model != null, "model %d instantiates from the cache" % code)
		if model != null: model.free()
		check(not reader.scenes.has(code), "a cache hit never loads the source model %d" % code)
		var cached: PackedScene = reader.runtime_scenes[[code, true]]
		var original: Node = fresh._source_scene(code).instantiate()
		var compiled: PackedScene = Catalog.RuntimeCompiler.compile(original, true)
		original.free()
		check(cached != null and compiled != null, "both scenes exist for %d" % code)
		if cached != null and compiled != null:
			check(_tree(cached) == _tree(compiled), "cached model %d reproduces the fresh compilation tree, geometry, materials and collision" % code)
	check_eq(reader.compiled_cache_hits, sample.size(), "warm cache serves every sampled model")
	check_eq(reader.compiled_cache_misses, 0, "warm cache compiles nothing")

func test_damaged_or_stale_entries_fall_back_to_compilation() -> void:
	var catalog := Catalog.new()
	catalog.load_manifest(Catalog.ROOT + "catalog.json")
	var code: int = catalog.entries.keys()[0]
	var path := catalog.compiled_cache_path(code, true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Catalog.COMPILED_CACHE_DIR))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("not a scene")
	file.close()
	var stale := "%s/%d-s-%s.scn" % [Catalog.COMPILED_CACHE_DIR, code, "0000000000000000"]
	var stale_file := FileAccess.open(stale, FileAccess.WRITE)
	stale_file.store_string("old")
	stale_file.close()
	var model := catalog.instantiate_model(code)
	check(model != null, "a damaged cache entry still yields a model")
	if model != null: model.free()
	check_eq(catalog.compiled_cache_misses, 1, "damaged entry counts as a miss and recompiles")
	check(not FileAccess.file_exists(stale), "stale entries for the same code and mode are removed")
	var reloaded: Variant = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	check(reloaded is PackedScene, "the damaged entry was rewritten with a valid scene")
	var disabled := Catalog.new()
	disabled.compiled_cache_enabled = false
	disabled.load_manifest(Catalog.ROOT + "catalog.json")
	var other := disabled.instantiate_model(code)
	if other != null: other.free()
	check_eq(disabled.compiled_cache_hits, 0, "a disabled cache never reads entries")

func test_cache_key_tracks_source_hash_and_versions() -> void:
	var catalog := Catalog.new()
	catalog.load_manifest(Catalog.ROOT + "catalog.json")
	var code: int = catalog.entries.keys()[0]
	var before := catalog.compiled_cache_path(code, true)
	check_ne(catalog.compiled_cache_path(code, false), before, "shadow mode is part of the key")
	catalog.entries[code]["glb_sha256"] = "changed"
	check_ne(catalog.compiled_cache_path(code, true), before, "a different source hash changes the key")
	check(before.begins_with(Catalog.COMPILED_CACHE_DIR + "/%d-s-" % code), "entries are grouped by code and mode")


## Desktop keeps user://; iOS/Android keep the regenerable cache out of the
## user-visible, backed-up user:// (Documents) in the OS cache directory.
func test_mobile_cache_lives_in_the_os_cache_directory() -> void:
	check_eq(Catalog.cache_dir_for(false, "/tmp/caches"), Catalog.COMPILED_CACHE_DIR, "desktop location is unchanged")
	check_eq(Catalog.cache_dir_for(true, "/var/mobile/App/Library/Caches"), "/var/mobile/App/Library/Caches/compiled-models", "mobile uses Library/Caches")
	check_eq(Catalog.cache_dir_for(true, ""), Catalog.COMPILED_CACHE_DIR, "an unavailable cache directory keeps the existing location")
	if not OS.has_feature("ios") and not OS.has_feature("android"):
		check_eq(Catalog.compiled_cache_dir(), Catalog.COMPILED_CACHE_DIR, "this desktop run uses user://")
