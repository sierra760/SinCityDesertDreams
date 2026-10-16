# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Synthetic lots/service flags for unit tests, not a full-host service proof.
class_name TourismFixture
extends RefCounted

static func context(city: City) -> SimContext:
	var ctx := SimContext.new()
	ctx.city = city
	ctx.stats = CityStats.new()
	ctx.rng = SimRng.new(7)
	ctx.clock = GameClock.new()
	ctx.clock.day = city.day
	ctx.events = CityEvents.new()
	return ctx

static func venue(city: City, key: StringName, anchor: Vector2i) -> Vector2i:
	return city.stamp_building(anchor.x, anchor.y, Buildings.id_of(key))

static func set_served(city: City, anchor: Vector2i, powered: bool, watered: bool) -> void:
	var size := Buildings.size(city.building_at(anchor.x, anchor.y))
	for dy in size.y:
		for dx in size.x:
			city.set_flag(anchor.x + dx, anchor.y + dy, TileFlags.POWERED, powered)
			city.set_flag(anchor.x + dx, anchor.y + dy, TileFlags.WATERED, watered)

## A synthetic served store with real Tourism/Budget systems; callers own cleanup.
## This is deliberately not a physical utility-network or rendered-host proof.
static func host_with_store(visitors: int = 24) -> SimContext:
	var city := City.new()
	city.funds = 10000
	for y in City.HEIGHT:
		for x in City.WIDTH:
			city.terrain.put(x, y, Terrain.FLAT)
			city.set_heights(x, y, 4, 0)
	var at := Vector2i(10, 10)
	venue(city, &"com_corner_store", at)
	set_served(city, at, true, true)
	for x in range(10): city.building.put(x,10,Buildings.ROAD_FIRST)
	var ctx := context(city)
	ctx.stats.population = 123
	var tourism := TourismSystem.new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	assert(tourism.finish_restore({}) == OK)
	var saved := tourism.save()
	saved.state.records[0].day_visitors = visitors
	saved.state.records[0].day_segments = TourismMarkets.partition(visitors,TourismMarkets.DAY_WEIGHTS)
	reservation_rows(saved)
	assert(tourism.finish_restore({"systems": {"tourism": saved}}) == OK)
	var budget := BudgetSystem.new()
	ctx.systems[&"budget"] = budget
	budget.setup(ctx)
	return ctx


## Connect synthetic road frontages through vacant ground, preserving every lot.
## District fixtures formerly asserted provisional proximity on isolated roads.
static func connect_roads(city: City) -> void:
	var roads := PackedInt32Array()
	for i in city.building.data.size():
		if city.building.data[i] == Buildings.ROAD_FIRST: roads.append(i)
	if roads.is_empty(): return
	var connected := {roads[0]:true}
	for start in roads:
		if connected.has(start): continue
		var queue := PackedInt32Array([start])
		var parent := {start:-1}
		var head := 0
		var found := -1
		while head < queue.size():
			var tile := queue[head]
			head += 1
			if connected.has(tile):
				found = tile
				break
			@warning_ignore("integer_division")
			var at := Vector2i(tile%City.WIDTH,tile/City.WIDTH)
			for step in [Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN]:
				var next: Vector2i = at+step
				var index := next.y*City.WIDTH+next.x
				if not city.in_bounds(next.x,next.y) or parent.has(index): continue
				if city.building_at(next.x,next.y) not in [Buildings.NONE,Buildings.ROAD_FIRST] or city.is_water(next.x,next.y): continue
				parent[index] = tile
				queue.append(index)
		while found >= 0:
			city.building.data[found] = Buildings.ROAD_FIRST
			connected[found] = true
			found = parent[found]

## Fixture-only attendance authoring. Real state validates rather than repairing.
static func segment_rows(rows: Array) -> void:
	for row: Dictionary in rows:
		row["guest_segments"] = TourismMarkets.partition(int(row.guests),TourismMarkets.GUEST_WEIGHTS)
		row["day_segments"] = TourismMarkets.partition(int(row.day_visitors),TourismMarkets.DAY_WEIGHTS)


## Fixture-authored current attendance must author its exact reservation too.
static func reservation_rows(block: Dictionary) -> void:
	if not block.get("features",{}).get("utilities",{}).is_empty():
		block.features.utilities.rows = TourismUtilities.snapshot(block.state.records)

## Physical established source fixtures for scheduler/fire integration tests.
## Fixed source output is deliberate; this does not test weather generation.
static func established_sources(sim: Simulation) -> void:
	var city := sim.city
	city.stamp_building(6,6,Buildings.COAL_PLANT)
	city.building.put(10,9,Buildings.POWER_LINE_FIRST)
	city.stamp_building(9,11,Buildings.WATER_PUMP)
	var full := Rect2i(0,0,City.WIDTH,City.HEIGHT)
	sim.get_system(&"power").networks_changed(sim._ctx,full)
	sim.get_system(&"water").networks_changed(sim._ctx,full)
	city.facility(Vector2i(9,11))["output"] = 100
	sim.get_system(&"water").reallocate_established(sim._ctx,full)
	sim.tourism().reconcile_now()
