# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

var _original_size: Vector2i

func before_all() -> void:
	_original_size = root.size

func after_all() -> void:
	root.content_scale_factor = 1.0
	root.size = _original_size

func test_compact_status_resolves_readable_lines_after_layout() -> void:
	await _check_status_at_size(Vector2i(640,400),1.0)

func test_retina_status_uses_shared_logical_canvas() -> void:
	await _check_status_at_size(Vector2i(1280,800),2.0)

func test_compact_retina_critical_status_clears_main_footer_without_scrolling() -> void:
	await _check_status_at_size(Vector2i(1280,800),2.0,111.0)

func test_actual_city_footer_critical_flight_status_is_visible_while_captured() -> void:
	await _check_status_at_size(Vector2i(1280,800),2.0,171.0,false)

func test_actual_city_footer_critical_flight_status_is_visible_while_suspended() -> void:
	await _check_status_at_size(Vector2i(1280,800),2.0,171.0,true)

func test_compact_passenger_platform_and_door_guidance_stay_visible() -> void:
	root.size=Vector2i(640,400)
	var layout := DisplayLayout.new()
	root.add_child(layout)
	layout.bind(root)
	layout.refresh_with_metrics(root.size,1.0)
	var hud := ExploreHUD.new()
	root.add_child(hud)
	hud.bind_layout(layout)
	hud.set_chrome_insets(44,171)
	hud.show_session(true)
	hud.set_status({"mode":0,"speed":0})
	hud.set_transit_status({"passenger":true,"transit_kind":"subway","current_stop":"Subway 120,101","next_stop":"Subway 120,103","door_state":"boarding","departure_seconds":8})
	await process_frame
	await process_frame
	check(Rect2(0,44,640,185).encloses(hud._status_panel.get_rect()),"ride information clears the actual compact footer")
	for label: Label in [hud._actor_label,hud._speed_label,hud._transit_label]:
		check(hud._status_panel.get_global_rect().encloses(label.get_global_rect()),"passenger guidance visible without scrolling")
	hud.free()
	layout.free()
	await process_frame

func _check_status_at_size(drawable: Vector2i, backing: float, footer_inset: float = 44.0, suspended: bool = true) -> void:
	root.size = drawable
	var layout := DisplayLayout.new()
	root.add_child(layout)
	layout.bind(root)
	layout.refresh_with_metrics(drawable,backing)
	var hud := ExploreHUD.new()
	root.add_child(hud)
	hud.bind_layout(layout)
	hud.set_chrome_insets(44.0,footer_inset)
	hud.show_session(true)
	hud.set_suspended(suspended)
	var status_panel := hud.get_node("ExploreStatus") as PanelContainer
	var controls_panel := hud.get_node("ExplorePanel") as PanelContainer
	var status_scroll := hud._status_scroll
	var column := hud._actor_label.get_parent() as VBoxContainer
	for mode in [ExploreActorProfile.Mode.WALK,ExploreActorProfile.Mode.DRIVE]:
		hud.set_status({"mode":mode,"speed":2.5,"altitude":0.0,"prompt":"F to enter or exit"})
		await process_frame
		await process_frame
		var actor := column.get_child(0) as Label
		var speed := column.get_child(1) as Label
		check_eq(actor.text,"Walking" if mode == ExploreActorProfile.Mode.WALK else "Driving")
		check_eq(actor.get_line_count(),1,"actor status must render on one line")
		check_eq(speed.get_line_count(),1,"speed must render on one line")
		check_ge(column.size.x,200.0,"critical column fills the visible content width")
		check_ge(actor.size.x,200.0,"actor label receives usable width")
		check_ge(speed.size.x,200.0,"speed label receives usable width")
		check(status_panel.get_global_rect().encloses(actor.get_global_rect()),"actor is visible inside fixed critical status")
		check(status_panel.get_global_rect().encloses(speed.get_global_rect()),"speed is visible inside fixed critical status")
		var prompt := column.get_child(3) as Label
		check(prompt.visible and status_panel.get_global_rect().encloses(prompt.get_global_rect()),
			"mode %d E prompt is visible without scrolling" % mode)
	hud.set_status({"mode":ExploreActorProfile.Mode.FLY,"speed":2.5,"altitude":.25,"prompt":"F to exit helicopter"})
	status_scroll.scroll_vertical = 0
	await process_frame
	await process_frame
	var altitude := column.get_child(2) as Label
	var flight_prompt := column.get_child(3) as Label
	check(altitude.visible and status_panel.get_global_rect().encloses(altitude.get_global_rect()),
		"flight altitude is visible without scrolling")
	check(flight_prompt.visible and status_panel.get_global_rect().encloses(flight_prompt.get_global_rect()),
		"flight E prompt is visible without scrolling")
	var usable := Rect2(0,44,640,400.0-44.0-footer_inset)
	check(usable.encloses(status_panel.get_rect()),"status stays below Main menu and above city chrome")
	check(not suspended or usable.encloses(controls_panel.get_rect()),"controls stay within compact logical bounds")
	check(not suspended or not status_panel.get_rect().intersects(controls_panel.get_rect()),"status and controls do not overlap")
	check(status_panel.get_rect().end.x <= usable.size.x*.5-40.0,
		"compact status leaves a clear central lane around the actor")
	if suspended:
		var controls_scroll := hud.get_node("ExplorePanel/ExploreControlsScroll") as ScrollContainer
		var resume := controls_scroll.get_child(0).get_child(1) as Button
		check_ge(resume.size.y,44.0,"Resume keeps its full touch target")
		check(controls_scroll.get_global_rect().encloses(resume.get_global_rect()),"Resume visible before scrolling controls")
	var long_message := "Long exploration message that should wrap inside the status panel. ".repeat(12)
	hud.set_status({"mode":ExploreActorProfile.Mode.DRIVE,"speed":2.5,"message":long_message})
	await process_frame
	await process_frame
	var message := hud._message_label
	check_gt(message.get_line_count(),1,"long message wraps across usable column width")
	var bar := status_scroll.get_v_scroll_bar()
	check_gt(bar.max_value,bar.page,"long message remains vertically scrollable")
	status_scroll.scroll_vertical = int(bar.max_value)
	await process_frame
	check(status_panel.get_global_rect().encloses(hud._actor_label.get_global_rect()),"scrolling feedback keeps mode visible")
	check(status_panel.get_global_rect().encloses(hud._speed_label.get_global_rect()),"scrolling feedback keeps speed visible")
	hud.free()
	layout.free()
	root.content_scale_factor = 1.0
	await process_frame
