# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func test_programmatic_last_save_selection_is_visible_in_long_list() -> void:
	root.size = Vector2i(640, 400)
	var dialog := LoadDialog.new()
	root.add_child(dialog)
	var saves: Array[Dictionary] = []
	for index in 30:
		saves.append({"name": "City %d" % index, "path": "user://saves/city-%d.sc2d" % index,
			"year": 1950, "population": 1234, "date_text": "2026-10-04 12:00 UTC"})
	saves[-1]["automatic_backup"] = true
	dialog.open(saves)
	# Select immediately as well as after a subsequent layout change.
	dialog.select(29)
	for frame in 5: await process_frame
	check_eq(dialog.selected_path(), "user://saves/city-29.sc2d")
	check(dialog.item_list.get_v_scroll_bar().value > 0, "last selected row scrolls into view")
	var last_visible := dialog.item_list.get_item_at_position(Vector2(30, dialog.item_list.size.y - 15), true)
	check_eq(last_visible, 29, "selected last save is reachable in the visible list")
	dialog.select(0)
	for frame in 4: await process_frame
	check_eq(dialog.item_list.get_v_scroll_bar().value, 0.0, "first selected row returns into view")
	dialog.free()
	for frame in 3: await process_frame

func test_pending_selection_reveal_does_not_outlive_dialog() -> void:
	var dialog := LoadDialog.new()
	root.add_child(dialog)
	dialog.open([{"name":"City","path":"user://saves/city.sc2d"}] as Array[Dictionary])
	dialog.select(0)
	dialog.free()
	for frame in 3: await process_frame
	check(not is_instance_valid(dialog))
