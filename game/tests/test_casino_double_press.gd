# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A second press on the button that started a round lands while the table is
## still animating and the buttons under the pointer have changed. Through
## real GUI routing on desktop, tablet and phone layouts, that press only
## finishes the animation; the next press plays.
extends "res://tests/exploration/async_test_case.gd"

const START_FUNDS := 10000000
const COMSTOCK := &"arcology_comstock"
const ORBIT := &"arcology_orbit"
const VELVET := &"arcology_velvet"
## Milliseconds between the two presses of a double click or double tap.
const DOUBLE_PRESS_MS := 150
## [label, drawable size, touch device]
const DISPLAYS := [
	["desktop 1280x800", Vector2i(1280, 800), false],
	["tablet 1024x768", Vector2i(1024, 768), true],
	["phone landscape 844x390", Vector2i(844, 390), true],
	["phone portrait 390x844", Vector2i(390, 844), true],
]

var sim: Simulation
var layout: DisplayLayout
var overlay: CasinoTableOverlay
var original_size: Vector2i
## The treasury when the table now open was sat down at.
var seated_funds := 0
## The clock the table's press guard reads, moved by hand.
var now_ms := 0


func before_each() -> void:
	original_size = root.size
	CasinoTableOverlay.animation_scale = 0.0
	sim = make_simulation(flat_city(START_FUNDS), 7)
	sim.set_speed(GameClock.Speed.PAUSED)
	layout = DisplayLayout.new()
	root.add_child(layout)
	layout.bind(root)
	overlay = CasinoTableOverlay.new()
	root.add_child(overlay)
	overlay.bind_layout(layout)
	now_ms = 5000
	overlay.press_clock = func() -> int: return now_ms


func after_each() -> void:
	overlay.free()
	layout.free()
	sim.free()
	CasinoTableOverlay.animation_scale = 1.0
	root.content_scale_factor = 1.0
	root.size = original_size
	await process_frame


func display(config: Array) -> void:
	var drawable: Vector2i = config[1]
	root.size = drawable
	layout.refresh_with_metrics(drawable, 1.0, Rect2i(), 0, bool(config[2]))
	await frames()


func frames(count: int = 6) -> void:
	for frame in count:
		await process_frame


func mouse(at: Vector2, pressed: bool, device: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.device = device
	root.push_input(event, true)


func finger(at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.pressed = pressed
	event.index = 0
	root.push_input(event, true)


## A mouse click, or on a touch device a tap with its synthesized mouse
## stream, a double press's interval after the one before.
func press(at: Vector2, touch: bool) -> void:
	now_ms += DOUBLE_PRESS_MS
	for pressed: bool in [true, false]:
		mouse(at, pressed, InputEvent.DEVICE_ID_EMULATION if touch else 0)
		if touch:
			finger(at, pressed)


func button(id: StringName) -> Button:
	return overlay.bet_bar.action_buttons.get(id, null)


func center_of(id: StringName) -> Vector2:
	var found := button(id)
	return found.get_global_rect().get_center() if found != null and found.is_visible_in_tree() else Vector2(-1, -1)


## The enabled action button at `point`, or "" when none is there.
func action_at(point: Vector2) -> StringName:
	for id: StringName in overlay.bet_bar.action_buttons:
		var found := button(id)
		if found.is_visible_in_tree() and not found.disabled and found.get_global_rect().has_point(point):
			return id
	return &""


func _card(rank: int, suit: int) -> Dictionary:
	return {"rank": rank, "suit": suit}


## Open `kind`, bet the minimum and press the commit button twice in place
## with the animations running. Returns the commit button's point.
func double_press(config: Array, resort: StringName, kind: StringName, rig: Array) -> Vector2:
	var label := "%s %s" % [config[0], kind]
	seated_funds = sim.city.funds
	overlay.open(sim, resort, kind, CasinoRng.new(5))
	overlay.press_chip(0)
	overlay.game.rig(rig)
	await frames()
	var commit := overlay.game.commit_action()
	var at := center_of(commit)
	check(at.x >= 0.0, "%s: the commit button is on screen" % label)
	# Long animations: the second press always lands while the table is busy.
	CasinoTableOverlay.animation_scale = 40.0
	press(at, bool(config[2]))
	await frames(2)
	check_eq(overlay.game.state, CasinoGame.PLAYING, "%s: the first press starts the round" % label)
	check(overlay.stage.is_busy(), "%s: the table is still animating" % label)
	check_eq(sim.city.funds, seated_funds - overlay.committed(), "%s: one stake is debited" % label)
	var under := action_at(at)
	press(at, bool(config[2]))
	await frames(2)
	if under != &"":
		check(not overlay.stage.is_busy(), "%s: a second press on %s only finishes the animation" % [label, under])
	return at


## Press action `id` as a player who has looked at the table would: later
## than a double press. A press during an animation only finishes it, so
## the button is pressed once more when the table was still animating.
func deliberate_press(id: StringName, touch: bool, label: String) -> void:
	now_ms += CasinoTableOverlay.PRESS_GUARD_MS
	var at := center_of(id)
	check(at.x >= 0.0, "%s: %s is on screen" % [label, id])
	if overlay.stage.is_busy():
		var before := overlay.game.view_state()
		press(at, touch)
		await frames(2)
		check(not overlay.stage.is_busy(), "%s: a press during the animation finishes it" % label)
		check_eq(overlay.game.view_state(), before, "%s: and does nothing else" % label)
	press(at, touch)
	await frames(2)


func test_blackjack_second_press_never_stands_or_hits() -> void:
	for config: Array in DISPLAYS:
		await display(config)
		var at := await double_press(config, COMSTOCK, &"blackjack",
			[_card(10, 0), _card(9, 1), _card(5, 2), _card(8, 3), _card(2, 0), _card(3, 1), _card(4, 2)])
		var label := String(config[0])
		var state := overlay.game.view_state()
		var hand: Dictionary = (state["hands"] as Array)[0]
		check_eq(overlay.game.state, CasinoGame.PLAYING, "%s: the hand is still the player's to play" % label)
		check_eq((hand["cards"] as Array).size(), 2, "%s: no card was drawn" % label)
		check(not bool(hand["done"]), "%s: the hand was not stood" % label)
		check_eq(overlay.committed(), int(overlay.game.limits["minimum"]), "%s: only the opening stake is committed" % label)
		check_eq(sim.city.funds, seated_funds - overlay.committed(), "%s: nothing more was debited" % label)
		# The buttons work again once the cards are shown.
		check_ne(action_at(at), &"", "%s: a decision button sits where the deal button was" % label)
		await deliberate_press(&"stand", bool(config[2]), label)
		check(bool(((overlay.game.view_state()["hands"] as Array)[0] as Dictionary)["done"]), "%s: a press after the reveal stands" % label)
		CasinoTableOverlay.animation_scale = 0.0
		overlay.resolve_round_now()
		await frames(2)
		check_eq(sim.city.funds - seated_funds, overlay.session_net(), "%s: the round settled once" % label)


func test_video_poker_second_press_never_draws() -> void:
	for config: Array in DISPLAYS:
		await display(config)
		await double_press(config, COMSTOCK, &"video_poker",
			[_card(1, 3), _card(1, 2), _card(5, 0), _card(9, 1), _card(13, 0), _card(1, 0), _card(7, 1), _card(7, 2)])
		var label := String(config[0])
		check_eq(overlay.game.state, CasinoGame.PLAYING, "%s: the draw still waits for the player" % label)
		check_eq(String(overlay.game.view_state()["rank"]), "", "%s: the hand was not drawn" % label)
		await deliberate_press(&"draw", bool(config[2]), label)
		check_eq(overlay.game.state, CasinoGame.SETTLED, "%s: a press after the deal draws" % label)
		CasinoTableOverlay.animation_scale = 0.0
		overlay.resolve_round_now()
		await frames(2)
		check_eq(sim.city.funds - seated_funds, overlay.session_net(), "%s: the round settled once" % label)


func test_launch_second_press_never_cashes_out_on_the_pad() -> void:
	for config: Array in DISPLAYS:
		await display(config)
		overlay.set_auto_target(0.0)
		await double_press(config, ORBIT, &"trajectory", [50.0])
		var label := String(config[0])
		check_eq(overlay.game.state, CasinoGame.PLAYING, "%s: the launch is still climbing" % label)
		if overlay.stage.is_busy():
			# Nothing was under the second press here: let the launch finish.
			overlay.stage.skip()
		check((overlay.stage as TrajectoryStage).live, "%s: the climb is live" % label)
		overlay.perform_action(&"advance", {"multiplier": 1.5})
		await deliberate_press(&"cash_out", bool(config[2]), label)
		check_eq(overlay.game.state, CasinoGame.SETTLED, "%s: a press during the climb cashes out" % label)
		check_ge(int(overlay.game.outcome()["returned"]), int(overlay.game.outcome()["staked"]) * 3 / 2, "%s: at the multiplier reached" % label)
		CasinoTableOverlay.animation_scale = 0.0
		overlay.resolve_round_now()
		await frames(2)
		check_eq(sim.city.funds - seated_funds, overlay.session_net(), "%s: the round settled once" % label)


func test_signature_game_second_press_never_chooses() -> void:
	for config: Array in DISPLAYS:
		await display(config)
		var label := String(config[0])
		seated_funds = sim.city.funds
		overlay.open(sim, VELVET, &"velvet_encore", CasinoRng.new(5))
		overlay.press_chip(0)
		await frames()
		var at := center_of(overlay.game.commit_action())
		check(at.x >= 0.0, "%s: the commit button is on screen" % label)
		CasinoTableOverlay.animation_scale = 40.0
		press(at, bool(config[2]))
		await frames(2)
		check_eq(overlay.game.state, CasinoGame.PLAYING, "%s: the first press starts the round" % label)
		var opened := overlay.game.view_state()
		var under := action_at(at)
		check_ne(under, &"", "%s: a choice sits where the commit button was" % label)
		press(at, bool(config[2]))
		await frames(2)
		check_eq(overlay.game.state, CasinoGame.PLAYING, "%s: the round is still the player's to play" % label)
		check_eq(overlay.game.view_state(), opened, "%s: the second press chose nothing" % label)
		# The same choice pressed on purpose a moment later is taken.
		await deliberate_press(under, bool(config[2]), label)
		check_ne(overlay.game.view_state(), opened, "%s: a later press on %s chooses" % [label, under])
		CasinoTableOverlay.animation_scale = 0.0
		overlay.resolve_round_now()
		await frames(2)
		check_eq(sim.city.funds - seated_funds, overlay.session_net(), "%s: the round settled once" % label)


func test_guard_passes_once_the_double_press_interval_is_over() -> void:
	await display(DISPLAYS[0])
	seated_funds = sim.city.funds
	overlay.open(sim, VELVET, &"velvet_encore", CasinoRng.new(5))
	overlay.press_chip(0)
	await frames()
	var at := center_of(overlay.game.commit_action())
	press(at, false)
	await frames(2)
	var opened := overlay.game.view_state()
	var under := action_at(at)
	check_ne(under, &"", "fixture: a choice sits where the commit button was")
	now_ms += CasinoTableOverlay.PRESS_GUARD_MS - 1
	mouse(at, true)
	mouse(at, false)
	await frames(2)
	check_eq(overlay.game.view_state(), opened, "one millisecond inside the guard the press is ignored")
	now_ms += 1
	mouse(at, true)
	mouse(at, false)
	await frames(2)
	check_ne(overlay.game.view_state(), opened, "at the guard's end the press chooses")
	overlay.resolve_round_now()


func test_same_button_pressed_twice_is_not_guarded() -> void:
	await display(DISPLAYS[0])
	overlay.open(sim, COMSTOCK, &"blackjack", CasinoRng.new(5))
	overlay.press_chip(0)
	overlay.game.rig([_card(2, 0), _card(9, 1), _card(3, 2), _card(8, 3), _card(2, 1), _card(2, 2), _card(4, 2)])
	overlay.perform_action(&"deal")
	await frames()
	var hit := center_of(&"hit")
	press(hit, false)
	await frames(2)
	press(hit, false)
	await frames(2)
	var hand: Dictionary = (overlay.game.view_state()["hands"] as Array)[0]
	check_eq((hand["cards"] as Array).size(), 4, "with nothing left to animate, two presses on Hit draw two cards")
	overlay.resolve_round_now()


func test_enter_during_an_animation_only_finishes_it() -> void:
	await display(DISPLAYS[0])
	overlay.open(sim, COMSTOCK, &"blackjack", CasinoRng.new(5))
	overlay.press_chip(0)
	overlay.game.rig([_card(10, 0), _card(9, 1), _card(5, 2), _card(8, 3), _card(2, 0)])
	CasinoTableOverlay.animation_scale = 40.0
	overlay.perform_action(&"deal")
	check(overlay.stage.is_busy())
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	check(overlay.handle_key(key), "Enter is used")
	check(not overlay.stage.is_busy(), "Enter finishes the animation")
	check(not bool(((overlay.game.view_state()["hands"] as Array)[0] as Dictionary)["done"]), "Enter does not also stand")
	CasinoTableOverlay.animation_scale = 0.0
	overlay.resolve_round_now()
