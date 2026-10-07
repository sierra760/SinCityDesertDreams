# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const Batcher := preload("res://scripts/view/city_mesh_batcher_3d.gd")

func _fixture() -> Dictionary:
	var world := Node3D.new()
	world.position = Vector3(1000, 3, -200)
	root.add_child(world)
	var sources := Node3D.new()
	sources.position.x = 11
	sources.set_meta("batch_domain", &"buildings")
	world.add_child(sources)
	var batcher := Batcher.new()
	batcher.position.x = 11
	world.add_child(batcher)
	var roots: Array[Node3D] = [sources]
	return {"world":world,"sources":sources,"roots":roots,"batcher":batcher,"mesh":BoxMesh.new()}

func _branch(fixture: Dictionary, owned: Rect2i, positions: Array) -> Node3D:
	var branch := Node3D.new()
	branch.set_meta("batch_region",owned)
	fixture.sources.add_child(branch)
	for x: float in positions:
		var source := MeshInstance3D.new()
		source.mesh = fixture.mesh
		source.position = Vector3(x,2,3)
		branch.add_child(source)
	return branch

func _update(fixture: Dictionary, region: Rect2i) -> Dictionary:
	var regions: Array[Rect2i] = [region]
	return fixture.batcher.update_regions(fixture.roots,regions)

func _signature(batcher: Node3D) -> Array:
	var result: Array = []
	for batch: MultiMeshInstance3D in batcher.get_children():
		result.append([str(batch.get_meta("chunk")),String(batch.get_meta("domain")),
			batch.get_meta("source_ids"),batch.get_meta("uploaded_transforms"),
			batch.multimesh.mesh.get_instance_id(),batch.multimesh.custom_aabb,
			batch.cast_shadow,batch.layers,batch.visible])
	result.sort_custom(func(a: Array,b: Array) -> bool:
		return str(a)<str(b))
	return result

func _check_full_reference(fixture: Dictionary) -> void:
	var batcher: Node3D = fixture.batcher
	var partial := _signature(batcher)
	batcher.rebuild(fixture.roots)
	check_eq(_signature(batcher),partial,"regional groups, source identities, transforms, bounds, domain and shadow match a fresh full rebuild")

func test_local_update_scans_one_owned_branch_and_retains_distant_batches() -> void:
	var f := _fixture()
	for chunk: int in 128:
		_branch(f,Rect2i(chunk*32,0,8,8),[chunk*32+2.0,chunk*32+3.0,chunk*32+4.0,chunk*32+5.0])
	for index: int in 2:
		f.sources.get_child(0).get_child(index).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	var batcher: Node3D = f.batcher
	var full: Dictionary = batcher.rebuild(f.roots)
	check_eq(full.source_meshes,512,"full fixture traverses every source")
	var far_ids: Array[int] = []
	for batch: Node in batcher.get_children():
		if batch.get_meta("chunk") != Vector2i.ZERO: far_ids.append(batch.get_instance_id())
	var branch: Node3D = f.sources.get_child(0)
	branch.get_child(0).position.y = 4
	var local: Dictionary = _update(f,Rect2i(0,0,8,8))
	check(local.source_meshes<=8,"local update scans a bounded branch rather than all 512 sources")
	for id: int in far_ids:
		var batch := instance_from_id(id) as Node
		check(batch!=null and batch.get_parent()==batcher,"each distant batch retains identity")
	_check_full_reference(f)
	f.world.free()

func test_cross_chunk_descendants_and_unsupported_parents_are_not_pruned_by_footprint() -> void:
	var f := _fixture()
	_branch(f,Rect2i(0,0,8,8),[2.0,3.0])
	var far := _branch(f,Rect2i(70,0,8,8),[70.0,71.0])
	var parent := MeshInstance3D.new()
	parent.mesh = f.mesh
	parent.position.x = 70
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = "shader_type spatial; void fragment() { ALBEDO = vec3(0.8); }"
	parent.material_override = material
	far.add_child(parent)
	for x: float in [-66.0,-65.0]:
		var child := MeshInstance3D.new()
		child.mesh = f.mesh
		child.position = Vector3(x,2,3)
		parent.add_child(child)
	for chunk: int in range(4,64):
		_branch(f,Rect2i(chunk*32,0,8,8),[chunk*32+2.0,chunk*32+3.0])
	var batcher: Node3D = f.batcher
	batcher.rebuild(f.roots)
	f.sources.get_child(0).get_child(0).position.y = 4
	var local: Dictionary = _update(f,Rect2i(0,0,8,8))
	check(local.source_meshes<=10,"only intersecting actual descendant chunks require source scans")
	var near_count := 0
	for batch: Node in batcher.get_children():
		if batch.get_meta("chunk")==Vector2i.ZERO: near_count += batch.get_meta("source_ids").size()
	check_eq(near_count,4,"far ownership contains two actual near descendants")
	check(parent.visible,"unsupported visual parent stays visible")
	_check_full_reference(f)
	f.world.free()

func test_touched_branch_reindexes_moving_new_and_removed_sources_with_negative_chunks() -> void:
	var f := _fixture()
	var changed := _branch(f,Rect2i(-4,0,8,8),[-4.0,-3.0,2.0,3.0])
	_branch(f,Rect2i(70,0,8,8),[70.0,71.0])
	var batcher: Node3D = f.batcher
	batcher.rebuild(f.roots)
	batcher.set_domain_visible(&"buildings",false)
	changed.get_child(0).position.x = 72
	var removed: Node = changed.get_child(1)
	changed.remove_child(removed)
	removed.free()
	var added := MeshInstance3D.new()
	added.mesh = f.mesh
	added.position = Vector3(-5,2,3)
	changed.add_child(added)
	_update(f,Rect2i(-4,0,8,8))
	_check_full_reference(f)
	# A second unannounced transform change in the touched owner must replace
	# its cached actual chunks again rather than reuse the preceding union.
	changed.get_child(0).position.x = -6
	_update(f,Rect2i(-4,0,8,8))
	_check_full_reference(f)
	f.world.free()

func test_procedural_world_origin_follows_actual_chunks_and_replaced_owners() -> void:
	var f := _fixture()
	_branch(f,Rect2i(0,0,8,8),[2.0,3.0])
	var far := _branch(f,Rect2i(90,0,8,8),[0.0,0.0])
	var batcher: Node3D = f.batcher
	batcher.rebuild(f.roots)
	# Sources carry world-space geometry but retain an origin near zero.
	far.get_child(0).position.y = 5
	_update(f,Rect2i(90,0,8,8))
	_check_full_reference(f)
	for replacement: int in 12:
		f.sources.remove_child(far)
		far.free()
		far = _branch(f,Rect2i(90,0,8,8),[0.0,float(replacement%2)])
		_update(f,Rect2i(90,0,8,8))
		check_eq(batcher.statistics.source_meshes,4,"removed ownership inventory does not skip new procedural sources")
	_check_full_reference(f)
	f.world.free()
