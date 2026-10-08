# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The table header: the resort's name in its sign lettering, the casino
## floor and the game, the live treasury with this sitting's net, the rules
## sheet toggle and Leave table. Narrow layouts move the money and the two
## buttons to a second row so the name keeps the full width; the name and
## the floor line wrap rather than cut off.
class_name CasinoChrome
extends PanelContainer

signal leave_requested
signal rules_toggled(shown: bool)

var resort_label: Label
var place_label: Label
var treasury_label: Label
var net_label: Label
var rules_button: Button
var leave_button: Button

var _top: HBoxContainer
var _money: VBoxContainer
var _bottom: HBoxContainer
var _narrow := false


func _init() -> void:
	name = "CasinoChrome"
	theme = UITheme.control_theme()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 10)
	column.add_child(_top)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	_top.add_child(names)
	resort_label = UIFactory.make_label("", UITheme.FONT_TITLE + 4, UITheme.TEXT_PRIMARY)
	resort_label.name = "ResortName"
	resort_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(resort_label)
	place_label = UIFactory.make_label("", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	place_label.name = "Place"
	place_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(place_label)
	_money = VBoxContainer.new()
	_money.add_theme_constant_override("separation", 0)
	_top.add_child(_money)
	treasury_label = UIFactory.make_label("", UITheme.FONT_BODY, UITheme.MONEY_POSITIVE)
	treasury_label.name = "Treasury"
	treasury_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money.add_child(treasury_label)
	net_label = UIFactory.make_label("", UITheme.FONT_SMALL, UITheme.MONEY_NEUTRAL)
	net_label.name = "SessionNet"
	net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money.add_child(net_label)
	rules_button = UIFactory.make_button("Rules", "Show how this game plays and pays")
	rules_button.name = "Rules"
	rules_button.toggle_mode = true
	rules_button.toggled.connect(func(on: bool) -> void: rules_toggled.emit(on))
	_top.add_child(rules_button)
	leave_button = UIFactory.make_button(CasinoLines.LEAVE_TABLE, "Leave the table (Esc)")
	leave_button.name = "Leave"
	leave_button.pressed.connect(func() -> void: leave_requested.emit())
	_top.add_child(leave_button)
	_bottom = HBoxContainer.new()
	_bottom.add_theme_constant_override("separation", 10)
	_bottom.visible = false
	column.add_child(_bottom)


## Resort name, floor and game, with the resort's lettering and accent rule.
func setup(colors: CasinoPalette, resort_name: String, floor_name: String, game_name: String) -> void:
	resort_label.text = colors.sign_text(resort_name)
	resort_label.add_theme_font_override("font", colors.sign_font)
	place_label.text = "%s · %s" % [floor_name, game_name] if not floor_name.is_empty() else game_name
	var face := StyleBoxFlat.new()
	face.bg_color = UITheme.PANEL_FACE
	face.border_color = colors.accent
	face.border_width_bottom = 4
	face.border_width_top = 1
	face.set_corner_radius_all(UITheme.CORNER)
	face.content_margin_left = 12
	face.content_margin_right = 8
	face.content_margin_top = 4
	face.content_margin_bottom = 6
	add_theme_stylebox_override("panel", face)


## The treasury after every transaction, this sitting's net and the stake
## now riding on the table.
func set_treasury(funds: int, session_net: int, in_play: int) -> void:
	treasury_label.text = "Treasury " + UIFactory.format_signed_amount(funds)
	treasury_label.add_theme_color_override("font_color", UITheme.MONEY_NEGATIVE if funds < 0 else UITheme.MONEY_POSITIVE)
	if in_play > 0:
		net_label.text = "In play " + UIFactory.format_amount(in_play)
		net_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	else:
		net_label.text = "This sitting " + UIFactory.format_money(session_net)
		net_label.add_theme_color_override("font_color", UITheme.MONEY_POSITIVE if session_net > 0 else (UITheme.MONEY_NEGATIVE if session_net < 0 else UITheme.MONEY_NEUTRAL))


func set_leave_enabled(enabled: bool, reason: String = "") -> void:
	leave_button.disabled = not enabled
	leave_button.tooltip_text = "Leave the table (Esc)" if enabled else reason


## Narrow headers put the money and the buttons on their own row; short
## ones use a smaller name.
func apply_layout(narrow: bool, short: bool = false) -> void:
	resort_label.add_theme_font_size_override("font_size", UITheme.FONT_TITLE + (0 if short or narrow else 4))
	if narrow == _narrow:
		return
	_narrow = narrow
	# Moving a focused button out of the tree drops its focus; give it back.
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused != rules_button and focused != leave_button: focused = null
	if narrow:
		_money.reparent(_bottom, false)
		_money.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rules_button.reparent(_bottom, false)
		leave_button.reparent(_bottom, false)
		_bottom.visible = true
		treasury_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		_money.reparent(_top, false)
		_top.move_child(_money, 1)
		_money.size_flags_horizontal = Control.SIZE_FILL
		rules_button.reparent(_top, false)
		leave_button.reparent(_top, false)
		_bottom.visible = false
		treasury_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if focused != null and focused.is_visible_in_tree() and not focused.has_focus():
		focused.grab_focus()
