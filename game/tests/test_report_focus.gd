# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

var sim: Simulation
var mounted: Array[Control] = []

func before_each() -> void:
	sim = make_simulation(flat_city(50000), 628)

func after_each() -> void:
	for w in mounted: w.free()
	mounted.clear()
	sim._ctx.systems.clear()
	sim.systems.clear()
	sim.free()

func window(w: Control) -> Control:
	root.add_child(w)
	mounted.append(w)
	w.bind(sim)
	w.open()
	return w

func test_empty_tourism_has_one_empty_state_and_retains_navigation() -> void:
	var w := window(TourismWindow.new()) as TourismWindow
	var overview := w.find_child("TourismOverview", true, false) as Control
	check(overview != null, "attendance and financial counters have an empty state")
	if overview == null: return
	check(not overview.is_visible_in_tree(), "a new city does not show a report of zeros")
	check(w._tourism_limiter.is_visible_in_tree())
	for button: Button in w._buttons.values(): check(not button.is_visible_in_tree())
	var links: Array = []
	w.report_requested.connect(func(name: String, page: String): links.append([name, page]))
	var taxes := w.find_child("VisitorTaxLink", true, false) as Button
	check(taxes != null and taxes.is_visible_in_tree(), "tax controls remain reachable before venues exist")
	if taxes != null: taxes.pressed.emit()
	check_eq(links, [["budget", "Taxes"]])

func test_tourism_keeps_completed_activity_when_no_venues_remain() -> void:
	var w := window(TourismWindow.new()) as TourismWindow
	var overview := w.find_child("TourismOverview", true, false) as Control
	check(overview != null)
	if overview == null: return
	sim.stats.ledger[&"taxes_occupancy"] = 120
	var before := sim.snapshot().duplicate(true)
	w.refresh()
	check(overview.is_visible_in_tree(), "demolition must not hide taxes already accrued")
	(w._buttons["Income"] as Button).button_pressed = true
	check(w._tourism_accrued.is_visible_in_tree())
	check(w._tourism_accrued.text.contains("120"))
	check_eq(sim.snapshot(), before, "empty-state decisions never change the books")
	w.refresh()
	check((w._buttons["Income"] as Button).button_pressed, "refresh keeps useful details open")

func test_unsettled_budget_does_not_show_an_empty_previous_year() -> void:
	var w := window(BudgetWindow.new()) as BudgetWindow
	check(not w._last_year_label.is_visible_in_tree(), "a city with no settled books needs no previous-year placeholder")
	var before := sim.snapshot().duplicate(true)
	w.select_page("Taxes")
	w.set_tax(&"occupancy", 12)
	check_eq(sim.stats.tax_occupancy, 12)
	before.stats.tax_occupancy = 12
	w.select_page("Summary")
	w.refresh()
	check_eq(sim.snapshot(), before)

func test_population_age_table_is_optional_and_survives_refresh() -> void:
	var w := window(PopulationWindow.new()) as PopulationWindow
	var toggle := w.find_child("AgeDetails", true, false) as Button
	var body := w.find_child("AgeDetailsBody", true, false) as Control
	check(toggle != null and body != null, "numeric age breakdown is available on demand")
	if toggle == null or body == null: return
	check(not body.is_visible_in_tree())
	var before := sim.snapshot().duplicate(true)
	toggle.button_pressed = true
	check(body.is_visible_in_tree())
	check_eq(w._cohort_rows.size(), 20, "all age groups remain available")
	w.refresh()
	check(body.is_visible_in_tree() and toggle.button_pressed)
	check_eq(sim.snapshot(), before)
	toggle.button_pressed = false
	check(not body.is_visible_in_tree())

func test_population_hides_empty_resort_section_but_keeps_venue_failures() -> void:
	var w := window(PopulationWindow.new()) as PopulationWindow
	var toggle := w.find_child("ResortDetails", true, false) as Button
	check(toggle != null)
	if toggle == null: return
	check(not toggle.is_visible_in_tree())
	TourismFixture.venue(sim.city, &"arcology_boddy", Vector2i(10, 10))
	sim.tourism().reconcile_now()
	w.refresh()
	check(toggle.is_visible_in_tree())
	toggle.button_pressed = true
	check(w._arcology_box.is_visible_in_tree())
	check_gt(w._arcology_box.get_child_count(), 1)
	var before := sim.snapshot().duplicate(true)
	w.refresh()
	check(toggle.button_pressed and w._arcology_box.is_visible_in_tree())
	check_eq(sim.snapshot(), before)

func test_graph_selection_is_optional_and_keeps_focus_when_collapsed() -> void:
	var w := window(GraphsWindow.new()) as GraphsWindow
	var toggle := w.find_child("SeriesDetails", true, false) as Button
	check(toggle != null, "the chart leads, with series selection available on demand")
	if toggle == null: return
	check(not w._picker.is_visible_in_tree())
	toggle.button_pressed = true
	check(w._picker.is_visible_in_tree())
	w.set_series_enabled(&"population", true)
	var selected := w.selected_series()
	var before := sim.snapshot().duplicate(true)
	w.refresh()
	check(toggle.button_pressed and w._picker.is_visible_in_tree())
	(w._series_boxes[&"population"] as CheckBox).grab_focus()
	toggle.button_pressed = false
	check(not w._picker.is_visible_in_tree())
	check_eq(root.gui_get_focus_owner(), toggle, "focus never remains on a hidden series")
	check_eq(w.selected_series(), selected)
	check_eq(sim.snapshot(), before)

func test_budget_treasury_color_follows_the_cash_balance() -> void:
	var w := window(BudgetWindow.new()) as BudgetWindow
	sim.city.funds = -1200
	w.refresh()
	check_eq(w._funds_label.get_theme_color("font_color"), UITheme.MONEY_NEGATIVE, "a negative treasury must not look healthy")
	w._on_funds_changed(0)
	check_eq(w._funds_label.get_theme_color("font_color"), UITheme.MONEY_NEUTRAL)
	w._on_funds_changed(1200)
	check_eq(w._funds_label.get_theme_color("font_color"), UITheme.MONEY_POSITIVE)
