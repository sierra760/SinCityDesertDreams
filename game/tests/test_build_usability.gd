# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Build-mode feedback: trackpad navigation, bounded zoom, drags that stop
## short, readable refusals and a confirmed inspector demolition.
extends "res://tests/test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
const PREFS := "user://test_build_usability.cfg"
var host: GameHost


func before_all() -> void:
	root.size = Vector2i(1280, 800)


func before_each() -> void:
	ViewPreferences.write({}, PREFS)
	host = MainScene.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)
	var city := flat_city()
	city.name = "Usability Test"
	host.start_new_city({"name": city.name, "seed": 4127, "difficulty": City.Difficulty.EASY}, city)
	host.found_city()
	host.sim.set_speed(GameClock.Speed.PAUSED)


func after_each() -> void:
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	root.remove_child(host)
	host.free()
	host = null
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))


func _message() -> String:
	return host.status_bar.message_label.text


# ── Trackpad and zoom ────────────────────────────────────────────────────

func test_trackpad_pinch_and_two_finger_scroll_navigate_build() -> void:
	var view := host.city_view_3d
	view.set_camera_state(Vector3(64, view.center.y, 64), 0, 40.0)
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = Vector2(640, 400)
	pinch.factor = 1.25
	view._unhandled_input(pinch)
	check(absf(view.camera_size - 32.0) < 0.001, "pinch apart zooms in like a touch pinch")
	pinch.factor = 0.8
	view._unhandled_input(pinch)
	check(absf(view.camera_size - 40.0) < 0.001, "pinch together zooms out")
	var start := view.center
	var scroll := InputEventPanGesture.new()
	scroll.position = Vector2(640, 400)
	scroll.delta = Vector2(1, 0.5)
	view._unhandled_input(scroll)
	var scrolled := view.center
	check(scrolled.distance_to(start) > 0.1, "two-finger scroll pans the map")
	view.set_camera_state(start, 0, 40.0)
	view.pan_screen(-Vector2(1, 0.5) * CityView3D.PAN_GESTURE_PIXELS)
	check(view.center.distance_to(scrolled) < 0.001, "the map follows the fingers like a drag")
	view.set_camera_state(start, 0, 40.0)
	host.push_modal()
	view._unhandled_input(pinch)
	view._unhandled_input(scroll)
	check_eq(view.camera_size, 40.0, "a modal blocks trackpad zoom")
	check_eq(view.center, start, "a modal blocks trackpad pan")
	host.pop_modal()


func test_free_zoom_stays_near_the_named_levels() -> void:
	var view := host.city_view_3d
	var far := view._zoom_size(0)
	var closest := view._zoom_size(CityView3D.ZOOM_COUNT - 1)
	for i: int in 40:
		view.zoom_out()
	check(view.camera_size <= far * 1.5 + 0.001, "zooming out stops at 1.5x the farthest level")
	check(view.camera_size >= far, "zooming out still reaches past the farthest level")
	for i: int in 40:
		view.zoom_in()
	check(view.camera_size >= closest * 0.75 - 0.001, "zooming in stops at 0.75x the closest level")
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 2.0
	for i: int in 10:
		view._unhandled_input(pinch)
	check(view.camera_size >= closest * 0.75 - 0.001, "pinch shares the bound")


func test_wheel_zoom_keeps_the_ground_under_the_pointer() -> void:
	var view := host.city_view_3d
	view.set_camera_state(Vector3(64, view.center.y, 64), 0, view._zoom_size(1))
	var point := view.container.position + view.container.size * Vector2(0.7, 0.3)
	var before: Variant = view._ground_point(point)
	check(before != null, "the pointer is over the map")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = point
	var size := view.camera_size
	view._unhandled_input(wheel)
	check_lt(view.camera_size, size, "wheel up zooms in")
	var after: Variant = view._ground_point(point)
	check(before != null and after != null and Vector2((before as Vector3).x, (before as Vector3).z).distance_to(Vector2((after as Vector3).x, (after as Vector3).z)) < 0.05,
		"the ground under the pointer stays put")


# ── Drags, refusals and prices ───────────────────────────────────────────

func test_a_drag_that_stops_short_says_why() -> void:
	check(bool(host.builder.apply(Tools.Kind.POLICE, Vector2i(46, 40))["ok"]), "a blocker stands in the path")
	var quote := host.builder.preview(Tools.Kind.ROAD, Vector2i(40, 40), Vector2i(52, 40))
	check(bool(quote["ok"]), "the tiles before the blocker still build")
	check(String(quote.get("stopped", "")).begins_with("blocked by"), "the plan reports where it stopped: %s" % quote.get("stopped", ""))
	host.select_tool(Tools.Kind.ROAD)
	host.construction.preview_drag(Vector2i(40, 40), Vector2i(52, 40))
	check(host.presentation.preview.caption.contains("· stops: blocked by"), "the caption shows the stop: " + host.presentation.preview.caption)
	var result := host.handle_drag(Vector2i(40, 40), Vector2i(52, 40))
	check(bool(result["applied"]))
	check(_message().begins_with("Spent $"), _message())
	check(_message().contains("stopped: blocked by"), "the build message keeps the reason: " + _message())
	var full := host.builder.preview(Tools.Kind.ROAD, Vector2i(40, 42), Vector2i(44, 42))
	check(not full.has("stopped"), "a complete drag reports no stop")


func test_short_funds_show_the_price_and_treasury() -> void:
	host.sim.city.funds = 3
	host.select_tool(Tools.Kind.ROAD)
	host.construction.preview_drag(Vector2i(40, 44), Vector2i(49, 44))
	var expected := "Costs $%s — treasury $3" % UIFactory.commafy(Tools.cost(Tools.Kind.ROAD) * 10)
	check_eq(host.presentation.preview.caption, expected)
	host.handle_drag(Vector2i(40, 44), Vector2i(49, 44))
	check_eq(_message(), expected)
	host.sim.city.funds = -830
	host.handle_drag(Vector2i(40, 44), Vector2i(49, 44))
	check(_message().ends_with("treasury -$830"), "a negative treasury keeps its sign: " + _message())


func test_refusal_captions_read_as_sentences() -> void:
	host.select_tool(Tools.Kind.ROAD)
	host.construction.preview_drag(Vector2i(10, 0), Vector2i(20, 0))
	check_eq(host.presentation.preview.caption, "Reaches the city limit.")


func test_bare_ground_bulldoze_names_what_it_removes_underground() -> void:
	check(bool(host.builder.apply(Tools.Kind.WATER_PIPE, Vector2i(30, 30), Vector2i(34, 30))["ok"]))
	host.select_tool(Tools.Kind.BULLDOZE)
	host.construction.preview_drag(Vector2i(30, 30), Vector2i(34, 30))
	check(host.presentation.preview.caption.contains("also removes water pipe"), host.presentation.preview.caption)


# ── Inspector demolition ─────────────────────────────────────────────────

func test_inspector_demolish_confirms_developed_buildings() -> void:
	var city := host.sim.city
	check(bool(host.builder.apply(Tools.Kind.POLICE, Vector2i(60, 60))["ok"]))
	var anchor := city.anchor_of(61, 61)
	var code := city.building_at(anchor.x, anchor.y)
	var funds := city.funds
	host.construction._on_demolish_requested(Vector2i(61, 61))
	check(host.notice_dialog.is_open(), "a developed building asks first")
	check_eq(city.building_at(anchor.x, anchor.y), code, "nothing is removed before the answer")
	var body := host.notice_dialog.body_label.text
	check(body.begins_with("Demolish the %s?" % Buildings.display_name(code)), body)
	check(body.contains("$") and body.contains("can't be undone"), body)
	host.notice_dialog.dismiss()
	check_eq(city.building_at(anchor.x, anchor.y), code, "Escape keeps the building")
	check_eq(city.funds, funds, "Cancel charges nothing")
	host.construction._on_demolish_requested(Vector2i(61, 61))
	host.notice_dialog.dismiss(&"demolish")
	check_ne(city.building_at(anchor.x, anchor.y), code, "Demolish removes it")
	check_lt(city.funds, funds, "and charges the bulldozing price")
	check(bool(host.builder.apply(Tools.Kind.ROAD, Vector2i(70, 70), Vector2i(72, 70))["ok"]))
	host.construction._on_demolish_requested(Vector2i(71, 70))
	check(not host.notice_dialog.is_open(), "a plain road goes at once")
	check_eq(city.building_at(71, 70), Buildings.NONE)


# ── Notices ──────────────────────────────────────────────────────────────

func test_flavour_notices_use_the_status_line() -> void:
	host.notices.raise(&"tree_protest", {"count": 12})
	check(not host.notice_dialog.is_open(), "a tree protest does not pause the city")
	check(_message().begins_with("Save Our Trees: "), _message())
	host.notices.raise(&"approval_milestone", {"approval": 72})
	check(not host.notice_dialog.is_open())
	check(_message().contains("72"), _message())
	host.notices.raise(&"fiscal_crisis", {"funds": -1200, "year": 2001})
	check(host.notice_dialog.is_open(), "decisions still open a notice")
	host.notice_dialog.dismiss()


func test_declining_a_neighbor_link_reports_the_built_road() -> void:
	host.select_tool(Tools.Kind.ROAD)
	var result := host.handle_drag(Vector2i(10, 20), Vector2i(0, 20))
	check(bool(result.get("applied", false)), "the road up to the border is built")
	check(host.choice_dialog.is_open(), "the link is offered")
	host.choice_dialog.cancel()
	check_eq(_message(), "Built up to the city limit; no link made.")
