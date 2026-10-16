# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Exact source pressure and bounded local consequences. No simulation RNG.
class_name TourismEffects
extends RefCounted

static func neutral_features() -> Dictionary:
	return {"safety": {"period_month": -1, "active": false, "cost_half_cents": 0, "remainders": []},
		"migration": {"grace_until_month": -1}, "reputation": {"value_milli": 60000, "empty_months": 0},
		"districts": {}, "access": {}, "markets": {}, "staffing": {}, "utilities": {}, "calendar": {}}

## Optional blocks have stable names; later phases own their bounded contents.
## Historical business is never re-priced when an earlier schema is adopted.
static func decode_features(block: Dictionary, month: int) -> Dictionary:
	var features := neutral_features()
	if not block.is_empty():
		var state: Variant = block.get("state")
		var activity: Variant = block.get("activity", {})
		if not state is Dictionary or not state.get("records") is Array or not activity is Dictionary: return {"ok": false}
		for value: Variant in state.records:
			if not value is Dictionary or not TourismState._integer(value.get("instance"), 1, TourismState.MAX_INSTANCE - 1): return {"ok": false}
		var activity_check := TourismSystem.validate_activity(activity, int(block.get("last_month", -1)), TourismSystem.activity_profile(block))
		if not activity_check.ok: return {"ok": false}
	var input: Variant = block.get("features", {})
	if not input is Dictionary: return {"ok": false}
	for key in input:
		if not features.has(key) or not input[key] is Dictionary: return {"ok": false}
		features[key] = input[key].duplicate(true)
	if not block.is_empty() and int(block.get("schema", 0)) < 3 and not input.has("migration"):
		features.migration.grace_until_month = month + 1
	var grace: Dictionary = features.migration
	if grace.size() != 1 or not TourismState._integer(grace.get("grace_until_month"), -1, month + 1): return {"ok": false}
	var reputation: Dictionary = features.reputation
	var reputation_check := TourismReputation.decode(reputation,block,month)
	if not reputation_check.ok: return {"ok":false}
	features.reputation=reputation_check.value
	for key in ["districts"]:
		if not features[key].is_empty(): return {"ok": false}
	var calendar := TourismCalendar.decode(features.calendar,block,month)
	if not calendar.ok: return {"ok":false}
	features.calendar = calendar.value
	var utilities := TourismUtilities.decode(features.utilities,block,month)
	if not utilities.ok: return {"ok":false}
	features.utilities = utilities.value
	var staffing := TourismEconomy.decode(features.staffing,block,month)
	if not staffing.ok: return {"ok":false}
	features.staffing = staffing.value
	var market: Dictionary = features.markets
	if not market.is_empty():
		if market != {"profile":TourismMarkets.PROFILE} or TourismSystem.activity_profile(block) != TourismMarkets.PROFILE: return {"ok":false}
		for row: Dictionary in block.get("state",{}).get("records",[]):
			if not TourismMarkets.valid_segments(row.get("guest_segments"),int(row.get("guests",0))) or not TourismMarkets.valid_segments(row.get("day_segments"),int(row.get("day_visitors",0))): return {"ok":false}
	elif TourismSystem.activity_profile(block) == TourismMarkets.PROFILE: return {"ok":false}
	var access := TourismAccess.decode_accepted(features.access,block,month)
	if not access.ok: return {"ok":false}
	features.access = access.value
	var safety: Dictionary = features.safety
	if safety.size() != 4 or not safety.get("active") is bool: return {"ok": false}
	if not TourismState._integer(safety.get("period_month"), -1, int(block.get("last_month", -1))): return {"ok": false}
	if not TourismState._integer(safety.get("cost_half_cents"), 0, TourismState.MAX_INSTANCE): return {"ok": false}
	var expected := 0
	if int(safety.period_month) >= 0:
		if int(safety.period_month) != int(block.get("last_month", -1)): return {"ok": false}
		for row: Dictionary in block.get("activity", {}).get("rows", []):
			expected += (int(row.get("guest_half_months", 0)) + 2 * int(row.get("day_visitors", 0))) * TourismParams.SAFETY_CENTS_PER_VISITOR
	elif safety.active: return {"ok": false}
	if int(safety.cost_half_cents) != (expected if safety.active else 0): return {"ok": false}
	var remainders: Variant = safety.get("remainders")
	if not remainders is Array or remainders.size() > City.WIDTH * City.HEIGHT: return {"ok": false}
	var known := {}
	for row: Dictionary in block.get("state", {}).get("records", []): known[int(row.get("instance", 0))] = true
	var seen := {}
	for value: Variant in remainders:
		if not value is Dictionary or value.size() != 6: return {"ok": false}
		if not TourismState._integer(value.get("instance"), 1, TourismState.MAX_INSTANCE - 1): return {"ok": false}
		var instance := int(value.instance)
		if not known.has(instance) or seen.has(instance): return {"ok": false}
		seen[instance] = true
		if not TourismState._integer(value.get("month"), 0, month): return {"ok": false}
		for field in ["micro", "opening_micro"]:
			if not TourismState._integer(value.get(field), 0, TourismParams.CRIME_MICRO_UNIT - 1): return {"ok": false}
		for field in ["cursor", "opening_cursor"]:
			if not TourismState._integer(value.get(field), 0, 1023): return {"ok": false}
	# JSON numbers arrive as floats; validated integral fields become integers
	# before installation, preserving byte-stable subsequent snapshots.
	grace.grace_until_month = int(grace.grace_until_month)
	safety.period_month = int(safety.period_month)
	safety.cost_half_cents = int(safety.cost_half_cents)
	for value: Dictionary in remainders:
		for field in ["instance", "month", "micro", "cursor", "opening_micro", "opening_cursor"]:
			value[field] = int(value[field])
	return {"ok": true, "features": features}

static func prune(features: Dictionary, rows: Array[Dictionary]) -> void:
	var live := {}
	for row in rows: live[int(row.instance)] = true
	var retained: Array = []
	for row: Dictionary in features.safety.remainders:
		if live.has(int(row.instance)): retained.append(row)
	features.safety.remainders = retained

@warning_ignore("integer_division")
static func venue_effect(row: Dictionary, business: Dictionary, safety: Dictionary) -> Dictionary:
	var half_guests := int(business.get("guest_half_months", 2 * int(row.guests)))
	var days := int(business.get("day_visitors", row.day_visitors))
	if not row.operating or int(row.guests) + int(row.day_visitors) == 0:
		half_guests = 0
		days = 0
	var raw := (half_guests * TourismParams.GUEST_CRIME_MICRO / 2 + days * TourismParams.DAY_CRIME_MICRO) * TourismParams.security_percent(row.key) / 100
	var active := bool(safety.active) and int(safety.period_month) >= 0 and not business.is_empty()
	var source := raw * TourismParams.SAFETY_REMAINING_PERCENT / 100 if active else raw
	var visitors := (half_guests + 1) / 2 + days
	var factor: int = {"budget": 100, "standard": 80, "premium": 50}[TourismParams.venue_tier(row.key)]
	var strength := mini(TourismParams.NIGHTLIFE_CAP, (visitors * factor + TourismParams.NIGHTLIFE_VISITOR_DIVISOR * 100 - 1) / (TourismParams.NIGHTLIFE_VISITOR_DIVISOR * 100))
	return {"security_tier": TourismParams.venue_tier(row.key), "crime_raw_micro": raw,
		"crime_source_micro": source, "crime_source_milli": source / 1000.0,
		"safety_active": active, "nightlife_strength": strength}

## Fractional source is carried per live instance. Whole units are assigned to
## a weighted ring, with a saved cursor rather than a separately truncated share
## at every block. Repeated reads/passes in one month reuse its opening carry.
@warning_ignore("integer_division")
static func environment(city: City, rows: Array, safety: Dictionary, month: int, developed: PackedByteArray) -> Dictionary:
	var crime := PackedInt32Array()
	var nightlife := PackedInt32Array()
	crime.resize(City.HALF * City.HALF)
	nightlife.resize(crime.size())
	var previous := {}
	for value: Dictionary in safety.remainders: previous[int(value.instance)] = value
	var next: Array = []
	for row: Dictionary in rows:
		var instance := int(row.instance)
		var state: Dictionary = previous.get(instance, {"instance": instance, "micro": 0, "cursor": 0,
			"opening_micro": 0, "opening_cursor": 0, "month": month})
		if int(state.month) != month:
			state.opening_micro = int(state.micro)
			state.opening_cursor = int(state.cursor)
			state.month = month
		var total := int(state.opening_micro) + int(row.crime_source_micro)
		var whole := total / TourismParams.CRIME_MICRO_UNIT
		state.micro = total % TourismParams.CRIME_MICRO_UNIT
		var ring := _crime_ring(row, developed)
		if not ring.is_empty():
			var cursor := int(state.opening_cursor) % ring.size()
			# Bounded by the venue's immutable capacity, independent of city size.
			for offset in whole: crime[ring[(cursor + offset) % ring.size()]] += 1
			state.cursor = (cursor + whole) % ring.size()
		next.append(state)
		_add_nightlife(city, row, nightlife)
	safety.remainders = next
	return {"crime": crime, "nightlife": nightlife}

@warning_ignore("integer_division")
static func _crime_ring(row: Dictionary, developed: PackedByteArray) -> Array[int]:
	var a: Vector2i = row.anchor
	var size := Buildings.size(int(row.code))
	var ring: Array[int] = []
	# Interleave weight layers so the cursor visits every surrounding block.
	for layer in 4:
		for by in range(maxi(0, (a.y - 2) / 2), mini(City.HALF, (a.y + size.y + 3) / 2)):
			for bx in range(maxi(0, (a.x - 2) / 2), mini(City.HALF, (a.x + size.x + 3) / 2)):
				var index := by * City.HALF + bx
				if developed[index] == 0: continue
				var distance := maxi(0, maxi(a.x - (bx * 2 + 1), bx * 2 - (a.x + size.x - 1))) + maxi(0, maxi(a.y - (by * 2 + 1), by * 2 - (a.y + size.y - 1)))
				var weight := 4 if distance == 0 else (2 if distance == 1 else (1 if distance == 2 else 0))
				if layer < weight: ring.append(index)
	return ring

@warning_ignore("integer_division")
static func _add_nightlife(city: City, row: Dictionary, output: PackedInt32Array) -> void:
	var strength := int(row.nightlife_strength)
	if strength == 0: return
	var a: Vector2i = row.anchor
	var size := Buildings.size(int(row.code))
	var r := TourismParams.NIGHTLIFE_RADIUS
	var per_block := {}
	for y in range(maxi(0, a.y - r), mini(City.HEIGHT, a.y + size.y + r)):
		for x in range(maxi(0, a.x - r), mini(City.WIDTH, a.x + size.x + r)):
			if not Zones.is_residential(city.zone_kind_at(x, y)): continue
			var nearest := Vector2i(clampi(x, a.x, a.x + size.x - 1), clampi(y, a.y, a.y + size.y - 1))
			var distance := absi(x - nearest.x) + absi(y - nearest.y)
			if distance > r: continue
			var green := 0
			var p := nearest
			while p != Vector2i(x, y):
				p += Vector2i(signi(x - p.x), 0) if p.x != x else Vector2i(0, signi(y - p.y))
				var code := city.building_at(p.x, p.y)
				if Buildings.is_tree(code) or code in [Buildings.SMALL_PARK, Buildings.LARGE_PARK]: green += 1
			var penalty := maxi(0, (strength * (r + 1 - distance) + r) / (r + 1) - green * 2)
			var index := (y / 2) * City.HALF + x / 2
			per_block[index] = maxi(int(per_block.get(index, 0)), penalty)
	for index: int in per_block: output[index] = mini(TourismParams.NIGHTLIFE_CAP, output[index] + int(per_block[index]))

## Actual concurrent attendance creates business opportunity, never city cash.
static func commercial_spending_cents(row: Dictionary) -> int:
	if not row.get("operating", false): return 0
	var guests := TourismMarkets.counts(row)
	var days := TourismMarkets.counts(row,true)
	var numerator := 0
	for segment in 4:
		numerator += (int(guests[segment])*TourismParams.GUEST_RETAIL_CENTS+int(days[segment])*TourismParams.DAY_RETAIL_CENTS)*int(TourismMarkets.SPEND[segment])
	return numerator / 100
