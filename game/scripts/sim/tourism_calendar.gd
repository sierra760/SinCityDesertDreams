# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Explicit zero-based absolute months. Queries never advance guards or emit news.
class_name TourismCalendar
extends RefCounted

const PROFILE := "calendar_20261015"
const SEASONS := [115,115,110,100,90,80,75,80,95,105,115,120]
const MONTHS := {"carnival":3,"sports":8,"convention":10}
const NAMES := {"carnival":"Annual Carnival","sports":"City Sports Festival","convention":"City Convention"}
const SEGMENTS := {"carnival":[125,125,100,100],"sports":[125,125,100,100],"convention":[100,100,100,125]}

static func initial(month: int, last: int = -1) -> Dictionary:
	return {"profile":PROFILE,"activation_month":month,"month_id":last,"events":[]}

static func eligible(kind: String, inputs: Dictionary) -> bool:
	match kind:
		"carnival": return bool(inputs.get("annual_carnival",false))
		"sports": return bool(inputs.get("stadium",false))
		"convention": return bool(inputs.get("city_hall",false)) and bool(inputs.get("business_gateway",false)) and int(inputs.get("supported_beds",0))>=1000
	return false

static func identity(kind: String, month: int) -> String:
	return "%s:%d" % [kind,month]

## At most three event identities, each at its explicit calendar date. No
## retrospective notice when this feature is first activated inside an event.
static func accept(month: int, inputs: Dictionary, previous: Dictionary) -> Dictionary:
	var state := previous.duplicate(true)
	var notices: Array = []
	if month<=int(state.month_id): return {"state":state,"notices":notices}
	state.events = state.events.filter(func(e: Dictionary) -> bool: return int(e.month_id)>=month-10)
	for event: Dictionary in state.events:
		if int(event.month_id)<month and event.status!="cancelled": event.status="completed"
		elif int(event.month_id)==month and event.status=="announced":
			event.status="active" if eligible(event.kind,inputs) else "cancelled"
			if event.status=="cancelled": notices.append(_notice(event,true))
	for kind: String in MONTHS:
		if (month+1)%12!=int(MONTHS[kind]) or not eligible(kind,inputs): continue
		var event := {"kind":kind,"month_id":month+1,"announced_month":month,"status":"announced"}
		state.events.append(event)
		notices.append(_notice(event,false))
	state.month_id=month
	return {"state":state,"notices":notices}

## Simulation-hook invalidation is sticky even if service returns before the
## event. Earned attendance/business and the accepted month are untouched.
static func cancel(month: int, inputs: Dictionary, previous: Dictionary) -> Dictionary:
	var state := previous.duplicate(true)
	var notices: Array = []
	for event: Dictionary in state.events:
		if int(event.month_id)<month or event.status not in ["announced","active"]: continue
		if not eligible(event.kind,inputs):
			event.status="cancelled"
			notices.append(_notice(event,true))
	return {"state":state,"notices":notices}

static func _notice(event: Dictionary, cancelled: bool) -> Dictionary:
	return {"kind":&"tourism_event_cancelled" if cancelled else &"tourism_event_announced",
		"args":{"event":NAMES[event.kind],"identity":identity(event.kind,int(event.month_id)),"event_month":int(event.month_id)}}

static func for_month(month: int, inputs: Dictionary) -> Dictionary:
	var factors := [100,100,100,100]
	var next: Dictionary = {}
	var current: Dictionary = {}
	for event: Dictionary in inputs.get("calendar",{}).get("events",[]):
		var display := event.duplicate(true)
		if display.status in ["announced","active"] and not eligible(display.kind,inputs): display.status="cancelled"
		display["name"] = NAMES[display.kind]
		if int(event.month_id)==month:
			current=display
			if display.status in ["announced","active"]: factors=SEGMENTS[display.kind].duplicate()
		if int(event.month_id)>=month and (next.is_empty() or int(event.month_id)<int(next.month_id)): next=display
	return {"month_id":month,"season_percent":SEASONS[month%12],"event_factors":factors,"current_event":current,"next_event":next,
		"time_basis":"Current-month season and announced events held fixed; annualized estimate, not a twelve-season projection."}

static func decode(value: Dictionary, block: Dictionary, month: int) -> Dictionary:
	if value.is_empty(): return {"ok":true,"value":{}}
	if value.size()!=4 or value.get("profile")!=PROFILE or not value.get("events") is Array or value.events.size()>3: return {"ok":false}
	if not TourismState._integer(value.get("activation_month"),0,month) or not TourismState._integer(value.get("month_id"),-1,month): return {"ok":false}
	var last := int(value.month_id)
	if last!=int(block.get("last_month",-1)): return {"ok":false}
	var seen := {}
	var result := value.duplicate(true)
	result.activation_month=int(result.activation_month)
	result.month_id=last
	for e: Variant in result.events:
		if not e is Dictionary or e.size()!=4 or not e.get("kind") is String or not MONTHS.has(e.kind): return {"ok":false}
		if not TourismState._integer(e.get("month_id"),maxi(int(result.activation_month)+1,last-10),last+1): return {"ok":false}
		if not TourismState._integer(e.get("announced_month"),int(result.activation_month),last): return {"ok":false}
		e.month_id=int(e.month_id)
		e.announced_month=int(e.announced_month)
		if e.month_id%12!=int(MONTHS[e.kind]) or e.announced_month!=e.month_id-1 or seen.has(e.kind): return {"ok":false}
		seen[e.kind]=true
		if not e.get("status") is String or e.status not in ["announced","active","completed","cancelled"]: return {"ok":false}
		if e.status=="announced" and e.month_id!=last+1: return {"ok":false}
		if e.status=="active" and e.month_id!=last: return {"ok":false}
		if e.status=="completed" and e.month_id>=last: return {"ok":false}
	return {"ok":true,"value":result}

## Pure hypothetical capacity, never a second admission transaction. Actual
## accepted day visitors compete for labor and utility against full guest beds.
static func supported_beds(city: City, rows: Array[Dictionary], workers: int, other_jobs: int, access: Dictionary, power: Dictionary, water: Dictionary) -> int:
	var prospective: Array[Dictionary] = rows.duplicate(true)
	for row in prospective:
		row["target_guests"]=TourismParams.guest_capacity(StringName(row.key)) if row.operating else 0
		row["target_day_visitors"]=int(row.get("day_visitors",0)) if row.operating else 0
	var staff := TourismEconomy.allocate(prospective,workers,other_jobs,access)
	for row: Dictionary in staff.rows:
		var required := TourismEconomy.requirements(StringName(row.key),0,int(row.day_visitors))
		var remaining := maxi(0,int(row.local_staff)+int(row.incoming_staff)-required[0]-required[2])
		@warning_ignore("integer_division")
		row.guests=mini(int(row.planned_guests),remaining*100/int(TourismEconomy.STAFF_PER_HUNDRED[TourismMarkets.tier(StringName(row.key))]))
	var plan := TourismUtilities.admission_plan(city,staff.rows,power,water,true)
	var total := 0
	for row: Dictionary in plan.rows: total+=int(row.guests)
	return total
