# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const PATH := "res://scripts/exploration/explore_actor_detail_manager.gd"
var host: Node3D
var gameplay_host: GameHost
func after_each() -> void:
	if is_instance_valid(gameplay_host): gameplay_host.free()
	if is_instance_valid(host): host.free()
	await process_frame
func candidates(meters: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in 40:
		result.append({"id":("ambient:" if i%2==0 else "mod:")+"%03d"%i,"kind":"pedestrian" if i<24 else "bus","variant":i%16,"position":Vector3(0,0,-meters/16.0),"yaw":0.0,"speed":.09,"steering":0.0,"airborne":false,"phase":.37})
	return result
func test_hysteresis_caps_and_identity() -> void:
	check(ResourceLoader.exists(PATH),"bounded detail manager exists")
	if not ResourceLoader.exists(PATH): return
	host=Node3D.new()
	root.add_child(host)
	var camera:=Camera3D.new()
	host.add_child(camera)
	var manager: Variant=load(PATH).new()
	manager.bind(host)
	var selected: Dictionary=manager.update(candidates(17.9),camera)
	check_eq(selected.size(),24)
	check_eq(manager.debug_state().pedestrian_rigs,16)
	var first: Node3D=selected["ambient:000"]
	var pose: Dictionary=first.debug_state()
	check_eq(manager.update(candidates(25.9),camera)["ambient:000"],first)
	check_eq(first.debug_state(),pose,"selection never advances pose")
	check_eq(manager.update(candidates(26.1),camera).size(),0)
	check_eq(manager.update(candidates(17.9),camera)["ambient:000"],first,"same compatible pool allocation reused")
	manager.clear()
	check_eq(manager.debug_state().allocated,0)
func test_ties_exclusions_churn_freeze_and_resource_sharing() -> void:
	host=Node3D.new()
	root.add_child(host)
	var camera:=Camera3D.new()
	host.add_child(camera)
	var manager: Variant=load(PATH).new()
	manager.bind(host)
	var states:=candidates(17.9)
	states.reverse()
	var selected: Dictionary=manager.update(states,camera)
	check(selected.has("ambient:000"),"stable lexical ties ignore insertion order")
	check(not selected.has("mod:019"),"nearest tie cap deterministic")
	var first: ExploreActorVisual=selected["ambient:000"]
	check(first.find_children("*","Skeleton3D",true,false).size()==1,"near pedestrian uses real rig")
	var before:=first.debug_state()
	for frame in 3: await process_frame
	check_eq(first.debug_state(),before,"render frames never advance owner time")
	var batch_before:=CityTrafficCatalog.mesh_for(&"pedestrian",0)
	for iteration in 30:
		manager.update(candidates(26.1),camera)
		manager.update(candidates(17.9),camera)
	check_eq(manager.debug_state().created,24,"crossing thresholds reuses allocations")
	check_eq(CityTrafficCatalog.mesh_for(&"pedestrian",0),batch_before,"batch resources retain identity")
	states=candidates(17.9)
	states[0].excluded=true
	states[1].visible=false
	selected=manager.update(states,camera)
	check(not selected.has(states[0].id),"player/occupied exclusion")
	check(not selected.has(states[1].id),"invisible candidate excluded")
	states.remove_at(2)
	selected=manager.update(states,camera)
	check(not selected.has("ambient:002"),"freed actors removed")
	camera.rotation.y=PI
	check(manager.update(states,camera).is_empty(),"changed camera releases hidden actors")
	camera.rotation.y=0
	manager.update(states,camera)
	check(manager.update(states,null).is_empty(),"missing camera releases detail")
	manager.clear()

func test_absolute_pose_survives_demotion_and_wave_sample() -> void:
	host=Node3D.new()
	root.add_child(host)
	var camera:=Camera3D.new()
	host.add_child(camera)
	var manager: Variant=load(PATH).new()
	manager.bind(host)
	var states:=candidates(17.9)
	states.resize(1)
	states[0].speed=0.0
	states[0].gesture="wave"
	states[0].gesture_time=.5
	var visual: ExploreActorVisual=manager.update(states,camera)[states[0].id]
	var skeleton:=visual.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var hand:=skeleton.find_bone("RightHand")
	skeleton.force_update_all_bone_transforms()
	var before:=skeleton.get_bone_global_pose(hand)
	var phase: float=visual.debug_state().animation_position
	states[0].position.z=-26.1/16.0
	manager.update(states,camera)
	states[0].position.z=-17.9/16.0
	visual=manager.update(states,camera)[states[0].id]
	check_eq(visual.debug_state().animation_position,phase,"demotion never restarts wave")
	states[0].gesture_time=.8
	manager.advance(states,.3)
	skeleton.force_update_all_bone_transforms()
	check(skeleton.get_bone_global_pose(hand)!=before,"actual imported hand moves on owner sample")
	var sampled:=visual.debug_state()
	manager.advance(states,0.0)
	check_eq(visual.debug_state(),sampled,"suspended sample freezes")
	check_eq(manager.debug_state().owner_updates,1)
	states[0].gesture=""
	states[0].speed=.09
	states[0].phase=.73
	manager.advance(states,.1)
	check_eq(visual.debug_state().clip,"walk")
	check_between(visual.debug_state().gait_phase,.729,.731)
	manager.clear()

func test_shared_animation_resources_and_reverse_wheels_after_swap() -> void:
	host=Node3D.new()
	root.add_child(host)
	var a:=CityTrafficCatalog.make_nearby_visual(&"pedestrian",3)
	var b:=CityTrafficCatalog.make_nearby_visual(&"pedestrian",3)
	host.add_child(a)
	host.add_child(b)
	check(a._player.get_animation("wave")==b._player.get_animation("wave"),"dense animation resource shared between instances")
	check_eq(a._player.get_animation("wave").loop_mode,Animation.LOOP_NONE)
	check_eq(a._player.get_animation("walk").loop_mode,Animation.LOOP_LINEAR)
	var original: Node=load("res://assets/desert-dreams-traffic/pedestrian_03_detail.glb").instantiate()
	host.add_child(original)
	var original_player:=original.find_children("*","AnimationPlayer",true,false)[0] as AnimationPlayer
	check(a._player.get_animation("walk")!=original_player.get_animation("walk"),"imported source library never mutated")
	var camera:=Camera3D.new()
	host.add_child(camera)
	var manager: Variant=load(PATH).new()
	manager.bind(host)
	var states: Array[Dictionary]=[{"id":"vehicle:1","kind":"bus","variant":0,"position":Vector3(0,0,-1),"yaw":0.0,"speed":-.2,"steering":.5,"airborne":false,"phase":0.0,"distance":-.1}]
	var visual: ExploreActorVisual=manager.update(states,camera)["vehicle:1"]
	var phases: Dictionary=visual.debug_state().wheel_phases
	check(not phases.is_empty(),"real detailed wheels available")
	states[0].position.z=-2
	manager.update(states,camera)
	states[0].distance=-.2
	states[0].position.z=-1
	visual=manager.update(states,camera)["vehicle:1"]
	for key in phases: check(visual.debug_state().wheel_phases[key]!=phases[key],"reverse distance retained while demoted")
	manager.clear()

## Run with SCDD_REQUIRE_NO_LUA=1 to require complete scripting-framework absence.
## Ordinary suite runs retain the same gameplay checks.
func test_detail_assets_work_without_lua() -> void:
	var require_absent := OS.get_environment("SCDD_REQUIRE_NO_LUA") == "1"
	if require_absent:
		check(not ClassDB.class_exists(&"SCDDExploreLua"),"native dispatcher genuinely unregistered")
		_check_optional_bridge_absent()
		check(not ClassDB.class_exists(&"SCDDExploreLua"),"availability query cannot load omitted dispatcher")
	print("MODEL_NATIVE_ABSENCE_REQUIRED ",require_absent)
	host=Node3D.new()
	root.add_child(host)
	for index in 34:
		var kind: StringName=CityTrafficCatalog.KINDS[index] if index<18 else &"pedestrian"
		var variant:=maxi(0,index-18)
		var visual:=CityTrafficCatalog.make_nearby_visual(kind,variant)
		host.add_child(visual)
		check(not visual.find_children("*","MeshInstance3D",true,false).is_empty(),"revised visual "+str(index))
		check(visual.find_children("*","CollisionObject3D",true,false).is_empty(),"visual owns no collider")
		visual.sample_owned_state({"speed":.09,"phase":.37,"distance":-.25,"gesture":"","gesture_time":0.0,"steering":0.0,"airborne":false})
		for far in [false,true]: check(CityTrafficCatalog.mesh_for(kind,variant,far)!=null,"both batch tiers load")
		visual.free()
	gameplay_host=load("res://scenes/main.tscn").instantiate()
	gameplay_host.preferences_path="user://model-detail-gameplay.cfg"
	root.add_child(gameplay_host)
	var city: City=load("res://tests/test_explore_transit_network.gd").rail_city()
	for x in range(18,34): city.building.put(x,24,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	gameplay_host.begin_city(city,{},173,null)
	gameplay_host.sim.set_speed(GameClock.Speed.PAUSED)
	gameplay_host.city_view_3d.set_camera_state(Vector3(22.5,4*CityGeometry3D.HEIGHT,24.5),1,12.0)
	await physics_frame
	check(gameplay_host.explore_switch.enter(),"ordinary Main Explore entry")
	var controller:=gameplay_host.exploration
	if not controller.is_active(): return
	var before:=SaveFormat.encode_city(city).duplicate(true)
	var simulation:=gameplay_host.sim.snapshot().duplicate(true)
	var settings:=gameplay_host.preferences.duplicate(true)
	var character:=controller.pedestrian_character
	var shapes:=_collider_pins(controller)
	for frame in 4: await physics_frame
	print("MODEL_INITIAL_STATE ",JSON.stringify({"focus":root.has_focus(),"active":controller.is_active(),"suspended":controller.is_suspended(),"application_suspended":gameplay_host._application_suspended,"input_blocked":gameplay_host.is_explore_input_blocked()}))
	controller.resume()
	check(controller.is_active() and not controller.is_suspended(),"public Resume starts ordinary controller")
	if controller.is_suspended():
		await _model_checkpoint("blocked-resume")
		gameplay_host.explore_switch.leave()
		return
	for frame in 3: await physics_frame
	var start:=controller.occupied.global_position
	controller.handle_event(_model_key(KEY_W,true))
	for frame in 40: await physics_frame
	controller.handle_event(_model_key(KEY_W,false))
	check(controller.occupied.global_position.distance_to(start)>.02,"ordinary controller walking advances")
	check(not controller.is_suspended(),"walk retains ordinary active lifecycle")
	if controller.is_suspended():
		await _model_checkpoint("blocked-walk")
		gameplay_host.explore_switch.leave()
		return
	await _model_checkpoint("walking")
	var player_visual: ExploreActorVisual
	for child in controller.pedestrian.get_children():
		if child is ExploreActorVisual: player_visual=child
	check(player_visual!=null,"actual player visual exposes owner gait phase")
	if player_visual==null:
		gameplay_host.explore_switch.leave()
		return
	controller.pause()
	check(controller.is_suspended(),"public Pause suspends ordinary controller")
	var paused:=controller.occupied.global_transform
	var paused_phase: float=player_visual.debug_state().gait_phase
	# The same W event already moved this actor; suspension must reject it.
	controller.handle_event(_model_key(KEY_W,true))
	for frame in 20: await physics_frame
	controller.handle_event(_model_key(KEY_W,false))
	check_eq(controller.occupied.global_transform,paused,"pause rejects normally effective walking input")
	check_eq(player_visual.debug_state().gait_phase,paused_phase,"pause freezes real owner gait phase")
	print("MODEL_PAUSE_PROOF ",JSON.stringify({"suspended":controller.is_suspended(),"position_unchanged":controller.occupied.global_transform==paused,"phase_before":paused_phase,"phase_after":player_visual.debug_state().gait_phase}))
	controller.resume()
	check(controller.is_active() and not controller.is_suspended(),"public Resume restores ordinary active controller")
	if not controller.is_active() or controller.is_suspended():
		print("MODEL_RESUME_BLOCKED_GUARD")
		await _model_checkpoint("blocked-pause-resume")
		gameplay_host.explore_switch.leave()
		return
	# Public Resume rearms input until an ordinary released-key frame.
	for frame in 3: await physics_frame
	var resumed_start:=controller.occupied.global_position
	var resumed_phase: float=player_visual.debug_state().gait_phase
	controller.handle_event(_model_key(KEY_W,true))
	for frame in 20: await physics_frame
	controller.handle_event(_model_key(KEY_W,false))
	check(not controller.is_suspended(),"resumed walk retains ordinary active lifecycle")
	check(controller.occupied.global_position.distance_to(resumed_start)>.01,"public Resume permits renewed walking")
	check(player_visual.debug_state().gait_phase!=resumed_phase,"resumed walking advances real owner gait phase")
	print("MODEL_RESUME_PROOF ",JSON.stringify({"suspended":controller.is_suspended(),"distance":controller.occupied.global_position.distance_to(resumed_start),"phase_before":resumed_phase,"phase_after":player_visual.debug_state().gait_phase}))
	if controller.is_suspended():
		await _model_checkpoint("blocked-resumed-walk")
		gameplay_host.explore_switch.leave()
		return
	# Set only the QA starting position beside the normally parked car.
	controller.pedestrian.global_position=controller.car.global_position+Vector3(.15,0,0)
	check(controller.request_interaction(),"ordinary car interaction")
	check_eq(controller.mode,ExploreActorProfile.Mode.DRIVE)
	start=controller.occupied.global_position
	controller.handle_event(_model_key(KEY_W,true))
	for frame in 40: await physics_frame
	controller.handle_event(_model_key(KEY_W,false))
	check(controller.occupied.global_position.distance_to(start)>.01,"ordinary controller driving advances")
	await _model_checkpoint("driving")
	for frame in 90: await physics_frame
	check(controller.request_interaction(),"ordinary car exit")
	var transit: ExploreTransitService=controller.transit_service
	var station: Dictionary=transit.network.stations[0]
	controller.pedestrian.global_position=station.platform+Vector3.UP*.002
	for frame in 1200:
		await physics_frame
		if transit.state=="boarding": break
	check_eq(transit.state,"boarding","ordinary controller advances transit to open doors")
	await _model_checkpoint("transit-boarding")
	var toward: Vector3=-Vector3(station.normal)
	controller.camera_rig.yaw=atan2(-toward.x,-toward.z)
	controller.handle_event(_model_key(KEY_W,true))
	for frame in 200:
		await physics_frame
		if transit.train.contains(controller.pedestrian.global_position): break
	# Continue beyond the threshold so the rider clears the closing door.
	for frame in 35: await physics_frame
	controller.handle_event(_model_key(KEY_W,false))
	check(transit.train.contains(controller.pedestrian.global_position),"ordinary controller walks through train doorway")
	if transit.train.contains(controller.pedestrian.global_position):
		var departed:=false
		for frame in 900:
			await physics_frame
			if transit.speed>.1:
				departed=true
				break
		check(departed,"ordinary transit departs with player")
		check(transit.train.contains(controller.pedestrian.global_position),"rider remains in moving cabin")
		await _model_checkpoint("transit-riding")
	check_eq(_collider_pins(controller),shapes,"visuals preserve exact physical shape geometry")
	check_eq(SaveFormat.encode_city(city),before,"all city layers preserved")
	check_eq(gameplay_host.sim.snapshot(),simulation,"paused simulation and RNG preserved")
	check_eq(gameplay_host.preferences,settings,"actor selection settings preserved")
	check_eq(controller.pedestrian_character,character)
	if require_absent:
		check(not ClassDB.class_exists(&"SCDDExploreLua"),"ordinary gameplay never loads native dispatcher")
		_check_optional_bridge_absent()
	gameplay_host.explore_switch.leave()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://model-detail-gameplay.cfg"))

func _model_key(code: Key, pressed: bool) -> InputEventKey:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	return event

func _collider_pins(controller: CityExplorationController) -> Array:
	var result: Array=[]
	for actor: CharacterBody3D in [controller.pedestrian,controller.car,controller.helicopter]:
		var items: Array=[]
		for child in actor.get_children():
			if child is CollisionShape3D:
				var shape: Shape3D=child.shape
				items.append([shape.get_class(),shape.margin,shape.height if shape is CapsuleShape3D else shape.size,shape.radius if shape is CapsuleShape3D else 0])
		result.append(items)
	return result

func _model_checkpoint(_label: String) -> void:
	pass

func _check_optional_bridge_absent() -> void:
	var bridge_path := "res://scripts/exploration/mods/explore_lua_bridge.gd"
	if ResourceLoader.exists(bridge_path):
		var bridge: Variant = load(bridge_path)
		check(not bridge.available(),"optional native bridge unavailable")
	check(not ClassDB.class_exists(&"SCDDExploreLua"),"optional query never registers native class")

func test_ambient_clock_samples_once_and_render_never_advances() -> void:
	host=Node3D.new()
	root.add_child(host)
	var traffic:=CityTraffic3D.new()
	host.add_child(traffic)
	var city: City=load("res://tests/test_explore_transit_network.gd").rail_city()
	for x in range(18,34): city.building.put(x,24,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	traffic.bind_city(city)
	traffic.graph.refresh()
	traffic._reconcile()
	traffic.actors.clear()
	traffic.actors.append({"id":1,"type":&"pedestrian","kind":&"pedestrian","domain":&"road","cell":Vector2i(23,24),"previous":Vector2i(22,24),"next":Vector2i(24,24),"lane":0,"t":.5,"variant":0,"turns":0,"side":1.0,"speed":.09,"length":.02,"stopped":false})
	traffic.set_detail_enabled(true)
	var camera:=Camera3D.new()
	host.add_child(camera)
	var point:=traffic.actor_pose(traffic.actors[0]).origin
	camera.position=point+Vector3(0,.1,.8)
	camera.look_at(point+Vector3(0,.05,0))
	traffic._render(camera)
	check_eq(traffic.detail_manager.debug_state().detailed_count,1)
	var updates:=int(traffic.detail_manager.debug_state().owner_updates)
	traffic._step(.1)
	check_eq(traffic.detail_manager.debug_state().owner_updates,updates+1,"exactly one model sample per traffic tick")
	check_eq(traffic.visual_states()[0].visual_time,.1,"one clock advance per traffic tick")
	var state:=traffic.visual_states().duplicate(true)
	for frame in 5: traffic._render(camera)
	check_eq(traffic.visual_states(),state,"render selection preserves every owner state")
	check_eq(traffic.detail_manager.debug_state().owner_updates,updates+1)
	traffic.set_detail_enabled(false)
	check(traffic.detail_manager==null,"disabling frees the pool")
