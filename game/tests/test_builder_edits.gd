# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## Edits that must leave the city exactly as the player was told: a tool that
## changes nothing charges nothing, demolition takes only what was pointed at
## and what remains is reshaped, and a preview always matches the charge.

const NS := preload("res://scripts/core/network_shapes.gd")
const DIR := "user://test_builder_edits"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(DIR)


func _builder(funds: int = 1000000) -> Builder:
	var c := flat_city(funds)
	c.founded_year = 2000
	return Builder.new(c, CityStats.new())


func _water_rect(c: City, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			c.terrain.put(x, y, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
			c.set_heights(x, y, c.ground_height(x, y), c.ground_height(x, y))


## Raise a rectangle of per-tile ground and give every tile its slope shape.
func _hill(c: City, x0: int, y0: int, x1: int, y1: int, height: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			c.set_heights(x, y, height)
	for y in City.HEIGHT:
		for x in City.WIDTH:
			Builder.refresh_shape(c, x, y)


## Preview, then apply, and check the two agree and the funds follow.
func _charged(b: Builder, tool: int, from: Vector2i, to: Vector2i = Vector2i(-1, -1), options: Dictionary = {}) -> Dictionary:
	var quote := b.preview(tool, from, to, options)
	var funds := b.city.funds
	var r := b.apply(tool, from, to, options)
	check_eq(bool(r["ok"]), bool(quote["ok"]), "preview and apply agree on %s" % Tools.display_name(tool))
	check_eq(int(r["cost"]), int(quote["cost"]), "preview price is the charge")
	check_eq(funds - b.city.funds, int(r["cost"]) if bool(r["applied"]) else 0, "funds follow the charge")
	return r


## Save and load the city and check every edited layer comes back.
func _check_round_trip(c: City, label: String) -> void:
	var path := "%s/%s.sc2d" % [DIR, label]
	check_eq(SaveFormat.save(path, c), OK)
	var loaded := SaveFormat.load(path)
	check(bool(loaded["ok"]), String(loaded["error"]))
	if not bool(loaded["ok"]):
		return
	var back: City = loaded["city"]
	check(back.building.data == c.building.data, "%s: buildings survive a save" % label)
	check(back.terrain.data == c.terrain.data, "%s: terrain survives a save" % label)
	check(back.altitude.data == c.altitude.data, "%s: heights survive a save" % label)
	check(back.zone.data == c.zone.data, "%s: zones survive a save" % label)
	check(back.underground.data == c.underground.data, "%s: underground survives a save" % label)


# ── Level Land ───────────────────────────────────────────────────────────

func test_level_that_changes_nothing_is_free() -> void:
	var b := _builder()
	var c := b.city
	check(bool(b.apply(Tools.Kind.RAISE_LAND, Vector2i(60, 60))["applied"]))
	check_eq(c.ground_height(59, 60), 4)
	check(not c.is_flat(59, 60), "the tile beside the hill slopes up to it")
	var before_terrain := c.terrain.data.duplicate()
	var before_altitude := c.altitude.data.duplicate()
	# The slope is already at the target height and follows the hill: nothing
	# can change, so nothing is charged, however often it is tried.
	for _try in 3:
		var r := _charged(b, Tools.Kind.LEVEL_LAND, Vector2i(55, 60), Vector2i(59, 60))
		check(not bool(r["ok"]), "a level that changes nothing is refused")
		check(not bool(r["applied"]))
		check_eq(int(r["cost"]), 0)
		check_eq(r["reason"], Builder.REASON_SLOPE_STAYS)
	check(c.terrain.data == before_terrain)
	check(c.altitude.data == before_altitude)
	check_eq(b.preview(Tools.Kind.LEVEL_LAND, Vector2i(50, 50), Vector2i(52, 52))["reason"], "the land is already level")


func test_level_charges_only_the_tiles_it_changes() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.RAISE_LAND, Vector2i(60, 60))
	# The drag passes over the slope, which cannot change on its own, and then
	# the raised tile, which comes down and takes its slopes with it.
	var r := _charged(b, Tools.Kind.LEVEL_LAND, Vector2i(55, 60), Vector2i(60, 60))
	check(bool(r["applied"]), r["reason"])
	check_eq(r["tiles"], [Vector2i(60, 60)] as Array[Vector2i])
	check_eq(int(r["cost"]), Builder.TERRAIN_STEP_COST)
	for y in range(58, 63):
		for x in range(55, 63):
			check(c.is_flat(x, y) and c.ground_height(x, y) == 4, "level at %d,%d" % [x, y])
	_check_round_trip(c, "level")


# ── Bulldozing buildings ─────────────────────────────────────────────────

func test_a_lone_piece_of_a_building_is_bulldozed_alone() -> void:
	var b := _builder()
	var c := b.city
	# One stray tile of a 3×3 building with a road, a house and a park in the
	# tiles a whole footprint would cover.
	c.building.put(20, 20, Buildings.POLICE_STATION)
	b.apply(Tools.Kind.ROAD, Vector2i(21, 20), Vector2i(22, 20))
	c.stamp_building(20, 21, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	c.building.put(21, 21, Buildings.SMALL_PARK)
	var around := {}
	for y in range(19, 24):
		for x in range(19, 24):
			around[Vector2i(x, y)] = c.building_at(x, y)
	var r := _charged(b, Tools.Kind.BULLDOZE, Vector2i(20, 20))
	check(bool(r["applied"]), r["reason"])
	check_eq(r["tiles"], [Vector2i(20, 20)] as Array[Vector2i])
	check_eq(int(r["cost"]), 1)
	check(Buildings.is_rubble(c.building_at(20, 20)))
	for p: Vector2i in around:
		if p != Vector2i(20, 20):
			check_eq(c.building_at(p.x, p.y), around[p], "neighbour at %s untouched" % p)


func test_two_pieces_of_one_building_go_together_and_a_whole_one_goes_whole() -> void:
	var b := _builder()
	var c := b.city
	# An L of three connected tiles left from a 3×3 building.
	for p: Vector2i in [Vector2i(30, 30), Vector2i(31, 30), Vector2i(30, 31)]:
		c.building.put(p.x, p.y, Buildings.POLICE_STATION)
	b.apply(Tools.Kind.ROAD, Vector2i(31, 31), Vector2i(32, 31))
	var r := _charged(b, Tools.Kind.BULLDOZE, Vector2i(31, 30))
	check_eq(int(r["cost"]), 3)
	check_eq(r["tiles"].size(), 3)
	check(NS.in_road_family(c.building_at(31, 31)), "the road inside the footprint stays")
	check(NS.in_road_family(c.building_at(32, 31)))
	# A complete building still comes down whole, wherever it is clicked.
	check(bool(b.apply(Tools.Kind.POLICE, Vector2i(40, 40))["applied"]))
	var whole := _charged(b, Tools.Kind.BULLDOZE, Vector2i(42, 42))
	check_eq(int(whole["cost"]), 9)
	for dy in 3:
		for dx in 3:
			check(Buildings.is_rubble(c.building_at(40 + dx, 40 + dy)))
	check(not c.facilities.has(Vector2i(40, 40)))


func test_stray_pieces_in_an_included_city_spare_their_neighbours() -> void:
	var loaded := SaveFormat.load("res://assets/cities/Valle del Mar.sc2d")
	check(bool(loaded["ok"]), String(loaded["error"]))
	var c: City = loaded["city"]
	c.funds = 100000
	var b := Builder.new(c, CityStats.new())
	for at: Vector2i in [Vector2i(68, 1), Vector2i(79, 1), Vector2i(83, 1), Vector2i(109, 1)]:
		var before := c.building.data.duplicate()
		var r := _charged(b, Tools.Kind.BULLDOZE, at)
		check(bool(r["applied"]), r["reason"])
		check_eq(int(r["cost"]), 1, "one tile at %s" % at)
		var changed := 0
		for i in before.size():
			if before[i] != c.building.data[i]:
				changed += 1
		check_eq(changed, 1, "only %s changes" % at)


func test_clearing_a_footprint_reports_only_what_it_cleared() -> void:
	var c := flat_city()
	c.building.put(20, 20, Buildings.POLICE_STATION)
	c.building.put(21, 20, Buildings.ROAD_FIRST)
	check_eq(c.footprint_tiles(20, 20), [Vector2i(20, 20)] as Array[Vector2i])
	check_eq(c.clear_footprint(20, 20), Rect2i(20, 20, 1, 1))
	check_eq(c.building_at(20, 20), Buildings.NONE)
	check_eq(c.building_at(21, 20), Buildings.ROAD_FIRST)
	c.stamp_building(30, 30, Buildings.POLICE_STATION, Zones.NONE)
	check_eq(c.footprint_tiles(31, 32).size(), 9)
	check_eq(c.clear_footprint(32, 31), Rect2i(30, 30, 3, 3))


# ── Highways ─────────────────────────────────────────────────────────────

func test_demolishing_a_highway_arm_reshapes_the_junction() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.HIGHWAY, Vector2i(10, 10), Vector2i(20, 10))
	b.apply(Tools.Kind.HIGHWAY, Vector2i(14, 10), Vector2i(14, 20))
	check_eq(c.building_at(14, 10), NS.HIGHWAY_JUNCTION)
	var r := _charged(b, Tools.Kind.BULLDOZE, Vector2i(14, 12), Vector2i(15, 13))
	check(bool(r["applied"]), r["reason"])
	check_eq(int(r["cost"]), 4)
	for p: Vector2i in [Vector2i(14, 10), Vector2i(15, 10), Vector2i(14, 11), Vector2i(15, 11)]:
		check_eq(c.building_at(p.x, p.y), NS.HIGHWAY_EW, "the junction is a straight again at %s" % p)
	check_eq(c.building_at(14, 14), NS.HIGHWAY_NS, "the cut-off arm keeps its direction")
	check(r["rect"].has_point(Vector2i(14, 10)), "the reshaped block is redrawn")
	_check_round_trip(c, "junction")


func test_demolishing_a_highway_leg_straightens_the_corner() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.HIGHWAY, Vector2i(10, 10), Vector2i(20, 20))
	check_eq(c.building_at(20, 10), NS.HIGHWAY_CORNER_SW)
	_charged(b, Tools.Kind.BULLDOZE, Vector2i(20, 12), Vector2i(21, 21))
	check_eq(c.building_at(20, 10), NS.HIGHWAY_EW)
	check_eq(c.building_at(21, 11), NS.HIGHWAY_EW)
	# A four-way interchange that loses one arm is still an interchange.
	var d := _builder()
	d.apply(Tools.Kind.HIGHWAY, Vector2i(30, 40), Vector2i(50, 40))
	d.apply(Tools.Kind.HIGHWAY, Vector2i(40, 30), Vector2i(40, 50))
	check_eq(d.city.building_at(40, 40), NS.HIGHWAY_JUNCTION)
	_charged(d, Tools.Kind.BULLDOZE, Vector2i(40, 30), Vector2i(41, 39))
	check_eq(d.city.building_at(40, 40), NS.HIGHWAY_JUNCTION)
	_charged(d, Tools.Kind.BULLDOZE, Vector2i(40, 42), Vector2i(41, 51))
	check_eq(d.city.building_at(40, 40), NS.HIGHWAY_EW)
	# A north-south block left alone stays north-south.
	var e := _builder()
	e.apply(Tools.Kind.HIGHWAY, Vector2i(60, 60), Vector2i(60, 64))
	_charged(e, Tools.Kind.BULLDOZE, Vector2i(60, 60), Vector2i(61, 61))
	_charged(e, Tools.Kind.BULLDOZE, Vector2i(60, 64), Vector2i(61, 65))
	check_eq(e.city.building_at(60, 62), NS.HIGHWAY_NS)


func test_demolishing_a_hillside_highway_restores_the_ground() -> void:
	var b := _builder()
	var c := b.city
	_hill(c, 61, 40, 90, 70, 5)
	var terrain := c.terrain.data.duplicate()
	var altitude := c.altitude.data.duplicate()
	var built := _charged(b, Tools.Kind.HIGHWAY, Vector2i(54, 50), Vector2i(65, 50))
	check(bool(built["applied"]), built["reason"])
	check_eq(c.building_at(60, 50), NS.HIGHWAY_SLOPE_E)
	check_eq(Terrain.slope(c.terrain.at(61, 50)), Terrain.PLATEAU, "the hilltop row is stored as a plateau")
	var cleared := _charged(b, Tools.Kind.BULLDOZE, Vector2i(54, 50), Vector2i(65, 51))
	check(bool(cleared["applied"]), cleared["reason"])
	check(c.terrain.data == terrain, "the land is as it was before the highway")
	check(c.altitude.data == altitude, "and at the same heights")
	var library := b.preview(Tools.Kind.LIBRARY, Vector2i(61, 50))
	check(bool(library["ok"]), "the hilltop can be built on: %s" % library["reason"])
	_check_round_trip(c, "hillside")


# ── Ramps over pipes ─────────────────────────────────────────────────────

func test_a_ramp_stands_over_a_water_pipe() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.HIGHWAY, Vector2i(40, 40), Vector2i(60, 40))
	var road := b.apply(Tools.Kind.ROAD, Vector2i(50, 30), Vector2i(50, 39))
	var open_sites := b.onramp_sites(road["tiles"], Vector2i(50, 39))
	check_eq(open_sites, [Vector2i(49, 39), Vector2i(51, 39)] as Array[Vector2i])
	check(bool(b.apply(Tools.Kind.WATER_PIPE, Vector2i(45, 39), Vector2i(55, 39))["applied"]))
	check_eq(b.onramp_sites(road["tiles"], Vector2i(50, 39)), open_sites, "the offer does not vanish over a pipe")
	var pipe := c.underground.at(49, 39)
	var r := _charged(b, Tools.Kind.ONRAMP, Vector2i(49, 39))
	check(bool(r["applied"]), r["reason"])
	check_eq(int(r["cost"]), Tools.cost(Tools.Kind.ONRAMP))
	check(NS.is_onramp(c.building_at(49, 39)))
	check_eq(c.underground.at(49, 39), pipe, "the pipe is kept")
	check(c.conducts_water(49, 39))
	_charged(b, Tools.Kind.BULLDOZE, Vector2i(49, 39))
	check_eq(c.underground.at(49, 39), pipe, "and survives the ramp's demolition")
	check(c.conducts_water(49, 39))
	# A piece that digs still needs the ground beneath it.
	var portal := b.preview(Tools.Kind.SUBWAY_STATION, Vector2i(47, 39))
	check(not bool(portal["ok"]))
	check_eq(portal["reason"], "blocked underground")
	_check_round_trip(c, "ramp")


# ── Water ────────────────────────────────────────────────────────────────

func test_trees_do_not_stand_in_water_the_land_lets_in() -> void:
	var c := TerrainGenerator.new().generate({"coast": "west", "river": false, "hills": 10, "water": 0, "trees": 100}, SimRng.new(5))
	c.founded_year = 2000
	c.funds = 1000000
	var b := Builder.new(c, CityStats.new())
	var flooded := 0
	for y in range(5, 120):
		for x in range(1, 120):
			if flooded >= 3:
				break
			if not (Buildings.is_tree(c.building_at(x, y)) and c.is_water(x - 1, y) and not c.is_water(x, y) and not c.is_water(x + 1, y)):
				continue
			var wet_before := 0
			for yy in range(y - 3, y + 4):
				for xx in range(x - 3, x + 5):
					if c.in_bounds(xx, yy) and c.is_water(xx, yy):
						wet_before += 1
			var r := _charged(b, Tools.Kind.LOWER_LAND, Vector2i(x + 1, y))
			if not bool(r["applied"]):
				continue
			var wet_after := 0
			for yy in range(y - 3, y + 4):
				for xx in range(x - 3, x + 5):
					if not c.in_bounds(xx, yy) or not c.is_water(xx, yy):
						continue
					wet_after += 1
					check(not Buildings.is_tree(c.building_at(xx, yy)), "no trees in the water at %d,%d" % [xx, yy])
			if wet_after > wet_before:
				flooded += 1
	check_gt(flooded, 0, "the shore was lowered into the water")


func test_a_road_is_not_bridged_over_flooded_land() -> void:
	var b := _builder()
	var c := b.city
	for x in range(20, 24):
		c.flood_overlay[Vector2i(x, 30)] = 1
	var r := _charged(b, Tools.Kind.ROAD, Vector2i(15, 30), Vector2i(28, 30))
	check(bool(r["applied"]), r["reason"])
	check(not r.has("choice_kind"), "no bridge is offered")
	check_eq(r["tiles"].size(), 5, "the road stops at the flood")
	check_eq(int(r["cost"]), 50)
	check_eq(r.get("stopped", ""), Builder.REASON_FLOODED)
	for x in range(20, 29):
		check_eq(c.building_at(x, 30), Buildings.NONE, "nothing built at %d" % x)
	var started := b.preview(Tools.Kind.ROAD, Vector2i(21, 30), Vector2i(26, 30))
	check(not bool(started["ok"]))
	check_eq(started["reason"], Builder.REASON_FLOODED)
	# A bridge may not land on a flooded bank either.
	_water_rect(c, 40, 50, 43, 60)
	c.flood_overlay[Vector2i(44, 55)] = 1
	var landing := _charged(b, Tools.Kind.ROAD, Vector2i(36, 55), Vector2i(47, 55), {"choice": &"causeway"})
	check_eq(landing["tiles"].size(), 4, "only the road up to the shore")
	check_eq(c.building_at(41, 55), Buildings.NONE, "no bridge to a flooded bank")
	check_eq(landing.get("stopped", ""), Builder.REASON_FLOODED)
	# With the flood gone the same drags build as usual.
	c.flood_overlay.clear()
	var dry := _charged(b, Tools.Kind.ROAD, Vector2i(15, 30), Vector2i(28, 30))
	check_eq(int(dry["cost"]), 90)
	var bridged := _charged(b, Tools.Kind.ROAD, Vector2i(36, 55), Vector2i(47, 55), {"choice": &"causeway"})
	check(bool(bridged["applied"]), bridged["reason"])
	check_eq(c.building_at(41, 55), 87)


func test_a_standing_bridge_is_not_offered_again() -> void:
	var b := _builder()
	var c := b.city
	_water_rect(c, 40, 5, 43, 20)
	var built := _charged(b, Tools.Kind.ROAD, Vector2i(36, 10), Vector2i(47, 10), {"choice": &"causeway"})
	check(bool(built["applied"]), built["reason"])
	check_eq(built.get("choice_kind"), &"bridge")
	# Dragging along the finished crossing has nothing to build or to ask.
	var again := b.preview(Tools.Kind.ROAD, Vector2i(36, 10), Vector2i(47, 10))
	check(not bool(again["ok"]))
	check_eq(again["reason"], "nothing to build")
	check(not again.has("needs_confirmation"))
	# Extending the road past the bridge is an ordinary road drag.
	var more := _charged(b, Tools.Kind.ROAD, Vector2i(38, 10), Vector2i(50, 10))
	check(bool(more["applied"]), more["reason"])
	check(not more.has("needs_confirmation"), "no bridge question for a bridge that stands")
	check_eq(int(more["cost"]), 30)
	check_eq(c.building_at(41, 10), 87, "the bridge is untouched")
	# A bridge with a missing piece is still quoted for the gap.
	_charged(b, Tools.Kind.BULLDOZE, Vector2i(42, 10))
	var gap := b.preview(Tools.Kind.ROAD, Vector2i(36, 10), Vector2i(50, 10))
	check(bool(gap["ok"]), gap["reason"])
	check_eq(gap.get("choice_kind"), &"bridge")
	check_eq(int(gap["cost"]), Builder.BRIDGE_COST_CAUSEWAY)
