# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

func test_season_scales_finite_pools_before_feasibility() -> void:
	var rows: Array[Dictionary] = []
	var neutral := TourismDemand.forecast(rows,{},0,0)
	var july := TourismDemand.forecast(rows,{"season_percent":75},0,0)
	check(july.guest_pool < neutral.guest_pool,"July's 75% season reduces finite demand even with no hotels")
	check(july.day_pool < neutral.day_pool,"season applies to mutually exclusive day demand")

func test_carnival_has_no_permanent_appeal() -> void:
	var rows: Array[Dictionary] = []
	check_eq(TourismDemand.forecast(rows,{"annual_carnival":true},0,0),TourismDemand.forecast(rows,{},0,0),"ordinance alone cannot grant permanent tourism appeal")

var contexts: Array[SimContext] = []
const DIR := "user://tourism-calendar-tests"

func after_each() -> void:
	for ctx in contexts: ctx.systems.clear()
	contexts.clear()

func after_all() -> void:
	remove_test_tree(DIR)

func test_exact_table_dates_and_segment_pools() -> void:
	check_eq(TourismCalendar.SEASONS,[115,115,110,100,90,80,75,80,95,105,115,120])
	var total := 0
	for n: int in TourismCalendar.SEASONS: total+=n
	check_eq(total,1200)
	var rows: Array[Dictionary]=[]
	var carnival := TourismDemand.forecast(rows,{"event_factors":[125,125,100,100]},0,0)
	check_eq(carnival.guest_pools,[98,66,26,17],"base175 split79/53/26/17 then only budget/leisure +25%, integer floors")
	check_eq(carnival.day_pools,[40,18,3,8],"base58 split32/15/3/8 then eligible markets")
	var business := TourismDemand.forecast(rows,{"event_factors":[100,100,100,125]},0,0)
	check_eq(business.guest_pools,[79,53,26,21])
	check_eq(business.day_pools,[32,15,3,10])
	var july := TourismDemand.forecast(rows,{"season_percent":75},0,0)
	check_eq(july.guest_pool,131)
	check_eq(july.day_pool,43)

func test_notice_boundaries_cancel_and_annual_identity() -> void:
	var inputs := {"annual_carnival":true,"stadium":true,"city_hall":true,"business_gateway":true,"supported_beds":1000}
	var state := TourismCalendar.initial(0)
	var notices: Array=[]
	for month in 36:
		var before := var_to_bytes(state)
		inputs["calendar"]=state
		var query := TourismCalendar.for_month(month,inputs)
		check_eq(var_to_bytes(state),before,"pure query")
		var accepted := TourismCalendar.accept(month,inputs,state)
		state=accepted.state
		notices.append_array(accepted.notices)
		check(state.events.size()<=3,"bounded rolling event guards")
		check(TourismCalendar.decode(state,{"last_month":month},month).ok,"accepted state validates every month")
		check(TourismCalendar.accept(month,inputs,state).notices.is_empty(),"repeated accepted month does not announce")
		if month%12 in [3,8]: check_eq(query.event_factors,[125,125,100,100])
		elif month%12==10: check_eq(query.event_factors,[100,100,100,125])
		else: check_eq(query.event_factors,[100,100,100,100])
	check_eq(notices.size(),9,"exactly three notices per year regardless of host count")
	var seen := {}
	for notice: Dictionary in notices:
		check(not seen.has(notice.args.identity),"distinct event/year identity")
		seen[notice.args.identity]=true
	check(seen.has("carnival:3") and seen.has("carnival:15") and seen.has("sports:8") and seen.has("convention:10"))
	var late := TourismCalendar.accept(3,inputs,TourismCalendar.initial(3))
	check(late.notices.is_empty(),"startup in April cannot backfill March notice")
	inputs.calendar=late.state
	check_eq(TourismCalendar.for_month(3,inputs).event_factors,[100,100,100,100])

func start(month: int = 2, founded_year: int = 1900) -> SimContext:
	var ctx := TourismFixture.context(flat_city(10000))
	ctx.clock.day=month*25+16
	ctx.clock.founded_year=founded_year
	ctx.city.founded_year=founded_year
	ctx.city.day=ctx.clock.day
	ctx.stats.ordinances[&"annual_carnival"]=true
	TourismFixture.venue(ctx.city,&"arcology_boddy",Vector2i(10,10))
	TourismFixture.set_served(ctx.city,Vector2i(10,10),true,true)
	for x in 10: ctx.city.building.put(x,10,Buildings.ROAD_FIRST)
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN]=500
	var tourism := TourismSystem.new()
	var budget := BudgetSystem.new()
	ctx.systems[&"tourism"]=tourism
	ctx.systems[&"budget"]=budget
	tourism.setup(ctx)
	budget.setup(ctx)
	check_eq(tourism.finish_restore({}),OK)
	contexts.append(ctx)
	return ctx

func advance(ctx: SimContext, month: int) -> void:
	ctx.clock.day=month*25+16
	ctx.city.day=ctx.clock.day
	ctx.system(&"tourism").monthly(ctx)
	ctx.system(&"budget").monthly(ctx)

func snapshot(ctx: SimContext) -> Dictionary:
	return {"clock_day":ctx.clock.day,"stats":ctx.stats.to_dict(),"rng_seed":str(ctx.rng.seed_value()),"rng_state":str(ctx.rng.state()),"systems":{"tourism":ctx.system(&"tourism").save(),"budget":ctx.system(&"budget").save()}}

func test_actual_host_cancellation_preserves_earned_money_and_read_purity() -> void:
	var ctx := start()
	var tourism := ctx.system(&"tourism") as TourismSystem
	var rng := ctx.rng.state()
	advance(ctx,2)
	check_eq(ctx.events.news.size(),1)
	check_eq(ctx.events.news[0].args.identity,"carnival:3")
	check_eq(ctx.events.news[0].args.date,"April 1900")
	var current := snapshot(ctx)
	for i in 8:
		tourism.forecast()
		tourism.report()
		tourism.calendar_report()
		tourism.monthly(ctx)
	check_eq(snapshot(ctx),current)
	check_eq(ctx.events.news.size(),1)
	check_eq(ctx.rng.state(),rng)
	advance(ctx,3)
	check_eq(tourism.calendar_report().event_factors,[125,125,100,100])
	var booked: Dictionary=ctx.system(&"budget").save()
	var completed: Dictionary=tourism.save().activity
	ctx.stats.ordinances[&"annual_carnival"]=false
	tourism.reconcile_now()
	check_eq(tourism.calendar_report().event_factors,[100,100,100,100])
	check_eq(tourism.calendar_report().next_event.status,"cancelled")
	check_eq(ctx.events.news.size(),2)
	check_eq(ctx.system(&"budget").save(),booked)
	check_eq(tourism.save().activity,completed)
	ctx.stats.ordinances[&"annual_carnival"]=true
	tourism.reconcile_now()
	check_eq(tourism.calendar_report().event_factors,[100,100,100,100],"service recovery cannot revive cancelled identity")
	check_eq(ctx.events.news.size(),2)
	var saved := snapshot(ctx)
	check_eq(tourism.finish_restore(saved),OK)
	check_eq(tourism.save(),saved.systems.tourism)
	check_eq(ctx.events.news.size(),2,"restore cannot replay notices")
	check_eq(TourismSaveCodec.problem(snapshot(ctx),ctx.city),"")

func test_real_cached_stadium_and_hall_require_complete_services() -> void:
	var ctx := start(7)
	var tourism := ctx.system(&"tourism") as TourismSystem
	for at in [Vector2i(20,10),Vector2i(30,10)]:
		TourismFixture.venue(ctx.city,&"stadium",at)
		TourismFixture.set_served(ctx.city,at,true,true)
		ctx.city.building.put(at.x,9,Buildings.ROAD_FIRST)
	TourismFixture.venue(ctx.city,&"city_hall",Vector2i(40,10))
	TourismFixture.set_served(ctx.city,Vector2i(40,10),true,true)
	ctx.city.building.put(40,9,Buildings.ROAD_FIRST)
	tourism.reconcile_now()
	check_eq(tourism._districts.event_hosts(),{"stadium":true,"city_hall":true})
	advance(ctx,7)
	check_eq(ctx.events.news.size(),1,"two stadiums announce one city event")
	ctx.city.set_flag(20,10,TileFlags.WATERED,false)
	tourism.reconcile_now()
	check_eq(ctx.events.news.size(),1,"second serviced host retains event")
	ctx.city.building.put(31,11,Buildings.NONE)
	tourism.reconcile_now()
	check_eq(ctx.events.news.size(),2,"incomplete remaining host cancels once")
	check_eq(tourism.calendar_report().next_event.status,"cancelled")
	ctx.city.set_flag(40,10,TileFlags.POWERED,false)
	tourism.reconcile_now()
	check(not tourism._districts.event_hosts().city_hall)

func test_calendar_schema_rejects_malformed_and_duplicate_dates_atomically() -> void:
	var ctx := start()
	advance(ctx,2)
	var tourism := ctx.system(&"tourism") as TourismSystem
	var good := snapshot(ctx)
	var bad_values: Array=[]
	for field in ["activation_month","month_id"]:
		var bad: Dictionary=good.systems.tourism.features.calendar.duplicate(true)
		bad[field]=2.5
		bad_values.append(bad)
	for field in ["month_id","announced_month","kind","status"]:
		var bad: Dictionary=good.systems.tourism.features.calendar.duplicate(true)
		bad.events[0][field]="unknown" if field in ["kind","status"] else 999999
		bad_values.append(bad)
	var duplicate: Dictionary=good.systems.tourism.features.calendar.duplicate(true)
	duplicate.events.append(duplicate.events[0].duplicate(true))
	bad_values.append(duplicate)
	var impossible: Dictionary=good.systems.tourism.features.calendar.duplicate(true)
	impossible.events[0].status="active"
	bad_values.append(impossible)
	for bad: Dictionary in bad_values:
		var changed := good.duplicate(true)
		changed.systems.tourism.features.calendar=bad
		check(TourismSaveCodec.problem(changed,ctx.city)!="")
		var before := var_to_bytes([snapshot(ctx),ctx.city.facilities,ctx.events.news])
		check_eq(tourism.finish_restore(changed),ERR_INVALID_DATA)
		check_eq(var_to_bytes([snapshot(ctx),ctx.city.facilities,ctx.events.news]),before)
	var earlier := good.duplicate(true)
	earlier.systems.tourism.features.calendar={}
	check_eq(tourism.finish_restore(earlier),OK)
	check(tourism.save().features.calendar.events.is_empty(),"older feature absence never invents a past announcement")
	check_eq(tourism.save().activity,good.systems.tourism.activity)
	check_eq(tourism.save().features.migration,good.systems.tourism.features.migration)

func test_native_announcement_continuation_and_newspaper_text() -> void:
	var ctx := start()
	advance(ctx,2)
	var path := DIR.path_join("march.sc2d")
	check_eq(SaveFormat.save(path,ctx.city,snapshot(ctx)),OK)
	var loaded := SaveFormat.load(path)
	check(loaded.ok)
	if not loaded.ok: return
	var tourism := ctx.system(&"tourism") as TourismSystem
	var before := tourism.save()
	check_eq(tourism.finish_restore(loaded.snapshot),OK)
	check_eq(tourism.save(),before)
	check_eq(ctx.events.news.size(),1)
	advance(ctx,3)
	check_eq(tourism.calendar_report().event_factors,[125,125,100,100])
	var notice: Dictionary=ctx.events.news[0]
	var values := NewsStories.values_for(notice.kind,notice.args,"Sample","Mayor",1900)
	var body := NewsStories.body(notice.kind,notice.args,values)
	check("April 1900" in body and "Annual Carnival" in body)
	check(not "{" in body)

func remove_test_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path): return
	for folder in DirAccess.get_directories_at(path): remove_test_tree(path.path_join(folder))
	for name in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)

func test_supported_beds_are_prospective_joint_capacity_not_occupancy() -> void:
	var city := flat_city()
	var rows: Array[Dictionary]=[]
	var labels := PackedInt32Array()
	labels.resize(City.WIDTH*City.HEIGHT)
	labels.fill(-1)
	for x in [10,20]:
		city.stamp_building(x,10,Buildings.id_of(&"arcology_last"))
		rows.append({"anchor":Vector2i(x,10),"key":&"arcology_last","guests":0,"day_visitors":0,"operating":true})
		for dy in 4:
			for dx in 4: labels[(10+dy)*128+x+dx]=0
	var power := {"tiles":labels,"components":[{"spare":50}]}
	var water := {"tiles":labels,"components":[{"spare":50}]}
	var before := var_to_bytes([city.facilities,city.flags.data,rows,power,water])
	check_eq(TourismCalendar.supported_beds(city,rows,100,0,{},power,water),1000,"two600bed budget resorts, 50 water units support 1000 beds")
	check_eq(var_to_bytes([city.facilities,city.flags.data,rows,power,water]),before,"capacity probe does not install anything")
	rows[0].guests=500
	rows[1].guests=500
	check_eq(TourismCalendar.supported_beds(city,rows,100,0,{},power,water),1000,"identical support whether empty or currently occupied")
	water.components[0].spare=49
	check_eq(TourismCalendar.supported_beds(city,rows,100,0,{},power,water),980)
	water.components[0].spare=100
	check_eq(TourismCalendar.supported_beds(city,rows,50,0,{},power,water),920,"50staff leaves46variable positions at20beds each")
	check(not TourismCalendar.eligible("convention",{"city_hall":true,"business_gateway":true,"supported_beds":999}))
	check(TourismCalendar.eligible("convention",{"city_hall":true,"business_gateway":true,"supported_beds":1000}))
	check(not TourismCalendar.eligible("convention",{"city_hall":true,"business_gateway":false,"supported_beds":1200}))

func test_fixed_day_probe_keeps_day_work_and_combined_fractional_units() -> void:
	var fixture_script := load("res://tests/test_tourism_admission.gd")
	var helper = fixture_script.new()
	var f: Dictionary=helper.pair()
	helper.free()
	for row: Dictionary in f.rows:
		row.guests=600
		row.day_visitors=20
	f.budget.components[0].spare=50
	var before := var_to_bytes(f.rows)
	var plan := TourismUtilities.admission_plan(f.city,f.rows,f.budget,f.budget,true)
	check_eq(plan.rows[0].day_visitors,20)
	check_eq(plan.rows[1].day_visitors,20)
	check_eq(plan.rows[0].guests+plan.rows[1].guests,980,"50budgetwaterunits minus40fixeddayload leaves980overnights")
	check_eq(plan.water_reserved[0],50)
	check_eq(TourismCalendar.supported_beds(f.city,f.rows,100,0,{},f.budget,f.budget),980)
	f.budget.components[0].spare=100
	check_eq(TourismCalendar.supported_beds(f.city,f.rows,50,0,{},f.budget,f.budget),840,"50filled staff minus4base and4day positions leaves42overnight positions")
	check_eq(TourismCalendar.supported_beds(f.city,f.rows,6,0,{},f.budget,f.budget),0,"insufficient base/day staff cannot become guest staff")
	f.budget.components[0].spare=0
	plan=TourismUtilities.admission_plan(f.city,f.rows,f.budget,f.budget,true)
	check_eq(plan.rows[0].guests+plan.rows[1].guests,0)
	check_eq(plan.water_reserved[0],0,"infeasible fixed days cannot overbook component")
	check(not plan.rows[0].fixed_days_feasible)
	check_eq(var_to_bytes(f.rows),before,"probe leaves accepted day obligations untouched")

func test_native_year_boundary_keeps_once_guards_and_old_business() -> void:
	var ctx := start(11,1985)
	var tourism := ctx.system(&"tourism") as TourismSystem
	for month in [11,12,14,15]:
		if month==12:
			ctx.clock.day=299
			ctx.city.day=299
			ctx.system(&"budget").yearly(ctx)
		advance(ctx,month)
		var before := snapshot(ctx)
		var path := DIR.path_join("boundary-%d.sc2d" % month)
		check_eq(SaveFormat.save(path,ctx.city,before),OK)
		var loaded := SaveFormat.load(path)
		check(loaded.ok)
		if not loaded.ok: continue
		check_eq(tourism.finish_restore(loaded.snapshot),OK)
		check_eq(tourism.save(),before.systems.tourism)
		check_eq(ctx.system(&"budget").save(),before.systems.budget)
		var count := ctx.events.news.size()
		tourism.monthly(ctx)
		check_eq(ctx.events.news.size(),count)
	check_eq(ctx.events.news.size(),1)
	check_eq(ctx.events.news[0].args.date,"April 1986")
	check_eq(tourism.calendar_report().event_factors,[125,125,100,100])

## Synthetic established physical networks, not a paid/weather allocator proof.
## Actual service/access discovery and exact local source budgets feed the host.
func test_convention_host_uses_real_gateway_sources_and_live_invalidation() -> void:
	var ctx := TourismFixture.context(flat_city())
	contexts.append(ctx)
	ctx.clock.day=9*25+16
	ctx.city.day=ctx.clock.day
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN]=1000
	var city := ctx.city
	city.building.data.fill(Buildings.POWER_LINE_FIRST)
	city.underground.data.fill(Underground.PIPE_FIRST)
	city.stamp_building(20,20,Buildings.id_of(&"arcology_alibi"))
	city.stamp_building(20,30,Buildings.id_of(&"city_hall"))
	city.stamp_building(24,20,Buildings.RAIL_STATION)
	for x in range(26,128): city.building.put(x,20,Buildings.RAIL_FIRST)
	for y in range(20,34): city.building.put(19,y,Buildings.ROAD_FIRST)
	city.stamp_building(10,10,Buildings.COAL_PLANT)
	city.stamp_building(15,15,Buildings.WATER_PUMP)
	city.add_facility(Vector2i(10,10),{"key":Buildings.key(Buildings.COAL_PLANT),"capacity":5000})
	city.add_facility(Vector2i(15,15),{"key":Buildings.key(Buildings.WATER_PUMP),"output":500})
	TourismFixture.set_served(city,Vector2i(20,20),true,true)
	TourismFixture.set_served(city,Vector2i(20,30),true,true)
	city.set_flag(15,15,TileFlags.POWERED,true)
	var tourism := TourismSystem.new()
	ctx.systems[&"tourism"]=tourism
	tourism.setup(ctx)
	check_eq(tourism.finish_restore({}),OK)
	check_eq(ctx.stats.tourist_guests,0,"empty destination can support future beds")
	check_eq(tourism.calendar_report().supported_beds,1400)
	check(tourism._calendar_inputs().business_gateway)
	var before := var_to_bytes([city.facilities,ctx.rng.state(),ctx.stats.to_dict(),tourism.save()])
	var signature := tourism._calendar_probe_signature.duplicate(true)
	for i in 8: tourism.forecast()
	check_eq(tourism._calendar_probe_signature,signature,"reports never rebuild capacity probe")
	check_eq(var_to_bytes([city.facilities,ctx.rng.state(),ctx.stats.to_dict(),tourism.save()]),before)
	tourism.monthly(ctx)
	check_eq(ctx.events.news.size(),1)
	check_eq(ctx.events.news[0].args.identity,"convention:10")
	var completed: Dictionary = tourism.save().activity.duplicate(true)
	city.facility(Vector2i(15,15))["output"]=1
	tourism.reconcile_now()
	check_eq(tourism.calendar_report().supported_beds,0,"raw source reduction invalidates cached prospective beds")
	check_eq(tourism.calendar_report().next_event.status,"cancelled")
	check_eq(ctx.events.news.size(),2)
	check_eq(tourism.save().activity,completed)
	city.facility(Vector2i(15,15))["output"]=500
	tourism.reconcile_now()
	check_gt(tourism.calendar_report().supported_beds,1000)
	check_eq(tourism.calendar_report().next_event.status,"cancelled")
	city.building.put(80,20,Buildings.NONE)
	tourism.reconcile_now()
	check(not tourism._calendar_inputs().business_gateway)
	check_eq(tourism.calendar_report().supported_beds,0)
	check_eq(ctx.events.news.size(),2)
