# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"


class PickView extends CityView3D:
	var picked := Vector2i(8, 9)
	var purpose_seen := -1
	func pick_cell(_point: Vector2, purpose: int = 0) -> Vector2i:
		purpose_seen = purpose
		return picked

func test_input_routing_through_3d_view() -> void:
	var owner: Node = CityPresentationController.new()
	root.add_child(owner)
	var view := PickView.new()
	owner.view = view
	var city := City.new()
	owner.bind_city(city)
	var before := SaveFormat.encode_city(city)
	var order: Array[String] = []
	owner.tile_clicked.connect(func(_tile, _button): order.append("click"))
	owner.drag_started.connect(func(_from, _to): order.append("start"))
	owner.drag_ended.connect(func(_from, to): order.append(str(to)))
	var hover: Array = []
	owner.tile_hovered.connect(func(tile): hover.append(tile))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	owner._unhandled_input(press)
	check(order == ["click", "start"] and view.purpose_seen == 1, "right query clicks before starting its drag")
	var motion := InputEventMouseMotion.new()
	view.picked = Vector2i(10, 11)
	owner._unhandled_input(motion)
	owner._unhandled_input(motion)
	check(hover == [Vector2i(10, 11)], "same hover is filtered")
	view.picked = Vector2i(-1, -1)
	press.pressed = false
	owner._unhandled_input(press)
	check(order.back() == str(Vector2i(10, 11)), "off-map release retains the last valid cell")
	view.picked = Vector2i(8, 9)
	press.pressed = true
	owner._unhandled_input(press)
	owner.cancel_drag()
	var count := order.size()
	press.pressed = false
	owner._unhandled_input(press)
	check(order.size() == count, "cancelled release is inert")
	owner.set_overlay(&"crime")
	owner.select_tool(Tools.Kind.WATER_PIPE)
	check(owner.is_underground(), "utility selection automatically enters underground")
	owner.set_overlay(&"water")
	owner.select_tool(Tools.Kind.ROAD)
	check(not owner.is_underground() and owner.get_overlay() == &"water", "surface tool restores explicitly updated analytical view")
	owner.set_overlay(&"nonsense")
	check(owner.get_overlay() == &"water", "unknown overlay selection is inert")
	owner.set_overlay(&"none")
	check(owner.get_overlay() == &"", "None clears canonical analytical selection")
	owner.set_view_mode(1)
	owner.select_tool(Tools.Kind.WATER_PIPE)
	owner.select_tool(Tools.Kind.ROAD)
	check(owner.is_underground(), "manual underground persists across tool selections")
	owner.set_view_mode(0)
	owner.preview.show_footprint([Vector2i(1, 2), Vector2(3.2, 4.8)], false, "$50")
	check(owner.preview.tiles == [Vector2i(1, 2), Vector2i(3, 5)] and owner.preview.caption == "$50", "preview owns normalized footprint and caption")
	owner.preview.clear()
	check(not owner.preview.is_showing(), "preview clears independently of canvas drawing")
	check(SaveFormat.encode_city(city) == before, "presentation operations preserve the encoded city")
	owner.free()
	view.free()
	await process_frame
