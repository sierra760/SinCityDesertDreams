# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Random source for casino games.
##
## Separate from the simulation's random stream so that play never changes
## what the city does next. Tests pass a seed; the overlay passes none.
class_name CasinoRng
extends RefCounted

var _rng := RandomNumberGenerator.new()


## A negative seed draws a fresh one; any other value repeats exactly.
func _init(seed_value: int = -1) -> void:
	_rng.seed = randi() if seed_value < 0 else seed_value


## Integer in [0, n). Returns 0 when n is 1 or less.
func below(n: int) -> int:
	if n <= 1:
		return 0
	return _rng.randi_range(0, n - 1)


## Float in [0, 1).
func randf() -> float:
	var value := _rng.randf()
	return value if value < 1.0 else 0.0


## Shuffle `items` in place (Fisher–Yates, drawing with below()).
func shuffle(items: Array) -> void:
	var i := items.size() - 1
	while i > 0:
		var j := below(i + 1)
		var held: Variant = items[i]
		items[i] = items[j]
		items[j] = held
		i -= 1


func state() -> int:
	return _rng.state


func set_state(value: int) -> void:
	_rng.state = value
