# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Environment system: the pollution, land value and crime maps.
##
## Runs once a month and rewrites the three half-resolution quality maps from
## the buildings, terrain, traffic, density and police coverage on the map.
## Publishes the city-wide averages and the pollution/crime news events.
## One pass over the packed tile layers gathers everything the block maps
## need; the maps themselves are then computed on packed block buffers.
## Rules: docs/simulation/environment.md.
class_name EnvironmentSystem
extends SimSystem

const Params := preload("res://scripts/sim/data/environment_params.gd")

const W := City.WIDTH
const H := City.HEIGHT
const N := W * H
const BLOCKS := City.HALF
const CELLS := City.QUARTER
const BLOCK_COUNT := BLOCKS * BLOCKS
const CELL_COUNT := CELLS * CELLS

## Buildings that lift the value of land around them.
const CIVIC_ATTRACTIONS: Array[int] = [
	Buildings.LIBRARY, Buildings.MUSEUM, Buildings.MARINA, Buildings.ZOO,
	Buildings.CITY_HALL, Buildings.MONUMENT, Buildings.MAYORS_RESIDENCE,
]

var _pollution_total := 0
var _land_value_total := 0
var _crime_total := 0
var _developed_blocks := 0
var _pollution_alerted := false
var _crime_alerted := false

## Per-id and per-terrain-code tables, built once.
var _developed_tbl := PackedByteArray()      # building alone makes a tile developed
var _abandoned_tbl := PackedByteArray()
var _emission_tbl := PackedInt32Array()      # emission minus absorption per tile
var _emission_controls_tbl := PackedInt32Array()
var _amenity_tbl := PackedInt32Array()       # amenity of a built dry tile
var _open_water_tbl := PackedByteArray()     # by terrain code
var _flat_tbl := PackedByteArray()           # by terrain code

## Gathered by the tile pass, consumed by the block passes.
var _developed := PackedByteArray()          # per block
var _block_zone := PackedByteArray()         # first zone kind of each block
var _block_emission := PackedInt32Array()    # net emission of each block
var _amenity := PackedInt32Array()           # amenity per 4×4 cell
var _treatment_anchors := PackedInt32Array()
var _centre := Vector2i.ZERO
## Block scratch buffers.
var _work := PackedInt32Array()
var _bonus := PackedByteArray()
var _base := PackedInt32Array()


func _init() -> void:
	key = &"environment"
	_build_tables()
	_developed.resize(BLOCK_COUNT)
	_block_zone.resize(BLOCK_COUNT)
	_block_emission.resize(BLOCK_COUNT)
	_amenity.resize(CELL_COUNT)
	_work.resize(BLOCK_COUNT)
	_bonus.resize(BLOCK_COUNT)
	_base.resize(BLOCK_COUNT)


func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_scan_tiles(ctx)
	_update_pollution(ctx)
	_update_land_value(ctx)
	_update_crime(ctx)
	_publish(ctx)


# ── Getters ──────────────────────────────────────────────────────────────

## Sum of the pollution map over developed blocks.
func pollution_total() -> int:
	return _pollution_total


## Sum of the land value map over developed blocks.
func land_value_total() -> int:
	return _land_value_total


## Sum of the crime map over developed blocks.
func crime_total() -> int:
	return _crime_total


## Number of 2×2 blocks that hold a zone or a building.
func developed_blocks() -> int:
	return _developed_blocks


# ── Tables ───────────────────────────────────────────────────────────────

func _build_tables() -> void:
	_developed_tbl.resize(Buildings.COUNT)
	_abandoned_tbl.resize(Buildings.COUNT)
	_emission_tbl.resize(Buildings.COUNT)
	_emission_controls_tbl.resize(Buildings.COUNT)
	_amenity_tbl.resize(Buildings.COUNT)
	for id in Buildings.COUNT:
		_developed_tbl[id] = 1 if _building_is_developed(id) else 0
		_abandoned_tbl[id] = 1 if Buildings.is_abandoned(id) else 0
		_emission_tbl[id] = emission_of(id, false) - absorption_of(id)
		_emission_controls_tbl[id] = emission_of(id, true) - absorption_of(id)
		_amenity_tbl[id] = _building_amenity(id, Terrain.FLAT)
	_open_water_tbl.resize(256)
	_flat_tbl.resize(256)
	for code in 256:
		_open_water_tbl[code] = 1 if Terrain.is_open_water(code) else 0
		_flat_tbl[code] = 1 if Terrain.is_flat(code) else 0


## A building alone makes its tile developed: anything other than open
## ground, rubble, trees, parks or a power line.
static func _building_is_developed(id: int) -> bool:
	if id == Buildings.NONE or Buildings.is_rubble(id):
		return false
	var cat := Buildings.category(id)
	return cat != Buildings.Category.TREE and cat != Buildings.Category.POWER_LINE


## A tile counts as developed when it is zoned or carries anything other than
## open ground, rubble, trees, parks or a power line.
static func is_developed_tile(city: City, x: int, y: int) -> bool:
	if Zones.kind(city.zone.at(x, y)) != Zones.NONE:
		return true
	return _building_is_developed(city.building.at(x, y))


# ── Tile pass ────────────────────────────────────────────────────────────

## Walk every tile once: mark developed blocks, sum each block's emission,
## note each block's zone kind, sum amenity per 4×4 cell, locate treatment
## plants and find the city centre.
func _scan_tiles(ctx: SimContext) -> void:
	var city := ctx.city
	var bld := city.building.data
	var zn := city.zone.data
	var ter := city.terrain.data
	var alt := city.altitude.data
	var flags := city.flags.data
	var controls := bool(ctx.stats.ordinances.get(&"pollution_controls", false))
	var emission := _emission_controls_tbl if controls else _emission_tbl
	var sea := maxi(city.sea_level, 0)
	_developed.fill(0)
	_block_zone.fill(0)
	_block_emission.fill(0)
	_amenity.fill(0)
	_treatment_anchors.resize(0)
	var dense_x := 0
	var dense_y := 0
	var dense_count := 0
	var dev_x := 0
	var dev_y := 0
	var dev_count := 0
	var i := 0
	for y in H:
		var b := (y >> 1) * BLOCKS
		var q := (y >> 2) * CELLS
		for x in W:
			var id := bld[i]
			var kind := zn[i] & Zones.KIND_MASK
			var bi := b + (x >> 1)
			if kind != Zones.NONE or _developed_tbl[id] != 0:
				_developed[bi] = 1
				dev_x += x
				dev_y += y
				dev_count += 1
			if id != Buildings.NONE:
				_block_emission[bi] += emission[id]
				if kind == Zones.COM_HIGH:
					dense_x += x
					dense_y += y
					dense_count += 1
				if id == Buildings.WATER_TREATMENT and (zn[i] & Zones.CORNER_NW) != 0:
					# Each lot once, placed at its anchor: a city saved at another
					# rotation carries CORNER_NW on another corner of the lot.
					var a := City.footprint_anchor(bld, zn, x, y)
					_treatment_anchors.append(a.y * W + a.x)
			if kind != Zones.NONE and _block_zone[bi] == 0:
				_block_zone[bi] = kind
			var code := ter[i]
			var score := 0
			if _open_water_tbl[code] != 0:
				score = Params.AMENITY_WATER
			else:
				if id == Buildings.NONE:
					score = Params.AMENITY_OPEN_GROUND
					if _flat_tbl[code] == 0:
						score += Params.AMENITY_SLOPE
				else:
					score = _amenity_tbl[id]
				@warning_ignore("integer_division")
				score += mini(maxi((alt[i] & City.ALT_MASK) - sea, 0), Params.ALTITUDE_CAP) \
					/ Params.ALTITUDE_DIVISOR
			if (flags[i] & TileFlags.WATERED) != 0:
				score += Params.AMENITY_WATERED
			_amenity[q + (x >> 2)] += score
			i += 1
	var developed := 0
	for bi in BLOCK_COUNT:
		developed += _developed[bi]
	_developed_blocks = developed
	_centre = Vector2i(BLOCKS / 2, BLOCKS / 2)
	if dense_count > 0:
		_centre = Vector2i(dense_x / dense_count / 2, dense_y / dense_count / 2)
	elif dev_count > 0:
		_centre = Vector2i(dev_x / dev_count / 2, dev_y / dev_count / 2)


# ── Pollution ────────────────────────────────────────────────────────────

## Pollution emitted by one tile of a building, before absorption.
static func emission_of(id: int, controls: bool) -> int:
	if id == Buildings.CONTAMINATION:
		return Params.CONTAMINATION_EMISSION
	var cat := Buildings.category(id)
	var width := Buildings.size(id).x
	match cat:
		Buildings.Category.INDUSTRIAL:
			var base: int = Params.INDUSTRIAL_EMISSION.get(width, 0)
			if controls:
				@warning_ignore("integer_division")
				base -= base * Params.POLLUTION_CONTROLS_PERCENT / 100
			return base
		Buildings.Category.COMMERCIAL:
			return Params.COMMERCIAL_EMISSION.get(width, 0)
		Buildings.Category.PLANT:
			return Params.PLANT_EMISSION.get(Buildings.key(id), 0)
	var flat: int = Params.CATEGORY_EMISSION.get(cat, 0)
	if flat != 0:
		return flat
	return Params.SPECIAL_EMISSION.get(Buildings.key(id), 0)


## Pollution absorbed by one tile of greenery.
static func absorption_of(id: int) -> int:
	if Buildings.is_tree(id):
		return Params.TREE_ABSORPTION
	if id == Buildings.SMALL_PARK or id == Buildings.LARGE_PARK:
		return Params.PARK_ABSORPTION
	return 0


func _update_pollution(ctx: SimContext) -> void:
	var city := ctx.city
	var pollution := city.pollution.data
	var traffic := city.traffic.data
	var industry_modifier := 0
	var economy := ctx.system(&"economy")
	if economy != null and economy.has_method("pollution_modifier"):
		industry_modifier = int(economy.call("pollution_modifier"))
	var diffusion_divisor := maxi(1, Params.DIFFUSION_DIVISOR - industry_modifier)
	for bi in BLOCK_COUNT:
		@warning_ignore("integer_division")
		_work[bi] = maxi(pollution[bi] + traffic[bi] / Params.TRAFFIC_POLLUTION_DIVISOR
			+ _block_emission[bi], 0)
	_treatment_bonus(city)
	var total := 0
	var bi := 0
	for by in BLOCKS:
		for bx in BLOCKS:
			var numerator := _work[bi] * 2
			var denominator := diffusion_divisor + _bonus[bi]
			if bx > 0:
				numerator += _work[bi - 1]
				denominator += 1
			if bx < BLOCKS - 1:
				numerator += _work[bi + 1]
				denominator += 1
			if by > 0:
				numerator += _work[bi - BLOCKS]
				denominator += 1
			if by < BLOCKS - 1:
				numerator += _work[bi + BLOCKS]
				denominator += 1
			@warning_ignore("integer_division")
			var value := mini(255, numerator / denominator)
			pollution[bi] = value
			if _developed[bi] != 0:
				total += value
			bi += 1
	city.pollution.data = pollution
	_pollution_total = total


## Extra diffusion divisor per block from powered water treatment plants.
func _treatment_bonus(city: City) -> void:
	_bonus.fill(0)
	var flags := city.flags.data
	var s := Buildings.size(Buildings.WATER_TREATMENT)
	for t in _treatment_anchors:
		var ax := t % W
		@warning_ignore("integer_division")
		var ay := t / W
		if not _footprint_powered(flags, ax, ay, s):
			continue
		var cx := ax >> 1
		var cy := ay >> 1
		var r := Params.TREATMENT_RADIUS
		for by in range(maxi(0, cy - r), mini(BLOCKS, cy + r + 1)):
			for bx in range(maxi(0, cx - r), mini(BLOCKS, cx + r + 1)):
				if absi(bx - cx) + absi(by - cy) > r:
					continue
				var bi := by * BLOCKS + bx
				_bonus[bi] = mini(Params.TREATMENT_MAX_BONUS,
					_bonus[bi] + Params.TREATMENT_DIVISOR_BONUS)


# ── Land value ───────────────────────────────────────────────────────────

func _update_land_value(ctx: SimContext) -> void:
	var city := ctx.city
	var land_value := city.land_value.data
	var pollution := city.pollution.data
	var crime := city.crime.data
	var traffic := city.traffic.data
	var density := city.density.data
	var bld := city.building.data
	# Amenity is immutable during this pass; each coarse cell serves four blocks.
	var means := PackedInt32Array()
	var ready := PackedByteArray()
	means.resize(CELL_COUNT)
	ready.resize(CELL_COUNT)
	var total := 0
	var bi := 0
	for by in BLOCKS:
		for bx in BLOCKS:
			if _developed[bi] == 0:
				land_value[bi] = 0
				bi += 1
				continue
			var qi := (by >> 1) * CELLS + (bx >> 1)
			if ready[qi] == 0:
				means[qi] = _neighbourhood_mean(_amenity, bx >> 1, by >> 1, CELLS)
				ready[qi] = 1
			var value := means[qi]
			var reach := maxi(0, Params.CENTRE_REACH - absi(_centre.x - bx) - absi(_centre.y - by))
			var block_pollution := pollution[bi]
			var block_crime := crime[bi]
			var block_density := density[qi]
			var zone := _block_zone[bi]
			if Zones.is_industrial(zone):
				@warning_ignore("integer_division")
				value += reach / 4 - block_pollution / Params.IND_POLLUTION_DIVISOR \
					- block_crime / Params.IND_CRIME_DIVISOR
				if zone == Zones.IND_HIGH:
					value += Params.INDUSTRIAL_DENSE_BONUS
			elif Zones.is_commercial(zone):
				@warning_ignore("integer_division")
				value += reach - block_pollution / Params.COM_POLLUTION_DIVISOR \
					- block_crime / Params.COM_CRIME_DIVISOR \
					+ block_density / Params.COM_DENSITY_DIVISOR
			else:
				@warning_ignore("integer_division")
				value += reach / 2 - block_pollution / Params.RES_POLLUTION_DIVISOR \
					- block_crime / Params.RES_CRIME_DIVISOR \
					- traffic[bi] / Params.RES_TRAFFIC_DIVISOR
				if block_density < Params.QUIET_DENSITY:
					value += Params.QUIET_BONUS
			if _abandoned_tbl[bld[(by * 2) * W + bx * 2]] != 0:
				@warning_ignore("integer_division")
				value /= 2
			value = clampi(value, 0, 255)
			land_value[bi] = value
			total += value
			bi += 1
	city.land_value.data = land_value
	_land_value_total = total


## Amenity contributed by a dry tile's building (or lack of one).
static func _building_amenity(id: int, terrain_code: int) -> int:
	if id == Buildings.NONE:
		var score := Params.AMENITY_OPEN_GROUND
		if not Terrain.is_flat(terrain_code):
			score += Params.AMENITY_SLOPE
		return score
	if Buildings.is_rubble(id):
		return Params.AMENITY_RUBBLE
	if Buildings.is_tree(id):
		return Params.AMENITY_TREE
	if id == Buildings.SMALL_PARK:
		return Params.AMENITY_PARK
	if id == Buildings.LARGE_PARK:
		return Params.AMENITY_LARGE_PARK
	if id in CIVIC_ATTRACTIONS:
		return Params.AMENITY_CIVIC
	return 0


## Mean of a cell and its in-bounds cardinal neighbours on a square grid.
static func _neighbourhood_mean(grid: PackedInt32Array, x: int, y: int, size: int) -> int:
	var i := y * size + x
	var sum := grid[i]
	var count := 1
	if x > 0:
		sum += grid[i - 1]
		count += 1
	if x < size - 1:
		sum += grid[i + 1]
		count += 1
	if y > 0:
		sum += grid[i - size]
		count += 1
	if y < size - 1:
		sum += grid[i + size]
		count += 1
	@warning_ignore("integer_division")
	return sum / count


# ── Crime ────────────────────────────────────────────────────────────────

func _update_crime(ctx: SimContext) -> void:
	var city := ctx.city
	var crime := city.crime.data
	var land_value := city.land_value.data
	var density := city.density.data
	var police := city.police.data
	var gambling := bool(ctx.stats.ordinances.get(&"legalized_gambling", false))
	var watch := bool(ctx.stats.ordinances.get(&"neighborhood_watch", false))
	var adjust := 0
	if gambling:
		adjust += Params.GAMBLING_CRIME
	if watch:
		adjust -= Params.WATCH_CRIME_RELIEF
	_base.fill(0)
	var bi := 0
	for by in BLOCKS:
		var q := (by >> 1) * CELLS
		for bx in BLOCKS:
			if _developed[bi] != 0:
				var qi := q + (bx >> 1)
				@warning_ignore("integer_division")
				_base[bi] = density[qi] - police[qi] / Params.POLICE_CRIME_DIVISOR \
					- land_value[bi] / Params.VALUE_CRIME_DIVISOR + adjust
			bi += 1
	var total := 0
	bi = 0
	for by in BLOCKS:
		for bx in BLOCKS:
			if _developed[bi] == 0:
				crime[bi] = 0
				bi += 1
				continue
			var sum := _base[bi]
			var count := 1
			if bx > 0:
				sum += _base[bi - 1]
				count += 1
			if bx < BLOCKS - 1:
				sum += _base[bi + 1]
				count += 1
			if by > 0:
				sum += _base[bi - BLOCKS]
				count += 1
			if by < BLOCKS - 1:
				sum += _base[bi + BLOCKS]
				count += 1
			@warning_ignore("integer_division")
			var value := clampi(sum / count, 0, 255)
			crime[bi] = value
			total += value
			bi += 1
	city.crime.data = crime
	_crime_total = total


# ── Publication ──────────────────────────────────────────────────────────

func _publish(ctx: SimContext) -> void:
	var count := maxi(_developed_blocks, 1)
	@warning_ignore("integer_division")
	ctx.stats.average_pollution = clampi(_pollution_total / count, 0, 255)
	@warning_ignore("integer_division")
	ctx.stats.average_land_value = clampi(_land_value_total / count, 0, 255)
	@warning_ignore("integer_division")
	ctx.stats.average_crime = clampi(_crime_total / count, 0, 255)
	var polluted := ctx.stats.average_pollution >= Params.POLLUTION_ALERT_LEVEL
	if polluted and not _pollution_alerted:
		ctx.events.report(&"pollution_alert", {"level": ctx.stats.average_pollution}, 2)
	_pollution_alerted = polluted
	var lawless := ctx.stats.average_crime >= Params.CRIME_WAVE_LEVEL
	if lawless and not _crime_alerted:
		ctx.events.report(&"crime_wave", {"level": ctx.stats.average_crime}, 2)
	_crime_alerted = lawless


# ── Footprint helpers ────────────────────────────────────────────────────

## True when any tile of the footprint received power.
static func _footprint_powered(flags: PackedByteArray, ax: int, ay: int, s: Vector2i) -> bool:
	for dy in s.y:
		var y := ay + dy
		if y >= H:
			break
		for dx in s.x:
			var x := ax + dx
			if x < W and (flags[y * W + x] & TileFlags.POWERED) != 0:
				return true
	return false


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	return {
		"pollution_total": _pollution_total,
		"land_value_total": _land_value_total,
		"crime_total": _crime_total,
		"developed_blocks": _developed_blocks,
		"pollution_alerted": _pollution_alerted,
		"crime_alerted": _crime_alerted,
	}


func load(data: Dictionary) -> void:
	_pollution_total = int(data.get("pollution_total", 0))
	_land_value_total = int(data.get("land_value_total", 0))
	_crime_total = int(data.get("crime_total", 0))
	_developed_blocks = int(data.get("developed_blocks", 0))
	_pollution_alerted = bool(data.get("pollution_alerted", false))
	_crime_alerted = bool(data.get("crime_alerted", false))
