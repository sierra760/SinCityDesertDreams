# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for the zone system. See docs/simulation/zones.md.
class_name ZoneParams
extends RefCounted

# ── Stages and occupancy ─────────────────────────────────────────────────

## Residents or jobs represented by one occupied unit.
const PEOPLE_PER_UNIT := 10
## Footprint side of a building at stages 1..4 (index 0 is open ground).
const STAGE_FOOTPRINT: Array[int] = [0, 1, 2, 2, 3]
## Occupied units of a finished building at stages 1..4.
const STAGE_UNITS: Array[int] = [0, 1, 8, 12, 36]
## Top stage reachable in light and dense zones.
const LIGHT_ZONE_MAX_STAGE := 1
const DENSE_ZONE_MAX_STAGE := 4
## Land value a residential or commercial lot needs to leave stage 0..3.
const UPGRADE_LAND_VALUE: Array[int] = [0, 32, 96, 192]
## Land value span of each residential 1×1 look class (three classes).
const RES_CLASS_LAND_VALUE_STEP := 64

# ── Eligibility ──────────────────────────────────────────────────────────

## How far (in tiles, any direction) a lot looks for road access.
const ACCESS_RADIUS := 3
## Multi-tile lots keep this many tiles from the map edge.
const EDGE_MARGIN := 2

# ── Demand ───────────────────────────────────────────────────────────────

## Accumulator range; the meters show it rescaled to ±999.
const DEMAND_RAW_LIMIT := 2000
## Accumulator change per unit of target/supply mismatch.
const DEMAND_GAIN := 600
## Residential target grows by one unit per this many resident units.
const RES_SELF_GROWTH_DIVISOR := 50
## Residential target limit from commerce: C × RES_PER_COMMERCIAL + RES_BASE_TARGET.
const RES_PER_COMMERCIAL := 4
const RES_BASE_TARGET := 500
## Residential cap: (RES_CAP_BASE + recreation buildings) × RES_CAP_STEP units.
const RES_CAP_BASE := 10
const RES_CAP_STEP := 150
## Commercial market: (residents + MARKET_BASE) / MARKET_SCALE.
const MARKET_BASE := 50000
const MARKET_SCALE := 150000
## Market lift for each neighbor city with people.
const EXTERNAL_MARKET_PER_NEIGHBOR := 0.1
## Commercial cap: (COM_CAP_BASE + stations / COM_STATIONS_PER_STEP + neighbors) × COM_CAP_STEP.
const COM_CAP_BASE := 1
const COM_STATIONS_PER_STEP := 5
const COM_CAP_STEP := 1500
## Industry is always wanted up to this many units.
const IND_TARGET_FLOOR := 15
## A few households are always willing to settle, so an empty town can start.
const RES_TARGET_FLOOR := 10
## Industrial pull on easy, medium and hard.
const INDUSTRY_BY_DIFFICULTY: Array[float] = [1.2, 1.1, 0.95]
## Industrial pull by national phase: recession, steady, growth, boom.
const INDUSTRY_BY_PHASE: Array[float] = [-0.15, 0.0, 0.1, 0.2]
## Industrial cap: (IND_CAP_BASE + rail stations + cranes) × IND_CAP_STEP.
const IND_CAP_BASE := 1
const IND_CAP_STEP := 1500
## Tax pressure on demand around the neutral rate.
const TAX_NEUTRAL := 7
const TAX_BELOW_PER_POINT := 25
const TAX_MILD_POINTS := 2
const TAX_MILD_PER_POINT := 25
const TAX_STEEP_PER_POINT := 50
## Ordinance nudges applied to one family's accumulator each month.
const ORDINANCE_NUDGE_SMALL := 25
const ORDINANCE_NUDGE_LARGE := 50

# ── Growth points and local conditions ───────────────────────────────────

const GROWTH_POINTS_MAX := 4000
## Growth points per land value point for residential and commercial lots.
const LAND_VALUE_WEIGHT := 2
## Pollution the families ignore, and the penalty per excess point (R, C, I).
const POLLUTION_TOLERANCE := 64
const POLLUTION_WEIGHT: Array[int] = [8, 4, 0]
## Crime the families ignore, and the penalty per excess point (R, C, I).
const CRIME_TOLERANCE := 64
const CRIME_WEIGHT: Array[int] = [6, 6, 2]

# ── Decision draws ───────────────────────────────────────────────────────

## Outcomes per decision draw; thresholds below are out of this span.
const ROLL_SPAN := 65536
## Construction finishing threshold at stage 1 (divided by the stage).
const CONSTRUCTION_FINISH := 16384
## Reoccupation threshold per growth point (divided by the stage).
const REBUILD_FACTOR := 15
## Upgrade threshold per growth point (divided by stage + 1).
const UPGRADE_FACTOR := 3
## Growth slowdown applied to construction and upgrades without water.
const WATER_SHORTAGE_NUMERATOR := 1
const WATER_SHORTAGE_DENOMINATOR := 2
## Residents that justify one more chapel.
const RESIDENTS_PER_CHAPEL := 2500

# ── Overlay maps and news ────────────────────────────────────────────────

const DENSITY_PEOPLE_PER_STEP := 4
const GROWTH_PEOPLE_PER_STEP := 4
## zone_boom needs this much demand and this many finished lots in a month.
const BOOM_DEMAND := 500
const BOOM_DEVELOPMENTS := 12
## abandonment_wave needs this many declines in a month.
const WAVE_DECLINES := 8

# ── Building roster helpers ──────────────────────────────────────────────

const FAMILY_RESIDENTIAL := 0
const FAMILY_COMMERCIAL := 1
const FAMILY_INDUSTRIAL := 2
const FAMILY_NAMES: Array[StringName] = [&"residential", &"commercial", &"industrial"]

## Recreation buildings that raise the residential cap.
const RECREATION_KEYS: Array[StringName] = [&"large_park", &"stadium", &"zoo", &"marina"]
## Transit stations that raise the commercial cap.
const STATION_KEYS: Array[StringName] = [&"bus_depot", &"rail_station", &"subway_station"]


## Family (0 residential, 1 commercial, 2 industrial) of a growth zone kind, else -1.
static func family_of(zone_kind: int) -> int:
	if not Zones.is_growth_zone(zone_kind):
		return -1
	@warning_ignore("integer_division")
	return (zone_kind - 1) / 2


static func max_stage(zone_kind: int) -> int:
	return DENSE_ZONE_MAX_STAGE if Zones.is_dense(zone_kind) else LIGHT_ZONE_MAX_STAGE


## Finished building ids of one family and stage. Stages 2 and 3 split the
## family's 2×2 roster into its lower and upper half.
static func finished_ids(family: int, stage: int) -> Array[int]:
	var dense_kind: int = [Zones.RES_HIGH, Zones.COM_HIGH, Zones.IND_HIGH][family]
	match stage:
		1:
			return Buildings.zone_stage_ids(dense_kind, 1)
		2, 3:
			var all := Buildings.zone_stage_ids(dense_kind, 2)
			@warning_ignore("integer_division")
			var half: int = all.size() / 2
			return all.slice(0, half) if stage == 2 else all.slice(half)
		4:
			return Buildings.zone_stage_ids(dense_kind, 3)
	return []


## Construction site ids for a stage (two looks each).
static func construction_ids(stage: int) -> Array[int]:
	match stage:
		1: return [Buildings.CONSTRUCTION_1X1_A, Buildings.CONSTRUCTION_1X1_B]
		2: return [Buildings.CONSTRUCTION_2X2_FIRST, Buildings.CONSTRUCTION_2X2_FIRST + 1]
		3: return [Buildings.CONSTRUCTION_2X2_FIRST + 2, Buildings.CONSTRUCTION_2X2_LAST]
		4: return [Buildings.CONSTRUCTION_3X3_A, Buildings.CONSTRUCTION_3X3_B]
	return []


## Abandoned building ids for a stage (two looks each).
static func abandoned_ids(stage: int) -> Array[int]:
	match stage:
		1: return [Buildings.ABANDONED_1X1_A, Buildings.ABANDONED_1X1_B]
		2: return [Buildings.ABANDONED_2X2_FIRST, Buildings.ABANDONED_2X2_FIRST + 1]
		3: return [Buildings.ABANDONED_2X2_FIRST + 2, Buildings.ABANDONED_2X2_LAST]
		4: return [Buildings.ABANDONED_3X3_A, Buildings.ABANDONED_3X3_B]
	return []


## Stage of a zone building, construction site or abandoned building; 0 for
## developable open ground; -1 for anything else.
static func stage_of(id: int) -> int:
	if is_open_ground(id):
		return 0
	if Buildings.is_zone_building(id):
		var s := Buildings.size(id)
		if s.x == 1:
			return 1
		if s.x == 3:
			return 4
		return 3 if id in finished_ids(_family_of_building(id), 3) else 2
	if Buildings.is_construction(id) or Buildings.is_abandoned(id):
		for stage in range(1, 5):
			if id in construction_ids(stage) or id in abandoned_ids(stage):
				return stage
	return -1


## Ground a zoned lot may develop over.
static func is_open_ground(id: int) -> bool:
	if id == Buildings.NONE or Buildings.is_tree(id):
		return true
	if id >= Buildings.RUBBLE_1 and id <= Buildings.RUBBLE_4:
		return true
	return id >= Buildings.POWER_LINE_FIRST and id <= Buildings.POWER_LINE_LAST


static func _family_of_building(id: int) -> int:
	match Buildings.category(id):
		Buildings.Category.RESIDENTIAL: return FAMILY_RESIDENTIAL
		Buildings.Category.COMMERCIAL: return FAMILY_COMMERCIAL
		Buildings.Category.INDUSTRIAL: return FAMILY_INDUSTRIAL
	return -1


## Residents housed by a finished residential building.
static func population_of(id: int) -> int:
	if Buildings.category(id) != Buildings.Category.RESIDENTIAL:
		return 0
	return STAGE_UNITS[stage_of(id)] * PEOPLE_PER_UNIT


## Jobs offered by a finished commercial or industrial building.
static func jobs_of(id: int) -> int:
	var c := Buildings.category(id)
	if c != Buildings.Category.COMMERCIAL and c != Buildings.Category.INDUSTRIAL:
		return 0
	return STAGE_UNITS[stage_of(id)] * PEOPLE_PER_UNIT


## Tiles that give a lot road access.
static func gives_access(id: int) -> bool:
	if id == Buildings.BUS_DEPOT or id == Buildings.RAIL_STATION or id == Buildings.SUBWAY_STATION:
		return true
	if id >= Buildings.ONRAMP_FIRST and id <= Buildings.ONRAMP_LAST:
		return true
	if id >= Buildings.HIGHWAY_FIRST and id <= Buildings.HIGHWAY_LAST:
		return false
	if id >= Buildings.HIGHWAY_PIECE_FIRST and id <= Buildings.HIGHWAY_PIECE_LAST:
		return false
	return Buildings.is_road_like(id)


## Demand change from a tax rate: positive below neutral, gently negative
## just above it, steeply negative beyond.
static func tax_pressure(rate: int) -> int:
	if rate <= TAX_NEUTRAL:
		return (TAX_NEUTRAL - rate) * TAX_BELOW_PER_POINT
	var above := rate - TAX_NEUTRAL
	var mild := mini(above, TAX_MILD_POINTS)
	return -(mild * TAX_MILD_PER_POINT + (above - mild) * TAX_STEEP_PER_POINT)
