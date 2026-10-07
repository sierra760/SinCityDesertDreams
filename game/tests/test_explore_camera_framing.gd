# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const DRAWABLE := Vector2i(1280,800)
const PLAYFIELD_BOTTOM := .72

var _original_size: Vector2i

func before_all() -> void:
	_original_size = root.size
	root.size = DRAWABLE

func after_all() -> void:
	root.size = _original_size

func test_actor_bounds_stay_above_main_footer_with_unchanged_camera_positions() -> void:
	for mode in [ExploreActorProfile.Mode.WALK,ExploreActorProfile.Mode.DRIVE,ExploreActorProfile.Mode.FLY]:
		var target := Node3D.new()
		root.add_child(target)
		target.global_position = Vector3(2,1,3)
		var rig := CityExploreCamera3D.new()
		root.add_child(rig)
		rig.configure_target(target,mode)
		rig.camera.make_current()
		for frame in 4:
			rig.update_follow(.1)
			await process_frame
		var focus := target.global_position + Vector3.UP * float(CityExploreCamera3D.FOLLOW_HEIGHT[mode])
		var direction := Vector3(sin(rig.yaw) * cos(rig.pitch),sin(rig.pitch),cos(rig.yaw) * cos(rig.pitch))
		var expected_position := focus + direction * (float(CityExploreCamera3D.FOLLOW_DISTANCE[mode]) * .995)
		check(rig.camera.global_position.is_finite(),"mode %d camera position is finite" % mode)
		check(rig.camera.global_basis.is_finite(),"mode %d camera orientation is finite" % mode)
		check(rig.camera.global_position.distance_to(expected_position) < .002,
			"mode %d keeps the established physical follow endpoint" % mode)
		var size: Vector3 = ExploreActorProfile.geometry(mode).size
		var max_y := -INF
		var min_y := INF
		for x_sign in [-1.0,1.0]:
			for y_sign in [0.0,1.0]:
				for z_sign in [-1.0,1.0]:
					var point := target.global_position + Vector3(size.x*.5*x_sign,size.y*y_sign,size.z*.5*z_sign)
					var pixel := rig.camera.unproject_position(point)
					check(pixel.is_finite(),"mode %d actor corner projects finitely" % mode)
					min_y = minf(min_y,pixel.y)
					max_y = maxf(max_y,pixel.y)
		check_ge(min_y,50.0,"mode %d actor remains below Main menu" % mode)
		check(max_y <= float(DRAWABLE.y)*PLAYFIELD_BOTTOM,
			"mode %d actor body clears Main's lower status and speed controls" % mode)
		rig.free()
		target.free()
