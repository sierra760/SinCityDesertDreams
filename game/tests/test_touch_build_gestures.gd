# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Touch routing commits through the existing Builder only after a clean release.
extends "res://tests/test_case.gd"

class PickView extends CityView3D:
	var points: Array[Vector2] = []
	func _ready() -> void: pass
	func bind_city(value: City) -> void:
		city = value
	func pick_cell(point: Vector2, _purpose: int = 0) -> Vector2i:
		points.append(point)
		return Vector2i(roundi(point.x / 10.0), roundi(point.y / 10.0))

var owner: CityPresentationController
var view: PickView
var city: City
var builder: Builder
var begins := 0
var ends := 0
var cancels := 0
var blocked := false

func before_each() -> void:
	begins = 0
	ends = 0
	cancels = 0
	blocked = false
	city = flat_city()
	builder = Builder.new(city, CityStats.new())
	view = PickView.new()
	view.active = true
	view.container = TextureRect.new()
	view.container.size = Vector2(1000, 800)
	view.add_child(view.container)
	view.viewport = SubViewport.new()
	view.viewport.size = Vector2i(2000, 1600)
	view.add_child(view.viewport)
	view.camera = Camera3D.new()
	view.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	view.add_child(view.camera)
	root.add_child(view)
	owner = CityPresentationController.new()
	owner.view = view
	owner.input_blocked = func(): return blocked
	root.add_child(owner)
	owner.bind_city(city)
	view.set_camera_state(Vector3(64, 4, 64), 0, 64.0)
	owner.drag_started.connect(func(_a, _b): begins += 1)
	owner.drag_ended.connect(func(a, b):
		ends += 1
		builder.apply(Tools.Kind.ROAD, a, b))
	if owner.has_signal("drag_cancelled"):
		owner.connect("drag_cancelled", func(): cancels += 1)
	if owner.has_method("set_touch_ui_ownership_checker"):
		owner.call("set_touch_ui_ownership_checker", func(point: Vector2): return point.x < 200)

func after_each() -> void:
	owner.free()
	view.free()

func touch(index: int, on: bool, point := Vector2(400, 448), cancelled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = on
	event.position = point
	event.canceled = cancelled
	if owner.has_method("_input"):
		owner.call("_input", event)

func move(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	if owner.has_method("_input"):
		owner.call("_input", event)

func test_single_touch_previews_at_finger_and_draws_selected_tool() -> void:
	var funds := city.funds
	touch(0, true)
	check_eq(begins, 1, "one city finger begins construction")
	check_eq(city.funds, funds, "press previews without charging")
	check_eq(view.points.back() if not view.points.is_empty() else Vector2.ZERO, Vector2(400, 448), "placement target stays at the finger")
	move(0, Vector2(430, 448))
	touch(0, false, Vector2(430, 448))
	check_eq(ends, 1, "clean release commits once")
	for x in range(40, 44):
		check(Buildings.is_road_like(city.building.at(x, 45)), "road follows the contacted row")
		check_eq(city.building.at(x, 40), Buildings.NONE, "above-finger row stays empty")
	check_eq(city.funds, funds - 4 * Tools.cost(Tools.Kind.ROAD))

func test_second_finger_cancels_before_release_and_navigation_never_commits() -> void:
	var funds := city.funds
	touch(0, true)
	touch(1, true, Vector2(600, 448))
	check_eq(cancels, 1, "takeover tells the host to discard its preview")
	touch(1, false, Vector2(600, 448))
	move(0, Vector2(440, 448))
	touch(0, false, Vector2(440, 448))
	check_eq(ends, 0)
	check_eq(city.funds, funds)
	touch(2, true)
	touch(2, false)
	check_eq(ends, 1, "fresh construction is allowed only after every old finger releases")

func test_ui_origin_touch_cannot_turn_into_a_city_stroke() -> void:
	touch(0, true, Vector2(100, 448))
	move(0, Vector2(400, 448))
	touch(0, false)
	check_eq(begins, 0)
	check_eq(ends, 0)
	touch(1, true)
	touch(1, false)
	check_eq(ends, 1, "city input still works after the UI finger releases")

func test_second_ui_finger_also_cancels_construction() -> void:
	touch(0, true)
	touch(1, true, Vector2(100, 448))
	check_eq(cancels, 1)
	touch(1, false, Vector2(100, 448))
	touch(0, false)
	check_eq(ends, 0)

func test_city_touch_released_over_ui_cannot_commit() -> void:
	touch(0, true)
	move(0, Vector2(100, 448))
	touch(0, false, Vector2(100, 448))
	check_eq(ends, 0)
	check_eq(cancels, 1)

func test_os_cancellation_never_commits_even_when_a_release_follows() -> void:
	touch(0, true)
	touch(0, false, Vector2(400, 448), true)
	touch(0, false)
	check_eq(ends, 0)
	check_eq(cancels, 1)

func test_external_cancel_requires_remaining_fingers_to_release() -> void:
	touch(0, true)
	owner.cancel_drag()
	move(0, Vector2(430, 448))
	touch(1, true, Vector2(600, 448))
	touch(0, false)
	touch(1, false, Vector2(600, 448))
	check_eq(ends, 0)
	touch(2, true)
	touch(2, false)
	check_eq(ends, 1)

func test_blocked_touch_cannot_commit_after_modal_closes() -> void:
	touch(0, true)
	blocked = true
	move(0, Vector2(430, 448))
	blocked = false
	touch(0, false, Vector2(430, 448))
	check_eq(ends, 0)
	check_eq(cancels, 1)

func test_suspension_cancels_and_resumption_does_not_reuse_held_finger() -> void:
	touch(0, true)
	owner.set_exploration_suspended(true)
	owner.set_exploration_suspended(false)
	move(0, Vector2(430, 448))
	touch(0, false)
	check_eq(ends, 0)
	touch(1, true)
	touch(1, false)
	check_eq(ends, 1)

func test_two_city_fingers_pan_and_pinch_without_large_initial_jump() -> void:
	var center := view.center
	touch(0, true)
	touch(1, true, Vector2(600, 448))
	check_eq(view.center, center)
	check_eq(view.camera_size, 64.0, "second press establishes the baseline")
	move(1, Vector2(700, 448))
	check(view.center.distance_to(center) > 0.5, "centroid motion pans")
	check(absf(view.camera_size - 64.0 / 1.5) < 0.001, "pinch uses the measured distance ratio")
	check_eq(ends, 0)

func test_host_cancel_callback_preserves_second_finger_navigation_baseline() -> void:
	if owner.has_signal("drag_cancelled"):
		owner.connect("drag_cancelled", owner.cancel_drag)
	touch(0, true)
	touch(1, true, Vector2(600, 448))
	var center := view.center
	move(1, Vector2(700, 448))
	check(view.center.distance_to(center) > 0.5, "host cancellation must not discard the established navigation baseline")
	check(absf(view.camera_size - 64.0 / 1.5) < 0.001)
	check_eq(cancels, 1, "cancel callback cannot recursively notify the host")

func test_third_finger_does_not_make_one_remaining_finger_build() -> void:
	touch(0, true)
	touch(1, true, Vector2(600, 448))
	touch(2, true, Vector2(800, 448))
	touch(0, false)
	touch(1, false, Vector2(600, 448))
	move(2, Vector2(830, 448))
	touch(2, false, Vector2(830, 448))
	check_eq(ends, 0)
	check_eq(begins, 1)

func test_emulated_mouse_cannot_duplicate_touch_construction() -> void:
	var press := InputEventMouseButton.new()
	press.device = InputEvent.DEVICE_ID_EMULATION
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(400, 400)
	owner._unhandled_input(press)
	press.pressed = false
	owner._unhandled_input(press)
	check_eq(begins, 0)
	check_eq(ends, 0)

func test_physical_mouse_still_places_with_its_original_target() -> void:
	var press := InputEventMouseButton.new()
	press.device = 0
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(400, 400)
	owner._unhandled_input(press)
	press.pressed = false
	owner._unhandled_input(press)
	check_eq(ends, 1)
	check(Buildings.is_road_like(city.building.at(40, 40)))

func test_pan_uses_logical_height_despite_double_native_resolution() -> void:
	if view.has_method("pan_screen"):
		view.call("pan_screen", Vector2(100, 0))
	check(absf(view.center.x - (64.0 - 8.0 / sqrt(2.0))) < 0.001)
	check(absf(view.center.z - (64.0 + 8.0 / sqrt(2.0))) < 0.001)

func _set_touch_camera_blocker(checker: Callable) -> void:
	for property in view.get_property_list():
		if property.name == "touch_input_blocked":
			view.set("touch_input_blocked", checker)
			return

func test_keyboard_focus_does_not_block_city_touch_navigation() -> void:
	view.input_blocked = func(): return true
	_set_touch_camera_blocker(func(): return false)
	var before := view.center
	view.pan_screen(Vector2(100, 0))
	check(view.center.distance_to(before) > 0.5, "focused toolbar blocks keyboard input while touch remains usable")
	view.pinch_zoom(1.25)
	check(absf(view.camera_size - 51.2) < 0.001, "touch pinch has its own modal/focus owner")

func test_touch_modal_blocks_navigation_even_when_keyboard_owner_allows_input() -> void:
	view.input_blocked = func(): return false
	_set_touch_camera_blocker(func(): return true)
	var before := view.center
	view.pan_screen(Vector2(100, 0))
	view.pinch_zoom(1.25)
	check_eq(view.center, before)
	check_eq(view.camera_size, 64.0)

func test_touch_navigation_preserves_old_blocker_until_touch_owner_is_bound() -> void:
	view.input_blocked = func(): return true
	var before := view.center
	view.pan_screen(Vector2(100, 0))
	view.pinch_zoom(1.25)
	check_eq(view.center, before)
	check_eq(view.camera_size, 64.0)

func test_invalid_or_extreme_pinch_cannot_throw_camera_out_of_bounds() -> void:
	if view.has_method("pinch_zoom"):
		view.call("pinch_zoom", NAN)
		view.call("pinch_zoom", 0.0)
	check_eq(view.camera_size, 64.0)
	if view.has_method("pinch_zoom"):
		view.call("pinch_zoom", 1000000.0)
	check(absf(view.camera_size - 32.0) < 0.001, "one delivered delta can at most double zoom")

func test_aerial_view_ignores_emulated_mouse_wheel_and_pan() -> void:
	var wheel := InputEventMouseButton.new()
	wheel.device = InputEvent.DEVICE_ID_EMULATION
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	view._unhandled_input(wheel)
	check_eq(view.camera_size, 64.0)
	wheel.button_index = MOUSE_BUTTON_MIDDLE
	view._unhandled_input(wheel)
	check(not view._panning)
