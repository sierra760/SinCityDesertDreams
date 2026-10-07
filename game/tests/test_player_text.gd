# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## Player-facing wording of news, notices, advice and report windows: names,
## articles, money and grammar. Display text only; saved keys stay as they are.

const NewspaperSystem := preload("res://scripts/sim/newspaper_system.gd")


func _values(kind: StringName, args: Dictionary, mayor: String = "Ada") -> Dictionary:
	return NewsStories.values_for(kind, args, "Dry Gulch", mayor, 1990)


func _all_headlines(kind: StringName, args: Dictionary, mayor: String = "Ada") -> Array[String]:
	var out: Array[String] = []
	var values := _values(kind, args, mayor)
	for h in NewsStories.headline_variants(kind, args):
		out.append(NewsStories.fill(String(h), values, true))
	return out


# ── Gaming resort launch ─────────────────────────────────────────────────

func test_resort_launch_counts_residents_not_resorts() -> void:
	var args := {"resorts": 1, "residents": 4200, "refund": 10000}
	var notice := NoticeLines.render(&"exodus", args, "Dry Gulch", "Ada", 2051)
	check(String(notice["body"]).contains("taking 4,200 residents"), notice["body"])
	check_eq(NewsStories.template_key(&"resort_launch"), &"resort_launch", "its own story")
	check_eq(NewsStories.headline_variants(&"resort_launch").size(), NewsStories.headline_variants(&"exodus").size(),
		"the headline pick draws from the same range as before")
	check_eq(NewsStories.priority_of(&"resort_launch"), NewsStories.priority_of(&"exodus"))
	check_eq(NewsStories.decay_of(&"resort_launch"), NewsStories.decay_of(&"exodus"))
	var body := NewsStories.body(&"resort_launch", args, _values(&"resort_launch", args))
	check(body.contains("carrying 4,200 residents"), body)
	check(not body.contains("Families"), body)
	for h in _all_headlines(&"resort_launch", args):
		check(not h.contains("Families"), h)
	check(_all_headlines(&"resort_launch", args).has("4,200 Residents Depart Aboard Departing Resorts"))


# ── Unnamed mayor ────────────────────────────────────────────────────────

func test_unnamed_mayor_reads_as_the_mayor() -> void:
	for mayor in ["Mayor", "", "  "]:
		var heads := _all_headlines(&"approval_vote", {"approval": 61}, mayor)
		for h in heads:
			check(not h.contains("Mayor Mayor") and not h.contains("Mayor  "), h)
		check(heads.has("Annual Poll: 61 Percent Approve Of The Mayor"), str(heads))
		check(heads.has("Voters Weigh In; The Mayor Scores 61"), str(heads))
		var body := NewsStories.body(&"approval_vote", {"approval": 61}, _values(&"approval_vote", {"approval": 61}, mayor))
		check(body.begins_with("The annual approval poll put the mayor at 61 percent"), body)
		var abandon := NewsStories.body(&"abandonment_wave", {"count": 3}, _values(&"abandonment_wave", {"count": 3}, mayor))
		check(abandon.contains("The mayor said the matter was under review"), abandon)
	var named := NewsStories.body(&"approval_vote", {"approval": 61}, _values(&"approval_vote", {"approval": 61}))
	check(named.contains("Mayor Ada at 61 percent"), "a named mayor keeps the name: " + named)
	var notice := NoticeLines.render(&"approval_milestone", {"approval": 80}, "Dry Gulch", "Mayor", 1990)
	check(String(notice["body"]).contains("gives the mayor an approval rating"), notice["body"])
	var gift := NoticeLines.render(&"reward_offered", {"key": &"mayors_residence"}, "Dry Gulch", "Mayor", 1990)
	check(String(gift["body"]).contains("build the mayor a proper residence"), gift["body"])
	var rng := SimRng.new(1)
	for i in 12:
		var line := AdvisorLines.line(&"approval", _values(&"", {}, "Mayor"), rng)
		check(not line.contains("Mayor Mayor") and not line.contains("{"), line)
		if line.contains("not happy"):
			check(line.begins_with("Mayor, the town is not happy with you."), line)


# ── Places ───────────────────────────────────────────────────────────────

func test_city_wide_reports_happen_in_the_city() -> void:
	for kind in [&"zone_boom", &"crime_wave", &"pollution_alert", &"traffic_jam", &"abandonment_wave"]:
		check_eq(_values(kind, {"level": 120})["place"], "Dry Gulch", "%s is city-wide" % kind)
	check_eq(_values(&"zone_boom", {"count": 3, "x": 64, "y": 64})["place"], "downtown", "a located report keeps its district")
	check_eq(_values(&"generic", {})["place"], "the edge of town")
	check_eq(NewsStories.place_text({}), "the edge of town")


func test_headlines_title_case_lowercase_values() -> void:
	var heads := _all_headlines(&"zone_boom", {"x": 100, "y": 20})
	check(heads.has("Building Boom Sweeps The Northeast Corner"), str(heads))
	check(heads.has("Several New Lots Break Ground This Month"), str(heads))
	var body := NewsStories.body(&"prison_escape", {"x": 10, "y": 10}, _values(&"prison_escape", {"x": 10, "y": 10}))
	check(body.begins_with("Several inmates escaped the prison near the northwest corner"), body)


# ── Articles, names and money ────────────────────────────────────────────

func test_disaster_notices_use_natural_phrases() -> void:
	var expected := {
		&"fire": "of a fire near", &"flood": "of flash flooding near", &"riot": "of a riot near",
		&"hazard": "of toxic contamination near", &"earthquake": "of an earthquake near",
		&"monster": "of Tsawhawbitts near", &"meltdown": "of a nuclear meltdown near",
		&"microwave": "of a stray microwave beam near", &"mass_riots": "of riots near",
		&"plane_crash": "of a plane crash near",
	}
	for kind in DisasterParams.KINDS:
		check(NoticeLines.DISASTER_PHRASES.has(kind), "phrase for %s" % kind)
		var spec := NoticeLines.render(&"disaster", {"kind": String(kind), "x": 64, "y": 64}, "Dry Gulch", "Ada", 1990)
		check(not String(spec["body"]).contains("{") and not String(spec["title"]).contains("{"), spec["body"])
		if expected.has(kind):
			check(String(spec["body"]).contains(String(expected[kind])), spec["body"])
	check_eq(DisasterParams.display_name(&"hazard"), "Toxic Contamination")
	check_eq(DisasterParams.display_name(&"microwave"), "Microwave Beam")
	check_eq(DisasterParams.display_name(&"meltdown"), "Nuclear Meltdown")
	check_eq(DisasterParams.display_name(&"monster"), "Tsawhawbitts")
	check_eq(DisasterParams.display_name(&"plane_crash"), "Plane Crash")
	check(DisasterParams.KINDS.has(&"hazard"), "the saved key is unchanged")
	var title := NoticeLines.render(&"disaster", {"kind": "hazard"}, "Dry Gulch", "Ada", 1990)
	check_eq(title["title"], "Emergency: Toxic Contamination")
	check(_all_headlines(&"disaster_started", {"kind": "microwave"}).has("Microwave Receiver Scorches Neighborhood"))


func test_military_offer_articles() -> void:
	var expected := {&"air": "an air force base", &"army": "an army base", &"naval": "a naval base",
		&"missile": "a missile base"}
	for kind in expected:
		var spec := NoticeLines.render(&"reward_offered", {"key": RewardParams.MILITARY_KEY, "kind": String(kind)},
			"Dry Gulch", "Ada", 1990)
		check(String(spec["body"]).contains("propose " + String(expected[kind])), spec["body"])


func test_ordinance_milestone_and_money_wording() -> void:
	var ordinance := {"key": "pollution_controls", "name": "Pollution Controls"}
	var body := NewsStories.body(&"ordinance_enacted", ordinance, _values(&"ordinance_enacted", ordinance))
	check(body.contains("adopted the Pollution Controls ordinance"), body)
	var milestone := {"key": "mayors_residence", "population": 2000}
	check_eq(NewsStories.kind_text(&"city_milestone", milestone), "Mayor's Residence")
	check_eq(NewsStories.kind_text(&"city_milestone", {"key": "military_base"}), "Military Base")
	var deficit := {"funds": -1250, "year": 1990}
	var text := NewsStories.body(&"treasury_deficit", deficit, _values(&"treasury_deficit", deficit))
	check(text.contains("leaving the treasury at -$1,250"), text)
	var rng := SimRng.new(4)
	var seen_pollution := false
	for i in 30:
		var line := AdvisorLines.line(&"pollution", _values(&"", {}), rng)
		check(not line.contains("a pollution ordinance"), line)
		seen_pollution = seen_pollution or line.contains("the Pollution Controls ordinance")
	check(seen_pollution, "the pollution advice names the ordinance")


func test_crime_story_has_no_incident_count() -> void:
	var args := {"level": 180}
	for h in _all_headlines(&"crime_wave", args):
		check(not h.contains("180"), h)
	var body := NewsStories.body(&"crime_wave", args, _values(&"crime_wave", args))
	check(not body.contains("180"), body)
	check(body.contains("a sharp rise in incidents around Dry Gulch"), body)


func test_budget_notices_explain_the_way_out() -> void:
	var bankrupt := NoticeLines.render(&"bankruptcy", {"funds": -150000, "debt": 30000, "year": 2002}, "Dry Gulch", "Ada", 2002)
	check(String(bankrupt["body"]).contains("back up to at least " + NoticeLines.money(BudgetParams.BANKRUPTCY_FUNDS)),
		bankrupt["body"])
	check(String(bankrupt["body"]).contains("Reports → Budget"), bankrupt["body"])
	var crisis := NoticeLines.render(&"fiscal_crisis", {"funds": -1200, "year": 2001}, "Dry Gulch", "Ada", 2001)
	check(String(crisis["body"]).contains("Automatic budgeting is now off, so you will review the budget each January."),
		crisis["body"])
	var ctx := make_context(flat_city())
	var budget := BudgetSystem.new()
	ctx.systems = {budget.key: budget}
	budget.setup(ctx)
	var quote: Dictionary = budget.bond_quote(BudgetParams.BOND_MAX + 1)
	check_eq(quote["reason"], "amount must be between %s and %s" % [NoticeLines.money(BudgetParams.BOND_MIN),
		NoticeLines.money(BudgetParams.BOND_MAX)])
	ctx.systems.clear()


# ── Disaster refusals ────────────────────────────────────────────────────

func test_unavailable_reasons_name_the_missing_ingredient() -> void:
	var c := flat_city()
	var ctx := make_context(c, 5)
	var sys := DisasterSystem.new()
	ctx.systems = {&"disasters": sys}
	sys.setup(ctx)
	check_eq(sys.unavailable_reason(c, &"meltdown"), "Needs a Nuclear Power Plant.")
	check_eq(sys.unavailable_reason(c, &"microwave"), "Needs a Microwave Receiver.")
	check_eq(sys.unavailable_reason(c, &"chemical_spill"), "Needs industry.")
	check_eq(sys.unavailable_reason(c, &"riot"), "Needs a road.")
	check_eq(sys.unavailable_reason(c, &"flood"), "Needs shoreline.")
	check_eq(sys.unavailable_reason(c, &"fire"), "Needs something that can burn.")
	check_eq(sys.unavailable_reason(c, &"hazard"), "Needs heavily polluted ground.")
	check(sys.request(ctx, &"earthquake", Vector2i(64, 64)), "an earthquake can always start")
	var draws_before := ctx.rng.state()
	check_eq(sys.unavailable_reason(c, &"tornado"), "Another disaster is still under way.")
	check_eq(ctx.rng.state(), draws_before, "asking for a reason draws no random numbers")
	ctx.systems.clear()


# ── Report windows ───────────────────────────────────────────────────────

func test_graph_lines_use_their_own_scales() -> void:
	var canvas := GraphsWindow.GraphCanvas.new()
	canvas.size = Vector2(400, 300)
	var small := PackedInt32Array([2, 4, 3])
	var large := PackedInt32Array([100000, 120000, 110000])
	var rows: Array[Dictionary] = [
		{"name": &"crime", "label": "Crime", "values": small, "color": Color.RED},
		{"name": &"population", "label": "Population", "values": large, "color": Color.BLUE},
	]
	canvas.set_series(rows, 12)
	check(canvas.own_scales(), "several series scale separately")
	var rect := canvas.plot_rect()
	for name in [&"crime", &"population"]:
		var points := canvas.points_for(name)
		var top := INF
		var bottom := -INF
		for p in points:
			top = minf(top, p.y)
			bottom = maxf(bottom, p.y)
		check(is_equal_approx(top, rect.position.y), "%s reaches the top" % name)
		check(is_equal_approx(bottom, rect.end.y), "%s reaches the bottom" % name)
	var one: Array[Dictionary] = [{"name": &"money", "label": "Funds", "values": PackedInt32Array([-50, 900]), "color": Color.RED}]
	canvas.set_series(one, 12)
	check(not canvas.own_scales(), "one series keeps the shared axis")
	check_eq(GraphsWindow.GraphCanvas.value_text(&"money", -1500), "-$1,500")
	check_eq(GraphsWindow.GraphCanvas.value_text(&"population", 1500), "1,500")
	canvas.free()
