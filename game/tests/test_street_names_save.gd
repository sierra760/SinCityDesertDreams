# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"
const Fixtures := preload("res://tests/fixtures/street_names_fixtures.gd")
var _dir := ""

func before_all() -> void:
	_dir = "user://street_names_save_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(_dir)

func after_all() -> void:
	var directory := DirAccess.open(_dir)
	if directory != null:
		for file: String in directory.get_files(): directory.remove(file)
		DirAccess.remove_absolute(_dir)

func _named() -> City:
	var f := Fixtures.straight()
	var service := StreetNamingService.new()
	check(service.bind_city(f.city,f.topology).ok)
	var keys: Array[String] = []
	keys.assign(f.keys)
	check(service.assign(keys,"Palm Avenue",f.topology.revision).ok)
	return f.city

func _auto() -> Dictionary:
	return {"source_street_ids":[1],"base_name":"Palm Avenue","suffix":2,"display_name":"Palm Avenue 2"}

func _wire() -> Dictionary:
	return {"schema":1,"next_street_id":"2","streets":{"1":"Palm Avenue"},"links":{"8,8,open>9,8,open":"1"},"station_auto":{}}

func _decode(block: Variant) -> Dictionary:
	var document := SaveFormat.encode_city(_named())
	document.street_naming = block
	return SaveFormat.decode_city(document)

func _reject(block: Variant, label: String = "") -> void:
	var before := var_to_bytes(block)
	var decoded := _decode(block)
	check(decoded.city == null,"malformed naming rejected: "+label)
	check(not String(decoded.error).is_empty(),"explanatory naming load error: "+label)
	check_eq(var_to_bytes(block),before,"decode does not mutate supplied naming")

func test_native_roundtrip_and_missing_block_is_a_load_error() -> void:
	var city := _named()
	var encoded := SaveFormat.encode_city(city)
	check(encoded.has("street_naming"),"applied names are encoded")
	var decoded := SaveFormat.decode_city(encoded)
	check(decoded.city != null,decoded.error)
	if decoded.city != null: check_eq(decoded.city.street_naming,city.street_naming)
	encoded.erase("street_naming")
	var missing := SaveFormat.decode_city(encoded)
	check(missing.city == null,"a city without street naming metadata is rejected")
	check(not String(missing.error).is_empty())

func test_unknown_schema_is_a_load_error() -> void:
	var block := _wire()
	block.schema = 2
	_reject(block,"unknown schema")
	var path := _dir.path_join("unknown.sc2d")
	var file := FileAccess.open(path,FileAccess.WRITE)
	var document := SaveFormat.encode_city(_named())
	document.street_naming = block
	file.store_string(JSON.stringify({"format":"sc2d","version":1,"stage":"play","city":document},"",false))
	file.close()
	var loaded := SaveFormat.load(path)
	check(not loaded.ok and loaded.city==null)
	check(not String(loaded.error).is_empty(),"player-facing load error")
	check(String(loaded.get("detail","")).to_lower().contains("schema"),"technical reason kept as detail")

func test_malformed_links_are_rejected_without_dropping_names() -> void:
	for key: String in ["garbage","08,8,open>9,8,open","9,8,open>8,8,open","8,8,rail>9,8,open","127,8,open>128,8,open","8,8,open>10,8,open","8,8,open>>9,8,open"]:
		var block := _wire()
		block.links = {key:"1"}
		_reject(block,key)
	for id: Variant in ["0","-1","2","01",1,1.5,true,null]:
		var block := _wire()
		block.links["8,8,open>9,8,open"] = id
		_reject(block,"invalid/dangling ID")

func test_invalid_registry_ids_names_and_next_bounds_are_rejected() -> void:
	for value: Variant in [null,[],{},true]: _reject(value,"block shape")
	for schema: Variant in ["1",true,0,1.5,null]:
		var invalid_schema := _wire()
		invalid_schema.schema = schema
		_reject(invalid_schema,"schema type")
	var extra := _wire()
	extra.draft = "Unapplied"
	_reject(extra,"unapplied/unknown field")
	for field: String in ["streets","links","station_auto"]:
		var invalid_registry := _wire()
		invalid_registry[field] = []
		_reject(invalid_registry,"registry type")
	for field: String in StreetNamingCodec.FIELDS:
		var block := _wire()
		block.erase(field)
		_reject(block,"missing field")
	for id: Variant in ["0","-1","01","9223372036854775808",1]:
		var block := _wire()
		block.streets = {id:"Palm Avenue"}
		_reject(block,"street ID")
	for next: Variant in ["0","-1","1","02","9223372036854775808",2,2.5,null]:
		var block := _wire()
		block.next_street_id = next
		_reject(block,"next ID")
	for name: Variant in [" Palm Avenue ","Palm  Avenue","Palm\nAvenue","X".repeat(49),5]:
		var block := _wire()
		block.streets["1"] = name
		_reject(block,"name")
	var duplicate := _wire()
	duplicate.next_street_id = "3"
	duplicate.streets["2"] = "palm avenue"
	_reject(duplicate,"normalized duplicate")

func test_station_anchor_record_and_source_validation_precedes_repair() -> void:
	for value: Variant in [null,[],{},true]:
		var block := _wire()
		block.station_auto["9,9"] = value
		_reject(block,"automatic record shape")
	for anchor: Variant in ["-1,9","128,9","09,9","9,9,open","9,,9",Vector2i(9,9)]:
		var block := _wire()
		block.station_auto[anchor] = {"source_street_ids":["1"],"base_name":"Palm Avenue","suffix":"0","display_name":"Palm Avenue"}
		_reject(block,"station anchor")
	for change: Dictionary in [{"source_street_ids":["2"]},{"source_street_ids":["1","1"]},{"source_street_ids":[]},{"source_street_ids":[1]},{"suffix":"1"},{"suffix":"-1"},{"suffix":"00"},{"suffix":"9223372036854775808"},{"suffix":0},{"display_name":"Wrong"},{"base_name":" Palm Avenue"}]:
		var block := _wire()
		var record := {"source_street_ids":["1"],"base_name":"Palm Avenue","suffix":"0","display_name":"Palm Avenue"}
		record.merge(change,true)
		block.station_auto["9,9"] = record
		_reject(block,"automatic station record")

func test_wire_shape_and_station_names_survive_real_json() -> void:
	var city := _named()
	city.building.put(9,9,Buildings.SUBWAY_STATION)
	city.facilities[Vector2i(9,9)] = {"key":&"subway_station","name":"  My Custom Name  "}
	city.street_naming.station_auto[Vector2i(9,9)] = _auto()
	var document := SaveFormat.encode_city(city)
	check_eq(document.get("street_naming",{}),{"schema":1,"next_street_id":"2","streets":{"1":"Palm Avenue"},"links":{"8,8,open>9,8,open":"1","9,8,open>10,8,open":"1","10,8,open>11,8,open":"1","11,8,open>12,8,open":"1"},"station_auto":{"9,9":{"source_street_ids":["1"],"base_name":"Palm Avenue","suffix":"2","display_name":"Palm Avenue 2"}}})
	var decoded := SaveFormat.decode_city(JSON.parse_string(JSON.stringify(document,"",false)))
	check(decoded.city!=null,decoded.error)
	if decoded.city!=null:
		check_eq(decoded.city.street_naming,city.street_naming)
		check_eq(decoded.city.facilities[Vector2i(9,9)].name,"  My Custom Name  ")

func test_well_formed_stale_links_and_auto_records_reconcile_on_load() -> void:
	var city := _named()
	city.street_naming.station_auto[Vector2i(9,9)] = _auto()
	city.facilities[Vector2i(9,9)] = {"key":&"subway_station","name":"Exact custom"}
	city.building.put(10,8,0)
	var decoded := SaveFormat.decode_city(SaveFormat.encode_city(city))
	check(decoded.city!=null,decoded.error)
	if decoded.city==null: return
	check_eq(decoded.city.street_naming.links,{"8,8,open>9,8,open":1,"11,8,open>12,8,open":1})
	check_eq(decoded.city.street_naming.streets,{1:"Palm Avenue"})
	check_eq(decoded.city.street_naming.next_street_id,2)
	check(decoded.city.street_naming.station_auto.is_empty(),"physically absent station pruned")
	check_eq(decoded.city.facilities[Vector2i(9,9)].name,"Exact custom")
	for x: int in range(8,13): city.building.put(x,8,0)
	decoded = SaveFormat.decode_city(SaveFormat.encode_city(city))
	check(decoded.city!=null,decoded.error)
	if decoded.city!=null:
		check(decoded.city.street_naming.links.is_empty())
		check(decoded.city.street_naming.streets.is_empty())
		check_eq(decoded.city.street_naming.next_street_id,2,"retired IDs not recycled")

func test_decode_and_encode_have_independent_nested_metadata() -> void:
	var city := _named()
	var encoded := SaveFormat.encode_city(city)
	var first := SaveFormat.decode_city(encoded)
	var second := SaveFormat.decode_city(encoded)
	check(first.city!=null and second.city!=null)
	if first.city==null or second.city==null: return
	first.city.street_naming.streets[1] = "Changed"
	check_eq(second.city.street_naming.streets,{1:"Palm Avenue"})
	check_eq(city.street_naming.streets,{1:"Palm Avenue"})
	if encoded.has("street_naming"):
		encoded.street_naming.streets["1"] = "Document edit"
		check_eq(second.city.street_naming.streets,{1:"Palm Avenue"})

func test_maximum_integer_ids_and_suffix_roundtrip_without_precision_loss() -> void:
	for id: int in [9007199254740993,9223372036854775806]:
		var city := _named()
		city.street_naming.next_street_id = id+1
		city.street_naming.streets = {id:"Palm Avenue"}
		for key: String in city.street_naming.links: city.street_naming.links[key] = id
		city.building.put(9,9,Buildings.SUBWAY_STATION)
		city.street_naming.station_auto[Vector2i(9,9)] = {"source_street_ids":[id],"base_name":"Palm Avenue","suffix":id,"display_name":"Palm Avenue "+str(id)}
		var decoded := SaveFormat.decode_city(JSON.parse_string(JSON.stringify(SaveFormat.encode_city(city),"",false)))
		check(decoded.city!=null,decoded.error)
		if decoded.city!=null: check_eq(decoded.city.street_naming,city.street_naming)

func test_native_and_recovery_paths_preserve_order_snapshot_rng_and_city() -> void:
	var city := _named()
	var simulation := make_simulation(city,98765)
	var snapshot := simulation.snapshot()
	var before := SaveFormat.encode_city(city)
	var metadata_before := var_to_bytes(city.street_naming)
	var snap_before := var_to_bytes(snapshot)
	var rng_before := simulation.rng.state()
	for filename: String in ["manual.sc2d","recovery.sc2d"]:
		var path := _dir.path_join(filename)
		check_eq(SaveFormat.save(path,city,snapshot),OK)
		var text := FileAccess.get_file_as_string(path)
		var wire: Dictionary = JSON.parse_string(text)
		check_eq(int(wire.version),1)
		var loaded := SaveFormat.load(path)
		check(loaded.ok,loaded.error)
		if loaded.ok:
			check_eq(SaveFormat.encode_city(loaded.city),before)
			var resumed := make_simulation(loaded.city,0)
			resumed.restore(loaded.snapshot)
			check_eq(resumed.rng.state(),rng_before,"native/recovery exact RNG restoration")
			check_eq(JSON.stringify(loaded.snapshot,"",false),JSON.stringify(JSON.parse_string(JSON.stringify(snapshot,"",false)),"",false),"complete ordered snapshot retained")
	check_eq(var_to_bytes(city.street_naming),metadata_before)
	check_eq(var_to_bytes(simulation.snapshot()),snap_before)
	check_eq(simulation.rng.state(),rng_before)

func test_failed_save_keeps_previous_applied_naming() -> void:
	var city := _named()
	var path := _dir.path_join("kept.sc2d")
	check_eq(SaveFormat.save(path,city),OK)
	var original := FileAccess.get_file_as_bytes(path)
	var original_names := city.street_naming.duplicate(true)
	var folder := _dir.path_join("unwritable.sc2d")
	DirAccess.make_dir_recursive_absolute(folder)
	city.street_naming.streets[1] = "New applied name"
	check_ne(SaveFormat.save(folder,city),OK)
	check_eq(FileAccess.get_file_as_bytes(path),original)
	var loaded := SaveFormat.load(path)
	check(loaded.ok,loaded.error)
	if loaded.ok: check_eq(loaded.city.street_naming,original_names)
	DirAccess.remove_absolute(folder)

func test_read_only_sc2_import_initializes_empty_naming_and_native_roundtrip() -> void:
	var source := "res://assets/cities/Foothills Ranch.sc2"
	var before := FileAccess.get_file_as_bytes(source)
	check(not before.is_empty(),"bundled city fixture available")
	var imported := Sc2Import.load(source)
	check(imported.ok,imported.error)
	if not imported.ok: return
	check_eq(imported.city.street_naming,StreetNamingCodec.empty_metadata())
	var facilities: Dictionary = imported.city.facilities.duplicate(true)
	var path := _dir.path_join("import-copy.sc2d")
	check_eq(SaveFormat.save(path,imported.city),OK)
	var loaded := SaveFormat.load(path)
	check(loaded.ok,loaded.error)
	if loaded.ok:
		check_eq(loaded.city.street_naming,StreetNamingCodec.empty_metadata())
		check_eq(loaded.city.facilities,facilities)
	check_eq(FileAccess.get_file_as_bytes(source),before,"import leaves the source file unchanged")

func test_invalid_runtime_metadata_rejects_save_before_replacement() -> void:
	var city := _named()
	var path := _dir.path_join("invalid-runtime.sc2d")
	check_eq(SaveFormat.save(path,city),OK)
	var original := FileAccess.get_file_as_bytes(path)
	city.street_naming.links["8,8,open>9,8,open"] = 77
	check_eq(SaveFormat.save(path,city),ERR_INVALID_DATA,"runtime codec failure prevents replacing a committed city")
	check_eq(FileAccess.get_file_as_bytes(path),original)
