# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The compiled-model cache fills while it is night. A model compiled before
## any of its own materials was lit is stored in its day state; a model whose
## materials are lit is never stored until day restores them.
extends "res://tests/test_case.gd"

const Catalog := preload("res://scripts/view/city_model_catalog.gd")

class StubView extends Node:
	var world := Node3D.new()
	func exploration_camera() -> Camera3D: return null


static func _materials(node: Node, out: Array[BaseMaterial3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		for surface: int in (node as MeshInstance3D).mesh.get_surface_count():
			var material := (node as MeshInstance3D).get_active_material(surface) as BaseMaterial3D
			if material != null and not out.has(material): out.append(material)
	for child: Node in node.get_children(): _materials(child, out)


## Geometry and every material value night mode can change, per surface.
static func _describe(scene: PackedScene) -> PackedByteArray:
	var model := scene.instantiate()
	var lines: Array = []
	var stack: Array[Node] = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if not node is MeshInstance3D or (node as MeshInstance3D).mesh == null: continue
		for surface: int in (node as MeshInstance3D).mesh.get_surface_count():
			var material := (node as MeshInstance3D).get_active_material(surface) as BaseMaterial3D
			lines.append([str(node.name), var_to_bytes((node as MeshInstance3D).mesh.surface_get_arrays(surface)).size()])
			if material == null: continue
			lines.append([material.resource_name, material.albedo_color, material.emission_enabled, material.emission, material.emission_energy_multiplier,
				material.emission_operator, material.emission_texture == null, material.uv1_triplanar, material.uv1_world_triplanar, material.uv1_scale, material.uv1_triplanar_sharpness])
	model.free()
	return var_to_bytes(lines)


func _catalog(cache: bool = true) -> Catalog:
	var catalog := Catalog.new()
	catalog.compiled_cache_enabled = cache
	check_eq(catalog.load_manifest(Catalog.ROOT + "catalog.json"), OK, "catalog loads")
	return catalog


func _forget(catalog: Catalog, code: int) -> String:
	var path: String = catalog.compiled_cache_path(code, true)
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return path


func test_models_compiled_at_night_are_cached_in_their_day_state() -> void:
	var plain := _catalog(false)
	# A model with windows or neon: night mode lights its materials.
	var code := -1
	var codes: Array = plain.entries.keys().filter(func(value: int) -> bool: return not Buildings.is_agricultural(value))
	codes.sort()
	for candidate: int in codes:
		var model := plain.instantiate_model(candidate)
		var materials: Array[BaseMaterial3D] = []
		_materials(model, materials)
		model.free()
		for material: BaseMaterial3D in materials:
			if CityNightMode.role_for(material.resource_name) != CityNightMode.Role.NONE: code = candidate
		if code >= 0: break
	check(code >= 0, "a model with night-lit materials exists")
	if code < 0: return
	var day: PackedByteArray = _describe(plain.runtime_scenes[[code, true]])

	var view := StubView.new()
	view.add_child(view.world)
	root.add_child(view)
	var night := CityNightMode.new()
	night.bind(view)
	view.add_child(night)
	var glass := StandardMaterial3D.new()
	glass.resource_name = "glass"
	var pane := MeshInstance3D.new()
	pane.mesh = QuadMesh.new()
	pane.mesh.surface_set_material(0, glass)
	view.world.add_child(pane)
	night.set_enabled(true, true)
	check(CityNightMode.materials_modified() and CityNightMode.lights(glass), "another building's windows are lit")

	# 1. Night elsewhere: this model's own materials are still in day state.
	var writer := _catalog()
	var path := _forget(writer, code)
	var model := writer.instantiate_model(code)
	check(model != null, "the model instantiates at night")
	check(FileAccess.file_exists(path), "a model compiled at night is written to the cache")
	var reader := _catalog()
	var cached := reader.instantiate_model(code)
	check_eq(reader.compiled_cache_hits, 1, "the next catalog reads it back")
	check(_describe(reader.runtime_scenes[[code, true]]) == day, "the cached model equals the day compilation, materials included")
	if cached != null: cached.free()

	# 2. The model stands in the city and its windows are lit.
	view.world.add_child(model)
	night._collect(view.world)
	var own: Array[BaseMaterial3D] = []
	_materials(model, own)
	var lit := 0
	for material: BaseMaterial3D in own:
		if CityNightMode.lights(material): lit += 1
	check(lit > 0, "the model's own materials are lit once it stands in the city (%d)" % lit)
	var second := _catalog()
	_forget(second, code)
	var again := second.instantiate_model(code)
	check(again != null, "the lit model still instantiates")
	if again != null: again.free()
	check(not FileAccess.file_exists(path), "a model with lit materials is never written")

	# 3. Day restores the materials; the cache accepts the model again.
	night.set_enabled(false, true)
	check(not CityNightMode.materials_modified() and not CityNightMode.lights(glass), "day restores every material")
	var third := _catalog()
	_forget(third, code)
	var restored := third.instantiate_model(code)
	if restored != null: restored.free()
	check(FileAccess.file_exists(path), "the model is written once it is day again")
	var last := _catalog()
	var from_cache := last.instantiate_model(code)
	if from_cache != null: from_cache.free()
	check(_describe(last.runtime_scenes[[code, true]]) == day, "and it equals the day compilation")
	view.free()
