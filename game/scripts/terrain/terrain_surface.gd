# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The shared-vertex terrain lattice.
##
## A city's ground is described by a 129×129 grid of vertex heights (0..31);
## every map tile owns the four vertices at its corners and shares them with
## its neighbours, so raising one corner raises the corner of up to four
## tiles at once. Water is stored per tile as a water height plus a salt flag
## and an optional flowing-water feature (stream or waterfall).
##
## The lattice is the editable truth. `project()` derives the city's `terrain`
## codes, `altitude` heights and salt flags from it; `from_city()` rebuilds the
## lattice from a city that arrived without one (an import or an old save).
class_name TerrainSurface
extends RefCounted

const WIDTH := City.WIDTH
const HEIGHT := City.HEIGHT
const VERTS_X := City.WIDTH + 1
const VERTS_Y := City.HEIGHT + 1
const MIN_HEIGHT := 0
const MAX_HEIGHT := 31
const NO_WATER := -1

## Flowing-water features carried by a tile in addition to its water height.
enum Feature { NONE, STREAM, WATERFALL }

## Corner order used by `corners()`: matches the bit order of
## `Terrain.raised_corners` (1 = NE, 2 = SE, 4 = SW, 8 = NW).
const NE := 0
const SE := 1
const SW := 2
const NW := 3

## Water shoreline table indexed by wet neighbours N/E/S/W (bits 0..3).
## Straight channels and end caps use 0x40..45; bends and junctions use shores.
const STREAM_CODES := [0x3d,0x45,0x42,0x38,0x43,0x40,0x35,0x31,
	0x44,0x37,0x41,0x34,0x36,0x33,0x32,0x30]

## Visits each vertex gets in the balanced relaxation pass; each visit halves
## the remaining gap, so a few are enough for any height difference.
const SPLIT_BUDGET := 8

var vertices := PackedByteArray()      ## VERTS_X * VERTS_Y heights
var water := PackedInt32Array()        ## per tile, NO_WATER when dry
var salt := PackedByteArray()          ## per tile, 1 when the water is brackish
var feature := PackedByteArray()       ## per tile, a Feature value


func _init(fill_height: int = 0) -> void:
	vertices.resize(VERTS_X * VERTS_Y)
	vertices.fill(clampi(fill_height, MIN_HEIGHT, MAX_HEIGHT))
	water.resize(WIDTH * HEIGHT)
	water.fill(NO_WATER)
	salt.resize(WIDTH * HEIGHT)
	feature.resize(WIDTH * HEIGHT)


# ── Vertices ─────────────────────────────────────────────────────────────

static func vertex_index(vx: int, vy: int) -> int:
	return vy * VERTS_X + vx


static func tile_index(x: int, y: int) -> int:
	return y * WIDTH + x


static func vertex_in_bounds(vx: int, vy: int) -> bool:
	return vx >= 0 and vy >= 0 and vx < VERTS_X and vy < VERTS_Y


func vertex(vx: int, vy: int) -> int:
	if not vertex_in_bounds(vx, vy):
		return 0
	return vertices[vy * VERTS_X + vx]


func set_vertex(vx: int, vy: int, h: int) -> void:
	if not vertex_in_bounds(vx, vy):
		return
	vertices[vy * VERTS_X + vx] = clampi(h, MIN_HEIGHT, MAX_HEIGHT)


## Heights of a tile's four corners in NE, SE, SW, NW order.
func corners(x: int, y: int) -> PackedInt32Array:
	var nw := vertex(x, y)
	var ne := vertex(x + 1, y)
	var sw := vertex(x, y + 1)
	var se := vertex(x + 1, y + 1)
	return PackedInt32Array([ne, se, sw, nw])


## Lowest corner: the tile's ground height.
func tile_base(x: int, y: int) -> int:
	return mini(mini(vertex(x, y), vertex(x + 1, y)), mini(vertex(x, y + 1), vertex(x + 1, y + 1)))


## Highest corner.
func tile_top(x: int, y: int) -> int:
	return maxi(maxi(vertex(x, y), vertex(x + 1, y)), maxi(vertex(x, y + 1), vertex(x + 1, y + 1)))


func is_tile_flat(x: int, y: int) -> bool:
	return tile_base(x, y) == tile_top(x, y)


## Set all four corners of a tile to one height.
func set_tile_height(x: int, y: int, h: int) -> void:
	set_vertex(x, y, h)
	set_vertex(x + 1, y, h)
	set_vertex(x, y + 1, h)
	set_vertex(x + 1, y + 1, h)


## The four vertex coordinates of a tile.
static func tile_vertices(x: int, y: int) -> Array[Vector2i]:
	return [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x + 1, y + 1)]


## Tiles that touch a vertex (up to four).
static func vertex_tiles(vx: int, vy: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-1, 1):
		for dx in range(-1, 1):
			var tx := vx + dx
			var ty := vy + dy
			if tx >= 0 and ty >= 0 and tx < WIDTH and ty < HEIGHT:
				out.append(Vector2i(tx, ty))
	return out


# ── Water ────────────────────────────────────────────────────────────────

func water_level(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
		return NO_WATER
	return water[y * WIDTH + x]


## True when the tile carries water above its ground.
func has_water(x: int, y: int) -> bool:
	return water_level(x, y) > tile_base(x, y)


func is_salt(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
		return false
	return salt[y * WIDTH + x] != 0


func feature_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
		return Feature.NONE
	return feature[y * WIDTH + x]


func set_water(x: int, y: int, level: int, is_salt_water: bool = false, kind: int = Feature.NONE) -> void:
	if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
		return
	var i := y * WIDTH + x
	water[i] = clampi(level, MIN_HEIGHT, MAX_HEIGHT)
	salt[i] = 1 if is_salt_water else 0
	feature[i] = kind


func clear_water(x: int, y: int) -> void:
	if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
		return
	var i := y * WIDTH + x
	water[i] = NO_WATER
	salt[i] = 0
	feature[i] = Feature.NONE


# ── Projection to city layers ────────────────────────────────────────────

## Terrain code for one tile, derived from its corners and water.
func tile_code(x: int, y: int) -> int:
	var c := corners(x, y)
	var base := mini(mini(c[NE], c[SE]), mini(c[SW], c[NW]))
	var top := maxi(maxi(c[NE], c[SE]), maxi(c[SW], c[NW]))
	var mask := 0
	if c[NE] > base: mask |= 1
	if c[SE] > base: mask |= 2
	if c[SW] > base: mask |= 4
	if c[NW] > base: mask |= 8
	var shape := Terrain.shape_from_corners(mask)
	if shape < 0:
		shape = Terrain.FLAT
	var w := water_level(x, y)
	if w <= base:
		return Terrain.make(shape, Terrain.DRY)
	var kind := feature_at(x, y)
	if kind == Feature.WATERFALL:
		return Terrain.WATERFALL
	if kind == Feature.STREAM:
		return _stream_code(x, y)
	if w > top:
		if base == top and w == base + 1:
			return Terrain.make(Terrain.FLAT, Terrain.SURFACE)
		return Terrain.make(shape, Terrain.SUBMERGED)
	return Terrain.make(shape, Terrain.SHORE)


## Pick a stream segment from which neighbours carry water.
func _stream_code(x: int, y: int) -> int:
	var mask := 0
	var directions := [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
	for i: int in 4:
		var neighbor: Vector2i = Vector2i(x,y)+directions[i]
		if has_water(neighbor.x,neighbor.y): mask |= 1<<i
	return STREAM_CODES[mask]


## Write terrain codes, ground and water heights and salt flags for the
## tiles inside `rect` (the whole map when the rect is empty). Tunnel bits
## and every other flag are preserved. Binds the surface to the city.
func project(city: City, rect: Rect2i = Rect2i()) -> void:
	if city == null:
		return
	city.terrain_surface = self
	var r := clamp_rect(rect)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var base := tile_base(x, y)
			var w := water_level(x, y)
			var wet := w > base
			city.terrain.put(x, y, tile_code(x, y))
			city.set_heights(x, y, base, w if wet else 0)
			city.set_flag(x, y, TileFlags.SALT_WATER, wet and is_salt(x, y))


## Clamp a tile rect to the map; an empty rect means the whole map.
static func clamp_rect(rect: Rect2i) -> Rect2i:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Rect2i(0, 0, WIDTH, HEIGHT)
	var start := Vector2i(maxi(rect.position.x, 0), maxi(rect.position.y, 0))
	var end := Vector2i(mini(rect.end.x, WIDTH), mini(rect.end.y, HEIGHT))
	if end.x <= start.x or end.y <= start.y:
		return Rect2i(start, Vector2i.ZERO)
	return Rect2i(start, end - start)


## Rebuild a lattice from a city's terrain and altitude layers. Where two
## tiles disagree about a shared vertex the higher reading wins; the caller
## normally follows with `normalize()` and re-projects the repaired rect.
static func from_city(city: City, saved_vertices: PackedByteArray = PackedByteArray()) -> TerrainSurface:
	var s := TerrainSurface.new(0)
	for y in HEIGHT:
		for x in WIDTH:
			var code := city.terrain.at(x, y)
			var base := city.ground_height(x, y)
			var raised := Terrain.raised_corners(Terrain.slope(code))
			s._lift_vertex(x + 1, y, base + (1 if raised & 1 else 0))
			s._lift_vertex(x + 1, y + 1, base + (1 if raised & 2 else 0))
			s._lift_vertex(x, y + 1, base + (1 if raised & 4 else 0))
			s._lift_vertex(x, y, base + (1 if raised & 8 else 0))
	if saved_vertices.size() == VERTS_X * VERTS_Y:
		s.vertices = saved_vertices
	for y in HEIGHT:
		for x in WIDTH:
			var code := city.terrain.at(x, y)
			var base := city.ground_height(x, y)
			var w := city.water_height(x, y)
			var i := y * WIDTH + x
			if Terrain.is_water(code) and w <= base:
				w = base + 1
			if w <= base:
				continue
			s.water[i] = w
			s.salt[i] = 1 if city.flags.has_bits(x, y, TileFlags.SALT_WATER) else 0
			var kind := Terrain.water_kind(code)
			if kind == Terrain.WATERFALL:
				s.feature[i] = Feature.WATERFALL
			elif kind == Terrain.STREAM:
				s.feature[i] = Feature.STREAM
			elif code > Terrain.SURFACE and code <= Terrain.SURFACE + Terrain.PLATEAU \
					and saved_vertices.size() == VERTS_X * VERTS_Y \
					and w > s.tile_base(x,y):
				# Native stream bends/junctions encode their banks in the SURFACE
				# band. Ordinary native slopes project as SHORE or SUBMERGED.
				# Restore this distinction before subsequent terrain edits project it.
				s.feature[i] = Feature.STREAM

	city.terrain_surface = s
	return s


func _lift_vertex(vx: int, vy: int, h: int) -> void:
	var i := vy * VERTS_X + vx
	if h > vertices[i]:
		vertices[i] = clampi(h, MIN_HEIGHT, MAX_HEIGHT)


# ── Normalization ────────────────────────────────────────────────────────

## Make the lattice representable: adjacent vertices differ by at most one
## level and no tile has two opposite corners raised on their own.
##
## Cliffs are relaxed from both sides first (the high side comes down, the
## low side comes up, halving the gap each visit) so a repair spreads evenly.
## Pinned vertices (Vector2i keys in `pinned`) never move; everything else is
## then clamped to the band a pin allows, and a final raise-only pass closes
## whatever gap is left, which always terminates. Saddle tiles get one low
## corner lifted into a valley shape.
##
## `rect` (tile coordinates, empty = whole map) is where the check starts;
## repairs propagate outward as far as they need to.
##
## Returns {changed: int, cliffs: int, saddles: int, converged: bool,
## rect: Rect2i} where `rect` bounds every tile touched by a changed vertex.
## Optional memory limit for normalize()'s worklists, used by the real-world
## importer; normalize() runs without one when no budget is given. Each check
## charges a generous upper bound for the queues' peak size, including the
## moment an array grows and its old and new buffers both exist.
class NormalizationWorkBudget extends RefCounted:
	var limit: int
	var queue_items := 0
	var recent_items := 0
	var bound_items := 0
	var peak_bytes := 0
	func _init(bytes: int) -> void:
		limit=bytes
	static func allocation_bytes(items: int) -> int:
		if items==0: return 128
		var rounded_items := 1
		while rounded_items<items: rounded_items*=2
		# This is a surrogate bound, not native capacity (CowData grows by 1.5x).
		# 128*rounded_items >= 100*items covers <=40-byte Variants and
		# simultaneous old/new buffers of about 2.5*items, plus fixed overhead.
		return 128+rounded_items*64*2
	func admit(queue_count: int, recent_count: int, bound_count: int, stats: Dictionary) -> bool:
		var q := maxi(queue_items,queue_count)
		var r := maxi(recent_items,recent_count)
		var b := maxi(bound_items,bound_count)
		var bytes := 512+allocation_bytes(q)+allocation_bytes(r)+allocation_bytes(b)
		stats["worklist_required_bytes"]=bytes
		if bytes>limit:
			stats["converged"]=false
			stats["resource_error"]="terrain_worklist_budget_exceeded"
			stats["worklist_peak_bytes"]=peak_bytes
			stats["worklist_queue_items"]=queue_items
			stats["worklist_recent_items"]=recent_items
			stats["worklist_bound_items"]=bound_items
			return false
		queue_items=q
		recent_items=r
		bound_items=b
		peak_bytes=maxi(peak_bytes,bytes)
		stats["worklist_peak_bytes"]=peak_bytes
		stats["worklist_queue_items"]=queue_items
		stats["worklist_recent_items"]=recent_items
		stats["worklist_bound_items"]=bound_items
		return true

@warning_ignore("integer_division")
func normalize(rect: Rect2i = Rect2i(), pinned: Dictionary = {}, worklist_budget_bytes: int = 0) -> Dictionary:
	var r := clamp_rect(rect)
	var total := VERTS_X * VERTS_Y
	var pins := PackedByteArray()
	pins.resize(total)
	var have_pins := false
	for p in pinned:
		if p is Vector2i and vertex_in_bounds(p.x, p.y):
			pins[p.y * VERTS_X + p.x] = 1
			have_pins = true
	var changed := PackedByteArray()
	changed.resize(total)
	var stats := {"changed": 0, "cliffs": 0, "saddles": 0, "converged": true, "rect": Rect2i()}
	var budget := NormalizationWorkBudget.new(worklist_budget_bytes) if worklist_budget_bytes>0 else null

	# Seed the worklist with the rect's vertices.
	var queued := PackedByteArray()
	queued.resize(total)
	var queue: Array[int] = []
	if budget!=null and not budget.admit((r.size.x+1)*(r.size.y+1),0,0,stats): return stats
	for vy in range(r.position.y, r.end.y + 1):
		for vx in range(r.position.x, r.end.x + 1):
			var i := vy * VERTS_X + vx
			queued[i] = 1
			queue.append(i)

	# Step 1: balanced relaxation with a visit budget per vertex.
	var visits := PackedByteArray()
	visits.resize(total)
	var head := 0
	while head < queue.size():
		if budget!=null and not budget.admit(queue.size()+5,0,0,stats): return stats
		var i := queue[head]
		head += 1
		queued[i] = 0
		if pins[i] or visits[i] >= SPLIT_BUDGET:
			if pins[i] and visits[i] == 0:
				visits[i] = 1
				_enqueue_neighbors(i, queue, queued)
			continue
		visits[i] += 1
		var v := vertices[i]
		var band := _neighbor_band(i)
		var lo := band.x
		var hi := band.y
		var target := v
		if lo > hi:
			target = (lo + hi) / 2
		elif v < lo:
			target = v + (lo - v + 1) / 2
		elif v > hi:
			target = v - (v - hi + 1) / 2
		if target == v:
			continue
		stats["cliffs"] += 1
		vertices[i] = clampi(target, MIN_HEIGHT, MAX_HEIGHT)
		changed[i] = 1
		if not queued[i]:
			queued[i] = 1
			queue.append(i)
		_enqueue_neighbors(i, queue, queued)

	# Step 2: keep every free vertex inside the band its pins allow.
	var lower := PackedInt32Array()
	var upper := PackedInt32Array()
	if have_pins:
		lower = _propagate_bound(pins, true, budget, stats)
		if lower.is_empty(): return stats
		upper = _propagate_bound(pins, false, budget, stats)
		if upper.is_empty(): return stats
		for i in total:
			if pins[i]:
				continue
			var v := vertices[i]
			var c := clampi(v, lower[i], upper[i])
			if c != v:
				vertices[i] = c
				changed[i] = 1
				if not queued[i]:
					if budget!=null and not budget.admit(queue.size()+1,0,0,stats): return stats
					queued[i] = 1
					queue.append(i)

	# Steps 3 and 4: raise-only closing pass, then saddle splitting, repeated
	# until nothing moves. Both only ever raise vertices, so they terminate.
	for i in total:
		if changed[i] and not queued[i]:
			if budget!=null and not budget.admit(queue.size()+1,0,0,stats): return stats
			queued[i] = 1
			queue.append(i)
	var recent: Array[int] = []
	if budget!=null and not budget.admit(queue.size(),queue.size(),0,stats): return stats
	for i in queue:
		recent.append(i)
	var first := true
	var settled := false
	while not settled:
		while head < queue.size():
			if budget!=null and not budget.admit(queue.size()+8,recent.size()+1,0,stats): return stats
			var i := queue[head]
			head += 1
			queued[i] = 0
			var v := vertices[i]
			var vx := i % VERTS_X
			var vy := i / VERTS_X
			var need := v
			if vx > 0: need = maxi(need, vertices[i - 1] - 1)
			if vx < VERTS_X - 1: need = maxi(need, vertices[i + 1] - 1)
			if vy > 0: need = maxi(need, vertices[i - VERTS_X] - 1)
			if vy < VERTS_Y - 1: need = maxi(need, vertices[i + VERTS_X] - 1)
			if need > v and not pins[i]:
				stats["cliffs"] += 1
				vertices[i] = need
				changed[i] = 1
				recent.append(i)
				_enqueue_neighbors(i, queue, queued)
			elif need > v:
				stats["converged"] = false
			# Neighbours below this vertex must come up too.
			_enqueue_low_neighbors(i, queue, queued)
		var tiles: Dictionary = {}
		if first:
			first = false
			for ty in range(r.position.y, r.end.y):
				for tx in range(r.position.x, r.end.x):
					tiles[Vector2i(tx, ty)] = true
		for i in recent:
			for t in vertex_tiles(i % VERTS_X, i / VERTS_X):
				tiles[t] = true
		recent.clear()
		var fixed := 0
		for t: Vector2i in tiles:
			if budget!=null and not budget.admit(queue.size()+1,recent.size()+1,0,stats): return stats
			var fix := _split_saddle(t.x, t.y, pins, upper)
			if fix >= 0:
				fixed += 1
				changed[fix] = 1
				recent.append(fix)
				if not queued[fix]:
					queued[fix] = 1
					queue.append(fix)
			elif fix == -2:
				stats["converged"] = false
		stats["saddles"] += fixed
		settled = fixed == 0 and head >= queue.size()

	# Report the tiles touched by every changed vertex.
	var lo_t := Vector2i(WIDTH, HEIGHT)
	var hi_t := Vector2i(-1, -1)
	for i in total:
		if not changed[i]:
			continue
		stats["changed"] += 1
		var vx := i % VERTS_X
		var vy := i / VERTS_X
		lo_t = Vector2i(mini(lo_t.x, maxi(vx - 1, 0)), mini(lo_t.y, maxi(vy - 1, 0)))
		hi_t = Vector2i(maxi(hi_t.x, mini(vx, WIDTH - 1)), maxi(hi_t.y, mini(vy, HEIGHT - 1)))
	if hi_t.x >= 0:
		stats["rect"] = Rect2i(lo_t, hi_t - lo_t + Vector2i.ONE)
	return stats


## Lowest and highest height a vertex may take to sit within one level of all
## its neighbours, as (lo, hi). lo > hi means the neighbours disagree.
@warning_ignore("integer_division")
func _neighbor_band(i: int) -> Vector2i:
	var vx := i % VERTS_X
	var vy := i / VERTS_X
	var lo := MIN_HEIGHT
	var hi := MAX_HEIGHT
	if vx > 0:
		lo = maxi(lo, vertices[i - 1] - 1)
		hi = mini(hi, vertices[i - 1] + 1)
	if vx < VERTS_X - 1:
		lo = maxi(lo, vertices[i + 1] - 1)
		hi = mini(hi, vertices[i + 1] + 1)
	if vy > 0:
		lo = maxi(lo, vertices[i - VERTS_X] - 1)
		hi = mini(hi, vertices[i - VERTS_X] + 1)
	if vy < VERTS_Y - 1:
		lo = maxi(lo, vertices[i + VERTS_X] - 1)
		hi = mini(hi, vertices[i + VERTS_X] + 1)
	return Vector2i(lo, hi)


@warning_ignore("integer_division")
func _enqueue_neighbors(i: int, queue: Array[int], queued: PackedByteArray) -> void:
	var vx := i % VERTS_X
	var vy := i / VERTS_X
	if vx > 0 and not queued[i - 1]:
		queued[i - 1] = 1
		queue.append(i - 1)
	if vx < VERTS_X - 1 and not queued[i + 1]:
		queued[i + 1] = 1
		queue.append(i + 1)
	if vy > 0 and not queued[i - VERTS_X]:
		queued[i - VERTS_X] = 1
		queue.append(i - VERTS_X)
	if vy < VERTS_Y - 1 and not queued[i + VERTS_X]:
		queued[i + VERTS_X] = 1
		queue.append(i + VERTS_X)


@warning_ignore("integer_division")
func _enqueue_low_neighbors(i: int, queue: Array[int], queued: PackedByteArray) -> void:
	var vx := i % VERTS_X
	var vy := i / VERTS_X
	var v := vertices[i]
	if vx > 0 and vertices[i - 1] < v - 1 and not queued[i - 1]:
		queued[i - 1] = 1
		queue.append(i - 1)
	if vx < VERTS_X - 1 and vertices[i + 1] < v - 1 and not queued[i + 1]:
		queued[i + 1] = 1
		queue.append(i + 1)
	if vy > 0 and vertices[i - VERTS_X] < v - 1 and not queued[i - VERTS_X]:
		queued[i - VERTS_X] = 1
		queue.append(i - VERTS_X)
	if vy < VERTS_Y - 1 and vertices[i + VERTS_X] < v - 1 and not queued[i + VERTS_X]:
		queued[i + VERTS_X] = 1
		queue.append(i + VERTS_X)


## The lowest (or highest) height each vertex may take so that every pinned
## vertex keeps all its neighbours within one level: a pin at height h forces
## a vertex d steps away to h - d or above (h + d or below).
@warning_ignore("integer_division")
func _propagate_bound(pins: PackedByteArray, is_lower: bool, budget: NormalizationWorkBudget = null, stats: Dictionary = {}) -> PackedInt32Array:
	var total := VERTS_X * VERTS_Y
	var bound := PackedInt32Array()
	bound.resize(total)
	bound.fill(MIN_HEIGHT if is_lower else MAX_HEIGHT)
	var queue: Array[int] = []
	if budget!=null and not budget.admit(budget.queue_items,budget.recent_items,total,stats): return PackedInt32Array()
	for i in total:
		if pins[i]:
			bound[i] = vertices[i]
			queue.append(i)
	var head := 0
	while head < queue.size():
		if budget!=null and not budget.admit(budget.queue_items,budget.recent_items,queue.size()+4,stats): return PackedInt32Array()
		var i := queue[head]
		head += 1
		var vx := i % VERTS_X
		var vy := i / VERTS_X
		var next := bound[i] - 1 if is_lower else bound[i] + 1
		for k in 4:
			var j := -1
			if k == 0 and vx > 0: j = i - 1
			elif k == 1 and vx < VERTS_X - 1: j = i + 1
			elif k == 2 and vy > 0: j = i - VERTS_X
			elif k == 3 and vy < VERTS_Y - 1: j = i + VERTS_X
			if j < 0 or pins[j]:
				continue
			if (is_lower and next > bound[j]) or (not is_lower and next < bound[j]):
				bound[j] = next
				queue.append(j)
	return bound


## Raise one low corner of a saddle tile so the tile becomes a valley shape.
## Returns the changed vertex index, -1 when the tile is fine, or -2 when the
## saddle cannot be split without moving a pinned vertex.
func _split_saddle(x: int, y: int, pins: PackedByteArray, upper: PackedInt32Array) -> int:
	var c := corners(x, y)
	var base := mini(mini(c[NE], c[SE]), mini(c[SW], c[NW]))
	var mask := 0
	if c[NE] > base: mask |= 1
	if c[SE] > base: mask |= 2
	if c[SW] > base: mask |= 4
	if c[NW] > base: mask |= 8
	if mask != 5 and mask != 10:
		return -1
	var low_a := Vector2i(x + 1, y + 1) if mask == 5 else Vector2i(x + 1, y)
	var low_b := Vector2i(x, y) if mask == 5 else Vector2i(x, y + 1)
	for v: Vector2i in [low_a, low_b]:
		var i := v.y * VERTS_X + v.x
		if pins[i] or vertices[i] >= MAX_HEIGHT:
			continue
		if not upper.is_empty() and vertices[i] + 1 > upper[i]:
			continue
		vertices[i] = vertices[i] + 1
		return i
	return -2


## Count of vertex pairs that still differ by more than one level.
func cliff_count() -> int:
	var n := 0
	for vy in VERTS_Y:
		for vx in VERTS_X:
			var h := vertices[vy * VERTS_X + vx]
			if vx < VERTS_X - 1 and absi(h - vertices[vy * VERTS_X + vx + 1]) > 1:
				n += 1
			if vy < VERTS_Y - 1 and absi(h - vertices[(vy + 1) * VERTS_X + vx]) > 1:
				n += 1
	return n


# ── Copies ───────────────────────────────────────────────────────────────

func duplicate_surface() -> TerrainSurface:
	var s := TerrainSurface.new()
	s.vertices = vertices.duplicate()
	s.water = water.duplicate()
	s.salt = salt.duplicate()
	s.feature = feature.duplicate()
	return s


func copy_from(other: TerrainSurface) -> void:
	vertices = other.vertices.duplicate()
	water = other.water.duplicate()
	salt = other.salt.duplicate()
	feature = other.feature.duplicate()
