# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Continuous close-wall movement must not flip the rendered camera aim.
extends "res://tests/exploration/async_test_case.gd"

var _original_size: Vector2i

func before_all() -> void:
	_original_size = root.size
	root.size = Vector2i(1280,800)

func after_all() -> void:
	root.size = _original_size

func test_close_wall_follow_keeps_a_continuous_aim() -> void:
	for separation in [.04,.10]:
		var wall := StaticBody3D.new()
		wall.collision_layer = 16
		wall.collision_mask = 0
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(.12,.5,.005)
		collider.shape = box
		wall.add_child(collider)
		root.add_child(wall)
		wall.position = Vector3(0,.15,separation)
		var target := Node3D.new()
		root.add_child(target)
		var rig := CityExploreCamera3D.new()
		root.add_child(rig)
		rig.configure_target(target,ExploreActorProfile.Mode.WALK)
		rig.camera.make_current()
		rig.set_chrome_insets(50,190)
		var recoveries: Array[int] = []
		rig.recovery_requested.connect(func() -> void: recoveries.append(1))
		await physics_frame
		target.position.x = -.06
		rig.update_follow(.1)
		var previous := rig.camera.global_basis.get_rotation_quaternion()
		var maximum_turn := 0.0
		var clear := true
		for tick in 241:
			target.position.x = -.06 + float(tick)*.0005
			rig.update_follow(1.0/60.0)
			var current := rig.camera.global_basis.get_rotation_quaternion()
			maximum_turn = maxf(maximum_turn,rad_to_deg(previous.angle_to(current)))
			previous = current
			clear = clear and rig._point_clear(rig.camera.global_position)
		check(maximum_turn < 2.0,"tiny wall-parallel steps keep camera aim continuous: separation=%s max=%s degrees" % [separation,maximum_turn])
		check(clear,"continuous camera path remains sphere clear")
		check_eq(recoveries.size(),0,"camera framing never recovers a clear target")
		check(rig.camera.current,"Explore camera keeps viewport ownership")
		rig.free()
		target.free()
		wall.free()
		await physics_frame

func test_leaving_wall_clearance_eases_instead_of_popping_out() -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 16
	wall.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.12,.5,.005)
	collider.shape = box
	wall.add_child(collider)
	root.add_child(wall)
	wall.position = Vector3(0,.15,.06)
	var target := Node3D.new()
	root.add_child(target)
	var rig := CityExploreCamera3D.new()
	root.add_child(rig)
	rig.configure_target(target,0)
	rig.camera.make_current()
	rig.set_chrome_insets(50,190)
	await physics_frame
	rig.update_follow(.1)
	var previous := rig.camera.global_position
	var maximum_move := 0.0
	var clear := true
	for tick in 201:
		target.position.x = float(tick)*.0005
		rig.update_follow(1.0/60.0)
		maximum_move = maxf(maximum_move,previous.distance_to(rig.camera.global_position))
		previous = rig.camera.global_position
		clear = clear and rig._point_clear(previous)
	check(maximum_move < .055,"clearing a wall releases the camera smoothly: max=%s tiles" % maximum_move)
	check(clear,"eased wall release stays sphere clear")
	check(rig.camera.global_position.z > .30,"camera eventually regains its normal stand-off")
	rig.free()
	target.free()
	wall.free()
	await physics_frame

func test_near_lens_framing_remains_continuous_for_each_actor_and_display() -> void:
	for dimensions in [Vector2i(1280,800),Vector2i(640,400),Vector2i(2560,1600)]:
		root.size = dimensions
		for mode in [0,1,2]:
			var target := Node3D.new()
			root.add_child(target)
			target.rotation.y = .7
			var rig := CityExploreCamera3D.new()
			root.add_child(rig)
			rig.configure_target(target,mode)
			rig.camera.make_current()
			rig.set_chrome_insets(float(dimensions.y)*.0625,float(dimensions.y)*.2375)
			var previous := Quaternion.IDENTITY
			var maximum_turn := 0.0
			var finite := true
			for tick in 800:
				rig.camera.global_position = Vector3(0,.14,.01+float(tick)*.001)
				rig._frame_actor()
				var current := rig.camera.global_basis.get_rotation_quaternion()
				if tick>0: maximum_turn = maxf(maximum_turn,rad_to_deg(previous.angle_to(current)))
				previous = current
				finite = finite and rig.camera.global_basis.is_finite()
			check(maximum_turn<2.0,"near-lens actor framing is continuous: mode=%s size=%s max=%s" % [mode,dimensions,maximum_turn])
			check(finite,"near-lens orientation stays finite")
			rig.free()
			target.free()

func test_embedded_focus_keeps_the_overlap_checked_fallback() -> void:
	var target := Node3D.new()
	root.add_child(target)
	var rig := CityExploreCamera3D.new()
	root.add_child(rig)
	rig.configure_target(target,0)
	var wall := StaticBody3D.new()
	wall.collision_layer = 16
	wall.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.04,.04,.08)
	collider.shape = shape
	wall.add_child(collider)
	root.add_child(wall)
	wall.position = Vector3(0,.10,0)
	await physics_frame
	rig.camera.global_position = Vector3(.0321,.10,0)
	rig._has_position = true
	check(rig._point_clear(rig.camera.global_position),"previous camera is outside the new solid")
	var recoveries: Array[int] = []
	rig.recovery_requested.connect(func() -> void: recoveries.append(1))
	rig.update_follow(0)
	check(rig._point_clear(rig.camera.global_position),"embedded focus cannot replace the clear fallback with an overlapping eased arm")
	check_eq(recoveries.size(),1,"embedded target still requests traversal recovery")
	rig.free()
	target.free()
	wall.free()
	await physics_frame

func test_city_coordinate_wall_release_does_not_linger_then_flip() -> void:
	root.size = Vector2i(1280,800)
	var base := Vector3(22.5,2.4903,20.50003)
	var wall := StaticBody3D.new()
	wall.collision_layer = 16
	wall.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.12,.5,.005)
	collider.shape = box
	wall.add_child(collider)
	root.add_child(wall)
	wall.position = base+Vector3(0,.15,.04)
	var target := Node3D.new()
	root.add_child(target)
	target.global_position = base+Vector3(-.06,0,0)
	var rig := CityExploreCamera3D.new()
	root.add_child(rig)
	rig.configure_target(target,0)
	rig.camera.make_current()
	rig.set_chrome_insets(50,190)
	await physics_frame
	for warmup in 8: rig.update_follow(1.0/60.0)
	var previous := rig.camera.global_basis.get_rotation_quaternion()
	var maximum_turn := 0.0
	var maximum_lag := 0.0
	for tick in 181:
		target.position = base+Vector3(-.06+float(tick)*.0015, .000085 if tick%2==0 else -.000085,0)
		target.rotation.y = PI*.5
		rig.update_follow(1.0/60.0)
		var current := rig.camera.global_basis.get_rotation_quaternion()
		maximum_turn = maxf(maximum_turn,rad_to_deg(previous.angle_to(current)))
		if target.position.x < base.x+.11:
			maximum_lag = maxf(maximum_lag,absf(rig.camera.global_position.x-target.global_position.x))
		previous = current
	check(maximum_turn<10.0,"normal-speed steps at city coordinates never flip camera aim: max=%s degrees" % maximum_turn)
	check(maximum_lag<.01,"released camera keeps up with wall-parallel movement: lag=%s tiles" % maximum_lag)
	rig.free()
	target.free()
	wall.free()
	await physics_frame

func test_released_camera_regains_full_standoff() -> void:
	var target := Node3D.new()
	root.add_child(target)
	var rig := CityExploreCamera3D.new()
	root.add_child(rig)
	rig.configure_target(target,0)
	var wall := StaticBody3D.new()
	wall.collision_layer = 16
	wall.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(.22,.5,.035)
	collider.shape = box
	wall.add_child(collider)
	root.add_child(wall)
	wall.position = Vector3(0,.15,.18)
	await physics_frame
	rig.update_follow(.1)
	wall.free()
	await physics_frame
	for tick in 180: rig.update_follow(1.0/60.0)
	var focus := Vector3(0,.10,0)
	check(absf(rig.camera.global_position.distance_to(focus)-.34825)<.002,
		"wall release returns to full collision-clear follow distance: length=%s" % rig.camera.global_position.distance_to(focus))
	rig.orbit(Vector2(20,0),1.0,false)
	for tick in 60: rig.update_follow(1.0/60.0)
	check(absf(rig.camera.global_position.distance_to(focus)-.34825)<.002,
		"ordinary orbit keeps full stand-off after release")
	rig.free()
	target.free()
