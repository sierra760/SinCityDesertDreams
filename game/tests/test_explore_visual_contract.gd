# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
var visuals: Array[Node] = []
func after_each() -> void:
	for visual in visuals: visual.free()
	visuals.clear()
	await process_frame
func visual_for(kind: StringName, variant: int = 0) -> ExploreActorVisual:
	var visual: ExploreActorVisual = CityTrafficCatalog.make_detailed_visual(kind,variant)
	root.add_child(visual)
	visuals.append(visual)
	return visual
func test_motion_metadata_overrides_cruiser_radius() -> void:
	var visual := visual_for(&"car")
	visual.configure_animation({"wheel_radius_m": 0.44})
	visual.set_motion(-0.2, 0.0, false)
	visual.advance_visual(0.1)
	check_eq(visual.debug_state().wheel_phase,0.2 * 0.1 / (0.44 / 16.0))
func test_fallback_and_stable_variants() -> void:
	var a := visual_for(&"pedestrian",3)
	var b := visual_for(&"pedestrian",19)
	var am: MeshInstance3D = a.find_child("CrowdPedestrian",true,false)
	var bm: MeshInstance3D = b.find_child("CrowdPedestrian",true,false)
	check(am.mesh == bm.mesh,"variants wrap stably")
	check_between((am.transform*am.mesh.get_aabb()).position.y,-.00001,.00001,"feet contact origin")
	var bus := visual_for(&"bus")
	check(bus.find_children("*","MeshInstance3D",true,false).size()>0,"missing detail falls back to catalog")
	check(not bus.play_gesture(&"wave"),"unavailable gesture is refused")
func test_frozen_and_tick_only_pose() -> void:
	var visual := visual_for(&"car")
	visual.set_motion(.15,0,false)
	var before := visual.debug_state()
	for frame in 3: await process_frame
	check_eq(visual.debug_state(),before,"frames do not animate")
	visual.advance_visual(.1)
	check_between(visual.debug_state().wheel_phase,-1.001,-.999,"one tick applies one distance")
	var state := visual.debug_state()
	state.wheel_phase=99
	check(visual.debug_state().wheel_phase!=99,"debug dictionary is detached")
	visual.set_gait_phase(.75)
	check_eq(visual.debug_state().gait_phase,.75)

func test_per_wheel_and_rotor_metadata() -> void:
	var car := visual_for(&"car")
	car.configure_animation({"wheels":[{"node":"WheelFrontLeft","radius_m":.48,"axis":"X","steer":true}]})
	car.set_motion(.15,1,false)
	car.advance_visual(.1)
	var wheel: Node3D = car.find_child("WheelFrontLeft",true,false)
	check_between(wheel.get_node("Spin").rotation.x,-.501,-.499,"individual radius used")
	check(wheel.rotation.y>0,"individual steering pivot used")
	check_between(car.debug_state().wheel_phases.WheelFrontLeft,-.501,-.499,"individual wheel metric exposed")
	var helicopter := visual_for(&"helicopter")
	helicopter.configure_animation({"rotors":[{"node":"MainRotor","axis":"Y","radians_per_second":2.0}]})
	helicopter.advance_visual(.1)
	check_between(helicopter.debug_state().main_rotor_phase,.199,.201,"individual rotor rate used")

func test_wave_is_manual_bounded_and_motion_cancels_it() -> void:
	var visual := ExploreActorVisual.new()
	visual.add_child(load("res://assets/desert-dreams-exploration/pedestrian_woman.glb").instantiate())
	root.add_child(visual)
	visuals.append(visual)
	check(visual.play_gesture(&"wave"))
	var before := visual.debug_state()
	for frame: int in 3: await process_frame
	check_eq(visual.debug_state(),before,"rendering cannot advance greeting")
	visual.advance_visual(.1)
	check(visual.debug_state().animation_position>0,"owner tick advances greeting")
	check(not visual.play_gesture(&"walk"),"locomotion is not a gesture")
	for tick: int in 20: visual.advance_visual(.1)
	check_eq(visual.debug_state().clip,"idle","one-shot wave returns to idle")
	check(visual.play_gesture(&"wave"))
	visual.set_motion(.2,0,false)
	check_eq(visual.debug_state().clip,"run","movement cancels gesture")
	check(not visual.play_gesture(&"wave"),"moving actor cannot start greeting")
	visual.set_motion(0,0,false)
	check(visual.play_gesture(&"wave"))
	visual.set_motion(0,0,true)
	check_eq(visual.debug_state().clip,"jump","airborne priority cancels greeting")
