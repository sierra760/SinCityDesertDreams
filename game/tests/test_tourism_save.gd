# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

const DIR := "user://tourism-save-tests"
var contexts: Array[SimContext] = []

func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)

func after_each() -> void:
	for ctx in contexts: ctx.systems.clear()
	contexts.clear()

func after_all() -> void:
	remove_test_tree(DIR)

func start() -> SimContext:
	var city := flat_city()
	TourismFixture.venue(city, &"arcology_boddy", Vector2i(10, 10))
	TourismFixture.set_served(city, Vector2i(10, 10), true, true)
	for x in range(10): city.building.put(x,10,Buildings.ROAD_FIRST)
	var ctx := TourismFixture.context(city)
	contexts.append(ctx)
	var tourism := TourismSystem.new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	check_eq(tourism.finish_restore({}), OK)
	var budget := BudgetSystem.new()
	ctx.systems[&"budget"] = budget
	budget.setup(ctx)
	ctx.stats.population = 123
	ctx.clock.day = 16
	ctx.city.day = 16
	tourism.monthly(ctx)
	return ctx

func snap(ctx: SimContext) -> Dictionary:
	return {"clock_day": ctx.clock.day, "stats": ctx.stats.to_dict(),
		"systems": {"tourism": ctx.system(&"tourism").save(), "budget": ctx.system(&"budget").save()}}

func write_doc(name: String, doc: Dictionary) -> String:
	var path := DIR.path_join(name + ".sc2d")
	check_eq(SaveFormat._write_replacement(path, JSON.stringify(doc).to_utf8_buffer()), OK)
	return path

func canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

func test_legacy_and_current_headers_have_separate_counts() -> void:
	var ctx := start()
	var snapshot := snap(ctx)
	var path := DIR.path_join("header.sc2d")
	check_eq(SaveFormat.save(path, ctx.city, snapshot), OK)
	var first := SaveFormat.read_header(path)
	check_eq(first.get("population"), 123)
	check_eq(first.get("tourists"), ctx.stats.tourists)
	check_eq(first.get("count_schema"), 1)
	check_eq(SaveFormat.read_header(path), first, "cache hit preserves split counts")
	var legacy := {"format": "sc2d", "header": {"population": 999999},
		"snapshot": {"stats": {"population": 123, "arcology_population": 98765}},
		"city": {"facilities": {"10,10": {"key": "arcology_boddy", "residents": 999999},
			"20,20": {"key": "unknown_venue", "residents": 1000}}}}
	path = write_doc("legacy-header", legacy)
	var header := SaveFormat.read_header(path)
	check_eq(header.get("population"), 123, "legacy header cannot preserve inflated population")
	check_eq(header.get("tourists"), TourismParams.guest_capacity(&"arcology_boddy"))
	check_eq(header.get("count_schema"), 1)
	legacy.erase("snapshot")
	path = write_doc("unknown-header", legacy)
	header = SaveFormat.read_header(path)
	check_eq(header.get("population"), 999999)
	check_eq(header.get("count_schema"), 0, "no snapshot means explicitly legacy combined count")
	check_eq(header.get("count_label"), "Legacy population")
	check_eq(header.get("tourists"), -1, "unknown is not invented zero attendance")

func test_malformed_tourism_is_rejected_structurally() -> void:
	var ctx := start()
	var good := snap(ctx)
	check_eq(SaveFormat.validate_snapshot(good), "")
	for value: Variant in [NAN, INF, -1, 0.5, true, "3"]:
		var bad := good.duplicate(true)
		bad.systems.tourism.state.records[0].guests = value
		check_ne(SaveFormat.validate_snapshot(bad), "", "reject guest count %s" % str(value))
	for field in ["schema", "last_month"]:
		var bad := good.duplicate(true)
		bad.systems.tourism[field] = 999
		check_ne(SaveFormat.validate_snapshot(bad), "", "reject " + field)
	var duplicate := good.duplicate(true)
	duplicate.systems.tourism.state.records.append(duplicate.systems.tourism.state.records[0].duplicate(true))
	check_ne(SaveFormat.validate_snapshot(duplicate), "", "duplicate venue identities")
	var missing := good.duplicate(true)
	missing.systems.tourism.pending = {}
	check_ne(SaveFormat.validate_snapshot(missing), "", "completed activity cannot disappear before booking")
	var altered := good.duplicate(true)
	altered.systems.tourism.pending.gaming_cents += 25
	check_ne(SaveFormat.validate_snapshot(altered), "", "pending must match immutable activity")
	var bad_activity := good.duplicate(true)
	bad_activity.systems.tourism.activity.rows[0].guest_half_months = -1
	check_ne(SaveFormat.validate_snapshot(bad_activity), "", "activity count bounds")

func test_financial_fields_are_bounded_integral_and_agree() -> void:
	var ctx := start()
	ctx.system(&"budget").monthly(ctx)
	var good := snap(ctx)
	check_eq(SaveFormat.validate_snapshot(good), "")
	for value: Variant in [-1, 1.5, NAN, INF, 9007199254740992.0]:
		for field in ["carry", "booking"]:
			var bad := good.duplicate(true)
			if field == "carry": bad.systems.budget.carry.taxes_gaming = value
			else: bad.systems.budget.tourism_booking.gaming_units = value
			check_ne(SaveFormat.validate_snapshot(bad), "", field + " rejects " + str(value))
	var mismatch := good.duplicate(true)
	mismatch.systems.budget.tourism_booking.month_id = 1
	check_ne(SaveFormat.validate_snapshot(mismatch), "", "booking identity must agree with guard")
	var missing := good.duplicate(true)
	missing.systems.budget.tourism_booking = {}
	check_ne(SaveFormat.validate_snapshot(missing), "", "booked month must have latest booking")
	ctx.stats.tax_gaming = 20
	ctx.stats.tax_occupancy = 0
	check_eq(SaveFormat.validate_snapshot(snap(ctx)), "", "prospective rates cannot invalidate historical booking")

func test_invalid_tourism_preserves_existing_save_and_rejects_detached_load() -> void:
	var ctx := start()
	var path := DIR.path_join("preserved.sc2d")
	check_eq(SaveFormat.save(path, ctx.city, snap(ctx)), OK)
	var original := FileAccess.get_file_as_bytes(path)
	var bad := snap(ctx)
	bad.systems.tourism.pending = {}
	check_eq(SaveFormat.save(path, ctx.city, bad), ERR_INVALID_DATA)
	check_eq(FileAccess.get_file_as_bytes(path), original)
	var doc: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	doc.snapshot = bad
	var damaged := write_doc("damaged", doc)
	var result := SaveFormat.load(damaged)
	check(not result.ok)
	check_eq(result.city, null)
	check_ne(result.get("detail", ""), "")
	var inconsistent: Dictionary = JSON.parse_string(original.get_string_from_utf8())
	inconsistent.city.day = 42
	check(not SaveFormat.load(write_doc("clock-mismatch", inconsistent)).ok)
	inconsistent = JSON.parse_string(original.get_string_from_utf8())
	inconsistent.snapshot.systems.budget.settled_year = ctx.city.founded_year + 1
	check(not SaveFormat.load(write_doc("future-settlement", inconsistent)).ok)

func test_invalid_direct_restore_leaves_active_simulation_unchanged() -> void:
	var sim := Simulation.new()
	sim.setup(flat_city(), 42)
	var before := canonical(sim.snapshot())
	var before_city := canonical(SaveFormat.encode_city(sim.city))
	var bad := sim.snapshot()
	bad.systems.tourism.schema = 100
	bad.stats.population = 789
	bad.rng_state = "12345"
	check_eq(sim.restore(bad), ERR_INVALID_DATA)
	check_eq(canonical(sim.snapshot()), before)
	check_eq(canonical(SaveFormat.encode_city(sim.city)), before_city)
	sim.free()

func restored_context(path: String) -> SimContext:
	var loaded := SaveFormat.load(path)
	check(loaded.ok, str(loaded.get("detail", "")))
	if not loaded.ok: return null
	var ctx := TourismFixture.context(loaded.city)
	contexts.append(ctx)
	ctx.stats.from_dict(loaded.snapshot.stats)
	ctx.rng = SimRng.from_saved_seed(int(loaded.snapshot.rng_seed))
	ctx.rng.set_state(int(loaded.snapshot.rng_state))
	var tourism := TourismSystem.new()
	var budget := BudgetSystem.new()
	ctx.systems[&"tourism"] = tourism
	ctx.systems[&"budget"] = budget
	tourism.setup(ctx)
	budget.setup(ctx)
	budget.load(loaded.snapshot.systems.budget)
	check_eq(tourism.finish_restore(loaded.snapshot), OK)
	return ctx

func save_context(ctx: SimContext, path: String) -> void:
	var snapshot := snap(ctx)
	snapshot.rng_seed = str(ctx.rng.seed_value())
	snapshot.rng_state = str(ctx.rng.state())
	check_eq(SaveFormat.save(path, ctx.city, snapshot), OK)

func check_contexts(a: SimContext, b: SimContext) -> void:
	check_eq(canonical(snap(a)), canonical(snap(b)), "attendance/activity/pending/carry/ledgers equal")
	check_eq(canonical(a.city.facilities), canonical(b.city.facilities), "facility metadata equal")
	check_eq(a.city.funds, b.city.funds)
	check_eq(a.rng.state(), b.rng.state())

func test_day17_day18_and_year_end_roundtrip_equal_continuous() -> void:
	var a := start()
	var path := DIR.path_join("continuation.sc2d")
	for month in 12:
		a.clock.day = month * 25 + 16
		a.city.day = a.clock.day
		a.system(&"tourism").monthly(a)
		check_gt(a.system(&"tourism").pending_bases().gaming_cents, 0)
		save_context(a, path)
		var b := restored_context(path)
		if b == null: return
		check_contexts(a, b)
		for ctx in [a, b]:
			ctx.clock.day += 1
			ctx.city.day = ctx.clock.day
			ctx.system(&"budget").monthly(ctx)
		check_contexts(a, b)
		save_context(b, path)
		var c := restored_context(path)
		if c == null: return
		check_contexts(a, c)
		var funds := c.city.funds
		var rng := c.rng.state()
		var before := c.system(&"budget").save()
		# An acknowledged pending block may survive a crash between two writes.
		var replay := snap(c)
		replay.systems.tourism.pending = a.system(&"tourism").pending_bases()
		var activity: Dictionary = replay.systems.tourism.activity
		var bases := TourismSystem.validate_activity(activity, month,TourismMarkets.PROFILE)
		replay.systems.tourism.pending = {"month_id": month,"profile":TourismMarkets.PROFILE,"lodging_numerator":bases.lodging_numerator,"gaming_numerator":bases.gaming_numerator, "lodging_cents": bases.lodging_cents, "gaming_cents": bases.gaming_cents}
		check_eq(TourismSaveCodec.problem(replay, c.city), "")
		check_eq(c.system(&"tourism").finish_restore(replay), OK)
		check(c.system(&"tourism").pending_bases().is_empty())
		check_eq(c.system(&"budget").save(), before)
		check_eq(c.city.funds, funds)
		check_eq(c.rng.state(), rng)
	# Year-end callback save and the following review both refer to closing 1900.
	a.clock.day = 299
	a.city.day = 299
	a.system(&"budget").yearly(a)
	var closing := snap(a)
	closing.budget_review_pending = true
	check_eq(TourismSaveCodec.problem(closing, a.city), "")
	save_context(a, path)
	var year_end := restored_context(path)
	if year_end == null: return
	check_contexts(a, year_end)
	for ctx in [a, year_end]:
		ctx.clock.day = 300
		ctx.city.day = 300
		ctx.system(&"budget").yearly(ctx)
	check_contexts(a, year_end)
	save_context(year_end, path)
	var review := restored_context(path)
	if review != null: check_contexts(a, review)

func test_stale_attendance_drops_but_earned_activity_survives_demolition() -> void:
	var ctx := start()
	var before := snap(ctx)
	var row: Dictionary = before.systems.tourism.state.records[0]
	ctx.city.clear_footprint(10, 10)
	check_eq(TourismSaveCodec.problem(before, ctx.city), "", "vanished venue can still owe earned tax")
	var path := DIR.path_join("demolished.sc2d")
	save_context(ctx, path)
	var twin := restored_context(path)
	if twin == null: return
	check(twin.system(&"tourism").report().is_empty())
	check_eq(canonical(twin.system(&"tourism").pending_bases()), canonical(before.systems.tourism.pending))
	twin.system(&"budget").monthly(twin)
	check_gt(int(twin.system(&"budget").save().carry.taxes_gaming), 0)
	# A replacement cannot recover stale attendance or Inspect activity.
	TourismFixture.venue(twin.city, &"arcology_boddy", Vector2i(10, 10))
	TourismFixture.set_served(twin.city, Vector2i(10, 10), true, true)
	twin.system(&"tourism").reconcile_now()
	var replacement: Dictionary = twin.system(&"tourism").venue_report(Vector2i(10, 10))
	check_ne(replacement.instance, int(row.instance))
	check_eq(replacement.guests, 0)
	check_eq(replacement.business_month, -1)

func test_legacy_native_v1_v2_migration_is_idempotent_and_preserves_history() -> void:
	for version in [1, 2]:
		var city := flat_city()
		city.day = 3 * GameClock.DAYS_PER_MONTH + 5
		var anchor := Vector2i(10, 10)
		TourismFixture.venue(city, &"arcology_comstock", anchor)
		for x in range(10): city.building.put(x,10,Buildings.ROAD_FIRST)
		city.add_facility(anchor, {"key": &"arcology_comstock", "residents": 80, "condition": 13, "built_day": -20, "built_year": 1888, "capacity": 12345, "custom": "kept"})
		city.status = 3 # Explicit legacy resort-inflated input, not an earned-history fixture.
		var stats := CityStats.new()
		stats.population = 42
		stats.cohorts[3] = 42
		stats.arcology_population = 80
		stats.history = {&"population": [999, 888]}
		stats.inventions[&"arcology_comstock"] = 1
		stats.rewards_offered[&"mayors_house"] = true
		stats.rewards_offered[&"mayors_residence"] = true
		stats.last_year_ledger = {&"taxes_residential": 123}
		var data := stats.to_dict()
		for field in ["tax_occupancy", "tax_gaming", "tourists"]: data.erase(field)
		var snapshot := {"stats": data, "systems": {"rewards": {"arcologies": {"10,10": {"residents": 80}}}}}
		var doc := {"format": "sc2d", "version": version, "stage": "play", "city": SaveFormat.encode_city(city), "snapshot": snapshot}
		if version == 1: doc.city.layers.building = SaveFormat.encode_bytes(PackedByteArray(Array(city.building.data)))
		var loaded := SaveFormat.load(write_doc("legacy-" + str(version), doc))
		check(loaded.ok, str(loaded.get("detail", "")))
		if not loaded.ok: continue
		var sim := Simulation.new()
		sim.setup(loaded.city, 7, null, loaded.snapshot)
		TourismFixture.set_served(sim.city, anchor, true, true)
		check_eq(sim.restore(loaded.snapshot), OK)
		check_eq(sim.stats.population, 42)
		check_eq(sim.city.status, 0, "legacy resort-inflated class is corrected against permanent residents")
		check_eq(sim.stats.cohorts, stats.cohorts)
		check_eq(sim.stats.tourists, 80)
		check_eq(sim.tourism().save().features.migration.grace_until_month, 4, "oldest native migration grants a full intervening month")
		check_eq(sim.stats.arcology_population, 0)
		check_eq(sim.stats.tax_gaming, 7)
		check_eq(sim.stats.tax_occupancy, 7)
		check_eq(canonical(sim.stats.history), canonical(stats.history))
		check_eq(canonical(sim.stats.last_year_ledger), canonical(stats.last_year_ledger))
		check_eq(canonical(sim.stats.inventions), canonical(stats.inventions))
		check_eq(canonical(sim.stats.rewards_offered), canonical(stats.rewards_offered))
		check(sim.stats.rewards_offered.get(&"mayors_residence",false),"legacy correction retains the earned civic gift")
		check_eq(sim.city.facility(anchor).custom, "kept")
		check_eq(sim.city.facility(anchor).condition, 13)
		check_eq(sim.city.facility(anchor).built_day, -20)
		check_eq(sim.city.facility(anchor).built_year, 1888)
		check_eq(sim.city.facility(anchor).capacity, 12345)
		var first := canonical(sim.tourism().save())
		check_eq(sim.restore(loaded.snapshot), OK)
		check_eq(canonical(sim.tourism().save()), first)
		check(sim.tourism().pending_bases().is_empty(), "migration creates no retroactive business")
		var current := sim.snapshot()
		check_eq(TourismSaveCodec.problem(current, sim.city), "")
		sim.setup(sim.city, 7, null, current)
		TourismFixture.set_served(sim.city, anchor, true, true)
		check_eq(sim.restore(current), OK)
		check_eq(canonical(sim.tourism().save()), first, "repeated setup/restoration retains canonical authority")
		# Resave as schema3, then reload in a later month without renewing grace.
		sim.clock.day = 6 * GameClock.DAYS_PER_MONTH
		sim.city.day = sim.clock.day
		var path := DIR.path_join("legacy-grace-resaved-" + str(version) + ".sc2d")
		check_eq(SaveFormat.save(path, sim.city, sim.snapshot()), OK)
		var resumed := restored_context(path)
		if resumed != null:
			check_eq(resumed.system(&"tourism").save().features.migration.grace_until_month, 4, "schema3 reload cannot renew expired grace")
			check_eq(resumed.stats.tourists, 80)
		sim.free()

func test_sc2_import_starts_empty_and_defaults_to_seven_percent() -> void:
	var tiles := City.WIDTH * City.HEIGHT
	var altitude := PackedByteArray()
	altitude.resize(tiles * 2)
	var terrain := PackedByteArray()
	terrain.resize(tiles)
	var buildings := PackedByteArray()
	buildings.resize(tiles)
	var zones := PackedByteArray()
	zones.resize(tiles)
	var code := Buildings.id_of(&"arcology_comstock")
	var size := Buildings.size(code)
	for dy in size.y:
		for dx in size.x:
			buildings[(10 + dx) * City.HEIGHT + 10 + dy] = code
	zones[10 * City.HEIGHT + 10] = Zones.CORNER_NW
	var imported := Sc2Import.import_chunks({"ALTM": altitude, "XTER": terrain, "XBLD": buildings, "XZON": zones}, "Tourism import")
	check(imported.ok)
	if not imported.ok: return
	var sim := Simulation.new()
	sim.setup(imported.city, 42)
	check_eq(sim.stats.tourists, 0)
	check_eq(sim.stats.tax_occupancy, 7)
	check_eq(sim.stats.tax_gaming, 7)
	check(sim.tourism().pending_bases().is_empty())
	check_eq(sim.tourism().report().size(), 1)
	sim.free()


func test_newly_discovered_venue_metadata_is_stable_across_restore() -> void:
	var ctx := start()
	TourismFixture.venue(ctx.city, &"com_corner_store", Vector2i(20, 20))
	ctx.system(&"tourism").reconcile_now()
	var before := canonical(ctx.city.facilities)
	var path := DIR.path_join("new-lot.sc2d")
	save_context(ctx, path)
	var twin := restored_context(path)
	if twin != null: check_eq(canonical(twin.city.facilities), before)

func test_legacy_header_uses_final_resident_override_without_mutation() -> void:
	var snapshot := {"stats": {"population": 42}, "systems": {"rewards": {"arcologies": {"10,10": {"residents": 37}}}}}
	var facilities := {"10,10": {"key": "arcology_boddy", "residents": 25, "condition": 6}}
	var before := canonical(facilities)
	check_eq(TourismSaveCodec.header_counts(snapshot, facilities).tourists, 37)
	check_eq(canonical(facilities), before)

func test_impossible_calendar_and_orphaned_carry_are_rejected() -> void:
	var ctx := start()
	var good := snap(ctx)
	var early := good.duplicate(true)
	early.clock_day = 15
	check_ne(TourismSaveCodec.problem(early), "", "current-month attendance cannot predate day 17")
	var unearned := good.duplicate(true)
	unearned.systems.budget.carry.taxes_gaming = 3
	check_ne(TourismSaveCodec.problem(unearned), "", "carry cannot precede the first booking")
	ctx.system(&"budget").monthly(ctx)
	good = snap(ctx)
	for value in [1, 2, 4]:
		var bad := good.duplicate(true)
		bad.systems.budget.carry.taxes_gaming = value
		check_ne(TourismSaveCodec.problem(bad,ctx.city), "", "open-year carry covers completed exact units")
	var lost := good.duplicate(true)
	lost.systems.budget.carry.taxes_gaming = 0
	check_ne(TourismSaveCodec.problem(lost, ctx.city), "", "open-year carry cannot omit its latest booking")
	var duplicate := good.duplicate(true)
	duplicate.systems.tourism.activity.rows.append(duplicate.systems.tourism.activity.rows[0].duplicate(true))
	check_ne(TourismSaveCodec.problem(duplicate), "", "duplicate earned identities cannot amplify pending money")
	var stale := good.duplicate(true)
	stale.systems.tourism.state.next_instance = 1
	check_ne(TourismSaveCodec.problem(stale), "", "next identity covers historical activity as well as attendance")

func test_explicit_legacy_facility_metadata_wins_without_changing_canonical_guests() -> void:
	var ctx := start()
	var rewards = preload("res://scripts/sim/reward_system.gd").new()
	rewards.setup(ctx)
	var before: Array = ctx.system(&"tourism").report()
	rewards.load({"arcologies": {"10,10": {"residents": 9999, "built_year": 1890, "capacity": 321, "condition": 8}}})
	check_eq(ctx.city.facility(Vector2i(10, 10)).built_year, 1890)
	check_eq(ctx.city.facility(Vector2i(10, 10)).capacity, 321)
	check_eq(ctx.city.facility(Vector2i(10, 10)).condition, 8)
	check(not ctx.city.facility(Vector2i(10, 10)).has("residents"))
	check_eq(ctx.system(&"tourism").report()[0].guests, before[0].guests)

func test_activity_cannot_reassign_an_existing_instance_to_another_venue() -> void:
	var ctx := start()
	var changed := snap(ctx)
	changed.systems.tourism.activity.rows[0].anchor = [20, 20]
	check_ne(TourismSaveCodec.problem(changed), "", "one lot instance cannot describe different attendance and business venues")

func test_year_end_native_save_restores_after_closing_day_without_rebooking() -> void:
	var sim := Simulation.new()
	sim.setup(flat_city(), 812)
	var path := DIR.path_join("year-end-native.sc2d")
	var captured: Array[Dictionary] = []
	sim.budget_review_due.connect(func(_year: int):
		check_eq(SaveFormat.save(path, sim.city, sim.snapshot()), OK)
		captured.append(sim.snapshot()))
	sim.advance_days(300)
	check_eq(captured.size(), 1)
	check_eq(int(captured[0].clock_day), 299)
	var loaded := SaveFormat.load(path)
	check(loaded.ok, str(loaded.get("detail", "")))
	if not loaded.ok:
		sim.free()
		return
	var twin := Simulation.new()
	twin.setup(loaded.city, -1, null, loaded.snapshot)
	check_eq(twin.restore(loaded.snapshot), OK)
	check_eq(twin.clock.day, 300)
	check_eq(canonical(twin.snapshot()), canonical(sim.snapshot()))
	check_eq(twin.city.funds, sim.city.funds)
	for running in [sim, twin]:
		running.get_system(&"budget").yearly(running._ctx)
		running.finish_budget_review()
		running.advance_days(20)
	check_eq(canonical(twin.snapshot()), canonical(sim.snapshot()))
	check_eq(twin.city.funds, sim.city.funds)
	twin.free()
	sim.free()

func test_editing_header_has_no_active_tourism_economy() -> void:
	var path := DIR.path_join("editing.sc2d")
	check_eq(SaveFormat.save(path, flat_city(), {}, SaveFormat.STAGE_EDITING), OK)
	var header := SaveFormat.read_header(path)
	check_eq(header.count_schema, 1)
	check_eq(header.population, 0)
	check_eq(header.tourists, 0)

func test_fractional_facility_token_is_rejected_before_numeric_normalization() -> void:
	var ctx := start()
	var path := DIR.path_join("token-source.sc2d")
	save_context(ctx, path)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	doc.city.facilities["10,10"].tourism_instance = 1.0000001
	var result := SaveFormat.load(write_doc("fractional-token", doc))
	check(not result.ok, "near-integral facility identity must not be rounded into a valid token")
	check_eq(result.city, null)

func test_live_facility_cannot_reuse_attendance_or_activity_identity() -> void:
	for activity_only in [false, true]:
		for moved in [false, true]:
			var ctx := start()
			var snapshot := snap(ctx)
			if activity_only:
				snapshot.systems.tourism.state.records = []
				snapshot.systems.tourism.features.staffing.rows = [] # Removed live opportunities; earned activity remains.
				snapshot.systems.tourism.features.utilities.rows = [] # Removed live reservations.
			var anchor := Vector2i(20, 20) if moved else Vector2i(10, 10)
			var key := &"arcology_boddy" if moved else &"arcology_woolier"
			var token := int(snapshot.systems.tourism.activity.rows[0].instance)
			ctx.city.clear_footprint(10, 10)
			TourismFixture.venue(ctx.city, key, anchor)
			ctx.city.add_facility(anchor, {"key": key, "tourism_instance": token})
			var label := "%s %s" % ["activity-only" if activity_only else "attendance+activity", "moved" if moved else "retyped"]
			check_eq(TourismSaveCodec.problem(snapshot), "", "snapshot alone remains structurally valid: " + label)
			var before := canonical(SaveFormat.encode_city(ctx.city))
			check_ne(TourismSaveCodec.problem(snapshot, ctx.city), "", "detached identity conflict rejected: " + label)
			check_eq(canonical(SaveFormat.encode_city(ctx.city)), before, "validation is read-only")
			var doc := {"format": SaveFormat.FORMAT, "version": SaveFormat.VERSION,
				"stage": SaveFormat.STAGE_PLAY, "city": SaveFormat.encode_city(ctx.city), "snapshot": snapshot}
			var loaded := SaveFormat.load(write_doc("conflicting-live-token", doc))
			check(not loaded.ok, "native load rejects conflicting live token: " + label)
			check_eq(loaded.city, null)

func test_absent_historical_lot_and_fresh_token_replacement_remain_valid() -> void:
	for activity_only in [false, true]:
		for moved in [false, true]:
			var ctx := start()
			var snapshot := snap(ctx)
			snapshot.rng_seed = str(ctx.rng.seed_value())
			snapshot.rng_state = str(ctx.rng.state())
			if activity_only:
				snapshot.systems.tourism.state.records = []
				snapshot.systems.tourism.features.staffing.rows = [] # Removed live opportunities; earned activity remains.
				snapshot.systems.tourism.features.utilities.rows = [] # Removed live reservations.
			ctx.city.clear_footprint(10, 10)
			check_eq(TourismSaveCodec.problem(snapshot, ctx.city), "", "earned business needs no standing original venue")
			var anchor := Vector2i(20, 20) if moved else Vector2i(10, 10)
			var key := &"arcology_boddy" if moved else &"arcology_woolier"
			TourismFixture.venue(ctx.city, key, anchor)
			var fresh := int(snapshot.systems.tourism.state.next_instance)
			ctx.city.add_facility(anchor, {"key": key, "tourism_instance": fresh})
			snapshot.systems.tourism.state.next_instance = fresh + 1
			check_eq(TourismSaveCodec.problem(snapshot, ctx.city), "", "new token identifies a distinct replacement")
			var path := DIR.path_join("fresh-replacement.sc2d")
			check_eq(SaveFormat.save(path, ctx.city, snapshot), OK)
			var twin := restored_context(path)
			if twin == null: continue
			var report: Dictionary = twin.system(&"tourism").venue_report(anchor)
			check_eq(report.instance, fresh)
			check_eq(report.guests, 0)
			check_eq(report.business_month, -1)
			check_eq(report.guest_half_months, 0)
			check_eq(report.lodging_cents, 0)
			check_eq(report.gaming_cents, 0)
			check_eq(canonical(twin.system(&"tourism").pending_bases()), canonical(snapshot.systems.tourism.pending))
			twin.system(&"budget").monthly(twin)
			check_gt(int(twin.system(&"budget").save().carry.taxes_gaming), 0, "old lot's earned tax remains payable")

func test_current_restore_keeps_population_invalid_status_handling() -> void:
	for invalid in [-1,99]:
		var sim := Simulation.new()
		sim.setup(flat_city(),7)
		var snapshot := sim.snapshot()
		sim.city.status = invalid
		check_eq(sim.restore(snapshot),OK)
		check_eq(sim.city.status,0,"PopulationSystem still normalizes invalid classes")
		sim.free()

func test_legacy_uncounted_residents_still_settle_their_imported_class() -> void:
	var city := flat_city()
	for i in 6: city.stamp_building(10+i*3,10,Buildings.RES_3X3_FIRST,Zones.RES_HIGH)
	city.day = 100
	city.status = 5 # Synthetic old import class, with no saved population census.
	var snapshot := {"clock_day":100,"stats":CityStats.new().to_dict(),"systems":{"population":{}}}
	var doc := {"format":"sc2d","version":2,"stage":"play","city":SaveFormat.encode_city(city),"snapshot":snapshot}
	var loaded := SaveFormat.load(write_doc("uncounted-status",doc))
	check(loaded.ok)
	if not loaded.ok: return
	var sim := Simulation.new()
	sim.setup(loaded.city,7,null,loaded.snapshot)
	check_eq(sim.restore(loaded.snapshot),OK)
	check_eq(sim.stats.population,2160,"PopulationSystem still settles uncounted imported homes")
	check_eq(sim.city.status,1,"uncounted initialization still corrects the imported class")
	sim.free()

func test_previous_capacity_pending_business_normalizes_without_losing_earnings() -> void:
	var ctx := start()
	var old := snap(ctx)
	var block: Dictionary = old.systems.tourism
	block.schema = 1
	block.features.access = {} # This historical fixture predates accepted-arrival ledgers.
	block.features.markets = {}
	block.features.staffing = {} # Historical profile has no accepted staff plan.
	block.features.utilities = {} # Historical profile has no accepted utility reservation.
	block.features.calendar = {} # Historical profile has no accepted event calendar.
	block.features.reputation = {} # Historical activity predates completed experience.
	block.erase("activity_profile")
	for legacy: Dictionary in block.state.records:
		legacy.erase("guest_segments")
		legacy.erase("day_segments")
	for legacy: Dictionary in block.activity.get("rows",[]):
		legacy.erase("guest_half_segments")
		legacy.erase("day_segments")
	for field in ["profile","lodging_numerator","gaming_numerator"]: block.pending.erase(field)
	block.state.schema = 1
	var row: Dictionary = block.state.records[0]
	row.capacity = 500
	row.day_capacity = 22
	row.guests = 450
	row.target_guests = 480
	row.day_visitors = 21
	row.target_day_visitors = 22
	row.arrivals = 200
	row.departures = 90
	block.activity.rows[0].guest_half_months = 850
	block.activity.rows[0].day_visitors = 21
	block.pending.lodging_cents = 42500
	block.pending.gaming_cents = 22300
	var activity := canonical(block.activity)
	var pending := canonical(block.pending)
	check_eq(TourismSaveCodec.problem(old, ctx.city), "")
	check_eq(ctx.system(&"tourism").finish_restore(old), OK)
	var report := ctx.system(&"tourism").call("report") as Array
	check_eq(report[0].capacity, 80, "new canonical guest capacity")
	check_eq(report[0].guests, 80, "validated old attendance is normalized")
	check_eq(report[0].day_visitors, 16)
	check_eq(canonical(ctx.system(&"tourism").save().activity), activity, "completed old business retained exactly")
	check_eq(canonical(ctx.system(&"tourism").pending_bases()), pending)
	var normalized := snap(ctx)
	check_eq(TourismSaveCodec.problem(normalized, ctx.city), "")
	check_eq(ctx.system(&"tourism").finish_restore(normalized), OK)
	check_eq(canonical(snap(ctx)), canonical(normalized), "normalization is idempotent")
	ctx.system(&"budget").monthly(ctx)
	check_gt(int(ctx.system(&"budget").save().tourism_booking.occupancy_units), 0)
	check_eq(TourismSaveCodec.problem(snap(ctx), ctx.city), "")
	var booked: Dictionary = ctx.system(&"budget").save().tourism_booking.duplicate(true)
	var carry: Dictionary = ctx.system(&"budget").save().carry.duplicate(true)
	ctx.system(&"budget").monthly(ctx)
	check_eq(ctx.system(&"budget").save().tourism_booking, booked, "old period never booked twice")
	for tax in ["taxes_occupancy", "taxes_gaming"]:
		check_eq(ctx.system(&"budget").save().carry[tax], carry[tax])

func test_previous_capacity_cannot_authorize_arbitrary_attendance() -> void:
	var ctx := start()
	for capacity in [81, 499, 501, 999999]:
		var bad := snap(ctx)
		bad.systems.tourism.state.records[0].capacity = capacity
		check_ne(TourismSaveCodec.problem(bad, ctx.city), "", "capacity must match an exact supported roster")

const OLD_CAPACITIES := {
	&"arcology_boddy": 500, &"arcology_woolier": 1200, &"arcology_stockgrowers": 3000, &"arcology_fremont": 5000,
	&"arcology_comstock": 55000, &"arcology_junction": 30000, &"arcology_boulder": 45000, &"arcology_orbit": 65000,
	&"arcology_fix": 35000, &"arcology_alibi": 30000, &"arcology_velvet": 30000,
	&"arcology_afterglow": 45000, &"arcology_last": 35000, &"arcology_dust": 40000,
}

func old_roster_snapshot(sim: Simulation, month: int) -> Dictionary:
	var snapshot := sim.snapshot()
	snapshot.clock_day = month * 25 + 16
	var block: Dictionary = snapshot.systems.tourism
	block.schema = 1
	block.features.access = {} # This historical fixture predates accepted-arrival ledgers.
	block.features.markets = {}
	block.features.staffing = {} # Historical profile has no accepted staff plan.
	block.features.utilities = {} # Historical profile has no accepted utility reservation.
	block.features.calendar = {} # Historical profile has no accepted event calendar.
	block.features.reputation = {} # Historical activity predates completed experience.
	block.erase("activity_profile")
	for legacy: Dictionary in block.state.records:
		legacy.erase("guest_segments")
		legacy.erase("day_segments")
	for legacy: Dictionary in block.activity.get("rows",[]):
		legacy.erase("guest_half_segments")
		legacy.erase("day_segments")
	for field in ["profile","lodging_numerator","gaming_numerator"]: block.pending.erase(field)
	block.state.schema = 1
	block.erase("activity_profile")
	block.last_month = month
	block.activity = {"month_id": month, "rows": []}
	block.pending = {"month_id": month, "lodging_cents": 0, "gaming_cents": 0}
	for row: Dictionary in block.state.records:
		var capacity := int(OLD_CAPACITIES[StringName(row.key)])
		var day := clampi(int(sqrt(capacity)), 16, 300)
		row.capacity = capacity
		row.day_capacity = day
		row.guests = capacity - 1
		row.target_guests = capacity
		row.day_visitors = day
		row.target_day_visitors = day
		row.arrivals = capacity / 2
		row.departures = capacity / 2
		row.operating = true
		var half := 2 * capacity - 1
		block.activity.rows.append({"anchor": row.anchor.duplicate(), "key": row.key,
			"code": row.code, "instance": row.instance, "guest_half_months": half, "day_visitors": day})
		block.pending.lodging_cents += half * 50
		block.pending.gaming_cents += half * 25 + day * 50
	return snapshot

func serve_all(sim: Simulation) -> void:
	for row: Dictionary in sim.tourism().report():
		TourismFixture.set_served(sim.city, row.anchor, true, true)

func test_previous_roster_native_and_annual_continuation_preserve_earned_state() -> void:
	for version in [1, 2]:
		for month in [0, 11]:
			var city := flat_city()
			var keys := [&"arcology_comstock", &"arcology_junction", &"arcology_boulder", &"arcology_orbit"] if version == 1 else OLD_CAPACITIES.keys()
			for i in keys.size():
				var at := Vector2i(8 + (i % 7) * 16, 8 + (i / 7) * 16)
				TourismFixture.venue(city, keys[i], at)
				city.stamp_building(at.x - 1, at.y, Buildings.ROAD_FIRST)
			var sim := Simulation.new()
			sim.setup(city, 73)
			sim.clock.day = month * 25 + 16
			sim.city.day = sim.clock.day
			sim.city.status = 3 # Earned current-format class survives a later population decline.
			sim.stats.population = 42
			sim.stats.cohorts[2] = 42
			sim.stats.history = {&"population": PackedInt32Array([12345, 42])}
			sim.stats.rewards_offered[&"mayors_residence"] = true
			sim.stats.inventions[&"arcology_comstock"] = 1
			for at: Vector2i in sim.city.facilities:
				sim.city.facility(at).capacity = 123456
				sim.city.facility(at).custom = {"preserved": [2, 7]}
			serve_all(sim)
			sim.tourism().reconcile_now()
			var old := old_roster_snapshot(sim, month)
			var doc := {"format": "sc2d", "version": version, "stage": "play", "city": SaveFormat.encode_city(sim.city), "snapshot": old}
			if version == 1: doc.city.layers.building = SaveFormat.encode_bytes(PackedByteArray(Array(sim.city.building.data)))
			var path := write_doc("old-roster-%d-%d" % [version, month], doc)
			var loaded := SaveFormat.load(path)
			check(loaded.ok, str(loaded.get("detail", "")))
			if not loaded.ok:
				sim.free()
				continue
			var twin := Simulation.new()
			twin.setup(loaded.city, 73, null, loaded.snapshot)
			serve_all(twin)
			check_eq(twin.restore(loaded.snapshot), OK)
			check_eq(twin.city.status, 3, "current-format earned class retained")
			for field in ["population", "cohorts", "history", "rewards_offered", "inventions", "last_year_ledger"]:
				check_eq(canonical(twin.stats.to_dict()[field]), canonical(old.stats[field]), "retained " + field)
			check_eq(canonical(twin.tourism().save().activity), canonical(old.systems.tourism.activity))
			check_eq(canonical(twin.tourism().pending_bases()), canonical(old.systems.tourism.pending))
			check_eq(canonical(twin.get_system(&"budget").save()), canonical(old.systems.budget))
			for row: Dictionary in twin.tourism().report():
				check_eq(row.guests, TourismParams.guest_capacity(row.key))
				check_eq(row.day_visitors, TourismParams.day_capacity(row.key))
				check_eq(twin.city.facility(row.anchor).capacity, 123456)
				check_eq(canonical(twin.city.facility(row.anchor).custom), canonical({"preserved": [2, 7]}))
			var normalized := twin.snapshot()
			check_eq(twin.restore(normalized), OK)
			check_eq(canonical(twin.snapshot()), canonical(normalized), "normalized reload is idempotent")
			# Old malformed attendance and business reject before replacing any live state.
			for change in [{"guests": NAN}, {"guests": 1.5}, {"capacity": 123456}, {"day_capacity": 999}, {"guests": 999999}]:
				var bad := old.duplicate(true)
				bad.systems.tourism.state.records[0].merge(change, true)
				check_eq(twin.restore(bad), ERR_INVALID_DATA)
				check_eq(canonical(twin.snapshot()), canonical(normalized))
			var bad := old.duplicate(true)
			bad.systems.tourism.activity.rows[0].guest_half_months = 999999
			check_eq(twin.restore(bad), ERR_INVALID_DATA)
			check_eq(canonical(twin.snapshot()), canonical(normalized))
			twin.clock.day += 1
			twin.city.day = twin.clock.day
			twin.get_system(&"budget").monthly(twin._ctx)
			var booking: Dictionary = twin.get_system(&"budget").save().tourism_booking
			check_eq(int(booking.occupancy_units), int(old.systems.tourism.pending.lodging_cents) * 7 * 12 / 100)
			check_eq(int(booking.gaming_units), int(old.systems.tourism.pending.gaming_cents) * 7 * 12 / 100)
			var booked := twin.snapshot()
			check_eq(TourismSaveCodec.problem(booked, twin.city), "")
			check_eq(twin.restore(booked), OK)
			check_eq(canonical(twin.snapshot()), canonical(booked))
			if month == 11:
				twin.clock.day = 299
				twin.city.day = 299
				twin.get_system(&"budget").yearly(twin._ctx)
				var settled := twin.snapshot()
				check_eq(TourismSaveCodec.problem(settled, twin.city), "")
				check_eq(twin.restore(settled), OK)
				check_eq(canonical(twin.snapshot()), canonical(settled), "old financial year settles exactly once")
			# Future completed months return to current bounds, retaining any earned carry.
			twin.clock.day = (month + 1) * 25 + 16
			twin.city.day = twin.clock.day
			twin.tourism().monthly(twin._ctx)
			check_eq(twin.tourism().save().activity_profile, TourismMarkets.PROFILE)
			check(TourismSystem.validate_activity(twin.tourism().save().activity, month + 1,TourismMarkets.PROFILE).ok)
			check_eq(TourismSaveCodec.problem(twin.snapshot(), twin.city), "")
			twin.free()
			sim.free()

func remove_test_tree(path: String) -> void:
	for folder in DirAccess.get_directories_at(path): remove_test_tree(path.path_join(folder))
	for name in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)

func test_safety_remainders_malformed_native_restore_is_atomic() -> void:
	var ctx := start()
	var env := EnvironmentSystem.new()
	env.monthly(ctx)
	var snapshot := snap(ctx)
	check_eq(TourismSaveCodec.problem(snapshot, ctx.city), "")
	for replacement in [null, [null], [{"instance": 1, "micro": -1, "cursor": 0, "opening_micro": 0, "opening_cursor": 0, "month": 0}], [{"instance": 9999, "micro": 0, "cursor": 0, "opening_micro": 0, "opening_cursor": 0, "month": 0}]]:
		var bad := snapshot.duplicate(true)
		bad.systems.tourism.features.safety.remainders = replacement
		check_ne(TourismSaveCodec.problem(bad, ctx.city), "", "detached native validation rejects malformed remainder")
		var before: Dictionary = ctx.system(&"tourism").save()
		check_eq(ctx.system(&"tourism").finish_restore(bad), ERR_INVALID_DATA)
		check_eq(ctx.system(&"tourism").save(), before)

func test_missing_schema3_feature_blocks_have_neutral_defaults() -> void:
	var ctx := start()
	var snapshot := snap(ctx)
	# Phase-1/2/3 schema-3 snapshot: old cost-scaled business with no markets.
	snapshot.systems.tourism.activity_profile = TourismParams.CURRENT_PROFILE
	for row: Dictionary in snapshot.systems.tourism.activity.rows:
		row.erase("guest_half_segments")
		row.erase("day_segments")
	var old_bases := TourismSystem.validate_activity(snapshot.systems.tourism.activity,0,TourismParams.CURRENT_PROFILE)
	snapshot.systems.tourism.pending = {"month_id":0,"lodging_cents":old_bases.lodging_cents,"gaming_cents":old_bases.gaming_cents}
	snapshot.systems.tourism.erase("features")
	# The omitted optional block has no new charges; existing taxes stay exact.
	snapshot.systems.tourism.pending.erase("program_half_cents")
	check_eq(TourismSaveCodec.problem(snapshot, ctx.city), "")
	check_eq(ctx.system(&"tourism").finish_restore(snapshot), OK)
	check_eq(ctx.system(&"tourism").save().features.reputation.value_milli, 60000)
	check_eq(ctx.system(&"tourism").pending_bases().gaming_cents, snapshot.systems.tourism.pending.gaming_cents)

func test_safety_booking_and_expense_carry_reject_forged_values() -> void:
	var ctx := start()
	var t := ctx.system(&"tourism") as TourismSystem
	var b := ctx.system(&"budget") as BudgetSystem
	b.monthly(ctx)
	ctx.stats.ordinances[&"casino_safety"] = true
	ctx.clock.day = GameClock.DAYS_PER_MONTH + 16
	ctx.city.day = ctx.clock.day
	t.monthly(ctx)
	b.monthly(ctx)
	var saved := snap(ctx)
	check_eq(TourismSaveCodec.problem(saved, ctx.city), "")
	for invalid in [-1, 0.5, "100", TourismState.MAX_INSTANCE]:
		var bad := saved.duplicate(true)
		bad.systems.budget["tourism_program_booking"] = {"month_id": 1, "half_cents": invalid}
		check_ne(TourismSaveCodec.problem(bad, ctx.city), "", "saved exact program booking must match completed period")
		bad = saved.duplicate(true)
		bad.systems.budget["tourism_program_carry"] = invalid
		check_ne(TourismSaveCodec.problem(bad, ctx.city), "", "saved program residue uses exact bounded units")
	var bad := saved.duplicate(true)
	bad.systems.budget.carry["ordinance_cost"] = -1
	check_ne(TourismSaveCodec.problem(bad, ctx.city), "", "negative expense residue cannot erase a paid program")

func test_native_mixed_program_expense_residue_continues_after_year_end() -> void:
	var a := TourismFixture.host_with_store(24)
	contexts.append(a)
	a.stats.population = 1000
	var ordinances := OrdinanceSystem.new()
	a.systems[&"ordinances"] = ordinances
	ordinances.setup(a)
	ordinances.set_enabled(&"neighborhood_watch", true)
	ordinances.set_enabled(&"casino_safety", true)
	for month in 2:
		a.clock.day = month * GameClock.DAYS_PER_MONTH + 16
		a.city.day = a.clock.day
		a.system(&"tourism").monthly(a)
		a.system(&"budget").monthly(a)
	var env := EnvironmentSystem.new()
	env.monthly(a)
	var path := DIR.path_join("program-mixed-native.sc2d")
	save_context(a, path)
	var b := restored_context(path)
	if b == null: return
	check_contexts(a, b)
	for ctx in [a, b]:
		ctx.clock.day = GameClock.DAYS_PER_YEAR
		ctx.city.day = ctx.clock.day
		ctx.system(&"budget").yearly(ctx)
	check_contexts(a, b)
	save_context(a, path)
	var resumed := restored_context(path)
	if resumed == null: return
	check_contexts(a, resumed)
	check_eq(int(resumed.system(&"budget").save().tourism_program_carry), 480)
	var resumed_ordinances := OrdinanceSystem.new()
	resumed.systems[&"ordinances"] = resumed_ordinances
	resumed_ordinances.setup(resumed)
	for ctx in [a, resumed]:
		ctx.clock.day = GameClock.DAYS_PER_YEAR + 16
		ctx.city.day = ctx.clock.day
		ctx.system(&"tourism").monthly(ctx)
		ctx.system(&"budget").monthly(ctx)
	check_contexts(a, resumed)
