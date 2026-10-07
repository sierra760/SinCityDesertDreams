# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
const Quality := preload("res://scripts/view/city_render_quality.gd")

func test_mobile_shadow_focus_and_camera_handoff() -> void:
	check(Quality.new().has_method("apply_shadow_focus"), "camera-aware shadow focus exists")
	if not Quality.new().has_method("apply_shadow_focus"): return
	var view := CityView3D.new()
	root.add_child(view)
	view.set_camera_state(Vector3(64,8,64),0,10)
	var sun: DirectionalLight3D
	var environment: Environment
	for child: Node in view.world.get_children():
		if child is DirectionalLight3D: sun = child
		if child is WorldEnvironment: environment = child.environment
	var mobile := RenderingServer.get_current_rendering_method() == "mobile"
	var planes := [view.camera.near, view.camera.far]
	for quality: String in ["high","balanced","performance"]:
		view.set_render_options(quality,100)
		check_eq(sun.shadow_enabled,quality != "performance")
		check_eq(sun.directional_shadow_max_distance,320.0 if quality == "balanced" else 400.0)
		check(is_equal_approx(sun.light_energy,0.7 if mobile else 0.325))
		check(is_equal_approx(environment.ambient_light_energy,0.4 if mobile else 0.195))
		if mobile and quality != "performance":
			check_eq(sun.directional_shadow_mode,DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
			check(sun.directional_shadow_split_2 * view.camera.far < view.camera.position.distance_to(view.center))
			check(sun.directional_shadow_split_3 * view.camera.far > view.camera.position.distance_to(view.center))
	view.set_render_options("high",100)
	var close_splits := Vector3(sun.directional_shadow_split_1,sun.directional_shadow_split_2,sun.directional_shadow_split_3)
	view.set_camera_state(view.center,2,180)
	if mobile:
		check(sun.directional_shadow_split_1 < close_splits.x,"overview expands shadow coverage")
		check(sun.directional_shadow_split_3 > close_splits.z)
	var actor_camera := Camera3D.new()
	view.world.add_child(actor_camera)
	view.set_exploration_camera(actor_camera)
	check_eq(Vector3(sun.directional_shadow_split_1,sun.directional_shadow_split_2,sun.directional_shadow_split_3),Vector3(.1,.2,.5),"exploration restores normal near-camera splits")
	view.clear_exploration_camera()
	for size: float in [0.5,10.0,70.0,180.0,2048.0]:
		view.set_camera_state(view.center,0,size)
		check(sun.directional_shadow_split_1 > 0.0)
		check(sun.directional_shadow_split_1 < sun.directional_shadow_split_2)
		check(sun.directional_shadow_split_2 < sun.directional_shadow_split_3)
		check(sun.directional_shadow_split_3 < 1.0)
	view.set_camera_state(view.center,0,10)
	check_eq(Vector3(sun.directional_shadow_split_1,sun.directional_shadow_split_2,sun.directional_shadow_split_3),close_splits,"aerial focus restored")
	check_eq([view.camera.near, view.camera.far],planes,"visibility planes remain unchanged")
	view.free()
