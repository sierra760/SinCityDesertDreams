class_name ExploreModPack
extends RefCounted
const Limits = preload("res://scripts/exploration/mods/explore_mod_limits.gd")
const Manifest = preload("res://scripts/exploration/mods/explore_mod_manifest.gd")

static func read(path: String) -> Dictionary:
	var parent := DirAccess.open(path.get_base_dir())
	if parent == null or parent.is_link(path.get_file()):
		return _bad("path")
	var files := {}
	var error := _collect(path, "", files, [0])
	if not error.is_empty():
		return _bad(error)
	return _snapshot(files)

static func _collect(root: String, relative: String, files: Dictionary, visited: Array) -> String:
	var dir := DirAccess.open(root.path_join(relative))
	if dir == null:
		return "folder"
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		visited[0] += 1
		if visited[0] > 64:
			return "files"
		var local := name if relative.is_empty() else relative.path_join(name)
		if dir.is_link(name) or not Manifest.safe_path(local):
			return "path"
		if dir.current_is_dir():
			# Empty directories are harmless, but bound traversal independently.
			if local.split("/").size() > 8:
				return "depth"
			var error := _collect(root, local, files, visited)
			if not error.is_empty():
				return error
		else:
			var error := _add(files, local, root.path_join(local))
			if not error.is_empty():
				return error
		name = dir.get_next()
	return ""

static func _add(files: Dictionary, name: String, path: String) -> String:
	if files.size() >= Limits.PACK_FILES or not _type_ok(name):
		return "files"
	for existing in files:
		if existing.to_lower() == name.to_lower():
			return "duplicate_path"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "file"
	var limit: int = Limits.MANIFEST_BYTES if name == "manifest.json" else Limits.FILE_BYTES
	if f.get_length() > limit:
		return "file_size"
	files[name] = f.get_buffer(f.get_length())
	return ""

static func _type_ok(name: String) -> bool:
	return Manifest.safe_path(name) and (name.ends_with(".lua") or name.ends_with(".json"))

static func _snapshot(files: Dictionary) -> Dictionary:
	if not files.has("manifest.json"):
		return _bad("manifest_missing")
	var total := 0
	for name in files:
		total += files[name].size()
	if total > Limits.PACK_BYTES:
		return _bad("pack_size")
	if not _valid_utf8(files["manifest.json"]):
		return _bad("source_encoding")
	var validated := Manifest.validate(JSON.parse_string(files["manifest.json"].get_string_from_utf8()))
	if not validated.ok:
		return validated
	if not files.has(validated.manifest.entry):
		return _bad("entry_missing")
	var sources := {}
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var names: Array = files.keys()
	names.sort()
	for name in names:
		var bytes: PackedByteArray = files[name]
		if not _valid_utf8(bytes):
			return _bad("source_encoding")
		var source := bytes.get_string_from_utf8()
		if name.ends_with(".json"):
			var json := JSON.new()
			if json.parse(source) != OK or not _json_depth(json.data, 0):
				return _bad("json")
		hash.update(String(name).to_utf8_buffer())
		hash.update(PackedByteArray([0]))
		hash.update(bytes)
		hash.update(PackedByteArray([0]))
		if name != "manifest.json":
			sources[name] = source
	sources.make_read_only()
	var snapshot := {"ok":true, "code":"", "manifest":validated.manifest, "sources":sources, "content_hash":hash.finish().hex_encode()}
	snapshot.make_read_only()
	return snapshot

# Validate bytes before Godot conversion (which otherwise emits diagnostics).
static func _valid_utf8(bytes: PackedByteArray) -> bool:
	var index := 0
	while index < bytes.size():
		var lead := int(bytes[index])
		if lead == 0:
			return false
		if lead < 128:
			index += 1
			continue
		var width := 2 if lead >= 0xc2 and lead <= 0xdf else (3 if lead >= 0xe0 and lead <= 0xef else (4 if lead >= 0xf0 and lead <= 0xf4 else 0))
		if width == 0 or index + width > bytes.size():
			return false
		for offset in range(1, width):
			if bytes[index + offset] < 0x80 or bytes[index + offset] > 0xbf:
				return false
		var second := int(bytes[index + 1])
		if (lead == 0xe0 and second < 0xa0) or (lead == 0xed and second >= 0xa0) or (lead == 0xf0 and second < 0x90) or (lead == 0xf4 and second >= 0x90):
			return false
		index += width
	return true

static func _json_depth(value: Variant, depth: int) -> bool:
	if value is Dictionary or value is Array:
		if depth >= Limits.JSON_DEPTH:
			return false
		var items: Array = value.values() if value is Dictionary else value
		for item in items:
			if not _json_depth(item, depth + 1):
				return false
	return true

static func import_zip(path: String, destination: String) -> Dictionary:
	# Validate central directory before ZIPReader can collapse duplicate names or
	# lose Unix file type metadata. No filesystem writes precede validation.
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > Limits.PACK_BYTES * 2:
		return _bad("archive_size")
	var bytes := f.get_buffer(f.get_length())
	var end := bytes.size() - 22
	while end >= maxi(0, bytes.size() - 65557) and bytes.decode_u32(end) != 0x06054b50:
		end -= 1
	if end < 0 or end < maxi(0, bytes.size() - 65557):
		return _bad("archive")
	if bytes.decode_u16(end + 4) != 0 or bytes.decode_u16(end + 6) != 0:
		return _bad("archive")
	if end + 22 + bytes.decode_u16(end + 20) != bytes.size():
		return _bad("archive")
	var count := bytes.decode_u16(end + 10)
	if count > Limits.PACK_FILES or bytes.decode_u16(end + 8) != count:
		return _bad("files")
	var offset := int(bytes.decode_u32(end + 16))
	# minizip adjusts raw offsets by EOCD - (directory offset + size).
	# V1 accepts only an unambiguous, non-prefixed complete directory.
	if offset + int(bytes.decode_u32(end + 12)) != end:
		return _bad("archive_directory")
	var names := {}
	var total := 0
	for i in count:
		if offset + 46 > end or bytes.decode_u32(offset) != 0x02014b50:
			return _bad("archive")
		var length := bytes.decode_u16(offset + 28)
		var next := offset + 46 + length + bytes.decode_u16(offset + 30) + bytes.decode_u16(offset + 32)
		if next > end:
			return _bad("archive")
		var name_bytes := bytes.slice(offset + 46, offset + 46 + length)
		if not _valid_utf8(name_bytes):
			return _bad("archive_path")
		var name := name_bytes.get_string_from_utf8()
		var mode := bytes.decode_u32(offset + 38) >> 16
		if mode & 0xf000 == 0xa000 or not _type_ok(name) or names.has(name.to_lower()) or bytes.decode_u16(offset + 8) & 1:
			return _bad("archive_path")
		var size := bytes.decode_u32(offset + 24)
		if size > (Limits.MANIFEST_BYTES if name == "manifest.json" else Limits.FILE_BYTES):
			return _bad("file_size")
		total += size
		if total > Limits.PACK_BYTES:
			return _bad("pack_size")
		names[name.to_lower()] = {"name":name, "size":size}
		offset = next
	if offset != end:
		return _bad("archive_directory")
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return _bad("archive")
	var files := {}
	for record in names.values():
		var data := zip.read_file(record.name)
		if data.size() != record.size:
			zip.close()
			return _bad("archive_size")
		files[record.name] = data
	zip.close()
	var snapshot := _snapshot(files)
	if not snapshot.ok:
		return snapshot
	# Existing installs are never overwritten. Registry selects a fresh destination.
	if DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination):
		return _bad("destination_exists")
	var stage := destination + ".staging-" + str(Time.get_ticks_usec())
	if DirAccess.make_dir_recursive_absolute(stage) != OK:
		return _bad("install")
	for name in files:
		var target := stage.path_join(name)
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK:
			_remove(stage)
			return _bad("install")
		var output := FileAccess.open(target, FileAccess.WRITE)
		if output == null:
			_remove(stage)
			return _bad("install")
		output.store_buffer(files[name])
		var error := output.get_error()
		output.close()
		if error != OK:
			_remove(stage)
			return _bad("install")
	if DirAccess.rename_absolute(stage, destination) != OK:
		_remove(stage)
		return _bad("install")
	return snapshot

static func _remove(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in dir.get_directories():
		_remove(path.path_join(name))
	DirAccess.remove_absolute(path)

static func _bad(code: String) -> Dictionary:
	return {"ok":false, "code":code, "manifest":{}, "sources":{}, "content_hash":""}
