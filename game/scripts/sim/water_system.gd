# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Water supply, storage, treatment and distribution. See docs/simulation/water.md.
##
## Conduction bits are derived from the underground and building layers every
## time the system runs. Powered pumps and desalination plants, and towers that
## hold water, seed a flood fill that serves the consumers it reaches; surplus
## refills towers. Tower contents are recorded in the WATERED bit of tower tiles.
## Every pass walks the packed layers with a running index and classifies
## tiles through the per-id tables in UtilityParams.
class_name WaterSystem
extends SimSystem

const Params := preload("res://scripts/sim/data/utility_params.gd")

const W := City.WIDTH
const H := City.HEIGHT
const N := W * H

## Result of the last distribution, for the UI.
var _summary: Dictionary = {}
var _shortage := false
var _consumed := 0
var _treatment_adequate := true

## Scratch buffers reused by every pass.
## Units produced by the source anchored at each tile, 0 elsewhere.
var _output := PackedInt32Array()
## Fill marks and the fill queue; a network is a slice of the queue.
var _visited := PackedByteArray()
var _queue := PackedInt32Array()
## Source anchors and tower tiles, as column-major keys; only these can seed.
var _seeds := PackedInt32Array()
## Every tile of every tower, for the storage count.
var _tower_tiles := PackedInt32Array()
## Anchor tiles of consumer buildings.
var _consumers := PackedInt32Array()
## Stats of a city set up from a save, until load() completes the summary.
var _restored_stats: CityStats = null


func _init() -> void:
	key = &"water"
	_output.resize(N)
	_visited.resize(N)
	_queue.resize(N)


# ── Lifecycle ────────────────────────────────────────────────────────────

func setup(ctx: SimContext) -> void:
	_refresh_conduction(ctx.city, Rect2i(0, 0, W, H))
	if ctx.city.restored_layers.has("flags"):
		# A saved city keeps the service and tower contents it was saved with
		# until the next scheduled pass; distributing now would use weather the
		# environment has not restored yet.
		_restored_stats = ctx.stats
		_summarize_saved(ctx.city, ctx.stats)
	else:
		_restored_stats = null
		_distribute(ctx)


func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_refresh_conduction(ctx.city, Rect2i(0, 0, W, H))
	_distribute(ctx)


func networks_changed(ctx: SimContext, rect: Rect2i) -> void:
	_refresh_conduction(ctx.city, rect)
	_distribute(ctx)


func save() -> Dictionary:
	return {"shortage": _shortage, "consumed": _consumed, "treatment_adequate": _treatment_adequate}


func load(data: Dictionary) -> void:
	_shortage = bool(data.get("shortage", false))
	_consumed = int(data.get("consumed", 0))
	_treatment_adequate = bool(data.get("treatment_adequate", true))
	if _restored_stats != null and not _summary.is_empty():
		# The saved stats are restored before the systems load.
		var capacity := maxi(0, _restored_stats.water_capacity)
		_summary["capacity"] = capacity
		_summary["demand"] = _restored_stats.water_demand
		_summary["unwatered_buildings"] = _restored_stats.unwatered_buildings
		_summary["stored"] = _restored_stats.water_stored
		_summary["storage_capacity"] = _restored_stats.water_storage_capacity
		_summary["consumed"] = _consumed
		@warning_ignore("integer_division")
		_summary["usage_percent"] = mini(100, _consumed * 100 / capacity) if capacity > 0 else 100
		_summary["shortage"] = _shortage
		_summary["treatment_adequate"] = _treatment_adequate
	_restored_stats = null


# ── Public getters ───────────────────────────────────────────────────────

## Last distribution: capacity, demand, consumed, usage_percent, shortage,
## stored, storage_capacity, treatment_adequate and a `facilities` array of
## {anchor, key, name, output, stored, powered}.
func network_summary() -> Dictionary:
	return _summary.duplicate(true)


func is_shortage() -> bool:
	return _shortage


func consumed() -> int:
	return _consumed


## True when the treatment plants can clean what the city consumes; the
## environment system uses it to soften pollution.
func treatment_adequate() -> bool:
	return _treatment_adequate


func usage_percent() -> int:
	return int(_summary.get("usage_percent", 100))


# ── Conduction flags ─────────────────────────────────────────────────────

## Rule 1: the conduction bit follows the underground and building layers.
func _refresh_conduction(city: City, rect: Rect2i) -> void:
	var r := rect.intersection(Rect2i(0, 0, W, H))
	var flags := city.flags.data
	var bld := city.building.data
	var ug := city.underground.data
	var codes := Params.conducts_water_code_table()
	var conducts := Params.conducts_water_table()
	for y in range(r.position.y, r.end.y):
		var i := y * W + r.position.x
		for _x in r.size.x:
			if codes[ug[i]] != 0 or conducts[bld[i]] != 0:
				flags[i] |= TileFlags.CONDUCTS_WATER
			else:
				flags[i] &= ~TileFlags.CONDUCTS_WATER
			i += 1
	city.flags.data = flags


# ── Facility records ─────────────────────────────────────────────────────

## Rule 9: every water facility anchor has a record. Called in scan order.
func _register_facility(city: City, a: Vector2i, id: int) -> Dictionary:
	var k := Buildings.key(id)
	var rec: Dictionary = city.facility(a)
	if rec.is_empty() or rec.get("key", &"") != k:
		rec = {"key": k, "built_day": city.day, "output": 0, "stored": 0}
		city.add_facility(a, rec)
		return rec
	if not rec.has("built_day"):
		rec["built_day"] = city.day
	return rec


## Rule 9: stale facility records are dropped.
func _drop_stale_facilities(city: City) -> void:
	for a in city.facilities.keys():
		var rec: Dictionary = city.facilities[a]
		var id := Buildings.id_of(rec.get("key", &""))
		if Params.is_water_facility(id) and city.building_at(a.x, a.y) != id:
			city.facilities.erase(a)


# ── Sources (rule 3) ─────────────────────────────────────────────────────

func _pump_output(city: City, anchor: Vector2i, rain: int) -> int:
	var table := city.sea_level if city.sea_level >= 0 else Params.DEFAULT_WATER_TABLE
	@warning_ignore("integer_division")
	var out := Params.WATER_TABLE_FACTOR * table + rain / Params.RAIN_DIVISOR
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var x := anchor.x + dx
			var y := anchor.y + dy
			if city.in_bounds(x, y) and city.is_water(x, y) and not city.is_salt_water(x, y):
				out += Params.FRESH_NEIGHBOR_YIELD
	return out


func _desalination_output(city: City, anchor: Vector2i, id: int) -> int:
	var s := Buildings.size(id)
	var out := 0
	for y in range(anchor.y - 1, anchor.y + s.y + 1):
		for x in range(anchor.x - 1, anchor.x + s.x + 1):
			var inside := x >= anchor.x and x < anchor.x + s.x and y >= anchor.y and y < anchor.y + s.y
			if inside or not city.in_bounds(x, y):
				continue
			if city.is_water(x, y) and city.is_salt_water(x, y):
				out += Params.SALT_NEIGHBOR_YIELD
	return out


# ── Distribution ─────────────────────────────────────────────────────────

func _distribute(ctx: SimContext) -> void:
	var city := ctx.city
	var flags := city.flags.data
	var bld := city.building.data
	var zn := city.zone.data
	var draws := Params.draws_water_table()
	var facility_tbl := Params.water_facility_table()
	var multi := Params.multi_tile_table()
	var rain := Params.weather(ctx, &"precipitation", Params.DEFAULT_RAIN)

	# One pass over the map: drop last month's service (tower tiles keep their
	# WATERED bit, it is their contents), total the load, record facilities and
	# their output, and collect the tiles that may seed a network.
	_output.fill(0)
	_seeds.resize(0)
	_tower_tiles.resize(0)
	_consumers.resize(0)
	var total_demand := 0
	var treatment_plants := 0
	var storage_capacity := 0
	var i := 0
	for y in H:
		for x in W:
			var id := bld[i]
			if id == Buildings.WATER_TOWER:
				storage_capacity += Params.TOWER_UNITS_PER_TILE
				_tower_tiles.append(i)
				_seeds.append(x * H + y)
			elif (flags[i] & TileFlags.WATERED) != 0:
				flags[i] &= ~TileFlags.WATERED
			if id == Buildings.NONE:
				i += 1
				continue
			if draws[id] != 0:
				total_demand += Params.LOAD_PER_TILE
				if multi[id] == 0 or Params.is_anchor_tile(bld, zn, i):
					_consumers.append(i)
			elif facility_tbl[id] != 0 and (multi[id] == 0 or Params.is_anchor_tile(bld, zn, i)):
				var a := Vector2i(x, y)
				var rec := _register_facility(city, a, id)
				match id:
					Buildings.WATER_PUMP, Buildings.DESALINATION:
						var units := 0
						if (flags[i] & TileFlags.POWERED) != 0:
							units = _pump_output(city, a, rain) if id == Buildings.WATER_PUMP \
								else _desalination_output(city, a, id)
						_output[i] = units
						rec["output"] = units
						_seeds.append(x * H + y)
					Buildings.WATER_TREATMENT:
						treatment_plants += 1
			i += 1
	_drop_stale_facilities(city)

	# Networks (rules 4 to 6): sources and full towers seed the fill of their
	# network once, column by column.
	_visited.fill(0)
	_seeds.sort()
	var tail := 0
	var total_capacity := 0
	var consumed := 0
	var short := false
	for k in _seeds:
		@warning_ignore("integer_division")
		var seed := (k % H) * W + k / H
		if _visited[seed] != 0 or (flags[seed] & TileFlags.CONDUCTS_WATER) == 0:
			continue
		var is_source := _output[seed] > 0
		var is_full_tower := bld[seed] == Buildings.WATER_TOWER \
			and (flags[seed] & TileFlags.WATERED) != 0
		if not is_source and not is_full_tower:
			continue
		var start := tail
		tail = _flood(seed, flags, tail)
		var capacity := 0
		var demand := 0
		var storage := 0
		for q in range(start, tail):
			var t := _queue[q]
			var id := bld[t]
			if id == Buildings.WATER_TOWER:
				storage += Params.TOWER_UNITS_PER_TILE
				if (flags[t] & TileFlags.WATERED) != 0:
					capacity += Params.TOWER_UNITS_PER_TILE
					flags[t] &= ~TileFlags.WATERED
			elif facility_tbl[id] != 0:
				capacity += _output[t]
			elif draws[id] != 0:
				demand += Params.LOAD_PER_TILE
		var served := mini(demand, capacity)
		if demand > capacity:
			short = true
		total_capacity += capacity
		consumed += served
		@warning_ignore("integer_division")
		var refill := (mini(capacity - served, storage) + Params.TOWER_UNITS_PER_TILE / 2) \
			/ Params.TOWER_UNITS_PER_TILE
		var remaining := served
		for q in range(start, tail):
			var t := _queue[q]
			var id := bld[t]
			if id == Buildings.WATER_TOWER:
				if refill > 0 and (flags[t] & TileFlags.POWERED) != 0:
					flags[t] |= TileFlags.WATERED
					refill -= 1
			elif facility_tbl[id] != 0:
				if (flags[t] & TileFlags.POWERED) != 0:
					flags[t] |= TileFlags.WATERED
			elif remaining > 0:
				flags[t] |= TileFlags.WATERED
				if draws[id] != 0:
					remaining -= Params.LOAD_PER_TILE
	city.flags.data = flags

	# Reporting (rules 7 and 8).
	var stored := 0
	for t in _tower_tiles:
		if (flags[t] & TileFlags.WATERED) != 0:
			stored += Params.TOWER_UNITS_PER_TILE
	var unwatered := _count_unserved(bld, flags)
	_treatment_adequate = treatment_plants * Params.TREATMENT_COVERAGE >= consumed
	_consumed = consumed
	ctx.stats.water_capacity = total_capacity
	ctx.stats.water_demand = total_demand
	ctx.stats.unwatered_buildings = unwatered
	ctx.stats.water_stored = stored
	ctx.stats.water_storage_capacity = storage_capacity
	var usage := 100
	if total_capacity > 0:
		@warning_ignore("integer_division")
		usage = mini(100, consumed * 100 / total_capacity)
	var facilities: Array = []
	for a in city.facilities:
		var rec: Dictionary = city.facilities[a]
		var id := Buildings.id_of(rec.get("key", &""))
		if not Params.is_water_facility(id):
			continue
		var anchor: Vector2i = a
		var tower_units := 0
		if id == Buildings.WATER_TOWER:
			var s := Buildings.size(id)
			for dy in s.y:
				for dx in s.x:
					if (flags[(anchor.y + dy) * W + anchor.x + dx] & TileFlags.WATERED) != 0:
						tower_units += Params.TOWER_UNITS_PER_TILE
			rec["stored"] = tower_units
		facilities.append({"anchor": anchor, "key": rec.get("key", &""),
			"name": Buildings.display_name(id), "output": int(rec.get("output", 0)),
			"stored": tower_units,
			"powered": (flags[anchor.y * W + anchor.x] & TileFlags.POWERED) != 0})
	_summary = {"capacity": total_capacity, "demand": total_demand, "consumed": consumed,
		"usage_percent": usage, "shortage": short, "unwatered_buildings": unwatered,
		"stored": stored, "storage_capacity": storage_capacity,
		"treatment_adequate": _treatment_adequate, "facilities": facilities}
	if short and not _shortage:
		ctx.events.report(&"water_shortage", {"unwatered": unwatered, "demand": total_demand,
			"capacity": total_capacity})
	elif _shortage and not short:
		ctx.events.report(&"water_restored", {})
	_shortage = short


## Rebuild the summary of a saved city from its saved flags and facility
## records without serving, draining or refilling anything. load() then puts
## back the saved totals, which the last pass computed before later growth.
func _summarize_saved(city: City, stats: CityStats) -> void:
	var flags := city.flags.data
	var bld := city.building.data
	var zn := city.zone.data
	var draws := Params.draws_water_table()
	var multi := Params.multi_tile_table()
	_consumers.resize(0)
	var total_demand := 0
	var storage_capacity := 0
	var stored := 0
	var i := 0
	for y in H:
		for x in W:
			var id := bld[i]
			if id == Buildings.WATER_TOWER:
				storage_capacity += Params.TOWER_UNITS_PER_TILE
				if (flags[i] & TileFlags.WATERED) != 0:
					stored += Params.TOWER_UNITS_PER_TILE
			elif id != Buildings.NONE and draws[id] != 0:
				total_demand += Params.LOAD_PER_TILE
				if multi[id] == 0 or Params.is_anchor_tile(bld, zn, i):
					_consumers.append(i)
			i += 1
	var unwatered := _count_unserved(bld, flags)
	var facilities: Array = []
	for a in city.facilities:
		var rec: Dictionary = city.facilities[a]
		var id := Buildings.id_of(rec.get("key", &""))
		if not Params.is_water_facility(id) or city.building_at(a.x, a.y) != id:
			continue
		var anchor: Vector2i = a
		var tower_units := 0
		if id == Buildings.WATER_TOWER:
			var s := Buildings.size(id)
			for dy in s.y:
				for dx in s.x:
					var t := (anchor.y + dy) * W + anchor.x + dx
					if t < N and (flags[t] & TileFlags.WATERED) != 0:
						tower_units += Params.TOWER_UNITS_PER_TILE
		facilities.append({"anchor": anchor, "key": rec.get("key", &""),
			"name": Buildings.display_name(id), "output": int(rec.get("output", 0)),
			"stored": tower_units,
			"powered": (flags[anchor.y * W + anchor.x] & TileFlags.POWERED) != 0})
	var capacity := maxi(0, stats.water_capacity)
	@warning_ignore("integer_division")
	var usage := mini(100, _consumed * 100 / capacity) if capacity > 0 else 100
	_summary = {"capacity": capacity, "demand": total_demand, "consumed": _consumed,
		"usage_percent": usage, "shortage": _shortage, "unwatered_buildings": unwatered,
		"stored": stored, "storage_capacity": storage_capacity,
		"treatment_adequate": _treatment_adequate, "facilities": facilities}


## Breadth-first fill through water-conducting tiles from `seed`, neighbours
## north, west, south, east. Appends the tiles reached to `_queue` from
## `tail` on, in fill order, and returns the new tail.
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
			if _visited[j] == 0 and (flags[j] & TileFlags.CONDUCTS_WATER) != 0:
				_visited[j] = 1
				_queue[tail] = j
				tail += 1
		if x > 0:
			var j := i - 1
			if _visited[j] == 0 and (flags[j] & TileFlags.CONDUCTS_WATER) != 0:
				_visited[j] = 1
				_queue[tail] = j
				tail += 1
		if i + W < N:
			var j := i + W
			if _visited[j] == 0 and (flags[j] & TileFlags.CONDUCTS_WATER) != 0:
				_visited[j] = 1
				_queue[tail] = j
				tail += 1
		if x + 1 < W:
			var j := i + 1
			if _visited[j] == 0 and (flags[j] & TileFlags.CONDUCTS_WATER) != 0:
				_visited[j] = 1
				_queue[tail] = j
				tail += 1
	return tail


## Consumer buildings with no watered tile in their footprint.
func _count_unserved(bld: PackedInt32Array, flags: PackedByteArray) -> int:
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
				if t < N and (flags[t] & TileFlags.WATERED) != 0:
					served = true
			row += W
		if not served:
			unserved += 1
	return unserved
