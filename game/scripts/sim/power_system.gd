# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Power generation, distribution and plant lifetime. See docs/simulation/power.md.
##
## Conduction bits combine the building layer with unchanged imported links each time the system
## runs; plants seed a flood fill through them and spend their tile budget on
## the consumers they reach. Plants age at year end and retire past their
## lifetime. Every pass walks the packed layers with a running index and
## classifies tiles through the per-id tables in UtilityParams, so a full-map
## pass costs a few milliseconds.
class_name PowerSystem
extends SimSystem

const Params := preload("res://scripts/sim/data/utility_params.gd")

const W := City.WIDTH
const H := City.HEIGHT
const N := W * H

## Result of the last distribution, for the UI.
var _summary: Dictionary = {}
var _shortage := false
var _consumed := 0

## Scratch buffers reused by every pass.
## Tiles supplied by the plant anchored at each tile, 0 elsewhere.
var _generation := PackedInt32Array()
## Fill marks and the fill queue; a network is a slice of the queue.
var _visited := PackedByteArray()
var _queue := PackedInt32Array()
## Every tile of every plant and every plant anchor, as column-major keys.
var _plant_tiles := PackedInt32Array()
var _plant_anchors := PackedInt32Array()
## Anchor tiles of consumer buildings.
var _consumers := PackedInt32Array()


func _init() -> void:
	key = &"power"
	_generation.resize(N)
	_visited.resize(N)
	_queue.resize(N)


# ── Lifecycle ────────────────────────────────────────────────────────────

func setup(ctx: SimContext) -> void:
	_refresh_conduction(ctx.city, Rect2i(0, 0, W, H))
	_distribute(ctx)


## A native save already owns generation and supply. Rebuild the UI/scratch
## caches from those fields without drawing a new gust, redistributing power,
## registering plants or changing the saved city. Missing power runtime data
## continues through ordinary setup instead.
func setup_from_save(ctx: SimContext, data: Dictionary) -> void:
	self.load(data)
	var city := ctx.city
	var bld := city.building.data
	var flags := city.flags.data
	var zn := city.zone.data
	var plant_tbl := Params.power_plant_table()
	var draws := Params.draws_power_table()
	var multi := Params.multi_tile_table()
	_plant_tiles.resize(0)
	_plant_anchors.resize(0)
	_consumers.resize(0)
	_generation.fill(0)
	var total_demand := 0
	# Column order matches the plant ordering used by normal distribution.
	for x in W:
		for y in H:
			var i := y * W + x
			var id := bld[i]
			if draws[id] != 0:
				total_demand += Params.LOAD_PER_TILE
				if multi[id] == 0 or Params.is_anchor_tile(bld, zn, i):
					_consumers.append(i)
			elif plant_tbl[id] != 0:
				_plant_tiles.append(x * H + y)
				if multi[id] == 0 or Params.is_anchor_tile(bld, zn, i):
					_plant_anchors.append(x * H + y)
	var total_capacity := 0
	var plants: Array = []
	for k in _plant_anchors:
		@warning_ignore("integer_division")
		var a := Vector2i(k / H, k % H)
		var i := a.y * W + a.x
		var id := bld[i]
		var rec: Dictionary = city.facility(a)
		var capacity := int(rec.get("capacity", 0))
		_generation[i] = capacity
		total_capacity += capacity
		plants.append({"anchor": a, "key": Buildings.key(id), "name": Buildings.display_name(id),
			"age_years": int(rec.get("age_years", 0)), "capacity": capacity,
			"powered": (flags[i] & TileFlags.POWERED) != 0})
	var usage := 100
	if total_capacity > 0:
		@warning_ignore("integer_division")
		usage = mini(100, _consumed * 100 / total_capacity)
	_summary = {"capacity": total_capacity, "demand": total_demand, "consumed": _consumed,
		"usage_percent": usage, "shortage": _shortage,
		"unpowered_buildings": _count_unserved(bld, flags), "plants": plants}


func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_refresh_conduction(ctx.city, Rect2i(0, 0, W, H))
	_distribute(ctx)


func networks_changed(ctx: SimContext, rect: Rect2i) -> void:
	_refresh_conduction(ctx.city, rect)
	_distribute(ctx)


func yearly(ctx: SimContext) -> void:
	_age_plants(ctx)


func save() -> Dictionary:
	return {"shortage": _shortage, "consumed": _consumed}


func load(data: Dictionary) -> void:
	_shortage = bool(data.get("shortage", false))
	_consumed = int(data.get("consumed", 0))


# ── Public getters ───────────────────────────────────────────────────────

## Last distribution: capacity, demand, consumed, usage_percent, shortage and
## a `plants` array of {anchor, key, name, age_years, capacity, powered}.
func network_summary() -> Dictionary:
	return _summary.duplicate(true)


func is_shortage() -> bool:
	return _shortage


func consumed() -> int:
	return _consumed


func usage_percent() -> int:
	return int(_summary.get("usage_percent", 100))


## Generation of the plant anchored at `anchor` in the last pass, 0 if none.
func plant_capacity(anchor: Vector2i) -> int:
	for p in _summary.get("plants", []):
		if p.get("anchor", Vector2i(-1, -1)) == anchor:
			return int(p.get("capacity", 0))
	return 0


# ── Conduction flags ─────────────────────────────────────────────────────

## Rule 1: the conduction bit follows the building layer inside `rect`.
## Zoned land carries power on its own: one line touching a block is enough
## for the whole block, even before anything is built on it.
func _refresh_conduction(city: City, rect: Rect2i) -> void:
	var r := rect.intersection(Rect2i(0, 0, W, H))
	var flags := city.flags.data
	var bld := city.building.data
	var zn := city.zone.data
	var conducts := Params.conducts_power_table()
	var open := Params.open_ground_table()
	# has_imported_power_link() is false without side effects for an index the
	# link table lacks; only listed indices need its signature check.
	var links: Dictionary = city.imported_power_links
	for y in range(r.position.y, r.end.y):
		var i := y * W + r.position.x
		for _x in r.size.x:
			var id := bld[i]
			var imported_link := links.has(i) and city.has_imported_power_link(i)
			if imported_link or conducts[id] != 0 or (open[id] != 0 and (zn[i] & Zones.KIND_MASK) != 0):
				flags[i] |= TileFlags.CONDUCTS_POWER
			else:
				flags[i] &= ~TileFlags.CONDUCTS_POWER
			i += 1
	city.flags.data = flags


# ── Facility records ─────────────────────────────────────────────────────

## Rule 9: every plant anchor has a record. Called for each anchor in scan order.
func _register_plant(city: City, a: Vector2i, id: int) -> void:
	var k := Buildings.key(id)
	var rec: Dictionary = city.facility(a)
	if rec.is_empty() or rec.get("key", &"") != k:
		city.add_facility(a, {"key": k, "built_day": city.day, "age_years": 0,
			"capacity": 0, "warned": false})
		return
	if not rec.has("age_years"):
		rec["age_years"] = 0
	if not rec.has("built_day"):
		rec["built_day"] = city.day
	if not rec.has("warned"):
		rec["warned"] = false


## Rule 9: stale plant records are dropped.
func _drop_stale_plants(city: City) -> void:
	for a in city.facilities.keys():
		var rec: Dictionary = city.facilities[a]
		var id := Buildings.id_of(rec.get("key", &""))
		if Buildings.is_power_plant(id) and city.building_at(a.x, a.y) != id:
			city.facilities.erase(a)


# ── Generation ───────────────────────────────────────────────────────────

## Rule 3: tiles a plant supplies this month.
func _generation_of(ctx: SimContext, anchor: Vector2i, id: int, rain: int, wind: int) -> int:
	var k := Buildings.key(id)
	if Params.PLANT_OUTPUT.has(k):
		return int(Params.PLANT_OUTPUT[k])
	match id:
		Buildings.HYDRO_PLANT_A, Buildings.HYDRO_PLANT_B:
			if ctx.city.terrain.at(anchor.x, anchor.y) == Terrain.WATERFALL:
				return Params.HYDRO_OUTPUT
			return 0
		Buildings.WIND_PLANT:
			@warning_ignore("integer_division")
			var gust := ctx.rng.below(wind / Params.WIND_DIVISOR + 1)
			@warning_ignore("integer_division")
			return (ctx.city.ground_height(anchor.x, anchor.y) + gust) / 2
		Buildings.SOLAR_PLANT:
			@warning_ignore("integer_division")
			var spread := (100 - rain) / Params.SOLAR_RAIN_DIVISOR
			var total := 0
			for _i in Params.SOLAR_TILES:
				total += Params.SOLAR_BASE + ctx.rng.below(spread)
			return total
	return 0


# ── Distribution ─────────────────────────────────────────────────────────

func _distribute(ctx: SimContext) -> void:
	var city := ctx.city
	var flags := city.flags.data
	var bld := city.building.data
	var zn := city.zone.data
	var plant_tbl := Params.power_plant_table()
	var draws := Params.draws_power_table()
	var multi := Params.multi_tile_table()
	var rain := Params.weather(ctx, &"precipitation", Params.DEFAULT_RAIN)
	var wind := Params.weather(ctx, &"wind_speed", Params.DEFAULT_WIND)
	var conservation := bool(ctx.stats.ordinances.get(Params.CONSERVATION_ORDINANCE, false))

	# One pass over the map: drop last month's supply, total the load (rule 2)
	# and collect plant tiles, plant anchors and consumer anchors.
	_plant_tiles.resize(0)
	_plant_anchors.resize(0)
	_consumers.resize(0)
	var total_demand := 0
	var i := 0
	for y in H:
		for x in W:
			var f := flags[i]
			if (f & TileFlags.POWERED) != 0:
				flags[i] = f & ~TileFlags.POWERED
			var id := bld[i]
			if id != Buildings.NONE:
				if draws[id] != 0:
					total_demand += Params.LOAD_PER_TILE
					if multi[id] == 0 or Params.is_anchor_tile(bld, zn, i):
						_consumers.append(i)
				elif plant_tbl[id] != 0:
					_plant_tiles.append(x * H + y)
					if multi[id] == 0 or Params.is_anchor_tile(bld, zn, i):
						_plant_anchors.append(x * H + y)
						_register_plant(city, Vector2i(x, y), id)
			i += 1
	_drop_stale_plants(city)

	# Generation per plant anchor (rule 3), column by column so random draws
	# happen in a fixed order.
	_generation.fill(0)
	_plant_anchors.sort()
	var total_capacity := 0
	for k in _plant_anchors:
		@warning_ignore("integer_division")
		var a := Vector2i(k / H, k % H)
		var ai := a.y * W + a.x
		var g := _generation_of(ctx, a, bld[ai], rain, wind)
		_generation[ai] = g
		total_capacity += g
		var rec: Dictionary = city.facility(a)
		if not rec.is_empty():
			rec["capacity"] = g

	# Networks (rules 4 to 6): each plant seeds the fill of its network once.
	_visited.fill(0)
	_plant_tiles.sort()
	var tail := 0
	var consumed := 0
	var short := false
	for k in _plant_tiles:
		@warning_ignore("integer_division")
		var seed := (k % H) * W + k / H
		if _visited[seed] != 0 or (flags[seed] & TileFlags.CONDUCTS_POWER) == 0:
			continue
		var start := tail
		tail = _flood(seed, flags, tail)
		var capacity := 0
		var demand := 0
		for q in range(start, tail):
			var t := _queue[q]
			var id := bld[t]
			if plant_tbl[id] != 0:
				capacity += _generation[t]
			elif draws[id] != 0:
				demand += Params.LOAD_PER_TILE
		var budget := capacity
		if conservation:
			@warning_ignore("integer_division")
			budget += capacity / Params.CONSERVATION_BONUS_DIVISOR
		if demand > budget:
			short = true
		consumed += mini(demand, budget)
		for q in range(start, tail):
			var t := _queue[q]
			var id := bld[t]
			if plant_tbl[id] != 0:
				flags[t] |= TileFlags.POWERED
			elif budget > 0:
				flags[t] |= TileFlags.POWERED
				if draws[id] != 0:
					budget -= Params.LOAD_PER_TILE
	city.flags.data = flags

	# Reporting (rule 7).
	var unpowered := _count_unserved(bld, flags)
	ctx.stats.power_capacity = total_capacity
	ctx.stats.power_demand = total_demand
	ctx.stats.unpowered_buildings = unpowered
	_consumed = consumed
	var usage := 100
	if total_capacity > 0:
		@warning_ignore("integer_division")
		usage = mini(100, consumed * 100 / total_capacity)
	var plants: Array = []
	for k in _plant_anchors:
		@warning_ignore("integer_division")
		var a := Vector2i(k / H, k % H)
		var ai := a.y * W + a.x
		var rec: Dictionary = city.facility(a)
		var id := bld[ai]
		plants.append({"anchor": a, "key": Buildings.key(id), "name": Buildings.display_name(id),
			"age_years": int(rec.get("age_years", 0)), "capacity": _generation[ai],
			"powered": (flags[ai] & TileFlags.POWERED) != 0})
	_summary = {"capacity": total_capacity, "demand": total_demand, "consumed": consumed,
		"usage_percent": usage, "shortage": short, "unpowered_buildings": unpowered, "plants": plants}
	if short and not _shortage:
		ctx.events.report(&"power_shortage", {"unpowered": unpowered, "demand": total_demand,
			"capacity": total_capacity})
	elif _shortage and not short:
		ctx.events.report(&"power_restored", {})
	_shortage = short


## Breadth-first fill through conducting tiles from `seed`, neighbours north,
## west, south, east. Appends the tiles reached to `_queue` from `tail` on,
## in fill order, and returns the new tail.
func _flood(seed: int, flags: PackedByteArray, tail: int) -> int:
	var head := tail
	_queue[tail] = seed
	tail += 1
	_visited[seed] = 1
	while head < tail:
		var i := _queue[head]
		head += 1
		var x := i % W
		if i >= W:
			var j := i - W
			if _visited[j] == 0 and (flags[j] & TileFlags.CONDUCTS_POWER) != 0:
				_visited[j] = 1
				_queue[tail] = j
				tail += 1
		if x > 0:
			var j := i - 1
			if _visited[j] == 0 and (flags[j] & TileFlags.CONDUCTS_POWER) != 0:
				_visited[j] = 1
				_queue[tail] = j
				tail += 1
		if i + W < N:
			var j := i + W
			if _visited[j] == 0 and (flags[j] & TileFlags.CONDUCTS_POWER) != 0:
				_visited[j] = 1
				_queue[tail] = j
				tail += 1
		if x + 1 < W:
			var j := i + 1
			if _visited[j] == 0 and (flags[j] & TileFlags.CONDUCTS_POWER) != 0:
				_visited[j] = 1
				_queue[tail] = j
				tail += 1
	return tail


## Consumer buildings with no powered tile in their footprint.
func _count_unserved(bld: PackedByteArray, flags: PackedByteArray) -> int:
	var widths := Params.footprint_width_table()
	var heights := Params.footprint_height_table()
	var unserved := 0
	for a in _consumers:
		var id := bld[a]
		var w := widths[id]
		var h := heights[id]
		var served := false
		var row := a
		for _dy in h:
			for dx in w:
				var t := row + dx
				if t < N and (flags[t] & TileFlags.POWERED) != 0:
					served = true
			row += W
		if not served:
			unserved += 1
	return unserved


# ── Aging (rule 8) ───────────────────────────────────────────────────────

func _age_plants(ctx: SimContext) -> void:
	var city := ctx.city
	for a in city.facilities.keys():
		var rec: Dictionary = city.facilities[a]
		var k: StringName = rec.get("key", &"")
		var id := Buildings.id_of(k)
		if not Buildings.is_power_plant(id) or city.building_at(a.x, a.y) != id:
			continue
		if not Params.ages(k):
			continue
		var age := int(rec.get("age_years", 0)) + 1
		rec["age_years"] = age
		var args := {"key": k, "name": Buildings.display_name(id), "anchor": a, "age_years": age}
		if age > Params.PLANT_LIFETIME_YEARS:
			_retire(ctx, a, id, rec, args)
		elif age > Params.PLANT_WARNING_YEARS and not bool(rec.get("warned", false)):
			rec["warned"] = true
			ctx.events.report(&"plant_aging", args)
	# Keep the UI summary current until the next distribution.
	var plants: Array = _summary.get("plants", [])
	for p in plants:
		var rec: Dictionary = city.facility(p.get("anchor", Vector2i(-1, -1)))
		p["age_years"] = int(rec.get("age_years", 0))


func _retire(ctx: SimContext, anchor: Vector2i, id: int, rec: Dictionary, args: Dictionary) -> void:
	var city := ctx.city
	var cost := Buildings.cost(id)
	if not ctx.stats.disasters_enabled and city.funds >= cost:
		city.funds -= cost
		rec["age_years"] = 0
		rec["warned"] = false
		rec["built_day"] = city.day
		args["cost"] = cost
		ctx.events.report(&"plant_replaced", args)
		return
	var rect := city.clear_footprint(anchor.x, anchor.y)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if city.is_flat(x, y) and not city.is_water(x, y):
				city.building.put(x, y, Buildings.RUBBLE_1 + ctx.rng.below(4))
			city.set_flag(x, y, TileFlags.CONDUCTS_POWER | TileFlags.POWERED
				| TileFlags.CONDUCTS_WATER | TileFlags.WATERED, false)
	ctx.events.report(&"plant_retired", args, 2)
	ctx.events.notify(&"plant_retired", args)
	ctx.events.mark_dirty(rect)
