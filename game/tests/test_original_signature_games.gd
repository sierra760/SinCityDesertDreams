# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"

const NAMES := ["vault_circuit", "alibi_route", "velvet_encore", "afterglow_forecast", "last_bank", "dust_pool"]

func test_original_engines_exist() -> void:
	for name in NAMES:
		check(FileAccess.file_exists("res://scripts/casino/games/%s_game.gd" % name), "%s original engine exists" % name)

func start(name: String, stake: int = 1000) -> CasinoGame:
	var script: Script = load("res://scripts/casino/games/%s_game.gd" % name)
	var game: CasinoGame = script.new()
	game.begin(CasinoRng.new(55), {"minimum": 1, "maximum": 1000000})
	game.place_bet(StringName(game.spots()[0]["id"]), stake)
	return game

func finish(game: CasinoGame) -> void:
	for _i in 8:
		if game.state != CasinoGame.PLAYING:
			break
		var action: StringName = game.call("background_action")
		check(action != &"", "playing round has a closing policy")
		check(bool(game.act(action)["ok"]))
	check_eq(game.state, CasinoGame.SETTLED)

func test_single_commit_settlement_and_repeat_contract() -> void:
	for name in NAMES:
		var game := start(name)
		check(not bool(game.act(&"invented")["ok"]))
		var opened := game.act(game.commit_action())
		check(bool(opened["ok"]))
		check_eq(int(opened["stake"]), 1000)
		check(not bool(game.act(game.commit_action())["ok"]), "cannot recommit")
		check(not bool(game.place_bet(StringName(game.spots()[0]["id"]), 10)["ok"]))
		finish(game)
		var settlements := 0
		for event in game.take_events():
			if event["kind"] == "settle":
				settlements += 1
		check_eq(settlements, 1)
		check_eq(int(game.outcome()["net"]), int(game.outcome()["returned"]) - 1000)
		check(not bool(game.act(&"bank")["ok"]))
		check(bool(game.act(CasinoGame.REBET)["ok"]))
		check_eq(game.state, CasinoGame.BETTING)
		check_eq(game.total_staked(), 1000)
		game.act(CasinoGame.CLEAR)
		check_eq(game.total_staked(), 0)
		for field in ["title", "phase_label", "instruction", "status", "choices", "rules_text"]:
			check(game.view_state().has(field), "%s: %s view" % [name, field])
		check(JSON.parse_string(JSON.stringify(game.view_state())) != null)

func test_vault_locks_and_risk() -> void:
	var game := start("vault_circuit")
	game.rig([79, 54, 79])
	game.act(&"case_vault")
	check(not bool(game.act(&"bank")["ok"]))
	check_eq(int(game.act(&"quiet")["stake"]), 0)
	check_eq(int(game.view_state()["currentbank"]), 1200)
	game.act(&"force")
	check_eq(int(game.view_state()["currentbank"]), 2040)
	game.act(&"quiet")
	check_eq(int(game.outcome()["returned"]), 2448)
	game = start("vault_circuit")
	game.rig([80])
	game.act(&"case_vault")
	game.act(&"quiet")
	check_eq(int(game.outcome()["returned"]), 0)

func test_alibi_route_coverage_terms() -> void:
	for route in [&"direct", &"night", &"express"]:
		for cover in [&"bare", &"covered"]:
			for draw in [0, 999]:
				var game := start("alibi_route")
				game.rig([draw])
				game.act(&"depart")
				check(not bool(game.act(cover)["ok"]))
				game.act(route)
				check(not bool(game.act(route)["ok"]))
				var multiplier := 1 if route == &"direct" else (2 if route == &"night" else 4)
				game.act(cover)
				var expected := multiplier * 1000 if draw == 0 else 0
				if cover == &"covered":
					expected = multiplier * 800 if draw == 0 else 250
				check_eq(int(game.outcome()["returned"]), expected)

func test_velvet_bow_duels_and_crowd_rotation() -> void:
	var game := start("velvet_encore")
	game.act(&"take_stage")
	game.act(&"bow")
	check_eq(int(game.outcome()["returned"]), 960)
	game = start("velvet_encore")
	game.rig([60, 40, 90])
	game.act(&"take_stage")
	game.act(&"rose") # audience fan, rose wins
	check_eq(int(game.view_state()["bank"]), 1248)
	game.act(&"fan") # rotated preference [20,50,30], audience fan: tie
	check_eq(int(game.view_state()["bank"]), 1248)
	game.act(&"rose") # rotated [30,20,50], spotlight beats rose
	check_eq(int(game.outcome()["returned"]), 0)

func test_forecast_correlated_portfolio_and_visible_class() -> void:
	var game := start("afterglow_forecast", 300)
	game.place_bet(&"pulse", 200)
	game.place_bet(&"surge", 100)
	var view := game.view_state()
	var expected := 0
	for quote in view["forecast_quotes"]:
		var wager := int(game.bets().get(StringName(quote["id"]), 0))
		expected += int(game.call("scale", wager, int(quote["gross_basis"]), 1000))
	game.rig([0])
	check_eq(int(game.act(&"observe")["stake"]), 600)
	check_eq(int(game.outcome()["returned"]), expected)
	game = start("afterglow_forecast")
	game.rig([999])
	game.act(&"observe")
	check_eq(int(game.outcome()["returned"]), 0)

func test_bank_depletion_contract_counts_and_pool_index_rig() -> void:
	var game := start("last_bank")
	game.rig([0, 0, 0, 0]) # A,2,3 of clubs, then 4
	game.act(&"draft")
	check_eq(int(game.view_state()["offers"][0]["rank"]), 1)
	game.act(&"draft_0")
	var counts: Dictionary = game.view_state()["remainingcounts"]
	check_eq(int(counts["rise"]), 46)
	check_eq(int(counts["fall"]), 0)
	check_eq(int(counts["match"]), 3)
	check(not bool(game.act(&"fall")["ok"]))
	game.act(&"rise")
	check_eq(int(game.outcome()["returned"]), 1022)
	check_eq(int(game.view_state()["bankcard"]["rank"]), 4)
	game = start("last_bank")
	game.rig([0, 0, 0, 0])
	game.act(&"draft")
	game.act(&"draft_0")
	game.act(&"match")
	check_eq(int(game.outcome()["returned"]), 0)

func test_dust_public_pledges_and_agreement() -> void:
	for share in range(1, 4):
		var game := start("dust_pool")
		game.rig([0, 1, 3, 0])
		game.act(&"convene")
		check_eq(game.view_state()["crewbids"], [1, 2, 4])
		check_eq(int(game.view_state()["pot"]), 12000)
		var quote: Dictionary = game.view_state()["claim_quotes"][share - 1]
		game.act(StringName("share_%d" % share))
		check_eq(int(game.outcome()["returned"]), int(quote["returned"]))
	var lost := start("dust_pool")
	lost.rig([0, 0, 0, 999])
	lost.act(&"convene")
	lost.act(&"share_3")
	check_eq(int(lost.outcome()["returned"]), 0)

func test_exact_conditional_expectations_never_exceed_96_percent() -> void:
	# Enumerate each local choice's sample space, including integer rounding.
	for stake in [1, 5, 7, 10, 100, 1003, 250000]:
		for terms in [[80, 120], [55, 170]]:
			var paid := int(stake * int(terms[1]) / 100)
			check(paid * int(terms[0]) * 100 <= stake * 96 * 100)
		for route in [[960, 1], [480, 2], [240, 4]]:
			var p := int(route[0])
			var multiplier := int(route[1])
			check(stake * multiplier * p <= stake * 960)
			var covered := int(stake * multiplier * 80 / 100)
			var rescue := int(stake * 25 / 100)
			check(covered * p + rescue * (1000 - p) <= stake * 960)
		for weights in [[50, 30, 20], [20, 50, 30], [30, 20, 50]]:
			for lead in 3:
				var win_weight := int(weights[(lead + 1) % 3])
				var tie_weight := int(weights[lead])
				check(int(stake * 130 / 100) * win_weight + stake * tie_weight <= stake * 96)
		for chance in [950, 650, 250, 900, 550, 180, 920, 700, 350]:
			var basis := int(960000 / chance)
			check(int(stake * basis / 1000) * chance <= stake * 960)
		for winners in range(1, 50):
			check(int(stake * 960 * 49 / (1000 * winners)) * winners * 1000 <= stake * 960 * 49)
		for first in range(1, 5):
			for second in range(1, 5):
				for third in range(1, 5):
					var total := first + second + third
					for share in range(1, 4):
						var chance := int(960 * (total + share) / (share * (total + 5)))
						var paid := int(stake * (total + 5) * share / (total + share))
						check(paid * chance <= stake * 960)

func test_seeded_determinism_and_background_actions_have_no_extra_debits() -> void:
	for name in NAMES:
		var first := start(name)
		var second := start(name)
		first.act(first.commit_action())
		second.act(second.commit_action())
		for _step in 8:
			check_eq(first.view_state(), second.view_state())
			if first.state != CasinoGame.PLAYING:
				break
			var action := StringName(first.call("background_action"))
			check_eq(int(first.act(action)["stake"]), 0)
			check_eq(int(second.act(action)["stake"]), 0)
		check_eq(first.state, CasinoGame.SETTLED)
		check_eq(first.outcome(), second.outcome())

func test_enumerated_actual_vault_and_alibi_outcomes() -> void:
	var stake := 1003
	for method in [&"quiet", &"force"]:
		var sum := 0
		for draw in 100:
			var game := start("vault_circuit", stake)
			game.rig([draw])
			game.act(&"case_vault")
			game.act(method)
			if game.state == CasinoGame.PLAYING:
				game.act(&"bank")
			sum += int(game.outcome()["returned"])
		check(sum * 100 <= stake * 96 * 100)
	for route in [&"direct", &"night", &"express"]:
		for coverage in [&"bare", &"covered"]:
			var sum := 0
			for draw in 1000:
				var game := start("alibi_route", stake)
				game.rig([draw])
				game.act(&"depart")
				game.act(route)
				game.act(coverage)
				sum += int(game.outcome()["returned"])
			check(sum <= stake * 960)

func test_enumerated_actual_forecast_and_crew_outcomes() -> void:
	var stake := 1003
	for forecast in 3:
		for spot in [&"steady", &"pulse", &"surge"]:
			var sum := 0
			for draw in 1000:
				var script: Script = load("res://scripts/casino/games/afterglow_forecast_game.gd")
				var game: CasinoGame = script.new()
				game.rig([forecast, draw])
				game.begin(CasinoRng.new(55), {"minimum": 1, "maximum": 1000000})
				game.place_bet(spot, stake)
				game.act(&"observe")
				sum += int(game.outcome()["returned"])
			check(sum <= stake * 960)
	for total in range(3, 13):
		var bids: Array = [0, 0, 0]
		var extra := total - 3
		for i in 3:
			bids[i] = mini(3, extra)
			extra -= int(bids[i])
		for share in range(1, 4):
			var sum := 0
			for draw in 1000:
				var game := start("dust_pool", stake)
				game.rig([bids[0], bids[1], bids[2], draw])
				game.act(&"convene")
				game.act(StringName("share_%d" % share))
				sum += int(game.outcome()["returned"])
			check(sum <= stake * 960)

func test_enumerated_card_contracts_use_actual_remaining_deck() -> void:
	var stake := 1003
	for anchor_rank in range(1, 14):
		for contract in [&"rise", &"fall", &"match"]:
			var sum := 0
			var supported := false
			for draw in 49:
				var game := start("last_bank", stake)
				# First offer is clubs anchor; next two are diamonds A,2.
				game.rig([anchor_rank - 1, 12, 12, draw])
				game.act(&"draft")
				game.act(&"draft_0")
				var winners := int(game.view_state()["remainingcounts"][String(contract)])
				if winners == 0:
					check(not bool(game.act(contract)["ok"]))
					continue
				supported = true
				game.act(contract)
				var bank_rank := int(game.view_state()["bankcard"]["rank"])
				var wins := (bank_rank > anchor_rank if contract == &"rise" else (bank_rank < anchor_rank if contract == &"fall" else bank_rank == anchor_rank))
				check_eq(int(game.outcome()["returned"]) > 0, wins)
				sum += int(game.outcome()["returned"])
			if supported:
				check(sum * 1000 <= stake * 960 * 49)

func test_enumerated_actual_encores_match_visible_crowd() -> void:
	var stake := 1003
	var opening_bank := int(stake * 96 / 100)
	for stage in 3:
		for lead in [&"rose", &"fan", &"spotlight"]:
			var sum := 0
			var wins := 0
			var ties := 0
			for draw in 100:
				var game := start("velvet_encore", stake)
				var rigs: Array = []
				if stage >= 1:
					rigs.append(0) # first crowd rose, tie with rose
				if stage >= 2:
					rigs.append(50) # second crowd fan, tie with fan
				rigs.append(draw)
				game.rig(rigs)
				game.act(&"take_stage")
				if stage >= 1:
					game.act(&"rose")
				if stage >= 2:
					game.act(&"fan")
				var crowd: Dictionary = game.view_state()["audienceweights"]
				game.act(lead)
				var result := String(game.view_state()["lasttokens"]["result"])
				if result == "win":
					wins += 1
				elif result == "tie":
					ties += 1
				if game.state == CasinoGame.PLAYING:
					game.act(&"bow")
				sum += int(game.outcome()["returned"])
				if draw == 99:
					var defeated := &"fan" if lead == &"rose" else (&"spotlight" if lead == &"fan" else &"rose")
					check_eq(wins, int(crowd[String(defeated)]))
					check_eq(ties, int(crowd[String(lead)]))
			check(sum <= opening_bank * 96)

func test_next_round_clears_decisions_and_outcome() -> void:
	for name in NAMES:
		var game := start(name)
		game.act(game.commit_action())
		finish(game)
		var events := game.take_events()
		check_eq(String(events.back()["kind"]), "settle")
		check_eq(int(events.back()["returned"]), int(game.outcome()["returned"]))
		game.act(CasinoGame.NEXT)
		check_eq(game.state, CasinoGame.BETTING)
		check(game.outcome().is_empty())
		check(game.bets().is_empty())
		var view := game.view_state()
		match name:
			"vault_circuit":
				check_eq(int(view["locklevel"]), 0)
				check_eq(int(view["currentbank"]), 0)
			"alibi_route":
				check_eq(String(view["route"]), "")
				check_eq(String(view["coverage"]), "")
			"velvet_encore":
				check_eq(int(view["roundindex"]), 0)
				check_eq(int(view["bank"]), 0)
				check(view["lasttokens"].is_empty())
			"afterglow_forecast":
				check_eq(int(view["draw"]), -1)
				check_eq(view["forecast_quotes"].size(), 3)
			"last_bank":
				check(view["offers"].is_empty())
				check(view["candidatecard"].is_empty())
				check(view["bankcard"].is_empty())
			"dust_pool":
				check(view["crewbids"].is_empty())
				check_eq(int(view["pot"]), 0)

func test_primary_closing_choices_are_enabled_and_do_not_repeat_risk() -> void:
	var game := start("vault_circuit")
	game.rig([0])
	game.act(&"case_vault")
	game.act(&"quiet")
	var primary: StringName = &""
	for action in game.actions():
		if bool(action["primary"]) and bool(action["enabled"]):
			primary = action["id"]
	check_eq(primary, &"bank")
	game = start("last_bank")
	game.rig([12, 0, 0])
	game.act(&"draft")
	game.act(&"draft_0")
	primary = &""
	for action in game.actions():
		if bool(action["primary"]) and bool(action["enabled"]):
			primary = action["id"]
	check_eq(primary, &"fall")
