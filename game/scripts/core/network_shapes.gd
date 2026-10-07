# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Network geometry: which building id a road, rail, power line, highway,
## pipe or subway tile takes given what it connects to.
##
## A connection mask has four bits: N = 1, E = 2, S = 4, W = 8. Fifteen
## surface shapes cover every tile: two straights, four slope pieces, four
## bends, four T junctions and one crossroads. Roads, rail and power lines
## share one mask-to-shape table and add their own base id; highways work on
## 2×2 blocks; pipes and subways store the mask itself in the underground
## layer.
class_name NetworkShapes
extends RefCounted

enum Family { NONE, ROAD, RAIL, POWER, HIGHWAY, PIPE, SUBWAY }

const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8
const AXIS_NS := 1
const AXIS_EW := 2
const AXIS_ANY := 3

## Shape offsets shared by roads and power lines (rail maps them below).
const SHAPE_NS := 0
const SHAPE_EW := 1
const SHAPE_SLOPE_W := 2
const SHAPE_SLOPE_N := 3
const SHAPE_SLOPE_E := 4
const SHAPE_SLOPE_S := 5
const SHAPE_NE := 6
const SHAPE_SE := 7
const SHAPE_SW := 8
const SHAPE_NW := 9
const SHAPE_NEW := 10
const SHAPE_NES := 11
const SHAPE_ESW := 12
const SHAPE_NSW := 13
const SHAPE_NESW := 14

## Connection mask → shape offset. A lone tile or a dead end is drawn as the
## straight piece that continues the run it belongs to.
const SHAPE_BY_MASK := [
	SHAPE_NS, SHAPE_NS, SHAPE_EW, SHAPE_NE,
	SHAPE_NS, SHAPE_NS, SHAPE_SE, SHAPE_NES,
	SHAPE_EW, SHAPE_NW, SHAPE_EW, SHAPE_NEW,
	SHAPE_SW, SHAPE_NSW, SHAPE_ESW, SHAPE_NESW,
]

## Canonical SC2 rail ids use the same shape order as roads. Imported grids
## and newly constructed networks therefore share one interpretation.
const RAIL_BY_SHAPE := [
	Buildings.RAIL_FIRST, Buildings.RAIL_FIRST + 1,
	46, 47, 48, 49,
	50, 51, 52, 53, 54, 55, 56, 57, 58,
]

## Underground layer codes, shared with the utility systems. A pipe's code is
## its connection mask; a subway's code is its mask plus SUBWAY_OFFSET. The
## crossings carry one straight run of each network; the station link joins
## a subway station to tunnels on every side.
const PIPE_FIRST := 1
const PIPE_LAST := 15
const SUBWAY_FIRST := 16
const SUBWAY_LAST := 30
const SUBWAY_OFFSET := 15
const PIPE_NS_SUBWAY_EW := 31
const PIPE_EW_SUBWAY_NS := 32
const PIPE_NS_OVER_SUBWAY_EW := 33
const PIPE_EW_OVER_SUBWAY_NS := 34
const STATION_LINK := 35

## Surface crossing ids by pair and orientation.
const CROSS_POWER_EW_ROAD_NS := 67
const CROSS_POWER_NS_ROAD_EW := 68
const CROSS_ROAD_NS_RAIL_EW := 69
const CROSS_ROAD_EW_RAIL_NS := 70
const CROSS_POWER_EW_RAIL_NS := 71
const CROSS_POWER_NS_RAIL_EW := 72
const RAIL_POWER_NS := 71
const RAIL_POWER_EW := 72
const RAIL_ROAD_NS := 70
const RAIL_ROAD_EW := 69

## Highway ids.
const HIGHWAY_NS := 73
const HIGHWAY_EW := 74
const HIGHWAY_NS_ROAD_EW := 75
const HIGHWAY_EW_ROAD_NS := 76
const HIGHWAY_NS_RAIL_EW := 77
const HIGHWAY_EW_RAIL_NS := 78
const HIGHWAY_NS_POWER_EW := 79
const HIGHWAY_EW_POWER_NS := 80
const HIGHWAY_SLOPE_W := 97
const HIGHWAY_SLOPE_N := 98
const HIGHWAY_SLOPE_E := 99
const HIGHWAY_SLOPE_S := 100
const HIGHWAY_CORNER_NE := 101
const HIGHWAY_CORNER_SE := 102
const HIGHWAY_CORNER_SW := 103
const HIGHWAY_CORNER_NW := 104
const HIGHWAY_JUNCTION := 105

const DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIRECTION_BITS: Array[int] = [NORTH, EAST, SOUTH, WEST]


# ── Shape lookup ─────────────────────────────────────────────────────────

## Building id for a surface network tile with the given connections on the
## given terrain code. Straight slopes give slope pieces regardless of mask.
static func shape_id(family: int, mask: int, terrain_code: int = Terrain.FLAT) -> int:
	var slope := Terrain.slope(terrain_code)
	var offset: int = SHAPE_BY_MASK[mask & 0x0F]
	if Terrain.is_edge_slope(slope) and not Terrain.is_water(terrain_code):
		offset = SHAPE_SLOPE_W + (slope - Terrain.SLOPE_W)
	match family:
		Family.ROAD:
			return Buildings.ROAD_FIRST + offset
		Family.POWER:
			return Buildings.POWER_LINE_FIRST + offset
		Family.RAIL:
			return RAIL_BY_SHAPE[offset]
		Family.PIPE, Family.SUBWAY:
			return underground_code(family, mask, 0)
		Family.HIGHWAY:
			return highway_id(mask, AXIS_EW if (mask & (EAST | WEST)) != 0 or mask == 0 else AXIS_NS, terrain_code)
	return Buildings.NONE


## Underground code for a pipe or subway with the given connections. A tile
## with no connections keeps the straight run of `current` when it has one,
## otherwise it becomes an east-west run.
static func underground_code(family: int, mask: int, current: int = 0) -> int:
	var m := mask & 0x0F
	if m == 0:
		var straight := NORTH | SOUTH if underground_axis(current, family) == AXIS_NS \
			or underground_mask(current, family) == NORTH | SOUTH else EAST | WEST
		m = straight
	return m if family == Family.PIPE else m + SUBWAY_OFFSET


## Straight underground run along an axis.
static func underground_straight(family: int, axis: int) -> int:
	return underground_code(family, NORTH | SOUTH if axis == AXIS_NS else EAST | WEST, 0)


## Connection mask carried by an underground code for `family`, 0 when the
## code is not part of that network.
static func underground_mask(code: int, family: int) -> int:
	if family == Family.PIPE:
		if code >= PIPE_FIRST and code <= PIPE_LAST: return code
		if code == PIPE_NS_SUBWAY_EW or code == PIPE_NS_OVER_SUBWAY_EW: return NORTH | SOUTH
		if code == PIPE_EW_SUBWAY_NS or code == PIPE_EW_OVER_SUBWAY_NS: return EAST | WEST
	elif family == Family.SUBWAY:
		if code >= SUBWAY_FIRST and code <= SUBWAY_LAST: return code - SUBWAY_OFFSET
		if code == PIPE_NS_SUBWAY_EW or code == PIPE_NS_OVER_SUBWAY_EW: return EAST | WEST
		if code == PIPE_EW_SUBWAY_NS or code == PIPE_EW_OVER_SUBWAY_NS: return NORTH | SOUTH
		if code == STATION_LINK: return 0x0F
	return 0


## Highway piece for a block mask. `axis_hint` decides the straight piece for
## a lone block. Three or four connections make an interchange.
static func highway_id(mask: int, axis_hint: int = AXIS_EW, terrain_code: int = Terrain.FLAT) -> int:
	var slope := Terrain.slope(terrain_code)
	if Terrain.is_edge_slope(slope):
		return HIGHWAY_SLOPE_W + (slope - Terrain.SLOPE_W)
	var m := mask & 0x0F
	if m == 0:
		return HIGHWAY_NS if axis_hint == AXIS_NS else HIGHWAY_EW
	if m == NORTH or m == SOUTH or m == NORTH | SOUTH:
		return HIGHWAY_NS
	if m == EAST or m == WEST or m == EAST | WEST:
		return HIGHWAY_EW
	if m == NORTH | EAST:
		return HIGHWAY_CORNER_NE
	if m == EAST | SOUTH:
		return HIGHWAY_CORNER_SE
	if m == SOUTH | WEST:
		return HIGHWAY_CORNER_SW
	if m == NORTH | WEST:
		return HIGHWAY_CORNER_NW
	return HIGHWAY_JUNCTION


## Crossing id when `family` is laid across an existing straight tile of
## another network, or NONE when no crossing exists for that pair.
static func crossing_id(family: int, existing: int) -> int:
	var road_ew := Buildings.ROAD_FIRST + SHAPE_EW
	var road_ns := Buildings.ROAD_FIRST + SHAPE_NS
	var rail_ew := Buildings.RAIL_FIRST + SHAPE_EW
	var rail_ns := Buildings.RAIL_FIRST + SHAPE_NS
	var power_ew := Buildings.POWER_LINE_FIRST + SHAPE_EW
	var power_ns := Buildings.POWER_LINE_FIRST + SHAPE_NS
	if family == Family.ROAD:
		if existing == power_ew: return CROSS_POWER_EW_ROAD_NS
		if existing == power_ns: return CROSS_POWER_NS_ROAD_EW
		if existing == rail_ew: return CROSS_ROAD_NS_RAIL_EW
		if existing == rail_ns: return CROSS_ROAD_EW_RAIL_NS
	elif family == Family.RAIL:
		if existing == road_ew: return CROSS_ROAD_EW_RAIL_NS
		if existing == road_ns: return CROSS_ROAD_NS_RAIL_EW
		if existing == power_ew: return CROSS_POWER_EW_RAIL_NS
		if existing == power_ns: return CROSS_POWER_NS_RAIL_EW
	elif family == Family.POWER:
		if existing == road_ew: return CROSS_POWER_NS_ROAD_EW
		if existing == road_ns: return CROSS_POWER_EW_ROAD_NS
		if existing == rail_ew: return CROSS_POWER_NS_RAIL_EW
		if existing == rail_ns: return CROSS_POWER_EW_RAIL_NS
	return Buildings.NONE


## Highway crossing id for a straight highway on `axis` over an existing
## straight road, rail or power line running the other way.
static func highway_crossing_id(axis: int, existing: int) -> int:
	if axis == AXIS_EW:
		if existing == Buildings.ROAD_FIRST + SHAPE_NS: return HIGHWAY_EW_ROAD_NS
		if existing == Buildings.RAIL_FIRST + SHAPE_NS: return HIGHWAY_EW_RAIL_NS
		if existing == Buildings.POWER_LINE_FIRST + SHAPE_NS: return HIGHWAY_EW_POWER_NS
	else:
		if existing == Buildings.ROAD_FIRST + SHAPE_EW: return HIGHWAY_NS_ROAD_EW
		if existing == Buildings.RAIL_FIRST + SHAPE_EW: return HIGHWAY_NS_RAIL_EW
		if existing == Buildings.POWER_LINE_FIRST + SHAPE_EW: return HIGHWAY_NS_POWER_EW
	return Buildings.NONE


## Underground crossing code for laying `family` over an existing straight
## run of the other underground network.
static func underground_crossing(family: int, existing: int) -> int:
	if family == Family.PIPE:
		if existing == SUBWAY_OFFSET + (EAST | WEST): return PIPE_NS_SUBWAY_EW
		if existing == SUBWAY_OFFSET + (NORTH | SOUTH): return PIPE_EW_SUBWAY_NS
	elif family == Family.SUBWAY:
		if existing == EAST | WEST: return PIPE_EW_SUBWAY_NS
		if existing == NORTH | SOUTH: return PIPE_NS_SUBWAY_EW
	return 0


# ── Family membership and orientation ────────────────────────────────────

static func is_plain_road(id: int) -> bool:
	return id >= Buildings.ROAD_FIRST and id <= Buildings.ROAD_LAST


static func is_plain_rail(id: int) -> bool:
	return id >= Buildings.RAIL_FIRST and id <= Buildings.RAIL_LAST


static func is_plain_power(id: int) -> bool:
	return id >= Buildings.POWER_LINE_FIRST and id <= Buildings.POWER_LINE_LAST


static func is_highway(id: int) -> bool:
	return (id >= Buildings.HIGHWAY_FIRST and id <= Buildings.HIGHWAY_LAST) \
		or (id >= Buildings.HIGHWAY_PIECE_FIRST and id <= Buildings.HIGHWAY_PIECE_LAST)


static func is_onramp(id: int) -> bool:
	return id >= Buildings.ONRAMP_FIRST and id <= Buildings.ONRAMP_LAST


static func is_tunnel(id: int) -> bool:
	return id >= Buildings.TUNNEL_FIRST and id <= Buildings.TUNNEL_LAST


static func is_subway_portal(id: int) -> bool:
	return id >= Buildings.SUBWAY_PORTAL_FIRST and id <= Buildings.SUBWAY_PORTAL_LAST


static func is_road_bridge(id: int) -> bool:
	return (id >= Buildings.BRIDGE_FIRST and id <= 89) or id == Buildings.REINFORCED_PYLON \
		or id == Buildings.REINFORCED_BRIDGE


static func is_rail_bridge(id: int) -> bool:
	return id == 90 or id == 91


static func is_power_bridge(id: int) -> bool:
	return id == 92


## Whether a surface id belongs to the road family for connection purposes.
## Highways are a separate family joined to roads only through ramps.
static func in_road_family(id: int) -> bool:
	if is_plain_road(id) or is_tunnel(id) or is_onramp(id) or is_road_bridge(id):
		return true
	return (id >= Buildings.CROSSING_FIRST and id <= Buildings.CROSSING_FIRST + 3) \
		or id == HIGHWAY_EW_ROAD_NS or id == HIGHWAY_NS_ROAD_EW


static func in_rail_family(id: int) -> bool:
	if is_plain_rail(id) or is_rail_bridge(id) or is_subway_portal(id):
		return true
	return id == RAIL_POWER_EW or id == RAIL_POWER_NS \
		or (id >= Buildings.CROSSING_FIRST + 2 and id <= Buildings.CROSSING_LAST) \
		or id == HIGHWAY_EW_RAIL_NS or id == HIGHWAY_NS_RAIL_EW


static func in_power_family(id: int) -> bool:
	if is_plain_power(id) or is_power_bridge(id):
		return true
	return id == CROSS_POWER_NS_ROAD_EW \
		or id == CROSS_POWER_EW_ROAD_NS or id == CROSS_POWER_NS_RAIL_EW or id == CROSS_POWER_EW_RAIL_NS \
		or id == HIGHWAY_EW_POWER_NS or id == HIGHWAY_NS_POWER_EW or Buildings.is_developed(id)


static func in_family(id: int, family: int) -> bool:
	match family:
		Family.ROAD: return in_road_family(id)
		Family.RAIL: return in_rail_family(id)
		Family.POWER: return in_power_family(id)
		Family.HIGHWAY: return is_highway(id)
	return false


## Family of the surface id when it is a plain, reshapeable network tile.
static func plain_family(id: int) -> int:
	if is_plain_road(id): return Family.ROAD
	if is_plain_rail(id): return Family.RAIL
	if is_plain_power(id): return Family.POWER
	return Family.NONE


## Axis a fixed-orientation tile carries for `family`: AXIS_NS, AXIS_EW, or
## AXIS_ANY for tiles that reshape freely (plain runs, bridges, buildings).
static func axis_for(id: int, family: int) -> int:
	var shape_offset := -1
	match family:
		Family.ROAD:
			if is_plain_road(id): shape_offset = id - Buildings.ROAD_FIRST
			elif id == 63 or id == 65: return AXIS_EW
			elif id == 64 or id == 66: return AXIS_NS
			elif id == CROSS_POWER_NS_ROAD_EW or id == CROSS_ROAD_EW_RAIL_NS or id == HIGHWAY_NS_ROAD_EW: return AXIS_EW
			elif id == CROSS_POWER_EW_ROAD_NS or id == CROSS_ROAD_NS_RAIL_EW or id == HIGHWAY_EW_ROAD_NS: return AXIS_NS
		Family.RAIL:
			if is_plain_rail(id):
				if id in [46,48,59,61]: return AXIS_EW
				if id in [47,49,60,62]: return AXIS_NS
				return AXIS_ANY
			elif id == CROSS_ROAD_NS_RAIL_EW or id == CROSS_POWER_NS_RAIL_EW \
					or id == HIGHWAY_NS_RAIL_EW:
				return AXIS_EW
			elif id == CROSS_ROAD_EW_RAIL_NS or id == CROSS_POWER_EW_RAIL_NS \
					or id == HIGHWAY_EW_RAIL_NS:
				return AXIS_NS
			elif id == Buildings.SUBWAY_PORTAL_FIRST or id == Buildings.SUBWAY_PORTAL_FIRST + 2: return AXIS_NS
			elif id == Buildings.SUBWAY_PORTAL_FIRST + 1 or id == Buildings.SUBWAY_PORTAL_FIRST + 3: return AXIS_EW
		Family.POWER:
			if is_plain_power(id): shape_offset = id - Buildings.POWER_LINE_FIRST
			elif id == CROSS_POWER_EW_ROAD_NS or id == CROSS_POWER_EW_RAIL_NS or id == HIGHWAY_NS_POWER_EW:
				return AXIS_EW
			elif id == CROSS_POWER_NS_ROAD_EW or id == CROSS_POWER_NS_RAIL_EW or id == HIGHWAY_EW_POWER_NS:
				return AXIS_NS
	if shape_offset == SHAPE_SLOPE_N or shape_offset == SHAPE_SLOPE_S:
		return AXIS_NS
	if shape_offset == SHAPE_SLOPE_E or shape_offset == SHAPE_SLOPE_W:
		return AXIS_EW
	return AXIS_ANY


## Underground family membership.
static func underground_in_family(code: int, family: int) -> bool:
	return underground_mask(code, family) != 0


## Axis a fixed underground code carries: crossings are straight runs,
## everything else reshapes freely.
static func underground_axis(code: int, family: int) -> int:
	if code >= PIPE_NS_SUBWAY_EW and code <= PIPE_EW_OVER_SUBWAY_NS:
		var m := underground_mask(code, family)
		return AXIS_NS if m == NORTH | SOUTH else AXIS_EW
	return AXIS_ANY


static func underground_plain_family(code: int) -> int:
	if code >= PIPE_FIRST and code <= PIPE_LAST: return Family.PIPE
	if code >= SUBWAY_FIRST and code <= SUBWAY_LAST: return Family.SUBWAY
	return Family.NONE


# ── Connection masks ─────────────────────────────────────────────────────

static func _axis_allows(axis: int, direction: int) -> bool:
	if axis == AXIS_ANY:
		return true
	var vertical := direction == 0 or direction == 2
	return axis == AXIS_NS if vertical else axis == AXIS_EW


## Which of the four neighbours of (x, y) connect to a `family` tile there.
static func connection_mask(city: City, x: int, y: int, family: int) -> int:
	var mask := 0
	for d in 4:
		var n: Vector2i = Vector2i(x, y) + DIRECTIONS[d]
		if not city.in_bounds(n.x, n.y):
			continue
		if family == Family.PIPE or family == Family.SUBWAY:
			var code := city.underground.at(n.x, n.y)
			if underground_in_family(code, family) and _axis_allows(underground_axis(code, family), d):
				mask |= DIRECTION_BITS[d]
		else:
			var id := city.building_at(n.x, n.y)
			if in_family(id, family) and _axis_allows(axis_for(id, family), d):
				mask |= DIRECTION_BITS[d]
	return mask


## Highway blocks connect at block distance. (bx, by) is the block anchor.
static func highway_block_mask(city: City, bx: int, by: int) -> int:
	var mask := 0
	for d in 4:
		var n: Vector2i = Vector2i(bx, by) + DIRECTIONS[d] * 2
		if not city.in_bounds(n.x, n.y):
			continue
		if is_highway(city.building_at(n.x, n.y)):
			mask |= DIRECTION_BITS[d]
	return mask


# ── Reshaping ────────────────────────────────────────────────────────────

## Recompute the shape of one tile from its neighbours. Fixed pieces
## (crossings, bridges, tunnels, ramps) keep their id.
static func reshape_tile(city: City, x: int, y: int) -> void:
	if not city.in_bounds(x, y):
		return
	var id := city.building_at(x, y)
	var family := plain_family(id)
	if family != Family.NONE and axis_for(id, family) == AXIS_ANY:
		var mask := connection_mask(city, x, y, family)
		city.building.put(x, y, shape_id(family, mask, city.terrain.at(x, y)))
	var code := city.underground.at(x, y)
	var under := underground_plain_family(code)
	if under != Family.NONE:
		var mask := connection_mask(city, x, y, under)
		city.underground.put(x, y, underground_code(under, mask, code))


## Reshape (x, y) and its four neighbours after a change there.
static func reshape(city: City, x: int, y: int) -> void:
	reshape_tile(city, x, y)
	for d in DIRECTIONS:
		reshape_tile(city, x + d.x, y + d.y)


## Reshape a highway block and its four block neighbours. Crossing and slope
## tiles inside a block keep their fixed ids.
static func reshape_highway_block(city: City, bx: int, by: int, axis_hint: int = AXIS_EW) -> void:
	_reshape_one_block(city, bx, by, axis_hint)
	for d in DIRECTIONS:
		_reshape_one_block(city, bx + d.x * 2, by + d.y * 2, axis_hint)


static func _reshape_one_block(city: City, bx: int, by: int, axis_hint: int) -> void:
	if not city.in_bounds(bx, by) or not is_highway(city.building_at(bx, by)):
		return
	var mask := highway_block_mask(city, bx, by)
	for dy in 2:
		for dx in 2:
			var id := city.building_at(bx + dx, by + dy)
			if id == HIGHWAY_EW or id == HIGHWAY_NS or id == HIGHWAY_JUNCTION \
					or (id >= HIGHWAY_CORNER_NE and id <= HIGHWAY_CORNER_NW):
				city.building.put(bx + dx, by + dy, highway_id(mask, axis_hint))


## Anchor of the 2×2 highway block containing a tile.
static func block_anchor(p: Vector2i) -> Vector2i:
	return Vector2i(p.x & ~1, p.y & ~1)


## Canonical road/highway endpoints shared by active 3D ramp geometry.
static func onramp_endpoints(code: int, axis: bool, rotation: int = 0) -> Array:
	const DIRECTIONS := [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
	const PAIRS := [[1,0],[3,0],[3,2],[1,2]]
	var pair: Array = PAIRS[clampi(code - Buildings.ONRAMP_FIRST,0,3)]
	var road: Vector2i = DIRECTIONS[pair[0]]
	var highway: Vector2i = DIRECTIONS[pair[1]]
	if axis:
		road = Vector2i(road.y,road.x)
		highway = Vector2i(highway.y,highway.x)
	for turn in posmod(rotation,4):
		road = Vector2i(road.y,-road.x)
		highway = Vector2i(highway.y,-highway.x)
	return [road,highway]
