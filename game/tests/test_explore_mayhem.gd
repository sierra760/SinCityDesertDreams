# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Explore's slapstick weapons: the walker switches between a rubber chicken,
## a custard pie, a foam mallet and empty hands; a struck ambient pedestrian
## pops into six pieces that land on the street, then hop back together
## about fifteen seconds later and rejoin the crowd exactly where it stopped. Mod
## actors are never struck, and leaving Explore puts everyone back at once.
extends "res://tests/exploration/vehicle_selection_case.gd"

const ROAD_Y := 20
const TICK := 1.0/30.0

func _road_city() -> City:
	var city := flat_city()
	for x in range(18,34): city.building.put(x,ROAD_Y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	return city

func _pedestrian(id: int, cell_x: int, t: float) -> Dictionary:
	var record := {"id":id,"type":&"pedestrian","kind":&"pedestrian","domain":&"road","cell":Vector2i(cell_x,ROAD_Y),
		"previous":Vector2i(cell_x-1,ROAD_Y),"next":Vector2i(cell_x+1,ROAD_Y),"lane":0,"t":t,"variant":id%16,
		"turns":0,"side":1.0,"speed":.09,"length":CityTrafficCatalog.dimensions(&"pedestrian").z,"stopped":true}
	view.traffic.actors.append(record)
	return record

func _session_ready() -> bool:
	if not await _setup(_road_city(),Vector3(24.5,.5,20.5)): return false
	session.car.global_position += Vector3(0,0,6)
	session.helicopter.global_position += Vector3(0,0,-6)
	check(is_instance_valid(session.mayhem),"the session owns the slapstick weapons")
	return is_instance_valid(session.mayhem)

## Stand the walker at `offset` from `record` and return the heading that
## faces it.
func _face(record: Dictionary, offset: Vector3) -> float:
	var target := view.traffic.actor_pose(record).origin
	var from := target+offset
	(session.pedestrian as ExplorePedestrian).place(Transform3D(Basis.IDENTITY,from))
	var direction := target-from
	return atan2(-direction.x,-direction.z)

func _run(seconds: float) -> void:
	for tick: int in ceili(seconds/TICK): session.mayhem.step(TICK,true)

func _knocked(record: Dictionary) -> bool:
	return view.traffic.is_knocked(int(record.id))

func test_every_crowd_variant_splits_into_six_pieces_that_form_the_body() -> void:
	for variant: int in CityTrafficCatalog.pedestrian_variants():
		var pieces := ExploreLimbKit.pieces(variant)
		var parts: Array[StringName] = []
		var top := 0.0
		var bottom := INF
		for piece: Dictionary in pieces:
			parts.append(piece.part)
			var rest: Transform3D = piece.rest
			var half: Vector3 = piece.half
			top = maxf(top,rest.origin.y+half.y)
			bottom = minf(bottom,rest.origin.y-half.y)
			check_gt((piece.mesh as ArrayMesh).get_surface_count(),0,"variant %d %s has a surface" % [variant,piece.part])
		check_eq(parts,ExploreLimbKit.PARTS,"variant %d has head, torso, arms and legs" % variant)
		check_lt(absf(bottom),.004,"variant %d pieces start at the feet" % variant)
		check(top > .09 and top < .13,"variant %d pieces stand a person tall (%.3f tiles)" % [variant,top])
		check(ExploreLimbKit.pieces(variant) == pieces,"variant %d is split once and shared" % variant)
	var head: Dictionary = ExploreLimbKit.pieces(0)[0]
	var leg: Dictionary = ExploreLimbKit.pieces(0)[4]
	check_gt((head.rest as Transform3D).origin.y,(leg.rest as Transform3D).origin.y+.05,"the head sits well above the legs")

func test_weapons_cycle_and_are_held_only_on_foot() -> void:
	if not await _session_ready(): return
	var mayhem := session.mayhem
	check_eq(mayhem.weapon,ExploreWeapons.Kind.NONE,"Explore starts empty-handed")
	var names: Array[String] = []
	for index: int in 4: names.append(mayhem.cycle_weapon())
	check_eq(names,["Rubber Chicken","Custard Pie","Foam Mallet","Empty hands"],"the weapons cycle and put away")
	mayhem.set_weapon(ExploreWeapons.Kind.MALLET)
	mayhem.step(TICK,true)
	var walker := session.pedestrian as ExplorePedestrian
	check(mayhem.debug_state().holder_visible,"the mallet is in the walker's hand")
	check(walker.visual_node().find_child("FoamMallet",true,false) != null,"held by the walker model")
	walker.set_character("man")
	mayhem.step(TICK,true)
	check(walker.visual_node().find_child("FoamMallet",true,false) != null,"a new character picks the mallet up again")
	mayhem.step(TICK,false)
	check(not mayhem.debug_state().holder_visible,"out of sight while driving or flying")

func test_rubber_chicken_pops_the_pedestrian_in_front_only() -> void:
	if not await _session_ready(): return
	# Along the sidewalk: one person ahead of the walker, one just behind,
	# both within the chicken's reach.
	var front := _pedestrian(801,25,.5)
	var behind := _pedestrian(802,25,.36)
	var yaw := _face(front,Vector3(-.07,0,0))
	check_lt(view.traffic.actor_pose(behind).origin.distance_to(session.pedestrian.global_position),ExploreWeapons.SPECS[ExploreWeapons.Kind.CHICKEN].reach,"the control is within reach")
	var mayhem := session.mayhem
	check(not mayhem.attack(yaw),"no swing with empty hands")
	mayhem.set_weapon(ExploreWeapons.Kind.CHICKEN)
	check(mayhem.attack(yaw),"the chicken swings")
	check(not mayhem.attack(yaw),"one swing at a time")
	_run(.5)
	check(_knocked(front),"the pedestrian in front pops apart")
	check(not _knocked(behind),"the one behind, outside the swing, is untouched")
	var state := mayhem.debug_state()
	check_eq(state.knocked.size(),1,"one person in pieces")
	check_eq(int(state.knocked[0].pieces),6,"six pieces")
	for visual: Dictionary in view.traffic.visual_states():
		check(visual.id != "ambient:801","and is not drawn whole")

func test_pieces_land_then_reassemble_where_the_pedestrian_stood() -> void:
	if not await _session_ready(): return
	var record := _pedestrian(811,26,.4)
	var before := view.traffic.actor_pose(record)
	var cell: Vector2i = record.cell
	var t: float = record.t
	var mayhem := session.mayhem
	mayhem.set_weapon(ExploreWeapons.Kind.CHICKEN)
	check(mayhem.attack(_face(record,Vector3(0,0,.06))),"swing")
	_run(.5)
	check(_knocked(record),"popped")
	_run(5.0)
	var lying := 0
	for piece: Dictionary in mayhem._knocked[0].pieces:
		var at: Vector3 = piece.position
		if piece.resting and absf(at.y-before.origin.y) < .03: lying += 1
	check_ge(lying,4,"most pieces come to rest on the pavement")
	_run(8.0)
	check(_knocked(record),"still in pieces after thirteen seconds")
	_run(6.0)
	check(not _knocked(record),"back together about fifteen seconds after the hit")
	check_eq(mayhem.knocked_count(),0,"no loose pieces remain")
	check_eq(record.cell,cell,"rejoins the crowd on the same cell")
	check_eq(float(record.t),t,"at the same spot")
	check(view.traffic.actor_pose(record).origin.is_equal_approx(before.origin),"exactly where it stood")
	var drawn := false
	for visual: Dictionary in view.traffic.visual_states():
		if visual.id == "ambient:811": drawn = true
	check(drawn,"and is drawn whole again")

func test_custard_pie_flies_and_hits_from_a_distance() -> void:
	if not await _session_ready(): return
	var record := _pedestrian(821,27,.5)
	var mayhem := session.mayhem
	var sounds := GameAudio.new()
	sounds.record_cues = true
	root.add_child(sounds)
	mayhem.audio = sounds
	mayhem.set_weapon(ExploreWeapons.Kind.PIE)
	var yaw := _face(record,Vector3(0,0,.3))
	check(mayhem.attack(yaw),"throw")
	_run(.25)
	check_eq(int(mayhem.debug_state().pies),1,"the pie is in the air")
	check(not _knocked(record),"not yet")
	_run(1.5)
	check(_knocked(record),"the pie knocks the pedestrian apart")
	check_eq(int(mayhem.debug_state().pies),0,"and is gone after it splats")
	for cue: StringName in [&"explore_whoosh",&"explore_splat",&"explore_pop"]:
		check(sounds.played.has(cue),"%s plays through the game's sound effects" % cue)
	mayhem.audio = null
	sounds.free()

func test_foam_mallet_pops_everyone_close_by() -> void:
	if not await _session_ready(): return
	var near_a := _pedestrian(831,25,.4)
	var near_b := _pedestrian(832,25,.6)
	var far := _pedestrian(833,31,.5)
	var mayhem := session.mayhem
	mayhem.set_weapon(ExploreWeapons.Kind.MALLET)
	var middle := (view.traffic.actor_pose(near_a).origin+view.traffic.actor_pose(near_b).origin)*.5
	(session.pedestrian as ExplorePedestrian).place(Transform3D(Basis.IDENTITY,middle+Vector3(0,0,.05)))
	check(mayhem.attack(0.0),"slam")
	_run(.3)
	check(not _knocked(near_a),"nothing before the mallet comes down")
	_run(.6)
	check(_knocked(near_a) and _knocked(near_b),"both people nearby pop apart")
	check(not _knocked(far),"someone down the street is untouched")

func test_mod_actors_are_never_struck_and_leaving_restores_everyone() -> void:
	if not await _session_ready(): return
	var scripted := _pedestrian(841,25,.5)
	scripted.mod_owner = "test_pack"
	var ordinary := _pedestrian(842,25,.6)
	var mayhem := session.mayhem
	mayhem.set_weapon(ExploreWeapons.Kind.MALLET)
	(session.pedestrian as ExplorePedestrian).place(Transform3D(Basis.IDENTITY,view.traffic.actor_pose(scripted).origin+Vector3(0,0,.03)))
	check(mayhem.attack(0.0),"slam")
	_run(1.2)
	check(not _knocked(scripted),"a mod's actor is never knocked apart")
	check(not view.traffic.knock_pedestrian(841),"nor can it be")
	check(_knocked(ordinary),"an ordinary pedestrian beside it is")
	session.leave()
	check(not view.traffic.is_knocked(842),"leaving Explore puts the pedestrian back")
	check(not is_instance_valid(session.mayhem),"and drops the weapons")

func test_knocking_is_limited_and_vehicles_are_not_pedestrians() -> void:
	if not await _session_ready(): return
	var car := {"id":851,"type":&"road","kind":&"car","domain":&"road","cell":Vector2i(28,ROAD_Y),"previous":Vector2i(27,ROAD_Y),"next":Vector2i(29,ROAD_Y),"lane":0,"t":.5,"variant":0,"turns":0,"side":1.0,"speed":1.0,"length":.28,"stopped":true}
	view.traffic.actors.append(car)
	check(not view.traffic.knock_pedestrian(851),"a car is not a pedestrian")
	var at := view.traffic.actor_pose(car).origin
	var claim: Dictionary = view.traffic.claim_nearby_vehicle(at,.05)
	check_eq(int(claim.get("id",-1)),851,"the car can be claimed for driving")
	view.traffic.restore_pedestrian(851)
	check(view.traffic.nearest_drivable_vehicle(at,.05).is_empty(),"restoring a pedestrian never releases a driven car")
	var mayhem := session.mayhem
	mayhem.set_weapon(ExploreWeapons.Kind.CHICKEN)
	for index: int in ExploreMayhem.MAX_KNOCKED+2:
		var record := _pedestrian(860+index,24,.5)
		mayhem._knock({"id":record.id,"variant":record.variant,"pose":view.traffic.actor_pose(record)},Vector3.FORWARD,ExploreWeapons.SPECS[ExploreWeapons.Kind.CHICKEN])
	check_eq(mayhem.knocked_count(),ExploreMayhem.MAX_KNOCKED,"a bounded number of people in pieces")
	check(not view.traffic.is_knocked(860),"the first one reassembled early to make room")

func test_controls_reach_the_weapons() -> void:
	var bindings := ControlBindings.new()
	var frame := ExploreInputFrame.from_keys({KEY_X:true,KEY_Z:true},{KEY_X:true,KEY_Z:true},bindings)
	check(frame.attack and frame.next_weapon,"X swings and Z switches by default")
	check(not ExploreInputFrame.from_keys({KEY_X:true},{},bindings).attack,"a swing is an edge, not a hold")
	var old := ControlBindings.DEFAULTS.duplicate(true)
	old.erase("attack")
	old.erase("next_weapon")
	old.interact = [KEY_X]
	bindings.configure(old)
	check_eq(bindings.values().interact,[KEY_X],"an older custom profile keeps its keys")
	check(bindings.values().attack != [KEY_X],"swing receives a free key")
	check(not bindings.values().next_weapon.is_empty(),"so does switching")
	var touch := ExploreTouchControls.new()
	check(touch._mode_actions().has(&"attack") and touch._mode_actions().has(&"weapon"),"touch walking shows Attack and Weapon")
	touch.set_mode(ExploreActorProfile.Mode.DRIVE)
	check(not touch._mode_actions().has(&"attack"),"not while driving")
	touch.free()

func test_sounds_are_synthesized() -> void:
	for cue: StringName in ExploreMayhemSounds.CUES:
		var sound := ExploreMayhemSounds.stream(cue)
		check(sound != null and sound.data.size() > 1000,"%s has samples" % cue)
	check(ExploreMayhemSounds.stream(&"missing") == null,"unknown cues are silent")

## World position of the walker model's right-hand bone and of its palm.
func _hand_world(walker: ExplorePedestrian) -> Transform3D:
	var model := walker.visual_node()
	var skeleton := model.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	var chain := Transform3D.IDENTITY
	var node: Node = skeleton
	while node != model:
		chain = (node as Node3D).transform*chain
		node = node.get_parent()
	var hand := model.global_transform*chain*skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
	return Transform3D(hand.basis.orthonormalized(),hand.origin)

## The point of the held weapon that belongs in the palm, in world space.
func _held_grip(kind: int) -> Vector3:
	var holder := session.mayhem._holder
	return holder.global_transform*(ExploreWeapons.grip(kind).affine_inverse()*ExploreWeapons.PALM)

func test_weapon_stays_in_the_hand_while_walking() -> void:
	if not await _session_ready(): return
	var walker := session.pedestrian as ExplorePedestrian
	var mayhem := session.mayhem
	var rest := _hand_world(walker)
	for kind: int in [ExploreWeapons.Kind.CHICKEN,ExploreWeapons.Kind.MALLET]:
		mayhem.set_weapon(kind)
		var frame := ExploreInputFrame.idle()
		frame.move = Vector2(0,-1)
		var worst := 0.0
		var hand_heights: Array[float] = []
		for tick: int in 40:
			await physics_frame
			walker.step(frame,0.0,1.0/60.0)
			mayhem.step(1.0/60.0,true)
			var hand := _hand_world(walker)
			worst = maxf(worst,_held_grip(kind).distance_to(hand*ExploreWeapons.PALM))
			hand_heights.append(hand.origin.y-walker.global_position.y)
		check_lt(worst,.0005,"%s stays in the palm on every walking tick" % ExploreWeapons.display_name(kind))
		check_gt(walker.velocity.length(),.05,"the walker was really walking")
		if kind == ExploreWeapons.Kind.MALLET:
			check_gt(hand_heights.min(),rest.origin.y-walker.global_position.y+.01,"the mallet arm is raised to the shoulder, not hanging")
			var holder := mayhem._holder
			var barrel: Vector3 = holder.global_transform*Vector3(0,.056,0)
			var behind := (barrel-walker.global_position).dot(-walker.visual_node().global_transform.basis.z)
			check_lt(behind,.0,"the barrel rests behind the shoulder, clear of the face")
	walker.stop_input()

func test_the_arm_swings_the_weapon_and_the_body_keeps_its_aim() -> void:
	if not await _session_ready(): return
	var walker := session.pedestrian as ExplorePedestrian
	var mayhem := session.mayhem
	mayhem.set_weapon(ExploreWeapons.Kind.MALLET)
	var frame := ExploreInputFrame.idle()
	frame.move = Vector2(1,0)
	for tick: int in 10:
		await physics_frame
		walker.step(frame,0.0,1.0/60.0)
		mayhem.step(1.0/60.0,true)
	var aim := 0.0
	check(mayhem.attack(aim),"slam while walking sideways")
	var heights: Array[float] = []
	var facing_error := 0.0
	for tick: int in 30:
		await physics_frame
		walker.step(frame,0.0,1.0/60.0)
		mayhem.step(1.0/60.0,true)
		heights.append(_hand_world(walker).origin.y-walker.global_position.y)
		facing_error = maxf(facing_error,absf(angle_difference(walker.visual_node().global_rotation.y,aim)))
		check_lt(_held_grip(ExploreWeapons.Kind.MALLET).distance_to(_hand_world(walker)*(Transform3D(Basis(Vector3.RIGHT,ExploreWeapons.arm_pose(ExploreWeapons.Kind.MALLET,mayhem._swing/.55 if mayhem._swing >= 0.0 else -1.0).w),Vector3.ZERO)*ExploreWeapons.PALM)),.0005,"the mallet stays in the hand through the swing")
	check_lt(facing_error,.001,"walking sideways never turns the swing away from its aim")
	check_gt(heights.max()-heights.min(),.03,"the arm lifts the mallet overhead and brings it down")
	walker.stop_input()

func test_swing_poses_start_and_end_at_the_carry_pose() -> void:
	for kind: int in [ExploreWeapons.Kind.CHICKEN,ExploreWeapons.Kind.PIE,ExploreWeapons.Kind.MALLET]:
		var carry := ExploreWeapons.arm_pose(kind)
		check(ExploreWeapons.arm_pose(kind,0.0).is_equal_approx(carry),"%s swing starts from the carry pose" % kind)
		check(ExploreWeapons.arm_pose(kind,.999).distance_to(carry) < .01,"%s swing returns to it" % kind)
		var previous := carry
		var jump := 0.0
		for step: int in 101:
			var pose := ExploreWeapons.arm_pose(kind,step/100.0)
			jump = maxf(jump,pose.distance_to(previous))
			previous = pose
		check_lt(jump,.25,"%s swing has no sudden jumps" % kind)

func test_crowd_characters_carry_and_swing_with_their_rigged_arm() -> void:
	if not await _session_ready(): return
	var walker := session.pedestrian as ExplorePedestrian
	var mayhem := session.mayhem
	for character: String in ["pedestrian_04","pedestrian_11"]:
		walker.set_character(character)
		mayhem.set_weapon(ExploreWeapons.Kind.CHICKEN)
		mayhem.step(TICK,true)
		check(not mayhem._rig_for(walker.visual_node()).is_empty(),"%s has an arm to hold with" % character)
		check_lt(_held_grip(ExploreWeapons.Kind.CHICKEN).distance_to(_hand_world(walker)*ExploreWeapons.PALM),.0005,"%s holds the chicken in the palm" % character)
		var resting := walker.visual_node().global_transform.affine_inverse()*_hand_world(walker).origin
		check(mayhem.attack(0.0),"swing")
		for tick: int in 9: mayhem.step(1.0/60.0,true)
		var swung := walker.visual_node().global_transform.affine_inverse()*_hand_world(walker).origin
		check_lt(swung.z,-.02,"%s's arm swings the chicken well out in front" % character)
		check_lt(swung.z,resting.z-.012,"and further forward than it carries it")
		for tick: int in 40: mayhem.step(1.0/60.0,true)

func test_a_single_crowd_mesh_still_holds_the_weapon_at_its_hand() -> void:
	if not await _session_ready(): return
	var mayhem := session.mayhem
	var model := ExploreActorVisual.new()
	model.configure_crowd_variant(4)
	root.add_child(model)
	check(mayhem._rig_for(model).is_empty(),"no rig")
	var crowd := model.crowd_mesh()
	var bounds := crowd.transform*crowd.mesh.get_aabb()
	var hand := mayhem._crowd_hand(model,ExploreWeapons.arm_pose(ExploreWeapons.Kind.CHICKEN))
	check(absf(hand.origin.x-bounds.end.x*.86) < .002 and hand.origin.y > bounds.position.y+bounds.size.y*.4 and hand.origin.y < bounds.position.y+bounds.size.y*.65,"the hand is at the mesh's right hand (%s)" % hand.origin)
	var swung := mayhem._crowd_hand(model,ExploreWeapons.arm_pose(ExploreWeapons.Kind.CHICKEN,.46))
	check_lt((swung.basis*Vector3(0,1,0)).z,-.5,"a swing turns the weapon out in front")
	model.free()

func test_the_throwing_arm_follows_through_after_the_pie_leaves() -> void:
	if not await _session_ready(): return
	var walker := session.pedestrian as ExplorePedestrian
	var mayhem := session.mayhem
	mayhem.set_weapon(ExploreWeapons.Kind.PIE)
	mayhem.step(TICK,true)
	check(mayhem.attack(0.0),"throw")
	var reach := 0.0
	for tick: int in 18:
		await physics_frame
		mayhem.step(1.0/60.0,true)
		if mayhem._struck:
			var hand := walker.visual_node().global_transform.affine_inverse()*_hand_world(walker).origin
			reach = minf(reach,hand.z)
	check(mayhem._struck,"the pie was released")
	check_lt(reach,-.02,"the empty hand keeps going forward after the release")

## Drives the occupied vehicle in the controller's order: hits are checked,
## then traffic bodies are placed, then the vehicle moves.
class HitDriver extends Node:
	signal completed
	var session: CityExplorationController
	var throttle := -1.0
	var limit := 150
	var ticks := 0
	var check_tick: Callable
	var hits := true
	func _physics_process(delta: float) -> void:
		if hits: session.mayhem.vehicle_hits(session.occupied,delta)
		session._sync_traffic_collision()
		var frame := ExploreInputFrame.idle()
		frame.move.y = throttle
		session.occupied.step(frame,0,delta)
		session.mayhem.step(delta,false)
		if check_tick.is_valid(): check_tick.call()
		ticks += 1
		if ticks >= limit:
			set_physics_process(false)
			completed.emit()

## The session car on the record's line `behind` tiles back, facing along it.
func _car_behind(record: Dictionary, behind: float) -> ExploreCar:
	var car := session.car as ExploreCar
	var pose := view.traffic.actor_pose(record)
	car.apply_safe_pose(Transform3D(pose.basis,pose.origin+pose.basis.z*behind+Vector3.UP*.002))
	session._occupy(car)
	session.helicopter.global_position += Vector3(0,0,-6)
	return car

func test_a_speeding_car_pops_the_pedestrian_it_hits_and_drives_on() -> void:
	if not await _setup(_road_city(),Vector3(22.5,.5,20.5)): return
	var record := _pedestrian(901,28,.5)
	record.stopped = true
	var car := _car_behind(record,2.0)
	var where := view.traffic.actor_pose(record).origin
	var hit_speed: Array[float] = [-1.0]
	var driver := HitDriver.new()
	driver.session = session
	driver.limit = 200
	driver.check_tick = func() -> void:
		if hit_speed[0] < 0.0 and _knocked(record): hit_speed[0] = absf(car.speed())
	root.add_child(driver)
	await driver.completed
	driver.queue_free()
	check(_knocked(record),"the pedestrian popped apart")
	check_gt(hit_speed[0],ExploreMayhem.VEHICLE_HIT_SPEED,"at driving speed")
	var past := (car.global_position-where).dot(-car.global_transform.basis.z)
	check_gt(past,.2,"the car drove on through where they stood")
	check_gt(absf(car.speed()),hit_speed[0]*.8,"without being stopped by them")
	var pieces: Array = session.mayhem._knocked[0].pieces
	var forward := 0
	for piece: Dictionary in pieces:
		if ((piece.position as Vector3)-where).dot(-car.global_transform.basis.z) > .02: forward += 1
	check_ge(forward,4,"the pieces were thrown ahead of the car")

func test_a_creeping_vehicle_only_nudges_and_walking_never_pops() -> void:
	if not await _setup(_road_city(),Vector3(22.5,.5,20.5)): return
	var record := _pedestrian(911,28,.5)
	var car := _car_behind(record,.16)
	var mayhem := session.mayhem
	var dt := 1.0/60.0
	var along := -car.global_transform.basis.z
	check_eq(mayhem.vehicle_hits(car,dt),0,"the first tick only learns where the car is")
	car.global_position += along*.001
	check_eq(mayhem.vehicle_hits(car,dt),0,"creeping (0.06 tiles per second) into someone does not pop them")
	check(not _knocked(record),"still whole")
	car.global_position += along*.02
	check_eq(mayhem.vehicle_hits(car,dt),1,"the same contact at 1.2 tiles per second does")
	var far := _pedestrian(912,28,.5)
	far.side = -1.0
	var gap := view.traffic.actor_pose(far).origin.distance_to(car.global_position)
	if gap > .1:
		car.global_position += along*.02
		check_eq(mayhem.vehicle_hits(car,dt),0,"someone across the road is not hit by a passing car")
	session._leave_vehicle(car.global_transform.translated(car.global_transform.basis.x*.3))
	var walker := session.pedestrian as ExplorePedestrian
	var person := _pedestrian(913,25,.5)
	walker.place(Transform3D(Basis.IDENTITY,view.traffic.actor_pose(person).origin+Vector3(0,0,.05)))
	check_eq(mayhem.vehicle_hits(walker,dt),0,"the walker is not a vehicle")
	walker.global_position += Vector3(0,0,-.05)
	check_eq(mayhem.vehicle_hits(walker,dt),0,"walking into someone never pops them")
	check(not _knocked(person),"they stay whole")

func test_without_the_hit_check_the_pedestrian_would_have_stopped_the_car() -> void:
	# Control for the drive above: the same run with hits switched off ends with
	# the car pressed against the pedestrian's body, so popping is what lets it
	# through.
	if not await _setup(_road_city(),Vector3(22.5,.5,20.5)): return
	var record := _pedestrian(921,28,.5)
	var car := _car_behind(record,2.0)
	var where := view.traffic.actor_pose(record).origin
	var driver := HitDriver.new()
	driver.session = session
	driver.limit = 200
	driver.hits = false
	root.add_child(driver)
	await driver.completed
	driver.queue_free()
	check(not _knocked(record),"nobody popped")
	var past := (car.global_position-where).dot(-car.global_transform.basis.z)
	check_lt(past,0.0,"the car is held back short of where they stand")
