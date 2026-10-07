# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

var _contexts: Array[SimContext] = []


func after_each() -> void:
	# Hand-built fixtures own the context table without a Simulation Node.
	for ctx: SimContext in _contexts:
		ctx.systems.clear()
	_contexts.clear()


func make_ctx(c: City, seed_value: int = 3) -> SimContext:
	var ctx := make_context(c, seed_value)
	_contexts.append(ctx)
	return ctx


func make_ordinances(ctx: SimContext) -> OrdinanceSystem:
	var o := OrdinanceSystem.new()
	ctx.systems[&"ordinances"] = o
	o.setup(ctx)
	return o


func test_catalog_has_twenty_policies_in_three_groups() -> void:
	var ctx := make_ctx(flat_city())
	var o := make_ordinances(ctx)
	var rows := o.catalog()
	check_eq(rows.size(), 20)
	var groups := {}
	var names := {}
	for row in rows:
		groups[row["group"]] = int(groups.get(row["group"], 0)) + 1
		check(not names.has(row["name"]), "duplicate name %s" % row["name"])
		names[row["name"]] = true
		check(String(row["description"]).length() > 20, "every policy has a description")
		check(ctx.stats.ordinances.has(row["key"]), "flag published for %s" % row["key"])
		check(not bool(ctx.stats.ordinances[row["key"]]), "everything starts off")
	check_eq(int(groups[OrdinanceParams.GROUP_FINANCE]), 6)
	check_eq(int(groups[OrdinanceParams.GROUP_SAFETY]), 7)
	check_eq(int(groups[OrdinanceParams.GROUP_CITY]), 7)
	check_eq(ctx.stats.ordinance_income, 0)
	check_eq(ctx.stats.ordinance_cost, 0)


func test_fees_scale_with_population() -> void:
	var ctx := make_ctx(flat_city())
	var o := make_ordinances(ctx)
	ctx.stats.population = 10000
	check_eq(o.estimated_yearly(&"income_tax"), 133)
	check_eq(o.estimated_yearly(&"free_clinics"), -67)
	check_eq(o.estimated_yearly(&"nuclear_free_zone"), 0)
	o.set_enabled(&"income_tax", true)
	o.set_enabled(&"free_clinics", true)
	o.set_enabled(&"nuclear_free_zone", true)
	check_eq(ctx.stats.ordinance_income, 133)
	check_eq(ctx.stats.ordinance_cost, 67)
	check(o.is_enabled(&"income_tax"))
	ctx.stats.population = 20000
	ctx.stats.arcology_population = 10000
	o.monthly(ctx)
	check_eq(ctx.stats.ordinance_income, 399, "arcology residents pay too")
	o.set_enabled(&"income_tax", false)
	check_eq(ctx.stats.ordinance_income, 0)
	o.set_enabled(&"no_such_policy", true)
	check(not ctx.stats.ordinances.has(&"no_such_policy"), "unknown keys are ignored")


func test_enabling_an_ordinance_changes_the_ledger() -> void:
	var ctx := make_ctx(flat_city())
	var o := make_ordinances(ctx)
	var b := BudgetSystem.new()
	ctx.systems[&"budget"] = b
	b.setup(ctx)
	ctx.stats.population = 12000
	b.monthly(ctx)
	check_eq(int(ctx.stats.ledger[&"ordinance_income"]), 0)
	o.set_enabled(&"legalized_gambling", true)
	o.set_enabled(&"neighborhood_watch", true)
	b.monthly(ctx)
	check_eq(int(ctx.stats.ledger[&"ordinance_income"]), 96 / 12, "gambling pays 96 a year on 12,000 people")
	check_eq(int(ctx.stats.ledger[&"ordinance_cost"]), 52 / 12, "the watch costs 52 a year")
	for _m in 10:
		b.monthly(ctx)
	check_eq(int(ctx.stats.ledger[&"ordinance_income"]), 96 * 11 / 12, "eleven months booked")
	var funds := ctx.city.funds
	b.yearly(ctx)
	check_eq(ctx.city.funds, funds + 96 * 11 / 12 - 52 * 11 / 12)


func test_effective_tax_rates_follow_the_switches() -> void:
	var ctx := make_ctx(flat_city())
	var o := make_ordinances(ctx)
	check_eq(o.effective_tax_rates(), Vector3i(7, 7, 7))
	o.set_enabled(&"sales_tax", true)
	o.set_enabled(&"income_tax", true)
	o.set_enabled(&"pollution_controls", true)
	check_eq(o.effective_tax_rates(), Vector3i(8, 8, 8))
	o.set_enabled(&"tree_planting", true)
	o.set_enabled(&"tourist_advertising", true)
	o.set_enabled(&"annual_carnival", true)
	o.set_enabled(&"business_advertising", true)
	check_eq(o.effective_tax_rates(), Vector3i(7, 6, 7))
	ctx.stats.tax_commercial = 0
	check_eq(o.effective_tax_rates().y, 0, "never below zero")
	check_eq(o.power_capacity_bonus(1200), 0)
	o.set_enabled(&"energy_conservation", true)
	check_eq(o.power_capacity_bonus(1200), 100, "conservation stretches capacity by a twelfth")


## Every ordinance key another system reads must be a catalog key; an unknown
## key can never be switched on, so the policy would cost money and do nothing.
func test_systems_read_catalog_ordinance_keys() -> void:
	var ctx := make_ctx(flat_city())
	var o := make_ordinances(ctx)
	for k: StringName in [PopulationParams.ORDINANCE_PRO_READING,
			PopulationParams.ORDINANCE_FREE_CLINICS, PopulationParams.ORDINANCE_ANTI_DRUG,
			PopulationParams.ORDINANCE_SMOKING_BAN, UtilityParams.CONSERVATION_ORDINANCE]:
		check(o.is_known(k), "%s is a catalog ordinance" % k)
	var pattern := RegEx.create_from_string("ordinances\\.get\\(&\"([a-z_]+)\"")
	var dir := DirAccess.open("res://scripts/sim")
	check(dir != null)
	if dir == null:
		return
	var reads := 0
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string("res://scripts/sim/" + file)
		for m in pattern.search_all(text):
			reads += 1
			check(o.is_known(StringName(m.get_string(1))),
				"%s reads catalog ordinance %s" % [file, m.get_string(1)])
	check_gt(reads, 0, "the scan found ordinance reads")

func test_council_enacts_only_when_rich_and_disasters_are_on() -> void:
	var ctx := make_ctx(flat_city(1000000))
	var o := make_ordinances(ctx)
	ctx.stats.disasters_enabled = false
	for _m in 200:
		o.monthly(ctx)
	check(ctx.events.news.is_empty(), "no council action while disasters are off")
	ctx.stats.disasters_enabled = true
	for _m in 200:
		o.monthly(ctx)
	var enacted := ctx.events.news.filter(func(n): return n["kind"] == &"ordinance_enacted")
	check_gt(enacted.size(), 0, "a rich council eventually acts")
	var any_on := false
	for k in ctx.stats.ordinances:
		any_on = any_on or bool(ctx.stats.ordinances[k])
	check(any_on)
	var poor := make_ctx(flat_city(100))
	var p := make_ordinances(poor)
	for _m in 200:
		p.monthly(poor)
	check(poor.events.news.is_empty(), "a poor council never spends")


func test_flags_survive_save_and_load() -> void:
	var ctx := make_ctx(flat_city())
	var o := make_ordinances(ctx)
	ctx.stats.population = 5000
	o.set_enabled(&"parking_fines", true)
	o.set_enabled(&"volunteer_fire", true)
	var stats_json: Dictionary = JSON.parse_string(JSON.stringify(ctx.stats.to_dict()))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(o.save()))
	var ctx2 := make_ctx(flat_city())
	ctx2.stats.from_dict(stats_json)
	var o2 := make_ordinances(ctx2)
	o2.load(saved)
	check(o2.is_enabled(&"parking_fines"))
	check(o2.is_enabled(&"volunteer_fire"))
	check(not o2.is_enabled(&"sales_tax"))
	check_eq(ctx2.stats.ordinance_income, ctx.stats.ordinance_income)
	check_eq(ctx2.stats.ordinance_cost, ctx.stats.ordinance_cost)
	check_eq(ctx2.stats.ordinances.size(), 20)


## True when the Simulation loaded every system script. A sibling package with
## a parse error aborts loading; then only this package's own script is checked.
func simulation_loaded(sim: Simulation, own: StringName, path: String) -> bool:
	if sim.get_system(own) != null:
		return true
	var script: GDScript = load(path)
	check(script != null and script.new() != null, "own system script loads")
	print("    skipped: the Simulation could not load a sibling system")
	return false


func test_simulation_runs_the_ordinance_day() -> void:
	var c := flat_city()
	var sim := make_simulation(c)
	if not simulation_loaded(sim, &"ordinances", "res://scripts/sim/ordinance_system.gd"):
		sim.queue_free()
		return
	var o: OrdinanceSystem = sim.get_system(&"ordinances")
	o.set_enabled(&"sales_tax", true)
	sim.stats.population = 8000
	sim.advance_days(25)
	# Another system may recount the population; the fee follows whatever it is.
	check_eq(sim.stats.ordinance_income, sim.stats.total_population() * 40 / 10000)
	check(bool(sim.snapshot()["stats"]["ordinances"]["sales_tax"]))
	sim.queue_free()
