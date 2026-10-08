# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Faro: bets on ranks, decided two cards at a time from one deck.
##
## Spots: `rank_1`..`rank_13` back a rank to win; `copper_1`..`copper_13`
## (a "coppered" bet) back it to lose. A rank cannot carry both. Action:
## `turn` (commits): the banker's card shows first (bets on its rank lose),
## then the player's card (bets on its rank win even money). The same rank on
## both is a split and the house takes half. A bet whose rank does not show is
## returned. Events: `shuffle`, `card` {to: "banker"|"player", card, face_up},
## `split` {rank}, `result` {spot, returned}, `settle`.
class_name FaroGame
extends CasinoGame

const TURN := &"turn"
const HISTORY := 12

var _deck: CasinoDeck
var _banker: Dictionary = {}
var _player: Dictionary = {}
## Cards of each rank already shown since the shuffle (the case keeper).
var _shown: Array[int] = []
var _history: Array = []


func _init() -> void:
	kind = &"faro"


func commit_action() -> StringName:
	return TURN


func commit_label() -> String:
	return "Turn"


func spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rank in range(1, 14):
		out.append(_spot(StringName("rank_%d" % rank), CasinoDeck.RANK_NAMES[rank], "1 to 1", "ranks"))
	for rank in range(1, 14):
		out.append(_spot(StringName("copper_%d" % rank), "Copper " + CasinoDeck.RANK_NAMES[rank], "1 to 1, bets to lose", "coppered"))
	return out


## Stack the deck: banker's card, player's card, banker's card...
func rig(values: Array) -> void:
	_deck.stack(values)
	_clear_case()


## Return per stake for a bet when `banker` and `player` ranks show.
## Returns -1 when the bet's rank did not show (the bet comes back).
static func bet_return(spot: StringName, banker: int, player: int) -> float:
	var name := String(spot)
	var coppered := name.begins_with("copper_")
	var rank := int(name.get_slice("_", 1))
	if rank == banker and rank == player:
		return 0.5
	if rank == banker:
		return 2.0 if coppered else 0.0
	if rank == player:
		return 0.0 if coppered else 2.0
	return -1.0


func _reset_table() -> void:
	_deck = CasinoDeck.new(1, _rng)
	_clear_case()


func _clear_case() -> void:
	_shown.clear()
	for _i in 14:
		_shown.append(0)


func _spot_reason(spot: StringName, _amount: int) -> String:
	var name := String(spot)
	var rank := name.get_slice("_", 1)
	var other := StringName(("rank_" if name.begins_with("copper_") else "copper_") + rank)
	if _bets.has(other):
		return CasinoLines.FARO_BOTH_WAYS
	return ""


func _act(action: StringName, _payload: Dictionary) -> Dictionary:
	if action != TURN:
		return _refuse(CasinoLines.ACTION_UNAVAILABLE)
	if not _deck.is_stacked() and _deck.remaining() < CasinoParams.FARO_RESHUFFLE:
		_deck.reset()
		_clear_case()
		_emit({"kind": "shuffle"})
	state = PLAYING
	_banker = _deck.draw()
	_emit({"kind": "card", "to": "banker", "card": _card_view(_banker), "face_up": true})
	_player = _deck.draw()
	_emit({"kind": "card", "to": "player", "card": _card_view(_player), "face_up": true})
	var b := int(_banker["rank"])
	var p := int(_player["rank"])
	_shown[b] += 1
	_shown[p] += 1
	_history.push_front({"banker": b, "player": p})
	while _history.size() > HISTORY:
		_history.pop_back()
	if b == p:
		_emit({"kind": "split", "rank": b})
	var returned := 0
	for spot in _bets:
		var stake := int(_bets[spot])
		var factor := bet_return(spot, b, p)
		var back := stake
		if factor >= 0.0:
			back = floori(stake * factor)
		returned += back
		_emit({"kind": "result", "spot": String(spot), "returned": back})
	var summary := "Banker %s, player %s." % [CasinoDeck.RANK_NAMES[b], CasinoDeck.RANK_NAMES[p]]
	if b == p:
		summary = "A split on %s: the house takes half." % CasinoDeck.RANK_NAMES[b]
	_settle(returned, summary, {"banker": b, "player": p, "split": b == p}, _plain_reaction(returned))
	return _accept()


func _view() -> Dictionary:
	var case_counts: Array = []
	for rank in range(1, 14):
		case_counts.append(_deck.decks * 4 - _shown[rank])
	return {
		"banker": _card_view(_banker) if not _banker.is_empty() else {},
		"player": _card_view(_player) if not _player.is_empty() else {},
		"case": case_counts,
		"remaining": _deck.remaining(),
		"history": _history.duplicate(true),
	}
