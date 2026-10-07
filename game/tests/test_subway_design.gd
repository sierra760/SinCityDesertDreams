# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

func _lift() -> Node3D:
	var lift := ExploreTransitWorld3D.Elevator.new()
	root.add_child(lift)
	lift.configure({"position":Vector3(20,2,20),"surface":3.0,"yaw":0.0,"side":1})
	return lift

func test_opening_doors_stay_in_their_recess_instead_of_crossing_lobby_walls() -> void:
	var lift := _lift()
	for fraction: float in [.0,.25,.5,.75,1.0]:
		lift._set_doors(fraction)
		var door: Node3D=lift._cabin_door
		for leaf: Node in door.get_children():
			if leaf is MeshInstance3D and leaf.visible and door.visible:
				var bounds: AABB=leaf.transform*leaf.mesh.get_aabb()
				bounds.position+=door.position-door.get_meta("closed_at")
				check(bounds.position.x>=-.076 and bounds.end.x<=.076,"door panels must retract inside their jambs, fraction "+str(fraction))
	lift.free()
	await physics_frame

func test_elevator_explains_destination_and_blocked_doorway() -> void:
	var lift := _lift()
	var rider := ExplorePedestrian.new()
	root.add_child(rider)
	rider.global_position=lift.cabin.global_position
	check(lift.interact(rider))
	check(lift.prompt(rider.global_position).to_lower().contains("platform"),"closing feedback names requested floor")
	rider.global_position=lift.cabin.global_transform*Vector3(0,0,-.105)
	lift.step(.1,rider)
	check(lift.prompt(rider.global_position).contains("Step fully inside"),"blocked doorway explains the corrective action")
	check_eq(lift.prompt(lift.global_transform*Vector3(.415,.55,-.20)),"","no false call prompt halfway down a shaft")
	rider.free(); lift.free()
	await physics_frame

func _sign_words(node: Node) -> String:
	var words := ""
	if node is MeshInstance3D and node.mesh is TextMesh: words+=node.mesh.text+" "
	for child: Node in node.get_children(): words+=_sign_words(child)
	return words

func test_lift_controls_have_mounted_instructions_and_landing_labels() -> void:
	var lift := _lift()
	var words := _sign_words(lift)
	check(words.contains("PRESS F"),"physical control panel explains the interaction key")
	check(words.contains("STREET") and words.contains("PLATFORM"),"both landings and cabin controls are identified")
	lift.free()
	await physics_frame

func _turn_network(rotation: int) -> ExploreTransitNetwork:
	var network := ExploreTransitNetwork.new()
	var basis := Basis(Vector3.UP,rotation*PI*.5)
	var origin := Vector3(20.5,2,20.5)
	var keys: Array[Vector3i]=[]
	for offset: Vector3 in [Vector3(0,0,2),Vector3(0,0,1),Vector3.ZERO,Vector3(1,0,0),Vector3(2,0,0)]:
		var p: Vector3=origin+basis*offset
		var key := Vector3i(roundi(p.x-.5),1,roundi(p.z-.5))
		keys.append(key)
		network.nodes[key]={"point":p,"links":[]}
	for i: int in keys.size():
		if i>0: network.nodes[keys[i]].links.append(keys[i-1])
		if i<keys.size()-1: network.nodes[keys[i]].links.append(keys[i+1])
	for index: int in [0,4]:
		var id := 0 if index==0 else 1
		network.stations.append({"id":id,"node":keys[index],"forward":basis*(Vector3.FORWARD if id==0 else Vector3.RIGHT),"position":network.nodes[keys[index]].point})
	return network

func test_all_four_subway_corner_routes_follow_the_curved_rails() -> void:
	for rotation: int in 4:
		var network := _turn_network(rotation)
		var route := network._route_between(network.stations[0],network.stations[1])
		check(not route.is_empty())
		if route.is_empty(): continue
		check_lt(absf(route.length-(3.0+PI*.25)),.002,"quarter-circle replaces the corner's two square half-spans")
		var center := Vector3(20.5,2,20.5)
		var nearest := INF
		for p: Vector3 in route.points: nearest=minf(nearest,p.distance_to(center))
		check_gt(nearest,.19,"train never cuts through the old sharp tile center")
		check_eq(route.stops.size(),2,"curving preserves both stopping platforms")

class TubeWorld extends ExploreTransitWorld3D:
	func _apply_cutouts(_cuts: Dictionary) -> void: pass

func test_curved_tubes_are_solid_and_clear_for_the_carriage_in_all_rotations() -> void:
	for rotation: int in 4:
		var network := _turn_network(rotation)
		var route := network._route_between(network.stations[0],network.stations[1])
		route.stops=[]
		var world := TubeWorld.new()
		root.add_child(world)
		world.network=network
		world.build(route)
		await physics_frame
		await physics_frame
		var space := root.get_world_3d().direct_space_state
		for i: int in range(5,95,3):
			var at := ExploreTransitNetwork.sample(route,route.length*float(i)/100)
			var eye := at.origin+Vector3.UP*.105
			for direction: Vector3 in [at.basis.x,-at.basis.x,Vector3.UP,Vector3.DOWN]:
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye,eye+direction*.90,24))
				check(not hit.is_empty(),"continuous side/roof/floor on curved tube, rotation "+str(rotation))
			# Every cabin corner must remain inside the tube's clear envelope.
			for x: float in [-.123,.123]:
				for z: float in [-.30,.30]:
					var corner := at*Vector3(x,.12,z)
					var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye,corner,24))
					check(hit.is_empty(),"turning carriage does not intersect curved walls")
		world.free()
		await physics_frame

func _check_signs(node: Node) -> void:
	if node is MeshInstance3D and node.mesh is TextMesh and node.has_meta("sign_backing"):
		var board: MeshInstance3D=node.get_meta("sign_backing").get_ref()
		var size: Vector3=node.mesh.get_aabb().size*node.scale
		check(size.x<board.mesh.size.x-.004 and size.y<board.mesh.size.y-.003,"changing elevator text stays within its mounted plaque")
		check(node.mesh.font.get_font_name().begins_with("BioRhyme"))
	for child: Node in node.get_children(): _check_signs(child)

func test_moving_and_arrival_labels_stay_inside_their_plates() -> void:
	var lift := _lift()
	var rider := ExplorePedestrian.new()
	root.add_child(rider)
	rider.global_position=lift.cabin.global_position
	_check_signs(lift)
	lift.interact(rider)
	_check_signs(lift)
	for i: int in 700:
		var before: Transform3D=lift.cabin.global_transform
		lift.step(1.0/60,rider)
		rider.global_transform=lift.cabin.global_transform*before.affine_inverse()*rider.global_transform
		if lift.floor==0 and lift.state=="open": break
	check_eq(lift.floor,0)
	_check_signs(lift)
	lift.interact(rider)
	_check_signs(lift)
	rider.free(); lift.free()
	await physics_frame

func test_underground_corner_art_and_geometry_use_the_same_four_masks() -> void:
	for pair: Vector2i in [Vector2i(3,10),Vector2i(6,7),Vector2i(12,8),Vector2i(9,9)]:
		var code := Underground.subway_code(pair.x)
		check_eq(Underground.from_art_code(pair.y),code,"imported diagonal corner keeps the reciprocal connection mask")
		check_eq(CityUnderground3D.decode(code).subway_mask,pair.x)

func test_curved_approach_distinguishes_waiting_platform_from_track_intrusion() -> void:
	for rotation: int in 4:
		var network := _turn_network(rotation)
		var route := network._route_between(network.stations[0],network.stations[1])
		var service := ExploreTransitService.new()
		service.route_data=route
		service.distance=1.60
		var pose := ExploreTransitNetwork.sample(route,service.distance)
		var basis := Basis(Vector3.UP,rotation*PI*.5)
		var waiting := Vector3(20.5,2.025,20.5)+basis*Vector3(-.24,0,1)
		var old_sensor := pose.affine_inverse()*waiting
		check(absf(old_sensor.x)<.18 and absf(old_sensor.z)<.65,"waiting passenger falls inside a plain rectangular sensor, which would report a false obstruction")
		check(not service._track_intrusion(waiting),"safe platform does not stop an approaching train")
		var intrusion := ExploreTransitNetwork.sample(route,service.distance+.35).origin+Vector3.UP*.025
		check(service._track_intrusion(intrusion),"real intrusion ahead on the curve still stops the train")
		check(not service._track_intrusion(intrusion+Vector3.UP),"a passenger above the running tube is not on its track")
		service.free()
