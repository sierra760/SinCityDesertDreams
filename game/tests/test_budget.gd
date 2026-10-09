# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const RES_TOP := Buildings.RES_1X1_LAST
const COM_TOP := Buildings.COM_2X2_LAST

var _contexts: Array[SimContext] = []


func after_each() -> void:
	for ctx: SimContext in _contexts:
		ctx.systems.clear()
	_contexts.clear()


func make_ctx(c: City, seed_value: int = 7) -> SimContext:
	var ctx := make_context(c, seed_value)
	ctx.clock.founded_year = c.founded_year
	_contexts.append(ctx)
	return ctx


func make_budget(ctx: SimContext) -> BudgetSystem:
	var b := BudgetSystem.new()
	ctx.systems[&"budget"] = b
	b.setup(ctx)
	return b


## 100 top-stage homes and 20 top-stage shopping blocks on a flat map.
func zoned_city() -> City:
	var c := flat_city(10000)
	for i in 100:
		c.stamp_building(i % 50, 10 + i / 50, RES_TOP, Zones.RES_LOW)
	for i in 20:
		c.stamp_building(2 * i, 20, COM_TOP, Zones.COM_HIGH)
	return c


func test_taxes_accrue_monthly_and_settle_in_january() -> void:
	var c := zoned_city()
	var ctx := make_ctx(c)
	var b := make_budget(ctx)
	# 100 × 80 residential value at 7% = 560/yr; 20 × 480 commercial at 7% = 672/yr.
	b.monthly(ctx)
	check_eq(int(ctx.stats.ledger[&"taxes_residential"]), 560 / 12, "one month of residential tax")
	check_eq(int(ctx.stats.ledger[&"taxes_commercial"]), 672 / 12, "one month of commercial tax")
	check_eq(c.funds, 10000, "cash does not move mid-year")
	for _m in 11:
		b.monthly(ctx)
	check_eq(int(ctx.stats.ledger[&"taxes_residential"]), 560, "twelve months add up exactly")
	check_eq(int(ctx.stats.ledger[&"taxes_commercial"]), 672)
	b.yearly(ctx)
	check_eq(c.funds, 10000 + 560 + 672, "settlement pays the year's taxes")
	check_eq(int(ctx.stats.last_year_ledger[&"taxes_residential"]), 560, "books copied to last year")
	check_eq(int(ctx.stats.ledger[&"taxes_residential"]), 0, "ledger reset after settlement")
	check(ctx.events.notices.is_empty(), "no crisis in a solvent year")


func test_rate_change_affects_only_following_months() -> void:
	var c := zoned_city()
	var ctx := make_ctx(c)
	var b := make_budget(ctx)
	for _m in 6:
		b.monthly(ctx)
	var half := int(ctx.stats.ledger[&"taxes_residential"])
	ctx.stats.tax_residential = 14
	for _m in 6:
		b.monthly(ctx)
	var full := int(ctx.stats.ledger[&"taxes_residential"])
	check_eq(half, 280, "six months at 7%")
	check_eq(full, 280 + 560, "six more months at 14%")


func test_service_upkeep_scales_with_funding() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.POLICE_STATION)
	c.stamp_building(20, 10, Buildings.POLICE_STATION)
	c.stamp_building(30, 10, Buildings.HOSPITAL)
	c.stamp_building(40, 10, Buildings.SCHOOL)
	c.stamp_building(50, 10, Buildings.COLLEGE)
	var ctx := make_ctx(c)
	var b := make_budget(ctx)
	var est := b.estimated_ledger()
	check_eq(int(est[&"police"]), 200, "two stations at full funding")
	check_eq(int(est[&"health"]), 50)
	check_eq(int(est[&"education"]), 125, "school plus college")
	ctx.stats.set_funding(&"police", 50)
	ctx.stats.set_funding(&"colleges", 0)
	est = b.estimated_ledger()
	check_eq(int(est[&"police"]), 100, "half funding halves the bill")
	check_eq(int(est[&"education"]), 25, "unfunded college costs nothing")
	check_eq(b.estimated_expenses(), 100 + 50 + 25)
	check_eq(b.estimated_income(), 0)


func test_transport_upkeep_per_tile_without_wear_system() -> void:
	var c := flat_city()
	for y in 8:
		for x in City.WIDTH:
			c.building.put(x, y, Buildings.ROAD_FIRST)
	for x in 100:
		c.building.put(x, 30, Buildings.RAIL_FIRST)
	var ctx := make_ctx(c)
	var b := make_budget(ctx)
	# 1024 road tiles at 10 cents and 100 rail tiles at 40 cents.
	check_eq(int(b.estimated_ledger()[&"transport"]), 102 + 40)
	ctx.stats.set_funding(&"roads", 0)
	check_eq(int(b.estimated_ledger()[&"transport"]), 40, "unfunded roads are free but rail still bills")


func test_bond_issue_adds_funds_and_interest() -> void:
	var c := flat_city(1000)
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	var ctx := make_ctx(c)
	var b := make_budget(ctx)
	b.monthly(ctx)
	check_eq(ctx.stats.city_value, 4000, "city value is what was built")
	var quote := b.bond_quote(10000)
	check(bool(quote["eligible"]), "a debt-free city can borrow")
	check_eq(int(quote["rate"]), ctx.stats.prime_rate + 1, "first bond at prime plus one")
	check(b.issue_bond(10000))
	check_eq(c.funds, 11000)
	check_eq(ctx.stats.bonds.size(), 1)
	var bond_news := ctx.events.news.filter(func(n): return n["kind"] == &"bond_issued")
	check_eq(bond_news.size(), 1, "the newspaper hears about the bond")
	if bond_news.size() == 1:
		check_eq(int(bond_news[0]["args"]["amount"]), 10000)
	var rate := int(ctx.stats.bonds[0]["rate"])
	check_eq(b.estimated_ledger()[&"bond_interest"], 10000 * rate / 100)
	var before := int(ctx.stats.ledger[&"bond_interest"])
	b.monthly(ctx)
	check_eq(int(ctx.stats.ledger[&"bond_interest"]) - before, 10000 * rate / 100 / 12, "one month of interest")
	check(not bool(b.bond_quote(10000)["eligible"]), "heavy debt against little value is refused")
	check(not b.issue_bond(10000))
	check(not b.repay_bond(1), "only the oldest bond can be repaid")
	c.funds = 5000
	check(not b.repay_bond(0), "cannot repay without the cash")
	c.funds = 12000
	check(b.repay_bond(0))
	check_eq(c.funds, 2000)
	check(ctx.stats.bonds.is_empty())
	check_ge(int(ctx.stats.ledger[&"bond_interest"]), 1, "interest already booked stays booked")


func test_bond_cap_and_amount_range() -> void:
	var c := flat_city(0)
	c.stamp_building(10, 10, Buildings.FUSION_PLANT)
	c.stamp_building(20, 10, Buildings.FUSION_PLANT)
	c.stamp_building(30, 10, Buildings.FUSION_PLANT)
	var ctx := make_ctx(c)
	var b := make_budget(ctx)
	b.monthly(ctx)
	check(not bool(b.bond_quote(BudgetParams.BOND_MAX * 10)["eligible"]), "oversized bond refused")
	var issued := 0
	while b.issue_bond(BudgetParams.BOND_MIN):
		issued += 1
		if issued > BudgetParams.MAX_BONDS + 5:
			break
	check_eq(issued, BudgetParams.MAX_BONDS, "the cap holds for a very valuable city")
	check_eq(c.funds, BudgetParams.MAX_BONDS * BudgetParams.BOND_MIN)


func test_deficit_settlement_disables_auto_budget() -> void:
	var c := flat_city(50)
	c.stamp_building(10, 10, Buildings.POLICE_STATION)
	var ctx := make_ctx(c)
	ctx.stats.auto_budget = true
	var b := make_budget(ctx)
	for _m in 12:
		b.monthly(ctx)
	b.yearly(ctx)
	check_eq(c.funds, 50 - 100)
	check(not ctx.stats.auto_budget, "a deficit hands the review back to the player")
	check(not ctx.stats.bankrupt, "a small deficit is not bankruptcy")
	var kinds: Array = ctx.events.notices.map(func(n): return n["kind"])
	check(&"fiscal_crisis" in kinds, "fiscal crisis notice")
	var news: Array = ctx.events.news.map(func(n): return n["kind"])
	check(&"treasury_deficit" in news)


func test_bankruptcy_when_treasury_collapses() -> void:
	var c := flat_city(BudgetParams.BANKRUPTCY_FUNDS - 1)
	var ctx := make_ctx(c)
	var b := make_budget(ctx)
	b.yearly(ctx)
	check(ctx.stats.bankrupt)
	var kinds: Array = ctx.events.notices.map(func(n): return n["kind"])
	check(&"bankruptcy" in kinds)
	var news: Array = ctx.events.news.map(func(n): return n["kind"])
	check(&"bankruptcy" in news, "the bankruptcy makes the paper")
	ctx.events.clear()
	b.yearly(ctx)
	check(ctx.events.notices.filter(func(n): return n["kind"] == &"bankruptcy").is_empty(), "notified once")


func test_recovered_treasury_clears_bankruptcy() -> void:
	var c := flat_city(BudgetParams.BANKRUPTCY_FUNDS - 1)
	var ctx := make_ctx(c)
	var b := make_budget(ctx)
	b.monthly(ctx)
	check(ctx.stats.bankrupt)
	c.funds = 5000
	ctx.events.clear()
	b.monthly(ctx)
	check(not ctx.stats.bankrupt, "a recovered treasury is no longer bankrupt")
	check(not bool(b.review_summary()["bankrupt"]))
	c.funds = BudgetParams.BANKRUPTCY_FUNDS - 1
	b.monthly(ctx)
	check(ctx.stats.bankrupt)
	check_eq(ctx.events.notices.filter(func(n): return n["kind"] == &"bankruptcy").size(), 1,
		"a second collapse is reported again")

func test_estimates_follow_map_edits_between_queries() -> void:
	var c := zoned_city()
	var ctx := make_ctx(c)
	var b := make_budget(ctx)
	var first := b.review_summary()
	check_eq(b.review_summary(), first, "an unchanged map gives the same summary")
	check_eq(first["estimated_ledger"], b.estimated_ledger())
	check_eq(int(first["estimated_income"]), b.estimated_income())
	check_eq(int(first["estimated_expenses"]), b.estimated_expenses())
	# Growth or a disaster changes the map without telling the budget.
	c.stamp_building(60, 60, RES_TOP, Zones.RES_LOW)
	check_gt(b.estimated_income(), int(first["estimated_income"]), "a new home is taxed at once")
	c.zone.put(60, 60, Zones.make(Zones.COM_LOW))
	var rezoned := b.estimated_income()
	c.building.put(60, 60, Buildings.NONE)
	check_lt(b.estimated_income(), rezoned, "a lost home leaves the estimate")

func test_prime_rate_follows_the_economy_within_bounds() -> void:
	var c := flat_city()
	var ctx := make_ctx(c)
	var b := make_budget(ctx)
	ctx.stats.economy_phase = 3
	for _y in 10:
		b.yearly(ctx)
	check_eq(ctx.stats.prime_rate, BudgetParams.PRIME_MAX, "a long boom pins the rate at the ceiling")
	ctx.stats.economy_phase = 0
	for _y in 10:
		b.yearly(ctx)
	check_eq(ctx.stats.prime_rate, BudgetParams.PRIME_MIN, "a long recession pins it at the floor")
	ctx.stats.bonds.append({"principal": 10000, "rate": 8, "age": 0})
	b.yearly(ctx)
	check_eq(int(ctx.stats.bonds[0]["age"]), 1, "bonds age at settlement")


func test_review_summary_reports_the_settled_year() -> void:
	var c := zoned_city()
	var ctx := make_ctx(c)
	var b := make_budget(ctx)
	for _m in 12:
		b.monthly(ctx)
	b.yearly(ctx)
	var s := b.review_summary()
	check_eq(int(s["income"]), 560 + 672)
	check_eq(int(s["expenses"]), 0)
	check_eq(int(s["net"]), 1232)
	check_eq(int(s["estimated_income"]), 1232, "next year looks the same at the same settings")
	check(s.has("bond_quote") and s.has("prime_rate") and s.has("last_year_ledger"))
	check(b.needs_review())
	ctx.stats.auto_budget = true
	check(not b.needs_review())


func test_save_load_round_trip_mid_year() -> void:
	var c := zoned_city()
	c.stamp_building(60, 60, Buildings.FIRE_STATION)
	var ctx := make_ctx(c)
	var b := make_budget(ctx)
	b.issue_bond(10000)
	for _m in 5:
		b.monthly(ctx)
	# Round-trip through JSON text, as the save format does.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(b.save()))
	var saved_stats: Dictionary = JSON.parse_string(JSON.stringify(ctx.stats.to_dict()))
	var ctx2 := make_ctx(c.duplicate_city())
	ctx2.stats.from_dict(saved_stats)
	var b2 := make_budget(ctx2)
	b2.load(saved)
	check_eq(ctx2.stats.ledger[&"taxes_residential"], ctx.stats.ledger[&"taxes_residential"])
	check_eq(ctx2.stats.bonds.size(), 1)
	for _m in 7:
		b.monthly(ctx)
		b2.monthly(ctx2)
	b.yearly(ctx)
	b2.yearly(ctx2)
	check_eq(ctx2.city.funds, c.funds, "resumed books settle to the same treasury")
	check_eq(ctx2.stats.last_year_ledger[&"bond_interest"], ctx.stats.last_year_ledger[&"bond_interest"])


## True when the Simulation loaded every system script. A sibling package with
## a parse error aborts loading; then only this package's own script is checked.
func simulation_loaded(sim: Simulation, own: StringName, path: String) -> bool:
	if sim.get_system(own) != null:
		return true
	var script: GDScript = load(path)
	check(script != null and script.new() != null, "own system script loads")
	print("    skipped: the Simulation could not load a sibling system")
	return false


func _free_simulation(sim: Simulation) -> void:
	# Release the context/system reference cycle before the synchronous harness quits.
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()


func test_simulation_settles_at_year_end_and_pauses_for_review() -> void:
	var c := zoned_city()
	var sim := make_simulation(c)
	if not simulation_loaded(sim, &"budget", "res://scripts/sim/budget_system.gd"):
		_free_simulation(sim)
		return
	var start := c.funds
	sim.advance_days(GameClock.DAYS_PER_YEAR - 1)
	check(not sim.budget_review_pending)
	check_eq(c.funds, start, "no cash movement before the review")
	sim.advance_day()
	check(sim.budget_review_pending, "January review is pending after the last day of December")
	var b: BudgetSystem = sim.get_system(&"budget")
	var s := b.review_summary()
	check_eq(c.funds, start + int(s["net"]), "treasury changed by the settled net")
	check_gt(int(s["income"]), 0, "the zoned city earned taxes")
	var snap := sim.snapshot()
	check(snap["systems"].has("budget"))
	sim.finish_budget_review()
	sim.advance_days(20)
	check(not sim.budget_review_pending)
	_free_simulation(sim)


func test_tax_changes_are_reported_once() -> void:
	var ctx := make_ctx(flat_city(1000))
	var b := make_budget(ctx)
	b.monthly(ctx)
	check(ctx.events.news.filter(func(n): return n["kind"] == &"tax_change").is_empty(),
		"unchanged rates are not news")
	ctx.stats.tax_commercial = 11
	ctx.events.clear()
	b.monthly(ctx)
	var news := ctx.events.news.filter(func(n): return n["kind"] == &"tax_change")
	check_eq(news.size(), 1)
	if news.size() == 1:
		check_eq(int(news[0]["args"]["count"]), 11)
		check_eq(news[0]["args"]["family"], "commercial")
	ctx.events.clear()
	var restored := BudgetSystem.new()
	restored.setup(ctx)
	restored.load(JSON.parse_string(JSON.stringify(b.save())))
	restored.monthly(ctx)
	check(ctx.events.news.filter(func(n): return n["kind"] == &"tax_change").is_empty(),
		"a reload does not repeat the story")


func test_budget_industrial_rate_survives_a_sector_edit_and_windows_agree() -> void:
	var c := flat_city(20000)
	c.founded_year = 2000
	var sim := make_simulation(c)
	if not simulation_loaded(sim, &"economy", "res://scripts/sim/economy_system.gd"):
		_free_simulation(sim)
		return
	var holder := Control.new()
	root.add_child(holder)
	var budget := BudgetWindow.new()
	var industries := IndustriesWindow.new()
	holder.add_child(budget)
	holder.add_child(industries)
	budget.bind(sim)
	industries.bind(sim)
	budget.open()
	industries.open()
	budget.set_tax(&"industrial", 15)
	check_eq(sim.stats.tax_industrial, 15)
	for t in sim.stats.sector_taxes:
		check_eq(t, 15, "every sector follows the Budget rate at once")
	check(industries.sector_text(3).ends_with("| 15"), "the open Industries window shows it: " + industries.sector_text(3))
	industries.set_sector_tax(3, 16)
	check_eq(sim.stats.sector_taxes[3], 16, "the sector edit lands")
	check_eq(sim.stats.sector_taxes[4], 15, "the Budget change is not thrown away")
	check_eq(sim.stats.tax_industrial, EconomySystem.aggregate_industrial_rate(sim.stats))
	check(sim.stats.tax_industrial >= 15, "the aggregate keeps the Budget's rise")
	check_eq(int((budget._tax_spinners[&"industrial"] as TouchNumberField).value), sim.stats.tax_industrial,
		"the open Budget agrees with Industries")
	root.remove_child(holder)
	holder.free()
	_free_simulation(sim)


func test_open_budget_follows_ordinances_and_the_treasury() -> void:
	var c := zoned_city()
	c.founded_year = 2000
	var sim := make_simulation(c)
	if not simulation_loaded(sim, &"ordinances", "res://scripts/sim/ordinance_system.gd"):
		_free_simulation(sim)
		return
	sim.stats.population = 200000
	var holder := Control.new()
	root.add_child(holder)
	var budget := BudgetWindow.new()
	var ordinances := OrdinancesWindow.new()
	holder.add_child(budget)
	holder.add_child(ordinances)
	budget.bind(sim)
	ordinances.bind(sim)
	budget.open()
	ordinances.open()
	var before := budget.ledger_text(&"ordinance_cost")
	ordinances.set_ordinance(&"energy_conservation", true)
	check(budget.ledger_text(&"ordinance_cost") != before, "the open Budget shows the new ordinance cost: " + budget.ledger_text(&"ordinance_cost"))
	# The treasury line and Repay follow the funds without waiting for month end.
	sim.adjust_funds(1234)
	check(budget.funds_text().contains(UIFactory.commafy(c.funds)), budget.funds_text())
	check(budget._repay_button.disabled, "no bonds to repay")
	check_eq(budget._repay_button.tooltip_text, "No bonds to repay")
	root.remove_child(holder)
	holder.free()
	_free_simulation(sim)
