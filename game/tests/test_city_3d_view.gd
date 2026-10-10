# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Live physics picking and camera controls exercise the same viewport as the game.
extends "res://tests/exploration/async_test_case.gd"


func _snapshot(city: City) -> PackedByteArray:
	return var_to_bytes([city.altitude.data, city.terrain.data, city.building.data,
		city.zone.data, city.flags.data, city.underground.data, city.flood_overlay,
		city.day, city.funds, city.rotation, city.facilities, city.signs])


func test_live_picking_and_camera_controls() -> void:
	root.size = Vector2i(1152, 720)
	var city := City.new()
	city.altitude.data.fill(4)
	city.stamp_building(64, 64, Buildings.RES_2X2_FIRST)
	for y: int in range(56, 61):
		for x: int in range(56, 61):
			city.terrain.put(x, y, Terrain.SURFACE)
			city.set_heights(x, y, 2, 5)
	city.signs[Vector2i(62, 62)] = "Desert Avenue"
	var before := _snapshot(city)
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	view.set_center_cell(Vector2i(64, 64))
	view.set_zoom_level(4)
	await process_frame
	await physics_frame
	await process_frame
	check(view.active and view.layer == -1, "3D view appears behind the existing interface")
	# Every building code from the first 1x1 lot through the last resort has a model.
	var covered := view.catalog.entries.size() == Buildings.COUNT - Buildings.RES_1X1_FIRST
	for code: int in range(Buildings.RES_1X1_FIRST, Buildings.COUNT):
		covered = covered and view.catalog.entries.has(code)
	check(covered and view.buildings.missing.is_empty(), "the complete authored catalog is available")
	check(not view.notice.visible, "complete models do not display a placeholder warning")
	check(view.viewport.size.x > 0 and view.viewport.size.y > 0, "viewport has usable dimensions")
	var layout := DisplayLayout.new()
	root.add_child(layout)
	view.bind_display_layout(layout)
	var camera_before := [view.center, view.quarter_turn, view.camera_size]
	for output: Vector2i in [Vector2i(1000,640),Vector2i(1280,800),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]:
		for backing: float in [1.0,2.0]:
			for percent: int in [0,100,125,150,175,200]:
				layout.ui_scale = percent
				layout.refresh_with_metrics(output,backing)
				check(view.viewport.size == output, "native output is independent of logical UI scale")
				check(view.container is TextureRect and view.container.size.is_equal_approx(layout.logical_rect().size), "native texture fits logical bounds once")
				check([view.center,view.quarter_turn,view.camera_size] == camera_before, "display changes preserve camera")
				for rotation: int in 4:
					view.set_camera_state(view.center,rotation,16)
					await physics_frame
					await process_frame
					var selected := Vector2i(68,66)
					check(view.pick_cell(view.project_cell(selected),0) == selected, "logical project/pick roundtrip for output, backing, scale and rotation")
				view.set_camera_state(camera_before[0],camera_before[1],camera_before[2])
	# Unbind the synthetic metrics for the remaining checks.
	view.bind_display_layout(null)
	layout.free()
	var focus := Vector2i(64, 64)
	for rotation: int in 4:
		view.set_camera_state(view.center, rotation, 16.0)
		await physics_frame
		await process_frame
		for cell: Vector2i in [Vector2i(62, 62), Vector2i(68, 66), focus]:
			check(view.pick_cell(view.project_cell(cell), 0) == cell, "terrain roundtrip rotation %d cell %s" % [rotation, cell])
		check(view.pick_cell(view.project_cell(focus), 1) == focus, "building query returns canonical anchor under rotation %d" % rotation)
		var origin := view.project_cell(Vector2i(62, 62))
		var dx := view.project_cell(Vector2i(63, 62)) - origin
		check(is_equal_approx(absf(dx.y / dx.x), 0.5), "camera preserves the 2:1 isometric diamond")
	for rotation: int in 4:
		var wet := Vector2i(58, 58)
		view.set_center_cell(wet)
		view.set_camera_state(view.center, rotation, 16.0)
		await physics_frame
		await process_frame
		check(view.pick_cell(view.project_cell(wet), 0) == wet, "water roundtrip uses surface rather than seabed at rotation %d" % rotation)
		view.show_cells([wet], true)
		var outline: MultiMeshInstance3D = view.cursor.get_child(0)
		check(outline.multimesh.buffer[7] > CityGeometry3D.water_surface_height(city, wet), "water placement preview stays above the visible material")
	view.clear_cursor()
	view.set_center_cell(focus)
	check(view.pick_cell(Vector2(-30, -30), 1) == Vector2i(-1, -1), "outside viewport picks nothing")
	var proxy: StaticBody3D = view.buildings.get_child(0).get_node("BuildingQuery")
	check(proxy.collision_layer == 2 and proxy.collision_mask == 0, "canonical query body is isolated")
	var shell := StaticBody3D.new()
	shell.collision_layer = 4
	shell.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1, 1)
	collision.shape = box
	shell.add_child(collision)
	view.world.add_child(shell)
	var ground := Vector3(62.5, CityGeometry3D.ground_height(city, Vector2i(62, 62)), 62.5)
	shell.position = ground + (view.camera.position - ground).normalized() * 2.0
	await physics_frame
	await process_frame
	var point := view.project_cell(Vector2i(62, 62))
	check(view.pick_cell(point, 0) == Vector2i(62, 62), "model shells cannot steal terrain placement")
	check(view.pick_cell(point, 1) == Vector2i(62, 62), "model shells cannot steal building queries")
	var local := view.container.get_global_transform_with_canvas().affine_inverse() * point
	local *= Vector2(view.viewport.size) / view.container.size
	var ray_start := view.camera.project_ray_origin(local)
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_start + view.camera.project_ray_normal(local) * 2048.0, 4)
	var hit := view.viewport.find_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.collider == shell, "shells remain available on their own physical layer")
	view.input_blocked = func() -> bool: return true
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	var previous := view.quarter_turn
	view._unhandled_input(key)
	check(view.quarter_turn == previous, "modal guard blocks view rotation")
	view.input_blocked = Callable()
	view.show_cells([Vector2i(62, 62), Vector2i(63, 62)], false)
	check(view.cursor.get_child_count() == 1, "one batched node draws the preview")
	var pair: MultiMeshInstance3D = view.cursor.get_child(0)
	check(pair.multimesh.instance_count == 7, "preview outlines every requested tile, shared edge once")
	check(pair.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "preview outline casts no shadow")
	var rect: Array = []
	for y: int in range(20, 60):
		for x: int in range(20, 60): rect.append(Vector2i(x, y))
	view.show_cells(rect, true)
	check(view.cursor.get_child_count() == 1, "a 40x40 drag remains one node")
	var large: MultiMeshInstance3D = view.cursor.get_child(0)
	check(large.multimesh.instance_count <= 40 * 40 * 4 and large.multimesh.instance_count >= 40 * 41 * 2, "large previews keep every distinct edge")
	check(large.material_override != pair.material_override, "valid and invalid previews keep distinct colors")
	# A terrain edit rebuilds geometry; the same preview follows the new ground.
	var raised := Vector2i(30, 30)
	view.show_cells([raised], true)
	var low_y: float = (view.cursor.get_child(0) as MultiMeshInstance3D).multimesh.buffer[7]
	var original_altitude := city.altitude.at(raised.x, raised.y)
	city.set_heights(raised.x, raised.y, 12)
	view.refresh()
	view.show_cells([raised], true)
	check(view.cursor.get_child_count() == 1, "rebuilt preview replaces the previous outline")
	var high_y: float = (view.cursor.get_child(view.cursor.get_child_count() - 1) as MultiMeshInstance3D).multimesh.buffer[7]
	check(high_y > low_y + 0.1, "unchanged preview tiles redraw at rebuilt ground heights")
	city.altitude.put(raised.x, raised.y, original_altitude)
	view.refresh()
	view.clear_cursor()
	check(view.cursor.get_child_count() == 0, "cursor cleanup removes old preview")
	check(view._labels.get_child_count() == 1, "the sign has one label")
	var sign_label: Label = view._labels.get_child(0)
	var sign_position := sign_label.position
	view.set_camera_state(view.center, view.quarter_turn + 1, view.camera_size)
	check(view._labels.get_child_count() == 1 and view._labels.get_child(0) == sign_label, "camera moves keep the existing sign label")
	check(sign_label.position != sign_position and sign_label.position.is_equal_approx(view.project_cell(Vector2i(62, 62)) + Vector2(0, -24)), "camera moves reposition the sign label")
	check(sign_label.text == "Desert Avenue", "label text follows the sign")
	view.feedback.sync_records([{"kind": &"car", "pos": Vector2(62.2, 62.5), "heading": 2},
		{"kind": &"fire", "tile": Vector2i(63, 63)}, {"kind": &"fire_crew", "tile": Vector2i(64, 63)}])
	check(view.feedback.marker_count() == 2, "fire and response feedback are visible")
	check(view.feedback.traffic.multimesh.visible_instance_count == 1, "normalized traffic records project into the view")
	check(view.feedback._traffic_buffer.size() >= 12, "visible traffic has a packed transform upload")
	view.feedback.sync_records([])
	check(view.feedback.marker_count() == 0 and view.feedback.traffic.multimesh == null, "stale transient feedback is cleared")
	check(_snapshot(city) == before, "rendering, picking, navigation and feedback never mutate the city")
	var model_id := view.buildings.get_child(0).get_instance_id()
	var chunk_id := view.chunks.get_child(0).get_instance_id()
	for mode: StringName in [&"crime", &""]:
		view.set_overlay(mode)
		check(view.buildings.visible == (mode == &"") and view.networks.visible == (mode == &""), "analytical roots cover unbatched models and landscaping")
		for batch: Node3D in view.mesh_batches.get_children():
			check(batch.visible == (mode == &""), "analytical visibility covers both uploaded batch domains")
		check(view.buildings.get_child(0).get_instance_id() == model_id and view.chunks.get_child(0).get_instance_id() == chunk_id, "analytical switches preserve unchanged geometry")
	view.set_underground(true)
	await physics_frame
	check(view.pick_cell(view.project_cell(Vector2i(65,65)),1) == Vector2i(65,65), "underground query bypasses surface building proxy")
	view.set_underground(false)
	check(view.buildings.visible and view.networks.visible, "surface restores both unbatched domains")
	view.set_active(false)
	check(view.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "inactive mode stops rendering")
	check(view.pick_cell(point) == Vector2i(-1, -1), "inactive view cannot receive map picks")
	root.remove_child(view)
	view.free()
	await process_frame
	await process_frame
