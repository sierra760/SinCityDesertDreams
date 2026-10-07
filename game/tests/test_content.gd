# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"


func has_braces(text: String) -> bool:
	return text.contains("{") or text.contains("}")


func test_city_names_are_plentiful_and_distinct() -> void:
	check_ge(CityNames.count(), 60)
	var seen: Dictionary = {}
	for n in CityNames.NAMES:
		check(not seen.has(n), "duplicate name %s" % n)
		check(n.strip_edges() == n and n.length() > 2, "name is clean: %s" % n)
		seen[n] = true
	var rng := SimRng.new(11)
	var city := CityNames.random_name(rng)
	check(CityNames.NAMES.has(city))
	var around: Array[String] = CityNames.neighbors(rng, city)
	check_eq(around.size(), 4)
	var distinct: Dictionary = {}
	for n in around:
		check_ne(n, city, "a neighbour is not the city itself")
		distinct[n] = true
	check_eq(distinct.size(), 4, "neighbours are distinct")
	check_eq(CityNames.pick(rng, 100).size(), CityNames.count(), "picking more than exist yields them all")


func test_story_templates_have_variants_and_paragraphs() -> void:
	for kind in NewsStories.kinds():
		var heads := NewsStories.headline_variants(kind)
		check_between(heads.size(), 3, 6, "%s headline variants" % kind)
		var body := NewsStories.body_paragraphs(kind)
		check_between(body.size(), 2, 3, "%s body paragraphs" % kind)
		var seen: Dictionary = {}
		for h in heads:
			check(not seen.has(h), "%s repeats a headline" % kind)
			seen[h] = true
			check_gt(String(h).length(), 8)
		for p in body:
			check_gt(String(p).length(), 30)
		check_gt(NewsStories.decay_of(kind), 0)


func test_fillers_are_many_and_original_in_shape() -> void:
	check_ge(NewsStories.FILLERS.size(), 40)
	var seen: Dictionary = {}
	for f in NewsStories.FILLERS:
		check(f.has("headline") and f.has("body"))
		check(not seen.has(f["headline"]), "duplicate filler %s" % f["headline"])
		seen[f["headline"]] = true
		check_gt(String(f["body"]).length(), 40)
	var rng := SimRng.new(5)
	var used: Array = []
	for i in NewsStories.FILLERS.size():
		var pick := NewsStories.pick_filler(rng, used)
		check(pick >= 0 and not (pick in used))
		used.append(pick)
	check_eq(NewsStories.pick_filler(rng, used), -1, "no repeats once every filler is used")


func test_advisor_lines_have_variants() -> void:
	var expected: Array[StringName] = [
		&"power_shortage", &"water_shortage", &"fire_protection", &"police", &"schools",
		&"hospitals", &"traffic", &"road_and_rail", &"pollution", &"unemployment",
		&"taxes", &"approval",
	]
	for kind in expected:
		check(AdvisorLines.has(kind), "advice for %s" % kind)
	for kind in AdvisorLines.kinds():
		check_between(AdvisorLines.variants(kind).size(), 2, 3, "%s variants" % kind)
		check_gt(AdvisorLines.title(kind).length(), 0)
	check_eq(AdvisorLines.line(&"nothing_here", {}, SimRng.new(1)), "")
	check_eq(AdvisorLines.title(&"road_and_rail"), "Transport")
	check_eq(AdvisorLines.normalize(&"needs_power"), &"power_shortage")
	check_eq(AdvisorLines.normalize(&"needs_transit"), &"road_and_rail")
	check_eq(AdvisorLines.normalize(&"needs_industry_connections"), &"connections")
	check_eq(AdvisorLines.normalize(&"needs_police"), &"police")
	check_eq(AdvisorLines.normalize(&"police"), &"police")
	check(AdvisorLines.has(&"needs_hospital"))
	check(AdvisorLines.line(&"needs_water", {"city": "X"}, SimRng.new(2)).length() > 0)


func test_placeholder_values() -> void:
	var v := NewsStories.values_for(&"zone_boom", {"count": 1234567, "at": Vector2i(0, 0)}, "Dry Gulch", "Ada", 1999)
	check_eq(v["city"], "Dry Gulch")
	check_eq(v["mayor"], "Ada")
	check_eq(v["year"], "1999")
	check_eq(v["count"], "1,234,567")
	check_eq(v["place"], "the northwest corner")
	check_eq(v["kind"], "Zone Boom")
	check_eq(NewsStories.count_text({"amount": -2500}), "-$2,500", "dollar amounts print as money")
	check_eq(NewsStories.count_text({}), "several")
	check_eq(NewsStories.place_text({"name": "Rimrock"}), "Rimrock")
	check_eq(NewsStories.place_text({"center": "64,64"}), "downtown")
	check_eq(NewsStories.place_text({"x": 100, "y": 20}), "the northeast corner")
	check_eq(NewsStories.place_text({"at": [5, 120]}), "the southwest corner")
	check_eq(NewsStories.place_text({"anchor": Vector2i(60, 70)}), "downtown")
	# A plant report names the plant and anchors it; its place is the district.
	var plant := {"key": "plant_coal", "name": "Coal Power Plant", "anchor": Vector2i(60, 70), "age_years": 49}
	check_eq(NewsStories.place_text(plant), "downtown")
	check_eq(NewsStories.place_text({"place": "Rimrock", "anchor": Vector2i(60, 70)}), "Rimrock")
	check_eq(NewsStories.place_text({"name": "Rimrock", "edge": 2}), "Rimrock")
	var notice := NoticeLines.render(&"plant_retired", plant, "Test City", "Ada", 1999)
	check(not String(notice.get("body", "")).contains("Coal Power Plant near Coal Power Plant"),
		"a retired plant is not near itself")
	check(String(notice.get("body", "")).contains("near downtown"))
	check_eq(NewsStories.count_text({"unpowered": 42}), "42")
	check_eq(NewsStories.count_text({"tiles": 3, "x": 1}), "3")
	check_eq(NewsStories.kind_text(&"city_milestone", {"key": "city_hall", "population": 5}), "City Hall")
	check_eq(NewsStories.kind_text(&"plant_aging", {"key": "plant_coal", "name": "Coal Plant"}), "Coal Plant")
	check_eq(NewsStories.kind_text(&"advisor_need", {"need": "needs_school"}), "Education")
	check_eq(NewsStories.kind_text(&"economy_shift", {"phase": 3, "name": "Boom"}), "Boom")
	check_eq(NewsStories.place_text({}), "the edge of town")
	check_eq(NewsStories.place_name(Vector2i(127, 127)), "the southeast corner")
	check_eq(NewsStories.place_name(Vector2i(64, 5)), "the north end")
	check_eq(NewsStories.kind_text(&"disaster_ended", {"kind": &"plane_crash"}), "Plane Crash")
	check_eq(NewsStories.fill("{city} in {year}", v), "Dry Gulch in 1999")
	check(has_braces(NewsStories.fill("{unknown}", v)), "unknown placeholders stay visible")


func test_priorities_follow_importance() -> void:
	check_eq(NewsStories.priority_of(&"bankruptcy"), NewspaperParams.PRIORITY_URGENT)
	check_eq(NewsStories.priority_of(&"disaster_started", {"kind": &"volcano"}), NewspaperParams.PRIORITY_URGENT)
	check_eq(NewsStories.priority_of(&"water_shortage"), NewspaperParams.PRIORITY_MAJOR)
	check_eq(NewsStories.priority_of(&"zone_boom"), NewspaperParams.PRIORITY_NOTABLE)
	check_eq(NewsStories.priority_of(&"chapel_built"), NewspaperParams.PRIORITY_MINOR)
	check_eq(NewsStories.priority_of(&"made_up_kind"), NewspaperParams.PRIORITY_MINOR)
	check_eq(NewsStories.decay_of(&"bridge_collapse"), NewspaperParams.DECAY_ONCE)
	check_eq(NewsStories.decay_of(&"road_decay"), NewspaperParams.DECAY_SLOW)
