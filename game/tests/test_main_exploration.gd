# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const PREFS := "user://test_main_exploration.cfg"
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

func _play() -> void:
	var city := flat_city()
	city.building.put(10,10,30)
	host.begin_city(city,{},4242,CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.city_view_3d.set_camera_state(Vector3(10.5,4*CityGeometry3D.HEIGHT,10.5),1,12.0)
	await physics_frame

func test_entry_is_atomic_outside_play() -> void:
	check(not host.enter_explore())
	check(host.title_screen.visible)
	check(host.city_view_3d.aerial_controls_enabled)
	check(not host.get("exploration").is_active())

func test_entry_without_cached_support_preserves_builder_owner() -> void:
	await _play()
	host.select_tool(Tools.Kind.ROAD)
	host.city_view_3d._traversal_chunks.clear()
	var state := host.presentation.capture_state()
	var center := host.city_view_3d.center
	check(not host.enter_explore())
	check_eq(host.tool,Tools.Kind.ROAD)
	check_eq(host.presentation.capture_state(),state)
	check_eq(host.city_view_3d.center,center)
	check(host.toolbar.visible and host.city_view_3d.camera.current)
	check(not host.exploration.is_active())
	check(host.city_view_3d.camera.environment == null, "failed entry leaves the aerial environment")

func test_explore_sky_follows_session_and_preserves_aerial_lighting() -> void:
	await _play()
	var view := host.city_view_3d
	var aerial: Environment
	for child: Node in view.world.get_children():
		if child is WorldEnvironment: aerial = child.environment
	var original_background := aerial.background_color
	var original_city := SaveFormat.encode_city(host.sim.city)
	var original_sim := host.sim.snapshot().duplicate(true)
	var sky: Sky
	for visit: int in 2:
		check(host.enter_explore(), "Main enters Explore")
		if not host.exploration.is_active(): return
		var camera: Camera3D = host.exploration.camera_rig.camera
		var environment: Environment = camera.environment
		check(environment != null, "Explore camera presents a sky environment")
		if environment == null:
			host.return_to_build()
			continue
		check_ne(environment, aerial, "Explore does not modify the shared aerial environment")
		check_eq(environment.background_mode, Environment.BG_SKY)
		check(environment.sky != null and environment.sky.sky_material != null, "a complete sky is attached")
		check_eq(environment.ambient_light_source, aerial.ambient_light_source)
		check_eq(environment.ambient_light_color, aerial.ambient_light_color)
		check_eq(environment.ambient_light_energy, aerial.ambient_light_energy)
		check_eq(environment.ambient_light_sky_contribution, 0.0, "sky adds no ambient relighting")
		check_eq(environment.reflected_light_source, Environment.REFLECTION_SOURCE_DISABLED, "sky adds no indirect relighting")
		if visit == 0: sky = environment.sky
		else: check_eq(environment.sky, sky, "reentry reuses the sky resource")
		for quality: String in ["performance", "balanced", "high"]:
			# A quality change must update the active camera override as well as
			# the aerial environment, even if its inherited energy was different.
			environment.ambient_light_energy = 0.11
			view.set_render_options(quality, 75)
			check_eq(environment.ambient_light_energy, aerial.ambient_light_energy)
			check_eq(environment.background_mode, Environment.BG_SKY)
		host.exploration.suspend()
		check_eq(camera.environment, environment, "controls/focus suspension keeps the sky")
		check_eq(aerial.background_mode, Environment.BG_COLOR)
		check_eq(aerial.background_color, original_background)
		host.return_to_build()
		check(view.camera.current and view.camera.environment == null)
		check_eq(aerial.background_mode, Environment.BG_COLOR)
		check_eq(aerial.background_color, original_background)
	check_eq(SaveFormat.encode_city(host.sim.city), original_city)
	check_eq(host.sim.snapshot(), original_sim, "sky consumes no simulation state or random draws")

func test_display_settings_initialize_controls() -> void:
	host.set_option(&"explore_sensitivity",1.75)
	host.set_option(&"explore_invert_y",true)
	var options := host.open_window("options") as OptionsWindow
	check(options.invert_check.button_pressed,"saved inversion is visible in Settings")
	check_eq(options.sensitivity_slider.value,1.75)
	check_eq(host.explore_hud.invert_y,true,"active camera consumes Settings inversion")
	check_eq(host.explore_hud.sensitivity,1.75)

func test_menu_announces_explore_popup_before_action() -> void:
	await _play()
	check(host.menu_bar.has_action(&"explore"),"View offers Explore")
	check(host.menu_bar.has_signal("popup_opened"),"popup suspends before menu actions")
	if not host.menu_bar.has_signal("popup_opened"): return
	var order: Array[String] = []
	host.menu_bar.connect("popup_opened",func() -> void: order.append("popup"))
	host.menu_bar.action_requested.connect(func(action: StringName,_value: Variant) -> void:
		if action == &"explore": order.append("explore"))
	host.menu_bar._menus["View"].about_to_popup.emit()
	host.menu_bar.press(&"explore")
	check_eq(order,["popup","explore"] as Array[String])
	while host.loading_screen.visible: await process_frame

func test_return_preserves_paused_city_and_complete_builder_state() -> void:
	await _play()
	host.presentation.set_overlay(&"crime")
	host.select_tool(Tools.Kind.WATER_PIPE)
	var city_before := SaveFormat.encode_city(host.sim.city).duplicate(true)
	var sim_before := host.sim.snapshot().duplicate(true)
	var presentation_before := host.presentation.capture_state()
	var center := host.city_view_3d.center
	var angle := host.city_view_3d.quarter_turn
	var size := host.city_view_3d.camera_size
	check(bool(host.enter_explore()))
	check(not host.toolbar.visible and not host.city_view_3d.aerial_controls_enabled)
	check_eq(host.sim.speed,GameClock.Speed.PAUSED)
	check_eq(host.city_view_3d._overlay_kind,&"")
	check(not host.city_view_3d._underground)
	host.return_to_build()
	check_eq(SaveFormat.encode_city(host.sim.city),city_before)
	check_eq(host.sim.snapshot(),sim_before)
	check_eq(host.presentation.capture_state(),presentation_before)
	check_eq(host.tool,Tools.Kind.WATER_PIPE)
	check_eq(host.city_view_3d.center,center)
	check_eq(host.city_view_3d.quarter_turn,angle)
	check_eq(host.city_view_3d.camera_size,size)
	check(host.toolbar.visible and host.city_view_3d.aerial_controls_enabled)

func test_explore_rejects_builder_paths_and_temporary_b_release() -> void:
	await _play()
	host.select_tool(Tools.Kind.ROAD)
	host._unhandled_key_input(_key(KEY_B,true))
	check_eq(host.tool,Tools.Kind.BULLDOZE)
	check(bool(host.enter_explore()))
	var encoded := SaveFormat.encode_city(host.sim.city).duplicate(true)
	check(not bool(host.handle_drag(Vector2i(10,10),Vector2i(11,10)).ok))
	check(host.construction.preview_drag(Vector2i(10,10),Vector2i(11,10)).is_empty())
	host.select_tool(Tools.Kind.QUERY)
	host.presentation.set_overlay(&"water")
	for key in [KEY_B,KEY_Q,KEY_U,KEY_R,KEY_1]:
		host._unhandled_key_input(_key(key,true))
		host._unhandled_key_input(_key(key,false))
	host._on_menu_action(&"rotate",null)
	host._on_menu_action(&"zoom",4)
	check_eq(SaveFormat.encode_city(host.sim.city),encoded)
	check_eq(host.city_view_3d._overlay_kind,&"")
	host.return_to_build()
	host._unhandled_key_input(_key(KEY_B,false))
	check_eq(host.tool,Tools.Kind.ROAD,"held temporary bulldoze normalizes before entry")

func test_modal_is_explicitly_resumable_and_escape_keeps_fullscreen() -> void:
	await _play()
	check(bool(host.enter_explore()))
	var session: Node = host.get("exploration")
	host.push_modal()
	check(session.is_suspended())
	host.pop_modal()
	check(session.is_suspended(),"closing modal never automatically resumes movement")
	session.resume()
	check(not session.is_suspended())
	host.escape()
	check(session.is_suspended(),"Escape opens exploration controls")
	check(session.is_active())
	host.menu_bar.popup_opened.emit()
	check(session.is_suspended())

func test_save_failure_and_replacement_lifecycle() -> void:
	await _play()
	check(bool(host.enter_explore()))
	var session: Node = host.get("exploration")
	var path := "user://test_explore_save.scity"
	var encoded := SaveFormat.encode_city(host.sim.city).duplicate(true)
	check_eq(host.files.write_save(path),OK)
	check_eq(host.autosave(),OK)
	check(session.is_active(),"saving keeps the occupied session")
	check_eq(SaveFormat.encode_city(host.sim.city),encoded)
	check(not host.load_city("user://explore_missing.scity"))
	await physics_frame
	check(session.is_active() and session.is_suspended(),"failed load keeps a resumable current city")
	if host.notice_dialog.is_open(): host.notice_dialog.dismiss()
	host.begin_city(flat_city(),{},4243,CityStats.new())
	check(not session.is_active())
	check(host.city_view_3d.aerial_controls_enabled and host.toolbar.visible)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CityFileFlow.autosave_path()))

func test_focus_loss_holds_input_and_resize_keeps_flight_camera() -> void:
	await _play()
	check(host.enter_explore())
	var session: CityExplorationController = host.exploration
	var aircraft: CharacterBody3D = session.helicopter
	session.pedestrian.global_position = aircraft.global_position+Vector3(.30,0,0)
	check(session.request_interaction())
	check_eq(session.mode,ExploreActorProfile.Mode.FLY)
	session.handle_event(_key(KEY_Q,true))
	for tick in 20: await physics_frame
	session.handle_event(_key(KEY_Q,false))
	session.set_physics_process(false)
	var pose := aircraft.global_transform
	var camera := session.camera_rig.camera
	host.display_layout.refresh_with_metrics(Vector2i(2560,1600),2.0)
	host.display_layout.set_fullscreen(true)
	host.display_layout.refresh_with_metrics(Vector2i(3840,2160),2.0)
	await process_frame
	check_eq(session.camera_rig.camera,camera)
	check(camera.current and not host.city_view_3d.camera.current)
	check_eq(aircraft.global_transform,pose,"resizing never writes an actor transform")
	get_root().focus_exited.emit()
	session.set_physics_process(true)
	check(session.is_suspended())
	check_eq(Input.mouse_mode,Input.MOUSE_MODE_VISIBLE)
	Input.parse_input_event(_key(KEY_W,true))
	for frame in 4: await process_frame
	check(Input.is_physical_key_pressed(KEY_W))
	session.resume()
	pose = aircraft.global_transform
	for tick in 10: await physics_frame
	check_eq(aircraft.global_transform,pose,"held input after focus loss waits for release")
	Input.parse_input_event(_key(KEY_W,false))
	for frame in 4: await process_frame
	host.display_layout.set_fullscreen(false)
	host.return_to_build()
	check(host.city_view_3d.camera.current)

func test_explore_actor_clears_measured_main_chrome_after_status_wrap_and_resize() -> void:
	await _play()
	# A compact logical canvas makes the real Main footer wrap. Its height is
	# measured from the Control after layout, not inferred from BAR_HEIGHT.
	host.display_layout.refresh_with_metrics(Vector2i(1280,800),2.0)
	host.status_bar.set_tool_text("Underground water and subway connection through the eastern district")
	host.status_bar.set_funds(987654321)
	host.status_bar.set_date("December 31, 2099")
	host.status_bar.set_population(12345678)
	host.status_bar.set_alerts(PackedStringArray(["Power shortage", "Water shortage", "Emergency", "Bankrupt"]))
	host.status_bar.set_message("Underground connection requires a clear, level approach beside the station.")
	for frame in 4: await process_frame
	check(host.enter_explore(),"real Main opens an Explore session")
	if not host.exploration.is_active(): return
	var session: CityExplorationController = host.exploration
	session.suspend()
	var rig := session.camera_rig
	var probe := Node3D.new()
	host.city_view_3d.world.add_child(probe)
	probe.global_position = session.occupied.global_position + Vector3.UP * .25
	for layout in [{"drawable":Vector2i(1280,800),"backing":2.0},
		{"drawable":Vector2i(1600,900),"backing":1.0}]:
		host.display_layout.refresh_with_metrics(layout.drawable,layout.backing)
		for frame in 4: await process_frame
		var drawable: Vector2i = host.display_layout.drawable_size()
		var scale := float(host.display_layout.metrics["scale"])
		var top := host.menu_bar.size.y * scale
		var bottom := float(drawable.y) - host.status_bar.size.y * scale
		check(bottom > top + 100.0,"measured Main chrome leaves an actor view")
		for mode in [ExploreActorProfile.Mode.WALK,ExploreActorProfile.Mode.DRIVE,ExploreActorProfile.Mode.FLY]:
			rig.configure_target(probe,mode)
			for frame in 12:
				rig.update_follow(.1)
				await process_frame
			var size: Vector3 = ExploreActorProfile.geometry(mode).size
			for x_sign in [-1.0,1.0]:
				for y_sign in [0.0,1.0]:
					for z_sign in [-1.0,1.0]:
						var point := probe.global_position + Vector3(size.x*.5*x_sign,size.y*y_sign,size.z*.5*z_sign)
						var pixel := rig.camera.unproject_position(point)
						check(pixel.is_finite(),"mode %d corner projects finitely" % mode)
						check(pixel.y >= top + 4.0 and pixel.y <= bottom - 4.0,
							"mode %d actor corner y %.1f clears measured Main %.1f..%.1f" % [mode,pixel.y,top,bottom])
	probe.free()

func test_critical_hud_clears_actual_main_city_footer_without_scrolling() -> void:
	await _play()
	host.display_layout.refresh_with_metrics(Vector2i(1280,800),2.0)
	host.status_bar.set_tool_text("Water Pipe")
	host.status_bar.set_funds(19860683)
	host.status_bar.set_date("December 2339")
	host.status_bar.set_population(0)
	host.status_bar.set_alerts(PackedStringArray(["Water shortage"]))
	host.status_bar.set_message("Underground · pipes and subway")
	for frame in 4: await process_frame
	check(host.enter_explore(),"Main city enters Explore")
	if not host.exploration.is_active(): return
	host.exploration.set_physics_process(false)
	for frame in 4: await process_frame
	var usable := Rect2(0,host.menu_bar.size.y,host.display_layout.logical_rect().size.x,
		host.display_layout.logical_rect().size.y-host.menu_bar.size.y-host.status_bar.size.y)
	print("MAIN_HUD menu=",host.menu_bar.get_rect()," footer=",host.status_bar.get_rect()," usable=",usable)
	check_lt(host.status_bar.size.y,171.0,"compact footer shrinks after duplicate speed row removal")
	check_eq(host.status_bar.find_children("*","Button",true,false), [host.status_bar.emergency_button], "Explore footer keeps emergency navigation without duplicate speed controls")
	var hud := host.explore_hud
	var status_panel := hud.get_node("ExploreStatus") as PanelContainer
	for suspended in [false,true]:
		hud.set_suspended(suspended)
		for mode in [ExploreActorProfile.Mode.WALK,ExploreActorProfile.Mode.DRIVE,ExploreActorProfile.Mode.FLY]:
			hud.set_status({"mode":mode,"speed":2.5,"altitude":.375,
				"prompt":"F to exit helicopter" if mode == ExploreActorProfile.Mode.FLY else "F to enter nearby vehicle",
				"message":"Land before exiting. ".repeat(15)})
			for frame in 4: await process_frame
			check(usable.encloses(status_panel.get_rect()),"critical HUD stays inside measured Main city region")
			for label: Label in [hud._actor_label,hud._speed_label,hud._altitude_label,hud._prompt_label]:
				if not label.visible: continue
				var rect := label.get_global_rect()
				var parent := label.get_parent()
				var visible_rect := status_panel.get_global_rect()
				while parent != status_panel and parent != null:
					if parent is ScrollContainer:
						visible_rect = visible_rect.intersection((parent as ScrollContainer).get_global_rect())
					parent = parent.get_parent()
				check(visible_rect.encloses(rect),"mode %d suspended %s critical '%s' visible without scrolling: %s inside %s" % [mode,suspended,label.text,rect,visible_rect])
			if suspended:
				var controls := hud.get_node("ExplorePanel") as PanelContainer
				check(usable.encloses(controls.get_rect()),"suspended controls stay inside measured city region")
				check(not status_panel.get_rect().intersects(controls.get_rect()),"critical HUD never overlaps suspended controls")
				var controls_scroll := hud.get_node("ExplorePanel/ExploreControlsScroll") as ScrollContainer
				var resume := controls_scroll.get_child(0).get_child(1) as Button
				check_ge(resume.size.y,44.0,"Resume keeps its readable touch target")
				check(controls_scroll.get_global_rect().encloses(resume.get_global_rect()),"Resume is initially visible inside suspended controls")

func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event

func test_q_e_f_route_through_main_without_builder_or_focus_leak() -> void:
	await _play()
	host.select_tool(Tools.Kind.ROAD)
	check(host.enter_explore())
	var session: CityExplorationController = host.exploration
	await physics_frame
	await physics_frame
	session.set_physics_process(false)
	for code: Key in [KEY_Q,KEY_E,KEY_F]:
		host._unhandled_key_input(_key(code,true))
		check(bool(session._held.get(code,false)),"Main captures physical Explore key %s" % code)
		var frame := ExploreInputFrame.from_keys(session._held,session._edges)
		check_eq(frame.vertical,1.0 if code == KEY_Q else (-1.0 if code == KEY_E else 0.0))
		check_eq(frame.interact,code == KEY_F,"only F press has interaction edge")
		session._edges.clear()
		var repeat := _key(code,true)
		repeat.echo = true
		host._unhandled_key_input(repeat)
		check(session._edges.is_empty(),"OS repeat does not create another edge")
		host._unhandled_key_input(_key(code,false))
		check(not bool(session._held.get(code,false)),"key release clears held control")
	check_eq(host.tool,Tools.Kind.ROAD,"Explore Q never selects builder Query")
	var field := LineEdit.new()
	host.ui_layer.add_child(field)
	field.grab_focus()
	check(host.is_camera_input_blocked(),"focused text owns keyboard")
	for code: Key in [KEY_Q,KEY_E,KEY_F]: host._unhandled_key_input(_key(code,true))
	check(session.is_suspended(),"focused text suspends before capturing shortcuts")
	check(session._held.is_empty() and session._edges.is_empty(),"text input cannot queue movement or entry")
	field.free()
	session.resume()
	check(session._arming,"explicit Resume requires fresh released keys")
	host.push_modal()
	for code: Key in [KEY_Q,KEY_E,KEY_F]: host._unhandled_key_input(_key(code,true))
	check(session._held.is_empty() and session._edges.is_empty(),"modal input cannot queue controls")
	host.pop_modal()
	check(session.is_suspended(),"closing modal does not resume")
	host.return_to_build()
	host._unhandled_key_input(_key(KEY_Q,true))
	check_eq(host.tool,Tools.Kind.QUERY,"builder Q remains Query outside Explore")

func test_f_edge_enters_and_exits_car_while_e_is_not_interaction() -> void:
	await _play()
	check(host.enter_explore())
	var session: CityExplorationController = host.exploration
	for tick in 3: await physics_frame
	host._unhandled_key_input(_key(KEY_E,true))
	for tick in 2: await physics_frame
	check_eq(session.mode,ExploreActorProfile.Mode.WALK,"E descent does not enter nearby car")
	host._unhandled_key_input(_key(KEY_E,false))
	host._unhandled_key_input(_key(KEY_F,true))
	for tick in 3: await physics_frame
	check_eq(session.mode,ExploreActorProfile.Mode.DRIVE,"F edge enters parked car through Main")
	for tick in 4: await physics_frame
	check_eq(session.mode,ExploreActorProfile.Mode.DRIVE,"held F does not immediately exit")
	host._unhandled_key_input(_key(KEY_F,false))
	await physics_frame
	host._unhandled_key_input(_key(KEY_F,true))
	for tick in 3: await physics_frame
	check_eq(session.mode,ExploreActorProfile.Mode.WALK,"fresh F edge exits supported stopped car")
	host._unhandled_key_input(_key(KEY_F,false))
