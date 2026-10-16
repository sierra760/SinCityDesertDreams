# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

func test_saturated_projection_cache_has_constant_eviction_work() -> void:
	TourismMarkets.clear_projection_cache()
	var count := TourismMarkets.PROJECTION_CACHE_LIMIT
	var started := Time.get_ticks_usec()
	for i in count+1024:
		var result := TourismMarkets.project([i+1,0,0,0],[1,0,0,0],1)
		check_eq(result.segments,[1,0,0,0])
	var elapsed := Time.get_ticks_usec()-started
	var work := TourismMarkets.projection_work()
	check_eq(work.entries,count)
	check_eq(int(work.get("evictions",-1)),1024,"exactly one constant-work slot replacement per saturated miss")
	var result := TourismMarkets.project([count+1024,0,0,0],[1,0,0,0],1)
	result.segments[0] = 123
	check_eq(TourismMarkets.project([count+1024,0,0,0],[1,0,0,0],1).segments,[1,0,0,0],"cache result is defensive")
	print("SATURATED_PROJECTION ",JSON.stringify({"microseconds":elapsed,"work":work}))
	TourismMarkets.clear_projection_cache()
	check_eq(TourismMarkets.projection_work().entries,0)

func test_budget_supported_forecast_caps_real_utility_constraint_and_is_pure() -> void:
	var sim := make_simulation(flat_city(),123)
	var ctx := sim._ctx
	TourismFixture.venue(ctx.city,&"arcology_last",Vector2i(10,10))
	for x in range(10): ctx.city.building.put(x,10,Buildings.ROAD_FIRST)
	TourismFixture.established_sources(sim)
	var tourism := sim.tourism()
	check_eq(tourism.supported_forecast().guests,0,"fresh venue awaits its first accepted monthly support plan")
	check_gt(tourism.supported_forecast().physical_capacity,0,"awaiting support never erases physical beds")
	var rows := tourism._state.records()
	rows[0].guests=100
	TourismFixture.segment_rows(rows)
	check_eq(tourism._state.replace_records(rows),OK)
	tourism._publish()
	ctx.city.facility(Vector2i(9,11))["output"]=17
	sim.clock.day=16
	ctx.city.day=16
	sim.advance_day()
	check_eq(tourism.report()[0].guests,20)
	var conditional := tourism.forecast()
	print("CONSTRAINED_FORECAST_BEFORE ",JSON.stringify({"guests":conditional.guests,"lodging":conditional.lodging_cents,"completed":ctx.stats.tourist_lodging_cents,"current":tourism.report()[0].current_lodging_cents}))
	check(tourism.has_method("supported_forecast"),"Budget requires useful current-supported estimate")
	if tourism.has_method("supported_forecast"):
		var before := var_to_bytes([tourism.save(),ctx.rng.state(),ctx.city.facilities])
		var supported: Dictionary=tourism.call("supported_forecast")
		check_eq(supported.guests,20)
		check_eq(supported.lodging_cents,tourism.report()[0].current_lodging_cents)
		print("SUPPORTED_FORECAST ",JSON.stringify({"conditional_guests":conditional.guests,"conditional_lodging":conditional.lodging_cents,"supported_guests":supported.guests,"supported_lodging":supported.lodging_cents,"completed_lodging":ctx.stats.tourist_lodging_cents}))
		for rate in 21:
			for rates in [[rate,7],[7,rate]]:
				var quote: Dictionary=tourism.call("supported_forecast",rates[0],rates[1])
				check(quote.guests<=20,"tax quote cannot promise unavailable capacity")
				check(quote.guests<=tourism.forecast(rates[0],rates[1]).guests,"lower demand also bounds supported estimate")
		check_eq(var_to_bytes([tourism.save(),ctx.rng.state(),ctx.city.facilities]),before,"reads cannot alter accepted state or sources")
		TourismFixture.set_served(ctx.city,Vector2i(10,10),false,true)
		tourism.reconcile_now()
		check_eq(tourism.call("supported_forecast").guests,0,"closure clears estimate")
		TourismFixture.set_served(ctx.city,Vector2i(10,10),true,true)
		tourism.reconcile_now()
		check_eq(tourism.call("supported_forecast").guests,0,"reopening waits for an accepted support plan")
		sim.advance_day() # Book the preserved completed period on day18.
		ctx.city.facility(Vector2i(9,11))["output"]=100
		ctx.clock.day=41;ctx.city.day=41
		sim.advance_day()
		check_gt(tourism.report()[0].guests,0,"new headroom is accepted on next tourism day")
		check_gt(tourism.call("supported_forecast").guests,0,"estimate reveals newly accepted headroom")
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()

func test_repeated_forecast_reads_reuse_work_and_invalidate_current_inputs() -> void:
	var fixture := preload("res://tests/test_tourism_work_budget.gd").new()
	var f: Dictionary=fixture.fixture(100)
	var t: TourismSystem=f.tourism
	var first:=t.forecast()
	var started:=Time.get_ticks_usec()
	for i in 20: check_eq(t.forecast(),first)
	print("REPEATED_FORECAST_BEFORE_US ",Time.get_ticks_usec()-started)
	check(t.has_method("forecast_work"),"repeated reads require computation cache")
	if t.has_method("forecast_work"):
		check_eq(t.call("forecast_work").computations,1)
		f.ctx.stats.tax_occupancy=20
		t.forecast()
		check_eq(t.call("forecast_work").computations,2,"tax change invalidates")
		f.city.land_value.put(0,0,123)
		t.forecast()
		check_eq(t.call("forecast_work").computations,3,"raw environment edit invalidates")
		f.ctx.clock.day=25
		t.forecast()
		check_eq(t.call("forecast_work").computations,4,"season/date invalidates")
		f.ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN]=20
		t.forecast()
		check_eq(t.call("forecast_work").computations,5,"labor invalidates")
		t.reconcile_now()
		t.forecast()
		check_eq(t.call("forecast_work").computations,6,"simulation publication invalidates")
		var mutations: Array[Callable]=[
			func(): f.ctx.stats.population+=10,
			func(): f.ctx.stats.jobs+=10,
			func(): f.ctx.stats.neighbor_populations[0]+=10,
			func(): f.ctx.stats.ordinances[&"tourist_advertising"]=true,
			func(): t._features.reputation.value_milli+=1000,
			func(): t._features.calendar.month_id+=1,
			func(): f.city.flags.put(0,0,TileFlags.POWERED),
			func(): f.city.crime.put(0,0,123),
			func(): f.city.pollution.put(0,0,123),
			func(): t._state.replace_records(t._state.records())]
		for mutation: Callable in mutations:
			var prior: int=t.call("forecast_work").computations
			mutation.call()
			t.forecast()
			check_eq(t.call("forecast_work").computations,prior+1,"population/jobs/neighbor/policy/reputation/calendar/service/environment/state changes invalidate")
	f.ctx.systems.clear()
	fixture.free()

class ReadCountState extends TourismState:
	var reads:=0
	func records() -> Array[Dictionary]:
		reads+=1
		return super.records()

func test_calendar_without_convention_host_never_walks_venues() -> void:
	var ctx:=TourismFixture.context(flat_city())
	var tourism:=TourismSystem.new()
	var state:=ReadCountState.new()
	tourism._state=state
	tourism.setup(ctx)
	check_eq(tourism.finish_restore({}),OK)
	state.reads=0
	for i in 20: tourism.calendar_report()
	check_eq(state.reads,0,"calendar with no City Hall needs no venue/business-gateway scan")


func test_market_preferences_are_computed_once_per_eligible_venue_and_kind() -> void:
	var rows: Array[Dictionary]=[]
	for i in 100:
		rows.append({"anchor":Vector2i(i,10),"key":&"arcology_boddy","appeal":70,"operating":i%2==0,"external_reachable":true})
	TourismMarkets.preference_evaluations=0
	var result:=TourismMarkets.allocate(rows,{"guest_pool":400,"day_pool":100,"access_enabled":true},7,7)
	check_eq(TourismMarkets.preference_evaluations,400,"four segment preferences once for each of two kinds and50eligible venues")
	var guests:=0
	var days:=0
	for row: Dictionary in result.rows:
		guests+=TourismMarkets.sum_counts(row.target_guest_segments)
		days+=TourismMarkets.sum_counts(row.target_day_segments)
		if not row.operating: check_eq(row.target_guest_segments,[0,0,0,0])
	check(guests<=result.guest_pool and days<=result.day_pool)
