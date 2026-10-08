# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"


func test_same_seed_repeats() -> void:
	var a := CasinoRng.new(42)
	var b := CasinoRng.new(42)
	for _i in 50:
		check_eq(a.below(1000), b.below(1000))
	check_eq(a.randf(), b.randf())


func test_below_bounds() -> void:
	var rng := CasinoRng.new(1)
	var seen := {}
	for _i in 600:
		var v := rng.below(6)
		check_between(v, 0, 5)
		seen[v] = true
	check_eq(seen.size(), 6, "every face appears")
	check_eq(rng.below(1), 0)
	check_eq(rng.below(0), 0)
	check_eq(rng.below(-3), 0)
	for _i in 200:
		var f := rng.randf()
		check(f >= 0.0 and f < 1.0, "randf in [0, 1)")


func test_shuffle_is_a_permutation_and_repeats() -> void:
	var items: Array = []
	for i in 52:
		items.append(i)
	var a := items.duplicate()
	var b := items.duplicate()
	CasinoRng.new(9).shuffle(a)
	CasinoRng.new(9).shuffle(b)
	check_eq(a, b, "same seed, same order")
	check_ne(a, items, "the order changed")
	var sorted := a.duplicate()
	sorted.sort()
	check_eq(sorted, items, "nothing lost or duplicated")


func test_state_round_trip() -> void:
	var rng := CasinoRng.new(5)
	rng.below(10)
	var saved := rng.state()
	var first := [rng.below(100), rng.below(100), rng.below(100)]
	rng.set_state(saved)
	check_eq([rng.below(100), rng.below(100), rng.below(100)], first)


func test_unseeded_instances_differ_and_leave_sim_rng_alone() -> void:
	var sim_rng := SimRng.new(3)
	var before := sim_rng.state()
	var draws := {}
	for _i in 8:
		draws[CasinoRng.new().below(1000000)] = true
	check_gt(draws.size(), 1, "fresh seeds")
	check_eq(sim_rng.state(), before)


func test_deck_composition_and_stacking() -> void:
	var deck := CasinoDeck.new(6, CasinoRng.new(2))
	check_eq(deck.size(), 312)
	var counts := {}
	for _i in 312:
		var c := deck.draw()
		var k := "%d/%d" % [int(c["rank"]), int(c["suit"])]
		counts[k] = int(counts.get(k, 0)) + 1
	check_eq(counts.size(), 52)
	for k in counts:
		check_eq(int(counts[k]), 6, k)
	check_eq(deck.remaining(), 0)
	deck.draw()
	check_eq(deck.remaining(), 311, "an exhausted shoe refills")
	deck.stack([CasinoDeck.card(1, 3), CasinoDeck.card(13, 0)])
	check(deck.is_stacked())
	check(not deck.reshuffle_below(52), "a stacked shoe is not reshuffled")
	check_eq(deck.draw(), {"rank": 1, "suit": 3})
	check_eq(deck.draw(), {"rank": 13, "suit": 0})
	check(not deck.is_stacked())
	check_eq(CasinoDeck.card_name({"rank": 12, "suit": 2}), "Q of hearts")
