# SPDX-License-Identifier: GPL-3.0-or-later
## Actual Lua sources for Desert Air Patrol (helicopter calls) and Silver State
## Express (long-haul courier) through the real host: every call kind and every
## courier job on a connected ring road with a hospital, plus the chained
## search reach the long routes rely on in an included city.
extends "res://tests/exploration/explore_session_case.gd"

const START := Vector3(23.5,GROUND,17.5)

## A 14x14 ring road inside the sampled chunk, with a hospital inside the
## east side so its road frontage is x=30, z=22..24.
func _loop_city(hospital: bool = true) -> City:
	var value := flat_city()
	var cells := {}
	for i in range(17,31):
		for cell: Vector2i in [Vector2i(i,17),Vector2i(i,30),Vector2i(17,i),Vector2i(30,i)]: cells[cell] = true
	for cell: Vector2i in cells:
		var mask := 0
		for index in NetworkShapes.DIRECTIONS.size():
			if cells.has(cell+NetworkShapes.DIRECTIONS[index]): mask |= NetworkShapes.DIRECTION_BITS[index]
		value.building.put(cell.x,cell.y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,mask))
	if hospital:
		for x in range(27,30):
			for z in range(22,25): value.building.put(x,z,Buildings.HOSPITAL)
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

func _pose(actor: Dictionary) -> Vector3:
	return view.traffic.actor_pose(actor.record).origin

func _dialogue(service: ExploreModService) -> Dictionary:
	return service.api.interactions._dialogue

func _objective(service: ExploreModService, owner: String, key: String) -> Dictionary:
	for entry in service.api.objectives.list_owned(owner):
		if entry.key == key: return entry
	return {}

func _state(service: ExploreModService, owner: String) -> Dictionary:
	return service._progress.get_state(owner,1).data

func _marker(service: ExploreModService, owner: String, key: String) -> Dictionary:
	return service.api.markers._owned.get(owner,{}).get(key,{})

static func _point(target: Dictionary) -> Vector3:
	return Vector3(target.x,target.y,target.z)

## Puts the player in the session helicopter, stopped at the given feet point.
func _fly(at: Vector3) -> void:
	var helicopter: CharacterBody3D = session.get("helicopter")
	if session.occupied != helicopter: session._occupy(helicopter)
	helicopter.velocity = Vector3.ZERO
	helicopter.global_position = at

## Runs until the named dialogue opens (or the step budget ends).
func _until_dialogue(service: ExploreModService, key: String, steps: int = 120) -> bool:
	for i in steps:
		if _dialogue(service).get("key","") == key: return true
		service.step(.1,false)
	return _dialogue(service).get("key","") == key

func _board(service: ExploreModService, owner: String, key: String) -> bool:
	var actors := _owned(service,owner,key)
	if actors.is_empty(): return false
	var record: Dictionary = actors[0].record
	var pose := view.traffic.actor_pose(record)
	session.pedestrian.place(Transform3D(Basis.IDENTITY,pose.origin+Vector3(0,0,.4)))
	var claim := view.traffic.claim_nearby_vehicle(pose.origin,.65)
	return not claim.is_empty() and session._select_vehicle(record.kind,claim)

func _drive_to(cell: Vector2i) -> void:
	var target := view.traffic.graph.point(cell,&"road")
	session.occupied.global_position = target+Vector3.UP*.002
	session._apply_safe_actor_pose(session.occupied,Transform3D(Basis.IDENTITY,target))

## Starts Air Patrol, accepts a single call of kind and dismisses its briefing.
func _air_call(kind: String) -> ExploreModService:
	var service := _service(["air_patrol"])
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	check(service.activate_interaction(),"Captain Vance offers calls")
	service.step(.1,false)
	check_eq(_dialogue(service).get("key",""),"offer")
	check_eq(_dialogue(service).get("choices",[]).size(),7,"shift, four calls, logbook and decline")
	service.api.interactions.choose(kind)
	check(_until_dialogue(service,"brief"),kind+" call is briefed over the radio")
	service.api.interactions.choose("go")
	_run(service,3)
	return service

func test_new_packs_are_valid_sources() -> void:
	for id in ["air_patrol","silver_express"]:
		var pack := ExploreModPack.read("res://explore_mods/"+id)
		check(pack.ok,id+" reads as a valid source pack")
		for source in ["guide.lua","far.lua","main.lua"]: check(pack.sources.has(source),id+" ships "+source)
		var runtime := ExploreModRuntime.new()
		runtime.bind([pack],ExploreModProgress.new(),7)
		check(runtime.has_owner(id),id+" starts")
		runtime.stop("test")

func test_civic_landmarks_find_road_frontage() -> void:
	var traffic := CityTraffic3D.new()
	traffic.bind_city(_loop_city())
	var queries := ExploreWorldQueries.new()
	queries.bind(traffic.graph,null)
	var from := {"x":23.5,"y":queries.route_point(Vector2i(23,17),&"pedestrian",&"road").y,"z":17.5}
	var found := func(kind: String) -> Dictionary:
		queries.request("test","world.find_landmark",{"kind":kind,"options":{"from":from}})
		for i in 64:
			var results := queries.step()
			if not results.is_empty(): return results[0]
		return {}
	var hospital: Dictionary = found.call("hospital")
	check_eq(hospital.code,"ok","a road cell beside the hospital is found")
	if hospital.code == "ok":
		check_eq(floori(hospital.data.x),30,"frontage is the road beside the hospital")
		check_between(floori(hospital.data.z),22,24)
	check_eq(found.call("police_station").code,"no_route","no police station, no match")
	check_eq(found.call("fire_station").code,"no_route")
	traffic.free()

func test_medevac_lands_beside_patient_and_flies_to_hospital() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	check(session.get("helicopter") != null,"the session parks a helicopter")
	var sim := Simulation.new()
	sim.setup(city,211)
	var sim_before := sim.snapshot().duplicate(true)
	var before := SaveFormat.encode_city(city).duplicate(true)
	var service := _air_call("medevac")
	var patient := _latest(service,"air_patrol","person")
	check(not patient.is_empty(),"a patient waits at the call")
	if patient.is_empty(): return
	var text := String(_objective(service,"air_patrol","patrol").get("text",""))
	check(text.begins_with("Patient ") or text.begins_with("Search area "),"guidance leads with where to fly: "+text)
	check(text.contains("condition"),"guidance tracks the patient's condition: "+text)
	check(text.contains("board a helicopter"),"on foot, guidance says to board a helicopter: "+text)
	# Hovering high above the patient is not a pickup.
	_fly(_pose(patient)+Vector3(.5,3,0))
	_run(service,40)
	check(_marker(service,"air_patrol","dest").is_empty(),"no pickup from a high hover")
	_fly(_pose(patient)+Vector3(.8,0,0))
	_run(service,6)
	check(_owned(service,"air_patrol","person").is_empty(),"the patient is aboard")
	check(service.runtime.diagnostics.is_empty(),"pickup runs cleanly: "+str(service.runtime.diagnostics))
	# A patient lying right beside the hospital is delivered by that landing.
	if _dialogue(service).get("key","") != "result":
		var dest := _marker(service,"air_patrol","dest")
		check(not dest.is_empty(),"the hospital is pinned")
		if dest.is_empty(): return
		check(String(dest.label).begins_with("Hospital"),String(dest.label))
		check_eq(floori(dest.target.x),30,"the pin is the hospital's road frontage")
		_fly(_point(dest.target))
		_run(service,6)
	check_eq(_dialogue(service).get("key",""),"result","landing at the hospital completes the call")
	check(String(_dialogue(service).get("speaker","")).contains("ER"),"the hospital's ER takes the patient")
	check(String(_dialogue(service).get("text","")).contains("Condition on arrival"),String(_dialogue(service).get("text","")))
	var state := _state(service,"air_patrol")
	check_eq(int(state.get("rescues",0)),1)
	check_eq(int(state.get("calls",0)),1)
	check(int(state.get("points",0)) > 10,"a quick rescue earns points")
	service.api.interactions.choose("stop")
	_run(service,4)
	check_eq(_objective(service,"air_patrol","patrol").get("status",""),"completed")
	check(service.api.interactions._owned.get("air_patrol",{}).has("patrol"),"the captain offers more calls")
	check(String(_objective(service,"air_patrol","rank").get("text","")).begins_with("Pilot rank: "))
	check_eq(SaveFormat.encode_city(city),before,"calls never write the city or treasury")
	check_eq(sim.snapshot(),sim_before,"funds, clock and simulation RNG unchanged")
	sim.free()
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")

func test_medevac_without_a_hospital_returns_to_the_pad() -> void:
	if not _setup(_loop_city(false)) or not await _enter(START): return
	session.set_physics_process(false)
	var service := _air_call("medevac")
	var patient := _latest(service,"air_patrol","person")
	if patient.is_empty():
		check(false,"patient spawns")
		return
	# A low hover lowers the ladder when there is no room to land.
	_fly(_pose(patient)+Vector3(.3,.8,0))
	_run(service,40)
	var dest := _marker(service,"air_patrol","dest")
	check(String(dest.get("label","")).begins_with("Air Patrol pad"),"no hospital: the paramedics meet you at the pad")
	if dest.is_empty(): return
	_fly(_point(dest.target))
	_run(service,6)
	check(String(_dialogue(service).get("text","")).contains("paramedics met you at the pad"))
	service.leave("test")

func test_pursuit_keeps_the_suspect_in_the_spotlight() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var service := _air_call("pursuit")
	var suspect := _latest(service,"air_patrol","suspect")
	check(not suspect.is_empty(),"a suspect car waits")
	if suspect.is_empty(): return
	check_eq(_marker(service,"air_patrol","target").get("icon",""),"vehicle")
	var start := _pose(suspect)
	_fly(start+Vector3(0,2,0))
	var moved := false
	for i in 1200:
		if _dialogue(service).get("key","") == "result": break
		if i % 3 == 0:
			var now := _latest(service,"air_patrol","suspect")
			if now.is_empty(): break
			var at := _pose(now)
			if at.distance_to(start) > 1.0: moved = true
			_fly(at+Vector3(0,2,0))
		service.step(.1,false)
	check(moved,"the suspect drives off once spotted")
	check_eq(_dialogue(service).get("key",""),"result","the chase ends")
	var text := String(_dialogue(service).get("text",""))
	check(text.contains("custody"),text)
	check_eq(int(_state(service,"air_patrol").get("arrests",0)),1)
	service.api.interactions.choose("stop")
	_run(service,40)
	check(_owned(service,"air_patrol","suspect").is_empty(),"the suspect car is taken away")
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")

func test_pursuit_suspect_escapes_when_left_alone() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var service := _air_call("pursuit")
	var suspect := _latest(service,"air_patrol","suspect")
	if suspect.is_empty():
		check(false,"suspect spawns")
		return
	_fly(_pose(suspect)+Vector3(0,2,0))
	_run(service,3)
	# Fly far away and hover: the suspect gets away after 15 seconds.
	_fly(Vector3(2.5,GROUND+3,2.5))
	var warned := false
	for i in 400:
		if _dialogue(service).get("key","") == "result": break
		if String(_objective(service,"air_patrol","patrol").get("text","")).contains("Losing him!"): warned = true
		service.step(.1,false)
	check(warned,"guidance warns while the suspect is out of the spotlight")
	var text := String(_dialogue(service).get("text",""))
	check(text.contains("lost him") or text.contains("custody"),"the chase ends either way: "+text)
	service.leave("test")

func test_traffic_report_hovers_over_each_jam() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var service := _air_call("traffic")
	var reported := 0
	for spot in 3:
		var pin := _marker(service,"air_patrol","spot")
		if pin.is_empty(): break
		check(String(pin.label).begins_with("Traffic jam "),String(pin.label))
		_fly(_point(pin.target)+Vector3(.4,2,0))
		_run(service,55)
		reported += 1
		if _dialogue(service).get("key","") == "result": break
	check(reported >= 1,"at least one jam to report")
	check_eq(_dialogue(service).get("key",""),"result","every jam reported ends the broadcast")
	check(String(_dialogue(service).get("text","")).contains("air time to spare"),"a quick broadcast stays on the air")
	check_eq(int(_state(service,"air_patrol").get("reports",0)),1)
	service.leave("test")

func test_charter_picks_up_and_lands_at_the_destination() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var service := _air_call("charter")
	var passenger := _latest(service,"air_patrol","person")
	check(not passenger.is_empty(),"a passenger waits")
	if passenger.is_empty(): return
	_fly(_pose(passenger)+Vector3(.8,0,0))
	_run(service,40)
	var dest := _marker(service,"air_patrol","dest")
	check(not dest.is_empty(),"the destination is pinned once the passenger is aboard")
	if dest.is_empty(): return
	_fly(_point(dest.target))
	_run(service,6)
	check_eq(_dialogue(service).get("key",""),"result")
	check(String(_dialogue(service).get("text","")).contains("tip "),String(_dialogue(service).get("text","")))
	check_eq(int(_state(service,"air_patrol").get("charters",0)),1)
	service.leave("test")

func test_patrol_shift_runs_three_different_calls() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var service := _service(["air_patrol"])
	check(service.activate_interaction())
	service.step(.1,false)
	service.api.interactions.choose("shift")
	check(_until_dialogue(service,"brief"),"the first radio call comes in")
	service.api.interactions.choose("go")
	_run(service,2)
	check(_owned(service,"air_patrol","captain").size() == 1,"the captain stays at the post during a shift")
	check(not service.api.interactions._owned.get("air_patrol",{}).has("patrol"),"no new shift offer mid-shift")
	service.leave("test")

func test_logbook_and_saved_progress() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var progress := ExploreModProgress.new()
	progress.commit("air_patrol",1,"1.0.0",{"calls":4,"points":120,"rescues":2,"arrests":1,"reports":1,"charters":0,"shifts":1,"best_shift":60})
	var service := _service(["air_patrol"],progress)
	check(String(_objective(service,"air_patrol","rank").get("text","")).contains("4 calls"),"the logbook journal survives reentry")
	check(service.activate_interaction())
	service.step(.1,false)
	service.api.interactions.choose("logbook")
	_run(service,2)
	check_eq(_dialogue(service).get("key",""),"logbook")
	check(String(_dialogue(service).get("text","")).contains("1 more call until Patrol Pilot"),String(_dialogue(service).get("text","")))
	service.api.interactions.choose("back")
	_run(service,2)
	service.api.interactions.choose("later")
	_run(service,2)
	check(service.api.interactions._owned.get("air_patrol",{}).has("patrol"),"declining keeps the offer")
	service.leave("test")

## Starts Silver State Express, accepts a job and dismisses its briefing.
func _courier(kind: String) -> ExploreModService:
	var service := _service(["silver_express"])
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	check(service.activate_interaction(),"Hank offers jobs")
	service.step(.1,false)
	check_eq(_dialogue(service).get("key",""),"offer")
	check_eq(_dialogue(service).get("choices",[]).size(),6)
	service.api.interactions.choose(kind)
	check(_until_dialogue(service,"brief",200),kind+" job is briefed")
	service.api.interactions.choose("go")
	_run(service,3)
	check(_board(service,"silver_express","express_pickup"),"player boards the Silver State pickup")
	_run(service,3)
	return service

func test_cross_town_rush_picks_up_then_delivers() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var before := SaveFormat.encode_city(city).duplicate(true)
	var service := _courier("rush")
	var stops := _owned(service,"silver_express","stop")
	check_eq(stops.size(),2,"a sender and a recipient")
	if stops.size() != 2: return
	check_eq(_marker(service,"silver_express","stop1").get("icon",""),"objective")
	var text := String(_objective(service,"silver_express","express").get("text",""))
	check(text.begins_with("Pick up ") and text.contains(" m "),"guidance leads with the pickup and its distance: "+text)
	# Arriving at the recipient first delivers nothing.
	_drive_to(stops[1].record.cell)
	_run(service,4)
	check(not _dialogue(service).has("key"),"the parcel has to be picked up first")
	_drive_to(stops[0].record.cell)
	_run(service,4)
	text = String(_objective(service,"silver_express","express").get("text",""))
	check(text.contains("Deliver ") and text.contains(" left"),"loaded: the clock runs to the drop: "+text)
	_drive_to(stops[1].record.cell)
	_run(service,4)
	check_eq(_dialogue(service).get("key",""),"result")
	check(String(_dialogue(service).get("text","")).contains("on time"),String(_dialogue(service).get("text","")))
	var state := _state(service,"silver_express")
	check_eq(int(state.get("jobs",0)),1)
	check_eq(int(state.get("deliveries",0)),1)
	check(int(state.get("tiles",0)) > 0,"the ledger counts road hauled")
	check_eq(int(state.get("on_time",0)),1)
	service.api.interactions.choose("done")
	_run(service,40)
	check(_owned(service,"silver_express","stop").is_empty(),"customers leave after the job")
	check(service.api.interactions._owned.get("silver_express",{}).has("counter"),"Hank offers another job")
	check_eq(SaveFormat.encode_city(city),before,"jobs never write the city or treasury")
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")

func test_milk_run_delivers_in_any_order() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var service := _courier("milk")
	var stops := _owned(service,"silver_express","stop")
	check_eq(stops.size(),3,"three recipients all at once")
	if stops.size() != 3: return
	for i in 3: check(not _marker(service,"silver_express","stop"+str(i+1)).is_empty(),"every drop is on the map")
	for index in [2,0,1]:
		_drive_to(stops[index].record.cell)
		_run(service,4)
	check_eq(_dialogue(service).get("key",""),"result","the third drop ends the run")
	check(String(_dialogue(service).get("text","")).contains("whole milk run"))
	check_eq(int(_state(service,"silver_express").get("deliveries",0)),3)
	service.leave("test")

func test_ice_melts_faster_parked_in_the_sun() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var service := _courier("ice")
	var stops := _owned(service,"silver_express","stop")
	if stops.size() != 2:
		check(false,"ice house and customer")
		return
	_drive_to(stops[0].record.cell)
	_run(service,4)
	_run(service,100)
	var text := String(_objective(service,"silver_express","express").get("text",""))
	check(text.contains("ice ") and not text.contains("ice 100%"),"the ice is melting: "+text)
	_drive_to(stops[1].record.cell)
	_run(service,4)
	check(String(_dialogue(service).get("text","")).contains("of the ice left"),String(_dialogue(service).get("text","")))
	service.leave("test")

func test_wedding_cake_rewards_a_gentle_ride() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var service := _courier("cake")
	var stops := _owned(service,"silver_express","stop")
	if stops.size() != 2:
		check(false,"bakery and chapel")
		return
	_drive_to(stops[0].record.cell)
	_run(service,4)
	_drive_to(stops[1].record.cell)
	_run(service,4)
	check(String(_dialogue(service).get("text","")).contains("not a crumb out of place"),String(_dialogue(service).get("text","")))
	service.leave("test")

func test_all_seven_built_in_packs_coexist() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var ids: Array[String] = ["desert_stroll","desert_delivery","desert_atmosphere","neon_rally","crooner_hunt","air_patrol","silver_express"]
	var service := _service(ids)
	_run(service,40)
	for id in ids: check(service.runtime.has_owner(id),id+" runs alongside the others")
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")

## The courier and air calls chain 30-tile hops outward; in an included city
## three hops end well over a kilometre from where they began.
func test_chained_hops_cross_an_included_city() -> void:
	var loaded := SaveFormat.load("res://assets/cities/La Presa.sc2d")
	check(bool(loaded.ok))
	var traffic := CityTraffic3D.new()
	traffic.bind_city(loaded.city)
	var queries := ExploreWorldQueries.new()
	queries.bind(traffic.graph,null)
	var find := func(options: Dictionary) -> Dictionary:
		queries.request("test","world.find_landmark",{"kind":"road_destination","options":options})
		for i in 200:
			var results := queries.step()
			if not results.is_empty(): return results[0]
		return {}
	var starts := [Vector2i(64,64),Vector2i(40,80),Vector2i(80,40),Vector2i(60,30)]
	var far_enough := 0
	var tried := 0
	for start: Vector2i in starts:
		var cell := start
		# Walk to the nearest supported road cell on a spiral.
		var found := false
		for radius in 12:
			for dz in range(-radius,radius+1):
				for dx in range(-radius,radius+1):
					if found: continue
					var candidate := start+Vector2i(dx,dz)
					if queries.supported(candidate,&"pedestrian",&"road"):
						cell = candidate
						found = true
		if not found: continue
		tried += 1
		var origin := {"x":cell.x+.5,"y":queries.route_point(cell,&"pedestrian",&"road").y,"z":cell.y+.5}
		var at := origin
		for hop in 3:
			var options := {"from":at,"min_distance":30}
			if hop > 0: options["away_from"] = origin
			var result: Dictionary = find.call(options)
			if result.get("code","") != "ok": break
			at = {"x":result.data.x,"y":result.data.y,"z":result.data.z}
		if Vector2(at.x,at.z).distance_to(Vector2(origin.x,origin.z)) >= 50: far_enough += 1
	check(tried >= 3,"probe starts found road")
	check(far_enough >= tried-1,"%d of %d chained routes reach 50+ tiles (800 m)" % [far_enough,tried])
	traffic.free()

## Repeat medevac calls until both kinds have flown: a known patient, and a
## search-and-rescue hiker whose pin only appears within four tiles.
func test_search_and_rescue_hides_the_hiker_until_close() -> void:
	if not _setup(_loop_city()) or not await _enter(START): return
	session.set_physics_process(false)
	var service := _air_call("medevac")
	var kinds := {}
	for flight in 8:
		var person := _latest(service,"air_patrol","person")
		if person.is_empty(): break
		var zone := _marker(service,"air_patrol","zone")
		var pin := _marker(service,"air_patrol","target")
		if zone.is_empty():
			kinds["known"] = true
			check_eq(float(pin.get("max_distance",0)),2048.0,"a known patient is always pinned")
		else:
			kinds["search"] = true
			check_eq(float(pin.get("max_distance",0)),4.0,"the hiker is only revealed up close")
			check(String(zone.label).begins_with("Search area"),String(zone.label))
		_fly(_pose(person)+Vector3(.8,0,0))
		_run(service,6)
		if _dialogue(service).get("key","") != "result":
			var dest := _marker(service,"air_patrol","dest")
			if dest.is_empty(): break
			_fly(_point(dest.target))
			_run(service,6)
		check_eq(_dialogue(service).get("key",""),"result","medevac %d completes" % (flight+1))
		if kinds.size() == 2: break
		service.api.interactions.choose("again")
		if not _until_dialogue(service,"brief"): break
		service.api.interactions.choose("go")
		_run(service,3)
	check_eq(kinds.size(),2,"both a known patient and a lost hiker were flown")
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	service.leave("test")
