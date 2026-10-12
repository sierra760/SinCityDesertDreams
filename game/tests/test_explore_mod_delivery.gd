extends "res://tests/exploration/explore_session_case.gd"

func test_interaction_and_objective_services_exist() -> void:
	check(ResourceLoader.exists("res://scripts/exploration/mods/explore_mod_interactions.gd"),"owned interactions required")
	check(ResourceLoader.exists("res://scripts/exploration/mods/explore_mod_objectives.gd"),"owned objectives required")
	check(ExploreModPack.read("res://explore_mods/desert_delivery").ok,"playable Lua delivery required")

func _street() -> bool:
	var value := flat_city()
	for x in range(18,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	return _setup(value)

func _delivery() -> ExploreModService:
	var service := ExploreModService.new()
	service.bind(session,[ExploreModPack.read("res://explore_mods/desert_delivery")],ExploreModProgress.new())
	service.enter()
	for i in 12: service.step(.1,false)
	return service

func test_delivery_accept_drive_complete() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var sim := Simulation.new()
	sim.setup(city,173)
	var sim_before := sim.snapshot().duplicate(true)
	var before := SaveFormat.encode_city(city).duplicate(true)
	var service := _delivery()
	session.mod_service = service
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	check_eq(service.actors._actors.size(),3,"actual Lua spawns courier, recipient and car")
	check_eq(service.api.objectives.list_owned("desert_delivery").size(),1)
	check(service.activate_interaction(),"courier prompt activates")
	service.step(.1,false)
	check(not service.api.interactions._dialogue.is_empty(),"actual Lua opens offer")
	check(session.is_suspended(),"dialogue suspends actor input")
	var ticks := service.runtime.tick_count
	service.step(5,true)
	check_eq(service.runtime.tick_count,ticks,"modal freezes Lua")
	service.api.interactions.choose("accept")
	check(not service._progress.get_state("desert_delivery",1).data.get("accepted",false),"choice is deferred beyond modal close")
	service.step(.1,false)
	check(service._progress.get_state("desert_delivery",1).data.get("accepted",false))
	var car_id := ""
	for id: String in service.actors._actors:
		if service.actors._actors[id].record.kind == &"car": car_id = id
	check(not car_id.is_empty())
	if car_id.is_empty(): return
	var record: Dictionary = service.actors._actors[car_id].record
	var pose := view.traffic.actor_pose(record)
	session.pedestrian.place(Transform3D(Basis.IDENTITY,pose.origin+Vector3(0,0,.4)))
	var claim := view.traffic.claim_nearby_vehicle(pose.origin,.65)
	check(not claim.is_empty())
	check(session._select_vehicle(&"car",claim),"supported engine player takeover")
	var drive := service.api.apply({"owner":"desert_delivery","generation":service.generation,"request_id":40,"kind":"actor.navigate","args":{"id":car_id,"destination":{"x":25.5,"y":GROUND,"z":20.5}}})
	check_eq(drive.code,"player_controlled","script cannot steer player's vehicle")
	var recipient_cell := CityTrafficGraph.INVALID
	for actor: Dictionary in service.actors._actors.values():
		if actor.key == "recipient": recipient_cell = actor.record.cell
	check(recipient_cell != CityTrafficGraph.INVALID,"actual recipient identifies delivery destination")
	var target := view.traffic.graph.point(recipient_cell,&"road")
	var start: Vector3 = pose.origin
	session.occupied.global_position = start+Vector3.UP*.002
	session._apply_safe_actor_pose(session.occupied,Transform3D(Basis.looking_at(target-start,Vector3.UP),start))
	var moved := false
	for i in 180:
		var frame := ExploreInputFrame.new()
		frame.move = Vector2(0,-1)
		session.occupied.step(frame,0,.1)
		service.step(.1,false)
		await physics_frame
		if session.occupied.global_position.distance_to(start) > .2: moved = true
		if service._progress.get_state("desert_delivery",1).data.get("completed",false): break
	check(moved,"player driving moves engine car along connected road")
	check(service._progress.get_state("desert_delivery",1).data.get("completed",false),"actual Lua recognizes player arrival")
	var listed := service.api.objectives.list_owned("desert_delivery")
	check(not listed.is_empty())
	if not listed.is_empty(): check_eq(listed[0].status,"completed")
	check_eq(SaveFormat.encode_city(city),before,"mission never writes city or treasury")
	check_eq(sim.snapshot(),sim_before,"funds, clock and simulation RNG unchanged")
	sim.free()
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))

func test_disable_while_player_drives() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var service := _delivery()
	session.mod_service = service
	var car_id := ""
	for id: String in service.actors._actors:
		if service.actors._actors[id].record.kind == &"car": car_id = id
	if car_id.is_empty(): check(false,"car spawn required"); return
	var record: Dictionary = service.actors._actors[car_id].record
	var claim := view.traffic.claim_nearby_vehicle(view.traffic.actor_pose(record).origin,.65)
	check(session._select_vehicle(&"car",claim))
	service.disable("desert_delivery")
	check(is_instance_valid(session.occupied))
	check(session.occupied.has_support())
	var command := {"owner":"desert_delivery","generation":service.generation,"request_id":50,"kind":"actor.navigate","args":{"id":car_id,"destination":{"x":25.5,"y":GROUND,"z":20.5}}}
	check_eq(service.api.apply(command).code,"player_controlled")
	command.owner = "other"
	check_eq(service.api.apply(command).code,"wrong_owner")
	command.generation = -1
	check_eq(service.api.apply(command).code,"stale_generation")
	check(service.api._outstanding.is_empty())
	check(service.api.objectives.journal().is_empty())
	check(service.api.interactions._owned.is_empty())
	check(record in view.traffic.actors,"occupied support remains after disable")
	var pose: Dictionary = session._exit_pose()
	check(not pose.is_empty())
	if not pose.is_empty(): session._leave_vehicle(pose.transform)
	check(service.actors._detached.is_empty(),"safe exit clears session handle")
	check(not record in view.traffic.actors,"safe exit removes transferred record")

func test_owned_dialogue_busy_choices_and_quotas() -> void:
	var interactions := ExploreModInteractions.new()
	var point := {"x":1.5,"y":0.0,"z":1.5}
	check_eq(interactions.register("one","courier",point,"talk").code,"ok")
	check_eq(interactions.activate(point).code,"ok")
	check_eq(interactions.dialogue("one","offer","Courier","Hello",[{"key":"yes","label":"Accept"}]).code,"ok")
	check_eq(interactions.dialogue("two","other","Other","Hello",[{"key":"yes","label":"Accept"}]).code,"busy")
	interactions.choose("bad")
	check(not interactions._dialogue.is_empty())
	interactions.choose("yes")
	check(interactions._dialogue.is_empty())
	check_eq(interactions.take_choices()[0].data.choice,"yes")
	check(interactions.take_choices().is_empty(),"choice delivered only once")
	interactions.busy = func() -> bool: return true
	check_eq(interactions.activate(point).code,"busy")
	interactions.clear_owner("one")
	check(interactions.nearby(point).is_empty())
	var objectives := ExploreModObjectives.new()
	for i in 8: check_eq(objectives.set_objective("one",str(i),"Task","active").code,"ok")
	check_eq(objectives.set_objective("one","ninth","Task","active").code,"quota_exceeded")
	check_eq(objectives.set_objective("one","0","Done","completed").code,"ok")
	check_eq(objectives.set_objective("one","0","Done","complete").code,"invalid_argument")
	var copy := objectives.list_owned("one")
	copy[0].text = "changed"
	check_eq(objectives.list_owned("one")[0].text,"Done")

func test_interaction_ties_use_owner_then_key_across_registration_orders() -> void:
	var player := {"x":0.0,"y":0.0,"z":0.0}
	var point := {"x":1.0,"y":0.0,"z":0.0}
	for owners in [["z_owner","a_owner"],["a_owner","z_owner"]]:
		var interactions := ExploreModInteractions.new()
		for owner: String in owners:
			check_eq(interactions.register(owner,"hello",point,owner).code,"ok")
		check_eq(interactions.nearby(player).owner,"a_owner","equal distance uses stable owner identity")
		check_eq(interactions.activate(player).event.owner,"a_owner","visible prompt and activated action select the same owner")
		interactions.clear_owner("a_owner")
		check_eq(interactions.nearby(player).owner,"z_owner","remaining owner stays usable while another reloads")
		check_eq(interactions.register("a_owner","hello",point,"reloaded").code,"ok")
		check_eq(interactions.activate(player).event.owner,"a_owner","re-registration retains stable selection")
	for keys in [["z_key","a_key"],["a_key","z_key"]]:
		var interactions := ExploreModInteractions.new()
		for key: String in keys:
			check_eq(interactions.register("one",key,point,key).code,"ok")
		check_eq(interactions.nearby(player).key,"a_key","same owner ties use interaction key")
		interactions.unregister("one","a_key")
		interactions.register("one","a_key",point,"reloaded key")
		check_eq(interactions.activate(player).event.key,"a_key","key re-registration retains stable selection")

func test_interaction_nearest_and_strict_radius_precede_identity() -> void:
	var player := {"x":0.0,"y":0.0,"z":0.0}
	var interactions := ExploreModInteractions.new()
	check_eq(interactions.register("a_owner","a_key",{"x":1.0,"y":0.0,"z":0.0},"farther").code,"ok")
	check_eq(interactions.register("z_owner","z_key",{"x":0.5,"y":0.0,"z":0.0},"closer").code,"ok")
	check_eq(interactions.nearby(player).owner,"z_owner","a closer target wins over lexical identity")
	check_eq(interactions.activate(player).event.key,"z_key")
	interactions.clear_owner("z_owner")
	interactions.clear_owner("a_owner")
	interactions.register("a_owner","edge",{"x":1.5,"y":0.0,"z":0.0},"edge")
	check(interactions.nearby(player).is_empty(),"exact original radius boundary stays excluded")
	interactions.register("z_owner","inside",{"x":1.499,"y":0.0,"z":0.0},"inside")
	check_eq(interactions.nearby(player).key,"inside","inside radius remains usable")

func test_no_route_delivery_is_safe() -> void:
	var value := flat_city()
	value.building.put(22,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	if not _setup(value) or not await _enter(): return
	session.set_physics_process(false)
	var service := _delivery()
	var listed := service.api.objectives.list_owned("desert_delivery")
	check(not listed.is_empty(),"no-route result survives healthy runtime: "+str(service.runtime.diagnostics))
	if not listed.is_empty(): check_eq(listed[0].status,"failed")
	check(service.api.interactions._owned.is_empty())
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")

class ElevatorFirst extends ExploreTransitService:
	func interact_elevator() -> bool: return true

func test_existing_elevator_and_nearer_parked_car_keep_priority() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var service := _delivery()
	session.mod_service = service
	check(service.actors._actors.size() == 3)
	var car_record: Dictionary = {}
	for actor: Dictionary in service.actors._actors.values():
		if actor.record.kind == &"car": car_record = actor.record
	check(not car_record.is_empty())
	if not car_record.is_empty():
		var car_pose := view.traffic.actor_pose(car_record)
		check(session._parking_clears_actors(Transform3D(Basis.IDENTITY,car_pose.origin),1),"enterable road spawn clears original parked actors")
	check(session._nearby_mod_vehicle().is_empty(),"farther mod car cannot override nearer original parked car")
	session.transit_service.free()
	var elevator := ElevatorFirst.new()
	view.world.add_child(elevator)
	session.transit_service = elevator
	check(session.request_interaction(),"existing elevator handles F before mod interaction")
	service.step(.1,false)
	check(service.api.interactions._dialogue.is_empty(),"courier receives no event when existing elevator handles F")

func test_remove_while_claimed_defers_and_cancels_original_drive_once() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var service := _delivery()
	session.mod_service = service
	var id := ""
	for handle: String in service.actors._actors:
		if service.actors._actors[handle].record.kind == &"car": id = handle
	if id.is_empty(): check(false,"car required"); return
	var record: Dictionary = service.actors._actors[id].record
	var command := {"owner":"desert_delivery","generation":service.generation,"request_id":70,"kind":"actor.navigate","args":{"id":id,"destination":{"x":25.5,"y":GROUND,"z":20.5}}}
	check(service.api.apply(command).is_empty())
	var claim := view.traffic.claim_nearby_vehicle(view.traffic.actor_pose(record).origin,.65)
	check(session._select_vehicle(&"car",claim))
	service.step(.1,false)
	check(not service.api._outstanding.desert_delivery.has(70),"claim cancels pending original navigation and releases outstanding slot")
	command.kind = "actor.remove"
	command.request_id = 71
	command.args = {"id":id}
	check_eq(service.api.apply(command).code,"player_controlled")
	check(record in view.traffic.actors)
	var exit_pose: Dictionary = session._exit_pose()
	check(not exit_pose.is_empty())
	if not exit_pose.is_empty(): session._leave_vehicle(exit_pose.transform)
	service.step(.1,false)
	check(not service.actors._actors.has(id),"deferred removal runs only after safe exit")
	check(not record in view.traffic.actors)

func test_actual_lua_fault_preserves_claimed_car_until_exit() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var pack := ExploreModPack._snapshot({"manifest.json":'{"id":"fault_delivery","name":"Fault Delivery","version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"}'.to_utf8_buffer(),"main.lua":'return {on_start=function(api) api.actor.spawn("car",{key="car",enterable=true}) end,on_tick=function(api) if api.state.get("fault",false) then error("fault injection") end end}'.to_utf8_buffer()})
	var progress := ExploreModProgress.new()
	var service := ExploreModService.new()
	service.bind(session,[pack],progress)
	service.enter()
	session.mod_service = service
	for i in 3: service.step(.1,false)
	check_eq(service.actors._actors.size(),1)
	if service.actors._actors.is_empty(): return
	var id: String = service.actors._actors.keys()[0]
	var record: Dictionary = service.actors._actors[id].record
	var claim := view.traffic.claim_nearby_vehicle(view.traffic.actor_pose(record).origin,.65)
	check(session._select_vehicle(&"car",claim))
	progress.commit("fault_delivery",1,"1.0.0",{"fault":true})
	service.step(.1,false)
	check(service.runtime._sessions.is_empty(),"actual entered Lua fault closes VM")
	check(is_instance_valid(session.occupied) and session.occupied.has_support())
	check_eq(service.api.apply({"owner":"fault_delivery","generation":service.generation,"request_id":90,"kind":"actor.navigate","args":{"id":id,"destination":{"x":25.5,"y":GROUND,"z":20.5}}}).code,"player_controlled")
	check(service.api._outstanding.is_empty())
	var exit_pose: Dictionary = session._exit_pose()
	if not exit_pose.is_empty(): session._leave_vehicle(exit_pose.transform)
	check(service.actors._detached.is_empty())

func test_rail_reservation_rejects_enterable_spawn() -> void:
	var value := flat_city()
	for x in range(18,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
	var traffic := CityTraffic3D.new()
	traffic.bind_city(value)
	traffic.set_reserved_rail_cells([Vector2i(22,20)])
	var queries := ExploreWorldQueries.new()
	queries.bind(traffic.graph,null)
	queries.reserved_rail = {Vector2i(22,20):true}
	var actors := ExploreActorRegistry.new()
	actors.bind(null,traffic,4)
	actors.queries = queries
	check_eq(actors.apply({"owner":"rail","generation":4,"request_id":1,"kind":"actor.spawn","args":{"kind":"train","options":{"key":"train","enterable":true,"position":{"x":22.5,"y":GROUND,"z":20.5}}}}).code,"no_route")
	traffic.free()

func test_owned_road_cars_share_junction_arbitration() -> void:
	var value := flat_city()
	for i in range(15,26):
		value.building.put(i,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
		value.building.put(20,i,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5))
	value.building.put(20,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,15))
	var traffic := CityTraffic3D.new()
	traffic.bind_city(value)
	var west := traffic.owned_spawn("delivery",&"car",Vector2i(20,20),0)
	west.t = .1
	var north := traffic.owned_spawn("other",&"car",Vector2i(20,19),0)
	check(not west.is_empty() and not north.is_empty())
	if west.is_empty() or north.is_empty(): traffic.free(); return
	north.cell = Vector2i(20,20)
	west.previous = Vector2i(19,20)
	west.next = Vector2i(21,20)
	north.previous = Vector2i(20,19)
	north.next = Vector2i(20,21)
	for actor: Dictionary in [west,north]:
		actor.t = .1
		actor.mod_route = [actor.next,actor.next+(actor.next-actor.cell),actor.next+2*(actor.next-actor.cell)]
		actor.mod_route_index = 0
		actor.mod_destination = actor.mod_route[-1]
		actor.mod_hold = false
		actor.stopped = false
	var overlap := false
	var cleared: Dictionary = {}
	for i in 240:
		traffic.advance_owned(1.0/30.0)
		var inside := 0
		for actor: Dictionary in [west,north]:
			if actor.cell != Vector2i(20,20): cleared[actor.id] = true
			elif actor.t >= CityTraffic3D.STOP_LINE and actor.t < CityTraffic3D.BOX_CLEAR: inside += 1
		if inside > 1: overlap = true
	check(not overlap,"scripted crossing cars never occupy conflicting junction axes")
	check_eq(cleared.size(),2,"both routes progress through the engine arbiter")
	traffic.free()

func test_enterable_admission_shares_surface_work_budget() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var service := ExploreModService.new()
	service.bind(session,[],ExploreModProgress.new())
	service.enter()
	service.queries.nodes_visited_in_one_step = 256
	check_eq(service.api.apply({"owner":"budget","generation":service.generation,"request_id":1,"kind":"actor.spawn","args":{"kind":"car","options":{"key":"car","enterable":true}}}).code,"quota_exceeded")
	check(service.actors._actors.is_empty(),"exhausted query step cannot bypass admission work budget")
	service.leave("test")

func test_actual_host_dialogue_restores_input_before_next_physics_tick() -> void:
	var host: GameHost = load("res://scenes/main.tscn").instantiate()
	host.preferences_path = "user://f4-dialogue-test.cfg"
	root.add_child(host)
	var value := flat_city()
	for x in range(18,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	host.begin_city(value,{},7,CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.city_view_3d.set_center_cell(Vector2i(22,20))
	host.exploration.mod_packs.assign([ExploreModPack.read("res://explore_mods/desert_delivery")])
	check(host.explore_switch.enter())
	host.display_layout.release_city_focus()
	host.exploration.set_physics_process(false)
	var service := host.exploration.mod_service
	if service == null: host.free(); return
	for i in 12: service.step(.1,false)
	check(service.activate_interaction())
	service.step(.1,false)
	check_eq(host.modal_depth,1)
	check(host.exploration.is_suspended())
	service.api.interactions.choose("accept")
	check_eq(host.modal_depth,0)
	check(not host.exploration.is_suspended(),"closing before another physics frame restores Explore")
	check(not service._progress.get_state("desert_delivery",1).data.get("accepted",false),"choice stays deferred after host modal closes")
	service.step(.1,false)
	check(service._progress.get_state("desert_delivery",1).data.get("accepted",false))
	host.exploration.pause()
	var data := {"owner":"desert_delivery","key":"pause","speaker":"Courier","text":"Hello","choices":[{"key":"ok","label":"Okay"}]}
	check(not host.exploration.present_mod_dialogue(data),"manual pause retains its input ownership")
	check(host.exploration._manual_pause)
	check(not host.exploration._resume_when_unblocked)
	host.exploration._manual_pause = false
	host.exploration._resume_when_unblocked = false
	check(not host.exploration.present_mod_dialogue(data),"suspension with automatic resume disabled refuses dialogue")
	check(host.exploration.is_suspended())
	check(not host.exploration._resume_when_unblocked)
	check_eq(host.modal_depth,0)
	host.free()

func test_long_objective_is_compact_and_full_journal_is_readable() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var service := ExploreModService.new()
	service.bind(session,[],ExploreModProgress.new())
	service.enter()
	session.mod_service = service
	var long_text := "Follow the connected road toward the waiting recipient and deliver the parcel safely. ".repeat(30)
	check_eq(service.api.objectives.set_objective("long","task",long_text,"active").code,"ok")
	session._publish_status()
	await process_frame
	await process_frame
	check(hud._journal_label.text.contains(long_text),"full valid objective remains in scrollable journal")
	check_eq(hud._objective_label.max_lines_visible,2)
	check(hud._objective_label.text == long_text,"tracked text is not silently lost or replaced by shortened example")
	check(hud._objective_label.size.y >= 28,"tracked objective has visible space, not a zero-height clipped label")
	check(hud._objective_label.get_combined_minimum_size().y < 60,"tracked text height remains compact for a long objective")
	check(hud._resume_button.custom_minimum_size.y >= 44,"journal preserves reachable Resume action")

func test_takeover_cancels_accepted_route_until_fresh_navigation() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var service := ExploreModService.new()
	service.bind(session,[],ExploreModProgress.new())
	service.enter()
	session.mod_service = service
	var command := {"owner":"takeover","generation":service.generation,"request_id":80,"kind":"actor.spawn","args":{"kind":"car","options":{"key":"car","enterable":true,"position":{"x":22.5,"y":GROUND,"z":20.5}}}}
	var spawned := service.api.apply(command)
	check_eq(spawned.code,"ok")
	if spawned.code != "ok": return
	var id: String = spawned.data.id
	var record: Dictionary = service.actors._actors[id].record
	var start: Vector3 = view.traffic.actor_pose(record).origin
	command.kind = "actor.navigate"
	command.request_id = 81
	command.args = {"id":id,"destination":{"x":28.5,"y":GROUND,"z":20.5}}
	check(service.api.apply(command).is_empty())
	for i in 8: service.step(.1,false)
	check(not record.get("mod_hold",true),"accepted navigation releases engine hold")
	check(view.traffic.actor_pose(record).origin.distance_to(start) > .03,"accepted route visibly moves before takeover")
	check(service.actors._actors[id].has("navigation_command"),"route remains outstanding at takeover")
	var claim := view.traffic.claim_nearby_vehicle(view.traffic.actor_pose(record).origin,.65)
	check(session._select_vehicle(&"car",claim))
	service.step(.1,false)
	check(not service.api._outstanding.takeover.has(81),"takeover releases request once")
	var frame := ExploreInputFrame.new()
	frame.move = Vector2(0,-1)
	for i in 4:
		session.occupied.step(frame,0,.1)
		await physics_frame
	var exit_pose: Dictionary = session._exit_pose()
	check(not exit_pose.is_empty(),"player can safely exit moving scripted car")
	if exit_pose.is_empty(): return
	session._leave_vehicle(exit_pose.transform)
	var released: Vector3 = view.traffic.actor_pose(record).origin
	for i in 12: service.step(.1,false)
	check_eq(view.traffic.actor_pose(record).origin,released,"canceled accepted route never resumes after safe exit")
	check(record.get("mod_hold",false),"released record remains held")
	check(record.get("mod_route",[]).is_empty(),"takeover invalidates old route")
	command.request_id = 82
	check(service.api.apply(command).is_empty(),"fresh navigation is admitted")
	for i in 12: service.step(.1,false)
	check(view.traffic.actor_pose(record).origin.distance_to(released) > .03,"fresh command restores scripted movement")

func test_actual_host_all_three_both_enable_orders_keep_offer_and_resume() -> void:
	for order in [["desert_stroll","desert_atmosphere","desert_delivery"],["desert_delivery","desert_atmosphere","desert_stroll"]]:
		var host: GameHost = load("res://scenes/main.tscn").instantiate()
		host.preferences_path = "user://coexistence-actual-host.cfg"
		root.add_child(host)
		var value := flat_city()
		for y in range(16,32): value.building.put(22,y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5))
		host.begin_city(value,{},7,CityStats.new())
		host.sim.set_speed(GameClock.Speed.PAUSED)
		host.sim.set_process(false)
		host.city_view_3d.set_center_cell(Vector2i(22,20))
		var packs: Array[Dictionary] = []
		for id: String in order: packs.append(ExploreModPack.read("res://explore_mods/"+id))
		host.exploration.mod_packs.assign(packs)
		await physics_frame
		check(host.explore_switch.enter(),"actual GameHost enters with all three enabled in user order")
		host.display_layout.release_city_focus()
		host.exploration.set_physics_process(false)
		var service := host.exploration.mod_service
		if service == null: host.free(); return
		for i in 12: service.step(.1,false)
		check(service.runtime.has_owner("desert_delivery") and service.runtime.has_owner("desert_stroll") and service.runtime.has_owner("desert_atmosphere"))
		check(service.api.interactions._owned.get("desert_delivery",{}).has("parcel"),"actual host retains a usable concurrent delivery offer")
		var keys := {}
		for actor: Dictionary in service.actors._actors.values(): keys[actor.owner+":"+actor.key] = true
		check(keys.has("desert_delivery:courier") and keys.has("desert_stroll:stroller1"),"both relative orders preserve both pedestrian roles in actual host")
		var actors := service.actors._actors.duplicate()
		var state := service._progress.snapshot()
		host.exploration.pause()
		service.configure_packs(packs)
		service.apply_configuration()
		check_eq(service.actors._actors,actors,"unchanged host Resume does not replace actual actor handles")
		check_eq(service._progress.snapshot(),state)
		check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
		host.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://coexistence-actual-host.cfg"))
		await physics_frame
