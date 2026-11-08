# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func test_resolution_preserves_ui_camera_city_and_live_picking() -> void:
	root.size = Vector2i(1400,1000)
	var city := flat_city()
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	view.set_camera_state(Vector3(64.5,CityGeometry3D.surface_height(city,Vector2i(64,64)),64.5),0,20)
	var layout := DisplayLayout.new()
	view.bind_display_layout(layout)
	layout.refresh_with_metrics(Vector2i(2560,1600),2.0)
	var encoded := SaveFormat.encode_city(city)
	var geometry := view.traversal_snapshot()
	var camera_state := [view.center,view.camera_size,view.quarter_turn]
	var logical_size := view.container.size
	for scale: int in [100,75,50]:
		for quality: String in ["high","balanced","performance"]:
			view.set_render_options(quality,scale)
			await physics_frame
			await process_frame
			check_eq(view.viewport.size,Vector2i(2560*scale/100,1600*scale/100))
			check_eq(view.container.size,logical_size,"UI dimensions unchanged")
			check_eq([view.center,view.camera_size,view.quarter_turn],camera_state)
			check_eq(view.traversal_snapshot().revision,geometry.revision,"no geometry rebuild")
			for cell: Vector2i in [Vector2i(64,64),Vector2i(66,65)]:
				check_eq(view.pick_cell(view.project_cell(cell)),cell,"live ray uses actual render resolution")
			check_eq(SaveFormat.encode_city(city),encoded)
	view.set_render_options("high",100)
	check_eq(view.viewport.msaa_3d,Viewport.MSAA_4X)
	check_eq(view.viewport.mesh_lod_threshold,1.0)
	for child: Node in view.world.get_children():
		if child is DirectionalLight3D:
			check(child.shadow_enabled)
			check_eq(child.directional_shadow_max_distance,400.0)
	view.free()
	layout.free()

func test_explore_uses_small_native_pixel_detail_error_and_restores_build() -> void:
	var view := CityView3D.new()
	root.add_child(view)
	var actor_camera := Camera3D.new()
	view.world.add_child(actor_camera)
	for quality: String in ["high","balanced","performance"]:
		for scale: int in [50,75,100]:
			view.set_render_options(quality,scale)
			var build_threshold := view.viewport.mesh_lod_threshold
			view.set_exploration_camera(actor_camera)
			var native_error := view.viewport.mesh_lod_threshold*100.0/scale
			check(native_error<=1.0,"Explore mesh changes stay within a native pixel at every render scale")
			check(view.viewport.mesh_lod_threshold<build_threshold,"Explore retains geometry beyond aerial detail distances")
			view.set_render_options(quality,scale)
			check(view.viewport.mesh_lod_threshold*100.0/scale<=1.0,"quality updates retain Explore detail")
			view.clear_exploration_camera()
			check_eq(view.viewport.mesh_lod_threshold,build_threshold,"Build restores its original detail budget")
	view.free()
