# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## Counts real transition classification, rather than introducing production
## instrumentation. Losing reuse must increase work without changing routes.
class CountingTransport extends TransportSystem:
	var computations := 0
	func _target_steps(s: int, nt: int) -> Array:
		computations += 1
		return super._target_steps(s, nt)


## Frozen pre-optimization search. In particular, workplace tests remain
## interleaved with each neighbour's transitions, and Dial queue ties retain
## their original order. This also independently checks the search work cap.
class LegacyTransport extends CountingTransport:
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


func _row(city: City, y: int, first: int, last: int, code: int = Buildings.ROAD_FIRST) -> void:
	for x in range(first, last + 1): city.building.put(x, y, code)


func _fixture(kind: String) -> City:
	var city := flat_city()
	for x in range(10, 13): city.stamp_building(x, 9, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	_row(city, 10, 10, 12)
	match kind:
		"road", "bus":
			_row(city, 10, 13, 30)
			city.stamp_building(30, 11, Buildings.COM_1X1_FIRST, Zones.COM_LOW)
			if kind == "bus": city.stamp_building(13, 8, Buildings.BUS_DEPOT)
		"rail":
			city.stamp_building(13, 10, Buildings.RAIL_STATION)
			_row(city, 10, 15, 40, Buildings.RAIL_FIRST)
			city.stamp_building(41, 10, Buildings.RAIL_STATION)
			_row(city, 10, 43, 45)
			city.stamp_building(46, 10, Buildings.COM_1X1_FIRST, Zones.COM_LOW)
		"subway":
			city.stamp_building(13, 10, Buildings.SUBWAY_STATION)
			for x in range(14, 41): city.underground.put(x, 10, UtilityParams.subway_code(UtilityParams.EW_MASK))
			city.stamp_building(41, 10, Buildings.SUBWAY_STATION)
			_row(city, 10, 42, 44)
			city.stamp_building(45, 10, Buildings.COM_1X1_FIRST, Zones.COM_LOW)
		"highway":
			city.building.put(13, 10, Buildings.ONRAMP_FIRST)
			_row(city, 10, 14, 40, Buildings.HIGHWAY_FIRST)
			city.building.put(41, 10, Buildings.ONRAMP_FIRST)
			_row(city, 10, 42, 44)
			city.stamp_building(45, 10, Buildings.COM_1X1_FIRST, Zones.COM_LOW)
		"tunnel":
			_row(city, 10, 13, 20)
			for x in range(15, 18):
				city.building.put(x, 10, Buildings.NONE)
				city.altitude.put(x, 10, city.altitude.at(x, 10) | (1 << City.TUNNEL_SHIFT))
			city.stamp_building(20, 11, Buildings.COM_1X1_FIRST, Zones.COM_LOW)
	return city


func _search_evidence(transport: TransportSystem, start: int) -> Dictionary:
	var before := transport._expanded
	var arrival := transport._search(start)
	var path := PackedInt32Array()
	var cursor := arrival
	while cursor >= 0:
		path.append(cursor)
		cursor = transport._parent[cursor]
	return {"arrival":arrival,"workplace":transport._arrival_tile,"path":path,
		"cost":transport._dist[arrival] if arrival >= 0 else -1,"work":transport._expanded-before}


func test_repeated_search_reuses_transitions_but_retains_search_work() -> void:
	var city := _fixture("road")
	var transport := CountingTransport.new()
	transport._bind(city)
	var start := transport._entrance(9 * City.WIDTH + 10)
	var first := _search_evidence(transport, start)
	var computations := transport.computations
	check_gt(computations, 0)
	check_eq(_search_evidence(transport, start), first, "same paths and expanded-state work")
	check_eq(transport.computations, computations, "second trip must reuse all classified transitions")
	transport._unbind()
	transport._bind(city)
	check_eq(_search_evidence(transport, start), first)
	check_gt(transport.computations, computations, "a new bind starts with current map inputs")
	transport._unbind()


func test_multimodal_search_matches_legacy_including_ties_and_destination_order() -> void:
	for kind in ["road", "bus", "rail", "subway", "highway", "tunnel"]:
		var city := _fixture(kind)
		var transport := CountingTransport.new()
		var legacy := LegacyTransport.new()
		transport._bind(city)
		legacy._bind(city)
		for x in [10, 12, 11, 10]:
			var start := transport._entrance(9 * City.WIDTH + x)
			var actual := _search_evidence(transport, start)
			check_eq(actual, _search_evidence(legacy, start), kind)
			check_ge(actual.arrival, 0, kind + " reaches its workplace")
		transport._unbind()
		legacy._unbind()


func test_new_bind_detects_raw_building_subway_and_tunnel_cuts() -> void:
	for kind in ["road", "subway", "tunnel"]:
		var city := _fixture(kind)
		var transport := CountingTransport.new()
		check(transport.trace_trip(city, Vector2i(10, 9)).reached, kind)
		match kind:
			"road": city.building.put(20, 10, Buildings.NONE)
			"subway": city.underground.put(25, 10, 0)
			"tunnel": city.altitude.put(16, 10, city.altitude.at(16, 10) & ~(15 << City.TUNNEL_SHIFT))
		check(not transport.trace_trip(city, Vector2i(10, 9)).reached, kind + " raw cut invalidates transitions")
		check_eq(transport.trace_trip(city, Vector2i(10, 9)), LegacyTransport.new().trace_trip(city, Vector2i(10, 9)), kind)


func test_monthly_multimodal_outputs_rng_and_pass_work_match_legacy() -> void:
	for kind in ["road", "bus", "rail", "subway", "highway", "tunnel"]:
		var city := _fixture(kind)
		var old_city := _fixture(kind)
		var ctx := make_context(city, 4729)
		var old_ctx := make_context(old_city, 4729)
		var transport := CountingTransport.new()
		var legacy := LegacyTransport.new()
		transport.setup(ctx)
		legacy.setup(old_ctx)
		for month in 3:
			transport.monthly(ctx)
			legacy.monthly(old_ctx)
			check_eq(city.traffic.data, old_city.traffic.data, kind)
			check_eq(transport.save(), legacy.save(), kind)
			check_eq(transport.states_searched(), legacy.states_searched(), kind)
			check_eq(ctx.stats.average_traffic, old_ctx.stats.average_traffic, kind)
			check_eq(ctx.events.news, old_ctx.events.news, kind)
			check_eq(ctx.rng.state(), old_ctx.rng.state(), kind)
		check_lt(transport.computations, legacy.computations, kind + " overlapping commuters reuse transition work")


func test_aggregate_search_budget_stops_at_the_same_trip() -> void:
	var cities: Array[City] = []
	for _copy in 2:
		var city := flat_city()
		for y in range(10, 61): _row(city, y, 10, 60)
		for y in range(14, 58, 4):
			for x in range(14, 58, 4): city.stamp_building(x, y, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
		cities.append(city)
	var ctx := make_context(cities[0], 5279)
	var old_ctx := make_context(cities[1], 5279)
	var transport := CountingTransport.new()
	var legacy := LegacyTransport.new()
	transport.setup(ctx)
	legacy.setup(old_ctx)
	transport.monthly(ctx)
	legacy.monthly(old_ctx)
	check_ge(transport.states_searched(), TransportParams.PASS_SEARCH_BUDGET, "fixture reaches aggregate work cap")
	check_lt(transport.trips_attempted(), 121, "remaining residential origins wait for another pass")
	check_eq(transport.states_searched(), legacy.states_searched(), "cache hits still spend search work")
	check_eq(transport.save(), legacy.save(), "same stopping trip and next origin cursor")
	check_eq(cities[0].traffic.data, cities[1].traffic.data)
	check_eq(ctx.rng.state(), old_ctx.rng.state())
	check_lt(transport.computations, legacy.computations, "overlapping failed routes also share transitions")
