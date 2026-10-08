# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Three-reel, one-line slot machine with authored strips.
##
## Symbols are `s1`..`s5` and the bonus `B`; the resort theme names them.
## Spot: `line`. Action: `pull` (commits). Events: `spin`, `reel_stop`
## {reel, stop, symbol} for each reel left to right, `jackpot` on three
## bonus symbols, `settle`.
class_name SlotsGame
extends CasinoGame

const LINE := &"line"
const PULL := &"pull"

var _stops: Array[int] = [0, 0, 0]


func _init() -> void:
	kind = &"slots"


func commit_action() -> StringName:
	return PULL


func commit_label() -> String:
	return "Pull"


func spots() -> Array[Dictionary]:
	return [_spot(LINE, "Line", "Up to 200 for 1", "line")]


## Return per stake for the three symbols on the line.
static func line_return(symbols: Array) -> int:
	if symbols.size() != 3:
		return 0
	var triples: Dictionary = CasinoParams.SLOT_TRIPLE_RETURNS
	if symbols[0] == symbols[1] and symbols[1] == symbols[2]:
		return int(triples.get(String(symbols[0]), 0))
	var bonus := 0
	for s in symbols:
		if String(s) == "B":
			bonus += 1
	var bonus_returns: Dictionary = CasinoParams.SLOT_BONUS_RETURNS
	return int(bonus_returns.get(bonus, 0))


## The symbol showing on the line of `reel` at `stop`.
static func symbol_at(reel: int, stop: int) -> String:
	var strip: Array = CasinoParams.SLOT_STRIPS[reel]
	return String(strip[posmod(stop, strip.size())])


func _act(action: StringName, _payload: Dictionary) -> Dictionary:
	if action != PULL:
		return _refuse(CasinoLines.ACTION_UNAVAILABLE)
	state = PLAYING
	_emit({"kind": "spin"})
	var symbols: Array[String] = []
	for reel in 3:
		var strip: Array = CasinoParams.SLOT_STRIPS[reel]
		_stops[reel] = _draw_below(strip.size())
		var symbol := symbol_at(reel, _stops[reel])
		symbols.append(symbol)
		_emit({"kind": "reel_stop", "reel": reel, "stop": _stops[reel], "symbol": symbol})
	var multiple := line_return(symbols)
	var returned := int(_bets.get(LINE, 0)) * multiple
	var jackpot := symbols[0] == "B" and symbols[1] == "B" and symbols[2] == "B"
	if jackpot:
		_emit({"kind": "jackpot"})
	var summary := "Pays %d for 1." % multiple if multiple > 0 else "No pay."
	_settle(returned, summary, {"stops": _stops.duplicate(), "symbols": symbols.duplicate(), "multiple": multiple},
		"jackpot" if jackpot else _plain_reaction(returned))
	return _accept()


func _view() -> Dictionary:
	var strips: Array = []
	for strip in CasinoParams.SLOT_STRIPS:
		strips.append((strip as Array).duplicate())
	var symbols: Array = []
	for reel in 3:
		symbols.append(symbol_at(reel, _stops[reel]))
	var paytable: Array = []
	for s in ["B", "s5", "s4", "s3", "s2", "s1"]:
		paytable.append({"symbols": [s, s, s], "returns": int(CasinoParams.SLOT_TRIPLE_RETURNS[s])})
	paytable.append({"symbols": ["B", "B"], "returns": int(CasinoParams.SLOT_BONUS_RETURNS[2])})
	paytable.append({"symbols": ["B"], "returns": int(CasinoParams.SLOT_BONUS_RETURNS[1])})
	return {"strips": strips, "stops": _stops.duplicate(), "symbols": symbols, "paytable": paytable}
