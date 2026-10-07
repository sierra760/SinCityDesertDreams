# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The monthly passes classify tiles through per-id tables and walk the packed
## layers directly. These checks pin those shortcuts to the plain accessors and
## predicates they stand in for, on the roster and on a lived-in city.
extends "res://tests/test_case.gd"


func test_utility_tables_match_predicates() -> void:
	for id in Buildings.COUNT:
		check_eq(UtilityParams.conducts_power_table()[id] != 0, UtilityParams.conducts_power_building(id), "conducts power %d" % id)
		check_eq(UtilityParams.draws_power_table()[id] != 0, UtilityParams.draws_power(id), "draws power %d" % id)
		check_eq(UtilityParams.power_plant_table()[id] != 0, Buildings.is_power_plant(id), "plant %d" % id)
		check_eq(UtilityParams.conducts_water_table()[id] != 0, UtilityParams.conducts_water_building(id), "conducts water %d" % id)
		check_eq(UtilityParams.draws_water_table()[id] != 0, UtilityParams.draws_water(id), "draws water %d" % id)
		check_eq(UtilityParams.water_facility_table()[id] != 0, UtilityParams.is_water_facility(id), "facility %d" % id)
		check_eq(UtilityParams.multi_tile_table()[id] != 0, Buildings.is_multi_tile(id), "multi %d" % id)
		check_eq(int(UtilityParams.footprint_width_table()[id]), Buildings.size(id).x, "width %d" % id)
		check_eq(int(UtilityParams.footprint_height_table()[id]), Buildings.size(id).y, "height %d" % id)
	for code in 256:
		check_eq(UtilityParams.conducts_water_code_table()[code] != 0, UtilityParams.conducts_water_code(code), "code %d" % code)


func _stamp_variety(c: City) -> void:
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	c.stamp_building(20, 10, Buildings.RES_2X2_FIRST, Zones.RES_HIGH)
	c.stamp_building(30, 10, Buildings.COM_3X3_FIRST, Zones.COM_HIGH)
	c.stamp_building(40, 10, Buildings.WATER_TOWER)
	c.stamp_building(50, 10, Buildings.DESALINATION)
	c.stamp_building(60, 10, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	c.stamp_building(125, 125, Buildings.IND_3X3_FIRST, Zones.IND_HIGH)
	# Footprints broken by later changes: a corner lost, an edge lost, a
	# footprint sharing an edge with a twin of the same id.
	c.stamp_building(70, 10, Buildings.COM_3X3_FIRST, Zones.COM_HIGH)
	c.building.put(70, 10, Buildings.RUBBLE_1)
	c.zone.put(70, 10, 0)
	c.stamp_building(80, 10, Buildings.RES_2X2_FIRST, Zones.RES_HIGH)
	c.building.put(80, 11, Buildings.ABANDONED_1X1_A)
	c.zone.put(80, 11, Zones.make(Zones.RES_HIGH))
	c.stamp_building(90, 10, Buildings.IND_2X2_FIRST, Zones.IND_HIGH)
	c.stamp_building(92, 10, Buildings.IND_2X2_FIRST, Zones.IND_HIGH)
	c.stamp_building(90, 12, Buildings.IND_2X2_FIRST, Zones.IND_HIGH)


func test_anchor_tile_matches_anchor_of() -> void:
	var c := flat_city()
	_stamp_variety(c)
	var bld := c.building.data
	var zn := c.zone.data
	var anchors := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var i := y * City.WIDTH + x
			if bld[i] == Buildings.NONE:
				continue
			var expected := c.anchor_of(x, y) == Vector2i(x, y)
			check_eq(UtilityParams.is_anchor_tile(bld, zn, i), expected, "anchor at %d,%d" % [x, y])
			if expected:
				anchors += 1
	check_gt(anchors, 10)


func test_access_matches_radius_scan() -> void:
	var c := flat_city()
	c.building.put(3, 3, Buildings.ROAD_FIRST)
	c.building.put(60, 60, Buildings.HIGHWAY_FIRST)
	c.building.put(64, 60, Buildings.ONRAMP_FIRST)
	c.building.put(127, 127, Buildings.BUS_DEPOT)
	c.building.put(0, 100, Buildings.RAIL_FIRST)
	var rects: Array[Rect2i] = [
		Rect2i(0, 0, 1, 1), Rect2i(6, 6, 1, 1), Rect2i(7, 7, 1, 1), Rect2i(6, 0, 2, 2),
		Rect2i(57, 57, 3, 3), Rect2i(61, 58, 2, 2), Rect2i(66, 63, 1, 1), Rect2i(67, 63, 1, 1),
		Rect2i(124, 124, 1, 1), Rect2i(123, 123, 1, 1), Rect2i(126, 120, 2, 2),
		Rect2i(1, 97, 1, 1), Rect2i(0, 103, 1, 1),
	]
	for rect in rects:
		var r := ZoneParams.ACCESS_RADIUS
		var naive := false
		for y in range(rect.position.y - r, rect.end.y + r):
			for x in range(rect.position.x - r, rect.end.x + r):
				if ZoneParams.gives_access(c.building.at(x, y)):
					naive = true
		check_eq(ZoneSystem.has_access(c, rect), naive, "access %s" % str(rect))


func _build_town(city: City, sim: Simulation) -> void:
	var b := Builder.new(city, sim.stats, sim)
	b.apply(Tools.Kind.COAL_PLANT, Vector2i(30, 40))
	b.apply(Tools.Kind.WATER_PUMP, Vector2i(34, 43))
	b.apply(Tools.Kind.WATER_TOWER, Vector2i(34, 46))
	b.apply(Tools.Kind.ROAD, Vector2i(36, 44), Vector2i(70, 44))
	b.apply(Tools.Kind.ROAD, Vector2i(36, 50), Vector2i(70, 50))
	b.apply(Tools.Kind.ROAD, Vector2i(36, 41), Vector2i(36, 56))
	b.apply(Tools.Kind.POWER_LINE, Vector2i(34, 44), Vector2i(36, 44))
	# The 2x2 water tower blocks a drag through x35. Route around it so
	# employment zones receive power before residents need real commutes.
	var spine: Dictionary = b.apply(Tools.Kind.POWER_LINE, Vector2i(33, 44), Vector2i(33, 51))
	check(bool(spine.get("ok", false)) and spine.get("tiles", []).has(Vector2i(33, 51)), "power spine reaches its endpoint")
	b.apply(Tools.Kind.POWER_LINE, Vector2i(35, 45), Vector2i(37, 45))
	var feed: Dictionary = b.apply(Tools.Kind.POWER_LINE, Vector2i(33, 51), Vector2i(37, 51))
	check(bool(feed.get("ok", false)) and feed.get("tiles", []).has(Vector2i(37, 51)), "employment feed reaches its endpoint")
	b.apply(Tools.Kind.ZONE_RES_HIGH, Vector2i(37, 45), Vector2i(70, 49))
	b.apply(Tools.Kind.ZONE_COM_HIGH, Vector2i(37, 51), Vector2i(52, 55))
	b.apply(Tools.Kind.ZONE_IND_HIGH, Vector2i(53, 51), Vector2i(70, 55))
	b.apply(Tools.Kind.WATER_PIPE, Vector2i(35, 43), Vector2i(35, 51))
	b.apply(Tools.Kind.WATER_PIPE, Vector2i(35, 44), Vector2i(70, 44))
	b.apply(Tools.Kind.WATER_PIPE, Vector2i(35, 50), Vector2i(70, 50))
	b.apply(Tools.Kind.WATER_TREATMENT, Vector2i(72, 51))
	b.apply(Tools.Kind.POWER_LINE, Vector2i(71, 51), Vector2i(72, 51))


func _naive_unserved(c: City, draws: Callable, bit: int) -> int:
	var unserved := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var id := c.building_at(x, y)
			if not draws.call(id) or c.anchor_of(x, y) != Vector2i(x, y):
				continue
			var s := Buildings.size(id)
			var served := false
			for dy in s.y:
				for dx in s.x:
					if c.flags.has_bits(x + dx, y + dy, bit):
						served = true
			if not served:
				unserved += 1
	return unserved


func test_lived_in_city_counts_match_accessors() -> void:
	var c := flat_city(50000)
	c.founded_year = 1950
	var sim := make_simulation(c, 31)
	_build_town(c, sim)
	sim.networks_changed()
	check(c.flags.has_bits(37, 51, TileFlags.POWERED), "commercial seed zone receives power")
	check(c.flags.has_bits(53, 51, TileFlags.POWERED), "industrial seed zone receives power")
	sim.advance_days(GameClock.DAYS_PER_YEAR * 2)
	check_gt(sim.stats.total_population(), 500, "the town grew")
	var stage3 := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if Buildings.size(c.building_at(x, y)).x > 1 and Buildings.is_zone_building(c.building_at(x, y)):
				stage3 += 1
	check_gt(stage3, 0, "multi-tile lots developed")
	# Rerun the passes on the map as it stands now, so the published counts
	# describe the same map the plain recount sees.
	sim.networks_changed()
	var env: EnvironmentSystem = sim.get_system(&"environment")
	var zones: ZoneSystem = sim.get_system(&"zones")
	env.monthly(sim._ctx)
	zones.setup(sim._ctx)
	check_eq(sim.stats.unpowered_buildings, _naive_unserved(c, UtilityParams.draws_power, TileFlags.POWERED), "unpowered")
	check_eq(sim.stats.unwatered_buildings, _naive_unserved(c, UtilityParams.draws_water, TileFlags.WATERED), "unwatered")
	var developed := 0
	for by in City.HALF:
		for bx in City.HALF:
			var x := bx * 2
			var y := by * 2
			if EnvironmentSystem.is_developed_tile(c, x, y) or EnvironmentSystem.is_developed_tile(c, x + 1, y) \
					or EnvironmentSystem.is_developed_tile(c, x, y + 1) or EnvironmentSystem.is_developed_tile(c, x + 1, y + 1):
				developed += 1
	check_eq(env.developed_blocks(), developed, "developed blocks")
	var census := c.building_census()
	var units := Vector3i.ZERO
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var id := c.building_at(x, y)
			if not Buildings.is_zone_building(id) or c.anchor_of(x, y) != Vector2i(x, y):
				continue
			var family := ZoneParams.family_of(c.zone_kind_at(x, y))
			if family >= 0:
				units[family] += ZoneParams.STAGE_UNITS[ZoneParams.stage_of(id)]
	check_eq(zones.occupied_units(), units)
	check_eq(sim.stats.jobs, (units.y + units.z) * ZoneParams.PEOPLE_PER_UNIT)
	check_ge(census[Buildings.COAL_PLANT], 1)
	sim.queue_free()
