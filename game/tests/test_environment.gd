# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const EnvironmentSystemScript := preload("res://scripts/sim/environment_system.gd")
const EnvironmentParams := preload("res://scripts/sim/data/environment_params.gd")

## District placed on every test city: light residential homes at (40..49, 40..49).
const DISTRICT := Rect2i(40, 40, 10, 10)


func make_ctx(c: City, seed_value: int = 7) -> SimContext:
	return make_context(c, seed_value)


## A flat city with a powered, watered residential district.
func district_city() -> City:
	var c := flat_city()
	for y in range(DISTRICT.position.y, DISTRICT.end.y):
		for x in range(DISTRICT.position.x, DISTRICT.end.x):
			c.stamp_building(x, y, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
			c.set_flag(x, y, TileFlags.POWERED | TileFlags.WATERED, true)
	return c


func run_months(env: SimSystem, ctx: SimContext, months: int) -> void:
	for _i in months:
		ctx.events.clear()
		env.monthly(ctx)


func test_coal_plant_raises_pollution_and_lowers_land_value() -> void:
	var control := district_city()
	var polluted := district_city()
	var plant := polluted.stamp_building(44, 52, Buildings.COAL_PLANT)
	for dy in 4:
		for dx in 4:
			polluted.set_flag(plant.x + dx, plant.y + dy, TileFlags.POWERED, true)
	var env_a := EnvironmentSystemScript.new()
	var env_b := EnvironmentSystemScript.new()
	var ctx_a := make_ctx(control)
	var ctx_b := make_ctx(polluted)
	run_months(env_a, ctx_a, 3)
	run_months(env_b, ctx_b, 3)
	check_eq(control.pollution_at(45, 53), 0, "clean city has no pollution at the plant site")
	check_gt(polluted.pollution_at(45, 53), 20, "coal plant pollutes its own block")
	check_gt(polluted.pollution_at(45, 49), polluted.pollution_at(45, 40),
		"pollution is stronger beside the plant than across the district")
	check_gt(polluted.pollution_at(45, 53), polluted.pollution_at(45, 40),
		"pollution falls off with distance")
	check_lt(polluted.land_value_at(45, 49), control.land_value_at(45, 49),
		"land value drops next to the plant")
	check_gt(ctx_b.stats.average_pollution, ctx_a.stats.average_pollution)
	check_gt(control.land_value_at(45, 45), 0, "developed land has value")
	check_eq(control.land_value_at(5, 5), 0, "empty desert has no land value")


func test_pollution_decays_when_the_source_is_removed() -> void:
	var c := district_city()
	var plant := c.stamp_building(44, 52, Buildings.COAL_PLANT)
	var env := EnvironmentSystemScript.new()
	var ctx := make_ctx(c)
	run_months(env, ctx, 6)
	var before := c.pollution_at(plant.x + 1, plant.y + 1)
	c.clear_footprint(plant.x, plant.y)
	run_months(env, ctx, 6)
	check_lt(c.pollution_at(plant.x + 1, plant.y + 1), before, "pollution fades after demolition")


func test_water_treatment_reduces_pollution() -> void:
	var plain := district_city()
	var treated := district_city()
	for c in [plain, treated]:
		c.stamp_building(44, 52, Buildings.COAL_PLANT)
	var plant := treated.stamp_building(52, 44, Buildings.WATER_TREATMENT)
	treated.set_flag(plant.x, plant.y, TileFlags.POWERED, true)
	var env_a := EnvironmentSystemScript.new()
	var env_b := EnvironmentSystemScript.new()
	run_months(env_a, make_ctx(plain), 6)
	run_months(env_b, make_ctx(treated), 6)
	check_lt(treated.pollution_at(45, 49), plain.pollution_at(45, 49),
		"a powered treatment plant lowers pollution around it")
	check_lt(env_b.pollution_total(), env_a.pollution_total())


func test_unpowered_treatment_plant_does_nothing() -> void:
	var plain := district_city()
	var idle := district_city()
	for c in [plain, idle]:
		c.stamp_building(44, 52, Buildings.COAL_PLANT)
	idle.stamp_building(52, 44, Buildings.WATER_TREATMENT)
	var env_a := EnvironmentSystemScript.new()
	var env_b := EnvironmentSystemScript.new()
	run_months(env_a, make_ctx(plain), 4)
	run_months(env_b, make_ctx(idle), 4)
	check_eq(idle.pollution_at(45, 49), plain.pollution_at(45, 49) + 0,
		"an unpowered plant leaves pollution unchanged")


func test_pollution_controls_cut_industrial_output() -> void:
	var free := flat_city()
	var controlled := flat_city()
	for c in [free, controlled]:
		for y in range(40, 52, 3):
			for x in range(40, 52, 3):
				c.stamp_building(x, y, Buildings.IND_3X3_FIRST, Zones.IND_HIGH)
	var env_a := EnvironmentSystemScript.new()
	var env_b := EnvironmentSystemScript.new()
	var ctx_b := make_ctx(controlled)
	ctx_b.stats.ordinances[&"pollution_controls"] = true
	run_months(env_a, make_ctx(free), 4)
	run_months(env_b, ctx_b, 4)
	check_gt(free.pollution_at(45, 45), 0)
	check_lt(controlled.pollution_at(45, 45), free.pollution_at(45, 45),
		"the ordinance reduces industrial pollution")


func test_parks_and_trees_lift_land_value_and_absorb_pollution() -> void:
	var bare := district_city()
	var green := district_city()
	for c in [bare, green]:
		c.stamp_building(44, 52, Buildings.COAL_PLANT)
	green.stamp_building(50, 40, Buildings.LARGE_PARK)
	for y in range(50, 52):
		for x in range(44, 46):
			green.stamp_building(x, y, Buildings.TREES_1 + 2)
	var env_a := EnvironmentSystemScript.new()
	var env_b := EnvironmentSystemScript.new()
	run_months(env_a, make_ctx(bare), 4)
	run_months(env_b, make_ctx(green), 4)
	check_gt(green.land_value_at(49, 41), bare.land_value_at(49, 41), "a park raises nearby value")
	check_gt(bare.pollution_at(45, 51), 0, "the grove site is polluted without trees")
	check_lt(green.pollution_at(45, 51), bare.pollution_at(45, 51), "trees absorb pollution")


func test_police_coverage_lowers_crime() -> void:
	var unguarded := district_city()
	var guarded := district_city()
	for c in [unguarded, guarded]:
		for cy in range(10, 13):
			for cx in range(10, 13):
				c.density.put(cx, cy, 160)
	for cy in range(10, 13):
		for cx in range(10, 13):
			guarded.police.put(cx, cy, 200)
	var env_a := EnvironmentSystemScript.new()
	var env_b := EnvironmentSystemScript.new()
	var ctx_a := make_ctx(unguarded)
	var ctx_b := make_ctx(guarded)
	run_months(env_a, ctx_a, 2)
	run_months(env_b, ctx_b, 2)
	check_gt(unguarded.crime_at(45, 45), 0, "dense unguarded blocks have crime")
	check_lt(guarded.crime_at(45, 45), unguarded.crime_at(45, 45), "coverage lowers crime")
	check_lt(ctx_b.stats.average_crime, ctx_a.stats.average_crime)
	check_eq(guarded.crime_at(5, 5), 0, "empty desert has no crime")


func test_ordinances_move_crime() -> void:
	var plain := district_city()
	var gambling := district_city()
	var watched := district_city()
	for c in [plain, gambling, watched]:
		for cy in range(10, 13):
			for cx in range(10, 13):
				c.density.put(cx, cy, 120)
	var ctx_g := make_ctx(gambling)
	ctx_g.stats.ordinances[&"legalized_gambling"] = true
	var ctx_w := make_ctx(watched)
	ctx_w.stats.ordinances[&"neighborhood_watch"] = true
	run_months(EnvironmentSystemScript.new(), make_ctx(plain), 2)
	run_months(EnvironmentSystemScript.new(), ctx_g, 2)
	run_months(EnvironmentSystemScript.new(), ctx_w, 2)
	check_gt(gambling.crime_at(45, 45), plain.crime_at(45, 45), "gambling raises crime")
	check_lt(watched.crime_at(45, 45), plain.crime_at(45, 45), "the watch lowers crime")
	for k: StringName in [&"anti_drug_campaign", &"junior_sports"]:
		var c := district_city()
		for cy in range(10, 13):
			for cx in range(10, 13):
				c.density.put(cx, cy, 120)
		var ctx := make_ctx(c)
		ctx.stats.ordinances[k] = true
		run_months(EnvironmentSystemScript.new(), ctx, 2)
		check_lt(c.crime_at(45, 45), plain.crime_at(45, 45), "%s lowers crime" % k)


func test_tree_planting_lines_streets_with_shade_trees() -> void:
	var bare := flat_city()
	var planted := flat_city()
	for c in [bare, planted]:
		c.stamp_building(44, 52, Buildings.COAL_PLANT)
		for x in range(40, 52):
			for y in range(50, 52):
				c.stamp_building(x, y, Buildings.ROAD_FIRST)
	var ctx_b := make_ctx(planted)
	ctx_b.stats.ordinances[&"tree_planting"] = true
	run_months(EnvironmentSystemScript.new(), make_ctx(bare), 4)
	run_months(EnvironmentSystemScript.new(), ctx_b, 4)
	check_gt(bare.pollution_at(45, 51), 0, "the street beside the plant is polluted")
	check_lt(planted.pollution_at(45, 51), bare.pollution_at(45, 51), "street trees absorb pollution")
	check_eq(EnvironmentSystemScript.absorption_of(Buildings.ROAD_FIRST), 0,
		"bare streets absorb nothing")
	check_eq(EnvironmentSystemScript.absorption_of(Buildings.HIGHWAY_FIRST, true), 0,
		"highways are not planted")


func test_dense_commercial_centre_raises_nearby_value() -> void:
	var c := flat_city()
	for y in range(60, 66, 3):
		for x in range(60, 66, 3):
			c.stamp_building(x, y, Buildings.COM_3X3_FIRST, Zones.COM_HIGH)
	# Two identical residential blocks: one near the centre, one far from it.
	for origin in [Vector2i(50, 60), Vector2i(20, 60)]:
		for y in range(origin.y, origin.y + 4):
			for x in range(origin.x, origin.x + 4):
				c.stamp_building(x, y, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
				c.set_flag(x, y, TileFlags.POWERED | TileFlags.WATERED, true)
	var env := EnvironmentSystemScript.new()
	run_months(env, make_ctx(c), 2)
	check_gt(c.land_value_at(51, 61), c.land_value_at(21, 61),
		"homes near the commercial centre are worth more than distant ones")


func test_pollution_alert_is_reported_once() -> void:
	var c := flat_city()
	for y in range(40, 52, 3):
		for x in range(40, 52, 3):
			c.stamp_building(x, y, Buildings.IND_3X3_FIRST, Zones.IND_HIGH)
	for y in range(40, 52):
		for x in range(52, 56):
			c.stamp_building(x, y, Buildings.CONTAMINATION)
	var env := EnvironmentSystemScript.new()
	var ctx := make_ctx(c)
	var alerts := 0
	for _i in 8:
		ctx.events.clear()
		env.monthly(ctx)
		for story in ctx.events.news:
			if story["kind"] == &"pollution_alert":
				alerts += 1
	check_ge(ctx.stats.average_pollution, EnvironmentParams.POLLUTION_ALERT_LEVEL,
		"the test city is heavily polluted")
	check_eq(alerts, 1, "one alert while the level stays high")


func test_save_load_round_trip() -> void:
	var c := district_city()
	c.stamp_building(44, 52, Buildings.COAL_PLANT)
	var env := EnvironmentSystemScript.new()
	var ctx := make_ctx(c)
	run_months(env, ctx, 3)
	var json := JSON.stringify(env.save())
	var back: Dictionary = JSON.parse_string(json)
	var restored := EnvironmentSystemScript.new()
	restored.load(back)
	check_eq(restored.pollution_total(), env.pollution_total())
	check_eq(restored.land_value_total(), env.land_value_total())
	check_eq(restored.crime_total(), env.crime_total())
	check_eq(restored.developed_blocks(), env.developed_blocks())
	check_gt(env.developed_blocks(), 0)
	# The restored system continues from the same maps and produces the same result.
	var twin := c.duplicate_city()
	var ctx_twin := make_ctx(twin)
	# The monthly weather roll draws from the shared generator.
	ctx_twin.rng.set_state(ctx.rng.state())
	run_months(env, ctx, 1)
	run_months(restored, ctx_twin, 1)
	check_eq(twin.pollution.data, c.pollution.data, "pollution map continues identically")
	check_eq(twin.land_value.data, c.land_value.data, "land value map continues identically")
	check_eq(twin.crime.data, c.crime.data, "crime map continues identically")


func test_weather_follows_the_desert_seasons() -> void:
	var ctx := make_ctx(flat_city())
	var env := EnvironmentSystemScript.new()
	ctx.systems[&"environment"] = env
	env.setup(ctx)
	check_eq(UtilityParams.weather(ctx, &"precipitation", -1), env.precipitation(),
		"power and water read the environment's weather")
	var rain_by_month := {}
	var wind_by_month := {}
	var rain_total := 0
	var wind_total := 0
	var months := 0
	for year in 10:
		for m in 12:
			ctx.clock.day = (year * 12 + m) * GameClock.DAYS_PER_MONTH + 10
			env.monthly(ctx)
			check_between(env.precipitation(), 0, 100)
			check_gt(env.wind_speed(), -1)
			rain_by_month[m] = int(rain_by_month.get(m, 0)) + env.precipitation()
			wind_by_month[m] = int(wind_by_month.get(m, 0)) + env.wind_speed()
			rain_total += env.precipitation()
			wind_total += env.wind_speed()
			months += 1
	check_gt(int(rain_by_month[0]), int(rain_by_month[5]), "January is wetter than June")
	check_gt(int(wind_by_month[3]), int(wind_by_month[8]), "April is windier than September")
	check_between(rain_total / months, UtilityParams.DEFAULT_RAIN - 3, UtilityParams.DEFAULT_RAIN + 3)
	check_between(wind_total / months, UtilityParams.DEFAULT_WIND - 2, UtilityParams.DEFAULT_WIND + 2)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(env.save()))
	var restored := EnvironmentSystemScript.new()
	restored.setup(ctx)
	restored.load(saved)
	check_eq(restored.precipitation(), env.precipitation())
	check_eq(restored.wind_speed(), env.wind_speed())
	ctx.systems.clear()


func test_the_neon_dome_lifts_land_value() -> void:
	var plain := district_city()
	var domed := district_city()
	domed.stamp_building(50, 40, Buildings.NEON_DOME)
	run_months(EnvironmentSystemScript.new(), make_ctx(plain), 2)
	run_months(EnvironmentSystemScript.new(), make_ctx(domed), 2)
	check_gt(domed.land_value_at(49, 41), plain.land_value_at(49, 41), "the landmark is an attraction")


func test_the_wind_carries_pollution_downwind() -> void:
	var c := flat_city()
	c.stamp_building(62, 62, Buildings.COAL_PLANT)
	var ctx := make_ctx(c)
	var env := EnvironmentSystemScript.new()
	env.setup(ctx)
	env._wind = 20
	env._wind_from = Vector2i(-1, 0)
	for _m in 6:
		env._scan_tiles(ctx)
		env._update_pollution(ctx)
	# The plant covers blocks 31..32; compare blocks three away on each side.
	check_gt(c.pollution_at(2 * 35, 2 * 31), c.pollution_at(2 * 28, 2 * 31),
		"a west wind leaves the east side smokier than the west")
	check_eq(env.wind_from_name(), "west")


class FakeArcologies extends SimSystem:
	func _init() -> void:
		key = &"rewards"

	func arcology_report() -> Array[Dictionary]:
		return [{"anchor": Vector2i(80, 80), "key": &"arcology_comstock", "residents": 40000,
			"pollution": 80, "crime": 40}]


func test_ports_bases_and_arcologies_bring_crime_and_pollution() -> void:
	var plain := flat_city()
	var based := flat_city()
	for c in [plain, based]:
		for cy in range(14, 17):
			for cx in range(14, 17):
				c.density.put(cx, cy, 120)
	for y in range(60, 64):
		for x in range(60, 64):
			based.stamp_building(x, y, Buildings.MILITARY_TOWER, Zones.MILITARY)
	run_months(EnvironmentSystemScript.new(), make_ctx(plain), 2)
	run_months(EnvironmentSystemScript.new(), make_ctx(based), 2)
	check_gt(based.crime_at(61, 61), plain.crime_at(61, 61), "a military base brings crime")
	check_gt(based.pollution_at(61, 61), 0, "base pieces pollute")
	var arco := flat_city()
	var empty := flat_city()
	for c in [arco, empty]:
		c.stamp_building(80, 80, Buildings.ARCOLOGY_COMSTOCK)
		for cy in range(19, 22):
			for cx in range(19, 22):
				c.density.put(cx, cy, 120)
	var crowded := make_ctx(arco)
	crowded.systems[&"rewards"] = FakeArcologies.new()
	run_months(EnvironmentSystemScript.new(), crowded, 2)
	run_months(EnvironmentSystemScript.new(), make_ctx(empty), 2)
	check_gt(arco.crime_at(81, 81), empty.crime_at(81, 81), "residents bring crime")
	check_gt(arco.pollution_at(81, 81), empty.pollution_at(81, 81), "residents add pollution")
	crowded.systems.clear()
