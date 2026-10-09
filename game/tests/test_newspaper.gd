# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const NewspaperSystem := preload("res://scripts/sim/newspaper_system.gd")

## Every kind the other systems report. Each must resolve to its own story.
const REPORTED_KINDS: Array[StringName] = [
	&"power_shortage", &"plant_retired", &"zone_boom", &"abandonment_wave",
	&"chapel_built", &"traffic_jam", &"road_decay", &"bridge_collapse", &"rail_decay",
	&"pollution_alert", &"crime_wave", &"prison_escape", &"status_upgrade",
	&"approval_vote", &"economy_shift", &"invention", &"bankruptcy",
	&"disaster_started", &"disaster_ended", &"fire_reported", &"reward_offered",
	&"exodus", &"neighbor_news", &"neighbor_growth", &"neighbor_connection",
	&"water_shortage", &"tax_change", &"ordinance_passed", &"bond_issued", &"quiet_month",
	&"power_restored", &"water_restored", &"treasury_deficit", &"port_opened", &"port_closed",
	&"plant_aging", &"plant_replaced", &"neighbor_shock", &"city_milestone", &"birth_record",
	&"advisor_need", &"resort_launch", &"casino_debut", &"casino_windfall", &"casino_losses",
]
## Kinds reported under another name that share a template.
const ALIASED_KINDS: Dictionary = {&"ordinance_enacted": &"ordinance_passed"}
const DISASTER_KINDS: Array[StringName] = [
	&"fire", &"flood", &"tornado", &"earthquake", &"monster", &"riot", &"plane_crash",
	&"hurricane", &"meltdown", &"chemical_spill", &"microwave", &"volcano", &"firestorm",
	&"mass_riots", &"major_flood", &"hazard",
]


class StubDisasters extends SimSystem:
	func _init() -> void:
		key = &"disasters"
	func advice() -> Array:
		return [&"needs_school", {"kind": &"hospitals"}, "needs_seaport", &"needs_school"]


func make_ctx(day: int = 21, seed_value: int = 7) -> SimContext:
	var ctx := make_context(flat_city(), seed_value)
	ctx.city.name = "Dry Gulch"
	ctx.city.mayor = "Ada"
	ctx.clock.founded_year = 1950
	ctx.clock.day = day
	return ctx


func make_system(ctx: SimContext) -> SimSystem:
	var s: SimSystem = NewspaperSystem.new()
	ctx.systems = {s.key: s}
	s.setup(ctx)
	return s


func next_day(ctx: SimContext) -> void:
	ctx.events.clear()
	ctx.clock.day += 1


func notices_of(ctx: SimContext, kind: StringName) -> int:
	var n := 0
	for notice in ctx.events.notices:
		if notice.kind == kind:
			n += 1
	return n


func has_braces(text: String) -> bool:
	return text.contains("{") or text.contains("}")


func test_key() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	check_eq(s.key, &"newspaper")
	check(s.latest_issue().is_empty())
	check_eq(s.archive().size(), 0)


func test_reports_are_absorbed_and_ordered_by_priority() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	ctx.events.report(&"road_decay", {"count": 3, "place": "the north end"})
	ctx.events.report(&"zone_boom", {"count": 8, "place": "downtown"})
	ctx.events.report(&"road_decay", {"count": 3, "place": "the south end"})
	ctx.events.report(&"water_shortage", {"count": 40})
	s.daily(ctx)
	var q: Array[Dictionary] = s.pending()
	check_eq(q.size(), 4)
	check_eq(q[0]["kind"], &"water_shortage", "major first")
	check_eq(q[1]["kind"], &"zone_boom", "notable second")
	check_eq(q[2]["kind"], &"road_decay")
	check_eq(q[2]["args"]["place"], "the north end", "ties keep the older story first")
	check_eq(q[3]["args"]["place"], "the south end")
	s.daily(ctx)
	check_eq(s.pending().size(), 4, "reading the same day twice adds nothing")
	ctx.events.report(&"road_decay", {"count": 3, "place": "the north end"})
	s.networks_changed(ctx, Rect2i())
	check_eq(s.pending().size(), 4, "a repeat of the same subject refreshes instead of duplicating")
	next_day(ctx)
	ctx.events.report(&"chapel_built", {"at": Vector2i(5, 5)})
	s.daily(ctx)
	check_eq(s.pending().size(), 5, "a new day's reports are absorbed")
	var boosted := make_ctx()
	var s2 := make_system(boosted)
	s2.submit(boosted, &"road_decay", {"x": 1, "y": 1}, 1)
	s2.submit(boosted, &"road_decay", {"x": 64, "y": 64, "tiles": 4}, 2)
	s2.submit(boosted, &"road_decay", {"x": 100, "y": 100}, 3)
	s2.submit(boosted, &"bankruptcy", {}, 0)
	var p: Array[Dictionary] = s2.pending()
	check_eq(p.size(), 4)
	check_eq(int(p[0]["priority"]), NewspaperParams.PRIORITY_URGENT, "importance 3 guarantees an urgent story")
	check_eq(p[0]["args"]["x"], 100)
	check_eq(int(p[1]["priority"]), NewspaperParams.PRIORITY_URGENT, "importance 0 leaves the kind's own priority")
	check_eq(p[1]["kind"], &"bankruptcy")
	check_eq(int(p[2]["priority"]), NewspaperParams.PRIORITY_MAJOR, "importance 2 guarantees a major story")
	check_eq(int(p[3]["priority"]), NewspaperParams.PRIORITY_MINOR)


func test_queue_is_bounded_and_squeezes_out_the_least_important() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	for i in 12:
		s.submit(ctx, &"road_decay", {"count": i + 1})
	check_eq(s.pending().size(), NewspaperParams.QUEUE_SIZE)
	s.submit(ctx, &"road_decay", {"count": 99})
	var q: Array[Dictionary] = s.pending()
	check_eq(q.size(), NewspaperParams.QUEUE_SIZE)
	check(not q.any(func(x: Dictionary) -> bool: return int(x["args"]["count"]) == 99),
		"an equal-priority newcomer is discarded when the queue is full")
	s.submit(ctx, &"prison_escape", {"count": 4})
	q = s.pending()
	check_eq(q.size(), NewspaperParams.QUEUE_SIZE)
	check_eq(q[0]["kind"], &"prison_escape", "a more important story replaces the least important")


func test_monthly_issue_prints_leads_then_decays_the_rest() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	s.submit(ctx, &"road_decay", {"count": 2, "place": "the west side"})
	for place in ["the north end", "downtown", "the east side", "the south end"]:
		s.submit(ctx, &"bridge_collapse", {"place": place})
	s.monthly(ctx, 0)
	var issue: Dictionary = s.latest_issue()
	check_eq(bool(issue["extra"]), false)
	check_eq(issue["title"], NewspaperParams.TITLE)
	check_eq(issue["date"], "January 1950")
	var stories: Array = issue["stories"]
	check_eq(stories.size(), NewspaperParams.ISSUE_STORIES)
	for i in NewspaperParams.LEAD_COUNT:
		check_eq(stories[i]["kind"], "bridge_collapse", "the three most important print")
		check_eq(bool(stories[i]["filler"]), false)
	for i in range(NewspaperParams.LEAD_COUNT, stories.size()):
		check_eq(bool(stories[i]["filler"]), true)
	var q: Array[Dictionary] = s.pending()
	check_eq(q.size(), 1, "the unprinted collapse decays away, the road story lingers")
	check_eq(q[0]["kind"], &"road_decay")
	check_eq(int(q[0]["priority"]), NewspaperParams.PRIORITY_MINOR - NewspaperParams.DECAY_SLOW)
	check_eq(notices_of(ctx, &"newspaper"), 1, "the monthly issue is always raised")
	check_eq(s.archive().size(), 1)


func test_quiet_month_when_nothing_is_pending() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	s.monthly(ctx, 0)
	var issue: Dictionary = s.latest_issue()
	var stories: Array = issue["stories"]
	check_eq(stories[0]["kind"], "quiet_month")
	check_eq(stories.size(), NewspaperParams.ISSUE_STORIES)
	var headlines: Dictionary = {}
	for st in stories:
		check(not has_braces(st["headline"]), st["headline"])
		check(not has_braces(st["body"]), st["body"])
		headlines[st["headline"]] = true
	check_eq(headlines.size(), stories.size(), "fillers do not repeat inside one issue")
	check_eq(notices_of(ctx, &"newspaper"), 1)


func test_extra_edition_breaks_on_urgent_news() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	ctx.events.report(&"zone_boom", {"count": 5, "at": Vector2i(3, 3)})
	s.daily(ctx)
	check(s.latest_issue().is_empty(), "notable news waits for the monthly issue")
	ctx.events.report(&"disaster_started", {"kind": "fire", "x": 120, "y": 120}, 3)
	s.daily(ctx)
	var issue: Dictionary = s.latest_issue()
	check(not issue.is_empty())
	check_eq(bool(issue["extra"]), true)
	var lead: Dictionary = issue["stories"][0]
	check_eq(lead["kind"], "disaster_started")
	check(lead["headline"].to_lower().contains("fire") or lead["body"].to_lower().contains("fire"))
	check(lead["body"].contains("the southeast corner"), lead["body"])
	check_eq(notices_of(ctx, &"newspaper"), 1)
	check_eq(s.pending().size(), 0, "the boom story was printed alongside the extra")
	ctx.events.report(&"disaster_started", {"kind": "flood", "x": 1, "y": 1}, 3)
	s.daily(ctx)
	check_eq(s.archive().size(), 1, "at most one extra per day")
	check_eq(s.pending().size(), 1)
	next_day(ctx)
	ctx.events.report(&"bankruptcy", {})
	s.daily(ctx)
	check_eq(s.archive().size(), 2)
	var printed: Array = []
	for st in s.latest_issue()["stories"]:
		printed.append(st["kind"])
	check_eq(printed.slice(0, 2), ["disaster_started", "bankruptcy"], "equal priorities print oldest first")


func test_every_reported_kind_has_its_own_story() -> void:
	for kind in REPORTED_KINDS:
		check_eq(NewsStories.template_key(kind), kind, "template for %s" % kind)
	for d in DISASTER_KINDS:
		var t := NewsStories.template_key(&"disaster_started", {"kind": d})
		check_eq(t, StringName("disaster_" + String(d)), "disaster template for %s" % d)
	for alias in ALIASED_KINDS:
		check_eq(NewsStories.template_key(alias), ALIASED_KINDS[alias], "alias %s" % alias)
	check_eq(NewsStories.template_key(&"no_such_kind"), NewsStories.GENERIC)
	check_eq(NewsStories.template_key(&"disaster_started", {"kind": &"unheard_of"}), &"disaster_started")


func test_placeholders_are_filled() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	s.submit(ctx, &"status_upgrade", {"status": 4, "name": "Metropolis", "population": 50000}, 2)
	s.monthly(ctx, 0)
	var lead: Dictionary = s.latest_issue()["stories"][0]
	check(not has_braces(lead["headline"]), lead["headline"])
	check(not has_braces(lead["body"]), lead["body"])
	check(lead["body"].contains("Dry Gulch"))
	check(lead["body"].contains("50,000"))
	check(lead["body"].contains("Metropolis"))
	check(lead["body"].contains("Ada"))


func test_every_template_renders_without_braces() -> void:
	var values := NewsStories.values_for(&"", {}, "Dry Gulch", "Ada", 1950)
	for kind in NewsStories.kinds():
		for h in NewsStories.headline_variants(kind):
			var text := NewsStories.fill(String(h), values)
			check(not has_braces(text), "%s headline: %s" % [kind, text])
		for p in NewsStories.body_paragraphs(kind):
			var text := NewsStories.fill(String(p), values)
			check(not has_braces(text), "%s body: %s" % [kind, text])
	for i in NewsStories.FILLERS.size():
		check(not has_braces(NewsStories.filler_headline(i, values)))
		check(not has_braces(NewsStories.filler_body(i, values)))
	var rng := SimRng.new(3)
	for kind in AdvisorLines.kinds():
		var text := AdvisorLines.line(kind, values, rng)
		check(text.length() > 0)
		check(not has_braces(text), "%s advice: %s" % [kind, text])


func test_archive_is_bounded() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	for i in NewspaperParams.ARCHIVE_ISSUES + 10:
		s.submit(ctx, &"tax_change", {"count": i})
		s.monthly(ctx, 0)
		ctx.clock.day += GameClock.DAYS_PER_MONTH
	check_eq(s.archive().size(), NewspaperParams.ARCHIVE_ISSUES)
	check_eq(ctx.stats.newspaper_archive.size(), NewspaperParams.ARCHIVE_ISSUES)
	var last: Dictionary = s.archive()[s.archive().size() - 1]
	check_eq(last, s.latest_issue())
	check(last["stories"][0]["headline"].contains(str(NewspaperParams.ARCHIVE_ISSUES + 9))
		or last["stories"][0]["body"].contains(str(NewspaperParams.ARCHIVE_ISSUES + 9)))


func test_save_load_round_trip() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	s.submit(ctx, &"crime_wave", {"count": 7, "at": Vector2i(64, 64)})
	s.submit(ctx, &"chapel_built", {"at": Vector2i(2, 2)})
	s.submit(ctx, &"disaster_ended", {"kind": &"tornado"})
	var text := JSON.stringify(s.save())
	var parsed: Variant = JSON.parse_string(text)
	check(typeof(parsed) == TYPE_DICTIONARY, "save is JSON-safe")
	var ctx2 := make_ctx()
	var s2 := make_system(ctx2)
	s2.load(parsed)
	var a: Array[Dictionary] = s.pending()
	var b: Array[Dictionary] = s2.pending()
	check_eq(b.size(), a.size())
	for i in a.size():
		check_eq(b[i]["kind"], a[i]["kind"])
		check_eq(int(b[i]["priority"]), int(a[i]["priority"]))
	s.monthly(ctx, 0)
	s2.monthly(ctx2, 0)
	var first: Array = s.latest_issue()["stories"]
	var second: Array = s2.latest_issue()["stories"]
	check_eq(second.size(), first.size())
	for i in first.size():
		check_eq(second[i]["headline"], first[i]["headline"], "same seed, same paper after reload")
	var mentions_downtown := false
	for st in second:
		if st["body"].contains("downtown") or st["headline"].contains("downtown"):
			mentions_downtown = true
	check(mentions_downtown, "saved positions still resolve to districts")
	s2.load({})
	check_eq(s2.pending().size(), 0)


func test_story_numbers_read_the_same_after_a_load() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	s.submit(ctx, &"port_opened", {"kind": Zones.AIRPORT, "at": Vector2i(10, 10)})
	s.submit(ctx, &"crime_wave", {"count": 7, "at": Vector2i(64, 64)})
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(s.save()))
	var ctx2 := make_ctx()
	var s2 := make_system(ctx2)
	s2.load(parsed)
	for story in s2.pending():
		for k in story["args"]:
			var v: Variant = story["args"][k]
			check(typeof(v) != TYPE_FLOAT, "%s.%s is a whole number again" % [story["kind"], k])
	s.monthly(ctx, 0)
	s2.monthly(ctx2, 0)
	var port := ""
	for st in s2.latest_issue()["stories"]:
		if st["kind"] == "port_opened":
			port = st["headline"] + " " + st["body"]
	check(port.contains("Airport"), "the reloaded port story names the airport: " + port)
	check(not port.contains("8.0"), "no float zone kind in the story")
	var first: Array = s.latest_issue()["stories"]
	var second: Array = s2.latest_issue()["stories"]
	for i in first.size():
		check_eq(second[i]["headline"], first[i]["headline"], "same paper after reload")


func test_advice_lists_needs_most_urgent_first() -> void:
	var ctx := make_ctx()
	var s := make_system(ctx)
	ctx.systems[&"disasters"] = StubDisasters.new()
	var st := ctx.stats
	st.power_capacity = 100
	st.power_demand = 99
	st.water_capacity = 100
	st.water_demand = 50
	st.unemployment = 12
	st.tax_residential = 13
	st.approval = 20
	st.active_fires = 1
	var out: Array[Dictionary] = s.advice()
	var kinds: Array = []
	for item in out:
		kinds.append(item["kind"])
		check(item["text"].length() > 0)
		check(not has_braces(item["text"]))
		check(item["title"].length() > 0)
	check_eq(kinds.slice(0, 3), [&"schools", &"hospitals", &"seaport"], "the disaster system's needs lead, under their line names, once each")
	check(bool(out[0]["urgent"]))
	check(kinds.has(&"power_shortage"))
	check(not kinds.has(&"water_shortage"))
	check(kinds.has(&"fire_protection"))
	check(kinds.has(&"unemployment"))
	check(kinds.has(&"taxes"))
	check(kinds.has(&"approval"))
	check(not kinds.has(&"pollution"))
	var later: Array[Dictionary] = s.advice()
	check_eq(later[0]["text"], out[0]["text"], "advice is stable within a day")
	var quiet := make_ctx()
	var s2 := make_system(quiet)
	check_eq(s2.advice().size(), 0, "a healthy empty town needs nothing")
