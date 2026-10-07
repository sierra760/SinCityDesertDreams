# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const ServicesSystemScript := preload("res://scripts/sim/services_system.gd")
const EnvironmentSystemScript := preload("res://scripts/sim/environment_system.gd")
const ServicesParams := preload("res://scripts/sim/data/services_params.gd")

const DISTRICT := Rect2i(40, 40, 12, 12)


func make_ctx(c: City, seed_value: int = 11) -> SimContext:
	return make_context(c, seed_value)


## A flat city with a powered residential district and a dense population.
func district_city() -> City:
	var c := flat_city()
	for y in range(DISTRICT.position.y, DISTRICT.end.y):
		for x in range(DISTRICT.position.x, DISTRICT.end.x):
			c.stamp_building(x, y, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
			c.set_flag(x, y, TileFlags.POWERED | TileFlags.WATERED, true)
	for cy in range(10, 13):
		for cx in range(10, 13):
			c.density.put(cx, cy, 160)
	return c


func place(c: City, x: int, y: int, id: int, powered: bool) -> Vector2i:
	var a := c.stamp_building(x, y, id)
	var s := Buildings.size(id)
	for dy in s.y:
		for dx in s.x:
			c.set_flag(a.x + dx, a.y + dy, TileFlags.POWERED, powered)
	return a


func test_powered_police_station_raises_coverage_and_lowers_crime() -> void:
	var unguarded := district_city()
	var guarded := district_city()
	place(guarded, 44, 44, Buildings.POLICE_STATION, true)
	var services_a := ServicesSystemScript.new()
	var services_b := ServicesSystemScript.new()
	var ctx_a := make_ctx(unguarded)
	var ctx_b := make_ctx(guarded)
	services_a.monthly(ctx_a)
	services_b.monthly(ctx_b)
	check_eq(services_a.police_strength_at(45, 45), 0, "no station, no coverage")
	check_eq(services_b.police_strength_at(45, 45), 250, "full funding gives full strength")
	check_gt(services_b.police_strength_at(45, 45), services_b.police_strength_at(52, 45),
		"coverage fades with distance")
	check_gt(services_b.police_strength_at(52, 45), 0, "the next cell is still covered")
	check_eq(services_b.police_strength_at(100, 100), 0, "far tiles are not covered")
	var env_a := EnvironmentSystemScript.new()
	var env_b := EnvironmentSystemScript.new()
	env_a.monthly(ctx_a)
	env_b.monthly(ctx_b)
	check_gt(unguarded.crime_at(46, 46), 0)
	check_lt(guarded.crime_at(46, 46), unguarded.crime_at(46, 46), "the station lowers crime")


func test_unpowered_station_has_half_strength() -> void:
	var c := district_city()
	place(c, 44, 44, Buildings.POLICE_STATION, false)
	var services := ServicesSystemScript.new()
	services.monthly(make_ctx(c))
	check_eq(services.police_strength_at(45, 45), 125)


func test_funding_shrinks_coverage() -> void:
	var c := district_city()
	place(c, 44, 44, Buildings.POLICE_STATION, true)
	var services := ServicesSystemScript.new()
	var ctx := make_ctx(c)
	services.monthly(ctx)
	var full_centre := services.police_strength_at(45, 45)
	var full_edge := services.police_strength_at(45, 56)
	check_gt(full_edge, 0, "full funding reaches three cells out")
	ctx.stats.set_funding(&"police", 40)
	services.monthly(ctx)
	check_lt(services.police_strength_at(45, 45), full_centre, "less funding, less strength")
	check_eq(services.police_strength_at(45, 56), 0, "less funding, shorter reach")
	ctx.stats.set_funding(&"police", 0)
	services.monthly(ctx)
	check_eq(services.police_strength_at(45, 45), 0, "no funding, no coverage")


func test_fire_station_and_volunteers() -> void:
	var c := district_city()
	place(c, 40, 40, Buildings.FIRE_STATION, true)
	var services := ServicesSystemScript.new()
	var ctx := make_ctx(c)
	services.monthly(ctx)
	check_eq(services.fire_strength_at(41, 41), 250)
	check_eq(services.fire_strength_at(100, 100), 0)
	ctx.stats.ordinances[&"volunteer_fire"] = true
	services.monthly(ctx)
	check_eq(services.fire_strength_at(100, 100), ServicesParams.VOLUNTEER_FIRE_COVERAGE,
		"volunteers cover the whole map a little")
	check_eq(services.fire_strength_at(41, 41), 255, "the station cell caps at 255")


func test_prison_over_capacity_produces_escapes() -> void:
	var c := district_city()
	var anchor := place(c, 60, 60, Buildings.PRISON, true)
	c.add_facility(anchor, {"key": &"prison", "built_day": 0})
	c.crime.fill(255)
	var services := ServicesSystemScript.new()
	var ctx := make_ctx(c)
	ctx.stats.set_funding(&"police", 0)
	services.monthly(ctx)
	var report: Dictionary = services.prison_report()
	check_eq(int(report["prisons"]), 1)
	check_gt(int(report["inmates"]), 0, "arrests fill the prison")
	check_gt(int(report["utilization"]), ServicesParams.ESCAPE_UTILIZATION, "the prison is overfull")
	check_gt(int(report["escapes"]), 0, "inmates escape")
	check_eq(int(report["modifier"]), 0, "an overfull prison gives no police bonus")
	var escape_news := 0
	for story in ctx.events.news:
		if story["kind"] == &"prison_escape":
			escape_news += 1
			check_eq(int(story["args"]["x"]), anchor.x)
	check_eq(escape_news, 1, "one escape story per prison")
	var facility := c.facility(anchor)
	check_eq(int(facility["inmates"]), int(report["inmates"]), "the facility record mirrors the report")
	services.yearly(ctx)
	check_eq(int(services.prison_report()["escapes"]), 0, "escape counts reset each year")


func test_prison_escape_raises_nearby_crime() -> void:
	var c := district_city()
	place(c, 52, 44, Buildings.PRISON, true)
	c.crime.fill(200)
	var services := ServicesSystemScript.new()
	var ctx := make_ctx(c)
	ctx.stats.set_funding(&"police", 0)
	services.monthly(ctx)
	check_gt(c.crime_at(50, 45), 200, "developed blocks near the prison gain crime")
	check_eq(c.crime_at(5, 5), 200, "distant blocks are untouched")


func test_prison_within_capacity_boosts_police() -> void:
	var without := district_city()
	var with_prison := district_city()
	for c in [without, with_prison]:
		place(c, 44, 44, Buildings.POLICE_STATION, true)
		c.crime.fill(20)
	place(with_prison, 60, 60, Buildings.PRISON, true)
	var services_a := ServicesSystemScript.new()
	var services_b := ServicesSystemScript.new()
	services_a.monthly(make_ctx(without))
	services_b.monthly(make_ctx(with_prison))
	var report: Dictionary = services_b.prison_report()
	check_eq(int(report["guards"]), 300)
	check_lt(int(report["utilization"]), ServicesParams.STRAINED_UTILIZATION)
	check_eq(int(report["modifier"]), 1)
	check_eq(int(report["escapes"]), 0)
	check_gt(services_b.police_strength_at(45, 45), services_a.police_strength_at(45, 45),
		"a working prison strengthens police coverage")


func test_service_counts() -> void:
	var c := district_city()
	place(c, 60, 40, Buildings.HOSPITAL, true)
	place(c, 64, 40, Buildings.HOSPITAL, false)
	place(c, 60, 44, Buildings.SCHOOL, true)
	place(c, 60, 48, Buildings.COLLEGE, true)
	place(c, 66, 48, Buildings.LIBRARY, true)
	var services := ServicesSystemScript.new()
	var ctx := make_ctx(c)
	ctx.stats.set_funding(&"health", 70)
	services.setup(ctx)
	var counts: Dictionary = services.service_counts()
	check_eq(int(counts[&"hospital"]["count"]), 2)
	check_eq(int(counts[&"hospital"]["powered"]), 1)
	check_eq(int(counts[&"hospital"]["funding"]), 70)
	check_eq(int(counts[&"school"]["count"]), 1)
	check_eq(int(counts[&"college"]["count"]), 1)
	check_eq(int(counts[&"library"]["count"]), 1)
	check_eq(int(counts[&"museum"]["count"]), 0)
	place(c, 66, 52, Buildings.MUSEUM, true)
	services.networks_changed(ctx, Rect2i(66, 52, 3, 3))
	check_eq(int(services.service_counts()[&"museum"]["count"]), 1, "construction refreshes the counts")


func test_save_load_round_trip() -> void:
	var c := district_city()
	place(c, 44, 44, Buildings.POLICE_STATION, true)
	place(c, 60, 60, Buildings.PRISON, true)
	c.crime.fill(60)
	var services := ServicesSystemScript.new()
	var ctx := make_ctx(c)
	services.monthly(ctx)
	services.monthly(ctx)
	var json := JSON.stringify(services.save())
	var back: Dictionary = JSON.parse_string(json)
	var restored := ServicesSystemScript.new()
	restored.load(back)
	var before: Dictionary = services.prison_report()
	var after: Dictionary = restored.prison_report()
	check_gt(int(before["inmates"]), 0)
	check_eq(int(after["inmates"]), int(before["inmates"]))
	check_eq(int(after["utilization"]), int(before["utilization"]))
	check_eq(int(after["modifier"]), int(before["modifier"]))
	check_eq(int(after["prisons"]), 1)
	var twin := c.duplicate_city()
	var ctx_twin := make_ctx(twin)
	services.monthly(ctx)
	restored.monthly(ctx_twin)
	check_eq(int(restored.prison_report()["inmates"]), int(services.prison_report()["inmates"]),
		"the restored prison continues identically")
	check_eq(twin.police.data, c.police.data, "coverage rebuilds identically")
