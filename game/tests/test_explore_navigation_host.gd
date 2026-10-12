# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const MAIN := preload("res://scenes/main.tscn")
var host: GameHost

func before_each() -> void:
	host = MAIN.instantiate()
	host.preferences_path = "user://navigation-host.cfg"
	root.add_child(host)

func after_each() -> void:
	host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://navigation-host.cfg"))
	await process_frame

func enter() -> bool:
	var city := flat_city()
	for x in range(18,34): city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	host.begin_city(city,{},173,null)
	host.sim.set_process(false)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.city_view_3d.set_camera_state(Vector3(22.5,4*CityGeometry3D.HEIGHT,20.5),1,12)
	await physics_frame
	var entered := host.enter_explore()
	check(entered)
	host.exploration.set_physics_process(false)
	return entered

func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

func pack(owner: String, at: int, faults: bool = false) -> Dictionary:
	var source := "return {on_start=function(api) api.marker.set('place',{target={x="+str(at)+",y=1,z=20},label='Native target'}); api.timer.after('clock',300) end"
	if faults: source += ",on_tick=function(api) api.marker.set('bad',{target={x=25,y=1,z=20}}); error('fixture fault') end"
	source += "}"
	return ExploreModPack._snapshot({"manifest.json":JSON.stringify({"id":owner,"name":owner,"version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"}).to_utf8_buffer(),"main.lua":source.to_utf8_buffer()})

func test_main_shortcut_freezes_explore_and_restores_previous_pause() -> void:
	if not await enter(): return
	var session := host.exploration
	var before := SaveFormat.encode_city(host.sim.city)
	var camera := host.city_view_3d.center
	var position := session.occupied.global_position
	var service := ExploreModService.new()
	session.mod_service = service
	service.bind(session,[pack("navigation.fixture",23)],session.mod_progress)
	service.enter()
	for i in 4: service.step(.1,false)
	check_eq(service.api.markers.count(),1,"actual Lua registers a map pin")
	var clock: float = service.api._timers["navigation.fixture"].clock.left
	host._input(key(KEY_M))
	check(session.is_suspended() and host.explore_hud.navigation.expanded)
	check(not host.explore_hud._panel.visible,"map replaces pause panel")
	check(not host.explore_hud._status_panel.visible,"expanded map has clear canvas")
	var repeated := key(KEY_M)
	repeated.echo = true
	host._input(repeated)
	check(host.explore_hud.navigation.expanded,"key repeat cannot toggle")
	host.explore_hud.navigation._large_map.pan_pixels(Vector2(40,10))
	host.explore_hud.navigation._large_map.set_span(16)
	for i in 10: session._physics_process(.1)
	check_eq(session.occupied.global_position,position)
	check_eq(service.api._timers["navigation.fixture"].clock.left,clock,"map browsing freezes Lua game clock")
	host._input(key(KEY_ESCAPE))
	check(not host.explore_hud.navigation.expanded and not session.is_suspended(),"one Escape closes and resumes")
	session.pause()
	host._input(key(KEY_M))
	host._input(key(KEY_M))
	check(session.is_suspended() and host.explore_hud._panel.visible,"manual pause survives browsing")
	check_eq(host.city_view_3d.center,camera,"browsing never moves Build camera")
	check_eq(SaveFormat.encode_city(host.sim.city),before,"navigation preserves city bytes")
	host.return_to_build()
	check(not host.explore_hud.navigation.visible and not host.explore_hud.navigation.expanded)
	check_eq(service.api.markers.count(),0,"leave clears static markers too")

func test_live_actor_markers_follow_owned_poses_expire_and_refuse_other_owners() -> void:
	if not await enter(): return
	var session := host.exploration
	var service := ExploreModService.new()
	session.mod_service = service
	service.bind(session,[],session.mod_progress)
	service.enter()
	var send := func(owner: String, kind: String, args: Dictionary) -> Dictionary:
		return service.api.apply({"owner":owner,"generation":service.generation,"request_id":1,"kind":kind,"args":args})
	var spawn: Dictionary = send.call("one","actor.spawn",{"kind":"pedestrian","options":{"key":"target","near_player":true}})
	check_eq(spawn.code,"ok")
	if spawn.code != "ok": return
	check_eq(send.call("two","marker.set",{"key":"target","options":{"target":{"id":spawn.data.id}}}).code,"wrong_owner")
	check_eq(send.call("one","marker.set",{"key":"target","options":{"target":{"id":"old"}}}).code,"stale_id")
	check_eq(send.call("one","marker.set",{"key":"target","options":{"target":{"id":spawn.data.id},"label":"Moving person"}}).code,"ok")
	var marker := session.navigation_markers()[0]
	var actor: Dictionary = service.actors._actors[spawn.data.id]
	actor.record.t = .8
	var moved := session.navigation_markers()[0]
	check(moved.position != marker.position,"live marker follows actual traffic pose")
	check_eq(moved.position,service.actors.traffic.actor_pose(actor.record).origin)
	check(moved.anchor.y > moved.position.y,"world badge anchors above model")
	for i in 15:
		check_eq(send.call("one","marker.set",{"key":"extra"+str(i),"options":{"target":{"id":spawn.data.id}}}).code,"ok")
	check_eq(send.call("one","actor.remove",{"id":spawn.data.id}).code,"ok")
	check_eq(send.call("one","marker.set",{"key":"place","options":{"target":{"x":22,"y":1,"z":20}}}).code,"ok","expired actor pins release quota even before render or metrics")
	check_eq(send.call("one","marker.remove",{"key":"place"}).code,"ok")
	check(session.navigation_markers().is_empty(),"deleted actor cannot leave ghost marker")
	check_eq(service.api.markers.count(),0)
	check_eq(send.call("one","marker.set",{"key":"place","options":{"target":{"x":22,"y":1,"z":20}}}).code,"ok")
	service.disable("one")
	# Host-owned fixtures have no VM, so explicit host owner cleanup remains valid.
	service.api.clear_owner("one")
	check_eq(service.api.markers.count(),0)
	service.leave("test")

func test_native_markers_disable_fault_reload_and_city_replacement_cleanup() -> void:
	if not await enter(): return
	var session := host.exploration
	var first := pack("first",23)
	var second := pack("second",24)
	var service := ExploreModService.new()
	session.mod_service = service
	service.bind(session,[first,second],session.mod_progress)
	service.enter()
	for i in 4: service.step(.1,false)
	check_eq(service.api.markers.count(),2)
	service.disable("first")
	check_eq(service.api.markers.count(),1,"disable removes only its own pins")
	check(service.api.markers._owned.has("second"))
	session.pause()
	service.configure_packs([pack("first",25),second])
	session.resume()
	for i in 4: service.step(.1,false)
	check_eq(service.api.markers.count(),2,"reload creates new target beside surviving owner")
	check_eq(service.api.markers._owned.first.place.target.x,25)
	session.pause()
	service.configure_packs([pack("first",26,true),second])
	session.resume()
	for i in 4: service.step(.1,false)
	check_eq(service.api.markers.count(),1,"fault discards callback output and all failed owner pins")
	check(service.api.markers._owned.has("second"))
	host.begin_city(flat_city(),{},174,null)
	check_eq(service.api.markers.count(),0,"replacing city removes markers and sessions")

func test_touch_navigation_keeps_menu_and_vehicle_actions_accessible() -> void:
	if not await enter(): return
	host.exploration.set_touch_controls_enabled(true)
	for drawable: Vector2i in [Vector2i(1280,800),Vector2i(390,844),Vector2i(844,390)]:
		host.display_layout.refresh_with_mobile_metrics(drawable,1,Rect2i(Vector2i.ZERO,drawable))
		for mode in [0,1,2]:
			host.explore_hud.set_status({"mode":mode})
			await process_frame
			await process_frame
			var navigation := host.explore_hud.navigation
			var touch := host.explore_hud.touch_controls
			var actions: Array[StringName] = touch._mode_actions()
			actions.append(&"menu")
			for action: StringName in actions:
				check(not navigation._compact.get_global_rect().intersects(touch.control_rect(action)),"Map cannot cover %s at %s" % [action,drawable])
			var center := navigation._open_button.get_global_rect().get_center()
			check(host.touch_ui_owned(center),"Map card owns touch, never camera look")
			check(host.explore_hud._usable_rect().encloses(navigation._compact.get_global_rect()),"touch map fits above footer")
			navigation.map_visible = false
			navigation._refresh_visibility()
			check(navigation._open_button.is_visible_in_tree(),"expanded Map stays accessible when minimap hidden")

func test_world_markers_align_at_retina_ui_and_render_scales() -> void:
	if not await enter(): return
	var view := host.city_view_3d
	var navigation := host.explore_hud.navigation
	var camera := host.exploration.camera_rig.camera
	for backing: float in [1.0,2.0]:
		for ui_scale: int in [100,125]:
			host.display_layout.ui_scale = ui_scale
			host.display_layout.refresh_with_metrics(Vector2i(2560,1600),backing)
			for render_scale: int in [100,75,50]:
				view.set_render_options("balanced",render_scale)
				await process_frame
				var pixel := Vector2(view.viewport.size)*Vector2(.6,.4)
				var anchor := camera.project_position(pixel,1.0)
				var expected := view.container.position+view.container.size*Vector2(.6,.4)
				check(navigation.world_point(anchor).distance_to(expected) < .01,"marker stays at its rendered object across backing/UI/render scales")

func test_map_shortcut_respects_editing_focus_and_owns_map_buttons() -> void:
	if not await enter(): return
	var field := LineEdit.new()
	host.add_child(field)
	field.grab_focus()
	host._input(key(KEY_M))
	check(not host.explore_hud.navigation.expanded,"focused text keeps its map key")
	field.free()
	host._input(key(KEY_M))
	check(host.explore_hud.navigation.expanded)
	host.explore_hud.navigation._open_button.grab_focus()
	host._input(key(KEY_M))
	check(not host.explore_hud.navigation.expanded,"map key still closes with its own button focus")
