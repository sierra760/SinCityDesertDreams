# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Offline code license and developer credit, using the shared window contract.
class_name LicenseWindow
extends Control

signal closed

var panel: PanelContainer
var license_text: RichTextLabel
var done_button: Button

func _init() -> void:
	name = "LicenseWindow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("License and credits")
	panel = chrome["root"]
	panel.name = "Panel"
	(chrome["close_button"] as Button).pressed.connect(close)
	var body: VBoxContainer = chrome["body"]
	var notice := UIFactory.make_label("Developed by Sierra Burkhart (sierra760)\n© 2026 Bristlecone Artists LLC\n\nProject-authored code is free software under GNU GPL version 3 or later. You may redistribute and modify it under that license. It comes with no warranty.\n\nArt, models and included cities are licensed under Creative Commons Attribution-NonCommercial-ShareAlike 4.0 (CC BY-NC-SA 4.0): share and adapt them non-commercially, with credit, under the same license. Fonts and third-party components have separate terms.")
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(notice)
	license_text = RichTextLabel.new()
	license_text.name = "GPLText"
	license_text.bbcode_enabled = false
	license_text.fit_content = true
	license_text.scroll_active = false
	license_text.selection_enabled = true
	license_text.add_theme_color_override("default_color", UITheme.TEXT_PRIMARY)
	license_text.text = FileAccess.get_file_as_string("res://legal/COPYING.txt")
	body.add_child(license_text)
	done_button = UIFactory.make_button("Done")
	done_button.pressed.connect(close)
	(chrome["actions"] as HBoxContainer).add_child(done_button)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = -250
	panel.offset_bottom = 250
	add_child(panel)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	WindowDrag.enable(chrome["title_bar"], panel)
	visible = false

func open() -> void:
	visible = true
	UIFactory.contain_modal_focus(self, done_button)

func close() -> void:
	if not visible: return
	visible = false
	closed.emit()
