# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Phone regressions: persistent chrome must leave city space, and resizing
## cannot turn UI contacts into construction or retain held Explore actions.
extends "res://tests/exploration/async_test_case.gd"
const HostFixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost

func before_each() -> void:
	host = HostFixture.make_host(self, "iphone-layout-tests")

func after_each() -> void:
	host.free()
	await process_frame

func phone(dimensions: Vector2i, safe: Rect2i, keyboard: int = 0, backing: float = 1.0) -> void:
	root.size = dimensions
	host.display_layout.refresh_with_mobile_metrics(dimensions,backing,safe,keyboard)
	await HostFixture.settle(self, 6)

func test_phone_shell_leaves_the_city_open_and_keeps_all_menu_actions() -> void:
	for display: Dictionary in [
		{"size":Vector2i(375,667),"safe":Rect2i(0,20,375,647)},
		{"size":Vector2i(390,844),"safe":Rect2i(0,47,390,763)},
		{"size":Vector2i(844,390),"safe":Rect2i(47,0,750,369)}]:
		await phone(display.size,display.safe)
		var usable := host.display_layout.logical_rect()
		check(not host.toolbar.visible,"phone tools collapse until requested")
		check(not host.mini_map.visible,"phone minimap leaves city space")
		check(usable.grow(.1).encloses(host.menu_bar.get_global_rect()),"all top actions fit phone")
		check(host.status_bar.size.y<=64.0,"phone summary stays compact")
		check(not host.touch_ui_owned(usable.get_center()),"city center is free for a phone gesture")
		for action: StringName in [&"city_save",&"city_load",&"explore",&"rotate",&"go_to_emergency",&"help"]:
			check(host.menu_bar.has_action(action),"compact menu retains "+str(action))

func test_phone_tools_selection_closes_drawer_without_changing_city() -> void:
	await phone(Vector2i(390,844),Rect2i(0,47,390,763))
	var original := SaveFormat.encode_city(host.sim.city)
	host.shell.set_phone_tools_open(true)
	await HostFixture.settle(self, 6)
	check(host.toolbar.is_visible_in_tree())
	check(host.touch_ui_owned(host.toolbar.get_global_rect().get_center()))
	check(host.display_layout.logical_rect().grow(.1).encloses(host.toolbar.get_global_rect()))
	host.toolbar.button_for(Tools.Kind.ROAD).pressed.emit()
	await HostFixture.settle(self, 6)
	check_eq(host.tool,Tools.Kind.ROAD)
	check(not host.toolbar.visible,"choosing a tool returns to the city")
	check_eq(SaveFormat.encode_city(host.sim.city),original,"opening and choosing are not construction")

func test_phone_status_details_preserve_metrics_and_keyboard_roundtrip() -> void:
	await phone(Vector2i(375,667),Rect2i(0,20,375,647))
	host.status_bar.set_details_open(true)
	await HostFixture.settle(self, 6)
	for label: Label in [host.status_bar.funds_label,host.status_bar.date_label,host.status_bar.population_label,host.status_bar.tool_label,host.status_bar.speed_label]:
		check(label.is_visible_in_tree(),"expanded detail retains "+label.text)
	host.status_bar.set_details_open(false)
	await phone(Vector2i(375,667),Rect2i(0,20,375,647),260)
	check(host.display_layout.logical_rect().grow(.1).encloses(host.status_bar.get_global_rect()))
	await phone(Vector2i(375,667),Rect2i(0,20,375,647))
	check(host.status_bar.size.y<=64.0,"keyboard dismissal restores compact summary")

func test_phone_rotation_returns_to_closed_tools_and_restores_tablet_layout() -> void:
	await phone(Vector2i(390,844),Rect2i(0,47,390,763))
	host.shell.set_phone_tools_open(true)
	await phone(Vector2i(844,390),Rect2i(47,0,750,369))
	check(not host.toolbar.visible,"rotation closes drawer and releases ownership")
	await phone(Vector2i(1194,834),Rect2i(0,24,1194,790))
	check(host.toolbar.visible,"iPad keeps the existing persistent tools")
	check(host.mini_map.visible,"iPad restores the saved minimap choice")

func test_short_phone_explore_targets_do_not_overlap_critical_status() -> void:
	var city := flat_city()
	for x in range(50,80): city.building.put(x,61,Buildings.ROAD_FIRST+NetworkShapes.SHAPE_EW)
	host.begin_city(city,{},123,null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	await phone(Vector2i(667,375),Rect2i(0,0,667,375))
	host.city_view_3d.set_camera_state(Vector3(64,2.4,61),0,48)
	host.exploration.set_touch_controls_enabled(true)
	check(host.enter_explore(),"real road-supported entry")
	if not host.exploration.is_active(): return
	host.exploration.set_physics_process(false)
	for mode in [0,1,2]:
		host.explore_hud.set_suspended(false)
		host.explore_hud.set_status({"mode":mode,"prompt":"Interact to call or ride the elevator","message":""})
		await HostFixture.settle(self, 6)
		var touch := host.explore_hud.touch_controls
		var status_rect := host.explore_hud._status_panel.get_global_rect()
		var rects: Array[Rect2] = []
		for action: StringName in [&"move",&"menu"]+touch._mode_actions():
			var rect := touch.control_rect(action)
			check(host.display_layout.logical_rect().grow(.1).encloses(rect),"phone fits "+str(action))
			check_ge(rect.size.x,44.0)
			check_ge(rect.size.y,44.0)
			check(not status_rect.intersects(rect),"critical status clears "+str(action))
			for previous: Rect2 in rects: check(not previous.intersects(rect),"separate finger targets")
			rects.append(rect)
		host.exploration.suspend()
		await HostFixture.settle(self, 6)
		check(host.display_layout.logical_rect().grow(.1).encloses(host.explore_hud._panel.get_global_rect()),"Resume menu fits short phone")

func test_phone_large_ui_scale_keeps_actions_within_the_safe_width() -> void:
	await phone(Vector2i(1170,2532),Rect2i(0,141,1170,2289),0,3.0)
	host.display_layout.set_ui_scale(200)
	await HostFixture.settle(self, 6)
	check(host.display_layout.logical_rect().size.x>=320.0,"phone scale cannot collapse the action width")
	check(host.display_layout.logical_rect().grow(.1).encloses(host.menu_bar.phone_inspect_button.get_global_rect()))
	check_ge(host.menu_bar.phone_inspect_button.size.y*float(host.display_layout.metrics.effective_percent)/100.0,44.0)

func test_phone_summary_keeps_current_tool_and_alert_identity_visible() -> void:
	await phone(Vector2i(390,844),Rect2i(0,47,390,763))
	host.select_tool(Tools.Kind.ROAD)
	host.status_bar.set_alerts(PackedStringArray(["Emergency"]))
	await HostFixture.settle(self, 6)
	check(host.status_bar._phone_summary.text.contains("Road"),"closed tools keep the selected tool identity")
	check_eq(host.status_bar._details_button.text,"Alerts","collapsed warnings have an explicit touch target")

func test_phone_look_caption_clears_interaction_status() -> void:
	await phone(Vector2i(390,844),Rect2i(0,47,390,763))
	host.explore_hud.set_touch_controls_enabled(true)
	host.explore_hud.show_session(true)
	host.explore_hud.set_status({"mode":0,"prompt":"Interact to ride the elevator"})
	await HostFixture.settle(self, 6)
	check(not host.explore_hud._status_panel.get_global_rect().intersects(host.explore_hud.touch_controls._look_label.get_global_rect()),"look caption cannot cover the interaction prompt")

func test_small_phone_inspector_fits_its_usable_width() -> void:
	await phone(Vector2i(320,568),Rect2i(0,20,320,548))
	host.open_query(Vector2i(64,64))
	await HostFixture.settle(self, 6)
	check(host.display_layout.logical_rect().grow(.1).encloses(host.query_panel.get_global_rect()),"inspector shrinks with the phone")

func test_short_narrow_explore_actions_have_their_own_fingers() -> void:
	var touch := ExploreTouchControls.new()
	root.add_child(touch)
	touch.set_enabled(true)
	touch.set_session_active(true)
	for width in [320,375]:
		touch.set_usable_rect(Rect2(0,50,width,250))
		for mode in [0,1,2]:
			touch.set_mode(mode)
			for action: StringName in touch._mode_actions():
				var rect := touch.control_rect(action)
				check(not rect.intersects(touch.control_rect(&"move")),"thumb action clears movement")
				var press := InputEventScreenTouch.new()
				press.index=1
				press.position=rect.get_center()
				press.pressed=true
				touch.handle_event(press)
				check_eq(touch._contacts[1].role,action,"finger owns the requested action")
				press.pressed=false
				touch.handle_event(press)
	touch.free()

func test_phone_inspect_stays_unavailable_while_shaping_terrain() -> void:
	await phone(Vector2i(390,844),Rect2i(0,47,390,763))
	host.session.begin_editing(flat_city(),{})
	await HostFixture.settle(self, 6)
	check(not host.menu_bar.phone_tools_button.disabled,"terrain tools remain available")
	check(host.menu_bar.phone_inspect_button.disabled,"Inspect follows the playable-city stage gate")
