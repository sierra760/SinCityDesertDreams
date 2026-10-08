# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Card tables: blackjack, baccarat and video poker. Cards slide from the
## shoe, hole cards and replaced poker cards turn over, and each hand shows
## its total and result. Poker cards are pressed (or keys 1–5) to hold them.
class_name CardStage
extends CasinoStage

const WIDE_CARD := Vector2(74, 104)
const POKER_WIDE_CARD := Vector2(112, 160)
const POKER_TALL_CARD := Vector2(90, 128)

## Blackjack: the dealer's cards and the player's hands
## ([{cards, result, doubled}]).
var _dealer: Array = []
var _hands: Array = []
## Baccarat: each side's cards.
var _player: Array = []
var _banker: Array = []
var _winner := ""
## Video poker: the five cards and the paying hand.
var _cards: Array = []
var _rank := ""


func design_size(tall_layout: bool) -> Vector2:
	match game.kind if game != null else &"":
		&"baccarat":
			return Vector2(520, 560) if tall_layout else Vector2(900, 420)
		&"video_poker":
			return Vector2(520, 600) if tall_layout else Vector2(900, 420)
	return Vector2(520, 640) if tall_layout else Vector2(900, 420)


func _banner_rest(_design: Vector2) -> Rect2:
	match game.kind:
		&"baccarat":
			return Rect2(60, 470, 400, 64) if _tall else Rect2(450, 336, 420, 64)
		&"video_poker":
			return Rect2(90, 400, 340, 64) if _tall else Rect2(300, 342, 340, 64)
	return Rect2(130, 440, 260, 64) if _tall else Rect2(24, 20, 250, 64)


func spot_order() -> Array[StringName]:
	if game != null and game.kind == &"baccarat":
		return [&"player", &"tie", &"banker"]
	return super.spot_order()


func _reset_model() -> void:
	_dealer.clear()
	_hands.clear()
	_player.clear()
	_banker.clear()
	_winner = ""
	_cards.clear()
	_rank = ""


func _sync_model() -> void:
	match game.kind:
		&"blackjack":
			var dealer: Dictionary = view.get("dealer", {})
			_dealer = (dealer.get("cards", []) as Array).duplicate(true)
			_hands.clear()
			for hand: Dictionary in view.get("hands", []):
				_hands.append({"cards": (hand["cards"] as Array).duplicate(true), "result": String(hand.get("result", "")),
					"doubled": bool(hand.get("doubled", false))})
		&"baccarat":
			_player = ((view.get("player", {}) as Dictionary).get("cards", []) as Array).duplicate(true)
			_banker = ((view.get("banker", {}) as Dictionary).get("cards", []) as Array).duplicate(true)
			_winner = String(view.get("winner", ""))
		&"video_poker":
			_cards = (view.get("cards", []) as Array).duplicate(true)
			_rank = String(view.get("rank_label", ""))


func _animation_key(event: Dictionary) -> String:
	match String(event.get("kind", "")):
		"reveal":
			return "flip"
		"card":
			return "flip" if bool(event.get("replace", false)) else "card"
		"blackjack", "bust", "dealer_stands", "natural", "hand_rank", "split", "double":
			return "beat"
	return super._animation_key(event)


func _finish_event(event: Dictionary) -> void:
	var kind := String(event.get("kind", ""))
	match kind:
		"card":
			var card: Dictionary = event["card"]
			match String(event.get("to", "")):
				"dealer":
					_dealer.append(card)
				"player":
					if game.kind == &"baccarat":
						_player.append(card)
					else:
						var h := int(event.get("hand", 0))
						while _hands.size() <= h:
							_hands.append({"cards": [], "result": "", "doubled": false})
						(_hands[h]["cards"] as Array).append(card)
				"banker":
					_banker.append(card)
				"hand":
					var i := int(event.get("index", 0))
					while _cards.size() <= i:
						_cards.append({"rank": 0, "suit": 0, "face_up": false})
					_cards[i] = card
		"reveal":
			if _dealer.size() >= 2:
				_dealer[1] = event["card"]
		"split":
			var h := int(event.get("hand", 0))
			if h < _hands.size():
				var cards: Array = _hands[h]["cards"]
				if not cards.is_empty():
					var moved: Dictionary = cards.pop_back()
					_hands.insert(h + 1, {"cards": [moved], "result": "", "doubled": false})
		"double":
			var h := int(event.get("hand", 0))
			if h < _hands.size():
				_hands[h]["doubled"] = true
		"result":
			if game.kind == &"baccarat":
				_winner = String(event.get("winner", ""))
				_winners.clear()
				_winners[StringName(_winner)] = true
			else:
				var h := int(event.get("hand", 0))
				if h < _hands.size():
					_hands[h]["result"] = String(event.get("result", ""))
		"hand_rank":
			_rank = String(event.get("label", ""))
			if int(event.get("returns", 0)) > 0:
				_winners[&"hand"] = true


## Hold a poker card when it is pressed during a hand.
func _press(design_point: Vector2) -> bool:
	if game.kind != &"video_poker" or game.state != CasinoGame.PLAYING:
		return false
	for i in _cards.size():
		if _poker_card_rect(i).grow_side(SIDE_BOTTOM, 40.0).has_point(design_point):
			stage_action.emit(&"hold", {"index": i})
			return true
	return false


func _draw_stage() -> void:
	match game.kind:
		&"baccarat":
			_draw_baccarat()
		&"video_poker":
			_draw_poker()
		_:
			_draw_blackjack()


# ── Blackjack ────────────────────────────────────────────────────────────

func _draw_blackjack() -> void:
	var design := design_size(_tall)
	var card := WIDE_CARD
	var dealer_y := 36.0
	var hands_y := 300.0 if _tall else 196.0
	var shoe := Vector2(30, 500) if _tall else Vector2(796, 24)
	var spot := Rect2(design.x * 0.5 - 80, 520, 160, 90) if _tall else Rect2(design.x * 0.5 - 80, 334, 160, 76)
	_draw_shoe(shoe, card)
	if _current.get("kind", "") == "shuffle":
		_text(shoe + Vector2(card.x * 0.5, card.y + 22), "Shuffling…", 15, palette.felt_line)
	# The flying card's destination joins its row so the row stays centred.
	var flying := _current if String(_current.get("kind", "")) == "card" else {}
	var dealer_count := _dealer.size() + (1 if String(flying.get("to", "")) == "dealer" else 0)
	var dealer_slots := _row_positions(dealer_count, design.x * 0.5, dealer_y, card.x, 54.0)
	for i in _dealer.size():
		var c: Dictionary = _dealer[i]
		var flip := 1.0
		if String(_current.get("kind", "")) == "reveal" and i == 1:
			flip = absf(cos(_progress * PI))
			if _progress >= 0.5:
				c = _current["card"]
		_draw_card(Rect2(dealer_slots[i], card), c, flip)
	if String(flying.get("to", "")) == "dealer":
		_draw_flying_card(shoe, dealer_slots[dealer_count - 1], card, flying["card"], _progress)
	if not _dealer.is_empty():
		var shown: Array = []
		for c: Dictionary in _dealer:
			if bool(c.get("face_up", true)) and int(c.get("rank", 0)) > 0:
				shown.append(c)
		var dealer_total := int(BlackjackGame.total_of(shown)["total"])
		var hidden := shown.size() < _dealer.size()
		_text(Vector2(design.x * 0.5, dealer_y + card.y + 20), ("Dealer shows %d" if hidden else "Dealer %d") % dealer_total, 18, palette.felt_line)
	# Player hands, side by side.
	var counts: Array[int] = []
	for h in _hands.size():
		var n := (_hands[h]["cards"] as Array).size()
		if String(flying.get("to", "")) == "player" and int(flying.get("hand", 0)) == h:
			n += 1
		counts.append(n)
	if String(flying.get("to", "")) == "player" and int(flying.get("hand", 0)) >= _hands.size():
		counts.append(1)
	var step := 30.0
	var widths: Array[float] = []
	var total_width := 0.0
	for n in counts:
		var w := card.x + maxi(0, n - 1) * step
		widths.append(w)
		total_width += w
	total_width += maxi(0, counts.size() - 1) * 36.0
	var x := design.x * 0.5 - total_width * 0.5
	var active := int(view.get("active_hand", -1)) if game.state == CasinoGame.PLAYING and not is_busy() else -1
	for h in counts.size():
		var cards: Array = _hands[h]["cards"] if h < _hands.size() else []
		if h == active:
			_round_rect(Rect2(x - 8, hands_y - 8, widths[h] + 16, card.y + 16), Color(palette.lamp, 0.25), 10.0, palette.lamp, 2.0)
		for i in cards.size():
			_draw_card(Rect2(Vector2(x + i * step, hands_y), card), cards[i])
		if String(flying.get("to", "")) == "player" and int(flying.get("hand", 0)) == h:
			_draw_flying_card(shoe, Vector2(x + cards.size() * step, hands_y), card, flying["card"], _progress)
		if not cards.is_empty():
			var t := BlackjackGame.total_of(cards)
			var label := ("Soft %d" if bool(t["soft"]) and int(t["total"]) < 21 else "%d") % int(t["total"])
			var result := String(_hands[h]["result"]) if h < _hands.size() else ""
			var color := palette.felt_line
			if not result.is_empty():
				label = "%s · %s" % [label, _result_word(result)]
				color = CasinoPalette.WIN_ON_FELT if result in ["win", "blackjack"] else (palette.lamp if result == "push" else CasinoPalette.LOSE_ON_FELT)
			if h < _hands.size() and bool(_hands[h]["doubled"]):
				label += " · doubled"
			_text_fit(Vector2(x + widths[h] * 0.5, hands_y + card.y + 20), label, 17, color, palette.body_font, maxf(widths[h] + 30.0, 120.0))
		x += widths[h] + 36.0
	_draw_spot(&"main", spot, "Bet", "Pays 1 to 1 · 21 pays 3 to 2", Color(0, 0, 0, 0), 20)


static func _result_word(result: String) -> String:
	match result:
		"win":
			return "wins"
		"blackjack":
			return "blackjack"
		"push":
			return "push"
		"bust":
			return "bust"
	return "loses"


## Top-left corners of `count` cards in a row centred on `center_x`.
static func _row_positions(count: int, center_x: float, y: float, card_width: float, step: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var width := card_width + maxi(0, count - 1) * step
	for i in count:
		out.append(Vector2(center_x - width * 0.5 + i * step, y))
	return out


# ── Baccarat ─────────────────────────────────────────────────────────────

func _draw_baccarat() -> void:
	var design := design_size(_tall)
	var card := WIDE_CARD
	var shoe := Vector2(223, 40) if _tall else Vector2(413, 34)
	_draw_shoe(shoe, card)
	if _current.get("kind", "") == "shuffle":
		_text(shoe + Vector2(card.x * 0.5, card.y + 22), "Shuffling…", 15, palette.felt_line)
	var flying := _current if String(_current.get("kind", "")) == "card" else {}
	var sides := [["player", _player, 130.0 if _tall else 210.0], ["banker", _banker, 390.0 if _tall else 690.0]]
	var step := 50.0 if _tall else 80.0
	for side: Array in sides:
		var who: String = side[0]
		var cards: Array = side[1]
		var cx: float = side[2]
		var count := cards.size() + (1 if String(flying.get("to", "")) == who else 0)
		var slots := _row_positions(count, cx, 50.0, card.x, step)
		_text(Vector2(cx, 26), who.to_upper(), 18, palette.felt_line, palette.sign_font)
		for i in cards.size():
			_draw_card(Rect2(slots[i], card), cards[i])
		if String(flying.get("to", "")) == who:
			_draw_flying_card(shoe, slots[count - 1], card, flying["card"], _progress)
		if not cards.is_empty():
			var total := BaccaratGame.total_of(cards)
			var won := _winner == who
			_text(Vector2(cx, 50 + card.y + 22), str(total), 24, CasinoPalette.GOLD if won else palette.felt_line)
	var boxes_y := 300.0 if _tall else 228.0
	var box_h := 110.0 if _tall else 100.0
	var specs := [[&"player", "Player", "1 to 1"], [&"tie", "Tie", "8 to 1"], [&"banker", "Banker", "1 to 1, 5% commission"]]
	var width := (design.x - 40.0 - 2.0 * 16.0) / 3.0
	for i in specs.size():
		var spec: Array = specs[i]
		var fill := palette.felt.lightened(0.08) if spec[0] == &"tie" else palette.felt.darkened(0.08)
		_draw_spot(spec[0], Rect2(20.0 + i * (width + 16.0), boxes_y, width, box_h), spec[1], spec[2], fill, 22)
	# The scoreboard: the latest coups, newest first.
	var history: Array = view.get("history", [])
	var y := boxes_y + box_h + 34.0
	_text_left(Vector2(20, y), "Recent coups", 14, palette.felt_line)
	for i in mini(history.size(), 12):
		var winner := String(history[i])
		var color := Color("3f6fb0") if winner == "player" else (Color("c0503a") if winner == "banker" else CasinoPalette.WIN)
		var center := Vector2(150.0 + i * 30.0, y) if not _tall else Vector2(150.0 + i * 28.0, y)
		if center.x > design.x - 20.0:
			break
		draw_circle(center, 11.0, color, true, -1.0, true)
		_text(center, winner.substr(0, 1).to_upper(), 12, Color.WHITE)


# ── Video poker ──────────────────────────────────────────────────────────

func _poker_card_size() -> Vector2:
	return POKER_TALL_CARD if _tall else POKER_WIDE_CARD


func _poker_card_rect(i: int) -> Rect2:
	var card := _poker_card_size()
	var step := card.x + (8.0 if _tall else 16.0)
	var design := design_size(_tall)
	var left := design.x * 0.5 - (5.0 * step - (step - card.x)) * 0.5
	return Rect2(Vector2(left + i * step, 180.0 if _tall else 128.0), card)


func _draw_poker() -> void:
	var design := design_size(_tall)
	var screen := Rect2(Vector2(12, 10), design - Vector2(24, 20))
	_round_rect(screen, palette.ink, 14.0, palette.metal, 3.0)
	# Paytable, best hand first; the paying row lights up.
	var table: Array = view.get("paytable", [])
	var columns := 2 if _tall else 3
	var rows := ceili(float(table.size()) / float(columns))
	var col_w := (screen.size.x - 24.0) / columns
	for i in table.size():
		var row: Dictionary = table[i]
		var col := floori(float(i) / float(rows)) if rows > 0 else 0
		var r := i % rows if rows > 0 else 0
		var at := Vector2(screen.position.x + 12.0 + col * col_w, 34.0 + r * 26.0)
		var lit := String(row["label"]) == _rank and _winners.has(&"hand")
		if lit:
			_round_rect(Rect2(at - Vector2(6, 12), Vector2(col_w - 6, 24)), palette.lamp, 4.0)
		_text_left(at, String(row["label"]), 15, palette.ink if lit else palette.paper)
		var pays := str(int(row["returns"]))
		var w := palette.body_font.get_string_size(pays, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		_text_left(at + Vector2(col_w - 18.0 - w, 0), pays, 15, palette.ink if lit else palette.lamp)
	var card := _poker_card_size()
	var held: Array = view.get("held", [])
	var flying := _current if String(_current.get("kind", "")) == "card" else {}
	var shoe := Vector2(design.x * 0.5 - card.x * 0.5, design.y)
	for i in 5:
		var rect := _poker_card_rect(i)
		if i >= _cards.size() and not (flying.size() > 0 and int(flying.get("index", -1)) == i):
			_round_rect(rect, Color(palette.paper, 0.08), 8.0, Color(palette.paper, 0.3), 1.0)
			continue
		var is_flying := not flying.is_empty() and int(flying.get("index", -1)) == i
		if is_flying and not bool(flying.get("replace", false)):
			_draw_flying_card(shoe, rect.position, card, flying["card"], _progress)
		elif is_flying:
			var turning: Dictionary = _cards[i] if _progress < 0.5 else flying["card"]
			_draw_card(rect, turning, absf(cos(_progress * PI)))
		else:
			_draw_card(rect, _cards[i])
		if i < held.size() and bool(held[i]):
			var tag := Rect2(rect.position.x, rect.end.y + 8, rect.size.x, 28)
			_round_rect(tag, palette.lamp, 5.0)
			_text(tag.get_center(), "HELD", 16, palette.ink)
		elif game.state == CasinoGame.PLAYING:
			_text(Vector2(rect.get_center().x, rect.end.y + 22), "%d · hold" % (i + 1), 13, Color(palette.paper, 0.6))
	var bottom := design.y - 54.0
	if not _rank.is_empty() and _banner.is_empty():
		_text_left(Vector2(screen.position.x + 22, bottom + 6), _rank, 24, palette.lamp if _winners.has(&"hand") else palette.paper, palette.sign_font)
	elif game.state == CasinoGame.PLAYING:
		_text_left(Vector2(screen.position.x + 22, bottom + 6), "Hold cards, then draw", 18, palette.paper)
	_draw_spot(&"hand", Rect2(screen.end.x - 200.0, bottom - 22.0, 184.0, 56.0), "Bet", "", palette.felt, 18)
