# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name TerrainTileCache
extends RefCounted
## On-disk cache of downloaded terrain tiles. Callers validate a body's format
## before publishing it. The metadata file is written last and marks the entry
## complete. Readers never trust half-written bodies, file paths stored in the
## JSON, or entries for a different object version.
const MAX_BYTES := 134217728
const PREFIX := "terrain-v1-"
# Directory listing costs grow with the entry count. Reconciliation runs on every
# publication for small caches and otherwise about once per this many entries'
# worth of publications, bounding its amortized cost per publication.
const RECONCILE_STRIDE := 64
## Tiles are disposable downloads. They live in the OS cache, not user://, which
## on iOS is the Files-visible, iCloud-backed Documents folder. Roots below
## user:// are still accepted, for test fixtures and for platforms without an
## OS cache directory.
const ROOT_NAME := "terrain_tiles_v1"
const LEGACY_ROOT := "user://terrain_tiles_v1"
var _root := LEGACY_ROOT
# Trusted directory the root is confined to and the root's path below it.
var _base := ""
var _relative := ""
var _limit := MAX_BYTES
var _configured := true
var _access := 0
# In-memory index of the configured root, loaded once and kept in step with
# every write this instance makes: key -> {access, body, index} plus the byte
# total of every owned file. Anything unexpected invalidates it for a rescan.
var _loaded := false
var _entries := {}
var _total := 0
var _since_reconcile := 0
static var _patterns := {}

func _init() -> void:
	configure()

## The OS cache directory with forward slashes, or "" where none exists.
static func cache_base() -> String:
	return OS.get_cache_dir().replace("\\","/").trim_suffix("/")

## Desktop OS caches are shared by every application (~/Library/Caches,
## %LOCALAPPDATA%, ~/.cache); the project's user-data directory name keeps this
## app's cache separate. iOS/Android caches are already private to the app.
static func app_dir_name() -> String:
	var name := String(ProjectSettings.get_setting("application/config/custom_user_dir_name",""))
	if name.is_empty(): name = String(ProjectSettings.get_setting("application/config/name","")).validate_filename()
	return name

static func root_for(base: String, app_dir: String) -> String:
	if base.is_empty() or app_dir.is_empty() or app_dir.contains("/") or app_dir.contains("\\") or app_dir in [".",".."]: return LEGACY_ROOT
	return base.path_join(app_dir).path_join(ROOT_NAME)

static func default_root() -> String:
	return root_for(cache_base(),app_dir_name())

func configure(root: String = "", max_bytes: int = MAX_BYTES) -> void:
	if root.is_empty(): root=default_root()
	_root=root
	_limit=max_bytes
	_invalidate()
	_base=""
	_relative=""
	# A root must sit inside this app's own cache or user directory.
	var own := default_root()
	if root==LEGACY_ROOT or root.begins_with(LEGACY_ROOT+"/"):
		_base=ProjectSettings.globalize_path("user://")
		_relative=root.trim_prefix("user://")
	elif own!=LEGACY_ROOT and (root==own or root.begins_with(own+"/")):
		_base=cache_base()
		_relative=root.trim_prefix(_base+"/")
	_configured=max_bytes>0 and max_bytes<=MAX_BYTES and not _base.is_empty() and not _relative.is_empty()
	if root.contains("\\") or _relative.contains("//"): _configured=false
	for part in _relative.split("/"):
		if part in [".","..",""]: _configured=false

func _safe_root(create: bool = false) -> bool:
	if not _configured: return false
	# Platform data paths may legitimately sit below symlinked system directories
	# (iOS /var -> /private/var, Android /data/user/0 -> /data/data). Only the
	# cache's own segments below its base (OS cache or user://) are examined,
	# before mkdir/read/write.
	if not symlink_free_below(_base,_relative): return false
	if create and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_root))!=OK: return false
	return true

## True when no segment of relative, walked downward from base, is a symlink.
## Ancestors of base itself are deliberately not examined.
static func symlink_free_below(base: String, relative: String) -> bool:
	var at := base.trim_suffix("/")
	for part in relative.split("/",false):
		var parent := DirAccess.open(at)
		if parent!=null and parent.is_link(part): return false
		at=at.path_join(part)
	return true

static func _pattern(source: String) -> RegEx:
	if not _patterns.has(source):
		var regex := RegEx.new()
		regex.compile(source)
		_patterns[source]=regex
	return _patterns[source]

static func _sha(body: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(body)
	return hash.finish().hex_encode()
static func _descriptor(resource: Dictionary) -> String:
	return "terrarium:%d:%d:%d"%[resource.z,resource.x,resource.y] if resource.source=="terrarium" else "worldcover:"+resource.tile
static func _key(resource: Dictionary, byte_range: Dictionary, identity: Dictionary) -> String:
	# Explicit scalar ordering; decimal strings retain 64-bit source offsets.
	var canonical := [_descriptor(resource),str(byte_range.get("offset",0)),str(byte_range.get("length",identity.size)),identity.etag,str(identity.size)]
	return _sha(JSON.stringify(canonical).to_utf8_buffer())
func _paths(key: String) -> Dictionary:
	var base := _root.path_join(PREFIX+key)
	return {"body":base+".body","index":base+".json"}
func _regular(path: String) -> bool:
	var parent := DirAccess.open(path.get_base_dir())
	return parent!=null and not parent.is_link(path.get_file()) and FileAccess.file_exists(path)
func _entry(path: String, key: String) -> Dictionary:
	if not _regular(path): return {}
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>4096: return {}
	var text := file.get_as_text()
	var decoded: Variant = JSON.parse_string(text)
	if not decoded is Dictionary or decoded.size()!=8: return {}
	for field in ["key","descriptor","etag","size","offset","length","sha256","access"]:
		if not decoded.get(field) is String: return {}
	if decoded.key!=key or decoded.etag.is_empty() or decoded.etag.length()>256: return {}
	for field in ["size","offset","length","access"]:
		if not decoded[field].is_valid_int(): return {}
	var size := int(decoded.size)
	var offset := int(decoded.offset)
	var length := int(decoded.length)
	if size<1 or size>1099511627776 or offset<0 or length<1 or length>2097152 or offset>size-length or int(decoded.access)<0: return {}
	if _pattern("^[0-9a-f]{64}$").search(decoded.sha256)==null: return {}
	return decoded
func _invalidate() -> void:
	_loaded=false
	_entries.clear()
	_total=0
## Loads the index once per configured root. Persisted ordering can exceed a
## restarted process clock, so untouched entries also advance the access clock.
func _ensure_loaded() -> Dictionary:
	if _loaded: return {"ok":true,"error":""}
	_invalidate()
	var directory := DirAccess.open(_root)
	if directory==null:
		_loaded=true
		return {"ok":true,"error":""}
	var owned := _pattern("^terrain-v1-([0-9a-f]{64})\\.(body|json)(\\.tmp)?$")
	var entries := {}
	var total := 0
	for name in directory.get_files():
		var matched := owned.search(name)
		if matched==null: continue
		if directory.is_link(name): return {"ok":false,"error":"Cache entry is a symlink"}
		var file := FileAccess.open(_root.path_join(name),FileAccess.READ)
		if file==null: return {"ok":false,"error":"Cache size unavailable"}
		var bytes := file.get_length()
		file.close()
		total+=bytes
		if not name.ends_with(".json"): continue
		var key := matched.get_string(1)
		var metadata := _entry(_root.path_join(name),key)
		if metadata.is_empty(): continue
		_access=maxi(_access,int(metadata.access))
		var body_path: String = _paths(key).body
		if not _regular(body_path): continue
		var body_file := FileAccess.open(body_path,FileAccess.READ)
		if body_file==null: continue
		entries[key]={"access":int(metadata.access),"body":body_file.get_length(),"index":bytes}
	_entries=entries
	_total=total
	_loaded=true
	return {"ok":true,"error":""}
func _next_access() -> String:
	_access=maxi(_access,Time.get_ticks_msec())+1
	return str(_access)
func _write_index(path: String, metadata: Dictionary, body_bytes: int) -> bool:
	var temporary := path+".tmp"
	if not _safe_root(true) or not _ensure_loaded().ok: return false
	var directory := DirAccess.open(_root)
	if directory==null or directory.is_link(temporary.get_file()) or directory.is_link(path.get_file()): return false
	var encoded := JSON.stringify(metadata).to_utf8_buffer()
	if encoded.size()>4096 or not _reserve(encoded.size(),metadata.key).ok: return false
	var old_bytes := 0
	if _regular(path):
		var old := FileAccess.open(path,FileAccess.READ)
		if old!=null: old_bytes=old.get_length()
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return false
	file.store_buffer(encoded)
	file.flush()
	var status := file.get_error()
	file.close()
	if status!=OK:
		DirAccess.remove_absolute(temporary)
		_invalidate()
		return false
	if DirAccess.rename_absolute(temporary,path)!=OK:
		DirAccess.remove_absolute(temporary)
		_invalidate()
		return false
	_total+=encoded.size()-old_bytes
	_entries[metadata.key]={"access":int(metadata.access),"body":body_bytes,"index":encoded.size()}
	return true
func lookup(resource: Dictionary, byte_range: Dictionary, identity: Dictionary) -> Dictionary:
	var valid := TerrainHttpTransport.validate_request(resource,byte_range,identity)
	if not valid.ok or identity.is_empty(): return {"ok":false,"error":"Invalid cache identity or range"}
	if not _safe_root(): return {"ok":false,"error":"Unsafe cache root"}
	var key := _key(resource,byte_range,identity)
	var paths := _paths(key)
	var entry := _entry(paths.index,key)
	if entry.is_empty() or entry.descriptor!=_descriptor(resource) or entry.etag!=identity.etag or int(entry.size)!=identity.size or int(entry.offset)!=byte_range.get("offset",0) or int(entry.length)!=byte_range.get("length",identity.size) or not _regular(paths.body):
		return {"ok":false,"error":"Cache miss or invalid metadata"}
	var file := FileAccess.open(paths.body,FileAccess.READ)
	if file==null or file.get_length()!=int(entry.length): return {"ok":false,"error":"Invalid cached body length"}
	var body := file.get_buffer(int(entry.length))
	if _sha(body)!=entry.sha256: return {"ok":false,"error":"Cached body hash mismatch"}
	if not _ensure_loaded().ok: return {"ok":false,"error":"Cache access publication failed"}
	_access=maxi(_access,int(entry.access))
	entry.access=_next_access()
	if not _write_index(paths.index,entry,body.size()): return {"ok":false,"error":"Cache access publication failed"}
	return {"ok":true,"error":"","body":body,"etag":identity.etag,"size":identity.size,"range":byte_range.duplicate(true),"sha256":entry.sha256}

func publish(resource: Dictionary, byte_range: Dictionary, identity: Dictionary, body: PackedByteArray) -> Dictionary:
	var valid := TerrainHttpTransport.validate_request(resource,byte_range,identity)
	if not valid.ok or identity.is_empty(): return {"ok":false,"error":"Invalid cache identity or range"}
	var expected: int = byte_range.get("length",identity.size)
	if body.is_empty() or body.size()>2097152 or body.size()!=expected or body.size()>_limit: return {"ok":false,"error":"Invalid cache body size"}
	if not _safe_root(true): return {"ok":false,"error":"Unsafe cache root"}
	if not _loaded or (_since_reconcile+1)*RECONCILE_STRIDE>=_entries.size():
		var recovery := _recover()
		if not recovery.ok: return recovery
		_since_reconcile=0
	else: _since_reconcile+=1
	var loaded := _ensure_loaded()
	if not loaded.ok: return loaded
	var key := _key(resource,byte_range,identity)
	var paths := _paths(key)
	var directory := DirAccess.open(_root)
	for path in [paths.body,paths.index,paths.body+".tmp",paths.index+".tmp"]:
		if directory.is_link(path.get_file()): return {"ok":false,"error":"Cache entry is a symlink"}
	var entry := {"key":key,"descriptor":_descriptor(resource),"etag":identity.etag,"size":str(identity.size),"offset":str(byte_range.get("offset",0)),"length":str(expected),"sha256":_sha(body),"access":_next_access()}
	var old_body_bytes := 0
	if _regular(paths.body):
		var old_body := FileAccess.open(paths.body,FileAccess.READ)
		if old_body!=null: old_body_bytes=old_body.get_length()
	var marker_bytes := JSON.stringify(entry).to_utf8_buffer().size()
	# Peak is either body.tmp with old commit intact, or the replacement marker
	# beside the renamed body and old marker. Reserve before modifying either.
	var peak_extra := maxi(body.size(),body.size()-old_body_bytes+marker_bytes)
	var reserved := _reserve(peak_extra,key)
	if not reserved.ok: return reserved
	var file := FileAccess.open(paths.body+".tmp",FileAccess.WRITE)
	if file==null: return {"ok":false,"error":"Cache body write failed"}
	file.store_buffer(body)
	file.flush()
	var status := file.get_error()
	file.close()
	if status!=OK or DirAccess.rename_absolute(paths.body+".tmp",paths.body)!=OK:
		DirAccess.remove_absolute(paths.body+".tmp")
		_invalidate()
		return {"ok":false,"error":"Cache body publication failed"}
	_total+=body.size()-old_body_bytes
	if _entries.has(key): _entries[key].body=body.size()
	if not _write_index(paths.index,entry,body.size()):
		_invalidate()
		return {"ok":false,"error":"Cache index publication failed"}
	var eviction := _evict()
	if not eviction.ok: return eviction
	return {"ok":true,"error":"","body_path":paths.body,"index_path":paths.index,"sha256":entry.sha256}

## Directory reconciliation before publication (see RECONCILE_STRIDE): torn
## staging files and half entries are removed. Entries this index already validated are trusted
## by name, so a steady-state publication parses no metadata. Unknown, missing
## or removed entries invalidate the index for a full rescan.
func _recover() -> Dictionary:
	var directory := DirAccess.open(_root)
	if directory==null: return {"ok":false,"error":"Cache unavailable"}
	var regex := _pattern("^terrain-v1-([0-9a-f]{64})\\.(body|json)(\\.tmp)?$")
	var owned := {}
	for name in directory.get_files():
		var matched := regex.search(name)
		if matched==null: continue
		if directory.is_link(name): return {"ok":false,"error":"Cache entry is a symlink"}
		owned[name]=matched.get_string(1)
	var rescan := false
	var known := {}
	var validated := {}
	for name: String in owned:
		var key: String = owned[name]
		var paths := _paths(key)
		var stale := name.ends_with(".tmp")
		if not stale and _loaded and _entries.has(key):
			known[key]=true
			stale=not owned.has(paths.body.get_file()) or not owned.has(paths.index.get_file())
		elif not stale:
			if not validated.has(key):
				var metadata := _entry(paths.index,key)
				var invalid := metadata.is_empty() or not _regular(paths.body)
				if not invalid:
					var body := FileAccess.open(paths.body,FileAccess.READ)
					invalid=body==null or body.get_length()!=int(metadata.length)
				validated[key]=not invalid
			stale=not validated[key]
			rescan=true
		if stale:
			rescan=true
			if FileAccess.file_exists(_root.path_join(name)):
				if DirAccess.remove_absolute(_root.path_join(name))!=OK:
					_invalidate()
					return {"ok":false,"error":"Torn cache recovery failed"}
	if rescan or known.size()!=_entries.size(): _invalidate()
	return {"ok":true,"error":""}

func _reserve(extra_bytes: int, protected_key: String) -> Dictionary:
	if extra_bytes<0 or extra_bytes>_limit: return {"ok":false,"error":"Cache publication exceeds disk budget"}
	return _evict(_limit-extra_bytes,protected_key)
## Least-recently-accessed eviction over the in-memory index; only runs when
## the tracked owned-byte total exceeds the target.
func _evict(target_bytes: int = -1, protected_key: String = "") -> Dictionary:
	var loaded := _ensure_loaded()
	if not loaded.ok: return loaded
	if target_bytes<0: target_bytes=_limit
	if _total<=target_bytes: return {"ok":true,"error":""}
	var candidates: Array[Dictionary] = []
	for key: String in _entries:
		if key==protected_key: continue
		var entry: Dictionary = _entries[key]
		candidates.append({"key":key,"bytes":int(entry.body)+int(entry.index),"access":int(entry.access)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.access<b.access)
	for candidate in candidates:
		if _total<=target_bytes: break
		var paths := _paths(candidate.key)
		# Remove the commit marker first; no reader observes half of a valid entry.
		for path: String in [paths.index,paths.body]:
			if FileAccess.file_exists(path) and DirAccess.remove_absolute(path)!=OK:
				_invalidate()
				return {"ok":false,"error":"Cache eviction failed"}
		_entries.erase(candidate.key)
		_total-=int(candidate.bytes)
	if _total>target_bytes: return {"ok":false,"error":"Insufficient cache publication headroom"}
	return {"ok":true,"error":""}
func clear() -> Dictionary:
	if not _safe_root(): return {"ok":false,"error":"Unsafe cache root"}
	_invalidate()
	var directory := DirAccess.open(_root)
	if directory==null: return {"ok":true,"error":"","removed":0}
	var regex := _pattern("^terrain-v1-([0-9a-f]{64})\\.(body|json)(\\.tmp)?$")
	var removed := 0
	for name in directory.get_files():
		if regex.search(name)==null: continue
		if directory.is_link(name): return {"ok":false,"error":"Cache entry is a symlink"}
		if DirAccess.remove_absolute(_root.path_join(name))!=OK: return {"ok":false,"error":"Cache clear failed"}
		removed+=1
	return {"ok":true,"error":"","removed":removed}
