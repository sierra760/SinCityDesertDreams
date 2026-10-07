# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Exact incremental physical surface resolution for regional network layers.
##
## The resolver's output is a concatenation of per-group blocks in group
## (first-appearance) order: floor = floors, obstacles = obstacle inputs +
## deck bottoms + deck boundary walls. Floors and bottoms of a group depend only
## on its own patches. A wall depends only on deck geometry within about 1e-4
## of its segment (vertex cuts, quantized segment matches, coverage probes), and
## belongs to the group whose segment key appears first. Therefore, after some
## regions change, only these blocks can differ from a full resolution:
## - floors/bottoms/decks of groups in changed regions (re-resolved alone);
## - walls of deck groups within MARGIN of the old or new deck geometry of the
##   changed groups, recomputed from every deck group within MARGIN of them.
## Everything else is copied from the previous exact result. Any situation the
## argument does not cover (a group key spanning regions, a changed region
## set) falls back to a full resolution, which is always exact.
extends RefCounted

const Native := preload("res://scripts/view/city_network_physics_native.gd")
## Far beyond every resolver neighbourhood (largest: 1e-4 candidate padding).
const MARGIN := 0.01

## Observational statistics for tests and profiling only.
var last_mode := ""
var last_changed_regions := 0
var last_recomputed_groups := 0
var last_wall_groups := 0
var last_context_groups := 0

var _ready := false
var _origins: Array[Vector2i] = []
## Per region: [cells, groups, roles, depths, triangles, obstacles] as resolved.
var _parts: Array = []
var _region_groups := PackedInt32Array()
var _keys := PackedInt32Array()
var _bounds := PackedFloat64Array()
var _floor := PackedVector3Array()
var _floor_ends := PackedInt32Array()
var _obstacles := PackedVector3Array()
var _prefix_size := 0
var _bottom_ends := PackedInt32Array()
var _wall_ends := PackedInt32Array()
var _deck := PackedVector3Array()
var _deck_depths := PackedFloat64Array()
var _key_region: Dictionary = {}


func reset() -> void:
	_ready = false
	_origins = []
	_parts = []
	_region_groups = PackedInt32Array()
	_keys = PackedInt32Array()
	_bounds = PackedFloat64Array()
	_floor = PackedVector3Array()
	_floor_ends = PackedInt32Array()
	_obstacles = PackedVector3Array()
	_prefix_size = 0
	_bottom_ends = PackedInt32Array()
	_wall_ends = PackedInt32Array()
	_deck = PackedVector3Array()
	_deck_depths = PackedFloat64Array()
	_key_region = {}


## `parts` holds one [cells, groups, roles, depths, triangles, obstacles] per
## region in `origins` order; `aggregate` is their concatenation, and `dirty`
## names every region rebuilt since the previous call. Returns [floor, obstacles].
func resolve(origins: Array[Vector2i], parts: Array, aggregate: Array, dirty: Dictionary) -> Array:
	if not _ready or origins != _origins or parts.size() != _parts.size():
		return _full(origins, parts, aggregate)
	var changed := PackedInt32Array()
	var prefix_changed := false
	for r: int in origins.size():
		if not dirty.has(origins[r]): continue
		var old: Array = _parts[r]
		var now: Array = parts[r]
		for k: int in 5:
			if old[k] != now[k]:
				changed.append(r)
				break
		if old[5] != now[5]: prefix_changed = true
	last_changed_regions = changed.size()
	last_recomputed_groups = 0
	last_wall_groups = 0
	last_context_groups = 0
	if changed.is_empty():
		for r: int in origins.size(): _parts[r] = parts[r]
		if prefix_changed:
			var prefix: PackedVector3Array = aggregate[5]
			_obstacles = Native.splice_vector3([prefix, _obstacles], PackedInt32Array([0, 0, prefix.size(), 1, _prefix_size, _obstacles.size()]))
			_prefix_size = prefix.size()
		last_mode = "retained"
		return [_floor, _obstacles]
	return _update(origins, parts, aggregate, changed, prefix_changed)


func _full(origins: Array[Vector2i], parts: Array, aggregate: Array) -> Array:
	reset()
	last_mode = "full"
	var detail: Dictionary = Native.resolve_detailed(aggregate[0], aggregate[1], aggregate[2], aggregate[3], aggregate[4], true)
	var prefix: PackedVector3Array = aggregate[5]
	var bottoms: PackedVector3Array = detail.bottoms
	var walls: PackedVector3Array = detail.walls
	var floor: PackedVector3Array = detail.floor
	var obstacles := Native.splice_vector3([prefix, bottoms, walls], PackedInt32Array([0, 0, prefix.size(), 1, 0, bottoms.size(), 2, 0, walls.size()]))
	# Keep incremental state only when every group lies in exactly one region.
	var offsets := PackedInt32Array([0])
	for part: Array in parts: offsets.append(offsets[-1] + (part[3] as PackedFloat64Array).size())
	var keys: PackedInt32Array = detail.keys
	var first: PackedInt32Array = detail.first
	var last: PackedInt32Array = detail.last
	var group_count := first.size()
	var region_groups := PackedInt32Array()
	region_groups.resize(parts.size() + 1)
	var key_region: Dictionary = {}
	var region := 0
	for g: int in group_count:
		var owner := offsets.bsearch(first[g], false) - 1
		if owner != offsets.bsearch(last[g], false) - 1 or owner < region: return [floor, obstacles]
		while region < owner:
			region += 1
			region_groups[region] = g
		key_region[Vector3i(keys[g*3], keys[g*3+1], keys[g*3+2])] = owner
	while region < parts.size():
		region += 1
		region_groups[region] = group_count
	_origins = origins.duplicate()
	_parts = parts.duplicate()
	_region_groups = region_groups
	_keys = keys
	_bounds = detail.bounds
	_floor = floor
	_floor_ends = detail.floor_ends
	_obstacles = obstacles
	_prefix_size = prefix.size()
	_bottom_ends = detail.bottom_ends
	_wall_ends = detail.wall_ends
	_deck = detail.deck
	_deck_depths = detail.deck_depths
	_key_region = key_region
	_ready = true
	return [_floor, _obstacles]


static func _start(ends: PackedInt32Array, g: int) -> int:
	return 0 if g == 0 else ends[g-1]


static func _add_run(runs: PackedInt32Array, source: int, begin: int, end: int) -> void:
	if end <= begin: return
	var n := runs.size()
	if n > 0 and runs[n-3] == source and runs[n-1] == begin:
		runs[n-1] = end
		return
	runs.append(source)
	runs.append(begin)
	runs.append(end)


static func _overlaps(a: PackedFloat64Array, ai: int, b: PackedFloat64Array, bi: int) -> bool:
	return a[ai] - MARGIN <= b[bi+2] and b[bi] <= a[ai+2] + MARGIN and a[ai+1] - MARGIN <= b[bi+3] and b[bi+1] <= a[ai+3] + MARGIN


func _update(origins: Array[Vector2i], parts: Array, aggregate: Array, changed: PackedInt32Array, prefix_changed: bool) -> Array:
	# Exact group diff of each changed region; only changed groups re-resolve.
	var cells := PackedInt32Array()
	var groups := PackedInt32Array()
	var roles := PackedInt32Array()
	var depths := PackedFloat64Array()
	var triangles := PackedVector3Array()
	var diffs: Dictionary = {}
	var affected := PackedFloat64Array()
	for r: int in changed:
		var old: Array = _parts[r]
		var now: Array = parts[r]
		var diff: Dictionary = Native.diff_groups(old[0], old[1], old[2], old[3], old[4], now[0], now[1], now[2], now[3], now[4])
		diffs[r] = diff
		var subset: Array = diff.subset
		cells.append_array(subset[0])
		groups.append_array(subset[1])
		roles.append_array(subset[2])
		depths.append_array(subset[3])
		triangles.append_array(subset[4])
	var detail: Dictionary = Native.resolve_detailed(cells, groups, roles, depths, triangles, false)
	var a_keys: PackedInt32Array = detail.keys
	var a_bounds: PackedFloat64Array = detail.bounds
	var a_floor_ends: PackedInt32Array = detail.floor_ends
	var a_bottom_ends: PackedInt32Array = detail.bottom_ends
	var a_index: Dictionary = {}
	for g: int in a_keys.size() / 3: a_index[Vector3i(a_keys[g*3], a_keys[g*3+1], a_keys[g*3+2])] = g
	last_recomputed_groups = a_index.size()
	# New group order: source 0 = previous result, 1 = sub-problem A.
	var new_source := PackedInt32Array()
	var new_index := PackedInt32Array()
	var new_region_groups := PackedInt32Array([0])
	var seen: Dictionary = {}
	for r: int in origins.size():
		if not diffs.has(r):
			for g: int in range(_region_groups[r], _region_groups[r+1]):
				new_source.append(0)
				new_index.append(g)
			new_region_groups.append(new_source.size())
			continue
		var diff: Dictionary = diffs[r]
		var old_index: Dictionary = {}
		for g: int in range(_region_groups[r], _region_groups[r+1]):
			old_index[Vector3i(_keys[g*3], _keys[g*3+1], _keys[g*3+2])] = g
		var keys: PackedInt32Array = diff.keys
		var flags: PackedByteArray = diff.changed
		var previous := -1
		for n: int in flags.size():
			var key := Vector3i(keys[n*3], keys[n*3+1], keys[n*3+2])
			var owner: int = _key_region.get(key, r)
			# A key shared with another region breaks per-region group order.
			if owner != r or seen.has(key): return _full(origins, parts, aggregate)
			seen[key] = true
			if flags[n]:
				var g: int = a_index[key]
				new_source.append(1)
				new_index.append(g)
				if a_bottom_ends[g] > _start(a_bottom_ends, g): affected.append_array(a_bounds.slice(g*4, g*4+4))
				var old_g: int = old_index.get(key, -1)
				if old_g >= 0 and _bottom_ends[old_g] > _start(_bottom_ends, old_g): affected.append_array(_bounds.slice(old_g*4, old_g*4+4))
			else:
				var g: int = old_index[key]
				# Retained groups must keep their relative order.
				if g < previous: return _full(origins, parts, aggregate)
				previous = g
				new_source.append(0)
				new_index.append(g)
		var removed: PackedInt32Array = diff.removed
		for i: int in range(0, removed.size(), 3):
			var g: int = old_index[Vector3i(removed[i], removed[i+1], removed[i+2])]
			if _bottom_ends[g] > _start(_bottom_ends, g): affected.append_array(_bounds.slice(g*4, g*4+4))
		new_region_groups.append(new_source.size())
	var count := new_source.size()
	# Deck bounds of the new group list and a cell grid over them.
	var deck_bounds := PackedFloat64Array()
	deck_bounds.resize(count*4)
	var has_deck := PackedByteArray()
	has_deck.resize(count)
	var grid: Dictionary = {}
	for n: int in count:
		var g: int = new_index[n]
		var source_bounds := _bounds if new_source[n] == 0 else a_bounds
		var ends := _bottom_ends if new_source[n] == 0 else a_bottom_ends
		if ends[g] <= _start(ends, g): continue
		has_deck[n] = 1
		for k: int in 4: deck_bounds[n*4+k] = source_bounds[g*4+k]
		for y: int in range(floori(deck_bounds[n*4+1] - MARGIN), floori(deck_bounds[n*4+3] + MARGIN) + 1):
			for x: int in range(floori(deck_bounds[n*4] - MARGIN), floori(deck_bounds[n*4+2] + MARGIN) + 1):
				var cell := Vector2i(x, y)
				if not grid.has(cell): grid[cell] = []
				grid[cell].append(n)
	# W: deck groups near changed deck geometry. C: deck groups near W.
	var wall_groups: Dictionary = {}
	for i: int in range(0, affected.size(), 4):
		for n: int in _near(grid, affected, i):
			if _overlaps(affected, i, deck_bounds, n*4): wall_groups[n] = true
	var context: Dictionary = {}
	for n: int in wall_groups:
		for m: int in _near(grid, deck_bounds, n*4):
			if _overlaps(deck_bounds, n*4, deck_bounds, m*4): context[m] = true
	var context_order: Array = context.keys()
	context_order.sort()
	last_wall_groups = wall_groups.size()
	last_context_groups = context_order.size()
	# Sub-problem B: deck boundary walls of the context, in global order.
	var walls_b := PackedVector3Array()
	var wall_ends_b := PackedInt32Array()
	var context_position: Dictionary = {}
	if not context_order.is_empty():
		var deck_runs := PackedInt32Array()
		var depth_runs := PackedInt32Array()
		var deck_ends_b := PackedInt32Array()
		var total := 0
		for n: int in context_order:
			var g: int = new_index[n]
			var source: int = new_source[n]
			var ends := _bottom_ends if source == 0 else a_bottom_ends
			var begin := _start(ends, g)
			_add_run(deck_runs, source, begin, ends[g])
			_add_run(depth_runs, source, begin/3, ends[g]/3)
			total += ends[g] - begin
			deck_ends_b.append(total)
			context_position[n] = deck_ends_b.size() - 1
		var deck_b := Native.splice_vector3([_deck, detail.deck], deck_runs)
		var depths_b := Native.splice_float64([_deck_depths, detail.deck_depths], depth_runs)
		var boundaries: Dictionary = Native.resolve_boundaries(deck_b, depths_b, deck_ends_b)
		walls_b = boundaries.walls
		wall_ends_b = boundaries.wall_ends
	# Assemble the exact full result from retained and recomputed blocks.
	var a_floor: PackedVector3Array = detail.floor
	var a_bottoms: PackedVector3Array = detail.bottoms
	var old_bottoms_total: int = _bottom_ends[-1] if not _bottom_ends.is_empty() else 0
	var floor_runs := PackedInt32Array()
	var bottom_runs := PackedInt32Array()
	var wall_runs := PackedInt32Array()
	var deck_runs := PackedInt32Array()
	var depth_runs := PackedInt32Array()
	var keys := PackedInt32Array()
	var bounds := PackedFloat64Array()
	var floor_ends := PackedInt32Array()
	var bottom_ends := PackedInt32Array()
	var wall_ends := PackedInt32Array()
	keys.resize(count*3)
	bounds.resize(count*4)
	floor_ends.resize(count)
	bottom_ends.resize(count)
	wall_ends.resize(count)
	var floor_total := 0
	var bottom_total := 0
	var wall_total := 0
	var key_region: Dictionary = {}
	var region := 0
	for n: int in count:
		while new_region_groups[region+1] <= n: region += 1
		var g: int = new_index[n]
		var key: Vector3i
		if new_source[n] == 0:
			var begin := _start(_floor_ends, g)
			_add_run(floor_runs, 0, begin, _floor_ends[g])
			floor_total += _floor_ends[g] - begin
			begin = _start(_bottom_ends, g)
			_add_run(bottom_runs, 0, _prefix_size + begin, _prefix_size + _bottom_ends[g])
			_add_run(deck_runs, 0, begin, _bottom_ends[g])
			_add_run(depth_runs, 0, begin/3, _bottom_ends[g]/3)
			bottom_total += _bottom_ends[g] - begin
			key = Vector3i(_keys[g*3], _keys[g*3+1], _keys[g*3+2])
			for k: int in 4: bounds[n*4+k] = _bounds[g*4+k]
			if not wall_groups.has(n):
				begin = _start(_wall_ends, g)
				_add_run(wall_runs, 0, _prefix_size + old_bottoms_total + begin, _prefix_size + old_bottoms_total + _wall_ends[g])
				wall_total += _wall_ends[g] - begin
		else:
			var begin := _start(a_floor_ends, g)
			_add_run(floor_runs, 1, begin, a_floor_ends[g])
			floor_total += a_floor_ends[g] - begin
			begin = _start(a_bottom_ends, g)
			_add_run(bottom_runs, 1, begin, a_bottom_ends[g])
			_add_run(deck_runs, 1, begin, a_bottom_ends[g])
			_add_run(depth_runs, 1, begin/3, a_bottom_ends[g]/3)
			bottom_total += a_bottom_ends[g] - begin
			key = Vector3i(a_keys[g*3], a_keys[g*3+1], a_keys[g*3+2])
			for k: int in 4: bounds[n*4+k] = a_bounds[g*4+k]
			# A changed group with deck geometry always lies within W.
			if has_deck[n] and not wall_groups.has(n): return _full(origins, parts, aggregate)
		if wall_groups.has(n):
			var c: int = context_position[n]
			var begin := _start(wall_ends_b, c)
			_add_run(wall_runs, 2, begin, wall_ends_b[c])
			wall_total += wall_ends_b[c] - begin
		keys[n*3] = key.x
		keys[n*3+1] = key.y
		keys[n*3+2] = key.z
		floor_ends[n] = floor_total
		bottom_ends[n] = bottom_total
		wall_ends[n] = wall_total
		key_region[key] = region
	var prefix_runs := PackedInt32Array()
	var prefix_source: PackedVector3Array = aggregate[5] if prefix_changed else _obstacles
	_add_run(prefix_runs, 3, 0, prefix_source.size() if prefix_changed else _prefix_size)
	prefix_runs.append_array(bottom_runs)
	prefix_runs.append_array(wall_runs)
	var obstacles := Native.splice_vector3([_obstacles, a_bottoms, walls_b, prefix_source], prefix_runs)
	var floor := Native.splice_vector3([_floor, a_floor], floor_runs)
	var deck := Native.splice_vector3([_deck, detail.deck], deck_runs)
	var deck_depths := Native.splice_float64([_deck_depths, detail.deck_depths], depth_runs)
	_prefix_size = prefix_source.size() if prefix_changed else _prefix_size
	_parts = parts.duplicate()
	_region_groups = new_region_groups
	_keys = keys
	_bounds = bounds
	_floor = floor
	_floor_ends = floor_ends
	_obstacles = obstacles
	_bottom_ends = bottom_ends
	_wall_ends = wall_ends
	_deck = deck
	_deck_depths = deck_depths
	_key_region = key_region
	last_mode = "incremental"
	return [_floor, _obstacles]


## Group indices whose grid cells meet the MARGIN-grown box at `at`.
static func _near(grid: Dictionary, boxes: PackedFloat64Array, at: int) -> Dictionary:
	var result: Dictionary = {}
	for y: int in range(floori(boxes[at+1] - MARGIN), floori(boxes[at+3] + MARGIN) + 1):
		for x: int in range(floori(boxes[at] - MARGIN), floori(boxes[at+2] + MARGIN) + 1):
			for n: int in grid.get(Vector2i(x, y), []): result[n] = true
	return result
