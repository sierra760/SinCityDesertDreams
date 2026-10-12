extends "res://tests/exploration/explore_session_case.gd"
const Service = preload("res://scripts/exploration/mods/explore_mod_service.gd")
const Progress = preload("res://scripts/exploration/mods/explore_mod_progress.gd")

func test_both_aircraft_follow_owned_waypoints_with_one_clock() -> void:
	if not _setup(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var service := Service.new()
	service.bind(session,[],Progress.new())
	service.enter()
	var sim := Simulation.new()
	sim.setup(city,123)
	var snapshot := sim.snapshot().duplicate(true)
	var before := SaveFormat.encode_city(city).duplicate(true)
	for kind in ["helicopter","plane"]:
		var spawn := service.api.apply({"owner":kind,"generation":service.generation,"request_id":1,"kind":"actor.spawn","args":{"kind":kind,"options":{"key":"air","position":{"x":22.5,"y":GROUND+2,"z":22.5}}}})
		check_eq(spawn.code,"ok",kind+" admits safe air waypoint")
		if spawn.code != "ok": continue
		var id: String = spawn.data.id
		var record: Dictionary = service.actors._actors[id].record
		service.api.apply({"owner":kind,"generation":service.generation,"request_id":2,"kind":"actor.navigate","args":{"id":id,"destination":{"x":25.5,"y":GROUND+2,"z":22.5}}})
		for i in 10: service.step(.1,false)
		var moving := service.actors.visual_states()[0].duplicate(true)
		check(moving.position.x > 22.5 and moving.position.x < 25.5,"bounded active-time motion")
		check(moving.airborne)
		view.traffic.advance(.1,true)
		check_eq(view.traffic.actor_pose(record).origin,moving.position,"city pause and reconciliation preserve owned aircraft")
		view.traffic._step(1.0)
		check_eq(view.traffic.actor_pose(record).origin,moving.position,"ambient clock cannot double step")
		service.step(10,true)
		check_eq(service.actors.visual_states()[0],moving,"Explore suspension freezes position and phase")
		for i in 30: service.step(.1,false)
		check(view.traffic.actor_pose(record).origin.is_equal_approx(Vector3(25.5,GROUND+2,22.5)))
		check(record.mod_hold)
		service.actors.clear_owner(kind)
	check_eq(SaveFormat.encode_city(city),before)
	check_eq(sim.snapshot(),snapshot,"sim and RNG unchanged")
	check(not CityTrafficCatalog.is_drivable(&"plane"))
	sim.free()
	service.leave("test")

func _service() -> ExploreModService:
	var result := Service.new()
	result.bind(session,[],Progress.new())
	result.enter()
	return result

func _command(service: ExploreModService, kind: String, args: Dictionary, request_id: int = 1, owner: String = "air") -> Dictionary:
	return {"owner":owner,"generation":service.generation,"request_id":request_id,"kind":kind,"args":args}

func _spawn_air(service: ExploreModService, position: Vector3 = Vector3(22.5,GROUND+2,22.5), key: String = "air", owner: String = "air") -> Dictionary:
	return service.api.apply(_command(service,"actor.spawn",{"kind":"helicopter","options":{"key":key,"position":ExploreWorldQueries.copied_point(position,0)}},1,owner))

func test_unsafe_bounded_and_obstructed_queries() -> void:
	if not _setup(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var service := _service()
	for point in [Vector3(-1,GROUND+2,22),Vector3(22,0,22),Vector3(22,100,22),Vector3(.1,GROUND+2,22)]:
		check_eq(_spawn_air(service,point).code,"no_route")
	var wall := StaticBody3D.new()
	wall.collision_layer = ExploreActorProfile.OBSTACLE
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.01,3,3)
	collision.shape = shape
	wall.add_child(collision)
	session.traversal.add_child(wall)
	wall.position = Vector3(24,GROUND+2,22.5)
	await physics_frame
	var origin := {"x":22.5,"y":GROUND+2,"z":22.5}
	for destination in [{"x":25.5,"y":GROUND+2,"z":22.5},{"x":100,"y":GROUND+2,"z":22.5},{"x":22.5,"y":100,"z":22.5}]:
		service.queries.request("air","world.route",{"from":origin,"destination":destination,"options":{"kind":"plane"}})
		var results := service.queries.step()
		check_eq(results.size(),1)
		check_eq(results[0].code,"no_route","full swept body rejects wall, length or ceiling")
		check(service.queries.nodes_visited_in_one_step <= 256)
	wall.free()
	await physics_frame
	service.queries.request("air","world.route",{"from":origin,"destination":{"x":25.5,"y":GROUND+2,"z":22.5},"options":{"kind":"plane"}})
	var result := service.queries.step()[0]
	check_eq(result.code,"ok","clear direct flight succeeds without road graph")
	check(result.data.x == 25.5 and not result.data.has("_air_destination"))
	service.leave("test")

class Recorder extends ExploreModRuntime:
	var events: Array[Dictionary] = []
	func deliver(_owner: String,event: Dictionary) -> void: events.append(event.duplicate(true))

func test_revision_cancels_wait_once_and_stale_callbacks_cannot_move() -> void:
	if not _setup(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var service := Service.new()
	var recorder := Recorder.new()
	service.runtime = recorder
	service.bind(session,[],Progress.new())
	service.enter()
	var spawn := _spawn_air(service)
	check_eq(spawn.code,"ok")
	if spawn.code != "ok": service.leave("test"); return
	var id: String = spawn.data.id
	var wrong := _command(service,"actor.remove",{"id":id},2,"other")
	check_eq(service.api.apply(wrong).code,"wrong_owner")
	wrong["generation"] -= 1
	check_eq(service.api.apply(wrong).code,"stale_generation")
	service.api.apply(_command(service,"actor.navigate",{"id":id,"destination":{"x":25,"y":GROUND+2,"z":22.5}},3))
	var pending := service.queries.step()[0]
	service.api.apply(_command(service,"actor.wait",{"id":id,"duration":.1},4))
	check(not service.actors.accept_query(pending),"replaced route callback is inert")
	session.traversal.revision += 1
	service.step(.1,false)
	service.step(1,false)
	check(service.actors.visual_states().is_empty())
	var cancelled := recorder.events.filter(func(event: Dictionary) -> bool: return event.request_id == 4)
	check_eq(cancelled.size(),1)
	check_eq(cancelled[0].code,"cancelled")
	check(not service.api._outstanding.air.has(4))
	check_eq(service.api.apply(_command(service,"actor.inspect",{"id":id})).code,"stale_id")
	service.leave("test")

func test_shared_caps_and_teardown() -> void:
	if not _setup(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var service := _service()
	for i in 64:
		var owner := "owner"+str(i/16)
		var spawn := _spawn_air(service,Vector3(18+(i%8)*2,GROUND+2,18+(i/8)*2),str(i),owner)
		check_eq(spawn.code,"ok","shared global air actor admission")
	check_eq(service.actors.visual_states().size(),64)
	check_eq(_spawn_air(service,Vector3(50,GROUND+2,50),"extra","other").code,"quota_exceeded")
	check_eq(_spawn_air(service,Vector3(50,GROUND+2,50),"extra","owner0").code,"quota_exceeded")
	service.leave("test")
	check(service.actors.visual_states().is_empty())
	check(view.traffic.actors.is_empty())
	service.enter()
	var spawn := _spawn_air(service)
	check_eq(spawn.code,"ok")
	if spawn.code == "ok":
		var record: Dictionary = service.actors._actors[spawn.data.id].record
		for i in 383:
			var copy := record.duplicate()
			copy.erase("mod_owner")
			copy["id"] = i+1000
			view.traffic.actors.append(copy)
		check_eq(_spawn_air(service,Vector3(50,GROUND+2,50),"extra","other").code,"quota_exceeded","384 ambient+owned vehicle budget")
		view.traffic.actors.clear()
	check_eq(CityTraffic3D.MAX_EXTERNAL,64)
	service.leave("test")

func test_segment_budget_water_column_and_stale_geometry() -> void:
	if not _setup(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var service := _service()
	var args := {"from":{"x":22.5,"y":GROUND+3,"z":22.5},"destination":{"x":86.5,"y":GROUND+3,"z":22.5},"options":{"kind":"helicopter"}}
	# Consume a candidate first, forcing the 256-segment aircraft route to defer.
	service.queries.request("first","world.route",{"from":args.from,"destination":args.from,"options":{"kind":"helicopter"}})
	service.queries.request("air","world.route",args)
	check_eq(service.queries.step().size(),1)
	check_eq(service.queries.nodes_visited_in_one_step,256)
	check_eq(service.queries.pending_count(),1)
	check_eq(service.queries.step()[0].code,"ok")
	check_eq(service.queries.nodes_visited_in_one_step,1)
	service.queries.request("air","world.route",args)
	session.traversal.revision += 1
	check_eq(service.queries.step()[0].code,"stale_geometry")
	# Water has no solid collider. Mid-route raised water must still block flight.
	session.traversal._water[Vector2i(24,22)] = [{"top":GROUND+4,"polygon":PackedVector2Array([Vector2(24,22),Vector2(25,22),Vector2(25,23),Vector2(24,23)])}]
	service.queries.request("air","world.route",args)
	check_eq(service.queries.step()[0].code,"no_route")
	service.leave("test")

func test_vertical_limit_and_aircraft_separation_fail_without_snapping() -> void:
	if not _setup(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var service := _service()
	var spawn := _spawn_air(service)
	check_eq(spawn.code,"ok")
	if spawn.code != "ok": service.leave("test"); return
	var id: String = spawn.data.id
	var record: Dictionary = service.actors._actors[id].record
	service.api.apply(_command(service,"actor.navigate",{"id":id,"destination":{"x":22.5,"y":GROUND+4,"z":22.5}},2))
	service.step(.1,false)
	check(view.traffic.actor_pose(record).origin.y <= GROUND+2.050001,"vertical speed at most .5 tile/second (8 m/s)")
	service.api.apply(_command(service,"actor.navigate",{"id":id,"destination":{"x":27.5,"y":GROUND+2.05,"z":22.5}},3))
	var other := _spawn_air(service,Vector3(25,GROUND+2.05,22.5),"other","other")
	check_eq(other.code,"ok")
	for i in 50: service.step(.1,false)
	check(record.mod_failed,"engine stops before another aircraft's conservative volume")
	check(record.air_position.x < 25,"failed route does not teleport past obstacle")
	check(record.stopped)
	service.leave("test")
