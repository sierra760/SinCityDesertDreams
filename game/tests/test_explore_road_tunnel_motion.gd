# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
const TunnelFixture := preload("res://tests/exploration/road_tunnel_fixture.gd")
var fixture: Node3D
var reports: Array[String] = []
var prior_ticks: int
var prior_scale: float

class Driver extends Node:
	signal completed
	var actor: CharacterBody3D
	var frame := ExploreInputFrame.idle()
	var yaw := 0.0
	var vertical := false
	var reverse := false
	var ticks := 0
	var limit := 3000
	var min_y := INF
	var max_y := -INF
	func _physics_process(delta: float) -> void:
		actor.step(frame,yaw,delta)
		min_y = minf(min_y,actor.position.y)
		max_y = maxf(max_y,actor.position.y)
		ticks += 1
		var at: float = actor.position.z if vertical else actor.position.x
		if ticks>=limit or (at<19.7 if reverse else at>27.3):
			set_physics_process(false)
			completed.emit()

func before_all() -> void:
	prior_ticks = Engine.physics_ticks_per_second
	prior_scale = Engine.time_scale
	Engine.physics_ticks_per_second = 600
	Engine.time_scale = 10

func after_all() -> void:
	Engine.physics_ticks_per_second = prior_ticks
	Engine.time_scale = prior_scale

func after_each() -> void:
	if is_instance_valid(fixture): fixture.free()
	reports.clear()
	await physics_frame

func journey(vertical: bool, reverse: bool, driving: bool, kind: StringName = &"car", covered_water := false) -> void:
	var city: City = TunnelFixture.city(vertical)
	if covered_water:
		city.terrain.put(23,20,Terrain.SUBMERGED)
		city.set_heights(23,20,8,9)
	fixture = Fixture.attach(self,city)
	var world := fixture.get_node("traversal") as CityTraversalWorld3D
	var actor: CharacterBody3D = ExploreCar.new() if driving else ExplorePedestrian.new()
	if driving:
		check(actor.configure_kind(kind),"selected road vehicle")
		var graph := CityTrafficGraph.new()
		graph.bind_city(city)
		actor.route_graph = graph
	fixture.add_child(actor)
	actor.bind(world)
	actor.recovery_requested.connect(func(reason: String) -> void: reports.append(reason))
	var start := 27.5 if reverse else 19.5
	var position := Vector3(20.65,2.49148974,start) if vertical else Vector3(start,2.49148974,20.65)
	var yaw := (0.0 if reverse else PI) if vertical else (PI/2 if reverse else -PI/2)
	if driving: actor.apply_safe_pose(Transform3D(Basis(Vector3.UP,yaw),position))
	else: actor.transform = Transform3D(Basis(Vector3.UP,yaw),position)
	await physics_frame
	var driver := Driver.new()
	driver.actor = actor
	driver.vertical = vertical
	driver.reverse = reverse
	driver.yaw = yaw
	driver.frame.move = Vector2(0,-1)
	driver.frame.sprint = true
	fixture.add_child(driver)
	await driver.completed
	await process_frame
	var at: float = actor.position.z if vertical else actor.position.x
	check(at<19.7 if reverse else at>27.3,"actual input crosses both mouths and entire buried span")
	check(reports.is_empty(),"tunnel journey needs no recovery: "+str(reports))
	check(actor.landed(),"supported on exit road")
	check_between(driver.min_y,2.486,2.500,"never falls under floor")
	check_between(driver.max_y,2.486,2.500,"never climbs the hill above tunnel")

func test_walk_east() -> void: await journey(false,false,false)
func test_walk_west() -> void: await journey(false,true,false)
func test_walk_south() -> void: await journey(true,false,false)
func test_walk_north() -> void: await journey(true,true,false)
func test_drive_east() -> void: await journey(false,false,true)
func test_drive_west() -> void: await journey(false,true,true)
func test_drive_south() -> void: await journey(true,false,true)
func test_drive_north() -> void: await journey(true,true,true)
func test_bus_inside_tunnel() -> void: await journey(false,false,true,&"bus")

func test_road_camera_stays_inside_and_returns_outside() -> void:
	fixture = Fixture.attach(self,TunnelFixture.city())
	var world := fixture.get_node("traversal") as CityTraversalWorld3D
	var actor := ExplorePedestrian.new()
	fixture.add_child(actor)
	actor.bind(world)
	actor.position = Vector3(23.5,2.49148974,20.65)
	var rig := CityExploreCamera3D.new()
	fixture.add_child(rig)
	rig.configure_target(actor,0)
	var controller := CityExplorationController.new()
	fixture.add_child(controller)
	controller.occupied = actor
	controller.traversal = world
	controller.camera_rig = rig
	await physics_frame
	controller._update_camera_space({})
	check(rig.interior_active,"session recognizes buried road interior")
	for angle: float in [-PI,-PI/2,0,PI/2,PI]:
		rig.yaw = angle
		rig.pitch = .5
		rig.update_follow(0)
		check(world.inside_road_tunnel(rig.camera.global_position),"eye remains in finite road tunnel during orbit")
		check(rig.camera.current,"indoor view available")
	actor.position = Vector3(19.5,2.49148974,20.5)
	controller._update_camera_space({})
	rig.update_follow(0)
	check(not rig.interior_active and not rig.cabin_first_person,"outside view returns at exit")
	check(not world.inside_road_tunnel(Vector3(23.5,5,20.5)),"hill surface is outdoors")
	var bus := ExploreCar.new()
	bus.configure_kind(&"bus")
	fixture.add_child(bus)
	bus.bind(world)
	bus.apply_safe_pose(Transform3D(Basis.IDENTITY,Vector3(23.5,2.49148974,20.65)))
	controller.occupied = bus
	controller.car = bus
	controller.mode = 1
	rig.configure_target(bus,1)
	await physics_frame
	controller._update_camera_space({})
	rig.update_follow(0)
	check(rig.cabin_first_person,"road vehicle receives tunnel eye view")
	check(not bus._visual.visible,"tall bus model cannot surround the indoor eye")
	bus.position = Vector3(27.5,2.49148974,20.65)
	controller._update_camera_space({})
	rig.update_follow(0)
	check(bus._visual.visible,"selected bus model returns outdoors")
	controller.car = null
	controller.occupied = null
	controller.traversal = null
	controller.camera_rig = null

func test_tunnel_side_and_roof_remain_solid() -> void:
	fixture = Fixture.attach(self,TunnelFixture.city())
	await physics_frame
	var space := fixture.get_world_3d().direct_space_state
	for end: Vector3 in [Vector3(23.5,2.65,21.2),Vector3(23.5,3.1,20.5)]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(23.5,2.65,20.5),end,ExploreActorProfile.OBSTACLE)
		ray.hit_back_faces = true
		check(not space.intersect_ray(ray).is_empty(),"road shell stops passage through side/ceiling")

func test_walk_below_water() -> void: await journey(false,false,false,&"car",true)
func test_drive_below_water() -> void: await journey(false,true,true,&"car",true)
