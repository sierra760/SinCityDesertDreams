# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends RefCounted

const Params := preload("res://scripts/sim/data/advisor_params.gd")
const Snapshot := preload("res://scripts/sim/advisor_city_snapshot.gd")
const Civic := preload("res://scripts/sim/advisor_civic.gd")
const Economy := preload("res://scripts/sim/advisor_economy.gd")
const Development := preload("res://scripts/sim/advisor_development.gd")

## Current sidebar only. Historical newspaper/report RNG and events stay intact.
static func assess(ctx: SimContext) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if ctx == null or ctx.city == null: return out
	var observed := Snapshot.new(ctx.city)
	_emergency(ctx, out)
	_utility(ctx, out, false)
	_utility(ctx, out, true)
	Civic.assess(ctx, observed, out)
	Economy.assess(ctx, observed, out)
	Development.assess(ctx, observed, out)
	_merge_power_remedies(out)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.priority != b.priority: return int(a.priority) > int(b.priority)
		return String(a.kind) < String(b.kind))
	return out

static func _merge_power_remedies(out: Array[Dictionary]) -> void:
	var supply: Dictionary = {}
	for item in out:
		if item.kind == &"power_shortage": supply = item
	if supply.is_empty() or supply.reason == "reserve": return
	var affected: Array[String] = []
	for i in range(out.size() - 1, -1, -1):
		if out[i].reason == "power":
			affected.append(String(out[i].title))
			out.remove_at(i)
	if not affected.is_empty():
		affected.sort()
		supply["text"] = String(supply.text) + " Affected services: %s." % ", ".join(affected)

static func entry(out: Array[Dictionary], kind: StringName, title: String, reason: String, text: String, priority: int, urgent: bool = false) -> void:
	for item in out:
		if item.kind == kind: return
	out.append({"kind": kind, "title": title, "reason": reason, "text": text, "priority": priority, "urgent": urgent})

static func _emergency(ctx: SimContext, out: Array[Dictionary]) -> void:
	var stats := ctx.stats
	if stats.active_fires > 0:
		entry(out, &"fire_protection", "Fire", "emergency", "%d burning tiles reported. Go to Emergency to inspect the fire and dispatch crews; check nearby fire coverage before rebuilding." % stats.active_fires, Params.EMERGENCY, true)
	if stats.active_disaster != &"" and stats.active_disaster != &"fire":
		entry(out, &"emergency", "Emergency", "emergency", "%s is active. Go to Emergency to follow the incident and choose the available response." % AdvisorLines.kind_label(stats.active_disaster), Params.EMERGENCY + 1, true)

static func _utility(ctx: SimContext, out: Array[Dictionary], water: bool) -> void:
	var st := ctx.stats
	var capacity := st.water_capacity if water else st.power_capacity
	var demand := st.water_demand if water else st.power_demand
	var missing := st.unwatered_buildings if water else st.unpowered_buildings
	var kind: StringName = &"water_shortage" if water else &"power_shortage"
	var title := "Water" if water else "Power"
	var system := ctx.system(&"water" if water else &"power")
	var report: Dictionary = system.call("network_summary") if system != null and system.has_method("network_summary") else {}
	# Power conservation adds a component-local budget beyond raw generation.
	# Use the accepted allocator figure only when it describes these stats;
	# partial/restored contexts may have no matching supply report yet.
	if int(report.get("capacity", -1)) == capacity and int(report.get("demand", -1)) == demand:
		capacity = int(report.get("available_capacity", capacity))
	var local_shortage := bool(report.get("shortage", false))
	var observation := "Latest supply: %d demand against %d usable capacity." % [demand, capacity]
	var construction := "pumping or desalination" if water else "generation"
	if demand > capacity:
		entry(out, kind, title, "capacity", "%s Add %s to the networks short of supply; check connections too if some buildings remain unserved." % [observation, construction], Params.ESSENTIAL, true)
	elif missing > 0 or local_shortage:
		var symptom := "The last allocation left %d building%s unserved" % [missing, "" if missing == 1 else "s"] if missing > 0 else "The last allocation found a local shortage"
		entry(out, kind, title, "distribution", "%s despite city-wide spare capacity. Check network connections and supply on each separate network before adding %s." % [symptom, construction], Params.ESSENTIAL, true)
	elif demand > 0 and (capacity - demand) * 100 < capacity * Params.RESERVE_PERCENT:
		entry(out, kind, title, "reserve", "%s Less than %d%% reserve remains; plan extra %s before expanding demand." % [observation, Params.RESERVE_PERCENT, construction], Params.WARNING)
