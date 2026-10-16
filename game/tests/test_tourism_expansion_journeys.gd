# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
## Full calendar evidence: paid construction, ordinary services, households and settlement.
## Initial flat geography, treasury/year and disaster suppression are synthetic.
extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost
var construction := 0
var observations: Array = []

func before_each() -> void:
	host = Fixture.make_host(self,"tourism-expansion-journeys")
	host.set_process(false)

func after_each() -> void:
	host.free()
	await process_frame

func build(tool: int, at: Vector2i, end := Vector2i(-1,-1)) -> void:
	if end.x < 0: end=at
	host.select_tool(tool)
	var before := host.sim.city.funds
	var result := host.handle_drag(at,end)
	check(result.get("applied",false),"paid construction %s %s: %s"%[tool,at,result])
	check_eq(host.sim.city.funds,before-int(result.get("cost",0)),"construction funds conserved")
	construction += int(result.get("cost",0))
	if host.choice_dialog.visible:
		var cash := host.sim.city.funds
		host.choice_dialog.build_button.pressed.emit()
		construction += cash-host.sim.city.funds

func setup_city(scenario: String, occupancy: int = 7, gaming: int = 7) -> void:
	var city := flat_city(1000000)
	city.name = "Tourism expansion "+scenario
	city.founded_year=2050
	host.begin_city(city,{},123,null)
	host.sim.set_process(false)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.sim.stats.disasters_enabled=false
	host.sim.stats.tax_occupancy=occupancy
	host.sim.stats.tax_gaming=gaming
	host.sim.stats.ordinances[&"casino_safety"]=true
	construction=0
	build(Tools.Kind.COAL_PLANT,Vector2i(32,36))
	build(Tools.Kind.POWER_LINE,Vector2i(36,37),Vector2i(68,37))
	build(Tools.Kind.ROAD,Vector2i(68,43),Vector2i(0,43))
	build(Tools.Kind.WATER_PIPE,Vector2i(36,38),Vector2i(68,38))
	for x in range(36,37 if scenario=="water" else 44):
		build(Tools.Kind.WATER_PUMP,Vector2i(x,36))
		build(Tools.Kind.WATER_PIPE,Vector2i(x,37),Vector2i(x,38))
	for x in [40,44,48,52,56,60,64,68]:
		build(Tools.Kind.POWER_LINE,Vector2i(x,38))
		build(Tools.Kind.WATER_PIPE,Vector2i(x,39),Vector2i(x,48))
	build(Tools.Kind.POWER_LINE,Vector2i(39,38),Vector2i(39,48))
	build(Tools.Kind.POWER_LINE,Vector2i(40,48),Vector2i(68,48))
	if scenario != "store":
		build(Tools.Kind.ARCOLOGY_VELVET if scenario=="premium" else Tools.Kind.ARCOLOGY_BODDY,Vector2i(40,39))
	if scenario in ["cluster","oversupply"]:
		for x in range(44,64,4): build(Tools.Kind.ARCOLOGY_BODDY,Vector2i(x,39))
	build(Tools.Kind.POWER_LINE,Vector2i(63,38),Vector2i(63,42))
	build(Tools.Kind.ZONE_COM_LOW,Vector2i(64,40),Vector2i(68,42))
	build(Tools.Kind.ZONE_RES_LOW,Vector2i(40,44),Vector2i(68,46))
	check_eq(host.sim.city.funds,1000000-construction,"one initial treasury less actual paid works")
	host.select_tool(Tools.Kind.QUERY)

func advance_to(day: int) -> void:
	while host.sim.clock.day < day:
		if host.sim.budget_review_pending: (host.windows.budget as BudgetWindow).close()
		host.sim.advance_day()

func measure(scenario: String, month: int) -> Dictionary:
	var sim := host.sim
	var tourism := sim.tourism()
	var stats := sim.stats
	var budget: Dictionary = sim.get_system(&"budget").save()
	var utility := tourism.utility_report()
	var staff := tourism.staffing_report()
	var rep := tourism.reputation_report()
	var rows := tourism.report()
	var pressure := 0.0
	var segments := [0,0,0,0]
	for row: Dictionary in rows:
		check_eq(TourismMarkets.sum_counts(row.guest_segments),row.guests)
		check_eq(TourismMarkets.sum_counts(row.day_segments),row.day_visitors)
		check(row.guests<=row.capacity,"physical beds bound current attendance")
		pressure += float(row.crime_source_micro)/1000000.0
		for i in 4: segments[i]+=int(row.guest_segments[i])+int(row.day_segments[i])
	check_eq(stats.tourists,stats.tourist_guests+stats.tourist_day_visitors)
	check_eq(stats.tourism_jobs,tourism.jobs(),"census/delta publishes one jobs contribution")
	var booking: Dictionary=budget.tourism_booking
	return {"scenario":scenario,"month":month,"day":sim.clock.day,"occupancy_rate":stats.tax_occupancy,"gaming_rate":stats.tax_gaming,"guests":stats.tourist_guests,"days":stats.tourist_day_visitors,"segments":segments,"population":stats.population,"jobs":stats.jobs,"tourism_jobs":stats.tourism_jobs,"local_staff":staff.local_staff,"incoming_staff":staff.incoming_staff,"unemployment":stats.unemployment,"approval":stats.approval,"crime":stats.average_crime,"casino_source":pressure,"traffic":stats.average_traffic,"power":stats.power_demand,"water":stats.water_demand,"water_capacity":stats.water_capacity,"water_consumed":sim.get_system(&"water").consumed(),"unwatered":stats.unwatered_buildings,"visitor_power":utility.power,"visitor_water":utility.water,"utility_limited":utility.limited_venues,"reputation":rep.value_milli,"experience":rep.experience_milli,"future_factor":rep.future_factor_milli,"occupancy_twelfth_cents":booking.get("occupancy_units",0),"gaming_twelfth_cents":booking.get("gaming_units",0),"program_half_cents":budget.tourism_program_booking.get("half_cents",0),"funds":sim.city.funds,"construction":construction,"year_ledger":stats.last_year_ledger.duplicate(),"economy_phase":stats.economy_phase,"season":tourism.calendar_report().season_percent}

func run_months(scenario: String, months: int = 36) -> Array:
	var result: Array=[]
	for month in months:
		advance_to(month*25+18)
		result.append(measure(scenario,month))
	return result

func emit_rows(label: String, rows: Array) -> void:
	print(label," ",JSON.stringify(rows))
	var directory := OS.get_environment("TOURISM_EXPANSION_OUTPUT")
	if not directory.is_empty():
		DirAccess.make_dir_recursive_absolute(directory)
		var file := FileAccess.open(directory.path_join(label+".json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(rows,"  "))

func test_full_calendar_paid_balance_pilot() -> void:
	for scenario in ([OS.get_environment("TOURISM_PILOT_SCENARIO")] if not OS.get_environment("TOURISM_PILOT_SCENARIO").is_empty() else ["small","premium","water"]):
		setup_city(scenario)
		check_eq(host.sim.city.current_year(),2050,"synthetic era is explicit")
		var expected := Buildings.ARCOLOGY_VELVET if scenario=="premium" else Buildings.ARCOLOGY_BODDY
		check_eq(host.sim.city.building_at(40,39),expected,"requested paid venue actually exists")
		var start := Time.get_ticks_usec()
		var rows := run_months(scenario)
		emit_rows("pilot-"+scenario,rows)
		print("FULL_HOST_RUNTIME_US ",scenario," ",Time.get_ticks_usec()-start)
		check_gt(rows[0].guests,0,"paid founding venue admits guests")
		if scenario!="water": check_gt(rows[-1].population,0,"ordinary zoned households survive multi-year feedback")

func test_independent_full_calendar_tax_sweeps() -> void:
	# The complete measured sweep is opt-in for evidence runs; the ordinary
	# regression still runs both axes through representative endpoints.
	var extensive := OS.get_environment("TOURISM_FULL_SWEEP")=="1"
	var rates: Array = range(21) if extensive else [0,20]
	for scenario in (["small","premium","water"] if extensive else ["premium"]):
		for axis in ["occupancy","gaming"]:
			for rate: int in rates:
				setup_city(scenario,rate if axis=="occupancy" else 7,rate if axis=="gaming" else 7)
				var rows:=run_months(scenario)
				var measured:=rows.slice(24,36)
				check_eq(measured.size(),12,"24 settling plus12 measured complete booking months")
				for row: Dictionary in measured:
					if rate==0: check_eq(row[axis+"_twelfth_cents"],0,"zero rate cannot accrue that tax")
				emit_rows("sweep-"+scenario+"-"+axis+"-%02d"%rate,rows)

func save_pose(name: String) -> void:
	var directory := OS.get_environment("TOURISM_EXPANSION_OUTPUT")
	if directory.is_empty(): return
	DirAccess.make_dir_recursive_absolute(directory)
	check_eq(SaveFormat.save(directory.path_join(name+".sc2d"),host.sim.city,host.sim.snapshot()),OK)

func test_named_paid_city_journeys_and_closed_loop_recovery() -> void:
	for scenario in ["store","cluster","premium","mixed","water","oversupply"]:
		setup_city(scenario)
		if scenario=="mixed":
			build(Tools.Kind.STADIUM,Vector2i(44,39))
			build(Tools.Kind.MUSEUM,Vector2i(48,39))
			build(Tools.Kind.ZOO,Vector2i(52,39))
			build(Tools.Kind.SMALL_PARK,Vector2i(56,41))
		if scenario=="oversupply":
			build(Tools.Kind.ARCOLOGY_AFTERGLOW,Vector2i(56,49))
			build(Tools.Kind.ROAD,Vector2i(40,53),Vector2i(68,53))
			build(Tools.Kind.ROAD,Vector2i(68,44),Vector2i(68,52))
			build(Tools.Kind.WATER_PIPE,Vector2i(56,49),Vector2i(56,52))
		var rows:=run_months(scenario,48)
		emit_rows("journey-"+scenario,rows)
		if scenario=="store":
			var days:=0
			for row: Dictionary in rows: days=maxi(days,int(row.days))
			check_gt(days,0,"paid commercial zoning develops founding day-only gaming")
			for row: Dictionary in rows: check_eq(row.guests,0,"store has no beds")
		if scenario=="water": save_pose("constrained")
		if scenario=="premium": save_pose("premium")
		if scenario=="mixed": save_pose("mixed")
		check_eq(rows[6].season,75,"explicit July trough")
		check_eq(rows[11].season,120,"explicit December peak")
		check(rows[-1].population>=0,"tourists never create negative residents")
	setup_city("small")
	save_pose("empty")
	var recovery:=run_months("housing-neighbors",24)
	save_pose("full")
	var near:=Vector2i(40,44)
	var far:=Vector2i(64,44)
	print("HOUSING_NEIGHBORS ",JSON.stringify({"near_land_value":host.sim.city.land_value_at(near.x,near.y),"far_land_value":host.sim.city.land_value_at(far.x,far.y),"near_crime":host.sim.city.crime_at(near.x,near.y),"far_crime":host.sim.city.crime_at(far.x,far.y),"population":host.sim.stats.population}))
	# Employment/service changes are paid city edits, never cohort replacement.
	build(Tools.Kind.ZONE_IND_LOW,Vector2i(44,39),Vector2i(60,42))
	for month in range(24,36):
		advance_to(month*25+18)
		recovery.append(measure("labor-recovery",month))
	advance_to(917) # March accepted period, earned business still pending.
	var t:=host.sim.tourism()
	var pending:=t.pending_bases().duplicate(true)
	var rep:int=t.reputation_report().value_milli
	build(Tools.Kind.BULLDOZE,Vector2i(32,36))
	check_eq(host.sim.stats.tourists,0,"real power demolition immediately closes tourism")
	check_eq(t.pending_bases(),pending,"service collapse preserves earned money")
	check_eq(t.reputation_report().value_milli,rep,"daily closure does not award or replay experience")
	check_eq(t.supported_forecast().guests,0)
	recovery.append(measure("service-collapse",36))
	advance_to(968)
	build(Tools.Kind.COAL_PLANT,Vector2i(32,36))
	check_eq(host.sim.stats.tourists,0,"recovery does not readmit outside day17")
	for month in range(39,51):
		advance_to(month*25+18)
		recovery.append(measure("service-recovery",month))
	check_gt(host.sim.stats.tourists,0,"paid source restoration recovers attendance on monthly schedule")
	emit_rows("journey-recovery",recovery)

func test_announced_cancelled_event_and_recession_real_calendar() -> void:
	setup_city("small")
	# Deliberate initial national recession input, then ordinary economy updates.
	host.sim.stats.economy_phase=0
	host.sim.stats.ordinances[&"annual_carnival"]=true
	advance_to(68)
	var t:=host.sim.tourism()
	var event: Dictionary=t.calendar_report().next_event
	check_eq(event.get("status"),"announced")
	save_pose("event")
	var rows: Array=[measure("recession-announcement",2)]
	host.sim.stats.ordinances[&"annual_carnival"]=false
	host.sim.advance_day()
	check_eq(t.calendar_report().next_event.status,"cancelled")
	advance_to(93)
	check_eq(t.calendar_report().event_factors,[100,100,100,100],"cancelled event adds no demand")
	rows.append(measure("cancelled-event",3))
	advance_to(293)
	rows.append(measure("peak-season",11))
	check_eq(rows[-1].season,120)
	emit_rows("journey-event-recession-peak",rows)

func test_paid_rail_and_airport_business_routes() -> void:
	setup_city("premium")
	build(Tools.Kind.RAIL_STATION,Vector2i(60,44))
	build(Tools.Kind.RAIL,Vector2i(60,46),Vector2i(60,50))
	build(Tools.Kind.RAIL,Vector2i(60,50),Vector2i(0,50))
	build(Tools.Kind.POWER_LINE,Vector2i(59,44),Vector2i(59,48))
	build(Tools.Kind.AIRPORT,Vector2i(72,38),Vector2i(79,45))
	build(Tools.Kind.POWER_LINE,Vector2i(69,37),Vector2i(79,37))
	build(Tools.Kind.ROAD,Vector2i(69,43),Vector2i(71,43))
	var rows:=run_months("gateway-business",36)
	var kinds: Array=[]
	for gateway: Dictionary in host.sim.tourism().access_routes().gateways(): kinds.append(gateway.kind)
	check(kinds.has("rail"),"paid station and rail border establish actual business gateway")
	check(kinds.has("airport"),"paid airport zone naturally builds an operating civilian gateway")
	print("BUSINESS_GATEWAYS ",JSON.stringify(host.sim.tourism().access_routes().gateways()))
	emit_rows("journey-gateway-business",rows)

func test_program_cost_and_crime_are_accepted_together_in_real_hosts() -> void:
	setup_city("small")
	advance_to(291)
	var path: String="user://tourism-expansion-program.sc2d"
	check_eq(SaveFormat.save(path,host.sim.city,host.sim.snapshot()),OK)
	var rows: Array=[]
	for active in [false,true]:
		check(host.load_city(path))
		host.sim.set_process(false)
		host.sim.stats.ordinances[&"casino_safety"]=active
		advance_to(293)
		var row:=measure("program-on" if active else "program-off",11)
		row["active"]=active
		rows.append(row)
	check_eq(rows[0].guests,rows[1].guests,"same accepted demand and staffing")
	check_eq(rows[0].days,rows[1].days)
	check_eq(rows[0].program_half_cents,0)
	check_gt(rows[1].program_half_cents,0,"actual Budget books accepted program cost")
	check(rows[1].casino_source<rows[0].casino_source,"accepted program reduces actual source before ordinary police")
	check(absf(float(rows[1].casino_source)/float(rows[0].casino_source)-0.6)<0.00001,"40 percent source reduction")
	emit_rows("journey-program-pair",rows)
	DirAccess.remove_absolute(path)

func test_city_scale_host_has_finite_attendance() -> void:
	# Explicit imported-style synthetic full-map physical stock; all ordinary
	# systems still run. With no streets or sources it cannot mint visitors.
	var city:=flat_city(1000000)
	for y in City.HEIGHT:
		for x in City.WIDTH: city.stamp_building(x,y,Buildings.id_of(&"com_corner_store"))
	host.begin_city(city,{},123,null)
	host.sim.set_process(false)
	host.sim.stats.disasters_enabled=false
	advance_to(18)
	check_eq(host.sim.tourism().report().size(),16384)
	check_eq(host.sim.stats.tourists,0)
	check_eq(host.sim.stats.ledger.get(&"taxes_gaming",0),0)
	emit_rows("journey-maxcity",[measure("maxcity",0)])


func _run_all() -> void:
	var selector := OS.get_environment("TOURISM_JOURNEY_CASE")
	await before_all()
	for method: Dictionary in get_method_list():
		var method_name: String=method.name
		if not method_name.begins_with("test_") or (not selector.is_empty() and not method_name.contains(selector)): continue
		_current=method_name
		await before_each()
		var failures_before:=_failed
		await call(method_name)
		await after_each()
		if _failed==failures_before: _passed+=1
		else: print("  FAIL ",method_name)
	await after_all()
	await process_frame
	print("Results: %d passed, %d failed"%[_passed,_failed])
	quit(0 if _failed==0 else 1)
