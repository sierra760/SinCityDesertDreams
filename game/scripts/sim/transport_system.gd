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


func _init() -> void:
	key = &"transport"
	_surface.resize(Buildings.COUNT)
	_origin.resize(Buildings.COUNT)
	_destination.resize(Buildings.COUNT)
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

func monthly(ctx: SimContext, _phase: int = 0) -> void:
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
			var cls := _surface[_buildings[tile]]
			for d in 4:
				var nx := x + DX[d]
				var ny := y + DY[d]
				if nx < 0 or ny < 0 or nx >= WIDTH or ny >= HEIGHT:
					continue
				var nt := ny * WIDTH + nx
				var nid := _buildings[nt]
				var ncls := _surface[nid]
				if _destination[nid] != 0 and (mode == MODE_CAR or mode == MODE_BUS or mode == MODE_STATION):
					_arrival_tile = nt
					bucket.clear()
					return s
				match mode:
					MODE_CAR:
						if ncls & TransportParams.SURFACE_STATION:
							_push(s, MODE_STATION, nt, cost + TransportParams.STATION_STEP)
						elif ncls & TransportParams.SURFACE_RAMP:
							_push(s, MODE_CAR, nt, cost + TransportParams.RAMP_STEP)
						elif ncls & TransportParams.SURFACE_ROAD or _has_tunnel(nt):
							_push(s, MODE_CAR, nt, cost + TransportParams.ROAD_STEP)
						elif (cls & TransportParams.SURFACE_RAMP) and (ncls & TransportParams.SURFACE_HIGHWAY):
							_push(s, MODE_HIGHWAY, nt, cost + TransportParams.HIGHWAY_STEP)
					MODE_HIGHWAY:
						if ncls & TransportParams.SURFACE_RAMP:
							_push(s, MODE_HIGHWAY, nt, cost + TransportParams.RAMP_STEP)
						elif ncls & TransportParams.SURFACE_HIGHWAY:
							_push(s, MODE_HIGHWAY, nt, cost + TransportParams.HIGHWAY_STEP)
						elif (cls & TransportParams.SURFACE_RAMP) and (ncls & TransportParams.SURFACE_ROAD):
							_push(s, MODE_CAR, nt, cost + TransportParams.ROAD_STEP)
					MODE_BUS:
						if ncls & TransportParams.SURFACE_STATION:
							_push(s, MODE_STATION, nt, cost + TransportParams.STATION_STEP)
						elif ncls & (TransportParams.SURFACE_ROAD | TransportParams.SURFACE_RAMP) or _has_tunnel(nt):
							_push(s, MODE_BUS, nt, cost + TransportParams.BUS_STEP)
					MODE_RAIL:
						if ncls & TransportParams.SURFACE_RAIL_STATION:
							_push(s, MODE_STATION, nt, cost + TransportParams.STATION_STEP)
						elif ncls & TransportParams.SURFACE_RAIL:
							_push(s, MODE_RAIL, nt, cost + TransportParams.RAIL_STEP)
						elif (cls & TransportParams.SURFACE_PORTAL) and _is_subway(nt):
							_push(s, MODE_SUBWAY, nt, cost + TransportParams.SUBWAY_STEP)
					MODE_SUBWAY:
						if ncls & TransportParams.SURFACE_SUBWAY_STATION:
							_push(s, MODE_STATION, nt, cost + TransportParams.STATION_STEP)
						elif _is_subway(nt):
							_push(s, MODE_SUBWAY, nt, cost + TransportParams.SUBWAY_STEP)
						elif ncls & TransportParams.SURFACE_PORTAL:
							_push(s, MODE_RAIL, nt, cost + TransportParams.RAIL_STEP)
					MODE_STATION:
						var kind := cls & TransportParams.SURFACE_STATION
						if ncls & TransportParams.SURFACE_STATION:
							var same := nid == _buildings[tile]
							_push(s, MODE_STATION, nt, cost + (TransportParams.PLATFORM_STEP if same else TransportParams.STATION_STEP))
						elif ncls & (TransportParams.SURFACE_ROAD | TransportParams.SURFACE_RAMP) or _has_tunnel(nt):
							if kind == TransportParams.SURFACE_BUS_DEPOT:
								_push(s, MODE_BUS, nt, cost + TransportParams.BUS_STEP)
							else:
								_push(s, MODE_CAR, nt, cost + TransportParams.ROAD_STEP)
						elif (kind & TransportParams.SURFACE_RAIL_STATION) and (ncls & TransportParams.SURFACE_RAIL):
							_push(s, MODE_RAIL, nt, cost + TransportParams.RAIL_STEP)
						elif (kind & TransportParams.SURFACE_SUBWAY_STATION) and _is_subway(nt):
							_push(s, MODE_SUBWAY, nt, cost + TransportParams.SUBWAY_STEP)
		bucket.clear()
		cost += 1
	return -1
