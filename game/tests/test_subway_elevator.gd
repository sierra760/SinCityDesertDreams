# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
const Fixtures := preload("res://tests/test_explore_transit_stations.gd")

func test_elevator_has_reversible_moving_support_and_closed_landing_gates() -> void:
	var path := "res://scripts/exploration/transit/station_elevator_3d.gd"
	check(ResourceLoader.exists(path),"station has a physical elevator instead of exposed stairs")
	if not ResourceLoader.exists(path): return
	var lift: Node3D=load(path).new()
	root.add_child(lift)
	var station := {"position":Vector3(20.5,3,20.5),"access_position":Vector3(20.5,3,20.5),"surface":4.5,"yaw":0.0,"side":1,"platform":Vector3(20.745,3.025,20.5)}
	lift.configure(station)
	await physics_frame
	var traveler := ExplorePedestrian.new()
	root.add_child(traveler)
	traveler.global_position=lift.cabin.global_position+Vector3.UP*.002
	var start := traveler.global_position
	check(lift.interact(traveler),"inside passenger can request platform floor")
	var heights := {}
	for i: int in 720:
		var old: Transform3D=lift.cabin.global_transform
		lift.step(1.0/60.0,traveler)
		traveler.global_transform=lift.cabin.global_transform*old.affine_inverse()*traveler.global_transform
		heights[snappedf(traveler.global_position.y,.01)]=true
		await physics_frame
		if lift.state=="open" and lift.floor==0: break
	check_eq(lift.floor,0,"elevator arrives at the platform floor")
	check_gt(heights.size(),15,"descent continuously carries rider through intermediate heights")
	check_lt(absf(traveler.global_position.y-station.position.y-.025),.006)
	check(lift.support_for(traveler.global_position).get("frame")==lift.cabin,"rider keeps a moving support frame")
	check(lift.landing_closed(1),"empty street landing stays physically closed")
	check(lift.interact(traveler),"passenger can return to street")
	for i: int in 720:
		var old: Transform3D=lift.cabin.global_transform
		lift.step(1.0/60.0,traveler)
		traveler.global_transform=lift.cabin.global_transform*old.affine_inverse()*traveler.global_transform
		await physics_frame
		if lift.state=="open" and lift.floor==1: break
	check_eq(lift.floor,1)
	check_lt(traveler.global_position.distance_to(start),.006,"return ride reaches the same entrance")
	check(lift.landing_closed(0),"empty basement landing remains sealed")
	traveler.free()
	lift.free()
	await physics_frame

func test_station_uses_stable_eye_camera_without_changing_outdoor_follow() -> void:
	var rig := CityExploreCamera3D.new()
	var traveler := ExplorePedestrian.new()
	root.add_child(traveler)
	root.add_child(rig)
	traveler.position=Vector3(30,2,30)
	rig.configure_target(traveler,0)
	rig.set_interior(true)
	for i: int in 24:
		rig.orbit(Vector2(17,4),1.0,false)
		rig.update_follow(1.0/60.0)
		check_lt(Vector2(rig.camera.global_position.x-traveler.global_position.x,rig.camera.global_position.z-traveler.global_position.z).length(),.001,"indoor view remains at the passenger eye")
		check(rig.camera.global_basis.is_finite())
	check(not traveler._visual.visible,"eye view hides only the avatar mesh")
	rig.set_interior(false)
	rig.update_follow(.1)
	check_gt(rig.camera.global_position.distance_to(traveler.global_position),.25,"street view restores ordinary follow")
	check(traveler._visual.visible)
	rig.free()
	traveler.free()
	await physics_frame

func test_subway_track_has_sleepers_and_solid_ballast_instead_of_a_ribbon() -> void:
	var underground := CityUnderground3D.new()
	root.add_child(underground)
	var city := Fixtures.terminal_subway_city()
	underground.bind_city(city)
	var colors := PackedColorArray()
	for surface: int in underground.mesh_instance.mesh.get_surface_count():
		var arrays := underground.mesh_instance.mesh.surface_get_arrays(surface)
		colors.append_array(arrays[Mesh.ARRAY_COLOR])
	var timber := false
	var steel := false
	for color: Color in colors:
		if Vector3(color.r-.40,color.g-.33,color.b-.26).length()<.006: timber=true
		if Vector3(color.r-.72,color.g-.75,color.b-.71).length()<.006: steel=true
	check(timber,"subway overlay has transverse railway sleepers")
	check(steel,"subway overlay has a pair of steel running rails")
	underground.free()
	await physics_frame

func _tree_faces(node: Node, at: Transform3D, physical: bool, faces: PackedVector3Array) -> void:
	if node is Node3D: at*=node.transform
	if physical and node is CollisionShape3D and not node.disabled:
		var shape_faces := PackedVector3Array()
		if node.shape is BoxShape3D:
			var box := BoxMesh.new()
			box.size=node.shape.size
			shape_faces=box.get_faces()
		elif node.shape is ConcavePolygonShape3D: shape_faces=node.shape.get_faces()
		for point: Vector3 in shape_faces: faces.append(at*point)
	elif not physical and node is MeshInstance3D and node.visible:
		for surface: int in node.mesh.get_surface_count():
			var arrays: Array=node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			for n: int in (indices.size() if not indices.is_empty() else vertices.size()): faces.append(at*vertices[indices[n] if not indices.is_empty() else n])
	for child: Node in node.get_children(): _tree_faces(child,at,physical,faces)

func _floor_hit(faces: PackedVector3Array, at: Vector3) -> float:
	var nearest := INF
	for i: int in range(0,faces.size(),3):
		var hit: Variant=Geometry3D.ray_intersects_triangle(at,Vector3.DOWN,faces[i],faces[i+1],faces[i+2])
		if hit!=null and at.distance_to(hit)<nearest: nearest=at.distance_to(hit)
	return nearest

func test_surface_plaza_and_open_lift_floor_close_the_station_tile() -> void:
	for side: int in [-1,1]:
		var at := Vector3(20.5,2,20.5)
		var yaw := PI*.5
		var basis := Basis(Vector3.UP,yaw)
		var station := {"id":0,"name":"Subway 20,20","anchor":Vector2i(20,20),"position":at,"access_position":at,"surface":2.825,"yaw":yaw,"side":side,"subway":true,"platform":at+basis*Vector3(side*.24,.025,0),"normal":basis*Vector3(side,0,0),"forward":basis*Vector3.FORWARD}
		var world := ExploreTransitWorld3D.new()
		root.add_child(world)
		world._platform(station)
		await physics_frame
		await physics_frame
		var visible := world._faces.duplicate()
		var physical := world._physical.duplicate()
		_tree_faces(world,Transform3D.IDENTITY,false,visible)
		_tree_faces(world,Transform3D.IDENTITY,true,physical)
		var pose := ExploreTransitWorld3D.Elevator.pose_for(station)
		for x: int in 19:
			for z: int in 19:
				var point: Vector3=pose*Vector3(-.475+float(x)*.05,station.surface-at.y+.1,-.475+float(z)*.05)
				check(_floor_hit(visible,point)<.11,"street plaza/cabin has no visible ground hole at "+str(point))
				check(_floor_hit(physical,point)<.11,"street plaza/cabin has solid floor at "+str(point))
		world.free()
		await physics_frame

func test_lift_waits_for_a_passenger_in_its_doorway() -> void:
	var lift: Node3D=ExploreTransitWorld3D.Elevator.new()
	root.add_child(lift)
	lift.configure({"position":Vector3(10,2,10),"surface":3.0,"yaw":0.0,"side":1})
	var traveler := ExplorePedestrian.new()
	root.add_child(traveler)
	traveler.global_position=lift.cabin.global_position
	check(lift.interact(traveler))
	traveler.global_position=lift.cabin.global_transform*Vector3(0,0,-.105)
	for i: int in 90: lift.step(1.0/60.0,traveler)
	check_eq(lift.state,"closing","occupied doorway prevents departure")
	check_lt(absf(lift.cabin.position.y-lift.heights[1]),.00001)
	check_gt(lift._door_fraction,.99,"doors reopen while doorway is occupied")
	traveler.global_position=lift.cabin.global_position
	for i: int in 45: lift.step(1.0/60.0,traveler)
	await physics_frame
	await physics_frame
	check_eq(lift.state,"moving","clear doorway permits smooth departure")
	check(lift.landing_closed(0) and lift.landing_closed(1),"both landing gates are interlocked during travel")
	for level: int in 2:
		var ray_from: Vector3=lift.global_transform*Vector3(.415,lift.heights[level]+.11,-.24)
		var ray_to: Vector3=lift.global_transform*Vector3(.415,lift.heights[level]+.11,-.15)
		var hit := root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(ray_from,ray_to,ExploreActorProfile.OBSTACLE))
		check(not hit.is_empty(),"empty landing has a physical closed gate")
	traveler.free()
	lift.free()
	await physics_frame

func test_station_chamber_closes_ground_between_branching_track_beds() -> void:
	for grade: float in [0.0,-.20]:
		var world := ExploreTransitWorld3D.new()
		root.add_child(world)
		var origin := Vector3(20.5,2,20.5)
		var key := Vector3i(20,1,20)
		world.network=ExploreTransitNetwork.new()
		world.network.nodes[key]={"point":origin,"links":[Vector3i(21,1,20),Vector3i(20,1,21)]}
		world.network.nodes[Vector3i(21,1,20)]={"point":origin+Vector3(1,grade,0)}
		world.network.nodes[Vector3i(20,1,21)]={"point":origin+Vector3(0,0,1)}
		world._station_room({"node":key,"position":origin,"platform":origin+Vector3(.245,.025,0),"yaw":0.0,"side":1,"normal":Vector3.RIGHT})
		# Passage finishing moves the rendered faces into its textured child.
		var visible := world._faces.duplicate()
		_tree_faces(world,Transform3D.IDENTITY,false,visible)
		for x: int in 7:
			for z: int in 7:
				var ray := origin+Vector3(-.30+x*.10,.02,-.30+z*.10)
				check(_floor_hit(visible,ray)<.25,"branch chamber has a visible solid base at "+str(ray))
				check(_floor_hit(world._physical,ray)<.25,"branch chamber ground also has collision at "+str(ray))
		world.free()
		await physics_frame

func test_offset_passage_walls_join_the_access_room_exit() -> void:
	var world := ExploreTransitWorld3D.new()
	var from := Vector3(10,.025,10)
	var to := Vector3(11,.025,10)
	world._access_passage(from,to)
	for side: int in [-1,1]:
		var eye := from+Vector3(.015,.11,0)
		var direction := Vector3(0,0,side)
		var nearest := INF
		for i: int in range(0,world._physical.size(),3):
			var hit: Variant=Geometry3D.ray_intersects_triangle(eye,direction,world._physical[i],world._physical[i+1],world._physical[i+2])
			if hit!=null and eye.distance_to(hit)<=.14: nearest=minf(nearest,eye.distance_to(hit))
		check(is_finite(nearest),"connector wall begins at its room boundary")
	world.free()
