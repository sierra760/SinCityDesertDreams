# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Portable preparation keeps ordered geometry while bounding dense searches.
extends "res://tests/test_case.gd"
const Resolver := preload("res://scripts/view/city_network_physics.gd")
const Native := preload("res://scripts/view/city_network_physics_native.gd")
const Hashes := preload("res://tests/fixtures/output_hashes.gd")


static func _grid(side: int) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	for y: int in side:
		for x: int in side:
			var a := Vector2(x,y)/side
			var b := Vector2(x+1,y)/side
			var c := Vector2(x+1,y+1)/side
			var d := Vector2(x,y+1)/side
			polygons.append(PackedVector2Array([a,b,c]))
			polygons.append(PackedVector2Array([a,c,d]))
	return polygons


func test_dense_partition_bounds_candidate_work_without_changing_faces() -> void:
	var polygons := _grid(64)
	var before := var_to_bytes(polygons)
	var work := {"measure":true}
	var actual := Resolver._partition_polygons(polygons,work)
	print("    dense partition candidates=",work.candidates," polygons=",polygons.size())
	check_lt(work.candidates,polygons.size()*16,"tiny disjoint facets avoid crowded coarse-bin candidate scans")
	check_eq(Hashes.sha(actual),"8efece4a3f25b18909a60cf582f4373a2cb5f8c0dc364bf54f849dc7102046b5","ordered dense partition matches the pre-optimization resolver")
	check_eq(var_to_bytes(polygons),before,"partition leaves caller-owned inputs unchanged")


func test_mixed_broad_acute_and_negative_partition_keeps_order() -> void:
	var polygons := _grid(24)
	polygons.push_front(PackedVector2Array([Vector2(-.001,.5),Vector2(1.001,.5),Vector2(.5,.500001)]))
	polygons.append(PackedVector2Array([Vector2(-10,-10),Vector2(10,-10),Vector2(0,10)]))
	polygons.append(PackedVector2Array([Vector2(-.25,-.5),Vector2(.25,-.5),Vector2(0,.5)]))
	var before := var_to_bytes(polygons)
	var actual := Resolver._partition_polygons(polygons)
	check_eq(Hashes.sha(actual),"255350ca2e2d6582a35d768b3442935c5369ce568db3647e13d0e3eaadfd64eb","broad-bin fallback, acute cuts and negative cells preserve the ordered pre-optimization result")
	check_eq(var_to_bytes(polygons),before,"mixed partition leaves caller-owned inputs unchanged")
	check_eq(Resolver._partition_polygons([]),[],"empty partitions remain empty")


func test_finer_bins_keep_facets_that_newly_cross_the_broad_search_cap() -> void:
	# A unit-square bound occupies 289 old bins and 4225 fine bins. Exercise
	# it as both an earlier cutter and a later subject, with the original hashes.
	for first: bool in [true,false]:
		var polygons := _grid(24)
		var broad := PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN])
		if first: polygons.push_front(broad)
		else: polygons.append(broad)
		var expected := "43ebb458240f253c3c7b0208b44ce5d36eed2e7924bd199da5bb1c8e2b85b54c" if first else "d33fe7755e3e05e3e401c13a19766a8b0568d44994dceea116aace796e97faeb"
		check_eq(Hashes.sha(Resolver._partition_polygons(polygons)),expected,"newly broad cutters and subjects preserve every clipped vertex and its order")


func test_interleaved_edge_contributors_keep_first_owner_and_cancel_nonmanifold_keys() -> void:
	# A,B,A,C,B,D,D,D,E,D: singles, lips, separated heights and a
	# four-contributor cancellation, with skipped groups and reversed edges.
	var keys := [0,2,0,4,2,6,6,6,8,6]
	var heights := [1.0,1.0,1.015,1.0,1.5,1.0,1.01,1.5,2.0,2.0]
	var groups := PackedInt32Array([0,1,2,3,4,5,6,7,9,10])
	var points := PackedVector3Array()
	var depths := PackedFloat64Array()
	for i: int in keys.size():
		var a := Vector3(keys[i],heights[i],0)
		var b := Vector3(keys[i]+.5,heights[i],0)
		points.append(b if i%2 else a);points.append(a if i%2 else b)
		depths.append(.1+i*.005)
	var before := var_to_bytes([points,depths,groups])
	var walls := PackedVector3Array()
	var ends := PackedInt32Array();ends.resize(12)
	Resolver._append_numeric_deck_boundaries(points,depths,[],walls,groups,ends)
	check_eq(walls.size(),72,"lip and separated pairs emit 24 points each; two singles emit 12 each; four contributors cancel")
	check_eq(ends,PackedInt32Array([24,48,48,60,60,60,60,60,60,72,72,72]),"walls belong to the first contributor and preserve skipped groups")
	check_eq(Hashes.sha(walls),"cd58cb6a7002512914b75981a1321a9130d9b4dc1463eba4a5170b0d1e7db748","every wall vertex and winding matches the pre-optimization resolver")
	check_eq(var_to_bytes([points,depths,groups]),before,"boundary preparation leaves inputs unchanged")


func test_flat_coverage_rejects_other_heights_at_the_existing_threshold() -> void:
	var triangle := PackedVector3Array([Vector3(0,1,0),Vector3(1,1,0),Vector3(0,1,1)])
	var prepared := Resolver.PackedDeckTriangles.new([triangle])
	var bins := {Vector3i(0,0,32):[0]}
	check(Resolver._packed_deck_bin_covers(Vector2(.01,.01),1.029,bins,prepared,32),"nearby deck height covers the probe")
	check(not Resolver._packed_deck_bin_covers(Vector2(.01,.01),1.031,bins,prepared,32),"a different deck height cannot hide an exposed wall")
	check(not Resolver._packed_deck_bin_covers(Vector2(.01,.01),2.0,bins,prepared,32),"stacked overpasses remain separate")


func test_packed_fallback_preserves_interleaved_groups_prefix_and_detached_boxes() -> void:
	var patches: Array[Dictionary] = []
	for i: int in 6:
		var origin := Vector3(126 if i%2 else -1,2+i*.01,4)
		patches.append({"cell":Vector2i(origin.x,origin.z),"group":i%2,"role":i%3,
			"depth":.12 if i%2 else 0.0,
			"triangle":PackedVector3Array([origin,origin+Vector3(.8,.02,0),origin+Vector3(.1,0,.8)])})
	var boxes: Array[Dictionary] = [{"nested":{"size":Vector3.ONE}}]
	var prefix := PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	var packed := Native.pack_patches(patches)
	var before := var_to_bytes([packed,boxes,prefix])
	var expected := Resolver.resolve(patches,boxes,prefix)
	var forced := Native.force_fallback
	Native.force_fallback = true
	var actual := Native.resolve_packed(packed[0],packed[1],packed[2],packed[3],packed[4],boxes,prefix)
	check_eq(var_to_bytes(actual),var_to_bytes(expected),"packed fallback retains floor, prefix, bottom, wall and box order")
	var empty: Array[Dictionary] = []
	var no_patches := Native.pack_patches(empty)
	check_eq(var_to_bytes(Native.resolve_packed(no_patches[0],no_patches[1],no_patches[2],no_patches[3],no_patches[4],boxes,prefix)),var_to_bytes(Resolver.resolve(empty,boxes,prefix)),"empty packed fallback retains prefix and boxes")
	Native.force_fallback = forced
	actual.physical_boxes[0].nested.size = Vector3.ZERO
	actual.physical_obstacle_faces[0] = Vector3.ONE
	check_eq(var_to_bytes([packed,boxes,prefix]),before,"returned geometry and nested boxes are detached from caller-owned inputs")


func test_triangle_clipping_preserves_crossings_boundary_vertices_and_winding() -> void:
	var triangle := PackedVector2Array([Vector2(-1,-1),Vector2(-1,1),Vector2(1,0)])
	var cases := [
		[triangle,1.0,PackedVector2Array([Vector2(0,-.5),Vector2(0,.5),Vector2(1,0)])],
		[triangle,-1.0,PackedVector2Array([Vector2(0,-.5),Vector2(-1,-1),Vector2(-1,1),Vector2(0,.5)])],
		[PackedVector2Array([Vector2(1,1),Vector2(1,-1),Vector2(2,0)]),1.0,PackedVector2Array([Vector2(1,1),Vector2(1,-1),Vector2(2,0)])],
		[PackedVector2Array([Vector2(1,1),Vector2(1,-1),Vector2(2,0)]),-1.0,PackedVector2Array()],
		[PackedVector2Array([Vector2(-0.0,1),Vector2(0,-1),Vector2(1,0)]),1.0,PackedVector2Array([Vector2(-0.0,1),Vector2(0,-1),Vector2(1,0)])],
		[PackedVector2Array([Vector2(0,0),Vector2(0,1),Vector2(0,2)]),1.0,PackedVector2Array([Vector2(0,0),Vector2(0,1),Vector2(0,2)])]]
	for fixture: Array in cases:
		var before := var_to_bytes(fixture[0])
		var actual := Resolver._clip_physical_plane(fixture[0],Vector2.ZERO,Vector2(0,-1),fixture[1])
		check_eq(var_to_bytes(actual),var_to_bytes(fixture[2]),"triangle clipping retains literal expected vertices in traversal order")
		if not actual.is_empty(): actual[0] = Vector2(10,10)
		check_eq(var_to_bytes(fixture[0]),before,"even wholly admitted triangles remain detached on mutation")
