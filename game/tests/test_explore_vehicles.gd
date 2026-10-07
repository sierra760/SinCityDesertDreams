# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
const CAR := "res://scripts/exploration/explore_car.gd"
const HELI := "res://scripts/exploration/explore_helicopter.gd"
const GROUND := 4*CityGeometry3D.HEIGHT
var fixture: Node3D
var actor: CharacterBody3D
var reports: Array[String] = []
var saved_physics: int
var ramp_diagnostics := false

# All movement, including route following, goes through one session-owned step
# per physics tick. Transforms are assigned only to initial fixture spawn poses.
class VehicleDriver extends Node:
	signal completed
	var actor: CharacterBody3D
	var phases: Array[Dictionary] = []
	var route: Array[Vector3] = []
	var route_index := 0
	var route_reverse := false
	var total := 180
	var ticks := 0
	var stall_tick := -1
	var diagnose := false
	var diagnostic_ring: Array[Dictionary] = []
	var bad_tick := -1
	var stuck_ticks := 0
	var unchanged_waypoint_ticks := 0
	var previous_waypoint := -1
	var positions: Array[Vector3] = []
	var velocities: Array[Vector3] = []
	var speeds: Array[float] = []
	var headings: Array[float] = []
	var landings: Array[bool] = []
	func _physics_process(delta: float) -> void:
		var frame := ExploreInputFrame.idle()
		var yaw := 0.0
		var cursor := 0
		for phase: Dictionary in phases:
			cursor += int(phase.ticks)
			if ticks < cursor:
				frame.move = phase.get("move",Vector2.ZERO)
				frame.vertical = phase.get("vertical",0.0)
				frame.brake = phase.get("brake",false)
				yaw = phase.get("yaw",0.0)
				break
		if not route.is_empty():
			var feet: Vector3 = actor.call("feet_position")
			while route_index < route.size()-1 and Vector2(feet.x-route[route_index].x,feet.z-route[route_index].z).length()<.09:
				route_index += 1
			var offset := route[route_index]-feet
			var wanted := atan2(-offset.x,-offset.z)
			if route_reverse: wanted += PI
			var error := wrapf(wanted-actor.rotation.y,-PI,PI)
			# Right steer rotates forward heading clockwise; reverse changes yaw sign.
			frame.move = Vector2(clampf(-error*3.0*(-1 if route_reverse else 1),-1,1),.65 if route_reverse else -.16)
			if route_index == route.size()-1 and Vector2(offset.x,offset.z).length()<.065:
				frame.move = Vector2.ZERO
				frame.brake = true
		actor.call("step",frame,yaw,.1 if ticks == stall_tick else delta)
		positions.append(actor.call("feet_position"))
		velocities.append(actor.velocity)
		speeds.append(actor.call("speed"))
		headings.append(actor.rotation.y)
		landings.append(actor.call("landed"))
		if diagnose:
			var sample := diagnostic_sample()
			diagnostic_ring.append(sample)
			if diagnostic_ring.size()>3: diagnostic_ring.pop_front()
			if positions.size()>1 and Vector2(positions[-1].x-positions[-2].x,positions[-1].z-positions[-2].z).length()<.00001 and absf(speeds[-1])>.1:
				stuck_ticks += 1
			else: stuck_ticks = 0
			if route_index == previous_waypoint: unchanged_waypoint_ticks += 1
			else: unchanged_waypoint_ticks = 0
			previous_waypoint = route_index
			if bad_tick<0 and (bool(actor.get("_reported")) or stuck_ticks>=30 or unchanged_waypoint_ticks>=90):
				bad_tick = ticks
				for past: Dictionary in diagnostic_ring: print("RAMP_CONTACT ",past)
			elif bad_tick>=0 and ticks<=bad_tick+2: print("RAMP_CONTACT ",sample)
		ticks += 1
		if ticks >= total:
			set_physics_process(false)
			completed.emit()


	func diagnostic_sample() -> Dictionary:
		var world: Node = get_parent().get_node("traversal")
		var feet: Vector3 = actor.call("feet_position")
		var exclusions: Array[RID] = [actor.get_rid()]
		var rays: Array[Dictionary] = []
		var offsets: Array[Vector3] = [Vector3.ZERO,-actor.global_basis.z*.13,actor.global_basis.z*.13,actor.global_basis.x*.05,-actor.global_basis.x*.05]
		for offset: Vector3 in offsets:
			var hit: Dictionary = world.call("support_near",feet+offset,.045,.16,exclusions)
			rays.append({"from":feet+offset,"hit":hit})
		var corners: Array[Dictionary] = []
		var collider: CollisionShape3D = actor.get("_collider")
		for x: float in [-.06,.06]:
			for z: float in [-.14,.14]:
				var point := collider.global_transform*Vector3(x,-.04,z)
				corners.append({"from":point,"hit":world.call("support_near",point,.045,.16,exclusions)})
		var contacts: Array[Dictionary] = []
		for i: int in actor.get_slide_collision_count():
			var hit := actor.get_slide_collision(i)
			contacts.append({"point":hit.get_position(),"normal":hit.get_normal(),"travel":hit.get_travel(),"remainder":hit.get_remainder()})
		return {"tick":ticks,"waypoint":route_index,"feet":feet,"yaw":actor.rotation.y,"box_basis":collider.basis,"landed":actor.call("landed"),"floor":actor.is_on_floor(),"wall":actor.is_on_wall(),"velocity":actor.velocity,"rays":rays,"corners":corners,"contacts":contacts}

func before_all() -> void:
	saved_physics = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 60

func after_all() -> void:
	Engine.physics_ticks_per_second = saved_physics

func setup(path: String, city: City = null, feet := Vector3(22.5,GROUND,22.5), heading := 0.0) -> bool:
	check(ResourceLoader.exists(path),"vehicle implementation exists: "+path)
	if not ResourceLoader.exists(path): return false
	fixture = Fixture.attach(self,flat_city() if city == null else city)
	var script: Script = load(path)
	actor = script.new()
	fixture.add_child(actor)
	actor.call("bind",fixture.get_node("traversal"))
	actor.position = feet
	actor.rotation.y = heading
	check(actor.has_signal("recovery_requested"),"vehicle reports recovery to session")
	if actor.has_signal("recovery_requested"):
		actor.connect("recovery_requested",func(reason: String) -> void: reports.append(reason))
	return true

func after_each() -> void:
	if is_instance_valid(fixture): fixture.free()
	fixture = null
	actor = null
	reports.clear()
	await physics_frame

func drive(phases: Array[Dictionary], stall_tick := -1, route: Array[Vector3] = [], backwards := false) -> VehicleDriver:
	var driver := VehicleDriver.new()
	driver.actor = actor
	driver.phases = phases
	driver.total = 0
	for phase: Dictionary in phases: driver.total += int(phase.ticks)
	driver.stall_tick = stall_tick
	driver.route = route
	driver.route_reverse = backwards
	driver.diagnose = ramp_diagnostics and not route.is_empty()
	fixture.add_child(driver)
	await driver.completed
	await process_frame
	return driver

func test_profiles_and_external_tick_ownership() -> void:
	for entry: Array in [[CAR,1,"WheelFrontLeft"],[HELI,2,"MainRotor"]]:
		if not setup(entry[0]): continue
		await physics_frame
		check_eq(actor.collision_layer,ExploreActorProfile.ACTOR)
		check_eq(actor.collision_mask,ExploreActorProfile.WORLD|ExploreActorProfile.ACTOR)
		check(not actor.is_physics_processing(),"session alone owns vehicle physics ticks")
		check_between(actor.safe_margin,.00099,.00101)
		var found := false
		for child: Node in actor.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				found = true
				check_eq(child.shape.size,ExploreActorProfile.geometry(entry[1]).size)
				check(absf(child.position.y-ExploreActorProfile.geometry(entry[1]).foot_offset)<.00001,"feet root offsets full box")
		check(found,"full profile collision box is installed")
		check(actor.find_child(entry[2],true,false)!=null,"editable owned actor visual attached")
		await after_each()

func test_car_brakes_through_zero_before_reverse() -> void:
	if not setup(CAR): return
	await physics_frame
	var run := await drive([{"ticks":60,"move":Vector2(0,-1)},{"ticks":120,"move":Vector2(0,1)}])
	check_between(run.speeds[59],.53,.57,"one second acceleration is .55")
	check_between(run.positions[0].z-run.positions[59].z,.25,.30,"acceleration moves the body")
	var saw_zero := false
	var zero_tick := -1
	for i: int in range(60,run.speeds.size()):
		if absf(run.speeds[i])<.00001:
			saw_zero = true
			if zero_tick<0: zero_tick = i
		if run.speeds[i]<-.00001: check(saw_zero,"must stop on an actual physics tick before reversing")
	check_between(zero_tick,87,92,".55 speed takes about .5 seconds at 1.1 braking")
	if zero_tick>=0:
		check_between(run.positions[59].z-run.positions[zero_tick].z,.12,.15,"measured braking distance")
	check_between(run.speeds[-1],-.301,-.299,"reverse cap .3")
	check(run.positions[-1].z>run.positions[zero_tick if zero_tick>=0 else 90].z+.25,"reverse body motion follows braking")
	check(reports.is_empty())

func test_car_forward_cap_handbrake_and_idle_friction() -> void:
	if not setup(CAR): return
	await physics_frame
	var run := await drive([{"ticks":180,"move":Vector2(0,-1)},{"ticks":60,"brake":true},{"ticks":60}])
	check_between(run.speeds[179],1.199,1.201)
	check(absf(run.speeds[239])<.001,"handbrake arrests within .8 seconds")
	check_between(run.positions[179].z-run.positions[239].z,.30,.49,"handbrake actual stopping distance is bounded")
	check(run.positions[239].distance_to(run.positions[-1])<.003,"rest has no creep")
	var coast := await drive([{"ticks":60,"move":Vector2(0,-1)},{"ticks":180}])
	check(absf(coast.speeds[-1])<.01,"released throttle friction arrests motion")
	check(coast.positions[59].distance_to(coast.positions[-1])>.01,"coast decelerates rather than teleport-stopping")

func test_car_measured_turning_and_reverse_yaw() -> void:
	if not setup(CAR): return
	await physics_frame
	var run := await drive([{"ticks":90,"move":Vector2(.4,-.4)}])
	check(absf(run.headings[-1]-run.headings[0])>.1,"steering changes actual heading")
	check(absf(run.positions[-1].x-run.positions[0].x)>.02,"steering bends actual trajectory")
	var forward_sign := signf(run.headings[-1]-run.headings[0])
	actor.call("stop_input")
	var reverse := await drive([{"ticks":90,"move":Vector2(.4,1)}])
	check(signf(reverse.headings[-1]-reverse.headings[0]) == -forward_sign,"same steering reverses yaw response while backing")
	check(reports.is_empty())

func test_car_steering_rate_reduces_at_high_speed() -> void:
	var rates: Array[float] = []
	for throttle: float in [.3,1.0]:
		if not setup(CAR): return
		await physics_frame
		await drive([{"ticks":180,"move":Vector2(0,-throttle)}])
		var start := actor.rotation.y
		var run := await drive([{"ticks":30,"move":Vector2(.5,-throttle)}])
		var turn := absf(wrapf(run.headings[-1]-start,-PI,PI))
		rates.append(turn)
		check(turn>.01,"both actual speeds permit steering")
		await after_each()
	check(rates[1]<rates[0],"measured yaw per fixed half-second decreases at high speed")

func test_car_complete_bridge_crossing_above_water() -> void:
	# Rigid level spans own no grade: connected dry road approaches climb to the
	# deck. Start on the near-bank road and drive onto, across and off the span.
	var city := Fixture.bridge_city()
	for x: int in [18,19,24,25]: city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	var original := SaveFormat.encode_city(city)
	if not setup(CAR,city,Vector3(18.3,GROUND+.041,20.5),-PI/2): return
	await physics_frame
	var run := await drive([{"ticks":420,"move":Vector2(0,-1)}])
	check(actor.position.x>25.15,"drives entire four-cell bridge and reaches far bank road")
	var interior_samples := 0
	for feet: Vector3 in run.positions:
		if feet.x>21.2 and feet.x<22.8:
			interior_samples += 1
			check_between(feet.y,GROUND+.11,GROUND+.14,"car remains on deck over water")
	check(interior_samples>30,"route crosses both submerged interior cells")
	check(reports.is_empty(),"supported bridge never reports water")
	check_eq(SaveFormat.encode_city(city),original,"driving preserves city bytes")

func test_car_lower_underpass_floor_is_retained() -> void:
	if not setup(CAR,Fixture.underpass_city(),Vector3(22.5,GROUND+.04,20.9)): return
	await physics_frame
	var run := await drive([{"ticks":180,"move":Vector2(0,-.4)}])
	check(actor.position.z<20.05,"crosses below elevated highway")
	for feet: Vector3 in run.positions: check(feet.y<GROUND+.09,"never snaps upward to highway")
	check(reports.is_empty())

func test_car_unapproached_bridge_end_requests_bounded_recovery() -> void:
	# A rigid span with no connected approach ends in a real .12 deck edge
	# above the ground.
	var city := Fixture.bridge_city()
	var original := SaveFormat.encode_city(city)
	if not setup(CAR,city,Vector3(23.25,GROUND+.122,20.5),-PI/2): return
	await physics_frame
	var run := await drive([{"ticks":360,"move":Vector2(0,-.25)}])
	check_eq(reports,["unsupported"],"unapproached deck end requests recovery exactly once")
	check_between(actor.position.x,24.13,24.15,"request occurs as the full chassis leaves the deck edge")
	check_between(actor.position.y,GROUND+.118,GROUND+.124,"no downward teleport or unchecked terrain snap")
	check(not actor.call("has_support"),"current full chassis cannot claim the distant lower floor")
	check(run.positions[-1].distance_to(run.positions[-30])<.00001,"latched request holds pose for session recovery")
	check(actor.velocity.is_zero_approx() and absf(actor.call("speed"))<.00001,"unsupported car arrests motion")
	check_eq(SaveFormat.encode_city(city),original,"recovery request preserves city bytes")

func test_car_actual_eight_ramp_orientations_up_and_down() -> void:
	for axis: bool in [false,true]:
		for index: int in 4:
			for descending: bool in [false,true]:
				await ramp_route(index,axis,descending)

func ramp_route(index: int, axis: bool, descending: bool) -> void:
	# Independent quarter-circle centerline, not production ramp helper output.
	var pairs := [[Vector2.RIGHT,Vector2.UP],[Vector2.LEFT,Vector2.UP],[Vector2.LEFT,Vector2.DOWN],[Vector2.RIGHT,Vector2.DOWN]]
	var city := flat_city()
	city.building.put(22,22,93+index)
	city.flags.put(22,22,2 if axis else 0)
	var road: Vector2 = pairs[index][0]
	var high: Vector2 = pairs[index][1]
	if axis:
		road = Vector2(road.y,road.x)
		high = Vector2(high.y,high.x)
	var center := Vector2(22.5,22.5)
	var pivot := center+(road+high)*.5
	var route: Array[Vector3] = []
	for step: int in 17:
		var p := pivot+(-high).rotated((-high).angle_to(-road)*step/16.0)*.5
		route.append(Vector3(p.x,GROUND+.04+.34*step/16.0,p.y))
	var low := Vector3(center.x+road.x*.8,GROUND+.04,center.y+road.y*.8)
	var upper := Vector3(center.x+high.x*.8,GROUND+.38,center.y+high.y*.8)
	route.push_front(low)
	route.append(upper)
	if descending: route.reverse()
	var direction := route[1]-route[0]
	if not setup(CAR,city,route[0],atan2(-direction.x,-direction.z)): return
	# Connected approach pads meet the authored endpoints; only the
	# central curve is the actual code93..96 physical network geometry.
	for pad: Vector3 in [low,upper]:
		Fixture.box(fixture,pad-Vector3.UP*.02,Vector3(.6,.04,.6),8)
	await physics_frame
	var run := await drive([{"ticks":900}],-1,route)
	print("RAMP %d axis=%s descending=%s waypoint=%d feet=%s reports=%s speed=%s" % [index,axis,descending,run.route_index,actor.position,reports,actor.call("speed")])
	check(run.route_index>=route.size()-2,"actual route reaches far ramp endpoint %d/%s/%s" % [index,axis,descending])
	check(actor.position.distance_to(route[-1])<.16,"actual car completes ramp route")
	var lowest := INF
	var highest := -INF
	for feet: Vector3 in run.positions:
		lowest = minf(lowest,feet.y)
		highest = maxf(highest,feet.y)
	check(highest-lowest>.30,"traversal covers full lowered ramp rise/descent")
	check(reports.is_empty(),"supported authored ramp does not recover")
	await after_each()


func test_both_vehicles_sweep_thin_obstacles_during_stall() -> void:
	for path: String in [CAR,HELI]:
		if not setup(path,null,Vector3(22.5,GROUND+(.6 if path==HELI else 0.0),22.5)): continue
		Fixture.box(fixture,Vector3(22.5,GROUND+.7,21.7),Vector3(2,1.4,.002),16)
		await physics_frame
		var run := await drive([{"ticks":180,"move":Vector2(0,-1)}],90 if path==CAR else 65)
		for feet: Vector3 in run.positions:
			check(feet.is_finite())
			check(feet.z>=21.839,"full .28-long shape never crosses thin wall even at .1-second stall")
		check(reports.is_empty(),"wall collision is not lost support")
		await after_each()

func test_helicopter_takeoff_hover_release_arrest_and_landing() -> void:
	if not setup(HELI): return
	await physics_frame
	await drive([{"ticks":10}])
	check(actor.call("landed"),"initial supported landing")
	var rotor := actor.find_child("MainRotor",true,false) as Node3D
	var rotor_start := rotor.rotation.y if rotor!=null else 0.0
	var climb := await drive([{"ticks":120,"vertical":1.0,"move":Vector2(0,-.25)}])
	check(not actor.call("landed"),"takeoff changes actual support state")
	check(actor.position.y>GROUND+.6,"vertical input produces actual climb")
	for v: Vector3 in climb.velocities: check(v.y<=.501,"vertical speed cap")
	check(float(actor.call("altitude"))>.6,"HUD altitude tracks flight")
	await drive([{"ticks":120}])
	check(actor.velocity.length()<.01,"release arrests horizontal and vertical velocity")
	var hovering := actor.position
	await drive([{"ticks":120}])
	check(actor.position.distance_to(hovering)<.005,"stationary hover stays stable for two seconds")
	if rotor!=null: check(absf(wrapf(rotor.rotation.y-rotor_start,-PI,PI))>.01,"rotor continues while hovering")
	await drive([{"ticks":300,"vertical":-1.0},{"ticks":90}])
	check(actor.call("landed"),"real descent lands on physical ground")
	check(actor.velocity.length()<.01,"landed exit speed is below .01")
	check_between(actor.position.y,GROUND-.003,GROUND+.004)
	check(reports.is_empty())

func test_helicopter_camera_relative_acceleration_and_cap() -> void:
	if not setup(HELI,null,Vector3(22.5,GROUND+1.0,22.5)): return
	await physics_frame
	var run := await drive([{"ticks":180,"move":Vector2(0,-1),"yaw":PI/2}])
	check_between(run.velocities[59].length(),.96,1.04,"horizontal acceleration 1.0")
	check_between(run.velocities[-1].length(),1.49,1.51,"flight cap 1.5")
	check(run.positions[-1].x<20,"camera yaw rotates forward flight")
	check(absf(run.positions[-1].z-22.5)<.01)
	check(reports.is_empty())

func test_helicopter_under_bridge_cannot_ascend_through_deck() -> void:
	if not setup(HELI,Fixture.underpass_city(),Vector3(22.5,GROUND+.04,20.5)): return
	await physics_frame
	var run := await drive([{"ticks":180,"vertical":1.0}])
	check(run.positions[-1].y>GROUND+.10,"attempt genuinely takes off below deck")
	for feet: Vector3 in run.positions: check(feet.y+.14<GROUND+.285,"full clearance box stays under actual lowered deck underside")
	check(reports.is_empty())

func test_helicopter_lands_on_upper_deck_and_does_not_snap_lower() -> void:
	if not setup(HELI,Fixture.underpass_city(),Vector3(22.5,GROUND+1.2,20.5)): return
	await physics_frame
	await drive([{"ticks":240,"vertical":-1.0},{"ticks":60}])
	check(actor.call("landed"))
	check_between(actor.position.y,GROUND+.379,GROUND+.384,"landing retains lowered highway deck instead of lower road")
	check(reports.is_empty())

func test_water_contact_latches_but_flight_does_not() -> void:
	for path: String in [CAR,HELI]:
		var city := flat_city()
		city.terrain.put(22,22,Terrain.SUBMERGED)
		city.set_heights(22,22,2,4)
		var original := SaveFormat.encode_city(city)
		if not setup(path,city,Vector3(22.5,GROUND+(.8 if path==HELI else .001),22.5)): continue
		await physics_frame
		if path==HELI:
			await drive([{"ticks":90}])
			check(reports.is_empty(),"airborne above water is safe")
			await drive([{"ticks":180,"vertical":-1.0}])
		else: await drive([{"ticks":60}])
		check_eq(reports.size(),1,"actual wet feet request recovery once")
		check_eq(SaveFormat.encode_city(city),original,"contact never mutates city")
		await after_each()

func test_deleted_supported_floor_requests_recovery_once() -> void:
	for path: String in [CAR,HELI]:
		if not setup(path,Fixture.bridge_city(),Vector3(22.5,GROUND+.12,20.5)): continue
		await physics_frame
		await drive([{"ticks":10}])
		check(actor.call("landed"))
		fixture.get_node("traversal").call("clear")
		await drive([{"ticks":60}])
		check_eq(reports.size(),1,"removed support triggers one session recovery, including landed helicopter")
		await after_each()

func test_bounds_nonfinite_input_and_ceiling_are_bounded() -> void:
	for path: String in [CAR,HELI]:
		for kind: String in ["bounds","nan"]:
			var feet := Vector3(-.1,GROUND,22.5) if kind=="bounds" else Vector3(22.5,GROUND,22.5)
			if not setup(path,null,feet): continue
			await physics_frame
			await drive([{"ticks":30,"move":Vector2(NAN,0) if kind=="nan" else Vector2.ZERO}])
			check_eq(reports.size(),1,"invalid %s requests one recovery" % kind)
			check(actor.position.is_finite() and actor.velocity.is_finite(),"invalid input never poisons physics transform")
			await after_each()
	if not setup(HELI,null,Vector3(22.5,GROUND+7.9,22.5)): return
	await physics_frame
	var run := await drive([{"ticks":120,"vertical":1.0}])
	var ceiling: float = fixture.get_node("traversal").call("max_flight_y")
	print("CEILING max=%s first=%s final=%s reports=%s" % [ceiling,run.positions[0],run.positions[-1],reports])
	for feet: Vector3 in run.positions:
		check(feet.y+.14<=ceiling+.003,"full body obeys ceiling")
		check(feet.y>=ceiling-.143,"held ascent stays at fitted ceiling instead of retaining downward correction")
	for recorded: Vector3 in run.velocities:
		check(absf(recorded.y)<=.501,"ceiling positional correction never becomes uncapped flight velocity")

func test_stop_input_clears_both_vehicle_motion() -> void:
	for path: String in [CAR,HELI]:
		if not setup(path,null,Vector3(22.5,GROUND+(.8 if path==HELI else 0),22.5)): continue
		await physics_frame
		await drive([{"ticks":60,"move":Vector2(0,-1)}])
		actor.call("stop_input")
		var stopped := actor.position
		await drive([{"ticks":60}])
		check(actor.position.distance_to(stopped)<.004,"modal stop clears previous movement")
		check(actor.velocity.length()<.01)
		await after_each()

func test_car_safe_pose_resets_actual_tilt_and_exposes_current_shape() -> void:
	if not setup(CAR,null,Vector3(22.5,GROUND+.12,22.5)): return
	for method: String in ["collision_pose","has_support","apply_safe_pose"]:
		check(actor.has_method(method),"car public physical-pose API: "+method)
		if not actor.has_method(method): return
	var slope := Fixture.box(fixture,Vector3(22.5,GROUND+.1,22.5),Vector3(1,.02,1),8)
	slope.rotation.z = .2
	await physics_frame
	await drive([{"ticks":60}])
	var before: Transform3D = actor.call("collision_pose")
	check(before.basis.y.dot(Vector3.UP)<.995,"actual resting slope tilts car collision body")
	var collider := actor.get("_collider") as CollisionShape3D
	check_eq(before,collider.global_transform,"public shape pose reports actual pitched collider")
	check(actor.call("has_support"),"fresh support validates tilted bottom contact")
	var safe := Transform3D(Basis.IDENTITY,Vector3(24.5,GROUND+.002,24.5))
	var box_pose := safe
	box_pose.origin.y += .04
	var exclusions: Array[RID] = [actor.get_rid()]
	check(fixture.get_node("traversal").call("has_clearance",box_pose,ExploreActorProfile.shape(1),exclusions),"upright recovery candidate is independently clear")
	actor.call("apply_safe_pose",safe)
	var after: Transform3D = actor.call("collision_pose")
	check(after.is_equal_approx(box_pose),"relocation resets stale pitch before using validated upright clearance")
	check(actor.call("has_support"),"relocated car has fresh dry-ground support")
	check(actor.velocity.is_zero_approx() and absf(actor.call("speed"))<.00001,"relocation arrests velocity")
	await drive([{"ticks":30}])
	check(reports.is_empty(),"safe relocation does not trigger stale-shape recovery")

func test_car_pitched_full_body_boundary_requests_recovery() -> void:
	# A .155 root margin fits the upright yaw envelope but a .65-radian pitched
	# full box extends ~.160 toward the edge. This is a seeded physical pose,
	# not simulated movement: the check targets admission of that exact body.
	if not setup(CAR,null,Vector3(22.5,GROUND+.2,.155)): return
	var collider := actor.get("_collider") as CollisionShape3D
	collider.basis = Basis(Vector3.RIGHT,-.65)
	collider.position = collider.basis.y*.04
	var foremost := collider.global_transform*Vector3(0,.04,-.14)
	check(foremost.z<0,"fixture full pitched shape actually protrudes")
	# Add local support only for this boundary fixture outside the normal chunk.
	Fixture.box(fixture,Vector3(22.5,GROUND+.15,.155),Vector3(1,.1,1),8)
	await physics_frame
	await drive([{"ticks":5}])
	check_eq(reports,["bounds"],"actual pitched shape extent, not root radius, gates city boundary")

func test_helicopter_approaches_ceiling_from_below_with_capped_velocity() -> void:
	if not setup(HELI,null,Vector3(22.5,GROUND+7.5,22.5)): return
	await physics_frame
	var ceiling: float = fixture.get_node("traversal").call("max_flight_y")
	var run := await drive([{"ticks":180,"vertical":1.0}])
	for i: int in run.positions.size():
		check(absf(run.velocities[i].y)<=.501,"ordinary approach obeys vertical cap")
		check(run.positions[i].y+.14<=ceiling+.003,"ordinary approach preserves full-body ceiling")
		if i>0: check(run.positions[i].y>=run.positions[i-1].y-.0001,"held ascent never bounces downward")
		if i>=120: check_between(run.positions[i].y,ceiling-.143,ceiling-.137,"held ascent rests at ceiling after approach")
	check(reports.is_empty(),"normal fitted ascent is not recovery")

func test_helicopter_blocked_ceiling_correction_requests_recovery_without_tunneling() -> void:
	if not setup(HELI,null,Vector3(22.5,GROUND+7.9,22.5)): return
	var ceiling: float = fixture.get_node("traversal").call("max_flight_y")-.14
	# A new obstruction blocks the downward fit of an initially protruding
	# body. Safe response is a latched session request, not forcing it through.
	Fixture.box(fixture,Vector3(22.5,ceiling-.03,22.5),Vector3(1,.1,1),16)
	await physics_frame
	var run := await drive([{"ticks":30,"vertical":1.0}])
	check_eq(reports.size(),1,"blocked positional ceiling fit requests session recovery once")
	for feet: Vector3 in run.positions: check(feet.y>=ceiling+.019,"blocked correction cannot tunnel through floor")
	for recorded: Vector3 in run.velocities: check(absf(recorded.y)<=.501,"blocked correction retains capped velocity")
