# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
const ACTOR_PATH := "res://scripts/exploration/explore_pedestrian.gd"
const GROUND := 4*CityGeometry3D.HEIGHT
var fixture: Node3D
var actor: CharacterBody3D
var reports: Array[String] = []
var saved_fps: int
var saved_physics: int

# Removing session-owned ticks, yaw rotation, step sweeps, or recovery reporting
# must fail these actual-body assertions. No movement is driven by render frames.
class WalkingDriver extends Node:
	signal completed
	var actor: CharacterBody3D
	var frame := ExploreInputFrame.idle()
	var yaw := 0.0
	var ticks := 0
	var total := 120
	var jump_ticks: Array[int] = []
	var stall_tick := -1
	var samples: Array[Vector3] = []
	var velocities: Array[Vector3] = []
	var reports: Array[String] = []
	var recovery_counts: Array[int] = []
	func _physics_process(delta: float) -> void:
		frame.jump = ticks in jump_ticks
		actor.call("step",frame,yaw,.1 if ticks == stall_tick else delta)
		samples.append(actor.call("feet_position"))
		velocities.append(actor.velocity)
		recovery_counts.append(reports.size())
		ticks += 1
		if ticks >= total:
			set_physics_process(false)
			completed.emit()

func before_all() -> void:
	saved_fps = Engine.max_fps
	saved_physics = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 60

func after_all() -> void:
	Engine.max_fps = saved_fps
	Engine.physics_ticks_per_second = saved_physics

func setup(city: City = null, feet := Vector3(22.5,GROUND,22.5)) -> bool:
	check(ResourceLoader.exists(ACTOR_PATH),"pedestrian implementation exists")
	if not ResourceLoader.exists(ACTOR_PATH): return false
	fixture = Fixture.attach(self,flat_city() if city == null else city)
	var script: Script = load(ACTOR_PATH)
	actor = script.new()
	fixture.add_child(actor)
	actor.call("bind",fixture.get_node("traversal"))
	actor.position = feet
	check(actor.has_signal("recovery_requested"),"actor reports recovery to session")
	if actor.has_signal("recovery_requested"):
		actor.connect("recovery_requested",func(reason: String) -> void: reports.append(reason))
	return true

func after_each() -> void:
	if is_instance_valid(fixture): fixture.free()
	fixture = null
	actor = null
	reports.clear()
	await physics_frame

func drive(ticks: int, move := Vector2.ZERO, sprint := false, yaw := 0.0,
		jump_ticks: Array[int] = [], stall_tick := -1) -> WalkingDriver:
	var driver := WalkingDriver.new()
	driver.actor = actor
	driver.total = ticks
	driver.frame.move = move
	driver.frame.sprint = sprint
	driver.yaw = yaw
	driver.jump_ticks = jump_ticks
	driver.stall_tick = stall_tick
	driver.reports = reports
	fixture.add_child(driver)
	await driver.completed
	# Unwind the emitting driver before a caller can release its fixture.
	await process_frame
	return driver

func test_profile_and_session_own_tick() -> void:
	if not setup(): return
	await physics_frame
	check_eq(actor.collision_layer,ExploreActorProfile.ACTOR)
	check_eq(actor.collision_mask,ExploreActorProfile.WORLD|ExploreActorProfile.ACTOR)
	check(not actor.is_physics_processing(),"only session ticks locomotion")
	check_between(actor.safe_margin,.00099,.00101)
	var found := false
	for child: Node in actor.get_children():
		if child is CollisionShape3D and child.shape is CapsuleShape3D:
			found = true
			check_between(child.position.y,.05749,.05751,"feet root offsets capsule center")
	check(found,"actor owns its capsule")
	check(not actor.find_children("*","Skeleton3D",true,false).is_empty(),"owned Blender pedestrian rig attached")
	check(not actor.find_children("*","AnimationPlayer",true,false).is_empty(),"authored pedestrian clips attached")

func test_fixed_walk_sprint_and_camera_yaw() -> void:
	if not setup(): return
	await physics_frame
	await drive(5)
	var start := actor.position
	await drive(120,Vector2(0,-1))
	check_between(start.z-actor.position.z,.170,.183,"two seconds at .09 including acceleration")
	check_between(actor.position.x,start.x-.002,start.x+.002)
	check_between(actor.position.y,GROUND-.003,GROUND+.003)
	actor.call("stop_input")
	start = actor.position
	await drive(120,Vector2(0,-1),true,PI/2)
	check_between(start.x-actor.position.x,.368,.404,"sprint .20 rotates with camera yaw")
	check_between(actor.position.z,start.z-.002,start.z+.002)
	check(reports.is_empty(),"ordinary walking is supported")

func test_jump_edges_land_and_do_not_repeat_held_space() -> void:
	if not setup(): return
	await physics_frame
	await drive(5)
	var run := await drive(150,Vector2.ZERO,false,0.0,[0,90])
	var peaks := 0
	var rising := false
	var highest := GROUND
	for i: int in run.samples.size():
		var up := run.velocities[i].y > .01
		if up and not rising: peaks += 1
		rising = up
		highest = maxf(highest,run.samples[i].y)
	check_eq(peaks,2,"exactly two input edges produce two jumps")
	check_between(highest-GROUND,.025,.040,".20 jump under .613 gravity")
	check(actor.call("landed"),"jump returns to floor")
	check(reports.is_empty(),"valid jump airtime does not request recovery")

func test_curb_step_and_descent() -> void:
	if not setup(): return
	Fixture.box(fixture,Vector3(22.5,GROUND+.02,22.32),Vector3(.4,.04,.12),16)
	await physics_frame
	var run := await drive(240,Vector2(0,-1))
	var highest := GROUND
	for feet: Vector3 in run.samples: highest = maxf(highest,feet.y)
	check_between(highest-GROUND,.038,.044,"deliberately climbs .04 curb")
	check(actor.position.z<22.20,"crosses curb and descends")
	check_between(actor.position.y,GROUND-.003,GROUND+.003)
	check(reports.is_empty())

func test_taller_than_step_limit_is_blocked() -> void:
	if not setup(): return
	Fixture.box(fixture,Vector3(22.5,GROUND+.025,22.32),Vector3(.4,.05,.12),16)
	await physics_frame
	await drive(180,Vector2(0,-1))
	check(actor.position.z>=22.397,".05 obstacle exceeds .045 step budget")
	check_between(actor.position.y,GROUND-.003,GROUND+.003)

func test_building_and_parked_actor_are_solid_but_query_proxy_is_not() -> void:
	if not setup(): return
	Fixture.box(fixture,Vector3(22.5,GROUND+.2,22.32),Vector3(.4,.4,.02),4)
	Fixture.box(fixture,Vector3(22.5,GROUND+.2,22.45),Vector3(.4,.4,.02),2)
	await physics_frame
	await drive(180,Vector2(0,-1))
	check_between(actor.position.z,22.347,22.355,"building shell blocks after query proxy is passed")
	actor.position = Vector3(23.5,GROUND,22.5)
	actor.call("stop_input")
	Fixture.box(fixture,Vector3(23.5,GROUND+.15,22.32),Vector3(.4,.3,.02),32)
	await physics_frame
	await drive(180,Vector2(0,-1))
	check(actor.position.z>=22.347,"parked actor also blocks")

func test_stop_input_clears_previous_velocity() -> void:
	if not setup(): return
	await physics_frame
	await drive(60,Vector2(0,-1),true)
	actor.call("stop_input")
	var stopped := actor.position
	await drive(60)
	check(actor.position.distance_to(stopped)<.004,"idle after modal stop cannot retain locomotion")

func test_stall_sweeps_thin_wall_and_remains_finite() -> void:
	if not setup(): return
	Fixture.box(fixture,Vector3(22.5,GROUND+.2,22.47),Vector3(.4,.4,.002),16)
	await physics_frame
	var run := await drive(60,Vector2(0,-1),true,0.0,[],3)
	for feet: Vector3 in run.samples: check(feet.is_finite())
	check(actor.position.z>=22.488,".1 second stall cannot tunnel through thin obstacle")

func test_water_contact_reports_once_and_preserves_city() -> void:
	var city := flat_city()
	city.terrain.put(22,22,Terrain.SUBMERGED)
	city.set_heights(22,22,2,4)
	var before := SaveFormat.encode_city(city)
	if not setup(city,Vector3(22.5,GROUND+.001,22.5)): return
	await physics_frame
	await drive(30)
	check_eq(reports.size(),1,"wet contact latches a single bounded recovery request")
	check(actor.position.is_finite())
	check_eq(SaveFormat.encode_city(city),before,"actor never changes city")

func test_supported_dry_walk_into_water_latches_and_stops() -> void:
	var city := flat_city()
	city.terrain.put(22,22,Terrain.SUBMERGED)
	# Equal bed heights give an actual flat walking route across the boundary;
	# water sits .025 above it. A raised shore edge would test blocking instead.
	city.set_heights(22,22,4,4)
	var before := SaveFormat.encode_city(city)
	if not setup(city,Vector3(22.5,GROUND,23.10)): return
	await physics_frame
	var world := fixture.get_node("traversal") as CityTraversalWorld3D
	var exclude: Array[RID] = [actor.get_rid()]
	var initial_support := world.support_near(actor.position,.004,.048,exclude)
	check(not initial_support.is_empty(),"dry approach starts on actual collision support")
	check(not world.touches_water(actor.position),"approach spawn is explicitly dry")
	await drive(5)
	check(actor.call("landed"),"idle native steps establish supported dry feet")
	check(reports.is_empty(),"dry support does not request recovery")
	var start := actor.position
	# The driver calls native step with movement input; no test transform changes
	# occur after setup. Keep supplying input after contact to verify the latch.
	var run := await drive(180,Vector2(0,-1))
	var first_wet := -1
	var previous := start
	for index: int in run.samples.size():
		var feet := run.samples[index]
		check(feet.is_finite(),"approach and latched feet stay finite")
		check(feet.distance_to(previous)<=.003,"every native step is bounded without teleporting")
		check_between(feet.x,start.x-.002,start.x+.002,"walk stays on the approach axis")
		check_between(feet.y,GROUND-.003,GROUND+.003,"equal-height transition keeps physical floor support")
		if first_wet<0 and world.touches_water(feet): first_wet = index
		previous = feet
	check(first_wet>0,"actual movement reaches water after dry samples")
	check(first_wet<run.samples.size()-30,"contact leaves many later input steps to exercise the latch")
	check(actor.position.z<23.0,"feet cross from dry tile into submerged tile")
	check(start.z-actor.position.z>.09,"input advances a meaningful distance before water contact")
	check_eq(reports,["water"],"dry-to-water contact emits exactly one water recovery")
	if first_wet>=0:
		check_eq(run.recovery_counts[first_wet],1,"native step reports on the same tick that walking enters water")
		if first_wet>0:
			check_eq(run.recovery_counts[first_wet-1],0,"dry movement has no early recovery report")
		var contact := run.samples[first_wet]
		for index: int in range(first_wet,run.samples.size()):
			check(run.samples[index].is_equal_approx(contact),"latched water recovery stops subsequent movement input")
			check_eq(run.velocities[index],Vector3.ZERO,"latched water recovery clears velocity")
	check_eq(SaveFormat.encode_city(city),before,"dry-to-water movement preserves all encoded city bytes")

func test_render_caps_do_not_change_fixed_physics_distance() -> void:
	if not setup(): return
	await physics_frame
	var distances: Array[float] = []
	for cap: int in [30,60,120]:
		Engine.max_fps = cap
		actor.position = Vector3(22.5,GROUND,22.5)
		actor.call("stop_input")
		await drive(5)
		var start := actor.position
		await drive(120,Vector2(0,-1))
		distances.append(start.distance_to(actor.position))
		check_between(distances[-1],.170,.183,"fixed 120 ticks at render cap %d" % cap)
	check(absf(distances[0]-distances[1])<.001)
	check(absf(distances[1]-distances[2])<.001)
	Engine.max_fps = saved_fps

func test_dry_inclined_floor_transition() -> void:
	if not setup(): return
	var ramp := Fixture.box(fixture,Vector3(22.5,GROUND+.015,22.25),Vector3(.4,.01,.4),8)
	ramp.rotation.x = .1
	await physics_frame
	var run := await drive(240,Vector2(0,-1))
	var highest := GROUND
	for feet: Vector3 in run.samples:
		check(feet.is_finite())
		highest = maxf(highest,feet.y)
	check(actor.position.z<22.17,"walk advances up actual inclined collision floor")
	check_between(highest-GROUND,.026,.043,"support follows the dry slope")
	check(reports.is_empty(),"supported slope transition stays valid")

func test_step_requires_clear_headroom() -> void:
	if not setup(): return
	Fixture.box(fixture,Vector3(22.5,GROUND+.02,22.32),Vector3(.4,.04,.12),16)
	Fixture.box(fixture,Vector3(22.5,GROUND+.15,22.32),Vector3(.4,.02,.12),16)
	await physics_frame
	await drive(180,Vector2(0,-1))
	check(actor.position.z>=22.397,"curb cannot lift capsule into low overhead obstacle")
	check_between(actor.position.y,GROUND-.003,GROUND+.003)

func test_bridge_support_above_water_and_removed_support_report() -> void:
	if not setup(Fixture.bridge_city(),Vector3(22.5,GROUND+.122,20.5)): return
	await physics_frame
	await drive(60,Vector2(.2,0))
	check(reports.is_empty(),"supported bridge above water is dry")
	check_between(actor.position.y,GROUND+.117,GROUND+.125)
	fixture.get_node("traversal").clear()
	await drive(5)
	check_eq(reports.size(),1,"removed support reports once without snapping to seabed")
	check(actor.position.is_finite())

func test_nonfinite_input_and_capsule_outside_city_report() -> void:
	if not setup(): return
	await physics_frame
	var before := actor.position
	await drive(3,Vector2(NAN,0))
	check_eq(reports.size(),1,"invalid input is reported once")
	check(actor.position.is_equal_approx(before),"invalid input never reaches physics transform")
	actor.call("stop_input")
	reports.clear()
	actor.position = Vector3(.01,GROUND,22.5)
	await drive(3)
	check_eq(reports.size(),1,"capsule straddling city edge is rejected")
	check(actor.position.is_finite())

func test_steep_wall_never_becomes_support() -> void:
	if not setup(): return
	var wall := Fixture.box(fixture,Vector3(22.5,GROUND+.12,22.32),Vector3(.4,.24,.02),16)
	wall.rotation.x = .2
	await physics_frame
	await drive(180,Vector2(0,-1))
	check(actor.position.z>22.30,"near-vertical face blocks walking")
	check_between(actor.position.y,GROUND-.003,GROUND+.003,"near-vertical face cannot lift feet")
	check(reports.is_empty())
