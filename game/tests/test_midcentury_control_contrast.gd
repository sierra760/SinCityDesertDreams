# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b

func contrast(first: Color, second: Color) -> float:
	var a := luminance(first)
	var b := luminance(second)
	return (maxf(a,b) + 0.05) / (minf(a,b) + 0.05)

func test_selected_tool_caption_stays_readable_when_keyboard_focused() -> void:
	var toolbar := Toolbar.new()
	root.add_child(toolbar)
	toolbar.set_active(Tools.Kind.ROAD)
	await process_frame
	var button := toolbar.button_for(Tools.Kind.ROAD)
	var surface := button.get_theme_stylebox("normal") as StyleBoxFlat
	for state: String in ["font_color","font_hover_color","font_focus_color"]:
		check_ge(contrast(button.get_theme_color(state),surface.bg_color),4.5,"selected caption contrast: " + state)
	toolbar.free()

func test_primary_and_selected_controls_have_a_visible_focus_ring() -> void:
	var toolbar := Toolbar.new()
	root.add_child(toolbar)
	toolbar.set_active(Tools.Kind.ROAD)
	var primary := UIFactory.make_primary_button("New City")
	root.add_child(primary)
	await process_frame
	for button: Button in [primary,toolbar.button_for(Tools.Kind.ROAD)]:
		var surface := button.get_theme_stylebox("normal") as StyleBoxFlat
		var focus := button.get_theme_stylebox("focus") as StyleBoxFlat
		check(not focus.draw_center or focus.shadow_color.a == 0.0 or focus.shadow_size == 0,"focus decoration leaves the caption surface visible")
		var visible_contrast := contrast(focus.border_color,surface.bg_color)
		if focus.shadow_size >= 2 and focus.shadow_color.a == 1.0:
			visible_contrast = maxf(visible_contrast,contrast(focus.shadow_color,surface.bg_color))
		check_ge(visible_contrast,3.0,"focus ring distinguishes the dark selected surface")
	primary.free()
	toolbar.free()
