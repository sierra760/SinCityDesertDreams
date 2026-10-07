# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func test_explore_camera_survives_view_refresh_and_resize() -> void:
	root.size = Vector2i(1280,800)
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(flat_city())
	var perspective := Camera3D.new()
	view.world.add_child(perspective)
	perspective.position = Vector3(10.5,3,10.5)
	perspective.rotation = Vector3(-.2,.3,0)
	view.set_exploration_camera(perspective)
	var pose := perspective.transform
	var aerial_pose := view.camera.transform
	view._update_camera()
	view._root_resized()
	check_eq(perspective.transform,pose)
	check_eq(view.camera.transform,aerial_pose)
	check(perspective.current and not view.camera.current)
	check(not bool(view.get("aerial_controls_enabled")))
	view.clear_exploration_camera()
	check(view.camera.current and not perspective.current)
	check(bool(view.get("aerial_controls_enabled")))
	view.free()
	await process_frame

func test_geometry_snapshot_is_revision_scoped() -> void:
	var view := CityView3D.new()
	root.add_child(view)
	check(view.has_signal("geometry_rebuilt"),"physical owner receives finished revisions")
	var data: Dictionary = view.traversal_snapshot()
	check(data.has("chunks") and data.has("networks") and data.has("revision"))
	view.free()
	await process_frame
