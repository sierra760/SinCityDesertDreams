# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

var contexts: Array[SimContext] = []

func after_each() -> void:
	for ctx in contexts: ctx.systems.clear()
	contexts.clear()

func test_effects_snapshot_distinguishes_occupied_empty_closed_and_frozen_security() -> void:
	var ctx := TourismFixture.host_with_store(24)
	contexts.append(ctx)
	var tourism := ctx.system(&"tourism") as TourismSystem
	TourismFixture.venue(ctx.city, &"arcology_last", Vector2i(20, 10))
	TourismFixture.set_served(ctx.city, Vector2i(20, 10), true, true)
	ctx.city.stamp_building(19, 10, Buildings.ROAD_FIRST)
	tourism.reconcile_now()
	var initial := tourism.save()
	initial.state.records[1].guests = 17
	TourismFixture.segment_rows(initial.state.records)
	TourismFixture.reservation_rows(initial)
	check_eq(tourism.finish_restore({"systems": {"tourism": initial}}), OK)
	var occupied := tourism.effects_snapshot()
	check_eq(occupied.rows[1].get("guests"), 17, "overnight attendance is an independent snapshot input")
	check_eq(occupied.rows[1].get("day_visitors"), 0)
	check_eq(occupied.get("security_active"), false)
	check_eq(occupied.rows[0].get("guests"), 0)
	check_eq(occupied.rows[0].get("day_visitors"), 24)
	check_eq(occupied.rows[0].get("operating"), true)
	ctx.stats.ordinances[&"casino_safety"] = true
	ctx.clock.day = 16
	tourism.monthly(ctx)
	ctx.stats.ordinances[&"casino_safety"] = false
	check_eq(tourism.effects_snapshot().get("security_active"), true, "accepted period owns activation")
	var state := tourism.save()
	state.state.records[0].day_visitors = 0
	TourismFixture.segment_rows(state.state.records)
	TourismFixture.reservation_rows(state)
	check_eq(tourism.finish_restore({"systems": {"tourism": state}}), OK)
	var empty := tourism.effects_snapshot()
	check_eq(empty.rows[0].get("guests"), 0)
	check_eq(empty.rows[0].get("day_visitors"), 0)
	check_eq(empty.rows[0].get("operating"), true, "empty is still operating")
	check_eq(empty.get("security_active"), true)
	TourismFixture.set_served(ctx.city, Vector2i(10, 10), false, true)
	tourism.reconcile_now()
	var closed := tourism.effects_snapshot()
	check_eq(closed.rows[0].get("guests"), 0)
	check_eq(closed.rows[0].get("day_visitors"), 0)
	check_eq(closed.rows[0].get("operating"), false, "closure is distinguishable from empty")
	check_eq(closed.get("security_active"), true, "live closure cannot rewrite the completed program")

func test_effects_snapshot_nested_mutation_cannot_change_state_or_other_snapshots() -> void:
	var ctx := TourismFixture.host_with_store(24)
	contexts.append(ctx)
	var tourism := ctx.system(&"tourism") as TourismSystem
	var before := tourism.save()
	var original := tourism.effects_snapshot()
	var changed := tourism.effects_snapshot()
	changed.rows[0]["guests"] = 999
	changed.rows[0]["day_visitors"] = 999
	changed.rows[0]["operating"] = false
	changed.rows[0]["anchor"] = Vector2i(99, 99)
	changed.rows[0]["crime_source_micro"] = 0
	changed["security_active"] = true
	changed.rows.append({"instance": 999})
	check_eq(tourism.effects_snapshot(), original)
	check_eq(tourism.save(), before)
	changed.rows.clear()
	check_eq(original.rows.size(), 1, "returned arrays are independent too")

func test_schema3_reserved_feature_names_are_accepted_and_neutral() -> void:
	var ctx := TourismFixture.host_with_store(24)
	contexts.append(ctx)
	var tourism := ctx.system(&"tourism") as TourismSystem
	var state := tourism.save()
	var names: Array = state.features.keys()
	names.sort()
	check_eq(names, ["access", "calendar", "districts", "markets", "migration", "reputation", "safety", "staffing", "utilities"])
	state.features.erase("transport")
	state.features.erase("employment")
	for name in ["access", "staffing"]: state.features[name] = {}
	check_eq(tourism.finish_restore({"systems": {"tourism": state}}), OK, "reserved neutral owner blocks are valid schema3")
	for name in ["districts", "access", "markets"]:
		check_eq(tourism.save().features.get(name), {})
	check_eq(tourism.save().features.calendar,TourismCalendar.initial(0))
	check_eq(tourism.save().features.utilities.activation_month,0)
	check_eq(tourism.save().features.utilities.rows[0].supported_days,24,"utilities now own exact accepted attendance")
	check_eq(tourism.save().features.staffing.rows, [])
	check_eq(tourism.save().features.staffing.initialized_month, 0)

func test_fresh_city_starts_without_legacy_grace() -> void:
	var ctx := TourismFixture.host_with_store(0)
	contexts.append(ctx)
	check_eq(ctx.system(&"tourism").save().features.migration.grace_until_month, -1)
