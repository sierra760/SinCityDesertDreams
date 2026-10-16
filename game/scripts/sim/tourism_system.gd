# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Concurrent guests/day visitors and completed monthly visitor business.
## CityStats is a derived publication; only this state owns attendance.
class_name TourismSystem
extends SimSystem

signal attendance_changed(anchors: Array[Vector2i])

const SCHEMA := 3
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
var _features := TourismEffects.neutral_features()
var _access := TourismAccess.new()
var _districts := TourismDistricts.new()
var _admission_busy := false
var _restoring_calendar := false
var _forecast_signature: Array = []
var _forecast_cache: Dictionary = {}
var _supported_cache: Dictionary = {}
var _forecast_computations := 0
var _forecast_hits := 0
var _calendar_supported_beds := 0
var _calendar_capacity_month := -1
var _calendar_probe_signature: Array = []
var _calendar_probe_budgets: Dictionary = {}

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
		activity = TourismMarkets.integer_activity(block.get("activity", {}))
		profile = activity_profile(block)
	var features := TourismEffects.decode_features(block, _month_id())
	if not features.ok: return ERR_INVALID_DATA
	_features = features.features
	_state = next_state
	_last_month = last
	_pending = pending.duplicate(true)
	_activity = activity
	_activity_profile = profile
	_loaded.clear()
	_state.reconcile(_ctx.city, true)
	# Pre-tourism saves have no feature block. Grant grace only when their
	# legacy occupancy actually became current guests, never to fresh cities.
	if block.is_empty() and migrate_population:
		for row in _state.records():
			if int(row.guests) > 0:
				_features.migration.grace_until_month = _month_id() + 1
				break
	if _features.staffing.is_empty():
		# Schema3 predecessor saves already have neutral staffing. Initialize once;
		# preserve an earlier absolute expiry even when it has already elapsed.
		if int(_features.migration.grace_until_month) == -1:
			for row in _state.records():
				if int(row.guests)+int(row.day_visitors) > 0:
					_features.migration.grace_until_month = _month_id()+1
					break
		_features.staffing = {"profile":"staffing_20261015","initialized_month":_month_id(),"month_id":_last_month,"resident_workers":0,"non_tourism_jobs":0,"incoming_allowance":0,"rows":[]}
	if _features.utilities.is_empty():
		# An absolute earlier migration expiry is authoritative. Utility activation
		# never extends a staffing predecessor's completed grace period.
		if int(_features.migration.grace_until_month)==-1 and block.get("features",{}).get("staffing",{}).is_empty():
			for row in _state.records():
				if int(row.guests)+int(row.day_visitors)>0:
					_features.migration.grace_until_month = _month_id()+1
					break
		_features.utilities = {"profile":"utility_20261015","activation_month":_month_id(),"month_id":_last_month,"rows":[]}
	if _features.calendar.is_empty(): _features.calendar = TourismCalendar.initial(_month_id(),_last_month)
	if migrate_population:
		_ctx.city.status = clampi(_ctx.city.status, 0, PopulationSystem.derived_status(_ctx.stats.population))
	_finished = true
	_restoring_calendar = true
	reconcile_now()
	_restoring_calendar = false
	return OK

## Shared with the save boundary: no money or state mutation while validating.
static func validate_period(block: Dictionary, month_id: int, budget: Dictionary = {}) -> Dictionary:
	if not TourismState._integer(block.get("schema"), 1, SCHEMA):
		return {"ok": false}
	if not TourismState._integer(block.get("last_month"), -1, month_id):
		return {"ok": false}
	if not TourismEffects.decode_features(block, month_id).ok:
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
	if profile not in [TourismParams.CURRENT_PROFILE, TourismParams.PREVIOUS_PROFILE, TourismMarkets.PROFILE]:
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
			if not TourismState._integer(pending.get(field), 0, TourismState.MAX_INSTANCE) or (profile != TourismMarkets.PROFILE and int(pending[field]) % 25 != 0):
				return {"ok": false}
		if int(pending.lodging_cents) != activity_check.lodging_cents or int(pending.gaming_cents) != activity_check.gaming_cents:
			return {"ok": false}
		if profile == TourismMarkets.PROFILE:
			if pending.get("profile") != profile: return {"ok":false}
			for field in ["lodging_numerator","gaming_numerator"]:
				if not TourismState._integer(pending.get(field),int(activity_check[field]),int(activity_check[field])): return {"ok":false}
		elif pending.has("profile") or pending.has("lodging_numerator") or pending.has("gaming_numerator"): return {"ok":false}
		var safety: Dictionary = block.get("features", {}).get("safety", {})
		var expected_cost := int(safety.get("cost_half_cents", 0))
		if not TourismState._integer(pending.get("program_half_cents", 0), expected_cost, expected_cost):
			return {"ok": false}
		if int(pending.month_id) <= int(booked):
			pending = {}
	var normalized: Dictionary = pending.duplicate(true)
	for field in ["month_id","lodging_cents","gaming_cents","lodging_numerator","gaming_numerator","program_half_cents"]:
		if normalized.has(field): normalized[field] = int(normalized[field])
	return {"ok": true, "pending": normalized}

## Schema 1 predates capacity tuning; retained business may outlive every lot.
static func activity_profile(block: Dictionary) -> String:
	if block.get("schema") == 1:
		return TourismParams.PREVIOUS_PROFILE
	var profile: Variant = block.get("activity_profile", TourismParams.CURRENT_PROFILE)
	return profile if profile is String else ""

## Activity belongs to the completed venue instance, even after demolition.
## Rows encode identity plus exact half-guest-months and concurrent day visits.
static func validate_activity(activity: Variant, last_month: int, profile: String = TourismParams.CURRENT_PROFILE) -> Dictionary:
	var result := {"ok": false, "lodging_cents": 0, "gaming_cents": 0,"lodging_numerator":0,"gaming_numerator":0}
	if profile not in [TourismParams.CURRENT_PROFILE,TourismParams.PREVIOUS_PROFILE,TourismMarkets.PROFILE] or not activity is Dictionary:
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
		if profile == TourismMarkets.PROFILE:
			if not TourismMarkets.valid_segments(row.get("guest_half_segments"),int(row.guest_half_months)) or not TourismMarkets.valid_segments(row.get("day_segments"),int(row.day_visitors)): return result
			var bases := TourismMarkets.business(row.guest_half_segments,[0,0,0,0],row.day_segments,key)
			result.lodging_numerator += int(bases.lodging_numerator)
			result.gaming_numerator += int(bases.gaming_numerator)
			continue
		if row.has("guest_half_segments") or row.has("day_segments"): return result
		result.lodging_cents += int(row.guest_half_months) * TourismParams.LODGING_CENTS_PER_HALF_GUEST
		result.gaming_cents += int(row.guest_half_months) * TourismParams.GAMING_CENTS_PER_HALF_GUEST + int(row.day_visitors) * TourismParams.GAMING_CENTS_PER_VISITOR
	if profile == TourismMarkets.PROFILE:
		result.lodging_cents = int(result.lodging_numerator) / TourismMarkets.BUSINESS_DENOMINATOR
		result.gaming_cents = int(result.gaming_numerator) / TourismMarkets.BUSINESS_DENOMINATOR
	result.ok = true
	return result

func daily(_context: SimContext) -> void:
	reconcile_now()

func networks_changed(_context: SimContext, _rect: Rect2i) -> void:
	reconcile_now()

## Native layer comparisons cache venue discovery; per-day work visits venues
## and their footprints, never every city tile in a script loop or every frame.
func reconcile_now() -> void:
	if not _finished or _admission_busy:
		return
	_state.reconcile(_ctx.city)
	var rows := _environment_rows()
	for row in rows:
		if not row.operating:
			row.guests = 0
			row.day_visitors = 0
			row.guest_segments = [0,0,0,0]
			row.day_segments = [0,0,0,0]
			row.target_guests = 0
			row.target_day_visitors = 0
			row.arrivals = 0
			row.departures = 0
	_state.replace_records(rows)
	TourismEffects.prune(_features, _state.records())
	var live := {}
	for row in _state.records():
		if row.operating: live[int(row.instance)] = true
	_features.staffing.rows = _features.staffing.rows.filter(func(row: Dictionary) -> bool: return live.has(int(row.instance)))
	_publish()
	_refresh_calendar_capacity()
	if not _restoring_calendar:
		var cancelled := TourismCalendar.cancel(_month_id(),_calendar_inputs(),_features.calendar)
		_features.calendar = cancelled.state
		_calendar_news(cancelled.notices)

func monthly(_context: SimContext, _phase: int = 0) -> void:
	if not _finished or _admission_busy:
		return
	reconcile_now()
	var month := _month_id()
	if month <= _last_month or not _pending.is_empty():
		return
	var power := _ctx.system(&"power") as PowerSystem
	var water := _ctx.system(&"water") as WaterSystem
	var budgets := {}
	# Reuse the convention probe's unchanged pre-transaction budgets. Both
	# prospective work and closing attendance use these detached graphs; only
	# the final accepted overlay causes one established pass per utility.
	if power != null or water != null:
		var pb: Dictionary = _calendar_probe_budgets.get("power",{})
		var wb: Dictionary = _calendar_probe_budgets.get("water",{})
		if pb.is_empty(): pb=power.admission_budget(_ctx.city) if power!=null else UtilityParams.admission_budget(_ctx.city,false)
		if wb.is_empty(): wb=water.admission_budget(_ctx.city) if water!=null else UtilityParams.admission_budget(_ctx.city,true)
		budgets = {"power":pb,"water":wb}
	var predicted := _forecast(-1,-1,false,budgets)
	var candidates: Array[Dictionary] = []
	for value: Dictionary in predicted.rows:
		var candidate := value.duplicate(true)
		var change := TourismDemand.turnover(int(candidate.guests),int(candidate.target_guests))
		if candidate.has("arrival_reservation"):
			change.arrivals = mini(int(change.arrivals),int(candidate.arrival_reservation))
		candidate.guests = int(candidate.guests)-int(change.departures)+int(change.arrivals)
		candidate.day_visitors = candidate.target_day_visitors
		candidates.append(candidate)
	if not budgets.is_empty():
		candidates.assign(TourismUtilities.admission_plan(_ctx.city,candidates,budgets.power,budgets.water).rows)
	var accepted := {}
	for row in candidates: accepted[int(row.instance)] = row
	var rows: Array[Dictionary] = []
	var lodging := 0
	var gaming := 0
	var lodging_numerator := 0
	var gaming_numerator := 0
	var activity_rows: Array[Dictionary] = []
	var access_rows: Array[Dictionary] = []
	var experience_rows: Array[Dictionary] = []
	for value: Dictionary in predicted.rows:
		var row := value.duplicate(true)
		var opening := int(row.guests)
		var opening_segments := TourismMarkets.counts(row)
		var change := TourismDemand.turnover(opening, int(row.target_guests))
		if row.has("arrival_reservation"):
			change.arrivals = mini(int(change.arrivals),int(row.arrival_reservation))
			change.guests = opening-int(change.departures)+int(change.arrivals)
		var supported: Dictionary = accepted[int(row.instance)]
		var natural_departures := int(change.departures)
		var survivors := opening-natural_departures
		# Capacity loss is essential safety, distinct from normal turnover. New
		# arrivals cannot replace displaced survivors in this same transaction.
		row["resource_departures"] = maxi(0,survivors-int(supported.guests))
		row.guests = int(supported.guests)
		row.arrivals = maxi(0,int(row.guests)-survivors)
		row.departures = natural_departures+int(row.resource_departures)
		row.day_visitors = int(supported.day_visitors)
		row["utility_limiting_reason"] = supported.get("utility_limiting_reason","")
		if row.utility_limiting_reason.is_empty(): row.utility_limiting_reason = row.get("planned_utility_limiting_reason","")
		var split := TourismDemand.allocate(PackedInt64Array([int(row.local_day_visitors),int(row.external_day_visitors)]),int(row.day_visitors))
		row.local_day_visitors = split[0]
		row.external_day_visitors = split[1]
		var prior := PackedInt64Array()
		for item: Dictionary in row.gateway_reservations: prior.append(item.count)
		var retained := TourismDemand.allocate(prior,int(row.arrivals)+int(row.external_day_visitors))
		for i in retained.size(): row.gateway_reservations[i].count = retained[i]
		row.gateway_reservations = row.gateway_reservations.filter(func(item: Dictionary) -> bool: return item.count>0)
		row.guest_segments = TourismMarkets.advance(opening_segments,row.guests,row.departures,row.arrivals,row.target_guest_segments)
		row.day_segments = TourismMarkets.partition(int(row.day_visitors),row.target_day_segments)
		var halves := opening_segments.duplicate()
		for segment in 4: halves[segment] += int(row.guest_segments[segment])
		var bases := TourismMarkets.business(opening_segments,row.guest_segments,row.day_segments,row.key)
		lodging_numerator += int(bases.lodging_numerator)
		gaming_numerator += int(bases.gaming_numerator)
		lodging += int(bases.lodging_cents)
		gaming += int(bases.gaming_cents)
		activity_rows.append({"anchor": [row.anchor.x, row.anchor.y], "key": String(row.key),
			"code": row.code, "instance": row.instance, "guest_half_months": opening + int(row.guests),
			"day_visitors": row.day_visitors,"guest_half_segments":halves,"day_segments":row.day_segments.duplicate()})
		access_rows.append({"instance":int(row.instance),"overnight_arrivals":int(row.arrivals),
			"local_day_visitors":int(row.local_day_visitors),"external_day_visitors":int(row.external_day_visitors),
			"gateways":row.gateway_reservations.duplicate(true)})
		var experienced := row.duplicate(true)
		experienced["opening_guests"]=opening
		experienced["natural_departures"]=natural_departures
		experienced["guest_half_segments"]=halves
		experience_rows.append(experienced)
		rows.append(row)
	if _state.replace_records(rows) != OK:
		return
	var experience := TourismReputation.completed(experience_rows,month,_ctx.stats.average_traffic)
	_features.reputation=TourismReputation.advance(_features.reputation,experience,experience.visitor_half_units)
	var staffing: Dictionary = predicted.staffing
	var staff_rows: Array = []
	for row: Dictionary in staffing.rows:
		if not row.operating: continue
		var item := {"instance":int(row.instance)}
		for field in TourismEconomy.FIELDS: item[field] = int(row[field])
		staff_rows.append(item)
	_features.staffing = {"profile":"staffing_20261015","initialized_month":int(_features.staffing.initialized_month),"month_id":month,"resident_workers":staffing.resident_workers,"non_tourism_jobs":staffing.non_tourism_jobs,"incoming_allowance":staffing.incoming_allowance,"rows":staff_rows}
	_features.utilities.month_id = month
	_features.utilities.rows = TourismUtilities.snapshot(rows)
	# Announce against closing accepted day obligations, not the opening
	# crowd. Reuse the unchanged transaction graphs for this pure probe.
	_refresh_calendar_capacity(_calendar_probe_budgets)
	var calendar := TourismCalendar.accept(month,_calendar_inputs(),_features.calendar)
	_features.calendar = calendar.state
	_calendar_news(calendar.notices)
	_last_month = month
	_activity_profile = TourismMarkets.PROFILE
	_features.markets = {"profile":TourismMarkets.PROFILE}
	_activity = {"month_id": month, "rows": activity_rows}
	var transport := transport_state()
	_features.access = {"month_id":month,"rows":access_rows}
	if transport != TransportSystem.neutral_tourism_transport(): _features.access["transport"] = transport
	var active := bool(_ctx.stats.ordinances.get(&"casino_safety", false))
	var half_cents := 0
	for item in activity_rows:
		half_cents += (int(item.guest_half_months) + 2 * int(item.day_visitors)) * TourismParams.SAFETY_CENTS_PER_VISITOR
	_features.safety.period_month = month
	_features.safety.active = active
	_features.safety.cost_half_cents = half_cents if active else 0
	_pending = {"month_id": month, "profile":TourismMarkets.PROFILE,"lodging_numerator":lodging_numerator,"gaming_numerator":gaming_numerator,
		"lodging_cents": lodging_numerator/TourismMarkets.BUSINESS_DENOMINATOR, "gaming_cents": gaming_numerator/TourismMarkets.BUSINESS_DENOMINATOR,
		"program_half_cents": _features.safety.cost_half_cents}
	# Publish the atomic attendance/reservation/business snapshot before either
	# utility reads its overlay. Callbacks cannot reconcile or recursively admit.
	_admission_busy = true
	_publish()
	var full := Rect2i(0,0,City.WIDTH,City.HEIGHT)
	if power!=null: power.reallocate_established(_ctx,full)
	if water!=null: water.reallocate_established(_ctx,full)
	_admission_busy = false
	reconcile_now()

func forecast(occupancy_rate: int = -1, gaming_rate: int = -1, summary_only: bool = false) -> Dictionary:
	return _forecast(occupancy_rate,gaming_rate,summary_only)

## Day-17 planning accepts detached budgets; ordinary report reads never build them.
func _forecast(occupancy_rate: int, gaming_rate: int, summary_only: bool, budgets: Dictionary = {}) -> Dictionary:
	if _ctx == null:
		return {}
	var stats := _ctx.stats
	var city := _ctx.city
	var disasters := _ctx.system(&"disasters")
	var fires: Array = disasters.call("fires") if disasters != null and disasters.has_method("fires") else []
	# Packed layer comparisons also detect raw environment/disaster writes.
	# Every accepted publication clears this derived cache; it is never saved.
	var signature: Array = [_state,_state.revision,occupancy_rate,gaming_rate,stats.tax_occupancy,stats.tax_gaming,
		_month_id(),TourismEconomy.workers(stats),stats.jobs,stats.tourism_jobs,
		stats.population,stats.neighbor_populations,stats.economy_phase,
		stats.average_land_value,stats.average_crime,stats.average_pollution,stats.average_traffic,
		stats.ordinances,_features.reputation,_features.calendar,_calendar_supported_beds,
		_access.version,city.building.data,city.zone.data,city.flags.data,
		city.land_value.data,city.crime.data,city.pollution.data,fires]
	if budgets.is_empty() and signature==_forecast_signature and not _forecast_cache.is_empty():
		_forecast_hits += 1
		return _forecast_copy(_forecast_cache,summary_only)
	if budgets.is_empty():
		_forecast_signature=signature.duplicate(true)
		_supported_cache.clear()
	_forecast_computations += 1
	var calendar := calendar_report()
	var environment := _environment_rows()
	var result := TourismDemand.forecast(environment, {
		"gateways": _access.gateways(),
		"resident_workers": TourismEconomy.workers(stats), "non_tourism_jobs": maxi(0,stats.jobs-stats.tourism_jobs),
		"staffing_grace": _month_id() <= int(_features.migration.grace_until_month),
		"permanent_population": stats.population, "neighbor_populations": stats.neighbor_populations,
		"economy_phase": stats.economy_phase, "average_land_value": stats.average_land_value,
		"average_crime": stats.average_crime, "average_pollution": stats.average_pollution,
		"average_traffic": stats.average_traffic,
		"tourist_advertising": stats.ordinances.get(&"tourist_advertising", false),
		"season_percent":calendar.season_percent,"event_factors":calendar.event_factors,
		"reputation_factor_milli":TourismReputation.demand_factor(_features.reputation,_month_id())},
		stats.tax_occupancy if occupancy_rate < 0 else occupancy_rate,
		stats.tax_gaming if gaming_rate < 0 else gaming_rate,
		city if not budgets.is_empty() else null,budgets.get("power",{}),budgets.get("water",{}))
	result["reputation"] = reputation_report()
	result["calendar"] = calendar
	# Cached display facts share the existing stock aggregation. A store has no
	# beds, but its operating status, day capacity and staff still matter.
	result["stock_venues"] = result.rows.size()
	for field in ["physical_capacity","day_capacity","operating_venues","closed_venues","staff_limited_guest_venues","staff_limited_day_venues"]: result[field]=0
	for row: Dictionary in result.rows:
		result.physical_capacity += int(row.capacity)
		if row.operating:
			result.operating_venues += 1
			result.day_capacity += int(row.day_capacity)
			if int(row.supported_capacity)<int(row.planned_guests): result.staff_limited_guest_venues += 1
			if int(row.supported_day_capacity)<int(row.planned_day_visitors): result.staff_limited_day_venues += 1
		else: result.closed_venues += 1
	if budgets.is_empty(): _forecast_cache=result
	return _forecast_copy(result,summary_only)

func forecast_work() -> Dictionary:
	return {"computations":_forecast_computations,"hits":_forecast_hits}

static func _forecast_copy(value: Dictionary, summary_only: bool) -> Dictionary:
	if not summary_only: return value.duplicate(true)
	var result := value.duplicate()
	result.erase("rows")
	result.erase("staffing")
	return result.duplicate(true)

## A conservative Budget quote. A limited venue cannot sell more places in
## the displayed estimate than its latest accepted utility plan. This is an
## estimate at the current month's pace, not a future resource reservation.
## The conditional demand forecast above remains the admission algorithm.
func supported_forecast(occupancy_rate: int = -1, gaming_rate: int = -1, summary_only: bool = false) -> Dictionary:
	forecast(occupancy_rate,gaming_rate,true)
	if _supported_cache.is_empty():
		var result := _forecast_cache.duplicate(true)
		var accepted := {}
		for item: Dictionary in _features.utilities.get("rows",[]): accepted[int(item.instance)]=item
		for field in ["guests","day_visitors","lodging_numerator","gaming_numerator"]: result[field]=0
		result["support_limited_venues"]=0
		result["awaiting_support_venues"]=0
		result["support_month"]=int(_features.utilities.get("month_id",-1))
		for row: Dictionary in result.rows:
			var support: Dictionary=accepted.get(int(row.instance),{})
			var utility_limited := not String(support.get("limiting_reason","")).is_empty()
			var awaiting_support := not utility_limited and int(support.get("supported_guests",0))+int(support.get("supported_days",0))==0
			if row.operating:
				if utility_limited: result.support_limited_venues += 1
				elif awaiting_support: result.awaiting_support_venues += 1
			if utility_limited or awaiting_support:
				row.projected_guests=mini(int(row.projected_guests),int(row.guests))
				row.projected_day_visitors=mini(int(row.projected_day_visitors),int(row.day_visitors))
				row.projected_guest_segments=TourismMarkets.partition(row.projected_guests,row.guest_segments)
				row.projected_day_segments=TourismMarkets.partition(row.projected_day_visitors,row.day_segments)
				row.merge(TourismMarkets.business(row.projected_guest_segments,row.projected_guest_segments,row.projected_day_segments,row.key),true)
			result.guests += int(row.projected_guests)
			result.day_visitors += int(row.projected_day_visitors)
			result.lodging_numerator += int(row.lodging_numerator)
			result.gaming_numerator += int(row.gaming_numerator)
		result.lodging_cents=int(result.lodging_numerator)/TourismMarkets.BUSINESS_DENOMINATOR
		result.gaming_cents=int(result.gaming_numerator)/TourismMarkets.BUSINESS_DENOMINATOR
		result.occupancy=int(result.guests)*100/int(result.capacity) if int(result.capacity)>0 else 0
		_supported_cache=result
	return _forecast_copy(_supported_cache,summary_only)

func report() -> Array[Dictionary]:
	var rows := _state.records()
	var staffing := {}
	for item: Dictionary in _features.staffing.get("rows",[]): staffing[int(item.instance)] = item
	var utilities := {}
	for item: Dictionary in _features.utilities.get("rows",[]): utilities[int(item.instance)] = item
	var activity_by_instance := {}
	for item: Dictionary in _activity.get("rows", []):
		activity_by_instance[int(item.instance)] = item
	for row in rows:
		row.merge(TourismEconomy.neutral(),true)
		row.merge(staffing.get(int(row.instance),{}),true)
		row.merge(_districts.venue_inputs(row.anchor), true)
		row.merge(_access.venue_access(row.anchor), true)
		var facility := _ctx.city.facility(row.anchor)
		var reservation: Dictionary = utilities.get(int(row.instance),{})
		row["utility_supported_guests"] = int(reservation.get("supported_guests",0))
		row["utility_supported_days"] = int(reservation.get("supported_days",0))
		row["utility_limiting_reason"] = String(reservation.get("limiting_reason",""))
		row["resource_departures"] = int(reservation.get("resource_departures",0))
		row["visitor_power_demand"] = TourismUtilities.request(row,false)
		row["visitor_water_demand"] = TourismUtilities.request(row,true)
		row["tourists"] = row.guests + row.day_visitors
		row["occupancy"] = int(row.guests) * 100 / int(row.capacity) if row.capacity > 0 else 0
		row["built_day"] = facility.get("built_day", _ctx.city.day)
		row["built_year"] = facility.get("built_year", _ctx.city.current_year())
		row["condition"] = facility.get("condition", 0)
		row["pollution"] = int(row.tourists) / 1000 * RewardParams.POLLUTION_PER_THOUSAND
		var effect := TourismEffects.venue_effect(row, activity_by_instance.get(int(row.instance), {}), _features.safety)
		row.merge(effect, true)
		row["crime"] = float(effect.crime_source_micro) / TourismParams.CRIME_MICRO_UNIT
		var current := TourismMarkets.business(row.guest_segments,row.guest_segments,row.day_segments,row.key)
		row["yield_factors"] = TourismMarkets.yield_factors(row.key)
		row["current_lodging_cents"] = current.lodging_cents
		row["current_gaming_cents"] = current.gaming_cents
		var business: Dictionary = activity_by_instance.get(int(row.instance), {})
		row["business_month"] = _last_month if not business.is_empty() else -1
		var half_months := int(business.get("guest_half_months", 0))
		row["guest_half_months"] = half_months
		row["business_day_visitors"] = int(business.get("day_visitors", 0))
		row["lodging_cents"] = half_months * TourismParams.LODGING_CENTS_PER_HALF_GUEST
		row["gaming_cents"] = half_months * TourismParams.GAMING_CENTS_PER_HALF_GUEST + int(row.business_day_visitors) * TourismParams.GAMING_CENTS_PER_VISITOR
		if _activity_profile == TourismMarkets.PROFILE and not business.is_empty():
			row.merge(TourismMarkets.business(business.guest_half_segments,[0,0,0,0],business.day_segments,row.key),true)
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
	return {"schema": SCHEMA, "features": _features.duplicate(true), "activity_profile": _activity_profile, "state": _state.to_dict(), "last_month": _last_month, "pending": _pending.duplicate(true), "activity": _activity.duplicate(true)}

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
		row.merge(_districts.venue_inputs(a), true)
		row.merge(_access.venue_access(a), true)
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
	_forecast_signature.clear()
	_forecast_cache.clear()
	_supported_cache.clear()
	if not _features.utilities.is_empty():
		_features.utilities.rows = TourismUtilities.snapshot(_state.records(),_features.utilities.rows)
	_access.refresh(_ctx)
	_districts.refresh(_ctx, _state.records(), _access)
	var stats := _ctx.stats
	var opportunities := jobs()
	stats.jobs += opportunities-stats.tourism_jobs
	stats.tourism_jobs = opportunities
	stats.tourist_reputation_milli=int(_features.reputation.value_milli)
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
	# Publish accepted inputs only; allocation stays with the coordinated utility pass.
	var accepted := utility_rows()
	for utility_key in [&"power",&"water"]:
		var utility := _ctx.system(utility_key)
		if utility != null and utility.has_method("accept_visitor_rows"):
			utility.call("accept_visitor_rows",_ctx.city,accepted)
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


## Copied, versioned live consequences; completed costs remain in pending business.
func effects_snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	for row in report():
		rows.append({"anchor": row.anchor, "instance": row.instance, "code": row.code,
			"positions":row.positions,"local_staff":row.local_staff,"incoming_staff":row.incoming_staff,
			"supported_capacity":row.supported_capacity,"supported_day_capacity":row.supported_day_capacity,
			"key": row.key, "guests": row.guests, "day_visitors": row.day_visitors,
			"visitor_power_demand":row.visitor_power_demand,"visitor_water_demand":row.visitor_water_demand,
			"guest_segments":row.guest_segments.duplicate(),"day_segments":row.day_segments.duplicate(),
			"operating": row.operating, "crime_source_micro": row.crime_source_micro,
			"crime_raw_micro": row.crime_raw_micro, "nightlife_strength": row.nightlife_strength,
			"safety_active": row.safety_active,
			"external_reachable":row.external_reachable,"local_reachable":row.local_reachable,
			"access_status":row.access_status,"gateway_ids":row.gateway_ids.duplicate(),
			"district_categories": row.district_categories.duplicate(),
			"district_appeal_bonus": row.district_appeal_bonus,
			"resort_variety_bonus": row.resort_variety_bonus,
			"commercial_spending_cents": row.commercial_spending_cents,
			"commercial_allocated_cents": row.commercial_allocated_cents})
	return {"schema": 1, "month_id": _last_month, "rows": rows,
		"security_active": bool(_features.safety.active), "commercial": _districts.report(), "access":_access.report(), "accepted_access":_features.access.duplicate(true)}

func extension_report() -> Dictionary:
	var source := 0
	var raw := 0
	for row in report():
		source += int(row.crime_source_micro)
		raw += int(row.crime_raw_micro)
	var result := _districts.report()
	result["access"] = _access.report()
	result.merge({"crime_source_milli": source / 1000.0, "crime_raw_milli": raw / 1000.0,
		"program_active": bool(_features.safety.active),
		"program_estimated_annual_cents": program_estimated_annual_cents(),
		"program_completed_half_cents": int(_features.safety.cost_half_cents),
		"migration_grace_until_month": int(_features.migration.grace_until_month)}, true)
	return result

## Prospective visitor quote, independent of current resident population.
func program_estimated_annual_cents() -> int:
	var projection := supported_forecast(-1,-1,true)
	return (int(projection.get("guests", 0)) + int(projection.get("day_visitors", 0))) * TourismParams.SAFETY_CENTS_PER_VISITOR * 12

## The scheduled environment pass owns rounding advancement; report reads do not.
func environmental_effects(developed: PackedByteArray) -> Dictionary:
	return TourismEffects.environment(_ctx.city, effects_snapshot().rows, _features.safety,
		_month_id(), developed)

## Cached influence only: zone growth/report readers never discover lots.
func commercial_bonus(anchor: Vector2i) -> int:
	return _districts.commercial_bonus(anchor)

func commercial_demand_bonus() -> int:
	return _districts.commercial_demand_bonus()


## Routing owner retained for the scheduled tourism-trip consumer.
func access_routes() -> TourismAccess:
	return _access


## Completed accepted trips survive route loss; consumer owns its process guard.
func accepted_access() -> Dictionary:
	return _features.access.duplicate(true)


func transport_state() -> Dictionary:
	return _features.access.get("transport",TransportSystem.neutral_tourism_transport()).duplicate(true)

## Only the scheduled Transport pass advances accepted-trip progress.
func accept_transport(value: Dictionary) -> void:
	if not _features.access.is_empty(): _features.access["transport"] = value.duplicate(true)

## Budget owns the only monetary conversion. An acknowledged completed rider
## cannot be booked by a second Budget call or after restoring the same state.
func claim_transport_riders() -> int:
	var value := transport_state()
	var count := TransportSystem.claim_fare_evidence(value)
	if count > 0:
		accept_transport(value)
	return count


## Scheduled writer hook: raw disasters may have bypassed a view notification.
func refresh_transport_access() -> void:
	_access.refresh(_ctx)


func transport_pass_month() -> int:
	return int(_features.access.get("transport",{}).get("pass_month",-1))

func transport_report() -> Dictionary:
	return _features.access.get("transport",{}).get("report",TransportSystem.neutral_tourism_report()).duplicate(true)


## Last accepted live opportunities. Census replacements and deltas share this.
func jobs() -> int:
	var total := 0
	for row: Dictionary in _features.staffing.get("rows",[]): total += int(row.positions)
	return total

## Current accepted opportunities, checked against the standing instance.
## Route consumers test every actual frontage; this adds no origin or worker.
func job_tiles() -> PackedInt32Array:
	var result := PackedInt32Array()
	var accepted := {}
	for row: Dictionary in _features.staffing.get("rows",[]):
		if int(row.positions)>0: accepted[int(row.instance)] = true
	for row in _state.records():
		if not row.operating or not accepted.has(int(row.instance)) or not TourismUtilities._standing(_ctx.city,row): continue
		var size := Buildings.size(int(row.code))
		for dy in size.y:
			for dx in size.x: result.append((row.anchor.y+dy)*City.WIDTH+row.anchor.x+dx)
	return result

func staffing_report() -> Dictionary:
	var result := {"positions":jobs(),"local_staff":0,"incoming_staff":0,"supported_capacity":0,"supported_day_capacity":0,"planned_guests":0,"planned_day_visitors":0}
	for row: Dictionary in _features.staffing.get("rows",[]):
		for field in ["local_staff","incoming_staff","supported_capacity","supported_day_capacity","planned_guests","planned_day_visitors"]: result[field] += int(row[field])
	return result


## Minimal immutable accepted snapshot for utilities, independent of UI/forecast work.
func utility_rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in _state.records():
		result.append({"anchor":row.anchor,"key":row.key,"code":row.code,"instance":row.instance,
			"guests":row.guests,"day_visitors":row.day_visitors,"operating":row.operating})
	return result


## Current accepted support only. No graph scans, allocation, or earned-state
## changes occur while Inspect, Details, forecasts or utility reports read it.
func utility_report() -> Dictionary:
	var result := {"supported_guests":0,"supported_days":0,"power":0,"water":0,"limited_venues":0,"resource_departures":0}
	for row: Dictionary in _features.utilities.get("rows",[]):
		for field in ["supported_guests","supported_days","power","water","resource_departures"]: result[field] += int(row[field])
		if not String(row.limiting_reason).is_empty(): result.limited_venues += 1
	return result

## Cached complete/serviced hosts and gateways; read paths do not build graphs.
func _calendar_inputs() -> Dictionary:
	var result := _districts.event_hosts()
	result["annual_carnival"] = bool(_ctx.stats.ordinances.get(&"annual_carnival",false))
	result["business_gateway"] = false
	if result.city_hall:
		var connected := {}
		for row: Dictionary in _state.records():
			if not row.operating: continue
			for id: String in _access.venue_access(row.anchor).get("gateway_ids",[]): connected[id]=true
		for gateway: Dictionary in _access.gateways():
			if gateway.kind in ["rail","airport"] and connected.has(gateway.id): result.business_gateway=true
	result["supported_beds"] = _calendar_supported_beds
	result["calendar"] = _features.calendar
	return result

## Prospective full overnight beds, retaining accepted day obligations. The
## probe neither installs positions/reservations nor touches attendance/money.
## Only simulation hooks call this. Packed-layer + source/labor comparisons
## avoid rebuilding graphs on unchanged daily hooks, and most months skip it.
func _refresh_calendar_capacity(budgets: Dictionary = {}) -> void:
	var inputs := _calendar_inputs()
	if _month_id()%12 not in [9,10] or not inputs.city_hall or not inputs.business_gateway:
		_calendar_supported_beds=0
		_calendar_capacity_month=-1
		_calendar_probe_signature.clear()
		_calendar_probe_budgets.clear()
		return
	var city := _ctx.city
	var rows := _environment_rows()
	var workers := TourismEconomy.workers(_ctx.stats)
	var other_jobs := maxi(0,_ctx.stats.jobs-_ctx.stats.tourism_jobs)
	var power := _ctx.system(&"power") as PowerSystem
	var water := _ctx.system(&"water") as WaterSystem
	var signature: Array = [city.building.data,city.zone.data,city.flags.data,city.underground.data,city.facilities,city.imported_power_links,rows,workers,other_jobs,_ctx.stats.ordinances,_access.version,power._conservation if power!=null else false]
	if signature==_calendar_probe_signature: return
	_calendar_probe_signature=signature.duplicate(true)
	_calendar_capacity_month=_month_id()
	var pb: Dictionary = budgets.get("power",{})
	var wb: Dictionary = budgets.get("water",{})
	if pb.is_empty(): pb=power.admission_budget(city) if power!=null else UtilityParams.admission_budget(city,false)
	if wb.is_empty(): wb=water.admission_budget(city) if water!=null else UtilityParams.admission_budget(city,true)
	_calendar_probe_budgets={"power":pb,"water":wb}
	_calendar_supported_beds=TourismCalendar.supported_beds(city,rows,workers,other_jobs,{"gateways":_access.gateways()},pb,wb)

func calendar_report() -> Dictionary:
	if _ctx==null: return {}
	var result := TourismCalendar.for_month(_month_id(),_calendar_inputs())
	result["supported_beds"]=_calendar_supported_beds
	result["accepted_month"]=int(_features.calendar.get("month_id",-1))
	result["capacity_snapshot_month"]=_calendar_capacity_month
	if not result.next_event.is_empty():
		var event_month := int(result.next_event.month_id)
		result.next_event["date"]="%s %d" % [GameClock.MONTH_NAMES[event_month%12],_ctx.clock.founded_year+event_month/12]
	return result

func _calendar_news(notices: Array) -> void:
	for notice: Dictionary in notices:
		var args: Dictionary = notice.args.duplicate(true)
		var month := int(args.event_month)
		args.date="%s %d" % [GameClock.MONTH_NAMES[month%12],_ctx.clock.founded_year+month/12]
		args["place"]=args.identity
		_ctx.events.report(notice.kind,args,2)

## Completed score is historical; opening reputation drives this month's demand.
func reputation_report() -> Dictionary:
	var result: Dictionary=_features.reputation.duplicate(true)
	result["current_factor_milli"]=TourismReputation.demand_factor(_features.reputation,_month_id())
	result["future_factor_milli"]=TourismReputation.factor_milli(int(result.value_milli))
	result["period_date"]="%s %d" % [GameClock.MONTH_NAMES[int(result.month_id)%12],_ctx.clock.founded_year+int(result.month_id)/12] if int(result.month_id)>=0 else "No completed visits"
	return result

func reputation_text() -> String:
	var r := reputation_report()
	var experience := "%.2f / 100" % (int(r.experience_milli)/1000.0) if int(r.experience_milli)>=0 else "no accepted visitors"
	return "Destination reputation %.2f / 100. Current-month demand factor %.2f%%; following-month factor %.2f%%. %s experience: %s. Accepted experience weight: %d units (opening guests + closing guests + twice day visitors; not headcount)." % [int(r.value_milli)/1000.0,int(r.current_factor_milli)/1000.0,int(r.future_factor_milli)/1000.0,r.period_date,experience,int(r.visitor_half_units)]
