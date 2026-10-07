# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Deterministic random source for the simulation.
##
## Thin wrapper over RandomNumberGenerator so the seed and state can be saved
## and every system draws from one stream in a fixed order.
class_name SimRng
extends RefCounted

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


## Saved seeds are raw signed64-bit data, including negative values. Only the
## new-city constructor interprets a negative seed as a randomize request.
static func from_saved_seed(saved_seed: int) -> SimRng:
	var restored := SimRng.new(0)
	restored._rng.seed = saved_seed
	return restored


func seed_value() -> int:
	return _rng.seed


func state() -> int:
	return _rng.state


func set_state(value: int) -> void:
	_rng.state = value


## Integer in [0, n).
func below(n: int) -> int:
	if n <= 1:
		return 0
	return _rng.randi_range(0, n - 1)


## Integer in [lo, hi] inclusive.
func range_int(lo: int, hi: int) -> int:
	return _rng.randi_range(lo, hi)


func chance(numerator: int, denominator: int) -> bool:
	return below(denominator) < numerator


func unit() -> float:
	return _rng.randf()


func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[below(items.size())]
