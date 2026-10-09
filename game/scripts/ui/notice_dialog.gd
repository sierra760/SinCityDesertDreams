# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A modal notice: a shaded backdrop, a titled panel with a body of text, an
## optional text field and one button per choice. Closing emits `closed`
## with the chosen button's key so the host can act on it.
class_name NoticeDialog
extends Control

signal closed(choice: StringName)

const PANEL_WIDTH := 460
## How long an unrequested notice ignores Enter and choice presses after it
## opens, so a key or tap meant for the city cannot answer it unseen.
const UNREQUESTED_GRACE_MSEC := 300

var title_label: Label
var body_label: Label
var line_edit: LineEdit
var button_row: HBoxContainer
var panel: PanelContainer
var choice_buttons: Array[Button] = []
var _shade: ColorRect
var _title_bar: Control
var _cancel_choice: StringName = &"ok"
## Ticks (msec) when the current unrequested notice opened; -1 otherwise.
var _unrequested_since := -1


func _init() -> void:
	name = "NoticeDialog"
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
	var chrome := UIFactory.make_window_chrome("Notice")
	panel = chrome["root"]
	panel.name = "Panel"
	_title_bar = chrome["title_bar"]
	title_label = (_title_bar.get_child(0) as HBoxContainer).get_child(0)
	(chrome["close_button"] as Button).pressed.connect(func() -> void: dismiss())
	var body: VBoxContainer = chrome["body"]
	body_label = UIFactory.make_label("", UITheme.FONT_BODY)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(0, 0)
	body.add_child(body_label)
	line_edit = LineEdit.new()
	line_edit.name = "TextField"
	line_edit.custom_minimum_size.y = 44
	line_edit.max_length = Builder.SIGN_TEXT_MAX
	line_edit.visible = false
	line_edit.text_submitted.connect(func(_t: String) -> void: dismiss(&"submit"))
	body.add_child(line_edit)
	button_row = chrome["actions"]
	button_row.name = "Buttons"
	button_row.alignment = BoxContainer.ALIGNMENT_END
	button_row.add_theme_constant_override("separation", 8)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL_WIDTH / 2.0
	panel.offset_right = PANEL_WIDTH / 2.0
	panel.offset_top = -100
	panel.offset_bottom = 100
	panel.set_meta("preferred_size",Vector2(PANEL_WIDTH,280))
	add_child(panel)
	WindowDrag.enable(_title_bar, panel)


## Show the notice. `choices` is a list of [label, key] pairs; the first is
## the default. With `prompt` true a text field is shown holding `initial`.
## A notice that arrives on its own (`focus_choice` false) keeps keyboard focus
## on the panel, so a Space or Enter meant for the city cannot press a choice.
func show_notice(title: String, body: String, choices: Array = [["OK", &"ok"]],
		prompt := false, initial := "", cancel_choice: StringName = &"", focus_choice := true) -> void:
	_cancel_choice = cancel_choice if cancel_choice != &"" else &"ok"
	if cancel_choice == &"":
		for pair in choices:
			if StringName(String(pair[1])) in [&"cancel", &"decline", &"no"]:
				_cancel_choice = StringName(String(pair[1]))
				break
	title_label.text = title
	body_label.text = body
	var chrome: Dictionary = panel.get_meta("window_chrome")
	(chrome["body_scroll"] as ScrollContainer).scroll_vertical = 0
	line_edit.visible = prompt
	line_edit.text = initial
	for b in choice_buttons:
		b.queue_free()
	choice_buttons.clear()
	for pair in choices:
		var label := String(pair[0])
		var key := StringName(String(pair[1]))
		var b := UIFactory.make_button(label)
		b.custom_minimum_size = Vector2(80, 44)
		b.pressed.connect(func() -> void:
			if not in_grace_period(): dismiss(key))
		button_row.add_child(b)
		choice_buttons.append(b)
	visible = true
	panel.size.y = maxf(panel.size.y,260.0)
	# The panel itself takes focus only for an unrequested notice; Escape
	# then dismisses it and Enter picks the first (safe) choice.
	focus_mode = Control.FOCUS_NONE if prompt or focus_choice else Control.FOCUS_ALL
	_unrequested_since = -1 if prompt or focus_choice else Time.get_ticks_msec()
	UIFactory.contain_modal_focus(self,line_edit if prompt else self if not focus_choice else choice_buttons[0] if not choice_buttons.is_empty() else null)


## Closing the chrome/Escape never submits a destructive choice. Ordinary
## notices acknowledge with ok; choice dialogs use their explicit cancel key.
func dismiss(choice: StringName = &"") -> void:
	if not visible:
		return
	if choice == &"":
		choice = _cancel_choice
	visible = false
	closed.emit(choice)


func is_open() -> bool:
	return visible


## True while an unrequested notice has only just opened: Enter and choice
## presses are ignored then (Escape and the close button still dismiss it
## with its safe choice).
func in_grace_period() -> bool:
	return _unrequested_since >= 0 and Time.get_ticks_msec() - _unrequested_since < UNREQUESTED_GRACE_MSEC


func prompt_text() -> String:
	return line_edit.text.strip_edges()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			if not key.echo: dismiss()
			accept_event()
		elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			# A held Enter (echo), or one right as an unrequested notice
			# opened, was meant for something else: it never answers.
			if key.echo or in_grace_period():
				accept_event()
			elif not choice_buttons.is_empty() and not line_edit.visible:
				(choice_buttons[0] as Button).pressed.emit()
				accept_event()
