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
	# Box in every corner with developed lots; never generate floating fallback.
	for cell: Vector2i in [Vector2i(7,7),Vector2i(9,7),Vector2i(7,9),Vector2i(9,9)]:
		f.city.building.putv(cell,Buildings.SUBWAY_STATION)
	s.layer.refresh()
	check_eq(_signs(s.layer).size(),0)
	check_eq(s.layer.diagnostics.size(),1)
	_dispose(s)

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
			if node.has_meta("complete_text"): lettering+=1
		check_ge(lettering,8,"all four names appear on both operational faces")
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

func test_rendered_verge_fallback_and_unsafe_sloping_support_rejection() -> void:
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
		if slope:
			check_eq(_signs(s.layer).size(),0,"steep actual verge cannot support four rigid shoe corners")
			check_eq(s.layer.diagnostics.size(),1)
		else:
			check_eq(sign_names_at(s.layer),["Palm Avenue"],"rendered verge succeeds after all ground corners are water")
			check_eq(s.layer.diagnostics.size(),0)
			for assembly: Node3D in _signs(s.layer):
				var support: Dictionary=assembly.get_meta("support")
				check_eq(support.kind,"rendered_verge")
				check_eq(support.contacts.size(),4)
				check_eq(support.geometry_revision,s.view._geometry_revision)
				var data:=networks.physical_data()
				for contact: Vector3 in support.contacts:
					var hit:=_floor_contact(data.physical_floor_faces,contact)
					check(not hit.is_empty(),"contact belongs to emitted physical floor")
					if not hit.is_empty(): check_lt(absf(hit.height-contact.y),.00001)
					check(_rendered_mesh_contact(networks,contact),"shoe touches actual emitted verge mesh")
				check(not data.physical_floor_faces.is_empty())
				_check_actual_supported_meshes(assembly)
		# Name assignment alone owns metadata; placement must preserve every
		# other encoded city field, including money and structural layers.
		var without_names: City=f.city.duplicate_city()
		without_names.street_naming=preload("res://scripts/core/naming/street_naming_codec.gd").empty_metadata()
		check_eq(var_to_bytes(SaveFormat.encode_city(without_names)),before)
		_dispose(s)
		networks.free()

func test_real_bridge_side_support_after_ground_and_verge_rejection() -> void:
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
	check_eq(sign_names_at(s.layer),["Palm Avenue"])
	check_eq(s.layer.diagnostics.size(),0)
	for assembly: Node3D in _signs(s.layer):
		var support: Dictionary=assembly.get_meta("support")
		check_eq(support.kind,"rendered_bridge_side")
		check(support.has("source_box"),"support is a real canonical collision box")
		if support.has("source_box"):
			check(networks.physical_data().physical_boxes.has(support.source_box))
			var b: Dictionary=support.source_box
			var box: AABB=b.transform*AABB(-Vector3(b.size)*.5,b.size)
			var rendered:=false
			for node: MeshInstance3D in networks.find_children("*","MeshInstance3D",true,false):
				if node.mesh is BoxMesh and node.mesh.size==b.size and node.global_transform.is_equal_approx(b.transform): rendered=true
			check(rendered,"canonical support box is an actual emitted structural mesh")
			for contact: Vector3 in support.contacts:
				check_lt(absf(contact.y-box.end.y),.00001)
				check(Rect2(Vector2(box.position.x,box.position.z),Vector2(box.size.x,box.size.z)).has_point(Vector2(contact.x,contact.z)))
		_check_actual_supported_meshes(assembly)
	var crossing: Array[String]=["21,21,open>21,22,open"]
	check(s.names.assign(crossing,"Fremont Street",f.topology.revision).ok)
	check_eq(_signs(s.layer).size(),0,"perpendicular maximum-width blade must not project into the bridge driving corridor")
	check_eq(s.layer.diagnostics.size(),1,"supported feet alone do not make the full assembly safe")
	if not s.layer.diagnostics.is_empty(): check("lane/shoulder" in s.layer.diagnostics[0].reason,"actual corridor causes unsafe full-blade rejection")
	_dispose(s)
	networks.free()

func test_rendered_support_refresh_after_early_names_and_removed_geometry() -> void:
	if not _available(): return
	var f:=Fixtures.junction()
	_wet_corners(f.city,Vector2i(8,8))
	var s:=_layer(f)
	var networks:=_render_support(s,f.city,Rect2i(5,5,7,7))
	check(s.names.assign(_keys(f.arms.north),"Palm Avenue",f.topology.revision).ok)
	check_eq(_signs(s.layer).size(),1)
	var old_height: float=_signs(s.layer)[0].position.y if not _signs(s.layer).is_empty() else -INF
	var lattice:=TerrainSurface.new(6)
	lattice.project(f.city)
	f.city.terrain_surface=lattice
	_wet_corners(f.city,Vector2i(8,8))
	var old_revision: int=s.view._geometry_revision
	# Main reconciles names before deferred CityView geometry has caught up.
	check(s.names.assign(_keys(f.arms.north),"Fremont Street",f.topology.revision).ok)
	check_eq(_signs(s.layer).size(),0,"stale rendered support is never reused")
	check_eq(s.view._geometry_revision,old_revision,"naming never builds network geometry")
	networks.free()
	networks=_render_support(s,f.city,Rect2i(5,5,7,7))
	s.view.geometry_rebuilt.emit(s.view._geometry_revision)
	check_eq(sign_names_at(s.layer),["Fremont Street"],"later current geometry refresh survives matching City/name snapshots")
	for assembly: Node3D in _signs(s.layer):
		check_gt(absf(assembly.position.y-old_height),.01,"replacement support has actual new floor height")
		var support: Dictionary=assembly.get_meta("support")
		check_eq(support.geometry_revision,s.view._geometry_revision)
		for contact: Vector3 in support.contacts:
			var hit:=_floor_contact(networks.physical_data().physical_floor_faces,contact)
			check(not hit.is_empty())
			if not hit.is_empty(): check_lt(absf(hit.height-contact.y),.00001)
		_check_actual_supported_meshes(assembly)
	var ids: Array[int]=[]
	for node: Node in s.layer._batches.get_children(): ids.append(node.get_instance_id())
	for i: int in 8: s.layer.refresh();s.layer.set_labels_visible(false);s.layer.set_labels_visible(true)
	var retained: Array[int]=[]
	for node: Node in s.layer._batches.get_children(): retained.append(node.get_instance_id())
	check_eq(retained,ids,"stable rendered support retains real batch nodes")
	# Removed emitted support must be re-read despite identical City/name data.
	networks.clear()
	s.view._geometry_revision+=1
	s.view.geometry_rebuilt.emit(s.view._geometry_revision)
	check_eq(_signs(s.layer).size(),0)
	check_eq(s.layer.diagnostics.size(),1)
	_dispose(s)
	networks.free()

