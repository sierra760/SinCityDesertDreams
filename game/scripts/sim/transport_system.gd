# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Traffic and transit routing. See docs/simulation/traffic.md.
##
## Once a month a trip leaves every residential lot (or an even sample of
## them) for the nearest commercial or industrial lot over roads, highways,
## rail and subway. Arriving trips deposit congestion on the road tiles they
## drove and count as riders on the transit they used; failed trips feed the
## unreachable ratio the zone system reads.
class_name TransportSystem
extends SimSystem

## Independent from the 160 resident origins / 32000 resident search states.
const TOURIST_ORIGINS := 1024
const TOURIST_SEARCH_WORK := 131072
const TOURIST_PATH_WORK := 131072
const TOURIST_QUEUE := 32
const TOURIST_FARE_PERIODS := 12

const MODE_CAR := 0
const MODE_HIGHWAY := 1
const MODE_BUS := 2
const MODE_RAIL := 3
const MODE_SUBWAY := 4
const MODE_STATION := 5
const MODE_COUNT := 6

const WIDTH := City.WIDTH
const HEIGHT := City.HEIGHT
const TILES := City.WIDTH * City.HEIGHT
const STATES := MODE_COUNT * TILES
const BUCKETS := TransportParams.MAX_STEP + 1

const DX: Array[int] = [0, 1, 0, -1]
const DY: Array[int] = [-1, 0, 1, 0]

## Surface class and lot roles by building id, filled once.
var _surface := PackedByteArray()
var _origin := PackedByteArray()
var _destination := PackedByteArray()
var _parcel_destination := PackedByteArray()

## Search buffers, indexed by state = mode * TILES + tile. A state is valid
## for the current trip when its stamp equals `_serial`.
var _stamp := PackedInt32Array()
var _dist := PackedInt32Array()
var _parent := PackedInt32Array()
var _buckets: Array[Array] = []
var _serial := 0
var _pending := 0
var _budget := TransportParams.TRIP_BUDGET
## States expanded so far in the current pass.
var _expanded := 0

## Map layers of the trip being searched.
var _buildings := PackedInt32Array()
var _underground := PackedByteArray()
var _altitude := PackedInt32Array()
## Tile of the destination reached by the last search, -1 for a map edge.
var _arrival_tile := -1

## Rider counters for the year and for the last pass.
var _riders_year := {&"bus": 0, &"rail": 0, &"subway": 0}
var _riders_month := {&"bus": 0, &"rail": 0, &"subway": 0}
var _unreachable := 0.0
var _attempted := 0
var _completed := 0
var _cursor := 0
var _jam_cooldown := 0
var _context: WeakRef
var _tourist_samples: Array[Dictionary] = []


func _init() -> void:
	key = &"transport"
	_surface.resize(Buildings.COUNT)
	_origin.resize(Buildings.COUNT)
	_destination.resize(Buildings.COUNT)
	_parcel_destination.resize(TILES)
	for id in Buildings.COUNT:
		_surface[id] = TransportParams.surface_class(id)
		_origin[id] = 1 if TransportParams.is_origin(id) else 0
		_destination[id] = 1 if TransportParams.is_destination(id) else 0
	_stamp.resize(STATES)
	_dist.resize(STATES)
	_parent.resize(STATES)
	for _i in BUCKETS:
		_buckets.append([])


# ── Schedule ─────────────────────────────────────────────────────────────

func setup(ctx: SimContext) -> void:
	_context = weakref(ctx)


@warning_ignore("integer_division")
func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_context = weakref(ctx)
	var tourism := ctx.system(&"tourism")
	if tourism != null and int(tourism.transport_pass_month()) == ctx.clock.day / GameClock.DAYS_PER_MONTH: return
	var city := ctx.city
	var traffic := city.traffic.data
	_decay(traffic)
	_riders_month = {&"bus": 0, &"rail": 0, &"subway": 0}
	_attempted = 0
	_completed = 0
	_expanded = 0
	var origins := _collect_origins(city)
	var total := origins.size()
	var take := mini(total, TransportParams.TRIPS_PER_PASS)
	if take > 0:
		var scale := mini(TransportParams.SAMPLE_WEIGHT_CAP, ceili(float(total) / float(take)))
		_bind(city)
		for k in take:
			if _expanded >= TransportParams.PASS_SEARCH_BUDGET:
				break
			@warning_ignore("integer_division")
			var index := (_cursor + (k * total) / take) % total
			var tile := origins[index]
			var weight := TransportParams.trip_weight(_buildings[tile]) * scale
			_attempted += 1
			if _run_trip(city, tile, weight, traffic):
				_completed += 1
		_cursor = (_cursor + 1) % total
		_unbind()
	_unreachable = 0.0 if _attempted == 0 else float(_attempted - _completed) / float(_attempted)
	_tourist_pass(ctx,traffic)
	city.traffic.data = traffic
	ctx.stats.average_traffic = _average(traffic)
	if _jam_cooldown > 0:
		_jam_cooldown -= 1
	elif ctx.stats.average_traffic >= TransportParams.JAM_LEVEL:
		ctx.events.report(&"traffic_jam", {"average": ctx.stats.average_traffic}, 2)
		_jam_cooldown = TransportParams.JAM_COOLDOWN_MONTHS


func yearly(ctx: SimContext) -> void:
	ctx.stats.record(&"riders_bus", int(_riders_year[&"bus"]))
	ctx.stats.record(&"riders_rail", int(_riders_year[&"rail"]))
	ctx.stats.record(&"riders_subway", int(_riders_year[&"subway"]))
	_riders_year = {&"bus": 0, &"rail": 0, &"subway": 0}


# ── Getters ──────────────────────────────────────────────────────────────

## Share of last month's trips that could not arrive, 0.0–1.0.
func unreachable_ratio() -> float:
	return _unreachable


## Riders carried so far this year: {bus, rail, subway}.
func ridership() -> Dictionary:
	return _riders_year.duplicate()


## Riders of every kind carried by last month's pass.
func monthly_ridership() -> int:
	return int(_riders_month[&"bus"]) + int(_riders_month[&"rail"]) + int(_riders_month[&"subway"])


## Riders carried by last month's pass: {bus, rail, subway}.
func monthly_riders_by_mode() -> Dictionary:
	return _riders_month.duplicate()


func trips_attempted() -> int:
	return _attempted


func trips_completed() -> int:
	return _completed


## States searched by last month's pass; bounded by PASS_SEARCH_BUDGET.
func states_searched() -> int:
	return _expanded


## Route one trip from the lot anchored at `anchor` without changing the map.
## Returns {reached, cost, tiles, highway, bus, rail, subway}.
func trace_trip(city: City, anchor: Vector2i) -> Dictionary:
	var out := {"reached": false, "cost": 0, "tiles": 0, "highway": false,
		"bus": false, "rail": false, "subway": false}
	if not city.in_bounds(anchor.x, anchor.y):
		return out
	_bind(city)
	var start := _entrance(anchor.y * WIDTH + anchor.x)
	if start >= 0:
		var arrival := _search(start)
		if arrival >= 0:
			out["reached"] = true
			out["cost"] = _dist[arrival]
			var s := arrival
			while s >= 0:
				out["tiles"] = int(out["tiles"]) + 1
				@warning_ignore("integer_division")
				match s / TILES:
					MODE_HIGHWAY: out["highway"] = true
					MODE_BUS: out["bus"] = true
					MODE_RAIL: out["rail"] = true
					MODE_SUBWAY: out["subway"] = true
				s = _parent[s]
	_unbind()
	return out


func reachable(city: City, anchor: Vector2i) -> bool:
	return bool(trace_trip(city, anchor)["reached"])


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	return {
		"riders_year": _riders_dict(_riders_year),
		"riders_month": _riders_dict(_riders_month),
		"unreachable": _unreachable,
		"attempted": _attempted,
		"completed": _completed,
		"cursor": _cursor,
		"jam_cooldown": _jam_cooldown,
	}


func load(data: Dictionary) -> void:
	var year: Dictionary = data.get("riders_year", {})
	var month: Dictionary = data.get("riders_month", {})
	_riders_year = _riders_from(year)
	_riders_month = _riders_from(month)
	_unreachable = float(data.get("unreachable", 0.0))
	_attempted = int(data.get("attempted", 0))
	_completed = int(data.get("completed", 0))
	_cursor = int(data.get("cursor", 0))
	_jam_cooldown = int(data.get("jam_cooldown", 0))


static func _riders_dict(riders: Dictionary) -> Dictionary:
	return {"bus": int(riders[&"bus"]), "rail": int(riders[&"rail"]), "subway": int(riders[&"subway"])}


static func _riders_from(data: Dictionary) -> Dictionary:
	return {&"bus": int(data.get("bus", 0)), &"rail": int(data.get("rail", 0)), &"subway": int(data.get("subway", 0))}


# ── The pass ─────────────────────────────────────────────────────────────

func _bind(city: City) -> void:
	_buildings = city.building.data
	_underground = city.underground.data
	_altitude = city.altitude.data
	_parcel_destination.fill(0)
	var records := city.agricultural_parcels.records()
	var allocation := AgriculturalParcelCapacity.allocate(records)
	var members_by_id := {}
	for record in records: members_by_id[record.id] = record.members
	for destination in AgriculturalParcelCapacity.destinations(records,allocation):
		# Every usable frontage aliases this one allocated parcel destination.
		# These route flags carry no capacity; jobs remain in allocation.by_id.
		var members: PackedInt32Array = members_by_id.get(destination.parcel_id,PackedInt32Array())
		for member in members:
			if _has_destination_entrance(member): _parcel_destination[member] = 1
	var ctx := _context.get_ref() as SimContext if _context != null else null
	var tourism := ctx.system(&"tourism") as TourismSystem if ctx != null and ctx.city == city else null
	if tourism != null:
		for tile in tourism.job_tiles():
			if _has_destination_entrance(tile): _parcel_destination[tile] = 1


func _unbind() -> void:
	_buildings = PackedInt32Array()
	_underground = PackedByteArray()
	_altitude = PackedInt32Array()


static func _decay(traffic: PackedByteArray) -> void:
	for i in traffic.size():
		var v := traffic[i]
		if v != 0:
			traffic[i] = v - (v >> TransportParams.TRAFFIC_DECAY_SHIFT)


static func _average(traffic: PackedByteArray) -> int:
	var sum := 0
	var cells := 0
	for i in traffic.size():
		var v := traffic[i]
		if v != 0:
			sum += v
			cells += 1
	@warning_ignore("integer_division")
	return 0 if cells == 0 else sum / cells


## Anchor tiles of every residential lot, in scan order. The CORNER_NW tile
## picks each lot once; a lot larger than one tile starts at its
## `City.anchor_of` tile, since a city saved at another rotation carries
## CORNER_NW on a different corner of the lot.
func _collect_origins(city: City) -> PackedInt32Array:
	var out := PackedInt32Array()
	var buildings := city.building.data
	var zones := city.zone.data
	var multi := UtilityParams.multi_tile_table()
	for t in TILES:
		var id := buildings[t]
		if _origin[id] == 0:
			continue
		if (zones[t] & Zones.CORNER_NW) == 0:
			continue
		if multi[id] != 0:
			@warning_ignore("integer_division")
			var a := City.footprint_anchor(buildings, zones, t % WIDTH, t / WIDTH)
			out.append(a.y * WIDTH + a.x)
		else:
			out.append(t)
	return out


## Route one trip and, on arrival, deposit congestion and count riders.
func _run_trip(city: City, anchor_tile: int, weight: int, traffic: PackedByteArray) -> bool:
	var start := _entrance(anchor_tile)
	if start < 0:
		return false
	var arrival := _search(start)
	if arrival < 0:
		return false
	var used_bus := false
	var used_rail := false
	var used_subway := false
	var s := arrival
	while s >= 0:
		@warning_ignore("integer_division")
		var mode := s / TILES
		match mode:
			MODE_CAR, MODE_HIGHWAY:
				var tile := s - mode * TILES
				@warning_ignore("integer_division")
				var cell := ((tile / WIDTH) >> 1) * City.HALF + ((tile % WIDTH) >> 1)
				traffic[cell] = mini(TransportParams.TRAFFIC_MAX, traffic[cell] + weight)
			MODE_BUS: used_bus = true
			MODE_RAIL: used_rail = true
			MODE_SUBWAY: used_subway = true
		s = _parent[s]
	if used_bus:
		_riders_month[&"bus"] = int(_riders_month[&"bus"]) + weight
		_riders_year[&"bus"] = int(_riders_year[&"bus"]) + weight
	if used_rail:
		_riders_month[&"rail"] = int(_riders_month[&"rail"]) + weight
		_riders_year[&"rail"] = int(_riders_year[&"rail"]) + weight
	if used_subway:
		_riders_month[&"subway"] = int(_riders_month[&"subway"]) + weight
		_riders_year[&"subway"] = int(_riders_year[&"subway"]) + weight
	return true


## First road or station tile in the rings around the lot, as a start state,
## or -1 when the lot has no entrance.
func _entrance(anchor_tile: int) -> int:
	@warning_ignore("integer_division")
	var ay := anchor_tile / WIDTH
	var ax := anchor_tile - ay * WIDTH
	var size := Buildings.size(_buildings[anchor_tile])
	for r in range(1, TransportParams.ENTRANCE_REACH + 1):
		var x0 := ax - r
		var y0 := ay - r
		var x1 := ax + size.x - 1 + r
		var y1 := ay + size.y - 1 + r
		for x in range(x0, x1 + 1):
			var s := _entrance_at(x, y0)
			if s >= 0:
				return s
			s = _entrance_at(x, y1)
			if s >= 0:
				return s
		for y in range(y0 + 1, y1):
			var s := _entrance_at(x0, y)
			if s >= 0:
				return s
			s = _entrance_at(x1, y)
			if s >= 0:
				return s
	return -1


func _entrance_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
		return -1
	var tile := y * WIDTH + x
	var cls := _surface[_buildings[tile]]
	if cls & (TransportParams.SURFACE_ROAD | TransportParams.SURFACE_RAMP):
		return MODE_CAR * TILES + tile
	if cls & TransportParams.SURFACE_STATION:
		return MODE_STATION * TILES + tile
	return -1


## The destination itself is a member; the neighboring surface is a route
## entrance under the same road/station policy used for origin lots.
func _has_destination_entrance(index: int) -> bool:
	@warning_ignore("integer_division")
	var y := index / WIDTH
	var x := index - y * WIDTH
	for d in 4:
		if _entrance_at(x + DX[d],y + DY[d]) >= 0: return true
	return false


func _push(parent: int, mode: int, tile: int, cost: int) -> void:
	if cost > _budget:
		return
	var s := mode * TILES + tile
	if _stamp[s] == _serial and _dist[s] <= cost:
		return
	_stamp[s] = _serial
	_dist[s] = cost
	_parent[s] = parent
	_buckets[cost % BUCKETS].append(s)
	_pending += 1


func _has_tunnel(tile: int) -> bool:
	return (_altitude[tile] >> City.TUNNEL_SHIFT) != 0


func _is_subway(tile: int) -> bool:
	return UtilityParams.is_subway(_underground[tile])


## Cheapest-first search from a start state. Returns the state next to the
## destination, or -1. Sets `_arrival_tile`.
func _search(start: int) -> int:
	_serial += 1
	_budget = TransportParams.TRIP_BUDGET
	for b in _buckets:
		b.clear()
	_pending = 0
	_arrival_tile = -1
	@warning_ignore("integer_division")
	_push(-1, start / TILES, start % TILES, 0)
	var cost := 0
	while _pending > 0 and cost <= _budget:
		var bucket: Array = _buckets[cost % BUCKETS]
		for s: int in bucket:
			_pending -= 1
			if _dist[s] != cost:
				continue
			_expanded += 1
			@warning_ignore("integer_division")
			var mode := s / TILES
			var tile := s - mode * TILES
			@warning_ignore("integer_division")
			var y := tile / WIDTH
			var x := tile - y * WIDTH
			if (mode == MODE_CAR or mode == MODE_HIGHWAY or mode == MODE_RAIL) \
					and (x == 0 or y == 0 or x == WIDTH - 1 or y == HEIGHT - 1):
				bucket.clear()
				return s
			for d in 4:
				var nx := x + DX[d]
				var ny := y + DY[d]
				if nx < 0 or ny < 0 or nx >= WIDTH or ny >= HEIGHT:
					continue
				var nt := ny * WIDTH + nx
				var nid := _buildings[nt]
				if (_destination[nid] != 0 or _parcel_destination[nt] != 0) and (mode == MODE_CAR or mode == MODE_BUS or mode == MODE_STATION):
					_arrival_tile = nt
					bucket.clear()
					return s
				for step: Array in _target_steps(s, nt):
					var next := int(step[0])
					@warning_ignore("integer_division")
					_push(s, next / TILES, next % TILES, cost + int(step[1]))
		bucket.clear()
		cost += 1
	return -1


## The single transition policy used by commuters and explicit destinations.
@warning_ignore("integer_division")
func _target_steps(s: int, nt: int) -> Array:
	var mode := s / TILES
	var tile := s % TILES
	var cls := _surface[_buildings[tile]]
	var nid := _buildings[nt]
	var ncls := _surface[nid]
	var out: Array = []
	match mode:
		MODE_CAR:
			if ncls & TransportParams.SURFACE_STATION:
				out.append([MODE_STATION * TILES + nt, TransportParams.STATION_STEP])
			elif ncls & TransportParams.SURFACE_RAMP:
				out.append([MODE_CAR * TILES + nt, TransportParams.RAMP_STEP])
			elif ncls & TransportParams.SURFACE_ROAD or _has_tunnel(nt):
				out.append([MODE_CAR * TILES + nt, TransportParams.ROAD_STEP])
			elif (cls & TransportParams.SURFACE_RAMP) and (ncls & TransportParams.SURFACE_HIGHWAY):
				out.append([MODE_HIGHWAY * TILES + nt, TransportParams.HIGHWAY_STEP])
		MODE_HIGHWAY:
			if ncls & TransportParams.SURFACE_RAMP:
				out.append([MODE_HIGHWAY * TILES + nt, TransportParams.RAMP_STEP])
			elif ncls & TransportParams.SURFACE_HIGHWAY:
				out.append([MODE_HIGHWAY * TILES + nt, TransportParams.HIGHWAY_STEP])
			elif (cls & TransportParams.SURFACE_RAMP) and (ncls & TransportParams.SURFACE_ROAD):
				out.append([MODE_CAR * TILES + nt, TransportParams.ROAD_STEP])
		MODE_BUS:
			if ncls & TransportParams.SURFACE_STATION:
				out.append([MODE_STATION * TILES + nt, TransportParams.STATION_STEP])
			elif ncls & (TransportParams.SURFACE_ROAD | TransportParams.SURFACE_RAMP) or _has_tunnel(nt):
				out.append([MODE_BUS * TILES + nt, TransportParams.BUS_STEP])
		MODE_RAIL:
			if ncls & TransportParams.SURFACE_RAIL_STATION:
				out.append([MODE_STATION * TILES + nt, TransportParams.STATION_STEP])
			elif ncls & TransportParams.SURFACE_RAIL:
				out.append([MODE_RAIL * TILES + nt, TransportParams.RAIL_STEP])
			elif (cls & TransportParams.SURFACE_PORTAL) and _is_subway(nt):
				out.append([MODE_SUBWAY * TILES + nt, TransportParams.SUBWAY_STEP])
		MODE_SUBWAY:
			if ncls & TransportParams.SURFACE_SUBWAY_STATION:
				out.append([MODE_STATION * TILES + nt, TransportParams.STATION_STEP])
			elif _is_subway(nt):
				out.append([MODE_SUBWAY * TILES + nt, TransportParams.SUBWAY_STEP])
			elif ncls & TransportParams.SURFACE_PORTAL:
				out.append([MODE_RAIL * TILES + nt, TransportParams.RAIL_STEP])
		MODE_STATION:
			var kind := cls & TransportParams.SURFACE_STATION
			if ncls & TransportParams.SURFACE_STATION:
				var same := nid == _buildings[tile]
				out.append([MODE_STATION * TILES + nt, (TransportParams.PLATFORM_STEP if same else TransportParams.STATION_STEP)])
			elif ncls & (TransportParams.SURFACE_ROAD | TransportParams.SURFACE_RAMP) or _has_tunnel(nt):
				if kind == TransportParams.SURFACE_BUS_DEPOT:
					out.append([MODE_BUS * TILES + nt, TransportParams.BUS_STEP])
				else:
					out.append([MODE_CAR * TILES + nt, TransportParams.ROAD_STEP])
			elif (kind & TransportParams.SURFACE_RAIL_STATION) and (ncls & TransportParams.SURFACE_RAIL):
				out.append([MODE_RAIL * TILES + nt, TransportParams.RAIL_STEP])
			elif (kind & TransportParams.SURFACE_SUBWAY_STATION) and _is_subway(nt):
				out.append([MODE_SUBWAY * TILES + nt, TransportParams.SUBWAY_STEP])
	return out

## Pure adjacency. No commuter destinations, traffic, ridership or RNG.
func target_graph(city: City) -> Dictionary:
	_buildings = city.building.data
	_underground = city.underground.data
	_altitude = city.altitude.data
	var graph := {}
	for tile in TILES:
		var cls := _surface[_buildings[tile]]
		var modes: Array[int] = []
		if cls & (TransportParams.SURFACE_ROAD | TransportParams.SURFACE_RAMP) or _has_tunnel(tile):
			modes.append(MODE_CAR)
			modes.append(MODE_BUS)
		if cls & (TransportParams.SURFACE_HIGHWAY | TransportParams.SURFACE_RAMP): modes.append(MODE_HIGHWAY)
		if cls & (TransportParams.SURFACE_RAIL | TransportParams.SURFACE_PORTAL): modes.append(MODE_RAIL)
		if _is_subway(tile): modes.append(MODE_SUBWAY)
		if cls & TransportParams.SURFACE_STATION: modes.append(MODE_STATION)
		for mode in modes:
			var state := mode * TILES + tile
			var edges := PackedInt32Array()
			@warning_ignore("integer_division")
			var at := Vector2i(tile % WIDTH, tile / WIDTH)
			for d in 4:
				var next := at + Vector2i(DX[d],DY[d])
				if not city.in_bounds(next.x,next.y): continue
				for step: Array in _target_steps(state,next.y * WIDTH + next.x): edges.append(step[0])
			graph[state] = edges
	_unbind()
	return graph

## Same keys, values and insertion order as target_graph(city). A tile's states
## and edges read only its own and its four neighbours' surface id, tunnel and
## subway bytes, so unchanged neighbourhoods reuse the previous edge arrays.
func target_graph_update(city: City, previous: Dictionary, old_layer: PackedInt32Array,
		old_underground: PackedByteArray, old_altitude: PackedInt32Array, new_layer: PackedInt32Array) -> Dictionary:
	_buildings = city.building.data
	_underground = city.underground.data
	_altitude = city.altitude.data
	var dirty := PackedByteArray()
	dirty.resize(TILES)
	for i in TILES:
		if old_layer[i] != new_layer[i] or old_underground[i] != _underground[i] or old_altitude[i] != _altitude[i]:
			dirty[i] = 1
			@warning_ignore("integer_division")
			var y := i / WIDTH
			var x := i - y * WIDTH
			if x > 0: dirty[i - 1] = 1
			if x < WIDTH - 1: dirty[i + 1] = 1
			if y > 0: dirty[i - WIDTH] = 1
			if y < HEIGHT - 1: dirty[i + WIDTH] = 1
	var graph := {}
	for tile in TILES:
		var cls := _surface[_buildings[tile]]
		var car := (cls & (TransportParams.SURFACE_ROAD | TransportParams.SURFACE_RAMP)) != 0 or _has_tunnel(tile)
		var highway := (cls & (TransportParams.SURFACE_HIGHWAY | TransportParams.SURFACE_RAMP)) != 0
		var rail := (cls & (TransportParams.SURFACE_RAIL | TransportParams.SURFACE_PORTAL)) != 0
		var subway := _is_subway(tile)
		var station := (cls & TransportParams.SURFACE_STATION) != 0
		if not (car or highway or rail or subway or station): continue
		var modes: Array[int] = []
		if car:
			modes.append(MODE_CAR)
			modes.append(MODE_BUS)
		if highway: modes.append(MODE_HIGHWAY)
		if rail: modes.append(MODE_RAIL)
		if subway: modes.append(MODE_SUBWAY)
		if station: modes.append(MODE_STATION)
		if dirty[tile] == 0:
			for mode in modes:
				var state := mode * TILES + tile
				graph[state] = previous[state]
			continue
		for mode in modes:
			var state := mode * TILES + tile
			var edges := PackedInt32Array()
			@warning_ignore("integer_division")
			var at := Vector2i(tile % WIDTH, tile / WIDTH)
			for d in 4:
				var next := at + Vector2i(DX[d],DY[d])
				if not city.in_bounds(next.x,next.y): continue
				for step: Array in _target_steps(state,next.y * WIDTH + next.x): edges.append(step[0])
			graph[state] = edges
	_unbind()
	return graph

## All valid entrances around the actual footprint. Explicit routing never
## allows an earlier isolated road to hide another frontage's station.
func target_entrances(city: City, rect: Rect2i) -> PackedInt32Array:
	_buildings = city.building.data
	var result := PackedInt32Array()
	for r in range(1,TransportParams.ENTRANCE_REACH+1):
		var ring := rect.grow(r)
		for y in range(maxi(0,ring.position.y),mini(HEIGHT,ring.end.y)):
			for x in range(maxi(0,ring.position.x),mini(WIDTH,ring.end.x)):
				if x != ring.position.x and x != ring.end.x-1 and y != ring.position.y and y != ring.end.y-1: continue
				var state := _entrance_at(x,y)
				if state >= 0: result.append(state)
	_unbind()
	result.sort()
	return result

## Bounded explicit target route; budget exhaustion cannot prove disconnection.
## Optional graph lets the tourism owner reuse its frozen routing generation.
func route_to_targets(city: City, seeds: PackedInt32Array, targets: PackedInt32Array,
		work_budget: int = STATES, graph: Dictionary = {}) -> Dictionary:
	if graph.is_empty(): graph = target_graph(city)
	var wanted := {}
	for state in targets: wanted[state] = true
	var queue := PackedInt32Array()
	var parent := {}
	for state in seeds:
		if graph.has(state) and not parent.has(state):
			parent[state] = -1
			queue.append(state)
	var head := 0
	while head < queue.size() and head < maxi(0,work_budget):
		var state := queue[head]
		head += 1
		if wanted.has(state):
			var path := PackedInt32Array()
			var cursor := state
			while cursor >= 0:
				path.append(cursor)
				cursor = parent[cursor]
			path.reverse()
			return {"status":"reachable", "path":path, "work":head}
		for next: int in graph.get(state,PackedInt32Array()):
			if not parent.has(next):
				parent[next] = state
				queue.append(next)
	return {"status":"pending" if head < queue.size() else "disconnected", "path":PackedInt32Array(), "work":head}


static func neutral_tourism_report() -> Dictionary:
	return {"month_id":-1,"attempted":0,"completed":0,"pending":0,"disconnected":0,"cancelled":0,
		"represented":0,"unsampled":0,"sampled_origins":0,"pending_jobs":0,"oldest_pending_month":-1,
		"states_searched":0,"edges_scanned":0,"path_states":0,"excursions":0,
		"modes":{"car":0,"highway":0,"bus":0,"rail":0,"subway":0}}

static func neutral_tourism_transport() -> Dictionary:
	return {"cursor":0,"gateway_cursor":0,"rotations":{},"processed_month":-1,"pass_month":-1,"pending_fare_riders":0,
		"pending":[],"report":neutral_tourism_report(),"fare_evidence":{"carry":{},"periods":[]}}

static func decode_tourism_report(value: Dictionary) -> Dictionary:
	var clean := neutral_tourism_report()
	if value.size() != clean.size(): return {"ok":false}
	for field in clean:
		if field == "modes": continue
		var low := -1 if field in ["month_id","oldest_pending_month"] else 0
		var high := TOURIST_SEARCH_WORK*MODE_COUNT*4 if field == "edges_scanned" else TourismParams.MAX_COUNT
		if not TourismState._integer(value.get(field),low,high): return {"ok":false}
		clean[field] = int(value[field])
	if clean.states_searched > TOURIST_SEARCH_WORK or clean.path_states > TOURIST_PATH_WORK or clean.sampled_origins > TOURIST_ORIGINS or clean.pending_jobs > TOURIST_QUEUE: return {"ok":false}
	if clean.attempted != clean.completed+clean.pending+clean.disconnected+clean.cancelled: return {"ok":false}
	var modes: Variant = value.get("modes")
	if not modes is Dictionary or modes.size() != 5: return {"ok":false}
	for mode in clean.modes:
		if not TourismState._integer(modes.get(mode),0,clean.completed): return {"ok":false}
		clean.modes[mode] = int(modes[mode])
	return {"ok":true,"value":clean}

@warning_ignore("integer_division")
func monthly_total_ridership() -> int:
	var report := tourism_report()
	var total := monthly_ridership()
	var ctx := _context.get_ref() as SimContext if _context != null else null
	if ctx != null and int(report.month_id) == ctx.clock.day / GameClock.DAYS_PER_MONTH:
		for mode in ["bus","rail","subway"]: total += int(report.modes[mode])
	return total

## Derived evidence of this process's completed representatives; never a save ledger.
func tourism_samples() -> Array[Dictionary]:
	return _tourist_samples.duplicate(true)

func tourism_report() -> Dictionary:
	var ctx := _context.get_ref() as SimContext if _context != null else null
	var tourism := ctx.system(&"tourism") if ctx != null else null
	return tourism.transport_report() if tourism != null else neutral_tourism_report()

## Each gateway gets its own conserved accepted cohorts. A representative path
## carries the sum of its bucket, without copying that sum to other gateways.
## Cursor rotation changes representative venues and scarce gateway selection.
@warning_ignore("integer_division")
func _tourist_jobs(ledger: Dictionary, live: Dictionary, cursor: int, limit: int, gateway_cursor: int = -1, rotations: Dictionary = {}) -> Dictionary:
	var groups := {}
	var total := 0
	var cancelled := 0
	for row: Dictionary in ledger.get("rows",[]):
		if not live.has(int(row.instance)):
			cancelled += int(row.local_day_visitors)
			for allocation: Dictionary in row.gateways: cancelled += int(allocation.count)
			continue
		var venue: Dictionary = live[int(row.instance)]
		var entries: Array = row.gateways.duplicate(true)
		if int(row.local_day_visitors) > 0: entries.append({"id":"local","count":int(row.local_day_visitors)})
		for allocation: Dictionary in entries:
			var id: String = allocation.id
			if not groups.has(id): groups[id] = []
			groups[id].append({"venue":venue,"count":int(allocation.count)})
			total += int(allocation.count)
	var ids := groups.keys()
	ids.sort()
	var jobs: Array[Dictionary] = []
	var represented := 0
	var selected := mini(limit,ids.size())
	var selected_ids: Array[String] = []
	var tickets_by_id := {}
	var allocation_count := 0
	for offset in selected:
		var id: String = ids[((cursor*selected if gateway_cursor < 0 else gateway_cursor)+offset)%ids.size()]
		selected_ids.append(id)
		tickets_by_id[id] = 1
		allocation_count += groups[id].size()-1
	var extra := limit-selected
	var used := 0
	var remainders: Array = []
	for id in selected_ids:
		var numerator: int = extra*(groups[id].size()-1)
		var add := mini(groups[id].size()-1,numerator/maxi(1,allocation_count))
		tickets_by_id[id] += add
		used += add
		remainders.append({"id":id,"remainder":numerator%maxi(1,allocation_count)})
	remainders.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.remainder > b.remainder if a.remainder != b.remainder else a.id < b.id)
	for entry: Dictionary in remainders:
		if used >= extra: break
		if int(tickets_by_id[entry.id]) < groups[entry.id].size():
			tickets_by_id[entry.id] += 1
			used += 1
	for offset in selected:
		var id: String = selected_ids[offset]
		var values: Array = groups[id]
		var tickets: int = tickets_by_id[id]
		for ticket in tickets:
			var bucket: Array = []
			var count := 0
			for index in range(ticket,values.size(),tickets):
				bucket.append(values[index])
				count += int(values[index].count)
			var representative: Dictionary = bucket[int(rotations.get(id,cursor))%bucket.size()].venue
			jobs.append({"period":int(ledger.month_id),"instance":int(representative.instance),
				"key":String(representative.key),"anchor":[representative.anchor.x,representative.anchor.y],
				"gateway":id,"source_count":count,"weight":count,"cohort":jobs.size()})
			represented += count
	return {"jobs":jobs,"represented":represented,"unsampled":total-represented,"cancelled":cancelled,"ids":ids}

## Real traffic/riders join the resident pass before its one publication. Only
## accepted cohorts are sampled. Reports and forecasts never call this writer.
@warning_ignore("integer_division")
func _tourist_pass(ctx: SimContext, traffic: PackedByteArray) -> void:
	var tourism := ctx.system(&"tourism")
	if tourism == null: return
	var state: Dictionary = tourism.transport_state()
	var month := ctx.clock.day/GameClock.DAYS_PER_MONTH
	if month <= int(state.pass_month): return
	var ledger: Dictionary = tourism.accepted_access()
	if ledger.is_empty() and state.pending.is_empty(): return
	tourism.refresh_transport_access()
	var live := {}
	for row: Dictionary in tourism.report():
		if row.operating and ctx.city.building_at(row.anchor.x,row.anchor.y) == int(row.code): live[int(row.instance)] = row
	_tourist_samples.clear()
	var jobs: Array = state.pending.duplicate(true)
	var report := neutral_tourism_report()
	var sampled_period := -1
	var sampled_ids: Array = []
	var new_groups := {}
	report.month_id = month
	if not ledger.is_empty() and int(ledger.month_id) > int(state.processed_month):
		var sample := _tourist_jobs(ledger,live,int(state.cursor),TOURIST_ORIGINS-jobs.size(),int(state.gateway_cursor),state.rotations)
		sampled_period = int(ledger.month_id)
		sampled_ids = sample.ids
		for id: String in state.rotations.keys():
			if not sampled_ids.has(id): state.rotations.erase(id)
		jobs.append_array(sample.jobs)
		report.cancelled = sample.cancelled
		report.attempted = sample.cancelled
		report.represented = sample.represented
		report.unsampled = sample.unsampled
		state.processed_month = int(ledger.month_id)
		state.cursor = (int(state.cursor)+1)%TourismParams.MAX_COUNT
	state.pending = []
	var access: TourismAccess = tourism.access_routes()
	access.begin_trip_pass()
	for job: Dictionary in jobs:
		var weight := int(job.weight)
		if state.pending.size() >= TOURIST_QUEUE:
			# Not started: this new cohort stays explicitly unsampled, never an
			# admitted pending job that could be silently discarded.
			report.represented -= weight
			report.unsampled += weight
			continue
		if int(job.period) == sampled_period:
			new_groups[job.gateway] = true
			state.gateway_cursor = (sampled_ids.find(job.gateway)+1)%maxi(1,sampled_ids.size())
		report.attempted += weight
		report.sampled_origins += 1
		var current: Dictionary = live.get(int(job.instance),{})
		if current.is_empty() or current.anchor != Vector2i(int(job.anchor[0]),int(job.anchor[1])) or String(current.key) != job.key:
			report.cancelled += weight
			continue
		var result := access.trip_route(current.anchor,job.gateway,TOURIST_SEARCH_WORK-int(report.states_searched),TOURIST_PATH_WORK-int(report.path_states))
		report.states_searched += int(result.work)
		report.edges_scanned += int(result.edges)
		report.path_states += int(result.path_work)
		if result.status == "pending":
			state.pending.append(job)
			report.pending += weight
			continue
		if result.status == "disconnected":
			report.disconnected += weight
			continue
		_tourist_samples.append({"period":int(job.period),"instance":int(job.instance),"gateway":String(job.gateway)})
		report.completed += weight
		var modes := _deposit_tourist_path(result.path,weight,traffic)
		for mode: String in modes:
			report.modes[mode] += weight
			if mode in ["bus","rail","subway"]:
				_riders_year[StringName(mode)] += weight
	for id: String in new_groups: state.rotations[id] = (int(state.rotations.get(id,0))+1)%TourismParams.MAX_COUNT
	report.pending_jobs = state.pending.size()
	if not state.pending.is_empty(): report.oldest_pending_month = int(state.pending[0].period)
	state.pass_month = month
	state.report = report
	record_fare_period(state,report)
	tourism.accept_transport(state)

@warning_ignore("integer_division")
func _deposit_tourist_path(path: PackedInt32Array, weight: int, traffic: PackedByteArray) -> Dictionary:
	var modes := {}
	var cells := {}
	for state in path:
		var mode := state/TILES
		if mode == MODE_STATION: continue
		var name: String = ["car","highway","bus","rail","subway"][mode]
		modes[name] = true
		if mode in [MODE_CAR,MODE_HIGHWAY]:
			var tile := state%TILES
			var cell := ((tile/WIDTH)>>1)*City.HALF+((tile%WIDTH)>>1)
			# One weighted trip per traffic cell, even when several path tiles share it.
			if not cells.has(cell):
				traffic[cell] = mini(TransportParams.TRAFFIC_MAX,int(traffic[cell])+weight)
				cells[cell] = true
	return modes


static func fare_usages(entry: Dictionary) -> int:
	var modes: Dictionary = entry.modes
	return int(modes.bus)+int(modes.rail)+int(modes.subway)

## Period evidence, not the pending scalar, owns earned transit. Old unclaimed
## entries compact without dropping a rider; claimed history needs no lifetime
## total because processed-period guards already prevent replay.
static func record_fare_period(state: Dictionary, report: Dictionary) -> void:
	var evidence: Dictionary = state.fare_evidence
	var periods: Array = []
	for entry: Dictionary in evidence.periods:
		if int(entry.claimed) < fare_usages(entry): periods.append(entry)
	var carry: Dictionary = evidence.carry
	if not carry.is_empty() and int(carry.claimed) == fare_usages(carry): carry = {}
	periods.append({"first_month":int(report.month_id),"last_month":int(report.month_id),
		"completed":int(report.completed),"modes":{"bus":int(report.modes.bus),
		"rail":int(report.modes.rail),"subway":int(report.modes.subway)},"claimed":0})
	while periods.size() > TOURIST_FARE_PERIODS:
		var oldest: Dictionary = periods.pop_front()
		if carry.is_empty(): carry = oldest.duplicate(true)
		else:
			carry.last_month = int(oldest.last_month)
			carry.completed += int(oldest.completed)
			carry.claimed += int(oldest.claimed)
			for mode in ["bus","rail","subway"]: carry.modes[mode] += int(oldest.modes[mode])
	evidence.carry = carry
	evidence.periods = periods
	state.pending_fare_riders = pending_fare_evidence(evidence)

static func pending_fare_evidence(evidence: Dictionary) -> int:
	var total := 0
	var carry: Dictionary = evidence.carry
	if not carry.is_empty(): total += fare_usages(carry)-int(carry.claimed)
	for entry: Dictionary in evidence.periods: total += fare_usages(entry)-int(entry.claimed)
	return total

static func claim_fare_evidence(state: Dictionary) -> int:
	var evidence: Dictionary = state.fare_evidence
	var total := pending_fare_evidence(evidence)
	# Keep the latest pass's completed/claimed evidence coherent with its report.
	var periods: Array = evidence.periods
	if not periods.is_empty():
		var latest: Dictionary = periods[-1].duplicate(true)
		latest.claimed = fare_usages(latest)
		evidence.periods = [latest]
	evidence.carry = {}
	state.pending_fare_riders = 0
	return total
