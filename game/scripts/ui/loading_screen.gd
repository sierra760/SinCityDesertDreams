# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## One opaque loading surface above the city, chrome and modal dialogs.
## The host gives it a draw before starting work and before revealing the view.
class_name GameLoadingScreen
extends Control

var heading: Label
var detail: Label
var _center: CenterContainer
var _column: VBoxContainer
var _layout: DisplayLayout
var _brand: Label
var _wait: Label

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
	_center = center
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	center.minimum_size_changed.connect(_fit)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := UIFactory.make_panel()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var column := VBoxContainer.new()
	_column = column
	column.custom_minimum_size.x = 400
	column.add_theme_constant_override("separation",16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	var brand := UIFactory.make_label("SIN CITY · DESERT DREAMS",UITheme.FONT_SMALL,UITheme.HEADER)
	_brand = brand
	brand.add_theme_font_override("font",UITheme.LOGO_FONT)
	brand.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(brand)
	heading = UIFactory.make_label("Loading…",UITheme.FONT_TITLE)
	heading.add_theme_font_override("font",UITheme.DISPLAY_FONT)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(heading)
	detail = UIFactory.make_label("",UITheme.FONT_BODY,UITheme.TEXT_MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	_wait = UIFactory.make_label("Please wait.",UITheme.FONT_SMALL,UITheme.TEXT_MUTED)
	column.add_child(_wait)
	hide()
	resized.connect(_fit)

func _ready() -> void:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is GameHost:
			_layout = ancestor.display_layout
			_layout.metrics_changed.connect(func(_metrics: Dictionary) -> void: _fit())
			break
		ancestor = ancestor.get_parent()
	_fit()

func _fit() -> void:
	if not is_inside_tree(): return
	var usable := _layout.logical_rect() if is_instance_valid(_layout) else Rect2(Vector2.ZERO, size)
	# Long filenames cannot grow this noninteractive surface off screen.
	# With a keyboard or short landscape, retain the operation and activity
	# indicator while the secondary branding yields its space.
	var short := usable.size.y < 280.0
	_brand.visible = not short
	_wait.visible = not short
	_column.add_theme_constant_override("separation", 8 if short else 16)
	heading.max_lines_visible = 1 if short else 2
	detail.max_lines_visible = 2 if short else 3
	_center.position = usable.position
	_center.size = usable.size
	var panel := _column.get_parent() as PanelContainer
	var padding := panel.get_theme_stylebox("panel").get_minimum_size().x
	_column.custom_minimum_size.x = maxf(1.0, minf(400.0, usable.size.x - 32.0 - padding))

func open(title: String, message: String) -> void:
	heading.text = title
	detail.text = message
	_fit()
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
