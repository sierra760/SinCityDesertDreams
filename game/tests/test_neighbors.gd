# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

var _contexts: Array[SimContext] = []


func after_each() -> void:
	# Hand-built fixtures own the context table without a Simulation Node.
	for ctx: SimContext in _contexts:
		ctx.systems.clear()
	_contexts.clear()


func make_ctx(c: City, seed_value: int = 11) -> SimContext:
	var ctx := make_context(c, seed_value)
	_contexts.append(ctx)
	return ctx


func make_neighbors(ctx: SimContext) -> NeighborSystem:
	var n := NeighborSystem.new()
	ctx.systems[&"neighbors"] = n
	n.setup(ctx)
	return n


func population_sum(stats: CityStats) -> int:
	var total := 0
	for p in stats.neighbor_populations:
		total += p
	return total


func test_founding_gives_four_named_towns() -> void:
	var ctx := make_ctx(flat_city())
	var n := make_neighbors(ctx)
	var report := n.neighbor_report()
	check_eq(report.size(), 4)
	var names := {}
	for entry in report:
		check_between(int(entry["population"]), NeighborParams.FOUNDING_MIN,
			NeighborParams.FOUNDING_MIN + NeighborParams.FOUNDING_SPREAD)
		check_between(int(entry["output"]), 1, int(entry["population"]))
		check(not names.has(entry["name"]), "distinct name %s" % entry["name"])
		names[entry["name"]] = true
		check(not bool(entry["connected"]["road"]), "an empty map reaches nobody")
	check_eq(ctx.stats.neighbor_populations.size(), 4)
	check_gt(ctx.stats.neighbor_populations[0], 0)


func test_neighbors_grow_with_the_economy() -> void:
	var ctx := make_ctx(flat_city())
	var n := make_neighbors(ctx)
	ctx.stats.economy_phase = 3
	var before := population_sum(ctx.stats)
	for _m in 12:
		n.monthly(ctx)
	var shocked := not ctx.events.news.filter(func(s): return s["kind"] == &"neighbor_shock").is_empty()
	check(population_sum(ctx.stats) > before or shocked, "a boom year grows the region unless a shock hit")
	for edge in 4:
		check_gt(ctx.stats.neighbor_populations[edge], 0)


func test_edge_scan_finds_each_network() -> void:
	var c := flat_city()
	c.building.put(5, 0, Buildings.ROAD_FIRST)
	c.building.put(City.WIDTH - 1, 40, Buildings.RAIL_FIRST)
	c.building.put(60, City.HEIGHT - 1, Buildings.POWER_LINE_FIRST)
	c.underground.put(0, 70, 1)
	var ctx := make_ctx(c)
	var n := make_neighbors(ctx)
	var conns := n.connections()
	check(bool(conns[NeighborParams.EDGE_NORTH]["road"]))
	check(not bool(conns[NeighborParams.EDGE_NORTH]["rail"]))
	check(bool(conns[NeighborParams.EDGE_EAST]["rail"]))
	check(bool(conns[NeighborParams.EDGE_SOUTH]["power"]))
	check(bool(conns[NeighborParams.EDGE_WEST]["water"]))
	check(not bool(conns[NeighborParams.EDGE_WEST]["road"]))
	check_eq(n.link_count(), 2)
	check_eq(n.commercial_demand_bonus(), 2 * NeighborParams.DEMAND_PER_LINK)
	c.building.put(5, 0, Buildings.NONE)
	n.networks_changed(ctx, Rect2i(5, 0, 1, 1))
	check(not bool(n.connections()[NeighborParams.EDGE_NORTH]["road"]), "demolition drops the link")
	check_eq(n.link_count(), 1)


func test_links_speed_up_a_neighbor() -> void:
	var quiet := make_ctx(flat_city(), 5)
	var a := make_neighbors(quiet)
	var linked_city := flat_city()
	linked_city.building.put(3, 0, Buildings.ROAD_FIRST)
	linked_city.building.put(4, 0, Buildings.RAIL_FIRST)
	var busy := make_ctx(linked_city, 5)
	var b := make_neighbors(busy)
	for edge in 4:
		quiet.stats.neighbor_populations[edge] = 100000
		busy.stats.neighbor_populations[edge] = 100000
	quiet.stats.economy_phase = 1
	busy.stats.economy_phase = 1
	for _m in 12:
		a.monthly(quiet)
		b.monthly(busy)
	check_gt(busy.stats.neighbor_populations[NeighborParams.EDGE_NORTH],
		quiet.stats.neighbor_populations[NeighborParams.EDGE_NORTH], "the connected town grows faster")
	check_eq(busy.stats.neighbor_populations[NeighborParams.EDGE_SOUTH],
		quiet.stats.neighbor_populations[NeighborParams.EDGE_SOUTH], "unconnected towns match with the same seed")


func test_utility_trade_needs_a_connection() -> void:
	var c := flat_city()
	var ctx := make_ctx(c)
	var n := make_neighbors(ctx)
	ctx.stats.power_capacity = 12000
	ctx.stats.power_demand = 2000
	n.monthly(ctx)
	check_eq(int(ctx.stats.ledger.get(&"neighbor_trade", 0)), 0, "surplus with no line earns nothing")
	c.building.put(10, 0, Buildings.POWER_LINE_FIRST)
	n.monthly(ctx)
	# 10,000 surplus units at 2 cents a year is 200 dollars, one twelfth per month.
	check_eq(int(ctx.stats.ledger[&"neighbor_trade"]), 200 / 12)
	for _m in 11:
		n.monthly(ctx)
	check_eq(int(ctx.stats.ledger[&"neighbor_trade"]), 200)
	check_eq(int(n.neighbor_report()[NeighborParams.EDGE_NORTH]["trade"]), 200)
	n.yearly(ctx)
	ctx.stats.ledger.erase(&"neighbor_trade")
	ctx.stats.power_capacity = 0
	ctx.stats.power_demand = 3000
	n.monthly(ctx)
	check_eq(int(ctx.stats.ledger[&"neighbor_trade"]), -120 / 12, "a shortfall on a connected line is bought in")


func test_trade_settles_through_the_budget() -> void:
	var c := flat_city(1000)
	c.building.put(10, 0, Buildings.POWER_LINE_FIRST)
	var ctx := make_ctx(c)
	var n := make_neighbors(ctx)
	var b := BudgetSystem.new()
	ctx.systems[&"budget"] = b
	b.setup(ctx)
	ctx.stats.power_capacity = 12000
	ctx.stats.power_demand = 2000
	for _m in 12:
		b.monthly(ctx)
		n.monthly(ctx)
	b.yearly(ctx)
	n.yearly(ctx)
	check_eq(c.funds, 1000 + 200, "power sales settle as income")
	check_eq(int(ctx.stats.last_year_ledger[&"neighbor_trade"]), 200)
	check(not ctx.stats.ledger.has(&"neighbor_trade") or int(ctx.stats.ledger[&"neighbor_trade"]) == 0)


func test_save_load_round_trip() -> void:
	var c := flat_city()
	c.building.put(7, 0, Buildings.ROAD_FIRST)
	var ctx := make_ctx(c)
	var n := make_neighbors(ctx)
	ctx.stats.power_capacity = 500
	for _m in 3:
		n.monthly(ctx)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(n.save()))
	var stats_json: Dictionary = JSON.parse_string(JSON.stringify(ctx.stats.to_dict()))
	# Same order as Simulation.restore: systems set up, then stats, then load.
	var ctx2 := make_ctx(flat_city(), 99)
	var n2 := make_neighbors(ctx2)
	ctx2.stats.from_dict(stats_json)
	n2.load(saved)
	var r1 := n.neighbor_report()
	var r2 := n2.neighbor_report()
	for edge in 4:
		check_eq(r2[edge]["name"], r1[edge]["name"], "name %d" % edge)
		check_eq(int(r2[edge]["population"]), int(r1[edge]["population"]), "population %d" % edge)
		check_eq(int(r2[edge]["output"]), int(r1[edge]["output"]), "output %d" % edge)
	check(bool(n2.connections()[NeighborParams.EDGE_NORTH]["road"]), "connections restored before any rescan")


## True when the Simulation loaded every system script. A sibling package with
## a parse error aborts loading; then only this package's own script is checked.
func simulation_loaded(sim: Simulation, own: StringName, path: String) -> bool:
	if sim.get_system(own) != null:
		return true
	var script: GDScript = load(path)
	check(script != null and script.new() != null, "own system script loads")
	print("    skipped: the Simulation could not load a sibling system")
	return false


func test_simulation_runs_the_neighbor_day() -> void:
	var c := flat_city()
	var sim := make_simulation(c)
	if not simulation_loaded(sim, &"neighbors", "res://scripts/sim/neighbor_system.gd"):
		sim.queue_free()
		return
	var n: NeighborSystem = sim.get_system(&"neighbors")
	var before := population_sum(sim.stats)
	check_gt(before, 0, "towns founded at setup")
	sim.advance_days(25)
	check_eq(n.neighbor_report().size(), 4)
	check(sim.snapshot()["systems"].has("neighbors"))
	sim.queue_free()
