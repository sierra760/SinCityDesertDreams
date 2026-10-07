# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Airports, seaports and military bases.
##
## Zoned port land develops on its own into runways, piers and support
## buildings; operating ports boost demand, provide jobs and send out planes,
## a helicopter and ships. Rules are in docs/simulation/ports.md; constants in
## PortParams.
extends SimSystem

const VEHICLE_PLANE := &"plane"
const VEHICLE_HELICOPTER := &"helicopter"
const VEHICLE_SHIP := &"ship"

const PHASE_CLIMB := &"climb"
const PHASE_CRUISE := &"cruise"
const PHASE_RETURN := &"return"
const PHASE_LAND := &"land"
const PHASE_FLY := &"fly"
const PHASE_INBOUND := &"inbound"
const PHASE_DOCKED := &"docked"
const PHASE_OUTBOUND := &"outbound"

## Military base kinds, as named by the rewards system.
const BASE_AIR := &"air"
const BASE_ARMY := &"army"
const BASE_NAVAL := &"naval"
const BASE_MISSILE := &"missile"

## Headings 0..7 clockwise from north, as tile steps.
const HEADING_STEP: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
## Neighbour order used when a crane looks for water: south, east, north, west.
const SHORE_ORDER: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
const EAST := Vector2i(1, 0)
const SOUTH := Vector2i(0, 1)

## Bridge pieces a ship may pass beneath.
const PASSABLE_BRIDGES: Array[StringName] = [
	&"bridge_suspension_start", &"bridge_suspension_rise", &"bridge_suspension_span",
	&"bridge_suspension_fall", &"bridge_suspension_end", &"bridge_lift_lowered",
	&"bridge_lift_raised", &"bridge_rail_span", &"power_elevated", &"bridge_reinforced_span",
]

var _ctx: SimContext
var _ports: Array[Dictionary] = []
var _ports_valid := false
var _vehicles: Array[Dictionary] = []
var _opened: Dictionary = {}
## Tiles of each opened port at its last report, by its _opened key. A port
## keeps its identity while it overlaps these tiles, so growing north or west
## (which moves its first scanned tile) does not reopen it. Not saved: after a
## load each key's own tile stands in for the set.
var _opened_tiles: Dictionary = {}
var _centre := Vector2i(City.HALF, City.HALF)


func _init() -> void:
	key = &"ports"


# ── Lifecycle ────────────────────────────────────────────────────────────

func setup(ctx: SimContext) -> void:
	_ctx = ctx
	_ports_valid = false
	_centre = _city_centre(ctx.city)


func daily(ctx: SimContext) -> void:
	_ensure_ports(ctx.city)
	_spawn_vehicles(ctx)
	_move_vehicles(ctx)


func monthly(ctx: SimContext, _phase: int = 0) -> void:
	var city := ctx.city
	_rebuild_ports(city)
	_centre = _city_centre(city)
	var base_kind := _military_kind(ctx)
	for port in _ports:
		var tiles: Array[Vector2i] = port.tiles.duplicate()
		for pos in tiles:
			if not ctx.rng.chance(1, PortParams.DEVELOP_CHANCE_DENOMINATOR):
				continue
			if port.kind != Zones.MILITARY and not _tile_powered(city, pos):
				continue
			var id := _choose_piece(port, base_kind)
			var placed := _try_place(ctx, port, pos, id)
			if not placed:
				var fallback := _fallback_piece(port, base_kind)
				if fallback != Buildings.NONE:
					placed = _try_place(ctx, port, pos, fallback)
			if placed:
				_count_pieces(city, port)
	_rebuild_ports(city)
	_report_openings(ctx)


func networks_changed(_ctx_unused: SimContext, _rect: Rect2i) -> void:
	_ports_valid = false


# ── Public getters ───────────────────────────────────────────────────────

## Vehicles for the renderer: kind, tile position, heading 0..7, frame counter
## and altitude (0 for ships).
func vehicles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for v in _vehicles:
		out.append({
			"kind": v.kind,
			"x": int(v.x),
			"y": int(v.y),
			"heading": int(v.heading),
			"frame": int(v.frame),
			"altitude": int(v.get("altitude", 0)),
		})
	return out


## Demand added by operating ports: (residential, commercial, industrial).
func demand_bonus() -> Vector3i:
	if _ctx == null:
		return Vector3i.ZERO
	_ensure_ports(_ctx.city)
	var com := 0
	var ind := 0
	for port in _ports:
		if not port.operating:
			continue
		var per_tile: int = int(port.developed) * PortParams.BONUS_PER_DEVELOPED_TILE
		if port.kind == Zones.AIRPORT:
			com += PortParams.AIRPORT_COMMERCIAL_BONUS + per_tile
		elif port.kind == Zones.SEAPORT:
			ind += PortParams.SEAPORT_INDUSTRIAL_BONUS + per_tile
	return Vector3i(0, mini(com, PortParams.DEMAND_BONUS_CAP), mini(ind, PortParams.DEMAND_BONUS_CAP))


## Jobs provided by developed port tiles.
func jobs() -> int:
	if _ctx == null:
		return 0
	_ensure_ports(_ctx.city)
	var total := 0
	for port in _ports:
		total += int(port.developed) * int(PortParams.JOBS_PER_TILE.get(port.kind, 0))
	return total


## One entry per port with its size, state and environmental load.
func port_report() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _ctx == null:
		return out
	_ensure_ports(_ctx.city)
	for port in _ports:
		var developed := int(port.developed)
		out.append({
			"kind": port.kind,
			"rect": port.rect,
			"tiles": port.tiles.size(),
			"developed": developed,
			"powered": port.powered,
			"operating": port.operating,
			"runways": int(port.runways),
			"cranes": int(port.cranes),
			"jobs": developed * int(PortParams.JOBS_PER_TILE.get(port.kind, 0)),
			"pollution": developed * int(PortParams.POLLUTION_PER_TILE.get(port.kind, 0)),
			"crime": developed * int(PortParams.CRIME_PER_TILE.get(port.kind, 0)),
		})
	return out


# ── Port enumeration ─────────────────────────────────────────────────────

func _ensure_ports(city: City) -> void:
	if not _ports_valid:
		_rebuild_ports(city)


## Group touching zone tiles of one port kind into ports.
func _rebuild_ports(city: City) -> void:
	_ports.clear()
	var zones := city.zone.data
	var visited := PackedByteArray()
	visited.resize(zones.size())
	for i in zones.size():
		if visited[i]:
			continue
		var kind := zones[i] & Zones.KIND_MASK
		if not Zones.is_port(kind) and kind != Zones.MILITARY:
			continue
		var tiles: Array[Vector2i] = []
		var tile_set: Dictionary = {}
		var queue: Array[int] = [i]
		visited[i] = 1
		while not queue.is_empty():
			var n: int = queue.pop_back()
			var p := _tile_of(n)
			tiles.append(p)
			tile_set[p] = true
			for d in SHORE_ORDER:
				var q := p + d
				if not city.in_bounds(q.x, q.y):
					continue
				var m := q.y * City.WIDTH + q.x
				if visited[m] or (zones[m] & Zones.KIND_MASK) != kind:
					continue
				visited[m] = 1
				queue.append(m)
		var port: Dictionary = {"kind": kind, "anchor": tiles[0], "tiles": tiles, "tile_set": tile_set}
		_count_pieces(city, port)
		_ports.append(port)
	_ports_valid = true


## The rectangle covering two tiles.
static func _rect_between(a: Vector2i, b: Vector2i) -> Rect2i:
	var lo := a.min(b)
	var hi := a.max(b)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## Count pieces, developed tiles, power and operating state of one port.
@warning_ignore("integer_division")
func _count_pieces(city: City, port: Dictionary) -> void:
	var counts: Dictionary = {}
	var developed := 0
	var runway_tiles: Array[Vector2i] = []
	var crane_tiles: Array[Vector2i] = []
	var powered := false
	var lo: Vector2i = port.tiles[0]
	var hi: Vector2i = port.tiles[0]
	for pos in port.tiles:
		lo = lo.min(pos)
		hi = hi.max(pos)
		if not powered and _tile_powered(city, pos):
			powered = true
		var id := city.building_at(pos.x, pos.y)
		if not _is_port_piece(id):
			continue
		developed += 1
		if id == Buildings.RUNWAY or id == Buildings.RUNWAY_CROSS:
			runway_tiles.append(pos)
		elif id == Buildings.CRANE:
			crane_tiles.append(pos)
		if Buildings.is_multi_tile(id) and not (Zones.corners(city.zone.at(pos.x, pos.y)) & Zones.CORNER_NW):
			continue
		counts[id] = int(counts.get(id, 0)) + 1
	port["counts"] = counts
	port["developed"] = developed
	port["powered"] = powered
	port["rect"] = _rect_between(lo, hi)
	port["runway_tiles"] = runway_tiles
	port["crane_tiles"] = crane_tiles
	port["runways"] = runway_tiles.size() / PortParams.RUNWAY_LENGTH
	port["cranes"] = crane_tiles.size()
	var operating := false
	match int(port.kind):
		Zones.AIRPORT:
			operating = powered and port.tiles.size() >= PortParams.AIRPORT_MIN_TILES and int(port.runways) >= 1
		Zones.SEAPORT:
			operating = powered and port.tiles.size() >= PortParams.SEAPORT_MIN_TILES and crane_tiles.size() >= 1
		Zones.MILITARY:
			operating = developed > 0
	port["operating"] = operating


static func _is_port_piece(id: int) -> bool:
	var c := Buildings.category(id)
	return c == Buildings.Category.PORT or c == Buildings.Category.MILITARY


static func _tile_powered(city: City, pos: Vector2i) -> bool:
	if city.is_powered(pos.x, pos.y):
		return true
	for d in SHORE_ORDER:
		if city.is_powered(pos.x + d.x, pos.y + d.y):
			return true
	return false


func _military_kind(ctx: SimContext) -> StringName:
	var rewards := ctx.system(&"rewards")
	if rewards != null and rewards.has_method("military_kind"):
		var k: StringName = rewards.call("military_kind")
		if k != &"":
			return k
	return BASE_AIR


func _report_openings(ctx: SimContext) -> void:
	var present: Dictionary = {}
	for port in _ports:
		var k := _opened_identity(port, present)
		present[k] = true
		var args := {"kind": port.kind, "x": port.anchor.x, "y": port.anchor.y}
		if port.operating and not _opened.has(k):
			_opened[k] = true
			_opened_tiles[k] = port.tile_set
			ctx.events.report(&"port_opened", args, 2)
		elif not port.operating and _opened.has(k):
			_opened.erase(k)
			_opened_tiles.erase(k)
			ctx.events.report(&"port_closed", args, 2)
		elif _opened.has(k):
			_opened_tiles[k] = port.tile_set
	for k in _opened.keys():
		if not present.has(k):
			_opened.erase(k)
			_opened_tiles.erase(k)


## The _opened key of an already opened port of the same kind this port
## overlaps, or the key of its first scanned tile. A matched key whose own tile
## has left the port moves to that tile, so a saved key still lies inside it.
func _opened_identity(port: Dictionary, claimed: Dictionary) -> String:
	var own := tile_key(port.anchor)
	var tile_set: Dictionary = port.tile_set
	for k: String in _opened.keys():
		if claimed.has(k):
			continue
		var at := parse_tile_key(k)
		var overlaps := tile_set.has(at)
		if not overlaps:
			var previous: Dictionary = _opened_tiles.get(k, {})
			for p: Vector2i in previous:
				if tile_set.has(p):
					overlaps = true
					break
		if not overlaps:
			continue
		if tile_set.has(at) or _opened.has(own):
			return k
		_opened.erase(k)
		_opened_tiles.erase(k)
		_opened[own] = true
		return own
	return own


# ── Piece selection ──────────────────────────────────────────────────────

static func _count_of(port: Dictionary, id: int) -> int:
	return int(port.counts.get(id, 0))


func _choose_piece(port: Dictionary, base_kind: StringName) -> int:
	match int(port.kind):
		Zones.AIRPORT:
			return _choose_airfield(port, false)
		Zones.SEAPORT:
			return _choose_harbour(port, false)
		Zones.MILITARY:
			match base_kind:
				BASE_ARMY:
					return _choose_army(port)
				BASE_NAVAL:
					return _choose_harbour(port, true)
				BASE_MISSILE:
					return Buildings.MISSILE_SILO
				_:
					return _choose_airfield(port, true)
	return Buildings.NONE


func _fallback_piece(port: Dictionary, base_kind: StringName) -> int:
	match int(port.kind):
		Zones.AIRPORT:
			return Buildings.HANGAR_SMALL
		Zones.SEAPORT:
			return Buildings.PORT_WAREHOUSE
		Zones.MILITARY:
			match base_kind:
				BASE_NAVAL:
					return Buildings.PORT_WAREHOUSE
				BASE_ARMY, BASE_MISSILE:
					return Buildings.NONE
				_:
					return Buildings.HANGAR_SMALL
	return Buildings.NONE


## Support buildings appear in proportion to the runways already laid.
@warning_ignore("integer_division")
static func _choose_airfield(port: Dictionary, military: bool) -> int:
	var runways := int(port.runways)
	var parking := Buildings.PARKING_MILITARY if military else Buildings.PARKING_CIVIL
	var tower := Buildings.MILITARY_TOWER if military else Buildings.CONTROL_TOWER
	if _count_of(port, parking) / 4 >= runways:
		return Buildings.RUNWAY
	if runways > 2 * _count_of(port, tower):
		return tower
	if runways > 2 * _count_of(port, Buildings.RADAR):
		return Buildings.RADAR
	if military:
		if runways > _count_of(port, Buildings.FIGHTER_JET):
			return Buildings.FIGHTER_JET
	elif runways > _count_of(port, Buildings.TARMAC):
		return Buildings.TARMAC
	if runways > _count_of(port, Buildings.PORT_BUILDING_A) / 2:
		return Buildings.PORT_BUILDING_A
	if runways > _count_of(port, Buildings.PORT_BUILDING_B) / 2:
		return Buildings.PORT_BUILDING_B
	if runways > _count_of(port, Buildings.HANGAR_LARGE) / 4:
		return Buildings.HANGAR_LARGE
	return parking


## Warehouses and yards appear in proportion to the cranes already built.
@warning_ignore("integer_division")
static func _choose_harbour(port: Dictionary, military: bool) -> int:
	var cranes := int(port.cranes)
	if _count_of(port, Buildings.CARGO_YARD) / 4 >= cranes:
		return Buildings.CRANE
	var bay := Buildings.RESTRICTED_FACILITY if military else Buildings.LOADING_BAY
	if cranes > _count_of(port, bay) / 4:
		return bay
	if cranes > _count_of(port, Buildings.PORT_WAREHOUSE) / 3:
		return Buildings.PORT_WAREHOUSE
	return Buildings.CARGO_YARD


@warning_ignore("integer_division")
static func _choose_army(port: Dictionary) -> int:
	if _count_of(port, Buildings.PARKING_MILITARY) / 4 <= _count_of(port, Buildings.HANGAR_SMALL) / 12:
		return Buildings.PARKING_MILITARY
	return Buildings.HANGAR_SMALL


# ── Placement ────────────────────────────────────────────────────────────

static func _empty_tile(city: City, pos: Vector2i) -> bool:
	return city.building_at(pos.x, pos.y) <= Buildings.TREES_7


## A support piece of any size that a runway may clear away.
static func _is_replaceable(id: int) -> bool:
	if not _is_port_piece(id):
		return false
	return id != Buildings.RUNWAY and id != Buildings.RUNWAY_CROSS and id != Buildings.CRANE and id != Buildings.PIER


## A 1×1 support piece that a larger piece may replace.
static func _is_support_piece(id: int) -> bool:
	return _is_replaceable(id) and not Buildings.is_multi_tile(id)


func _try_place(ctx: SimContext, port: Dictionary, pos: Vector2i, id: int) -> bool:
	match id:
		Buildings.NONE:
			return false
		Buildings.RUNWAY:
			return _place_runway(ctx, port, pos)
		Buildings.CRANE:
			return _place_crane(ctx, port, pos)
		_:
			return _place_footprint(ctx, port, pos, id)


## Place a piece anchored at `pos`. Every tile must belong to the port and be
## empty or hold a replaceable support piece.
func _place_footprint(ctx: SimContext, port: Dictionary, pos: Vector2i, id: int) -> bool:
	var city := ctx.city
	var size := Buildings.size(id)
	for dy in size.y:
		for dx in size.x:
			var p := pos + Vector2i(dx, dy)
			if not port.tile_set.has(p) or city.is_water(p.x, p.y):
				return false
			var old := city.building_at(p.x, p.y)
			if not (old <= Buildings.TREES_7 or _is_support_piece(old)):
				return false
	city.stamp_building(pos.x, pos.y, id, int(port.kind))
	ctx.events.mark_dirty(Rect2i(pos, size))
	return true


func _place_runway(ctx: SimContext, port: Dictionary, pos: Vector2i) -> bool:
	var directions: Array[Vector2i] = [EAST, SOUTH]
	if int(port.runways) % 2 == 1:
		directions = [SOUTH, EAST]
	for d in directions:
		var plan := _runway_plan(ctx.city, port, pos, d)
		if plan.is_empty():
			continue
		_lay_runway(ctx, port, plan)
		return true
	return false


## The tiles a runway from `pos` in direction `d` would touch, with what each
## becomes; empty when it does not fit.
func _runway_plan(city: City, port: Dictionary, pos: Vector2i, d: Vector2i) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var laid := 0
	var p := pos
	var guard := PortParams.RUNWAY_LENGTH * 4
	while laid < PortParams.RUNWAY_LENGTH and guard > 0:
		guard -= 1
		if not port.tile_set.has(p) or city.is_water(p.x, p.y):
			return []
		var id := city.building_at(p.x, p.y)
		if id == Buildings.RUNWAY:
			var same := _runway_runs_ew(city, p) == (d.x != 0)
			plan.append({"pos": p, "id": Buildings.RUNWAY if same else Buildings.RUNWAY_CROSS})
		elif id == Buildings.RUNWAY_CROSS:
			plan.append({"pos": p, "id": Buildings.RUNWAY_CROSS})
		elif id <= Buildings.TREES_7 or _is_replaceable(id):
			plan.append({"pos": p, "id": Buildings.RUNWAY})
			laid += 1
		else:
			return []
		p += d
	if laid < PortParams.RUNWAY_LENGTH:
		return []
	return plan


## Support buildings in the way are cleared first, whole footprints at a time,
## then the runway tiles are stamped.
func _lay_runway(ctx: SimContext, port: Dictionary, plan: Array[Dictionary]) -> void:
	var city := ctx.city
	var first: Vector2i = plan[0].pos
	var last: Vector2i = plan[plan.size() - 1].pos
	var dirty := _rect_between(first, last)
	for step in plan:
		var p: Vector2i = step.pos
		if _is_replaceable(city.building_at(p.x, p.y)):
			dirty = dirty.merge(city.clear_footprint(p.x, p.y))
	for step in plan:
		var p: Vector2i = step.pos
		if city.building_at(p.x, p.y) != int(step.id):
			city.stamp_building(p.x, p.y, int(step.id), int(port.kind))
	ctx.events.mark_dirty(dirty)


## A runway tile runs east–west when a runway continues east or west of it.
static func _runway_runs_ew(city: City, p: Vector2i) -> bool:
	for d in [EAST, -EAST]:
		var id := city.building_at(p.x + d.x, p.y + d.y)
		if id == Buildings.RUNWAY or id == Buildings.RUNWAY_CROSS:
			return true
	return false


## A crane on the shore with piers reaching over the water.
func _place_crane(ctx: SimContext, port: Dictionary, pos: Vector2i) -> bool:
	var city := ctx.city
	if city.is_water(pos.x, pos.y) or not _empty_tile(city, pos):
		return false
	var d := _shore_direction(city, pos)
	if d == Vector2i.ZERO:
		return false
	for i in range(1, PortParams.PIER_LENGTH + 2):
		var p := pos + d * i
		if not city.in_bounds(p.x, p.y) or not city.is_open_water(p.x, p.y):
			return false
		if city.building_at(p.x, p.y) != Buildings.NONE:
			return false
	var berth := pos + d * (PortParams.PIER_LENGTH + 1)
	if city.water_height(berth.x, berth.y) - city.ground_height(berth.x, berth.y) < PortParams.MIN_BERTH_DEPTH:
		return false
	city.stamp_building(pos.x, pos.y, Buildings.CRANE, int(port.kind))
	for i in range(1, PortParams.PIER_LENGTH + 1):
		var p := pos + d * i
		city.stamp_building(p.x, p.y, Buildings.PIER, int(port.kind))
		port.tile_set[p] = true
		port.tiles.append(p)
	ctx.events.mark_dirty(_rect_between(pos, pos + d * PortParams.PIER_LENGTH))
	return true


## First neighbour direction (south, east, north, west) that is open water.
static func _shore_direction(city: City, pos: Vector2i) -> Vector2i:
	for d in SHORE_ORDER:
		var p := pos + d
		if city.in_bounds(p.x, p.y) and city.is_open_water(p.x, p.y):
			return d
	return Vector2i.ZERO


## The water tile just beyond a crane's piers.
static func _berth_of(city: City, crane: Vector2i) -> Vector2i:
	for d in SHORE_ORDER:
		var p := crane + d
		if city.building_at(p.x, p.y) == Buildings.PIER:
			return crane + d * (PortParams.PIER_LENGTH + 1)
	return Vector2i(-1, -1)


# ── Vehicles ─────────────────────────────────────────────────────────────

func _count_vehicles(kind: StringName) -> int:
	var n := 0
	for v in _vehicles:
		if v.kind == kind:
			n += 1
	return n


func _spawn_vehicles(ctx: SimContext) -> void:
	for port in _ports:
		if not port.operating:
			continue
		if port.kind == Zones.AIRPORT:
			if _count_vehicles(VEHICLE_PLANE) < PortParams.MAX_PLANES and ctx.rng.chance(1, PortParams.PLANE_SPAWN_DENOMINATOR):
				_spawn_plane(ctx, port)
			if _count_vehicles(VEHICLE_HELICOPTER) == 0 and ctx.rng.chance(1, PortParams.HELICOPTER_SPAWN_DENOMINATOR):
				_spawn_helicopter(ctx, port)
		elif port.kind == Zones.SEAPORT:
			if _count_vehicles(VEHICLE_SHIP) == 0 and ctx.rng.chance(1, PortParams.SHIP_SPAWN_DENOMINATOR):
				_spawn_ship(ctx, port)


func _spawn_plane(ctx: SimContext, port: Dictionary) -> void:
	var runway: Vector2i = ctx.rng.pick(port.runway_tiles)
	var ew := _runway_runs_ew(ctx.city, runway)
	var heading := 2 if ew else 4
	if ctx.rng.chance(1, 2):
		heading = (heading + 4) % 8
	_vehicles.append({
		"kind": VEHICLE_PLANE, "x": runway.x, "y": runway.y, "heading": heading, "frame": 0,
		"altitude": 0, "phase": PHASE_CLIMB, "days": 0, "target": runway, "port": port.anchor,
	})


func _spawn_helicopter(ctx: SimContext, port: Dictionary) -> void:
	var runway: Vector2i = ctx.rng.pick(port.runway_tiles)
	_vehicles.append({
		"kind": VEHICLE_HELICOPTER, "x": runway.x, "y": runway.y, "heading": 0, "frame": 0,
		"altitude": PortParams.PLANE_CRUISE_ALTITUDE, "phase": PHASE_FLY, "days": 0,
		"target": _random_hover_target(ctx), "port": port.anchor,
	})


func _spawn_ship(ctx: SimContext, port: Dictionary) -> void:
	var city := ctx.city
	var crane: Vector2i = port.crane_tiles[0]
	var berth := _berth_of(city, crane)
	if berth.x < 0:
		return
	var route := _water_route(city, berth)
	if route.is_empty():
		return
	var first := _tile_of(route[0])
	_vehicles.append({
		"kind": VEHICLE_SHIP, "x": first.x, "y": first.y, "heading": 0, "frame": 0,
		"altitude": 0, "phase": PHASE_INBOUND, "days": 0, "target": berth, "port": port.anchor,
		"route": route, "index": 0,
	})


func _move_vehicles(ctx: SimContext) -> void:
	var keep: Array[Dictionary] = []
	for v in _vehicles:
		var alive := false
		match v.kind:
			VEHICLE_PLANE:
				alive = _move_plane(ctx, v)
			VEHICLE_HELICOPTER:
				alive = _move_helicopter(ctx, v)
			VEHICLE_SHIP:
				alive = _move_ship(ctx, v)
		if alive:
			v.frame = int(v.frame) + 1
			keep.append(v)
	_vehicles = keep


## Step one tile along the heading. Returns false, without moving, when the
## step would leave the map.
static func _step(v: Dictionary) -> bool:
	var d: Vector2i = HEADING_STEP[int(v.heading) & 7]
	var x := int(v.x) + d.x
	var y := int(v.y) + d.y
	if x < 0 or y < 0 or x >= City.WIDTH or y >= City.HEIGHT:
		return false
	v.x = x
	v.y = y
	return true


## Step, or turn toward the city centre when the map edge is reached.
func _step_or_turn_back(v: Dictionary) -> void:
	if not _step(v):
		v.heading = _heading_toward(Vector2i(int(v.x), int(v.y)), _centre)


static func _heading_toward(from: Vector2i, to: Vector2i) -> int:
	if from == to:
		return 0
	var angle := atan2(float(to.y - from.y), float(to.x - from.x)) + PI / 2.0
	var h := int(roundf(angle / (PI / 4.0)))
	return posmod(h, 8)


## Rotate one step toward the desired heading.
static func _turn_toward(current: int, desired: int) -> int:
	var diff := posmod(desired - current, 8)
	if diff == 0:
		return current
	return (current + 1) & 7 if diff <= 4 else (current - 1) & 7


static func _distance(v: Dictionary, target: Vector2i) -> int:
	return maxi(absi(int(v.x) - target.x), absi(int(v.y) - target.y))


## An arcology within the lookahead distance along a heading.
static func _obstacle_ahead(city: City, v: Dictionary, heading: int) -> bool:
	var d: Vector2i = HEADING_STEP[heading & 7]
	for i in range(1, PortParams.AIR_LOOKAHEAD + 1):
		var x := int(v.x) + d.x * i
		var y := int(v.y) + d.y * i
		if city.in_bounds(x, y) and Buildings.is_arcology(city.building_at(x, y)):
			return true
	return false


static func _avoid_obstacles(city: City, v: Dictionary) -> void:
	var heading := int(v.heading)
	if not _obstacle_ahead(city, v, heading):
		return
	for offset: int in [1, 7, 2, 6, 3, 5, 4]:
		var candidate: int = (heading + offset) & 7
		if not _obstacle_ahead(city, v, candidate):
			v.heading = candidate
			return


func _nearest_runway(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for port in _ports:
		if port.kind != Zones.AIRPORT or not port.operating:
			continue
		for r in port.runway_tiles:
			var d: int = absi(r.x - from.x) + absi(r.y - from.y)
			if d < best_d:
				best_d = d
				best = r
	return best


@warning_ignore("integer_division")
func _move_plane(ctx: SimContext, v: Dictionary) -> bool:
	var city := ctx.city
	v.days = int(v.days) + 1
	match v.phase:
		PHASE_CLIMB:
			v.altitude = mini(PortParams.PLANE_CRUISE_ALTITUDE, int(v.altitude) + maxi(1, PortParams.PLANE_CRUISE_ALTITUDE / PortParams.PLANE_CLIMB_DAYS))
			for _i in PortParams.PLANE_SPEED:
				_step_or_turn_back(v)
			if int(v.days) >= PortParams.PLANE_CLIMB_DAYS:
				v.phase = PHASE_CRUISE
				v.days = 0
		PHASE_CRUISE:
			if ctx.rng.chance(1, PortParams.PLANE_TURN_DENOMINATOR):
				v.heading = (int(v.heading) + (1 if ctx.rng.chance(1, 2) else 7)) & 7
			_avoid_obstacles(city, v)
			for _i in PortParams.PLANE_SPEED:
				_step_or_turn_back(v)
			if int(v.days) >= PortParams.PLANE_CRUISE_DAYS:
				var runway := _nearest_runway(Vector2i(int(v.x), int(v.y)))
				if runway.x < 0:
					# No operating airport left to land at; the flight leaves.
					return false
				v.target = runway
				v.phase = PHASE_RETURN
		PHASE_RETURN:
			var target: Vector2i = v.target
			v.heading = _turn_toward(int(v.heading), _heading_toward(Vector2i(int(v.x), int(v.y)), target))
			_avoid_obstacles(city, v)
			for _i in PortParams.PLANE_SPEED:
				if _distance(v, target) <= 1:
					break
				_step_or_turn_back(v)
			if _distance(v, target) <= 1:
				v.phase = PHASE_LAND
		PHASE_LAND:
			v.altitude = int(v.altitude) - maxi(1, PortParams.PLANE_CRUISE_ALTITUDE / PortParams.PLANE_CLIMB_DAYS)
			if int(v.altitude) <= 0:
				return false
	return true


func _random_hover_target(ctx: SimContext) -> Vector2i:
	var r := PortParams.HELICOPTER_RANGE
	var x := _centre.x - r + ctx.rng.below(2 * r + 1)
	var y := _centre.y - r + ctx.rng.below(2 * r + 1)
	return Vector2i(clampi(x, 0, City.WIDTH - 1), clampi(y, 0, City.HEIGHT - 1))


func _move_helicopter(ctx: SimContext, v: Dictionary) -> bool:
	if _nearest_runway(Vector2i(int(v.x), int(v.y))).x < 0:
		return false
	var target: Vector2i = v.target
	v.heading = _heading_toward(Vector2i(int(v.x), int(v.y)), target)
	_avoid_obstacles(ctx.city, v)
	for _i in PortParams.HELICOPTER_SPEED:
		if _distance(v, target) <= 1 or not _step(v):
			break
	if _distance(v, target) <= 1:
		v.target = _random_hover_target(ctx)
	return true


func _move_ship(ctx: SimContext, v: Dictionary) -> bool:
	var city := ctx.city
	var route: PackedInt32Array = v.route
	if route.is_empty():
		return false
	match v.phase:
		PHASE_INBOUND:
			var last := route.size() - 1
			var next := mini(last, int(v.index) + PortParams.SHIP_SPEED)
			if not _sail_to(city, v, route, next):
				return false
			if int(v.index) >= last:
				v.phase = PHASE_DOCKED
				v.days = PortParams.SHIP_DOCK_DAYS
		PHASE_DOCKED:
			v.days = int(v.days) - 1
			if int(v.days) <= 0:
				v.phase = PHASE_OUTBOUND
				v.heading = (int(v.heading) + 4) & 7
		PHASE_OUTBOUND:
			var next := int(v.index) - PortParams.SHIP_SPEED
			if next < 0:
				return false
			if not _sail_to(city, v, route, next):
				return false
	return true


## Move along the route to `next`, checking every tile is still open water.
func _sail_to(city: City, v: Dictionary, route: PackedInt32Array, next: int) -> bool:
	var index := int(v.index)
	var step := 1 if next > index else -1
	while index != next:
		index += step
		var p := _tile_of(route[index])
		if not _navigable(city, p):
			return false
		v.heading = _heading_toward(Vector2i(int(v.x), int(v.y)), p)
		v.x = p.x
		v.y = p.y
	v.index = index
	return true


static func _navigable(city: City, p: Vector2i) -> bool:
	if not city.in_bounds(p.x, p.y) or not city.is_open_water(p.x, p.y):
		return false
	var id := city.building_at(p.x, p.y)
	if id == Buildings.NONE:
		return true
	return Buildings.category(id) == Buildings.Category.BRIDGE and Buildings.key(id) in PASSABLE_BRIDGES


static func _is_edge(p: Vector2i) -> bool:
	return p.x == 0 or p.y == 0 or p.x == City.WIDTH - 1 or p.y == City.HEIGHT - 1


@warning_ignore("integer_division")
static func _tile_of(index: int) -> Vector2i:
	return Vector2i(index % City.WIDTH, index / City.WIDTH)


## Shortest open-water route from a map edge to the berth, edge first.
static func _water_route(city: City, berth: Vector2i) -> PackedInt32Array:
	var empty := PackedInt32Array()
	if not _navigable(city, berth):
		return empty
	var parent := PackedInt32Array()
	parent.resize(City.WIDTH * City.HEIGHT)
	parent.fill(-1)
	var start := berth.y * City.WIDTH + berth.x
	parent[start] = start
	var queue: Array[int] = [start]
	var head := 0
	var found := -1
	while head < queue.size():
		var n: int = queue[head]
		head += 1
		var p := _tile_of(n)
		if _is_edge(p):
			found = n
			break
		for d in SHORE_ORDER:
			var q := p + d
			if not city.in_bounds(q.x, q.y):
				continue
			var m := q.y * City.WIDTH + q.x
			if parent[m] >= 0 or not _navigable(city, q):
				continue
			parent[m] = n
			queue.append(m)
	if found < 0:
		return empty
	var route := PackedInt32Array()
	var cursor := found
	while cursor != start:
		route.append(cursor)
		cursor = parent[cursor]
	route.append(start)
	return route


## Centroid of the city's residential, commercial and industrial buildings.
@warning_ignore("integer_division")
static func _city_centre(city: City) -> Vector2i:
	if _zone_building_table.is_empty():
		_zone_building_table.resize(Buildings.COUNT)
		for id: int in Buildings.COUNT:
			_zone_building_table[id] = 1 if Buildings.is_zone_building(id) else 0
	var data := city.building.data
	var sx := 0
	var sy := 0
	var n := 0
	for i in data.size():
		if _zone_building_table[data[i]] != 0:
			sx += i % City.WIDTH
			sy += i / City.WIDTH
			n += 1
	if n == 0:
		return Vector2i(City.HALF, City.HALF)
	return Vector2i(sx / n, sy / n)


## Only immutable roster membership is cached; every city tile is read afresh.
static var _zone_building_table := PackedByteArray()


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	var vs: Array = []
	for v in _vehicles:
		var target: Vector2i = v.target
		var port: Vector2i = v.port
		var entry := {
			"kind": String(v.kind),
			"x": int(v.x), "y": int(v.y), "heading": int(v.heading), "frame": int(v.frame),
			"altitude": int(v.get("altitude", 0)), "phase": String(v.phase), "days": int(v.days),
			"target": [target.x, target.y], "port": [port.x, port.y],
		}
		if v.has("route"):
			entry["route"] = Array(v.route)
			entry["index"] = int(v.index)
		vs.append(entry)
	var opened: Array = []
	for k in _opened:
		opened.append(String(k))
	return {"vehicles": vs, "opened": opened, "centre": [_centre.x, _centre.y]}


func load(data: Dictionary) -> void:
	_vehicles.clear()
	for entry in data.get("vehicles", []):
		var e: Dictionary = entry
		var target: Array = e.get("target", [0, 0])
		var port: Array = e.get("port", [0, 0])
		var v: Dictionary = {
			"kind": StringName(String(e.get("kind", ""))),
			"x": int(e.get("x", 0)), "y": int(e.get("y", 0)),
			"heading": int(e.get("heading", 0)), "frame": int(e.get("frame", 0)),
			"altitude": int(e.get("altitude", 0)),
			"phase": StringName(String(e.get("phase", ""))), "days": int(e.get("days", 0)),
			"target": Vector2i(int(target[0]), int(target[1])),
			"port": Vector2i(int(port[0]), int(port[1])),
		}
		if e.has("route"):
			var route := PackedInt32Array()
			for n in e.route:
				route.append(int(n))
			v["route"] = route
			v["index"] = int(e.get("index", 0))
		_vehicles.append(v)
	_opened.clear()
	_opened_tiles.clear()
	for k in data.get("opened", []):
		_opened[String(k)] = true
	var centre: Array = data.get("centre", [City.HALF, City.HALF])
	_centre = Vector2i(int(centre[0]), int(centre[1]))
	_ports_valid = false
