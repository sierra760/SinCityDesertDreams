# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Review a ready-to-send native city copy before opening system sharing.
class_name ShareCityDialog
extends Control

signal closed
var panel: PanelContainer
var share_button: Button
var reveal_button: Button
var done_button: Button
var details: Label
var feedback: Label
var copy: Dictionary = {}
var platform: CitySharePlatform

func _init() -> void:
	name = "ShareCityDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0,0,0,0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var chrome := UIFactory.make_window_chrome("Share City")
	panel = chrome.root
	panel.name = "Panel"
	panel.set_meta("preferred_size",Vector2(520,380))
	(chrome.close_button as Button).pressed.connect(close)
	details = UIFactory.make_label("")
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(chrome.body as VBoxContainer).add_child(details)
	feedback = UIFactory.make_label("",UITheme.FONT_SMALL,UITheme.TEXT_MUTED)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(chrome.body as VBoxContainer).add_child(feedback)
	var row: HBoxContainer = chrome.actions
	reveal_button = UIFactory.make_button("Show File", "Find the city file to attach to a message or email")
	reveal_button.pressed.connect(func() -> void:
		var error := CitySharePlatform.reveal_file(String(copy.path))
		if error != OK: feedback.text = "The file couldn't be shown. Your city copy is still ready to share.")
	row.add_child(reveal_button)
	done_button = UIFactory.make_button("Done")
	done_button.pressed.connect(close)
	row.add_child(done_button)
	share_button = UIFactory.make_primary_button("Share…", "Choose an app and recipient in system sharing")
	share_button.pressed.connect(_share)
	row.add_child(share_button)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -190
	panel.offset_bottom = 190
	add_child(panel)
	visible = false
	WindowDrag.enable(chrome.title_bar,panel)

func open(prepared: Dictionary) -> void:
	copy = prepared
	if platform == null: platform = CitySharePlatform.new()
	var mayor := String(copy.get("mayor",""))
	# The default "Mayor" credit adds nothing; show only a chosen mayor name.
	var mayor_line := "" if mayor.is_empty() or mayor == CityShare.DEFAULT_MAYOR else "\nMayor: %s" % mayor
	details.text = "%s%s\n\nA playable copy is ready. Your normal save stays where it is.\n\nRecipients can open the .sc2d file with Load City → Browse." % [copy.name,mayor_line]
	share_button.visible = platform.available()
	reveal_button.visible = not MobilePlatform.is_mobile()
	feedback.text = "Choose Messages, Mail, AirDrop or another available app." if platform.available() else ("In Files, open SC2D → shared-cities. Attach %s from folder %s to a message or email." % [String(copy.path).get_file(),String(copy.path).get_base_dir().get_file()] if MobilePlatform.is_mobile() else "Select Show File, then attach %s to a message or email." % String(copy.path).get_file())
	if OS.get_name() == "Android": feedback.text = "Sharing is not available in this Android build."
	visible = true
	UIFactory.contain_modal_focus(self,share_button if share_button.visible else done_button)

func _share() -> void:
	if platform.busy(): return
	var error := platform.share_file(String(copy.path),String(copy.name),String(copy.message))
	if error != OK:
		feedback.text = "Sharing couldn't open. Your city copy is still available."
		return
	share_button.disabled = true
	done_button.disabled = true

func _process(_delta: float) -> void:
	if not visible or platform == null or not share_button.disabled or platform.busy(): return
	share_button.disabled = false
	done_button.disabled = false
	feedback.text = "City shared." if platform.completion() == 1 else ("Sharing canceled. Your city copy is ready whenever you are." if platform.completion() == 0 else "Sharing did not finish. You can try again or use the city file.")
	share_button.grab_focus()

func close() -> void:
	if not visible or (platform != null and platform.busy()): return
	visible = false
	closed.emit()

func is_open() -> bool: return visible

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		accept_event()
