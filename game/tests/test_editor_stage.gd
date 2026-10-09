# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A new map opens in the editing stage: terrain tools only, free, the clock
## stopped and the treasury untouched. Founding sets the simulation up with
## the starting funds and prices the same tools; Regenerate rolls new land;
## an unfounded map survives a save and returns to the stage on load.
extends "res://tests/exploration/async_test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
const PARAMS := {"name": "Dry Wash", "seed": 31337, "hills": 45, "water": 35, "trees": 30,
	"coast": "east", "river": true, "difficulty": City.Difficulty.MEDIUM, "founded_year": 1950}
const SAVE_PATH := "user://saves/editor-stage-test.sc2d"

var host: GameHost


func before_each() -> void:
	host = MainScene.instantiate()
	root.add_child(host)


func after_each() -> void:
	host.sim._ctx.systems.clear()
	host.sim.systems.clear()
	root.remove_child(host)
	host.free()
	host = null


## A dry, flat, empty tile at least `margin` tiles from the edge.
static func _flat_tile(city: City, margin: int = 8) -> Vector2i:
	for y in range(margin, City.HEIGHT - margin):
		for x in range(margin, City.WIDTH - margin):
			if city.is_flat(x, y) and not city.is_water(x, y) and city.building_at(x, y) == Buildings.NONE:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _visible_tools(toolbar: Toolbar) -> Array[int]:
	var out: Array[int] = []
	for tool in Tools.all():
		if toolbar.is_shown(tool):
			out.append(tool)
	return out


func test_new_city_lands_in_the_editing_stage() -> void:
	var city := host.start_new_city(PARAMS)
	check_eq(host.stage, GameHost.Stage.EDITING)
	check(host.in_game, "the map chrome is up")
	check(not host.title_screen.visible)
	check(host.toolbar.visible and host.status_bar.visible)
	check_eq(host.sim.city, city, "the simulation is bound to the map")
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "the clock is stopped")
	check_eq(host.sim.clock.day, 0)
	check_eq(city.funds, int(City.STARTING_FUNDS[City.Difficulty.MEDIUM]), "funds untouched by the stage")
	check_eq(host.tool, GameHost.NO_TOOL, "no tool until the player picks one")
	check(host.terrain_editor != null, "terrain editor attached")
	check_eq(host.status_bar.date_label.text, "Shaping the land")
	check_eq(host.status_bar.population_label.text, "Dry Wash")
	check_eq(host.toolbar.stage, Toolbar.Stage.EDITING)
	check(host.toolbar.editing_panel.visible, "Regenerate and Found City are offered")
	check(host.menu_bar.is_enabled(&"city_found"), "the City menu offers Found City")
	check(host.menu_bar.is_shown(&"city_found"), "Found City is listed while shaping")
	var shown := _visible_tools(host.toolbar)
	check_eq(shown.size(), 8, "only the terrain tools show")
	for tool in shown:
		check(Tools.is_terrain_tool(tool), "%s is a terrain tool" % Tools.display_name(tool))
		check((host.toolbar.buttons[tool] as Button).tooltip_text.contains("free"), "%s is free" % Tools.display_name(tool))
	check(not host.toolbar.is_shown(Tools.Kind.ROAD), "construction tools are hidden")
	# Construction and the clock wait for founding.
	host.select_tool(Tools.Kind.ROAD)
	var road := host.handle_drag(Vector2i(40, 40), Vector2i(45, 40))
	check(not bool(road["ok"]), "no roads before founding")
	host.menu_bar.press(&"speed", GameClock.Speed.FAST)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "the menu cannot start the clock")
	check_eq(host.open_window("budget"), null, "game windows wait for founding")
	check(host.open_window("help") != null, "help is always available")
	host.window_manager.close_all()
	check_eq(city.funds, int(City.STARTING_FUNDS[City.Difficulty.MEDIUM]))


func test_raise_through_the_map_path_is_free_and_redraws() -> void:
	var city := host.start_new_city(PARAMS)
	var at := _flat_tile(city)
	check(at.x >= 0, "the map has a flat tile")
	var funds := city.funds
	var before := city.ground_height(at.x, at.y)
	host.select_tool(Tools.Kind.RAISE_LAND)
	check_eq(host.toolbar.active_tool, Tools.Kind.RAISE_LAND)
	var preview := host.construction.preview_drag(at, at)
	check(bool(preview["ok"]), "preview allows the raise")
	check(host.presentation.preview.is_showing(), "cursor shows the footprint")
	check_eq(host.presentation.preview.caption, "free")
	var redraws := host.presentation.preview.redraw_count
	var result := host.handle_drag(at, at)
	check(bool(result["ok"]), "raise applies: %s" % String(result.get("reason", "")))
	check(bool(result["applied"]))
	check_eq(int(result["cost"]), 0, "nothing charged")
	check_eq(city.funds, funds, "funds unchanged")
	check_eq(city.ground_height(at.x, at.y), before + 1, "the tile is one level up")
	check(city.is_flat(at.x, at.y), "a raised flat tile stays flat")
	check_eq(city.terrain_surface.cliff_count(), 0, "neighbours were pulled along")
	var rect: Rect2i = result["rect"]
	check(rect.has_point(at + Vector2i(-1, -1)) and rect.has_point(at + Vector2i(1, 1)), "returned rect covers the ring")
	check_ge(host.presentation.preview.redraw_count, redraws, "renderer was told about the edit")
	# Lower brings it back; level flattens a run; forest plants.
	host.select_tool(Tools.Kind.LOWER_LAND)
	check(bool(host.handle_drag(at, at)["ok"]))
	check_eq(city.ground_height(at.x, at.y), before)
	host.select_tool(Tools.Kind.FOREST)
	var planted := host.handle_drag(at, at + Vector2i(3, 0))
	check(bool(planted["ok"]), planted["reason"])
	check(Buildings.is_tree(city.building_at(at.x + 2, at.y)), "trees planted along the drag")
	check_eq(city.funds, funds, "still free")
	# The tree tool thickens a wooded tile one step per click.
	var wooded := city.building_at(at.x + 1, at.y)
	host.select_tool(Tools.Kind.PLANT_TREE)
	if wooded < Buildings.TREES_7:
		check(bool(host.handle_drag(at + Vector2i(1, 0), at + Vector2i(1, 0))["ok"]))
		check_eq(city.building_at(at.x + 1, at.y), wooded + 1, "one step denser")
	check_eq(city.funds, funds, "still free")
	# Water fills the hollow; clicking water again drains it.
	host.select_tool(Tools.Kind.LOWER_LAND)
	var pit := at + Vector2i(0, 4)
	host.handle_drag(pit, pit)
	host.select_tool(Tools.Kind.PLACE_WATER)
	var pond := host.handle_drag(pit, pit)
	check(bool(pond["ok"]), pond["reason"])
	check(city.is_water(pit.x, pit.y), "the pit holds water")
	var drained := host.handle_drag(pit, pit)
	check(bool(drained["ok"]) and not city.is_water(pit.x, pit.y), "water on water drains")
	check_eq(city.funds, funds)


func test_sea_level_tools_move_the_whole_map() -> void:
	var city := host.start_new_city(PARAMS)
	var level := city.sea_level
	check(level > 0, "generated maps have a sea level")
	var water_before := _water_count(city)
	host.select_tool(Tools.Kind.LEVEL_LAND)
	var up := host.construction.apply_immediate(Tools.Kind.RAISE_SEA)
	check(bool(up["ok"]), up["reason"])
	check_eq(city.sea_level, level + 1)
	check_gt(_water_count(city), water_before, "the sea spread onto low ground")
	var rect: Rect2i = up["rect"]
	check_eq(rect.size, Vector2i(City.WIDTH, City.HEIGHT), "the whole map was redrawn")
	# One press on the button is the whole action; the map tool stays.
	host.toolbar.button_for(Tools.Kind.LOWER_SEA).pressed.emit()
	check_eq(city.sea_level, level)
	check_eq(host.tool, Tools.Kind.LEVEL_LAND, "the sea buttons do not replace the map tool")
	check(host.toolbar.button_for(Tools.Kind.RAISE_SEA).get_parent() != host.toolbar.button_for(Tools.Kind.LEVEL_LAND).get_parent(),
		"the sea buttons sit apart from the map tools")
	check(host.toolbar.is_shown(Tools.Kind.RAISE_SEA), "the sea block shows while shaping the land")
	check_eq(city.funds, int(City.STARTING_FUNDS[City.Difficulty.MEDIUM]), "free")


static func _water_count(city: City) -> int:
	var n := 0
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if city.is_water(x, y):
				n += 1
	return n


func test_founding_sets_up_the_simulation_and_prices_the_tools() -> void:
	var city := host.start_new_city(PARAMS)
	var at := _flat_tile(city)
	host.select_tool(Tools.Kind.RAISE_LAND)
	host.handle_drag(at, at)
	var shaped := city.altitude.data.duplicate()
	check(host.found_city(), "founding succeeds from the editing stage")
	check_eq(host.stage, GameHost.Stage.PLAY)
	check_eq(host.sim.city, city, "the same map continues")
	check_eq(city.altitude.data, shaped, "the shaped land is kept")
	check_eq(city.founded_year, 1950)
	check_eq(host.sim.clock.founded_year, 1950)
	check_eq(host.sim.clock.day, 0)
	check_eq(city.funds, int(City.STARTING_FUNDS[City.Difficulty.MEDIUM]), "funds equal the difficulty's start")
	check_eq(host.sim.speed, GameClock.Speed.SLOW, "the clock runs")
	check_eq(host.toolbar.stage, Toolbar.Stage.PLAY)
	check(not host.toolbar.editing_panel.visible)
	check(host.toolbar.is_shown(Tools.Kind.ROAD), "construction tools are back")
	for sea: int in [Tools.Kind.RAISE_SEA, Tools.Kind.LOWER_SEA]:
		check(not host.toolbar.is_shown(sea), "%s is gone once the city is founded" % Tools.display_name(sea))
	check(host.toolbar.is_shown(Tools.Kind.LEVEL_LAND), "the land tools stay after founding")
	var sea_before := city.sea_level
	var funds_before := city.funds
	check(not bool(host.construction.apply_immediate(Tools.Kind.RAISE_SEA)["ok"]), "the sea cannot move after founding")
	check_eq(city.sea_level, sea_before)
	check_eq(city.funds, funds_before)
	check(not host.menu_bar.is_enabled(&"city_found"), "Found City is spent")
	check(not host.menu_bar.is_shown(&"city_found"), "Found City leaves the City menu after founding")
	check_eq(host.tool, Tools.Kind.QUERY)
	check(host.terrain_editor == null)
	check(host.status_bar.date_label.text.contains("1950"))
	check(host.sim.get_system(&"power") != null, "systems are set up")
	check(not host.found_city(), "founding twice does nothing")
	# The same raise now costs the ordinary price.
	var funds := city.funds
	host.select_tool(Tools.Kind.RAISE_LAND)
	check((host.toolbar.buttons[Tools.Kind.RAISE_LAND] as Button).tooltip_text.contains("$25"))
	var result := host.handle_drag(at, at)
	check(bool(result["ok"]), result["reason"])
	check_eq(int(result["cost"]), 25)
	check_eq(city.funds, funds - 25, "raising land is paid for after founding")
	host.sim.advance_days(3)
	check_eq(host.sim.clock.day, 3, "days advance after founding")


func test_founding_from_the_menu_and_the_toolbar_button() -> void:
	host.start_new_city(PARAMS)
	host.menu_bar.press(&"city_found")
	while host.loading_screen.visible: await process_frame
	check_eq(host.stage, GameHost.Stage.PLAY, "the City menu founds the city")
	host.start_new_city(PARAMS)
	check_eq(host.stage, GameHost.Stage.EDITING, "a new map re-enters the stage")
	var city_menu: PopupMenu = host.menu_bar.get_node("City")
	check_eq(city_menu.get_item_text(1), "Found City", "Found City returns to its place under New City")
	check(not city_menu.is_item_disabled(1), "the restored Found City is usable")
	check_eq(city_menu.get_item_text(2), "Load City…", "the items after it keep their order")
	check(city_menu.get_item_shortcut(2) != null, "the items after it keep their shortcuts")
	host.toolbar.found_button.pressed.emit()
	while host.loading_screen.visible: await process_frame
	check_eq(host.stage, GameHost.Stage.PLAY, "the toolbar button founds the city")


func test_regenerate_changes_the_terrain_and_keeps_the_settings() -> void:
	var city := host.start_new_city(PARAMS)
	var terrain := city.terrain.data.duplicate()
	var fresh := host.regenerate(4242)
	check(fresh != null and fresh != city, "a new city object")
	check_eq(host.stage, GameHost.Stage.EDITING)
	check_eq(host.sim.city, fresh)
	check_eq(host.presentation.city, fresh, "the renderer shows the new land")
	check_ne(fresh.terrain.data, terrain, "the terrain changed")
	check_eq(fresh.name, "Dry Wash", "the name is kept")
	check_eq(fresh.difficulty, City.Difficulty.MEDIUM)
	check_eq(fresh.founded_year, 1950)
	check_eq(int(host.editing_params["hills"]), 45, "sliders are kept")
	check_eq(int(host.editing_params["seed"]), 4242)
	var same := TerrainGenerator.new().generate(host.editing_params, SimRng.new(4242))
	check_eq(same.terrain.data, fresh.terrain.data, "the new seed reproduces the map")
	var again := host.regenerate()
	check_ne(again.terrain.data, fresh.terrain.data, "a random seed rolls different land")
	check(host.found_city(), "the regenerated map can be founded")
	check_eq(host.regenerate(), null, "no regenerate after founding")


func test_unfounded_save_round_trip_returns_to_the_stage() -> void:
	var city := host.start_new_city(PARAMS)
	var at := _flat_tile(city)
	host.select_tool(Tools.Kind.RAISE_LAND)
	host.handle_drag(at, at)
	host.handle_drag(at, at)
	var shaped := city.altitude.data.duplicate()
	var vertices: PackedByteArray = (city.terrain_surface as TerrainSurface).vertices.duplicate()
	check_eq(host.files.save_city_as("editor-stage-test"), SAVE_PATH, "saving is allowed while shaping")
	var header := SaveFormat.read_header(SAVE_PATH)
	check_eq(header["stage"], SaveFormat.STAGE_EDITING, "the save is marked unfounded")
	var raw := SaveFormat.load(SAVE_PATH)
	check_eq(raw["stage"], SaveFormat.STAGE_EDITING)
	check_eq(int((raw["generator"] as Dictionary).get("hills", 0)), 45, "generator settings travel with the map")
	check_eq(raw["version"], SaveFormat.VERSION, "the format version is unchanged")
	host.found_city()
	host.sim.advance_days(5)
	check(host.load_city(SAVE_PATH), "the unfounded map loads")
	check_eq(host.stage, GameHost.Stage.EDITING, "back in the editing stage")
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	check_eq(host.sim.city.altitude.data, shaped, "the shaped land came back")
	check_eq((host.sim.city.terrain_surface as TerrainSurface).vertices, vertices, "the lattice came back")
	check_eq(host.sim.city.funds, int(City.STARTING_FUNDS[City.Difficulty.MEDIUM]))
	check_eq(host.save_path, SAVE_PATH)
	check(host.terrain_editor != null)
	# Editing continues on the loaded lattice and founding still works.
	host.select_tool(Tools.Kind.LOWER_LAND)
	check(bool(host.handle_drag(at, at)["ok"]), "edits continue after loading")
	check_eq(host.sim.city.terrain_surface.cliff_count(), 0)
	check(host.found_city())
	check_eq(host.sim.clock.day, 0)
	var listed := SaveFormat.list_saves()
	var found := false
	for entry in listed:
		if String(entry["path"]) == SAVE_PATH:
			found = true
	check(found, "the save is listed")
	host.files.open_load_dialog()
	var row := -1
	for i in host.load_dialog.item_list.item_count:
		if host.load_dialog.item_list.get_item_text(i).begins_with("Dry Wash"):
			row = i
	check(row >= 0 and host.load_dialog.item_list.get_item_text(row).contains("unfounded"), "the load dialog says the map is unfounded")
	host.load_dialog.close()
	DirAccess.remove_absolute(SAVE_PATH)


func test_loading_and_importing_skip_the_stage() -> void:
	_play_and_save()
	host.start_new_city(PARAMS)
	check_eq(host.stage, GameHost.Stage.EDITING)
	check(host.load_city(SAVE_PATH))
	check_eq(host.stage, GameHost.Stage.PLAY, "a founded save skips the stage")
	check_eq(host.sim.clock.day, 7)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "a loaded city opens paused")
	var pause := InputEventKey.new()
	pause.keycode = KEY_P
	pause.physical_keycode = KEY_P
	pause.pressed = true
	host._unhandled_key_input(pause)
	check_eq(host.sim.speed, GameClock.Speed.SLOW, "P resumes the saved speed")
	DirAccess.remove_absolute(SAVE_PATH)


func _play_and_save() -> void:
	host.start_new_city(PARAMS)
	host.found_city()
	host.sim.advance_days(7)
	host.files.save_city_as("editor-stage-test")


func test_escape_drops_the_tool_and_modals_keep_the_clock_stopped() -> void:
	host.start_new_city(PARAMS)
	host.select_tool(Tools.Kind.LEVEL_LAND)
	host.escape()
	check_eq(host.tool, GameHost.NO_TOOL)
	host.files.open_save_dialog()
	check(host.is_input_blocked())
	host.save_dialog.close()
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "closing a dialog does not start the clock")
	check(not host.is_input_blocked(), "the camera works again")
