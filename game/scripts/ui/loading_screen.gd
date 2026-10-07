# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## One opaque loading surface above the city, chrome and modal dialogs.
## The host gives it a draw before starting work and before revealing the view.
class_name GameLoadingScreen
extends Control

var heading: Label
var detail: Label

func _init() -> void:
	name = "LoadingScreen"
	theme = UITheme.control_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var backdrop := ColorRect.new()
	backdrop.color = UITheme.BACKDROP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := UIFactory.make_panel()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 400
	column.add_theme_constant_override("separation",16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	var brand := UIFactory.make_label("SIN CITY: DESERT DREAMS",UITheme.FONT_SMALL,UITheme.HEADER)
	brand.add_theme_font_override("font",UITheme.LOGO_FONT)
	column.add_child(brand)
	heading = UIFactory.make_label("Loading…",UITheme.FONT_TITLE)
	heading.add_theme_font_override("font",UITheme.DISPLAY_FONT)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(heading)
	detail = UIFactory.make_label("",UITheme.FONT_BODY,UITheme.TEXT_MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail)
	var activity := ProgressBar.new()
	activity.custom_minimum_size.y = 8
	activity.show_percentage = false
	activity.indeterminate = true
	activity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = UITheme.ROW_ALT
	track.set_corner_radius_all(4)
	activity.add_theme_stylebox_override("background",track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = UITheme.ACCENT_BRASS
	activity.add_theme_stylebox_override("fill",fill)
	column.add_child(activity)
	column.add_child(UIFactory.make_label("Please wait.",UITheme.FONT_SMALL,UITheme.TEXT_MUTED))
	hide()

func open(title: String, message: String) -> void:
	heading.text = title
	detail.text = message
	show()
	grab_focus()

func close() -> void:
	hide()

## Wait until the current frame, with this screen in it, has been drawn.
func presented_frame() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		# Dummy rendering emits no post-draw signal. Keep the same deferred
		# lifecycle in headless tools without waiting for a nonexistent draw.
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw

func _gui_input(_event: InputEvent) -> void:
	accept_event()

func _input(_event: InputEvent) -> void:
	if not visible: return
	# Covered dialogs may reclaim focus in their Tab handlers or when an
	# error opens. Consume input before it can reach their GUI controls.
	grab_focus()
	get_viewport().set_input_as_handled()
