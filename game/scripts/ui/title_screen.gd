# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A composed title lockup, framed desert illustration and aligned city actions.
class_name TitleScreen
extends Control

const BRAND_FONT := preload("res://assets/fonts/biorhyme-expanded/BioRhymeExpanded-Bold.ttf")
const EDITION_FONT := preload("res://assets/fonts/biorhyme-expanded/BioRhymeExpanded-Regular.ttf")
const EDITION_SIZE_RATIO := 0.42

signal new_city_requested
signal load_requested
signal import_requested
signal settings_requested
signal help_requested
signal license_requested
signal quit_requested

var new_button: Button
var load_button: Button
var import_button: Button
var quit_button: Button
var subtitle: Label
var settings_button: Button
var help_button: Button
## Main supplies whether a dialog, picker or loading screen owns input; the
## title's keyboard shortcuts wait while it returns true.
var shortcuts_blocked: Callable
var license_button: Button
var developer_credit: Label
var copyright_credit: Label
var _panel: PanelContainer
var _poster: PanelContainer
var _content_margin: MarginContainer
var _content: VBoxContainer
var _header: HBoxContainer
var _body: BoxContainer
var _actions_scroll: ScrollContainer
var _city_actions: BoxContainer
var _preferences: BoxContainer
var _actions: VBoxContainer
var _small_brand: Label
var _logo: Label
var _title: Label
var _eyebrow: Label
var _guide: Label
var _artwork: TextureRect
var _bounds := Rect2()
var _reveal_pending := false

func _init() -> void:
	name = "TitleScreen"
	theme = UITheme.control_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	resized.connect(_reflow)

func _ready() -> void:
	_reflow()

func set_mayor_name(value: String) -> void:
	var mayor := ViewPreferences.clean_mayor_name(value)
	_eyebrow.text = "WELCOME, MAYOR" if mayor.is_empty() else "WELCOME, MAYOR %s" % mayor.to_upper()
	_reflow()

func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = UITheme.BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_panel = UIFactory.make_panel()
	_panel.name = "Panel"
	var frame := UITheme.window_stylebox()
	frame.set_content_margin_all(0)
	frame.border_color = UITheme.ACCENT_BRASS
	frame.shadow_size = 16
	frame.shadow_offset = Vector2(0, 8)
	_panel.add_theme_stylebox_override("panel", frame)
	add_child(_panel)
	_content_margin = MarginContainer.new()
	_panel.add_child(_content_margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	_content_margin.add_child(_content)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 24)
	_content.add_child(_header)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 0)
	_header.add_child(identity)
	_title = UIFactory.make_label("SIN CITY", 56, UITheme.HEADER)
	_title.name = "BrandTitle"
	_title.add_theme_font_override("font", BRAND_FONT)
	identity.add_child(_title)
	_logo = UIFactory.make_label("DESERT DREAMS", 24, UITheme.TEXT_MUTED)
	_logo.name = "BrandEdition"
	_logo.add_theme_font_override("font", EDITION_FONT)
	identity.add_child(_logo)
	subtitle = UIFactory.make_label("Big plans.\nRoom to grow.", UITheme.FONT_BODY, UITheme.TEXT_MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_header.add_child(subtitle)
	var rule := HSeparator.new()
	_content.add_child(rule)
	_body = BoxContainer.new()
	_body.name = "TitleBody"
	_body.add_theme_constant_override("separation", 32)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_body)
	_poster = PanelContainer.new()
	_poster.name = "Postcard"
	_poster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_poster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mat := StyleBoxFlat.new()
	mat.bg_color = UITheme.PANEL_FACE
	mat.border_color = UITheme.DIVIDER
	mat.set_border_width_all(1)
	_poster.add_theme_stylebox_override("panel", mat)
	_body.add_child(_poster)
	_artwork = TextureRect.new()
	_artwork.name = "DesertSkyline"
	_artwork.texture = preload("res://assets/ui/oro-canyon-splash.png")
	_artwork.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Fill every frame shape, cropping the centered image without distortion.
	_artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_poster.add_child(_artwork)
	_actions_scroll = ScrollContainer.new()
	_actions_scroll.name = "CityActions"
	_actions_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_actions_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_actions_scroll.follow_focus = true
	_actions_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_actions_scroll)
	_actions = VBoxContainer.new()
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_theme_constant_override("separation", 12)
	_actions_scroll.add_child(_actions)
	_small_brand = UIFactory.make_label("SIN CITY · DESERT DREAMS", UITheme.FONT_SMALL, UITheme.HEADER)
	_small_brand.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_small_brand.hide()
	_actions.add_child(_small_brand)
	_eyebrow = UIFactory.make_label("WELCOME, MAYOR", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_eyebrow.name = "MayorGreeting"
	_eyebrow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_child(_eyebrow)
	new_button = _button(_actions, "New City", func() -> void: new_city_requested.emit(), true)
	_city_actions = BoxContainer.new()
	_city_actions.add_theme_constant_override("separation", 8)
	_actions.add_child(_city_actions)
	load_button = _button(_city_actions, "Load City", func() -> void: load_requested.emit())
	import_button = _button(_city_actions, "Import Classic City", func() -> void: import_requested.emit())
	_preferences = BoxContainer.new()
	_preferences.add_theme_constant_override("separation", 8)
	_actions.add_child(_preferences)
	settings_button = _button(_preferences, "Settings", func() -> void: settings_requested.emit())
	help_button = _button(_preferences, "Help", func() -> void: help_requested.emit())
	help_button.tooltip_text = "Playing the Game: controls and how to start a city"
	quit_button = _button(_preferences, "Quit", func() -> void: quit_requested.emit())
	_guide = UIFactory.make_label("Shape the skyline.\nExplore the streets.", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	_guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_actions.add_child(_guide)
	var footer := HBoxContainer.new()
	footer.name = "Credits"
	footer.add_theme_constant_override("separation", 12)
	_content.add_child(footer)
	var credits := VBoxContainer.new()
	credits.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	credits.add_theme_constant_override("separation", 2)
	footer.add_child(credits)
	developer_credit = UIFactory.make_label("Developed by Sierra Burkhart (sierra760)", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	developer_credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.add_child(developer_credit)
	copyright_credit = UIFactory.make_label("© 2026 Bristlecone Artists LLC", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	copyright_credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.add_child(copyright_credit)
	for credit: Label in [developer_credit,copyright_credit]:
		credit.resized.connect(func() -> void: _reflow.call_deferred())
	license_button = _button(footer, "License", func() -> void: license_requested.emit())
	license_button.size_flags_horizontal = Control.SIZE_FILL
	license_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _button(parent: Control, text: String, handler: Callable, primary := false) -> Button:
	var button := UIFactory.make_primary_button(text) if primary else UIFactory.make_button(text)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	parent.add_child(button)
	return button

## Main supplies the same safe/keyboard rectangle as the other UI.
func apply_layout(bounds: Rect2) -> void:
	_bounds = bounds
	_reflow()

func _reflow() -> void:
	if not is_inside_tree(): return
	var available := _bounds if _bounds.has_area() else Rect2(Vector2.ZERO, size)
	var compact := available.size.x < 900 or available.size.y < 620
	var portrait := available.size.x < 760 and available.size.y >= 700
	var actions_only := available.size.x < 620 or available.size.y < 300
	var short := available.size.y < 300
	var edge := 16.0 if compact else 24.0
	var wanted := Vector2(minf(1040, available.size.x - edge * 2), minf(800 if portrait else 640, available.size.y - edge * 2))
	var padding := 16 if compact else 32
	for side in ["left", "right", "top", "bottom"]:
		_content_margin.add_theme_constant_override("margin_" + side, padding)
	# Establish wrapped credit widths before the panel's minimum height is
	# measured. A fresh label's zero width otherwise counts every letter.
	var credit_width := maxf(1.0,wanted.x-float(padding)*2.0-license_button.get_combined_minimum_size().x-12.0)
	developer_credit.size.x = credit_width
	copyright_credit.size.x = credit_width
	_header.visible = not short
	subtitle.visible = not compact
	_small_brand.visible = short
	_eyebrow.visible = not short and not (compact and available.size.y < 420 and not actions_only)
	_guide.visible = not compact and available.size.y >= 700
	# The expanded face stays proportional without extra tracking. Fit the
	# title to the identity column before deriving the edition's smaller size.
	var identity_width := wanted.x - float(padding) * 2.0
	if subtitle.visible:
		identity_width -= subtitle.get_combined_minimum_size().x + 24.0
	var preferred_size := 32 if compact else 56
	var title_width := BRAND_FONT.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, preferred_size).x
	var title_size := mini(preferred_size, maxi(1, floori(float(preferred_size) * identity_width / title_width)))
	_title.add_theme_font_size_override("font_size", title_size)
	_logo.add_theme_font_size_override("font_size", maxi(1, roundi(float(title_size) * EDITION_SIZE_RATIO)))
	_content.add_theme_constant_override("separation", 8 if compact else 12)
	_body.vertical = portrait and not actions_only
	_body.add_theme_constant_override("separation", 16 if compact else 32)
	_poster.visible = not actions_only
	_poster.custom_minimum_size = Vector2(0, (wanted.x - padding * 2) * 2.0 / 3.0) if _body.vertical else Vector2.ZERO
	_actions_scroll.custom_minimum_size.x = 0 if actions_only or _body.vertical else (320 if compact else 288)
	_actions_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL if actions_only or _body.vertical else Control.SIZE_FILL
	# A new wrapped greeting must have its column width before panel height is measured.
	var greeting_column := wanted.x-float(padding)*2.0 if actions_only or _body.vertical else (320.0 if compact else 288.0)
	_eyebrow.size.x = maxf(1.0,greeting_column-16.0) # Reserve the vertical scrollbar before container layout.
	_actions.custom_minimum_size.x = 0
	_actions.add_theme_constant_override("separation", 8)
	_city_actions.vertical = (not compact and not portrait) or actions_only
	_preferences.vertical = not compact or portrait or actions_only
	for button: Button in [new_button, load_button, import_button, settings_button, help_button, quit_button]:
		button.custom_minimum_size = Vector2(0, 44 if compact else (56 if button == new_button else 48))
		button.add_theme_font_size_override("font_size", 16 if compact else 18)
	if not _city_actions.vertical:
		var shared_width := maxf(load_button.get_minimum_size().x, import_button.get_minimum_size().x)
		load_button.custom_minimum_size.x = shared_width
		import_button.custom_minimum_size.x = shared_width
	if not _body.vertical:
		# The action column scrolls only as a last resort. Whenever the screen
		# has the room, the panel grows past its preferred height so every
		# action, the greeting and the credits are in view at once. On a
		# short screen the layout tightens step by step before it may scroll:
		# shorter buttons with the preferences in a row, then no greeting,
		# then no subtitle, then narrower padding.
		var room := available.size.y - edge * 2
		for tighten in 5:
			var body_min := _body.get_combined_minimum_size().y
			var needed := _content.get_combined_minimum_size().y - body_min + maxf(body_min, _actions.get_combined_minimum_size().y) + float(padding) * 2.0
			if needed <= room or tighten == 4:
				wanted.y = minf(maxf(wanted.y, needed), room)
				break
			match tighten:
				0:
					for button: Button in [new_button, load_button, import_button, settings_button, help_button, quit_button]:
						button.custom_minimum_size.y = 44
					_actions.add_theme_constant_override("separation", 6)
					_preferences.vertical = false
				1: _eyebrow.visible = false
				2: subtitle.visible = false
				3:
					padding = 16
					for side in ["left", "right", "top", "bottom"]:
						_content_margin.add_theme_constant_override("margin_" + side, padding)
					_content.add_theme_constant_override("separation", 8)
	if _body.vertical:
		# Reserve the complete button list before assigning portrait artwork
		# height. The illustration yields space rather than clipping actions.
		var body_height := wanted.y - float(padding) * 2.0
		var visible_sections := 0
		for section: Control in _content.get_children():
			if not section.visible: continue
			visible_sections += 1
			if section != _body:
				body_height -= section.get_combined_minimum_size().y
		body_height -= float(maxi(0, visible_sections - 1) * _content.get_theme_constant("separation"))
		var artwork_height := body_height - _actions.get_combined_minimum_size().y - float(_body.get_theme_constant("separation"))
		_poster.custom_minimum_size.y = maxf(0.0, minf(_poster.custom_minimum_size.y, artwork_height))
	_panel.size = wanted
	_panel.position = available.position + (available.size - _panel.size) * 0.5
	_reveal_focused_action()

func _reveal_focused_action() -> void:
	if _reveal_pending or not is_inside_tree(): return
	_reveal_pending = true
	# Container reflow can move an already-focused action without emitting a
	# focus change. Bound one-shot callbacks also disconnect on host teardown.
	get_tree().process_frame.connect(_reveal_after_layout.bind(1), CONNECT_ONE_SHOT)

func _reveal_after_layout(frames_left: int) -> void:
	if not is_inside_tree():
		_reveal_pending = false
		return
	if frames_left > 0:
		get_tree().process_frame.connect(_reveal_after_layout.bind(frames_left - 1), CONNECT_ONE_SHOT)
		return
	_reveal_pending = false
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and _actions_scroll.is_ancestor_of(focused):
		# The first action fits with its greeting; discard stale scroll from an earlier wrapped height.
		if focused == new_button: _actions_scroll.scroll_vertical = 0
		_actions_scroll.ensure_control_visible(focused)

## The City menu's file shortcuts also work on the title, where the menu bar
## is hidden: Cmd/Ctrl+N, Cmd/Ctrl+O and Cmd/Ctrl+, (Settings). Handled as a
## shortcut so the hidden menu bar's accelerators cannot swallow them first.
func _shortcut_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey: return
	var key := event as InputEventKey
	if not key.pressed or key.echo or not key.is_command_or_control_pressed() or key.alt_pressed or key.shift_pressed: return
	if shortcuts_blocked.is_valid() and bool(shortcuts_blocked.call()): return
	match key.keycode:
		KEY_N: new_city_requested.emit()
		KEY_O: load_requested.emit()
		KEY_COMMA: settings_requested.emit()
		_: return
	get_viewport().set_input_as_handled()

func open() -> void:
	visible = true
	_reflow()
	new_button.grab_focus()

func close() -> void:
	visible = false
