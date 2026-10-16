# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

var contexts: Array[SimContext] = []

func after_each() -> void:
	for ctx in contexts: ctx.systems.clear()
	contexts.clear()

func start(key: StringName, guests: int, days: int = 0) -> SimContext:
	var city := flat_city(10000)
	TourismFixture.venue(city, key, Vector2i(10, 10))
	TourismFixture.set_served(city, Vector2i(10, 10), true, true)
	for x in range(10): city.building.put(x,10,Buildings.ROAD_FIRST)
	var ctx := TourismFixture.context(city)
	contexts.append(ctx)
	ctx.stats.population = 123
	var t := TourismSystem.new()
	ctx.systems[&"tourism"] = t
	t.setup(ctx)
	check_eq(t.finish_restore({}), OK)
	var state := t.save()
	state.state.records[0].guests = guests
	state.state.records[0].day_visitors = days
	TourismFixture.segment_rows(state.state.records)
	TourismFixture.reservation_rows(state)
	check_eq(t.finish_restore({"systems": {"tourism": state}}), OK)
	var b := BudgetSystem.new()
	ctx.systems[&"budget"] = b
	b.setup(ctx)
	return ctx

func test_equal_visitors_have_declining_tier_pressure() -> void:
	var pressure: Array[float] = []
	for key in [&"arcology_last", &"arcology_alibi", &"arcology_afterglow"]:
		var ctx := start(key, 100)
		pressure.append(float(ctx.system(&"tourism").report()[0].get("crime_source_milli", 0)))
	check_eq(pressure, [1500.0, 1000.0, 650.0], "100 equal guests: tiered source, without old truncation")

func test_store_pressure_reaches_map_over_twelve_months() -> void:
	var ctx := TourismFixture.host_with_store(24)
	var empty := TourismFixture.host_with_store(0)
	contexts.append_array([ctx, empty])
	for c in [ctx.city, empty.city]: c.density.data.fill(120)
	var env := EnvironmentSystem.new()
	var quiet := EnvironmentSystem.new()
	var accumulated := 0
	for month in 12:
		ctx.clock.day = month * GameClock.DAYS_PER_MONTH + 9
		empty.clock.day = ctx.clock.day
		env.monthly(ctx)
		quiet.monthly(empty)
		accumulated += env.crime_total() - quiet.crime_total()
	check_gt(accumulated, 0, "small venue survives monthly and spatial rounding")
	check_eq(ctx.stats.population, 123, "visitors never transfer into residents")

func test_program_period_charge_survives_toggle_and_demolition() -> void:
	var ctx := start(&"com_corner_store", 0, 24)
	var t := ctx.system(&"tourism") as TourismSystem
	var b := ctx.system(&"budget") as BudgetSystem
	ctx.stats.ordinances[&"casino_safety"] = true
	ctx.clock.day = 16
	t.monthly(ctx)
	var count := int(t.report()[0].day_visitors)
	check_gt(count, 0)
	ctx.stats.ordinances[&"casino_safety"] = false
	ctx.city.clear_footprint(10, 10)
	t.reconcile_now()
	b.monthly(ctx)
	check_eq(int(b.save().carry.get("ordinance_cost", 0)), count * 24, "2 cents per visitor in twelfth-cent Budget units")
	var before: Dictionary = b.save().carry
	b.monthly(ctx)
	check_eq(b.save().carry.get("ordinance_cost", 0), before.get("ordinance_cost", 0), "once only")

func test_program_protection_and_cost_use_same_accepted_period() -> void:
	var ctx := start(&"arcology_last", 101)
	var t := ctx.system(&"tourism") as TourismSystem
	ctx.stats.ordinances[&"casino_safety"] = true
	ctx.clock.day = 16
	ctx.city.day = 16
	t.monthly(ctx)
	var row := t.report()[0]
	check_eq(int(row.crime_source_micro) * 100, int(row.crime_raw_micro) * 60)
	check_eq(t.pending_bases().program_half_cents, (int(row.guest_half_months) + 2 * int(row.business_day_visitors)) * 2)
	var before := t.effects_snapshot()
	ctx.stats.ordinances[&"casino_safety"] = false
	check_eq(t.effects_snapshot(), before, "switch cannot retroactively undo a paid/protected period")
	var b := ctx.system(&"budget") as BudgetSystem
	b.monthly(ctx)
	var state := t.save()
	check_eq(t.finish_restore({"systems": {"tourism": JSON.parse_string(JSON.stringify(state)), "budget": b.save()}}), OK)
	check_eq(t.effects_snapshot(), before)

func test_police_suppresses_source_without_negative_crime() -> void:
	var busy := start(&"com_corner_store", 0, 24)
	var empty := start(&"com_corner_store", 0)
	for ctx in [busy, empty]:
		ctx.city.police.data.fill(255)
		var env := EnvironmentSystem.new()
		for month in 12:
			ctx.clock.day = month * GameClock.DAYS_PER_MONTH + 9
			env.monthly(ctx)
			check_eq(env.crime_total(), 0, "ordinary police mitigation remains before final clamp")

func test_nightlife_reaches_only_nearby_residential_land() -> void:
	var ctx := start(&"arcology_last", 500)
	var empty := start(&"arcology_last", 0)
	for c in [ctx.city, empty.city]:
		c.zone.put(14, 10, Zones.RES_LOW)
		c.zone.put(30, 10, Zones.RES_LOW)
		c.zone.put(14, 14, Zones.COM_LOW)
	var busy := EnvironmentSystem.new()
	var quiet := EnvironmentSystem.new()
	busy.monthly(ctx)
	quiet.monthly(empty)
	check_lt(ctx.city.land_value_at(14, 10), empty.city.land_value_at(14, 10), "nearby homes experience nightlife")
	check_eq(ctx.city.land_value_at(30, 10), empty.city.land_value_at(30, 10), "distant homes unaffected")
	check_eq(ctx.city.land_value_at(14, 14), empty.city.land_value_at(14, 14), "commercial land unaffected")
	ctx.city.clear_footprint(10, 10)
	ctx.system(&"tourism").reconcile_now()
	busy.monthly(ctx)
	check_eq(busy._tourism_nightlife.count(0), busy._tourism_nightlife.size(), "removal clears live influence")

func test_fractional_remainders_do_not_transfer_to_replacement() -> void:
	var ctx := start(&"com_corner_store", 0, 24)
	var t := ctx.system(&"tourism") as TourismSystem
	var env := EnvironmentSystem.new()
	env.monthly(ctx)
	var old: int = t.report()[0].instance
	check_gt(t.save().features.safety.remainders.size(), 0)
	ctx.city.clear_footprint(10, 10)
	TourismFixture.venue(ctx.city, &"com_corner_store", Vector2i(10, 10))
	TourismFixture.set_served(ctx.city, Vector2i(10, 10), true, true)
	t.reconcile_now()
	check_ne(t.report()[0].instance, old)
	check_eq(t.save().features.safety.remainders, [])

func test_malformed_feature_state_is_atomic_and_grace_does_not_renew() -> void:
	var ctx := start(&"com_corner_store", 0, 24)
	var t := ctx.system(&"tourism") as TourismSystem
	var legacy := t.save()
	legacy.schema = 2
	legacy.state.schema = 2
	legacy.erase("features")
	check_eq(t.finish_restore({"systems": {"tourism": legacy}}), OK)
	var saved := t.save()
	check_eq(saved.features.migration.grace_until_month, 1)
	ctx.clock.day = 10 * GameClock.DAYS_PER_MONTH
	check_eq(t.finish_restore({"systems": {"tourism": saved}}), OK)
	check_eq(t.save().features.migration.grace_until_month, 1, "saved grace expires absolutely")
	var before := t.save()
	for path in [["safety", "active", 1], ["safety", "cost_half_cents", 1.5], ["migration", "grace_until_month", 12], ["safety", "remainders", [{"instance": 999}]], ["reputation", "value_milli", -1]]:
		var bad := before.duplicate(true)
		bad.features[path[0]][path[1]] = path[2]
		check_eq(t.finish_restore({"systems": {"tourism": bad}}), ERR_INVALID_DATA)
		check_eq(t.save(), before, "failed validation leaves current state intact")

func test_ordinance_visitor_quote_is_not_resident_based() -> void:
	var ctx := start(&"com_corner_store", 0, 24)
	var o := OrdinanceSystem.new()
	ctx.systems[&"ordinances"] = o
	o.setup(ctx)
	o.set_enabled(&"casino_safety", true)
	var estimate := o.estimated_yearly(&"casino_safety")
	check_lt(estimate, 0)
	check_eq(o.yearly_totals().cost, -estimate)
	check_eq(o.yearly_totals(false).cost, 0, "ordinary accrual excludes visitor cost")
	var b := ctx.system(&"budget") as BudgetSystem
	check_eq(b.estimated_ledger().ordinance_cost, -estimate)

func test_small_store_exact_source_and_spatial_carry_survive_reload() -> void:
	var ctx := TourismFixture.host_with_store(24)
	contexts.append(ctx)
	var t := ctx.system(&"tourism") as TourismSystem
	var env := EnvironmentSystem.new()
	var delivered := 0
	for month in 12:
		ctx.clock.day = month * GameClock.DAYS_PER_MONTH + 9
		env.monthly(ctx)
		for units in env._tourism_crime: delivered += units
		var before := t.save()
		var map := env._tourism_crime.duplicate()
		check_eq(t.finish_restore({"systems": {"tourism": JSON.parse_string(JSON.stringify(before))}}), OK)
		env.monthly(ctx)
		check_eq(env._tourism_crime, map, "same-month replay neither loses nor duplicates source")
		check_eq(t.save(), before, "reports and environment replay preserve exact rounding state")
	check_eq(delivered, 8, "24 * .020 * 1.5 * 12 = 8.64 crime units")
	check_eq(t.save().features.safety.remainders[0].micro, 640000)

func test_park_separation_reduces_local_nightlife() -> void:
	var ctx := start(&"arcology_last", 500)
	ctx.city.zone.put(16, 10, Zones.RES_LOW)
	var env := EnvironmentSystem.new()
	env.monthly(ctx)
	var before := int(env._tourism_nightlife[5 * City.HALF + 8])
	check_gt(before, 0)
	ctx.city.stamp_building(15, 10, Buildings.SMALL_PARK)
	env.monthly(ctx)
	check_lt(int(env._tourism_nightlife[5 * City.HALF + 8]), before)

func test_no_venues_leave_environment_unchanged() -> void:
	var plain := TourismFixture.context(flat_city())
	var tourism_city := TourismFixture.context(flat_city())
	contexts.append_array([plain, tourism_city])
	for ctx in [plain, tourism_city]:
		ctx.city.zone.put(20, 20, Zones.RES_LOW)
		ctx.city.density.data.fill(100)
		ctx.city.police.data.fill(60)
	var tourism := TourismSystem.new()
	tourism_city.systems[&"tourism"] = tourism
	tourism.setup(tourism_city)
	check_eq(tourism.finish_restore({}), OK)
	EnvironmentSystem.new().monthly(plain)
	EnvironmentSystem.new().monthly(tourism_city)
	check_eq(tourism_city.city.land_value.data, plain.city.land_value.data)
	check_eq(tourism_city.city.crime.data, plain.city.crime.data)
	check_eq(tourism_city.city.pollution.data, plain.city.pollution.data)
