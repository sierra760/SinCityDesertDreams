# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Event queue shared by the systems during a day.
##
## Systems push news and notices here; the Simulation drains the queue after
## each day and turns the entries into signals. Keeping this indirect means no
## system needs a reference to the Simulation node.
class_name CityEvents
extends RefCounted

var news: Array[Dictionary] = []
var notices: Array[Dictionary] = []
var map_dirty := Rect2i()


## Queue a newsworthy happening. `kind` is a StringName the newspaper system
## understands; `args` carries whatever the story needs (a place, a number).
func report(kind: StringName, args: Dictionary = {}, priority: int = 1) -> void:
	news.append({"kind": kind, "args": args, "priority": priority})


## Queue something the player must see now (a modal notice or a toolbar alert).
func notify(kind: StringName, payload: Dictionary = {}) -> void:
	notices.append({"kind": kind, "payload": payload})


func mark_dirty(rect: Rect2i) -> void:
	if map_dirty.size == Vector2i.ZERO:
		map_dirty = rect
	else:
		map_dirty = map_dirty.merge(rect)


func mark_tile(x: int, y: int) -> void:
	mark_dirty(Rect2i(x, y, 1, 1))


func clear() -> void:
	news.clear()
	notices.clear()
	map_dirty = Rect2i()
