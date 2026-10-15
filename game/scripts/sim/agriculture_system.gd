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
## Reserve the complete phase before any mutation at the signed save boundary.
## At most two lifecycle writes per owner/member (aging then dormancy),
## two writes per development
## action (recovery then activation), and one repair plus one adoption apply.
const MONTHLY_STORE_REVISION_HEADROOM := 2 * AgriculturalParcels.CELL_COUNT + 2 * DEVELOPMENT_BUDGET + 2
## A retained record may be repaired, age, recover acreage and activate.
const MONTHLY_RECORD_REVISION_HEADROOM := 4
var _ctx: SimContext
var _rng := SimRng.from_saved_seed(0)
var _raw := Params.DEMAND_INITIAL
var _lots: Dictionary = {}
var _demand_month := -1
var _phase_months: Array[int] = [-1, -1]
var _service_map: City
var _projection_count := 0
var _migration_error: Error = OK
var _repair_error := ""
var _counts := {"actions":0,"evaluations":0,"admissions":0,"eligible_cells":0}

func work_counts() -> Dictionary:
	return _counts.duplicate()

func parcel_jobs() -> Dictionary:
	return AgriculturalParcelCapacity.allocate(current_parcels()).by_id

func _init() -> void:
	key = &"agriculture"

func setup(ctx: SimContext) -> void:
	_migration_error = OK
	_repair_error = ""
	_ctx = ctx
	_rng = SimRng.from_saved_seed(ctx.rng.seed_value() ^ SEED_SALT)
	_reconcile()
	_publish()

func setup_from_save(ctx: SimContext, data: Dictionary) -> void:
	_ctx = ctx
	self.load(data)

func networks_changed(ctx: SimContext, _rect: Rect2i) -> void:
	_ctx = ctx
	_service_map = null
	if _reconcile() == OK: _publish()

## Mutation adapter: topology and all lifecycle state publish together, after
## detached service validation. No live utility rerolls or getters repair maps.
func repair_parcels(cells: PackedInt32Array) -> Dictionary:
	if _ctx == null: return {"ok":false,"error":"Agriculture is not initialized."}
	if _migration_error != OK: return {"ok":false,"error":_repair_error if not _repair_error.is_empty() else "Agriculture recovery is blocked."}
	var change := _ctx.city.agricultural_parcels.repair_changed_cells(_ctx.city,cells,_cut_services)
	if not change.get("ok",false):
		_repair_error = String(change.get("error","Parcel repair failed."))
		_migration_error = ERR_INVALID_DATA
		return change
	var dirty := AgriculturalParcels.change_bounds(change,_ctx.city.agricultural_parcels)
	if dirty.has_area():
		_service_map = null
		_ctx.events.mark_dirty(dirty)
	return change


func _cut_services(candidate: City, eligible: Array[int]) -> Array:
	var ctx := SimContext.new()
	ctx.city = candidate
	ctx.systems = _ctx.systems.duplicate()
	var retained: Array = eligible.duplicate()
	# Every pass drops an unserved candidate. Bound this edit work to two
	# projections; unstable allocation falls back to preparation, never healing.
	for attempt in 2:
		var supplied := AgriculturalParcelService.project(ctx)
		var failed: Array = []
		for id: int in retained:
			var r := candidate.agricultural_parcels.record(id)
			if not AgriculturalParcelService.summary(ctx,r,supplied).blocked_reason.is_empty(): failed.append(id)
		if failed.is_empty(): return retained
		for id: int in failed:
			retained.erase(id)
			var r := candidate.agricultural_parcels.record(id)
			r.state = &"prepared"
			if candidate.agricultural_parcels.put(candidate,r) != OK: return []
		if retained.is_empty(): return []
	return []

## A failed migration is terminal until an explicit setup/load retries it.
## No secondary low-lot authority or monthly advancement is allowed meanwhile.
func migration_error() -> Error:
	return _migration_error

## A raw edit cannot be undone here. Expose the reason and use the existing
## failed-recovery/save guard until explicit setup/load retries recovery.
func repair_error() -> String:
	return _repair_error

## Native save/load preflight shares the real recovery path on detached data.
## Empty system registry avoids host/cache references, and saved-seed creation
## does not consume the city's or the global RNG.
static func validate_legacy_migration(city: City, data: Dictionary) -> Error:
	var ctx := SimContext.new()
	ctx.city = city.duplicate_city()
	ctx.rng = SimRng.from_saved_seed(0)
	ctx.stats = CityStats.new()
	var system := AgricultureSystem.new()
	system._ctx = ctx
	system._restore(data)
	return system.migration_error()

func raw_demand() -> int:
	return _raw

func projection_count() -> int:
	return _projection_count

func jobs() -> int:
	_reconcile(false)
	return _jobs()

func _jobs() -> int:
	var total: int = AgriculturalParcelCapacity.allocate(current_parcels()).jobs
	for lot: Dictionary in _lots.values():
		if lot.state == &"active": total += Params.jobs_of(lot.building_id)
	return total

func assessed_value() -> int:
	return jobs() * Params.ASSESSMENT_PER_JOB

func current_lots() -> Array[Dictionary]:
	_reconcile(false)
	var result: Array[Dictionary] = []
	for lot: Dictionary in _lots.values():
		var view := lot.duplicate(true)
		var members := PackedInt32Array()
		for y in range(lot.rect.position.y,lot.rect.end.y):
			for x in range(lot.rect.position.x,lot.rect.end.x): members.append(y*City.WIDTH+x)
		view.merge({"source_key":StringName("legacy:%d:%d" % [lot.anchor.x,lot.anchor.y]),
			"parcel_id":0,"members":members,"mode":&"legacy","origin":lot.anchor,"revision":0})
		result.append(view)
	for r in current_parcels(): result.append(_parcel_lot(r))
	return result

func current_parcels() -> Array[Dictionary]:
	return _ctx.city.agricultural_parcels.records() if _ctx != null else []

func _parcel_lot(r: Dictionary) -> Dictionary:
	var rect := AgriculturalParcels.bounds(r.members)
	return {"parcel_id":r.id,"anchor":rect.position,"archetype":r.archetype,"state":r.state,
		"building_id":AgriculturalParcels._code(r),"zone_kind":Zones.AGR_LOW,"rect":rect,
		"failed_months":r.failed_months,"last_month":r.last_month,"mode":r.mode,"phase":r.phase,
		"source_key":StringName("parcel:%d" % r.id),"members":r.members.duplicate(),
		"origin":AgriculturalParcels.tile(r.origin_index),"revision":r.revision}

func _persist_lot(lot: Dictionary) -> Error:
	if not lot.has("parcel_id"): return OK
	var r := _ctx.city.agricultural_parcels.record(lot.parcel_id)
	if r.is_empty(): return OK
	if r.state == lot.state and r.failed_months == lot.failed_months and r.last_month == lot.last_month: return OK
	r.state = lot.state
	if r.mode == &"legacy": r.legacy_code = lot.building_id
	r.failed_months = lot.failed_months
	r.last_month = lot.last_month
	var error := _ctx.city.agricultural_parcels.put(_ctx.city,r)
	if error != OK:
		_migration_error = error
		_repair_error = "Canonical parcel lifecycle update failed."
	return error

func inspect_tile(tile: Vector2i) -> Dictionary:
	if _ctx == null or not _ctx.city.in_bounds(tile.x, tile.y): return {}
	_reconcile(false)
	var city := _ctx.city
	var kind := city.zone_kind_at(tile.x, tile.y)
	if not Zones.is_agricultural(kind): return {}
	var anchor := city.anchor_of(tile.x, tile.y)
	var owned := city.agricultural_parcels.record(city.agricultural_parcels.id_at(tile))
	if not _lots.has(anchor) and owned.is_empty():
		var rect := Rect2i(tile, Vector2i.ONE)
		var reason := _land_reason(rect, kind)
		if reason.is_empty() and not ZoneSystem.has_access(city, rect): reason = "Needs road or station access within three tiles."
		if reason.is_empty() and _emergency(): reason = "Development waits until the emergency ends."
		if reason.is_empty(): reason = "Waiting for positive agricultural demand." if _raw <= 0 else "Waiting for monthly preparation."
		return {"anchor": tile, "archetype": &"", "state": &"zoned", "building_id": city.building_at(tile.x, tile.y),
			"rect": rect, "parcel_id": 0, "members_count": 0, "mode": &"zoned", "failed_months": 0,
			"blocked_reason": reason, "jobs": 0, "assigned_jobs": 0, "stock_count": 0,
			"water_required": 0, "water_supplied": false, "power_required": 0, "power_supplied": true}
	var lot: Dictionary = _parcel_lot(owned) if not owned.is_empty() else _lots[anchor].duplicate(true)
	_service_map = null
	var service := _service(lot)
	lot.merge(service, true)
	if not owned.is_empty() and owned.state != &"active" and owned.archetype in [&"cattle_range", &"sheep_pasture"]:
		var layout := AgriculturalParcelGeometry.plan(owned)
		if not layout.ok: lot.blocked_reason = layout.error
	if lot.blocked_reason.is_empty() and (_raw < 0 or (_raw == 0 and lot.state != &"active")):
		lot.blocked_reason = "Waiting for positive agricultural demand."
	lot["jobs"] = parcel_jobs().get(lot.parcel_id,0) if lot.has("parcel_id") else (Params.jobs_of(lot.building_id) if lot.state == &"active" else 0)
	lot["parcel_id"] = int(lot.get("parcel_id",0))
	lot["mode"] = lot.get("mode",&"legacy")
	lot["assigned_jobs"] = lot.jobs
	lot["members_count"] = owned.members.size() if not owned.is_empty() else lot.rect.get_area()
	lot["stock_count"] = 0
	if lot.state == &"active" and lot.archetype in [&"cattle_range", &"sheep_pasture", &"dairy", &"feedlot"]:
		if not owned.is_empty():
			lot["stock_count"] = AgriculturalParcelGeometry.max_safe_stock(owned,AgriculturalParcelGeometry.plan(owned))
		else:
			lot["stock_count"] = int(Params.ROSTER[lot.archetype][4])
	return lot

func monthly(ctx: SimContext, phase: int = 0) -> void:
	if phase < 0 or phase > 1: return
	_ctx = ctx
	@warning_ignore("integer_division")
	var month := ctx.clock.day / GameClock.DAYS_PER_MONTH
	if _migration_error != OK or not _monthly_revision_capacity(): return
	if _reconcile() != OK: return
	if _phase_months[phase] == month: return
	if _demand_month != month:
		_update_demand()
		_demand_month = month
	_phase_months[phase] = month
	_projection_count = 0
	_counts = {"actions":0,"evaluations":0,"admissions":0,"eligible_cells":0}
	_service_map = null
	var grow := AgriculturalParcelGrowth.new()
	var disasters := ctx.system(&"disasters")
	var fires: Array = disasters.call("fires") if disasters != null and disasters.has_method("fires") else []
	grow.prepare(ctx.city,fires)
	_counts.eligible_cells = grow.eligible_cells
	var x0 := 0 if phase == 0 else City.HALF
	var x1 := City.HALF if phase == 0 else City.WIDTH
	var touched := {}
	var dirty := Rect2i()
	var before_building := ctx.city.building.data.duplicate()
	var waiting: Array[Dictionary] = []
	var extending: Array[Dictionary] = []
	var declining: Array[Dictionary] = []
	var proposals: Array[Dictionary] = []
	var lifecycle: Array[Dictionary] = []
	for lot: Dictionary in _lots.values(): lifecycle.append(lot)
	for r in current_parcels(): lifecycle.append(_parcel_lot(r))
	# Evaluate every existing active load against a single unchanged allocation.
	for lot in lifecycle:
		var lot_phase: int = lot.get("phase",0 if lot.anchor.x < City.HALF else 1)
		if lot_phase != phase or lot.last_month == month: continue
		if lot.has("members"):
			var protected := false
			for i in lot.members:
				if (ctx.city.flags.data[i] & TileFlags.LANDMARK) != 0: protected = true;break
			if protected: continue
		elif _protected(lot.rect): continue
		lot.last_month = month
		if lot.state != &"active":
			waiting.append(lot)
		else:
			var service := _service(lot)
			lot.failed_months = 0 if service.blocked_reason.is_empty() and _raw >= 0 else mini(Params.FAILURE_MONTHS,int(lot.failed_months)+1)
			if lot.failed_months >= Params.FAILURE_MONTHS: declining.append(lot)
			elif lot.get("mode",&"legacy") != &"legacy" and lot.failed_months == 0:
				extending.append(lot)
		if _persist_lot(lot) != OK: return
	for lot in declining:
		if _change(lot,&"dormant",month) != OK: return
		dirty = _merge(dirty,lot.rect)
		_touch(touched,lot.rect)
	# Reserve one action for formation and, when present, one for extensions.
	# Failed waiting service checks must not monopolize the shared phase budget.
	if _raw > 0 and not _emergency():
		var waiting_budget := DEVELOPMENT_BUDGET - (2 if not extending.is_empty() else 1)
		var first := (month*waiting_budget)%waiting.size() if not waiting.is_empty() else 0
		for offset in mini(waiting.size(),waiting_budget):
			var lot: Dictionary = waiting[(first+offset)%waiting.size()]
			_counts.actions += 1
			var value := _activation(lot)
			if value.is_empty() and lot.get("mode",&"legacy") != &"legacy":
				var remnant := ctx.city.agricultural_parcels.record(lot.parcel_id)
				if AgriculturalParcelService.land_reason(ctx.city,remnant).is_empty() and AgriculturalParcelService.has_access(ctx.city,remnant.members):
					var recovery := grow.extension(ctx.city,remnant,_rng)
					_count_shape(recovery)
					if recovery.ok and ctx.city.agricultural_parcels.put(ctx.city,recovery.record) == OK:
						# Recovery may need several passes. Waiting acreage retains
						# its state/history/tokens; only a safe supplied final plan
						# enters the existing joint active-allocation transaction.
						grow.reserve(recovery.record.members)
						dirty = _merge(dirty,AgriculturalParcels.bounds(recovery.record.members))
						value = _activation(_parcel_lot(recovery.record))
			if value.is_empty(): continue
			var trial := proposals.duplicate()
			trial.append(value)
			var projected := _project_values(trial)
			if _proposal_served(value,projected): proposals.append(value)
		for offset in extending.size():
			if _counts.actions >= DEVELOPMENT_BUDGET - 1: break
			# The saved month rotates first choice without drawing shared RNG.
			var lot: Dictionary = extending[(month+offset)%extending.size()]
			var current := ctx.city.agricultural_parcels.record(lot.parcel_id)
			if current.members.size() >= current.target_area: continue
			_counts.actions += 1
			var extended := grow.extension(ctx.city,current,_rng)
			_count_shape(extended)
			if not extended.ok: continue
			var trial := proposals.duplicate()
			trial.append(extended.record)
			if _proposal_served(extended.record,_project_values(trial)): proposals.append(extended.record)
	# Reserve proposed extension members without publishing their occupancy.
	for value in proposals:
		if value.has("members"): grow.reserve(value.members)
		else: _touch(touched,value.rect)
	# New preparation needs access but may precede water/power availability.
	if _raw > 0 and not _emergency():
		# Alternate density priority so a low-density scan cannot consume the
		# last preparation action every month ahead of high-density land.
		var kinds := [Zones.AGR_LOW,Zones.AGR_HIGH] if month%2 == 0 else [Zones.AGR_HIGH,Zones.AGR_LOW]
		for preferred_kind in kinds:
			for y in range(Params.EDGE_MARGIN,City.HEIGHT-Params.EDGE_MARGIN):
				if _counts.actions >= DEVELOPMENT_BUDGET: break
				for x in range(maxi(x0,Params.EDGE_MARGIN),mini(x1,City.WIDTH-Params.EDGE_MARGIN)):
					if _counts.actions >= DEVELOPMENT_BUDGET: break
					var at := Vector2i(x,y)
					var kind := ctx.city.zone_kind_at(x,y)
					if kind != preferred_kind: continue
					if kind == Zones.AGR_LOW:
						if not grow.eligible(at): continue
						if not AgriculturalParcelService.has_access(ctx.city,PackedInt32Array([y*128+x])): continue
						_counts.actions += 1
						var archetype: StringName = Params.LOW_ARCHETYPES[_rng.below(Params.LOW_ARCHETYPES.size())]
						var shape := grow.candidate(ctx.city,at,archetype,0,_rng)
						_count_shape(shape)
						if not shape.ok: continue
						var parcel := _new_parcel(shape,archetype,at,month)
						if parcel.is_empty(): continue
						if ctx.city.agricultural_parcels.put(ctx.city,parcel) == OK:
							dirty = _merge(dirty,AgriculturalParcels.bounds(parcel.members))
						continue
					if kind != Zones.AGR_HIGH or touched.has(at): continue
					var old: Dictionary = _lots.get(ctx.city.anchor_of(x,y),{})
					if not old.is_empty() and (old.anchor != at or old.rect.size.x >= 3 or old.failed_months > 0 or old.state == &"dormant"): continue
					var choices := Params.archetypes(true)
					var first := _rng.below(choices.size())
					for offset in choices.size():
						var archetype: StringName = choices[(first+offset)%choices.size()]
						var side: int = Params.ROSTER[archetype][0]
						var rect := Rect2i(at,Vector2i(side,side))
						if not _candidate(rect,kind,touched): continue
						_counts.actions += 1
						for covered in _lots.keys():
							if rect.encloses(_lots[covered].rect): _lots.erase(covered)
						var lot := _record(at,archetype,&"prepared",kind)
						_lots[at] = lot
						if _change(lot,&"prepared",month) != OK: return
						dirty = _merge(dirty,rect)
						_touch(touched,rect)
						break
	# Validate the complete proposed allocation before publishing any acreage.
	# Removing a proposal can displace another consumer; every failed pass drops
	# at least one of the sixteen candidates. Original active farms stay intact.
	for _validation in proposals.size():
		var final_service := _project_values(proposals)
		var failed: Array[int] = []
		for i in proposals.size():
			if not _proposal_served(proposals[i],final_service): failed.append(i)
		if failed.is_empty(): break
		failed.reverse()
		for i in failed: proposals.remove_at(i)
		if proposals.is_empty(): break
	for value in proposals:
		if value.has("members"):
			if ctx.city.agricultural_parcels.put(ctx.city,value) != OK: continue
			dirty = _merge(dirty,AgriculturalParcels.bounds(value.members))
		else:
			if _change(value,&"active",month) != OK: return
			_touch(touched,value.rect)
			dirty = _merge(dirty,value.rect)
	if dirty.has_area() and ctx.city.building.data != before_building:
		var power := ctx.system(&"power") as PowerSystem
		var water := ctx.system(&"water") as WaterSystem
		if power != null: power.reallocate_established(ctx,dirty)
		if water != null: water.reallocate_established(ctx,dirty)
		ctx.events.mark_dirty(dirty)
	_service_map = null
	_reconcile()
	_publish()

## Near the representable limit, refuse conservatively rather than publish a
## partial phase. The final reserved counters may remain unused; save domains
## and ordinary growth rules do not change. Empty nonfarm cities need no writes.
func _monthly_revision_capacity() -> bool:
	var store := _ctx.city.agricultural_parcels
	var records := store.records()
	var exhausted := false
	for record in records:
		if record.revision > AgriculturalParcels.MAX_ID - MONTHLY_RECORD_REVISION_HEADROOM:
			exhausted = true
			break
	if not exhausted and store.revision > AgriculturalParcels.MAX_ID - MONTHLY_STORE_REVISION_HEADROOM:
		exhausted = not records.is_empty()
		if not exhausted:
			for zone: int in _ctx.city.zone.data:
				if Zones.kind(zone) == Zones.AGR_LOW:
					exhausted = true
					break
	if exhausted:
		_migration_error = ERR_OUT_OF_MEMORY
		_repair_error = "Agricultural lifecycle revision capacity exhausted."
	return not exhausted


func _count_shape(shape: Dictionary) -> void:
	_counts.evaluations += shape.evaluations
	_counts.admissions += shape.admissions

func _new_parcel(shape: Dictionary, archetype: StringName, at: Vector2i, month: int) -> Dictionary:
	var id := _ctx.city.agricultural_parcels.available_id()
	if id == 0: return {}
	var first := AgriculturalParcels.cell(at)
	var value := {"id":id,"members":shape.members,"identity_index":first,"origin_index":first,
		"phase":0 if at.x < City.HALF else 1,"archetype":archetype,"state":&"prepared",
		"mode":shape.mode,"legacy_code":Params.building_id(archetype) if shape.mode == &"square" else 0,
		"layout_seed":_rng.state(),"target_area":shape.target_area,"height":_ctx.city.ground_height(at.x,at.y),
		"modules":[],"stock_units":AgriculturalParcelParams.stock_units(archetype,shape.members),
		"failed_months":0,"last_month":month,"revision":1}
	var layout := AgriculturalParcelGeometry.plan(value)
	if not layout.ok: return {}
	value.modules = layout.modules
	return value

func _activation(lot: Dictionary) -> Dictionary:
	if not lot.has("parcel_id"):
		if not _land_reason(lot.rect,lot.zone_kind).is_empty() or not ZoneSystem.has_access(_ctx.city,lot.rect): return {}
		return lot
	var r := _ctx.city.agricultural_parcels.record(lot.parcel_id)
	if not AgriculturalParcelService.land_reason(_ctx.city,r).is_empty() or not AgriculturalParcelService.has_access(_ctx.city,r.members): return {}
	var layout := AgriculturalParcelGeometry.plan(r,r.modules)
	if not layout.ok: return {}
	r.modules = layout.modules
	r.state = &"active"
	r.failed_months = 0
	if r.mode == &"legacy": r.legacy_code = Params.building_id(r.archetype)
	return r

func _proposal_served(value: Dictionary, supplied: City) -> bool:
	if supplied == null: return false
	if value.has("members"):
		return AgriculturalParcelService.summary(_ctx,value,supplied).blocked_reason.is_empty()
	var id := Params.building_id(value.archetype)
	return _all_served(supplied,value.rect,TileFlags.WATERED) and (Params.power_load(id) == 0 or (_ctx.system(&"power") != null and _all_served(supplied,value.rect,TileFlags.POWERED)))

func _project_values(values: Array[Dictionary]) -> City:
	_projection_count += 1
	# Keep logical attempts bounded and the empty active-census City cacheable.
	# Every agricultural activation draws water; without any possible existing
	# source, full detached allocation cannot change its rejection.
	if not values.is_empty() and not AgriculturalParcelService.has_established_water_source(_ctx): return null
	return AgriculturalParcelService.project(_ctx,{},values)

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
	if _ctx == null or _migration_error != OK: return
	@warning_ignore("integer_division")
	_ctx.stats.demand_agricultural = _raw * Params.DEMAND_DISPLAY_LIMIT / Params.DEMAND_RAW_LIMIT
	var previous_jobs := _ctx.stats.agricultural_jobs
	_ctx.stats.agricultural_jobs = _jobs()
	# Both replacement censuses publish the farm share already included in
	# stats.jobs. Replace only that share, preserving the latest nonfarm census
	# through growth, network notifications and saved-census restore ordering.
	_ctx.stats.jobs += _ctx.stats.agricultural_jobs - previous_jobs
	_ctx.stats.agricultural_lots = AgriculturalParcelCapacity.allocate(current_parcels()).active_count
	for lot: Dictionary in _lots.values():
		if lot.state == &"active": _ctx.stats.agricultural_lots += 1

func _record(at: Vector2i, archetype: StringName, state: StringName, kind: int) -> Dictionary:
	var id := Params.building_id(archetype)
	var size := Buildings.size(id)
	if state != &"active": id = Params.state_id(state, size.x)
	return {"anchor": at, "archetype": archetype, "state": state, "building_id": id,
		"zone_kind": kind, "rect": Rect2i(at, size), "failed_months": Params.FAILURE_MONTHS if state == &"dormant" else 0, "last_month": -1}

func _change(lot: Dictionary, state: StringName, month: int) -> Error:
	lot.state = state
	lot.building_id = Params.building_id(lot.archetype) if state == &"active" else Params.state_id(state, lot.rect.size.x)
	lot.last_month = month
	if state != &"dormant": lot.failed_months = 0
	if lot.has("parcel_id"):
		var error := _persist_lot(lot)
		if error != OK: return error
	else:
		_ctx.city.stamp_building(lot.anchor.x, lot.anchor.y, lot.building_id, lot.zone_kind)
	_service_map = null
	return OK

func _candidate(rect: Rect2i, kind: int, touched: Dictionary) -> bool:
	if _emergency(): return false
	if not _land_reason(rect, kind).is_empty() or not ZoneSystem.has_access(_ctx.city, rect): return false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var at := Vector2i(x, y)
			if touched.has(at) or _ctx.city.agricultural_parcels.id_at(at) != 0: return false
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
	return AgriculturalParcelService.project(_ctx,lot)

func _service(lot: Dictionary) -> Dictionary:
	if lot.has("parcel_id"):
		var r := _ctx.city.agricultural_parcels.record(lot.parcel_id)
		var supplied: City
		if r.state == &"active":
			if _service_map == null: _service_map = _project()
			supplied = _service_map
		else:
			var active := _activation(lot)
			if not active.is_empty(): supplied = _project(active)
		return AgriculturalParcelService.summary(_ctx,r,supplied)
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

## Read-only census rebuilds adapters; mutation hooks first repair ownership.
func _reconcile(mutate: bool = true) -> Error:
	if _migration_error != OK: return _migration_error
	if _ctx == null: return OK
	var city := _ctx.city
	if mutate:
		if not repair_parcels(PackedInt32Array()).get("ok",false): return _migration_error
	var valid := {}
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var id := city.building_at(x, y)
			if not Buildings.is_agricultural(id) or id >= AgriculturalParcelParams.ACTIVE_CODES[&"vegetables"] or city.agricultural_parcels.id_at(Vector2i(x,y)) != 0: continue
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
	var low: Array[Dictionary] = []
	for at in valid:
		if valid[at].zone_kind == Zones.AGR_LOW: low.append(valid[at])
	if mutate: _migration_error = city.agricultural_parcels.adopt_legacy(city,low)
	# Failed adoption is explicit; low records never become a second authority.
	for lot in low: valid.erase(lot.anchor)
	_lots = valid
	return _migration_error

func save() -> Dictionary:
	_reconcile(false)
	var records: Array = []
	for lot: Dictionary in _lots.values():
		records.append({"x": lot.anchor.x, "y": lot.anchor.y, "archetype": String(lot.archetype),
			"state": String(lot.state), "building_id": lot.building_id, "zone_kind": lot.zone_kind,
			"failed_months": lot.failed_months, "last_month": lot.last_month})
	var ids: Array[int] = []
	for r in current_parcels(): ids.append(r.id)
	var snapshot := {"schema":2,"parcel_ids":ids,"raw_demand": _raw, "rng_seed": str(_rng.seed_value()), "rng_state": str(_rng.state()),
		"demand_month": _demand_month, "phase_months": _phase_months.duplicate(), "lots": records}
	if _migration_error != OK: snapshot["migration_error"] = _migration_error
	return snapshot

func load(data: Dictionary) -> void:
	_restore(data)
	_publish()

func _restore(data: Dictionary) -> void:
	_migration_error = OK
	_repair_error = ""
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

static func _saved_int(value: Variant, fallback: int) -> int:
	if value is int: return value
	if value is float and is_finite(value) and value == floor(value) and absf(value) <= 9007199254740991.0: return int(value)
	if value is String:
		var parsed := AgriculturalParcels._seed(value)
		if parsed.ok: return parsed.value
	return fallback
