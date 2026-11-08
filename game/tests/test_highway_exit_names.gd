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
			check_lt(sign_node.position.z,19.0,"upstream before mouth")
			check_eq(sign_node.get_meta("support").highway_cell,Vector2i(20,17),"two real highway connections upstream")
		_dispose(s)

func test_named_connector_precedence_first_junction_stop_and_incoming_only() -> void:
	if not _available(): return
	var f:=Fixtures.exit_city()
	var s:=_layer(f)
	var beyond:=StreetTopology.link_key(f.junction+Vector2i.LEFT,&"open",f.junction+Vector2i.LEFT*2,&"open")
	_assign(s,f,beyond,"Too Far Avenue")
	check_eq(exit_names_at(s.layer),[],"first unnamed junction ends search")
	_assign(s,f,f.named,"Fremont Street")
	var first:=StreetTopology.link_key(f.road,&"open",f.road+Vector2i.DOWN,&"open")
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
	for x: int in [20,21]: f.city.building.put(x,17,0)
	f.topology.rebuild(f.city)
	var s:=_layer(f)
	_assign(s,f,f.named,"Palm Avenue")
	check_eq(exit_names_at(s.layer),["Palm Avenue"])
	for sign_node: Node in _signs(s.layer,"exit"):
		check_eq(sign_node.get_meta("support").highway_cell,Vector2i(20,18))
	f.city.building.put(f.road.x,f.road.y,0)
	f.topology.rebuild(f.city)
	s.layer.refresh()
	check_eq(exit_names_at(s.layer),[])
	_dispose(s)

# Measure the rendered gantry, not the obsolete neighbouring-bank supports.
func _check_gantry_meshes(assembly: Node3D, graph: CityTrafficGraph) -> void:
	var support: Dictionary=assembly.get_meta("support")
	var cell: Vector2i=support.highway_cell
	var bounds: AABB=assembly.get_meta("world_bounds")
	check_eq(support.kind,"highway_shoulders")
	check_eq(support.contacts.size(),8,"both shoes have four measured contacts")
	check(Rect2(Vector2(cell),Vector2.ONE).encloses(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))),"entire gantry stays on its own carriageway")
	var shoes:=0
	var posts:=0
	var faces:=0
	for node: MeshInstance3D in assembly.find_children("*","MeshInstance3D",true,false):
		var actual: AABB=node.global_transform*node.mesh.get_aabb()
		var part:=String(node.name)
		check(bounds.grow(.000001).encloses(actual),part+" entire rendered assembly enclosed")
		check(not part.begins_with("Shoulder"),"old ground-standing exit support is removed")
		if part.begins_with("GantryShoe"):
			shoes+=1
			var lowest:=INF
			for delta: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
				var at:=Vector2(actual.position.x,actual.position.z)+Vector2(actual.size.x,actual.size.z)*delta
				var contact:=graph.point(cell,&"highway",at-Vector2(cell))-Vector3.UP*.008
				lowest=minf(lowest,contact.y)
				var recorded:=false
				for measured: Vector3 in support.contacts:
					if measured.distance_to(contact)<.000001: recorded=true
				check(recorded,"contact is an actual shoe corner on the carriageway shoulder")
			check_lt(absf(actual.position.y-lowest),.000001,"actual shoe rests at lowest longitudinal shoulder contact")
			var side:=part.trim_prefix("GantryShoe")
			check_lt(absf(actual.position.y-assembly.position.y-float(support.feet_m[side])/16.0),.000001,"shoe uses its own measured footing")
		elif part.begins_with("GantryPost"):
			posts+=1
			check_gt(node.basis.determinant(),0.0,"lengthening retains outward closed geometry")
			check_ge(actual.end.y,float(support.deck_height)+7.0/16.0,"post reaches the overhead truss")
			var side:=part.trim_prefix("GantryPost")
			check_lt(absf(actual.position.y-assembly.position.y-float(support.feet_m[side])/16.0),.000001,"post reaches its own shoulder footing")
		elif part=="BlankFaceFront":
			faces+=1
			check_gt(actual.position.y,float(support.deck_height)+5.0/16.0,"full operational face clears tall traffic")
	check_eq(shoes,2,"both real gantry shoes checked")
	check_eq(posts,2,"both real gantry posts checked")
	check_eq(faces,1,"operational exit board checked")

func test_actual_gantry_feet_board_height_bounds_and_preservation() -> void:
	if not _available(): return
	var f:=Fixtures.exit_city()
	var s:=_layer(f)
	_assign(s,f,f.named,"W".repeat(48))
	var before:=var_to_bytes(SaveFormat.encode_city(f.city))
	check_eq(_signs(s.layer,"exit").size(),1)
	for assembly: Node3D in _signs(s.layer,"exit"):
		_check_gantry_meshes(assembly,f.topology.traffic_graph())
	for i: int in 5:
		s.layer.refresh()
		s.layer.set_explore_active(false)
		s.layer.set_explore_active(true)
	check_eq(var_to_bytes(SaveFormat.encode_city(f.city)),before,"presentation retains city/funds/saved random state")
	_dispose(s)

func test_wet_upstream_carriageways_fall_back_then_refuse_ramp_mouth() -> void:
	if not _available(): return
	var f:=Fixtures.exit_city()
	# Gantries stand on their own carriageway shoulders, never on an outside
	# bank or a ramp mouth. A wet preferred tile leaves the one-tile lead.
	for x: int in [20,21]: f.city.terrain.put(x,17,Terrain.SUBMERGED)
	f.topology.rebuild(f.city)
	var s:=_layer(f)
	_assign(s,f,f.named,"Palm Avenue")
	check_eq(exit_names_at(s.layer),["Palm Avenue"])
	check_eq(s.layer.diagnostics.size(),0)
	for assembly: Node in _signs(s.layer,"exit"):
		check_eq(assembly.get_meta("support").highway_cell,Vector2i(20,18),"wet preferred carriageway falls through to the supported one-tile lead")
	for x: int in [20,21]: f.city.terrain.put(x,18,Terrain.SUBMERGED)
	f.topology.rebuild(f.city)
	s.layer.refresh()
	check_eq(exit_names_at(s.layer),[],"dry ramp mouth is not a safe gantry fallback")
	check_eq(s.layer.diagnostics.size(),1,"unplaceable named exit reports its reason")
	for diagnostic: Dictionary in s.layer.diagnostics:
		check(String(diagnostic.reason).contains("Bridge deck"),"diagnostic identifies the unsupported upstream carriageways")
	_dispose(s)

func test_sloped_highway_samples_actual_longitudinal_shoulder_height() -> void:
	if not _available(): return
	var f:=Fixtures.exit_city()
	# A real monotonic terrain surface gives the selected upstream tile a
	# resolved longitudinal grade, including the small shoe footprints.
	var surface:=TerrainSurface.new(4)
	for y: int in TerrainSurface.VERTS_Y:
		for x: int in TerrainSurface.VERTS_X:
			surface.set_vertex(x,y,4+clampi(y-16,0,3))
	surface.project(f.city)
	f.topology.rebuild(f.city)
	var s:=_layer(f)
	_assign(s,f,f.named,"Palm Avenue")
	check_eq(exit_names_at(s.layer),["Palm Avenue"])
	var graph: CityTrafficGraph=f.topology.traffic_graph()
	for assembly: Node3D in _signs(s.layer,"exit"):
		var cell: Vector2i=assembly.get_meta("support").highway_cell
		var expected:=graph.point(cell,&"highway",Vector2(.5,.5))
		check_lt(assembly.position.distance_to(expected),.000001,"rigid gantry root is at its carriageway centre")
		check_gt(absf(graph.point(cell,&"highway",Vector2(.5,.9)).y-graph.point(cell,&"highway",Vector2(.5,.1)).y),.01,"fixture genuinely changes longitudinal grade")
		_check_gantry_meshes(assembly,graph)
	_dispose(s)
