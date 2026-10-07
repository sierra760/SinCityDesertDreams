# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Physical contacts traverse the root viewport and live city physics picker.
## A shifted construction ray or a second DPI/safe-area conversion breaks this.
extends "res://tests/exploration/async_test_case.gd"

var view: CityView3D
var owner: CityPresentationController
var layout: DisplayLayout
var starts: Array[Vector2i] = []
var updates: Array[Vector2i] = []
var commits: Array[Vector2i] = []
var queries: Array[Vector2i] = []

func before_all() -> void:
	layout = DisplayLayout.new()
	root.add_child(layout)
	layout.bind(root)
	view = CityView3D.new()
	root.add_child(view)
	view.bind_display_layout(layout)
	owner = CityPresentationController.new()
	owner.view = view
	root.add_child(owner)
	owner.bind_city(flat_city())
	view.set_active(true)
	owner.drag_started.connect(func(_a, b): starts.append(b))
	owner.drag_updated.connect(func(_a, b): updates.append(b))
	owner.drag_ended.connect(func(_a, b): commits.append(b))
	owner.tile_clicked.connect(func(tile, _button): queries.append(tile))
	await process_frame
	await physics_frame

func after_all() -> void:
	owner.free()
	view.free()
	layout.free()

func send_contact(pressed: bool, cell: Vector2i) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = pressed
	# project_cell describes where the cell is actually drawn. Supply native
	# drawable pixels to the engine, rather than calling the owner directly.
	event.position = view.project_cell(cell) * float(layout.metrics.scale)
	root.push_input(event, false)

func send_drag(cell: Vector2i) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = view.project_cell(cell) * float(layout.metrics.scale)
	root.push_input(event, false)

func test_build_contact_alignment_across_mobile_displays() -> void:
	owner.select_tool(Tools.Kind.ROAD)
	for display: Array in [
		[Vector2i(1170,2532),3.0,Rect2i(0,141,1170,2289)],
		[Vector2i(2532,1170),3.0,Rect2i(141,0,2250,1107)],
		[Vector2i(1668,2388),2.0,Rect2i(0,48,1668,2300)],
		[Vector2i(2388,1668),2.0,Rect2i(0,48,2388,1580)],
	]:
		root.size = display[0]
		for percent: int in [100,150]:
			layout.ui_scale = percent
			layout.refresh_with_mobile_metrics(display[0],display[1],display[2])
			for resolution: int in [50,75,100]:
				view.set_render_options("balanced",resolution)
				for rotation: int in 4:
					view.set_camera_state(Vector3(64.5,CityGeometry3D.surface_height(view.city,Vector2i(64,64)),64.5),rotation,24)
					await process_frame
					await physics_frame
					starts.clear()
					updates.clear()
					commits.clear()
					send_contact(true,Vector2i(64,64))
					check_eq(starts,[Vector2i(64,64)] as Array[Vector2i],"press begins at contacted cell")
					send_drag(Vector2i(66,64))
					check_eq(updates,[Vector2i(66,64)] as Array[Vector2i],"drag tracks contacted cell")
					send_contact(false,Vector2i(67,64))
					check_eq(commits,[Vector2i(67,64)] as Array[Vector2i],"release commits at final contact")

func test_query_and_build_use_the_same_physical_contact() -> void:
	root.size = Vector2i(1170,2532)
	layout.ui_scale = 100
	layout.refresh_with_mobile_metrics(root.size,3.0,Rect2i(0,141,1170,2289))
	view.set_camera_state(Vector3(64.5,CityGeometry3D.surface_height(view.city,Vector2i(64,64)),64.5),0,24)
	await process_frame
	await physics_frame
	queries.clear()
	owner.select_tool(Tools.Kind.QUERY)
	send_contact(true,Vector2i(64,64))
	check(queries.is_empty(),"Query waits for release")
	send_contact(false,Vector2i(64,64))
	check_eq(queries,[Vector2i(64,64)] as Array[Vector2i])
	starts.clear()
	commits.clear()
	owner.select_tool(Tools.Kind.ROAD)
	send_contact(true,Vector2i(64,64))
	send_contact(false,Vector2i(64,64))
	check_eq(starts,[Vector2i(64,64)] as Array[Vector2i])
	check_eq(commits,[Vector2i(64,64)] as Array[Vector2i])
