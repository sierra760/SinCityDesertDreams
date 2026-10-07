# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Presentation state only: construction still owns pricing and admission.
class_name CursorPreviewState
extends RefCounted
signal footprint_changed
const CAPTION_OK := Color(0.85, 1.0, 0.85)
const CAPTION_BLOCKED := Color(1.0, 0.8, 0.8)
var redraw_count := 0
var tiles: Array[Vector2i] = []
var ok := true
var caption := ""

func show_footprint(footprint: Array, allowed: bool, text: String = "") -> void:
	tiles.clear()
	for tile: Variant in footprint:
		if tile is Vector2i:
			tiles.append(tile)
		elif tile is Vector2 and tile.is_finite():
			tiles.append(Vector2i(roundi(tile.x), roundi(tile.y)))
	ok = allowed
	caption = text
	redraw_count += 1
	footprint_changed.emit()

func clear() -> void:
	tiles.clear()
	caption = ""
	redraw_count += 1
	footprint_changed.emit()

func is_showing() -> bool:
	return not tiles.is_empty()
