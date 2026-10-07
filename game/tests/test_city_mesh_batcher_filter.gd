# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Regional work skips remote material eligibility without pruning transformed children.
extends "res://tests/exploration/async_test_case.gd"
class ObservedBatcher extends "res://scripts/view/city_mesh_batcher_3d.gd":
	var inspected: Array[int] = []
	func _eligible(source: MeshInstance3D) -> bool:
		inspected.append(source.get_instance_id())
		return super._eligible(source)
func test_regional_work_skips_remote_material_checks() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var source_root := Node3D.new()
	world.add_child(source_root)
	var mesh := BoxMesh.new()
	var remote: Array[int] = []
	for x: int in [1,2,80,81]:
		var source := MeshInstance3D.new()
		source.mesh = mesh
		source.position.x = x
		source_root.add_child(source)
		if x > 32: remote.append(source.get_instance_id())
	var far_parent := MeshInstance3D.new()
	far_parent.mesh = mesh
	far_parent.position.x = 80
	source_root.add_child(far_parent)
	remote.append(far_parent.get_instance_id())
	var near_child := MeshInstance3D.new()
	near_child.mesh = mesh
	near_child.position.x = -77
	far_parent.add_child(near_child)
	var batcher := ObservedBatcher.new()
	world.add_child(batcher)
	batcher.rebuild([source_root])
	var far_batch: Node = null
	for batch: Node in batcher.get_children():
		if batch.get_meta("chunk") == Vector2i(2,0): far_batch = batch
	batcher.inspected.clear()
	batcher.update_regions([source_root],[Rect2i(1,0,3,1)])
	for id: int in remote:
		check(not batcher.inspected.has(id),"regional edit skips remote material/render eligibility work")
	check(batcher.inspected.has(near_child.get_instance_id()) and not near_child.visible,"remote parent does not prune a transformed child in affected chunk")
	check(is_instance_valid(far_batch) and far_batch.get_parent() == batcher,"remote batch remains attached unchanged")
	check(batcher.statistics.batched_instances == 5,"regional filtering retains all five eligible visible replacements")
	world.free()
	await process_frame
