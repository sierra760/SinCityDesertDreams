# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const INPUT_PATH := "res://scripts/exploration/explore_input_frame.gd"
const PROFILE_PATH := "res://scripts/exploration/explore_actor_profile.gd"

func test_physics_fixture_awaits_before_reporting() -> void:
	var before := Engine.get_physics_frames()
	await physics_frame
	await physics_frame
	check(Engine.get_physics_frames()>before, "async methods finish before Results")

func test_normalized_motion_and_interaction_edges() -> void:
	check(ResourceLoader.exists(INPUT_PATH), "exploration input contract exists")
	if not ResourceLoader.exists(INPUT_PATH): return
	var input_script: Script = load(INPUT_PATH)
	var frame = input_script.from_keys({KEY_W:true,KEY_D:true,KEY_F:true}, {})
	check(is_equal_approx(frame.move.length(),1.0))
	check(frame.move.x>0 and frame.move.y<0)
	check(not frame.interact, "held F does not repeatedly enter/exit")
	check(input_script.from_keys({}, {KEY_F:true}).interact)
	check_eq(input_script.from_keys({KEY_W:true,KEY_S:true},{}).move, Vector2.ZERO)
	check_eq(input_script.from_keys({KEY_W:"bad",KEY_A:9},{}).move,Vector2.ZERO)
	check_eq(input_script.from_keys({KEY_SPACE:true,KEY_CTRL:true},{}).vertical,0.0)
	check(not input_script.from_keys({KEY_SPACE:true},{}).jump)
	check(input_script.from_keys({}, {KEY_SPACE:true}).jump)
	check_eq(input_script.idle().move,Vector2.ZERO)

func test_shapes_and_physical_masks_are_consistent() -> void:
	check(ResourceLoader.exists(PROFILE_PATH), "actor physical contract exists")
	if not ResourceLoader.exists(PROFILE_PATH): return
	var profile: Script = load(PROFILE_PATH)
	check_eq(profile.FLOOR,8)
	check_eq(profile.OBSTACLE,16)
	check_eq(profile.ACTOR,32)
	check_eq(profile.WORLD,28)
	check_eq(profile.METRES_PER_TILE,16.0)
	var walk = profile.shape(profile.Mode.WALK)
	check(walk is CapsuleShape3D)
	check(is_equal_approx(walk.height,.115))
	check(is_equal_approx(walk.radius,.018))
	check_eq(profile.shape(profile.Mode.DRIVE).size,Vector3(.12,.08,.28))
	check_eq(profile.shape(profile.Mode.FLY).size,Vector3(.50,.14,.28))
	check(is_equal_approx(profile.geometry(profile.Mode.WALK).foot_offset,.0575))
	check(is_equal_approx(profile.geometry(profile.Mode.DRIVE).step,.045))
	check(is_equal_approx(profile.geometry(profile.Mode.FLY).margin,.001))
	var settings: Dictionary = profile.geometry(profile.Mode.WALK)
	settings["margin"] = 99.0
	check(is_equal_approx(profile.geometry(profile.Mode.WALK).margin,.001), "returned profiles are isolated")

func test_altitude_and_interaction_have_separate_keys() -> void:
	check_eq(ExploreInputFrame.from_keys({KEY_Q:true},{}).vertical,1.0,"held Q climbs")
	check_eq(ExploreInputFrame.from_keys({KEY_E:true},{}).vertical,-1.0,"held E descends")
	check_eq(ExploreInputFrame.from_keys({KEY_Q:true,KEY_E:true},{}).vertical,0.0,"opposed altitude cancels")
	check(not ExploreInputFrame.from_keys({KEY_E:true},{KEY_E:true}).interact,"descent never exits a vehicle")
	check(not ExploreInputFrame.from_keys({KEY_F:true},{}).interact,"held F never repeats interaction")
	check(ExploreInputFrame.from_keys({},{KEY_F:true}).interact,"F press edge interacts")
	check_eq(ExploreInputFrame.from_keys({KEY_SPACE:true},{}).vertical,0.0,"Space does not climb")
	check_eq(ExploreInputFrame.from_keys({KEY_CTRL:true},{}).vertical,0.0,"Control does not descend")
	check(ExploreInputFrame.from_keys({KEY_SPACE:true},{}).brake,"held Space retains handbrake")
	check(ExploreInputFrame.from_keys({},{KEY_SPACE:true}).jump,"Space edge retains jump")
