# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

func test_forecasts_publish_finite_segments_and_exact_business() -> void:
	var rows: Array[Dictionary] = [{"anchor":Vector2i(10,10),"key":&"arcology_boddy","operating":true,"guests":0}]
	var forecast := TourismDemand.forecast(rows, {"permanent_population":1000}, 7, 7)
	check(forecast.rows[0].has("guest_segments"), "forecast publishes guest segment counts")
	check(forecast.rows[0].has("day_segments"), "forecast publishes exclusive day segment counts")
	check(forecast.has("lodging_numerator"), "business retains subcent precision")

var contexts: Array[SimContext] = []
const DIR := "user://tourism-market-tests"

func after_each() -> void:
	for ctx in contexts: ctx.systems.clear()
	contexts.clear()

func after_all() -> void:
	remove_test_tree(DIR)

func start() -> SimContext:
	var ctx := TourismFixture.context(flat_city(10000))
	contexts.append(ctx)
	TourismFixture.venue(ctx.city,&"arcology_comstock",Vector2i(10,10))
	TourismFixture.set_served(ctx.city,Vector2i(10,10),true,true)
	for x in 10: ctx.city.building.put(x,10,Buildings.ROAD_FIRST)
	var tourism := TourismSystem.new()
	var budget := BudgetSystem.new()
	ctx.systems[&"tourism"] = tourism
	ctx.systems[&"budget"] = budget
	tourism.setup(ctx)
	budget.setup(ctx)
	check_eq(tourism.finish_restore({}),OK)
	return ctx

func snapshot(ctx: SimContext) -> Dictionary:
	return {"clock_day":ctx.clock.day,"stats":ctx.stats.to_dict(),"rng_seed":str(ctx.rng.seed_value()),"rng_state":str(ctx.rng.state()),"systems":{"tourism":ctx.system(&"tourism").save(),"budget":ctx.system(&"budget").save()}}

## One budget visitor half-month at a standard venue: 55.25c lodging and
## 25.5c gaming, independently authored from 50*1.30*.85 and 25*1.20*.85.
func earned(ctx: SimContext, month: int) -> void:
	ctx.clock.day = month*25+16
	ctx.city.day = ctx.clock.day
	var block: Dictionary = ctx.system(&"tourism").save()
	var row: Dictionary = block.state.records[0]
	block.last_month = month
	block.features.calendar = {} # Authored historical business predates event guards.
	block.features.utilities = {} # Independently authored historical business predates utility reservations.
	block.features.staffing = {} # Independently authored historical business predates staffing allocation.
	block.activity_profile = "segments_20261015"
	block.features.markets = {"profile":"segments_20261015"}
	block.activity = {"month_id":month,"rows":[{"anchor":[10,10],"key":row.key,"code":row.code,"instance":row.instance,"guest_half_months":1,"day_visitors":0,"guest_half_segments":[1,0,0,0],"day_segments":[0,0,0,0]}]}
	block.pending = {"month_id":month,"profile":"segments_20261015","lodging_numerator":552500,"gaming_numerator":255000,"lodging_cents":55,"gaming_cents":25}
	check_eq(ctx.system(&"tourism").finish_restore({"systems":{"tourism":block,"budget":ctx.system(&"budget").save()}}),OK)
	check_eq(TourismSaveCodec.problem(snapshot(ctx),ctx.city),"")

func resume_native(ctx: SimContext, tag: String) -> SimContext:
	var path := DIR.path_join(tag+".sc2d")
	check_eq(SaveFormat.save(path,ctx.city,snapshot(ctx)),OK)
	var local := SaveFormat.load(path)
	check(local.ok)
	if not local.ok: return ctx
	var twin := TourismFixture.context(local.city)
	contexts.append(twin)
	twin.stats.from_dict(local.snapshot.stats)
	twin.rng = SimRng.from_saved_seed(int(local.snapshot.rng_seed))
	twin.rng.set_state(int(local.snapshot.rng_state))
	var tourism := TourismSystem.new()
	var budget := BudgetSystem.new()
	twin.systems[&"tourism"] = tourism
	twin.systems[&"budget"] = budget
	tourism.setup(twin)
	budget.setup(twin)
	budget.load(local.snapshot.systems.budget)
	check_eq(tourism.finish_restore(local.snapshot),OK)
	check_eq(JSON.stringify(snapshot(twin),"",true),JSON.stringify(snapshot(ctx),"",true))
	return twin

func test_independent_fractional_rational_reference_survives_years_and_native() -> void:
	var continuous := start()
	var resumed := start()
	var cumulative_lodging := 0
	var cumulative_gaming := 0
	var booked_lodging := 0
	var booked_gaming := 0
	for month in 37:
		# Legal historical rates deliberately differ from the next prospective rate.
		var rate: int = [0,7,20,7][month%4]
		for ctx in [continuous,resumed]:
			ctx.stats.tax_occupancy = rate
			ctx.stats.tax_gaming = 7
			earned(ctx,month)
		if month in [5,12,23]: resumed = resume_native(resumed,"pending-%d"%month)
		for ctx in [continuous,resumed]:
			ctx.clock.day += 1
			ctx.city.day = ctx.clock.day
			ctx.system(&"budget").monthly(ctx)
			ctx.stats.tax_occupancy = 19
			check_eq(TourismSaveCodec.problem(snapshot(ctx),ctx.city),"")
		cumulative_lodging += 552500*rate*12
		cumulative_gaming += 255000*7*12
		var budget: Dictionary = continuous.system(&"budget").save()
		booked_lodging += int(budget.tourism_booking.occupancy_units)
		booked_gaming += int(budget.tourism_booking.gaming_units)
		check_eq(booked_lodging,cumulative_lodging/1000000,"sum of actual units equals the single rational reference")
		check_eq(booked_gaming,cumulative_gaming/1000000,"gaming units cannot lose whole carry units")
		# Previous years settled whole dollars (1200 twelfth-cents each).
		check_eq(int(budget.tourism_residue.occupancy),cumulative_lodging%1000000)
		check_eq(int(budget.tourism_residue.gaming),cumulative_gaming%1000000)
		check_eq(int(budget.carry.taxes_occupancy)%1200,(cumulative_lodging/1000000)%1200)
		check_eq(int(budget.carry.taxes_gaming)%1200,(cumulative_gaming/1000000)%1200)
		if month%12 == 11:
			for ctx in [continuous,resumed]:
				ctx.clock.day = (month+1)*25-1
				ctx.city.day = ctx.clock.day
				ctx.system(&"budget").yearly(ctx)
				check_eq(TourismSaveCodec.problem(snapshot(ctx),ctx.city),"")
		if month%12 == 11:
			check_eq(continuous.city.funds,10000+cumulative_lodging/1200000000+cumulative_gaming/1200000000-(month+1)/12,"single rational tax reference less one dollar annual road upkeep")
		if month in [5,11,23,35]: resumed = resume_native(resumed,"booked-%d"%month)
		check_eq(JSON.stringify(snapshot(continuous),"",true),JSON.stringify(snapshot(resumed),"",true))
		check_eq(continuous.city.funds,resumed.city.funds)
	print("MARKET_RATIONAL months=37 lodging_exact=",cumulative_lodging," gaming_exact=",cumulative_gaming," denominator=1000000 final=",continuous.system(&"budget").save().tourism_residue)

func test_exact_yields_have_independent_rational_oracles() -> void:
	var standard := TourismMarkets.business([1,0,0,0],[0,0,0,0],[0,0,0,0],&"arcology_comstock")
	check_eq(standard.lodging_numerator,552500)
	check_eq(standard.gaming_numerator,255000)
	var luxury := TourismMarkets.business([0,0,1,0],[0,0,0,0],[0,0,0,0],&"arcology_afterglow")
	check_eq(luxury.lodging_numerator,1350000)
	check_eq(luxury.gaming_numerator,562500)
	var mixed := TourismMarkets.business([1,2,3,4],[4,3,2,1],[2,3,4,5],&"arcology_alibi")
	check_eq(mixed.lodging_numerator,14462500)
	check_eq(mixed.gaming_numerator,16395000)
	for key in RewardParams.ARCOLOGIES:
		check_eq(TourismMarkets.tier(key),["budget","standard","premium"].find(TourismParams.venue_tier(key)),"frozen profile agrees with approved tier roster")

func test_pool_partition_elasticity_and_joint_caps() -> void:
	check_eq(TourismMarkets.partition(101,[45,30,15,10]),[46,30,15,10])
	check_eq(TourismMarkets.partition(101,[55,25,5,15]),[56,25,5,15])
	var rows: Array[Dictionary] = []
	for i in 200:
		rows.append({"anchor":Vector2i(i%128,i/128),"key":&"arcology_afterglow" if i%2 else &"arcology_boddy","operating":true,"appeal":100})
	for rates in [Vector2i(0,0),Vector2i(7,7),Vector2i(20,20)]:
		var result := TourismMarkets.allocate(rows,{"guest_pool":10000,"day_pool":10000},rates.x,rates.y)
		var guest_sums := [0,0,0,0]
		var day_sums := [0,0,0,0]
		for row: Dictionary in result.rows:
			check_between(TourismMarkets.sum_counts(row.target_guest_segments),0,TourismParams.guest_capacity(row.key))
			check_between(TourismMarkets.sum_counts(row.target_day_segments),0,TourismParams.day_capacity(row.key))
			for s in 4:
				guest_sums[s] += int(row.target_guest_segments[s])
				day_sums[s] += int(row.target_day_segments[s])
		for s in 4:
			var guest_pool: int = int([4500,3000,1500,1000][s])*(100-int([5,4,3,3][s])*rates.x)*(100-int([4,3,2,3][s])*rates.y)/10000
			var day_pool: int = int([5500,2500,500,1500][s])*(100-int([4,3,2,3][s])*rates.y)/100
			check_eq(result.guest_pools[s],guest_pool)
			check_eq(result.day_pools[s],day_pool)
			check_between(int(guest_sums[s]),0,guest_pool)
			check_between(int(day_sums[s]),0,day_pool)
	var empty := TourismMarkets.allocate(rows,{"guest_pool":0,"day_pool":0},0,0)
	for row: Dictionary in empty.rows: check_eq(TourismMarkets.sum_counts(row.target_guest_segments)+TourismMarkets.sum_counts(row.target_day_segments),0)
	var budget: Dictionary = TourismMarkets.allocate([rows[0]],{"guest_pool":100000,"day_pool":100000},0,0).rows[0]
	var premium: Dictionary = TourismMarkets.allocate([rows[1]],{"guest_pool":100000,"day_pool":100000},0,0).rows[0]
	check_gt(budget.target_guest_segments[2],0,"budget venues accept weaker luxury demand")
	check_gt(premium.target_guest_segments[0],0,"premium venues accept weaker budget demand")
	check_gt(int(budget.target_guest_segments[0])*5000,int(premium.target_guest_segments[0])*80,"affordable preference per bed")
	check_gt(int(premium.target_guest_segments[2])*80,int(budget.target_guest_segments[2])*5000,"luxury preference per bed")

func test_forged_segments_rates_residue_and_legacy_quantums_reject() -> void:
	var ctx := start()
	earned(ctx,0)
	ctx.system(&"budget").monthly(ctx)
	var good := snapshot(ctx)
	for field in ["occupancy_rate","occupancy_opening_residue","occupancy_closing_residue","occupancy_units"]:
		for value in [-1,0.5,1000000,true,"7"]:
			var bad := good.duplicate(true)
			bad.systems.budget.tourism_booking[field] = value
			check_ne(TourismSaveCodec.problem(bad,ctx.city),"",field+" strict range/type/proof")
	for value in [[],[1,0,0],[0,0,0,0],[1.5,0,0,0],[true,0,0,0]]:
		var bad := good.duplicate(true)
		bad.systems.tourism.activity.rows[0].guest_half_segments = value
		check_ne(TourismSaveCodec.problem(bad,ctx.city),"")
	var wrong := good.duplicate(true)
	wrong.systems.budget.tourism_residue.occupancy += 1
	check_ne(TourismSaveCodec.problem(wrong,ctx.city),"","residue must equal exact proof")
	# Legacy profile still requires six/three-unit quantum; no global relaxation.
	var legacy := good.duplicate(true)
	legacy.systems.tourism.activity_profile = TourismParams.CURRENT_PROFILE
	legacy.systems.tourism.features.markets = {}
	legacy.systems.tourism.activity.rows[0].erase("guest_half_segments")
	legacy.systems.tourism.activity.rows[0].erase("day_segments")
	legacy.systems.budget.tourism_money_profile = ""
	legacy.systems.budget.tourism_residue = {"occupancy":0,"gaming":0}
	legacy.systems.budget.tourism_booking = {"month_id":0,"occupancy_units":42,"gaming_units":21}
	legacy.systems.budget.carry.taxes_occupancy = 42
	legacy.systems.budget.carry.taxes_gaming = 21
	check_eq(TourismSaveCodec.problem(legacy,ctx.city),"")
	for value in [22,23,25]:
		var bad := legacy.duplicate(true)
		bad.systems.budget.carry.taxes_gaming = value
		check_ne(TourismSaveCodec.problem(bad),"","legacy gaming quantum remains three")
	for value in [43,44,45]:
		var bad := legacy.duplicate(true)
		bad.systems.budget.carry.taxes_occupancy = value
		check_ne(TourismSaveCodec.problem(bad),"","legacy lodging quantum remains six")

func remove_test_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path): return
	for folder in DirAccess.get_directories_at(path): remove_test_tree(path.path_join(folder))
	for name in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)


func test_segment_migration_and_saved_booking_are_defensive() -> void:
	var ctx := start()
	var block: Dictionary = ctx.system(&"tourism").save()
	block.features.utilities = {} # Earlier segment migration has no utility reservation.
	block.state.records[0].guests = 101
	block.state.records[0].day_visitors = 11
	block.state.records[0].erase("guest_segments")
	block.state.records[0].erase("day_segments")
	check_eq(ctx.system(&"tourism").finish_restore({"systems":{"tourism":block}}),OK)
	var row: Dictionary = ctx.system(&"tourism").report()[0]
	check_eq(row.guests,101)
	check_eq(row.day_visitors,11)
	check_eq(row.guest_segments,[46,30,15,10])
	check_eq(row.day_segments,[7,3,0,1])
	var before: Dictionary = ctx.system(&"tourism").save()
	check_eq(ctx.system(&"tourism").finish_restore({"systems":{"tourism":before}}),OK)
	check_eq(ctx.system(&"tourism").save(),before)
	for o in [0,7,20]:
		for g in [0,7,20]:
			var forecast: Dictionary = ctx.system(&"tourism").forecast(o,g)
			for value: Dictionary in forecast.rows:
				check_eq(TourismMarkets.sum_counts(value.guest_segments),value.guests)
				check_eq(TourismMarkets.sum_counts(value.day_segments),value.day_visitors)
				check_eq(TourismMarkets.sum_counts(value.projected_guest_segments),value.projected_guests)
				check_eq(TourismMarkets.sum_counts(value.projected_day_segments),value.projected_day_visitors)
	earned(ctx,0)
	ctx.system(&"budget").monthly(ctx)
	var original: Dictionary = ctx.system(&"budget").save()
	var exposed: Dictionary = ctx.system(&"budget").tourism_booking()
	exposed.activity.rows[0].guest_half_segments[0] = 999
	check_eq(ctx.system(&"budget").save(),original)
	exposed = ctx.system(&"budget").save()
	exposed.tourism_booking.activity.rows.clear()
	check_eq(ctx.system(&"budget").save(),original)

func test_segment_change_invalidates_retail_cache_without_new_money() -> void:
	var ctx := start()
	var districts := TourismDistricts.new()
	var rows: Array[Dictionary] = [{"anchor":Vector2i(10,10),"key":&"arcology_comstock","code":251,"instance":1,"guests":10,"day_visitors":0,"guest_segments":[10,0,0,0],"day_segments":[0,0,0,0],"operating":true}]
	districts.refresh(ctx,rows)
	check_eq(districts.report().available_spending_cents,170)
	var funds := ctx.city.funds
	rows[0].guest_segments = [0,0,10,0]
	districts.refresh(ctx,rows)
	check_eq(districts.report().available_spending_cents,300)
	check_eq(ctx.city.funds,funds)


func test_pending_next_period_retains_booking_proof_and_historical_identity() -> void:
	var ctx := start()
	earned(ctx,0)
	ctx.system(&"budget").monthly(ctx)
	var booked: Dictionary = ctx.system(&"budget").tourism_booking()
	earned(ctx,1)
	var good := snapshot(ctx)
	check_eq(good.systems.budget.tourism_booking,booked)
	check_eq(TourismSaveCodec.problem(good,ctx.city),"")
	for field in ["instance","anchor"]:
		var bad := good.duplicate(true)
		bad.systems.budget.tourism_booking.activity.rows[0][field] = 999 if field == "instance" else [20,20]
		check_ne(TourismSaveCodec.problem(bad,ctx.city),"","prior booked activity retains identity proof when next period is pending")
	var before := ctx.system(&"tourism").save()
	var bad := good.duplicate(true)
	bad.systems.tourism.state.records[0].guest_segments = [1,0,0,0]
	check_eq(ctx.system(&"tourism").finish_restore(bad),ERR_INVALID_DATA)
	check_eq(ctx.system(&"tourism").save(),before,"invalid segment restore is atomic")


func test_forecast_reproduces_rounded_mix_without_changing_turnover() -> void:
	var rows: Array[Dictionary] = [{"anchor":Vector2i(10,10),"key":&"arcology_boddy","operating":true,"guests":0,"land_value":160}]
	var predicted := TourismDemand.forecast(rows,{"permanent_population":1000,"neighbor_populations":[100000],"average_land_value":160,"economy_phase":2},7,7)
	check_eq(predicted.forecast_mix_basis,"turnover_projection")
	check(predicted.forecast_mix_exact)
	check(predicted.explanation.contains("integer guest turnover"))
	var row: Dictionary = predicted.rows[0]
	check_eq(row.target_guest_segments,[19,11,2,3])
	var actual := [0,0,0,0]
	for month in 36:
		var change := TourismDemand.turnover(TourismMarkets.sum_counts(actual),row.target_guests)
		actual = TourismMarkets.advance(actual,change.guests,change.departures,change.arrivals,row.target_guest_segments)
	check_eq(actual,[21,12,1,1],"ordinary survivors retain their segment through exact integer turnover")
	check_eq(predicted.lodging_numerator,32450000)
	check_eq(row.projected_guest_segments,[21,12,1,1])
	check_eq(TourismMarkets.business(actual,actual,row.target_day_segments,row.key).lodging_numerator,32450000)
	print("FORECAST_MIX_ROUNDING target=19/11/2/3 actual=21/12/1/1 forecast_lodging=3245c actual_lodging=3245c; exact cached turnover projection")

func test_projection_cache_is_bounded_and_warm_reads_do_no_turnover_work() -> void:
	TourismMarkets.clear_projection_cache()
	var inputs: Array = []
	for i in 1000:
		var total := (i*73)%5001
		var target := (i*31+7)%5001
		var opening := TourismMarkets.partition(total,[10+i%17,15,30,45])
		var targets := TourismMarkets.partition(target,[45,30,15,10+i%13])
		var projected := target-1 if target>0 and target%2==0 and total<target else target
		inputs.append([opening,targets,projected])
	var before := inputs.duplicate(true)
	var started := Time.get_ticks_usec()
	var expected: Array = []
	for item: Array in inputs:
		var result := TourismMarkets.project(item[0],item[1],item[2])
		check(result.exact,"bounded supported-capacity projection closes")
		check_eq(TourismMarkets.sum_counts(result.segments),item[2])
		expected.append(result)
	var cold_us := Time.get_ticks_usec()-started
	var cold := TourismMarkets.projection_work()
	started = Time.get_ticks_usec()
	for i in inputs.size(): check_eq(TourismMarkets.project(inputs[i][0],inputs[i][1],inputs[i][2]),expected[i])
	var warm_us := Time.get_ticks_usec()-started
	var warm := TourismMarkets.projection_work()
	check_eq(warm.steps,cold.steps,"cache hits execute zero recurrence steps")
	check_eq(warm.misses,cold.misses)
	check_eq(warm.hits-cold.hits,1000)
	check_between(int(warm.entries),0,TourismMarkets.PROJECTION_CACHE_LIMIT)
	check_between(int(warm.steps),0,1000*TourismMarkets.PROJECTION_STEP_LIMIT)
	for i in 16384: check_eq(TourismMarkets.project([0,0,0,0],[0,0,0,0],0).segments,[0,0,0,0])
	check_eq(TourismMarkets.projection_work(),warm,"maximum zero-bed city does no projection work or allocation")
	check_eq(inputs,before,"pure input arrays retain bytes")
	print("MARKET_PROJECTION cold1000_us=",cold_us," warm1000_us=",warm_us," work=",warm)

func test_restricted_gateway_projection_preserves_supported_survivor_scalar() -> void:
	TourismMarkets.clear_projection_cache()
	var current := [900,600,300,200]
	var target := [900,600,300,200]
	var result := TourismMarkets.project(current,target,1100,100)
	var next := TourismMarkets.advance(current,1100,1000,100,target)
	check(result.exact)
	check_eq(result.basis,"supported_turnover_step")
	check_eq(result.segments,next)
	check_eq(TourismMarkets.sum_counts(result.segments),1100)
