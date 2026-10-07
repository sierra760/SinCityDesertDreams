# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## The transport system is driven directly through a SimContext so these
## tests do not depend on what the other systems do to an unpowered lot.
## One test at the end checks the Simulation schedules the pass on day 8.

const TRANSPORT_DAY := 8
const ROAD := Buildings.ROAD_FIRST
const HOUSE := Buildings.RES_1X1_FIRST
const BIG_HOUSE := Buildings.RES_3X3_FIRST
const SHOP := Buildings.COM_1X1_FIRST


func _context(c: City, seed_value: int = 12345) -> SimContext:
	var ctx := make_context(c, seed_value)
	ctx.clock.founded_year = c.founded_year
	return ctx


func _transport(ctx: SimContext) -> TransportSystem:
	var t := TransportSystem.new()
	ctx.systems[t.key] = t
	t.setup(ctx)
	return t


## Run one monthly pass and return the kinds of news it queued.
func _pass(t: TransportSystem, ctx: SimContext) -> Array[StringName]:
	ctx.events.clear()
	t.monthly(ctx)
	var kinds: Array[StringName] = []
	for story in ctx.events.news:
		kinds.append(story["kind"])
	return kinds


func _road_row(c: City, y: int, x0: int, x1: int, id: int = ROAD) -> void:
	for x in range(x0, x1 + 1):
		c.building.put(x, y, id)


func _traffic_sum(c: City) -> int:
	var total := 0
	for v in c.traffic.data:
		total += v
	return total


func test_road_trip_leaves_traffic() -> void:
	var c := flat_city()
	_road_row(c, 10, 10, 20)
	c.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	c.stamp_building(20, 11, SHOP, Zones.COM_LOW)
	var ctx := _context(c)
	var t := _transport(ctx)
	_pass(t, ctx)
	check_eq(t.trips_attempted(), 1)
	check_eq(t.trips_completed(), 1)
	check_eq(t.unreachable_ratio(), 0.0)
	check_gt(c.traffic_at(12, 10), 0, "traffic on the road")
	check_gt(c.traffic_at(18, 10), 0, "traffic near the shop")
	check_eq(c.traffic_at(12, 30), 0, "no traffic away from the road")
	check_gt(ctx.stats.average_traffic, 0)
	check_eq(t.monthly_ridership(), 0, "no transit used")


func test_disconnected_shop_is_unreachable() -> void:
	var c := flat_city()
	_road_row(c, 10, 10, 14)
	c.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	_road_row(c, 10, 28, 32)
	c.stamp_building(30, 11, SHOP, Zones.COM_LOW)
	var ctx := _context(c)
	var t := _transport(ctx)
	_pass(t, ctx)
	check_eq(t.trips_attempted(), 1)
	check_eq(t.trips_completed(), 0)
	check_eq(t.unreachable_ratio(), 1.0)
	check_eq(_traffic_sum(c), 0, "failed trips leave no traffic")


func test_lot_without_entrance_fails() -> void:
	var c := flat_city()
	c.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	c.stamp_building(11, 9, SHOP, Zones.COM_LOW)
	var ctx := _context(c)
	var t := _transport(ctx)
	_pass(t, ctx)
	check_eq(t.trips_attempted(), 1)
	check_eq(t.unreachable_ratio(), 1.0)
	check(not t.reachable(c, Vector2i(10, 9)))


func test_industry_is_a_destination_too() -> void:
	var c := flat_city()
	_road_row(c, 10, 10, 20)
	c.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	c.stamp_building(19, 11, Buildings.IND_2X2_FIRST, Zones.IND_HIGH)
	var ctx := _context(c)
	var t := _transport(ctx)
	check(t.reachable(c, Vector2i(10, 9)))


func test_bus_depot_carries_riders_and_keeps_cars_off_the_road() -> void:
	var c := flat_city()
	_road_row(c, 10, 10, 30)
	c.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	c.stamp_building(12, 8, Buildings.BUS_DEPOT)
	c.stamp_building(30, 11, SHOP, Zones.COM_LOW)
	var ctx := _context(c)
	var t := _transport(ctx)
	var trip := t.trace_trip(c, Vector2i(10, 9))
	check(trip["reached"])
	check(trip["bus"], "the cheaper bus ride is chosen")
	_pass(t, ctx)
	check_ge(int(t.ridership()[&"bus"]), 1)
	check_ge(t.monthly_ridership(), 1)
	check_eq(int(t.monthly_riders_by_mode()[&"rail"]), 0)
	check_eq(c.traffic_at(24, 10), 0, "bus passengers add no congestion")


func test_rail_station_links_two_road_networks() -> void:
	var c := flat_city()
	c.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	_road_row(c, 10, 10, 12)
	c.stamp_building(13, 10, Buildings.RAIL_STATION)
	_road_row(c, 10, 15, 40, Buildings.RAIL_FIRST)
	c.stamp_building(41, 10, Buildings.RAIL_STATION)
	_road_row(c, 10, 43, 45)
	c.stamp_building(46, 10, SHOP, Zones.COM_LOW)
	var ctx := _context(c)
	var t := _transport(ctx)
	var trip := t.trace_trip(c, Vector2i(10, 9))
	check(trip["reached"], "train connects the two road stubs")
	check(trip["rail"])
	check(not trip["subway"])
	_pass(t, ctx)
	check_ge(int(t.ridership()[&"rail"]), 1)
	check_eq(t.unreachable_ratio(), 0.0)


func test_plain_rail_does_not_admit_a_trip() -> void:
	var c := flat_city()
	c.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	_road_row(c, 10, 10, 40, Buildings.RAIL_FIRST)
	c.stamp_building(40, 11, SHOP, Zones.COM_LOW)
	var ctx := _context(c)
	check(not _transport(ctx).reachable(c, Vector2i(10, 9)))


func test_subway_links_two_road_networks() -> void:
	var c := flat_city()
	c.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	_road_row(c, 10, 10, 12)
	c.stamp_building(13, 10, Buildings.SUBWAY_STATION)
	var tunnel := UtilityParams.subway_code(UtilityParams.EW_MASK)
	for x in range(14, 41):
		c.underground.put(x, 10, tunnel)
	c.underground.put(20, 10, UtilityParams.CROSSING_PIPE_NS_UNDER_SUBWAY_EW)
	c.stamp_building(41, 10, Buildings.SUBWAY_STATION)
	_road_row(c, 10, 42, 44)
	c.stamp_building(45, 10, SHOP, Zones.COM_LOW)
	var ctx := _context(c)
	var t := _transport(ctx)
	var trip := t.trace_trip(c, Vector2i(10, 9))
	check(trip["reached"])
	check(trip["subway"])
	_pass(t, ctx)
	check_ge(int(t.ridership()[&"subway"]), 1)


func test_portal_joins_rail_and_subway() -> void:
	var c := flat_city()
	c.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	_road_row(c, 10, 10, 12)
	c.stamp_building(13, 10, Buildings.RAIL_STATION)
	_road_row(c, 10, 15, 24, Buildings.RAIL_FIRST)
	c.building.put(25, 10, Buildings.SUBWAY_PORTAL_FIRST)
	var tunnel := UtilityParams.subway_code(UtilityParams.EW_MASK)
	for x in range(26, 41):
		c.underground.put(x, 10, tunnel)
	c.stamp_building(41, 10, Buildings.SUBWAY_STATION)
	_road_row(c, 10, 42, 44)
	c.stamp_building(45, 10, SHOP, Zones.COM_LOW)
	var ctx := _context(c)
	var trip := _transport(ctx).trace_trip(c, Vector2i(10, 9))
	check(trip["reached"])
	check(trip["rail"] and trip["subway"], "one trip rides both")


func test_highway_reaches_where_a_long_road_cannot() -> void:
	var by_road := flat_city()
	by_road.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	_road_row(by_road, 10, 10, 44)
	by_road.stamp_building(45, 10, SHOP, Zones.COM_LOW)
	check(not _transport(_context(by_road)).reachable(by_road, Vector2i(10, 9)),
		"35 road tiles exceed the trip budget")

	var by_highway := flat_city()
	by_highway.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	_road_row(by_highway, 10, 10, 12)
	by_highway.building.put(13, 10, Buildings.ONRAMP_FIRST)
	_road_row(by_highway, 10, 14, 40, Buildings.HIGHWAY_FIRST)
	by_highway.building.put(41, 10, Buildings.ONRAMP_FIRST)
	_road_row(by_highway, 10, 42, 44)
	by_highway.stamp_building(45, 10, SHOP, Zones.COM_LOW)
	var ctx := _context(by_highway)
	var t := _transport(ctx)
	var trip := t.trace_trip(by_highway, Vector2i(10, 9))
	check(trip["reached"], "highway is three times faster")
	check(trip["highway"])
	_pass(t, ctx)
	check_gt(by_highway.traffic_at(30, 10), 0, "cars on the highway count as traffic")


func test_highway_lane_needs_a_ramp() -> void:
	var c := flat_city()
	c.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	_road_row(c, 10, 10, 12)
	_road_row(c, 10, 13, 20, Buildings.HIGHWAY_FIRST)
	_road_row(c, 10, 21, 23)
	c.stamp_building(24, 10, SHOP, Zones.COM_LOW)
	check(not _transport(_context(c)).reachable(c, Vector2i(10, 9)))


func test_tunnel_passes_under_a_hill() -> void:
	var c := flat_city()
	c.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	_road_row(c, 10, 10, 12)
	c.building.put(13, 10, Buildings.TUNNEL_FIRST)
	for x in range(14, 20):
		c.set_heights(x, 10, 8)
		c.set_tunnel_bits(x, 10, 1)
		c.building.put(x, 10, Buildings.TREES_1)
	c.building.put(20, 10, Buildings.TUNNEL_FIRST)
	_road_row(c, 10, 21, 23)
	c.stamp_building(24, 10, SHOP, Zones.COM_LOW)
	check(_transport(_context(c)).reachable(c, Vector2i(10, 9)))


func test_road_to_map_edge_reaches_a_neighbour() -> void:
	var c := flat_city()
	_road_row(c, 10, 0, 3)
	c.stamp_building(3, 9, HOUSE, Zones.RES_LOW)
	check(_transport(_context(c)).reachable(c, Vector2i(3, 9)))


func test_traffic_decays_when_trips_stop() -> void:
	var c := flat_city()
	_road_row(c, 10, 10, 20)
	c.stamp_building(10, 7, BIG_HOUSE, Zones.RES_HIGH)
	c.stamp_building(20, 11, SHOP, Zones.COM_LOW)
	var ctx := _context(c)
	var t := _transport(ctx)
	_pass(t, ctx)
	var before := c.traffic_at(16, 10)
	check_ge(before, 4, "a 3×3 lot deposits weight 3 per tile")
	c.clear_footprint(20, 11)
	_pass(t, ctx)
	var after := c.traffic_at(16, 10)
	check_lt(after, before, "a quarter is lost each month")
	check_gt(after, 0, "but it lingers")
	check_eq(t.unreachable_ratio(), 1.0)


func test_heavy_commuting_reports_a_jam_once() -> void:
	var c := flat_city()
	_road_row(c, 20, 0, 40)
	for i in 12:
		c.stamp_building(i * 3 + 2, 17, BIG_HOUSE, Zones.RES_HIGH)
		c.stamp_building(i * 3 + 2, 21, BIG_HOUSE, Zones.RES_HIGH)
	c.stamp_building(41, 20, SHOP, Zones.COM_LOW)
	var ctx := _context(c)
	var t := _transport(ctx)
	var jams := 0
	for _month in 8:
		jams += _pass(t, ctx).count(&"traffic_jam")
	check_ge(ctx.stats.average_traffic, TransportParams.JAM_LEVEL)
	check_eq(jams, 1, "one story, then the cooldown")


func test_yearly_publishes_riders_and_resets() -> void:
	var c := flat_city()
	_road_row(c, 10, 10, 30)
	c.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	c.stamp_building(12, 8, Buildings.BUS_DEPOT)
	c.stamp_building(30, 11, SHOP, Zones.COM_LOW)
	var ctx := _context(c)
	var t := _transport(ctx)
	for _month in GameClock.MONTHS_PER_YEAR:
		_pass(t, ctx)
	t.yearly(ctx)
	check(ctx.stats.history.has(&"riders_bus"))
	check_eq(ctx.stats.history[&"riders_bus"].size(), 1)
	check_eq(ctx.stats.history[&"riders_bus"][0], 12, "one rider a month all year")
	check_eq(ctx.stats.history[&"riders_rail"][0], 0)
	check_eq(int(t.ridership()[&"bus"]), 0, "counters reset for the new year")


func test_large_cities_are_sampled_in_turn() -> void:
	var c := flat_city()
	for y in 20:
		for x in 20:
			c.stamp_building(x * 2, y * 2, HOUSE, Zones.RES_LOW)
	var ctx := _context(c)
	var t := _transport(ctx)
	_pass(t, ctx)
	check_eq(t.trips_attempted(), TransportParams.TRIPS_PER_PASS)
	check_eq(t.trips_completed(), 0)
	check_eq(t.unreachable_ratio(), 1.0)
	var first: Dictionary = t.save()
	_pass(t, ctx)
	check_ne(int(t.save()["cursor"]), int(first["cursor"]), "the sample window advances")


func test_save_load_round_trip() -> void:
	var c := flat_city()
	_road_row(c, 10, 10, 30)
	c.stamp_building(10, 9, HOUSE, Zones.RES_LOW)
	c.stamp_building(12, 8, Buildings.BUS_DEPOT)
	c.stamp_building(30, 11, SHOP, Zones.COM_LOW)
	var ctx := _context(c)
	var t := _transport(ctx)
	_pass(t, ctx)
	_pass(t, ctx)
	var saved: Dictionary = t.save()
	var back: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var fresh := TransportSystem.new()
	fresh.load(back)
	check_eq(fresh.save(), saved)
	check_eq(fresh.ridership(), t.ridership())
	check_eq(fresh.unreachable_ratio(), t.unreachable_ratio())


## A full map of blocks between a road grid: half residential, half commercial.
func _grid_city(all_residential: bool) -> City:
	var c := flat_city()
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var border := x == 0 or y == 0 or x == City.WIDTH - 1 or y == City.HEIGHT - 1
			if (x % 4 == 0 or y % 4 == 0) and not border:
				c.building.put(x, y, ROAD)
	for by in 32:
		for bx in 32:
			var x := bx * 4 + 1
			var y := by * 4 + 1
			if x + 2 >= City.WIDTH or y + 2 >= City.HEIGHT:
				continue
			if all_residential or (bx + by) % 2 == 0:
				c.stamp_building(x, y, BIG_HOUSE, Zones.RES_HIGH)
			else:
				c.stamp_building(x, y, Buildings.COM_3X3_FIRST, Zones.COM_HIGH)
	return c


func test_full_city_pass_is_bounded() -> void:
	for worst_case in [false, true]:
		var c := _grid_city(worst_case)
		var ctx := _context(c)
		var t := _transport(ctx)
		var started := Time.get_ticks_usec()
		t.monthly(ctx)
		var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
		print("    full-city pass (%s): %.1f ms, %d trips, %d completed" % [
			"no destinations" if worst_case else "mixed", elapsed_ms, t.trips_attempted(), t.trips_completed()])
		if worst_case:
			check_eq(t.trips_completed(), 0)
			check_lt(t.trips_attempted(), TransportParams.TRIPS_PER_PASS, "the search budget cuts the pass short")
			check_ge(t.states_searched(), TransportParams.PASS_SEARCH_BUDGET)
		else:
			check_eq(t.trips_attempted(), TransportParams.TRIPS_PER_PASS)
			check_eq(t.trips_completed(), TransportParams.TRIPS_PER_PASS)
		check_lt(elapsed_ms, 500.0, "pass stays bounded")


func test_simulation_runs_the_pass_on_day_eight() -> void:
	var c := flat_city()
	for y in 20:
		for x in 20:
			c.stamp_building(x * 2, y * 2, HOUSE, Zones.NONE)
	var sim := make_simulation(c)
	var t := sim.get_system(&"transport") as TransportSystem
	check(t != null)
	sim.advance_days(TRANSPORT_DAY - 1)
	check_eq(t.trips_attempted(), 0)
	sim.advance_day()
	check_eq(t.trips_attempted(), TransportParams.TRIPS_PER_PASS)
	# Release the context/system reference cycle before the synchronous harness quits.
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()
