# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Ordered compact intermediates keep their golden floors, obstacles and walls.
extends "res://tests/test_case.gd"
const Hashes := preload("res://tests/fixtures/output_hashes.gd")
const Resolver := preload("res://scripts/view/city_network_physics.gd")

func test_complete_multigroup_projection_keeps_depths_and_order() -> void:
	var patches: Array[Dictionary] = []
	for cell: Vector2i in [Vector2i(126,126),Vector2i(3,4),Vector2i(127,126)]:
		for i: int in 3:
			var origin := Vector3(cell.x,4.0+i*.015,cell.y)
			var triangle := PackedVector3Array([origin+Vector3(.1,0,.1),origin+Vector3(.9,.03,.1),origin+Vector3(.5,.01,.9)])
			patches.append({"cell":cell,"group":1 if i%2==0 else 4,"role":i,"triangle":triangle,"depth":.09500000000000003 if i%2==0 else .12500000000000003})
	var obstacles := PackedVector3Array([Vector3(126,4,126),Vector3(126,5,126),Vector3(126,4,127)])
	var boxes: Array[Dictionary] = [{"size":Vector3(.2,1,.3),"transform":Transform3D(Basis.IDENTITY,Vector3(127,4,127))}]
	var inputs := var_to_bytes([patches,boxes,obstacles])
	var actual := Resolver.resolve(patches,boxes,obstacles)
	check(Hashes.matches("resolve/multigroup", Hashes.sha(actual)),"every floor/obstacle/box and group order survives compact projection")
	check_eq(var_to_bytes([patches,boxes,obstacles]),inputs,"projection leaves caller-owned inputs unchanged")
	check_gt(actual.physical_floor_faces.size(),0,"fixture contains usable ordered floors")

func test_boundary_adapter_keeps_t_junctions_lips_degenerate_and_nonmanifold_edges() -> void:
	var triangles: Array[PackedVector3Array] = [
		PackedVector3Array([Vector3(126,4,126),Vector3(127,4,126),Vector3(127,4.02,127)]),
		PackedVector3Array([Vector3(126,4,126),Vector3(127,4.02,127),Vector3(126,4.02,127)]),
		PackedVector3Array([Vector3(127,4,126),Vector3(128,4.01,126),Vector3(127,4.02,126.5)]),
		PackedVector3Array([Vector3(128,4,127),Vector3(128,4,127),Vector3(128,4,128)]),
		PackedVector3Array([Vector3(127,4,127),Vector3(127.5,4,127),Vector3(127.25,4,127.00002)])]
	# Three coincident copies exercise cancellation with more than two
	# contributors: they are not welded and no majority rule applies.
	triangles.append(triangles[4]);triangles.append(triangles[4])
	var edges: Array[Dictionary] = []
	for index: int in triangles.size():
		var triangle := triangles[index]
		for i: int in 3:
			edges.append({"a":triangle[i],"b":triangle[(i+1)%3],"depth":.09500000000000003+index*.00700000000000001})
	var before := var_to_bytes([edges,triangles])
	var actual := PackedVector3Array()
	Resolver._append_deck_boundaries(edges,triangles,actual)
	check(Hashes.matches("deck_boundaries/contributors", Hashes.sha(actual)),"edge splitting, quantized cancellation, exposure, lips and winding match the golden hash")
	check_eq(var_to_bytes([edges,triangles]),before,"boundary projection leaves edges and triangles unchanged")
	check_gt(actual.size(),0,"fixture exercises exposed walls")
