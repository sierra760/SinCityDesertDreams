# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Regional ownership must not fragment exact-resource instancing across chunks.
extends "res://tests/test_case.gd"
func test_equivalent_bridge_parts_share_resources_across_region_boundary() -> void:
	var city := flat_city()
	for x: int in range(14,18):
		city.building.put(x,8,87)
		city.flags.put(x,8,RotationMapper.AXIS_FLAG)
		city.terrain.put(x,8,Terrain.SURFACE)
		city.set_heights(x,8,1,3)
	var layer := CityNetworks3D.new()
	layer.update_regions(city,[])
	var left: CityNetworks3D = layer._regions[Vector2i.ZERO]
	var right: CityNetworks3D = layer._regions[Vector2i(16,0)]
	var compared := 0
	for a: Node in left.get_children():
		if not a is MeshInstance3D or not a.mesh is BoxMesh: continue
		for b: Node in right.get_children():
			if not b is MeshInstance3D or not b.mesh is BoxMesh: continue
			if a.mesh.size != b.mesh.size or a.material_override.albedo_color != b.material_override.albedo_color: continue
			compared += 1
			check(a.mesh == b.mesh,"identical structural box meshes stay shared across a 16-cell ownership boundary")
			check(a.material_override == b.material_override,"identical structural materials stay shared across a 16-cell ownership boundary")
			break
	check(compared > 0,"actual bridge meshes on both sides exercise resource sharing")
	layer.free()

## Replaced regions release box meshes no live region uses; live sizes keep
## one shared resource.
func test_replaced_regions_release_unused_box_meshes() -> void:
	var city := flat_city()
	for x: int in range(14,18):
		city.building.put(x,8,87)
		city.flags.put(x,8,RotationMapper.AXIS_FLAG)
		city.terrain.put(x,8,Terrain.SURFACE)
		city.set_heights(x,8,1,3)
	var layer := CityNetworks3D.new()
	layer.update_regions(city,[])
	var shared: Dictionary = layer._box_meshes.duplicate()
	check(not shared.is_empty(),"bridge emits structural boxes")
	var seen: Dictionary = shared.duplicate()
	for water: int in [4,5,6,7,8,3]:
		for x: int in range(14,18): city.set_heights(x,8,1,water)
		layer.update_regions(city,[Rect2i(0,0,16,16)])
		var live: Dictionary = {}
		for part: CityNetworks3D in layer._regions.values():
			for node: Node in part.get_children():
				if node is MeshInstance3D and node.mesh is BoxMesh: live[node.mesh.size] = node.mesh
		for size: Vector3 in layer._box_meshes: check(live.has(size),"every cached box size belongs to a live region")
		for size: Vector3 in live: check(layer._box_meshes.get(size) == live[size],"live boxes keep their shared resource")
		seen.merge(live)
	check(seen.size() > layer._box_meshes.size(),"edits produced sizes that were later released")
	layer.free()
