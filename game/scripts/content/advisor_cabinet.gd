# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends RefCounted

const People := preload("res://scripts/content/advisor_cast.gd")
const Params := preload("res://scripts/sim/data/advisor_params.gd")
const MOOD_RANK := {"critical":0, "concerned":1, "neutral":2, "pleased":3, "delighted":4}
## Presentation thresholds, not changes to simulation balance.
const EXCELLENT_RESERVE_PERCENT := 20
const LOW_CITY_INDEX := 32
const SEVERE_CITY_INDEX := 192
const EXCELLENT_HEALTH := 75
const EXCELLENT_EDUCATION := 120
const SEVERE_HEALTH := 35
const SEVERE_EDUCATION := 50
const SEVERE_UNEMPLOYMENT := 40
const EXCELLENT_UNEMPLOYMENT := 3

## Group one existing assessment without rewriting its diagnoses or remedies.
## Only published scalar state and read-only trip counters are observed here.
static func assess(city: City, stats: CityStats, advice: Array, transport: SimSystem = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var month := 0
	if city != null:
		@warning_ignore("integer_division")
		month = city.day / GameClock.DAYS_PER_MONTH
	for id: String in People.ORDER:
		var issues: Array[Dictionary] = []
		var priority := 0
		var emergency := false
		for entry: Dictionary in advice:
			if People.department_of(String(entry.get("kind", ""))) != id: continue
			issues.append(entry)
			priority = maxi(priority, int(entry.get("priority", 0)))
			emergency = emergency or String(entry.get("reason", "")) == "emergency"
		var observation := _observation(id, city, stats, transport)
		var mood: String = observation.mood
		for issue: Dictionary in issues:
			var issue_mood := "neutral"
			if bool(issue.get("urgent", false)) or int(issue.get("priority", 0)) >= Params.ESSENTIAL:
				issue_mood = "critical"
			elif int(issue.get("priority", Params.WARNING)) >= Params.WARNING:
				issue_mood = "concerned"
			if int(MOOD_RANK[issue_mood]) < int(MOOD_RANK[mood]): mood = issue_mood
		if emergency: mood = "critical"
		# Older outcomes don't establish today's service during an outage.
		# Shared power remedies remain in Utilities instead of being repeated.
		if stats != null and stats.unpowered_buildings > 0 and id in ["safety","community"] and int(MOOD_RANK[mood]) > 2:
			mood = "neutral"
			observation.facts.append("An open power issue needs review in Utilities; older outcomes do not establish current service.")
		result.append({"id":id, "mood":mood, "speaker":People.speaker(id,mood,month,emergency),
			"issues":issues, "facts":observation.facts, "priority":priority,
			"attention":mood in ["critical","concerned"]})
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if MOOD_RANK[a.mood] != MOOD_RANK[b.mood]: return MOOD_RANK[a.mood] < MOOD_RANK[b.mood]
		if a.priority != b.priority: return int(a.priority) > int(b.priority)
		return People.ORDER.find(a.id) < People.ORDER.find(b.id))
	return result

static func _sampled(stats: CityStats, keys: Array) -> bool:
	if stats.population <= 0: return false
	for key in keys:
		var samples: Variant = stats.history.get(StringName(key), [])
		if samples.is_empty(): return false
	return true

static func _observation(id: String, city: City, st: CityStats, transport: SimSystem) -> Dictionary:
	var out := {"mood":"neutral", "facts":[]}
	if city == null or st == null:
		out.facts.append("Load a city to hear from the advisors.")
		return out
	if st.population == 0:
		out.facts.append("No residents yet. Advice will follow as the town develops.")
	elif st.history.is_empty():
		out.facts.append("Monthly reports are still building up.")
	match id:
		"finance":
			out.facts.append("Current treasury: $%d." % city.funds)
			if city.funds < 0: out.mood = "critical"
			elif _sampled(st,["money"]):
				out.mood = "pleased"
				var income := 0
				var expenses := 0
				for key: Variant in st.last_year_ledger:
					if StringName(key) in BudgetParams.EXPENSE_KEYS: expenses += int(st.last_year_ledger[key])
					else: income += int(st.last_year_ledger[key])
				if expenses > 0:
					out.facts.append("Last settled year: $%d income and $%d expenses." % [income,expenses])
					if income >= expenses and city.funds * 2 >= expenses: out.mood = "delighted"
		"utilities":
			var active := 0
			var excellent := true
			for pair: Array in [["Power",st.power_capacity,st.power_demand,st.unpowered_buildings],["Water",st.water_capacity,st.water_demand,st.unwatered_buildings]]:
				var capacity: int = pair[1]
				var demand: int = pair[2]
				var missing: int = pair[3]
				if demand > 0 or missing > 0:
					active += 1
					out.facts.append("Latest %s allocation: %d demand; %d building%s unserved." % [String(pair[0]).to_lower(),demand,missing,"" if missing == 1 else "s"])
					if missing > 0: out.mood = "critical"
					excellent = excellent and capacity > 0 and (capacity-demand)*100 >= capacity*EXCELLENT_RESERVE_PERCENT
			if active > 0 and out.mood != "critical": out.mood = "delighted" if active == 2 and excellent else "pleased"
		"transport":
			if transport != null and transport.has_method("trips_attempted") and transport.has_method("trips_completed"):
				var attempts: int = transport.call("trips_attempted")
				var completed: int = transport.call("trips_completed")
				if attempts > 0 and _sampled(st,["traffic"]):
					out.facts.append("Last transport sample: %d of %d trips completed; traffic %d/255." % [completed,attempts,st.average_traffic])
					out.mood = "pleased"
					if completed == attempts and st.average_traffic <= LOW_CITY_INDEX: out.mood = "delighted"
					if (attempts-completed)*100 >= attempts*Params.ROUTE_FAILURE_PERCENT or st.average_traffic >= NewspaperParams.TRAFFIC_WARNING: out.mood = "concerned"
					if (attempts-completed)*2 >= attempts or st.average_traffic >= SEVERE_CITY_INDEX: out.mood = "critical"
				else: out.facts.append("No transport assessment yet. Routes with no sampled trips are not rated as successful.")
		"safety":
			if _sampled(st,["crime"]):
				out.facts.append("Last measured crime: %d/255. Active fires: %d." % [st.average_crime,st.active_fires])
				out.mood = "pleased"
				if st.average_crime <= LOW_CITY_INDEX and st.funding_of(&"police") == 100 and st.funding_of(&"fire") == 100: out.mood = "delighted"
				if st.average_crime >= NewspaperParams.CRIME_WARNING: out.mood = "concerned"
				if st.average_crime >= SEVERE_CITY_INDEX: out.mood = "critical"
			if st.active_fires > 0 or st.active_disaster != &"": out.mood = "critical"
		"community":
			if _sampled(st,["health","education"]):
				out.facts.append("Last measured life expectancy: %d years; education: %d." % [st.life_expectancy,st.education_quotient])
				out.mood = "pleased"
				if st.life_expectancy >= EXCELLENT_HEALTH and st.education_quotient >= EXCELLENT_EDUCATION and st.funding_of(&"health") == 100 and st.funding_of(&"schools") == 100: out.mood = "delighted"
				if st.life_expectancy < Params.POOR_HEALTH or st.education_quotient < Params.POOR_EDUCATION: out.mood = "concerned"
				if st.life_expectancy <= SEVERE_HEALTH or st.education_quotient <= SEVERE_EDUCATION: out.mood = "critical"
		"planning":
			if _sampled(st,["unemployment","pollution"]):
				out.facts.append("Last measured unemployment: %d%%; pollution: %d/255." % [st.unemployment,st.average_pollution])
				out.mood = "pleased"
				var strong_demand: bool = st.demand.x > 0 and st.demand.y > 0 and st.demand.z > 0
				var visitors_supported: bool = st.tourist_capacity == 0 or (not st.history.get(&"tourist_occupancy",PackedInt32Array()).is_empty() and st.tourist_occupancy >= 75 and st.tourist_reputation_milli >= 80000)
				if st.unemployment <= EXCELLENT_UNEMPLOYMENT and st.average_pollution <= LOW_CITY_INDEX and strong_demand and visitors_supported: out.mood = "delighted"
				if st.unemployment >= NewspaperParams.UNEMPLOYMENT_WARNING or st.average_pollution >= NewspaperParams.POLLUTION_WARNING: out.mood = "concerned"
				if st.unemployment >= SEVERE_UNEMPLOYMENT or st.average_pollution >= SEVERE_CITY_INDEX: out.mood = "critical"
	if out.facts.is_empty(): out.facts.append("No department readings yet. Advice will follow as the town develops.")
	return out
