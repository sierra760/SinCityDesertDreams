# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Shared look for enclosed station rooms, tunnels and access passages: the
## shell palette and the textured finish that replaces their flat-colored faces.
## Tile units (16m per tile).
extends RefCounted

const CREAM := Color(.88,.85,.77)
const CEILING := Color(.36,.49,.51)
const TEAL := Color(.035,.25,.24)
const ENAMEL := Color(.035,.26,.25)
const BRASS := Color(.66,.46,.22)
const LIGHT := Color(1.0,.89,.67)
const STONE := Color(.70,.62,.48)
const INK := Color(.025,.14,.135)
static var _finish_material: ShaderMaterial

## A SurfaceTool using the shared terrazzo/plaster/ceramic shell finish material.
static func finish_tool() -> SurfaceTool:
	var finish := SurfaceTool.new()
	finish.begin(Mesh.PRIMITIVE_TRIANGLES)
	if _finish_material==null:
		_finish_material=ShaderMaterial.new()
		_finish_material.resource_name="stairwell_shared_finishes"
		_finish_material.shader=preload("res://scripts/exploration/transit/stairwell_finish.gdshader")
		_finish_material.set_shader_parameter("terrazzo",load(ExploreStationInterior.ROOT+"warm-terrazzo.png"))
	finish.set_material(_finish_material)
	return finish

## Rebuild the shell triangles `world` added since `face_start` as one textured
## surface in `pose` space. Collision triangles are untouched.
static func finish_passage(world: Node3D, pose: Transform3D, face_start: int) -> void:
	# The flat shell is removed rather than hidden, so nothing z-fights the finish.
	var shell: Dictionary=world.take_shell(face_start)
	var faces: PackedVector3Array=shell.faces
	var colors: PackedColorArray=shell.colors
	var finish := finish_tool()
	var inverse := pose.affine_inverse()
	for triangle: int in range(0,faces.size(),3):
		var a: Vector3=faces[triangle]
		var b: Vector3=faces[triangle+1]
		var c: Vector3=faces[triangle+2]
		var normal := (c-a).cross(b-a).normalized()
		var local_normal := pose.basis.inverse()*normal
		var color: Color=colors[triangle]
		var kind := 0.0 if color==STONE else .4 if color==TEAL else .5 if color==ENAMEL else .6 if color==BRASS else .8 if color==LIGHT else .2
		# Downward-facing cream faces are soffits, tagged by geometry rather than
		# lighting so graded and clipped roofs match.
		if color==CREAM and local_normal.y<-.7:
			color=CEILING
			kind=.26
		for point: Vector3 in [a,b,c]:
			var local: Vector3=inverse*point
			var uv := Vector2(local.z,local.y) if absf(local_normal.x)>.7 else Vector2(local.x,local.z) if absf(local_normal.y)>.7 else Vector2(local.x,local.y)
			finish.set_normal(normal)
			finish.set_color(Color(color,kind))
			finish.set_uv(uv*16.0)
			finish.add_vertex(point)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name="StairwellFinishes"
	floor_mesh.mesh=finish.commit()
	floor_mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(floor_mesh)
