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

func _setup(branch: bool = false) -> void:
	var city := flat_city()
	view = SnapshotView.new()
	root.add_child(view)
	view.bind_city(city)
	view._geometry_revision = 1
	view.snapshot_chunks = [CityGeometry3D.build_chunk(city,Rect2i(18,18,6,6))]
	view.snapshot_networks = view.networks.physical_data()
	traversal = CityTraversalWorld3D.new()
	view.world.add_child(traversal)
	traversal.rebuild(city,view.snapshot_chunks,view.snapshot_networks,1)
	var network := ExploreTransitNetwork.new()
	network.city = city
	var height := CityGeometry3D.ground_height(city,Vector2i(20,20))-.62
	var a := Vector3i(20,1,21)
	var b := Vector3i(20,1,20)
	var c := Vector3i(21,1,20)
	network.nodes = {a:{"point":Vector3(20.5,height,21.5),"links":[b]},b:{"point":Vector3(20.5,height,20.5),"links":[a,c]},c:{"point":Vector3(21.5,height,20.5),"links":[b]}}
	if branch:
		var d := Vector3i(19,1,20)
		network.nodes[d] = {"point":Vector3(19.5,height,20.5),"links":[b]}
		network.nodes[b].links.append(d)
	var nodes: Array[Vector3i] = [a,b,c]
	var points := PackedVector3Array([network.nodes[a].point])
	var corner := network.corner_points(b,a)
	if corner.is_empty(): points.append(network.nodes[b].point)
	else: points.append_array(corner)
	points.append(network.nodes[c].point)
	var distances := PackedFloat32Array([0.0])
	for index: int in range(1,points.size()): distances.append(distances[-1]+points[index].distance_to(points[index-1]))
	path = {"nodes":nodes,"points":points,"distances":distances,"stops":[],"length":distances[-1]}
	world = ExploreTransitWorld3D.new()
	view.world.add_child(world)
	world.bind(view,traversal,network)
	world.build(path)
	walker = ExplorePedestrian.new()
	view.world.add_child(walker)
	walker.bind(traversal)
	recoveries = 0
	walker.recovery_requested.connect(func(_reason): recoveries += 1)
	support = SupportOwner.new()
	view.world.add_child(support)
	support.world = world
	walker.transit_support = support
	await physics_frame
	await physics_frame

func after_each() -> void:
	if is_instance_valid(world): world.clear()
	if is_instance_valid(view): view.free()
	await physics_frame

func test_curve_and_branch_have_unobstructed_physical_centerline() -> void:
	for branch in [false,true]:
		await _setup(branch)
		for i in range(5,195):
			var at := ExploreTransitNetwork.sample(path,float(i)/100.0)
			at.origin += Vector3.UP*.027
			var next := ExploreTransitNetwork.sample(path,float(i+1)/100.0).origin+Vector3.UP*.027
			check(not walker.test_move(at,next-at.origin),"physical tube blocks curve/branch at %s, branch %s" % [i,branch])
		if not branch:
			world.clear()
			view.free()
			await physics_frame

func test_actual_rider_stays_in_carriage_through_right_angle() -> void:
	await _setup()
	support.train = ExploreTransitTrain.new()
	view.world.add_child(support.train)
	support.train.global_transform = ExploreTransitNetwork.sample(path,.1)
	walker.global_position = support.train.global_transform*Vector3(0,.027,0)
	await physics_frame
	for i in 20:
		walker.step(ExploreInputFrame.idle(),0,1.0/60.0)
		await physics_frame
	var before := support.train.global_transform.affine_inverse()*walker.global_position
	for i in 360:
		support.train.global_transform = ExploreTransitNetwork.sample(path,.1+float(i+1)*1.8/360)
		walker.step(ExploreInputFrame.idle(),0,1.0/60.0)
		await physics_frame
	var after := support.train.global_transform.affine_inverse()*walker.global_position
	check_eq(recoveries,0,"no unsupported/obstruction recovery during physical turn")
	check(support.train.contains(walker.global_position),"rider stays in turning cabin")
	check_lt(Vector2(after.x-before.x,after.z-before.z).length(),.003,"turn carries passenger without wall-induced drift")

func test_actual_rider_crosses_authored_surface_subway_portal() -> void:
	var city := preload("res://tests/test_explore_transit_network.gd").mixed_city()
	view = SnapshotView.new()
	root.add_child(view)
	view.bind_city(city)
	view._geometry_revision = 1
	view.networks.rebuild(city)
	view.snapshot_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,24,12))]
	view.snapshot_networks = view.networks.physical_data()
	var original_obstacles: PackedVector3Array = view.snapshot_networks.physical_obstacle_faces.duplicate()
	traversal = CityTraversalWorld3D.new()
	view.world.add_child(traversal)
	traversal.rebuild(city,view.snapshot_chunks,view.snapshot_networks,1)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var network := ExploreTransitNetwork.new()
	network.rebuild(city,graph,1)
	path = network.route(0,1)
	check(not path.is_empty(),"mixed station route exists")
	if path.is_empty(): return
	world = ExploreTransitWorld3D.new()
	view.world.add_child(world)
	world.bind(view,traversal,network)
	world.build(path)
	check_eq(world._filter_portal_faces(original_obstacles).size(),original_obstacles.size()-12,"opens exactly two recess triangles and their reverse-winding collision copies")
	var saved_meshes: Array[Dictionary] = world._terrain.duplicate()
	var removed_visual_vertices := 0
	for record: Dictionary in saved_meshes:
		var node: Variant = record.node.get_ref()
		if is_instance_valid(node): removed_visual_vertices += record.mesh.get_faces().size()-node.mesh.get_faces().size()
	check_eq(removed_visual_vertices,6,"same exact visual recess triangles removed")
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
	for record: Dictionary in saved_meshes:
		var node: Variant = record.node.get_ref()
		if is_instance_valid(node): check(node.mesh==record.mesh,"original portal mesh restored by identity")
	var profile := CityPortal3D.profile(city,Vector2i(24,20),CityGeometry3D.HEIGHT)
	var end := Vector2(24,20)+Vector2(profile.outside)+Vector2(profile.inward)*(float(profile.depth)+.025)
	var normal := Vector3(profile.inward.x,0,profile.inward.y)
	var point := Vector3(end.x,float(profile.floor_end)+.20,end.y)
	var ray := PhysicsRayQueryParameters3D.create(point+normal*.1,point-normal*.1,ExploreActorProfile.OBSTACLE)
	ray.hit_back_faces = true
	check(not walker.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"physical recess restored after transit exit")
