# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Accepted visitor demand only; no admission, generation, storage or RNG.
## The cache compares native layers and bounded venue identities, never networks.
class_name TourismUtilities
extends RefCounted

var rows: Array = []
var values := PackedInt32Array()
var units := 0
var _buildings := PackedInt32Array()
var _zones := PackedByteArray()
var _tokens: Array = []
var _water := false

## Exact fractional guest+day request, rounded UP once for the whole venue.
## Guest load is twice day load; tiers are independent of segment spending.
static func request(row: Dictionary, water: bool) -> int:
	if not bool(row.get("operating",true)): return 0
	var multiplier: int = [100,125,150][TourismMarkets.tier(StringName(row.key))]
	var numerator := (2 * int(row.get("guests",0)) + int(row.get("day_visitors",0))) * multiplier
	var denominator := 4000 if water else 8000
	@warning_ignore("integer_division")
	return (numerator + denominator - 1) / denominator

static func _standing(city: City, row: Dictionary) -> bool:
	var code := Buildings.id_of(StringName(row.key))
	if (TourismParams.guest_capacity(StringName(row.key)) == 0 and TourismParams.day_capacity(StringName(row.key)) == 0) or code != int(row.get("code",code)):
		return false
	if not TourismState._standing(city,row.anchor,code): return false
	# Accepted state has an adopted instance even for imported lots. Missing
	# size/facing/key metadata is irrelevant; absent/replaced identity is not.
	return not row.has("instance") or city.facility(row.anchor).get("tourism_instance",-1) == row.instance

static func overlay(city: City, input: Array, water: bool) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(City.WIDTH * City.HEIGHT)
	for row: Dictionary in input:
		if not _standing(city,row): continue
		var size := Buildings.size(Buildings.id_of(StringName(row.key)))
		var count := size.x * size.y
		var requested := request(row,water)
		@warning_ignore("integer_division")
		var share := requested / count
		var remainder := requested % count
		for dy in size.y:
			for dx in size.x:
				var index: int = (row.anchor.y+dy)*City.WIDTH+row.anchor.x+dx
				result[index] += share + (1 if dy*size.x+dx < remainder else 0)
	return result

func accept(city: City, input: Array, water: bool) -> void:
	var tokens: Array = []
	for row: Dictionary in input: tokens.append(city.facility(row.anchor).get("tourism_instance",-1))
	if values.size() == City.WIDTH*City.HEIGHT and rows == input and _water == water \
			and _buildings == city.building.data and _zones == city.zone.data and _tokens == tokens:
		return
	rows = input.duplicate(true)
	_water = water
	_tokens = tokens
	_buildings = city.building.data.duplicate()
	_zones = city.zone.data.duplicate()
	values = overlay(city,rows,water)
	units = 0
	for row: Dictionary in rows:
		if _standing(city,row): units += request(row,water)


## A standing rectangular venue conducts internally, hence belongs to exactly
## one component per utility. Require the entire footprint, not just its anchor.
static func _component(city: City, row: Dictionary, budget: Dictionary) -> int:
	if not _standing(city,row): return -1
	var labels: PackedInt32Array = budget.tiles
	var component: int = labels[row.anchor.y*City.WIDTH+row.anchor.x]
	if component < 0: return -1
	var size := Buildings.size(Buildings.id_of(StringName(row.key)))
	for dy in size.y:
		for dx in size.x:
			if labels[(row.anchor.y+dy)*City.WIDTH+row.anchor.x+dx] != component: return -1
	return component

## Joint, conservative proportional shortfall: each network grants exact
## rounded units to its own venues, then each venue accepts only attendance
## supported by BOTH grants. Release unusable grants, then fill joint residual
## capacity in canonical order. This produces a feasible maximal allocation:
## no remaining venue can add a visitor without reducing another venue.
## Work is O(map + venues log venues), independent of visitor counts.
static func admission_plan(city: City, input: Array, power_budget: Dictionary, water_budget: Dictionary, fixed_days: bool = false) -> Dictionary:
	if fixed_days: return _fixed_day_plan(city,input,power_budget,water_budget)
	var ordered: Array[Dictionary] = []
	ordered.assign(input.duplicate(true))
	ordered.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.anchor.y*City.WIDTH+a.anchor.x < b.anchor.y*City.WIDTH+b.anchor.x)
	var desired_rows: Array[Dictionary] = ordered.duplicate(true)
	var checks := 0
	var grants: Array = []
	var memberships: Array = []
	var reserved: Array = []
	for water in [false,true]:
		var budget := water_budget if water else power_budget
		var groups := {}
		var membership := PackedInt32Array()
		membership.resize(ordered.size())
		membership.fill(-1)
		var allowed := PackedInt64Array()
		allowed.resize(ordered.size())
		var used := PackedInt64Array()
		used.resize(budget.components.size())
		for i in ordered.size():
			var component := _component(city,ordered[i],budget)
			membership[i] = component
			if component < 0: continue
			if not groups.has(component): groups[component] = []
			groups[component].append(i)
		for component: int in groups:
			var wanted := PackedInt64Array()
			for i: int in groups[component]: wanted.append(request(ordered[i],water))
			var shares := TourismDemand.allocate(wanted,int(budget.components[component].spare))
			for j in shares.size(): allowed[groups[component][j]] = shares[j]
		grants.append(allowed)
		memberships.append(membership)
		reserved.append(used)
	for i in ordered.size():
		var row := ordered[i]
		var desired := PackedInt64Array([int(row.guests),int(row.day_visitors)])
		var low := 0
		var high := int(row.guests)+int(row.day_visitors)
		if not bool(row.get("operating",true)): high = 0
		var reason := ""
		if request(row,false)>grants[0][i] or memberships[0][i]<0: reason = "power"
		if request(row,true)>grants[1][i] or memberships[1][i]<0: reason = "water" if reason.is_empty() else "power and water"
		while low < high:
			checks += 1
			@warning_ignore("integer_division")
			var mid := (low+high+1)/2
			var counts := TourismDemand.allocate(desired,mid)
			var trial := {"key":row.key,"guests":counts[0],"day_visitors":counts[1]}
			if request(trial,false)<=grants[0][i] and request(trial,true)<=grants[1][i]: low = mid
			else: high = mid-1
		var accepted := TourismDemand.allocate(desired,low)
		row.guests = accepted[0]
		row.day_visitors = accepted[1]
		row["utility_supported_guests"] = accepted[0]
		row["utility_supported_days"] = accepted[1]
		row["utility_limiting_reason"] = reason
		for water in [false,true]:
			var index := 1 if water else 0
			if memberships[index][i]>=0: reserved[index][memberships[index][i]] += request(row,water)
	# Both resource grants are released before residual filling. Charging actual
	# rounded requests, never independent promises, recovers crossed leftovers.
	for i in ordered.size():
		var row := ordered[i]
		var desired_row := desired_rows[i]
		var pc: int = memberships[0][i]
		var wc: int = memberships[1][i]
		if pc<0 or wc<0 or not bool(row.get("operating",true)): continue
		var old_power := request(row,false)
		var old_water := request(row,true)
		var power_limit := int(power_budget.components[pc].spare)-int(reserved[0][pc])+old_power
		var water_limit := int(water_budget.components[wc].spare)-int(reserved[1][wc])+old_water
		var desired := PackedInt64Array([int(desired_row.guests),int(desired_row.day_visitors)])
		var low := int(row.guests)+int(row.day_visitors)
		var high := int(desired_row.guests)+int(desired_row.day_visitors)
		while low<high:
			checks += 1
			@warning_ignore("integer_division")
			var mid := (low+high+1)/2
			var counts := TourismDemand.allocate(desired,mid)
			var trial := {"key":row.key,"guests":counts[0],"day_visitors":counts[1]}
			if request(trial,false)<=power_limit and request(trial,true)<=water_limit: low=mid
			else: high=mid-1
		var counts := TourismDemand.allocate(desired,low)
		# Rounding can leave one day place even when the next proportional
		# increment contains an overnight guest. Fill that final whole place
		# arithmetically (guests then days), with no per-visitor loop.
		var tier: int = [100,125,150][TourismMarkets.tier(StringName(row.key))]
		@warning_ignore("integer_division")
		var weighted_limit := mini(power_limit*8000/tier,water_limit*4000/tier)
		var room := maxi(0,weighted_limit-2*counts[0]-counts[1])
		@warning_ignore("integer_division")
		var extra_guests := mini(desired[0]-counts[0],room/2)
		counts[0] += extra_guests
		room -= 2*extra_guests
		counts[1] += mini(desired[1]-counts[1],room)
		row.guests = counts[0]
		row.day_visitors = counts[1]
		row.utility_supported_guests = counts[0]
		row.utility_supported_days = counts[1]
		var reason := ""
		if request(desired_row,false)>power_limit: reason = "power"
		if request(desired_row,true)>water_limit: reason = "water" if reason.is_empty() else "power and water"
		row.utility_limiting_reason = reason
		reserved[0][pc] += request(row,false)-old_power
		reserved[1][wc] += request(row,true)-old_water
	return {"rows":ordered,"power_reserved":reserved[0],"water_reserved":reserved[1],"reservation_checks":checks}


## Authoritative reservation is the live accepted overlay, not a serialized
## network graph. Closing/removal updates it without touching earned business.
static func snapshot(rows: Array, previous: Array = []) -> Array:
	var prior := {}
	for item: Dictionary in previous: prior[int(item.instance)] = item
	var result: Array = []
	for row: Dictionary in rows:
		if not row.operating: continue
		var old: Dictionary = prior.get(int(row.instance),{})
		result.append({"instance":int(row.instance),"power":request(row,false),"water":request(row,true),
			"supported_guests":int(row.guests),"supported_days":int(row.day_visitors),
			"limiting_reason":String(row.get("utility_limiting_reason",old.get("limiting_reason",""))),
			"resource_departures":int(row.get("resource_departures",old.get("resource_departures",0)))})
	return result

static func decode(value: Dictionary, block: Dictionary, month: int) -> Dictionary:
	if value.is_empty(): return {"ok":true,"value":{}}
	if value.size()!=4 or value.get("profile")!="utility_20261015" or not value.get("rows") is Array: return {"ok":false}
	if not TourismState._integer(value.get("activation_month"),0,month) or not TourismState._integer(value.get("month_id"),-1,month): return {"ok":false}
	if int(value.month_id)!=int(block.get("last_month",-1)): return {"ok":false}
	var state: Variant = block.get("state")
	if not state is Dictionary or not TourismState._integer(state.get("schema"),1,TourismState.SCHEMA): return {"ok":false}
	var checked := TourismState._validate_rows(state.get("records"),true,int(state.schema)==1)
	if not checked.ok: return {"ok":false}
	var known := {}
	for row: Dictionary in checked.rows:
		if row.operating: known[int(row.instance)] = row
	if value.rows.size()!=known.size(): return {"ok":false}
	var seen := {}
	var result := value.duplicate(true)
	for item: Variant in result.rows:
		if not item is Dictionary or item.size()!=7 or not TourismState._integer(item.get("instance"),1,TourismState.MAX_INSTANCE-1): return {"ok":false}
		var id := int(item.instance)
		if seen.has(id) or not known.has(id): return {"ok":false}
		seen[id] = true
		item.instance = id
		for field in ["power","water","supported_guests","supported_days","resource_departures"]:
			if not TourismState._integer(item.get(field),0,TourismParams.MAX_COUNT): return {"ok":false}
			item[field] = int(item[field])
		var row: Dictionary = known[id]
		if item.supported_guests!=int(row.guests) or item.supported_days!=int(row.day_visitors): return {"ok":false}
		if item.power!=request(row,false) or item.water!=request(row,true): return {"ok":false}
		if not item.get("limiting_reason") is String or item.limiting_reason not in ["","power","water","power and water"]: return {"ok":false}
		if item.resource_departures>int(row.departures) or (item.resource_departures>0 and item.limiting_reason.is_empty()): return {"ok":false}
	result.activation_month = int(result.activation_month)
	result.month_id = int(result.month_id)
	return {"ok":true,"value":result}

## Convention-only prospective capacity. Fixed accepted day obligations are
## charged before dividing additional guest demand; live admission never uses
## this mode. Infeasible day components promise no guests or reservations.
static func _fixed_day_plan(city: City, input: Array, power: Dictionary, water: Dictionary) -> Dictionary:
	var rows: Array[Dictionary]=[]
	rows.assign(input.duplicate(true))
	rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.anchor.y*City.WIDTH+a.anchor.x<b.anchor.y*City.WIDTH+b.anchor.x)
	var membership: Array=[]
	var grants: Array=[]
	var reserved: Array=[]
	var invalid: Array=[]
	for wet in [false,true]:
		var budget := water if wet else power
		var members := PackedInt32Array()
		var bases := PackedInt64Array()
		bases.resize(budget.components.size())
		var allocation := PackedInt64Array()
		allocation.resize(rows.size())
		var groups := {}
		for i in rows.size():
			var component := _component(city,rows[i],budget) if bool(rows[i].get("operating",true)) else -1
			members.append(component)
			if component<0: continue
			if not groups.has(component): groups[component]=[]
			groups[component].append(i)
			bases[component]+=request({"key":rows[i].key,"guests":0,"day_visitors":rows[i].day_visitors},wet)
		var impossible := {}
		for component: int in groups:
			if bases[component]>int(budget.components[component].spare):
				impossible[component]=true
				continue
			var wanted := PackedInt64Array()
			for i: int in groups[component]:
				wanted.append(request(rows[i],wet)-request({"key":rows[i].key,"guests":0,"day_visitors":rows[i].day_visitors},wet))
			var shares := TourismDemand.allocate(wanted,int(budget.components[component].spare)-bases[component])
			for j in shares.size():
				var i: int=groups[component][j]
				allocation[i]=shares[j]+request({"key":rows[i].key,"guests":0,"day_visitors":rows[i].day_visitors},wet)
		membership.append(members)
		grants.append(allocation)
		var used := PackedInt64Array()
		used.resize(budget.components.size())
		for component in bases.size():
			if not impossible.has(component): used[component]=bases[component]
		reserved.append(used)
		invalid.append(impossible)
	var desired := rows.duplicate(true)
	var checks := 0
	for i in rows.size():
		var row := rows[i]
		var pc: int=membership[0][i]
		var wc: int=membership[1][i]
		var feasible: bool=pc>=0 and wc>=0 and not invalid[0].has(pc) and not invalid[1].has(wc)
		row["fixed_days_feasible"]=feasible
		if not feasible:
			row.guests=0
			row.day_visitors=0 # No hypothetical reservation can be promised.
			continue
		var result := _fixed_guest_limit(row,int(row.guests),int(grants[0][i]),int(grants[1][i]))
		row.guests=result.guests
		checks+=int(result.checks)
		reserved[0][pc]+=request(row,false)-request({"key":row.key,"guests":0,"day_visitors":row.day_visitors},false)
		reserved[1][wc]+=request(row,true)-request({"key":row.key,"guests":0,"day_visitors":row.day_visitors},true)
	for i in rows.size():
		var row := rows[i]
		if not row.fixed_days_feasible: continue
		var pc: int=membership[0][i]
		var wc: int=membership[1][i]
		var old_power := request(row,false)
		var old_water := request(row,true)
		var result := _fixed_guest_limit(row,int(desired[i].guests),int(power.components[pc].spare)-reserved[0][pc]+old_power,int(water.components[wc].spare)-reserved[1][wc]+old_water)
		row.guests=result.guests
		checks+=int(result.checks)
		reserved[0][pc]+=request(row,false)-old_power
		reserved[1][wc]+=request(row,true)-old_water
	return {"rows":rows,"power_reserved":reserved[0],"water_reserved":reserved[1],"reservation_checks":checks}

static func _fixed_guest_limit(row: Dictionary, guests: int, power: int, water: int) -> Dictionary:
	var low := 0
	var high := guests
	var checks := 0
	while low<high:
		checks+=1
		@warning_ignore("integer_division")
		var mid := (low+high+1)/2
		var trial := {"key":row.key,"guests":mid,"day_visitors":row.day_visitors}
		if request(trial,false)<=power and request(trial,true)<=water: low=mid
		else: high=mid-1
	return {"guests":low,"checks":checks}
