# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The city's identity stays reachable without crowding the mobile shell.
extends "res://tests/exploration/async_test_case.gd"
const HostFixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost

func before_each() -> void:
	host = HostFixture.make_host(self,"city-name-control-tests")
	host.sim.city.name = "Silver Springs"
	host.shell.set_chrome_visible(true)
	await HostFixture.settle(self,6)

func after_each() -> void:
	host.free()
	await process_frame

func name_button() -> Button:
	var button := host.ui_layer.get_node_or_null("CityName") as Button
	check(button != null,"gameplay offers a tappable city name")
	return button

func display(size_px: Vector2i, safe: Rect2i, mobile := true) -> void:
	root.size = size_px
	if mobile: host.display_layout.refresh_with_mobile_metrics(size_px,1.0,safe,0,"iOS")
	else: host.display_layout.refresh_with_metrics(size_px,1.0,safe)
	await HostFixture.settle(self,8)

func test_tapping_name_renames_and_round_trips_without_moving_save_slot() -> void:
	var button := name_button()
	if button == null: return
	check_eq(button.text,"Silver Springs")
	host.save_path = "user://existing-city.sc2d"
	host.sim.set_speed(GameClock.Speed.FAST)
	button.pressed.emit()
	check(host.notice_dialog.is_open())
	check_eq(host.notice_dialog.line_edit.text,"Silver Springs")
	check_eq(host.sim.speed,GameClock.Speed.PAUSED)
	host.notice_dialog.line_edit.text = "  Las Luciérnagas  "
	host.notice_dialog.line_edit.text_submitted.emit(host.notice_dialog.line_edit.text)
	await HostFixture.settle(self,6)
	check_eq(host.sim.city.name,"Las Luciérnagas")
	check_eq(button.text,"Las Luciérnagas")
	check_eq(host.save_path,"user://existing-city.sc2d","renaming preserves the chosen file")
	check_eq(host.sim.speed,GameClock.Speed.FAST)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	var path := "user://city-name-roundtrip.sc2d"
	check_eq(SaveFormat.save(path,host.sim.city,host.sim.snapshot()),OK)
	var loaded := SaveFormat.load(path)
	check(loaded.ok)
	check_eq(loaded.city.name,"Las Luciérnagas")
	check(host.begin_city(loaded.city,loaded.snapshot,-1,null,loaded.topology))
	await HostFixture.settle(self,6)
	check_eq(button.text,"Las Luciérnagas","loading refreshes the city name")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_cancel_and_blank_keep_name_and_release_the_modal() -> void:
	var button := name_button()
	if button == null: return
	for cancel: bool in [true,false]:
		button.pressed.emit()
		host.notice_dialog.line_edit.text = "Other City" if cancel else "   "
		if cancel: host.escape()
		else: host.notice_dialog.dismiss(&"submit")
		check_eq(host.sim.city.name,"Silver Springs")
		check_eq(host.modal_depth,0)
		check(not host.notice_dialog.is_open())
		check_eq(button.text,"Silver Springs")

func test_name_follows_city_and_disappears_at_title() -> void:
	var button := name_button()
	if button == null: return
	var city := flat_city()
	city.name = "La Presa"
	check(host.begin_city(city,{},34,null))
	await HostFixture.settle(self,6)
	check_eq(button.text,"La Presa")
	host._show_title()
	await HostFixture.settle(self,6)
	check(not button.is_visible_in_tree())

func test_editing_name_survives_regenerating_and_founding() -> void:
	var button := name_button()
	if button == null: return
	var city := flat_city()
	city.name = "New City"
	check(host.session.begin_editing(city,{"name":"New City","seed":45}))
	button.pressed.emit()
	host.notice_dialog.line_edit.text = "Reborn Junction"
	host.notice_dialog.dismiss(&"submit")
	check_eq(host.editing_params.name,"Reborn Junction")
	check_eq(host.status_bar.population_label.text,"Reborn Junction")
	var regenerated := host.regenerate(46)
	check(regenerated != null)
	check_eq(regenerated.name,"Reborn Junction")
	check(host.found_city())
	check_eq(host.sim.city.name,"Reborn Junction")

func test_long_names_fit_phone_controls_safe_areas_and_rotation() -> void:
	var button := name_button()
	if button == null: return
	host.sim.city.name = "The Very Long City of Silver Springs and Beyond"
	host.shell.set_chrome_visible(true)
	for item: Array in [
		[Vector2i(375,667),Rect2i(0,20,375,647)],
		[Vector2i(402,874),Rect2i(0,62,402,778)],
		[Vector2i(667,375),Rect2i(0,0,667,375)],
		[Vector2i(874,402),Rect2i(62,0,750,381)],
		[Vector2i(320,568),Rect2i(0,20,320,548)]]:
		await display(item[0],item[1])
		var rect := button.get_global_rect()
		check(button.is_visible_in_tree())
		check(host.display_layout.logical_rect().grow(.1).encloses(rect),"city name stays inside safe bounds")
		check_ge(rect.size.y,44.0,"name has a full touch target")
		check_lt(rect.size.x,280.1,"long names stay compact")
		check(host.touch_ui_owned(rect.get_center()),"the name never starts a city gesture")
		for other: Control in host.menu_bar.phone_controls():
			if other.is_visible_in_tree(): check(not rect.intersects(other.get_global_rect()),"name avoids phone buttons")
		check(not rect.intersects(host.status_bar.get_global_rect()),"name avoids the footer")
	await display(Vector2i(1280,800),Rect2i(0,0,1280,800),false)
	check(button.is_visible_in_tree())
	check_lt(button.get_global_rect().end.x,1280.1)

func test_name_is_reachable_in_explore_and_blocked_by_other_modals() -> void:
	var button := name_button()
	if button == null: return
	await display(Vector2i(402,874),Rect2i(0,62,402,778))
	var city := host.sim.city
	for x in range(50,80): city.building.put(x,61,Buildings.ROAD_FIRST+NetworkShapes.SHAPE_EW)
	host.begin_city(city,{},123,null)
	host.exploration.set_touch_controls_enabled(true)
	check(host.enter_explore(),"flat city enters Explore")
	host.exploration.set_physics_process(false)
	await HostFixture.settle(self,8)
	check(button.is_visible_in_tree(),"Explore keeps the name accessible")
	check(not button.get_global_rect().intersects(host.explore_hud._status_panel.get_global_rect()),"name avoids Explore status")
	check_eq(host.explore_hud._usable_rect(),host.display_layout.logical_rect(),"name leaves the map and thumbs their full safe area")
	for action: StringName in [&"menu",&"move"]+host.explore_hud.touch_controls._mode_actions():
		check(not button.get_global_rect().intersects(host.explore_hud.touch_controls.control_rect(action)),"name avoids Explore touch actions")
	check(not button.get_global_rect().intersects(host.explore_hud.navigation._compact.get_global_rect()),"name avoids Map")
	button.pressed.emit()
	check(host.notice_dialog.is_open(),"name opens rename during Explore")
	check_eq(host.modal_depth,1)
	button.pressed.emit()
	check_eq(host.notices.pending(),0,"repeated taps cannot stack rename prompts")
	host.escape()
	check_eq(host.modal_depth,0)
	check_eq(host.sim.city.name,"Silver Springs")
	host.exploration.set_touch_controls_enabled(false)
	host.exploration.resume()
	await HostFixture.settle(self,8)
	check(not button.get_global_rect().intersects(host.explore_hud._status_panel.get_global_rect()),"a phone mouse keeps the name clear of status")
	host.exploration.pause()
	await display(Vector2i(874,402),Rect2i(62,0,750,381))
	check(host.display_layout.logical_rect().grow(.1).encloses(button.get_global_rect()),"rotating paused Explore keeps the name safe")
	check(not button.get_global_rect().intersects(host.menu_bar._phone_menu.get_global_rect()),"rotating paused Explore keeps Menu reachable")
	host.return_to_build()

func test_loaded_long_name_is_not_silently_shortened_by_the_prompt() -> void:
	var button := name_button()
	if button == null: return
	var long_name := "The Very Long City of Silver Springs"
	host.sim.city.name = long_name
	host.shell.refresh_city_name()
	host.files.mark_saved()
	check(not host.files.has_unsaved_changes())
	button.pressed.emit()
	check_eq(host.notice_dialog.line_edit.text,long_name)
	host.notice_dialog.dismiss(&"submit")
	check_eq(host.sim.city.name,long_name)
	check(not host.files.has_unsaved_changes(),"accepting an unchanged name is not an edit")
	button.pressed.emit()
	host.notice_dialog.line_edit.text = "Silver Springs"
	host.notice_dialog.dismiss(&"submit")
	check(host.files.has_unsaved_changes(),"renaming counts as unsaved work")
	host.notices.queue("Other Prompt","Text",[["OK",&"ok"]],Callable(),true,"Text")
	check_eq(host.notice_dialog.line_edit.max_length,Builder.SIGN_TEXT_MAX,"name editing restores other prompts' limit")
	host.notice_dialog.dismiss()
