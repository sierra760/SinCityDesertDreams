# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Character capsules and vehicle boxes cross imported tile seams without recovery.
extends "res://tests/exploration/async_test_case.gd"

const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
const TerrainFixture := preload("res://tests/test_3d_terrain_continuity.gd")
var fixture: Node3D
var saved_scale: float
var reports: Array[String] = []

class Driver extends Node:
	signal completed
	var actor: CharacterBody3D
	var frame := ExploreInputFrame.idle()
	var ticks := 0
	var samples: Array[Vector3] = []
	func _physics_process(delta: float) -> void:
		actor.step(frame,0,delta)
		samples.append(actor.global_position)
		ticks += 1
		if ticks==180:
			set_physics_process(false)
			completed.emit()

func before_all() -> void:
	saved_scale = Engine.time_scale
	Engine.time_scale = 4.0

func after_all() -> void:
	Engine.time_scale = saved_scale

func after_each() -> void:
	if is_instance_valid(fixture): fixture.free()
	reports.clear()
	await physics_frame

func cross(uphill: bool, vehicle: bool, along_z := false) -> void:
	var city := TerrainFixture.hillside(along_z)
	# The route spans the grade's toe, so the journey never leaves its road.
	for i in range(14,30):
		city.building.put(22 if along_z else i,i if along_z else 22,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5 if along_z else 10))
	fixture = Fixture.attach(self,city)
	var world := fixture.get_node("traversal") as CityTraversalWorld3D
	var actor: CharacterBody3D = ExploreCar.new() if vehicle else ExplorePedestrian.new()
	fixture.add_child(actor)
	actor.bind(world)
	actor.recovery_requested.connect(func(reason: String) -> void: reports.append(reason))
	var start := Vector2(20.65 if uphill else 21.35,22.5 if vehicle else 22.88)
	if along_z: start = Vector2(start.y,start.x)
	var cell := Vector2i(floori(start.x),floori(start.y))
	actor.position = CityGeometry3D.point_on_ground(city,cell,start-Vector2(cell))+Vector3.UP*(.042 if vehicle else .002)
	if vehicle: actor.rotation.y = (PI if uphill else 0.0) if along_z else (-PI/2 if uphill else PI/2)
	await physics_frame
	await physics_frame
	var driver := Driver.new()
	driver.actor = actor
	driver.frame.sprint = true
	driver.frame.move = Vector2(0,-.5) if vehicle else Vector2(1 if uphill else -1,0)
	if along_z and not vehicle: driver.frame.move = Vector2(0,1 if uphill else -1)
	fixture.add_child(driver)
	await driver.completed
	await process_frame
	check(reports.is_empty(),"crossing the terrain seam must not request recovery: "+str(reports))
	var coordinate: float = actor.position.z if along_z else actor.position.x
	if uphill: check(coordinate>21.5,"native input climbs past the formerly broken edge")
	else: check(coordinate<20.5,"native input descends past the formerly broken edge")
	for feet: Vector3 in driver.samples:
		check(feet.is_finite(),"every physical pose stays finite")
		var support := world.support_near(feet,.05,.08,[actor.get_rid()])
		check(not support.is_empty(),"physical support is continuous throughout the journey")

func test_walker_climbs_imported_seam() -> void: await cross(true,false)
func test_walker_descends_imported_seam() -> void: await cross(false,false)
func test_car_climbs_imported_seam() -> void: await cross(true,true)
func test_car_descends_imported_seam() -> void: await cross(false,true)
func test_walker_climbs_north_south_seam() -> void: await cross(true,false,true)
func test_walker_descends_north_south_seam() -> void: await cross(false,false,true)
func test_car_climbs_north_south_seam() -> void: await cross(true,true,true)
func test_car_descends_north_south_seam() -> void: await cross(false,true,true)
