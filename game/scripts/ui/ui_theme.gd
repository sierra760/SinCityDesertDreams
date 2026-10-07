# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Design tokens for the game's windows and panels.
## Desert ivory, deep teal and brass. One place for every color and size so the UI stays
## consistent. Static so any UI script can read tokens
## without an instance: UITheme.PANEL_FACE, UITheme.window_stylebox(), etc.
class_name UITheme
extends RefCounted

# ── Surfaces ──
const PANEL_FACE   := Color("eee5d3")
const BEVEL_LIGHT  := Color("fff8eb")
const BEVEL_DARK   := Color("b4a58a")
const DIVIDER      := Color("c8b99d")
const ROW_ALT      := Color("e2d7c0")
const BUTTON_FACE  := Color("f7efdf")
const FIELD_FACE   := Color("fff9ed")
const FOCUS        := Color("80501e")
const BACKDROP     := Color("173e39")
const SHADOW       := Color(0.06, 0.14, 0.12, 0.22)

# ── Title bars / accents ──
const TITLE_BAR      := Color("286c60")
const TITLE_BAR_DARK := Color("20584f")
const TITLE_TEXT     := Color("fff8eb")
const ACCENT_BRASS   := Color("c49a50")
const HEADER         := TITLE_BAR_DARK  # section headers (teal)

# ── Text ──
const TEXT_PRIMARY := Color("293e36")
const TEXT_MUTED   := Color("596153")
## Unavailable controls and menu items: clearly lighter than enabled text so
## the two never read alike, while staying legible (about 3:1 on menus).
const TEXT_DISABLED := Color("948e7e")

# ── Semantic money/state ──
const MONEY_POSITIVE := Color("1a5e4c")
const MONEY_NEGATIVE := Color("9a3b1a")
const MONEY_NEUTRAL  := Color("5a5a48")

# ── Zone identity (icons / RCI meters) ──
const ZONE_R := Color("3f9d3f")
const ZONE_C := Color("3f6fb0")
const ZONE_I := Color("c7a93a")

# ── Font tiers ──
const FONT_TITLE  := 22
const FONT_HEADER := 18
const FONT_BODY   := 16
const FONT_SMALL  := 14

# ── Shape / spacing ──
const CORNER         := 4
const CORNER_BUTTON  := 3
const BORDER         := 1
const MARGIN         := 12
const MARGIN_COMPACT := 8
const VSEP           := 8
const DISPLAY_FONT := preload("res://assets/fonts/biorhyme/BioRhyme-Medium.ttf")
const LOGO_FONT := DISPLAY_FONT

static func window_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_FACE
	sb.border_color = BEVEL_DARK
	sb.set_border_width_all(BORDER)
	sb.set_corner_radius_all(CORNER)
	sb.set_content_margin_all(float(MARGIN))
	sb.shadow_color = SHADOW
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb

static func title_bar_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TITLE_BAR
	sb.corner_radius_top_left = CORNER
	sb.corner_radius_top_right = CORNER
	sb.border_width_bottom = 2
	sb.border_color = ACCENT_BRASS
	sb.set_content_margin_all(float(MARGIN_COMPACT))
	return sb

static func button_stylebox(active := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TITLE_BAR if active else BUTTON_FACE
	sb.border_color = TITLE_BAR_DARK if active else BEVEL_DARK
	sb.set_border_width_all(BORDER)
	sb.set_corner_radius_all(CORNER_BUTTON)
	sb.set_content_margin_all(4.0)
	return sb

## Flat continuous shell chrome; no rounded seam between city and controls.
static func shell_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_FACE
	sb.border_color = ACCENT_BRASS
	sb.border_width_bottom = 2
	return sb

static var _controls: Theme

## Shared read-only theme. Per-widget adjustments use Control overrides.
static func control_theme() -> Theme:
	if _controls != null: return _controls
	var theme := Theme.new()
	theme.default_font = DISPLAY_FONT
	theme.default_font_size = FONT_BODY
	for type in ["Button", "OptionButton", "CheckBox", "LineEdit", "SpinBox", "PopupMenu", "ItemList", "Label", "TooltipLabel", "MenuBar"]:
		theme.set_font_size("font_size", type, FONT_BODY)
		theme.set_color("font_color", type, TEXT_PRIMARY)
	for type in ["Button", "OptionButton", "CheckBox", "MenuBar"]:
		theme.set_stylebox("normal",type,button_stylebox())
		var hover := button_stylebox()
		hover.bg_color = BEVEL_LIGHT
		theme.set_stylebox("hover",type,hover)
		theme.set_stylebox("pressed",type,button_stylebox(true))
		theme.set_stylebox("hover_pressed",type,button_stylebox(true))
		theme.set_color("font_hover_color",type,TEXT_PRIMARY)
		theme.set_color("font_focus_color",type,TEXT_PRIMARY)
		theme.set_color("font_hover_pressed_color",type,TITLE_TEXT)
		var disabled := button_stylebox()
		disabled.bg_color = ROW_ALT
		theme.set_stylebox("disabled",type,disabled)
		theme.set_color("font_disabled_color",type,TEXT_DISABLED)
		theme.set_color("font_pressed_color",type,TITLE_TEXT)
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color.TRANSPARENT
		focus.draw_center = false
		focus.border_color = FOCUS
		focus.set_border_width_all(3)
		focus.set_corner_radius_all(CORNER_BUTTON)
		focus.shadow_color = TITLE_TEXT
		focus.shadow_size = 2
		theme.set_stylebox("focus",type,focus)
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", button_stylebox(true))
	var primary_pressed := button_stylebox(true)
	primary_pressed.bg_color = Color("123f37")
	for state in ["pressed", "hover_pressed"]:
		theme.set_stylebox(state, "PrimaryButton", primary_pressed)
	var primary_hover := button_stylebox(true)
	primary_hover.bg_color = TITLE_BAR_DARK
	theme.set_stylebox("hover", "PrimaryButton", primary_hover)
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		theme.set_color(state, "PrimaryButton", TITLE_TEXT)
	theme.set_type_variation("TitleCloseButton", "Button")
	var close_normal := button_stylebox(true)
	close_normal.border_color = TITLE_BAR
	theme.set_stylebox("normal", "TitleCloseButton", close_normal)
	theme.set_stylebox("hover", "TitleCloseButton", primary_hover)
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		theme.set_color(state, "TitleCloseButton", TITLE_TEXT)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var menu := button_stylebox(state in ["pressed", "hover_pressed"])
		menu.bg_color = BEVEL_LIGHT if state == "hover" else menu.bg_color
		menu.set_border_width_all(0)
		menu.set_corner_radius_all(0)
		menu.content_margin_left = 10
		menu.content_margin_right = 10
		var vertical_padding := maxf(0.0, 44.0 - DISPLAY_FONT.get_height(FONT_BODY))
		menu.content_margin_top = floorf(vertical_padding * 0.5)
		menu.content_margin_bottom = vertical_padding - menu.content_margin_top
		theme.set_stylebox(state, "MenuBar", menu)
	for state in ["font_hover_color", "font_focus_color"]:
		theme.set_color(state, "MenuBar", TEXT_PRIMARY)
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, "MenuBar", TITLE_TEXT)
	theme.set_color("font_disabled_color", "MenuBar", TEXT_DISABLED)
	theme.set_constant("h_separation", "MenuBar", 2)
	for type in ["HSeparator", "VSeparator"]:
		var rule := StyleBoxFlat.new()
		rule.bg_color = DIVIDER
		rule.set_content_margin_all(1)
		theme.set_stylebox("separator", type, rule)
	for state in ["background", "fill"]:
		var progress := StyleBoxFlat.new()
		progress.bg_color = ROW_ALT if state == "background" else TITLE_BAR
		progress.set_corner_radius_all(3)
		theme.set_stylebox(state, "ProgressBar", progress)
	theme.set_constant("item_start_padding","PopupMenu",12)
	# A font line is at least its 16-unit body size; padding retains a
	# 44-unit row even on platforms with shorter font ascent/descent.
	theme.set_constant("v_separation","PopupMenu",28)
	theme.set_color("font_separator_color","PopupMenu",TEXT_MUTED)
	for type in ["Button", "OptionButton", "CheckBox", "MenuBar"]:
		theme.set_color("icon_normal_color",type,TEXT_PRIMARY)
		theme.set_color("icon_hover_color",type,TEXT_PRIMARY)
		theme.set_color("icon_pressed_color",type,TITLE_TEXT)
		theme.set_color("icon_disabled_color",type,TEXT_DISABLED)
	theme.set_stylebox("panel","AcceptDialog",window_stylebox())
	# AcceptDialog reapplies these to Open/Cancel whenever it lays out.
	theme.set_constant("buttons_min_width","AcceptDialog",44)
	theme.set_constant("buttons_min_height","AcceptDialog",44)
	theme.set_color("title_color","Window",TITLE_TEXT)
	theme.set_font_size("title_font_size","Window",FONT_BODY)
	var embedded_border := title_bar_stylebox()
	embedded_border.expand_margin_top = 36.0
	theme.set_stylebox("embedded_border","Window",embedded_border)
	for type in ["LineEdit", "ItemList", "PopupMenu", "TooltipPanel"]:
		var field := window_stylebox()
		field.bg_color = FIELD_FACE
		field.set_content_margin_all(8.0)
		theme.set_stylebox("normal" if type == "LineEdit" else "panel",type,field)
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color.TRANSPARENT
		focus.draw_center = false
		focus.border_color = FOCUS
		focus.set_border_width_all(2)
		focus.set_corner_radius_all(CORNER_BUTTON)
		focus.shadow_color = TITLE_TEXT
		focus.shadow_size = 2
		theme.set_stylebox("focus",type,focus)
		theme.set_color("font_color",type,TEXT_PRIMARY)
		theme.set_color("font_disabled_color",type,TEXT_DISABLED)
		theme.set_color("font_selected_color",type,TITLE_TEXT)
		theme.set_color("font_hover_color",type,TITLE_TEXT)
		theme.set_color("selection_color",type,TITLE_BAR_DARK)
		theme.set_stylebox("hover",type,button_stylebox(true))
		theme.set_stylebox("selected",type,button_stylebox(true))
		theme.set_stylebox("selected_focus",type,button_stylebox(true))
	for type in ["ItemList"]:
		theme.set_color("font_hovered_color",type,TEXT_PRIMARY)
		theme.set_color("font_hovered_selected_color",type,TITLE_TEXT)
		theme.set_stylebox("hovered",type,button_stylebox())
		theme.set_stylebox("hovered_selected",type,button_stylebox(true))
		theme.set_stylebox("hovered_selected_focus",type,button_stylebox(true))
	var read_only := window_stylebox()
	read_only.bg_color = ROW_ALT
	theme.set_stylebox("read_only","LineEdit",read_only)
	theme.set_color("font_uneditable_color","LineEdit",TEXT_MUTED)
	theme.set_color("font_placeholder_color","LineEdit",TEXT_MUTED)
	theme.set_color("caret_color","LineEdit",TEXT_PRIMARY)
	for type in ["HSlider","VSlider","HScrollBar","VScrollBar"]:
		var rail := StyleBoxFlat.new()
		rail.bg_color = BEVEL_DARK
		rail.set_corner_radius_all(3)
		rail.set_content_margin_all(3 if type.ends_with("Slider") else 7)
		var fill := rail.duplicate() as StyleBoxFlat
		fill.bg_color = TITLE_BAR_DARK
		var hover_fill := fill.duplicate() as StyleBoxFlat
		hover_fill.bg_color = TITLE_BAR
		if type.ends_with("Slider"):
			theme.set_stylebox("slider",type,rail)
			theme.set_stylebox("grabber_area",type,fill)
			theme.set_stylebox("grabber_area_highlight",type,hover_fill)
		else:
			theme.set_stylebox("scroll",type,rail)
			theme.set_stylebox("scroll_focus",type,rail)
			theme.set_stylebox("grabber",type,fill)
			theme.set_stylebox("grabber_highlight",type,hover_fill)
			theme.set_stylebox("grabber_pressed",type,hover_fill)
	if MobilePlatform.is_ios():
		# Hide scroll bars on iOS, including the engine-owned bars inside
		# ItemList, PopupMenu and FileDialog. Empty resources remove both the
		# drawing and the gutter; the ranges still scroll. IOSGestureScroll
		# supplies swipe and glide for ScrollContainer and ItemList.
		var empty_style := StyleBoxEmpty.new()
		var empty_icon := ImageTexture.new()
		for type in ["HScrollBar","VScrollBar"]:
			for style in ["scroll","scroll_focus","grabber","grabber_highlight","grabber_pressed"]:
				theme.set_stylebox(style,type,empty_style)
			for icon in ["increment","increment_highlight","increment_pressed","decrement","decrement_highlight","decrement_pressed"]:
				theme.set_icon(icon,type,empty_icon)
			for padding in ["padding_left","padding_right","padding_top","padding_bottom"]:
				theme.set_constant(padding,type,0)
		theme.set_constant("scrollbar_h_separation","ScrollContainer",0)
		theme.set_constant("scrollbar_v_separation","ScrollContainer",0)
	_controls = theme
	return _controls
