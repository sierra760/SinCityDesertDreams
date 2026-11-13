# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The Load City list reads headers from files anyone may have shared: a
## malformed header is skipped or listed with sane values, never mis-read.
extends "res://tests/test_case.gd"

const DIR := "user://save-header-guard-tests"
const TOURIST_CITY := "res://assets/cities/Bonanza Gap.sc2d"

var _count := 0


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	for file: String in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _write(doc: Variant) -> String:
	_count += 1
	var path := DIR.path_join("header-%03d.sc2d" % _count)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(doc))
	file.close()
	return path


func _doc() -> Dictionary:
	return {"format": "sc2d", "version": 2, "stage": "play", "header": {"name": "Alpha", "mayor": "Ana", "year": 2030,
		"day": 12, "population": 321, "funds": 45000, "saved_at": 123456, "stage": "play"}}


func _read(doc: Variant) -> Dictionary:
	var result: Variant = SaveFormat.read_header(_write(doc))
	check(result is Dictionary, "the reader always answers with a header or nothing")
	return result if result is Dictionary else {}


func test_a_sound_header_is_listed_as_written() -> void:
	var header := _read(_doc())
	check_eq(header.get("name"), "Alpha")
	check_eq(header.get("mayor"), "Ana")
	check_eq(header.get("population"), 321)
	check_eq(header.get("funds"), 45000)
	check_eq(header.get("saved_at"), 123456)
	var negative := _doc()
	negative.header.funds = -2500
	check_eq(_read(negative).get("funds"), -2500, "a treasury in debt is an ordinary header")


func test_count_schema_of_any_kind_is_read_safely() -> void:
	for value: Variant in ["1", [1], {"a": 1}, true, null, 1.5, -1]:
		var doc := _doc()
		doc.header.count_schema = value
		doc.header.tourists = 55
		var header := _read(doc)
		check_eq(header.get("name"), "Alpha", "count_schema %s lists the city" % str(value))
		check_eq(header.get("tourists"), -1, "count_schema %s is not the current schema" % str(value))
	for value: Variant in [1, 1.0]:
		var doc := _doc()
		doc.header.count_schema = value
		doc.header.tourists = 55
		check_eq(_read(doc).get("tourists"), 55, "the current schema keeps its tourist count")
		doc.header.tourists = "many"
		check_eq(_read(doc).get("tourists"), -1, "a tourist count that is not a number is ignored")


func test_numbers_no_city_holds_are_not_listed() -> void:
	for field: String in ["saved_at", "population", "year", "day", "funds"]:
		for value: Variant in [1e300, -1e300, 9.3e18, -9.3e18, 1.0e17]:
			var doc := _doc()
			doc.header[field] = value
			check(_read(doc).is_empty(), "%s = %s is not a save" % [field, str(value)])
		for value: Variant in ["7", true, null, [1], {"a": 1}]:
			var doc := _doc()
			doc.header[field] = value
			check(_read(doc).is_empty(), "%s = %s is not a save" % [field, str(value)])
	for value: Variant in [-5, 253402300800.0]:
		var doc := _doc()
		doc.header.saved_at = value
		check(_read(doc).is_empty(), "saved_at %s is not a save time" % str(value))
	var doc := _doc()
	doc.header.population = -5
	check(_read(doc).is_empty(), "a negative population is not a save")


func test_other_wrong_typed_fields_are_skipped_or_defaulted() -> void:
	for value: Variant in [5, [1], {"a": 1}, null, true]:
		var doc := _doc()
		doc.header.mayor = value
		check_eq(_read(doc).get("mayor"), "Mayor", "a mayor that is not text takes the default credit")
		doc = _doc()
		doc.header.name = value
		check(_read(doc).is_empty(), "a name that is not text is not a save")
		doc = _doc()
		doc.header = value
		# A header with no fields lists under the file's own name.
		if value is Dictionary: check_eq(_read(doc).get("population"), 0)
		else: check(_read(doc).is_empty(), "a header that is not a table is not a save")
		doc = _doc()
		doc.city = value
		check_eq(_read(doc).get("name"), "Alpha", "a damaged city body still lists by its header")
		doc = _doc()
		doc.snapshot = value
		check_eq(_read(doc).get("name"), "Alpha")
	for city: Variant in [{"facilities": []}, {"facilities": {"1,1": 5}}, {"facilities": {"1,1": {"key": 0.5}}},
			{"facilities": {"1,1": {"key": "arcology_comstock", "residents": "many"}}},
			{"facilities": {"1,1": {"key": "arcology_comstock", "residents": [1]}}}]:
		for snapshot: Variant in [{"stats": {"population": 10}}, {"stats": {"population": 10}, "systems": []},
				{"stats": {"population": 10}, "systems": {"tourism": 5}}, {"stats": {"population": 10}, "systems": {"rewards": 5}},
				{"stats": {"population": 10}, "systems": {"rewards": {"arcologies": {"1,1": 5}}}}]:
			var doc := _doc()
			doc.city = city
			doc.snapshot = snapshot
			check_eq(_read(doc).get("population"), 10)


func test_damaged_facilities_of_a_visited_city_do_not_stop_the_listing() -> void:
	var text := FileAccess.get_file_as_string(TOURIST_CITY)
	check(not text.is_empty(), "the fixture city is available")
	if text.is_empty(): return
	var sound: Dictionary = JSON.parse_string(text)
	var listed := _read(sound)
	check(int(listed.get("tourists", 0)) > 0, "the city has visitors to count")
	for damage: Array in [["key", 0.5], ["key", [500, 500]], ["key", null], ["tourism_instance", "x"], ["tourism_instance", [1]], ["tourism_instance", null]]:
		var doc: Dictionary = JSON.parse_string(text)
		for anchor: Variant in doc.city.facilities:
			if doc.city.facilities[anchor] is Dictionary: doc.city.facilities[anchor][damage[0]] = damage[1]
		var header := _read(doc)
		check_eq(header.get("name"), listed.get("name"), "%s = %s still lists the city" % [damage[0], str(damage[1])])
		check_eq(header.get("population"), listed.get("population"))
		check_eq(header.get("tourists"), 0, "venues that cannot be matched count no visitors")


func test_listing_a_folder_of_damaged_files_returns_only_sound_rows() -> void:
	var rows := SaveFormat.list_saves(DIR)
	check(rows.size() > 0)
	for row: Dictionary in rows:
		check(row.get("name") is String and row.get("mayor") is String and row.get("date_text") is String)
		check(int(row.saved_at) >= 0 and int(row.saved_at) <= 253402300799, str(row.saved_at))
		check(int(row.population) >= 0)
		check(String(row.date_text).length() <= 24, String(row.date_text))
