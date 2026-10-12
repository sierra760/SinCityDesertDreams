# SPDX-License-Identifier: GPL-3.0-or-later
class_name ExploreModProgress
extends RefCounted
const MAX_MOD_BYTES := 65536
const MAX_TOTAL_BYTES := 524288
const MAX_MODS := 64
var _mods: Dictionary = {}

# Check before copying/serializing: the depth bound also rejects reference cycles.
static func _valid(value: Variant, depth: int = 0) -> bool:
	if depth > 8: return false
	if value == null or value is bool or value is int: return true
	if value is float: return is_finite(value)
	if value is String: return value.to_utf8_buffer().size() <= 4096
	if value is Array:
		if value.size() > 1024: return false
		for item in value:
			if not _valid(item,depth+1): return false
		return true
	if value is Dictionary:
		if value.size() > 1024: return false
		for key in value:
			if not key is String or not _valid(key,depth+1) or not _valid(value[key],depth+1): return false
		return true
	return false

static func _valid_owner(owner: String) -> bool:
	if owner.is_empty() or owner.length() > 64: return false
	for c in owner:
		if not c in "abcdefghijklmnopqrstuvwxyz0123456789._": return false
	return true

static func _valid_record(record: Variant) -> bool:
	if not record is Dictionary: return false
	var version: Variant = record.get("state_version")
	if not (version is int or version is float): return false
	if not is_finite(float(version)) or version < 1 or float(version) != floor(float(version)) or (version is float and version >= 9223372036854775808.0): return false
	var pack: Variant = record.get("pack_version")
	if not pack is String or pack.is_empty() or not _valid(pack): return false
	var data: Variant = record.get("data")
	return data is Dictionary and _valid(data) and JSON.stringify(data).to_utf8_buffer().size() <= MAX_MOD_BYTES

static func _document(mods: Dictionary) -> Dictionary:
	return {} if mods.is_empty() else {"format_version":1,"mods":mods}

## Malformed optional progress is recoverable and never invalidates a city.
func restore(value: Variant) -> Dictionary:
	_mods.clear()
	if value is Dictionary and value.is_empty(): return {"ok":true,"code":"ok","notices":[]}
	if not value is Dictionary or value.get("format_version") != 1 or not value.get("mods") is Dictionary or value.mods.size() > MAX_MODS:
		return _invalid_restore()
	var next: Dictionary = {}
	for owner in value.mods:
		if not owner is String or not _valid_owner(owner) or not _valid_record(value.mods[owner]): return _invalid_restore()
		var record: Dictionary = value.mods[owner]
		next[owner] = {"state_version":int(record.state_version),"pack_version":record.pack_version,"data":record.data.duplicate(true)}
	if JSON.stringify(_document(next)).to_utf8_buffer().size() > MAX_TOTAL_BYTES: return _invalid_restore()
	_mods = next
	return {"ok":true,"code":"ok","notices":[]}

static func _invalid_restore() -> Dictionary:
	return {"ok":false,"code":"invalid_progress","notices":["Invalid Explore mod progress was ignored."]}

func snapshot() -> Dictionary:
	return _document(_mods.duplicate(true))

func get_state(owner: String, state_version: int) -> Dictionary:
	if not _mods.has(owner): return {"ok":true,"code":"ok","data":{}}
	if _mods[owner].state_version != state_version: return {"ok":false,"code":"state_version_mismatch","data":{}}
	return {"ok":true,"code":"ok","data":_mods[owner].data.duplicate(true)}

func commit(owner: String, state_version: int, pack_version: String, writes: Dictionary) -> Dictionary:
	if not _valid_owner(owner) or state_version < 1 or pack_version.is_empty() or not _valid(pack_version) or not _valid(writes): return {"ok":false,"code":"invalid_progress"}
	var state := get_state(owner,state_version)
	if not state.ok: return state
	var data: Dictionary = state.data
	data.merge(writes.duplicate(true),true)
	if not _valid(data) or JSON.stringify(data).to_utf8_buffer().size() > MAX_MOD_BYTES: return {"ok":false,"code":"quota_exceeded"}
	var next := _mods.duplicate(true)
	next[owner] = {"state_version":state_version,"pack_version":pack_version,"data":data}
	if next.size() > MAX_MODS or JSON.stringify(_document(next)).to_utf8_buffer().size() > MAX_TOTAL_BYTES: return {"ok":false,"code":"quota_exceeded"}
	_mods = next
	return {"ok":true,"code":"ok"}

func reset(owner: String) -> void: _mods.erase(owner)
