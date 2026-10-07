# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The host boots headless, starts a city, builds through the toolbar's
## tool, keeps the status bar current, shows notices, reviews the budget
## and round-trips a save.
extends "res://tests/test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
const PARAMS := {"name": "Testbed", "seed": 4242, "hills": 15, "water": 20, "trees": 10,
	"coast": "none", "river": false, "difficulty": City.Difficulty.EASY, "founded_year": 1950}

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


## Start a city and found it at once: the map goes straight into play.
func _play(params: Dictionary) -> City:
	var city := host.start_new_city(params)
	host.found_city()
	return city


## A run of `length` flat, dry, empty tiles at one height, going east.
static func _flat_run(city: City, length: int) -> Vector2i:
	for y in range(16, City.HEIGHT - 16):
		for x in range(16, City.WIDTH - 16 - length):
			var h := city.ground_height(x, y)
			var ok := true
			for i in length:
				if not city.is_flat(x + i, y) or city.is_water(x + i, y) \
						or city.building_at(x + i, y) != Buildings.NONE or city.ground_height(x + i, y) != h:
					ok = false
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_boots_to_the_title_screen() -> void:
	check(host.title_screen.visible, "title screen shown")
	check(not host.in_game)
	check(not host.toolbar.visible, "toolbar hidden before a city exists")
	check(host.is_input_blocked(), "map input blocked on the title screen")
	check_eq(host.menu_bar.menu_titles(), ["City", "Speed", "View", "Reports", "Disasters", "Help"] as Array[String])


func test_new_city_road_drag_changes_the_city_and_charges() -> void:
	var city := _play(PARAMS)
	check(host.in_game)
	check(not host.title_screen.visible)
	check(host.toolbar.visible and host.status_bar.visible)
	check_eq(city.name, "Testbed")
	check_eq(host.sim.city, city)
	check_eq(host.presentation.city, city)
	check(host.builder != null)
	check_eq(host.tool, Tools.Kind.QUERY)
	check_eq(host.sim.speed, GameClock.Speed.SLOW)
	var start := _flat_run(city, 8)
	check(start.x >= 0, "the map has a flat run")
	var funds := city.funds
	host.select_tool(Tools.Kind.ROAD)
	check_eq(host.tool, Tools.Kind.ROAD)
	check_eq(host.toolbar.active_tool, Tools.Kind.ROAD)
	check(host.status_bar.tool_label.text.contains("Road"))
	var preview := host.construction.preview_drag(start, start + Vector2i(7, 0))
	check(bool(preview["ok"]), "preview is legal")
	check(host.presentation.preview.is_showing(), "cursor shows the footprint")
	var result := host.handle_drag(start, start + Vector2i(7, 0))
	check(bool(result["ok"]), "road applies: %s" % String(result.get("reason", "")))
	check(Buildings.is_road_like(city.building_at(start.x + 3, start.y)), "road tile placed")
	check_eq(city.funds, funds - 8 * Tools.cost(Tools.Kind.ROAD), "funds dropped by the road price")
	check(host.status_bar.funds_label.text.contains(UIFactory.commafy(city.funds)), "status bar shows new funds")
	var refused := host.handle_drag(Vector2i(-5, -5), Vector2i(-5, -5))
	check(not bool(refused["ok"]), "off-map drag is refused")


func test_status_bar_follows_the_calendar() -> void:
	_play(PARAMS)
	var before := host.status_bar.date_label.text
	check(before.contains("1950"))
	host.sim.advance_days(30)
	check_ne(host.status_bar.date_label.text, before, "date text updated after a month")
	check(host.status_bar.date_label.text.begins_with("February"))
	check_eq(host.status_bar.speed_label.text, "Slow")


func test_notice_opens_a_modal_and_pauses() -> void:
	_play(PARAMS)
	check_eq(host.sim.speed, GameClock.Speed.SLOW)
	host.sim.notice_raised.emit(&"disaster", {"kind": "fire", "x": 30, "y": 30})
	check(host.notice_dialog.is_open(), "notice dialog visible")
	check(host.notice_dialog.visible)
	check(host.notice_dialog.title_label.text.contains("Fire"))
	check(host.is_input_blocked(), "camera input blocked while modal")
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "sim paused under the notice")
	host.sim.notice_raised.emit(&"plant_retired", {"name": "Coal Power Plant", "x": 3, "y": 4})
	check_eq(host.notices.pending(), 1, "second notice waits its turn")
	host.notice_dialog.dismiss()
	check(host.notice_dialog.is_open(), "queued notice shown next")
	check(host.notice_dialog.title_label.text.contains("Retired"))
	host.notice_dialog.dismiss()
	check(not host.notice_dialog.is_open(), "dialog closed")
	check_eq(host.sim.speed, GameClock.Speed.SLOW, "speed restored")
	check(not host.is_input_blocked())
	# Monthly papers stay quiet; extras interrupt.
	host.sim.notice_raised.emit(&"newspaper", {"extra": false, "stories": []})
	check(not host.notice_dialog.is_open(), "an ordinary issue is not a modal")
	host.sim.notice_raised.emit(&"newspaper", {"extra": true, "date": "May 1950",
		"stories": [{"headline": "Big news", "body": "Details."}]})
	check(host.notice_dialog.is_open())
	check(host.notice_dialog.body_label.text.contains("Big news"))
	host.notice_dialog.dismiss()


func test_reward_offer_enables_the_reward_tool() -> void:
	_play(PARAMS)
	host.sim.stats.rewards_offered[&"mayors_residence"] = true
	host.sim.notice_raised.emit(&"reward_offered", {"key": "mayors_residence"})
	check(host.notice_dialog.is_open())
	check_eq(host.notice_dialog.choice_buttons.size(), 2)
	host.notice_dialog.dismiss(&"accept")
	check_eq(host.tool, Tools.Kind.REWARD_MAYORS_RESIDENCE, "accepting selects the reward tool")
	check(not host.toolbar.is_locked(Tools.Kind.REWARD_MAYORS_RESIDENCE))


func test_budget_review_pauses_until_acknowledged_and_autosaves() -> void:
	_play(PARAMS)
	var autosave_path := CityFileFlow.autosave_path()
	if FileAccess.file_exists(autosave_path):
		DirAccess.remove_absolute(autosave_path)
	host.sim.advance_days(GameClock.DAYS_PER_YEAR)
	check(host.sim.budget_review_pending, "review pending after December")
	check(FileAccess.file_exists(autosave_path), "January autosave written")
	var saw_budget_window := host.window_manager.is_open("budget")
	if saw_budget_window:
		var w: Control = host.windows["budget"]
		w.call("close")
	else:
		check(host.notice_dialog.is_open(), "review notice shown without a budget window")
		check(host.notice_dialog.title_label.text.contains("Budget"))
		host.notice_dialog.dismiss()
	check(not host.sim.budget_review_pending, "review finished on close")
	check_eq(host.sim.speed, GameClock.Speed.SLOW, "speed restored after the review")
	host.sim.advance_days(1)
	check(host.status_bar.date_label.text.contains("1951"))


func test_save_then_load_keeps_the_city() -> void:
	var city := _play(PARAMS)
	var start := _flat_run(city, 6)
	host.select_tool(Tools.Kind.ROAD)
	host.handle_drag(start, start + Vector2i(5, 0))
	host.sim.advance_days(10)
	var funds := city.funds
	var path := host.files.save_city_as("host round trip")
	check(not path.is_empty(), "save wrote a file")
	check(FileAccess.file_exists(path))
	check_eq(host.save_path, path)
	host.start_new_city({"name": "Other", "seed": 7, "hills": 10, "water": 10, "trees": 5, "river": false})
	check_eq(host.sim.city.name, "Other")
	check_eq(host.stage, GameHost.Stage.EDITING, "a fresh map is being shaped")
	check(host.load_city(path), "load succeeds")
	check_eq(host.stage, GameHost.Stage.PLAY, "a founded save loads straight into play")
	check_eq(host.sim.city.name, "Testbed")
	check_eq(host.sim.city.funds, funds)
	check_eq(host.sim.clock.day, 10)
	check(Buildings.is_road_like(host.sim.city.building_at(start.x + 2, start.y)), "road survived the round trip")
	check_eq(host.presentation.city, host.sim.city, "renderer shows the loaded city")
	check(not host.load_city("user://saves/does-not-exist.sc2d"), "missing file is refused")
	check(host.notice_dialog.is_open(), "the refusal is explained")
	host.notice_dialog.dismiss()


func test_windows_open_by_name_and_close_on_escape() -> void:
	_play(PARAMS)
	var help := host.open_window("help")
	check(help != null and help.visible, "help window opens")
	check(host.window_manager.is_open("help"))
	check_eq(host.open_window("help"), help, "windows are reused")
	check_eq(host.open_window("no_such"), null, "unknown windows are null")
	host.escape()
	check(not help.visible, "escape closes the window")
	check(not host.window_manager.is_open("help"))
	var options := host.open_window("options")
	check(options != null and options.visible)
	options.call("close")
	check(not host.window_manager.is_open("options"))
	for w in GameMenuBar.WINDOW_NAMES:
		var opened := host.open_window(w)
		if opened != null:
			check(opened.visible, "%s window visible" % w)
			check(opened.has_method("bind") and opened.has_method("refresh"), "%s follows the contract" % w)
	host.window_manager.close_all()
	check(host.window_manager.open_windows.is_empty())


func test_query_and_escape_drop_the_tool() -> void:
	var city := _play(PARAMS)
	host.select_tool(Tools.Kind.ZONE_RES_LOW)
	host.open_query(Vector2i(40, 40))
	check(host.query_panel.is_open())
	check(host.query_panel.lines().size() > 5)
	host.escape()
	check(not host.query_panel.is_open(), "escape closes the query panel first")
	host.escape()
	check_eq(host.tool, GameHost.NO_TOOL, "escape then drops the tool")
	var r := host.handle_drag(Vector2i(40, 40), Vector2i(41, 41))
	check(not bool(r["ok"]), "nothing happens without a tool")
	check_eq(city.zone_kind_at(40, 40), Zones.NONE)


func test_options_and_menu_actions_apply() -> void:
	_play(PARAMS)
	host.set_option(&"ui_scale", 125)
	check_eq(host.display_layout.ui_scale, 125)
	host.set_option(&"labels", false)
	check(not host.city_view_3d.labels_visible)
	host.set_option(&"disasters_enabled", false)
	check(not host.sim.stats.disasters_enabled)
	host.menu_bar.press(&"disasters_enabled")
	check(host.sim.stats.disasters_enabled, "menu toggle flips the flag back")
	host.menu_bar.press(&"speed", GameClock.Speed.FAST)
	check_eq(host.sim.speed, GameClock.Speed.FAST)
	check(host.menu_bar.is_checked(&"speed", GameClock.Speed.FAST))
	host.menu_bar.press(&"underground")
	check(host.presentation.is_underground())
	host.menu_bar.press(&"overlay", &"crime")
	check_eq(host.presentation.get_overlay(), &"crime")
	host.menu_bar.press(&"zoom", 0)
	check_eq(host.city_view_3d.zoom_level(), 0)
	host.select_tool(Tools.Kind.WATER_PIPE)
	check(host.presentation.is_underground(), "pipes are laid in the underground view")
	host.select_tool(Tools.Kind.ROAD)
	check(host.presentation.is_underground(), "a manual underground choice is kept")
	host.menu_bar.press(&"city_save_as")
	check(host.save_dialog.is_open())
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "dialogs pause the game")
	host.save_dialog.close()
	check_eq(host.sim.speed, GameClock.Speed.FAST)


func test_ordinance_toggle_refreshes_tool_locks_at_once() -> void:
	var params := PARAMS.duplicate()
	params["founded_year"] = 2000
	_play(params)
	check(not host.toolbar.is_locked(Tools.Kind.NUCLEAR_PLANT), "nuclear plants are available in 2000")
	host.open_window("ordinances")
	var w: OrdinancesWindow = host.windows["ordinances"]
	w.set_ordinance(&"nuclear_free_zone", true)
	check(host.sim.stats.ordinances.get(&"nuclear_free_zone", false), "the window enacts the ordinance")
	check(host.toolbar.is_locked(Tools.Kind.NUCLEAR_PLANT), "the toolbar locks the plant without waiting for a day")
	w.set_ordinance(&"nuclear_free_zone", false)
	check(not host.toolbar.is_locked(Tools.Kind.NUCLEAR_PLANT), "repeal unlocks it at once")
