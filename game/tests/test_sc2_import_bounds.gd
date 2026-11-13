# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## A classic city file is read as untrusted data: its calendar and treasury
## are kept within bounds and no building reaches past the map edge.

const TILES := City.WIDTH * City.HEIGHT


static func _u32(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF])


static func _chunk(tag: String, data: PackedByteArray) -> PackedByteArray:
	var body := Sc2Import.rle_encode(data)
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


## Classic files store grids column by column.
static func _idx(x: int, y: int) -> int:
	return x * City.HEIGHT + y


## A flat, empty city file with the given metadata and building layer.
func _import(meta: Dictionary, xbld: PackedByteArray = PackedByteArray(), xzon: PackedByteArray = PackedByteArray(), xbit: PackedByteArray = PackedByteArray()) -> Dictionary:
	var altm := PackedByteArray()
	altm.resize(TILES * 2)
	for i in TILES:
		altm[i * 2 + 1] = 6
	var chunks := [
		_chunk("MISC", _meta(meta)),
		_chunk("ALTM", altm),
		_chunk("XTER", _filled(TILES, Terrain.FLAT)),
		_chunk("XBLD", xbld if not xbld.is_empty() else _filled(TILES, 0)),
	]
	if not xzon.is_empty():
		chunks.append(_chunk("XZON", xzon))
	if not xbit.is_empty():
		chunks.append(_chunk("XBIT", xbit))
	return Sc2Import.load_bytes(_container(chunks), "Bounds")


func test_ordinary_calendar_and_funds_are_kept() -> void:
	var r := _import({Sc2Import.META_FOUNDED_YEAR: 1950, Sc2Import.META_DAYS: 3000, Sc2Import.META_FUNDS: -12345})
	check(bool(r["ok"]), String(r["error"]))
	var c: City = r["city"]
	check_eq(c.founded_year, 1950)
	check_eq(c.day, 3000)
	check_eq(c.funds, -12345, "a city in the red stays in the red")
	check(r["warnings"].is_empty())


func test_absurd_calendar_and_funds_are_bounded() -> void:
	var low := _import({Sc2Import.META_FOUNDED_YEAR: -2147483648, Sc2Import.META_DAYS: -5, Sc2Import.META_FUNDS: -2147483648})
	check(bool(low["ok"]), String(low["error"]))
	var c: City = low["city"]
	check_eq(c.founded_year, Sc2Import.YEAR_MIN)
	check_eq(c.day, 0)
	check_eq(c.funds, -Sc2Import.FUNDS_LIMIT)
	var high := _import({Sc2Import.META_FOUNDED_YEAR: 2147483647, Sc2Import.META_DAYS: 2147483647, Sc2Import.META_FUNDS: 2147483647})
	check(bool(high["ok"]), String(high["error"]))
	var d: City = high["city"]
	check_eq(d.founded_year, Sc2Import.YEAR_MAX)
	check_eq(d.funds, Sc2Import.FUNDS_LIMIT)
	check_eq(d.current_year(), Sc2Import.YEAR_MAX, "the calendar never passes its last year")
	var late := _import({Sc2Import.META_FOUNDED_YEAR: 2000, Sc2Import.META_DAYS: 2147483647})
	var e: City = late["city"]
	check_eq(e.founded_year, 2000)
	check_eq(e.current_year(), Sc2Import.YEAR_MAX)
	check_eq(e.day, (Sc2Import.YEAR_MAX - 2000 + 1) * GameClock.DAYS_PER_YEAR - 1)


func test_buildings_reaching_past_the_edge_are_removed() -> void:
	var xbld := _filled(TILES, 0)
	var xzon := _filled(TILES, 0)
	var xbit := _filled(TILES, 0)
	# A whole police station in the corner of the map: it fits and stays.
	for dy in 3:
		for dx in 3:
			xbld[_idx(125 + dx, 125 + dy)] = Buildings.POLICE_STATION
			xzon[_idx(125 + dx, 125 + dy)] = Zones.corner_flags_for(dx, dy, 3, 3)
	# Pieces of larger buildings hanging over the east and south edges.
	for y in range(10, 13):
		xbld[_idx(127, y)] = Buildings.COAL_PLANT
		xzon[_idx(127, y)] = Zones.make(Zones.IND_LOW, 0)
		xbit[_idx(127, y)] = Sc2Import.FILE_CONDUCTS_POWER | Sc2Import.FILE_POWERED
	for x in range(40, 42):
		xbld[_idx(x, 127)] = Buildings.POLICE_STATION
	# A stray piece inland and a road on the edge are left alone.
	xbld[_idx(60, 60)] = Buildings.POLICE_STATION
	xbld[_idx(127, 80)] = Buildings.ROAD_FIRST
	var r := _import({Sc2Import.META_FOUNDED_YEAR: 1950}, xbld, xzon, xbit)
	check(bool(r["ok"]), String(r["error"]))
	var c: City = r["city"]
	for y in range(10, 13):
		check_eq(c.building_at(127, y), Buildings.NONE, "east edge piece at %d" % y)
		check_eq(c.zone_kind_at(127, y), Zones.IND_LOW, "the zone under it stays")
		check(not c.conducts_power(127, y))
	for x in range(40, 42):
		check_eq(c.building_at(x, 127), Buildings.NONE, "south edge piece at %d" % x)
	check_eq(c.building_at(126, 126), Buildings.POLICE_STATION, "a lot that fits stays")
	check(c.facilities.has(Vector2i(125, 125)))
	check_eq(c.building_at(60, 60), Buildings.POLICE_STATION)
	check_eq(c.building_at(127, 80), Buildings.ROAD_FIRST)
	check_eq(c.facilities_of(&"coal_plant").size(), 0, "no plant is recorded for the removed pieces")
	check_eq(r["warnings"].size(), 1)
	# Every remaining lot lies inside the map.
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var size := Buildings.size(c.building_at(x, y))
			var anchor := c.anchor_of(x, y)
			check(anchor.x + size.x <= City.WIDTH and anchor.y + size.y <= City.HEIGHT, "lot at %d,%d fits" % [x, y])


func test_tunnel_marks_without_portals_are_dropped() -> void:
	var altm := PackedByteArray()
	altm.resize(TILES * 2)
	for i in TILES:
		altm[i * 2 + 1] = 6
	# A marked bore along row 40 with no portal at either end.
	for x in range(30, 36):
		altm[_idx(x, 40) * 2] = 2 << 2
	var r := Sc2Import.load_bytes(_container([
		_chunk("ALTM", altm),
		_chunk("XTER", _filled(TILES, Terrain.FLAT)),
		_chunk("XBLD", _filled(TILES, 0)),
	]), "Bounds")
	check(bool(r["ok"]), String(r["error"]))
	var c: City = r["city"]
	for x in range(30, 36):
		check_eq(c.tunnel_bits(x, 40), 0, "mark at %d" % x)
		check_eq(c.ground_height(x, 40), 6, "the ground is untouched")


func test_included_classic_cities_import_unchanged() -> void:
	for name: String in ["Valle del Mar", "Foothills Ranch", "La Presa"]:
		var r := Sc2Import.load("res://assets/cities/%s.sc2" % name)
		check(bool(r["ok"]), String(r["error"]))
		check(r["warnings"].is_empty(), "%s needs no repair" % name)
		check_eq((r["city"] as City).clear_orphan_tunnels(), 0, "%s keeps every tunnel" % name)
	var foothills: City = Sc2Import.load("res://assets/cities/Foothills Ranch.sc2")["city"]
	var marked := 0
	for v in foothills.altitude.data:
		if v >> City.TUNNEL_SHIFT != 0:
			marked += 1
	check_eq(marked, 164, "every imported bore stays marked")
