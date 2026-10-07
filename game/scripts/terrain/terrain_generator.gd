# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Procedural desert map generator.
##
## Builds a `City` with a fresh `TerrainSurface`: rolling relief from layered
## noise folded into ridges and valleys with a few higher hills, an ocean along
## one edge with an irregular bay, lakes sunk into low basins, dry washes, a
## river that descends from high ground through waterfalls and broadens into
## an estuary at the coast, and trees clustered on slopes, along water and in
## washes with a scatter elsewhere. Every choice comes from the supplied
## `SimRng`, so a seed reproduces the same map.
##
## Parameters (all optional, see `docs/design/terrain.md`):
##   hills 0..100, water 0..100, trees 0..100, coast "none"|"north"|"south"|
##   "east"|"west", river bool, sea_level int, name, difficulty, founded_year.
class_name TerrainGenerator
extends RefCounted

const DEFAULT_HILLS := 40
const DEFAULT_WATER := 40
const DEFAULT_TREES := 40
const DEFAULT_SEA_LEVEL := 5
const MIN_SEA_LEVEL := 1
const MAX_SEA_LEVEL := 16

## Relief the hills control buys, in levels at 100, and the relief that is
## always present so the desert is never a billiard table.
const HILL_AMPLITUDE := 25.0
const HILL_FLOOR := 1.5
## Exponent shaping how relief grows with the control: below 1 the middle
## settings already carry much of the relief.
const HILL_CURVE := 0.8
## Noise octave cell sizes (in vertices) and weights, coarse to fine.
const NOISE_CELLS := [40, 20, 10, 5]
const NOISE_WEIGHTS := [0.55, 0.8, 0.52, 0.28]
## A finer octave whose weight grows with the hills control, so high
## settings are rugged where low ones stay rolling.
const ROUGH_CELL := 3
const ROUGH_WEIGHT_AT_MAX := 0.32
## A ridged octave folds the noise into ridge lines and valley floors.
const RIDGE_CELL := 26
const RIDGE_WEIGHT := 0.5
## Higher hills: one per this many hill points, each a rounded dome.
const PEAK_POINTS := 20
const PEAK_RADIUS_MIN := 8
const PEAK_RADIUS_MAX := 20
const PEAK_HEIGHT_MIN := 0.25
const PEAK_HEIGHT_MAX := 0.5
## Passes of saddle settling before the lattice is handed to normalization.
const SADDLE_PASSES := 8
## Relief fades toward the shore over this many tiles, down to this share.
const COAST_TAPER := 20.0
const COAST_TAPER_FLOOR := 0.35
## Sea band depth in tiles before the shoreline wobble and the bay.
const COAST_BAND := 17.0
## Bay: half-width range in tiles; its depth is a multiple of the band.
const BAY_RADIUS_MIN := 14
const BAY_RADIUS_MAX := 26
## Lakes: one plus one per this many water points; basin radius range.
const LAKE_POINTS := 34
const LAKE_RADIUS_MIN := 2
const LAKE_RADIUS_MAX := 4
## Water points per extra tile of the largest lake radius.
const LAKE_GROWTH_POINTS := 50
## Dry washes: one plus one per this many hill points.
const WASH_POINTS := 34
## Meander behaviour: chance per step of a sideways move, and the run of
## straight tiles at the start of a river (so a waterfall can be placed).
const MEANDER_SIDE_CHANCE := 35
const RIVER_STRAIGHT_LEAD := 4
const RIVER_MAX_LENGTH := 240
## Least distance, in tiles, between the river's source and the sea.
const RIVER_MIN_RUN := 56
## Estuary: the river's last tiles before the sea broaden to this many tiles
## on each side of the channel.
const ESTUARY_LENGTH := 28
const ESTUARY_HALF_WIDTH_MIN := 2
const ESTUARY_WIDTH_POINTS := 100
## Tree placement: the share of dry land under trees at 100 and the curve
## that takes the control there (a smooth ramp raised to this power, so low
## settings give only a few trees), the distance (tiles) from water that
## still counts as moist, the cover noise cells (in tiles) and weights, the
## bonuses added to the cover on slopes, near water and in washes, and the
## random jitter per tile that scatters lone trees outside the clusters.
const TREE_COVER_MAX := 0.78
const TREE_COVER_CURVE := 1.3
const TREE_MOISTURE_RANGE := 6
const TREE_COVER_CELLS := [12, 6, 3]
const TREE_COVER_WEIGHTS := [1.0, 0.5, 0.25]
const TREE_SLOPE_BONUS := 0.12
const TREE_MOIST_BONUS := 0.35
const TREE_WASH_BONUS := 0.3
const TREE_JITTER := 0.25

const DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var _rng: SimRng
var _surface: TerrainSurface
var _sea_level := DEFAULT_SEA_LEVEL
var _coast := "none"
var _field := PackedFloat32Array()      ## per vertex, relief before quantizing
var _sea_mask := PackedByteArray()      ## per tile, 1 inside the sea region
var _sea_distance := PackedInt32Array() ## per tile, steps to the nearest sea tile
var _lake_mask := PackedByteArray()     ## per tile, 1 inside a lake basin
var _river_mask := PackedByteArray()    ## per tile, 1 on the river channel
var _wash_mask := PackedByteArray()     ## per tile, 1 on a dry wash
var _pinned: Dictionary = {}            ## vertices the river owns
var _pin_mask := PackedByteArray()      ## per vertex, 1 when pinned
var _estuary_half_width := ESTUARY_HALF_WIDTH_MIN


## Decorate imported terrain without consuming a simulation or procedural RNG.
static func decorate_trees(city: City, trees: int, seed_value: int) -> void:
	var generator := TerrainGenerator.new()
	generator._rng = SimRng.from_saved_seed(seed_value)
	generator._wash_mask.resize(City.WIDTH * City.HEIGHT)
	generator._plant_trees(city, clampi(trees, 0, 100))


## Generate a new city. `params` keys are listed in the class comment.
func generate(params: Dictionary, rng: SimRng) -> City:
	_rng = rng
	var hills := clampi(int(params.get("hills", DEFAULT_HILLS)), 0, 100)
	var water := clampi(int(params.get("water", DEFAULT_WATER)), 0, 100)
	var trees := clampi(int(params.get("trees", DEFAULT_TREES)), 0, 100)
	_coast = String(params.get("coast", "none"))
	if not _coast in ["none", "north", "south", "east", "west"]:
		_coast = "none"
	var river := bool(params.get("river", true))
	_estuary_half_width = ESTUARY_HALF_WIDTH_MIN + int(water / float(ESTUARY_WIDTH_POINTS))
	_sea_level = clampi(int(params.get("sea_level", DEFAULT_SEA_LEVEL)), MIN_SEA_LEVEL, MAX_SEA_LEVEL)

	var city := City.new()
	city.name = String(params.get("name", "New City"))
	city.founded_year = int(params.get("founded_year", 1900))
	city.difficulty = clampi(int(params.get("difficulty", City.Difficulty.EASY)), City.Difficulty.EASY, City.Difficulty.HARD)
	city.funds = int(City.STARTING_FUNDS[city.difficulty])
	city.sea_level = _sea_level

	_surface = TerrainSurface.new(_sea_level + 1)
	var tiles := City.WIDTH * City.HEIGHT
	_sea_mask = PackedByteArray()
	_sea_mask.resize(tiles)
	_sea_distance = PackedInt32Array()
	_sea_distance.resize(tiles)
	_sea_distance.fill(City.WIDTH + City.HEIGHT)
	_lake_mask = PackedByteArray()
	_lake_mask.resize(tiles)
	_river_mask = PackedByteArray()
	_river_mask.resize(tiles)
	_wash_mask = PackedByteArray()
	_wash_mask.resize(tiles)
	_pinned = {}
	_pin_mask = PackedByteArray()
	_pin_mask.resize(TerrainSurface.VERTS_X * TerrainSurface.VERTS_Y)

	_shape_relief(hills)
	if _coast != "none":
		_carve_coast()
	_limit_slopes()
	_carve_washes(hills)
	_carve_lakes(water)
	_limit_slopes()
	if river:
		_carve_river()
		_limit_slopes()
	_settle_saddles()
	var settled := _surface.normalize(Rect2i(), _pinned)
	if not bool(settled["converged"]):
		_surface.normalize()
	_flood_basins()
	_surface.project(city)
	_plant_trees(city, trees)
	return city


# ── Relief ───────────────────────────────────────────────────────────────

## Layered value noise, a ridged octave and a few domes, faded toward the
## coast, scaled by the hills control and quantized to whole levels at or
## above sea level.
func _shape_relief(hills: int) -> void:
	var amplitude := HILL_FLOOR + pow(hills / 100.0, HILL_CURVE) * HILL_AMPLITUDE
	var vw := TerrainSurface.VERTS_X
	var vh := TerrainSurface.VERTS_Y
	_field = PackedFloat32Array()
	_field.resize(vw * vh)
	var rough := ROUGH_WEIGHT_AT_MAX * hills / 100.0
	var weight_sum := RIDGE_WEIGHT + rough
	for w in NOISE_WEIGHTS:
		weight_sum += float(w)
	for octave in NOISE_CELLS.size():
		_add_noise(vw, vh, int(NOISE_CELLS[octave]), float(NOISE_WEIGHTS[octave]) / weight_sum, false)
	_add_noise(vw, vh, RIDGE_CELL, RIDGE_WEIGHT / weight_sum, true)
	if rough > 0.0:
		_add_noise(vw, vh, ROUGH_CELL, rough / weight_sum, false)
	# Domes: a few rounded higher hills.
	var peaks := 1 + int(hills / float(PEAK_POINTS))
	for _p in peaks:
		var cx := _rng.range_int(PEAK_RADIUS_MAX, vw - 1 - PEAK_RADIUS_MAX)
		var cy := _rng.range_int(PEAK_RADIUS_MAX, vh - 1 - PEAK_RADIUS_MAX)
		var radius := float(_rng.range_int(PEAK_RADIUS_MIN, PEAK_RADIUS_MAX))
		var height := PEAK_HEIGHT_MIN + _rng.unit() * (PEAK_HEIGHT_MAX - PEAK_HEIGHT_MIN)
		var r := int(radius)
		for vy in range(maxi(cy - r, 0), mini(cy + r + 1, vh)):
			for vx in range(maxi(cx - r, 0), mini(cx + r + 1, vw)):
				var dist := sqrt(float((vx - cx) * (vx - cx) + (vy - cy) * (vy - cy))) / radius
				if dist < 1.0:
					_field[vy * vw + vx] += height * _smooth(1.0 - dist)
	# Quantize; relief fades toward the sea edge so the coast is a lowland.
	for vy in vh:
		for vx in vw:
			var i := vy * vw + vx
			var taper := 1.0
			if _coast != "none":
				var d := float(_shore_distance(vx, vy))
				taper = COAST_TAPER_FLOOR + (1.0 - COAST_TAPER_FLOOR) * _smooth(clampf(d / COAST_TAPER, 0.0, 1.0))
			var h := _sea_level + int(floor(_field[i] * amplitude * taper + 0.5))
			_surface.vertices[i] = clampi(h, _sea_level, TerrainSurface.MAX_HEIGHT - 1)


## Add one octave of value noise (or its ridged fold) to `_field`, using a
## lattice of random samples `cell` vertices apart.
@warning_ignore("integer_division")
func _add_noise(vw: int, vh: int, cell: int, weight: float, ridged: bool) -> void:
	var lattice_w := vw / cell + 2
	var lattice_h := vh / cell + 2
	var lattice := PackedFloat32Array()
	lattice.resize(lattice_w * lattice_h)
	for i in lattice.size():
		lattice[i] = _rng.unit()
	for vy in vh:
		var fy := float(vy) / cell
		var cy := int(fy)
		var ty := _smooth(fy - cy)
		for vx in vw:
			var fx := float(vx) / cell
			var cx := int(fx)
			var tx := _smooth(fx - cx)
			var a := lattice[cy * lattice_w + cx]
			var b := lattice[cy * lattice_w + cx + 1]
			var c := lattice[(cy + 1) * lattice_w + cx]
			var d := lattice[(cy + 1) * lattice_w + cx + 1]
			var v := lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)
			if ridged:
				v = 1.0 - absf(v * 2.0 - 1.0)
			_field[vy * vw + vx] += v * weight


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Vertex distance, in tiles, from the coast edge.
func _shore_distance(vx: int, vy: int) -> int:
	match _coast:
		"north": return vy
		"south": return TerrainSurface.VERTS_Y - 1 - vy
		"west": return vx
		"east": return TerrainSurface.VERTS_X - 1 - vx
	return TerrainSurface.VERTS_X


## Bring every unpinned vertex down to within one level of its lower
## neighbours, so no cliff survives and sunk features get sloping sides.
## Two sweeps (forward and back) settle the whole lattice.
func _limit_slopes() -> void:
	var vw := TerrainSurface.VERTS_X
	var vh := TerrainSurface.VERTS_Y
	for vy in vh:
		for vx in vw:
			var i := vy * vw + vx
			if _pin_mask[i]:
				continue
			var h := int(_surface.vertices[i])
			if vx > 0:
				h = mini(h, _surface.vertices[i - 1] + 1)
			if vy > 0:
				h = mini(h, _surface.vertices[i - vw] + 1)
			_surface.vertices[i] = h
	for vy in range(vh - 1, -1, -1):
		for vx in range(vw - 1, -1, -1):
			var i := vy * vw + vx
			if _pin_mask[i]:
				continue
			var h := int(_surface.vertices[i])
			if vx < vw - 1:
				h = mini(h, _surface.vertices[i + 1] + 1)
			if vy < vh - 1:
				h = mini(h, _surface.vertices[i + vw] + 1)
			_surface.vertices[i] = h


## Break saddle tiles (two opposite corners raised on their own) by lowering
## one raised corner to the tile's base and re-limiting the slopes. Only
## ever lowers, so it settles; pinned corners are left alone.
func _settle_saddles() -> void:
	for _pass in SADDLE_PASSES:
		var fixed := 0
		for y in City.HEIGHT:
			for x in City.WIDTH:
				var c := _surface.corners(x, y)
				var base := mini(mini(c[0], c[1]), mini(c[2], c[3]))
				var mask := 0
				for k in 4:
					if c[k] > base:
						mask |= 1 << k
				if mask != 5 and mask != 10:
					continue
				var a := Vector2i(x + 1, y) if mask == 5 else Vector2i(x + 1, y + 1)
				var b := Vector2i(x, y + 1) if mask == 5 else Vector2i(x, y)
				for v: Vector2i in [a, b]:
					if _pin_mask[v.y * TerrainSurface.VERTS_X + v.x]:
						continue
					_surface.set_vertex(v.x, v.y, base)
					fixed += 1
					break
		if fixed == 0:
			return
		_limit_slopes()


# ── Coast ────────────────────────────────────────────────────────────────

## Lower the vertices along one edge below sea level, with a wavy shoreline
## and one bay. Marks the sea region, and how far every tile lies from it,
## so later steps keep clear of the sea.
@warning_ignore("integer_division")
func _carve_coast() -> void:
	var band := COAST_BAND
	var along := TerrainSurface.VERTS_X
	var bay_center := _rng.range_int(BAY_RADIUS_MAX, along - 1 - BAY_RADIUS_MAX)
	var bay_radius := _rng.range_int(BAY_RADIUS_MIN, BAY_RADIUS_MAX)
	var bay_depth := band * (0.8 + _rng.unit() * 0.8)
	# A one-dimensional wobble along the shore, from coarse random samples.
	var samples := PackedFloat32Array()
	var sample_count := along / 8 + 2
	samples.resize(sample_count)
	for i in sample_count:
		samples[i] = (_rng.unit() - 0.5) * 8.0
	for vy in TerrainSurface.VERTS_Y:
		for vx in TerrainSurface.VERTS_X:
			var t := vx
			if _coast == "west" or _coast == "east":
				t = vy
			var d := _shore_distance(vx, vy)
			var ft := float(t) / 8.0
			var si := int(ft)
			var wobble := lerpf(samples[si], samples[si + 1], _smooth(ft - si))
			var bay := 0.0
			var u := float(t - bay_center) / bay_radius
			if u > -1.0 and u < 1.0:
				bay = bay_depth * (1.0 - u * u)
			var into_sea := band + wobble + bay - d
			var i := vy * TerrainSurface.VERTS_X + vx
			if into_sea > 0.0:
				var depth := 1 + int(into_sea / 4.0)
				_surface.vertices[i] = maxi(_sea_level - depth, TerrainSurface.MIN_HEIGHT)
			elif into_sea > -1.5:
				_surface.vertices[i] = _sea_level
	var queue: Array[Vector2i] = []
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if _surface.tile_base(x, y) < _sea_level:
				_sea_mask[y * City.WIDTH + x] = 1
				_sea_distance[y * City.WIDTH + x] = 0
				queue.append(Vector2i(x, y))
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		var next := _sea_distance[p.y * City.WIDTH + p.x] + 1
		for d in DIRECTIONS:
			var n := p + d
			if _in_bounds(n) and _sea_distance[n.y * City.WIDTH + n.x] > next:
				_sea_distance[n.y * City.WIDTH + n.x] = next
				queue.append(n)


# ── Washes and lakes ─────────────────────────────────────────────────────

## Dry meandering channels one level below the land around them.
func _carve_washes(hills: int) -> void:
	var count := 1 + int(hills / float(WASH_POINTS))
	for _w in count:
		var start := _random_interior_tile(10)
		var dir := DIRECTIONS[_rng.below(4)]
		var path := _meander(start, dir, int(RIVER_MAX_LENGTH / 2.0), 0, false)
		for p in path:
			var base := _surface.tile_base(p.x, p.y)
			var target := maxi(base - 1, _sea_level)
			for v in TerrainSurface.tile_vertices(p.x, p.y):
				if _surface.vertex(v.x, v.y) > target:
					_surface.set_vertex(v.x, v.y, target)
			_wash_mask[p.y * City.WIDTH + p.x] = 1


## Lakes: pick the lowest of a few random interior spots and sink a rounded
## basin to just below sea level so it fills with fresh water; the slope
## limiter then shapes the surrounding land into a bowl.
func _carve_lakes(water: int) -> void:
	var count := 1 + int(water / float(LAKE_POINTS))
	var radius_max := LAKE_RADIUS_MAX + int(water / float(LAKE_GROWTH_POINTS))
	for _l in count:
		var best := Vector2i(-1, -1)
		var best_h := 999
		for _c in 8:
			var c := _random_interior_tile(14)
			var i := c.y * City.WIDTH + c.x
			if _sea_mask[i] or _lake_mask[i]:
				continue
			var h := _surface.tile_base(c.x, c.y)
			if h < best_h:
				best_h = h
				best = c
		if best.x < 0:
			continue
		var radius := _rng.range_int(LAKE_RADIUS_MIN, radius_max)
		var stretch := 0.7 + _rng.unit() * 0.6
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var dist := sqrt(dx * dx * stretch + dy * dy / stretch)
				if dist > radius:
					continue
				var tx := best.x + dx
				var ty := best.y + dy
				if tx < 0 or ty < 0 or tx >= City.WIDTH or ty >= City.HEIGHT:
					continue
				var depth := 2 if dist <= radius * 0.5 else 1
				for v in TerrainSurface.tile_vertices(tx, ty):
					if _surface.vertex(v.x, v.y) > _sea_level - depth:
						_surface.set_vertex(v.x, v.y, maxi(_sea_level - depth, TerrainSurface.MIN_HEIGHT))
				_lake_mask[ty * City.WIDTH + tx] = 1


# ── River ────────────────────────────────────────────────────────────────

## A stream from the highest interior point toward the coast (or a random
## edge), one level below the land, dropping a level at waterfalls placed
## on straight tiles. Its vertices are pinned so later shaping keeps it.
## When it reaches the sea its last stretch broadens into an estuary.
func _carve_river() -> void:
	var dir := _river_direction(_highest_interior_tile(Vector2i.ZERO))
	var source := _highest_interior_tile(_run_toward(dir))
	var path := _meander(source, dir, RIVER_MAX_LENGTH, RIVER_STRAIGHT_LEAD, true)
	if path.size() < 3:
		return
	var last := path[path.size() - 1]
	var estuary_start := path.size()
	if _sea_mask[last.y * City.WIDTH + last.x]:
		estuary_start = maxi(path.size() / 2, path.size() - ESTUARY_LENGTH)
	# Which path tiles are straight (previous and next in the same direction).
	var straight := PackedByteArray()
	straight.resize(path.size())
	for i in range(1, path.size() - 1):
		if path[i] - path[i - 1] == path[i + 1] - path[i]:
			straight[i] = 1
	var straight_after := PackedInt32Array()
	straight_after.resize(path.size() + 1)
	for i in range(path.size() - 1, -1, -1):
		straight_after[i] = straight_after[i + 1] + (1 if straight[i] else 0)
	# Height profile: never rise, drop at most one level per straight tile,
	# and drop as soon as the land ahead requires it: `bound` is the highest
	# bed at each tile's exit that still lets the river stay a level below
	# the land it will cross, given the straight tiles left to drop on. The
	# bed also reaches sea level by the estuary if enough straight tiles
	# remain, so the river's water, drawn on its bed, meets the sea flush.
	var floor_h := _sea_level
	var bound := PackedInt32Array()
	bound.resize(path.size() + 1)
	bound[path.size()] = TerrainSurface.MAX_HEIGHT
	for i in range(path.size() - 1, -1, -1):
		var p := path[i]
		var land := _surface.tile_base(p.x, p.y) - 1
		var next := bound[i + 1] + (1 if i + 1 < path.size() and straight[i + 1] else 0)
		bound[i] = maxi(mini(land, next), floor_h)
	var h := maxi(mini(_surface.tile_base(source.x, source.y) - 1, bound[0]), _sea_level)
	var entry := PackedInt32Array()
	var exit := PackedInt32Array()
	for i in path.size():
		entry.append(h)
		var remaining := straight_after[i] - straight_after[estuary_start]
		var must := h - floor_h >= remaining
		if straight[i] and h > floor_h and (h > bound[i] or must):
			h -= 1
		exit.append(h)
	# Carve: flat stream tiles, sloped waterfall tiles, all pinned; then the
	# estuary, which is plain sunk land that floods at sea level.
	for i in path.size():
		var p := path[i]
		if i >= estuary_start:
			_sink_estuary(path, i, estuary_start)
			continue
		var prev := path[i - 1] if i > 0 else p - dir
		var d := p - prev
		for v in TerrainSurface.tile_vertices(p.x, p.y):
			_pin(v, exit[i])
		for v in _edge_vertices(p, -d):
			_pin(v, entry[i])
		_river_mask[p.y * City.WIDTH + p.x] = 1
		if entry[i] != exit[i]:
			_surface.set_water(p.x, p.y, entry[i], false, TerrainSurface.Feature.WATERFALL)
		else:
			_surface.set_water(p.x, p.y, exit[i] + 1, false, TerrainSurface.Feature.STREAM)


func _pin(v: Vector2i, h: int) -> void:
	_surface.set_vertex(v.x, v.y, h)
	_pinned[v] = true
	_pin_mask[v.y * TerrainSurface.VERTS_X + v.x] = 1


## Sink the tiles across the channel at path index `i` to just below sea
## level; the channel widens from one tile to the full estuary at the mouth.
func _sink_estuary(path: Array[Vector2i], i: int, start: int) -> void:
	var p := path[i]
	var d := p - path[i - 1]
	var side := Vector2i(d.y, d.x)
	var span := maxi(path.size() - start, 1)
	var width := int(round(_estuary_half_width * float(i - start + 1) / span)) + _rng.below(2)
	var bed := maxi(_sea_level - 1, TerrainSurface.MIN_HEIGHT)
	for k in range(-width, width + 1):
		var q := p + side * k
		if q.x < 0 or q.y < 0 or q.x >= City.WIDTH or q.y >= City.HEIGHT:
			continue
		if _sea_mask[q.y * City.WIDTH + q.x]:
			continue
		for v in TerrainSurface.tile_vertices(q.x, q.y):
			if _surface.vertex(v.x, v.y) > bed and not _pin_mask[v.y * TerrainSurface.VERTS_X + v.x]:
				_surface.set_vertex(v.x, v.y, bed)


## The two vertices of a tile's edge facing direction `d`.
static func _edge_vertices(p: Vector2i, d: Vector2i) -> Array[Vector2i]:
	if d.y < 0:
		return [Vector2i(p.x, p.y), Vector2i(p.x + 1, p.y)]
	if d.y > 0:
		return [Vector2i(p.x, p.y + 1), Vector2i(p.x + 1, p.y + 1)]
	if d.x < 0:
		return [Vector2i(p.x, p.y), Vector2i(p.x, p.y + 1)]
	return [Vector2i(p.x + 1, p.y), Vector2i(p.x + 1, p.y + 1)]


@warning_ignore("integer_division")
func _river_direction(source: Vector2i) -> Vector2i:
	match _coast:
		"north": return Vector2i(0, -1)
		"south": return Vector2i(0, 1)
		"west": return Vector2i(-1, 0)
		"east": return Vector2i(1, 0)
	# No coast: head for the farthest edge so the river has room to drop.
	var dx := City.WIDTH - 1 - source.x if source.x < City.WIDTH / 2 else -source.x
	var dy := City.HEIGHT - 1 - source.y if source.y < City.HEIGHT / 2 else -source.y
	if absi(dx) >= absi(dy):
		return Vector2i(signi(dx), 0)
	return Vector2i(0, signi(dy))


## The highest dry tile away from the edges. With `run` set, only tiles at
## least RIVER_MIN_RUN tiles from the sea count, so the river has room to
## meander before it reaches the coast.
@warning_ignore("integer_division")
func _highest_interior_tile(run: Vector2i = Vector2i.ZERO) -> Vector2i:
	var best := Vector2i(City.WIDTH / 2, City.HEIGHT / 2)
	var best_h := -1
	var margin := 12
	for y in range(margin, City.HEIGHT - margin):
		for x in range(margin, City.WIDTH - margin):
			var i := y * City.WIDTH + x
			if _sea_mask[i] or _wash_mask[i] or _lake_mask[i]:
				continue
			if run != Vector2i.ZERO and _sea_distance[i] < RIVER_MIN_RUN:
				continue
			var h := _surface.tile_base(x, y)
			if h > best_h:
				best_h = h
				best = Vector2i(x, y)
	return best


## The river's main direction as a run requirement for source selection;
## without a coast the direction depends on the source, so no requirement.
func _run_toward(dir: Vector2i) -> Vector2i:
	return dir if _coast != "none" else Vector2i.ZERO


func _random_interior_tile(margin: int) -> Vector2i:
	return Vector2i(_rng.range_int(margin, City.WIDTH - 1 - margin), _rng.range_int(margin, City.HEIGHT - 1 - margin))


## A 4-connected path that mostly heads along `main`, with sideways runs.
## Stops at the map edge, when it enters the sea, or at `max_len` tiles.
## The first `lead` steps are always straight along `main`. A river keeps
## straight while the land ahead or beside it falls, so it can drop with the
## slope, and meanders where the land is level. Lakes are never entered.
func _meander(start: Vector2i, main: Vector2i, max_len: int, lead: int, river: bool) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	var visited: Dictionary = {}
	visited[start] = true
	var p := start
	var side := Vector2i(main.y, main.x)
	if _rng.below(2) == 0:
		side = -side
	var side_run := 0
	for step in max_len:
		var d := main
		if step >= lead:
			var here := _surface.tile_base(p.x, p.y)
			var falling := river and (_lower_than(p + main, here) or _lower_than(p + side, here))
			if side_run > 0 and falling:
				side_run = 0
			if side_run > 0:
				d = side
				side_run -= 1
			elif not falling and _rng.below(100) < MEANDER_SIDE_CHANCE:
				if _rng.below(3) == 0:
					side = -side
				side_run = _rng.range_int(0, 3)
				d = side
		var n := Vector2i(-1, -1)
		for candidate in [d, main, -side, side]:
			var c: Vector2i = p + candidate
			if not _in_bounds(c):
				continue
			if _lake_mask[c.y * City.WIDTH + c.x]:
				continue
			if _touches_visited(c, p, visited):
				continue
			n = c
			break
		if n.x < 0:
			break
		path.append(n)
		visited[n] = true
		p = n
		if _sea_mask[n.y * City.WIDTH + n.x]:
			break
	return path


static func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < City.WIDTH and p.y < City.HEIGHT


## True when tile `p` lies on the map and its ground is below `h`.
func _lower_than(p: Vector2i, h: int) -> bool:
	return _in_bounds(p) and _surface.tile_base(p.x, p.y) < h


## True when `c` or any of its neighbours other than `from` is on the path,
## which keeps a channel from running alongside itself.
static func _touches_visited(c: Vector2i, from: Vector2i, visited: Dictionary) -> bool:
	if visited.has(c):
		return true
	for d in DIRECTIONS:
		var n := c + d
		if n != from and visited.has(n):
			return true
	return false


# ── Standing water ───────────────────────────────────────────────────────

## Every tile whose ground lies below sea level holds water at sea level:
## brackish inside the sea region (and anything touching it), fresh elsewhere.
func _flood_basins() -> void:
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var i := y * City.WIDTH + x
			if _river_mask[i]:
				continue
			if _surface.tile_base(x, y) < _sea_level:
				_surface.set_water(x, y, _sea_level, _sea_mask[i] == 1)
	# Salt spreads through connected water from the sea region.
	var queue: Array[Vector2i] = []
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if _sea_mask[y * City.WIDTH + x] and _surface.has_water(x, y):
				queue.append(Vector2i(x, y))
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		for d in DIRECTIONS:
			var n := p + d
			if not _in_bounds(n):
				continue
			var i := n.y * City.WIDTH + n.x
			if _surface.has_water(n.x, n.y) and _surface.feature[i] == TerrainSurface.Feature.NONE and _surface.salt[i] == 0:
				_surface.salt[i] = 1
				queue.append(n)


# ── Trees ────────────────────────────────────────────────────────────────

## Share of open land that carries trees at a control setting.
static func tree_cover_share(trees: int) -> float:
	var t := clampf(trees / 100.0, 0.0, 1.0)
	return TREE_COVER_MAX * pow(_smooth(t), TREE_COVER_CURVE)


## Palms and scrub in clusters: a cover noise field, raised on slopes, near
## water and along washes, is thresholded by the trees control; a few lone
## trees are scattered over the rest.
func _plant_trees(city: City, trees: int) -> void:
	if trees <= 0:
		return
	var tiles := City.WIDTH * City.HEIGHT
	var distance := PackedInt32Array()
	distance.resize(tiles)
	distance.fill(TREE_MOISTURE_RANGE + 1)
	var queue: Array[Vector2i] = []
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if city.is_water(x, y):
				distance[y * City.WIDTH + x] = 0
				queue.append(Vector2i(x, y))
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		var next := distance[p.y * City.WIDTH + p.x] + 1
		if next > TREE_MOISTURE_RANGE:
			continue
		for d in DIRECTIONS:
			var n := p + d
			if not _in_bounds(n):
				continue
			var i := n.y * City.WIDTH + n.x
			if distance[i] > next:
				distance[i] = next
				queue.append(n)
	# Cover noise on the tile grid.
	_field = PackedFloat32Array()
	_field.resize(tiles)
	var weight_sum := 0.0
	for w in TREE_COVER_WEIGHTS:
		weight_sum += float(w)
	for octave in TREE_COVER_CELLS.size():
		_add_noise(City.WIDTH, City.HEIGHT, int(TREE_COVER_CELLS[octave]), float(TREE_COVER_WEIGHTS[octave]) / weight_sum, false)
	# Score every open tile; the control decides what share of them get trees
	# and the highest scores win, so trees gather where the score is raised.
	var score := PackedFloat32Array()
	score.resize(tiles)
	score.fill(-1.0)
	var open := PackedFloat32Array()
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var i := y * City.WIDTH + x
			if city.is_water(x, y) or city.building.at(x, y) != Buildings.NONE:
				continue
			var moisture := 1.0 - minf(distance[i], TREE_MOISTURE_RANGE + 1) / float(TREE_MOISTURE_RANGE + 1)
			var v := _field[i] + TREE_MOIST_BONUS * moisture * moisture + _rng.unit() * TREE_JITTER
			if not city.is_flat(x, y):
				v += TREE_SLOPE_BONUS
			if _wash_mask[i]:
				v += TREE_WASH_BONUS
			score[i] = v
			open.append(v)
	var want := int(round(tree_cover_share(trees) * open.size()))
	if want <= 0:
		return
	open.sort()
	var threshold := open[maxi(open.size() - want, 0)]
	var chosen := PackedByteArray()
	chosen.resize(tiles)
	for i in tiles:
		if score[i] >= threshold:
			chosen[i] = 1
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if not chosen[y * City.WIDTH + x]:
				continue
			var count := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < City.WIDTH and ny < City.HEIGHT and chosen[ny * City.WIDTH + nx]:
						count += 1
			var id := Buildings.TREES_1 + clampi(count - 1, 0, Buildings.TREES_7 - Buildings.TREES_1)
			city.building.put(x, y, id)
