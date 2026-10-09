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
			check_eq(e["population"], 1500, "population counts arcologies")
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
		check_eq(SaveFormat.save(path, c, snapshot), OK)
		var loaded := SaveFormat.load(path)
		check(not bool(loaded["ok"]), "refused: %s" % JSON.stringify(snapshot))
		check_eq(loaded["error"], SaveFormat.MESSAGE_DAMAGED)
		check(loaded["city"] == null, "no half-loaded city is handed back")


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
