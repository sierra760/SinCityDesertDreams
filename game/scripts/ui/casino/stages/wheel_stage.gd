# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The money wheel: fifty-four segments with pegs round the rim and a leather
## pointer that ticks past each peg as the wheel slows to the drawn segment.
class_name WheelStage
extends CasinoStage

const TURNS := 3.0

var _angle := 0.0
var _spin_from := 0.0
var _spin_by := 0.0
var _segment := -1


func design_size(tall_layout: bool) -> Vector2:
	return Vector2(520, 800) if tall_layout else Vector2(900, 420)


func _banner_rest(_design: Vector2) -> Rect2:
	return Rect2(20, 700, 480, 64) if _tall else Rect2(440, 270, 432, 64)


func spot_order() -> Array[StringName]:
	return [&"seg_1", &"seg_2", &"seg_5", &"seg_10", &"seg_20", &"emblem_a", &"emblem_b"]


## A first chip goes on the 1 segment, the wheel's lowest odds.
func default_spot() -> StringName:
	return &"seg_1"


func spot_label(spot: StringName) -> String:
	var emblems := ResortThemes.wheel_emblems(resort)
	if spot == &"emblem_a" and emblems.size() > 0:
		return emblems[0]
	if spot == &"emblem_b" and emblems.size() > 1:
		return emblems[1]
	return super.spot_label(spot)


func _reset_model() -> void:
	_sync_model()


func _sync_model() -> void:
	_segment = int(view.get("segment", -1))
	if _segment >= 0 and String(_current.get("kind", "")) != "wheel":
		_angle = -_segment * _step()


func _step() -> float:
	return TAU / CasinoParams.WHEEL_LAYOUT.size()


func _animation_key(event: Dictionary) -> String:
	if String(event.get("kind", "")) == "wheel":
		return "wheel"
	return super._animation_key(event)


func _begin_event(event: Dictionary) -> void:
	if String(event.get("kind", "")) == "wheel":
		var segment := int(event.get("segment", 0))
		_spin_from = _angle
		_spin_by = TAU * TURNS + fposmod(-segment * _step() - _angle, TAU)
		_winners.clear()


func _finish_event(event: Dictionary) -> void:
	if String(event.get("kind", "")) == "wheel":
		_segment = int(event.get("segment", 0))
		_angle = fposmod(_spin_from + _spin_by, TAU)
		var symbol := String(event.get("symbol", ""))
		if int(_bets().get(MoneyWheelGame.spot_for(symbol), 0)) > 0:
			_winners[MoneyWheelGame.spot_for(symbol)] = true


func _current_angle() -> float:
	if String(_current.get("kind", "")) == "wheel":
		return _spin_from + _spin_by * (1.0 - pow(1.0 - _progress, 3.2))
	return _angle


func _draw_stage() -> void:
	var center := Vector2(260, 232) if _tall else Vector2(214, 214)
	var radius := 196.0 if _tall else 186.0
	var angle := _current_angle()
	_draw_wheel(center, radius, angle)
	_draw_board()


## Segment colors stay the same at every resort so the values read at a
## glance; only the emblems take the resort's gold.
func _segment_color(symbol: String) -> Color:
	match symbol:
		"1":
			return Color("f4ead6")
		"2":
			return Color("9cc3e0")
		"5":
			return Color("a9d08e")
		"10":
			return Color("e39a6a")
		"20":
			return Color("d0604a")
	return CasinoPalette.GOLD


func _draw_wheel(center: Vector2, radius: float, angle: float) -> void:
	var layout := CasinoParams.WHEEL_LAYOUT
	var step := _step()
	var emblems := ResortThemes.wheel_emblems(resort)
	draw_circle(center + Vector2(5, 7), radius + 10.0, Color(0, 0, 0, 0.3), true, -1.0, true)
	draw_circle(center, radius + 10.0, palette.wood, true, -1.0, true)
	draw_arc(center, radius + 8.0, 0.0, TAU, 96, palette.metal, 3.0, true)
	for i in layout.size():
		var symbol: String = layout[i]
		var a0 := angle + (i - 0.5) * step - PI * 0.5
		var points := PackedVector2Array([center])
		for k in 4:
			points.append(center + Vector2.from_angle(a0 + step * k / 3.0) * radius)
		var fill := _segment_color(symbol)
		if i == _segment and String(_current.get("kind", "")) != "wheel":
			fill = fill.lightened(0.3)
		draw_colored_polygon(points, fill)
		draw_line(center + Vector2.from_angle(a0) * radius * 0.3, center + Vector2.from_angle(a0) * radius, Color(palette.ink, 0.5), 1.0, true)
		var mid := a0 + step * 0.5
		var text := symbol
		var font_size := int(radius * 0.085)
		if symbol.begins_with("emblem"):
			var e := 0 if symbol == "emblem_a" else 1
			text = emblems[e] if e < emblems.size() else "Emblem"
			font_size = int(radius * 0.05)
		# Lettering runs along the radius, reading outward from the hub.
		draw_set_transform_matrix(_xf * Transform2D(mid, center + Vector2.from_angle(mid) * radius * 0.66))
		_text_fit(Vector2.ZERO, text, font_size, palette.ink, palette.sign_font if symbol.begins_with("emblem") else palette.body_font, radius * 0.6)
		draw_set_transform_matrix(_xf)
		var peg := center + Vector2.from_angle(a0) * (radius - 6.0)
		draw_circle(peg, 3.5, palette.metal.lightened(0.25), true, -1.0, true)
	draw_circle(center, radius * 0.3, palette.wood, true, -1.0, true)
	draw_arc(center, radius * 0.3, 0.0, TAU, 48, palette.metal, 3.0, true)
	_text_fit(center, palette.sign_text(ResortThemes.resort_name(resort)), int(radius * 0.08), palette.lamp, palette.sign_font, radius * 0.52)
	# The pointer flicks back each time a peg passes under it.
	var spinning := String(_current.get("kind", "")) == "wheel"
	var phase := fposmod(-(angle) / step + 0.5, 1.0)
	var flick := (maxf(0.0, 1.0 - phase * 5.0) * 0.45) if spinning else 0.0
	var hinge := center + Vector2(0, -radius - 18.0)
	var tip := hinge + Vector2(0, 34).rotated(-flick)
	var side := Vector2(9, 0).rotated(-flick)
	draw_colored_polygon(PackedVector2Array([hinge - side, hinge + side, tip]), CasinoPalette.CARD_RED.darkened(0.2))
	draw_circle(hinge, 7.0, palette.metal, true, -1.0, true)


func _draw_board() -> void:
	var numbers := [[&"seg_1", "1", "1 to 1"], [&"seg_2", "2", "2 to 1"], [&"seg_5", "5", "5 to 1"],
		[&"seg_10", "10", "10 to 1"], [&"seg_20", "20", "20 to 1"]]
	var origin := Vector2(20, 470) if _tall else Vector2(440, 36)
	var cell := Vector2(88, 92) if _tall else Vector2(80, 96)
	var gap := 10.0 if _tall else 8.0
	for i in numbers.size():
		var spec: Array = numbers[i]
		var rect := Rect2(origin + Vector2(i * (cell.x + gap), 0), cell)
		var color := _segment_color(String(spec[1]))
		_draw_spot(spec[0], rect, spec[1], spec[2], color.darkened(0.5), 24)
	var row_w := numbers.size() * (cell.x + gap) - gap
	var emblem_w := (row_w - gap) * 0.5
	for e in 2:
		var spot := &"emblem_a" if e == 0 else &"emblem_b"
		var rect := Rect2(origin + Vector2(e * (emblem_w + gap), cell.y + 18.0), Vector2(emblem_w, 96))
		_draw_spot(spot, rect, spot_label(spot), "40 to 1", CasinoPalette.GOLD.darkened(0.45), 18)
	var history: Array = view.get("history", [])
	var y := origin.y + cell.y + 150.0
	_text_left(Vector2(origin.x, y), "Last stops", 14, palette.felt_line)
	var x := origin.x + 100.0
	for value in history:
		if x > origin.x + row_w - 10.0:
			break
		var symbol := String(value)
		draw_circle(Vector2(x, y), 14.0, _segment_color(symbol), true, -1.0, true)
		_text(Vector2(x, y), "E" if symbol.begins_with("emblem") else symbol, 13, palette.ink)
		x += 33.0
