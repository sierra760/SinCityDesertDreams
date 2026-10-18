# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A stationary overview retains its canvas commands and corner projections.
extends "res://tests/exploration/async_test_case.gd"

class CountedView extends CityView3D:
	var projections := 0
	func minimap_rect(rotation: int, scale_factor: float) -> Rect2:
		projections += 1
		return super.minimap_rect(rotation, scale_factor)

class Marker extends Node:
	var view: CityView3D
	var position := Vector2(32, 32)
	var heading := Vector2.UP
	var enabled := false
	func minimap_marker() -> Dictionary:
		return {"position": position, "heading": heading} if enabled else {}

func test_idle_overlay_retains_projections_and_hidden_overlay_does_no_work() -> void:
	var view := CountedView.new()
	var overview := MiniMap.new()
	root.add_child(view)
	root.add_child(overview)
	view.city = City.new()
	view.active = true
	overview.view_3d = view
	var draws: Array[int] = [0]
	overview._overlay.draw.connect(func() -> void: draws[0] += 1)
	await _frames(4)
	var before_draws := draws[0]
	var before_projections := view.projections
	await _frames(8)
	check_eq(draws[0], before_draws, "idle overlay keeps its draw commands")
	check_eq(view.projections, before_projections, "idle overlay does not reproject corners")
	view.center.y += 1
	await _frames(3)
	check_gt(view.projections, before_projections, "ground plane changes refresh the frame")
	overview.visible = false
	await _frames(3)
	before_projections = view.projections
	view.center.y += 1
	await _frames(8)
	check_eq(view.projections, before_projections, "hidden overview avoids projection work")
	overview.visible = true
	await _frames(3)
	check_gt(view.projections, before_projections, "showing the overview refreshes changed state")
	overview.free()
	view.free()

func test_overlay_refreshes_for_camera_layout_and_explore_marker_changes() -> void:
	var view := CountedView.new()
	var overview := MiniMap.new()
	var marker := Marker.new()
	root.add_child(view)
	root.add_child(overview)
	root.add_child(marker)
	view.city = City.new()
	view.active = true
	overview.view_3d = view
	marker.view = view
	marker.add_to_group(MiniMap.EXPLORE_MARKER_GROUP)
	var draws: Array[int] = [0]
	overview._overlay.draw.connect(func() -> void: draws[0] += 1)
	await _frames(4)
	for change: int in 10:
		var before := draws[0]
		match change:
			0: view.camera.position.x += 1
			1: view.camera.size += 1
			2: view.quarter_turn = 1
			3: overview.apply_layout(Rect2(0,0,160,160), 0, 0, 0)
			4: marker.enabled = true
			5: marker.position += Vector2(1,0); marker.heading = Vector2.RIGHT
			6: view.viewport.size += Vector2i(24, 16)
			7: view.active = false
			8: view.active = true
			9: view.aerial_controls_enabled = false
		await _frames(3)
		check_gt(draws[0], before, "overlay follows change %d" % change)
	var before := draws[0]
	await _frames(8)
	check_eq(draws[0], before, "stationary Explore marker also keeps canvas commands")
	marker.enabled = false
	await _frames(3)
	check_gt(draws[0], before, "leaving Explore restores the aerial frame")
	marker.free()
	overview.free()
	view.free()

func _frames(count: int) -> void:
	for frame: int in count:
		await process_frame
