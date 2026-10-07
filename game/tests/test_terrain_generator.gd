# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## A quick default map for tests that just need a generated city.
func _generate(seed_value: int, params: Dictionary = {}) -> City:
	return TerrainGenerator.new().generate(params, SimRng.new(seed_value))


func test_same_seed_same_map() -> void:
	var a := _generate(7, {"coast": "west", "river": true, "hills": 60, "water": 50, "trees": 50})
	var b := _generate(7, {"coast": "west", "river": true, "hills": 60, "water": 50, "trees": 50})
	check_eq(a.terrain.data, b.terrain.data, "terrain codes")
	check_eq(a.altitude.data, b.altitude.data, "altitude")
	check_eq(a.building.data, b.building.data, "trees")
	check_eq(a.flags.data, b.flags.data, "flags")
	var c := _generate(8, {"coast": "west", "river": true, "hills": 60, "water": 50, "trees": 50})
	check_ne(c.terrain.data, a.terrain.data, "a different seed gives a different map")


func test_surface_is_bound_and_consistent() -> void:
	var c := _generate(3, {"hills": 80, "water": 60, "coast": "south"})
	check(c.terrain_surface != null, "surface bound to city")
	var s: TerrainSurface = c.terrain_surface
	check_eq(s.cliff_count(), 0, "no cliffs after generation")
	var saddles := 0
	var unrepresentable := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var code := c.terrain.at(x, y)
			var shape := Terrain.slope(code)
			if shape > Terrain.PLATEAU and code != Terrain.WATERFALL:
				unrepresentable += 1
			var cs := s.corners(x, y)
			var base := mini(mini(cs[0], cs[1]), mini(cs[2], cs[3]))
			var mask := 0
			for i in 4:
				if cs[i] > base:
					mask |= 1 << i
			if Terrain.shape_from_corners(mask) < 0:
				saddles += 1
			check_eq(c.ground_height(x, y), base, "ground height is the lowest corner at %d,%d" % [x, y])
	check_eq(saddles, 0, "no saddle tiles")
	check_eq(unrepresentable, 0, "every slope code is a known shape")


func test_river_has_a_waterfall_and_streams() -> void:
	for seed_value in [1, 2, 3]:
		var c := _generate(seed_value, {"river": true, "coast": "none", "hills": 30})
		var waterfalls := 0
		var streams := 0
		for y in City.HEIGHT:
			for x in City.WIDTH:
				var code := c.terrain.at(x, y)
				if code == Terrain.WATERFALL:
					waterfalls += 1
				elif Terrain.water_kind(code) == Terrain.STREAM:
					streams += 1
		check_gt(waterfalls, 0, "seed %d has a waterfall" % seed_value)
		check_gt(streams, 10, "seed %d has a river" % seed_value)
	var dry := _generate(4, {"river": false, "coast": "none", "water": 0})
	check_eq(dry.terrain.count(Terrain.WATERFALL), 0, "no waterfall without a river")


func test_coast_is_salt_and_lakes_are_fresh() -> void:
	var c := _generate(11, {"coast": "east", "water": 80, "river": false, "hills": 20})
	check_eq(c.sea_level, TerrainGenerator.DEFAULT_SEA_LEVEL, "sea level recorded")
	var salt := 0
	var fresh := 0
	var edge_water := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if not c.is_water(x, y):
				continue
			if c.is_salt_water(x, y):
				salt += 1
			else:
				fresh += 1
			if x == City.WIDTH - 1:
				edge_water += 1
			check_eq(c.water_height(x, y), c.sea_level, "standing water sits at sea level")
	check_gt(salt, 200, "a sea along the east edge")
	check_gt(edge_water, 100, "the east edge is sea")
	check_gt(fresh, 20, "fresh lakes inland")
	var none := _generate(11, {"coast": "none", "water": 0, "river": false})
	check_eq(none.flags.count(TileFlags.SALT_WATER), 0, "no salt water without a coast")


func test_trees_follow_density_and_water() -> void:
	var c := _generate(5, {"trees": 70, "water": 60, "coast": "north"})
	var counts := c.building_census()
	var total := 0
	for id in range(Buildings.TREES_1, Buildings.TREES_7 + 1):
		total += counts[id]
	check_gt(total, 300, "plenty of trees at 70")
	check_gt(counts[Buildings.TREES_1 + 4] + counts[Buildings.TREES_1 + 5] + counts[Buildings.TREES_7], 0, "dense groves exist")
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if Buildings.is_tree(c.building.at(x, y)):
				check(not c.is_water(x, y), "trees never stand in water")
	var bare := _generate(5, {"trees": 0})
	var bare_counts := bare.building_census()
	var bare_total := 0
	for id in range(Buildings.TREES_1, Buildings.TREES_7 + 1):
		bare_total += bare_counts[id]
	check_eq(bare_total, 0, "no trees at 0")


func test_generation_is_fast() -> void:
	var started := Time.get_ticks_msec()
	_generate(9, {"hills": 100, "water": 100, "trees": 100, "coast": "west", "river": true})
	var elapsed := Time.get_ticks_msec() - started
	check_lt(elapsed, 1000, "generation takes under a second (%d ms)" % elapsed)


func test_difficulty_sets_funds() -> void:
	var hard := _generate(1, {"difficulty": City.Difficulty.HARD, "name": "Dust Bowl"})
	check_eq(hard.funds, City.STARTING_FUNDS[City.Difficulty.HARD])
	check_eq(hard.name, "Dust Bowl")
	check_eq(hard.difficulty, City.Difficulty.HARD)
