# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

const PortSystem := preload("res://scripts/sim/port_system.gd")
const Paper := preload("res://scripts/sim/newspaper_system.gd")
var _contexts: Array[SimContext] = []

func context(population: int = 5000) -> SimContext:
	var ctx := make_context(flat_city())
	ctx.stats.population = population
	ctx.stats.disasters_enabled = false
	var paper := Paper.new()
	var disasters := DisasterSystem.new()
	ctx.systems = {&"newspaper": paper, &"disasters": disasters}
	paper.setup(ctx)
	disasters.setup(ctx)
	_contexts.append(ctx)
	return ctx

func after_each() -> void:
	for ctx in _contexts: ctx.systems.clear()
	_contexts.clear()

func advice(ctx: SimContext, kind: StringName) -> Dictionary:
	for entry: Dictionary in ctx.system(&"newspaper").advice():
		if entry.kind == kind: return entry
	return {}

func reason(ctx: SimContext, kind: StringName) -> String:
	return String(advice(ctx, kind).get("reason", ""))

func powered(ctx: SimContext, x: int, y: int, id: int) -> void:
	ctx.city.stamp_building(x,y,id)
	var size := Buildings.size(id)
	for dy in size.y:
		for dx in size.x:
			ctx.city.flags.put(x+dx,y+dy, TileFlags.POWERED | TileFlags.WATERED)

func house(ctx: SimContext, x: int = 40, y: int = 40) -> void:
	powered(ctx,x,y,Buildings.RES_1X1_FIRST)

func test_resolved_utility_need_ignores_monthly_cache() -> void:
	var ctx := context()
	ctx.stats.power_demand = 100
	ctx.system(&"disasters").monthly(ctx)
	check(not advice(ctx,&"power_shortage").is_empty())
	ctx.stats.power_capacity = 1000
	check(advice(ctx,&"power_shortage").is_empty(), "resolved shortage must clear immediately")

func test_utility_connection_problem_does_not_prescribe_a_plant() -> void:
	var ctx := context()
	ctx.stats.power_demand = 100
	ctx.stats.power_capacity = 1000
	ctx.stats.unpowered_buildings = 1
	check_eq(reason(ctx,&"power_shortage"), "distribution")
	var text := String(advice(ctx,&"power_shortage").get("text",""))
	check(text.contains("network"))
	check(not text.contains("running flat out"))

func test_shortage_and_reserve_have_different_urgency() -> void:
	var ctx := context()
	ctx.stats.water_capacity = 100
	ctx.stats.water_demand = 101
	check_eq(reason(ctx,&"water_shortage"), "capacity")
	check(bool(advice(ctx,&"water_shortage").get("urgent",false)))
	ctx.stats.water_demand = 99
	check_eq(reason(ctx,&"water_shortage"), "reserve")
	check(not bool(advice(ctx,&"water_shortage").get("urgent",true)))
	ctx.stats.water_demand = 98
	check(advice(ctx,&"water_shortage").is_empty(), "two percent reserve is sufficient")

func test_prison_is_not_police_coverage() -> void:
	var ctx := context()
	house(ctx)
	powered(ctx,10,10,Buildings.PRISON)
	check_eq(reason(ctx,&"police"), "missing")

func test_service_funding_is_actionable_and_clears_immediately() -> void:
	var ctx := context()
	house(ctx)
	powered(ctx,36,38,Buildings.POLICE_STATION)
	ctx.stats.set_funding(&"police",0)
	check_eq(reason(ctx,&"police"), "funding")
	ctx.stats.set_funding(&"police",100)
	check(advice(ctx,&"police").is_empty(), "current coverage clears stale funding advice")

func test_unpowered_fire_station_is_not_a_missing_station() -> void:
	var ctx := context()
	house(ctx)
	ctx.city.stamp_building(36,38,Buildings.FIRE_STATION)
	check_eq(reason(ctx,&"fire_protection"), "power")

func test_school_uses_funding_and_relevant_cohort_not_total_population() -> void:
	var ctx := context(50000)
	ctx.stats.cohorts[0] = 600
	ctx.stats.cohorts[1] = 600
	powered(ctx,20,20,Buildings.SCHOOL)
	ctx.stats.set_funding(&"schools",0)
	check_eq(reason(ctx,&"schools"), "funding")
	ctx.stats.set_funding(&"schools",100)
	check(advice(ctx,&"schools").is_empty(), "15 places serves expected 10 movers in each school-age cohort")
	ctx.stats.cohorts[1] = 1200
	check_eq(reason(ctx,&"schools"), "capacity")

func test_health_recommends_recovering_existing_hospital_funding() -> void:
	var ctx := context()
	powered(ctx,20,20,Buildings.HOSPITAL)
	ctx.stats.set_funding(&"health",0)
	check_eq(reason(ctx,&"hospitals"), "funding")
	check(String(advice(ctx,&"hospitals").get("text","")).contains("fund"))

func test_active_fire_is_emergency_not_automatic_station_expansion() -> void:
	var ctx := context()
	house(ctx)
	powered(ctx,36,38,Buildings.FIRE_STATION)
	ctx.stats.active_fires = 1
	var entries: Array = ctx.system(&"newspaper").advice()
	check_eq(entries[0].get("reason",""), "emergency")
	check(bool(entries[0].urgent))
	check(not String(entries[0].text).contains("Build a station"))

func test_uncongested_city_does_not_need_a_transit_quota() -> void:
	var ctx := context(5000)
	ctx.system(&"disasters").monthly(ctx)
	check(advice(ctx,&"road_and_rail").is_empty())

func test_station_coverage_is_spatial_and_uses_current_power() -> void:
	var ctx := context()
	house(ctx,100,100)
	powered(ctx,10,10,Buildings.POLICE_STATION)
	check_eq(reason(ctx,&"police"), "coverage")
	powered(ctx,96,98,Buildings.POLICE_STATION)
	check(advice(ctx,&"police").is_empty())

func transport(ctx: SimContext, attempts: int, completed: int) -> void:
	var system := TransportSystem.new()
	ctx.systems[&"transport"] = system
	system.setup(ctx)
	system.load({"attempted":attempts,"completed":completed})

func test_measured_route_failure_is_not_a_shortage_of_transit_stations() -> void:
	var ctx := context()
	transport(ctx,10,7)
	check_eq(reason(ctx,&"road_and_rail"),"access")
	check(String(advice(ctx,&"road_and_rail").get("text","")).contains("3 of 10"))
	transport(ctx,10,9)
	check(advice(ctx,&"road_and_rail").is_empty())
	transport(ctx,0,0)
	check(advice(ctx,&"road_and_rail").is_empty())

func test_unemployment_distinguishes_jobs_from_access_and_abandonment() -> void:
	var ctx := context()
	ctx.stats.cohorts[4] = 100
	ctx.stats.jobs = 40
	ctx.stats.unemployment = 60
	check_eq(reason(ctx,&"unemployment"),"jobs")
	ctx.stats.jobs = 120
	transport(ctx,10,5)
	check_eq(reason(ctx,&"unemployment"),"access")
	transport(ctx,10,10)
	check_eq(reason(ctx,&"unemployment"),"employment")

func test_jobs_already_in_authoritative_total_are_not_added_twice() -> void:
	var ctx := context()
	ctx.stats.cohorts[4] = 100
	ctx.stats.jobs = 60
	ctx.stats.agricultural_jobs = 30
	ctx.stats.tourism_jobs = 30
	ctx.stats.unemployment = 40
	check_eq(reason(ctx,&"unemployment"),"jobs")

func test_congestion_reports_a_measurement_not_an_invented_trend() -> void:
	var ctx := context()
	ctx.stats.average_traffic = 110
	var item := advice(ctx,&"traffic")
	check(not item.is_empty())
	check(String(item.get("text","")).contains("110"))
	check(not String(item.get("text","")).contains("climbing"))
	check(not bool(item.get("urgent",true)))

func test_tax_advice_names_existing_sector_and_respects_cash_deficit() -> void:
	var ctx := context()
	house(ctx)
	ctx.stats.tax_residential = 13
	ctx.stats.demand.x = -100
	ctx.city.funds = -50
	var item := advice(ctx,&"taxes")
	check(not item.is_empty())
	check(String(item.get("text","")).contains("Residential"))
	check(String(item.get("text","")).contains("13%"))
	check(String(item.get("text","")).contains("Budget"))
	check(not String(item.get("text","")).contains("Bring the rate down"))
	check_eq(reason(ctx,&"treasury"),"cash")

func test_empty_sector_high_tax_is_not_a_current_crisis() -> void:
	var ctx := context(0)
	ctx.stats.tax_commercial = 20
	check(advice(ctx,&"taxes").is_empty())

func test_agricultural_and_visitor_taxes_are_not_ignored() -> void:
	var ctx := context()
	ctx.stats.agricultural_lots = 2
	ctx.stats.tax_agricultural = 13
	ctx.stats.tourist_capacity = 100
	ctx.stats.tax_occupancy = 15
	ctx.stats.tax_gaming = 16
	var text := String(advice(ctx,&"taxes").get("text",""))
	check(text.contains("Agricultural"))
	check(text.contains("Occupancy"))
	check(text.contains("Gaming"))

func test_last_poll_is_labeled_and_uses_real_leading_complaint() -> void:
	var ctx := context()
	ctx.stats.approval = 25
	var pop := PopulationSystem.new()
	ctx.systems[&"population"] = pop
	pop.setup(ctx)
	pop.load({"complaints":[{"key":"crime","name":"Crime","votes":60}]})
	var text := String(advice(ctx,&"approval").get("text",""))
	check(text.contains("last poll"))
	check(text.contains("Crime"))
	check(text.contains("25%"))
	check(not text.contains("Crime is climbing"))

func test_unmeasured_approval_is_not_a_poll() -> void:
	var ctx := context()
	ctx.stats.approval = 20
	check(advice(ctx,&"approval").is_empty(),"no poll ranking, no invented poll")

func test_recreation_advice_follows_residential_cap_not_population_quota() -> void:
	var ctx := context(20000)
	for x in range(10,24):
		for y in range(10,110):
			powered(ctx,x,y,Buildings.RES_1X1_FIRST)
	var item := advice(ctx,&"recreation")
	check(not item.is_empty())
	check(not bool(item.get("urgent",true)))
	check(String(item.get("text","")).contains("large park"))
	powered(ctx,60,60,Buildings.LARGE_PARK)
	check(advice(ctx,&"recreation").is_empty())

func test_dry_map_trade_advice_never_prescribes_seaport() -> void:
	var ctx := context(30000)
	for x in range(10,24):
		for y in range(10,110): powered(ctx,x,y,Buildings.IND_1X1_FIRST)
	check(advice(ctx,&"seaport").is_empty())
	check(not advice(ctx,&"connections").is_empty())

func test_zoned_unfinished_airport_is_repair_not_another_airport() -> void:
	var ctx := context()
	for x in range(20,25):
		for y in range(20,24): ctx.city.zone.put(x,y,Zones.AIRPORT)
	check_eq(reason(ctx,&"airport"),"existing")
	check(String(advice(ctx,&"airport").get("text","")).contains("existing"))

func test_pollution_has_no_invented_emitter() -> void:
	var ctx := context()
	ctx.stats.average_pollution = 110
	var text := String(advice(ctx,&"pollution").get("text",""))
	check(text.contains("110"))
	check(text.contains("Pollution Controls"))
	check(not text.contains("worst near the plants"))

func test_budget_advice_uses_read_only_outlook_not_forecast() -> void:
	var ctx := context()
	powered(ctx,10,10,Buildings.POLICE_STATION)
	var budget := BudgetSystem.new()
	ctx.systems[&"budget"] = budget
	budget.setup(ctx)
	var before := var_to_bytes([ctx.stats.to_dict(),budget.save(),ctx.rng.state()])
	check_eq(reason(ctx,&"treasury"),"outlook")
	check_eq(var_to_bytes([ctx.stats.to_dict(),budget.save(),ctx.rng.state()]),before)

func test_repeated_advice_is_stable_and_read_only() -> void:
	var ctx := context()
	house(ctx)
	ctx.stats.power_capacity = 1000
	ctx.stats.power_demand = 100
	ctx.stats.unpowered_buildings = 1
	ctx.stats.average_crime = 120
	var before := var_to_bytes([ctx.city.building.data,ctx.city.zone.data,ctx.city.flags.data,ctx.city.police.data,ctx.city.fire_cover.data,ctx.city.facilities,ctx.stats.to_dict(),ctx.rng.state(),ctx.events.news,ctx.events.notices,ctx.system(&"disasters").save(),ctx.system(&"newspaper").save()])
	var first: Array = ctx.system(&"newspaper").advice()
	for i in 3: check_eq(ctx.system(&"newspaper").advice(),first)
	check_eq(var_to_bytes([ctx.city.building.data,ctx.city.zone.data,ctx.city.flags.data,ctx.city.police.data,ctx.city.fire_cover.data,ctx.city.facilities,ctx.stats.to_dict(),ctx.rng.state(),ctx.events.news,ctx.events.notices,ctx.system(&"disasters").save(),ctx.system(&"newspaper").save()]),before)

func city_state(city: City) -> Array:
	var state: Array = [city.day,city.funds,city.facilities,city.flood_overlay,city.agricultural_parcels.to_dict()]
	for layer in [&"terrain",&"altitude",&"building",&"zone",&"flags",&"underground",&"traffic",&"pollution",&"land_value",&"crime",&"police",&"fire_cover",&"density",&"growth"]:
		state.append(city.get(layer).data)
	return state

func dispose_sim(sim: Simulation) -> void:
	sim._ctx.systems.clear()
	sim.systems.clear()
	sim.free()

func test_real_simulation_reads_and_restore_preserve_all_saved_state_and_caches() -> void:
	var city := flat_city()
	city.stamp_building(40,40,Buildings.RES_1X1_FIRST)
	city.stamp_building(35,39,Buildings.POLICE_STATION)
	var sim := make_simulation(city,733)
	sim.stats.disasters_enabled = false
	sim.advance_days(25)
	check_eq(sim.clock.day,25,"fixture completed a real month before reading")
	var paper := sim.get_system(&"newspaper")
	var ports := sim.get_system(&"ports") as PortSystem
	var budget := sim.get_system(&"budget") as BudgetSystem
	var before := var_to_bytes([city_state(city),sim.snapshot(),sim._ctx.events.news,sim._ctx.events.notices,ports._ports,ports._ports_zones,ports._ports_valid,budget._survey_result])
	var first: Array = paper.advice()
	for i in 5: check_eq(paper.advice(),first)
	check_eq(var_to_bytes([city_state(city),sim.snapshot(),sim._ctx.events.news,sim._ctx.events.notices,ports._ports,ports._ports_zones,ports._ports_valid,budget._survey_result]),before)
	var saved := sim.snapshot()
	check_eq(sim.restore(saved),OK)
	var restored_before := var_to_bytes([city_state(city),sim.snapshot()])
	paper.advice()
	check_eq(var_to_bytes([city_state(city),sim.snapshot()]),restored_before)
	dispose_sim(sim)

func test_advisor_reads_leave_paired_daily_simulation_outcomes_exact() -> void:
	var city := flat_city()
	city.stamp_building(40,40,Buildings.RES_1X1_FIRST)
	var left := make_simulation(city,91)
	var right := make_simulation(city.duplicate_city(),91)
	left.stats.disasters_enabled = false
	right.stats.disasters_enabled = false
	for day in 75:
		left.get_system(&"newspaper").advice()
		left.advance_day()
		right.advance_day()
		check_eq(var_to_bytes([city_state(left.city),left.snapshot(),left._ctx.events.news,left._ctx.events.notices]),var_to_bytes([city_state(right.city),right.snapshot(),right._ctx.events.news,right._ctx.events.notices]),"paired day %d" % day)
	check_eq(left.clock.day,75,"all paired days actually advanced")
	check_eq(right.clock.day,75)
	dispose_sim(left)
	dispose_sim(right)

func test_projected_station_maps_equal_actual_coverage_without_publication() -> void:
	var ctx := context()
	powered(ctx,20,20,Buildings.POLICE_STATION)
	ctx.city.stamp_building(40,40,Buildings.FIRE_STATION)
	ctx.stats.set_funding(&"police",40)
	ctx.stats.ordinances[&"volunteer_fire"] = true
	var observed := preload("res://scripts/sim/advisor_city_snapshot.gd").new(ctx.city)
	var services := ServicesSystem.new()
	var projected := services.projected_coverage(ctx.stats, observed.stations)
	check_eq(ctx.city.police.at(5,5),0,"projection does not publish")
	services.monthly(ctx)
	check_eq(projected.police.data,ctx.city.police.data)
	check_eq(projected.fire.data,ctx.city.fire_cover.data)

class GuardTourism extends TourismSystem:
	var forecasts := 0
	var fare_claims := 0
	func supported_forecast(_occupancy_rate: int = -1, _gaming_rate: int = -1, _summary_only: bool = false) -> Dictionary:
		forecasts += 1
		return {}
	func claim_transport_riders() -> int:
		fare_claims += 1
		return 0

func test_finance_never_forecasts_or_claims_fares_and_counts_known_costs() -> void:
	var ctx := context()
	powered(ctx,10,10,Buildings.POLICE_STATION)
	var tourism := GuardTourism.new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	check_eq(tourism.finish_restore({}),OK)
	var budget := BudgetSystem.new()
	ctx.systems[&"budget"] = budget
	budget.setup(ctx)
	ctx.stats.ordinances[&"casino_safety"] = true
	var item := advice(ctx,&"treasury")
	check(String(item.text).contains("$0 income against $100 expenses"))
	check_eq(tourism.forecasts,0)
	check_eq(tourism.fare_claims,0)

func test_accepted_tourism_bottleneck_is_specific_and_read_only() -> void:
	var ctx := TourismFixture.host_with_store(0)
	_contexts.append(ctx)
	var paper := Paper.new()
	ctx.systems[&"newspaper"] = paper
	paper.setup(ctx)
	var tourism := ctx.system(&"tourism") as TourismSystem
	var row: Dictionary = tourism._state.records()[0]
	row["target_day_visitors"] = 24
	row["target_guests"] = 0
	row["gateway_ids"] = []
	var rows: Array[Dictionary] = [row]
	var allocation := TourismEconomy.allocate(rows,0,0,{})
	tourism._features.staffing["rows"] = allocation.rows
	check_eq(reason(ctx,&"tourism"),"staffing")
	row["utility_limiting_reason"] = "power"
	tourism._features.utilities["rows"] = TourismUtilities.snapshot(rows)
	var before := var_to_bytes([ctx.stats.to_dict(),tourism.save(),ctx.rng.state()])
	check_eq(reason(ctx,&"tourism"),"utilities")
	check_eq(var_to_bytes([ctx.stats.to_dict(),tourism.save(),ctx.rng.state()]),before)

func test_connected_operating_airport_clears_existing_port_advice() -> void:
	var ctx := context()
	for x in range(20,25):
		for y in range(20,24):
			ctx.city.zone.put(x,y,Zones.AIRPORT)
			ctx.city.flags.put(x,y,TileFlags.POWERED)
	for x in range(20,25): ctx.city.building.put(x,20,Buildings.RUNWAY)
	var ports := PortSystem.new()
	ctx.systems[&"ports"] = ports
	ports.setup(ctx)
	ports.port_report() # Establish the existing simulation discovery before a read-only assessment.
	check(advice(ctx,&"airport").is_empty())
	for x in range(20,25):
		for y in range(20,24): ctx.city.flags.put(x,y,0)
	check_eq(reason(ctx,&"airport"),"existing")
	var before := var_to_bytes([ports._ports,ports._ports_valid,ports._ports_zones])
	advice(ctx,&"airport")
	check_eq(var_to_bytes([ports._ports,ports._ports_valid,ports._ports_zones]),before)

func test_casino_development_gets_spatial_civic_advice_without_resident_houses() -> void:
	var ctx := context(0)
	powered(ctx,40,40,Buildings.id_of(&"arcology_last"))
	check_eq(reason(ctx,&"police"),"missing")
	check_eq(reason(ctx,&"fire_protection"),"missing")

func test_power_loss_is_one_remedy_with_affected_services_identified() -> void:
	var ctx := context()
	house(ctx)
	ctx.city.stamp_building(20,20,Buildings.SCHOOL)
	ctx.stats.cohorts[0] = 600
	ctx.stats.power_capacity = 1000
	ctx.stats.power_demand = 100
	ctx.stats.unpowered_buildings = 1
	var power_advice := advice(ctx,&"power_shortage")
	check(String(power_advice.get("text","")).contains("Education"))
	check(advice(ctx,&"schools").is_empty(),"one shared power remedy instead of repeated construction advice")

func test_low_reserve_keeps_current_school_reconnection_remedy() -> void:
	var ctx := context()
	ctx.city.stamp_building(20,20,Buildings.SCHOOL)
	ctx.stats.cohorts[0] = 600
	ctx.stats.power_capacity = 100
	ctx.stats.power_demand = 99
	check_eq(reason(ctx,&"power_shortage"),"reserve")
	check_eq(reason(ctx,&"schools"),"power")
	check(String(advice(ctx,&"schools").get("text","")).contains("Restore power"))

func test_health_capacity_uses_power_funding_and_free_clinics() -> void:
	var ctx := context(5000)
	ctx.stats.life_expectancy = 40
	powered(ctx,20,20,Buildings.HOSPITAL)
	check_eq(reason(ctx,&"hospitals"),"capacity")
	check(String(advice(ctx,&"hospitals").get("text","")).contains("25 places"))
	ctx.stats.ordinances[&"free_clinics"] = true
	check(String(advice(ctx,&"hospitals").get("text","")).contains("37 places"))
	ctx.stats.set_funding(&"health",50)
	check_eq(reason(ctx,&"hospitals"),"funding")
	check(String(advice(ctx,&"hospitals").get("text","")).contains("24 places"))
	ctx.stats.set_funding(&"health",100)
	check_eq(reason(ctx,&"hospitals"),"capacity")

func test_poor_health_with_sufficient_care_does_not_prescribe_more_hospitals() -> void:
	var ctx := context(20)
	ctx.stats.life_expectancy = 40
	powered(ctx,20,20,Buildings.HOSPITAL)
	check_eq(reason(ctx,&"hospitals"),"health")
	var text := String(advice(ctx,&"hospitals").get("text",""))
	check(text.contains("25 places"))
	check(text.contains("pollution"))
	check(not text.contains("Another hospital"))

func test_sufficient_care_does_not_prescribe_needless_funding_increase() -> void:
	var ctx := context(10)
	ctx.stats.life_expectancy = 40
	powered(ctx,20,20,Buildings.HOSPITAL)
	ctx.stats.set_funding(&"health",50)
	check_eq(reason(ctx,&"hospitals"),"health","12 places already cover 10 residents; raising funding cannot improve the capped coverage benefit")

func test_unpowered_station_with_adequate_partial_funding_points_to_power() -> void:
	var ctx := context()
	house(ctx)
	ctx.city.stamp_building(36,38,Buildings.POLICE_STATION)
	ctx.stats.set_funding(&"police",80)
	check_eq(reason(ctx,&"police"),"power","coverage is already adequate; the actionable fault is missing power")

func test_power_advice_uses_actual_conservation_budget_not_raw_generation() -> void:
	var ctx := context(130)
	ctx.stats.ordinances[UtilityParams.CONSERVATION_ORDINANCE] = true
	ctx.city.stamp_building(18,20,Buildings.WIND_PLANT)
	ctx.city.building.put(19,20,Buildings.POWER_LINE_FIRST)
	for x in range(20,33): house(ctx,x,20)
	var power := PowerSystem.new()
	ctx.systems[&"power"] = power
	power.setup(ctx)
	ctx.city.facility(Vector2i(18,20)).capacity = 12
	power.reallocate_established(ctx,Rect2i(0,0,128,128))
	check_eq(ctx.stats.power_capacity,12)
	check_eq(ctx.stats.power_demand,13)
	check_eq(ctx.stats.unpowered_buildings,0)
	check_eq(power.network_summary().available_capacity,13)
	check_eq(reason(ctx,&"power_shortage"),"reserve","conservation supports the whole load; this is reserve planning, not lost supply")
	check(not bool(advice(ctx,&"power_shortage").get("urgent",true)))
