# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The bet bar: chips worth one, two, five and ten times the table minimum
## and Max, minus and plus for the selected spot, the automatic cash-out of a
## trajectory launch, and one button per game action. Wide tables keep chips
## and actions on one row; narrow ones stack and wrap them.
class_name CasinoBetBar
extends PanelContainer

## A chip was pressed: `index` 0–3 for the denominations, 4 for Max.
signal chip_pressed(index: int)
## Minus (-1) or plus (+1) for the selected spot.
signal step_pressed(direction: int)
signal action_pressed(action: StringName)
signal auto_pressed

const MAX_CHIP := 4
const WIDE := 900.0

var chip_buttons: Array[Button] = []
var minus_button: Button
var plus_button: Button
var auto_button: Button
## Action id -> button.
var action_buttons: Dictionary = {}
var spot_label: Label
var total_label: Label

var _column: VBoxContainer
## A row on wide bars, stacked on narrow ones (see apply_layout).
var _readout: BoxContainer
var _row: HBoxContainer
var _chips: HFlowContainer
var _actions: HFlowContainer
var _selected_chip := 0
var _wide := true


func _init() -> void:
	name = "CasinoBetBar"
	theme = UITheme.control_theme()
	var face := UITheme.shell_stylebox()
	face.border_width_bottom = 0
	face.border_width_top = 2
	face.set_corner_radius_all(UITheme.CORNER)
	face.content_margin_left = 10
	face.content_margin_right = 10
	face.content_margin_top = 6
	face.content_margin_bottom = 6
	add_theme_stylebox_override("panel", face)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 6)
	add_child(_column)
	_readout = BoxContainer.new()
	_readout.add_theme_constant_override("separation", 12)
	_column.add_child(_readout)
	spot_label = UIFactory.make_label("", UITheme.FONT_SMALL, UITheme.TEXT_PRIMARY)
	spot_label.name = "SpotReadout"
	spot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spot_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	spot_label.clip_text = true
	_readout.add_child(spot_label)
	total_label = UIFactory.make_label("", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	total_label.name = "TotalReadout"
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_readout.add_child(total_label)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	_column.add_child(_row)
	_chips = HFlowContainer.new()
	_chips.name = "Chips"
	_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 6)
	_row.add_child(_chips)
	_actions = HFlowContainer.new()
	_actions.name = "Actions"
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.alignment = FlowContainer.ALIGNMENT_END
	_actions.add_theme_constant_override("h_separation", 6)
	_actions.add_theme_constant_override("v_separation", 6)
	_row.add_child(_actions)
	for i in MAX_CHIP + 1:
		var chip := UIFactory.make_button("")
		chip.name = "Chip%d" % i
		chip.custom_minimum_size = Vector2(60, 44)
		chip.pressed.connect(func() -> void: chip_pressed.emit(i))
		_chips.add_child(chip)
		chip_buttons.append(chip)
	minus_button = UIFactory.make_button("-", "Take a chip off the selected spot (-)")
	minus_button.name = "Minus"
	minus_button.pressed.connect(func() -> void: step_pressed.emit(-1))
	_chips.add_child(minus_button)
	plus_button = UIFactory.make_button("+", "Add a chip to the selected spot (+)")
	plus_button.name = "Plus"
	plus_button.pressed.connect(func() -> void: step_pressed.emit(1))
	_chips.add_child(plus_button)
	auto_button = UIFactory.make_button("Auto cash-out: off", "Cash out automatically at this multiplier (A)")
	auto_button.name = "AutoCashOut"
	auto_button.pressed.connect(func() -> void: auto_pressed.emit())
	auto_button.visible = false
	_chips.add_child(auto_button)


## Chip labels and colors for a table minimum; `max_value` is the Max chip.
func set_chips(values: Array[int], max_value: int, minimum: int) -> void:
	for i in chip_buttons.size():
		var chip := chip_buttons[i]
		var amount := max_value if i == MAX_CHIP else (values[i] if i < values.size() else 0)
		chip.text = "Max" if i == MAX_CHIP else CasinoPalette.chip_label(amount)
		chip.tooltip_text = ("Bet up to the maximum, %s (5)" % CasinoLines.money(amount)) if i == MAX_CHIP else ("%s chip (%d)" % [CasinoLines.money(amount), i + 1])
		chip.set_meta("chip_value", amount)
		chip.set_meta("chip_color", CasinoPalette.CHIP_FACES.size() - 1 if i == MAX_CHIP else CasinoPalette.chip_index(amount, minimum))
		_style_chip(i)


func set_selected_chip(index: int) -> void:
	_selected_chip = clampi(index, 0, MAX_CHIP)
	for i in chip_buttons.size():
		_style_chip(i)


func _style_chip(i: int) -> void:
	var chip := chip_buttons[i]
	var color_index := int(chip.get_meta("chip_color", 0))
	var selected := i == _selected_chip
	var key := color_index * 2 + (1 if selected else 0)
	# Restyle only when the chip's color or selection changes: the bar is
	# refreshed on every climb step of a launch.
	if int(chip.get_meta("chip_style", -1)) == key:
		return
	chip.set_meta("chip_style", key)
	var faces: Dictionary = _chip_styles(color_index, selected)
	for state: String in faces:
		chip.add_theme_stylebox_override(state, faces[state])
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		chip.add_theme_color_override(state, CasinoPalette.CHIP_TEXT[color_index])


## Chip faces per color and selection, built once for this bar.
var _chip_style_cache: Dictionary = {}


func _chip_styles(color_index: int, selected: bool) -> Dictionary:
	var key := color_index * 2 + (1 if selected else 0)
	if _chip_style_cache.has(key):
		return _chip_style_cache[key]
	var faces: Dictionary = {}
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var face := StyleBoxFlat.new()
		face.bg_color = CasinoPalette.CHIP_FACES[color_index]
		if state == "hover":
			face.bg_color = face.bg_color.lightened(0.12)
		elif state == "disabled":
			face.bg_color = face.bg_color.lerp(UITheme.ROW_ALT, 0.65)
		face.set_corner_radius_all(22)
		face.border_color = UITheme.ACCENT_BRASS if selected else CasinoPalette.CHIP_SPOTS[color_index]
		face.set_border_width_all(5 if selected else 2)
		face.set_content_margin_all(4)
		faces[state] = face
	_chip_style_cache[key] = faces
	return faces


func selected_chip() -> int:
	return _selected_chip


## Enable the chips and steppers (only while bets can change).
func set_betting_enabled(enabled: bool) -> void:
	for chip in chip_buttons:
		chip.disabled = not enabled
	minus_button.disabled = not enabled
	plus_button.disabled = not enabled
	auto_button.disabled = not enabled


## One button per action, in the game's order; ids in `hidden` are left out
## (the table handles them itself).
func set_actions(actions: Array[Dictionary], hidden: Array[StringName], shortcuts: Dictionary) -> void:
	var shown: Array[StringName] = []
	for action: Dictionary in actions:
		var id := StringName(action["id"])
		if id in hidden:
			continue
		shown.append(id)
		var button: Button = action_buttons.get(id, null)
		var primary := bool(action.get("primary", false))
		if button == null or bool(button.get_meta("primary", false)) != primary:
			if button != null:
				action_buttons.erase(id)
				button.queue_free()
			button = UIFactory.make_primary_button("") if primary else UIFactory.make_button("")
			button.name = "Action_%s" % String(id)
			button.custom_minimum_size = Vector2(96, 44)
			button.set_meta("primary", primary)
			button.pressed.connect(func() -> void: action_pressed.emit(id))
			_actions.add_child(button)
			action_buttons[id] = button
		button.text = String(action["label"])
		button.disabled = not bool(action.get("enabled", true))
		var key := String(shortcuts.get(id, ""))
		button.tooltip_text = "%s (%s)" % [String(action["label"]), key] if not key.is_empty() else String(action["label"])
		button.visible = true
		_actions.move_child(button, shown.size() - 1)
	for id: StringName in action_buttons:
		if id not in shown:
			(action_buttons[id] as Button).visible = false


## The container the action buttons are in now.
func actions_parent() -> Node:
	return _actions.get_parent()


## The first enabled primary action's button, or null.
func primary_button() -> Button:
	for child in _actions.get_children():
		var button := child as Button
		if button != null and button.visible and not button.disabled and bool(button.get_meta("primary", false)):
			return button
	return null


func set_readout(spot_text: String, total_text: String) -> void:
	spot_label.text = spot_text
	total_label.text = total_text


func set_auto(value: float, shown: bool) -> void:
	auto_button.visible = shown
	auto_button.text = "Auto cash-out: %s" % ("%.2fx" % value if value > 0.0 else "off")


## Wide bars keep chips and actions side by side. Short displays hide the
## readout row and, given `side`, stack the actions there (beside the table)
## so the table keeps its height.
func apply_layout(width: float, short: bool, side: Container = null) -> void:
	_readout.visible = not short
	_wide = width >= WIDE
	# Narrow bars let the spot caption wrap instead of cutting it short.
	spot_label.autowrap_mode = TextServer.AUTOWRAP_OFF if _wide else TextServer.AUTOWRAP_WORD_SMART
	spot_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if _wide else TextServer.OVERRUN_NO_TRIMMING
	spot_label.clip_text = _wide
	# ...and on a line of its own, above the bet total.
	_readout.vertical = not _wide
	_readout.add_theme_constant_override("separation", 12 if _wide else 0)
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if _wide else HORIZONTAL_ALIGNMENT_LEFT
	var chips_target: Container = _row if _wide else _column
	var actions_target: Container = side if short and side != null else chips_target
	if _chips.get_parent() != chips_target:
		_chips.reparent(chips_target, false)
	if _actions.get_parent() != actions_target:
		_actions.reparent(actions_target, false)
	_row.visible = _wide
	_actions.alignment = FlowContainer.ALIGNMENT_BEGIN if actions_target == side else FlowContainer.ALIGNMENT_END
	if side != null:
		side.visible = actions_target == side
