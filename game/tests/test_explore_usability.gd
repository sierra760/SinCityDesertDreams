# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Explore feedback, pause and controls-hint behaviour that needs no city world.
extends "res://tests/test_case.gd"

func _session(hud: ExploreHUD) -> CityExplorationController:
	var session := CityExplorationController.new()
	session.hud = hud
	session.set("_active",true)
	return session

func _hud(touch: bool = false) -> ExploreHUD:
	var hud := ExploreHUD.new()
	root.add_child(hud)
	hud.set_touch_controls_enabled(touch)
	hud.show_session(true)
	return hud

func test_transient_message_expires_after_active_play() -> void:
	var session := CityExplorationController.new()
	session._message = "Stop before exiting."
	session._tick_message(.016)
	session._tick_message(1.0)
	check_eq(session._message,"Stop before exiting.","message stays readable")
	session._tick_message(3.5)
	check_eq(session._message,"","message clears after about four seconds")
	session._message = "Moved you back to safe ground."
	session._tick_message(.016)
	session._tick_message(2.0)
	session._message = "There is no clear place to exit."
	session._tick_message(.016)
	session._tick_message(3.0)
	check_eq(session._message,"There is no clear place to exit.","a new message restarts its time")
	session.free()

func test_escape_style_suspension_focuses_resume_only_without_touch() -> void:
	var hud := _hud()
	hud.set_suspended(true)
	check(hud._resume_button.has_focus(),"Enter/Space resumes from the paused panel")
	hud.set_suspended(false)
	hud._resume_button.release_focus()
	hud.set_suspended(true,false)
	check(not hud._resume_button.has_focus(),"a modal keeps its own focus")
	hud.free()
	var touch := _hud(true)
	touch.set_suspended(true)
	check(not touch._resume_button.has_focus(),"touch play has no keyboard focus ring")
	touch.free()

func test_modal_suspension_resumes_but_manual_pause_stays() -> void:
	var hud := _hud()
	var session := _session(hud)
	var modal := [true]
	var window := [false]
	session.modal_open = func() -> bool: return modal[0]
	session.window_open = func() -> bool: return window[0]
	session.suspend()
	session._check_auto_resume()
	check(session.is_suspended(),"suspended while the notice is open")
	modal[0] = false
	session._check_auto_resume()
	check(not session.is_suspended(),"closing the notice resumes Explore")
	session.pause()
	modal[0] = true
	session._check_auto_resume()
	modal[0] = false
	session._check_auto_resume()
	check(session.is_suspended(),"a manual pause stays paused after a notice")
	window[0] = true
	session.resume()
	check(session.is_suspended(),"Resume waits for an open window")
	check(session._message.contains("window"),"the refusal explains itself")
	window[0] = false
	session.resume()
	check(not session.is_suspended())
	session.free()
	hud.free()

func test_escape_press_marks_the_following_suspension_manual() -> void:
	var hud := _hud()
	var session := _session(hud)
	var modal := [false]
	session.modal_open = func() -> bool: return modal[0]
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	check(not session.handle_event(escape),"Escape still reaches the host")
	session.suspend()
	modal[0] = true
	session._check_auto_resume()
	modal[0] = false
	session._check_auto_resume()
	check(session.is_suspended(),"Escape pause is never auto-resumed")
	session.free()
	hud.free()

func test_exit_message_is_reported_once() -> void:
	var session := CityExplorationController.new()
	var returned := [0]
	session.return_requested.connect(func() -> void: returned[0] += 1)
	session._request_return("No safe place remains. Returning to Build.")
	check_eq(returned[0],1)
	check_eq(session.last_exit_message(),"No safe place remains. Returning to Build.")
	check_eq(session.take_exit_message(),"No safe place remains. Returning to Build.")
	check_eq(session.take_exit_message(),"","shown once")
	session.free()

func test_controls_hint_follows_mode_bindings_and_touch() -> void:
	var hud := _hud()
	hud.set_status({"mode":0})
	check(hud._hint_panel.visible,"hint shows after entering Explore")
	check(hud._hint_label.text.contains("WASD move") and hud._hint_label.text.contains("Space jump"))
	hud.set_status({"mode":1,"vehicle":"bus"})
	check(hud._hint_label.text.contains("throttle") and hud._hint_label.text.contains("steer"),"driving hint")
	hud.set_status({"mode":1,"vehicle":"train"})
	check(not hud._hint_label.text.contains("steer"),"rail vehicles have no steering")
	hud.controls.assign(&"interact",0,KEY_H)
	hud.set_status({"mode":2})
	check(hud._hint_label.text.contains("Q climb") and hud._hint_label.text.contains("E descend"),"flight hint")
	check(hud._hint_label.text.contains("H exit"),"hint follows rebinding")
	hud._hint_until_msec = 0
	hud.set_status({"mode":2})
	check(not hud._hint_panel.visible,"hint hides after its time")
	hud.set_suspended(true)
	check(hud._panel_hint_label.visible and hud._panel_hint_label.text.contains("climb"),"paused panel always lists controls")
	hud.free()
	var touch := _hud(true)
	touch.set_status({"mode":0})
	check(not touch._hint_panel.visible,"touch shows no keyboard hint")
	touch.set_suspended(true)
	check(not touch._panel_hint_label.visible)
	touch.free()

func test_arrow_keys_are_explore_alternates_without_build_conflict() -> void:
	var input := ControlBindings.new()
	var up := InputEventKey.new()
	up.keycode = KEY_UP
	up.physical_keycode = KEY_UP
	up.pressed = true
	check(input.matches(up,&"move_forward"),"Up moves forward in Explore")
	check(input.matches(up,&"pan_forward"),"Up still pans in Build")
	check_eq(ControlBindings.sanitize(input.values()),input.values(),"defaults are a valid profile")
	check_eq(input.assign(&"move_forward",0,KEY_UP),"","an action's own alternate can move to its primary slot")
	check_eq(input.values().move_forward,[KEY_UP])

func test_platform_destination_header_and_change_hint() -> void:
	var hud := _hud()
	var status := {"station_id":0,"destinations":[{"id":2,"name":"West"},{"id":3,"name":"East"}],"selected_destination":3,"can_choose_destination":true}
	hud.set_transit_status(status)
	check(hud._destination_header.visible and hud._destination_header.text == "Destination")
	check(hud._transit_label.text.contains("To: East — Esc to change"))
	hud.set_transit_status({"passenger":true,"current_stop":"North","next_stop":"West","destination":"East","door_state":"closed"})
	check(hud._transit_label.text.contains("To: East"),"riders see the final stop")
	hud.free()
