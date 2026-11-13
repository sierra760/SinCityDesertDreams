# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Farm employment settles at what the city supports: farms open only while
## the city is short of farm work and close a few at a time when it has too
## much, instead of the whole sector failing in the same month.
extends "res://tests/test_case.gd"

const FARMS := 40


## A row of one-tile vegetable plots along a road, all with water.
func _farm_row(active: bool) -> Dictionary:
	var c := flat_city()
	c.sea_level = 30
	for x in range(20, 20 + FARMS):
		c.building.put(x, 9, Buildings.ROAD_FIRST)
		var id := AgricultureParams.building_id(&"vegetables") if active else AgricultureParams.state_id(&"prepared", 1)
		c.stamp_building(x, 10, id, Zones.AGR_LOW)
	for x in range(20, 20 + FARMS, 4):
		c.stamp_building(x, 11, Buildings.WATER_PUMP)
	c.stamp_building(10, 20, Buildings.COAL_PLANT)
	for x in range(14, 20 + FARMS):
		c.stamp_building(x, 12, Buildings.POWER_LINE_FIRST)
	for y in range(13, 21):
		c.stamp_building(14, y, Buildings.POWER_LINE_FIRST)
	var ctx := make_context(c)
	var power := PowerSystem.new()
	var water := WaterSystem.new()
	var ag := AgricultureSystem.new()
	ctx.systems[&"power"] = power
	ctx.systems[&"water"] = water
	ctx.systems[&"agriculture"] = ag
	power.setup(ctx)
	water.setup(ctx)
	ag.setup(ctx)
	return {"city": c, "ctx": ctx, "ag": ag}


func _month(f: Dictionary) -> void:
	f.ag.monthly(f.ctx, 0)
	f.ag.monthly(f.ctx, 1)
	f.ctx.clock.day += GameClock.DAYS_PER_MONTH


func _set_raw(f: Dictionary, raw: int) -> void:
	var data: Dictionary = f.ag.save()
	data.raw_demand = raw
	f.ag.load(data)


func _active(f: Dictionary) -> int:
	var n := 0
	for lot: Dictionary in f.ag.current_lots():
		if lot.state == &"active": n += 1
	return n


func test_fixture_farms_are_served() -> void:
	var f := _farm_row(true)
	check_eq(_active(f), FARMS)
	check_eq(f.ag.jobs(), FARMS * 4)
	_month(f)
	for lot: Dictionary in f.ag.current_lots():
		check_eq(f.ag.inspect_tile(lot.anchor).water_supplied, true, "watered")
	f.ctx.systems.clear()


func test_farms_stop_opening_once_the_city_has_enough_farm_work() -> void:
	var f := _farm_row(false)
	# No residents: the city supports the base number of farm jobs.
	var target := AgricultureParams.TARGET_BASE_JOBS
	var most := 0
	for _i in 12:
		_month(f)
		most = maxi(most, f.ag.jobs())
	check_ge(f.ag.jobs(), target, "farms open while the city is short of farm work")
	check_lt(most, target + 4, "no farm opens once the target is met")
	var waiting: Dictionary = {}
	for lot: Dictionary in f.ag.current_lots():
		if lot.state != &"active": waiting = lot
	check(not waiting.is_empty(), "the rest keep waiting")
	if not waiting.is_empty():
		check_eq(f.ag.inspect_tile(waiting.anchor).blocked_reason, "The city has enough farm work for now.")
	f.ctx.systems.clear()


func test_surplus_farms_close_a_few_at_a_time_and_the_rest_stay_open() -> void:
	var f := _farm_row(true)
	var lowest := FARMS * 4
	var history: Array[int] = []
	for _i in 60:
		_month(f)
		history.append(f.ag.jobs())
		lowest = mini(lowest, f.ag.jobs())
	check_gt(lowest, 0, "the sector never collapses: %s" % str(history))
	check_ge(history[-1], AgricultureParams.TARGET_BASE_JOBS, "it settles at what the city supports: %s" % str(history))
	check_lt(history[-1], AgricultureParams.TARGET_BASE_JOBS + 4, "the surplus is gone: %s" % str(history))
	var late := history.slice(36)
	check_eq(late.min(), late.max(), "and it stops changing: %s" % str(late))
	f.ctx.systems.clear()


func test_farms_at_the_supported_level_report_no_demand_problem() -> void:
	var f := _farm_row(true)
	for _i in 60:
		_month(f)
	for lot: Dictionary in f.ag.current_lots():
		if lot.state == &"active":
			check_eq(f.ag.inspect_tile(lot.anchor).blocked_reason, "", "a supported farm has nothing to report")
	f.ctx.systems.clear()


func test_every_farm_closes_when_demand_is_absent() -> void:
	var f := _farm_row(true)
	_set_raw(f, -AgricultureParams.DEMAND_RAW_LIMIT)
	f.ctx.stats.tax_agricultural = 20
	_month(f)
	_month(f)
	check_eq(_active(f), FARMS, "two failed months are tolerated")
	_month(f)
	check_eq(_active(f), 0, "dormant on the third")
	check_eq(f.ag.jobs(), 0)
	f.ctx.systems.clear()


func test_heavy_tax_closes_farms_gradually() -> void:
	var f := _farm_row(true)
	f.ctx.stats.population = 6000
	f.ctx.stats.tax_agricultural = 20
	var history: Array[int] = []
	for _i in 24:
		_month(f)
		history.append(_active(f))
	check_eq(history[-1], 0, "a punishing tax ends farming: %s" % str(history))
	var steps := {}
	for n in history: steps[n] = true
	check_gt(steps.size(), 3, "the farms do not all fail in one month: %s" % str(history))
	f.ctx.systems.clear()


func test_bonanza_gap_keeps_farming_for_five_years() -> void:
	var loaded := SaveFormat.load("res://assets/cities/Bonanza Gap.sc2d")
	check(bool(loaded.ok), "city loads")
	if not bool(loaded.ok): return
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(loaded.city, -1, null, loaded.snapshot)
	check_eq(sim.restore(loaded.snapshot), OK)
	sim.stats.disasters_enabled = false
	var history: Array[int] = []
	for _m in 60:
		for _d in GameClock.DAYS_PER_MONTH:
			if sim.budget_review_pending: sim.finish_budget_review()
			sim.advance_day()
		history.append(sim.stats.agricultural_jobs)
	check_gt(history.min(), 0, "farm jobs never reach zero: %s" % str(history))
	var late := history.slice(36)
	check_lt(late.max() - late.min(), 40, "employment is steady in the later years: %s" % str(late))
	sim.free()
