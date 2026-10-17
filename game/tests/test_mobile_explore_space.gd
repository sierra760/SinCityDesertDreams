# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost
func before_each() -> void:
	host = Fixture.make_host(self,"mobile-explore-space")
	var city := flat_city()
	for x in range(50,80): city.building.put(x,61,Buildings.ROAD_FIRST+NetworkShapes.SHAPE_EW)
	host.begin_city(city,{},123,null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.exploration.follow_pointer_kind=false
	host.exploration.set_touch_controls_enabled(true)
func after_each() -> void:
	host.free()
	await process_frame
func test_phone_explore_reclaims_chrome_and_preserves_pause_build_routes() -> void:
	for profile: Array in [[Vector2i(320,568),Rect2i(0,20,320,548)],[Vector2i(390,844),Rect2i(0,47,390,763)],[Vector2i(667,375),Rect2i(0,0,667,375)],[Vector2i(844,390),Rect2i(47,0,750,369)]]:
		root.size=profile[0]
		host.display_layout.refresh_with_mobile_metrics(root.size,1.0,profile[1])
		await Fixture.settle(self,8)
		host.city_view_3d.set_camera_state(Vector3(64,2.4,61),0,48)
		check(host.enter_explore(),"safe road entry")
		host.exploration.set_physics_process(false)
		await Fixture.settle(self,8)
		var hud := host.explore_hud
		var touch := hud.touch_controls
		var safe := host.display_layout.logical_rect()
		check(not host.menu_bar.visible and not host.status_bar.visible,"active phone Explore gives the world both chrome bands")
		check_eq(hud._usable_rect(),safe,"Explore uses the entire phone safe area")
		check(not hud.navigation._small_map.is_visible_in_tree(),"phone Map stays a compact action")
		check(not touch._move_label.visible and not touch._look_label.visible,"permanent captions do not cover phone scenery")
		check(hud._status_panel.size.y<=96,"walking summary keeps a compact height")
		for mode in [0,1,2]:
			hud.set_status({"mode":mode,"speed":.5,"altitude":.25,"prompt":"F to enter nearby vehicle"})
			await Fixture.settle(self,6)
			var summary := hud.get("_phone_summary") as Label
			check(summary!=null and summary.is_visible_in_tree(),"phone guidance is visible")
			if summary!=null:
				check_ge(summary.size.y,summary.get_theme_font("font").get_height(summary.get_theme_font_size("font_size")),"the compact summary has room to draw a line")
				check(summary.text.contains("Interact"),"phone keeps interaction guidance")
			var occupied := [hud._status_panel.get_global_rect(),hud.navigation._compact.get_global_rect()]
			for action: StringName in [&"menu",&"move"]+touch._mode_actions():
				var rect := touch.control_rect(action)
				check(safe.grow(.1).encloses(rect),"safe target "+str(action))
				check_ge(rect.size.x,44)
				check_ge(rect.size.y,44)
				for other: Rect2 in occupied: check(not other.intersects(rect),"independent finger region "+str(action))
				occupied.append(rect)
		host.sim.stats.population = 1234567
		host.sim.stats.tourists = 2345678
		host.sim._emit_scalars()
		host.exploration.suspend()
		await Fixture.settle(self,8)
		check(host.menu_bar.visible and host.status_bar.visible,"paused phone restores city menus and alerts")
		_check_current_counts()
		check(hud._scroll.get_global_rect().grow(.1).encloses(hud._resume_button.get_global_rect()),"Resume appears without scrolling")
		host.exploration.resume()
		await Fixture.settle(self,8)
		check(not host.menu_bar.visible and not host.status_bar.visible,"Resume reclaims chrome again")
		host.return_to_build()
		await Fixture.settle(self,8)
		check(host.menu_bar.visible and host.status_bar.visible,"Build restores city chrome")
		_check_current_counts()
func test_tablet_keeps_its_roomy_shell_and_navigation() -> void:
	for size: Vector2i in [Vector2i(768,1024),Vector2i(1194,834)]:
		root.size=size
		host.display_layout.refresh_with_mobile_metrics(size,1,Rect2i(Vector2i.ZERO,size))
		await Fixture.settle(self,8)
		host.city_view_3d.set_camera_state(Vector3(64,2.4,61),0,48)
		check(host.enter_explore())
		host.exploration.set_physics_process(false)
		await Fixture.settle(self,8)
		check(host.menu_bar.visible and host.status_bar.visible,"iPad retains city chrome")
		check(host.explore_hud.navigation._small_map.is_visible_in_tree(),"iPad retains live map")
		host.return_to_build()
		await Fixture.settle(self,4)

func test_phone_objectives_refresh_and_transit_doors_have_priority() -> void:
	root.size=Vector2i(390,844)
	host.display_layout.refresh_with_mobile_metrics(root.size,1,Rect2i(0,47,390,763))
	var hud := host.explore_hud
	hud.show_session(true)
	hud.set_status({"mode":0,"objectives":[{"status":"active","text":"First objective"}]})
	await Fixture.settle(self,8)
	hud.set_status({"mode":0,"objectives":[{"status":"active","text":"Second objective"}]})
	await Fixture.settle(self,8)
	check(hud._phone_summary.text.contains("Second objective"),"tracked objective updates even when everything else stays unchanged")
	hud.set_status({"mode":0,"prompt":"F to exit nearby train"})
	hud.set_transit_status({"passenger":true,"transit_kind":"subway","current_stop":"Northwest Desert Terminal","next_stop":"Southern Valley Transit Center","destination":"Faraway Creek Station","door_state":"boarding","departure_seconds":4})
	await Fixture.settle(self,8)
	check(hud._phone_summary.text.find("Doors:")<hud._phone_summary.text.find("Next:"),"doors and departure stay ahead of long route labels")

func _check_current_counts() -> void:
	var pop := host.status_bar.population_label
	var tourists := host.status_bar.get("tourists_label") as Label
	check(tourists != null,"restored chrome includes tourists")
	if tourists == null: return
	check(pop.is_visible_in_tree() and tourists.is_visible_in_tree(),"both counts return immediately from hidden Explore chrome")
	check(pop.tooltip_text.contains("1,234,567") and tourists.tooltip_text.contains("2,345,678"),"latest scalars survive hidden chrome")
	check(absf(pop.global_position.y-tourists.global_position.y)<1,"restored counts remain adjacent")
	for label: Label in [pop,tourists]:
		check(host.display_layout.logical_rect().grow(.1).encloses(label.get_global_rect()),"restored counts fit safe display")
