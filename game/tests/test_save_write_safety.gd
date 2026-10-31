# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const DIR := "user://test_save_write_safety"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	_remove_tree(DIR)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child in directory.get_directories():
		_remove_tree(path.path_join(child))
	for child in directory.get_files():
		DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)


func test_overwrite_publishes_complete_new_file_without_mutating_open_reader() -> void:
	var path := DIR.path_join("overwrite.sc2d")
	var city := City.new()
	city.name = "Original committed city"
	check_eq(SaveFormat.save(path, city), OK)
	var original := FileAccess.get_file_as_bytes(path)
	var reader := FileAccess.open(path, FileAccess.READ)
	check(reader != null)
	city.name = "Replacement city"
	var saved := SaveFormat.save(path, city, {"marker": 42})
	# A reader already holding the committed file must never observe truncation
	# or replacement bytes; the new document is published at the path separately.
	check_eq(reader.get_buffer(original.size()), original, "previously committed bytes remain intact")
	reader.close()
	if OS.has_feature("windows"):
		# Windows cannot replace a file that another handle holds open, so the
		# save fails and leaves the committed city as it was.
		check_ne(saved, OK, "an open file cannot be replaced on Windows")
		check(FileAccess.get_file_as_bytes(path) == original, "the committed city is untouched")
	else:
		check_eq(saved, OK)
		var loaded := SaveFormat.load(path)
		check(loaded["ok"])
		check_eq(loaded["city"].name, "Replacement city")
		check_eq(int(loaded["snapshot"]["marker"]), 42)
	check_eq(_staging_folders(DIR).size(), 0, "staging cleaned up")


func test_unwritable_parent_preserves_existing_save() -> void:
	if not (OS.has_feature("macos") or OS.has_feature("linux")):
		return
	var folder := DIR.path_join("locked")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("city.sc2d")
	var city := City.new()
	city.name = "Keep this city"
	check_eq(SaveFormat.save(path, city), OK)
	var original := FileAccess.get_file_as_bytes(path)
	var absolute := ProjectSettings.globalize_path(folder)
	check_eq(OS.execute("/bin/chmod", ["500", absolute]), 0)
	city.name = "Must not be committed"
	var result := SaveFormat.save(path, city)
	# Restore before assertions and cleanup, even when the save under test fails.
	check_eq(OS.execute("/bin/chmod", ["700", absolute]), 0)
	check_ne(result, OK, "cannot stage replacement in unwritable parent")
	check_eq(FileAccess.get_file_as_bytes(path), original, "failed save preserves previous bytes")
	check_eq(DirAccess.open(folder).get_files().size(), 1)
	check_eq(DirAccess.open(folder).get_directories().size(), 0)


func test_directory_target_and_neighbor_files_are_preserved() -> void:
	var path := DIR.path_join("directory.sc2d")
	DirAccess.make_dir_recursive_absolute(path)
	var sentinel := path.path_join("keep.txt")
	var file := FileAccess.open(sentinel, FileAccess.WRITE)
	file.store_string("keep")
	file.close()
	check_ne(SaveFormat.save(path, City.new()), OK)
	check_eq(FileAccess.get_file_as_string(sentinel), "keep")
	check_eq(DirAccess.open(path).get_files().size(), 1)


func test_neighbor_backup_and_temporary_files_are_not_overwritten() -> void:
	var path := DIR.path_join("neighbors.sc2d")
	for suffix in [".tmp", ".bak", ".saving"]:
		var file := FileAccess.open(path + suffix, FileAccess.WRITE)
		file.store_string("unrelated " + suffix)
		file.close()
	check_eq(SaveFormat.save(path, City.new()), OK)
	for suffix in [".tmp", ".bak", ".saving"]:
		check_eq(FileAccess.get_file_as_string(path + suffix), "unrelated " + suffix)


func _staged_document(folder: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("document"), FileAccess.WRITE)
	file.store_string(contents)
	file.close()


func test_backup_strategy_replaces_and_cleans_recovery_copy() -> void:
	var target := DIR.path_join("backup-success.sc2d")
	check_eq(SaveFormat.save(target, City.new()), OK)
	var staged := DIR.path_join("backup-success-stage")
	_staged_document(staged, "complete replacement")
	check_eq(SaveFormat._publish_staged_save(staged, ProjectSettings.globalize_path(target), true), OK)
	check_eq(FileAccess.get_file_as_string(target), "complete replacement")
	check(not DirAccess.dir_exists_absolute(staged), "successful backup strategy cleans staging")


func test_backup_strategy_failed_publication_keeps_previous_city() -> void:
	var target := DIR.path_join("backup-failure.sc2d")
	check_eq(SaveFormat.save(target, City.new()), OK)
	var original := FileAccess.get_file_as_bytes(target)
	var staged := DIR.path_join("backup-failure-stage")
	DirAccess.make_dir_recursive_absolute(staged)
	# Missing staged document makes actual rename fail after backup preparation.
	# Windows removes the destination before finding that out and the recovery
	# copy puts it back; elsewhere the destination is never touched. Either way
	# the copy is no longer needed once the previous city is in place.
	check_ne(SaveFormat._publish_staged_save(staged, ProjectSettings.globalize_path(target), true), OK)
	check(FileAccess.get_file_as_bytes(target) == original, "failed publication keeps the previous city")
	check(not DirAccess.dir_exists_absolute(staged), "redundant recovery copy cleaned up")


## A staging folder as an interrupted save leaves it: the recovery copy of
## previous, an unpublished document, a marker naming target, and nothing at
## the target's path.
func _interrupted_save(folder: String, name: String, target: String, previous: City) -> String:
	var staging := folder.path_join(SaveFormat.STAGING_PREFIX + name)
	_staged_document(staging, "unpublished new bytes")
	check_eq(SaveFormat.save(staging.path_join("previous.sc2d"), previous), OK)
	var marker := FileAccess.open(staging.path_join(SaveFormat.STAGING_TARGET), FileAccess.WRITE)
	marker.store_string(target)
	marker.close()
	return staging


func _staging_folders(folder: String) -> PackedStringArray:
	var directory := DirAccess.open(folder)
	if directory == null:
		return PackedStringArray()
	directory.include_hidden = true
	var found := PackedStringArray()
	for name in directory.get_directories():
		if name.begins_with(SaveFormat.STAGING_PREFIX):
			found.append(name)
	return found


func test_listing_restores_a_city_left_by_an_interrupted_save() -> void:
	var folder := DIR.path_join("interrupted-list")
	DirAccess.make_dir_recursive_absolute(folder)
	var city := City.new()
	city.name = "Recovered city"
	_interrupted_save(folder, "list", "recovered.sc2d", city)
	var names := []
	for entry in SaveFormat.list_saves(folder):
		names.append(entry["path"].get_file())
	check_eq(names, ["recovered.sc2d"], "the interrupted city is listed again")
	check_eq(SaveFormat.load(folder.path_join("recovered.sc2d"))["city"].name, "Recovered city")
	check_eq(_staging_folders(folder).size(), 0, "recovery removes the staging folder")
	_remove_tree(folder)


func test_loading_a_missing_path_restores_its_interrupted_save() -> void:
	var folder := DIR.path_join("interrupted-load")
	DirAccess.make_dir_recursive_absolute(folder)
	var city := City.new()
	city.name = "Opened again"
	_interrupted_save(folder, "load", "opened.sc2d", city)
	var loaded := SaveFormat.load(folder.path_join("opened.sc2d"))
	check(loaded["ok"], "the missing city loads from its recovery copy")
	if loaded["ok"]:
		check_eq(loaded["city"].name, "Opened again")
	_remove_tree(folder)


func test_recovery_leaves_existing_saves_and_foreign_markers_alone() -> void:
	var folder := DIR.path_join("interrupted-guarded")
	DirAccess.make_dir_recursive_absolute(folder)
	var current := City.new()
	current.name = "Published meanwhile"
	check_eq(SaveFormat.save(folder.path_join("present.sc2d"), current), OK)
	var published := FileAccess.get_file_as_bytes(folder.path_join("present.sc2d"))
	var older := City.new()
	older.name = "Older copy"
	var kept := _interrupted_save(folder, "present", "present.sc2d", older)
	var escaping := _interrupted_save(folder, "escaping", "../escaped.sc2d", older)
	check_eq(SaveFormat.recover_interrupted_saves(folder), 0)
	check(FileAccess.get_file_as_bytes(folder.path_join("present.sc2d")) == published, "a published save is never replaced by a recovery copy")
	check(FileAccess.file_exists(kept.path_join("previous.sc2d")), "the recovery copy stays when its path is taken")
	check(not FileAccess.file_exists(DIR.path_join("escaped.sc2d")), "a marker cannot name a path outside the folder")
	check(FileAccess.file_exists(escaping.path_join("previous.sc2d")))
	for staging in [kept, escaping]:
		for name in ["document", "previous.sc2d", SaveFormat.STAGING_TARGET]:
			DirAccess.remove_absolute(staging.path_join(name))
		DirAccess.remove_absolute(staging)
	_remove_tree(folder)


func test_recovery_restores_missing_destination_and_cleans_stage() -> void:
	var target := DIR.path_join("restored.sc2d")
	var staged := DIR.path_join("restore-stage")
	_staged_document(staged, "incomplete new bytes")
	check_eq(SaveFormat.save(staged.path_join("previous.sc2d"), City.new()), OK)
	var original := FileAccess.get_file_as_bytes(staged.path_join("previous.sc2d"))
	check_eq(SaveFormat._restore_previous_save(staged, ProjectSettings.globalize_path(target)), OK)
	check(FileAccess.get_file_as_bytes(target) == original)
	check(not DirAccess.dir_exists_absolute(staged))


func test_failed_recovery_keeps_previous_copy_and_existing_target() -> void:
	var staged := DIR.path_join("failed-restore-stage")
	_staged_document(staged, "incomplete new bytes")
	check_eq(SaveFormat.save(staged.path_join("previous.sc2d"), City.new()), OK)
	var previous := FileAccess.get_file_as_bytes(staged.path_join("previous.sc2d"))
	var target := DIR.path_join("occupied-target")
	DirAccess.make_dir_recursive_absolute(target)
	check_ne(SaveFormat._restore_previous_save(staged, ProjectSettings.globalize_path(target)), OK)
	check(FileAccess.get_file_as_bytes(staged.path_join("previous.sc2d")) == previous,
		"failed restoration must leave previous city recoverable")
	check(DirAccess.dir_exists_absolute(target), "recovery must not remove an intervening destination")


func test_restore_rename_failure_keeps_recovery_bytes() -> void:
	var staged := DIR.path_join("rename-restore-stage")
	_staged_document(staged, "incomplete new bytes")
	check_eq(SaveFormat.save(staged.path_join("previous.sc2d"), City.new()), OK)
	var previous := FileAccess.get_file_as_bytes(staged.path_join("previous.sc2d"))
	var target := DIR.path_join("absent-parent/city.sc2d")
	check_ne(SaveFormat._restore_previous_save(staged, ProjectSettings.globalize_path(target)), OK)
	check(FileAccess.get_file_as_bytes(staged.path_join("previous.sc2d")) == previous,
		"OS rename failure preserves recovery bytes")
