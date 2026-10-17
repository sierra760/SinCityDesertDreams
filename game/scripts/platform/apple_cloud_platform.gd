# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
class_name AppleCloudPlatform
extends RefCounted
## Main-thread adapter. Native work is asynchronous and never owns Godot values.
const CONFIG := "res://addons/apple_cloud/apple_cloud.cfg"
const CONTAINER := "iCloud.com.sierraburkhart.sincitydesertdreams"
const OPS := ["account", "prepare_zone", "changes", "fetch_record", "download", "save"]
const CODES := ["unavailable", "signed_out", "transient", "quota", "conflict", "token_expired", "cancelled", "invalid", "permission"]
const STAGING := "user://apple-cloud-staging"
## Completions settled per drain; native bounds outstanding requests, so a larger
## batch (account notifications) is held and settled over the next drains.
const DRAIN_LIMIT := 64
var _native: RefCounted
var _requests: Dictionary = {}
var _backlog: Array = []
## Outstanding request ids that received a malformed or mismatched completion.
var _suspect: Dictionary = {}

func _init() -> void:
	if Engine.is_editor_hint() or OS.has_feature("editor") or DisplayServer.get_name() == "headless": return
	if OS.get_name() not in ["macOS", "iOS"]: return
	if ProjectSettings.get_setting("apple_cloud/enabled", false) != true: return
	if ProjectSettings.get_setting("apple_cloud/container_id", "") != CONTAINER: return
	if not ClassDB.class_exists("SCDDAppleCloud"):
		var status := GDExtensionManager.load_extension(CONFIG)
		if status not in [GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED]: return
	if not ClassDB.class_exists("SCDDAppleCloud"): return
	var bridge: RefCounted = ClassDB.instantiate("SCDDAppleCloud")
	var staging := ProjectSettings.globalize_path(STAGING)
	# A terminated process cannot clean its own transport directory. Only this
	# process configures a new one below, so every existing one is abandoned.
	remove_stale_staging(staging)
	if bridge.call("configure", CONTAINER, staging) == OK:
		_native = bridge

func available() -> bool:
	return _native != null and _native.call("available") == true

func start_request(request: Dictionary) -> Error:
	if not available(): return ERR_UNAVAILABLE
	if not valid_request(request) or _requests.has(request.id): return ERR_INVALID_PARAMETER
	var error: Error = _native.call("start_request", request)
	if error == OK: _requests[request.id] = request.duplicate(true)
	return error

func drain_completions() -> Array[Dictionary]:
	var accepted: Array[Dictionary] = []
	if _native == null: return accepted
	var incoming: Variant = _native.call("drain_completions")
	if incoming is Array: _backlog.append_array(incoming)
	var batch := _backlog.slice(0, DRAIN_LIMIT)
	_backlog = _backlog.slice(batch.size())
	var earlier := _suspect
	_suspect = {}
	for item: Variant in batch:
		var completion := accept_completion(item)
		if not completion.is_empty(): accepted.append(completion)
	# Native finishes each request once. If its answer was malformed and no
	# valid answer followed by the next drain, settle it as an invalid failure
	# so the coordinator's lane is released instead of waiting forever.
	if _backlog.is_empty():
		for id: String in earlier:
			if not _requests.has(id) or _suspect.has(id): continue
			var request: Dictionary = _requests[id]
			_requests.erase(id)
			accepted.append({"id": id, "epoch": request.epoch, "op": request.op, "ok": false, "code": "invalid", "result": {}, "retry_after_ms": 0})
	else:
		_suspect.merge(earlier)
	return accepted

## Validate one native completion against its outstanding request. Anything
## malformed or mismatched is never delivered; it only marks that request.
func accept_completion(item: Variant) -> Dictionary:
	var id: Variant = item.get("id") if item is Dictionary else null
	var outstanding: bool = id is String and _requests.has(id)
	if not valid_completion(item):
		if outstanding: _suspect[id] = true
		return {}
	if item.op == "account_changed": return item
	if not outstanding: return {}
	var request: Dictionary = _requests[item.id]
	if request.epoch != item.epoch or request.op != item.op:
		_suspect[item.id] = true
		return {}
	_requests.erase(item.id)
	_suspect.erase(item.id)
	return item

func cancel_all() -> void:
	_requests.clear()
	_backlog.clear()
	_suspect.clear()
	if _native != null: _native.call("cancel_all")

## Remove abandoned transport directories directly under `root`. Only entries
## named as generated UUIDs are touched, and links are unlinked, never followed.
## A symlinked root is refused, matching the native transport's own rule.
static func remove_stale_staging(root: String) -> int:
	root = root.simplify_path()
	if root.is_empty() or not DirAccess.dir_exists_absolute(root): return 0
	var parent := DirAccess.open(root.get_base_dir())
	if parent == null or parent.is_link(root.get_file()): return 0
	var dir := DirAccess.open(root)
	if dir == null: return 0
	var removed := 0
	for name in dir.get_directories() + dir.get_files():
		if not _uuid_name(name): continue
		var path := root.path_join(name)
		if dir.is_link(name):
			if DirAccess.remove_absolute(path) == OK: removed += 1
		elif DirAccess.dir_exists_absolute(path):
			if _remove_tree(path) == OK: removed += 1
	return removed

static func _remove_tree(path: String) -> Error:
	var dir := DirAccess.open(path)
	if dir == null: return ERR_CANT_OPEN
	# Staged transport files can be dotfiles; listings skip them by default.
	dir.include_hidden = true
	for name in dir.get_files(): DirAccess.remove_absolute(path.path_join(name))
	for name in dir.get_directories():
		if dir.is_link(name): DirAccess.remove_absolute(path.path_join(name))
		else: _remove_tree(path.path_join(name))
	return DirAccess.remove_absolute(path)

static func _uuid_name(name: String) -> bool:
	if name.length() != 36: return false
	for i in 36:
		if i in [8, 13, 18, 23]:
			if name[i] != "-": return false
		elif not name[i] in "0123456789abcdefABCDEF": return false
	return true

static func valid_request(r: Variant) -> bool:
	if not r is Dictionary or not CloudSaveTypes.valid_id(r.get("id")) or not r.get("epoch") is int or r.epoch < 0 or r.get("op") not in OPS or not r.get("args") is Dictionary: return false
	var a: Dictionary = r.args
	match r.op:
		"account", "prepare_zone": return a.is_empty()
		"changes": return _archive(a.get("token")) and a.get("limit") is int and a.limit == 256
		"fetch_record": return CloudSaveTypes.valid_id(a.get("slot_id"))
		"download": return _remote(a.get("remote")) and a.get("max_bytes") is int and a.max_bytes == CloudSaveTypes.MAX_ASSET_BYTES
		"save": return CloudSaveTypes.valid_pending(a.get("pending")) and _archive(a.pending.baseline) and _metadata(a.get("metadata"))
	return false

static func _archive(v: Variant) -> bool:
	return v is PackedByteArray and v.size() <= 1048576

static func _metadata(v: Variant) -> bool:
	if not v is Dictionary or v.size() > 64 or not CloudSaveTypes.valid_metadata(v): return false
	for item: Variant in v.values():
		if item is float and not is_finite(item): return false
	return true

static func _remote(v: Variant) -> bool:
	return CloudSaveTypes.valid_remote(v) and _archive(v.system_fields) and _metadata(v.metadata)

static func valid_completion(c: Variant) -> bool:
	if not c is Dictionary or not c.get("id") is String or not c.get("epoch") is int or c.epoch < 0 or not c.get("ok") is bool or not c.get("code") is String or not c.get("result") is Dictionary or not c.get("retry_after_ms") is int or c.retry_after_ms < 0: return false
	if c.get("op") == "account_changed": return c.id.is_empty() and c.ok and c.code.is_empty() and c.result.is_empty() and c.retry_after_ms == 0
	if not CloudSaveTypes.valid_id(c.id) or c.get("op") not in OPS: return false
	if not c.ok:
		return c.code in CODES and (c.code != "conflict" or _remote(c.result.get("remote")))
	if not c.code.is_empty(): return false
	var r: Dictionary = c.result
	match c.op:
		"account": return CloudSaveTypes.valid_hash(r.get("owner"))
		"prepare_zone": return r.is_empty()
		"save": return CloudSaveTypes.valid_id(r.get("commit_id")) and r.get("change_tag") is String and r.change_tag.to_utf8_buffer().size() <= 128 and _archive(r.get("system_fields"))
		"fetch_record": return r.get("remote") is Dictionary and (r.remote.is_empty() or _remote(r.remote))
		"download":
			if not r.get("downloaded") is Dictionary or r.downloaded.size() > 2: return false
			for key: Variant in r.downloaded:
				if key not in ["continuation", "manual"] or not r.downloaded[key] is String or r.downloaded[key].is_empty() or r.downloaded[key].length() > 4096: return false
			return true
		"changes":
			if not r.get("records") is Array or not r.get("deleted_ids") is Array or r.records.size() + r.deleted_ids.size() > 256 or not _archive(r.get("token")) or not r.get("more") is bool: return false
			var ids: Dictionary = {}
			for item: Variant in r.records:
				if not _remote(item) or ids.has(item.slot_id): return false
				ids[item.slot_id] = true
			for id: Variant in r.deleted_ids:
				if not CloudSaveTypes.valid_id(id) or ids.has(id): return false
				ids[id] = true
			return true
	return false
