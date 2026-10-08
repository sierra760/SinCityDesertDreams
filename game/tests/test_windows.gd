# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The information windows: each one binds to a running simulation, shows the
## right numbers, writes the settings it owns, survives an empty simulation
## and closes cleanly.
extends "res://tests/test_case.gd"

const MONTHS := 14

var sim: Simulation
var city: City
var _mounted: Array[Control] = []


func before_all() -> void:
	city = flat_city(20000)
	city.founded_year = 1950
	city.name = "Testbed"
	sim = make_simulation(city, 777)
	_build_town(city, sim.stats, sim)
	sim.advance_months(MONTHS)


func after_all() -> void:
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()


func after_each() -> void:
	for w in _mounted:
		root.remove_child(w)
		w.free()
	_mounted.clear()


func _build_town(c: City, stats: CityStats, s: Simulation) -> void:
	var b := Builder.new(c, stats, s)
	b.apply(Tools.Kind.COAL_PLANT, Vector2i(30, 40))
	b.apply(Tools.Kind.WATER_PUMP, Vector2i(34, 43))
	b.apply(Tools.Kind.ROAD, Vector2i(36, 44), Vector2i(70, 44))
	b.apply(Tools.Kind.ROAD, Vector2i(36, 50), Vector2i(70, 50))
	b.apply(Tools.Kind.ROAD, Vector2i(36, 41), Vector2i(36, 56))
	b.apply(Tools.Kind.POWER_LINE, Vector2i(34, 44), Vector2i(36, 44))
	b.apply(Tools.Kind.POWER_LINE, Vector2i(35, 44), Vector2i(35, 51))
	b.apply(Tools.Kind.POWER_LINE, Vector2i(35, 45), Vector2i(37, 45))
	b.apply(Tools.Kind.POWER_LINE, Vector2i(35, 51), Vector2i(37, 51))
	b.apply(Tools.Kind.ZONE_RES_LOW, Vector2i(37, 45), Vector2i(70, 49))
	b.apply(Tools.Kind.ZONE_COM_LOW, Vector2i(37, 51), Vector2i(52, 55))
	b.apply(Tools.Kind.ZONE_IND_LOW, Vector2i(53, 51), Vector2i(70, 55))
	b.apply(Tools.Kind.WATER_PIPE, Vector2i(35, 43), Vector2i(35, 51))
	b.apply(Tools.Kind.WATER_PIPE, Vector2i(35, 44), Vector2i(70, 44))
	b.apply(Tools.Kind.WATER_PIPE, Vector2i(35, 50), Vector2i(70, 50))
	b.apply(Tools.Kind.POLICE, Vector2i(72, 45))
	b.apply(Tools.Kind.FIRE, Vector2i(72, 51))


func _mount(w: Control) -> Control:
	root.add_child(w)
	_mounted.append(w)
	return w


func _all_windows() -> Array[Control]:
	var out: Array[Control] = []
	out.append(BudgetWindow.new())
	out.append(GraphsWindow.new())
	out.append(PopulationWindow.new())
	out.append(IndustriesWindow.new())
	out.append(OrdinancesWindow.new())
	out.append(NewspaperWindow.new())
	out.append(CityMapsWindow.new())
	out.append(NeighborsWindow.new())
	return out


func _escape() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	return e


# ── Budget ───────────────────────────────────────────────────────────────

func test_budget_shows_books_and_writes_settings() -> void:
	var w: BudgetWindow = _mount(BudgetWindow.new())
	w.bind(sim)
	w.open()
	check(w.visible, "open shows the window")
	check(w.funds_text().contains(UIFactory.commafy(city.funds)), "treasury shown: " + w.funds_text())
	var ytd := int(sim.stats.ledger.get(&"taxes_residential", 0))
	check(w.ledger_text(&"taxes_residential").begins_with(UIFactory.format_amount(ytd)),
		"year-to-date residential taxes: " + w.ledger_text(&"taxes_residential"))
	var budget := sim.get_system(&"budget")
	var estimate: Dictionary = budget.call("estimated_ledger")
	check(w.ledger_text(&"police").ends_with(UIFactory.format_amount(int(estimate[&"police"]))),
		"police estimate: " + w.ledger_text(&"police"))
	check(w.totals_text().contains("Estimated income"), w.totals_text())

	w.set_tax(&"residential", 12)
	check_eq(sim.stats.tax_residential, 12, "tax spinner writes the stat")
	w.set_tax(&"commercial", 3)
	check_eq(sim.stats.tax_commercial, 3)
	w.set_tax(&"industrial", 9)
	check_eq(sim.stats.tax_industrial, 9)
	w.set_funding(&"police", 40)
	check_eq(sim.stats.funding_of(&"police"), 40, "funding slider writes the stat")
	w.set_funding(&"roads", 0)
	check_eq(sim.stats.funding_of(&"roads"), 0)
	w.set_auto_budget(true)
	check(sim.stats.auto_budget, "auto-budget checkbox writes the stat")
	w.set_auto_budget(false)
	check(not sim.stats.auto_budget)
	w.set_tax(&"residential", 7)
	w.set_tax(&"commercial", 7)
	w.set_tax(&"industrial", 7)
	w.set_funding(&"police", 100)
	w.set_funding(&"roads", 100)

	var closed := [0]
	w.closed.connect(func() -> void: closed[0] += 1)
	w.close()
	check(not w.visible, "close hides")
	check_eq(closed[0], 1, "close emits closed once")


func test_budget_ledger_keeps_the_sign_of_negative_amounts() -> void:
	var label := Label.new()
	BudgetWindow._set_amount(label, -1250, false)
	check_eq(label.text, "-$1,250", "net trade imports keep their minus sign")
	check_eq(label.get_theme_color("font_color"), UITheme.MONEY_NEGATIVE, "a negative income costs money")
	BudgetWindow._set_amount(label, 1250, false)
	check_eq(label.text, "$1,250")
	check_eq(label.get_theme_color("font_color"), UITheme.MONEY_POSITIVE)
	BudgetWindow._set_amount(label, 800, true)
	check_eq(label.text, "$800")
	check_eq(label.get_theme_color("font_color"), UITheme.MONEY_NEGATIVE, "spending stays red")
	BudgetWindow._set_amount(label, -800, true)
	check_eq(label.text, "-$800")
	check_eq(label.get_theme_color("font_color"), UITheme.MONEY_POSITIVE, "a refund adds money")
	BudgetWindow._set_amount(label, 0, true)
	check_eq(label.get_theme_color("font_color"), UITheme.MONEY_NEUTRAL)
	label.free()
	check_eq(UIFactory.commafy_signed(-12345), "-12,345")
	check_eq(UIFactory.commafy_signed(12345), "12,345")


func test_budget_bonds_issue_and_repay() -> void:
	var w: BudgetWindow = _mount(BudgetWindow.new())
	w.bind(sim)
	w.open()
	var before := city.funds
	var count := sim.stats.bonds.size()
	w.set_bond_amount(5000)
	check(w.quote_text().contains("5,000"), "live quote follows the amount: " + w.quote_text())
	check(w.issue_bond(), "a solvent town can borrow")
	check_eq(sim.stats.bonds.size(), count + 1, "bond recorded")
	check_eq(city.funds, before + 5000, "principal lands in the treasury")
	check(w.funds_text().contains(UIFactory.commafy(city.funds)), "treasury label refreshed")
	check(w.repay_oldest(), "the oldest bond can be repaid")
	check_eq(sim.stats.bonds.size(), count, "bond gone")
	check_eq(city.funds, before, "principal paid back")


func test_budget_review_closes_with_done() -> void:
	var w: BudgetWindow = _mount(BudgetWindow.new())
	w.bind(sim)
	var remaining := GameClock.DAYS_PER_YEAR - sim.clock.day % GameClock.DAYS_PER_YEAR
	sim.advance_days(remaining - 1)
	sim.advance_day()
	check(sim.budget_review_pending, "January review pending after the last day of the year")
	w.closed.connect(func() -> void: sim.finish_budget_review())
	w.open()
	check(w.ledger_text(&"taxes_residential").begins_with("$0"), "books reset after settlement")
	w.close()
	check(not sim.budget_review_pending, "closing the review resumes the simulation")
	sim.advance_months(1)


# ── Graphs ───────────────────────────────────────────────────────────────

func test_graphs_plot_selected_series() -> void:
	var w: GraphsWindow = _mount(GraphsWindow.new())
	w.bind(sim)
	w.open()
	check(&"population" in w.selected_series(), "population is picked by default")
	var history: PackedInt32Array = sim.stats.history.get(&"population", PackedInt32Array())
	check_gt(history.size(), 6, "the town has sampled history")
	var points := w.canvas().points_for(&"population")
	check_eq(points.size(), mini(history.size(), 120), "one point per sample inside the span")
	check(points[points.size() - 1].x > points[0].x, "newest sample drawn to the right")
	check(w.legend_text().contains("Population: " + UIFactory.commafy(history[history.size() - 1])),
		"legend shows the current value: " + w.legend_text())
	w.set_series_enabled(&"money", true)
	check_eq(w.selected_series().size(), 2, "two series overlay")
	check(w.legend_text().contains("Funds"), "legend lists both: " + w.legend_text())
	w.set_range_years(1)
	check_eq(w.range_years(), 1)
	check(w.canvas().points_for(&"population").size() <= 12, "one-year span keeps twelve samples at most")
	w.set_range_years(100)
	check_eq(w.canvas().points_for(&"population").size(), history.size(), "century span shows everything")
	var closed := [0]
	w.closed.connect(func() -> void: closed[0] += 1)
	w._unhandled_key_input(_escape())
	check(not w.visible, "escape closes")
	check_eq(closed[0], 1)


# ── Population ───────────────────────────────────────────────────────────

func test_population_headline_and_cohorts() -> void:
	var w: PopulationWindow = _mount(PopulationWindow.new())
	w.bind(sim)
	w.open()
	var total := sim.stats.total_population()
	check_gt(total, 0, "people moved in")
	check(w.headline_text().contains(UIFactory.commafy(total)), w.headline_text())
	check(w.headline_text().contains(PopulationSystem.status_name(city.status)), "status name shown")
	check(w.scores_text().contains("approval %d%%" % sim.stats.approval), w.scores_text())
	check(w.scores_text().contains("education %d" % sim.stats.education_quotient), w.scores_text())
	var summed := 0
	for i in PopulationWindow.COHORTS:
		var parts := w.cohort_text(i).split(" | ")
		check_eq(parts.size(), 3, "three columns per cohort")
		summed += int(parts[0].replace(",", ""))
	check_eq(summed, sim.stats.population, "cohort rows add up to the residents")
	var population := sim.get_system(&"population")
	var eq5 := int(population.call("cohort_education", 5, sim.stats))
	check(w.cohort_text(5).ends_with("| %d | %d" % [eq5, int(population.call("cohort_health", 5, sim.stats))]),
		"education and health per cohort: " + w.cohort_text(5))
	check(w.complaint_text(0) != "", "complaint list has a first line")
	check_eq(w.arcology_count(), 1, "the arcology list shows its placeholder row")
	var closed := [0]
	w.closed.connect(func() -> void: closed[0] += 1)
	w.close()
	check_eq(closed[0], 1)


# ── Industries ───────────────────────────────────────────────────────────

func test_industries_table_and_sector_tax() -> void:
	var w: IndustriesWindow = _mount(IndustriesWindow.new())
	w.bind(sim)
	w.open()
	check(w.phase_text().contains(EconomySystem.phase_name(sim.stats.economy_phase)), w.phase_text())
	check(w.value_text().contains(UIFactory.commafy(sim.stats.city_value)), w.value_text())
	check(w.sector_text(0).begins_with(EconomySystem.sector_name(0)), w.sector_text(0))
	check(w.sector_text(9).ends_with("| 7"), "default sector tax shown: " + w.sector_text(9))
	w.set_sector_tax(9, 15)
	check_eq(sim.stats.sector_taxes[9], 15, "sector spinner writes the stat")
	check_eq(sim.stats.sector_taxes[8], 7, "other sectors untouched")
	check(w.sector_text(9).ends_with("| 15"))
	check_eq(sim.stats.tax_industrial, EconomySystem.aggregate_industrial_rate(sim.stats),
		"a sector rate moves the aggregate industrial rate at once")
	check(w.value_text().contains("aggregate industrial tax %d%%" % sim.stats.tax_industrial), w.value_text())
	w.set_sector_tax(9, 7)
	var closed := [0]
	w.closed.connect(func() -> void: closed[0] += 1)
	w.close()
	check_eq(closed[0], 1)


func test_budget_shows_network_condition() -> void:
	var text := BudgetWindow.condition_text(sim)
	check(text.begins_with("Condition: "), text)
	check(text.contains("Roads ") and text.contains("% worn"), text)
	check(BudgetWindow.condition_text(null).is_empty())


func test_status_bar_lists_the_status_lines() -> void:
	var bar := StatusBar.new()
	_mount(bar)
	bar.refresh(sim)
	var statistics := sim.get_system(&"statistics")
	var lines: Array = statistics.call("status_lines")
	check_eq(bar.population_label.tooltip_text, "\n".join(PackedStringArray(lines)))
	check(bar.population_label.tooltip_text.contains("Rain "), bar.population_label.tooltip_text)


# ── Ordinances ───────────────────────────────────────────────────────────

func test_ordinances_toggle_and_totals() -> void:
	var w: OrdinancesWindow = _mount(OrdinancesWindow.new())
	w.bind(sim)
	w.open()
	check_eq(w.row_count(), OrdinanceParams.CATALOG.size(), "every policy listed")
	check(not w.is_checked(&"free_clinics"))
	w.set_ordinance(&"free_clinics", true)
	check(bool(sim.stats.ordinances.get(&"free_clinics", false)), "checkbox writes the ordinance flag")
	check(w.is_checked(&"free_clinics"))
	var ordinances := sim.get_system(&"ordinances")
	check(bool(ordinances.call("is_enabled", &"free_clinics")), "system agrees")
	var expected := int(ordinances.call("estimated_yearly", &"free_clinics"))
	check(w.amount_text(&"free_clinics").begins_with(UIFactory.format_money(expected)), w.amount_text(&"free_clinics"))
	check(w.totals_text().contains("cost " + UIFactory.format_amount(sim.stats.ordinance_cost)), w.totals_text())
	w.set_ordinance(&"free_clinics", false)
	check(not bool(sim.stats.ordinances.get(&"free_clinics", true)), "unchecking clears it")
	var closed := [0]
	w.closed.connect(func() -> void: closed[0] += 1)
	w._unhandled_key_input(_escape())
	check_eq(closed[0], 1, "escape closes")


# ── Newspaper ────────────────────────────────────────────────────────────

func test_newspaper_pages_through_the_archive() -> void:
	var w: NewspaperWindow = _mount(NewspaperWindow.new())
	w.bind(sim)
	w.open()
	var count := w.issue_count()
	check_gt(count, 1, "months of issues exist")
	check_eq(w.current_index(), count - 1, "opens on the latest issue")
	check(w.headline_text() != "", "lead headline shown")
	check_ge(w.story_count(), 1)
	var latest: Dictionary = sim.stats.newspaper_archive[count - 1]
	check_eq(w.date_text(), String(latest["date"]), "issue date shown")
	w.show_previous()
	check_eq(w.current_index(), count - 2, "previous walks back")
	var older: Dictionary = sim.stats.newspaper_archive[count - 2]
	check_eq(w.date_text(), String(older["date"]))
	w.show_next()
	check_eq(w.current_index(), count - 1, "next walks forward")
	w.show_issue(0)
	check_eq(w.current_index(), 0)
	w.show_previous()
	check_eq(w.current_index(), 0, "cannot go before the first issue")
	check_ge(w.advice_count(), 1, "advisor panel filled")
	var closed := [0]
	w.closed.connect(func() -> void: closed[0] += 1)
	w.close()
	check_eq(closed[0], 1)


# ── City maps ────────────────────────────────────────────────────────────

func test_city_maps_select_overlay_and_drive_renderer() -> void:
	var w: CityMapsWindow = _mount(CityMapsWindow.new())
	w.bind(sim)
	w.open()
	var picked: Array[StringName] = []
	w.overlay_selected.connect(func(kind: StringName) -> void: picked.append(kind))
	w.select_overlay(&"crime")
	check_eq(w.selected_overlay(), &"crime")
	check(w.legend_text().contains("Low") and w.legend_text().contains("High"), w.legend_text())
	w.select_overlay(&"power")
	check(w.legend_text().contains("Powered"), w.legend_text())
	w.select_overlay(&"bogus")
	check_eq(w.selected_overlay(), &"power", "unknown kinds are ignored")
	var presentation := CityPresentationController.new()
	root.add_child(presentation)
	presentation.bind_city(city)
	presentation.set_overlay(&"traffic")
	var pushed: Array[StringName] = []
	presentation.overlay_changed.connect(func(kind: StringName) -> void: pushed.append(kind))
	w.bind_presentation(presentation)
	check_eq(presentation.get_overlay(), &"traffic", "attaching keeps the active overlay")
	check_eq(w.selected_overlay(), &"traffic", "the window adopts the drawn overlay")
	check_eq(pushed.size(), 0, "attaching does not announce an overlay change")
	w.select_overlay(&"zones")
	check_eq(presentation.get_overlay(), &"zones", "selection drives the presentation")
	check(w.legend_text().contains("Light Residential"), w.legend_text())
	w.select_overlay(&"")
	check_eq(presentation.get_overlay(), &"", "none hides the overlay")
	check_eq(picked.size(), 4, "one signal per accepted choice")
	root.remove_child(presentation)
	presentation.free()
	var closed := [0]
	w.closed.connect(func() -> void: closed[0] += 1)
	w.close()
	check_eq(closed[0], 1)


# ── Neighbors ────────────────────────────────────────────────────────────

func test_neighbors_cards_show_the_region() -> void:
	var w: NeighborsWindow = _mount(NeighborsWindow.new())
	w.bind(sim)
	w.open()
	var neighbors := sim.get_system(&"neighbors")
	var report: Array = neighbors.call("neighbor_report")
	check_eq(report.size(), 4)
	for edge in 4:
		var rec: Dictionary = report[edge]
		var text := w.card_text(edge)
		check(text.begins_with(String(rec["name"])), "name on card %d: %s" % [edge, text])
		check(text.contains(UIFactory.commafy(int(rec["population"]))), "population on card %d: %s" % [edge, text])
	check(w.compass_text().contains(city.name), "the city sits at the centre")
	var closed := [0]
	w.closed.connect(func() -> void: closed[0] += 1)
	w.close()
	check_eq(closed[0], 1)


# ── Shared behaviour ─────────────────────────────────────────────────────

func test_every_window_survives_no_city_and_no_simulation() -> void:
	var empty := Simulation.new()
	root.add_child(empty)
	for w in _all_windows():
		_mount(w)
		w.call("bind", empty)
		w.call("open")
		w.call("refresh")
		check(w.visible, "%s opens without a city" % w.get_class())
		w.call("close")
		w.call("bind", null)
		w.call("open")
		w.call("refresh")
		check(w.visible, "%s opens without a simulation" % w.get_class())
		w.call("close")
	root.remove_child(empty)
	empty.free()


func test_every_window_refreshes_on_month_end_while_open() -> void:
	for w in _all_windows():
		_mount(w)
		w.call("bind", sim)
		check(not w.visible, "windows start hidden")
		w.call("open")
		check(w.visible)
		check(sim.month_ended.get_connections().size() >= 1, "month_ended wired")
	sim.advance_months(1)
	var budget: BudgetWindow = _mounted[0]
	check(budget.funds_text().contains(UIFactory.commafy(city.funds)), "budget followed the month: " + budget.funds_text())
	var paper: NewspaperWindow = _mounted[5]
	check_eq(paper.current_index(), paper.issue_count() - 1, "newspaper followed the month")
	for w in _mounted:
		var closed := [0]
		w.connect("closed", func() -> void: closed[0] += 1)
		w.call("_unhandled_key_input", _escape())
		check(not w.visible, "escape closes %s" % w.get_class())
		check_eq(closed[0], 1, "%s emits closed once" % w.get_class())
