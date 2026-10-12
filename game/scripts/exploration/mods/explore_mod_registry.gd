# SPDX-License-Identifier: GPL-3.0-or-later
## Installed immutable versions and explicit local-player configuration.
class_name ExploreModRegistry
extends RefCounted
signal changed
var install_directory := "user://explore_mods"
var diagnostics: Array[Dictionary] = []
var service: ExploreModService
var _entries: Array[Dictionary] = []
var _enabled: Array[String] = []
var _serial := 0

func runtime_label() -> String:
	if not ExploreLuaBridge.supported_platform(): return "Runtime unavailable on this platform. Source packs can still be imported and configured."
	if not ExploreLuaBridge.available(): return "Runtime unavailable: native library is missing. Source configuration is available."
	return "Lua runtime available • up to 8 enabled packs • changes start on Resume"

func set_preferences(ids: Array) -> void:
	_enabled = ViewPreferences.clean_mod_ids(ids)

func enabled_ids() -> Array[String]: return _enabled.duplicate()

func scan(directory: String) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var folder := DirAccess.open(directory)
	if folder != null:
		var names := folder.get_directories()
		names.sort()
		for name in names.slice(0,128):
			var path := directory.path_join(name)
			var snapshot := ExploreModPack.read(path)
			var item := snapshot.duplicate()
			item["path"] = path
			item["source_path"] = path
			candidates.append(item)
	# The version catalogue only points inside our installation root. It never
	# supplies script contents or enabling preferences.
	var catalog_path := install_directory.path_join("catalog.json")
	if FileAccess.file_exists(catalog_path) and FileAccess.get_file_as_bytes(catalog_path).size() <= 65536:
		var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
		if catalog is Array:
			for entry: Variant in catalog.slice(0,128):
				if not entry is Dictionary or not entry.get("version",null) is String: continue
				var version: String = entry.version
				if not ExploreModManifest.safe_path(version) or version.contains("/"): continue
				var path := install_directory.path_join(version)
				var snapshot := ExploreModPack.read(path)
				var item := snapshot.duplicate()
				item["path"] = path
				item["source_path"] = String(entry.get("source_path",path))
				# An installed update explicitly supersedes its bundled source.
				if snapshot.ok:
					candidates = candidates.filter(func(old: Dictionary) -> bool: return not (old.get("ok",false) and old.manifest.id == snapshot.manifest.id and old.path == item.source_path))
				candidates.append(item)
	_entries = ExploreModManifest.resolve_candidates(candidates)
	for entry in _entries:
		if not entry.ok: _note(String(entry.get("path","")),String(entry.code))
	return entries()

func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _entries:
		var row := {"ok":entry.ok,"code":entry.get("code",""),"path":entry.path,"source_path":entry.source_path,"manifest":entry.get("manifest",{}).duplicate(),"enabled":false}
		if entry.ok: row.enabled = entry.manifest.id in _enabled
		result.append(row)
	return result

func _find(id: String) -> Dictionary:
	for entry in _entries:
		if entry.get("ok",false) and entry.manifest.id == id: return entry
	return {}

func set_enabled(id: String, enabled: bool) -> Dictionary:
	if _find(id).is_empty(): return _bad(id,"missing_or_duplicate")
	if enabled and not id in _enabled:
		if _enabled.size() >= 8: return _bad(id,"session_limit")
		_enabled.append(id)
	elif not enabled:
		_enabled.erase(id)
		if service != null: service.disable(id)
	changed.emit()
	return {"ok":true,"code":"pending_resume"}

func active_packs() -> Array[Dictionary]:
	var packs: Array[Dictionary] = []
	for id in _enabled:
		var entry := _find(id)
		if not entry.is_empty(): packs.append(entry.snapshot if entry.has("snapshot") else _immutable(entry))
	return packs

func _immutable(entry: Dictionary) -> Dictionary:
	var snapshot := {"ok":true,"code":"","manifest":entry.manifest,"sources":entry.sources,"content_hash":entry.content_hash}
	snapshot.make_read_only()
	return snapshot

## Source validation uses one freed owner slot; other VMs remain untouched.
## Candidate validation does not dispatch on_start.
func _validate_source(snapshot: Dictionary) -> Dictionary:
	if not ExploreLuaBridge.available(): return {"ok":true,"code":"source_only"}
	if service != null and service._active:
		if not service.controller.is_suspended(): return {"ok":false,"code":"pause_required"}
		var owner: String = snapshot.manifest.id
		if service.runtime.has_owner(owner): service.disable(owner)
		if service.runtime.metrics().sessions >= 8: return {"ok":false,"code":"session_limit"}
	var vm := ExploreLuaBridge.new()
	var modules := {}
	for name: String in snapshot.sources:
		if name.ends_with(".lua"): modules[name] = snapshot.sources[name]
	var result := vm.start(snapshot.sources[snapshot.manifest.entry],modules,{"owner":String(snapshot.manifest.id),"generation":0,"progress":{},"queries":{},"delta":0.0},0)
	vm.close()
	return {"ok":result.ok,"code":String(result.get("fault","")),"diagnostic":ExploreLuaBridge.diagnostic_text(result.get("diagnostic",""))}

func import_pack(path: String) -> Dictionary:
	if _entries.size() >= 128: return _bad("","installed_limit")
	DirAccess.make_dir_recursive_absolute(install_directory)
	var destination := _destination()
	var is_archive := path.to_lower().get_extension() in ["scddmod","zip"]
	var loaded: Dictionary
	if is_archive:
		loaded = ExploreModPack.import_zip(path,destination)
	else:
		loaded = ExploreModPack.read(path)
	if not loaded.ok: return _bad("",loaded.code)
	var id: String = loaded.manifest.id
	if not _find(id).is_empty(): return _bad(id,"duplicate_id")
	if not is_archive:
		loaded = _publish(loaded,destination)
		if not loaded.ok: return _bad(id,loaded.code)
	var entry := loaded.duplicate()
	entry["snapshot"] = loaded
	entry["path"] = destination
	entry["source_path"] = path
	if is_archive:
		var working := _destination()+"-source"
		var copied := _publish(loaded,working)
		if not copied.ok: return _bad(id,copied.code)
		entry["source_path"] = working
	_entries.append(entry)
	if not _save_catalog():
		_entries.erase(entry)
		return _bad(id,"catalog_publish")
	# Imported packs always require a new explicit Enable, even if a stale
	# preference for this missing identity existed.
	_enabled.erase(id)
	changed.emit()
	return {"ok":true,"code":"imported_disabled","path":destination}

func reload(id: String, suspended: bool) -> Dictionary:
	if not suspended: return _bad(id,"pause_required")
	var old := _find(id)
	if old.is_empty(): return _bad(id,"missing_or_duplicate")
	var candidate := ExploreModPack.read(old.source_path)
	if not candidate.ok: return _bad(id,candidate.code)
	if candidate.manifest.id != id: return _bad(id,"identity_changed")
	var validation := _validate_source(candidate)
	if not validation.ok: return _reload_failed(id,validation.code,String(validation.get("diagnostic","")))
	var destination := _destination()
	candidate = _publish(candidate,destination)
	if not candidate.ok: return _reload_failed(id,candidate.code)
	var entry := candidate.duplicate()
	entry["snapshot"] = candidate
	entry["path"] = destination
	entry["source_path"] = old.source_path
	var index := _entries.find(old)
	_entries[index] = entry
	if not _save_catalog():
		_entries[index] = old
		return _reload_failed(id,"catalog_publish")
	changed.emit()
	return {"ok":true,"code":"reloaded_pending_resume"}

func _reload_failed(id: String, code: String, diagnostic: String = "") -> Dictionary:
	# Validation may have stopped the selected owner to free its native slot.
	# Reconfigure from the unchanged immutable entry: only that missing owner
	# is staged for explicit Resume; unchanged/faulted owners retain their state.
	changed.emit()
	return _bad(id,code,diagnostic)

func _destination() -> String:
	_serial += 1
	return install_directory.path_join("version-%d-%d" % [Time.get_ticks_usec(),_serial])

func _publish(snapshot: Dictionary, destination: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(install_directory)
	var temporary := destination+".zip"
	var writer := ZIPPacker.new()
	if writer.open(temporary) != OK: return {"ok":false,"code":"write"}
	var files: Dictionary = snapshot.sources.duplicate()
	files["manifest.json"] = JSON.stringify(snapshot.manifest)
	for name: String in files:
		writer.start_file(name)
		writer.write_file(String(files[name]).to_utf8_buffer())
		writer.close_file()
	writer.close()
	var result := ExploreModPack.import_zip(temporary,destination)
	DirAccess.remove_absolute(temporary)
	return result

func _save_catalog() -> bool:
	var catalog: Array = []
	for entry in _entries:
		if entry.ok and String(entry.path).begins_with(install_directory+"/"):
			catalog.append({"version":String(entry.path).get_file(),"source_path":entry.source_path})
	var path := install_directory.path_join("catalog.json")
	var f := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if f == null:
		_note("","catalog_write")
		return false
	f.store_string(JSON.stringify(catalog)); f.close()
	if DirAccess.rename_absolute(path+".tmp",path) != OK:
		_note("","catalog_publish")
		DirAccess.remove_absolute(path+".tmp")
		return false
	return true

func diagnostic_text() -> String:
	var lines: Array[String] = [runtime_label(),"Explore API 1"]
	for entry in _entries:
		if entry.ok: lines.append(String(entry.manifest.id)+" "+String(entry.manifest.version)+" state "+str(entry.manifest.state_version))
	for entry in diagnostics: lines.append(String(entry.owner)+": "+ExploreLuaBridge.diagnostic_summary(entry))
	if service != null:
		for entry in service.runtime.diagnostics.slice(-24): lines.append(String(entry.owner)+": "+ExploreLuaBridge.diagnostic_summary(entry))
	return ExploreLuaBridge.bounded_text("\n".join(lines),16384)

func _note(owner: String, reason: String, diagnostic: String = "") -> void:
	if diagnostics.size() >= 128: diagnostics.pop_front()
	diagnostics.append({"owner":ExploreLuaBridge.diagnostic_text(owner).left(64),"reason":reason.left(128),"diagnostic":ExploreLuaBridge.diagnostic_text(diagnostic),"time_usec":Time.get_ticks_usec()})
func _bad(owner: String, code: String, diagnostic: String = "") -> Dictionary:
	_note(owner,code,diagnostic)
	return {"ok":false,"code":code,"diagnostic":ExploreLuaBridge.diagnostic_text(diagnostic)}
