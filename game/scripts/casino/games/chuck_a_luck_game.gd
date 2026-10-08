# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Chuck-a-luck: three dice tumbled in a wire cage.
##
## Spots: `die_1`..`die_6` (the stake back plus even money for each die
## showing the number) and `any_triple` (30 to 1). Action: `roll` (commits).
## Events: `dice` {dice: [a, b, c]}, `settle`.
class_name ChuckALuckGame
extends CasinoGame

const ROLL := &"roll"
const TRIPLE := &"any_triple"
const HISTORY := 12

var _dice: Array[int] = []
var _history: Array = []


func _init() -> void:
	kind = &"chuck_a_luck"


func commit_action() -> StringName:
	return ROLL


func commit_label() -> String:
	return "Roll"


func spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in range(1, 7):
		out.append(_spot(StringName("die_%d" % n), str(n), "1 to 1 for each die", "numbers"))
	out.append(_spot(TRIPLE, "Any triple", "30 to 1", "triples"))
	return out


## Return per stake for a bet on `spot` when `dice` show.
static func bet_return(spot: StringName, dice: Array) -> int:
	if dice.size() != 3:
		return 0
	if spot == TRIPLE:
		return CasinoParams.CHUCK_TRIPLE_RETURN if dice[0] == dice[1] and dice[1] == dice[2] else 0
	var number := int(String(spot).get_slice("_", 1))
	var hits := 0
	for d in dice:
		if int(d) == number:
			hits += 1
	return hits + 1 if hits > 0 else 0


func _act(action: StringName, _payload: Dictionary) -> Dictionary:
	if action != ROLL:
		return _refuse(CasinoLines.ACTION_UNAVAILABLE)
	state = PLAYING
	_dice.clear()
	for _i in 3:
		_dice.append(_draw_below(6) + 1)
	_history.push_front(_dice.duplicate())
	while _history.size() > HISTORY:
		_history.pop_back()
	_emit({"kind": "dice", "dice": _dice.duplicate()})
	var returned := 0
	for spot in _bets:
		returned += int(_bets[spot]) * bet_return(spot, _dice)
	var triple := _dice[0] == _dice[1] and _dice[1] == _dice[2]
	var reaction := _plain_reaction(returned)
	if triple and _bets.has(TRIPLE):
		reaction = "jackpot"
	_settle(returned, "The cage shows %d, %d, %d." % [_dice[0], _dice[1], _dice[2]],
		{"dice": _dice.duplicate(), "triple": triple}, reaction)
	return _accept()


func _view() -> Dictionary:
	return {"dice": _dice.duplicate(), "history": _history.duplicate(true)}
