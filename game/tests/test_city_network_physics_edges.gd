# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Fine-bin boundaries and microscopic T-junctions keep their golden deck walls.
extends "res://tests/test_case.gd"
const Hashes := preload("res://tests/fixtures/output_hashes.gd")
const Resolver := preload("res://scripts/view/city_network_physics.gd")
func test_bin_boundaries_and_tiny_junctions_match_goldens() -> void:
	var walls := []
	for offset: Vector2 in [Vector2.ZERO,Vector2(0.249999,0.499999),Vector2(126.99999,127.25),Vector2(-0.00001,-0.5)]:
		for drift: float in [0.0,0.0000002,0.000005,-0.000005]:
			var triangles: Array[PackedVector3Array] = []
			var shape: Array[Vector2] = [Vector2(0,0),Vector2(.6,0),Vector2(0,.6),Vector2(.6,0),Vector2(.6,.6),Vector2(0,.6),
				Vector2(.6+drift,0),Vector2(.9,0),Vector2(.6+drift,.3),Vector2(.6+drift,.3),Vector2(.9,0),Vector2(.9,.6),
				Vector2(.6+drift,.3),Vector2(.9,.6),Vector2(.6+drift,.6)]
			for height: float in [1.0,3.0]:
				for i: int in range(0,shape.size(),3):
					var triangle := PackedVector3Array()
					for j: int in 3:
						var point := shape[i+j]+offset
						triangle.append(Vector3(point.x,height,point.y))
					triangles.append(triangle)
			var edges: Array[Dictionary] = []
			for triangle: PackedVector3Array in triangles:
				for i: int in 3: edges.append({"a":triangle[i],"b":triangle[(i+1)%3],"depth":0.12})
			var actual := PackedVector3Array()
			Resolver._append_deck_boundaries(edges,triangles,actual)
			check(not actual.is_empty(), "microscopic deck edges emit walls %s drift=%s" % [offset,drift])
			walls.append(actual)
	check(Hashes.matches("deck_boundaries/microscopic_junctions", Hashes.sha(walls)), "microscopic deck edges match the golden walls")
	# Tolerant half planes of a needle triangle extend much farther than its
	# AABB near an acute tip. A fixed padded fine exposure bin is not safe.
	var needle: Array[PackedVector3Array] = [PackedVector3Array([Vector3(.2502,1,.5),Vector3(1.25,1,.500001),Vector3(1.25,1,.499999)])]
	var probe_edges: Array[Dictionary] = [{"a":Vector3(.24999,1,.4),"b":Vector3(.24999,1,.6),"depth":.12}]
	var needle_walls := PackedVector3Array()
	Resolver._append_deck_boundaries(probe_edges,needle,needle_walls)
	check(needle_walls.is_empty(), "acute tolerant exposure outside the triangle AABB keeps coarse-bin semantics, actual=%d" % needle_walls.size())
	# Conservative fine bins must keep tolerance-expanded acute tips at
	# rotated city coordinates, across coarse and fine cell boundaries.
	walls = []
	for origin: Vector2 in [Vector2.ZERO,Vector2(63.9999,126.5)]:
		for angle: float in [0.0,.3,PI*.5,PI]:
			for width: float in [.000001,.00002,.001]:
				var points := PackedVector3Array()
				for source: Vector2 in [Vector2(.0002,0),Vector2(1.0,width),Vector2(1.0,-width)]:
					var point := source.rotated(angle)+origin
					points.append(Vector3(point.x,1,point.y))
				var probe_a := Vector2(-.00001,-.1).rotated(angle)+origin
				var probe_b := Vector2(-.00001,.1).rotated(angle)+origin
				var probes: Array[Dictionary] = [{"a":Vector3(probe_a.x,1,probe_a.y),"b":Vector3(probe_b.x,1,probe_b.y),"depth":.12}]
				var triangles: Array[PackedVector3Array] = [points]
				var actual := PackedVector3Array()
				Resolver._append_deck_boundaries(probes,triangles,actual)
				walls.append(actual)
	check(Hashes.matches("deck_boundaries/rotated_acute_tips", Hashes.sha(walls)), "rotated acute tips match the golden walls")
