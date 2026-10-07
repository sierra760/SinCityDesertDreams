# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Shared fixtures and sign/mesh queries for Explore street-sign tests.
extends "res://tests/test_case.gd"
const Fixtures := preload("res://tests/fixtures/street_names_fixtures.gd")
const PATH := "res://scripts/view/street_signage_3d.gd"
const TEXT := "res://scripts/view/street_sign_text_3d.gd"

func _available() -> bool:
	var exists := ResourceLoader.exists(PATH) and ResourceLoader.exists(TEXT)
	check(exists,"Explore signage and complete cached lettering must exist")
	return exists

func _keys(value: Array) -> Array[String]:
	var keys: Array[String]=[]
	keys.assign(value)
	return keys

func _layer(f: Dictionary) -> Dictionary:
	var view := CityView3D.new()
	view.city = f.city
	var names := StreetNamingService.new()
	check(names.bind_city(f.city,f.topology).ok)
	var layer: Node3D = load(PATH).new()
	root.add_child(layer)
	layer.bind(view,f.topology,names)
	layer.set_explore_active(true)
	return {"view":view,"layer":layer,"names":names}

func _dispose(f: Dictionary) -> void:
	f.layer.free()
	f.view.free()

func _signs(layer: Node, kind: String = "intersection") -> Array[Node]:
	var result: Array[Node] = []
	for node: Node in layer.find_children("*","Node3D",true,false):
		if node.get_meta("sign_kind","")==kind: result.append(node)
	return result

func sign_names_at(layer: Node) -> Array[String]:
	var result: Array[String] = []
	for assembly: Node in _signs(layer):
		for value: String in assembly.get_meta("display_texts",[]): result.append(value)
	result.sort()
	return result

func _render_support(s: Dictionary, city: City, region: Rect2i) -> CityNetworks3D:
	var networks:=CityNetworks3D.new()
	root.add_child(networks)
	networks._prepare_bridge_decks(city)
	networks._road_tunnels=preload("res://scripts/view/city_road_tunnels_3d.gd").profiles(city)
	networks._build_region(city,region)
	s.view.networks=networks
	# These are actual emitted local surfaces; the declared matching revision
	# lets the detached view fixture expose them through the production seam.
	s.view._has_rendered=true
	s.view._geometry_state=s.view._geometry_inputs(city)
	s.view._geometry_revision+=1
	return networks

func _wet_corners(city: City, cell: Vector2i) -> void:
	for delta: Vector2i in [Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]:
		city.terrain.putv(cell+delta,Terrain.SUBMERGED)

func _check_actual_supported_meshes(assembly: Node3D) -> void:
	var bounds: AABB=assembly.get_meta("world_bounds")
	for node: MeshInstance3D in assembly.find_children("*","MeshInstance3D",true,false):
		var actual: AABB=node.global_transform*node.mesh.get_aabb()
		check(bounds.grow(.000001).encloses(actual),String(node.name)+" stays inside checked actual support envelope")
		if String(node.name)=="GroundShoe":
			for contact: Vector3 in assembly.get_meta("support").contacts:
				check_lt(absf(actual.position.y-contact.y),.0021,"actual rendered shoe rests on support")
				check_lt(minf(absf(contact.x-actual.position.x),absf(contact.x-actual.end.x)),.000002,"contact is an actual shoe X corner")
				check_lt(minf(absf(contact.z-actual.position.z),absf(contact.z-actual.end.z)),.000002,"contact is an actual shoe Z corner")

func _floor_contact(triangles: PackedVector3Array, contact: Vector3) -> Dictionary:
	var height: float=-INF
	for i: int in range(0,triangles.size(),3):
		var hit: Variant=Geometry3D.ray_intersects_triangle(contact+Vector3.UP*10,Vector3.DOWN,triangles[i],triangles[i+1],triangles[i+2])
		if hit is Vector3: height=maxf(height,hit.y)
	return {} if height==-INF else {"height":height}

func _rendered_mesh_contact(networks: CityNetworks3D, contact: Vector3) -> bool:
	for node: MeshInstance3D in networks.find_children("*","MeshInstance3D",true,false):
		for surface: int in node.mesh.get_surface_count():
			var arrays:=node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var count:=indices.size() if not indices.is_empty() else vertices.size()
			for i: int in range(0,count,3):
				var triangle: Array[Vector3]=[]
				for j: int in 3: triangle.append(node.global_transform*vertices[indices[i+j] if not indices.is_empty() else i+j])
				var hit: Variant=Geometry3D.ray_intersects_triangle(contact+Vector3.UP,Vector3.DOWN,triangle[0],triangle[1],triangle[2])
				if hit is Vector3 and absf(hit.y-contact.y)<.00001: return true
	return false
