# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Single-zero roulette: the wheel beside (or above) the betting layout. The
## wheel turns one way and the ball the other; the ball slows, drops off the
## rim and settles in the drawn pocket. Any number of spots can carry chips.
class_name RouletteStage
extends CasinoStage

## Pocket numbers clockwise round a single-zero wheel.
const WHEEL_ORDER: Array[int] = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23,
	10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
const IDLE_TURN := 0.05
const WHEEL_TURNS := 2.5
const BALL_TURNS := 4.0

var _wheel_angle := 0.0
var _spin_start := 0.0
var _pocket := -1


func design_size(tall_layout: bool) -> Vector2:
	return Vector2(520, 860) if tall_layout else Vector2(940, 420)


func _banner_rest(_design: Vector2) -> Rect2:
	return Rect2(30, 796, 460, 60) if _tall else Rect2(450, 350, 470, 64)


func spot_order() -> Array[StringName]:
	var out: Array[StringName] = [&"n0"]
	for n in range(1, 37):
		out.append(StringName("n%d" % n))
	for id: StringName in [&"column_1", &"column_2", &"column_3", &"dozen_1", &"dozen_2", &"dozen_3",
			&"low", &"even", &"red", &"black", &"odd", &"high"]:
		out.append(id)
	return out


func spot_label(spot: StringName) -> String:
	var text := String(spot)
	if text.begins_with("n"):
		var n := int(text.substr(1))
		return "%d %s" % [n, RouletteGame.color_of(n)] if n > 0 else "0"
	return super.spot_label(spot)


func _reset_model() -> void:
	_winners.clear()


func _animation_key(event: Dictionary) -> String:
	if String(event.get("kind", "")) == "spin":
		return "roulette"
	return super._animation_key(event)


func _begin_event(event: Dictionary) -> void:
	if String(event.get("kind", "")) == "spin":
		_spin_start = _wheel_angle
		_pocket = -1


func _finish_event(event: Dictionary) -> void:
	match String(event.get("kind", "")):
		"spin":
			_pocket = int(event.get("pocket", -1))
			_wheel_angle = fposmod(_spin_start + WHEEL_TURNS * TAU, TAU)
		"result":
			if bool(event.get("won", false)):
				_winners[StringName(String(event.get("spot", "")))] = true


func _advance_clock(delta: float) -> void:
	if String(_current.get("kind", "")) != "spin":
		_wheel_angle = fposmod(_wheel_angle + IDLE_TURN * delta, TAU)
		queue_redraw()


func _draw_stage() -> void:
	var center := Vector2(260, 150) if _tall else Vector2(200, 205)
	var radius := 132.0 if _tall else 178.0
	var spinning := String(_current.get("kind", "")) == "spin"
	var wheel := _wheel_angle
	var ball_angle := 0.0
	var ball_radius := radius * 0.62
	var show_ball := _pocket >= 0
	if spinning:
		var t := _progress
		wheel = _spin_start + WHEEL_TURNS * TAU * (1.0 - pow(1.0 - t, 3.0))
		var target := int(_current.get("pocket", 0))
		var settle := 1.0 - pow(1.0 - minf(1.0, t / 0.86), 2.5)
		ball_angle = wheel + _pocket_angle(target) + (1.0 - settle) * BALL_TURNS * TAU * -1.0
		var drop := clampf((t - 0.55) / 0.3, 0.0, 1.0)
		var bounce := sin(drop * PI * 3.0) * (1.0 - drop) * radius * 0.04
		ball_radius = lerpf(radius * 0.93, radius * 0.62, drop) + bounce
		show_ball = true
	elif _pocket >= 0:
		ball_angle = wheel + _pocket_angle(_pocket)
	_draw_wheel(center, radius, wheel)
	if show_ball:
		var at := center + Vector2.from_angle(ball_angle - PI * 0.5) * ball_radius
		draw_circle(at + Vector2(1.5, 2.0), radius * 0.042, Color(0, 0, 0, 0.35), true, -1.0, true)
		draw_circle(at, radius * 0.042, Color("fbf7ee"), true, -1.0, true)
	if _tall:
		_draw_layout_tall()
	else:
		_draw_layout_wide()
	_draw_history()


func _pocket_angle(pocket: int) -> float:
	return WHEEL_ORDER.find(pocket) * TAU / WHEEL_ORDER.size()


func _draw_wheel(center: Vector2, radius: float, angle: float) -> void:
	draw_circle(center + Vector2(4, 6), radius + 6.0, Color(0, 0, 0, 0.3), true, -1.0, true)
	draw_circle(center, radius + 6.0, palette.wood, true, -1.0, true)
	draw_arc(center, radius + 4.0, 0.0, TAU, 72, palette.metal, 3.0, true)
	draw_circle(center, radius, palette.wood.lightened(0.12), true, -1.0, true)
	var step := TAU / WHEEL_ORDER.size()
	var inner := radius * 0.68
	var outer := radius * 0.88
	for i in WHEEL_ORDER.size():
		var pocket := WHEEL_ORDER[i]
		var a0 := angle + (i - 0.5) * step - PI * 0.5
		var a1 := a0 + step
		var points := PackedVector2Array()
		for k in 4:
			points.append(center + Vector2.from_angle(lerpf(a0, a1, k / 3.0)) * outer)
		for k in 4:
			points.append(center + Vector2.from_angle(lerpf(a1, a0, k / 3.0)) * inner)
		var color := CasinoPalette.WIN if pocket == 0 else (CasinoPalette.CARD_RED if RouletteGame.color_of(pocket) == "red" else Color("1c1a17"))
		if pocket == _pocket and String(_current.get("kind", "")) != "spin":
			color = color.lightened(0.35)
		draw_colored_polygon(points, color)
		draw_line(center + Vector2.from_angle(a0) * inner, center + Vector2.from_angle(a0) * radius, palette.metal, 1.5, true)
		var mid := a0 + step * 0.5
		draw_set_transform_matrix(_xf * Transform2D(mid + PI * 0.5, center + Vector2.from_angle(mid) * radius * 0.79))
		_text(Vector2.ZERO, str(pocket), int(radius * 0.075), Color("fbf7ee"))
		draw_set_transform_matrix(_xf)
	draw_arc(center, inner, 0.0, TAU, 72, palette.metal, 2.0, true)
	draw_circle(center, inner - 2.0, palette.felt.darkened(0.2), true, -1.0, true)
	draw_circle(center, inner * 0.62, palette.wood, true, -1.0, true)
	for spoke in 4:
		var a := angle + spoke * PI * 0.5
		draw_line(center, center + Vector2.from_angle(a) * inner * 0.72, palette.metal, 5.0, true)
		draw_circle(center + Vector2.from_angle(a) * inner * 0.72, 6.0, palette.metal, true, -1.0, true)
	draw_circle(center, 12.0, palette.metal.lightened(0.2), true, -1.0, true)


func _number_fill(n: int) -> Color:
	if n == 0:
		return CasinoPalette.WIN.darkened(0.15)
	return CasinoPalette.CARD_RED.darkened(0.1) if RouletteGame.color_of(n) == "red" else Color("1c1a17")


func _draw_number(n: int, rect: Rect2) -> void:
	_draw_spot(StringName("n%d" % n), rect, str(n), "", _number_fill(n), 18)
	if n == _pocket and String(_current.get("kind", "")) != "spin":
		var c := rect.get_center()
		draw_circle(c + Vector2(rect.size.x * 0.32, -rect.size.y * 0.28), 7.0, palette.metal, true, -1.0, true)
		draw_arc(c + Vector2(rect.size.x * 0.32, -rect.size.y * 0.28), 7.0, 0.0, TAU, 16, CasinoPalette.GOLD, 2.0, true)


func _draw_layout_wide() -> void:
	var left := 410.0
	var top := 30.0
	_draw_number(0, Rect2(left, top, 40, 180))
	for c in 12:
		for r in 3:
			_draw_number(3 * (c + 1) - r, Rect2(left + 40 + c * 38, top + r * 60, 38, 60))
	for r in 3:
		_draw_spot(StringName("column_%d" % (3 - r)), Rect2(left + 40 + 12 * 38, top + r * 60, 30, 60), "2:1", "", Color(0, 0, 0, 0), 13)
	var labels := ["1st 12", "2nd 12", "3rd 12"]
	for d in 3:
		_draw_spot(StringName("dozen_%d" % (d + 1)), Rect2(left + 40 + d * 152, top + 184, 152, 46), labels[d], "2 to 1", Color(0, 0, 0, 0), 17)
	_draw_outside(Vector2(left + 40, top + 234), Vector2(76, 46), false)


func _draw_layout_tall() -> void:
	var left := 130.0
	var top := 300.0
	_draw_number(0, Rect2(left, top, 300, 40))
	for r in 12:
		for c in 3:
			_draw_number(3 * r + c + 1, Rect2(left + c * 100, top + 40 + r * 36, 100, 36))
	for c in 3:
		_draw_spot(StringName("column_%d" % (c + 1)), Rect2(left + c * 100, top + 40 + 12 * 36, 100, 40), "2:1", "", Color(0, 0, 0, 0), 15)
	var labels := ["1-12", "13-24", "25-36"]
	for d in 3:
		_draw_spot(StringName("dozen_%d" % (d + 1)), Rect2(left - 56, top + 40 + d * 144, 56, 144), labels[d], "", Color(0, 0, 0, 0), 14)
	_draw_outside(Vector2(left - 118, top + 40), Vector2(62, 72), true)


## Low, even, red, black, odd and high, in a row or a column.
func _draw_outside(origin: Vector2, cell: Vector2, column: bool) -> void:
	var specs := [[&"low", "1-18" if column else "1 to 18"], [&"even", "Even"], [&"red", "Red"],
		[&"black", "Black"], [&"odd", "Odd"], [&"high", "19-36" if column else "19 to 36"]]
	for i in specs.size():
		var spec: Array = specs[i]
		var rect := Rect2(origin + (Vector2(0, i * cell.y) if column else Vector2(i * cell.x, 0)), cell)
		var fill := Color(0, 0, 0, 0)
		if spec[0] == &"red":
			fill = CasinoPalette.CARD_RED.darkened(0.1)
		elif spec[0] == &"black":
			fill = Color("1c1a17")
		_draw_spot(spec[0], rect, spec[1], "", fill, 15)


func _draw_history() -> void:
	var history: Array = view.get("history", [])
	var origin := Vector2(20, 836) if _tall else Vector2(450, 330)
	var width := 480.0 if _tall else 470.0
	_text_left(origin, "Last spins", 14, palette.felt_line)
	var x := origin.x + 92.0
	for value in history:
		if x > origin.x + width:
			break
		var n := int(value)
		draw_circle(Vector2(x, origin.y), 13.0, _number_fill(n), true, -1.0, true)
		draw_arc(Vector2(x, origin.y), 13.0, 0.0, TAU, 20, palette.felt_line, 1.0, true)
		_text(Vector2(x, origin.y), str(n), 13, Color.WHITE)
		x += 31.0
