# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Playable copies of a city for sending to someone else, made from the open
## city or from a saved file. A copy is not the city's save file: making one
## leaves the save path, the unsaved-changes state and the simulation's random
## stream untouched.
class_name CityShare
extends RefCounted

const DIRECTORY := "user://shared-cities"
## The credit a city carries when no mayor name was chosen.
const DEFAULT_MAYOR := "Mayor"
## Older share copies beyond this many are removed after a new one is made.
const KEEP_COPIES := 5
static var _sequence := 0

static func _path(city_name: String, directory: String) -> String:
	_sequence += 1
	var name := SaveDialog.clean_name(city_name)
	if name.is_empty(): name = "City"
	var folder := "%d-%d" % [Time.get_ticks_usec(),_sequence]
	var path := directory.path_join(folder).path_join(name + ".sc2d")
	while FileAccess.file_exists(path):
		_sequence += 1
		folder = "%d-%d" % [Time.get_ticks_usec(),_sequence]
		path = directory.path_join(folder).path_join(name + ".sc2d")
	return path

static func create_current(city: City, snapshot: Dictionary, stage: String, generator: Dictionary, directory: String = DIRECTORY) -> Dictionary:
	if city == null: return _failure("Open a city before sharing it.")
	if FileAccess.file_exists(directory): return _failure("The share-copy folder is not available.")
	var path := _path(city.name,directory)
	var error := SaveFormat.save(path,city,snapshot,stage,generator)
	if error != OK: return _failure("The share copy couldn't be written. Check free space and try again.")
	_prune(directory,path)
	return _success(path,city.name,city.mayor)

static func copy_saved(source: String, directory: String = DIRECTORY) -> Dictionary:
	var loaded := SaveFormat.load(source)
	if not loaded.ok: return _failure(String(loaded.error))
	var city: City = loaded.city
	var path := _path(city.name,directory)
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if error == OK: error = DirAccess.copy_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(path))
	if error != OK: return _failure("The saved city couldn't be copied. Check free space and try again.")
	_prune(directory,path)
	return _success(path,city.name,city.mayor)

static func _success(path: String, city_name: String, mayor: String) -> Dictionary:
	# The default "Mayor" credit adds nothing; name only a chosen mayor.
	var visit := "Visit %s" % city_name if mayor.is_empty() or mayor == DEFAULT_MAYOR else "Visit %s, a city by %s," % [city_name,mayor]
	return {"ok":true,"path":path,"name":city_name,"mayor":mayor,
		"message":"%s in Sin City - Desert Dreams. Open the attached .sc2d file with Load City → Browse." % visit}


## Each share gets its own folder, so a copy a share sheet still holds is never
## overwritten. Keep only the newest few copies; remove older ones and their
## folders. Only share-copy files are removed; anything else stays.
static func _prune(directory: String, keep_path: String) -> void:
	var root := DirAccess.open(directory)
	if root == null: return
	var copies: Array[Dictionary] = []
	for folder in root.get_directories():
		var folder_path := directory.path_join(folder)
		var newest := 0
		var files := DirAccess.get_files_at(folder_path)
		for file in files:
			newest = maxi(newest,FileAccess.get_modified_time(folder_path.path_join(file)))
		copies.append({"folder":folder_path,"files":files,"time":newest})
	copies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.time) > int(b.time))
	var kept := 0
	for copy in copies:
		var folder_path: String = copy.folder
		if folder_path == keep_path.get_base_dir() or kept < KEEP_COPIES - 1:
			if folder_path != keep_path.get_base_dir(): kept += 1
			continue
		var removable := true
		for file: String in copy.files:
			if file.get_extension().to_lower() != SaveFormat.EXTENSION: removable = false
		if not removable: continue
		for file: String in copy.files: DirAccess.remove_absolute(ProjectSettings.globalize_path(folder_path.path_join(file)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder_path))

static func _failure(message: String) -> Dictionary:
	return {"ok":false,"error":message}
