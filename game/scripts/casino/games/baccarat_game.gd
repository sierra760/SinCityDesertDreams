# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Baccarat from an eight-deck shoe with the standard third-card tableau.
##
## Spots: `player` (1 to 1), `banker` (1 to 1 less commission), `tie` (8 to 1;
## player and banker bets are returned on a tie). Action: `deal` (commits).
## Events: `shuffle`, `card` {to: "player"|"banker", index, card, face_up},
## `natural` {who: "player"|"banker"|"both", total}, `result` {winner, player,
## banker}, `settle`.
class_name BaccaratGame
extends CasinoGame

const DEAL := &"deal"
const PLAYER := &"player"
const BANKER := &"banker"
const TIE := &"tie"
const HISTORY := 12

var _shoe: CasinoDeck
var _player_cards: Array[Dictionary] = []
var _banker_cards: Array[Dictionary] = []
var _winner := ""
var _history: Array[String] = []


func _init() -> void:
	kind = &"baccarat"


func commit_action() -> StringName:
	return DEAL


func commit_label() -> String:
	return "Deal"


func spots() -> Array[Dictionary]:
	return [
		_spot(PLAYER, "Player", "1 to 1", "main"),
		_spot(BANKER, "Banker", "1 to 1 less 5%", "main"),
		_spot(TIE, "Tie", "8 to 1", "tie"),
	]


## Stack the shoe: player, banker, player, banker, then third cards
## (player's first when it draws).
func rig(values: Array) -> void:
	_shoe.stack(values)


## A card's point value: aces one, tens and court cards zero.
static func point(c: Dictionary) -> int:
	var rank := int(c["rank"])
	return 0 if rank >= 10 else rank


static func total_of(cards: Array) -> int:
	var total := 0
	for c in cards:
		total += point(c)
	return total % 10


## Whether the banker draws on `banker_total`. `player_third` is the point
## value of the player's third card, or -1 when the player stood.
static func banker_draws(banker_total: int, player_third: int) -> bool:
	if player_third < 0:
		return banker_total <= 5
	match banker_total:
		0, 1, 2:
			return true
		3:
			return player_third != 8
		4:
			return player_third >= 2 and player_third <= 7
		5:
			return player_third >= 4 and player_third <= 7
		6:
			return player_third == 6 or player_third == 7
	return false


## Return for `stake` on `spot` when `winner` takes the coup.
static func bet_return(spot: StringName, stake: int, winner: String) -> int:
	match spot:
		PLAYER:
			if winner == "player":
				return stake * 2
			return stake if winner == "tie" else 0
		BANKER:
			if winner == "banker":
				@warning_ignore("integer_division")
				return stake + stake * (100 - CasinoParams.BACCARAT_COMMISSION_PERCENT) / 100
			return stake if winner == "tie" else 0
		TIE:
			return stake * CasinoParams.BACCARAT_TIE_RETURN if winner == "tie" else 0
	return 0


func _reset_table() -> void:
	_shoe = CasinoDeck.new(CasinoParams.BACCARAT_DECKS, _rng)


func _on_round_start() -> void:
	_player_cards.clear()
	_banker_cards.clear()
	_winner = ""


func _act(action: StringName, _payload: Dictionary) -> Dictionary:
	if action != DEAL:
		return _refuse(CasinoLines.ACTION_UNAVAILABLE)
	if _shoe.reshuffle_below(CasinoParams.BACCARAT_RESHUFFLE):
		_emit({"kind": "shuffle"})
	state = PLAYING
	_give(_player_cards, "player")
	_give(_banker_cards, "banker")
	_give(_player_cards, "player")
	_give(_banker_cards, "banker")
	var pt := total_of(_player_cards)
	var bt := total_of(_banker_cards)
	if pt >= 8 or bt >= 8:
		var who := "both" if pt >= 8 and bt >= 8 else ("player" if pt >= 8 else "banker")
		_emit({"kind": "natural", "who": who, "total": maxi(pt, bt)})
	else:
		var third := -1
		if pt <= 5:
			_give(_player_cards, "player")
			third = point(_player_cards[2])
		if banker_draws(bt, third):
			_give(_banker_cards, "banker")
	pt = total_of(_player_cards)
	bt = total_of(_banker_cards)
	_winner = "tie" if pt == bt else ("player" if pt > bt else "banker")
	_history.push_front(_winner)
	while _history.size() > HISTORY:
		_history.pop_back()
	_emit({"kind": "result", "winner": _winner, "player": pt, "banker": bt})
	var returned := 0
	for spot in _bets:
		returned += bet_return(spot, int(_bets[spot]), _winner)
	var summary := "Tie at %d." % pt if _winner == "tie" else "%s wins, %d to %d." % [_winner.capitalize(), maxi(pt, bt), mini(pt, bt)]
	_settle(returned, summary, {"winner": _winner, "player": pt, "banker": bt}, _plain_reaction(returned))
	return _accept()


func _give(hand: Array[Dictionary], to: String) -> void:
	var c := _shoe.draw()
	hand.append(c)
	_emit({"kind": "card", "to": to, "index": hand.size() - 1, "card": _card_view(c), "face_up": true})


func _view() -> Dictionary:
	var player: Array = []
	for c in _player_cards:
		player.append(_card_view(c))
	var banker: Array = []
	for c in _banker_cards:
		banker.append(_card_view(c))
	return {
		"player": {"cards": player, "total": total_of(_player_cards)},
		"banker": {"cards": banker, "total": total_of(_banker_cards)},
		"winner": _winner,
		"history": _history.duplicate(),
		"shoe": _shoe.remaining() if _shoe != null else 0,
	}
