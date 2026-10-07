# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Fresh file text owns validity; header caching never trusts metadata alone.
extends "res://tests/test_case.gd"
const DIR := "user://save-header-cache-tests"
var _paths: Array[String] = []
func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
func after_all() -> void:
	for path: String in _paths: DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(DIR)
func _write(name: String, doc: Dictionary) -> String:
	var path := DIR.path_join(name + ".sc2d")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(doc));file.close()
	if not _paths.has(path): _paths.append(path)
	return path
func _doc(name: String = "Alpha") -> Dictionary:
	return {"format":"sc2d","version":1,"header":{"name":name,"year":2030,"day":12,"population":321,"funds":45000,"saved_at":123456,"mayor":"  Ana María  "}}
func test_same_size_and_time_replacements_and_returned_mutation_are_observed() -> void:
	var same_time := false
	for trial: int in 4:
		var path := _write("replacement",_doc())
		var first := SaveFormat.read_header(path)
		var modified := FileAccess.get_modified_time(path)
		var size := FileAccess.get_file_as_bytes(path).size()
		first.name="caller edit";first.mayor="caller edit"
		check_eq(SaveFormat.read_header(path).name,"Alpha","caller cannot mutate cached header")
		check_eq(SaveFormat.read_header(path).mayor,"Ana María","header mayor is cleaned")
		_write("replacement",_doc("Bravo"))
		check_eq(FileAccess.get_file_as_bytes(path).size(),size,"fixture replacement has equal byte count")
		check_eq(SaveFormat.read_header(path).name,"Bravo","fresh exact text observes replacement")
		if FileAccess.get_modified_time(path)==modified: same_time=true;break
	check(same_time,"replacement also exercises equal modification timestamp")
func test_missing_deleted_and_invalid_schema_match_reference() -> void:
	var path := _write("missing",_doc())
	check_eq(SaveFormat.read_header(path),_original_read_header(path))
	DirAccess.remove_absolute(path)
	check_eq(SaveFormat.read_header(path),{},"deleted file cannot return cached data")
	for doc: Dictionary in [{},{"format":"wrong","header":{}},{"format":"sc2d","header":[]},{"format":"sc2d","header":{},"city":null}]:
		path=_write("schema",doc)
		check_eq(SaveFormat.read_header(path),_original_read_header(path),"cached result matches a direct header-only read")
func test_identical_text_with_new_timestamp_updates_modified_time_fallback() -> void:
	var doc := _doc();doc.header.erase("saved_at")
	var path := _write("timestamp",doc)
	var first := SaveFormat.read_header(path)
	OS.delay_msec(1100)
	_write("timestamp",doc)
	check_gt(FileAccess.get_modified_time(path),int(first.saved_at),"fixture advances the timestamp")
	check_eq(SaveFormat.read_header(path),_original_read_header(path),"same text keeps current metadata fallback")
func test_repeated_large_header_queries_avoid_full_parse_work() -> void:
	var doc := _doc();doc.snapshot={"unused_payload":"x".repeat(262144)}
	var path := _write("performance",doc)
	check_eq(SaveFormat.read_header(path),_original_read_header(path),"header result stays exact")
	var reference_times: Array[int] = []
	var cached_times: Array[int] = []
	for repetition: int in 3:
		var start := Time.get_ticks_usec()
		for i: int in 30: _original_read_header(path)
		reference_times.append(Time.get_ticks_usec()-start)
		start=Time.get_ticks_usec()
		for i: int in 30: SaveFormat.read_header(path)
		cached_times.append(Time.get_ticks_usec()-start)
	reference_times.sort();cached_times.sort()
	print("HEADER_CPU reference_usec=",reference_times[0]," current_usec=",cached_times[0])
	check_lt(cached_times[0],reference_times[0]*.75,"unchanged complete text avoids reparsing the full document")
func test_cache_is_bounded_and_oversized_documents_are_not_retained() -> void:
	for i: int in 70:
		var path := _write("bounded-%02d"%i,_doc(str(i)))
		check_eq(SaveFormat.read_header(path).name,str(i))
	var doc := _doc();doc.snapshot={"unused_payload":"x".repeat(2097153)}
	var path := _write("oversized",doc)
	check_eq(SaveFormat.read_header(path),_original_read_header(path))
	var cache: Variant = load("res://scripts/io/save_format.gd").get("_header_cache")
	check(cache is Dictionary,"valid headers have a bounded reusable cache")
	if cache is Dictionary:
		check(cache.size()<=64,"at most 64 paths retained")
		check(not cache.has(path),"oversized document is not retained")
		var actual_text_bytes := 0
		for entry: Dictionary in cache.values(): actual_text_bytes+=String(entry.text).length()*4
		check(actual_text_bytes<=8388608,"retained text stays within the 8 MiB budget")

static func _original_read_header(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var doc: Dictionary = parsed
	if String(doc.get("format", "")) != SaveFormat.FORMAT:
		return {}
	var header: Variant = doc.get("header", {})
	if typeof(header) != TYPE_DICTIONARY:
		return {}
	var h: Dictionary = header
	var saved_at := int(h.get("saved_at", FileAccess.get_modified_time(path)))
	return {
		"path": path,
		"mayor": ViewPreferences.mayor_credit(h.get("mayor", "")),
		"name": String(h.get("name", path.get_file().get_basename())),
		"date_text": Time.get_datetime_string_from_unix_time(saved_at, true) + " UTC",
		"population": int(h.get("population", 0)),
		"year": int(h.get("year", 0)),
		"day": int(h.get("day", 0)),
		"funds": int(h.get("funds", 0)),
		"stage": SaveFormat.STAGE_EDITING if String(h.get("stage", SaveFormat.STAGE_PLAY)) == SaveFormat.STAGE_EDITING else SaveFormat.STAGE_PLAY,
		"saved_at": saved_at,
	}

