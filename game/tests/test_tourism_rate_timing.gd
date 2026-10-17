# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

## Visitor taxes are booked at the rates that shaped the month's demand. A rate
## raised between the day-17 visitor pass and the day-18 booking cannot keep
## the low-rate crowd while collecting the high-rate tax.

func _sim(day_rates: Array) -> Dictionary:
	var loaded := SaveFormat.load("res://assets/cities/Adaven.sc2d")
	check(loaded.ok)
	if not loaded.ok: return {}
	var sim := Simulation.new()
	sim.setup(loaded.city, 31, null, loaded.snapshot)
	check_eq(sim.restore(loaded.snapshot), OK)
	sim.stats.auto_budget = false
	var booking := {}
	var pending := {}
	# Run through the next complete visitor pass and its booking.
	for i in GameClock.DAYS_PER_MONTH * 2:
		var dom := sim.clock.day_of_month()
		var rate: int = day_rates[0] if dom < 18 else day_rates[1]
		sim.stats.tax_occupancy = rate
		sim.stats.tax_gaming = rate
		if sim.budget_review_pending: sim.finish_budget_review()
		sim.advance_day()
		if pending.is_empty(): pending = sim.tourism().pending_bases()
		var booked: Dictionary = (sim.get_system(&"budget") as BudgetSystem).tourism_booking()
		if not pending.is_empty() and int(booked.get("month_id", -1)) == int(pending.month_id):
			booking = booked
			break
	sim.free()
	return {"booking": booking, "pending": pending}

func test_raising_rates_after_the_visitor_pass_does_not_raise_its_tax() -> void:
	var timed := _sim([0, 20])
	var steady := _sim([20, 20])
	if timed.is_empty() or steady.is_empty(): return
	check(not timed.booking.is_empty(), "a visitor month is booked")
	check_gt(int(timed.pending.get("gaming_cents", 0)), 0, "the fixture city has gaming business")
	check_eq(int(timed.pending.get("occupancy_rate", -1)), 0, "pending business records its demand rate")
	check_eq(int(timed.pending.get("gaming_rate", -1)), 0)
	check_eq(int(timed.booking.get("occupancy_units", -1)), 0, "low-rate demand books low-rate occupancy tax")
	check_eq(int(timed.booking.get("gaming_units", -1)), 0, "low-rate demand books low-rate gaming tax")
	check_eq(int(steady.pending.get("gaming_rate", -1)), 20)
	check_gt(int(steady.booking.get("gaming_units", 0)), 0, "steady rates still collect their tax")

func test_saved_pending_business_restores_its_demand_rates() -> void:
	var loaded := SaveFormat.load("res://assets/cities/Adaven.sc2d")
	if not loaded.ok: return
	var sim := Simulation.new()
	sim.setup(loaded.city, 31, null, loaded.snapshot)
	check_eq(sim.restore(loaded.snapshot), OK)
	for i in GameClock.DAYS_PER_MONTH * 2:
		if sim.budget_review_pending: sim.finish_budget_review()
		sim.stats.tax_gaming = 3
		sim.advance_day()
		if not sim.tourism().pending_bases().is_empty(): break
	var pending := sim.tourism().pending_bases()
	check_eq(int(pending.get("gaming_rate", -1)), 3)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.snapshot()))
	check_eq(SaveFormat.validate_snapshot(snapshot), "")
	check_eq(TourismSaveCodec.problem(snapshot, sim.city), "")
	var twin := Simulation.new()
	twin.setup(sim.city.duplicate_city(), 31, null, snapshot)
	check_eq(twin.restore(snapshot), OK)
	check_eq(int(twin.tourism().pending_bases().get("gaming_rate", -1)), 3, "the demand rate survives a save")
	var malformed: Dictionary = snapshot.duplicate(true)
	malformed.systems.tourism.pending.gaming_rate = 99
	check_eq(TourismSaveCodec.problem(malformed, sim.city) != "" or twin.restore(malformed) != OK, true, "an impossible rate is rejected")
	twin.free()
	sim.free()
