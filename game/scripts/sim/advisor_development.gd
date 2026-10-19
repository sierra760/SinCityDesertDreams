# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends RefCounted

const Params := preload("res://scripts/sim/data/advisor_params.gd")
const Civic := preload("res://scripts/sim/advisor_civic.gd")

static func assess(ctx: SimContext, observed: RefCounted, out: Array[Dictionary]) -> void:
	var recreation: int = observed.count_keys(ZoneParams.RECREATION_KEYS)
	var residential_cap: int = (ZoneParams.RES_CAP_BASE + recreation) * ZoneParams.RES_CAP_STEP
	if observed.units.x * 100 >= residential_cap * Params.GROWTH_CAP_PERCENT:
		Civic._add(out, &"recreation", "Recreation", "growth", "Housing is near the recreation-based growth limit. A large park, zoo, stadium or marina raises this limit; small parks provide greenery but do not raise it.", Params.OPPORTUNITY)
	var industrial_cap := (ZoneParams.IND_CAP_BASE + int(observed.counts[Buildings.RAIL_STATION]) + int(observed.counts[Buildings.CRANE])) * ZoneParams.IND_CAP_STEP
	var neighbors := ctx.system(&"neighbors")
	var links := int(neighbors.call("link_count")) if neighbors != null and neighbors.has_method("link_count") else 0
	if observed.units.z * 100 >= industrial_cap * Params.GROWTH_CAP_PERCENT:
		var text := "Industry is near its station-and-crane growth limit. A rail station raises the limit; connected road or rail links to neighbors can also help trade."
		if links > 0: text = "Industry is near its station-and-crane growth limit. Inspect rail-station provision before expanding industrial zoning; regional links already exist."
		Civic._add(out, &"connections", "Industry", "growth", text, Params.OPPORTUNITY)
	var markets := 0
	for population in ctx.stats.neighbor_populations:
		if population > 0: markets += 1
	@warning_ignore("integer_division")
	var commercial_cap: int = (ZoneParams.COM_CAP_BASE + observed.count_keys(ZoneParams.STATION_KEYS) / ZoneParams.COM_STATIONS_PER_STEP + markets) * ZoneParams.COM_CAP_STEP
	if observed.units.y * 100 >= commercial_cap * Params.GROWTH_CAP_PERCENT:
		Civic._add(out, &"commerce", "Commerce", "growth", "Commerce is near its station-and-regional-market growth limit. Inspect connected transit provision and regional markets before zoning more shops.", Params.OPPORTUNITY)
	_ports(ctx, observed, out)
	_tourism(ctx, out)

static func _ports(ctx: SimContext, observed: RefCounted, out: Array[Dictionary]) -> void:
	var ports := ctx.system(&"ports")
	var report: Dictionary = ports.call("advisor_port_observations") if ports != null and ports.has_method("advisor_port_observations") else {}
	for kind in [Zones.AIRPORT, Zones.SEAPORT]:
		var tiles := int(observed.airport_tiles) if kind == Zones.AIRPORT else int(observed.seaport_tiles)
		if tiles == 0: continue
		var title := "Airport" if kind == Zones.AIRPORT else "Seaport"
		var key: StringName = &"airport" if kind == Zones.AIRPORT else &"seaport"
		var found := false
		var operating := false
		var has_power := false
		for row: Dictionary in report.get("rows", []):
			if int(row.kind) != kind: continue
			found = true
			operating = operating or bool(row.operating)
			has_power = has_power or bool(row.powered)
		if bool(report.get("known", false)) and found and operating: continue
		var action := "Inspect the existing airport's power, contiguous zone and complete runway before zoning another airport."
		if kind == Zones.SEAPORT: action = "Inspect the existing seaport's power, crane and shore access before zoning another; inland water alone does not establish a shipping route."
		if bool(report.get("known", false)) and found and not has_power:
			action = "The existing %s has no operating powered zone. Restore power, then inspect its other operating requirements." % title.to_lower()
		Civic._add(out, key, title, "existing", "%d tiles are zoned. %s" % [tiles, action], Params.OPPORTUNITY)

static func _tourism(ctx: SimContext, out: Array[Dictionary]) -> void:
	var tourism := ctx.system(&"tourism")
	if tourism == null: return
	var utilities: Dictionary = tourism.call("utility_report") if tourism.has_method("utility_report") else {}
	var staffing: Dictionary = tourism.call("staffing_report") if tourism.has_method("staffing_report") else {}
	var limited := int(utilities.get("limited_venues", 0))
	var labor_limited := int(staffing.get("supported_capacity", 0)) < int(staffing.get("planned_guests", 0)) or int(staffing.get("supported_day_capacity", 0)) < int(staffing.get("planned_day_visitors", 0))
	if limited > 0:
		Civic._add(out, &"tourism", "Tourism", "utilities", "Latest accepted visitor plan: %d venues are limited by utilities. Review Tourism's support figures and the relevant utility networks before adding beds or cutting visitor taxes." % limited)
	elif labor_limited:
		Civic._add(out, &"tourism", "Tourism", "staffing", "The latest accepted visitor plan has less staffed capacity than planned attendance. Review Tourism staffing and resident/neighbor labor before adding more resort capacity.")
