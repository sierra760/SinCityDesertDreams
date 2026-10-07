# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const Cheats := preload("res://scripts/core/cheat_codes.gd")

var sim: Simulation

func before_each() -> void:
	sim = make_simulation(flat_city(), 7)

func after_each() -> void:
	sim.free()

func redeem(code: String) -> Dictionary:
	return sim.redeem_cheat(code)

func test_highroller_unlocks_without_building_or_changing_time() -> void:
	var before := SaveFormat.encode_city(sim.city).duplicate(true)
	var day := sim.city.day
	var result := redeem("  HiGhRoLlEr  ")
	check(bool(result.get("ok", false)))
	check_eq(sim.city.funds, 520000)
	check_eq(sim.city.day, day)
	for kind in Tools.all():
		check(Tools.is_available(kind, sim.city, sim.stats), "all tools unlocked: %s" % kind)
	check_eq(sim.stats.population, 0)
	var after := SaveFormat.encode_city(sim.city).duplicate(true)
	after["funds"] = before["funds"]
	check_eq(after, before, "cheat offers buildings, never stamps them onto the city")

func test_repeat_highroller_preserves_standing_rewards() -> void:
	redeem("highroller")
	var builder := Builder.new(sim.city, sim.stats, sim)
	var placed := builder.apply(Tools.Kind.REWARD_MONUMENT, Vector2i(10,10))
	check(bool(placed.get("ok", false)))
	sim.networks_changed()
	redeem("highroller")
	check_eq(sim.city.funds, 1020000)
	check(not Tools.is_available(Tools.Kind.REWARD_MONUMENT,sim.city,sim.stats), "no duplicate standing gifts")

func test_marker_is_real_debt_with_limit_and_repayment() -> void:
	var rng := sim.rng.state()
	var result := redeem("marker")
	check(bool(result.get("ok", false)))
	check(String(result.get("body", "")).contains("$25,000"))
	check_eq(sim.city.funds, 45000)
	check_eq(sim.stats.bonds.size(), 1)
	if sim.stats.bonds.size() == 1:
		check_eq(sim.stats.bonds[0].rate, 20)
		check_eq(sim.stats.bonds[0].principal, 25000)
		var budget := sim.get_system(&"budget") as BudgetSystem
		check_eq(budget.estimated_ledger()[&"bond_interest"], 5000)
		check(budget.repay_bond())
		check_eq(sim.city.funds, 20000)
	for i in BudgetParams.MAX_BONDS: redeem("MARKER")
	var funds := sim.city.funds
	check(not bool(redeem("marker").get("ok", false)))
	check_eq(sim.city.funds, funds)
	check_eq(sim.rng.state(), rng, "a marker does not roll simulation RNG")

func test_gags_unknown_and_missing_city_do_not_mutate() -> void:
	var before := sim.snapshot().duplicate(true)
	var rng := sim.rng.state()
	for code in ["chapel", "Chapel"]:
		var result := redeem(code)
		check(bool(result.get("ok", false)))
		check(not String(result.get("body", "")).is_empty())
	check(not bool(redeem("highroller!!!").get("ok", false)))
	check_eq(sim.snapshot(), before)
	check_eq(sim.rng.state(), rng)
	var empty := Simulation.new()
	if empty.has_method("redeem_cheat"):
		check(not bool(empty.call("redeem_cheat", "highroller").get("ok", false)))
	empty.free()

func test_retired_codes_are_unknown() -> void:
	var before := sim.snapshot().duplicate(true)
	var rng := sim.rng.state()
	for code in ["cassino", "jackpot", "loanshark", "nerdalert", "squidproquo", "marquee", "cass", "fund", "joke", "vers"]:
		check(not bool(redeem(code).get("ok", false)), "%s is not a code" % code)
	check_eq(sim.snapshot(), before)
	check_eq(sim.rng.state(), rng)

func test_cheat_effects_survive_native_roundtrip() -> void:
	redeem("highroller")
	redeem("marker")
	var path := "user://test_cheat_codes.sc2d"
	check_eq(SaveFormat.save(path,sim.city,sim.snapshot()), OK)
	var loaded := SaveFormat.load(path)
	check(bool(loaded.get("ok",false)))
	if bool(loaded.get("ok",false)):
		var other := make_simulation(loaded.city, 8)
		other.restore(loaded.snapshot)
		check_eq(other.city.funds, sim.city.funds)
		check_eq(other.stats.bonds.size(), sim.stats.bonds.size())
		for index in sim.stats.bonds.size():
			for key in ["principal", "rate", "age", "issued_year"]:
				check_eq(int(other.stats.bonds[index][key]), int(sim.stats.bonds[index][key]))
		for kind in Tools.all(): check(Tools.is_available(kind,other.city,other.stats))
		other.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## Point the simulation RNG at a state whose next DOUBLEDOWN roll has `outcome`.
func set_bet_roll(outcome: StringName) -> void:
	for seed_value in 1000:
		var probe := SimRng.new(seed_value)
		var state := probe.state()
		if Cheats.bet_outcome(probe.below(100)) == outcome:
			sim.rng.set_state(state)
			return
	check(false, "fixture finds a %s roll" % outcome)

func test_bet_outcomes_follow_the_house_odds() -> void:
	var counts := {&"fire": 0, &"win": 0, &"lose": 0}
	for roll in 100: counts[Cheats.bet_outcome(roll)] += 1
	check_eq(counts, {&"fire": 3, &"win": 47, &"lose": 50})

func test_stake_is_a_tenth_within_table_limits() -> void:
	check_eq(Cheats.bet_stake(20000), 2000)
	check_eq(Cheats.bet_stake(500), 100, "table minimum")
	check_eq(Cheats.bet_stake(100), 100)
	check_eq(Cheats.bet_stake(99), 0, "cannot cover the minimum")
	check_eq(Cheats.bet_stake(-5000), 0, "no betting from debt")
	check_eq(Cheats.bet_stake(10000000), 25000, "table maximum")

func test_doubledown_win_doubles_the_stake() -> void:
	set_bet_roll(&"win")
	var result := redeem("DoubleDown")
	check(bool(result.get("ok", false)))
	check_eq(sim.city.funds, 22000)
	check(String(result.get("body", "")).contains("$2,000"))
	check_eq(sim.city.day, 0)

func test_doubledown_loss_keeps_the_stake() -> void:
	set_bet_roll(&"lose")
	check(bool(redeem("doubledown").get("ok", false)))
	check_eq(sim.city.funds, 18000)

func test_doubledown_respects_the_table_maximum() -> void:
	sim.city.funds = 1000000
	set_bet_roll(&"lose")
	redeem("doubledown")
	check_eq(sim.city.funds, 975000)

func test_doubledown_below_minimum_is_refused_without_rolling() -> void:
	sim.city.funds = 99
	var rng := sim.rng.state()
	check(not bool(redeem("doubledown").get("ok", false)))
	check_eq(sim.city.funds, 99)
	check_eq(sim.rng.state(), rng)

func test_doubledown_fire_roll_starts_real_firestorm_without_cash() -> void:
	for y in range(40,50):
		for x in range(40,50): sim.city.building.put(x,y,Buildings.TREES_7)
	sim.city.stamp_building(44,44,Buildings.RES_2X2_FIRST,Zones.RES_HIGH)
	set_bet_roll(&"fire")
	var funds := sim.city.funds
	check(bool(redeem("doubledown").get("ok", false)))
	var disasters := sim.get_system(&"disasters")
	check(not disasters.call("fires").is_empty())
	check_eq(sim.city.funds, funds)
	check_eq(sim.city.day, 0)

func test_doubledown_fire_roll_without_fuel_returns_the_stake() -> void:
	set_bet_roll(&"fire")
	check(not bool(redeem("doubledown").get("ok", false)))
	check_eq(sim.city.funds, 20000)
	check(sim.get_system(&"disasters").call("fires").is_empty())

func test_highroller_cannot_reopen_declined_or_existing_military() -> void:
	var rewards := sim.get_system(&"rewards")
	sim.stats.rewards_offered[&"military_base"] = true
	rewards.load({"military": {"kind": "army", "answered": true, "accepted": false}})
	var state := sim.rng.state()
	redeem("highroller")
	check_eq(sim.rng.state(), state, "known base does not reroll sites")
	check(not rewards.call("military_offer").pending)
	sim.city.zone.put(80,80,Zones.make(Zones.MILITARY))
	sim.networks_changed(Rect2i(80,80,1,1))
	redeem("highroller")
	check(sim.stats.rewards_built[&"military_base"])
	check(not Tools.is_available(Tools.Kind.REWARD_MILITARY_BASE,sim.city,sim.stats))
	check(not rewards.call("military_offer").pending)
