# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

class PickView extends CityView3D:
	func pick_cell(_point: Vector2, _purpose: int = 0) -> Vector2i:
		return Vector2i(10,10)

var owner: CityPresentationController
var view: CityView3D

func before_each() -> void:
	root.size = Vector2i(1280,800)
	view = PickView.new()
	root.add_child(view)
	owner = CityPresentationController.new()
	owner.view = view
	root.add_child(owner)
	owner.bind_city(flat_city())

func after_each() -> void:
	owner.free()
	view.free()
	await process_frame

func test_temporary_explore_preserves_automatic_underground_ownership() -> void:
	owner.set_overlay(&"crime")
	owner.select_tool(Tools.Kind.WATER_PIPE)
	var original: Dictionary = owner.capture_state()
	check(bool(original.automatic_underground))
	var emissions: Array = []
	owner.overlay_changed.connect(func(kind: StringName) -> void: emissions.append(kind))
	owner.set_exploration_suspended(true)
	owner.set_overlay(&"water")
	owner.set_view_mode(CityPresentationController.ViewMode.SURFACE)
	check_eq(owner.capture_state(),original,"direct analytical setters are blocked")
	check_eq(emissions.size(),0,"Explore visibility does not write preferences")
	owner.set_exploration_suspended(false)
	owner.restore_state(original)
	owner.select_tool(Tools.Kind.ROAD)
	check(not owner.is_underground())
	check_eq(owner.get_overlay(),&"crime")

func test_suspension_cancels_drag_and_prevents_construction() -> void:
	var clicks: Array = []
	owner.tile_clicked.connect(func(tile: Vector2i,_button: int) -> void: clicks.append(tile))
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	owner._unhandled_input(event)
	check_eq(clicks.size(),1)
	owner.set_exploration_suspended(true)
	check_eq(owner._drag_from,Vector2i(-1,-1))
	owner._unhandled_input(event)
	check_eq(clicks.size(),1)
	owner.set_exploration_suspended(false)
	owner._unhandled_input(event)
	check_eq(clicks.size(),2)

func test_manual_underground_remains_manual_after_restore() -> void:
	owner.set_view_mode(CityPresentationController.ViewMode.UNDERGROUND)
	var original: Dictionary = owner.capture_state()
	owner.set_exploration_suspended(true)
	owner.set_exploration_suspended(false)
	owner.restore_state(original)
	owner.select_tool(Tools.Kind.ROAD)
	check(owner.is_underground())
