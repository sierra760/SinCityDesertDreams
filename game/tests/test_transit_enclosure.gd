# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
const Fixtures := preload("res://tests/test_explore_transit_network.gd")

## Collision layer of the double-sided copy of the rendered shell.
const SIDED := 1<<19

class EnclosedWorld extends ExploreTransitWorld3D:
	func _apply_cutouts(_cuts: Dictionary) -> void: pass

func _visible_faces(node: Node, parent: Transform3D, out: PackedVector3Array) -> void:
	var at := parent
	if node is Node3D:
		if not node.visible: return
		at*=node.transform
	if node is MeshInstance3D and node.mesh!=null:
		for point: Vector3 in node.mesh.get_faces(): out.append(at*point)
	for child: Node in node.get_children(): _visible_faces(child,at,out)

func test_full_subway_station_has_no_open_shell_along_platform_or_track_approach() -> void:
	await _check_city(Fixtures.subway_city())

func test_terminus_station_closes_the_unused_end_of_its_room() -> void:
	var city := Fixtures.subway_city()
	for x: int in range(18,20): city.underground.put(x,20,0)
	await _check_city(city)

func test_diagonal_elevator_passage_joins_a_closed_station_room() -> void:
	var city := Fixtures.flat_city()
	for x: int in range(21,30): city.underground.put(x,21,Underground.subway_code(10))
	for cell: Vector2i in [Vector2i(20,20),Vector2i(29,21)]:
		city.building.putv(cell,Buildings.SUBWAY_STATION)
		city.underground.putv(cell,Underground.STATION_LINK)
	await _check_city(city)

func test_station_on_a_bend_closes_its_platform_side_portal() -> void:
	# The track turns at the station, so one tube leaves through the thin
	# platform-side wall rather than an end wall.
	var city := Fixtures.flat_city()
	for x: int in range(21,27): city.underground.put(x,20,Underground.subway_code(10))
	for y: int in range(21,27): city.underground.put(20,y,Underground.subway_code(5))
	for cell: Vector2i in [Vector2i(20,20),Vector2i(20,27)]:
		city.building.putv(cell,Buildings.SUBWAY_STATION)
		city.underground.putv(cell,Underground.STATION_LINK)
	await _check_city(city)

func test_graded_running_tubes_keep_a_closed_station_join() -> void:
	var city := Fixtures.subway_city()
	city.set_heights(21,20,5,0)
	await _check_city(city)

func _check_city(city: City) -> void:
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var network := ExploreTransitNetwork.new()
	network.rebuild(city,graph,1)
	var world := EnclosedWorld.new()
	root.add_child(world)
	world.network=network
	var path := network.route(0,1)
	world.build(path)
	var station := network.station_for_route(path,0)
	var at := Transform3D(Basis(Vector3.UP,float(station.yaw)),station.position)
	# The rendered mesh and physical shell are checked independently. Neither
	# scenery nor terrain may disguise missing station walls or ceiling joints.
	# Rendered faces are single-sided like the renderer's culled finishes: a
	# ray that only meets a face from behind (a hollow cut edge or an open box
	# end) sees straight through to the ground. Such back-face leaks are
	# located with a double-sided copy and charged to the station when they
	# lie within its room and wall portals; any ray meeting nothing fails.
	var faces := PackedVector3Array()
	_visible_faces(world,Transform3D.IDENTITY,faces)
	var rendered := Node3D.new()
	for layer: int in [1,SIDED]:
		var body := StaticBody3D.new()
		body.collision_layer=layer
		body.collision_mask=0
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision=layer==SIDED
		shape.set_faces(faces)
		var collision := CollisionShape3D.new()
		collision.shape=shape
		body.add_child(collision)
		rendered.add_child(body)
	root.add_child(rendered)
	await physics_frame
	await physics_frame
	var misses := {"visible":[],"physical":[]}
	var samples: Array[Dictionary] = []
	for z: float in [-.43,-.30,0,.30,.43,.53,-.53]:
		var x: float=float(station.side)*.245 if absf(z)<.46 else 0.0
		if absf(z)>.46 and world.support_for(at*Vector3(x,.03,z)).is_empty(): continue
		samples.append({"eye":at*Vector3(x,.13,z),"label":"platform "+str(z)})
	# Low against the platform wall, beside the lift shaft, and in the lobby.
	for z: float in [-.30,-.15,0,.15]:
		samples.append({"eye":at*Vector3(float(station.side)*.31,.05,z),"label":"wall foot "+str(z)})
	var lift := ExploreTransitWorld3D.Elevator.pose_for(station)
	for z: float in [-.40,-.30,-.21]:
		samples.append({"eye":lift*Vector3(.45,.12,z),"label":"lobby "+str(z)})
	var from: Vector3=lift*Vector3(.415,.025,-.30)
	var to: Vector3=station.platform+station.normal*.11-lift.basis.z*.30
	for fraction: float in [0,.15,.5,.85,1]:
		samples.append({"eye":from.lerp(to,fraction)+Vector3.UP*.105,"label":"passage "+str(fraction)})
	for sample: Dictionary in samples:
		for pitch: float in [-1.0,-.35,0,.45,1.05]:
			for heading: int in 48:
				var angle := TAU*heading/48.0
				var direction := at.basis*Vector3(cos(angle)*cos(pitch),sin(pitch),sin(angle)*cos(pitch))
				var eye: Vector3=sample.eye
				var space := world.get_world_3d().direct_space_state
				for kind: String in misses:
					var query := PhysicsRayQueryParameters3D.create(eye,eye+direction*32,1 if kind=="visible" else 24)
					if not space.intersect_ray(query).is_empty(): continue
					if kind=="visible":
						var behind := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye,eye+direction*32,SIDED))
						if not behind.is_empty():
							var local: Vector3=at.affine_inverse()*behind.position
							if absf(local.z)>ExploreTransitWorld3D.ROOM_HALF_LENGTH+.05: continue
					misses[kind].append({"sample":sample.label,"pitch":pitch,"heading":heading})
	for kind: String in misses:
		check(misses[kind].is_empty(),"%s shell has %d escaping rays; first: %s" % [kind,misses[kind].size(),str(misses[kind].slice(0,8))])
	rendered.free()
	world.free()
	await physics_frame
