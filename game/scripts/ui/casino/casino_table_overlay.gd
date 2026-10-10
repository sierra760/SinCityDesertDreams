# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A gaming-resort table over the city: the resort header with the live
## treasury, the game's table drawn and animated in 2D, the dealer's patter
## and the bet bar.
##
## The overlay runs one `CasinoGame` and keeps the treasury in step with it:
## every accepted action that reports a stake is debited through
## `Simulation.casino_commit`, a settled round is credited once through
## `casino_settle`, and closing the city mid-round refunds the committed stake
## through `casino_refund`. It never writes the city itself. The host pauses
## the city while the overlay is open (see `GameHost.open_casino_table`).
class_name CasinoTableOverlay
extends Control

signal closed
signal round_settled(resort: StringName, game: StringName, outcome: Dictionary)
## Every animated table event as it starts, plus `bet` and `hold` actions,
## for sound: (game kind, event dictionary with at least "kind").
signal event_played(game: StringName, event: Dictionary)

## Every animation's length in seconds, before `animation_scale`.
const ANIMATION := {
	"card": 0.3,
	"flip": 0.26,
	"beat": 0.2,
	"result": 0.12,
	"shuffle": 0.7,
	"settle": 0.3,
	"banner": 1.6,
	"flourish": 2.4,
	"roulette": 4.2,
	"reel_start": 0.35,
	"reel_stop": 0.6,
	"wheel": 4.4,
	"dice": 1.7,
	"launch": 0.7,
	"burst": 0.8,
	## Longest replayed climb of a launch decided at once (automatic cash-out).
	"flight_max": 6.0,
	"signature_reveal": 0.55,
}
## Multiplies every animation; 0 applies events at once (tests).
static var animation_scale := 1.0

## Automatic cash-out targets offered before a trajectory launch.
const AUTO_TARGETS: Array[float] = [0.0, 1.5, 2.0, 3.0, 5.0, 10.0]
const VOICE_NAMES := {
	&"shopkeeper": "The shopkeeper",
	&"assayer": "The assayer",
	&"conductor": "The conductor",
	&"foreman": "The foreman",
	&"flight_director": "The flight director",
}
## Keyboard shortcuts named in the action tooltips.
const SHORTCUTS := {
	&"deal": "Enter", &"spin": "Enter", &"pull": "Enter", &"turn": "Enter", &"roll": "Enter",
	&"launch": "Enter", &"next": "Enter or N", &"hit": "H", &"stand": "S or Enter", &"double": "D",
	&"split": "P", &"draw": "D or Enter", &"cash_out": "Enter or Space", &"rebet": "R",
	&"clear": "Backspace",
}
const LETTER_ACTIONS := {
	KEY_H: [&"hit"], KEY_S: [&"stand"], KEY_D: [&"double", &"draw"], KEY_P: [&"split"],
	KEY_R: [&"rebet"], KEY_N: [&"next"], KEY_BACKSPACE: [&"clear"], KEY_DELETE: [&"clear"],
}

var sim: Simulation
var resort: StringName = &""
var kind: StringName = &""
var game: CasinoGame
var stage: CasinoStage
var palette: CasinoPalette
var chrome: CasinoChrome
var bet_bar: CasinoBetBar
var rules_panel: PanelContainer
var rules_label: Label
var patter_label: Label

var _layout: DisplayLayout
var _rng: CasinoRng
var _line_rng: CasinoRng
var _root: VBoxContainer
var _table_area: Control
var _side: PanelContainer
var _rules_close: Button
var _committed := 0
var _settled := false
var _session_net := 0
var _shown_net := 0
var _shown_funds := 0
var _auto_index := 0
var _patter := ""
var _message := ""
var _round_opened := false
var _patter_voiced := false
var _was_debuted := true
var _bounds_pending := false
## The round settled logically but its result has not finished playing yet.
var _settle_signal_pending := false
## The control the table itself focused; Enter there plays the main action,
## while Enter on any other focused button activates that button.
var _default_focus: Control
## A round that stakes more than half the treasury waits for a second
## Enter or tap: the bets and stake it was asked about (empty when none).
var _confirm_bets: Dictionary = {}
var _confirm_stake := 0
## What became of a round the app played out in the background; read once
## by the host when the app comes back (see `take_background_summary`).
var _background_summary := ""


func _init() -> void:
	name = "CasinoTableOverlay"
	theme = UITheme.control_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.02, 0.06, 0.05, 0.28)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_root = VBoxContainer.new()
	_root.name = "Table"
	_root.add_theme_constant_override("separation", 6)
	add_child(_root)
	chrome = CasinoChrome.new()
	chrome.leave_requested.connect(close)
	chrome.rules_toggled.connect(_show_rules)
	_root.add_child(chrome)
	var middle := HBoxContainer.new()
	middle.name = "Middle"
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 6)
	_root.add_child(middle)
	_table_area = Control.new()
	_table_area.name = "TableArea"
	_table_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_area.custom_minimum_size = Vector2(160, 120)
	_table_area.clip_contents = true
	middle.add_child(_table_area)
	# Short displays stack the game's actions here, beside the table.
	_side = PanelContainer.new()
	_side.name = "SideActions"
	_side.custom_minimum_size.x = 124
	var side_face := StyleBoxFlat.new()
	side_face.bg_color = Color(UITheme.PANEL_FACE, 0.95)
	side_face.set_corner_radius_all(UITheme.CORNER)
	side_face.set_content_margin_all(6)
	_side.add_theme_stylebox_override("panel", side_face)
	_side.visible = false
	middle.add_child(_side)
	var patter_panel := PanelContainer.new()
	patter_panel.name = "Patter"
	var patter_face := StyleBoxFlat.new()
	patter_face.bg_color = Color(UITheme.PANEL_FACE, 0.95)
	patter_face.set_corner_radius_all(UITheme.CORNER)
	patter_face.content_margin_left = 12
	patter_face.content_margin_right = 12
	patter_face.content_margin_top = 3
	patter_face.content_margin_bottom = 3
	patter_panel.add_theme_stylebox_override("panel", patter_face)
	_root.add_child(patter_panel)
	patter_label = UIFactory.make_label("", UITheme.FONT_BODY, UITheme.TEXT_PRIMARY)
	patter_label.name = "PatterLine"
	# The dealer's line wraps on narrow displays instead of cutting off.
	patter_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	patter_panel.add_child(patter_label)
	bet_bar = CasinoBetBar.new()
	bet_bar.chip_pressed.connect(press_chip)
	bet_bar.step_pressed.connect(step_bet)
	bet_bar.action_pressed.connect(func(action: StringName) -> void: perform_action(action))
	bet_bar.auto_pressed.connect(cycle_auto_target)
	_root.add_child(bet_bar)
	_build_rules()
	resized.connect(_apply_bounds)
	# A container keeps a size it was forced to grow to; refit once the
	# table's content shrinks again (a narrower bet bar, a shorter header).
	_root.minimum_size_changed.connect(_schedule_bounds)
	visible = false


func _build_rules() -> void:
	rules_panel = UIFactory.make_panel()
	rules_panel.name = "Rules"
	rules_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rules_panel.offset_left = 12
	rules_panel.offset_top = 12
	rules_panel.offset_right = -12
	rules_panel.offset_bottom = -12
	rules_panel.visible = false
	_table_area.add_child(rules_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UITheme.VSEP)
	rules_panel.add_child(column)
	column.add_child(UIFactory.make_section_header("How it plays"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	rules_label = UIFactory.make_label("", UITheme.FONT_BODY, UITheme.TEXT_PRIMARY)
	rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rules_label)
	_rules_close = UIFactory.make_button("Close rules")
	_rules_close.name = "CloseRules"
	_rules_close.size_flags_horizontal = Control.SIZE_SHRINK_END
	_rules_close.pressed.connect(func() -> void: _show_rules(false))
	column.add_child(_rules_close)


## Fit the table to the display's safe area as it changes.
func bind_layout(layout: DisplayLayout) -> void:
	_layout = layout
	if not layout.metrics_changed.is_connected(_on_metrics_changed):
		layout.metrics_changed.connect(_on_metrics_changed)
	_apply_bounds()


## Seconds an animation runs at the current animation scale.
static func seconds(key: String) -> float:
	return float(ANIMATION.get(key, 0.2)) * maxf(0.0, animation_scale)


## `raw` seconds at the current animation scale.
static func scaled(raw: float) -> float:
	return raw * maxf(0.0, animation_scale)


# ── Opening and closing ──────────────────────────────────────────────────

## Sit down at `game_kind` in `resort_key`. `rng` seeds the game (tests);
## null draws a fresh seed. The host has already checked the city can play.
func open(table_sim: Simulation, resort_key: StringName, game_kind: StringName, rng: CasinoRng = null) -> void:
	sim = table_sim
	resort = resort_key
	kind = game_kind
	palette = CasinoPalette.for_resort(resort)
	_rng = rng if rng != null else CasinoRng.new()
	_line_rng = CasinoRng.new(posmod(_rng.state() * 7 + 11, 2147483647))
	game = ResortThemes.make_game(kind)
	game.begin(_rng, _limits())
	if is_instance_valid(stage):
		stage.queue_free()
	stage = _make_stage(kind)
	stage.name = "Stage"
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_table_area.add_child(stage)
	_table_area.move_child(stage, 0)
	stage.setup(game, resort, palette)
	stage.spot_pressed.connect(_on_spot_pressed)
	stage.stage_action.connect(_on_stage_action)
	stage.event_started.connect(_on_event_started)
	stage.event_finished.connect(_on_event_finished)
	stage.idle.connect(_refresh)
	chrome.setup(palette, ResortThemes.resort_name(resort), ResortThemes.floor_name(resort), ResortThemes.game_name(resort, kind))
	chrome.rules_button.set_pressed_no_signal(false)
	rules_panel.visible = false
	rules_label.text = rules_text(kind, resort, game.limits)
	_committed = 0
	_settled = false
	_session_net = 0
	_shown_net = 0
	_shown_funds = sim.city.funds
	_auto_index = 0
	_round_opened = false
	_message = ""
	_was_debuted = sim.casino().has_debuted()
	_settle_signal_pending = false
	_patter_voiced = false
	_clear_confirmation()
	var table_maximum := int(CasinoParams.table_limits(resort)["maximum"])
	_patter = "Welcome to %s. Table limits %s to %s." % [ResortThemes.floor_name(resort),
		CasinoLines.money(int(game.limits["minimum"])), CasinoLines.money(table_maximum)]
	if int(game.limits["maximum"]) < table_maximum:
		# The treasury caps the bet below the table's own maximum; say so.
		_patter = _patter.trim_suffix(".") + "; the treasury covers up to %s." % CasinoLines.money(int(game.limits["maximum"]))
	bet_bar.set_selected_chip(0)
	visible = true
	_apply_bounds()
	_refresh()
	_default_focus = bet_bar.chip_buttons[0]
	UIFactory.contain_modal_focus(self, _default_focus)


## Leave the table. Refused while a round is being played (nothing is at
## risk otherwise: bets placed but not played were never debited).
func close() -> void:
	if not visible:
		return
	if not can_leave():
		_say_message(CasinoLines.ROUND_OPEN)
		return
	_finish_close()


## Close at once because the city is closing: a round in play has its
## committed stake refunded.
func force_close() -> void:
	if not visible:
		return
	if game != null and game.state == CasinoGame.PLAYING and _committed > 0:
		sim.casino_refund(resort, kind, _committed)
	_committed = 0
	_finish_close()


## Close at once because the app is going to the background: a round in
## play is played out as it stands instead of refunded, so leaving the app
## never undoes a bad hand. Blackjack stands on every remaining hand, video
## poker draws with the current holds and a launch cashes out at the shown
## multiplier (at or past the burn-out it settles as a burn-out). Every other
## game settles as soon as it is committed.
##
## Returns a one-line summary of what became of the round ("Your Assay
## Twenty-One hand was played out while you were away: -$1,000."), or "" when
## no round was in play; the summary is also kept for
## `take_background_summary`.
func resolve_round_now() -> String:
	if not visible:
		return ""
	var summary := ""
	var refunded := 0
	var game_name := ResortThemes.game_name(resort, kind)
	var in_play := game != null and game.state == CasinoGame.PLAYING
	if in_play:
		if is_instance_valid(stage) and stage.is_busy():
			stage.skip()
		var guard := 8
		while game.state == CasinoGame.PLAYING and guard > 0:
			guard -= 1
			match kind:
				&"blackjack":
					perform_action(&"stand")
				&"video_poker":
					perform_action(&"draw")
				&"trajectory":
					perform_action(&"cash_out")
				_:
					var fallback := game.background_action()
					if fallback == &"":
						break
					perform_action(fallback)
	if game != null and game.state == CasinoGame.PLAYING and _committed > 0:
		# A game that cannot be played out here is refunded rather than kept.
		refunded = _committed
		sim.casino_refund(resort, kind, _committed)
	if in_play:
		if refunded > 0:
			summary = CasinoLines.background_refund(game_name, refunded)
		elif game != null and game.state == CasinoGame.SETTLED:
			var noun := "round"
			match kind:
				&"blackjack", &"video_poker":
					noun = "hand"
				&"trajectory":
					noun = "launch"
			summary = CasinoLines.background_result(game_name, noun, int(game.outcome().get("net", 0)))
	_background_summary = summary
	_committed = 0
	_finish_close()
	return summary


## The summary of the last round played out in the background, once; "" when
## there is none.
func take_background_summary() -> String:
	var summary := _background_summary
	_background_summary = ""
	return summary


## Show a short message in the dealer's line (for example why a quit waits).
func say(text: String) -> void:
	if visible:
		_say_message(text)


## Hold or release a live launch's climb (the window lost or regained focus).
func set_clock_held(held: bool) -> void:
	if is_instance_valid(stage) and stage is TrajectoryStage:
		(stage as TrajectoryStage).clock_held = held


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_clock_held(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_clock_held(false)


## Escape: close the rules, finish an animation, then leave when allowed.
## Each step takes its own Escape, so hurrying a result shows it instead of
## leaving with it unseen.
func request_leave() -> void:
	if not visible:
		return
	if rules_panel.visible:
		_show_rules(false)
		return
	if is_instance_valid(stage) and stage.is_busy():
		stage.skip()
		return
	close()


func is_open() -> bool:
	return visible


## False while a round is being played.
func can_leave() -> bool:
	return game == null or game.state != CasinoGame.PLAYING


## True while a round has been committed and not yet settled.
func round_in_progress() -> bool:
	return visible and game != null and game.state == CasinoGame.PLAYING


## The stake debited for the round now being played.
func committed() -> int:
	return _committed


## Net of the rounds settled since sitting down.
func session_net() -> int:
	return _session_net


func _finish_close() -> void:
	if is_instance_valid(stage):
		stage.skip()
		stage.queue_free()
	stage = null
	_emit_settled()
	rules_panel.visible = false
	visible = false
	closed.emit()


func _make_stage(game_kind: StringName) -> CasinoStage:
	if game_kind in OriginalSignatureStage.KINDS:
		return OriginalSignatureStage.new()
	match game_kind:
		&"roulette":
			return RouletteStage.new()
		&"slots":
			return SlotStage.new()
		&"money_wheel":
			return WheelStage.new()
		&"faro":
			return FaroStage.new()
		&"chuck_a_luck":
			return DiceStage.new()
		&"trajectory":
			return TrajectoryStage.new()
	return CardStage.new()


func _limits() -> Dictionary:
	return sim.casino().limits(resort, sim.city.funds)


# ── Betting ──────────────────────────────────────────────────────────────

## Choose chip `index` (0–3 for the denominations, 4 for Max) and put it on
## the selected spot.
func press_chip(index: int) -> void:
	if not _begin_betting():
		return
	bet_bar.set_selected_chip(index)
	add_to_spot(stage.selected_spot, _chip_amount(index))


## Put the selected chip on `spot` (and select it).
func bet_on(spot: StringName) -> void:
	if not _begin_betting():
		return
	stage.selected_spot = spot
	add_to_spot(spot, _chip_amount(bet_bar.selected_chip()))


## Add `amount` to `spot`; an amount over the maximum is cut to what fits.
func add_to_spot(spot: StringName, amount: int) -> Dictionary:
	if game.state != CasinoGame.BETTING:
		return {"ok": false, "reason": CasinoLines.BETS_CLOSED}
	var room := int(game.limits["maximum"]) - game.total_staked()
	var placed := mini(amount, room)
	if placed <= 0:
		_say_message(CasinoLines.OVER_MAXIMUM if room <= 0 else CasinoLines.BET_TOO_SMALL)
		return {"ok": false, "reason": CasinoLines.OVER_MAXIMUM}
	var result := game.place_bet(spot, placed)
	if bool(result["ok"]):
		_message = ""
		_clear_confirmation()
	else:
		_say_message(String(result["reason"]))
	stage.sync(game.view_state())
	_refresh()
	return result


## Minus (-1) takes the selected chip's worth off the selected spot; plus
## (+1) adds it.
func step_bet(direction: int) -> void:
	if not _begin_betting():
		return
	var spot := stage.selected_spot
	var amount := _chip_amount(bet_bar.selected_chip())
	if direction > 0:
		add_to_spot(spot, amount)
		return
	var current := int(game.bets().get(spot, 0))
	if current <= 0:
		return
	game.remove_bet(spot)
	var left := current - amount
	if left > 0:
		game.place_bet(spot, left)
	_message = ""
	_clear_confirmation()
	stage.sync(game.view_state())
	_refresh()


## Select a spot without betting on it.
func select_spot(spot: StringName) -> void:
	if is_instance_valid(stage):
		stage.selected_spot = spot
		stage.queue_redraw()
		_refresh()


## Cycle the trajectory's automatic cash-out target.
func cycle_auto_target() -> void:
	if kind != &"trajectory" or game.state == CasinoGame.PLAYING:
		return
	_auto_index = (_auto_index + 1) % AUTO_TARGETS.size()
	(stage as TrajectoryStage).set_auto_target(AUTO_TARGETS[_auto_index])
	_refresh()


## Set the trajectory's automatic cash-out target (0 for none).
func set_auto_target(value: float) -> void:
	var index := AUTO_TARGETS.find(value)
	_auto_index = maxi(0, index)
	if kind == &"trajectory" and is_instance_valid(stage):
		(stage as TrajectoryStage).set_auto_target(AUTO_TARGETS[_auto_index])
	_refresh()


func _chip_amount(index: int) -> int:
	if index >= CasinoBetBar.MAX_CHIP:
		return int(game.limits["maximum"]) - game.total_staked()
	var values := CasinoPalette.chip_values(int(game.limits["minimum"]))
	return values[clampi(index, 0, values.size() - 1)]


## Bets can change now; a settled round makes way for the next one first.
func _begin_betting() -> bool:
	if game == null or not visible:
		return false
	if game.state == CasinoGame.SETTLED:
		_next_round()
	return game.state == CasinoGame.BETTING


# ── Actions and the treasury ─────────────────────────────────────────────

## Perform a game action through the treasury: a reported stake is debited
## before anything is shown; a settled round is credited once.
func perform_action(action: StringName, payload: Dictionary = {}) -> Dictionary:
	if game == null or not visible:
		return {"ok": false, "reason": CasinoLines.ACTION_UNAVAILABLE, "stake": 0}
	if is_instance_valid(stage) and stage.is_busy() and action != &"advance":
		stage.skip()
	if action == CasinoGame.NEXT:
		return _next_round()
	if action == CasinoGame.REBET and game.state == CasinoGame.SETTLED:
		# "Same bet" after a result: start the next round, then repeat.
		_next_round()
		if not _action_enabled(CasinoGame.REBET):
			# Keep the next round's own explanation (a treasury below the
			# minimum) rather than a generic refusal.
			return {"ok": false, "reason": _message if not _message.is_empty() else CasinoLines.ACTION_UNAVAILABLE, "stake": 0}
	var args := payload.duplicate()
	if kind == &"trajectory":
		if action == game.commit_action() and not args.has("auto") and AUTO_TARGETS[_auto_index] > 0.0:
			args["auto"] = AUTO_TARGETS[_auto_index]
		elif action == &"cash_out" and not args.has("multiplier"):
			var shown := (stage as TrajectoryStage).current_multiplier()
			args["multiplier"] = maxf(shown, float(game.view_state().get("multiplier", 1.0)))
	var expected := _expected_stake(action)
	if expected > sim.city.funds:
		_say_message(CasinoLines.NO_CREDIT)
		return {"ok": false, "reason": CasinoLines.NO_CREDIT, "stake": 0}
	var opening := game.state == CasinoGame.BETTING and action == game.commit_action()
	if opening and not _stake_confirmed(expected):
		var question := CasinoLines.confirm_stake(expected, sim.city.funds, game.commit_label())
		_say_message(question)
		return {"ok": false, "reason": question, "stake": 0, "confirm": true}
	if not opening and action != &"advance" and action != &"hold":
		_clear_confirmation()
	# A stake known in advance (the opening bet, a double or a split) is
	# debited before the game applies it, so the game never holds a stake
	# the treasury refused; it is refunded if the game then refuses.
	var precommitted := 0
	if expected > 0:
		if not sim.casino_commit(resort, kind, expected):
			_say_message(CasinoLines.NO_CREDIT)
			_refresh()
			return {"ok": false, "reason": CasinoLines.NO_CREDIT, "stake": 0}
		precommitted = expected
	var result := game.act(action, args)
	if not bool(result.get("ok", false)):
		if precommitted > 0:
			sim.casino_refund(resort, kind, precommitted)
		_say_message(String(result.get("reason", "")))
		return result
	var stake := int(result.get("stake", 0))
	var extra := stake - precommitted
	if extra > 0:
		if not sim.casino_commit(resort, kind, extra):
			if precommitted > 0:
				sim.casino_refund(resort, kind, precommitted)
			_commit_refused(opening)
			return {"ok": false, "reason": CasinoLines.NO_CREDIT, "stake": 0}
	elif extra < 0:
		sim.casino_refund(resort, kind, -extra)
	if stake > 0 or precommitted > 0:
		_committed += stake
		_shown_funds = sim.city.funds
		event_played.emit(kind, {"kind": "bet", "stake": stake})
	elif action == &"hold":
		event_played.emit(kind, {"kind": "hold"})
	_message = ""
	if opening:
		_round_opened = false
	var events := game.take_events()
	if game.state == CasinoGame.SETTLED:
		_settle()
	if events.is_empty():
		stage.sync(game.view_state())
	else:
		stage.play(events)
	if _settle_signal_pending and not stage.is_busy():
		_emit_settled()
	_refresh()
	return result


## The stake an action would debit, checked against the treasury first.
func _expected_stake(action: StringName) -> int:
	if game.state == CasinoGame.BETTING and action == game.commit_action():
		return game.total_staked()
	if kind == &"blackjack" and game.state == CasinoGame.PLAYING and (action == &"double" or action == &"split"):
		var state := game.view_state()
		var hands: Array = state.get("hands", [])
		var active := int(state.get("active_hand", -1))
		if active >= 0 and active < hands.size():
			return int((hands[active] as Dictionary).get("stake", 0))
	return 0


## True when an opening stake may be debited now: at most half the treasury,
## or the same bets the dealer already asked about (the second Enter or
## tap). A larger stake asked about for the first time is remembered and
## refused, so the player confirms it deliberately.
func _stake_confirmed(stake: int) -> bool:
	if stake * 2 <= sim.city.funds:
		_clear_confirmation()
		return true
	var bets := game.bets()
	if _confirm_stake == stake and _confirm_bets == bets:
		_clear_confirmation()
		return true
	_confirm_stake = stake
	_confirm_bets = bets
	return false


func _clear_confirmation() -> void:
	_confirm_stake = 0
	_confirm_bets = {}


## True while the dealer waits for a second Enter or tap to confirm a large
## stake.
func awaiting_confirmation() -> bool:
	return _confirm_stake > 0


## The treasury refused a stake after the game accepted it. The opening
## stake is undone by starting the table afresh; nothing was debited.
func _commit_refused(opening: bool) -> void:
	_say_message(CasinoLines.NO_CREDIT)
	if opening:
		game.take_events()
		game.begin(_rng, _limits())
		stage.reset_round()
	_refresh()


func _settle() -> void:
	if _settled:
		return
	_settled = true
	var outcome := game.outcome()
	sim.casino_settle(resort, kind, int(outcome["staked"]), int(outcome["returned"]))
	_committed = 0
	_session_net += int(outcome["net"])
	# The treasury is credited now; listeners hear of the result once its
	# animation has played, so nothing outside the table reveals it early.
	_settle_signal_pending = true


func _emit_settled() -> void:
	if not _settle_signal_pending or game == null:
		return
	_settle_signal_pending = false
	round_settled.emit(resort, kind, game.outcome())


func _next_round() -> Dictionary:
	if game.state != CasinoGame.SETTLED:
		return {"ok": false, "reason": CasinoLines.ACTION_UNAVAILABLE, "stake": 0}
	if is_instance_valid(stage) and stage.is_busy():
		stage.skip()
	_emit_settled()
	game.next_round()
	game.set_limits(_limits())
	_settled = false
	_round_opened = false
	_shown_funds = sim.city.funds
	_shown_net = _session_net
	stage.reset_round()
	var check := sim.casino().can_play(resort, sim.city.funds)
	if not bool(check["ok"]):
		_say_message(String(check["reason"]))
	else:
		_message = ""
	_refresh()
	return {"ok": true, "reason": "", "stake": 0}


func _on_spot_pressed(spot: StringName) -> void:
	if game != null and game.state != CasinoGame.PLAYING:
		bet_on(spot)


func _on_stage_action(action: StringName, payload: Dictionary) -> void:
	if game == null or game.state != CasinoGame.PLAYING:
		return
	perform_action(action, payload)


# ── Animation feedback ───────────────────────────────────────────────────

func _on_event_started(event: Dictionary) -> void:
	event_played.emit(kind, event)
	var event_kind := String(event.get("kind", ""))
	var voice := ResortThemes.voice(resort)
	if not _round_opened and event_kind in ["card", "spin", "wheel", "dice", "launch"]:
		_round_opened = true
		_set_patter(CasinoLines.line(voice, &"deal" if event_kind == "card" else &"spin", _line_rng))
	elif event_kind == "blackjack" and String(event.get("who", "")) == "player":
		_set_patter(CasinoLines.line(voice, &"blackjack", _line_rng))
	elif event_kind == "bust" and String(event.get("who", "")) == "player":
		_set_patter(CasinoLines.line(voice, &"bust", _line_rng))
	elif event_kind == "crash":
		_set_patter(CasinoLines.line(voice, &"crash", _line_rng))
	elif event_kind == "jackpot":
		_set_patter(CasinoLines.line(voice, &"jackpot", _line_rng))


func _on_event_finished(event: Dictionary) -> void:
	if String(event.get("kind", "")) != "settle":
		return
	_emit_settled()
	var outcome := game.outcome()
	var reaction := String(outcome.get("reaction", "lose"))
	var net := int(outcome.get("net", 0))
	_shown_funds = sim.city.funds
	_shown_net = _session_net
	var voice := ResortThemes.voice(resort)
	if not _was_debuted and sim.casino().has_debuted():
		_was_debuted = true
		_set_patter(CasinoLines.line(voice, &"debut", _line_rng))
	else:
		_set_patter(CasinoLines.line(voice, CasinoLines.reaction_event(reaction), _line_rng))
	var title := "Push"
	var color := palette.ink
	match reaction:
		"blackjack":
			title = "Blackjack"
			color = CasinoPalette.WIN
		"jackpot":
			title = "Jackpot"
			color = CasinoPalette.WIN
		"win":
			title = "Winner"
			color = CasinoPalette.WIN
		"bust":
			title = "Bust"
			color = CasinoPalette.LOSE
		"crash":
			title = "Burn-out"
			color = CasinoPalette.LOSE
		"lose":
			title = "House wins"
			color = CasinoPalette.LOSE
	var detail := "%s  %s" % [String(outcome.get("summary", "")), UIFactory.format_money(net)]
	if is_instance_valid(stage):
		stage.show_banner(title, detail, color, reaction == "blackjack" or reaction == "jackpot")
	_refresh()


func _set_patter(line: String) -> void:
	if line.is_empty():
		return
	_patter = line
	_patter_voiced = true
	_message = ""
	_refresh()


func _say_message(text: String) -> void:
	_message = text
	_refresh()


# ── Display ──────────────────────────────────────────────────────────────

func _refresh() -> void:
	if game == null or not visible or not is_instance_valid(stage):
		return
	var minimum := int(game.limits["minimum"])
	var maximum := int(game.limits["maximum"])
	var betting := game.state != CasinoGame.PLAYING
	bet_bar.set_chips(CasinoPalette.chip_values(minimum), maxi(0, maximum - game.total_staked()) if game.state == CasinoGame.BETTING else maximum, minimum)
	bet_bar.set_betting_enabled(betting and maximum >= minimum)
	var hidden: Array[StringName] = [&"hold", &"advance"]
	bet_bar.set_actions(game.actions(), hidden, SHORTCUTS)
	bet_bar.set_auto(AUTO_TARGETS[_auto_index], kind == &"trajectory" and game.state != CasinoGame.PLAYING)
	var spot := stage.selected_spot
	var info := stage.spot_info(spot)
	var on_spot := int(game.bets().get(spot, 0))
	var spot_text := stage.spot_label(spot)
	var several := stage.spot_order().size() > 1
	if several:
		# Tables with several spots say plainly where the next chip goes.
		spot_text = "Chips go on " + spot_text
	if info.has("odds"):
		spot_text += (" · pays " if several else " · ") + String(info["odds"])
	if on_spot > 0:
		spot_text += " · " + CasinoLines.money(on_spot) + " on it"
	bet_bar.set_readout(spot_text, "Bet %s · limits %s to %s" % [CasinoLines.money(game.total_staked()), CasinoLines.money(minimum), CasinoLines.money(maximum)])
	var in_play := _committed if game.state == CasinoGame.PLAYING else 0
	chrome.set_treasury(_shown_funds, _shown_net, in_play)
	chrome.set_leave_enabled(can_leave(), CasinoLines.ROUND_OPEN)
	if not _message.is_empty():
		patter_label.text = _message
		patter_label.add_theme_color_override("font_color", UITheme.MONEY_NEGATIVE)
	else:
		var voice_name := String(VOICE_NAMES.get(ResortThemes.voice(resort), ""))
		patter_label.text = ("%s · %s" % [voice_name, _patter]) if not voice_name.is_empty() and _patter_voiced else _patter
		patter_label.add_theme_color_override("font_color", palette.ink if palette != null else UITheme.TEXT_PRIMARY)
	_keep_focus()
	if kind in OriginalSignatureStage.KINDS:
		_schedule_bounds()


## Keep keyboard focus on a usable control inside the table.
func _keep_focus() -> void:
	if not is_visible_in_tree():
		return
	var focused := get_viewport().gui_get_focus_owner()
	# Focus never rests on Hit: Space (and a mouse click's focus) would then
	# draw another card by accident.
	var usable: bool = focused != null and is_ancestor_of(focused) and focused.is_visible_in_tree() \
		and not (focused is BaseButton and (focused as BaseButton).disabled) \
		and focused != bet_bar.action_buttons.get(&"hit", null)
	if usable:
		return
	var preferred: Control = bet_bar.primary_button()
	if preferred == null:
		preferred = bet_bar.chip_buttons[bet_bar.selected_chip()] if not bet_bar.chip_buttons[0].disabled else chrome.rules_button
	_default_focus = preferred
	UIFactory.contain_modal_focus(self, preferred)


func _show_rules(shown: bool) -> void:
	rules_panel.visible = shown
	chrome.rules_button.set_pressed_no_signal(shown)
	if shown:
		_rules_close.grab_focus()
	UIFactory.contain_modal_focus(self, _rules_close if shown else chrome.rules_button)


func _on_metrics_changed(_metrics: Dictionary) -> void:
	_apply_bounds()


func _schedule_bounds() -> void:
	if _bounds_pending:
		return
	_bounds_pending = true
	_apply_bounds.call_deferred()


func _apply_bounds() -> void:
	_bounds_pending = false
	if _root == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	if _layout != null:
		rect = _layout.logical_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var roomy := rect.size.x >= 900.0 and rect.size.y >= 600.0
	var inner := rect.grow(-(14.0 if roomy else 6.0))
	if inner.size.x > 1400.0:
		inner = Rect2(inner.position + Vector2((inner.size.x - 1400.0) * 0.5, 0.0), Vector2(1400.0, inner.size.y))
	_root.position = inner.position
	_root.size = inner.size
	var short := inner.size.y < 520.0
	chrome.apply_layout(inner.size.x < 520.0, short)
	var signature_four_actions := kind in OriginalSignatureStage.KINDS and game != null and game.actions().size() >= 4
	bet_bar.apply_layout(inner.size.x, short, _side if short and inner.size.x >= 480.0 and not signature_four_actions else null)
	_side.visible = bet_bar.actions_parent() == _side


# ── Keyboard ─────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not visible or game == null or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and not is_ancestor_of(focused):
		return
	if rules_panel.visible:
		return
	if handle_key(key):
		get_viewport().set_input_as_handled()


## Keys that keep working while held down (the key repeats): +/- step the bet,
## and navigation (arrows, Tab) moves on. Repeats of action keys are
## swallowed so a held key never replays a table action.
const REPEATING_KEYS: Array[Key] = [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]


## Keys that play, bet or leave: their repeats do nothing.
static func is_action_key(key: InputEventKey) -> bool:
	var code := key.keycode
	if code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE, KEY_A] or LETTER_ACTIONS.has(code):
		return true
	var physical := key.physical_keycode
	return (code >= KEY_0 and code <= KEY_9) or (physical >= KEY_0 and physical <= KEY_9) \
		or (code >= KEY_KP_0 and code <= KEY_KP_9)


## Table keys: Enter plays the primary action, arrows choose a spot, digits
## and +/- bet, letters play the named actions. True when the key was used.
## A held action key's repeats are used (swallowed) without doing anything;
## +/- and navigation keys repeat as usual.
func handle_key(key: InputEventKey) -> bool:
	var code := key.keycode
	if key.echo and code not in REPEATING_KEYS and is_action_key(key):
		return true
	match code:
		KEY_ENTER, KEY_KP_ENTER:
			# A button the player moved focus to (Leave table, Rules, a game
			# action other than Hit) takes Enter itself; the table's own
			# default focus, a chip, the steppers and Hit play the main action,
			# so Enter after clicking a chip deals instead of betting again.
			var focused := get_viewport().gui_get_focus_owner()
			if focused is BaseButton and is_ancestor_of(focused) and focused != _default_focus \
					and focused != bet_bar.primary_button() and not (focused as BaseButton).disabled \
					and not _enter_plays_main_action(focused):
				return false
			if is_instance_valid(stage) and stage.is_busy():
				stage.skip()
				return true
			var primary := _primary_action()
			if primary != &"":
				perform_action(primary)
			return true
		KEY_SPACE:
			if kind == &"trajectory" and game.state == CasinoGame.PLAYING:
				perform_action(&"cash_out")
				return true
			return false
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if game.state == CasinoGame.PLAYING or stage.spot_order().size() < 2:
				return false
			var direction := {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}[code] as Vector2
			stage.move_selection_toward(direction)
			_refresh()
			return true
		KEY_PLUS, KEY_EQUAL, KEY_KP_ADD:
			step_bet(1)
			return true
		KEY_MINUS, KEY_KP_SUBTRACT:
			step_bet(-1)
			return true
		KEY_A:
			if kind == &"trajectory" and game.state != CasinoGame.PLAYING:
				cycle_auto_target()
				return true
			return false
	# The digit row by key position, so layouts that need Shift for digits
	# (AZERTY) still bet with the unshifted key; then by label and keypad.
	var digit := -1
	var physical := key.physical_keycode
	if physical >= KEY_1 and physical <= KEY_5:
		digit = physical - KEY_1
	elif code >= KEY_1 and code <= KEY_5:
		digit = code - KEY_1
	elif code >= KEY_KP_1 and code <= KEY_KP_5:
		digit = code - KEY_KP_1
	if digit >= 0:
		if kind == &"video_poker" and game.state == CasinoGame.PLAYING:
			perform_action(&"hold", {"index": digit})
		else:
			press_chip(digit)
		return true
	if LETTER_ACTIONS.has(code):
		for action: StringName in LETTER_ACTIONS[code]:
			if _action_enabled(action):
				perform_action(action)
				return true
	return false


func _primary_action() -> StringName:
	for action: Dictionary in game.actions():
		var id := StringName(action["id"])
		if bool(action.get("primary", false)) and bool(action.get("enabled", false)) and id != &"advance" and id != &"hold":
			return id
	return &""


## True for focused bet-bar controls where Enter plays the table's main
## action instead of pressing the control: the chips, - and +, the automatic
## cash-out and Hit.
func _enter_plays_main_action(focused: Control) -> bool:
	if focused in bet_bar.chip_buttons:
		return true
	if focused == bet_bar.minus_button or focused == bet_bar.plus_button or focused == bet_bar.auto_button:
		return true
	return focused == bet_bar.action_buttons.get(&"hit", null)


func _action_enabled(action: StringName) -> bool:
	for entry: Dictionary in game.actions():
		if StringName(entry["id"]) == action:
			return bool(entry.get("enabled", false))
	return false


# ── Rules ────────────────────────────────────────────────────────────────

## The rules sheet for a game at a resort with the table's limits.
static func rules_text(game_kind: StringName, resort_key: StringName, limits: Dictionary) -> String:
	var table := CasinoParams.table_limits(resort_key)
	var lines: Array[String] = []
	if game_kind in OriginalSignatureStage.KINDS:
		var rules_game := ResortThemes.make_game(game_kind)
		if rules_game != null:
			rules_game.begin(CasinoRng.new(1), limits)
			lines.append(String(rules_game.view_state().get("rules_text", "")))
		lines.append("During a round, choose on the board or use Tab to reach each action button. Enter chooses the enabled primary action. Backgrounding finishes a committed round using the displayed safe decision; it never restores a lost stake.")
	match game_kind:
		&"blackjack":
			lines.append("Get closer to 21 than the dealer without going over. Number cards count their value, court cards ten, aces one or eleven. The dealer draws to 16 and stands on every 17.")
			lines.append("A two-card 21 pays 3 to 2; other wins pay 1 to 1; a tie returns the bet. Double on any first two cards for one more card. Split a pair once; split aces take one card each.")
			lines.append("Keys: Enter deals, then stands during a hand (Enter never draws a card); H hits, S stands, D doubles, P splits.")
		&"roulette":
			lines.append("A single-zero wheel, 0 to 36. Bet on as many spots as you like; the table maximum applies to the total.")
			lines.append("A number pays 35 to 1. Red or black, odd or even, 1 to 18 or 19 to 36 pay 1 to 1. Dozens and columns pay 2 to 1. Zero loses every bet except a bet on zero.")
		&"slots":
			var names := ResortThemes.reel_names(resort_key)
			var pays: Array[String] = []
			for symbol in ["B", "s5", "s4", "s3", "s2", "s1"]:
				pays.append("three %s %d" % [ResortThemes.reel_name(resort_key, symbol), int(CasinoParams.SLOT_TRIPLE_RETURNS[symbol])])
			lines.append("Three reels and one line. Pays for 1, bet included: %s." % ", ".join(pays))
			var bonus := names[5] if names.size() > 5 else "bonus"
			lines.append("Any two %s pay %d; any one pays %d." % [bonus, int(CasinoParams.SLOT_BONUS_RETURNS[2]), int(CasinoParams.SLOT_BONUS_RETURNS[1])])
		&"money_wheel":
			var emblems := ResortThemes.wheel_emblems(resort_key)
			lines.append("Fifty-four segments. Bet on the segment the pointer will stop at: 1 pays 1 to 1 (24 segments), 2 pays 2 to 1 (15), 5 pays 5 to 1 (7), 10 pays 10 to 1 (4), 20 pays 20 to 1 (2).")
			lines.append("%s and %s have one segment each and pay 40 to 1." % [emblems[0] if emblems.size() > 0 else "Each emblem", emblems[1] if emblems.size() > 1 else "the other"])
		&"video_poker":
			var rows: Array[String] = []
			for rank: String in CasinoParams.POKER_RETURNS:
				if rank != "nothing":
					rows.append("%s %d" % [String(VideoPokerGame.LABELS[rank]), int(CasinoParams.POKER_RETURNS[rank])])
			lines.append("Jacks or better, a fresh deck every hand. Deal five cards, hold the ones you want (press them, or keys 1 to 5), then draw.")
			lines.append("Pays for 1, bet included: %s." % ", ".join(rows))
		&"faro":
			lines.append("Bet on ranks of the layout. Each turn the banker's card shows first and bets on its rank lose; then the player's card shows and bets on its rank win 1 to 1.")
			lines.append("When both cards share a rank it is a split and the house takes half. A coppered bet (the tab under a card) backs the rank to lose. Bets whose rank does not show come back.")
		&"chuck_a_luck":
			lines.append("Three dice tumble in the cage. A bet on a number wins 1 to 1 for each die that shows it and loses if none do. Any triple pays 30 to 1.")
		&"baccarat":
			lines.append("Player and Banker each take two cards, and a third by the standard tableau. Closest to nine wins: tens and court cards count zero, and only a total's last digit counts.")
			lines.append("Player pays 1 to 1, Banker 1 to 1 less a 5% commission, Tie 8 to 1. Player and Banker bets come back on a tie.")
		&"trajectory":
			lines.append("Launch and watch the multiplier climb. Cash out (Enter or Space) before the engine burns out to collect the stake times the multiplier; a burn-out loses the stake.")
			lines.append("One launch in %d fails on the pad. Set an automatic cash-out (A) before launch to let the flight decide." % CasinoParams.TRAJECTORY_FAIL_ONE_IN)
	lines.append("Table limits %s to %s per round; the treasury caps the maximum. Every bet comes from the city treasury and every win goes back to it." % [
		CasinoLines.money(int(limits.get("minimum", table["minimum"]))), CasinoLines.money(int(table["maximum"]))])
	lines.append("A round that stakes more than half of the treasury asks first: press Enter or the button again to confirm.")
	lines.append("Keys: arrows choose a spot, 1 to 5 or the chips add a bet, + and - adjust it (hold to repeat), Enter plays, R repeats the last bet, Escape finishes the animation and then leaves between rounds.")
	return "\n\n".join(lines)
