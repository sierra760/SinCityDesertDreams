# SPDX-License-Identifier: GPL-3.0-or-later
## Scripted actors replan around an Explore actor parked on their route instead
## of waiting behind it, through the real host (actor.navigate, the traffic
## clock and Explore obstacle boxes). With no other way round they stop short
## and continue once the body moves.
extends "res://tests/exploration/explore_session_case.gd"

const Service = preload("res://scripts/exploration/mods/explore_mod_service.gd")
const Progress = preload("res://scripts/exploration/mods/explore_mod_progress.gd")
const START := Vector3(23.5,GROUND,17.5)
const ASIDE := Vector3(25.5,GROUND,21.5)

## A 14x14 ring with a north-south street at x=22 and an east-west street at
## y=23, so blocked routes have junctions to turn at.
func _grid_city() -> City:
	var value := flat_city()
	var cells := {}
	for i in range(17,31):
		for cell: Vector2i in [Vector2i(i,17),Vector2i(i,30),Vector2i(17,i),Vector2i(30,i),Vector2i(22,i),Vector2i(i,23)]: cells[cell] = true
	_pave(value,cells)
	return value

func _street_city() -> City:
	var value := flat_city()
	var cells := {}
	for x in range(18,30): cells[Vector2i(x,20)] = true
	_pave(value,cells)
	return value

static func _pave(value: City, cells: Dictionary) -> void:
	for cell: Vector2i in cells:
		var mask := 0
		for index in NetworkShapes.DIRECTIONS.size():
			if cells.has(cell+NetworkShapes.DIRECTIONS[index]): mask |= NetworkShapes.DIRECTION_BITS[index]
		value.building.put(cell.x,cell.y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,mask))

## Moves the walker, parked car and helicopter off the road so only the body a
## test places counts as an obstacle.
func _clear_road() -> void:
	session.pedestrian.place(Transform3D(Basis.IDENTITY,ASIDE))
	for key in ["car","helicopter"]:
		var actor: CharacterBody3D = session.get(key)
		if actor != null: actor.global_position = ASIDE+Vector3(1.5 if key == "car" else -1.5,.1,0)
	session._sync_traffic_collision()

func _service() -> ExploreModService:
	var service := Service.new()
	service.bind(session,[],Progress.new())
	service.enter()
	return service

func _command(service: ExploreModService, request_id: int, kind: String, args: Dictionary) -> Dictionary:
	return service.api.apply({"owner":"driver","generation":service.generation,"request_id":request_id,"kind":kind,"args":args})

func _spawn_and_navigate(service: ExploreModService, from: Vector2i, to: Vector2i) -> Dictionary:
	var graph := view.traffic.graph
	var at := graph.point(from,&"road")
	var spawn := _command(service,1,"actor.spawn",{"kind":"car","options":{"key":"car","position":{"x":at.x,"y":at.y,"z":at.z}}})
	check_eq(spawn.code,"ok","scripted car spawns")
	if spawn.code != "ok": return {}
	var goal := graph.point(to,&"road")
	_command(service,2,"actor.navigate",{"id":spawn.data.id,"destination":{"x":goal.x,"y":goal.y,"z":goal.z}})
	for i in 4: service.step(.1,false)
	var record: Dictionary = service.actors._actors[spawn.data.id].record
	check(not record.get("mod_route",[]).is_empty(),"navigation planned a route")
	return record

## Parks the session car on `cell` in the lane a car travelling
## previous → cell → next uses (or the opposite lane).
func _park_on(record: Dictionary, previous: Vector2i, cell: Vector2i, next: Vector2i) -> void:
	var probe := record.duplicate()
	probe.cell = cell
	probe.previous = previous
	probe.next = next
	probe.t = .5
	var parked: CharacterBody3D = session.get("car")
	parked.global_transform = view.traffic.actor_pose(probe)
	parked.global_position += Vector3.UP*.002
	session._sync_traffic_collision()

func test_scripted_car_reroutes_around_a_parked_car() -> void:
	if not _setup(_grid_city()) or not await _enter(START): return
	session.set_physics_process(false)
	_clear_road()
	var service := _service()
	var record := _spawn_and_navigate(service,Vector2i(18,17),Vector2i(27,30))
	if record.is_empty(): return
	var route: Array = record.mod_route.duplicate()
	check(route.has(Vector2i(22,26)),"the shortest route runs down the x=22 street: "+str(route))
	if not route.has(Vector2i(22,26)): return
	_park_on(record,Vector2i(22,25),Vector2i(22,26),Vector2i(22,27))
	var visited := {}
	var stopped_for := 0.0
	for i in 600:
		service.step(.1,false)
		visited[record.cell] = true
		stopped_for = stopped_for+.1 if record.stopped and not record.mod_hold else 0.0
		check(stopped_for < 6.0 or i % 60 != 0,"the car does not sit waiting behind the parked car")
		if record.mod_hold: break
	check(not visited.has(Vector2i(22,26)),"the car never drives into the parked car's cell")
	check(record.mod_hold and record.cell == Vector2i(27,30),"the car reaches its destination another way: "+str(record.cell))
	check(not record.mod_route.has(Vector2i(22,26)),"the replanned route leaves the parked car's cell out")
	check(service.runtime.diagnostics.is_empty())
	service.leave("test")

func test_parked_car_in_the_opposite_lane_does_not_reroute() -> void:
	if not _setup(_grid_city()) or not await _enter(START): return
	session.set_physics_process(false)
	_clear_road()
	var service := _service()
	var record := _spawn_and_navigate(service,Vector2i(18,17),Vector2i(27,30))
	if record.is_empty(): return
	var route: Array = record.mod_route.duplicate()
	# Parked facing north on the x=22 street: the southbound lane stays clear.
	_park_on(record,Vector2i(22,27),Vector2i(22,26),Vector2i(22,25))
	var visited := {}
	for i in 600:
		service.step(.1,false)
		visited[record.cell] = true
		if record.mod_hold: break
	check(visited.has(Vector2i(22,26)),"the car drives past a car parked in the other lane")
	check_eq(record.mod_route,route,"no reroute for a clear lane")
	check(record.mod_hold and record.cell == Vector2i(27,30))
	service.leave("test")

func test_no_way_round_waits_then_continues() -> void:
	if not _setup(_street_city()) or not await _enter(Vector3(19.5,GROUND,20.5)): return
	session.set_physics_process(false)
	_clear_road()
	var service := _service()
	var record := _spawn_and_navigate(service,Vector2i(20,20),Vector2i(28,20))
	if record.is_empty(): return
	_park_on(record,Vector2i(24,20),Vector2i(25,20),Vector2i(26,20))
	for i in 80: service.step(.1,false)
	check(record.stopped and not record.mod_hold and not record.get("mod_failed",false),"with no way round the car stops short and keeps its route")
	var parked_x: float = (session.get("car") as CharacterBody3D).global_position.x
	check(view.traffic.actor_pose(record).origin.x < parked_x-.1,"it stopped short of the parked car, not through it")
	check(service.actors._actors.values()[0].has("navigation_command"),"navigation is still in progress, not failed")
	# The player drives off: the car carries on.
	var parked: CharacterBody3D = session.get("car")
	parked.global_position = ASIDE+Vector3(1.5,.1,0)
	session._sync_traffic_collision()
	for i in 200:
		service.step(.1,false)
		if record.mod_hold: break
	check(record.mod_hold and record.cell == Vector2i(28,20),"the car arrives once the road clears")
	service.leave("test")
