# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/street_signs_case.gd"

func exit_names_at(layer: Node) -> Array[String]:
	var result: Array[String]=[]
	for node: Node in _signs(layer,"exit"): result.append(node.get_meta("display_text"))
	return result

func _assign(s: Dictionary,f: Dictionary,key: String,text: String) -> void:
	var keys: Array[String]=[key]
	check(s.names.assign(keys,text,f.topology.revision).ok)

# Actual rendered destinations exercise topology traversal without reimplementing it.
func test_true_exit_direction_connector_limit_and_pair_dedup() -> void:
	if not _available(): return
	for length: int in [3,8,9]:
		var f:=Fixtures.exit_city(length)
		var s:=_layer(f)
		_assign(s,f,f.named,"Fremont Street")
		var east:=StreetTopology.link_key(f.junction,&"open",f.junction+Vector2i.RIGHT,&"open")
		_assign(s,f,east,"Palm Avenue")
		check_eq(exit_names_at(s.layer),["Palm Avenue & Fremont Street"] if length<=8 else [])
		check_eq(s.layer.diagnostics.size(),0,"ordinary exit support is legal")
		for sign_node: Node3D in _signs(s.layer,"exit"):
			check_eq(sign_node.get_meta("travel_direction"),Vector2i.DOWN)
			check(sign_node.basis.z.dot(Vector3.FORWARD)>.999,"front faces incoming northward viewer")
			check_eq(sign_node.get_meta("arrow"),"→","west ramp is driver's right travelling south")
			check_lt(sign_node.position.z,20.0,"upstream before mouth")
			check_eq(sign_node.get_meta("support").highway_cell,Vector2i(20,18),"two real highway connections upstream")
		_dispose(s)

func test_named_connector_precedence_first_junction_stop_and_incoming_only() -> void:
	if not _available(): return
	var f:=Fixtures.exit_city()
	var s:=_layer(f)
	var beyond:=StreetTopology.link_key(f.junction+Vector2i.LEFT,&"open",f.junction+Vector2i.LEFT*2,&"open")
	_assign(s,f,beyond,"Too Far Avenue")
	check_eq(exit_names_at(s.layer),[],"first unnamed junction ends search")
	_assign(s,f,f.named,"Fremont Street")
	var first:=StreetTopology.link_key(f.road,&"open",f.road+Vector2i.UP,&"open")
	_assign(s,f,first,"Connector Road")
	check_eq(exit_names_at(s.layer),["Connector Road"])
	_dispose(s)
	f=Fixtures.exit_city(3,true)
	s=_layer(f)
	_assign(s,f,f.named,"Fremont Street")
	check_eq(exit_names_at(s.layer),[],"entrance-only ramp")
	_dispose(s)

func test_disconnected_overpass_and_short_upstream_fallback() -> void:
	if not _available(): return
	var f:=Fixtures.exit_city()
	for x: int in [20,21]: f.city.building.put(x,18,0)
	f.topology.rebuild(f.city)
	var s:=_layer(f)
	_assign(s,f,f.named,"Palm Avenue")
	check_eq(exit_names_at(s.layer),["Palm Avenue"])
	for sign_node: Node in _signs(s.layer,"exit"):
		check_eq(sign_node.get_meta("support").highway_cell,Vector2i(20,19))
	f.city.building.put(19,19,0)
	f.topology.rebuild(f.city)
	s.layer.refresh()
	check_eq(exit_names_at(s.layer),[])
	_dispose(s)

# A floating pole or an incorrectly shifted board cannot pass via metadata.
func test_actual_extended_feet_board_height_bounds_and_preservation() -> void:
	if not _available(): return
	var f:=Fixtures.exit_city()
	var s:=_layer(f)
	_assign(s,f,f.named,"W".repeat(48))
	var before:=var_to_bytes(SaveFormat.encode_city(f.city))
	check_eq(_signs(s.layer,"exit").size(),1)
	for assembly: Node3D in _signs(s.layer,"exit"):
		var support: Dictionary=assembly.get_meta("support")
		check_between(support.lateral_offset,0.0,2.0,"bounded local outer-side ground")
		check_gt(support.lateral_offset,1.0,"adjacent connector is not covered by support")
		check_eq(support.contacts.size(),8,"both shoes have four measured contacts")
		var bounds: AABB=assembly.get_meta("world_bounds")
		for node: Node in assembly.find_children("*","MeshInstance3D",true,false):
			var mesh_node:=node as MeshInstance3D
			var actual: AABB=mesh_node.global_transform*mesh_node.mesh.get_aabb()
			check(bounds.grow(.000001).encloses(actual),String(node.name)+" entire rendered assembly enclosed")
			if String(node.name).begins_with("ShoulderShoe"):
				for delta: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
					var at:=Vector2(actual.position.x,actual.position.z)+Vector2(actual.size.x,actual.size.z)*delta
					var cell:=Vector2i(floori(at.x),floori(at.y))
					var floor_point:=CityGeometry3D.point_on_ground(f.city,cell,at-Vector2(cell))
					check_lt(absf(actual.position.y-floor_point.y),.0021,"actual shoe rests on floor")
			if String(node.name).begins_with("ShoulderPost"):
				check_gt(mesh_node.basis.determinant(),0.0,"lengthening retains outward closed geometry")
				check_lt(absf(actual.end.y-float(support.deck_height)-3.96/16.0),.00001,"post still overlaps authored board back")
			if String(node.name)=="BlankFaceFront":
				check_gt(actual.position.y,float(support.deck_height)+.12,"full operational face stands above roadway")
		check_lt(bounds.end.x,19.0,"whole board and support clear adjacent connector lane")
	for i: int in 5:
		s.layer.refresh()
		s.layer.set_explore_active(false)
		s.layer.set_explore_active(true)
	check_eq(var_to_bytes(SaveFormat.encode_city(f.city)),before,"presentation retains city/funds/saved random state")
	_dispose(s)

func test_unsupported_upstream_water_falls_back_to_supported_mouth() -> void:
	if not _available(): return
	var f:=Fixtures.exit_city()
	# A declared wet outer bank excludes both upstream posts, while the ramp
	# mouth has a dry outside corner. No replacement road/bridge geometry.
	for y: int in [18,19]:
		f.city.terrain.put(18,y,Terrain.SUBMERGED)
		for x: int in [20,21]: f.city.terrain.put(x,y,Terrain.SUBMERGED)
	f.topology.rebuild(f.city)
	var s:=_layer(f)
	_assign(s,f,f.named,"Palm Avenue")
	check_eq(exit_names_at(s.layer),["Palm Avenue"])
	check_eq(s.layer.diagnostics.size(),0)
	for assembly: Node in _signs(s.layer,"exit"):
		check_eq(assembly.get_meta("support").highway_cell,Vector2i(20,20),"unsafe earlier candidates fall through to dry mouth")
	_dispose(s)

func test_sloped_highway_samples_actual_longitudinal_shoulder_height() -> void:
	if not _available(): return
	var f:=Fixtures.exit_city()
	# Raised highway row creates an actual longitudinal resolved approach;
	# outer bank remains dry and locally level for the measured post shoes.
	for x: int in [20,21]: f.city.set_heights(x,19,5,0)
	f.topology.rebuild(f.city)
	var s:=_layer(f)
	_assign(s,f,f.named,"Palm Avenue")
	check_eq(exit_names_at(s.layer),["Palm Avenue"])
	var graph:=CityTrafficGraph.new()
	graph.bind_city(f.city)
	for assembly: Node3D in _signs(s.layer,"exit"):
		var support: Dictionary=assembly.get_meta("support")
		var cell: Vector2i=support.highway_cell
		var expected:=graph.point(cell,&"highway",Vector2(.04,assembly.position.z-cell.y))
		check_lt(absf(assembly.position.y-expected.y),.000001,"board root matches real shoulder height at its own upstream coordinate")
		check_gt(absf(expected.y-graph.point(cell,&"highway",Vector2(.04,.5)).y),.001,"fixture genuinely changes longitudinal grade")
	_dispose(s)
