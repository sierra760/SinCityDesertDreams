# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for the transport (traffic and transit) and wear systems.
## See docs/simulation/traffic.md and docs/simulation/maintenance.md.
class_name TransportParams
extends RefCounted

# ── Routing ──────────────────────────────────────────────────────────────

## Travel cost a trip may spend before it gives up.
const TRIP_BUDGET := 100

## Step prices by the mode a trip arrives in. Highways are three times faster
## than roads; stations cost the most to pass through.
const ROAD_STEP := 3
const HIGHWAY_STEP := 1
const RAMP_STEP := 2
const BUS_STEP := 2
const RAIL_STEP := 1
const SUBWAY_STEP := 1
const STATION_STEP := 4
const PLATFORM_STEP := 1
## Largest step price; the search buckets pending states by cost modulo this plus one.
const MAX_STEP := 4

## Rings searched around a lot's footprint for its entrance.
const ENTRANCE_REACH := 3

## Most origins routed in one monthly pass; larger cities are sampled evenly.
const TRIPS_PER_PASS := 160
## Largest factor a sampled trip's weight is scaled by.
const SAMPLE_WEIGHT_CAP := 8
## States the whole pass may search; once spent, remaining origins wait a month.
const PASS_SEARCH_BUDGET := 32000

## Saturation of a traffic block and the monthly decay shift (a quarter is lost).
const TRAFFIC_MAX := 255
const TRAFFIC_DECAY_SHIFT := 2

## Average traffic that produces a traffic jam story, and the passes to wait
## before the next one.
const JAM_LEVEL := 128
const JAM_COOLDOWN_MONTHS := 6

# ── Surface classes used by routing ──────────────────────────────────────

## Bit flags describing what a building id offers to a traveller.
const SURFACE_ROAD := 1            ## cars and buses drive here
const SURFACE_HIGHWAY := 2         ## highway lanes
const SURFACE_RAIL := 4            ## trains run here
const SURFACE_RAMP := 8            ## junction between road and highway
const SURFACE_PORTAL := 16         ## rail tile that continues into the subway
const SURFACE_BUS_DEPOT := 32
const SURFACE_RAIL_STATION := 64
const SURFACE_SUBWAY_STATION := 128
const SURFACE_STATION := SURFACE_BUS_DEPOT | SURFACE_RAIL_STATION | SURFACE_SUBWAY_STATION

## Canonical level crossings; 57/58 are ordinary rail junctions.
const _RAIL_ROAD_CROSSINGS: Array[int] = [69, 70]
## Rail that shares a tile with a power line.
const _RAIL_UNDER_POWER: Array[int] = [71, 72]
## Highway lanes stacked over a road or over rail.
const _HIGHWAY_OVER_ROAD: Array[int] = [75, 76]
const _HIGHWAY_OVER_RAIL: Array[int] = [77, 78]
## Rail bridge pylon and span.
const _RAIL_BRIDGE: Array[int] = [90, 91]
## Elevated power line: a bridge id that carries no traffic.
const _ELEVATED_POWER := 92


## What a building id offers to a traveller, as SURFACE_* flags.
static func surface_class(id: int) -> int:
	match id:
		Buildings.BUS_DEPOT: return SURFACE_BUS_DEPOT
		Buildings.RAIL_STATION: return SURFACE_RAIL_STATION
		Buildings.SUBWAY_STATION: return SURFACE_SUBWAY_STATION
		_ELEVATED_POWER: return 0
	if id >= Buildings.ONRAMP_FIRST and id <= Buildings.ONRAMP_LAST:
		return SURFACE_RAMP
	if id >= Buildings.SUBWAY_PORTAL_FIRST and id <= Buildings.SUBWAY_PORTAL_LAST:
		return SURFACE_RAIL | SURFACE_PORTAL
	if id in _RAIL_ROAD_CROSSINGS:
		return SURFACE_ROAD | SURFACE_RAIL
	if id in _RAIL_UNDER_POWER:
		return SURFACE_RAIL
	if id in _HIGHWAY_OVER_ROAD:
		return SURFACE_HIGHWAY | SURFACE_ROAD
	if id in _HIGHWAY_OVER_RAIL:
		return SURFACE_HIGHWAY | SURFACE_RAIL
	if id in _RAIL_BRIDGE:
		return SURFACE_RAIL
	if id == Buildings.REINFORCED_PYLON or id == Buildings.REINFORCED_BRIDGE:
		return SURFACE_HIGHWAY
	match Buildings.category(id):
		Buildings.Category.ROAD, Buildings.Category.TUNNEL, Buildings.Category.BRIDGE:
			return SURFACE_ROAD
		Buildings.Category.HIGHWAY:
			return SURFACE_HIGHWAY
		Buildings.Category.RAIL:
			return SURFACE_RAIL
	return 0


## Lots that trips start from.
static func is_origin(id: int) -> bool:
	return Buildings.category(id) == Buildings.Category.RESIDENTIAL


## Lots that trips arrive at.
static func is_destination(id: int) -> bool:
	var c := Buildings.category(id)
	return c == Buildings.Category.COMMERCIAL or c == Buildings.Category.INDUSTRIAL


## Weight of one trip: the side of the lot's footprint.
static func trip_weight(id: int) -> int:
	return maxi(1, Buildings.size(id).x)


# ── Wear categories ──────────────────────────────────────────────────────

const ROADS := 0
const HIGHWAYS := 1
const BRIDGES := 2
const RAIL := 3
const SUBWAY := 4
const TUNNELS := 5
const CATEGORY_COUNT := 6
const NO_CATEGORY := 255

## Category names, indexed by the constants above. They double as the funding
## slider keys in CityStats.
const CATEGORY_KEYS: Array[StringName] = [&"roads", &"highways", &"bridges", &"rail", &"subway", &"tunnels"]

## Wear points that trigger one loss. Roads lose about half a percent of their
## tiles per month at zero funding; bridges fail fastest, highways lose a whole
## block at a time.
const WEAR_THRESHOLD := {
	&"roads": 20000,
	&"highways": 40000,
	&"bridges": 5000,
	&"rail": 15000,
	&"subway": 20000,
	&"tunnels": 20000,
}

## Random spread, in percent, applied to each month's accrued wear.
const WEAR_JITTER_PERCENT := 25

## Yearly upkeep per tile at full funding, in cents.
const UPKEEP_CENTS := {
	&"roads": 10,
	&"highways": 30,
	&"bridges": 40,
	&"rail": 25,
	&"subway": 50,
	&"tunnels": 50,
}


## Wear category of a surface building id, or NO_CATEGORY.
static func wear_category(id: int) -> int:
	if id == _ELEVATED_POWER:
		return NO_CATEGORY
	if id == Buildings.REINFORCED_PYLON or id == Buildings.REINFORCED_BRIDGE:
		return HIGHWAYS
	if id in _RAIL_ROAD_CROSSINGS:
		return ROADS
	if id in _RAIL_UNDER_POWER:
		return RAIL
	if id >= Buildings.SUBWAY_PORTAL_FIRST and id <= Buildings.SUBWAY_PORTAL_LAST:
		return RAIL
	match Buildings.category(id):
		Buildings.Category.ROAD: return ROADS
		Buildings.Category.HIGHWAY: return HIGHWAYS
		Buildings.Category.BRIDGE: return BRIDGES
		Buildings.Category.RAIL: return RAIL
		Buildings.Category.TUNNEL: return TUNNELS
	return NO_CATEGORY


## Whether wear may remove this surface tile. Subway portals are spared so a
## tunnel never loses its mouth to rail wear.
static func is_losable(id: int) -> bool:
	if id >= Buildings.SUBWAY_PORTAL_FIRST and id <= Buildings.SUBWAY_PORTAL_LAST:
		return false
	return wear_category(id) != NO_CATEGORY


## Whether an underground code is a subway segment wear may remove.
static func is_losable_subway(code: int) -> bool:
	return code >= UtilityParams.SUBWAY_FIRST and code <= UtilityParams.SUBWAY_LAST


static func category_index(category: StringName) -> int:
	return CATEGORY_KEYS.find(category)
