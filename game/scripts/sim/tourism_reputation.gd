# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Pure completed-visit experience. Exposure units are half visitor-months,
## never additional people, journeys, arrivals, staff or resident cohorts.
class_name TourismReputation
extends RefCounted

const PROFILE := "reputation_20261015"
const NEUTRAL := 60000
const NEEDS := ["safety", "access", "attractions", "staffing", "services"]

static func initial(month: int) -> Dictionary:
	return {"profile":PROFILE,"activation_month":month,"month_id":-1,"value_milli":NEUTRAL,
		"quarter_remainder":0,"empty_months":0,"opening_milli":NEUTRAL,"opening_remainder":0,
		"opening_empty_months":0,"experience_milli":-1,"visitor_half_units":0}

@warning_ignore("integer_division")
static func factor_milli(value_milli: int) -> int:
	return clampi(100000+(value_milli-NEUTRAL)/2,75000,120000)

static func demand_factor(state: Dictionary, month: int) -> int:
	return factor_milli(int(state.opening_milli) if int(state.month_id)==month else int(state.value_milli))

## The supplied month is the acceptance guard; queries never call this writer.
## A signed remainder retains sub-milli quarter movement between visited months.
@warning_ignore("integer_division")
static func advance(previous: Dictionary, experience: Dictionary, visitors: int) -> Dictionary:
	var state := previous.duplicate(true)
	var month := int(experience.month_id)
	if month<=int(state.month_id) or month<int(state.activation_month): return state
	state.month_id=month
	state.opening_milli=int(state.value_milli)
	state.opening_remainder=int(state.quarter_remainder)
	state.opening_empty_months=int(state.empty_months)
	state.visitor_half_units=maxi(0,visitors)
	state.experience_milli=clampi(int(experience.value_milli),0,100000) if visitors>0 else -1
	if visitors>0:
		state.empty_months=0
		var numerator := int(state.experience_milli)-int(state.value_milli)+int(state.quarter_remainder)
		var step := numerator/4
		var bounded := clampi(step,-8000,3000)
		state.quarter_remainder=numerator%4 if numerator>=-32000 and numerator<=12000 else 0
		state.value_milli=clampi(int(state.value_milli)+bounded,0,100000)
	else:
		state.empty_months=mini(TourismParams.MAX_COUNT,int(state.empty_months)+1)
		state.quarter_remainder=0
		if int(state.empty_months)>3:
			state.value_milli+=clampi(NEUTRAL-int(state.value_milli),-1000,1000)
	return state

## Inputs come from the accepted rows and already published environment/cache.
## Natural turnover is not a service failure; refused future demand never visited.
@warning_ignore("integer_division")
static func venue_experience(row: Dictionary, traffic: int) -> Dictionary:
	var opening := int(row.get("opening_guests",0))
	var survivors := maxi(0,opening-int(row.get("natural_departures",0)))
	var displaced := clampi(int(row.get("resource_departures",0)),0,survivors)
	var services := (survivors-displaced)*100000/survivors if survivors>0 else 100000
	if not row.get("operating",false): services=0
	var needed := TourismEconomy.requirements(StringName(row.key),maxi(opening,int(row.guests)),int(row.day_visitors))
	var positions := needed[0]+needed[1]+needed[2]
	var filled := int(row.get("local_staff",0))+int(row.get("incoming_staff",0))
	var staffing := mini(100000,filled*100000/positions) if positions>0 else 100000
	var reachable: bool=row.get("external_reachable",false) or row.get("local_reachable",false)
	var needs := [100000-clampi(int(row.get("crime",0)),0,255)*100000/255,
		100000-clampi(traffic,0,255)*100000/255 if reachable else 0,
		clampi(int(row.get("attraction_appeal_bonus",0)),0,TourismParams.DISTRICT_APPEAL_CAP)*100000/TourismParams.DISTRICT_APPEAL_CAP,
		staffing,services]
	var scores := []
	for weights: Array in TourismParams.EXPERIENCE_WEIGHTS:
		var score := 0
		for i in NEEDS.size(): score+=int(needs[i])*int(weights[i])
		score/=100
		if TourismParams.ESSENTIAL_SERVICE_EXPERIENCE_CEILING: score=mini(score,services)
		scores.append(score)
	return {"needs_milli":needs,"segment_scores_milli":scores}

@warning_ignore("integer_division")
static func completed(rows: Array[Dictionary], month: int, traffic: int) -> Dictionary:
	var numerator := 0
	var units := 0
	for row in rows:
		var experience := venue_experience(row,traffic)
		for segment in 4:
			var weight := int(row.guest_half_segments[segment])+2*int(row.day_segments[segment])
			units+=weight
			numerator+=weight*int(experience.segment_scores_milli[segment])
	return {"month_id":month,"value_milli":numerator/units if units>0 else -1,"visitor_half_units":units}

## Shared native/cloud detached validation. Old two-field phase placeholders
## migrate only from their actual neutral default; old earnings stay untouched.
static func decode(value: Dictionary, block: Dictionary, month: int) -> Dictionary:
	if value.is_empty(): return {"ok":true,"value":initial(month)}
	if value.size()==2 and TourismState._integer(value.get("value_milli"),NEUTRAL,NEUTRAL) and TourismState._integer(value.get("empty_months"),0,0):
		return {"ok":true,"value":initial(month)}
	if value.size()!=11 or value.get("profile")!=PROFILE: return {"ok":false}
	var ranges := {"activation_month":[0,month],"month_id":[-1,month],"value_milli":[0,100000],
		"quarter_remainder":[-3,3],"empty_months":[0,TourismParams.MAX_COUNT],"opening_milli":[0,100000],
		"opening_remainder":[-3,3],"opening_empty_months":[0,TourismParams.MAX_COUNT],
		"experience_milli":[-1,100000],"visitor_half_units":[0,TourismState.MAX_INSTANCE]}
	var result := value.duplicate(true)
	for field in ranges:
		if not TourismState._integer(result.get(field),ranges[field][0],ranges[field][1]): return {"ok":false}
		result[field]=int(result[field])
	if result.month_id==-1:
		return {"ok":result==initial(result.activation_month),"value":result}
	if result.month_id<int(result.activation_month) or result.month_id!=int(block.get("last_month",-1)): return {"ok":false}
	if int(result.opening_empty_months)>int(result.month_id)-int(result.activation_month): return {"ok":false}
	if TourismSystem.activity_profile(block)!=TourismMarkets.PROFILE: return {"ok":false}
	var units := 0
	for row: Dictionary in block.get("activity",{}).get("rows",[]):
		units+=int(row.guest_half_months)+2*int(row.day_visitors)
	if units!=int(result.visitor_half_units): return {"ok":false}
	if (units==0)!=(int(result.experience_milli)==-1): return {"ok":false}
	var prior := initial(result.activation_month)
	prior.value_milli=result.opening_milli
	prior.quarter_remainder=result.opening_remainder
	prior.empty_months=result.opening_empty_months
	var expected := advance(prior,{"month_id":result.month_id,"value_milli":result.experience_milli},units)
	return {"ok":expected==result,"value":result}
