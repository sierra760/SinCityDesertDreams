# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Close geometry remains byte-identical; far crowns use continuous coarse ribbons.
extends "res://tests/test_case.gd"
const Palm := preload("res://scripts/view/city_palm_3d.gd")
const BASE_HASHES := [
	"043e2a49b35f9926c473c1c681f0baf33ae272cf0df9e625e87be536a48e7688",
	"5899483d531e09ffcd5edb41686bf3bfcf9434f6cd9a6d65b1f67c47b375d6ef",
	"ea53e1703f79cea1da3a5d08437b1355afde529c469f266776ed710e94feea40",
	"901e840d3694c47b584c87893dc19548aa4fdf39d2c5117048e9ac848db5506c",
]
func test_close_and_far_palm_geometry() -> void:
	for variant: int in 4:
		var palm := Palm.create(0.7,0.18,variant)
		var mesh: ArrayMesh = palm.get_child(2).mesh
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		var arrays := mesh.surface_get_arrays(0)
		var near_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var identity := near_indices.size() == 480
		for index: int in near_indices.size(): identity = identity and near_indices[index] == index
		check(identity, "near index stream reproduces every original unindexed triangle in order")
		arrays[Mesh.ARRAY_INDEX] = null
		hash.update(var_to_bytes(arrays))
		check(hash.finish().hex_encode() == BASE_HASHES[variant], "variant%d complete close geometry/colors/normals unchanged" % variant)
		check(Palm.is_static_crown_material(mesh.surface_get_material(0)), "crown material batching contract unchanged")
		var lods: Array = mesh.get("_surfaces")[0].get("lods", [])
		check(lods.size() == 4, "variant%d has two automatic crown LODs" % variant)
		if lods.size() == 4:
			for level: int in 2:
				var bytes: PackedByteArray = lods[level*2+1]
				var indices := PackedInt32Array()
				for i: int in range(0,bytes.size(),2): indices.append(bytes.decode_u16(i))
				var segments := 3 if level == 0 else 2
				check(indices.size() == 8*segments*6, "coarse crown has 48 or 32 triangles")
				for leaf: int in 8:
					var first := leaf*segments*6
					var last := first+(segments-1)*6
					check(indices[first] == leaf*60 and indices[first+1] == leaf*60+1 and indices[last+2] == leaf*60+56 and indices[last+4] == leaf*60+58, "each ribbon retains its original root and tip")
					for segment: int in range(1,segments):
						var current := first+segment*6
						check(indices[current] == indices[current-6+2] and indices[current+1] == indices[current-6+4], "adjacent coarse ribbon quads share full edges without holes")
				for index: int in indices: check(index >= 0 and index < 480, "LOD index references existing crown vertices")
		var trunk: CollisionShape3D = palm.get_node("PalmTrunk").get_child(0)
		check(is_equal_approx(trunk.shape.height,0.7) and is_equal_approx(trunk.shape.radius,0.0175), "physical trunk dimensions unchanged")
		palm.free()
