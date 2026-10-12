# SPDX-License-Identifier: GPL-3.0-or-later
class_name ExploreModObjectives
extends RefCounted
var _owned: Dictionary = {}

func set_objective(owner: String, key: String, text: String, status: String) -> Dictionary:
	if key.is_empty() or text.to_utf8_buffer().size() > 4096 or status not in ["active","completed","failed"]: return {"code":"invalid_argument"}
	var entries: Dictionary = _owned.get(owner,{})
	if entries.size() >= 8 and not entries.has(key): return {"code":"quota_exceeded"}
	entries[key] = {"owner":owner,"key":key,"text":text,"status":status}
	_owned[owner] = entries
	return {"code":"ok"}

func list_owned(owner: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _owned.get(owner,{}).values(): result.append(entry.duplicate(true))
	return result

func remove(owner: String, key: String) -> Dictionary:
	if _owned.has(owner): _owned[owner].erase(key)
	return {"code":"ok"}

func journal() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for owner: String in _owned: result.append_array(list_owned(owner))
	return result

func clear_owner(owner: String) -> void: _owned.erase(owner)
