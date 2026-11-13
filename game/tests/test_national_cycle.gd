# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The national economy visits every phase, recession and boom included, and
## each phase lasts for years.
extends "res://tests/test_case.gd"

const SEEDS := 12
const YEARS := 200


func _census(founded: int) -> Dictionary:
	var months := [0, 0, 0, 0]
	var changes := 0
	var seen_by_seed := 0
	for seed_value in SEEDS:
		var c := City.new()
		c.founded_year = founded
		var ctx := make_context(c, seed_value + 1)
		ctx.clock.founded_year = founded
		var eco := EconomySystem.new()
		ctx.systems = {&"economy": eco}
		eco.setup(ctx)
		var last := ctx.stats.economy_phase
		var seen := {}
		for _m in 12 * YEARS:
			eco.call("_advance_nation", ctx)
			var phase := ctx.stats.economy_phase
			months[phase] += 1
			seen[phase] = true
			if phase != last:
				changes += 1
				last = phase
			ctx.events.clear()
		if seen.size() == 4: seen_by_seed += 1
		check_gt(eco.national_product(), 0, "the product never dies out")
		ctx.systems.clear()
	return {"months": months, "changes": changes, "all_four": seen_by_seed}


func _check_era(founded: int) -> void:
	var census := _census(founded)
	var total := float(SEEDS * 12 * YEARS)
	var months: Array = census.months
	var label := "founded %d %s" % [founded, str(months)]
	for phase in 4:
		var share: float = 100.0 * int(months[phase]) / total
		check_gt(share, 4.0, "%s: %s is a real part of the cycle" % [label, EconomySystem.phase_name(phase)])
		check_lt(share, 60.0, "%s: %s does not crowd out the others" % [label, EconomySystem.phase_name(phase)])
	check_gt(int(months[1]) + int(months[2]), int(months[0]) + int(months[3]), "%s: the middle phases are the usual ones" % label)
	check_eq(census.all_four, SEEDS, "%s: every city sees all four phases in %d years" % [label, YEARS])
	var mean_spell: float = total / maxi(1, int(census.changes))
	check_between(mean_spell, 36.0, 144.0, "%s: a phase lasts years, not months or generations" % label)


func test_early_nation_cycles_through_every_phase() -> void:
	_check_era(1900)


func test_late_nation_cycles_through_every_phase() -> void:
	_check_era(2050)
