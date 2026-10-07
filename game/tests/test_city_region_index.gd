# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const Index := preload("res://scripts/view/city_region_index_2d.gd")
const Batcher := preload("res://scripts/view/city_mesh_batcher_3d.gd")

static func _linear(owned: Rect2i, regions: Array[Rect2i]) -> bool:
	for region: Rect2i in regions:
		if owned.intersects(region): return true
	return false

func test_exact_rect_intersection_randomized_edges_and_fallbacks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 829145
	for scenario: int in 9:
		var regions: Array[Rect2i] = []
		for i: int in (3 if scenario == 0 else 500):
			regions.append(Rect2i(rng.randi_range(-8192,8192),rng.randi_range(-8192,8192),rng.randi_range(1,64),rng.randi_range(1,64)))
		if scenario == 2: regions.append(Rect2i(-5,-8,0,2))
		if scenario == 3: regions.append(Rect2i(-5,-8,2,0))
		if scenario == 4: regions.append(Rect2i(-900000,-900000,1800000,1800000))
		if scenario == 5: regions.append(Rect2i(2147483640,0,16,8))
		if scenario == 6:
			for i: int in 1000: regions.append(Rect2i(i*1024,0,512,512))
		if scenario == 7: regions.clear()
		var index := Index.new(regions)
		for i: int in 1200:
			var owned := Rect2i(rng.randi_range(-8192,8192),rng.randi_range(-8192,8192),rng.randi_range(0,100),rng.randi_range(0,100))
			if i<regions.size():
				var region := regions[i]
				owned = Rect2i(region.position+Vector2i(region.size.x,0),Vector2i(1,1)) if i%2==0 else region
			if i == 1198: owned = Rect2i(-1000000,-1000000,2000000,2000000)
			if i == 1199: owned = Rect2i(2147483640,0,16,8)
			check_eq(index.intersects(owned),_linear(owned,regions),"scenario%s/query%s matches the linear scan"%[scenario,i])

func test_input_snapshot_and_scattered_query_performance() -> void:
	var regions: Array[Rect2i] = []
	for i: int in 1000: regions.append(Rect2i((i%40)*256-5000,(i/40)*256-3000,4,4))
	var index := Index.new(regions)
	var queries: Array[Rect2i] = []
	for i: int in 6000: queries.append(Rect2i((i%120)*32-5000,(i/120)*32-3000,2,2))
	var expected: Array[bool] = []
	var start := Time.get_ticks_usec()
	for query: Rect2i in queries: expected.append(_linear(query,regions))
	var original_us := Time.get_ticks_usec()-start
	start = Time.get_ticks_usec()
	var actual: Array[bool] = []
	for query: Rect2i in queries: actual.append(index.intersects(query))
	var indexed_us := Time.get_ticks_usec()-start
	check_eq(actual,expected,"exact query results")
	print("REGION_QUERY_CPU_US before=%s after=%s"%[original_us,indexed_us])
	check(indexed_us*2<original_us,"scattered region queries must halve linear CPU")
	regions.clear()
	check(index.intersects(Rect2i(-5000,-3000,1,1)),"index owns stable input snapshot")

func _signature(batcher: Node3D) -> Array:
	var out: Array = []
	for batch: MultiMeshInstance3D in batcher.get_children():
		out.append([batch.get_meta("chunk"),batch.get_meta("domain"),batch.get_meta("source_ids"),
			batch.get_meta("uploaded_transforms"),batch.multimesh.custom_aabb,batch.multimesh.mesh.get_instance_id(),
			batch.layers,batch.cast_shadow,batch.visible,batch.get_meta("source_regions")])
	out.sort_custom(func(a: Array,b: Array)->bool: return str(a)<str(b))
	return out

func test_large_region_update_matches_full_batches_and_retains_far_identity() -> void:
	var world := Node3D.new()
	world.position = Vector3(1000,7,-2000)
	root.add_child(world)
	var sources := Node3D.new()
	sources.position.x = 9
	sources.set_meta("batch_domain",&"buildings")
	world.add_child(sources)
	var batcher := Batcher.new()
	batcher.position.x = 9
	world.add_child(batcher)
	var mesh := BoxMesh.new()
	for i: int in 80:
		var x := (i-40)*64
		var branch := Node3D.new()
		branch.set_meta("batch_region",Rect2i(x,-1,8,8))
		sources.add_child(branch)
		for offset: int in 2:
			var source := MeshInstance3D.new()
			source.mesh = mesh
			source.position = Vector3(x+offset,2,3)
			branch.add_child(source)
	var roots: Array[Node3D] = [sources]
	batcher.rebuild(roots)
	var regions: Array[Rect2i] = [Rect2i(-2560,-1,8,8)]
	for i: int in 999: regions.append(Rect2i(i*64,-5000,4,4))
	var distant: Node = batcher.get_child(79)
	var distant_id := distant.get_instance_id()
	sources.get_child(0).get_child(0).position.y = 8
	batcher.set_domain_visible(&"buildings",false)
	batcher.update_regions(roots,regions)
	check(is_instance_valid(distant) and distant.get_parent()==batcher and distant.get_instance_id()==distant_id,"far batch identity stays intact")
	var signature := _signature(batcher)
	batcher.rebuild(roots)
	check_eq(_signature(batcher),signature,"full exact sources/groups/transforms/bounds/domain/visibility match indexed update")
	regions = [Rect2i(-2496,-1,8,8)]
	sources.get_child(1).get_child(1).position.y = 6
	batcher.update_regions(roots,regions)
	signature = _signature(batcher)
	batcher.rebuild(roots)
	check_eq(_signature(batcher),signature,"later unrelated small update has no stale query scope")
	batcher.clear()
	for branch: Node3D in sources.get_children():
		for source: MeshInstance3D in branch.get_children(): check(source.visible,"clear restores every source")
	world.free()
