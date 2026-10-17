# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost
func before_each() -> void:
	host = Fixture.make_host(self,"ios-camera-menu")
func after_each() -> void:
	host.free()
	await process_frame
func phone(dimensions: Vector2i, safe: Rect2i, backing: float = 1.0) -> void:
	root.size = dimensions
	host.display_layout.refresh_with_mobile_metrics(dimensions,backing,safe,0,"iOS")
	await Fixture.settle(self,8)
func test_portrait_actions_use_camera_wings_and_recover_the_menu_row() -> void:
	for profile: Array in [[Vector2i(375,812),Rect2i(0,44,375,734)],[Vector2i(390,844),Rect2i(0,47,390,763)],[Vector2i(393,852),Rect2i(0,59,393,759)],[Vector2i(1170,2532),Rect2i(0,141,1170,2289),3.0]]:
		await phone(profile[0],profile[1],profile[2] if profile.size()>2 else 1.0)
		var bar := host.menu_bar.get_global_rect()
		var safe := host.display_layout.logical_rect()
		var full: Rect2 = host.display_layout.metrics.full_logical_rect
		check_eq(bar.position.y,0.0,"menu face starts at the display edge")
		check(bar.end.y<=maxf(60.0,safe.position.y),"no second menu row below the camera")
		check_eq(bar.size.y,60.0,"notch and Island share the same portrait bar height")
		var camera := Rect2((full.size.x-220.0)*.5,0,220,safe.position.y)
		for button: Button in [host.menu_bar.phone_tools_button,host.menu_bar.get("_phone_menu")]:
			var rect := button.get_global_rect()
			check(rect.position.y<safe.position.y,"actions use the camera wings")
			check(not rect.intersects(camera),"camera has a clear center exclusion")
			check_ge(rect.size.x,44.0)
			check_ge(rect.size.y,44.0)
			check_eq(rect.position.y-bar.position.y,8.0,"consistent space above the target")
			check_eq(bar.end.y-rect.end.y,8.0,"matching space below the target")
			check(full.grow(.1).encloses(rect),"target remains on the display")
			check(host.touch_ui_owned(rect.get_center()),"wing contact belongs to UI")
		check(not host.menu_bar.phone_inspect_button.visible,"third action moves into Menu")
		host.shell.set_phone_tools_open(true)
		await Fixture.settle(self,6)
		check(host.toolbar.position.y>=bar.end.y,"drawer clears the bar")
		check(host.toolbar.position.y<safe.position.y+44,"drawer benefits from recovered space")
		host.shell.set_phone_tools_open(false)
func test_landscape_face_reaches_edges_but_actions_avoid_side_camera() -> void:
	for safe in [Rect2i(47,0,750,369),Rect2i(0,0,797,369)]:
		await phone(Vector2i(844,390),safe)
		check_eq(host.menu_bar.position,Vector2.ZERO,"landscape face fills the camera-side margin")
		check_eq(host.menu_bar.size,Vector2(844,44))
		for button: Button in [host.menu_bar.phone_tools_button,host.menu_bar.phone_inspect_button,host.menu_bar.get("_phone_menu")]:
			check(host.display_layout.logical_rect().grow(.1).encloses(button.get_global_rect()),"side camera leaves actions unobscured")

func tap(at: Vector2) -> void:
	for pressed: bool in [true,false]:
		var mouse := InputEventMouseButton.new()
		mouse.position = at
		mouse.global_position = at
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.pressed = pressed
		mouse.device = InputEvent.DEVICE_ID_EMULATION
		root.push_input(mouse,true)
		var finger := InputEventScreenTouch.new()
		finger.position = at
		finger.pressed = pressed
		root.push_input(finger,true)

func test_wing_tools_receive_taps_and_menu_inspect_respects_stage() -> void:
	await phone(Vector2i(390,844),Rect2i(0,47,390,763))
	var original := SaveFormat.encode_city(host.sim.city)
	tap(host.menu_bar.phone_tools_button.get_global_rect().get_center())
	await Fixture.settle(self,6)
	check(host.toolbar.is_visible_in_tree(),"camera-wing tap opens Tools exactly once")
	tap(host.menu_bar.phone_tools_button.get_global_rect().get_center())
	await Fixture.settle(self,6)
	check(not host.toolbar.visible,"same target closes Tools")
	var popup: PopupMenu = host.menu_bar.get("_phone_menu").get_popup()
	var index := popup.get_item_index(GameMenuBar.PHONE_INSPECT_ID)
	check_ge(index,0,"Menu retains Inspect")
	if index<0: return
	check(not popup.is_item_disabled(index))
	popup.id_pressed.emit(GameMenuBar.PHONE_INSPECT_ID)
	check_eq(host.tool,Tools.Kind.QUERY,"Menu Inspect selects the original query tool")
	check_eq(SaveFormat.encode_city(host.sim.city),original,"menu taps cannot construct on the map")
	host.session.begin_editing(flat_city(),{})
	await Fixture.settle(self,6)
	check(popup.is_item_disabled(index),"Inspect stays unavailable during terrain editing")
	popup.id_pressed.emit(GameMenuBar.PHONE_INSPECT_ID)
	check(host.tool!=Tools.Kind.QUERY,"disabled Menu Inspect cannot bypass stage gating")

func test_rotation_scale_and_ipad_restore_original_actions() -> void:
	await phone(Vector2i(390,844),Rect2i(0,47,390,763))
	host.display_layout.set_ui_scale(200)
	await Fixture.settle(self,8)
	var full: Rect2 = host.display_layout.metrics.full_logical_rect
	for button: Button in [host.menu_bar.phone_tools_button,host.menu_bar.get("_phone_menu")]:
		check(full.grow(.1).encloses(button.get_global_rect()),"requested large UI keeps targets on screen")
		check_ge(button.size.y*float(host.display_layout.metrics.effective_percent)/100.0,44.0)
	host.display_layout.set_ui_scale(100)
	await phone(Vector2i(320,700),Rect2i(0,47,320,619))
	for button: Button in [host.menu_bar.phone_tools_button,host.menu_bar.phone_inspect_button,host.menu_bar.get("_phone_menu")]:
		check(host.display_layout.logical_rect().grow(.1).encloses(button.get_global_rect()),"insufficient wing room falls back to safe row")
	await phone(Vector2i(844,390),Rect2i(47,0,750,369))
	check(host.menu_bar.phone_inspect_button.visible,"landscape restores direct Inspect")
	check_eq(host.menu_bar.get("_phone_menu").get_popup().get_item_index(GameMenuBar.PHONE_INSPECT_ID),-1,"no duplicate Inspect in landscape")
	await phone(Vector2i(1194,834),Rect2i(0,24,1194,790))
	check_eq(host.menu_bar.position,host.display_layout.logical_rect().position,"iPad keeps safe-area menu geometry")
	check_ge(host.menu_bar.get_menu_count(),6,"iPad restores the original menus")
	await phone(Vector2i(320,568),Rect2i(0,20,320,548))
	check(host.display_layout.logical_rect().grow(.1).encloses(host.menu_bar.phone_inspect_button.get_global_rect()),"small non-notched phone keeps direct Inspect")

func test_ios_explore_pause_and_inspector_use_the_recovered_inset() -> void:
	var city := flat_city()
	for x in range(50,80): city.building.put(x,61,Buildings.ROAD_FIRST+NetworkShapes.SHAPE_EW)
	host.begin_city(city,{},123,null)
	await phone(Vector2i(390,844),Rect2i(0,47,390,763))
	host.open_query(Vector2i(64,64))
	await Fixture.settle(self,6)
	check(host.query_panel.position.y>=host.menu_bar.get_global_rect().end.y,"inspector clears wing row")
	check(host.query_panel.position.y<47+44,"inspector benefits from reclaimed height")
	host.query_panel.close()
	host.city_view_3d.set_camera_state(Vector3(64,2.4,61),0,48)
	host.exploration.set_touch_controls_enabled(true)
	check(host.enter_explore())
	host.exploration.set_physics_process(false)
	await Fixture.settle(self,8)
	check(not host.menu_bar.visible,"active Explore remains immersive")
	check_eq(host.explore_hud._usable_rect(),host.display_layout.logical_rect())
	host.exploration.suspend()
	await Fixture.settle(self,8)
	check(host.menu_bar.visible,"pause restores menu wings")
	check_eq(host.menu_bar.position.y,0.0)
	check_eq(host.explore_hud._usable_rect().position.y,host.menu_bar.get_global_rect().end.y,"pause reserves the actual bar end once")

func test_street_names_panel_uses_actual_chrome_end() -> void:
	await phone(Vector2i(390,844),Rect2i(0,47,390,763))
	check(host.street_names.enter())
	await Fixture.settle(self,6)
	var safe := host.display_layout.logical_rect()
	var height := safe.end.y-host.status_bar.size.y-maxf(safe.position.y,host.menu_bar.get_global_rect().end.y)
	check(absf(host.street_names.panel.size.y-height*.56)<.1,"Street Names retains recovered camera-row space")
	check(safe.grow(.1).encloses(host.street_names.panel.get_global_rect()))
