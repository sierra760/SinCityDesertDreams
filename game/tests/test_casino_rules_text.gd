# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The rules sheet says what the tables do at their limits.
extends "res://tests/test_case.gd"

const LIMITS := {"minimum": 100, "maximum": 1000}


func _card(rank: int, suit: int) -> Dictionary:
	return {"rank": rank, "suit": suit}


func _enabled(game: CasinoGame, id: StringName) -> bool:
	for action: Dictionary in game.actions():
		if StringName(action["id"]) == id:
			return bool(action.get("enabled", false))
	return false


func _deal_pair(bet: int) -> BlackjackGame:
	var game := BlackjackGame.new()
	game.begin(CasinoRng.new(3), LIMITS)
	game.rig([_card(8, 0), _card(6, 1), _card(8, 2), _card(10, 3), _card(3, 0), _card(2, 1)])
	game.place_bet(BlackjackGame.MAIN, bet)
	game.act(BlackjackGame.DEAL)
	return game


func test_blackjack_rules_say_when_a_bet_cannot_double_or_split() -> void:
	var half := _deal_pair(500)
	check(_enabled(half, BlackjackGame.DOUBLE), "half the maximum can double")
	check(_enabled(half, BlackjackGame.SPLIT), "half the maximum can split")
	half.act(BlackjackGame.SPLIT)
	check(not _enabled(half, BlackjackGame.DOUBLE), "after the split a third bet no longer fits")
	var over := _deal_pair(600)
	check(not _enabled(over, BlackjackGame.DOUBLE), "over half the maximum cannot double")
	check(not _enabled(over, BlackjackGame.SPLIT), "over half the maximum cannot split")
	for keyboard: bool in [true, false]:
		var rules := CasinoTableOverlay.rules_text(&"blackjack", &"arcology_comstock", LIMITS, keyboard)
		check(rules.contains("a bet over half the maximum cannot double or split"), rules)
		check(rules.contains("after a split a hand can double only while a third bet still fits"), rules)


func test_launch_rules_name_the_highest_multiplier() -> void:
	for keyboard: bool in [true, false]:
		var rules := CasinoTableOverlay.rules_text(&"trajectory", &"arcology_orbit", LIMITS, keyboard)
		check(rules.contains("No engine lasts to 1,000x"), rules)
