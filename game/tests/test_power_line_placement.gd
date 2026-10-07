# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const ZoneSys := preload("res://scripts/sim/zone_system.gd")
const MainScene := preload("res://scenes/main.tscn")
const Saves := preload("res://scripts/io/save_format.gd")


func _builder(funds: int = 20000) -> Builder:
	var c := flat_city(funds)
	c.founded_year = 2000
	return Builder.new(c, CityStats.new())


func test_all_standalone_line_shapes_allow_zoning() -> void:
	var b := _builder()
	for id in range(14, 29):
		var p := Vector2i(20 + id - 14, 20)
		b.city.stamp_building(p.x, p.y, id)
		b.city.set_flag(p.x, p.y, TileFlags.CONDUCTS_POWER, true)
	b.city.terrain.put(20, 21, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
	b.stats.rewards_offered[&"military_base"] = true
	for tool in [Tools.Kind.ZONE_RES_LOW, Tools.Kind.ZONE_RES_HIGH,
			Tools.Kind.ZONE_COM_LOW, Tools.Kind.ZONE_COM_HIGH,
			Tools.Kind.ZONE_IND_LOW, Tools.Kind.ZONE_IND_HIGH, Tools.Kind.AIRPORT,
			Tools.Kind.SEAPORT, Tools.Kind.REWARD_MILITARY_BASE]:
		var quote := b.preview(tool, Vector2i(20, 20), Vector2i(34, 20))
		check(quote.ok, "lines accept zone tool %d: %s" % [tool, quote.reason])
		check_eq(quote.tiles.size(), 15)
		check_eq(quote.cost, Tools.cost(tool) * 15)
		var result := b.apply(tool, Vector2i(20, 20), Vector2i(34, 20))
		check(result.applied)
		check_eq(result.cost, quote.cost)
		for x in range(20, 35):
			check_eq(b.city.zone_kind_at(x, 20), Tools.zone_kind(tool))
			check(NetworkShapes.is_plain_power(b.city.building_at(x, 20)), "line remains")
			check(b.city.conducts_power(x, 20))


func test_zone_rezone_and_dezone_keep_live_lines_and_price_only_changes() -> void:
	var b := _builder()
	b.apply(Tools.Kind.POWER_LINE, Vector2i(20, 20), Vector2i(24, 20))
	var c := b.city
	var lines := c.building.data.duplicate()
	var flags := c.flags.data.duplicate()
	var funds := c.funds
	var quote := b.preview(Tools.Kind.ZONE_RES_LOW, Vector2i(20, 20), Vector2i(24, 20))
	check(quote.ok)
	check_eq(quote.cost, 25)
	check_eq(c.funds, funds)
	check_eq(c.zone_kind_at(22, 20), Zones.NONE, "preview is read only")
	var result := b.apply(Tools.Kind.ZONE_RES_LOW, Vector2i(20, 20), Vector2i(24, 20))
	check(result.applied)
	check_eq(c.funds, funds - 25)
	check_eq(c.building.data, lines)
	check_eq(c.flags.data, flags)
	check(not b.apply(Tools.Kind.ZONE_RES_LOW, Vector2i(20, 20), Vector2i(24, 20)).applied)
	check_eq(c.funds, funds - 25, "same zone costs nothing")
	var dense := b.apply(Tools.Kind.ZONE_RES_HIGH, Vector2i(20, 20), Vector2i(24, 20))
	check(dense.applied)
	check_eq(dense.cost, 50)
	var dezone := b.apply(Tools.Kind.DEZONE, Vector2i(20, 20), Vector2i(24, 20))
	check(dezone.applied)
	check_eq(dezone.cost, 5)
	check_eq(c.funds, funds - 80)
	check_eq(c.zone_kind_at(22, 20), Zones.NONE)
	check_eq(c.building.data, lines)
	check_eq(c.flags.data, flags)


func test_mixed_zone_drag_skips_slopes_water_crossings_and_military() -> void:
	var b := _builder()
	var c := b.city
	for x in range(20, 27):
		c.stamp_building(x, 20, Buildings.POWER_LINE_FIRST)
	c.terrain.put(21, 20, Terrain.SLOPE_N)
	c.terrain.put(22, 20, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
	c.building.put(23, 20, NetworkShapes.CROSS_POWER_NS_ROAD_EW)
	c.building.put(24, 20, NetworkShapes.CROSS_POWER_NS_RAIL_EW)
	c.zone.put(25, 20, Zones.make(Zones.MILITARY))
	var quote := b.preview(Tools.Kind.ZONE_COM_LOW, Vector2i(20, 20), Vector2i(26, 20))
	check(quote.ok)
	check_eq(quote.tiles, [Vector2i(20, 20), Vector2i(26, 20)] as Array[Vector2i])
	check_eq(quote.cost, 10)
	var result := b.apply(Tools.Kind.ZONE_COM_LOW, Vector2i(20, 20), Vector2i(26, 20))
	check(result.applied)
	check_eq(c.funds, 19990)
	for x in range(21, 25):
		check_eq(c.zone_kind_at(x, 20), Zones.NONE, "invalid tile %d unchanged" % x)
	check_eq(c.zone_kind_at(25, 20), Zones.MILITARY)


func test_building_replaces_full_line_footprint_and_preserves_underground() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.POWER_LINE, Vector2i(19, 21), Vector2i(24, 21))
	b.apply(Tools.Kind.WATER_PIPE, Vector2i(19, 21), Vector2i(24, 21))
	var under := c.underground.data.duplicate()
	var before := c.building.data.duplicate()
	var funds := c.funds
	var quote := b.preview(Tools.Kind.POLICE, Vector2i(20, 20))
	check(quote.ok, quote.reason)
	check_eq(quote.cost, 500)
	check_eq(quote.tiles.size(), 9)
	check_eq(c.building.data, before)
	check_eq(c.funds, funds)
	var result := b.apply(Tools.Kind.POLICE, Vector2i(20, 20))
	check(result.applied, result.reason)
	check_eq(c.funds, funds - 500, "no extra demolition charge")
	for y in range(20, 23):
		for x in range(20, 23):
			check_eq(c.building_at(x, y), Buildings.POLICE_STATION)
			check_eq(c.anchor_of(x, y), Vector2i(20, 20))
			check(c.conducts_power(x, y))
	check(NetworkShapes.is_plain_power(c.building_at(19, 21)))
	check(NetworkShapes.is_plain_power(c.building_at(23, 21)))
	check(NetworkShapes.is_plain_power(c.building_at(24, 21)))
	check_eq(c.underground.data, under)
	check_eq(c.facility(Vector2i(20, 20)).get("key"), &"police_station")


func test_nonconductive_park_replaces_line_and_reshapes_neighbors() -> void:
	var b := _builder()
	b.apply(Tools.Kind.POWER_LINE, Vector2i(20, 19), Vector2i(20, 21))
	b.apply(Tools.Kind.POWER_LINE, Vector2i(20, 20), Vector2i(22, 20))
	check_eq(b.city.building_at(20, 20), Buildings.id_of(&"power_nes"))
	var result := b.apply(Tools.Kind.SMALL_PARK, Vector2i(21, 20))
	check(result.applied, result.reason)
	check_eq(b.city.building_at(21, 20), Buildings.SMALL_PARK)
	check(not b.city.conducts_power(21, 20))
	check_eq(b.city.building_at(20, 20), Buildings.id_of(&"power_ns"))


func test_blocked_or_unaffordable_building_leaves_all_lines_unchanged() -> void:
	for obstruction in [Buildings.ROAD_FIRST, NetworkShapes.CROSS_POWER_NS_ROAD_EW,
			NetworkShapes.CROSS_POWER_NS_RAIL_EW, Buildings.id_of(&"power_elevated"),
			Buildings.RES_1X1_FIRST]:
		var b := _builder()
		b.city.stamp_building(20, 20, Buildings.POWER_LINE_FIRST)
		b.city.stamp_building(22, 22, obstruction)
		var before := b.city.building.data.duplicate()
		var result := b.apply(Tools.Kind.POLICE, Vector2i(20, 20))
		check(not result.applied, "obstruction %d remains protected" % obstruction)
		check_eq(b.city.building.data, before)
		check_eq(b.city.funds, 20000)
	var poor := _builder(499)
	poor.city.stamp_building(20, 20, Buildings.POWER_LINE_FIRST)
	check(not poor.apply(Tools.Kind.POLICE, Vector2i(20, 20)).applied)
	check_eq(poor.city.funds, 499)
	check_eq(poor.city.building_at(20, 20), Buildings.POWER_LINE_FIRST)
	for constraint in ["slope", "height", "water", "landmark", "military"]:
		var b := _builder()
		b.city.stamp_building(20, 20, Buildings.POWER_LINE_FIRST)
		match constraint:
			"slope": b.city.terrain.put(22, 22, Terrain.SLOPE_N)
			"height": b.city.set_heights(22, 22, 5)
			"water": b.city.terrain.put(22, 22, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
			"landmark": b.city.set_flag(20, 20, TileFlags.LANDMARK, true)
			"military": b.city.zone.put(20, 20, Zones.make(Zones.MILITARY))
		check(not b.apply(Tools.Kind.POLICE, Vector2i(20, 20)).applied, constraint)
		check_eq(b.city.building_at(20, 20), Buildings.POWER_LINE_FIRST)
		check_eq(b.city.funds, 20000)


func test_shore_and_waterfall_buildings_replace_standalone_lines() -> void:
	var b := _builder()
	var c := b.city
	c.stamp_building(20, 20, Buildings.POWER_LINE_FIRST)
	c.terrain.put(22, 22, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
	var marina := b.apply(Tools.Kind.MARINA, Vector2i(20, 20))
	check(marina.applied, marina.reason)
	check_eq(c.building_at(20, 20), Buildings.MARINA)
	c.terrain.put(30, 30, Terrain.WATERFALL)
	c.stamp_building(30, 30, Buildings.POWER_LINE_FIRST)
	var dam := b.apply(Tools.Kind.HYDRO_PLANT, Vector2i(30, 30))
	check(dam.applied, dam.reason)
	check_eq(c.building_at(30, 30), Buildings.HYDRO_PLANT_A)


func test_live_power_network_stays_connected_through_replacement_building() -> void:
	var b := _builder()
	var c := b.city
	c.stamp_building(10, 20, Buildings.COAL_PLANT)
	b.apply(Tools.Kind.POWER_LINE, Vector2i(14, 21), Vector2i(24, 21))
	c.stamp_building(25, 21, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	var sim := make_simulation(c)
	b.sim = sim
	check(c.is_powered(25, 21))
	var result := b.apply(Tools.Kind.POLICE, Vector2i(20, 20))
	check(result.applied, result.reason)
	check(c.is_powered(20, 20), "new facility gets power immediately")
	check(c.is_powered(25, 21), "downstream house keeps power")
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()


func test_zoned_lines_develop_into_buildings() -> void:
	var b := _builder()
	var c := b.city
	b.apply(Tools.Kind.ROAD, Vector2i(19, 21), Vector2i(24, 21))
	b.apply(Tools.Kind.POWER_LINE, Vector2i(20, 20), Vector2i(23, 20))
	var zone := b.apply(Tools.Kind.ZONE_RES_LOW, Vector2i(20, 20), Vector2i(23, 20))
	check(zone.applied, zone.reason)
	for x in range(20, 24):
		c.set_flag(x, 20, TileFlags.POWERED | TileFlags.WATERED, true)
	var ctx := make_context(c)
	ctx.stats = b.stats
	var zones := ZoneSys.new()
	zones.setup(ctx)
	for _month in 24:
		zones.monthly(ctx, 0)
		zones.monthly(ctx, 1)
	var developed := 0
	for x in range(20, 24):
		if Buildings.is_zone_building(c.building_at(x, 20)):
			developed += 1
		check_eq(c.zone_kind_at(x, 20), Zones.RES_LOW)
		check(c.conducts_power(x, 20))
	check_gt(developed, 0, "zoned line tiles grow into homes")


func test_subway_station_replaces_line_without_admitting_surface_portals() -> void:
	var b := _builder()
	b.apply(Tools.Kind.POWER_LINE, Vector2i(20, 20), Vector2i(22, 20))
	b.apply(Tools.Kind.RAIL, Vector2i(21, 19))
	check(not b.preview(Tools.Kind.SUBWAY_PORTAL, Vector2i(21, 20)).ok,
		"portal still refuses an occupied surface tile")
	var result := b.apply(Tools.Kind.SUBWAY_STATION, Vector2i(21, 20))
	check(result.applied, result.reason)
	check_eq(b.city.building_at(21, 20), Buildings.SUBWAY_STATION)
	check_eq(b.city.underground.at(21, 20), NetworkShapes.STATION_LINK)


func test_all_standalone_shapes_can_be_replaced_by_a_one_tile_building() -> void:
	for id in range(14, 29):
		var b := _builder()
		b.city.stamp_building(20, 20, id)
		var result := b.apply(Tools.Kind.WIND_PLANT, Vector2i(20, 20))
		check(result.applied, "replace line %d: %s" % [id, result.reason])
		check_eq(b.city.building_at(20, 20), Buildings.WIND_PLANT)


func test_zones_and_replacement_buildings_round_trip_in_existing_save_format() -> void:
	var b := _builder()
	b.apply(Tools.Kind.POWER_LINE, Vector2i(20, 20), Vector2i(24, 20))
	check(b.apply(Tools.Kind.ZONE_RES_LOW, Vector2i(20, 20), Vector2i(24, 20)).applied)
	check(b.apply(Tools.Kind.POLICE, Vector2i(20, 20)).applied)
	var loaded := Saves.decode_city(Saves.encode_city(b.city))
	check_eq(loaded.get("error", ""), "")
	var restored: City = loaded.get("city")
	check(restored != null)
	if restored == null:
		return
	check_eq(restored.building.data, b.city.building.data)
	check_eq(restored.zone.data, b.city.zone.data)
	check_eq(restored.flags.data, b.city.flags.data)
	check_eq(restored.funds, b.city.funds)
	check_eq(restored.facilities, b.city.facilities)
	check_eq(restored.zone_kind_at(23, 20), Zones.RES_LOW)
	check(NetworkShapes.is_plain_power(restored.building_at(23, 20)))
	check_eq(restored.building_at(21, 20), Buildings.POLICE_STATION)


func test_main_selected_tools_zone_then_replace_power_lines() -> void:
	var host: GameHost = MainScene.instantiate()
	root.add_child(host)
	var c := flat_city()
	c.founded_year = 2000
	host.start_new_city({"name": "Power Placement", "seed": 9, "founded_year": 2000}, c)
	host.found_city()
	host.select_tool(Tools.Kind.POWER_LINE)
	check(host.handle_drag(Vector2i(20, 20), Vector2i(24, 20)).applied)
	var funds := c.funds
	host.select_tool(Tools.Kind.ZONE_RES_LOW)
	check(host.handle_drag(Vector2i(20, 20), Vector2i(24, 20)).applied)
	check_eq(c.funds, funds - 25)
	check_eq(c.zone_kind_at(21, 20), Zones.RES_LOW)
	check(NetworkShapes.is_plain_power(c.building_at(21, 20)))
	host.select_tool(Tools.Kind.POLICE)
	var quote := host.builder.preview(Tools.Kind.POLICE, Vector2i(20, 20))
	check(quote.ok, "selected building preview accepts lines")
	check(host.handle_drag(Vector2i(20, 20), Vector2i(20, 20)).applied)
	check_eq(c.building_at(21, 20), Buildings.POLICE_STATION)
	check_eq(c.funds, funds - 525)
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	root.remove_child(host)
	host.free()
