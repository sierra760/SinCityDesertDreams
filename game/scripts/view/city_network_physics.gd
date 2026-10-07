# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Resolves overlapping network surface triangles into physical floor and
## deck-wall faces. Spatial bins only skip predicates for distant candidates;
## they never change which faces are produced or their order.
extends RefCounted

const BIN_SCALE := 32
const COARSE_BIN_SCALE := 4
const DENSE_LIMIT := 0.125
## Generous relative to the 1e-6 edge predicate, including float32 error.
const CANDIDATE_PAD := 0.0001

## Per-call table of projected deck triangles. Vectors stay float32 and the
## predicate scalars float64; source triangles are kept for _patch_point.
class PackedDeckTriangles extends RefCounted:
	var triangles: Array[PackedVector3Array]
	var projected := PackedVector2Array()
	var values := PackedFloat64Array()
	var flats := PackedByteArray()
	func _init(source: Array[PackedVector3Array]) -> void:
		triangles = source
		projected.resize(source.size()*6)
		values.resize(source.size()*5)
		flats.resize(source.size())
		for index: int in source.size():
			var points: PackedVector3Array = source[index]
			flats[index] = int(points[0].y==points[1].y and points[0].y==points[2].y)
			var a := Vector2(points[0].x,points[0].z)
			var b := Vector2(points[1].x,points[1].z)
			var c := Vector2(points[2].x,points[2].z)
			var ab := b-a; var bc := c-b; var ca := a-c
			var area := ab.cross(c-a)
			var sign_value := 1.0 if area>0 else -1.0
			var ab_limit := -0.000002*ab.length()
			var bc_limit := -0.000002*bc.length()
			var ca_limit := -0.000002*ca.length()
			var vector_offset := index*6
			projected[vector_offset] = a;projected[vector_offset+1] = b;projected[vector_offset+2] = c
			projected[vector_offset+3] = ab;projected[vector_offset+4] = bc;projected[vector_offset+5] = ca
			var scalar_offset := index*5
			values[scalar_offset] = area;values[scalar_offset+1] = sign_value
			values[scalar_offset+2] = ab_limit;values[scalar_offset+3] = bc_limit;values[scalar_offset+4] = ca_limit

static func resolve(patch_inputs: Array[Dictionary], box_inputs: Array[Dictionary], obstacle_inputs: PackedVector3Array) -> Dictionary:
	var groups: Dictionary = {}
	for patch: Dictionary in patch_inputs:
		var key := Vector3i(patch.cell.x, patch.cell.y, patch.group)
		if not groups.has(key): groups[key] = []
		groups[key].append(patch)
	var partition_cache: Dictionary = {}
	var floor := PackedVector3Array()
	var obstacles := obstacle_inputs.duplicate()
	var deck_points := PackedVector3Array()
	var deck_depths := PackedFloat64Array()
	var deck_triangles: Array[PackedVector3Array] = []
	for patches: Array in groups.values():
		patches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.role > b.role)
		# Work near the origin: repeated float32 clipping at far city coordinates
		# otherwise opens micrometre seams along internal arc subdivisions.
		var origin := Vector2(patches[0].cell)
		var polygons: Array[PackedVector2Array] = []
		for patch: Dictionary in patches:
			var polygon := PackedVector2Array()
			for p: Vector3 in patch.triangle: polygon.append(Vector2(p.x,p.z)-origin)
			polygons.append(polygon)
		# Repeated road shapes have identical local clipping inputs. The cache
		# compares the full polygons after hashing, so nothing is quantized.
		var key := hash(polygons)
		var cached: Dictionary = partition_cache.get(key,{})
		var partitions: Array
		if not cached.is_empty() and cached.polygons==polygons:
			partitions = cached.partitions
		else:
			partitions = _partition_polygons(polygons)
			partition_cache[key] = {"polygons":polygons,"partitions":partitions}
		for index: int in patches.size():
			var patch: Dictionary = patches[index]
			var triangle: PackedVector3Array = patch.triangle
			var pieces: Array = partitions[index]
			for piece: PackedVector2Array in pieces:
				for i: int in range(1, piece.size()-1):
					var a := _patch_point(triangle, piece[0]+origin)
					var b := _patch_point(triangle, piece[i]+origin)
					var c := _patch_point(triangle, piece[i+1]+origin)
					if absf((b-a).cross(c-a).y) < 0.000000001: continue
					if (b-a).cross(c-a).y > 0:
						var swap := b; b = c; c = swap
					floor.append_array(PackedVector3Array([a,b,c]))
					var depth: float = patch.depth
					if depth > 0:
						deck_triangles.append(PackedVector3Array([a,b,c]))
						var down := Vector3.DOWN * depth
						obstacles.append_array(PackedVector3Array([c+down,b+down,a+down]))
						for edge: Array in [[a,b],[b,c],[c,a]]:
							deck_points.append(edge[0]);deck_points.append(edge[1]);deck_depths.append(depth)
	_append_numeric_deck_boundaries(deck_points, deck_depths, deck_triangles, obstacles)
	return {"physical_floor_faces": floor, "physical_obstacle_faces": obstacles,
		"physical_boxes": box_inputs.duplicate(true)}


## Per-group results of the same resolution, for exact incremental reuse.
## Group keys follow first appearance; each group owns its floor, deck-bottom
## and deck triangles (one depth per deck triangle), deck XZ bounds and, when
## requested, the boundary walls whose segment key first appears in it.
## Concatenated blocks reproduce resolve(): floor = floor, obstacles =
## inputs + bottoms + walls.
static func resolve_detailed(cells: PackedInt32Array, group_ids: PackedInt32Array, roles: PackedInt32Array, depths: PackedFloat64Array, triangles: PackedVector3Array, with_walls: bool) -> Dictionary:
	var count := depths.size()
	var slots: Dictionary = {}
	var patch_group := PackedInt32Array()
	patch_group.resize(count)
	var sizes := PackedInt32Array()
	var keys := PackedInt32Array()
	for index: int in count:
		var key := Vector3i(cells[index*2],cells[index*2+1],group_ids[index])
		var slot: int = slots.get(key,-1)
		if slot < 0:
			slot = sizes.size()
			slots[key] = slot
			sizes.append(0)
			keys.append(key.x);keys.append(key.y);keys.append(key.z)
		patch_group[index] = slot
		sizes[slot] += 1
	var group_count := sizes.size()
	var starts := PackedInt32Array()
	starts.resize(group_count+1)
	for g: int in group_count: starts[g+1] = starts[g]+sizes[g]
	var fill := starts.duplicate()
	var order := PackedInt32Array()
	order.resize(count)
	for index: int in count:
		var g: int = patch_group[index]
		order[fill[g]] = index
		fill[g] += 1
	var first := PackedInt32Array(); first.resize(group_count)
	var last := PackedInt32Array(); last.resize(group_count)
	var bounds := PackedFloat64Array(); bounds.resize(group_count*4)
	var floor := PackedVector3Array()
	var bottoms := PackedVector3Array()
	var deck := PackedVector3Array()
	var deck_depths := PackedFloat64Array()
	var floor_ends := PackedInt32Array(); floor_ends.resize(group_count)
	var bottom_ends := PackedInt32Array(); bottom_ends.resize(group_count)
	var partition_cache: Dictionary = {}
	for g: int in group_count:
		var patches: Array = Array(order.slice(starts[g],starts[g+1]))
		first[g] = patches[0]
		last[g] = patches[-1]
		patches.sort_custom(func(a: int, b: int) -> bool: return roles[a] > roles[b])
		var origin := Vector2(cells[patches[0]*2],cells[patches[0]*2+1])
		var polygons: Array[PackedVector2Array] = []
		for patch: int in patches:
			var polygon := PackedVector2Array()
			for k: int in 3:
				var p: Vector3 = triangles[patch*3+k]
				polygon.append(Vector2(p.x,p.z)-origin)
			polygons.append(polygon)
		var key := hash(polygons)
		var cached: Dictionary = partition_cache.get(key,{})
		var partitions: Array
		if not cached.is_empty() and cached.polygons==polygons:
			partitions = cached.partitions
		else:
			partitions = _partition_polygons(polygons)
			partition_cache[key] = {"polygons":polygons,"partitions":partitions}
		var deck_begin := deck.size()
		for index: int in patches.size():
			var patch: int = patches[index]
			var triangle := triangles.slice(patch*3,patch*3+3)
			var depth: float = depths[patch]
			var pieces: Array = partitions[index]
			for piece: PackedVector2Array in pieces:
				for i: int in range(1, piece.size()-1):
					var a := _patch_point(triangle, piece[0]+origin)
					var b := _patch_point(triangle, piece[i]+origin)
					var c := _patch_point(triangle, piece[i+1]+origin)
					if absf((b-a).cross(c-a).y) < 0.000000001: continue
					if (b-a).cross(c-a).y > 0:
						var swap := b; b = c; c = swap
					floor.append_array(PackedVector3Array([a,b,c]))
					if depth > 0:
						deck.append_array(PackedVector3Array([a,b,c]))
						deck_depths.append(depth)
						var down := Vector3.DOWN * depth
						bottoms.append_array(PackedVector3Array([c+down,b+down,a+down]))
		floor_ends[g] = floor.size()
		bottom_ends[g] = bottoms.size()
		if deck.size() > deck_begin:
			bounds[g*4] = deck_bound(deck,deck_begin,0,true)
			bounds[g*4+1] = deck_bound(deck,deck_begin,2,true)
			bounds[g*4+2] = deck_bound(deck,deck_begin,0,false)
			bounds[g*4+3] = deck_bound(deck,deck_begin,2,false)
	var walls := PackedVector3Array()
	var wall_ends := PackedInt32Array(); wall_ends.resize(group_count)
	if with_walls:
		var boundaries := resolve_boundaries(deck,deck_depths,bottom_ends)
		walls = boundaries.walls
		wall_ends = boundaries.wall_ends
	return {"keys":keys,"first":first,"last":last,"bounds":bounds,"floor":floor,"floor_ends":floor_ends,
		"bottoms":bottoms,"bottom_ends":bottom_ends,"deck":deck,"deck_depths":deck_depths,"walls":walls,"wall_ends":wall_ends}


## Group-by-group comparison of two patch sets (see the native diff_groups):
## new keys in first-appearance order, a changed flag per new group, vanished
## old keys and the new patches of changed groups in input order. Values are
## compared bit for bit.
static func diff_groups(old_cells: PackedInt32Array, old_groups: PackedInt32Array, old_roles: PackedInt32Array, old_depths: PackedFloat64Array, old_triangles: PackedVector3Array,
		cells: PackedInt32Array, group_ids: PackedInt32Array, roles: PackedInt32Array, depths: PackedFloat64Array, triangles: PackedVector3Array) -> Dictionary:
	var before := _members(old_cells, old_groups)
	var after := _members(cells, group_ids)
	var before_index: Dictionary = before[2]
	var keys := PackedInt32Array()
	var changed := PackedByteArray()
	var kept: Dictionary = {}
	var subset := PackedInt32Array()
	for g: int in (after[0] as Array).size():
		var key: Vector3i = after[0][g]
		keys.append(key.x);keys.append(key.y);keys.append(key.z)
		var members: PackedInt32Array = after[1][g]
		var same := before_index.has(key)
		if same:
			kept[key] = true
			var old_members: PackedInt32Array = before[1][before_index[key]]
			same = old_members.size() == members.size() and _gather(old_roles, old_depths, old_triangles, old_members) == _gather(roles, depths, triangles, members)
		changed.append(0 if same else 1)
		if not same: subset.append_array(members)
	var removed := PackedInt32Array()
	for key: Vector3i in before[0]:
		if not kept.has(key): removed.append(key.x);removed.append(key.y);removed.append(key.z)
	subset.sort()
	var subset_cells := PackedInt32Array()
	var subset_groups := PackedInt32Array()
	var subset_roles := PackedInt32Array()
	var subset_depths := PackedFloat64Array()
	var subset_triangles := PackedVector3Array()
	for p: int in subset:
		subset_cells.append(cells[p*2]);subset_cells.append(cells[p*2+1])
		subset_groups.append(group_ids[p]);subset_roles.append(roles[p]);subset_depths.append(depths[p])
		subset_triangles.append(triangles[p*3]);subset_triangles.append(triangles[p*3+1]);subset_triangles.append(triangles[p*3+2])
	return {"keys":keys,"changed":changed,"removed":removed,"subset":[subset_cells,subset_groups,subset_roles,subset_depths,subset_triangles]}


## [keys in first-appearance order, member index lists, key -> slot].
static func _members(cells: PackedInt32Array, group_ids: PackedInt32Array) -> Array:
	var slots: Dictionary = {}
	var keys: Array[Vector3i] = []
	var members: Array[PackedInt32Array] = []
	var patch_group := PackedInt32Array()
	patch_group.resize(group_ids.size())
	var sizes := PackedInt32Array()
	for index: int in group_ids.size():
		var key := Vector3i(cells[index*2],cells[index*2+1],group_ids[index])
		var slot: int = slots.get(key,-1)
		if slot < 0:
			slot = keys.size()
			slots[key] = slot
			keys.append(key)
			sizes.append(0)
		patch_group[index] = slot
		sizes[slot] += 1
	var starts := PackedInt32Array([0])
	for size: int in sizes: starts.append(starts[-1]+size)
	var fill := starts.duplicate()
	var order := PackedInt32Array()
	order.resize(group_ids.size())
	for index: int in group_ids.size():
		var g: int = patch_group[index]
		order[fill[g]] = index
		fill[g] += 1
	for g: int in keys.size(): members.append(order.slice(starts[g],starts[g+1]))
	return [keys,members,slots]


## Exact bit image of one group's ordered patch values.
static func _gather(roles: PackedInt32Array, depths: PackedFloat64Array, triangles: PackedVector3Array, members: PackedInt32Array) -> PackedByteArray:
	var group_roles := PackedInt32Array()
	var group_depths := PackedFloat64Array()
	var group_triangles := PackedVector3Array()
	for p: int in members:
		group_roles.append(roles[p]);group_depths.append(depths[p])
		group_triangles.append(triangles[p*3]);group_triangles.append(triangles[p*3+1]);group_triangles.append(triangles[p*3+2])
	var bytes := group_roles.to_byte_array()
	bytes.append_array(group_depths.to_byte_array())
	bytes.append_array(group_triangles.to_byte_array())
	return bytes


## Extreme deck coordinate (axis 0 = x, 2 = z) from `begin` to the end, as
## float64 values of the float32 points.
static func deck_bound(deck: PackedVector3Array, begin: int, axis: int, minimum: bool) -> float:
	var result: float = deck[begin][axis]
	for i: int in range(begin,deck.size()):
		var value: float = deck[i][axis]
		result = minf(result,value) if minimum else maxf(result,value)
	return result


## Deck boundary walls of an ordered subset of groups; `deck_ends` holds the
## cumulative deck point count of each group. Edges follow resolve() order.
static func resolve_boundaries(deck: PackedVector3Array, deck_depths: PackedFloat64Array, deck_ends: PackedInt32Array) -> Dictionary:
	var points := PackedVector3Array()
	var depths := PackedFloat64Array()
	var edge_groups := PackedInt32Array()
	var triangles: Array[PackedVector3Array] = []
	var group := 0
	for t: int in deck_depths.size():
		while group < deck_ends.size() and deck_ends[group] <= t*3: group += 1
		var a: Vector3 = deck[t*3]; var b: Vector3 = deck[t*3+1]; var c: Vector3 = deck[t*3+2]
		var depth: float = deck_depths[t]
		triangles.append(PackedVector3Array([a,b,c]))
		for edge: Array in [[a,b],[b,c],[c,a]]:
			points.append(edge[0]);points.append(edge[1]);depths.append(depth);edge_groups.append(group)
	var walls := PackedVector3Array()
	var wall_ends := PackedInt32Array()
	wall_ends.resize(deck_ends.size())
	if not edge_groups.is_empty(): _append_numeric_deck_boundaries(points,depths,triangles,walls,edge_groups,wall_ends)
	return {"walls":walls,"wall_ends":wall_ends}


static func _partition_polygons(polygons: Array[PackedVector2Array]) -> Array:
	var occupied: Array[PackedVector2Array] = []
	var occupied_bounds: Array[Rect2] = []
	# Curved approaches contain thousands of disjoint little triangles in one
	# cell. Preserve subtraction order, but only visit overlapping AABB bins.
	var indexed := polygons.size() > 64
	var bins: Dictionary = {}
	var broad: Array[int] = []
	var result: Array = []
	for polygon: PackedVector2Array in polygons:
		var polygon_bounds := _polygon_bounds(polygon)
		var pieces: Array[PackedVector2Array] = [polygon]
		var cells := _partition_cells(polygon_bounds) if indexed else Rect2i()
		var candidates: Array[int] = []
		if indexed and cells.get_area() <= 4096:
			var seen: Dictionary = {}
			for index: int in broad: seen[index] = true
			for y: int in range(cells.position.y,cells.end.y):
				for x: int in range(cells.position.x,cells.end.x):
					for index: int in bins.get(Vector2i(x,y),[]): seen[index] = true
			candidates.assign(seen.keys())
			candidates.sort()
		else:
			for index: int in occupied.size(): candidates.append(index)
		for cut_index: int in candidates:
			var cut := occupied[cut_index]
			var cut_bounds := occupied_bounds[cut_index]
			if not polygon_bounds.intersects(cut_bounds): continue
			var rest: Array[PackedVector2Array] = []
			for piece: PackedVector2Array in pieces: rest.append_array(_subtract_triangle(piece,cut,cut_bounds))
			pieces = rest
			if pieces.is_empty(): break
		if indexed:
			var index := occupied.size()
			if cells.get_area() > 4096:
				broad.append(index)
			else:
				for y: int in range(cells.position.y,cells.end.y):
					for x: int in range(cells.position.x,cells.end.x):
						var key := Vector2i(x,y)
						if not bins.has(key): bins[key] = []
						bins[key].append(index)
		occupied.append(polygon)
		occupied_bounds.append(polygon_bounds)
		result.append(pieces)
	return result


static func _partition_cells(bounds: Rect2) -> Rect2i:
	var start := Vector2i(floori(bounds.position.x*16),floori(bounds.position.y*16))
	var end := Vector2i(floori(bounds.end.x*16)+1,floori(bounds.end.y*16)+1)
	return Rect2i(start,end-start)


static func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0], Vector2.ZERO)
	for p: Vector2 in polygon: result = result.expand(p)
	return result


## Convex half-plane subtraction produces simple pieces, including when the
## cut is wholly inside its subject. It never mistakes a hole ring for a floor.
static func _subtract_triangle(polygon: PackedVector2Array, cut: PackedVector2Array, cut_bounds: Rect2) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = []
	if not _polygon_bounds(polygon).intersects(cut_bounds): return [polygon]
	var remainder := polygon
	var sign_value := -1.0 if (cut[1]-cut[0]).cross(cut[2]-cut[0]) < 0 else 1.0
	for i: int in 3:
		var a := cut[i]; var delta := cut[(i+1)%3]-a
		var outside := _clip_physical_plane(remainder, a, delta, -sign_value)
		if _physical_polygon_area(outside) > 0.000000001: pieces.append(outside)
		remainder = _clip_physical_plane(remainder, a, delta, sign_value)
		if _physical_polygon_area(remainder) < 0.000000001: break
	return pieces


static func _physical_polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i: int in range(1, polygon.size()-1): area += (polygon[i]-polygon[0]).cross(polygon[i+1]-polygon[0])
	return absf(area)*0.5


static func _clip_physical_plane(polygon: PackedVector2Array, origin: Vector2, edge: Vector2, sign_value: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	if polygon.is_empty(): return result
	var previous := polygon[-1]
	var before := edge.cross(previous-origin)*sign_value
	for current: Vector2 in polygon:
		var now := edge.cross(current-origin)*sign_value
		if (before >= 0) != (now >= 0): result.append(previous.lerp(current, before/(before-now)))
		if now >= 0: result.append(current)
		previous = current; before = now
	return result


static func _patch_point(triangle: PackedVector3Array, p: Vector2) -> Vector3:
	var a := triangle[0]; var b := triangle[1]; var c := triangle[2]
	if a.y==b.y and a.y==c.y: return Vector3(p.x,a.y,p.y)
	var ab := Vector2(b.x-a.x,b.z-a.z); var ac := Vector2(c.x-a.x,c.z-a.z)
	var ap := p-Vector2(a.x,a.z)
	var area := ab.cross(ac)
	return Vector3(p.x, a.y+(b.y-a.y)*ap.cross(ac)/area+(c.y-a.y)*ab.cross(ap)/area, p.y)


## Takes edges as {a, b, depth} records; see _append_numeric_deck_boundaries.
static func _append_deck_boundaries(edges: Array[Dictionary], triangles: Array[PackedVector3Array], faces: PackedVector3Array) -> void:
	var points := PackedVector3Array()
	var depths := PackedFloat64Array()
	for edge: Dictionary in edges:
		points.append(edge.a);points.append(edge.b);depths.append(edge.depth)
	_append_numeric_deck_boundaries(points,depths,triangles,faces)


## Split at projected T junctions before cancellation. Adjacent terrain facets,
## block quadrants and material strips can triangulate the same boundary with
## different subdivisions. Only exposed boundaries receive full-depth walls.
## `edge_groups` (one non-decreasing group index per edge) and `wall_ends`
## (one cumulative wall point count per group) are optional bookkeeping for the
## incremental resolver and never change the emitted faces. Walls of one
## quantized segment key belong to the group of the key's first segment.
static func _append_numeric_deck_boundaries(points: PackedVector3Array, depths: PackedFloat64Array, triangles: Array[PackedVector3Array], faces: PackedVector3Array, edge_groups: PackedInt32Array = PackedInt32Array(), wall_ends: PackedInt32Array = PackedInt32Array()) -> void:
	var triangle_bins: Dictionary = {}
	var prepared := PackedDeckTriangles.new(triangles)
	for triangle_index: int in triangles.size():
		var triangle: PackedVector3Array = triangles[triangle_index]
		var polygon := PackedVector2Array()
		for p: Vector3 in triangle: polygon.append(Vector2(p.x,p.z))
		var bounds := _polygon_bounds(polygon)
		# The half-plane tolerance extends acute tips beyond their AABB.
		# A uniform outward offset expands a triangle about its incenter by
		# offset/inradius. Bounding vertex travel by its longest edge gives a
		# conservative extent, including needle triangles. Admit whole unit
		# cells first, then narrow candidates inside those cells.
		var area: float = prepared.values[triangle_index*5]
		if absf(area)<0.000000001: continue
		var vector_offset := triangle_index*6
		var lengths := Vector3(prepared.projected[vector_offset+3].length(),prepared.projected[vector_offset+4].length(),prepared.projected[vector_offset+5].length())
		var margin := .00005*(lengths.x+lengths.y+lengths.z)*maxf(lengths.x,maxf(lengths.y,lengths.z))/absf(area)+CANDIDATE_PAD
		var expanded := bounds.grow(margin)
		# Dense curve facets benefit from fine buckets. Broad flat facets must
		# not fill thousands of those buckets merely to answer a few probes.
		var scale := BIN_SCALE if maxf(expanded.size.x,expanded.size.y)<DENSE_LIMIT else COARSE_BIN_SCALE
		if scale==COARSE_BIN_SCALE: triangle_bins["coarse"] = true
		for x: int in range(floori(bounds.position.x),floori(bounds.end.x)+1):
			for z: int in range(floori(bounds.position.y),floori(bounds.end.y)+1):
				for fine_x: int in range(maxi(x*scale,floori(expanded.position.x*scale)),mini((x+1)*scale-1,floori(expanded.end.x*scale))+1):
					for fine_z: int in range(maxi(z*scale,floori(expanded.position.y*scale)),mini((z+1)*scale-1,floori(expanded.end.y*scale))+1):
						var key := Vector3i(fine_x,fine_z,scale)
						if not triangle_bins.has(key): triangle_bins[key] = []
						triangle_bins[key].append(triangle_index)
	var vertices: Dictionary = {}
	for index: int in depths.size():
		for p: Vector3 in [points[index*2],points[index*2+1]]:
			var bin := Vector2i(floori(p.x),floori(p.z))
			if not vertices.has(bin): vertices[bin] = {}
			vertices[bin][_edge_key(p)] = Vector2(p.x,p.z)
	# De-duplicate quantized vertices per unit cell, then rebin the surviving
	# values finely. Sorting the cuts below keeps the output independent of
	# candidate traversal order.
	var fine_vertices: Dictionary = {}
	var coarse_vertices := triangle_bins.has("coarse")
	for bucket: Dictionary in vertices.values():
		for p: Vector2 in bucket.values():
			var key := Vector3i(floori(p.x*BIN_SCALE),floori(p.y*BIN_SCALE),BIN_SCALE)
			if not fine_vertices.has(key): fine_vertices[key] = []
			fine_vertices[key].append(p)
			if coarse_vertices:
				key = Vector3i(floori(p.x*COARSE_BIN_SCALE),floori(p.y*COARSE_BIN_SCALE),COARSE_BIN_SCALE)
				if not fine_vertices.has(key): fine_vertices[key] = []
				fine_vertices[key].append(p)
	var cuts_cache: Dictionary = {}
	var segments: Dictionary = {}
	var segment_points := PackedVector3Array()
	var segment_depths := PackedFloat64Array()
	var tracking := not edge_groups.is_empty()
	var segment_groups := PackedInt32Array()
	for index: int in depths.size():
		var a: Vector3=points[index*2];var b: Vector3=points[index*2+1]
		var depth: float=depths[index]
		var start:=Vector2(a.x,a.z);var delta:=Vector2(b.x-a.x,b.z-a.z)
		var length_squared:=delta.length_squared()
		if length_squared<0.0000000001: continue
		var projection_key := Vector4(a.x,a.z,b.x,b.z)
		var cuts: Array[float]
		if cuts_cache.has(projection_key):
			cuts = cuts_cache[projection_key]
		else:
			cuts = [0.0,1.0]
			var cross_limit := 0.000001*sqrt(length_squared)
			var scale := COARSE_BIN_SCALE if coarse_vertices and maxf(absf(delta.x),absf(delta.y))>=DENSE_LIMIT else BIN_SCALE
			for x: int in range(floori((minf(a.x,b.x)-CANDIDATE_PAD)*scale),floori((maxf(a.x,b.x)+CANDIDATE_PAD)*scale)+1):
				for z: int in range(floori((minf(a.z,b.z)-CANDIDATE_PAD)*scale),floori((maxf(a.z,b.z)+CANDIDATE_PAD)*scale)+1):
					for p: Vector2 in fine_vertices.get(Vector3i(x,z,scale),[]):
						var t: float=(p-start).dot(delta)/length_squared
						if t>0.00001 and t<0.99999 and absf(delta.cross(p-start))<cross_limit: cuts.append(t)
			cuts.sort()
			cuts_cache[projection_key] = cuts
		for i: int in range(cuts.size()-1):
			if cuts[i+1]-cuts[i]<0.000001: continue
			var p:=a.lerp(b,cuts[i]);var q:=a.lerp(b,cuts[i+1])
			var pk:=_edge_key(p);var qk:=_edge_key(q)
			if pk==qk: continue
			if pk.x>qk.x or (pk.x==qk.x and pk.y>qk.y):
				var swap:=p;p=q;q=swap
				var key_swap:=pk;pk=qk;qk=key_swap
			var key:=Vector4i(pk.x,pk.y,qk.x,qk.y)
			if not segments.has(key): segments[key]=[]
			segments[key].append(segment_depths.size())
			segment_points.append(p);segment_points.append(q);segment_depths.append(depth)
			if tracking: segment_groups.append(edge_groups[index])
	var wall_start := faces.size()
	var wall_group := 0
	for matches: Array in segments.values():
		if tracking:
			var owner: int = segment_groups[matches[0]]
			while wall_group < owner and wall_group < wall_ends.size():
				wall_ends[wall_group] = faces.size()-wall_start
				wall_group += 1
		if matches.size()==1:
			var index: int=matches[0]
			var a: Vector3=segment_points[index*2];var b: Vector3=segment_points[index*2+1]
			var depth: float=segment_depths[index]
			if _packed_deck_edge_is_internal_points(a,b,triangle_bins,prepared): continue
			_side_wall(faces,a,b,a+Vector3.DOWN*depth,b+Vector3.DOWN*depth)
		elif matches.size()==2:
			var first: int=matches[0];var second: int=matches[1]
			var first_a: Vector3=segment_points[first*2];var first_b: Vector3=segment_points[first*2+1]
			var second_a: Vector3=segment_points[second*2];var second_b: Vector3=segment_points[second*2+1]
			var first_depth: float=segment_depths[first];var second_depth: float=segment_depths[second]
			if maxf(absf(first_a.y-second_a.y),absf(first_b.y-second_b.y))<0.03:
				_side_wall(faces,first_a,first_b,second_a,second_b)
				_side_wall(faces,first_a+Vector3.DOWN*first_depth,first_b+Vector3.DOWN*first_depth,
					second_a+Vector3.DOWN*second_depth,second_b+Vector3.DOWN*second_depth)
			else:
				for index: int in matches:
					var a: Vector3=segment_points[index*2];var b: Vector3=segment_points[index*2+1]
					var depth: float=segment_depths[index]
					_side_wall(faces,a,b,a+Vector3.DOWN*depth,b+Vector3.DOWN*depth)
	while wall_group < wall_ends.size():
		wall_ends[wall_group] = faces.size()-wall_start
		wall_group += 1


## The probe offset is below 1 mm at the adopted world scale and exceeds
## float32 rounding at the city boundary. It tests both sides against actual
## elevated faces near this edge's height, never against a different overpass.
static func _packed_deck_edge_is_internal_points(a: Vector3, b: Vector3, bins: Dictionary, prepared: PackedDeckTriangles) -> bool:
	var midpoint := (a+b)*0.5
	var direction := Vector2(b.x-a.x,b.z-a.z).normalized()
	var across := Vector2(-direction.y,direction.x)*0.00004
	var center := Vector2(midpoint.x,midpoint.z)
	return _packed_deck_covers(center+across, midpoint.y, bins, prepared) and _packed_deck_covers(center-across, midpoint.y, bins, prepared)


static func _packed_deck_covers(point: Vector2, height: float, bins: Dictionary, prepared: PackedDeckTriangles) -> bool:
	return _packed_deck_bin_covers(point,height,bins,prepared,BIN_SCALE) or (bins.has("coarse") and _packed_deck_bin_covers(point,height,bins,prepared,COARSE_BIN_SCALE))


static func _packed_deck_bin_covers(point: Vector2, height: float, bins: Dictionary, prepared: PackedDeckTriangles, scale: int) -> bool:
	var candidates: Array = bins.get(Vector3i(floori(point.x*scale),floori(point.y*scale),scale),[])
	var projected := prepared.projected
	var values := prepared.values
	for index: int in candidates:
		var scalar_offset := index*5
		if absf(values[scalar_offset])<0.000000001: continue
		var vector_offset := index*6
		var sign_value: float = values[scalar_offset+1]
		if projected[vector_offset+3].cross(point-projected[vector_offset])*sign_value < values[scalar_offset+2]: continue
		if projected[vector_offset+4].cross(point-projected[vector_offset+1])*sign_value < values[scalar_offset+3]: continue
		if projected[vector_offset+5].cross(point-projected[vector_offset+2])*sign_value < values[scalar_offset+4]: continue
		var triangle: PackedVector3Array = prepared.triangles[index]
		var surface_y: float = triangle[0].y if prepared.flats[index] else _patch_point(triangle,point).y
		if absf(surface_y-height)<0.03: return true
	return false

static func _edge_key(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x*100000),roundi(p.z*100000))


static func _side_wall(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	if a==c and b==d: return
	for triangle: PackedVector3Array in [PackedVector3Array([a,b,c]),PackedVector3Array([b,d,c])]:
		if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).length_squared()<0.000000000001: continue
		faces.append_array(triangle)
		faces.append_array(PackedVector3Array([triangle[2],triangle[1],triangle[0]]))
