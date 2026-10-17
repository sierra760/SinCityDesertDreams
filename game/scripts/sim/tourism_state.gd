# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Canonical occupancy, keyed by standing facility instance rather than coordinates.
class_name TourismState
extends RefCounted

const SCHEMA := 3
## Largest integer exactly representable by a JSON number.
const MAX_INSTANCE := 9007199254740991

var _rows: Array[Dictionary] = []
## Derived read-cache invalidation only; never serialized.
var revision := 0
var _next_instance := 1
## Canonical restored/updated rows outrank any surviving legacy metadata.
var _adopted_instances: Dictionary = {}
var _city: City
var _buildings := PackedInt32Array()
var _zones := PackedByteArray()
var _anchors: Array[Vector2i] = []
var _validated_input := PackedByteArray()
var _validated_rows: Array[Dictionary] = []


func reconcile(city: City, adopt_legacy: bool = false) -> void:
	_refresh_anchors(city)
	# Reserve all standing tokens before allocating; discovery order never aliases
	# an imported token belonging to a later lot.
	for anchor in _anchors:
		var token: Variant = city.facility(anchor).get("tourism_instance", 0)
		if _integer(token, 1, MAX_INSTANCE - 1):
			_next_instance = maxi(_next_instance, int(token) + 1)
	var old := {}
	for row in _rows:
		old[row.anchor] = row
	var next: Array[Dictionary] = []
	var adopted := {}
	var used := {}
	for anchor in _anchors:
		var code := city.building_at(anchor.x, anchor.y)
		var key := Buildings.key(code)
		var facility := city.facility(anchor)
		if StringName(facility.get("key", &"")) != key:
			facility = {"key": key}
			city.add_facility(anchor, facility)
		if not facility.has("built_day"):
			facility.built_day = city.day
		if not facility.has("built_year"):
			facility.built_year = city.current_year()
		if not facility.has("condition"):
			facility.condition = 0
		# Reward snapshots retain this legacy resort metadata. Initialize it on
		# discovery so saving/loading a newly paid lot cannot add a field later.
		if Buildings.is_arcology(code) and not facility.has("capacity"):
			facility.capacity = TourismParams.guest_capacity(key)
		var token: Variant = facility.get("tourism_instance", 0)
		if not _integer(token, 1, MAX_INSTANCE - 1) or used.has(int(token)):
			token = _next_instance
			_next_instance += 1
			facility.tourism_instance = token
		used[int(token)] = true
		var row: Dictionary = old.get(anchor, {})
		var authoritative := false
		if row.get("instance", 0) != int(token) or row.get("code", -1) != code:
			row = _empty_row(anchor, key, code, int(token))
		else:
			row = row.duplicate(true)
			authoritative = _adopted_instances.has(int(token))
		if adopt_legacy:
			if not authoritative and not bool(facility.get("tourism_migrated", false)):
				row.guests = _legacy_count(facility.get("residents", 0), row.capacity)
				row["guest_segments"] = TourismMarkets.partition(row.guests,TourismMarkets.GUEST_WEIGHTS)
			facility.tourism_migrated = true
			authoritative = true
			# Transfer has completed before removing the old occupant source.
			facility.erase("residents")
		if authoritative or bool(facility.get("tourism_migrated", false)):
			adopted[int(token)] = true
		row["guest_segments"] = TourismMarkets.counts(row)
		row["day_segments"] = TourismMarkets.counts(row,true)
		next.append(row)
	_rows = next
	revision += 1
	_adopted_instances = adopted


func records() -> Array[Dictionary]:
	return _rows.duplicate(true)


func record_at(anchor: Vector2i) -> Dictionary:
	for row in _rows:
		if row.anchor == anchor:
			return row.duplicate(true)
	return {}


func to_dict() -> Dictionary:
	var encoded: Array[Dictionary] = []
	for row in _rows:
		var item := row.duplicate(true)
		item.anchor = [row.anchor.x, row.anchor.y]
		item.key = String(row.key)
		encoded.append(item)
	return {"schema": SCHEMA, "next_instance": _next_instance, "records": encoded}


func _refresh_anchors(city: City) -> void:
	var buildings := city.building.data
	var zones := city.zone.data
	if _city == city and buildings == _buildings and zones == _zones:
		return
	_city = city
	_buildings = buildings.duplicate()
	_zones = zones.duplicate()
	_anchors.clear()
	var keys := RewardParams.ARCOLOGIES.keys()
	keys.append(&"com_corner_store")
	var found := PackedInt32Array()
	for key in keys:
		var code := Buildings.id_of(key)
		var index := buildings.find(code)
		while index >= 0:
			if UtilityParams.is_anchor_tile(buildings, zones, index):
				@warning_ignore("integer_division")
				var anchor := Vector2i(index % City.WIDTH, index / City.WIDTH)
				if _standing(city, anchor, code):
					found.append(index)
			index = buildings.find(code, index + 1)
	found.sort()
	for index in found:
		@warning_ignore("integer_division")
		_anchors.append(Vector2i(index % City.WIDTH, index / City.WIDTH))


static func _standing(city: City, anchor: Vector2i, code: int) -> bool:
	var size := Buildings.size(code)
	if not city.in_bounds(anchor.x, anchor.y) or not city.in_bounds(anchor.x + size.x - 1, anchor.y + size.y - 1):
		return false
	if city.anchor_of(anchor.x, anchor.y) != anchor:
		return false
	for dy in size.y:
		for dx in size.x:
			if city.building_at(anchor.x + dx, anchor.y + dy) != code:
				return false
	return true


static func _empty_row(anchor: Vector2i, key: StringName, code: int, instance: int) -> Dictionary:
	return {"anchor": anchor, "key": key, "code": code, "instance": instance,
		"capacity": TourismParams.guest_capacity(key), "day_capacity": TourismParams.day_capacity(key),
		"guests": 0, "day_visitors": 0, "target_guests": 0, "target_day_visitors": 0,
		"arrivals": 0, "departures": 0, "appeal": 0, "operating": false, "reason": ""}


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= minimum and value <= maximum
	if typeof(value) == TYPE_FLOAT:
		return is_finite(value) and value == floor(value) and value >= minimum and value <= maximum
	return false


static func _legacy_count(value: Variant, capacity: int) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0
	if typeof(value) == TYPE_FLOAT and not is_finite(value):
		return 0
	return int(clampf(float(value), 0.0, float(capacity)))

## Internal monthly writer: complete current identity set, atomically installed.
## Presentation getters remain copies; caller dictionaries are never retained.
func replace_records(rows_to_install: Array[Dictionary]) -> Error:
	if _city == null or rows_to_install.size() != _rows.size():
		return ERR_INVALID_DATA
	# _validate_rows is a pure function of its input; exact (type-preserving)
	# byte equality with the previous accepted input reuses its result.
	var encoded := var_to_bytes(rows_to_install)
	var checked: Dictionary
	if encoded == _validated_input:
		checked = {"ok": true, "rows": _validated_rows.duplicate(true), "error": ""}
	else:
		checked = _validate_rows(rows_to_install, false)
		if checked.ok:
			_validated_input = encoded
			_validated_rows = checked.rows.duplicate(true)
	if not checked.ok:
		return ERR_INVALID_DATA
	var known := {}
	for row in _rows:
		known[row.anchor] = row
	for row in checked.rows:
		var previous: Dictionary = known.get(row.anchor, {})
		if previous.is_empty() or previous.instance != row.instance or previous.key != row.key or previous.code != row.code:
			return ERR_INVALID_DATA
		if not _matches_city(_city, row):
			return ERR_INVALID_DATA
	_rows.assign(checked.rows)
	revision += 1
	for row in _rows:
		_adopted_instances[row.instance] = true
		# Canonical attendance now owns this lot, including newly grown stores.
		# Persist that fact now so a save/resume does not add metadata later.
		_city.facility(row.anchor)["tourism_migrated"] = true
	return OK


## Pure snapshot validation. Month/pending-period checks belong to the system
## codec; this unit validates the supplied month only as a nonnegative context.
static func decode(data: Variant, city: City, month_id: int) -> Dictionary:
	if city == null or month_id < 0 or not data is Dictionary:
		return _failure("Invalid tourism state context or block")
	if not _integer(data.get("schema"), 1, SCHEMA):
		return _failure("Unsupported tourism state schema")
	if not _integer(data.get("next_instance"), 1, MAX_INSTANCE):
		return _failure("Invalid next tourism instance")
	var checked := _validate_rows(data.get("records"), true, int(data.schema) == 1)
	if not checked.ok:
		return _failure(checked.error)
	var next_instance := int(data.next_instance)
	# Validate the entire block, even rows whose venues have since vanished.
	for row in checked.rows:
		if row.instance >= next_instance:
			return _failure("Tourism instance counter must exceed every saved instance")
		if city.building_at(row.anchor.x, row.anchor.y) == row.code and city.anchor_of(row.anchor.x, row.anchor.y) != row.anchor:
			return _failure("Tourism row is not at a canonical lot anchor")
	var state := TourismState.new()
	state._next_instance = next_instance
	state._city = city
	for row in checked.rows:
		if _matches_city(city, row):
			state._rows.append(row)
			state._adopted_instances[row.instance] = true
	return {"ok": true, "state": state, "error": ""}


static func _matches_city(city: City, row: Dictionary) -> bool:
	if city.building_at(row.anchor.x, row.anchor.y) != row.code or not _standing(city, row.anchor, row.code):
		return false
	var facility := city.facility(row.anchor)
	var token: Variant = facility.get("tourism_instance")
	return _integer(token, 1, MAX_INSTANCE - 1) and int(token) == row.instance and StringName(facility.get("key", &"")) == row.key


static func _validate_rows(input: Variant, encoded: bool, previous_roster: bool = false) -> Dictionary:
	if not input is Array or input.size() > City.WIDTH * City.HEIGHT:
		return {"ok": false, "error": "Invalid tourism record list"}
	var rows: Array[Dictionary] = []
	var anchors := {}
	var instances := {}
	for value in input:
		if not value is Dictionary:
			return {"ok": false, "error": "Invalid tourism record"}
		var anchor: Vector2i
		var raw_anchor: Variant = value.get("anchor")
		if encoded:
			if not raw_anchor is Array or raw_anchor.size() != 2:
				return {"ok": false, "error": "Invalid encoded tourism anchor"}
			if not _integer(raw_anchor[0], 0, City.WIDTH - 1) or not _integer(raw_anchor[1], 0, City.HEIGHT - 1):
				return {"ok": false, "error": "Invalid tourism anchor coordinates"}
			anchor = Vector2i(int(raw_anchor[0]), int(raw_anchor[1]))
		else:
			if not raw_anchor is Vector2i:
				return {"ok": false, "error": "Invalid runtime tourism anchor"}
			anchor = raw_anchor
			if anchor.x < 0 or anchor.y < 0 or anchor.x >= City.WIDTH or anchor.y >= City.HEIGHT:
				return {"ok": false, "error": "Tourism anchor outside city"}
		var raw_key: Variant = value.get("key")
		if not raw_key is String and not raw_key is StringName:
			return {"ok": false, "error": "Invalid tourism venue key"}
		var key := StringName(raw_key)
		if key != &"com_corner_store" and not RewardParams.ARCOLOGIES.has(key):
			return {"ok": false, "error": "Unknown tourism venue"}
		var code := Buildings.id_of(key)
		if not _integer(value.get("code"), code, code) or not _integer(value.get("instance"), 1, MAX_INSTANCE - 1):
			return {"ok": false, "error": "Invalid tourism venue identity"}
		var instance := int(value.instance)
		if anchors.has(anchor) or instances.has(instance):
			return {"ok": false, "error": "Duplicate tourism anchor or instance"}
		anchors[anchor] = true
		instances[instance] = true
		var row := _empty_row(anchor, key, code, instance)
		var guest_limit := TourismParams.profile_guest_capacity(key, TourismParams.PREVIOUS_PROFILE) if previous_roster else int(row.capacity)
		var day_limit := TourismParams.profile_day_capacity(key, TourismParams.PREVIOUS_PROFILE) if previous_roster else int(row.day_capacity)
		# Saved capacities are a profile assertion, never arbitrary authority.
		for pair in [["capacity", guest_limit], ["day_capacity", day_limit]]:
			if value.has(pair[0]) and not _integer(value[pair[0]], pair[1] if encoded else 0, pair[1] if encoded else TourismParams.MAX_COUNT):
				return {"ok": false, "error": "Tourism capacity does not match its roster"}
		for field in ["guests", "day_visitors", "target_guests", "target_day_visitors", "arrivals", "departures", "appeal"]:
			var limit := guest_limit
			var current_limit := int(row.capacity)
			if field == "day_visitors" or field == "target_day_visitors":
				limit = day_limit
				current_limit = int(row.day_capacity)
			elif field == "appeal":
				limit = TourismParams.APPEAL_MAX
				current_limit = limit
			if not _integer(value.get(field), 0, limit):
				return {"ok": false, "error": "Invalid tourism " + field}
			row[field] = mini(int(value[field]), current_limit)
		for pair in [["guest_segments","guests",TourismMarkets.GUEST_WEIGHTS],["day_segments","day_visitors",TourismMarkets.DAY_WEIGHTS]]:
			var count := int(value[pair[1]])
			if value.has(pair[0]) and not TourismMarkets.valid_segments(value[pair[0]],count):
				return {"ok":false,"error":"Tourism segments do not conserve attendance"}
			var segments: Array = value.get(pair[0],TourismMarkets.partition(count,pair[2]))
			row[pair[0]] = TourismMarkets.partition(int(row[pair[1]]),segments) if count != int(row[pair[1]]) else segments.map(func(v: Variant) -> int: return int(v))
		if not value.get("operating") is bool or not value.get("reason") is String:
			return {"ok": false, "error": "Invalid tourism operating status"}
		row.operating = value.operating
		row.reason = value.reason
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.anchor.y * City.WIDTH + a.anchor.x < b.anchor.y * City.WIDTH + b.anchor.x)
	return {"ok": true, "rows": rows, "error": ""}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "state": null, "error": message}
