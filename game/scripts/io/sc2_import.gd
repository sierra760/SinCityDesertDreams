# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Reads classic `.sc2` city files into a `City`.
##
## The file is an IFF container (`FORM` / `SCDH`) of tagged chunks, most of
## them run-length packed. Only the chunks that describe the map and the
## handful of metadata fields the game needs are read: terrain, altitude,
## buildings, zones, service flags, underground codes, the four half- and
## four quarter-resolution maps, player signs, the city name and the founding
## year, day count, funds, difficulty and tax rates. Everything else (facility
## labels, graphs, moving things, counters) is ignored.
##
## `load()` returns {ok, city, error, tax_rates, warnings}. `tax_rates` is
## {residential, commercial, industrial} for the caller to apply to
## `CityStats`, since the city model has no tax fields.
class_name Sc2Import
extends RefCounted

const CONTAINER_MAGIC := "FORM"
const CONTAINER_KIND := "SCDH"
const HEADER_BYTES := 12

const TILES := City.WIDTH * City.HEIGHT
const HALF_TILES := City.HALF * City.HALF
const QUARTER_TILES := City.QUARTER * City.QUARTER

## Chunk tag -> unpacked size. A chunk whose stored size differs is packed.
const CHUNK_SIZES := {
	"CNAM": 32,
	"MISC": 4800,
	"ALTM": TILES * 2,
	"XTER": TILES,
	"XBLD": TILES,
	"XZON": TILES,
	"XUND": TILES,
	"XTXT": TILES,
	"XLAB": 6400,
	"XMIC": 1200,
	"XTHG": 480,
	"XBIT": TILES,
	"XTRF": HALF_TILES,
	"XPLT": HALF_TILES,
	"XVAL": HALF_TILES,
	"XCRM": HALF_TILES,
	"XPLC": QUARTER_TILES,
	"XFIR": QUARTER_TILES,
	"XPOP": QUARTER_TILES,
	"XROG": QUARTER_TILES,
	"XGRP": 3328,
}

## Indices into the metadata chunk's array of 32-bit integers.
const META_ROTATION := 2
const META_FOUNDED_YEAR := 3
const META_DAYS := 4
const META_FUNDS := 5
const META_DIFFICULTY := 7
const META_STATUS := 8
const META_TAX_RESIDENTIAL := 480
const META_TAX_COMMERCIAL := 507
const META_TAX_INDUSTRIAL := 534

## Text slots: `XTXT` holds one slot number per tile, `XLAB` 256 slots of a
## length byte and 24 characters. Slots 1..50 are player signs.
const LABEL_BYTES := 25
const SIGN_SLOT_FIRST := 1
const SIGN_SLOT_LAST := 50

## Altitude word layout in the file: ground in the low five bits, water
## height in the next five, tunnel bits above.
const FILE_GROUND_MASK := 0x1F
const FILE_WATER_SHIFT := 5
const FILE_TUNNEL_SHIFT := 10

## Service bits in the file's flag byte.
const FILE_SALT := 0x01
const FILE_AXIS := 0x02
const FILE_WATER_COVERED := 0x04
const FILE_WATERED := 0x10
const FILE_CONDUCTS_WATER := 0x20
## Power bits: 0x80 marks a conducting tile, 0x40 a powered one.
const FILE_CONDUCTS_POWER := 0x80
const FILE_POWERED := 0x40

## Underground bands in the file: subways first, then pipes, crossings and
## the station link. This game numbers pipes first (see UtilityParams).
const FILE_SUBWAY_FIRST := 1
const FILE_SUBWAY_LAST := 15
const FILE_PIPE_FIRST := 16
const FILE_PIPE_LAST := 30
const FILE_CROSSING_FIRST := 31
const FILE_STATION_LINK := 35


## Read a `.sc2` file from disk.
static func load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("The file couldn't be found.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("The file couldn't be read. Check that it is still available.")
	var raw := file.get_buffer(file.get_length())
	file.close()
	return load_bytes(raw, path.get_file().get_basename())


## Import from bytes already in memory. `fallback_name` is used when the
## file carries no city name.
static func load_bytes(raw: PackedByteArray, fallback_name: String = "Imported City") -> Dictionary:
	var container := parse_container(raw)
	if not container["ok"]:
		return _fail("This file isn't a classic city (.sc2) file.")
	var chunks: Dictionary = container["chunks"]
	return import_chunks(chunks, fallback_name)


# ── Container ────────────────────────────────────────────────────────────

## Split the container into {tag: unpacked bytes}. Chunks are packed back to
## back with no alignment padding. Returns {ok, chunks, error}.
static func parse_container(raw: PackedByteArray) -> Dictionary:
	if raw.size() < HEADER_BYTES:
		return {"ok": false, "chunks": {}, "error": "File too short."}
	if raw.slice(0, 4).get_string_from_ascii() != CONTAINER_MAGIC:
		return {"ok": false, "chunks": {}, "error": "Not a city file (bad container)."}
	if raw.slice(8, 12).get_string_from_ascii() != CONTAINER_KIND:
		return {"ok": false, "chunks": {}, "error": "Not a city file (unexpected content type)."}
	var chunks := {}
	var offset := HEADER_BYTES
	while offset + 8 <= raw.size():
		var tag := raw.slice(offset, offset + 4).get_string_from_ascii()
		var size := read_u32(raw, offset + 4)
		var start := offset + 8
		if start + size > raw.size():
			return {"ok": false, "chunks": chunks, "error": "Chunk %s runs past the end of the file." % tag}
		var data := raw.slice(start, start + size)
		if CHUNK_SIZES.has(tag) and size != int(CHUNK_SIZES[tag]):
			data = rle_decode(data)
		chunks[tag] = data
		offset = start + size
	return {"ok": true, "chunks": chunks, "error": ""}


## Unpack run-length data: a control byte of 0..127 copies that many literal
## bytes; 128..255 repeats the following byte (control - 127) times.
static func rle_decode(data: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var pos := 0
	var n := data.size()
	while pos < n:
		var control := data[pos]
		pos += 1
		if control <= 127:
			var end := mini(pos + control, n)
			out.append_array(data.slice(pos, end))
			pos = end
		else:
			if pos >= n:
				break
			var value := data[pos]
			pos += 1
			var run := PackedByteArray()
			run.resize(control - 127)
			run.fill(value)
			out.append_array(run)
	return out


## Pack bytes with the same scheme (used by tests and fixtures).
static func rle_encode(data: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var pos := 0
	var n := data.size()
	while pos < n:
		var value := data[pos]
		var run := 1
		while pos + run < n and data[pos + run] == value and run < 128:
			run += 1
		if run >= 3:
			out.append(run + 127)
			out.append(value)
			pos += run
			continue
		var literal_start := pos
		while pos < n and pos - literal_start < 127:
			var ahead := 1
			while pos + ahead < n and data[pos + ahead] == data[pos] and ahead < 3:
				ahead += 1
			if ahead >= 3:
				break
			pos += 1
		out.append(pos - literal_start)
		out.append_array(data.slice(literal_start, pos))
	return out


static func read_u32(data: PackedByteArray, at: int) -> int:
	return (data[at] << 24) | (data[at + 1] << 16) | (data[at + 2] << 8) | data[at + 3]


static func read_i32(data: PackedByteArray, at: int) -> int:
	var v := read_u32(data, at)
	return v - 0x100000000 if v >= 0x80000000 else v


static func read_u16(data: PackedByteArray, at: int) -> int:
	return (data[at] << 8) | data[at + 1]


# ── Mapping ──────────────────────────────────────────────────────────────

## Build a City from unpacked chunks.
static func import_chunks(chunks: Dictionary, fallback_name: String) -> Dictionary:
	var warnings: Array[String] = []
	for required in ["ALTM", "XTER", "XBLD"]:
		if not chunks.has(required) or (chunks[required] as PackedByteArray).size() != int(CHUNK_SIZES[required]):
			return _fail("This classic city file is incomplete and can't be imported.")
	var city := City.new()

	# Name and metadata.
	city.name = fallback_name
	if chunks.has("CNAM"):
		var name := city_name(_read_name(chunks["CNAM"]), fallback_name)
		if name != "":
			city.name = name
	var tax := {"residential": 7, "commercial": 7, "industrial": 7}
	if chunks.has("MISC"):
		var meta: PackedByteArray = chunks["MISC"]
		city.rotation = _meta(meta, META_ROTATION, 0) & 3
		city.founded_year = _meta(meta, META_FOUNDED_YEAR, 1900)
		city.day = maxi(_meta(meta, META_DAYS, 0), 0)
		city.funds = _meta(meta, META_FUNDS, 0)
		# Six classes, 0..5. The population system re-derives the class from
		# the imported city's residents when it first counts them.
		city.status = clampi(_meta(meta, META_STATUS, 0), 0, PopulationParams.STATUS_NAMES.size() - 1)
		city.difficulty = clampi(_meta(meta, META_DIFFICULTY, 1) - 1, City.Difficulty.EASY, City.Difficulty.HARD)
		tax["residential"] = clampi(_meta(meta, META_TAX_RESIDENTIAL, 7), 0, 20)
		tax["commercial"] = clampi(_meta(meta, META_TAX_COMMERCIAL, 7), 0, 20)
		tax["industrial"] = clampi(_meta(meta, META_TAX_INDUSTRIAL, 7), 0, 20)
	else:
		warnings.append("No metadata chunk; using new-city defaults.")

	# Full-resolution layers. The file stores every grid column by column
	# (x outer, y inner); the city keeps rows, so each layer is transposed.
	var altm: PackedByteArray = chunks["ALTM"]
	for x in City.WIDTH:
		for y in City.HEIGHT:
			var word := read_u16(altm, (x * City.HEIGHT + y) * 2)
			var ground := word & FILE_GROUND_MASK
			var water := (word >> FILE_WATER_SHIFT) & FILE_GROUND_MASK
			var tunnel := word >> FILE_TUNNEL_SHIFT
			city.altitude.data[y * City.WIDTH + x] = ground | (water << City.WATER_SHIFT) | (tunnel << City.TUNNEL_SHIFT)
	city.terrain.data = _transposed(chunks["XTER"], City.WIDTH)
	city.building.data = PackedInt32Array(Array(_transposed(chunks["XBLD"], City.WIDTH)))
	if chunks.has("XZON"):
		city.zone.data = _transposed(chunks["XZON"], City.WIDTH)
	if chunks.has("XBIT"):
		var bits := _transposed(chunks["XBIT"], City.WIDTH)
		for i in TILES:
			city.flags.data[i] = _map_flags(bits[i])
			if bits[i] & FILE_CONDUCTS_POWER and not Buildings.carries_power(city.building.data[i]):
				city.imported_power_links[i] = Vector2i(city.building.data[i], city.zone.data[i] & Zones.KIND_MASK)
	if chunks.has("XUND"):
		var codes := _transposed(chunks["XUND"], City.WIDTH)
		for i in TILES:
			city.underground.data[i] = map_underground(codes[i])

	if chunks.has("XTXT") and chunks.has("XLAB"):
		_import_signs(city, _transposed(chunks["XTXT"], City.WIDTH), chunks["XLAB"])

	# Half- and quarter-resolution maps.
	var half := {"XTRF": city.traffic, "XPLT": city.pollution, "XVAL": city.land_value, "XCRM": city.crime}
	for tag in half:
		if chunks.has(tag):
			(half[tag] as Grid8).data = _transposed(chunks[tag], City.HALF)
	var quarter := {"XPLC": city.police, "XFIR": city.fire_cover, "XPOP": city.density, "XROG": city.growth}
	for tag in quarter:
		if chunks.has(tag):
			(quarter[tag] as Grid8).data = _transposed(chunks[tag], City.QUARTER)

	# Imported terrain is kept exactly as stored: per-tile heights and water,
	# cliffs included. There is no global sea, and the editing lattice is built
	# only when the player first edits terrain.
	city.sea_level = -1
	city.terrain_surface = null

	_scan_facilities(city)
	return {"ok": true, "city": city, "error": "", "tax_rates": tax, "warnings": warnings}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "city": null, "error": message, "tax_rates": {}, "warnings": []}


## Name chunk: a length byte then the text, ended by the first zero byte.
static func _read_name(data: PackedByteArray) -> String:
	if data.size() < 2:
		return ""
	var end := 1
	while end < data.size() and data[end] != 0:
		end += 1
	return data.slice(1, end).get_string_from_ascii().strip_edges()


## The player-facing name for a stored city name. Some classic cities store
## their DOS file name ("OROCANYON.SC2"): the extension goes, and the shouted
## remainder becomes the file's own name when that reads better, otherwise it
## is title-cased ("Orocanyon").
static func city_name(stored: String, fallback_name: String = "") -> String:
	var name := stored.strip_edges()
	if not name.to_lower().ends_with(".sc2"):
		return name
	name = name.substr(0, name.length() - 4).strip_edges()
	if name == "":
		return ""
	if name == name.to_upper() and name != name.to_lower() and not name.contains(" "):
		var fallback := fallback_name.strip_edges()
		if fallback.to_lower().ends_with(".sc2"):
			fallback = fallback.substr(0, fallback.length() - 4).strip_edges()
		if fallback != "" and fallback != fallback.to_upper() \
				and fallback.to_lower().replace(" ", "") == name.to_lower().replace("_", ""):
			return fallback
		return name.capitalize()
	return name


## Player signs: each tile marked with a sign slot gets that slot's text.
## Empty slots draw nothing; facility and moving-thing slots are not signs.
static func _import_signs(city: City, slots: PackedByteArray, labels: PackedByteArray) -> void:
	for i in TILES:
		var slot := slots[i]
		if slot < SIGN_SLOT_FIRST or slot > SIGN_SLOT_LAST:
			continue
		var at := slot * LABEL_BYTES
		if at + LABEL_BYTES > labels.size():
			continue
		var length := mini(labels[at], LABEL_BYTES - 1)
		var text := labels.slice(at + 1, at + 1 + length).get_string_from_ascii().strip_edges()
		if not text.is_empty():
			city.signs[Vector2i(i % City.WIDTH, i / City.WIDTH)] = text


static func _meta(meta: PackedByteArray, index: int, fallback: int) -> int:
	if (index + 1) * 4 > meta.size():
		return fallback
	return read_i32(meta, index * 4)


## Column-major file bytes to a row-major square grid of the given side.
static func _transposed(data: PackedByteArray, side: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(side * side)
	for x in side:
		for y in side:
			var src := x * side + y
			if src < data.size():
				out[y * side + x] = data[src]
	return out


## File service bits -> TileFlags.
static func _map_flags(bits: int) -> int:
	var out := 0
	if bits & FILE_POWERED: out |= TileFlags.POWERED
	if bits & FILE_CONDUCTS_POWER: out |= TileFlags.CONDUCTS_POWER
	if bits & FILE_CONDUCTS_WATER: out |= TileFlags.CONDUCTS_WATER
	if bits & FILE_WATERED: out |= TileFlags.WATERED
	if bits & FILE_SALT: out |= TileFlags.SALT_WATER
	if bits & FILE_AXIS: out |= TileFlags.RESERVED_A
	return out


## Connection masks of the file's underground shapes, which come in a different
## order from this game's underground art: NS, EW, W/N/E/S grades,
## NE/SE/SW/NW corners, NEW/NES/ESW/NSW tees, cross.
const FILE_UNDERGROUND_MASKS := [5,10,10,5,10,5,3,6,12,9,11,7,14,13,15]

static func map_underground(code: int) -> int:
	if code >= FILE_SUBWAY_FIRST and code <= FILE_SUBWAY_LAST:
		return Underground.subway_code(FILE_UNDERGROUND_MASKS[code-FILE_SUBWAY_FIRST])
	if code >= FILE_PIPE_FIRST and code <= FILE_PIPE_LAST:
		return Underground.pipe_code(FILE_UNDERGROUND_MASKS[code-FILE_PIPE_FIRST])
	# Code 31 is a north-south subway over an east-west pipe; 32 swaps the axes.
	if code == 31: return Underground.PIPE_EW_UNDER_SUBWAY_NS
	if code == 32: return Underground.PIPE_NS_UNDER_SUBWAY_EW
	# Codes 34 and 35 are subway transitions. Code 33 only marks water for
	# display, not a pipe/subway crossing; its service flags import separately.
	if code in [34,FILE_STATION_LINK]: return Underground.STATION_LINK
	return UtilityParams.UNDERGROUND_NONE


## Record a facility for every civic building anchor on the map. Records are
## keyed by `City.anchor_of`, the lot's top-left tile: a city saved at another
## rotation carries CORNER_NW on a different corner of each lot.
static func _scan_facilities(city: City) -> void:
	for y in City.HEIGHT:
		for x in City.WIDTH:
			var id := city.building.at(x, y)
			if id == Buildings.NONE or not Buildings.is_developed(id) or Buildings.is_zone_building(id):
				continue
			var anchor := city.anchor_of(x, y)
			if city.facilities.has(anchor):
				continue
			city.add_facility(anchor, {"key": Buildings.key(id), "built_day": city.day, "imported": true})
