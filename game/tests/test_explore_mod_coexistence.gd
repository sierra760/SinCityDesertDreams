# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/explore_session_case.gd"

# Production Lua/Service throughout: no synthetic completion, actor injection,
# overlap clearing or player pose assignment. Dispatch sends the first parcel
# about ten tiles from the van; starting at the south end of the north/south
# street keeps the van's ordinary initial facing toward that address.
const MISSION_ORIGIN := Vector3(22.5,GROUND,26.5)
func _street(extend_north: bool = false) -> bool:
	var value := flat_city()
	for y in range(15 if extend_north else 16,32): value.building.put(22,y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5))
	return _setup(value)

func _packs(delivery_first: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var order := ["desert_delivery","desert_atmosphere","desert_stroll"] if delivery_first else ["desert_stroll","desert_atmosphere","desert_delivery"]
	for id: String in order: result.append(ExploreModPack.read("res://explore_mods/"+id))
	return result

func _service(packs: Array[Dictionary], progress: ExploreModProgress = null) -> ExploreModService:
	var service := ExploreModService.new()
	service.bind(session,packs,progress if progress != null else ExploreModProgress.new())
	session.mod_service = service
	service.enter()
	return service

func _actor(service: ExploreModService, owner: String, key: String) -> Dictionary:
	for actor: Dictionary in service.actors._actors.values():
		if actor.owner == owner and actor.key == key: return actor
	return {}

## The address Dispatch actually requested, from its own cached query result.
func _requested_address(service: ExploreModService) -> Vector2:
	var entries: Array = service.runtime._sessions.get("desert_delivery",{}).get("queries",{}).get("world.find_landmark",[])
	for index in range(entries.size()-1,-1,-1):
		var entry: Dictionary = entries[index]
		if entry.args.size() > 1 and entry.args[1] is Dictionary and entry.args[1].has("from") and entry.result.code == "ok":
			return Vector2(entry.result.data.x,entry.result.data.z)
	return Vector2.INF

## Recipients carry a per-parcel serial suffix.
func _recipient(service: ExploreModService) -> Dictionary:
	for actor: Dictionary in service.actors._actors.values():
		if actor.owner == "desert_delivery" and String(actor.key).begins_with("recipient"): return actor
	return {}

func _supported_distinct(service: ExploreModService) -> void:
	var cells := {}
	var exclusions: Array[RID] = []
	for actor: Dictionary in service.actors._actors.values():
		var record: Dictionary = actor.record
		if record.kind != &"pedestrian": continue
		check(not cells.has(record.cell),"pedestrian admissions retain occupied-cell refusal")
		cells[record.cell] = true
		var point := view.traffic.actor_pose(record).origin
		check(not session.traversal.support_near(point,.06,.06,exclusions).is_empty(),"actual admitted pose has real native support")
		check(not session.traversal.touches_water(point),"admitted pose is dry")

func test_all_three_stroll_first_actual_delivery_and_three_routines() -> void:
	await _mission(false)

func test_all_three_delivery_first_actual_delivery_and_three_routines() -> void:
	await _mission(true)

func test_common_endpoint_delivery_arrival_uses_actual_admitted_recipient() -> void:
	await _mission(false,true)

func _mission(delivery_first: bool, endpoint_blocked: bool = false) -> void:
	# Keep the displaced recipient on an interior lane, beyond the landmark arrival radius.
	if not _street(endpoint_blocked) or not await _enter(MISSION_ORIGIN): return
	session.set_physics_process(false)
	var before := SaveFormat.encode_city(city).duplicate(true)
	var packs := _packs(delivery_first)
	if endpoint_blocked:
		# Both possible far addresses are occupied, so the recipient must be
		# admitted at a different, actual vacancy.
		packs.push_front(_blocking_pack('return {on_start=function(api) api.actor.spawn("pedestrian",{key="endpoint",position={x=22.5,y='+str(GROUND)+',z=15.9}}); api.actor.spawn("pedestrian",{key="endpoint2",position={x=22.5,y='+str(GROUND)+',z=16.9}}) end}'))
	var service := _service(packs)
	for i in 12: service.step(.1,false)
	check(service.runtime.has_owner("desert_atmosphere"),"all three real packs remain enabled")
	check(not _actor(service,"desert_delivery","courier").is_empty(),"both startup orders admit courier")
	check(not _actor(service,"desert_stroll","stroller1").is_empty(),"both startup orders admit leading walker")
	check(service.api.interactions._owned.get("desert_delivery",{}).has("parcel"),"real mission has a useful offer")
	_supported_distinct(service)
	var car := _actor(service,"desert_delivery","delivery_car")
	var courier := _actor(service,"desert_delivery","courier")
	if car.is_empty() or courier.is_empty(): check(false,"actual mission resources required"); return
	var car_id: String = car.record.mod_handle
	# Nearest prompt can be the walker in one order. Walk only toward the real
	# courier until its ordinary proximity prompt wins, then use real dialogue.
	var courier_point := view.traffic.actor_pose(courier.record).origin
	for i in 120:
		if service.api.interactions.nearby(service.queries.player).get("owner","") == "desert_delivery": break
		var offset: Vector3 = courier_point-session.pedestrian.feet_position()
		var frame := ExploreInputFrame.new()
		frame.move = Vector2(offset.x,offset.z).normalized()
		session.pedestrian.step(frame,0,.1)
		service.step(.1,false)
		await physics_frame
	check(service.activate_interaction(),"actual proximity activation")
	for i in 3: service.step(.1,false)
	check_eq(service.api.interactions._dialogue.get("owner",""),"desert_delivery","courier offer rather than fabricated interaction")
	if service.api.interactions._dialogue.get("owner","") != "desert_delivery": return
	service.api.interactions.choose("accept")
	for i in 3: service.step(.1,false)
	check(not service.api.interactions._owned.get("desert_delivery",{}).has("parcel"),"real accepted shift retires the offer")
	check(_actor(service,"desert_delivery","courier").is_empty(),"acceptance clears only own courier")
	check(not _actor(service,"desert_stroll","stroller1").is_empty(),"handoff preserves foreign walker")
	var pose := view.traffic.actor_pose(car.record)
	for i in 160:
		if not session._nearby_mod_vehicle().is_empty(): break
		var offset: Vector3 = pose.origin-session.pedestrian.feet_position()
		var frame := ExploreInputFrame.new()
		frame.move = Vector2(offset.x,offset.z).normalized()
		session.pedestrian.step(frame,0,.1)
		service.step(.1,false)
		await physics_frame
	check(session._board_mod_vehicle(),"player walks to and boards actual mission van")
	if session.mode != 1: return
	service.step(.1,false)
	check_eq(service.queries.player.get("vehicle",""),car_id,"ordinary boarding identifies the owned mission handle")
	for i in 10: service.step(.1,false)
	var recipient := _recipient(service)
	if recipient.is_empty(): check(false,"actual mission resources required"); return
	var target := view.traffic.actor_pose(recipient.record).origin
	var address := _requested_address(service)
	check(address.is_finite(),"Dispatch requested a real address")
	check(absf(target.z-session.occupied.feet_position().z) >= 5.0,"the first parcel goes well beyond the old three-tile hop: "+str(target))
	if endpoint_blocked: check(recipient.record.cell != Vector2i(floori(address.x),floori(address.y)),"real occupied landmark requires a different admitted recipient cell")
	var start: Vector3 = session.occupied.feet_position()
	# Forward when the recipient lies ahead (north), reverse otherwise.
	var throttle := -1.0 if target.z < start.z else 1.0
	for i in 600:
		var frame := ExploreInputFrame.new()
		frame.move = Vector2(0,throttle)
		session.occupied.step(frame,0,.1)
		service.step(.1,false)
		await physics_frame
		var probe: Vector3 = session.occupied.feet_position()
		var at_anchor := address.is_finite() and Vector2(probe.x,probe.z).distance_squared_to(address) < .64
		if endpoint_blocked and at_anchor and Vector2(probe.x-target.x,probe.z-target.z).length_squared() >= .64:
			check_eq(int(service._progress.get_state("desert_delivery",1).data.get("deliveries",0)),0,"requested landmark alone cannot earn completion at displaced recipient")
		if int(service._progress.get_state("desert_delivery",1).data.get("deliveries",0)) == 1: break
	check(session.occupied.feet_position().distance_to(start)>.2,"engine player input moves the actual car")
	check_eq(int(service._progress.get_state("desert_delivery",1).data.get("deliveries",0)),1,"Lua earns completion at actual admitted recipient")
	check(Vector2(session.occupied.feet_position().x-target.x,session.occupied.feet_position().z-target.z).length()<.8,"arrival compares actual target point")
	check_eq(service.api.interactions._dialogue.get("key",""),"drop","recipient thanks the courier")
	service.api.interactions.choose("stop")
	for i in 3: service.step(.1,false)
	check_eq(service.api.interactions._dialogue.get("key",""),"radio","ending the shift radios dispatch")
	service.api.interactions.choose("done")
	for i in 30: service.step(.1,false)
	check(_recipient(service).is_empty(),"delivery completion frees own recipient after a wave")
	for i in 1000: service.step(.1,false)
	if endpoint_blocked:
		check(not _actor(service,"street_blocker","endpoint").is_empty(),"mission never removes foreign shared-endpoint blocker")
		check(service.runtime.has_owner("desert_stroll"),"permanent foreign congestion leaves healthy safe waiting routine")
	else:
		check_eq(service._progress.get_state("desert_stroll",1).data.get("strolls",0),3,"all three actual walk/wait routines complete after normal handoffs: "+str(service.api.objectives.list_owned("desert_stroll"))+" "+str(service.actors._actors.values().map(func(a: Dictionary) -> String: return "%s:%s@%s/%s" % [a.owner,a.key,a.record.cell,view.traffic.actor_pose(a.record).origin]))+" player "+str(session.occupied.feet_position()))
		check_eq(service.api.interactions._owned.get("desert_stroll",{}).size(),3,"three real greetings remain")
	check_eq(SaveFormat.encode_city(city),before,"concurrent examples leave all city bytes unchanged")
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")
	check(service.actors._actors.is_empty(),"normal leave clears owned actors")

func _blocking_pack(source: String) -> Dictionary:
	return ExploreModPack._snapshot({"manifest.json":'{"id":"street_blocker","name":"Street blocker fixture","version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"}'.to_utf8_buffer(),"main.lua":source.to_utf8_buffer()})

func test_occupied_origin_and_common_landmark_use_actual_vacancies() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	# The fixture uses ordinary Lua admission at the exact two points the
	# examples would otherwise contest. It stays held; the examples cannot erase it.
	var blocker := _blocking_pack('return {on_start=function(api) api.actor.spawn("pedestrian",{key="origin",position={x=22.5,y='+str(GROUND)+',z=20.9}}); api.actor.spawn("pedestrian",{key="endpoint",position={x=22.5,y='+str(GROUND)+',z=17.9}}) end}')
	var packs := _packs(false)
	packs.push_front(blocker)
	var service := _service(packs)
	for i in 12: service.step(.1,false)
	check_eq(_actor(service,"street_blocker","origin").record.cell,Vector2i(22,20))
	check_eq(_actor(service,"street_blocker","endpoint").record.cell,Vector2i(22,17))
	check(not _actor(service,"desert_delivery","courier").is_empty(),"occupied origin does not permanently lose courier")
	check(service.api.interactions._owned.get("desert_delivery",{}).has("parcel"))
	service.runtime.deliver("desert_delivery",{"kind":"interaction","key":"parcel","code":"ok","data":{}})
	for i in 3: service.step(.1,false)
	service.api.interactions.choose("accept")
	for i in 12: service.step(.1,false)
	var recipient := _recipient(service)
	check(not recipient.is_empty(),"explicit supported landmark admission finds a vacancy")
	if not recipient.is_empty(): check(recipient.record.cell not in [Vector2i(22,17),Vector2i(22,20)],"recipient does not overlap occupied cells")
	_supported_distinct(service)
	var frozen := service.actors.visual_states().duplicate(true)
	var state := service._progress.snapshot()
	var sessions := service.runtime._sessions.duplicate()
	var timers := service.api._timers.duplicate(true)
	service.step(20,true)
	service.configure_packs(packs)
	service.apply_configuration()
	check_eq(service.actors.visual_states(),frozen,"unchanged Resume never respawns or moves held actors")
	check_eq(service._progress.snapshot(),state,"unchanged Resume keeps progress")
	check_eq(service.api._timers,timers,"unchanged Resume keeps active-time recovery phase")
	for id: String in sessions: check(service.runtime._sessions[id] == sessions[id],"unchanged Resume retains the actual VM session")
	check_eq(service.actors._actors.values().filter(func(actor: Dictionary) -> bool: return actor.owner == "street_blocker").size(),2,"no foreign actor removal")
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")

func test_real_lua_transient_startup_refusal_recovers_on_bounded_timer() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var source := 'local ids={} return {on_start=function(api) for z=16,24 do api.actor.spawn("pedestrian",{key="b"..z,position={x=22.5,y='+str(GROUND)+',z=z+.9}}) end api.timer.after("release",2) end,on_event=function(api,e) if e.kind=="action_completed" and e.data.id then ids[#ids+1]=e.data.id end if e.kind=="timer" and e.key=="release" then for i=1,#ids do api.actor.remove(ids[i]) end end end}'
	var packs := _packs(false)
	packs.push_front(_blocking_pack(source))
	var service := _service(packs)
	for i in 12: service.step(.1,false)
	check(_actor(service,"desert_delivery","courier").is_empty(),"real held road occupancy forces initial refusal")
	check(service.api._timers.get("desert_delivery",{}).has("startup_retry"),"exactly one active-time recovery timer is installed")
	check_eq(service.api._timers.get("desert_delivery",{}).size(),1,"no per-frame retry accumulation")
	service.step(50,true)
	check(_actor(service,"desert_delivery","courier").is_empty(),"suspension cannot consume recovery delay")
	for i in 50: service.step(.1,false)
	check(not _actor(service,"desert_delivery","courier").is_empty(),"courier recovers after fixture removes only its own blockers")
	check(service.api.interactions._owned.get("desert_delivery",{}).has("parcel"),"actual recovered source registers offer")
	check(service.runtime.has_owner("desert_stroll") and service.runtime.has_owner("desert_atmosphere"))
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")

func test_delivery_exhaustion_is_finite_truthful_and_keeps_progress() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var source := 'return {on_start=function(api) for z=16,24 do api.actor.spawn("pedestrian",{key="b"..z,position={x=22.5,y='+str(GROUND)+',z=z+.9}}) end end}'
	var packs := _packs(true)
	packs.push_front(_blocking_pack(source))
	var progress := ExploreModProgress.new()
	progress.commit("desert_delivery",1,"1.0.0",{"accepted":true})
	var service := _service(packs,progress)
	for i in 130: service.step(.1,false)
	var listed := service.api.objectives.list_owned("desert_delivery")
	check(not listed.is_empty())
	if not listed.is_empty():
		check_eq(listed[0].status,"failed")
		check("two tries" in listed[0].text and "record is kept" in listed[0].text,"exhausted recovery explains finite bound and normal restart")
	check(service.api._timers.get("desert_delivery",{}).is_empty(),"no unbounded recovery timer remains")
	var count := service.actors._actors.size()
	for i in 100: service.step(.1,false)
	check_eq(service.actors._actors.size(),count,"exhausted recovery stays idle without duplicate actors")
	check(progress.get_state("desert_delivery",1).data.get("accepted",false),"accepted progress survives refused startup")
	service.leave("test")
	progress.commit("desert_delivery",1,"1.0.0",{"accepted":true,"completed":true})
	service = _service(_packs(false),progress)
	for i in 12: service.step(.1,false)
	check(not _actor(service,"desert_delivery","courier").is_empty(),"a finished version-one delivery still offers new shifts")
	var record := service.api.objectives.list_owned("desert_delivery").filter(func(entry: Dictionary) -> bool: return entry.key == "rank")
	check(not record.is_empty() and String(record[0].text).contains("1 parcel ·"),"the finished delivery counts toward the courier record")
	service.leave("test")

func _spawn(service: ExploreModService, owner: String, key: String, options: Dictionary) -> Dictionary:
	options = options.duplicate(true)
	options["key"] = key
	return service.api.apply({"owner":owner,"generation":service.generation,"request_id":1,"kind":"actor.spawn","args":{"kind":"pedestrian","options":options}})

func test_nearby_admission_keeps_explicit_height_support_and_shared_step_budget() -> void:
	if not _street() or not await _enter(): return
	session.set_physics_process(false)
	var service := _service([])
	var anchor := ExploreWorldQueries.copied_point(service.queries.route_point(Vector2i(22,20),&"pedestrian",&"road"),view.traffic.graph.revision)
	var first := _spawn(service,"one","first",{"position":anchor})
	check_eq(first.code,"ok")
	check_eq(_spawn(service,"two","exact",{"position":anchor}).code,"no_route","explicit position remains exact and occupied")
	var before := service.actors._actors.size()
	service.queries.nodes_visited_in_one_step = 256
	check_eq(_spawn(service,"two","budget",{"position":anchor,"near_player":true}).code,"quota_exceeded","nearby admission charges shared query work")
	check_eq(service.actors._actors.size(),before)
	service.queries.nodes_visited_in_one_step = 255
	check_eq(_spawn(service,"two","last_node",{"position":anchor,"near_player":true}).code,"quota_exceeded","one remaining node cannot skip occupied origin")
	check_eq(service.queries.nodes_visited_in_one_step,256)
	service.queries.nodes_visited_in_one_step = 0
	var wrong := anchor.duplicate(true)
	wrong.y += 1.0
	check_eq(_spawn(service,"two","height",{"position":wrong,"near_player":true}).code,"no_route","anchor height cannot be silently repaired")
	check_eq(_spawn(service,"two","unsupported",{"position":{"x":23.5,"y":GROUND,"z":20.5},"near_player":true}).code,"no_route","vacancy search cannot jump from unsupported anchor")
	check_eq(_spawn(service,"two","bad_enterable",{"position":anchor,"near_player":true,"enterable":true}).code,"invalid_argument")
	check_eq(service.actors._actors.size(),before,"invalid options never leak an admitted actor")
	var moved := _spawn(service,"two","near",{"position":anchor,"near_player":true})
	check_eq(moved.code,"ok","occupied anchor admits a supported connected vacancy")
	if moved.code != "ok": service.leave("test"); return
	check(moved.data.has("position"),"spawn returns actual admitted copied position")
	if not moved.data.has("position"): service.leave("test"); return
	var actual := view.traffic.actor_pose(service.actors._actors[moved.data.id].record).origin
	check_eq(ExploreWorldQueries.point(moved.data.position),actual,"completion uses actual pose rather than requested anchor")
	check_eq(moved.data.position.coordinate_space,"tile")
	check_eq(moved.data.position.geometry_revision,view.traffic.graph.revision)
	check_eq(service.actors._actors[moved.data.id].record.cell,Vector2i(22,19),"stable graph order selects nearest connected vacant slot")
	moved.data.position.y = -1000
	check_eq(view.traffic.actor_pose(service.actors._actors[moved.data.id].record).origin,actual,"returned point cannot mutate native record")
	_supported_distinct(service)
	service.leave("test")

func test_nearby_search_does_not_cross_a_missing_supported_connection() -> void:
	var value := flat_city()
	for y in [16,17,18,19,20,22,23,24]: value.building.put(22,y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5))
	if not _setup(value) or not await _enter(): return
	session.set_physics_process(false)
	var service := _service([])
	for y in range(16,21):
		var at := service.queries.route_point(Vector2i(22,y),&"pedestrian",&"road")
		check_eq(_spawn(service,"blocker","b"+str(y),{"position":ExploreWorldQueries.copied_point(at,view.traffic.graph.revision)}).code,"ok")
	var anchor := service.queries.route_point(Vector2i(22,20),&"pedestrian",&"road")
	check_eq(_spawn(service,"new","near",{"position":ExploreWorldQueries.copied_point(anchor,view.traffic.graph.revision),"near_player":true}).code,"no_route","vacant disconnected road remains unreachable")
	check_eq(service.actors._actors.size(),5,"search never crosses unsupported gap to fabricate connection")
	service.leave("test")

func test_nearby_search_32_node_four_edge_and_actor_quota_bounds() -> void:
	var value := flat_city()
	for y in range(16,31):
		for x in range(16,31): value.building.put(x,y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,15))
	if not _setup(value) or not await _enter(): return
	session.set_physics_process(false)
	var service := _service([])
	var anchor := Vector2i(22,20)
	var cells: Array[Vector2i] = [anchor]
	var seen := {anchor:true}
	var depths := {anchor:0}
	var head := 0
	while head < cells.size() and cells.size() < 32:
		var cell := cells[head]
		head += 1
		if depths[cell] >= 4: continue
		for next: Vector2i in view.traffic.graph.neighbors(cell,&"road"):
			if not seen.has(next) and cells.size() < 32:
				seen[next] = true
				depths[next] = int(depths[cell])+1
				cells.append(next)
	check_eq(cells.size(),32,"bounded search fixture has 32 supported graph candidates")
	# Populate through real guarded host admissions; no direct traffic mutation.
	for i in cells.size():
		var at := service.queries.route_point(cells[i],&"pedestrian",&"road")
		check_eq(_spawn(service,"owner"+str(i >> 4),"b"+str(i),{"position":ExploreWorldQueries.copied_point(at,view.traffic.graph.revision)}).code,"ok")
	var at := service.queries.route_point(anchor,&"pedestrian",&"road")
	check_eq(_spawn(service,"new","bounded",{"position":ExploreWorldQueries.copied_point(at,view.traffic.graph.revision),"near_player":true}).code,"no_route","search refuses despite vacant cells beyond its fixed traversal bound")
	check_eq(service.queries.nodes_visited_in_one_step,32,"search inspects at most its exact 32-node bound")
	check_eq(_spawn(service,"owner0","seventeenth",{"near_player":true}).code,"quota_exceeded","nearby search cannot bypass per-owner16 cap")
	check_eq(service.queries.nodes_visited_in_one_step,32,"owner cap refuses before search")
	var serial := 32
	for y in range(16,31):
		for x in range(16,31):
			var cell := Vector2i(x,y)
			if serial >= 64 or seen.has(cell): continue
			var point := service.queries.route_point(cell,&"pedestrian",&"road")
			check_eq(_spawn(service,"extra"+str(serial >> 4),"b"+str(serial),{"position":ExploreWorldQueries.copied_point(point,view.traffic.graph.revision)}).code,"ok")
			serial += 1
	check_eq(service.actors._actors.size(),64)
	check_eq(_spawn(service,"another","global",{"near_player":true}).code,"quota_exceeded","global64 actor cap remains authoritative")
	service.leave("test")

func test_nearby_admission_samples_sloped_candidate_actual_supported_height() -> void:
	var value := flat_city()
	value.terrain_surface = TerrainSurface.new(4)
	for x in [22,23]: value.terrain_surface.set_vertex(x,19,5)
	for y in range(16,32): value.building.put(22,y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5))
	if not _setup(value) or not await _enter(): return
	session.set_physics_process(false)
	var service := _service([])
	var anchor := ExploreWorldQueries.copied_point(service.queries.route_point(Vector2i(22,20),&"pedestrian",&"road"),view.traffic.graph.revision)
	check_eq(_spawn(service,"one","anchor",{"position":anchor}).code,"ok")
	var result := _spawn(service,"two","slope",{"position":anchor,"near_player":true})
	check_eq(result.code,"ok","connected sloped vacancy uses its own authoritative height")
	if result.code == "ok":
		check(result.data.has("position"),"sloped admission returns actual copied feet")
		if result.data.has("position"):
			var actual := ExploreWorldQueries.point(result.data.position)
			check(actual.y > anchor.y+.15,"candidate does not reuse anchor height on slope")
			check_eq(actual,view.traffic.actor_pose(service.actors._actors[result.data.id].record).origin)
			var exclusions: Array[RID] = []
			check(not session.traversal.support_near(actual,.06,.06,exclusions).is_empty(),"actual sloped standing pose has real collision support")
	service.leave("test")
