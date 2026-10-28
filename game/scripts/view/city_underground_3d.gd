# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Exposed utilities and developed-lot conduits, with inspectable crossing levels.
## Stored codes are network connection masks, not shape-ordered import codes.
class_name CityUnderground3D
extends Node3D

const LOWER_OFFSET := 0.12
const UPPER_OFFSET := 0.30
const PIPE_WET := Color(0.22, 0.70, 1.0)
const PIPE_DRY := Color(0.86, 0.39, 0.22)
const LOT_WET := Color(0.10, 0.29, 0.38)
const LOT_DRY := Color(0.38, 0.22, 0.16)
const LOT_OFFSET := 0.025
const FACILITY_COLOR := Color(0.96, 0.89, 0.65)
const STATION_COLOR := Color(0.20, 0.95, 0.79)
const DIRECTIONS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
const NEIGHBORS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
var city: City
var mesh_instance: MeshInstance3D
var rebuild_count := 0
## Observational: tiles projected anew by the last rebuild.
var emitted_cells := 0
## Detached projection inputs of the current mesh: underground, building,
## zone and flag bytes, then the serialized surface inputs. Empty when no mesh.
var _inputs: Array = []
## Each tile's finished triangles (faces, colors, normals) and each row's
## concatenation of them, in the row-major order of a full build.
var _cell_faces: Array[PackedVector3Array] = []
var _cell_colors: Array[PackedColorArray] = []
var _cell_normals: Array[PackedVector3Array] = []
var _row_faces: Array[PackedVector3Array] = []
var _row_colors: Array[PackedColorArray] = []
var _row_normals: Array[PackedVector3Array] = []
## Surface and dry-ground corners with their diagonal per tile. They read
## only the surface inputs, so they stay valid until those change.
var _facets: Dictionary = {}
var _ground_facets: Dictionary = {}
## Flag bits a tile's projection reads: service color and rail bridge axis.
const PROJECTED_FLAGS := TileFlags.WATERED | RotationMapper.AXIS_FLAG
static var _reach := -1
static var _facet_part_cache: Dictionary = {}
static var _ribbon_arm_cache: Dictionary = {}

class RailwayOverlay extends CityNetworks3D:
	var bed_offset := 0.0
	var surface_facets: Dictionary = {}
	func _point(value: City, cell: Vector2i, offset: Vector2, elevation: float) -> Vector3:
		var facet: Array = surface_facets.get(cell, [])
		if facet.is_empty():
			var corners := CityGeometry3D.surface_corners(value, cell)
			facet = [corners, CityGeometry3D.uses_nw_se_diagonal(corners)]
			surface_facets[cell] = facet
		return CityGeometry3D.point_over_facet(facet[0], facet[1], cell, offset)+Vector3.UP*(bed_offset+elevation)
	# The projection draws visible faces only; it has no walking surfaces.
	func _record_physical_points(_cell: Vector2i, _a: Vector3, _b: Vector3, _c: Vector3, _role: int) -> void:
		pass


func _init() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "UndergroundNetworks"
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = CityOverlay3D.analytical_material()
	add_child(mesh_instance)


static func decode(code: int) -> Dictionary:
	var result := {"pipe_mask": 0, "subway_mask": 0, "pipe_above": false, "station": false}
	if code >= 1 and code <= 15: result.pipe_mask = code
	elif code >= 16 and code <= 30: result.subway_mask = code - 15
	elif code >= 31 and code <= 34:
		result.pipe_mask = 5 if code % 2 else 10
		result.subway_mask = 10 if code % 2 else 5
		result.pipe_above = code >= 33
	elif code == 35:
		result.subway_mask = 15
		result.station = true
	return result


## Tiles a changed input can reach: cardinal conduit and rail neighbors, and
## the footprint search that finds a water facility's anchor.
static func reach() -> int:
	if _reach < 0:
		_reach = 1
		for id: int in [Buildings.WATER_PUMP, Buildings.WATER_TOWER, Buildings.WATER_TREATMENT, Buildings.DESALINATION]:
			var size := Buildings.size(id)
			_reach = maxi(_reach, maxi(size.x, size.y) - 1)
	return _reach


func bind_city(value: City) -> void:
	city = value
	_forget()
	# Surface city loads do not need the hidden utility projection. The view
	# calls refresh before revealing Underground, including any hidden edits.
	if visible: refresh()


func clear() -> void:
	city = null
	_forget()


func _forget() -> void:
	_inputs.clear()
	_facets.clear()
	_ground_facets.clear()
	_cell_faces.clear()
	_cell_colors.clear()
	_cell_normals.clear()
	_row_faces.clear()
	_row_colors.clear()
	_row_normals.clear()
	mesh_instance.mesh = null


## Rebuilds only the tiles whose inputs changed, within reach(), and keeps
## every other tile's triangles. The mesh equals a full rebuild's.
func refresh() -> void:
	if city == null:
		_forget()
		return
	var surface := var_to_bytes(CityOverlay3D.surface_inputs(city))
	var now: Array = [city.underground.data, city.building.data, city.zone.data, city.flags.data]
	var dirty := PackedByteArray()
	dirty.resize(City.WIDTH * City.HEIGHT)
	var full: bool = _inputs.is_empty() or surface != _inputs[4]
	if full:
		dirty.fill(1)
	elif not _mark_changes(now, dirty):
		return
	if full:
		_facets.clear()
		_ground_facets.clear()
		for list: Array in [_cell_faces, _cell_colors, _cell_normals]: list.resize(dirty.size())
		for list: Array in [_row_faces, _row_colors, _row_normals]: list.resize(City.HEIGHT)
	_inputs = [now[0].duplicate(), now[1].duplicate(), now[2].duplicate(), now[3].duplicate(), surface]
	emitted_cells = 0
	var ground_sampling := CityGeometry3D.begin_ground_sampling(city)
	var railway := RailwayOverlay.new()
	railway.surface_facets = _facets
	railway._facets = _ground_facets
	var conduits := UtilityParams.conducts_water_table()
	for y in City.HEIGHT:
		var row := y * City.WIDTH
		var first := dirty.find(1, row)
		if first < 0: break
		if first >= row + City.WIDTH: continue
		var row_faces := PackedVector3Array()
		var row_colors := PackedColorArray()
		var row_normals := PackedVector3Array()
		for x in City.WIDTH:
			var i := row + x
			if dirty[i]: _emit_cell(x, y, conduits, railway)
			row_faces.append_array(_cell_faces[i])
			row_colors.append_array(_cell_colors[i])
			row_normals.append_array(_cell_normals[i])
		_row_faces[y] = row_faces
		_row_colors[y] = row_colors
		_row_normals[y] = row_normals
	railway.free()
	CityGeometry3D.end_ground_sampling(ground_sampling)
	var faces := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	for y in City.HEIGHT:
		faces.append_array(_row_faces[y])
		colors.append_array(_row_colors[y])
		normals.append_array(_row_normals[y])
	mesh_instance.mesh = CityGeometry3D.mesh_from_arrays(faces, colors, normals)
	rebuild_count += 1


## Marks every tile within reach() of a changed projection input. Whole layers
## compare natively first, then rows, then the tiles of a changed row.
func _mark_changes(now: Array, dirty: PackedByteArray) -> bool:
	var changed := false
	var radius := reach()
	for layer: int in 4:
		if now[layer] == _inputs[layer]: continue
		var before = _inputs[layer]
		var after = now[layer]
		var mask := PROJECTED_FLAGS if layer == 3 else -1
		for y in City.HEIGHT:
			var row := y * City.WIDTH
			if after.slice(row, row + City.WIDTH) == before.slice(row, row + City.WIDTH): continue
			for x in City.WIDTH:
				if ((int(after[row + x]) ^ int(before[row + x])) & mask) == 0: continue
				changed = true
				for yy in range(maxi(0, y - radius), mini(City.HEIGHT, y + radius + 1)):
					var start := yy * City.WIDTH + maxi(0, x - radius)
					for i in range(start, yy * City.WIDTH + mini(City.WIDTH, x + radius + 1)): dirty[i] = 1
	if not changed:
		# Unprojected flag bits changed alone; keep their bytes for next time.
		_inputs[3] = now[3].duplicate()
	return changed


func _emit_cell(x: int, y: int, conduits: PackedByteArray, railway: RailwayOverlay) -> void:
	var i := y * City.WIDTH + x
	var code := city.underground.data[i]
	var id := city.building.data[i]
	var lot := conduits[id] != 0
	emitted_cells += 1
	var faces := PackedVector3Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	if code != 0 or lot:
		_cell(x, y, code, id, lot, faces, colors, railway)
		normals.resize(faces.size())
		for n: int in range(0, faces.size(), 3):
			var normal := (faces[n + 2] - faces[n]).cross(faces[n + 1] - faces[n]).normalized()
			normals[n] = normal
			normals[n + 1] = normal
			normals[n + 2] = normal
	_cell_faces[i] = faces
	_cell_colors[i] = colors
	_cell_normals[i] = normals


func _cell(x: int, y: int, code: int, id: int, lot: bool, faces: PackedVector3Array,
		colors: PackedColorArray, railway: RailwayOverlay) -> void:
	var decoded := decode(code)
	var cell := Vector2i(x, y)
	var cells: Array[Vector2i] = []
	if not decoded.pipe_mask and not decoded.subway_mask and not lot: return
	var service_color := PIPE_WET if city.is_watered(x,y) else PIPE_DRY
	if lot:
		_lot(cell, LOT_WET if city.is_watered(x,y) else LOT_DRY, faces, colors)
		# Developed and prepared agricultural lots conduct on every side,
		# even without an explicit pipe. Draw those connections
		# independently of the stored underground layer.
		var lot_mask := _water_neighbors(cell)
		if not decoded.pipe_above: lot_mask |= int(decoded.pipe_mask)
		_ribbons(cell, lot_mask, LOWER_OFFSET, 0.13, service_color, faces, cells, colors)
		if UtilityParams.is_water_facility(id) and City.is_footprint_anchor(city.building.data,city.zone.data,x,y):
			_facility(cell,id,faces,cells,colors)
	var pipe_height := UPPER_OFFSET if decoded.pipe_above else LOWER_OFFSET
	var subway_height := LOWER_OFFSET if decoded.pipe_above else UPPER_OFFSET
	var pipe_mask: int = decoded.pipe_mask
	if pipe_mask and not Underground.is_crossing(code):
		# Old and imported endpoints may omit a neighboring building.
		# Attach the projection without rewriting its saved network mask.
		pipe_mask |= _water_neighbors(cell, true)
	if not lot or decoded.pipe_above:
		_ribbons(cell, pipe_mask, pipe_height, 0.13, service_color, faces, cells, colors)
	if decoded.subway_mask:
		# Reuse the actual railway's masks, curves, sleepers, rail gauge and
		# sloped shoulder geometry; analytical pipe layers keep their heights.
		railway.bed_offset=subway_height-.06
		railway._draw_network(city,cell,NetworkShapes.Family.RAIL,decoded.subway_mask,.06)
		faces.append_array(railway._faces)
		colors.append_array(railway._colors)
		railway._faces.clear()
		railway._colors.clear()
		railway._cells.clear()
	if decoded.station: _station(cell, subway_height, faces, cells, colors)


## Surface corners and diagonal choice of `cell`, sampled once per surface.
func _facet(cell: Vector2i) -> Array:
	var facet: Array = _facets.get(cell, [])
	if facet.is_empty():
		var corners := CityGeometry3D.surface_corners(city, cell)
		facet = [corners, CityGeometry3D.uses_nw_se_diagonal(corners)]
		_facets[cell] = facet
	return facet


func _surface_point(cell: Vector2i, offset: Vector2) -> Vector3:
	var facet := _facet(cell)
	return CityGeometry3D.point_over_facet(facet[0], facet[1], cell, offset)


## Water's flood fill joins cardinal conducting tiles. Empty zoning and
## surface roads are not conduits; pipe/subway crossings still carry water.
func _water_neighbors(cell: Vector2i, buildings_only: bool = false) -> int:
	var mask := 0
	var conduits := UtilityParams.conducts_water_table()
	var codes := UtilityParams.conducts_water_code_table()
	var buildings := city.building.data
	var underground := city.underground.data
	for i in 4:
		var neighbor := cell + NEIGHBORS[i]
		if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= City.WIDTH or neighbor.y >= City.HEIGHT: continue
		var at := neighbor.y * City.WIDTH + neighbor.x
		if conduits[buildings[at]] != 0 or (not buildings_only and codes[underground[at]] != 0):
			mask |= 1 << i
	return mask


func _lot(cell: Vector2i, color: Color, faces: PackedVector3Array, colors: PackedColorArray) -> void:
	_faceted_ribbon(cell,[Vector2(.04,.04),Vector2(.96,.04),Vector2(.96,.96),Vector2(.04,.96)],_facet(cell),LOT_OFFSET,color,faces,colors)


## Small batched plan symbols keep sources/storage identifiable while the
## surface models are hidden: pump diamond, tower ring, treatment bars,
## desalination triangle. Inspect supplies the facility's name and live data.
func _facility(cell: Vector2i, id: int, faces: PackedVector3Array,
		_cells: Array[Vector2i], colors: PackedColorArray) -> void:
	var facet := _facet(cell)
	var center := Vector2(.5,.5)
	var sides := 4
	if id == Buildings.WATER_TOWER: sides = 16
	elif id == Buildings.DESALINATION: sides = 3
	for i in sides:
		var angle := TAU * float(i) / sides
		var next := TAU * float(i+1) / sides
		var a := Vector2(cos(angle),sin(angle))
		var b := Vector2(cos(next),sin(next))
		_faceted_ribbon(cell,[center+a*.30,center+b*.30,center+b*.22,center+a*.22],facet,0.36,FACILITY_COLOR,faces,colors)
	if id == Buildings.WATER_TREATMENT:
		for x: float in [-.10,0.0,.10]:
			_faceted_ribbon(cell,[center+Vector2(x-.02,-.16),center+Vector2(x+.02,-.16),center+Vector2(x+.02,.16),center+Vector2(x-.02,.16)],facet,0.36,FACILITY_COLOR,faces,colors)


func _ribbons(cell: Vector2i, mask: int, height: float, width: float,
		color: Color, faces: PackedVector3Array, cells: Array[Vector2i], colors: PackedColorArray) -> void:
	var facet := _facet(cell)
	var corners: PackedVector3Array = facet[0]
	# A valley or isolated raised corner has two different planes. Split at
	# that diagonal so a broad ribbon cannot cut through the terrain facet.
	var planar := is_equal_approx(corners[0].y + corners[3].y, corners[1].y + corners[2].y)
	var diagonal: bool = facet[1]
	var arms := _ribbon_arms(width)
	for i in 4:
		if not mask & (1 << i): continue
		var arm: Array[Vector2] = arms[i]
		if not planar:
			_faceted_ribbon(cell, [arm[0], arm[1], arm[3], arm[2]], facet, height, color, faces, colors)
			continue
		var a := CityGeometry3D.point_over_facet(corners, diagonal, cell, arm[0]) + Vector3.UP * height
		var b := CityGeometry3D.point_over_facet(corners, diagonal, cell, arm[1]) + Vector3.UP * height
		var c := CityGeometry3D.point_over_facet(corners, diagonal, cell, arm[2]) + Vector3.UP * height
		var d := CityGeometry3D.point_over_facet(corners, diagonal, cell, arm[3]) + Vector3.UP * height
		CityGeometry3D.quad(faces, cells, colors, a, b, c, d, cell, color)


## Per direction, the ribbon arm's begin/end points on its two sides:
## [begin - across, end - across, begin + across, end + across].
static func _ribbon_arms(width: float) -> Array:
	var arms: Array = _ribbon_arm_cache.get(width, [])
	if not arms.is_empty(): return arms
	for direction: Vector2 in DIRECTIONS:
		var across := Vector2(-direction.y, direction.x) * width * 0.5
		var begin := Vector2(0.5, 0.5) - direction * width * 0.5
		var end := Vector2(0.5, 0.5) + direction * 0.5
		var arm: Array[Vector2] = [begin - across, end - across, begin + across, end + across]
		arms.append(arm)
	_ribbon_arm_cache[width] = arms
	return arms


## `facet` is the cell's surface corners and diagonal choice (see _facet).
func _faceted_ribbon(cell: Vector2i, polygon: Array[Vector2], facet: Array,
		height: float, color: Color, faces: PackedVector3Array, colors: PackedColorArray) -> void:
	var corners: PackedVector3Array = facet[0]
	var diagonal: bool = facet[1]
	for clipped: Array[Vector2] in _facet_parts(polygon, diagonal):
		var first := CityGeometry3D.point_over_facet(corners, diagonal, cell, clipped[0]) + Vector3.UP * height
		for i in range(1, clipped.size() - 1):
			var b := CityGeometry3D.point_over_facet(corners, diagonal, cell, clipped[i]) + Vector3.UP * height
			var c := CityGeometry3D.point_over_facet(corners, diagonal, cell, clipped[i + 1]) + Vector3.UP * height
			if (b - first).cross(c - first).length_squared() <= 0.000000000001: continue
			faces.push_back(first)
			faces.push_back(b)
			faces.push_back(c)
			colors.push_back(color)
			colors.push_back(color)
			colors.push_back(color)


## `polygon` clipped to each terrain facet of a cell, in facet order; parts
## with fewer than three points are dropped. Pure 2D, so shared by all cells.
static func _facet_parts(polygon: Array[Vector2], diagonal: bool) -> Array:
	var key := [polygon, diagonal]
	var parts: Array = _facet_part_cache.get(key, [])
	if not parts.is_empty() or _facet_part_cache.has(key): return parts
	var facets: Array = [[Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN],
		[Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]]
	if diagonal:
		facets = [[Vector2.ZERO, Vector2.RIGHT, Vector2.ONE], [Vector2.ZERO, Vector2.ONE, Vector2.DOWN]]
	for triangle: Array in facets:
		var clipped := polygon
		for i in 3:
			clipped = _clip_edge(clipped, triangle[i], triangle[(i + 1) % 3])
		if clipped.size() >= 3: parts.append(clipped)
	_facet_part_cache[key.duplicate(true)] = parts
	return parts


static func _clip_edge(polygon: Array[Vector2], a: Vector2, b: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if polygon.is_empty(): return result
	var previous := polygon[-1]
	var before := (b - a).cross(previous - a)
	for current in polygon:
		var now := (b - a).cross(current - a)
		if (now >= 0) != (before >= 0): result.append(previous.lerp(current, before / (before - now)))
		if now >= 0: result.append(current)
		previous = current
		before = now
	return result


func _station(cell: Vector2i, height: float, faces: PackedVector3Array,
		cells: Array[Vector2i], colors: PackedColorArray) -> void:
	var center := _surface_point(cell, Vector2(0.5, 0.5)) + Vector3.UP * height
	var bottom: Array[Vector3] = []
	for offset: Vector3 in [Vector3(-0.11, 0, -0.11), Vector3(0.11, 0, -0.11), Vector3(0.11, 0, 0.11), Vector3(-0.11, 0, 0.11)]:
		bottom.append(center + offset)
	var lift := Vector3.UP * 0.65
	for i in 4:
		var j := (i + 1) % 4
		CityGeometry3D.quad(faces, cells, colors, bottom[i], bottom[j], bottom[i] + lift, bottom[j] + lift, cell, STATION_COLOR)
	CityGeometry3D.quad(faces, cells, colors, bottom[0] + lift, bottom[1] + lift, bottom[3] + lift, bottom[2] + lift, cell, STATION_COLOR)
