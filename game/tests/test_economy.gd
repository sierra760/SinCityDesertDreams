# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"


## A context wired to only the economy system.
func make_ctx(c: City, seed_value: int = 11) -> SimContext:
	var ctx := make_context(c, seed_value)
	ctx.clock.founded_year = c.founded_year
	ctx.clock.day = c.day
	var eco := EconomySystem.new()
	ctx.systems = {&"economy": eco}
	eco.setup(ctx)
	return ctx


func eco_of(ctx: SimContext) -> EconomySystem:
	return ctx.system(&"economy") as EconomySystem


## Runs months, advancing the clock a month each time.
func run_months(ctx: SimContext, months: int) -> Array:
	var kinds := []
	for _m in months:
		ctx.events.clear()
		eco_of(ctx).monthly(ctx)
		for story in ctx.events.news:
			kinds.append(story["kind"])
		ctx.clock.day += GameClock.DAYS_PER_MONTH
	return kinds


func industrial_city(founded: int = 1950) -> City:
	var c := flat_city()
	c.founded_year = founded
	for i in 8:
		c.stamp_building(10 + i * 3, 10, Buildings.IND_3X3_FIRST, Zones.IND_HIGH)
	for i in 20:
		c.stamp_building(10 + i, 20, Buildings.IND_1X1_FIRST, Zones.IND_LOW)
	return c


func share_sum(stats: CityStats) -> float:
	var total := 0.0
	for s in stats.sector_shares:
		total += s
	return total


func test_phase_stays_in_range_and_shifts_over_the_years() -> void:
	var ctx := make_ctx(industrial_city())
	var shifts := 0
	for _m in 360:
		var kinds := run_months(ctx, 1)
		check_between(ctx.stats.economy_phase, 0, 3)
		shifts += kinds.count(&"economy_shift")
	check_gt(shifts, 0, "thirty years see at least one national shift")
	check_gt(eco_of(ctx).national_population(), 0)
	check_gt(eco_of(ctx).national_product(), 0)
	check_eq(EconomySystem.phase_name(0), "Recession")
	check_eq(EconomySystem.phase_name(3), "Boom")


func test_national_figures_never_grow_above_their_cap() -> void:
	var cap := EconomyParams.NATION_PRODUCT_CAP
	var above := cap + 1000000
	for rate: int in EconomyParams.PRODUCT_RATE:
		check(EconomySystem._grow(above, rate, cap) <= above, "rate %d shrinks above the cap" % rate)
	check_lt(EconomySystem._grow(above, -3, cap), above, "a negative rate still shrinks")
	check_gt(EconomySystem._grow(cap - 1000000, 6, cap), cap - 1000000)
	check_lt(EconomySystem._grow(cap - 1000000, -3, cap), cap - 1000000)

func test_sector_shares_sum_to_one() -> void:
	var ctx := make_ctx(industrial_city())
	for _m in 24:
		run_months(ctx, 1)
		check_eq(ctx.stats.sector_shares.size(), 11)
		check_lt(absf(share_sum(ctx.stats) - 1.0), 0.001)
	var empty := make_ctx(flat_city())
	run_months(empty, 1)
	check_lt(absf(share_sum(empty.stats) - 1.0), 0.001, "an empty city still shows a mix")
	var report := eco_of(ctx).sector_report()
	check_eq(report.size(), 11)
	check_eq(report[9]["name"], "Electronics")
	check(report[0]["heavy"])
	check(not report[10]["heavy"])
	var units := 0
	for row in report:
		units += int(row["units"])
	check_eq(units, 8 * 360 + 20 * 10, "every industrial unit belongs to a sector")


func test_sector_tax_moves_its_share() -> void:
	var electronics := 9
	var base := make_ctx(industrial_city(2000))
	run_months(base, 1)
	var cut := make_ctx(industrial_city(2000))
	cut.stats.sector_taxes[electronics] = 0
	run_months(cut, 1)
	var raised := make_ctx(industrial_city(2000))
	raised.stats.sector_taxes[electronics] = 20
	run_months(raised, 1)
	check_gt(cut.stats.sector_shares[electronics], base.stats.sector_shares[electronics], "a tax cut attracts the sector")
	check_lt(raised.stats.sector_shares[electronics], base.stats.sector_shares[electronics], "a tax rise repels it")
	check_between(eco_of(base).industrial_demand_modifier(), 0, 16)
	check_ge(eco_of(base).pollution_modifier(), -1)


func test_era_curve_favours_heavy_industry_early() -> void:
	var early := EconomyParams.era_demand(1900)
	var late := EconomyParams.era_demand(2100)
	check_gt(early[0], early[9], "steel outweighs electronics in 1900")
	check_gt(late[9], late[0], "electronics outweighs steel in 2100")
	check_gt(late[10], early[10], "tourism grows over time")
	var mid := EconomyParams.era_demand(1925)
	check_between(mid[9], early[9], EconomyParams.era_demand(1950)[9])


func test_inventions_unlock_in_order() -> void:
	var c := flat_city()
	c.founded_year = 1900
	var ctx := make_ctx(c)
	var inventions := ctx.stats.inventions
	for tech in EconomyParams.TECHNOLOGIES:
		check(inventions.has(tech), "%s has a year" % tech)
		var base := int(EconomyParams.TECHNOLOGIES[tech])
		check_between(int(inventions[tech]), base, base + EconomyParams.INVENTION_SPREAD - 1, String(tech))
	var eco := eco_of(ctx)
	check_lt(eco.available_year(&"arcology_comstock"), eco.available_year(&"arcology_junction"))
	check_lt(eco.available_year(&"arcology_junction"), eco.available_year(&"arcology_boulder"))
	check_lt(eco.available_year(&"arcology_boulder"), eco.available_year(&"arcology_orbit"))
	check_lt(eco.available_year(&"gas_plant"), eco.available_year(&"fusion_plant"))
	# The toolbar unlocks on exactly the rolled years the news announces.
	for tool in Tools.all():
		var tech := Tools.invention_key(tool)
		if tech == &"":
			continue
		check(EconomyParams.TECHNOLOGIES.has(tech), "%s gates on a rolled technology" % tech)
		check_eq(Tools.available_year(tool, ctx.stats), eco.available_year(tech), String(tech))
	check_eq(Tools.available_year(Tools.Kind.COAL_PLANT, ctx.stats), 0, "coal needs no invention")
	check(not Tools.is_available(Tools.Kind.FUSION_PLANT, c, ctx.stats))
	check(Tools.invention_key(Tools.Kind.WIND_PLANT) == &"wind_plant", "wind power is an invention")
	# Jump to the year 2000: every technology due by then is announced once.
	ctx.clock.day = 100 * GameClock.DAYS_PER_YEAR
	var kinds := run_months(ctx, 1)
	var due := 0
	for tech in inventions:
		if int(inventions[tech]) <= 2000:
			due += 1
	check_eq(kinds.count(&"invention"), due)
	check_gt(due, 5)
	kinds = run_months(ctx, 1)
	check_eq(kinds.count(&"invention"), 0, "each invention is reported once")
	# A city founded in 2050 starts with everything before that and no news.
	var late := flat_city()
	late.founded_year = 2050
	var late_ctx := make_ctx(late)
	check(Tools.is_available(Tools.Kind.NUCLEAR_PLANT, late, late_ctx.stats))
	kinds = run_months(late_ctx, 1)
	check_eq(kinds.count(&"invention"), 0)


func test_a_save_without_a_new_technology_gets_one_quietly() -> void:
	var c := flat_city()
	c.founded_year = 1900
	var ctx := make_ctx(c)
	ctx.stats.inventions.erase(&"wind_plant")
	ctx.clock.day = 120 * GameClock.DAYS_PER_YEAR
	var eco := eco_of(ctx)
	eco.load(eco.save())
	check(ctx.stats.inventions.has(&"wind_plant"), "the missing technology gets a year")
	check_lt(int(ctx.stats.inventions[&"wind_plant"]), 2021)
	ctx.events.clear()
	eco.monthly(ctx)
	for story in ctx.events.news:
		if story["kind"] == &"invention":
			check(story["args"]["technology"] != &"wind_plant", "a past invention is not announced as news")


func test_city_value_sums_buildings() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	for i in 10:
		c.stamp_building(20 + i, 10, Buildings.ROAD_FIRST)
	c.stamp_building(30, 30, Buildings.RES_3X3_FIRST, Zones.RES_HIGH)
	c.stamp_building(40, 30, Buildings.ABANDONED_2X2_FIRST, Zones.RES_HIGH)
	c.stamp_building(50, 30, Buildings.CITY_HALL)
	var ctx := make_ctx(c)
	run_months(ctx, 1)
	check_eq(ctx.stats.city_value, 4000 + 100 + 1500 + 100 + EconomyParams.LANDMARK_VALUE)


func test_save_and_load_round_trip() -> void:
	var ctx := make_ctx(industrial_city())
	run_months(ctx, 24)
	var saved := eco_of(ctx).save()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var restored := EconomySystem.new()
	restored.load(parsed)
	check_eq(restored.save(), saved)
	check_eq(restored.national_population(), eco_of(ctx).national_population())
	check_eq(restored.industrial_demand_modifier(), eco_of(ctx).industrial_demand_modifier())
	var twin := make_ctx(industrial_city())
	twin.systems[&"economy"] = restored
	restored.setup(twin)
	twin.stats.inventions = ctx.stats.inventions.duplicate()
	twin.stats.economy_phase = ctx.stats.economy_phase
	twin.stats.population = ctx.stats.population
	twin.clock.day = ctx.clock.day
	twin.rng.set_state(ctx.rng.state())
	run_months(ctx, 6)
	run_months(twin, 6)
	check_eq(twin.stats.economy_phase, ctx.stats.economy_phase)
	check_eq(twin.stats.sector_shares, ctx.stats.sector_shares)
	check_eq(restored.save(), eco_of(ctx).save())


func test_simulation_snapshot_restores_economy_state() -> void:
	var sim := make_simulation(industrial_city())
	sim.advance_days(GameClock.DAYS_PER_MONTH)
	var system := sim.get_system(&"economy")
	check(system != null, "economy system registered")
	if system == null:
		return
	check_between(sim.stats.economy_phase, 0, 3)
	check_gt((system as EconomySystem).assessed_value(), 0)
	check_eq(sim.stats.inventions.size(), EconomyParams.TECHNOLOGIES.size())
	var snap := sim.snapshot()
	var copy := make_simulation(industrial_city())
	copy.restore(snap)
	check_eq(copy.get_system(&"economy").save(), system.save())
	check_eq(copy.stats.inventions, sim.stats.inventions)
	check_eq(copy.stats.sector_shares, sim.stats.sector_shares)
	root.remove_child(sim)
	root.remove_child(copy)
	sim.free()
	copy.free()


func test_sector_rates_set_the_industrial_tax() -> void:
	var ctx := make_ctx(flat_city())
	var eco := eco_of(ctx)
	check_eq(ctx.stats.tax_industrial, 7)
	check_eq(EconomySystem.aggregate_industrial_rate(ctx.stats), 7, "equal sector rates give the same aggregate")
	# The budget's slider writes the aggregate; every sector follows the change.
	ctx.stats.tax_industrial = 10
	run_months(ctx, 1)
	for t in ctx.stats.sector_taxes:
		check_eq(t, 10)
	check_eq(ctx.stats.tax_industrial, 10)
	# Sector rates set the aggregate the budget charges.
	var taxes := ctx.stats.sector_taxes
	var shares := ctx.stats.sector_shares
	var top := 0
	for i in shares.size():
		if shares[i] > shares[top]:
			top = i
	taxes[top] = 20
	ctx.stats.sector_taxes = taxes
	eco.sector_taxes_changed()
	check_gt(ctx.stats.tax_industrial, 10, "taxing the biggest sector raises the aggregate")
	check_eq(ctx.stats.tax_industrial, EconomySystem.aggregate_industrial_rate(ctx.stats))
	run_months(ctx, 1)
	check_eq(ctx.stats.sector_taxes[top], 20, "a published aggregate is not mistaken for a slider move")
	check_eq(ctx.stats.tax_industrial, EconomySystem.aggregate_industrial_rate(ctx.stats),
		"the aggregate follows the new shares")


func test_an_older_save_lines_sector_rates_up_with_the_industrial_rate() -> void:
	var ctx := make_ctx(flat_city())
	var eco := eco_of(ctx)
	var saved := eco.save()
	saved.erase("published_industrial")
	ctx.stats.tax_industrial = 12
	var fresh := PackedInt32Array()
	fresh.resize(EconomyParams.SECTOR_COUNT)
	fresh.fill(7)
	ctx.stats.sector_taxes = fresh
	eco.load(saved)
	for t in ctx.stats.sector_taxes:
		check_eq(t, 12, "untouched sector rates take the player's rate")
	check_eq(ctx.stats.tax_industrial, 12)
