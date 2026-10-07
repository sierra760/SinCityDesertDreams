# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Save As: a name for the city file.
class_name SaveDialog
extends Control

signal save_requested(save_name: String)
signal closed

var name_edit: LineEdit
var save_button: Button
var cancel_button: Button
var hint_label: Label
var filename_label: Label
var panel: PanelContainer


func _init() -> void:
	name = "SaveDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var chrome := UIFactory.make_window_chrome("Save City As")
	panel = chrome["root"]
	panel.name = "Panel"
	panel.set_meta("preferred_size", Vector2(420, 300))
	(chrome["close_button"] as Button).pressed.connect(close)
	var body: VBoxContainer = chrome["body"]
	body.add_child(UIFactory.make_section_header("File name"))
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.custom_minimum_size.y = 44
	name_edit.max_length = 40
	name_edit.placeholder_text = "city name"
	name_edit.text_submitted.connect(func(_t: String) -> void: confirm())
	body.add_child(name_edit)
	filename_label = UIFactory.make_label("", UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	filename_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(filename_label)
	name_edit.text_changed.connect(func(_text: String): _update_filename())
	hint_label = UIFactory.make_label("Save folder: %s" % ProjectSettings.globalize_path(SaveFormat.default_dir()), UITheme.FONT_SMALL, UITheme.TEXT_MUTED)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint_label)
	var row: HBoxContainer = chrome["actions"]
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	cancel_button = UIFactory.make_button("Cancel")
	cancel_button.pressed.connect(close)
	row.add_child(cancel_button)
	save_button = UIFactory.make_primary_button("Save")
	save_button.pressed.connect(confirm)
	row.add_child(save_button)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -170
	panel.offset_right = 170
	panel.offset_top = -70
	panel.offset_bottom = 70
	add_child(panel)
	WindowDrag.enable(chrome["title_bar"], panel)


func open(default_name: String = "") -> void:
	name_edit.text = default_name
	hint_label.text = "Save folder: %s" % ProjectSettings.globalize_path(SaveFormat.default_dir())
	_update_filename()
	visible = true
	UIFactory.contain_modal_focus(self, name_edit)
	name_edit.select_all()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


## Accept the typed name; an empty name is refused.
func confirm() -> void:
	var save_name := clean_name(name_edit.text)
	if save_name.is_empty():
		hint_label.text = "Type a name for the file."
		return
	visible = false
	save_requested.emit(save_name)
	closed.emit()


## Characters no common file system accepts in a file name.
const UNSAFE_CHARACTERS := "/\\:*?\"<>|"
## Device names Windows reserves, with or without an extension.
const RESERVED_NAMES: Array[String] = ["CON", "PRN", "AUX", "NUL",
	"COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
	"LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]


## A file-system safe version of a name. Accents and every script are kept;
## only path separators, wildcard/reserved punctuation and control characters
## are dropped. Leading/trailing dots and spaces are trimmed, and Windows device
## names gain a suffix.
static func clean_name(text: String) -> String:
	var source := text.strip_edges()
	if source.to_lower().ends_with("." + SaveFormat.EXTENSION):
		source = source.left(-SaveFormat.EXTENSION.length() - 1).strip_edges()
	var out := ""
	for ch in source:
		var code := ch.unicode_at(0)
		if code < 32 or (code >= 127 and code <= 159) or UNSAFE_CHARACTERS.contains(ch):
			continue
		out += ch
	out = " ".join(out.split(" ", false))
	# Dots or spaces at either end are hidden files or invalid on Windows.
	while not out.is_empty() and (out.begins_with(".") or out.begins_with(" ")):
		out = out.substr(1)
	while not out.is_empty() and (out.ends_with(".") or out.ends_with(" ")):
		out = out.left(-1)
	var stem := out.get_slice(".", 0)
	if stem.strip_edges().to_upper() in RESERVED_NAMES:
		out = stem.strip_edges() + " city" + out.substr(stem.length())
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		accept_event()


func _update_filename() -> void:
	var resolved := clean_name(name_edit.text)
	filename_label.text = "File: %s.%s" % [resolved, SaveFormat.EXTENSION] if not resolved.is_empty() else "Enter a name to choose the save file."


## The host can retain the current text when a write is refused.
func set_error(message: String) -> void:
	hint_label.text = message
	visible = true
	UIFactory.contain_modal_focus(self, name_edit)
