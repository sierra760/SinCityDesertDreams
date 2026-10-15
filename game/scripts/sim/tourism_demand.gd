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
static func forecast(rows: Array[Dictionary], inputs: Dictionary, occupancy_rate: int, gaming_rate: int) -> Dictionary:
	var ordered: Array[Dictionary] = rows.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: Vector2i = a.get("anchor", Vector2i.ZERO)
		var right: Vector2i = b.get("anchor", Vector2i.ZERO)
		return left.y * City.WIDTH + left.x < right.y * City.WIDTH + right.x)
	var occupancy_factor := maxi(0, TourismParams.PERCENT - TourismParams.OCCUPANCY_TAX_DISCOURAGEMENT * clampi(occupancy_rate, TourismParams.TAX_MIN, TourismParams.TAX_MAX))
	var gaming_factor := maxi(0, TourismParams.PERCENT - TourismParams.GAMING_TAX_DISCOURAGEMENT * clampi(gaming_rate, TourismParams.TAX_MIN, TourismParams.TAX_MAX))
	var bonus := 0
	if inputs.get("tourist_advertising", false):
		bonus += TourismParams.ADVERTISING_APPEAL
	if inputs.get("annual_carnival", false):
		bonus += TourismParams.CARNIVAL_APPEAL
	var city_appeal := _appeal(inputs.get("average_land_value", 0), inputs.get("average_crime", 0), inputs.get("average_pollution", 0), inputs.get("average_traffic", 0), bonus)
	var neighbors := 0
	var neighbor_values: Variant = inputs.get("neighbor_populations", [])
	if neighbor_values is Array or neighbor_values is PackedInt64Array or neighbor_values is PackedInt32Array:
		for value: Variant in neighbor_values:
			neighbors = mini(neighbors + _count(value), TourismParams.NEIGHBOR_POOL_CAP * TourismParams.NEIGHBOR_DIVISOR)
	var raw_pool := TourismParams.BASE_POOL + _count(inputs.get("permanent_population", 0)) / TourismParams.POPULATION_DIVISOR + neighbors / TourismParams.NEIGHBOR_DIVISOR
	var phase := clampi(_count(inputs.get("economy_phase", 2)), 0, TourismParams.ECONOMY_PERCENT.size() - 1)
	var economy_pool: int = raw_pool * TourismParams.ECONOMY_PERCENT[phase] / TourismParams.PERCENT
	var guest_pool := economy_pool * city_appeal * occupancy_factor * gaming_factor / (TourismParams.PERCENT * TourismParams.PERCENT * TourismParams.PERCENT)
	var day_pool := (economy_pool / TourismParams.DAY_POOL_DIVISOR) * city_appeal * gaming_factor / (TourismParams.PERCENT * TourismParams.PERCENT)
	var desired_guests := PackedInt64Array()
	var desired_day := PackedInt64Array()
	var capacity := 0
	for row in ordered:
		var key := StringName(row.get("key", &""))
		var guests_cap := TourismParams.guest_capacity(key)
		var day_cap := TourismParams.day_capacity(key)
		var local_appeal := _appeal(row.get("land_value", 0), row.get("crime", 0), row.get("pollution", 0), inputs.get("average_traffic", 0), bonus)
		row["capacity"] = guests_cap
		row["day_capacity"] = day_cap
		row["appeal"] = local_appeal
		var operating: bool = row.get("operating", false)
		if operating:
			capacity += guests_cap
		desired_guests.append(guests_cap * local_appeal * occupancy_factor * gaming_factor / (TourismParams.PERCENT * TourismParams.PERCENT * TourismParams.PERCENT) if operating else 0)
		desired_day.append(day_cap * local_appeal * gaming_factor / (TourismParams.PERCENT * TourismParams.PERCENT) if operating else 0)
	var guest_targets := allocate(desired_guests, guest_pool)
	var day_targets := allocate(desired_day, day_pool)
	var guests := 0
	var day_visitors := 0
	var lodging_cents := 0
	var gaming_cents := 0
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
		row["projected_guests"] = projected
		row["projected_day_visitors"] = day_targets[i]
		var bases := business_bases(projected, projected, day_targets[i])
		row.merge(bases, true)
		guests += projected
		day_visitors += day_targets[i]
		lodging_cents += int(bases["lodging_cents"])
		gaming_cents += int(bases["gaming_cents"])
	return {"rows": ordered, "guest_pool": guest_pool, "day_pool": day_pool,
		"guests": guests, "day_visitors": day_visitors, "capacity": capacity,
		"occupancy": guests * TourismParams.PERCENT / capacity if capacity > 0 else 0,
		"lodging_cents": lodging_cents, "gaming_cents": gaming_cents,
		"explanation": "City appeal %d%%; occupancy demand factor %d%%; gaming demand factor %d%%; finite pools %d guests / %d day visitors." % [city_appeal, occupancy_factor, gaming_factor, guest_pool, day_pool]}


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
