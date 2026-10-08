# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The money wheel: 54 segments, bets on the segment the pointer stops at.
##
## Spots: `seg_1`, `seg_2`, `seg_5`, `seg_10`, `seg_20` (their number to one)
## and `emblem_a`, `emblem_b` (40 to 1; the resort theme names them).
## Action: `spin` (commits). Events: `wheel` {segment, symbol}, `settle`.
class_name MoneyWheelGame
extends CasinoGame

const SPIN := &"spin"
const HISTORY := 12
const SYMBOLS: Array[String] = ["1", "2", "5", "10", "20", "emblem_a", "emblem_b"]

var _segment := -1
var _history: Array[String] = []


func _init() -> void:
	kind = &"money_wheel"


func commit_action() -> StringName:
	return SPIN


func commit_label() -> String:
	return "Spin"


func spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for symbol in SYMBOLS:
		var odds := "%d to 1" % (int(CasinoParams.WHEEL_RETURNS[symbol]) - 1)
		var label := symbol if not symbol.begins_with("emblem") else ("Emblem A" if symbol == "emblem_a" else "Emblem B")
		out.append(_spot(spot_for(symbol), label, odds, "emblems" if symbol.begins_with("emblem") else "numbers"))
	return out


## The bet spot that wins when the wheel stops on `symbol`.
static func spot_for(symbol: String) -> StringName:
	return StringName(symbol) if symbol.begins_with("emblem") else StringName("seg_" + symbol)


func _act(action: StringName, _payload: Dictionary) -> Dictionary:
	if action != SPIN:
		return _refuse(CasinoLines.ACTION_UNAVAILABLE)
	state = PLAYING
	_segment = _draw_below(CasinoParams.WHEEL_LAYOUT.size())
	var symbol: String = CasinoParams.WHEEL_LAYOUT[_segment]
	_history.push_front(symbol)
	while _history.size() > HISTORY:
		_history.pop_back()
	_emit({"kind": "wheel", "segment": _segment, "symbol": symbol})
	var stake := int(_bets.get(spot_for(symbol), 0))
	var returned := stake * int(CasinoParams.WHEEL_RETURNS[symbol])
	var reaction := _plain_reaction(returned)
	if returned > 0 and symbol.begins_with("emblem"):
		reaction = "jackpot"
	var stopped := "an emblem" if symbol.begins_with("emblem") else symbol
	_settle(returned, "The wheel stops on %s." % stopped, {"segment": _segment, "symbol": symbol}, reaction)
	return _accept()


func _view() -> Dictionary:
	return {
		"segments": CasinoParams.WHEEL_LAYOUT.duplicate(),
		"segment": _segment,
		"symbol": CasinoParams.WHEEL_LAYOUT[_segment] if _segment >= 0 else "",
		"history": _history.duplicate(),
	}
