# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Offline code license and developer credit, using the shared window contract.
## Engine licenses (Godot's MIT license and the notices of the libraries the
## engine bundles) come from the running engine itself, so every platform,
## including iOS, Android and Web where no file can be opened, shows them.
class_name LicenseWindow
extends Control

signal closed

## Bundled font license files, shown with the engine licenses.
const FONT_NOTICES := [
	["BioRhyme", "res://assets/fonts/biorhyme/OFL.txt"],
	["BioRhyme Expanded", "res://assets/fonts/biorhyme-expanded/OFL.txt"],
	["Atomic Age", "res://assets/fonts/atomic-age/OFL.txt"],
	["Fontdiner Swanky", "res://assets/fonts/fontdiner-swanky/LICENSE.txt"],
]
## godot-cpp ships inside the native extensions of Apple and Windows builds.
const GODOT_CPP_NOTICE := "res://addons/scdd_geometry/GODOT-CPP-LICENSE.md"

var panel: PanelContainer
var license_text: RichTextLabel
var engine_button: Button
var engine_text: RichTextLabel
var done_button: Button

func _init() -> void:
	name = "LicenseWindow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("License and Credits")
	panel = chrome["root"]
	panel.name = "Panel"
	(chrome["close_button"] as Button).pressed.connect(close)
	var body: VBoxContainer = chrome["body"]
	var notice := UIFactory.make_label("Developed by Sierra Burkhart (sierra760)\n© 2026 Bristlecone Artists LLC\n\nProject-authored code is free software under GNU GPL version 3 or later. You may redistribute and modify it under that license. It comes with no warranty.\n\nArt, models and included cities are licensed under Creative Commons Attribution-NonCommercial-ShareAlike 4.0 (CC BY-NC-SA 4.0): share and adapt them non-commercially, with credit, under the same license. Fonts, the Godot Engine and its third-party components have separate terms, listed under Engine licenses below.")
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
	body.add_child(UIFactory.make_section_header("Engine licenses"))
	var engine_note := UIFactory.make_label("Built with the Godot Engine (MIT license), which includes third-party libraries such as FreeType, HarfBuzz, ICU, Mbed TLS and zlib under their own licenses.")
	engine_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(engine_note)
	engine_button = UIFactory.make_button("Show Engine and Font Licenses")
	engine_button.name = "EngineLicensesButton"
	engine_button.pressed.connect(show_engine_licenses)
	body.add_child(engine_button)
	engine_text = RichTextLabel.new()
	engine_text.name = "EngineText"
	engine_text.bbcode_enabled = false
	engine_text.fit_content = true
	engine_text.scroll_active = false
	engine_text.selection_enabled = true
	engine_text.add_theme_color_override("default_color", UITheme.TEXT_PRIMARY)
	engine_text.visible = false
	body.add_child(engine_text)
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

## The engine notices are long; they are built the first time they are shown.
func show_engine_licenses() -> void:
	if engine_text.text.is_empty(): engine_text.text = third_party_notices()
	engine_text.visible = true
	engine_button.visible = false
	if done_button.is_inside_tree(): done_button.grab_focus.call_deferred()

## Godot's license, every engine component's copyright and license, the full
## text of each of those licenses, then the bundled font and godot-cpp notices.
static func third_party_notices() -> String:
	var lines := PackedStringArray()
	lines.append("GODOT ENGINE")
	lines.append(Engine.get_license_text().strip_edges())
	lines.append("")
	lines.append("THIRD-PARTY COMPONENTS IN THE GODOT ENGINE")
	for component: Dictionary in Engine.get_copyright_info():
		lines.append("")
		lines.append(String(component.get("name", "")))
		for part: Dictionary in component.get("parts", []):
			for holder: String in part.get("copyright", PackedStringArray()):
				lines.append("  © " + holder)
			lines.append("  License: " + String(part.get("license", "")))
	var licenses: Dictionary = Engine.get_license_info()
	var names := licenses.keys()
	names.sort()
	for license_name: String in names:
		lines.append("")
		lines.append("LICENSE: " + license_name)
		lines.append(String(licenses[license_name]).strip_edges())
	for font: Array in FONT_NOTICES:
		if FileAccess.file_exists(font[1]):
			lines.append("")
			lines.append("FONT: " + String(font[0]))
			lines.append(FileAccess.get_file_as_string(font[1]).strip_edges())
	if FileAccess.file_exists(GODOT_CPP_NOTICE):
		lines.append("")
		lines.append("GODOT-CPP (native extensions)")
		lines.append(FileAccess.get_file_as_string(GODOT_CPP_NOTICE).strip_edges())
	return "\n".join(lines)

func close() -> void:
	if not visible: return
	visible = false
	closed.emit()
