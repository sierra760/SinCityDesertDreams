# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

var city: City
var editor: TerrainEditor


func before_each() -> void:
	city = flat_city(20000, 6)
	city.sea_level = 4
	editor = TerrainEditor.new(city)


func _no_cliffs(message: String) -> void:
	check_eq(editor.surface().cliff_count(), 0, message)
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var code := city.terrain.at(x, y)
			if code != Terrain.WATERFALL and Terrain.slope(code) > Terrain.PLATEAU:
				check(false, "bad slope code at %d,%d" % [x, y])
				return


func test_attach_builds_surface_from_flat_city() -> void:
	check(city.terrain_surface != null, "surface built on attach")
	check_eq(editor.surface().tile_base(10, 10), 6)
	check_eq(city.ground_height(10, 10), 6)


func test_raise_lifts_tile_and_slopes_neighbours() -> void:
	var r := editor.raise(20, 20)
	check(r["ok"], r["reason"])
	check_eq(r["cost"], TerrainEditor.RAISE_COST)
	check_eq(city.ground_height(20, 20), 7, "tile is one level up")
	check(city.is_flat(20, 20), "raised tile stays flat")
	check_eq(city.ground_height(19, 20), 6, "west neighbour keeps its base")
	check_eq(Terrain.slope(city.terrain.at(19, 20)), Terrain.SLOPE_E, "west neighbour slopes up to the east")
	check_eq(Terrain.slope(city.terrain.at(21, 20)), Terrain.SLOPE_W)
	check_eq(Terrain.slope(city.terrain.at(20, 19)), Terrain.SLOPE_S)
	check_eq(Terrain.slope(city.terrain.at(20, 21)), Terrain.SLOPE_N)
	check_eq(Terrain.slope(city.terrain.at(19, 19)), Terrain.CORNER_SE, "diagonal neighbour gets one raised corner")
	var rect: Rect2i = r["rect"]
	check(rect.has_point(Vector2i(19, 19)) and rect.has_point(Vector2i(21, 21)), "dirty rect covers the ring")
	_no_cliffs("after raise")
	# Raising again makes a two-step mesa with a wider skirt.
	r = editor.raise(20, 20)
	check(r["ok"])
	check_eq(city.ground_height(20, 20), 8)
	check_eq(city.ground_height(19, 20), 7)
	check_eq(city.ground_height(18, 20), 6)
	_no_cliffs("after second raise")


func test_lower_digs_and_refuses_at_floor() -> void:
	var r := editor.lower(30, 30)
	check(r["ok"], r["reason"])
	check_eq(r["cost"], TerrainEditor.LOWER_COST)
	check_eq(city.ground_height(30, 30), 5)
	check_eq(Terrain.slope(city.terrain.at(29, 30)), Terrain.SLOPE_W, "west neighbour slopes down toward the pit")
	_no_cliffs("after lower")
	for _i in 10:
		editor.lower(30, 30)
	check_eq(city.ground_height(30, 30), 0)
	var last := editor.lower(30, 30)
	check(not last["ok"], "cannot dig below zero")
	check_eq(last["cost"], 0)
	_no_cliffs("after digging to the floor")


func test_level_sets_exact_height() -> void:
	var r := editor.level(40, 40, 10)
	check(r["ok"], r["reason"])
	check_eq(city.ground_height(40, 40), 10)
	check(city.is_flat(40, 40))
	check_eq(city.ground_height(36, 40), 6, "skirt spreads four tiles")
	_no_cliffs("after level")
	check(not editor.level(40, 40, 10)["ok"], "levelling to the same height does nothing")


func test_ground_tools_refuse_built_tiles() -> void:
	city.stamp_building(50, 50, Buildings.POLICE_STATION)
	var r := editor.raise(51, 51)
	check(not r["ok"], "cannot raise under a building")
	check_eq(r["cost"], 0)
	check_eq(city.ground_height(51, 51), 6)
	r = editor.raise(53, 51)
	check(not r["ok"], "the ripple would tilt the station")
	check_eq(city.ground_height(53, 51), 6, "refused edit leaves the map untouched")
	check_eq(editor.surface().vertex(53, 51), 6)
	r = editor.raise(56, 51)
	check(r["ok"], "far enough away the ripple never reaches the station")
	check(editor.surface().is_tile_flat(52, 52), "station tile still flat")
	# Trees are cleared, not an obstacle.
	city.building.put(70, 70, Buildings.TREES_1 + 2)
	r = editor.raise(70, 70)
	check(r["ok"])
	check_eq(city.building.at(70, 70), Buildings.NONE, "trees cleared by the raise")


func test_water_placement_and_removal() -> void:
	var r := editor.place_water(60, 60)
	check(r["ok"], r["reason"])
	check_eq(r["cost"], TerrainEditor.WATER_COST)
	check(city.is_water(60, 60))
	check_eq(city.terrain.at(60, 60), Terrain.make(Terrain.FLAT, Terrain.SURFACE), "a pond on flat ground")
	check_eq(city.water_height(60, 60), 7)
	check(not city.is_salt_water(60, 60), "inland water is fresh")
	check(not editor.place_water(60, 60)["ok"], "no double water")
	r = editor.remove_water(60, 60)
	check(r["ok"])
	check(not city.is_water(60, 60))
	check_eq(city.water_height(60, 60), 0)
	check(not editor.remove_water(60, 60)["ok"], "nothing to drain")
	# Water beside a raised tile becomes a shore.
	editor.raise(80, 80)
	r = editor.place_water(81, 80)
	check(r["ok"])
	check_eq(Terrain.water_kind(city.terrain.at(81, 80)), Terrain.SHORE, "sloped tile with water is a shore")
	# Salt spreads from salt neighbours.
	editor.surface().set_water(90, 90, 7, true)
	editor.surface().project(city, Rect2i(90, 90, 1, 1))
	editor.place_water(91, 90)
	check(city.is_salt_water(91, 90), "water next to brackish water is brackish")


func test_raise_drains_water_and_lower_floods() -> void:
	editor.place_water(100, 100)
	editor.raise(100, 100)
	check(not city.is_water(100, 100), "raising the bed drains the pond")
	editor.place_water(100, 100)
	var r := editor.lower(101, 100)
	check(r["ok"])
	check(city.is_water(101, 100), "a pit beside water fills")
	check_eq(city.water_height(101, 100), city.water_height(100, 100))


func test_trees() -> void:
	var r := editor.plant_trees(5, 5, 4)
	check(r["ok"])
	check_eq(r["cost"], TerrainEditor.TREE_COST)
	check_eq(city.building.at(5, 5), Buildings.TREES_1 + 3)
	check(not editor.plant_trees(5, 5, 4)["ok"], "same density again is a no-op")
	check(editor.plant_trees(5, 5, 7)["ok"], "denser planting replaces")
	check_eq(city.building.at(5, 5), Buildings.TREES_7)
	editor.place_water(6, 6)
	check(not editor.plant_trees(6, 6, 1)["ok"], "no trees in water")
	city.stamp_building(8, 8, Buildings.WATER_PUMP)
	check(not editor.plant_trees(8, 8, 1)["ok"], "no trees on buildings")


func test_tree_tool_thickens_and_area_tools_fill_the_rectangle() -> void:
	var first := editor.apply_tool(Tools.Kind.PLANT_TREE, Vector2i(20, 20))
	check(first["ok"], first["reason"])
	check_eq(city.building.at(20, 20), Buildings.TREES_1, "one tree on open ground")
	for _i in 6:
		check(editor.apply_tool(Tools.Kind.PLANT_TREE, Vector2i(20, 20))["ok"])
	check_eq(city.building.at(20, 20), Buildings.TREES_7, "each click adds density")
	check(not editor.preview_tool(Tools.Kind.PLANT_TREE, Vector2i(20, 20))["ok"], "full density previews as refused")
	check(not editor.apply_tool(Tools.Kind.PLANT_TREE, Vector2i(20, 20))["ok"])
	var forest := editor.apply_tool(Tools.Kind.FOREST, Vector2i(33, 32), Vector2i(30, 30))
	check(forest["ok"], forest["reason"])
	check_eq((forest["tiles"] as Array).size(), 12, "a 4 by 3 area")
	check_eq((editor.preview_tool(Tools.Kind.FOREST, Vector2i(30, 30), Vector2i(33, 32))["tiles"] as Array).size(), 12)
	editor.raise(42, 42)
	editor.raise(44, 41)
	var level := editor.apply_tool(Tools.Kind.LEVEL_LAND, Vector2i(40, 40), Vector2i(46, 44))
	check(level["ok"], level["reason"])
	for y in range(40, 45):
		for x in range(40, 47):
			check(editor.surface().is_tile_flat(x, y) and editor.surface().tile_base(x, y) == 6,
				"area tile %d,%d level with the start" % [x, y])
	_no_cliffs("levelling an area leaves no cliffs")


func test_sea_level_floods_and_recedes() -> void:
	# A basin two levels deep with the sea at 4 stays dry until the sea rises.
	editor.level(10, 60, 4)
	editor.level(11, 60, 4)
	editor.lower(10, 60)
	editor.lower(11, 60)
	check_eq(city.ground_height(10, 60), 3)
	editor.place_water(10, 60)
	check_eq(city.water_height(10, 60), 4)
	check(not city.is_water(11, 60))
	var r := editor.raise_sea_level()
	check(r["ok"], r["reason"])
	check_eq(r["cost"], TerrainEditor.SEA_LEVEL_COST)
	check_eq(city.sea_level, 5)
	check_eq(city.water_height(10, 60), 5, "standing water rises")
	check(city.is_water(11, 60), "low ground next to water floods")
	check(city.is_water(12, 60) and city.is_water(13, 60), "the sloped bank below the new level floods too")
	check(not city.is_water(14, 60), "ground at the new level stays dry")
	r = editor.lower_sea_level()
	check(r["ok"])
	check_eq(city.sea_level, 4)
	check_eq(city.water_height(10, 60), 4)
	check(city.is_water(11, 60), "water at 4 still stands over ground at 3")
	editor.lower_sea_level()
	check_eq(city.sea_level, 3)
	check(not city.is_water(11, 60), "ground at the sea level dries out")
	_no_cliffs("after sea level changes")
	var none := City.new()
	none.sea_level = -1
	check(not TerrainEditor.new(none).raise_sea_level()["ok"], "no sea level, no tool")


func test_edits_keep_generated_map_consistent() -> void:
	var generated := TerrainGenerator.new().generate({"coast": "west", "hills": 70}, SimRng.new(21))
	var ed := TerrainEditor.new(generated)
	var applied := 0
	for i in 40:
		var x := 20 + (i * 7) % 90
		var y := 20 + (i * 11) % 90
		var r: Dictionary = ed.raise(x, y) if i % 3 != 0 else ed.lower(x, y)
		if r["ok"]:
			applied += 1
	check_gt(applied, 20, "most edits on open ground succeed")
	check_eq(ed.surface().cliff_count(), 0, "no cliffs after a burst of edits")
	for y in City.HEIGHT:
		for x in City.WIDTH:
			check_eq(generated.ground_height(x, y), ed.surface().tile_base(x, y), "projection matches lattice at %d,%d" % [x, y])
			if Terrain.is_water(generated.terrain.at(x, y)):
				check_gt(generated.water_height(x, y), generated.ground_height(x, y), "water stands above ground at %d,%d" % [x, y])
