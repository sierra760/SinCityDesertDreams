# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Base class for simulation systems.
##
## A system owns one concern (power, zones, budget...). It keeps its private
## state in its own fields and exposes results through CityStats or the city
## layers. Override only what you need.
class_name SimSystem
extends RefCounted

var key: StringName = &"system"


func setup(_ctx: SimContext) -> void:
	pass


## Called every simulated day, for every system, in registration order.
func daily(_ctx: SimContext) -> void:
	pass


## Called on this system's scheduled day(s) of the month. `phase` is 0 for the
## first scheduled day, 1 for the second, and so on.
func monthly(_ctx: SimContext, _phase: int = 0) -> void:
	pass


## Called on the last day of December, before the budget review.
func yearly(_ctx: SimContext) -> void:
	pass


## Called after the player builds or demolishes inside `rect`.
func networks_changed(_ctx: SimContext, _rect: Rect2i) -> void:
	pass


## Persistent private state. Must be JSON-safe (no Vector2i keys: use strings).
func save() -> Dictionary:
	return {}


func load(_data: Dictionary) -> void:
	pass


## Helpers for string keys in saved dictionaries.
static func tile_key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]


static func parse_tile_key(s: String) -> Vector2i:
	var parts := s.split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))
