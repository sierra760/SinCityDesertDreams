# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"

func _faces(model: Node3D) -> PackedVector3Array:
	var result:=PackedVector3Array()
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		var at:=model.global_transform.affine_inverse()*mesh.global_transform
		for point: Vector3 in mesh.mesh.get_faces():result.append(at*point)
	return result

func _front_surface(faces: PackedVector3Array, x: float, y: float) -> float:
	var nearest:=-INF
	var from:=Vector3(x,y,1.1)
	for i: int in range(0,faces.size(),3):
		var hit: Variant=Geometry3D.ray_intersects_triangle(from,Vector3.FORWARD,faces[i],faces[i+1],faces[i+2])
		if hit is Vector3:nearest=maxf(nearest,hit.z)
	return nearest

func test_complete_rail_title_is_in_front_of_real_porch_columns_on_supported_mount() -> void:
	var catalog:=CityModelCatalog.new()
	check_eq(catalog.load_manifest(CityModelCatalog.ROOT+"catalog.json"),OK)
	var model:=catalog.instantiate_model(Buildings.RAIL_STATION)
	root.add_child(model)
	var original_faces:=_faces(model)
	var original_nodes: Array=[]
	for node: Node in model.find_children("*","Node3D",true,false):original_nodes.append([node.get_instance_id(),node.transform])
	var sign_node:=StationEntrySign3D.add_to(model,"Bristlecone Artists Promenade 2",true)
	var board: MeshInstance3D=sign_node.get_node("NameplateFace")
	var board_box:=board.transform*board.mesh.get_aabb()
	for x: float in [-4.75/16.0,0.0,4.75/16.0]:
		var front:=_front_surface(original_faces,x,board.position.y)
		check(is_finite(front),"real emitted porch column supports mount")
		check_lt(absf(board_box.position.z-front),.0001,"opaque face back sits on actual original wood front")
	check_gt(board_box.position.y,.0425+.115+.01,"mounted face retains standing passage clearance")
	for title: String in ["Sierra Central","Bristlecone Artists Promenade 2","W".repeat(99)]:
		StationEntrySign3D.set_title(sign_node,title)
		var letters: MeshInstance3D=sign_node.get_node("StationName")
		var bounds:=letters.transform*letters.mesh.get_aabb()
		check_eq(letters.mesh.text,title.to_upper())
		check(bounds.position.x>board_box.position.x and bounds.end.x<board_box.end.x)
		var blocked:=0
		for sample: int in 65:
			var x:=lerpf(bounds.position.x,bounds.end.x,float(sample)/64)
			if _front_surface(original_faces,x,bounds.get_center().y)>bounds.position.z+.000001:blocked+=1
		check_eq(blocked,0,"complete mounted title has no original porch geometry in front")
	var after: Array=[]
	for node: Node in model.find_children("*","Node3D",true,false):
		if node!=sign_node and not sign_node.is_ancestor_of(node):after.append([node.get_instance_id(),node.transform])
	check_eq(after,original_nodes,"all original building/model/collision instances and transforms retained")
	model.free();await physics_frame
