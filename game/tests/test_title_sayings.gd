# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const TitleSayings := preload("res://scripts/ui/title_sayings.gd")

func settle() -> void:
	for frame in 6: await process_frame

func test_sayings_are_plentiful_unique_and_two_short_lines() -> void:
	var sayings: Array = TitleSayings.SAYINGS
	check(sayings.size() >= 300, "a few hundred sayings to choose from")
	var seen := {}
	for saying: String in sayings:
		check(not seen.has(saying), "saying is unique: " + saying)
		seen[saying] = true
		var lines := saying.split("\n")
		check_eq(lines.size(), 2, "saying has two lines: " + saying)
		for line: String in lines:
			check(not line.strip_edges().is_empty(), "no blank line: " + saying)
			check(line.length() <= TitleSayings.MAX_LINE, "line stays short: " + line)
	check(seen.has("Big plans.\nRoom to grow."), "the original saying stays in the rotation")

func test_pick_draws_from_the_whole_list() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000
	var drawn := {}
	for draw in 4000:
		var saying := TitleSayings.pick(rng)
		check(TitleSayings.SAYINGS.has(saying), "pick returns a listed saying")
		drawn[saying] = true
	check(drawn.size() > TitleSayings.SAYINGS.size() * 9 / 10, "seeded draws reach nearly every saying")
	check(TitleSayings.SAYINGS.has(TitleSayings.pick()), "unseeded pick returns a listed saying")

func test_title_shows_a_saying_and_the_widest_one_fits() -> void:
	root.size = Vector2i(1280, 800)
	var title := TitleScreen.new()
	root.add_child(title)
	title.open()
	check(TitleSayings.SAYINGS.has(title.subtitle.text), "title subtitle is one of the sayings")
	var widest := ""
	var widest_width := 0.0
	for saying: String in TitleSayings.SAYINGS:
		title.subtitle.text = saying
		var width := title.subtitle.get_combined_minimum_size().x
		if width > widest_width:
			widest_width = width
			widest = saying
	for bounds: Rect2 in [Rect2(0,0,1280,800), Rect2(0,0,1000,640), Rect2(0,24,820,1156), Rect2(0,0,640,900)]:
		root.size = Vector2i(bounds.end)
		title.subtitle.text = "Big plans.\nRoom to grow."
		title.apply_layout(bounds)
		await settle()
		var original_logo := title._logo.size
		title.subtitle.text = widest
		title.apply_layout(bounds)
		await settle()
		check(bounds.encloses(title.get_node("Panel").get_global_rect()), "widest saying keeps the frame in view: " + str(bounds))
		if title.subtitle.visible:
			check(title.subtitle.get_global_rect().end.x <= title.get_node("Panel").get_global_rect().end.x, "widest saying stays inside the frame")
			check(not title._logo.get_global_rect().intersects(title.subtitle.get_global_rect()), "saying never overlaps the logo")
		check(title._logo.size.y >= original_logo.y - 0.5, "widest saying (%s) does not shrink the logo at %s" % [widest.replace("\n", " "), bounds])
	title.free()
