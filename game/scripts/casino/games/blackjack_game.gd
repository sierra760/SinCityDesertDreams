# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Blackjack from a six-deck shoe. Dealer stands on all 17s, a two-card 21
## pays 3 to 2, double on any first two cards, split once.
##
## Spot: `main`. Actions: `deal` (commits), then `hit`, `stand`, `double`,
## `split`. Events: `card` {to: "player"|"dealer", hand, card, face_up},
## `reveal` {to: "dealer", card}, `blackjack` {who}, `bust` {who, hand},
## `double` {hand}, `split` {hand}, `dealer_stands` {total},
## `result` {hand, result: win|lose|push|blackjack|bust, returned}, `shuffle`,
## `settle`. Hidden cards travel as {rank: 0, suit: 0}.
class_name BlackjackGame
extends CasinoGame

const MAIN := &"main"
const DEAL := &"deal"
const HIT := &"hit"
const STAND := &"stand"
const DOUBLE := &"double"
const SPLIT := &"split"

var _shoe: CasinoDeck
## {cards: Array[Dictionary], stake: int, doubled: bool, done: bool,
##  split: bool, split_aces: bool, result: String, returned: int}
var _hands: Array[Dictionary] = []
var _dealer: Array[Dictionary] = []
var _hole_hidden := true
var _active := 0
var _split_used := false


func _init() -> void:
	kind = &"blackjack"


func commit_action() -> StringName:
	return DEAL


func commit_label() -> String:
	return "Deal"


func spots() -> Array[Dictionary]:
	return [_spot(MAIN, "Bet", "1 to 1, blackjack 3 to 2", "main")]


## Stack the shoe with cards: the deal order is player, dealer up card,
## player, dealer hole card, then hits in order.
func rig(values: Array) -> void:
	_shoe.stack(values)


## Hand total and whether an ace is being counted as eleven.
static func total_of(cards: Array) -> Dictionary:
	var total := 0
	var aces := 0
	for c in cards:
		var rank := int(c["rank"])
		if rank == 1:
			aces += 1
		total += mini(rank, 10)
	var soft := aces > 0 and total + 10 <= 21
	return {"total": total + 10 if soft else total, "soft": soft}


func _reset_table() -> void:
	_shoe = CasinoDeck.new(CasinoParams.BLACKJACK_DECKS, _rng)


func _on_round_start() -> void:
	_hands.clear()
	_dealer.clear()
	_hole_hidden = true
	_active = 0
	_split_used = false


func _playing_actions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _active >= _hands.size():
		return out
	var hand := _hands[_active]
	var cards: Array = hand["cards"]
	var first_two := cards.size() == 2 and not bool(hand["split_aces"])
	var room := total_staked() + int(hand["stake"]) <= int(limits["maximum"])
	out.append(_action(HIT, "Hit", true, true))
	out.append(_action(STAND, "Stand", true, true))
	out.append(_action(DOUBLE, "Double", first_two and room, false))
	out.append(_action(SPLIT, "Split", first_two and room and not _split_used
		and int(cards[0]["rank"]) == int(cards[1]["rank"]), false))
	return out


func _act(action: StringName, _payload: Dictionary) -> Dictionary:
	match action:
		DEAL:
			_deal()
			return _accept()
		HIT:
			_hit()
			return _accept()
		STAND:
			_hands[_active]["done"] = true
			_advance()
			return _accept()
		DOUBLE:
			return _accept(_double())
		SPLIT:
			return _accept(_split())
	return _refuse(CasinoLines.ACTION_UNAVAILABLE)


func _deal() -> void:
	if _shoe.reshuffle_below(CasinoParams.BLACKJACK_RESHUFFLE):
		_emit({"kind": "shuffle"})
	state = PLAYING
	_hands = [_new_hand(int(_bets.get(MAIN, 0)), false)]
	_give(0)
	_give_dealer(true)
	_give(0)
	_give_dealer(false)
	var player_natural := _is_natural(_hands[0])
	var dealer_natural := _dealer.size() == 2 and int(total_of(_dealer)["total"]) == 21
	if not player_natural and not dealer_natural:
		return
	_reveal()
	var stake := int(_hands[0]["stake"])
	var returned := 0
	var result := "lose"
	if player_natural:
		_emit({"kind": "blackjack", "who": "player"})
	if dealer_natural:
		_emit({"kind": "blackjack", "who": "dealer"})
	if player_natural and dealer_natural:
		returned = stake
		result = "push"
	elif player_natural:
		@warning_ignore("integer_division")
		returned = stake + stake * CasinoParams.BLACKJACK_NATURAL_NUMERATOR / CasinoParams.BLACKJACK_NATURAL_DENOMINATOR
		result = "blackjack"
	_hands[0]["done"] = true
	_hands[0]["result"] = result
	_hands[0]["returned"] = returned
	_emit({"kind": "result", "hand": 0, "result": result, "returned": returned})
	_active = 1
	var summary := "Blackjack and blackjack: a push." if result == "push" \
		else ("Blackjack! Pays three to two." if result == "blackjack" else "Dealer blackjack.")
	_settle(returned, summary, {"player": [_hand_detail(0)], "dealer": _dealer_total()},
		"blackjack" if result == "blackjack" else ("push" if result == "push" else "lose"))


func _hit() -> void:
	_give(_active)
	_check_hand(_active)
	_advance()


func _double() -> int:
	var hand := _hands[_active]
	var extra := int(hand["stake"])
	hand["stake"] = extra * 2
	hand["doubled"] = true
	_extra_stake += extra
	_emit({"kind": "double", "hand": _active})
	_give(_active)
	_check_hand(_active)
	hand["done"] = true
	_advance()
	return extra


func _split() -> int:
	var hand := _hands[_active]
	var cards: Array = hand["cards"]
	var stake := int(hand["stake"])
	var aces := int(cards[0]["rank"]) == 1
	var moved: Dictionary = cards.pop_back()
	var second := _new_hand(stake, true)
	(second["cards"] as Array).append(moved)
	hand["split"] = true
	hand["split_aces"] = aces
	second["split_aces"] = aces
	_hands.insert(_active + 1, second)
	_extra_stake += stake
	_split_used = true
	_emit({"kind": "split", "hand": _active})
	_give(_active)
	_give(_active + 1)
	for i in [_active, _active + 1]:
		if aces:
			_hands[i]["done"] = true
		else:
			_check_hand(i)
	_advance()
	return stake


func _check_hand(i: int) -> void:
	var total := int(total_of(_hands[i]["cards"])["total"])
	if total > 21:
		_hands[i]["done"] = true
		_emit({"kind": "bust", "who": "player", "hand": i})
	elif total == 21:
		_hands[i]["done"] = true


func _advance() -> void:
	while _active < _hands.size() and bool(_hands[_active]["done"]):
		_active += 1
	if _active >= _hands.size():
		_finish()


func _finish() -> void:
	_reveal()
	var live := false
	for hand in _hands:
		if int(total_of(hand["cards"])["total"]) <= 21:
			live = true
	var dealer_total := int(total_of(_dealer)["total"])
	if live:
		while dealer_total < CasinoParams.BLACKJACK_DEALER_STANDS:
			_give_dealer(true)
			dealer_total = int(total_of(_dealer)["total"])
		if dealer_total > 21:
			_emit({"kind": "bust", "who": "dealer", "hand": -1})
		else:
			_emit({"kind": "dealer_stands", "total": dealer_total})
	var returned := 0
	var all_bust := true
	var parts: Array[String] = []
	for i in _hands.size():
		var hand := _hands[i]
		var stake := int(hand["stake"])
		var total := int(total_of(hand["cards"])["total"])
		var result := "lose"
		var back := 0
		if total > 21:
			result = "bust"
		else:
			all_bust = false
			if dealer_total > 21 or total > dealer_total:
				result = "win"
				back = stake * 2
			elif total == dealer_total:
				result = "push"
				back = stake
		hand["result"] = result
		hand["returned"] = back
		returned += back
		_emit({"kind": "result", "hand": i, "result": result, "returned": back})
		parts.append("%d %s" % [total, _result_word(result)])
	var dealer_text := "Dealer busts" if dealer_total > 21 else "Dealer %d" % dealer_total
	var hands_detail: Array = []
	for i in _hands.size():
		hands_detail.append(_hand_detail(i))
	var reaction := _plain_reaction(returned)
	if all_bust:
		reaction = "bust"
	_settle(returned, "%s. You: %s." % [dealer_text, ", ".join(parts)],
		{"player": hands_detail, "dealer": dealer_total}, reaction)


static func _result_word(result: String) -> String:
	match result:
		"win":
			return "wins"
		"push":
			return "pushes"
		"bust":
			return "busts"
	return "loses"


func _give(i: int) -> void:
	var c := _shoe.draw()
	(_hands[i]["cards"] as Array).append(c)
	_emit({"kind": "card", "to": "player", "hand": i, "card": _card_view(c), "face_up": true})


func _give_dealer(face_up: bool) -> void:
	var c := _shoe.draw()
	_dealer.append(c)
	_emit({"kind": "card", "to": "dealer", "hand": -1, "card": _card_view(c, face_up), "face_up": face_up})


func _reveal() -> void:
	if not _hole_hidden:
		return
	_hole_hidden = false
	if _dealer.size() >= 2:
		_emit({"kind": "reveal", "to": "dealer", "card": _card_view(_dealer[1])})


func _is_natural(hand: Dictionary) -> bool:
	var cards: Array = hand["cards"]
	return not bool(hand["split"]) and cards.size() == 2 and int(total_of(cards)["total"]) == 21


func _new_hand(stake: int, from_split: bool) -> Dictionary:
	return {"cards": [], "stake": stake, "doubled": false, "done": false, "split": from_split,
		"split_aces": false, "result": "", "returned": 0}


func _hand_detail(i: int) -> Dictionary:
	var hand := _hands[i]
	var t := total_of(hand["cards"])
	return {"total": int(t["total"]), "stake": int(hand["stake"]), "result": String(hand["result"])}


func _dealer_total() -> int:
	return int(total_of(_dealer)["total"])


func _view() -> Dictionary:
	var hands: Array = []
	for hand in _hands:
		var cards: Array = []
		for c in hand["cards"]:
			cards.append(_card_view(c))
		var t := total_of(hand["cards"])
		hands.append({"cards": cards, "total": int(t["total"]), "soft": bool(t["soft"]),
			"stake": int(hand["stake"]), "doubled": bool(hand["doubled"]), "done": bool(hand["done"]),
			"result": String(hand["result"])})
	var dealer_cards: Array = []
	var visible: Array = []
	for i in _dealer.size():
		var shown := i != 1 or not _hole_hidden
		dealer_cards.append(_card_view(_dealer[i], shown))
		if shown:
			visible.append(_dealer[i])
	var vt := total_of(visible)
	return {
		"hands": hands,
		"active_hand": _active if state == PLAYING else -1,
		"dealer": {"cards": dealer_cards, "total": int(vt["total"]), "soft": bool(vt["soft"]),
			"hidden": _hole_hidden and _dealer.size() >= 2},
		"shoe": _shoe.remaining() if _shoe != null else 0,
	}
