# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")
const G := preload("res://scripts/core/agricultural_parcel_geometry.gd")

# Exhaustively enumerate the documented half-metre lattice and yaw order,
# using the general transformed-box predicate as the placement oracle.
func reference(record: Dictionary, previous: Array, fill: bool) -> Dictionary:
	var cells := G._mask(record)
	var placed: Array = []
	var keys := {}
	for module: Variant in previous:
		var valid := G._valid_pose(module)
		if valid: valid = not keys.has(String(module.key)) and G._fits(module,cells,placed)
		if not valid:
			if not fill: return {"ok":false,"modules":placed}
			continue
		placed.append(module.duplicate(true));keys[String(module.key)]=true
	for key: StringName in G._required(record):
		if keys.has(String(key)): continue
		if not fill: return {"ok":false,"modules":placed}
		var found := false
		var box: Array = G._pen(record,[],[]).bounds
		for z in range(ceili(box[1]*2),floori(box[3]*2)+1):
			if found: break
			for x in range(ceili(box[0]*2),floori(box[2]*2)+1):
				if found: break
				if not cells.has(Vector2i(floori(x*.5/G.TILE),floori(z*.5/G.TILE))): continue
				for yaw in 4:
					var pose := {"key":key,"at":Vector3(x*.5,G.GROUND,z*.5),"yaw":yaw}
					if G._fits(pose,cells,placed):
						placed.append(pose);keys[String(key)]=true;found=true
						break
		if not found: return {"ok":false,"modules":placed}
	return {"ok":true,"modules":placed}

func compare(record: Dictionary, previous: Array = [], fill: bool = true) -> void:
	var before := var_to_bytes([record,previous])
	var expected := reference(record,previous,fill)
	var actual := G._placement(record,previous,fill)
	check(var_to_bytes(actual)==var_to_bytes(expected),"exact module poses and yaw order: %s" % record.archetype)
	check(var_to_bytes([record,previous])==before,"placement must not mutate retained inputs")

func comb() -> PackedInt32Array:
	var members := PackedInt32Array()
	for y in range(20,29):
		for x in range(20,32):
			if (y-20)%2 == 0 or x == 20: members.append(y*128+x)
	return members

func test_shapes_and_archetypes_keep_exact_first_legal_module_pose() -> void:
	var shapes := [F.square(1),F.square(2),F.square(8),F.expanded(F.l_shape()),
		F.expanded(F.u_shape()),F.expanded(F.ring()),F.expanded(F.dumbbell()),comb()]
	check_eq(comb().size(),64)
	for members in shapes:
		for key in AgricultureParams.LOW_ARCHETYPES:
			for shift in [Vector2i(-4,-4),Vector2i.ZERO,Vector2i(4,4),Vector2i(100,100)]:
				var record := F.record(1,members,key)
				record.origin_index += shift.y*128+shift.x
				compare(record)

func test_all_retained_structure_kinds_and_yaws_keep_their_identity() -> void:
	var record := F.record(1,F.square(4),&"cattle_range")
	for key in G.STRUCTURES:
		for yaw in 4:
			var previous := [{"key":key,"at":Vector3(8,G.GROUND,8),"yaw":yaw}]
			compare(record,previous)
			compare(record,previous,false)

func test_invalid_and_cut_module_poses_follow_the_same_repair_policy() -> void:
	var record := F.record(1,F.expanded(F.ring()),&"sheep_pasture")
	for pose in [{"key":&"farm_shed","at":Vector3(40,G.GROUND,40),"yaw":0},
		{"key":&"shade_shelter","at":Vector3(-2,G.GROUND,-2),"yaw":3},
		{"key":&"water_trough","at":Vector3(8.25,G.GROUND,8),"yaw":1},
		{"key":&"grain_bin","at":Vector3(8,G.GROUND,8),"yaw":4},
		{"key":&"hay_bale","at":Vector3(INF,G.GROUND,8),"yaw":0},
		{"key":&"unknown","at":Vector3(8,G.GROUND,8),"yaw":0}]:
		compare(record,[pose])
		compare(record,[pose],false)
	var duplicated := [{"key":&"shade_shelter","at":Vector3(8,G.GROUND,8),"yaw":0},
		{"key":&"shade_shelter","at":Vector3(24,G.GROUND,8),"yaw":1}]
	compare(record,duplicated)
	compare(record,duplicated,false)

func test_required_placement_builds_bounded_number_of_transformed_boxes() -> void:
	for key in [&"grain",&"cattle_range",&"sheep_pasture"]:
		var record := F.record(1,F.square(4),key)
		var start: int = G._box_evaluations
		var expected := reference(record,[],true)
		var reference_work: int = G._box_evaluations-start
		start = G._box_evaluations
		var actual := G._placement(record,[],true)
		var actual_work: int = G._box_evaluations-start
		check(var_to_bytes(actual)==var_to_bytes(expected))
		check(reference_work > 100,"oracle must exercise the placement search")
		check(actual_work <= 8,"only four fixed boxes per required structure: %d" % actual_work)
