# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Read-only tile feedback separate from construction and physics picking.
class_name CityQueryFeedback3D
extends Node3D
const INVALID := Vector2i(-1,-1)
const LIFT := 0.075
var hovered := INVALID
var selected := INVALID
var _signature := 0

func show_tiles(city: City, hover: Vector2i, selection: Vector2i, revision: int) -> void:
	if city == null:
		clear()
		return
	hovered = hover if city.in_bounds(hover.x,hover.y) else INVALID
	selected = selection if city.in_bounds(selection.x,selection.y) else INVALID
	var signature := hash([city.get_instance_id(),hovered,selected,revision])
	if signature == _signature: return
	_remove_geometry()
	_signature = signature
	if selected != INVALID: _tile(city,selected,true)
	if hovered != INVALID and hovered != selected: _tile(city,hovered,false)

func clear() -> void:
	hovered = INVALID
	selected = INVALID
	_signature = 0
	_remove_geometry()

func _remove_geometry() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

func _material(color: Color, priority: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = priority
	if color.a < 1.0: mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func _tile(city: City, cell: Vector2i, chosen: bool) -> void:
	var group := Node3D.new()
	group.name = "Selected" if chosen else "Hovered"
	add_child(group)
	var corners := CityGeometry3D.surface_corners(city,cell)
	var mat := _material(Color(0.22,1.0,0.83) if chosen else Color(1.0,0.89,0.61),122)
	for edge: Array in [[0,1],[1,3],[3,2],[2,0]]:
		var a: Vector3 = corners[edge[0]]+Vector3.UP*LIFT
		var b: Vector3 = corners[edge[1]]+Vector3.UP*LIFT
		var box := BoxMesh.new()
		box.size = Vector3(0.045 if chosen else 0.025,0.012,a.distance_to(b))
		var line := MeshInstance3D.new()
		line.mesh = box
		line.material_override = mat
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(line)
		line.position = (a+b)/2.0
		line.look_at(b)
	if chosen:
		var mesh := ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		var vertices := PackedVector3Array()
		for i: int in [0,1,2,1,3,2]: vertices.append(corners[i]+Vector3.UP*LIFT)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var fill := MeshInstance3D.new()
		fill.name = "SelectionFill"
		fill.mesh = mesh
		fill.material_override = _material(Color(0.12,0.9,0.73,0.12),121)
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(fill)
