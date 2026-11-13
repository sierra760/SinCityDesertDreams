# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The city limits and open water are barriers to the flown helicopter: it
## stops at them and slides along, and is never moved back to where it last
## landed.
extends "res://tests/exploration/explore_session_case.gd"

const HALF_LENGTH := .25
var reports: Array[String] = []
var old_physics_ticks: int

func before_all() -> void:
	old_physics_ticks = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 60

func after_all() -> void:
	Engine.physics_ticks_per_second = old_physics_ticks

func before_each() -> void:
	reports.clear()

func _lake_city() -> City:
	var value := flat_city()
	value.building.put(22,20,30)
	for y: int in range(22,26):
		for x: int in range(21,25):
			value.terrain.put(x,y,Terrain.SUBMERGED)
			value.set_heights(x,y,2,4)
	return value

func _board() -> ExploreHelicopter:
	var craft: ExploreHelicopter = session.helicopter
	check(craft != null,"the fixture parks a helicopter")
	if craft == null: return null
	craft.recovery_requested.connect(func(reason: String) -> void: reports.append(reason))
	session.pedestrian.global_position = craft.global_position+Vector3(.30,0,0)
	check(session.request_interaction(),"the player boards the helicopter")
	check_eq(session.occupied,craft)
	session.set_physics_process(false)
	return craft if session.occupied == craft else null

## One controller tick with the given stick and climb, camera facing north.
func _fly(move: Vector2, vertical: float, ticks: int) -> void:
	session.camera_rig.yaw = 0.0
	for tick in ticks:
		session._held.clear()
		if move.x < 0: session._held[KEY_A] = true
		if move.x > 0: session._held[KEY_D] = true
		if move.y < 0: session._held[KEY_W] = true
		if move.y > 0: session._held[KEY_S] = true
		if vertical > 0: session._held[KEY_Q] = true
		if vertical < 0: session._held[KEY_E] = true
		session._arming = false
		session._physics_process(1.0/60.0)
		await physics_frame
	session._held.clear()

func test_map_edge_stops_the_helicopter_and_lets_it_slide_along() -> void:
	if not _setup() or not await _enter(): return
	var craft := _board()
	if craft == null: return
	var parked := craft.global_position
	await _fly(Vector2.ZERO,1.0,120)
	check(not craft.landed(),"the helicopter took off")
	# Hop to just inside the western city limit, still airborne.
	craft.global_position = Vector3(1.5,craft.global_position.y,22.5)
	await _fly(Vector2(-1,0),0.0,240)
	check_eq(reports,[] as Array[String],"reaching the city limit never requests a recovery")
	check_eq(session.occupied,craft,"the pilot keeps flying")
	check_lt(craft.global_position.x,HALF_LENGTH+.3,"the helicopter stays at the city limit")
	check(craft._inside(),"its whole body is inside the city")
	check_gt(craft.global_position.distance_to(parked),10.0,"it was not returned to where it last landed")
	check(not craft.landed(),"it is still airborne")
	var held := craft.global_position
	await _fly(Vector2(-1,-1),0.0,120)
	check_eq(reports,[] as Array[String])
	check(craft._inside(),"sliding keeps the body inside the city")
	check_lt(craft.global_position.z,held.z-.5,"pushing diagonally into the limit slides along it")
	await _fly(Vector2(1,0),0.0,120)
	check_gt(craft.global_position.x,held.x+.5,"the helicopter flies away from the limit again")
	check_eq(reports,[] as Array[String])

func test_corner_of_the_map_holds_the_helicopter_inside() -> void:
	if not _setup() or not await _enter(): return
	var craft := _board()
	if craft == null: return
	await _fly(Vector2.ZERO,1.0,120)
	craft.global_position = Vector3(1.0,craft.global_position.y,1.0)
	await _fly(Vector2(-1,-1),0.0,240)
	check_eq(reports,[] as Array[String],"the corner never requests a recovery")
	check(craft._inside(),"the body stays inside at the corner")
	check_lt(craft.global_position.x,1.0)
	check_lt(craft.global_position.z,1.0)

func test_descent_over_open_water_holds_above_the_surface() -> void:
	if not _setup(_lake_city()) or not await _enter(): return
	var craft := _board()
	if craft == null: return
	var parked := craft.global_position
	await _fly(Vector2.ZERO,1.0,120)
	craft.global_position = Vector3(23.0,craft.global_position.y,24.0)
	var world: CityTraversalWorld3D = session.traversal
	var surface := world.water_top(craft.global_position)
	check(surface > -INF,"the fixture lake is under the helicopter")
	await _fly(Vector2.ZERO,-1.0,360)
	check_eq(reports,[] as Array[String],"descending onto water never requests a recovery")
	check_eq(session.occupied,craft)
	check(not craft.landed(),"water is not a landing")
	check(not world.touches_water(craft.global_position),"the skids stay dry")
	check_lt(craft.global_position.y,surface+.05,"the helicopter comes down to just above the surface")
	check_lt(Vector2(craft.global_position.x-23.0,craft.global_position.z-24.0).length(),.05,"it holds its place over the water")
	check_gt(craft.global_position.distance_to(parked),1.0,"it was not returned to where it last landed")
	check_lt(craft.altitude(),.05,"height is read from the water surface")
	check(session._message.contains("water"),"the pilot is told why the helicopter will not land")
	check(not session.request_interaction(),"hovering over water is no place to get out")
	check_eq(session.occupied,craft)
	# Skim to the shore and land there.
	await _fly(Vector2(0,-1),0.0,200)
	await _fly(Vector2.ZERO,-1.0,240)
	check_eq(reports,[] as Array[String])
	check(craft.landed(),"dry ground beside the lake is a normal landing")
	check_lt(craft.global_position.z,22.0)

func test_low_flight_from_shore_skims_over_the_water() -> void:
	if not _setup(_lake_city()) or not await _enter(): return
	var craft := _board()
	if craft == null: return
	await _fly(Vector2.ZERO,1.0,12)
	check(not craft.landed())
	craft.global_position = Vector3(23.0,craft.global_position.y,21.2)
	var low := craft.global_position.y
	await _fly(Vector2(0,1),0.0,240)
	check_eq(reports,[] as Array[String],"crossing the shoreline at low height never requests a recovery")
	check_gt(craft.global_position.z,23.0,"the helicopter flies out over the lake")
	check(not session.traversal.touches_water(craft.global_position))
	check_lt(craft.global_position.y,low+.2,"it is not thrown upward")

func test_shoreline_stops_a_helicopter_on_its_skids() -> void:
	if not _setup(_lake_city()) or not await _enter(): return
	var craft := _board()
	if craft == null: return
	# Set down beside the lake, then push toward it without climbing.
	await _fly(Vector2.ZERO,1.0,30)
	craft.global_position = Vector3(23.0,craft.global_position.y,21.4)
	await _fly(Vector2.ZERO,-1.0,200)
	check(craft.landed(),"the helicopter is down on the shore")
	var shore := craft.global_position
	await _fly(Vector2(0,1),0.0,240)
	check_eq(reports,[] as Array[String],"the shoreline never requests a recovery")
	check_eq(session.occupied,craft)
	check(craft.landed(),"it stays on its skids at the water's edge")
	check(not session.traversal.touches_water_footprint(craft.get_child(0).global_transform,(craft.get_child(0) as CollisionShape3D).shape.size),"no part of it is over the water")
	check_lt(craft.global_position.z,22.0,"the shoreline stops it")
	check_lt(craft.global_position.distance_to(shore),.6,"it was not moved anywhere else")
	check(session._message.contains("water"),"the pilot is told why: "+session._message)
	# It can still back away, or take off and cross.
	await _fly(Vector2(0,-1),0.0,60)
	check_lt(craft.global_position.z,shore.z+.01,"it backs away from the water")
	await _fly(Vector2.ZERO,1.0,20)
	await _fly(Vector2(0,1),0.0,240)
	check_eq(reports,[] as Array[String])
	check_gt(craft.global_position.z,23.0,"airborne, it crosses the lake")
