# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const PowerSystemScript := preload("res://scripts/sim/power_system.gd")
const UtilityParams := preload("res://scripts/sim/data/utility_params.gd")

const HOUSE := Buildings.RES_1X1_FIRST


func make_ctx(c: City) -> SimContext:
	var ctx := make_context(c)
	ctx.clock.founded_year = c.founded_year
	ctx.clock.day = c.day
	return ctx


func make_power() -> PowerSystemScript:
	var s: PowerSystemScript = PowerSystemScript.new()
	return s


func line(c: City, from: Vector2i, to: Vector2i) -> void:
	var p := from
	while p != to:
		c.stamp_building(p.x, p.y, Buildings.POWER_LINE_FIRST)
		p += (to - p).sign()
	c.stamp_building(to.x, to.y, Buildings.POWER_LINE_FIRST)


func news_kinds(ctx: SimContext) -> Array:
	var out: Array = []
	for n in ctx.events.news:
		out.append(n.kind)
	return out


func test_coal_plant_powers_connected_house() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	line(c, Vector2i(14, 10), Vector2i(15, 10))
	c.stamp_building(16, 10, HOUSE)
	c.stamp_building(30, 30, HOUSE)
	var ctx := make_ctx(c)
	var power := make_power()
	power.setup(ctx)
	check(c.is_powered(16, 10), "house on the line is powered")
	check(c.is_powered(14, 10), "line carries power")
	check(c.is_powered(10, 10), "plant tile is powered")
	check(not c.is_powered(30, 30), "isolated house stays dark")
	check_eq(ctx.stats.power_capacity, 704)
	check_eq(ctx.stats.power_demand, 2)
	check_eq(ctx.stats.unpowered_buildings, 1)
	check_eq(power.consumed(), 1)
	check_eq(power.usage_percent(), 0)
	check(not power.is_shortage())


func test_roads_and_trees_do_not_conduct() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	c.stamp_building(14, 10, Buildings.ROAD_FIRST)
	c.stamp_building(15, 10, Buildings.TREES_1)
	c.stamp_building(16, 10, HOUSE)
	var ctx := make_ctx(c)
	make_power().setup(ctx)
	check(not c.conducts_power(14, 10), "road does not conduct")
	check(not c.conducts_power(15, 10), "tree does not conduct")
	check(c.conducts_power(10, 10), "plant conducts")
	check(c.conducts_power(16, 10), "house conducts")
	check(not c.is_powered(16, 10), "house behind a road is dark")
	check_eq(ctx.stats.unpowered_buildings, 1)


func test_crossing_carries_power_over_road() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	c.stamp_building(14, 10, Buildings.CROSSING_FIRST)   # road under power line
	c.stamp_building(15, 10, HOUSE)
	var ctx := make_ctx(c)
	make_power().setup(ctx)
	check(c.is_powered(15, 10))


func test_short_network_browns_out_farthest_first() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.WIND_PLANT)   # ground 4, wind 10: two tiles
	for x in range(11, 17):
		c.stamp_building(x, 10, HOUSE)
	var ctx := make_ctx(c)
	var power := make_power()
	power.setup(ctx)
	check_eq(ctx.stats.power_capacity, 2)
	check_eq(ctx.stats.power_demand, 6)
	check(c.is_powered(11, 10), "nearest house powered")
	check(c.is_powered(12, 10), "second house powered")
	check(not c.is_powered(13, 10), "third house browns out")
	check(not c.is_powered(16, 10), "farthest house dark")
	check_eq(ctx.stats.unpowered_buildings, 4)
	check(power.is_shortage())
	check(&"power_shortage" in news_kinds(ctx), "shortage reported once")
	ctx.events.clear()
	power.monthly(ctx)
	check(not (&"power_shortage" in news_kinds(ctx)), "no repeat while still short")
	c.stamp_building(20, 20, Buildings.COAL_PLANT)
	line(c, Vector2i(17, 10), Vector2i(20, 10))
	line(c, Vector2i(20, 11), Vector2i(20, 19))
	ctx.events.clear()
	power.networks_changed(ctx, Rect2i(17, 10, 7, 14))
	check(c.is_powered(16, 10), "coal plant joins the network")
	check(not power.is_shortage())
	check(&"power_restored" in news_kinds(ctx))


func test_energy_conservation_stretches_budget() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.GAS_PLANT)   # 176 tiles
	for y in range(10, 19):
		for x in range(14, 34):
			c.stamp_building(x, y, HOUSE)   # 180 consumer tiles, all adjacent
	var ctx := make_ctx(c)
	var power := make_power()
	power.setup(ctx)
	check_eq(ctx.stats.power_capacity, 176)
	check_eq(ctx.stats.unpowered_buildings, 4)
	ctx.stats.ordinances[&"energy_conservation"] = true
	power.monthly(ctx)
	check_eq(ctx.stats.power_capacity, 176, "reported capacity unchanged")
	check_eq(ctx.stats.unpowered_buildings, 0, "one twelfth more budget covers the rest")


func test_hydro_needs_a_waterfall() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.HYDRO_PLANT_A)
	c.stamp_building(11, 10, HOUSE)
	var ctx := make_ctx(c)
	var power := make_power()
	power.setup(ctx)
	check_eq(ctx.stats.power_capacity, 0)
	check(not c.is_powered(11, 10))
	c.terrain.put(10, 10, Terrain.WATERFALL)
	power.monthly(ctx)
	check_eq(ctx.stats.power_capacity, 40)
	check(c.is_powered(11, 10))


func test_solar_output_depends_on_rain_range() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.SOLAR_PLANT)
	var ctx := make_ctx(c)
	var power := make_power()
	for _i in 5:
		power.monthly(ctx)
		check_between(ctx.stats.power_capacity, 80, 192, "solar farm output")


func test_plant_records_and_ages() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	c.stamp_building(20, 20, Buildings.HYDRO_PLANT_A)
	var ctx := make_ctx(c)
	var power := make_power()
	power.setup(ctx)
	var rec := c.facility(Vector2i(10, 10))
	check_eq(rec.get("key"), &"plant_coal")
	check_eq(rec.get("age_years"), 0)
	check_eq(rec.get("capacity"), 704)
	for _i in 49:
		power.yearly(ctx)
	check_eq(c.facility(Vector2i(10, 10)).get("age_years"), 49)
	check_eq(c.facility(Vector2i(20, 20)).get("age_years"), 0, "dams never age")
	check(&"plant_aging" in news_kinds(ctx), "warning past 48 years")
	check_eq(ctx.events.news.size(), 1, "warned once")
	var summary := power.network_summary()
	check_eq(summary.plants.size(), 2)
	var found := false
	for p in summary.plants:
		if p.anchor == Vector2i(10, 10):
			found = true
			check_eq(p.age_years, 49)
			check_eq(p.key, &"plant_coal")
	check(found, "coal plant listed in summary")
	check_eq(power.plant_capacity(Vector2i(10, 10)), 704)


func test_old_plant_retires_to_rubble() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	c.stamp_building(14, 10, HOUSE)
	var ctx := make_ctx(c)
	var power := make_power()
	power.setup(ctx)
	check(c.is_powered(14, 10))
	c.facility(Vector2i(10, 10))["age_years"] = 50
	power.yearly(ctx)
	check(Buildings.is_rubble(c.building_at(10, 10)), "footprint becomes rubble")
	check(Buildings.is_rubble(c.building_at(13, 13)))
	check(not c.conducts_power(12, 12))
	check(c.facility(Vector2i(10, 10)).is_empty(), "record released")
	check(&"plant_retired" in news_kinds(ctx))
	check_eq(ctx.events.notices.size(), 1)
	check_eq(ctx.events.notices[0].kind, &"plant_retired")
	check_ne(ctx.events.map_dirty.size, Vector2i.ZERO, "map marked dirty")
	power.monthly(ctx)
	check(not c.is_powered(14, 10), "house dark after retirement")
	check_eq(ctx.stats.power_capacity, 0)


func test_disasters_off_pays_for_replacement() -> void:
	var c := flat_city(5000)
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	var ctx := make_ctx(c)
	ctx.stats.disasters_enabled = false
	var power := make_power()
	power.setup(ctx)
	c.facility(Vector2i(10, 10))["age_years"] = 50
	power.yearly(ctx)
	check_eq(c.building_at(10, 10), Buildings.COAL_PLANT, "plant stays")
	check_eq(c.funds, 1000, "replacement cost debited")
	check_eq(c.facility(Vector2i(10, 10)).get("age_years"), 0)
	check(&"plant_replaced" in news_kinds(ctx))
	c.funds = 100
	c.facility(Vector2i(10, 10))["age_years"] = 50
	ctx.events.clear()
	power.yearly(ctx)
	check(Buildings.is_rubble(c.building_at(10, 10)), "no funds: retired instead")


func test_networks_changed_maintains_conduction_flags() -> void:
	var c := flat_city()
	c.building.put(5, 5, Buildings.POWER_LINE_FIRST)
	c.building.put(6, 5, Buildings.ROAD_FIRST)
	c.building.put(7, 5, NetworkShapes.CROSS_POWER_EW_RAIL_NS)
	c.building.put(8, 5, 55)   # plain rail T-junction, without a power line
	c.set_flag(8, 5, TileFlags.CONDUCTS_POWER, true)
	var ctx := make_ctx(c)
	var power := make_power()
	power.networks_changed(ctx, Rect2i(5, 5, 4, 1))
	check(c.conducts_power(5, 5))
	check(not c.conducts_power(6, 5))
	check(c.conducts_power(7, 5))
	check(not c.conducts_power(8, 5), "plain rail clears a stale conduction flag")
	c.building.put(5, 5, Buildings.NONE)
	power.networks_changed(ctx, Rect2i(5, 5, 1, 1))
	check(not c.conducts_power(5, 5), "flag cleared after demolition")


func test_stale_plant_record_is_pruned() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	var ctx := make_ctx(c)
	var power := make_power()
	power.setup(ctx)
	check(not c.facility(Vector2i(10, 10)).is_empty())
	c.add_facility(Vector2i(40, 40), {"key": &"police_station", "built_day": 0})
	c.clear_footprint(10, 10)
	c.add_facility(Vector2i(10, 10), {"key": &"plant_coal", "built_day": 0, "age_years": 3})
	power.monthly(ctx)
	check(c.facility(Vector2i(10, 10)).is_empty(), "record without a plant is dropped")
	check(not c.facility(Vector2i(40, 40)).is_empty(), "other systems' records untouched")


func test_save_load_round_trip() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.WIND_PLANT)
	for x in range(11, 17):
		c.stamp_building(x, 10, HOUSE)
	var ctx := make_ctx(c)
	var power := make_power()
	power.setup(ctx)
	check(power.is_shortage())
	var data := power.save()
	var json := JSON.stringify(data)
	var back: Dictionary = JSON.parse_string(json)
	var other := make_power()
	other.load(back)
	check(other.is_shortage())
	check_eq(other.consumed(), power.consumed())


func test_runs_inside_simulation_on_day_one() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	c.stamp_building(14, 10, HOUSE)
	var sim := make_simulation(c)
	check(sim.get_system(&"power") != null, "registered under its key")
	check_eq(sim.stats.power_capacity, 704, "setup distributes")
	sim.stats.power_capacity = 0
	sim.advance_day()
	check_eq(sim.stats.power_capacity, 704, "monthly job on day 1")
	check(c.is_powered(14, 10))
	# Release the context/system reference cycle before the synchronous harness quits.
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()
