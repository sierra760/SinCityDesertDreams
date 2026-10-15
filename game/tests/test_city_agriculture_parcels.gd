# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")

func test_parcels_have_a_dedicated_exact_member_presenter() -> void:
	check(ResourceLoader.exists("res://scripts/view/city_agriculture_3d.gd"),"continuous parcel presenter exists")
	var city := flat_city()
	var record := F.record(1,F.l_shape(),&"grain",&"active")
	F.zone(city,record.members)
	check_eq(city.agricultural_parcels.put(city,record),OK)
	check_eq(CityBuildings3D.collect(city).size(),0,"cell occupancy must never request ordinary whole-building GLBs")

func _view(city: City) -> CityAgriculture3D:
	var view := CityAgriculture3D.new()
	root.add_child(view)
	var catalog := CityModelCatalog.new()
	catalog.load_manifest(CityModelCatalog.ROOT+"catalog.json")
	view.bind_city(city,catalog)
	return view

func _install(city: City,members: PackedInt32Array,key: StringName = &"grain",id: int = 1) -> Dictionary:
	var record := F.record(id,members,key,&"active")
	F.zone(city,members)
	check_eq(city.agricultural_parcels.put(city,record),OK)
	return city.agricultural_parcels.record(id)

func _triangles(node: Node) -> int:
	var count := 0
	for mesh: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and mesh.visible: count += mesh.mesh.get_faces().size()/3
	for multi: MultiMeshInstance3D in node.find_children("*","MultiMeshInstance3D",true,false):
		if multi.visible: count += multi.multimesh.mesh.get_faces().size()/3*multi.multimesh.instance_count
	return count

func test_generated_l_ring_have_exact_ground_rows_queries_and_one_shed() -> void:
	for members in [F.l_shape(),F.ring()]:
		var city := flat_city()
		var record := _install(city,members)
		var view := _view(city)
		var node: Node3D = view.record_for_parcel(1).node
		check_eq(node.find_children("farm_shed","Node3D",true,false).size(),1)
		check(node.get_node_or_null("SquareTemplate") == null)
		var ground := node.get_node("Ground") as MeshInstance3D
		var top_area := 0.0
		var faces := ground.mesh.get_faces()
		for i in range(0,faces.size(),3):
			var a := faces[i];var b := faces[i+1];var c := faces[i+2]
			if absf(a.y-.14)+absf(b.y-.14)+absf(c.y-.14)>.0001: continue
			top_area += (b-a).cross(c-a).length()*.5
			for sample in [(a+b+c)/3,a*.8+b*.1+c*.1,a*.1+b*.8+c*.1]:
				var point: Vector3 = node.transform*sample
				check(members.has(floori(point.z)*128+floori(point.x)),"top triangle remains in members")
		check(is_equal_approx(top_area,members.size()*256.0),"continuous ground covers exactly the union")
		var bodies := node.find_children("Query*","StaticBody3D",true,false)
		check_eq(bodies.size(),members.size())
		for body: StaticBody3D in bodies:
			var shape := body.get_child(0) as CollisionShape3D
			var point := shape.global_position
			check(members.has(floori(point.z)*128+floori(point.x)),"actual transformed query owns a true member")
		var rows := node.get_node("CropRows") as MeshInstance3D
		var repeated := false
		for s in rows.mesh.get_surface_count():
			for uv: Vector2 in rows.mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]:
				if uv.x>2 or uv.y>2: repeated = true
		check(repeated,"UVs repeat in metre space across merged spans")
		for face: Vector3 in rows.mesh.get_faces():
			for module: Dictionary in record.modules:
				var b: Array = AgriculturalParcelGeometry._box(module,"placement_bounds").bounds
				check(not (face.x>b[0]-.19 and face.x<b[2]+.19 and face.z>b[1]-.19 and face.z<b[3]+.19),"crop geometry leaves core clearance")
		view.free()

func test_shared_fence_survives_owner_removal_and_unrelated_node_is_retained() -> void:
	var city := F.install_pair(flat_city(1000000))
	_install(city,F.square(2,Vector2i(40,40)),&"grain",3)
	var view := _view(city)
	var before := F.rendered_records(view)
	check(F.all_logical_fences_have_one_physical_owner(before.filter(func(r): return r.parcel_id < 3)))
	var unrelated: int = view.record_for_parcel(3).node.get_instance_id()
	var neighbor: int = view.record_for_parcel(2).node.get_instance_id()
	city.remove_agricultural_cells(city.agricultural_parcels.record(1).members)
	await process_frame
	var after := F.rendered_records(view)
	check_eq(after[0].parcel_id,2)
	check(after[0].fence_segments.size() >= before[1].fence_segments.size())
	check_ne(after[0].node.get_instance_id(),neighbor,"unchanged neighbor revision rebuilds ownership")
	check_eq(view.record_for_parcel(3).node.get_instance_id(),unrelated,"unrelated node identity retained")
	check(F.all_logical_fences_have_one_physical_owner(after.filter(func(r): return r.parcel_id == 2)))
	view.free()

func test_member_base_ignores_hole_and_fixed_origin_survives_cuts() -> void:
	var city := flat_city()
	var record := _install(city,F.ring())
	var expected := CityAgriculture3D.parcel_transform(city,record)
	city.set_heights(21,21,28,0)
	# A raised nonmember is irrelevant unless its visible corner actually changes
	# the member surface. Imported flat-cell altitude does not share its corners.
	var actual := CityAgriculture3D.parcel_transform(city,record)
	var maximum := -INF
	for i: int in record.members:
		for corner: Vector3 in CityGeometry3D.visible_cell_corners(city,AgriculturalParcels.tile(i)): maximum = maxf(maximum,corner.y)
	check_eq(actual.origin.y,maximum)
	check_eq(actual.origin.x,expected.origin.x)
	check_eq(actual.basis.get_scale(),Vector3.ONE/16)
	var view := _view(city)
	city.remove_agricultural_cells(PackedInt32Array([record.members[0]]))
	await process_frame
	var next := city.agricultural_parcels.record(1)
	check_eq(next.origin_index,record.origin_index)
	check_eq(view.record_for_parcel(1).transform.origin.x,actual.origin.x)
	view.free()

func test_square_reuses_original_then_partial_cut_replaces_template() -> void:
	var city := flat_city()
	var record := F.record(1,F.square(2),&"grain",&"active")
	record.mode = &"square";record.legacy_code = AgricultureParams.building_id(&"grain");record.modules = []
	F.zone(city,record.members)
	check_eq(city.agricultural_parcels.put(city,record),OK)
	var view := _view(city)
	var old := view.record_for_parcel(1)
	check(old.node.get_node_or_null("SquareTemplate") != null)
	check_eq(old.transform.origin.x,21.0)
	city.remove_agricultural_cells(PackedInt32Array([21*128+21]))
	await process_frame
	var next := view.record_for_parcel(1)
	check(next.node.get_node_or_null("SquareTemplate") == null)
	check(next.node.get_node_or_null("Ground") != null)
	check_eq(next.transform.origin.x,20.0)
	view.free()

func test_maximum_and_concave_static_triangle_budget_counts_all_instances() -> void:
	for key: StringName in [&"grain",&"alfalfa",&"vegetables",&"cattle_range",&"sheep_pasture"]:
		for members in [F.square(8),F.dumbbell()]:
			var city := flat_city()
			_install(city,members,key)
			var view := _view(city)
			var count := _triangles(view)
			print("STATIC_TRIANGLES ",key," members=",members.size()," triangles=",count)
			check(count>0 and count<=20000,"actual visible mesh copies remain <=20000")
			view.free()

func test_far_boundary_change_reports_full_bounds_and_revision_reuses_geometry() -> void:
	var city := flat_city()
	var members := PackedInt32Array()
	for x in range(20,32): members.append(20*128+x)
	_install(city,members)
	var view := _view(city)
	var old := view.record_for_parcel(1)
	var emitted: Array = []
	view.changed_regions.connect(func(regions): emitted.append_array(regions))
	var node_id: int = old.node.get_instance_id()
	view.update_regions([Rect2i(30,20,1,1)])
	check_eq(view.record_for_parcel(1).node.get_instance_id(),node_id,"unchanged geometry keeps memory mesh")
	city.remove_agricultural_cells(PackedInt32Array([20*128+31]))
	await process_frame
	check(Rect2i(20,20,12,1) in emitted,"old bounds cover the remote edge")
	check(Rect2i(20,20,11,1) in emitted,"new bounds cover retained cells")
	view.free()

func test_ground_keeps_original_soil_and_ring_physics_excludes_hole_in_four_rotations() -> void:
	var city := flat_city()
	_install(city,F.ring())
	var view := _view(city)
	var node: Node3D = view.record_for_parcel(1).node
	var ground := node.get_node("Ground") as MeshInstance3D
	check_eq(ground.get_active_material(0).resource_name,"farm_soil","continuous ground uses original soil")
	for turn in 4:
		view.rotation.y = turn*PI*.5
		await physics_frame
		await physics_frame
		for cell in [Vector2i(20,20),Vector2i(21,21),Vector2i(22,22)]:
			var point := view.global_transform*Vector3(cell.x+.5,node.position.y,cell.y+.5)
			for layer in [CityBuildings3D.QUERY_LAYER,CityModelCatalog.SHELL_LAYER]:
				var hit := view.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*8,point-Vector3.UP,layer))
				check_eq(hit.is_empty(),cell==Vector2i(21,21),"actual rotated ground/query leaves hole empty")
	view.free()

func test_view_batches_retains_and_hides_parcels_without_covering_hole_pump() -> void:
	var city := flat_city()
	_install(city,F.ring())
	city.building.put(21,21,Buildings.WATER_PUMP)
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.set_active(true)
	await process_frame
	var record := view.agriculture.record_for_parcel(1)
	var id: int = record.node.get_instance_id()
	check_eq(CityBuildings3D.collect(city).size(),1,"hole pump remains in ordinary collector")
	check(view.mesh_batches._roots.has(view.agriculture),"static presenter belongs to existing batch domain")
	view.refresh()
	check_eq(view.agriculture.record_for_parcel(1).node.get_instance_id(),id)
	view.set_underground(true)
	check(not view.agriculture.visible,"underground hides static farms")
	view.set_underground(false)
	check(view.agriculture.visible)
	var surfaces := CityUnderground3D.new()
	view.world.add_child(surfaces)
	surfaces.bind_city(city)
	check(surfaces.mesh_instance.mesh != null,"member conduits and hole pump remain visible underground")
	for turn in 4:
		view.set_camera_state(Vector3(21.5,record.transform.origin.y,21.5),turn,4)
		await physics_frame
		await physics_frame
		check_eq(view.pick_cell(view.project_cell(Vector2i(21,21)),1),Vector2i(21,21),"hole pump selectable at each quarter turn")
	view.free()

func test_shared_fences_on_distinct_support_planes_keep_both_owners() -> void:
	var city := F.install_pair(flat_city())
	for y in range(20,22):
		for x in range(22,24): city.set_heights(x,y,6,0)
	var view := _view(city)
	var records := F.rendered_records(view)
	check_ne(records[0].transform.origin.y,records[1].transform.origin.y)
	check(F.all_logical_fences_have_one_physical_owner(records),"each different-height domain remains enclosed on its own grade")
	view.free()

func test_high_perimeter_64_member_comb_counts_every_crop_and_fence_instance() -> void:
	var members := PackedInt32Array()
	for y in range(20,29):
		for x in range(20,32):
			if (y-20)%2 == 0 or x == 20: members.append(y*128+x)
	check_eq(members.size(),64)
	for key: StringName in [&"vegetables",&"cattle_range",&"sheep_pasture"]:
		var city := flat_city()
		var record := F.record(1,members,key,&"active")
		check(AgriculturalParcelGeometry.plan(record).ok,"high-perimeter comb remains a valid domain")
		F.zone(city,members)
		check_eq(city.agricultural_parcels.put(city,record),OK)
		var view := _view(city)
		var count := _triangles(view)
		print("COMB_STATIC_TRIANGLES ",key," members=64 triangles=",count)
		check(count>0 and count<=20000,"all actual copies satisfy the high-perimeter parcel cap")
		view.free()

func test_generated_pasture_retains_original_dry_ground_material() -> void:
	var view := _view(F.install_pair(flat_city()))
	var ground := view.record_for_parcel(1).node.get_node("Ground") as MeshInstance3D
	check_eq(ground.get_active_material(0).resource_name,"farm_dry","inland pasture keeps original dry ground character")
	view.free()

func test_actual_explore_consumer_support_clearance_and_shared_owner_removal() -> void:
	var city := F.install_pair(flat_city())
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city);view.set_active(true)
	var traversal := CityTraversalWorld3D.new()
	view.world.add_child(traversal)
	var snapshot := view.traversal_snapshot()
	traversal.rebuild(city,snapshot.chunks,snapshot.networks,snapshot.revision)
	var no_exclusions: Array[RID] = []
	var base: float = view.agriculture.record_for_parcel(1).transform.origin.y
	var ground := base+.14/16
	var capsule := ExploreActorProfile.shape(ExploreActorProfile.Mode.WALK)
	for turn in 4:
		view.set_camera_state(Vector3(22,base,21),turn,4)
		await physics_frame
		await physics_frame
		var support := traversal.support_near(Vector3(23,ground+.01,21.2),.01,.03,no_exclusions)
		check(not support.is_empty(),"real Explore consumer finds member floor")
		if not support.is_empty(): check(absf(support.position.y-ground)<.00001)
		check(traversal.has_clearance(Transform3D(Basis.IDENTITY,Vector3(23,ground+.06,21.2)),capsule,no_exclusions),"actual walking capsule clears pasture interior")
		check(not traversal.has_clearance(Transform3D(Basis.IDENTITY,Vector3(22,ground+.06,21.2)),capsule,no_exclusions),"actual walking capsule blocked by shared fence")
		var r := view.agriculture.record_for_parcel(2)
		var obstacle: Dictionary = r.layout.obstacles[0]
		var point: Vector3 = r.transform*Vector3(obstacle.center[0]-obstacle.size[0]*.5,obstacle.center[1],obstacle.center[2])
		check(not traversal.has_clearance(Transform3D(Basis.IDENTITY,point),capsule,no_exclusions),"actual walking capsule intersects the imported module envelope wall")
		point = r.transform*Vector3(obstacle.center[0],obstacle.center[1],obstacle.center[2])
		check(not traversal.has_clearance(Transform3D(Basis.IDENTITY,point),capsule,no_exclusions),"module envelope centre is occupied for actual Explore placement")
	city.remove_agricultural_cells(city.agricultural_parcels.record(1).members)
	await process_frame
	view.refresh()
	snapshot=view.traversal_snapshot()
	traversal.rebuild(city,snapshot.chunks,snapshot.networks,snapshot.revision)
	await physics_frame
	await physics_frame
	check(not traversal.has_clearance(Transform3D(Basis.IDENTITY,Vector3(22,ground+.06,21.2)),capsule,no_exclusions),"surviving owner closes the same fence for the real consumer")
	check(traversal.has_clearance(Transform3D(Basis.IDENTITY,Vector3(20,ground+.06,21.2)),capsule,no_exclusions),"removed owner's outer fence is gone")
	var ring := flat_city()
	_install(ring,F.ring())
	view.bind_city(ring)
	snapshot=view.traversal_snapshot()
	traversal.rebuild(ring,snapshot.chunks,snapshot.networks,snapshot.revision)
	await physics_frame
	await physics_frame
	var hole := traversal.support_near(Vector3(21.5,ground+.01,21.5),.01,.04,no_exclusions)
	check(not hole.is_empty(),"hole retains original city ground")
	if not hole.is_empty(): check(absf(hole.position.y-base)<.00001,"hole never receives parcel slab")
	check(traversal.has_clearance(Transform3D(Basis.IDENTITY,Vector3(21.5,base+.06,21.5)),capsule,no_exclusions),"hole is empty to actual walking capsule")
	view.free()

func test_generated_ring_pasture_closes_inner_and_outer_physical_loops() -> void:
	var city := flat_city()
	_install(city,F.ring(),&"cattle_range")
	var view := _view(city)
	var records := F.rendered_records(view)
	check(F.all_logical_fences_have_one_physical_owner(records),"every inner and outer logical edge has one actual physical fence")
	var boundaries := AgriculturalParcelGeometry.boundary(F.ring())
	check_eq(boundaries.size(),16,"ring has twelve outer and four inner unit edges")
	var inner := 0
	for physical: Dictionary in records[0].physical_fences:
		var center: Vector2 = (physical.a+physical.b)*.5
		if center.x>=21 and center.x<=22 and center.y>=21 and center.y<=22: inner += 1
	check_eq(inner,4,"emitted physical shapes close all four hole sides")
	view.free()

func _physical_fence_count(records: Array[Dictionary], point: Vector2, base: float) -> int:
	var count := 0
	for item: Dictionary in records:
		for fence: Dictionary in item.physical_fences:
			if absf(fence.height-(base+.965/16)) < .0001 and point.distance_to(Geometry2D.get_closest_point_to_segment(point,fence.a,fence.b)) < .0001: count += 1
	return count

func _traversal(city: City) -> CityTraversalWorld3D:
	var traversal := CityTraversalWorld3D.new()
	root.add_child(traversal)
	# The actual consumer includes sibling mask-4 parcel shells, as in CityView.
	traversal.rebuild(city,[],{},1)
	return traversal

func test_small_lower_id_remnants_cannot_take_survivors_physical_fence() -> void:
	for size in [1,2,3]:
		var city := F.install_pair(flat_city())
		var view := _view(city)
		var traversal := _traversal(city)
		var keep := F.mask([[21,20]] if size == 1 else ([[20,20],[21,20]] if size == 2 else [[20,20],[21,20],[21,21]]))
		var removed := PackedInt32Array()
		for index: int in city.agricultural_parcels.record(1).members:
			if not keep.has(index): removed.append(index)
		city.remove_agricultural_cells(removed)
		await process_frame
		await physics_frame
		await physics_frame
		var remnant := city.agricultural_parcels.record(1)
		check_eq(remnant.members.size(),size)
		check_eq(remnant.state,&"prepared")
		check(AgriculturalParcelGeometry.plan(remnant).profile.is_empty())
		var base: float = view.record_for_parcel(2).transform.origin.y
		check_eq(_physical_fence_count(F.rendered_records(view),Vector2(22,20.5),base),1,"surviving active pasture owns actual edge beside %d-cell remnant"%size)
		var no_exclusions: Array[RID] = []
		check(not traversal.has_clearance(Transform3D(Basis.IDENTITY,Vector3(22,base+.14/16+.06,20.5)),ExploreActorProfile.shape(ExploreActorProfile.Mode.WALK),no_exclusions),"real Explore capsule blocked beside prepared remnant")
		view.free();traversal.free()

func test_far_corner_terrain_rechecks_remote_shared_physical_owner_both_directions() -> void:
	var city := flat_city()
	city.terrain_surface = TerrainSurface.new(4)
	var members := PackedInt32Array()
	for y in range(20,22):
		for x in range(20,32): members.append(y*128+x)
	_install(city,members,&"cattle_range",1)
	_install(city,F.square(2,Vector2i(32,20)),&"cattle_range",2)
	_install(city,F.square(2,Vector2i(50,50)),&"grain",3)
	var view := _view(city)
	var traversal := _traversal(city)
	var unrelated: int = view.record_for_parcel(3).node.get_instance_id()
	var region := Rect2i(20,20,1,1)
	check(not view.record_for_parcel(2).bounds.grow(1).intersects(region),"edit lies beyond neighbor regional reach")
	var emitted: Array = []
	view.changed_regions.connect(func(regions): emitted.append_array(regions))
	for height in [6,4]:
		var old_neighbor: int = view.record_for_parcel(2).node.get_instance_id()
		city.terrain_surface.set_vertex(20,20,height)
		emitted.clear()
		view.update_regions([region])
		await physics_frame
		await physics_frame
		var a := view.record_for_parcel(1);var b := view.record_for_parcel(2)
		check_eq(a.transform.origin.y == b.transform.origin.y,height == 4)
		check_ne(b.node.get_instance_id(),old_neighbor,"remote neighbor ownership changes on plane transition")
		check(Rect2i(32,20,2,2) in emitted,"remote neighbor bounds published for batching")
		check_eq(view.record_for_parcel(3).node.get_instance_id(),unrelated)
		var records := F.rendered_records(view)
		check(F.all_logical_fences_have_one_physical_owner(records.filter(func(r): return r.parcel_id < 3)),"same and distinct grades each have exactly one physical owner per edge/height")
		check_eq(_physical_fence_count(records,Vector2(32,21.2),b.transform.origin.y),1)
		# Ignore the raised owner floor: its deep support slab must not mask a missing fence.
		var floor_exclusion: Array[RID] = [a.node.get_node("MemberFloors").get_rid()]
		check(not traversal.has_clearance(Transform3D(Basis.IDENTITY,Vector3(32,b.transform.origin.y+.14/16+.06,21.2)),ExploreActorProfile.shape(ExploreActorProfile.Mode.WALK),floor_exclusion),"actual lower neighbor remains enclosed after remote terrain change")
	view.free();traversal.free()

func test_fixed_maximum_lower_corner_updates_actual_skirt_and_floor_bottom() -> void:
	var city := flat_city()
	city.terrain_surface = TerrainSurface.new(4)
	city.terrain_surface.set_vertex(22,22,5)
	_install(city,F.square(2))
	_install(city,F.square(2,Vector2i(50,50)),&"grain",2)
	var view := _view(city)
	var old := view.record_for_parcel(1)
	var old_id: int = old.node.get_instance_id()
	var unrelated: int = view.record_for_parcel(2).node.get_instance_id()
	city.terrain_surface.set_vertex(20,20,3)
	view.update_regions([Rect2i(20,20,1,1)])
	var next := view.record_for_parcel(1)
	check_eq(next.transform,old.transform,"maximum and origin are fixed")
	check_eq(next.revision,old.revision,"terrain edit does not revise canonical parcel")
	check_ne(next.node.get_instance_id(),old_id,"lower support input replaces geometry")
	check_eq(view.record_for_parcel(2).node.get_instance_id(),unrelated)
	var corner: Vector3 = CityGeometry3D.visible_cell_corners(city,Vector2i(20,20))[0]
	var expected := corner.y-.02/16
	var bottom := INF
	for shape: CollisionShape3D in next.node.get_node("MemberFloors").get_children():
		var box := shape.shape as BoxShape3D
		var point := shape.global_transform*Vector3(0,-box.size.y*.5,0)
		if absf(point.x-20.5)+absf(point.z-20.5)<.0001: bottom = point.y
	check(absf(bottom-expected)<.00001,"actual floor box reaches updated lower member corner")
	var skirt := INF
	for vertex: Vector3 in next.node.get_node("Ground").mesh.get_faces():
		var point: Vector3 = next.transform*vertex
		if absf(point.x-20)+absf(point.z-20)<.0001: skirt = minf(skirt,point.y)
	check(absf(skirt-expected)<.00001,"actual skirt endpoint reaches updated lower corner")
	var stable: int = next.node.get_instance_id()
	view.update_regions([Rect2i(20,20,1,1)])
	check_eq(view.record_for_parcel(1).node.get_instance_id(),stable,"identical complete support inputs retain meshes")
	view.free()

func test_ordinary_farm_full_regional_and_retained_handoff_have_legacy_source_keys() -> void:
	var city := flat_city()
	var code := AgricultureParams.building_id(&"grain")
	for cell in [Vector2i(20,20),Vector2i(30,30)]:
		city.stamp_building(cell.x,cell.y,code,Zones.AGR_HIGH)
	var records := CityBuildings3D.collect(city)
	check_eq(records.size(),2)
	var regions: Array[Rect2i] = [Rect2i(20,20,1,1),Rect2i(30,30,1,1)]
	check_eq(CityBuildings3D.collect_regions(city,regions),records,"regional producer has exact full-scan records and keys")
	for record: Dictionary in records:
		check_eq(record.get("source_key",""),"legacy:%d:%d"%[record.anchor.x,record.anchor.y])
	var projection := CityBuildings3D.new()
	root.add_child(projection)
	projection.rebuild(city)
	var input_reader := CityView3D.new()
	var inputs: Array = input_reader._geometry_inputs(city)
	input_reader.free()
	var ids := {}
	for node in projection.get_children():
		var cell: Vector2i = node.get_meta("cell")
		ids[cell] = node.get_instance_id()
		check_eq(node.get_meta("source_key",""),"legacy:%d:%d"%[cell.x,cell.y],"actual ordinary retained node carries producer key")
	projection.update_regions(city,null,regions,inputs,inputs)
	check_eq(projection.last_retained_lots,2)
	for node in projection.get_children():
		var cell: Vector2i = node.get_meta("cell")
		check_eq(node.get_instance_id(),ids[cell])
		check_eq(node.get_meta("source_key",""),"legacy:%d:%d"%[cell.x,cell.y],"retained handoff preserves key")
	projection.free()


func test_crop_canopies_are_finite_original_triangles_with_air_gaps() -> void:
	for key: StringName in [&"grain",&"alfalfa",&"vegetables"]:
		var city := flat_city()
		var record := _install(city,F.ring(),key)
		var view := _view(city)
		var rows: MeshInstance3D = view.record_for_parcel(1).node.get_node("CropRows")
		var plant_triangles := 0
		for surface in rows.mesh.get_surface_count():
			var material := rows.mesh.surface_get_material(surface)
			if material.resource_name in ["farm_soil","farm_dark"]: continue
			var points: PackedVector3Array = rows.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for i in range(0,points.size(),3):
				var a := points[i];var b := points[i+1];var c := points[i+2]
				check(maxf(a.z,maxf(b.z,c.z))-minf(a.z,minf(b.z,c.z)) < .7,"finite crop triangles retain seedling depth")
				for point in [a,b,c]:
					var global: Vector3 = view.record_for_parcel(1).transform*point
					check(record.members.has(floori(global.z)*128+floori(global.x)),"finite plant never bridges hole")
				plant_triangles += 1
		check(plant_triangles>0,"actual seedling silhouettes remain visible")
		check(rows.has_meta("plant_spacing") and rows.get_meta("plant_spacing")>=1.0,"bounded deterministic plant spacing")
		view.free()

func test_sheep_woven_style_survives_shared_ownership_both_orders_and_removal() -> void:
	for sheep_id in [1,2]:
		var city := flat_city()
		for id in [1,2]: _install(city,F.square(2,Vector2i(20+(id-1)*2,20)),&"sheep_pasture" if id==sheep_id else &"cattle_range",id)
		var view := _view(city)
		var owner := view.record_for_parcel(1)
		var shared := 0
		for segment: Dictionary in owner.fence_segments:
			if is_equal_approx(segment.a[0]+20*16,22*16) and is_equal_approx(segment.b[0]+20*16,22*16):
				check_eq(segment.style,"woven_wire","sheep selects infill regardless of physical owner")
				shared += 1
		check(shared>0)
		for id in [1,2]:
			var record := view.record_for_parcel(id)
			for shape: CollisionShape3D in record.node.get_node("OwnedFences").get_children():
				check(shape.get_meta("fence_segment").has("style"),"merge retains style metadata")
		city.remove_agricultural_cells(city.agricultural_parcels.record(1).members)
		await process_frame
		for segment: Dictionary in view.record_for_parcel(2).fence_segments:
			check_eq(segment.style,"woven_wire" if sheep_id==2 else "pipe_rail","survivor recomputes its own identity")
		view.free()


func test_sparse_dry_pasture_cover_is_render_only_and_respects_core() -> void:
	var city := flat_city()
	var record := _install(city,F.ring(),&"sheep_pasture")
	var view := _view(city)
	var node: Node3D = view.record_for_parcel(1).node
	var cover := node.get_node("DryPastureTufts") as MeshInstance3D
	check(cover!=null,"sparse original dry cover visible")
	check_eq(cover.get_child_count(),0,"tufts add no collision or navigation changes")
	for point: Vector3 in cover.mesh.get_faces():
		var world: Vector3 = node.transform*point
		check(record.members.has(floori(world.z)*128+floori(world.x)),"tufts never fill a hole")
		for pose: Dictionary in record.modules:
			var bounds: Array = AgriculturalParcelGeometry._box(pose,"placement_bounds").bounds
			check(not (point.x>bounds[0]-.2 and point.x<bounds[2]+.2 and point.z>bounds[1]-.2 and point.z<bounds[3]+.2),"tuft leaves physical core clear")
	for surface in cover.mesh.get_surface_count(): check(cover.mesh.surface_get_material(surface).resource_name in ["farm_sage","farm_grain"],"original dry swatches")
	check(_triangles(node)<=20000)
	view.free()
