# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const StatisticsSystem := preload("res://scripts/sim/statistics_system.gd")


func make_ctx(day: int = 21) -> SimContext:
	var ctx := make_context(flat_city())
	ctx.city.name = "Dry Gulch"
	ctx.city.mayor = "Ada"
	ctx.clock.founded_year = 1950
	ctx.clock.day = day
	return ctx


func make_system(ctx: SimContext) -> SimSystem:
	var s: SimSystem = StatisticsSystem.new()
	ctx.systems = {s.key: s}
	s.setup(ctx)
	return s


func test_key_and_names() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	check_eq(s.key, &"statistics")
	var names: Array[StringName] = s.names()
	check_eq(names.size(), 18, "seventeen city series plus transit riders")
	check_eq(names[0], &"population")
	check(names.has(&"money"))
	check(names.has(&"demand_industrial"))


func test_monthly_sample_records_every_series() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	var c := ctx.city
	for i in 5:
		c.stamp_building(10 + i, 10, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	c.stamp_building(20, 20, Buildings.COM_2X2_FIRST, Zones.COM_HIGH)
	c.stamp_building(30, 30, Buildings.IND_1X1_FIRST, Zones.IND_LOW)
	c.stamp_building(40, 40, Buildings.CONSTRUCTION_1X1_A, Zones.RES_LOW)
	c.funds = 4321
	var st := ctx.stats
	st.population = 1500
	st.arcology_population = 100
	st.power_capacity = 1000
	st.power_demand = 250
	st.water_capacity = 0
	st.water_demand = 10
	st.average_crime = 12
	st.average_pollution = 34
	st.average_land_value = 56
	st.average_traffic = 78
	st.unemployment = 9
	st.life_expectancy = 61
	st.education_quotient = 105
	st.demand = Vector3i(300, -20, 45)
	s.monthly(ctx, 0)
	for name in s.names():
		check_eq(s.series(name, 1).size(), 1, "one sample for %s" % name)
	check_eq(s.series(&"population", 1)[0], 1600)
	check_eq(s.series(&"residents", 1)[0], 5)
	check_eq(s.series(&"commercial", 1)[0], 4, "every tile of a lot counts")
	check_eq(s.series(&"industrial", 1)[0], 1)
	check_eq(s.series(&"money", 1)[0], 4321)
	check_eq(s.series(&"crime", 1)[0], 12)
	check_eq(s.series(&"pollution", 1)[0], 34)
	check_eq(s.series(&"land_value", 1)[0], 56)
	check_eq(s.series(&"traffic", 1)[0], 78)
	check_eq(s.series(&"power_percent", 1)[0], 75)
	check_eq(s.series(&"water_percent", 1)[0], 0, "no capacity means no spare")
	check_eq(s.series(&"unemployment", 1)[0], 9)
	check_eq(s.series(&"health", 1)[0], 61)
	check_eq(s.series(&"education", 1)[0], 105)
	check_eq(s.series(&"demand_residential", 1)[0], 300)
	check_eq(s.series(&"demand_commercial", 1)[0], -20)
	check_eq(s.series(&"demand_industrial", 1)[0], 45)
	check_eq(s.samples_taken(), 1)
	check(ctx.events.news.is_empty(), "statistics reports nothing")


func test_windows_round_up_and_slice_newest() -> void:
	check_eq(StatisticsSystem.window_years(1), 1)
	check_eq(StatisticsSystem.window_years(3), 10)
	check_eq(StatisticsSystem.window_years(10), 10)
	check_eq(StatisticsSystem.window_years(11), 100)
	check_eq(StatisticsSystem.window_years(100), 100)
	check_eq(StatisticsSystem.window_years(900), 100)
	var ctx := make_ctx()
	var s := make_system(ctx)
	for i in 30:
		ctx.stats.population = i
		s.monthly(ctx, 0)
		ctx.clock.day += GameClock.DAYS_PER_MONTH
	var year: PackedInt32Array = s.series(&"population", 1)
	check_eq(year.size(), 12)
	check_eq(year[0], 18, "oldest of the last twelve")
	check_eq(year[11], 29, "newest last")
	check_eq(s.series(&"population", 10).size(), 30)
	check_eq(s.series(&"population", 100).size(), 30)
	check_eq(s.series(&"no_such_series", 1).size(), 0)


func test_history_keeps_a_century() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	for i in StatisticsParams.KEEP_MONTHS + 50:
		ctx.stats.record(&"money", i, StatisticsParams.KEEP_MONTHS)
	var all: PackedInt32Array = s.series(&"money", 100)
	check_eq(all.size(), StatisticsParams.KEEP_MONTHS)
	check_eq(all[0], 50, "oldest samples dropped first")
	check_eq(all[all.size() - 1], StatisticsParams.KEEP_MONTHS + 49)


func test_money_is_clamped() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	ctx.city.funds = 99999999999
	s.monthly(ctx, 0)
	check_eq(s.series(&"money", 1)[0], StatisticsParams.MONEY_MAX)


func test_status_lines() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	var lines: Array[String] = s.status_lines()
	check_eq(lines.size(), 6, "lines exist from setup")
	check(lines[0].contains("Dry Gulch"))
	check(lines[0].contains("Village"))
	ctx.city.status = 4
	ctx.stats.population = 123456
	ctx.stats.approval = 63
	ctx.stats.unemployment = 7
	ctx.city.funds = 1000000
	s.monthly(ctx, 0)
	lines = s.status_lines()
	check(lines[0].contains("Metropolis"), lines[0])
	check_eq(lines[1], "January 1950")
	check_eq(lines[2], "Population 123,456")
	check_eq(lines[3], "Funds $1,000,000")
	check_eq(lines[4], "Employment 93%")
	check_eq(lines[5], "Approval 63%")
	ctx.city.funds = -1234
	s.monthly(ctx, 0)
	check_eq(s.status_lines()[3], "Funds -$1,234", "the sign leads a debt")
	check_eq(StatisticsSystem.status_name(99), "Megalopolis", "beyond the table uses the last name")
	check_eq(StatisticsSystem.status_name(-1), "Village")


func test_save_load_round_trip() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	ctx.city.status = 2
	for i in 3:
		s.monthly(ctx, 0)
	var text := JSON.stringify(s.save())
	var parsed: Variant = JSON.parse_string(text)
	check(typeof(parsed) == TYPE_DICTIONARY)
	var ctx2 := make_ctx()
	var s2 := make_system(ctx2)
	s2.load(parsed)
	check_eq(s2.samples_taken(), 3)
	check_eq(s2.status_lines(), s.status_lines())
	s2.load({})
	check_eq(s2.samples_taken(), 0, "missing fields fall back to defaults")


class FakeTransport extends SimSystem:
	func _init() -> void:
		key = &"transport"

	func monthly_ridership() -> int:
		return 42


func test_status_lines_show_weather_and_storage_and_riders_are_graphed() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	var env := EnvironmentSystem.new()
	ctx.systems[&"environment"] = env
	env.setup(ctx)
	ctx.systems[&"transport"] = FakeTransport.new()
	ctx.stats.water_stored = 200
	ctx.stats.water_storage_capacity = 400
	s.monthly(ctx, 0)
	var lines: Array = s.call("status_lines")
	check_eq(lines[6], "Rain %d%%, wind %d from the %s" % [env.precipitation(), env.wind_speed(), env.wind_from_name()])
	check_eq(lines[7], "Water towers hold 200 of 400")
	check(StatisticsParams.SERIES.has(&"transit_riders"))
	check_eq(int(ctx.stats.history[&"transit_riders"][-1]), 42, "the month's riders are graphed")
	ctx.systems.clear()
