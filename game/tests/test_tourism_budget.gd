# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

var contexts: Array[SimContext] = []

func after_each() -> void:
	for ctx in contexts:
		ctx.systems.clear()
	contexts.clear()

## Fremont supports the hand-calculated fixture's 20 day visitors under current bounds.
func start(key: StringName = &"arcology_fremont") -> SimContext:
	var city := flat_city(10000)
	var a := Vector2i(10, 10)
	TourismFixture.venue(city, key, a)
	TourismFixture.set_served(city, a, true, true)
	city.stamp_building(a.x - 1, a.y, Buildings.ROAD_FIRST)
	var ctx := TourismFixture.context(city)
	contexts.append(ctx)
	var tourism := TourismSystem.new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	check_eq(tourism.finish_restore({}), OK)
	var budget := BudgetSystem.new()
	ctx.systems[&"budget"] = budget
	budget.setup(ctx)
	return ctx

func budget(ctx: SimContext) -> BudgetSystem:
	return ctx.system(&"budget") as BudgetSystem

func tourism(ctx: SimContext) -> TourismSystem:
	return ctx.system(&"tourism") as TourismSystem

## Valid completed business via the public restore boundary; never a projection.
func earned(ctx: SimContext, month: int, half_guests: int, day_visitors: int) -> void:
	ctx.clock.day = month * GameClock.DAYS_PER_MONTH + 17
	ctx.city.day = ctx.clock.day
	var t := tourism(ctx)
	var block := t.save()
	var row := t.report()[0]
	block.last_month = month
	block.activity = {"month_id": month, "rows": [{"anchor": [10, 10],
		"key": String(row.key), "code": row.code, "instance": row.instance,
		"guest_half_months": half_guests, "day_visitors": day_visitors}]}
	block.pending = {"month_id": month, "lodging_cents": half_guests * 50,
		"gaming_cents": half_guests * 25 + day_visitors * 50}
	check_eq(t.finish_restore({"systems": {"tourism": block, "budget": budget(ctx).save()}}), OK)

func test_fractional_tax_accumulates_without_lot_rounding() -> void:
	var ctx := start()
	ctx.stats.tax_occupancy = 0
	var b := budget(ctx)
	for month in 12:
		earned(ctx, month, 1, 0)
		b.monthly(ctx)
		check_eq(int(b.save().carry.get("taxes_gaming", 0)), (month + 1) * 21)
	check_eq(ctx.stats.ledger.get(&"taxes_gaming", -1), 0)
	var original := b.save()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(original))
	b.load(saved)
	check_eq(b.save(), original, "fractional carry and latest booking survive JSON")
	check_eq(int(b.save().carry.get("taxes_gaming", 0)), 252)
	if not b.has_method("tourism_booking"):
		check(false, "Budget exposes saved actual booking")
		return
	check_eq(b.call("tourism_booking"), {"month_id": 11, "occupancy_units": 0, "gaming_units": 21})
	var copy: Dictionary = b.call("tourism_booking")
	copy.gaming_units = 999
	check_eq(b.call("tourism_booking").gaming_units, 21, "getter returns a copy")

func test_nonzero_settlement_matches_hand_calculation() -> void:
	var ctx := start()
	var b := budget(ctx)
	for month in 12:
		earned(ctx, month, 100, 20)
		b.monthly(ctx)
	# Lodging 5000 cents and gaming 3500 cents per month, both at 7%.
	check_eq(ctx.stats.ledger.get(&"taxes_occupancy", -1), 42)
	check_eq(ctx.stats.ledger.get(&"taxes_gaming", -1), 29)
	ctx.clock.day = GameClock.DAYS_PER_YEAR
	ctx.city.day = ctx.clock.day
	var before := ctx.city.funds
	b.yearly(ctx)
	check_eq(ctx.city.funds - before, 71, "business revenue itself never enters treasury")
	check_eq(int(b.save().carry.get("taxes_gaming", 0)), 480)
	check_eq(ctx.stats.ledger.get(&"taxes_gaming", -1), 0)

func test_store_only_has_gaming_tax_and_commercial_property_tax() -> void:
	var ctx := start(&"com_corner_store")
	var t := tourism(ctx)
	var b := budget(ctx)
	ctx.clock.day = 16
	t.monthly(ctx)
	check_eq(t.pending_bases().lodging_cents, 0)
	check_gt(t.pending_bases().gaming_cents, 0)
	b.monthly(ctx)
	check_eq(int(b.save().carry.get("taxes_occupancy", -1)), 0)
	check_gt(int(b.save().carry.get("taxes_gaming", 0)), 0)
	check_gt(b.estimated_ledger()[&"taxes_commercial"], 0)
	check_eq(b.estimated_ledger()[&"taxes_residential"], 0)

func test_resorts_have_no_residential_property_tax() -> void:
	var ctx := start()
	for key in RewardParams.ARCOLOGIES:
		var index: int = RewardParams.ARCOLOGIES.keys().find(key)
		TourismFixture.venue(ctx.city, key, Vector2i(20 + index % 5 * 10, 30 + index / 5 * 10))
	var b := budget(ctx)
	check_eq(b.estimated_ledger()[&"taxes_residential"], 0)
	check_eq(b.estimated_ledger()[&"taxes_commercial"], 0)
	b.monthly(ctx)
	check_eq(ctx.stats.ledger[&"taxes_residential"], 0)

func test_demolish_between_day17_and18_keeps_earned_base() -> void:
	var ctx := start()
	var t := tourism(ctx)
	var b := budget(ctx)
	ctx.clock.day = 16
	t.monthly(ctx)
	var pending := t.pending_bases()
	check_gt(pending.gaming_cents, 0)
	ctx.city.clear_footprint(10, 10)
	t.reconcile_now()
	check_eq(t.pending_bases(), pending)
	ctx.clock.day = 17
	b.monthly(ctx)
	check_eq(int(b.save().carry.get("taxes_gaming", 0)), pending.gaming_cents * 7 * 12 / 100)
	check_eq(int(b.save().carry.get("taxes_occupancy", 0)), pending.lodging_cents * 7 * 12 / 100)
	check(t.pending_bases().is_empty())

func test_forecast_does_not_book_or_acknowledge() -> void:
	var ctx := start()
	var t := tourism(ctx)
	var b := budget(ctx)
	ctx.clock.day = 16
	t.monthly(ctx)
	var before_t := t.save()
	var before_b := b.save()
	var funds := ctx.city.funds
	var rng := ctx.rng.state()
	var projection := t.forecast()
	var estimate := b.estimated_ledger()
	check_eq(estimate.get(&"taxes_occupancy", -1), projection.lodging_cents * 7 * 12 / 10000)
	check_eq(estimate.get(&"taxes_gaming", -1), projection.gaming_cents * 7 * 12 / 10000)
	check_eq(b.review_summary().estimated_ledger, estimate)
	check_eq(b.review_summary().estimated_income, b.estimated_income())
	check_eq(b.review_summary().estimated_expenses, b.estimated_expenses())
	check_eq(t.save(), before_t)
	check_eq(b.save(), before_b)
	check_eq(ctx.city.funds, funds)
	check_eq(ctx.rng.state(), rng)

func test_booking_guard_and_changed_rates_are_prospective() -> void:
	var ctx := start()
	var b := budget(ctx)
	earned(ctx, 0, 100, 20)
	b.monthly(ctx)
	var carry: Dictionary = b.save().carry.duplicate()
	ctx.stats.tax_gaming = 20
	ctx.stats.tax_occupancy = 0
	b.monthly(ctx)
	check_eq(b.save().carry.get("taxes_gaming"), carry.get("taxes_gaming"))
	check_eq(b.save().carry.get("taxes_occupancy"), carry.get("taxes_occupancy"))
	# A restored duplicate pending period must be cleared without another credit.
	var saved := b.save()
	b.load(JSON.parse_string(JSON.stringify(saved)))
	earned(ctx, 0, 100, 20)
	b.monthly(ctx)
	check_eq(b.save().carry.get("taxes_gaming"), carry.get("taxes_gaming"))
	check(tourism(ctx).pending_bases().is_empty())
	earned(ctx, 1, 100, 20)
	b.monthly(ctx)
	if not b.has_method("tourism_booking"):
		check(false, "Budget exposes saved actual booking")
		return
	check_eq(b.call("tourism_booking"), {"month_id": 1, "occupancy_units": 0, "gaming_units": 8400})

func test_year_end_and_auto_budget_settle_once() -> void:
	for auto in [false, true]:
		var ctx := start()
		ctx.stats.auto_budget = auto
		ctx.stats.bonds = [{"principal": 1000, "rate": 5, "age": 0}]
		var b := budget(ctx)
		earned(ctx, 0, 100, 20)
		b.monthly(ctx)
		ctx.clock.day = GameClock.DAYS_PER_YEAR
		ctx.city.day = ctx.clock.day
		b.yearly(ctx)
		var funds := ctx.city.funds
		var rng := ctx.rng.state()
		var saved := b.save()
		var previous := ctx.stats.last_year_ledger.duplicate()
		b.review_summary()
		b.yearly(ctx)
		check_eq(ctx.city.funds, funds)
		check_eq(ctx.stats.bonds[0].age, 1)
		check_eq(ctx.rng.state(), rng, "same-year call cannot redraw prime rate")
		check_eq(b.save(), saved)
		check_eq(ctx.stats.last_year_ledger, previous)
		b.load(JSON.parse_string(JSON.stringify(saved)))
		b.yearly(ctx)
		check_eq(ctx.city.funds, funds, "annual-review restore cannot settle again")
		check_eq(ctx.stats.bonds[0].age, 1)
		check_eq(ctx.rng.state(), rng)

func test_fractional_remainder_survives_multiple_years() -> void:
	var ctx := start()
	ctx.stats.tax_occupancy = 0
	var b := budget(ctx)
	for year in 6:
		for month in 12:
			earned(ctx, year * 12 + month, 1, 0)
			b.monthly(ctx)
		ctx.clock.day = (year + 1) * GameClock.DAYS_PER_YEAR
		ctx.city.day = ctx.clock.day
		b.yearly(ctx)
		check_eq(int(b.save().carry.get("taxes_gaming", 0)), ((year + 1) * 252) % 1200)
		check_eq(ctx.stats.ledger.get(&"taxes_gaming", -1), 0)
		b.load(JSON.parse_string(JSON.stringify(b.save())))
	check_eq(ctx.city.funds, 10001, "72 tiny periods eventually settle one dollar")

func test_mayor_play_does_not_change_tourism_base() -> void:
	var ctx := start()
	var casino := CasinoSystem.new()
	ctx.systems[&"casino"] = casino
	casino.setup(ctx)
	ctx.clock.day = 16
	tourism(ctx).monthly(ctx)
	var pending := tourism(ctx).pending_bases()
	var forecast := tourism(ctx).forecast()
	check(casino.commit_round(ctx, &"arcology_boddy", &"blackjack", 10))
	casino.settle_round(ctx, &"arcology_boddy", &"blackjack", 10, 20)
	check_eq(tourism(ctx).pending_bases(), pending)
	check_eq(tourism(ctx).forecast(), forecast)
	budget(ctx).monthly(ctx)
	if not budget(ctx).has_method("tourism_booking"):
		check(false, "Budget exposes saved actual booking")
		return
	check_eq(budget(ctx).call("tourism_booking").gaming_units, pending.gaming_cents * 7 * 12 / 100)

func test_day17_restore_continues_exactly_before_and_after_booking() -> void:
	var ctx := start()
	var b := budget(ctx)
	ctx.clock.day = 16
	ctx.city.day = 16
	tourism(ctx).monthly(ctx)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify({"stats": ctx.stats.to_dict(),
		"systems": {"budget": b.save(), "tourism": tourism(ctx).save()}}))
	var twin := start()
	twin.clock.day = 16
	twin.city.day = 16
	twin.stats.from_dict(snapshot.stats)
	budget(twin).load(snapshot.systems.budget)
	check_eq(tourism(twin).finish_restore(snapshot), OK)
	check_eq(JSON.parse_string(JSON.stringify(tourism(twin).pending_bases())),
		JSON.parse_string(JSON.stringify(tourism(ctx).pending_bases())))
	b.monthly(ctx)
	budget(twin).monthly(twin)
	check_eq(budget(twin).save(), b.save())
	check_eq(JSON.parse_string(JSON.stringify(tourism(twin).save())),
		JSON.parse_string(JSON.stringify(tourism(ctx).save())))
	# Save again after booking: pending stays empty and completed business remains.
	snapshot = JSON.parse_string(JSON.stringify({"systems": {"budget": b.save(), "tourism": tourism(ctx).save()}}))
	budget(twin).load(snapshot.systems.budget)
	check_eq(tourism(twin).finish_restore(snapshot), OK)
	budget(twin).monthly(twin)
	check_eq(budget(twin).save().carry.get("taxes_gaming"), b.save().carry.get("taxes_gaming"))
	check_eq(budget(twin).tourism_booking(), b.tourism_booking())
	check_eq(tourism(twin).venue_report(Vector2i(10, 10)).gaming_cents,
		tourism(ctx).venue_report(Vector2i(10, 10)).gaming_cents)

func test_automatic_budget_uses_the_same_guard_at_actual_year_boundary() -> void:
	var sim := make_simulation(flat_city(10000))
	sim.stats.auto_budget = true
	sim.stats.bonds = [{"principal": 1000, "rate": 0, "age": 0}]
	var b := sim.get_system(&"budget") as BudgetSystem
	var closing_snapshots: Array[Dictionary] = []
	# Main handles this signal for automatic budgets after the annual books close.
	# Backup may save here, before Simulation advances the year-end clock.
	sim.budget_review_due.connect(func(_year: int):
		closing_snapshots.append(sim.snapshot())
		if not b.needs_review(): sim.finish_budget_review())
	var saved := b.save()
	saved.carry = {"taxes_occupancy": 2520, "taxes_gaming": 1260}
	b.load(saved)
	var before := sim.city.funds
	sim.advance_days(GameClock.DAYS_PER_YEAR)
	check(not sim.budget_review_pending, "automatic budget does not pause for review")
	check_eq(sim.city.funds, before + 3)
	check_eq(sim.stats.last_year_ledger.get(&"taxes_occupancy", -1), 2)
	check_eq(sim.stats.last_year_ledger.get(&"taxes_gaming", -1), 1)
	check_eq(int(b.save().carry.get("taxes_occupancy", 0)), 120)
	check_eq(int(b.save().carry.get("taxes_gaming", 0)), 60)
	var rng := sim._ctx.rng.state()
	b.yearly(sim._ctx)
	check_eq(sim.city.funds, before + 3)
	check_eq(sim._ctx.rng.state(), rng)
	check_eq(sim.stats.bonds[0].age, 1)
	closing_snapshots.append(sim.snapshot())
	for snapshot in closing_snapshots:
		check_eq(sim.restore(JSON.parse_string(JSON.stringify(snapshot))), OK)
		check_eq(sim.clock.day, GameClock.DAYS_PER_YEAR, "both backup times resume after completed year")
		var restored_carry: Dictionary = b.save().carry.duplicate()
		var restored_rng := sim._ctx.rng.state()
		b.yearly(sim._ctx)
		check_eq(sim.city.funds, before + 3)
		check_eq(b.save().carry, restored_carry)
		check_eq(sim.stats.bonds[0].age, 1)
		check_eq(sim._ctx.rng.state(), restored_rng)
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()
