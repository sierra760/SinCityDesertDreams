# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Station name lettering on the pavilion's brass entry cabinet.
## Tile units: subway cabinet faces -Z, rail hall facade faces +Z.
class_name StationEntrySign3D
extends RefCounted
## The rail hall's canopy fascia face is 15.45 m in front of its lot centre
## in the Blender master. The plaque mounts flush on it, above the apron.
const RAIL_PORCH_FRONT := 15.45/16.0
static var _face_material: StandardMaterial3D
static var _letter_material: Material

static func add_to(parent: Node3D, title: String, rail := false) -> Node3D:
	var sign := Node3D.new()
	sign.name="StationEntranceName"
	sign.set_meta("station_entry_name",title)
	parent.add_child(sign)
	if _face_material==null:
		_face_material=StandardMaterial3D.new()
		_face_material.resource_name="station_entry_enamel"
		_face_material.albedo_color=Color(.025,.24,.23)
		_face_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var board := MeshInstance3D.new()
	board.name="NameplateFace"
	var panel := BoxMesh.new()
	panel.size=Vector3(.650,.065,.003) if rail else Vector3(.330,.044,.002)
	panel.material=_face_material
	board.mesh=panel
	# This opaque enamel face replaces the master's generic lettering while
	# preserving its mounted cabinet, brass border and editable fallback.
	board.position=Vector3(0,.325,RAIL_PORCH_FRONT+.0015) if rail else Vector3(.24,.211,-.497)
	board.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sign.add_child(board)
	if rail:
		# Porch columns face local +Z; keep the complete title in front of them.
		_line(sign,board,title.to_upper(),"StationName",.337,.0008,Vector2(.610,.024),true)
		_line(sign,board,"DESERT TRANSIT","TransitOperator",.309,.00025,Vector2(.590,.012),true)
	else:
		_line(sign,board,title.to_upper(),"StationName",.219,.00073,Vector2(.310,.021))
		_line(sign,board,"DESERT TRANSIT","TransitOperator",.198,.00023,Vector2(.300,.010))
	return sign

static func _line(parent: Node3D, board: MeshInstance3D, words: String, node_name: String, height: float, pixel: float, room: Vector2, rail := false) -> void:
	var pose := Transform3D(Basis.IDENTITY,Vector3(0,height,board.position.z+.002)) if rail else Transform3D(Basis(Vector3.UP,PI),Vector3(.24,height,-.4988))
	var label := ExploreStationInterior.add_lettering(parent,pose,words,pixel,Color(.96,.87,.66))
	if _letter_material==null: _letter_material=label.mesh.material
	else: label.mesh.material=_letter_material
	label.name=node_name
	label.set_meta("mutable_station_name",true)
	label.set_meta("title_room",room)
	var bounds := label.mesh.get_aabb().size
	label.scale=Vector3.ONE*minf(1.0,minf(room.x/maxf(bounds.x,.0001),room.y/maxf(bounds.y,.0001)))
	label.set_meta("sign_backing",weakref(board))

## Keep the mounted face and lettering node; only the title mesh and fit change.
static func set_title(sign: Node3D, title: String) -> void:
	sign.set_meta("station_entry_name",title)
	var label: MeshInstance3D = sign.get_node("StationName")
	label.mesh.text = title.to_upper()
	var bounds := label.mesh.get_aabb().size
	var room: Vector2 = label.get_meta("title_room")
	label.scale = Vector3.ONE*minf(1.0,minf(room.x/maxf(bounds.x,.0001),room.y/maxf(bounds.y,.0001)))
