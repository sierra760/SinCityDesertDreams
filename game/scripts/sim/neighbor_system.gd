# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The four towns beyond the map edges: founding, growth, shocks, edge
## connections and utility trade. Rules are in docs/simulation/neighbors.md.
class_name NeighborSystem
extends SimSystem

const TRADE_KEY := &"neighbor_trade"

var _ctx: SimContext
var _founded := false
## Index into NeighborParams.NAME_POOL per edge.
var _name_index: PackedInt32Array = PackedInt32Array([0, 1, 2, 3])
## Economic output per edge; grows alongside population.
var _output: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
## Per edge: {"road": bool, "rail": bool, "power": bool, "water": bool}.
var _connections: Array[Dictionary] = []
## Year-to-date trade in cents (twelfths of yearly cents, like the budget).
var _trade_twelfths := 0
## Year-to-date trade per edge in dollars, for the report.
var _trade_by_edge: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])


func _init() -> void:
	key = &"neighbors"
	for _i in NeighborParams.EDGE_COUNT:
		_connections.append({"road": false, "rail": false, "power": false, "water": false})


func setup(ctx: SimContext) -> void:
	_ctx = ctx
	if not _founded:
		# Restored stats already carry the region; only a fresh city founds one.
		if _has_region(ctx.stats):
			_founded = true
		else:
			_found(ctx)
	_scan_connections(ctx.city)


# ── Schedule ─────────────────────────────────────────────────────────────

func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_scan_connections(ctx.city)
	_grow(ctx)
	_trade(ctx)


func yearly(_ctx_unused: SimContext) -> void:
	# The budget has just settled the trade account; start the new year clean.
	_trade_twelfths = 0
	_trade_by_edge.fill(0)


func networks_changed(ctx: SimContext, _rect: Rect2i) -> void:
	_scan_connections(ctx.city)


# ── Public queries ───────────────────────────────────────────────────────

func neighbor_name(edge: int) -> String:
	return NeighborParams.NAME_POOL[_name_index[edge] % NeighborParams.NAME_POOL.size()]


## One entry per edge: name, edge, population, output, connections, trade.
func neighbor_report() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _ctx == null:
		return out
	for edge in NeighborParams.EDGE_COUNT:
		out.append({
			"name": neighbor_name(edge),
			"edge": edge,
			"edge_name": NeighborParams.EDGE_NAMES[edge],
			"population": _ctx.stats.neighbor_populations[edge],
			"output": _output[edge],
			"connected": _connections[edge].duplicate(),
			"trade": _trade_by_edge[edge],
		})
	return out


## Connection flags per edge, indexed like neighbor_populations.
func connections() -> Array[Dictionary]:
	return _connections.duplicate(true)


## Number of road and rail links to neighbors across all edges.
func link_count() -> int:
	var n := 0
	for c in _connections:
		if bool(c["road"]):
			n += 1
		if bool(c["rail"]):
			n += 1
	return n


## Commercial and industrial demand added each month by road and rail links:
## trade needs a way out of town. Read by the zone system.
func trade_demand_bonus() -> int:
	return mini(link_count() * NeighborParams.DEMAND_PER_LINK, NeighborParams.LINK_DEMAND_CAP)


func has_utility_link(utility: StringName) -> bool:
	for c in _connections:
		if bool(c.get(utility, false)):
			return true
	return false


## The player accepted a link of `kind` (road, rail, power or water) on
## `edge`. The border tile has just been built, so the flag is set at once
## and the newspaper hears about it; the monthly scan keeps it current.
func record_connection(edge: int, kind: StringName) -> void:
	if edge < 0 or edge >= NeighborParams.EDGE_COUNT or not _connections[edge].has(kind):
		return
	_connections[edge][kind] = true
	if _ctx != null:
		_ctx.events.report(&"neighbor_connection", {"name": neighbor_name(edge), "edge": edge, "kind": String(kind)}, 2)


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	var conns: Array = []
	for c in _connections:
		conns.append(c.duplicate())
	return {
		"founded": _founded,
		"names": Array(_name_index),
		"output": Array(_output),
		"connections": conns,
		"trade_twelfths": _trade_twelfths,
		"trade_by_edge": Array(_trade_by_edge),
	}


func load(data: Dictionary) -> void:
	_founded = bool(data.get("founded", _founded))
	var names: Array = data.get("names", Array(_name_index))
	var output: Array = data.get("output", Array(_output))
	var trade: Array = data.get("trade_by_edge", Array(_trade_by_edge))
	for edge in NeighborParams.EDGE_COUNT:
		if edge < names.size():
			_name_index[edge] = int(names[edge])
		if edge < output.size():
			_output[edge] = int(output[edge])
		if edge < trade.size():
			_trade_by_edge[edge] = int(trade[edge])
	var conns: Array = data.get("connections", [])
	for edge in mini(conns.size(), NeighborParams.EDGE_COUNT):
		var c: Dictionary = conns[edge]
		for flag in ["road", "rail", "power", "water"]:
			_connections[edge][flag] = bool(c.get(flag, false))
	_trade_twelfths = int(data.get("trade_twelfths", 0))


# ── Rules ────────────────────────────────────────────────────────────────

static func _has_region(stats: CityStats) -> bool:
	for p in stats.neighbor_populations:
		if p > 0:
			return true
	return false


func _found(ctx: SimContext) -> void:
	var pool: Array[int] = []
	for i in NeighborParams.NAME_POOL.size():
		pool.append(i)
	for edge in NeighborParams.EDGE_COUNT:
		var pick := ctx.rng.below(pool.size())
		_name_index[edge] = pool[pick]
		pool.remove_at(pick)
		var population := NeighborParams.FOUNDING_MIN + ctx.rng.below(NeighborParams.FOUNDING_SPREAD)
		for _roll in 2:
			population = mini(population, NeighborParams.FOUNDING_MIN + ctx.rng.below(NeighborParams.FOUNDING_SPREAD))
		ctx.stats.neighbor_populations[edge] = population
		_output[edge] = population / (1 + ctx.rng.below(NeighborParams.OUTPUT_DIVISOR_SPREAD))
	_founded = true


func _grow(ctx: SimContext) -> void:
	var phase := clampi(ctx.stats.economy_phase, 0, 3)
	var populations := ctx.stats.neighbor_populations
	var grew: Array[int] = []
	for edge in NeighborParams.EDGE_COUNT:
		var population := populations[edge]
		if population <= 0:
			continue
		var links := 0
		if bool(_connections[edge]["road"]):
			links += 1
		if bool(_connections[edge]["rail"]):
			links += 1
		var rate := phase + ctx.rng.below(NeighborParams.GROWTH_JITTER) + links * NeighborParams.LINK_GROWTH_BONUS
		var change := population * rate / NeighborParams.GROWTH_DIVISOR
		if change == 0:
			change = ctx.rng.below(2)
		var before := population
		if population > NeighborParams.POPULATION_CEILING:
			population -= change
		else:
			population += change
		populations[edge] = maxi(population, 0)
		if populations[edge] > before:
			grew.append(edge)
		for milestone: int in NeighborParams.GROWTH_NEWS_MILESTONES:
			if before < milestone and populations[edge] >= milestone:
				ctx.events.report(&"neighbor_growth", {"place": neighbor_name(edge), "count": milestone, "edge": edge})
		var output := _output[edge]
		var output_rate: int = NeighborParams.PHASE_OUTPUT_RATE[phase] + ctx.rng.below(NeighborParams.OUTPUT_JITTER)
		var output_change := output * output_rate / NeighborParams.GROWTH_DIVISOR
		if output > NeighborParams.OUTPUT_CEILING:
			output -= output_change
		else:
			output += output_change
		_output[edge] = maxi(output, 0)
	ctx.stats.neighbor_populations = populations
	# Now and then the paper prints a note from a growing neighbor.
	if not grew.is_empty() and ctx.rng.chance(1, NeighborParams.NEWS_CHANCE_DENOMINATOR):
		var edge: int = grew[ctx.rng.below(grew.size())]
		ctx.events.report(&"neighbor_news", {"place": neighbor_name(edge), "edge": edge})
	if ctx.rng.chance(1, NeighborParams.SHOCK_CHANCE_DENOMINATOR):
		var edge := ctx.rng.below(NeighborParams.EDGE_COUNT)
		populations[edge] = populations[edge] * NeighborParams.SHOCK_POPULATION_PERCENT / 100
		_output[edge] = _output[edge] * NeighborParams.SHOCK_OUTPUT_PERCENT / 100
		ctx.stats.neighbor_populations = populations
		ctx.events.report(&"neighbor_shock", {"name": neighbor_name(edge), "edge": edge})


func _trade(ctx: SimContext) -> void:
	var stats := ctx.stats
	var yearly_cents := 0
	yearly_cents += _utility_trade_cents(&"power", stats.power_capacity, stats.power_demand)
	yearly_cents += _utility_trade_cents(&"water", stats.water_capacity, stats.water_demand)
	_trade_twelfths += yearly_cents
	var dollars := _trade_twelfths / BudgetSystem.TWELFTH_CENTS_PER_DOLLAR
	stats.ledger[TRADE_KEY] = dollars
	# Spread this year's balance over the connected edges for the report.
	var connected: Array[int] = []
	for edge in NeighborParams.EDGE_COUNT:
		if bool(_connections[edge]["power"]) or bool(_connections[edge]["water"]):
			connected.append(edge)
	_trade_by_edge.fill(0)
	if not connected.is_empty():
		var share := dollars / connected.size()
		for edge in connected:
			_trade_by_edge[edge] = share
		_trade_by_edge[connected[0]] += dollars - share * connected.size()


## Yearly cents earned (positive) or owed (negative) for one utility.
func _utility_trade_cents(utility: StringName, capacity: int, demand: int) -> int:
	if not has_utility_link(utility):
		return 0
	var surplus := capacity - demand
	if surplus >= 0:
		return mini(surplus, NeighborParams.TRADE_UNIT_CAP) * int(NeighborParams.EXPORT_CENTS[utility])
	return surplus * int(NeighborParams.IMPORT_CENTS[utility])


## Which networks reach each edge of the map.
func _scan_connections(city: City) -> void:
	for edge in NeighborParams.EDGE_COUNT:
		var c := _connections[edge]
		c["road"] = false
		c["rail"] = false
		c["power"] = false
		c["water"] = false
	var last := City.WIDTH - 1
	for i in City.WIDTH:
		_scan_tile(city, i, 0, _connections[NeighborParams.EDGE_NORTH])
		_scan_tile(city, last, i, _connections[NeighborParams.EDGE_EAST])
		_scan_tile(city, i, last, _connections[NeighborParams.EDGE_SOUTH])
		_scan_tile(city, 0, i, _connections[NeighborParams.EDGE_WEST])


func _scan_tile(city: City, x: int, y: int, flags: Dictionary) -> void:
	var id := city.building.at(x, y)
	if id != Buildings.NONE:
		if Buildings.is_road_like(id):
			flags["road"] = true
		if Buildings.is_rail_like(id):
			flags["rail"] = true
		if Buildings.is_network(id) and Buildings.carries_power(id):
			flags["power"] = true
	if city.conducts_power(x, y):
		flags["power"] = true
	if city.conducts_water(x, y) or city.underground.at(x, y) != 0:
		flags["water"] = true
