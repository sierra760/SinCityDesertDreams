# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Catch anchored footer growth and missing persistent Query selection.
extends "res://tests/exploration/async_test_case.gd"
const HostFixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost

func before_each() -> void:
	host = HostFixture.make_host(self, "ipad-polish-host-tests")
	await HostFixture.settle(self, 4)

func after_each() -> void:
	host.free()
	await process_frame

func test_keyboard_roundtrips_restore_footer_content_height() -> void:
	for dimensions: Vector2i in [Vector2i(1194,834),Vector2i(768,1024)]:
		root.size=dimensions
		host.display_layout.refresh_with_mobile_metrics(dimensions,1,Rect2i(0,24,dimensions.x,dimensions.y-44))
		await HostFixture.settle(self, 4)
		check_eq(host.status_bar.size.y,48.0,"ordinary footer starts at natural height")
		for repeat in 3:
			host.display_layout.refresh_with_mobile_metrics(dimensions,1,Rect2i(0,24,dimensions.x,dimensions.y-44),300)
			await HostFixture.settle(self, 4)
			host.display_layout.refresh_with_mobile_metrics(dimensions,1,Rect2i(0,24,dimensions.x,dimensions.y-44),0)
			await HostFixture.settle(self, 4)
			check_eq(host.status_bar.size.y,48.0,"keyboard dismissal cannot accumulate blank footer space")

func test_safe_area_bottom_roundtrip_does_not_stretch_footer() -> void:
	root.size=Vector2i(1194,834)
	for safe: Rect2i in [Rect2i(0,24,1194,790),Rect2i(0,24,1194,740),Rect2i(0,24,1194,790)]:
		host.display_layout.refresh_with_mobile_metrics(root.size,1,safe)
		await HostFixture.settle(self, 4)
		check_eq(host.status_bar.size.y,48.0)
		check_eq(host.status_bar.get_global_rect().end.y,float(safe.end.y))

func test_footer_shrinks_after_wrapped_content_disappears() -> void:
	root.size=Vector2i(768,1024)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,24,768,980))
	host.status_bar.set_emergency_available(true)
	await HostFixture.settle(self, 4)
	check_ge(host.status_bar.size.y,80,"visible emergency action legitimately wraps")
	host.status_bar.set_emergency_available(false)
	await HostFixture.settle(self, 4)
	check_eq(host.status_bar.size.y,48.0,"unused emergency row no longer reserves blank space")

func feedback() -> Node:
	var result: Variant=host.city_view_3d.get("query_feedback")
	check(result is Node,"Query has independent hover/selection drawing")
	return result as Node

func test_query_hover_and_selection_have_independent_lifetimes() -> void:
	host.select_tool(Tools.Kind.QUERY)
	host._on_tile_hovered(Vector2i(64,64))
	var drawing:=feedback()
	if drawing==null: return
	check_eq(drawing.get("hovered"),Vector2i(64,64))
	check_eq(drawing.get("selected"),Vector2i(-1,-1))
	host.open_query(Vector2i(64,64))
	check_eq(drawing.get("selected"),Vector2i(64,64))
	host._on_tile_hovered(Vector2i(65,64))
	check_eq(drawing.get("hovered"),Vector2i(65,64))
	check_eq(drawing.get("selected"),Vector2i(64,64),"hover does not replace inspector selection")
	host._on_tile_hovered(Vector2i(-1,-1))
	check_eq(drawing.get("hovered"),Vector2i(-1,-1))
	check_eq(drawing.get("selected"),Vector2i(64,64),"leaving city preserves inspector selection")
	host.query_panel.close()
	check_eq(drawing.get("selected"),Vector2i(-1,-1),"closing inspector releases selection")

func test_query_selection_survives_tool_switch_but_not_city_change() -> void:
	host.open_query(Vector2i(64,64))
	var drawing:=feedback()
	if drawing==null: return
	host.select_tool(Tools.Kind.ROAD)
	check_eq(drawing.get("selected"),Vector2i(64,64),"inspector owns selected tile even with another tool")
	host.begin_city(flat_city(),{},124,null)
	check_eq(drawing.get("selected"),Vector2i(-1,-1))
	check_eq(drawing.get("hovered"),Vector2i(-1,-1))

func test_lazily_opened_options_inherit_current_platform_metrics() -> void:
	host.display_layout.refresh_with_mobile_metrics(Vector2i(1194,834),1,Rect2i(0,24,1194,790))
	var options:=host.open_window("options") as OptionsWindow
	await HostFixture.settle(self, 4)
	check(not options.checks[&"fullscreen"].visible,"Options created after metrics injection hides mobile fullscreen")
	check(options.checks[&"fullscreen"].disabled)
	host.display_layout.refresh_with_metrics(Vector2i(1194,834),1)
	await HostFixture.settle(self, 4)
	check(options.checks[&"fullscreen"].visible,"desktop can still use fullscreen")

func test_query_shortcut_and_camera_keep_stationary_pointer_target_current() -> void:
	root.size=Vector2i(1194,834)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,24,1194,790))
	await HostFixture.settle(self, 4)
	host.select_tool(Tools.Kind.ROAD)
	var event:=InputEventMouseMotion.new()
	event.position=host.city_view_3d.project_cell(Vector2i(64,64))
	host.presentation._unhandled_input(event)
	host.select_tool(Tools.Kind.QUERY)
	var drawing:=feedback()
	if drawing==null: return
	check_eq(drawing.get("hovered"),Vector2i(64,64),"Query shortcut previews the existing stationary pointer")
	host.city_view_3d.set_camera_state(Vector3(67,2.4,64),1,32)
	await HostFixture.settle(self, 4)
	check_eq(drawing.get("hovered"),host.city_view_3d.pick_cell(event.position,1),"camera change re-picks the actual stationary pointer")

func test_resizing_display_retains_stationary_query_pointer_feedback() -> void:
	root.size=Vector2i(1194,834)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,24,1194,790))
	await HostFixture.settle(self, 4)
	var event:=InputEventMouseMotion.new()
	event.position=host.city_view_3d.project_cell(Vector2i(64,64))
	host.presentation._unhandled_input(event)
	root.size=Vector2i(768,1024)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,24,768,980))
	await HostFixture.settle(self, 4)
	var drawing:=feedback()
	if drawing==null: return
	check_eq(drawing.get("hovered"),host.city_view_3d.pick_cell(event.position,1),"display layout re-picks the stationary physical mouse after cancellation or reflow")

func test_stationary_query_pointer_survives_ui_scale_change() -> void:
	root.size=Vector2i(1194,834)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,24,1194,790))
	host.display_layout.set_ui_scale(100)
	await HostFixture.settle(self, 4)
	var event:=InputEventMouseMotion.new()
	event.position=host.city_view_3d.project_cell(Vector2i(64,64))
	host.presentation._unhandled_input(event)
	host.display_layout.set_ui_scale(125)
	await HostFixture.settle(self, 4)
	var drawing:=feedback()
	if drawing==null: return
	check_eq(drawing.get("hovered"),host.city_view_3d.pick_cell(event.position/1.25,1),"hover agrees with a new click at the same physical point after scale change")
