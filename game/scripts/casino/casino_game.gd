# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Base class for a casino game: bets, rounds and the animation log.
##
## A round moves betting -> playing -> settled. Bets are placed on spots while
## betting; the game's committing action (deal, spin, pull, roll, turn,
## launch) closes betting. The caller debits the treasury by the `stake` that
## an accepted action reports, and credits `outcome().returned` once the game
## is settled. Game logic never touches the city.
##
## Results of `act()` are `{ok: bool, reason: String, stake: int}`; `stake` is
## the amount to debit now (the opening total for the committing action, the
## extra for a blackjack double or split, otherwise 0).
##
## `take_events()` drains an ordered log for the table view. Every entry has a
## String "kind"; the games document their own kinds. Every game emits
## `{"kind": "settle", "staked", "returned", "net", "reaction"}` last when a
## round settles, and `{"kind": "shuffle"}` when a shoe is reshuffled.
class_name CasinoGame
extends RefCounted

const BETTING := &"betting"
const PLAYING := &"playing"
const SETTLED := &"settled"

## Shared actions every game offers besides its own.
const CLEAR := &"clear"
const REBET := &"rebet"
const NEXT := &"next"

var kind: StringName = &""
var state: StringName = BETTING
var limits: Dictionary = {"minimum": 0, "maximum": 0}

var _rng: CasinoRng
var _bets: Dictionary = {}
var _last_bets: Dictionary = {}
var _extra_stake: int = 0
var _events: Array[Dictionary] = []
var _outcome: Dictionary = {}
var _rigged: Array = []


## Start a fresh table: new shoe or wheel state, betting open.
func begin(rng: CasinoRng, table_limits: Dictionary) -> void:
	_rng = rng if rng != null else CasinoRng.new()
	limits = _clean_limits(table_limits)
	_events.clear()
	_last_bets = {}
	_reset_table()
	_start_round()


## Refresh the limits between rounds (the treasury may have changed).
## Ignored while a round is under way.
func set_limits(table_limits: Dictionary) -> void:
	if state == PLAYING:
		return
	limits = _clean_limits(table_limits)


## The bet spots of this table: [{id: StringName, label, odds, group}].
func spots() -> Array[Dictionary]:
	return []


## The action that closes betting and starts the round.
func commit_action() -> StringName:
	return &""


func commit_label() -> String:
	return "Play"


## Legal actions now: [{id: StringName, label, enabled, primary}].
func actions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match state:
		BETTING:
			var staked := total_staked()
			out.append(_action(commit_action(), commit_label(),
				staked > 0 and staked >= int(limits["minimum"]) and staked <= int(limits["maximum"]), true))
			out.append(_action(REBET, "Same bet", _bets.is_empty() and _rebet_fits(), false))
			out.append(_action(CLEAR, "Clear bets", not _bets.is_empty(), false))
		PLAYING:
			out.append_array(_playing_actions())
		SETTLED:
			out.append(_action(NEXT, "Next round", true, true))
			# "Same bet" from a settled table starts the next round with the
			# last round's bets on the felt.
			out.append(_action(REBET, "Same bet", _rebet_fits(), false))
	return out


## Add `amount` to the bet on `spot`. Returns {ok, reason}.
func place_bet(spot: StringName, amount: int) -> Dictionary:
	if state != BETTING:
		return _refuse(CasinoLines.BETS_CLOSED)
	if not _has_spot(spot):
		return _refuse(CasinoLines.UNKNOWN_SPOT)
	if amount <= 0:
		return _refuse(CasinoLines.BET_TOO_SMALL)
	if total_staked() + amount > int(limits["maximum"]):
		return _refuse(CasinoLines.OVER_MAXIMUM)
	var reason := _spot_reason(spot, int(_bets.get(spot, 0)) + amount)
	if not reason.is_empty():
		return _refuse(reason)
	_bets[spot] = int(_bets.get(spot, 0)) + amount
	return {"ok": true, "reason": ""}


func remove_bet(spot: StringName) -> void:
	if state == BETTING:
		_bets.erase(spot)


func clear_bets() -> void:
	if state == BETTING:
		_bets.clear()


## Spot -> amount for the current round.
func bets() -> Dictionary:
	return _bets.duplicate()


## The previous round's committed bets, for "Same bet".
func last_bets() -> Dictionary:
	return _last_bets.duplicate()


## Everything at risk this round, including doubles and splits.
func total_staked() -> int:
	var total := _extra_stake
	for spot in _bets:
		total += int(_bets[spot])
	return total


## Perform an action. Returns {ok, reason, stake}.
func act(action: StringName, payload: Dictionary = {}) -> Dictionary:
	var legal := _find_action(action)
	if legal.is_empty() or not bool(legal["enabled"]):
		if state == BETTING and action == commit_action():
			return _refuse(_commit_reason())
		return _refuse(CasinoLines.ACTION_UNAVAILABLE)
	match action:
		CLEAR:
			clear_bets()
			return _accept()
		REBET:
			if state == SETTLED:
				next_round()
			_bets = _last_bets.duplicate()
			return _accept()
		NEXT:
			next_round()
			return _accept()
	var committing := state == BETTING and action == commit_action()
	var staked := total_staked()
	var result := _act(action, payload)
	if not result.has("reason"):
		result["reason"] = ""
	if not result.has("stake"):
		result["stake"] = 0
	if committing and bool(result.get("ok", false)):
		result["stake"] = staked
		_last_bets = _bets.duplicate()
	return result


## Drain the animation log.
func take_events() -> Array[Dictionary]:
	var out := _events.duplicate()
	_events.clear()
	return out


## JSON-safe drawing state: kind, state, bets, staked, limits, outcome, plus
## the game's own keys.
func view_state() -> Dictionary:
	var named := {}
	for spot in _bets:
		named[String(spot)] = int(_bets[spot])
	var out := {
		"kind": String(kind),
		"state": String(state),
		"bets": named,
		"staked": total_staked(),
		"limits": limits.duplicate(),
		"outcome": _outcome.duplicate(true),
	}
	out.merge(_view(), true)
	return out


## Valid once settled: {staked, returned, net, summary, detail, reaction}.
## `reaction` is one of win, lose, push, blackjack, bust, jackpot, crash.
func outcome() -> Dictionary:
	return _outcome.duplicate(true)


## Settled -> betting, keeping the shoe and the wheel history.
func next_round() -> void:
	if state == SETTLED:
		_start_round()


## Tests only: the next random draws come from `values` instead of the rng.
## Card games read the values as cards and stack the shoe with them.
func rig(values: Array) -> void:
	_rigged = values.duplicate()


# ── For subclasses ───────────────────────────────────────────────────────

func _reset_table() -> void:
	pass


func _on_round_start() -> void:
	pass


func _playing_actions() -> Array[Dictionary]:
	return []


func _act(_action: StringName, _payload: Dictionary) -> Dictionary:
	return _refuse(CasinoLines.ACTION_UNAVAILABLE)


func _view() -> Dictionary:
	return {}


## A reason the spot cannot hold `amount`, or "" when it can.
func _spot_reason(_spot: StringName, _amount: int) -> String:
	return ""


func _draw_below(n: int) -> int:
	if not _rigged.is_empty():
		return clampi(int(_rigged.pop_front()), 0, maxi(0, n - 1))
	return _rng.below(n)


func _emit(event: Dictionary) -> void:
	_events.append(event)


## Close the round with `returned` going back to the treasury.
func _settle(returned: int, summary: String, detail: Dictionary, reaction: String) -> void:
	var staked := total_staked()
	var paid := maxi(0, returned)
	state = SETTLED
	_outcome = {
		"staked": staked,
		"returned": paid,
		"net": paid - staked,
		"summary": summary,
		"detail": detail,
		"reaction": reaction,
	}
	_emit({"kind": "settle", "staked": staked, "returned": paid, "net": paid - staked, "reaction": reaction})


## win, lose or push from a round's totals.
func _plain_reaction(returned: int) -> String:
	var staked := total_staked()
	if returned > staked:
		return "win"
	if returned < staked:
		return "lose"
	return "push"


static func _action(id: StringName, label: String, enabled: bool, primary: bool) -> Dictionary:
	return {"id": id, "label": label, "enabled": enabled, "primary": primary}


static func _spot(id: StringName, label: String, odds: String, group: String) -> Dictionary:
	return {"id": id, "label": label, "odds": odds, "group": group}


static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "stake": 0}


static func _accept(stake: int = 0) -> Dictionary:
	return {"ok": true, "reason": "", "stake": stake}


static func _card_view(c: Dictionary, face_up: bool = true) -> Dictionary:
	if not face_up:
		return {"rank": 0, "suit": 0, "face_up": false}
	return {"rank": int(c["rank"]), "suit": int(c["suit"]), "face_up": true}


# ── Internals ────────────────────────────────────────────────────────────

func _start_round() -> void:
	state = BETTING
	_bets = {}
	_extra_stake = 0
	_outcome = {}
	_on_round_start()


func _has_spot(spot: StringName) -> bool:
	for s in spots():
		if s["id"] == spot:
			return true
	return false


func _find_action(action: StringName) -> Dictionary:
	for a in actions():
		if a["id"] == action:
			return a
	return {}


func _commit_reason() -> String:
	var staked := total_staked()
	if staked <= 0:
		return CasinoLines.NO_BETS
	if staked < int(limits["minimum"]):
		return CasinoLines.below_minimum(int(limits["minimum"]))
	if staked > int(limits["maximum"]):
		return CasinoLines.OVER_MAXIMUM
	return CasinoLines.ACTION_UNAVAILABLE


func _rebet_fits() -> bool:
	if _last_bets.is_empty():
		return false
	var total := 0
	for spot in _last_bets:
		total += int(_last_bets[spot])
	return total <= int(limits["maximum"]) and total >= int(limits["minimum"])


static func _clean_limits(table_limits: Dictionary) -> Dictionary:
	var minimum := maxi(0, int(table_limits.get("minimum", 0)))
	var maximum := maxi(0, int(table_limits.get("maximum", 0)))
	return {"minimum": minimum, "maximum": maximum}
