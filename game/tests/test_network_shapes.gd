# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const NS := preload("res://scripts/core/network_shapes.gd")


func test_road_shapes_by_mask() -> void:
	check_eq(NS.shape_id(NS.Family.ROAD, 0), Buildings.ROAD_FIRST, "lone tile is a north-south piece")
	check_eq(NS.shape_id(NS.Family.ROAD, NS.NORTH | NS.SOUTH), Buildings.id_of(&"road_ns"))
	check_eq(NS.shape_id(NS.Family.ROAD, NS.EAST | NS.WEST), Buildings.id_of(&"road_ew"))
	check_eq(NS.shape_id(NS.Family.ROAD, NS.NORTH | NS.EAST), Buildings.id_of(&"road_ne"))
	check_eq(NS.shape_id(NS.Family.ROAD, NS.EAST | NS.SOUTH), Buildings.id_of(&"road_se"))
	check_eq(NS.shape_id(NS.Family.ROAD, NS.SOUTH | NS.WEST), Buildings.id_of(&"road_sw"))
	check_eq(NS.shape_id(NS.Family.ROAD, NS.NORTH | NS.WEST), Buildings.id_of(&"road_nw"))
	check_eq(NS.shape_id(NS.Family.ROAD, NS.NORTH | NS.EAST | NS.SOUTH), Buildings.id_of(&"road_nes"))
	check_eq(NS.shape_id(NS.Family.ROAD, 15), Buildings.ROAD_LAST)


func test_family_bases_share_shapes() -> void:
	for mask in 16:
		var road := NS.shape_id(NS.Family.ROAD, mask) - Buildings.ROAD_FIRST
		check_eq(NS.shape_id(NS.Family.POWER, mask) - Buildings.POWER_LINE_FIRST, road, "power mask %d" % mask)
	check_eq(NS.shape_id(NS.Family.RAIL, NS.EAST | NS.WEST), Buildings.id_of(&"rail_ew"))
	check_eq(NS.shape_id(NS.Family.RAIL, NS.NORTH | NS.EAST), Buildings.id_of(&"rail_ne"))
	check_eq(NS.shape_id(NS.Family.RAIL, 15), Buildings.id_of(&"rail_nesw"))


func test_slope_variants_follow_terrain() -> void:
	check_eq(NS.shape_id(NS.Family.ROAD, 0, Terrain.SLOPE_N), Buildings.id_of(&"road_slope_n"))
	check_eq(NS.shape_id(NS.Family.ROAD, 15, Terrain.SLOPE_W), Buildings.id_of(&"road_slope_w"))
	check_eq(NS.shape_id(NS.Family.RAIL, 0, Terrain.SLOPE_E), Buildings.id_of(&"rail_slope_e"))
	check_eq(NS.shape_id(NS.Family.POWER, 0, Terrain.SLOPE_S), Buildings.id_of(&"power_slope_s"))
	check_eq(NS.highway_id(0, NS.AXIS_NS, Terrain.SLOPE_S), NS.HIGHWAY_SLOPE_S)


func test_crossings() -> void:
	check_eq(NS.crossing_id(NS.Family.ROAD, Buildings.id_of(&"power_ns")), Buildings.id_of(&"cross_road_ew_power_ns"))
	check_eq(NS.crossing_id(NS.Family.ROAD, Buildings.id_of(&"rail_ew")), Buildings.id_of(&"cross_road_ns_rail_ew"))
	check_eq(NS.crossing_id(NS.Family.POWER, Buildings.id_of(&"road_ew")), Buildings.id_of(&"cross_road_ew_power_ns"))
	check_eq(NS.crossing_id(NS.Family.RAIL, Buildings.id_of(&"power_ew")), Buildings.id_of(&"cross_rail_ns_power_ew"))
	check_eq(NS.crossing_id(NS.Family.ROAD, Buildings.id_of(&"road_ne")), Buildings.NONE, "bends cannot be crossed")
	check_eq(NS.highway_crossing_id(NS.AXIS_EW, Buildings.id_of(&"road_ns")), NS.HIGHWAY_EW_ROAD_NS)
	check_eq(NS.highway_crossing_id(NS.AXIS_NS, Buildings.id_of(&"power_ew")), NS.HIGHWAY_NS_POWER_EW)
	check_eq(NS.highway_crossing_id(NS.AXIS_NS, Buildings.id_of(&"road_ns")), Buildings.NONE)
	check_eq(NS.underground_crossing(NS.Family.PIPE, NS.underground_straight(NS.Family.SUBWAY, NS.AXIS_EW)), NS.PIPE_NS_SUBWAY_EW)
	check_eq(NS.underground_crossing(NS.Family.SUBWAY, NS.underground_straight(NS.Family.PIPE, NS.AXIS_EW)), NS.PIPE_EW_SUBWAY_NS)
	check_eq(NS.underground_crossing(NS.Family.SUBWAY, NS.EAST | NS.SOUTH), 0, "bends cannot be crossed underground")


func test_highway_pieces() -> void:
	check_eq(NS.highway_id(NS.EAST | NS.WEST), NS.HIGHWAY_EW)
	check_eq(NS.highway_id(NS.NORTH), NS.HIGHWAY_NS)
	check_eq(NS.highway_id(NS.NORTH | NS.EAST), NS.HIGHWAY_CORNER_NE)
	check_eq(NS.highway_id(NS.SOUTH | NS.WEST), NS.HIGHWAY_CORNER_SW)
	check_eq(NS.highway_id(NS.NORTH | NS.EAST | NS.SOUTH), NS.HIGHWAY_JUNCTION)
	check_eq(NS.highway_id(0, NS.AXIS_NS), NS.HIGHWAY_NS)


func test_connection_mask_and_reshape() -> void:
	var c := flat_city()
	for x in range(10, 13):
		c.building.put(x, 10, Buildings.ROAD_FIRST)
	c.building.put(11, 11, Buildings.ROAD_FIRST + 1)
	check_eq(NS.connection_mask(c, 11, 10, NS.Family.ROAD), NS.EAST | NS.WEST | NS.SOUTH)
	NS.reshape(c, 11, 10)
	check_eq(c.building_at(11, 10), Buildings.id_of(&"road_esw"))
	check_eq(c.building_at(10, 10), Buildings.id_of(&"road_ew"), "west neighbour stays straight")
	check_eq(c.building_at(11, 11), Buildings.id_of(&"road_ns"))
	# A power line beside the road does not count as a road connection.
	c.building.put(11, 9, Buildings.POWER_LINE_FIRST + 1)
	check_eq(NS.connection_mask(c, 11, 10, NS.Family.ROAD), NS.EAST | NS.WEST | NS.SOUTH)
	# A crossing connects the road along its road axis only.
	c.building.put(13, 10, NS.CROSS_POWER_NS_ROAD_EW)
	check_eq(NS.connection_mask(c, 12, 10, NS.Family.ROAD) & NS.EAST, NS.EAST)
	check_eq(NS.connection_mask(c, 13, 9, NS.Family.ROAD) & NS.SOUTH, 0, "crossing does not open a road northward")
	check_eq(NS.connection_mask(c, 13, 9, NS.Family.POWER) & NS.SOUTH, NS.SOUTH, "but carries power northward")


func test_fixed_pieces_keep_orientation() -> void:
	var c := flat_city()
	c.terrain.put(5, 5, Terrain.SLOPE_N)
	c.building.put(5, 5, Buildings.id_of(&"road_slope_n"))
	c.building.put(6, 5, Buildings.ROAD_FIRST)
	NS.reshape(c, 5, 5)
	check_eq(c.building_at(5, 5), Buildings.id_of(&"road_slope_n"), "slope pieces are not reshaped")
	check_eq(NS.connection_mask(c, 5, 4, NS.Family.ROAD) & NS.SOUTH, NS.SOUTH, "slope connects along its axis")
	check_eq(NS.connection_mask(c, 6, 5, NS.Family.ROAD) & NS.WEST, 0, "slope does not connect sideways")
	check_eq(NS.axis_for(Buildings.id_of(&"tunnel_e"), NS.Family.ROAD), NS.AXIS_EW)
	check_eq(NS.axis_for(Buildings.id_of(&"subway_portal_n"), NS.Family.RAIL), NS.AXIS_NS)


func test_underground_codes_are_masks() -> void:
	for mask in range(1, 16):
		check_eq(NS.underground_code(NS.Family.PIPE, mask), mask)
		check_eq(NS.underground_code(NS.Family.SUBWAY, mask), mask + NS.SUBWAY_OFFSET)
		check_eq(NS.underground_mask(mask, NS.Family.PIPE), mask)
		check_eq(NS.underground_mask(mask + NS.SUBWAY_OFFSET, NS.Family.SUBWAY), mask)
		check_eq(NS.underground_mask(mask, NS.Family.SUBWAY), 0)
	check_eq(NS.underground_code(NS.Family.PIPE, 0), NS.EAST | NS.WEST, "a lone pipe is an east-west run")
	check_eq(NS.underground_code(NS.Family.PIPE, 0, NS.NORTH | NS.SOUTH), NS.NORTH | NS.SOUTH, "a lone north-south run stays")
	check_eq(NS.underground_straight(NS.Family.SUBWAY, NS.AXIS_NS), NS.SUBWAY_OFFSET + (NS.NORTH | NS.SOUTH))
	check_eq(NS.underground_mask(NS.PIPE_NS_SUBWAY_EW, NS.Family.PIPE), NS.NORTH | NS.SOUTH)
	check_eq(NS.underground_mask(NS.PIPE_NS_SUBWAY_EW, NS.Family.SUBWAY), NS.EAST | NS.WEST)
	check_eq(NS.underground_mask(NS.STATION_LINK, NS.Family.SUBWAY), 15)
	# The utility systems read the same numbering.
	if ResourceLoader.exists("res://scripts/sim/data/utility_params.gd"):
		var params: Script = load("res://scripts/sim/data/utility_params.gd")
		check_eq(int(params.get("PIPE_FIRST")), NS.PIPE_FIRST)
		check_eq(int(params.get("PIPE_LAST")), NS.PIPE_LAST)
		check_eq(int(params.get("SUBWAY_FIRST")), NS.SUBWAY_FIRST)
		check_eq(int(params.get("SUBWAY_LAST")), NS.SUBWAY_LAST)
		check_eq(int(params.get("CROSSING_PIPE_NS_UNDER_SUBWAY_EW")), NS.PIPE_NS_SUBWAY_EW)
		check_eq(int(params.get("CROSSING_PIPE_EW_UNDER_SUBWAY_NS")), NS.PIPE_EW_SUBWAY_NS)
		check_eq(int(params.get("SUBWAY_STATION_LINK")), NS.STATION_LINK)
		for mask in range(1, 16):
			check_eq(int(params.call("pipe_code", mask)), NS.underground_code(NS.Family.PIPE, mask))
			check_eq(int(params.call("subway_code", mask)), NS.underground_code(NS.Family.SUBWAY, mask))
			check_eq(int(params.call("pipe_mask", mask)), NS.underground_mask(mask, NS.Family.PIPE))
			check_eq(int(params.call("subway_mask", mask + NS.SUBWAY_OFFSET)), NS.underground_mask(mask + NS.SUBWAY_OFFSET, NS.Family.SUBWAY))
		for code in [NS.PIPE_NS_SUBWAY_EW, NS.PIPE_EW_SUBWAY_NS, NS.PIPE_NS_OVER_SUBWAY_EW, NS.PIPE_EW_OVER_SUBWAY_NS, NS.STATION_LINK]:
			check_eq(int(params.call("pipe_mask", code)), NS.underground_mask(code, NS.Family.PIPE), "pipe mask of %d" % code)
			check_eq(int(params.call("subway_mask", code)), NS.underground_mask(code, NS.Family.SUBWAY), "subway mask of %d" % code)


func test_underground_masks() -> void:
	var c := flat_city()
	c.underground.put(20, 20, NS.EAST | NS.WEST)
	c.underground.put(21, 20, NS.EAST | NS.WEST)
	c.underground.put(21, 21, NS.NORTH | NS.SOUTH)
	check_eq(NS.connection_mask(c, 21, 20, NS.Family.PIPE), NS.WEST | NS.SOUTH)
	NS.reshape(c, 21, 20)
	check_eq(c.underground.at(21, 20), NS.WEST | NS.SOUTH)
	check_eq(c.underground.at(20, 20), NS.EAST, "a dead end points at its only neighbour")
	check_eq(c.underground.at(21, 21), NS.NORTH)
	c.underground.put(22, 20, NS.PIPE_NS_SUBWAY_EW)
	check_eq(NS.connection_mask(c, 21, 20, NS.Family.PIPE) & NS.EAST, 0, "pipe crossing runs north-south")
	check_eq(NS.connection_mask(c, 23, 20, NS.Family.SUBWAY) & NS.WEST, NS.WEST, "subway crossing runs east-west")
	c.underground.put(30, 30, NS.STATION_LINK)
	check_eq(NS.connection_mask(c, 30, 31, NS.Family.SUBWAY) & NS.NORTH, NS.NORTH, "station links connect on every side")
	check(not NS.underground_in_family(NS.STATION_LINK, NS.Family.PIPE))


func test_highway_block_reshape() -> void:
	var c := flat_city()
	for bx in [10, 12, 14]:
		for dy in 2:
			for dx in 2:
				c.building.put(bx + dx, 10 + dy, NS.HIGHWAY_EW)
	for dy in 2:
		for dx in 2:
			c.building.put(14 + dx, 12 + dy, NS.HIGHWAY_NS)
	check_eq(NS.highway_block_mask(c, 12, 10), NS.EAST | NS.WEST)
	check_eq(NS.highway_block_mask(c, 14, 10), NS.WEST | NS.SOUTH)
	NS.reshape_highway_block(c, 14, 10)
	check_eq(c.building_at(14, 10), NS.HIGHWAY_CORNER_SW)
	check_eq(c.building_at(15, 11), NS.HIGHWAY_CORNER_SW)
	check_eq(c.building_at(12, 10), NS.HIGHWAY_EW)
	check_eq(NS.block_anchor(Vector2i(15, 11)), Vector2i(14, 10))


## Rail IDs are written out literally so the test does not share the key lookup.
func test_canonical_rail_roster_matches_imported_network_ids() -> void:
	var codes := [44,44,45,50,44,44,51,55,45,53,45,54,52,57,56,58]
	for mask: int in 16:
		check_eq(NS.shape_id(NS.Family.RAIL,mask),codes[mask],"canonical rail mask %d" % mask)
	for slope: int in 4:
		check_eq(NS.shape_id(NS.Family.RAIL,10,Terrain.SLOPE_W+slope),46+slope,"canonical grade")
	for code: int in range(44,63):
		check(NS.in_rail_family(code),"rail %d retains membership" % code)
		check(not NS.in_power_family(code),"rail %d is not a phantom power crossing" % code)
		check(not NS.in_road_family(code),"rail %d is not a phantom road crossing" % code)
		check(not Buildings.carries_power(code),"rail %d is not conductive" % code)
	for code: int in [46,48,59,61]: check_eq(NS.axis_for(code,NS.Family.RAIL),NS.AXIS_EW)
	for code: int in [47,49,60,62]: check_eq(NS.axis_for(code,NS.Family.RAIL),NS.AXIS_NS)
	check_eq(Buildings.id_of(&"rail_ne"),50)
	check_eq(Buildings.id_of(&"rail_slope_w"),46)
	check_eq(NS.RAIL_POWER_NS,71)
	check_eq(NS.RAIL_POWER_EW,72)
	check_eq(NS.RAIL_ROAD_NS,70)
	check_eq(NS.RAIL_ROAD_EW,69)


func test_existing_highway_corners_reshape_when_branches_change() -> void:
	for code: int in range(101,105):
		var c := flat_city()
		for anchor: Vector2i in [Vector2i(10,10),Vector2i(10,8),Vector2i(12,10),Vector2i(10,12),Vector2i(8,10)]:
			for dy: int in 2:
				for dx: int in 2: c.building.put(anchor.x+dx,anchor.y+dy,code if anchor==Vector2i(10,10) else 73)
		NS.reshape_highway_block(c,10,10)
		for dy: int in 2:
			for dx: int in 2:check_eq(c.building.at(10+dx,10+dy),105,"corner becomes junction when branches added")
		for y: int in [8,12]:
			for dy: int in 2:
				for dx: int in 2:c.building.put(10+dx,y+dy,0)
		NS.reshape_highway_block(c,10,10)
		for dy: int in 2:
			for dx: int in 2:check_eq(c.building.at(10+dx,10+dy),74,"removed branches restore straight")


func test_canonical_rail_is_not_a_driveable_crossing_or_road_upkeep() -> void:
	for code: int in range(44,63):
		check_eq(TransportParams.surface_class(code),TransportParams.SURFACE_RAIL,"plain rail routes trains only")
		check_eq(TransportParams.wear_category(code),TransportParams.RAIL,"rail uses rail wear and upkeep")
	for code: int in [69,70]:
		check_eq(TransportParams.surface_class(code),TransportParams.SURFACE_RAIL|TransportParams.SURFACE_ROAD)
		check_eq(TransportParams.wear_category(code),TransportParams.ROADS)
