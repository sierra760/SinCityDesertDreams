# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"


func test_grid_bounds_are_safe() -> void:
	var g := Grid8.new(4, 4)
	g.put(-1, 0, 7)
	g.put(4, 4, 7)
	check_eq(g.at(-1, 0), 0)
	check_eq(g.at(9, 9), 0)
	g.put(2, 3, 200)
	check_eq(g.at(2, 3), 200)
	g.set_bits(2, 3, 0x01, true)
	check(g.has_bits(2, 3, 0x01))
	g.set_bits(2, 3, 0x01, false)
	check(not g.has_bits(2, 3, 0x01))


func test_altitude_packing() -> void:
	var c := City.new()
	c.set_heights(5, 5, 12, 9)
	check_eq(c.ground_height(5, 5), 12)
	check_eq(c.water_height(5, 5), 9)
	c.set_tunnel_bits(5, 5, 3)
	check_eq(c.tunnel_bits(5, 5), 3)
	check_eq(c.ground_height(5, 5), 12)
	c.set_heights(5, 5, 3)
	check_eq(c.water_height(5, 5), 9, "water height kept when omitted")


func test_terrain_codes() -> void:
	check(Terrain.is_flat(Terrain.FLAT))
	check(Terrain.is_flat(Terrain.PLATEAU))
	check(not Terrain.is_flat(Terrain.SLOPE_N))
	check(Terrain.is_water(Terrain.make(Terrain.FLAT, Terrain.SURFACE)))
	check(not Terrain.is_water(Terrain.make(Terrain.SLOPE_E)))
	check_eq(Terrain.water_kind(Terrain.WATERFALL), Terrain.WATERFALL)
	for s in range(Terrain.PLATEAU + 1):
		check_eq(Terrain.shape_from_corners(Terrain.raised_corners(s)), s, "shape %d round trip" % s)
	check_eq(Terrain.shape_from_corners(1 | 4), -1)


func test_footprint_stamp_and_anchor() -> void:
	var c := flat_city()
	var a := c.stamp_building(10, 10, Buildings.COAL_PLANT)
	check_eq(a, Vector2i(10, 10))
	for dy in 4:
		for dx in 4:
			check_eq(c.building_at(10 + dx, 10 + dy), Buildings.COAL_PLANT)
			check_eq(c.anchor_of(10 + dx, 10 + dy), Vector2i(10, 10), "anchor from (%d,%d)" % [dx, dy])
	check(Zones.corners(c.zone.at(10, 10)) & Zones.CORNER_NW)
	check(Zones.corners(c.zone.at(13, 13)) & Zones.CORNER_SE)
	var census := c.building_census()
	check_eq(census[Buildings.COAL_PLANT], 1)
	var cleared := c.clear_footprint(12, 12)
	check_eq(cleared, Rect2i(10, 10, 4, 4))
	check_eq(c.building_at(11, 11), Buildings.NONE)


func test_building_roster_is_complete() -> void:
	check_eq(Buildings.COUNT, 262)
	check_eq(Buildings.id_of(&"plant_coal"), Buildings.COAL_PLANT)
	check_eq(Buildings.size(Buildings.ARCOLOGY_ORBIT), Vector2i(4, 4))
	check_eq(Buildings.cost(Buildings.POLICE_STATION), 500)
	check(Buildings.is_road_like(Buildings.ROAD_FIRST))
	check(Buildings.carries_power(Buildings.POWER_LINE_FIRST))
	check(not Buildings.carries_power(Buildings.ROAD_FIRST))
	var seen := {}
	for id in Buildings.all_ids():
		var k := Buildings.key(id)
		check(not seen.has(k), "duplicate key %s" % k)
		seen[k] = true
	check_eq(Buildings.zone_stage_ids(Zones.RES_HIGH, 3).size(), 4)


func test_clock_calendar() -> void:
	var clock := GameClock.new()
	clock.founded_year = 1950
	check_eq(clock.year(), 1950)
	check_eq(clock.month(), 1)
	check_eq(clock.day_of_month(), 1)
	clock.day = 299
	check(clock.is_year_end())
	check_eq(clock.month(), 12)
	clock.advance()
	check_eq(clock.year(), 1951)
	check(clock.is_year_start())


func test_stats_round_trip() -> void:
	var s := CityStats.new()
	s.demand = Vector3i(100, -50, 7)
	s.population = 1234
	s.bonds.append({"principal": 10000, "rate": 5})
	s.set_funding(&"police", 60)
	s.record(&"population", 5)
	var d := s.to_dict()
	var json := JSON.stringify(d)
	var back: Dictionary = JSON.parse_string(json)
	var t := CityStats.new()
	t.from_dict(back)
	check_eq(t.demand, Vector3i(100, -50, 7))
	check_eq(t.population, 1234)
	check_eq(t.bonds.size(), 1)
	check_eq(int(t.bonds[0]["principal"]), 10000)
	check_eq(t.funding_of(&"police"), 60)
	check_eq(t.history[&"population"].size(), 1)


func test_simulation_advances_without_systems() -> void:
	var c := flat_city()
	c.founded_year = 1900
	var sim := make_simulation(c)
	var days := [0]
	sim.day_advanced.connect(func(_y: int, _m: int, _d: int) -> void: days[0] += 1)
	sim.advance_days(30)
	check_eq(days[0], 30)
	check_eq(sim.clock.month(), 2)
	check_eq(c.day, 30)
	var snap := sim.snapshot()
	check_eq(int(snap["clock_day"]), 30)
	sim.advance_days(300)
	check_eq(sim.clock.year(), 1901)
	check(sim.budget_review_pending == false, "advance_days clears the review")
	sim.queue_free()
