# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Three nested thresholds share one draw: a portfolio of correlated risk.
class_name AfterglowForecastGame
extends OriginalSignatureGame

const IDS := [&"steady", &"pulse", &"surge"]
const CHANCES := [[950, 650, 250], [900, 550, 180], [920, 700, 350]]
const CLASSES := ["Clear horizon", "Thin atmosphere", "Charged dusk"]
var _class := 0
var _draw := -1

func _init() -> void:
	kind = &"afterglow_forecast"
	title = "Afterglow Forecast"
	rules_text = "Allocate your stake between Steady, Pulse and Surge. The visible forecast gives each signal's exact probability and gross return per dollar. One draw from 0–999 resolves all three thresholds together: a surge also brings a pulse and steady glow. Each gross multiplier is floor(960000 / chance) per thousand, and each individual payout rounds down to whole dollars."

func commit_action() -> StringName:
	return &"observe"

func commit_label() -> String:
	return "Observe the horizon"

func _on_round_start() -> void:
	_class = _draw_below(3)
	_draw = -1

func spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for quote in _quotes():
		out.append(_spot(quote["id"], quote["label"], "%.1f%% · %0.3fx gross" % [int(quote["chance"]) / 10.0, int(quote["gross_basis"]) / 1000.0], "forecast"))
	return out

func _quotes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in 3:
		var chance := int(CHANCES[_class][i])
		var basis := scale(960000, 1, chance)
		out.append({"id": IDS[i], "label": String(IDS[i]).capitalize(), "chance": chance, "gross_basis": basis,
			"returned": scale(int(_bets.get(IDS[i], 0)), basis, 1000)})
	return out

func _act(_action: StringName, _payload: Dictionary) -> Dictionary:
	_draw = _draw_below(1000)
	var returned := 0
	var signals: Array[String] = []
	for quote in _quotes():
		if _draw < int(quote["chance"]):
			returned += int(quote["returned"])
			signals.append(String(quote["id"]))
	_emit({"kind": "forecast", "draw": _draw, "signals": signals})
	_finish(returned, "%s: %s. $%d returned." % [CLASSES[_class], "no signal" if signals.is_empty() else ", ".join(signals), returned])
	return _accept()

func _view() -> Dictionary:
	var out := _presentation("Allocate your forecast", "All signals share one draw. Spread your stake or concentrate it.", CLASSES[_class])
	out.merge({"forecast_class": CLASSES[_class], "forecast_quotes": _quotes(), "draw": _draw})
	return out
