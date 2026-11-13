# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A launch ridden to the highest multiplier on the board: the display stops
## there, the engine burns out there at the latest, and until then a cash-out
## is paid. The round always ends.
extends "res://tests/exploration/async_test_case.gd"

const ORBIT := &"arcology_orbit"
const START_FUNDS := 10000000
const CAP := CasinoParams.TRAJECTORY_MAX_MULTIPLIER
const LIMITS := {"minimum": 100, "maximum": 10000}

var sim: Simulation
var layout: DisplayLayout
var overlay: CasinoTableOverlay
var _original_size: Vector2i


func before_each() -> void:
	_original_size = root.size
	CasinoTableOverlay.animation_scale = 0.0
	sim = make_simulation(flat_city(START_FUNDS), 7)
	sim.set_speed(GameClock.Speed.PAUSED)
	layout = DisplayLayout.new()
	root.add_child(layout)
	layout.bind(root)
	root.size = Vector2i(1280, 800)
	layout.refresh_with_metrics(Vector2i(1280, 800), 1.0, Rect2i(), 0, false)
	overlay = CasinoTableOverlay.new()
	root.add_child(overlay)
	overlay.bind_layout(layout)


func after_each() -> void:
	overlay.free()
	layout.free()
	sim.free()
	CasinoTableOverlay.animation_scale = 1.0
	root.size = _original_size
	await process_frame


func launch(burn_out: float) -> TrajectoryGame:
	var game := TrajectoryGame.new()
	game.begin(CasinoRng.new(11), LIMITS)
	game.rig([burn_out])
	game.place_bet(TrajectoryGame.STAKE, 100)
	game.act(TrajectoryGame.LAUNCH)
	return game


## Launch at the table with a fixed burn-out and jump the live climb to
## `multiplier`, as if it had been ridden that far.
func ride_to(burn_out: float, multiplier: float) -> TrajectoryStage:
	overlay.open(sim, ORBIT, &"trajectory", CasinoRng.new(2))
	overlay.set_auto_target(0.0)
	overlay.press_chip(0)
	overlay.game.rig([burn_out])
	overlay.perform_action(&"launch")
	var rocket := overlay.stage as TrajectoryStage
	check(rocket.live, "fixture: the climb is live")
	rocket.flight_seconds = TrajectoryGame.seconds_for(multiplier)
	return rocket


## Run the climb at `hertz` frames a second until the round ends; the number
## of frames it took, or -1 if it was still going after `limit` frames.
func fly(rocket: TrajectoryStage, hertz: float, limit: int = 1200) -> int:
	for frame in limit:
		if overlay.game.state != CasinoGame.PLAYING:
			return frame
		rocket._process(1.0 / hertz)
	return -1 if overlay.game.state == CasinoGame.PLAYING else limit


func test_every_burn_out_near_the_cap_ends_the_round() -> void:
	for burn_out: float in [CAP, 999.99, 999.5, 999.0, 998.5, 998.0, 997.0]:
		for hertz: float in [30.0, 60.0, 120.0]:
			var before := sim.city.funds
			var rocket := ride_to(burn_out, 990.0)
			var frames := fly(rocket, hertz)
			var label := "burn-out %.2fx at %d Hz" % [burn_out, int(hertz)]
			check(frames >= 0, "%s: the engine burns out" % label)
			check_eq(overlay.game.state, CasinoGame.SETTLED, label)
			if overlay.game.state != CasinoGame.SETTLED:
				overlay.force_close()
				continue
			var outcome := overlay.game.outcome()
			check_eq(String(outcome["reaction"]), "crash", label)
			check_eq(int(outcome["returned"]), 0, "%s: a burn-out pays nothing" % label)
			check_eq(float(overlay.game.view_state()["burn_out"]), burn_out, "%s: at the multiplier drawn" % label)
			check_eq(sim.city.funds, before - int(outcome["staked"]), "%s: the stake is lost once" % label)
			check(rocket.multiplier <= CAP, "%s: the display never passes the cap (%.2f)" % [label, rocket.multiplier])
			check(overlay.can_leave(), "%s: the table can be left" % label)
			overlay.perform_action(&"next")
			overlay.close()


func test_display_stops_at_the_cap() -> void:
	var rocket := ride_to(CAP, 990.0)
	var highest := 0.0
	for frame in 600:
		rocket._process(1.0 / 60.0)
		highest = maxf(highest, rocket.multiplier)
	check(highest <= CAP, "the multiplier shown stops at the cap (%.2f)" % highest)
	check(rocket.current_multiplier() <= CAP)
	check_eq(overlay.game.state, CasinoGame.SETTLED, "and the round has ended there")
	check_eq(rocket.multiplier, CAP, "the burn-out is shown at the cap")
	overlay.perform_action(&"next")
	overlay.close()


func test_cash_out_just_below_the_cap_is_paid() -> void:
	var before := sim.city.funds
	var rocket := ride_to(CAP, 999.0)
	rocket._process(0.0)
	check_eq(overlay.game.state, CasinoGame.PLAYING, "still climbing below the cap")
	var shown := rocket.current_multiplier()
	check_between(shown, 998.99, 999.01)
	var result := overlay.perform_action(&"cash_out")
	check(bool(result["ok"]), String(result.get("reason", "")))
	check_eq(overlay.game.state, CasinoGame.SETTLED)
	var outcome := overlay.game.outcome()
	var stake := int(outcome["staked"])
	check_eq(int(outcome["returned"]), TrajectoryGame.payout(stake, shown), "paid at the multiplier shown")
	check_eq(sim.city.funds, before - stake + int(outcome["returned"]), "settled once")
	overlay.perform_action(&"next")
	overlay.close()


func test_cash_out_at_the_cap_is_too_late() -> void:
	var before := sim.city.funds
	var rocket := ride_to(CAP, 999.99)
	# One long frame carries the display from below the cap to it.
	rocket.multiplier = CAP
	var result := overlay.perform_action(&"cash_out")
	check(bool(result["ok"]), "the press is answered: " + String(result.get("reason", "")))
	check_eq(overlay.game.state, CasinoGame.SETTLED, "the round ends")
	check_eq(int(overlay.game.outcome()["returned"]), 0, "at the cap the engine has burnt out")
	check_eq(sim.city.funds, before - int(overlay.game.outcome()["staked"]))
	overlay.perform_action(&"next")
	overlay.close()


func test_leaving_the_app_at_the_cap_plays_the_launch_out() -> void:
	var before := sim.city.funds
	var rocket := ride_to(CAP, 999.99)
	rocket.multiplier = CAP
	var summary := overlay.resolve_round_now()
	check(not summary.is_empty(), "the launch is accounted for")
	check(not summary.contains("came back"), "it is played out, not refunded: " + summary)
	check_lt(sim.city.funds, before, "the stake is not returned by leaving")


func test_game_ends_any_report_at_or_past_the_cap() -> void:
	for report: float in [CAP, CAP + 0.01, 1234.56, 1.0e9]:
		for action: StringName in [TrajectoryGame.ADVANCE, TrajectoryGame.CASH_OUT]:
			for burn_out: float in [CAP, 998.37]:
				var game := launch(burn_out)
				check(bool(game.act(TrajectoryGame.ADVANCE, {"multiplier": 990.0})["ok"]))
				var result := game.act(action, {"multiplier": report})
				var label := "%s %.2fx against a %.2fx burn-out" % [action, report, burn_out]
				check(bool(result["ok"]), label)
				check(bool(result.get("crashed", false)), "%s is a burn-out" % label)
				check_eq(game.state, CasinoGame.SETTLED, label)
				if game.state == CasinoGame.SETTLED:
					check_eq(int(game.outcome()["returned"]), 0, label)
					check_eq(float(game.view_state()["burn_out"]), burn_out, label)


func test_reports_that_are_not_multipliers_are_still_refused() -> void:
	var game := launch(CAP)
	for bad: Variant in [NAN, INF, -INF, 0.5, -3.0]:
		check_eq(String(game.act(TrajectoryGame.CASH_OUT, {"multiplier": bad})["reason"]), CasinoLines.BAD_MULTIPLIER, str(bad))
		check_eq(String(game.act(TrajectoryGame.ADVANCE, {"multiplier": bad})["reason"]), CasinoLines.BAD_MULTIPLIER, str(bad))
	check_eq(String(game.act(TrajectoryGame.CASH_OUT, {})["reason"]), CasinoLines.BAD_MULTIPLIER)
	check_eq(game.state, CasinoGame.PLAYING, "a refused report changes nothing")
	check(bool(game.act(TrajectoryGame.ADVANCE, {"multiplier": 500.0})["ok"]))
	check_eq(String(game.act(TrajectoryGame.ADVANCE, {"multiplier": 499.0})["reason"]), CasinoLines.MULTIPLIER_FALLS)


func test_the_draw_and_the_payout_below_the_cap_are_unchanged() -> void:
	check_eq(TrajectoryGame.burn_out_for(0.0), 1.0)
	check_eq(TrajectoryGame.burn_out_for(0.5), 1.94)
	check_eq(TrajectoryGame.burn_out_for(0.99), 96.99)
	check_eq(TrajectoryGame.burn_out_for(0.9990299), 999.89)
	check_eq(TrajectoryGame.burn_out_for(0.999031), CAP)
	check_eq(TrajectoryGame.burn_out_for(0.9999999), CAP)
	var game := launch(CAP)
	game.act(TrajectoryGame.CASH_OUT, {"multiplier": 999.99})
	check_eq(game.state, CasinoGame.SETTLED)
	check_eq(int(game.outcome()["returned"]), 99999, "the highest cash-out is 999.99x")
	game = launch(500.0)
	game.act(TrajectoryGame.CASH_OUT, {"multiplier": 499.99})
	check_eq(int(game.outcome()["returned"]), 49999)
	game = launch(500.0)
	game.act(TrajectoryGame.CASH_OUT, {"multiplier": 500.0})
	check_eq(int(game.outcome()["returned"]), 0, "reaching the burn-out loses, as before")
	var rules := CasinoTableOverlay.rules_text(&"trajectory", ORBIT, {"minimum": 1000, "maximum": 100000})
	check(rules.contains("1,000x"), "the rules name the highest multiplier: " + rules)
