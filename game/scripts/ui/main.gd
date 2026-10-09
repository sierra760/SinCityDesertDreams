# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The game host: the title screen and the in-game shell (map, toolbar,
## status bar, menus, minimap). Everything a player does goes through this
## node; the simulation only ever hears from it.
##
## The host owns input, menu dispatch, modal state and the loading screen,
## and wires the pieces together. Its helpers own the rest:
## `GameShellLayout` (the chrome), `CityFileFlow` (dialogs, saving and
## quitting), `CitySession` (new, founded, loaded and imported cities),
## `ConstructionFlow` (building), `ExploreModeSwitch` (entering and leaving
## Explore), `PreferencesController` (options), `WindowManager` (report
## windows) and `NoticeQueue` (notices).
class_name GameHost
extends Node

const Platform := preload("res://scripts/platform/mobile_platform.gd")

## A gaming-resort table was closed (Leave table, Escape or the city closing).
signal casino_closed

## NONE before a city exists, EDITING while the land is shaped, PLAY after founding.
enum Stage { NONE, EDITING, PLAY }

const NO_TOOL := -1
## Visible time for transient feedback, independent of simulation speed.
const MESSAGE_SECONDS := 7.0

@onready var sim: Simulation = $Simulation
var street_names: StreetNamesSession
var street_topology := StreetTopology.new()
var street_naming_service := StreetNamingService.new()
var _sim_process_holds: Dictionary = {}
var _sim_process_before_holds := true
var presentation: CityPresentationController
var display_layout: DisplayLayout
var entity_records: CityEntityRecords
@onready var mini_map: MiniMap = $MiniMap
@onready var ui_layer: CanvasLayer = $UI

var shell: GameShellLayout
var files: CityFileFlow
var session: CitySession
var construction: ConstructionFlow
var prefs: PreferencesController
var window_manager: WindowManager
var notices: NoticeQueue
var explore_switch: ExploreModeSwitch

var modal_layer: CanvasLayer
var loading_screen: GameLoadingScreen
var city_view_3d: CityView3D
var exploration: CityExplorationController
var explore_hud: ExploreHUD
var cursor_caption_3d: Label
## Tests may supply a separate preference file without changing city saves.
var preferences_path := ViewPreferences.PATH
var builder: Builder
var toolbar: Toolbar
var status_bar: StatusBar
var menu_bar: GameMenuBar
var share_dialog: ShareCityDialog
var title_screen: TitleScreen
var new_city_dialog: NewCityDialog
var load_dialog: LoadDialog
var save_dialog: SaveDialog
var notice_dialog: NoticeDialog
var choice_dialog: ConstructionChoiceDialog
var query_panel: QueryPanel
## The gaming-resort table, created the first time one opens.
var casino_overlay: CasinoTableOverlay
## Music, interface sounds and effects.
var audio: GameAudio
var _casino_hid_hud := false

## The selected tool, or NO_TOOL.
var tool := NO_TOOL
var in_game := false
var stage := Stage.NONE
## The terrain tools of the editing stage; null once the city is founded.
var terrain_editor: TerrainEditor
## Settings of the map being shaped (see `TerrainGenerator`), kept for
## Regenerate, for founding and for unfounded saves.
var editing_params: Dictionary = {}
## File the current city was loaded from or last saved to.
var save_path := ""
var preferences: Dictionary = {}
var controls := ControlBindings.new()
## Windows created so far, by name.
var windows: Dictionary:
	get: return window_manager.windows

## Open modal dialogs; the city is paused while this is above zero.
var modal_depth := 0
## Speed to restore when the last modal closes.
## Frame cap while a desktop window is in the background.
const BACKGROUND_MAX_FPS := 15
var speed_before_modal: int = GameClock.Speed.SLOW
## The speed Pause returns to: the last speed the city actually ran at.
var _last_running_speed: int = GameClock.Speed.SLOW
## Time left before the status message reverts; zero keeps it up.
var message_seconds_left := 0.0
var _tool_before_bulldoze := NO_TOOL
var _temporary_bulldoze := false
var _drag_active := false
var _query_hover := Vector2i(-1, -1)
var _query_hover_suppressed := false
var _active_drag_from := Vector2i(-1, -1)
var _active_drag_to := Vector2i(-1, -1)
var _last_click_button := MOUSE_BUTTON_LEFT
var _query_refresh_pending := false
var _previous_auto_accept_quit := true
var _application_suspended := false
## False while another application has focus (minimized or behind another window).
var _window_in_foreground := true
var _background_save_error: Error = OK


func _init() -> void:
	session = CitySession.new(self)
	construction = ConstructionFlow.new(self)
	prefs = PreferencesController.new(self)
	window_manager = WindowManager.new(self)
	notices = NoticeQueue.new(self)
	explore_switch = ExploreModeSwitch.new(self)


func _ready() -> void:
	IOSGestureScroll.install_tree(self)
	shell = GameShellLayout.new(self)
	add_child(shell)
	# A test may supply its own file flow before the host enters the tree.
	if files == null: files = CityFileFlow.new(self)
	add_child(files)
	_previous_auto_accept_quit = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(files.quit_game)
	preferences = Platform.read_view_preferences(preferences_path)
	controls.configure(preferences.get("control_bindings",{}))
	display_layout = DisplayLayout.new()
	add_child(display_layout)
	display_layout.bind(get_window())
	display_layout.restore_window(preferences)
	city_view_3d = CityView3D.new()
	city_view_3d.controls = controls
	city_view_3d.name = "CityView3D"
	add_child(city_view_3d)
	city_view_3d.bind_display_layout(display_layout)
	city_view_3d.bind_analytics(CityOverlay3D.new(), CityUnderground3D.new())
	city_view_3d.input_blocked = is_camera_input_blocked
	city_view_3d.touch_input_blocked = is_touch_camera_input_blocked
	presentation = CityPresentationController.new()
	presentation.name = "Presentation"
	presentation.view = city_view_3d
	presentation.input_blocked = is_input_blocked
	presentation.set_touch_ui_ownership_checker(touch_ui_owned)
	presentation.drag_cancelled.connect(cancel_map_gesture)
	add_child(presentation)
	entity_records = CityEntityRecords.new()
	entity_records.simulation = sim
	modal_layer = CanvasLayer.new()
	modal_layer.name = "Modal"
	modal_layer.layer = 20
	add_child(modal_layer)
	var loading_layer := CanvasLayer.new()
	loading_layer.name = "Loading"
	loading_layer.layer = 30
	add_child(loading_layer)
	loading_screen = GameLoadingScreen.new()
	loading_layer.add_child(loading_screen)
	_build_chrome()
	_build_dialogs()
	street_names = StreetNamesSession.new()
	add_child(street_names)
	street_names.bind(self,street_naming_service,street_topology)
	street_naming_service.changed.connect(_on_station_names_changed)
	_connect_simulation()
	_connect_presentation()
	prefs.apply()
	explore_hud = ExploreHUD.new()
	explore_hud.controls = controls
	explore_hud.layer = 8
	explore_hud.sensitivity = preferences["explore_sensitivity"]
	explore_hud.invert_y = preferences["explore_invert_y"]
	add_child(explore_hud)
	explore_hud.bind_layout(display_layout)
	explore_hud.settings_requested.connect(func() -> void:
		var options := window_manager.open("options") as OptionsWindow
		if options != null: options.tabs.current_tab = 1)
	exploration = CityExplorationController.new()
	exploration.controls = controls
	exploration.set_pedestrian_character(preferences["explore_character"])
	add_child(exploration)
	exploration.bind(city_view_3d,explore_hud)
	exploration.set_touch_controls_enabled(Platform.uses_touch())
	exploration.touch_controls_changed.connect(func(_on: bool) -> void:
		if is_instance_valid(shell) and is_exploring(): shell.update_minimap_visibility())
	exploration.input_blocked = is_explore_input_blocked
	exploration.release_ui_focus = display_layout.release_city_focus
	exploration.return_requested.connect(explore_switch.leave)
	exploration.casino_table_requested.connect(_on_casino_table_requested)
	audio = GameAudio.new()
	audio.name = "Audio"
	add_child(audio)
	audio.apply_preferences(preferences)
	audio.bind(self)
	menu_bar.popup_opened.connect(exploration.suspend)
	get_window().focus_exited.connect(exploration.suspend)
	get_window().focus_exited.connect(restore_temporary_bulldoze)
	get_window().focus_exited.connect(cancel_map_gesture)
	menu_bar.popup_opened.connect(restore_temporary_bulldoze)
	mini_map.input_blocked = is_minimap_input_blocked
	display_layout.metrics_changed.connect(shell.apply_metrics)
	status_bar.resized.connect(shell.schedule)
	status_bar.minimum_size_changed.connect(shell.schedule)
	menu_bar.resized.connect(shell.schedule)
	shell.register_chrome(ui_layer)
	shell.register_chrome(modal_layer)
	shell.apply_popups(ui_layer)
	shell.apply_popups(modal_layer)
	shell.apply_metrics(display_layout.metrics)
	_show_title()


func _build_chrome() -> void:
	shell.build_chrome(ui_layer)
	menu_bar.action_requested.connect(_on_menu_action)
	menu_bar.tools_requested.connect(func() -> void: shell.set_phone_tools_open(not shell.phone_tools_open))
	menu_bar.inspect_requested.connect(func() -> void:
		if stage == Stage.PLAY: select_tool(Tools.Kind.QUERY))
	toolbar.tool_selected.connect(select_tool)
	toolbar.found_requested.connect(func() -> void: run_loading("Founding city…","Preparing your city for play.",session.found_city))
	toolbar.regenerate_requested.connect(func() -> void: files.request_city_action(&"regenerate"))
	status_bar.emergency_requested.connect(go_to_emergency)
	query_panel.demolish_requested.connect(construction._on_demolish_requested)
	query_panel.rename_requested.connect(construction.prompt_rename)
	query_panel.closed.connect(sync_query_feedback)


func _build_dialogs() -> void:
	title_screen = TitleScreen.new()
	title_screen.quit_button.visible = can_quit_application()
	title_screen.new_city_requested.connect(func() -> void: files.request_city_action(&"new"))
	title_screen.load_requested.connect(func() -> void: files.request_city_action(&"load"))
	title_screen.import_requested.connect(func() -> void: files.request_city_action(&"import"))
	title_screen.quit_requested.connect(files.quit_game)
	title_screen.settings_requested.connect(func() -> void: window_manager.open("options"))
	title_screen.license_requested.connect(func() -> void: window_manager.open("license"))
	title_screen.help_requested.connect(func() -> void: window_manager.open("help"))
	title_screen.shortcuts_blocked = func() -> bool: return modal_depth > 0 or files.picker_modal or loading_screen.visible
	modal_layer.add_child(title_screen)
	new_city_dialog = NewCityDialog.new()
	new_city_dialog.run_loading = run_loading
	new_city_dialog.started.connect(func(params: Dictionary, city: City) -> void: session.start_new_city(params, city))
	new_city_dialog.closed.connect(pop_modal)
	modal_layer.add_child(new_city_dialog)
	load_dialog = LoadDialog.new()
	load_dialog.load_requested.connect(func(path: String) -> void: run_loading("Loading city…",path.get_file(),session.load_city.bind(path)))
	load_dialog.bundled_city_requested.connect(func(path: String) -> void: run_loading("Opening included city…",path.get_file().get_basename(),session.open_included_city.bind(path)))
	load_dialog.share_requested.connect(files.request_city_share)
	load_dialog.closed.connect(pop_modal)
	load_dialog.browse_requested.connect(files.open_native_load_dialog)
	modal_layer.add_child(load_dialog)
	share_dialog = ShareCityDialog.new()
	share_dialog.closed.connect(func() -> void:
		pop_modal()
		files.restore_share_browser())
	modal_layer.add_child(share_dialog)
	save_dialog = SaveDialog.new()
	save_dialog.save_requested.connect(files._on_save_name_submitted)
	save_dialog.closed.connect(files._on_save_dialog_closed)
	modal_layer.add_child(save_dialog)
	notice_dialog = NoticeDialog.new()
	notice_dialog.closed.connect(notices._on_notice_closed)
	modal_layer.add_child(notice_dialog)
	choice_dialog = ConstructionChoiceDialog.new()
	choice_dialog.chosen.connect(construction._on_choice_made)
	choice_dialog.cancelled.connect(construction._on_choice_cancelled)
	modal_layer.add_child(choice_dialog)


func _connect_simulation() -> void:
	sim.map_changed.connect(func(_rect: Rect2i) -> void:
		if street_topology.is_bound_to(sim.city):
			street_naming_service.reconcile(_rect)
			street_names.structural_changed()
		city_view_3d.queue_refresh()
		mini_map.generate_image()
		_query_refresh_pending = true)
	sim.day_advanced.connect(_on_day_advanced)
	sim.year_ended.connect(func(_y: int) -> void: refresh_toolbar())
	sim.funds_changed.connect(func(funds: int) -> void: status_bar.set_funds(funds))
	sim.population_changed.connect(func(p: int) -> void: status_bar.set_population(p))
	sim.speed_changed.connect(_on_speed_changed)
	sim.budget_review_due.connect(_on_budget_review_due)
	sim.notice_raised.connect(notices.raise)
	sim.disaster_started.connect(_on_disaster_started)
	sim.disaster_ended.connect(func(_k: StringName) -> void: refresh_toolbar())


func _connect_presentation() -> void:
	city_view_3d.view_changed.connect(_on_3d_view_changed)
	presentation.preview.footprint_changed.connect(sync_3d_cursor)
	presentation.tile_clicked.connect(_on_tile_clicked)
	presentation.tile_hovered.connect(_on_tile_hovered)
	presentation.drag_started.connect(_on_drag_started)
	presentation.drag_updated.connect(_on_drag_updated)
	presentation.drag_ended.connect(_on_drag_ended)
	presentation.overlay_changed.connect(func(kind: StringName) -> void:
		menu_bar.set_checked(&"overlay", true, kind)
		prefs.set_value("overlay", String(kind)))
	presentation.view_mode_changed.connect(func(mode: int) -> void:
		menu_bar.set_checked(&"underground", mode == CityPresentationController.ViewMode.UNDERGROUND))


func _show_title() -> void:
	if not OS.has_feature("web"): DisplayServer.screen_set_keep_on(false)
	explore_switch.dispose()
	title_screen.open()
	shell.set_chrome_visible(false)


# ── Entry points ─────────────────────────────────────────────────────────
# Tests and tools drive the game through these; the helpers do the work.

func start_new_city(params: Dictionary, prebuilt: City = null) -> City:
	return session.start_new_city(params, prebuilt)


func found_city() -> bool:
	return session.found_city()


func regenerate(seed_value: int = -1) -> City:
	return session.regenerate(seed_value)


func load_city(path: String) -> bool:
	return session.load_city(path)


func import_city(path: String) -> bool:
	return session.import_city(path)


## Bind an already loaded or generated city and enter play (see `CitySession.begin_city`).
func begin_city(city: City, snapshot: Dictionary, seed_value: int, stats: CityStats, topology: StreetTopology = null) -> void:
	session.begin_city(city, snapshot, seed_value, stats, topology)


func save_city() -> Error:
	return files.save_city()


func open_new_city_dialog() -> void:
	files.open_new_city_dialog()


func handle_drag(from: Vector2i, to: Vector2i) -> Dictionary:
	return construction.handle_drag(from, to)


func set_option(key: StringName, value: Variant) -> void:
	prefs.set_option(key, value)


func open_window(window_name: String) -> Control:
	return window_manager.open(window_name)


func enter_explore() -> bool:
	return explore_switch.enter()


func return_to_build() -> void:
	explore_switch.leave()


# ── Loading and the application lifecycle ───────────────────────────────

## Run slow synchronous `work` behind the loading screen. Simulation
## processing (not the saved speed) is held across the draw boundaries so
## loading cannot consume city time.
func run_loading(title: String, detail: String, work: Callable) -> Variant:
	if loading_screen.visible or not work.is_valid(): return null
	var focused := get_viewport().gui_get_focus_owner()
	var focus: WeakRef = weakref(focused) if focused != null else null
	acquire_sim_process_hold(&"loading")
	var explore_processing := is_instance_valid(exploration) and exploration.is_physics_processing()
	var was_exploring := is_exploring()
	interrupt_map_input()
	if is_instance_valid(exploration): exploration.set_physics_process(false)
	loading_screen.open(title,detail)
	await loading_screen.presented_frame()
	var result: Variant = work.call()
	# Explore normally captures the pointer immediately. Keep the loading
	# surface in control until its final covered frame has been presented.
	if is_exploring(): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await loading_screen.presented_frame()
	var restore_focus := get_viewport().gui_get_focus_owner() == loading_screen or get_viewport().gui_get_focus_owner() == null
	loading_screen.close()
	release_sim_process_hold(&"loading")
	if is_instance_valid(exploration): exploration.set_physics_process(explore_processing)
	if is_exploring() and not was_exploring and not exploration.is_suspended() and not is_input_blocked():
		exploration.resume()
	elif not is_exploring() and restore_focus and not notice_dialog.is_open() and not choice_dialog.is_open():
		var previous := focus.get_ref() as Control if focus != null else null
		if is_instance_valid(previous) and previous.is_visible_in_tree(): previous.grab_focus()
	# A notice opened by the work, or a covered form that stayed open, gets
	# its keyboard owner back even if loading consumed input after it opened.
	for modal: Control in [notice_dialog,choice_dialog,new_city_dialog,load_dialog,save_dialog]:
		if modal.is_visible_in_tree():
			UIFactory.contain_modal_focus(modal)
			break
	return result


## Write the annual backup. Only a founded city has one.
func autosave() -> Error:
	if stage != Stage.PLAY:
		return ERR_UNAVAILABLE
	return SaveFormat.save(CityFileFlow.autosave_path(), sim.city, sim.snapshot())


## iOS keeps applications alive; leaving a city returns to the title instead.
func can_quit_application() -> bool:
	return not Platform.is_ios()


## Save a recovery copy while a mobile OS still allows background execution.
## Named and annual saves, and the unsaved-changes state, are left untouched.
func suspend_for_background(recovery_path: String = "") -> Error:
	if _help_sources_open(): (windows.help as HelpWindow).sources_dialog.close()
	if is_instance_valid(new_city_dialog) and new_city_dialog.is_open(): new_city_dialog.cancel_online_work()
	if _application_suspended: return _background_save_error
	_application_suspended = true
	# A round in play is played out as it stands (not refunded, so leaving
	# the app never undoes a bad hand) and the table closes; the recovery
	# copy never holds a stake.
	if is_casino_open() and casino_overlay.round_in_progress(): casino_overlay.resolve_round_now()
	acquire_sim_process_hold(&"background")
	interrupt_map_input()
	speed_before_modal = GameClock.Speed.PAUSED
	if not is_instance_valid(sim) or sim.city == null or stage == Stage.NONE:
		_background_save_error = ERR_UNAVAILABLE
		return _background_save_error
	sim.set_speed(GameClock.Speed.PAUSED)
	var path := CityFileFlow.application_recovery_path() if recovery_path.is_empty() else recovery_path
	_background_save_error = SaveFormat.save(path, sim.city, {}, SaveFormat.STAGE_EDITING, editing_params) if stage == Stage.EDITING else SaveFormat.save(path, sim.city, sim.snapshot())
	if _background_save_error == OK and is_instance_valid(files) and CityFileFlow.is_application_recovery_path(path):
		files.note_recovery_copy(sim.city)
	return _background_save_error


func resume_from_background() -> void:
	if is_instance_valid(new_city_dialog) and new_city_dialog.is_open(): new_city_dialog.resume_online_work()
	if not _application_suspended: return
	_application_suspended = false
	release_sim_process_hold(&"background")
	cancel_map_gesture()
	speed_before_modal = GameClock.Speed.PAUSED
	if is_instance_valid(sim): sim.set_speed(GameClock.Speed.PAUSED)
	# A casino round the app played out on the way to the background.
	var casino_note := casino_overlay.take_background_summary() if is_instance_valid(casino_overlay) else ""
	if _background_save_error != OK and _background_save_error != ERR_UNAVAILABLE:
		notices.show("Recovery Backup Failed", "The recovery copy could not be written while the app was in the background. Your saved cities are unchanged. Save the city before leaving the app.")
		if not casino_note.is_empty(): show_message(casino_note)
	elif is_instance_valid(sim) and sim.city != null and stage == Stage.PLAY:
		show_message(("%s " % casino_note if not casino_note.is_empty() else "") + "Paused while you were away. Choose a speed to continue.")
	# The app came back, so the recovery copy written on the way out is not needed.
	if _background_save_error == OK and is_instance_valid(files): files.discard_recovery_copy()
	_background_save_error = OK


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_CLOSE_REQUEST:
		prefs.flush()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# project.godot sets quit_on_go_back=false, so Android Back arrives here.
		if is_instance_valid(files): go_back()
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_in_foreground = what == NOTIFICATION_APPLICATION_FOCUS_IN
		if is_instance_valid(sim): sync_keep_screen_on()
	if not Platform.is_mobile():
		# Switching to another window keeps terrain downloads going; only an
		# OS-level pause stops them. A hidden or background window renders
		# slowly to spare the laptop battery; the simulation clock uses delta.
		if is_instance_valid(new_city_dialog) and new_city_dialog.is_open():
			if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
				new_city_dialog.terrain_dialog.extent_map.cancel_gesture()
			elif what == NOTIFICATION_APPLICATION_PAUSED:
				new_city_dialog.cancel_online_work()
			elif what == NOTIFICATION_APPLICATION_RESUMED:
				new_city_dialog.resume_online_work()
		if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
			Engine.max_fps = BACKGROUND_MAX_FPS
			if bool(preferences.get("pause_in_background", true)):
				if is_instance_valid(sim): acquire_sim_process_hold(&"desktop_background")
				# Music and loops pause with the city instead of playing over other apps.
				if is_instance_valid(audio): audio.set_background(true)
		elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
			Engine.max_fps = 0
			if is_instance_valid(sim): release_sim_process_hold(&"desktop_background")
			if is_instance_valid(audio): audio.set_background(false)
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_instance_valid(presentation): suspend_for_background()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if is_instance_valid(presentation): resume_from_background()


## Android Back closes the front-most thing as Escape does (a notice, dialog,
## window, the phone Tools drawer, the Explore menu, the tool). Exploring with
## nothing open, it opens the Explore menu. With nothing left to close it
## leaves through the normal quit path, which offers to save the city first.
func go_back() -> void:
	if loading_screen.visible: return
	if _back_has_target(): escape(true)
	else: files.quit_game()


## True when Escape would close or cancel something rather than do nothing.
func _back_has_target() -> bool:
	return share_dialog.is_open() or is_casino_open() or notice_dialog.is_open() or choice_dialog.is_open() \
		or new_city_dialog.is_open() or load_dialog.is_open() or save_dialog.is_open() or _help_sources_open() \
		or window_manager.front() != null or _drag_active or query_panel.is_open() \
		or (shell.phone_layout and shell.phone_tools_open) or is_exploring() \
		or street_names.is_active() or tool != NO_TOOL


## Keep the display awake only while a city's clock runs in the focused
## window. A background, minimized or suspended game lets the display sleep;
## Web has no keep-awake support (it would log a warning on every change).
func keep_screen_on_wanted(speed: int = -1) -> bool:
	var running := (sim.speed if speed < 0 else speed) != GameClock.Speed.PAUSED
	return running and in_game and _window_in_foreground and not _application_suspended


func sync_keep_screen_on(speed: int = -1) -> void:
	if OS.has_feature("web"): return
	DisplayServer.screen_set_keep_on(keep_screen_on_wanted(speed))


# ── Tools and the inspector ──────────────────────────────────────────────

## Make `new_tool` the active tool (NO_TOOL for none). A whole-map tool
## (the sea level) is applied once instead and the current tool stays.
func select_tool(new_tool: int, preserve_gesture: bool = false) -> void:
	if street_names != null and street_names.is_active(): return
	if is_exploring(): return
	if new_tool != NO_TOOL and Tools.is_immediate(new_tool):
		if construction != null: construction.apply_immediate(new_tool)
		return
	if shell.phone_layout and shell.phone_tools_open and not preserve_gesture:
		shell.set_phone_tools_open(false)
	if not preserve_gesture:
		drop_temporary_bulldoze()
		cancel_map_gesture()
	tool = new_tool
	presentation.set_query_tool_active(tool == Tools.Kind.QUERY)
	presentation.pick_purpose = 1 if tool == Tools.Kind.QUERY or tool == Tools.Kind.BULLDOZE else 0
	toolbar.set_active(tool)
	status_bar.set_tool_text(Tools.display_name(tool) if tool != NO_TOOL else "none")
	presentation.preview.clear()
	if in_game and not preserve_gesture:
		presentation.select_tool(tool)
		if presentation.is_underground():
			status_bar.set_message("Underground · pipes and subway")
	if preserve_gesture and _drag_active:
		construction.preview_drag(_active_drag_from, _active_drag_to)
	if tool != Tools.Kind.QUERY: _query_hover = Vector2i(-1, -1)
	presentation.refresh_query_pointer_hover()
	sync_query_feedback()


func open_query(at: Vector2i) -> void:
	if stage != Stage.PLAY or sim.city == null:
		return
	query_panel.show_tile(sim.city, sim, at)
	sync_query_feedback()


## Station renames apply only to the city currently shown.
func _on_station_names_changed(revision: int, affected: Dictionary) -> void:
	if sim.city == null or city_view_3d.city != sim.city: return
	var anchors: Array[Vector2i] = []
	for anchor: Vector2i in affected.get("station_anchors",[]): anchors.append(anchor)
	if anchors.is_empty(): return
	city_view_3d.buildings.refresh_station_names(anchors)
	if query_panel.is_open(): query_panel.show_tile(sim.city,sim,query_panel.tile)
	if is_instance_valid(exploration):
		var transit := exploration.transit_service as ExploreTransitService
		if is_instance_valid(transit) and transit.network != null and transit.network.city == sim.city:
			transit.refresh_names(revision)
			explore_hud.set_transit_status(transit.status())


## A status message that stays readable at every simulation speed.
func show_message(text: String) -> void:
	status_bar.set_message(text)
	message_seconds_left = MESSAGE_SECONDS


## Bring the toolbar, emergency action and street menus up to date with the city.
func refresh_toolbar() -> void:
	refresh_street_menus()
	if sim.city == null:
		return
	if stage == Stage.EDITING and editing_params.get("source") == "real_world":
		var imported := CitySession.restore_imported_terrain(editing_params, sim.city)
		toolbar.set_imported_terrain_reset(imported.ok, imported.error)
	else:
		toolbar.set_procedural_regeneration()
	toolbar.refresh(sim.city, sim.stats, sim.get_system(&"disasters"), sim.get_system(&"rewards"))
	if Tools.is_dispatch_tool(tool) and toolbar.is_locked(tool):
		# The emergency is over (or its last station is gone): crews can no
		# longer be sent, so the tool goes back to Inspect.
		var reason := String(toolbar.lock_reasons.get(tool, ""))
		select_tool(Tools.Kind.QUERY)
		if stage == Stage.PLAY:
			show_message("The emergency is over; crews stood down." if reason == Builder.REASON_NO_EMERGENCY else ConstructionFlow.sentence(reason))
	var disasters := sim.get_system(&"disasters") as DisasterSystem
	var available := stage == Stage.PLAY and disasters != null and disasters.emergency_target().x >= 0
	status_bar.set_emergency_available(available)
	menu_bar.set_enabled(&"go_to_emergency", available)


# ── Map input ────────────────────────────────────────────────────────────

func _on_tile_clicked(at: Vector2i, button: int) -> void:
	_last_click_button = button
	if is_exploring() or is_input_blocked():
		return
	if stage != Stage.PLAY:
		return
	if button == MOUSE_BUTTON_RIGHT:
		open_query(at)
	elif tool == Tools.Kind.QUERY:
		open_query(at)
	elif tool == Tools.Kind.SIGN:
		construction.prompt_sign(at)


func _on_tile_hovered(at: Vector2i) -> void:
	_query_hover = at if tool == Tools.Kind.QUERY and not is_exploring() and not is_input_blocked() else Vector2i(-1, -1)
	sync_query_feedback()
	if is_exploring() or is_input_blocked() or _drag_active:
		return
	if at.x < 0 or tool == NO_TOOL or tool == Tools.Kind.QUERY or tool == Tools.Kind.SIGN:
		presentation.preview.clear()
		return
	construction.preview_drag(at, at)


func _on_drag_started(from: Vector2i, to: Vector2i) -> void:
	_drag_active = false
	if is_exploring() or is_input_blocked() or _last_click_button == MOUSE_BUTTON_RIGHT:
		return
	if tool == NO_TOOL or tool == Tools.Kind.QUERY or tool == Tools.Kind.SIGN:
		return
	_drag_active = true
	construction.begin_drag(from)
	_active_drag_from = from
	_active_drag_to = to
	construction.preview_drag(from, to)


func _on_drag_updated(from: Vector2i, to: Vector2i) -> void:
	if is_exploring(): return
	if _drag_active:
		_active_drag_from = from
		_active_drag_to = to
		construction.preview_drag(from, to)


func _on_drag_ended(from: Vector2i, to: Vector2i) -> void:
	if is_exploring():
		cancel_map_gesture()
		return
	if not _drag_active:
		return
	_drag_active = false
	presentation.preview.clear()
	if not is_input_blocked():
		construction.handle_drag(from, to)


## Stop whatever the player was doing on the map: a held temporary
## Bulldoze, a drag or pan in progress, and Explore movement.
func interrupt_map_input() -> void:
	restore_temporary_bulldoze()
	cancel_map_gesture()
	if is_exploring(): exploration.suspend()


## Drop any drag, pan, preview or hover in progress on the map.
func cancel_map_gesture() -> void:
	if construction != null: construction.end_drag()
	_query_hover = Vector2i(-1, -1)
	sync_query_feedback()
	_drag_active = false
	_active_drag_from = Vector2i(-1, -1)
	_active_drag_to = Vector2i(-1, -1)
	presentation.cancel_drag()
	presentation.preview.clear()
	if city_view_3d != null:
		city_view_3d.cancel_pan()
		city_view_3d.clear_cursor()
	if cursor_caption_3d != null:
		cursor_caption_3d.hide()


# ── Keyboard ─────────────────────────────────────────────────────────────

## Release cleanup must run before focused controls can consume the key-up.
func _input(event: InputEvent) -> void:
	if windows.has("options") and (windows.options as OptionsWindow).capture_event(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C \
			and (event.ctrl_pressed or event.meta_pressed) and event.alt_pressed and event.shift_pressed:
		open_cheat_dialog()
		get_viewport().set_input_as_handled()
		return
	if _is_mac_fullscreen_chord(event):
		if not loading_screen.visible: prefs.set_option(&"fullscreen", not display_layout.fullscreen)
		get_viewport().set_input_as_handled()
		return
	# An editing text field would swallow the first Escape (it only stops
	# editing), leaving its dialog open; the dialog closes on the first press.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE \
			and _dialog_text_field_focused():
		escape()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(exploration): exploration.note_pointer_event(event)
	if is_instance_valid(exploration) and event is InputEventKey and not event.pressed:
		exploration.handle_event(event)
	if is_instance_valid(exploration):
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			if is_input_blocked() and is_exploring(): exploration.suspend()
			if exploration.handle_event(event,touch_ui_owned(event.position)):
				get_viewport().set_input_as_handled()
		elif event.device == InputEvent.DEVICE_ID_EMULATION and is_exploring() and (event is InputEventMouseMotion or event is InputEventMouseButton):
			if not touch_ui_owned(event.position) and exploration.handle_event(event):
				get_viewport().set_input_as_handled()
	if event is InputEventKey and not event.pressed and controls.matches(event,&"bulldoze"):
		restore_temporary_bulldoze(true)


## True while a text field inside an open modal dialog has keyboard focus.
func _dialog_text_field_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	if not focused is LineEdit: return false
	for dialog: Control in [notice_dialog, save_dialog, new_city_dialog, load_dialog, share_dialog]:
		if is_instance_valid(dialog) and dialog.visible and dialog.is_ancestor_of(focused): return true
	return false


## macOS keeps F11 for Show Desktop; Ctrl+Cmd+F is the Mac fullscreen chord.
func _is_mac_fullscreen_chord(event: InputEvent) -> bool:
	if OS.get_name() != "macOS" or not event is InputEventKey: return false
	var key := event as InputEventKey
	return key.pressed and not key.echo and key.keycode == KEY_F and key.ctrl_pressed and key.meta_pressed \
		and not key.alt_pressed and not key.shift_pressed


## Return from a held temporary Bulldoze to the tool under it.
func restore_temporary_bulldoze(preserve_gesture: bool = false) -> void:
	if not _temporary_bulldoze: return
	var previous := _tool_before_bulldoze
	drop_temporary_bulldoze()
	select_tool(previous, preserve_gesture)


## Forget a temporary Bulldoze without returning to the tool under it.
func drop_temporary_bulldoze() -> void:
	_temporary_bulldoze = false
	_tool_before_bulldoze = NO_TOOL


## The tool the player chose: the one under a temporary Bulldoze, if any.
func chosen_tool() -> int:
	return _tool_before_bulldoze if _temporary_bulldoze else tool


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.echo:
		return
	if is_exploring():
		# Text and modal owners must suspend before a shortcut can queue input.
		if is_explore_input_blocked(): exploration.suspend()
		if exploration.handle_event(event):
			get_viewport().set_input_as_handled()
			return
	if not key.pressed:
		if controls.matches(key,&"bulldoze"):
			restore_temporary_bulldoze(true)
		return
	# Preserve Shift+plus while leaving application/OS chords to their owners.
	if key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
		return
	if key.keycode == KEY_ESCAPE:
		escape()
		get_viewport().set_input_as_handled()
		return
	if is_camera_input_blocked():
		return
	if controls.matches(key,&"fullscreen"):
		prefs.set_option(&"fullscreen", not display_layout.fullscreen)
		get_viewport().set_input_as_handled()
		return
	if stage != Stage.PLAY:
		return
	if controls.matches(key,&"pause"): sim.set_speed(_last_running_speed if sim.speed == GameClock.Speed.PAUSED else GameClock.Speed.PAUSED)
	elif controls.matches(key,&"faster"): sim.set_speed(sim.speed + 1)
	elif controls.matches(key,&"slower"): sim.set_speed(sim.speed - 1)
	elif controls.matches(key,&"underground"): toggle_underground()
	elif controls.matches(key,&"query"): select_tool(Tools.Kind.QUERY)
	elif controls.matches(key,&"bulldoze"):
		if tool != Tools.Kind.BULLDOZE:
			_tool_before_bulldoze = tool
			_temporary_bulldoze = true
			select_tool(Tools.Kind.BULLDOZE, true)
	else: return
	get_viewport().set_input_as_handled()


## Escape: close the front-most thing, otherwise drop the tool. Android Back
## (`from_back`) does the same, except that while a street name is being
## typed it cancels that edit (Escape leaves typing to the text field).
func escape(from_back: bool = false) -> void:
	if share_dialog.is_open():
		share_dialog.close()
		return
	if loading_screen.visible: return
	if is_casino_open() and not notice_dialog.is_open():
		casino_overlay.request_leave()
		return
	if notice_dialog.is_open():
		notice_dialog.dismiss()
	elif choice_dialog.is_open():
		choice_dialog.cancel()
	elif new_city_dialog.is_open() and new_city_dialog.terrain_dialog.sources_dialog.visible:
		# Only the credits close; the chooser and its download keep going.
		new_city_dialog.terrain_dialog.sources_dialog.close()
	elif new_city_dialog.is_open():
		if new_city_dialog.terrain_dialog.visible: new_city_dialog.terrain_dialog.close()
		else: new_city_dialog.close()
	elif load_dialog.is_open():
		load_dialog.close()
	elif save_dialog.is_open():
		save_dialog.close()
	elif _help_sources_open():
		(windows.help as HelpWindow).sources_dialog.close()
	elif window_manager.front() != null:
		window_manager.front().call("close")
	elif _drag_active:
		cancel_map_gesture()
	elif query_panel.is_open():
		query_panel.close()
	elif shell.phone_layout and shell.phone_tools_open:
		shell.set_phone_tools_open(false)
	elif is_exploring():
		# The Explore menu toggles, so the key that opened it also closes it.
		if exploration.is_suspended(): exploration.resume()
		else: exploration.pause()
	elif street_names.is_active():
		if not street_names.panel.name_edit.has_focus(): street_names.leave()
		elif from_back: street_names.cancel_edit()
	elif tool != NO_TOOL:
		select_tool(NO_TOOL)
	elif display_layout.fullscreen:
		prefs.set_option(&"fullscreen", false)


func toggle_underground() -> void:
	if street_names.is_active(): return
	if is_exploring(): return
	presentation.set_view_mode(CityPresentationController.ViewMode.SURFACE if presentation.is_underground() else CityPresentationController.ViewMode.UNDERGROUND)


# ── Menus ────────────────────────────────────────────────────────────────

func _on_menu_action(action: StringName, value: Variant) -> void:
	if loading_screen.visible: return
	if action in [&"zoom_in", &"zoom_out", &"zoom", &"rotate", &"recenter", &"underground", &"overlay"] and (is_exploring() or is_input_blocked() or WindowDrag.is_dragging()):
		menu_bar.set_checked(&"zoom", true, city_view_3d.zoom_level())
		menu_bar.set_checked(&"underground", presentation.is_underground())
		menu_bar.set_checked(&"overlay", true, presentation.get_overlay())
		return
	if street_names.is_active() and action in [&"underground",&"overlay",&"explore"]: return
	# Keyboard accelerators reach the menu even while a dialog has the input.
	if action in [&"city_new",&"city_load",&"city_save",&"city_save_as",&"options"] and (is_input_blocked() or WindowDrag.is_dragging()): return
	match action:
		&"street_names": street_names.enter()
		&"explore": explore_switch.request()
		&"city_new": files.request_city_action(&"new")
		&"city_found": run_loading("Founding city…","Preparing your city for play.",session.found_city)
		&"city_load": files.request_city_action(&"load")
		&"city_save": files.save_from_menu()
		&"city_save_as": files.open_save_dialog()
		&"city_share": files.request_city_share()
		&"city_import": files.request_city_action(&"import")
		&"city_quit": files.quit_game()
		&"speed":
			if stage == Stage.EDITING:
				show_message("Found the city to start the clock.")
			else:
				sim.set_speed(int(value))
		&"zoom_in": city_view_3d.zoom_in()
		&"zoom_out": city_view_3d.zoom_out()
		&"zoom": city_view_3d.set_zoom_level(int(value))
		&"rotate": city_view_3d.cycle_rotation()
		&"recenter": city_view_3d.recenter()
		&"underground":
			presentation.set_view_mode(CityPresentationController.ViewMode.UNDERGROUND if bool(value) else CityPresentationController.ViewMode.SURFACE)
		&"overlay":
			presentation.set_overlay(StringName(String(value)))
		&"labels", &"button_labels", &"vehicles", &"minimap", &"disasters_enabled", &"auto_budget":
			prefs.set_option(action, bool(value))
		&"window": window_manager.open(String(value))
		&"disaster": request_disaster(StringName(String(value)))
		&"go_to_emergency": go_to_emergency()
		&"options": window_manager.open("options")
		&"help": window_manager.open("help")
		&"cheats": open_cheat_dialog()
		&"about": open_about()


func open_about() -> void:
	var version := String(ProjectSettings.get_setting("application/config/version", "Development"))
	var body := "Version %s\n\n" % version
	body += "Developed by Sierra Burkhart (sierra760)\n© 2026 Bristlecone Artists LLC\n\n"
	body += "A desert city builder. Lay out zones, wire them up, keep the water flowing and the books balanced.\n\n"
	body += "Project-authored code: GNU General Public License, version 3 or later (GPL-3.0-or-later). Free software; no warranty.\n\n"
	body += "Art, models and included cities: Creative Commons Attribution-NonCommercial-ShareAlike 4.0 (CC-BY-NC-SA-4.0).\n\n"
	body += "Fonts and third-party components retain their separate terms and notices. Read License for the full code license."
	notices.queue("About Sin City - Desert Dreams", body,
		[["Done", &"ok"], ["Read License", &"license"]], _on_about_closed)


func _on_about_closed(choice: StringName) -> void:
	if choice == &"license":
		window_manager.open("license")


## Secret codes are entered explicitly so text never doubles as map/actor input.
## The notice queue handles pausing, touch focus, cancelling and restoring speed.
func open_cheat_dialog() -> void:
	if stage != Stage.PLAY or is_input_blocked() or WindowDrag.is_dragging(): return
	var lines := preload("res://scripts/content/cheat_lines.gd")
	notices.queue("Secret Municipal Paperwork", lines.PROMPT,
		[["Submit", &"submit"], ["Never mind", &"cancel"]], _on_cheat_submitted, true)


func _on_cheat_submitted(choice: StringName) -> void:
	if choice != &"submit" or stage != Stage.PLAY: return
	var result := sim.redeem_cheat(notice_dialog.prompt_text())
	status_bar.refresh(sim)
	refresh_toolbar()
	window_manager.refresh_open()
	_query_refresh_pending = true
	notices.show(String(result["title"]), String(result["body"]))


## Reveal the current emergency in Build, preserving the clock and selected tool.
func go_to_emergency() -> void:
	if stage != Stage.PLAY or is_input_blocked(): return
	var disasters := sim.get_system(&"disasters") as DisasterSystem
	if disasters == null: return
	var point := disasters.emergency_target()
	if point.x < 0:
		refresh_toolbar()
		return
	if is_exploring(): explore_switch.leave()
	cancel_map_gesture()
	presentation.set_view_mode(CityPresentationController.ViewMode.SURFACE)
	presentation.set_overlay(&"")
	city_view_3d.set_center_cell(point)


func request_disaster(kind: StringName) -> bool:
	if stage != Stage.PLAY:
		return false
	var ok := sim.request_disaster(kind)
	if not ok:
		var message := "%s can't start right now." % DisasterParams.display_name(kind)
		var disasters := sim.get_system(&"disasters")
		if disasters != null and disasters.has_method("unavailable_reason"):
			var reason := String(disasters.call("unavailable_reason", sim.city, kind))
			if not reason.is_empty(): message += " " + reason
		show_message(message)
	return ok


# ── Gaming resorts ───────────────────────────────────────────────────────

## Sit down at a gaming-resort table: pauses the city behind the table and
## suspends Explore until the player leaves. Refused (false) before founding,
## while another dialog holds input, or for an unknown resort or game; a
## treasury below the table minimum is refused with a notice. `rng` seeds
## the table (tests); null draws a fresh seed.
func open_casino_table(resort: StringName, game: StringName, rng: CasinoRng = null) -> bool:
	if stage != Stage.PLAY or sim.city == null or is_input_blocked() or WindowDrag.is_dragging():
		return false
	if not ResortThemes.has(resort):
		notices.show("Table Closed", CasinoLines.UNKNOWN_RESORT)
		return false
	if not ResortThemes.offers(resort, game):
		notices.show(ResortThemes.resort_name(resort), CasinoLines.UNKNOWN_GAME)
		return false
	var check := sim.casino().can_play(resort, sim.city.funds)
	if not bool(check["ok"]):
		notices.show(ResortThemes.resort_name(resort), String(check["reason"]))
		return false
	if casino_overlay == null:
		casino_overlay = CasinoTableOverlay.new()
		modal_layer.add_child(casino_overlay)
		casino_overlay.bind_layout(display_layout)
		casino_overlay.closed.connect(_on_casino_closed)
		casino_overlay.round_settled.connect(func(_resort: StringName, _game: StringName, _outcome: Dictionary) -> void: _refresh_after_casino())
		if audio != null: audio.bind_casino(casino_overlay)
	push_modal()
	modal_layer.move_child(casino_overlay, modal_layer.get_child_count() - 1)
	casino_overlay.open(sim, resort, game, rng)
	return true


## True while a gaming-resort table is open.
func is_casino_open() -> bool:
	return is_instance_valid(casino_overlay) and casino_overlay.is_open()


## Close an open table at once (the city is closing or being replaced);
## a round in play has its stake refunded.
func force_close_casino() -> void:
	if is_casino_open(): casino_overlay.force_close()


func _on_casino_closed() -> void:
	pop_modal()
	if is_instance_valid(exploration): exploration.release_casino_table_view()
	# Resume Explore now, when nothing else holds input, so the HUD comes
	# back without flashing its paused panel until the next physics tick.
	# The controller's own check keeps a manual pause and an open window.
	if is_exploring() and exploration.is_suspended(): exploration.resume_if_unblocked()
	if _casino_hid_hud:
		_casino_hid_hud = false
		if is_instance_valid(explore_hud): explore_hud.visible = is_exploring()
	_refresh_after_casino()
	casino_closed.emit()


## A seat on a resort floor in Explore: open its table, hold the seated
## camera view and hide the Explore HUD (its paused panel) behind the table.
## Explore suspends while the table holds input and resumes after it closes.
func _on_casino_table_requested(resort: StringName, game: StringName, table: Dictionary) -> void:
	if not open_casino_table(resort, game):
		exploration.release_casino_table_view()
		return
	exploration.hold_casino_table_view(table)
	if is_instance_valid(explore_hud) and explore_hud.visible:
		explore_hud.visible = false
		_casino_hid_hud = true


func _refresh_after_casino() -> void:
	if sim.city == null: return
	status_bar.refresh(sim)
	refresh_toolbar()
	window_manager.refresh_open()
	_query_refresh_pending = true


# ── Modal state ──────────────────────────────────────────────────────────

## True while Help's full-screen terrain sources view is open. Ordinary Help
## stays nonmodal; only this view blocks input and holds the simulation.
func _help_sources_open() -> bool:
	return windows.has("help") and is_instance_valid(windows.help) and (windows.help as HelpWindow).sources_dialog.is_visible_in_tree()


## Hold the simulation while Help's terrain sources view is open.
func sync_help_sources_hold() -> void:
	if _help_sources_open():
		if _sim_process_holds.has(&"help_terrain_sources"): return
		interrupt_map_input()
		acquire_sim_process_hold(&"help_terrain_sources")
	else:
		release_sim_process_hold(&"help_terrain_sources")


func is_input_blocked() -> bool:
	return is_casino_open() or _help_sources_open() or _application_suspended or loading_screen.visible or not in_game or modal_depth > 0 or title_screen.visible or share_dialog.is_open() or notice_dialog.is_open() \
		or choice_dialog.is_open() or new_city_dialog.is_open() or load_dialog.is_open() or save_dialog.is_open() \
		or files.picker_modal or (files.import_dialog != null and files.import_dialog.visible)


## Contact ownership is determined from geometry, not the single emulated
## mouse pointer: every touch beginning on chrome stays with that GUI owner.
func touch_ui_owned(point: Vector2) -> bool:
	if is_input_blocked() or display_layout.blocks_city_touch(): return true
	if not display_layout.logical_rect().has_point(point): return true
	for control: Control in [menu_bar,status_bar,toolbar,query_panel]:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(point): return true
	if mini_map.visible and mini_map.frame_rect().has_point(point): return true
	if street_names != null and street_names.is_active() and street_names.panel.get_global_rect().has_point(point): return true
	for control: Control in window_manager.open_windows:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(point): return true
	return false


## Open a modal: interrupts map input and pauses the city on the first one.
func push_modal() -> void:
	if shell.phone_layout: shell.set_phone_tools_open(false)
	interrupt_map_input()
	if modal_depth == 0 and in_game:
		speed_before_modal = sim.speed
		sim.set_speed(GameClock.Speed.PAUSED)
	modal_depth += 1


## Close a modal; the last one restores `speed_before_modal`.
func pop_modal() -> void:
	if modal_depth <= 0:
		return
	modal_depth -= 1
	if modal_depth == 0 and in_game:
		sim.set_speed(speed_before_modal)


func _on_speed_changed(speed: int) -> void:
	if _application_suspended and speed != GameClock.Speed.PAUSED:
		sim.set_speed(GameClock.Speed.PAUSED)
		return
	status_bar.set_speed(speed)
	menu_bar.set_checked(&"speed", true, speed)
	# Let the display sleep while the city is paused; keep it awake while time runs.
	sync_keep_screen_on(speed)
	if speed != GameClock.Speed.PAUSED:
		_last_running_speed = speed
	if modal_depth > 0 and speed != GameClock.Speed.PAUSED:
		speed_before_modal = speed


## Named holds that stop simulation processing until every holder releases.
## Speed and modal pauses are handled separately by the clock.
func acquire_sim_process_hold(owner: StringName) -> void:
	if _sim_process_holds.has(owner): return
	if _sim_process_holds.is_empty(): _sim_process_before_holds = sim.is_processing()
	_sim_process_holds[owner] = true
	sim.set_process(false)


func release_sim_process_hold(owner: StringName) -> void:
	if not _sim_process_holds.has(owner): return
	_sim_process_holds.erase(owner)
	if _sim_process_holds.is_empty(): sim.set_process(_sim_process_before_holds)


# ── Time ─────────────────────────────────────────────────────────────────

func _on_day_advanced(_year: int, _month: int, _day: int) -> void:
	# Daily simulation also changes data grids and utility flags without
	# touching geometry. Refresh their cached presentation afterwards.
	city_view_3d.refresh_analytics()
	city_view_3d.feedback.sync_power()
	status_bar.refresh(sim)
	refresh_toolbar()
	_query_refresh_pending = true


func _on_budget_review_due(_year: int) -> void:
	if autosave() != OK:
		notices.show("Automatic Backup Failed", "The automatic backup couldn't be written. Use City → Save As to save your city to another file.")
	present_budget_review()


## Open the January budget review; the city stays paused until it closes.
## With automatic budgeting the review settles at once.
func present_budget_review() -> void:
	if sim.stats.auto_budget:
		sim.finish_budget_review()
		return
	push_modal()
	var w := window_manager.window("budget")
	window_manager.open("budget")
	if not w.is_connected("closed", _finish_budget_review):
		w.connect("closed", _finish_budget_review, CONNECT_ONE_SHOT)


func _finish_budget_review() -> void:
	sim.finish_budget_review()
	pop_modal()
	status_bar.refresh(sim)


func _on_disaster_started(_kind: StringName, center: Vector2i) -> void:
	if center.x >= 0 and in_game and not is_exploring():
		city_view_3d.set_center_cell(center)
	refresh_toolbar()


# ── Input blocking ───────────────────────────────────────────────────────

func is_camera_input_blocked() -> bool:
	return is_input_blocked() or (display_layout != null and display_layout.blocks_city_keyboard())


func is_touch_camera_input_blocked() -> bool:
	return is_input_blocked() or (display_layout != null and display_layout.blocks_city_touch())


func is_explore_input_blocked() -> bool:
	if is_instance_valid(exploration) and exploration.touch_controls_enabled():
		return is_touch_camera_input_blocked()
	return is_camera_input_blocked()


## True while the player is walking, driving or flying in Explore.
func is_exploring() -> bool:
	return is_instance_valid(exploration) and exploration.is_active()


func is_minimap_input_blocked() -> bool:
	return is_exploring() or is_input_blocked()


## Enable Street Names and Explore in a founded city outside Explore;
## Explore also stays off while streets are being named. The clock, reports,
## disasters and secret codes wait for founding, so their items are greyed
## out instead of accepting a choice that cannot apply yet.
func refresh_street_menus() -> void:
	var naming := street_names != null and street_names.is_active()
	var founded := in_game and stage == Stage.PLAY
	menu_bar.set_enabled(&"street_names",founded and not is_exploring())
	menu_bar.set_enabled(&"explore",founded and not is_exploring() and not naming)
	for speed: int in GameClock.Speed.values(): menu_bar.set_enabled(&"speed",founded,speed)
	for window_name: String in GameMenuBar.WINDOW_NAMES: menu_bar.set_enabled(&"window",founded,window_name)
	for kind: StringName in DisasterParams.KINDS: menu_bar.set_enabled(&"disaster",founded,kind)
	menu_bar.set_enabled(&"cheats",founded)


# ── 3D view feedback ─────────────────────────────────────────────────────

func _on_3d_view_changed() -> void:
	presentation.refresh_query_pointer_hover()
	if is_exploring() or city_view_3d.city == null:
		return
	prefs.defer("size_3d", city_view_3d.camera_size)
	prefs.defer("rotation_3d", city_view_3d.quarter_turn)
	prefs.defer("center_3d", city_view_3d.center)
	if city_view_3d.active:
		menu_bar.set_checked(&"zoom", true, city_view_3d.zoom_level())
		mini_map.generate_image()
		sync_3d_cursor()


## The inspector owns selection; transient pointer feedback has its own lifetime.
func sync_query_feedback() -> void:
	if city_view_3d == null or city_view_3d.query_feedback == null: return
	var selected := query_panel.tile if query_panel != null and query_panel.is_open() else Vector2i(-1, -1)
	if is_exploring() or not city_view_3d.active:
		city_view_3d.query_feedback.clear()
		return
	city_view_3d.query_feedback.show_tiles(sim.city,_query_hover,selected,city_view_3d.geometry_revision())


## Show the construction preview and its caption in the 3D view.
func sync_3d_cursor() -> void:
	if city_view_3d == null or cursor_caption_3d == null:
		return
	var preview := presentation.preview
	if is_exploring() or not city_view_3d.active or not preview.is_showing() or is_input_blocked():
		city_view_3d.clear_cursor()
		cursor_caption_3d.hide()
		return
	city_view_3d.show_cells(preview.tiles, preview.ok)
	cursor_caption_3d.text = preview.caption
	cursor_caption_3d.modulate = CursorPreviewState.CAPTION_OK if preview.ok else CursorPreviewState.CAPTION_BLOCKED
	var last: Vector2i = preview.tiles.back()
	var point := city_view_3d.project_cell(last) if sim.city.in_bounds(last.x, last.y) else get_viewport().get_mouse_position()
	var bounds := display_layout.logical_rect()
	var width := minf(520.0, bounds.size.x - 16.0)
	var natural := cursor_caption_3d.get_theme_font("font").get_string_size(preview.caption, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SMALL).x
	cursor_caption_3d.size = Vector2(minf(width, natural + 8.0), 0)
	cursor_caption_3d.size.y = minf(bounds.size.y - 16.0, cursor_caption_3d.get_minimum_size().y)
	var caption_rect := DisplayLayout.clamp_caption_rect(Rect2(point + Vector2(14, 20), cursor_caption_3d.size), bounds)
	cursor_caption_3d.position = caption_rect.position
	cursor_caption_3d.visible = not preview.caption.is_empty()


func _process(delta: float) -> void:
	if loading_screen != null and loading_screen.visible: return
	files.resume_waiting_quit()
	if message_seconds_left > 0.0:
		message_seconds_left = maxf(0.0, message_seconds_left - maxf(delta, 0.0))
		if message_seconds_left == 0.0:
			status_bar.set_message(CitySession.editing_message(sim.city.name if sim.city != null else "") if stage == Stage.EDITING else ("Underground · pipes and subway" if presentation.is_underground() else ""))
	if _query_refresh_pending:
		_query_refresh_pending = false
		if query_panel.is_open(): query_panel.refresh(sim.city, sim)
	prefs.advance(delta)
	if city_view_3d == null or not city_view_3d.active:
		return
	if is_exploring() or is_input_blocked() or (not presentation.has_query_touch() and get_viewport().gui_get_hovered_control() != null):
		_query_hover = Vector2i(-1, -1)
		_query_hover_suppressed = true
		city_view_3d.clear_cursor()
		cursor_caption_3d.hide()
	else:
		if _query_hover_suppressed:
			_query_hover_suppressed = false
			presentation.refresh_query_pointer_hover()
		sync_3d_cursor()
	sync_query_feedback()
	presentation.sync_actors(delta, entity_records.gather(), sim.get_system(&"transport"),
		sim.speed == GameClock.Speed.PAUSED, bool(preferences.get("vehicles", true)))


## Write the preferences to their file.
func save_preferences() -> void:
	ViewPreferences.write(preferences, preferences_path)


func _exit_tree() -> void:
	if get_window().close_requested.is_connected(files.quit_game): get_window().close_requested.disconnect(files.quit_game)
	get_tree().auto_accept_quit = _previous_auto_accept_quit
	explore_switch.dispose()
	prefs.flush()
