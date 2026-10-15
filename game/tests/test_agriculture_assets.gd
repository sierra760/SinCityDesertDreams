# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"


func test_all_sixteen_farm_models_are_loadable_and_collidable() -> void:
	var catalog := CityModelCatalog.new()
	catalog.runtime_compilation_enabled = false
	check_eq(catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json"), OK)
	var count := 0
	for code: int in range(Buildings.COUNT):
		if not Buildings.is_agricultural(code):
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
