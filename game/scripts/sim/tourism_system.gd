# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Concurrent guests/day visitors and completed monthly visitor business.
## CityStats is a derived publication; only this state owns attendance.
class_name TourismSystem
extends SimSystem

signal attendance_changed(anchors: Array[Vector2i])

const SCHEMA := 2
var _ctx: SimContext
var _state := TourismState.new()
var _last_month := -1
var _pending: Dictionary = {}
## Encoded immutable rows for the last completed month, including removed lots.
var _activity: Dictionary = {}
var _activity_profile := TourismParams.CURRENT_PROFILE
var _loaded: Dictionary = {}
var _finished := false
var _published_attendance: Dictionary = {}

func _init() -> void:
	key = &"tourism"

## Binding does not adopt old facility counts or expose partially restored totals.
func setup(ctx: SimContext) -> void:
	_ctx = ctx

func finish_restore(snapshot: Dictionary) -> Error:
	if _ctx == null:
		return ERR_UNCONFIGURED
	var systems: Dictionary = snapshot.get("systems", {})
	var block: Dictionary = systems.get("tourism", _loaded)
	# Only a legacy population transfer can invalidate a resident-derived class.
	# Current saves retain classes earned before an ordinary resident decline.
	var migrate_population := false
	if block.is_empty():
		migrate_population = _ctx.stats.arcology_population > 0
		for facility: Dictionary in _ctx.city.facilities.values():
			if RewardParams.ARCOLOGIES.has(StringName(facility.get("key", &""))) \
					and facility.has("residents") and not bool(facility.get("tourism_migrated", false)):
				migrate_population = true
				break
	var next_state := _state
	var last := -1
	var pending: Dictionary = {}
	var activity: Dictionary = {}
	var profile := TourismParams.CURRENT_PROFILE
	if not block.is_empty():
		var checked := validate_period(block, _month_id(), systems.get("budget", {}))
		if not checked.ok:
			return ERR_INVALID_DATA
		var decoded := TourismState.decode(block.get("state"), _ctx.city, _month_id())
		if not decoded.ok:
			return ERR_INVALID_DATA
		next_state = decoded.state
		last = int(block.last_month)
		pending = checked.pending
		activity = block.get("activity", {}).duplicate(true)
		profile = activity_profile(block)
	_state = next_state
	_last_month = last
	_pending = pending.duplicate(true)
	_activity = activity
	_activity_profile = profile
	_loaded.clear()
	_state.reconcile(_ctx.city, true)
	if migrate_population:
		_ctx.city.status = clampi(_ctx.city.status, 0, PopulationSystem.derived_status(_ctx.stats.population))
	_finished = true
	reconcile_now()
	return OK

## Shared with the save boundary: no money or state mutation while validating.
static func validate_period(block: Dictionary, month_id: int, budget: Dictionary = {}) -> Dictionary:
	if not TourismState._integer(block.get("schema"), 1, SCHEMA):
		return {"ok": false}
	if not TourismState._integer(block.get("last_month"), -1, month_id):
		return {"ok": false}
	var pending: Variant = block.get("pending", {})
	if not pending is Dictionary:
		return {"ok": false}
	var booked: Variant = budget.get("tourism_booked_month", -1)
	if not TourismState._integer(booked, -1, month_id):
		return {"ok": false}
	if int(booked) > int(block.last_month):
		return {"ok": false}
	var profile := activity_profile(block)
	if profile not in [TourismParams.CURRENT_PROFILE, TourismParams.PREVIOUS_PROFILE]:
		return {"ok": false}
	var activity_check := validate_activity(block.get("activity", {}), int(block.last_month), profile)
	if not activity_check.ok:
		return {"ok": false}
	if pending.is_empty() and int(block.last_month) != int(booked):
		return {"ok": false}
	if not pending.is_empty():
		if not TourismState._integer(pending.get("month_id"), 0, month_id) or int(pending.month_id) != int(block.last_month):
			return {"ok": false}
		for field in ["lodging_cents", "gaming_cents"]:
			if not TourismState._integer(pending.get(field), 0, TourismState.MAX_INSTANCE) or int(pending[field]) % 25 != 0:
				return {"ok": false}
		if int(pending.lodging_cents) != activity_check.lodging_cents or int(pending.gaming_cents) != activity_check.gaming_cents:
			return {"ok": false}
		if int(pending.month_id) <= int(booked):
			pending = {}
	return {"ok": true, "pending": pending.duplicate(true)}

## Schema 1 predates capacity tuning; retained business may outlive every lot.
static func activity_profile(block: Dictionary) -> String:
	if block.get("schema") == 1:
		return TourismParams.PREVIOUS_PROFILE
	var profile: Variant = block.get("activity_profile", TourismParams.CURRENT_PROFILE)
	return profile if profile is String else ""

## Activity belongs to the completed venue instance, even after demolition.
## Rows encode identity plus exact half-guest-months and concurrent day visits.
static func validate_activity(activity: Variant, last_month: int, profile: String = TourismParams.CURRENT_PROFILE) -> Dictionary:
	var result := {"ok": false, "lodging_cents": 0, "gaming_cents": 0}
	if not activity is Dictionary:
		return result
	if activity.is_empty():
		result.ok = last_month == -1
		return result
	if not TourismState._integer(activity.get("month_id"), 0, last_month) or int(activity.month_id) != last_month:
		return result
	var rows: Variant = activity.get("rows")
	if not rows is Array or rows.size() > City.WIDTH * City.HEIGHT:
		return result
	var instances := {}
	var anchors := {}
	for row: Variant in rows:
		if not row is Dictionary:
			return result
		var raw_key: Variant = row.get("key")
		if not raw_key is String:
			return result
		var key := StringName(raw_key)
		if key != &"com_corner_store" and not RewardParams.ARCOLOGIES.has(key):
			return result
		var code := Buildings.id_of(key)
		var anchor: Variant = row.get("anchor")
		if not anchor is Array or anchor.size() != 2:
			return result
		if not TourismState._integer(anchor[0], 0, City.WIDTH - 1) or not TourismState._integer(anchor[1], 0, City.HEIGHT - 1):
			return result
		if not TourismState._integer(row.get("code"), code, code) or not TourismState._integer(row.get("instance"), 1, TourismState.MAX_INSTANCE - 1):
			return result
		var tile := int(anchor[1]) * City.WIDTH + int(anchor[0])
		if instances.has(int(row.instance)) or anchors.has(tile):
			return result
		instances[int(row.instance)] = true
		anchors[tile] = true
		if not TourismState._integer(row.get("guest_half_months"), 0, 2 * TourismParams.profile_guest_capacity(key, profile)) or not TourismState._integer(row.get("day_visitors"), 0, TourismParams.profile_day_capacity(key, profile)):
			return result
		result.lodging_cents += int(row.guest_half_months) * TourismParams.LODGING_CENTS_PER_HALF_GUEST
		result.gaming_cents += int(row.guest_half_months) * TourismParams.GAMING_CENTS_PER_HALF_GUEST + int(row.day_visitors) * TourismParams.GAMING_CENTS_PER_VISITOR
	result.ok = true
	return result

func daily(_context: SimContext) -> void:
	reconcile_now()

func networks_changed(_context: SimContext, _rect: Rect2i) -> void:
	reconcile_now()

## Native layer comparisons cache venue discovery; per-day work visits venues
## and their footprints, never every city tile in a script loop or every frame.
func reconcile_now() -> void:
	if not _finished:
		return
	_state.reconcile(_ctx.city)
	var rows := _environment_rows()
	for row in rows:
		if not row.operating:
			row.guests = 0
			row.day_visitors = 0
			row.target_guests = 0
			row.target_day_visitors = 0
			row.arrivals = 0
			row.departures = 0
	_state.replace_records(rows)
	_publish()

func monthly(_context: SimContext, _phase: int = 0) -> void:
	if not _finished:
		return
	reconcile_now()
	var month := _month_id()
	if month <= _last_month or not _pending.is_empty():
		return
	var predicted := forecast()
	var rows: Array[Dictionary] = []
	var lodging := 0
	var gaming := 0
	var activity_rows: Array[Dictionary] = []
	for value: Dictionary in predicted.rows:
		var row := value.duplicate(true)
		var opening := int(row.guests)
		var change := TourismDemand.turnover(opening, int(row.target_guests))
		row.guests = change.guests
		row.arrivals = change.arrivals
		row.departures = change.departures
		row.day_visitors = row.target_day_visitors
		var bases := TourismDemand.business_bases(opening, row.guests, row.day_visitors)
		lodging += int(bases.lodging_cents)
		gaming += int(bases.gaming_cents)
		activity_rows.append({"anchor": [row.anchor.x, row.anchor.y], "key": String(row.key),
			"code": row.code, "instance": row.instance, "guest_half_months": opening + int(row.guests),
			"day_visitors": row.day_visitors})
		rows.append(row)
	if _state.replace_records(rows) != OK:
		return
	_last_month = month
	_activity_profile = TourismParams.CURRENT_PROFILE
	_activity = {"month_id": month, "rows": activity_rows}
	_pending = {"month_id": month, "lodging_cents": lodging, "gaming_cents": gaming}
	_publish()

func forecast(occupancy_rate: int = -1, gaming_rate: int = -1) -> Dictionary:
	if _ctx == null:
		return {}
	var stats := _ctx.stats
	return TourismDemand.forecast(_environment_rows(), {
		"permanent_population": stats.population, "neighbor_populations": stats.neighbor_populations,
		"economy_phase": stats.economy_phase, "average_land_value": stats.average_land_value,
		"average_crime": stats.average_crime, "average_pollution": stats.average_pollution,
		"average_traffic": stats.average_traffic,
		"tourist_advertising": stats.ordinances.get(&"tourist_advertising", false),
		"annual_carnival": stats.ordinances.get(&"annual_carnival", false)},
		stats.tax_occupancy if occupancy_rate < 0 else occupancy_rate,
		stats.tax_gaming if gaming_rate < 0 else gaming_rate)

func report() -> Array[Dictionary]:
	var rows := _state.records()
	var activity_by_instance := {}
	for item: Dictionary in _activity.get("rows", []):
		activity_by_instance[int(item.instance)] = item
	for row in rows:
		var facility := _ctx.city.facility(row.anchor)
		row["tourists"] = row.guests + row.day_visitors
		row["occupancy"] = int(row.guests) * 100 / int(row.capacity) if row.capacity > 0 else 0
		row["built_day"] = facility.get("built_day", _ctx.city.day)
		row["built_year"] = facility.get("built_year", _ctx.city.current_year())
		row["condition"] = facility.get("condition", 0)
		row["pollution"] = int(row.tourists) / 1000 * RewardParams.POLLUTION_PER_THOUSAND
		row["crime"] = int(row.tourists) / 1000 * RewardParams.CRIME_PER_THOUSAND
		var current := TourismDemand.business_bases(row.guests, row.guests, row.day_visitors)
		row["current_lodging_cents"] = current.lodging_cents
		row["current_gaming_cents"] = current.gaming_cents
		var business: Dictionary = activity_by_instance.get(int(row.instance), {})
		row["business_month"] = _last_month if not business.is_empty() else -1
		var half_months := int(business.get("guest_half_months", 0))
		row["guest_half_months"] = half_months
		row["business_day_visitors"] = int(business.get("day_visitors", 0))
		row["lodging_cents"] = half_months * TourismParams.LODGING_CENTS_PER_HALF_GUEST
		row["gaming_cents"] = half_months * TourismParams.GAMING_CENTS_PER_HALF_GUEST + int(row.business_day_visitors) * TourismParams.GAMING_CENTS_PER_VISITOR
	return rows

func venue_report(anchor: Vector2i) -> Dictionary:
	for row in report():
		if row.anchor == anchor:
			return row
	return {}

func pending_bases() -> Dictionary:
	return _pending.duplicate(true)

func acknowledge_booking(month_id: int) -> void:
	if not _pending.is_empty() and int(_pending.month_id) == month_id:
		_pending.clear()
		# Published business bases describe the latest completed month, not
		# whether the budget has consumed it yet.

func save() -> Dictionary:
	return {"schema": SCHEMA, "activity_profile": _activity_profile, "state": _state.to_dict(), "last_month": _last_month, "pending": _pending.duplicate(true), "activity": _activity.duplicate(true)}

func load(data: Dictionary) -> void:
	_loaded = data.duplicate(true)
	_finished = false

@warning_ignore("integer_division")
func _month_id() -> int:
	return _ctx.clock.day / GameClock.DAYS_PER_MONTH

func _environment_rows() -> Array[Dictionary]:
	var rows := _state.records()
	var city := _ctx.city
	var fires := {}
	var disasters := _ctx.system(&"disasters")
	if disasters != null and disasters.has_method("fires"):
		for tile: Vector2i in disasters.call("fires"):
			fires[tile] = true
	for row in rows:
		var a: Vector2i = row.anchor
		row["land_value"] = city.land_value_at(a.x, a.y)
		row["crime"] = city.crime_at(a.x, a.y)
		row["pollution"] = city.pollution_at(a.x, a.y)
		row.reason = _operating_reason(row, fires)
		row.operating = row.reason.is_empty()
	return rows

func _operating_reason(row: Dictionary, fires: Dictionary) -> String:
	var a: Vector2i = row.anchor
	var city := _ctx.city
	var size := Buildings.size(row.code)
	for dy in size.y:
		for dx in size.x:
			if fires.has(a + Vector2i(dx, dy)):
				return "Active fire."
	for dy in size.y:
		for dx in size.x:
			if not city.is_powered(a.x + dx, a.y + dy):
				return "Needs power throughout the venue."
	for dy in size.y:
		for dx in size.x:
			if not city.is_watered(a.x + dx, a.y + dy):
				return "Needs water throughout the venue."
	if not ZoneSystem.has_access(city, Rect2i(a, size)):
		return "Needs a road or station within three tiles."
	return ""

func _publish() -> void:
	var stats := _ctx.stats
	stats.arcology_population = 0
	stats.tourist_guests = 0
	stats.tourist_day_visitors = 0
	stats.tourist_capacity = 0
	for row in _state.records():
		stats.tourist_guests += int(row.guests)
		stats.tourist_day_visitors += int(row.day_visitors)
		if row.operating:
			stats.tourist_capacity += int(row.capacity)
	stats.tourists = stats.tourist_guests + stats.tourist_day_visitors
	stats.tourist_occupancy = stats.tourist_guests * 100 / stats.tourist_capacity if stats.tourist_capacity > 0 else 0
	var business := validate_activity(_activity, _last_month, _activity_profile)
	stats.tourist_lodging_cents = int(business.lodging_cents)
	stats.tourist_gaming_cents = int(business.gaming_cents)
	_notify_attendance()

## Identity and per-venue counts matter even if the scalar total is unchanged.
func _notify_attendance() -> void:
	var next := {}
	var changed: Array[Vector2i] = []
	for row in _state.records():
		var signature := [row.instance, row.guests, row.day_visitors, row.operating]
		next[row.anchor] = signature
		if _published_attendance.get(row.anchor, []) != signature:
			changed.append(row.anchor)
	for anchor: Vector2i in _published_attendance:
		if not next.has(anchor):
			changed.append(anchor)
	_published_attendance = next
	if not changed.is_empty():
		changed.sort_custom(func(a: Vector2i, b: Vector2i): return a.y * City.WIDTH + a.x < b.y * City.WIDTH + b.x)
		attendance_changed.emit(changed)
