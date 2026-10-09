# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Base for the table views: draws a game's felt, cards, wheels and bet spots
## and animates the game's event log one entry at a time.
##
## A stage lays its table out in design units (`design_size()`) and scales
## that picture uniformly to fit its rectangle, choosing a wide or a tall
## arrangement by the rectangle's shape. Events from `CasinoGame.take_events()`
## go to `play()`; each runs for its duration in `CasinoTableOverlay.ANIMATION`
## (scaled by `CasinoTableOverlay.animation_scale`; zero applies it at once)
## and is reported through `event_finished`. A stage never changes the game:
## it asks the overlay through `spot_pressed` and `stage_action`.
class_name CasinoStage
extends Control

## The player pressed a bet spot on the table.
signal spot_pressed(spot: StringName)
## The table asks the overlay to perform a game action (a poker hold, a
## climbing multiplier).
signal stage_action(action: StringName, payload: Dictionary)
signal event_started(event: Dictionary)
signal event_finished(event: Dictionary)
## Every queued event has played.
signal idle

var game: CasinoGame
var palette: CasinoPalette
var resort: StringName = &""
## The game's latest view_state().
var view: Dictionary = {}
## The spot that chips go to.
var selected_spot: StringName = &""

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _progress := 0.0
var _tween: Tween
var _advancing := false
var _instant := false
## Spot id -> Rect2 in design units, filled while drawing.
var _spot_rects: Dictionary = {}
## Spot id -> true for bets that won this round.
var _winners: Dictionary = {}
var _xf := Transform2D.IDENTITY
var _tall := false
var _banner: Dictionary = {}
var _banner_t := 1.0
var _banner_tween: Tween
var _clock := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	custom_minimum_size = Vector2(160, 120)


## Bind the stage to a game and its resort.
func setup(table_game: CasinoGame, resort_key: StringName, colors: CasinoPalette) -> void:
	game = table_game
	resort = resort_key
	palette = colors
	selected_spot = default_spot()
	view = game.view_state() if game != null else {}
	reset_round()


## The spot a first chip goes to: the table's plainest even bet. The first
## spot in keyboard order unless a table names a safer one (roulette: Red).
func default_spot() -> StringName:
	var ids := spot_order()
	return ids[0] if not ids.is_empty() else &""


## Forget the round's drawing state (a new round began).
func reset_round() -> void:
	_winners.clear()
	_banner.clear()
	if game != null:
		view = game.view_state()
	_reset_model()
	queue_redraw()


## Take the game's latest state. While events play, the table keeps
## showing the state they started from and catches up once they finish.
func sync(state: Dictionary) -> void:
	if is_busy():
		return
	view = state
	_sync_model()
	queue_redraw()


## Queue events from the game's log and start playing them.
func play(events: Array[Dictionary]) -> void:
	_queue.append_array(events)
	if _current.is_empty():
		_advance()


## True while events are playing or waiting.
func is_busy() -> bool:
	return not _current.is_empty() or not _queue.is_empty()


## Finish every queued animation at once.
func skip() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_instant = true
	if not _current.is_empty():
		_end_current()
	_advance()
	_instant = false
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_t = 1.0
	queue_redraw()


## Bet spot ids in keyboard order (left/right steps, up/down jumps a row).
func spot_order() -> Array[StringName]:
	var out: Array[StringName] = []
	if game != null:
		for s: Dictionary in game.spots():
			out.append(StringName(s["id"]))
	return out


## Spots per keyboard row; up and down move by this many.
func spot_columns() -> int:
	return maxi(1, spot_order().size())


## Move the selection by `step` in keyboard order, wrapping.
func move_selection(step: int) -> void:
	var ids := spot_order()
	if ids.is_empty():
		return
	var index := maxi(0, ids.find(selected_spot))
	selected_spot = ids[posmod(index + step, ids.size())]
	queue_redraw()


## Move the selection to the nearest spot in `direction` on the drawn table
## (falls back to keyboard order before the first draw).
func move_selection_toward(direction: Vector2) -> void:
	if _spot_rects.is_empty() or not _spot_rects.has(selected_spot):
		move_selection(1 if direction.x + direction.y > 0.0 else -1)
		return
	var from: Vector2 = (_spot_rects[selected_spot] as Rect2).get_center()
	var best: StringName = &""
	var best_score := INF
	for spot: StringName in _spot_rects:
		if spot == selected_spot:
			continue
		var offset: Vector2 = (_spot_rects[spot] as Rect2).get_center() - from
		var along := offset.dot(direction)
		if along <= 1.0:
			continue
		var across := absf(offset.dot(Vector2(-direction.y, direction.x)))
		var score := along + across * 2.5
		if score < best_score:
			best_score = score
			best = spot
	if best != &"":
		selected_spot = best
		queue_redraw()


## Spot label and odds for readouts.
func spot_info(spot: StringName) -> Dictionary:
	if game != null:
		for s: Dictionary in game.spots():
			if StringName(s["id"]) == spot:
				return s
	return {}


## A spot's display name; themed games override it.
func spot_label(spot: StringName) -> String:
	return String(spot_info(spot).get("label", String(spot)))


## The design-unit rectangle of a spot, for tests and hit testing.
func spot_rect(spot: StringName) -> Rect2:
	return _spot_rects.get(spot, Rect2())


## The spot under a local point, or &"".
func spot_at(point: Vector2) -> StringName:
	var p := _xf.affine_inverse() * point
	for spot: StringName in _spot_rects:
		if (_spot_rects[spot] as Rect2).has_point(p):
			return spot
	return &""


## A local point for a design-unit point (tests press spots with it).
func to_local_point(design_point: Vector2) -> Vector2:
	return _xf * design_point


## Announce a result over the table. `flourish` adds the jackpot burst.
func show_banner(text: String, detail: String, color: Color, flourish: bool) -> void:
	_banner = {"text": text, "detail": detail, "color": color, "flourish": flourish}
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	var seconds := CasinoTableOverlay.seconds("flourish" if flourish else "banner")
	if seconds <= 0.0 or not is_inside_tree():
		_banner_t = 1.0
	else:
		_banner_t = 0.0
		_banner_tween = create_tween()
		_banner_tween.tween_method(_set_banner_t, 0.0, 1.0, seconds)
	queue_redraw()


func clear_banner() -> void:
	_banner.clear()
	queue_redraw()


func _set_banner_t(value: float) -> void:
	_banner_t = value
	queue_redraw()


# ── For subclasses ───────────────────────────────────────────────────────

## Design size of the wide (`tall` false) or tall arrangement.
func design_size(_tall_layout: bool) -> Vector2:
	return Vector2(900, 420)


func _reset_model() -> void:
	pass


func _sync_model() -> void:
	pass


## The ANIMATION key for an event.
func _animation_key(event: Dictionary) -> String:
	match String(event.get("kind", "")):
		"settle":
			return "settle"
		"shuffle":
			return "shuffle"
		"card":
			return "card"
		"result":
			return "result"
	return "beat"


## How long an event plays, already scaled by the overlay's animation scale.
func _event_seconds(event: Dictionary) -> float:
	return CasinoTableOverlay.seconds(_animation_key(event))


func _begin_event(_event: Dictionary) -> void:
	pass


func _finish_event(_event: Dictionary) -> void:
	pass


func _draw_stage() -> void:
	pass


## A press on the table that is not a spot (poker holds). True if used.
func _press(_design_point: Vector2) -> bool:
	return false


func _advance_clock(_delta: float) -> void:
	pass


# ── Event playback ───────────────────────────────────────────────────────

func _advance() -> void:
	if _advancing:
		return
	_advancing = true
	while not _queue.is_empty():
		var event: Dictionary = _queue.pop_front()
		_current = event
		_progress = 0.0
		_begin_event(event)
		event_started.emit(event)
		var seconds := 0.0 if _instant else _event_seconds(event)
		if seconds <= 0.0 or not is_inside_tree():
			_end_current()
			continue
		_tween = create_tween()
		_tween.tween_method(_set_progress, 0.0, 1.0, seconds)
		_tween.tween_callback(_on_tween_done)
		_advancing = false
		queue_redraw()
		return
	_advancing = false
	_current = {}
	if game != null:
		view = game.view_state()
		_sync_model()
	queue_redraw()
	idle.emit()


func _set_progress(value: float) -> void:
	_progress = value
	queue_redraw()


func _on_tween_done() -> void:
	_tween = null
	_end_current()
	_advance()


func _end_current() -> void:
	var event := _current
	_progress = 1.0
	_finish_event(event)
	_current = {}
	event_finished.emit(event)
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	_advance_clock(delta)


# ── Input ────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	var point := Vector2.ZERO
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
			return
		point = button.position
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if not touch.pressed:
			return
		point = touch.position
	else:
		return
	accept_event()
	if _press(_xf.affine_inverse() * point):
		return
	var spot := spot_at(point)
	if spot != &"":
		selected_spot = spot
		spot_pressed.emit(spot)
		queue_redraw()


# ── Drawing ──────────────────────────────────────────────────────────────

func _draw() -> void:
	if game == null or palette == null:
		return
	var wide := design_size(false)
	var tall := design_size(true)
	var aspect := size.x / maxf(1.0, size.y)
	_tall = absf(log(aspect / (tall.x / tall.y))) < absf(log(aspect / (wide.x / wide.y)))
	var design := tall if _tall else wide
	var s := minf(size.x / design.x, size.y / design.y)
	var offset := (size - design * s) * 0.5
	_xf = Transform2D(0.0, Vector2(s, s), 0.0, offset)
	draw_rect(Rect2(Vector2.ZERO, size), palette.felt_dark)
	draw_set_transform_matrix(_xf)
	var felt := Rect2(Vector2.ZERO, design).grow(-4.0)
	_round_rect(felt, palette.felt, 18.0, palette.metal, 3.0)
	_spot_rects.clear()
	_draw_stage()
	_draw_banner(design)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Where a result banner settles after its moment centre stage, in design
## units; stages pick a spot that leaves the cards and wheels visible.
func _banner_rest(design: Vector2) -> Rect2:
	return Rect2(design.x * 0.5 - 170.0, 8.0, 340.0, 64.0)


func _draw_banner(design: Vector2) -> void:
	if _banner.is_empty():
		return
	var t := clampf(_banner_t, 0.0, 1.0)
	var grow := 1.0 - pow(1.0 - minf(1.0, t / 0.35), 3.0)
	var settle := smoothstep(0.0, 1.0, clampf((t - 0.7) / 0.3, 0.0, 1.0))
	var center := Vector2(design.x * 0.5, design.y * 0.5)
	var color: Color = _banner["color"]
	if bool(_banner["flourish"]) and settle < 1.0:
		for ray in 24:
			var angle := TAU * ray / 24.0 + t * 0.8
			var inner := center + Vector2.from_angle(angle) * 40.0 * grow
			var outer := center + Vector2.from_angle(angle) * (design.y * 0.62) * grow
			draw_line(inner, outer, Color(CasinoPalette.GOLD, 0.55 * (1.0 - settle)), 5.0, true)
	var width := minf(design.x - 40.0, 560.0) * (0.6 + 0.4 * grow)
	var stage_box := Rect2(center - Vector2(width * 0.5, 54), Vector2(width, 108))
	var rest := _banner_rest(design)
	var box := Rect2(stage_box.position.lerp(rest.position, settle), stage_box.size.lerp(rest.size, settle))
	_round_rect(box, Color(palette.paper, 0.96), lerpf(14.0, 10.0, settle), color, lerpf(4.0, 3.0, settle))
	var title_size := int(lerpf(clampf(48.0 * grow, 12.0, 48.0), 26.0, settle))
	var title_y := box.position.y + lerpf(40.0, 22.0, settle)
	_text_fit(Vector2(box.get_center().x, title_y), String(_banner["text"]), title_size, color, palette.sign_font, box.size.x - 24.0)
	var detail := String(_banner["detail"])
	if not detail.is_empty():
		var detail_y := box.position.y + lerpf(82.0, 48.0, settle)
		_text_fit(Vector2(box.get_center().x, detail_y), detail, int(lerpf(20.0, 15.0, settle)), palette.ink, palette.body_font, box.size.x - 20.0)


## A rounded rectangle with an optional outline, in the current transform.
func _round_rect(rect: Rect2, fill: Color, radius: float, border: Color = Color(0, 0, 0, 0), width: float = 0.0) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(int(radius))
	box.corner_detail = 6
	box.anti_aliasing = true
	if width > 0.0:
		box.border_color = border
		box.set_border_width_all(int(ceilf(width)))
	draw_style_box(box, rect)


## Text centred on `center` (horizontally and on the cap height).
func _text(center: Vector2, text: String, font_size: int, color: Color, font: Font = null) -> void:
	var f := font if font != null else palette.body_font
	var width := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := center.y + (f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
	draw_string(f, Vector2(center.x - width * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Centred text shrunk until it fits `max_width`.
func _text_fit(center: Vector2, text: String, font_size: int, color: Color, font: Font, max_width: float) -> void:
	var f := font if font != null else palette.body_font
	var fitted := font_size
	while fitted > 8 and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > max_width:
		fitted -= 1
	_text(center, text, fitted, color, f)


## Left-aligned text with its cap height centred on `y`.
func _text_left(left: Vector2, text: String, font_size: int, color: Color, font: Font = null) -> void:
	var f := font if font != null else palette.body_font
	var baseline := left.y + (f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
	draw_string(f, Vector2(left.x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## The bets on the table now: spot -> amount.
func _bets() -> Dictionary:
	return game.bets() if game != null else {}


## Smallest odds-line size under a spot title before the line is left out.
const SUBTITLE_MIN_SIZE := 10


## A bet spot: a lined box with its label and odds, the selection glow, the
## winning highlight and the chips on it. Records its rectangle for presses.
## Chips sit beside the label on wide spots, below it on tall ones and in
## the corner of small ones, so the label stays readable.
func _draw_spot(spot: StringName, rect: Rect2, title: String, subtitle: String = "", fill: Color = Color(0, 0, 0, 0), title_size: int = 18) -> void:
	_spot_rects[spot] = rect
	var selected := spot == selected_spot and game != null and game.state != CasinoGame.PLAYING
	var won := _winners.has(spot)
	var base := fill if fill.a > 0.0 else Color(palette.felt.lightened(0.06), 1.0)
	var line := CasinoPalette.GOLD if won else (palette.lamp if selected else palette.felt_line)
	_round_rect(rect, base, 6.0, line, 4.0 if won or selected else 1.5)
	var amount := int(_bets().get(spot, 0))
	var text_color := palette.felt_line if fill.a <= 0.0 else Color.WHITE
	var label_area := rect
	var chip_center := Vector2.ZERO
	var chip_radius := 0.0
	if amount > 0:
		var side := clampf(rect.size.y * 0.34, 9.0, 24.0)
		var below := clampf(minf(rect.size.x, rect.size.y) * 0.26, 9.0, 24.0)
		if rect.size.x - side * 2.0 - 12.0 >= rect.size.x * 0.55:
			chip_radius = side
			chip_center = Vector2(rect.end.x - side - 8.0, rect.get_center().y)
			label_area = Rect2(rect.position, Vector2(rect.size.x - side * 2.0 - 12.0, rect.size.y))
		elif rect.size.y >= 64.0:
			chip_radius = below
			chip_center = Vector2(rect.get_center().x, rect.end.y - below - 6.0)
			label_area = Rect2(rect.position, Vector2(rect.size.x, rect.size.y - below * 2.0 - 8.0))
		else:
			chip_radius = clampf(minf(rect.size.x, rect.size.y) * 0.3, 8.0, 14.0)
			chip_center = rect.end - Vector2(chip_radius * 0.9, rect.size.y - chip_radius * 0.9)
	# The odds line only shows when it fits beside the chips at a readable
	# size; the bet bar's readout always repeats the selected spot's odds.
	var two_lines := not subtitle.is_empty() and label_area.size.y >= 52.0 \
		and palette.body_font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, SUBTITLE_MIN_SIZE).x <= label_area.size.x - 6.0
	var title_y := label_area.position.y + label_area.size.y * (0.38 if two_lines else 0.5)
	_text_fit(Vector2(label_area.get_center().x, title_y), title, title_size, text_color, palette.body_font, label_area.size.x - 6.0)
	if two_lines:
		_text_fit(Vector2(label_area.get_center().x, label_area.position.y + label_area.size.y * 0.72), subtitle, 12, Color(text_color, 0.8), palette.body_font, label_area.size.x - 6.0)
	if amount > 0:
		_draw_bet_chip(chip_center, chip_radius, amount)


## A chip showing `amount` at `center`.
func _draw_bet_chip(center: Vector2, radius: float, amount: int) -> void:
	var minimum := int(game.limits.get("minimum", 1))
	CasinoPalette.draw_chip(self, center, radius, CasinoPalette.chip_index(amount, minimum),
		CasinoPalette.chip_label(amount), palette.body_font, mini(4, 1 + floori(float(amount) / float(maxi(1, minimum * 5)))))


# ── Cards ────────────────────────────────────────────────────────────────

## A playing card in `rect`. `flip` below 1 narrows it (turning over);
## a face-down or hidden card shows its back.
func _draw_card(rect: Rect2, card: Dictionary, flip: float = 1.0, glow: Color = Color(0, 0, 0, 0)) -> void:
	var w := rect.size.x * absf(flip)
	var r := Rect2(rect.position + Vector2((rect.size.x - w) * 0.5, 0), Vector2(maxf(1.0, w), rect.size.y))
	var radius := rect.size.x * 0.09
	_round_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.3), radius)
	if glow.a > 0.0:
		_round_rect(r.grow(4.0), glow, radius + 4.0)
	var face_up := bool(card.get("face_up", true)) and int(card.get("rank", 0)) > 0
	if not face_up:
		_round_rect(r, palette.accent.darkened(0.15), radius, palette.paper, 2.0)
		var inner := r.grow(-r.size.x * 0.12)
		if inner.size.x > 4.0:
			_round_rect(inner, palette.accent.darkened(0.35), radius * 0.6, palette.lamp, 1.0)
			var step := maxf(6.0, rect.size.x * 0.16)
			var x := inner.position.x - inner.size.y
			while x < inner.end.x:
				var a := Vector2(x, inner.end.y)
				var b := Vector2(x + inner.size.y, inner.position.y)
				var clipped := _clip_segment(a, b, inner)
				if not clipped.is_empty():
					draw_line(clipped[0], clipped[1], Color(palette.lamp, 0.35), 1.0)
				x += step
		return
	_round_rect(r, CasinoPalette.CARD_FACE, radius, CasinoPalette.CARD_EDGE, 1.5)
	if flip < 0.35:
		return
	var rank := int(card.get("rank", 0))
	var suit := int(card.get("suit", 0))
	var color := CasinoPalette.CARD_RED if suit == 1 or suit == 2 else CasinoPalette.CARD_BLACK
	var rank_name := String(CasinoDeck.RANK_NAMES[rank]) if rank >= 1 and rank < CasinoDeck.RANK_NAMES.size() else "?"
	var corner := int(clampf(rect.size.y * 0.2, 9.0, 40.0))
	var cx := r.position.x + rect.size.x * 0.17
	_text(Vector2(cx, r.position.y + rect.size.y * 0.15), rank_name, corner, color, palette.body_font)
	_draw_suit(Vector2(cx, r.position.y + rect.size.y * 0.33), rect.size.y * 0.065, suit, color)
	_draw_suit(r.get_center() + Vector2(rect.size.x * 0.08, rect.size.y * 0.08), rect.size.y * 0.17, suit, color)


## A vector suit symbol of half-height `s` centred on `c`.
## Suits: 0 clubs, 1 diamonds, 2 hearts, 3 spades.
func _draw_suit(c: Vector2, s: float, suit: int, color: Color) -> void:
	match suit:
		1:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(0.72 * s, 0), c + Vector2(0, s), c + Vector2(-0.72 * s, 0)]), color)
		2:
			draw_circle(c + Vector2(-0.47 * s, -0.32 * s), 0.52 * s, color, true, -1.0, true)
			draw_circle(c + Vector2(0.47 * s, -0.32 * s), 0.52 * s, color, true, -1.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.98 * s, -0.16 * s), c + Vector2(0.98 * s, -0.16 * s), c + Vector2(0, s)]), color)
		3:
			draw_circle(c + Vector2(-0.47 * s, 0.14 * s), 0.52 * s, color, true, -1.0, true)
			draw_circle(c + Vector2(0.47 * s, 0.14 * s), 0.52 * s, color, true, -1.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.98 * s, 0.3 * s), c + Vector2(0.98 * s, 0.3 * s), c + Vector2(0, -s)]), color)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0.2 * s), c + Vector2(-0.38 * s, s), c + Vector2(0.38 * s, s)]), color)
		_:
			draw_circle(c + Vector2(0, -0.44 * s), 0.42 * s, color, true, -1.0, true)
			draw_circle(c + Vector2(-0.46 * s, 0.14 * s), 0.42 * s, color, true, -1.0, true)
			draw_circle(c + Vector2(0.46 * s, 0.14 * s), 0.42 * s, color, true, -1.0, true)
			draw_circle(c + Vector2(0, 0.02 * s), 0.22 * s, color, true, -1.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0.1 * s), c + Vector2(-0.38 * s, s), c + Vector2(0.38 * s, s)]), color)


## A card travelling from `from` to `to` (its top-left corners).
func _draw_flying_card(from: Vector2, to: Vector2, card_size: Vector2, card: Dictionary, t: float) -> void:
	var eased := 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)
	var at := from.lerp(to, eased) - Vector2(0, sin(eased * PI) * 18.0)
	_draw_card(Rect2(at, card_size), card if eased > 0.5 else {"rank": 0, "suit": 0, "face_up": false}, maxf(0.15, absf(cos(eased * PI))))


## A shoe (card dispenser) with its top card showing.
func _draw_shoe(at: Vector2, card_size: Vector2) -> void:
	var body := Rect2(at - Vector2(10, 8), card_size + Vector2(20, 16))
	_round_rect(body, palette.wood, 8.0, palette.metal, 2.0)
	_draw_card(Rect2(at + Vector2(-6, 0), card_size), {"rank": 0, "suit": 0, "face_up": false})


static func _clip_segment(a: Vector2, b: Vector2, rect: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - rect.position.x, rect.end.x - a.x, a.y - rect.position.y, rect.end.y - a.y]
	for i in 4:
		var pi_v: float = p[i]
		var qi: float = q[i]
		if is_zero_approx(pi_v):
			if qi < 0.0:
				return []
			continue
		var r := qi / pi_v
		if pi_v < 0.0:
			t0 = maxf(t0, r)
		else:
			t1 = minf(t1, r)
	if t0 > t1:
		return []
	return [a + d * t0, a + d * t1]
