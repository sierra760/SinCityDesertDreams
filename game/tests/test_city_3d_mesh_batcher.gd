# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Exact world geometry/material state, chunk bounds and reversible cleanup.
extends "res://tests/exploration/async_test_case.gd"

const Batcher := preload("res://scripts/view/city_mesh_batcher_3d.gd")


func test_batches_preserve_world_state_and_cleanup() -> void:
	await _independent_visibility_domains()
	await _equivalent_transforms_and_cleanup()
	await _material_and_render_state_isolation()
	await _unsupported_sources_stay_visible()
	await _exact_palm_resource_cache()
	await _network_palm_crowns_batch_without_material_changes()
	await _view_refresh_preserves_geometry_for_service_flags()
	if DisplayServer.get_name() == "headless":
		print("Coverage: CPU upload transforms verified; Dummy renderer has no GPU transform readback. Run rendered for that additional check.")


func _equivalent_transforms_and_cleanup() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var lots := Node3D.new()
	lots.transform = Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3(1.2, 0.8, 1.1)), Vector3(2, 4, 1))
	world.add_child(lots)
	var batcher := Batcher.new()
	batcher.position = Vector3(-3, 1, 2)
	world.add_child(batcher)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 2, 3)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.2, 0.1)
	mesh.material = material
	var sources: Array[MeshInstance3D] = []
	var transforms: Dictionary = {}
	var collision_ids: PackedInt64Array = []
	for x: float in [5.0, 8.0, 72.0, 75.0]:
		var source := MeshInstance3D.new()
		source.mesh = mesh
		source.transform = Transform3D(Basis(Vector3.UP, x * 0.03).scaled(Vector3(1.0, 1.4, 0.7)), Vector3(x, 2, 3))
		lots.add_child(source)
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		body.add_child(shape)
		source.add_child(body)
		collision_ids.append(body.get_instance_id())
		sources.append(source)
		transforms[source.get_instance_id()] = source.global_transform
	var stats := batcher.rebuild([lots], 32)
	check(stats.batched_instances == 4 and stats.batches == 2, "repeated meshes batch separately in two spatial chunks")
	for replacement: MultiMeshInstance3D in batcher.get_children():
		var mm := replacement.multimesh
		check(mm.mesh == mesh and mm.mesh.surface_get_material(0) == material, "batch retains the exact original geometry and material")
		var ids: PackedInt64Array = replacement.get_meta("source_ids")
		var uploaded: Array = replacement.get_meta("uploaded_transforms")
		var expected_bounds := AABB()
		for i: int in ids.size():
			var actual := replacement.global_transform * (uploaded[i] as Transform3D)
			var expected: Transform3D = transforms[ids[i]]
			check(actual.is_equal_approx(expected), "uploaded nested rotated and nonuniformly scaled world transform is unchanged")
			if DisplayServer.get_name() != "headless":
				check((replacement.global_transform * mm.get_instance_transform(i)).is_equal_approx(expected),
					"actual MultiMesh GPU transform readback matches the original world transform")
			var local_bounds: AABB = (replacement.global_transform.affine_inverse() * expected) * mesh.get_aabb()
			expected_bounds = local_bounds if i == 0 else expected_bounds.merge(local_bounds)
		check(mm.custom_aabb.is_equal_approx(expected_bounds), "chunk AABB encloses exactly its transformed mesh instances")
		check(mm.custom_aabb.size.x < 12.0, "distant chunks do not share a city-wide culling box")
	for source: MeshInstance3D in sources:
		check(not source.visible and source.mesh == mesh, "only the original visual visibility changes")
	for id: int in collision_ids:
		var body := instance_from_id(id) as StaticBody3D
		check(body != null and body.collision_layer == 2 and body.get_child_count() == 1, "existing physical/query body survives batching")
	batcher.clear()
	check(batcher.get_child_count() == 0, "clear detaches all replacement batches immediately")
	for source: MeshInstance3D in sources:
		check(source.visible and source.global_transform.is_equal_approx(transforms[source.get_instance_id()]), "clear restores the exact visible source")
	batcher.rebuild([lots], 32)
	check(batcher.get_child_count() == 2, "a repeated rebuild does not duplicate batches")
	batcher.queue_free()
	await process_frame
	for source: MeshInstance3D in sources:
		check(source.visible, "removing the batcher restores its live sources")
	world.queue_free()
	await process_frame
	await process_frame


func _material_and_render_state_isolation() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var lots := Node3D.new()
	world.add_child(lots)
	var batcher := Batcher.new()
	world.add_child(batcher)
	var mesh := BoxMesh.new()
	var red := StandardMaterial3D.new()
	red.albedo_color = Color.RED
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color.BLUE
	mesh.material = red
	var originals: Array[MeshInstance3D] = []
	for group: int in 4:
		for i: int in 2:
			var source := MeshInstance3D.new()
			source.mesh = mesh
			source.position = Vector3(4 + group * 3 + i, 1, 4)
			if group == 1:
				source.set_surface_override_material(0, blue)
			elif group == 2:
				source.material_override = blue
			elif group == 3:
				source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				source.layers = 4
				source.lod_bias = 2.0
			lots.add_child(source)
			originals.append(source)
	var before_arrays := mesh.surface_get_arrays(0).duplicate(true)
	var stats := batcher.rebuild([lots])
	check(stats.batches == 4 and stats.batched_instances == 8, "surface/global material and render-state differences produce distinct groups")
	var surface_override_seen := false
	var shadow_group_seen := false
	for replacement: MultiMeshInstance3D in batcher.get_children():
		var ids: PackedInt64Array = replacement.get_meta("source_ids")
		var original := instance_from_id(ids[0]) as MeshInstance3D
		var effective: Material = replacement.material_override if replacement.material_override != null else replacement.multimesh.mesh.surface_get_material(0)
		check(effective == original.get_active_material(0), "each replacement uses the same effective material")
		check(replacement.cast_shadow == original.cast_shadow and replacement.layers == original.layers and is_equal_approx(replacement.lod_bias, original.lod_bias),
			"shadow, view layers and automatic-LOD bias are preserved")
		if original.get_surface_override_material(0) != null:
			surface_override_seen = true
			check(replacement.multimesh.mesh != mesh, "surface override uses an isolated mesh resource")
			check(replacement.multimesh.mesh.surface_get_arrays(0) == before_arrays, "surface override preserves all geometry arrays including UVs")
		if original.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadow_group_seen = true
	check(surface_override_seen and shadow_group_seen, "material and shadow controls executed")
	check(mesh.material == red and mesh.surface_get_arrays(0) == before_arrays, "source mesh/material data is never rewritten")
	world.queue_free()
	await process_frame
	await process_frame


func _unsupported_sources_stay_visible() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var lots := Node3D.new()
	world.add_child(lots)
	var batcher := Batcher.new()
	world.add_child(batcher)
	var mesh := BoxMesh.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; void fragment() { ALBEDO = vec3(0.8); }"
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	var sources: Array[MeshInstance3D] = []
	for kind: int in 7:
		for i: int in 2:
			var source := MeshInstance3D.new()
			source.mesh = mesh
			source.position = Vector3(kind * 3 + i, 0, 4)
			match kind:
				0: source.material_override = shader_material
				1: source.scale.x = -1.0
				2: source.visibility_range_end = 100.0
				3: source.skin = Skin.new()
				4: source.custom_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
				5: source.visible = false
			lots.add_child(source)
			if kind == 6:
				var child := MeshInstance3D.new()
				child.mesh = mesh
				child.material_override = shader_material
				source.add_child(child)
			sources.append(source)
	var stats := batcher.rebuild([lots])
	check(stats.source_meshes == 16 and stats.batched_instances == 0, "unsupported shader/skinned/mirrored/LOD/custom-bound and visual-parent nodes remain unbatched")
	for i: int in sources.size():
		check(sources[i].visible == (i != 10 and i != 11), "batcher preserves visibility of unbatched and originally hidden sources")
	world.queue_free()
	await process_frame
	await process_frame


func _exact_palm_resource_cache() -> void:
	var palm_script := preload("res://scripts/view/city_palm_3d.gd")
	var a := palm_script.create(0.7, 0.18, 2)
	var b := palm_script.create(0.7, 0.18, 2)
	var c := palm_script.create(0.7, 0.19, 2)
	var d := palm_script.create(0.7, 0.18, 3)
	check(a.get_child(0).mesh == b.get_child(0).mesh and a.get_child(2).mesh == b.get_child(2).mesh,
		"identical palm parameters reuse exact trunk and crown geometry")
	check(a.get_child(0).material_override == b.get_child(0).material_override,
		"palm trunk material is shared without recoloring")
	check(a.get_child(2).mesh != c.get_child(2).mesh and a.get_child(2).mesh != d.get_child(2).mesh,
		"different crown size or variant does not share approximated geometry")
	check(a.get_node("PalmTrunk") != b.get_node("PalmTrunk"), "every palm retains an independent physical trunk body")
	var first := a.get_node("PalmTrunk").get_child(0) as CollisionShape3D
	var second := b.get_node("PalmTrunk").get_child(0) as CollisionShape3D
	check(first.shape != second.shape and is_equal_approx(first.shape.height, second.shape.height),
		"geometry caching leaves the physical trunk shapes and dimensions intact")
	for palm: Node3D in [a, b, c, d]:
		palm.free()
	await process_frame


func _network_palm_crowns_batch_without_material_changes() -> void:
	var city := City.new()
	TerrainSurface.new(4).project(city)
	city.building.put(5, 5, Buildings.TREES_1)
	city.building.put(7, 5, Buildings.TREES_1)
	var before := SaveFormat.encode_city(city)
	var world := Node3D.new()
	root.add_child(world)
	var networks := CityNetworks3D.new()
	world.add_child(networks)
	networks.rebuild(city)
	var batcher := Batcher.new()
	world.add_child(batcher)
	var crowns: Array[MeshInstance3D] = []
	var materials: Dictionary = {}
	var arrays: Dictionary = {}
	for palm: Node3D in networks.get_children():
		var crown := palm.get_child(2) as MeshInstance3D
		crowns.append(crown)
		materials[crown.mesh] = crown.mesh.surface_get_material(0)
		arrays[crown.mesh] = crown.mesh.surface_get_arrays(0)
	var stats := batcher.rebuild([networks])
	check(crowns.size() == 8 and stats.batched_instances == 16,
		"two actual grove cells batch every trunk and crown, not just the trunks")
	var all_hidden := true
	for crown: MeshInstance3D in crowns:
		all_hidden = all_hidden and not crown.visible
	check(all_hidden, "every original grove crown has an attached batch replacement")
	var crown_batches := 0
	for replacement: MultiMeshInstance3D in batcher.get_children():
		var mesh := replacement.multimesh.mesh
		if not materials.has(mesh):
			continue
		crown_batches += 1
		check(mesh.surface_get_material(0) == materials[mesh] and mesh.surface_get_arrays(0) == arrays[mesh],
			"crown batching preserves the exact shader material, colors, normals and vertices")
	check(crown_batches == 4, "four distinct authored palm variants retain separate exact batches")
	batcher.clear()
	var material := crowns[0].mesh.surface_get_material(0) as ShaderMaterial
	var untrusted := material.duplicate() as ShaderMaterial
	check(not Batcher._material_supported(untrusted), "an identical-looking unregistered shader material is not admitted")
	material.set_shader_parameter("grain_strength", 0.01)
	batcher.rebuild([networks])
	check(crowns[0].visible, "world-grain palm material stays outside the static detail allowance")
	material.set_shader_parameter("grain_strength", 0.0)
	material.set_shader_parameter("surface_kind", CityGeometry3D.SurfaceKind.NETWORK)
	batcher.rebuild([networks])
	check(crowns[0].visible, "network-mode material stays outside the static palm allowance")
	material.set_shader_parameter("surface_kind", CityGeometry3D.SurfaceKind.DETAIL)
	var original_shader := material.shader
	var changed_shader := Shader.new()
	changed_shader.code = "shader_type spatial; void vertex() { VERTEX.x += TIME; }"
	material.shader = changed_shader
	batcher.rebuild([networks])
	check(crowns[0].visible, "a replaced animated shader is rejected even on a registered material")
	material.shader = original_shader
	batcher.rebuild([networks])
	check(not crowns[0].visible and batcher.statistics.batched_instances == 16,
		"restoring the exact static palm material restores complete batching")
	check(SaveFormat.encode_city(city) == before, "grove batching and rejection checks never mutate city bytes")
	world.queue_free()
	await process_frame
	await process_frame


func _view_refresh_preserves_geometry_for_service_flags() -> void:
	var city := City.new()
	TerrainSurface.new(4).project(city)
	city.stamp_building(60, 60, Buildings.RES_1X1_FIRST)
	city.stamp_building(62, 60, Buildings.RES_1X1_FIRST)
	city.set_flag(60, 60, TileFlags.CONDUCTS_POWER, true)
	city.set_flag(62, 60, TileFlags.CONDUCTS_POWER, true)
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	await process_frame
	check(view.mesh_batches.statistics.batched_instances > 0, "actual authored buildings and their palms enter shared batches")
	var authored_meshes := view.buildings.get_child(0).get_child(0).find_children("*", "MeshInstance3D", true, false)
	var authored_hidden := not authored_meshes.is_empty()
	for mesh: MeshInstance3D in authored_meshes:
		authored_hidden = authored_hidden and not mesh.visible
	check(authored_hidden, "every repeated authored GLB mesh enters a batch independently of lot palms")
	check(view.buildings.get_child_count() == 2, "batch root does not change canonical building child counts")
	var model_id := view.buildings.get_child(0).get_instance_id()
	var terrain_id := view.chunks.get_child(0).get_instance_id()
	check(view.feedback.power_warning_count() == 2, "actual view starts with both unpowered utility warnings")
	city.set_flag(60, 60, TileFlags.POWERED | TileFlags.WATERED, true)
	var before := SaveFormat.encode_city(city)
	view.refresh()
	check(view.buildings.get_child(0).get_instance_id() == model_id and view.chunks.get_child(0).get_instance_id() == terrain_id,
		"powered/watered changes do not rebuild static buildings or terrain")
	check(view.feedback.power_warning_count() == 1, "service-only refresh still updates power warnings")
	check(SaveFormat.encode_city(city) == before, "batching and service refresh leave the complete city payload unchanged")
	city.flags.put(60, 60, city.flags.at(60, 60) ^ RotationMapper.AXIS_FLAG)
	before = SaveFormat.encode_city(city)
	view.refresh()
	check(view.buildings.get_child(0).get_instance_id() != model_id, "orientation flag changes still rebuild transformed model geometry")
	check(SaveFormat.encode_city(city) == before, "orientation rebuild never edits source city data")
	view.queue_free()
	await process_frame
	await process_frame


func _independent_visibility_domains() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var batcher := Batcher.new()
	world.add_child(batcher)
	var roots: Array[Node3D] = []
	var mesh := BoxMesh.new()
	for domain: StringName in [&"buildings",&"networks"]:
		var source_root := Node3D.new()
		source_root.set_meta("batch_domain",domain)
		world.add_child(source_root)
		roots.append(source_root)
		for i: int in 2:
			var source := MeshInstance3D.new()
			source.mesh = mesh
			source.position = Vector3(i,0,0)
			source_root.add_child(source)
	var stats := batcher.rebuild(roots)
	check(stats.batches == 2, "identical mesh resources in different domains never merge")
	var ids := batcher.get_children().map(func(node): return node.get_instance_id())
	batcher.set_domain_visible(&"buildings",false)
	for batch: Node3D in batcher.get_children():
		check(batch.visible == (batch.get_meta("domain") == &"networks"), "domains toggle independently")
	batcher.set_domain_visible(&"buildings",true)
	check(batcher.get_children().map(func(node): return node.get_instance_id()) == ids, "visibility restoration does not rebuild batches")
	world.free()
	await process_frame
	await process_frame
