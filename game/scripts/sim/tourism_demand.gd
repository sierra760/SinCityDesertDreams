# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Pure deterministic forecasts. No clock, RNG, city mutation or treasury writes.
class_name TourismDemand
extends RefCounted


## Proportional floors followed by canonical-order remainders. Callers provide
## canonical order; every awarded remainder stays within that venue's demand.
static func allocate(desired: PackedInt64Array, pool: int) -> PackedInt64Array:
	var result := PackedInt64Array()
	var total := 0
	for value in desired:
		var count := _count(value)
		result.append(count)
		total += count
	pool = _count(pool)
	if total <= pool:
		return result
	if pool == 0:
		result.fill(0)
		return result
	var assigned := 0
	for i in result.size():
		result[i] = result[i] * pool / total
		assigned += result[i]
	var remaining := pool - assigned
	for i in result.size():
		if remaining == 0:
			break
		if result[i] < _count(desired[i]):
			result[i] += 1
			remaining -= 1
	return result


static func turnover(guests: int, target: int) -> Dictionary:
	guests = _count(guests)
	target = _count(target)
	var departures := (guests + TourismParams.TURNOVER_DIVISOR - 1) / TourismParams.TURNOVER_DIVISOR
	var remaining := guests - departures
	var admission_cap := (target + TourismParams.TURNOVER_DIVISOR - 1) / TourismParams.TURNOVER_DIVISOR
	var arrivals := mini(maxi(0, target - remaining), admission_cap)
	return {"guests": remaining + arrivals, "arrivals": arrivals, "departures": departures}


static func business_bases(opening_guests: int, closing_guests: int, day_visitors: int) -> Dictionary:
	var half_months := _count(opening_guests) + _count(closing_guests)
	return {
		"lodging_cents": half_months * TourismParams.LODGING_CENTS_PER_HALF_GUEST,
		"gaming_cents": half_months * TourismParams.GAMING_CENTS_PER_HALF_GUEST + _count(day_visitors) * TourismParams.GAMING_CENTS_PER_VISITOR,
	}


## Returns settled targets and activity; live turnover is deliberately separate.
## Rows use local land_value/crime/pollution and an already-reconciled operating
## flag. Known capacities are always derived from the venue roster.
static func forecast(rows: Array[Dictionary], inputs: Dictionary, occupancy_rate: int, gaming_rate: int, utility_city: City = null, power_budget: Dictionary = {}, water_budget: Dictionary = {}) -> Dictionary:
	var ordered: Array[Dictionary] = rows.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: Vector2i = a.get("anchor", Vector2i.ZERO)
		var right: Vector2i = b.get("anchor", Vector2i.ZERO)
		return left.y * City.WIDTH + left.x < right.y * City.WIDTH + right.x)
	var bonus := 0
	if inputs.get("tourist_advertising", false):
		bonus += TourismParams.ADVERTISING_APPEAL
	var city_appeal := _appeal(inputs.get("average_land_value", 0), inputs.get("average_crime", 0), inputs.get("average_pollution", 0), inputs.get("average_traffic", 0), bonus)
	var neighbors := 0
	var neighbor_values: Variant = inputs.get("neighbor_populations", [])
	if neighbor_values is Array or neighbor_values is PackedInt64Array or neighbor_values is PackedInt32Array:
		for value: Variant in neighbor_values:
			neighbors = mini(neighbors + _count(value), TourismParams.NEIGHBOR_POOL_CAP * TourismParams.NEIGHBOR_DIVISOR)
	var raw_pool := TourismParams.BASE_POOL + _count(inputs.get("permanent_population", 0)) / TourismParams.POPULATION_DIVISOR + neighbors / TourismParams.NEIGHBOR_DIVISOR
	var phase := clampi(_count(inputs.get("economy_phase", 2)), 0, TourismParams.ECONOMY_PERCENT.size() - 1)
	var access_enabled := inputs.has("gateways")
	var gateway_types := {}
	var connected_ids := {}
	for row in ordered:
		if row.get("operating",false):
			for id: String in row.get("gateway_ids",[]): connected_ids[id] = true
	for gateway: Dictionary in inputs.get("gateways",[]):
		if connected_ids.has(gateway.id) and gateway.kind in ["rail","airport","harbor"]: gateway_types[gateway.kind] = true
	var reach_bonus := [0,25,40,50][mini(3,gateway_types.size())] as int
	var economy_pool: int = raw_pool * TourismParams.ECONOMY_PERCENT[phase] / TourismParams.PERCENT
	if access_enabled: economy_pool = economy_pool * (100+reach_bonus) / 100
	var guest_pool := economy_pool * city_appeal / TourismParams.PERCENT
	var day_pool := (economy_pool / TourismParams.DAY_POOL_DIVISOR) * city_appeal / TourismParams.PERCENT
	guest_pool = guest_pool * clampi(int(inputs.get("season_percent",100)),0,200) / 100
	day_pool = day_pool * clampi(int(inputs.get("season_percent",100)),0,200) / 100
	var reputation := clampi(int(inputs.get("reputation_factor_milli",100000)),75000,120000)
	guest_pool = guest_pool * reputation / 100000
	day_pool = day_pool * reputation / 100000
	var capacity := 0
	for row in ordered:
		var key := StringName(row.get("key", &""))
		var guests_cap := TourismParams.guest_capacity(key)
		var day_cap := TourismParams.day_capacity(key)
		var local_appeal := _appeal(row.get("land_value", 0), row.get("crime", 0), row.get("pollution", 0), inputs.get("average_traffic", 0), bonus + clampi(int(row.get("district_appeal_bonus", 0)), 0, TourismParams.DISTRICT_APPEAL_CAP + TourismParams.RESORT_VARIETY_CAP))
		row["capacity"] = guests_cap
		row["day_capacity"] = day_cap
		row["appeal"] = local_appeal
		var operating: bool = row.get("operating", false)
		if operating:
			capacity += guests_cap
	var market_inputs := inputs.duplicate(true)
	market_inputs.merge({"guest_pool":guest_pool,"day_pool":day_pool,"access_enabled":access_enabled},true)
	var markets := TourismMarkets.allocate(ordered,market_inputs,occupancy_rate,gaming_rate)
	ordered.assign(markets.rows)
	guest_pool = markets.guest_pool
	day_pool = markets.day_pool
	var guest_targets := PackedInt64Array()
	var day_targets := PackedInt64Array()
	for row in ordered:
		guest_targets.append(TourismMarkets.sum_counts(row.target_guest_segments))
		day_targets.append(TourismMarkets.sum_counts(row.target_day_segments))
	var reservations := PackedInt64Array()
	var local_days := PackedInt64Array()
	var external_days := PackedInt64Array()
	if access_enabled:
		var local_desired := PackedInt64Array()
		for i in ordered.size(): local_desired.append(day_targets[i] if ordered[i].get("local_reachable",false) else 0)
		# Resident-only finite demand cannot borrow the founding regional floor.
		var local_pool := mini(day_pool,_count(inputs.get("permanent_population",0)) / TourismParams.POPULATION_DIVISOR / TourismParams.DAY_POOL_DIVISOR)
		local_days = allocate(local_desired,local_pool)
		var wanted_arrivals := PackedInt64Array()
		var wanted_external := PackedInt64Array()
		reservations.resize(ordered.size())
		external_days.resize(ordered.size())
		for i in ordered.size():
			ordered[i]["gateway_reservations"] = []
			wanted_arrivals.append(turnover(int(ordered[i].get("guests",0)),guest_targets[i]).arrivals)
			wanted_external.append(day_targets[i]-local_days[i] if ordered[i].get("external_reachable",false) else 0)
		for gateway: Dictionary in inputs.get("gateways",[]):
			var requests := PackedInt64Array()
			for i in ordered.size():
				requests.append(wanted_arrivals[i]+wanted_external[i] if gateway.id in ordered[i].get("gateway_ids",[]) else 0)
			var seats := allocate(requests,int(gateway.capacity))
			for i in ordered.size():
				var split := allocate(PackedInt64Array([wanted_arrivals[i],wanted_external[i]]),seats[i])
				if split[0]+split[1] > 0:
					ordered[i].gateway_reservations.append({"id":String(gateway.id),"count":split[0]+split[1]})
				reservations[i] += split[0]
				external_days[i] += split[1]
				wanted_arrivals[i] -= split[0]
				wanted_external[i] -= split[1]
		for i in ordered.size(): day_targets[i] = local_days[i]+external_days[i]
	# Demand targets are independent of current occupancy; an empty resort can
	# recover. Gateway seat limits precede the shared labor calculation.
	var staffing := {}
	if inputs.has("resident_workers"):
		# A separate settled plan uses potential admissions, never this month's
		# remaining guests. Existing occupancy cannot suppress future positions.
		var feasible_guests := guest_targets.duplicate()
		if access_enabled:
			feasible_guests.fill(0)
			var wanted := PackedInt64Array()
			var wanted_days := external_days.duplicate()
			for target in guest_targets: wanted.append((target+TourismParams.TURNOVER_DIVISOR-1)/TourismParams.TURNOVER_DIVISOR)
			for gateway: Dictionary in inputs.get("gateways",[]):
				var requests := PackedInt64Array()
				for i in ordered.size(): requests.append(wanted[i]+wanted_days[i] if gateway.id in ordered[i].get("gateway_ids",[]) else 0)
				var seats := allocate(requests,int(gateway.capacity))
				for i in ordered.size():
					var split := allocate(PackedInt64Array([wanted[i],wanted_days[i]]),seats[i])
					feasible_guests[i] += split[0]*TourismParams.TURNOVER_DIVISOR
					wanted[i] -= split[0]
					wanted_days[i] -= split[1]
		for i in ordered.size():
			ordered[i]["target_guests"] = mini(guest_targets[i],maxi(int(ordered[i].get("guests",0)),feasible_guests[i]))
			ordered[i]["target_day_visitors"] = day_targets[i]
		# Accepted work is prospective, not current occupancy. Reserve the same
		# joint component budgets before assigning finite workers, so impossible
		# variable work cannot take labor away from a serviceable neighbor.
		# Reports omit these detached budgets and remain counterfactual/pure.
		if utility_city != null:
			var requests: Array[Dictionary] = ordered.duplicate(true)
			for row in requests:
				row.guests = row.target_guests
				row.day_visitors = row.target_day_visitors
			var feasible := TourismUtilities.admission_plan(utility_city,requests,power_budget,water_budget)
			for i in ordered.size():
				ordered[i].target_guests = feasible.rows[i].guests
				ordered[i].target_day_visitors = feasible.rows[i].day_visitors
				ordered[i]["planned_utility_limiting_reason"] = feasible.rows[i].get("utility_limiting_reason","")
		staffing = TourismEconomy.allocate(ordered,int(inputs.resident_workers),int(inputs.get("non_tourism_jobs",0)),inputs)
		ordered.assign(staffing.rows)
		for i in ordered.size():
			var row := ordered[i]
			guest_targets[i] = row.supported_capacity
			day_targets[i] = row.supported_day_capacity
			if bool(inputs.get("staffing_grace",false)):
				guest_targets[i] = maxi(guest_targets[i],mini(int(row.get("guests",0)),int(row.planned_guests)))
				day_targets[i] = maxi(day_targets[i],mini(int(row.get("day_visitors",0)),int(row.planned_day_visitors)))
			row.target_guest_segments = TourismMarkets.partition(guest_targets[i],row.target_guest_segments)
			if access_enabled:
				reservations[i] = mini(reservations[i],TourismDemand.turnover(int(row.get("guests",0)),guest_targets[i]).arrivals)
				var day_split := allocate(PackedInt64Array([local_days[i],external_days[i]]),day_targets[i])
				local_days[i] = day_split[0]
				external_days[i] = day_split[1]
				var previous := PackedInt64Array()
				for item: Dictionary in row.gateway_reservations: previous.append(item.count)
				var kept := allocate(previous,reservations[i]+external_days[i])
				for j in kept.size(): row.gateway_reservations[j].count = kept[j]
				row.gateway_reservations = row.gateway_reservations.filter(func(item: Dictionary) -> bool: return item.count > 0)
	var guests := 0
	var day_visitors := 0
	var lodging_cents := 0
	var gaming_cents := 0
	var lodging_numerator := 0
	var gaming_numerator := 0
	var projected_mix_exact := true
	for i in ordered.size():
		var row := ordered[i]
		row["target_guests"] = guest_targets[i]
		row["target_day_visitors"] = day_targets[i]
		# With rounded-up departures and admissions capped at half the target,
		# an even target approached from below stabilizes one guest short.
		# Preserve the supplied current counts: projections are separate fields.
		var projected := guest_targets[i]
		if projected > 0 and projected % TourismParams.TURNOVER_DIVISOR == 0 and _count(row.get("guests", 0)) < projected:
			projected -= 1
		if access_enabled:
			row["arrival_reservation"] = reservations[i]
			row["local_day_visitors"] = local_days[i]
			row["external_day_visitors"] = external_days[i]
			var current := _count(row.get("guests",0))
			var remaining := current - (current+TourismParams.TURNOVER_DIVISOR-1)/TourismParams.TURNOVER_DIVISOR
			projected = mini(projected,maxi(remaining+reservations[i],mini(projected,reservations[i]*TourismParams.TURNOVER_DIVISOR))) if inputs.has("resident_workers") else maxi(remaining+reservations[i],mini(projected,reservations[i]*TourismParams.TURNOVER_DIVISOR))
		row["projected_guests"] = projected
		row["projected_day_visitors"] = day_targets[i]
		row["guest_segments"] = TourismMarkets.counts(row)
		row["day_segments"] = TourismMarkets.counts(row,true)
		var mixture := TourismMarkets.project(row.guest_segments,row.target_guest_segments,projected,int(row.get("arrival_reservation",-1)))
		row["projected_guest_segments"] = mixture.segments
		row["forecast_mix_basis"] = mixture.basis
		projected_mix_exact = projected_mix_exact and bool(mixture.exact)
		row["target_day_segments"] = TourismMarkets.partition(day_targets[i],row.target_day_segments)
		row["projected_day_segments"] = row.target_day_segments.duplicate()
		var bases := TourismMarkets.business(row.projected_guest_segments,row.projected_guest_segments,row.projected_day_segments,row.key)
		lodging_numerator += int(bases.lodging_numerator)
		gaming_numerator += int(bases.gaming_numerator)
		row.merge(bases, true)
		guests += projected
		day_visitors += day_targets[i]
		lodging_cents += int(bases["lodging_cents"])
		gaming_cents += int(bases["gaming_cents"])
	return {"rows": ordered, "staffing": staffing, "guest_pool": guest_pool, "day_pool": day_pool,
		"guests": guests, "day_visitors": day_visitors, "capacity": capacity,
		"occupancy": guests * TourismParams.PERCENT / capacity if capacity > 0 else 0,
		"lodging_cents": lodging_numerator / TourismMarkets.BUSINESS_DENOMINATOR, "gaming_cents": gaming_numerator / TourismMarkets.BUSINESS_DENOMINATOR,
		"lodging_numerator":lodging_numerator,"gaming_numerator":gaming_numerator,"forecast_mix_basis":"turnover_projection" if projected_mix_exact else "estimated_target_mix","forecast_mix_exact":projected_mix_exact,"guest_pools":markets.guest_pools,"day_pools":markets.day_pools,
		"explanation": "City appeal %d%%; segment-specific tax response; finite pools %d guests / %d day visitors. Business forecast projects integer guest turnover at fixed current settings.%s" % [city_appeal, guest_pool, day_pool,"" if projected_mix_exact else " Some mixes reached the bounded projection limit and use approximate target shares."]}


static func _appeal(land_value: Variant, crime: Variant, pollution: Variant, traffic: Variant, bonus: int) -> int:
	# Common denominator retains fractions until one final division. The three
	# local divisors are eight; congestion uses sixteen.
	var scale := TourismParams.TRAFFIC_DIVISOR
	var numerator := (TourismParams.APPEAL_BASE + bonus) * scale
	numerator += _count(land_value) * (scale / TourismParams.LAND_VALUE_DIVISOR)
	numerator -= _count(crime) * (scale / TourismParams.CRIME_DIVISOR)
	numerator -= _count(pollution) * (scale / TourismParams.POLLUTION_DIVISOR)
	numerator -= _count(traffic)
	return clampi(numerator / scale, TourismParams.APPEAL_MIN, TourismParams.APPEAL_MAX)


static func _count(value: Variant) -> int:
	if value is int:
		return clampi(value, 0, TourismParams.MAX_COUNT)
	if value is float and is_finite(value):
		return int(clampf(value, 0.0, float(TourismParams.MAX_COUNT)))
	return 0
