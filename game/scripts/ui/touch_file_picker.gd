# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Touch-friendly styling for Godot's built-in file dialog, used where no
## native picker exists. File access and selection stay with FileDialog and
## MobilePlatform, including the iOS Documents sandbox.
class_name TouchFilePicker
extends RefCounted

const TARGET := Vector2(44,44)

static func polish(picker: FileDialog) -> void:
	if picker == null or picker.use_native_dialog:
		return
	picker.theme = UITheme.control_theme()
	picker.add_theme_stylebox_override("panel",UITheme.window_stylebox())
	_polish_controls(picker)
	if picker.get_node_or_null("TouchPickerReflow") == null:
		var reflow := PickerReflow.new()
		reflow.name = "TouchPickerReflow"
		picker.add_child(reflow)

static func _polish_controls(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		button.custom_minimum_size = button.custom_minimum_size.max(TARGET)
	elif node is LineEdit:
		var field := node as LineEdit
		field.custom_minimum_size.y = maxf(44.0,field.custom_minimum_size.y)
	elif node is ItemList:
		var list := node as ItemList
		# Selection geometry includes this padding, unlike a surrounding
		# minimum-size box, so every file/folder receives a full touch row.
		list.add_theme_constant_override("v_separation",28)
	for child: Node in node.get_children(true):
		_polish_controls(child)

## Favorites/recents are optional shortcuts. Compact browsing gives their
## width to the file list; history, parent navigation and editable paths remain.
class PickerReflow:
	extends Node
	var _picker: FileDialog
	var _favorites := true
	var _recents := true
	var _host_viewport: Viewport
	func _ready() -> void:
		_picker = get_parent() as FileDialog
		_favorites = _picker.favorites_enabled
		_recents = _picker.recent_list_enabled
		_picker.about_to_popup.connect(_prepare)
		var host := _picker.get_parent()
		if host != null:
			_host_viewport = host.get_viewport()
			_host_viewport.size_changed.connect(_prepare)
		_prepare()
	func _exit_tree() -> void:
		if is_instance_valid(_host_viewport) and _host_viewport.size_changed.is_connected(_prepare):
			_host_viewport.size_changed.disconnect(_prepare)
	func _prepare() -> void:
		var host := _picker.get_parent()
		if host == null:
			return
		var available := host.get_viewport().get_visible_rect().size
		var compact := available.x < 640.0
		_picker.favorites_enabled = _favorites and not compact
		_picker.recent_list_enabled = _recents and not compact
