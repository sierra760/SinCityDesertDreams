# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const Catalog := preload("res://scripts/traffic/city_traffic_catalog.gd")

func test_vehicle_inventory_and_drive_domains() -> void:
	check_eq(Catalog.vehicle_kinds().size(), 18)
	for kind in Catalog.vehicle_kinds():
		check_eq(Catalog.is_drivable(kind), kind != &"plane", String(kind))
		check(Catalog.domain(kind) in [&"road", &"rail", &"water", &"air"])
		check(not Catalog.display_name(kind).is_empty())
	check(not Catalog.is_drivable(&"unknown"))
	check(Catalog.mesh_for(&"unknown") == null)
	check_eq(Catalog.domain(&"train"), &"rail")
	check_eq(Catalog.domain(&"ship"), &"water")
	check_eq(Catalog.domain(&"helicopter"), &"air")

func test_near_and_far_models_use_tile_units_and_shared_cache() -> void:
	for kind in Catalog.vehicle_kinds():
		var near := Catalog.mesh_for(kind)
		var far := Catalog.mesh_for(kind, 0, true)
		check(near != null and far != null, String(kind))
		if near == null or far == null:
			continue
		check(near == Catalog.mesh_for(kind), "cached identity")
		check(near.get_surface_count() <= 10, "bounded material surfaces")
		check(near.get_aabb().size.is_equal_approx(Catalog.dimensions(kind)), "manifest matches transformed mesh: " + String(kind))
		check(near.get_aabb().size.length() < 1.2, "tile units: " + String(kind))
		check(_triangles(far) < _triangles(near), "far reduces triangles: " + String(kind))
		var visual := Catalog.make_visual(kind)
		check_eq(visual.get_child_count(), 1)
		check((visual.get_child(0) as MeshInstance3D).mesh == near)
		visual.free()

func test_pedestrian_variety_and_instanced_gait() -> void:
	check_ge(Catalog.pedestrian_variants(), 12)
	var seen: Array[Mesh] = []
	for variant in Catalog.pedestrian_variants():
		var near := Catalog.mesh_for(&"pedestrian", variant)
		var far := Catalog.mesh_for(&"pedestrian", variant, true)
		check(near != null and far != null)
		if near == null or far == null:
			continue
		check(not seen.has(near))
		seen.append(near)
		check(near.get_aabb().size.y > .09 and near.get_aabb().size.y < .14)
		check(absf(near.get_aabb().position.y) < .001)
		check(_triangles(far) < _triangles(near))
		for surface in near.get_surface_count():
			check(near.surface_get_material(surface) is ShaderMaterial)
	check(Catalog.mesh_for(&"pedestrian", 16) == Catalog.mesh_for(&"pedestrian", 0))

func test_transit_kit_and_passenger_cabin_scale() -> void:
	for kind in Catalog.TRANSIT_PARTS:
		check(Catalog.mesh_for(kind) != null, String(kind))
		check(not Catalog.is_drivable(kind))
	var cabin := Catalog.mesh_for(&"passenger_carriage")
	check(absf(cabin.get_aabb().size.x - .24) < .00001)
	check(absf(cabin.get_aabb().size.z - .625) < .00001)
	check(Catalog.dimensions(&"passenger_door").y < .18)

func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		total += indices.size() / 3 if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total
