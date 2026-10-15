# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Private farm development, service lifecycle and independent demand.
class_name AgricultureSystem
extends SimSystem

const Params := preload("res://scripts/sim/data/agriculture_params.gd")
const SEED_SALT := 0x4167726963756C74
## Bound candidate projections; unchanged active farms share one service map.
const DEVELOPMENT_BUDGET := 16
## One unchanged active census, at most 16 candidate previews, and at most
## 16 validation passes (every failed pass removes at least one activation).
const MAX_PROJECTIONS_PER_PHASE := 2 * DEVELOPMENT_BUDGET + 1
var _ctx: SimContext
var _rng := SimRng.from_saved_seed(0)
var _raw := Params.DEMAND_INITIAL
var _lots: Dictionary = {}
var _demand_month := -1
var _phase_months: Array[int] = [-1, -1]
var _service_map: City
var _projection_count := 0

func _init() -> void:
	key = &"agriculture"

func setup(ctx: SimContext) -> void:
	_ctx = ctx
	_rng = SimRng.from_saved_seed(ctx.rng.seed_value() ^ SEED_SALT)
	_reconcile()
	_publish()

func networks_changed(ctx: SimContext, _rect: Rect2i) -> void:
	_ctx = ctx
	_service_map = null
	_reconcile()
	_publish()

func raw_demand() -> int:
	return _raw

func projection_count() -> int:
	return _projection_count

func jobs() -> int:
	_reconcile()
	return _jobs()

func _jobs() -> int:
	var total := 0
	for lot: Dictionary in _lots.values():
		if lot.state == &"active": total += Params.jobs_of(lot.building_id)
	return total

func assessed_value() -> int:
	return jobs() * Params.ASSESSMENT_PER_JOB

func current_lots() -> Array[Dictionary]:
	_reconcile()
	var result: Array[Dictionary] = []
	for lot: Dictionary in _lots.values(): result.append(lot.duplicate(true))
	return result

func inspect_tile(tile: Vector2i) -> Dictionary:
	if _ctx == null or not _ctx.city.in_bounds(tile.x, tile.y): return {}
	_reconcile()
	var city := _ctx.city
	var kind := city.zone_kind_at(tile.x, tile.y)
	if not Zones.is_agricultural(kind): return {}
	var anchor := city.anchor_of(tile.x, tile.y)
	if not _lots.has(anchor):
		var rect := Rect2i(tile, Vector2i.ONE)
		var reason := _land_reason(rect, kind)
		if reason.is_empty() and not ZoneSystem.has_access(city, rect): reason = "Needs road or station access within three tiles."
		if reason.is_empty() and _emergency(): reason = "Development waits until the emergency ends."
		if reason.is_empty(): reason = "Waiting for positive agricultural demand." if _raw <= 0 else "Waiting for monthly preparation."
		return {"anchor": tile, "archetype": &"", "state": &"zoned", "building_id": city.building_at(tile.x, tile.y),
			"rect": rect, "failed_months": 0, "blocked_reason": reason, "jobs": 0,
			"water_required": 0, "water_supplied": false, "power_required": 0, "power_supplied": true}
	var lot: Dictionary = _lots[anchor].duplicate(true)
	_service_map = null
	var service := _service(lot)
	lot.merge(service, true)
	if lot.blocked_reason.is_empty() and (_raw < 0 or (_raw == 0 and lot.state != &"active")):
		lot.blocked_reason = "Waiting for positive agricultural demand."
	lot["jobs"] = Params.jobs_of(lot.building_id) if lot.state == &"active" else 0
	return lot

func monthly(ctx: SimContext, phase: int = 0) -> void:
	if phase < 0 or phase > 1: return
	_ctx = ctx
	@warning_ignore("integer_division")
	var month := ctx.clock.day / GameClock.DAYS_PER_MONTH
	if _phase_months[phase] == month: return
	_reconcile()
	if _demand_month != month:
		_update_demand()
		_demand_month = month
	_phase_months[phase] = month
	_projection_count = 0
	_service_map = null
	var x0 := 0 if phase == 0 else City.HALF
	var x1 := City.HALF if phase == 0 else City.WIDTH
	var touched := {}
	var dirty := Rect2i()
	var before_building := ctx.city.building.data.duplicate()
	var waiting: Array[Dictionary] = []
	var declining: Array[Dictionary] = []
	var activated := {}
	# All existing active lots evaluate the same allocation before this batch
	# changes loads. This avoids a new whole-city projection per dormant farm.
	for lot: Dictionary in _lots.values():
		if lot.anchor.x < x0 or lot.anchor.x >= x1 or lot.last_month == month or _protected(lot.rect): continue
		if lot.state != &"active":
			waiting.append(lot)
			continue
		lot.last_month = month
		var service := _service(lot)
		lot.failed_months = 0 if service.blocked_reason.is_empty() and _raw >= 0 else mini(Params.FAILURE_MONTHS, int(lot.failed_months) + 1)
		if lot.failed_months >= Params.FAILURE_MONTHS: declining.append(lot)
	for lot in declining:
		_change(lot, &"dormant", month)
		dirty = _merge(dirty, lot.rect)
		_touch(touched, lot.rect)
	# Random start prevents permanently starving later anchors when many plots
	# await service. This draw belongs only to the saved agricultural RNG.
	if _raw > 0 and not waiting.is_empty():
		var first := _rng.below(waiting.size()) if waiting.size() > DEVELOPMENT_BUDGET else 0
		for offset in mini(waiting.size(), DEVELOPMENT_BUDGET):
			var lot: Dictionary = waiting[(first + offset) % waiting.size()]
			lot.last_month = month
			if not _service(lot).blocked_reason.is_empty(): continue
			activated[lot.anchor] = {"state": lot.state, "failed_months": lot.failed_months}
			_change(lot, &"active", month)
			dirty = _merge(dirty, lot.rect)
			_touch(touched, lot.rect)
	var attempts := 0
	if _raw > 0:
		for y in range(Params.EDGE_MARGIN, City.HEIGHT - Params.EDGE_MARGIN):
			for x in range(maxi(x0, Params.EDGE_MARGIN), mini(x1, City.WIDTH - Params.EDGE_MARGIN)):
				if attempts >= DEVELOPMENT_BUDGET: break
				var at := Vector2i(x, y)
				var kind := ctx.city.zone_kind_at(x, y)
				if not Zones.is_agricultural(kind) or touched.has(at): continue
				var old: Dictionary = _lots.get(ctx.city.anchor_of(x, y), {})
				if not old.is_empty() and (old.anchor != at or old.rect.size.x >= 3 or old.failed_months > 0 or old.state == &"dormant"): continue
				var choices := Params.archetypes(kind == Zones.AGR_HIGH)
				# Random cyclic roster order makes each size and archetype reachable.
				var first := _rng.below(choices.size())
				for offset in choices.size():
					var archetype: StringName = choices[(first + offset) % choices.size()]
					var side: int = Params.ROSTER[archetype][0]
					var rect := Rect2i(at, Vector2i(side, side))
					if not _candidate(rect, kind, touched): continue
					attempts += 1
					for covered in _lots.keys():
						if rect.encloses(_lots[covered].rect): _lots.erase(covered)
					var lot := _record(at, archetype, &"prepared", kind)
					_lots[at] = lot
					_change(lot, &"prepared", month)
					dirty = _merge(dirty, rect)
					_touch(touched, rect)
					break
	# Whole-load skipping is non-monotonic: a rollback can make an earlier
	# consumer fit and displace another newly active farm. Re-project after
	# removals until retained activations are all served in that exact state.
	# Each failed pass removes at least one of at most DEVELOPMENT_BUDGET lots.
	for _validation in activated.size():
		var final_service := _project()
		var failed: Array[Vector2i] = []
		for at in activated:
			var lot: Dictionary = _lots[at]
			var id := Params.building_id(lot.archetype)
			if not _all_served(final_service, lot.rect, TileFlags.WATERED) or (Params.power_load(id) > 0 and not _all_served(final_service, lot.rect, TileFlags.POWERED)):
				failed.append(at)
		if failed.is_empty(): break
		for at in failed:
			var lot: Dictionary = _lots[at]
			_change(lot, activated[at].state, month)
			lot.failed_months = activated[at].failed_months
			activated.erase(at)
		if activated.is_empty(): break
	if dirty.has_area() and ctx.city.building.data != before_building:
		var power := ctx.system(&"power") as PowerSystem
		var water := ctx.system(&"water") as WaterSystem
		if power != null: power.reallocate_established(ctx, dirty)
		if water != null: water.reallocate_established(ctx, dirty)
		ctx.events.mark_dirty(dirty)
	_service_map = null
	_publish()

func _update_demand() -> void:
	var links := 0
	var neighbors := _ctx.system(&"neighbors")
	if neighbors != null and neighbors.has_method("link_count"): links = int(neighbors.call("link_count"))
	@warning_ignore("integer_division")
	var target := clampi(Params.TARGET_BASE_JOBS + _ctx.stats.population / Params.RESIDENTS_PER_TARGET_JOB + links * Params.TARGET_JOBS_PER_CITY_LINK, Params.TARGET_BASE_JOBS, Params.TARGET_JOBS_LIMIT)
	var change := clampi((target - _jobs()) * Params.DEMAND_GAIN, -Params.DEMAND_MONTHLY_LIMIT, Params.DEMAND_MONTHLY_LIMIT)
	change += ZoneParams.tax_pressure(clampi(_ctx.stats.tax_agricultural, Params.TAX_MIN, Params.TAX_MAX))
	_raw = clampi(_raw + change, -Params.DEMAND_RAW_LIMIT, Params.DEMAND_RAW_LIMIT)

func _publish() -> void:
	if _ctx == null: return
	@warning_ignore("integer_division")
	_ctx.stats.demand_agricultural = _raw * Params.DEMAND_DISPLAY_LIMIT / Params.DEMAND_RAW_LIMIT
	var previous_jobs := _ctx.stats.agricultural_jobs
	_ctx.stats.agricultural_jobs = _jobs()
	# Both replacement censuses publish the farm share already included in
	# stats.jobs. Replace only that share, preserving the latest nonfarm census
	# through growth, network notifications and saved-census restore ordering.
	_ctx.stats.jobs += _ctx.stats.agricultural_jobs - previous_jobs
	_ctx.stats.agricultural_lots = 0
	for lot: Dictionary in _lots.values():
		if lot.state == &"active": _ctx.stats.agricultural_lots += 1

func _record(at: Vector2i, archetype: StringName, state: StringName, kind: int) -> Dictionary:
	var id := Params.building_id(archetype)
	var size := Buildings.size(id)
	if state != &"active": id = Params.state_id(state, size.x)
	return {"anchor": at, "archetype": archetype, "state": state, "building_id": id,
		"zone_kind": kind, "rect": Rect2i(at, size), "failed_months": Params.FAILURE_MONTHS if state == &"dormant" else 0, "last_month": -1}

func _change(lot: Dictionary, state: StringName, month: int) -> void:
	lot.state = state
	lot.building_id = Params.building_id(lot.archetype) if state == &"active" else Params.state_id(state, lot.rect.size.x)
	lot.last_month = month
	if state != &"dormant": lot.failed_months = 0
	_ctx.city.stamp_building(lot.anchor.x, lot.anchor.y, lot.building_id, lot.zone_kind)
	_service_map = null

func _candidate(rect: Rect2i, kind: int, touched: Dictionary) -> bool:
	if _emergency(): return false
	if not _land_reason(rect, kind).is_empty() or not ZoneSystem.has_access(_ctx.city, rect): return false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var at := Vector2i(x, y)
			if touched.has(at): return false
			var id := _ctx.city.building_at(x, y)
			if Buildings.is_agricultural(id):
				var old: Dictionary = _lots.get(_ctx.city.anchor_of(x, y), {})
				if old.is_empty() or not rect.encloses(old.rect) or old.rect.size.x >= rect.size.x or old.failed_months > 0 or old.state == &"dormant": return false
			elif not Builder._clearable(id): return false
	return true

func _emergency() -> bool:
	var disasters := _ctx.system(&"disasters")
	return disasters != null and disasters.has_method("is_emergency") and bool(disasters.call("is_emergency"))

func _protected(rect: Rect2i) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if _ctx.city.flags.has_bits(x, y, TileFlags.LANDMARK): return true
	return false

func _land_reason(rect: Rect2i, kind: int) -> String:
	var city := _ctx.city
	var margin := Params.EDGE_MARGIN
	if not Rect2i(margin, margin, City.WIDTH - 2 * margin, City.HEIGHT - 2 * margin).encloses(rect): return "Too close to the city boundary."
	var height := city.ground_height(rect.position.x, rect.position.y)
	var disasters := _ctx.system(&"disasters")
	var fires: Array = disasters.call("fires") if disasters != null and disasters.has_method("fires") else []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if city.zone_kind_at(x, y) != kind: return "Requires a whole footprint of the same agricultural density."
			if not city.is_flat(x, y) or city.ground_height(x, y) != height: return "Requires flat, level ground."
			if city.is_water(x, y) or city.flood_overlay.has(Vector2i(x, y)): return "Requires dry ground."
			if city.flags.has_bits(x, y, TileFlags.LANDMARK): return "Protected land."
			if city.building_at(x, y) == Buildings.id_of(&"contamination"): return "Contaminated ground."
			if Vector2i(x, y) in fires: return "Active fire."
	return ""

## Detached city AND detached utility instances: preview cannot alter real caches,
## events, facilities, storage, statistics, source generation or either RNG.
func _project(lot: Dictionary = {}) -> City:
	_projection_count += 1
	var city := _ctx.city.duplicate_city()
	city.imported_power_links = _ctx.city.imported_power_links.duplicate()
	if not lot.is_empty(): city.stamp_building(lot.anchor.x, lot.anchor.y, Params.building_id(lot.archetype), lot.zone_kind)
	var ctx := SimContext.new()
	ctx.city = city
	ctx.stats = CityStats.new()
	ctx.events = CityEvents.new()
	var power := _ctx.system(&"power") as PowerSystem
	var water := _ctx.system(&"water") as WaterSystem
	var full := Rect2i(0, 0, City.WIDTH, City.HEIGHT)
	if power != null:
		var detached := PowerSystem.new()
		detached.copy_supply_policy(power)
		detached.reallocate_established(ctx, full)
	if water != null:
		var detached := WaterSystem.new()
		detached.reallocate_established(ctx, full)
	else:
		for i in city.flags.data.size(): city.flags.data[i] &= ~TileFlags.WATERED
	return city

func _service(lot: Dictionary) -> Dictionary:
	var id := Params.building_id(lot.archetype)
	var rect: Rect2i = lot.rect
	var water_load := Params.water_load(id)
	var power_load := Params.power_load(id)
	var reason := _land_reason(rect, lot.zone_kind)
	if reason.is_empty() and lot.state != &"active" and _emergency(): reason = "Development waits until the emergency ends."
	if reason.is_empty() and not ZoneSystem.has_access(_ctx.city, rect): reason = "Needs road or station access within three tiles."
	var supplied_city: City
	if lot.state == &"active":
		if _service_map == null: _service_map = _project()
		supplied_city = _service_map
	elif reason.is_empty():
		supplied_city = _project(lot)
	var watered := water_load == 0
	var powered := power_load == 0
	if supplied_city != null:
		watered = water_load == 0 or _all_served(supplied_city, rect, TileFlags.WATERED)
		powered = power_load == 0 or (_ctx.system(&"power") != null and _all_served(supplied_city, rect, TileFlags.POWERED))
	if reason.is_empty() and not watered: reason = "Needs water for the whole footprint."
	if reason.is_empty() and not powered: reason = "Needs power for the whole footprint."
	return {"water_required": water_load * rect.get_area(), "water_supplied": watered,
		"power_required": power_load * rect.get_area(), "power_supplied": powered, "blocked_reason": reason}

static func _all_served(city: City, rect: Rect2i, flag: int) -> bool:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not city.flags.has_bits(x, y, flag): return false
	return true

static func _merge(a: Rect2i, b: Rect2i) -> Rect2i:
	return a.merge(b) if a.has_area() else b

static func _touch(touched: Dictionary, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x): touched[Vector2i(x, y)] = true

## Validate current footprints before every census/query/mutation. No layer writes.
func _reconcile() -> void:
	if _ctx == null: return
	var city := _ctx.city
	var valid := {}
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var id := city.building_at(x, y)
			if not Buildings.is_agricultural(id): continue
			var kind := city.zone_kind_at(x, y)
			if not Zones.is_agricultural(kind): continue
			var at := Vector2i(x, y)
			var size := Buildings.size(id)
			if city.anchor_of(x, y) != at or x + size.x > City.WIDTH or y + size.y > City.HEIGHT: continue
			if size.x == 1:
				if Zones.corners(city.zone.at(x, y)) != Zones.ALL_CORNERS: continue
			elif not City._is_footprint(city.building.data, city.zone.data, x, y, id, size): continue
			var intact := true
			for dy in size.y:
				for dx in size.x:
					if city.zone_kind_at(x + dx, y + dy) != kind: intact = false
			if not intact: continue
			var state := &"active"
			var archetype := Params.archetype_for_id(id)
			if archetype == &"":
				state = &"prepared" if id == Params.state_id(&"prepared", size.x) else &"dormant"
				var old: Dictionary = _lots.get(at, {})
				if old.get("building_id", -1) == id and old.get("zone_kind", -1) == kind:
					archetype = old.get("archetype", &"")
				if not Params.archetypes(kind == Zones.AGR_HIGH).has(archetype) or int(Params.ROSTER.get(archetype, [0])[0]) != size.x:
					archetype = &""
					for candidate in Params.archetypes(kind == Zones.AGR_HIGH):
						if int(Params.ROSTER[candidate][0]) == size.x:
							archetype = candidate
							break
			if archetype == &"" or not Params.archetypes(kind == Zones.AGR_HIGH).has(archetype): continue
			var lot := _record(at, archetype, state, kind)
			var old: Dictionary = _lots.get(at, {})
			if old.get("building_id", -1) == id and old.get("zone_kind", -1) == kind and old.get("archetype", &"") == archetype:
				lot.failed_months = clampi(int(old.get("failed_months", 0)), 0, Params.FAILURE_MONTHS)
				lot.last_month = int(old.get("last_month", -1))
			valid[at] = lot
	_lots = valid

func save() -> Dictionary:
	_reconcile()
	var records: Array = []
	for lot: Dictionary in _lots.values():
		records.append({"x": lot.anchor.x, "y": lot.anchor.y, "archetype": String(lot.archetype),
			"state": String(lot.state), "building_id": lot.building_id, "zone_kind": lot.zone_kind,
			"failed_months": lot.failed_months, "last_month": lot.last_month})
	return {"raw_demand": _raw, "rng_seed": str(_rng.seed_value()), "rng_state": str(_rng.state()),
		"demand_month": _demand_month, "phase_months": _phase_months.duplicate(), "lots": records}

func load(data: Dictionary) -> void:
	_lots.clear()
	var seed_value := (_ctx.rng.seed_value() ^ SEED_SALT) if _ctx != null else 0
	_rng = SimRng.from_saved_seed(_saved_int(data.get("rng_seed"), seed_value))
	_rng.set_state(_saved_int(data.get("rng_state"), _rng.state()))
	_raw = clampi(_saved_int(data.get("raw_demand"), Params.DEMAND_INITIAL), -Params.DEMAND_RAW_LIMIT, Params.DEMAND_RAW_LIMIT)
	_demand_month = _saved_int(data.get("demand_month"), -1)
	_phase_months = [-1, -1]
	var phases: Variant = data.get("phase_months", [])
	if phases is Array and phases.size() == 2:
		for i in 2: _phase_months[i] = _saved_int(phases[i], -1)
	var records: Variant = data.get("lots", [])
	if records is Array:
		for value: Variant in records:
			if not value is Dictionary: continue
			var at := Vector2i(_saved_int(value.get("x"), -1), _saved_int(value.get("y"), -1))
			if not Rect2i(0, 0, City.WIDTH, City.HEIGHT).has_point(at): continue
			if not value.get("archetype") is String or not value.get("state") is String: continue
			var archetype := StringName(value.archetype)
			var state := StringName(value.state)
			var kind := _saved_int(value.get("zone_kind"), -1)
			if state not in [&"prepared", &"active", &"dormant"] or not Params.archetypes(kind == Zones.AGR_HIGH).has(archetype): continue
			var lot := _record(at, archetype, state, kind)
			if _saved_int(value.get("building_id"), -1) != lot.building_id: continue
			lot.failed_months = clampi(_saved_int(value.get("failed_months"), 0), 0, Params.FAILURE_MONTHS)
			lot.last_month = _saved_int(value.get("last_month"), -1)
			_lots[at] = lot
	_service_map = null
	_reconcile()
	_publish()

static func _saved_int(value: Variant, fallback: int) -> int:
	if value is int: return value
	if value is float and is_finite(value) and value == floor(value): return int(value)
	if value is String and value.is_valid_int(): return int(value)
	return fallback
