# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A small modal quote for construction that needs the player's answer: which
## bridge to build, whether to bore a tunnel, whether to connect to the town
## next door. One row per option with its price, a Build button and Cancel.
## `chosen` carries the option key; `cancelled` means nothing is built.
class_name ConstructionChoiceDialog
extends Control

signal chosen(key: StringName)
signal cancelled

const PANEL_WIDTH := 400

var title_label: Label
var body_label: Label
var price_label: Label
var option_rows: VBoxContainer
var build_button: Button
var cancel_button: Button
var panel: PanelContainer
## One button per option, in the order given to `open`.
var option_buttons: Array[Button] = []
var _options: Array[Dictionary] = []
var _selected := -1
var _funds := 0
var _shade: ColorRect
var _title_bar: Control
var _group: ButtonGroup


func _init() -> void:
	name = "ConstructionChoiceDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func _build() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.22)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	var chrome := UIFactory.make_window_chrome("Build")
	panel = chrome["root"]
	panel.name = "Panel"
	_title_bar = chrome["title_bar"]
	title_label = (_title_bar.get_child(0) as HBoxContainer).get_child(0)
	(chrome["close_button"] as Button).pressed.connect(cancel)
	var body: VBoxContainer = chrome["body"]
	body_label = UIFactory.make_label("", UITheme.FONT_BODY)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(0, 0)
	body.add_child(body_label)
	option_rows = VBoxContainer.new()
	option_rows.name = "Options"
	option_rows.add_theme_constant_override("separation", 2)
	body.add_child(option_rows)
	price_label = UIFactory.make_label("", UITheme.FONT_BODY, UITheme.TEXT_MUTED)
	price_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(price_label)
	var buttons: HBoxContainer = chrome["actions"]
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	cancel_button = UIFactory.make_button("Cancel")
	cancel_button.custom_minimum_size = Vector2(80, 44)
	cancel_button.pressed.connect(cancel)
	buttons.add_child(cancel_button)
	build_button = UIFactory.make_button("Build")
	build_button.custom_minimum_size = Vector2(80, 44)
	build_button.pressed.connect(confirm)
	buttons.add_child(build_button)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL_WIDTH / 2.0
	panel.offset_right = PANEL_WIDTH / 2.0
	panel.offset_top = -90
	panel.offset_bottom = 90
	panel.set_meta("preferred_size",Vector2(PANEL_WIDTH,300))
	add_child(panel)
	WindowDrag.enable(_title_bar, panel)


## Show the quote. `options` is a list of {key, label, cost}; the first one
## is selected. `action` names the Build button. Options the treasury cannot
## pay for stay listed but cannot be chosen.
func open(title: String, body: String, options: Array, funds: int, action := "Build") -> void:
	title_label.text = title
	body_label.text = body
	build_button.text = action
	_funds = funds
	_options.clear()
	for b in option_buttons:
		b.queue_free()
	option_buttons.clear()
	_group = ButtonGroup.new()
	for entry in options:
		var option: Dictionary = entry
		_options.append(option)
	for i in _options.size():
		var option := _options[i]
		var b := CheckBox.new()
		b.custom_minimum_size.y = 44
		b.button_group = _group
		b.text = "%s  %s" % [String(option.get("label", String(option.get("key", "")))), _price(int(option.get("cost", 0)))]
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_select_index(i))
		option_rows.add_child(b)
		option_buttons.append(b)
	visible = true
	_selected = -1
	if not option_buttons.is_empty():
		option_buttons[0].button_pressed = true
		_select_index(0)
	else:
		build_button.disabled = true
	panel.size.y = maxf(panel.size.y,260.0)
	UIFactory.contain_modal_focus(self,cancel_button if build_button.disabled else build_button)


## Select an option by key; returns false when no such option is listed.
func select(key: StringName) -> bool:
	for i in _options.size():
		if StringName(String(_options[i].get("key", ""))) == key:
			option_buttons[i].button_pressed = true
			_select_index(i)
			return true
	return false


func _select_index(i: int) -> void:
	_selected = i
	var cost := int(_options[i].get("cost", 0))
	var affordable := cost <= _funds
	price_label.text = "Cost: %s" % _price(cost) if affordable else "Cost: %s (the treasury holds %s)" % [_price(cost), _price(_funds)]
	build_button.disabled = not affordable


## Key of the selected option, or empty.
func selected_key() -> StringName:
	if _selected < 0 or _selected >= _options.size():
		return &""
	return StringName(String(_options[_selected].get("key", "")))


## Build with the selected option.
func confirm() -> void:
	if not visible or build_button.disabled:
		return
	var key := selected_key()
	if key == &"":
		return
	visible = false
	chosen.emit(key)


func cancel() -> void:
	if not visible:
		return
	visible = false
	cancelled.emit()


func is_open() -> bool:
	return visible


static func _price(cost: int) -> String:
	return UIFactory.format_signed_amount(cost)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			cancel()
			accept_event()
		elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			confirm()
			accept_event()
