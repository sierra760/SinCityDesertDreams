# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A typed numeric field with full-height adjustment actions. The hidden
## SpinBox retains Godot's numeric expression, snapping and range behavior.
class_name TouchNumberField
extends HBoxContainer

signal value_changed(value: float)

var _number := SpinBox.new()
var _edit := LineEdit.new()
var _minus: Button
var _plus: Button
## True while the player has typed text that apply() has not yet committed.
## Refreshes from the simulation then leave that text alone.
var _typing := false

var value: float:
	get: return _number.value
	set(amount):
		_number.value = amount
		_sync_controls()

var min_value: float:
	get: return _number.min_value
	set(amount):
		_number.min_value = amount
		_sync_controls()

var max_value: float:
	get: return _number.max_value
	set(amount):
		_number.max_value = amount
		_sync_controls()

var step: float:
	get: return _number.step
	set(amount):
		_number.step = amount
		_sync_controls()


func _init() -> void:
	custom_minimum_size.y = 44
	add_theme_constant_override("separation", 4)
	_number.hide()
	add_child(_number)
	_number.value_changed.connect(_on_value_changed)
	_minus = UIFactory.make_button("−", "Decrease value")
	_minus.name = "Decrease"
	_minus.pressed.connect(_adjust.bind(-1))
	add_child(_minus)
	_edit.name = "Value"
	_edit.theme = UITheme.control_theme()
	_edit.custom_minimum_size = Vector2(64, 44)
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit.select_all_on_focus = true
	_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_edit.text_changed.connect(_on_text_changed)
	_edit.text_submitted.connect(_on_text_submitted)
	_edit.focus_exited.connect(apply)
	add_child(_edit)
	_plus = UIFactory.make_button("+", "Increase value")
	_plus.name = "Increase"
	_plus.pressed.connect(_adjust.bind(1))
	add_child(_plus)
	_sync_controls()


func get_line_edit() -> LineEdit:
	return _edit


func set_value_no_signal(amount: float) -> void:
	_number.set_value_no_signal(amount)
	_sync_controls()


## Commit through the same parser used by ordinary SpinBox typing, including
## arithmetic expressions and recovery from text that is not a number.
func apply() -> void:
	_typing = false
	_number.get_line_edit().text = _edit.text
	_number.apply()
	_sync_controls()


func _on_text_submitted(_text: String) -> void:
	apply()


func _on_text_changed(_text: String) -> void:
	_typing = true
	## Pending typing may move away from the old value's range boundary.
	_minus.disabled = false
	_plus.disabled = false


func _adjust(direction: int) -> void:
	apply()
	value += float(direction) * step


func _on_value_changed(amount: float) -> void:
	_sync_controls()
	value_changed.emit(amount)


func _sync_controls() -> void:
	## A hidden SpinBox does not redraw its editor after range changes.
	## Format the live range value rather than reading that stale editor.
	## Uncommitted typing in the focused editor is kept until it is applied.
	if _typing and _edit.has_focus():
		return
	_typing = false
	_edit.text = String.num(value).trim_suffix(".0")
	if _minus != null:
		_minus.disabled = value <= min_value
	if _plus != null:
		_plus.disabled = value >= max_value
