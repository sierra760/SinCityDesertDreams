# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const Batcher := preload("res://scripts/view/city_mesh_batcher_3d.gd")

func test_claim_suppresses_only_its_batch_row_and_survives_rebuilds() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var lots := Node3D.new()
	world.add_child(lots)
	var batcher := Batcher.new()
	world.add_child(batcher)
	var mesh := BoxMesh.new()
	var a := MeshInstance3D.new()
	a.mesh = mesh
	a.position = Vector3(2,1,2)
	lots.add_child(a)
	var b := MeshInstance3D.new()
	b.mesh = mesh
	b.position = Vector3(4,1,2)
	lots.add_child(b)
	batcher.rebuild([lots])
	check(batcher.has_method("set_source_visible"),"batcher supports reversible individual claims")
	if not batcher.has_method("set_source_visible"):
		world.free()
		return
	batcher.call("set_source_visible",a,false)
	check(not a.visible)
	if DisplayServer.get_name() != "headless":
		var batch := batcher.get_child(0) as MultiMeshInstance3D
		check_eq(batch.multimesh.get_instance_transform(0).basis.determinant(),0.0,"claimed GPU row collapses")
		check(batch.multimesh.get_instance_transform(1).is_equal_approx(b.transform),"other GPU row is untouched")
	batcher.clear()
	check(not a.visible and b.visible,"clear does not resurrect a claimed static vehicle")
	batcher.rebuild([lots])
	check_eq(batcher.get_child_count(),1,"suppressed row keeps the same shared batch")
	if DisplayServer.get_name() != "headless":
		check_eq((batcher.get_child(0) as MultiMeshInstance3D).multimesh.get_instance_transform(0).basis.determinant(),0.0,"rebuild never resurrects its GPU row")
	batcher.call("set_source_visible",a,true)
	if DisplayServer.get_name() != "headless":
		check((batcher.get_child(0) as MultiMeshInstance3D).multimesh.get_instance_transform(0).is_equal_approx(a.transform),"release restores the actual GPU transform")
	check(not a.visible,"restored batched source remains hidden behind its batch")
	batcher.clear()
	check(a.visible and b.visible,"releasing the claim restores normal source visibility")
	batcher.call("set_source_visible",a,false)
	check(not a.visible,"single unbatched vehicle also suppresses")
	batcher.call("set_source_visible",a,true)
	check(a.visible,"single unbatched vehicle also restores")
	world.free()
