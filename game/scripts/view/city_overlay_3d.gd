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


func _init() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "AnalyticalSurface"
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = analytical_material(true)
	add_child(mesh_instance)
	visible = false


func bind_city(value: City) -> void:
	city = value
	_fingerprint.clear()
	refresh()


func set_layer(kind: StringName) -> void:
	if kind == &"none": kind = &""
	if kind != &"" and not CityOverlaySampler.LAYERS.has(kind): return
	active_layer = kind
	visible = kind != &""
	refresh()


func clear() -> void:
	city = null
	_fingerprint.clear()
	mesh_instance.mesh = null


func refresh() -> void:
	if city == null or active_layer == &"":
		mesh_instance.mesh = null
		_fingerprint.clear()
		return
	var values := PackedByteArray()
	var block := CityOverlaySampler.tiles_per_cell(active_layer)
	for y in range(0, City.HEIGHT, block):
		for x in range(0, City.WIDTH, block):
			values.append(CityOverlaySampler.value_at(city, active_layer, Vector2i(x, y)))
	var fingerprint := var_to_bytes([active_layer, values, surface_inputs(city)])
	if fingerprint == _fingerprint: return
	_fingerprint = fingerprint
	var faces := PackedVector3Array()
	var colors := PackedColorArray()
	var cells: Array[Vector2i] = []
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var cell := Vector2i(x, y)
			var color := CityOverlaySampler.cell_color(active_layer, CityOverlaySampler.value_at(city, active_layer, cell))
			if color.a <= 0.003: continue
			var points := CityGeometry3D.surface_corners(city, cell)
			for i in points.size(): points[i].y += SURFACE_OFFSET
			if CityGeometry3D.uses_nw_se_diagonal(points):
				CityGeometry3D.quad(faces, cells, colors, points[1], points[3], points[0], points[2], cell, color)
			else:
				CityGeometry3D.quad(faces, cells, colors, points[0], points[1], points[2], points[3], cell, color)
	mesh_instance.mesh = CityGeometry3D.mesh_from_faces(faces, colors)
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
