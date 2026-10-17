# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const MAIN := preload("res://scenes/main.tscn")
const Fake := preload("res://tests/helpers/fake_apple_cloud.gd")
class CountingFiles extends CityFileFlow:
	var snapshots := 0
	func save_content() -> Dictionary:
		snapshots += 1
		return super.save_content()
var host: GameHost
var store: CloudSaveStore
var coordinator: CloudSaveCoordinator
var cloud: CloudSaveSession
var directory: String
var paths: Array[String] = []
func before_each() -> void:
	directory = "user://cloud-session-tests/" + CloudSaveTypes.uuid()
	store = CloudSaveStore.new(directory)
	check_eq(store.open_library(""), OK)
	coordinator = CloudSaveCoordinator.new(store, Fake.new())
	host = MAIN.instantiate()
	host.files = CountingFiles.new(host)
	cloud = CloudSaveSession.new(host, coordinator, store)
	host.cloud_saves = cloud
	host.preferences_path = directory.path_join("preferences.cfg")
	root.add_child(host)
	host.set_process(false)
	host.begin_city(flat_city(), {}, 123, null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.save_path = ""
	cloud.begin_session()
func after_each() -> void:
	host.free()
	for path in paths: DirAccess.remove_absolute(path)
	paths.clear()
	await process_frame
func saved(name: String) -> String:
	var path := host.files.save_city_as("cloud-session-" + name)
	paths.append(path)
	return path
func row(id: String = "") -> Dictionary:
	store.open_library(cloud.owner)
	for entry in store.slots():
		if entry.slot_id == (cloud.slot_id if id.is_empty() else id): return entry
	return {}
func _verify_account(value: String) -> void:
	coordinator.set_enabled(true)
	coordinator.advance(Time.get_ticks_msec())
	var fake = coordinator._platform
	fake.finish(fake.last("account"), {"owner": value})
	coordinator.advance(Time.get_ticks_msec())
	check_eq(coordinator.status().owner, value)

func test_dont_save_reverts_uploaded_checkpoint() -> void:
	_verify_account("account-a")
	var path := saved("rollback")
	var manual_hash := FileAccess.get_sha256(path)
	host.sim.city.funds -= 900
	cloud.capture(&"test")
	var work := store.pending()[0]
	store.begin_upload(cloud.slot_id, work.generation)
	store.acknowledge(cloud.slot_id, work.generation, work.commit_id, PackedByteArray([4]), "checkpoint-tag")
	check_eq(cloud.discard(), OK)
	var pending := store.pending()[0]
	check_eq(pending.continuation.sha256, manual_hash)
	check_eq(pending.parent_commit_id, work.commit_id)
	check_eq(pending.baseline_tag, "checkpoint-tag")
	check_ne(cloud.capture(&"background"), OK)
	check_eq(FileAccess.get_sha256(path), manual_hash)

func test_discard_unnamed_session_queues_conditional_tombstone() -> void:
	_verify_account("account-a")
	host.sim.city.funds -= 1
	cloud.capture(&"test")
	var id := cloud.slot_id
	var work := store.pending()[0]
	store.begin_upload(id, work.generation)
	check_eq(cloud.discard(), OK)
	var next := store.pending()[0]
	check(next.tombstone)
	check_eq(next.parent_commit_id, work.commit_id)
	var restart := CloudSaveStore.new(directory)
	check_eq(restart.open_library("account-a"), OK)
	check(restart.pending()[0].tombstone)
	check_eq(restart.inflight()[0].commit_id, work.commit_id)

func test_last_manual_restore_preserves_named_path() -> void:
	var path := saved("restore")
	var id := cloud.slot_id
	var funds := host.sim.city.funds
	host.sim.city.funds -= 321
	cloud.capture(&"test")
	check_eq(cloud.restore_manual(), OK)
	check_eq(host.save_path, path)
	check_eq(cloud.slot_id, id)
	check_eq(host.sim.city.funds, funds)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	check(not host.files.has_unsaved_changes())
	check_eq(row().manual_sha256, row().continuation_sha256)
	check_eq(row().generation, 3)

func test_first_async_account_adopts_named_and_unnamed_once() -> void:
	var path := saved("preaccount")
	var id := cloud.slot_id
	host.sim.city.funds -= 12
	cloud.capture(&"test")
	_verify_account("account-a")
	check_eq(cloud.owner, "account-a")
	check_eq(cloud.slot_id, id)
	check_eq(row().manual_path, path)
	coordinator.set_enabled(false)
	_verify_account("account-b")
	check_eq(cloud.owner, "account-a")
	check_eq(store.slots().size(), 0)
	check_ne(cloud.capture(&"test"), OK)
	check_eq(cloud._local.adopt_local(id, "account-b"), ERR_UNAUTHORIZED)
	coordinator.set_enabled(false)
	_verify_account("account-a")
	check_eq(cloud.capture(&"test"), OK)
	check_eq(row().generation, 2, "reconnection cannot rewrite unchanged content")

func test_explicit_save_as_allows_new_account_copy() -> void:
	_verify_account("account-a")
	var source := saved("old-owner")
	var original := cloud.slot_id
	var old_hash: String = row().continuation_sha256
	coordinator.set_enabled(false)
	_verify_account("account-b")
	host.sim.city.funds -= 99
	check_eq(host.files.save_city(), OK)
	check_eq(store.slots().size(), 0, "ordinary Save is local only after swap")
	old_hash = FileAccess.get_sha256(source)
	host.sim.city.funds -= 7
	check_eq(cloud.discard(), OK, "parked ordinary Save establishes the rollback point")
	var parked := CloudSaveStore.new(directory)
	parked.open_library("account-a")
	check_eq(parked.pending()[0].continuation.sha256, old_hash)
	check_eq(parked.pending()[0].manual.sha256, old_hash)
	check_eq(store.slots().size(), 0)
	var destination := saved("new-owner")
	check_eq(cloud.owner, "account-b")
	check_ne(cloud.slot_id, original)
	check_eq(row().manual_path, destination)
	var old := CloudSaveStore.new(directory)
	old.open_library("account-a")
	check_eq(old.slots()[0].manual_path, source)
	check_eq(old.slots()[0].continuation_sha256, old_hash)

func test_cancel_does_not_discard() -> void:
	var path := saved("cancel")
	host.sim.city.funds -= 4
	cloud.capture(&"test")
	var before: String = row().continuation_sha256
	host.files.request_city_action(&"new")
	host.notice_dialog.dismiss(&"cancel")
	check_eq(row().continuation_sha256, before)
	check_eq(host.save_path, path)
	check_eq(cloud.capture(&"test"), OK)

func test_first_save_replace_retires_only_redundant_unnamed_slot() -> void:
	_verify_account("account-a")
	var path := saved("first-replace")
	var target := cloud.slot_id
	cloud.end_session()
	host.save_path = ""
	cloud.begin_session()
	var unnamed := cloud.slot_id
	host.sim.city.funds -= 9
	cloud.capture(&"test")
	var work: Dictionary = {}
	for pending in store.pending():
		if pending.slot_id == unnamed: work = pending
	store.begin_upload(unnamed, work.generation)
	check_eq(saved("first-replace"), path)
	check_eq(cloud.slot_id, target)
	var restart := CloudSaveStore.new(directory)
	restart.open_library("account-a")
	check_eq(restart.slots().size(), 1)
	check_eq(restart.slots()[0].slot_id, target)
	check_eq(restart.inflight()[0].slot_id, unnamed)
	var tombstone: Dictionary = {}
	for pending in restart.pending():
		if pending.slot_id == unnamed: tombstone = pending
	check(tombstone.get("tombstone", false))
	check_eq(tombstone.get("parent_commit_id"), work.commit_id)

func test_initial_adoption_preserves_active_old_ancestor_against_new_remote() -> void:
	var manual := saved("late-owner")
	var active := cloud.slot_id
	host.sim.city.funds -= 5
	cloud.capture(&"test")
	var funds := host.sim.city.funds
	_verify_account("account-a")
	var remote_path := directory.path_join("advanced.sc2d")
	var city := flat_city()
	city.funds -= 500
	SaveFormat.save(remote_path, city)
	var remote := {"slot_id":"other-device", "commit_id":"remote-new", "change_tag":"new-tag", "system_fields":PackedByteArray([8]), "continuation_sha256":FileAccess.get_sha256(remote_path), "manual_sha256":FileAccess.get_sha256(manual), "tombstone":false, "metadata":{}}
	var fake = coordinator._platform
	fake.finish(fake.last("prepare_zone"))
	coordinator.advance(Time.get_ticks_msec())
	fake.finish(fake.last("changes"), {"records":[remote], "deleted_ids":[], "token":PackedByteArray([2]), "more":false})
	coordinator.advance(Time.get_ticks_msec())
	fake.finish(fake.last("download"), {"downloaded":{"continuation":remote_path, "manual":manual}})
	coordinator.advance(Time.get_ticks_msec())
	check_eq(cloud.slot_id, active)
	check_eq(host.sim.city.funds, funds)
	check_ne(cloud.slot_id, remote.slot_id)
	check_eq(row(remote.slot_id).continuation_sha256, remote.continuation_sha256)
	host.sim.city.funds -= 1
	check_eq(cloud.capture(&"test"), OK)
	check_eq(row(remote.slot_id).continuation_sha256, remote.continuation_sha256)

func test_backup_origin_gets_personal_destination() -> void:
	var path := CityFileFlow.autosave_path()
	paths.append(path)
	check_eq(SaveFormat.save(path, host.sim.city), OK)
	var bytes := FileAccess.get_file_as_bytes(path)
	check(host.load_city(ProjectSettings.globalize_path(path)))
	check(CloudSaveStore.personal_path(row().manual_path))
	check_eq(host.save_path, "")
	check(host.files.has_unsaved_changes())
	host.sim.city.funds -= 10
	host._on_menu_action(&"city_save", null)
	check(host.save_dialog.is_open())
	if host.save_dialog.is_open():
		host.save_dialog.name_edit.text = "cloud-session-recovered-origin"
		host.save_dialog.confirm()
		await process_frame
		while host.loading_screen.visible: await process_frame
		paths.append(host.save_path)
		check_eq(host.save_path, CityFileFlow.save_path_for("cloud-session-recovered-origin"))
		check_eq(row().manual_path, host.save_path)
	check_eq(FileAccess.get_file_as_bytes(path), bytes)
	# An ordinary selected document keeps the existing explicit Save contract.
	var external := directory.path_join("selected-document.sc2d")
	check_eq(SaveFormat.save(external, host.sim.city), OK)
	var external_bytes := FileAccess.get_file_as_bytes(external)
	check(host.load_city(external))
	check_eq(host.save_path, external)
	check(CloudSaveStore.personal_path(row().manual_path))
	check(not host.files.has_unsaved_changes())
	host.sim.city.funds -= 1
	check_eq(cloud.capture(&"test"), OK)
	check_eq(FileAccess.get_file_as_bytes(external), external_bytes)
	host._on_menu_action(&"city_save", null)
	await process_frame
	while host.loading_screen.visible: await process_frame
	check(not host.save_dialog.is_open())
	check_eq(host.save_path, external)
	check_ne(FileAccess.get_file_as_bytes(external), external_bytes)

func test_discard_conflict_preserves_concurrent_remote_branch() -> void:
	_verify_account("account-a")
	var manual := saved("discard-conflict")
	var id := cloud.slot_id
	host.sim.city.funds -= 3
	cloud.capture(&"test")
	var sent := store.pending()[0]
	store.begin_upload(id, sent.generation)
	store.acknowledge(id, sent.generation, sent.commit_id, PackedByteArray([1]), "old-tag")
	check_eq(cloud.discard(), OK)
	var remote_path := directory.path_join("concurrent.sc2d")
	var city := flat_city()
	city.funds -= 800
	SaveFormat.save(remote_path, city)
	var remote := {"slot_id":id, "commit_id":"concurrent", "change_tag":"concurrent-tag", "system_fields":PackedByteArray([2]), "continuation_sha256":FileAccess.get_sha256(remote_path), "manual_sha256":FileAccess.get_sha256(manual), "tombstone":false, "metadata":{}}
	check(coordinator._reconcile(id, remote))
	check_eq(store.publish_remote(remote, {"continuation":remote_path, "manual":manual}), OK)
	check_eq(store.slots().size(), 2)
	check_eq(row(id).continuation_sha256, remote.continuation_sha256)
	check_eq(store.pending()[0].continuation.sha256, FileAccess.get_sha256(manual))
	check_ne(store.pending()[0].slot_id, id)

class FailingStore extends CloudSaveStore:
	var fail := false
	var writes_before_failure := -1
	func _write_journal(bytes: PackedByteArray) -> Error:
		if fail or writes_before_failure == 0: return ERR_CANT_CREATE
		if writes_before_failure > 0: writes_before_failure -= 1
		return super._write_journal(bytes)
func use_failing_store() -> FailingStore:
	var replacement := FailingStore.new(directory)
	replacement.open_library(coordinator.status().owner)
	store = replacement
	coordinator._store = replacement
	cloud.store = replacement
	return replacement

func test_failed_discard_blocks_exit_and_preserves_current_city() -> void:
	_verify_account("account-a")
	saved("failed-discard")
	host.sim.city.funds -= 77
	cloud.capture(&"test")
	var fault := use_failing_store()
	var before := FileAccess.get_file_as_bytes(store.journal_path())
	var city := host.sim.city
	fault.fail = true
	host.files.request_city_action(&"new")
	host.notice_dialog.dismiss(&"discard")
	check_eq(host.sim.city, city)
	check(not host.new_city_dialog.visible)
	check_eq(FileAccess.get_file_as_bytes(store.journal_path()), before)
	check(not cloud._discarded)
	fault.fail = false
	check_eq(cloud.discard(), OK)
	check_ne(cloud.capture(&"background"), OK)
	check_eq(host.files.save_city(), OK, "a later explicit Save resumes a cancelled leave")
	check_eq(cloud.capture(&"test"), OK)

func test_failed_crossaccount_save_as_retries_destination_without_source_capture() -> void:
	_verify_account("account-a")
	var original := saved("transfer-source")
	var source := cloud.slot_id
	var source_hash: String = row().continuation_sha256
	coordinator.set_enabled(false)
	_verify_account("account-b")
	var fault := use_failing_store()
	fault.fail = true
	host.sim.city.funds -= 5
	var destination := saved("transfer-destination")
	check(not destination.is_empty(), "optional cloud failure does not fail local Save As")
	check(not host.files.has_unsaved_changes())
	check_eq(cloud.owner, "account-a")
	host.sim.city.funds -= 8
	check_ne(cloud.capture(&"test"), OK)
	fault.fail = false
	check_eq(cloud.capture(&"test"), OK)
	check_eq(cloud.owner, "account-b")
	check_eq(row().manual_sha256, FileAccess.get_sha256(destination))
	check_ne(row().continuation_sha256, row().manual_sha256)
	var previous := CloudSaveStore.new(directory)
	previous.open_library("account-a")
	check_eq(previous.slots()[0].slot_id, source)
	check_eq(previous.slots()[0].continuation_sha256, source_hash)
	check_eq(previous.slots()[0].manual_path, original)

func test_crossaccount_replace_repairs_old_named_association_on_restart() -> void:
	_verify_account("account-a")
	var path := saved("transfer-replace")
	var old := cloud.slot_id
	var old_hash: String = row().continuation_sha256
	coordinator.set_enabled(false)
	_verify_account("account-b")
	host.sim.city.funds -= 4
	check_eq(saved("transfer-replace"), path)
	check_eq(cloud.owner, "account-b")
	check_ne(cloud.slot_id, old)
	var previous := CloudSaveStore.new(directory)
	previous.open_library("account-a")
	check_eq(previous.slots()[0].manual_path, "")
	check_eq(previous.slots()[0].continuation_sha256, old_hash)
	check_eq(row().manual_path, path)

func test_background_starts_eligible_upload_without_another_frame() -> void:
	_verify_account("account-a")
	var fake = coordinator._platform
	fake.finish(fake.last("prepare_zone"))
	coordinator.advance(Time.get_ticks_msec())
	fake.finish(fake.last("changes"), {"records":[], "deleted_ids":[], "token":PackedByteArray([1]), "more":false})
	coordinator.advance(Time.get_ticks_msec())
	check_eq(fake.count("save"), 0)
	host.sim.city.funds -= 17
	var expected := host.sim.city.funds
	check_eq(host.suspend_for_background(directory.path_join("suspended.sc2d")), OK)
	check_eq(fake.count("save"), 1, "background return cannot depend on another engine frame")
	var request: Dictionary = fake.last("save")
	if request.is_empty(): return
	check_eq(SaveFormat.load(request.args.pending.continuation.path).city.funds, expected)
	check(host.files.has_unsaved_changes())
	check_eq(host.save_path, "")

func reserved_continuation() -> Dictionary:
	_verify_account("account-a")
	host.sim.city.funds -= 1
	cloud.capture(&"test")
	var id := cloud.slot_id
	var continuation: String = row().path
	check(host.load_city(continuation))
	check_eq(cloud.slot_id, id)
	check(not host.save_path.is_empty())
	check(not FileAccess.file_exists(host.save_path))
	return {"id":id, "reserved":host.save_path}

func test_review_reserved_first_save_as_names_existing_slot() -> void:
	var info := reserved_continuation()
	var path := saved("reserved-first-name")
	check_eq(cloud.slot_id, info.id)
	var reopened := CloudSaveStore.new(directory)
	reopened.open_library("account-a")
	check_eq(reopened.slots().size(), 1)
	check_eq(reopened.slots()[0].manual_path, path)
	check(not FileAccess.file_exists(info.reserved))

func test_review_reserved_first_replace_retires_with_pin_atomically() -> void:
	var info := reserved_continuation()
	var work := store.pending()[0]
	store.begin_upload(info.id, work.generation)
	var path := CityFileFlow.save_path_for("review-replace-" + CloudSaveTypes.uuid())
	paths.append(path)
	SaveFormat.save(path, flat_city())
	var target := store.create_slot()
	store.stage(target, path, path)
	check_eq(host.files.save_city_as(path.get_file().get_basename()), path)
	check_eq(cloud.slot_id, target)
	var reopened := CloudSaveStore.new(directory)
	reopened.open_library("account-a")
	check_eq(reopened.slots().size(), 1)
	check_eq(reopened.slots()[0].slot_id, target)
	check_eq(reopened.inflight()[0].slot_id, info.id)
	var tombstone: Dictionary = {}
	for pending in reopened.pending():
		if pending.slot_id == info.id: tombstone = pending
	check(tombstone.get("tombstone", false))
	check_eq(tombstone.get("parent_commit_id"), work.commit_id)

func test_review_migration_repairs_claimed_empty_target_after_restart() -> void:
	_verify_account("account-a")
	saved("repair-source")
	var source := cloud.slot_id
	var fault := use_failing_store()
	var target := fault.create_slot()
	var path := CityFileFlow.save_path_for("review-empty-" + CloudSaveTypes.uuid())
	paths.append(path)
	SaveFormat.save(path, host.sim.city)
	fault.fail = true
	check(fault.stage(target, path, path).is_empty())
	var reopened := CloudSaveStore.new(directory)
	reopened.open_library("account-a")
	check_eq(reopened.migrate_personal_file(path), OK)
	var matches: Array[String] = []
	for entry in reopened.slots():
		if CloudSaveSession._same_path(entry.manual_path, path): matches.append(entry.slot_id)
	check_eq(matches, [target] as Array[String])
	check_eq(reopened.slots().size(), 2)
	check_ne(source, target)

func test_review_migration_before_manual_retry_keeps_one_destination() -> void:
	_verify_account("account-a")
	var source_path := saved("migration-source")
	var source := cloud.slot_id
	var fault := use_failing_store()
	var path := CityFileFlow.save_path_for("review-interleave-" + CloudSaveTypes.uuid())
	paths.append(path)
	# Allow destination creation, then fail its actual journal payload write.
	fault.writes_before_failure = 1
	host.sim.city.funds -= 4
	check_eq(host.files.save_city_as(path.get_file().get_basename()), path)
	var target: String = cloud._pending_manual.target
	check(not target.is_empty())
	fault.writes_before_failure = -1
	# Simulate the exact post-inventory migration before the next capture.
	coordinator._initial_inventory_complete = true
	check_eq(coordinator.migrate_personal_saves([SaveFormat.read_header(path)]), OK)
	host.sim.city.funds -= 6
	check_eq(cloud.capture(&"test"), OK)
	check_eq(cloud.slot_id, target)
	var reopened := CloudSaveStore.new(directory)
	reopened.open_library("account-a")
	var associations := 0
	for entry in reopened.slots():
		if CloudSaveSession._same_path(entry.manual_path, path): associations += 1
	check_eq(associations, 1)
	check_eq(reopened.slots().size(), 2)
	check_eq(row(source).manual_path, source_path)
	check_eq(row(target).manual_sha256, FileAccess.get_sha256(path))
	check_ne(row(target).manual_sha256, row(target).continuation_sha256)
	# A competing direct publication cannot create a second filename binding.
	var duplicate := reopened.create_slot()
	check(reopened.stage(duplicate, path, ProjectSettings.globalize_path(path)).is_empty())

func test_review_pending_successful_first_save_is_manual_intent() -> void:
	reserved_continuation()
	var source := cloud.slot_id
	var fault := use_failing_store()
	fault.fail = true
	var first := saved("pending-first-manual")
	check(not first.is_empty())
	check(cloud._pending_manual.unnamed)
	var second := saved("pending-second-manual")
	check(not second.is_empty())
	check(not cloud._pending_manual.unnamed, "the earlier successful local manual write counts even while publication is pending")
	check_eq(cloud.slot_id, source)
