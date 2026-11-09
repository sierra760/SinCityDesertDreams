# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const MAIN := preload("res://scenes/main.tscn")
const PREFS := "user://test_mayor_spawn_choice.cfg"
var host: GameHost

func before_each() -> void:
	root.size = Vector2i(1280,800)
	host = MAIN.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)

func after_each() -> void:
	if host.sim._ctx != null: host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	await physics_frame

func _play(house: bool = true) -> void:
	var city := flat_city()
	for x: int in range(18,25): city.building.put(x,22,30)
	city.building.put(64,64,30)
	if house: city.stamp_building(20,20,Buildings.MAYORS_RESIDENCE)
	host.begin_city(city,{},4242,CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.city_view_3d.set_camera_state(Vector3(20.5,2.5,22.5),1,12)
	await physics_frame

func test_no_house_starts_near_the_active_build_view() -> void:
	await _play(false)
	check(host.enter_explore())
	check(host.exploration.is_active())
	if not host.exploration.is_active(): return
	var at := host.exploration.pedestrian.global_position
	check_eq(Vector2i(floori(at.x),floori(at.z)),Vector2i(20,22),"camera-adjacent road beats map-center road")
	check(host.exploration.car==null and host.exploration.helicopter==null)

func test_house_prompts_once_and_cancel_keeps_build_unchanged() -> void:
	await _play()
	var before := SaveFormat.encode_city(host.sim.city)
	var camera := host.city_view_3d.center
	check(host.enter_explore(),"choice request accepted")
	check(not host.exploration.is_active(),"choice precedes actor creation")
	check(host.notice_dialog.is_open())
	check_eq(host.notice_dialog.choice_buttons.size(),3)
	check_eq(host.notice_dialog.choice_buttons[0].text,"Current View")
	check(not host.enter_explore(),"pending choice cannot duplicate")
	host.notice_dialog.dismiss()
	check(not host.exploration.is_active())
	check_eq(host.city_view_3d.center,camera)
	check_eq(SaveFormat.encode_city(host.sim.city),before)
	check(host.toolbar.visible)

func test_both_choices_keep_the_same_four_vehicle_fleet_at_the_house() -> void:
	await _play()
	for choice: StringName in [&"center",&"house"]:
		check(host.enter_explore())
		check(host.notice_dialog.is_open())
		host.notice_dialog.dismiss(choice)
		check(host.exploration.is_active())
		if not host.exploration.is_active(): return
		check_eq(host.exploration.owned_vehicles.size(),4)
		var at := host.exploration.pedestrian.global_position
		if choice == &"center": check_eq(Vector2i(floori(at.x),floori(at.z)),Vector2i(20,22))
		else: check_lt(Vector2(at.x-21,at.z-21).length(),1)
		for vehicle: CharacterBody3D in host.exploration.owned_vehicles:
			check_lt(Vector2(vehicle.global_position.x-21,vehicle.global_position.z-21).length(),1.3)
		host.return_to_build()

func test_loading_street_entry_uses_the_active_view_with_or_without_a_house() -> void:
	for house: bool in [false,true]:
		await _play(house)
		host.explore_switch.request()
		if house: host.notice_dialog.dismiss(&"center")
		for frame in 12: await process_frame
		check(host.exploration.is_active())
		if not host.exploration.is_active(): return
		var at := host.exploration.pedestrian.global_position
		check_eq(Vector2i(floori(at.x),floori(at.z)),Vector2i(20,22))
		host.return_to_build()

func test_dispose_invalidates_a_pending_house_choice() -> void:
	await _play()
	check(host.enter_explore())
	host.explore_switch.dispose()
	host.notice_dialog.dismiss(&"house")
	check(not host.exploration.is_active(),"cancelled old choice cannot create actors")

func test_choice_buttons_fit_a_narrow_phone() -> void:
	root.size = Vector2i(320,568)
	host.display_layout.refresh_with_mobile_metrics(Vector2i(320,568),1.0,Rect2i(0,0,320,568),0,"iOS")
	await _play()
	check(host.enter_explore())
	for frame in 8: await process_frame
	var screen := Rect2(Vector2.ZERO,Vector2(320,568))
	for button: Button in host.notice_dialog.choice_buttons:
		check(screen.encloses(button.get_global_rect()),"each spawn choice fits narrow phone: "+button.text)

func test_replacing_the_city_cancels_the_old_choice() -> void:
	await _play()
	check(host.enter_explore())
	var next := flat_city()
	next.building.put(64,64,30)
	host.begin_city(next,{},5353,CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.notice_dialog.dismiss(&"house")
	check(not host.exploration.is_active())
	check_eq(host.sim.city,next)

func test_deferred_loading_cannot_enter_a_replacement_city() -> void:
	await _play()
	host.explore_switch.request()
	check(host.notice_dialog.is_open())
	host.notice_dialog.dismiss(&"house")
	check(host.loading_screen.visible,"entry is waiting behind the loading surface")
	var next := flat_city()
	next.building.put(64,64,30)
	host.begin_city(next,{},6767,CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	for frame in 12: await process_frame
	check(not host.exploration.is_active(),"old loading callback cannot enter the new city")
	check_eq(host.sim.city,next)

func test_dispose_cancels_entry_already_waiting_for_a_loading_frame() -> void:
	await _play()
	host.explore_switch.request()
	host.notice_dialog.dismiss(&"house")
	host.explore_switch.dispose()
	for frame in 12: await process_frame
	check(not host.exploration.is_active(),"disposed entry cannot resume after its loading await")
