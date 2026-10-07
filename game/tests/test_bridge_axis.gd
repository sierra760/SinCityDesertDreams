# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const DIRECTIONS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]


func _crossing(tool: int, direction: Vector2i, length: int, style: StringName) -> void:
	var city := flat_city(20000)
	city.founded_year = 2000
	var builder := Builder.new(city, CityStats.new())
	var start := Vector2i(50, 50)
	var ew := direction.x != 0
	var water: Array[Vector2i] = []
	var seed := TileFlags.SALT_WATER | TileFlags.CONDUCTS_WATER | TileFlags.WATERED | TileFlags.RESERVED_B
	# Begin with the opposite orientation: NS placement must clear an old EW bit.
	if not ew:
		seed |= RotationMapper.AXIS_FLAG
	for k: int in range(1, length + 1):
		var cell := start + direction * k
		water.append(cell)
		city.terrain.put(cell.x, cell.y, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
		city.set_heights(cell.x, cell.y, 4, 4)
		city.flags.put(cell.x, cell.y, seed)
	var end := start + direction * (length + 1)
	var preview := builder.preview(tool, start, end, {"choice": style})
	check(preview.ok, "bridge preview %s %s: %s" % [style, direction, preview.reason])
	for cell: Vector2i in water:
		check_eq(city.flags.atv(cell), seed, "preview preserves existing flags")
	var applied := builder.apply(tool, start, end, {"choice": style})
	check(applied.ok and applied.applied, "bridge applied %s %s" % [style, direction])
	check_eq(applied.cost, preview.cost, "quotation and placement cost agree")
	check_eq(city.funds, 20000 - int(preview.cost), "axis metadata has no extra charge")
	for cell: Vector2i in water:
		var expected := seed & ~RotationMapper.AXIS_FLAG
		if ew:
			expected |= RotationMapper.AXIS_FLAG
		if Buildings.carries_power(city.building.atv(cell)):
			expected |= TileFlags.CONDUCTS_POWER
		check_eq(city.flags.atv(cell), expected, "axis is correct and unrelated flags survive at %s" % cell)
		check(city.is_water(cell.x, cell.y), "bridge leaves water intact")
	# Exercise the actual rendering profile consumer, not a duplicate axis decoder.
	var networks := CityNetworks3D.new()
	networks._prepare_bridge_decks(city)
	var ordered := water.duplicate()
	if direction.x < 0 or direction.y < 0:
		ordered.reverse()
	var step := Vector2i.RIGHT if ew else Vector2i.DOWN
	var entry := Vector2(0.0, 0.5) if ew else Vector2(0.5, 0.0)
	var exit := Vector2(1.0, 0.5) if ew else Vector2(0.5, 1.0)
	for i: int in ordered.size():
		var cell: Vector2i = ordered[i]
		var profile: Dictionary = networks._deck_profiles[cell]
		check_eq(profile.ew, ew, "profile follows placed direction")
		check_eq(profile.length, length, "whole crossing forms one continuous span")
		check_eq(profile.index, i, "span index follows canonical axis")
		if i > 0:
			check(networks._point(city, ordered[i - 1], exit, 0.65).is_equal_approx(
				networks._point(city, cell, entry, 0.65)), "adjacent bridge deck edges meet")
	var near: Vector2i = ordered[0] - step
	var far: Vector2i = ordered[-1] + step
	var height := 4*CityGeometry3D.HEIGHT+.12
	check_lt(absf(networks._point(city,ordered[0],entry,.65).y-height),.00001,"rigid bridge clears the water at its near end")
	check_lt(absf(networks._point(city,ordered[-1],exit,.65).y-height),.00001,"rigid bridge clears the water at its far end")
	if tool!=Tools.Kind.POWER_LINE:
		networks._physical_group = NetworkShapes.Family.RAIL if tool==Tools.Kind.RAIL else NetworkShapes.Family.ROAD
		check(networks._point(city,ordered[0],entry,.65).is_equal_approx(networks._point(city,near,exit,.04)),"near graded road meets the level bridge")
		check(networks._point(city,ordered[-1],exit,.65).is_equal_approx(networks._point(city,far,entry,.04)),"far graded road meets the level bridge")
	networks.free()


func test_causeway_axis_in_all_four_drag_directions() -> void:
	for direction: Vector2i in DIRECTIONS:
		_crossing(Tools.Kind.ROAD, direction, 3, &"causeway")


func test_suspension_axis_in_all_four_drag_directions() -> void:
	for direction: Vector2i in DIRECTIONS:
		_crossing(Tools.Kind.ROAD, direction, 8, &"suspension")


func test_rail_axis_in_all_four_drag_directions() -> void:
	for direction: Vector2i in DIRECTIONS:
		_crossing(Tools.Kind.RAIL, direction, 3, &"rail")


func test_power_axis_in_all_four_drag_directions() -> void:
	for direction: Vector2i in DIRECTIONS:
		_crossing(Tools.Kind.POWER_LINE, direction, 3, &"elevated")


func test_single_water_cell_uses_drag_axis() -> void:
	for direction: Vector2i in DIRECTIONS:
		_crossing(Tools.Kind.ROAD, direction, 1, &"causeway")
		_crossing(Tools.Kind.RAIL, direction, 1, &"rail")
		_crossing(Tools.Kind.POWER_LINE, direction, 1, &"elevated")
