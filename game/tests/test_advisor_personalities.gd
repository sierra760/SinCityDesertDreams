# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const People := preload("res://scripts/content/advisor_cast.gd")

func test_each_department_has_one_distinct_person_for_its_related_topics() -> void:
	var names: Dictionary = {}
	for id: String in People.ORDER: names[People.speaker(id,"neutral",0).name] = true
	check_eq(names.size(),6)
	for pair in [["power_shortage","utilities"],["water_shortage","utilities"],["water_treatment","utilities"],["fire_protection","safety"],["police","safety"],["emergency","safety"],["schools","community"],["hospitals","community"],["recreation","community"],["traffic","transport"],["road_and_rail","transport"],["airport","transport"],["seaport","transport"],["tourism","planning"],["commerce","planning"],["unemployment","planning"],["connections","planning"],["pollution","planning"],["approval","planning"],["treasury","finance"],["taxes","finance"]]:
		check_eq(People.department_of(pair[0]),pair[1])
	check_eq(People.department_of("future_topic"),"planning", "future findings retain a home")

func test_every_advisor_has_five_distinct_bundled_mood_portraits() -> void:
	for id: String in People.ORDER:
		var images: Dictionary = {}
		var paths: Dictionary = {}
		var neutral := People.speaker(id,"neutral",0)
		for mood: String in ["delighted","pleased","neutral","concerned","critical"]:
			var speaker := People.speaker(id,mood,0)
			check_eq(speaker.name,neutral.name,"moods do not change the person")
			check(ResourceLoader.exists(speaker.portrait),"bundled portrait: " + speaker.portrait)
			if not ResourceLoader.exists(speaker.portrait): continue
			var texture := load(String(speaker.portrait)) as Texture2D
			check(texture != null)
			if texture != null:
				check(texture.get_width() <= 512 and texture.get_height() <= 512,"bounded runtime import")
			images[FileAccess.get_sha256(speaker.portrait)] = true
			paths[speaker.portrait] = true
		check_eq(images.size(),5,"five independently authored expressions for " + id)
		check_eq(paths.size(),5)

func test_speech_is_stable_by_month_and_emergencies_use_a_direct_tone() -> void:
	var first := People.speaker("transport","concerned",0)
	check_eq(People.speaker("transport","concerned",0),first)
	check_ne(People.speaker("transport","concerned",1).quip,first.quip)
	check_ne(People.speaker("transport","delighted",0).quip,first.quip)
	check_eq(People.speaker("safety","critical",1,true).quip,"Mayor, the emergency comes first.")
	check_eq(People.speaker("missing","unknown",0).mood,"neutral")
