# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Single-zero roulette. Any number of spots; the maximum applies to the total.
##
## Spots: `n0`..`n36` (straight up, 35 to 1), `red`, `black`, `odd`, `even`,
## `low`, `high` (1 to 1), `dozen_1`..`dozen_3` and `column_1`..`column_3`
## (2 to 1). Action: `spin` (commits). Events: `spin` {pocket, color},
## `result` {spot, won, returned} per bet, `settle`.
class_name RouletteGame
extends CasinoGame

const SPIN := &"spin"
const HISTORY := 12

var _pocket := -1
var _history: Array[int] = []


func _init() -> void:
	kind = &"roulette"


func commit_action() -> StringName:
	return SPIN


func commit_label() -> String:
	return "Spin"


func spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in CasinoParams.ROULETTE_POCKETS:
		out.append(_spot(StringName("n%d" % n), str(n), "35 to 1", "straight"))
	out.append(_spot(&"red", "Red", "1 to 1", "even_money"))
	out.append(_spot(&"black", "Black", "1 to 1", "even_money"))
	out.append(_spot(&"odd", "Odd", "1 to 1", "even_money"))
	out.append(_spot(&"even", "Even", "1 to 1", "even_money"))
	out.append(_spot(&"low", "1 to 18", "1 to 1", "even_money"))
	out.append(_spot(&"high", "19 to 36", "1 to 1", "even_money"))
	for d in 3:
		out.append(_spot(StringName("dozen_%d" % (d + 1)), ["1st 12", "2nd 12", "3rd 12"][d], "2 to 1", "dozens"))
	for c in 3:
		out.append(_spot(StringName("column_%d" % (c + 1)), "Column %d" % (c + 1), "2 to 1", "columns"))
	return out


## "red", "black" or "green" for a pocket.
static func color_of(pocket: int) -> String:
	if pocket <= 0:
		return "green"
	return "red" if pocket in CasinoParams.ROULETTE_RED else "black"


## The return per stake for a bet on `spot` when the ball lands in `pocket`.
static func spot_return(spot: StringName, pocket: int) -> int:
	var name := String(spot)
	var returns: Dictionary = CasinoParams.ROULETTE_RETURNS
	if name.begins_with("n"):
		return int(returns["straight"]) if int(name.substr(1)) == pocket else 0
	if pocket <= 0:
		return 0
	var won := false
	match name:
		"red":
			won = color_of(pocket) == "red"
		"black":
			won = color_of(pocket) == "black"
		"odd":
			won = pocket % 2 == 1
		"even":
			won = pocket % 2 == 0
		"low":
			won = pocket <= 18
		"high":
			won = pocket >= 19
		_:
			if name.begins_with("dozen_"):
				@warning_ignore("integer_division")
				won = (pocket - 1) / 12 + 1 == int(name.substr(6))
				return int(returns["dozens"]) if won else 0
			if name.begins_with("column_"):
				won = (pocket - 1) % 3 + 1 == int(name.substr(7))
				return int(returns["columns"]) if won else 0
	return int(returns["even_money"]) if won else 0


func _act(action: StringName, _payload: Dictionary) -> Dictionary:
	if action != SPIN:
		return _refuse(CasinoLines.ACTION_UNAVAILABLE)
	state = PLAYING
	_pocket = _draw_below(CasinoParams.ROULETTE_POCKETS)
	_history.push_front(_pocket)
	while _history.size() > HISTORY:
		_history.pop_back()
	var color := color_of(_pocket)
	_emit({"kind": "spin", "pocket": _pocket, "color": color})
	var returned := 0
	var winners := 0
	for spot in _bets:
		var back := int(_bets[spot]) * spot_return(spot, _pocket)
		returned += back
		if back > 0:
			winners += 1
		_emit({"kind": "result", "spot": String(spot), "won": back > 0, "returned": back})
	var summary := "%d %s." % [_pocket, color]
	if winners > 0:
		summary += " %d %s." % [winners, "bet wins" if winners == 1 else "bets win"]
	_settle(returned, summary, {"pocket": _pocket, "color": color}, _plain_reaction(returned))
	return _accept()


func _view() -> Dictionary:
	return {
		"pocket": _pocket,
		"color": color_of(_pocket) if _pocket >= 0 else "",
		"history": _history.duplicate(),
		"red": CasinoParams.ROULETTE_RED.duplicate(),
	}
