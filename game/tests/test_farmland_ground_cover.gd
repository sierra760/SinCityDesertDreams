# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Low-density farmland develops over trees and rubble, and Inspect names what
## is in the way when something else occupies the tile.
extends "res://tests/test_case.gd"

const BLOCK := Rect2i(14, 10, 6, 6)


func _fixture(cover: Array) -> Dictionary:
	var c := flat_city()
	var n := 0
	for y in range(BLOCK.position.y, BLOCK.end.y):
		for x in range(BLOCK.position.x, BLOCK.end.x):
			c.zone.put(x, y, Zones.make(Zones.AGR_LOW))
			if not cover.is_empty():
				c.building.put(x, y, cover[n % cover.size()])
			n += 1
	for x in range(BLOCK.position.x, BLOCK.end.x):
		c.building.put(x, BLOCK.position.y - 1, Buildings.ROAD_FIRST)
	c.stamp_building(BLOCK.end.x, BLOCK.position.y, Buildings.WATER_PUMP)
	c.stamp_building(BLOCK.end.x + 1, BLOCK.position.y, Buildings.COAL_PLANT)
	c.sea_level = 30
	var ctx := make_context(c)
	# Enough residents to want every farm this block can hold.
	ctx.stats.population = 8000
	var power := PowerSystem.new()
	var water := WaterSystem.new()
	var ag := AgricultureSystem.new()
	ctx.systems[&"power"] = power
	ctx.systems[&"water"] = water
	power.setup(ctx)
	ctx.systems[&"agriculture"] = ag
	water.setup(ctx)
	ag.setup(ctx)
	return {"city": c, "ctx": ctx, "ag": ag}


func _month(f: Dictionary) -> void:
	f.ag.monthly(f.ctx, 0)
	f.ag.monthly(f.ctx, 1)
	f.ctx.clock.day += GameClock.DAYS_PER_MONTH


func _farmed(f: Dictionary) -> int:
	var n := 0
	for r: Dictionary in f.ag.current_parcels():
		n += r.members.size()
	return n


func _check_develops(cover: Array, label: String) -> void:
	var f := _fixture(cover)
	var first := Vector2i(BLOCK.position)
	if not cover.is_empty():
		check_eq(f.ag.inspect_tile(first).blocked_reason, "Waiting for monthly preparation.", label + ": inspect before the first month")
	for _i in 6:
		_month(f)
	check_gt(_farmed(f), BLOCK.get_area() / 2, label + ": most of the block is farmed within six months")
	var active := 0
	for r: Dictionary in f.ag.current_parcels():
		if r.state == &"active": active += 1
		for i: int in r.members:
			check_eq(f.city.building.data[i], AgriculturalParcels._code(r), label + ": the parcel replaces what stood on its tiles")
	check_gt(active, 0, label + ": farms open")
	check_eq(f.ag.migration_error(), OK, label)
	f.ctx.systems.clear()


func test_bare_farmland_develops() -> void:
	_check_develops([], "bare")


func test_wooded_farmland_develops() -> void:
	_check_develops([Buildings.TREES_1, Buildings.TREES_7, Buildings.TREES_1 + 3], "trees")


func test_farmland_under_rubble_develops() -> void:
	_check_develops([Buildings.RUBBLE_1, Buildings.RUBBLE_4], "rubble")


func test_mixed_cover_develops() -> void:
	_check_develops([Buildings.NONE, Buildings.TREES_1, Buildings.RUBBLE_1 + 1], "mixed")


func test_inspect_names_an_occupied_tile() -> void:
	var f := _fixture([])
	var tile := Vector2i(BLOCK.position)
	f.city.building.put(tile.x, tile.y, Buildings.POWER_LINE_FIRST)
	check_eq(f.ag.inspect_tile(tile).blocked_reason, "Occupied land.")
	for _i in 4:
		_month(f)
	check_eq(f.city.building_at(tile.x, tile.y), Buildings.POWER_LINE_FIRST, "a power line is left standing")
	check_eq(f.ag.inspect_tile(tile).blocked_reason, "Occupied land.")
	f.ctx.systems.clear()
