# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Imported Blender timelines must really animate their independent instances.
extends "res://tests/exploration/async_test_case.gd"

const KINDS := [&"tornado", &"hurricane", &"monster", &"beam", &"riot", &"plane", &"fire"]

func player_of(visual: Node) -> AnimationPlayer:
	var players := visual.find_children("*", "AnimationPlayer", true, false)
	return players[0] as AnimationPlayer if not players.is_empty() else null

func pose(visual: Node) -> Array:
	var values: Array = []
	for node: Node in visual.find_children("*", "", true, false):
		if node is Node3D: values.append((node as Node3D).transform)
		if node is Skeleton3D:
			for bone in (node as Skeleton3D).get_bone_count(): values.append((node as Skeleton3D).get_bone_pose(bone))
		if node is MeshInstance3D:
			for shape in (node as MeshInstance3D).get_blend_shape_count(): values.append((node as MeshInstance3D).get_blend_shape_value(shape))
			if (node as MeshInstance3D).material_override is ShaderMaterial:
				values.append(((node as MeshInstance3D).material_override as ShaderMaterial).get_shader_parameter(&"playback_seconds"))
	return values

func test_every_model_plays_an_imported_loop_with_visible_pose_changes() -> void:
	for kind: StringName in KINDS:
		var visual := CityDisasterVisual3D.new()
		visual.build(kind)
		root.add_child(visual)
		visual.set_process(false)
		var player := player_of(visual)
		check(player != null, "authored Blender animation imported: " + String(kind))
		if player != null:
			check(player.is_playing(), "timeline starts automatically")
			var animation := player.get_animation(player.current_animation)
			check(animation != null and animation.length >= 4, "substantial authored cycle")
			if animation != null: check_eq(animation.loop_mode, Animation.LOOP_LINEAR, "loop survives export/import")
			var before := pose(visual)
			visual._process(0.73)
			check_ne(pose(visual), before, "actual transform/bone/morph values change")
		visual.free()
	await process_frame

func test_creatures_have_independent_articulated_skeletons() -> void:
	for kind: StringName in [&"monster", &"riot"]:
		var visual := CityDisasterVisual3D.new()
		visual.build(kind)
		root.add_child(visual)
		visual.set_process(false)
		var skeletons := visual.find_children("*", "Skeleton3D", true, false)
		check(not skeletons.is_empty(), "creature has an imported skeleton")
		for skeleton: Skeleton3D in skeletons:
			check(skeleton.get_bone_count() >= (20 if kind == &"monster" else 70), "limbs and appendages have real joints")
			var before: Array[Transform3D] = []
			for bone in skeleton.get_bone_count(): before.append(skeleton.get_bone_pose(bone))
			visual._process(0.59)
			var changed := 0
			for bone in skeleton.get_bone_count():
				if not before[bone].is_equal_approx(skeleton.get_bone_pose(bone)): changed += 1
			check(changed >= 12, "many individual joints animate")
		visual.free()
	await process_frame

func test_weather_deforms_its_sculpted_meshes() -> void:
	for kind: StringName in [&"tornado", &"hurricane", &"beam"]:
		var visual := CityDisasterVisual3D.new()
		visual.build(kind)
		root.add_child(visual)
		visual.set_process(false)
		var before: Dictionary = {}
		for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
			for shape in mesh.get_blend_shape_count(): before[[mesh, shape]] = mesh.get_blend_shape_value(shape)
		check(not before.is_empty(), "sculpted effect contains morph channels")
		visual._process(0.61)
		var changed := 0
		for key: Array in before:
			if not is_equal_approx(before[key], (key[0] as MeshInstance3D).get_blend_shape_value(key[1])): changed += 1
		check(changed > 0, "actual imported sculpt deformation advances")
		visual.free()
	await process_frame

func test_instances_share_assets_but_not_playback_or_owner_transforms() -> void:
	for kind: StringName in KINDS:
		var first := CityDisasterVisual3D.new()
		var second := CityDisasterVisual3D.new()
		first.build(kind); second.build(kind)
		root.add_child(first); root.add_child(second)
		first.set_process(false); second.set_process(false)
		first.position = Vector3(12, 3, 19); first.rotation.y = PI / 2
		var owner := first.transform
		var other_pose := pose(second)
		var a := player_of(first); var b := player_of(second)
		check(a != null and b != null, "two independent imported animation players")
		if a != null and b != null:
			check_eq(a.get_animation(a.current_animation), b.get_animation(b.current_animation), "animation resources are shared")
			first._process(0.83)
			check_eq(pose(second), other_pose, "advancing one instance never changes the other")
		check_eq(first.transform, owner, "animation cannot change city position or heading")
		first.free(); second.free()
	await process_frame

func test_animation_keeps_running_across_multiple_loop_boundaries() -> void:
	for kind: StringName in KINDS:
		var visual := CityDisasterVisual3D.new()
		visual.build(kind)
		root.add_child(visual)
		visual.set_process(false)
		var player := player_of(visual)
		check(player != null, "imported loop exists")
		if player != null:
			var animation := player.get_animation(player.current_animation)
			if animation != null:
				visual._process(animation.length * 2 + 0.47)
				check(player.is_playing(), "cycle does not stop at its end")
				check(absf(player.current_animation_position - 0.47) < 0.0001, "timeline wraps correctly")
		visual.free()
	await process_frame

func test_live_fires_keep_their_animation_when_the_city_or_other_fires_change() -> void:
	var city := flat_city()
	var feedback := CityFeedback3D.new()
	root.add_child(feedback)
	feedback.bind_city(city)
	feedback.sync_records([{ "kind": &"fire", "pos": Vector2(30, 40), "source": &"disasters" }])
	var fire := feedback.markers.get_child(0) as CityDisasterVisual3D
	fire.set_process(false)
	var player := player_of(fire)
	check(player != null, "live fire has authored animation")
	if player != null:
		fire._process(0.81)
		var time := player.current_animation_position
		city.stamp_building(60, 60, Buildings.RES_1X1_FIRST)
		feedback.sync_records([{ "kind": &"fire", "pos": Vector2(30, 40), "source": &"disasters" },
			{ "kind": &"fire", "pos": Vector2(31, 40), "source": &"disasters" }])
		check_eq(feedback.markers.get_child(0), fire, "existing fire survives city edits and new outbreaks")
		check_eq(player.current_animation_position, time, "ongoing clip never restarts during feedback refresh")
		check_eq(feedback.marker_count(), 2)
		feedback.sync_records([])
		check_eq(feedback.marker_count(), 0, "ended fires disappear immediately")
	feedback.free()
	await process_frame

func test_fire_draw_cost_stays_bounded_for_city_wide_firestorms() -> void:
	var visual := CityDisasterVisual3D.new()
	visual.build(&"fire")
	root.add_child(visual)
	visual.set_process(false)
	var surfaces := 0
	var shapes := 0
	var meshes := visual.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		surfaces += mesh.mesh.get_surface_count()
		shapes += mesh.get_blend_shape_count()
	check(meshes.size() == 1, "firestorm must not instantiate dozens of separately drawn pieces per tile")
	check(surfaces == 1, "all fire palettes share one drawn surface")
	check(shapes == 0, "baked fire playback avoids per-instance Compatibility morph feedback")
	check(visual.find_children("*", "Skeleton3D", true, false).is_empty(), "baked fire playback avoids per-instance skeletal feedback")
	visual.free()
	await process_frame


func test_fire_atlas_preserves_authored_frames_and_material_playback() -> void:
	var material := CityDisasterVisual3D.fire_material()
	var positions := material.get_shader_parameter(&"motion_positions") as Texture2D
	var normals := material.get_shader_parameter(&"motion_normals") as Texture2D
	check(positions != null and normals != null, "shared Blender vertex animation textures are imported")
	if positions == null or normals == null: return
	var image := positions.get_image()
	var normal_image := normals.get_image()
	check_eq(image.get_size(), Vector2i(1024, 2405), "all 481 frames retain five vertex rows")
	check_eq(normal_image.get_size(), image.get_size(), "matching normal atlas")
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/desert-dreams-disasters/provenance.json"))
	var record: Dictionary = provenance.models.fire.vertex_animation
	for landmark: Dictionary in record.landmarks:
		var first := image.get_pixel(0, int(landmark.frame) * int(record.rows_per_frame))
		var expected: Array = landmark.vertex0_position
		check(Vector3(first.r, first.g, first.b).distance_to(Vector3(expected[0], expected[1], expected[2])) < 0.0001, "actual Godot import retains atlas orientation and signed positions")
		var normal := normal_image.get_pixel(0, int(landmark.frame) * int(record.rows_per_frame))
		var expected_normal: Array = landmark.vertex0_normal
		check(Vector3(normal.r, normal.g, normal.b).distance_to(Vector3(expected_normal[0], expected_normal[1], expected_normal[2])) < 0.0001, "actual Godot import retains authored normal vectors and their frame orientation")
		var last_index := int(record.vertex_count) - 1
		var last := image.get_pixel(last_index % 1024, int(landmark.frame) * 5 + last_index / 1024)
		var expected_last: Array = landmark.last_vertex_position
		check(Vector3(last.r, last.g, last.b).distance_to(Vector3(expected_last[0], expected_last[1], expected_last[2])) < 0.0001, "moving particle frame survives texture import")
	await process_frame
