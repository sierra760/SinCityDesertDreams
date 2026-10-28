# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## One terrain-following analytical mesh, independent of terrain/model rebuilds.
class_name CityOverlay3D
extends Node3D

const SURFACE_OFFSET := 0.045
var city: City
var active_layer: StringName = &""
var mesh_instance: MeshInstance3D
var rebuild_count := 0
var _fingerprint := PackedByteArray()
## Detached layer, source bytes and sampled block values of the current mesh,
## and each tile row's triangles in the row-major order of a full build.
var _source: Variant = null
var _values := PackedByteArray()
var _row_faces: Array[PackedVector3Array] = []
var _row_colors: Array[PackedColorArray] = []
var _row_normals: Array[PackedVector3Array] = []
## Raised corners and diagonal of each tile (empty until drawn). They read only
## the surface inputs, so they stay valid until those change.
var _corners: Array = []
var _surface := PackedByteArray()


func _init() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "AnalyticalSurface"
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = analytical_material(true)
	add_child(mesh_instance)
	visible = false


func bind_city(value: City) -> void:
	city = value
	_forget()
	refresh()


func set_layer(kind: StringName) -> void:
	if kind == &"none": kind = &""
	if kind != &"" and not CityOverlaySampler.LAYERS.has(kind): return
	active_layer = kind
	visible = kind != &""
	refresh()


func clear() -> void:
	city = null
	_forget()


func _forget() -> void:
	_fingerprint.clear()
	_source = null
	_values.clear()
	_corners.clear()
	_surface.clear()
	_row_faces.clear()
	_row_colors.clear()
	_row_normals.clear()
	mesh_instance.mesh = null


## Unchanged source bytes return at once; changed sample values rebuild only
## the tile rows of their blocks. The mesh equals a full rebuild's.
func refresh() -> void:
	if city == null or active_layer == &"":
		_forget()
		return
	var surface := var_to_bytes(surface_inputs(city))
	if surface != _surface:
		_surface = surface
		_corners.clear()
	var fingerprint := var_to_bytes([active_layer, surface])
	var source: Variant = CityOverlaySampler.source_data(city, active_layer)
	var full := fingerprint != _fingerprint or _row_faces.is_empty()
	if not full and source == _source: return
	var values := PackedByteArray()
	var block := CityOverlaySampler.tiles_per_cell(active_layer)
	for y in range(0, City.HEIGHT, block):
		for x in range(0, City.WIDTH, block):
			values.append(CityOverlaySampler.value_at(city, active_layer, Vector2i(x, y)))
	_source = source.duplicate()
	if not full and values == _values: return
	var blocks_per_row := City.WIDTH / block
	var dirty := PackedByteArray()
	dirty.resize(City.HEIGHT)
	if full:
		dirty.fill(1)
		for list: Array in [_row_faces, _row_colors, _row_normals]: list.resize(City.HEIGHT)
	else:
		for by in City.HEIGHT / block:
			var at := by * blocks_per_row
			if values.slice(at, at + blocks_per_row) == _values.slice(at, at + blocks_per_row): continue
			for y in range(by * block, (by + 1) * block): dirty[y] = 1
	_fingerprint = fingerprint
	_values = values
	if _corners.is_empty(): _corners.resize(City.WIDTH * City.HEIGHT)
	var ground_sampling := CityGeometry3D.begin_ground_sampling(city)
	var cells: Array[Vector2i] = []
	for y in City.HEIGHT:
		if not dirty[y]: continue
		var faces := PackedVector3Array()
		var colors := PackedColorArray()
		var by := y / block
		for x in City.WIDTH:
			var cell := Vector2i(x, y)
			var color := CityOverlaySampler.cell_color(active_layer, values[by * blocks_per_row + x / block])
			if color.a <= 0.003: continue
			var raised: Array = _corners[y * City.WIDTH + x] if _corners[y * City.WIDTH + x] != null else []
			if raised.is_empty():
				var corners := CityGeometry3D.surface_corners(city, cell)
				for i in corners.size(): corners[i].y += SURFACE_OFFSET
				raised = [corners, CityGeometry3D.uses_nw_se_diagonal(corners)]
				_corners[y * City.WIDTH + x] = raised
			var points: PackedVector3Array = raised[0]
			if raised[1]:
				CityGeometry3D.quad(faces, cells, colors, points[1], points[3], points[0], points[2], cell, color)
			else:
				CityGeometry3D.quad(faces, cells, colors, points[0], points[1], points[2], points[3], cell, color)
		cells.clear()
		var normals := PackedVector3Array()
		normals.resize(faces.size())
		for n: int in range(0, faces.size(), 3):
			var normal := (faces[n + 2] - faces[n]).cross(faces[n + 1] - faces[n]).normalized()
			normals[n] = normal
			normals[n + 1] = normal
			normals[n + 2] = normal
		_row_faces[y] = faces
		_row_colors[y] = colors
		_row_normals[y] = normals
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


## Only inputs actually defining the visible utility/analytical surface.
static func surface_inputs(value: City) -> Array:
	var vertices := PackedByteArray()
	if value.terrain_surface is TerrainSurface: vertices = value.terrain_surface.vertices
	return [value.terrain.data, value.altitude.data, vertices, value.flood_overlay]


static func surface_point(value: City, cell: Vector2i, offset: Vector2) -> Vector3:
	return CityGeometry3D.point_over_corners(CityGeometry3D.surface_corners(value, cell), cell, offset)


static func analytical_material(translucent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if translucent: material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
