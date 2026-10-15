# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const DIR := "user://test_saves"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(DIR)


## A generated city dressed with buildings, facilities, signs and stats.
func _sample_city() -> City:
	var c := TerrainGenerator.new().generate({"coast": "north", "name": "Saltwash", "hills": 55}, SimRng.new(42))
	c.mayor = "Tester"
	c.day = 1234
	c.funds = 987
	c.difficulty = City.Difficulty.MEDIUM
	c.rotation = 2
	c.status = 3
	c.stamp_building(40, 40, Buildings.COAL_PLANT)
	c.add_facility(Vector2i(40, 40), {"key": &"plant_coal", "built_day": 12, "age": 3, "output": 2500})
	c.stamp_building(50, 50, Buildings.RES_2X2_FIRST, Zones.RES_HIGH)
	c.underground.put(60, 60, 5)
	c.set_flag(40, 40, TileFlags.POWERED, true)
	c.traffic.put(3, 4, 77)
	c.pollution.put(5, 6, 66)
	c.land_value.put(7, 8, 55)
	c.crime.put(9, 10, 44)
	c.police.put(1, 2, 33)
	c.fire_cover.put(3, 4, 22)
	c.density.put(5, 6, 11)
	c.growth.put(7, 8, 9)
	c.signs[Vector2i(12, 13)] = "Old Mine Road"
	return c


func test_round_trip_preserves_everything() -> void:
	var c := _sample_city()
	var snapshot := {"clock_day": 1234, "stats": {"population": 5400, "arcology_population": 0}, "systems": {"power": {"a": 1}}}
	var path := DIR.path_join("roundtrip.sc2d")
	check_eq(SaveFormat.save(path, c, snapshot), OK)
	var loaded := SaveFormat.load(path)
	check(loaded["ok"], loaded["error"])
	check_eq(loaded["version"], SaveFormat.VERSION)
	var d: City = loaded["city"]
	check_eq(d.name, "Saltwash")
	check_eq(d.mayor, "Tester")
	check_eq(d.founded_year, c.founded_year)
	check_eq(d.day, 1234)
	check_eq(d.funds, 987)
	check_eq(d.difficulty, City.Difficulty.MEDIUM)
	check_eq(d.rotation, 2)
	check_eq(d.sea_level, c.sea_level)
	check_eq(d.status, 3)
	check_eq(d.terrain.data, c.terrain.data, "terrain")
	check_eq(d.altitude.data, c.altitude.data, "altitude")
	check_eq(d.building.data, c.building.data, "building")
	check_eq(d.zone.data, c.zone.data, "zone")
	check_eq(d.flags.data, c.flags.data, "flags")
	check_eq(d.underground.data, c.underground.data, "underground")
	check_eq(d.traffic.data, c.traffic.data, "traffic")
	check_eq(d.pollution.data, c.pollution.data, "pollution")
	check_eq(d.land_value.data, c.land_value.data, "land_value")
	check_eq(d.crime.data, c.crime.data, "crime")
	check_eq(d.police.data, c.police.data, "police")
	check_eq(d.fire_cover.data, c.fire_cover.data, "fire_cover")
	check_eq(d.density.data, c.density.data, "density")
	check_eq(d.growth.data, c.growth.data, "growth")
	check_eq(d.signs.get(Vector2i(12, 13), ""), "Old Mine Road")
	check_eq(d.signs.size(), 1)
	var rec: Dictionary = d.facility(Vector2i(40, 40))
	check_eq(rec.get("key"), &"plant_coal")
	check(rec.get("key") is StringName, "facility key restored as StringName")
	check_eq(rec.get("built_day"), 12)
	check_eq(rec.get("output"), 2500)
	check(rec.get("output") is int, "integers stay integers")
	check_eq(d.facilities.size(), 1)
	check(d.terrain_surface != null, "surface restored")
	check_eq(d.terrain_surface.vertices, c.terrain_surface.vertices, "lattice vertices")
	check_eq(d.terrain_surface.water, c.terrain_surface.water, "lattice water")
	check_eq(d.terrain_surface.feature, c.terrain_surface.feature, "lattice features")
	var snap: Dictionary = loaded["snapshot"]
	check_eq(int(snap["clock_day"]), 1234)
	check_eq(int(snap["stats"]["population"]), 5400)
	check_eq(int(snap["systems"]["power"]["a"]), 1)


func test_list_saves_reads_headers() -> void:
	var c := _sample_city()
	c.name = "Listed Town"
	var path := DIR.path_join("listed.sc2d")
	check_eq(SaveFormat.save(path, c, {"stats": {"population": 1200, "arcology_population": 300}}), OK)
	var other := DIR.path_join("notes.txt")
	var f := FileAccess.open(other, FileAccess.WRITE)
	f.store_string("not a save")
	f.close()
	var bogus := DIR.path_join("bogus.sc2d")
	f = FileAccess.open(bogus, FileAccess.WRITE)
	f.store_string("{\"format\": \"other\"}")
	f.close()
	var entries := SaveFormat.list_saves(DIR)
	var found := false
	for e in entries:
		check(String(e["path"]).ends_with(".sc2d"), "only saves are listed")
		if e["name"] == "Listed Town":
			found = true
			check_eq(e["population"], 1200, "population counts permanent residents")
			check_eq(e["tourists"], 0, "unknown legacy occupant history is not invented")
			check_eq(e["year"], c.current_year())
			check_eq(e["day"], c.day)
			check_eq(e["funds"], 987)
			check(String(e["date_text"]).length() > 8, "has a date")
	check(found, "listed save found")
	for e in entries:
		check_ne(e["path"], bogus, "unrelated documents are skipped")


func test_load_errors() -> void:
	var missing := SaveFormat.load(DIR.path_join("nope.sc2d"))
	check(not missing["ok"])
	check_ne(missing["error"], "")
	var junk := DIR.path_join("junk.sc2d")
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("[1, 2, 3]")
	f.close()
	check(not SaveFormat.load(junk)["ok"], "non-document rejected")
	var future := DIR.path_join("future.sc2d")
	f = FileAccess.open(future, FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": "sc2d", "version": 99, "city": {}}))
	f.close()
	var r := SaveFormat.load(future)
	check(not r["ok"], "future version rejected")
	check_eq(r["version"], 99)


func test_default_dir() -> void:
	check(SaveFormat.default_dir().begins_with("user://"))


func test_documents_missing_required_fields_are_rejected() -> void:
	for field: String in ["terrain_model", "street_naming"]:
		var doc := SaveFormat.encode_city(flat_city(100, 5))
		doc.erase(field)
		var decoded := SaveFormat.decode_city(doc)
		check(decoded.city == null, "missing %s is a load error" % field)
		check_ne(decoded.error, "")
	var path := DIR.path_join("no-stage.sc2d")
	check_eq(SaveFormat.save(path, flat_city()), OK)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	saved.erase("stage")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved))
	file.close()
	var loaded := SaveFormat.load(path)
	check(not loaded.ok, "a save without a stage is rejected")
	check_ne(loaded.error, "")


func test_damaged_terrain_vertices_are_a_load_error() -> void:
	var doc := SaveFormat.encode_city(_sample_city())
	doc["terrain_vertices"] = SaveFormat.encode_bytes(PackedByteArray([1, 2, 3]))
	var decoded := SaveFormat.decode_city(doc)
	check(decoded.city == null, "short vertex data does not silently rebuild terrain")
	check_ne(decoded.error, "")


func _per_tile_city() -> City:
	var city := flat_city(100, 5)
	# Independent imported slope words disagree at shared corners. They must
	# retain their own geometry instead of becoming a maximum-height lattice.
	city.terrain.put(10, 10, Terrain.SLOPE_E)
	city.set_heights(10, 10, 7, 7)
	city.terrain.put(11, 10, Terrain.SURFACE | Terrain.SLOPE_E)
	city.set_heights(11, 10, 7, 7)
	city.terrain.put(11, 11, 0x3e)
	city.set_heights(11, 11, 6, 6)
	city.terrain.put(12, 11, 0x2e)
	city.set_heights(12, 11, 4, 4)
	city.terrain.put(12, 12, Terrain.SHORE | Terrain.SLOPE_N)
	city.set_heights(12, 12, 4, 5)
	city.terrain.put(13, 12, Terrain.SUBMERGED)
	city.set_heights(13, 12, 4, 5)
	return city


func _terrain_samples(city: City) -> Array:
	var samples: Array = []
	for cell: Vector2i in [Vector2i(10, 10), Vector2i(11, 10), Vector2i(11, 11),
			Vector2i(12, 11), Vector2i(12, 12), Vector2i(13, 12), Vector2i(10, 11)]:
		samples.append([CityGeometry3D.cell_corners(city, cell),
			CityGeometry3D.visible_cell_corners(city, cell),
			CityGeometry3D.surface_corners(city, cell),
			CityGeometry3D.water_surface_height(city, cell),
			CityGeometry3D.surface_height(city, cell)])
	return samples


func test_per_tile_ownership_and_geometry_survive_two_round_trips() -> void:
	var city := _per_tile_city()
	var samples := _terrain_samples(city)
	var layers: Dictionary = SaveFormat.encode_city(city).layers
	for cycle: int in 2:
		var encoded := SaveFormat.encode_city(city)
		check_eq(encoded.get("terrain_model", ""), "per_tile", "explicit per-tile ownership")
		check(not encoded.has("terrain_vertices"), "per-tile saves have no lattice")
		var decoded := SaveFormat.decode_city(JSON.parse_string(JSON.stringify(encoded)))
		check(decoded.city != null, decoded.error)
		if decoded.city == null:
			return
		city = decoded.city
		check(city.terrain_surface == null, "per-tile owner survives cycle %d" % cycle)
		check_eq(_terrain_samples(city), samples, "water, banks and picking geometry survive cycle %d" % cycle)
		check_eq(SaveFormat.encode_city(city).layers, layers, "every raw layer survives cycle %d" % cycle)


func test_public_save_load_preserves_per_tile_owner() -> void:
	var city := _per_tile_city()
	var before := _terrain_samples(city)
	var path := DIR.path_join("per-tile.sc2d")
	check_eq(SaveFormat.save(path, city), OK)
	var loaded := SaveFormat.load(path)
	check(loaded.ok, loaded.error)
	if not loaded.ok:
		return
	check(loaded.city.terrain_surface == null, "public loader preserves per-tile ownership")
	check_eq(_terrain_samples(loaded.city), before)


func test_native_vertices_remain_the_terrain_owner() -> void:
	var city := _sample_city()
	var doc := SaveFormat.encode_city(city)
	check(doc.has("terrain_vertices"))
	check(not doc.has("terrain_model"), "native vertex saves keep their existing representation")
	var decoded := SaveFormat.decode_city(doc)
	check(decoded.city != null, decoded.error)
	if decoded.city == null:
		return
	check(decoded.city.terrain_surface is TerrainSurface)
	check_eq(decoded.city.terrain_surface.vertices, city.terrain_surface.vertices)
	check_eq(decoded.city.terrain_surface.water, city.terrain_surface.water)
	check_eq(decoded.city.terrain_surface.feature, city.terrain_surface.feature)


func test_malformed_or_conflicting_terrain_ownership_is_rejected() -> void:
	for marker: Variant in [null, 5, true, [], {}, "unknown", ""]:
		var doc := SaveFormat.encode_city(_per_tile_city())
		doc["terrain_model"] = marker
		var decoded := SaveFormat.decode_city(doc)
		check(decoded.city == null, "malformed explicit ownership is rejected")
		check_ne(decoded.error, "")
	for vertices: Variant in ["", "not compressed vertices", SaveFormat.encode_city(_sample_city()).terrain_vertices]:
		var doc := SaveFormat.encode_city(_per_tile_city())
		doc["terrain_model"] = "per_tile"
		doc["terrain_vertices"] = vertices
		var decoded := SaveFormat.decode_city(doc)
		check(decoded.city == null, "per-tile ownership cannot also claim vertices")
		check_ne(decoded.error, "")


func test_a_damaged_snapshot_is_refused_before_anything_is_replaced() -> void:
	var c := _sample_city()
	var cases := [
		{"systems": {"budget": {"carry": []}}},
		{"systems": {"neighbors": {"connections": [1, 2, 3, 4]}}},
		{"systems": {"zones": {"raw_demand": "lots"}}},
		{"systems": {"population": []}},
		{"systems": []},
		{"stats": {"demand": 5}},
		{"stats": {"ledger": [1, 2]}},
		{"stats": {"population": {"x": 1}}},
		{"clock_day": {"day": 1}},
	]
	for snapshot: Dictionary in cases:
		var path := DIR.path_join("damaged.sc2d")
		check_eq(SaveFormat.save(path, c, snapshot), ERR_INVALID_DATA)
		_write_damaged_snapshot(path, c, snapshot)
		var loaded := SaveFormat.load(path)
		check(not bool(loaded["ok"]), "refused: %s" % JSON.stringify(snapshot))
		check_eq(loaded["error"], SaveFormat.MESSAGE_DAMAGED)
		check(loaded["city"] == null, "no half-loaded city is handed back")


func test_nested_snapshot_damage_is_refused_before_restore() -> void:
	var cases := [
		{"systems": {"newspaper": {"queue": [{"kind": "disaster_started", "args": {"x": [], "y": 1}, "priority": 2, "born_day": 0, "seq": 0}]}}},
		{"systems": {"newspaper": {"queue": [{"kind": "disaster_started", "args": {"at": [{}, 1]}, "priority": 2, "born_day": 0, "seq": 0}]}}},
		{"systems": {"newspaper": {"queue": [{"kind": "disaster_started", "args": {"count": []}, "priority": 2, "born_day": 0, "seq": 0}]}}},
		{"systems": {"newspaper": {"queue": [{"kind": "disaster_started", "args": {"need": []}, "priority": 2, "born_day": 0, "seq": 0}]}}},
		{"systems": {"newspaper": {"queue": [{"kind": "disaster_started", "args": {"kind": []}, "priority": 2, "born_day": 0, "seq": 0}]}}},
		{"stats": {"neighbor_populations": []}},
		{"stats": {"bonds": [{"principal": []}]}},
		{"stats": {"history": {"population": {}}}},
		{"systems": {"population": {"complaints": [1]}}},
		{"systems": {"rewards": {"military": {"sites": [1]}}}},
		{"systems": {"budget": {"carry": {"taxes": []}}}},
		{"systems": {"newspaper": {"queue": [{"priority": []}]}}},
		{"systems": {"economy": {"sector_base": 1}}},
		{"systems": {"ports": {"vehicles": [1]}}},
		{"systems": {"ports": {"centre": []}}},
		{"systems": {"ports": {"centre": [0, {}]}}},
		{"systems": {"ports": {"vehicles": [{"target": [0]}]}}},
		{"systems": {"ports": {"vehicles": [{"route": [0, {}]}]}}},
		{"systems": {"services": {"prisons": {"0,0": 1}}}},
		{"systems": {"services": {"prisons": {"0,0": {"inmates": []}}}}},
		{"systems": {"disasters": {"entities": [1]}}},
		{"systems": {"disasters": {"entities": [{}]}}},
		{"systems": {"disasters": {"crews": [1]}}},
		{"systems": {"disasters": {"fires": {"0,0": []}}}},
		{"systems": {"disasters": {"active": {"kind": "earthquake"}}}},
	]
	for snapshot: Dictionary in cases:
		var path := DIR.path_join("nested-damage.sc2d")
		check_eq(SaveFormat.save(path, flat_city(), snapshot), ERR_INVALID_DATA)
		_write_damaged_snapshot(path, flat_city(), snapshot)
		var loaded := SaveFormat.load(path)
		check(not loaded.ok, "nested damage refused: %s" % JSON.stringify(snapshot))
		check_eq(loaded.error, SaveFormat.MESSAGE_DAMAGED)
		check(loaded.city == null)


func test_valid_nested_records_and_legacy_absent_fields_still_load() -> void:
	var sim := Simulation.new()
	sim.setup(flat_city(), 7)
	check(sim.request_disaster(&"earthquake", Vector2i(40, 40)))
	var snapshot := sim.snapshot()
	var path := DIR.path_join("nested-valid.sc2d")
	check_eq(SaveFormat.save(path, sim.city, snapshot), OK)
	var loaded := SaveFormat.load(path)
	check(loaded.ok, str(loaded.get("detail", "")))
	check_eq(loaded.snapshot.systems.disasters, JSON.parse_string(JSON.stringify(snapshot.systems.disasters, "", false)))
	for legacy: Dictionary in [{}, {"systems": {"ports": {}, "services": {}, "disasters": {}}}]:
		check_eq(SaveFormat.save(path, flat_city(), legacy), OK)
		check(SaveFormat.load(path).ok, "missing legacy fields retain defaults")
	sim.free()


func test_populated_port_and_prison_records_survive_native_roundtrip() -> void:
	var city := flat_city()
	var ctx := make_context(city, 11)
	for y in range(20, 24):
		for x in range(20, 26):
			city.zone.put(x, y, Zones.make(Zones.AIRPORT))
			city.set_flag(x, y, TileFlags.POWERED, true)
	for x in range(20, 20 + PortParams.RUNWAY_LENGTH):
		city.building.put(x, 20, Buildings.RUNWAY)
	var ports = preload("res://scripts/sim/port_system.gd").new()
	ports.setup(ctx)
	for day in 100:
		ports.daily(ctx)
		ctx.clock.advance()
		if not ports.vehicles().is_empty(): break
	check(not ports.vehicles().is_empty(), "real operating airport creates saved vehicle records")
	city.stamp_building(60, 60, Buildings.PRISON)
	city.crime.fill(60)
	var services := ServicesSystem.new()
	services.setup(ctx)
	services.monthly(ctx)
	var prison_records: Dictionary = services.save().prisons
	check(not prison_records.is_empty(), "real prison scan creates saved records")
	check_gt(int(prison_records["60,60"].inmates), 0, "record includes real arrests")
	var snapshot := {"systems": {"ports": ports.save(), "services": services.save()}}
	var path := DIR.path_join("populated-records.sc2d")
	check_eq(SaveFormat.save(path, city, snapshot), OK)
	var loaded := SaveFormat.load(path)
	check(loaded.ok, str(loaded.get("detail", "")))
	var expected: Dictionary = JSON.parse_string(JSON.stringify(snapshot, "", false))
	check_eq(loaded.snapshot, expected, "all populated nested records retain their saved values")
	var restored_ports = preload("res://scripts/sim/port_system.gd").new()
	restored_ports.setup(make_context(loaded.city))
	restored_ports.load(loaded.snapshot.systems.ports)
	check_eq(restored_ports.vehicles(), ports.vehicles())
	var restored_services := ServicesSystem.new()
	restored_services.load(loaded.snapshot.systems.services)
	check_eq(restored_services.prison_report(), services.prison_report())


func test_conditional_and_populated_system_schemas_keep_valid_snapshots() -> void:
	var included := SaveFormat.load("res://assets/cities/Adaven.sc2d")
	check(included.ok)
	var sim := Simulation.new()
	sim.setup(included.city, 17, null, included.snapshot)
	sim.restore(included.snapshot)
	# A real March population pass generates complaint records from this city.
	sim.clock.day = (sim.clock.day / GameClock.DAYS_PER_YEAR) * GameClock.DAYS_PER_YEAR + 2 * GameClock.DAYS_PER_MONTH + 13
	sim.city.day = sim.clock.day
	var population := sim.get_system(&"population") as PopulationSystem
	population.monthly(sim._ctx)
	check(not population.save().complaints.is_empty(), "March vote creates complaint records")
	var budget := sim.get_system(&"budget") as BudgetSystem
	budget.monthly(sim._ctx)
	check(not budget.save().carry.is_empty(), "budget pass creates fractional account records")
	check(budget.issue_bond(), "ordinary eligible city creates a real bond record")
	var newspaper: Variant = sim.get_system(&"newspaper")
	newspaper.monthly(sim._ctx)
	check(not sim.stats.newspaper_archive.is_empty(), "real issue records enter the saved archive")
	sim.get_system(&"statistics").monthly(sim._ctx)
	check(not sim.stats.history.is_empty(), "real monthly graph samples enter saved history")
	newspaper.submit(sim._ctx, &"city_milestone", {"population": sim.stats.population}, 2)
	check(not newspaper.save().queue.is_empty(), "real news enters the saved queue")
	var economy := sim.get_system(&"economy") as EconomySystem
	sim.stats.sector_taxes[0] = 2
	economy.sector_taxes_changed()
	sim.stats.tax_industrial = 20
	economy.industrial_rate_written()
	check(economy.save().has("sector_base"), "Budget shift stores its conditional sector spread")
	var rewards: Variant = sim.get_system(&"rewards")
	var sites: Array[Rect2i] = rewards._find_missile_sites(sim._ctx)
	check(not sites.is_empty(), "real site finder produces usable military rectangles")
	# Use the existing wire codec/load path to retain a legacy pending proposal.
	rewards.load({"military": {"kind": "missile", "sites": rewards._rects_to_array(sites)}})
	var snapshot := sim.snapshot()
	var path := DIR.path_join("conditional-records.sc2d")
	check_eq(SaveFormat.save(path, sim.city, snapshot), OK)
	var loaded := SaveFormat.load(path)
	check(loaded.ok, str(loaded.get("detail", "")))
	check_eq(loaded.snapshot, JSON.parse_string(JSON.stringify(snapshot, "", false)), "full populated snapshot remains exact")
	var restored := Simulation.new()
	restored.setup(loaded.city, 17, null, loaded.snapshot)
	restored.restore(loaded.snapshot)
	# JSON restores numeric values in typed bond records as floats; compare
	# their saved values through the same wire representation on both sides.
	check_eq(JSON.parse_string(JSON.stringify(restored.snapshot(), "", false)),
		JSON.parse_string(JSON.stringify(sim.snapshot(), "", false)), "restored runtime keeps all saved values")
	restored.free()
	sim.free()


func test_valid_newspaper_argument_forms_and_custom_payload_roundtrip() -> void:
	var cases: Array[Dictionary] = [
		{}, {"count": 3}, {"amount": 12.5}, {"count": "several"},
		{"need": "needs_water"}, {"kind": "tornado", "x": "12", "y": "13"},
		{"x": true, "y": false},
		{"count": 3, "custom_payload": {"list": [{"arbitrary": []}]}},
	]
	for field: String in NewsStories.PLACE_KEYS:
		cases.append({field: [12, 13]})
		cases.append({field: ["12", "13"]})
		cases.append({field: "12,13"})
	var path := DIR.path_join("news-arguments.sc2d")
	for args: Dictionary in cases:
		var row := {"kind": "disaster_started", "args": args, "priority": 2, "born_day": 0, "seq": 0}
		var snapshot := {"systems": {"newspaper": {"queue": [row]}}}
		check_eq(SaveFormat.save(path, flat_city(), snapshot), OK)
		var loaded := SaveFormat.load(path)
		check(loaded.ok, "valid news arguments: %s (%s)" % [str(args), str(loaded.get("detail", ""))])
		check_eq(loaded.snapshot, JSON.parse_string(JSON.stringify(snapshot, "", false)), "wire forms and custom keys preserved")
		var paper = preload("res://scripts/sim/newspaper_system.gd").new()
		paper.load(loaded.snapshot.systems.newspaper)
		var restored_args: Dictionary = paper.pending()[0].args
		check_eq(NewsStories.values_for(&"disaster_started", restored_args, "City", "Mayor", 2000),
			NewsStories.values_for(&"disaster_started", args, "City", "Mayor", 2000), "restored formatting matches")
		check_eq(NewsStories.template_key(&"disaster_started", restored_args),
			NewsStories.template_key(&"disaster_started", args), "restored template matches")
		paper.monthly(make_context(loaded.city))


func test_a_running_city_snapshot_passes_the_shape_check() -> void:
	var c := flat_city()
	var sim := Simulation.new()
	sim.setup(c, 3)
	sim.advance_days(40)
	var path := DIR.path_join("running.sc2d")
	check_eq(SaveFormat.save(path, sim.city, sim.snapshot()), OK)
	var loaded := SaveFormat.load(path)
	check(bool(loaded["ok"]), str(loaded.get("detail", "")))
	check((loaded["city"] as City).restored_layers.has("density"), "loaded layers are marked as saved ones")
	sim.free()
	for city_name in ["Adaven", "Oro Canyon"]:
		var included := SaveFormat.load("res://assets/cities/%s.sc2d" % city_name)
		check(bool(included["ok"]), "%s: %s" % [city_name, str(included.get("detail", ""))])


func test_stats_tables_hold_whole_numbers_after_a_load() -> void:
	var stats := CityStats.new()
	stats.ledger[&"neighbor_trade"] = 0
	stats.ledger[&"residential_tax"] = 1234
	stats.inventions[&"legacy_tech"] = 1951
	var restored := CityStats.new()
	restored.from_dict(JSON.parse_string(JSON.stringify(stats.to_dict())))
	for k in restored.ledger:
		check_eq(typeof(restored.ledger[k]), TYPE_INT, "ledger %s" % k)
	check_eq(typeof(restored.inventions[&"legacy_tech"]), TYPE_INT, "inventions")
	check_eq(str(restored.inventions[&"legacy_tech"]), "1951")


func _write_damaged_snapshot(path: String, city: City, snapshot: Dictionary) -> void:
	# The writer now rejects malformed snapshots; inject external corrupt bytes
	# explicitly so the independent reader rejection remains under test.
	var doc := {"format": SaveFormat.FORMAT, "version": SaveFormat.VERSION,
		"stage": SaveFormat.STAGE_PLAY, "city": SaveFormat.encode_city(city), "snapshot": snapshot}
	check_eq(SaveFormat._write_replacement(path, JSON.stringify(doc).to_utf8_buffer()), OK)
