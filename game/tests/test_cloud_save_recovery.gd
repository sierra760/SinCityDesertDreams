# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const MAIN := preload("res://scenes/main.tscn")
const Fake := preload("res://tests/helpers/fake_apple_cloud.gd")
class FailingStore extends CloudSaveStore:
	var fail_clear := false
	var fail_write := false
	var fail_pointer := false
	func clear_application_recovery() -> Error:
		return ERR_FILE_CANT_WRITE if fail_clear else super.clear_application_recovery()
	func _write_journal(bytes: PackedByteArray) -> Error:
		return ERR_FILE_CANT_WRITE if fail_write else super._write_journal(bytes)
	func _write_recovery_pointer(value: Dictionary) -> Error:
		return ERR_FILE_CANT_WRITE if fail_pointer else super._write_recovery_pointer(value)
var host: GameHost
var store: CloudSaveStore
var cloud: CloudSaveSession
var coordinator: CloudSaveCoordinator
var directory: String
var named := ""

func before_each() -> void:
	directory = "user://cloud-recovery-tests/" + CloudSaveTypes.uuid()
	_start_host()
	var city := flat_city()
	city.name = "Recovery fixture " + CloudSaveTypes.uuid()
	host.begin_city(city, {}, 123, null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	cloud.begin_session()

func _start_host() -> void:
	store = FailingStore.new(directory)
	check_eq(store.open_library(""), OK)
	coordinator = CloudSaveCoordinator.new(store, Fake.new())
	host = MAIN.instantiate()
	cloud = CloudSaveSession.new(host, coordinator, store)
	host.cloud_saves = cloud
	host.preferences_path = directory.path_join("preferences.cfg")
	root.add_child(host)
	host.set_process(false)

func _restart() -> void:
	host.free()
	await process_frame
	_start_host()

func after_each() -> void:
	host.free()
	if not named.is_empty(): DirAccess.remove_absolute(named)
	for entry in SaveFormat.list_saves():
		if entry.path.get_file().begins_with("Recovery fixture "): DirAccess.remove_absolute(entry.path)
	DirAccess.remove_absolute(CityFileFlow.application_recovery_path())
	DirAccess.remove_absolute("user://recovery/suspended-untracked.sc2d")
	DirAccess.remove_absolute(CityFileFlow.autosave_path())
	await process_frame

func _entry(id: String = "") -> Dictionary:
	var library := CloudSaveStore.new(directory)
	check_eq(library.open_library(cloud.owner), OK)
	for entry in library.slots():
		if entry.slot_id == (cloud.slot_id if id.is_empty() else id): return entry
	return {}

# Missing durable recovery identity must fail here: a genuinely new host and
# store reopen the ordinary application recovery, keeping the named baseline.
func test_tracked_recovery_reopens_same_slot_and_original_manual_baseline() -> void:
	named = host.files.save_city_as("cloud-recovery-" + CloudSaveTypes.uuid())
	var id := cloud.slot_id
	var manual := FileAccess.get_file_as_bytes(named)
	host.sim.city.funds -= 77
	var funds := host.sim.city.funds
	check_eq(host.suspend_for_background(), OK)
	await _restart()
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_eq(cloud.slot_id, id, "tracked suspension must retain its cloud identity across host/store reopen")
	check_eq(host.save_path, named, "manual Save must still target the original personal document")
	check_eq(host.sim.city.funds, funds)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	check(host.files.has_unsaved_changes(), "recovery must retain the older explicit manual baseline")
	check_eq(FileAccess.get_file_as_bytes(named), manual)

func _verify(owner: String) -> void:
	coordinator.set_enabled(true)
	coordinator.advance(Time.get_ticks_msec())
	var fake = coordinator._platform
	fake.finish(fake.last("account"), {"owner": owner})
	coordinator.advance(Time.get_ticks_msec())
	check_eq(coordinator.status().owner, owner)

func _ack_all() -> void:
	for work in store.pending():
		check(not store.begin_upload(work.slot_id, work.generation).is_empty())
		check_eq(store.acknowledge(work.slot_id, work.generation, work.commit_id, PackedByteArray([1]), "ack-" + str(work.generation)), OK)

func _tracked_owned_recovery() -> Dictionary:
	_verify("account-a")
	named = host.files.save_city_as("cloud-recovery-" + CloudSaveTypes.uuid())
	_ack_all()
	var id := cloud.slot_id
	host.sim.city.funds -= 33
	check_eq(host.suspend_for_background(), OK)
	return {"id": id, "funds": host.sim.city.funds, "manual": FileAccess.get_file_as_bytes(named),
		"recovery": FileAccess.get_file_as_bytes(CityFileFlow.application_recovery_path()), "work": store.pending()[0]}

func test_acknowledged_suspension_preserves_identity_after_process_store_reopen() -> void:
	var before := _tracked_owned_recovery()
	_ack_all()
	await _restart()
	_verify("account-a")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_eq(cloud.slot_id, before.id)
	check_eq(host.save_path, named)
	check(host.files.has_unsaved_changes())

func test_advanced_remote_keeps_both_exact_branches_and_original_manual_baseline() -> void:
	var before := _tracked_owned_recovery()
	_ack_all()
	var city := flat_city()
	city.funds = 8765
	var incoming := directory.path_join("remote.sc2d")
	check_eq(SaveFormat.save(incoming, city, host.sim.snapshot()), OK)
	var remote := {"slot_id": before.id, "commit_id": "remote-commit", "change_tag": "advanced-tag", "system_fields": PackedByteArray([9]), "continuation_sha256": FileAccess.get_sha256(incoming), "manual_sha256": "", "tombstone": false, "metadata": {}}
	check_eq(store.publish_remote(remote, {"continuation": incoming}), OK)
	await _restart()
	_verify("account-a")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	var branch := cloud.slot_id
	check_ne(branch, before.id, "old recovered bytes must not descend from a newer remote head")
	check_eq(_entry(before.id).continuation_sha256, remote.continuation_sha256)
	check_eq(host.sim.city.funds, before.funds)
	check_eq(host.save_path, named)
	check(host.files.has_unsaved_changes())
	check_eq(FileAccess.get_file_as_bytes(named), before.manual)
	var work: Dictionary = {}
	for pending in store.pending():
		if pending.slot_id == branch: work = pending
	check_eq(work.get("parent_commit_id", "missing"), "")
	check_eq(work.get("baseline_tag", "missing"), "")
	check_eq(work.get("manual", {}).get("sha256", ""), before.work.manual.sha256)
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_eq(cloud.slot_id, branch, "repeated recovery is idempotent while its captured commit is still current")

func test_newer_local_pending_and_uncertain_pin_survive_exact_recovery_fork() -> void:
	var before := _tracked_owned_recovery()
	check(not store.begin_upload(before.id, before.work.generation).is_empty())
	host.sim.city.funds -= 100
	check_eq(cloud.capture(&"test"), OK)
	var newer := store.pending()[0]
	await _restart()
	_verify("account-a")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_ne(cloud.slot_id, before.id)
	check_eq(host.sim.city.funds, before.funds)
	var original_pending: Dictionary = {}
	for pending in store.pending():
		if pending.slot_id == before.id: original_pending = pending
	check_eq(original_pending, newer, "older recovery cannot clear or reparent newer pending work")
	check_eq(store.inflight().size(), 1)
	check_eq(store.inflight()[0].commit_id, before.work.commit_id)

func test_foreign_owner_recovery_is_parked_until_original_owner_returns() -> void:
	var before := _tracked_owned_recovery()
	await _restart()
	_verify("account-b")
	var active_directory := store._directory
	var active_journal := FileAccess.get_file_as_bytes(store.journal_path())
	var parked := CloudSaveStore.new(directory)
	check_eq(parked.open_library("account-a"), OK)
	var parked_journal := FileAccess.get_file_as_bytes(parked.journal_path())
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_eq(cloud.owner, "account-a")
	check_eq(cloud.slot_id, before.id)
	check_eq(cloud.capture(&"test"), ERR_UNAUTHORIZED)
	check_eq(store._directory, active_directory)
	check_eq(FileAccess.get_file_as_bytes(store.journal_path()), active_journal)
	check_eq(FileAccess.get_file_as_bytes(parked.journal_path()), parked_journal)

func test_parked_owner_background_preserves_authenticated_copy_and_latest_fallback() -> void:
	var before := _tracked_owned_recovery()
	await _restart()
	_verify("account-b")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	var owner_library := CloudSaveStore.new(directory)
	check_eq(owner_library.open_library("account-a"), OK)
	var owner_bytes := FileAccess.get_file_as_bytes(owner_library.journal_path())
	var pointer := FileAccess.get_file_as_bytes(directory.path_join("application-recovery.bin"))
	host.sim.city.funds -= 19
	var latest := host.sim.city.funds
	check_eq(host.suspend_for_background(), OK)
	check_eq(FileAccess.get_file_as_bytes(CityFileFlow.application_recovery_path()), before.recovery)
	check_eq(FileAccess.get_file_as_bytes(directory.path_join("application-recovery.bin")), pointer)
	check_eq(FileAccess.get_file_as_bytes(owner_library.journal_path()), owner_bytes)
	await _restart()
	_verify("account-b")
	var loaded := host.load_city("user://recovery/suspended-untracked.sc2d")
	check(loaded)
	if not loaded: return
	check_ne(cloud.slot_id, before.id, "fresh untracked choice never impersonates the absent owner's slot")
	check_eq(host.sim.city.funds, latest)
	check_eq(host.save_path, "")

func test_original_owner_return_resolves_deferred_receipt_before_new_capture() -> void:
	var before := _tracked_owned_recovery()
	await _restart()
	_verify("account-b")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	var fake = coordinator._platform
	fake.account_changed(coordinator.status().epoch)
	coordinator.advance(Time.get_ticks_msec())
	fake.finish(fake.last("account"), {"owner": "account-a"})
	coordinator.advance(Time.get_ticks_msec())
	check_eq(cloud.owner, "account-a")
	check_eq(cloud.slot_id, before.id)
	host.sim.city.funds -= 1
	check_eq(cloud.capture(&"test"), OK)
	check_eq(SaveFormat.load(_entry().path).city.funds, before.funds - 1)

func test_adopted_local_receipt_uses_consumed_owner_proof() -> void:
	named = host.files.save_city_as("cloud-recovery-" + CloudSaveTypes.uuid())
	var id := cloud.slot_id
	host.sim.city.funds -= 23
	check_eq(host.suspend_for_background(), OK)
	_verify("account-a")
	await _restart()
	_verify("account-b")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_eq(cloud.owner, "account-a", "consumed local receipt cannot be adopted by another account")
	check_eq(cloud.slot_id, id)
	check_eq(cloud.capture(&"test"), ERR_UNAUTHORIZED)

func _fork_local_recovery_then_adopt() -> String:
	named = host.files.save_city_as("cloud-recovery-" + CloudSaveTypes.uuid())
	var original := cloud.slot_id
	host.sim.city.funds -= 6
	check_eq(host.suspend_for_background(), OK)
	host.sim.city.funds -= 70
	check_eq(cloud.capture(&"test"), OK)
	check(host.load_city(CityFileFlow.application_recovery_path()))
	var branch := cloud.slot_id
	check_ne(branch, original)
	_verify("account-a")
	check_eq(cloud.owner, "account-a")
	check_eq(cloud.slot_id, branch)
	return branch

func test_recovered_local_fork_retains_exact_identity_through_first_account_adoption() -> void:
	var branch := _fork_local_recovery_then_adopt()
	await _restart()
	_verify("account-a")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_eq(cloud.owner, "account-a")
	check_eq(cloud.slot_id, branch)
	host.sim.city.funds -= 1
	check_eq(cloud.capture(&"test"), OK)
	check_eq(_entry().slot_id, branch)

func test_adopted_recovered_local_fork_remains_parked_for_another_account() -> void:
	var branch := _fork_local_recovery_then_adopt()
	await _restart()
	_verify("account-b")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_eq(cloud.owner, "account-a")
	check_eq(cloud.slot_id, branch)
	check_eq(cloud.capture(&"test"), ERR_UNAUTHORIZED)

func test_pointer_invalidation_failure_writes_playable_untracked_fallback() -> void:
	var before := _tracked_owned_recovery()
	host._application_suspended = false
	host.sim.city.funds -= 44
	var latest := host.sim.city.funds
	store.fail_clear = true
	check_eq(host.suspend_for_background(), OK, "optional cloud metadata failure cannot lose latest local recovery")
	check_eq(FileAccess.get_file_as_bytes(CityFileFlow.application_recovery_path()), before.recovery)
	var fallback := "user://recovery/suspended-untracked.sc2d"
	check_eq(SaveFormat.load(fallback).get("city").funds, latest)
	var listed := false
	for entry in host.files._load_entries():
		if CloudSaveSession._same_path(entry.path, fallback): listed = true
	check(listed, "latest fallback appears in ordinary Load")
	store.fail_clear = false
	await _restart()
	_verify("account-a")
	check(host.load_city(fallback))
	check_ne(cloud.slot_id, before.id)
	check_eq(host.save_path, "")
	check_eq(host.sim.city.funds, latest)
	check_eq(host.suspend_for_background(), OK)
	check(not FileAccess.file_exists(fallback), "durable newer canonical recovery retires obsolete fallback")

func test_corrupt_or_hash_mismatched_receipts_fall_back_to_personal_recovery() -> void:
	var before := _tracked_owned_recovery()
	var pointer_path := directory.path_join("application-recovery.bin")
	check_eq(SaveFormat._write_replacement(pointer_path, "invalid".to_utf8_buffer()), OK)
	await _restart()
	_verify("account-a")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_ne(cloud.slot_id, before.id)
	check_eq(host.save_path, "")

func test_replaced_recovery_bytes_and_copied_recovery_path_never_borrow_identity() -> void:
	var before := _tracked_owned_recovery()
	var copied := directory.path_join("copied.sc2d")
	check_eq(SaveFormat._write_replacement(copied, before.recovery), OK)
	check(host.load_city(copied))
	check_ne(cloud.slot_id, before.id, "identical portable bytes outside the known managed path do not identify a cloud city")
	var city := flat_city()
	city.funds = 1234
	check_eq(SaveFormat.save(CityFileFlow.application_recovery_path(), city), OK)
	await _restart()
	_verify("account-a")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_ne(cloud.slot_id, before.id)
	check_eq(host.sim.city.funds, 1234)
	check_eq(host.save_path, "")

func test_receipt_publication_failure_keeps_recovery_playable_with_fresh_identity() -> void:
	_verify("account-a")
	named = host.files.save_city_as("cloud-recovery-" + CloudSaveTypes.uuid())
	var original := cloud.slot_id
	host.sim.city.funds -= 5
	store.fail_pointer = true
	check_eq(host.suspend_for_background(), OK)
	check(host.notice_dialog.is_open(), "cloud-local receipt failure is visible")
	check(SaveFormat.load(CityFileFlow.application_recovery_path()).ok)
	await _restart()
	_verify("account-a")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_ne(cloud.slot_id, original)
	check_eq(host.save_path, "")

func test_recovery_journal_failure_keeps_local_copy_and_prior_library() -> void:
	_verify("account-a")
	named = host.files.save_city_as("cloud-recovery-" + CloudSaveTypes.uuid())
	var original := cloud.slot_id
	var journal := FileAccess.get_file_as_bytes(store.journal_path())
	host.sim.city.funds -= 5
	store.fail_write = true
	check_eq(host.suspend_for_background(), OK)
	check(host.notice_dialog.is_open())
	check_eq(FileAccess.get_file_as_bytes(store.journal_path()), journal)
	store.fail_write = false
	await _restart()
	_verify("account-a")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_ne(cloud.slot_id, original)

func test_rebound_manual_destination_is_never_stolen_by_older_recovery() -> void:
	var before := _tracked_owned_recovery()
	_ack_all()
	var other := store.create_slot()
	check(not other.is_empty())
	var next := store._state.duplicate(true)
	next.slots[before.id].manual_path = ""
	check_eq(store._commit(next), OK)
	check_eq(store.bind_manual_path(other, named), OK)
	await _restart()
	_verify("account-a")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_ne(host.save_path, named, "old receipt cannot take another explicit document association")
	check_eq(_entry(other).manual_path, named)
	check_eq(FileAccess.get_file_as_bytes(named), before.manual)

func test_foreign_claim_cannot_restore_stale_manual_path_from_matching_resumed_head() -> void:
	var before := _tracked_owned_recovery()
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_eq(cloud.slot_id, before.id)
	check_eq(store._claim(["path:" + ProjectSettings.globalize_path(named).simplify_path()], "account-b", "foreign-slot", true), OK)
	check_eq(store._state.slots[before.id].manual_path, named, "foreign Save As need not mutate the absent owner's stale journal")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_ne(host.save_path, named, "matching captured commit is not permission to overwrite a foreign claimed document")
	check_eq(FileAccess.get_file_as_bytes(named), before.manual)
	check_eq(store.path_claim(named).owner, "account-b")
	var previous := host.save_path
	var previous_bytes := FileAccess.get_file_as_bytes(previous)
	check_eq(store._claim(["path:" + ProjectSettings.globalize_path(previous).simplify_path()], "account-a", "other-manual-intent", true), OK)
	check_eq(store._state.slots[before.id].manual_path, previous)
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_ne(host.save_path, previous, "same-owner failed explicit transfer still reserves the document for its intended target")
	check_eq(FileAccess.get_file_as_bytes(previous), previous_bytes)

func test_loading_old_recovery_after_new_local_head_preserves_both_generations() -> void:
	var before := _tracked_owned_recovery()
	_ack_all()
	var remote_city := flat_city()
	remote_city.funds = 7654
	var incoming := directory.path_join("newer-remote.sc2d")
	check_eq(SaveFormat.save(incoming, remote_city), OK)
	var remote := {"slot_id": before.id, "commit_id": "remote-later", "change_tag": "remote-tag", "system_fields": PackedByteArray([8]), "continuation_sha256": FileAccess.get_sha256(incoming), "manual_sha256": "", "tombstone": false, "metadata": {}}
	check_eq(store.publish_remote(remote, {"continuation": incoming}), OK)
	await _restart()
	_verify("account-a")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	var first := cloud.slot_id
	check_ne(first, before.id)
	host.sim.city.funds -= 101
	check_eq(cloud.capture(&"test"), OK)
	var advanced: String = _entry(first).continuation_sha256
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_ne(cloud.slot_id, first)
	check_eq(_entry(first).continuation_sha256, advanced)
	check_eq(host.sim.city.funds, before.funds)
	var second := cloud.slot_id
	var resumed_path := host.save_path
	check_ne(resumed_path, named, "older recovery cannot share the newer first fork's manual document")
	var file_count := SaveFormat.list_saves().size()
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_eq(cloud.slot_id, second)
	check_eq(host.save_path, resumed_path, "repeat recovery keeps the proved resumed slot's durable manual destination")
	check_eq(SaveFormat.list_saves().size(), file_count, "repeat creates no additional personal document")
	check_eq(_entry(first).manual_path, named, "newer first fork retains its named association")

func test_late_ancestor_ack_keeps_captured_identity_and_acknowledged_parent() -> void:
	_verify("account-a")
	named = host.files.save_city_as("cloud-recovery-" + CloudSaveTypes.uuid())
	var id := cloud.slot_id
	var sent := store.pending()[0]
	check(not store.begin_upload(id, sent.generation).is_empty())
	host.sim.city.funds -= 7
	check_eq(host.suspend_for_background(), OK)
	var captured := store.pending()[0]
	check_eq(captured.parent_commit_id, sent.commit_id)
	check_eq(store.acknowledge(id, sent.generation, sent.commit_id, PackedByteArray([7]), "late-tag"), OK)
	await _restart()
	_verify("account-a")
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_eq(cloud.slot_id, id)
	host.sim.city.funds -= 1
	check_eq(cloud.capture(&"test"), OK)
	check_eq(store.pending()[0].parent_commit_id, sent.commit_id)
	check_eq(store.pending()[0].baseline_tag, "late-tag", "captured child reuses proven ACK, never latest unrelated inventory")

func test_fallback_cleanup_targets_only_the_actual_loaded_recovery_path() -> void:
	var before := _tracked_owned_recovery()
	var fallback := "user://recovery/suspended-untracked.sc2d"
	check_eq(SaveFormat._write_replacement(fallback, before.recovery), OK)
	check(host.load_city(fallback))
	host.files.discard_recovery_copy()
	check(not FileAccess.file_exists(fallback))
	check_eq(FileAccess.get_file_as_bytes(CityFileFlow.application_recovery_path()), before.recovery)

func test_receipt_failure_retains_previous_fallback_until_complete_canonical_publication() -> void:
	var before := _tracked_owned_recovery()
	var fallback := "user://recovery/suspended-untracked.sc2d"
	check_eq(SaveFormat._write_replacement(fallback, before.recovery), OK)
	host._application_suspended = false
	host.sim.city.funds -= 8
	store.fail_pointer = true
	check_eq(host.suspend_for_background(), OK)
	check(FileAccess.file_exists(fallback), "canonical bytes alone cannot retire fallback before receipt publication succeeds")
	store.fail_pointer = false
	host._application_suspended = false
	check_eq(host.suspend_for_background(), OK)
	check(not FileAccess.file_exists(fallback))

func test_background_recovery_does_not_clear_substituted_manual_integrity_error() -> void:
	var before := _tracked_owned_recovery()
	_ack_all()
	var continuation: String = _entry(before.id).path
	var manual_path: String = _entry(before.id).manual.path
	var original_manual := FileAccess.get_file_as_bytes(manual_path)
	var substituted := flat_city()
	substituted.funds = 999
	check_eq(SaveFormat.save(manual_path, substituted), OK)
	check(host.load_city(continuation), "valid continuation remains playable despite substituted separate manual asset")
	check(cloud._manual_integrity_error)
	var journal := FileAccess.get_file_as_bytes(store.journal_path())
	host._application_suspended = false
	check_eq(host.suspend_for_background(), OK)
	check(cloud._manual_integrity_error)
	check(not cloud._capture_error_slot.is_empty(), "background cannot report successful cloud preparation over sticky integrity error")
	check_eq(FileAccess.get_file_as_bytes(store.journal_path()), journal)
	check(SaveFormat.load("user://recovery/suspended-untracked.sc2d").ok)
	# Restore immutable fixture bytes before teardown, without mutating any city.
	check_eq(SaveFormat._write_replacement(manual_path, original_manual), OK)

func test_legacy_recovery_and_annual_backup_still_create_personal_sessions() -> void:
	var old := cloud.slot_id
	check_eq(SaveFormat.save(CityFileFlow.application_recovery_path(), host.sim.city, host.sim.snapshot()), OK)
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_ne(cloud.slot_id, old)
	check_eq(host.save_path, "")
	old = cloud.slot_id
	check_eq(host.autosave(), OK)
	check(host.load_city(CityFileFlow.autosave_path()))
	check_ne(cloud.slot_id, old)
	check_eq(host.save_path, "")
