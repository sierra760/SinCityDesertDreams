# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name TerrainPlaceSearch
extends Node
## Place-name search for the terrain chooser, on explicit submit only (the
## public Nominatim policy forbids search-as-you-type). The provider comes from
## TerrainMapConfig; requests keep its minimum interval (one second or more for
## public Nominatim) and repeated queries are answered from memory. Results only
## move the chooser's map and square; they are never saved with a city.
signal results_ready(query: String, results: Array)
signal failed(query: String, detail: String)

const LIMIT := 5
const MAX_QUERY := 200
const MAX_BODY := 262144
const CACHE_ENTRIES := 32

static var default_request_factory: Callable
var request_factory: Callable
var _clock: Callable = Time.get_ticks_msec
var _cache := {}
var _backend: Node
var _query := ""
var _pending := ""
var _last_start := -60000
var _provider: Dictionary = TerrainMapConfig.DEFAULT.search.duplicate(true)

func _init() -> void:
	name="TerrainPlaceSearch"

func set_clock(clock: Callable) -> void:
	if clock.is_valid(): _clock=clock

## Use the `search` section of a validated TerrainMapConfig.
func configure_provider(search: Dictionary) -> void:
	if search==_provider: return
	cancel()
	_cache.clear()
	_provider=search.duplicate(true)

func enabled() -> bool: return bool(_provider.get("enabled",false))
func attribution() -> String: return str(_provider.get("attribution",""))
func min_interval_ms() -> int: return int(_provider.get("min_interval_ms",TerrainMapConfig.NOMINATIM_MIN_INTERVAL_MS))

static func search_url(template: String, query: String, language: String) -> String:
	return template.replace("{limit}",str(LIMIT)).replace("{lang}",language.uri_encode()).replace("{query}",query.uri_encode())

static func normalize(query: String) -> String:
	return " ".join(query.strip_edges().split(" ",false)).left(MAX_QUERY)

func is_searching() -> bool: return not _query.is_empty() or not _pending.is_empty()

## Search for a place. A newer search replaces any older pending one.
func search(text: String) -> void:
	var query := normalize(text)
	cancel()
	if not enabled():
		failed.emit(query,"Place search is turned off")
		return
	if query.length()<2:
		failed.emit(query,"Type at least two characters")
		return
	# Nominatim ignores case, so the memory cache does too.
	if _cache.has(query.to_lower()):
		results_ready.emit.call_deferred(query,_cache[query.to_lower()].duplicate(true))
		return
	_pending=query
	_try_start()

func cancel() -> void:
	_pending=""
	_query=""
	if is_instance_valid(_backend):
		_backend.abort()
		_backend.queue_free()
	_backend=null

func _process(_delta: float) -> void:
	if not _pending.is_empty(): _try_start()

func _try_start() -> void:
	if _pending.is_empty() or is_instance_valid(_backend) or int(_clock.call())-_last_start<min_interval_ms(): return
	_query=_pending
	_pending=""
	_last_start=int(_clock.call())
	var factory := request_factory if request_factory.is_valid() else default_request_factory
	_backend=factory.call() if factory.is_valid() else TerrainBasemap.NativeBackend.new()
	if _backend==null:
		_finish_failure("Search could not be requested")
		return
	add_child(_backend)
	_backend.finished.connect(_finished.bind(_query,_backend),CONNECT_ONE_SHOT)
	var headers := TerrainBasemap.request_headers()
	var language := OS.get_locale_language()
	if not language.is_empty(): headers.append("Accept-Language: "+language)
	if _backend.start(search_url(str(_provider.url),_query,language),headers)!=OK:
		_finish_failure("Search could not be requested")

func _finish_failure(detail: String) -> void:
	var query := _query
	cancel()
	failed.emit(query,detail)

func _finished(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, query: String, backend: Node) -> void:
	if backend!=_backend or query!=_query: return
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200 or body.size()>MAX_BODY:
		_finish_failure("Search unavailable (%d/%d)"%[result,code])
		return
	var parsed := parse(body.get_string_from_utf8(),str(_provider.get("format","nominatim")))
	if not parsed.ok:
		_finish_failure(parsed.error)
		return
	_backend.queue_free()
	_backend=null
	_query=""
	_cache[query.to_lower()]=parsed.results
	while _cache.size()>CACHE_ENTRIES: _cache.erase(_cache.keys()[0])
	results_ready.emit(query,parsed.results.duplicate(true))

static func _place(name: String, latitude: float, longitude: float, bounds: Dictionary) -> Dictionary:
	if name.is_empty() or not is_finite(latitude) or not is_finite(longitude) or absf(latitude)>90.0 or absf(longitude)>180.0: return {}
	if not bounds.is_empty() and (bounds.south>bounds.north or bounds.west>bounds.east): bounds={}
	return {"name":name.left(240),"latitude":latitude,"longitude":longitude,"bounds":bounds}

static func _number(value: Variant) -> Variant:
	if value is int or value is float: return float(value)
	if value is String and value.is_valid_float(): return float(value)
	return null

## Provider answer → [{name, latitude, longitude, bounds}]. `nominatim` is the
## jsonv2 array; `geojson` is a FeatureCollection of Point features (Photon,
## Pelias, MapTiler). bounds holds south/north/west/east or is empty. Entries
## that do not parse are skipped.
static func parse(text: String, format: String = "nominatim") -> Dictionary:
	var decoded: Variant=TerrainMapConfig.parse_json(text)
	if format=="geojson": return _parse_geojson(decoded)
	if not decoded is Array: return {"ok":false,"error":"Search returned an unreadable answer","results":[]}
	var results: Array = []
	for item in decoded:
		if results.size()>=LIMIT: break
		if not item is Dictionary: continue
		var lat := str(item.get("lat",""))
		var lon := str(item.get("lon",""))
		var name := str(item.get("display_name","")).strip_edges()
		if not lat.is_valid_float() or not lon.is_valid_float(): continue
		var latitude := float(lat)
		var longitude := float(lon)
		var bounds := {}
		var box: Variant=item.get("boundingbox")
		if box is Array and box.size()==4 and box.all(func(value: Variant) -> bool: return str(value).is_valid_float()):
			var south := float(box[0]); var north := float(box[1]); var west := float(box[2]); var east := float(box[3])
			bounds={"south":south,"north":north,"west":west,"east":east}
		var place := _place(name,latitude,longitude,bounds)
		if not place.is_empty(): results.append(place)
	return {"ok":true,"error":"","results":results}

static func _parse_geojson(decoded: Variant) -> Dictionary:
	if not decoded is Dictionary or not decoded.get("features") is Array: return {"ok":false,"error":"Search returned an unreadable answer","results":[]}
	var results: Array = []
	for feature in decoded.features:
		if results.size()>=LIMIT: break
		if not feature is Dictionary or not feature.get("geometry") is Dictionary: continue
		var coordinates: Variant=feature.geometry.get("coordinates")
		if feature.geometry.get("type")!="Point" or not coordinates is Array or coordinates.size()<2: continue
		var longitude: Variant=_number(coordinates[0])
		var latitude: Variant=_number(coordinates[1])
		if longitude==null or latitude==null: continue
		var properties: Dictionary=feature.get("properties") if feature.get("properties") is Dictionary else {}
		var name := ""
		for candidate in [feature.get("place_name"),properties.get("label"),properties.get("display_name"),properties.get("name")]:
			if candidate is String and not candidate.strip_edges().is_empty():
				name=candidate.strip_edges()
				break
		# Photon gives only the name; add its locality context.
		if properties.has("osm_id") and not properties.has("label"):
			var context: Array = []
			for key in ["city","state","country"]:
				var part: Variant=properties.get(key)
				if part is String and not part.is_empty() and part!=name and part not in context: context.append(part)
			if not context.is_empty(): name+=", "+", ".join(context)
		var bounds := {}
		var box: Variant=feature.get("bbox")
		if box is Array and box.size()==4 and box.all(func(v: Variant) -> bool: return _number(v)!=null):
			bounds={"west":float(box[0]),"south":float(box[1]),"east":float(box[2]),"north":float(box[3])}
		elif properties.get("extent") is Array and properties.extent.size()==4 and properties.extent.all(func(v: Variant) -> bool: return _number(v)!=null):
			var e: Array=properties.extent
			bounds={"west":float(e[0]),"north":float(e[1]),"east":float(e[2]),"south":float(e[3])}
		var place := _place(name,float(latitude),float(longitude),bounds)
		if not place.is_empty(): results.append(place)
	return {"ok":true,"error":"","results":results}

func _exit_tree() -> void: cancel()
