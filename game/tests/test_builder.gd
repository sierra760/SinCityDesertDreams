# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const NS := preload("res://scripts/core/network_shapes.gd")


## A modern flat city so every ordinary tool is already invented.
func _builder(funds: int = 20000) -> Builder:
	var c := flat_city(funds)
	c.founded_year = 2000
	return Builder.new(c, CityStats.new())


func _water_row(c: City, y: int, x0: int, x1: int) -> void:
	for x in range(x0, x1 + 1):
		c.terrain.put(x, y, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
		c.set_heights(x, y, c.ground_height(x, y), c.ground_height(x, y))


func test_road_drag_builds_connected_shapes() -> void:
	var b := _builder()
	var c := b.city
	var r := b.apply(Tools.Kind.ROAD, Vector2i(10, 10), Vector2i(14, 12))
	check(r["ok"], r["reason"])
	check(r["applied"])
	check_eq(r["cost"], 70)
	check_eq(c.funds, 20000 - 70)
	check_eq(r["tiles"].size(), 7)
	check_eq(c.building_at(10, 10), Buildings.id_of(&"road_ew"))
	check_eq(c.building_at(12, 10), Buildings.id_of(&"road_ew"))
	check_eq(c.building_at(14, 10), Buildings.id_of(&"road_sw"), "corner turns south")
	check_eq(c.building_at(14, 11), Buildings.id_of(&"road_ns"))
	check_eq(c.building_at(14, 12), Buildings.id_of(&"road_ns"))
	# A second road meeting the first makes a junction.
	var r2 := b.apply(Tools.Kind.ROAD, Vector2i(12, 11), Vector2i(12, 13))
	check(r2["ok"], r2["reason"])
	check_eq(c.building_at(12, 10), Buildings.id_of(&"road_esw"))
	# Dragging over existing road costs nothing.
	var r3 := b.preview(Tools.Kind.ROAD, Vector2i(10, 10), Vector2i(14, 10))
	check(not r3["ok"])
	check_eq(r3["cost"], 0)


func test_power_line_crosses_road() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.ROAD, Vector2i(10, 10), Vector2i(14, 10))
	var r := b.apply(Tools.Kind.POWER_LINE, Vector2i(12, 8), Vector2i(12, 12))
	check(r["ok"], r["reason"])
	check_eq(r["cost"], 10)
	check_eq(c.building_at(12, 10), Buildings.id_of(&"cross_road_ew_power_ns"))
	check(c.conducts_power(12, 10))
	check(c.conducts_power(12, 8))
	check(not c.conducts_power(11, 10))
	check_eq(c.building_at(12, 9), Buildings.id_of(&"power_ns"))
	check_eq(c.building_at(11, 10), Buildings.id_of(&"road_ew"), "road keeps its run through the crossing")
	# Rail across the same road makes a level crossing; a bend cannot be crossed.
	b.apply(Tools.Kind.RAIL, Vector2i(13, 8), Vector2i(13, 12))
	check_eq(c.building_at(13, 10), Buildings.id_of(&"cross_road_ew_rail_ns"))
	b.apply(Tools.Kind.ROAD, Vector2i(14, 10), Vector2i(14, 12))
	var blocked := b.preview(Tools.Kind.POWER_LINE, Vector2i(14, 10), Vector2i(14, 10))
	check(not blocked["ok"], "power line over a road bend is refused")


func test_power_line_crosses_zones_and_stops_at_buildings() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.ZONE_RES_LOW, Vector2i(10, 10), Vector2i(14, 10))
	var r := b.apply(Tools.Kind.POWER_LINE, Vector2i(9, 10), Vector2i(15, 10))
	check(r["ok"], r["reason"])
	check_eq(r["cost"], 14)
	check_eq(c.zone_kind_at(12, 10), Zones.RES_LOW, "zone survives under the line")
	c.stamp_building(20, 10, Buildings.COAL_PLANT)
	var r2 := b.apply(Tools.Kind.POWER_LINE, Vector2i(17, 10), Vector2i(23, 10))
	check(r2["ok"], r2["reason"])
	check_eq(r2["tiles"].size(), 3, "line stops when it reaches the plant")
	check_eq(c.building_at(20, 10), Buildings.COAL_PLANT)
	# Roads take the zone with them.
	b.apply(Tools.Kind.ROAD, Vector2i(10, 12), Vector2i(10, 12))
	b.apply(Tools.Kind.ZONE_COM_LOW, Vector2i(11, 12), Vector2i(11, 12))
	b.apply(Tools.Kind.ROAD, Vector2i(11, 12), Vector2i(11, 12))
	check_eq(c.zone_kind_at(11, 12), Zones.NONE)


func test_zoning_charges_only_valid_tiles() -> void:
	var b := _builder()
	var c := b.city
	c.terrain.put(11, 11, Terrain.SLOPE_N)
	_water_row(c, 12, 10, 10)
	c.building.put(12, 12, (Buildings.TREES_1 + 2))
	c.building.put(10, 11, Buildings.SMALL_PARK)
	var p := b.preview(Tools.Kind.ZONE_RES_LOW, Vector2i(10, 10), Vector2i(12, 12))
	check(p["ok"], p["reason"])
	check_eq(p["cost"], 6 * 5, "slope, water and park tiles are free")
	check_eq(p["tiles"].size(), 6)
	check_eq(c.zone_kind_at(10, 10), Zones.NONE, "preview does not zone")
	var r := b.apply(Tools.Kind.ZONE_RES_LOW, Vector2i(10, 10), Vector2i(12, 12))
	check_eq(r["cost"], 30)
	check_eq(c.funds, 20000 - 30)
	check_eq(c.zone_kind_at(10, 10), Zones.RES_LOW)
	check_eq(c.zone_kind_at(11, 11), Zones.NONE, "slope not zoned")
	check_eq(c.zone_kind_at(10, 12), Zones.NONE, "water not zoned")
	check_eq(c.zone_kind_at(12, 12), Zones.RES_LOW, "trees are zoned and kept")
	check_eq(c.building_at(12, 12), (Buildings.TREES_1 + 2))
	# Re-zoning the same kind costs nothing; a dense zone costs 10 per tile.
	var same := b.preview(Tools.Kind.ZONE_RES_LOW, Vector2i(10, 10), Vector2i(12, 12))
	check(not same["ok"])
	var dense := b.preview(Tools.Kind.ZONE_RES_HIGH, Vector2i(10, 10), Vector2i(12, 12))
	check_eq(dense["cost"], 60)
	var dz := b.apply(Tools.Kind.DEZONE, Vector2i(10, 10), Vector2i(12, 12))
	check(dz["ok"])
	check_eq(dz["cost"], 6)
	check_eq(c.zone_kind_at(12, 12), Zones.NONE)


func test_seaport_needs_shore_and_military_is_a_reward() -> void:
	var b := _builder()
	var c := b.city
	var inland := b.preview(Tools.Kind.SEAPORT, Vector2i(30, 30), Vector2i(32, 32))
	check(not inland["ok"])
	_water_row(c, 33, 28, 36)
	var shore := b.apply(Tools.Kind.SEAPORT, Vector2i(30, 30), Vector2i(32, 32))
	check(shore["ok"], shore["reason"])
	check_eq(shore["cost"], 9 * 150)
	check_eq(c.zone_kind_at(31, 31), Zones.SEAPORT)
	var locked := b.preview(Tools.Kind.REWARD_MILITARY_BASE, Vector2i(40, 40), Vector2i(43, 43))
	check(not locked["ok"])
	b.stats.rewards_offered[&"military_base"] = true
	var base := b.apply(Tools.Kind.REWARD_MILITARY_BASE, Vector2i(40, 40), Vector2i(43, 43))
	check(base["ok"], base["reason"])
	check_eq(base["cost"], 0)
	check_eq(c.zone_kind_at(41, 41), Zones.MILITARY)
	check(b.stats.rewards_built.get(&"military_base", false) == false, "zoning a base does not consume a building reward")
	check(not b.preview(Tools.Kind.BULLDOZE, Vector2i(41, 41)).ok, "military land refuses the bulldozer")


func test_buildings_refuse_slopes_and_water() -> void:
	var b := _builder()
	var c := b.city
	c.terrain.put(21, 21, Terrain.SLOPE_E)
	var slope := b.preview(Tools.Kind.POLICE, Vector2i(20, 20))
	check(not slope["ok"])
	check_eq(slope["tiles"].size(), 9, "preview still shows the footprint")
	_water_row(c, 31, 30, 32)
	check(not b.preview(Tools.Kind.SCHOOL, Vector2i(30, 30))["ok"])
	c.set_heights(41, 41, 5)
	check(not b.preview(Tools.Kind.FIRE, Vector2i(40, 40))["ok"], "uneven heights refuse")
	check(not b.preview(Tools.Kind.HOSPITAL, Vector2i(126, 126))["ok"], "footprint leaving the map")
	c.building.put(51, 51, (Buildings.TREES_1 + 1))
	c.building.put(52, 52, (Buildings.RUBBLE_1 + 1))
	var r := b.apply(Tools.Kind.POLICE, Vector2i(50, 50))
	check(r["ok"], r["reason"])
	check_eq(r["cost"], 500)
	check_eq(c.building_at(52, 52), Buildings.POLICE_STATION, "trees and rubble are cleared for free")
	check_eq(c.anchor_of(52, 52), Vector2i(50, 50))
	check(c.facility(Vector2i(50, 50)).get("key", &"") == &"police_station")
	check_eq(int(c.facility(Vector2i(50, 50)).get("built_day", -1)), c.day)
	check(c.conducts_power(51, 51))
	check(not b.preview(Tools.Kind.SCHOOL, Vector2i(52, 52))["ok"], "occupied footprint")


func test_special_sites() -> void:
	var b := _builder()
	var c := b.city
	check(not b.preview(Tools.Kind.HYDRO_PLANT, Vector2i(10, 10))["ok"])
	c.terrain.put(10, 10, Terrain.WATERFALL)
	var dam := b.apply(Tools.Kind.HYDRO_PLANT, Vector2i(10, 10))
	check(dam["ok"], dam["reason"])
	check_eq(c.building_at(10, 10), Buildings.HYDRO_PLANT_A)
	check(not b.preview(Tools.Kind.MARINA, Vector2i(20, 20))["ok"], "marina needs water")
	_water_row(c, 22, 18, 26)
	var marina := b.apply(Tools.Kind.MARINA, Vector2i(20, 20))
	check(marina["ok"], marina["reason"])
	check_eq(c.building_at(22, 22), Buildings.MARINA)
	check(not b.preview(Tools.Kind.DESALINATION, Vector2i(40, 40))["ok"], "desalination needs the shore")
	var desal := b.apply(Tools.Kind.DESALINATION, Vector2i(20, 23))
	check(desal["ok"], desal["reason"])
	check(c.conducts_water(21, 24))
	var pump := b.apply(Tools.Kind.WATER_PUMP, Vector2i(30, 30))
	check(pump["ok"])
	check(c.facilities.has(Vector2i(30, 30)))
	check(not b.preview(Tools.Kind.WATER_PUMP, Vector2i(18, 22))["ok"], "pump refuses water")


func test_funds_gate() -> void:
	var b := _builder(45)
	var c := b.city
	var p := b.preview(Tools.Kind.ROAD, Vector2i(10, 10), Vector2i(14, 10))
	check(not p["ok"])
	check_eq(p["reason"], Builder.REASON_FUNDS)
	check_eq(p["cost"], 50, "cost is still reported")
	var r := b.apply(Tools.Kind.ROAD, Vector2i(10, 10), Vector2i(14, 10))
	check(not r["applied"])
	check_eq(c.funds, 45)
	check_eq(c.building_at(10, 10), Buildings.NONE)
	var short := b.apply(Tools.Kind.ROAD, Vector2i(10, 10), Vector2i(13, 10))
	check(short["ok"])
	check_eq(c.funds, 5)
	check(not b.apply(Tools.Kind.COAL_PLANT, Vector2i(30, 30))["ok"])


func test_bulldoze_rubble_and_networks() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.SCHOOL, Vector2i(10, 10))
	b.apply(Tools.Kind.ROAD, Vector2i(20, 10), Vector2i(24, 10))
	b.apply(Tools.Kind.ZONE_RES_LOW, Vector2i(30, 10), Vector2i(30, 10))
	c.stamp_building(30, 10, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	var funds := c.funds
	var r := b.apply(Tools.Kind.BULLDOZE, Vector2i(11, 11))
	check(r["ok"], r["reason"])
	check_eq(r["cost"], 9, "one dollar per footprint tile")
	check_eq(c.funds, funds - 9)
	for dy in 3:
		for dx in 3:
			check(Buildings.is_rubble(c.building_at(10 + dx, 10 + dy)), "rubble at %d,%d" % [dx, dy])
	check(not c.facilities.has(Vector2i(10, 10)))
	check(not c.conducts_power(11, 11))
	var road := b.apply(Tools.Kind.BULLDOZE, Vector2i(22, 10))
	check_eq(road["cost"], 1)
	check_eq(c.building_at(22, 10), Buildings.NONE, "roads leave nothing")
	check_eq(c.building_at(21, 10), Buildings.id_of(&"road_ew"))
	var home := b.apply(Tools.Kind.BULLDOZE, Vector2i(30, 10))
	check(home["ok"])
	check(Buildings.is_rubble(c.building_at(30, 10)))
	check_eq(c.zone_kind_at(30, 10), Zones.RES_LOW, "zone kind survives demolition")
	var rubble := b.apply(Tools.Kind.BULLDOZE, Vector2i(30, 10))
	check_eq(rubble["cost"], 1)
	check_eq(c.building_at(30, 10), Buildings.NONE)
	check(not b.preview(Tools.Kind.BULLDOZE, Vector2i(60, 60))["ok"], "empty ground")
	# A drag across empty and built tiles charges only what it clears.
	var line := b.apply(Tools.Kind.BULLDOZE, Vector2i(18, 10), Vector2i(26, 10))
	check_eq(line["cost"], 4)
	check(not b.preview(Tools.Kind.BULLDOZE, Vector2i(24, 10))["ok"])


func test_bridge_over_water_gap() -> void:
	var b := _builder()
	var c := b.city
	_water_row(c, 10, 12, 14)
	var p := b.preview(Tools.Kind.ROAD, Vector2i(10, 10), Vector2i(16, 10))
	check(p["ok"], p["reason"])
	check_eq(p["cost"], 4 * 10 + 3 * Builder.BRIDGE_COST_CAUSEWAY)
	var r := b.apply(Tools.Kind.ROAD, Vector2i(10, 10), Vector2i(16, 10))
	check(r["ok"])
	for x in range(12, 15):
		check_eq(c.building_at(x, 10), Buildings.id_of(&"bridge_causeway_pylon"), "causeway at %d" % x)
		check(c.is_water(x, 10), "water stays under the bridge")
	check_eq(c.building_at(11, 10), Buildings.id_of(&"road_ew"))
	check_eq(c.building_at(15, 10), Buildings.id_of(&"road_ew"))
	check_eq(NS.connection_mask(c, 11, 10, NS.Family.ROAD) & NS.EAST, NS.EAST, "road connects onto the bridge")
	# A drag that ends in the water still reaches the far bank.
	_water_row(c, 20, 12, 19)
	var long := b.apply(Tools.Kind.ROAD, Vector2i(11, 20), Vector2i(15, 20))
	check(long["ok"], long["reason"])
	check_eq(long["cost"], 2 * 10 + 8 * Builder.BRIDGE_COST_SUSPENSION)
	check_eq(c.building_at(12, 20), Buildings.id_of(&"bridge_suspension_start"))
	check_eq(c.building_at(15, 20), Buildings.id_of(&"bridge_suspension_span"))
	check_eq(c.building_at(19, 20), Buildings.id_of(&"bridge_suspension_end"))
	check_eq(c.building_at(20, 20), Buildings.id_of(&"road_ew"), "far bank gets its road")
	# Rail and power lines use their own spans; a lone water click is refused.
	_water_row(c, 30, 12, 14)
	var rail := b.apply(Tools.Kind.RAIL, Vector2i(10, 30), Vector2i(16, 30))
	check(rail["ok"], rail["reason"])
	check_eq(c.building_at(13, 30), Buildings.id_of(&"bridge_rail_span"))
	var power := b.apply(Tools.Kind.POWER_LINE, Vector2i(10, 40), Vector2i(16, 40))
	check(power["ok"])
	_water_row(c, 50, 12, 14)
	check(not b.preview(Tools.Kind.ROAD, Vector2i(13, 50))["ok"], "bridges start from the shore")
	c.set_heights(15, 60, 6)
	_water_row(c, 60, 12, 14)
	var uneven := b.preview(Tools.Kind.ROAD, Vector2i(10, 60), Vector2i(16, 60))
	check_eq(uneven["tiles"].size(), 2, "banks must be level: the walk stops at the shore")
	check_eq(uneven["cost"], 20)


func test_pipe_and_subway_drags_write_underground() -> void:
	var b := _builder()
	var c := b.city
	var r := b.apply(Tools.Kind.WATER_PIPE, Vector2i(10, 10), Vector2i(13, 12))
	check(r["ok"], r["reason"])
	check_eq(r["cost"], 6 * 3)
	check_eq(c.underground.at(10, 10), NS.EAST, "pipe codes are connection masks")
	check_eq(c.underground.at(11, 10), NS.EAST | NS.WEST)
	check_eq(c.underground.at(13, 10), NS.WEST | NS.SOUTH)
	check_eq(c.underground.at(13, 12), NS.NORTH)
	check(c.conducts_water(12, 10))
	check_eq(c.building_at(12, 10), Buildings.NONE, "surface untouched")
	var s := b.apply(Tools.Kind.SUBWAY, Vector2i(11, 8), Vector2i(11, 12))
	check(s["ok"], s["reason"])
	check_eq(s["cost"], 5 * 100)
	check_eq(c.underground.at(11, 10), NS.PIPE_EW_SUBWAY_NS, "subway under a pipe makes a crossing")
	check_eq(c.underground.at(11, 9), NS.SUBWAY_OFFSET + (NS.NORTH | NS.SOUTH))
	check_eq(c.underground.at(11, 8), NS.SUBWAY_OFFSET + NS.SOUTH)
	check(c.conducts_water(11, 10), "the pipe still runs through the crossing")
	check_eq(NS.connection_mask(c, 10, 10, NS.Family.PIPE) & NS.EAST, NS.EAST)
	var again := b.preview(Tools.Kind.WATER_PIPE, Vector2i(10, 10), Vector2i(13, 10))
	check(not again["ok"], "existing pipes are free and nothing is left to build")
	var station := b.apply(Tools.Kind.SUBWAY_STATION, Vector2i(11, 13))
	check(station["ok"], station["reason"])
	check_eq(c.underground.at(11, 13), NS.STATION_LINK)
	check_eq(c.building_at(11, 13), Buildings.SUBWAY_STATION)
	check(c.facilities.has(Vector2i(11, 13)))
	check_eq(NS.connection_mask(c, 11, 12, NS.Family.SUBWAY) & NS.SOUTH, NS.SOUTH)


func test_subway_portal_links_rail() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.RAIL, Vector2i(10, 10), Vector2i(10, 14))
	check(not b.preview(Tools.Kind.SUBWAY_PORTAL, Vector2i(30, 30))["ok"], "portal needs rail or subway")
	var r := b.apply(Tools.Kind.SUBWAY_PORTAL, Vector2i(10, 15))
	check(r["ok"], r["reason"])
	check_eq(r["cost"], 500)
	check_eq(c.building_at(10, 15), Buildings.id_of(&"subway_portal_n"))
	check_eq(c.underground.at(10, 15), NS.SUBWAY_OFFSET + (NS.NORTH | NS.SOUTH), "portal carries a north-south subway run")
	check_eq(c.building_at(10, 14), Buildings.id_of(&"rail_ns"))
	var s := b.apply(Tools.Kind.SUBWAY, Vector2i(10, 16), Vector2i(10, 18))
	check(s["ok"])
	check_eq(c.underground.at(10, 16), NS.SUBWAY_OFFSET + (NS.NORTH | NS.SOUTH))
	check_eq(c.underground.at(10, 15), NS.SUBWAY_OFFSET + NS.SOUTH, "the portal's tunnel now points at the subway")


## A builder on a vertex-lattice city with one straight hillside: ground at
## height 5 on the raised side of the vertex line `edge`, 4 on the other.
## Rising north (or west for an east-west hill) when `rise_low` is set.
func _hillside_builder(east_west: bool, edge: int, rise_low: bool) -> Builder:
	var b := _builder()
	var lattice := TerrainSurface.new(4)
	for vy in TerrainSurface.VERTS_Y:
		for vx in TerrainSurface.VERTS_X:
			var along := vx if east_west else vy
			var high := along <= edge - 1 if rise_low else along >= edge + 1
			lattice.set_vertex(vx, vy, 5 if high else 4)
	lattice.project(b.city)
	return b


func test_highway_climbs_hillside_onto_hilltop() -> void:
	# Tile row 11 is the north-facing slope; row 10 is the hilltop at 5.
	var b := _hillside_builder(false, 12, true)
	var c := b.city
	check_eq(Terrain.slope(c.terrain.at(10, 11)), Terrain.SLOPE_N)
	check_eq(c.ground_height(10, 10), 5)
	var vertices: PackedByteArray = (c.terrain_surface as TerrainSurface).vertices.duplicate()
	var quote := b.preview(Tools.Kind.HIGHWAY, Vector2i(10, 6), Vector2i(10, 15))
	check(quote["ok"], quote["reason"])
	var h := b.apply(Tools.Kind.HIGHWAY, Vector2i(10, 6), Vector2i(10, 15))
	check(h["ok"], h["reason"])
	check_eq(h["cost"], quote["cost"])
	check_eq(h["cost"], 5 * 100, "five blocks, one on the hillside")
	for p: Vector2i in [Vector2i(10, 10), Vector2i(11, 10), Vector2i(10, 11), Vector2i(11, 11)]:
		check_eq(c.building_at(p.x, p.y), NS.HIGHWAY_SLOPE_N, "the whole block takes the slope piece")
		check_eq(c.ground_height(p.x, p.y), 4, "the block shares the slope's base")
	check_eq(Terrain.slope(c.terrain.at(10, 10)), Terrain.PLATEAU, "the hilltop row is stored as a plateau")
	check_eq(Terrain.slope(c.terrain.at(11, 10)), Terrain.PLATEAU)
	check_eq(Terrain.slope(c.terrain.at(10, 11)), Terrain.SLOPE_N)
	check_eq((c.terrain_surface as TerrainSurface).vertices, vertices, "the ground itself does not move")
	check_eq(c.building_at(10, 8), NS.HIGHWAY_NS, "level blocks above the hill")
	check_eq(c.building_at(10, 14), NS.HIGHWAY_NS, "level blocks below the hill")
	check(NS.highway_block_mask(c, 10, 10) & (NS.NORTH | NS.SOUTH) == NS.NORTH | NS.SOUTH, "the hillside joins both neighbours")
	# The block is one 2×2 picture: a ring of single corner flags.
	check_eq(Zones.corners(c.zone.at(10, 10)), Zones.CORNER_NW)
	check_eq(Zones.corners(c.zone.at(11, 10)), Zones.CORNER_NE)
	check_eq(Zones.corners(c.zone.at(11, 11)), Zones.CORNER_SE)
	check_eq(Zones.corners(c.zone.at(10, 11)), Zones.CORNER_SW)
	check_eq(Zones.kind(c.zone.at(10, 10)), Zones.NONE)
	check_eq(Zones.corners(c.zone.at(10, 8)), 0, "level blocks are drawn tile by tile")
	var removed := b.apply(Tools.Kind.BULLDOZE, Vector2i(11, 11))
	check(removed["ok"], removed["reason"])
	check(not NS.is_highway(c.building_at(10, 10)), "the whole hillside block comes down together")
	check_eq(Zones.corners(c.zone.at(10, 10)), 0, "and leaves no lot flags behind")


func test_highway_climbs_hillside_from_its_foot() -> void:
	# Tile column 21 is the east-rising slope; column 20 is the foot at 4.
	var b := _hillside_builder(true, 21, false)
	var c := b.city
	check_eq(Terrain.slope(c.terrain.at(21, 30)), Terrain.SLOPE_E)
	check_eq(c.ground_height(20, 30), 4)
	var h := b.apply(Tools.Kind.HIGHWAY, Vector2i(16, 30), Vector2i(25, 31))
	check(h["ok"], h["reason"])
	check_eq(h["cost"], 5 * 100)
	for p: Vector2i in [Vector2i(20, 30), Vector2i(21, 30), Vector2i(20, 31), Vector2i(21, 31)]:
		check_eq(c.building_at(p.x, p.y), NS.HIGHWAY_SLOPE_E)
		check_eq(c.ground_height(p.x, p.y), 4)
	check_eq(Terrain.slope(c.terrain.at(20, 30)), Terrain.FLAT, "the foot keeps its level ground")
	check_eq(c.building_at(18, 30), NS.HIGHWAY_EW)
	check_eq(c.building_at(22, 30), NS.HIGHWAY_EW)


func test_highway_refuses_unsuitable_hillsides() -> void:
	var b := _hillside_builder(false, 12, true)
	var c := b.city
	var funds := c.funds
	var across := b.preview(Tools.Kind.HIGHWAY, Vector2i(6, 10), Vector2i(15, 11))
	check(not across["ok"], "a hill rising across an east-west highway")
	check_eq(across["reason"], "the slope runs across the path")
	var turn := b.apply(Tools.Kind.HIGHWAY, Vector2i(10, 4), Vector2i(14, 10))
	check(turn["ok"], turn["reason"])
	check_eq(c.building_at(10, 8), NS.HIGHWAY_NS)
	check(not NS.is_highway(c.building_at(10, 10)), "the drag stops before turning on the hillside")
	check_eq(Terrain.slope(c.terrain.at(10, 10)), Terrain.FLAT, "a refused block leaves the hilltop alone")
	check_eq(c.funds, funds - int(turn["cost"]))
	# Two levels across one block: a slope row beside a level row at the
	# wrong height is not a hillside.
	var steep := _hillside_builder(false, 12, true)
	for x in range(30, 32):
		steep.city.set_heights(x, 10, 6)
	check(not steep.preview(Tools.Kind.HIGHWAY, Vector2i(30, 10), Vector2i(30, 13))["ok"])
	check_eq(steep.preview(Tools.Kind.HIGHWAY, Vector2i(30, 10), Vector2i(30, 13))["reason"], "the ground is not level")


func test_highway_ramp_and_tunnel() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.ROAD, Vector2i(15, 8), Vector2i(15, 14))
	var h := b.apply(Tools.Kind.HIGHWAY, Vector2i(10, 10), Vector2i(21, 11))
	check(h["ok"], h["reason"])
	check_eq(h["cost"], 6 * 100)
	check_eq(h["tiles"].size(), 24)
	check_eq(c.building_at(10, 10), NS.HIGHWAY_EW)
	check_eq(c.building_at(21, 11), NS.HIGHWAY_EW)
	check_eq(c.building_at(15, 10), NS.HIGHWAY_EW_ROAD_NS, "road passes under the highway")
	check_eq(c.building_at(15, 11), NS.HIGHWAY_EW_ROAD_NS)
	check_eq(c.building_at(15, 9), Buildings.id_of(&"road_ns"))
	check_eq(NS.connection_mask(c, 15, 9, NS.Family.ROAD) & NS.SOUTH, NS.SOUTH, "road connects through the underpass")
	var turn := b.apply(Tools.Kind.HIGHWAY, Vector2i(22, 10), Vector2i(22, 15))
	check(turn["ok"], turn["reason"])
	check_eq(c.building_at(22, 10), NS.HIGHWAY_CORNER_SW)
	check_eq(c.building_at(22, 14), NS.HIGHWAY_NS)
	check(not b.preview(Tools.Kind.HIGHWAY, Vector2i(10, 10), Vector2i(21, 10))["ok"], "existing blocks are free")
	check(not b.preview(Tools.Kind.ONRAMP, Vector2i(12, 12))["ok"], "ramp needs a road too")
	# A road straight behind the ramp, facing the highway, has no ramp piece:
	# the ramp sits beside the road where it meets the highway.
	b.apply(Tools.Kind.ROAD, Vector2i(12, 13), Vector2i(12, 14))
	var behind := b.preview(Tools.Kind.ONRAMP, Vector2i(12, 12))
	check(not behind["ok"], "a ramp needs the road beside it, along the highway")
	check_eq(ConstructionFlow.sentence(String(behind["reason"])),
		"Place a ramp on an empty tile next to both the road and the highway, where they meet.", "the refusal says where a ramp goes")
	b.apply(Tools.Kind.ROAD, Vector2i(13, 12), Vector2i(13, 14))
	var ramp := b.apply(Tools.Kind.ONRAMP, Vector2i(12, 12))
	check(ramp["ok"], ramp["reason"])
	check_eq(ramp["cost"], 25)
	check_eq(c.building_at(12, 12), Buildings.ONRAMP_FIRST, "ramp faces north to the highway")
	check(not c.flags.has_bits(12, 12, TileFlags.RESERVED_A), "the unswapped piece: road east, highway north")
	check_eq(NS.onramp_endpoints(c.building_at(12, 12), false), [Vector2i.RIGHT, Vector2i.UP])
	check_eq(NS.connection_mask(c, 13, 12, NS.Family.ROAD) & NS.WEST, NS.WEST)
	# A hill three tiles wide takes a tunnel with two portals.
	for x in range(40, 43):
		c.set_heights(x, 40, 6)
	c.terrain.put(39, 40, Terrain.SLOPE_E)
	c.terrain.put(43, 40, Terrain.SLOPE_W)
	check(not b.preview(Tools.Kind.TUNNEL, Vector2i(38, 40))["ok"], "flat ground is no entrance")
	var t := b.preview(Tools.Kind.TUNNEL, Vector2i(39, 40))
	check(t["ok"], t["reason"])
	check_eq(t["cost"], 5 * 150)
	t = b.apply(Tools.Kind.TUNNEL, Vector2i(39, 40))
	check_eq(c.building_at(39, 40), Buildings.id_of(&"tunnel_e"))
	check_eq(c.building_at(43, 40), Buildings.id_of(&"tunnel_w"))
	check_eq(c.building_at(41, 40), Buildings.NONE, "the hill stays on top")
	check_eq(c.tunnel_bits(41, 40), NS.AXIS_EW)
	b.apply(Tools.Kind.ROAD, Vector2i(36, 40), Vector2i(38, 40))
	check_eq(NS.connection_mask(c, 38, 40, NS.Family.ROAD) & NS.EAST, NS.EAST)
	check(not b.preview(Tools.Kind.TUNNEL, Vector2i(39, 40))["ok"], "portal already built")
	var gone := b.apply(Tools.Kind.BULLDOZE, Vector2i(43, 40))
	check(gone["ok"])
	check_eq(gone["cost"], 5)
	check_eq(c.building_at(39, 40), Buildings.NONE, "both portals go")
	check_eq(c.tunnel_bits(41, 40), 0)


func test_signs_limit() -> void:
	var b := _builder()
	var c := b.city
	for i in Builder.SIGN_LIMIT:
		var r := b.place_sign(Vector2i(i, 0), "Sign %d" % i)
		check(r["ok"], "sign %d" % i)
	check_eq(c.signs.size(), Builder.SIGN_LIMIT)
	var extra := b.place_sign(Vector2i(0, 5), "One more")
	check(not extra["ok"])
	check_eq(extra["reason"], "sign limit reached")
	check(b.place_sign(Vector2i(3, 0), "Renamed")["ok"], "replacing an existing sign is allowed")
	check_eq(c.signs[Vector2i(3, 0)], "Renamed")
	check(b.place_sign(Vector2i(3, 0), "")["ok"])
	check(not c.signs.has(Vector2i(3, 0)))
	check(b.place_sign(Vector2i(0, 5), "  Welcome to the Strip, where the lights never sleep  ")["ok"])
	check_eq(String(c.signs[Vector2i(0, 5)]).length(), Builder.SIGN_TEXT_MAX)
	check(not b.place_sign(Vector2i(-1, 0), "x")["ok"])


func test_trees_and_parks() -> void:
	var b := _builder()
	var c := b.city
	var r := b.apply(Tools.Kind.TREES, Vector2i(10, 10), Vector2i(12, 10))
	check(r["ok"])
	check_eq(r["cost"], 9)
	check_eq(c.building_at(10, 10), Buildings.TREES_1)
	check_eq(c.building_at(11, 10), (Buildings.TREES_1 + 1), "denser beside another tree")
	var f := b.apply(Tools.Kind.FOREST, Vector2i(11, 11))
	check(f["ok"])
	check_eq(c.building_at(11, 11), (Buildings.TREES_1 + 3))
	check(not b.preview(Tools.Kind.TREES, Vector2i(10, 10))["ok"], "no tree over a tree")
	var park := b.apply(Tools.Kind.SMALL_PARK, Vector2i(11, 10))
	check(park["ok"], park["reason"])
	check_eq(c.building_at(11, 10), Buildings.SMALL_PARK)
	var big := b.apply(Tools.Kind.LARGE_PARK, Vector2i(20, 20))
	check(big["ok"])
	check_eq(big["cost"], 150)
	check(c.facilities.has(Vector2i(20, 20)))


func test_tree_tool_adds_one_tree_then_thickens_it() -> void:
	var b := _builder()
	var c := b.city
	check_eq(Tools.mode(Tools.Kind.PLANT_TREE), Tools.Mode.POINT)
	check(not Tools.is_building_tool(Tools.Kind.PLANT_TREE))
	var first := b.apply(Tools.Kind.PLANT_TREE, Vector2i(30, 30))
	check(first["ok"], first["reason"])
	check_eq(first["cost"], Tools.cost(Tools.Kind.PLANT_TREE))
	check_eq(c.building_at(30, 30), Buildings.TREES_1, "a single tree on open ground")
	for density in range(2, 8):
		var again := b.apply(Tools.Kind.PLANT_TREE, Vector2i(30, 30))
		check(again["ok"], again["reason"])
		check_eq(c.building_at(30, 30), Buildings.TREES_1 + density - 1, "each click adds density")
	var funds := c.funds
	check(not b.preview(Tools.Kind.PLANT_TREE, Vector2i(30, 30))["ok"], "full density refuses")
	check(not b.apply(Tools.Kind.PLANT_TREE, Vector2i(30, 30))["ok"])
	check_eq(c.funds, funds, "a refused click costs nothing")
	b.apply(Tools.Kind.SMALL_PARK, Vector2i(32, 30))
	check(not b.preview(Tools.Kind.PLANT_TREE, Vector2i(32, 30))["ok"], "no tree over a park")
	_water_row(c, 40, 30, 30)
	check(not b.preview(Tools.Kind.PLANT_TREE, Vector2i(30, 40))["ok"], "no tree in water")


func test_forest_and_level_cover_the_dragged_area() -> void:
	check_eq(Tools.mode(Tools.Kind.FOREST), Tools.Mode.RECT)
	check_eq(Tools.mode(Tools.Kind.LEVEL_LAND), Tools.Mode.RECT)
	var b := _builder()
	var c := b.city
	var forest := b.apply(Tools.Kind.FOREST, Vector2i(14, 13), Vector2i(10, 10))
	check(forest["ok"], forest["reason"])
	check_eq(forest["tiles"].size(), 20, "a 5 by 4 area, not an L-shaped line")
	for y in range(10, 14):
		for x in range(10, 15):
			check(Buildings.is_tree(c.building_at(x, y)), "tree at %d,%d" % [x, y])
	check_eq(forest["cost"], Tools.cost(Tools.Kind.FOREST) * 20)
	for lattice: bool in [false, true]:
		var lb := _lattice_builder() if lattice else _builder()
		var lc := lb.city
		lb.apply(Tools.Kind.RAISE_LAND, Vector2i(42, 42))
		lb.apply(Tools.Kind.RAISE_LAND, Vector2i(44, 41))
		var level := lb.apply(Tools.Kind.LEVEL_LAND, Vector2i(40, 40), Vector2i(46, 44))
		check(level["ok"], level["reason"])
		check_eq(level["cost"], Builder.TERRAIN_STEP_COST * level["tiles"].size())
		for y in range(40, 45):
			for x in range(40, 47):
				check(lc.is_flat(x, y) and lc.ground_height(x, y) == lc.ground_height(40, 40),
					"%s area tile %d,%d level with the start" % ["lattice" if lattice else "tile", x, y])


func test_terrain_tools() -> void:
	var b := _builder()
	var c := b.city
	var up := b.apply(Tools.Kind.RAISE_LAND, Vector2i(20, 20))
	check(up["ok"], up["reason"])
	check_eq(up["cost"], Builder.TERRAIN_STEP_COST)
	check_eq(c.ground_height(20, 20), 5)
	check(c.is_flat(20, 20))
	check_eq(Terrain.slope(c.terrain.at(19, 20)), Terrain.SLOPE_E)
	check_eq(Terrain.slope(c.terrain.at(20, 19)), Terrain.SLOPE_S)
	check_eq(Terrain.slope(c.terrain.at(19, 19)), Terrain.CORNER_SE)
	b.apply(Tools.Kind.RAISE_LAND, Vector2i(20, 20))
	check_eq(c.ground_height(20, 20), 6)
	check_eq(c.ground_height(19, 20), 5, "neighbours are pulled up to keep one-level steps")
	check_eq(c.ground_height(18, 20), 4)
	var down := b.apply(Tools.Kind.LOWER_LAND, Vector2i(20, 20))
	check(down["ok"])
	check_eq(c.ground_height(20, 20), 5)
	var level := b.apply(Tools.Kind.LEVEL_LAND, Vector2i(10, 20), Vector2i(22, 20))
	check(level["ok"], level["reason"])
	check_eq(level["cost"], Builder.TERRAIN_STEP_COST * level["tiles"].size())
	check_eq(c.ground_height(20, 20), 4)
	b.apply(Tools.Kind.LEVEL_LAND, Vector2i(10, 19), Vector2i(22, 19))
	b.apply(Tools.Kind.LEVEL_LAND, Vector2i(10, 21), Vector2i(22, 21))
	check(c.is_flat(20, 20))
	check(c.is_flat(19, 19))
	c.set_heights(30, 30, 0)
	check(not b.preview(Tools.Kind.LOWER_LAND, Vector2i(30, 30))["ok"])
	b.apply(Tools.Kind.ROAD, Vector2i(40, 40), Vector2i(40, 40))
	check(not b.preview(Tools.Kind.RAISE_LAND, Vector2i(40, 40))["ok"], "built land refuses")
	var water := b.apply(Tools.Kind.PLACE_WATER, Vector2i(50, 50))
	check(water["ok"])
	check_eq(water["cost"], 100)
	check(c.is_water(50, 50))
	check_eq(c.water_height(50, 50), 4)
	check(not b.preview(Tools.Kind.PLACE_WATER, Vector2i(50, 50))["ok"])


func test_sea_tools_refuse_after_founding() -> void:
	check(Tools.is_editing_only(Tools.Kind.RAISE_SEA))
	check(Tools.is_editing_only(Tools.Kind.LOWER_SEA))
	for lattice: bool in [false, true]:
		var b := _lattice_builder() if lattice else _builder()
		var c := b.city
		c.sea_level = 4
		var funds := c.funds
		var altitude := c.altitude.data.duplicate()
		for tool: int in [Tools.Kind.RAISE_SEA, Tools.Kind.LOWER_SEA]:
			var quote := b.preview(tool, Vector2i.ZERO)
			check(not quote["ok"])
			check_eq(String(quote["reason"]), Builder.REASON_BEFORE_FOUNDING)
			check(not b.apply(tool, Vector2i.ZERO)["ok"])
		check_eq(c.sea_level, 4, "the sea stays where it was set")
		check_eq(c.funds, funds, "nothing charged")
		check_eq(c.altitude.data, altitude, "no water moved")


func test_availability_and_rewards() -> void:
	var b := _builder(50000)
	var c := b.city
	c.founded_year = 1900
	var early := b.preview(Tools.Kind.GAS_PLANT, Vector2i(10, 10))
	check(not early["ok"])
	check_eq(early["reason"], "not available until %d" % EconomyParams.TECHNOLOGIES[&"gas_plant"],
		"without a rolled year the tool waits for the technology's base year")
	b.stats.inventions[&"gas_plant"] = 1900
	check(b.preview(Tools.Kind.GAS_PLANT, Vector2i(10, 10))["ok"], "recorded invention unlocks the tool")
	check(b.preview(Tools.Kind.COAL_PLANT, Vector2i(10, 10))["ok"])
	check(not Tools.is_available(Tools.Kind.FUSION_PLANT, c, b.stats))
	check(not b.preview(Tools.Kind.REWARD_CITY_HALL, Vector2i(20, 20))["ok"])
	b.stats.rewards_offered[&"city_hall"] = true
	var hall := b.apply(Tools.Kind.REWARD_CITY_HALL, Vector2i(20, 20))
	check(hall["ok"], hall["reason"])
	check_eq(hall["cost"], 0)
	check_eq(c.building_at(21, 21), Buildings.CITY_HALL)
	check(b.stats.rewards_built.get(&"city_hall", false))
	check_eq(Tools.locked_reason(Tools.Kind.REWARD_CITY_HALL, c, b.stats), "already built")


func test_nuclear_free_zone_refuses_new_nuclear_plants() -> void:
	var b := _builder(50000)
	var c := b.city
	var standing := b.apply(Tools.Kind.NUCLEAR_PLANT, Vector2i(10, 10))
	check(standing["ok"], standing["reason"])
	b.stats.ordinances[&"nuclear_free_zone"] = true
	var funds := c.funds
	var refused := b.apply(Tools.Kind.NUCLEAR_PLANT, Vector2i(30, 30))
	check(not refused["ok"], "a nuclear plant is refused in a Nuclear Free Zone")
	check_eq(refused["reason"], Tools.NUCLEAR_FREE_ZONE_REASON)
	check_eq(int(refused["cost"]), 0)
	check_eq(c.funds, funds, "the refusal costs nothing")
	check_eq(c.building_at(30, 30), Buildings.NONE)
	check_eq(b.preview(Tools.Kind.NUCLEAR_PLANT, Vector2i(30, 30))["reason"], Tools.NUCLEAR_FREE_ZONE_REASON)
	check_eq(c.building_at(10, 10), Buildings.NUCLEAR_PLANT, "the plant already standing stays")
	check(b.apply(Tools.Kind.COAL_PLANT, Vector2i(30, 30))["ok"], "other plants are still allowed")
	b.stats.ordinances[&"nuclear_free_zone"] = false
	check(b.apply(Tools.Kind.NUCLEAR_PLANT, Vector2i(50, 50))["ok"], "repealing the ordinance allows nuclear plants again")


func test_tools_table_is_complete() -> void:
	var icons := DirAccess.get_files_at("res://assets/ui/tool-icons")
	var seen := {}
	for tool in Tools.all():
		check(not Tools.display_name(tool).is_empty(), "tool %d has a name" % tool)
		check(icons.has(String(Tools.icon(tool)) + ".svg"), "icon for %s exists" % Tools.display_name(tool))
		seen[Tools.icon(tool)] = true
		var id := Tools.building_id(tool)
		if id > Buildings.NONE and Tools.is_building_tool(tool):
			check_eq(Tools.footprint(tool), Buildings.size(id), "footprint of %s" % Tools.display_name(tool))
			check_eq(Tools.cost(tool), Buildings.cost(id), "price of %s" % Tools.display_name(tool))
	check_eq(Tools.all().size(), Tools.Kind.size())
	check_eq(Tools.zone_kind(Tools.Kind.ZONE_IND_HIGH), Zones.IND_HIGH)
	check_eq(Tools.mode(Tools.Kind.HIGHWAY), Tools.Mode.BLOCK_LINE)
	check_eq(Tools.mode(Tools.Kind.RAISE_SEA), Tools.Mode.GLOBAL)
	check_eq(Tools.dispatch_kind(Tools.Kind.DISPATCH_FIRE), &"fire")
	check_eq(Tools.reward_key(Tools.Kind.REWARD_NEON_DOME), &"neon_dome")


func test_simulation_is_told_about_changes() -> void:
	var c := flat_city()
	var sim := make_simulation(c)
	var b := Builder.new(c, sim.stats, sim)
	var rects: Array = []
	sim.map_changed.connect(func(rect: Rect2i) -> void: rects.append(rect))
	var r := b.apply(Tools.Kind.ROAD, Vector2i(10, 10), Vector2i(12, 10))
	check(r["ok"])
	check_eq(rects.size(), 1)
	var rect: Rect2i = rects[0]
	check(rect.has_point(Vector2i(10, 10)) and rect.has_point(Vector2i(12, 10)))
	check(rect.has_point(Vector2i(13, 10)), "neighbours that were reshaped are inside the rect")
	b.preview(Tools.Kind.ROAD, Vector2i(20, 10), Vector2i(22, 10))
	check_eq(rects.size(), 1, "previews are silent")
	# Crews go out only during an emergency; the preview says so as well.
	var d := b.apply(Tools.Kind.DISPATCH_FIRE, Vector2i(30, 30))
	check(not d["ok"], "no crews are sent outside an emergency")
	check_eq(d["reason"], Builder.REASON_NO_EMERGENCY)
	check_eq(d["cost"], 0)
	check_eq(b.preview(Tools.Kind.DISPATCH_FIRE, Vector2i(30, 30))["reason"], Builder.REASON_NO_EMERGENCY)
	# A bare Builder with no disaster system does not check.
	var bare := Builder.new(c, sim.stats)
	check(bare.preview(Tools.Kind.DISPATCH_FIRE, Vector2i(30, 30))["ok"], "dispatch validates without a disaster system")
	# Release the context/system reference cycle before the synchronous harness quits.
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()


# ── Crossings, bridge landings, one-tile slopes ─────────────────────────

func test_crossings_need_a_right_angle() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.POWER_LINE, Vector2i(10, 10), Vector2i(20, 10))
	var funds := c.funds
	var along := b.apply(Tools.Kind.ROAD, Vector2i(12, 10), Vector2i(18, 10))
	check(not along["ok"], "a road laid along a power line is refused")
	check_eq(c.funds, funds, "nothing charged")
	for x in range(10, 21):
		check(NetworkShapes.is_plain_power(c.building_at(x, 10)), "power line at %d kept" % x)
	var across := b.apply(Tools.Kind.ROAD, Vector2i(15, 7), Vector2i(15, 13))
	check(across["ok"], across["reason"])
	check_eq(c.building_at(15, 10), NetworkShapes.CROSS_POWER_EW_ROAD_NS)
	# Rail along a road stops at the road; the preview agrees with the build.
	b.apply(Tools.Kind.ROAD, Vector2i(30, 30), Vector2i(40, 30))
	var rail_quote := b.preview(Tools.Kind.RAIL, Vector2i(28, 30), Vector2i(36, 30))
	var rail := b.apply(Tools.Kind.RAIL, Vector2i(28, 30), Vector2i(36, 30))
	check_eq(rail_quote["tiles"], rail["tiles"])
	check_eq(rail["tiles"], [Vector2i(28, 30), Vector2i(29, 30)] as Array[Vector2i], "rail stops at the parallel road")
	check(NetworkShapes.is_plain_road(c.building_at(33, 30)))
	# A turn cannot be a crossing: the corner of this drag sits on a line.
	b.apply(Tools.Kind.POWER_LINE, Vector2i(60, 38), Vector2i(60, 42))
	var bend := b.apply(Tools.Kind.ROAD, Vector2i(55, 40), Vector2i(60, 45))
	check(bend["ok"], bend["reason"])
	check(NetworkShapes.is_plain_power(c.building_at(60, 40)), "no crossing at the corner")
	check(not bend["tiles"].has(Vector2i(60, 41)), "the drag stops at the corner")
	# Underground: a pipe along a subway is refused, one across it crosses.
	b.apply(Tools.Kind.SUBWAY, Vector2i(70, 70), Vector2i(80, 70))
	var pipe_along := b.preview(Tools.Kind.WATER_PIPE, Vector2i(72, 70), Vector2i(78, 70))
	check(not pipe_along["ok"], "a pipe along a subway is refused")
	var pipe := b.apply(Tools.Kind.WATER_PIPE, Vector2i(75, 67), Vector2i(75, 73))
	check(pipe["ok"], pipe["reason"])
	check_eq(c.underground.at(75, 70), NetworkShapes.PIPE_NS_SUBWAY_EW)
	# A single click still crosses whichever way the line runs.
	var click := b.apply(Tools.Kind.ROAD, Vector2i(18, 10), Vector2i(18, 10))
	check(click["ok"], click["reason"])
	check_eq(c.building_at(18, 10), NetworkShapes.CROSS_POWER_EW_ROAD_NS)


func test_bridge_landings_follow_the_walk_rules() -> void:
	var b := _builder()
	var c := b.city
	# Military land on the far bank: neither a drag ending over the water nor
	# one ending on the bank builds a bridge onto it.
	_water_row(c, 20, 12, 14)
	c.zone.put(15, 20, Zones.make(Zones.MILITARY))
	var funds := c.funds
	var short := b.apply(Tools.Kind.ROAD, Vector2i(10, 20), Vector2i(13, 20))
	check(short["ok"], short["reason"])
	check_eq(c.building_at(13, 20), Buildings.NONE, "no bridge to protected land")
	check_eq(c.zone_kind_at(15, 20), Zones.MILITARY, "the base keeps its land")
	check_eq(c.funds, funds - 2 * Tools.cost(Tools.Kind.ROAD), "only the shore road is paid")
	var onto := b.preview(Tools.Kind.ROAD, Vector2i(11, 20), Vector2i(17, 20))
	check(not onto["ok"] or not onto["tiles"].has(Vector2i(13, 20)), "no bridge when the landing is refused")
	# A bank on the city limit needs the neighbor prompt, so the bridge stops.
	_water_row(c, 40, 123, 126)
	var edge := b.preview(Tools.Kind.ROAD, Vector2i(120, 40), Vector2i(124, 40))
	check(not edge["tiles"].has(Vector2i(127, 40)), "the edge tile is never paved without asking")
	check(not edge["tiles"].has(Vector2i(124, 40)), "no bridge to the city limit")


func test_one_tile_link_on_a_north_south_slope() -> void:
	var b := _builder()
	var c := b.city
	c.terrain.put(40, 0, Terrain.make(Terrain.SLOPE_S))
	var ask := b.preview(Tools.Kind.ROAD, Vector2i(40, 3), Vector2i(40, 0))
	check_eq(ask.get("choice_kind"), &"neighbor")
	var linked := b.apply(Tools.Kind.ROAD, Vector2i(40, 0), Vector2i(40, 0), {"connect": true})
	check(linked["ok"] and linked["applied"], linked["reason"])
	check(NetworkShapes.is_plain_road(c.building_at(40, 0)), "the sloped border tile carries the road")
	# An east-west slope on the north edge still runs across the link.
	c.terrain.put(50, 0, Terrain.make(Terrain.SLOPE_E))
	check(not b.preview(Tools.Kind.ROAD, Vector2i(50, 0), Vector2i(50, 0), {"connect": true})["ok"])
	# Inland, a one-tile road fits a slope either way.
	c.terrain.put(60, 60, Terrain.make(Terrain.SLOPE_N))
	check(b.preview(Tools.Kind.ROAD, Vector2i(60, 60))["ok"], "north slope")
	c.terrain.put(61, 61, Terrain.make(Terrain.SLOPE_W))
	check(b.preview(Tools.Kind.ROAD, Vector2i(61, 61))["ok"], "west slope")


# ── Land and sea tools after founding ───────────────────────────────────

func test_land_tools_refuse_to_move_built_neighbours() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.ROAD, Vector2i(21, 20), Vector2i(21, 22))
	var funds := c.funds
	var road_id := c.building_at(21, 21)
	var next_to := b.preview(Tools.Kind.RAISE_LAND, Vector2i(20, 21))
	check(not next_to["ok"], "the road beside would tilt")
	var r := b.apply(Tools.Kind.RAISE_LAND, Vector2i(20, 21))
	check(not r["ok"])
	check_eq(c.funds, funds, "refusal is free")
	check_eq(c.ground_height(20, 21), 4)
	check_eq(c.building_at(21, 21), road_id)
	check(c.is_flat(21, 21))
	# Two tiles away the first step is fine but the cascade of a second one
	# would reach the road.
	var first := b.apply(Tools.Kind.RAISE_LAND, Vector2i(19, 21))
	check(first["ok"], first["reason"])
	check(not b.preview(Tools.Kind.RAISE_LAND, Vector2i(19, 21))["ok"], "the cascade reaches the road")
	check(c.is_flat(21, 21))
	# Level skips tiles that would disturb buildings and charges only the rest.
	var level := b.apply(Tools.Kind.LEVEL_LAND, Vector2i(10, 25), Vector2i(19, 21))
	check(level["ok"], level["reason"])
	check(c.is_flat(21, 21))
	check_eq(level["cost"], Builder.TERRAIN_STEP_COST * level["tiles"].size())


## A founded city whose ground is the shared-vertex lattice, as generated
## and native cities are.
func _lattice_builder() -> Builder:
	var b := _builder()
	TerrainEditor.new(b.city)
	return b


func test_lattice_land_tools_keep_the_lattice_in_sync() -> void:
	var b := _lattice_builder()
	var c := b.city
	var s: TerrainSurface = c.terrain_surface
	var r := b.apply(Tools.Kind.RAISE_LAND, Vector2i(30, 30))
	check(r["ok"], r["reason"])
	check_eq(r["cost"], Builder.TERRAIN_STEP_COST)
	check_eq(c.ground_height(30, 30), 5)
	check_eq(s.vertex(30, 30), 5, "the lattice moved with the tile")
	check_eq(s.tile_base(30, 30), c.ground_height(30, 30))
	var doc := SaveFormat.encode_city(c)
	var loaded: City = SaveFormat.decode_city(doc)["city"]
	check_eq(loaded.ground_height(30, 30), 5)
	check_eq((loaded.terrain_surface as TerrainSurface).vertex(31, 31), 5, "saved vertices carry the edit")
	# Built neighbours refuse, preview and apply alike, and nothing is charged.
	b.apply(Tools.Kind.ROAD, Vector2i(41, 40), Vector2i(41, 42))
	var funds := c.funds
	check(not b.preview(Tools.Kind.RAISE_LAND, Vector2i(40, 41))["ok"])
	check(not b.apply(Tools.Kind.RAISE_LAND, Vector2i(40, 41))["ok"])
	check_eq(c.funds, funds)
	check(c.is_flat(41, 41))
	var level := b.apply(Tools.Kind.LEVEL_LAND, Vector2i(25, 30), Vector2i(35, 30))
	check(level["ok"], level["reason"])
	check_eq(c.ground_height(30, 30), 4)
	check_eq(s.vertex(30, 30), 4)
	var water := b.apply(Tools.Kind.PLACE_WATER, Vector2i(50, 50))
	check(water["ok"], water["reason"])
	check(s.has_water(50, 50))
	check(c.is_water(50, 50))


# ── Crossing highways and offered ramps ──────────────────────────────────

func test_road_rail_and_power_cross_a_highway() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.HIGHWAY, Vector2i(10, 10), Vector2i(21, 11))
	var funds := c.funds
	var road := b.apply(Tools.Kind.ROAD, Vector2i(13, 6), Vector2i(13, 15))
	check(road["ok"], road["reason"])
	check(not road.has("stopped"), "the road runs straight through")
	check_eq(road["cost"], 10 * Tools.cost(Tools.Kind.ROAD), "both highway tiles are priced as road")
	check_eq(c.funds, funds - 10 * Tools.cost(Tools.Kind.ROAD))
	check_eq(c.building_at(13, 10), NS.HIGHWAY_EW_ROAD_NS, "the road passes under the highway")
	check_eq(c.building_at(13, 11), NS.HIGHWAY_EW_ROAD_NS)
	check_eq(NS.connection_mask(c, 13, 9, NS.Family.ROAD) & NS.SOUTH, NS.SOUTH)
	check_eq(NS.connection_mask(c, 13, 12, NS.Family.ROAD) & NS.NORTH, NS.NORTH)
	check_eq(NS.highway_block_mask(c, 12, 10) & (NS.EAST | NS.WEST), NS.EAST | NS.WEST, "the highway stays joined")
	# Drawn from the far side too.
	var back := b.apply(Tools.Kind.ROAD, Vector2i(15, 15), Vector2i(15, 6))
	check(back["ok"], back["reason"])
	check_eq(c.building_at(15, 10), NS.HIGHWAY_EW_ROAD_NS)
	check_eq(c.building_at(15, 11), NS.HIGHWAY_EW_ROAD_NS)
	var rail := b.apply(Tools.Kind.RAIL, Vector2i(17, 6), Vector2i(17, 15))
	check(rail["ok"], rail["reason"])
	check_eq(c.building_at(17, 10), NS.HIGHWAY_EW_RAIL_NS)
	check_eq(c.building_at(17, 11), NS.HIGHWAY_EW_RAIL_NS)
	var power := b.apply(Tools.Kind.POWER_LINE, Vector2i(19, 6), Vector2i(19, 15))
	check(power["ok"], power["reason"])
	check_eq(c.building_at(19, 10), NS.HIGHWAY_EW_POWER_NS)
	check(c.conducts_power(19, 10) and c.conducts_power(19, 11), "the line carries power across")
	# A run that stops on the highway's first lane is cut short before it.
	var half := b.apply(Tools.Kind.ROAD, Vector2i(11, 6), Vector2i(11, 10))
	check(half["ok"], half["reason"])
	check_eq(String(half.get("stopped", "")), "a road must cross the whole highway")
	check_eq(c.building_at(11, 10), NS.HIGHWAY_EW, "the highway is untouched")
	check(Buildings.is_road_like(c.building_at(11, 9)))
	# Along the highway is no crossing.
	var lengthwise := b.preview(Tools.Kind.ROAD, Vector2i(12, 10), Vector2i(20, 10))
	check(not lengthwise["ok"], "a road cannot run along a highway lane")
	check_eq(lengthwise["reason"], "a road must cross the highway at right angles")
	# North-south highways take east-west crossings.
	b.apply(Tools.Kind.HIGHWAY, Vector2i(40, 20), Vector2i(41, 31))
	var east := b.apply(Tools.Kind.ROAD, Vector2i(36, 25), Vector2i(45, 25))
	check(east["ok"], east["reason"])
	check_eq(c.building_at(40, 25), NS.HIGHWAY_NS_ROAD_EW)
	check_eq(c.building_at(41, 25), NS.HIGHWAY_NS_ROAD_EW)
	check_eq(NS.connection_mask(c, 42, 25, NS.Family.ROAD) & NS.WEST, NS.WEST)
	# Corners are no crossing.
	b.apply(Tools.Kind.HIGHWAY, Vector2i(60, 40), Vector2i(60, 47))
	b.apply(Tools.Kind.HIGHWAY, Vector2i(60, 40), Vector2i(67, 40))
	var corner := b.preview(Tools.Kind.ROAD, Vector2i(60, 36), Vector2i(60, 44))
	check(corner["ok"])
	check_eq(String(corner.get("stopped", "")), "a road can only cross a straight, level highway")
	# Removing the crossing removes the highway block with it, as before.
	var gone := b.apply(Tools.Kind.BULLDOZE, Vector2i(13, 10))
	check(gone["ok"], gone["reason"])
	check_eq(c.building_at(13, 10), Buildings.NONE)


func test_onramp_sites_where_a_road_meets_a_highway() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.HIGHWAY, Vector2i(10, 10), Vector2i(21, 11))
	var road := b.apply(Tools.Kind.ROAD, Vector2i(13, 6), Vector2i(13, 15))
	var sites := b.onramp_sites(road["tiles"], Vector2i(13, 15))
	check_eq(sites, [Vector2i(12, 12), Vector2i(14, 12), Vector2i(12, 9), Vector2i(14, 9)] as Array[Vector2i],
		"both sides of the road on both sides of the highway, nearest the drag end first")
	var expect := {
		Vector2i(12, 12): [Vector2i.RIGHT, Vector2i.UP],
		Vector2i(14, 12): [Vector2i.LEFT, Vector2i.UP],
		Vector2i(12, 9): [Vector2i.RIGHT, Vector2i.DOWN],
		Vector2i(14, 9): [Vector2i.LEFT, Vector2i.DOWN],
	}
	for site: Vector2i in expect:
		var probe := Builder.new(c.duplicate_city(), CityStats.new())
		var r := probe.apply(Tools.Kind.ONRAMP, site)
		check(r["ok"], r["reason"])
		var id := probe.city.building_at(site.x, site.y)
		var axis := probe.city.flags.has_bits(site.x, site.y, TileFlags.RESERVED_A)
		check_eq(NS.onramp_endpoints(id, axis), expect[site], "ramp at %s joins its road and highway" % site)
	b.apply(Tools.Kind.ONRAMP, Vector2i(12, 12))
	check_eq(b.onramp_sites(road["tiles"], Vector2i(13, 15)), [Vector2i(12, 9), Vector2i(14, 9)] as Array[Vector2i],
		"a road tile with a ramp beside it is not offered another")
	# A road reaching the highway from the side, ending against it.
	var stub := b.apply(Tools.Kind.ROAD, Vector2i(18, 4), Vector2i(18, 9))
	check_eq(b.onramp_sites(stub["tiles"], Vector2i(18, 9)), [Vector2i(17, 9), Vector2i(19, 9)] as Array[Vector2i])
	# A new highway beside an existing road end offers the same spot.
	var b2 := _builder()
	b2.apply(Tools.Kind.ROAD, Vector2i(30, 2), Vector2i(30, 9))
	var hw := b2.apply(Tools.Kind.HIGHWAY, Vector2i(24, 10), Vector2i(37, 11))
	check_eq(b2.onramp_sites(hw["tiles"], Vector2i(37, 11)), [Vector2i(31, 9), Vector2i(29, 9)] as Array[Vector2i])
	# A road running alongside with a gap row is no meeting: nothing offered.
	var b3 := _builder()
	b3.apply(Tools.Kind.HIGHWAY, Vector2i(10, 10), Vector2i(21, 11))
	var parallel := b3.apply(Tools.Kind.ROAD, Vector2i(12, 13), Vector2i(19, 13))
	check(b3.onramp_sites(parallel["tiles"], Vector2i(19, 13)).is_empty())

