# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const StatisticsSystem := preload("res://scripts/sim/statistics_system.gd")
var sim: Simulation
var mounted: Array[Control] = []

func before_each() -> void:
	var city := flat_city(20000)
	for a in [Vector2i(10,10), Vector2i(30,30), Vector2i(50,50)]:
		TourismFixture.venue(city, &"com_corner_store" if a.x == 50 else &"arcology_boddy", a)
		TourismFixture.set_served(city, a, true, true)
		city.stamp_building(a.x-1,a.y,Buildings.ROAD_FIRST)
	sim = make_simulation(city, 770)
	# Actual network setup may clear flags: these unit fixtures explicitly provide service.
	for a in [Vector2i(10,10), Vector2i(30,30), Vector2i(50,50)]:
		TourismFixture.set_served(city,a,true,true)
	sim.tourism().reconcile_now()
	sim.stats.population = 1234

func after_each() -> void:
	for node in mounted:
		root.remove_child(node)
		node.free()
	mounted.clear()
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()

func window(w: Control) -> Control:
	root.add_child(w)
	mounted.append(w)
	w.bind(sim)
	w.open()
	return w

func labels(node: Node) -> String:
	var parts: PackedStringArray = []
	for child in node.get_children():
		if child is Label: parts.append(child.text)
		parts.append(labels(child))
	return "\n".join(parts)

func test_two_tax_controls_clamp_and_refresh_independently() -> void:
	var w := window(BudgetWindow.new()) as BudgetWindow
	check(labels(w).contains("Occupancy tax %"), "exact occupancy label")
	check(labels(w).contains("Gaming revenue tax %"), "exact gaming label")
	if not w._tax_spinners.has(&"occupancy") or not w._tax_spinners.has(&"gaming"): return
	check_eq(w._tax_spinners[&"occupancy"].value,7.0)
	check_eq(w._tax_spinners[&"gaming"].value,7.0)
	for rate in [-1,0,7,20,21]:
		w.set_tax(&"occupancy",rate)
		check_eq(sim.stats.tax_occupancy,clampi(rate,0,20))
		check_eq(sim.stats.tax_gaming,7)
	w.set_tax(&"occupancy",7)
	for rate in [-1,0,7,20,21]:
		w.set_tax(&"gaming",rate)
		check_eq(sim.stats.tax_gaming,clampi(rate,0,20))
		check_eq(sim.stats.tax_occupancy,7)
	for account in [&"taxes_occupancy", &"taxes_gaming"]:
		check(not w.ledger_text(account).is_empty(),"tourism book row exists")

func test_budget_forecast_repeated_reads_are_pure() -> void:
	sim.clock.day = 16
	sim.tourism().monthly(sim._ctx)
	var before := sim.snapshot().duplicate(true)
	var funds := sim.city.funds
	var facilities := sim.city.facilities.duplicate(true)
	var w := window(BudgetWindow.new()) as BudgetWindow
	for i in 4:
		w.refresh()
		w.close()
		w.open()
	check(labels(w).contains("Current occupancy"),"current attendance distinct")
	check(labels(w).contains("Target occupancy"),"allocation target distinct")
	check(labels(w).contains("Settled forecast"),"settled forecast explicit")
	check(labels(w).contains("Completed monthly taxable bases: lodging $%.2f; gaming after payouts $%.2f" % [sim.stats.tourist_lodging_cents / 100.0, sim.stats.tourist_gaming_cents / 100.0]),"completed actual business remains separate from projection")
	check_eq(sim.snapshot(),before,"report reads do not book, admit or draw RNG")
	check_eq(sim.city.funds,funds)
	check_eq(sim.city.facilities,facilities)
	var baseline := sim.snapshot().duplicate(true)
	w.set_tax(&"occupancy",20)
	baseline.stats.tax_occupancy = 20
	check_eq(sim.snapshot(),baseline,"changing a rate only writes that prospective rate")

func test_inspect_separates_store_guests_day_visitors_and_mayor_play() -> void:
	TourismFixture.set_served(sim.city,Vector2i(30,30),false,true)
	sim.tourism().reconcile_now()
	sim.clock.day = 16
	sim.tourism().monthly(sim._ctx)
	for a in [Vector2i(10,10),Vector2i(30,30),Vector2i(50,50)]:
		var row := sim.tourism().venue_report(a)
		var shown := QueryPanel.describe(sim.city,sim,a)
		check_eq(shown.get("Guests",-1),row.guests,"guests belong to selected anchor")
		check_eq(shown.get("Day visitors",-1),row.day_visitors)
		check_eq(shown.get("Tourists",-1),row.tourists)
		check_eq(shown.get("Lodging capacity",-1),row.capacity)
		check_eq(shown.get("Day visitor capacity",-1),row.day_capacity)
		check_eq(shown.get("Occupancy",""),"%d%%" % row.occupancy)
		check(not shown.has("Residents"),"visitors are not residents")
		check(shown.has("Mayor's play this year"),"separate mayor ledger")
		check_eq(shown.get("Completed lodging base",""),"$%.2f" % (row.lodging_cents / 100.0))
		check_eq(shown.get("Completed gaming base",""),"$%.2f" % (row.gaming_cents / 100.0))
	check_eq(sim.tourism().venue_report(Vector2i(30,30)).tourists,0)
	check_gt(sim.tourism().venue_report(Vector2i(10,10)).tourists,0)
	check_eq(sim.tourism().venue_report(Vector2i(50,50)).guests,0)
	check(QueryPanel.describe(sim.city,sim,Vector2i(50,50)).has("Jobs"),"store retains its ordinary commercial employment")

func test_graph_booking_month_and_year_rollover() -> void:
	var budget := sim.get_system(&"budget")
	var statistics := sim.get_system(&"statistics")
	var before := sim.snapshot().duplicate(true)
	# An exact sub-dollar actual booking must not be rounded into money or rebooked.
	var saved := budget.save()
	saved.tourism_booking = {"month_id":11,"occupancy_units":1199,"gaming_units":2401}
	saved.tourism_booked_month = 11
	budget.load(saved)
	sim.clock.day = 11 * GameClock.DAYS_PER_MONTH + 21
	statistics.monthly(sim._ctx)
	check_eq(sim.stats.history.get(&"taxes_occupancy",PackedInt32Array()),PackedInt32Array([0]))
	check_eq(sim.stats.history.get(&"taxes_gaming",PackedInt32Array()),PackedInt32Array([2]))
	var book := budget.save()
	sim.clock.day = GameClock.DAYS_PER_YEAR + 21
	statistics.monthly(sim._ctx)
	check_eq(sim.stats.history.get(&"taxes_gaming",PackedInt32Array()),PackedInt32Array([2,0]),"previous year's booking is not this month")
	check_eq(budget.save(),book,"sampling never acknowledges or rebooks")
	check_eq(sim.city.funds,20000)
	check_eq(sim._ctx.rng.state(),int(before.rng_state))
	check_eq(GraphsWindow.SERIES_LABELS.get(&"taxes_occupancy",""),"Monthly occupancy tax accrued ($)")
	check_eq(GraphsWindow.SERIES_LABELS.get(&"taxes_gaming",""),"Monthly gaming tax accrued ($)")
	check_eq(GraphsWindow.GraphCanvas.value_text(&"taxes_gaming",2),"$2")
	check_eq(GraphsWindow.GraphCanvas.value_text(&"tourist_occupancy",25),"25%")

func test_legacy_history_unchanged() -> void:
	var old := PackedInt32Array([120,240,99999])
	sim.stats.history[&"population"] = old.duplicate()
	var w := window(GraphsWindow.new()) as GraphsWindow
	w.refresh()
	check_eq(sim.stats.history[&"population"].to_byte_array(),old.to_byte_array())
	check(not sim.stats.history.has(&"tourists"),"opening a graph cannot synthesize history")
	check(labels(w).contains("older population samples included resort occupants"),"history semantics explained")
	var p := window(PopulationWindow.new()) as PopulationWindow
	check_eq(p.headline_text(),"Population 1,234, a Village")
	check(labels(p).contains("Tourism"))
	check(not labels(p).contains("residents, built"))

func test_save_cards_honor_legacy_unknown_and_separate_current_counts() -> void:
	var dialog := LoadDialog.new()
	root.add_child(dialog)
	mounted.append(dialog)
	var entries: Array[Dictionary] = [{"name":"Old town","path":"user://old.sc2d","population":55,"count_schema":0,"count_label":"Legacy population","tourists":-1}]
	dialog.open(entries)
	check(dialog.details_label.text.contains("Legacy population 55"))
	check(not dialog.details_label.text.contains("Tourists"),"unknown is omitted")
	check(not dialog.item_list.get_item_text(0).contains("-1"))
	entries[0].merge({"count_schema":1,"count_label":"Population","tourists":42},true)
	dialog.refresh(entries)
	check(dialog.details_label.text.contains("Population 55"))
	check(dialog.details_label.text.contains("Tourists 42"))


func test_save_dialog_optional_count_input_and_unknown_tourists() -> void:
	var dialog := SaveDialog.new()
	root.add_child(dialog)
	mounted.append(dialog)
	dialog.open("Old",{"population":55,"tourists":-1,"count_label":"Legacy population"})
	check_eq(dialog.counts_label.text,"Legacy population 55")
	dialog.close()
	dialog.open("Current",{"population":100,"tourists":45,"count_schema":1})
	check_eq(dialog.counts_label.text,"Population 100 · Tourists 45")
	dialog.close()
	dialog.open("Standalone")
	check(not dialog.counts_label.visible,"standalone callers do not invent counts")

func test_tourism_compact_disclosure_and_tax_estimate_are_pure() -> void:
	var w := window(BudgetWindow.new()) as BudgetWindow
	var details := w.find_child("TourismDetails", true, false) as Button
	check(details != null, "tourism has a touch and keyboard disclosure")
	if details == null: return
	var body := w.find_child("TourismDetailBody", true, false) as Control
	check(not body.visible, "details start collapsed")
	check_ge(details.custom_minimum_size.y, 44)
	check_eq(details.focus_mode, Control.FOCUS_ALL)
	var before := sim.snapshot().duplicate(true)
	details.button_pressed = true
	check(body.visible)
	w.refresh()
	check(body.visible, "refresh preserves disclosure")
	details.button_pressed = false
	check_eq(sim.snapshot(), before, "disclosure does not advance tourism or finances")
	check(labels(w).contains("Current"))
	check(labels(w).contains("Forecast"))
	check(labels(w).contains("Estimated city tax income"))
	var estimate: Dictionary = sim.get_system(&"budget").call("estimated_ledger")
	var value := w.find_child("TourismTaxEstimate", true, false) as Label
	check(value != null)
	if value != null:
		check_eq(value.text, UIFactory.format_amount(int(estimate.taxes_occupancy) + int(estimate.taxes_gaming)) + " / year")

func test_structured_tourism_current_forecast_and_income_follow_both_rates() -> void:
	sim.clock.day = 16
	sim.city.day = 16
	sim.tourism().monthly(sim._ctx)
	sim.get_system(&"budget").monthly(sim._ctx)
	var w := window(BudgetWindow.new()) as BudgetWindow
	var before := sim.snapshot().duplicate(true)
	for rates in [Vector2i(0, 7), Vector2i(12, 17), Vector2i(20, 0), Vector2i(7, 7)]:
		w.set_tax(&"occupancy", rates.x)
		w.set_tax(&"gaming", rates.y)
		var projection := sim.tourism().forecast()
		var estimate: Dictionary = sim.get_system(&"budget").call("estimated_ledger")
		check_eq(w._tourism_values.guests[0].text, UIFactory.commafy(before.stats.tourist_guests))
		check_eq(w._tourism_values.day[0].text, UIFactory.commafy(before.stats.tourist_day_visitors))
		check_eq(w._tourism_values.occupancy[0].text, "%d%%" % before.stats.tourist_occupancy)
		check_eq(w._tourism_values.guests[1].text, UIFactory.commafy(projection.guests))
		check_eq(w._tourism_values.day[1].text, UIFactory.commafy(projection.day_visitors))
		check_eq(w._tourism_values.occupancy[1].text, "%d%%" % projection.occupancy)
		check_eq(w._tourism_tax.text, UIFactory.format_amount(int(estimate.taxes_occupancy) + int(estimate.taxes_gaming)) + " / year")
		before.stats.tax_occupancy = rates.x
		before.stats.tax_gaming = rates.y
		check_eq(sim.snapshot(), before, "rates change only prospective tax; forecast remains pure")
