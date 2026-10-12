class_name ExploreModManifest
extends RefCounted

static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _bad("manifest_type")
	for key in ["id", "name", "version", "entry"]:
		if not value.get(key) is String or value[key].is_empty():
			return _bad("manifest_field")
	var id: String = value.id
	if id.length() > 64:
		return _bad("identity")
	for c in id:
		if not c in "abcdefghijklmnopqrstuvwxyz0123456789._":
			return _bad("identity")
	for key in ["api_version", "state_version", "priority"]:
		var n: Variant = value.get(key, 0 if key == "priority" else null)
		if not (n is int or n is float) or not is_finite(float(n)) or float(n) != floor(float(n)):
			return _bad("manifest_integer")
	if value.api_version != 1:
		return _bad("api_version")
	if (value.state_version is float and value.state_version >= 9223372036854775808.0) or value.state_version < 1 or value.get("priority", 0) < 0 or value.get("priority", 0) > 100:
		return _bad("manifest_range")
	var version := RegEx.new()
	version.compile("^[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9A-Za-z.-]+)?(\\+[0-9A-Za-z.-]+)?$")
	if version.search(value.version) == null:
		return _bad("version")
	if not safe_path(value.entry) or not value.entry.ends_with(".lua"):
		return _bad("entry")
	if value.has("description") and not value.description is String:
		return _bad("manifest_field")
	var manifest: Dictionary = {}
	for key in ["id", "name", "version", "entry", "description"]:
		if value.has(key):
			manifest[key] = value[key]
	manifest.priority = int(value.get("priority", 0))
	manifest.api_version = int(value.api_version)
	manifest.state_version = int(value.state_version)
	manifest.make_read_only()
	return {"ok":true, "code":"", "manifest":manifest}

static func safe_path(path: String) -> bool:
	if path.is_empty() or path.begins_with("/") or path.contains("\\") or path.contains(":") or path.to_utf8_buffer().has(0):
		return false
	for part in path.split("/"):
		if part in ["", ".", ".."]:
			return false
	return true

static func resolve_candidates(packs: Array[Dictionary]) -> Array[Dictionary]:
	var counts := {}
	for pack in packs:
		if pack.get("ok", false):
			var id: String = pack.manifest.id.to_lower()
			counts[id] = counts.get(id, 0) + 1
	var result: Array[Dictionary] = []
	for pack in packs:
		var item: Dictionary = pack.duplicate()
		if item.get("ok", false) and counts[item.manifest.id.to_lower()] > 1:
			item.ok = false
			item.code = "duplicate_id"
		result.append(item)
	return result

static func _bad(code: String) -> Dictionary:
	return {"ok":false, "code":code, "manifest":{}}
