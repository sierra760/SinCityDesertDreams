# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

const Rotated := preload("res://tests/test_rotated_footprints.gd")
const AT := Vector2i(10, 10)
const KEY := &"arcology_boddy"

func test_all_venues_and_rotated_anchors_count_once() -> void:
	for turn in 4:
		var city := flat_city()
		var keys := RewardParams.ARCOLOGIES.keys()
		keys.append_array([&"com_corner_store", &"com_corner_store", KEY, KEY])
		var expected_capacity := 0
		var expected_day := 0
		for i in keys.size():
			var anchor := Vector2i(5 + (i % 6) * 8, 5 + (i / 6) * 8)
			Rotated.stamp_rotated(city, anchor, Buildings.id_of(keys[i]), Zones.NONE, turn)
			expected_capacity += TourismParams.guest_capacity(keys[i])
			expected_day += TourismParams.day_capacity(keys[i])
		var state := TourismState.new()
		state.reconcile(city)
		var rows := state.records()
		check_eq(rows.size(), keys.size(), "one canonical row per unique lot at rotation %d" % turn)
		var capacity := 0
		var day := 0
		var previous := -1
		var tokens := {}
		for row in rows:
			var index: int = row.anchor.y * City.WIDTH + row.anchor.x
			check_gt(index, previous, "canonical anchor ordering")
			previous = index
			capacity += row.capacity
			day += row.day_capacity
			check(not tokens.has(row.instance), "unique instance")
			tokens[row.instance] = true
		check_eq(capacity, expected_capacity)
		check_eq(day, expected_day)

func test_legacy_adoption_preserves_cohorts_and_metadata() -> void:
	var city := flat_city()
	TourismFixture.venue(city, KEY, AT)
	city.add_facility(AT, {"key": KEY, "residents": 37, "built_day": 44, "built_year": 1973,
		"condition": 27, "name": "Old Boddy", "unrelated": {"value": 9}})
	var ctx := TourismFixture.context(city)
	ctx.stats.population = 456
	ctx.stats.cohorts[0] = 456
	var before_cohorts := ctx.stats.cohorts.duplicate()
	var rng_before := ctx.rng.state()
	var state := TourismState.new()
	state.reconcile(city, true)
	check_eq(state.record_at(AT).get("guests", -1), 37)
	check_eq(ctx.stats.population, 456)
	check_eq(ctx.stats.cohorts, before_cohorts)
	check_eq(ctx.rng.state(), rng_before)
	var facility := city.facility(AT)
	check(not facility.has("residents"), "obsolete count removed after transfer")
	check_eq(facility.get("built_day"), 44)
	check_eq(facility.get("built_year"), 1973)
	check_eq(facility.get("condition"), 27)
	check_eq(facility.get("unrelated"), {"value": 9})
	check_eq(facility.get("name"), "Old Boddy")
	var saved := state.to_dict()
	state.reconcile(city, true)
	check_eq(state.to_dict(), saved, "adoption is idempotent")

func test_imported_empty_and_clamped_legacy_counts() -> void:
	var city := flat_city()
	TourismFixture.venue(city, KEY, AT)
	var state := TourismState.new()
	state.reconcile(city, true)
	check_eq(state.record_at(AT).get("guests", -1), 0)
	check_eq(city.facility(AT).get("built_day", -1), city.day)
	var upper := AT + Vector2i(8, 0)
	TourismFixture.venue(city, KEY, upper)
	city.add_facility(upper, {"key": KEY, "residents": 2147483647})
	var lower := AT + Vector2i(16, 0)
	TourismFixture.venue(city, KEY, lower)
	city.add_facility(lower, {"key": KEY, "residents": -50})
	state.reconcile(city, true)
	check_eq(state.record_at(upper).get("guests", -1), TourismParams.guest_capacity(KEY))
	check_eq(state.record_at(lower).get("guests", -1), 0)

func test_setup_then_final_adoption_transfers_once() -> void:
	var city := flat_city()
	TourismFixture.venue(city, KEY, AT)
	city.add_facility(AT, {"key": KEY, "residents": 37})
	var state := TourismState.new()
	state.reconcile(city)
	check_eq(state.record_at(AT).guests, 0, "setup never admits")
	check_eq(city.facility(AT).residents, 37, "legacy source waits for final restore")
	state.reconcile(city, true)
	check_eq(state.record_at(AT).guests, 37)
	city.facility(AT).residents = 499
	state.reconcile(city, true)
	check_eq(state.record_at(AT).guests, 37, "completed adoption cannot refill")
	check(not city.facility(AT).has("residents"))

func test_same_day_same_code_rebuild_does_not_inherit() -> void:
	var city := flat_city(1000000)
	var builder := Builder.new(city, CityStats.new())
	check(builder.apply(Tools.Kind.ARCOLOGY_BODDY, AT).ok)
	city.facility(AT).residents = 37
	var state := TourismState.new()
	state.reconcile(city, true)
	var old_instance: int = state.record_at(AT).instance
	var old_day: int = city.facility(AT).built_day
	check(builder.apply(Tools.Kind.BULLDOZE, AT + Vector2i.ONE).ok)
	check(city.facility(AT).is_empty(), "Builder removes facility identity")
	check(builder.apply(Tools.Kind.ARCOLOGY_BODDY, AT).ok)
	check_eq(city.facility(AT).built_day, old_day)
	state.reconcile(city, true)
	check_gt(state.record_at(AT).instance, old_instance)
	check_eq(state.record_at(AT).guests, 0, "same-code same-day rebuild starts empty")

func test_missing_or_replaced_lot_drops_row() -> void:
	var city := flat_city()
	TourismFixture.venue(city, KEY, AT)
	city.add_facility(AT, {"key": KEY, "residents": 37})
	var state := TourismState.new()
	state.reconcile(city, true)
	city.clear_footprint(AT.x, AT.y)
	state.reconcile(city)
	check(state.record_at(AT).is_empty())
	TourismFixture.venue(city, &"arcology_woolier", AT)
	state.reconcile(city)
	check_eq(state.record_at(AT).key, &"arcology_woolier")
	check_eq(state.record_at(AT).guests, 0)

func test_getters_cannot_mutate_state() -> void:
	var city := flat_city()
	TourismFixture.venue(city, KEY, AT)
	var state := TourismState.new()
	state.reconcile(city)
	var before := state.to_dict()
	var rows := state.records()
	rows[0].guests = 500
	rows.clear()
	var row := state.record_at(AT)
	row.instance = 99
	var encoded := state.to_dict()
	encoded.records[0].anchor[0] = 99
	encoded.records[0].guests = 50
	check_eq(state.to_dict(), before)

func test_snapshot_roundtrip_and_stale_pruning_are_pure() -> void:
	var city := flat_city()
	TourismFixture.venue(city, KEY, AT)
	city.add_facility(AT, {"key": KEY, "residents": 37})
	var state := TourismState.new()
	state.reconcile(city, true)
	var saved := state.to_dict()
	var facilities := city.facilities.duplicate(true)
	var decoded := TourismState.decode(JSON.parse_string(JSON.stringify(saved)), city, 0)
	check(decoded.ok, "JSON snapshot roundtrip")
	if decoded.ok:
		check_eq(decoded.state.to_dict(), saved)
	check_eq(city.facilities, facilities, "decode never mutates city")
	city.clear_footprint(AT.x, AT.y)
	TourismFixture.venue(city, KEY, AT)
	var replacement := TourismState.new()
	replacement.reconcile(city)
	# Simulate a later authoritative token even when a fresh state allocates one.
	city.facility(AT).tourism_instance = saved.next_instance + 4
	facilities = city.facilities.duplicate(true)
	decoded = TourismState.decode(saved, city, 0)
	check(decoded.ok, "replaced venue row safely pruned")
	if decoded.ok:
		check(decoded.state.records().is_empty())
	check_eq(city.facilities, facilities)

func test_decode_rejects_invalid_blocks_before_installation() -> void:
	var city := flat_city()
	TourismFixture.venue(city, KEY, AT)
	TourismFixture.venue(city, KEY, AT + Vector2i(8, 0))
	var state := TourismState.new()
	state.reconcile(city)
	var saved := state.to_dict()
	var invalid: Array = [null, [], {}, {"schema": 999, "next_instance": 1, "records": []}]
	for field in ["guests", "day_visitors", "target_guests", "target_day_visitors", "arrivals", "departures", "appeal", "code", "instance", "capacity", "day_capacity"]:
		for value in [-1, 0.5, NAN, INF, "3", true]:
			var bad := saved.duplicate(true)
			bad.records[1][field] = value
			invalid.append(bad)
	for change in [
		{"guests": TourismParams.guest_capacity(KEY) + 1},
		{"day_visitors": TourismParams.day_capacity(KEY) + 1},
		{"target_guests": TourismParams.guest_capacity(KEY) + 1},
		{"appeal": 101}, {"operating": 1}, {"reason": []}, {"key": "unknown"},
		{"anchor": [-1, 0]}, {"anchor": [10.5, 10]}, {"anchor": [10, 10, 1]},
	]:
		var bad := saved.duplicate(true)
		bad.records[1].merge(change, true)
		invalid.append(bad)
	var duplicate_anchor := saved.duplicate(true)
	duplicate_anchor.records[1].anchor = duplicate_anchor.records[0].anchor.duplicate()
	invalid.append(duplicate_anchor)
	var duplicate_token := saved.duplicate(true)
	duplicate_token.records[1].instance = duplicate_token.records[0].instance
	invalid.append(duplicate_token)
	var noncanonical := saved.duplicate(true)
	noncanonical.records[1].anchor = [AT.x + 1, AT.y + 1]
	invalid.append(noncanonical)
	for value in [0, -1, 0.5, INF, saved.records[1].instance]:
		var bad := saved.duplicate(true)
		bad.next_instance = value
		invalid.append(bad)
	var before := city.facilities.duplicate(true)
	for bad in invalid:
		var result := TourismState.decode(bad, city, 0)
		check(not result.ok, "unsafe block rejected")
		check(result.state == null, "failure never exposes partial state")
		check(not String(result.error).is_empty())
	check_eq(city.facilities, before)
	check_eq(state.to_dict(), saved, "decode cannot partially overwrite existing state")

func test_updates_are_atomic_and_derive_capacities() -> void:
	var city := flat_city()
	TourismFixture.venue(city, KEY, AT)
	var state := TourismState.new()
	state.reconcile(city)
	var rows := state.records()
	rows[0].guests = 40
	rows[0].day_visitors = 10
	rows[0].operating = true
	rows[0].capacity = 999999
	check_eq(state.replace_records(rows), OK)
	check_eq(state.record_at(AT).guests, 40)
	check_eq(state.record_at(AT).capacity, TourismParams.guest_capacity(KEY))
	rows[0].guests = 400
	check_eq(state.record_at(AT).guests, 40, "caller-owned rows cannot mutate installed state")
	var saved := state.to_dict()
	for field in ["instance", "code", "key", "anchor", "guests"]:
		var bad := state.records()
		bad[0][field] = {"instance": 99, "code": Buildings.ARCOLOGY_WOOLIER, "key": &"arcology_woolier",
			"anchor": Vector2i(30, 30), "guests": -1}[field]
		check_ne(state.replace_records(bad), OK)
		check_eq(state.to_dict(), saved)
	check_ne(state.replace_records([]), OK, "update cannot erase identities")
	var duplicates := state.records()
	duplicates.append(duplicates[0].duplicate(true))
	check_ne(state.replace_records(duplicates), OK)
	check_eq(state.to_dict(), saved)
	var encoded := saved.duplicate(true)
	encoded.records[0].capacity = 0
	encoded.records[0].day_capacity = 0
	var decoded := TourismState.decode(encoded, city, 0)
	check(not decoded.ok, "saved capacity must assert an exact supported profile")
	check_eq(decoded.state, null, "invalid capacity exposes no partial state")

func test_stale_invalid_rows_still_reject_entire_block() -> void:
	var city := flat_city()
	TourismFixture.venue(city, KEY, AT)
	var state := TourismState.new()
	state.reconcile(city)
	var encoded := state.to_dict()
	city.clear_footprint(AT.x, AT.y)
	encoded.records[0].guests = NAN
	check(not TourismState.decode(encoded, city, 0).ok, "validate malformed stale data before pruning")

func test_current_snapshot_adoption_does_not_overwrite_authoritative_guests() -> void:
	var city := flat_city()
	TourismFixture.venue(city, KEY, AT)
	city.add_facility(AT, {"key": KEY, "residents": 499})
	var state := TourismState.new()
	state.reconcile(city)
	var saved := state.to_dict()
	saved.records[0].guests = 37
	var decoded := TourismState.decode(saved, city, 0)
	check(decoded.ok)
	if decoded.ok:
		decoded.state.reconcile(city, true)
		check_eq(decoded.state.record_at(AT).guests, 37, "current-format state outranks legacy metadata")
		check(not city.facility(AT).has("residents"))

func test_updated_authoritative_guests_survive_late_adoption() -> void:
	var city := flat_city()
	TourismFixture.venue(city, KEY, AT)
	var state := TourismState.new()
	state.reconcile(city)
	var rows := state.records()
	rows[0].guests = 37
	check_eq(state.replace_records(rows), OK)
	state.reconcile(city, true)
	check_eq(state.record_at(AT).guests, 37)

func test_store_growth_replacement_invalidates_identity_before_regrowth() -> void:
	for reconcile_between in [false, true]:
		for replacement in [Buildings.CONSTRUCTION_1X1_A, Buildings.ABANDONED_1X1_A, Buildings.CONSTRUCTION_2X2_FIRST]:
			var city := flat_city()
			var ctx := TourismFixture.context(city)
			var zones := ZoneSystem.new()
			zones.setup(ctx)
			var store := Buildings.id_of(&"com_corner_store")
			zones._stamp(ctx, AT, store, Zones.COM_LOW)
			city.add_facility(AT, {"key": &"com_corner_store", "name": "Established store",
				"built_day": 12, "built_year": 1900, "condition": 8, "unrelated": {"history": [3, 5]}})
			var state := TourismState.new()
			state.reconcile(city, true)
			var rows := state.records()
			rows[0].day_visitors = TourismParams.STORE_DAY_CAPACITY
			rows[0].target_day_visitors = TourismParams.STORE_DAY_CAPACITY
			rows[0].operating = true
			check_eq(state.replace_records(rows), OK)
			var old_instance: int = state.record_at(AT).instance
			var old_snapshot := state.to_dict()
			var metadata := city.facility(AT).duplicate(true)
			metadata.erase("tourism_instance")
			metadata.erase("tourism_migrated")
			zones._stamp(ctx, AT, replacement, Zones.COM_LOW)
			check(not city.facility(AT).has("tourism_instance"), "growth replacement invalidates token immediately")
			check(not city.facility(AT).has("tourism_migrated"), "replacement invalidates migration marker")
			check_eq(city.facility(AT), metadata, "unrelated metadata survives growth replacement")
			if reconcile_between:
				state.reconcile(city)
				check(state.record_at(AT).is_empty())
			zones._stamp(ctx, AT, store, Zones.COM_LOW)
			state.reconcile(city, true)
			var renewed := state.record_at(AT)
			check_gt(renewed.instance, old_instance, "regrowth allocates a newer lot instance")
			check_eq(renewed.guests, 0)
			check_eq(renewed.day_visitors, 0, "regrown store cannot inherit former attendance")
			check_eq(renewed.target_day_visitors, 0)
			var after := city.facility(AT).duplicate(true)
			after.erase("tourism_instance")
			after.erase("tourism_migrated")
			check_eq(after, metadata, "regrowth preserves unrelated facility metadata")
			var restored := TourismState.decode(old_snapshot, city, 0)
			check(restored.ok)
			if restored.ok:
				check(restored.state.records().is_empty(), "old occupancy snapshot rejects replacement identity")
