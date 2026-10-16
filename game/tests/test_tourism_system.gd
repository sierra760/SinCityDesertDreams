# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

const SYSTEM := "res://scripts/sim/tourism_system.gd"
const Rewards := preload("res://scripts/sim/reward_system.gd")
const Disasters := preload("res://scripts/sim/disaster_system.gd")
var contexts: Array[SimContext] = []

func after_each() -> void:
	for ctx in contexts:
		ctx.systems.clear()
	contexts.clear()

func start(city: City) -> SimContext:
	var ctx := TourismFixture.context(city)
	contexts.append(ctx)
	if not ResourceLoader.exists(SYSTEM):
		check(false, "monthly TourismSystem exists")
		return ctx
	var tourism: SimSystem = load(SYSTEM).new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	tourism.call("finish_restore", {})
	return ctx

func served(city: City, key: StringName, a: Vector2i) -> void:
	TourismFixture.venue(city, key, a)
	TourismFixture.set_served(city, a, true, true)
	for x in range(a.x): city.building.put(x,a.y,Buildings.ROAD_FIRST)

func test_day17_runs_once_before_budget() -> void:
	check_eq(Simulation.SCHEDULE.get(17, []), [&"tourism"], "tourism scheduled before day-18 budget")
	var city := flat_city()
	served(city, &"arcology_boddy", Vector2i(10, 10))
	var ctx := start(city)
	var t = ctx.system(&"tourism")
	if t == null: return
	check_eq(ctx.stats.get("tourists"), 0, "setup admits nobody")
	ctx.clock.day = 16
	var rng_before := ctx.rng.state()
	var funds_before := city.funds
	var forecast: Dictionary = t.forecast()
	t.monthly(ctx)
	var row: Dictionary = t.venue_report(Vector2i(10, 10))
	check_eq(row.guests, TourismDemand.turnover(0, forecast.rows[0].target_guests).guests)
	check_eq(row.day_visitors, forecast.rows[0].target_day_visitors)
	check_eq(ctx.stats.get("tourists"), row.guests + row.day_visitors)
	var pending: Dictionary = t.pending_bases()
	check_eq(pending.month_id, 0)
	# Independent sum: budget tier, opening empty, weighted half-guests.
	var weighted_guests := 0
	var weighted_days := 0
	for segment in 4:
		weighted_guests += int(row.guest_segments[segment])*int([85,100,150,110][segment])
		weighted_days += int(row.day_segments[segment])*int([85,100,150,110][segment])
	check_eq(pending.lodging_numerator, weighted_guests*50*100)
	check_eq(pending.lodging_cents, weighted_guests*50/100)
	check_eq(pending.gaming_numerator, (weighted_guests*25+weighted_days*50)*100)
	var saved: Dictionary = t.save()
	t.monthly(ctx)
	check_eq(t.save(), saved, "duplicate monthly call has no effect")
	t.forecast(20, 20)
	t.report()
	check_eq(t.save(), saved, "reads and projections are pure")
	check_eq(ctx.rng.state(), rng_before)
	check_eq(city.funds, funds_before)
	ctx.clock.day += 25
	t.monthly(ctx)
	check_eq(t.pending_bases(), pending, "unbooked activity cannot be overwritten")
	t.acknowledge_booking(99)
	check_eq(t.pending_bases(), pending, "wrong month cannot acknowledge")
	t.acknowledge_booking(0)
	t.monthly(ctx)
	check_eq(t.pending_bases().month_id, 1)

func test_service_access_and_fire_clear_counts_without_admissions() -> void:
	var city := flat_city()
	var a := Vector2i(10, 10)
	var b := Vector2i(30, 30)
	var c := Vector2i(50, 50)
	served(city, &"arcology_boddy", a)
	served(city, &"arcology_woolier", b)
	served(city, &"com_corner_store", c)
	var ctx := start(city)
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN] = 100 # Isolate service closure from labor.
	var t = ctx.system(&"tourism")
	if t == null: return
	ctx.clock.day = 16
	t.monthly(ctx)
	var pending: Dictionary = t.pending_bases()
	check_gt(t.venue_report(a).tourists, 0)
	check_gt(t.venue_report(c).day_visitors, 0)
	check_eq(t.venue_report(c).guests, 0)
	city.set_flag(a.x + 1, a.y + 1, TileFlags.WATERED, false)
	t.daily(ctx)
	check_eq(t.venue_report(a).tourists, 0, "all footprint members need water")
	check(not t.venue_report(a).operating)
	TourismFixture.set_served(city, a, true, true)
	t.reconcile_now()
	check_eq(t.venue_report(a).tourists, 0, "recovery never admits early")
	city.set_flag(b.x + 1, b.y + 1, TileFlags.POWERED, false)
	t.daily(ctx)
	check_eq(t.venue_report(b).tourists, 0, "all footprint members need power")
	for x in range(c.x-3,c.x): city.building.put(x,c.y,0)
	t.networks_changed(ctx, Rect2i(c, Vector2i.ONE))
	check_eq(t.venue_report(c).tourists, 0, "road access loss clears attendance")
	TourismFixture.set_served(city, b, true, true)
	for x in range(c.x): city.building.put(x,c.y,Buildings.ROAD_FIRST)
	t.acknowledge_booking(0)
	ctx.clock.day += 25
	t.monthly(ctx)
	check_gt(t.venue_report(a).tourists, 0, "next month admits again")
	var fire := Disasters.new()
	ctx.systems[&"disasters"] = fire
	fire.setup(ctx)
	fire.load({"fires": {"11,11": 10}})
	t.reconcile_now()
	check_eq(t.venue_report(a).tourists, 0)
	check_eq(t.venue_report(a).reason, "Active fire.")
	check_gt(pending.lodging_cents, 0, "closure keeps completed business")

func test_resort_only_city_never_gains_residents_or_milestones() -> void:
	var city := flat_city()
	served(city, &"arcology_orbit", Vector2i(10, 10))
	var ctx := start(city)
	var t = ctx.system(&"tourism")
	if t == null: return
	var rewards := Rewards.new()
	ctx.systems[&"rewards"] = rewards
	rewards.setup(ctx)
	for month in 24:
		ctx.clock.day = month * 25 + 16
		t.monthly(ctx)
		t.acknowledge_booking(month)
		rewards.monthly(ctx)
		rewards.yearly(ctx)
	check_gt(ctx.stats.get("tourists"), 0)
	check_eq(ctx.stats.total_population(), 0)
	check_eq(ctx.stats.arcology_population, 0)
	check_eq(ctx.stats.rewards_offered, {})
	check_eq(city.status, 0)
	check(not city.facility(Vector2i(10, 10)).has("residents"))

func test_setup_restore_emits_only_normalized_totals() -> void:
	if not ResourceLoader.exists(SYSTEM):
		check(false, "monthly TourismSystem exists")
		return
	var city := flat_city()
	served(city, &"arcology_boddy", Vector2i(10, 10))
	city.restored_layers = {"flags": true, "land_value": true}
	city.facility(Vector2i(10, 10))["residents"] = 25
	city.status = 3
	var restored := CityStats.new()
	restored.population = 42
	restored.arcology_population = 999
	var snapshot := {"stats": restored.to_dict(), "systems": {"rewards": {"arcologies": {"10,10": {"residents": 37}}}}}
	var sim := Simulation.new()
	var people: Array[int] = []
	var tourists: Array[int] = []
	sim.population_changed.connect(func(value: int): people.append(value))
	sim.connect("tourists_changed", func(value: int): tourists.append(value))
	sim.setup(city, 7, restored, snapshot)
	check_eq(people, [], "setup defers observable totals until final restore")
	check_eq(tourists, [])
	TourismFixture.set_served(city, Vector2i(10, 10), true, true)
	sim.restore(snapshot)
	check_eq(people, [42])
	check_eq(tourists, [37], "final legacy system count wins")
	check_eq(sim.stats.arcology_population, 0)
	check_eq(city.status, 0)
	sim.restore(snapshot)
	check_eq(tourists, [37], "repeat migration is idempotent")
	sim.free()

func test_snapshot_continuation_preserves_pending_and_counts() -> void:
	var city := flat_city()
	served(city, &"arcology_boddy", Vector2i(10, 10))
	var ctx := start(city)
	var t = ctx.system(&"tourism")
	if t == null: return
	ctx.clock.day = 16
	t.monthly(ctx)
	var snapshot := {"systems": {"tourism": t.save()}}
	var other := city.duplicate_city()
	other.day = 16
	var twin := start(other)
	var restored = twin.system(&"tourism")
	restored.load(snapshot.systems.tourism)
	check_eq(restored.finish_restore(snapshot), OK)
	check_eq(restored.save(), t.save())
	restored.monthly(twin)
	check_eq(restored.save(), t.save(), "restoring between day 17 and 18 never repeats activity")
	var bad := snapshot.duplicate(true)
	bad.systems.tourism.pending.month_id = 1
	check_eq(restored.finish_restore(bad), ERR_INVALID_DATA)
	check_eq(restored.save(), t.save(), "invalid pending rejected atomically")

func test_completed_activity_survives_closure_acknowledgement_and_replacement() -> void:
	var city := flat_city()
	var a := Vector2i(10, 10)
	served(city, &"arcology_boddy", a)
	var ctx := start(city)
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN] = 100 # Isolate service closure from labor.
	var t = ctx.system(&"tourism")
	if t == null: return
	ctx.clock.day = 16
	t.monthly(ctx)
	var pending: Dictionary = t.pending_bases()
	var report: Dictionary = t.venue_report(a)
	check_eq(report.get("business_month", -1), 0)
	check_eq(report.lodging_cents, pending.lodging_cents, "report uses exact opening/closing half-month activity")
	check_eq(report.gaming_cents, pending.gaming_cents)
	TourismFixture.set_served(city, a, false, true)
	t.reconcile_now()
	check_eq(t.venue_report(a).lodging_cents, pending.lodging_cents, "closed venue retains completed business")
	t.acknowledge_booking(0)
	check_eq(t.venue_report(a).lodging_cents, pending.lodging_cents, "booking retains last activity for Inspect")
	var saved: Dictionary = t.save()
	check(saved.has("activity"), "exact business activity persists independently of current attendance")
	city.clear_footprint(a.x, a.y)
	served(city, &"arcology_boddy", a)
	t.reconcile_now()
	check_eq(t.venue_report(a).guests, 0)
	check_eq(t.venue_report(a).lodging_cents, 0, "replacement cannot inherit another instance's business")
	check_eq(t.save().get("activity"), saved.get("activity"), "replacement preserves immutable completed activity")

func test_natural_day17_execution_and_scalar_publication() -> void:
	var city := flat_city()
	served(city, &"arcology_boddy", Vector2i(10, 10))
	city.day = 16
	city.restored_layers = {"flags": true, "land_value": true}
	var sim := Simulation.new()
	var totals: Array[int] = []
	sim.tourists_changed.connect(func(value: int): totals.append(value))
	sim.setup(city, 7)
	check_eq(totals, [0])
	# Day17 now requires real established source budgets as well as service.
	TourismFixture.established_sources(sim)
	sim.advance_day()
	check_gt(sim.stats.tourists, 0)
	check_eq(sim.tourism().pending_bases().month_id, 0)
	check_eq(totals, [0, sim.stats.tourists])
	var before := sim.tourism().save()
	sim.advance_day()
	check_eq(sim.tourism().save().state, before.state, "day 18 never advances attendance")
	check_eq(sim.tourism().save().activity, before.activity, "booking retains completed business")
	check_eq(sim.tourism().save().last_month, before.last_month)
	city.clear_footprint(6,6)
	sim.networks_changed(Rect2i(6,6,4,4))
	check_eq(sim.stats.tourists, 0, "source removal clears accepted attendance before publishing")
	check_eq(totals.back(), 0)
	sim.free()

func test_equal_total_redistribution_notifies_changed_venues_only() -> void:
	var city := flat_city()
	var a := Vector2i(10, 10)
	var b := Vector2i(30, 30)
	served(city, &"arcology_boddy", a)
	served(city, &"arcology_boddy", b)
	city.add_facility(a, {"key": &"arcology_boddy", "residents": 10})
	city.add_facility(b, {"key": &"arcology_boddy", "residents": 30})
	var ctx := start(city)
	var t = ctx.system(&"tourism")
	if t == null: return
	check(t.has_signal("attendance_changed"), "venue observers receive changes even with unchanged citywide totals")
	if not t.has_signal("attendance_changed"): return
	var changes: Array = []
	var statuses: Array[int] = []
	t.connect("attendance_changed", func(anchors: Array[Vector2i]):
		changes.append(anchors)
		statuses.append(city.status))
	city.status = 3
	var saved: Dictionary = t.save()
	saved.state.records[0].guests = 30
	saved.state.records[1].guests = 10
	TourismFixture.segment_rows(saved.state.records)
	TourismFixture.reservation_rows(saved)
	check_eq(t.finish_restore({"systems": {"tourism": saved}}), OK)
	check_eq(ctx.stats.tourists, 40)
	check_eq(changes, [[a, b]])
	check_eq(statuses, [3], "current tourism restore preserves an earned settlement class")
	t.forecast(20, 20)
	t.report()
	t.reconcile_now()
	check_eq(changes, [[a, b]], "pure reads and unchanged reconcile emit nothing")
	city.clear_footprint(a.x, a.y)
	t.reconcile_now()
	check_eq(changes.back(), [a], "removed venue invalidates its cached hall")

func test_restored_stats_without_system_block_are_normalized() -> void:
	var city := flat_city()
	var a := Vector2i(10, 10)
	served(city, &"arcology_boddy", a)
	city.add_facility(a, {"key": &"arcology_boddy", "residents": 77, "custom": "keep"})
	var stats := CityStats.new()
	stats.population = 120
	stats.arcology_population = 77
	stats.tourists = 999
	var sim := Simulation.new()
	var observed: Array = []
	sim.population_changed.connect(func(value): observed.append([value, sim.stats.tourists, sim.stats.arcology_population]))
	sim.setup(city, 7, stats)
	check_eq(observed, [[120, 0, 0]], "unserved legacy occupants clear before first publication")
	check_eq(city.facility(a).custom, "keep")
	check(city.facility(a).tourism_migrated)
	check(not city.facility(a).has("residents"))
	sim.free()

func test_requested_fire_clears_attendance_immediately_while_paused() -> void:
	var city := flat_city()
	var a := Vector2i(10, 10)
	served(city, &"arcology_boddy", a)
	var sim := Simulation.new()
	sim.setup(city, 7)
	TourismFixture.established_sources(sim)
	sim.clock.day = 16
	sim.tourism().monthly(sim._ctx)
	check_gt(sim.stats.tourists, 0)
	check(sim.request_disaster(&"fire", a), "actual disaster ignition succeeds")
	check_eq(sim.stats.tourists, 0, "paused fire action immediately clears attendance")
	check_eq(sim.tourism().venue_report(a).reason, "Active fire.")
	sim.free()

func test_station_access_boundary_and_current_business_after_booked_restore() -> void:
	var city := flat_city()
	var a := Vector2i(10, 10)
	served(city, &"arcology_boddy", a)
	for x in range(7,10): city.building.put(x,10,0)
	city.stamp_building(7, 10, Buildings.SUBWAY_STATION)
	var ctx := start(city)
	var t = ctx.system(&"tourism")
	if t == null: return
	check(t.venue_report(a).operating, "station at distance three grants access")
	ctx.clock.day = 16
	t.monthly(ctx)
	var before: Dictionary = t.pending_bases()
	var saved: Dictionary = t.save()
	check_eq(t.finish_restore({"systems": {"tourism": saved, "budget": {"tourism_booked_month": 0}}}), OK)
	check_eq(t.pending_bases(), {}, "already-booked period is cleared without credit")
	check_eq(t.venue_report(a).lodging_cents, before.lodging_cents)
	check_eq(ctx.stats.tourist_lodging_cents, before.lodging_cents)
	city.clear_footprint(7, 10)
	city.stamp_building(6, 10, Buildings.SUBWAY_STATION)
	t.reconcile_now()
	check(not t.venue_report(a).operating, "station at distance four cannot serve")
	check_eq(t.venue_report(a).tourists, 0)
	var activity: Dictionary = t.save().activity
	city.clear_footprint(a.x, a.y)
	t.reconcile_now()
	var removed: Dictionary = t.save()
	check_eq(t.finish_restore({"systems": {"tourism": removed, "budget": {"tourism_booked_month": 0}}}), OK)
	check_eq(t.report(), [])
	check_eq(t.save().activity, activity, "activity is valid after its lot disappears")

func test_legacy_tax_defaults_reset_and_history_remains_unchanged() -> void:
	var stats := CityStats.new()
	stats.tax_occupancy = 20
	stats.tax_gaming = 19
	stats.from_dict({"population": 12, "arcology_population": 500,
		"cohorts": [12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"history": {"population": [512, 512]}, "ledger": {"taxes_residential": 123}})
	check_eq(stats.tax_occupancy, 7)
	check_eq(stats.tax_gaming, 7)
	var before := stats.to_dict()
	var city := flat_city()
	var ctx := start(city)
	var t = ctx.system(&"tourism")
	if t == null: return
	ctx.stats = stats
	t.finish_restore({})
	check_eq(stats.total_population(), 12)
	check_eq(stats.arcology_population, 0)
	check_eq(stats.to_dict().cohorts, before.cohorts)
	check_eq(stats.to_dict().history, before.history)
	check_eq(stats.to_dict().ledger, before.ledger)

func test_status_correction_requires_legacy_population_migration() -> void:
	for mode in ["no_legacy_counts", "aggregate_only", "legacy_facility", "already_migrated_facility"]:
		var city := flat_city()
		var at := Vector2i(10,10)
		if mode in ["legacy_facility", "already_migrated_facility"]:
			served(city,&"arcology_boddy",at)
			city.add_facility(at,{"key":&"arcology_boddy","residents":80,
				"tourism_migrated":mode == "already_migrated_facility"})
		city.status = 3 # Unit input: the journey suite proves actually earned history.
		var ctx := TourismFixture.context(city)
		contexts.append(ctx)
		ctx.stats.population = 42
		ctx.stats.arcology_population = 80 if mode == "aggregate_only" else 0
		var t := TourismSystem.new()
		ctx.systems[&"tourism"] = t
		t.setup(ctx)
		check_eq(t.finish_restore({}),OK)
		var needs_migration: bool = mode in ["aggregate_only", "legacy_facility"]
		check_eq(city.status,0 if needs_migration else 3,mode)
		check_eq(ctx.stats.arcology_population,0)
		city.status = 3
		check_eq(t.finish_restore({}),OK)
		check_eq(city.status,3,"completed adoption does not reset an earned class: "+mode)
