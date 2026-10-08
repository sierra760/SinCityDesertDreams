# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Jacks-or-better video poker from one fresh deck per hand.
##
## Spot: `hand`. Actions: `deal` (commits), then `hold` {index: 0..4} to
## toggle a hold and `draw` (optionally {held: [bool x5]}, which replaces the
## holds). Events: `card` {to: "hand", index, card, face_up, replace},
## `hand_rank` {rank, label, returns}, `settle`.
class_name VideoPokerGame
extends CasinoGame

const HAND := &"hand"
const DEAL := &"deal"
const HOLD := &"hold"
const DRAW := &"draw"

const LABELS := {
	"royal_flush": "Royal Flush",
	"straight_flush": "Straight Flush",
	"four_of_a_kind": "Four of a Kind",
	"full_house": "Full House",
	"flush": "Flush",
	"straight": "Straight",
	"three_of_a_kind": "Three of a Kind",
	"two_pair": "Two Pair",
	"jacks_or_better": "Jacks or Better",
	"nothing": "No Pay",
}

var _deck: CasinoDeck
var _cards: Array[Dictionary] = []
var _held: Array[bool] = [false, false, false, false, false]
var _rank := ""
var _stacked: Array = []


func _init() -> void:
	kind = &"video_poker"


func commit_action() -> StringName:
	return DEAL


func commit_label() -> String:
	return "Deal"


func spots() -> Array[Dictionary]:
	return [_spot(HAND, "Bet", "Jacks or better", "hand")]


## Stack the next hand's deck: five dealt cards, then the replacements.
func rig(values: Array) -> void:
	_stacked = values.duplicate()


## The paying hand for five cards, as a POKER_RETURNS key.
static func evaluate(cards: Array) -> String:
	if cards.size() != 5:
		return "nothing"
	var counts := {}
	var suits := {}
	var ranks: Array = []
	for c in cards:
		var rank := int(c["rank"])
		ranks.append(rank)
		counts[rank] = int(counts.get(rank, 0)) + 1
		suits[int(c["suit"])] = true
	ranks.sort()
	var flush := suits.size() == 1
	var straight := false
	var royal := false
	if counts.size() == 5:
		if ranks[4] - ranks[0] == 4:
			straight = true
		elif ranks == [1, 10, 11, 12, 13]:
			straight = true
			royal = true
	if straight and flush:
		return "royal_flush" if royal else "straight_flush"
	var groups: Array = counts.values()
	groups.sort()
	if groups[-1] == 4:
		return "four_of_a_kind"
	if groups == [2, 3]:
		return "full_house"
	if flush:
		return "flush"
	if straight:
		return "straight"
	if groups[-1] == 3:
		return "three_of_a_kind"
	if groups == [1, 2, 2]:
		return "two_pair"
	if groups[-1] == 2:
		for rank in counts:
			if int(counts[rank]) == 2 and (int(rank) == 1 or int(rank) >= CasinoParams.POKER_LOW_PAIR):
				return "jacks_or_better"
	return "nothing"


func _reset_table() -> void:
	_deck = CasinoDeck.new(1, _rng)


func _on_round_start() -> void:
	_cards.clear()
	_held = [false, false, false, false, false]
	_rank = ""


func _playing_actions() -> Array[Dictionary]:
	return [_action(HOLD, "Hold", true, false), _action(DRAW, "Draw", true, true)]


func _act(action: StringName, payload: Dictionary) -> Dictionary:
	match action:
		DEAL:
			if _stacked.is_empty():
				_deck.reset()
			else:
				_deck.stack(_stacked)
				_stacked = []
			state = PLAYING
			for i in 5:
				var c := _deck.draw()
				_cards.append(c)
				_emit({"kind": "card", "to": "hand", "index": i, "card": _card_view(c), "face_up": true, "replace": false})
			return _accept()
		HOLD:
			var index := int(payload.get("index", -1))
			if index < 0 or index > 4:
				return _refuse(CasinoLines.ACTION_UNAVAILABLE)
			_held[index] = not _held[index]
			return _accept()
		DRAW:
			var held: Variant = payload.get("held", null)
			if typeof(held) == TYPE_ARRAY and (held as Array).size() == 5:
				for i in 5:
					_held[i] = bool((held as Array)[i])
			for i in 5:
				if _held[i]:
					continue
				var c := _deck.draw()
				_cards[i] = c
				_emit({"kind": "card", "to": "hand", "index": i, "card": _card_view(c), "face_up": true, "replace": true})
			_rank = evaluate(_cards)
			var multiple := int(CasinoParams.POKER_RETURNS[_rank])
			_emit({"kind": "hand_rank", "rank": _rank, "label": LABELS[_rank], "returns": multiple})
			var returned := int(_bets.get(HAND, 0)) * multiple
			var reaction := _plain_reaction(returned)
			if _rank == "royal_flush" or _rank == "straight_flush" or _rank == "four_of_a_kind":
				reaction = "jackpot"
			_settle(returned, "%s. Pays %d for 1." % [LABELS[_rank], multiple] if multiple > 0 else "No pay.",
				{"rank": _rank, "label": LABELS[_rank], "multiple": multiple}, reaction)
			return _accept()
	return _refuse(CasinoLines.ACTION_UNAVAILABLE)


func _view() -> Dictionary:
	var cards: Array = []
	for c in _cards:
		cards.append(_card_view(c))
	var paytable: Array = []
	for key in CasinoParams.POKER_RETURNS:
		if key != "nothing":
			paytable.append({"rank": key, "label": LABELS[key], "returns": int(CasinoParams.POKER_RETURNS[key])})
	return {
		"cards": cards,
		"held": _held.duplicate(),
		"rank": _rank,
		"rank_label": String(LABELS.get(_rank, "")),
		"paytable": paytable,
	}
