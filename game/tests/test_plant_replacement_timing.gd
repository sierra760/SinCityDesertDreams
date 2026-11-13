# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## With disasters off, a worn-out plant is replaced from the treasury as it
## stands after the year's books are settled, not before the income arrives.
extends "res://tests/test_case.gd"

const PLANT := Vector2i(10, 10)


## A city on the last day of its year with a plant at the end of its life,
## `funds` in the treasury and `income` accrued but not yet settled.
func _year_end(funds: int, income: int) -> Simulation:
	var c := flat_city(funds)
	c.stamp_building(PLANT.x, PLANT.y, Buildings.COAL_PLANT)
	c.day = GameClock.DAYS_PER_YEAR - 1
	var sim := make_simulation(c)
	sim.stats.disasters_enabled = false
	sim.city.facility(PLANT)["age_years"] = UtilityParams.PLANT_LIFETIME_YEARS
	var budget := sim.get_system(&"budget")
	var accrued: Dictionary = budget.get("_twelfths")
	accrued[&"taxes_residential"] = income * int(budget.get("TWELFTH_CENTS_PER_DOLLAR"))
	return sim


func test_income_settled_at_year_end_pays_for_the_replacement() -> void:
	var cost := Buildings.cost(Buildings.COAL_PLANT)
	var sim := _year_end(cost - 500, 2000)
	check(sim.clock.is_year_end(), "fixture is at the year end")
	sim.advance_day()
	check_eq(sim.city.building_at(PLANT.x, PLANT.y), Buildings.COAL_PLANT, "the plant is replaced, not lost")
	check_eq(int(sim.city.facility(PLANT).get("age_years", -1)), 0)
	check_eq(sim.city.funds, cost - 500 + 2000 - cost, "income settled, then the replacement paid")
	sim.free()


func test_treasury_still_short_after_settlement_loses_the_plant() -> void:
	var cost := Buildings.cost(Buildings.COAL_PLANT)
	var sim := _year_end(cost - 500, 100)
	sim.advance_day()
	check(Buildings.is_rubble(sim.city.building_at(PLANT.x, PLANT.y)), "no funds: retired")
	check_eq(sim.city.funds, cost - 500 + 100)
	sim.free()
