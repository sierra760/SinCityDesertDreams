# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Validated runtime catalog for the authored Blender building models.
class_name CityModelCatalog
extends RefCounted

const ROOT := "res://assets/desert-dreams-3d/"
const SHELL_LAYER := 4
const RuntimeCompiler := preload("res://scripts/view/city_runtime_mesh_compiler.gd")
## Switchable for benchmark comparison; never rewrites authored source scenes.
var runtime_compilation_enabled := true
var runtime_scenes: Dictionary = {}
## Compiled scenes persist under compiled_cache_dir() keyed by model code, shadow mode, the
## catalog's source GLB hash, the compiler version and the engine version. A hit
## skips loading and compiling the source model; a miss or damaged file
## compiles the model and rewrites the entry. Disabled caches never read or write.
## Desktop location. Mobile keeps this regenerable cache out of user:// (iOS
## Documents is user-visible and backed up) in the OS cache directory instead.
const COMPILED_CACHE_DIR := "user://compiled-models"
var compiled_cache_enabled := true
var compiled_cache_hits := 0
var compiled_cache_misses := 0
var entries: Dictionary = {}
## Advances whenever load_manifest replaces the entries; consumers that derive
## presentation from entry dimensions compare it instead of rehashing entries.
var revision := 0
var scenes: Dictionary = {}
var errors: PackedStringArray = []


## Validate the model identity, transform and lot dimensions before loading.
func valid_entry(entry: Dictionary) -> bool:
	if not finite_number(entry.get("code")):
		return false
	var code := int(entry.code)
	if float(code) != float(entry.code) or code < Buildings.RES_1X1_FIRST or code >= Buildings.COUNT:
		return false
	if entry.get("path", "") != ROOT + "%d-blender.glb" % code:
		return false
	if not finite_number(entry.get("scale")) or float(entry.scale) <= 0.0:
		return false
	var footprint: Variant = entry.get("footprint")
	if not footprint is Array or footprint.size() != 2:
		return false
	for dimension: Variant in footprint:
		if not finite_number(dimension) or float(dimension) != floorf(float(dimension)):
			return false
	if Vector2i(int(footprint[0]), int(footprint[1])) != Buildings.size(code):
		return false
	var pivot: Variant = entry.get("pivot", [0, 0, 0])
	if not pivot is Array or pivot.size() != 3:
		return false
	for value: Variant in pivot:
		if not finite_number(value):
			return false
	if not finite_number(entry.get("height")) or float(entry.height) <= 0.0:
		return false
	return finite_number(entry.get("yaw", 0))


## Load valid entries; diagnostics retain rejected or unavailable models.
func load_manifest(path: String) -> Error:
	revision += 1
	entries.clear()
	scenes.clear()
	runtime_scenes.clear()
	errors.clear()
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not parsed.get("entries") is Array:
		return ERR_PARSE_ERROR
	var seen: Dictionary = {}
	for entry: Variant in parsed.entries:
		if not entry is Dictionary or not valid_entry(entry):
			errors.append("Invalid model entry")
			continue
		var code := int(entry.code)
		if seen.has(code):
			entries.erase(code)
			errors.append("Duplicate model code %d" % code)
			continue
		seen[code] = true
		if not ResourceLoader.exists(str(entry.path)):
			errors.append("Missing model %d" % code)
			continue
		entries[code] = entry.duplicate(true)
	return OK


## Instantiate a transformed model with isolated exterior collision shells.
func instantiate_model(code: int) -> Node3D:
	if not entries.has(code):
		return null
	var scene: PackedScene = null
	if runtime_compilation_enabled:
		var cache_key: Array = [code, true]
		if not runtime_scenes.has(cache_key):
			var compiled: PackedScene = _load_compiled(code, true)
			if compiled != null:
				compiled_cache_hits += 1
			else:
				var source := _source_scene(code)
				if source == null:
					return null
				var original: Node = source.instantiate()
				compiled = RuntimeCompiler.compile(original, true) if original is Node3D else null
				original.free()
				if compiled != null:
					compiled_cache_misses += 1
					_store_compiled(code, true, compiled)
			runtime_scenes[cache_key] = compiled
		if runtime_scenes[cache_key] is PackedScene:
			scene = runtime_scenes[cache_key]
	if scene == null:
		scene = _source_scene(code)
		if scene == null:
			return null
	var model: Node = scene.instantiate()
	if not model is Node3D:
		model.free()
		return null
	configure_physical_collisions(model)
	var wrapper := Node3D.new()
	wrapper.add_child(model)
	var entry: Dictionary = entries[code]
	model.scale = Vector3.ONE * float(entry.scale)
	model.rotation.y = deg_to_rad(float(entry.get("yaw", 0.0)))
	var pivot: Array = entry.get("pivot", [0, 0, 0])
	# A pivot is expressed in model space, so its offset follows model yaw.
	model.position = -(model.basis * Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2])))
	return wrapper


## The imported source model, loaded once per catalog; null when unusable.
func _source_scene(code: int) -> PackedScene:
	if not scenes.has(code):
		scenes[code] = load(str(entries[code].path))
	return scenes[code] if scenes[code] is PackedScene else null


## Directory holding compiled scenes on this platform.
static func compiled_cache_dir() -> String:
	return cache_dir_for(OS.has_feature("ios") or OS.has_feature("android"), OS.get_cache_dir())


## Mobile uses the OS cache directory when it is available; desktop, and
## mobile without one, use user://compiled-models.
static func cache_dir_for(mobile: bool, os_cache_dir: String) -> String:
	if mobile and not os_cache_dir.is_empty():
		return os_cache_dir.path_join("compiled-models")
	return COMPILED_CACHE_DIR


func compiled_cache_path(code: int, shadows: bool) -> String:
	var entry: Dictionary = entries[code]
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(("%s|%s|%d|%s" % [str(entry.get("glb_sha256", "")), str(entry.get("path", "")),
		RuntimeCompiler.VERSION, Engine.get_version_info().string]).to_utf8_buffer())
	return "%s/%d-%s-%s.scn" % [compiled_cache_dir(), code, "s" if shadows else "n", context.finish().hex_encode().substr(0, 16)]


func _load_compiled(code: int, shadows: bool) -> PackedScene:
	if not compiled_cache_enabled: return null
	var path := compiled_cache_path(code, shadows)
	if not FileAccess.file_exists(path): return null
	# Only a binary resource header is handed to the loader; anything else is a
	# damaged entry and is dropped quietly so the model compiles as usual.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	var header := file.get_buffer(4)
	file.close()
	if header.get_string_from_ascii() != "RSRC":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return null
	var loaded: Variant = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	return loaded if loaded is PackedScene else null


func _store_compiled(code: int, shadows: bool, compiled: PackedScene) -> void:
	if not compiled_cache_enabled: return
	var path := compiled_cache_path(code, shadows)
	var cache_dir := compiled_cache_dir()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir)) != OK: return
	# Stale entries of this code and mode (older hashes/versions) are replaced.
	var directory := DirAccess.open(cache_dir)
	if directory != null:
		var prefix := "%d-%s-" % [code, "s" if shadows else "n"]
		for file: String in directory.get_files():
			if file.begins_with(prefix) and file != path.get_file():
				directory.remove(file)
	ResourceSaver.save(compiled, path)


## Imported shells cannot intercept terrain or building queries.
static func configure_physical_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		node.collision_layer = SHELL_LAYER
		node.collision_mask = 0
		if node is Area3D:
			node.monitoring = false
			node.monitorable = false
	for child: Node in node.get_children():
		configure_physical_collisions(child)



static func finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
