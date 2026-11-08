# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Character selection must persist and change only the session-owned visual.
extends "res://tests/exploration/async_test_case.gd"

const PREFS := "user://test_pedestrian_character.cfg"
var owned: Array[Node] = []

func after_each() -> void:
	for node in owned:
		if node is GameHost:
			if node.sim._ctx != null: node.sim._ctx.systems.clear()
			node.sim.systems.clear()
		if is_instance_valid(node): node.free()
	owned.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	await process_frame

func test_missing_or_invalid_saved_character_defaults_to_woman() -> void:
	check_eq(ViewPreferences.read(PREFS).get("explore_character"),"woman")
	var config := ConfigFile.new()
	config.set_value("view","explore_sensitivity",1.5)
	check_eq(config.save(PREFS),OK)
	check_eq(ViewPreferences.read(PREFS).get("explore_character"),"woman","old preferences gain the default")
	check_eq(ViewPreferences.read(PREFS).explore_sensitivity,1.5)
	for value: Variant in [null,42,true,[],{},"", "unknown", "../../other.glb"]:
		check_eq(ViewPreferences.sanitize({"explore_character":value}).get("explore_character"),"woman","invalid character has a safe default")

func test_character_choice_roundtrips_without_overwriting_other_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("other","keep",17)
	config.save(PREFS)
	for character: String in ["man","woman","pedestrian_00","pedestrian_15"]:
		check_eq(ViewPreferences.write({"explore_character":character,"explore_sensitivity":1.5,"render_scale":75},PREFS),OK)
		var saved := ViewPreferences.read(PREFS)
		check_eq(saved.get("explore_character"),character)
		check_eq(saved.explore_sensitivity,1.5)
		check_eq(saved.render_scale,75)
		config.load(PREFS)
		check_eq(config.get_value("other","keep"),17)

func test_settings_picker_displays_and_emits_the_choice_without_refresh_feedback() -> void:
	var window := OptionsWindow.new()
	root.add_child(window)
	owned.append(window)
	var picker := window.find_child("PedestrianCharacter",true,false) as OptionButton
	check(picker != null,"Settings offers a pedestrian character picker")
	if picker == null: return
	window.open()
	check(picker.is_visible_in_tree(),"character is reachable from the initial Settings page")
	check(picker.custom_minimum_size.y>=44,"touch-readable target")
	check_eq(picker.item_count,18,"all sixteen crowd characters and both Explore characters are available")
	check_eq(picker.get_item_text(0),"Woman")
	check_eq(picker.get_item_text(1),"Man")
	check_eq(window.values().get("explore_character"),"woman")
	var changes: Array = []
	window.option_changed.connect(func(key: StringName,value: Variant) -> void: changes.append([key,value]))
	window.set_values({"explore_character":"man"})
	check(changes.is_empty(),"refresh does not write preferences")
	check_eq(window.values().get("explore_character"),"man")
	picker.select(0)
	picker.item_selected.emit(0)
	check_eq(changes,[[&"explore_character","woman"]])
	for variant: int in 16:
		window.set_values({"explore_character":"pedestrian_%02d" % variant})
		check_eq(picker.selected,variant+2)
		check_eq(window.values().get("explore_character"),"pedestrian_%02d" % variant)
	check_eq(changes.size(),1,"refreshing any roster member stays silent")

func test_live_swap_preserves_actor_pose_collision_support_and_occlusion() -> void:
	var actor := ExplorePedestrian.new()
	root.add_child(actor)
	owned.append(actor)
	check_eq(actor.get("character"),"woman","new actor is a woman")
	actor.position = Vector3(12.5,.5,11.5)
	actor.rotation.y = .7
	actor.velocity = Vector3(.09,.1,0)
	var support := Node3D.new()
	root.add_child(support)
	owned.append(support)
	actor.transit_support = support
	actor._support_frame = support
	actor.set_camera_occluded(true)
	actor._visual.rotation.y = .4
	actor._visual.set_motion(.09,0,false)
	var pose := actor.transform
	var rid := actor.get_rid()
	var collider := actor.get_child(0)
	var shape := actor._shape
	var old := actor._visual
	actor.set_character("man")
	check(not is_instance_valid(old),"old visual is released")
	check_eq(actor.get("character"),"man")
	check_eq(actor.transform,pose)
	check_eq(actor.velocity,Vector3(.09,.1,0))
	check_eq(actor.get_rid(),rid)
	check_eq(actor.get_child(0),collider)
	check_eq(actor._shape,shape)
	check_eq(actor.transit_support,support)
	check_eq(actor._support_frame,support)
	check(not actor._visual.visible,"first-person occlusion survives replacement")
	check(absf(actor._visual.rotation.y-.4)<.000001,"visual heading survives replacement")
	check_eq(actor._visual._player.current_animation,"walk","motion carries into replacement")
	var unchanged := actor._visual
	actor.set_character("man")
	check_eq(actor._visual,unchanged,"reselecting does not recreate the model")
	actor.set_character("woman")
	check(actor._visual.get_node("ImportedModel").scene_file_path.ends_with("pedestrian_woman.glb"),"woman choice uses the woman's imported artwork")
	actor.set_character("bad")
	check_eq(actor.get("character"),"woman")

func test_every_existing_crowd_character_uses_its_rigged_model_and_session_owned_motion() -> void:
	var actor := ExplorePedestrian.new()
	root.add_child(actor)
	owned.append(actor)
	for variant: int in 16:
		var character := "pedestrian_%02d" % variant
		actor.set_character(character)
		check_eq(actor.get("character"),character,"every existing character can be selected")
		var visual := actor._visual
		var model := visual.find_child("DetailedModel",false,false)
		check(model != null and model.scene_file_path.ends_with("pedestrian_%02d_detail.glb" % variant),"%s uses its own rigged street-crowd model" % character)
		check(visual.find_child("CrowdPedestrian",true,false) == null,"not the single crowd mesh")
		check_eq(visual.find_children("*","Skeleton3D",true,false).size(),1,"one skeleton")
		var player := visual._player
		check(player != null,"the model has its authored animation player")
		if player == null: continue
		check_eq(player.callback_mode_process,AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL,"only Explore ticks animate it")
		for sample: Array in [[0.0,false,"idle"],[.09,false,"walk"],[.20,false,"run"],[.20,true,"jump"]]:
			visual.set_motion(sample[0],0,sample[1])
			check_eq(player.current_animation,sample[2],"%s clip" % sample[2])
		visual.set_motion(.09,0,false)
		var before := player.current_animation_position
		await process_frame
		check_eq(player.current_animation_position,before,"motion freezes while the session is paused")
		visual.advance_visual(.1)
		var advanced := player.current_animation_position
		check(advanced != before,"session ticks animate walking")
		for value: Variant in [INF,NAN,-INF]: visual.advance_visual(value)
		check_eq(player.current_animation_position,advanced,"invalid frame deltas cannot corrupt motion")
		visual.set_motion(0,0,false)
		var bounds := AABB()
		var first := true
		for mesh: MeshInstance3D in visual.find_children("*","MeshInstance3D",true,false):
			check(mesh.skin != null,"model is skin-bound")
			var chain := Transform3D.IDENTITY
			var node: Node = mesh
			while node != visual:
				chain = (node as Node3D).transform*chain
				node = node.get_parent()
			var box := chain*mesh.mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		check(bounds.position.y>=-.000001 and bounds.end.y<=.115001,"feet and height fit the existing actor")
		check(bounds.position.x>=-.018001 and bounds.end.x<=.018001,"accessories fit the existing actor width")

func test_both_characters_have_session_driven_skinned_motion() -> void:
	var actor := ExplorePedestrian.new()
	root.add_child(actor)
	owned.append(actor)
	for character: String in ["woman","man"]:
		actor.set_character(character)
		var visual := actor._visual
		var player := visual._player
		check(player != null,"character has an authored animation player")
		if player == null: continue
		check_eq(player.callback_mode_process,AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
		check_eq(visual.find_children("*","Skeleton3D",true,false).size(),1)
		for mesh: MeshInstance3D in visual.find_children("*","MeshInstance3D",true,false):
			check(mesh.skin != null,"model is skin-bound")
		for sample: Array in [[0.0,false,"idle"],[.09,false,"walk"],[.20,false,"run"],[.20,true,"jump"]]:
			visual.set_motion(sample[0],0,sample[1])
			check_eq(player.current_animation,sample[2])
			var before := player.current_animation_position
			await process_frame
			check_eq(player.current_animation_position,before,"suspension leaves pose frozen")
			visual.advance_visual(.1)
			check(player.current_animation_position>before,"session tick advances motion")

func test_main_settings_persist_apply_and_survive_explore_reentry() -> void:
	root.size = Vector2i(1280,800)
	var host: GameHost = load("res://scenes/main.tscn").instantiate()
	host.preferences_path = PREFS
	ViewPreferences.write({"explore_character":"man"},PREFS)
	root.add_child(host)
	owned.append(host)
	check_eq(host.prefs.option_values().get("explore_character"),"man","startup restores saved selection")
	var city := flat_city()
	city.stamp_building(10,10,Buildings.MAYORS_RESIDENCE)
	for x: int in range(8,15): city.building.put(x,12,30)
	host.begin_city(city,{},4242,CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.city_view_3d.set_camera_state(Vector3(10.5,4*CityGeometry3D.HEIGHT,10.5),1,12.0)
	await physics_frame
	var before_city := SaveFormat.encode_city(city)
	var before_sim := host.sim.snapshot().duplicate(true)
	check(host.enter_explore(),"offers the Mayor's House start")
	check(host.notice_dialog.is_open(),"house fixture asks where to start")
	host.notice_dialog.dismiss(&"house")
	check(host.exploration.is_active(),"Mayor's House choice enters Explore")
	if not host.exploration.is_active(): return
	var pedestrian: CharacterBody3D = host.exploration.pedestrian
	check_eq(pedestrian.get("character"),"man","entry uses saved selection")
	var pose := pedestrian.transform
	host.exploration.suspend()
	var window := host.open_window("options") as OptionsWindow
	var picker := window.find_child("PedestrianCharacter",true,false) as OptionButton
	check(picker != null,"Main Settings offers the picker")
	if picker == null: return
	picker.select(0)
	picker.item_selected.emit(0)
	check_eq(pedestrian.get("character"),"woman","Settings applies to the existing actor")
	check_eq(host.exploration.pedestrian,pedestrian,"no session actor replacement")
	check_eq(host.exploration.occupied,pedestrian)
	check_eq(pedestrian.transform,pose)
	check(host.exploration.is_suspended(),"Settings does not resume input")
	check_eq(ViewPreferences.read(PREFS).get("explore_character"),"woman")
	window.close()
	var helicopter := host.exploration.helicopter
	check(is_instance_valid(helicopter),"Mayor's House supplies the parked helicopter")
	if not is_instance_valid(helicopter): return
	pedestrian.global_position = helicopter.global_position+Vector3(-.19,0,0)
	check(host.exploration.select_vehicle(&"helicopter"),"parked helicopter can be selected while suspended")
	var occupied: CharacterBody3D = host.exploration.occupied
	check(occupied != pedestrian and not pedestrian.visible)
	var vehicle_pose := occupied.transform
	host.set_option(&"explore_character","pedestrian_15")
	check_eq(pedestrian.get("character"),"pedestrian_15","hidden pedestrian can use any crowd character while driving")
	check_eq(host.exploration.occupied,occupied)
	check_eq(occupied.transform,vehicle_pose)
	check(not pedestrian.visible,"vehicle occupant stays hidden")
	check_eq(pedestrian.collision_layer,0)
	check_eq(pedestrian.collision_mask,0)
	host.set_option(&"explore_character","woman")
	host.return_to_build()
	check(host.enter_explore())
	host.notice_dialog.dismiss(&"house")
	check(host.exploration.is_active(),"Mayor's House choice starts the new session")
	check_eq(host.exploration.pedestrian.get("character"),"woman","new session keeps selection")
	host.return_to_build()
	check_eq(SaveFormat.encode_city(city),before_city)
	check_eq(host.sim.snapshot(),before_sim,"appearance consumes no simulation or random state")
	var restored: GameHost = load("res://scenes/main.tscn").instantiate()
	restored.preferences_path = PREFS
	root.add_child(restored)
	owned.append(restored)
	check_eq(restored.prefs.option_values().get("explore_character"),"woman","restarting Main restores the last choice")
