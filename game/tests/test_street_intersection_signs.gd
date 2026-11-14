# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/street_signs_case.gd"

# Missing named-arm filtering or opposite-ID grouping changes rendered blades.
func test_named_arms_only_and_different_opposing_names() -> void:
	if not _available(): return
	var f := Fixtures.junction()
	var demolition:=Builder.new(f.city,CityStats.new()).apply(Tools.Kind.BULLDOZE,Vector2i(9,8),Vector2i(10,8))
	check(demolition.ok and demolition.applied)
	f.topology.rebuild(f.city)
	check_eq(f.topology.junctions({})[0].approaches.size(),3,"actual paid T junction")
	var s := _layer(f)
	check_eq(sign_names_at(s.layer),[])
	check(s.names.assign(_keys(f.arms.north),"Palm Avenue",f.topology.revision).ok)
	check_eq(sign_names_at(s.layer),["Palm Avenue"])
	check(s.names.assign(_keys(f.arms.south),"Palm Avenue",f.topology.revision).ok)
	check_eq(sign_names_at(s.layer),["Palm Avenue"],"same opposite identity has one blade")
	check(s.names.assign(_keys(f.arms.south),"Fremont Street",f.topology.revision).ok)
	check_eq(sign_names_at(s.layer),["Fremont Street","Palm Avenue"])
	check_eq(s.layer.diagnostics.size(),0,"ordinary legal junction places")
	var signs := _signs(s.layer)
	if not signs.is_empty():
		check_eq(signs[0].get_meta("street_ids").size(),2)
		check_eq(signs[0].get_meta("blade_directions").size(),2)
		check_ne(signs[0].get_meta("blade_directions")[0],signs[0].get_meta("blade_directions")[1])
	_dispose(s)

# Hidden aerial signage defers work; Explore entry and geometry revisions that
# change nothing retain the same assemblies and uploaded batches.
func test_hidden_signage_defers_and_unchanged_geometry_keeps_batches() -> void:
	if not _available(): return
	var f := Fixtures.junction()
	var s := _layer(f)
	s.layer.set_explore_active(false)
	check(s.names.assign(_keys(f.arms.north),"Palm Avenue",f.topology.revision).ok)
	check_eq(_signs(s.layer).size(),0,"aerial naming does not build hidden signs")
	s.layer.set_explore_active(true)
	check_eq(sign_names_at(s.layer),["Palm Avenue"],"entering Explore builds the deferred signs")
	var assembly := _signs(s.layer)[0].get_instance_id()
	var batch_ids: Array[int]=[]
	for node: Node in s.layer._batches.get_children(): batch_ids.append(node.get_instance_id())
	check(not batch_ids.is_empty())
	s.view._geometry_revision+=1
	s.view.geometry_rebuilt.emit(s.view._geometry_revision)
	var after: Array[int]=[]
	for node: Node in s.layer._batches.get_children(): after.append(node.get_instance_id())
	check_eq(_signs(s.layer)[0].get_instance_id(),assembly,"unchanged placement keeps the assembly")
	check_eq(after,batch_ids,"unchanged placement keeps the uploaded batches")
	s.layer.set_explore_active(false)
	check(s.names.assign(_keys(f.arms.north),"Fremont Street",f.topology.revision).ok)
	check_eq(sign_names_at(s.layer),["Palm Avenue"],"hidden signs wait for Explore")
	s.layer.set_explore_active(true)
	check_eq(sign_names_at(s.layer),["Fremont Street"])
	_dispose(s)

# Incorrect support sampling or clearance must not hide behind successful tags.
func test_grade_support_and_passage_clearance() -> void:
	if not _available(): return
	var f := Fixtures.junction()
	for y: int in range(4,13):
		for x: int in range(4,13): f.city.set_heights(x,y,7,0)
	f.topology.rebuild(f.city)
	var s := _layer(f)
	check(s.names.assign(_keys(f.arms.north),"Palm Avenue",f.topology.revision).ok)
	check_eq(s.layer.diagnostics.size(),0)
	check_eq(_signs(s.layer).size(),1)
	for sign_node: Node3D in _signs(s.layer):
		var support: Dictionary = sign_node.get_meta("support")
		check_lt(absf(sign_node.position.y-float(support.height)),.000001)
		check_gt(sign_node.position.y,.5,"raised grade is used")
		check(sign_node.get_meta("world_bounds") is AABB)
		check(sign_node.get_meta("batch_region") is Rect2i)
		check(bool(support.clearance_checked),"whole maximum assembly checked")
	# Developed lots in every corner no longer hide the sign: it stands on the
	# junction tile's own verge and stays inside that tile.
	for cell: Vector2i in [Vector2i(7,7),Vector2i(9,7),Vector2i(7,9),Vector2i(9,9)]:
		f.city.building.putv(cell,Buildings.SUBWAY_STATION)
	s.layer.refresh()
	check_eq(_signs(s.layer).size(),1,"corner lots cannot suppress an on-tile sign")
	check_eq(s.layer.diagnostics.size(),0)
	for sign_node: Node3D in _signs(s.layer): _check_on_junction_tile(sign_node,Vector2i(8,8))
	_dispose(s)

## The whole assembly is inside one verge corner of the junction tile: never
## over a lane, a neighbouring tile or the sidewalk line 0.10 tile in.
func _check_on_junction_tile(assembly: Node3D, cell: Vector2i) -> void:
	var support: Dictionary=assembly.get_meta("support")
	check_eq(support.kind,"junction_verge")
	var corner: Vector2=support.corner
	var edge: float=(1.0-CityNetworks3D.ROAD_WIDTH)*.5
	var square:=Rect2(Vector2(cell)+corner*(1.0-edge),Vector2(edge,edge)).grow(.0006)
	for node: MeshInstance3D in assembly.find_children("*","MeshInstance3D",true,false):
		var box: AABB=node.global_transform*node.mesh.get_aabb() if node.is_inside_tree() else assembly.transform*_local(assembly,node)*node.mesh.get_aabb()
		check(square.encloses(Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z))),String(node.name)+" stays in the junction tile's verge corner")
	var post:=Vector2(assembly.position.x,assembly.position.z)-Vector2(cell)
	var inset:=Vector2(absf(post.x-corner.x),absf(post.y-corner.y))
	check_gt(minf(inset.x,inset.y),.13,"post clears the sidewalk walking line")
	check_lt(maxf(inset.x,inset.y),.16,"post stays on the verge, outside the shoulder")

func _local(assembly: Node3D, node: Node3D) -> Transform3D:
	var t:=Transform3D.IDENTITY
	var at: Node=node
	while at!=assembly:
		t=(at as Node3D).transform*t
		at=at.get_parent()
	return t

# Truncation, shared mutable cached nodes, or an unbounded cache violates spelling/lifetime.
func test_long_names_complete_and_cache_bounded() -> void:
	if not _available(): return
	var script: Script = load(TEXT)
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/street-name-signs/templates.json"))
	var face: Dictionary = contract.templates["street-blade"].duplicate(true)
	face.font = contract.font
	var full := "W".repeat(48)
	var layout: Dictionary = script.layout(full,face)
	check_eq("".join(layout.lines),full,"all characters retain exact spelling")
	check(layout.lines.size()<=2)
	check(layout.bounds.size.x<float(face.layout.destination_safe_m[0]))
	check(layout.bounds.size.y<float(face.layout.destination_safe_m[1]))
	var again: Dictionary = script.layout(full,face)
	check_eq(layout.meshes[0].mesh.get_instance_id(),again.meshes[0].mesh.get_instance_id(),"immutable mesh resource reused")
	for i: int in 160: script.layout("Palm Avenue "+str(i),face)
	check(script.cache_size()<=128)
	face.layout.destination_safe_m=[2.0,.48]
	var narrow: Dictionary=script.layout(full,face)
	check(narrow.bounds.size.x<2.0,"face dimensions are in the cache key")

# Visibility/reload must preserve cache and use the new City's metadata.
func test_visibility_rename_and_identical_city_replacement() -> void:
	if not _available(): return
	var f := Fixtures.junction()
	var s := _layer(f)
	check(s.names.assign(_keys(f.arms.north),"Palm Avenue",f.topology.revision).ok)
	var original := _signs(s.layer)[0].get_instance_id()
	var text_count: int = load(TEXT).cache_size()
	var mesh_ids: Array[int]=[]
	for node: MeshInstance3D in s.layer.find_children("*","MeshInstance3D",true,false): mesh_ids.append(node.mesh.get_instance_id())
	var batch_ids: Array[int]=[]
	for node: Node in s.layer._batches.get_children(): batch_ids.append(node.get_instance_id())
	check(not s.layer.is_processing(),"no per-frame scan or text allocation callback")
	for i: int in 8:
		s.layer.set_labels_visible(false)
		check(not s.layer.visible)
		s.layer.set_labels_visible(true)
		s.layer.set_explore_active(false)
		check(not s.layer.visible)
		s.layer.set_explore_active(true)
		s.layer.refresh()
	check_eq(_signs(s.layer)[0].get_instance_id(),original,"unchanged refresh retains assembly")
	check_eq(load(TEXT).cache_size(),text_count)
	var after_mesh_ids: Array[int]=[]
	for node: MeshInstance3D in s.layer.find_children("*","MeshInstance3D",true,false): after_mesh_ids.append(node.mesh.get_instance_id())
	var after_batch_ids: Array[int]=[]
	for node: Node in s.layer._batches.get_children(): after_batch_ids.append(node.get_instance_id())
	check_eq(after_mesh_ids,mesh_ids,"stable refresh and visibility allocate no text/blank resources")
	check_eq(after_batch_ids,batch_ids,"stable refresh and visibility retain signage upload buffers")
	var replacement: City=f.city.duplicate_city()
	f.topology.rebuild(replacement)
	check(s.names.bind_city(replacement,f.topology).ok)
	s.view.city=replacement
	s.layer.bind(s.view,f.topology,s.names)
	check(s.names.assign(_keys(f.arms.north),"Fremont Street",f.topology.revision).ok)
	check_eq(sign_names_at(s.layer),["Fremont Street"])
	check_eq(f.city.street_naming.streets.values(),["Palm Avenue"])
	s.layer.clear()
	check_eq(_signs(s.layer).size(),0)
	_dispose(s)

func test_four_named_arms_complete_faces_and_no_grade_separated_junction() -> void:
	if not _available(): return
	var f:=Fixtures.junction()
	var s:=_layer(f)
	for arm: String in ["north","east","south","west"]:
		check(s.names.assign(_keys(f.arms[arm]),arm+" Road",f.topology.revision).ok)
	check_eq(sign_names_at(s.layer),["east Road","north Road","south Road","west Road"])
	check_eq(s.layer.diagnostics.size(),0)
	for assembly: Node3D in _signs(s.layer):
		var bounds: AABB=assembly.get_meta("world_bounds")
		var lettering:=0
		for node: Node in assembly.find_children("*","MeshInstance3D",true,false):
			var mesh_node:=node as MeshInstance3D
			check(bounds.grow(.000001).encloses(mesh_node.global_transform*mesh_node.mesh.get_aabb()),"every actual blade/face/post stays in safe envelope")
			if node.has_meta("complete_text"):
				lettering+=1
				# The blade casts the sign's shadow; the dense glyph meshes stay out of the shadow maps.
				check_eq(mesh_node.cast_shadow,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"lettering casts no shadow of its own")
			else: check_ne(mesh_node.cast_shadow,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"blades, posts and faces keep casting the sign's shadow")
		check_ge(lettering,8,"all four names appear on both operational faces")
		_check_on_junction_tile(assembly,Vector2i(8,8))
	_dispose(s)
	var city:=flat_city()
	Fixtures.road(city,Vector2i(8,8),Vector2i(12,8))
	city.building.put(10,8,75)
	city.building.put(10,7,73)
	city.building.put(10,9,73)
	f=Fixtures.from_city(city)
	s=_layer(f)
	check(s.names.assign(_keys(["9,8,open>10,8,open"]),"Palm Avenue",f.topology.revision).ok)
	check_eq(sign_names_at(s.layer),[],"nearby upper highway is not an ordinary-road junction")
	_dispose(s)

func test_real_view_visibility_binding_and_geometry_reuse() -> void:
	if not _available(): return
	var f:=Fixtures.junction()
	var view:=CityView3D.new()
	root.add_child(view)
	var names:=StreetNamingService.new()
	check(names.bind_city(f.city,f.topology).ok)
	view.bind_city(f.city)
	view.bind_street_names(f.topology,names)
	check(names.assign(_keys(f.arms.north),"Palm Avenue",f.topology.revision).ok)
	check(not view.street_signage.visible,"Build aerial hides physical signs")
	var camera:=Camera3D.new()
	view.world.add_child(camera)
	view.set_exploration_camera(camera)
	check(view.street_signage.visible)
	view.set_labels_visible(false)
	check(not view.street_signage.visible)
	view.set_labels_visible(true)
	var before_revision:=view._geometry_revision
	var batch_id:=view.mesh_batches.get_instance_id()
	# Establish precisely the retained-geometry branch without drawing an
	# entire empty 128x128 city; the branch's equality inputs are real City data.
	view._geometry_state=view._geometry_inputs(f.city)
	view._has_rendered=true
	var replacement: City=f.city.duplicate_city()
	f.topology.rebuild(replacement)
	check(names.bind_city(replacement,f.topology).ok)
	view.bind_city(replacement)
	view.bind_street_names(f.topology,names)
	check(names.assign(_keys(f.arms.north),"Fremont Street",f.topology.revision).ok)
	check_eq(sign_names_at(view.street_signage),["Fremont Street"])
	check_eq(view._geometry_revision,before_revision,"naming and retained rebind do not rebuild city geometry")
	check_eq(view.mesh_batches.get_instance_id(),batch_id)
	view.clear_exploration_camera()
	check(not view.street_signage.visible)
	view.bind_city(null)
	check_eq(_signs(view.street_signage).size(),0,"close city removes previous signs")
	view.free()

func test_on_tile_verge_on_wet_corners_and_graded_junction() -> void:
	if not _available(): return
	for slope: bool in [false,true]:
		var f:=Fixtures.junction()
		if slope:
			var lattice:=TerrainSurface.new(4)
			for y: int in TerrainSurface.VERTS_Y:
				for x: int in TerrainSurface.VERTS_X: lattice.set_vertex(x,y,mini(4+x,30))
			lattice.project(f.city)
			f.city.terrain_surface=lattice
		_wet_corners(f.city,Vector2i(8,8))
		f.topology.rebuild(f.city)
		var s:=_layer(f)
		var networks:=_render_support(s,f.city,Rect2i(5,5,7,7))
		var before:=var_to_bytes(SaveFormat.encode_city(f.city))
		check(s.names.assign(_keys(f.arms.north),"Palm Avenue",f.topology.revision).ok)
		check_eq(sign_names_at(s.layer),["Palm Avenue"],"water in every diagonal cell is irrelevant to an on-tile sign")
		check_eq(s.layer.diagnostics.size(),0)
		for assembly: Node3D in _signs(s.layer):
			var support: Dictionary=assembly.get_meta("support")
			_check_on_junction_tile(assembly,Vector2i(8,8))
			check_eq(support.contacts.size(),4)
			var data:=networks.physical_data()
			var lowest:=INF
			for contact: Vector3 in support.contacts:
				lowest=minf(lowest,contact.y)
				var hit:=_floor_contact(data.physical_floor_faces,contact)
				check(not hit.is_empty(),"contact belongs to emitted physical floor")
				if not hit.is_empty(): check_lt(absf(hit.height-contact.y),.0001)
				check(_rendered_mesh_contact(networks,contact,.0001),"shoe corner touches actual emitted verge mesh")
			check_lt(absf(assembly.position.y-lowest),.000001,"graded verge seats the shoe on its lowest corner, never floating")
			if not slope: _check_actual_supported_meshes(assembly)
		var without_names: City=f.city.duplicate_city()
		without_names.street_naming=preload("res://scripts/core/naming/street_naming_codec.gd").empty_metadata()
		check_eq(var_to_bytes(SaveFormat.encode_city(without_names)),before)
		_dispose(s)
		networks.free()

func test_bank_junction_on_bridge_approach_keeps_both_blades_on_tile() -> void:
	if not _available(): return
	var city: City=preload("res://tests/test_bridge_approaches.gd").bank_city(true,3,87,false)
	# Synthetic bank geometry, as in bank_city: explicit compatible road masks.
	for y: int in range(20,25): city.building.put(21,y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,15 if y==22 else 5))
	_wet_corners(city,Vector2i(21,22))
	var f:=Fixtures.from_city(city)
	var s:=_layer(f)
	var networks:=_render_support(s,city,Rect2i(18,18,12,12))
	var key: Array[String]=["21,22,open>22,22,open"]
	check(f.topology.has_link(key[0]),"real bank junction connects bridge")
	check(s.names.assign(key,"Palm Avenue",f.topology.revision).ok)
	var crossing: Array[String]=["21,21,open>21,22,open"]
	check(s.names.assign(crossing,"Fremont Street",f.topology.revision).ok)
	check_eq(sign_names_at(s.layer),["Fremont Street","Palm Avenue"],"graded approach junction keeps its sign, both blades in one verge corner")
	check_eq(s.layer.diagnostics.size(),0)
	for assembly: Node3D in _signs(s.layer):
		_check_on_junction_tile(assembly,Vector2i(21,22))
		for contact: Vector3 in assembly.get_meta("support").contacts:
			var hit:=_floor_contact(networks.physical_data().physical_floor_faces,contact)
			check(not hit.is_empty(),"shoe corner is on the emitted approach verge")
			if not hit.is_empty(): check_lt(absf(hit.height-contact.y),.0001)
	_dispose(s)
	networks.free()

func test_verge_height_follows_terrain_without_waiting_for_rendered_geometry() -> void:
	if not _available(): return
	var f:=Fixtures.junction()
	var s:=_layer(f)
	check(s.names.assign(_keys(f.arms.north),"Palm Avenue",f.topology.revision).ok)
	check_eq(_signs(s.layer).size(),1)
	var old_height: float=_signs(s.layer)[0].position.y if not _signs(s.layer).is_empty() else -INF
	var lattice:=TerrainSurface.new(6)
	lattice.project(f.city)
	f.city.terrain_surface=lattice
	var old_revision: int=s.view._geometry_revision
	check(s.names.assign(_keys(f.arms.north),"Fremont Street",f.topology.revision).ok)
	check_eq(sign_names_at(s.layer),["Fremont Street"],"the travel graph supplies the new verge at once")
	check_eq(s.view._geometry_revision,old_revision,"naming never builds network geometry")
	for assembly: Node3D in _signs(s.layer):
		check_gt(absf(assembly.position.y-old_height),.01,"replacement support has actual new floor height")
		_check_on_junction_tile(assembly,Vector2i(8,8))
	var networks:=_render_support(s,f.city,Rect2i(5,5,7,7))
	s.view.geometry_rebuilt.emit(s.view._geometry_revision)
	for assembly: Node3D in _signs(s.layer):
		for contact: Vector3 in assembly.get_meta("support").contacts:
			var hit:=_floor_contact(networks.physical_data().physical_floor_faces,contact)
			check(not hit.is_empty())
			if not hit.is_empty(): check_lt(absf(hit.height-contact.y),.0001,"graph verge matches the later rendered verge")
		_check_actual_supported_meshes(assembly)
	var ids: Array[int]=[]
	for node: Node in s.layer._batches.get_children(): ids.append(node.get_instance_id())
	for i: int in 8: s.layer.refresh();s.layer.set_labels_visible(false);s.layer.set_labels_visible(true)
	var retained: Array[int]=[]
	for node: Node in s.layer._batches.get_children(): retained.append(node.get_instance_id())
	check_eq(retained,ids,"stable support retains real batch nodes")
	_dispose(s)
	networks.free()

# Post parts wider than a blade's face plane must stay out of every blade's
# height band, and the cap must clear the top blade, for any stack height.
func test_post_cap_and_collar_clear_stacked_blades() -> void:
	if not _available(): return
	var arms: Array[String]=["north","east","south","west"]
	for count: int in [1,2,3,4]:
		var f:=Fixtures.junction()
		var s:=_layer(f)
		for i: int in count: check(s.names.assign(_keys(f.arms[arms[i]]),"Wardell Boulevard %d"%i,f.topology.revision).ok)
		var signs:=_signs(s.layer)
		check_eq(signs.size(),1)
		for assembly: Node3D in signs:
			check_eq(assembly.get_meta("display_texts").size(),count)
			var art:=assembly.get_child(0) as Node3D
			var post_root: Node3D=null
			var bands: Array[Vector2]=[]
			for root: Node in art.get_children():
				if root.find_child("IvoryCap",true,false)!=null: post_root=root;continue
				var body:=root.find_child("BrassBody",true,false) as MeshInstance3D
				var box: AABB=_to(art,body)*body.mesh.get_aabb()
				bands.append(Vector2(box.position.y,box.end.y))
			check_eq(bands.size(),count,"one blade per name")
			check(post_root!=null)
			if post_root==null: continue
			var top_blade:=-INF
			for band: Vector2 in bands: top_blade=maxf(top_blade,band.y)
			for node: Node in post_root.find_children("*","MeshInstance3D",true,false):
				var part:=node as MeshInstance3D
				var box: AABB=_to(art,part)*part.mesh.get_aabb()
				var radius:=maxf(maxf(absf(box.position.x),absf(box.end.x)),maxf(absf(box.position.z),absf(box.end.z)))
				if radius>.047:
					for band: Vector2 in bands:
						check(box.end.y<=band.x+.000001 or box.position.y>=band.y-.000001,"%s (%d blades) stays out of blade band %s"%[part.name,count,band])
				if String(part.name)=="IvoryCap": check_gt(box.position.y,top_blade,"cap sits above the top blade (%d blades)"%count)
				if String(part.name)=="Post": check_gt(box.end.y,top_blade,"post reaches above the top blade (%d blades)"%count)
			_check_actual_supported_meshes(assembly)
		_dispose(s)

func _to(ancestor: Node3D, node: Node3D) -> Transform3D:
	var t:=Transform3D.IDENTITY
	var at: Node=node
	while at!=ancestor:
		t=(at as Node3D).transform*t
		at=at.get_parent()
	return t
