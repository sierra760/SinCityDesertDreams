# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

func test_empty_labor_cannot_admit_small_target_into_large_physical_resort() -> void:
	var rows: Array[Dictionary] = [{"anchor":Vector2i(10,10),"key":&"arcology_afterglow","operating":true,"guests":0}]
	var result := TourismDemand.forecast(rows,{"resident_workers":0,"non_tourism_jobs":0},0,0)
	check_eq(result.guests,0,"zero labor cannot admit even demand far below the 5000 physical beds")
	check_eq(result.day_visitors,0,"day capacity also needs staff")

var contexts: Array[SimContext] = []
const DIR := "user://tourism-staffing-tests"

func after_each() -> void:
	for ctx in contexts: ctx.systems.clear()
	contexts.clear()

func after_all() -> void:
	remove_test_tree(DIR)

func row_at(x: int, key: StringName, guests: int, days: int = 0) -> Dictionary:
	return {"anchor":Vector2i(x,10),"key":key,"operating":true,"target_guests":guests,"target_day_visitors":days,"gateway_ids":["road-west"]}

func test_shared_labor_proportional_opportunities_canonical_remainders() -> void:
	var rows: Array[Dictionary] = [row_at(30,&"arcology_afterglow",100),row_at(10,&"arcology_boddy",100),row_at(20,&"arcology_comstock",100)]
	var result := TourismEconomy.allocate(rows,14,28,{})
	# 7+9+12 tourism positions against 28 ordinary opportunities: exactly 7 locals.
	check_eq(result.positions,28)
	check_eq(result.local_staff,7)
	check_eq(result.rows[0].local_staff,2)
	check_eq(result.rows[1].local_staff,2)
	check_eq(result.rows[2].local_staff,3)
	check_eq(result.rows[2].supported_capacity,10,"one premium service position after base supports ten planned guests, not hundreds of physical beds")
	check_eq(result.rows[0].supported_capacity,0)
	check_eq(result.rows[2].planned_guests,100)
	check_eq(rows[0].target_guests,100,"pure allocation does not mutate input")
	var reverse: Array[Dictionary] = rows.duplicate(true)
	reverse.reverse()
	check_eq(TourismEconomy.allocate(reverse,14,28,{}),result)

func test_regional_allowance_shared_once_and_capped_and_store_only_incremental() -> void:
	var rows: Array[Dictionary] = [row_at(10,&"arcology_afterglow",5000),row_at(20,&"arcology_afterglow",5000)]
	var access := {"gateways":[{"id":"road-west"}]}
	var result := TourismEconomy.allocate(rows,0,0,access)
	check_eq(result.incoming_allowance,8)
	check_eq(result.rows[0].incoming_staff+result.rows[1].incoming_staff,8)
	check_eq(result.rows[0].supported_capacity,20)
	for i in 30:
		access.gateways.append({"id":"gate-%d"%i})
		for row in rows: row.gateway_ids.append("gate-%d"%i)
	result = TourismEconomy.allocate(rows,0,0,access)
	check_eq(result.incoming_allowance,64)
	check_eq(result.rows[0].incoming_staff+result.rows[1].incoming_staff,64)
	var shop: Array[Dictionary] = [row_at(10,&"com_corner_store",0,24)]
	result = TourismEconomy.allocate(shop,0,0,access)
	check_eq(result.positions,2,"only gaming day positions, no duplicated ordinary shop jobs or resort base")
	check_eq(result.rows[0].supported_day_capacity,24)
	check_eq(result.rows[0].supported_capacity,0)

func start() -> SimContext:
	var ctx := TourismFixture.host_with_store(0)
	contexts.append(ctx)
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN] = 20
	ctx.stats.population = 20
	return ctx

func accept_month(ctx: SimContext, month: int) -> void:
	ctx.clock.day = month*25+16
	ctx.city.day = ctx.clock.day
	ctx.system(&"tourism").monthly(ctx)
	ctx.system(&"budget").monthly(ctx)

func test_both_census_replacements_delta_closure_and_read_purity() -> void:
	var ctx := start()
	ctx.city.zone.put(10,10,Zones.COM_LOW | Zones.CORNER_NW)
	var tourism := ctx.system(&"tourism") as TourismSystem
	var zones := ZoneSystem.new()
	var population := PopulationSystem.new()
	ctx.systems[&"zones"] = zones
	ctx.systems[&"population"] = population
	zones.setup(ctx)
	population.setup(ctx)
	var ordinary := ctx.stats.jobs
	check(ordinary > 0,"ordinary store employment is present")
	accept_month(ctx,0)
	check(tourism.jobs()>0)
	check_eq(ctx.stats.jobs,ordinary+tourism.jobs())
	for i in 2:
		zones._take_census(ctx.city,ctx.stats)
		zones._add_port_jobs(ctx)
		check_eq(ctx.stats.jobs,ordinary+tourism.jobs(),"zones replaces, then contributes once")
		population._run_census(ctx)
		check_eq(ctx.stats.jobs,ordinary+tourism.jobs(),"population replacement retains exactly one contribution")
	var before := JSON.stringify(tourism.save(),"",true)
	var stats := ctx.stats.to_dict()
	var random_state := ctx.rng.state()
	for i in 4:
		tourism.report()
		tourism.forecast()
		tourism.staffing_report()
	check_eq(JSON.stringify(tourism.save(),"",true),before)
	check_eq(ctx.stats.to_dict(),stats)
	check_eq(ctx.rng.state(),random_state)
	var earned: Dictionary = tourism.save().activity.duplicate(true)
	var budget := ctx.system(&"budget").save()
	TourismFixture.set_served(ctx.city,Vector2i(10,10),false,true)
	tourism.reconcile_now()
	check_eq(tourism.jobs(),0)
	check_eq(ctx.stats.jobs,ordinary)
	check_eq(tourism.save().activity,earned,"closure does not rewrite completed business")
	check_eq(ctx.system(&"budget").save(),budget)

func test_schema3_predecessor_gets_absolute_grace_once_and_expired_grace_stays_expired() -> void:
	var ctx := start()
	var tourism := ctx.system(&"tourism") as TourismSystem
	var block := tourism.save()
	block.features.staffing = {}
	block.features.utilities = {} # This predecessor predates accepted utility reservations.
	block.state.records[0].day_visitors = 12
	block.state.records[0].day_segments = [7,3,0,2]
	check_eq(tourism.finish_restore({"systems":{"tourism":block}}),OK)
	check_eq(tourism.save().features.migration.grace_until_month,1)
	var initialized := tourism.save()
	ctx.clock.day = 3*25
	ctx.city.day = ctx.clock.day
	check_eq(tourism.finish_restore({"systems":{"tourism":initialized}}),OK)
	check_eq(tourism.save().features.migration.grace_until_month,1)
	initialized.features.staffing = {}
	check_eq(tourism.finish_restore({"systems":{"tourism":initialized}}),OK)
	check_eq(tourism.save().features.migration.grace_until_month,1,"owned feature cannot renew a prior absolute expiry")
	check_eq(tourism.save().features.staffing.initialized_month,3)

func snapshot(ctx: SimContext) -> Dictionary:
	return {"clock_day":ctx.clock.day,"stats":ctx.stats.to_dict(),"rng_seed":str(ctx.rng.seed_value()),"rng_state":str(ctx.rng.state()),"systems":{"tourism":ctx.system(&"tourism").save(),"budget":ctx.system(&"budget").save()}}

func test_local_cloud_continuation_and_atomic_staffing_rejection() -> void:
	var ctx := start()
	accept_month(ctx,0)
	var before := snapshot(ctx)
	var path := DIR.path_join("staff.sc2d")
	check_eq(SaveFormat.save(path,ctx.city,before),OK)
	var store := CloudSaveStore.new(DIR.path_join("cloud"))
	check_eq(store.open_library("private-test-account"),OK)
	var staged := store.stage(store.create_slot(),path)
	check(not staged.is_empty())
	if staged.is_empty(): return
	var local := SaveFormat.load(path)
	var cloud := SaveFormat.load(staged.continuation.path)
	check(local.ok and cloud.ok)
	if not local.ok or not cloud.ok: return
	check_eq(JSON.stringify(local.snapshot,"",true),JSON.stringify(cloud.snapshot,"",true))
	var twin := TourismFixture.context(cloud.city)
	contexts.append(twin)
	twin.stats.from_dict(cloud.snapshot.stats)
	for system: SimSystem in [TourismSystem.new(),BudgetSystem.new()]:
		twin.systems[system.key] = system
		system.setup(twin)
	twin.system(&"budget").load(cloud.snapshot.systems.budget)
	check_eq(twin.system(&"tourism").finish_restore(cloud.snapshot),OK)
	check_eq(JSON.stringify(snapshot(twin),"",true),JSON.stringify(before,"",true))
	for month in range(1,4):
		accept_month(ctx,month)
		accept_month(twin,month)
		check_eq(JSON.stringify(snapshot(ctx),"",true),JSON.stringify(snapshot(twin),"",true))
	var tourism := ctx.system(&"tourism") as TourismSystem
	var valid := tourism.save()
	for field in ["positions","local_staff","incoming_staff","supported_capacity","staffing_percent"]:
		var bad := snapshot(ctx)
		bad.systems.tourism.features.staffing.rows[0][field] += 100
		check(not TourismSaveCodec.problem(bad,ctx.city).is_empty(),"detached malformed "+field)
		check_eq(tourism.finish_restore(bad),ERR_INVALID_DATA)
		check_eq(tourism.save(),valid,"atomic malformed "+field)

func test_workforce_recovery_and_no_tourist_resident_transfer() -> void:
	var rows: Array[Dictionary] = [row_at(10,&"arcology_afterglow",100,20)]
	var empty := TourismEconomy.allocate(rows,0,100,{})
	var recovered := TourismEconomy.allocate(rows,10000,100,{})
	check_eq(empty.rows[0].supported_capacity,0)
	check_eq(recovered.rows[0].supported_capacity,100)
	check_eq(recovered.rows[0].supported_day_capacity,20)
	var ctx := start()
	var residents := ctx.stats.population
	var cohorts := ctx.stats.cohorts.duplicate()
	accept_month(ctx,0)
	check_eq(ctx.stats.population,residents)
	check_eq(ctx.stats.cohorts,cohorts)
	check_eq(ctx.stats.tourists,ctx.stats.tourist_guests+ctx.stats.tourist_day_visitors)

func remove_test_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path): return
	for folder in DirAccess.get_directories_at(path): remove_test_tree(path.path_join(folder))
	for name in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)

func test_partial_staffing_inverts_requirements_and_zero_occupancy_keeps_positions() -> void:
	var rows: Array[Dictionary] = [row_at(10,&"arcology_afterglow",100,24)]
	var plan := TourismEconomy.allocate(rows,9,0,{})
	# Fourteen offered: base2 + ten guest staff + two day staff. Nine workers
	# leave seven visitor positions, canonically split six guest / one day.
	check_eq(plan.positions,14)
	check_eq(plan.rows[0].supported_capacity,60)
	check_eq(plan.rows[0].supported_day_capacity,12)
	check_eq(plan.rows[0].staffing_percent,64)
	rows[0].guests = 0
	check_eq(TourismEconomy.allocate(rows,0,0,{}).positions,14,"no occupancy/job circular deadlock")
	var no_gateway := TourismEconomy.allocate(rows,0,0,{"gateways":[{"id":"unreachable"}]})
	check_eq(no_gateway.incoming_allowance,0,"only connected qualifying gateways supply workers")

func test_allocator_measured_city_scale_and_shared_budget_bounds() -> void:
	var rows: Array[Dictionary] = []
	for i in 1024:
		var row := row_at(i%128,&"arcology_afterglow",100,24)
		row.anchor.y = i/128
		rows.append(row)
	var start_us := Time.get_ticks_usec()
	var result := TourismEconomy.allocate(rows,1000,2000,{"gateways":[{"id":"road-west"}]})
	var local := 0
	var incoming := 0
	for row: Dictionary in result.rows:
		local += int(row.local_staff)
		incoming += int(row.incoming_staff)
	check(local <= 1000)
	check_eq(incoming,8)
	check_eq(local,1000*14336/16336)
	print("STAFFING_SCALE venues=1024 local=",local," incoming=",incoming," elapsed_us=",Time.get_ticks_usec()-start_us)

func test_saved_grace_bypasses_only_staff_limit_and_then_expires() -> void:
	var rows: Array[Dictionary] = [{"anchor":Vector2i(10,10),"key":&"arcology_afterglow","operating":true,"guests":100,"day_visitors":12}]
	var inputs := {"resident_workers":0,"non_tourism_jobs":0,"staffing_grace":true}
	var grace := TourismDemand.forecast(rows,inputs,0,0)
	check_eq(grace.rows[0].supported_capacity,0,"staff report remains factual during grace")
	check_eq(grace.rows[0].target_guests,100,"old guests retain the month's ordinary turnover target")
	check_eq(grace.rows[0].target_day_visitors,12)
	inputs.staffing_grace = false
	var constrained := TourismDemand.forecast(rows,inputs,0,0)
	check_eq(constrained.rows[0].target_guests,0)
	check_eq(constrained.rows[0].target_day_visitors,0)
	check_eq(TourismDemand.turnover(100,constrained.rows[0].target_guests).guests,50,"normal departures reduce retained guests gradually after grace")
	rows[0].operating = false
	inputs.staffing_grace = true
	check_eq(TourismDemand.forecast(rows,inputs,0,0).rows[0].target_guests,0,"grace never bypasses essential-service closure")

func test_accepted_staffing_rejects_malformed_source_rows_without_installing() -> void:
	var ctx := start()
	accept_month(ctx,0)
	var tourism := ctx.system(&"tourism") as TourismSystem
	var valid := snapshot(ctx)
	check(not valid.systems.tourism.features.staffing.rows.is_empty(),"exercise accepted staffing, not its neutral fast path")
	for field in ["key","instance","code","operating"]:
		for malformed: Variant in [null,{},[],"invalid",1.5]:
			var bad := valid.duplicate(true)
			var row: Dictionary = bad.systems.tourism.state.records[0]
			if malformed == null:
				row.erase(field)
			else:
				row[field] = malformed
			var label := "%s=%s" % [field,str(malformed)]
			check(not TourismSaveCodec.problem(bad,ctx.city).is_empty(),"public codec rejects malformed source "+label)
			check_eq(tourism.finish_restore(bad),ERR_INVALID_DATA,"restore rejects malformed source "+label)
			check_eq(snapshot(ctx),valid,"malformed source cannot install partial state "+label)
			check_eq(TourismEconomy.decode(bad.systems.tourism.features.staffing,bad.systems.tourism,0).get("ok"),false,"staffing boundary explicitly rejects "+label)

func test_accepted_staffing_rejects_malformed_source_containers() -> void:
	var ctx := start()
	accept_month(ctx,0)
	var valid := snapshot(ctx)
	var tourism := ctx.system(&"tourism") as TourismSystem
	for field in ["state","records","row"]:
		for malformed: Variant in [null,7,"invalid",[]]:
			var bad := valid.duplicate(true)
			if field == "state": bad.systems.tourism.state = malformed
			elif field == "records": bad.systems.tourism.state.records = malformed
			else: bad.systems.tourism.state.records = [malformed]
			var label := "%s=%s" % [field,str(malformed)]
			check(not TourismSaveCodec.problem(bad,ctx.city).is_empty(),"public codec rejects source container "+label)
			check_eq(tourism.finish_restore(bad),ERR_INVALID_DATA,"restore rejects source container "+label)
			check_eq(snapshot(ctx),valid,"source container cannot install partial state "+label)
			check_eq(TourismEconomy.decode(bad.systems.tourism.features.staffing,bad.systems.tourism,0).get("ok"),false,"staffing explicitly rejects source container "+label)
