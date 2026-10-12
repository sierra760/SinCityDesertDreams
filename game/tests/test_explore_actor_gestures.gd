# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/explore_session_case.gd"
func test_owned_wave_completes_once_and_cancels() -> void:
	var value:=flat_city()
	for x in range(18,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	if not _setup(value) or not await _enter(): return
	session.set_physics_process(false)
	var registry:=ExploreActorRegistry.new()
	registry.bind(session,view.traffic,7)
	registry.queries=ExploreWorldQueries.new()
	registry.queries.bind(view.traffic.graph,session.traversal)
	var command: Dictionary={"owner":"wave","generation":7,"request_id":1,"kind":"actor.spawn","args":{"kind":"pedestrian","options":{"key":"walker","position":{"x":22.5,"y":GROUND,"z":20.5}}}}
	var spawned:=registry.apply(command)
	check_eq(spawned.code,"ok")
	if spawned.code!="ok": return
	var id: String=spawned.data.id
	command.merge({"kind":"actor.wave","request_id":2,"args":{"id":id}},true)
	var accepted:=registry.apply(command)
	check(accepted.is_empty(),"wave stays pending under owner clock")
	if not accepted.is_empty(): registry.clear_owner("wave"); return
	registry.step(.5)
	var state:=registry.visual_states()[0]
	check_eq(state.gesture,"wave")
	check_between(state.gesture_time,.499,.501)
	var events:=registry.step(1.0)
	check_eq(events.size(),1)
	check_eq(events[0].code,"ok")
	check_eq(events[0].request_id,2)
	check(registry.step(.1).is_empty(),"completion exactly once")
	command.request_id=3
	registry.apply(command)
	command.merge({"kind":"actor.wait","request_id":4,"args":{"id":id,"duration":1.0}},true)
	registry.apply(command)
	events=registry.step(.1)
	check_eq(events.size(),1)
	check_eq(events[0].code,"cancelled")
	check_eq(events[0].request_id,3)
	check_eq(registry.visual_states()[0].gesture,"")
	registry.clear_owner("wave")
	check(registry.visual_states().is_empty())

func test_actual_stroll_wave_and_suspension_release_outstanding() -> void:
	var value:=flat_city()
	for x in range(18,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	if not _setup(value) or not await _enter(): return
	session.set_physics_process(false)
	var service:=ExploreModService.new()
	session.mod_service=service
	service.bind(session,[ExploreModPack.read("res://explore_mods/desert_stroll")],session.mod_progress)
	service.enter()
	var observed: Dictionary={}
	var released: Dictionary={}
	# Stroll starts its three walkers serially after each preceding 2s wait.
	# This straight fixture travels 3+2+1 cells at the owned pedestrian .09
	# cells/s. Budget all three 1.5s waves even though earlier waves overlap.
	# Origin plus each spawn/landmark/navigate/wait/wave has at most two
	# service ticks for host completion and Lua dispatch on this tiny graph.
	var service_delta := .1
	var travel_seconds := (3.0+2.0+1.0)/.09
	var wait_seconds := 3*2.0
	var wave_seconds := 3*1.5
	var dispatch_seconds := (1+3*5)*2*service_delta
	var max_ticks := ceili((travel_seconds+wait_seconds+wave_seconds+dispatch_seconds)/service_delta)
	for tick in max_ticks:
		service.step(service_delta,false)
		for actor: Dictionary in service.actors._actors.values():
			if actor.has("gesture_command"):
				var request: int=actor.gesture_command.request_id
				observed[request]=true
				check(service.api._outstanding.get("desert_stroll",{}).has(request),"real wave reserves pending action")
				var frozen:=service.actors.visual_states()
				service.step(.7,true)
				check_eq(service.actors.visual_states(),frozen,"suspension freezes wave and gait")
		for request in observed:
			if not service.api._outstanding.get("desert_stroll",{}).has(request): released[request]=true
		if observed.size()==3 and released.size()==3:
			var navigating := false
			for actor: Dictionary in service.actors._actors.values():
				if actor.has("navigation_command"): navigating = true
			if not navigating: break
	check_eq(observed.size(),3,"all three source Stroll walkers walk/wait/wave")
	check_eq(service.api.interactions._owned.get("desert_stroll",{}).size(),3,"all three greetings retained")
	var stops: Dictionary={}
	for actor: Dictionary in service.actors._actors.values():
		check(not actor.has("navigation_command"),"no follower remains permanently blocked")
		stops[str(actor.record.cell)]=true
	check_eq(stops.size(),3,"three distinct validated stopping cells")
	check_eq(released.size(),observed.size(),"every observed wave releases its pending reservation")
	check(service.runtime.has_owner("desert_stroll"),"actual native Lua routine remains live")
	check(service.runtime.diagnostics.is_empty(),"no unavailable/fault diagnostics")
	service.runtime.deliver("desert_stroll",{"kind":"interaction","key":"greet1","code":"ok","data":{}})
	for tick in 5: service.step(.1,false)
	check(not service.api.interactions._dialogue.is_empty(),"greeting still opens")
	service.api.interactions.choose("hello")
	session.leave()
	check(view.traffic.detail_manager==null,"leaving tears down pool")
	check(service.actors.visual_states().is_empty(),"leaving releases scripted actors")

func test_real_batch_exclusion_and_single_owner_clock() -> void:
	var value:=flat_city()
	for x in range(18,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	if not _setup(value) or not await _enter(): return
	session.set_physics_process(false)
	var registry:=ExploreActorRegistry.new()
	registry.bind(session,view.traffic,9)
	registry.queries=ExploreWorldQueries.new()
	registry.queries.bind(view.traffic.graph,session.traversal)
	var command: Dictionary={"owner":"clock","generation":9,"request_id":1,"kind":"actor.spawn","args":{"kind":"pedestrian","options":{"key":"walker","position":{"x":23.5,"y":GROUND,"z":20.5}}}}
	var result:=registry.apply(command)
	check_eq(result.code,"ok")
	if result.code!="ok": return
	var id: String=result.data.id
	var record: Dictionary=registry._actors[id].record
	var camera: Camera3D=session.camera_rig.camera
	var point:=view.traffic.actor_pose(record).origin
	camera.global_position=point+Vector3(0,.1,-.9)
	camera.look_at(point+Vector3(0,.06,0))
	view.traffic._render(camera)
	var manager: ExploreActorDetailManager=view.traffic.detail_manager
	check(manager.debug_state().ids.has(id))
	var zero_rows:=0
	for batch: MultiMeshInstance3D in view.traffic._batches.values():
		for i in batch.multimesh.visible_instance_count:
			if batch.multimesh.get_instance_transform(i).basis.determinant()==0: zero_rows+=1
	# Headless RenderingServer's dummy backend returns identity for every
	# MultiMesh readback. Native capture runs execute the actual upload check.
	if DisplayServer.get_name()!="headless": check_eq(zero_rows,1,"only promoted batch slot is hidden")
	check_eq(view.traffic.statistics.visible,1,"promotion retains batch row count")
	var before:=int(manager.debug_state().owner_updates)
	registry.step(.1)
	check_eq(manager.debug_state().owner_updates,before+1,"one pose update for entire owner tick, not each motion substep")
	for frame in 5: view.traffic._render(camera)
	check_eq(manager.debug_state().owner_updates,before+1,"renders add no owner updates")
	view.traffic._step(.1)
	check_eq(manager.debug_state().owner_updates,before+1,"ambient clock cannot animate scripted actor")
	view.traffic._claims[record.id]={}
	view.traffic._paused_render_state.clear()
	view.traffic._render(camera)
	check(not manager.debug_state().ids.has(id),"claimed actor excluded from NPC pool")
	check(registry.visual_states().is_empty(),"claimed actor absent from scripted visual records")
	view.traffic._claims.erase(record.id)
	registry.clear_owner("clock")
	view.traffic._render(camera)
	check_eq(manager.debug_state().detailed_count,0)
