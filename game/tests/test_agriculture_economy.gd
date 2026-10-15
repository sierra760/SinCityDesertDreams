# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"

const ScanTables := preload("res://scripts/sim/data/public_scan_tables.gd")
const ParcelFixture := preload("res://tests/helpers/agricultural_parcel_fixture.gd")
var _contexts: Array[SimContext] = []

func after_each() -> void:
	for ctx in _contexts: ctx.systems.clear()
	_contexts.clear()

func fixture(archetype: StringName = &"greenhouse", state: StringName = &"active") -> SimContext:
	var city := flat_city(10000)
	var id := AgricultureParams.building_id(archetype)
	if state != &"active": id = AgricultureParams.state_id(state, Buildings.size(id).x)
	city.stamp_building(20, 20, id, Zones.AGR_HIGH if archetype in AgricultureParams.HIGH_ARCHETYPES else Zones.AGR_LOW)
	var ctx := make_context(city, 7)
	_contexts.append(ctx)
	var agriculture := AgricultureSystem.new()
	ctx.systems[&"agriculture"] = agriculture
	agriculture.setup(ctx)
	return ctx

func zones_for(ctx: SimContext) -> ZoneSystem:
	var zones := ZoneSystem.new()
	ctx.systems[&"zones"] = zones
	zones.setup(ctx)
	return zones

func test_census_replaces_active_jobs_once_and_excludes_dormant() -> void:
	for state: StringName in [&"active", &"prepared", &"dormant"]:
		var ctx := fixture(&"greenhouse", state)
		ctx.city.stamp_building(10, 10, Buildings.COM_1X1_FIRST, Zones.COM_LOW)
		var zones := zones_for(ctx)
		var expected := ZoneParams.jobs_of(Buildings.COM_1X1_FIRST) + (10 if state == &"active" else 0)
		check_eq(ctx.stats.jobs, expected, "setup shared jobs")
		zones.monthly(ctx, 0)
		check_eq(ctx.stats.jobs, expected, "first census replacement")
		zones.monthly(ctx, 1)
		var rci := (zones.occupied_units().y + zones.occupied_units().z) * ZoneParams.PEOPLE_PER_UNIT
		check_eq(ctx.stats.jobs, rci + (10 if state == &"active" else 0), "second census replacement")
		var pop := PopulationSystem.new()
		pop.setup(ctx)
		pop._run_census(ctx)
		check_eq(ctx.stats.jobs, pop.commercial_units() + pop.industrial_units() + (10 if state == &"active" else 0))
		pop._run_census(ctx)
		check_eq(ctx.stats.jobs, pop.commercial_units() + pop.industrial_units() + (10 if state == &"active" else 0), "no double addition")

func test_agriculture_phase_endpoints_update_jobs_and_removal() -> void:
	var ctx := fixture()
	var zones := zones_for(ctx)
	# Existing active farm tolerates two failed service months, then goes dormant.
	for m in 3:
		ctx.clock.day = m * GameClock.DAYS_PER_MONTH + 5
		zones.monthly(ctx, 0)
		ctx.system(&"agriculture").monthly(ctx, 0)
		check_eq(ctx.stats.jobs, 10 if m < 2 else 0, "day 5 completed growth")
		zones.monthly(ctx, 1)
		ctx.system(&"agriculture").monthly(ctx, 1)
		check_eq(ctx.stats.jobs, 10 if m < 2 else 0, "day 6 completed growth")
	var ag := ctx.system(&"agriculture") as AgricultureSystem
	ctx.city.stamp_building(20, 20, AgricultureParams.building_id(&"greenhouse"), Zones.AGR_HIGH)
	ag.networks_changed(ctx, Rect2i(20, 20, 1, 1))
	check_eq(ctx.stats.jobs, 10, "new active job contribution")
	ctx.city.building.put(20, 20, Buildings.NONE)
	ag.networks_changed(ctx, Rect2i(20, 20, 1, 1))
	check_eq(ctx.stats.jobs, 0, "last farm removal clears jobs")

func test_housing_pull_and_industrial_labor_stay_separate() -> void:
	var base := fixture(&"nursery", &"dormant")
	var active := fixture(&"nursery")
	for ctx in [base, active]:
		# Five nurseries supply 120 jobs, exceeding the unchanged ten-unit
		# residential target floor; a single small farm sits below that floor.
		for x in [24, 28, 32, 36]:
			var id := AgricultureParams.building_id(&"nursery") if ctx == active else AgricultureParams.state_id(&"dormant", 2)
			ctx.city.stamp_building(x, 20, id, Zones.AGR_HIGH)
		for x in 15: ctx.city.stamp_building(40 + x, 40, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
		var zones := zones_for(ctx)
		zones._raw_demand = Vector3i.ZERO
		zones._update_demand(ctx)
	var z0 := base.system(&"zones") as ZoneSystem
	var z1 := active.system(&"zones") as ZoneSystem
	check_gt(z1.raw_demand().x, z0.raw_demand().x, "farm jobs attract homes")
	check_eq(z1.raw_demand().y, z0.raw_demand().y, "farm labor does not become industrial labor")
	check_eq(z1.raw_demand().z, z0.raw_demand().z)
	check_eq(z1.occupied_units(), z0.occupied_units(), "RCI remains three dimensions")

func test_native_and_fallback_capacity_and_commutes_require_active_jobs() -> void:
	for state: StringName in [&"active", &"prepared", &"dormant"]:
		var ctx := fixture(&"greenhouse", state)
		var id := ctx.city.building_at(20, 20)
		for native in [true, false]:
			check_eq(ScanTables.capacities(native)[id], 10 if state == &"active" else 0)
		check_eq(TransportParams.is_destination(id), state == &"active")
		ctx.city.stamp_building(10, 19, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
		for x in range(10, 21): ctx.city.building.put(x, 20 - 1, Buildings.ROAD_FIRST)
		# Move house immediately above the road.
		ctx.city.stamp_building(10, 18, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
		var transport := TransportSystem.new()
		transport.setup(ctx)
		transport.monthly(ctx)
		check_eq(transport.trips_completed(), 1 if state == &"active" else 0)

func test_flexible_markers_have_no_per_cell_capacity_or_legacy_destination() -> void:
	for id in range(282,289):
		for native in [true,false]: check_eq(ScanTables.capacities(native)[id],0)
		check(not TransportParams.is_destination(id))

func test_flexible_parcels_replace_census_share_once_and_keep_assessment() -> void:
	var city := flat_city()
	for row in [[1,20],[2,24]]:
		var m := ParcelFixture.mask([[row[1],20]])
		ParcelFixture.zone(city,m)
		check_eq(city.agricultural_parcels.put(city,ParcelFixture.record(row[0],m,&"alfalfa",&"active")),OK)
	city.stamp_building(10,10,Buildings.COM_1X1_FIRST,Zones.COM_LOW)
	var ctx := make_context(city)
	_contexts.append(ctx)
	var ag := AgricultureSystem.new()
	ctx.systems[&"agriculture"] = ag
	ag.setup(ctx)
	check_eq(ag.jobs(),3)
	check_eq(ag.assessed_value(),300)
	check_eq(ctx.stats.agricultural_jobs,3)
	check_eq(ctx.stats.agricultural_lots,2)
	var pop := PopulationSystem.new()
	pop.setup(ctx)
	for _i in 3:
		pop._run_census(ctx)
		check_eq(ctx.stats.jobs,pop.commercial_units()+pop.industrial_units()+3)
		ag.networks_changed(ctx,Rect2i(20,20,5,1))
		check_eq(ctx.stats.agricultural_jobs,3)
		check_eq(ctx.stats.jobs,pop.commercial_units()+pop.industrial_units()+3)
	check_eq(ag.parcel_jobs().values().reduce(func(a,b): return a+b,0),3)
	check_eq(ag.inspect_tile(Vector2i(20,20)).jobs,2)
	check_eq(ag.inspect_tile(Vector2i(24,20)).jobs,1)

func test_transport_reaches_assigned_member_destination_only() -> void:
	for state in [&"active",&"prepared"]:
		var c := flat_city()
		var m := ParcelFixture.mask([[20,20],[21,20]])
		ParcelFixture.zone(c,m)
		check_eq(c.agricultural_parcels.put(c,ParcelFixture.record(1,m,&"alfalfa",state)),OK)
		c.stamp_building(10,18,Buildings.RES_1X1_FIRST,Zones.RES_LOW)
		for x in range(10,21): c.building.put(x,19,Buildings.ROAD_FIRST)
		var ctx := make_context(c)
		var transport := TransportSystem.new()
		transport.setup(ctx)
		transport.monthly(ctx)
		check_eq(transport.trips_completed(),1 if state == &"active" else 0)
		check_eq(transport.trace_trip(c,Vector2i(10,18)).reached,state == &"active")

func test_transport_selects_accessible_member_when_first_has_no_road() -> void:
	var c := flat_city()
	var m := ParcelFixture.mask([[20,20],[21,20],[22,20],[23,20],[24,20]])
	ParcelFixture.zone(c,m)
	check_eq(c.agricultural_parcels.put(c,ParcelFixture.record(1,m,&"grain",&"active")),OK)
	c.stamp_building(24,17,Buildings.RES_1X1_FIRST,Zones.RES_LOW)
	c.building.put(24,18,Buildings.ROAD_FIRST)
	c.building.put(24,19,Buildings.ROAD_FIRST)
	var ctx := make_context(c)
	var transport := TransportSystem.new()
	transport.setup(ctx)
	transport.monthly(ctx)
	check_eq(transport.trips_completed(),1,"route reaches the member with road frontage")
	check_eq(transport._arrival_tile,24+20*128,"arrival stays inside the parcel")
	var destinations := 0
	for v in transport._parcel_destination: destinations += v
	check_eq(destinations,1,"one allocated parcel contributes one destination")

func test_separate_assessment_rates_accrual_and_settlement() -> void:
	for rate in [0, 7, 20]:
		var ctx := fixture()
		var ag := ctx.system(&"agriculture") as AgricultureSystem
		var budget := BudgetSystem.new()
		ctx.systems[&"budget"] = budget
		budget.setup(ctx)
		ctx.stats.tax_agricultural = rate
		check_eq(ag.assessed_value(), 1000)
		check_eq(budget._city_value(ctx.city), 1000, "fallback city assessment includes farm jobs")
		check_eq(int(budget._yearly_cents(ctx).get(&"taxes_agricultural", -1)), rate * 1000)
		check_eq(budget.estimated_income(), rate * 10)
		check_eq(ctx.stats.tax_industrial, 7)
		for m in 12:
			budget.monthly(ctx)
			check_eq(ctx.city.funds, 10000, "no direct farm or monthly credit")
			check_eq(int(ctx.stats.ledger.get(&"taxes_agricultural", -1)), rate * 1000 * (m + 1) / 1200)
		budget.yearly(ctx)
		check_eq(ctx.city.funds, 10000 + rate * 10)
		check_eq(int(ctx.stats.last_year_ledger.get(&"taxes_agricultural", -1)), rate * 10)
		check_eq(int(budget.review_summary().income), rate * 10)

func test_tax_restore_bounds_preserve_legacy_rates() -> void:
	for rate in [-99, 0, 7, 20, 999]:
		var stats := CityStats.new()
		stats.from_dict({"tax_agricultural": rate, "tax_industrial": 24})
		check_eq(stats.tax_agricultural, clampi(rate, 0, 20))
		check_eq(stats.tax_industrial, 24)

func test_environment_emits_once_per_anchor_without_urban_density() -> void:
	var cases := {&"vegetables": 1, &"alfalfa": 1, &"grain": 1, &"market_garden": 1,
		&"cattle_range": 0, &"sheep_pasture": 0, &"greenhouse": 0, &"nursery": 0, &"dairy": 4, &"feedlot": 6}
	for archetype: StringName in cases:
		var ctx := fixture(archetype)
		var environment := EnvironmentSystem.new()
		environment.setup(ctx)
		environment._scan_tiles(ctx)
		var emissions := 0
		for value in environment._block_emission: emissions += value
		check_eq(emissions, cases[archetype], "one emission assessment per anchor")
		check_eq(environment.developed_blocks(), 0, "agricultural acreage is not urban density")
		check_eq(AgricultureParams.pollution_of(AgricultureParams.building_id(&"feedlot")), 6)

func test_flexible_emissions_accumulate_by_half_resolution_block() -> void:
	var m := ParcelFixture.mask([[20,20],[21,20],[20,21],[21,21]])
	for split in [false,true]:
		var c := flat_city()
		ParcelFixture.zone(c,m)
		if split:
			for n in m.size():
				var one := PackedInt32Array([m[n]])
				check_eq(c.agricultural_parcels.put(c,ParcelFixture.record(n+1,one,&"alfalfa",&"active")),OK)
		else:
			check_eq(c.agricultural_parcels.put(c,ParcelFixture.record(1,m,&"alfalfa",&"active")),OK)
		var ctx := make_context(c)
		var env := EnvironmentSystem.new()
		env._scan_tiles(ctx)
		check_eq(env._block_emission[10*City.HALF+10],1,"four member quarters round together once")
		check_eq(env._block_emission[10*City.HALF+11],0,"unrelated half block remains clean")

func test_agricultural_value_and_statistics_leave_industry_mix_unchanged() -> void:
	var ctx := fixture()
	var economy := EconomySystem.new()
	ctx.systems[&"economy"] = economy
	economy.setup(ctx)
	var base := fixture(&"greenhouse", &"dormant")
	var baseline_economy := EconomySystem.new()
	base.systems[&"economy"] = baseline_economy
	baseline_economy.setup(base)
	baseline_economy.monthly(base)
	var shares := base.stats.sector_shares.duplicate()
	var taxes := base.stats.sector_taxes.duplicate()
	economy._assess_city(ctx)
	check_eq(economy.assessed_value(), 1000)
	check_eq(economy._industrial_units(ctx), 0)
	ctx.stats.tax_agricultural = 20
	economy.monthly(ctx)
	check_eq(ctx.stats.sector_shares, shares)
	check_eq(ctx.stats.sector_taxes, taxes)
	var statistics := preload("res://scripts/sim/statistics_system.gd").new()
	statistics.setup(ctx)
	statistics.monthly(ctx)
	for series: StringName in [&"demand_agricultural", &"agricultural_jobs", &"agricultural_lots", &"taxes_agricultural"]:
		check(statistics.names().has(series), "published graph series")
		check_eq(statistics.series(series, 1).size(), 1)
	check_eq(statistics.series(&"agricultural_jobs", 1), PackedInt32Array([10]))
	check_eq(statistics.series(&"agricultural_lots", 1), PackedInt32Array([1]))

func test_zero_agriculture_phase_endpoints_preserve_rci_timing_exactly() -> void:
	var contexts: Array[SimContext] = []
	for enabled in [false, true]:
		var city := flat_city()
		for x in range(10, 20):
			city.stamp_building(x, 10, Buildings.COM_1X1_FIRST, Zones.COM_LOW)
		var ctx := make_context(city, 987)
		_contexts.append(ctx)
		if enabled:
			var ag := AgricultureSystem.new()
			ctx.systems[&"agriculture"] = ag
			ag.setup(ctx)
		zones_for(ctx)
		contexts.append(ctx)
	for phase in 2:
		for ctx in contexts:
			ctx.system(&"zones").monthly(ctx, phase)
			if ctx.system(&"agriculture") != null: ctx.system(&"agriculture").monthly(ctx, phase)
		check_eq(contexts[1].stats.jobs, contexts[0].stats.jobs, "legacy jobs timing")
		check_eq(contexts[1].stats.demand, contexts[0].stats.demand)
		check_eq(contexts[1].city.building.data, contexts[0].city.building.data)
		check_eq(contexts[1].city.density.data, contexts[0].city.density.data)
		check_eq(contexts[1].rng.state(), contexts[0].rng.state())

func test_growth_activation_and_save_restore_replace_jobs_once() -> void:
	var ctx := fixture(&"vegetables", &"prepared")
	var ag := ctx.system(&"agriculture") as AgricultureSystem
	var zones := zones_for(ctx)
	ctx.city.building.put(20, 19, Buildings.ROAD_FIRST)
	ctx.city.stamp_building(16, 20, Buildings.SOLAR_PLANT)
	ctx.city.stamp_building(15, 20, Buildings.WIND_PLANT)
	ctx.city.stamp_building(21, 20, Buildings.WATER_PUMP)
	ctx.city.sea_level = 30
	var power := PowerSystem.new()
	var water := WaterSystem.new()
	ctx.systems[&"power"] = power
	ctx.systems[&"water"] = water
	power.setup(ctx)
	water.setup(ctx)
	zones.monthly(ctx, 0)
	ag.monthly(ctx, 0)
	check_eq(ag.inspect_tile(Vector2i(20, 20)).state, &"active")
	check_eq(ctx.stats.jobs, 4, "new jobs are present at growth endpoint")
	var saved := ag.save()
	ag.load(saved)
	ag.load(saved)
	check_eq(ctx.stats.jobs, 4, "reload cannot double farm jobs")
	var population := PopulationSystem.new()
	ctx.city.day = 20
	population.setup(ctx)
	check_eq(ctx.stats.jobs, 4, "population setup counts farm jobs once")
	ctx.systems.erase(&"zones")
	population._run_census(ctx)
	check_eq(ctx.stats.jobs, 4, "population fallback counts farm jobs once")

func test_tax_carry_and_history_preserve_receipts() -> void:
	var ctx := fixture()
	var budget := BudgetSystem.new()
	budget.setup(ctx)
	for _m in 5: budget.monthly(ctx)
	var saved := budget.save()
	var restored := BudgetSystem.new()
	restored.setup(ctx)
	restored.load(saved)
	for _m in 7: restored.monthly(ctx)
	check_eq(int(ctx.stats.ledger[&"taxes_agricultural"]), 70)
	var statistics := preload("res://scripts/sim/statistics_system.gd").new()
	statistics.setup(ctx)
	statistics.monthly(ctx)
	check_eq(statistics.series(&"taxes_agricultural", 1), PackedInt32Array([70]))
	restored.yearly(ctx)
	check_eq(ctx.city.funds, 10070)
	check_eq(int(ctx.stats.last_year_ledger[&"taxes_agricultural"]), 70)
	check_eq(int(ctx.stats.ledger[&"taxes_agricultural"]), 0)

func test_simulation_restore_keeps_saved_growth_census_before_zone_load() -> void:
	var city := flat_city()
	city.stamp_building(20, 20, AgricultureParams.building_id(&"greenhouse"), Zones.AGR_HIGH)
	city.stamp_building(10, 10, Buildings.COM_1X1_FIRST, Zones.COM_LOW)
	var sim := make_simulation(city, 71)
	check_eq(sim.stats.jobs, 20)
	# RCI's first growth phase can remove a shop after taking its census.
	# Saving then legitimately retains that census until the second phase.
	city.building.put(10, 10, Buildings.NONE)
	var saved := sim.snapshot()
	var restored_city := flat_city()
	restored_city.stamp_building(20, 20, AgricultureParams.building_id(&"greenhouse"), Zones.AGR_HIGH)
	var restored := make_simulation(restored_city, 71)
	check_eq(restored.stats.jobs, 10, "setup sees the current map")
	restored.restore(saved)
	check_eq(restored.stats.jobs, 20, "restore preserves saved RCI census plus current farm jobs")
	restored.restore(saved)
	check_eq(restored.stats.jobs, 20, "repeat restore remains idempotent")
	var missing_system := saved.duplicate(true)
	missing_system.systems.erase("agriculture")
	restored.restore(missing_system)
	check_eq(restored.stats.jobs, 20, "missing agriculture state reconstructs current contribution once")
	var agriculture := restored.get_system(&"agriculture") as AgricultureSystem
	agriculture.load({})
	agriculture.load({})
	check_eq(restored.stats.jobs, 20)
	sim.free()
	restored.free()

func test_newer_population_census_survives_agriculture_network_publication() -> void:
	var ctx := fixture()
	ctx.city.stamp_building(10, 10, Buildings.COM_1X1_FIRST, Zones.COM_LOW)
	zones_for(ctx)
	var population := PopulationSystem.new()
	ctx.systems[&"population"] = population
	population.setup(ctx)
	var agriculture := ctx.system(&"agriculture") as AgricultureSystem
	check_eq(ctx.stats.jobs, 20, "initial farm plus shop")
	ctx.city.building.put(10, 10, Buildings.NONE)
	population._run_census(ctx)
	check_eq(ctx.stats.jobs, 10, "newer population census excludes demolished shop")
	agriculture.networks_changed(ctx, Rect2i(40, 40, 1, 1))
	check_eq(ctx.stats.jobs, 10, "unrelated network notification preserves latest RCI jobs")
	ctx.city.building.put(20, 20, Buildings.NONE)
	agriculture.networks_changed(ctx, Rect2i(20, 20, 1, 1))
	check_eq(ctx.stats.jobs, 0, "last farm removal cannot resurrect stale RCI jobs")

func test_census_observing_farm_removal_prevents_double_subtraction() -> void:
	for census: StringName in [&"population", &"zones"]:
		var ctx := fixture()
		ctx.city.stamp_building(10, 10, Buildings.COM_1X1_FIRST, Zones.COM_LOW)
		var zones := zones_for(ctx)
		var population := PopulationSystem.new()
		population.setup(ctx)
		var agriculture := ctx.system(&"agriculture") as AgricultureSystem
		ctx.city.building.put(20, 20, Buildings.NONE)
		if census == &"population":
			population._run_census(ctx)
		else:
			zones.setup(ctx)
		check_eq(ctx.stats.jobs, 10, "replacement census contains only current shop jobs")
		check_eq(ctx.stats.agricultural_jobs, 0, "published farm share agrees with replacement census")
		agriculture.networks_changed(ctx, Rect2i(40, 40, 1, 1))
		check_eq(ctx.stats.jobs, 10, "farm removal already counted must not subtract twice")
		agriculture.networks_changed(ctx, Rect2i(20, 20, 1, 1))
		check_eq(ctx.stats.jobs, 10, "repeated notifications keep the same contribution")

func test_legacy_population_restore_keeps_job_total_and_farm_share_together() -> void:
	var ctx := fixture()
	ctx.city.stamp_building(10, 10, Buildings.COM_1X1_FIRST, Zones.COM_LOW)
	zones_for(ctx)
	var population := PopulationSystem.new()
	population.setup(ctx)
	var agriculture := ctx.system(&"agriculture") as AgricultureSystem
	ctx.city.building.put(20, 20, Buildings.NONE)
	# With no residents, the legacy load branch rolls its provisional census
	# back to the prior shared figures. Its included farm share must roll back too.
	population.load({})
	check_eq(ctx.stats.jobs, 20, "legacy no-resident branch retains prior total")
	check_eq(ctx.stats.agricultural_jobs, 10, "retained total includes the prior farm share")
	agriculture.networks_changed(ctx, Rect2i(20, 20, 1, 1))
	check_eq(ctx.stats.jobs, 10, "publication replaces that retained share exactly once")


func test_disconnected_frontages_alias_one_parcel_capacity() -> void:
	var c := flat_city()
	var members := ParcelFixture.mask([[20,20],[21,20],[22,20],[23,20],[24,20]])
	ParcelFixture.zone(c,members)
	check_eq(c.agricultural_parcels.put(c,ParcelFixture.record(1,members,&"grain",&"active")),OK)
	for x in [19,25]:
		c.stamp_building(x,18,Buildings.RES_1X1_FIRST,Zones.RES_LOW)
		c.building.put(x,19,Buildings.ROAD_FIRST)
		c.building.put(x,20,Buildings.ROAD_FIRST)
	var ctx := make_context(c)
	_contexts.append(ctx)
	var ag := AgricultureSystem.new()
	ctx.systems[&"agriculture"] = ag
	ag.setup(ctx)
	var transport := TransportSystem.new()
	transport.setup(ctx)
	for origin in [Vector2i(19,18),Vector2i(25,18)]:
		check(transport.trace_trip(c,origin).reached,"both disconnected road approaches reach the same field")
		check(members.has(transport._arrival_tile),"arrival is an actual productive member")
	transport.monthly(ctx)
	check_eq(transport.trips_completed(),2)
	check_eq(ag.jobs(),5,"frontages do not duplicate jobs")
	check_eq(ag.parcel_jobs(),{1:5},"capacity has one parcel owner")
	var destinations := AgriculturalParcelCapacity.destinations(ag.current_parcels(),AgriculturalParcelCapacity.allocate(ag.current_parcels()))
	check_eq(destinations.size(),1,"routing aliases retain one capacity entry")
	check_eq(destinations[0].jobs,5)
	var population := PopulationSystem.new()
	population.setup(ctx)
	population._run_census(ctx)
	check_eq(ctx.stats.jobs,5)
	check_eq(PopulationSystem.reachable_jobs(ctx),5)
	var budget := BudgetSystem.new()
	budget.setup(ctx)
	check_eq(ag.assessed_value(),500)
	check_eq(int(budget._yearly_cents(ctx).taxes_agricultural),3500)


func test_both_densities_feed_employment_tax_services_environment_and_history() -> void:
	for kind in [Zones.AGR_LOW,Zones.AGR_HIGH]:
		var ctx: SimContext
		var expected_jobs := 4 if kind == Zones.AGR_LOW else 40
		if kind == Zones.AGR_LOW:
			var c := flat_city()
			var m := ParcelFixture.square(2)
			ParcelFixture.zone(c,m)
			check_eq(c.agricultural_parcels.put(c,ParcelFixture.record(1,m,&"grain",&"active")),OK)
			ctx = make_context(c)
			_contexts.append(ctx)
			var agriculture := AgricultureSystem.new()
			ctx.systems[&"agriculture"] = agriculture
			agriculture.setup(ctx)
		else:
			ctx = fixture(&"dairy")
		var ag := ctx.system(&"agriculture") as AgricultureSystem
		var pop := PopulationSystem.new()
		pop.setup(ctx)
		pop._run_census(ctx)
		ctx.stats.cohorts.fill(0)
		ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN] = 80
		pop._update_employment(ctx)
		check_eq(ctx.stats.jobs,expected_jobs)
		check_eq(PopulationSystem.reachable_jobs(ctx),expected_jobs)
		check_eq(ctx.stats.unemployment,95 if kind == Zones.AGR_LOW else 50)
		check_eq(ctx.stats.employment_rate,5.0 if kind == Zones.AGR_LOW else 50.0)
		var economy := EconomySystem.new()
		economy.setup(ctx)
		economy._assess_city(ctx)
		check_eq(economy.assessed_value(),expected_jobs*100)
		var budget := BudgetSystem.new()
		budget.setup(ctx)
		check_eq(int(budget._yearly_cents(ctx).taxes_agricultural),expected_jobs*700)
		budget.monthly(ctx)
		var expected_tax := 2 if kind == Zones.AGR_LOW else 23
		check_eq(int(ctx.stats.ledger.taxes_agricultural),expected_tax)
		var power := PowerSystem.new()
		var water := WaterSystem.new()
		power.reallocate_established(ctx,Rect2i(0,0,128,128))
		water.reallocate_established(ctx,Rect2i(0,0,128,128))
		check_eq(ctx.stats.power_demand,0 if kind == Zones.AGR_LOW else 9)
		check_eq(ctx.stats.water_demand,4 if kind == Zones.AGR_LOW else 27)
		var env := EnvironmentSystem.new()
		env._scan_tiles(ctx)
		var emissions := 0
		for value in env._block_emission: emissions += value
		check_eq(emissions,1 if kind == Zones.AGR_LOW else 4)
		check_eq(env.developed_blocks(),0)
		var statistics := preload("res://scripts/sim/statistics_system.gd").new()
		statistics.setup(ctx)
		statistics.monthly(ctx)
		check_eq(statistics.series(&"agricultural_jobs",1),PackedInt32Array([expected_jobs]))
		check_eq(statistics.series(&"agricultural_lots",1),PackedInt32Array([1]))
		check_eq(statistics.series(&"taxes_agricultural",1),PackedInt32Array([expected_tax]))
		check_eq(ag.jobs(),expected_jobs,"consumer passes do not duplicate capacity")
