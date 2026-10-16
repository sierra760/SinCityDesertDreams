# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Finite deterministic markets and immutable segmented business profile.
class_name TourismMarkets
extends RefCounted

const PROFILE := "segments_20261015"
const NAMES := ["Budget", "Leisure", "Luxury", "Business"]
const GUEST_WEIGHTS := [45, 30, 15, 10]
const DAY_WEIGHTS := [55, 25, 5, 15]
const OCCUPANCY_ELASTICITY := [5, 4, 3, 3]
const GAMING_ELASTICITY := [4, 3, 2, 3]
const SPEND := [85, 100, 150, 110]
const BUSINESS_DENOMINATOR := 10000
const TAX_DENOMINATOR := 1000000
# Frozen profile tier membership: historical earnings never consult mutable costs.
const STANDARD := [&"arcology_comstock", &"arcology_junction", &"arcology_alibi", &"arcology_boulder"]
const PREMIUM := [&"arcology_orbit", &"arcology_velvet", &"arcology_fix", &"arcology_afterglow"]

static func tier(key: StringName) -> int:
	return 2 if key in PREMIUM else (1 if key in STANDARD else 0)

static func yield_factors(key: StringName) -> Array:
	return [[100, 100], [130, 120], [180, 150]][tier(key)]

static func sum_counts(values: Array) -> int:
	var total := 0
	for value in values: total += int(value)
	return total

## Exact partition with canonical remainder order; also used for migration.
@warning_ignore("integer_division")
static func partition(count: int, weights: Array) -> Array:
	var result := [0, 0, 0, 0]
	var total := sum_counts(weights)
	if count <= 0 or total <= 0: return result
	var assigned := 0
	for s in 4:
		result[s] = count * int(weights[s]) / total
		assigned += int(result[s])
	for s in 4:
		if assigned == count: break
		if int(weights[s]) > 0:
			result[s] += 1
			assigned += 1
	return result

static func valid_segments(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != 4: return false
	var total := 0
	for item: Variant in value:
		if not TourismState._integer(item, 0, count): return false
		total += int(item)
	return total == count

static func counts(row: Dictionary, day: bool = false) -> Array:
	var field := "day_segments" if day else "guest_segments"
	var count := int(row.get("day_visitors" if day else "guests", 0))
	return row[field].duplicate() if row.has(field) else partition(count, DAY_WEIGHTS if day else GUEST_WEIGHTS)

## Opening and closing are separate cohorts; only arrivals adopt the new mix.
static func advance(opening: Array, closing: int, departures: int, arrivals: int, targets: Array) -> Array:
	var survivors := partition(maxi(0, sum_counts(opening) - departures), opening)
	var incoming := partition(arrivals, targets if sum_counts(targets) > 0 else GUEST_WEIGHTS)
	for s in 4: survivors[s] += int(incoming[s])
	assert(sum_counts(survivors) == closing)
	return survivors

## Inputs are untaxed finite pools. Sequential segment claims share each venue's
## capacity partition. Weaker cross-tier weights are positive for every segment.
@warning_ignore("integer_division")
static var preference_evaluations := 0

static func allocate(rows: Array[Dictionary], inputs: Dictionary, occupancy_rate: int, gaming_rate: int) -> Dictionary:
	var ordered: Array[Dictionary] = rows.duplicate(true)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.anchor.y * City.WIDTH + a.anchor.x < b.anchor.y * City.WIDTH + b.anchor.x)
	var pools := [partition(maxi(0,int(inputs.get("guest_pool",0))),GUEST_WEIGHTS), partition(maxi(0,int(inputs.get("day_pool",0))),DAY_WEIGHTS)]
	var totals := [0,0]
	for row in ordered:
		row["target_guest_segments"] = [0,0,0,0]
		row["target_day_segments"] = [0,0,0,0]
	for kind in 2:
		var field := "target_guest_segments" if kind == 0 else "target_day_segments"
		# Capacity/preferences do not depend on the segment being allocated.
		# Calculate each eligible venue's four shares once, rather than four
		# identical partitions; closed venues need none of this work.
		var available_by_row: Array[Array] = []
		for row in ordered:
			var eligible: bool = row.get("operating",false)
			if inputs.get("access_enabled",false): eligible = eligible and (row.get("external_reachable",false) or (kind == 1 and row.get("local_reachable",false)))
			if not eligible:
				available_by_row.append([0,0,0,0])
				continue
			var cap := TourismParams.guest_capacity(row.key) if kind == 0 else TourismParams.day_capacity(row.key)
			var weights := []
			for segment in 4: weights.append(int(GUEST_WEIGHTS[segment] if kind == 0 else DAY_WEIGHTS[segment])*preference(row,segment,inputs))
			available_by_row.append(partition(cap*clampi(int(row.get("appeal",100)),0,100)/100,weights))
		for s in 4:
			var occupancy := maxi(0,100-int(OCCUPANCY_ELASTICITY[s])*clampi(occupancy_rate,0,20)) if kind == 0 else 100
			var gaming := maxi(0,100-int(GAMING_ELASTICITY[s])*clampi(gaming_rate,0,20))
			var event_factors: Array = inputs.get("event_factors",[100,100,100,100])
			var pool := int(pools[kind][s])*int(event_factors[s])/100
			pool = pool*occupancy*gaming/10000
			pools[kind][s] = pool
			var desired := PackedInt64Array()
			for available: Array in available_by_row:
				desired.append(int(available[s])*occupancy*gaming/10000)
			var shares := TourismDemand.allocate(desired,pool)
			for i in ordered.size(): ordered[i][field][s] = shares[i]
			totals[kind] += pool
	return {"rows":ordered,"guest_pool":totals[0],"day_pool":totals[1],"guest_pools":pools[0],"day_pools":pools[1]}

static func preference(row: Dictionary, segment: int, inputs: Dictionary) -> int:
	preference_evaluations += 1
	var venue_tier := tier(row.key)
	var base: int = [[100,75,40],[75,100,90],[35,65,100],[70,100,90]][segment][venue_tier]
	if segment == 1: base += mini(20,int(row.get("district_appeal_bonus",0)))
	if segment == 2: base -= mini(20,maxi(0,int(row.get("crime",0)))/16 + maxi(0,int(inputs.get("average_traffic",0)))/32)
	if segment == 3:
		for gateway: Dictionary in inputs.get("gateways",[]):
			if gateway.kind in ["rail","airport"] and gateway.id in row.get("gateway_ids",[]):
				base += 10
				break
	return clampi(base,10,100)

## Numerators are cents / 10,000. Integer cents are presentation only.
@warning_ignore("integer_division")
static func business(opening_segments: Array, closing_segments: Array, day_segments: Array, key: StringName) -> Dictionary:
	var factors := yield_factors(key)
	var lodging := 0
	var gaming := 0
	for s in 4:
		var halves := int(opening_segments[s])+int(closing_segments[s])
		lodging += halves*TourismParams.LODGING_CENTS_PER_HALF_GUEST*int(factors[0])*int(SPEND[s])
		gaming += (halves*TourismParams.GAMING_CENTS_PER_HALF_GUEST+int(day_segments[s])*TourismParams.GAMING_CENTS_PER_VISITOR)*int(factors[1])*int(SPEND[s])
	return {"lodging_numerator":lodging,"gaming_numerator":gaming,"lodging_cents":lodging/BUSINESS_DENOMINATOR,"gaming_cents":gaming/BUSINESS_DENOMINATOR}

@warning_ignore("integer_division")
static func tax(numerator: int, rate: int, opening: int) -> Dictionary:
	var exact := numerator*rate*12+opening
	return {"units":exact/TAX_DENOMINATOR,"residue":exact%TAX_DENOMINATOR}

static func mix_text(guests: Array, days: Array) -> String:
	var parts := PackedStringArray()
	for s in 4: parts.append("%s %d / %d" % [NAMES[s],int(guests[s]),int(days[s])])
	return "Guests / day visitors: " + "; ".join(parts)

## Normalize validated JSON activity once at installation, preserving exact integers.
static func integer_activity(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	if result.is_empty(): return result
	result.month_id = int(result.month_id)
	for row: Dictionary in result.rows:
		for field in ["code","instance","guest_half_months","day_visitors"]: row[field] = int(row[field])
		for field in ["anchor","guest_half_segments","day_segments"]:
			if row.has(field): row[field] = row[field].map(func(v: Variant) -> int: return int(v))
	return result

## Derived pure-input cache, never serialized or used by accepted attendance.
## One entry per possible map record; zero overnight projections do no work.
const PROJECTION_CACHE_LIMIT := City.WIDTH * City.HEIGHT
const PROJECTION_STEP_LIMIT := 32
static var _projection_cache: Dictionary = {}
static var _projection_fifo: Array[String] = []
static var _projection_cursor := 0
static var _projection_evictions := 0
static var _projection_hits := 0
static var _projection_misses := 0
static var _projection_steps := 0

static func clear_projection_cache() -> void:
	_projection_cache.clear()
	_projection_fifo.clear()
	_projection_cursor = 0
	_projection_evictions = 0
	_projection_hits = 0
	_projection_misses = 0
	_projection_steps = 0

static func projection_work() -> Dictionary:
	return {"evictions":_projection_evictions,"entries":_projection_cache.size(),"hits":_projection_hits,"misses":_projection_misses,"steps":_projection_steps,"entry_limit":PROJECTION_CACHE_LIMIT,"step_limit":PROJECTION_STEP_LIMIT}

## Reproduce the existing turnover and exact survivor/arrival remainder rule.
## The scalar forecast sometimes intentionally denotes next-period survivors
## under a newly restricted gateway, rather than its distant equilibrium. Keep
## that scalar and return its matching actual step, not a fabricated remix.
static func project(opening: Array, targets: Array, projected: int, arrival_cap: int = -1) -> Dictionary:
	if projected == 0: return {"segments":[0,0,0,0],"exact":true,"basis":"settled_turnover"}
	var cache_key := str([opening,targets,projected,arrival_cap])
	if _projection_cache.has(cache_key):
		_projection_hits += 1
		return _projection_cache[cache_key].duplicate(true)
	_projection_misses += 1
	var current := opening.duplicate()
	var matching: Array = []
	var result := {}
	for iteration in PROJECTION_STEP_LIMIT:
		_projection_steps += 1
		var change := TourismDemand.turnover(sum_counts(current),sum_counts(targets))
		if arrival_cap >= 0:
			change.arrivals = mini(int(change.arrivals),arrival_cap)
			change.guests = sum_counts(current)-int(change.departures)+int(change.arrivals)
		var next := advance(current,change.guests,change.departures,change.arrivals,targets)
		if sum_counts(next) == projected and matching.is_empty(): matching = next.duplicate()
		if next == current:
			if sum_counts(next) == projected: result = {"segments":next,"exact":true,"basis":"settled_turnover"}
			elif not matching.is_empty(): result = {"segments":matching,"exact":true,"basis":"supported_turnover_step"}
			break
		current = next
	if result.is_empty():
		# Defensive bounded fallback is explicit; tested supported capacity/rate
		# cases close well before this limit. Never change live turnover here.
		result = {"segments":partition(projected,targets if sum_counts(targets)>0 else GUEST_WEIGHTS),"exact":false,"basis":"estimated_target_mix"}
	if _projection_fifo.size() >= PROJECTION_CACHE_LIMIT:
		_projection_cache.erase(_projection_fifo[_projection_cursor])
		_projection_fifo[_projection_cursor] = cache_key
		_projection_cursor = (_projection_cursor + 1) % PROJECTION_CACHE_LIMIT
		_projection_evictions += 1
	else:
		_projection_fifo.append(cache_key)
	_projection_cache[cache_key] = result.duplicate(true)
	return result
