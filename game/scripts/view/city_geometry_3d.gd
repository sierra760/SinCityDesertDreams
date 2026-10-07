# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Read-only terrain meshes shared by the aerial city view and its picking surface.
class_name CityGeometry3D
extends RefCounted

## Relief matches 12 vertical pixels per level on the 32-by-16 isometric tile.
const HEIGHT := 0.6123724357
const WATER_COLOR := Color("5fa49d")
const GRAIN := preload("res://assets/desert-dreams-3d/textures/connected-materials.png")
const SAND_TEXTURE := preload("res://assets/desert-dreams-3d/textures/desert-sand.png")
const ROCK_TEXTURE := preload("res://assets/desert-dreams-3d/textures/desert-rock.png")
const ROAD_TEXTURE := preload("res://assets/desert-dreams-3d/textures/road-grain.png")
enum SurfaceKind { TERRAIN, NETWORK, DETAIL }
enum PhysicalRole { FLOOR, OBSTACLE, WATER }
static var _surface_shader: Shader
static var _face_materials: Dictionary = {}



## Corners in NW, NE, SW, SE order, in city coordinates.
static func cell_corners(city: City, cell: Vector2i) -> PackedVector3Array:
	var base := city.ground_height(cell.x, cell.y)
	var heights := PackedInt32Array([base, base, base, base])
	if city.terrain_surface is TerrainSurface:
		var surface: TerrainSurface = city.terrain_surface
		heights = PackedInt32Array([surface.vertex(cell.x, cell.y), surface.vertex(cell.x + 1, cell.y),
			surface.vertex(cell.x, cell.y + 1), surface.vertex(cell.x + 1, cell.y + 1)])
	else:
		var code := city.terrain.atv(cell)
		var mask := 0 if Terrain.water_kind(code) == Terrain.STREAM else Terrain.raised_corners(Terrain.slope(code))
		var corner_bits: Array[int] = [8, 1, 4, 2]
		for i: int in 4:
			heights[i] += 1 if mask & corner_bits[i] else 0
	return PackedVector3Array([Vector3(cell.x, heights[0] * HEIGHT, cell.y),
		Vector3(cell.x + 1, heights[1] * HEIGHT, cell.y),
		Vector3(cell.x, heights[2] * HEIGHT, cell.y + 1),
		Vector3(cell.x + 1, heights[3] * HEIGHT, cell.y + 1)])


## Shared dry corners for 3D only. Imported tile codes are independent samples;
## using each tile's reading creates vertical walls at otherwise ordinary grades.
## A vertex is resolved from its touching dry tiles in a fixed order. Level tiles
## supply level lot/road boundaries; otherwise the readings share their mean.
## Native editing lattices already share vertices and are used as they are.
## The one-cell dependency stays local so chunk edits can keep distant meshes.
static func ground_corners(city: City, cell: Vector2i) -> PackedVector3Array:
	if _ground_sampling_city == city and _ground_corner_cache.has(cell):
		return (_ground_corner_cache[cell] as PackedVector3Array).duplicate()
	var points := cell_corners(city,cell)
	if city.terrain_surface is TerrainSurface or city.is_water(cell.x,cell.y): return points
	for i: int in 4:
		points[i].y = _shared_dry_vertex(city,int(points[i].x),int(points[i].z))
	if _ground_sampling_city == city: _ground_corner_cache[cell] = points.duplicate()
	return points


## Short-lived read-only sampling scope. A renderer may reuse shared vertices
## within one synchronous geometry build, never across edits or public callbacks.
## Outside the scope all callers still read current city data directly.
static var _road_tunnel_cache: Dictionary = {}
static var _ground_sampling_city: City
static var _ground_vertex_cache: Dictionary = {}
static var _ground_corner_cache: Dictionary = {}
## Per-cell water presentation, cached only within a sampling scope in flat
## tables allocated on first use: classification flags (bit 7 marks a known
## entry), the four visible water corner heights, their center height and the
## surroundings of each lattice vertex. NaN marks an unknown height.
const _KNOWN := 0x80
static var _water_flow_table := PackedByteArray()
static var _water_corner_table := PackedFloat32Array()
static var _water_height_table := PackedFloat64Array()
static var _water_vertex_table := PackedByteArray()


static func _water_tables_ready() -> void:
	if not _water_flow_table.is_empty(): return
	_water_flow_table.resize(City.WIDTH * City.HEIGHT)
	_water_corner_table.resize(City.WIDTH * City.HEIGHT * 4)
	_water_corner_table.fill(NAN)
	_water_height_table.resize(City.WIDTH * City.HEIGHT)
	_water_height_table.fill(NAN)
	_water_vertex_table.resize((City.WIDTH + 1) * (City.HEIGHT + 1))


static func road_tunnel_profiles(city: City) -> Dictionary:
	if _ground_sampling_city == city:
		if _road_tunnel_cache.is_empty(): _road_tunnel_cache = {"profiles": preload("res://scripts/view/city_road_tunnels_3d.gd").profiles(city)}
		return _road_tunnel_cache.profiles
	return preload("res://scripts/view/city_road_tunnels_3d.gd").profiles(city)


## True while a sampling scope for `city` is open.
static func is_sampling_ground(city: City) -> bool:
	return _ground_sampling_city == city


static func begin_ground_sampling(city: City) -> Dictionary:
	var previous := {"city": _ground_sampling_city, "vertices": _ground_vertex_cache, "corners": _ground_corner_cache, "tunnels": _road_tunnel_cache,
		"water_flow": _water_flow_table, "water_corners": _water_corner_table, "water_heights": _water_height_table,
		"water_vertices": _water_vertex_table}
	_road_tunnel_cache = {}
	_ground_sampling_city = city
	_ground_vertex_cache = {}
	_ground_corner_cache = {}
	_water_flow_table = PackedByteArray()
	_water_corner_table = PackedFloat32Array()
	_water_height_table = PackedFloat64Array()
	_water_vertex_table = PackedByteArray()
	return previous


static func end_ground_sampling(previous: Dictionary) -> void:
	_road_tunnel_cache = previous.tunnels
	_ground_sampling_city = previous.city
	_ground_vertex_cache = previous.vertices
	_ground_corner_cache = previous.corners
	_water_flow_table = previous.water_flow
	_water_corner_table = previous.water_corners
	_water_height_table = previous.water_heights
	_water_vertex_table = previous.water_vertices


static func _shared_dry_vertex(city: City, vx: int, vy: int) -> float:
	if _ground_sampling_city != city: return _resolve_shared_dry_vertex(city,vx,vy)
	var key := Vector2i(vx,vy)
	if not _ground_vertex_cache.has(key):
		_ground_vertex_cache[key] = _resolve_shared_dry_vertex(city,vx,vy)
	return _ground_vertex_cache[key]


static func _resolve_shared_dry_vertex(city: City, vx: int, vy: int) -> float:
	var total := 0.0
	var count := 0
	var level_total := 0.0
	var level_count := 0
	for dy: int in range(-1,1):
		for dx: int in range(-1,1):
			var x := vx+dx
			var y := vy+dy
			if not city.in_bounds(x,y) or city.is_water(x,y): continue
			var mask := Terrain.raised_corners(Terrain.slope(city.terrain.at(x,y)))
			var bit: int = (8 if dx==0 else 1) if dy==0 else (4 if dx==0 else 2)
			var height := float(city.ground_height(x,y)+(1 if mask & bit else 0))*HEIGHT
			total += height
			count += 1
			# A fully raised encoded plateau is an independent cap reading,
			# not a level foundation at the stored base. Pinning that cap can
			# steepen an adjoining hill beyond the controller's floor limit.
			if mask==0:
				level_total += height
				level_count += 1
	return level_total/level_count if level_count>0 else total/maxi(count,1)


## Ground height at the tile center on the shared 3D facets.
static func ground_height(city: City, cell: Vector2i) -> float:
	return point_on_ground(city, cell, Vector2(0.5, 0.5)).y


## Interpolate one point over the tile's two planar terrain faces.
static func point_on_ground(city: City, cell: Vector2i, offset: Vector2) -> Vector3:
	return point_over_corners(ground_corners(city, cell), cell, offset)


## Imported wet slope codes describe shoreline art at the water level. They
## must not raise their seabed through that plane. Native shared-vertex terrain
## keeps its actual shoreline relief; neither path edits the stored city.
static func visible_cell_corners(city: City, cell: Vector2i) -> PackedVector3Array:
	var points:=ground_corners(city,cell)
	var kind:=Terrain.water_kind(city.terrain.atv(cell))
	if not city.terrain_surface is TerrainSurface and kind in [Terrain.SUBMERGED,Terrain.SHORE,Terrain.SURFACE]:
		var ceiling:=water_surface_height(city,cell)-0.006
		for i in points.size(): points[i].y=minf(points[i].y,ceiling)
	return points


static func visible_ground_height(city: City, cell: Vector2i, offset: Vector2 = Vector2(0.5,0.5)) -> float:
	return point_over_corners(visible_cell_corners(city,cell),cell,offset).y


## The ground point at `offset` within `cell`, over the facets of `points`.
static func point_over_corners(points: PackedVector3Array, cell: Vector2i, offset: Vector2) -> Vector3:
	return point_over_facet(points, uses_nw_se_diagonal(points), cell, offset)


## Interpolation over corners whose diagonal choice is already known.
static func point_over_facet(points: PackedVector3Array, nw_se: bool, cell: Vector2i, offset: Vector2) -> Vector3:
	var height: float
	if nw_se:
		if offset.x >= offset.y:
			height = points[0].y * (1.0 - offset.x) + points[1].y * (offset.x - offset.y) + points[3].y * offset.y
		else:
			height = points[0].y * (1.0 - offset.y) + points[2].y * (offset.y - offset.x) + points[3].y * offset.x
	elif offset.x + offset.y <= 1.0:
		height = points[0].y * (1.0 - offset.x - offset.y) + points[1].y * offset.x + points[2].y * offset.y
	else:
		height = points[1].y * (1.0 - offset.y) + points[2].y * (1.0 - offset.x) + points[3].y * (offset.x + offset.y - 1.0)
	return Vector3(cell.x + offset.x, height, cell.y + offset.y)


## Whether the cell's two facets split along the NW–SE diagonal.
static func uses_nw_se_diagonal(points: PackedVector3Array) -> bool:
	var diagonal := is_equal_approx(points[0].y, points[3].y) and not is_equal_approx(points[1].y, points[2].y)
	# Keep ordinary authored facets. On reconstructed multi-level corners the
	# default split can introduce a 60-degree triangle even though the other split
	# supports walking. Use the gentler diagonal only at that physical limit.
	var grade := _maximum_facet_grade_squared(points,diagonal)
	if grade>2.039606729 and _maximum_facet_grade_squared(points,not diagonal)<grade-.00001:
		return not diagonal
	return diagonal


static func _maximum_facet_grade_squared(points: PackedVector3Array, nw_se: bool) -> float:
	# Tile X/Z edges have unit length. Compare squared gradients directly;
	# this also avoids allocating triangles or normalizing vectors per pose.
	var ne := points[1].y-points[0].y
	var sw := points[2].y-points[0].y
	var se := points[3].y-points[0].y
	return maxf(ne*ne+(se-ne)*(se-ne),sw*sw+(se-sw)*(se-sw)) if nw_se \
		else maxf(ne*ne+sw*sw,(se-sw)*(se-sw)+(se-ne)*(se-ne))


## Depth of visible water over a native stream or waterfall bed.
const BED_FILM := 0.025


## Height of the visible water material, including temporary floods and streams.
## On native terrain this is the center of `water_corners`.
static func water_surface_height(city: City, cell: Vector2i) -> float:
	var sampling := _ground_sampling_city == city and city.in_bounds(cell.x, cell.y)
	var index := cell.y * City.WIDTH + cell.x
	if sampling:
		_water_tables_ready()
		var cached := _water_height_table[index]
		if not is_nan(cached): return cached
	var height: float
	if _flow(city, cell) & _NATIVE:
		var water := _water_corners(city, cell)
		if water[0].y == water[1].y and water[0].y == water[2].y and water[0].y == water[3].y:
			height = water[0].y
		else:
			# Water facets split like the ground beneath, so bank-draped water
			# stays at or below the bank's facets between its corners.
			height = point_over_facet(water, uses_nw_se_diagonal(visible_cell_corners(city, cell)), cell, Vector2(0.5, 0.5)).y
	else:
		height = _stored_water_surface(city, cell)
	if sampling: _water_height_table[index] = height
	return height


static func _stored_water_surface(city: City, cell: Vector2i) -> float:
	var water := city.water_height(cell.x, cell.y) * HEIGHT + 0.025
	if city.flood_overlay.has(cell):
		water = maxf(water, ground_height(city, cell) + 0.12)
	elif _imported_waterfall_block(city, cell):
		# Imported waterfall words locate the lower baseline of a full-height
		# water block, including saved baselines after a load rebuilds a lattice.
		# Projected native falls store their upper water level strictly above ground.
		water += HEIGHT
	elif Terrain.water_kind(city.terrain.atv(cell)) == Terrain.STREAM:
		water = maxf(water, ground_height(city, cell) + 0.025)
	return water


static func _imported_waterfall_block(city: City, cell: Vector2i) -> bool:
	var code := city.terrain.atv(cell)
	return (code == 0x2e or code == 0x3e) and (not city.terrain_surface is TerrainSurface \
		or city.water_height(cell.x, cell.y) <= city.ground_height(cell.x, cell.y))


## Water classification flags. Native water is wet on a shared-vertex lattice,
## other than temporary floods and imported waterfall blocks, which keep their
## stored presentation. Fusion is resolved on first request.
const _NATIVE := 1
const _BED := 2
const _FUSED := 4
const _FUSION_KNOWN := 8


static func _flow(city: City, cell: Vector2i) -> int:
	if not city.in_bounds(cell.x, cell.y): return 0
	var sampling := _ground_sampling_city == city
	var index := cell.y * City.WIDTH + cell.x
	if sampling:
		_water_tables_ready()
		var cached := _water_flow_table[index]
		if cached & _KNOWN: return cached & ~_KNOWN
	var flags := 0
	# Read the terrain byte directly: water codes are wet; a flood or an
	# imported waterfall block (stored at or below ground) is not native.
	var code: int = city.terrain.data[index]
	if city.terrain_surface is TerrainSurface and code >= Terrain.SUBMERGED \
			and (city.flood_overlay.is_empty() or not city.flood_overlay.has(cell)) \
			and not ((code == 0x2e or code == 0x3e) and city.water_height(cell.x, cell.y) <= city.ground_height(cell.x, cell.y)):
		flags = _NATIVE
		var surface: TerrainSurface = city.terrain_surface
		if surface.feature[index] != TerrainSurface.Feature.NONE: flags |= _BED
	if sampling: _water_flow_table[index] = flags | _KNOWN
	return flags


static func _native_water(city: City, cell: Vector2i) -> bool:
	return _flow(city, cell) & _NATIVE != 0


## Native streams and waterfalls flow over their carved bed. The lattice stores
## their water one level above that bed only so the tile counts as wet; the bed
## shares its vertices with the dry banks, so drawing the stored level would
## leave the water hanging a full level above the channel and its banks. Their
## visible water is instead a film following the bed. Stored data is unchanged;
## imported per-tile streams and temporary floods keep their own presentation.
static func is_bed_water(city: City, cell: Vector2i) -> bool:
	return _flow(city, cell) & _BED != 0


## Visible water surface corners in NW, NE, SW, SE order. Bed water follows its
## bed, so a native waterfall is a sloped cascade. Native standing water keeps
## its stored level except at corners it shares with a dry bank or a stream
## bed, where it meets that ground instead of hanging above it; when every bank
## stands at or above the water, as around generated lakes and seas, it is level.
static func water_corners(city: City, cell: Vector2i) -> PackedVector3Array:
	return _water_corners(city, cell).duplicate()


## Read-only shared corners; callers must not modify the result.
static func _water_corners(city: City, cell: Vector2i) -> PackedVector3Array:
	var slot := _water_corner_slot(city, cell)
	if slot >= 0:
		return PackedVector3Array([Vector3(cell.x, _water_corner_table[slot], cell.y),
			Vector3(cell.x + 1, _water_corner_table[slot + 1], cell.y),
			Vector3(cell.x, _water_corner_table[slot + 2], cell.y + 1),
			Vector3(cell.x + 1, _water_corner_table[slot + 3], cell.y + 1)])
	return _compute_water_corners(city, cell)


## Within a sampling scope, the table offset of the cell's four cached water
## corner heights (computed on first use); -1 outside a scope or the map.
static func _water_corner_slot(city: City, cell: Vector2i) -> int:
	if _ground_sampling_city != city or not city.in_bounds(cell.x, cell.y): return -1
	_water_tables_ready()
	var slot := (cell.y * City.WIDTH + cell.x) * 4
	if is_nan(_water_corner_table[slot]):
		var points := _compute_water_corners(city, cell)
		for i: int in 4:
			_water_corner_table[slot + i] = points[i].y
	return slot


static func _compute_water_corners(city: City, cell: Vector2i) -> PackedVector3Array:
	var points: PackedVector3Array
	var flags := _flow(city, cell)
	if not flags & _NATIVE:
		var water := _stored_water_surface(city, cell)
		points = PackedVector3Array([Vector3(cell.x, water, cell.y), Vector3(cell.x + 1, water, cell.y),
			Vector3(cell.x, water, cell.y + 1), Vector3(cell.x + 1, water, cell.y + 1)])
	else:
		# Native water lies on a lattice, whose visible corners are its vertices.
		var surface: TerrainSurface = city.terrain_surface
		var vertices := surface.vertices
		var at := cell.y * TerrainSurface.VERTS_X + cell.x
		points = PackedVector3Array([Vector3(cell.x, vertices[at] * HEIGHT, cell.y),
			Vector3(cell.x + 1, vertices[at + 1] * HEIGHT, cell.y),
			Vector3(cell.x, vertices[at + TerrainSurface.VERTS_X] * HEIGHT, cell.y + 1),
			Vector3(cell.x + 1, vertices[at + TerrainSurface.VERTS_X + 1] * HEIGHT, cell.y + 1)])
		if flags & _BED:
			for i: int in 4:
				points[i].y += BED_FILM
		else:
			# Native standing water is neither a flood nor an imported block.
			var level := _stored_water_surface(city, cell) \
				if Terrain.water_kind(city.terrain.atv(cell)) == Terrain.STREAM \
				else city.water_height(cell.x, cell.y) * HEIGHT + 0.025
			for i: int in 4:
				# Only a corner whose ground lies below the water can be lowered.
				var bank := points[i].y + BED_FILM
				points[i].y = bank if bank < level and _meets_bank(city, int(points[i].x), int(points[i].z)) else level
	return points


## Whether a lattice vertex touches a dry tile or a stream bed.
static func _meets_bank(city: City, vx: int, vy: int) -> bool:
	return _vertex_water(city, vx, vy) & (_TOUCHES_DRY | _TOUCHES_BED) != 0


## What the up to four tiles around a lattice vertex are: dry land, a stream
## bed, and whether that bed is a channel not fused with a body.
const _TOUCHES_DRY := 1
const _TOUCHES_BED := 2
const _TOUCHES_CHANNEL := 4


static func _vertex_water(city: City, vx: int, vy: int) -> int:
	var sampling := _ground_sampling_city == city
	var index := vy * (City.WIDTH + 1) + vx
	if sampling:
		_water_tables_ready()
		var cached := _water_vertex_table[index]
		if cached & _KNOWN: return cached & ~_KNOWN
	var flags := 0
	var features := PackedByteArray()
	if city.terrain_surface is TerrainSurface:
		features = (city.terrain_surface as TerrainSurface).feature
	var terrain := city.terrain.data
	var floods := city.flood_overlay
	for dy: int in range(-1, 1):
		for dx: int in range(-1, 1):
			var x := vx + dx
			var y := vy + dy
			if x < 0 or y < 0 or x >= City.WIDTH or y >= City.HEIGHT: continue
			# A water code is wet without a flood lookup; floods only wet dry codes.
			if terrain[y * City.WIDTH + x] < Terrain.SUBMERGED and (floods.is_empty() or not floods.has(Vector2i(x, y))):
				flags |= _TOUCHES_DRY
				continue
			# Streams are rare: the lattice feature byte rules most tiles out at once.
			if features.is_empty() or features[y * City.WIDTH + x] == TerrainSurface.Feature.NONE: continue
			var tile := Vector2i(x, y)
			if _flow(city, tile) & _BED:
				flags |= _TOUCHES_BED
				if not fuses_with_body(city, tile): flags |= _TOUCHES_CHANNEL
	if sampling: _water_vertex_table[index] = flags | _KNOWN
	return flags


## The visible center surface used by cursors, labels, camera focus and picking.
static func surface_height(city: City, cell: Vector2i) -> float:
	var ground := visible_ground_height(city, cell)
	return maxf(ground, water_surface_height(city, cell)) if city.is_water(cell.x, cell.y) else ground


## Raised shoreline corners stay on dry ground while submerged corners meet water.
static func surface_corners(city: City, cell: Vector2i) -> PackedVector3Array:
	var points := visible_cell_corners(city, cell)
	if city.is_water(cell.x, cell.y):
		var water := _water_corners(city, cell)
		for i: int in points.size():
			points[i].y = maxf(points[i].y, water[i].y)
	return points


## Opaque, rough material suitable for terrain and small procedural details.
static func material(color: Color, vertex_colors: bool = false) -> Material:
	if vertex_colors:
		return surface_material()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = vertex_colors
	mat.vertex_color_is_srgb = vertex_colors
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Corner indices, neighbor step and the neighbor's matching corner indices of
## each tile edge, in skirt emission order.
const CHUNK_EDGES := [[0, 1, Vector2i(0, -1), 2, 3], [1, 3, Vector2i(1, 0), 0, 2],
	[3, 2, Vector2i(0, 1), 1, 0], [2, 0, Vector2i(-1, 0), 3, 1]]


## Ground tint origin of each emitted triangle: fixed water colours, the cell's
## sand (floor and shoreline relief) or its darkened skirt. Building and zone
## changes recolour sand/skirt triangles without rebuilding the chunk.
const TINT_FIXED := 0
const TINT_SAND := 1
const TINT_SKIRT := 2


static func _mark_tint(tints: PackedByteArray, vertex_count: int, tint: int) -> void:
	while tints.size() < vertex_count / 3: tints.append(tint)


## Ground colour under one cell: desert sand, or the zone tint while the zoned
## ground stays visible. Standalone utility lines leave the zoned ground visible.
static func cell_sand_color(city: City, x: int, y: int) -> Color:
	var sand := Color(0.75, 0.633, 0.49)
	var zone := city.zone_kind_at(x, y)
	var building := city.building.at(x, y)
	if zone > Zones.NONE and (building == Buildings.NONE \
			or (building >= Buildings.POWER_LINE_FIRST and building <= Buildings.POWER_LINE_LAST)):
		var tint := Color(0.35, 0.64, 0.34) if zone <= Zones.RES_HIGH else Color(0.28, 0.53, 0.70) if zone <= Zones.COM_HIGH else Color(0.79, 0.64, 0.27)
		sand = sand.lerp(tint, 0.65)
	return sand


## Visible corners of one cell, computed once per chunk build. Callers only read.
static func _chunk_visible_corners(city: City, cell: Vector2i, cache: Dictionary) -> PackedVector3Array:
	var cached: Variant = cache.get(cell)
	if cached == null:
		cached = visible_cell_corners(city, cell)
		cache[cell] = cached
	return cached


## Build visible triangles and a matching triangle-to-cell picking index.
static func build_chunk(city: City, bounds: Rect2i) -> Dictionary:
	var faces := PackedVector3Array()
	var cells: Array[Vector2i] = []
	var colors := PackedColorArray()
	var roles: Array[int] = []
	var tunnels := road_tunnel_profiles(city)
	var clipped := bounds.intersection(Rect2i(0, 0, City.WIDTH, City.HEIGHT))
	var corner_cache: Dictionary = {}
	var tints := PackedByteArray()
	var cell_sand: Dictionary = {}
	for y: int in range(clipped.position.y, clipped.end.y):
		for x: int in range(clipped.position.x, clipped.end.x):
			var cell := Vector2i(x, y)
			var p := _chunk_visible_corners(city, cell, corner_cache)
			var sand := cell_sand_color(city, x, y)
			cell_sand[cell] = sand
			if uses_nw_se_diagonal(p):
				quad(faces, cells, colors, p[1], p[3], p[0], p[2], cell, sand)
			else:
				quad(faces, cells, colors, p[0], p[1], p[2], p[3], cell, sand)
			_mark_role(roles, faces.size(), PhysicalRole.FLOOR)
			_mark_tint(tints, faces.size(), TINT_SAND)
			# Dry shared edges meet exactly. Keep skirts at map/water boundaries
			# and native cliffs, where a vertical exposed face is intentional.
			var skirt_color := Color()
			var skirt_colored := false
			for edge: Array in CHUNK_EDGES:
				var neighbor: Vector2i = cell + edge[2]
				var a: Vector3 = p[edge[0]]
				var b: Vector3 = p[edge[1]]
				var bottom_a := a
				var bottom_b := b
				if not city.in_bounds(neighbor.x, neighbor.y):
					bottom_a.y = -HEIGHT
					bottom_b.y = -HEIGHT
				else:
					var n := _chunk_visible_corners(city, neighbor, corner_cache)
					bottom_a.y = minf(a.y, n[edge[3]].y)
					bottom_b.y = minf(b.y, n[edge[4]].y)
				if bottom_a.y < a.y or bottom_b.y < b.y:
					if not skirt_colored:
						skirt_color = sand.darkened(0.15)
						skirt_colored = true
					quad(faces, cells, colors, b, a, bottom_b, bottom_a, cell, skirt_color)
			_mark_role(roles, faces.size(), PhysicalRole.OBSTACLE)
			_mark_tint(tints, faces.size(), TINT_SKIRT)
			if city.is_water(x, y):
				var water := water_surface_height(city, cell)
				var kind := Terrain.water_kind(city.terrain.at(x, y))
				var native := _native_water(city, cell)
				var bed := native and is_bed_water(city, cell) and not fuses_with_body(city, cell)
				if bed:
					_channel(city, cell, faces, cells, colors)
				elif kind == Terrain.STREAM and not native and not city.flood_overlay.has(cell):
					_stream(faces, cells, colors, cell, city.terrain.at(x,y)-Terrain.STREAM, water)
				else:
					if native:
						var w := _water_corners(city, cell)
						if uses_nw_se_diagonal(p):
							quad(faces, cells, colors, w[1], w[3], w[0], w[2], cell, WATER_COLOR)
						else:
							quad(faces, cells, colors, w[0], w[1], w[2], w[3], cell, WATER_COLOR)
					else:
						quad(faces, cells, colors, Vector3(x, water, y), Vector3(x + 1, water, y),
							Vector3(x, water, y + 1), Vector3(x + 1, water, y + 1), cell, WATER_COLOR)
					_mark_role(roles, faces.size(), PhysicalRole.WATER)
					_mark_tint(tints, faces.size(), TINT_FIXED)
					if city.terrain.at(x,y) in [0x2e,0x3e]:
						# A native fall is the sloped bed cascade itself.
						if not native: _waterfall(city,cell,water,faces,cells,colors)
						_mark_role(roles, faces.size(), PhysicalRole.WATER)
						_mark_tint(tints, faces.size(), TINT_FIXED)
					elif kind in [Terrain.SHORE,Terrain.SURFACE] and not city.flood_overlay.has(cell):
						_shore(city,cell,water,p,sand,faces,cells,colors)
						_mark_role(roles, faces.size(), PhysicalRole.FLOOR)
						_mark_tint(tints, faces.size(), TINT_SAND)
				_mark_role(roles, faces.size(), PhysicalRole.WATER)
				_mark_tint(tints, faces.size(), TINT_FIXED)
				_edge_fall(city, cell, p, faces, cells, colors)
				if native: _spill(city, cell, faces, cells, colors)
				_mark_role(roles, faces.size(), PhysicalRole.WATER)
				_mark_tint(tints, faces.size(), TINT_FIXED)
	# Construction queries keep the full terrain faces, including entrances.
	# The presentation cuts mouths without altering imported heights or picking.
	var shown_faces := PackedVector3Array()
	var shown_colors := PackedColorArray()
	var physical_floor := PackedVector3Array()
	var physical_obstacles := PackedVector3Array()
	var water_regions: Array[Dictionary] = []
	# Source triangle of every shown triangle, for later recolouring.
	var shown_sources := PackedInt32Array()
	# Portal and tunnel membership are per cell; resolve each cell once.
	var portal_cache: Dictionary = {}
	for i: int in range(0, faces.size(), 3):
		var cell: Vector2i = cells[i / 3]
		var portal: Variant = portal_cache.get(cell)
		if portal == null:
			portal = preload("res://scripts/view/city_portal_3d.gd").profile(city, cell, HEIGHT)
			portal_cache[cell] = portal
		var first := shown_faces.size()
		var color := colors[i]
		if tunnels.has(cell):
			var emitted := preload("res://scripts/exploration/transit/portal_passage_clip_3d.gd").triangle(faces[i],faces[i + 1],faces[i + 2],preload("res://scripts/view/city_road_tunnels_3d.gd").passage(cell,tunnels[cell]))
			shown_faces.append_array(emitted)
			for vertex: Vector3 in emitted: shown_colors.append(color)
		elif portal.is_empty():
			shown_faces.push_back(faces[i])
			shown_faces.push_back(faces[i + 1])
			shown_faces.push_back(faces[i + 2])
			shown_colors.push_back(color)
			shown_colors.push_back(color)
			shown_colors.push_back(color)
		else:
			var triangle: Array[Vector3] = [faces[i], faces[i + 1], faces[i + 2]]
			_cut_portal_triangle(triangle, cell, portal, color, shown_faces, shown_colors)
		var last := shown_faces.size()
		for _k: int in range(first, last, 3): shown_sources.append(i / 3)
		match roles[i / 3]:
			PhysicalRole.FLOOR:
				for k: int in range(first, last): physical_floor.push_back(shown_faces[k])
			PhysicalRole.OBSTACLE:
				for k: int in range(first, last): physical_obstacles.push_back(shown_faces[k])
			PhysicalRole.WATER:
				for j: int in range(first, last, 3):
					var polygon := PackedVector2Array()
					for k: int in 3: polygon.append(Vector2(shown_faces[j+k].x, shown_faces[j+k].z))
					if absf((polygon[1]-polygon[0]).cross(polygon[2]-polygon[0])) > 0.00000001:
						# Sloped bed water is wet up to its highest point.
						var top := maxf(shown_faces[j].y, maxf(shown_faces[j+1].y, shown_faces[j+2].y))
						water_regions.append({"polygon": polygon, "top": top, "cell": cell})
	# Remove the visible dry shelf footprint from the water classification. This
	# does not change the intentionally continuous visible/query water material.
	var dry_water := _dry_water_regions(water_regions,physical_floor)
	return {"mesh": mesh_from_faces(shown_faces, shown_colors, 0.025, SurfaceKind.TERRAIN), "faces": faces, "face_cells": cells,
		"physical_floor_faces": physical_floor, "physical_obstacle_faces": physical_obstacles,
		"water_regions": dry_water, "bounds": clipped,
		"colors": colors, "tints": tints, "cell_sand": cell_sand, "shown_faces": shown_faces, "shown_sources": shown_sources}


## Recolour a completed chunk after building/zone changes in `changed` cells.
## Geometry, picking, physical and water outputs are untouched; only sand and
## skirt triangles of those cells take the cell's current tint, as a fresh
## build would colour them. Returns `data` itself when nothing changes,
## or an empty dictionary when `data` predates tint records.
static func recolor_chunk(city: City, data: Dictionary, changed: Array) -> Dictionary:
	if not data.has("tints") or not data.has("shown_sources"): return {}
	var cell_sand: Dictionary = data.cell_sand
	var updates: Dictionary = {}
	for cell: Vector2i in changed:
		if not cell_sand.has(cell): continue
		var sand := cell_sand_color(city, cell.x, cell.y)
		if sand == cell_sand[cell]: continue
		updates[cell] = [sand, sand.darkened(0.15)]
	if updates.is_empty(): return data
	var colors: PackedColorArray = data.colors.duplicate()
	var tints: PackedByteArray = data.tints
	var cells: Array[Vector2i] = data.face_cells
	for i: int in cells.size():
		var tint := tints[i]
		if tint == TINT_FIXED or not updates.has(cells[i]): continue
		var color: Color = updates[cells[i]][tint - 1]
		colors[3 * i] = color
		colors[3 * i + 1] = color
		colors[3 * i + 2] = color
	var shown_sources: PackedInt32Array = data.shown_sources
	var shown_colors := PackedColorArray()
	shown_colors.resize(shown_sources.size() * 3)
	for t: int in shown_sources.size():
		var color := colors[3 * shown_sources[t]]
		shown_colors[3 * t] = color
		shown_colors[3 * t + 1] = color
		shown_colors[3 * t + 2] = color
	var result := data.duplicate()
	result.colors = colors
	result.cell_sand = cell_sand.duplicate()
	for cell: Vector2i in updates: result.cell_sand[cell] = updates[cell][0]
	result.mesh = mesh_from_faces(data.shown_faces, shown_colors, 0.025, SurfaceKind.TERRAIN)
	return result


## Tag newly emitted triangles by their generating operation, never by color.
static func _mark_role(roles: Array[int], vertex_count: int, role: int) -> void:
	while roles.size() < vertex_count / 3: roles.append(role)


## A native stream or fall beside lake, sea or estuary water joins that body:
## it draws as full water rather than a channel strip.
static func fuses_with_body(city: City, cell: Vector2i) -> bool:
	var flags := _flow(city, cell)
	if not flags & _BED: return false
	if flags & _FUSION_KNOWN: return flags & _FUSED != 0
	var fused := false
	for edge: Array in CHUNK_EDGES:
		if _flow(city, cell + edge[2]) & (_NATIVE | _BED) == _NATIVE:
			fused = true
			break
	if _ground_sampling_city == city:
		_water_flow_table[cell.y * City.WIDTH + cell.x] = flags | _FUSION_KNOWN | (_FUSED if fused else 0) | _KNOWN
	return fused


## Raised shoreline corners that show a sand shelf. On a native lattice a shelf
## marks real land, so corners whose vertex touches only full water (bodies
## and the river tiles fused with them) are open water, and channel tiles have
## none. Imported per-tile shorelines and floods keep their encoded shelves.
static func shore_shelf_mask(city: City, cell: Vector2i) -> int:
	var raised := Terrain.raised_corners(Terrain.slope(city.terrain.atv(cell)))
	if raised == 0 or not city.terrain_surface is TerrainSurface or city.flood_overlay.has(cell): return raised
	if is_bed_water(city, cell): return 0
	var vertices: Array[Vector2i] = [cell + Vector2i(1, 0), cell + Vector2i(1, 1), cell + Vector2i(0, 1), cell]
	for i: int in 4:
		var bit := 1 << i
		if raised & bit and not _vertex_water(city, vertices[i].x, vertices[i].y) & (_TOUCHES_DRY | _TOUCHES_CHANNEL):
			raised &= ~bit
	return raised



## Water width of a one-tile stream channel, in tiles.
const CHANNEL_WIDTH := 0.32


## Native streams and waterfalls are one-tile channels whatever shoreline code
## projection gave them: straight reaches, bends, junctions and falls all draw
## a CHANNEL_WIDTH strip from the tile center toward each neighbouring water
## tile, lying on the bed facets (so a fall's strip runs down its slope). A
## stream with no wet neighbour keeps only its center pool.
static func _channel(city: City, cell: Vector2i, faces: PackedVector3Array,
		cells: Array[Vector2i], colors: PackedColorArray) -> void:
	var ground := visible_cell_corners(city, cell)
	var nw_se := uses_nw_se_diagonal(ground)
	var half := CHANNEL_WIDTH * 0.5
	var low := 0.5 - half
	var high := 0.5 + half
	var pieces: Array[PackedVector2Array] = [_box(low, low, high, high)]
	var arms := [_box(low, 0.0, high, low), _box(high, low, 1.0, high), _box(low, high, high, 1.0), _box(0.0, low, low, high)]
	for i: int in 4:
		var neighbor: Vector2i = cell + CHUNK_EDGES[i][2]
		if city.in_bounds(neighbor.x, neighbor.y):
			if city.is_water(neighbor.x, neighbor.y): pieces.append(arms[i])
		else:
			# A channel running straight off the map reaches its edge fall.
			var inside: Vector2i = cell - CHUNK_EDGES[i][2]
			if city.in_bounds(inside.x, inside.y) and city.is_water(inside.x, inside.y): pieces.append(arms[i])
	var facets: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]),
		PackedVector2Array([Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])]
	if nw_se:
		facets = [PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]),
			PackedVector2Array([Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])]
	for piece: PackedVector2Array in pieces:
		for facet: PackedVector2Array in facets:
			for polygon: PackedVector2Array in Geometry2D.intersect_polygons(piece, facet):
				var points: Array[Vector3] = []
				for local: Vector2 in polygon:
					points.append(point_over_facet(ground, nw_se, cell, local) + Vector3.UP * BED_FILM)
				for k: int in range(1, points.size() - 1):
					var a := points[0]
					var b := points[k]
					var c := points[k + 1]
					if absf((b - a).cross(c - a).y) < 0.0000001: continue
					if (b - a).cross(c - a).y > 0:
						var swap := b
						b = c
						c = swap
					faces.push_back(a)
					faces.push_back(b)
					faces.push_back(c)
					cells.append(cell)
					for _v: int in 3: colors.append(WATER_COLOR)


static func _box(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


## Imported stream codes 0x40/41 run N-S/E-W; 0x42..45 end at E/S/W/N.
## Bends use the ordinary 0x35..38 shoreline codes, not stream variants.
static func _stream(faces: PackedVector3Array, cells: Array[Vector2i], colors: PackedColorArray,
		cell: Vector2i, variant: int, height: float) -> void:
	var paths: Array = [[Vector2.UP,Vector2.DOWN],[Vector2.LEFT,Vector2.RIGHT],
		[Vector2.RIGHT],[Vector2.DOWN],[Vector2.LEFT],[Vector2.UP]]
	var center := Vector2(cell)+Vector2(0.5,0.5)
	var width := CHANNEL_WIDTH
	for direction: Vector2 in paths[clampi(variant,0,5)]:
		var across := Vector2(-direction.y,direction.x)*width*0.5
		var begin := center-direction*width*0.5
		var end := center+direction*0.5
		_flat_quad(faces,cells,colors,cell,[begin-across,end-across,end+across,begin+across],height,WATER_COLOR)


## Encoded shore edges remain visible when the imported seabed lies below water.
## Dry slopes keep their own geometry. The narrow shelf follows
## the selected shore mask rather than flattening or raising the city height data.
static func _shore(city: City, cell: Vector2i, water: float, points: PackedVector3Array,
		color: Color, faces: PackedVector3Array, cells: Array[Vector2i], colors: PackedColorArray) -> void:
	var raised := shore_shelf_mask(city, cell)
	if raised == 0: return
	var ring: Array[int] = [0,1,3,2]
	var bits: Array[int] = [8,1,2,4]
	var center := Vector2(cell)+Vector2(0.5,0.5)
	for i in 4:
		var next := (i+1)%4
		var a: Vector3 = points[ring[i]]
		var b: Vector3 = points[ring[next]]
		if (raised & bits[i]) and (raised & bits[next]) and maxf(a.y,b.y)<=water:
			var av:=Vector2(a.x,a.z);var bv:=Vector2(b.x,b.z)
			var inward:=(center-(av+bv)*0.5).normalized()*0.18
			_flat_quad(faces,cells,colors,cell,[av,bv,bv+inward,av+inward],water+0.008,color)
		elif (raised & bits[i]) and a.y<=water:
			var corner:=Vector2(a.x,a.z)
			var previous: Vector3=points[ring[(i+3)%4]]
			var side_a:=(Vector2(b.x,b.z)-corner)*0.2
			var side_b:=(Vector2(previous.x,previous.z)-corner)*0.2
			_flat_quad(faces,cells,colors,cell,[corner,corner+side_a,corner+side_a+side_b,corner+side_b],water+0.008,color)


static func _flat_quad(faces: PackedVector3Array, cells: Array[Vector2i], colors: PackedColorArray,
		cell: Vector2i, polygon: Array[Vector2], height: float, color: Color) -> void:
	var a:=Vector3(polygon[0].x,height,polygon[0].y)
	var b:=Vector3(polygon[1].x,height,polygon[1].y)
	var c:=Vector3(polygon[2].x,height,polygon[2].y)
	var d:=Vector3(polygon[3].x,height,polygon[3].y)
	if (b-a).cross(c-a).y>0:
		quad(faces,cells,colors,a,d,b,c,cell,color)
	else:
		quad(faces,cells,colors,a,b,d,c,cell,color)


static func _waterfall(city: City, cell: Vector2i, water: float, faces: PackedVector3Array,
		cells: Array[Vector2i], colors: PackedColorArray) -> void:
	var ring: Array[Vector2] = [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
	var directions: Array[Vector2i] = [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
	for i in 4:
		var neighbor:=cell+directions[i]
		if not city.in_bounds(neighbor.x,neighbor.y): continue
		var lower:=water_surface_height(city,neighbor) if city.is_water(neighbor.x,neighbor.y) else ground_height(city,neighbor)
		if lower>=water-0.02: continue
		var shift:=Vector2(directions[i])*0.004
		var a:=Vector2(cell)+ring[i]+shift
		var b:=Vector2(cell)+ring[(i+1)%4]+shift
		quad(faces,cells,colors,Vector3(b.x,water,b.y),Vector3(a.x,water,a.y),
			Vector3(b.x,lower,b.y),Vector3(a.x,lower,a.y),cell,WATER_COLOR)


## Native water above lower neighbouring water pours into it across their
## shared edge, e.g. a lake outflow over a stream bed, so neither surface's
## edge hangs open. Only the higher side emits; floods keep their own surface.
static func _spill(city: City, cell: Vector2i, faces: PackedVector3Array,
		cells: Array[Vector2i], colors: PackedColorArray) -> void:
	var slot := _water_corner_slot(city, cell)
	if slot >= 0 and not _may_spill(city, cell, slot): return
	var top := _water_corners(city, cell)
	var channel := is_bed_water(city, cell) and not fuses_with_body(city, cell)
	for edge: Array in CHUNK_EDGES:
		var neighbor: Vector2i = cell + edge[2]
		if not city.in_bounds(neighbor.x, neighbor.y) or not city.is_water(neighbor.x, neighbor.y) \
				or city.flood_overlay.has(neighbor):
			continue
		var lower := _water_corners(city, neighbor)
		var a: Vector3 = top[edge[0]]
		var b: Vector3 = top[edge[1]]
		var below_a: float = lower[edge[3]].y
		var below_b: float = lower[edge[4]].y
		if channel:
			# A channel pours only across its own width.
			var from := 0.5 - CHANNEL_WIDTH * 0.5
			var to := 0.5 + CHANNEL_WIDTH * 0.5
			var a2 := a.lerp(b, from)
			b = a.lerp(b, to)
			a = a2
			var below_a2 := lerpf(below_a, below_b, from)
			below_b = lerpf(below_a, below_b, to)
			below_a = below_a2
		var bottom_a := minf(a.y, below_a)
		var bottom_b := minf(b.y, below_b)
		if a.y - bottom_a <= 0.02 and b.y - bottom_b <= 0.02: continue
		var shift := Vector3(edge[2].x, 0, edge[2].y) * 0.004
		quad(faces, cells, colors, b + shift, a + shift, Vector3(b.x, bottom_b, b.z) + shift,
			Vector3(a.x, bottom_a, a.z) + shift, cell, WATER_COLOR)


## Water at the city limits pours over the map's edge as a waterfall down the
## exposed side of the terrain block, instead of leaving a gap between its
## surface and the skirt below. Only the wet span of the edge falls: a bank that
## rises above the water keeps its skirt. Channels and imported streams fall
## across their own width where they run off the map.
static func _edge_fall(city: City, cell: Vector2i, ground: PackedVector3Array,
		faces: PackedVector3Array, cells: Array[Vector2i], colors: PackedColorArray) -> void:
	if cell.x > 0 and cell.y > 0 and cell.x < City.WIDTH - 1 and cell.y < City.HEIGHT - 1: return
	var native := _native_water(city, cell)
	var flooded := city.flood_overlay.has(cell)
	var channel := native and is_bed_water(city, cell) and not fuses_with_body(city, cell)
	var code := city.terrain.at(cell.x, cell.y)
	var stream := not native and not flooded and Terrain.water_kind(code) == Terrain.STREAM
	var top: PackedVector3Array
	if native:
		top = _water_corners(city, cell)
	else:
		var level := water_surface_height(city, cell)
		top = PackedVector3Array([Vector3(cell.x, level, cell.y), Vector3(cell.x + 1, level, cell.y),
			Vector3(cell.x, level, cell.y + 1), Vector3(cell.x + 1, level, cell.y + 1)])
	for edge: Array in CHUNK_EDGES:
		var step: Vector2i = edge[2]
		var outside: Vector2i = cell + step
		if city.in_bounds(outside.x, outside.y): continue
		var from := 0.0
		var to := 1.0
		if channel or stream:
			var flows := false
			if channel:
				var inside: Vector2i = cell - step
				flows = city.in_bounds(inside.x, inside.y) and city.is_water(inside.x, inside.y)
			else:
				const PATHS := [[Vector2i.UP, Vector2i.DOWN], [Vector2i.LEFT, Vector2i.RIGHT],
					[Vector2i.RIGHT], [Vector2i.DOWN], [Vector2i.LEFT], [Vector2i.UP]]
				flows = step in PATHS[clampi(code - Terrain.STREAM, 0, 5)]
			if not flows: continue
			from = 0.5 - CHANNEL_WIDTH * 0.5
			to = 0.5 + CHANNEL_WIDTH * 0.5
		var a: Vector3 = top[edge[0]]
		var b: Vector3 = top[edge[1]]
		# Wetness along the edge: water above the visible ground there.
		var wet_a: float = a.y - ground[edge[0]].y
		var wet_b: float = b.y - ground[edge[1]].y
		if wet_a < -0.0001 or wet_b < -0.0001:
			if wet_a <= 0.0001 and wet_b <= 0.0001: continue
			var crossing := wet_a / (wet_a - wet_b)
			if wet_a < wet_b: from = maxf(from, crossing)
			else: to = minf(to, crossing)
		if to - from < 0.001: continue
		var start := a.lerp(b, from)
		var end := a.lerp(b, to)
		var shift := Vector3(step.x, 0, step.y) * 0.004
		quad(faces, cells, colors, end + shift, start + shift, Vector3(end.x, -HEIGHT, end.z) + shift,
			Vector3(start.x, -HEIGHT, start.z) + shift, cell, WATER_COLOR)


## Cached-table pre-check: whether any edge of the cell has neighbouring water
## lower by more than the spill tolerance at either end. Every edge it rejects
## would emit nothing (a narrowed channel span interpolates the same ends).
## Per edge N, E, S, W (as CHUNK_EDGES): own corners A/B, neighbour step and
## the neighbour's matching corners C/D.
const _SPILL_A := [0, 1, 3, 2]
const _SPILL_B := [1, 3, 2, 0]
const _SPILL_DX := [0, 1, 0, -1]
const _SPILL_DY := [-1, 0, 1, 0]
const _SPILL_C := [2, 0, 1, 3]
const _SPILL_D := [3, 2, 0, 1]


static func _may_spill(city: City, cell: Vector2i, slot: int) -> bool:
	for e: int in 4:
		var nx: int = cell.x + _SPILL_DX[e]
		var ny: int = cell.y + _SPILL_DY[e]
		if nx < 0 or ny < 0 or nx >= City.WIDTH or ny >= City.HEIGHT: continue
		var index: int = ny * City.WIDTH + nx
		var known := _water_flow_table[index]
		var flags := known & ~_KNOWN if known & _KNOWN else _flow(city, Vector2i(nx, ny))
		if flags == 0 and (not city.is_water(nx, ny) or city.flood_overlay.has(Vector2i(nx, ny))): continue
		var other: int = index * 4
		if is_nan(_water_corner_table[other]): _water_corner_slot(city, Vector2i(nx, ny))
		if _water_corner_table[slot + _SPILL_A[e]] - _water_corner_table[other + _SPILL_C[e]] > 0.02 \
				or _water_corner_table[slot + _SPILL_B[e]] - _water_corner_table[other + _SPILL_D[e]] > 0.02:
			return true
	return false


## Subtract the rectangular mouth from each terrain triangle. Sequentially
## keep the outside of each half-plane, then discard the final inside piece.
static func _cut_portal_triangle(triangle: Array[Vector3], cell: Vector2i, profile: Dictionary,
		color: Color, faces: PackedVector3Array, colors: PackedColorArray) -> void:
	var origin: Vector2=Vector2(cell)+profile.outside
	var inward: Vector2=profile.inward
	var across: Vector2=profile.across
	var planes: Array = [[inward,origin.dot(inward)],[-inward,-origin.dot(inward)-float(profile.depth)],
		[across,origin.dot(across)-float(profile.width)*0.5],[-across,-origin.dot(across)-float(profile.width)*0.5]]
	var remainder:=triangle
	for plane: Array in planes:
		var exterior:=_clip_plane(remainder,plane[0],plane[1],false)
		for i in range(1,exterior.size()-1):
			if (exterior[i]-exterior[0]).cross(exterior[i+1]-exterior[0]).length_squared()<0.000000000001:
				continue
			faces.append_array(PackedVector3Array([exterior[0],exterior[i],exterior[i+1]]))
			colors.append_array(PackedColorArray([color,color,color]))
		remainder=_clip_plane(remainder,plane[0],plane[1],true)
		if remainder.is_empty(): break


static func _clip_plane(polygon: Array[Vector3], normal: Vector2, distance: float, inside: bool) -> Array[Vector3]:
	var result: Array[Vector3]=[]
	if polygon.is_empty(): return result
	var previous:=polygon[-1]
	var before:=Vector2(previous.x,previous.z).dot(normal)-distance
	if not inside: before=-before
	for current: Vector3 in polygon:
		var now:=Vector2(current.x,current.z).dot(normal)-distance
		if not inside: now=-now
		if (now>=0)!=(before>=0): result.append(previous.lerp(current,before/(before-now)))
		if now>=0: result.append(current)
		previous=current;before=now
	return result


## Make an unindexed colored triangle mesh.
static func mesh_from_faces(faces: PackedVector3Array, colors: PackedColorArray, grain_strength: float = 0.0, surface_kind: int = SurfaceKind.DETAIL) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if faces.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	arrays[Mesh.ARRAY_COLOR] = colors
	var normals := PackedVector3Array()
	normals.resize(faces.size())
	for i: int in range(0, faces.size(), 3):
		var normal := (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).normalized()
		normals[i] = normal
		normals[i + 1] = normal
		normals[i + 2] = normal
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Identical parameters render identically: share one immutable material per
	# (grain, kind). Callers that need their own material assign a fresh one.
	var key := [grain_strength, surface_kind]
	if not _face_materials.has(key):
		_face_materials[key] = surface_material(grain_strength, surface_kind)
	mesh.surface_set_material(0, _face_materials[key])
	return mesh


## Append a quad and its two picking records.
static func quad(faces: PackedVector3Array, cells: Array[Vector2i], colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, cell: Vector2i, color: Color) -> void:
	# Godot front faces use clockwise winding; normals use the opposite cross product.
	faces.push_back(a)
	faces.push_back(b)
	faces.push_back(c)
	faces.push_back(b)
	faces.push_back(d)
	faces.push_back(c)
	cells.append(cell)
	cells.append(cell)
	for i: int in 6:
		colors.append(color)


## Continuous generated color variation stays within the selected terrain palette.
## Clockwise faces and ordinary lighting preserve facets and cast shadows.
static func surface_material(grain_strength: float = 0.0, surface_kind: int = SurfaceKind.DETAIL) -> ShaderMaterial:
	if _surface_shader == null:
		_surface_shader = Shader.new()
		_surface_shader.code = """shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D grain_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D sand_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D road_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float grain_strength = 0.0;
uniform int surface_kind = 2;
#include \"res://shaders/city_water_3d.gdshaderinc\"
#include \"res://shaders/city_tile_grid_3d.gdshaderinc\"
#include \"res://shaders/city_paving_finish.gdshaderinc\"
varying vec3 map_position;
varying vec3 map_normal;
// Mirrored sampling joins identical texels at each turnaround, so generated
// opposite edges never meet. Large nonintegral periods avoid tile checkerboards.
vec2 mirrored_uv(vec2 position, float period) {
	return vec2(0.025) + abs(fract(position / period) * 2.0 - 1.0) * 0.95;
}
vec3 texture_ratio(sampler2D tex, vec2 position, float period, vec3 linear_average, vec3 srgb_average) {
	// Compatibility shades in sRGB; Forward+/Mobile shade in linear color.
	vec3 average = OUTPUT_IS_SRGB ? srgb_average : linear_average;
	return clamp(texture(tex, mirrored_uv(position, period)).rgb / average, vec3(0.5), vec3(1.6));
}
void vertex() {
	map_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	vec3 base = COLOR.rgb;
	bool water = distance(base, vec3(0.372549, 0.643137, 0.615686)) < 0.005;
	if (surface_kind == 0 && !water) {
		vec3 sand = texture_ratio(sand_texture, map_position.xz, 5.7, vec3(0.615251, 0.348525, 0.139784), vec3(0.805804, 0.623608, 0.407961));
		vec3 weights = pow(abs(normalize(map_normal)), vec3(4.0));
		weights /= max(dot(weights, vec3(1.0)), 0.0001);
		vec3 rock_mean = vec3(0.492699, 0.301950, 0.144144);
		vec3 rock = texture_ratio(rock_texture, map_position.yz, 3.9, rock_mean, vec3(0.727569, 0.581333, 0.410902)) * weights.x
			+ texture_ratio(rock_texture, map_position.xz, 3.9, rock_mean, vec3(0.727569, 0.581333, 0.410902)) * weights.y
			+ texture_ratio(rock_texture, map_position.xy, 3.9, rock_mean, vec3(0.727569, 0.581333, 0.410902)) * weights.z;
		float slope = smoothstep(0.04, 0.25, 1.0 - abs(map_normal.y));
		base *= mix(vec3(1.0), mix(sand, rock, slope), mix(0.38, 0.50, slope));
	} else if (surface_kind == 1) {
		vec3 aggregate = texture_ratio(road_texture, map_position.xz, 3.3, vec3(0.154489, 0.163048, 0.163720), vec3(0.417961, 0.430275, 0.433608));
		// Colored paint, steel and sleepers retain their authored identity.
		float neutral = 1.0 - smoothstep(0.10, 0.22, max(max(base.r, base.g), base.b) - min(min(base.r, base.g), base.b));
		if (distance(COLOR.rgb,vec3(.74,.72,.65))<.005) {
			base=paving_finish(base,map_position,map_normal);
		} else if (distance(COLOR.rgb,vec3(.77,.63,.47))<.005) {
			vec3 n=abs(map_normal);
			vec2 p=n.y>.5 ? map_position.xz : (n.x>n.z ? map_position.zy : map_position.xy);
			vec3 sand=texture_ratio(sand_texture,p,5.7,vec3(.615251,.348525,.139784),vec3(.805804,.623608,.407961));
			base*=mix(vec3(1.0),sand,.38);
		} else {
		base *= mix(vec3(1.0), aggregate, 0.34 * neutral);
		}
	} else if (grain_strength > 0.0 && !water) {
		vec2 uv = vec2(0.0, 0.5) + mirrored_uv(map_position.xz, 1.0) * 0.5;
		vec3 grain = texture(grain_texture, uv).rgb;
		base += (dot(grain, vec3(0.333333)) - 0.5) * grain_strength;
	}
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	if (surface_kind == 0 && water && water_style_enabled) {
		bool vertical = abs(map_normal.y) < 0.5;
		vec2 p = map_position.xz;
		vec2 source_cell = floor(p - (vertical ? map_normal.xz*0.02 : vec2(0.0)));
		vec4 data = texture(water_geometry,(source_cell+0.5)/128.0);
		float footprint = max(length(dFdx(p)),length(dFdy(p)));
		if (vertical) {
			vec2 outside_cell = floor(p+map_normal.xz*0.02);
			vec4 outside = texture(water_geometry,(outside_cell+0.5)/128.0);
			// Falls over the city limits pour off the block; no pool, no foam.
			bool off_map = any(lessThan(outside_cell,vec2(0.0))) || any(greaterThanEqual(outside_cell,vec2(128.0)));
			float bottom = off_map ? -1000.0 : (outside.r >= 0.0 ? outside.r : outside.g);
			float flow = sin((p.x+p.y)*31.0 + sin(map_position.y*3.0+water_time*4.2));
			float streak = sin((p.x+p.y)*16.7-map_position.y*9.0-water_time*6.0);
			float foam = 1.0-smoothstep(0.01,0.16,map_position.y-bottom);
			base = mix(vec3(0.16,0.48,0.49),vec3(0.40,0.70,0.66),flow*0.22+streak*0.08+0.4);
			base = mix(base,vec3(0.76,0.86,0.80),foam*0.55);
			ROUGHNESS = 0.5;
			SPECULAR = 0.35;
		} else {
			vec2 distances = water_bank_distances(p,map_position.y);
			float depth = max(0.0,map_position.y-texture(water_depth,p/128.0).g);
			float offshore = smoothstep(0.0,0.9,distances.x);
			float deep = offshore*0.70 + smoothstep(0.05,2.0,depth)*0.30;
			vec3 waves = water_ripples(p,footprint);
			vec3 normal = normalize(vec3(-waves.x,1.0,-waves.y));
			NORMAL = normalize((VIEW_MATRIX*vec4(normal,0.0)).xyz);
			float fresnel = pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),3.0);
			base = mix(vec3(0.31,0.65,0.58),vec3(0.10,0.37,0.40),deep);
			base += vec3(waves.z);
			vec3 reflected = normalize((INV_VIEW_MATRIX*vec4(reflect(-VIEW,NORMAL),0.0)).xyz);
			vec3 sky = mix(vec3(0.72,0.83,0.78),vec3(0.34,0.57,0.67),smoothstep(0.0,0.8,reflected.y));
			base = mix(base,sky,0.05+fresnel*0.30);
			float edge = 0.055+sin(dot(p,vec2(4.1,3.6))-water_time*1.2)*0.013;
			// The bounded bank search can jump at its outer cutoff. Its
			// derivative must not widen foam into lines on open-water tiles.
			float aa = clamp(footprint,0.008,0.06);
			float foam = 1.0-smoothstep(edge,edge+aa+0.045,distances.x);
			float impact = 1.0-smoothstep(0.02,0.24,distances.y);
			base = mix(base,vec3(0.77,0.86,0.79),max(foam*0.26,impact*0.48));
			EMISSION = water_linear(sky)*(0.015+fresnel*0.06);
			ROUGHNESS = water_quality == 2 ? 0.44 : 0.30;
			SPECULAR = 0.45;
		}
	}
	if (surface_kind == 0 && tile_grid_enabled) {
		base = tile_grid_color(base, map_position, map_normal);
	}
	base = clamp(base, vec3(0.0), vec3(1.0));
	// Procedural vertex colors are authored in sRGB. Mobile shades in linear
	// space; leave Compatibility's existing palette unchanged.
	ALBEDO = OUTPUT_IS_SRGB ? base : mix(pow((base + vec3(0.055)) / 1.055, vec3(2.4)),
		base / 12.92, lessThanEqual(base, vec3(0.04045)));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _surface_shader
	mat.set_shader_parameter("grain_texture", GRAIN)
	mat.set_shader_parameter("sand_texture", SAND_TEXTURE)
	mat.set_shader_parameter("rock_texture", ROCK_TEXTURE)
	mat.set_shader_parameter("road_texture", ROAD_TEXTURE)
	mat.set_shader_parameter("grain_strength", grain_strength)
	mat.set_shader_parameter("surface_kind", surface_kind)
	return mat


## Clip only local candidates, in floor-triangle order. Geometry2D normalizes
## even disjoint subjects, so keep the first eligible operation and the next
## eligible operation after each potentially intersecting cut; this keeps
## fresh triangles and emitted hole contours normalized the same way.
## Inventory and height admission live only for this one chunk build.
static func _dry_water_regions(water_regions: Array[Dictionary], floor: PackedVector3Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if water_regions.is_empty(): return result
	var inventory := _water_cut_inventory(floor)
	var height_admission: Dictionary = {}
	for region: Dictionary in water_regions:
		var top := float(region.top)
		if not height_admission.has(top):
			var eligible: Array[int] = []
			for i: int in inventory.heights.size():
				if float(inventory.heights[i]) > top: eligible.append(i)
			height_admission[top] = eligible
		var eligible: Array[int] = height_admission[top]
		var pieces: Array[PackedVector2Array] = [region.polygon]
		for index: int in _water_clip_candidates(region.polygon,inventory,eligible):
			var remaining: Array[PackedVector2Array] = []
			for piece: PackedVector2Array in pieces:
				remaining.append_array(Geometry2D.clip_polygons(piece,inventory.cuts[index]))
			pieces = remaining
		for polygon: PackedVector2Array in pieces:
			result.append({"polygon":polygon,"top":region.top,"cell":region.cell})
	return result


static func _water_polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	var bounds := Rect2(polygon[0],Vector2.ZERO)
	for point: Vector2 in polygon: bounds = bounds.expand(point)
	return bounds


static func _water_cut_inventory(floor: PackedVector3Array) -> Dictionary:
	var cuts: Array[PackedVector2Array] = []
	var heights: Array[float] = []
	var bins: Dictionary = {}
	for i: int in range(0,floor.size(),3):
		var polygon := PackedVector2Array()
		for j: int in 3: polygon.append(Vector2(floor[i+j].x,floor[i+j].z))
		var index := cuts.size()
		cuts.append(polygon)
		heights.append(minf(floor[i].y,minf(floor[i+1].y,floor[i+2].y)))
		# Cover shared edges and Clipper's precision rounding at city coordinates.
		var bounds := _water_polygon_bounds(polygon).grow(.0001)
		for y: int in range(floori(bounds.position.y),floori(bounds.end.y)+1):
			for x: int in range(floori(bounds.position.x),floori(bounds.end.x)+1):
				var key := Vector2i(x,y)
				if not bins.has(key): bins[key] = []
				bins[key].append(index)
	return {"cuts":cuts,"heights":heights,"bins":bins}


static func _water_clip_candidates(polygon: PackedVector2Array, inventory: Dictionary, eligible: Array[int]) -> Array[int]:
	var result: Array[int] = []
	if eligible.is_empty(): return result
	var seen: Dictionary = {eligible[0]:true}
	var bounds := _water_polygon_bounds(polygon).grow(.0001)
	for y: int in range(floori(bounds.position.y),floori(bounds.end.y)+1):
		for x: int in range(floori(bounds.position.x),floori(bounds.end.x)+1):
			for index: int in inventory.bins.get(Vector2i(x,y),[]):
				var slot := eligible.bsearch(index)
				if slot>=eligible.size() or eligible[slot]!=index: continue
				seen[index] = true
				if slot+1<eligible.size(): seen[eligible[slot+1]] = true
	result.assign(seen.keys())
	result.sort()
	return result
