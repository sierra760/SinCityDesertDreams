# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func test_toolbar_can_be_destroyed_while_focus_reveal_is_pending() -> void:
	var toolbar := Toolbar.new()
	root.add_child(toolbar)
	for frame in 5: await process_frame
	# Exercise the actual resize signal and its deferred scheduling.
	(toolbar.get_node("Shell/Scroll") as ScrollContainer).resized.emit()
	for frame in 3:
		await process_frame
		if toolbar._reveal_pending: break
	check(toolbar._reveal_pending, "deletion occurs with a scheduled focus adjustment")
	toolbar.free()
	for frame in 4: await process_frame
	check(not is_instance_valid(toolbar), "focus adjustment must not keep the toolbar alive")

func test_live_toolbar_reveals_last_focused_tool_after_resize() -> void:
	root.size = Vector2i(640, 400)
	var toolbar := Toolbar.new()
	root.add_child(toolbar)
	toolbar.size = Vector2(196, 350)
	for frame in 5: await process_frame
	var scroll := toolbar.get_node("Shell/Scroll") as ScrollContainer
	var last := toolbar.buttons[Tools.Kind.PLACE_WATER] as Button
	last.grab_focus()
	for frame in 3: await process_frame
	scroll.scroll_vertical = 0
	scroll.resized.emit()
	for frame in 5: await process_frame
	check(scroll.scroll_vertical > 0, "resize restores the focused tool into view")
	check(scroll.get_global_rect().intersects(last.get_global_rect()))
	toolbar.free()
	await process_frame
