# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Marks the tiles an offered on-ramp could take while the player decides:
## every candidate gets a brass outline, the selected one a glowing fill and
## a bobbing marker above it. Presentation only; nothing here is picked.
class_name CityRampHighlight3D
extends Node3D

const LIFT := 0.08
const MARKER_HEIGHT := 1.6
const SITE_COLOR := Color(1.0, 0.82, 0.42)
const SELECTED_COLOR := Color(0.25, 1.0, 0.85)

## The candidate tiles shown, and the index of the selected one.
var sites: Array[Vector2i] = []
var selected := -1
var _marker: Node3D
var _fill_material: StandardMaterial3D
var _time := 0.0


func _init() -> void:
	name = "RampHighlight"
	set_process(false)


func show_sites(city: City, cells: Array, selection: int) -> void:
	_remove_geometry()
	sites.clear()
	if city == null:
		return
	for cell: Variant in cells:
		if cell is Vector2i and city.in_bounds(cell.x, cell.y):
			sites.append(cell)
	selected = selection if selection >= 0 and selection < sites.size() else -1
	for i in sites.size():
		_tile(city, sites[i], i == selected)
	set_process(not sites.is_empty())


func clear() -> void:
	sites.clear()
	selected = -1
	_remove_geometry()
	set_process(false)


func is_showing() -> bool:
	return not sites.is_empty()


func _process(delta: float) -> void:
	_time += delta
	var pulse := 0.5 + 0.5 * sin(_time * TAU * 0.8)
	if _fill_material != null:
		_fill_material.albedo_color.a = lerpf(0.18, 0.42, pulse)
	if _marker != null:
		_marker.position.y = float(_marker.get_meta("base_y", 0.0)) + 0.18 * pulse


func _remove_geometry() -> void:
	_marker = null
	_fill_material = null
	for child in get_children():
		remove_child(child)
		child.queue_free()


static func _material(color: Color, priority: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = priority
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _tile(city: City, cell: Vector2i, chosen: bool) -> void:
	var group := Node3D.new()
	group.name = "Selected" if chosen else "Site"
	group.set_meta("cell", cell)
	add_child(group)
	var corners := CityGeometry3D.surface_corners(city, cell)
	var color := SELECTED_COLOR if chosen else SITE_COLOR
	var outline := _material(color, 124)
	for edge: Array in [[0, 1], [1, 3], [3, 2], [2, 0]]:
		var a: Vector3 = corners[edge[0]] + Vector3.UP * LIFT
		var b: Vector3 = corners[edge[1]] + Vector3.UP * LIFT
		var box := BoxMesh.new()
		box.size = Vector3(0.07 if chosen else 0.04, 0.014, a.distance_to(b))
		var line := MeshInstance3D.new()
		line.mesh = box
		line.material_override = outline
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(line)
		line.position = (a + b) / 2.0
		line.look_at(b)
	if not chosen:
		return
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	for i: int in [0, 1, 2, 1, 3, 2]:
		vertices.append(corners[i] + Vector3.UP * LIFT)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_fill_material = _material(Color(SELECTED_COLOR, 0.3), 123)
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	fill.mesh = mesh
	fill.material_override = _fill_material
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	group.add_child(fill)
	# A downward-pointing marker floating over the tile, visible through
	# buildings and from far out.
	var cone := CylinderMesh.new()
	cone.top_radius = 0.32
	cone.bottom_radius = 0.0
	cone.height = 0.6
	cone.radial_segments = 4
	cone.rings = 1
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	marker.mesh = cone
	marker.material_override = _material(SELECTED_COLOR, 125)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var top := 0.0
	for corner: Vector3 in corners:
		top = maxf(top, corner.y)
	var base_y := top + MARKER_HEIGHT
	marker.position = Vector3(cell.x + 0.5, base_y, cell.y + 0.5)
	marker.set_meta("base_y", base_y)
	group.add_child(marker)
	_marker = marker
