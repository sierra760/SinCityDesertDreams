# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

## How the flown Explore helicopter feels. Each physics tick steps the
## helicopter with the follow camera's yaw and then updates that camera, in the
## same order as the exploration controller.

const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
const GROUND := 4*CityGeometry3D.HEIGHT
const START := Vector3(22.5,GROUND+1.2,22.5)

var fixture: Node3D
var heli: ExploreHelicopter
var rig: CityExploreCamera3D
var saved_physics: int


class Pilot extends Node:
	signal completed
	var heli: ExploreHelicopter
	var rig: CityExploreCamera3D
	var phases: Array[Dictionary] = []
	var ticks := 0
	var total := 0
	var samples: Array[Dictionary] = []
	func _physics_process(delta: float) -> void:
		var frame := ExploreInputFrame.idle()
		var cursor := 0
		for phase: Dictionary in phases:
			cursor += int(phase.ticks)
			if ticks < cursor:
				frame.move = phase.get("move",Vector2.ZERO)
				frame.vertical = phase.get("vertical",0.0)
				var orbit: float = phase.get("orbit",0.0)
				if orbit != 0.0: rig.orbit(Vector2(orbit,0),1.0,false)
				break
		heli.step(frame,rig.yaw,delta)
		rig.update_follow(delta)
		var visual: Node3D = heli.get("_visual")
		var rotor := visual.find_child("MainRotor",true,false) as Node3D
		samples.append({"position":heli.global_position,"velocity":heli.velocity,"yaw":heli.rotation.y,
			"camera_yaw":rig.yaw,"visual":visual.basis,"landed":heli.landed(),"altitude":heli.altitude(),
			"rotor":rotor.rotation.y if rotor != null else 0.0})
		ticks += 1
		if ticks >= total:
			set_physics_process(false)
			completed.emit()


func before_all() -> void:
	saved_physics = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 60


func after_all() -> void:
	Engine.physics_ticks_per_second = saved_physics


func setup(feet: Vector3 = START, heading: float = 0.0) -> void:
	fixture = Fixture.attach(self,flat_city())
	heli = ExploreHelicopter.new()
	fixture.add_child(heli)
	heli.bind(fixture.get_node("traversal"))
	heli.position = feet
	heli.rotation.y = heading
	rig = CityExploreCamera3D.new()
	fixture.add_child(rig)
	rig.configure_target(heli,2)
	rig.yaw = heading
	rig.update_follow(0)


func after_each() -> void:
	if is_instance_valid(fixture): fixture.free()
	fixture = null
	heli = null
	rig = null
	await physics_frame


func fly(phases: Array[Dictionary]) -> Array[Dictionary]:
	var pilot := Pilot.new()
	pilot.heli = heli
	pilot.rig = rig
	pilot.phases = phases
	for phase: Dictionary in phases: pilot.total += int(phase.ticks)
	fixture.add_child(pilot)
	await pilot.completed
	await process_frame
	var samples := pilot.samples
	pilot.queue_free()
	return samples


static func horizontal(v: Vector3) -> Vector2:
	return Vector2(v.x,v.z)


## Nose-down pitch and left-wing-down bank of the drawn helicopter, radians.
static func attitude(visual: Basis) -> Vector2:
	var forward := -visual.z
	return Vector2(asin(clampf(-forward.y,-1,1)),asin(clampf(visual.x.y,-1,1)))


func _at_most(actual: float, limit: float, message: String) -> void:
	check(actual <= limit,"%s (%.4f > %.4f)" % [message,actual,limit])


func test_held_sideways_input_flies_straight_instead_of_circling() -> void:
	setup()
	await physics_frame
	var run := await fly([{"ticks":360,"move":Vector2(1,0)}])
	var camera_turn := 0.0
	var worst := 0.0
	for i: int in range(1,run.size()):
		camera_turn += absf(angle_difference(float(run[i-1].camera_yaw),float(run[i].camera_yaw)))
		var v := horizontal(run[i].velocity)
		if v.length() > .5: worst = maxf(worst,absf(v.angle_to(Vector2(1,0))))
	_at_most(camera_turn,.05,"the view is not dragged round by the helicopter's nose")
	_at_most(worst,deg_to_rad(5.0),"held right flies right, not round in circles")
	check(run[-1].position.x > START.x+5.0,"and actually travels to the right")


func test_held_back_input_backs_away_without_spinning() -> void:
	setup()
	await physics_frame
	var run := await fly([{"ticks":300,"move":Vector2(0,1)}])
	var spin := 0.0
	var worst := 0.0
	for i: int in range(1,run.size()):
		spin += absf(angle_difference(float(run[i-1].yaw),float(run[i].yaw)))
		var v := horizontal(run[i].velocity)
		if v.length() > .3: worst = maxf(worst,absf(v.angle_to(Vector2(0,1))))
	_at_most(spin,.05,"backing up keeps the nose pointed away from the camera")
	_at_most(worst,deg_to_rad(5.0),"back input moves toward the camera")


func test_speed_changes_are_eased_and_capped() -> void:
	setup()
	await physics_frame
	var run := await fly([{"ticks":240,"move":Vector2(0,-1)},{"ticks":150}])
	var dt := 1.0/60.0
	var jerk := 0.0
	var top := 0.0
	for i: int in range(2,run.size()):
		var a1 := (horizontal(run[i-1].velocity)-horizontal(run[i-2].velocity))/dt
		var a2 := (horizontal(run[i].velocity)-horizontal(run[i-1].velocity))/dt
		jerk = maxf(jerk,(a2-a1).length())
		top = maxf(top,horizontal(run[i].velocity).length())
	_at_most(jerk,.4,"acceleration never jumps from one tick to the next")
	check_between(horizontal(run[239].velocity).length(),1.47,1.5,"full speed is reached")
	_at_most(top,1.5,"flight speed cap")
	_at_most(horizontal(run[-1].velocity).length(),.01,"release still arrests the helicopter")


func test_helicopter_leans_into_acceleration_and_turns() -> void:
	setup()
	await physics_frame
	var run := await fly([{"ticks":60},{"ticks":90,"move":Vector2(0,-1)},{"ticks":120,"move":Vector2(0,-1),"orbit":-6.0},{"ticks":180}])
	var hover := attitude(run[50].visual)
	_at_most(absf(hover.x)+absf(hover.y),deg_to_rad(1.0),"level in a still hover")
	check_gt(attitude(run[100].visual).x,deg_to_rad(5.0),"nose dips while speeding up")
	var turn_rate := 0.0
	var banked := 0
	for i: int in range(151,270):
		var rate := angle_difference(float(run[i-1].yaw),float(run[i].yaw))*60.0
		turn_rate = maxf(turn_rate,absf(rate))
		if absf(rate) > .5 and signf(attitude(run[i].visual).y) == signf(rate) and absf(attitude(run[i].visual).y) > deg_to_rad(3.0): banked += 1
	check_gt(absf(angle_difference(float(run[150].yaw),float(run[269].yaw))),.5,"the nose follows the new direction of travel")
	_at_most(turn_rate,1.85,"turns at a flying rate")
	check_gt(banked,10,"banks into the turn")
	var settled := attitude(run[-1].visual)
	_at_most(absf(settled.x)+absf(settled.y),deg_to_rad(1.0),"levels out again in the hover")


func test_landing_touches_down_softly_and_sits_level() -> void:
	setup(Vector3(22.5,GROUND+.6,22.5))
	await physics_frame
	var run := await fly([{"ticks":360,"vertical":-1.0},{"ticks":30}])
	var touchdown := -1
	for i: int in run.size():
		if bool(run[i].landed):
			touchdown = i
			break
	check(touchdown > 0,"the helicopter lands")
	if touchdown > 0:
		_at_most(-float(run[touchdown-1].velocity.y),.12,"it flares rather than dropping onto its skids")
	var level := attitude(run[-1].visual)
	_at_most(absf(level.x)+absf(level.y),deg_to_rad(.5),"parked level on its skids")


func test_rotor_spools_up_on_boarding_and_winds_down_after_exit() -> void:
	setup(Vector3(22.5,GROUND,22.5))
	await physics_frame
	var run := await fly([{"ticks":120}])
	var early := absf(angle_difference(float(run[0].rotor),float(run[5].rotor)))
	var late := absf(angle_difference(float(run[110].rotor),float(run[115].rotor)))
	check(early < late*.6,"the rotor starts slowly and spools up (%.3f then %.3f)" % [early,late])
	var visual: Node3D = heli.get("_visual")
	var rotor := visual.find_child("MainRotor",true,false) as Node3D
	# Left alone (no longer stepped), sampled over six real seconds.
	var times: Array[int] = []
	var phases: Array[float] = []
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec()-started < 6000:
		await process_frame
		times.append(Time.get_ticks_msec()-started)
		phases.append(rotor.rotation.y)
	var moved := 0.0
	var resting := 0.0
	for i: int in range(1,phases.size()):
		var turn := absf(angle_difference(phases[i-1],phases[i]))
		if times[i] <= 400: moved += turn
		if times[i] >= 5000: resting += turn
	check(moved > .5,"left alone it keeps turning for a moment (%.3f rad in 0.4 s)" % moved)
	_at_most(resting,.0001,"and comes to rest")
