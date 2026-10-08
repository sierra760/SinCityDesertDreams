# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A whole gaming-resort visit through Main: walk in from the street, sit at
## a table, play a hand with the keyboard, leave the table and the hall,
## Inspect the resort, save and load the ledger, and close the city while a
## hand is in play.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const Access := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")
const COMSTOCK := &"arcology_comstock"
const ANCHOR := Vector2i(20, 18)
const ROAD := Vector2i(22, 24)
const START_FUNDS := 200000
const PREFERENCES := "user://casino-session.cfg"
const SAVE_NAME := "casino-session"

var host: GameHost
var closed_count := 0
var requests: Array = []
var funds_seen: Array[int] = []
var _transition_seconds := 0.0


func before_all() -> void:
	CasinoTableOverlay.animation_scale = 0.0
	_transition_seconds = ExploreResortService.transition_seconds
	ExploreResortService.transition_seconds = 0.0


func after_all() -> void:
	CasinoTableOverlay.animation_scale = 1.0
	ExploreResortService.transition_seconds = _transition_seconds


func before_each() -> void:
	host = MAIN.instantiate()
	host.preferences_path = PREFERENCES
	root.add_child(host)
	closed_count = 0
	requests.clear()
	funds_seen.clear()
	host.casino_closed.connect(func() -> void: closed_count += 1)


func after_each() -> void:
	for code: Key in [KEY_1, KEY_ENTER, KEY_S, KEY_F, KEY_W]:
		Input.parse_input_event(_key_event(code, false))
	host.free()
	for path: String in [PREFERENCES, "user://saves/%s.sc2d" % SAVE_NAME]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await physics_frame


func _resort_city() -> City:
	var value := flat_city(START_FUNDS)
	value.stamp_building(ANCHOR.x, ANCHOR.y, Buildings.ARCOLOGY_COMSTOCK)
	value.building.putv(ROAD, 30)
	value.building.putv(ROAD + Vector2i.RIGHT, 30)
	return value


static func _key_event(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _press(code: Key) -> void:
	root.push_input(_key_event(code, true))
	root.push_input(_key_event(code, false))


func _frames(count: int) -> void:
	for _i in count:
		await physics_frame


func _status() -> Dictionary:
	var captured: Array[Dictionary] = []
	var listener := func(status: Dictionary) -> void: captured.append(status)
	host.exploration.status_changed.connect(listener)
	host.exploration._publish_status()
	host.exploration.status_changed.disconnect(listener)
	return captured[0] if not captured.is_empty() else {}


func _walk_to(point: Vector3) -> void:
	var walker: ExplorePedestrian = host.exploration.pedestrian
	walker.clear_support_frame()
	walker.global_position = point + Vector3.UP * .002
	walker.stop_input()
	await _frames(2)


## Found the resort city, enter Explore on its road and walk in the door.
## False (after a failed check) when any step of the way is unavailable.
func _walk_inside() -> bool:
	host.begin_city(_resort_city(), {}, 7, CityStats.new())
	host.sim.set_speed(GameClock.Speed.SLOW)
	host.exploration.casino_table_requested.connect(func(resort: StringName, game: StringName, table: Dictionary) -> void:
		requests.append([resort, game, table]))
	host.sim.funds_changed.connect(func(value: int) -> void: funds_seen.append(value))
	await physics_frame
	host.city_view_3d.set_camera_state(Vector3(ROAD.x + .5, 2.4, ROAD.y + .5), 0, 48)
	check(host.enter_explore(), "Explore starts on the resort's road")
	if not host.is_exploring(): return false
	await _frames(2)
	await _walk_to(Access.threshold(host.sim.city, ANCHOR).origin)
	check_eq(String(_status().get("prompt", "")), "F to enter Comstock Grand", "the door names the resort")
	check(host.exploration.request_interaction(), "F at the door")
	await _frames(2)
	var service: ExploreResortService = host.exploration.resort_service
	check(service.is_inside(), "the walker is on the casino floor")
	return service.is_inside()


func _blackjack_table() -> Dictionary:
	var service: ExploreResortService = host.exploration.resort_service
	var world := service.world_for({"anchor": ANCHOR, "code": Buildings.ARCOLOGY_COMSTOCK, "key": COMSTOCK})
	for table: Dictionary in world.tables():
		if StringName(table.game) == &"blackjack": return table
	return {}


## Sit at the blackjack table: the request opens the table over the city.
func _sit_down() -> bool:
	var table := _blackjack_table()
	check(not table.is_empty(), "the hall has a blackjack table")
	if table.is_empty(): return false
	await _walk_to(table.seat)
	check(String(_status().get("prompt", "")).begins_with("F to play Assay Twenty-One"), "the seat names its table")
	check(host.exploration.request_interaction(), "F at the seat")
	check_eq(requests.size(), 1, "the controller asks for the table")
	check(host.is_casino_open(), "the request opens the table")
	return host.is_casino_open()


func test_walk_in_play_a_hand_walk_out_and_keep_the_ledger() -> void:
	if not await _walk_inside(): return
	if not await _sit_down(): return
	var overlay := host.casino_overlay
	check_eq(host.modal_depth, 1)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED, "the city waits while the mayor plays")
	check(host.exploration.camera_rig.table_view_active, "the camera holds the table's seated view")
	check(not host.explore_hud.visible, "the Explore panel stays out from behind the table")
	check(_status().has("table_camera"), "the status carries the held view")
	await _frames(2)
	check(host.exploration.is_suspended(), "Explore is suspended at the table")
	var feet: Vector3 = host.exploration.pedestrian.global_position
	# One seeded hand by keyboard: either deal order ends in a player win.
	overlay.game.rig([CasinoDeck.card(10, 0), CasinoDeck.card(9, 1), CasinoDeck.card(8, 2), CasinoDeck.card(8, 3), CasinoDeck.card(10, 2)])
	_press(KEY_1)
	check_eq(overlay.game.total_staked(), 100, "1 bets the table minimum")
	funds_seen.clear()
	_press(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.PLAYING, "Enter deals")
	check_eq(host.sim.city.funds, START_FUNDS - 100, "the stake leaves the treasury")
	check(funds_seen.has(START_FUNDS - 100), "funds_changed reports the debit while paused")
	_press(KEY_S)
	check_eq(overlay.game.state, CasinoGame.SETTLED, "S stands")
	check_eq(String(overlay.game.outcome().get("reaction", "")), "win")
	check_eq(host.sim.city.funds, START_FUNDS + 100, "the win comes back to the treasury")
	check(funds_seen.has(START_FUNDS + 100), "funds_changed reports the payout")
	check_eq(host.status_bar.funds_label.text, "$" + UIFactory.commafy(START_FUNDS + 100))
	await _frames(2)
	check_eq(host.exploration.pedestrian.global_position, feet, "table keys never move the walker")
	# Leave the table.
	host.escape()
	check(not host.is_casino_open(), "Escape leaves a settled table")
	check_eq(closed_count, 1)
	check_eq(host.modal_depth, 0)
	check_eq(host.sim.speed, GameClock.Speed.SLOW, "the city's speed comes back")
	check(not host.exploration.camera_rig.table_view_active, "the camera follows the walker again")
	check(not _status().has("table_camera"))
	check(host.explore_hud.visible, "the Explore HUD returns")
	await _frames(4)
	check(not host.exploration.is_suspended(), "Explore resumes after the table")
	check(host.exploration.resort_service.is_inside(), "still on the casino floor")
	# Inspect reads the floor and the year's play.
	var rows := QueryPanel.describe(host.sim.city, host.sim, ANCHOR + Vector2i(1, 1))
	check_eq(String(rows.get("Casino floor", "")), "The Assay Office")
	check_eq(String(rows.get("Mayor's play this year", "")), "+$100")
	# Out the door.
	var service: ExploreResortService = host.exploration.resort_service
	await _walk_to(service.world_for({"anchor": ANCHOR, "code": Buildings.ARCOLOGY_COMSTOCK, "key": COMSTOCK}).mat_transform().origin)
	check_eq(String(_status().get("prompt", "")), "F to step outside")
	check(host.exploration.request_interaction(), "F at the mat")
	await _frames(2)
	check(not service.is_inside(), "back on the street")
	var threshold := Access.threshold(host.sim.city, ANCHOR)
	var outside: Vector3 = host.exploration.pedestrian.global_position
	check_lt(Vector2(outside.x - threshold.origin.x, outside.z - threshold.origin.z).length(), .35, "at the resort's threshold")
	# Save and load keep the ledger.
	host.return_to_build()
	await _frames(2)
	var path := host.files.save_city_as(SAVE_NAME)
	check(not path.is_empty(), "the city saves")
	if path.is_empty(): return
	host.begin_city(flat_city(30000), {}, 9, CityStats.new())
	check_eq(host.sim.casino().ledger(COMSTOCK).get("rounds", -1), 0, "a different city has its own ledger")
	check(host.load_city(path), "the saved city loads")
	while host.loading_screen.visible: await process_frame
	var ledger := host.sim.casino().ledger(COMSTOCK)
	check_eq(int(ledger.get("rounds", 0)), 1, "the loaded ledger remembers the hand")
	check_eq(int(ledger.get("year_net", 0)), 100)
	check(host.sim.casino().has_debuted(), "the debut story is not told twice")
	check_eq(host.sim.city.funds, START_FUNDS + 100)


func test_closing_the_city_from_the_table_refunds_the_hand() -> void:
	if not await _walk_inside(): return
	if not await _sit_down(): return
	var overlay := host.casino_overlay
	overlay.game.rig([CasinoDeck.card(10, 0), CasinoDeck.card(9, 1), CasinoDeck.card(8, 2), CasinoDeck.card(8, 3), CasinoDeck.card(10, 2)])
	_press(KEY_2)
	_press(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.PLAYING)
	var old_city := host.sim.city
	check_eq(old_city.funds, START_FUNDS - 200, "the stake is on the table")
	host.begin_city(flat_city(30000), {}, 9, CityStats.new())
	check(not host.is_casino_open(), "the table closes with its city")
	check_eq(old_city.funds, START_FUNDS, "the open hand is refunded to its own city")
	check_eq(host.sim.city.funds, 30000)
	check_eq(host.sim.casino().ledger(COMSTOCK).get("rounds", -1), 0, "a refund is not a round")
	check_eq(host.modal_depth, 0)
	check_eq(closed_count, 1)
	await _frames(2)
	check(not host.is_exploring(), "Explore ends with its city")
	check(not host.explore_hud.visible, "the HUD is not left showing after the city closes")


func test_inspect_says_when_a_ledger_covers_several_floors() -> void:
	var city := _resort_city()
	var sim := make_simulation(city, 7)
	check(sim.casino_commit(COMSTOCK, &"blackjack", 100))
	sim.casino_settle(COMSTOCK, &"blackjack", 100, 300)
	var rows := QueryPanel.describe(city, sim, ANCHOR)
	check_eq(String(rows.get("Casino floor", "")), "The Assay Office")
	check_eq(String(rows.get("Mayor's play this year", "")), "+$200", "one floor shows the plain figure")
	city.stamp_building(ANCHOR.x + 6, ANCHOR.y, Buildings.ARCOLOGY_COMSTOCK)
	rows = QueryPanel.describe(city, sim, ANCHOR)
	check_eq(String(rows.get("Mayor's play this year", "")), "+$200 across 2 floors", "the shared ledger says so")
	check_eq(String(QueryPanel.describe(city, sim, Vector2i(30, 30)).get("Mayor's play this year", "none")), "none", "not a resort")
	sim.free()
