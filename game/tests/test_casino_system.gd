# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const COMSTOCK := &"arcology_comstock"
const JUNCTION := &"arcology_junction"
const ORBIT := &"arcology_orbit"
const SAVE_PATH := "user://casino_roundtrip.sc2d"

var sim: Simulation
var funds_seen: Array[int] = []


func before_each() -> void:
	sim = make_simulation(flat_city(), 7)
	funds_seen.clear()
	sim.funds_changed.connect(_on_funds)


func after_each() -> void:
	sim.free()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _on_funds(value: int) -> void:
	funds_seen.append(value)


func paper() -> SimSystem:
	return sim.get_system(&"newspaper")


func pending_kinds() -> Array:
	var out: Array = []
	for story in paper().call("pending"):
		out.append(StringName(String(story["kind"])))
	return out


func test_registered_after_rewards_and_scheduled_before_the_paper() -> void:
	check(sim.casino() is CasinoSystem)
	check_eq(sim.casino().key, &"casino")
	var keys: Array = []
	for s in sim.systems:
		keys.append(s.key)
	check_eq(keys.find(&"casino"), keys.find(&"rewards") + 1)
	var day: Array = Simulation.SCHEDULE[22]
	check(day.find(&"casino") >= 0 and day.find(&"casino") < day.find(&"newspaper"))


func test_limits_and_refusals() -> void:
	var casino := sim.casino()
	check_eq(casino.limits(COMSTOCK, 20000), {"minimum": 100, "maximum": 10000})
	check_eq(casino.limits(COMSTOCK, 4000), {"minimum": 100, "maximum": 4000})
	check_eq(casino.limits(ORBIT, 500000), {"minimum": 1000, "maximum": 100000})
	check_eq(casino.limits(&"nowhere", 20000), {"minimum": 0, "maximum": 0})
	check(bool(casino.can_play(COMSTOCK, 100)["ok"]))
	var poor := casino.can_play(ORBIT, 999)
	check(not bool(poor["ok"]))
	check_eq(String(poor["reason"]), "The cage doesn't extend credit to the city. Tables here start at $1,000; the treasury has $999.",
		"the refusal names the minimum and the treasury")
	var unknown := casino.can_play(&"nowhere", 20000)
	check(not bool(unknown["ok"]))
	check_eq(String(unknown["reason"]), CasinoLines.UNKNOWN_RESORT)


func test_commit_settle_refund_publish_funds_while_paused() -> void:
	check_eq(sim.speed, GameClock.Speed.PAUSED)
	var day := sim.city.day
	check(sim.casino_commit(COMSTOCK, &"blackjack", 500))
	check_eq(sim.city.funds, 19500)
	check_eq(funds_seen, [19500], "the debit is published at once")
	sim.casino_settle(COMSTOCK, &"blackjack", 500, 1250)
	check_eq(sim.city.funds, 20750)
	check_eq(funds_seen, [19500, 20750])
	var row := sim.casino().ledger(COMSTOCK)
	check_eq(int(row["rounds"]), 1)
	check_eq(int(row["staked"]), 500)
	check_eq(int(row["returned"]), 1250)
	check_eq(int(row["best_win"]), 750)
	check_eq(int(row["worst_loss"]), 0)
	check_eq(int(row["month_net"]), 750)
	check_eq(int(row["year_net"]), 750)
	check_eq(int(row["last_day"]), day)
	check(sim.casino_commit(COMSTOCK, &"faro", 1000))
	sim.casino_refund(COMSTOCK, &"faro", 1000)
	check_eq(sim.city.funds, 20750)
	check_eq(int(sim.casino().ledger(COMSTOCK)["rounds"]), 1, "a refund is not a round")
	check_eq(sim.city.day, day, "the clock does not move")


func test_commit_refusals_leave_the_treasury_alone() -> void:
	check(not sim.casino_commit(COMSTOCK, &"blackjack", 20001), "more than the treasury")
	check(not sim.casino_commit(COMSTOCK, &"blackjack", 0))
	check(not sim.casino_commit(COMSTOCK, &"blackjack", -50))
	check(not sim.casino_commit(&"nowhere", &"blackjack", 100))
	check(not sim.casino_commit(JUNCTION, &"faro", 100), "faro is not played at the Roundhouse")
	check(not sim.casino_commit(COMSTOCK, &"pachinko", 100))
	check_eq(sim.city.funds, 20000)
	check(funds_seen.is_empty())
	check(sim.casino_commit(COMSTOCK, &"blackjack", 20000), "the whole treasury may be staked")
	check_eq(sim.city.funds, 0)
	sim.casino_settle(COMSTOCK, &"blackjack", 20000, -5)
	check_eq(sim.city.funds, 0, "a negative return credits nothing")
	var empty := Simulation.new()
	check(not empty.casino_commit(COMSTOCK, &"blackjack", 100))
	empty.free()


func test_debut_reported_once() -> void:
	sim.casino_commit(JUNCTION, &"roulette", 300)
	check(not (&"casino_debut" in pending_kinds()), "no story until the round settles")
	sim.casino_settle(JUNCTION, &"roulette", 300, 0)
	check_eq(pending_kinds().count(&"casino_debut"), 1)
	check(sim.casino().has_debuted())
	sim.casino_commit(COMSTOCK, &"slots", 100)
	sim.casino_settle(COMSTOCK, &"slots", 100, 200)
	check_eq(pending_kinds().count(&"casino_debut"), 1, "only the first round ever")
	for story in paper().call("pending"):
		if String(story["kind"]) == "casino_debut":
			check_eq(String(story["args"]["place"]), "Silver Junction")


func test_day_22_stories_and_month_reset() -> void:
	sim.city.funds = 200000
	sim.casino_commit(COMSTOCK, &"blackjack", 10000)
	sim.casino_settle(COMSTOCK, &"blackjack", 10000, 40000)
	sim.casino_commit(ORBIT, &"trajectory", 26000)
	sim.casino_settle(ORBIT, &"trajectory", 26000, 0)
	sim.casino_commit(JUNCTION, &"slots", 1000)
	sim.casino_settle(JUNCTION, &"slots", 1000, 0)
	var guard := 0
	while guard < 30:
		guard += 1
		var dom := sim.clock.day_of_month()
		sim.advance_day()
		if dom == 22:
			break
	var issue: Dictionary = paper().call("latest_issue")
	check_eq(int(issue.get("day", -1)), 22)
	var kinds: Array = []
	var headlines: Array = []
	for story in issue["stories"]:
		kinds.append(String(story["kind"]))
		headlines.append(String(story["headline"]))
	check("casino_windfall" in kinds, "windfall printed: %s" % [kinds])
	check("casino_losses" in kinds, "losses printed: %s" % [kinds])
	for i in kinds.size():
		if kinds[i] == "casino_windfall" or kinds[i] == "casino_losses":
			check(not String(headlines[i]).contains("{"), "filled: %s" % headlines[i])
			check(not String(issue["stories"][i]["body"]).contains("{"))
	var windfall_body := ""
	var losses_body := ""
	for story in issue["stories"]:
		if String(story["kind"]) == "casino_windfall":
			windfall_body = String(story["body"])
		elif String(story["kind"]) == "casino_losses":
			losses_body = String(story["body"])
	check(windfall_body.contains("Comstock Grand") and windfall_body.contains("$30,000"), windfall_body)
	check(losses_body.contains("Desert Orbit") and losses_body.contains("$26,000"), losses_body)
	for resort in ResortThemes.keys():
		check_eq(int(sim.casino().ledger(resort)["month_net"]), 0, "month resets: %s" % resort)
	check_eq(int(sim.casino().ledger(COMSTOCK)["year_net"]), 30000, "the year keeps counting")
	check_eq(int(sim.casino().ledger(JUNCTION)["year_net"]), -1000)
	# Another month with small play reports nothing.
	sim.casino_commit(COMSTOCK, &"blackjack", 100)
	sim.casino_settle(COMSTOCK, &"blackjack", 100, 200)
	sim.advance_days(25)
	for story in (paper().call("latest_issue") as Dictionary)["stories"]:
		check(not String(story["kind"]).begins_with("casino_w") and String(story["kind"]) != "casino_losses",
			"no story for small play")


func test_year_reset_and_totals() -> void:
	var ctx := make_context(flat_city(100000))
	var casino := CasinoSystem.new()
	casino.commit_round(ctx, COMSTOCK, &"roulette", 1000)
	casino.settle_round(ctx, COMSTOCK, &"roulette", 1000, 36000)
	casino.commit_round(ctx, ORBIT, &"slots", 2000)
	casino.settle_round(ctx, ORBIT, &"slots", 2000, 0)
	var total := casino.total_ledger()
	check_eq(int(total["rounds"]), 2)
	check_eq(int(total["staked"]), 3000)
	check_eq(int(total["returned"]), 36000)
	check_eq(int(total["best_win"]), 35000)
	check_eq(int(total["worst_loss"]), -2000)
	check_eq(int(total["year_net"]), 33000)
	casino.monthly(ctx)
	check_eq(int(casino.total_ledger()["month_net"]), 0)
	check_eq(int(casino.total_ledger()["year_net"]), 33000)
	casino.yearly(ctx)
	check_eq(int(casino.total_ledger()["year_net"]), 0)
	check_eq(int(casino.total_ledger()["rounds"]), 2, "lifetime totals stay")
	check_eq(ctx.city.funds, 100000 - 3000 + 36000)


func test_save_load_round_trip_and_old_saves() -> void:
	sim.casino_commit(COMSTOCK, &"blackjack", 400)
	sim.casino_settle(COMSTOCK, &"blackjack", 400, 1000)
	sim.casino_commit(ORBIT, &"trajectory", 2000)
	sim.casino_settle(ORBIT, &"trajectory", 2000, 0)
	var before_comstock := sim.casino().ledger(COMSTOCK)
	var before_orbit := sim.casino().ledger(ORBIT)
	check_eq(SaveFormat.save(SAVE_PATH, sim.city, sim.snapshot()), OK)
	var loaded := SaveFormat.load(SAVE_PATH)
	check(bool(loaded["ok"]), String(loaded.get("error", "")))
	var restored := make_simulation(loaded["city"], 7)
	restored.restore(loaded["snapshot"])
	check_eq(restored.city.funds, sim.city.funds)
	check_eq(restored.casino().ledger(COMSTOCK), before_comstock)
	check_eq(restored.casino().ledger(ORBIT), before_orbit)
	check(restored.casino().has_debuted())
	# A snapshot from before the casino existed loads empty ledgers.
	var old: Dictionary = (loaded["snapshot"] as Dictionary).duplicate(true)
	(old["systems"] as Dictionary).erase("casino")
	var fresh := make_simulation(flat_city(), 7)
	fresh.restore(old)
	check_eq(int(fresh.casino().total_ledger()["rounds"]), 0)
	check(not fresh.casino().has_debuted())
	var odd := CasinoSystem.new()
	odd.load({"ledgers": {"arcology_comstock": {"rounds": "7"}, "nowhere": {"rounds": 3}}, "debut": true})
	check_eq(int(odd.ledger(COMSTOCK)["rounds"]), 7)
	check_eq(int(odd.ledger(COMSTOCK)["staked"]), 0, "missing fields default to zero")
	check_eq(int(odd.total_ledger()["rounds"]), 7, "unknown resorts are dropped")
	odd.load({"ledgers": "garbage"})
	check_eq(int(odd.total_ledger()["rounds"]), 0)
	restored.free()
	fresh.free()


func test_play_leaves_the_simulation_random_stream_alone() -> void:
	var state := sim.rng.state()
	var seed_value := sim.rng.seed_value()
	var rng := CasinoRng.new(31)
	for kind in ResortThemes.games(COMSTOCK):
		var game := ResortThemes.make_game(kind)
		game.begin(rng, sim.casino().limits(COMSTOCK, sim.city.funds))
		for _round in 3:
			game.place_bet(game.spots()[0]["id"], 100)
			var result := game.act(game.commit_action())
			check(sim.casino_commit(COMSTOCK, kind, int(result["stake"])), "commit %s" % kind)
			var guard := 0
			while game.state == CasinoGame.PLAYING and guard < 10:
				guard += 1
				if kind == &"blackjack":
					game.act(BlackjackGame.STAND)
				elif kind == &"video_poker":
					game.act(VideoPokerGame.DRAW)
				elif kind == &"trajectory":
					game.act(TrajectoryGame.CASH_OUT, {"multiplier": 1.0})
			var out := game.outcome()
			sim.casino_settle(COMSTOCK, kind, int(out["staked"]), int(out["returned"]))
			game.next_round()
	check_eq(int(sim.casino().ledger(COMSTOCK)["rounds"]), 18)
	check_eq(sim.rng.state(), state, "casino play never draws from the simulation stream")
	check_eq(sim.rng.seed_value(), seed_value)
	var ledger := sim.casino().ledger(COMSTOCK)
	check_eq(sim.city.funds, 20000 + int(ledger["returned"]) - int(ledger["staked"]))


func test_snapshot_without_play_matches_except_the_casino_key() -> void:
	var other := make_simulation(flat_city(), 7)
	other.advance_days(30)
	sim.advance_days(30)
	check_eq(sim.rng.state(), other.rng.state())
	var a: Dictionary = sim.snapshot()
	var b: Dictionary = other.snapshot()
	check_eq(a, b, "an idle casino changes nothing")
	check(a["systems"].has("casino"))
	other.free()
