# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Collision extraction keeps its golden geometry and output order.
extends "res://tests/test_case.gd"
const Hashes := preload("res://tests/fixtures/output_hashes.gd")
const Resolver := preload("res://scripts/view/city_network_physics.gd")

func _grid(side: int) -> Array[PackedVector2Array]:
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

func test_dense_curved_deck_partition() -> void:
	check(Hashes.matches("partition/dense_grid", Hashes.sha(Resolver._partition_polygons(_grid(24)))), "same polygons, vertices and output order")

func test_partition_preserves_overlaps_holes_acute_and_boundary_faces() -> void:
	var polygons := _grid(8)
	polygons.push_front(PackedVector2Array([Vector2(.2,.2),Vector2(.8,.2),Vector2(.5,.8)]))
	polygons.push_front(PackedVector2Array([Vector2(-.001,.5),Vector2(1.001,.5),Vector2(.5,.500001)]))
	polygons.append(PackedVector2Array([Vector2(-2,-2),Vector2(4,-2),Vector2(1,4)]))
	check(Hashes.matches("partition/overlaps_holes_acute", Hashes.sha(Resolver._partition_polygons(polygons))), "overlap subtraction keeps ordered geometry")

func test_complete_curved_floor_walls_and_boxes() -> void:
	var patches: Array[Dictionary] = []
	for polygon: PackedVector2Array in _grid(8):
		var triangle := PackedVector3Array()
		for p: Vector2 in polygon: triangle.append(Vector3(91+p.x,4+.12*p.x*p.x,87+p.y))
		patches.append({"cell":Vector2i(91,87),"group":1,"role":0,"triangle":triangle,"depth":.095})
	var boxes: Array[Dictionary] = [{"size":Vector3(.1,1,.1),"transform":Transform3D(Basis.IDENTITY,Vector3(91,3,87))}]
	var obstacles := PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	check(Hashes.matches("resolve/curved_floor_walls_boxes", Hashes.sha(Resolver.resolve(patches,boxes,obstacles))), "complete floor/wall/box outputs match the golden hash")

func test_dense_deck_boundary_search_preserves_all_walls() -> void:
	check(Hashes.matches("deck_boundaries/dense_curve", Hashes.sha(_deck_walls(false))), "dense subdivision walls and ordering match the golden hash")

func test_broad_flat_deck_walls() -> void:
	check(Hashes.matches("deck_boundaries/broad_flat", Hashes.sha(_deck_walls(true))), "flat span walls and ordering match the golden hash")

func _deck_walls(flat: bool) -> PackedVector3Array:
	var triangles: Array[PackedVector3Array] = []
	var edges: Array[Dictionary] = []
	for polygon: PackedVector2Array in _grid(8 if flat else 24):
		var triangle := PackedVector3Array()
		for p: Vector2 in polygon:
			triangle.append(Vector3(67+p.x*8,4,91+p.y*8) if flat else Vector3(67+p.x,4+.1*p.x*p.x,91+p.y))
		triangles.append(triangle)
		for i: int in 3: edges.append({"a":triangle[i],"b":triangle[(i+1)%3],"depth":.095})
	var walls := PackedVector3Array()
	Resolver._append_deck_boundaries(edges,triangles,walls)
	return walls
