# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A shoe of one or more 52-card decks.
##
## A card is `{"rank": 1..13, "suit": 0..3}`: 1 is the ace, 11 the jack, 12 the
## queen, 13 the king; suits are clubs, diamonds, hearts, spades in that order.
## Cards are drawn from the front. A stacked shoe (tests) deals exactly the
## cards given and is never reshuffled by the games until it runs out.
class_name CasinoDeck
extends RefCounted

const SUIT_NAMES: Array[String] = ["clubs", "diamonds", "hearts", "spades"]
const RANK_NAMES: Array[String] = ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

var decks: int = 1
var _rng: CasinoRng
var _cards: Array[Dictionary] = []
var _next: int = 0
var _stacked: bool = false


func _init(deck_count: int = 1, rng: CasinoRng = null) -> void:
	decks = maxi(1, deck_count)
	_rng = rng if rng != null else CasinoRng.new()
	reset()


## Every card back in the shoe, shuffled.
func reset() -> void:
	_cards.clear()
	for _d in decks:
		for suit in 4:
			for rank in range(1, 14):
				_cards.append(card(rank, suit))
	_rng.shuffle(_cards)
	_next = 0
	_stacked = false


## Replace the shoe with `cards`, dealt in the given order (tests only).
func stack(cards: Array) -> void:
	_cards.clear()
	for c in cards:
		var d: Dictionary = c
		_cards.append(card(int(d.get("rank", 1)), int(d.get("suit", 0))))
	_next = 0
	_stacked = true


## The next card. An exhausted shoe is refilled and reshuffled first.
func draw() -> Dictionary:
	if _next >= _cards.size():
		reset()
	var c: Dictionary = _cards[_next]
	_next += 1
	return c.duplicate()


func remaining() -> int:
	return _cards.size() - _next


func size() -> int:
	return _cards.size()


func is_stacked() -> bool:
	return _stacked and remaining() > 0


## Reshuffle when fewer than `threshold` cards remain, unless stacked.
## Returns true when it reshuffled.
func reshuffle_below(threshold: int) -> bool:
	if is_stacked() or remaining() >= threshold:
		return false
	reset()
	return true


static func card(rank: int, suit: int) -> Dictionary:
	return {"rank": clampi(rank, 1, 13), "suit": clampi(suit, 0, 3)}


## A readable card name, for example "A of spades".
static func card_name(c: Dictionary) -> String:
	var rank := int(c.get("rank", 0))
	var suit := int(c.get("suit", 0))
	if rank < 1 or rank > 13:
		return "hidden card"
	return "%s of %s" % [RANK_NAMES[rank], SUIT_NAMES[suit]]


static func is_red(c: Dictionary) -> bool:
	var suit := int(c.get("suit", 0))
	return suit == 1 or suit == 2
