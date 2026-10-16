# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## One finite resident labor share and one regional staff allowance per city.
## All calculations are pure. Only TourismSystem's accepted month publishes jobs.
class_name TourismEconomy
extends RefCounted

const STAFF_PER_HUNDRED := [5, 7, 10]
const BASE_POSITIONS := 2
const DAY_VISITORS_PER_POSITION := 12
const INITIAL_INCOMING := 8
const EXTRA_INCOMING := 4
const MAX_INCOMING := 64
const FIELDS := ["planned_guests", "planned_day_visitors", "positions", "local_staff", "incoming_staff", "staffing_percent", "supported_capacity", "supported_day_capacity"]

static func workers(stats: CityStats) -> int:
	var total := 0
	for i in range(PopulationParams.WORK_COHORT_MIN, mini(PopulationParams.WORK_COHORT_MAX + 1, stats.cohorts.size())):
		total += maxi(0, stats.cohorts[i])
	return total

static func neutral() -> Dictionary:
	return {"planned_guests":0,"planned_day_visitors":0,"positions":0,"local_staff":0,"incoming_staff":0,"staffing_percent":0,"supported_capacity":0,"supported_day_capacity":0}

@warning_ignore("integer_division")
static func requirements(key: StringName, guests: int, days: int) -> PackedInt64Array:
	return PackedInt64Array([0 if key == &"com_corner_store" else BASE_POSITIONS,
		(guests * int(STAFF_PER_HUNDRED[TourismMarkets.tier(key)]) + 99) / 100,
		(days + DAY_VISITORS_PER_POSITION - 1) / DAY_VISITORS_PER_POSITION])

@warning_ignore("integer_division")
static func support(key: StringName, guests: int, days: int, filled: int) -> Vector2i:
	var required := requirements(key, guests, days)
	if filled < required[0]: return Vector2i.ZERO
	var variable := TourismDemand.allocate(PackedInt64Array([required[1],required[2]]),filled-required[0])
	return Vector2i(mini(guests,variable[0]*100/int(STAFF_PER_HUNDRED[TourismMarkets.tier(key)])), mini(days,variable[1]*DAY_VISITORS_PER_POSITION))

@warning_ignore("integer_division")
static func allocate(rows: Array[Dictionary], resident_workers: int, non_tourism_jobs: int, access: Dictionary) -> Dictionary:
	var ordered: Array[Dictionary] = rows.duplicate(true)
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.anchor.y*City.WIDTH+a.anchor.x < b.anchor.y*City.WIDTH+b.anchor.x)
	var valid := {}
	for gateway: Dictionary in access.get("gateways",[]): valid[String(gateway.id)] = true
	var connected := {}
	var positions := PackedInt64Array()
	var total := 0
	for row in ordered:
		var guests := int(row.get("target_guests",0)) if row.get("operating",false) else 0
		var days := int(row.get("target_day_visitors",0)) if row.get("operating",false) else 0
		row.merge(neutral(),true)
		row.planned_guests = guests
		row.planned_day_visitors = days
		if row.get("operating",false):
			var required := requirements(row.key,guests,days)
			row.positions = required[0]+required[1]+required[2]
			for id: String in row.get("gateway_ids",[]):
				if valid.has(id): connected[id] = true
		positions.append(row.positions)
		total += int(row.positions)
	var allowance := mini(MAX_INCOMING,INITIAL_INCOMING+EXTRA_INCOMING*(connected.size()-1)) if not connected.is_empty() else 0
	var opportunities := total + maxi(0,non_tourism_jobs)
	var share := mini(total,maxi(0,resident_workers)*total/opportunities) if opportunities > 0 else 0
	var local := TourismDemand.allocate(positions,share)
	var unmet := PackedInt64Array()
	for i in ordered.size():
		var eligible := false
		for id: String in ordered[i].get("gateway_ids",[]):
			if valid.has(id): eligible = true
		unmet.append(positions[i]-local[i] if eligible else 0)
	var incoming := TourismDemand.allocate(unmet,allowance)
	for i in ordered.size():
		var row := ordered[i]
		row.local_staff = local[i]
		row.incoming_staff = incoming[i]
		var filled := local[i]+incoming[i]
		row.staffing_percent = filled*100/positions[i] if positions[i] > 0 else 0
		var capacity := support(row.key,row.planned_guests,row.planned_day_visitors,filled)
		row.supported_capacity = capacity.x
		row.supported_day_capacity = capacity.y
	return {"rows":ordered,"positions":total,"resident_workers":maxi(0,resident_workers),"local_staff":share,"incoming_allowance":allowance,"non_tourism_jobs":maxi(0,non_tourism_jobs)}

## Detached persistence checks: offered counts derive from the saved plan,
## support derives from filled counts, and city pools are checked once globally.
static func decode(value: Dictionary, block: Dictionary, month: int) -> Dictionary:
	if value.is_empty(): return {"ok":true,"value":{}}
	if value.size() != 7 or not value.get("rows") is Array: return {"ok":false}
	for field in ["initialized_month","month_id"]:
		if not TourismState._integer(value.get(field),-1,month): return {"ok":false}
	if int(value.initialized_month) < 0 or int(value.month_id) != int(block.get("last_month",-1)): return {"ok":false}
	for field in ["resident_workers","non_tourism_jobs"]:
		if not TourismState._integer(value.get(field),0,TourismParams.MAX_COUNT): return {"ok":false}
	if not TourismState._integer(value.get("incoming_allowance"),0,MAX_INCOMING): return {"ok":false}
	if value.get("profile") != "staffing_20261015": return {"ok":false}
	# Feature validation precedes the state installer at both public save
	# boundaries. Raw source rows are untrusted here, including their keys,
	# identities and operating flags. Reuse the detached row codec and only
	# index its normalized records; a script error must never imply success.
	var state: Variant = block.get("state")
	if not state is Dictionary or not TourismState._integer(state.get("schema"),1,TourismState.SCHEMA): return {"ok":false}
	var checked := TourismState._validate_rows(state.get("records"),true,int(state.schema)==1)
	if not checked.ok: return {"ok":false}
	var known := {}
	for row: Dictionary in checked.rows: known[int(row.instance)] = row
	var seen := {}
	var local := 0
	var incoming := 0
	var normalized := value.duplicate(true)
	for row: Variant in normalized.rows:
		if not row is Dictionary or row.size() != FIELDS.size()+1: return {"ok":false}
		if not TourismState._integer(row.get("instance"),1,TourismState.MAX_INSTANCE-1): return {"ok":false}
		var id := int(row.instance)
		if not known.has(id) or seen.has(id): return {"ok":false}
		seen[id] = true
		for field in FIELDS:
			if not TourismState._integer(row.get(field),0,TourismParams.MAX_COUNT): return {"ok":false}
			row[field] = int(row[field])
		row.instance = id
		var source: Dictionary = known[id]
		if row.planned_guests > TourismParams.guest_capacity(source.key) or row.planned_day_visitors > TourismParams.day_capacity(source.key): return {"ok":false}
		var required := requirements(source.key,row.planned_guests,row.planned_day_visitors)
		if row.positions != required[0]+required[1]+required[2] or not source.operating: return {"ok":false}
		var filled := int(row.local_staff)+int(row.incoming_staff)
		if filled > int(row.positions): return {"ok":false}
		@warning_ignore("integer_division")
		var percent := filled*100/int(row.positions) if int(row.positions)>0 else 0
		var capacity := support(source.key,row.planned_guests,row.planned_day_visitors,filled)
		if row.staffing_percent != percent or row.supported_capacity != capacity.x or row.supported_day_capacity != capacity.y: return {"ok":false}
		local += int(row.local_staff)
		incoming += int(row.incoming_staff)
	if local > int(value.resident_workers) or incoming > int(value.incoming_allowance): return {"ok":false}
	for field in ["initialized_month","month_id","resident_workers","non_tourism_jobs","incoming_allowance"]: normalized[field] = int(normalized[field])
	return {"ok":true,"value":normalized}
