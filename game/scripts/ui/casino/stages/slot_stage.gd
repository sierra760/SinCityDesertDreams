# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A three-reel cabinet with one pay line. The reels spin together and stop
## left to right with a small kick; the resort names every symbol.
class_name SlotStage
extends CasinoStage

const STRIP := 20
const SPIN_SPEED := 14.0
## Radians of reel curvature per symbol.
const CURVE := 0.62

var _pos: Array[float] = [0.0, 0.0, 0.0]
var _spinning: Array[bool] = [false, false, false]
var _flash: Array[float] = [0.0, 0.0, 0.0]
var _stop_from := 0.0
var _stop_to := 0.0


func design_size(tall_layout: bool) -> Vector2:
	return Vector2(520, 700) if tall_layout else Vector2(900, 420)


func _banner_rest(_design: Vector2) -> Rect2:
	return Rect2(40, 2, 440, 62) if _tall else Rect2(60, 2, 520, 62)


func _reset_model() -> void:
	_sync_model()


func _sync_model() -> void:
	var stops: Array = view.get("stops", [0, 0, 0])
	for reel in 3:
		if not _spinning[reel] and reel < stops.size():
			_pos[reel] = float(int(stops[reel]))


func _animation_key(event: Dictionary) -> String:
	match String(event.get("kind", "")):
		"spin":
			return "reel_start"
		"reel_stop":
			return "reel_stop"
		"jackpot":
			return "beat"
	return super._animation_key(event)


func _begin_event(event: Dictionary) -> void:
	match String(event.get("kind", "")):
		"spin":
			for reel in 3:
				_spinning[reel] = true
		"reel_stop":
			var reel := int(event.get("reel", 0))
			_stop_from = _pos[reel]
			var stop := float(int(event.get("stop", 0)))
			var target := floorf(_stop_from / STRIP) * STRIP + stop
			while target < _stop_from + 5.0:
				target += STRIP
			_stop_to = target
			_spinning[reel] = false


func _finish_event(event: Dictionary) -> void:
	if String(event.get("kind", "")) == "reel_stop":
		var reel := int(event.get("reel", 0))
		_pos[reel] = float(int(event.get("stop", 0)))
		_spinning[reel] = false
		_flash[reel] = 1.0


func _advance_clock(delta: float) -> void:
	var moving := false
	for reel in 3:
		if _spinning[reel]:
			_pos[reel] += SPIN_SPEED * delta
			moving = true
		if _flash[reel] > 0.0:
			_flash[reel] = maxf(0.0, _flash[reel] - delta * 2.5)
			moving = true
	if moving or String(_current.get("kind", "")) == "reel_stop":
		queue_redraw()


func _reel_position(reel: int) -> float:
	if String(_current.get("kind", "")) == "reel_stop" and int(_current.get("reel", -1)) == reel:
		var t := _progress - 1.0
		var c1 := 1.4
		var eased := 1.0 + (c1 + 1.0) * t * t * t + c1 * t * t
		return lerpf(_stop_from, _stop_to, eased)
	return _pos[reel]


func _draw_stage() -> void:
	var cabinet := Rect2(20, 8, 480, 350) if _tall else Rect2(30, 8, 580, 404)
	var window := Rect2(35, 56, 450, 280) if _tall else Rect2(45, 56, 550, 280)
	_round_rect(cabinet, palette.wood, 16.0, palette.metal, 3.0)
	_text_fit(Vector2(cabinet.get_center().x, 32), ResortThemes.game_name(resort, &"slots").to_upper(), 26, palette.lamp, palette.sign_font, cabinet.size.x - 40.0)
	var gap := 10.0
	var reel_w := (window.size.x - gap * 2.0) / 3.0
	for reel in 3:
		var rect := Rect2(window.position + Vector2(reel * (reel_w + gap), 0), Vector2(reel_w, window.size.y))
		_draw_reel(reel, rect)
	var line_y := window.get_center().y
	draw_line(Vector2(window.position.x - 8, line_y), Vector2(window.end.x + 8, line_y), Color(palette.lamp, 0.85), 3.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(window.position.x - 16, line_y - 9), Vector2(window.position.x - 4, line_y), Vector2(window.position.x - 16, line_y + 9)]), palette.lamp)
	draw_colored_polygon(PackedVector2Array([Vector2(window.end.x + 16, line_y - 9), Vector2(window.end.x + 4, line_y), Vector2(window.end.x + 16, line_y + 9)]), palette.lamp)
	var spot := Rect2(160, 616, 200, 64) if _tall else Rect2(220, 346, 200, 56)
	_draw_spot(&"line", spot, "Line bet", "", palette.felt, 18)
	_draw_paytable(Rect2(20, 372, 480, 230) if _tall else Rect2(630, 20, 250, 380))


func _draw_reel(reel: int, rect: Rect2) -> void:
	_round_rect(rect, palette.paper, 8.0, palette.metal, 2.0)
	var pos := _reel_position(reel)
	var radius := rect.size.y * 0.5
	var center := rect.get_center()
	var base := floori(pos)
	for k in range(-3, 4):
		var index := base + k
		var d := float(index) - pos
		var theta := d * CURVE
		if absf(theta) >= PI * 0.5 - 0.05:
			continue
		var squash := cos(theta)
		var at := Vector2(center.x, center.y + sin(theta) * radius * 0.94)
		var symbol := SlotsGame.symbol_at(reel, posmod(index, STRIP))
		draw_set_transform_matrix(_xf * Transform2D(0.0, Vector2(1.0, squash), 0.0, at))
		# Only rows turned toward the player keep their name: a row near
		# the drum's edge is squashed too far for its caption to read.
		_draw_symbol(symbol, minf(rect.size.x, 120.0), squash > 0.6)
		draw_set_transform_matrix(_xf)
	# Shade the drum's top and bottom so it reads as a turning reel.
	var shade := Color(0, 0, 0, 0.32)
	var clear := Color(0, 0, 0, 0)
	draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.position.y + rect.size.y * 0.3), Vector2(rect.position.x, rect.position.y + rect.size.y * 0.3)]),
		PackedColorArray([shade, shade, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(rect.position.x, rect.end.y - rect.size.y * 0.3), Vector2(rect.end.x, rect.end.y - rect.size.y * 0.3), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([clear, clear, shade, shade]))
	if _flash[reel] > 0.0:
		_round_rect(Rect2(rect.position.x, center.y - 50, rect.size.x, 100), Color(palette.lamp, 0.35 * _flash[reel]), 6.0, Color(CasinoPalette.GOLD, _flash[reel]), 3.0)


## A reel symbol centred on the origin of the current transform: a shape by
## rank, then its themed name.
func _draw_symbol(symbol: String, width: float, named: bool) -> void:
	var s := 26.0
	var c := Vector2(0, -12 if named else 0)
	var index := CasinoParams.SLOT_SYMBOLS.find(symbol)
	var colors := [palette.glass, palette.metal, CasinoPalette.CARD_RED, palette.felt.lightened(0.1), CasinoPalette.GOLD, palette.accent]
	var color: Color = colors[clampi(index, 0, colors.size() - 1)]
	var outline := palette.ink
	match symbol:
		"s1":
			draw_circle(c, s, color, true, -1.0, true)
			draw_circle(c, s * 0.45, palette.paper, true, -1.0, true)
		"s2":
			draw_colored_polygon(_polygon(c, s * 1.1, 4, 0.0), color)
			draw_colored_polygon(_polygon(c, s * 0.5, 4, 0.0), palette.paper)
		"s3":
			draw_colored_polygon(_polygon(c + Vector2(0, 3), s * 1.1, 3, 0.0), color)
		"s4":
			draw_colored_polygon(_star(c, s * 1.1, s * 0.5, 5), color)
		"s5":
			draw_colored_polygon(_polygon(c, s * 1.05, 6, PI / 6.0), color)
			draw_colored_polygon(_star(c, s * 0.7, s * 0.3, 4), palette.paper)
		_:
			draw_colored_polygon(_star(c, s * 1.25, s * 0.6, 12), CasinoPalette.GOLD)
			draw_circle(c, s * 0.62, palette.accent, true, -1.0, true)
	draw_arc(c, s * 1.2, 0.0, TAU, 32, Color(outline, 0.15), 1.0, true)
	if named:
		var label := ResortThemes.reel_name(resort, symbol)
		var font := palette.sign_font if symbol == "B" else palette.body_font
		_text_fit(Vector2(0, 30), label, 15, palette.ink, font, width - 10.0)


static func _polygon(c: Vector2, r: float, sides: int, rotation_offset: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		points.append(c + Vector2.from_angle(rotation_offset - PI * 0.5 + TAU * i / sides) * r)
	return points


static func _star(c: Vector2, outer: float, inner: float, points_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in points_count * 2:
		var r := outer if i % 2 == 0 else inner
		points.append(c + Vector2.from_angle(-PI * 0.5 + PI * i / points_count) * r)
	return points


func _draw_paytable(rect: Rect2) -> void:
	_round_rect(rect, Color(palette.ink, 0.85), 10.0, palette.metal, 2.0)
	var rows: Array = view.get("paytable", [])
	_text(Vector2(rect.get_center().x, rect.position.y + 20), "Pays for 1", 16, palette.lamp)
	var columns := 2 if _tall else 1
	var per_column := ceili(float(rows.size()) / float(columns))
	var row_h := (rect.size.y - 40.0) / maxf(1.0, float(per_column))
	var col_w := rect.size.x / columns
	for i in rows.size():
		var row: Dictionary = rows[i]
		var col := floori(float(i) / float(per_column))
		var r := i % per_column
		var y := rect.position.y + 44.0 + r * row_h + row_h * 0.3
		var x := rect.position.x + col * col_w + 22.0
		var symbols: Array = row["symbols"]
		for k in symbols.size():
			draw_set_transform_matrix(_xf * Transform2D(0.0, Vector2(0.42, 0.42), 0.0, Vector2(x + k * 26.0, y)))
			_draw_symbol(String(symbols[k]), 60.0, false)
			draw_set_transform_matrix(_xf)
		if symbols.size() < 3:
			_text_left(Vector2(x + symbols.size() * 26.0 - 6.0, y), "any", 12, palette.paper)
		var pays := str(int(row["returns"]))
		var w := palette.body_font.get_string_size(pays, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_text_left(Vector2(rect.position.x + (col + 1) * col_w - 16.0 - w, y), pays, 16, palette.lamp)
