# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The Recall Warning for a losing round opens once the table has shown the
## result: not while the wheel is still turning or the dealer's cards are
## still face down.
extends "res://tests/exploration/async_test_case.gd"

const MAIN := preload("res://scenes/main.tscn")
const COMSTOCK := &"arcology_comstock"
const PREFERENCES := "user://casino-recall-warning.cfg"
const START_FUNDS := 10000

var host: GameHost
var warnings := 0


func before_each() -> void:
	CasinoTableOverlay.animation_scale = 0.0
	host = MAIN.instantiate()
	host.preferences_path = PREFERENCES
	root.add_child(host)
	host.begin_city(flat_city(START_FUNDS), {}, 7, CityStats.new())
	warnings = 0
	host.sim.notice_raised.connect(func(kind: StringName, _payload: Dictionary) -> void:
		if kind == &"recall_warning": warnings += 1)


func after_each() -> void:
	CasinoTableOverlay.animation_scale = 1.0
	host.free()
	if FileAccess.file_exists(PREFERENCES):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFERENCES))
	await physics_frame


func _warning_open() -> bool:
	return host.notice_dialog.is_open() and host.notice_dialog.title_label.text == "Recall Warning"


## Stake 6,000 of the 10,000 treasury on a number that does not come up.
func _lose_at_roulette() -> CasinoTableOverlay:
	check(host.open_casino_table(COMSTOCK, &"roulette", CasinoRng.new(9)))
	var overlay := host.casino_overlay
	for chip in 60:
		overlay.bet_on(&"n17")
	check_eq(overlay.game.total_staked(), 6000)
	overlay.game.rig([4])
	check(bool(overlay.perform_action(&"spin").get("confirm", false)), "more than half the treasury asks first")
	return overlay


func test_warning_waits_for_the_wheel_to_stop() -> void:
	var overlay := _lose_at_roulette()
	CasinoTableOverlay.animation_scale = 40.0
	overlay.perform_action(&"spin")
	check_eq(overlay.game.state, CasinoGame.SETTLED, "the round is decided at once")
	check_eq(host.sim.city.funds, START_FUNDS - 6000, "and the treasury settled at once")
	check_eq(warnings, 1, "the simulation raised the warning at settlement")
	check(overlay.stage.is_busy(), "the wheel is still turning")
	check(not _warning_open(), "no warning over a wheel that is still turning")
	for frame in 4:
		await process_frame
	check(not _warning_open(), "still none a few frames later")
	overlay.stage.skip()
	check(not overlay.stage.is_busy())
	check(_warning_open(), "the warning opens once the result has been shown")
	check_eq(host.notices.pending(), 0, "once")
	host.notice_dialog.dismiss()
	check(host.is_casino_open(), "the table is still open behind it")
	CasinoTableOverlay.animation_scale = 0.0
	overlay.perform_action(&"next")
	host.escape()
	check(not host.is_casino_open())


func test_warning_waits_for_the_dealer_to_turn_the_cards() -> void:
	check(host.open_casino_table(COMSTOCK, &"blackjack", CasinoRng.new(3)))
	var overlay := host.casino_overlay
	overlay.game.rig([CasinoDeck.card(10, 0), CasinoDeck.card(9, 1), CasinoDeck.card(5, 2), CasinoDeck.card(10, 3)])
	for chip in 60:
		overlay.press_chip(0)
	check_eq(overlay.game.total_staked(), 6000)
	overlay.perform_action(&"deal")
	overlay.perform_action(&"deal")
	check_eq(overlay.game.state, CasinoGame.PLAYING)
	CasinoTableOverlay.animation_scale = 40.0
	overlay.perform_action(&"stand")
	check_eq(overlay.game.state, CasinoGame.SETTLED, "15 against the dealer's 19 loses")
	check_eq(warnings, 1)
	check(overlay.stage.is_busy(), "the dealer's hole card has not turned yet")
	check(not _warning_open(), "no warning before the dealer's cards are shown")
	overlay.stage.skip()
	check(_warning_open(), "the warning follows the reveal")
	host.notice_dialog.dismiss()
	CasinoTableOverlay.animation_scale = 0.0
	overlay.perform_action(&"next")
	host.escape()


func test_warning_is_immediate_when_nothing_is_left_to_show() -> void:
	var overlay := _lose_at_roulette()
	overlay.perform_action(&"spin")
	check(not overlay.stage.is_busy())
	check(_warning_open(), "with the result already shown the warning opens at once")
	host.notice_dialog.dismiss()
	overlay.perform_action(&"next")
	host.escape()


func test_warning_is_not_lost_when_the_table_closes_during_the_reveal() -> void:
	var overlay := _lose_at_roulette()
	CasinoTableOverlay.animation_scale = 40.0
	overlay.perform_action(&"spin")
	check(not _warning_open())
	host.force_close_casino()
	check(not host.is_casino_open())
	check(host.notice_dialog.is_open(), "the player is still told")
	host.notices.clear_pending()
	host.notice_dialog.dismiss()
