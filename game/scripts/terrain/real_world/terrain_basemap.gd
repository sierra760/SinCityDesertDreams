# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name TerrainBasemap
extends Node
## Street basemap behind the real-world terrain chooser. Display only: it never
## feeds terrain conversion and does not wait for the elevation or water checks.
## The provider comes from TerrainMapConfig. Only tiles the player is viewing
## are requested (no prefetch). Viewed tiles stay on disk for at least seven
## days, as the OpenStreetMap tile policy asks; stale tiles are shown at once
## while they revalidate. On high-density screens a provider's optional 512 px
## (@2x) template keeps the map sharp at the same tile count.
signal tiles_changed

## Logical tile size; 512 px @2x tiles cover the same 256-unit square.
const TILE := 256
const HIDPI_TILE := 512
const MEMORY_TILES := 128
const FRESH_SECONDS := 604800
const DISK_MAX_BYTES := 67108864
const DISK_ROOT_NAME := "map_tiles_v1"
const PRUNE_STRIDE := 64
const MAX_BODY := 1048576
const TIMEOUT := 15.0
const RETRY_MS := 30000
## Longest address a redirect may name.
const REDIRECT_URL_MAX := 4096
## Segments and padding bytes read while looking for a JPEG's frame header.
const JPEG_HEADER_STEPS := 256

## Node with start(url, headers) -> Error, abort() and
## finished(result, code, headers, body), like an HTTPRequest wrapper.
class NativeBackend extends Node:
	signal finished(result: int, code: int, headers: PackedStringArray, body: PackedByteArray)
	## Redirects followed, each only to the host that was asked (see
	## `redirect_target`); any other redirect ends the request as a failure.
	var max_redirects := 2
	var http: HTTPRequest
	var _url := ""
	var _headers := PackedStringArray()
	var _hops := 0
	func start(url: String, headers: PackedStringArray) -> int:
		_url=url
		_headers=headers
		_hops=0
		return _request()
	func abort() -> void:
		if is_instance_valid(http): http.cancel_request()
	## A request that never follows a redirect by itself: the engine would
	## follow one to any host.
	static func make_request() -> HTTPRequest:
		var request := HTTPRequest.new()
		request.timeout=TIMEOUT
		request.body_size_limit=MAX_BODY
		request.max_redirects=0
		return request
	func _request() -> int:
		if is_instance_valid(http): http.queue_free()
		http=make_request()
		add_child(http)
		http.request_completed.connect(_completed)
		return http.request(_url,_headers)
	func _completed(result: int, code: int, response_headers: PackedStringArray, body: PackedByteArray) -> void:
		if result==HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED and _hops<max_redirects:
			var next := TerrainBasemap.redirect_target(_url,response_headers)
			if not next.is_empty():
				_hops+=1
				_url=next
				if _request()==OK: return
		finished.emit(result,code,response_headers,body)

## Tests replace this once so no suite reaches the public tile servers.
static var default_request_factory: Callable
var request_factory: Callable
var _clock: Callable = Time.get_unix_time_from_system
var _active := false
var _wanted: Array = []
var _queue: Array = []
var _requests := {}
var _memory := {}
var _use := 0
var _failed := {}
var _disk_root := ""
var _disk_base := ""
var _disk_writes := 0
var _last_error := ""
var _provider: Dictionary = TerrainMapConfig.DEFAULT.tiles.duplicate(true)
var _hidpi := false
var _template := ""
var _tile_pixels := TILE

func _init() -> void:
	name="TerrainBasemap"
	_select_template()
	configure_disk()

static func user_agent() -> String:
	return "SinCityDesertDreams/%s (+https://github.com/sierra760/SinCityDesertDreams)"%str(ProjectSettings.get_setting("application/config/version","0"))

## Browsers send their own User-Agent and a Referer; setting one there would
## only force a CORS preflight.
static func request_headers() -> PackedStringArray:
	return PackedStringArray() if OS.has_feature("web") else PackedStringArray(["User-Agent: "+user_agent()])

static func default_disk_root() -> String:
	var base := TerrainTileCache.cache_base()
	var app := TerrainTileCache.app_dir_name()
	if OS.has_feature("web") or base.is_empty() or app.is_empty() or app.contains("/") or app.contains("\\") or app in [".",".."]: return ""
	return base.path_join(app).path_join(DISK_ROOT_NAME)

## Empty root disables the disk cache. Each tile template gets its own folder.
func configure_disk(root: String = "<default>") -> void:
	_disk_base=default_disk_root() if root=="<default>" else root
	_disk_root="" if _disk_base.is_empty() else _disk_base.path_join(_template.sha256_text().left(12))

## Use the `tiles` section of a validated TerrainMapConfig.
func configure_provider(tiles: Dictionary) -> void:
	_provider=tiles.duplicate(true)
	_select_template()

## True on screens with at least 1.5 device pixels per logical pixel.
func set_hidpi(value: bool) -> void:
	if value==_hidpi: return
	_hidpi=value
	_select_template()

func enabled() -> bool: return bool(_provider.get("enabled",false))
func attribution() -> String: return str(_provider.get("attribution",""))
func max_zoom() -> int: return int(_provider.get("max_zoom",19))
func uses_hidpi_tiles() -> bool: return _tile_pixels==HIDPI_TILE

func _select_template() -> void:
	var hidpi_url := str(_provider.get("hidpi_url",""))
	var template := hidpi_url if _hidpi and not hidpi_url.is_empty() else str(_provider.get("url",""))
	if not enabled(): template=""
	if template==_template: return
	_template=template
	_tile_pixels=HIDPI_TILE if template==hidpi_url and not hidpi_url.is_empty() else TILE
	cancel()
	_memory.clear()
	_failed.clear()
	_last_error=""
	configure_disk(_disk_base)
	tiles_changed.emit()

func set_clock(clock: Callable) -> void:
	if clock.is_valid(): _clock=clock

func last_error() -> String: return _last_error

static func key(z: int, x: int, y: int) -> String: return "%d/%d/%d"%[z,x,y]

## Tiles covering a view of `size` pixels around the Web Mercator pixel
## (center_x, center_y) at zoom z, nearest the center first.
static func visible_tiles(center_x: float, center_y: float, z: int, size: Vector2) -> Array:
	var count := 1<<z
	var half := size/2.0
	var x0 := floori((center_x-half.x)/TILE)
	var x1 := floori((center_x+half.x)/TILE)
	var y0 := maxi(0,floori((center_y-half.y)/TILE))
	var y1 := mini(count-1,floori((center_y+half.y)/TILE))
	var tiles: Array = []
	var seen := {}
	for ty in range(y0,y1+1):
		for tx in range(x0,x1+1):
			var wrapped := posmod(tx,count)
			var id := key(z,wrapped,ty)
			if seen.has(id): continue
			seen[id]=true
			var dx := (tx+0.5)*TILE-center_x
			var dy := (ty+0.5)*TILE-center_y
			tiles.append({"z":z,"x":wrapped,"y":ty,"d":dx*dx+dy*dy})
	tiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d<b.d)
	return tiles

## Replace the wanted set with the tiles of the current view. Pending requests
## for tiles that scrolled away are dropped; in-flight ones finish.
func request_view(center_x: float, center_y: float, z: int, size: Vector2) -> void:
	if _template.is_empty():
		_wanted=[]
		_queue.clear()
		return
	_wanted=visible_tiles(center_x,center_y,clampi(z,0,max_zoom()),size)
	_queue.clear()
	var changed := false
	var now := _now_ms()
	for tile in _wanted:
		var id := key(tile.z,tile.x,tile.y)
		if _memory.has(id):
			_memory[id].use=_next_use()
			if not _memory[id].stale or _requests.has(id): continue
		elif _load_disk(tile):
			changed=true
			if not _memory[id].stale: continue
		if _requests.has(id) or now<int(_failed.get(id,-RETRY_MS))+RETRY_MS: continue
		_queue.append(tile)
	if changed: tiles_changed.emit()
	_pump()

func set_active(value: bool) -> void:
	_active=value
	if not value: cancel()
	else: _pump()

func cancel() -> void:
	_queue.clear()
	for id in _requests.keys(): _drop(id)

## Texture for one tile, or null when it is not loaded.
func texture(z: int, x: int, y: int) -> Texture2D:
	var entry: Dictionary=_memory.get(key(z,x,y),{})
	return entry.get("texture")

func loaded_count() -> int: return _memory.size()
func pending_count() -> int: return _queue.size()+_requests.size()

func _now_ms() -> int: return int(float(_clock.call())*1000.0)
func _next_use() -> int:
	_use+=1
	return _use

func _pump() -> void:
	while _active and _requests.size()<int(_provider.get("max_active",4)) and not _queue.is_empty():
		_start(_queue.pop_front())

func _start(tile: Dictionary) -> void:
	var factory := request_factory if request_factory.is_valid() else default_request_factory
	var backend: Node = factory.call() if factory.is_valid() else NativeBackend.new()
	if backend==null: return
	var id := key(tile.z,tile.x,tile.y)
	add_child(backend)
	_requests[id]=backend
	backend.finished.connect(_finished.bind(tile,backend),CONNECT_ONE_SHOT)
	if backend.start(tile_url(_template,tile.z,tile.x,tile.y),request_headers())!=OK:
		_fail(id,"Map tiles could not be requested")

func _drop(id: String) -> void:
	var backend: Node=_requests.get(id)
	_requests.erase(id)
	if is_instance_valid(backend):
		backend.abort()
		backend.queue_free()

func _fail(id: String, detail: String) -> void:
	_drop(id)
	_failed[id]=_now_ms()
	_last_error=detail
	tiles_changed.emit()
	_pump()

func _finished(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, tile: Dictionary, backend: Node) -> void:
	var id := key(tile.z,tile.x,tile.y)
	if _requests.get(id)!=backend: return
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
		_fail(id,"Map unavailable (%d/%d)"%[result,code])
		return
	var texture_value := decode(body,_tile_pixels)
	if texture_value==null:
		_fail(id,"Map tile was not a valid image")
		return
	_drop(id)
	_failed.erase(id)
	_last_error=""
	_remember(id,texture_value,false)
	_store_disk(tile,body)
	tiles_changed.emit()
	_pump()

static func tile_url(template: String, z: int, x: int, y: int) -> String:
	return template.replace("{z}",str(z)).replace("{x}",str(x)).replace("{y}",str(y))

## Where a redirect may continue: the `Location` among `headers` as a full
## URL when it stays on the https host that `url` asked; empty otherwise.
static func redirect_target(url: String, headers: PackedStringArray) -> String:
	if not TerrainMapConfig.is_https_url(url,REDIRECT_URL_MAX): return ""
	var location := ""
	for header in headers:
		if header.left(9).to_lower()=="location:":
			location=header.substr(9).strip_edges()
			break
	if location.begins_with("/"):
		# "//host" and "/\host" name another host, not a path.
		if location.length()>1 and location[1] in ["/","\\"]: return ""
		location="https://"+url.trim_prefix("https://").get_slice("/",0).get_slice("?",0)+location
	if not TerrainMapConfig.is_https_url(location,REDIRECT_URL_MAX) or TerrainMapConfig.host(location)!=TerrainMapConfig.host(url): return ""
	return location

static func _big_endian(body: PackedByteArray, at: int, count: int) -> int:
	var value := 0
	for i in count: value=(value<<8)|body[at+i]
	return value

## The width and height a PNG or JPEG says it has, read from its header
## without decoding anything; zero when there is no well-formed header.
static func declared_size(body: PackedByteArray) -> Vector2i:
	var length := body.size()
	if length>=24 and body.slice(0,8)==PackedByteArray([137,80,78,71,13,10,26,10]):
		# The header chunk always comes first: length 13, "IHDR", width, height.
		if body.slice(8,16)!=PackedByteArray([0,0,0,13,73,72,68,82]): return Vector2i.ZERO
		return Vector2i(_big_endian(body,16,4),_big_endian(body,20,4))
	if length<4 or body[0]!=255 or body[1]!=216: return Vector2i.ZERO
	# JPEG: walk the segments before the image data to the frame header.
	var at := 2
	for _step in JPEG_HEADER_STEPS:
		if at+3>=length or body[at]!=255: return Vector2i.ZERO
		var marker := body[at+1]
		if marker==255:
			at+=1
			continue
		var segment := _big_endian(body,at+2,2)
		if segment<2: return Vector2i.ZERO
		# Frame headers: C0–CF except the tables C4 and CC and the reserved C8.
		if marker>=192 and marker<=207 and marker not in [196,200,204]:
			if segment<7 or at+9>length: return Vector2i.ZERO
			return Vector2i(_big_endian(body,at+7,2),_big_endian(body,at+5,2))
		# Only tables, application data and comments may come before it.
		if not (marker in [196,204,219,221,254] or (marker>=224 and marker<=239)): return Vector2i.ZERO
		at+=2+segment
	return Vector2i.ZERO

## Square PNG or JPEG tiles of the expected size only; anything else is rejected.
## The size is read from the header first: decoding is what costs memory and
## time, and a small response can claim a very large image.
static func decode(body: PackedByteArray, pixels: int = TILE) -> Texture2D:
	if body.size()<33 or body.size()>MAX_BODY: return null
	if declared_size(body)!=Vector2i(pixels,pixels): return null
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	if body.slice(0,8)==PackedByteArray([137,80,78,71,13,10,26,10]): error=image.load_png_from_buffer(body)
	elif body.slice(0,3)==PackedByteArray([255,216,255]): error=image.load_jpg_from_buffer(body)
	if error!=OK or image.get_width()!=pixels or image.get_height()!=pixels: return null
	return ImageTexture.create_from_image(image)

func _remember(id: String, texture_value: Texture2D, stale: bool) -> void:
	_memory[id]={"texture":texture_value,"use":_next_use(),"stale":stale}
	if _memory.size()<=MEMORY_TILES: return
	var wanted := {}
	for tile in _wanted: wanted[key(tile.z,tile.x,tile.y)]=true
	var order: Array=_memory.keys()
	order.sort_custom(func(a: String, b: String) -> bool: return _memory[a].use<_memory[b].use)
	for old in order:
		if _memory.size()<=MEMORY_TILES: break
		if not wanted.has(old): _memory.erase(old)

func _disk_path(tile: Dictionary) -> String:
	return _disk_root.path_join("%d-%d-%d.tile"%[tile.z,tile.x,tile.y])

func _load_disk(tile: Dictionary) -> bool:
	if _disk_root.is_empty(): return false
	var path := _disk_path(tile)
	if not FileAccess.file_exists(path): return false
	var texture_value := decode(FileAccess.get_file_as_bytes(path),_tile_pixels)
	if texture_value==null:
		DirAccess.remove_absolute(path)
		return false
	var age := float(_clock.call())-float(FileAccess.get_modified_time(path))
	_remember(key(tile.z,tile.x,tile.y),texture_value,age>=FRESH_SECONDS)
	return true

func _store_disk(tile: Dictionary, body: PackedByteArray) -> void:
	if _disk_root.is_empty(): return
	# Only the cache's own segments below the OS cache directory are examined.
	var base := TerrainTileCache.cache_base()
	if not base.is_empty() and _disk_root.begins_with(base+"/") and not TerrainTileCache.symlink_free_below(base,_disk_root.trim_prefix(base+"/")): return
	if DirAccess.make_dir_recursive_absolute(_disk_root)!=OK: return
	var path := _disk_path(tile)
	var temporary := path+".part"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return
	file.store_buffer(body)
	file.close()
	if DirAccess.rename_absolute(temporary,path)!=OK:
		DirAccess.remove_absolute(temporary)
		return
	_disk_writes+=1
	if _disk_writes%PRUNE_STRIDE==1: prune_disk()

## Remove the least recently written tiles beyond the disk budget, across every
## provider folder, so switching providers cannot grow the cache without bound.
func prune_disk(max_bytes: int = DISK_MAX_BYTES) -> void:
	if _disk_base.is_empty() or not DirAccess.dir_exists_absolute(_disk_base): return
	var files: Array = []
	var total := 0
	for folder in DirAccess.get_directories_at(_disk_base):
		var directory := _disk_base.path_join(folder)
		for file_name in DirAccess.get_files_at(directory):
			var path := directory.path_join(file_name)
			if not file_name.ends_with(".tile"):
				DirAccess.remove_absolute(path)
				continue
			var handle := FileAccess.open(path,FileAccess.READ)
			if handle==null: continue
			var length := handle.get_length()
			handle.close()
			total+=length
			files.append([FileAccess.get_modified_time(path),path,length])
	if total>max_bytes:
		files.sort()
		for entry in files:
			if total<=max_bytes: break
			if DirAccess.remove_absolute(entry[1])==OK: total-=int(entry[2])
	for folder in DirAccess.get_directories_at(_disk_base):
		var directory := _disk_base.path_join(folder)
		if DirAccess.get_files_at(directory).is_empty(): DirAccess.remove_absolute(directory)

func clear_disk() -> void:
	prune_disk(0)

func _exit_tree() -> void: cancel()
