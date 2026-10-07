# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Getting a city onto the screen: generating, founding, regenerating,
## loading and importing, and binding the city to the simulation, the views
## and the shell.
##
## A new map first enters the editing stage: the land is shown with only the
## terrain tools, all free, and nothing runs until the player founds the city.
## The simulation is bound to the map during that stage (so the shell, the
## renderer and saving see one city) but held: its speed is pinned to Paused,
## the host refuses to start the clock, and founding sets it up again on the
## finished land with fresh stats, the starting funds and day zero.
class_name CitySession
extends RefCounted

## Imported and included cities open paused; tell the player how to start.
const PAUSED_HINT := "Paused — choose a speed (Speed menu or P) to start."

var _host: GameHost
var _has_bound_camera := false


func _init(host: GameHost) -> void:
	_host = host


## Generate a city from `params` (see `TerrainGenerator`) and show it in
## the editing stage. A pre-generated `prebuilt` city (from the dialog's
## preview) is used as is. Play starts with `found_city`.
func start_new_city(params: Dictionary, prebuilt: City = null) -> City:
	if params.get("source") == "real_world":
		if prebuilt == null:
			return null
		var imported := restore_imported_terrain(params, prebuilt)
		if not imported.ok:
			return null
		prebuilt.mayor = _mayor_credit()
		var imported_settings := params.duplicate(true)
		imported_settings["seed"] = imported.tree_seed
		imported_settings["name"] = prebuilt.name
		begin_editing(prebuilt, imported_settings)
		_host.save_path = ""
		_host.files.mark_generated()
		return prebuilt
	var seed_value: int = int(params.get("seed", randi()))
	var city := prebuilt
	if city == null:
		city = TerrainGenerator.new().generate(params, SimRng.new(seed_value))
	city.mayor = _mayor_credit()
	var settings := params.duplicate()
	settings["seed"] = seed_value
	settings["name"] = city.name
	begin_editing(city, settings)
	_host.save_path = ""
	_host.files.mark_generated()
	return city


## Show a map in the editing stage: terrain tools only, free, clock stopped.
func begin_editing(city: City, settings: Dictionary) -> void:
	if settings.get("source") == "real_world":
		settings = settings.duplicate(true)
		var imported := restore_imported_terrain(settings, city)
		if imported.ok:
			settings["seed"] = imported.tree_seed
		# Optional origin failure cannot damage the loaded terrain or baseline.
		city.terrain_origin = RealWorldManifest.sanitize_origin(settings.get("terrain_origin"))
		settings["terrain_origin"] = city.terrain_origin.duplicate(true)
	var had_surface := city.terrain_surface != null
	begin_city(city, {}, _simulation_seed(settings), null)
	var host := _host
	host.stage = GameHost.Stage.EDITING
	host.refresh_street_menus()
	host.editing_params = settings
	host.terrain_editor = TerrainEditor.new(city)
	if not had_surface:
		host.city_view_3d.queue_refresh()
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.speed_before_modal = GameClock.Speed.PAUSED
	if host.presentation.is_underground():
		host.presentation.set_view_mode(CityPresentationController.ViewMode.SURFACE)
	host.toolbar.set_stage(Toolbar.Stage.EDITING)
	host.shell.update_phone_tools()
	host.refresh_toolbar()
	host.menu_bar.set_shown(&"city_found", true)
	host.select_tool(GameHost.NO_TOOL)
	host.status_bar.show_editing(city.name)
	host.status_bar.set_message("Shape the land, then found %s." % city.name)


## Found the city on the shaped land: fix the founding year and difficulty
## from the settings, open the treasury at the difficulty's starting funds,
## set the simulation up on day zero and start the clock. Returns false
## outside the editing stage.
func found_city() -> bool:
	var sim := _host.sim
	if _host.stage != GameHost.Stage.EDITING or sim.city == null:
		return false
	var city := sim.city
	var settings := _host.editing_params
	if settings.has("founded_year"):
		city.founded_year = int(settings["founded_year"])
	if settings.has("difficulty"):
		city.difficulty = clampi(int(settings["difficulty"]), City.Difficulty.EASY, City.Difficulty.HARD)
	city.day = 0
	city.funds = int(City.STARTING_FUNDS[city.difficulty])
	var speed := clampi(int(settings.get("speed", GameClock.Speed.SLOW)), GameClock.Speed.SLOW, GameClock.Speed.FASTEST)
	# Fresh stats for day zero, keeping the Disasters and Auto budget choices
	# the player made while shaping the land. Neither draws a random number.
	var stats := CityStats.new()
	var options := _city_options()
	if not options.is_empty():
		stats.disasters_enabled = bool(options["disasters_enabled"])
		stats.auto_budget = bool(options["auto_budget"])
	begin_city(city, {}, _simulation_seed(settings), stats)
	sim.set_speed(speed)
	_host.speed_before_modal = sim.speed
	_host.show_message("Welcome to %s, founded %d." % [city.name, city.founded_year])
	return true


## Roll a fresh map with the same settings and a new seed (or the one
## given). Only in the editing stage; returns the new city or null.
func regenerate(seed_value: int = -1) -> City:
	if _host.stage != GameHost.Stage.EDITING:
		return null
	var current := _host.sim.city
	var editing_params := _host.editing_params
	var options := _city_options()
	if editing_params.get("source") == "real_world":
		var imported := restore_imported_terrain(editing_params, current)
		if not imported.ok:
			_host.toolbar.set_imported_terrain_reset(false, imported.error)
			_host.show_message(imported.error)
			return null
		var city: City = imported.city
		# Reset restores terrain only; keep the current name, dates and mayor.
		city.name = current.name
		city.difficulty = current.difficulty
		city.founded_year = current.founded_year
		city.mayor = current.mayor
		city.terrain_origin = current.terrain_origin
		var settings := editing_params.duplicate(true)
		settings["seed"] = imported.tree_seed
		settings["name"] = city.name
		settings["difficulty"] = city.difficulty
		settings["founded_year"] = city.founded_year
		settings["terrain_origin"] = city.terrain_origin.duplicate(true)
		begin_editing(city, settings)
		_restore_city_options(options)
		_host.files.mark_generated()
		_host.show_message("Imported terrain restored for %s." % city.name)
		return city
	if seed_value < 0:
		seed_value = randi() % 1000000000
	var settings := editing_params.duplicate()
	settings["seed"] = seed_value
	var city := TerrainGenerator.new().generate(settings, SimRng.new(seed_value))
	city.mayor = current.mayor
	begin_editing(city, settings)
	_restore_city_options(options)
	_host.files.mark_generated()
	_host.show_message("New land for %s." % city.name)
	return city


## The Disasters and Auto budget choices, kept while the land is reshaped.
func _city_options() -> Dictionary:
	var stats := _host.sim.stats
	if stats == null: return {}
	return {"disasters_enabled": stats.disasters_enabled, "auto_budget": stats.auto_budget}


func _restore_city_options(options: Dictionary) -> void:
	if options.is_empty() or _host.sim.stats == null: return
	_host.sim.stats.disasters_enabled = bool(options["disasters_enabled"])
	_host.sim.stats.auto_budget = bool(options["auto_budget"])
	_host.menu_bar.set_checked(&"disasters_enabled", _host.sim.stats.disasters_enabled)
	_host.menu_bar.set_checked(&"auto_budget", _host.sim.stats.auto_budget)


## Verify the imported-terrain baseline stored in `settings` and rebuild a city
## from it, before any city, settings or random state changes. The result's
## tree seed comes from the binary baseline, not the JSON settings number.
static func restore_imported_terrain(settings: Dictionary, city: City) -> Dictionary:
	var invalid := {"ok": false, "error": "Reset imported terrain is unavailable: the saved baseline is damaged."}
	var version: Variant = settings.get("baseline_version")
	if typeof(version) not in [TYPE_INT, TYPE_FLOAT] or version != 1:
		return invalid
	var encoded: Variant = settings.get("baseline_base64")
	var digest: Variant = settings.get("baseline_sha256")
	if not encoded is String or encoded.length() != ((RealWorldManifest.BASELINE_SIZE + 2) / 3) * 4 or not digest is String or digest.length() != 64:
		return invalid
	var body := Marshalls.base64_to_raw(encoded)
	if body.size() != RealWorldManifest.BASELINE_SIZE or RealWorldManifest.sha256(body).hex_encode() != digest:
		return invalid
	var metadata := {"name": city.name, "difficulty": city.difficulty, "founded_year": city.founded_year}
	var restored := RealWorldManifest.restore_baseline(body, metadata, settings.get("terrain_origin", {}))
	return restored if restored.ok else invalid


## Load a native save. Returns false (and shows why) when the file is bad.
## An unfounded map returns to the editing stage.
func load_city(path: String) -> bool:
	var result := SaveFormat.load(path)
	var topology: StreetTopology = result.get("topology", null)
	if not bool(result["ok"]):
		_host.notices.show("Cannot Load", "%s couldn't be opened. %s" % [path.get_file(), String(result["error"])])
		return false
	var manual_path := "" if CityFileFlow.is_managed_recovery_path(path) else path
	var city: City = result["city"]
	if String(result["stage"]) == SaveFormat.STAGE_EDITING:
		var settings: Dictionary = result["generator"]
		settings["name"] = city.name
		begin_editing(city, settings)
		_host.save_path = manual_path
		_host.files.mark_saved()
		_host.show_message("Loaded the unfounded map %s." % city.name)
		return true
	var snapshot: Dictionary = result["snapshot"]
	begin_city(city, snapshot, -1, null, topology)
	var sim := _host.sim
	_host.save_path = manual_path
	_host.files.mark_saved()
	_host.speed_before_modal = sim.speed
	_host.show_message("Loaded %s." % city.name)
	if sim.budget_review_pending:
		# Saved during the January review: reopen it, or time never resumes.
		_host.present_budget_review()
	return true


## Open an included city: a fully imported native save shipped with the game.
## Like a fresh import it is credited to the player, opens paused and needs a
## new personal save; the packaged file is never a save destination.
func open_included_city(path: String) -> bool:
	if not load_city(path):
		return false
	var sim := _host.sim
	_host.save_path = ""
	sim.city.mayor = _mayor_credit()
	_host.files.forget_saved()
	var resume_speed := sim.speed if sim.speed != GameClock.Speed.PAUSED else GameClock.Speed.SLOW
	if _host.modal_depth > 0:
		# A saved January review is open; it already holds the city paused.
		_host.speed_before_modal = GameClock.Speed.PAUSED
	else:
		sim.set_speed(GameClock.Speed.PAUSED)
		_host.speed_before_modal = resume_speed
	_host.show_message("Opened %s. %s" % [sim.city.name, PAUSED_HINT])
	return true


## Import a classic `.sc2` city; its tax rates go into the stats.
func import_city(path: String) -> bool:
	var result := Sc2Import.load(path)
	if not bool(result["ok"]):
		_host.notices.show("Cannot Import", "%s couldn't be imported. %s" % [path.get_file(), String(result["error"])])
		return false
	var city: City = result["city"]
	city.mayor = _mayor_credit()
	var stats := CityStats.new()
	var taxes: Dictionary = result.get("tax_rates", {})
	stats.tax_residential = int(taxes.get("residential", stats.tax_residential))
	stats.tax_commercial = int(taxes.get("commercial", stats.tax_commercial))
	stats.tax_industrial = int(taxes.get("industrial", stats.tax_industrial))
	begin_city(city, {}, -1, stats)
	_host.save_path = ""
	_host.sim.set_speed(GameClock.Speed.PAUSED)
	_host.speed_before_modal = GameClock.Speed.SLOW
	var warnings: Array = result.get("warnings", [])
	# Import details stay out of the status line; say only that defaults filled gaps.
	_host.show_message("Imported %s. %s" % [city.name, PAUSED_HINT] if warnings.is_empty() else "Imported %s. Some city details were missing and use defaults. %s" % [city.name, PAUSED_HINT])
	return true


## Bind `city` to the simulation (restoring `snapshot` when given), the
## builder, street names, the views and the shell, and enter play. Anything
## still open from the previous city is closed first.
func begin_city(city: City, snapshot: Dictionary, seed_value: int, stats: CityStats, topology: StreetTopology = null) -> void:
	var host := _host
	var sim := host.sim
	host.street_names.leave()
	host.files.reset()
	host.message_seconds_left = 0.0
	host.explore_switch.dispose()
	host.cancel_map_gesture()
	host.window_manager.close_all()
	host.query_panel.close()
	host.notices.clear_pending()
	host.notice_dialog.dismiss()
	host.choice_dialog.cancel()
	sim.set_speed(GameClock.Speed.PAUSED)
	sim.setup(city, seed_value, stats, snapshot)
	if not snapshot.is_empty():
		sim.restore(snapshot)
	host.builder = Builder.new(city, sim.stats, sim)
	if topology != null: host.street_topology.adopt(topology, city)
	else: host.street_topology.rebuild(city)
	host.street_naming_service.set_station_allocator(StationNameResolver.reconcile)
	host.street_naming_service.bind_city(city,host.street_topology)
	var view := host.city_view_3d
	var saved_view := host.preferences.duplicate()
	host.presentation.bind_city(city)
	view.bind_street_names(host.street_topology,host.street_naming_service)
	host.mini_map.bind(city, view)
	if not _has_bound_camera:
		var focus: Vector3 = saved_view.get("center_3d", Vector3(64, 0, 64))
		var cell := Vector2i(clampi(int(focus.x), 0, City.WIDTH - 1), clampi(int(focus.z), 0, City.HEIGHT - 1))
		focus.y = CityGeometry3D.surface_height(city, cell)
		view.set_camera_state(focus, int(saved_view.get("rotation_3d", 0)), float(saved_view.get("size_3d", 72.0)))
		_has_bound_camera = true
	host.mini_map.generate_image()
	host.window_manager.bind_all(sim)
	host.in_game = true
	host.stage = GameHost.Stage.PLAY
	host.terrain_editor = null
	host.editing_params = {}
	host.toolbar.set_stage(Toolbar.Stage.PLAY)
	host.menu_bar.set_shown(&"city_found", false)
	host.title_screen.close()
	host.shell.set_chrome_visible(true)
	host.select_tool(Tools.Kind.QUERY)
	host.status_bar.refresh(sim)
	host.refresh_toolbar()
	host.menu_bar.set_checked(&"speed", true, sim.speed)
	host.menu_bar.set_checked(&"disasters_enabled", sim.stats.disasters_enabled)
	host.menu_bar.set_checked(&"auto_budget", sim.stats.auto_budget)
	host.menu_bar.set_checked(&"underground", host.presentation.is_underground())
	view.set_active(true)


## A negative seed asks the simulation for a random one, so an imported
## terrain's 64-bit tree seed is masked to stay non-negative.
static func _simulation_seed(settings: Dictionary) -> int:
	var seed_value := int(settings.get("seed", -1))
	if settings.get("source") == "real_world":
		return seed_value & 0x7fffffffffffffff
	return seed_value


## The player's mayor name as credited on a new or imported city.
func _mayor_credit() -> String:
	return ViewPreferences.mayor_credit(_host.preferences.get("mayor_name", ""))
