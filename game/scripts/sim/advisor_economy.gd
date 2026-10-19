# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends RefCounted

const Params := preload("res://scripts/sim/data/advisor_params.gd")
const Civic := preload("res://scripts/sim/advisor_civic.gd")

static func assess(ctx: SimContext, observed: RefCounted, out: Array[Dictionary]) -> void:
	_transport(ctx, out)
	_jobs(ctx, out)
	_finance(ctx, observed, out)
	_environment(ctx, out)
	_poll(ctx, out)

static func _transport(ctx: SimContext, out: Array[Dictionary]) -> void:
	var system := ctx.system(&"transport")
	if system != null and system.has_method("trips_attempted"):
		var attempts := int(system.call("trips_attempted"))
		var failed := maxi(0, attempts - int(system.call("trips_completed")))
		if attempts > 0 and failed * 100 >= attempts * Params.ROUTE_FAILURE_PERCENT:
			Civic._add(out, &"road_and_rail", "Transport", "access", "Last transport sample: %d of %d trips could not reach a destination. Check connected roads, station access and routes to jobs before adding more transit buildings." % [failed, attempts], Params.SERIOUS)
	if ctx.stats.average_traffic >= NewspaperParams.TRAFFIC_WARNING:
		Civic._add(out, &"traffic", "Traffic", "congestion", "Last measured traffic averages %d/255. Inspect the busiest links; connected alternatives, buses or rail can relieve a bottleneck." % ctx.stats.average_traffic)

static func _jobs(ctx: SimContext, out: Array[Dictionary]) -> void:
	if ctx.stats.unemployment < NewspaperParams.UNEMPLOYMENT_WARNING: return
	var jobs := PopulationSystem.reachable_jobs(ctx)
	var shortage := PopulationSystem.job_shortfall_percent(ctx.stats, jobs)
	var measured := "Last measured unemployment is %d%%." % ctx.stats.unemployment
	if shortage >= NewspaperParams.UNEMPLOYMENT_WARNING:
		Civic._add(out, &"unemployment", "Jobs", "jobs", "%s Local jobs and neighbor commuting places fall short of working-age residents. Develop suitable commercial, industrial or agricultural land, or improve regional links; avoid expanding a sector with weak demand." % measured, Params.SERIOUS)
	elif _has(out, &"road_and_rail"):
		# One access remedy, with its employment consequence in the same entry.
		for item in out:
			if item.kind == &"road_and_rail":
				item["text"] = "%s Jobs exist in the city-wide totals, but the sampled routes need attention. %s" % [measured, item.text]
		# The employment diagnosis remains queryable without repeating the fix.
		Civic._add(out, &"unemployment", "Jobs", "access", "%s City-wide job totals are sufficient; see Transport for the measured access problem. Totals do not guarantee that every household can reach work." % measured)
	else:
		Civic._add(out, &"unemployment", "Jobs", "employment", "%s Aggregate job totals are sufficient. Inspect abandonment and local connections; adding more job zones alone may not resolve the next monthly employment reading." % measured)

static func _finance(ctx: SimContext, observed: RefCounted, out: Array[Dictionary]) -> void:
	var budget := ctx.system(&"budget")
	var outlook: Dictionary = budget.call("advisor_outlook", observed.counts, observed.tiles, observed.wear) if budget != null and budget.has_method("advisor_outlook") else {}
	var deficit := int(outlook.get("net", 0)) < 0
	if ctx.city.funds < 0:
		Civic._add(out, &"treasury", "Treasury", "cash", "Treasury cash is $%d. Review Budget income, service funding and debt costs before committing to more construction or tax cuts." % ctx.city.funds, Params.SERIOUS)
	elif deficit:
		Civic._add(out, &"treasury", "Treasury", "outlook", "Annual outlook: $%d income against $%d expenses at current settings and recent business. Check Budget before expanding or cutting taxes; visitor receipts and fares can vary." % [int(outlook.income), int(outlook.expenses)], Params.SERIOUS)
	var rates := OrdinanceSystem.effective_rates(ctx.stats)
	var labels: Array[String] = []
	var names := ["Residential", "Commercial", "Industrial"]
	var actual := [ctx.stats.tax_residential, ctx.stats.tax_commercial, ctx.stats.tax_industrial]
	for i in 3:
		if observed.units[i] > 0 and rates[i] >= Params.TAX_WARNING and ctx.stats.demand[i] <= 0:
			labels.append("%s %d%% (felt rate %d%%)" % [names[i], actual[i], rates[i]])
	if (ctx.stats.agricultural_lots > 0 or observed.agriculture > 0) and ctx.stats.tax_agricultural >= Params.TAX_WARNING and ctx.stats.demand_agricultural <= 0:
		labels.append("Agricultural %d%%" % ctx.stats.tax_agricultural)
	if ctx.stats.tourist_capacity > 0 or ctx.stats.tourists > 0:
		if ctx.stats.tax_occupancy >= Params.VISITOR_TAX_WARNING: labels.append("Occupancy %d%%" % ctx.stats.tax_occupancy)
		if ctx.stats.tax_gaming >= Params.VISITOR_TAX_WARNING: labels.append("Gaming %d%%" % ctx.stats.tax_gaming)
	if not labels.is_empty():
		var action := "Check Budget before reducing rates; the treasury or annual outlook is already negative." if deficit or ctx.city.funds < 0 else "Compare demand and the Budget outlook before easing a rate; the city still needs to fund its services."
		Civic._add(out, &"taxes", "Taxes", "rates", "%s. These rates discourage the affected sectors; %s" % [", ".join(labels), action])

static func _environment(ctx: SimContext, out: Array[Dictionary]) -> void:
	if ctx.stats.average_pollution >= NewspaperParams.POLLUTION_WARNING:
		var action := "Inspect the pollution map, separate homes from emitters, add greenery and consider cleaner power."
		if not bool(ctx.stats.ordinances.get(&"pollution_controls", false)): action += " Pollution Controls can reduce emissions."
		Civic._add(out, &"pollution", "Pollution", "pollution", "Last measured pollution averages %d/255. %s" % [ctx.stats.average_pollution, action])
	if ctx.stats.population > 0 and ctx.stats.water_demand > 0 and PopulationSystem._untreated_water(ctx):
		Civic._add(out, &"water_treatment", "Water treatment", "treatment", "The latest water report shows inadequate treatment. Add treatment capacity to protect health; more pumping alone does not clean the water.")

static func _poll(ctx: SimContext, out: Array[Dictionary]) -> void:
	if ctx.stats.approval >= NewspaperParams.APPROVAL_WARNING: return
	var population := ctx.system(&"population")
	if population == null or not population.has_method("complaints"): return
	var ranking: Array = population.call("complaints")
	if ranking.is_empty(): return
	var complaint: Dictionary = ranking[0]
	Civic._add(out, &"approval", "Approval", "poll", "Approval was %d%% at the last poll; %s led the recorded complaints. Compare that result with today's warnings before deciding what still needs attention." % [ctx.stats.approval, String(complaint.get("name", "city conditions"))])

static func _has(out: Array[Dictionary], kind: StringName) -> bool:
	for item in out:
		if item.kind == kind: return true
	return false
