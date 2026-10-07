# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## The wear system is driven directly through a SimContext so these tests do
## not depend on the other systems. One test at the end checks the Simulation
## schedules the pass on day 18.

const WEAR_DAY := 18
const ROAD := Buildings.ROAD_FIRST


func _context(c: City, seed_value: int = 12345) -> SimContext:
	var ctx := make_context(c, seed_value)
	ctx.clock.founded_year = c.founded_year
	return ctx


func _wear(ctx: SimContext) -> WearSystem:
	var w := WearSystem.new()
	ctx.systems[w.key] = w
	w.setup(ctx)
	return w


var _dirty_seen := false


## Run `months` passes and return every story queued along the way.
func _months(w: WearSystem, ctx: SimContext, months: int) -> Array[Dictionary]:
	var stories: Array[Dictionary] = []
	for _m in months:
		ctx.events.clear()
		w.monthly(ctx)
		stories.append_array(ctx.events.news)
		if ctx.events.map_dirty.size != Vector2i.ZERO:
			_dirty_seen = true
	return stories


func _row(c: City, y: int, x0: int, x1: int, id: int) -> void:
	for x in range(x0, x1 + 1):
		c.building.put(x, y, id)


func _count(c: City, id_first: int, id_last: int) -> int:
	var n := 0
	for v in c.building.data:
		if v >= id_first and v <= id_last:
			n += 1
	return n


func _stories_of(stories: Array[Dictionary], kind: StringName, category: String = "") -> int:
	var n := 0
	for s in stories:
		if s["kind"] == kind and (category == "" or s["args"].get("category", "") == category):
			n += 1
	return n


func _two_hundred_roads() -> City:
	var c := flat_city()
	_row(c, 10, 0, 99, ROAD)
	_row(c, 20, 0, 99, ROAD)
	return c


func test_unfunded_roads_crumble_and_funded_roads_last() -> void:
	var c := _two_hundred_roads()
	var ctx := _context(c)
	var w := _wear(ctx)
	ctx.stats.set_funding(&"roads", 0)
	var stories := _months(w, ctx, 6)
	var lost := 200 - int(w.network_counts()[&"roads"])
	check_between(lost, 3, 9, "about one road a month at zero funding")
	check_eq(_count(c, Buildings.RUBBLE_1, Buildings.RUBBLE_4), lost, "lost roads become rubble")
	check_eq(int(w.losses()[&"roads"]), lost)
	check_eq(_stories_of(stories, &"road_decay", "roads"), lost, "one story per lost road")
	check(_dirty_seen, "the renderer is told")

	var control := _two_hundred_roads()
	var funded_ctx := _context(control)
	var funded := _wear(funded_ctx)
	_months(funded, funded_ctx, 6)
	check_eq(int(funded.network_counts()[&"roads"]), 200, "full funding loses nothing")
	check_eq(funded.wear_percent(&"roads"), 0)


func test_restored_funding_stops_further_loss_without_repair() -> void:
	var c := _two_hundred_roads()
	var ctx := _context(c)
	var w := _wear(ctx)
	ctx.stats.set_funding(&"roads", 0)
	_months(w, ctx, 4)
	var damaged := int(w.network_counts()[&"roads"])
	check_lt(damaged, 200)
	ctx.stats.set_funding(&"roads", 100)
	_months(w, ctx, 8)
	check_eq(int(w.network_counts()[&"roads"]), damaged, "no further loss, no repair")


func test_partial_funding_wears_slower() -> void:
	var c := _two_hundred_roads()
	var ctx := _context(c)
	var w := _wear(ctx)
	ctx.stats.set_funding(&"roads", 50)
	_months(w, ctx, 6)
	var lost := 200 - int(w.network_counts()[&"roads"])
	check_between(lost, 1, 5, "half the funding, about half the wear")


func test_unfunded_rail_loses_track() -> void:
	var c := flat_city()
	_row(c, 10, 10, 109, Buildings.RAIL_FIRST)
	c.building.put(5, 10, Buildings.SUBWAY_PORTAL_FIRST)
	var ctx := _context(c)
	var w := _wear(ctx)
	ctx.stats.set_funding(&"rail", 0)
	var stories := _months(w, ctx, 6)
	var lost := 101 - int(w.network_counts()[&"rail"])
	check_between(lost, 2, 7)
	check_eq(c.building_at(5, 10), Buildings.SUBWAY_PORTAL_FIRST, "portals are never lost")
	check_eq(_stories_of(stories, &"rail_decay", "rail"), lost)


func test_unfunded_highway_loses_whole_blocks() -> void:
	var c := flat_city()
	_row(c, 10, 0, 99, Buildings.HIGHWAY_FIRST)
	_row(c, 11, 0, 99, Buildings.HIGHWAY_FIRST)
	var ctx := _context(c)
	var w := _wear(ctx)
	ctx.stats.set_funding(&"highways", 0)
	var stories := _months(w, ctx, 6)
	var lost := 200 - int(w.network_counts()[&"highways"])
	check_ge(lost, 4)
	check_eq(lost % 4, 0, "highway wear removes aligned 2×2 blocks")
	check_eq(_count(c, Buildings.RUBBLE_1, Buildings.RUBBLE_4), lost)
	@warning_ignore("integer_division")
	check_eq(_stories_of(stories, &"road_decay", "highways"), lost / 4)


func test_unfunded_bridge_collapses_entirely() -> void:
	var c := flat_city()
	for x in range(20, 60):
		c.terrain.put(x, 10, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
		c.building.put(x, 10, Buildings.BRIDGE_FIRST + 2)
	var ctx := _context(c)
	var w := _wear(ctx)
	ctx.stats.set_funding(&"bridges", 0)
	check_eq(int(w.network_counts()[&"bridges"]), 40)
	var stories := _months(w, ctx, 4)
	check_eq(int(w.network_counts()[&"bridges"]), 0, "the whole span is gone")
	check_eq(c.building_at(40, 10), Buildings.NONE, "open water, not rubble")
	check_eq(_stories_of(stories, &"bridge_collapse"), 1)
	for s in stories:
		if s["kind"] == &"bridge_collapse":
			check_eq(int(s["args"]["tiles"]), 40)


func test_one_collapse_per_bridge_even_with_surplus_wear() -> void:
	var c := flat_city()
	for x in range(20, 60):
		c.terrain.put(x, 10, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
		c.building.put(x, 10, Buildings.BRIDGE_FIRST + 2)
	var ctx := _context(c)
	var w := _wear(ctx)
	var threshold: int = TransportParams.WEAR_THRESHOLD[&"bridges"]
	w.load({"wear": {"bridges": threshold * 3}})
	check_eq(int(w.network_counts()[&"bridges"]), 40)
	var stories := _months(w, ctx, 1)
	check_eq(_stories_of(stories, &"bridge_collapse"), 1, "a span already gone is not news again")
	for s in stories:
		if s["kind"] == &"bridge_collapse":
			check_eq(int(s["args"]["tiles"]), 40)
	check_eq(int(w.losses()[&"bridges"]), 40)
	check_eq(w.wear_percent(&"bridges"), 100, "removed tiles use up no wear")


func test_map_edits_outside_construction_refresh_the_scan() -> void:
	var c := _two_hundred_roads()
	var ctx := _context(c)
	var w := _wear(ctx)
	check_eq(int(w.network_counts()[&"roads"]), 200)
	var full := w.maintenance_cost(&"roads")
	# A disaster or port edits the map without a networks change.
	_row(c, 10, 0, 99, Buildings.SMALL_PARK)
	check_eq(int(w.network_counts()[&"roads"]), 100, "wrecked roads leave the count")
	@warning_ignore("integer_division")
	check_eq(w.maintenance_cost(&"roads"), full / 2, "and stop costing upkeep")
	ctx.stats.set_funding(&"roads", 0)
	_months(w, ctx, 24)
	for x in 100:
		check_eq(c.building_at(x, 10), Buildings.SMALL_PARK, "wear only removes roads")

func test_unfunded_subway_caves_in_but_spares_crossings() -> void:
	var c := flat_city()
	var tunnel := UtilityParams.subway_code(UtilityParams.EW_MASK)
	for x in 100:
		c.underground.put(x, 10, tunnel)
		c.underground.put(x, 11, tunnel)
	c.underground.put(5, 12, UtilityParams.CROSSING_PIPE_NS_UNDER_SUBWAY_EW)
	c.underground.put(6, 12, UtilityParams.SUBWAY_STATION_LINK)
	var ctx := _context(c)
	var w := _wear(ctx)
	check_eq(int(w.network_counts()[&"subway"]), 202)
	ctx.stats.set_funding(&"subway", 0)
	var stories := _months(w, ctx, 6)
	var lost := 202 - int(w.network_counts()[&"subway"])
	check_between(lost, 3, 9)
	check_eq(c.underground.at(5, 12), UtilityParams.CROSSING_PIPE_NS_UNDER_SUBWAY_EW)
	check_eq(c.underground.at(6, 12), UtilityParams.SUBWAY_STATION_LINK)
	check_eq(_stories_of(stories, &"rail_decay", "subway"), lost)


func test_unfunded_tunnel_loses_its_entrance() -> void:
	var c := flat_city()
	for i in 100:
		c.building.put(i, 10 + (i % 2) * 2, Buildings.TUNNEL_FIRST)
	var ctx := _context(c)
	var w := _wear(ctx)
	ctx.stats.set_funding(&"tunnels", 0)
	var stories := _months(w, ctx, 6)
	var lost := 100 - int(w.network_counts()[&"tunnels"])
	check_between(lost, 1, 5)
	check_eq(_stories_of(stories, &"road_decay", "tunnels"), lost)


func test_network_counts_classify_tiles() -> void:
	var c := flat_city()
	c.building.put(1, 1, ROAD)
	c.building.put(2, 1, 69)                                  # level crossing counts as road
	c.building.put(3, 1, Buildings.TUNNEL_FIRST)
	c.building.put(4, 1, Buildings.RAIL_FIRST)
	c.building.put(5, 1, 71)                                  # rail under power counts as rail
	c.building.put(6, 1, Buildings.SUBWAY_PORTAL_FIRST)
	c.building.put(7, 1, Buildings.HIGHWAY_FIRST)
	c.building.put(8, 1, Buildings.ONRAMP_FIRST)
	c.building.put(9, 1, Buildings.REINFORCED_BRIDGE)          # highway bridge
	c.building.put(10, 1, Buildings.BRIDGE_FIRST)
	c.building.put(11, 1, 92)                                 # elevated power line: not transport
	c.underground.put(1, 5, UtilityParams.subway_code(1))
	c.underground.put(2, 5, UtilityParams.pipe_code(1))
	var counts := _wear(_context(c)).network_counts()
	check_eq(int(counts[&"roads"]), 2)
	check_eq(int(counts[&"tunnels"]), 1)
	check_eq(int(counts[&"rail"]), 3)
	check_eq(int(counts[&"highways"]), 3)
	check_eq(int(counts[&"bridges"]), 1)
	check_eq(int(counts[&"subway"]), 1)


func test_maintenance_cost_scales_with_tiles_and_funding() -> void:
	var c := flat_city()
	_row(c, 10, 0, 99, ROAD)
	for x in range(0, 20):
		c.terrain.put(x, 20, Terrain.make(Terrain.FLAT, Terrain.SURFACE))
		c.building.put(x, 20, Buildings.BRIDGE_FIRST + 2)
	var ctx := _context(c)
	var w := _wear(ctx)
	var road_cents: int = TransportParams.UPKEEP_CENTS[&"roads"]
	var bridge_cents: int = TransportParams.UPKEEP_CENTS[&"bridges"]
	@warning_ignore("integer_division")
	check_eq(w.maintenance_cost(&"roads"), 100 * road_cents / 100)
	@warning_ignore("integer_division")
	check_eq(w.maintenance_cost(&"roads", 50), 100 * road_cents / 200)
	@warning_ignore("integer_division")
	check_eq(w.maintenance_cost(&"bridges"), 20 * bridge_cents / 100)
	check_eq(w.maintenance_cost(&"subway"), 0)
	check_eq(w.maintenance_cost(&"nonsense"), 0)
	check_eq(w.maintenance_total(false), w.maintenance_cost(&"roads") + w.maintenance_cost(&"bridges"))
	ctx.stats.set_funding(&"roads", 0)
	check_eq(w.maintenance_total(true), w.maintenance_cost(&"bridges"))


func test_construction_refreshes_counts() -> void:
	var c := flat_city()
	var ctx := _context(c)
	var w := _wear(ctx)
	check_eq(int(w.network_counts()[&"roads"]), 0)
	_row(c, 10, 0, 9, ROAD)
	w.networks_changed(ctx, Rect2i(0, 10, 10, 1))
	check_eq(int(w.network_counts()[&"roads"]), 10)


func test_save_load_round_trip() -> void:
	var c := _two_hundred_roads()
	var ctx := _context(c)
	var w := _wear(ctx)
	ctx.stats.set_funding(&"roads", 0)
	_months(w, ctx, 3)
	check_gt(w.wear_percent(&"roads"), 0, "some wear is carried over")
	var saved: Dictionary = w.save()
	var back: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var fresh := WearSystem.new()
	fresh.load(back)
	check_eq(fresh.save(), saved)
	check_eq(fresh.wear_percent(&"roads"), w.wear_percent(&"roads"))
	check_eq(fresh.losses(), w.losses())


func test_simulation_runs_the_pass_on_day_eighteen() -> void:
	var c := _two_hundred_roads()
	var sim := make_simulation(c)
	var w := sim.get_system(&"wear") as WearSystem
	check(w != null)
	sim.stats.set_funding(&"roads", 0)
	sim.advance_days(WEAR_DAY - 1)
	check_eq(w.wear_percent(&"roads"), 0)
	sim.advance_day()
	check_gt(w.wear_percent(&"roads") + int(w.losses()[&"roads"]), 0, "wear accrued on day 18")
	# Release the context/system reference cycle before the synchronous harness quits.
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()
