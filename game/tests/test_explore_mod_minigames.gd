# SPDX-License-Identifier: GPL-3.0-or-later
## Actual Lua sources for Desert Dispatch, Neon Rally and Find the Crooner on a
## connected road loop: full shifts, races and searches through the real host.
extends "res://tests/exploration/explore_session_case.gd"

const START := Vector3(23.5,GROUND,17.5)

## A 14x14 ring road inside the sampled chunk, with correct corner masks.
func _loop_city() -> City:
	var value := flat_city()
	var cells := {}
	for i in range(17,31):
		for cell: Vector2i in [Vector2i(i,17),Vector2i(i,30),Vector2i(17,i),Vector2i(30,i)]: cells[cell] = true
	for cell: Vector2i in cells:
		var mask := 0
		for index in NetworkShapes.DIRECTIONS.size():
			if cells.has(cell+NetworkShapes.DIRECTIONS[index]): mask |= NetworkShapes.DIRECTION_BITS[index]
		value.building.put(cell.x,cell.y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,mask))
	return value

func _service(ids: Array[String], progress: ExploreModProgress = null) -> ExploreModService:
	var packs: Array[Dictionary] = []
	for id in ids: packs.append(ExploreModPack.read("res://explore_mods/"+id))
	var service := ExploreModService.new()
	service.bind(session,packs,progress if progress != null else ExploreModProgress.new())
	service.enter()
	session.mod_service = service
	_run(service,12)
	return service

func _run(service: ExploreModService, steps: int, delta: float = .1) -> void:
	for i in steps: service.step(delta,false)

static func _serial(id: String) -> int:
	return int(id.get_slice(":",3))

## Owned actors whose logical key starts with prefix, in spawn order.
func _owned(service: ExploreModService, owner: String, prefix: String) -> Array[Dictionary]:
	var ids: Array = service.actors._actors.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return _serial(a) < _serial(b))
	var result: Array[Dictionary] = []
	for id: String in ids:
		var actor: Dictionary = service.actors._actors[id]
		if actor.owner == owner and String(actor.key).begins_with(prefix):
			var copy := actor.duplicate()
			copy["id"] = id
			result.append(copy)
	return result

func _latest(service: ExploreModService, owner: String, prefix: String) -> Dictionary:
	var actors := _owned(service,owner,prefix)
	return actors.back() if not actors.is_empty() else {}

func _board(service: ExploreModService, owner: String, key: String) -> bool:
	var actors := _owned(service,owner,key)
	if actors.is_empty(): return false
	var record: Dictionary = actors[0].record
	var pose := view.traffic.actor_pose(record)
	session.pedestrian.place(Transform3D(Basis.IDENTITY,pose.origin+Vector3(0,0,.4)))
	var claim := view.traffic.claim_nearby_vehicle(pose.origin,.65)
	return not claim.is_empty() and session._select_vehicle(record.kind,claim)

## Places the occupied car on the road at cell, as if it had been driven there.
func _drive_to(cell: Vector2i) -> void:
	var target := view.traffic.graph.point(cell,&"road")
	session.occupied.global_position = target+Vector3.UP*.002
	session._apply_safe_actor_pose(session.occupied,Transform3D(Basis.IDENTITY,target))

func _dialogue(service: ExploreModService) -> Dictionary:
	return service.api.interactions._dialogue

func _objective(service: ExploreModService, owner: String, key: String) -> Dictionary:
	for entry in service.api.objectives.list_owned(owner):
		if entry.key == key: return entry
	return {}

func _state(service: ExploreModService, owner: String) -> Dictionary:
	return service._progress.get_state(owner,1).data

func test_new_packs_are_valid_sources() -> void:
	for id in ["desert_delivery","neon_rally","crooner_hunt"]:
		var pack := ExploreModPack.read("res://explore_mods/"+id)
		check(pack.ok,id+" reads as a valid source pack")
		check(pack.sources.has("guide.lua"),id+" ships its guidance module")

func test_landmark_options_reach_farther_vary_and_continue_outward() -> void:
	var traffic := CityTraffic3D.new()
	traffic.bind_city(_loop_city())
	var queries := ExploreWorldQueries.new()
	queries.bind(traffic.graph,null)
	var from := {"x":23.5,"y":queries.route_point(Vector2i(23,17),&"car",&"road").y,"z":17.5}
	var found := func(options: Dictionary) -> Dictionary:
		queries.request("test","world.find_landmark",{"kind":"road_destination","options":options})
		for i in 64:
			var results := queries.step()
			if not results.is_empty(): return results[0]
		return {}
	var near: Dictionary = found.call({"kind":"car","from":from})
	check_eq(near.code,"ok")
	var origin := Vector2(23,17)
	var reach := func(result: Dictionary) -> float: return origin.distance_to(Vector2(floorf(result.data.x),floorf(result.data.z)))
	check(reach.call(near) >= 3.0 and reach.call(near) < 4.0,"default keeps the original three-tile stop")
	var far: Dictionary = found.call({"kind":"car","from":from,"min_distance":10})
	check_eq(far.code,"ok")
	if far.code == "ok": check(reach.call(far) >= 10.0,"min_distance reaches farther addresses")
	var skipped: Dictionary = found.call({"kind":"car","from":from,"min_distance":10,"skip":2})
	if skipped.code == "ok": check(Vector2(skipped.data.x,skipped.data.z) != Vector2(far.data.x,far.data.z),"skip selects a different match")
	var away := {"x":17.5,"y":from.y,"z":17.5}
	var onward: Dictionary = found.call({"kind":"car","from":from,"min_distance":6,"away_from":away})
	check_eq(onward.code,"ok")
	if onward.code == "ok":
		var stop := Vector2(onward.data.x,onward.data.z)
		check(stop.distance_to(Vector2(17.5,17.5)) >= Vector2(23.5,17.5).distance_to(Vector2(17.5,17.5))+3.0,"away_from continues away from the previous stop")
	var impossible: Dictionary = found.call({"kind":"car","from":from,"min_distance":40})
	check_eq(impossible.code,"no_route","an unreachable distance fails as ordinary data")
	check(not ExploreModApi.valid_arguments("world.find_landmark",{"kind":"road","options":{"min_distance":41}}),"distance is bounded")
	check(not ExploreModApi.valid_arguments("world.find_landmark",{"kind":"road","options":{"skip":1.5}}),"skip is an integer")
	check(not ExploreModApi.valid_arguments("world.find_landmark",{"kind":"road","options":{"from":{"x":1}}}),"from is a point")
	traffic.free()

func test_player_query_reports_speed_and_camera_heading() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var service := _service([])
	var player := service.queries.player
	check(player.has("speed") and player.speed is float,"speed is reported")
	check(player.has("heading"),"camera heading is reported")
	if player.has("heading"): check(absf(Vector2(player.heading.x,player.heading.z).length()-1.0) < .001,"heading is a level unit vector")
	service.leave("test")

func test_dispatch_express_shift_delivers_three_parcels() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var sim := Simulation.new()
	sim.setup(city,173)
	var sim_before := sim.snapshot().duplicate(true)
	var before := SaveFormat.encode_city(city).duplicate(true)
	var service := _service(["desert_delivery"])
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	check(service.activate_interaction(),"Marisol offers a shift")
	service.step(.1,false)
	check_eq(_dialogue(service).get("key",""),"offer")
	check_eq(_dialogue(service).get("choices",[]).size(),4,"easy, express, record and decline")
	service.api.interactions.choose("express")
	_run(service,8)
	check(_owned(service,"desert_delivery","courier").is_empty(),"dispatcher steps aside for the shift")
	check(_board(service,"desert_delivery","delivery_car"),"player boards the Delivery Van")
	_run(service,60)
	var tracked: String = _objective(service,"desert_delivery","delivery").get("text","")
	check(tracked.begins_with("1/3 "),"live guidance names the parcel: "+tracked)
	check(tracked.contains(" m") and tracked.contains(" left"),"guidance shows distance and express clock: "+tracked)
	var first := _latest(service,"desert_delivery","recipient")
	check(not first.is_empty())
	check_eq(service.api.markers._owned.desert_delivery.destination.target.id,first.get("id",""),"Dispatch pins the current recipient")
	if first.is_empty(): return
	var address: Vector2i = first.record.cell
	check(Vector2(address).distance_to(Vector2(23,17)) >= 6.0,"first address is well beyond the old three-tile stop")
	for parcel in 3:
		var recipient := _latest(service,"desert_delivery","recipient")
		check(not recipient.is_empty(),"parcel %d has a recipient" % (parcel+1))
		if recipient.is_empty(): return
		_drive_to(recipient.record.cell)
		_run(service,4)
		check_eq(service.api.markers._owned.desert_delivery.destination.target.id,recipient.id,"destination pin follows each parcel")
		var dialogue := _dialogue(service)
		check_eq(dialogue.get("key",""),"drop","arrival opens the recipient's thanks")
		check(String(dialogue.get("text","")).contains("Tip: "),"thanks reports the tip")
		service.api.interactions.choose("next" if parcel < 2 else "finish")
		_run(service,10)
	check_eq(_dialogue(service).get("key",""),"radio","shift wraps with a radio call")
	var state := _state(service,"desert_delivery")
	check_eq(int(state.get("deliveries",0)),3)
	check_eq(int(state.get("shifts",0)),1)
	check_eq(int(state.get("on_time",0)),3,"fast express deliveries are on time")
	check(int(state.get("tips",0)) > 0 and int(state.get("best_shift",0)) == int(state.get("tips",0)))
	check_eq(_objective(service,"desert_delivery","delivery").get("status",""),"completed")
	check(String(_objective(service,"desert_delivery","rank").get("text","")).begins_with("Courier rank: "),"journal keeps the courier record")
	service.api.interactions.choose("done")
	_run(service,4)
	check(_dialogue(service).is_empty())
	check_eq(SaveFormat.encode_city(city),before,"shifts never write the city or treasury")
	check_eq(sim.snapshot(),sim_before,"funds, clock and simulation RNG unchanged")
	sim.free()
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")

func test_dispatch_reads_version_one_progress_and_shows_record() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var progress := ExploreModProgress.new()
	progress.commit("desert_delivery",1,"1.0.0",{"accepted":true,"completed":true})
	var service := _service(["desert_delivery"],progress)
	check(String(_objective(service,"desert_delivery","rank").get("text","")).contains("1 parcel ·"),"an earlier delivery counts toward the record")
	check(service.activate_interaction())
	service.step(.1,false)
	service.api.interactions.choose("stats")
	_run(service,2)
	check_eq(_dialogue(service).get("key",""),"stats")
	check(String(_dialogue(service).get("text","")).contains("4 more deliveries until Road Regular"))
	service.api.interactions.choose("back")
	_run(service,2)
	check_eq(_dialogue(service).get("key",""),"offer","record returns to the offer")
	service.api.interactions.choose("later")
	_run(service,2)
	check(service.api.interactions._owned.get("desert_delivery",{}).has("parcel"),"declining keeps the offer available")
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")

func test_rally_sprint_with_marshals_countdown_and_rival() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var before := SaveFormat.encode_city(city).duplicate(true)
	var service := _service(["neon_rally"])
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	check(service.api.interactions._owned.get("neon_rally",{}).has("race"),"Fran offers a race")
	check(service.activate_interaction())
	service.step(.1,false)
	check_eq(_dialogue(service).get("key",""),"offer")
	service.api.interactions.choose("sprint")
	_run(service,30)
	var marshals := _owned(service,"neon_rally","marshal")
	check_eq(marshals.size(),3,"three marshals mark the sprint course")
	check_eq(_owned(service,"neon_rally","dan").size(),1,"Dusty Dan lines up in his pickup")
	check(not service.api.interactions._owned.get("neon_rally",{}).has("race"),"Fran waits while a course is out")
	check(_board(service,"neon_rally","rally_car"),"player boards the Desert Cruiser")
	_run(service,3)
	check(String(_objective(service,"neon_rally","rally").get("text","")).begins_with("Ready... "),"countdown starts behind the wheel")
	_run(service,32)
	check(String(_objective(service,"neon_rally","rally").get("text","")).contains("CP 1/3"),"race guidance shows the next checkpoint")
	check_eq(service.api.markers._owned.neon_rally.checkpoint.target.id,marshals[0].id,"rally pins only the next marshal")
	var dan: Dictionary = _owned(service,"neon_rally","dan")[0]
	var dan_start: Vector3 = view.traffic.actor_pose(dan.record).origin
	_run(service,10)
	check(view.traffic.actor_pose(dan.record).origin.distance_to(dan_start) > .1,"Dusty Dan drives the course")
	for marshal: Dictionary in marshals:
		_drive_to(marshal.record.cell)
		_run(service,3)
	var dialogue := _dialogue(service)
	check_eq(dialogue.get("key",""),"result","finish line reports the result")
	check(not service.api.markers._owned.neon_rally.has("checkpoint"),"finish removes the last checkpoint")
	check(String(dialogue.get("text","")).contains("GOLD"),"a fast run earns gold: "+String(dialogue.get("text","")))
	check(String(dialogue.get("text","")).contains("You beat Dusty Dan"))
	var state := _state(service,"neon_rally")
	check_eq(int(state.get("races",0)),1)
	check_eq(int(state.get("gold",0)),1)
	check_eq(int(state.get("beat_dan",0)),1)
	check_eq(_objective(service,"neon_rally","rally").get("status",""),"completed")
	service.api.interactions.choose("done")
	_run(service,4)
	check(_owned(service,"neon_rally","marshal").is_empty() and _owned(service,"neon_rally","dan").is_empty(),"course clears after the race")
	check(service.api.interactions._owned.get("neon_rally",{}).has("race"),"Fran is ready for another race")
	check_eq(SaveFormat.encode_city(city),before)
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")

func test_rally_false_start_adds_penalty() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var service := _service(["neon_rally"])
	check(service.activate_interaction())
	service.step(.1,false)
	service.api.interactions.choose("sprint")
	_run(service,30)
	check(_board(service,"neon_rally","rally_car"))
	_run(service,3)
	session.occupied.velocity = Vector3(.5,0,0)
	_run(service,3)
	session.occupied.velocity = Vector3.ZERO
	check(String(_objective(service,"neon_rally","rally").get("text","")).contains("False start"),"rolling early is penalized")
	service.leave("test")

func test_crooner_hot_cold_catch_and_showtime() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var before := SaveFormat.encode_city(city).duplicate(true)
	var service := _service(["crooner_hunt"])
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	check(service.activate_interaction(),"Lou explains the search")
	service.step(.1,false)
	check_eq(_dialogue(service).get("key",""),"offer")
	service.api.interactions.choose("start")
	_run(service,10)
	var crooner := _latest(service,"crooner_hunt","crooner")
	check(not crooner.is_empty(),"the Crooner hides somewhere")
	if crooner.is_empty(): return
	check_eq(service.api.markers._owned.crooner_hunt.crooner.target.id,crooner.id)
	check(not session.navigation_markers().any(func(pin: Dictionary) -> bool: return pin.owner == "crooner_hunt" and pin.key == "crooner"),"distant search target stays hidden on both maps")
	var hidden := view.traffic.actor_pose(crooner.record).origin
	check(Vector2(hidden.x,hidden.z).distance_to(Vector2(START.x,START.z)) >= 4.0,"he hides out of reach")
	check(String(_objective(service,"crooner_hunt","crooner").get("text","")).begins_with("Find the Crooner: "))
	session.pedestrian.place(Transform3D(Basis.IDENTITY,hidden+Vector3(.3,0,0)))
	_run(service,4)
	check(String(_objective(service,"crooner_hunt","crooner").get("text","")).contains("Sizzling"),"right beside him is sizzling")
	check(session.navigation_markers().any(func(pin: Dictionary) -> bool: return pin.owner == "crooner_hunt" and pin.key == "crooner"),"nearby crooner gains an overhead and map pin")
	check(service.activate_interaction(),"tap him on the shoulder")
	service.step(.1,false)
	check_eq(_dialogue(service).get("key",""),"caught")
	check(String(_dialogue(service).get("text","")).contains("Found 1 time"))
	service.api.interactions.choose("go")
	_run(service,30)
	var next := _latest(service,"crooner_hunt","crooner")
	check(not next.is_empty() and next.id != crooner.id,"he slips off to a new spot")
	check(not service.actors._actors.has(crooner.id),"the caught Crooner vanishes after his wave")
	var hinted := false
	for i in 220:
		service.step(1.0,false)
		if String(_objective(service,"crooner_hunt","crooner").get("text","")).contains("A fan spotted him"): hinted = true
		if _dialogue(service).get("key","") == "over": break
	check(hinted,"a long search earns a direction hint")
	check_eq(_dialogue(service).get("key",""),"over","the curtain ends the search")
	var state := _state(service,"crooner_hunt")
	check_eq(int(state.get("rounds",0)),1)
	check_eq(int(state.get("best",0)),1)
	check(_owned(service,"crooner_hunt","crooner").is_empty(),"no Crooner lingers after the show")
	service.api.interactions.choose("done")
	_run(service,2)
	check(service.api.interactions._owned.get("crooner_hunt",{}).has("lou"),"Lou is ready for another search")
	check_eq(SaveFormat.encode_city(city),before)
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")

func test_all_five_built_in_packs_share_one_session() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var ids: Array[String] = ["desert_stroll","desert_delivery","desert_atmosphere","neon_rally","crooner_hunt"]
	var service := _service(ids)
	_run(service,200)
	for id in ids: check(service.runtime.has_owner(id),id+" keeps running alongside the others")
	for pair in [["desert_delivery","parcel"],["neon_rally","race"],["crooner_hunt","lou"]]:
		check(service.api.interactions._owned.get(pair[0],{}).has(pair[1]),pair[0]+" offers its game: "+str(service.api.objectives.list_owned(pair[0]))+" actors "+str(_owned(service,pair[0],"").map(func(a: Dictionary) -> String: return a.key)))
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")

func test_new_packs_idle_safely_without_roads() -> void:
	if not _setup() or not await _enter(): return
	session.set_physics_process(false)
	for id: String in ["neon_rally","crooner_hunt"]:
		var service := _service([id])
		_run(service,400)
		check(service.runtime.has_owner(id),id+" remains safely idle")
		check_eq(service.queries.pending_count(),0)
		check(not service.api.objectives.list_owned(id).is_empty(),id+" explains what is missing")
		check(service.api.interactions._owned.get(id,{}).is_empty(),id+" offers no game without roads")
		check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
		service.leave("test")
