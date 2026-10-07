# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Exact catalog surface/LOD/shadow preservation and scene node reduction.
extends "res://tests/test_case.gd"
const Compiler := preload("res://scripts/view/city_runtime_mesh_compiler.gd")
func meshes(node: Node) -> Array:
	return node.find_children("*", "MeshInstance3D", true, false)
func signature(node: Node) -> Array:
	var result: Array = []
	for instance: MeshInstance3D in meshes(node):
		if instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
		for surface: int in instance.mesh.get_surface_count():
			var data: Dictionary = instance.mesh.get("_surfaces")[surface].duplicate()
			data.material = instance.get_active_material(surface)
			result.append(data)
	return result
func physics(node: Node) -> Dictionary:
	var result := {}
	for child: Node in node.find_children("*", "CollisionObject3D", true, false):
		result[str(node.get_path_to(child))] = [child.transform, child.collision_layer, child.collision_mask]
	for child: CollisionShape3D in node.find_children("*", "CollisionShape3D", true, false):
		result[str(node.get_path_to(child))] = [child.transform, child.shape]
	return result
func shadows(node: Node) -> Array:
	var result: Array = []
	for instance: MeshInstance3D in meshes(node):
		if instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
		if instance.mesh.shadow_mesh != null:
			result.append_array(instance.mesh.shadow_mesh.get("_surfaces"))
	return result
func same_members(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	var remaining := b.duplicate()
	for item: Variant in a:
		var index := remaining.find(item)
		if index < 0: return false
		remaining.remove_at(index)
	return true
func shadow_triangles(node: Node, proxies: bool) -> Dictionary:
	var result := {}
	for instance: MeshInstance3D in meshes(node):
		var mesh: Mesh = instance.mesh
		if proxies:
			if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
		for surface: int in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				for i: int in vertices.size(): indices.append(i)
			for i: int in range(0, indices.size(), 3):
				var triangle := PackedVector3Array([vertices[indices[i]], vertices[indices[i+1]], vertices[indices[i+2]]])
				result[triangle] = int(result.get(triangle, 0)) + 1
	return result
func bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for instance: MeshInstance3D in meshes(node):
		var box: AABB = instance.transform * instance.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
func _lod_indices(mesh: ArrayMesh, edge: float) -> PackedInt32Array:
	var data: Dictionary = mesh.get("_surfaces")[0]
	var lods: Array = data.get("lods", [])
	var result := PackedInt32Array()
	for i: int in range(0, lods.size(), 2):
		if is_equal_approx(float(lods[i]), edge):
			var bytes: PackedByteArray = lods[i+1]
			for j: int in range(0, bytes.size(), 2): result.append(bytes.decode_u16(j))
	return result
func _shadow_levels() -> void:
	var box := BoxMesh.new()
	var arrays := box.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count: int = arrays[Mesh.ARRAY_VERTEX].size()
	var a := ArrayMesh.new()
	var b := ArrayMesh.new()
	a.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {1.0: indices.slice(0, 18)})
	b.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {2.0: indices.slice(0, 6)})
	var combined := Compiler._shadow_mesh([{"mesh":a,"surface":0},{"mesh":b,"surface":0}])
	var expected_middle := indices.slice(0,18)
	var expected_far := indices.slice(0,18)
	for i: int in indices: expected_middle.append(i+count)
	for i: int in indices.slice(0,6): expected_far.append(i+count)
	check(_lod_indices(combined,1.0) == expected_middle, "shadowLOD keeps full second part until its own threshold")
	check(_lod_indices(combined,2.0) == expected_far, "shadowLOD concatenates both original simplified index lists with exact offsets")
	check(combined.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 2*count, "shadowLOD shares unchanged full-resolution vertices")
	var source := Node3D.new()
	for cull: int in [BaseMaterial3D.CULL_BACK,BaseMaterial3D.CULL_FRONT]:
		var child := MeshInstance3D.new()
		child.mesh = a
		var material := StandardMaterial3D.new()
		material.cull_mode = cull
		child.material_override = material
		source.add_child(child)
	var proxies := Compiler._shadow_proxies(source.get_children())
	check(proxies.size() == 2, "opposite face culling retains independent shadow groups")
	for i: int in proxies.size():
		check(proxies[i].mesh.surface_get_material(0).cull_mode == i, "shadow material preserves source face culling")
		check(proxies[i].cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and proxies[i].gi_mode == GeometryInstance3D.GI_MODE_DISABLED, "proxy contributes shadow only")
		proxies[i].free()
	source.get_child(0).material_override.grow = true
	check(Compiler._shadow_proxies(source.get_children()).is_empty(), "vertex displacement keeps original material-owned shadows")
	source.get_child(0).material_override.grow = false
	source.get_child(0).material_override.next_pass = StandardMaterial3D.new()
	check(Compiler._shadow_proxies(source.get_children()).is_empty(), "extra material passes retain original shadows")
	source.free()
func _synthetic() -> void:
	var source := Node3D.new()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().surface_get_arrays(0))
	var material := StandardMaterial3D.new()
	mesh.surface_set_material(0, material)
	for i: int in 4:
		var child := MeshInstance3D.new()
		child.name = "Part%d" % i
		child.mesh = mesh
		child.position = Vector3(2,3,4) if i < 2 else Vector3(-3,1,2)
		source.add_child(child)
	var original_bounds := bounds(source)
	var original_signatures := signature(source)
	var packed := Compiler.compile(source)
	var compiled := packed.instantiate()
	check(meshes(compiled).size() == 2, "different local transforms remain distinct compiled groups")
	check(bounds(compiled).is_equal_approx(original_bounds), "translated groups preserve exact union bounds")
	check(same_members(signature(compiled), original_signatures), "translated groups do not bake or change source arrays")
	for instance: MeshInstance3D in meshes(compiled):
		check(instance.get_meta("source_node_names").size() == instance.mesh.get_surface_count(), "source part names retained per surface")
	compiled.free()
	source.free()
	var excluded := Node3D.new()
	for i: int in 4:
		var child := MeshInstance3D.new()
		child.mesh = mesh
		if i < 2:
			var body := StaticBody3D.new()
			child.add_child(body)
		else:
			child.visibility_range_end = 20
		excluded.add_child(child)
	packed = Compiler.compile(excluded)
	compiled = packed.instantiate()
	check(meshes(compiled).size() == 4, "physical parent meshes and manual distance LOD remain unchanged")
	check(compiled.find_children("*", "StaticBody3D", true, false).size() == 2, "physical child hierarchy retained")
	compiled.free()
	excluded.free()
	var animated := Node3D.new()
	animated.add_child(AnimationPlayer.new())
	check(Compiler.compile(animated) == null, "animated scenes preserve original node paths via fallback")
	animated.free()
	var scripted := Node3D.new()
	var behavior := GDScript.new()
	behavior.source_code = "extends Node3D\n"
	behavior.reload()
	scripted.set_script(behavior)
	check(Compiler.compile(scripted) == null, "scripted scenes preserve original node paths via fallback")
	scripted.free()
func test_compiled_models_preserve_surfaces_lods_and_shadows() -> void:
	_synthetic()
	_shadow_levels()
	var catalog := CityModelCatalog.new()
	# This exercises the compiler's own output, which shares the import's exact
	# material and shape resources. Scenes restored from the on-disk compiled
	# cache carry equal copies instead; test_compiled_model_cache covers them.
	catalog.compiled_cache_enabled = false
	check(catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json") == OK, "catalog loads")
	var original_count := 0
	var runtime_count := 0
	for code: int in catalog.entries:
		var original: Node3D = load(catalog.entries[code].path).instantiate()
		CityModelCatalog.configure_physical_collisions(original)
		var wrapper := catalog.instantiate_model(code)
		var actual: Node3D = wrapper.get_child(0)
		original_count += meshes(original).size()
		runtime_count += meshes(actual).size()
		check(same_members(signature(original), signature(actual)), "model %d exact raw vertex/index/normal/UV/color/LOD/material surfaces" % code)
		check(same_members(shadows(original), shadows(actual)), "model %d exact shadow surfaces and shadow LODs" % code)
		check(bounds(original).is_equal_approx(bounds(actual)), "model %d compiled culling bound is original union" % code)
		check(shadow_triangles(original, false) == shadow_triangles(actual, true), "model %d opaque shadow proxy preserves every original oriented triangle" % code)
		check(physics(original) == physics(actual), "model %d imported physical hierarchy, transforms and shared shapes" % code)
		var again := catalog.instantiate_model(code)
		var first_meshes := meshes(actual)
		var second_meshes := meshes(again)
		check(first_meshes.size() == second_meshes.size() and first_meshes[0].mesh == second_meshes[0].mesh, "model %d compiled mesh cache shared across lots" % code)
		again.free()
		wrapper.free()
		original.free()
	catalog.runtime_compilation_enabled = false
	var uncompiled := catalog.instantiate_model(112)
	check(meshes(uncompiled).size() > 1, "benchmark switch retains uncompiled source model")
	uncompiled.free()
	check(catalog.load_manifest("user://missing-runtime-catalog.json") == ERR_FILE_NOT_FOUND and catalog.runtime_scenes.is_empty(), "catalog reload invalidates compiled cache")
	print("Catalog mesh instances: %d -> %d" % [original_count, runtime_count])
	check(original_count > 2000 and runtime_count < 400, "catalog compilation cuts mesh node inventory by at least 80 percent")
