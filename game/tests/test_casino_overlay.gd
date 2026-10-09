# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The gaming-resort table overlay: every table at every display size,
## keyboard play, multi-spot bets and the treasury sequencing.
extends "res://tests/exploration/async_test_case.gd"

const COMSTOCK := &"arcology_comstock"
const JUNCTION := &"arcology_junction"
const BOULDER := &"arcology_boulder"
const ORBIT := &"arcology_orbit"
const START_FUNDS := 500000

var sim: Simulation
var layout: DisplayLayout
var overlay: CasinoTableOverlay
var funds_seen: Array[int] = []
var closed_count := 0
var settled: Array[Dictionary] = []
var _original_size: Vector2i


func before_all() -> void:
	_original_size = root.size
	CasinoTableOverlay.animation_scale = 0.0


func after_all() -> void:
	CasinoTableOverlay.animation_scale = 1.0
	root.content_scale_factor = 1.0
	root.size = _original_size


func before_each() -> void:
	sim = make_simulation(flat_city(START_FUNDS), 7)
	sim.set_speed(GameClock.Speed.PAUSED)
	funds_seen.clear()
	settled.clear()
	closed_count = 0
	sim.funds_changed.connect(func(value: int) -> void: funds_seen.append(value))
	layout = DisplayLayout.new()
	root.add_child(layout)
	layout.bind(root)
	_display(Vector2i(1280, 800), 1.0)
	overlay = CasinoTableOverlay.new()
	root.add_child(overlay)
	overlay.bind_layout(layout)
	overlay.closed.connect(func() -> void: closed_count += 1)
	overlay.round_settled.connect(func(_r: StringName, _g: StringName, outcome: Dictionary) -> void: settled.append(outcome))


func after_each() -> void:
	overlay.free()
	layout.free()
	sim.free()
	root.content_scale_factor = 1.0
	await process_frame


func _display(drawable: Vector2i, backing: float, safe := Rect2i(), mobile := false) -> void:
	root.size = drawable
	layout.refresh_with_metrics(drawable, backing, safe, 0, mobile)


func _settle_frames(frames: int = 3) -> void:
	for _i in frames:
		await process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release)


static func _card(rank: int, suit: int) -> Dictionary:
	return CasinoDeck.card(rank, suit)


## Every visible control lies inside the logical rectangle and every button is
## at least 44 units each way.
func _check_layout(context: String) -> void:
	var bounds := layout.logical_rect().grow(0.5)
	for node: Node in overlay.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or control.name == "Shade":
			continue
		var rect := control.get_global_rect()
		if not bounds.encloses(rect):
			check(false, "%s: %s at %s leaves %s" % [context, control.name, rect, bounds])
			return
		if control is Button:
			check(rect.size.x >= 44.0 and rect.size.y >= 44.0, "%s: %s is %s" % [context, control.name, rect.size])
	var focused := root.gui_get_focus_owner()
	check(focused != null and overlay.is_ancestor_of(focused), "%s: focus stays on the table" % context)


## The resort name, the floor · game line and the dealer's line are never
## cut short: no ellipsis or clipping, and every wrapped line is shown.
func _check_text_whole(context: String) -> void:
	for label: Label in [overlay.chrome.resort_label, overlay.chrome.place_label, overlay.patter_label]:
		check(label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and not label.clip_text, "%s: %s never trims" % [context, label.name])
		check(label.autowrap_mode != TextServer.AUTOWRAP_OFF, "%s: %s wraps" % [context, label.name])
		check_eq(label.get_visible_line_count(), label.get_line_count(), "%s: every line of %s shows" % [context, label.name])
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		for word: String in label.text.split(" ", false):
			if font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x + 0.5:
				check(false, "%s: %s too narrow for '%s' (%s)" % [context, label.name, word, label.size.x])
				return


func _longest_line(voice: StringName) -> String:
	var longest := ""
	for event: StringName in CasinoLines.EVENTS:
		for line: String in CasinoLines.lines(voice, event):
			if line.length() > longest.length(): longest = line
	return longest


func test_every_table_fits_each_display_size() -> void:
	var sizes := [
		[Vector2i(1280, 800), 1.0, Rect2i(), false, "desktop"],
		[Vector2i(640, 400), 1.0, Rect2i(), false, "compact"],
		[Vector2i(2560, 1600), 2.0, Rect2i(), false, "retina"],
		[Vector2i(1170, 2532), 3.0, Rect2i(0, 141, 1170, 2289), true, "phone portrait"],
		[Vector2i(2532, 1170), 3.0, Rect2i(141, 0, 2250, 1107), true, "phone landscape"],
	]
	for spec: Array in sizes:
		_display(spec[0], spec[1], spec[2], spec[3])
		for resort: StringName in ResortThemes.keys():
			for game: StringName in ResortThemes.games(resort):
				overlay.open(sim, resort, game, CasinoRng.new(11))
				await _settle_frames()
				_check_layout("%s %s %s" % [spec[4], resort, game])
				_check_text_whole("%s %s %s" % [spec[4], resort, game])
				overlay._set_patter(_longest_line(ResortThemes.voice(resort)))
				await _settle_frames()
				_check_text_whole("%s %s %s patter" % [spec[4], resort, game])
				check(overlay.stage.size.x > 100.0 and overlay.stage.size.y > 100.0, "%s %s: the table has room" % [spec[4], game])
				overlay.close()
	check_eq(closed_count, 4 * 6 * 5)


func test_full_blackjack_hand_by_keyboard() -> void:
	overlay.open(sim, COMSTOCK, &"blackjack", CasinoRng.new(3))
	await _settle_frames()
	overlay.game.rig([_card(10, 0), _card(9, 1), _card(8, 2), _card(8, 3)])
	_key(KEY_1)
	check_eq(overlay.game.bets(), {&"main": 100}, "1 puts the smallest chip on the bet")
	_key(KEY_EQUAL)
	check_eq(overlay.game.total_staked(), 200, "plus adds the selected chip")
	_key(KEY_MINUS)
	check_eq(overlay.game.total_staked(), 100, "minus takes it back")
	_key(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.PLAYING, "Enter deals")
	check_eq(sim.city.funds, START_FUNDS - 100)
	check(overlay.chrome.leave_button.disabled, "no leaving mid-hand")
	_key(KEY_S)
	check_eq(overlay.game.state, CasinoGame.SETTLED, "S stands and the dealer plays out")
	check_eq(String(overlay.game.outcome()["reaction"]), "win")
	check_eq(sim.city.funds, START_FUNDS + 100)
	check_eq(overlay.session_net(), 100)
	check(not overlay.chrome.leave_button.disabled)
	check(overlay.chrome.treasury_label.text.contains("500,100"), overlay.chrome.treasury_label.text)
	check(overlay.patter_label.text.begins_with("The assayer"), overlay.patter_label.text)
	_key(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.BETTING, "Enter starts the next round")
	_key(KEY_R)
	check_eq(overlay.game.total_staked(), 100, "R repeats the last bet")
	check_eq(settled.size(), 1)


func test_blackjack_double_and_split_debit_their_extra_stakes() -> void:
	overlay.open(sim, JUNCTION, &"blackjack", CasinoRng.new(5))
	overlay.game.rig([_card(8, 0), _card(6, 1), _card(8, 2), _card(10, 3), _card(3, 0), _card(2, 1), _card(10, 0)])
	overlay.press_chip(0)
	overlay.perform_action(&"deal")
	check_eq(sim.city.funds, START_FUNDS - 250)
	overlay.perform_action(&"split")
	check_eq(sim.city.funds, START_FUNDS - 500, "the split hand is debited")
	check_eq(overlay.committed(), 500)
	overlay.perform_action(&"double")
	check_eq(sim.city.funds, START_FUNDS - 750, "the double is debited")
	check_eq(overlay.game.total_staked(), 750)
	if overlay.game.state == CasinoGame.PLAYING:
		overlay.perform_action(&"stand")
	check_eq(overlay.game.state, CasinoGame.SETTLED)
	var outcome := overlay.game.outcome()
	check_eq(int(outcome["staked"]), 750)
	check_eq(sim.city.funds, START_FUNDS - 750 + int(outcome["returned"]))
	check_eq(sim.casino().ledger(JUNCTION)["staked"], 750)


func test_roulette_multi_spot_round() -> void:
	overlay.open(sim, COMSTOCK, &"roulette", CasinoRng.new(9))
	await _settle_frames()
	for spot: StringName in [&"n17", &"black", &"dozen_2", &"red"]:
		overlay.bet_on(spot)
	check_eq(overlay.game.total_staked(), 400)
	overlay.game.rig([17])
	overlay.perform_action(&"spin")
	check_eq(overlay.game.state, CasinoGame.SETTLED)
	check_eq(int(overlay.game.outcome()["returned"]), 3600 + 200 + 300)
	check_eq(sim.city.funds, START_FUNDS + 3700)
	for spot: StringName in [&"n17", &"black", &"dozen_2"]:
		check(overlay.stage._winners.has(spot), "%s marked as a winner" % spot)
	check(not overlay.stage._winners.has(&"red"))
	# Arrow keys move the selection over the drawn layout.
	overlay.perform_action(&"next")
	await _settle_frames()
	overlay.select_spot(&"n17")
	_key(KEY_RIGHT)
	check_ne(overlay.stage.selected_spot, &"n17", "arrows choose another spot")


func test_slots_pull_pays_a_jackpot_with_a_flourish() -> void:
	overlay.open(sim, ORBIT, &"slots", CasinoRng.new(1))
	overlay.press_chip(0)
	overlay.game.rig([8, 9, 7])
	overlay.perform_action(&"pull")
	check_eq(String(overlay.game.outcome()["reaction"]), "jackpot")
	check_eq(sim.city.funds, START_FUNDS - 1000 + 200000)
	check(bool(overlay.stage._banner.get("flourish", false)), "jackpot flourish")
	check_eq(String(overlay.stage._banner.get("text", "")), "Jackpot")


func test_video_poker_hold_and_draw() -> void:
	overlay.open(sim, BOULDER, &"video_poker", CasinoRng.new(4))
	await _settle_frames()
	overlay.game.rig([_card(1, 3), _card(1, 2), _card(5, 0), _card(9, 1), _card(13, 0),
		_card(1, 1), _card(2, 0), _card(3, 2)])
	overlay.press_chip(1)
	_key(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.PLAYING)
	_key(KEY_1)
	_key(KEY_2)
	check_eq(overlay.game.view_state()["held"], [true, true, false, false, false], "keys 1 and 2 hold the aces")
	_key(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.SETTLED, "Enter draws")
	check_eq(String(overlay.game.view_state()["rank"]), "three_of_a_kind")
	check_eq(int(overlay.game.outcome()["returned"]), 1000 * 3)
	check_eq(sim.city.funds, START_FUNDS - 1000 + 3000)


func test_trajectory_auto_and_manual_cash_out() -> void:
	overlay.open(sim, ORBIT, &"trajectory", CasinoRng.new(2))
	overlay.set_auto_target(2.0)
	overlay.press_chip(0)
	overlay.game.rig([5.0])
	overlay.perform_action(&"launch")
	check_eq(overlay.game.state, CasinoGame.SETTLED, "the automatic target decides at once")
	check_eq(int(overlay.game.outcome()["returned"]), 2000)
	check_eq(sim.city.funds, START_FUNDS + 1000)
	check_eq(String((overlay.stage as TrajectoryStage)._ending), "cash_out")
	overlay.perform_action(&"next")
	overlay.set_auto_target(0.0)
	overlay.press_chip(0)
	overlay.game.rig([3.0])
	overlay.perform_action(&"launch")
	check_eq(overlay.game.state, CasinoGame.PLAYING)
	check((overlay.stage as TrajectoryStage).live, "the climb is live")
	check(overlay.chrome.leave_button.disabled)
	overlay.perform_action(&"advance", {"multiplier": 1.5})
	_key(KEY_SPACE)
	check_eq(overlay.game.state, CasinoGame.SETTLED, "Space cashes out")
	check_eq(sim.city.funds, START_FUNDS + 1500, "cashed out at the 1.50x reached")
	overlay.perform_action(&"next")
	overlay.press_chip(0)
	overlay.game.rig([1.8])
	overlay.perform_action(&"launch")
	overlay.perform_action(&"advance", {"multiplier": 1.9})
	check_eq(overlay.game.state, CasinoGame.SETTLED, "climbing past the burn-out crashes")
	check_eq(String(overlay.game.outcome()["reaction"]), "crash")
	check_eq(sim.city.funds, START_FUNDS + 500)


func test_treasury_signals_follow_commit_and_settle() -> void:
	overlay.open(sim, COMSTOCK, &"money_wheel", CasinoRng.new(8))
	funds_seen.clear()
	overlay.bet_on(&"seg_2")
	check(funds_seen.is_empty(), "placing chips never touches the treasury")
	overlay.game.rig([2])
	overlay.perform_action(&"spin")
	check_eq(funds_seen.size(), 2, "one debit, one credit")
	check_eq(funds_seen[0], START_FUNDS - 100)
	check_eq(funds_seen[1], START_FUNDS + 200)
	check_eq(sim.casino().ledger(COMSTOCK)["rounds"], 1)
	check_eq(settled.size(), 1)


func test_leave_is_refused_while_playing_and_force_close_refunds() -> void:
	overlay.open(sim, COMSTOCK, &"blackjack", CasinoRng.new(6))
	overlay.game.rig([_card(10, 0), _card(9, 1), _card(5, 2), _card(8, 3)])
	overlay.press_chip(2)
	overlay.perform_action(&"deal")
	check_eq(sim.city.funds, START_FUNDS - 500)
	overlay.close()
	check(overlay.is_open(), "Leave is refused mid-hand")
	overlay.request_leave()
	check(overlay.is_open(), "so is Escape")
	check_eq(overlay.patter_label.text, CasinoLines.ROUND_OPEN)
	check(overlay.round_in_progress())
	overlay.force_close()
	check(not overlay.is_open())
	check_eq(sim.city.funds, START_FUNDS, "the committed stake comes back")
	check_eq(sim.casino().ledger(COMSTOCK)["rounds"], 0, "a refunded round is not played")
	check_eq(closed_count, 1)


func test_bets_beyond_the_treasury_are_refused_without_a_debit() -> void:
	overlay.open(sim, COMSTOCK, &"chuck_a_luck", CasinoRng.new(1))
	overlay.bet_on(&"die_3")
	overlay.bet_on(&"die_4")
	sim.city.funds = 150
	var result := overlay.perform_action(&"roll")
	check(not bool(result["ok"]))
	check_eq(String(result["reason"]), CasinoLines.NO_CREDIT)
	check_eq(overlay.game.state, CasinoGame.BETTING)
	check_eq(sim.city.funds, 150)
	check_eq(overlay.patter_label.text, CasinoLines.NO_CREDIT)


func test_faro_coppered_bets_and_baccarat_spots() -> void:
	overlay.open(sim, COMSTOCK, &"faro", CasinoRng.new(2))
	await _settle_frames()
	overlay.bet_on(&"rank_5")
	overlay.bet_on(&"copper_9")
	overlay.game.rig([_card(9, 0), _card(5, 1)])
	overlay.perform_action(&"turn")
	check_eq(int(overlay.game.outcome()["returned"]), 400, "rank 5 wins and the coppered 9 wins")
	check(overlay.stage._winners.has(&"rank_5") and overlay.stage._winners.has(&"copper_9"))
	overlay.close()
	overlay.open(sim, BOULDER, &"baccarat", CasinoRng.new(2))
	await _settle_frames()
	var rect := overlay.stage.spot_rect(&"tie")
	check(rect.size.x >= 44.0, "the tie box is drawn")
	overlay.stage._gui_input(_press_at(overlay.stage.to_local_point(rect.get_center())))
	check_eq(overlay.game.bets(), {&"tie": 500}, "pressing the tie box bets on it")


static func _press_at(point: Vector2) -> InputEventMouseButton:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	return press


func test_tab_stays_on_the_table_and_rules_toggle() -> void:
	overlay.open(sim, JUNCTION, &"chuck_a_luck", CasinoRng.new(1))
	await _settle_frames()
	for _i in 30:
		_key(KEY_TAB)
		var focused := root.gui_get_focus_owner()
		check(focused != null and overlay.is_ancestor_of(focused), "Tab keeps focus on the table")
	overlay.chrome.rules_button.button_pressed = true
	check(overlay.rules_panel.visible)
	check(overlay.rules_label.text.contains("Any triple pays 30 to 1"), overlay.rules_label.text)
	overlay.request_leave()
	check(not overlay.rules_panel.visible, "Escape closes the rules first")
	check(overlay.is_open())


func test_animations_play_and_skip_at_normal_speed() -> void:
	CasinoTableOverlay.animation_scale = 1.0
	overlay.open(sim, COMSTOCK, &"roulette", CasinoRng.new(9))
	overlay.bet_on(&"red")
	overlay.perform_action(&"spin")
	check_eq(overlay.game.state, CasinoGame.SETTLED, "the result is decided at once")
	check_eq(sim.city.funds, START_FUNDS - 100 + int(overlay.game.outcome()["returned"]), "and settled at once")
	check(overlay.stage.is_busy(), "the wheel is still turning")
	check_eq(overlay.chrome.treasury_label.text, "Treasury $499,900", "the readout waits for the ball")
	await _settle_frames(5)
	check(overlay.stage.is_busy())
	_key(KEY_ENTER)
	check(not overlay.stage.is_busy(), "Enter skips the animation")
	check(overlay.chrome.treasury_label.text.contains(UIFactory.commafy(sim.city.funds)))
	CasinoTableOverlay.animation_scale = 0.0


func test_enter_on_a_focused_button_activates_that_button() -> void:
	overlay.open(sim, COMSTOCK, &"blackjack", CasinoRng.new(3))
	await _settle_frames()
	overlay.press_chip(0)
	check_eq(overlay.game.total_staked(), 100, "fixture: a bet is placed")
	overlay.chrome.leave_button.grab_focus()
	_key(KEY_ENTER)
	await _settle_frames()
	check_eq(closed_count, 1, "Enter on Leave table leaves")
	check(not overlay.is_open())
	check_eq(sim.city.funds, START_FUNDS, "nothing was dealt or debited")
	# The table's own default focus still plays the main action.
	overlay.open(sim, COMSTOCK, &"blackjack", CasinoRng.new(3))
	await _settle_frames()
	overlay.press_chip(0)
	_key(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.PLAYING, "Enter deals from the default focus")


func test_round_settled_waits_for_the_result_to_play() -> void:
	CasinoTableOverlay.animation_scale = 1.0
	overlay.open(sim, ORBIT, &"slots", CasinoRng.new(7))
	await _settle_frames()
	overlay.press_chip(0)
	overlay.game.rig([8, 9, 7])
	overlay.perform_action(&"pull")
	check_eq(overlay.game.state, CasinoGame.SETTLED, "fixture: the pull settles at once")
	check(overlay.stage.is_busy(), "fixture: the reels are still spinning")
	check_eq(settled.size(), 0, "nobody outside the table hears the result yet")
	check_eq(sim.city.funds, START_FUNDS - 1000 + int(overlay.game.outcome()["returned"]), "the treasury is credited at once")
	overlay.stage.skip()
	check_eq(settled.size(), 1, "the result is announced when it has played")
	CasinoTableOverlay.animation_scale = 0.0


func test_a_refused_double_is_refunded() -> void:
	overlay.open(sim, COMSTOCK, &"blackjack", CasinoRng.new(3))
	overlay.game.rig([_card(2, 0), _card(9, 1), _card(3, 2), _card(8, 3), _card(4, 0)])
	overlay.press_chip(0)
	overlay.perform_action(&"deal")
	overlay.perform_action(&"hit")
	check_eq(overlay.game.state, CasinoGame.PLAYING, "fixture: 2+3+4 is still in play")
	funds_seen.clear()
	var result := overlay.perform_action(&"double")
	check(not bool(result.get("ok", true)), "no double after three cards")
	check_eq(sim.city.funds, START_FUNDS - 100, "the double's stake came back")
	check_eq(overlay.committed(), 100, "only the opening stake is riding")
	check_eq(overlay.game.total_staked(), 100)


func test_a_launch_holds_its_climb_while_the_window_is_away() -> void:
	CasinoTableOverlay.animation_scale = 1.0
	overlay.open(sim, ORBIT, &"trajectory", CasinoRng.new(2))
	await _settle_frames()
	overlay.press_chip(0)
	overlay.game.rig([50.0])
	overlay.perform_action(&"launch")
	overlay.stage.skip()
	var rocket := overlay.stage as TrajectoryStage
	check(rocket.live, "fixture: the climb is live")
	await _settle_frames(4)
	overlay.set_clock_held(true)
	var held := rocket.flight_seconds
	await _settle_frames(8)
	check_eq(rocket.flight_seconds, held, "the climb stands still while the window is away")
	overlay.set_clock_held(false)
	await _settle_frames(8)
	check_gt(rocket.flight_seconds, held, "the climb continues from the same point")
	overlay.perform_action(&"cash_out")
	check_eq(overlay.game.state, CasinoGame.SETTLED)
	overlay.stage.skip()
	CasinoTableOverlay.animation_scale = 0.0


func test_chip_faces_are_reused_between_refreshes() -> void:
	overlay.open(sim, COMSTOCK, &"slots", CasinoRng.new(1))
	var chip := overlay.bet_bar.chip_buttons[2]
	var face := chip.get_theme_stylebox("normal")
	overlay.press_chip(0)
	overlay.press_chip(0)
	check(chip.get_theme_stylebox("normal") == face, "an unchanged chip keeps its face")
	overlay.press_chip(2)
	check(chip.get_theme_stylebox("normal") != face, "selecting the chip restyles it")


func _echo(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = true
	root.push_input(event)


func _player_cards() -> int:
	var hands: Array = overlay.game.view_state().get("hands", [])
	return (hands[0]["cards"] as Array).size() if not hands.is_empty() else 0


func test_enter_never_hits_and_held_keys_do_not_repeat() -> void:
	overlay.open(sim, COMSTOCK, &"blackjack", CasinoRng.new(3))
	await _settle_frames()
	# Player 10+7 = 17 against the dealer's 9+8 = 17; a fifth card would bust.
	overlay.game.rig([_card(10, 0), _card(9, 1), _card(7, 2), _card(8, 3), _card(10, 1)])
	_key(KEY_1)
	_echo(KEY_1)
	_echo(KEY_1)
	check_eq(overlay.game.total_staked(), 100, "a held digit adds one chip, not one per repeat")
	_echo(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.BETTING, "a repeated Enter never deals")
	_key(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.PLAYING, "Enter deals")
	var hit: Button = overlay.bet_bar.action_buttons.get(&"hit", null)
	check(hit != null and hit.visible, "fixture: Hit is offered")
	check(root.gui_get_focus_owner() != hit, "focus does not land on Hit after the deal")
	check_eq(overlay.bet_bar.primary_button(), overlay.bet_bar.action_buttons.get(&"stand", null), "Stand is the main action in a hand")
	_echo(KEY_ENTER)
	_echo(KEY_H)
	check_eq(_player_cards(), 2, "repeats of Enter and H draw nothing")
	check_eq(overlay.game.state, CasinoGame.PLAYING)
	_key(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.SETTLED, "Enter stands")
	check_eq(_player_cards(), 2, "Enter never drew a card")
	check_eq(String(overlay.game.outcome()["reaction"]), "push", "17 stands against 17")
	check_eq(sim.city.funds, START_FUNDS)
	# A mouse click on Hit leaves focus there; Enter still stands, not hits.
	overlay.perform_action(&"next")
	overlay.game.rig([_card(10, 0), _card(9, 1), _card(7, 2), _card(8, 3), _card(10, 1)])
	overlay.press_chip(0)
	overlay.perform_action(&"deal")
	hit.grab_focus()
	_key(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.SETTLED, "Enter on a focused Hit stands")
	check_eq(_player_cards(), 2)
	check(overlay.rules_label.text.contains("Enter never draws a card"), "the rules say what Enter does")


# Guards against: every repeated key swallowed at the table, so holding an
# arrow no longer stepped across the roulette layout.
func test_held_arrows_keep_stepping_but_held_action_keys_do_not() -> void:
	overlay.open(sim, COMSTOCK, &"roulette", CasinoRng.new(9))
	await _settle_frames()
	overlay.select_spot(&"n17")
	_key(KEY_RIGHT)
	var first := overlay.stage.selected_spot
	check_ne(first, &"n17", "fixture: an arrow moves the selection")
	_echo(KEY_RIGHT)
	check_ne(overlay.stage.selected_spot, first, "a held arrow keeps stepping across the spots")
	var held := InputEventKey.new()
	held.keycode = KEY_TAB
	held.physical_keycode = KEY_TAB
	held.pressed = true
	held.echo = true
	check(not overlay.handle_key(held), "a held Tab passes through to move focus")
	for code: Key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE, KEY_1, KEY_KP_3, KEY_H, KEY_R, KEY_A]:
		held.keycode = code
		held.physical_keycode = code
		check(overlay.handle_key(held), "a held %s is swallowed" % OS.get_keycode_string(code))
	var staked := overlay.game.total_staked()
	_echo(KEY_1)
	check_eq(overlay.game.total_staked(), staked, "a repeated digit adds no chip")
	_echo(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.BETTING, "a repeated Enter never spins")


func test_enter_after_clicking_a_chip_plays_instead_of_betting_again() -> void:
	overlay.open(sim, COMSTOCK, &"roulette", CasinoRng.new(9))
	await _settle_frames()
	check_eq(overlay.stage.selected_spot, &"red", "a first chip goes on Red, not on zero")
	check(overlay.bet_bar.spot_label.text.begins_with("Chips go on Red"), overlay.bet_bar.spot_label.text)
	var chip := overlay.bet_bar.chip_buttons[1]
	chip.grab_focus()
	chip.pressed.emit()
	check_eq(overlay.game.bets(), {&"red": 200}, "the clicked chip goes on Red")
	check_eq(root.gui_get_focus_owner(), chip, "fixture: the clicked chip holds focus")
	overlay.game.rig([17])
	_key(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.SETTLED, "Enter spins")
	check_eq(int(overlay.game.outcome()["staked"]), 200, "the stake is unchanged by Enter")
	check_eq(sim.city.funds, START_FUNDS - 200)
	overlay.close()
	overlay.open(sim, COMSTOCK, &"money_wheel", CasinoRng.new(9))
	check_eq(overlay.stage.selected_spot, &"seg_1", "the money wheel starts on its lowest odds")


func test_same_bet_after_a_result_starts_the_next_round() -> void:
	overlay.open(sim, COMSTOCK, &"roulette", CasinoRng.new(9))
	await _settle_frames()
	overlay.bet_on(&"black")
	overlay.game.rig([17])
	overlay.perform_action(&"spin")
	check_eq(overlay.game.state, CasinoGame.SETTLED, "fixture: the spin settles")
	var shown := false
	for action: Dictionary in overlay.game.actions():
		shown = shown or (StringName(action["id"]) == CasinoGame.REBET and bool(action["enabled"]))
	check(shown, "Same bet is offered next to Next round")
	_key(KEY_R)
	check_eq(overlay.game.state, CasinoGame.BETTING, "R starts the next round")
	check_eq(overlay.game.bets(), {&"black": 100}, "with the same bets")
	overlay.game.rig([2])
	_key(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.SETTLED, "Enter spins again")
	check_eq(int(sim.casino().ledger(COMSTOCK)["rounds"]), 2)


func test_staking_over_half_the_treasury_asks_first() -> void:
	sim.city.funds = 8000
	overlay.open(sim, COMSTOCK, &"blackjack", CasinoRng.new(3))
	await _settle_frames()
	check(overlay.patter_label.text.contains("the treasury covers up to $8,000"), overlay.patter_label.text)
	overlay.game.rig([_card(10, 0), _card(9, 1), _card(7, 2), _card(8, 3)])
	_key(KEY_5)
	check_eq(overlay.game.total_staked(), 8000, "fixture: Max is the whole treasury")
	_key(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.BETTING, "the first Enter only asks")
	check_eq(sim.city.funds, 8000, "nothing is debited before the answer")
	check_eq(overlay.patter_label.text, CasinoLines.confirm_stake(8000, 8000, "Deal"))
	check(overlay.patter_label.text.begins_with("Bet $8,000 of the city's $8,000?"), overlay.patter_label.text)
	_key(KEY_BACKSPACE)
	_key(KEY_5)
	_key(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.BETTING, "changing the bets asks again")
	overlay.perform_action(&"deal")
	check_eq(overlay.game.state, CasinoGame.PLAYING, "a second press (here the Deal button) confirms")
	check_eq(sim.city.funds, 0)
	overlay.perform_action(&"stand")
	check_eq(sim.city.funds, 8000, "17 against 17 pushes")
	overlay.perform_action(&"next")
	overlay.press_chip(3)
	overlay.press_chip(3)
	overlay.press_chip(3)
	overlay.press_chip(3)
	check_eq(overlay.game.total_staked(), 4000)
	overlay.game.rig([_card(10, 0), _card(9, 1), _card(7, 2), _card(8, 3)])
	_key(KEY_ENTER)
	check_eq(overlay.game.state, CasinoGame.PLAYING, "half the treasury deals at once")


func test_a_treasury_below_the_minimum_says_both_amounts() -> void:
	sim.city.funds = 350
	overlay.open(sim, COMSTOCK, &"blackjack", CasinoRng.new(3))
	overlay.game.rig([_card(10, 0), _card(9, 1), _card(5, 2), _card(8, 3)])
	overlay.press_chip(4)
	check_eq(overlay.game.total_staked(), 350)
	overlay.perform_action(&"deal")
	overlay.perform_action(&"deal")
	overlay.perform_action(&"stand")
	check_eq(sim.city.funds, 0, "fixture: 15 loses to 17")
	overlay.perform_action(&"next")
	check_eq(overlay.patter_label.text, CasinoLines.no_credit(100, 0))
	check(overlay.patter_label.text.contains("$100") and overlay.patter_label.text.contains("$0"), overlay.patter_label.text)


func test_escape_finishes_the_result_before_leaving() -> void:
	CasinoTableOverlay.animation_scale = 1.0
	overlay.open(sim, COMSTOCK, &"roulette", CasinoRng.new(9))
	await _settle_frames()
	overlay.bet_on(&"red")
	overlay.perform_action(&"spin")
	check(overlay.stage.is_busy(), "fixture: the wheel is turning")
	overlay.request_leave()
	check(overlay.is_open(), "the first Escape stays at the table")
	check(not overlay.stage.is_busy(), "and shows the result")
	check(not String(overlay.stage._banner.get("text", "")).is_empty(), "the result banner is up")
	overlay.request_leave()
	check(not overlay.is_open(), "the second Escape leaves")
	CasinoTableOverlay.animation_scale = 0.0


func test_digit_chips_follow_the_key_position() -> void:
	overlay.open(sim, COMSTOCK, &"blackjack", CasinoRng.new(3))
	await _settle_frames()
	# AZERTY: the unshifted key in the 1 position types an ampersand.
	var event := InputEventKey.new()
	event.keycode = KEY_AMPERSAND
	event.physical_keycode = KEY_1
	event.pressed = true
	root.push_input(event)
	check_eq(overlay.game.total_staked(), 100, "the first digit key bets the smallest chip")
