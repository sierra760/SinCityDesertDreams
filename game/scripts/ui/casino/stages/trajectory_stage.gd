# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Trajectory: a rocket climbing a multiplier curve. While the player holds
## on, the stage climbs in real time and reports each new hundredth through
## `stage_action(&"advance", …)`; the game decides when the engine burns out.
## A launch with an automatic cash-out is decided at once and replayed here.
class_name TrajectoryStage
extends CasinoStage

## Flight seconds and multiplier on display.
var flight_seconds := 0.0
## While true a live climb stands still (the window lost focus); it
## continues from the same point when released.
var clock_held := false
var multiplier := 1.0
## True while the climb is live and the player can still cash out.
var live := false
## The cash-out target chosen before launch (0: none), drawn as a line.
var auto_target := 0.0

var _reported := 1.0
var _ending := ""
var _replay_seconds := 0.0
var _replay_multiplier := 1.0
var _from_live := false


func design_size(tall_layout: bool) -> Vector2:
	return Vector2(520, 760) if tall_layout else Vector2(900, 420)


## The multiplier the player would cash out at now.
func current_multiplier() -> float:
	return TrajectoryGame.hundredths(multiplier)


func set_auto_target(value: float) -> void:
	auto_target = value
	queue_redraw()


func _banner_rest(_design: Vector2) -> Rect2:
	return Rect2(60, 40, 360, 64) if _tall else Rect2(150, 30, 360, 64)


func _reset_model() -> void:
	flight_seconds = 0.0
	multiplier = 1.0
	live = false
	_reported = 1.0
	_ending = ""


func _animation_key(event: Dictionary) -> String:
	match String(event.get("kind", "")):
		"launch":
			return "launch"
		"cash_out", "crash":
			return "burst"
	return super._animation_key(event)


func _event_seconds(event: Dictionary) -> float:
	var kind := String(event.get("kind", ""))
	if (kind == "cash_out" or kind == "crash") and not _from_live:
		# A launch decided at once replays its climb, shortened when long.
		var climb := minf(float(event.get("seconds", 0.0)), float(CasinoTableOverlay.ANIMATION["flight_max"]))
		return CasinoTableOverlay.scaled(climb) + CasinoTableOverlay.seconds("burst")
	return super._event_seconds(event)


func _begin_event(event: Dictionary) -> void:
	match String(event.get("kind", "")):
		"launch":
			_reset_model()
			auto_target = float(event.get("auto", 0.0))
		"cash_out", "crash":
			_from_live = live
			_replay_seconds = float(event.get("seconds", 0.0))
			_replay_multiplier = float(event.get("multiplier", 1.0))
			if live:
				live = false
				flight_seconds = maxf(flight_seconds, _replay_seconds)
				multiplier = _replay_multiplier
				_ending = String(event["kind"])


func _finish_event(event: Dictionary) -> void:
	match String(event.get("kind", "")):
		"launch":
			live = game.state == CasinoGame.PLAYING
		"cash_out", "crash":
			flight_seconds = _replay_seconds
			multiplier = _replay_multiplier
			_ending = String(event["kind"])


func _advance_clock(delta: float) -> void:
	var kind := String(_current.get("kind", ""))
	if (kind == "cash_out" or kind == "crash") and _ending.is_empty():
		# Replaying a decided launch: climb to the event's point, then burst.
		var climb := minf(_replay_seconds, float(CasinoTableOverlay.ANIMATION["flight_max"]))
		var total := CasinoTableOverlay.scaled(climb) + CasinoTableOverlay.seconds("burst")
		var share := CasinoTableOverlay.scaled(climb) / maxf(0.0001, total)
		var climb_t := clampf(_progress / maxf(0.0001, share), 0.0, 1.0)
		flight_seconds = _replay_seconds * climb_t
		multiplier = minf(TrajectoryGame.multiplier_at(flight_seconds), _replay_multiplier)
		if climb_t >= 1.0:
			_ending = kind
			multiplier = _replay_multiplier
		queue_redraw()
		return
	if not live:
		if not _ending.is_empty():
			queue_redraw()
		return
	if clock_held:
		return
	flight_seconds += delta
	multiplier = TrajectoryGame.multiplier_at(flight_seconds)
	if multiplier >= _reported + 0.0099:
		_reported = multiplier
		stage_action.emit(&"advance", {"multiplier": multiplier})
	queue_redraw()


func _draw_stage() -> void:
	var chart := Rect2(20, 20, 480, 380) if _tall else Rect2(30, 20, 630, 300)
	var panel := Rect2(20, 420, 480, 120) if _tall else Rect2(684, 20, 196, 300)
	_draw_chart(chart)
	_draw_panel(panel)
	var spot := Rect2(160, 560, 200, 70) if _tall else Rect2(30, 336, 240, 66)
	_draw_spot(&"stake", spot, "Stake", "", palette.felt.darkened(0.1), 18)
	_draw_history(Vector2(20, 680) if _tall else Vector2(300, 370), 480.0 if _tall else 580.0)


func _draw_chart(chart: Rect2) -> void:
	_round_rect(chart, Color(palette.ink, 0.88), 10.0, palette.metal, 2.0)
	var plot := chart.grow_individual(-48, -16, -16, -34)
	var x_max := maxf(10.0, flight_seconds * 1.15)
	var y_max := maxf(2.0, maxf(multiplier, auto_target) * 1.2)
	for k in 5:
		var m := 1.0 + (y_max - 1.0) * k / 4.0
		var y := _chart_y(plot, m, y_max)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(palette.paper, 0.12), 1.0)
		_text_left(Vector2(chart.position.x + 8, y), "%.1fx" % m, 12, Color(palette.paper, 0.7))
	_text(Vector2(plot.get_center().x, chart.end.y - 14), "seconds after ignition", 12, Color(palette.paper, 0.6))
	if auto_target > 0.0:
		var ay := _chart_y(plot, auto_target, y_max)
		var x := plot.position.x
		while x < plot.end.x:
			draw_line(Vector2(x, ay), Vector2(minf(x + 10.0, plot.end.x), ay), CasinoPalette.WIN.lightened(0.3), 2.0)
			x += 18.0
		_text_left(Vector2(plot.end.x - 120, ay - 12), "auto %.2fx" % auto_target, 12, CasinoPalette.WIN.lightened(0.3))
	var points := PackedVector2Array()
	var samples := 48
	for i in samples + 1:
		var t := flight_seconds * i / samples
		var m := minf(exp(CasinoParams.TRAJECTORY_RATE * t), maxf(multiplier, 1.0))
		points.append(Vector2(plot.position.x + plot.size.x * t / x_max, _chart_y(plot, m, y_max)))
	if flight_seconds > 0.0:
		draw_polyline(points, palette.lamp, 4.0, true)
	var tip := points[points.size() - 1] if flight_seconds > 0.0 else Vector2(plot.position.x, _chart_y(plot, 1.0, y_max))
	var heading := (points[points.size() - 1] - points[points.size() - 2]).angle() if points.size() > 1 and flight_seconds > 0.0 else -PI * 0.25
	if _ending == "crash":
		for ray in 14:
			var a := TAU * ray / 14.0
			draw_line(tip, tip + Vector2.from_angle(a) * (16.0 + (ray % 3) * 8.0), Color("f08a3a"), 4.0, true)
		draw_circle(tip, 10.0, Color("ffd38a"), true, -1.0, true)
	else:
		_draw_rocket(tip, heading, live)
		if _ending == "cash_out":
			draw_line(tip, tip + Vector2(0, -34), palette.paper, 2.0)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -34), tip + Vector2(22, -28), tip + Vector2(0, -22)]), CasinoPalette.WIN)


func _chart_y(plot: Rect2, m: float, y_max: float) -> float:
	return plot.end.y - plot.size.y * clampf((m - 1.0) / (y_max - 1.0), 0.0, 1.0)


func _draw_rocket(at: Vector2, heading: float, burning: bool) -> void:
	draw_set_transform_matrix(_xf * Transform2D(heading, at))
	if burning:
		var flicker := 0.8 + 0.2 * sin(_clock * 40.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-10, -5), Vector2(-10 - 22 * flicker, 0), Vector2(-10, 5)]), Color("f6a23a"))
	draw_colored_polygon(PackedVector2Array([Vector2(16, 0), Vector2(4, -7), Vector2(-12, -7), Vector2(-12, 7), Vector2(4, 7)]), palette.paper)
	draw_colored_polygon(PackedVector2Array([Vector2(-6, -7), Vector2(-14, -14), Vector2(-12, -7)]), palette.metal)
	draw_colored_polygon(PackedVector2Array([Vector2(-6, 7), Vector2(-14, 14), Vector2(-12, 7)]), palette.metal)
	draw_circle(Vector2(4, 0), 3.0, palette.glass, true, -1.0, true)
	draw_set_transform_matrix(_xf)


func _draw_panel(panel: Rect2) -> void:
	_round_rect(panel, Color(palette.ink, 0.88), 10.0, palette.metal, 2.0)
	var color := palette.lamp
	var replaying := String(_current.get("kind", "")) in ["cash_out", "crash"] and _ending.is_empty()
	var caption := "Ready on the pad" if game.state == CasinoGame.BETTING else ("Climbing" if live or replaying else "")
	if _ending == "crash":
		color = Color("f08a3a")
		caption = "Burn-out" if multiplier > 1.0 else "Engine failure"
	elif _ending == "cash_out":
		color = CasinoPalette.WIN.lightened(0.3)
		caption = "Cashed out"
	var big := 48 if not _tall else 44
	var center := panel.get_center() if _tall else Vector2(panel.get_center().x, panel.position.y + 110)
	_text_fit(center + (Vector2(-90, 0) if _tall else Vector2.ZERO), "%.2fx" % multiplier, big, color, palette.sign_font, panel.size.x * (0.5 if _tall else 0.9))
	var caption_at := center + (Vector2(140, -14) if _tall else Vector2(0, 52))
	_text_fit(caption_at, caption, 18, palette.paper, palette.body_font, panel.size.x * 0.45 if _tall else panel.size.x - 16.0)
	var stake := int(_bets().get(&"stake", 0))
	if stake > 0:
		var worth := TrajectoryGame.payout(stake, multiplier) if _ending != "crash" else 0
		var worth_at := center + (Vector2(140, 18) if _tall else Vector2(0, 90))
		_text_fit(worth_at, "Worth %s" % CasinoLines.money(worth), 16, palette.lamp, palette.body_font, panel.size.x * 0.45 if _tall else panel.size.x - 16.0)


func _draw_history(origin: Vector2, width: float) -> void:
	var history: Array = view.get("history", [])
	_text_left(origin, "Burn-outs", 13, palette.felt_line)
	var x := origin.x + 80.0
	for value in history:
		var text := "%.2fx" % float(value)
		var w := palette.body_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14.0
		if x + w > origin.x + width:
			break
		_round_rect(Rect2(x, origin.y - 11, w, 22), CasinoPalette.WIN.darkened(0.2) if float(value) >= 2.0 else CasinoPalette.LOSE, 8.0)
		_text(Vector2(x + w * 0.5, origin.y), text, 13, Color.WHITE)
		x += w + 8.0
