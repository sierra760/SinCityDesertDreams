# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

var contexts: Array[SimContext] = []

func cabinet() -> GDScript:
	var path := "res://scripts/content/advisor_cabinet.gd"
	check(ResourceLoader.exists(path), "six-department cabinet exists")
	return load(path) if ResourceLoader.exists(path) else null

func context() -> SimContext:
	var ctx := make_context(flat_city(10000))
	contexts.append(ctx)
	var st := ctx.stats
	st.population = 100
	st.power_demand = 100; st.power_capacity = 110
	st.water_demand = 100; st.water_capacity = 110
	st.average_traffic = 50; st.average_crime = 50
	st.life_expectancy = 65; st.education_quotient = 100
	st.unemployment = 5; st.average_pollution = 50
	for key in [&"money", &"crime", &"traffic", &"health", &"education", &"unemployment", &"pollution"]:
		st.history[key] = PackedInt32Array([1])
	var transport := TransportSystem.new()
	transport.setup(ctx)
	transport._attempted = 10; transport._completed = 9
	ctx.systems[&"transport"] = transport
	return ctx

func after_each() -> void:
	for ctx in contexts: ctx.systems.clear()
	contexts.clear()

func rows(script: GDScript, ctx: SimContext, advice: Array = []) -> Array:
	return script.assess(ctx.city, ctx.stats, advice, ctx.system(&"transport"))

func by_id(items: Array, id: String) -> Dictionary:
	for item: Dictionary in items:
		if item.id == id: return item
	return {}

func test_related_topics_share_one_unique_advisor_without_losing_findings() -> void:
	var script := cabinet()
	if script == null: return
	var ctx := context()
	var issues := [{"kind":"power_shortage", "priority":900, "urgent":true, "text":"Power evidence."},
		{"kind":"water_shortage", "priority":900, "urgent":true, "text":"Water evidence."},
		{"kind":"schools", "priority":500, "text":"School evidence."},
		{"kind":"hospitals", "priority":500, "text":"Care evidence."}]
	var before := var_to_bytes(issues)
	var result := rows(script, ctx, issues)
	check_eq(result.size(), 6)
	check_eq(by_id(result,"utilities").issues.size(), 2)
	check_eq(by_id(result,"community").issues.size(), 2)
	var names: Dictionary = {}
	for item: Dictionary in result: names[item.speaker.name] = true
	check_eq(names.size(), 6, "one distinct person per department")
	check_eq(var_to_bytes(issues), before, "original diagnosis fields and order untouched")
	check_eq(by_id(result,"utilities").issues[0].text, "Power evidence.")
	check_eq(result[0].id, "utilities", "worst department first")

func test_empty_and_unsampled_cities_are_neutral_not_successful() -> void:
	var script := cabinet()
	if script == null: return
	var ctx := context()
	ctx.stats.history.clear()
	ctx.stats.power_demand = 0; ctx.stats.water_demand = 0
	(ctx.system(&"transport") as TransportSystem)._attempted = 0
	for row: Dictionary in rows(script,ctx): check_eq(row.mood,"neutral",row.id)
	for row: Dictionary in script.assess(null,null,[]): check_eq(row.mood,"neutral")

func test_five_moods_follow_evidence_and_the_worst_open_issue() -> void:
	var script := cabinet()
	if script == null: return
	var ctx := context()
	for item: Dictionary in rows(script,ctx): check_eq(item.mood,"pleased",item.id)
	var st := ctx.stats
	st.last_year_ledger = {&"taxes_residential":2000, &"police":1000}
	st.power_capacity = 150; st.water_capacity = 150
	st.average_traffic = 20; st.average_crime = 20
	(ctx.system(&"transport") as TransportSystem)._completed = 10
	st.life_expectancy = 80; st.education_quotient = 130
	st.unemployment = 2; st.average_pollution = 20; st.demand = Vector3i(100,100,100)
	for item: Dictionary in rows(script,ctx): check_eq(item.mood,"delighted",item.id)
	var keys := {"finance":"taxes", "utilities":"water_shortage", "transport":"traffic", "safety":"police", "community":"schools", "planning":"tourism"}
	for id: String in keys:
		var issue := {"kind":keys[id], "reason":"funding", "priority":500, "text":"A measured problem."}
		check_eq(by_id(rows(script,ctx,[issue]),id).mood,"concerned",id)
		issue.priority = 100
		check_eq(by_id(rows(script,ctx,[issue]),id).mood,"neutral", "growth opportunity is not a crisis")
		issue.urgent = true
		check_eq(by_id(rows(script,ctx,[issue]),id).mood,"critical",id)

func test_severe_outcomes_and_recovery_change_portraits_immediately() -> void:
	var script := cabinet()
	if script == null: return
	var ctx := context()
	ctx.city.funds = -1
	ctx.stats.average_traffic = 200; ctx.stats.average_crime = 200
	ctx.stats.life_expectancy = 30; ctx.stats.unemployment = 50
	ctx.stats.unpowered_buildings = 1
	for item: Dictionary in rows(script,ctx): check_eq(item.mood,"critical",item.id)
	ctx.city.funds = 10000
	ctx.stats.average_traffic = 50; ctx.stats.average_crime = 50
	ctx.stats.life_expectancy = 65; ctx.stats.unemployment = 5
	ctx.stats.unpowered_buildings = 0
	for item: Dictionary in rows(script,ctx): check_eq(item.mood,"pleased", "recovery needs no saved mood state")

func test_transport_without_attempts_never_receives_a_success_portrait() -> void:
	var script := cabinet()
	if script == null: return
	var ctx := context()
	(ctx.system(&"transport") as TransportSystem)._attempted = 0
	check_eq(by_id(rows(script,ctx),"transport").mood,"neutral")

func test_repeated_cabinet_reads_preserve_stats_rng_events_and_sim_systems() -> void:
	var script := cabinet()
	if script == null: return
	var ctx := context()
	var transport := ctx.system(&"transport") as TransportSystem
	var before := var_to_bytes([ctx.stats.to_dict(),[ctx.city.funds,ctx.city.day,ctx.city.building.data,ctx.city.flags.data,ctx.city.facilities],ctx.rng.state(),ctx.events.news,ctx.events.notices,transport.save()])
	var first := rows(script,ctx)
	for i in 5: check_eq(rows(script,ctx),first)
	check_eq(var_to_bytes([ctx.stats.to_dict(),[ctx.city.funds,ctx.city.day,ctx.city.building.data,ctx.city.flags.data,ctx.city.facilities],ctx.rng.state(),ctx.events.news,ctx.events.notices,transport.save()]),before)
