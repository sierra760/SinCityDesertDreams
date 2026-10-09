# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Regressions from the pre-release simulation review: wear backlogs, the
## advisor's repeated story, the jobs figure between passes, the exodus on a
## total wipe-out and the weather the utilities see before it is rolled.
extends "res://tests/test_case.gd"


func _sim_from(path: String) -> Simulation:
	var result := SaveFormat.load(path)
	check(bool(result["ok"]), "loads %s" % path)
	var sim := Simulation.new()
	sim.setup(result["city"], -1, null, result["snapshot"])
	if not (result["snapshot"] as Dictionary).is_empty():
		sim.restore(result["snapshot"])
	return sim


func _advance_to_day_of_month(sim: Simulation, dom: int) -> void:
	for _i in GameClock.DAYS_PER_MONTH + 1:
		if sim.clock.day_of_month() == dom:
			return
		sim.advance_days(1)


func test_portals_alone_build_no_wear_backlog() -> void:
	var c := flat_city()
	for x in 20:
		c.building.put(10 + x, 10, Buildings.SUBWAY_PORTAL_FIRST)
	var ctx := make_context(c)
	var w := WearSystem.new()
	ctx.systems[w.key] = w
	w.setup(ctx)
	ctx.stats.set_funding(&"rail", 0)
	for _m in 120:
		ctx.events.clear()
		w.monthly(ctx)
	check_eq(w.wear_percent(&"rail"), 0, "unlosable portals accrue no wear")
	c.building.put(60, 40, Buildings.RAIL_FIRST)
	w.networks_changed(ctx, Rect2i(60, 40, 1, 1))
	ctx.events.clear()
	w.monthly(ctx)
	check_eq(c.building_at(60, 40), Buildings.RAIL_FIRST, "the next rail tile built survives its first month")
	check_eq(c.building_at(10, 10), Buildings.SUBWAY_PORTAL_FIRST, "portals are never lost")


func test_wear_resets_once_nothing_losable_remains() -> void:
	var c := flat_city()
	c.building.put(60, 40, Buildings.RAIL_FIRST)
	c.building.put(10, 10, Buildings.SUBWAY_PORTAL_FIRST)
	var ctx := make_context(c)
	var w := WearSystem.new()
	ctx.systems[w.key] = w
	w.setup(ctx)
	ctx.stats.set_funding(&"rail", 0)
	for _m in 600:
		ctx.events.clear()
		w.monthly(ctx)
	check(c.building_at(60, 40) != Buildings.RAIL_FIRST, "the lone rail tile wore out")
	check_eq(w.wear_percent(&"rail"), 0, "no backlog waits for the next rail tile")


func test_unchanged_advisor_need_is_not_news_every_month() -> void:
	var sim := _sim_from("res://assets/cities/Salton Shores.sc2d")
	var advisor_stories: Array[int] = [0]
	var seen := func(story: Dictionary) -> void:
		if story.get("kind", &"") == &"advisor_need":
			advisor_stories[0] += 1
	sim.news_published.connect(seen)
	sim.advance_months(12)
	check_gt(advisor_stories[0], 0, "the advisor is heard")
	check_lt(advisor_stories[0], 6, "the advisor's story does not lead most issues: %d" % advisor_stories[0])
	var disasters := sim.get_system(&"disasters")
	check(not (disasters.call("advice") as Array).is_empty(), "the advisor panel still lists the needs")
	sim.free()


func test_jobs_figure_is_the_same_on_day_six_and_day_fourteen() -> void:
	var sim := _sim_from("res://assets/cities/Oro Canyon.sc2d")
	sim.stats.disasters_enabled = false
	sim.advance_months(1)
	_advance_to_day_of_month(sim, 7)
	var after_zones := sim.stats.jobs
	_advance_to_day_of_month(sim, 15)
	check_gt(after_zones, 0)
	check_eq(sim.stats.jobs, after_zones, "zone and population census publish the same jobs, ports included")
	sim.free()


func test_a_city_that_loses_every_home_reports_the_exodus() -> void:
	var c := flat_city()
	for row in 5:
		for i in 20:
			c.stamp_building(10 + i, 10 + row, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	var ctx := make_context(c)
	var pop := PopulationSystem.new()
	ctx.systems = {&"population": pop}
	pop.setup(ctx)
	ctx.events.clear()
	pop.monthly(ctx)
	check_gt(ctx.stats.population, 100)
	for i in c.building.data.size():
		c.building.data[i] = Buildings.NONE
	ctx.events.clear()
	pop.monthly(ctx)
	check_eq(ctx.stats.population, 0)
	var exodus := 0
	for story in ctx.events.news:
		if story["kind"] == &"exodus":
			exodus += 1
	check_eq(exodus, 1, "everyone leaving is news once")
	ctx.events.clear()
	pop.monthly(ctx)
	for story in ctx.events.news:
		check(story["kind"] != &"exodus", "and only once")


func test_utilities_see_seasonal_weather_before_the_weather_is_rolled() -> void:
	var c := flat_city()
	var ctx := make_context(c)
	var env := EnvironmentSystem.new()
	ctx.systems = {&"environment": env}
	check(env.precipitation() < 0, "unset before setup")
	var rain := UtilityParams.weather(ctx, &"precipitation", -99)
	check(rain >= 0, "the water system is given a real month's rain, not -1")
	check_eq(rain, env.precipitation(), "the seasonal mean the environment will keep")
