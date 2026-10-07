# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Cross-system regressions for commuting, industrial demand and pollution.
extends "res://tests/test_case.gd"

var _contexts: Array[SimContext] = []


func after_each() -> void:
	for ctx in _contexts:
		ctx.systems.clear()
	_contexts.clear()


## Equal housing and employment on two parallel streets, with one paid-road
## connection represented by the two tiles between them. Fixtures are synthetic.
func district(connected: bool = true) -> City:
	var city := flat_city()
	city.difficulty = City.Difficulty.MEDIUM
	city.founded_year = 1950
	for x in range(18, 72):
		city.building.put(x, 30, Buildings.ROAD_FIRST)
		city.building.put(x, 33, Buildings.ROAD_FIRST)
	for x in range(20, 70):
		for y in [28, 29]:
			city.stamp_building(x, y, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
		for y in [34, 35]:
			city.stamp_building(x, y, Buildings.IND_1X1_FIRST, Zones.IND_LOW)
	for y in range(27, 37):
		for x in range(18, 72):
			city.set_flag(x, y, TileFlags.POWERED | TileFlags.WATERED, true)
	city.land_value.fill(100)
	if connected:
		connect_streets(city)
	return city


func connect_streets(city: City) -> void:
	city.building.put(48, 31, Buildings.ROAD_FIRST)
	city.building.put(48, 32, Buildings.ROAD_FIRST)


func context(city: City, seed_value: int = 7) -> SimContext:
	var ctx := make_context(city, seed_value)
	ctx.clock.founded_year = city.founded_year
	ctx.systems = {&"zones": ZoneSystem.new(), &"transport": TransportSystem.new(),
		&"environment": EnvironmentSystem.new()}
	for system: SimSystem in ctx.systems.values():
		system.setup(ctx)
	_contexts.append(ctx)
	return ctx


func zones(ctx: SimContext) -> ZoneSystem:
	return ctx.system(&"zones") as ZoneSystem


func transport(ctx: SimContext) -> TransportSystem:
	return ctx.system(&"transport") as TransportSystem


func grow_month(ctx: SimContext) -> void:
	ctx.events.clear()
	zones(ctx).monthly(ctx, 0)
	zones(ctx).monthly(ctx, 1)
	transport(ctx).monthly(ctx)
	ctx.clock.day += 25
	ctx.city.day = ctx.clock.day


## Real saved sector allocations are advanced by the actual economy worker;
## the modifiers themselves are never mocked or assigned by the test.
func economy(ctx: SimContext, allocation: Array[int]) -> EconomySystem:
	var system := EconomySystem.new()
	ctx.systems[&"economy"] = system
	system.setup(ctx)
	var saved := system.save()
	saved["local"] = allocation
	system.load(saved)
	system.monthly(ctx)
	# Hold the national phase equal for a controlled comparison of industry mix.
	ctx.stats.economy_phase = 1
	return system


func test_failed_commutes_increase_residential_decline() -> void:
	# Removing the growth consumer would leave both districts' homes unchanged.
	var connected := context(district())
	var isolated := context(district(false))
	for ctx in [connected, isolated]:
		transport(ctx).monthly(ctx)
	check_eq(transport(connected).unreachable_ratio(), 0.0, "all routes reach jobs")
	check_eq(transport(isolated).unreachable_ratio(), 1.0, "roads exist but cannot reach jobs")
	for month in 3:
		grow_month(connected)
		grow_month(isolated)
	check_eq(zones(connected).residents(), 1000, "supplied, connected homes remain occupied")
	check_lt(zones(isolated).residents(), zones(connected).residents(),
		"failed commuting must affect the growth worker")
	check_eq(isolated.city.traffic_at(30, 30), 0, "failed trips deposit no traffic")


func test_reconnecting_jobs_removes_pressure_and_recovers_homes() -> void:
	var repaired := context(district(false))
	var isolated := context(district(false))
	for ctx in [repaired, isolated]:
		transport(ctx).monthly(ctx)
		for month in 3:
			grow_month(ctx)
	check_lt(zones(repaired).residents(), 1000, "the outage has a real cost")
	var before_repair := zones(repaired).residents()
	connect_streets(repaired.city)
	transport(repaired).monthly(repaired)
	check_eq(transport(repaired).unreachable_ratio(), 0.0)
	for month in 6:
		grow_month(repaired)
		grow_month(isolated)
	check_gt(zones(repaired).residents(), zones(isolated).residents(),
		"restoring transport must permit occupied homes to recover")
	check_gt(zones(repaired).residents(), before_repair, "homes actually reoccupy after repair")


func test_partial_failed_commutes_scale_saturated_residential_growth() -> void:
	var city := flat_city()
	city.land_value.fill(100)
	for x in range(10, 21):
		city.building.put(x, 10, Buildings.ROAD_FIRST)
	for x in range(60, 71):
		city.building.put(x, 10, Buildings.ROAD_FIRST)
	for home in [Vector2i(10, 9), Vector2i(60, 9)]:
		city.stamp_building(home.x, home.y, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
		city.set_flag(home.x, home.y, TileFlags.POWERED | TileFlags.WATERED, true)
	city.stamp_building(20, 11, Buildings.IND_1X1_FIRST, Zones.IND_LOW)
	city.stamp_building(70, 25, Buildings.IND_1X1_FIRST, Zones.IND_LOW)
	var ctx := context(city)
	transport(ctx).monthly(ctx)
	check_eq(transport(ctx).unreachable_ratio(), 0.5, "one real route succeeds and one fails")
	zones(ctx).monthly(ctx, 0)
	zones(ctx)._bind(city)
	check_eq(zones(ctx)._growth_points(Vector2i(10, 9), 0, true), 2000,
		"saturated local growth is clamped to 4000 before the 50 percent pressure")
	check_eq(zones(ctx)._growth_points(Vector2i(10, 9), 0, false), 0,
		"local missing access remains prohibitive")
	zones(ctx)._unbind()


func test_saved_failed_commutes_apply_to_the_second_growth_phase() -> void:
	var city := district(false)
	# Enough unsupplied western homes to exceed the real reporting threshold;
	# the original eastern homes still exercise the loaded growth phase.
	for y in range(20, 26):
		for x in range(20, 64):
			city.stamp_building(x, y, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	for y in range(14, 20):
		for x in range(20, 64):
			city.stamp_building(x, y, Buildings.CONSTRUCTION_1X1_A, Zones.IND_LOW)
			city.set_flag(x, y, TileFlags.POWERED | TileFlags.WATERED, true)
	var live := context(city)
	transport(live).monthly(live)
	zones(live).monthly(live, 0)
	live.clock.day = 5
	live.city.day = 5
	var twin := context(live.city.duplicate_city(), 123)
	twin.clock.day = live.clock.day
	twin.stats.from_dict(JSON.parse_string(JSON.stringify(live.stats.to_dict())))
	twin.rng = SimRng.from_saved_seed(live.rng.seed_value())
	twin.rng.set_state(live.rng.state())
	for key in live.systems:
		twin.systems[key].load(JSON.parse_string(JSON.stringify(live.systems[key].save())))
	check_eq(transport(twin).unreachable_ratio(), 1.0)
	for ctx in [live, twin]:
		ctx.events.clear()
		zones(ctx).monthly(ctx, 1)
		zones(ctx)._bind(ctx.city)
		check_eq(zones(ctx)._growth_points(Vector2i(68, 29), 0, true), 0,
			"the eastern phase recalculates pressure after loading")
		zones(ctx)._unbind()
	check_eq(SaveFormat.encode_city(twin.city), SaveFormat.encode_city(live.city))
	check_eq(twin.rng.state(), live.rng.state())
	check_eq(zones(twin).save(), zones(live).save())
	var kinds: Array[StringName] = []
	for story in live.events.news:
		kinds.append(story["kind"])
	check(kinds.has(&"abandonment_wave"), "the first phase's declines produce a report")
	check(kinds.has(&"zone_boom"), "the first phase's completions produce a report")
	check_eq(twin.events.news, live.events.news, "reload keeps both phases' news counts")


func test_industrial_specialization_changes_the_demand_target() -> void:
	# Same occupied lots, taxes, difficulty, phase and prior R units. The only
	# difference is whether the 1000 jobs are diverse or in one sector.
	var diverse := context(district())
	var specialized := context(district())
	var a := economy(diverse, [100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 0])
	var b := economy(specialized, [1000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	check_eq(a.industrial_demand_modifier(), 0)
	check_eq(b.industrial_demand_modifier(), 15)
	for ctx in [diverse, specialized]:
		var saved := zones(ctx).save()
		saved["raw_demand"] = [0, 0, 0]
		zones(ctx).load(saved)
		zones(ctx).monthly(ctx, 0)
	# Hand calculation: 100 R/0 C/100 I units, labor=100/101, target factors
	# 1.10 and 1.25, then 600*(target/101-1), truncated once.
	check_eq(zones(diverse).raw_demand().z, 46)
	check_eq(zones(specialized).raw_demand().z, 135,
		"sector bonus is a percentage of the target, not a flat meter increment")
	check_eq(zones(specialized).raw_demand().x, zones(diverse).raw_demand().x)
	check_eq(zones(specialized).raw_demand().y, zones(diverse).raw_demand().y)


func test_industry_mix_changes_pollution_and_land_value() -> void:
	var clean := context(district())
	var diverse := context(district())
	var heavy := context(district())
	var a := economy(clean, [0, 0, 0, 0, 0, 0, 0, 0, 0, 1000, 0])
	var b := economy(diverse, [100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 0])
	var c := economy(heavy, [1000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	check_eq(a.pollution_modifier(), -1)
	check_eq(b.pollution_modifier(), 0)
	check_eq(c.pollution_modifier(), 2)
	for ctx in [clean, diverse, heavy]:
		ctx.city.pollution.fill(96)
		ctx.system(&"environment").monthly(ctx)
	# A source-free interior block has numerator 6*96=576 and four neighbours.
	check_eq(clean.city.pollution_at(10, 10), 64)
	check_eq(diverse.city.pollution_at(10, 10), 72)
	check_eq(heavy.city.pollution_at(10, 10), 96)
	check_lt(clean.city.pollution_at(30, 34), heavy.city.pollution_at(30, 34),
		"the same factories pollute differently with a different industry mix")
	check_gt(clean.city.land_value_at(30, 29), heavy.city.land_value_at(30, 29),
		"the pollution consequence reaches residential land value")


func test_saved_feedback_continues_with_identical_maps_and_random_stream() -> void:
	var live := context(district(false))
	economy(live, [1000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	transport(live).monthly(live)
	for month in 3:
		grow_month(live)
	var twin := context(live.city.duplicate_city(), 123)
	twin.clock.day = live.clock.day
	twin.stats.from_dict(JSON.parse_string(JSON.stringify(live.stats.to_dict())))
	twin.rng = SimRng.from_saved_seed(live.rng.seed_value())
	twin.rng.set_state(live.rng.state())
	twin.systems[&"economy"] = EconomySystem.new()
	for key in live.systems:
		twin.systems[key].load(JSON.parse_string(JSON.stringify(live.systems[key].save())))
	for month in 6:
		for ctx in [live, twin]:
			grow_month(ctx)
			ctx.system(&"environment").monthly(ctx)
			ctx.system(&"economy").monthly(ctx)
		check_eq(SaveFormat.encode_city(twin.city), SaveFormat.encode_city(live.city))
		check_eq(JSON.parse_string(JSON.stringify(twin.stats.to_dict())),
			JSON.parse_string(JSON.stringify(live.stats.to_dict())))
		check_eq(twin.rng.state(), live.rng.state())
		for key in live.systems:
			check_eq(twin.systems[key].save(), live.systems[key].save(), String(key))
