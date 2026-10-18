# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

var sim: Simulation
var mounted: Array[Control] = []

func before_each() -> void:
	sim = make_simulation(flat_city(50000), 450)

func after_each() -> void:
	for w in mounted: w.free()
	mounted.clear()
	sim._ctx.systems.clear()
	sim.systems.clear()
	sim.free()

func budget() -> BudgetWindow:
	var w := BudgetWindow.new()
	root.add_child(w)
	mounted.append(w)
	w.bind(sim)
	w.open()
	return w

func test_budget_opens_with_a_short_summary_and_fixed_tabs() -> void:
	var w := budget()
	check(w.has_method("select_page"), "budget has named pages")
	if not w.has_method("select_page"): return
	check_eq(w.call("selected_page"), "Summary")
	var tabs := w.find_child("ReportTabs", true, false) as TabBar
	check(tabs != null)
	if tabs != null:
		check_eq(tabs.tab_count, 4)
		check(not w._body.is_ancestor_of(tabs), "tabs stay out of the scrolling body")
	var breakdown := w.find_child("AccountBreakdown", true, false) as Button
	check(breakdown != null)
	if breakdown != null: check(not breakdown.button_pressed)
	check_eq(w._tax_spinners.size(), 6, "all tax controls survive reorganization")
	check(w.find_child("TourismComparison", true, false) == null, "attendance leaves Budget")
	var before := sim.snapshot().duplicate(true)
	for page in ["Taxes", "Funding", "Debt", "Summary"]: w.call("select_page", page)
	check_eq(sim.snapshot(), before, "navigation is read-only")

func test_budget_keeps_tab_and_disclosure_on_refresh() -> void:
	var w := budget()
	if not w.has_method("select_page"):
		check(false, "budget has pages")
		return
	w.call("select_page", "Taxes")
	w.refresh()
	check_eq(w.call("selected_page"), "Taxes")
	w.call("select_page", "Summary")
	var disclosure := w.find_child("AccountBreakdown", true, false) as Button
	if disclosure == null:
		check(false, "ledger has disclosure")
		return
	disclosure.button_pressed = true
	w.refresh()
	check(disclosure.button_pressed)
	var period := w.find_child("LedgerPeriod", true, false) as OptionButton
	check(period != null)
	if period != null: check_eq(period.item_count, 3)

func test_funding_shows_one_category_and_writes_both() -> void:
	var w := budget()
	check(w.has_method("select_funding"))
	if not w.has_method("select_funding"): return
	w.call("select_page", "Funding")
	var services := w.find_child("ServiceFunding", true, false) as Control
	var transport := w.find_child("TransportFunding", true, false) as Control
	check(services != null and transport != null)
	if services == null or transport == null: return
	check(services.visible and not transport.visible)
	w.call("select_funding", 1)
	check(transport.visible and not services.visible)
	w.set_funding(&"roads", 40)
	w.set_funding(&"police", 60)
	check_eq(sim.stats.funding_of(&"roads"), 40)
	check_eq(sim.stats.funding_of(&"police"), 60)

func test_ordinance_categories_filter_without_changing_totals() -> void:
	var w := OrdinancesWindow.new()
	root.add_child(w)
	mounted.append(w)
	w.bind(sim)
	w.open()
	check(w.has_method("select_group"), "ordinances have category pages")
	if not w.has_method("select_group"): return
	w.set_ordinance(&"sales_tax", true)
	var totals := w.totals_text()
	w.call("select_group", "Safety")
	w.call("set_enacted_only", true)
	check_eq(w.totals_text(), totals, "totals cover all enacted policies")
	check_eq(w.call("visible_policy_count"), 0)
	w.call("select_group", "Finance")
	check_eq(w.call("visible_policy_count"), 1)
	w.refresh()
	check_eq(w.call("selected_group"), "Finance")
	check_eq(w.row_count(), OrdinanceParams.CATALOG.size(), "filter never loses policies")

func test_tourism_menu_and_report_are_separate_and_pure() -> void:
	check(GameMenuBar.WINDOW_NAMES.has("tourism"))
	check(WindowManager.SCRIPTS.has("tourism"))
	var w := TourismWindow.new()
	root.add_child(w)
	mounted.append(w)
	var before := sim.snapshot().duplicate(true)
	w.bind(sim)
	w.open()
	w.refresh()
	check_eq(sim.snapshot(), before)
	check(w._tourism_limiter.text.contains("No tourism venues"))
	check(w.find_child("TourismComparison", true, false) != null)
	var actual := w.find_child("TourismActualHeader", true, false) as Label
	var forecast := w.find_child("TourismForecastHeader", true, false) as Label
	check(actual != null and forecast != null)
	if actual != null and forecast != null:
		check(actual.is_visible_in_tree() and forecast.is_visible_in_tree(), "period qualifications are visible before expanding any section")
		check_eq(actual.text, "Latest monthly")
		check_eq(forecast.text, "Supported forecast")
	w.bind(null)
	check_eq(w._status.text, "No city loaded")

func test_only_one_ordinance_description_expands_and_names_are_accessible() -> void:
	var w := OrdinancesWindow.new()
	root.add_child(w)
	mounted.append(w)
	w.bind(sim)
	w.open()
	var first: Dictionary = w._rows[&"sales_tax"]
	var second: Dictionary = w._rows[&"income_tax"]
	check_eq((first.box as CheckBox).accessibility_name, "Sales Tax")
	(first.details as Button).button_pressed = true
	check((first.description as Control).visible)
	(second.details as Button).button_pressed = true
	check(not (first.description as Control).visible)
	check((second.description as Control).visible)
	w.refresh()
	check((second.description as Control).visible)
