# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Construction recomputes who is served from the month's established supply:
## it draws no weather, leaves the random stream and the towers alone, and
## only the scheduled pass moves any of them.
extends "res://tests/test_case.gd"

const WaterSystemScript := preload("res://scripts/sim/water_system.gd")
const PowerSystemScript := preload("res://scripts/sim/power_system.gd")
const UtilityParams := preload("res://scripts/sim/data/utility_params.gd")

const HOUSE := Buildings.RES_1X1_FIRST
const WATER := Terrain.FLAT | Terrain.SURFACE
const EVERYWHERE := Rect2i(0, 0, City.WIDTH, City.HEIGHT)


func make_ctx(c: City) -> SimContext:
	var ctx := make_context(c)
	ctx.clock.founded_year = c.founded_year
	ctx.clock.day = c.day
	return ctx


func powered(c: City, x: int, y: int, w: int = 1, h: int = 1) -> void:
	for dy in h:
		for dx in w:
			c.set_flag(x + dx, y + dy, TileFlags.POWERED, true)


func pipe(c: City, from: Vector2i, to: Vector2i) -> void:
	var p := from
	var step := (to - from).sign()
	while true:
		c.underground.put(p.x, p.y, UtilityParams.pipe_code(UtilityParams.EW_MASK if step.x != 0 else UtilityParams.NS_MASK))
		if p == to:
			break
		p += step


func island_pump(c: City, x: int, y: int) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if (dx == 0 and dy == 0) or (dx == 1 and dy == 0):
				continue
			c.terrain.put(x + dx, y + dy, WATER)
	c.stamp_building(x, y, Buildings.WATER_PUMP)
	powered(c, x, y)


## Two pumps, a four-tile tower and 800 houses on one network.
func water_district() -> City:
	var c := flat_city()
	c.sea_level = 10
	island_pump(c, 10, 10)
	island_pump(c, 10, 14)
	pipe(c, Vector2i(11, 10), Vector2i(20, 10))
	pipe(c, Vector2i(11, 14), Vector2i(20, 14))
	pipe(c, Vector2i(20, 11), Vector2i(20, 13))
	c.stamp_building(21, 10, Buildings.WATER_TOWER)
	powered(c, 21, 10, 2, 2)
	for x in range(21, 61):
		for y in range(14, 34):
			c.stamp_building(x, y, HOUSE)
	return c


func test_unrelated_builds_leave_water_towers_alone_in_a_dry_month() -> void:
	var c := water_district()
	var ctx := make_ctx(c)
	var water: WaterSystemScript = WaterSystemScript.new()
	water.setup(ctx)
	water.monthly(ctx)
	check_eq(ctx.stats.water_stored, 3200, "tower full")
	# The pumps lose power: the tower carries the district this month.
	c.set_flag(10, 10, TileFlags.POWERED, false)
	c.set_flag(10, 14, TileFlags.POWERED, false)
	water.monthly(ctx)
	check_eq(ctx.stats.water_stored, 2400)
	check_eq(ctx.stats.unwatered_buildings, 0)
	ctx.events.clear()
	var rng_state := ctx.rng.state()
	var flags := c.flags.data.duplicate()
	for n in 5:
		c.stamp_building(100 + n, 100, Buildings.ROAD_FIRST)
		water.networks_changed(ctx, Rect2i(99 + n, 99, 3, 3))
		check_eq(ctx.stats.water_stored, 2400, "a road elsewhere does not drain the tower")
		check_eq(ctx.stats.unwatered_buildings, 0, "the district is still served")
	check_eq(c.facility(Vector2i(21, 10)).get("stored"), 2400)
	check_eq(ctx.rng.state(), rng_state, "no random draw")
	check_eq(ctx.events.news.size(), 0, "no news")
	check(c.flags.data == flags, "service flags unchanged")
	check(not water.is_shortage())
	# The scheduled pass still spends the tower.
	water.monthly(ctx)
	check_eq(ctx.stats.water_stored, 1600)


func test_unrelated_builds_do_not_refill_towers_from_surplus() -> void:
	var c := water_district()
	var ctx := make_ctx(c)
	var water: WaterSystemScript = WaterSystemScript.new()
	water.setup(ctx)
	check_eq(ctx.stats.water_stored, 1600, "half charged by the first pass")
	for n in 3:
		c.stamp_building(100 + n, 100, Buildings.ROAD_FIRST)
		water.networks_changed(ctx, Rect2i(99 + n, 99, 3, 3))
		check_eq(ctx.stats.water_stored, 1600, "a click does not refill the tower")
	water.monthly(ctx)
	check_eq(ctx.stats.water_stored, 3200, "the scheduled pass does")


func test_new_pump_and_new_connection_take_effect_at_once() -> void:
	var c := flat_city()
	c.sea_level = 4
	c.stamp_building(10, 10, Buildings.WATER_PUMP)
	powered(c, 10, 10)
	c.stamp_building(11, 10, HOUSE)
	c.stamp_building(30, 30, HOUSE)
	var ctx := make_ctx(c)
	var water: WaterSystemScript = WaterSystemScript.new()
	water.setup(ctx)
	check_eq(ctx.stats.water_capacity, 216)
	check(not c.is_watered(30, 30))
	var rng_state := ctx.rng.state()
	c.stamp_building(29, 30, Buildings.WATER_PUMP)
	powered(c, 29, 30)
	water.networks_changed(ctx, Rect2i(28, 29, 3, 3))
	check_eq(ctx.stats.water_capacity, 432, "the new pump yields under this month's rain")
	check_eq(c.facility(Vector2i(29, 30)).get("output"), 216)
	check(c.is_watered(30, 30), "and serves its neighbour")
	# A pump that was dark at the scheduled pass yields once it gets power.
	c.stamp_building(50, 50, Buildings.WATER_PUMP)
	water.networks_changed(ctx, Rect2i(49, 49, 3, 3))
	check_eq(ctx.stats.water_capacity, 432, "no power, no water")
	powered(c, 50, 50)
	water.networks_changed(ctx, Rect2i(49, 49, 3, 3))
	check_eq(ctx.stats.water_capacity, 648)
	# Removing a pump takes its capacity away at once.
	c.clear_footprint(29, 30)
	water.networks_changed(ctx, Rect2i(28, 29, 3, 3))
	check_eq(ctx.stats.water_capacity, 432)
	check(not c.is_watered(30, 30))
	check(c.facility(Vector2i(29, 30)).is_empty(), "stale record dropped")
	check_eq(ctx.rng.state(), rng_state, "no random draw")


func test_builds_do_not_redraw_wind_and_sun() -> void:
	var c := flat_city(20000, 20)
	c.stamp_building(10, 10, Buildings.WIND_PLANT)
	c.stamp_building(20, 10, Buildings.SOLAR_PLANT)
	c.stamp_building(11, 10, HOUSE)
	var ctx := make_ctx(c)
	var power: PowerSystemScript = PowerSystemScript.new()
	power.setup(ctx)
	var after_setup := ctx.rng.state()
	power.monthly(ctx)
	check_ne(ctx.rng.state(), after_setup, "the scheduled pass draws the weather")
	var rng_state := ctx.rng.state()
	var capacity := ctx.stats.power_capacity
	var wind := power.plant_capacity(Vector2i(10, 10))
	var sun := power.plant_capacity(Vector2i(20, 10))
	ctx.events.clear()
	for n in 8:
		c.stamp_building(100 + n, 100, Buildings.ROAD_FIRST)
		power.networks_changed(ctx, Rect2i(99 + n, 99, 3, 3))
		check_eq(ctx.stats.power_capacity, capacity, "capacity holds for the month")
	check_eq(power.plant_capacity(Vector2i(10, 10)), wind)
	check_eq(power.plant_capacity(Vector2i(20, 10)), sun)
	check_eq(ctx.rng.state(), rng_state, "no random draw")
	check_eq(ctx.events.news.size(), 0, "no news")
	check(c.is_powered(11, 10))


func test_new_plants_generate_at_once_without_a_draw() -> void:
	var c := flat_city(20000, 20)
	c.stamp_building(10, 10, Buildings.WIND_PLANT)
	var ctx := make_ctx(c)
	var power: PowerSystemScript = PowerSystemScript.new()
	power.setup(ctx)
	var rng_state := ctx.rng.state()
	var capacity := ctx.stats.power_capacity
	c.stamp_building(30, 30, Buildings.COAL_PLANT)
	c.stamp_building(34, 30, HOUSE)
	power.networks_changed(ctx, Rect2i(29, 29, 7, 6))
	check_eq(ctx.stats.power_capacity, capacity + 704, "a coal plant adds its output at once")
	check(c.is_powered(34, 30))
	c.stamp_building(50, 50, Buildings.WIND_PLANT)
	c.stamp_building(60, 50, Buildings.SOLAR_PLANT)
	power.networks_changed(ctx, Rect2i(49, 49, 20, 6))
	# Ground 20, wind 10: the typical gust is 0 of 0..1. Rain 15: 16 tiles of 5 + 0..7.
	check_eq(power.plant_capacity(Vector2i(50, 50)), 10, "wind at this month's typical output")
	check_eq(power.plant_capacity(Vector2i(60, 50)), 16 * 5 + 16 * 7 / 2, "sun at this month's typical output")
	check_eq(ctx.rng.state(), rng_state, "no random draw")
	# Removing a plant takes its capacity away at once.
	c.clear_footprint(30, 30)
	power.networks_changed(ctx, Rect2i(29, 29, 7, 6))
	check(not c.is_powered(34, 30))
	check(c.facility(Vector2i(30, 30)).is_empty(), "stale record dropped")
	# The next scheduled pass draws real weather for every plant.
	power.monthly(ctx)
	check_ne(ctx.rng.state(), rng_state)


func test_builder_clicks_leave_the_city_rng_alone() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.WIND_PLANT)
	c.stamp_building(20, 10, Buildings.SOLAR_PLANT)
	var sim := make_simulation(c)
	var b := Builder.new(c, sim.stats, sim)
	var rng_state := sim.rng.state()
	var capacity := sim.stats.power_capacity
	for n in 4:
		var r := b.apply(Tools.Kind.ROAD, Vector2i(60, 60 + 2 * n), Vector2i(62, 60 + 2 * n))
		check(r["ok"])
	check_eq(sim.rng.state(), rng_state, "building roads consumes no randomness")
	check_eq(sim.stats.power_capacity, capacity)
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()


# ── Destruction between scheduled passes ─────────────────────────────────

func test_retired_plant_leaves_its_district_dark_at_once() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	c.stamp_building(14, 10, HOUSE)
	var ctx := make_ctx(c)
	var power: PowerSystemScript = PowerSystemScript.new()
	ctx.systems[power.key] = power
	power.setup(ctx)
	check(c.is_powered(14, 10))
	c.facility(Vector2i(10, 10))["age_years"] = UtilityParams.PLANT_LIFETIME_YEARS
	var rng_state := ctx.rng.state()
	power.yearly(ctx)
	check(Buildings.is_rubble(c.building_at(10, 10)))
	check(not c.is_powered(14, 10), "house dark without waiting for the monthly pass")
	check_eq(ctx.stats.power_capacity, 0)
	check_eq(ctx.stats.unpowered_buildings, 1)
	# Sixteen rubble draws and nothing else.
	var expected := SimRng.new(1)
	expected.set_state(rng_state)
	for _i in 16: expected.below(4)
	check_eq(ctx.rng.state(), expected.state(), "the recompute draws nothing")
	ctx.systems.clear()


func test_worn_out_crossing_cuts_power_at_once() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	for x in range(14, 54):
		c.building.put(x, 10, Buildings.CROSSING_FIRST)
	c.stamp_building(54, 10, HOUSE)
	var ctx := make_ctx(c)
	var power: PowerSystemScript = PowerSystemScript.new()
	var wear := WearSystem.new()
	ctx.systems[power.key] = power
	ctx.systems[wear.key] = wear
	power.setup(ctx)
	wear.setup(ctx)
	check(c.is_powered(54, 10))
	ctx.stats.set_funding(&"roads", 0)
	var lost := false
	for _m in 24:
		wear.monthly(ctx)
		for x in range(14, 54):
			lost = lost or c.building_at(x, 10) != Buildings.CROSSING_FIRST
		if lost: break
	check(lost, "an unfunded crossing wore out")
	check(not c.is_powered(54, 10), "the house past the gap is dark at once")
	check_eq(ctx.stats.unpowered_buildings, 1)
	ctx.systems.clear()


func test_wrecked_line_cuts_power_the_same_day() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	for x in range(14, 20):
		c.stamp_building(x, 10, Buildings.POWER_LINE_FIRST)
	c.stamp_building(20, 10, HOUSE)
	var sim := make_simulation(c)
	check(c.is_powered(20, 10))
	var disasters := sim.get_system(&"disasters") as DisasterSystem
	var rng_state := sim.rng.state()
	check_eq(disasters._wreck(sim._ctx, 16, 10, false), 1)
	check_eq(sim.rng.state(), rng_state)
	disasters.daily(sim._ctx)
	check(not c.is_powered(20, 10), "the house past the break is dark the same day")
	check(c.is_powered(15, 10), "the line before it still carries power")
	check_eq(sim.stats.unpowered_buildings, 1)
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()
