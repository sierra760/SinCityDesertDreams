# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The native `.sc2d` save format.
##
## A save is one JSON document:
##
##   {
##     "format": "sc2d", "version": 2,
##     "stage": "play" | "editing",   # "editing": an unfounded map
##     "generator": {...},            # editing only: the settings that made the map
##     "header": {name, mayor, year, day, population, funds, saved_at, stage},
##     "city": {name, mayor, founded_year, day, funds, difficulty, rotation,
##              sea_level, status,
##              "layers": {layer_name: base64(deflate(bytes))},
##              "facilities": {"x,y": record}, "signs": {"x,y": text},
##              # terrain: "terrain_vertices": base64(deflate(bytes))
##              # or "terrain_model": "per_tile" (independent tiles)
##             },
##     "snapshot": {...}          # Simulation.snapshot(), stored as given
##   }
##
## The header repeats what the load dialog needs so `list_saves()` can show
## a directory without decoding a single layer.
class_name SaveFormat
extends RefCounted

const FORMAT := "sc2d"
const VERSION := 2
const EXTENSION := "sc2d"
## A save of a founded, running city.
const STAGE_PLAY := "play"
## A save of a map still being shaped; loading it returns to the editing stage.
const STAGE_EDITING := "editing"
## Preserve independent imported tile geometry without reconstructing a lattice.
const TERRAIN_PER_TILE := "per_tile"

## Layer name -> expected byte length. Altitude is two bytes per tile.
const LAYER_SIZES := {
	"terrain": City.WIDTH * City.HEIGHT,
	"altitude": City.WIDTH * City.HEIGHT * 2,
	"building": City.WIDTH * City.HEIGHT * 2,
	"zone": City.WIDTH * City.HEIGHT,
	"flags": City.WIDTH * City.HEIGHT,
	"underground": City.WIDTH * City.HEIGHT,
	"traffic": City.HALF * City.HALF,
	"pollution": City.HALF * City.HALF,
	"land_value": City.HALF * City.HALF,
	"crime": City.HALF * City.HALF,
	"police": City.QUARTER * City.QUARTER,
	"fire_cover": City.QUARTER * City.QUARTER,
	"density": City.QUARTER * City.QUARTER,
	"growth": City.QUARTER * City.QUARTER,
}
const VERTEX_BYTES := TerrainSurface.VERTS_X * TerrainSurface.VERTS_Y

## Browse requests always reread the file; parsing is skipped only when the text
## and modification time match the cached copy. Callers get a deep copy of the
## cached header, so editing it cannot corrupt the cache.
const HEADER_CACHE_LIMIT := 64
const HEADER_CACHE_BYTES := 8 * 1024 * 1024
static var _header_cache: Dictionary = {}
static var _header_cache_bytes := 0


static func default_dir() -> String:
	return "user://saves"


## Write the city and the simulation snapshot to `path`. `stage` marks an
## unfounded map (STAGE_EDITING) whose `generator` settings are kept so the
## map can be regenerated after loading.
static func save(path: String, city: City, sim_snapshot: Dictionary = {}, stage: String = STAGE_PLAY, generator: Dictionary = {}) -> Error:
	if city == null:
		return ERR_INVALID_PARAMETER
	# Reject invalid applied metadata before staging or replacing any save.
	if not StreetNamingCodec.validate(city.street_naming).ok:
		return ERR_INVALID_DATA
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		var made := DirAccess.make_dir_recursive_absolute(dir)
		if made != OK:
			return made
	var doc := {
		"format": FORMAT,
		"version": VERSION,
		"stage": stage,
		"header": _header(city, sim_snapshot, stage),
		"city": encode_city(city),
		"snapshot": sim_snapshot,
	}
	if not generator.is_empty():
		var stored_generator := generator.duplicate() if generator.get("source") == "real_world" else generator
		if stored_generator.get("source") == "real_world":
			stored_generator["terrain_origin"] = RealWorldManifest.sanitize_origin(generator.get("terrain_origin"))
		doc["generator"] = stored_generator
	# Hazard workers consume RNG in tile-record insertion order. Sorting JSON
	# keys silently changes their next day after loading the same saved state.
	return _write_replacement(path, JSON.stringify(doc, "", false).to_utf8_buffer())


## Reserve a private sibling directory so an interrupted/parallel save cannot
## collide with or truncate another writer's temporary file. Only the final
## rename touches the destination; never delete the previous save as a fallback.
static func _write_replacement(path: String, bytes: PackedByteArray) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute):
		return ERR_FILE_CANT_WRITE
	var parent := absolute.get_base_dir()
	if parent.is_empty():
		parent = "."
	var staging := ""
	var nonce := "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	for attempt in range(16):
		var candidate := parent.path_join(".sc2d-save-%s-%d" % [nonce, attempt])
		var made := DirAccess.make_dir_absolute(candidate)
		if made == OK:
			staging = candidate
			break
		if made != ERR_ALREADY_EXISTS:
			return made
	if staging.is_empty():
		return ERR_ALREADY_EXISTS
	var temporary := staging.path_join("document")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		var opened := FileAccess.get_open_error()
		_discard_staged_save(staging)
		return opened
	var stored := file.store_buffer(bytes)
	file.flush()
	var written := file.get_error()
	file.close()
	if not stored or written != OK:
		_discard_staged_save(staging)
		return written if written != OK else ERR_FILE_CANT_WRITE
	# Reopen after close: a buffered write/close failure must never publish a
	# partial document, even when the platform's last-error getter missed it.
	var verify := FileAccess.open(temporary, FileAccess.READ)
	if verify == null:
		var opened := FileAccess.get_open_error()
		_discard_staged_save(staging)
		return opened
	var matches := verify.get_length() == bytes.size() and verify.get_buffer(bytes.size()) == bytes
	verify.close()
	if not matches:
		_discard_staged_save(staging)
		return ERR_FILE_CANT_WRITE
	return _publish_staged_save(staging, absolute, OS.has_feature("windows"))


## Some platform backends remove the destination before moving the new file
## into place. On those backends keep a verified copy of the old save until the
## move succeeds. A failed restoration intentionally leaves previous.sc2d in staging.
static func _publish_staged_save(staging: String, absolute: String, preserve_backup: bool) -> Error:
	var previous := staging.path_join("previous.sc2d")
	var has_previous := preserve_backup and FileAccess.file_exists(absolute)
	if has_previous:
		var source := FileAccess.open(absolute, FileAccess.READ)
		if source == null:
			var opened := FileAccess.get_open_error()
			_discard_staged_save(staging)
			return opened
		var expected_size := source.get_length()
		var original := source.get_buffer(expected_size)
		var read_error := source.get_error()
		source.close()
		if original.size() != expected_size or read_error != OK:
			_discard_staged_save(staging)
			return ERR_FILE_CANT_READ
		var copied := DirAccess.copy_absolute(absolute, previous)
		var verified := false
		if copied == OK:
			var backup := FileAccess.open(previous, FileAccess.READ)
			if backup != null:
				verified = backup.get_length() == original.size() and backup.get_buffer(original.size()) == original
				backup.close()
		if not verified:
			if FileAccess.file_exists(previous):
				DirAccess.remove_absolute(previous)
			_discard_staged_save(staging)
			return copied if copied != OK else ERR_FILE_CANT_WRITE
	var replaced := DirAccess.rename_absolute(staging.path_join("document"), absolute)
	if replaced != OK and has_previous:
		# Restore only a missing destination, never overwrite a file another
		# process may have published. Preserve recovery bytes if this also fails.
		_restore_previous_save(staging, absolute)
		return replaced
	if has_previous:
		DirAccess.remove_absolute(previous)
	_discard_staged_save(staging)
	return replaced


static func _restore_previous_save(staging: String, absolute: String) -> Error:
	if FileAccess.file_exists(absolute) or DirAccess.dir_exists_absolute(absolute):
		return ERR_ALREADY_EXISTS
	var restored := DirAccess.rename_absolute(staging.path_join("previous.sc2d"), absolute)
	if restored == OK:
		_discard_staged_save(staging)
	return restored


static func _discard_staged_save(staging: String) -> void:
	var temporary := staging.path_join("document")
	if FileAccess.file_exists(temporary):
		DirAccess.remove_absolute(temporary)
	DirAccess.remove_absolute(staging)


## Player-facing reasons a city file cannot be opened.
const MESSAGE_MISSING := "The file couldn't be found."
const MESSAGE_UNREADABLE := "The file couldn't be read. Check that it is still available."
const MESSAGE_NOT_A_CITY := "This file isn't a Sin City - Desert Dreams city."
const MESSAGE_NEWER := "This city was saved by a newer version of the game."
const MESSAGE_DAMAGED := "This city file is damaged and can't be opened."


## Read a save. Returns {ok, city, snapshot, stage, generator, error, version};
## `error` is player-facing, and a technical `detail` may accompany it.
static func load(path: String) -> Dictionary:
	var result := {"ok": false, "city": null, "snapshot": {}, "stage": STAGE_PLAY, "generator": {}, "error": "", "version": 0, "topology": null}
	if not FileAccess.file_exists(path):
		result["error"] = MESSAGE_MISSING
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result["error"] = MESSAGE_UNREADABLE
		result["detail"] = "Cannot open file (error %d)." % FileAccess.get_open_error()
		return result
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		result["error"] = MESSAGE_NOT_A_CITY
		return result
	var doc: Dictionary = parsed
	if String(doc.get("format", "")) != FORMAT:
		result["error"] = MESSAGE_NOT_A_CITY
		return result
	var version := int(doc.get("version", 0))
	result["version"] = version
	if version > VERSION:
		result["error"] = MESSAGE_NEWER
		return result
	if version < 1:
		result["error"] = MESSAGE_NOT_A_CITY
		return result
	var stage: Variant = doc.get("stage", null)
	if typeof(stage) != TYPE_STRING or stage not in [STAGE_PLAY, STAGE_EDITING]:
		result["error"] = MESSAGE_DAMAGED
		result["detail"] = "Save has no valid stage."
		return result
	var city_doc: Variant = doc.get("city", null)
	if typeof(city_doc) != TYPE_DICTIONARY:
		result["error"] = MESSAGE_DAMAGED
		result["detail"] = "Save has no city."
		return result
	var decoded := decode_city(city_doc, version)
	if decoded["city"] == null:
		# Keep the technical reason for diagnostics, out of the player's view.
		result["error"] = MESSAGE_DAMAGED
		result["detail"] = String(decoded["error"])
		return result
	result["city"] = decoded["city"]
	if stage != STAGE_PLAY:
		# An unfounded map has never run; founding derives its maps afresh.
		(decoded["city"] as City).restored_layers.clear()
	# The street topology built while validating names belongs to this City;
	# callers may reuse it instead of rebuilding it from the same layers.
	result["topology"] = decoded.get("topology", null)
	var snap: Variant = doc.get("snapshot", {})
	result["snapshot"] = snap if typeof(snap) == TYPE_DICTIONARY else {}
	if stage == STAGE_PLAY:
		var problem := validate_snapshot(result["snapshot"])
		if problem != "":
			# Refuse it here, before the open city is replaced.
			result["city"] = null
			result["topology"] = null
			result["error"] = MESSAGE_DAMAGED
			result["detail"] = problem
			return result
	result["stage"] = stage
	var generator: Variant = doc.get("generator", {})
	result["generator"] = generator if typeof(generator) == TYPE_DICTIONARY else {}
	if result["generator"].get("source") == "real_world":
		result["generator"]["terrain_origin"] = RealWorldManifest.sanitize_origin(generator.get("terrain_origin"))
	result["ok"] = true
	return result


## Default save() shape of every simulation system, by system key, for
## validate_snapshot. Built once from fresh systems.
static var _system_shapes: Dictionary = {}


## Why a saved simulation snapshot cannot be restored, or "" when it can. Each
## field is checked against the kind of value the game stores there: numbers
## where numbers belong, lists and tables where those belong. Fields the game
## does not know are left alone; missing fields take their defaults.
static func validate_snapshot(snap: Dictionary) -> String:
	if snap.is_empty():
		return ""
	for k in ["clock_day", "speed", "accumulator"]:
		if snap.has(k) and not _is_number(snap[k]):
			return "Snapshot field '%s' is not a number." % k
	if snap.has("budget_review_pending") and not _is_number(snap["budget_review_pending"]):
		return "Snapshot field 'budget_review_pending' is not a flag."
	for k in ["rng_seed", "rng_state"]:
		if snap.has(k) and typeof(snap[k]) not in [TYPE_STRING, TYPE_INT, TYPE_FLOAT]:
			return "Snapshot field '%s' is damaged." % k
	if snap.has("stats"):
		if typeof(snap["stats"]) != TYPE_DICTIONARY:
			return "Snapshot stats are damaged."
		var defaults := CityStats.new()
		var stats: Dictionary = snap["stats"]
		for p in defaults.get_property_list():
			if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or not stats.has(p.name):
				continue
			if not CityStats.accepts(defaults.get(p.name), stats[p.name]):
				return "Snapshot stat '%s' is damaged." % p.name
	if snap.has("systems"):
		if typeof(snap["systems"]) != TYPE_DICTIONARY:
			return "Snapshot systems are damaged."
		var systems: Dictionary = snap["systems"]
		var shapes := _shapes()
		for key in systems:
			if not shapes.has(String(key)):
				continue
			if typeof(systems[key]) != TYPE_DICTIONARY:
				return "Snapshot system '%s' is damaged." % key
			var problem := _shape_problem(shapes[String(key)], systems[key], String(key))
			if problem != "":
				return problem
	return ""


static func _shapes() -> Dictionary:
	if _system_shapes.is_empty():
		for path in Simulation.SYSTEM_SCRIPTS:
			if not ResourceLoader.exists(path):
				continue
			var system: SimSystem = (ResourceLoader.load(path) as Script).new()
			_system_shapes[String(system.key)] = system.save()
	return _system_shapes


static func _is_number(v: Variant) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]


static func _is_list(v: Variant) -> bool:
	return typeof(v) == TYPE_ARRAY or (typeof(v) >= TYPE_PACKED_BYTE_ARRAY and typeof(v) <= TYPE_PACKED_VECTOR4_ARRAY)


## A saved value against the value a fresh system saves for the same field.
static func _shape_problem(expected: Dictionary, saved: Dictionary, where: String) -> String:
	for field in expected:
		if not saved.has(field):
			continue
		var want: Variant = expected[field]
		var got: Variant = saved[field]
		var name := "%s.%s" % [where, field]
		if _is_number(want):
			if not _is_number(got):
				return "Snapshot field '%s' is not a number." % name
		elif typeof(want) == TYPE_DICTIONARY:
			if typeof(got) != TYPE_DICTIONARY:
				return "Snapshot field '%s' is not a table." % name
		elif _is_list(want):
			if typeof(got) != TYPE_ARRAY:
				return "Snapshot field '%s' is not a list." % name
			# Lists of records (one table per entry) must hold tables.
			var records: bool = want.size() > 0
			for item in want:
				records = records and typeof(item) == TYPE_DICTIONARY
			if records:
				for item in got:
					if typeof(item) != TYPE_DICTIONARY:
						return "Snapshot field '%s' holds a damaged entry." % name
	return ""


## Saves in a directory, newest first: [{path, name, date_text, population,
## year, day, funds, stage}]. No city layer decoding is needed for the headers.
static func list_saves(dir: String = default_dir()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if not d.current_is_dir() and entry.get_extension().to_lower() == EXTENSION:
			var path := dir.path_join(entry)
			var header := read_header(path)
			if not header.is_empty():
				out.append(header)
		entry = d.get_next()
	d.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["saved_at"]) > int(b["saved_at"]))
	return out


## Header of one save, or an empty Dictionary when the file is not a save.
## Always read current text; an unchanged validated document can reuse parsing.
static func read_header(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_forget_header(path)
		return {}
	var text := file.get_as_text()
	file.close()
	var modified_time := FileAccess.get_modified_time(path)
	var cached: Dictionary = _header_cache.get(path,{})
	if not cached.is_empty() and cached.text == text and int(cached.modified_time) == modified_time:
		# Dictionary insertion order supplies a bounded least-recently-used queue.
		_header_cache.erase(path)
		_header_cache[path] = cached
		return (cached.header as Dictionary).duplicate(true)
	_forget_header(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var doc: Dictionary = parsed
	if String(doc.get("format", "")) != FORMAT:
		return {}
	var header: Variant = doc.get("header", {})
	if typeof(header) != TYPE_DICTIONARY:
		return {}
	var h: Dictionary = header
	var saved_at := int(h.get("saved_at", modified_time))
	var result := {
		"path": path,
		"mayor": ViewPreferences.mayor_credit(h.get("mayor", "")),
		"name": String(h.get("name", path.get_file().get_basename())),
		"date_text": Time.get_datetime_string_from_unix_time(saved_at, true) + " UTC",
		"population": int(h.get("population", 0)),
		"year": int(h.get("year", 0)),
		"day": int(h.get("day", 0)),
		"funds": int(h.get("funds", 0)),
		"stage": STAGE_EDITING if String(h.get("stage", STAGE_PLAY)) == STAGE_EDITING else STAGE_PLAY,
		"saved_at": saved_at,
	}

	_remember_header(path,text,modified_time,result)
	return result


static func _forget_header(path: String) -> void:
	if not _header_cache.has(path): return
	_header_cache_bytes -= int(_header_cache[path].bytes)
	_header_cache.erase(path)


static func _remember_header(path: String, text: String, modified_time: int, header: Dictionary) -> void:
	# Godot strings hold 32-bit characters. Include header/path string storage
	# and conservative entry overhead, so large documents cannot fill the cache.
	var bytes := 1024 + (text.length()+path.length())*4
	for value: Variant in header.values():
		if value is String: bytes += value.length()*4
	if bytes > HEADER_CACHE_BYTES: return
	while _header_cache.size() >= HEADER_CACHE_LIMIT or _header_cache_bytes+bytes > HEADER_CACHE_BYTES:
		_forget_header(String(_header_cache.keys()[0]))
	_header_cache[path] = {"text":text,"modified_time":modified_time,"header":header.duplicate(true),"bytes":bytes}
	_header_cache_bytes += bytes


# ── City encoding ────────────────────────────────────────────────────────

static func _header(city: City, snap: Dictionary, stage: String = STAGE_PLAY) -> Dictionary:
	var population := 0
	var stats: Variant = snap.get("stats", {})
	if typeof(stats) == TYPE_DICTIONARY:
		for k in ["population", "arcology_population"]:
			var v: Variant = stats.get(k, 0)
			if _is_number(v):
				population += int(v)
	return {
		"name": city.name,
		"mayor": city.mayor,
		"year": city.current_year(),
		"day": city.day,
		"population": population,
		"funds": city.funds,
		"stage": stage,
		"saved_at": int(Time.get_unix_time_from_system()),
	}


## The JSON-safe city document.
static func encode_city(city: City) -> Dictionary:
	var layers := {
		"terrain": encode_bytes(city.terrain.data),
		"altitude": encode_bytes(city.altitude.to_bytes()),
		"building": encode_bytes(city.building.to_bytes()),
		"zone": encode_bytes(city.zone.data),
		"flags": encode_bytes(city.flags.data),
		"underground": encode_bytes(city.underground.data),
		"traffic": encode_bytes(city.traffic.data),
		"pollution": encode_bytes(city.pollution.data),
		"land_value": encode_bytes(city.land_value.data),
		"crime": encode_bytes(city.crime.data),
		"police": encode_bytes(city.police.data),
		"fire_cover": encode_bytes(city.fire_cover.data),
		"density": encode_bytes(city.density.data),
		"growth": encode_bytes(city.growth.data),
	}
	var facilities := {}
	for anchor in city.facilities:
		var record: Dictionary = city.facilities[anchor]
		facilities[SimSystem.tile_key(anchor)] = _json_safe(record)
	var signs := {}
	for tile in city.signs:
		signs[SimSystem.tile_key(tile)] = String(city.signs[tile])
	var doc := {
		"name": city.name,
		"mayor": city.mayor,
		"founded_year": city.founded_year,
		"day": city.day,
		"funds": city.funds,
		"difficulty": city.difficulty,
		"rotation": city.rotation,
		"sea_level": city.sea_level,
		"status": city.status,
		"layers": layers,
		"facilities": facilities,
		"signs": signs,
		"street_naming": _encode_street_naming(city.street_naming),
	}
	var origin := RealWorldManifest.sanitize_origin(city.terrain_origin)
	if not origin.is_empty(): doc["terrain_origin"] = origin
	# Optional; saves without imported cities have no such links.
	var power_links := {}
	for index: int in city.imported_power_links.keys():
		var signature: Vector2i = city.imported_power_links[index]
		if signature == Vector2i(city.building.data[index], city.zone.data[index] & Zones.KIND_MASK):
			power_links[str(index)] = [signature.x, signature.y]
	if not power_links.is_empty(): doc["imported_power_links"] = power_links
	if city.terrain_surface != null:
		doc["terrain_vertices"] = encode_bytes(city.terrain_surface.vertices)
	else:
		doc["terrain_model"] = TERRAIN_PER_TILE
	return doc


## Rebuild a City from its document. Returns {city, error, topology}; `city`
## is null when the document is incomplete or damaged.
static func decode_city(doc: Dictionary, version: int = VERSION) -> Dictionary:
	if not doc.has("street_naming"):
		return {"city": null, "error": "Save has no street naming metadata."}
	var decoded_naming := _decode_street_naming(doc.street_naming)
	if not decoded_naming.ok:
		return {"city": null, "error": decoded_naming.error}
	if doc.has("terrain_model"):
		var model: Variant = doc["terrain_model"]
		if typeof(model) != TYPE_STRING or model != TERRAIN_PER_TILE:
			return {"city": null, "error": "Save has an unsupported terrain model."}
		if doc.has("terrain_vertices"):
			return {"city": null, "error": "Save has conflicting terrain ownership."}
	elif not doc.has("terrain_vertices"):
		return {"city": null, "error": "Save has no terrain."}
	var city := City.new()
	city.terrain_origin = RealWorldManifest.sanitize_origin(doc.get("terrain_origin"))
	city.name = String(doc.get("name", city.name))
	city.mayor = String(doc.get("mayor", city.mayor))
	city.founded_year = int(doc.get("founded_year", city.founded_year))
	city.day = int(doc.get("day", 0))
	city.funds = int(doc.get("funds", 0))
	city.difficulty = clampi(int(doc.get("difficulty", City.Difficulty.EASY)), City.Difficulty.EASY, City.Difficulty.HARD)
	city.rotation = int(doc.get("rotation", 0)) & 3
	city.sea_level = int(doc.get("sea_level", -1))
	city.status = int(doc.get("status", 0))
	var layers: Variant = doc.get("layers", {})
	if typeof(layers) != TYPE_DICTIONARY:
		return {"city": null, "error": "Save has no layers."}
	var grids := {
		"terrain": city.terrain, "building": city.building, "zone": city.zone,
		"flags": city.flags, "underground": city.underground,
		"traffic": city.traffic, "pollution": city.pollution,
		"land_value": city.land_value, "crime": city.crime,
		"police": city.police, "fire_cover": city.fire_cover,
		"density": city.density, "growth": city.growth,
	}
	for layer_name in LAYER_SIZES:
		if not layers.has(layer_name):
			continue
		var expected_size := int(LAYER_SIZES[layer_name])
		if layer_name == "building" and version == 1:
			expected_size /= 2
		var bytes := decode_bytes(String(layers[layer_name]), expected_size)
		if bytes.size() != expected_size:
			return {"city": null, "error": "Layer '%s' is damaged." % layer_name}
		if layer_name == "building":
			if version == 1:
				city.building.data = PackedInt32Array(Array(bytes))
			else:
				city.building.from_bytes(bytes)
			for code in city.building.data:
				if code >= Buildings.COUNT:
					return {"city": null, "error": "Building layer contains an unknown building."}
		elif layer_name == "altitude":
			city.altitude.from_bytes(bytes)
		else:
			var grid: Grid8 = grids[layer_name]
			grid.data = bytes
		city.restored_layers[layer_name] = true
	var power_links: Variant = doc.get("imported_power_links", {})
	if typeof(power_links) != TYPE_DICTIONARY:
		return {"city": null, "error": "Save has invalid imported power links."}
	for key: Variant in power_links:
		var value: Variant = power_links[key]
		if not String(key).is_valid_int() or typeof(value) != TYPE_ARRAY or value.size() != 2:
			return {"city": null, "error": "Save has invalid imported power links."}
		var index := int(key)
		if index < 0 or index >= City.WIDTH * City.HEIGHT:
			return {"city": null, "error": "Save has invalid imported power link position."}
		for component_index in 2:
			var component: Variant = value[component_index]
			var maximum := Buildings.COUNT - 1 if component_index == 0 else 255
			if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)) or float(component) != floorf(float(component)) or component < 0 or component > maximum:
				return {"city": null, "error": "Save has invalid imported power link signature."}
		var signature := Vector2i(int(value[0]), int(value[1]))
		if signature == Vector2i(city.building.data[index], city.zone.data[index] & Zones.KIND_MASK):
			city.imported_power_links[index] = signature
	var facilities: Variant = doc.get("facilities", {})
	if typeof(facilities) == TYPE_DICTIONARY:
		for k in facilities:
			var anchor := SimSystem.parse_tile_key(String(k))
			if anchor.x < 0 or typeof(facilities[k]) != TYPE_DICTIONARY:
				continue
			var record: Dictionary = facilities[k]
			var restored := {}
			for field in record:
				var value: Variant = record[field]
				if String(field) == "key":
					restored["key"] = StringName(String(value))
				elif typeof(value) == TYPE_FLOAT and is_equal_approx(value, floorf(value)):
					restored[String(field)] = int(value)
				else:
					restored[String(field)] = value
			city.facilities[anchor] = restored
	var signs: Variant = doc.get("signs", {})
	if typeof(signs) == TYPE_DICTIONARY:
		for k in signs:
			var tile := SimSystem.parse_tile_key(String(k))
			if tile.x >= 0:
				city.signs[tile] = String(signs[k])
	if doc.has("terrain_vertices"):
		var verts := decode_bytes(String(doc["terrain_vertices"]), VERTEX_BYTES)
		if verts.size() != VERTEX_BYTES:
			return {"city": null, "error": "Save has damaged terrain vertices."}
		city.terrain_surface = TerrainSurface.from_city(city, verts)
	city.street_naming = decoded_naming.metadata
	# Drop memberships and station names that no longer match the loaded
	# streets. The host installs the station allocator before it binds or
	# draws the city.
	var topology := StreetTopology.new()
	topology.rebuild(city)
	var reconciled := StreetNamingService.new().bind_city(city, topology)
	if not reconciled.ok:
		return {"city": null, "error": "Invalid street naming metadata: " + reconciled.error}
	return {"city": city, "error": "", "topology": topology}


## Street IDs and automatic suffixes are written as decimal strings, because
## JSON numbers cannot hold the full int64 range. Street keys are decimal IDs,
## station keys are "x,y"; the schema field stays the number 1.
static func _encode_street_naming(metadata: Dictionary) -> Dictionary:
	var validated := StreetNamingCodec.validate(metadata)
	if not validated.ok:
		# encode_city has no error channel. Preserve invalid supplied data for
		# decode rejection; save() prevents it from reaching a committed file.
		return metadata.duplicate(true)
	var wire := {"schema": 1, "next_street_id": str(metadata.next_street_id), "streets": {}, "links": {}, "station_auto": {}}
	for id: int in metadata.streets:
		wire.streets[str(id)] = metadata.streets[id]
	for key: String in metadata.links:
		wire.links[key] = str(metadata.links[key])
	for anchor: Vector2i in metadata.station_auto:
		var record: Dictionary = metadata.station_auto[anchor]
		var sources: Array[String] = []
		for id: int in record.source_street_ids: sources.append(str(id))
		wire.station_auto[SimSystem.tile_key(anchor)] = {"source_street_ids": sources, "base_name": record.base_name, "suffix": str(record.suffix), "display_name": record.display_name}
	return wire


static func _naming_failure(message: String) -> Dictionary:
	return {"ok": false, "error": "Invalid street naming metadata: " + message, "metadata": {}}


## Never coerce a number, boolean, padded decimal, overflow or alternate spelling.
static func _naming_decimal(value: Variant, allow_zero: bool = false) -> Dictionary:
	if typeof(value) != TYPE_STRING or not value.is_valid_int():
		return {"ok": false, "value": 0}
	var number := int(value)
	return {"ok": str(number) == value and (number >= 0 if allow_zero else number > 0), "value": number}


static func _decode_street_naming(block: Variant) -> Dictionary:
	if typeof(block) != TYPE_DICTIONARY or block.size() != StreetNamingCodec.FIELDS.size():
		return _naming_failure("The block must contain exactly the schema fields.")
	for field: String in StreetNamingCodec.FIELDS:
		if not block.has(field): return _naming_failure("Missing schema field '%s'." % field)
	# JSON reads the number 1 back as a float, so accept either numeric type.
	if typeof(block.schema) not in [TYPE_INT, TYPE_FLOAT] or block.schema != 1:
		return _naming_failure("Unsupported street naming schema.")
	var next := _naming_decimal(block.next_street_id)
	if not next.ok: return _naming_failure("Invalid next street ID.")
	var metadata := StreetNamingCodec.empty_metadata()
	metadata.next_street_id = next.value
	for field: String in ["streets", "links", "station_auto"]:
		if typeof(block[field]) != TYPE_DICTIONARY: return _naming_failure("Invalid %s registry." % field)
	for key: Variant in block.streets:
		var id := _naming_decimal(key)
		if not id.ok: return _naming_failure("Invalid street ID.")
		metadata.streets[id.value] = block.streets[key]
	for key: Variant in block.links:
		var id := _naming_decimal(block.links[key])
		if not id.ok: return _naming_failure("Invalid street connection ID.")
		metadata.links[key] = id.value
	for key: Variant in block.station_auto:
		if typeof(key) != TYPE_STRING: return _naming_failure("Invalid station anchor.")
		var parts: PackedStringArray = key.split(",", true)
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return _naming_failure("Invalid station anchor.")
		var anchor := Vector2i(int(parts[0]), int(parts[1]))
		if not StreetNamingCodec.valid_anchor(anchor) or SimSystem.tile_key(anchor) != key:
			return _naming_failure("Invalid station anchor.")
		var record: Variant = block.station_auto[key]
		if typeof(record) != TYPE_DICTIONARY or record.size() != StreetNamingCodec.AUTO_FIELDS.size():
			return _naming_failure("Invalid automatic station record.")
		for field: String in StreetNamingCodec.AUTO_FIELDS:
			if not record.has(field): return _naming_failure("Invalid automatic station record.")
		if typeof(record.source_street_ids) != TYPE_ARRAY: return _naming_failure("Invalid automatic station sources.")
		var sources: Array = []
		for value: Variant in record.source_street_ids:
			var id := _naming_decimal(value)
			if not id.ok: return _naming_failure("Invalid automatic station source ID.")
			sources.append(id.value)
		var suffix := _naming_decimal(record.suffix, true)
		if not suffix.ok: return _naming_failure("Invalid automatic station suffix.")
		metadata.station_auto[anchor] = {"source_street_ids": sources, "base_name": record.base_name, "suffix": suffix.value, "display_name": record.display_name}
	var validated := StreetNamingCodec.validate(metadata)
	if not validated.ok: return _naming_failure(validated.error)
	return validated


# ── Byte helpers ─────────────────────────────────────────────────────────

static func encode_bytes(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes.compress(FileAccess.COMPRESSION_DEFLATE))


static func decode_bytes(text: String, expected_size: int) -> PackedByteArray:
	var packed := Marshalls.base64_to_raw(text)
	if packed.is_empty():
		return PackedByteArray()
	return packed.decompress(expected_size, FileAccess.COMPRESSION_DEFLATE)


## Turn a record into plain JSON types: StringNames become Strings and
## Vector2i values become [x, y] arrays.
static func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var out := {}
			for k in value:
				out[String(k)] = _json_safe(value[k])
			return out
		TYPE_ARRAY:
			var arr := []
			for item in value:
				arr.append(_json_safe(item))
			return arr
		TYPE_STRING_NAME:
			return String(value)
		TYPE_VECTOR2I:
			return [value.x, value.y]
		_:
			return value
