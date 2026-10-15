# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"


func test_all_sixteen_farm_models_are_loadable_and_collidable() -> void:
	var catalog := CityModelCatalog.new()
	catalog.runtime_compilation_enabled = false
	check_eq(catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json"), OK)
	var count := 0
	for code: int in range(Buildings.COUNT):
		if not Buildings.is_agricultural(code) or Buildings.is_agricultural_cell(code):
			continue
		count += 1
		check(catalog.entries.has(code), "Missing agricultural model %s" % Buildings.key(code))
		if not catalog.entries.has(code):
			continue
		var model := catalog.instantiate_model(code)
		check(model != null, "load %s" % Buildings.key(code))
		if model != null:
			check(_count_type(model, "MeshInstance3D") > 0, "visible farming geometry")
			check(_count_type(model, "StaticBody3D") > 0, "physical support and obstacles")
			check_eq(_count_type(model, "Skeleton3D"), 0, "static lot has no animals")
			model.free()
	check_eq(count, 16)


func _count_type(node: Node, type: String) -> int:
	var count := int(node.is_class(type))
	for child: Node in node.get_children():
		count += _count_type(child, type)
	return count


func test_farm_textures_are_embedded_and_repeat() -> void:
	for archetype: StringName in AgricultureParams.ROSTER:
		var path := CityModelCatalog.ROOT + "%d-blender.glb" % AgricultureParams.building_id(archetype)
		var packed := load(path) as PackedScene
		check(packed != null)
		if packed == null:
			continue
		var model := packed.instantiate()
		check(_check_textures(model) > 0, "real growing-lot materials have original textures")
		model.free()


func _check_textures(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and node.mesh != null:
		for surface: int in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null or material.albedo_texture == null:
				continue
			count += 1
			check(material.albedo_texture.is_built_in(), "farm texture must survive source-preserving sync without extracted PNGs")
			check(material.texture_repeat, "farm swatches use plain repeat")
	for child: Node in node.get_children():
		count += _check_textures(child)
	return count


func test_modular_kit_loads_embedded_resources_and_complete_collision_once() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/agriculture/parcel_modules.json"))
	check_eq(manifest.get("scale"), 1.0 / 16.0, "renderer alone applies tile scale")
	var modules: Dictionary = manifest.get("modules", {})
	check_eq(modules.size(), 12)
	for key: String in modules:
		var entry: Dictionary = modules[key]
		var path: String = entry.get("path", "")
		check(not path.is_empty(), key + " has a packaged path")
		if path.is_empty():
			continue
		check_eq(FileAccess.get_sha256(path), entry.get("model_sha256"), key + " exact model identity")
		var packed := ResourceLoader.load(path) as PackedScene
		check(packed != null, key + " imported PackedScene")
		if packed == null:
			continue
		check_eq(ResourceLoader.load(path), packed, key + " stable cached resource")
		check(ResourceLoader.get_resource_uid(path) > 0, key + " genuine importer UID")
		var model := packed.instantiate() as Node3D
		check(model != null)
		if model == null:
			continue
		check_eq(model.scale, Vector3.ONE, key + " import retains authored metres")
		check(_count_type(model, "MeshInstance3D") > 0, key + " visible geometry")
		check_eq(_count_type(model, "StaticBody3D"), 1, key + " complete envelope body")
		check(_check_textures(model) > 0, key + " embedded original surfaces")
		var shapes := model.find_children("*", "CollisionShape3D", true, false)
		check_eq(shapes.size(), 1, key + " envelope shape")
		if shapes.size() == 1:
			var shape_node := shapes[0] as CollisionShape3D
			var shape := shape_node.shape as ConcavePolygonShape3D
			check(shape != null, key + " imported closed triangle shell")
			if shape != null:
				var faces := shape.get_faces()
				check_eq(faces.size(), 36, key + " all six cuboid faces")
				var bounds := AABB(faces[0], Vector3.ZERO)
				for point: Vector3 in faces:
					bounds = bounds.expand(point)
				var expected: Array = entry.collision_bounds
				check(bounds.position.is_equal_approx(Vector3(expected[0], expected[1], expected[2])), key + " collision lower bound")
				check(bounds.end.is_equal_approx(Vector3(expected[3], expected[4], expected[5])), key + " collision upper bound")
		model.free()
