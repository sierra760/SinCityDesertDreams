# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Synthetic lots/service flags for unit tests, not a full-host service proof.
class_name TourismFixture
extends RefCounted

static func context(city: City) -> SimContext:
	var ctx := SimContext.new()
	ctx.city = city
	ctx.stats = CityStats.new()
	ctx.rng = SimRng.new(7)
	ctx.clock = GameClock.new()
	ctx.clock.day = city.day
	ctx.events = CityEvents.new()
	return ctx

static func venue(city: City, key: StringName, anchor: Vector2i) -> Vector2i:
	return city.stamp_building(anchor.x, anchor.y, Buildings.id_of(key))

static func set_served(city: City, anchor: Vector2i, powered: bool, watered: bool) -> void:
	var size := Buildings.size(city.building_at(anchor.x, anchor.y))
	for dy in size.y:
		for dx in size.x:
			city.set_flag(anchor.x + dx, anchor.y + dy, TileFlags.POWERED, powered)
			city.set_flag(anchor.x + dx, anchor.y + dy, TileFlags.WATERED, watered)
