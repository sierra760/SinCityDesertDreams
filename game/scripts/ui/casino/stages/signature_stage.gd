# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Six signature tables, each with its own visual language and live decision
## board. Drawn choices ask the overlay; the focusable action bar mirrors them.
class_name OriginalSignatureStage
extends CasinoStage

const KINDS: Array[StringName] = [&"vault_circuit", &"alibi_route", &"velvet_encore", &"afterglow_forecast", &"last_bank", &"dust_pool"]
var choice_rects: Dictionary = {}
var text_boxes: Array[Rect2] = []
var text_overflows: Array[String] = []
var rendered_text: Array[String] = []
var _compact_board := false

# Work in actual logical pixels: a small display retains readable lettering
# rather than shrinking a desktop illustration and its text together.
func design_size(_tall_layout: bool) -> Vector2:
	return Vector2(maxf(160.0, size.x), maxf(120.0, size.y))

func _animation_key(event: Dictionary) -> String:
	return "signature_reveal" if String(event.get("kind", "")) in ["signature_reveal", "lock", "arrival", "encore", "forecast", "draft", "contract", "pool", "pledges", "agreement", "offers", "bank_card"] else super._animation_key(event)

func _banner_rest(design: Vector2) -> Rect2:
	return Rect2(12, 8, design.x - 24, 64)

func _press(point: Vector2) -> bool:
	if game.state != CasinoGame.PLAYING or is_busy():
		return false
	for id: StringName in choice_rects:
		if (choice_rects[id] as Rect2).has_point(point):
			for action: Dictionary in game.actions():
				if StringName(action["id"]) == id and bool(action.get("enabled", false)):
					stage_action.emit(id, {})
					return true
	return false

func _draw_stage() -> void:
	choice_rects.clear()
	text_boxes.clear()
	text_overflows.clear()
	rendered_text.clear()
	var area := Rect2(Vector2(12, 10), size - Vector2(24, 20))
	var short := area.size.y < 230
	_compact_board = short
	var title_h := 22.0 if short else 32.0
	var heading := String(view.get("forecast_class", view.get("phase_label", view.get("title", ""))))
	if game.kind == &"velvet_encore":
		heading += " · Bank " + CasinoLines.money(int(view.get("bank", 0)))
	elif game.kind == &"dust_pool" and short:
		heading = "Pot %s · Crew %s" % [CasinoLines.money(int(view.get("pot", 0))), "/".join(view.get("crewbids", []).map(func(bid: Variant) -> String: return str(bid)))]
	_words(Rect2(area.position, Vector2(area.size.x, title_h)), heading, 16 if short else 21, palette.lamp, true)
	var instruction_h := 0.0 if short else 42.0
	if not short:
		_words(Rect2(area.position + Vector2(0, title_h + 2), Vector2(area.size.x, instruction_h)), String(view.get("instruction", "")), 14, palette.paper)
	var choices: Array = view.get("choices", [])
	var choice_h := 76.0 if not short and not choices.is_empty() else 0.0
	var board := Rect2(area.position + Vector2(0, title_h + instruction_h + 6), Vector2(area.size.x, maxf(30, area.size.y - title_h - instruction_h - choice_h - 14)))
	_round_rect(board, palette.ink.lightened(0.03), 10, Color(palette.metal, 0.65), 1)
	match game.kind:
		&"vault_circuit": _vault(board)
		&"alibi_route": _route(board)
		&"velvet_encore": _theater(board)
		&"afterglow_forecast": _forecast(board)
		&"last_bank": _bank(board)
		&"dust_pool": _pool(board)
	if choice_h > 0:
		_choices(Rect2(Vector2(area.position.x, area.end.y - choice_h), Vector2(area.size.x, choice_h)), choices)
	if game.state == CasinoGame.BETTING and game.kind != &"afterglow_forecast" and board.size.y >= 44:
		# A single broad stake spot is also a direct touch target.
		_spot_rects[default_spot()] = board

func _choices(area: Rect2, choices: Array) -> void:
	var gap := 6.0
	var width := (area.size.x - gap * (choices.size() - 1)) / maxi(1, choices.size())
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var id := StringName(choice["id"])
		var rect := Rect2(area.position + Vector2(i * (width + gap), 0), Vector2(width, area.size.y))
		choice_rects[id] = rect
		_round_rect(rect, palette.felt.lightened(0.04), 7, palette.metal, 1)
		_words(Rect2(rect.position + Vector2(5, 3), Vector2(rect.size.x - 10, 23)), ("Draft %d" % (int(String(id).trim_prefix("draft_")) + 1)) if String(id).begins_with("draft_") else String(choice.get("label", id)), 14, palette.paper, true)
		_words(Rect2(rect.position + Vector2(5, 27), Vector2(rect.size.x - 10, 44)), _choice_brief(choice), 11, palette.lamp, true)

func _choice_brief(choice: Dictionary) -> String:
	var id := String(choice["id"])
	match game.kind:
		&"vault_circuit":
			return "80% · ×1.20" if id == "quiet" else ("55% · ×1.70" if id == "force" else CasinoLines.money(int(view.get("currentbank", 0))))
		&"alibi_route":
			for q: Dictionary in view.get("route_quotes", []):
				if String(q["id"]) == id: return "%.1f%% · %s" % [float(q["chance"]) / 10, CasinoLines.money(int(q["returned"]))]
			return "Full win / $0 back" if id == "bare" else "80% win / 25% back"
		&"velvet_encore":
			if id == "bow": return CasinoLines.money(int(view.get("bank", 0)))
			var weights: Dictionary = view.get("audienceweights", {})
			var beats := {"rose": "fan", "fan": "spotlight", "spotlight": "rose"}
			return "%d%% win · %d%% tie" % [int(weights.get(beats.get(id, ""), 0)), int(weights.get(id, 0))]
		&"last_bank":
			for q: Dictionary in view.get("contract_quotes", []):
				if String(q["id"]) == id: return "%d/%d · %s" % [q["chance_numerator"], q["chance_denominator"], CasinoLines.money(int(q["returned"]))]
			return "Select this card"
		&"dust_pool":
			for q: Dictionary in view.get("claim_quotes", []):
				if String(q["id"]) == id:
					var total := 0
					for bid in view.get("crewbids", []): total += int(bid)
					return "%d/%d · %.1f%%\n%s" % [int(q["share"]), total + int(q["share"]), float(q["chance"]) / 10, CasinoLines.money(int(q["returned"]))]
	return String(choice.get("detail", ""))

func _vault(r: Rect2) -> void:
	var small := _compact_board or r.size.y < 125
	var rad := minf(r.size.y * 0.34, r.size.x * 0.19)
	var center := r.position + Vector2(r.size.x * 0.25, r.size.y * 0.5)
	draw_circle(center, rad, palette.metal.darkened(0.35), true, -1, true)
	draw_arc(center, rad * 0.78, 0, TAU, 48, palette.metal, 3, true)
	for tick in 12:
		var direction := Vector2.from_angle(TAU * tick / 12.0)
		draw_line(center + direction * rad * 0.59, center + direction * rad * 0.74, palette.paper, 2, true)
	var needle := Vector2.from_angle(-PI * 0.5 + int(view.get("locklevel", 0)) * TAU / 3)
	draw_line(center, center + needle * rad * 0.51, palette.lamp, 4, true)
	_emblem(Rect2(center - Vector2.ONE * rad * 0.18, Vector2.ONE * rad * 0.36), "s1")
	var side := Rect2(r.position + Vector2(r.size.x * 0.49, 8), Vector2(r.size.x * 0.46, r.size.y - 16))
	for lock in 3:
		var at := center + Vector2((lock - 1) * 12, rad + 5) if small else side.position + Vector2(side.size.x * (lock + 0.5) / 3, side.size.y * 0.22)
		draw_circle(at, 3 if small else 12, palette.lamp if lock < int(view.get("locklevel", 0)) else palette.felt_dark, true, -1, true)
	if small:
		var lines := ["Quiet 80% ×1.20", "Force 55% ×1.70", "Bank " + CasinoLines.money(int(view.get("currentbank", 0)))]
		for i in lines.size():
			_words(Rect2(side.position + Vector2(0, side.size.y * i / 3), Vector2(side.size.x, side.size.y / 3)), lines[i], 12, palette.paper, true)
	else:
		_words(Rect2(side.position + Vector2(0, side.size.y * 0.43), Vector2(side.size.x, side.size.y * 0.5)), "VAULT PURSE\n" + CasinoLines.money(int(view.get("currentbank", 0))), 19, palette.paper, true)

func _route(r: Rect2) -> void:
	var small := _compact_board or r.size.y < 125
	var quotes: Array = view.get("route_quotes", [])
	if small and not String(view.get("route", "")).is_empty() and game.state == CasinoGame.PLAYING:
		for q: Dictionary in quotes:
			if String(q["id"]) != String(view["route"]): continue
			_words(Rect2(r.position + Vector2(8, 0), Vector2(r.size.x - 16, r.size.y / 3)), "%s · %.1f%% arrival" % [q["label"], float(q["chance"]) / 10], 13, palette.lamp, true)
			_words(Rect2(r.position + Vector2(8, r.size.y / 3), Vector2(r.size.x - 16, r.size.y / 3)), "Bare: %s win / $0 back" % CasinoLines.money(int(q["returned"])), 12, palette.paper, true)
			_words(Rect2(r.position + Vector2(8, r.size.y * 2 / 3), Vector2(r.size.x - 16, r.size.y / 3)), "Covered: %s win / %s back" % [CasinoLines.money(int(q["covered_returned"])), CasinoLines.money(int(q["loss_returned"]))], 12, palette.paper, true)
		return
	var origin := r.position + Vector2(r.size.x * 0.1, r.size.y * 0.5)
	_emblem(Rect2(origin - Vector2(16, 16), Vector2(32, 32)), "s2")
	for i in 3:
		var end := r.position + Vector2(r.size.x * 0.4, r.size.y * (i + 0.5) / 3.0)
		var active := not quotes.is_empty() and i < quotes.size() and String(quotes[i].get("id", "")) == String(view.get("route", ""))
		draw_polyline(PackedVector2Array([origin + Vector2(18, 0), Vector2(end.x - 18, origin.y), end]), palette.lamp if active else palette.metal, 3, true)
		draw_circle(end, 5, palette.lamp, true, -1, true)
		var quote: Dictionary = quotes[i] if i < quotes.size() else {}
		var label := String(quote.get("label", ["Direct", "Night", "Express"][i]))
		var detail := "%s · %.1f%% · %s" % [label, float(quote.get("chance", 0)) / 10, CasinoLines.money(int(quote.get("returned", 0)))] if not quote.is_empty() else label
		_words(Rect2(Vector2(end.x + 10, end.y - 13), Vector2(r.size.x * 0.5, 26)), detail, 12 if small else 16, palette.paper)
	if not small:
		_words(Rect2(r.position + Vector2(8, r.size.y - 25), Vector2(r.size.x - 16, 22)), "Travel cover: " + String(view.get("coverage", "choose after the route")), 12, palette.lamp, true)

func _theater(r: Rect2) -> void:
	var small := _compact_board or r.size.y < 125
	var curtain := minf(34, r.size.x * 0.09)
	for x in [r.position.x, r.end.x - curtain]:
		_round_rect(Rect2(Vector2(x, r.position.y), Vector2(curtain, r.size.y)), palette.accent.darkened(0.1), 6)
	var weights: Dictionary = view.get("audienceweights", {})
	var labels := ["Rose", "Fan", "Spotlight"]
	for i in 3:
		var at := r.position + Vector2(curtain + (r.size.x - 2 * curtain) * (i + 0.5) / 3, r.size.y * (0.45 if small else 0.3))
		var icon := 18.0 if small else minf(46, r.size.y * 0.2)
		_emblem(Rect2(at - Vector2.ONE * icon / 2, Vector2.ONE * icon), ["s4", "s2", "s3"][i])
		var key: String = ["rose", "fan", "spotlight"][i]
		_words(Rect2(Vector2(at.x - (r.size.x - 2 * curtain) / 6, r.position.y + (3 if small else r.size.y * 0.52)), Vector2((r.size.x - 2 * curtain) / 3, 25 if small else 30)), "%s %s" % [labels[i], "%d%%" % int(weights.get(key, 0))], 11 if small else 15, palette.paper, true)
	var last: Dictionary = view.get("lasttokens", {})
	var feedback := "Rose > Fan > Spotlight > Rose" if last.is_empty() else "%s · %s · %s" % [String(last.get("lead", "")).capitalize(), String(last.get("audience", "")).capitalize(), String(last.get("result", "")).to_upper()]
	_words(Rect2(r.position + Vector2(curtain, r.size.y - 25), Vector2(r.size.x - curtain * 2, 23)), feedback, 11 if small else 15, palette.lamp, true)


func _forecast(r: Rect2) -> void:
	var small := _compact_board or r.size.y < 125
	var circle_r := minf(r.size.y * 0.38, r.size.x * 0.23)
	var center := r.position + Vector2(r.size.x * 0.25, r.size.y * 0.5)
	for radius in [0.33, 0.66, 1.0]:
		draw_arc(center, circle_r * radius, 0, TAU, 48, Color(palette.lamp, 0.35), 1, true)
	draw_line(center - Vector2(circle_r, 0), center + Vector2(circle_r, 0), Color(palette.lamp, 0.4), 1)
	draw_line(center - Vector2(0, circle_r), center + Vector2(0, circle_r), Color(palette.lamp, 0.4), 1)
	var bearing: float = -PI * 0.35 + (sin(_clock) * 0.1 if is_busy() else 0.0)
	draw_line(center, center + Vector2.from_angle(bearing) * circle_r, palette.lamp, 3, true)
	_emblem(Rect2(center - Vector2(12, 12), Vector2(24, 24)), "B")
	var quotes: Array = view.get("forecast_quotes", [])
	for i in maxi(1, quotes.size()):
		var q: Dictionary = quotes[i] if i < quotes.size() else {}
		var y := r.position.y + r.size.y * (i + 0.5) / maxi(1, quotes.size())
		_words(Rect2(Vector2(r.position.x + r.size.x * 0.52, y - 14), Vector2(r.size.x * 0.45, 28)), "%s · %.1f%% · %.3fx" % [q.get("label", "Awaiting forecast"), float(q.get("chance", 0)) / 10, float(q.get("gross_basis", 0)) / 1000], 12 if small else 16, palette.paper)
		if not small:
			var bar := Rect2(Vector2(r.position.x + r.size.x * 0.52, y + 15), Vector2(r.size.x * 0.42, 4))
			draw_rect(bar, palette.felt_dark)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(q.get("chance", 0)) / 1000, 4)), palette.lamp)
	# Forecast bets remain individual selectable portfolio positions.
	if game.state == CasinoGame.BETTING and not quotes.is_empty() and r.size.y >= quotes.size() * 44:
		for i in quotes.size():
			var q: Dictionary = quotes[i]
			var spot := StringName(q["id"])
			var rect := Rect2(Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * i / quotes.size()), Vector2(r.size.x * 0.5, r.size.y / quotes.size()))
			_spot_rects[spot] = rect
			if spot == selected_spot:
				draw_rect(rect.grow(-1), palette.lamp, false, 2)

func _bank(r: Rect2) -> void:
	var cards: Array = view.get("offers", [])
	var candidate: Dictionary = view.get("candidatecard", {})
	if not candidate.is_empty(): cards = [candidate, view.get("bankcard", {"rank": 0, "face_up": false})]
	if cards.is_empty(): cards = [{"rank": 0, "face_up": false}, {"rank": 0, "face_up": false}, {"rank": 0, "face_up": false}]
	if (_compact_board or r.size.y < 125) and not candidate.is_empty():
		var height := minf(r.size.y - 8, 100)
		_draw_card(Rect2(r.position + Vector2(6, 4), Vector2(height * 0.68, height)), candidate)
		var inset := height * 0.68 + 18
		var quotes: Array = view.get("contract_quotes", [])
		for i in quotes.size():
			var q: Dictionary = quotes[i]
			_words(Rect2(r.position + Vector2(inset, r.size.y * i / 3), Vector2(r.size.x - inset - 6, r.size.y / 3)), "%s %d/49 · %s gross" % [q["label"], q["chance_numerator"], CasinoLines.money(int(q["returned"]))], 12, palette.paper)
		return
	var card_h := minf(r.size.y - 12, 155)
	var card_w := minf(card_h * 0.68, (r.size.x - 26) / (cards.size() + 0.8))
	var card_y := r.get_center().y - card_h / 2
	for i in cards.size():
		var x := r.position.x + r.size.x * (i + 0.5) / cards.size() - card_w / 2
		_draw_card(Rect2(Vector2(x, card_y), Vector2(card_w, card_h)), cards[i])
		if game.state == CasinoGame.PLAYING and candidate.is_empty() and card_h >= 44 and card_w + 8 >= 44:
			choice_rects[StringName("draft_%d" % i)] = Rect2(Vector2(x - 4, card_y), Vector2(card_w + 8, card_h))

func _pool(r: Rect2) -> void:
	var small := _compact_board or r.size.y < 125
	if small:
		var quotes: Array = view.get("claim_quotes", [])
		var total := 0
		for bid in view.get("crewbids", []): total += int(bid)
		for i in quotes.size():
			var q: Dictionary = quotes[i]
			_words(Rect2(r.position + Vector2(8, r.size.y * i / 3), Vector2(r.size.x - 16, r.size.y / 3)), "Claim %d · %d/%d · %.1f%% · %s gross" % [int(q["share"]), int(q["share"]), total + int(q["share"]), float(q["chance"]) / 10, CasinoLines.money(int(q["returned"]))], 12, palette.paper, true)
		return
	var center := r.position + Vector2(r.size.x * 0.48, r.size.y * 0.54)
	var rx := minf(r.size.x * 0.28, r.size.y * 0.55)
	var ry := r.size.y * 0.35
	var points := PackedVector2Array()
	for i in 48:
		var angle := TAU * i / 48.0
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	draw_colored_polygon(points, palette.felt.lightened(0.1))
	draw_polyline(points + PackedVector2Array([points[0]]), palette.metal, 2, true)
	var bids: Array = view.get("crewbids", [])
	for i in 3:
		var at := center + Vector2.from_angle(PI + i * TAU / 3) * Vector2(rx * 0.95, ry * 0.95)
		var bid := int(bids[i]) if i < bids.size() else 0
		draw_circle(at, 13 if small else 20, palette.wood, true, -1, true)
		_emblem(Rect2(at - Vector2(9, 9), Vector2(18, 18)), ["s1", "s4", "s5"][i])
		if not small:
			_words(Rect2(Vector2(at.x - 36, clampf(at.y + 22, r.position.y + 5, r.end.y - 25)), Vector2(72, 24)), "%d shares" % bid, 12, palette.paper, true)
	_words(Rect2(center - Vector2(rx * 0.65, 16), Vector2(rx * 1.3, 32)), CasinoLines.money(int(view.get("pot", 0))), 14 if small else 20, palette.lamp, true)
	if not small:
		_words(Rect2(r.position + Vector2(6, 5), Vector2(r.size.x - 12, 24)), "COMMON POT · house sponsored", 12, palette.paper, true)

func _emblem(rect: Rect2, symbol: String) -> void:
	var art := ResortArtwork.payout(resort, symbol)
	if art == null: return
	var extent := art.get_size() * minf(rect.size.x / art.get_width(), rect.size.y / art.get_height())
	draw_texture_rect(art, Rect2(rect.get_center() - extent * 0.5, extent), false)

# Word wrapping is measured against the actual box; no ellipsis and no text
# outside its panel. Oversized detail belongs in the full Rules sheet.
func _words(rect: Rect2, value: String, font_size: int, color: Color, centered := false) -> void:
	if value.is_empty() or rect.size.x <= 0 or rect.size.y <= 0: return
	text_boxes.append(rect)
	rendered_text.append(value)
	var font := palette.body_font
	var fitted := font_size
	var lines: Array[String] = []
	while fitted >= 10:
		lines.clear()
		for paragraph: String in value.split("\n"):
			var line := ""
			for word: String in paragraph.split(" ", false):
				var trial := word if line.is_empty() else line + " " + word
				if not line.is_empty() and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > rect.size.x:
					lines.append(line)
					line = word
				else: line = trial
			if not line.is_empty(): lines.append(line)
		if lines.size() * font.get_height(fitted) <= rect.size.y: break
		fitted -= 1
	fitted = maxi(10, fitted)
	var step := font.get_height(fitted)
	if lines.size() * step > rect.size.y + 0.5:
		text_overflows.append(value)
	for line: String in lines:
		if font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > rect.size.x + 0.5:
			text_overflows.append(value)
	for i in lines.size():
		var center := Vector2(rect.get_center().x if centered else rect.position.x, rect.position.y + step * (i + 0.5))
		if centered: _text_fit(center, lines[i], fitted, color, font, rect.size.x)
		else: _text_left(center, lines[i], fitted, color, font)
