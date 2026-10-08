# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Faro: the thirteen-card layout to bet on, the dealing box with the
## banker's (losing) and player's (winning) cards, and the case keeper that
## counts what is left of each rank. The lower tab of a layout card coppers a
## bet so it backs the rank to lose.
class_name FaroStage
extends CasinoStage

## Layout ranks: the top row runs ace to six with the seven at its end; the
## bottom row runs king down to eight.
const TOP_ROW: Array[int] = [1, 2, 3, 4, 5, 6, 7]
const BOTTOM_ROW: Array[int] = [13, 12, 11, 10, 9, 8]

var _banker: Dictionary = {}
var _player: Dictionary = {}
var _split := false


func design_size(tall_layout: bool) -> Vector2:
	return Vector2(520, 720) if tall_layout else Vector2(940, 420)


func spot_order() -> Array[StringName]:
	var out: Array[StringName] = []
	for rank in TOP_ROW + BOTTOM_ROW:
		out.append(StringName("rank_%d" % rank))
	for rank in TOP_ROW + BOTTOM_ROW:
		out.append(StringName("copper_%d" % rank))
	return out


func spot_label(spot: StringName) -> String:
	var text := String(spot)
	var rank := int(text.get_slice("_", 1))
	var rank_name := String(CasinoDeck.RANK_NAMES[rank]) if rank >= 1 and rank <= 13 else "?"
	return ("Copper " if text.begins_with("copper_") else "") + rank_name


func _reset_model() -> void:
	_sync_model()


func _sync_model() -> void:
	_banker = view.get("banker", {})
	_player = view.get("player", {})
	_split = not _banker.is_empty() and not _player.is_empty() and int(_banker.get("rank", 0)) == int(_player.get("rank", -1))


func _begin_event(event: Dictionary) -> void:
	if String(event.get("kind", "")) == "card" and String(event.get("to", "")) == "banker":
		_banker = {}
		_player = {}
		_split = false
		_winners.clear()


func _finish_event(event: Dictionary) -> void:
	match String(event.get("kind", "")):
		"card":
			if String(event.get("to", "")) == "banker":
				_banker = event["card"]
			else:
				_player = event["card"]
		"split":
			_split = true
		"result":
			var spot := StringName(String(event.get("spot", "")))
			if int(event.get("returned", 0)) > int(_bets().get(spot, 0)):
				_winners[spot] = true


func _banner_rest(_design: Vector2) -> Rect2:
	return Rect2(30, 650, 460, 64) if _tall else Rect2(650, 330, 270, 70)


func _card_size() -> Vector2:
	return Vector2(60, 84) if _tall else Vector2(72, 100)


func _layout_rect(rank: int) -> Rect2:
	var card := _card_size()
	var step := card.x + (10.0 if _tall else 12.0)
	var top := TOP_ROW.find(rank)
	var row := 0 if top >= 0 else 1
	var col := top if top >= 0 else BOTTOM_ROW.find(rank)
	var origin := Vector2(15, 28) if _tall else Vector2(30, 26)
	var row_gap := 150.0 if _tall else 176.0
	return Rect2(origin + Vector2(col * step + (step * 0.5 if row == 1 else 0.0), row * row_gap), card)


func _draw_stage() -> void:
	var case_counts: Array = view.get("case", [])
	for rank in TOP_ROW + BOTTOM_ROW:
		var rect := _layout_rect(rank)
		var spot := StringName("rank_%d" % rank)
		var copper := StringName("copper_%d" % rank)
		_spot_rects[spot] = rect
		var selected := selected_spot == spot and game.state != CasinoGame.PLAYING
		var glow := Color(CasinoPalette.GOLD, 0.8) if _winners.has(spot) else (Color(palette.lamp, 0.7) if selected else Color(0, 0, 0, 0))
		_draw_card(rect, {"rank": rank, "suit": 3, "face_up": true}, 1.0, glow)
		var gone := rank - 1 < case_counts.size() and int(case_counts[rank - 1]) <= 0
		if gone:
			_round_rect(rect, Color(0, 0, 0, 0.35), 6.0)
		var amount := int(_bets().get(spot, 0))
		if amount > 0:
			_draw_bet_chip(Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.7), minf(18.0, rect.size.x * 0.26), amount)
		var tab := Rect2(rect.position.x, rect.end.y + 4.0, rect.size.x, 26.0)
		_spot_rects[copper] = tab
		var copper_selected := selected_spot == copper and game.state != CasinoGame.PLAYING
		var copper_color := Color("b06b3a")
		var line := CasinoPalette.GOLD if _winners.has(copper) else (palette.lamp if copper_selected else palette.felt_line)
		_round_rect(tab, Color(copper_color, 0.85 if int(_bets().get(copper, 0)) > 0 else 0.35), 5.0, line, 3.0 if copper_selected or _winners.has(copper) else 1.0)
		var coppered := int(_bets().get(copper, 0))
		_text_fit(tab.get_center(), CasinoLines.money(coppered) if coppered > 0 else "copper", 12, Color.WHITE, palette.body_font, tab.size.x - 4.0)
	_draw_box()
	_draw_case_keeper()


func _draw_box() -> void:
	var card := Vector2(72, 100)
	var origin := Vector2(144, 330) if _tall else Vector2(660, 26)
	var box := Rect2(origin - Vector2(14, 10), Vector2(260, 150))
	_round_rect(box, palette.wood, 10.0, palette.metal, 2.0)
	var banker_at := origin + Vector2(10, 24)
	var player_at := origin + Vector2(140, 24)
	_text(banker_at + Vector2(card.x * 0.5, -12), "Banker", 14, palette.lamp)
	_text(player_at + Vector2(card.x * 0.5, -12), "Player", 14, palette.lamp)
	var deal := Vector2(origin.x + 75, origin.y + 24)
	var flying := _current if String(_current.get("kind", "")) == "card" else {}
	if not _banker.is_empty():
		_draw_card(Rect2(banker_at, card), _banker)
	elif String(flying.get("to", "")) == "banker":
		_draw_flying_card(deal, banker_at, card, flying["card"], _progress)
	if not _player.is_empty():
		_draw_card(Rect2(player_at, card), _player)
	elif String(flying.get("to", "")) == "player":
		_draw_flying_card(deal, player_at, card, flying["card"], _progress)
	if _split:
		_text(Vector2(box.get_center().x, box.end.y - 10), "Split: the house takes half", 13, CasinoPalette.GOLD)


func _draw_case_keeper() -> void:
	var counts: Array = view.get("case", [])
	var origin := Vector2(30, 520) if _tall else Vector2(650, 200)
	var width := 460.0 if _tall else 270.0
	var area := Rect2(origin, Vector2(width, 120))
	_round_rect(area, Color(palette.ink, 0.6), 8.0, palette.metal, 1.5)
	_text(Vector2(area.get_center().x, origin.y + 14), "Case keeper · %d cards left" % int(view.get("remaining", 52)), 13, palette.lamp)
	var col_w := (width - 16.0) / 13.0
	for rank in range(1, 14):
		var x := origin.x + 8.0 + (rank - 0.5) * col_w
		_text(Vector2(x, origin.y + 34), String(CasinoDeck.RANK_NAMES[rank]), 12, palette.paper)
		var left := int(counts[rank - 1]) if rank - 1 < counts.size() else 4
		for bead in 4:
			var at := Vector2(x, origin.y + 54 + bead * 16)
			draw_circle(at, minf(6.0, col_w * 0.35), palette.lamp if bead < left else Color(palette.paper, 0.18), true, -1.0, true)
	var history: Array = view.get("history", [])
	var y := area.end.y + 26.0
	if _tall:
		y = area.end.y + 30.0
	_text_left(Vector2(origin.x, y), "Turns", 13, palette.felt_line)
	var x := origin.x + 56.0
	for turn: Dictionary in history:
		if x > origin.x + width - 30.0:
			break
		var text := "%s/%s" % [CasinoDeck.RANK_NAMES[int(turn["banker"])], CasinoDeck.RANK_NAMES[int(turn["player"])]]
		_text_left(Vector2(x, y), text, 13, palette.felt_line)
		x += palette.body_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 12.0
