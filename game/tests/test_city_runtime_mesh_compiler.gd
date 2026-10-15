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
## Include opaque proxies and retained direct casters (for example glazing).
## Compiled visible surfaces have shadows OFF and must not be counted twice.
func shadow_triangles(node: Node) -> Dictionary:
	var result := {}
	for instance: MeshInstance3D in meshes(node):
		if instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: continue
		var mesh: Mesh = instance.mesh
		var at := instance.transform
		var ancestor := instance.get_parent()
		while ancestor != node and ancestor != null:
			if ancestor is Node3D: at = ancestor.transform * at
			ancestor = ancestor.get_parent()
		for surface: int in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				for i: int in vertices.size(): indices.append(i)
			for i: int in range(0, indices.size(), 3):
				var triangle := PackedVector3Array([at * vertices[indices[i]], at * vertices[indices[i+1]], at * vertices[indices[i+2]]])
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
		check(shadow_triangles(original) == shadow_triangles(actual), "model %d all shadow casters preserve every original oriented triangle" % code)
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


func test_mixed_opaque_proxy_and_transparent_fallback_shadow_geometry() -> void:
	var source := Node3D.new()
	for i: int in 3:
		var instance := MeshInstance3D.new()
		instance.name = "Glass" if i == 2 else "Opaque%d" % i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,BoxMesh.new().surface_get_arrays(0))
		var material := StandardMaterial3D.new()
		if i == 2:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color(1,1,1,.4)
			instance.position.x = 2
		mesh.surface_set_material(0,material)
		instance.mesh = mesh
		source.add_child(instance)
	var expected := shadow_triangles(source)
	var glass_mesh: Mesh = source.get_node("Glass").mesh
	var packed := Compiler.compile(source,true)
	var actual := packed.instantiate()
	check_eq(shadow_triangles(actual),expected,"opaque proxies plus unchanged transparent direct casters")
	var glass := actual.get_node("Glass") as MeshInstance3D
	check(glass.mesh == glass_mesh,"unsupported glazing retains the exact shared mesh")
	check_eq(glass.cast_shadow,GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	check_ne(shadow_triangles(actual),expected,"disabled fallback is detected")
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var proxy: MeshInstance3D
	for instance: MeshInstance3D in meshes(actual):
		if instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: proxy = instance; break
	check(proxy != null,"opaque geometry is compiled to a shadow proxy")
	if proxy != null:
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		check_ne(shadow_triangles(actual),expected,"missing opaque proxy is detected")
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	actual.remove_child(glass);glass.free()
	check_ne(shadow_triangles(actual),expected,"deleted fallback is detected")
	source.free();actual.free()

func test_generated_parcel_cells_are_dispatched_outside_whole_lot_compilation() -> void:
	var city := flat_city()
	var fixture := preload("res://tests/helpers/agricultural_parcel_fixture.gd")
	var record := fixture.record(1,fixture.ring(),&"grain",&"active")
	fixture.zone(city,record.members)
	check_eq(city.agricultural_parcels.put(city,record),OK)
	check(CityBuildings3D.collect(city).is_empty(),"full collection excludes cell proxies")
	check(CityBuildings3D.collect_regions(city,[Rect2i(20,20,3,3)]).is_empty(),"regional collection excludes cell proxies")
