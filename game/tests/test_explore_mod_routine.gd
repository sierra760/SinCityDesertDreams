extends "res://tests/exploration/explore_session_case.gd"
const Service = preload("res://scripts/exploration/mods/explore_mod_service.gd")
const Progress = preload("res://scripts/exploration/mods/explore_mod_progress.gd")
const Queries = preload("res://scripts/exploration/mods/explore_world_queries.gd")

func _street() -> bool:
	var value := flat_city()
	for x in range(18,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	return _setup(value)

func test_city_pause_does_not_pause_owned_routine() -> void:
	if not _street(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var sim := Simulation.new()
	sim.setup(city,123)
	var sim_before := sim.snapshot().duplicate(true)
	var before := SaveFormat.encode_city(city).duplicate(true)
	var service := Service.new()
	service.bind(session, [], Progress.new())
	service.enter()
	var command := {"owner":"test", "generation":service.generation,"request_id":1,"kind":"actor.spawn","args":{"kind":"pedestrian","options":{"key":"walker","position":{"x":22.5,"y":GROUND,"z":20.5}}}}
	var spawned: Dictionary = service.api.apply(command)
	check_eq(spawned.code,"ok")
	if spawned.code != "ok": service.leave("test"); sim.free(); return
	var id: String = spawned.data.id
	var start: Vector3 = service.actors.visual_states()[0].position
	command["kind"] = "actor.navigate"
	command["args"] = {"id":id,"destination":{"x":25.5,"y":GROUND,"z":20.5}}
	service.api.apply(command)
	for i in 30: service.step(.1,false)
	check(service.actors.visual_states()[0].position != start,"city pause does not stop owned actor")
	check_eq(SaveFormat.encode_city(city),before,"all copied city layers unchanged")
	check_eq(sim.snapshot(),sim_before,"simulation, clock, treasury and RNG unchanged")
	sim.free()
	var frozen := service.actors.visual_states().duplicate(true)
	for i in 10: service.step(.1,true)
	check_eq(service.actors.visual_states(),frozen,"Explore suspension freezes movement and gait")
	command["owner"] = "other"
	check_eq(service.api.apply(command).code,"wrong_owner")
	command["owner"] = "test"
	command["generation"] = -1
	check_eq(service.api.apply(command).code,"stale_generation")
	service.leave("test")
	check(service.actors.visual_states().is_empty())

func test_actual_stroll_ticks_and_timer_freeze() -> void:
	if not _street(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var pack := ExploreModPack.read("res://explore_mods/desert_stroll")
	check(pack.ok,"actual Pedestrians pack validates")
	if not pack.ok: return
	var progress := Progress.new()
	var service := Service.new()
	service.bind(session,[pack],progress)
	service.enter()
	for i in 30: service.step(.1,false)
	check_eq(service.runtime.tick_count,30)
	check_eq(service.actors.visual_states().size(),1,"actual Lua routine spawns a walker; runtime diagnostics="+str(service.runtime.diagnostics))
	var ticks: int = service.runtime.tick_count
	for i in 20: service.step(.1,true)
	check_eq(service.runtime.tick_count,ticks)
	service.leave("test")

func test_pending_query_is_bounded_and_disconnect_is_safe() -> void:
	var graph := CityTrafficGraph.new()
	var value := flat_city()
	for y in range(1,90):
		for x in range(1,90): value.building.put(x,y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,15))
	graph.bind_city(value)
	var queries := Queries.new()
	queries.bind(graph,null)
	var result := queries.request("test","world.route",{"from":{"x":1.5,"y":GROUND,"z":1.5},"destination":{"x":88.5,"y":GROUND,"z":88.5}})
	check_eq(result.code,"pending")
	check(queries.step().is_empty(),"long query stays pending until a later step")
	check_eq(queries.nodes_visited_in_one_step,256)
	for i in 20: queries.step()
	check(queries.pending_count() == 0,"query exhausts bounded total work")

func test_road_vehicle_uses_engine_route_and_single_clock() -> void:
	if not _street(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var service := Service.new()
	service.bind(session,[],Progress.new())
	service.enter()
	var command := {"owner":"vehicle","generation":service.generation,"request_id":1,"kind":"actor.spawn","args":{"kind":"car","options":{"key":"car","position":{"x":22.5,"y":GROUND,"z":20.5}}}}
	var result := service.api.apply(command)
	check_eq(result.code,"ok")
	if result.code != "ok": service.leave("test"); return
	var id: String = result.data.id
	var actor: Dictionary = service.actors._actors[id].record
	var start: Transform3D = view.traffic.actor_pose(actor)
	command["kind"] = "actor.navigate"
	command["args"] = {"id":id,"destination":{"x":25.5,"y":GROUND,"z":20.5}}
	service.api.apply(command)
	for i in 40: service.step(.1,false)
	check(view.traffic.actor_pose(actor).origin != start.origin)
	var t: float = actor.t
	view.traffic._step(1.0)
	check_eq(actor.t,t,"ambient clock never double steps mod actors")
	check(actor.mod_hold,"navigation reaches a bounded destination and stops")
	check_eq(actor.cell,Vector2i(25,20))
	service.leave("test")

func test_runtime_ticks_progress_timer_and_copy_bounds() -> void:
	var progress := Progress.new()
	var pack := ExploreModPack._snapshot({"manifest.json":'{"id":"clock","name":"Clock","version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"}'.to_utf8_buffer(),"main.lua":'return {on_tick=function(api) api.state.set("ticks",api.state.get("ticks",0)+1) end}'.to_utf8_buffer()})
	var runtime := ExploreModRuntime.new()
	runtime.bind([pack],progress,17)
	for i in 60: runtime.step(1.0/60.0,false,{})
	check_eq(progress.get_state("clock",1).data.get("ticks"),10,"Lua handler runs ten times per active second")
	runtime.step(10,true,{})
	check_eq(progress.get_state("clock",1).data.get("ticks"),10)
	var copied := progress.snapshot()
	copied.mods.clock.data["ticks"] = -100
	check_eq(progress.get_state("clock",1).data.ticks,10)
	check_eq(progress.commit("clock",2,"1.0.0",{}).code,"state_version_mismatch")
	check_eq(progress.commit("clock",1,"1.0.0",{"bad":Vector3.ZERO}).code,"invalid_progress")
	runtime.stop("test")

func test_disconnected_height_and_revision_fail_safely() -> void:
	if not _street(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var queries := Queries.new()
	queries.bind(view.traffic.graph,session.traversal)
	for destination in [{"x":40.5,"y":GROUND,"z":40.5},{"x":24.5,"y":GROUND+2,"z":20.5}]:
		var pending := queries.request("test","world.route",{"from":{"x":22.5,"y":GROUND,"z":20.5},"destination":destination})
		check_eq(pending.code,"pending")
		var completed := queries.step()
		check_eq(completed.size(),1)
		check_eq(completed[0].code,"no_route")
	queries.request("test","world.route",{"from":{"x":22.5,"y":GROUND,"z":20.5},"destination":{"x":24.5,"y":GROUND,"z":20.5}})
	view.traffic.graph.revision += 1
	check_eq(queries.step()[0].code,"stale_geometry")
	var retry := queries.request("test","world.route",{"from":{"x":22.5,"y":GROUND,"z":20.5},"destination":{"x":24.5,"y":GROUND,"z":20.5}})
	check_eq(retry.code,"pending","stale completion must not poison the new graph's cache")
	if retry.code == "pending": check_eq(queries.step()[0].code,"ok")

func test_actual_stroll_finishes_wait_and_safe_wave() -> void:
	if not _street(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var progress := Progress.new()
	var service := Service.new()
	service.bind(session,[ExploreModPack.read("res://explore_mods/desert_stroll")],progress)
	service.enter()
	for i in 900: service.step(.1,false)
	check_eq(progress.get_state("desert_stroll",1).data.get("strolls",0),3,"all three actual routines complete route and active-time wait")
	check_eq(service.actors.visual_states().size(),3,"completed waves preserve all three routine actors")
	check(service.runtime.diagnostics.is_empty(),"native runtime remains healthy: "+str(service.runtime.diagnostics))
	service.leave("test")

func test_shared_actor_capacity_and_timer_freeze() -> void:
	if not _street(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var service := Service.new()
	service.bind(session,[],Progress.new())
	service.enter()
	var timer := {"owner":"test","generation":service.generation,"request_id":3,"kind":"timer.after","args":{"key":"rest","delay":1.0}}
	check_eq(service.api.apply(timer).code,"ok")
	service.step(.5,false)
	var left: float = service.api._timers.test.rest.left
	service.step(20,true)
	check_eq(service.api._timers.test.rest.left,left)
	service.step(.6,false)
	check(service.api._timers.test.is_empty())
	var prototype := view.traffic.owned_spawn("ambient_fixture",&"pedestrian",Vector2i(22,20),0)
	check(not prototype.is_empty())
	if prototype.is_empty(): service.leave("test"); return
	prototype.erase("mod_owner")
	view.traffic.actors.clear()
	for i in CityTraffic3D.MAX_PEDESTRIANS:
		var actor := prototype.duplicate(true)
		actor["id"] = i+1000
		actor["cell"] = Vector2i(18,20)
		view.traffic.actors.append(actor)
	check(view.traffic.owned_spawn("test",&"pedestrian",Vector2i(24,20),0).is_empty(),"script and ambient walkers share 512 cap")
	for actor in view.traffic.actors:
		actor["kind"] = &"car"
		actor["type"] = &"road"
	view.traffic.actors.resize(CityTraffic3D.MAX_VEHICLES)
	check(view.traffic.owned_spawn("test",&"car",Vector2i(24,20),0).is_empty(),"script and ambient vehicles share 384 cap")
	view.traffic.actors.clear()
	service.leave("test")

func test_controller_lifecycle_is_dormant_then_cleans_generation() -> void:
	if not _street(): return
	if not await _enter(): return
	check(session.mod_service == null,"no packs means ordinary Explore stays dormant")
	session.leave()
	session.mod_packs.assign([ExploreModPack.read("res://explore_mods/desert_stroll")])
	if not await _enter(): return
	session.set_physics_process(false)
	var service: ExploreModService = session.mod_service
	for i in 10: service.step(.1,false)
	check_eq(service.actors.visual_states().size(),1,"lifecycle actor admission; native diagnostics="+str(service.runtime.diagnostics)+"; actor records="+str(service.actors._actors)+"; pending="+str(service.api._pending))
	var generation: int = service.generation
	session.leave()
	check(service.actors.visual_states().is_empty())
	check_eq(view.traffic.actors.size(),0)
	if not await _enter(): return
	check(session.mod_service.generation > generation,"reentry cannot reuse stale handles")

func test_existing_rail_water_domains_and_reservations() -> void:
	for kind: StringName in [&"train",&"sailboat"]:
		var value := flat_city()
		for x in range(18,30):
			if kind == &"sailboat": value.terrain.put(x,20,Terrain.SURFACE)
			else: value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
		var traffic := CityTraffic3D.new()
		traffic.bind_city(value)
		var queries := Queries.new()
		queries.bind(traffic.graph,null)
		var registry := ExploreActorRegistry.new()
		registry.bind(null,traffic,91)
		registry.queries = queries
		var domain := CityTrafficCatalog.domain(kind)
		var position := queries.copied_point(traffic.graph.point(Vector2i(22,20),domain),traffic.graph.revision)
		var command := {"owner":"domain","generation":91,"request_id":1,"kind":"actor.spawn","args":{"kind":String(kind),"options":{"key":"vehicle","position":position}}}
		var spawn := registry.apply(command)
		check_eq(spawn.code,"ok",String(kind)+" uses existing domain")
		if spawn.code == "ok":
			var actor: Dictionary = registry._actors[spawn.data.id].record
			command["kind"] = "actor.navigate"
			command["args"] = {"id":spawn.data.id,"destination":queries.copied_point(traffic.graph.point(Vector2i(25,20),domain),traffic.graph.revision)}
			registry.apply(command)
			for result in queries.step(): registry.accept_query(result)
			for i in 100: registry.step(.1)
			check_eq(actor.cell,Vector2i(25,20))
			check(actor.mod_hold)
		registry.clear_owner("domain")
		if kind == &"train":
			traffic.set_reserved_rail_cells([Vector2i(22,20)])
			check(traffic.owned_spawn("domain",kind,Vector2i(22,20),0).is_empty(),"passenger reservations forbid owned admission")
		traffic.free()

func test_landmarks_cached_replies_and_owner_disable() -> void:
	if not _street(): return
	city.building.put(24,21,Buildings.SMALL_PARK)
	view.traffic.graph.refresh()
	if not await _enter(): return
	session.set_physics_process(false)
	var service := Service.new()
	service.bind(session,[ExploreModPack.read("res://explore_mods/desert_stroll")],Progress.new())
	service.enter()
	var request := service.queries.request("landmark","world.find_landmark",{"kind":"park"})
	check_eq(request.code,"pending")
	var completed := service.queries.step()
	check_eq(completed.size(),1)
	check_eq(completed[0].code,"ok")
	check_eq(completed[0].data.x,24.5,"park result is a reachable outdoor approach")
	check_eq(service.queries.request("landmark","world.find_landmark",{"kind":"park"}).code,"ok","cached result returns immediately")
	for i in 10: service.step(.1,false)
	service.disable("desert_stroll")
	check(service.actors.visual_states().is_empty())
	check(service.api._timers.is_empty())
	check(service.runtime.step(1.0,false,{}).is_empty())
	service.leave("test")

func test_implicit_landmarks_follow_player_and_recover_after_no_route() -> void:
	var value := flat_city()
	for x in range(10,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	var graph := CityTrafficGraph.new()
	graph.bind_city(value)
	var queries := Queries.new()
	queries.bind(graph,null)
	queries.player = {"x":12.5,"y":GROUND,"z":20.5}
	var args := {"kind":"road_destination"}
	check_eq(queries.request("moving","world.find_landmark",args).code,"pending")
	check_eq(queries.step()[0].data.x,15.5)
	check_eq(queries.request("moving","world.find_landmark",args).data.x,15.5,"unchanged origin reuses the bounded cache")
	queries.player.x = 25.5
	var moved := queries.request("moving","world.find_landmark",args)
	check_eq(moved.code,"pending","a moved player needs a search from the new origin")
	if moved.code == "pending": check_eq(queries.step()[0].data.x,28.5)
	queries.player.x = 5.5
	queries.request("retry","world.find_landmark",args)
	check_eq(queries.step()[0].code,"no_route")
	queries.player.x = 20.5
	var retry := queries.request("retry","world.find_landmark",args)
	check_eq(retry.code,"pending","moving onto a road retries an earlier missing route")
	if retry.code == "pending": check_eq(queries.step()[0].code,"ok")
	queries.player.x = 12.999999
	queries.request("boundary","world.find_landmark",args)
	check_eq(queries.step()[0].data.x,15.5)
	queries.player.x = 13.000001
	var crossed := queries.request("boundary","world.find_landmark",args)
	check_eq(crossed.code,"pending","rounded display coordinates cannot alias opposite sides of a cell boundary")
	if crossed.code == "pending": check_eq(queries.step()[0].data.x,16.5)

func test_explicit_landmark_origin_stays_cached_when_player_moves() -> void:
	var value := flat_city()
	for x in range(10,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	var graph := CityTrafficGraph.new()
	graph.bind_city(value)
	var queries := Queries.new()
	queries.bind(graph,null)
	queries.player = {"x":12.5,"y":GROUND,"z":20.5}
	var args := {"kind":"road_destination","options":{"from":{"x":20.5,"y":GROUND,"z":20.5}}}
	queries.request("fixed","world.find_landmark",args)
	check_eq(queries.step()[0].data.x,23.5)
	queries.player.x = 25.5
	var cached := queries.request("fixed","world.find_landmark",args)
	check_eq(cached.code,"ok","explicit from is independent of the player")
	check_eq(cached.data.x,23.5)
	for x in range(10,30): value.building.put(x,20,0)
	graph.refresh()
	check_eq(queries.request("fixed","world.find_landmark",args).code,"pending","geometry edits invalidate even explicit-origin cache")
	check_eq(queries.step()[0].code,"no_route")

func test_actual_stroll_destinations_stay_at_origin_after_player_moves() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var progress := Progress.new()
	var service := Service.new()
	service.bind(session,[ExploreModPack.read("res://explore_mods/desert_stroll")],progress)
	service.enter()
	for i in 20: service.step(.1,false)
	session.pedestrian.place(Transform3D(Basis.IDENTITY,Vector3(18.5,GROUND,20.5)))
	for i in 900: service.step(.1,false)
	check_eq(progress.get_state("desert_stroll",1).data.get("strolls",0),3,"moving the player cannot send followers ahead of the leader")
	var stops := {}
	for actor: Dictionary in service.actors._actors.values(): stops[actor.key] = actor.record.cell
	check_eq(stops.get("stroller1"),Vector2i(25,20))
	check_eq(stops.get("stroller2"),Vector2i(24,20))
	check_eq(stops.get("stroller3"),Vector2i(23,20))
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")

func test_actual_stroll_origin_failure_preserves_three_safe_greetings() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var progress := Progress.new()
	var service := Service.new()
	service.bind(session,[ExploreModPack.read("res://explore_mods/desert_stroll")],progress)
	service.enter()
	service.step(.1,false)
	view.traffic.graph.revision += 1
	for i in 900: service.step(.1,false)
	check(service.runtime.has_owner("desert_stroll"),"failed initial origin leaves a healthy pack")
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	check_eq(service.actors.visual_states().size(),3,"all three safe waiting walkers still arrive after origin failure")
	check_eq(service.api.interactions._owned.get("desert_stroll",{}).size(),3,"all waiting walkers retain their greetings")
	check_eq(progress.get_state("desert_stroll",1).data.get("strolls",0),0,"failed origin must not award completed walks")
	var exclusions: Array[RID] = []
	for actor: Dictionary in service.actors._actors.values():
		check(actor.record.mod_hold,"origin failure never starts unsupported navigation")
		check(actor.record.get("mod_route",[]).is_empty())
		var feet := view.traffic.actor_pose(actor.record).origin
		check(not session.traversal.support_near(feet,.06,.06,exclusions).is_empty(),"waiting actors stay physically supported")
	check_eq(service.queries.pending_count(),0)
	check_eq(service.api.resource_metrics().queries,0)
	check_eq(service.runtime.metrics().pending_transactions,0)
	service.leave("test")

func test_landmark_cache_tracks_park_creation_and_removal_without_graph_revision() -> void:
	var value := flat_city()
	for x in range(10,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	var graph := CityTrafficGraph.new()
	graph.bind_city(value)
	var queries := Queries.new()
	queries.bind(graph,null)
	var args := {"kind":"park","options":{"from":{"x":12.5,"y":GROUND,"z":20.5}}}
	queries.request("park","world.find_landmark",args)
	check_eq(queries.step()[0].code,"no_route")
	var revision := graph.revision
	value.building.put(15,21,Buildings.SMALL_PARK)
	graph.refresh()
	check_eq(graph.revision,revision,"park land use leaves traffic topology unchanged")
	var added := queries.request("park","world.find_landmark",args)
	check_eq(added.code,"pending","park creation retries cached missing landmarks")
	if added.code == "pending": check_eq(queries.step()[0].data.x,15.5)
	check_eq(queries.request("park","world.find_landmark",args).code,"ok","unchanged explicit origin remains memoized")
	value.building.put(15,21,0)
	graph.refresh()
	var removed := queries.request("park","world.find_landmark",args)
	check_eq(removed.code,"pending","park removal discards its cached approach")
	if removed.code == "pending": check_eq(queries.step()[0].code,"no_route")

func test_rail_query_cache_and_queued_routes_track_reservation_changes() -> void:
	var value := flat_city()
	for x in range(10,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
	var graph := CityTrafficGraph.new()
	graph.bind_city(value)
	var queries := Queries.new()
	queries.bind(graph,null)
	var args := {"from":Queries.copied_point(graph.point(Vector2i(12,20),&"rail"),graph.revision),"destination":Queries.copied_point(graph.point(Vector2i(16,20),&"rail"),graph.revision),"options":{"kind":"train"}}
	queries.reserved_rail = {Vector2i(12,20):true}
	queries.request("rail","world.route",args)
	check_eq(queries.step()[0].code,"no_route")
	queries.reserved_rail.clear()
	var opened := queries.request("rail","world.route",args)
	check_eq(opened.code,"pending","released rail reservations retry missing routes")
	if opened.code == "pending": check_eq(queries.step()[0].code,"ok")
	queries.reserved_rail[Vector2i(14,20)] = true
	var blocked := queries.request("rail","world.route",args)
	check_eq(blocked.code,"pending","new rail reservations discard cached success")
	if blocked.code == "pending": check_eq(queries.step()[0].code,"no_route")
	queries.reserved_rail.clear()
	queries.request("queued","world.route",args)
	queries.reserved_rail[Vector2i(14,20)] = true
	check_eq(queries.step()[0].code,"stale_geometry","queued routes cannot straddle reservation versions")

func test_queued_road_route_survives_unrelated_landmark_and_rail_changes() -> void:
	var value := flat_city()
	for x in range(10,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	var graph := CityTrafficGraph.new()
	graph.bind_city(value)
	var queries := Queries.new()
	queries.bind(graph,null)
	var args := {"from":{"x":12.5,"y":GROUND,"z":20.5},"destination":{"x":16.5,"y":GROUND,"z":20.5}}
	queries.request("walking","world.route",args)
	value.building.put(15,21,Buildings.SMALL_PARK)
	graph.refresh()
	queries.reserved_rail[Vector2i(50,50)] = true
	var result := queries.step()[0]
	check_eq(result.code,"ok","ordinary construction and rail reservations cannot cancel an unrelated walk")
	check_eq(result.data.x,16.5)

func test_ground_query_cache_and_pending_jobs_track_physical_rebuilds() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var queries := Queries.new()
	queries.bind(view.traffic.graph,session.traversal)
	var args := {"from":{"x":22.5,"y":GROUND,"z":20.5},"destination":{"x":25.5,"y":GROUND,"z":20.5}}
	queries.request("cached","world.route",args)
	check_eq(queries.step()[0].code,"ok")
	queries.request("queued","world.route",args)
	var empty_chunks: Array[Dictionary] = []
	session.traversal.rebuild(city,empty_chunks,{},session.traversal.revision+1)
	await physics_frame
	check_eq(queries.step()[0].code,"stale_geometry","pending ground route refuses stale physical support")
	var lost := queries.request("cached","world.route",args)
	check_eq(lost.code,"pending","physical rebuild drops cached supported route")
	if lost.code == "pending": check_eq(queries.step()[0].code,"no_route")

func test_service_invalidates_native_queries_for_all_host_dependencies() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var source := "return {on_tick=function(api) api.utility.log(api.world.find_landmark('park',{from={x=22.5,y="+str(GROUND)+",z=20.5}}).code) end}"
	var pack := ExploreModPack._snapshot({"manifest.json":'{"id":"dependency","name":"Dependency","version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"}'.to_utf8_buffer(),"main.lua":source.to_utf8_buffer()})
	var service := Service.new()
	service.bind(session,[pack],Progress.new())
	service.enter()
	var args: Array = ["park",{"from":{"x":22.5,"y":GROUND,"z":20.5}}]
	for dependency in ["buildings","rail","traversal"]:
		service.runtime.cache_query("dependency","world.find_landmark",args,{"ok":false,"code":"no_route"})
		service._update_context()
		var unchanged: Dictionary = service.runtime._sessions.dependency.vm.dispatch("on_tick",{},service.runtime._context("dependency",{}),{})
		check_eq(unchanged.logs,["no_route"],"unchanged host dependencies preserve explicit-from native memoization")
		if dependency == "buildings":
			city.building.put(24,21,Buildings.SMALL_PARK)
			view.traffic.graph.refresh()
		elif dependency == "rail": view.traffic.set_reserved_rail_cells([Vector2i(24,20)])
		else: session.traversal.rebuild(city,view.sample_chunks,view.sample_networks,session.traversal.revision+1)
		service._update_context()
		var changed: Dictionary = service.runtime._sessions.dependency.vm.dispatch("on_tick",{},service.runtime._context("dependency",{}),{})
		check_eq(changed.logs,["pending"],dependency+" change forces native lookup through current host")
		check_eq(changed.commands.size(),1)
	service.leave("test")

func test_fault_drops_commands_from_earlier_callback_in_same_step() -> void:
	var pack := ExploreModPack._snapshot({"manifest.json":'{"id":"fault","name":"Fault","version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"}'.to_utf8_buffer(),"main.lua":'local ticks=0 return {on_event=function(api) ticks=ticks+1 if ticks==1 then api.timer.after("later",1) else error("stop") end end}'.to_utf8_buffer()})
	var runtime := ExploreModRuntime.new()
	runtime.bind([pack],Progress.new(),1)
	runtime.deliver("fault",{"kind":"first"})
	runtime.deliver("fault",{"kind":"second"})
	check(runtime.step(.1,false,{}).is_empty(),"fault cannot recreate resources after owner cleanup")
	check(runtime._sessions.is_empty())
	runtime.stop("test")

func test_malformed_script_arguments_are_deferred_failures() -> void:
	var api := ExploreModApi.new()
	api.generation = 3
	for bad in [
		{"kind":"actor.spawn","args":{"kind":{},"options":{}}},
		{"kind":"actor.spawn","args":{"kind":"pedestrian","options":"bad"}},
		{"kind":"actor.navigate","args":{"id":12,"destination":{}}},
		{"kind":"actor.wait","args":{"id":"x","duration":{}}},
		{"kind":"actor.inspect","args":{"id":[]}},
		{"kind":"world.nearby","args":{"options":{"radius":{}}}},
		{"kind":"world.find_landmark","args":{"kind":[]}},
		{"kind":"world.route","args":{"from":{},"destination":{}}},
		{"kind":"timer.cancel","args":{"key":{}}}]:
		bad["owner"] = "malformed"
		bad["generation"] = 3
		bad["request_id"] = 1
		check_eq(api.apply(bad).code,"invalid_argument","untrusted argument types never reach engine adapters")

func test_nearby_scans_candidates_in_bounded_steps_before_truncating() -> void:
	if not _street(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var service := Service.new()
	service.bind(session,[],Progress.new())
	service.enter()
	var prototype := view.traffic.owned_spawn("test",&"pedestrian",Vector2i(22,20),0)
	prototype.erase("mod_owner")
	view.traffic.actors.clear()
	for i in 300:
		var actor := prototype.duplicate(true)
		actor["id"] = i+1000
		actor["cell"] = Vector2i(28,20) if i < 290 else Vector2i(22,20)
		actor["previous"] = actor.cell-Vector2i.RIGHT
		actor["next"] = actor.cell+Vector2i.RIGHT
		view.traffic.actors.append(actor)
	check_eq(service.queries.request("test","world.nearby",{"options":{"radius":2.0}}).code,"pending")
	check(service.queries.step().is_empty(),"nearby cannot inspect 300 records in one step")
	check_eq(service.queries.nodes_visited_in_one_step,256)
	var finished := service.queries.step()
	check_eq(finished.size(),1)
	check_eq(finished[0].data.size(),10,"nearby candidates late in ambient ordering are retained")
	view.traffic.actors.clear()
	service.leave("test")

func test_committed_nested_progress_does_not_alias_incoming_writes() -> void:
	var progress := Progress.new()
	var incoming := {"nested":{"list":[{"value":"accepted"}]}}
	check_eq(progress.commit("copied",1,"1.0.0",incoming).code,"ok")
	var accepted := progress.snapshot()
	incoming.nested.list[0]["value"] = "changed outside commit"
	incoming.nested.list.append(Vector3.ONE)
	incoming.nested["oversized"] = "x".repeat(65537)
	check(progress.snapshot() == accepted,"caller mutations cannot bypass progress validation")
	check(Progress._valid(progress.snapshot()),"stored progress stays valid after caller inserts forbidden values")
	check_eq(progress.get_state("copied",1).data.nested.list.size(),1)

class CompletionRecorder extends ExploreModRuntime:
	var received: Array[Dictionary] = []
	func deliver(_owner: String, event: Dictionary) -> void:
		received.append(event.duplicate(true))

func test_geometry_removal_cancels_pending_wait_once_and_releases_slot() -> void:
	await _removed_wait_case(30.0,false)

func test_missing_actor_cancels_wait_even_when_deadline_is_this_step() -> void:
	await _removed_wait_case(.1,true)

func _removed_wait_case(duration: float, erase_record: bool) -> void:
	if not _street(): return
	if not await _enter(): return
	session.set_physics_process(false)
	var service := Service.new()
	var recorder := CompletionRecorder.new()
	service.runtime = recorder
	service.bind(session,[],Progress.new())
	service.enter()
	var spawn := service.api.apply({"owner":"waiting","generation":service.generation,"request_id":1,"kind":"actor.spawn","args":{"kind":"pedestrian","options":{"key":"waiting","position":{"x":22.5,"y":GROUND,"z":20.5}}}})
	check_eq(spawn.code,"ok")
	if spawn.code != "ok": service.leave("test"); return
	var command := {"owner":"waiting","generation":service.generation,"request_id":2,"kind":"actor.wait","args":{"id":spawn.data.id,"duration":duration}}
	check(service.api.apply(command).is_empty(),"wait remains deferred")
	check(service.api._outstanding.waiting.has(2))
	if erase_record:
		view.traffic.actors.erase(service.actors._actors[spawn.data.id].record)
	else:
		city.building.put(22,20,0)
		view.traffic.graph.refresh()
	service.step(.1,false)
	var completed := recorder.received.filter(func(event: Dictionary) -> bool: return event.request_id == 2)
	check_eq(completed.size(),1,"geometry removal completes the original wait exactly once")
	if not completed.is_empty():
		check_eq(completed[0].kind,"action_failed")
		check_eq(completed[0].code,"cancelled")
	check(not service.api._outstanding.waiting.has(2),"matching cancellation releases the outstanding slot")
	check(service.actors.visual_states().is_empty())
	service.step(31.0,false)
	completed = recorder.received.filter(func(event: Dictionary) -> bool: return event.request_id == 2)
	check_eq(completed.size(),1,"removed actor cannot later report wait success")
	service.leave("test")

class DeferredBridge extends ExploreLuaBridge:
	var calls: Array[String] = []
	var completed: Array[String] = []
	var defer := {"on_start":false,"on_event":true,"on_resume":true,"on_tick":true}
	var closed := false
	var inventory: Array = ["on_start","on_event","on_resume","on_tick"]
	func start(_source: String,_modules: Dictionary,_context: Dictionary,_seed: int) -> Dictionary:
		return {"ok":true,"handlers":inventory.duplicate(),"commands":[],"progress_writes":{},"logs":[]}
	func dispatch(handler: String,_payload: Dictionary,_context: Dictionary,_budget: Dictionary) -> Dictionary:
		calls.append(handler)
		var reply := {"ok":true,"commands":[],"progress_writes":{},"logs":[],"instructions":0}
		if defer.get(handler,false):
			defer[handler] = false
			reply["deferred"] = true
		else: completed.append(handler)
		return reply
	func close() -> void: closed = true

class DeferredRuntime extends ExploreModRuntime:
	var bridge := DeferredBridge.new()
	func _create_vm() -> ExploreLuaBridge: return bridge

func _deferred_pack() -> Dictionary:
	return ExploreModPack._snapshot({"manifest.json":'{"id":"deferred","name":"Deferred","version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"}'.to_utf8_buffer(),"main.lua":'return {}'.to_utf8_buffer()})

func test_deferred_callbacks_remain_queued_across_active_ticks_and_suspension() -> void:
	var runtime := DeferredRuntime.new()
	runtime.bind([_deferred_pack()],Progress.new(),1)
	check_eq(runtime.bridge.calls,["on_start"])
	check_eq(runtime.bridge.completed,["on_start"])
	runtime.deliver("deferred",{"kind":"timer","key":"once"})
	runtime.step(1.0,true,{})
	check_eq(runtime.bridge.calls,["on_start"],"suspension invokes no pending callback")
	for i in 5: runtime.step(.1,false,{})
	check_eq(runtime.bridge.completed.count("on_start"),1)
	check_eq(runtime.bridge.completed.count("on_resume"),1)
	check_eq(runtime.bridge.completed.count("on_event"),1)
	check(runtime.bridge.completed.count("on_tick") >= 1,"deferred tick eventually runs")
	check(runtime._sessions.deferred.events.is_empty())
	check(runtime.diagnostics.is_empty())
	runtime.stop("test")
	check(runtime.bridge.closed,"absent on_stop still closes VM")
	check(not runtime.bridge.calls.has("on_stop"),"absent callbacks never dispatch")

func test_absent_callbacks_are_never_dispatched() -> void:
	var runtime := DeferredRuntime.new()
	runtime.bridge.inventory = []
	runtime.bind([_deferred_pack()],Progress.new(),1)
	runtime.deliver("deferred",{"kind":"timer"})
	runtime.step(.1,true,{})
	runtime.step(.1,false,{})
	runtime.stop("test")
	check_eq(runtime.bridge.calls,[])
	check(runtime.bridge.closed)

func test_stop_always_closes_even_if_bridge_defers() -> void:
	var runtime := DeferredRuntime.new()
	runtime.bridge.inventory = ["on_stop"]
	runtime.bridge.defer["on_stop"] = true
	runtime.bind([_deferred_pack()],Progress.new(),1)
	runtime.stop("test")
	check_eq(runtime.bridge.calls,["on_stop"])
	check(runtime.bridge.closed)
	check(runtime._sessions.is_empty())

func test_host_invalid_33_fault_discards_later_commands_in_same_batch() -> void:
	await _invalid_progress_case(false)

func test_mixed_native_host_33_discards_only_unaccepted_progress() -> void:
	await _invalid_progress_case(true)

func _invalid_progress_case(mixed: bool) -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var first_count := 31 if mixed else 32
	var native_bad := "api.timer.after('native_bad',0); " if mixed else ""
	var source := "local ticks=0 return {on_tick=function(api) ticks=ticks+1 if ticks==1 then api.state.set('prior','accepted'); for i=1,"+str(first_count)+" do api.actor.spawn('forged',{key='bad'}) end elseif ticks==2 then api.state.set('unsafe',true); api.state.set('prior','corrupted'); "+native_bad+"api.actor.spawn('forged',{key='bad'}); api.actor.spawn('pedestrian',{key='late',near_player=true}) end end}"
	var pack := ExploreModPack._snapshot({"manifest.json":'{"id":"invalid_host","name":"Invalid host","version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"}'.to_utf8_buffer(),"main.lua":source.to_utf8_buffer()})
	var service := ExploreModService.new()
	var progress := Progress.new()
	service.bind(session,[pack],progress)
	service.enter()
	service.step(.1,false)
	check_eq(progress.get_state("invalid_host",1).data.get("prior"),"accepted")
	check(service.runtime._sessions.has("invalid_host"),"32 semantic invalid calls remain enabled")
	service.step(.1,false)
	check(service.runtime._sessions.is_empty(),"33rd host rejection faults")
	check(service.actors._actors.is_empty(),"later command from faulted batch cannot recreate actor")
	check_eq(progress.get_state("invalid_host",1).data.get("prior"),"accepted","previous accepted callback survives")
	check(not progress.get_state("invalid_host",1).data.has("unsafe"),"faulting callback progress discarded")
	check(service.api._timers.is_empty())
	service.leave("test")

func test_actual_foreign_handle_misuse_is_logged_and_faults_at_33() -> void:
	await _foreign_handle_case(false)

func test_mixed_native_foreign_handle_misuse_shares_active_window() -> void:
	await _foreign_handle_case(true)

func _foreign_handle_case(mixed: bool) -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var service := ExploreModService.new()
	service.bind(session,[],Progress.new())
	service.enter()
	var owned := service.api.apply({"owner":"victim","generation":service.generation,"request_id":1,"kind":"actor.spawn","args":{"kind":"pedestrian","options":{"key":"victim","position":{"x":22.5,"y":GROUND,"z":20.5}}}})
	check_eq(owned.code,"ok")
	if owned.code != "ok": service.leave("test"); return
	var count := 31 if mixed else 32
	var last := "api.timer.after('bad',0); api.actor.inspect('"+String(owned.data.id)+"')" if mixed else "api.actor.remove('"+String(owned.data.id)+"')"
	var source := "local ticks=0 return {on_tick=function(api) ticks=ticks+1 if ticks==1 then for i=1,"+str(count)+" do api.actor.wait('"+String(owned.data.id)+"',1) end elseif ticks==2 then api.state.set('unsafe',true); "+last+" end end}"
	var pack := ExploreModPack._snapshot({"manifest.json":'{"id":"forger","name":"Forger","version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"}'.to_utf8_buffer(),"main.lua":source.to_utf8_buffer()})
	var progress := Progress.new()
	service.runtime.bind([pack],progress,service.generation)
	service.step(.1,false)
	check(service.runtime.has_owner("forger"),"32 foreign handle calls remain enabled")
	var logged := service.runtime.diagnostics.filter(func(entry: Dictionary) -> bool: return entry.reason == "wrong_owner")
	check_eq(logged.size(),count,"foreign handle misuse logged even without on_event")
	service.step(100,true)
	service.step(.1,false)
	check(not service.runtime.has_owner("forger"),"33rd foreign handle faults; suspended time did not expire window")
	check(service.actors._actors.has(owned.data.id),"victim's actor remains intact")
	check(not progress.get_state("forger",1).data.has("unsafe"))
	service.leave("test")

func test_accepted_async_action_failure_keeps_committed_callback_progress() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var service := ExploreModService.new()
	service.bind(session,[],Progress.new())
	service.enter()
	var owned := service.api.apply({"owner":"async","generation":service.generation,"request_id":1,"kind":"actor.spawn","args":{"kind":"pedestrian","options":{"key":"waiting","position":{"x":22.5,"y":GROUND,"z":20.5}}}})
	check_eq(owned.code,"ok")
	if owned.code != "ok": service.leave("test"); return
	var source := "local done=false return {on_tick=function(api) if not done then done=true; api.state.set('accepted',true); api.actor.wait('"+String(owned.data.id)+"',30) end end,on_event=function(api,e) if e.code=='cancelled' then api.state.set('cancelled',true) end end}"
	var pack := ExploreModPack._snapshot({"manifest.json":'{"id":"async","name":"Async","version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"}'.to_utf8_buffer(),"main.lua":source.to_utf8_buffer()})
	var progress := Progress.new()
	service.runtime.bind([pack],progress,service.generation)
	service.step(.1,false)
	check_eq(progress.get_state("async",1).data.get("accepted"),true,"pending asynchronous wait is host-accepted immediately")
	check_eq(service.runtime.metrics().pending_transactions,0)
	city.building.put(22,20,0)
	view.traffic.graph.refresh()
	service.step(.1,false)
	check_eq(progress.get_state("async",1).data.get("accepted"),true,"later cancellation does not undo accepted state")
	check_eq(progress.get_state("async",1).data.get("cancelled"),true)
	check(service.runtime.diagnostics.is_empty())
	service.leave("test")
