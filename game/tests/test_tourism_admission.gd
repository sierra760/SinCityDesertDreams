# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

func pair() -> Dictionary:
	var city := flat_city()
	var rows: Array[Dictionary] = []
	for x in [10,20]:
		city.stamp_building(x,10,Buildings.id_of(&"arcology_last"))
		rows.append({"anchor":Vector2i(x,10),"key":&"arcology_last","guests":40,"day_visitors":0,"operating":true})
	var components := PackedInt32Array()
	components.resize(City.WIDTH*City.HEIGHT)
	components.fill(-1)
	for row in rows:
		var size := Buildings.size(Buildings.id_of(row.key))
		for y in size.y:
			for x in size.x: components[(row.anchor.y+y)*City.WIDTH+row.anchor.x+x] = 0
	return {"city":city,"rows":rows,"budget":{"tiles":components,"components":[{"capacity":35,"baseline":32,"spare":3}]}}

func test_joint_last_units_are_fair_and_never_promised_twice() -> void:
	var f := pair()
	var before := var_to_bytes([f.city.flags.data,f.city.facilities,f.rows])
	var plan: Dictionary = TourismUtilities.admission_plan(f.city,f.rows,f.budget,f.budget)
	check_eq(plan.rows[0].guests,40)
	check_eq(plan.rows[1].guests,20)
	check_eq(plan.power_reserved[0],2)
	check_eq(plan.water_reserved[0],3)
	check_eq(var_to_bytes([f.city.flags.data,f.city.facilities,f.rows]),before,"planning is pure")

func test_disconnected_spare_cannot_support_a_venue() -> void:
	var f := pair()
	f.budget.components.append({"capacity":100000,"baseline":0,"spare":100000})
	f.budget.components[0].spare = 0
	var plan: Dictionary = TourismUtilities.admission_plan(f.city,f.rows,f.budget,f.budget)
	check_eq(plan.rows[0].guests+plan.rows[1].guests,0)
	check_eq(plan.water_reserved[1],0)

func test_exact_component_conservation_and_pure_budget() -> void:
	var city := flat_city()
	city.stamp_building(10,10,Buildings.COAL_PLANT)
	city.facilities[Vector2i(10,10)] = {"key":&"power_coal","capacity":13}
	# Use actual roster key; the stored source token is mandatory.
	city.facility(Vector2i(10,10)).key = Buildings.key(Buildings.COAL_PLANT)
	var power := PowerSystem.new()
	power._conservation = true
	var before := var_to_bytes([city.flags.data,city.facilities])
	var budget: Dictionary = power.admission_budget(city)
	check_eq(budget.components[0].capacity,14,"floor bonus belongs to this component")
	check_eq(var_to_bytes([city.flags.data,city.facilities]),before)

class CountPower extends PowerSystem:
	var calls := 0
	func reallocate_established(ctx: SimContext, rect: Rect2i) -> void:
		calls += 1
		if calls==1:
			ctx.system(&"tourism").reconcile_now()
			ctx.system(&"tourism").monthly(ctx)
		super.reallocate_established(ctx,rect)

class CountWater extends WaterSystem:
	var calls := 0
	func reallocate_established(ctx: SimContext, rect: Rect2i) -> void:
		calls += 1
		super.reallocate_established(ctx,rect)

func test_one_month_transaction_does_not_advance_storage_or_rng() -> void:
	var fixture := preload("res://tests/test_tourism_utilities.gd").new()
	var ctx: SimContext = fixture.fixture()
	fixture.attend(ctx,80)
	var power := CountPower.new()
	var water := CountWater.new()
	ctx.systems[&"power"] = power
	ctx.systems[&"water"] = water
	power.setup(ctx)
	ctx.city.set_flag(9,10,TileFlags.POWERED,true)
	water.setup(ctx)
	ctx.city.facility(Vector2i(9,10))["output"] = 100
	ctx.city.stamp_building(14,10,Buildings.WATER_TOWER)
	var tower := Vector2i(14,10)
	TourismFixture.set_served(ctx.city,tower,true,true)
	var before := ctx.rng.state()
	var tourism := ctx.system(&"tourism") as TourismSystem
	tourism.monthly(ctx)
	check_eq(power.calls,1)
	check_eq(water.calls,1)
	check_eq(ctx.rng.state(),before)
	check(ctx.city.is_watered(tower.x,tower.y),"established admission does not drain the tower")
	var accepted := tourism.save()
	for i in 8:
		tourism.reconcile_now()
		tourism.monthly(ctx)
	check_eq(power.calls,1)
	check_eq(water.calls,1)
	check_eq(tourism.save().pending,accepted.pending)
	fixture.after_each()
	fixture.free()

func mark_component(budget: Dictionary, row: Dictionary, component: int) -> void:
	var size := Buildings.size(Buildings.id_of(row.key))
	for y in size.y:
		for x in size.x: budget.tiles[(row.anchor.y+y)*City.WIDTH+row.anchor.x+x] = component

func test_crossed_components_reclaim_unusable_grants_jointly() -> void:
	var f := pair()
	f.city.stamp_building(30,10,Buildings.id_of(&"arcology_last"))
	f.rows.append({"anchor":Vector2i(30,10),"key":&"arcology_last","guests":120,"day_visitors":0,"operating":true})
	f.rows[1].guests = 20
	var power: Dictionary = f.budget.duplicate(true)
	var water: Dictionary = f.budget.duplicate(true)
	power.components = [{"spare":1},{"spare":1}]
	water.components = [{"spare":4},{"spare":1}]
	mark_component(power,f.rows[2],1)
	mark_component(water,f.rows[1],1)
	mark_component(water,f.rows[2],0)
	var plan := TourismUtilities.admission_plan(f.city,f.rows,power,water)
	check_eq([plan.rows[0].guests,plan.rows[1].guests,plan.rows[2].guests],[40,0,40],"independent grants stranded20 places; joint residual capacity recovers them")
	check_eq(plan.power_reserved,PackedInt64Array([1,1]))
	check_eq(plan.water_reserved,PackedInt64Array([4,0]))
	f.rows.reverse()
	check_eq(TourismUtilities.admission_plan(f.city,f.rows,power,water),plan,"canonical remainder is independent of input order")

func test_resource_loss_departures_are_distinct_from_natural_turnover() -> void:
	var fixture := preload("res://tests/test_tourism_utilities.gd").new()
	var ctx: SimContext = fixture.fixture(&"arcology_last")
	var tourism := ctx.system(&"tourism") as TourismSystem
	var water := ctx.system(&"water") as WaterSystem
	var full := Rect2i(0,0,128,128)
	ctx.city.facility(Vector2i(9,10))["output"] = 100
	water.reallocate_established(ctx,full)
	fixture.attend(ctx,100)
	# Normal no-arrival turnover leaves50. Water baseline32 leaves1 unit.
	ctx.city.facility(Vector2i(9,10))["output"] = 33
	ctx.clock.day = 16
	ctx.city.day = 16
	tourism.monthly(ctx)
	var row := tourism.report()[0]
	check_eq(row.guests,20)
	check_eq(row.departures,80,"50 natural plus30 essential capacity departures")
	check_eq(row.resource_departures,30)
	check_eq(row.arrivals,0,"capacity loss cannot be replaced immediately")
	check_eq(row.guest_half_months,120,"factual100opening+20closing business")
	check_eq(TourismMarkets.sum_counts(row.guest_segments),20)
	check_eq(tourism.save().features.utilities.rows[0].water,1)
	var earned := tourism.pending_bases()
	var activity: Dictionary = tourism.save().activity
	TourismFixture.set_served(ctx.city,row.anchor,false,true)
	tourism.reconcile_now()
	check_eq(tourism.report()[0].guests,0)
	check_eq(tourism.save().features.utilities.rows,[])
	check_eq(tourism.pending_bases(),earned)
	check_eq(tourism.save().activity,activity)
	TourismFixture.set_served(ctx.city,row.anchor,true,true)
	tourism.reconcile_now()
	check_eq(tourism.report()[0].guests,0,"recovery cannot admit in reconciliation")
	check_eq(tourism.pending_bases(),earned)
	fixture.after_each()
	fixture.free()

func test_malformed_reservations_and_raw_source_reject_atomically() -> void:
	var ctx := TourismFixture.host_with_store(12)
	var tourism := ctx.system(&"tourism") as TourismSystem
	var valid := tourism.save()
	var city_before := var_to_bytes([ctx.city.flags.data,ctx.city.facilities,ctx.stats.to_dict()])
	var mutations := [{"power":-1},{"power":0.5},{"water":99999},{"supported_days":11},{"instance":true},{"instance":99999},{"resource_departures":1},{"limiting_reason":"unknown"}]
	for change in mutations:
		var block := valid.duplicate(true)
		block.features.utilities.rows[0].merge(change,true)
		var snapshot := {"clock_day":ctx.clock.day,"systems":{"tourism":block}}
		check(not TourismSaveCodec.problem(snapshot,ctx.city).is_empty())
		check_eq(tourism.finish_restore(snapshot),ERR_INVALID_DATA)
		check_eq(tourism.save(),valid)
		check_eq(var_to_bytes([ctx.city.flags.data,ctx.city.facilities,ctx.stats.to_dict()]),city_before)
	for field in ["instance","key","operating","anchor"]:
		for value in [null,[],{},0,0.5]:
			var block := valid.duplicate(true)
			block.state.records[0][field] = value
			check_eq(tourism.finish_restore({"systems":{"tourism":block}}),ERR_INVALID_DATA,"raw source "+field)
			check_eq(tourism.save(),valid)
	for field in ["activation_month","month_id","rows"]:
		var block := valid.duplicate(true)
		block.features.utilities[field] = 1000
		check_eq(tourism.finish_restore({"systems":{"tourism":block}}),ERR_INVALID_DATA)
		check_eq(tourism.save(),valid)
	var duplicate := valid.duplicate(true)
	duplicate.features.utilities.rows.append(duplicate.features.utilities.rows[0].duplicate(true))
	check_eq(tourism.finish_restore({"systems":{"tourism":duplicate}}),ERR_INVALID_DATA)
	ctx.systems.clear()

func test_maximum_city_reservation_work_is_bounded_by_venues() -> void:
	var city := flat_city()
	var code := Buildings.id_of(&"com_corner_store")
	city.building.data.fill(code)
	var rows: Array[Dictionary] = []
	var labels := PackedInt32Array()
	labels.resize(City.WIDTH*City.HEIGHT)
	for y in City.HEIGHT:
		for x in City.WIDTH:
			rows.append({"anchor":Vector2i(x,y),"key":&"com_corner_store","guests":0,"day_visitors":24,"operating":true})
	var budget := {"tiles":labels,"components":[{"spare":8192}]}
	var start := Time.get_ticks_usec()
	var plan := TourismUtilities.admission_plan(city,rows,budget,budget)
	check_eq(plan.rows.size(),16384)
	check_eq(plan.power_reserved[0],8192)
	check_eq(plan.water_reserved[0],8192)
	check(plan.reservation_checks<=16384*12,"two bounded binary searches, never one iteration per visitor")
	var admitted := 0
	for row: Dictionary in plan.rows: admitted += int(row.day_visitors)
	check_eq(admitted,8192*24)
	print("ADMISSION_SCALE venues=16384 visitors=%d checks=%d elapsed_us=%d"%[admitted,plan.reservation_checks,Time.get_ticks_usec()-start])

func test_utility_activation_does_not_renew_absolute_migration_grace() -> void:
	var ctx := TourismFixture.host_with_store(12)
	var tourism := ctx.system(&"tourism") as TourismSystem
	var predecessor := tourism.save()
	predecessor.features.utilities = {}
	predecessor.features.migration.grace_until_month = 1
	ctx.clock.day = 3*25
	ctx.city.day = ctx.clock.day
	check_eq(tourism.finish_restore({"systems":{"tourism":predecessor}}),OK)
	check_eq(tourism.save().features.utilities.activation_month,3)
	check_eq(tourism.save().features.migration.grace_until_month,1)
	var normalized := tourism.save()
	ctx.clock.day = 12*25
	ctx.city.day = ctx.clock.day
	check_eq(tourism.finish_restore({"systems":{"tourism":normalized}}),OK)
	check_eq(tourism.save(),normalized,"year boundary reload cannot renew activation or expired grace")
	var before := var_to_bytes([tourism.save(),ctx.stats.to_dict(),ctx.city.facilities,ctx.rng.state()])
	for i in 8:
		tourism.utility_report()
		tourism.forecast()
		tourism.report()
	check_eq(var_to_bytes([tourism.save(),ctx.stats.to_dict(),ctx.city.facilities,ctx.rng.state()]),before)
	ctx.systems.clear()

func test_no_single_feasible_residual_place_and_exact_request_conservation() -> void:
	var f := pair()
	for power_units in range(5):
		for water_units in range(7):
			var power: Dictionary = f.budget.duplicate(true)
			var water: Dictionary = f.budget.duplicate(true)
			power.components[0].spare = power_units
			water.components[0].spare = water_units
			var plan := TourismUtilities.admission_plan(f.city,f.rows,power,water)
			var actual_power := 0
			var actual_water := 0
			for row: Dictionary in plan.rows:
				actual_power += TourismUtilities.request(row,false)
				actual_water += TourismUtilities.request(row,true)
			check_eq(actual_power,plan.power_reserved[0])
			check_eq(actual_water,plan.water_reserved[0])
			check(actual_power<=power_units and actual_water<=water_units)
			for row: Dictionary in plan.rows:
				if row.guests==40: continue
				var next := row.duplicate(true)
				next.guests += 1
				var p := actual_power-TourismUtilities.request(row,false)+TourismUtilities.request(next,false)
				var w := actual_water-TourismUtilities.request(row,true)+TourismUtilities.request(next,true)
				check(p>power_units or w>water_units,"no single supported place remains idle")

func test_fractional_mixed_remainder_fills_last_day_place() -> void:
	var f := pair()
	f.rows.resize(1)
	f.rows[0].day_visitors = 40
	f.budget.components[0].spare = 1
	var plan := TourismUtilities.admission_plan(f.city,f.rows,f.budget,f.budget)
	check_eq(plan.rows[0].guests,13)
	check_eq(plan.rows[0].day_visitors,14,"last affordable day place survives proportional guest rounding")
	check_eq(plan.water_reserved[0],1)

func test_zero_visitor_headroom_releases_variable_jobs_and_recovers() -> void:
	var fixture := preload("res://tests/test_tourism_utilities.gd").new()
	var ctx: SimContext = fixture.fixture(&"arcology_last")
	var tourism := ctx.system(&"tourism") as TourismSystem
	var water := ctx.system(&"water") as WaterSystem
	ctx.city.building.put(11,9,Buildings.ROAD_FIRST)
	ctx.city.stamp_building(11,8,Buildings.id_of(&"res_bungalow_1"))
	tourism.reconcile_now()
	ctx.stats.population = 1000
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN] = 500
	ctx.city.facility(Vector2i(9,10)).output = 32
	water.reallocate_established(ctx,Rect2i(0,0,128,128))
	check(ctx.city.is_watered(10,10),"ordinary building is genuinely watered")
	check_eq(water.admission_budget(ctx.city).components[0].spare,0)
	ctx.clock.day = 16
	ctx.city.day = 16
	check_gt(tourism.forecast().staffing.positions,2,"market demand includes variable work before utility admission")
	tourism.monthly(ctx)
	var staff := tourism.staffing_report()
	check_eq(tourism.report()[0].guests+tourism.report()[0].day_visitors,0)
	check_eq(staff.positions,2,"only bounded base work survives zero visitor headroom")
	check_eq(staff.local_staff,2,"impossible variable work cannot claim residents")
	check_eq(staff.planned_guests+staff.planned_day_visitors,0)
	var saved := tourism.save()
	check_eq(tourism.finish_restore({"systems":{"tourism":saved}}),OK)
	check_eq(tourism.save(),saved)
	var zones := ZoneSystem.new()
	var population := PopulationSystem.new()
	ctx.systems[&"zones"] = zones
	ctx.systems[&"population"] = population
	zones.setup(ctx)
	population.setup(ctx)
	for i in 2:
		zones._take_census(ctx.city,ctx.stats)
		zones._add_port_jobs(ctx)
		check_eq(ctx.stats.tourism_jobs,2)
		check_eq(ctx.stats.jobs,2)
		population._run_census(ctx)
		check_eq(ctx.stats.jobs,2)
	# Recovery starts from zero actual visitors, without manufacturing attendance.
	ctx.stats.population = 1000
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN] = 500
	ctx.city.facility(Vector2i(9,10)).output = 100
	water.reallocate_established(ctx,Rect2i(0,0,128,128))
	tourism.acknowledge_booking(0)
	ctx.clock.day = 41
	ctx.city.day = 41
	tourism.monthly(ctx)
	check_gt(tourism.staffing_report().positions,2)
	check_gt(tourism.report()[0].day_visitors,0,"prospective feasible jobs recover an empty venue")
	fixture.after_each()
	fixture.free()

func test_prospective_joint_plan_releases_workers_to_serviceable_neighbor() -> void:
	var f := pair()
	var power: Dictionary = f.budget.duplicate(true)
	var water: Dictionary = f.budget.duplicate(true)
	power.components = [{"spare":1000},{"spare":1000}]
	water.components = [{"spare":0},{"spare":1000}]
	mark_component(power,f.rows[1],1)
	mark_component(water,f.rows[1],1)
	for row: Dictionary in f.rows:
		row.guests = 0
		row.land_value = 100
	var inputs := {"resident_workers":6,"non_tourism_jobs":0,"permanent_population":1000}
	var counterfactual := TourismDemand.forecast(f.rows,inputs,7,7)
	var before := var_to_bytes([f.rows,power,water,f.city.flags.data])
	var feasible := TourismDemand.forecast(f.rows,inputs,7,7,f.city,power,water)
	check_eq(feasible.staffing.rows[0].positions,2)
	check_eq(feasible.staffing.rows[0].planned_guests+feasible.staffing.rows[0].planned_day_visitors,0)
	check_gt(feasible.staffing.rows[1].local_staff,counterfactual.staffing.rows[1].local_staff,"infeasible variable work releases shared finite workers")
	check_gt(feasible.rows[1].target_guests+feasible.rows[1].target_day_visitors,0,"empty serviceable resort has prospective support")
	check_eq(feasible.staffing.local_staff,6)
	check_eq(var_to_bytes([f.rows,power,water,f.city.flags.data]),before,"prospective plan is detached and pure")
	f.rows.reverse()
	check_eq(TourismDemand.forecast(f.rows,inputs,7,7,f.city,power,water),feasible,"canonical allocation independent of input order")
	inputs.resident_workers = 0
	inputs["gateways"] = [{"id":"road-west","kind":"road","capacity":500}]
	for row: Dictionary in f.rows:
		row["gateway_ids"] = ["road-west"]
		row["external_reachable"] = true
	var incoming_market := TourismDemand.forecast(f.rows,inputs,7,7)
	var incoming_feasible := TourismDemand.forecast(f.rows,inputs,7,7,f.city,power,water)
	check(incoming_feasible.staffing.rows[0].incoming_staff<=2,"impossible variable work takes no regional allowance")
	check_gt(incoming_feasible.staffing.rows[1].incoming_staff,incoming_market.staffing.rows[1].incoming_staff)
	check_eq(incoming_feasible.staffing.rows[0].incoming_staff+incoming_feasible.staffing.rows[1].incoming_staff,8)


func test_actual_disjoint_utility_components_publish_only_feasible_shared_jobs() -> void:
	var fixture := preload("res://tests/test_tourism_utilities.gd").new()
	var ctx: SimContext = fixture.fixture(&"arcology_last")
	var city := ctx.city
	city.stamp_building(40,40,Buildings.id_of(&"arcology_last"))
	city.stamp_building(39,40,Buildings.WATER_PUMP)
	city.stamp_building(36,36,Buildings.COAL_PLANT)
	for y in range(37,40): city.building.put(40,y,Buildings.POWER_LINE_FIRST)
	for at in [Vector2i(10,10),Vector2i(40,40)]:
		city.building.put(at.x,at.y-1,Buildings.ROAD_FIRST)
		city.building.put(at.x+1,at.y-1,Buildings.ROAD_FIRST)
		city.stamp_building(at.x+1,at.y-2,Buildings.id_of(&"res_bungalow_1"))
	var power := ctx.system(&"power") as PowerSystem
	var water := ctx.system(&"water") as WaterSystem
	power.setup(ctx) # Register and generate both real sources before established planning.
	water.setup(ctx)
	city.facility(Vector2i(9,10)).output = 32
	city.facility(Vector2i(39,40)).output = 100
	water.reallocate_established(ctx,Rect2i(0,0,128,128))
	check(city.is_watered(10,10) and city.is_watered(40,40),"both ordinary buildings actually served")
	var budget := water.admission_budget(city)
	var constrained: int = budget.tiles[10*128+10]
	var available: int = budget.tiles[40*128+40]
	check(constrained!=available)
	check_eq(budget.components[constrained].spare,0)
	check_gt(budget.components[available].spare,0)
	ctx.stats.population = 1000
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN] = 5
	var tourism := ctx.system(&"tourism") as TourismSystem
	tourism.reconcile_now()
	var market := tourism.forecast()
	ctx.clock.day = 16
	ctx.city.day = 16
	tourism.monthly(ctx)
	var rows := tourism.report()
	check_eq(rows.size(),2)
	check_eq(rows[0].positions,2)
	check_eq(rows[0].planned_guests+rows[0].planned_day_visitors,0)
	check_gt(rows[1].local_staff,market.staffing.rows[1].local_staff)
	check_gt(rows[1].day_visitors,0)
	check_eq(rows[0].local_staff+rows[1].local_staff,5)
	check_eq(rows[0].incoming_staff+rows[1].incoming_staff,0)
	check_eq(ctx.stats.tourism_jobs,tourism.jobs())
	fixture.after_each()
	fixture.free()
