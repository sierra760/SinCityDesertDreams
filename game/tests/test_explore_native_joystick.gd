# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_ipad_explore_touch.gd"

const LiveHost := preload("res://tests/helpers/host_fixture.gd")

func test_scaled_main_contacts_drive_actor_without_navigation_or_button_capture() -> void:
	var original_size := root.size
	var host := LiveHost.make_host(self,"native-joystick-host")
	var city := flat_city()
	for x in range(50,80): city.building.put(x,61,Buildings.ROAD_FIRST+NetworkShapes.SHAPE_EW)
	host.begin_city(city,{},123,null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.exploration.follow_pointer_kind=false
	host.exploration.set_touch_controls_enabled(true)
	for drawable: Vector2i in [Vector2i(780,1688),Vector2i(1688,780)]:
		root.size=drawable
		host.display_layout.refresh_with_mobile_metrics(drawable,2.0,Rect2i(Vector2i(0,48),drawable-Vector2i(0,88)))
		host.city_view_3d.set_camera_state(Vector3(64,2.4,61),0,48)
		await process_frame
		await physics_frame
		check(host.enter_explore(),"scaled Main enters a supported touch session")
		if not host.exploration.is_active(): break
		await process_frame
		await process_frame
		var owner := host.explore_hud.touch_controls
		var pad := _native_pad(owner)
		if pad == null: break
		var scale: float=host.display_layout.metrics.scale
		var center: Vector2=owner.control_rect(&"move").get_center()
		var radius: float=owner._pad_radius
		var actor: CharacterBody3D=host.exploration.occupied
		var start := actor.global_position
		root.push_input(_finger(0,center*scale,true),false)
		root.push_input(_drag(0,(center+Vector2(0,-radius))*scale,Vector2(0,-radius)*scale),false)
		root.push_input(_finger(1,owner.control_rect(&"sprint").get_center()*scale,true),false)
		for tick in 10: await physics_frame
		check(actor.global_position.distance_to(start)>.005,"Main scales the native movement contact into real actor physics")
		check_eq(Input.get_action_strength(pad.get("action_up")),1.0,"viewport routing preserves full analog travel")
		root.push_input(_finger(1,owner.control_rect(&"sprint").get_center()*scale,false),false)
		root.push_input(_finger(0,center*scale,false),false)
		host.return_to_build()
		check(not Input.is_action_pressed(pad.get("action_up")),"returning to Build releases native movement")
		await process_frame
	host.free()
	root.size=original_size
	await process_frame

func _native_pad(owner: Control) -> Control:
	var pads := owner.find_children("*", "VirtualJoystick", true, false)
	check_eq(pads.size(),1,"Explore routes movement through one native joystick")
	return pads[0] as Control if pads.size()==1 else null

func test_detach_ignores_late_layout_and_reattach_requires_fresh_movement() -> void:
	if not _setup_touch(): return
	var center: Vector2=touch.control_rect(&"move").get_center()
	touch.handle_event(_finger(0,center,true))
	touch.handle_event(_drag(0,center+Vector2(48,0),Vector2(48,0)))
	root.remove_child(touch)
	# Scene replacement can still deliver a deferred shell layout to a live,
	# detached HUD. It must neither query retired actions nor resize the pad.
	touch.set_usable_rect(Rect2(0,44,390,250))
	check_eq(touch.sample_frame().move,Vector2.ZERO,"detached controls do not retain movement")
	check(not touch.handle_event(_finger(1,Vector2(80,200),true)),"detached controls ignore late input")
	root.add_child(touch)
	center=touch.control_rect(&"move").get_center()
	touch.handle_event(_finger(0,center,false))
	touch.handle_event(_finger(1,center,true))
	touch.handle_event(_drag(1,center+Vector2(20,0),Vector2(20,0)))
	check_eq(touch.sample_frame().move,Vector2(.5,0),"reattached pad accepts a fresh contact with its own live actions")

func test_finger_lifted_while_detached_does_not_block_reattached_controls() -> void:
	if not _setup_touch(): return
	for canceled: bool in [false,true]:
		var center: Vector2=touch.control_rect(&"move").get_center()
		touch.handle_event(_finger(0,center,true))
		touch.handle_event(_drag(0,center+Vector2(48,0),Vector2(48,0)))
		root.remove_child(touch)
		var release := _finger(0,center,false)
		release.canceled=canceled
		check(not touch.handle_event(release),"detached release only retires its contact")
		root.add_child(touch)
		touch.handle_event(_finger(1,center,true))
		touch.handle_event(_drag(1,center+Vector2(24,0),Vector2(24,0)))
		check_eq(touch.sample_frame().move,Vector2(.5,0),"a finger lifted during detachment cannot leave permanent quarantine")
		touch.handle_event(_finger(1,center,false))
		touch.clear_input()

func test_native_actions_receive_only_the_movement_finger_and_clear_on_cancel() -> void:
	if not _setup_touch(): return
	var pad := _native_pad(touch)
	if pad == null: return
	var left: StringName = pad.get("action_left")
	var up: StringName = pad.get("action_up")
	check(left != &"ui_left" and up != &"ui_up","movement never presses GUI navigation actions")
	var center: Vector2 = touch.control_rect(&"move").get_center()
	touch.handle_event(_finger(0,center,true))
	touch.handle_event(_drag(0,center+Vector2(-24,-24),Vector2(-24,-24)))
	check_eq(Input.get_action_strength(left),.5,"routed movement reaches native input actions")
	check_eq(Input.get_action_strength(up),.5)
	touch.handle_event(_finger(1,Vector2(650,300),true))
	touch.handle_event(_drag(1,Vector2(680,310),Vector2(30,10)))
	check_eq(Input.get_action_strength(left),.5,"camera finger cannot alter native movement")
	check_eq(touch.take_look_delta(),Vector2(30,10))
	touch.clear_input()
	check(not Input.is_action_pressed(left) and not Input.is_action_pressed(up),"cancel releases native actions immediately")
	touch.handle_event(_drag(0,center+Vector2(-48,0),Vector2(-24,24)))
	check_eq(touch.sample_frame().move,Vector2.ZERO,"old movement contact cannot reacquire the joystick")
	check(not Input.is_action_pressed(left))
	for id in 2: touch.handle_event(_finger(id,center,false))
	touch.handle_event(_finger(2,center,true))
	touch.handle_event(_drag(2,center+Vector2(-24,0),Vector2(-24,0)))
	check_eq(touch.sample_frame().move,Vector2(-.5,0),"fresh movement press reaches the native pad after quarantine")

func test_native_input_is_owned_by_its_controller_and_released_on_destruction() -> void:
	if not _setup_touch(): return
	var pad := _native_pad(touch)
	if pad == null: return
	var other := ExploreTouchControls.new()
	root.add_child(other)
	other.set_enabled(true)
	other.set_session_active(true)
	var other_pad := _native_pad(other)
	if other_pad == null:
		other.free()
		return
	var right: StringName = pad.get("action_right")
	var other_right: StringName = other_pad.get("action_right")
	var center: Vector2 = touch.control_rect(&"move").get_center()
	touch.handle_event(_finger(0,center,true))
	touch.handle_event(_drag(0,center+Vector2(48,0),Vector2(48,0)))
	check_eq(Input.get_action_strength(right),1.0)
	check_eq(other.sample_frame().move,Vector2.ZERO,"another controller cannot read this joystick's movement")
	other.clear_input()
	check_eq(Input.get_action_strength(right),1.0,"another controller cannot release this joystick's actions")
	other.free()
	check(not InputMap.has_action(other_right),"controller disposal removes its temporary actions")
	touch.free()
	touch=null
	check(not InputMap.has_action(right),"leaving Explore removes its native action map")
