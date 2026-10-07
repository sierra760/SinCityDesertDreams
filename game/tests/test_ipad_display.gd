# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const Layout := preload("res://scripts/ui/display_layout.gd")

func _mobile_metrics(layout: Node, drawable: Vector2i, backing: float, safe: Rect2i, keyboard: int = 0) -> bool:
	layout.call("refresh_with_mobile_metrics", drawable, backing, safe, keyboard)
	return true

func test_safe_area_and_keyboard_are_converted_once() -> void:
	var layout := Layout.new()
	if _mobile_metrics(layout, Vector2i(2560,1800), 2.0, Rect2i(40,48,2480,1712), 500):
		check_eq(layout.logical_rect(), Rect2(20,24,1240,626))
		check_eq(layout.ui_to_drawable(Vector2(20,24)), Vector2(40,48))
		check_eq(layout.drawable_to_ui(Vector2(40,48)), Vector2(20,24))
		layout.set_ui_scale(200)
		check_eq(layout.logical_rect(), Rect2(10,12,620,313), "scale changes preserve physical occlusion")
	layout.free()

func test_portrait_and_offscreen_safe_readings_are_bounded() -> void:
	var layout := Layout.new()
	if _mobile_metrics(layout, Vector2i(1668,2388), 2.0, Rect2i(-20,48,1800,2400), 800):
		check_eq(layout.logical_rect(), Rect2(0,24,834,770))
		layout.call("refresh_with_mobile_metrics", Vector2i(1668,2388), 2.0, Rect2i(), 0)
		check_eq(layout.logical_rect(), Rect2(0,0,834,1194), "empty safe reading falls back to drawable")
	layout.free()

func test_mobile_restore_never_resizes_or_changes_window_mode() -> void:
	var layout := Layout.new()
	root.add_child(layout)
	layout.bind(root)
	var old_size := root.size
	var old_mode := root.mode
	if _mobile_metrics(layout, Vector2i(2388,1668), 2.0, Rect2i(0,48,2388,1580)):
		layout.restore_window({"ui_scale":125,"windowed_size":Vector2(640,400),"fullscreen":true})
		layout.set_fullscreen(false)
		check_eq(root.size, old_size, "mobile restoration leaves OS size alone")
		check_eq(root.mode, old_mode, "mobile restoration leaves OS mode alone")
		check_eq(layout.ui_scale,125)
		check_eq(layout.metrics.scale,2.5,"startup scale applies to injected mobile metrics")
		check_eq(layout.logical_rect(),Rect2(0,19.2,955.2,632))
	layout.free()

func test_registered_dialog_and_embedded_popup_fit_usable_rect() -> void:
	var layout := Layout.new()
	var panel := Control.new()
	root.add_child(panel)
	var popup := Window.new()
	root.add_child(popup)
	if _mobile_metrics(layout, Vector2i(2560,1800), 2.0, Rect2i(40,48,2480,1712), 500):
		panel.position = Vector2(2000,2000)
		layout.register_window({"root":panel}, Vector2(1600,900))
		check(layout.logical_rect().encloses(panel.get_rect()), "dialog fits physical safe area above keyboard")
		popup.position = Vector2i(2000,2000)
		popup.size = Vector2i(1600,900)
		layout.apply_popup(popup)
		check(layout.logical_rect().encloses(Rect2(Vector2(popup.position),Vector2(popup.size))), "embedded popup fits same usable rect")
	panel.free()
	popup.free()
	layout.free()

func test_complete_keyboard_occlusion_has_no_negative_rect() -> void:
	var layout := Layout.new()
	if _mobile_metrics(layout, Vector2i(1280,800), 1.0, Rect2i(0,40,1280,740), 900):
		check_eq(layout.logical_rect(),Rect2(0,40,1280,0))
		var fitted := Layout.clamp_caption_rect(Rect2(100,100,200,100),layout.logical_rect())
		check_eq(fitted,layout.logical_rect(),"fully occluded popup cannot acquire negative dimensions")
	layout.free()
