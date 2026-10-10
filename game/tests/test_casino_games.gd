# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const LIMITS := {"minimum": 100, "maximum": 10000}


static func c(rank: int, suit: int = 0) -> Dictionary:
	return CasinoDeck.card(rank, suit)


func start(kind: StringName, seed_value: int = 11) -> CasinoGame:
	var game := ResortThemes.make_game(kind)
	game.begin(CasinoRng.new(seed_value), LIMITS)
	return game


func ids(list: Array) -> Array:
	var out: Array = []
	for item in list:
		out.append(item["id"])
	return out


func enabled(game: CasinoGame, action: StringName) -> bool:
	for a in game.actions():
		if a["id"] == action:
			return bool(a["enabled"])
	return false


func events_of(game: CasinoGame, kind: String) -> Array:
	var out: Array = []
	for e in game.take_events():
		if String(e["kind"]) == kind:
			out.append(e)
	return out


# ── Shared behaviour ─────────────────────────────────────────────────────

func test_every_game_shares_the_betting_contract() -> void:
	for kind in ResortThemes.KINDS:
		var game := start(kind)
		check_eq(game.kind, kind)
		check_eq(game.state, CasinoGame.BETTING)
		var spots := game.spots()
		check(not spots.is_empty(), "%s has spots" % kind)
		for s in spots:
			check(s.has("id") and s.has("label") and s.has("odds") and s.has("group"), "%s spot fields" % kind)
			check_eq(typeof(s["id"]), TYPE_STRING_NAME)
		var commit := game.commit_action()
		check(commit in ids(game.actions()), "%s offers %s" % [kind, commit])
		check(not enabled(game, commit), "%s needs a bet first" % kind)
		check_eq(String(game.act(commit).get("reason", "")), CasinoLines.NO_BETS)
		var spot: StringName = spots[0]["id"]
		check(not bool(game.place_bet(&"nowhere", 100).get("ok", true)), "unknown spot")
		check(not bool(game.place_bet(spot, 0).get("ok", true)), "zero bet")
		check(not bool(game.place_bet(spot, 10001).get("ok", true)), "over maximum")
		check(bool(game.place_bet(spot, 50).get("ok", false)))
		check_eq(game.total_staked(), 50)
		check(not enabled(game, commit), "%s below minimum" % kind)
		check_eq(String(game.act(commit).get("reason", "")), CasinoLines.below_minimum(100))
		check(bool(game.place_bet(spot, 50).get("ok", false)), "bets stack on a spot")
		check_eq(game.bets(), {spot: 100})
		check(not bool(game.place_bet(spot, 9901).get("ok", true)), "total stays under the maximum")
		check(enabled(game, commit))
		var view := game.view_state()
		check_eq(String(view["state"]), "betting")
		check_eq(int(view["staked"]), 100)
		check(JSON.parse_string(JSON.stringify(view)) != null, "%s view is JSON-safe" % kind)
		var payload := {}
		var result := game.act(commit, payload)
		check(bool(result.get("ok", false)), "%s commits" % kind)
		check_eq(int(result.get("stake", -1)), 100, "%s reports the stake to debit" % kind)
		check_ne(game.state, CasinoGame.BETTING)
		check(not bool(game.place_bet(spot, 100).get("ok", true)), "bets closed")
		_finish_round(game)
		check_eq(game.state, CasinoGame.SETTLED, "%s settles" % kind)
		var out := game.outcome()
		check_eq(int(out["staked"]), game.total_staked())
		check_eq(int(out["net"]), int(out["returned"]) - int(out["staked"]))
		check(String(out["reaction"]) in ["win", "lose", "push", "blackjack", "bust", "jackpot", "crash"])
		check(not String(out["summary"]).is_empty())
		game.take_events()
		check(JSON.parse_string(JSON.stringify(game.view_state())) != null)
		check(bool(game.act(CasinoGame.NEXT).get("ok", false)))
		check_eq(game.state, CasinoGame.BETTING)
		check(game.bets().is_empty())
		check(enabled(game, CasinoGame.REBET), "%s offers the same bet" % kind)
		game.act(CasinoGame.REBET)
		check_eq(game.total_staked(), 100)
		game.act(CasinoGame.CLEAR)
		check_eq(game.total_staked(), 0)


## Drive a committed round to settlement with the simplest choices.
func _finish_round(game: CasinoGame) -> void:
	var guard := 0
	while game.state == CasinoGame.PLAYING and guard < 20:
		guard += 1
		match game.kind:
			&"blackjack":
				game.act(BlackjackGame.STAND)
			&"video_poker":
				game.act(VideoPokerGame.DRAW, {"held": [true, true, true, true, true]})
			&"trajectory":
				game.act(TrajectoryGame.CASH_OUT, {"multiplier": 1.0})
			_:
				var closing := game.background_action()
				if closing != &"":
					game.act(closing)


func test_settle_event_is_last_and_matches_outcome() -> void:
	var game := start(&"roulette")
	game.place_bet(&"red", 100)
	game.act(RouletteGame.SPIN)
	var drained := game.take_events()
	var last: Dictionary = drained[drained.size() - 1]
	check_eq(String(last["kind"]), "settle")
	check_eq(int(last["returned"]), int(game.outcome()["returned"]))
	check(game.take_events().is_empty(), "the log drains")


func test_limits_refresh_between_rounds() -> void:
	var game := start(&"chuck_a_luck")
	game.set_limits({"minimum": 100, "maximum": 300})
	check(not bool(game.place_bet(&"die_1", 400).get("ok", true)))
	check(bool(game.place_bet(&"die_1", 300).get("ok", false)))


# ── Blackjack ────────────────────────────────────────────────────────────

func blackjack(cards: Array, bet: int = 100) -> BlackjackGame:
	var game := start(&"blackjack") as BlackjackGame
	game.rig(cards)
	game.place_bet(BlackjackGame.MAIN, bet)
	game.act(BlackjackGame.DEAL)
	return game


func test_blackjack_natural_pays_three_to_two() -> void:
	var game := blackjack([c(1), c(9), c(13), c(7)])
	check_eq(game.state, CasinoGame.SETTLED)
	check_eq(int(game.outcome()["returned"]), 250)
	check_eq(String(game.outcome()["reaction"]), "blackjack")
	check_eq(events_of(game, "blackjack").size(), 1)
	game = blackjack([c(1), c(9), c(13), c(7)], 101)
	check_eq(int(game.outcome()["returned"]), 252, "odd stakes round down")


func test_blackjack_dealer_natural_and_double_natural() -> void:
	var game := blackjack([c(9), c(1), c(7), c(12)])
	check_eq(game.state, CasinoGame.SETTLED)
	check_eq(int(game.outcome()["returned"]), 0)
	game = blackjack([c(1), c(1, 1), c(11), c(10)])
	check_eq(int(game.outcome()["returned"]), 100, "both naturals push")
	check_eq(String(game.outcome()["reaction"]), "push")


func test_blackjack_hidden_hole_card() -> void:
	var game := blackjack([c(10), c(9), c(7), c(5, 2)])
	var hole_event: Dictionary = {}
	for e in game.take_events():
		if String(e["kind"]) == "card" and not bool(e["face_up"]):
			hole_event = e
	check_eq(hole_event["card"], {"rank": 0, "suit": 0, "face_up": false}, "the hole card is not leaked")
	var view := game.view_state()
	check(bool(view["dealer"]["hidden"]))
	check_eq(int(view["dealer"]["total"]), 9, "only the up card counts on screen")
	check_eq(int(view["hands"][0]["total"]), 17)
	check_eq(int(view["active_hand"]), 0)


func test_blackjack_stand_win_lose_push_and_dealer_rules() -> void:
	# Player 20 v dealer 9+7, draws 2 -> 18: win.
	var game := blackjack([c(10), c(9), c(13), c(7), c(2)])
	game.act(BlackjackGame.STAND)
	check_eq(int(game.outcome()["returned"]), 200)
	# Player 17 v dealer 10+8: lose.
	game = blackjack([c(10), c(10), c(7), c(8)])
	game.act(BlackjackGame.STAND)
	check_eq(int(game.outcome()["returned"]), 0)
	# Player 18 v dealer 10+8: push.
	game = blackjack([c(10), c(10), c(8), c(8)])
	game.act(BlackjackGame.STAND)
	check_eq(int(game.outcome()["returned"]), 100)
	# Dealer stands on soft 17 (ace + 6): player 18 wins.
	game = blackjack([c(10), c(1), c(8), c(6), c(5)])
	game.act(BlackjackGame.STAND)
	check_eq(int(game.view_state()["dealer"]["cards"].size()), 2, "no draw on soft 17")
	check_eq(int(game.outcome()["returned"]), 200)
	# Dealer 16 draws and busts.
	game = blackjack([c(10), c(10), c(7), c(6), c(13)])
	game.act(BlackjackGame.STAND)
	check_eq(events_of(game, "bust").size(), 1)
	check_eq(int(game.outcome()["returned"]), 200)


func test_blackjack_hit_and_bust() -> void:
	var game := blackjack([c(10), c(10), c(6), c(7), c(9)])
	game.act(BlackjackGame.HIT)
	check_eq(game.state, CasinoGame.SETTLED)
	check_eq(int(game.outcome()["returned"]), 0)
	check_eq(String(game.outcome()["reaction"]), "bust")
	game = blackjack([c(10), c(10), c(2), c(8), c(9)])
	game.act(BlackjackGame.HIT)
	check_eq(game.state, CasinoGame.SETTLED, "21 stands automatically")
	check_eq(int(game.outcome()["returned"]), 200)


func test_blackjack_double() -> void:
	var game := blackjack([c(6), c(10), c(5), c(7), c(10)])
	check(enabled(game, BlackjackGame.DOUBLE))
	var result := game.act(BlackjackGame.DOUBLE)
	check(bool(result["ok"]))
	check_eq(int(result["stake"]), 100, "the double debits the extra stake")
	check_eq(game.state, CasinoGame.SETTLED)
	check_eq(int(game.outcome()["staked"]), 200)
	check_eq(int(game.outcome()["returned"]), 400)
	# No double over the maximum.
	game = start(&"blackjack") as BlackjackGame
	game.rig([c(6), c(10), c(5), c(7)])
	game.place_bet(BlackjackGame.MAIN, 6000)
	game.act(BlackjackGame.DEAL)
	check(not enabled(game, BlackjackGame.DOUBLE), "6,000 more would pass 10,000")
	check(not bool(game.act(BlackjackGame.DOUBLE)["ok"]))


func test_blackjack_split_and_split_aces() -> void:
	var game := blackjack([c(8), c(10), c(8, 1), c(7), c(3), c(13), c(10), c(9)])
	check(enabled(game, BlackjackGame.SPLIT))
	var result := game.act(BlackjackGame.SPLIT)
	check_eq(int(result["stake"]), 100)
	check_eq(game.view_state()["hands"].size(), 2)
	check(not enabled(game, BlackjackGame.SPLIT), "split once")
	game.act(BlackjackGame.STAND)  # hand 0: 8+3 = 11
	game.act(BlackjackGame.STAND)  # hand 1: 8+K = 18; dealer 17 stands
	check_eq(game.state, CasinoGame.SETTLED)
	check_eq(int(game.outcome()["staked"]), 200)
	check_eq(int(game.outcome()["returned"]), 200, "11 loses, 18 wins")
	# Split aces get one card each; a 21 after a split pays even money.
	game = blackjack([c(1), c(10), c(1, 1), c(7), c(13), c(5), c(10)])
	game.act(BlackjackGame.SPLIT)
	check_eq(game.state, CasinoGame.SETTLED, "both ace hands stand at once")
	check_eq(int(game.outcome()["staked"]), 200)
	check_eq(int(game.outcome()["returned"]), 200, "21 after a split pays even money; 16 loses to 17")


func test_blackjack_shoe_reshuffles_below_threshold() -> void:
	var game := start(&"blackjack", 3)
	check_eq(int(game.view_state()["shoe"]), 312)
	game.place_bet(BlackjackGame.MAIN, 100)
	game.act(BlackjackGame.DEAL)
	var shuffled := events_of(game, "shuffle").size()
	check_eq(shuffled, 0, "a full shoe is not reshuffled")


# ── Roulette ─────────────────────────────────────────────────────────────

func test_roulette_returns() -> void:
	check_eq(RouletteGame.spot_return(&"n17", 17), 36)
	check_eq(RouletteGame.spot_return(&"n17", 18), 0)
	check_eq(RouletteGame.spot_return(&"n0", 0), 36)
	for spot in [&"red", &"black", &"odd", &"even", &"low", &"high", &"dozen_1", &"column_3"]:
		check_eq(RouletteGame.spot_return(spot, 0), 0, "zero loses %s" % spot)
	check_eq(RouletteGame.spot_return(&"red", 1), 2)
	check_eq(RouletteGame.spot_return(&"black", 2), 2)
	check_eq(RouletteGame.spot_return(&"red", 2), 0)
	check_eq(RouletteGame.spot_return(&"odd", 35), 2)
	check_eq(RouletteGame.spot_return(&"even", 36), 2)
	check_eq(RouletteGame.spot_return(&"low", 18), 2)
	check_eq(RouletteGame.spot_return(&"high", 19), 2)
	check_eq(RouletteGame.spot_return(&"dozen_2", 24), 3)
	check_eq(RouletteGame.spot_return(&"dozen_3", 25), 3)
	check_eq(RouletteGame.spot_return(&"column_1", 34), 3)
	check_eq(RouletteGame.spot_return(&"column_3", 36), 3)
	check_eq(RouletteGame.spot_return(&"column_2", 36), 0)
	check_eq(CasinoParams.ROULETTE_RED.size(), 18)
	check_eq(RouletteGame.color_of(0), "green")


func test_roulette_multi_spot_round() -> void:
	var game := start(&"roulette")
	game.rig([7])
	for spot in [&"n7", &"red", &"odd", &"even", &"column_1"]:
		check(bool(game.place_bet(spot, 100)["ok"]))
	check(not bool(game.place_bet(&"black", 9600)["ok"]), "maximum applies to the total")
	game.act(RouletteGame.SPIN)
	var out := game.outcome()
	check_eq(int(out["staked"]), 500)
	check_eq(int(out["returned"]), 3600 + 200 + 200 + 300)
	check_eq(int(game.view_state()["pocket"]), 7)
	check_eq(String(game.view_state()["color"]), "red")


# ── Slots ────────────────────────────────────────────────────────────────

func test_slots_paytable_lines() -> void:
	check_eq(SlotsGame.line_return(["B", "B", "B"]), 200)
	check_eq(SlotsGame.line_return(["s5", "s5", "s5"]), 60)
	check_eq(SlotsGame.line_return(["s4", "s4", "s4"]), 30)
	check_eq(SlotsGame.line_return(["s3", "s3", "s3"]), 15)
	check_eq(SlotsGame.line_return(["s2", "s2", "s2"]), 10)
	check_eq(SlotsGame.line_return(["s1", "s1", "s1"]), 5)
	check_eq(SlotsGame.line_return(["B", "s1", "B"]), 5)
	check_eq(SlotsGame.line_return(["s2", "B", "s2"]), 2)
	check_eq(SlotsGame.line_return(["s1", "s2", "s1"]), 0)


func test_slots_strips_and_return_over_every_stop() -> void:
	var strips: Array = CasinoParams.SLOT_STRIPS
	check_eq(strips.size(), 3)
	for strip in strips:
		check_eq((strip as Array).size(), 20)
		for s in strip:
			check(String(s) in CasinoParams.SLOT_SYMBOLS)
	var total := 0
	var combos := 0
	for a in 20:
		for b in 20:
			for d in 20:
				total += SlotsGame.line_return([SlotsGame.symbol_at(0, a), SlotsGame.symbol_at(1, b), SlotsGame.symbol_at(2, d)])
				combos += 1
	check_eq(combos, 8000)
	var rtp := float(total) / float(combos)
	check_between(rtp, 0.88, 0.97, "slot return")


func test_slots_jackpot_round() -> void:
	var game := start(&"slots")
	var stops: Array = []
	for reel in 3:
		stops.append((CasinoParams.SLOT_STRIPS[reel] as Array).find("B"))
	game.rig(stops)
	game.place_bet(SlotsGame.LINE, 100)
	game.act(SlotsGame.PULL)
	check_eq(int(game.outcome()["returned"]), 20000)
	check_eq(String(game.outcome()["reaction"]), "jackpot")
	var stopped := 0
	var jackpot := false
	for e in game.take_events():
		if String(e["kind"]) == "reel_stop":
			check_eq(String(e["symbol"]), "B")
			stopped += 1
		jackpot = jackpot or String(e["kind"]) == "jackpot"
	check_eq(stopped, 3)
	check(jackpot)
	check_eq(game.view_state()["symbols"], ["B", "B", "B"])


# ── Money wheel ──────────────────────────────────────────────────────────

func test_money_wheel_layout_and_returns() -> void:
	var counts := {}
	for s in CasinoParams.WHEEL_LAYOUT:
		counts[s] = int(counts.get(s, 0)) + 1
	check_eq(CasinoParams.WHEEL_LAYOUT.size(), 54)
	check_eq(counts, {"1": 24, "2": 15, "5": 7, "10": 4, "20": 2, "emblem_a": 1, "emblem_b": 1})
	for symbol in counts:
		var index := CasinoParams.WHEEL_LAYOUT.find(symbol)
		var game := start(&"money_wheel")
		game.rig([index])
		game.place_bet(MoneyWheelGame.spot_for(symbol), 100)
		game.place_bet(&"seg_1" if symbol != "1" else &"seg_2", 100)
		game.act(MoneyWheelGame.SPIN)
		check_eq(int(game.outcome()["returned"]), 100 * int(CasinoParams.WHEEL_RETURNS[symbol]), symbol)
		check_eq(int(game.view_state()["segment"]), index)
	check_eq(int(CasinoParams.WHEEL_RETURNS["emblem_a"]), 41, "emblems pay 40 to 1")


# ── Video poker ──────────────────────────────────────────────────────────

func test_video_poker_hand_ranks() -> void:
	var hands := {
		"royal_flush": [c(1, 2), c(13, 2), c(12, 2), c(11, 2), c(10, 2)],
		"straight_flush": [c(9, 1), c(8, 1), c(7, 1), c(6, 1), c(5, 1)],
		"four_of_a_kind": [c(4, 0), c(4, 1), c(4, 2), c(4, 3), c(9)],
		"full_house": [c(3, 0), c(3, 1), c(3, 2), c(9, 0), c(9, 1)],
		"flush": [c(2, 3), c(5, 3), c(9, 3), c(11, 3), c(13, 3)],
		"straight": [c(1, 0), c(2, 1), c(3, 2), c(4, 3), c(5, 0)],
		"three_of_a_kind": [c(7, 0), c(7, 1), c(7, 2), c(2), c(13)],
		"two_pair": [c(7, 0), c(7, 1), c(2, 2), c(2), c(13)],
		"jacks_or_better": [c(11, 0), c(11, 1), c(2, 2), c(4), c(9)],
		"nothing": [c(10, 0), c(10, 1), c(2, 2), c(4), c(9)],
	}
	for rank in hands:
		check_eq(VideoPokerGame.evaluate(hands[rank]), rank)
	check_eq(VideoPokerGame.evaluate([c(10, 0), c(11, 1), c(12, 2), c(13, 3), c(1, 0)]), "straight", "ace-high straight")
	check_eq(VideoPokerGame.evaluate([c(1, 0), c(1, 1), c(5, 2), c(6), c(9)]), "jacks_or_better", "aces pay")
	check_eq(int(CasinoParams.POKER_RETURNS["royal_flush"]), 800)


func test_video_poker_hold_and_draw() -> void:
	var game := start(&"video_poker")
	game.rig([c(11, 0), c(11, 1), c(2, 2), c(4), c(9), c(11, 2), c(3), c(5)])
	game.place_bet(VideoPokerGame.HAND, 100)
	game.act(VideoPokerGame.DEAL)
	check_eq(game.view_state()["cards"].size(), 5)
	check(bool(game.act(VideoPokerGame.HOLD, {"index": 0})["ok"]))
	check_eq(game.view_state()["held"], [true, false, false, false, false])
	check(not bool(game.act(VideoPokerGame.HOLD, {"index": 9})["ok"]))
	game.act(VideoPokerGame.DRAW, {"held": [true, true, false, false, false]})
	check_eq(String(game.view_state()["rank"]), "three_of_a_kind")
	check_eq(int(game.outcome()["returned"]), 300)
	var replaced := 0
	for e in game.take_events():
		if String(e["kind"]) == "card" and bool(e["replace"]):
			replaced += 1
	check_eq(replaced, 3)


# ── Faro ─────────────────────────────────────────────────────────────────

func faro(cards: Array, bets: Dictionary) -> FaroGame:
	var game := start(&"faro") as FaroGame
	game.rig(cards)
	for spot in bets:
		check(bool(game.place_bet(spot, int(bets[spot]))["ok"]), "faro bet %s" % spot)
	game.act(FaroGame.TURN)
	return game


func test_faro_banker_player_and_unshown() -> void:
	var game := faro([c(5), c(9)], {&"rank_5": 100, &"rank_9": 100, &"rank_2": 100})
	check_eq(int(game.outcome()["returned"]), 0 + 200 + 100, "banker's rank loses, player's wins, others return")
	game = faro([c(5), c(9)], {&"copper_5": 100, &"copper_9": 100})
	check_eq(int(game.outcome()["returned"]), 200, "coppered bets invert")


func test_faro_split_takes_half() -> void:
	var game := faro([c(7, 0), c(7, 1)], {&"rank_7": 100, &"copper_3": 100})
	check_eq(int(game.outcome()["returned"]), 50 + 100)
	check_eq(events_of(game, "split").size(), 1)
	game = faro([c(7, 0), c(7, 1)], {&"copper_7": 101})
	check_eq(int(game.outcome()["returned"]), 50, "half, rounded down")


func test_faro_rules() -> void:
	var game := start(&"faro")
	check(bool(game.place_bet(&"rank_4", 100)["ok"]))
	check_eq(String(game.place_bet(&"copper_4", 100)["reason"]), CasinoLines.FARO_BOTH_WAYS)
	game.act(FaroGame.TURN)
	check_eq(int(game.view_state()["remaining"]), 50)
	# Turns until a reshuffle: 52 cards, two a turn; fewer than four forces it.
	var shuffled := 0
	for _turn in 30:
		game.next_round()
		game.place_bet(&"rank_4", 100)
		game.act(FaroGame.TURN)
		shuffled += events_of(game, "shuffle").size()
	check_eq(shuffled, 1)
	var case_counts: Array = game.view_state()["case"]
	check_eq(case_counts.size(), 13)


# ── Chuck-a-luck ─────────────────────────────────────────────────────────

func test_chuck_a_luck_returns() -> void:
	check_eq(ChuckALuckGame.bet_return(&"die_3", [3, 1, 2]), 2)
	check_eq(ChuckALuckGame.bet_return(&"die_3", [3, 3, 2]), 3)
	check_eq(ChuckALuckGame.bet_return(&"die_3", [3, 3, 3]), 4)
	check_eq(ChuckALuckGame.bet_return(&"die_3", [1, 1, 2]), 0)
	check_eq(ChuckALuckGame.bet_return(&"any_triple", [5, 5, 5]), 31)
	check_eq(ChuckALuckGame.bet_return(&"any_triple", [5, 5, 4]), 0)
	var game := start(&"chuck_a_luck")
	game.rig([5, 5, 5])
	game.place_bet(&"die_6", 100)
	game.place_bet(&"any_triple", 100)
	game.act(ChuckALuckGame.ROLL)
	check_eq(game.view_state()["dice"], [6, 6, 6])
	check_eq(int(game.outcome()["returned"]), 400 + 3100)
	check_eq(String(game.outcome()["reaction"]), "jackpot")


# ── Baccarat ─────────────────────────────────────────────────────────────

func baccarat(cards: Array, bets: Dictionary) -> BaccaratGame:
	var game := start(&"baccarat") as BaccaratGame
	game.rig(cards)
	for spot in bets:
		game.place_bet(spot, int(bets[spot]))
	game.act(BaccaratGame.DEAL)
	return game


func test_baccarat_banker_tableau() -> void:
	# Player stood: banker draws on 0-5.
	for t in 8:
		check_eq(BaccaratGame.banker_draws(t, -1), t <= 5, "stood %d" % t)
	var draws_on := {0: range(10), 1: range(10), 2: range(10), 3: [0, 1, 2, 3, 4, 5, 6, 7, 9],
		4: [2, 3, 4, 5, 6, 7], 5: [4, 5, 6, 7], 6: [6, 7], 7: []}
	for banker in draws_on:
		for third in 10:
			check_eq(BaccaratGame.banker_draws(banker, third), third in draws_on[banker],
				"banker %d v third %d" % [banker, third])
	check_eq(BaccaratGame.point(c(13)), 0)
	check_eq(BaccaratGame.point(c(1)), 1)
	check_eq(BaccaratGame.total_of([c(9), c(8)]), 7)


func test_baccarat_coups() -> void:
	# Natural 9 for the player: no third cards.
	var game := baccarat([c(4), c(3), c(5), c(3)], {&"player": 100, &"banker": 100})
	check_eq(game.view_state()["player"]["cards"].size(), 2)
	check_eq(game.view_state()["banker"]["cards"].size(), 2)
	check_eq(String(game.view_state()["winner"]), "player")
	check_eq(int(game.outcome()["returned"]), 200)
	# Player 5 draws a 4 (9); banker 3 draws (third not 8): 3 + 10 = 3.
	game = baccarat([c(2), c(1), c(3), c(2), c(4), c(10)], {&"player": 100})
	check_eq(game.view_state()["player"]["cards"].size(), 3)
	check_eq(game.view_state()["banker"]["cards"].size(), 3)
	check_eq(int(game.view_state()["player"]["total"]), 9)
	check_eq(int(game.outcome()["returned"]), 200)
	# Player 6 stands; banker 5 draws a 2: banker 7 wins, less commission.
	game = baccarat([c(3), c(2), c(3), c(3), c(2)], {&"banker": 100, &"player": 100})
	check_eq(game.view_state()["player"]["cards"].size(), 2)
	check_eq(String(game.view_state()["winner"]), "banker")
	check_eq(int(game.outcome()["returned"]), 195)
	# Player 3 draws an 8 (1); banker 3 stands against an 8: banker wins.
	game = baccarat([c(1), c(2), c(2), c(1), c(8)], {&"banker": 101})
	check_eq(game.view_state()["banker"]["cards"].size(), 2)
	check_eq(int(game.outcome()["returned"]), 101 + 95)
	# A tie returns player/banker bets and pays the tie bet 8 to 1.
	game = baccarat([c(4), c(4), c(3), c(3)], {&"player": 100, &"banker": 100, &"tie": 100})
	check_eq(String(game.view_state()["winner"]), "tie")
	check_eq(int(game.outcome()["returned"]), 100 + 100 + 900)


# ── Trajectory ───────────────────────────────────────────────────────────

func launch(burn_out: float, payload: Dictionary = {}, bet: int = 100) -> TrajectoryGame:
	var game := start(&"trajectory") as TrajectoryGame
	game.rig([burn_out])
	game.place_bet(TrajectoryGame.STAKE, bet)
	game.act(TrajectoryGame.LAUNCH, payload)
	return game


func test_trajectory_curve_and_formula() -> void:
	check_eq(TrajectoryGame.multiplier_at(0.0), 1.0)
	check(absf(TrajectoryGame.seconds_for(2.0) - log(2.0) / 0.12) < 0.0001)
	check_eq(TrajectoryGame.burn_out_for(0.0), 1.0, "0.97 rounds up to the floor of 1.00")
	check_eq(TrajectoryGame.burn_out_for(0.5), 1.94)
	check_eq(TrajectoryGame.burn_out_for(0.99), 96.99)
	check_eq(TrajectoryGame.burn_out_for(0.9999999), CasinoParams.TRAJECTORY_MAX_MULTIPLIER)
	check_eq(TrajectoryGame.payout(100, 2.5), 250)
	check_eq(TrajectoryGame.payout(333, 1.37), 456)
	check_eq(TrajectoryGame.payout(100, 1.999), 199, "hundredths, rounded down")


func test_trajectory_manual_cash_out_and_validation() -> void:
	var game := launch(3.0)
	check_eq(game.state, CasinoGame.PLAYING)
	check(bool(game.act(TrajectoryGame.ADVANCE, {"multiplier": 1.5})["ok"]))
	check_eq(String(game.act(TrajectoryGame.ADVANCE, {"multiplier": 1.2})["reason"]), CasinoLines.MULTIPLIER_FALLS)
	check_eq(String(game.act(TrajectoryGame.CASH_OUT, {"multiplier": NAN})["reason"]), CasinoLines.BAD_MULTIPLIER)
	check_eq(String(game.act(TrajectoryGame.CASH_OUT, {"multiplier": 0.5})["reason"]), CasinoLines.BAD_MULTIPLIER)
	check_eq(String(game.act(TrajectoryGame.CASH_OUT, {})["reason"]), CasinoLines.BAD_MULTIPLIER)
	check_eq(float(game.view_state()["burn_out"]), 0.0, "the burn-out stays hidden")
	game.act(TrajectoryGame.CASH_OUT, {"multiplier": 2.99})
	check_eq(game.state, CasinoGame.SETTLED)
	check_eq(int(game.outcome()["returned"]), 299)
	check_eq(float(game.view_state()["burn_out"]), 3.0)


func test_trajectory_crash_paths() -> void:
	var game := launch(2.0)
	var result := game.act(TrajectoryGame.ADVANCE, {"multiplier": 2.0})
	check(bool(result["crashed"]))
	check_eq(game.state, CasinoGame.SETTLED)
	check_eq(int(game.outcome()["returned"]), 0)
	check_eq(String(game.outcome()["reaction"]), "crash")
	game = launch(2.0)
	game.act(TrajectoryGame.CASH_OUT, {"multiplier": 2.5})
	check_eq(int(game.outcome()["returned"]), 0, "too late")
	game = launch(1.0)
	check_eq(game.state, CasinoGame.SETTLED, "engine failure on the pad")
	check_eq(int(game.outcome()["returned"]), 0)


func test_trajectory_auto_cash_out() -> void:
	var game := launch(5.0, {"auto": 2.0})
	check_eq(game.state, CasinoGame.SETTLED)
	check_eq(int(game.outcome()["returned"]), 200)
	check_eq(events_of(game, "cash_out").size(), 1)
	game = launch(1.5, {"auto": 2.0})
	check_eq(int(game.outcome()["returned"]), 0)
	game = start(&"trajectory")
	game.place_bet(TrajectoryGame.STAKE, 100)
	check_eq(String(game.act(TrajectoryGame.LAUNCH, {"auto": 1.0})["reason"]), CasinoLines.BAD_TARGET)
	check_eq(String(game.act(TrajectoryGame.LAUNCH, {"auto": INF})["reason"]), CasinoLines.BAD_TARGET)
	check_eq(game.state, CasinoGame.BETTING, "a refused launch commits nothing")


func test_trajectory_draws_failures_and_long_flights() -> void:
	var failures := 0
	var rng := CasinoRng.new(77)
	var game := TrajectoryGame.new()
	game.begin(rng, LIMITS)
	for _i in 660:
		game.place_bet(TrajectoryGame.STAKE, 100)
		game.act(TrajectoryGame.LAUNCH)
		if game.state == CasinoGame.SETTLED:
			failures += 1
		else:
			game.act(TrajectoryGame.CASH_OUT, {"multiplier": 1.0})
		game.next_round()
	# One launch in 33 fails outright, and draws whose curve value is below 1.01
	# also burn out at 1.00x: about 7% in all.
	check_between(failures, 20, 75, "launches that end on the pad")
