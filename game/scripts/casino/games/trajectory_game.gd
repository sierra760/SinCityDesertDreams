# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Trajectory: a rising multiplier that burns out at a hidden point.
##
## On launch a burn-out multiplier M is drawn and kept hidden. The display
## climbs as exp(rate x seconds); cashing out at m < M returns floor(stake x m),
## reaching M first loses the stake. Multipliers are kept to hundredths.
##
## Spot: `stake`. Actions: `launch` (commits; optional {auto: float} cash-out
## target), then `advance` {multiplier} as the display climbs (settles with a
## crash once it reaches M) and `cash_out` {multiplier}. Reported multipliers
## must be finite, at least 1.00 and never fall. Events: `launch` {auto},
## `cash_out` {multiplier, seconds}, `crash` {multiplier, seconds}, `settle`.
class_name TrajectoryGame
extends CasinoGame

const STAKE := &"stake"
const LAUNCH := &"launch"
const ADVANCE := &"advance"
const CASH_OUT := &"cash_out"
const HISTORY := 12
const MIN_TARGET := 1.01

var _burn_out := 1.0
var _current := 1.0
var _auto := 0.0
var _crashed := false
var _history: Array[float] = []


func _init() -> void:
	kind = &"trajectory"


func commit_action() -> StringName:
	return LAUNCH


func commit_label() -> String:
	return "Launch"


func spots() -> Array[Dictionary]:
	return [_spot(STAKE, "Stake", "Cash out before burn-out", "stake")]


## The displayed multiplier `seconds` after launch, to hundredths.
static func multiplier_at(seconds: float) -> float:
	return hundredths(exp(CasinoParams.TRAJECTORY_RATE * maxf(0.0, seconds)))


## Seconds after launch at which the display reaches `multiplier`.
static func seconds_for(multiplier: float) -> float:
	return log(maxf(1.0, multiplier)) / CasinoParams.TRAJECTORY_RATE


## A multiplier rounded down to hundredths.
static func hundredths(value: float) -> float:
	return floorf(value * 100.0 + 0.000001) / 100.0


## The burn-out multiplier for a uniform draw `u` in [0, 1) when the engine
## does not fail on the pad.
static func burn_out_for(u: float) -> float:
	var raw := floorf(100.0 * CasinoParams.TRAJECTORY_EDGE / maxf(0.000001, 1.0 - u)) / 100.0
	return clampf(raw, 1.0, CasinoParams.TRAJECTORY_MAX_MULTIPLIER)


## Whole dollars returned for cashing `stake` out at `multiplier`.
static func payout(stake: int, multiplier: float) -> int:
	@warning_ignore("integer_division")
	return stake * roundi(hundredths(multiplier) * 100.0) / 100


## Tests only: the next launches burn out at these multipliers.
func rig(values: Array) -> void:
	_rigged = values.duplicate()


func _on_round_start() -> void:
	_burn_out = 1.0
	_current = 1.0
	_auto = 0.0
	_crashed = false


func _playing_actions() -> Array[Dictionary]:
	return [_action(CASH_OUT, "Cash out", true, true), _action(ADVANCE, "Climb", true, false)]


func _act(action: StringName, payload: Dictionary) -> Dictionary:
	match action:
		LAUNCH:
			var auto := 0.0
			if payload.has("auto"):
				auto = float(payload["auto"])
				if not is_finite(auto) or auto < MIN_TARGET or auto > CasinoParams.TRAJECTORY_MAX_MULTIPLIER:
					return _refuse(CasinoLines.BAD_TARGET)
				auto = hundredths(auto)
			_launch(auto)
			return _accept()
		ADVANCE, CASH_OUT:
			var m := float(payload.get("multiplier", -1.0))
			if not is_finite(m) or m < 1.0 or m > CasinoParams.TRAJECTORY_MAX_MULTIPLIER:
				return _refuse(CasinoLines.BAD_MULTIPLIER)
			m = hundredths(m)
			if m < _current:
				return _refuse(CasinoLines.MULTIPLIER_FALLS)
			if m >= _burn_out:
				_crash()
				return {"ok": true, "reason": "", "stake": 0, "crashed": true}
			_current = m
			if action == CASH_OUT:
				_cash_out(m)
			return {"ok": true, "reason": "", "stake": 0, "crashed": false}
	return _refuse(CasinoLines.ACTION_UNAVAILABLE)


func _launch(auto: float) -> void:
	state = PLAYING
	_auto = auto
	if not _rigged.is_empty():
		_burn_out = clampf(hundredths(float(_rigged.pop_front())), 1.0, CasinoParams.TRAJECTORY_MAX_MULTIPLIER)
	elif _rng.below(CasinoParams.TRAJECTORY_FAIL_ONE_IN) == 0:
		_burn_out = 1.0
	else:
		_burn_out = burn_out_for(_rng.randf())
	_emit({"kind": "launch", "auto": auto})
	if _burn_out <= 1.0:
		_crash()
	elif auto > 0.0:
		if auto < _burn_out:
			_current = auto
			_cash_out(auto)
		else:
			_crash()


func _cash_out(m: float) -> void:
	var returned := payout(int(_bets.get(STAKE, 0)), m)
	_emit({"kind": "cash_out", "multiplier": m, "seconds": seconds_for(m)})
	_record()
	_settle(returned, "Cashed out at %.2fx." % m, {"multiplier": m, "burn_out": _burn_out}, _plain_reaction(returned))


func _crash() -> void:
	_crashed = true
	_current = _burn_out
	_emit({"kind": "crash", "multiplier": _burn_out, "seconds": seconds_for(_burn_out)})
	_record()
	var summary := "Engine failure on the pad." if _burn_out <= 1.0 else "Burn-out at %.2fx." % _burn_out
	_settle(0, summary, {"multiplier": 0.0, "burn_out": _burn_out}, "crash")


func _record() -> void:
	_history.push_front(_burn_out)
	while _history.size() > HISTORY:
		_history.pop_back()


func _view() -> Dictionary:
	return {
		"multiplier": _current,
		"auto": _auto,
		"crashed": _crashed,
		"burn_out": _burn_out if state == SETTLED else 0.0,
		"history": _history.duplicate(),
		"rate": CasinoParams.TRAJECTORY_RATE,
	}
