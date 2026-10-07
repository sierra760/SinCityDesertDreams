# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Real controller journeys cross the closed curb and verge faces in both directions.
extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
class Driver extends Node:
	signal completed
	var actor: CharacterBody3D
	var frame := ExploreInputFrame.idle()
	var ticks := 0
	var samples: Array[Vector3] = []
	var along_z := false
	var reverse := false
	func _physics_process(delta: float) -> void:
		actor.step(frame,0,delta);samples.append(actor.global_position);ticks+=1
		var at: float=actor.position.z if along_z else actor.position.x
		if (at<19.65 if reverse else at>21.35) or ticks>=180:
			set_physics_process(false);completed.emit()
var fixture: Node3D
var previous_scale: float
func before_all() -> void:
	previous_scale=Engine.time_scale;Engine.time_scale=4
func after_all() -> void: Engine.time_scale=previous_scale
func after_each() -> void:
	if is_instance_valid(fixture):fixture.free()
	await physics_frame
func cross(vehicle: bool, along_z: bool, reverse: bool) -> void:
	var city := flat_city()
	for i: int in range(17,30):city.building.put(i if along_z else 20,20 if along_z else i,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10 if along_z else 5))
	fixture=Fixture.attach(self,city)
	var world := fixture.get_node("traversal") as CityTraversalWorld3D
	var actor: CharacterBody3D=ExploreCar.new() if vehicle else ExplorePedestrian.new()
	fixture.add_child(actor);actor.bind(world)
	var reports: Array[String]=[]
	actor.recovery_requested.connect(func(reason: String) -> void:reports.append(reason))
	var start:=Vector2(21.2 if reverse else 19.8,22.5)
	if along_z:start=Vector2(start.y,start.x)
	actor.position=Vector3(start.x,4*CityGeometry3D.HEIGHT+.002,start.y)
	if vehicle:actor.rotation.y=(0.0 if reverse else PI) if along_z else (PI/2 if reverse else -PI/2)
	await physics_frame;await physics_frame
	var driver:=Driver.new();driver.actor=actor;driver.frame.sprint=true;driver.along_z=along_z;driver.reverse=reverse
	driver.frame.move=Vector2(0,-.5) if vehicle else (Vector2(0,-1 if reverse else 1) if along_z else Vector2(-1 if reverse else 1,0))
	fixture.add_child(driver);await driver.completed;await process_frame
	var coordinate:float=actor.position.z if along_z else actor.position.x
	print("CURB_CROSS car=",vehicle," along_z=",along_z," reverse=",reverse," ticks=",driver.ticks," end=",actor.position," recovery=",reports)
	check(coordinate<19.75 if reverse else coordinate>21.25,"controller crosses both closed edges without being blocked: "+str(actor.position))
	check(reports.is_empty(),"no recovery request during curb crossing")
	for feet: Vector3 in driver.samples:
		check(feet.is_finite(),"finite pose")
		check(not world.support_near(feet,.05,.08,[actor.get_rid()]).is_empty(),"continuous support")
func test_walker_crosses_east_west() -> void: await cross(false,false,false)
func test_walker_crosses_west_east() -> void: await cross(false,false,true)
func test_walker_crosses_north_south() -> void: await cross(false,true,false)
func test_walker_crosses_south_north() -> void: await cross(false,true,true)
func test_car_crosses_east_west() -> void: await cross(true,false,false)
func test_car_crosses_west_east() -> void: await cross(true,false,true)
func test_car_crosses_north_south() -> void: await cross(true,true,false)
func test_car_crosses_south_north() -> void: await cross(true,true,true)
