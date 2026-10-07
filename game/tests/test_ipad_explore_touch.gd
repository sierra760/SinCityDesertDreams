# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const TOUCH_PATH := "res://scripts/ui/explore_touch_controls.gd"
var touch: Control

func _setup_touch() -> bool:
	check(ResourceLoader.exists(TOUCH_PATH),"Explore has a touch input owner")
	if not ResourceLoader.exists(TOUCH_PATH): return false
	touch = load(TOUCH_PATH).new()
	root.add_child(touch)
	touch.set_enabled(true)
	touch.set_usable_rect(Rect2(0,44,1024,680))
	touch.set_session_active(true)
	return true

func after_each() -> void:
	if is_instance_valid(touch): touch.free()
	touch = null

func test_move_look_and_actions_are_simultaneous_and_analog() -> void:
	if not _setup_touch(): return
	var center: Vector2 = touch.control_rect(&"move").get_center()
	touch.handle_event(_finger(0,center,true))
	touch.handle_event(_drag(0,center+Vector2(24,-24),Vector2(24,-24)))
	touch.handle_event(_finger(1,Vector2(620,340),true))
	touch.handle_event(_drag(1,Vector2(633,333),Vector2(13,-7)))
	touch.handle_event(_finger(2,touch.control_rect(&"sprint").get_center(),true))
	touch.handle_event(_finger(3,touch.control_rect(&"jump").get_center(),true))
	touch.handle_event(_finger(4,touch.control_rect(&"interact").get_center(),true))
	var frame: ExploreInputFrame = touch.sample_frame()
	check(frame.move.is_equal_approx(Vector2(.5,-.5)),"partial pad displacement keeps analog strength")
	check(frame.sprint and frame.jump and frame.interact,"five concurrent fingers keep independent roles")
	check_eq(touch.take_look_delta(),Vector2(13,-7),"look uses screen delta once")
	check_eq(touch.take_look_delta(),Vector2.ZERO)
	frame = touch.sample_frame()
	check(frame.sprint and not frame.jump and not frame.interact,"only jump and interaction are press edges")

func test_action_and_ui_origin_fingers_never_become_camera_or_move() -> void:
	if not _setup_touch(): return
	var action: Vector2 = touch.control_rect(&"sprint").get_center()
	touch.handle_event(_finger(0,action,true))
	touch.handle_event(_drag(0,Vector2(600,300),Vector2(-200,-100)))
	touch.handle_event(_finger(1,Vector2(620,340),true),true)
	touch.handle_event(_drag(1,touch.control_rect(&"move").get_center(),Vector2(-450,150)))
	var frame: ExploreInputFrame = touch.sample_frame()
	check_eq(frame.move,Vector2.ZERO,"a UI-origin finger cannot acquire movement")
	check(not frame.sprint,"sliding away releases held action")
	check_eq(touch.take_look_delta(),Vector2.ZERO,"button and UI drags do not orbit")

func test_suspend_resume_quarantines_every_old_contact_until_release() -> void:
	if not _setup_touch(): return
	var center: Vector2 = touch.control_rect(&"move").get_center()
	touch.handle_event(_finger(0,center,true))
	touch.handle_event(_drag(0,center+Vector2(0,-48),Vector2(0,-48)))
	touch.handle_event(_finger(1,touch.control_rect(&"sprint").get_center(),true))
	touch.set_suspended(true)
	touch.set_suspended(false)
	touch.handle_event(_finger(2,center,true))
	touch.handle_event(_drag(2,center+Vector2(48,0),Vector2(48,0)))
	check_eq(touch.sample_frame().move,Vector2.ZERO,"new contact cannot bypass old held contacts")
	check(not touch.sample_frame().sprint,"suspension releases every action")
	for id in 3: touch.handle_event(_finger(id,center,false))
	touch.handle_event(_finger(0,center,true))
	touch.handle_event(_drag(0,center+Vector2(0,-24),Vector2(0,-24)))
	check_eq(touch.sample_frame().move,Vector2(0,-.5),"fresh press after all releases moves")

func test_vehicle_modes_clear_old_roles_and_expose_their_actions() -> void:
	if not _setup_touch(): return
	var sprint: Vector2 = touch.control_rect(&"sprint").get_center()
	touch.handle_event(_finger(0,sprint,true))
	touch.set_mode(ExploreActorProfile.Mode.DRIVE)
	check(not touch.sample_frame().sprint)
	touch.handle_event(_finger(0,sprint,false))
	var center: Vector2 = touch.control_rect(&"move").get_center()
	touch.handle_event(_finger(1,center,true))
	touch.handle_event(_drag(1,center+Vector2(24,-48),Vector2(24,-48)))
	touch.handle_event(_finger(2,touch.control_rect(&"brake").get_center(),true))
	check(touch.sample_frame().brake,"road/rail/boat all use existing brake input")
	check(touch.sample_frame().move.length()<=1.0,"diagonal throttle/steering stays bounded")
	for id in [1,2]: touch.handle_event(_finger(id,center,false))
	touch.set_mode(ExploreActorProfile.Mode.FLY)
	touch.handle_event(_finger(3,touch.control_rect(&"ascend").get_center(),true))
	check_eq(touch.sample_frame().vertical,1.0,"flight ascent uses existing altitude axis")
	touch.handle_event(_finger(4,touch.control_rect(&"descend").get_center(),true))
	check_eq(touch.sample_frame().vertical,0.0,"opposed flight touches cancel")
	touch.handle_event(_finger(3,center,false))
	check_eq(touch.sample_frame().vertical,-1.0)

func test_cancel_and_resize_drop_pending_edges_and_require_fresh_contacts() -> void:
	if not _setup_touch(): return
	touch.handle_event(_finger(0,touch.control_rect(&"interact").get_center(),true))
	touch.handle_event(_finger(1,touch.control_rect(&"jump").get_center(),true))
	var cancel := _finger(0,Vector2.ZERO,false)
	cancel.canceled=true
	touch.handle_event(cancel)
	var frame: ExploreInputFrame = touch.sample_frame()
	check(not frame.interact and not frame.jump,"OS cancellation drops unconsumed edges")
	touch.set_usable_rect(Rect2(20,50,620,820))
	touch.handle_event(_drag(1,Vector2(500,500),Vector2(20,20)))
	check_eq(touch.take_look_delta(),Vector2.ZERO,"resize cannot turn old fingers into look")
	check(touch.is_waiting_for_release())
	touch.handle_event(_finger(1,Vector2.ZERO,false))
	check(not touch.is_waiting_for_release())

func test_menu_remains_reachable_and_layout_targets_fit_safe_portrait_bounds() -> void:
	if not _setup_touch(): return
	var menus: Array[bool] = []
	touch.menu_requested.connect(func() -> void: menus.append(true))
	var usable := Rect2(22,64,620,790)
	touch.set_usable_rect(usable)
	for mode in 3:
		touch.set_mode(mode)
		var actions: Array[StringName] = [&"menu",&"move",&"interact"]
		actions.append_array([&"sprint",&"jump"] if mode==0 else ([&"brake"] if mode==1 else [&"ascend",&"descend"]))
		for action: StringName in actions:
			var rect: Rect2 = touch.control_rect(action)
			check(usable.encloses(rect),"safe area encloses "+str(action))
			check_ge(rect.size.x,44.0)
			check_ge(rect.size.y,44.0)
	var menu: Vector2 = touch.control_rect(&"menu").get_center()
	touch.handle_event(_finger(0,menu,true))
	touch.handle_event(_finger(0,menu,false))
	check_eq(menus,[true])
	var menu_button: Button=touch.get_node("TouchMenu")
	check_eq(menu_button.mouse_filter,Control.MOUSE_FILTER_STOP,"physical pointer can reach Menu")
	menu_button.pressed.emit()
	check_eq(menus,[true,true],"Menu remains accessible to a physical pointer")
	check_eq(touch.sample_frame().move,Vector2.ZERO)

func test_combined_frame_bounds_axes_and_keeps_both_sources_action_edges() -> void:
	var hardware := ExploreInputFrame.from_keys({KEY_D:true,KEY_Q:true,KEY_SHIFT:true},{KEY_SPACE:true})
	var fingers := ExploreInputFrame.idle()
	fingers.move=Vector2(1,0)
	fingers.vertical=-1
	fingers.brake=true
	fingers.interact=true
	var frame: ExploreInputFrame = ExploreInputFrame.combined(hardware,fingers)
	check_eq(frame.move,Vector2(1,0),"same-direction sources cannot double movement")
	check_eq(frame.vertical,0.0,"opposed altitude sources cancel")
	check(frame.sprint and frame.jump and frame.brake and frame.interact,"both sources retain distinct action edges")

func test_routed_actions_show_pressed_feedback_and_keep_independent_fingers() -> void:
	if not _setup_touch(): return
	var sprint: Button = touch.get_node("TouchSprint")
	var jump: Button = touch.get_node("TouchJump")
	var interact: Button = touch.get_node("TouchInteract")
	var sprint_at: Vector2 = touch.control_rect(&"sprint").get_center()
	var jump_at: Vector2 = touch.control_rect(&"jump").get_center()
	var interact_at: Vector2 = touch.control_rect(&"interact").get_center()
	touch.handle_event(_finger(0,sprint_at,true))
	touch.handle_event(_finger(1,jump_at,true))
	touch.handle_event(_finger(2,interact_at,true))
	check(sprint.button_pressed and jump.button_pressed and interact.button_pressed,"all three routed contacts visibly press their own buttons")
	check_eq(sprint.get_draw_mode(),BaseButton.DRAW_PRESSED,"touch renders the theme's pressed appearance")
	check(touch.sample_frame().jump,"jump retains its press edge")
	check(jump.button_pressed and interact.button_pressed,"consuming edges keeps held contact feedback")
	touch.handle_event(_drag(0,Vector2(600,300),Vector2(-200,-100)))
	check(not sprint.button_pressed and jump.button_pressed and interact.button_pressed,"drag-out only releases its own feedback")
	check(not touch.sample_frame().sprint)
	touch.handle_event(_drag(0,sprint_at,Vector2(200,100)))
	check(sprint.button_pressed and touch.sample_frame().sprint,"same finger can reenter its held action")
	touch.handle_event(_drag(1,Vector2(600,300),Vector2(-200,-100)))
	touch.handle_event(_drag(1,jump_at,Vector2(200,100)))
	check(jump.button_pressed and not touch.sample_frame().jump,"edge action reentry restores feedback without a second jump")
	touch.handle_event(_finger(1,jump_at,false))
	check(not jump.button_pressed and sprint.button_pressed and interact.button_pressed,"release preserves other fingers' feedback")
	touch.handle_event(_finger(0,sprint_at,false))
	touch.handle_event(_finger(2,interact_at,false))
	check(not sprint.button_pressed and not interact.button_pressed,"final releases return to normal appearance")

func test_vehicle_feedback_and_cancellation_never_leave_a_pressed_button() -> void:
	if not _setup_touch(): return
	touch.set_mode(ExploreActorProfile.Mode.DRIVE)
	var brake: Button = touch.get_node("TouchBrake")
	touch.handle_event(_finger(0,touch.control_rect(&"brake").get_center(),true))
	check(brake.button_pressed and touch.sample_frame().brake,"brake shows the same held feedback")
	touch.set_mode(ExploreActorProfile.Mode.FLY)
	check(not brake.button_pressed,"changing actor mode clears old button feedback")
	touch.handle_event(_finger(0,Vector2.ZERO,false))
	var ascend: Button = touch.get_node("TouchAscend")
	var descend: Button = touch.get_node("TouchDescend")
	touch.handle_event(_finger(1,touch.control_rect(&"ascend").get_center(),true))
	touch.handle_event(_finger(2,touch.control_rect(&"descend").get_center(),true))
	check(ascend.button_pressed and descend.button_pressed,"opposed flight fingers each retain feedback")
	check_eq(touch.sample_frame().vertical,0.0)
	var canceled := _finger(1,Vector2.ZERO,false)
	canceled.canceled=true
	touch.handle_event(canceled)
	check(not ascend.button_pressed and not descend.button_pressed,"OS cancellation clears feedback for quarantined contacts")
	touch.handle_event(_drag(2,touch.control_rect(&"descend").get_center(),Vector2.ZERO))
	check(not descend.button_pressed,"quarantined drag cannot reengage feedback")
	touch.handle_event(_finger(2,Vector2.ZERO,false))
	touch.handle_event(_finger(3,touch.control_rect(&"ascend").get_center(),true))
	check(ascend.button_pressed,"fresh contact can engage after quarantine")
	touch.set_suspended(true)
	touch.set_suspended(false)
	check(not ascend.button_pressed,"suspension/resume leaves no held appearance")

func test_world_captions_have_contrasting_backing_and_ignore_input() -> void:
	if not _setup_touch(): return
	for caption: Label in [touch._move_label,touch._look_label]:
		check(caption.has_theme_stylebox_override("normal"),"world caption has its own backing")
		if not caption.has_theme_stylebox_override("normal"): continue
		var backing := caption.get_theme_stylebox("normal") as StyleBoxFlat
		check(backing != null and backing.bg_color.a >= .85,"caption backing protects text over bright world surfaces")
		if backing == null: continue
		var foreground := caption.get_theme_color("font_color")
		var a := _relative_luminance(foreground)
		var b := _relative_luminance(backing.bg_color)
		check_ge((maxf(a,b)+.05)/(minf(a,b)+.05),4.5,"body caption contrast stays readable")
		check_eq(caption.mouse_filter,Control.MOUSE_FILTER_IGNORE,"caption never captures movement or look")

func _relative_luminance(color: Color) -> float:
	var values := [color.r,color.g,color.b]
	for i in 3:
		values[i] = values[i]/12.92 if values[i]<=.04045 else pow((values[i]+.055)/1.055,2.4)
	return values[0]*.2126+values[1]*.7152+values[2]*.0722

func _finger(id: int, at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index=id
	event.position=at
	event.pressed=pressed
	return event

func _drag(id: int, at: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index=id
	event.position=at
	event.relative=relative
	event.screen_relative=relative
	return event
