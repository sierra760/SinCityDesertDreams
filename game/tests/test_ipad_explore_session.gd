# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/explore_session_case.gd"

func _enable_touch() -> bool:
	session.set_touch_controls_enabled(true)
	return true

func test_touch_actor_blends_hardware_keys_without_mouse_capture_or_emulated_orbit() -> void:
	if not _setup() or not _enable_touch() or not await _enter(): return
	check_eq(Input.mouse_mode,Input.MOUSE_MODE_VISIBLE,"touch Explore never captures a pointer")
	var actor: CharacterBody3D = session.get("occupied")
	var start := actor.global_position
	await _physical_key(KEY_W,true)
	session.handle_event(_key(KEY_W,true))
	for tick in 10: await physics_frame
	check(actor.global_position.distance_to(start)>.005,"hardware keyboard remains available beside touch")
	await _physical_key(KEY_W,false)
	session.handle_event(_key(KEY_W,false))
	var controls: Control = hud.get("touch_controls")
	check(controls != null,"HUD renders its touch controller")
	if controls == null: return
	var center: Vector2 = controls.control_rect(&"move").get_center()
	session.handle_event(_touch(0,center,true))
	session.handle_event(_touch_drag(0,center+Vector2(0,-48),Vector2(0,-48)))
	for tick in 25: await physics_frame
	check(actor.global_position.distance_to(start)>.02,"analog touch input reaches real pedestrian physics")
	var yaw: float = session.camera_rig.yaw
	var mouse := InputEventMouseMotion.new()
	mouse.device=InputEvent.DEVICE_ID_EMULATION
	mouse.screen_relative=Vector2(100,100)
	check(session.handle_event(mouse),"touch emulated mouse is consumed")
	check_eq(session.camera_rig.yaw,yaw,"touch emulated mouse never orbits")
	mouse.device=0
	check(session.handle_event(mouse),"touch-capable desktops retain real mouse input")
	check_ne(session.camera_rig.yaw,yaw,"a physical mouse still orbits")

func test_touch_resume_quarantines_held_hardware_keys_until_release() -> void:
	if not _setup() or not _enable_touch() or not await _enter(): return
	session.handle_event(_key(KEY_W,true))
	for tick in 8: await physics_frame
	var actor: CharacterBody3D = session.occupied
	check_gt(actor.velocity.length(),0.0,"touch-enabled hardware key reaches actor")
	session.suspend()
	await _physical_key(KEY_W,true)
	session.handle_event(_key(KEY_W,true))
	var stopped := actor.global_transform
	session.resume()
	for tick in 10: await physics_frame
	check_eq(actor.global_transform,stopped,"held hardware W cannot resume movement")
	await _physical_key(KEY_W,false)
	session.handle_event(_key(KEY_W,false))
	for tick in 2: await physics_frame
	session.handle_event(_key(KEY_W,true))
	for tick in 10: await physics_frame
	check(actor.global_position.distance_to(stopped.origin)>.005,"released then fresh hardware W moves")

func test_touch_menu_suspend_resume_waits_for_all_old_contacts() -> void:
	if not _setup() or not _enable_touch() or not await _enter(): return
	var controls: Control = hud.get("touch_controls")
	if controls == null: return
	var center: Vector2 = controls.control_rect(&"move").get_center()
	session.handle_event(_touch(0,center,true))
	session.handle_event(_touch_drag(0,center+Vector2(0,-48),Vector2(0,-48)))
	for tick in 8: await physics_frame
	var menu: Vector2 = controls.control_rect(&"menu").get_center()
	session.handle_event(_touch(1,menu,true))
	session.handle_event(_touch(1,menu,false))
	check(session.is_suspended(),"always-visible touch Menu releases actor input")
	var actor: CharacterBody3D = session.occupied
	var stopped := actor.global_transform
	session.resume()
	session.handle_event(_touch_drag(0,center+Vector2(0,-48),Vector2(0,-20)))
	for tick in 12: await physics_frame
	check_eq(actor.global_transform,stopped,"deliberate resume cannot inherit old finger")
	session.handle_event(_touch(0,center,false))
	session.handle_event(_touch(0,center,true))
	session.handle_event(_touch_drag(0,center+Vector2(0,-48),Vector2(0,-48)))
	for tick in 12: await physics_frame
	check(actor.global_position.distance_to(stopped.origin)>.01,"fresh input after release moves")

func test_touch_hud_portrait_resume_and_menu_stay_inside_usable_area() -> void:
	if not _setup() or not _enable_touch(): return
	var layout := DisplayLayout.new()
	layout.refresh_with_metrics(Vector2i(640,900),1.0)
	hud.bind_layout(layout)
	hud.set_chrome_insets(44,88)
	hud.show_session(true)
	hud.set_status({"mode":2,"altitude":1,"prompt":"F to exit helicopter"})
	hud.set_suspended(true)
	await process_frame
	await process_frame
	var usable := Rect2(0,44,640,768)
	check(usable.encloses(hud._panel.get_rect()),"portrait controls clear shell chrome")
	check(not hud._panel.get_rect().intersects(hud._status_panel.get_rect()))
	var column: Node = hud._scroll.get_child(0)
	var resume: Button = column.get_child(1)
	check(hud._scroll.get_global_rect().encloses(resume.get_global_rect()),"Resume is reachable before scrolling")
	check_ge(resume.size.y,44.0)
	layout.free()

func test_touch_display_change_stops_real_actor_and_old_fingers_stay_released() -> void:
	if not _setup() or not _enable_touch() or not await _enter(): return
	var layout := DisplayLayout.new()
	layout.refresh_with_metrics(Vector2i(1024,768),1.0)
	hud.bind_layout(layout)
	var controls: Control = hud.get("touch_controls")
	if controls == null: return
	var center: Vector2 = controls.control_rect(&"move").get_center()
	session.handle_event(_touch(0,center,true))
	session.handle_event(_touch_drag(0,center+Vector2(0,-48),Vector2(0,-48)))
	for tick in 8: await physics_frame
	check_gt(session.occupied.velocity.length(),0.0)
	layout.refresh_with_metrics(Vector2i(768,1024),1.0)
	check_eq(session.occupied.velocity,Vector3.ZERO,"display change immediately clears actor input")
	var at: Vector3 = session.occupied.global_position
	session.handle_event(_touch_drag(0,controls.control_rect(&"move").get_center()+Vector2(0,-48),Vector2(0,-48)))
	for tick in 6: await physics_frame
	check(session.occupied.global_position.distance_to(at)<.005,"old movement finger cannot survive display change")
	layout.free()

func _touch(id: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index=id
	event.position=position
	event.pressed=pressed
	return event

func _touch_drag(id: int, position: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index=id
	event.position=position
	event.screen_relative=relative
	return event
