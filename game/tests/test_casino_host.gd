# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Gaming-resort tables through Main: refusals, the modal pause, Escape,
## the status bar, closing the city mid-round and Explore suspension.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const COMSTOCK := &"arcology_comstock"
const PREFERENCES := "user://casino-host.cfg"

var host: GameHost
var closed_count := 0


func before_all() -> void:
	CasinoTableOverlay.animation_scale = 0.0


func after_all() -> void:
	CasinoTableOverlay.animation_scale = 1.0


func before_each() -> void:
	host = MAIN.instantiate()
	host.preferences_path = PREFERENCES
	root.add_child(host)
	closed_count = 0
	host.casino_closed.connect(func() -> void: closed_count += 1)


func after_each() -> void:
	host.free()
	if FileAccess.file_exists(PREFERENCES):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFERENCES))
	await physics_frame


func found(funds: int = 200000) -> void:
	host.begin_city(flat_city(funds), {}, 7, CityStats.new())
	host.sim.set_speed(GameClock.Speed.FAST)


func test_refusals_before_founding_and_while_blocked() -> void:
	check(not host.open_casino_table(COMSTOCK, &"blackjack"), "no table on the title screen")
	check(not host.is_casino_open())
	found()
	host.stage = GameHost.Stage.EDITING
	check(not host.open_casino_table(COMSTOCK, &"blackjack"), "no table before founding")
	host.stage = GameHost.Stage.PLAY
	host.notices.show("Busy", "Another dialog")
	check(not host.open_casino_table(COMSTOCK, &"blackjack"), "no table over a dialog")
	host.notice_dialog.dismiss()
	check_eq(host.modal_depth, 0)


func test_unknown_tables_and_an_empty_treasury_explain_themselves() -> void:
	found()
	check(not host.open_casino_table(&"nowhere", &"blackjack"))
	check(host.notice_dialog.is_open())
	check_eq(host.notice_dialog.body_label.text, CasinoLines.UNKNOWN_RESORT)
	host.notice_dialog.dismiss()
	check(not host.open_casino_table(COMSTOCK, &"chuck_a_luck"), "the birdcage is at Silver Junction")
	check_eq(host.notice_dialog.body_label.text, CasinoLines.UNKNOWN_GAME)
	host.notice_dialog.dismiss()
	host.sim.city.funds = 50
	check(not host.open_casino_table(COMSTOCK, &"blackjack"))
	check_eq(host.notice_dialog.body_label.text, CasinoLines.no_credit(100, 50))
	check(host.notice_dialog.body_label.text.contains("$100") and host.notice_dialog.body_label.text.contains("$50"),
		"the refusal names the minimum and the treasury")
	host.notice_dialog.dismiss()
	check_eq(host.modal_depth, 0)
	check_eq(host.sim.speed, GameClock.Speed.FAST)


func test_table_pauses_the_city_and_escape_restores_it() -> void:
	found()
	check(host.open_casino_table(COMSTOCK, &"blackjack", CasinoRng.new(3)))
	check(host.is_casino_open())
	check(host.is_input_blocked())
	check_eq(host.modal_depth, 1)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	check(not host.open_casino_table(COMSTOCK, &"roulette"), "one table at a time")
	var overlay := host.casino_overlay
	check_eq(overlay.get_parent(), host.modal_layer)
	var focused := root.gui_get_focus_owner()
	check(focused != null and overlay.is_ancestor_of(focused), "keyboard focus is on the table")
	overlay.game.rig([CasinoDeck.card(10, 0), CasinoDeck.card(9, 1), CasinoDeck.card(5, 2), CasinoDeck.card(8, 3)])
	overlay.press_chip(0)
	overlay.perform_action(&"deal")
	check_eq(host.status_bar.funds_label.text, "$199,900", "the status bar follows the debit while paused")
	host.escape()
	check(host.is_casino_open(), "Escape cannot abandon a hand")
	overlay.perform_action(&"stand")
	check_eq(overlay.game.state, CasinoGame.SETTLED)
	host.escape()
	check(not host.is_casino_open())
	check_eq(closed_count, 1)
	check_eq(host.modal_depth, 0)
	check_eq(host.sim.speed, GameClock.Speed.FAST, "the speed before the table comes back")
	check_eq(host.status_bar.funds_label.text, "$" + UIFactory.commafy(host.sim.city.funds))
	check(not host.is_input_blocked())


func test_escape_closes_a_notice_over_the_table_first() -> void:
	found()
	host.open_casino_table(COMSTOCK, &"slots", CasinoRng.new(1))
	host.notices.show("Dispatch", "A notice over the table")
	host.escape()
	check(not host.notice_dialog.is_open())
	check(host.is_casino_open(), "the table stays")
	host.escape()
	check(not host.is_casino_open())
	check_eq(host.modal_depth, 0)


func test_replacing_the_city_mid_round_refunds_the_stake() -> void:
	found()
	host.open_casino_table(COMSTOCK, &"blackjack", CasinoRng.new(4))
	var overlay := host.casino_overlay
	overlay.game.rig([CasinoDeck.card(10, 0), CasinoDeck.card(9, 1), CasinoDeck.card(5, 2), CasinoDeck.card(8, 3)])
	overlay.press_chip(3)
	overlay.perform_action(&"deal")
	var old_city := host.sim.city
	check_eq(old_city.funds, 199000)
	host.begin_city(flat_city(30000), {}, 9, CityStats.new())
	check(not host.is_casino_open())
	check_eq(old_city.funds, 200000, "the abandoned round is refunded to its own city")
	check_eq(host.sim.city.funds, 30000)
	check_eq(host.modal_depth, 0)
	check_eq(closed_count, 1)


## Play into a round with `play`, then send the app to the background.
func _background_round(resort: StringName, game: StringName, rig: Array, play: Callable) -> void:
	found()
	check(host.open_casino_table(resort, game, CasinoRng.new(4)), "fixture: the table opens")
	var overlay := host.casino_overlay
	overlay.game.rig(rig)
	play.call(overlay)
	check_eq(overlay.game.state, CasinoGame.PLAYING, "fixture: a round is in play")
	var recovery := "user://casino-host-recovery.sc2d"
	host.suspend_for_background(recovery)
	check(not host.is_casino_open(), "backgrounding closes the table")
	check_eq(host.modal_depth, 0)
	host.resume_from_background()
	if FileAccess.file_exists(recovery):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(recovery))
	while host.notice_dialog.is_open():
		host.notice_dialog.dismiss()


func test_backgrounding_mid_blackjack_stands_instead_of_refunding() -> void:
	# Player 10+5 = 15 against the dealer's 9+8 = 17: standing loses.
	_background_round(COMSTOCK, &"blackjack", [CasinoDeck.card(10, 0), CasinoDeck.card(9, 1), CasinoDeck.card(5, 2), CasinoDeck.card(8, 3)],
		func(overlay: CasinoTableOverlay) -> void:
			overlay.press_chip(0)
			overlay.perform_action(&"deal"))
	check_eq(host.sim.city.funds, 200000 - 100, "a losing hand is not refunded by leaving the app")
	var message := host.status_bar.message_label.text
	check(message.contains("Your Assay Twenty-One hand was played out while you were away: -$100."), message)
	check(message.contains("Paused while you were away"), "the pause note stays: " + message)
	var ledger := host.sim.casino().ledger(COMSTOCK)
	check_eq(int(ledger.get("rounds", 0)), 1, "the hand is recorded as a round")
	check_eq(int(ledger.get("year_net", 0)), -100)


func test_backgrounding_mid_launch_cashes_out_at_the_shown_multiplier() -> void:
	_background_round(&"arcology_orbit", &"trajectory", [5.0],
		func(overlay: CasinoTableOverlay) -> void:
			overlay.press_chip(0)
			overlay.perform_action(&"launch")
			overlay.perform_action(&"advance", {"multiplier": 2.0}))
	check_eq(host.sim.city.funds, 200000 + 1000, "a $1,000 launch cashed out at 2.00x")
	var message := host.status_bar.message_label.text
	check(message.contains("Your %s launch was played out while you were away: +$1,000." % ResortThemes.game_name(&"arcology_orbit", &"trajectory")), message)
	check_eq(int(host.sim.casino().ledger(&"arcology_orbit").get("rounds", 0)), 1)


func test_backgrounding_mid_poker_draws_with_the_holds() -> void:
	_background_round(&"arcology_boulder", &"video_poker", [CasinoDeck.card(1, 3), CasinoDeck.card(1, 2), CasinoDeck.card(5, 0), CasinoDeck.card(9, 1), CasinoDeck.card(13, 0),
		CasinoDeck.card(1, 1), CasinoDeck.card(2, 0), CasinoDeck.card(3, 2)],
		func(overlay: CasinoTableOverlay) -> void:
			overlay.press_chip(0)
			overlay.perform_action(&"deal")
			overlay.perform_action(&"hold", {"index": 0})
			overlay.perform_action(&"hold", {"index": 1}))
	# Aces held, the draw brings a third ace: three of a kind returns 3x.
	check_eq(host.sim.city.funds, 200000 - 500 + 1500, "the draw is played with the cards held")
	var message := host.status_bar.message_label.text
	check(message.contains("Your %s hand was played out while you were away: +$1,000." % ResortThemes.game_name(&"arcology_boulder", &"video_poker")), message)
	check_eq(int(host.sim.casino().ledger(&"arcology_boulder").get("rounds", 0)), 1)


func test_quit_while_seated_explains_the_wait() -> void:
	found()
	host.open_casino_table(COMSTOCK, &"blackjack", CasinoRng.new(3))
	host.files.quit_game()
	check(host.is_casino_open(), "the table stays open")
	check_eq(host.casino_overlay.patter_label.text, CasinoLines.QUIT_SEATED, "the table says why the quit waits")
	# Do not let the waiting quit end the test run after the table closes.
	host.files._quit_waiting = false
	host.casino_overlay.close()
	check(not host.is_casino_open())


func test_explore_suspends_while_seated_and_resumes_after() -> void:
	found()
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.select_tool(Tools.Kind.ROAD)
	host.handle_drag(Vector2i(22, 20), Vector2i(24, 20))
	await physics_frame
	host.city_view_3d.set_camera_state(Vector3(22.5, 2.4, 20.5), 0, 48)
	check(host.enter_explore(), "fixture enters on an outdoor road")
	if not host.is_exploring():
		return
	await physics_frame
	await physics_frame
	check(not host.exploration.is_suspended())
	check(host.open_casino_table(COMSTOCK, &"roulette", CasinoRng.new(2)))
	check(host.exploration.is_suspended(), "the walker stands still at the table")
	var feet: Vector3 = host.exploration.pedestrian.global_position
	for code in [KEY_W, KEY_A, KEY_SPACE]:
		var key := InputEventKey.new()
		key.keycode = code
		key.pressed = true
		root.push_input(key)
	await physics_frame
	await physics_frame
	check_eq(host.exploration.pedestrian.global_position, feet, "table keys never move the walker")
	check(host.exploration.is_suspended())
	host.casino_overlay.close()
	check(not host.is_casino_open())
	check(not host.exploration.is_suspended(), "Explore resumes as the table closes")
	check(not (host.explore_hud.visible and host.explore_hud._panel.visible), "the paused panel never flashes after the table")
	for _i in 4:
		await physics_frame
	check(not host.exploration.is_suspended(), "Explore resumes after leaving the table")
	check(host.is_exploring())


func test_backgrounding_between_rounds_adds_no_casino_note() -> void:
	found()
	check(host.open_casino_table(COMSTOCK, &"slots", CasinoRng.new(1)), "fixture: the table opens")
	var recovery := "user://casino-host-recovery.sc2d"
	host.suspend_for_background(recovery)
	check(host.is_casino_open(), "nothing in play: the table stays")
	host.resume_from_background()
	if FileAccess.file_exists(recovery):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(recovery))
	while host.notice_dialog.is_open():
		host.notice_dialog.dismiss()
	check(not host.status_bar.message_label.text.contains("played out"), host.status_bar.message_label.text)
	host.casino_overlay.close()


func test_despicables_is_available_before_resort_budget_and_keeps_low_limits() -> void:
	found(10000)
	var store := &"com_corner_store"
	check(host.open_casino_table(store,&"video_poker",CasinoRng.new(7)))
	check_eq(host.casino_overlay.game.limits,{"minimum":1,"maximum":1000})
	check(host.casino_overlay.rules_label.text.contains("$1,000"))
	host.escape()
	host.sim.city.funds = 17
	check(host.open_casino_table(store,&"slots",CasinoRng.new(7)))
	check_eq(host.casino_overlay.game.limits,{"minimum":1,"maximum":17})
	host.casino_overlay.press_chip(0)
	host.casino_overlay.perform_action(&"pull")
	check_eq(host.casino_overlay.game.state,CasinoGame.SETTLED)
	check_eq(int(host.sim.casino().ledger(store).staked),1)
	host.escape()
	check_eq(host.modal_depth,0)
