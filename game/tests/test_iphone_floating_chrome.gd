# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## iPhone chrome gives the city its screen: floating top buttons instead of a
## strip, a one-face footer, and paused Explore without the city footer.
extends "res://tests/exploration/async_test_case.gd"
const HostFixture := preload("res://tests/helpers/host_fixture.gd")
const PORTRAIT := [Vector2i(402,874),Rect2i(0,62,402,778)]
const LANDSCAPE := [Vector2i(874,402),Rect2i(62,0,750,381)]
const SMALL_LANDSCAPE := [Vector2i(667,375),Rect2i(0,0,667,375)]
var host: GameHost

func before_each() -> void:
	host = HostFixture.make_host(self, "iphone-floating-chrome-tests")

func after_each() -> void:
	host.free()
	await process_frame

func phone(display: Array) -> void:
	root.size = display[0]
	host.display_layout.refresh_with_mobile_metrics(display[0],1.0,display[1],0,"iOS")
	await HostFixture.settle(self, 6)

func enter_explore() -> bool:
	var city := flat_city()
	for x in range(50,80): city.building.put(x,61,Buildings.ROAD_FIRST+NetworkShapes.SHAPE_EW)
	host.begin_city(city,{},123,null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.city_view_3d.set_camera_state(Vector3(64,2.4,61),0,48)
	host.exploration.set_touch_controls_enabled(true)
	var entered := host.enter_explore()
	if entered: host.exploration.set_physics_process(false)
	return entered

func test_phone_top_buttons_float_and_leave_the_strip_to_the_city() -> void:
	for display: Array in [PORTRAIT,LANDSCAPE,SMALL_LANDSCAPE]:
		await phone(display)
		var bar := host.menu_bar
		check_eq(bar.mouse_filter,Control.MOUSE_FILTER_IGNORE,"phone bar passes touches through")
		check(not bar.get_node("MenuSurface").visible,"phone draws no shell strip")
		check(not bar.get_node("MenuBorder").visible,"phone draws no strip border")
		check(not bar._phone_menu.flat,"Menu has a raised face over the city")
		var controls := bar.phone_controls().filter(func(c: Control) -> bool: return c.is_visible_in_tree())
		check_ge(controls.size(),2)
		var safe := host.display_layout.logical_rect()
		for control: Control in controls:
			var rect := control.get_global_rect()
			check(host.touch_ui_owned(rect.get_center()),"floating button owns its touch")
			check_ge(rect.size.y,44.0)
			check(Rect2(Vector2.ZERO,Vector2(display[0])).grow(.1).encloses(rect),"button on screen")
			if safe.position.y > 44.0: continue
			check(safe.grow(.1).encloses(rect),"landscape buttons stay in the safe area")
		# Between the left buttons and Menu, the strip is city.
		var gap := Vector2((controls[0].get_global_rect().end.x+bar._phone_menu.get_global_rect().position.x)*.5,bar._phone_menu.get_global_rect().get_center().y)
		# In portrait that gap is the camera housing, outside the safe area.
		if safe.has_point(gap): check(not host.touch_ui_owned(gap),"space between buttons is a city gesture")
		else: check(host.touch_ui_owned(gap),"camera housing is never a city gesture")

func test_phone_footer_is_one_face_and_messages_fold_into_details() -> void:
	for display: Array in [PORTRAIT,LANDSCAPE]:
		await phone(display)
		var footer := host.status_bar
		footer.set_message("")
		await HostFixture.settle(self, 4)
		check_lt(footer.size.y,56.1,"compact footer is a single 44-unit face")
		footer.set_message("Not enough money for that road.")
		await HostFixture.settle(self, 4)
		check(footer.is_message_line_shown(),"a new message shows on the phone")
		footer._on_message_timeout()
		await HostFixture.settle(self, 4)
		check(not footer.is_message_line_shown(),"then folds away")
		check_lt(footer.size.y,56.1,"and the footer returns to one face")
		footer.set_details_open(true)
		await HostFixture.settle(self, 4)
		check(footer.message_label.is_visible_in_tree(),"Details keeps the message")
		footer.set_details_open(false)
		footer.set_message("Not enough money for that road.")
		await HostFixture.settle(self, 4)
		check(footer.is_message_line_shown(),"a repeated message shows again")
		footer._on_message_timeout()

func test_desktop_footer_keeps_its_message() -> void:
	host.display_layout.refresh_with_metrics(Vector2i(1280,800),1.0)
	await HostFixture.settle(self, 4)
	host.status_bar.set_message("Saved.")
	host.status_bar._on_message_timeout()
	check(host.status_bar.message_label.visible,"desktop status line does not time out")
	check_eq(host.menu_bar.mouse_filter,Control.MOUSE_FILTER_STOP,"desktop keeps its menu bar")
	check(host.menu_bar.get_node("MenuSurface").visible)

func test_paused_phone_explore_gives_the_panel_the_footer_space() -> void:
	await phone(SMALL_LANDSCAPE)
	check(await enter_explore(),"real road-supported entry")
	if not host.exploration.is_active(): return
	await phone(SMALL_LANDSCAPE)
	host.exploration.suspend()
	await HostFixture.settle(self, 8)
	check(not host.status_bar.visible,"city footer stays away in phone Explore")
	check(host.menu_bar.visible and host.menu_bar._phone_menu.is_visible_in_tree(),"city Menu stays available while paused")
	check(not host.menu_bar.phone_tools_button.visible,"no disabled Tools over the street")
	check(not host.menu_bar.phone_inspect_button.visible,"no disabled Inspect over the street")
	var hud := host.explore_hud
	check(not hud.touch_controls._buttons[&"menu"].visible,"no disabled Menu copy over the panel")
	check(not hud.navigation._compact.visible,"floating Map moves into the panel")
	check(hud._panel_map_button.is_visible_in_tree(),"panel offers Map")
	var panel := hud._panel.get_global_rect()
	check(host.display_layout.logical_rect().grow(.1).encloses(panel),"pause panel fits")
	check(not panel.intersects(host.menu_bar._phone_menu.get_global_rect()),"pause panel clears city Menu")
	var before := SaveFormat.encode_city(host.sim.city)
	hud._panel_map_button.pressed.emit()
	await HostFixture.settle(self, 6)
	check(hud.navigation.expanded,"panel Map opens the Explore map")
	check(not hud.navigation._body.vertical,"landscape map sits beside its controls")
	check_ge(hud.navigation._large_map.size.x,200.0,"landscape map stays large")
	check(host.display_layout.logical_rect().grow(.1).encloses(hud.navigation._expanded.get_global_rect()),"map fits")
	host.exploration.toggle_navigation()
	await HostFixture.settle(self, 6)
	check(not hud.navigation.expanded)
	check_eq(SaveFormat.encode_city(host.sim.city),before,"opening Explore panels is not construction")
	host.exploration.resume()
	await HostFixture.settle(self, 6)
	check(hud.touch_controls._buttons[&"menu"].is_visible_in_tree(),"active Explore restores Menu")
	host.return_to_build()
	await HostFixture.settle(self, 8)
	check(host.status_bar.visible,"Build restores the footer")
	check(host.menu_bar.phone_tools_button.is_visible_in_tree(),"Build restores Tools")

func test_portrait_expanded_map_keeps_controls_below() -> void:
	await phone(PORTRAIT)
	check(await enter_explore(),"real road-supported entry")
	if not host.exploration.is_active(): return
	await phone(PORTRAIT)
	host.exploration.toggle_navigation()
	await HostFixture.settle(self, 6)
	check(host.explore_hud.navigation._body.vertical,"portrait map stacks above its controls")
	check(host.display_layout.logical_rect().grow(.1).encloses(host.explore_hud.navigation._expanded.get_global_rect()))

func test_short_narrow_walking_keeps_every_action() -> void:
	var touch := ExploreTouchControls.new()
	root.add_child(touch)
	touch.set_enabled(true)
	touch.set_session_active(true)
	touch.set_phone_layout(true)
	for width in [320,375,430]:
		touch.set_usable_rect(Rect2(0,50,width,250))
		touch.set_mode(0)
		check(&"weapon" in touch._mode_actions(),"switching weapons never needs a bigger screen")
		var rects: Array[Rect2] = [touch.control_rect(&"move")]
		for action: StringName in touch._mode_actions():
			var rect := touch.control_rect(action)
			check(touch._buttons[action].visible,str(action)+" shown")
			check(Rect2(0,50,width,250).grow(.1).encloses(rect),str(action)+" fits")
			for other: Rect2 in rects: check(not other.intersects(rect),str(action)+" has its own finger")
			rects.append(rect)
		var interact := touch.control_rect(&"interact")
		var attack := touch.control_rect(&"attack")
		check(is_equal_approx(interact.position.y,attack.position.y) and attack.position.x < interact.position.x,"Attack sits beside Interact")
	touch.free()
