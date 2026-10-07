# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Named constants for the power and water systems, the code table of the
## underground layer that pipes and subways share, and the per-id tables the
## monthly passes classify tiles with.
class_name UtilityParams
extends RefCounted

# ── Shared ───────────────────────────────────────────────────────────────

## Units one developed tile draws from a network each month.
const LOAD_PER_TILE := 1

## Weather fallbacks when no system publishes precipitation or wind.
const DEFAULT_RAIN := 15
const DEFAULT_WIND := 10

## Systems asked, in order, for `precipitation()` and `wind_speed()`.
const WEATHER_SYSTEM_KEYS: Array[StringName] = [&"environment", &"weather", &"disasters"]

## Ordinance flag that stretches every power network's budget.
const CONSERVATION_ORDINANCE := &"energy_conservation"


## Ask the weather-owning system for a value (`precipitation`, `wind_speed`);
## fall back when no loaded system publishes it.
static func weather(ctx: SimContext, method: StringName, fallback: int) -> int:
	for k in WEATHER_SYSTEM_KEYS:
		var s := ctx.system(k)
		if s != null and s.has_method(method):
			return int(s.call(method))
	return fallback

# ── Power ────────────────────────────────────────────────────────────────

## Tiles a whole plant can supply, by building key.
const PLANT_OUTPUT := {
	&"plant_coal": 704,
	&"plant_gas": 176,
	&"plant_oil": 768,
	&"plant_nuclear": 1776,
	&"plant_microwave": 5680,
	&"plant_fusion": 8880,
}

## Tiles one hydro dam supplies when it stands on a waterfall.
const HYDRO_OUTPUT := 40

## Wind speed is divided by this before it raises turbine output.
const WIND_DIVISOR := 8

## Collector tiles in a solar farm, guaranteed output per tile, and how strongly
## rain limits the random bonus on top of it.
const SOLAR_TILES := 16
const SOLAR_BASE := 5
const SOLAR_RAIN_DIVISOR := 10

## Extra budget share (one part in this many) from the energy conservation ordinance.
const CONSERVATION_BONUS_DIVISOR := 12

## Age at which a plant starts warning, and the age past which it retires.
const PLANT_WARNING_YEARS := 48
const PLANT_LIFETIME_YEARS := 50

## Plants that never wear out.
const AGELESS_PLANTS: Array[StringName] = [&"plant_hydro_a", &"plant_hydro_b", &"plant_wind"]

# ── Water ────────────────────────────────────────────────────────────────

## Pump output per level of the global water table, and the divisor applied to
## precipitation before it is added.
const WATER_TABLE_FACTOR := 5
const RAIN_DIVISOR := 2

## Pump output per adjacent fresh water tile; desalination output per adjacent
## salt water tile.
const FRESH_NEIGHBOR_YIELD := 10
const SALT_NEIGHBOR_YIELD := 20

## Water table assumed when the city has no global water level.
const DEFAULT_WATER_TABLE := 4

## Storage per water tower tile.
const TOWER_UNITS_PER_TILE := 100

## Consumption one treatment plant can clean.
const TREATMENT_COVERAGE := 2000

# ── Underground layer codes ──────────────────────────────────────────────

const UNDERGROUND_NONE := 0
## Pipes: the code is the connection mask (N=1, E=2, S=4, W=8).
const PIPE_FIRST := 1
const PIPE_LAST := 15
## Subway tunnels: code minus SUBWAY_OFFSET is the connection mask.
const SUBWAY_FIRST := 16
const SUBWAY_LAST := 30
const SUBWAY_OFFSET := 15
## Pipe and subway sharing one tile; each carries a straight run.
const CROSSING_PIPE_NS_UNDER_SUBWAY_EW := 31
const CROSSING_PIPE_EW_UNDER_SUBWAY_NS := 32
const CROSSING_PIPE_NS_OVER_SUBWAY_EW := 33
const CROSSING_PIPE_EW_OVER_SUBWAY_NS := 34
const CROSSING_FIRST := 31
const CROSSING_LAST := 34
## Link between a surface subway station and the tunnel below it.
const SUBWAY_STATION_LINK := 35

const DIR_N := 1
const DIR_E := 2
const DIR_S := 4
const DIR_W := 8
const NS_MASK := DIR_N | DIR_S
const EW_MASK := DIR_E | DIR_W


static func is_pipe(code: int) -> bool:
	return code >= PIPE_FIRST and code <= PIPE_LAST


static func is_crossing(code: int) -> bool:
	return code >= CROSSING_FIRST and code <= CROSSING_LAST


static func is_subway(code: int) -> bool:
	return (code >= SUBWAY_FIRST and code <= SUBWAY_LAST) or is_crossing(code) \
		or code == SUBWAY_STATION_LINK


## True when the code carries water.
static func conducts_water_code(code: int) -> bool:
	return is_pipe(code) or is_crossing(code)


## Connection mask of the pipe on this tile, 0 when there is none.
static func pipe_mask(code: int) -> int:
	if is_pipe(code):
		return code
	match code:
		CROSSING_PIPE_NS_UNDER_SUBWAY_EW, CROSSING_PIPE_NS_OVER_SUBWAY_EW:
			return NS_MASK
		CROSSING_PIPE_EW_UNDER_SUBWAY_NS, CROSSING_PIPE_EW_OVER_SUBWAY_NS:
			return EW_MASK
	return 0


## Connection mask of the subway on this tile, 0 when there is none.
static func subway_mask(code: int) -> int:
	if code >= SUBWAY_FIRST and code <= SUBWAY_LAST:
		return code - SUBWAY_OFFSET
	match code:
		CROSSING_PIPE_NS_UNDER_SUBWAY_EW, CROSSING_PIPE_NS_OVER_SUBWAY_EW:
			return EW_MASK
		CROSSING_PIPE_EW_UNDER_SUBWAY_NS, CROSSING_PIPE_EW_OVER_SUBWAY_NS:
			return NS_MASK
		SUBWAY_STATION_LINK:
			return NS_MASK | EW_MASK
	return 0


## Underground code for a pipe with the given connection mask (1..15).
static func pipe_code(mask: int) -> int:
	return clampi(mask, PIPE_FIRST, PIPE_LAST)


## Underground code for a subway tunnel with the given connection mask (1..15).
static func subway_code(mask: int) -> int:
	return clampi(mask, PIPE_FIRST, PIPE_LAST) + SUBWAY_OFFSET


# ── Building classification ──────────────────────────────────────────────

## A lot that carries and consumes utilities: anything built on a lot, including
## sites under construction and abandoned buildings.
static func is_lot(id: int) -> bool:
	return Buildings.is_developed(id) or Buildings.is_construction(id) or Buildings.is_abandoned(id)


static func is_water_facility(id: int) -> bool:
	return id == Buildings.WATER_PUMP or id == Buildings.WATER_TOWER \
		or id == Buildings.WATER_TREATMENT or id == Buildings.DESALINATION


static func conducts_power_building(id: int) -> bool:
	return Buildings.carries_power(id) or Buildings.is_construction(id) or Buildings.is_abandoned(id)


static func conducts_water_building(id: int) -> bool:
	return is_lot(id)


static func draws_power(id: int) -> bool:
	return is_lot(id) and not Buildings.is_power_plant(id)


static func draws_water(id: int) -> bool:
	return is_lot(id) and not is_water_facility(id)


static func ages(building_key: StringName) -> bool:
	return not (building_key in AGELESS_PLANTS)


# ── Per-id classification tables ─────────────────────────────────────────
##
## The monthly passes walk the packed map layers directly. Classifying a tile
## through these tables is one array lookup instead of a chain of roster
## queries, which is what keeps a full-map pass cheap. Each table has one byte
## per building id and is built once from the roster and the rules above.

static var _tables_built := false
static var _conducts_power_tbl := PackedByteArray()
static var _draws_power_tbl := PackedByteArray()
static var _power_plant_tbl := PackedByteArray()
static var _conducts_water_tbl := PackedByteArray()
static var _draws_water_tbl := PackedByteArray()
static var _water_facility_tbl := PackedByteArray()
static var _open_ground_tbl := PackedByteArray()
static var _multi_tile_tbl := PackedByteArray()
static var _width_tbl := PackedByteArray()
static var _height_tbl := PackedByteArray()
static var _conducts_water_code_tbl := PackedByteArray()


static func _build_tables() -> void:
	if _tables_built:
		return
	var n := Buildings.COUNT
	_conducts_power_tbl.resize(n)
	_draws_power_tbl.resize(n)
	_power_plant_tbl.resize(n)
	_conducts_water_tbl.resize(n)
	_draws_water_tbl.resize(n)
	_water_facility_tbl.resize(n)
	_open_ground_tbl.resize(n)
	_multi_tile_tbl.resize(n)
	_width_tbl.resize(n)
	_height_tbl.resize(n)
	for id in n:
		_conducts_power_tbl[id] = 1 if conducts_power_building(id) else 0
		_draws_power_tbl[id] = 1 if draws_power(id) else 0
		_power_plant_tbl[id] = 1 if Buildings.is_power_plant(id) else 0
		_conducts_water_tbl[id] = 1 if conducts_water_building(id) else 0
		_draws_water_tbl[id] = 1 if draws_water(id) else 0
		_water_facility_tbl[id] = 1 if is_water_facility(id) else 0
		_open_ground_tbl[id] = 1 if id == Buildings.NONE or Buildings.is_tree(id) else 0
		var s := Buildings.size(id)
		_multi_tile_tbl[id] = 1 if s.x > 1 or s.y > 1 else 0
		_width_tbl[id] = s.x
		_height_tbl[id] = s.y
	_conducts_water_code_tbl.resize(256)
	for code in 256:
		_conducts_water_code_tbl[code] = 1 if conducts_water_code(code) else 0
	_tables_built = true


## Building ids that carry power (lines, lots, sites, abandoned buildings).
static func conducts_power_table() -> PackedByteArray:
	_build_tables()
	return _conducts_power_tbl


## Building ids that draw power.
static func draws_power_table() -> PackedByteArray:
	_build_tables()
	return _draws_power_tbl


## Building ids that are power plants.
static func power_plant_table() -> PackedByteArray:
	_build_tables()
	return _power_plant_tbl


## Building ids that carry water.
static func conducts_water_table() -> PackedByteArray:
	_build_tables()
	return _conducts_water_tbl


## Building ids that draw water.
static func draws_water_table() -> PackedByteArray:
	_build_tables()
	return _draws_water_tbl


## Building ids that are pumps, towers, treatment or desalination plants.
static func water_facility_table() -> PackedByteArray:
	_build_tables()
	return _water_facility_tbl


## Open ground and trees: land that zoning alone makes conductive.
static func open_ground_table() -> PackedByteArray:
	_build_tables()
	return _open_ground_tbl


## Building ids with a footprint larger than one tile.
static func multi_tile_table() -> PackedByteArray:
	_build_tables()
	return _multi_tile_tbl


## Footprint width and height per building id.
static func footprint_width_table() -> PackedByteArray:
	_build_tables()
	return _width_tbl


static func footprint_height_table() -> PackedByteArray:
	_build_tables()
	return _height_tbl


## Underground codes that carry water.
static func conducts_water_code_table() -> PackedByteArray:
	_build_tables()
	return _conducts_water_code_tbl


## Whether tile `i` of a multi-tile footprint is its own anchor, exactly as
## `City.anchor_of`: the north-west tile of the lot whose corner cells carry a
## clockwise ring of corner flags in any of the four saved orientations, or
## the top-left of a same-id block without usable flags. Imported cities saved
## at another rotation carry CORNER_NW away from the top-left tile, so the flag
## alone does not mark the anchor. Single-tile buildings are always their own
## anchor.
static func is_anchor_tile(bld: PackedByteArray, zn: PackedByteArray, i: int) -> bool:
	var x := i % City.WIDTH
	@warning_ignore("integer_division")
	var y := i / City.WIDTH
	return City.is_footprint_anchor(bld, zn, x, y)
