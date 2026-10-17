# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

func test_reputation_scales_finite_pools_without_new_visitors() -> void:
	var rows: Array[Dictionary]=[]
	var low := TourismDemand.forecast(rows,{"reputation_factor_milli":75000},0,0)
	var high := TourismDemand.forecast(rows,{"reputation_factor_milli":120000},0,0)
	check_eq(low.guest_pool,131,"175 finite overnight pool at75%, floored")
	check_eq(high.guest_pool,210,"175 finite overnight pool at120%")
	check_eq(low.day_pool,43,"58 day pool at75%, floored")
	check_eq(high.day_pool,69,"58 day pool at120%, floored")

func test_exact_quarter_caps_fraction_and_empty_guard() -> void:
	var path := "res://scripts/sim/tourism_reputation.gd"
	check(ResourceLoader.exists(path),"pure reputation model exists")
	if not ResourceLoader.exists(path): return
	var model: GDScript=load(path)
	var initial: Dictionary=model.initial(0)
	var original := var_to_bytes(initial)
	var state: Dictionary=model.advance(initial,{"month_id":0,"value_milli":100000},10)
	check_eq(state.value_milli,63000)
	check_eq(var_to_bytes(initial),original,"pure transition")
	check_eq(model.advance(state,{"month_id":0,"value_milli":0},10),state,"same month cannot replay")
	state=model.advance(state,{"month_id":1,"value_milli":0},10)
	check_eq(state.value_milli,55000)
	state=model.advance(state,{"month_id":2,"value_milli":55001},10)
	check_eq(state.value_milli,55000)
	check_eq(state.quarter_remainder,1,"quarter milli retained")
	state=model.advance(state,{"month_id":3,"value_milli":55003},10)
	check_eq(state.value_milli,55001,"carried quarter completes milli")
	for month in [4,5,6]:
		state=model.advance(state,{"month_id":month,"value_milli":100000},0)
		check_eq(state.value_milli,55001,"first three empty months cannot farm reputation")
	state=model.advance(state,{"month_id":7,"value_milli":100000},0)
	check_eq(state.value_milli,56001,"after three empty months drift at most one toward60")
	check_eq(state.experience_milli,-1,"empty has no invented experience")
	check_eq(model.factor_milli(60000),100000)
	check_eq(model.factor_milli(0),75000)
	check_eq(model.factor_milli(100000),120000)

func ideal_budget() -> Dictionary:
	return {"key":&"arcology_boddy","opening_guests":100,"natural_departures":50,"resource_departures":0,
		"guests":100,"day_visitors":0,"operating":true,"local_staff":10,"incoming_staff":0,
		"external_reachable":true,"crime":0,"attraction_appeal_bonus":0,
		"guest_half_segments":[200,0,0,0],"day_segments":[0,0,0,0]}

func test_named_weights_budget_excellence_service_failure_and_recovery() -> void:
	for vector: Array in TourismParams.EXPERIENCE_WEIGHTS:
		check_eq(TourismMarkets.sum_counts(vector),100)
	var row := ideal_budget()
	var before := var_to_bytes(row)
	var healthy := TourismReputation.venue_experience(row,0)
	check_eq(healthy.segment_scores_milli,[90000,70000,75000,90000],"independent dot products: no attraction, all other needs fulfilled")
	check_eq(var_to_bytes(row),before)
	row.resource_departures=30
	row.guests=20
	row.guest_half_segments=[120,0,0,0]
	var bad := TourismReputation.completed([row],0,0)
	check_eq(bad.value_milli,40000,"20 of50 natural survivors served: essential ceiling40")
	check_eq(bad.visitor_half_units,120,"opening100 + closing20, not staff or arrivals")
	var state := TourismReputation.advance(TourismReputation.initial(0),bad,bad.visitor_half_units)
	check_eq(state.value_milli,55000)
	var high := TourismReputation.initial(0)
	high.value_milli=90000
	check_eq(TourismReputation.advance(high,bad,120).value_milli,82000)
	row=ideal_budget()
	row.guests=50
	check_eq(TourismReputation.venue_experience(row,0).segment_scores_milli[0],90000,"ordinary natural departures never imply failed service")
	for month in [1,2,3]:
		var previous := int(state.value_milli)
		state=TourismReputation.advance(state,{"month_id":month,"value_milli":90000},100)
		check_eq(state.value_milli,previous+3000,"recovery is gradual even after excellent visits")
	row.guests=0
	row.resource_departures=50
	check_eq(TourismReputation.venue_experience(row,0).segment_scores_milli,[0,0,0,0],"all actual survivors displaced gives zero fulfilled experience")

func test_exposure_weighting_uses_actual_segments_and_all_needs() -> void:
	var a := ideal_budget()
	var b := ideal_budget()
	b.guest_half_segments=[0,0,0,0]
	b.day_segments=[0,10,0,0]
	var score := TourismReputation.completed([a,b],0,0)
	check_eq(score.visitor_half_units,220)
	check_eq(score.value_milli,88181,"(200*90 +20*70)/220 points, floor only after summing")
	for field in ["crime","attraction_appeal_bonus","local_staff","external_reachable"]:
		var changed := a.duplicate(true)
		changed[field]={"crime":255,"attraction_appeal_bonus":20,"local_staff":0,"external_reachable":false}[field]
		check(TourismReputation.venue_experience(changed,0)!=TourismReputation.venue_experience(a,0),"each fulfilled need changes experience: "+field)
	check_eq(TourismReputation.venue_experience(a,255).segment_scores_milli[0],65000,"fully congested access loses budget25 points")
	var empty := a.duplicate(true)
	empty.guest_half_segments=[0,0,0,0]
	empty.day_segments=[0,0,0,0]
	check_eq(TourismReputation.completed([empty],0,0).value_milli,-1,"empty hotel cannot provide positive experience")

var contexts: Array[SimContext]=[]
const DIR := "user://tourism-reputation-tests"
func after_each() -> void:
	for ctx in contexts: ctx.systems.clear()
	contexts.clear()
func after_all() -> void:
	remove_test_tree(DIR)
func remove_test_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path): return
	for folder in DirAccess.get_directories_at(path): remove_test_tree(path.path_join(folder))
	for name in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)
func start(month: int = 0) -> SimContext:
	var ctx := TourismFixture.host_with_store(0)
	contexts.append(ctx)
	ctx.clock.day=month*25+16
	ctx.city.day=ctx.clock.day
	return ctx
func advance_host(ctx: SimContext, month: int) -> void:
	ctx.clock.day=month*25+16
	ctx.city.day=ctx.clock.day
	ctx.system(&"tourism").monthly(ctx)
	ctx.system(&"budget").monthly(ctx)
func snapshot(ctx: SimContext) -> Dictionary:
	return {"clock_day":ctx.clock.day,"stats":ctx.stats.to_dict(),"rng_seed":str(ctx.rng.seed_value()),"rng_state":str(ctx.rng.state()),"systems":{"tourism":ctx.system(&"tourism").save(),"budget":ctx.system(&"budget").save()}}

func test_opening_factor_once_month_read_purity_and_closure_history() -> void:
	var ctx := start()
	var tourism := ctx.system(&"tourism") as TourismSystem
	check_eq(tourism.reputation_report().value_milli,60000)
	check_eq(tourism.forecast().reputation.current_factor_milli,100000)
	advance_host(ctx,0)
	var r := tourism.reputation_report()
	check_gt(r.visitor_half_units,0)
	check_gt(r.value_milli,60000)
	check_eq(r.current_factor_milli,100000,"completion does not feed current month's demand")
	check_gt(r.future_factor_milli,100000)
	var saved := snapshot(ctx)
	var rng := ctx.rng.state()
	for i in 8:
		tourism.forecast()
		tourism.report()
		tourism.reputation_text()
		tourism.effects_snapshot()
		tourism.monthly(ctx)
		check_eq(tourism.finish_restore(saved),OK)
	check_eq(snapshot(ctx),saved,"reports/replayed monthly/restore cannot mutate reputation, money, RNG or grace")
	check_eq(ctx.rng.state(),rng)
	TourismFixture.set_served(ctx.city,Vector2i(10,10),false,true)
	tourism.reconcile_now()
	check_eq(ctx.stats.tourists,0)
	check_eq(tourism.save().features.reputation,saved.systems.tourism.features.reputation,"later closure never rewrites completed visits")
	check_eq(tourism.save().activity,saved.systems.tourism.activity)
	check_eq(tourism.save().pending,saved.systems.tourism.pending)
	ctx.clock.day=41
	ctx.city.day=41
	check_eq(tourism.forecast().reputation.current_factor_milli,r.future_factor_milli)
	advance_host(ctx,1)
	check_eq(tourism.reputation_report().value_milli,r.value_milli,"pre-acceptance closure earns no experience")
	check_eq(tourism.reputation_report().experience_milli,-1)
	check_eq(tourism.reputation_report().empty_months,1)

func test_schema_source_weights_malformed_atomic_and_earlier_phase_neutral() -> void:
	var ctx := start()
	advance_host(ctx,0)
	var tourism := ctx.system(&"tourism") as TourismSystem
	var good := snapshot(ctx)
	for mutation: Array in [["month_id",1],["month_id",-1],["quarter_remainder",4],["value_milli",63000.5],["empty_months",true],["experience_milli",-1],["visitor_half_units",999999],["opening_milli",50000],["profile","unknown"],["activation_month",1]]:
		var bad := good.duplicate(true)
		bad.systems.tourism.features.reputation[mutation[0]]=mutation[1]
		check(TourismSaveCodec.problem(bad,ctx.city)!="","shared boundary rejects "+str(mutation))
		check_eq(tourism.finish_restore(bad),ERR_INVALID_DATA)
		check_eq(snapshot(ctx),good,"failed restoration atomic")
	var json: Dictionary=JSON.parse_string(JSON.stringify(good))
	check_eq(tourism.finish_restore(json),OK)
	check_eq(tourism.save(),good.systems.tourism,"validated JSON normalized exactly")
	for missing in [{},{"value_milli":60000,"empty_months":0}]:
		var old := good.duplicate(true)
		old.systems.tourism.features.reputation=missing
		check_eq(tourism.finish_restore(old),OK)
		check_eq(tourism.reputation_report().value_milli,60000)
		check_eq(tourism.save().activity,good.systems.tourism.activity)
		check_eq(tourism.save().features.migration,good.systems.tourism.features.migration)
		var restored := snapshot(ctx)
		tourism.monthly(ctx)
		check_eq(snapshot(ctx),restored,"migration never replays completed month")

func test_native_cloud_year_boundary_continuation_and_fraction() -> void:
	var ctx := start(11)
	var tourism := ctx.system(&"tourism") as TourismSystem
	advance_host(ctx,11)
	var good := snapshot(ctx)
	var path := DIR.path_join("december.sc2d")
	check_eq(SaveFormat.save(path,ctx.city,good),OK)
	var store := CloudSaveStore.new(DIR.path_join("cloud"))
	check_eq(store.open_library("private-reputation-account"),OK)
	var staged := store.stage(store.create_slot(),path)
	check(not staged.is_empty())
	if staged.is_empty(): return
	var loaded := SaveFormat.load(staged.continuation.path)
	check(loaded.ok)
	if not loaded.ok: return
	check_eq(tourism.finish_restore(loaded.snapshot),OK)
	check_eq(tourism.save(),good.systems.tourism)
	check_eq(tourism.reputation_report().current_factor_milli,100000)
	advance_host(ctx,12)
	var expected := tourism.save()
	check_eq(tourism.finish_restore(good),OK)
	ctx.system(&"budget").load(good.systems.budget)
	advance_host(ctx,12)
	check_eq(tourism.save(),expected,"native/cloud replay produces exact next-year continuation")

func test_reputation_graph_units_and_history() -> void:
	check_eq(GraphsWindow.GraphCanvas.value_text(&"tourist_reputation",63120),"63.12")
	check(StatisticsParams.SERIES.has(&"tourist_reputation"))
	var ctx := start()
	advance_host(ctx,0)
	var statistics := preload("res://scripts/sim/statistics_system.gd").new()
	statistics.setup(ctx)
	statistics._sample(ctx)
	check(ctx.stats.history.has(&"tourist_reputation"),"monthly reputation history exists")
	if ctx.stats.history.has(&"tourist_reputation"):
		check_eq(ctx.stats.history[&"tourist_reputation"][-1],ctx.system(&"tourism").save().features.reputation.value_milli)

func test_caps_drop_fractional_overshoot_and_empty_drift_never_crosses_neutral() -> void:
	var state := TourismReputation.initial(0)
	state.value_milli=60000
	var up := TourismReputation.advance(state,{"month_id":0,"value_milli":72003},1)
	check_eq(up.value_milli,63000)
	check_eq(up.quarter_remainder,0,"cap discards excess quarter-milli, not future hidden credit")
	var down := TourismReputation.advance(state,{"month_id":0,"value_milli":27997},1)
	check_eq(down.value_milli,52000)
	check_eq(down.quarter_remainder,0)
	state.value_milli=60500
	for month in 8:
		state=TourismReputation.advance(state,{"month_id":month,"value_milli":100000},0)
		check_eq(state.value_milli,60500 if month<3 else 60000)

func test_real_accepted_utility_displacement_lowers_score_and_preserves_history() -> void:
	var fixture := preload("res://tests/test_tourism_utilities.gd").new()
	var ctx: SimContext=fixture.fixture(&"arcology_last")
	var tourism := ctx.system(&"tourism") as TourismSystem
	var water := ctx.system(&"water") as WaterSystem
	ctx.city.facility(Vector2i(9,10))["output"]=100
	water.reallocate_established(ctx,Rect2i(0,0,128,128))
	fixture.attend(ctx,100)
	ctx.city.facility(Vector2i(9,10))["output"]=33
	ctx.clock.day=16
	ctx.city.day=16
	tourism.monthly(ctx)
	check_eq(tourism.report()[0].guests,20)
	check_eq(tourism.report()[0].resource_departures,30)
	var r := tourism.reputation_report()
	check_eq(r.visitor_half_units,120)
	check(r.experience_milli<=40000,"accepted actual resource loss caps completed experience")
	check(r.value_milli<=55000)
	var accepted := tourism.save()
	TourismFixture.set_served(ctx.city,Vector2i(10,10),false,true)
	tourism.reconcile_now()
	check_eq(tourism.save().features.reputation,accepted.features.reputation)
	check_eq(tourism.save().activity,accepted.activity)
	fixture.after_each()
	fixture.free()

func test_fraction_survives_native_cloud_and_both_reject_bad_source_proofs() -> void:
	var ctx := start()
	advance_host(ctx,0)
	var tourism := ctx.system(&"tourism") as TourismSystem
	var saved := snapshot(ctx)
	var units := int(saved.systems.tourism.features.reputation.visitor_half_units)
	# Independently authored completed experience60001milli has1quarter carry.
	var fractional := TourismReputation.advance(TourismReputation.initial(0),{"month_id":0,"value_milli":60001},units)
	saved.systems.tourism.features.reputation=fractional
	check_eq(tourism.finish_restore(saved),OK)
	var path := DIR.path_join("fraction.sc2d")
	check_eq(SaveFormat.save(path,ctx.city,snapshot(ctx)),OK)
	var store := CloudSaveStore.new(DIR.path_join("fraction-cloud"))
	check_eq(store.open_library("private-reputation-fraction"),OK)
	var staged := store.stage(store.create_slot(),path)
	check(not staged.is_empty())
	if staged.is_empty(): return
	var loaded := SaveFormat.load(staged.continuation.path)
	check(loaded.ok)
	if not loaded.ok: return
	check_eq(tourism.finish_restore(loaded.snapshot),OK)
	check_eq(tourism.save().features.reputation,fractional)
	check_eq(TourismReputation.advance(fractional,{"month_id":1,"value_milli":60003},units).value_milli,60001)
	var original := snapshot(ctx)
	for mutation: Array in [["visitor_half_units",units+1],["empty_months",1.5],["quarter_remainder",false],["month_id",12],["value_milli",-1]]:
		var bad := original.duplicate(true)
		bad.systems.tourism.features.reputation[mutation[0]]=mutation[1]
		var doc := {"format":"sc2d","version":2,"stage":"play","city":SaveFormat.encode_city(ctx.city),"snapshot":bad}
		var bad_path := DIR.path_join("invalid-"+String(mutation[0])+".sc2d")
		check_eq(SaveFormat._write_replacement(bad_path,JSON.stringify(doc).to_utf8_buffer()),OK)
		check(not SaveFormat.load(bad_path).ok,"native rejects malformed reputation proof")
		check(store.stage(store.create_slot(),bad_path).is_empty(),"cloud boundary rejects same malformed payload")
		check_eq(snapshot(ctx),original,"save validation is detached")
	for bad: Dictionary in [{"value_milli":60000,"empty_months":false},{"value_milli":true,"empty_months":0}]:
		check(not TourismReputation.decode(bad,saved.systems.tourism,0).ok,"legacy placeholders still reject booleans")

func test_empty_counter_cannot_predate_feature_and_derived_score_is_bounded() -> void:
	var prior := TourismReputation.initial(0)
	prior.empty_months=100
	var impossible := TourismReputation.advance(prior,{"month_id":0,"value_milli":0},0)
	var block := {"schema":3,"last_month":0,"activity_profile":TourismMarkets.PROFILE,"activity":{"month_id":0,"rows":[]}}
	check(not TourismReputation.decode(impossible,block,0).ok,"empty-month counter cannot claim months before feature activation")
	var ctx := start()
	advance_host(ctx,0)
	var good := snapshot(ctx)
	for value: Variant in [-1,100001,60000.5,true,"60000"]:
		var bad := good.duplicate(true)
		bad.stats.tourist_reputation_milli=value
		check(TourismSaveCodec.problem(bad,ctx.city)!="","derived reputation has explicit0..100000 integral bounds")
	var historical: Dictionary = good.systems.tourism.duplicate(true)
	historical.activity_profile=TourismParams.PREVIOUS_PROFILE
	check(not TourismReputation.decode(historical.features.reputation,historical,0).ok,"earlier business profiles cannot acquire retrospective experience")
	for history: Variant in [[-1],[100001],[60000.5],[true],"60000"]:
		var bad := good.duplicate(true)
		bad.stats.history["tourist_reputation"]=history
		check(TourismSaveCodec.problem(bad,ctx.city)!="","reputation graph samples cannot escape their score units")
	var too_long: Array=[]
	too_long.resize(StatisticsParams.KEEP_MONTHS+1)
	too_long.fill(60000)
	var bad := good.duplicate(true)
	bad.stats.history["tourist_reputation"]=too_long
	check(TourismSaveCodec.problem(bad,ctx.city)!="","new graph history has the ordinary finite retention bound")
