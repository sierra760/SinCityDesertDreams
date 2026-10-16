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
		for x in range(a.x): city.building.put(x,a.y,Buildings.ROAD_FIRST)
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
	w._tourism_details.button_pressed=true
	check(w._tourism_calendar.is_visible_in_tree(),"season and event are organized under Details")
	check(w._tourism_calendar.text.begins_with("Season: 115%"))
	check(labels(w).contains("this month’s season/events ×12"),"annual estimate discloses its current-month basis")
	check(labels(w).contains("Current"),"current attendance distinct")
	check(labels(w).contains("Last plan:"),"staff plan distinct")
	check(labels(w).contains("Supported estimate:"),"supported estimate explicit")
	check(labels(w).contains("last accepted utility support"),"market/staff forecast cannot promise unavailable utility-supported attendance")
	check(labels(w).contains("Completed monthly taxable bases: lodging $%.2f; gaming after payouts $%.2f" % [sim.stats.tourist_lodging_cents / 100.0, sim.stats.tourist_gaming_cents / 100.0]),"completed actual business remains separate from projection")
	check_eq(sim.snapshot(),before,"report reads do not book, admit or draw RNG")
	check_eq(sim.city.funds,funds)
	check_eq(sim.city.facilities,facilities)
	var baseline := sim.snapshot().duplicate(true)
	w.set_tax(&"occupancy",20)
	baseline.stats.tax_occupancy = 20
	check_eq(sim.snapshot(),baseline,"changing a rate only writes that prospective rate")

func test_inspect_separates_store_guests_day_visitors_and_mayor_play() -> void:
	TourismFixture.established_sources(sim) # The scheduled admission verifies physical local budgets.
	TourismFixture.set_served(sim.city,Vector2i(30,30),false,true)
	sim.tourism().reconcile_now()
	sim.clock.day = 16
	sim.tourism().monthly(sim._ctx)
	for a in [Vector2i(10,10),Vector2i(30,30),Vector2i(50,50)]:
		var row := sim.tourism().venue_report(a)
		var shown := QueryPanel.describe(sim.city,sim,a)
		check(shown.has("Utility support"),"accepted utility support is distinct from physical beds")
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
		check_eq(value.text, UIFactory.format_amount(int(estimate.taxes_occupancy) + int(estimate.taxes_gaming)) + " / year at this month’s pace")

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
		var projection := sim.tourism().supported_forecast()
		var estimate: Dictionary = sim.get_system(&"budget").call("estimated_ledger")
		check_eq(w._tourism_values.guests[0].text, UIFactory.commafy(before.stats.tourist_guests))
		check_eq(w._tourism_values.day[0].text, UIFactory.commafy(before.stats.tourist_day_visitors))
		check_eq(w._tourism_values.occupancy[0].text, "%d%%" % before.stats.tourist_occupancy)
		check_eq(w._tourism_values.guests[1].text, UIFactory.commafy(projection.guests))
		check_eq(w._tourism_values.day[1].text, UIFactory.commafy(projection.day_visitors))
		check_eq(w._tourism_values.occupancy[1].text, "%d%%" % projection.occupancy)
		check_eq(w._tourism_tax.text, UIFactory.format_amount(int(estimate.taxes_occupancy) + int(estimate.taxes_gaming)) + " / year at this month’s pace")
		before.stats.tax_occupancy = rates.x
		before.stats.tax_gaming = rates.y
		check_eq(sim.snapshot(), before, "rates change only prospective tax; forecast remains pure")

func test_safety_details_and_inspect_explain_live_source_and_program_estimate() -> void:
	sim.stats.ordinances[&"casino_safety"] = true
	sim.clock.day = 16
	sim.tourism().monthly(sim._ctx)
	var w := window(BudgetWindow.new()) as BudgetWindow
	w._tourism_details.button_pressed=true
	check(labels(w).contains("Casino crime source"), "Details explains pressure rather than hiding it in tax income")
	check(labels(w).contains("estimate if enabled"), "explicit expense estimate")
	var shown := QueryPanel.describe(sim.city, sim, Vector2i(10, 10))
	check(shown.has("Casino source"))
	check(shown.has("Casino safety"))
	check(shown.has("Nightlife exposure"))

func test_district_details_and_inspect_share_authoritative_commercial_fields() -> void:
	var at:=Vector2i(10,10)
	TourismFixture.venue(sim.city,&"small_park",Vector2i(13,10))
	sim.tourism().reconcile_now()
	sim.clock.day=16
	sim.tourism().monthly(sim._ctx)
	var before:=sim.snapshot().duplicate(true)
	var w:=window(BudgetWindow.new()) as BudgetWindow
	w._tourism_details.button_pressed=true
	check(labels(w).contains("Retail support"))
	check(labels(w).contains("Business support is not city cash"))
	check(labels(w).contains("Arrival capacity:"))
	var row:=sim.tourism().venue_report(at)
	var shown:=QueryPanel.describe(sim.city,sim,at)
	check_eq(shown["District appeal"],"+%d points; %d attraction categories" % [int(row.district_appeal_bonus),row.district_categories.size()])
	check_eq(shown["Retail support"],"$%.2f business opportunity; $%.2f allocated nearby" % [int(row.commercial_spending_cents)/100.0,int(row.commercial_allocated_cents)/100.0])
	check_eq(sim.snapshot(),before)


func test_gateway_capacity_and_reason_are_visible_without_routing_on_reads() -> void:
	var before := sim.tourism().access_routes().report()
	var w := window(BudgetWindow.new()) as BudgetWindow
	w._tourism_details.button_pressed=true
	check(labels(w).contains("Arrival capacity"),"budget exposes shared gateway seats")
	# Ordinary report and forecast reads must not advance pending search work.
	for i in 5:
		w.refresh()
		sim.tourism().venue_report(Vector2i(10,10))
	check_eq(sim.tourism().access_routes().report(),before)

func test_inspect_discloses_visitor_utility_units() -> void:
	var rows := sim.tourism()._state.records()
	rows[0].guests = 40
	TourismFixture.segment_rows(rows)
	check_eq(sim.tourism()._state.replace_records(rows),OK)
	sim.tourism()._publish()
	var out := {}
	QueryPanel._tourism_figures(out,sim,rows[0].anchor)
	check_eq(out.get("Visitor power"),"1 unit above building demand")
	check_eq(out.get("Visitor water"),"2 units above building demand")
	var power := sim.get_system(&"power") as PowerSystem
	check_eq(power.network_summary().visitor_demand,1)
	check(power.network_summary().has("spare_capacity"))

func test_accepted_zero_water_support_is_the_primary_limiter() -> void:
	var t:=sim.tourism()
	var rows:=t._state.records()
	for row: Dictionary in rows:
		row.guests=0
		row.day_visitors=0
		row.guest_segments=[0,0,0,0]
		row.day_segments=[0,0,0,0]
	check_eq(t._state.replace_records(rows),OK)
	t._features.utilities.month_id=0
	t._features.utilities.rows=TourismUtilities.snapshot(rows)
	for support: Dictionary in t._features.utilities.rows: support.limiting_reason="water"
	t._publish()
	var w:=window(BudgetWindow.new()) as BudgetWindow
	check_eq(w._tourism_limiter.text,"Main limit: Local power or water capacity")
	check_eq(w._tourism_values.guests[1].text,"0")
	check_gt(t.supported_forecast().physical_capacity,0)


## These classification fixtures author stock and accepted reservations explicitly.
## The separate native journey exercises the same UI through paid, scheduled service.
func limiter_stores(count: int, accepted: bool = true) -> void:
	for at in [Vector2i(10,10),Vector2i(30,30),Vector2i(50,50)]: sim.city.clear_footprint(at.x,at.y)
	for i in count:
		var at := Vector2i(10+i,10)
		TourismFixture.venue(sim.city,&"com_corner_store",at)
		TourismFixture.set_served(sim.city,at,true,true)
		for x in range(10+count): sim.city.building.put(x,9,Buildings.ROAD_FIRST)
	sim.tourism().reconcile_now()
	if accepted:
		var rows := sim.tourism()._state.records()
		for row in rows: row.day_visitors=1
		TourismFixture.segment_rows(rows)
		check_eq(sim.tourism()._state.replace_records(rows),OK)
		sim.tourism()._features.utilities.rows=TourismUtilities.snapshot(rows)
		sim.tourism()._publish()

func test_budget_limiter_accepted_day_only_is_not_a_service_failure() -> void:
	limiter_stores(1)
	var before := sim.snapshot()
	var w := window(BudgetWindow.new()) as BudgetWindow
	limiter_quote_oracle()
	check_eq(w._tourism_limiter.text,"Main limit: Demand at current taxes and season")
	var quote := sim.tourism().supported_forecast(-1,-1,true)
	check_eq(quote.get("stock_venues",-1),1)
	check_eq(quote.get("operating_venues",-1),1)
	check_eq(quote.get("closed_venues",-1),0)
	check_eq(quote.get("awaiting_support_venues",-1),0)
	check_eq(quote.get("support_limited_venues",-1),0)
	check_eq(quote.capacity,0)
	check_gt(quote.day_visitors,0)
	var work: int = sim.tourism().forecast_work().computations
	for i in 5: w.refresh()
	check_eq(sim.tourism().forecast_work().computations,work,"summary facts reuse the forecast cache")
	check_eq(sim.snapshot(),before,"limiter reads do not alter accepted simulation")

func test_budget_limiter_mixed_accepted_and_fresh_is_awaiting_not_utility() -> void:
	limiter_stores(1)
	TourismFixture.venue(sim.city,&"arcology_boddy",Vector2i(30,30))
	TourismFixture.set_served(sim.city,Vector2i(30,30),true,true)
	sim.tourism().reconcile_now()
	var w := window(BudgetWindow.new()) as BudgetWindow
	limiter_quote_oracle()
	check_eq(w._tourism_limiter.text,"Main limit: Awaiting monthly support plan")
	var quote := sim.tourism().supported_forecast(-1,-1,true)
	check_eq(quote.get("awaiting_support_venues",-1),1)
	check_eq(quote.get("support_limited_venues",-1),0)
	check_gt(quote.day_visitors,0)
	check_eq(quote.guests,0,"new resort cannot bypass the support lag")

func test_budget_limiter_distinguishes_absent_stock_and_closed_stock() -> void:
	limiter_stores(0)
	var w := window(BudgetWindow.new()) as BudgetWindow
	limiter_quote_oracle()
	check_eq(w._tourism_limiter.text,"Main limit: No tourism venues")
	TourismFixture.venue(sim.city,&"com_corner_store",Vector2i(10,10))
	TourismFixture.set_served(sim.city,Vector2i(10,10),false,false)
	sim.tourism().reconcile_now()
	w.refresh()
	check_eq(w._tourism_limiter.text,"Main limit: Closed venues: power, water, access or fire")
	var quote := sim.tourism().supported_forecast(-1,-1,true)
	check_eq(quote.get("stock_venues",-1),1)
	check_eq(quote.get("closed_venues",-1),1)
	check_eq(quote.get("awaiting_support_venues",-1),0)
	check_eq(quote.get("support_limited_venues",-1),0)

func test_budget_limiter_day_only_staff_shortfall() -> void:
	limiter_stores(12)
	sim.stats.population=100000
	sim.stats.neighbor_populations=PackedInt32Array([100000,100000,100000,100000])
	var w := window(BudgetWindow.new()) as BudgetWindow
	limiter_quote_oracle()
	check_eq(w._tourism_limiter.text,"Main limit: Available staff")
	var quote := sim.tourism().supported_forecast(-1,-1,true)
	check_eq(quote.capacity,0)
	check_gt(int(quote.get("staff_limited_day_venues",0)),0)

func test_budget_limiter_genuine_zero_water_is_not_awaiting() -> void:
	limiter_stores(1)
	var tourism := sim.tourism()
	var rows := tourism._state.records()
	rows[0].day_visitors=0
	TourismFixture.segment_rows(rows)
	check_eq(tourism._state.replace_records(rows),OK)
	tourism._features.utilities.rows[0].supported_days=0
	tourism._features.utilities.rows[0].limiting_reason="water"
	tourism._publish()
	var w := window(BudgetWindow.new()) as BudgetWindow
	limiter_quote_oracle()
	check_eq(w._tourism_limiter.text,"Main limit: Local power or water capacity")
	var quote := tourism.supported_forecast(-1,-1,true)
	check_eq(quote.get("support_limited_venues",-1),1)
	check_eq(quote.get("awaiting_support_venues",-1),0)
	check_eq(quote.day_visitors,0)

func limiter_quote_oracle() -> void:
	var quote := sim.tourism().supported_forecast()
	var values := {}
	for field in ["guests","day_visitors","capacity","occupancy","lodging_numerator","gaming_numerator","lodging_cents","gaming_cents"]: values[field]=quote[field]
	values["tax_ledger"]=sim.get_system(&"budget").estimated_ledger()
	values["simulation_hash"]=var_to_bytes(sim.snapshot()).hex_encode().sha256_text()
	print("LIMITER_QUOTE_ORACLE ",JSON.stringify(values))

func test_budget_limiter_day_capacity_is_distinct_from_beds() -> void:
	limiter_stores(1)
	sim.stats.population=100000
	sim.stats.cohorts[PopulationParams.WORK_COHORT_MIN]=100000
	sim.stats.tax_gaming=0
	sim.stats.average_land_value=255
	sim.city.land_value.put(5,5,255)
	var w := window(BudgetWindow.new()) as BudgetWindow
	var quote := sim.tourism().supported_forecast(-1,-1,true)
	check_eq(quote.capacity,0)
	check_gt(quote.day_capacity,0)
	check_eq(quote.day_visitors,quote.day_capacity,"fixture fills day places")
	check_eq(w._tourism_limiter.text,"Main limit: Available day-visitor capacity")
