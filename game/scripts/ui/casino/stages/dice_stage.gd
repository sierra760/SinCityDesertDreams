# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Chuck-a-luck: three dice in an hourglass wire cage. The cage turns over,
## the dice tumble and settle; bets sit on the six numbers and on any triple.
class_name DiceStage
extends CasinoStage

const PIPS := {
	1: [Vector2(0, 0)],
	2: [Vector2(-1, -1), Vector2(1, 1)],
	3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
	5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
	6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
}

var _dice: Array = []


func design_size(tall_layout: bool) -> Vector2:
	return Vector2(520, 760) if tall_layout else Vector2(900, 420)


func _banner_rest(_design: Vector2) -> Rect2:
	return Rect2(20, 708, 480, 50) if _tall else Rect2(420, 340, 440, 64)


func spot_order() -> Array[StringName]:
	return [&"die_1", &"die_2", &"die_3", &"die_4", &"die_5", &"die_6", &"any_triple"]


func _reset_model() -> void:
	_sync_model()


func _sync_model() -> void:
	_dice = (view.get("dice", []) as Array).duplicate()


func _animation_key(event: Dictionary) -> String:
	if String(event.get("kind", "")) == "dice":
		return "dice"
	return super._animation_key(event)


func _begin_event(event: Dictionary) -> void:
	if String(event.get("kind", "")) == "dice":
		_winners.clear()


func _finish_event(event: Dictionary) -> void:
	if String(event.get("kind", "")) != "dice":
		return
	_dice = (event.get("dice", []) as Array).duplicate()
	for spot: StringName in _bets():
		if ChuckALuckGame.bet_return(spot, _dice) > 0:
			_winners[spot] = true


func _draw_stage() -> void:
	var center := Vector2(260, 190) if _tall else Vector2(200, 200)
	var rolling := String(_current.get("kind", "")) == "dice"
	var turn := _progress * TAU if rolling else 0.0
	_draw_cage(center, turn, rolling)
	_draw_board()


func _draw_cage(center: Vector2, turn: float, rolling: bool) -> void:
	var half := Vector2(120, 150)
	var waist := 34.0
	var squash := cos(turn)
	var stand := Rect2(center + Vector2(-140, half.y + 8), Vector2(280, 18))
	_round_rect(stand, palette.wood, 6.0, palette.metal, 2.0)
	draw_line(center + Vector2(-half.x - 14, 0), center + Vector2(-half.x - 14, half.y + 10), palette.metal, 6.0, true)
	draw_line(center + Vector2(half.x + 14, 0), center + Vector2(half.x + 14, half.y + 10), palette.metal, 6.0, true)
	var top := center.y - half.y * squash
	var bottom := center.y + half.y * squash
	var wire := Color(palette.metal.lightened(0.3), 0.9)
	var glass := Color(palette.lamp, 0.12)
	draw_colored_polygon(PackedVector2Array([Vector2(center.x - half.x, top), Vector2(center.x + half.x, top), Vector2(center.x + waist, center.y), Vector2(center.x - waist, center.y)]), glass)
	draw_colored_polygon(PackedVector2Array([Vector2(center.x - waist, center.y), Vector2(center.x + waist, center.y), Vector2(center.x + half.x, bottom), Vector2(center.x - half.x, bottom)]), glass)
	for i in 9:
		var f := i / 8.0
		var x_top := lerpf(center.x - half.x, center.x + half.x, f)
		var x_mid := lerpf(center.x - waist, center.x + waist, f)
		draw_line(Vector2(x_top, top), Vector2(x_mid, center.y), wire, 1.5, true)
		draw_line(Vector2(x_mid, center.y), Vector2(x_top, bottom), wire, 1.5, true)
	for y in [top, bottom]:
		draw_line(Vector2(center.x - half.x - 6, y), Vector2(center.x + half.x + 6, y), palette.metal, 6.0, true)
	draw_line(Vector2(center.x - waist - 4, center.y), Vector2(center.x + waist + 4, center.y), palette.metal, 5.0, true)
	draw_circle(Vector2(center.x - half.x - 14, center.y), 8.0, palette.metal, true, -1.0, true)
	draw_circle(Vector2(center.x + half.x + 14, center.y), 8.0, palette.metal, true, -1.0, true)
	# The dice: tumbling while the cage turns, then resting in its lower bowl.
	var shown: Array = _dice
	if rolling:
		shown = []
		var tick := int(_progress * 18.0)
		for i in 3:
			shown.append(1 + posmod(tick * 7 + i * 3 + int(turn * 2.0) * (i + 1), 6))
	if shown.is_empty():
		return
	for i in shown.size():
		var rest := Vector2(center.x + (i - 1) * 46.0, bottom - 32.0 * absf(squash) - 6.0)
		if rolling:
			var fall := sin(_progress * PI * 3.0 + i)
			rest = Vector2(center.x + (i - 1) * 40.0 + sin(turn * 2.0 + i) * 20.0, center.y + fall * half.y * 0.45 * absf(squash))
		var spin := turn * (1.5 + i * 0.4) if rolling else 0.0
		_draw_die(rest, 19.0, int(shown[i]), spin)


func _draw_die(center: Vector2, half_size: float, value: int, angle: float) -> void:
	draw_set_transform_matrix(_xf * Transform2D(angle, center))
	var rect := Rect2(Vector2(-half_size, -half_size), Vector2(half_size, half_size) * 2.0)
	_round_rect(Rect2(rect.position + Vector2(2, 3), rect.size), Color(0, 0, 0, 0.3), half_size * 0.3)
	_round_rect(rect, CasinoPalette.CARD_FACE, half_size * 0.3, CasinoPalette.CARD_EDGE, 1.5)
	var pips: Array = PIPS.get(clampi(value, 1, 6), [])
	for pip: Vector2 in pips:
		var color := CasinoPalette.CARD_RED if value == 1 else palette.ink
		draw_circle(pip * half_size * 0.52, half_size * 0.17, color, true, -1.0, true)
	draw_set_transform_matrix(_xf)


func _draw_board() -> void:
	var origin := Vector2(20, 400) if _tall else Vector2(420, 26)
	var cell := Vector2(155, 110) if _tall else Vector2(140, 110)
	var gap := 10.0
	for n in range(1, 7):
		var col := (n - 1) % 3
		var row := 0 if n <= 3 else 1
		var rect := Rect2(origin + Vector2(col * (cell.x + gap), row * (cell.y + gap)), cell)
		var spot := StringName("die_%d" % n)
		_draw_spot(spot, rect, "", "", Color(0, 0, 0, 0))
		var face_center := Vector2(rect.get_center().x, rect.position.y + (34.0 if int(_bets().get(spot, 0)) > 0 else rect.size.y * 0.42))
		_draw_die(face_center, 22.0, n, 0.0)
		if int(_bets().get(spot, 0)) <= 0:
			_text(Vector2(rect.get_center().x, rect.end.y - 16.0), "1 to 1 each die", 12, palette.felt_line)
	var width := 3.0 * cell.x + 2.0 * gap
	var triple := Rect2(origin + Vector2(0, 2.0 * (cell.y + gap)), Vector2(width, 64))
	_draw_spot(&"any_triple", triple, "Any triple", "30 to 1", palette.felt.darkened(0.12), 20)
	var history: Array = view.get("history", [])
	var y := triple.end.y + 28.0
	_text_left(Vector2(origin.x, y), "Last rolls", 13, palette.felt_line)
	var x := origin.x + 86.0
	for roll in history:
		var dice: Array = roll
		var text := "%d %d %d" % [int(dice[0]), int(dice[1]), int(dice[2])] if dice.size() == 3 else ""
		var w := palette.body_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		if x + w > origin.x + width:
			break
		_text_left(Vector2(x, y), text, 13, palette.felt_line)
		x += w + 16.0
