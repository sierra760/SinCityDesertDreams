# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
class_name PrivacyWindow
extends Control

signal closed
const POLICY_PATH := "res://legal/PRIVACY.txt"
const URL_SETTING := "sincity/privacy/policy_url"

var panel: PanelContainer
var policy_text: RichTextLabel
var policy_scroll: ScrollContainer
var online_button: Button
var status: Label
var done_button: Button
var url_opener: Callable = OS.shell_open

func _init() -> void:
	name = "PrivacyWindow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := UIFactory.make_window_chrome("Privacy")
	panel = chrome.root
	panel.name = "Panel"
	policy_scroll = chrome.body_scroll
	(chrome.close_button as Button).pressed.connect(close)
	policy_text = RichTextLabel.new()
	policy_text.bbcode_enabled = false
	policy_text.fit_content = true
	policy_text.scroll_active = false
	policy_text.selection_enabled = true
	policy_text.add_theme_color_override("default_color", UITheme.TEXT_PRIMARY)
	(chrome.body as VBoxContainer).add_child(policy_text)
	status = UIFactory.make_label("")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(chrome.body as VBoxContainer).add_child(status)
	online_button = UIFactory.make_button("Online Policy")
	online_button.pressed.connect(open_online_policy)
	(chrome.actions as HBoxContainer).add_child(online_button)
	done_button = UIFactory.make_button("Done")
	done_button.pressed.connect(close)
	(chrome.actions as HBoxContainer).add_child(done_button)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -250
	panel.offset_bottom = 250
	add_child(panel)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	WindowDrag.enable(chrome.title_bar, panel)
	refresh()
	visible = false

static func online_url() -> String:
	var url := str(ProjectSettings.get_setting(URL_SETTING, "")).strip_edges()
	return url if TerrainMapConfig._https_url(url) and not url.contains("{") else ""

func refresh() -> void:
	policy_text.text = FileAccess.get_file_as_string(POLICY_PATH)
	online_button.visible = not online_url().is_empty()
	status.text = ""

func open() -> void:
	refresh()
	policy_scroll.scroll_vertical = 0
	visible = true
	UIFactory.contain_modal_focus(self, done_button)

func open_online_policy() -> void:
	var url := online_url()
	if url.is_empty(): return
	if not url_opener.is_valid() or int(url_opener.call(url)) != OK:
		status.text = "The browser could not open the policy. You can read it here or visit %s." % url

func close() -> void:
	if not visible: return
	visible = false
	closed.emit()
