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
	run_months(env, ctx, 1)
	run_months(restored, ctx_twin, 1)
	check_eq(twin.pollution.data, c.pollution.data, "pollution map continues identically")
	check_eq(twin.land_value.data, c.land_value.data, "land value map continues identically")
	check_eq(twin.crime.data, c.crime.data, "crime map continues identically")
