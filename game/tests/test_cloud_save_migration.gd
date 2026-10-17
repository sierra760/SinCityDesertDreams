# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"
const Fake := preload("res://tests/helpers/fake_apple_cloud.gd")
var directory: String
var store: CloudSaveStore
var coordinator: CloudSaveCoordinator
var paths: Array[String] = []
func before_each() -> void:
	directory = "user://migration-tests/" + CloudSaveTypes.uuid()
	store = CloudSaveStore.new(directory)
	store.open_library("account-a")
	coordinator = CloudSaveCoordinator.new(store, Fake.new())
	coordinator._owner = "account-a"
	coordinator._initial_inventory_complete = true
func after_each() -> void:
	coordinator.shutdown()
	for path in paths: DirAccess.remove_absolute(path)
	paths.clear()
func saved(label: String, funds: int = 100) -> String:
	var path := CityFileFlow.save_path_for("migration-" + CloudSaveTypes.uuid() + label)
	var city := flat_city()
	city.name = "Equal title"
	city.funds = funds
	check_eq(SaveFormat.save(path, city), OK)
	paths.append(path)
	return path
func headers(path: String) -> Array[Dictionary]:
	return [SaveFormat.read_header(path)]
func remote(path: String) -> Dictionary:
	return {"slot_id":"remote", "commit_id":"remote-commit", "change_tag":"tag", "system_fields":PackedByteArray([1]), "continuation_sha256":FileAccess.get_sha256(path), "manual_sha256":FileAccess.get_sha256(path), "tombstone":false, "metadata":{}}
func test_equal_bytes_map_without_upload_and_repeat_is_idempotent() -> void:
	var path := saved("equal")
	check_eq(store.publish_remote(remote(path), {"continuation":path, "manual":path}), OK)
	check_eq(coordinator.migrate_personal_saves(headers(path)), OK)
	check_eq(store.slots().size(), 1)
	check_eq(store.slots()[0].manual_path, path)
	check_eq(store.pending().size(), 0)
	var journal := FileAccess.get_file_as_bytes(store.journal_path())
	check_eq(coordinator.migrate_personal_saves(headers(path)), OK)
	check_eq(FileAccess.get_file_as_bytes(store.journal_path()), journal)
func test_equal_name_different_bytes_separate_and_restart_owner_is_consumed() -> void:
	var remote_path := saved("remote", 100)
	var local_path := saved("local", 200)
	store.publish_remote(remote(remote_path), {"continuation":remote_path, "manual":remote_path})
	check_eq(coordinator.migrate_personal_saves(headers(local_path)), OK)
	check_eq(store.slots().size(), 2)
	var other := CloudSaveStore.new(directory)
	other.open_library("account-b")
	var next := CloudSaveCoordinator.new(other, Fake.new())
	next._owner = "account-b"
	next._initial_inventory_complete = true
	check_eq(next.migrate_personal_saves(headers(local_path)), OK)
	check_eq(other.slots().size(), 0)
	next.shutdown()
func test_complete_initial_inventory_required() -> void:
	var path := saved("wait")
	coordinator._initial_inventory_complete = false
	check_eq(coordinator.migrate_personal_saves(headers(path)), ERR_BUSY)
	check_eq(store.slots().size(), 0)
func test_nonpersonal_and_corrupt_files_stay_untouched() -> void:
	var path := saved("private")
	var outside := directory.path_join("picker.sc2d")
	DirAccess.copy_absolute(path, outside)
	var bad := saved("bad")
	SaveFormat._write_replacement(bad, "invalid".to_utf8_buffer())
	var rows: Array[Dictionary] = [{"path":outside}, {"path":bad}, {"path":CityFileFlow.autosave_path()}, {"path":CityFileFlow.application_recovery_path()}, {"path":"res://assets/cities/included.sc2d"}]
	check_eq(coordinator.migrate_personal_saves(rows), OK)
	check_eq(store.slots().size(), 0)
	check_eq(FileAccess.get_sha256(outside), FileAccess.get_sha256(path))
func test_local_adoption_cannot_repeat_into_second_account_after_restart() -> void:
	store.open_library("")
	var path := saved("adopt")
	var id := store.create_slot()
	store.stage(id, path, path)
	check_eq(store.adopt_local(id, "account-a"), OK)
	var restart := CloudSaveStore.new(directory)
	restart.open_library("")
	check_eq(restart.adopt_local(id, "account-a"), OK)
	check_eq(restart.adopt_local(id, "account-b"), ERR_UNAUTHORIZED)

class FaultStore extends CloudSaveStore:
	var fail_claim := false
	var fail_journal := false
	var fail_destination := false
	func _write_claims(value: Dictionary) -> Error:
		return ERR_FILE_CANT_WRITE if fail_claim else super._write_claims(value)
	func _write_journal(bytes: PackedByteArray) -> Error:
		return ERR_FILE_CANT_WRITE if fail_journal else super._write_journal(bytes)
	func _adoption_destination() -> CloudSaveStore:
		var destination := FaultStore.new(_root)
		destination.fail_journal = fail_destination
		return destination

func test_claim_failure_prevents_namespace_publication() -> void:
	var fault := FaultStore.new(directory)
	fault.open_library("account-a")
	fault.fail_claim = true
	var path := saved("claim-fault")
	check_eq(fault.migrate_personal_file(path), ERR_FILE_CANT_WRITE)
	check_eq(fault.slots().size(), 0)
	check(fault.path_claim(path).is_empty())
	fault.fail_claim = false
	check_eq(fault.migrate_personal_file(path), OK)
	check_eq(fault.slots().size(), 1)

func test_claim_survives_namespace_failure_changed_bytes_and_restart() -> void:
	var fault := FaultStore.new(directory)
	fault.open_library("account-a")
	var path := saved("journal-fault")
	fault.fail_journal = true
	check_eq(fault.migrate_personal_file(path), ERR_FILE_CANT_WRITE)
	var reserved: String = fault.path_claim(path).slot_id
	var changed := flat_city()
	changed.funds = 777
	SaveFormat.save(path, changed)
	var other := CloudSaveStore.new(directory)
	other.open_library("account-b")
	check_eq(other.migrate_personal_file(path), OK)
	check_eq(other.slots().size(), 0)
	var retry := CloudSaveStore.new(directory)
	retry.open_library("account-a")
	check_eq(retry.migrate_personal_file(path), OK)
	check_eq(retry.slots()[0].slot_id, reserved)
	check_eq(retry.pending().size(), 1)

func test_adoption_destination_failure_repairs_immutable_checkpoint() -> void:
	var fault := FaultStore.new(directory)
	fault.open_library("")
	var path := saved("adopt-fault")
	var id := fault.create_slot()
	fault.stage(id, path, path)
	var checkpoint := saved("checkpoint", 22)
	var work := fault.stage(id, checkpoint)
	fault.fail_destination = true
	check_eq(fault.adopt_local(id, "account-a"), ERR_FILE_CANT_WRITE)
	var local := CloudSaveStore.new(directory)
	local.open_library("")
	check_eq(local.adopt_local(id, "account-b"), ERR_UNAUTHORIZED)
	var repaired := CloudSaveStore.new(directory)
	repaired.open_library("account-a")
	check_eq(repaired.repair_adoptions(), OK)
	check_eq(repaired.slots()[0].slot_id, id)
	check_eq(repaired.slots()[0].continuation_sha256, work.continuation.sha256)
	check_eq(repaired.slots()[0].manual_sha256, work.manual.sha256)
	check(CloudSaveSession._same_path(repaired.slots()[0].manual_path, path))
	var before := FileAccess.get_file_as_bytes(repaired.journal_path())
	check_eq(repaired.repair_adoptions(), OK)
	check_eq(FileAccess.get_file_as_bytes(repaired.journal_path()), before)

func test_inventory_last_page_and_download_precede_migration() -> void:
	coordinator.shutdown()
	var fake := Fake.new()
	coordinator = CloudSaveCoordinator.new(store, fake)
	var local := saved("inventory")
	coordinator.set_enabled(true)
	coordinator.advance(0)
	fake.finish(fake.last("account"), {"owner":"account-a"})
	coordinator.advance(0)
	fake.finish(fake.last("prepare_zone"))
	coordinator.advance(0)
	fake.finish(fake.last("changes"), {"records":[], "deleted_ids":[], "token":PackedByteArray([1]), "more":true})
	coordinator.advance(0)
	check_eq(store.slots().size(), 0)
	fake.finish(fake.last("changes"), {"records":[remote(local)], "deleted_ids":[], "token":PackedByteArray([2]), "more":false})
	coordinator.advance(0)
	check_eq(store.slots().size(), 0)
	check(not coordinator._initial_inventory_complete)
	fake.finish(fake.last("download"), {"downloaded":{"continuation":local, "manual":local}})
	coordinator.advance(0)
	check(coordinator._initial_inventory_complete)
	check_eq(store.slots().size(), 1)
	check_eq(store.slots()[0].slot_id, "remote")
	check_eq(fake.count("save"), 0)

func test_legacy_tourism_headers_migrate_once_without_rewriting_history() -> void:
	var path := saved("tourism-legacy")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	doc.header.population = 9000
	doc.header.erase("count_schema")
	doc.snapshot = {"stats": {"population": 42, "arcology_population": 500,
		"history": {"population": [9000, 8999]}, "last_year_ledger": {"taxes_residential": 123}}}
	doc.city.facilities = {"10,10": {"key": "arcology_comstock", "residents": 500, "built_day": 12, "condition": 3}}
	check_eq(SaveFormat._write_replacement(path, JSON.stringify(doc).to_utf8_buffer()), OK)
	var bytes := FileAccess.get_file_as_bytes(path)
	check_eq(coordinator.migrate_personal_saves(headers(path)), OK)
	check_eq(store.slots().size(), 1)
	var header := store.readable_header(store.slots()[0].path)
	check_eq(header.population, 42)
	check_eq(header.tourists, 500)
	check_eq(header.count_schema, 1)
	var journal := FileAccess.get_file_as_bytes(store.journal_path())
	check_eq(coordinator.migrate_personal_saves(headers(path)), OK)
	check_eq(FileAccess.get_file_as_bytes(store.journal_path()), journal)
	check_eq(FileAccess.get_file_as_bytes(path), bytes, "cloud migration keeps historical payload bytes")
