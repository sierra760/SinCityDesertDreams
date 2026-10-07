# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Exposed utility ribbons over the terrain, with inspectable crossing levels.
## Stored codes are network connection masks, not shape-ordered import codes.
class_name CityUnderground3D
extends Node3D

const LOWER_OFFSET := 0.12
const UPPER_OFFSET := 0.30
const PIPE_WET := Color(0.22, 0.70, 1.0)
const PIPE_DRY := Color(0.86, 0.39, 0.22)
const STATION_COLOR := Color(0.20, 0.95, 0.79)
const DIRECTIONS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
var city: City
var mesh_instance: MeshInstance3D
var rebuild_count := 0
var _fingerprint := PackedByteArray()

class RailwayOverlay extends CityNetworks3D:
	var bed_offset := 0.0
	func _point(value: City, cell: Vector2i, offset: Vector2, elevation: float) -> Vector3:
		return CityOverlay3D.surface_point(value,cell,offset)+Vector3.UP*(bed_offset+elevation)


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


func bind_city(value: City) -> void:
	city = value
	_fingerprint.clear()
	mesh_instance.mesh = null
	# Surface city loads do not need the hidden utility projection. The view
	# calls refresh before revealing Underground, including any hidden edits.
	if visible: refresh()


func clear() -> void:
	city = null
	_fingerprint.clear()
	mesh_instance.mesh = null


func refresh() -> void:
	if city == null:
		mesh_instance.mesh = null
		return
	var water_flags := PackedByteArray()
	for flag in city.flags.data: water_flags.append(flag & TileFlags.WATERED)
	var fingerprint := var_to_bytes([city.underground.data, water_flags, CityOverlay3D.surface_inputs(city)])
	if fingerprint == _fingerprint: return
	_fingerprint = fingerprint
	var faces := PackedVector3Array()
	var colors := PackedColorArray()
	var cells: Array[Vector2i] = []
	var railway := RailwayOverlay.new()
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var decoded := decode(city.underground.at(x, y))
			if not decoded.pipe_mask and not decoded.subway_mask: continue
			var cell := Vector2i(x, y)
			var pipe_height := UPPER_OFFSET if decoded.pipe_above else LOWER_OFFSET
			var subway_height := LOWER_OFFSET if decoded.pipe_above else UPPER_OFFSET
			_ribbons(cell, decoded.pipe_mask, pipe_height, 0.13,
				PIPE_WET if city.is_watered(x, y) else PIPE_DRY, faces, cells, colors)
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
				railway.clear_physical_patches()
				railway._physical_obstacles.clear()
			if decoded.station: _station(cell, subway_height, faces, cells, colors)
	railway.free()
	mesh_instance.mesh = CityGeometry3D.mesh_from_faces(faces, colors)
	rebuild_count += 1


func _ribbons(cell: Vector2i, mask: int, height: float, width: float,
		color: Color, faces: PackedVector3Array, cells: Array[Vector2i], colors: PackedColorArray) -> void:
	var corners := CityGeometry3D.surface_corners(city, cell)
	for i in 4:
		if not mask & (1 << i): continue
		var direction: Vector2 = DIRECTIONS[i]
		var across := Vector2(-direction.y, direction.x) * width * 0.5
		var begin := Vector2(0.5, 0.5) - direction * width * 0.5
		var end := Vector2(0.5, 0.5) + direction * 0.5
		# A valley or isolated raised corner has two different planes. Split at
		# that diagonal so a broad ribbon cannot cut through the terrain facet.
		if not is_equal_approx(corners[0].y + corners[3].y, corners[1].y + corners[2].y):
			_faceted_ribbon(cell, [begin - across, end - across, end + across, begin + across],
				corners, height, color, faces, colors)
			continue
		var a := CityOverlay3D.surface_point(city, cell, begin - across) + Vector3.UP * height
		var b := CityOverlay3D.surface_point(city, cell, end - across) + Vector3.UP * height
		var c := CityOverlay3D.surface_point(city, cell, begin + across) + Vector3.UP * height
		var d := CityOverlay3D.surface_point(city, cell, end + across) + Vector3.UP * height
		CityGeometry3D.quad(faces, cells, colors, a, b, c, d, cell, color)


func _faceted_ribbon(cell: Vector2i, polygon: Array[Vector2], corners: PackedVector3Array,
		height: float, color: Color, faces: PackedVector3Array, colors: PackedColorArray) -> void:
	var facets: Array = [[Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN],
		[Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]]
	if CityGeometry3D.uses_nw_se_diagonal(corners):
		facets = [[Vector2.ZERO, Vector2.RIGHT, Vector2.ONE], [Vector2.ZERO, Vector2.ONE, Vector2.DOWN]]
	for triangle: Array in facets:
		var clipped := polygon
		for i in 3:
			clipped = _clip_edge(clipped, triangle[i], triangle[(i + 1) % 3])
		if clipped.size() < 3: continue
		var first := CityGeometry3D.point_over_corners(corners, cell, clipped[0]) + Vector3.UP * height
		for i in range(1, clipped.size() - 1):
			var b := CityGeometry3D.point_over_corners(corners, cell, clipped[i]) + Vector3.UP * height
			var c := CityGeometry3D.point_over_corners(corners, cell, clipped[i + 1]) + Vector3.UP * height
			if (b - first).cross(c - first).length_squared() <= 0.000000000001: continue
			faces.append_array(PackedVector3Array([first, b, c]))
			colors.append_array(PackedColorArray([color, color, color]))


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
	var center := CityOverlay3D.surface_point(city, cell, Vector2(0.5, 0.5)) + Vector3.UP * height
	var bottom: Array[Vector3] = []
	for offset: Vector3 in [Vector3(-0.11, 0, -0.11), Vector3(0.11, 0, -0.11), Vector3(0.11, 0, 0.11), Vector3(-0.11, 0, 0.11)]:
		bottom.append(center + offset)
	var lift := Vector3.UP * 0.65
	for i in 4:
		var j := (i + 1) % 4
		CityGeometry3D.quad(faces, cells, colors, bottom[i], bottom[j], bottom[i] + lift, bottom[j] + lift, cell, STATION_COLOR)
	CityGeometry3D.quad(faces, cells, colors, bottom[0] + lift, bottom[1] + lift, bottom[3] + lift, bottom[2] + lift, cell, STATION_COLOR)
