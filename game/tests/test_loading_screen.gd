# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const PREFS := "user://loading-test.cfg"
const SAVE := "user://loading-test.sc2d"
const NAMED_SAVE := "loading-screen-test-save"
var host: GameHost

func before_each() -> void:
	host = MAIN.instantiate()
	host.preferences_path = PREFS
	root.add_child(host)
	host.new_city_dialog.terrain_transport_factory = preload("res://tests/real_world/fake_terrain_transport.gd").new().make_transport

func after_each() -> void:
	host.free()
	for path: String in [PREFS,SAVE,CityFileFlow.save_path_for(NAMED_SAVE)]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await process_frame

func _screen() -> Control:
	return host.get("loading_screen") as Control

func _settle() -> void:
	for frame in 30:
		await process_frame
		if not _screen().visible: return
	check(false,"loading transition finishes")

func _play() -> void:
	host.begin_city(flat_city(),{},4242,CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.select_tool(Tools.Kind.ROAD)
	check(bool(host.handle_drag(Vector2i(8,10),Vector2i(15,10)).get("ok",false)),"entry fixture has a paid ordinary road")
	host.select_tool(Tools.Kind.QUERY)
	host.city_view_3d.set_camera_state(Vector3(10.5,4*CityGeometry3D.HEIGHT,10.5),1,12.0)
	await physics_frame

func test_work_waits_for_loading_and_duplicate_actions_are_blocked() -> void:
	await _play()
	var city_before := SaveFormat.encode_city(host.sim.city)
	var sim_before := host.sim.snapshot().duplicate(true)
	var state := {"calls":0}
	host.run_loading("Preparing city…","Please wait.",func() -> bool:
		state.calls += 1
		check(_screen().visible and host.is_input_blocked(),"screen covers synchronous work")
		check(not host.sim.is_processing(),"city clock held without changing saved speed")
		host._on_menu_action(&"speed",GameClock.Speed.FASTEST)
		host.escape()
		return true)
	check(_screen().visible,"screen appears immediately")
	check_eq(state.calls,0,"work has not started in the initiating signal")
	host.run_loading("Duplicate","",func(): state.calls += 100)
	await _settle()
	check_eq(state.calls,1,"one operation runs")
	check(not host.is_input_blocked(),"map input returns")
	check(host.sim.is_processing(),"clock processing restored")
	check_eq(SaveFormat.encode_city(host.sim.city),city_before,"wait preserves city")
	check_eq(host.sim.snapshot(),sim_before,"wait preserves simulation and speed")

func test_load_dialog_uses_loading_then_restores_saved_speed() -> void:
	await _play()
	var target := flat_city(12345)
	target.name = "Loaded town"
	var snapshot := host.sim.snapshot().duplicate(true)
	snapshot["speed"] = GameClock.Speed.FAST
	check_eq(SaveFormat.save(SAVE,target,snapshot),OK)
	var previous := host.sim.city
	host.files.open_load_dialog()
	host.load_dialog.refresh([SaveFormat.read_header(SAVE)] as Array[Dictionary])
	host.load_dialog.confirm()
	check(_screen().visible,"save selection immediately shows loading")
	check_eq(host.sim.city,previous,"old city retained until screen can draw")
	await _settle()
	check_eq(host.sim.city.name,"Loaded town")
	check_eq(host.sim.city.funds,12345)
	check_eq(host.sim.speed,GameClock.Speed.FAST,"saved speed survives dialog closure")
	check_eq(host.modal_depth,0)
	check(not host.is_input_blocked())

func test_failed_load_dismisses_loading_and_retains_error_and_city() -> void:
	await _play()
	var previous := host.sim.city
	host.toolbar.button_for(Tools.Kind.ROAD).grab_focus()
	host.load_dialog.load_requested.emit("user://no-such-loading-city.sc2d")
	check(_screen().visible)
	await _settle()
	check_eq(host.sim.city,previous)
	check(host.notice_dialog.is_open(),"failure notice remains accessible")
	check(host.notice_dialog.is_ancestor_of(root.gui_get_focus_owner()),"failure notice keeps keyboard focus")
	check_eq(host.modal_depth,1,"only error owns a modal")
	host.notice_dialog.dismiss()
	check_eq(host.modal_depth,0)
	check(not host.is_input_blocked())

func test_explore_menu_defers_entry_and_preserves_build_return() -> void:
	await _play()
	host.select_tool(Tools.Kind.ROAD)
	var city_before := SaveFormat.encode_city(host.sim.city)
	var sim_before := host.sim.snapshot().duplicate(true)
	host._on_menu_action(&"explore",null)
	check(_screen().visible)
	check(not host.exploration.is_active(),"physical world waits for loading frame")
	host._on_menu_action(&"explore",null)
	await _settle()
	check(host.exploration.is_active())
	check(not host.exploration.is_suspended(),"new Explore session is ready after loading")
	check_eq(SaveFormat.encode_city(host.sim.city),city_before)
	check_eq(host.sim.snapshot(),sim_before)
	host.return_to_build()
	check_eq(host.tool,Tools.Kind.ROAD)
	check(host.toolbar.visible and host.city_view_3d.camera.current)

func test_failed_explore_entry_returns_to_build_without_stuck_loading() -> void:
	await _play()
	host.city_view_3d._traversal_chunks.clear()
	host.select_tool(Tools.Kind.ROAD)
	host._on_menu_action(&"explore",null)
	await _settle()
	check(not host.exploration.is_active())
	check_eq(host.tool,Tools.Kind.ROAD)
	check(host.toolbar.visible and host.notice_dialog.is_open(),"failure returns to Build with its error")
	host.notice_dialog.dismiss()
	check(not host.is_input_blocked(),"acknowledging restores Build input")

func test_new_city_buttons_cover_generation_and_start_without_nested_loads() -> void:
	host.open_new_city_dialog()
	host.new_city_dialog.name_edit.text = "Loading new city"
	host.new_city_dialog.seed_edit.text = "4242"
	host.new_city_dialog.generate_button.pressed.emit()
	check(_screen().visible)
	check(host.new_city_dialog.preview_city == null)
	await _settle()
	check(host.new_city_dialog.preview_city != null)
	check(host.new_city_dialog.is_open())
	host.new_city_dialog.start_button.pressed.emit()
	check(_screen().visible)
	await _settle()
	check_eq(host.stage,GameHost.Stage.EDITING)
	check_eq(host.sim.city.name,"Loading new city")
	check_eq(host.modal_depth,0)
	check_eq(host.sim.speed,GameClock.Speed.PAUSED)
	host.toolbar.found_button.pressed.emit()
	check(_screen().visible)
	await _settle()
	check_eq(host.stage,GameHost.Stage.PLAY)
	check_eq(host.sim.city.day,0,"loading does not consume days")

func test_screen_fits_compact_and_high_density_display() -> void:
	for dimensions: Vector2i in [Vector2i(640,400),Vector2i(2560,1600)]:
		root.size = dimensions
		host.display_layout.refresh_with_metrics(dimensions,2.0 if dimensions.x > 640 else 1.0)
		host.run_loading("Importing classic city…","Preparing the city and its 3D view.",func():
			var panel: Control = _screen().get_node("Center/Panel")
			check(host.display_layout.logical_rect().encloses(panel.get_global_rect()),"loading content fits display")
			check_eq(_screen().size,host.display_layout.logical_rect().size,"screen covers whole logical canvas"))
		await _settle()

func test_native_pickers_cover_import_and_load_failures_and_balance_modals() -> void:
	await _play()
	var previous := host.sim.city
	for importing: bool in [true,false]:
		if importing: host.files.open_import_dialog()
		else: host.files.open_native_load_dialog()
		var picker: FileDialog = host.files.import_dialog if importing else host.files.native_load_dialog
		picker.hide()
		picker.file_selected.emit("user://missing-loading-city.sc2" if importing else "user://missing-loading-city.sc2d")
		check(_screen().visible,"native file selection starts loading")
		check(not host.files.picker_modal,"picker ownership ends before loading")
		await _settle()
		check_eq(host.sim.city,previous,"bad file preserves current city")
		check(host.notice_dialog.is_open())
		check_eq(host.modal_depth,1)
		host.notice_dialog.dismiss()
		check_eq(host.modal_depth,0)
		check(not host.is_input_blocked())

func test_regeneration_waits_and_preserves_editing_settings() -> void:
	var params := {"name":"Terrain wait","seed":4242,"hills":0,"water":0,"trees":0}
	var previous := host.start_new_city(params,flat_city())
	var before := host.editing_params.duplicate(true)
	host.files._perform_city_action(&"regenerate")
	check(_screen().visible)
	check_eq(host.sim.city,previous)
	await _settle()
	check_ne(host.sim.city,previous)
	check_eq(host.stage,GameHost.Stage.EDITING)
	check_eq(host.editing_params.name,before.name)
	check_eq(host.editing_params.hills,0)
	check_eq(host.sim.speed,GameClock.Speed.PAUSED)

func _press(code: Key, unicode_value: int = 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode_value
	event.pressed = true
	root.push_input(event)

func test_loading_consumes_tab_typing_and_escape_over_visible_dialog() -> void:
	host.open_new_city_dialog()
	host.new_city_dialog.name_edit.text = "Keep this name"
	host.new_city_dialog.generate_button.pressed.emit()
	_press(KEY_TAB)
	_press(KEY_Z,122)
	_press(KEY_ESCAPE)
	check_eq(host.new_city_dialog.name_edit.text,"Keep this name","typing cannot reach covered dialog")
	check(host.new_city_dialog.is_open(),"Escape cannot dismiss covered dialog")
	check_eq(root.gui_get_focus_owner(),_screen(),"loading retains keyboard ownership")
	await _settle()
	check(host.new_city_dialog.is_open())

func test_loading_consumes_enter_and_escape_over_new_error_notice() -> void:
	await _play()
	host.run_loading("Loading city…","",func():
		host.notices.show("Cannot Load","Keep this error visible.")
		_press(KEY_TAB)
		_press(KEY_ENTER)
		_press(KEY_ESCAPE)
		check(host.notice_dialog.is_open(),"covered error cannot be acknowledged early"))
	await _settle()
	check(host.notice_dialog.is_open(),"error survives loading")
	check(host.notice_dialog.is_ancestor_of(root.gui_get_focus_owner()),"error receives focus when loading ends")

func test_manual_save_and_save_as_wait_before_writing() -> void:
	await _play()
	host.save_path = SAVE
	check_eq(host.save_city(),OK)
	var before := FileAccess.get_file_as_bytes(SAVE)
	host.sim.city.funds -= 10
	host._on_menu_action(&"city_save",null)
	check(_screen().visible,"manual Save starts loading")
	check(FileAccess.get_file_as_bytes(SAVE) == before,"file waits until loading can draw")
	await _settle()
	check_ne(FileAccess.get_file_as_bytes(SAVE),before)
	check_eq(host.save_path,SAVE)
	host.files.open_save_dialog()
	host.save_dialog.name_edit.text = NAMED_SAVE
	host.save_dialog.confirm()
	await process_frame
	check(_screen().visible,"Save As starts loading after dialog closure")
	await _settle()
	check_eq(host.save_path,CityFileFlow.save_path_for(NAMED_SAVE))
	check_eq(host.modal_depth,0)
	check(not host.files.has_unsaved_changes())

func test_save_before_leaving_runs_next_action_after_loading_closes() -> void:
	await _play()
	host.files.save_city_as(NAMED_SAVE)
	host.sim.city.funds -= 10
	host.files.request_city_action(&"new")
	check(host.notice_dialog.is_open())
	host.notice_dialog.dismiss(&"save")
	check(_screen().visible,"save-before-leaving starts loading")
	check(not host.new_city_dialog.is_open(),"next action waits for save")
	await _settle()
	check(host.new_city_dialog.is_open(),"next action runs after loading closes")
	check_eq(int(SaveFormat.load(CityFileFlow.save_path_for(NAMED_SAVE)).city.funds),host.sim.city.funds)
	host.new_city_dialog.close()
	check_eq(host.modal_depth,0)

func test_load_menu_covers_save_list_scan() -> void:
	host.title_screen.load_requested.emit()
	check(_screen().visible,"saved-city scan starts loading")
	check(not host.load_dialog.is_open(),"dialog waits for scan")
	await _settle()
	check(host.load_dialog.is_open())
	check(host.load_dialog.is_ancestor_of(root.gui_get_focus_owner()),"loaded list owns focus")
