# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

class SnapshotView extends CityView3D:
	var snapshot_chunks: Array[Dictionary] = []
	var snapshot_networks: Dictionary = {}
	func traversal_snapshot() -> Dictionary:
		return {"chunks":snapshot_chunks,"networks":snapshot_networks,"revision":_geometry_revision,"city":city}

class SupportOwner extends Node3D:
	var train: ExploreTransitTrain
	var world: ExploreTransitWorld3D
	func support_for(feet: Vector3) -> Dictionary:
		var cabin := train.support_for(feet) if is_instance_valid(train) else {}
		return cabin if not cabin.is_empty() else world.support_for(feet)
	func contains(feet: Vector3) -> bool:
		return not support_for(feet).is_empty()

var view: SnapshotView
var traversal: CityTraversalWorld3D
var world: ExploreTransitWorld3D
var walker: ExplorePedestrian
var support: SupportOwner
var path: Dictionary
var recoveries := 0

func after_each() -> void:
	if is_instance_valid(world): world.clear()
	if is_instance_valid(view): view.free()
	await physics_frame

func test_north_mouth_turns_east_without_ramp_in_cabin() -> void:
	var city := flat_city(20000,5)
	for y: int in range(16,20): city.building.put(23,y,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,5))
	city.stamp_building(24,17,Buildings.RAIL_STATION)
	city.building.put(23,20,Buildings.SUBWAY_PORTAL_FIRST+3)
	city.underground.put(23,20,Underground.STATION_LINK)
	for x: int in range(24,30): city.underground.put(x,20,Underground.subway_code(10))
	city.building.put(29,20,Buildings.SUBWAY_STATION)
	city.underground.put(29,20,Underground.STATION_LINK)
	var city_before := SaveFormat.encode_city(city)
	view = SnapshotView.new()
	root.add_child(view)
	view.bind_city(city)
	view._geometry_revision = 1
	view.networks.rebuild(city)
	view.snapshot_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,24,12))]
	view.snapshot_networks = view.networks.physical_data()
	var original_obstacles: PackedVector3Array = view.snapshot_networks.physical_obstacle_faces.duplicate()
	var original_floors: PackedVector3Array = view.snapshot_networks.physical_floor_faces.duplicate()
	traversal = CityTraversalWorld3D.new()
	view.world.add_child(traversal)
	traversal.rebuild(city,view.snapshot_chunks,view.snapshot_networks,1)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var network := ExploreTransitNetwork.new()
	network.rebuild(city,graph,1)
	# Declared converter fixture: same lowered local tunnel envelope as Isla's
	# north-facing portal at23,20; leave source grids and ramp profile unchanged.
	for key: Vector3i in network.nodes:
		if key.y==1: network.nodes[key].point.y-=.3123724
	for options: Array in network._station_options.values():
		for option: Dictionary in options:
			if option.subway:
				option.position.y-=.3123724
				option.platform.y-=.3123724
				option.access_position.y-=.3123724
	path = network.route(0,1)
	check(not path.is_empty(),"mixed station route exists")
	if path.is_empty(): return
	world = ExploreTransitWorld3D.new()
	view.world.add_child(world)
	world.bind(view,traversal,network)
	world.build(path)
	check(world._filter_portal_faces(original_obstacles)!=original_obstacles,"opens converter recess and real side passage")
	var saved_meshes: Array[Dictionary] = world._terrain.duplicate()
	var removed_visual_vertices := 0
	for record: Dictionary in saved_meshes:
		var node: Variant = record.node.get_ref()
		if is_instance_valid(node): removed_visual_vertices += record.mesh.get_faces().size()-node.mesh.get_faces().size()
	check(not world._portal_passages.is_empty(),"side opening has matching visible projection")
	var visual_changed := false
	for record: Dictionary in saved_meshes:
		var mesh_node: Variant = record.node.get_ref()
		if is_instance_valid(mesh_node) and mesh_node.mesh.get_faces()!=record.mesh.get_faces(): visual_changed=true
	check(visual_changed,"actual portal visual triangles are clipped")
	check(world.apply_physical_projection(view.traversal_snapshot()).networks.physical_floor_faces!=original_floors,"actual ramp collision receives the same side opening")
	walker = ExplorePedestrian.new()
	view.world.add_child(walker)
	walker.bind(traversal)
	recoveries = 0
	walker.recovery_requested.connect(func(reason):
		recoveries += 1
		if recoveries<=2: print("PORTAL_RECOVERY ",reason," walker ",walker.global_position," train ",support.train.global_transform," local ",support.train.global_transform.affine_inverse()*walker.global_position," support ",support.train.support_for(walker.global_position)," grounded ",walker._grounded," velocity ",walker.velocity))
	support = SupportOwner.new()
	view.world.add_child(support)
	support.world = world
	walker.transit_support = support
	support.train = ExploreTransitTrain.new()
	view.world.add_child(support.train)
	support.train.global_transform = ExploreTransitNetwork.sample(path,.1)
	walker.global_position = support.train.global_transform*Vector3(0,.027,0)
	await physics_frame
	for i in 20:
		walker.step(ExploreInputFrame.idle(),0,1.0/60.0)
		await physics_frame
	var before := support.train.global_transform.affine_inverse()*walker.global_position
	var frames := ceili(float(path.length)*100)
	var worst_drift := 0.0
	var printed := false
	for i in frames:
		support.train.global_transform = ExploreTransitNetwork.sample(path,.1+float(i+1)*(float(path.length)-.2)/frames)
		walker.step(ExploreInputFrame.idle(),0,1.0/60.0)
		await physics_frame
		var local := support.train.global_transform.affine_inverse()*walker.global_position
		worst_drift = maxf(worst_drift,Vector2(local.x-before.x,local.z-before.z).length())
		if not printed and worst_drift>.03:
			printed = true
			print("PORTAL_DRIFT frame ",i," distance ",.1+float(i+1)*(float(path.length)-.2)/frames," local ",local," before ",before," velocity ",walker.velocity," collisions ",walker.get_slide_collision_count())
			for c in walker.get_slide_collision_count(): print("COLLISION ",walker.get_slide_collision(c).get_position()," normal ",walker.get_slide_collision(c).get_normal()," collider ",walker.get_slide_collision(c).get_collider()," path ",walker.get_slide_collision(c).get_collider().get_path()," floorRID ",support.train._body.get_rid())
	check_eq(recoveries,0,"portal journey has no unsupported/collision recovery")
	check(support.train.contains(walker.global_position),"rider reaches subway in cabin")
	check_lt(worst_drift,.015,"pitched portal carriage retains rider through transition")

	world.clear()
	await physics_frame
	check_eq(view.snapshot_networks.physical_obstacle_faces,original_obstacles,"canonical physical snapshot unchanged")
	check_eq(view.snapshot_networks.physical_floor_faces,original_floors,"canonical ramp floors unchanged")
	for record: Dictionary in saved_meshes:
		var node: Variant = record.node.get_ref()
		if is_instance_valid(node): check(node.mesh==record.mesh,"original portal mesh restored by identity")
	var profile := CityPortal3D.profile(city,Vector2i(23,20),CityGeometry3D.HEIGHT)
	var end := Vector2(23,20)+Vector2(profile.outside)+Vector2(profile.inward)*(float(profile.depth)+.025)
	var normal := Vector3(profile.inward.x,0,profile.inward.y)
	var point := Vector3(end.x,float(profile.floor_end)+.20,end.y)
	var ray := PhysicsRayQueryParameters3D.create(point+normal*.1,point-normal*.1,ExploreActorProfile.OBSTACLE)
	ray.hit_back_faces = true
	check(not walker.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"physical recess restored after transit exit")

	check_eq(SaveFormat.encode_city(city),city_before,"corner converter projection leaves city unchanged")
