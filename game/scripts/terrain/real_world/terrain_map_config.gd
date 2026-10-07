# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name TerrainMapConfig
extends Node
## Which street-map and place-search providers the terrain chooser uses. A small
## JSON file published at `sincity/map/config_url` can switch providers (or turn
## either off) without an app update. The built-in default, then the last valid
## published file kept on disk, apply at once; a refresh runs in the background
## at most hourly and is used only if every field validates.
signal changed(config: Dictionary)

const SCHEMA := 1
const SETTING := "sincity/map/config_url"
const DEFAULT_URL := "https://sincity-maps.sierraburkhart.com/map-config.json"
const MAX_BODY := 16384
const REFRESH_MS := 3600000
const CACHE_NAME := "map_config_v1.json"
const NOMINATIM_HOST := "nominatim.openstreetmap.org"
const NOMINATIM_MIN_INTERVAL_MS := 1100
const DEFAULT := {
	"schema":SCHEMA,
	"tiles":{
		"enabled":true,
		"url":"https://tile.openstreetmap.org/{z}/{x}/{y}.png",
		"hidpi_url":"",
		"max_zoom":19,
		"max_active":4,
		"attribution":"© OpenStreetMap contributors",
	},
	"search":{
		"enabled":true,
		"url":"https://nominatim.openstreetmap.org/search?format=jsonv2&limit={limit}&q={query}",
		"format":"nominatim",
		"min_interval_ms":NOMINATIM_MIN_INTERVAL_MS,
		"attribution":"Search © OpenStreetMap contributors · Nominatim",
	},
}

static var default_request_factory: Callable
var request_factory: Callable
var config: Dictionary = DEFAULT.duplicate(true)
var source := "built-in"
## Why the last published file was refused, for diagnostics; empty when accepted.
var last_error := ""
var _clock: Callable = Time.get_ticks_msec
var _backend: Node
var _last_attempt := -REFRESH_MS
var _cache_path := ""

func _init() -> void:
	name="TerrainMapConfig"
	configure_cache()

func set_clock(clock: Callable) -> void:
	if clock.is_valid(): _clock=clock

static func config_url() -> String:
	return str(ProjectSettings.get_setting(SETTING,DEFAULT_URL)).strip_edges()

static func default_cache_path() -> String:
	var root := TerrainBasemap.default_disk_root()
	return "" if root.is_empty() else root.get_base_dir().path_join(CACHE_NAME)

## Load the last valid published file; an empty path disables the disk copy.
func configure_cache(path: String = "<default>") -> void:
	_cache_path=default_cache_path() if path=="<default>" else path
	config=DEFAULT.duplicate(true)
	source="built-in"
	if _cache_path.is_empty() or not FileAccess.file_exists(_cache_path): return
	var parsed := validate(parse_json(FileAccess.get_file_as_string(_cache_path)))
	if parsed.ok:
		config=parsed.config
		source="saved"

func is_refreshing() -> bool: return is_instance_valid(_backend)

## Fetch the published file unless one was fetched within the hour.
func refresh(force: bool = false) -> void:
	var url := config_url()
	if is_refreshing() or not _https_url(url): return
	if not force and int(_clock.call())-_last_attempt<REFRESH_MS: return
	_last_attempt=int(_clock.call())
	var factory := request_factory if request_factory.is_valid() else default_request_factory
	_backend=factory.call() if factory.is_valid() else TerrainBasemap.NativeBackend.new()
	if _backend==null: return
	add_child(_backend)
	_backend.finished.connect(_finished.bind(_backend),CONNECT_ONE_SHOT)
	if _backend.start(url,TerrainBasemap.request_headers())!=OK: _release()

func cancel() -> void:
	if is_instance_valid(_backend):
		_backend.abort()
		_last_attempt=-REFRESH_MS
	_release()

func _release() -> void:
	if is_instance_valid(_backend): _backend.queue_free()
	_backend=null

func _finished(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, backend: Node) -> void:
	if backend!=_backend: return
	_release()
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200 or body.is_empty() or body.size()>MAX_BODY: return
	var parsed := validate(parse_json(body.get_string_from_utf8()))
	last_error=parsed.error
	if not parsed.ok: return
	_store(JSON.stringify(parsed.config))
	source="published"
	if parsed.config==config: return
	config=parsed.config
	changed.emit(config.duplicate(true))

func _store(text: String) -> void:
	if _cache_path.is_empty(): return
	if DirAccess.make_dir_recursive_absolute(_cache_path.get_base_dir())!=OK: return
	var temporary := _cache_path+".part"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return
	file.store_string(text)
	file.close()
	if DirAccess.rename_absolute(temporary,_cache_path)!=OK: DirAccess.remove_absolute(temporary)

## JSON without engine error output for malformed text; null when unreadable.
static func parse_json(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text)==OK else null

static func _https_url(url: String) -> bool:
	if not url.begins_with("https://") or url.length()>512: return false
	var host := url.trim_prefix("https://").get_slice("/",0).get_slice("?",0)
	if host.is_empty() or host.contains("@") or host.begins_with(".") or not "." in host: return false
	for c in url:
		if c.unicode_at(0)<=32 or c in ["\"","'","<",">","\\","`"]: return false
	return true

static func host(url: String) -> String:
	return url.trim_prefix("https://").get_slice("/",0).get_slice("?",0).get_slice(":",0).to_lower()

static func _text(value: Variant, limit: int) -> String:
	if not value is String: return ""
	var text: String=value.strip_edges()
	for c in text:
		if c.unicode_at(0)<32: return ""
	return text if text.length()<=limit else ""

static func _int(value: Variant, low: int, high: int, fallback: int) -> Variant:
	if value==null: return fallback
	if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floor(float(value)): return null
	var number := int(value)
	return number if number>=low and number<=high else null

## Normalize a published file. Every field must be valid or the file is refused
## as a whole; omitted optional fields take their defaults.
static func validate(data: Variant) -> Dictionary:
	var refuse := func(reason: String) -> Dictionary: return {"ok":false,"error":reason,"config":{}}
	if not data is Dictionary: return refuse.call("not a JSON object")
	if data.get("schema")!=SCHEMA and data.get("schema")!=float(SCHEMA): return refuse.call("unsupported schema")
	if not data.get("tiles") is Dictionary or not data.get("search") is Dictionary: return refuse.call("tiles and search sections are required")
	var t: Dictionary=data.tiles
	var s: Dictionary=data.search
	var tiles := {}
	tiles.enabled=t.get("enabled",true)
	if not tiles.enabled is bool: return refuse.call("tiles.enabled must be true or false")
	tiles.url=_text(t.get("url",""),512)
	tiles.hidpi_url=_text(t.get("hidpi_url",""),512)
	tiles.attribution=_text(t.get("attribution",""),160)
	tiles.max_zoom=_int(t.get("max_zoom"),1,22,19)
	tiles.max_active=_int(t.get("max_active"),1,8,4)
	if tiles.max_zoom==null or tiles.max_active==null: return refuse.call("tile limits out of range")
	if tiles.enabled:
		for key in ["url","hidpi_url"]:
			var url: String=tiles[key]
			if key=="hidpi_url" and url.is_empty(): continue
			if not _https_url(url) or not ("{z}" in url and "{x}" in url and "{y}" in url): return refuse.call("tiles.%s must be an https template with {z}, {x} and {y}"%key)
		if tiles.attribution.is_empty(): return refuse.call("tiles.attribution is required")
	var search := {}
	search.enabled=s.get("enabled",true)
	if not search.enabled is bool: return refuse.call("search.enabled must be true or false")
	search.url=_text(s.get("url",""),512)
	search.format=_text(s.get("format","nominatim"),16)
	search.attribution=_text(s.get("attribution",""),160)
	search.min_interval_ms=_int(s.get("min_interval_ms"),0,60000,NOMINATIM_MIN_INTERVAL_MS)
	if search.min_interval_ms==null: return refuse.call("search.min_interval_ms out of range")
	if search.enabled:
		if not _https_url(search.url) or not "{query}" in search.url: return refuse.call("search.url must be an https template with {query}")
		if search.format not in ["nominatim","geojson"]: return refuse.call("search.format must be nominatim or geojson")
		if search.attribution.is_empty(): return refuse.call("search.attribution is required")
		# The public Nominatim policy allows one request per second.
		if host(search.url)==NOMINATIM_HOST: search.min_interval_ms=maxi(search.min_interval_ms,NOMINATIM_MIN_INTERVAL_MS)
	return {"ok":true,"error":"","config":{"schema":SCHEMA,"tiles":tiles,"search":search}}

func _exit_tree() -> void: cancel()
