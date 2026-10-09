# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const DIR := "user://test_import"
const TILES := City.WIDTH * City.HEIGHT


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(DIR)


# ── Synthetic file builder ───────────────────────────────────────────────

static func _u32(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF])


static func _chunk(tag: String, data: PackedByteArray, packed: bool) -> PackedByteArray:
	var body := Sc2Import.rle_encode(data) if packed else data
	var out := PackedByteArray()
	out.append_array(tag.to_ascii_buffer())
	out.append_array(_u32(body.size()))
	out.append_array(body)
	return out


static func _container(chunks: Array) -> PackedByteArray:
	var body := PackedByteArray()
	for c in chunks:
		body.append_array(c)
	var out := PackedByteArray()
	out.append_array("FORM".to_ascii_buffer())
	out.append_array(_u32(body.size() + 4))
	out.append_array("SCDH".to_ascii_buffer())
	out.append_array(body)
	return out


static func _filled(size: int, value: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(size)
	b.fill(value)
	return b


static func _meta(values: Dictionary) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4800)
	for index in values:
		var v: int = values[index]
		var at: int = int(index) * 4
		b[at] = (v >> 24) & 0xFF
		b[at + 1] = (v >> 16) & 0xFF
		b[at + 2] = (v >> 8) & 0xFF
		b[at + 3] = v & 0xFF
	return b


static func _put16(b: PackedByteArray, x: int, y: int, v: int) -> void:
	var i := _idx(x, y) * 2
	b[i] = (v >> 8) & 0xFF
	b[i + 1] = v & 0xFF


## Classic files store grids column by column.
static func _idx(x: int, y: int) -> int:
	return x * City.HEIGHT + y


## A small but complete city: flat desert at height 6, one hill, a pond,
## a police station, a pump, a dense residential lot and some underground.
func _sample_file(with_cliff: bool = false) -> PackedByteArray:
	var altm := PackedByteArray()
	altm.resize(TILES * 2)
	for y in City.HEIGHT:
		for x in City.WIDTH:
			_put16(altm, x, y, 6)
	var xter := _filled(TILES, Terrain.FLAT)
	var xbld := _filled(TILES, 0)
	var xzon := _filled(TILES, 0)
	var xbit := _filled(TILES, 0)
	var xund := _filled(TILES, 0)
	# Hill: tile (10,10) one level up with sloped skirts.
	_put16(altm, 10, 10, 7)
	xter[_idx(9, 10)] = Terrain.SLOPE_E
	xter[_idx(11, 10)] = Terrain.SLOPE_W
	xter[_idx(10, 9)] = Terrain.SLOPE_S
	xter[_idx(10, 11)] = Terrain.SLOPE_N
	xter[_idx(9, 9)] = Terrain.CORNER_SE
	xter[_idx(11, 9)] = Terrain.CORNER_SW
	xter[_idx(9, 11)] = Terrain.CORNER_NE
	xter[_idx(11, 11)] = Terrain.CORNER_NW
	# Pond: (20,20) and (21,20) flooded to 7, salt on the first.
	_put16(altm, 20, 20, 6 | (7 << 5))
	_put16(altm, 21, 20, 6 | (7 << 5))
	xter[_idx(20, 20)] = Terrain.make(Terrain.FLAT, Terrain.SURFACE)
	xter[_idx(21, 20)] = Terrain.make(Terrain.FLAT, Terrain.SURFACE)
	xbit[_idx(20, 20)] = Sc2Import.FILE_SALT | Sc2Import.FILE_WATER_COVERED
	xbit[_idx(21, 20)] = Sc2Import.FILE_WATER_COVERED
	# Police station 3x3 at (30,30), powered and watered.
	for dy in 3:
		for dx in 3:
			xbld[_idx(30 + dx, 30 + dy)] = Buildings.POLICE_STATION
			xzon[_idx(30 + dx, 30 + dy)] = Zones.corner_flags_for(dx, dy, 3, 3)
			xbit[_idx(30 + dx, 30 + dy)] = Sc2Import.FILE_POWERED | Sc2Import.FILE_CONDUCTS_POWER | Sc2Import.FILE_WATERED | Sc2Import.FILE_CONDUCTS_WATER
	# Pump at (40,40); dense residential 2x2 at (50,50); a road at (45,45).
	xbld[_idx(40, 40)] = Buildings.WATER_PUMP
	xzon[_idx(40, 40)] = Zones.ALL_CORNERS
	for dy in 2:
		for dx in 2:
			xbld[_idx(50 + dx, 50 + dy)] = Buildings.RES_2X2_FIRST
			xzon[_idx(50 + dx, 50 + dy)] = Zones.make(Zones.RES_HIGH, Zones.corner_flags_for(dx, dy, 2, 2))
	xbld[_idx(45, 45)] = Buildings.ROAD_FIRST
	# Underground: pipe, subway, crossing, station link.
	xund[_idx(60, 60)] = Sc2Import.FILE_PIPE_FIRST + 3
	xund[_idx(61, 60)] = Sc2Import.FILE_SUBWAY_FIRST + 2
	xund[_idx(62, 60)] = Sc2Import.FILE_CROSSING_FIRST + 1
	xund[_idx(63, 60)] = Sc2Import.FILE_STATION_LINK
	xund[_idx(64, 60)] = 200
	if with_cliff:
		_put16(altm, 100, 100, 12)
	var cnam := PackedByteArray()
	cnam.resize(32)
	cnam[0] = 31
	var name := "Test Town".to_ascii_buffer()
	for i in name.size():
		cnam[1 + i] = name[i]
	var misc := _meta({
		Sc2Import.META_ROTATION: 1,
		Sc2Import.META_FOUNDED_YEAR: 1950,
		Sc2Import.META_DAYS: 3000,
		Sc2Import.META_FUNDS: 12345,
		Sc2Import.META_DIFFICULTY: 2,
		Sc2Import.META_STATUS: 2,
		Sc2Import.META_TAX_RESIDENTIAL: 9,
		Sc2Import.META_TAX_COMMERCIAL: 8,
		Sc2Import.META_TAX_INDUSTRIAL: 6,
	})
	var xtrf := _filled(City.HALF * City.HALF, 0)
	xtrf[4 * City.HALF + 3] = 99
	var xplc := _filled(City.QUARTER * City.QUARTER, 0)
	xplc[1 * City.QUARTER + 2] = 88
	return _container([
		_chunk("CNAM", cnam, false),
		_chunk("MISC", misc, true),
		_chunk("ALTM", altm, true),
		_chunk("XTER", xter, true),
		_chunk("XBLD", xbld, true),
		_chunk("XZON", xzon, true),
		_chunk("XUND", xund, true),
		_chunk("XBIT", xbit, true),
		_chunk("XTRF", xtrf, true),
		_chunk("XPLC", xplc, false),
		_chunk("XGRP", _filled(3328, 0), true),
	])


# ── Tests ────────────────────────────────────────────────────────────────

func test_rle_round_trip() -> void:
	var rng := SimRng.new(3)
	var data := PackedByteArray()
	for i in 5000:
		data.append(0 if rng.below(4) != 0 else rng.below(256))
	var packed := Sc2Import.rle_encode(data)
	check_lt(packed.size(), data.size(), "runs shrink")
	check_eq(Sc2Import.rle_decode(packed), data, "decode reverses encode")
	var literal := PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8])
	check_eq(Sc2Import.rle_decode(Sc2Import.rle_encode(literal)), literal)
	var run := _filled(1000, 42)
	check_eq(Sc2Import.rle_decode(Sc2Import.rle_encode(run)), run)


func test_import_maps_layers_and_metadata() -> void:
	var path := DIR.path_join("sample.sc2")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(_sample_file())
	f.close()
	var r := Sc2Import.load(path)
	check(r["ok"], r["error"])
	var c: City = r["city"]
	check_eq(c.name, "Test Town")
	check_eq(c.rotation, 1)
	check_eq(c.founded_year, 1950)
	check_eq(c.day, 3000)
	check_eq(c.funds, 12345)
	check_eq(c.difficulty, City.Difficulty.MEDIUM)
	check_eq(c.status, 2)
	check_eq(c.current_year(), 1960)
	check_eq(r["tax_rates"], {"residential": 9, "commercial": 8, "industrial": 6})
	# Terrain and altitude.
	check_eq(c.ground_height(10, 10), 7)
	check_eq(c.terrain.at(9, 10), Terrain.SLOPE_E)
	check_eq(c.ground_height(5, 5), 6)
	check(c.terrain_surface == null, "imported terrain is kept verbatim; no lattice until editing")
	check_eq((r["warnings"] as Array).size(), 0)
	# Water.
	check(c.is_water(20, 20))
	check_eq(c.water_height(20, 20), 7)
	check(c.is_salt_water(20, 20))
	check(not c.is_salt_water(21, 20))
	check_eq(c.sea_level, -1, "imports have per-tile water only")
	# Buildings, zones, facilities.
	check_eq(c.building.at(31, 31), Buildings.POLICE_STATION)
	check_eq(c.anchor_of(32, 32), Vector2i(30, 30))
	check_eq(c.building.at(40, 40), Buildings.WATER_PUMP)
	check_eq(c.zone_kind_at(51, 51), Zones.RES_HIGH)
	check_eq(c.anchor_of(51, 51), Vector2i(50, 50))
	check_eq(c.building.at(45, 45), Buildings.ROAD_FIRST)
	check_eq(c.facilities.size(), 2, "one record per civic building")
	check_eq(c.facility(Vector2i(30, 30)).get("key"), &"police_station")
	check_eq(c.facility(Vector2i(40, 40)).get("key"), &"water_pump")
	check(not c.facilities.has(Vector2i(50, 50)), "zone lots are not facilities")
	# Flags.
	check(c.is_powered(30, 30))
	check(c.conducts_power(31, 31))
	check(c.is_watered(32, 32))
	check(c.conducts_water(30, 32))
	check(not c.is_powered(5, 5))
	# Underground.
	# Original file shape 4 is a north-south grade (mask 5),
	# shape 3 an east-west grade (mask 10); these are not owned-art indices.
	check_eq(c.underground.at(60, 60), Underground.pipe_code(Underground.NORTH | Underground.SOUTH))
	check_eq(c.underground.at(61, 60), Underground.subway_code(Underground.EAST | Underground.WEST))
	check_eq(c.underground.at(62, 60), Underground.PIPE_NS_UNDER_SUBWAY_EW)
	check_eq(c.underground.at(63, 60), UtilityParams.SUBWAY_STATION_LINK)
	check_eq(c.underground.at(64, 60), UtilityParams.UNDERGROUND_NONE, "unknown codes are dropped")
	# Half and quarter maps.
	check_eq(c.traffic.at(4, 3), 99)
	check_eq(c.police.at(1, 2), 88)
	check_eq(c.pollution.at(4, 3), 0, "absent maps stay empty")


func test_import_keeps_cliffs() -> void:
	# Classic maps may hold vertical drops between tiles; they are imported as
	# stored, and only the editor builds a lattice when the player edits.
	var r := Sc2Import.load_bytes(_sample_file(true), "cliffs")
	check(r["ok"], r["error"])
	var c: City = r["city"]
	check_eq((r["warnings"] as Array).size(), 0, "nothing is repaired on import")
	check_eq(c.ground_height(100, 100), 12, "the spike is kept as stored")
	check(c.terrain_surface == null)
	var editor := TerrainEditor.new(c)
	check(c.terrain_surface != null, "the editor builds the lattice on demand")


func test_rejects_other_files() -> void:
	check(not Sc2Import.load_bytes("hello".to_ascii_buffer())["ok"])
	var wrong := _sample_file()
	wrong[9] = "X".to_ascii_buffer()[0]
	check(not Sc2Import.load_bytes(wrong)["ok"], "wrong content type")
	var missing := _container([_chunk("CNAM", _filled(32, 0), false)])
	var r := Sc2Import.load_bytes(missing)
	check(not r["ok"])
	check_ne(r["error"], "")
	check(not Sc2Import.load(DIR.path_join("absent.sc2"))["ok"])


func test_name_falls_back_to_file_name() -> void:
	var chunks := _container([
		_chunk("ALTM", _filled(TILES * 2, 0), true),
		_chunk("XTER", _filled(TILES, 0), true),
		_chunk("XBLD", _filled(TILES, 0), true),
	])
	var r := Sc2Import.load_bytes(chunks, "Dusty Flats")
	check(r["ok"], r["error"])
	check_eq((r["city"] as City).name, "Dusty Flats")
	check_eq((r["city"] as City).sea_level, -1, "no standing water, no sea level")
	check_gt((r["warnings"] as Array).size(), 0, "missing metadata is reported")


## A 25-byte label slot: a length byte then up to 24 characters.
static func _put_label(xlab: PackedByteArray, index: int, text: String) -> void:
	var bytes := text.to_ascii_buffer()
	xlab[index * 25] = bytes.size()
	for i in bytes.size():
		xlab[index * 25 + 1 + i] = bytes[i]


func test_import_reads_player_signs() -> void:
	var xtxt := _filled(TILES, 0)
	var xlab := _filled(6400, 0)
	_put_label(xlab, 0, "Mayor Name")
	_put_label(xlab, 1, "Pacific Ocean")
	_put_label(xlab, 2, "  Bayshore Freeway ")
	_put_label(xlab, 50, "Last Sign")
	_put_label(xlab, 51, "Facility Name")
	xtxt[_idx(12, 34)] = 1
	xtxt[_idx(100, 7)] = 2
	xtxt[_idx(127, 127)] = 50
	xtxt[_idx(40, 40)] = 51   # facility names are not signs
	xtxt[_idx(41, 40)] = 3    # an empty slot draws nothing
	xtxt[_idx(42, 40)] = 0xFA # moving things are not signs
	var chunks := _container([
		_chunk("ALTM", _filled(TILES * 2, 0), true),
		_chunk("XTER", _filled(TILES, 0), true),
		_chunk("XBLD", _filled(TILES, 0), true),
		_chunk("XTXT", xtxt, true),
		_chunk("XLAB", xlab, true),
	])
	var r := Sc2Import.load_bytes(chunks, "Signs")
	check(r["ok"], r["error"])
	var c: City = r["city"]
	check_eq(c.signs, {
		Vector2i(12, 34): "Pacific Ocean",
		Vector2i(100, 7): "Bayshore Freeway",
		Vector2i(127, 127): "Last Sign",
	}, "player signs keep their tile and text")


func test_dos_file_names_become_readable_city_names() -> void:
	check_eq(Sc2Import.city_name("FOO.SC2"), "Foo")
	check_eq(Sc2Import.city_name("OROCANYON.SC2", "Imported City"), "Orocanyon")
	check_eq(Sc2Import.city_name("OROCANYON.SC2", "Oro Canyon"), "Oro Canyon", "the file's own name reads better")
	check_eq(Sc2Import.city_name("Salton Shores"), "Salton Shores", "ordinary names are kept")
	check_eq(Sc2Import.city_name("NYC"), "NYC", "capitals without a file extension are a choice")
	var r := Sc2Import.load("res://assets/cities/Oro Canyon.sc2")
	check(r["ok"], r["error"])
	check_eq((r["city"] as City).name, "Oro Canyon")


func test_an_imported_city_opens_with_its_people_counted() -> void:
	for city_name in ["Oro Canyon", "Salton Shores"]:
		var r := Sc2Import.load("res://assets/cities/%s.sc2" % city_name)
		check(r["ok"], r["error"])
		var city: City = r["city"]
		check_lt(city.status, PopulationParams.STATUS_NAMES.size(), "a real class: " + city_name)
		var sim := Simulation.new()
		var stats := CityStats.new()
		sim.setup(city, 99, stats)
		var opened := sim.stats.total_population()
		check_gt(opened, 0, "%s reads its population on open" % city_name)
		check_gt(sim.stats.jobs, 0, "and its jobs")
		check_eq(city.status, mini(city.status, PopulationSystem.derived_status(opened)), "class no higher than its people")
		check_lt(sim.stats.education_quotient, 100, "scores come from the people, not placeholders")
		var invented: Array[Dictionary] = []
		var year := sim.clock.year()
		sim.news_published.connect(func(story: Dictionary) -> void:
			if story.get("kind", &"") == &"invention":
				invented.append(story))
		sim.advance_days(75)
		for story in invented:
			check_ge(int(story["args"]["year"]), year, "%s: no retroactive invention news (%s)" % [city_name, str(story["args"])])
		check_between(sim.stats.population, opened / 2, opened * 2, "%s: the first pass does not move the whole city in" % city_name)
		sim.free()


func test_salton_shores_is_not_a_megalopolis() -> void:
	var r := Sc2Import.load("res://assets/cities/Salton Shores.sc2")
	var sim := Simulation.new()
	sim.setup(r["city"], 5, CityStats.new())
	sim.advance_days(30)
	check(PopulationParams.status_name(sim.city.status) in ["Village", "Town"],
		"Salton Shores is a %s" % PopulationParams.status_name(sim.city.status))
	sim.free()
