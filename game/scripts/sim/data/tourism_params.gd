# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Aggregate concurrent tourism tuning; percentages and money use integer units.
class_name TourismParams
extends RefCounted

const TAX_MIN := 0
const TAX_MAX := 20
const TAX_STEP := 1
const TAX_DEFAULT := 7
const OCCUPANCY_TAX_LABEL := "Occupancy tax %"
const GAMING_TAX_LABEL := "Gaming revenue tax %"
const MONTHLY_DAY := 17
const BOOKING_DAY := 18
const STATISTICS_DAY := 22
const PERCENT := 100
const BASE_POOL := 250
const POPULATION_DIVISOR := 2
const NEIGHBOR_DIVISOR := 100
const NEIGHBOR_POOL_CAP := 50000
const ECONOMY_PERCENT := [70, 90, 100, 115]
const DAY_POOL_DIVISOR := 3
const APPEAL_BASE := 70
const APPEAL_MIN := 10
const APPEAL_MAX := 100
const LAND_VALUE_DIVISOR := 8
const CRIME_DIVISOR := 8
const POLLUTION_DIVISOR := 8
const TRAFFIC_DIVISOR := 16
const ADVERTISING_APPEAL := 10
const OCCUPANCY_TAX_DISCOURAGEMENT := 4
const GAMING_TAX_DISCOURAGEMENT := 3
const TURNOVER_DIVISOR := 2
const STORE_DAY_CAPACITY := 24
const MIN_DAY_CAPACITY := 16
const MAX_DAY_CAPACITY := 300
const ACCESS_DISTANCE := 3
const LODGING_CENTS_PER_GUEST := 100
const GAMING_CENTS_PER_VISITOR := 50
## A half-month is exact even for an odd sum of opening and closing guests.
const LODGING_CENTS_PER_HALF_GUEST := LODGING_CENTS_PER_GUEST / TURNOVER_DIVISOR
const GAMING_CENTS_PER_HALF_GUEST := GAMING_CENTS_PER_VISITOR / TURNOVER_DIVISOR
## Defensive bound for external numeric inputs, keeping intermediate int64 math safe.
## Real city and venue counts are far below this limit.
const MAX_COUNT := 2147483647
const CRIME_MICRO_UNIT := 1000000
const GUEST_CRIME_MICRO := 10000
const DAY_CRIME_MICRO := 20000
const SAFETY_REMAINING_PERCENT := 60
const SAFETY_CENTS_PER_VISITOR := 2
const NIGHTLIFE_RADIUS := 6
const NIGHTLIFE_CAP := 12
const NIGHTLIFE_VISITOR_DIVISOR := 50
const DISTRICT_REACH := 16
const DISTRICT_CATEGORY_FIRST := 4
const DISTRICT_CATEGORY_SECOND := 2
const DISTRICT_CATEGORY_LATER := 1
const DISTRICT_CATEGORY_CAP := 5
const DISTRICT_APPEAL_CAP := 20
const RESORT_VARIETY_CAP := 5
const COMMERCIAL_REACH := 12
const GUEST_RETAIL_CENTS := 20
const DAY_RETAIL_CENTS := 10
const COMMERCIAL_CENTS_PER_POINT := 100
const COMMERCIAL_DEMAND_CAP := 100
const COMMERCIAL_GROWTH_CAP := 10

static func venue_tier(key: StringName) -> String:
	var cost := Buildings.cost(Buildings.id_of(key))
	if key == &"com_corner_store" or cost < 100000: return "budget"
	return "standard" if cost < 200000 else "premium"

static func security_percent(key: StringName) -> int:
	return {"budget": 150, "standard": 100, "premium": 65}[venue_tier(key)]


## Immutable schema-1 roster: validation authority for previously earned business only.
const PREVIOUS_GUEST_CAPACITIES := {
	&"arcology_boddy": 500,
	&"arcology_woolier": 1200,
	&"arcology_stockgrowers": 3000,
	&"arcology_fremont": 5000,
	&"arcology_last": 35000,
	&"arcology_dust": 40000,
	&"arcology_comstock": 55000,
	&"arcology_junction": 30000,
	&"arcology_alibi": 30000,
	&"arcology_boulder": 45000,
	&"arcology_orbit": 65000,
	&"arcology_velvet": 30000,
	&"arcology_fix": 35000,
	&"arcology_afterglow": 45000,
}
const CURRENT_PROFILE := "cost_scaled_20261015"
const PREVIOUS_PROFILE := "roster_20261014"

static func profile_guest_capacity(key: StringName, profile: String) -> int:
	return int(PREVIOUS_GUEST_CAPACITIES.get(key, 0)) if profile == PREVIOUS_PROFILE else guest_capacity(key)

static func profile_day_capacity(key: StringName, profile: String) -> int:
	if key == &"com_corner_store": return STORE_DAY_CAPACITY
	var capacity := profile_guest_capacity(key, profile)
	return clampi(int(sqrt(capacity)), MIN_DAY_CAPACITY, MAX_DAY_CAPACITY) if capacity > 0 else 0

static func guest_capacity(key: StringName) -> int:
	return int(RewardParams.ARCOLOGIES.get(key, {}).get("capacity", 0))


static func day_capacity(key: StringName) -> int:
	if key == &"com_corner_store":
		return STORE_DAY_CAPACITY
	var capacity := guest_capacity(key)
	if capacity == 0:
		return 0
	return clampi(int(sqrt(capacity)), MIN_DAY_CAPACITY, MAX_DAY_CAPACITY)

## Fulfilled safety/access/attractions/staffing/services, each vector sums100.
## Budget visitors chiefly need safe access and reliable affordable service;
## leisure prizes attractions; business prizes access; luxury prizes service
## and attractions. Prices, spend multipliers and venue tiers award no points.
const EXPERIENCE_BUDGET := [30,25,10,15,20]
const EXPERIENCE_LEISURE := [20,20,30,10,20]
const EXPERIENCE_LUXURY := [20,15,25,20,20]
const EXPERIENCE_BUSINESS := [20,30,10,20,20]
const EXPERIENCE_WEIGHTS := [EXPERIENCE_BUDGET,EXPERIENCE_LEISURE,EXPERIENCE_LUXURY,EXPERIENCE_BUSINESS]
## Forced loss of actual natural survivors caps experience at their service
## fulfillment, before city exposure weighting. Never penalizes unadmitted demand.
const ESSENTIAL_SERVICE_EXPERIENCE_CEILING := true
