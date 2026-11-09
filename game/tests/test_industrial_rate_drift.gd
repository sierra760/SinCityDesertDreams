# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The industrial rate is the share-weighted mean of the sector rates, so it
## moves as shares move. Only a rate the player set is a tax change.
extends "res://tests/test_case.gd"


func make_ctx() -> SimContext:
	var c := flat_city(100000)
	c.founded_year = 1950
	for i in 8:
		c.stamp_building(10 + i * 3, 10, Buildings.IND_3X3_FIRST, Zones.IND_HIGH)
	for i in 20:
		c.stamp_building(10 + i, 20, Buildings.IND_1X1_FIRST, Zones.IND_LOW)
	var ctx := make_context(c, 11)
	ctx.clock.founded_year = c.founded_year
	ctx.clock.day = c.day
	var eco := EconomySystem.new()
	var budget := BudgetSystem.new()
	ctx.systems = {&"economy": eco, &"budget": budget}
	eco.setup(ctx)
	budget.setup(ctx)
	return ctx


## One month of the two systems in schedule order; returns its tax stories.
func month(ctx: SimContext) -> Array:
	ctx.events.clear()
	(ctx.system(&"economy") as EconomySystem).monthly(ctx)
	(ctx.system(&"budget") as BudgetSystem).monthly(ctx)
	ctx.clock.day += GameClock.DAYS_PER_MONTH
	return ctx.events.news.filter(func(n: Dictionary) -> bool: return n["kind"] == &"tax_change")


## New factories open. Heavily taxed sectors take few of them, so their
## share of the city's industry falls.
func grow(ctx: SimContext) -> void:
	for row in 4:
		for i in 30:
			ctx.city.stamp_building(10 + i * 3, 30 + row * 4, Buildings.IND_3X3_FIRST, Zones.IND_HIGH)


## The two biggest sectors pay 20%, the rest nothing.
func uneven_rates(ctx: SimContext) -> void:
	var eco := ctx.system(&"economy") as EconomySystem
	month(ctx)
	var taxes := ctx.stats.sector_taxes
	var shares := ctx.stats.sector_shares
	var top := 0
	for i in shares.size():
		if shares[i] > shares[top]:
			top = i
	var second := 1 if top == 0 else 0
	for i in shares.size():
		if i != top and shares[i] > shares[second]:
			second = i
	for i in taxes.size():
		taxes[i] = 20 if i == top or i == second else 0
	ctx.stats.sector_taxes = taxes
	eco.sector_taxes_changed()


func test_share_drift_is_not_reported_as_a_tax_change() -> void:
	var ctx := make_ctx()
	uneven_rates(ctx)
	var set_rate := ctx.stats.tax_industrial
	var first := month(ctx)
	var player_stories := first.size()
	check_le_one(player_stories)
	var drifted := ctx.stats.tax_industrial != set_rate
	var stories := 0
	for m in 36:
		if m == 12: grow(ctx)
		var before := ctx.stats.tax_industrial
		var news := month(ctx)
		drifted = drifted or ctx.stats.tax_industrial != before
		stories += news.size()
	check(drifted, "the aggregate moved as the taxed sector lost its share")
	check_eq(stories, 0, "no tax story for a rate nobody set")
	check_eq(ctx.stats.tax_industrial, EconomySystem.aggregate_industrial_rate(ctx.stats), "the rate is still the aggregate")
	ctx.systems.clear()


func check_le_one(n: int) -> void:
	check(n <= 1, "at most one story for the player's own change")


func test_player_change_after_drift_is_still_reported() -> void:
	var ctx := make_ctx()
	uneven_rates(ctx)
	for m in 24:
		if m == 12: grow(ctx)
		month(ctx)
	var eco := ctx.system(&"economy") as EconomySystem
	var before := ctx.stats.tax_industrial
	ctx.stats.tax_industrial = before + 3
	eco.industrial_rate_written()
	var written := ctx.stats.tax_industrial
	check_ne(written, before)
	var news := month(ctx)
	check_eq(news.size(), 1, "the player's change is news")
	if news.size() == 1:
		check_eq(news[0]["args"]["family"], "industrial")
		check_eq(int(news[0]["args"]["previous"]), before, "from the rate in force, drift included")
	check_eq(month(ctx).size(), 0, "once")
	ctx.systems.clear()


func test_drift_between_the_two_passes_survives_a_save() -> void:
	var ctx := make_ctx()
	uneven_rates(ctx)
	month(ctx)
	var eco := ctx.system(&"economy") as EconomySystem
	var budget := ctx.system(&"budget") as BudgetSystem
	# Find a month whose economy pass moves the rate, and reload before the budget pass.
	var found := false
	for m in 24:
		if m == 6: grow(ctx)
		ctx.events.clear()
		var before := ctx.stats.tax_industrial
		eco.monthly(ctx)
		if ctx.stats.tax_industrial != before:
			found = true
			var saved: Dictionary = JSON.parse_string(JSON.stringify(eco.save()))
			check(SaveFormat._shape_problem(SaveFormat._shapes()["economy"], saved, "economy") == "", "the save passes validation")
			var twin := EconomySystem.new()
			ctx.systems[&"economy"] = twin
			twin.setup(ctx)
			twin.load(saved)
			budget.monthly(ctx)
			check(ctx.events.news.filter(func(n: Dictionary) -> bool: return n["kind"] == &"tax_change").is_empty(),
				"a reload between the passes does not turn drift into news")
			break
		budget.monthly(ctx)
		ctx.clock.day += GameClock.DAYS_PER_MONTH
	check(found, "a month with drift was found")
	ctx.systems.clear()
