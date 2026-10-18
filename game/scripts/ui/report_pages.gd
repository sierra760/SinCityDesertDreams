# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Fixed report navigation over the chrome's single scrolling body.
class_name ReportPages
extends RefCounted

var header: VBoxContainer
var tabs: TabBar
var _pages: Array[VBoxContainer] = []
var _scroll: ScrollContainer
var _positions: Dictionary = {}
var _selected := 0
var _revision := 0

func _init(chrome: Dictionary, titles: Array[String]) -> void:
	_scroll = chrome.body_scroll
	var column := _scroll.get_parent()
	var navigation := VBoxContainer.new()
	navigation.name = "ReportNavigation"
	column.add_child(navigation)
	column.move_child(navigation, _scroll.get_index())
	header = VBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	navigation.add_child(header)
	tabs = TabBar.new()
	tabs.name = "ReportTabs"
	tabs.custom_minimum_size.y = 44
	tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	tabs.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	tabs.add_theme_constant_override("h_separation", 8)
	for state in ["tab_unselected", "tab_selected", "tab_hovered"]:
		var face := UITheme.button_stylebox(state == "tab_selected")
		face.content_margin_left = 8
		face.content_margin_right = 8
		tabs.add_theme_stylebox_override(state, face)
	tabs.add_theme_color_override("font_selected_color", UITheme.TITLE_TEXT)
	tabs.add_theme_color_override("font_unselected_color", UITheme.TEXT_PRIMARY)
	navigation.add_child(tabs)
	for title in titles:
		tabs.add_tab(title)
		var body := VBoxContainer.new()
		body.name = title.replace(" ", "") + "Page"
		body.add_theme_constant_override("separation", UITheme.VSEP)
		body.visible = _pages.is_empty()
		chrome.body.add_child(body)
		_pages.append(body)
	tabs.tab_changed.connect(_changed)

func page(index: int) -> VBoxContainer:
	return _pages[index]

func selected() -> String:
	return tabs.get_tab_title(_selected)

func select(title: String) -> void:
	for i in tabs.tab_count:
		if tabs.get_tab_title(i) == title:
			tabs.current_tab = i
			return

func _changed(index: int) -> void:
	_positions[_selected] = _scroll.scroll_vertical
	var focus := _scroll.get_viewport().gui_get_focus_owner()
	var move_focus := focus != null and _pages[_selected].is_ancestor_of(focus)
	_pages[_selected].hide()
	_selected = index
	_pages[index].show()
	# ScrollContainer caches its content extent during minimum-size queries;
	# a tab can change that extent without changing the scroll's own minimum.
	_scroll.get_minimum_size()
	_scroll.queue_sort()
	_revision += 1
	_scroll.scroll_vertical = int(_positions.get(index, 0))
	_restore.call_deferred(_revision, index)
	if move_focus: tabs.grab_focus()

func _restore(revision: int, index: int) -> void:
	# The explicit scroll sort above updates its range for the newly visible
	# page before this deferred restore; the outgoing range can be much shorter.
	if revision == _revision and is_instance_valid(_scroll) and _scroll.is_inside_tree():
		_scroll.scroll_vertical = int(_positions.get(index, 0))
