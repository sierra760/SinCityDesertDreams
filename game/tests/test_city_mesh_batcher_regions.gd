# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
const Batcher := preload("res://scripts/view/city_mesh_batcher_3d.gd")
func test_regional_updates_match_full_batches() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var sources := Node3D.new()
	sources.set_meta("batch_domain", &"buildings")
	world.add_child(sources)
	var mesh := BoxMesh.new()
	for x: int in [-3,-2,3,4,70,71]:
		var source := MeshInstance3D.new()
		source.mesh = mesh
		source.position.x = x
		source.set_meta("batch_region", Rect2i(x,0,1,1))
		sources.add_child(source)
	var batcher := Batcher.new()
	world.add_child(batcher)
	batcher.rebuild([sources])
	var distant: Node = null
	for batch: Node in batcher.get_children():
		if batch.get_meta("chunk") == Vector2i(2,0): distant = batch
	var removed := sources.get_child(2)
	sources.remove_child(removed)
	removed.free()
	batcher.update_regions([sources], [Rect2i(3,0,1,1)])
	check(is_instance_valid(distant) and distant.get_parent() == batcher, "unrelated distant batch identity retained")
	check(sources.get_child(2).visible, "remaining singleton restored after removal")
	check(batcher.statistics.batched_instances == 4, "removed and singleton instances excluded from statistics")
	var replacement := MeshInstance3D.new()
	replacement.mesh = mesh
	replacement.position.x = 3
	replacement.set_meta("batch_region", Rect2i(3,0,1,1))
	sources.add_child(replacement)
	batcher.set_domain_visible(&"buildings",false)
	batcher.update_regions([sources], [Rect2i(3,0,1,1)])
	check(not replacement.visible, "new source batched alongside existing neighbor")
	for batch: Node3D in batcher.get_children(): check(not batch.visible, "hidden domain survives incremental replacement")
	check(batcher.statistics.batched_instances == 6 and batcher.statistics.batches == 3, "incremental statistics cover all retained and recreated batches")
	batcher.clear()
	for source: MeshInstance3D in sources.get_children(): check(source.visible, "clear restores retained and new sources")
	world.free()
	await process_frame
