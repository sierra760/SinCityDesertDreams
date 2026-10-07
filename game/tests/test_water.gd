# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const WaterSystemScript := preload("res://scripts/sim/water_system.gd")
const UtilityParams := preload("res://scripts/sim/data/utility_params.gd")

const HOUSE := Buildings.RES_1X1_FIRST
const WATER := Terrain.FLAT | Terrain.SURFACE


func make_ctx(c: City) -> SimContext:
	var ctx := make_context(c)
	ctx.clock.founded_year = c.founded_year
	ctx.clock.day = c.day
	return ctx


func make_water() -> WaterSystemScript:
	var s: WaterSystemScript = WaterSystemScript.new()
	return s


## Straight pipe run between two tiles (inclusive).
func pipe(c: City, from: Vector2i, to: Vector2i) -> void:
	var p := from
	var step := (to - from).sign()
	while true:
		var mask := 0
		if step.x != 0:
			mask = UtilityParams.EW_MASK
		else:
			mask = UtilityParams.NS_MASK
		c.underground.put(p.x, p.y, UtilityParams.pipe_code(mask))
		if p == to:
			break
		p += step


## Power a tile the way the power pass would.
func powered(c: City, x: int, y: int, w: int = 1, h: int = 1) -> void:
	for dy in h:
		for dx in w:
			c.set_flag(x + dx, y + dy, TileFlags.POWERED, true)


func fresh_lake(c: City, x: int, y: int, w: int, h: int, salt: bool = false) -> void:
	for dy in h:
		for dx in w:
			c.terrain.put(x + dx, y + dy, WATER)
			c.set_flag(x + dx, y + dy, TileFlags.SALT_WATER, salt)


func news_kinds(ctx: SimContext) -> Array:
	var out: Array = []
	for n in ctx.events.news:
		out.append(n.kind)
	return out


func test_underground_code_table() -> void:
	check_eq(UtilityParams.pipe_code(UtilityParams.NS_MASK), 5)
	check_eq(UtilityParams.pipe_mask(5), UtilityParams.NS_MASK)
	check_eq(UtilityParams.subway_code(UtilityParams.EW_MASK), 25)
	check_eq(UtilityParams.subway_mask(25), UtilityParams.EW_MASK)
	check(UtilityParams.is_pipe(15))
	check(not UtilityParams.is_pipe(16))
	check(UtilityParams.is_subway(16))
	check(UtilityParams.is_subway(30))
	check(not UtilityParams.is_pipe(30))
	for code in range(UtilityParams.CROSSING_FIRST, UtilityParams.CROSSING_LAST + 1):
		check(UtilityParams.conducts_water_code(code), "crossing %d carries water" % code)
		check(UtilityParams.is_subway(code), "crossing %d carries subway" % code)
		check_ne(UtilityParams.pipe_mask(code), 0)
		check_ne(UtilityParams.subway_mask(code), 0)
	check(not UtilityParams.conducts_water_code(UtilityParams.SUBWAY_STATION_LINK))
	check(UtilityParams.is_subway(UtilityParams.SUBWAY_STATION_LINK))
	check(not UtilityParams.conducts_water_code(0))


func test_powered_pump_waters_through_pipes() -> void:
	var c := flat_city()
	c.sea_level = 4
	c.stamp_building(10, 10, Buildings.WATER_PUMP)
	powered(c, 10, 10)
	pipe(c, Vector2i(11, 10), Vector2i(15, 10))
	c.stamp_building(16, 10, HOUSE)
	c.stamp_building(30, 30, HOUSE)
	var ctx := make_ctx(c)
	var water := make_water()
	water.setup(ctx)
	check(c.conducts_water(12, 10), "pipe conducts")
	check(c.conducts_water(16, 10), "house conducts")
	check(not c.conducts_water(20, 20), "open ground does not")
	check(c.is_watered(16, 10), "house at the end of the pipe is watered")
	check(c.is_watered(12, 10), "pipe is wet")
	check(c.is_watered(10, 10), "pump tile watered")
	check(not c.is_watered(30, 30))
	check_eq(ctx.stats.water_capacity, 27, "water table 4 and default rain")
	check_eq(ctx.stats.water_demand, 2)
	check_eq(ctx.stats.unwatered_buildings, 1)
	check_eq(water.consumed(), 1)


func test_unpowered_pump_gives_nothing() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.WATER_PUMP)
	c.stamp_building(11, 10, HOUSE)
	var ctx := make_ctx(c)
	make_water().setup(ctx)
	check_eq(ctx.stats.water_capacity, 0)
	check(not c.is_watered(11, 10))
	check_eq(ctx.stats.unwatered_buildings, 1)


func test_fresh_water_boosts_pump_and_salt_needs_desalination() -> void:
	var c := flat_city()
	c.sea_level = 4
	fresh_lake(c, 9, 9, 3, 3)
	c.terrain.put(10, 10, Terrain.FLAT)   # the pump sits on an island
	c.stamp_building(10, 10, Buildings.WATER_PUMP)
	powered(c, 10, 10)
	var ctx := make_ctx(c)
	var water := make_water()
	water.setup(ctx)
	check_eq(ctx.stats.water_capacity, 27 + 8 * 10, "eight fresh neighbours")
	fresh_lake(c, 9, 9, 3, 3, true)
	c.terrain.put(10, 10, Terrain.FLAT)
	water.monthly(ctx)
	check_eq(ctx.stats.water_capacity, 27, "salt water gives a pump nothing")
	c.stamp_building(40, 40, Buildings.DESALINATION)
	powered(c, 40, 40, 3, 3)
	fresh_lake(c, 39, 39, 5, 1, true)   # five salt tiles along the north edge
	water.monthly(ctx)
	check_eq(ctx.stats.water_capacity, 27 + 5 * 20, "desalination draws on salt water")
	check(c.is_watered(41, 41), "desalination tiles are wet")


## A powered pump with fresh water on seven sides; the east side stays dry
## for a pipe.
func island_pump(c: City, x: int, y: int) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx == 0 and dy == 0) or (dx == 1 and dy == 0):
				continue
			c.terrain.put(x + dx, y + dy, WATER)
	c.stamp_building(x, y, Buildings.WATER_PUMP)
	powered(c, x, y)


func test_tower_charges_from_surplus_and_covers_an_outage() -> void:
	var c := flat_city()
	c.sea_level = 10
	island_pump(c, 10, 10)   # 50 + 7 + 70 = 127 units
	island_pump(c, 10, 14)
	pipe(c, Vector2i(11, 10), Vector2i(20, 10))
	pipe(c, Vector2i(11, 14), Vector2i(20, 14))
	pipe(c, Vector2i(20, 11), Vector2i(20, 13))
	c.stamp_building(21, 10, Buildings.WATER_TOWER)
	powered(c, 21, 10, 2, 2)
	for x in range(21, 41):
		for y in range(14, 19):
			c.stamp_building(x, y, HOUSE)   # 100 consumer tiles
	var ctx := make_ctx(c)
	var water := make_water()
	water.setup(ctx)
	check_eq(ctx.stats.water_capacity, 254, "two pumps")
	check_eq(ctx.stats.water_demand, 100)
	check_eq(ctx.stats.water_storage_capacity, 400)
	check_eq(ctx.stats.water_stored, 200, "surplus 154 rounds to two tower tiles")
	check_eq(ctx.stats.unwatered_buildings, 0)
	water.monthly(ctx)
	check_eq(ctx.stats.water_capacity, 454, "released storage counts as capacity")
	check_eq(ctx.stats.water_stored, 400, "tower fills up")
	water.monthly(ctx)
	check_eq(ctx.stats.water_stored, 400)
	check_eq(c.facility(Vector2i(21, 10)).get("stored"), 400)
	# Pumps lose power: the tower carries the district for four months.
	c.set_flag(10, 10, TileFlags.POWERED, false)
	c.set_flag(10, 14, TileFlags.POWERED, false)
	var expected_stored := [300, 200, 100, 0]
	for stored in expected_stored:
		water.monthly(ctx)
		check_eq(ctx.stats.unwatered_buildings, 0, "houses still served")
		check_eq(ctx.stats.water_stored, stored)
	check(not water.is_shortage(), "storage covered the load, no network was short")
	water.monthly(ctx)
	check_eq(ctx.stats.unwatered_buildings, 100, "tower empty, district dry")
	check_eq(ctx.stats.water_capacity, 0)
	# Power returns: the pumps serve the district and the tower refills.
	powered(c, 10, 10)
	powered(c, 10, 14)
	water.monthly(ctx)
	check_eq(ctx.stats.unwatered_buildings, 0)
	check_eq(ctx.stats.water_stored, 200)


func test_short_network_dries_farthest_consumers() -> void:
	var c := flat_city()
	c.sea_level = 0
	c.stamp_building(10, 10, Buildings.WATER_PUMP)   # 7 units from rain alone
	powered(c, 10, 10)
	for x in range(11, 21):
		c.stamp_building(x, 10, HOUSE)
	var ctx := make_ctx(c)
	var water := make_water()
	water.setup(ctx)
	check_eq(ctx.stats.water_capacity, 7)
	check(c.is_watered(11, 10))
	check(c.is_watered(17, 10))
	check(not c.is_watered(18, 10))
	check_eq(ctx.stats.unwatered_buildings, 3)
	check(water.is_shortage())
	check(&"water_shortage" in news_kinds(ctx), "shortage reported once")
	check_eq(water.usage_percent(), 100)
	ctx.events.clear()
	water.monthly(ctx)
	check(not (&"water_shortage" in news_kinds(ctx)), "no repeat while still short")
	c.sea_level = 4
	water.monthly(ctx)
	check(not water.is_shortage(), "higher water table covers the street")
	check(&"water_restored" in news_kinds(ctx))


func test_treatment_covers_consumption() -> void:
	var c := flat_city()
	c.sea_level = 4
	c.stamp_building(10, 10, Buildings.WATER_PUMP)
	powered(c, 10, 10)
	c.stamp_building(11, 10, HOUSE)
	var ctx := make_ctx(c)
	var water := make_water()
	water.setup(ctx)
	check(not water.treatment_adequate(), "no plant, some consumption")
	c.stamp_building(20, 20, Buildings.WATER_TREATMENT)
	water.monthly(ctx)
	check(water.treatment_adequate())
	c.clear_footprint(11, 10)
	c.clear_footprint(20, 20)
	water.monthly(ctx)
	check(water.treatment_adequate(), "nothing consumed is always treated")


func test_water_facility_records() -> void:
	var c := flat_city()
	c.sea_level = 4
	c.stamp_building(10, 10, Buildings.WATER_PUMP)
	powered(c, 10, 10)
	c.stamp_building(20, 20, Buildings.WATER_TOWER)
	var ctx := make_ctx(c)
	var water := make_water()
	water.setup(ctx)
	check_eq(c.facility(Vector2i(10, 10)).get("key"), &"water_pump")
	check_eq(c.facility(Vector2i(10, 10)).get("output"), 27)
	check_eq(c.facility(Vector2i(20, 20)).get("key"), &"water_tower")
	var summary := water.network_summary()
	check_eq(summary.facilities.size(), 2)
	c.clear_footprint(20, 20)
	c.add_facility(Vector2i(20, 20), {"key": &"water_tower", "built_day": 0})
	c.add_facility(Vector2i(50, 50), {"key": &"school", "built_day": 0})
	water.monthly(ctx)
	check(c.facility(Vector2i(20, 20)).is_empty(), "stale tower record dropped")
	check(not c.facility(Vector2i(50, 50)).is_empty(), "other systems' records untouched")


func test_networks_changed_maintains_conduction_flags() -> void:
	var c := flat_city()
	c.underground.put(5, 5, UtilityParams.pipe_code(UtilityParams.EW_MASK))
	c.underground.put(6, 5, UtilityParams.subway_code(UtilityParams.EW_MASK))
	c.underground.put(7, 5, UtilityParams.CROSSING_PIPE_EW_UNDER_SUBWAY_NS)
	c.building.put(8, 5, Buildings.POWER_LINE_FIRST)
	c.building.put(9, 5, HOUSE)
	var ctx := make_ctx(c)
	var water := make_water()
	water.networks_changed(ctx, Rect2i(5, 5, 5, 1))
	check(c.conducts_water(5, 5), "pipe")
	check(not c.conducts_water(6, 5), "subway alone")
	check(c.conducts_water(7, 5), "crossing")
	check(not c.conducts_water(8, 5), "power line")
	check(c.conducts_water(9, 5), "house")
	c.underground.put(5, 5, 0)
	water.networks_changed(ctx, Rect2i(5, 5, 1, 1))
	check(not c.conducts_water(5, 5), "flag cleared after pipe removal")


func test_save_load_round_trip() -> void:
	var c := flat_city()
	c.sea_level = 0
	c.stamp_building(10, 10, Buildings.WATER_PUMP)
	powered(c, 10, 10)
	for x in range(11, 21):
		c.stamp_building(x, 10, HOUSE)
	var ctx := make_ctx(c)
	var water := make_water()
	water.setup(ctx)
	check(water.is_shortage())
	check(not water.treatment_adequate())
	var back: Dictionary = JSON.parse_string(JSON.stringify(water.save()))
	var other := make_water()
	other.load(back)
	check(other.is_shortage())
	check(not other.treatment_adequate())
	check_eq(other.consumed(), water.consumed())


func test_runs_inside_simulation_on_day_three() -> void:
	var c := flat_city()
	c.sea_level = 4
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	c.stamp_building(14, 10, Buildings.WATER_PUMP)
	c.stamp_building(15, 10, HOUSE)
	var sim := make_simulation(c)
	check(sim.get_system(&"water") != null, "registered under its key")
	sim.stats.water_capacity = 0
	sim.advance_days(3)
	check_gt(sim.stats.water_capacity, 0, "monthly job on day 3 after power on day 1")
	check(c.is_watered(15, 10))
	root.remove_child(sim)
	sim.free()
