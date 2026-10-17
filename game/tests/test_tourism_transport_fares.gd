# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

const DIR := "user://tourist-fare-evidence"

func fare_context() -> SimContext:
	var ctx := TourismFixture.context(flat_city())
	var at := Vector2i(20,20)
	TourismFixture.venue(ctx.city,&"arcology_boddy",at)
	TourismFixture.set_served(ctx.city,at,true,true)
	ctx.city.stamp_building(24,20,Buildings.RAIL_STATION)
	for x in range(26,128): ctx.city.building.put(x,20,Buildings.RAIL_FIRST)
	ctx.stats.population = 10000
	var tourism := TourismSystem.new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	assert(tourism.finish_restore({}) == OK)
	var budget := BudgetSystem.new()
	ctx.systems[&"budget"] = budget
	budget.setup(ctx)
	var transport := TransportSystem.new()
	ctx.systems[&"transport"] = transport
	transport.setup(ctx)
	ctx.clock.day = 16
	ctx.city.day = 16
	tourism.monthly(ctx)
	budget.monthly(ctx) # Genuine accepted business is booked before later trips earn fares.
	return ctx

func snapshot(ctx: SimContext) -> Dictionary:
	return {"clock_day":ctx.clock.day,"stats":ctx.stats.to_dict(),"systems":{
		"tourism":ctx.system(&"tourism").save(),"transport":ctx.system(&"transport").save(),
		"budget":ctx.system(&"budget").save()}}

func remove_tree(path: String) -> void:
	for folder in DirAccess.get_directories_at(path): remove_tree(path.path_join(folder))
	for name in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)

func after_all() -> void:
	remove_tree(DIR)

func test_never_processed_positive_fare_refuses_local_cloud_and_atomic_restore() -> void:
	var ctx := fare_context()
	var tourism: TourismSystem = ctx.system(&"tourism")
	var saved := snapshot(ctx)
	var before := tourism.save().duplicate(true)
	var impossible := TransportSystem.neutral_tourism_transport()
	impossible.pending_fare_riders = 1
	saved.systems.tourism.features.access["transport"] = impossible
	var input := JSON.stringify(saved)
	check(TourismSaveCodec.problem(saved,ctx.city) != "","unearned transit claim must refuse at the detached save boundary")
	check_eq(tourism.finish_restore(saved),ERR_INVALID_DATA)
	check_eq(tourism.save(),before,"malformed transport money cannot replace active state")
	check_eq(JSON.stringify(saved),input,"detached validation cannot mutate its input")
	var refused := DIR.path_join("refused.sc2d")
	check_eq(SaveFormat.save(refused,ctx.city,saved),ERR_INVALID_DATA)
	check(not FileAccess.file_exists(refused),"invalid write is refused before a file exists")
	# Start with a real native document, then emulate malformed incoming bytes.
	var good := DIR.path_join("genuine.sc2d")
	check_eq(SaveFormat.save(good,ctx.city,snapshot(ctx)),OK)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(good))
	doc.snapshot = saved
	var incoming := DIR.path_join("incoming.sc2d")
	check_eq(SaveFormat._write_replacement(incoming,JSON.stringify(doc).to_utf8_buffer()),OK)
	check(not SaveFormat.load(incoming).ok,"local native reader rejects genuine malformed transport payload")
	var store := CloudSaveStore.new(DIR.path_join("invalid-cloud"))
	check_eq(store.open_library("private-fare-account"),OK)
	check(store.stage(store.create_slot(),incoming).is_empty(),"local cloud continuation validation rejects the same bytes")
	ctx.systems.clear()

func test_unclaimed_periods_survive_attendance_and_claimed_local_cloud_continuation() -> void:
	var ctx := fare_context()
	var tourism: TourismSystem = ctx.system(&"tourism")
	var transport: TransportSystem = ctx.system(&"transport")
	ctx.clock.day = 32
	ctx.city.day = 32
	transport.monthly(ctx)
	var first := tourism.transport_state()
	check_gt(first.pending_fare_riders,0,"actual completed rail trips earn the claim")
	check(first.has("fare_evidence"),"completed fares retain bounded period-identified earned/claimed evidence")
	if not first.has("fare_evidence"):
		ctx.systems.clear()
		return
	ctx.clock.day = 41
	ctx.city.day = 41
	tourism.monthly(ctx) # A later attendance period must retain unclaimed earlier rides.
	check_eq(tourism.transport_state().pending_fare_riders,first.pending_fare_riders)
	ctx.clock.day = 57
	ctx.city.day = 57
	transport.monthly(ctx)
	var second := tourism.transport_state()
	check_gt(second.pending_fare_riders,first.pending_fare_riders)
	ctx.clock.day = 82
	ctx.city.day = 82
	transport.monthly(ctx) # No new accepted ledger: a zero-earning pass follows the positive ones.
	check_eq(tourism.transport_state().report.completed,0)
	check_eq(tourism.transport_state().pending_fare_riders,second.pending_fare_riders)
	var saved := snapshot(ctx)
	check_eq(TourismSaveCodec.problem(saved,ctx.city),"")
	for claimed in [false,true]:
		var path := DIR.path_join("claimed.sc2d" if claimed else "unclaimed.sc2d")
		check_eq(SaveFormat.save(path,ctx.city,saved),OK)
		var store := CloudSaveStore.new(DIR.path_join("claimed-cloud" if claimed else "unclaimed-cloud"))
		check_eq(store.open_library("private-fare-account"),OK)
		var staged := store.stage(store.create_slot(),path)
		check(not staged.is_empty())
		var paths := [path]
		if not staged.is_empty(): paths.append(staged.continuation.path)
		for input_path: String in paths:
			var loaded := SaveFormat.load(input_path)
			check(loaded.ok,str(loaded.get("detail","")))
			if not loaded.ok: continue
			var twin := TourismFixture.context(loaded.city)
			twin.clock.day = ctx.clock.day
			twin.stats.from_dict(loaded.snapshot.stats)
			var next := TourismSystem.new()
			twin.systems[&"tourism"] = next
			next.setup(twin)
			check_eq(next.finish_restore(loaded.snapshot),OK)
			var trips := TransportSystem.new()
			twin.systems[&"transport"] = trips
			trips.setup(twin)
			trips.load(loaded.snapshot.systems.transport)
			var budget := BudgetSystem.new()
			twin.systems[&"budget"] = budget
			budget.setup(twin)
			budget.load(loaded.snapshot.systems.budget)
			var before := int(budget.save().carry.get("transit_fares",0))
			budget.monthly(twin)
			var expected := before+(0 if claimed else int(second.pending_fare_riders)*BudgetParams.FARE_CENTS*12)
			check_eq(int(budget.save().carry.get("transit_fares",0)),expected)
			check_eq(next.transport_state().pending_fare_riders,0)
			budget.monthly(twin)
			check_eq(int(budget.save().carry.get("transit_fares",0)),expected,"claimed evidence cannot earn again")
			twin.systems.clear()
		if not claimed:
			ctx.system(&"budget").monthly(ctx)
			saved = snapshot(ctx)
	ctx.systems.clear()

func test_compacted_delayed_claim_roundtrip_and_malformed_period_evidence() -> void:
	var ctx := fare_context()
	var tourism: TourismSystem = ctx.system(&"tourism")
	var transport: TransportSystem = ctx.system(&"transport")
	var budget: BudgetSystem = ctx.system(&"budget")
	ctx.clock.day = 32
	ctx.city.day = 32
	transport.monthly(ctx)
	var real_report := transport.tourism_report()
	var state := tourism.transport_state()
	# Synthetic repeated-period fixture uses an actual completed rail report and
	# the production record helper, isolating journal compaction from routing.
	# It is not a claim that these are additional physical traveler journeys.
	var periods := TransportSystem.TOURIST_FARE_PERIODS+6
	for month in range(2,periods+1):
		if month == GameClock.MONTHS_PER_YEAR:
			ctx.clock.day = GameClock.DAYS_PER_YEAR-1
			ctx.city.day = ctx.clock.day
			budget.yearly(ctx) # Annual settlement does not claim unbooked rides.
		var report := real_report.duplicate(true)
		report.month_id = month
		state.pass_month = month
		state.report = report
		TransportSystem.record_fare_period(state,report)
	ctx.clock.day = periods*GameClock.DAYS_PER_MONTH+7
	ctx.city.day = ctx.clock.day
	tourism.accept_transport(state)
	var expected_riders := int(real_report.modes.rail)*periods
	check_eq(state.pending_fare_riders,expected_riders)
	check_eq(state.fare_evidence.periods.size(),TransportSystem.TOURIST_FARE_PERIODS)
	check_eq(state.fare_evidence.carry.first_month,1)
	check_eq(state.fare_evidence.carry.last_month,6)
	check_eq(state.fare_evidence.carry.modes.rail,int(real_report.modes.rail)*6)
	var saved := snapshot(ctx)
	check_eq(TourismSaveCodec.problem(saved,ctx.city),"","compacted delayed claim remains a coherent detached snapshot")
	var before := tourism.save()
	for kind in ["pending","overlap","reverse","future","claimed","latest","neutral"]:
		var bad := saved.duplicate(true)
		var trips: Dictionary = bad.systems.tourism.features.access.transport
		match kind:
			"pending": trips.pending_fare_riders += 1
			"overlap": trips.fare_evidence.carry.last_month = trips.fare_evidence.periods[0].first_month
			"reverse": trips.fare_evidence.carry.first_month = trips.fare_evidence.carry.last_month+1
			"future": trips.fare_evidence.periods[-1].last_month = periods+1
			"claimed": trips.fare_evidence.carry.claimed = TransportSystem.fare_usages(trips.fare_evidence.carry)+1
			"latest":
				trips.fare_evidence.periods[-1].completed += 1
				trips.fare_evidence.periods[-1].modes.rail += 1
				trips.pending_fare_riders += 1
			"neutral":
				trips.pass_month = -1
				trips.processed_month = -1
				trips.report = TransportSystem.neutral_tourism_report()
		var raw := JSON.stringify(bad)
		check(TourismSaveCodec.problem(bad,ctx.city) != "",kind+" refuses at real save boundary")
		check_eq(tourism.finish_restore(bad),ERR_INVALID_DATA,kind)
		check_eq(tourism.save(),before,"refusal preserves active earned/claimed state")
		check_eq(JSON.stringify(bad),raw,"validation never normalizes into its input")
	var path := DIR.path_join("compacted.sc2d")
	check_eq(SaveFormat.save(path,ctx.city,saved),OK)
	var store := CloudSaveStore.new(DIR.path_join("compacted-cloud"))
	check_eq(store.open_library("private-fare-account"),OK)
	var staged := store.stage(store.create_slot(),path)
	check(not staged.is_empty())
	var paths := [path]
	if not staged.is_empty(): paths.append(staged.continuation.path)
	for source: String in paths:
		var loaded := SaveFormat.load(source)
		check(loaded.ok,str(loaded.get("detail","")))
		if not loaded.ok: continue
		var twin := TourismFixture.context(loaded.city)
		twin.clock.day = ctx.clock.day
		twin.stats.from_dict(loaded.snapshot.stats)
		var next := TourismSystem.new()
		twin.systems[&"tourism"] = next
		next.setup(twin)
		check_eq(next.finish_restore(loaded.snapshot),OK)
		check_eq(next.transport_state().pending_fare_riders,expected_riders)
		var trips := TransportSystem.new()
		twin.systems[&"transport"] = trips
		trips.setup(twin)
		trips.load(loaded.snapshot.systems.transport)
		var book := BudgetSystem.new()
		twin.systems[&"budget"] = book
		book.setup(twin)
		book.load(loaded.snapshot.systems.budget)
		var prior := int(book.save().carry.get("transit_fares",0))
		book.monthly(twin)
		check_eq(int(book.save().carry.get("transit_fares",0)),prior+expected_riders*BudgetParams.FARE_CENTS*12)
		check_eq(next.transport_state().pending_fare_riders,0)
		check_eq(next.claim_transport_riders(),0,"a compacted claim cannot replay")
		check_eq(TourismSaveCodec.problem(snapshot(twin),twin.city),"","claimed compacted continuation stays coherent")
		twin.systems.clear()
	ctx.systems.clear()
