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
	check_eq(SaveFormat.save(path, city, {"marker": 42}), OK)
	# A reader already holding the committed file must never observe truncation
	# or replacement bytes; the new document is published at the path separately.
	check_eq(reader.get_buffer(original.size()), original, "previously committed bytes remain intact")
	reader.close()
	var loaded := SaveFormat.load(path)
	check(loaded["ok"])
	check_eq(loaded["city"].name, "Replacement city")
	check_eq(int(loaded["snapshot"]["marker"]), 42)
	check_eq(DirAccess.open(DIR).get_directories().size(), 0, "successful staging cleaned up")


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


func test_backup_strategy_failed_publication_retains_verified_previous_copy() -> void:
	var target := DIR.path_join("backup-failure.sc2d")
	check_eq(SaveFormat.save(target, City.new()), OK)
	var original := FileAccess.get_file_as_bytes(target)
	var staged := DIR.path_join("backup-failure-stage")
	DirAccess.make_dir_recursive_absolute(staged)
	# Missing staged document makes actual rename fail after backup preparation.
	check_ne(SaveFormat._publish_staged_save(staged, ProjectSettings.globalize_path(target), true), OK)
	check(FileAccess.get_file_as_bytes(target) == original)
	check(FileAccess.file_exists(staged.path_join("previous.sc2d")), "failed publication retains recovery copy")
	if FileAccess.file_exists(staged.path_join("previous.sc2d")):
		check(FileAccess.get_file_as_bytes(staged.path_join("previous.sc2d")) == original,
			"recovery copy contains exact previous bytes")


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
