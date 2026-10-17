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
func test_changed_city_checkpoints_at_60_seconds() -> void:
	var count: int = host.files.snapshots
	host.sim.city.funds -= 1
	cloud.tick(59.0)
	check_eq(row().generation, 0)
	check_eq(host.files.snapshots, count, "no per-frame serialization")
	cloud.tick(1.0)
	check_eq(row().generation, 1)
func test_unchanged_city_does_not_rewrite() -> void:
	cloud.tick(60.0)
	check_eq(row().generation, 0)
	host.sim.city.funds -= 1
	cloud.tick(60.0)
	var before := row()
	host.sim.set_speed(GameClock.Speed.FAST)
	cloud.tick(60.0)
	check_eq(row().generation, before.generation)
func test_checkpoint_leaves_manual_dirty_flag_and_file_unchanged() -> void:
	var path := saved("manual")
	var bytes := FileAccess.get_file_as_bytes(path)
	host.sim.city.funds -= 300
	check_eq(cloud.capture(&"test"), OK)
	check(host.files.has_unsaved_changes())
	check_eq(FileAccess.get_file_as_bytes(path), bytes)
	check_eq(host.save_path, path)
func test_unnamed_city_keeps_slot_on_first_save() -> void:
	var original := cloud.slot_id
	var path := saved("first")
	check_eq(cloud.slot_id, original)
	check_eq(row().manual_path, path)
func test_save_as_new_path_forks_identity() -> void:
	var path := saved("source")
	var original := cloud.slot_id
	var bytes := FileAccess.get_file_as_bytes(path)
	host.sim.city.funds -= 10
	var destination := saved("destination")
	check_ne(cloud.slot_id, original)
	check_eq(row(original).manual_path, path)
	check_eq(row().manual_path, destination)
	check_eq(FileAccess.get_file_as_bytes(path), bytes)
func test_cloud_load_retains_slot_and_opens_paused() -> void:
	var path := saved("continue")
	var original := cloud.slot_id
	host.sim.city.funds -= 100
	cloud.capture(&"test")
	var continuation: String = row().path
	check(host.load_city(continuation))
	check_eq(cloud.slot_id, original)
	check_eq(host.save_path, path)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	check(host.files.has_unsaved_changes(), "retained manual baseline remains distinct")
func _incoming_while_active(casino: bool = false) -> Dictionary:
	_verify_account("account-a")
	cloud.begin_session()
	var path := saved("active-download")
	var original := cloud.slot_id
	var work := store.pending()[0]
	store.begin_upload(original, work.generation)
	check_eq(store.acknowledge(original, work.generation, work.commit_id, PackedByteArray([1]), "old-tag"), OK)
	var remote_city := flat_city()
	remote_city.name = host.sim.city.name
	remote_city.funds -= 999
	var incoming := directory.path_join("remote.sc2d")
	check_eq(SaveFormat.save(incoming, remote_city, host.sim.snapshot()), OK)
	var remote := {"slot_id":original, "commit_id":CloudSaveTypes.uuid(), "change_tag":"new-tag", "system_fields":PackedByteArray([2]), "continuation_sha256":FileAccess.get_sha256(incoming), "manual_sha256":FileAccess.get_sha256(path), "tombstone":false, "metadata":{}}
	if casino: _open_round()
	var fake = coordinator._platform
	fake.finish(fake.last("prepare_zone"))
	coordinator.advance(Time.get_ticks_msec())
	fake.finish(fake.last("changes"), {"records":[remote], "deleted_ids":[], "token":PackedByteArray([1]), "more":false})
	coordinator.advance(Time.get_ticks_msec())
	var download: Dictionary = fake.last("download")
	if not download.is_empty():
		fake.finish(download, {"downloaded":{"continuation":incoming, "manual":path}})
		coordinator.advance(Time.get_ticks_msec())
	return {"original":original, "manual":path, "remote":remote}
func test_active_city_not_replaced_by_download() -> void:
	var active := host.sim.city
	var funds := active.funds
	var info := _incoming_while_active()
	check_eq(host.sim.city, active)
	check_eq(host.sim.city.funds, funds)
	check_ne(cloud.slot_id, info.original, "unchanged active city retains its true old ancestry as an independent branch")
	host.sim.city.funds -= 2
	check_eq(cloud.capture(&"test"), OK)
	var pending := store.pending()
	var branch: Dictionary = {}
	for work in pending:
		if work.slot_id == cloud.slot_id: branch = work
	check(not branch.is_empty())
	check_ne(branch.get("parent_commit_id", ""), info.remote.commit_id)
	check_eq(row(info.original).continuation_sha256, info.remote.continuation_sha256)
	check_eq(row(info.original).manual_path, "", "downloaded branch cannot share active named destination")
	check_eq(row().manual_path, info.manual)
func test_remote_advance_then_manual_save_preserves_both_branches() -> void:
	var info := _incoming_while_active()
	host.sim.city.funds -= 3
	check_eq(host.files.save_city(), OK)
	check_ne(cloud.slot_id, info.original)
	check_eq(row(info.original).continuation_sha256, info.remote.continuation_sha256)
	check_eq(row().manual_sha256, FileAccess.get_sha256(info.manual))
func test_checkpoint_defers_unsettled_casino() -> void:
	_open_round()
	check_eq(cloud.capture(&"periodic"), ERR_BUSY)
	check(not host.notice_dialog.is_open(), "busy round is not a disk error")
	check_eq(row().generation, 0)
func _open_round() -> void:
	CasinoTableOverlay.animation_scale = 0.0
	check(host.open_casino_table(&"arcology_comstock", &"blackjack", CasinoRng.new(3)))
	host.casino_overlay.game.rig([CasinoDeck.card(10, 0), CasinoDeck.card(9, 1), CasinoDeck.card(5, 2), CasinoDeck.card(8, 3)])
	host.casino_overlay.press_chip(0)
	host.casino_overlay.perform_action(&"deal")
	check(host.casino_overlay.round_in_progress())
	CasinoTableOverlay.animation_scale = 1.0
func test_background_capture_follows_existing_settlement() -> void:
	_open_round()
	var path := directory.path_join("background.sc2d")
	check_eq(host.suspend_for_background(path), OK)
	check(not host.casino_overlay.round_in_progress())
	var result := SaveFormat.load(row().path)
	check(result.ok)
	check_eq(result.city.funds, host.sim.city.funds)
func test_snapshot_does_not_advance_rng_or_mod_callbacks() -> void:
	host.mod_progress.restore({})
	var runtime := host.sim.snapshot().duplicate(true)
	var mods := host.explore_progress_snapshot().duplicate(true)
	seed(12345)
	var expected := randi()
	seed(12345)
	host.sim.city.funds -= 1
	cloud.capture(&"test")
	check_eq(randi(), expected)
	check_eq(host.sim.snapshot(), runtime)
	check_eq(host.explore_progress_snapshot(), mods)
func test_first_save_replace_binds_existing_destination_across_restart() -> void:
	var path := saved("replace")
	var target := cloud.slot_id
	host.begin_city(flat_city(), {}, 44, null)
	host.save_path = ""
	cloud.begin_session()
	var redundant := cloud.slot_id
	host.sim.city.funds -= 7
	cloud.capture(&"test")
	check_eq(saved("replace"), path)
	check_eq(cloud.slot_id, target)
	check(row(redundant).is_empty(), "redundant unnamed continuation retired")
	check(host.load_city(path))
	check_eq(cloud.slot_id, target)
func test_save_as_replace_binds_existing_destination() -> void:
	var destination := saved("replace-target")
	var target := cloud.slot_id
	var source := saved("replace-source")
	var source_id := cloud.slot_id
	host.sim.city.funds -= 3
	check_eq(saved("replace-target"), destination)
	check_eq(cloud.slot_id, target)
	check_eq(row(source_id).manual_path, source)
func test_foreground_timer_and_desktop_background_hook() -> void:
	host.sim.city.funds -= 1
	host._window_in_foreground = false
	cloud.tick(120.0)
	check_eq(row().generation, 0)
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check_eq(row().generation, 1)
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
func test_founding_keeps_identity_and_final_editing_shape() -> void:
	host.start_new_city({"seed":123, "name":"Cloud terrain"}, flat_city())
	var id := cloud.slot_id
	host.sim.city.funds -= 1
	cloud.capture(&"test")
	check_eq(SaveFormat.load(row().path).stage, SaveFormat.STAGE_EDITING)
	check(host.found_city())
	check_eq(cloud.slot_id, id)
func _verify_account(value: String) -> void:
	coordinator.set_enabled(true)
	coordinator.advance(Time.get_ticks_msec())
	var fake = coordinator._platform
	fake.finish(fake.last("account"), {"owner": value})
	coordinator.advance(Time.get_ticks_msec())
	check_eq(coordinator.status().owner, value)
func test_delayed_account_keeps_genuinely_unowned_session() -> void:
	var id := cloud.slot_id
	host.sim.city.funds -= 2
	check_eq(cloud.capture(&"test"), OK)
	_verify_account("account-a")
	check_eq(cloud.capture(&"test"), OK)
	check_eq(row().generation, 1, "pre-account unnamed checkpoint is adopted without rewriting")
	check_eq(cloud.owner, "account-a")
	check_eq(cloud.slot_id, id)
	check_eq(store.slots().size(), 1, "genuinely unowned progress adopted once")
	check_eq(cloud._local.slots().size(), 1)
func test_revocation_never_redirects_old_city_to_new_account() -> void:
	_verify_account("account-a")
	cloud.begin_session()
	var id := cloud.slot_id
	host.sim.city.funds -= 1
	cloud.capture(&"test")
	var fake = coordinator._platform
	fake.account_changed(coordinator.status().epoch)
	coordinator.advance(Time.get_ticks_msec())
	host.sim.city.funds -= 1
	check_eq(cloud.capture(&"test"), ERR_UNAUTHORIZED)
	fake.finish(fake.last("account"), {"owner":"account-b"})
	coordinator.advance(Time.get_ticks_msec())
	check_eq(cloud.capture(&"test"), ERR_UNAUTHORIZED)
	check_eq(cloud.slot_id, id)
	check_eq(cloud.owner, "account-a")
	check_eq(store.slots().size(), 0)
	var path := saved("revoked-local")
	check(FileAccess.file_exists(path), "local manual Save succeeds despite cloud revocation")
func test_durable_fork_rebinds_only_active_slot() -> void:
	_verify_account("account-a")
	cloud.begin_session()
	host.sim.city.funds -= 1
	cloud.capture(&"test")
	var original := cloud.slot_id
	var fork := store.fork_pending(original, 1)
	check(not fork.is_empty())
	coordinator.slot_forked.emit(original, fork)
	check_eq(cloud.slot_id, fork)
	host.sim.city.funds -= 1
	check_eq(cloud.capture(&"test"), OK)
	var reopened := CloudSaveStore.new(directory)
	check_eq(reopened.open_library("account-a"), OK)
	var entries := reopened.slots()
	var found := false
	for entry in entries:
		if entry.slot_id == fork:
			found = true
			check_eq(entry.generation, 2)
	check(found)
func test_remote_removal_preserves_active_city_and_blocks_resurrection() -> void:
	_verify_account("account-a")
	cloud.begin_session()
	var city := host.sim.city
	coordinator.slot_removed.emit(cloud.slot_id)
	host.sim.city.funds -= 5
	check_eq(cloud.capture(&"test"), ERR_UNAUTHORIZED)
	check_eq(host.sim.city, city)
func test_remote_manual_destination_avoids_existing_named_file() -> void:
	var existing := saved("remote-collision")
	var bytes := FileAccess.get_file_as_bytes(existing)
	var manual: Dictionary = row().manual
	var id := cloud._local.create_slot()
	host.sim.city.funds -= 100
	var incoming := directory.path_join("incoming.sc2d")
	check_eq(SaveFormat.save(incoming, host.sim.city, host.sim.snapshot()), OK)
	var work := cloud._local.stage(id, incoming, manual.path)
	check(not work.is_empty())
	# Remote rows retain an asset, but do not bring another device's local path.
	check_eq(cloud._local.bind_manual_path(id, existing), ERR_ALREADY_EXISTS)
	var next := cloud._local._state.duplicate(true)
	next.slots[id].manual_path = ""
	check_eq(cloud._local._commit(next), OK)
	check(host.load_city(work.continuation.path))
	check_eq(cloud.slot_id, id)
	check_ne(host.save_path, work.continuation.path)
	check_ne(host.save_path, existing)
	check(FileAccess.file_exists(host.save_path))
	paths.append(host.save_path)
	check(host.files.has_unsaved_changes())
	check_eq(FileAccess.get_file_as_bytes(existing), bytes)
class FailingStore extends CloudSaveStore:
	var fail := false
	func _write_journal(bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail else super._write_journal(bytes)
func test_manual_binding_is_durable_collision_safe_and_atomic() -> void:
	var library := FailingStore.new(directory.path_join("binding"))
	check_eq(library.open_library(""), OK)
	var a := library.create_slot()
	var b := library.create_slot()
	var path := CityFileFlow.save_path_for("binding-reserved")
	check_eq(library.bind_manual_path(a, path), OK)
	check_eq(library.bind_manual_path(b, ProjectSettings.globalize_path(path)), ERR_ALREADY_EXISTS)
	check_eq(library.bind_manual_path(a, path), OK)
	var before := FileAccess.get_file_as_bytes(library.journal_path())
	library.fail = true
	check_eq(library.bind_manual_path(a, path + ".sc2d"), ERR_CANT_CREATE)
	check_eq(FileAccess.get_file_as_bytes(library.journal_path()), before)
	var reopened := CloudSaveStore.new(directory.path_join("binding"))
	check_eq(reopened.open_library(""), OK)
	check_eq(reopened.slots()[0].manual_path, path)
	check_eq(reopened.slots()[0].generation, 0)
	check_eq(library.bind_manual_path(a, directory.path_join("binding/payload.sc2d")), ERR_INVALID_PARAMETER)

func test_casino_download_retains_complete_baseline_before_fork() -> void:
	var before := host.sim.city.funds
	var info := _incoming_while_active(true)
	check(host.casino_overlay.round_in_progress())
	check_ne(cloud.slot_id, info.original)
	check_eq(SaveFormat.load(row().path).city.funds, before, "fork never contains an unsettled stake")
	host.casino_overlay.resolve_round_now()
	check_eq(cloud.capture(&"test"), OK)
	check_eq(SaveFormat.load(row().path).city.funds, host.sim.city.funds)
func test_late_own_ack_preserves_active_identity_and_new_checkpoint() -> void:
	_verify_account("account-a")
	cloud.begin_session()
	saved("late-ack")
	var id := cloud.slot_id
	var fake = coordinator._platform
	fake.finish(fake.last("prepare_zone"))
	coordinator.advance(Time.get_ticks_msec())
	var request: Dictionary = fake.last("save")
	check(not request.is_empty())
	host.sim.city.funds -= 1
	check_eq(cloud.capture(&"test"), OK)
	fake.finish(request, {"commit_id":request.args.pending.commit_id, "change_tag":"ack", "system_fields":PackedByteArray([3])})
	coordinator.advance(Time.get_ticks_msec())
	check_eq(cloud.slot_id, id)
	check_eq(row().generation, 2)
	check_eq(store.pending()[0].parent_commit_id, request.args.pending.commit_id)
func test_revalidated_deletion_and_tombstone_preserve_active_manual_branch() -> void:
	for tombstone in [false, true]:
		if coordinator.status().owner.is_empty(): _verify_account("account-a")
		cloud.begin_session()
		var path := saved("removed-" + str(tombstone))
		var id := cloud.slot_id
		var work: Dictionary = {}
		for item in store.pending():
			if item.slot_id == id: work = item
		store.begin_upload(id, work.generation)
		check_eq(store.acknowledge(id, work.generation, work.commit_id, PackedByteArray([1]), "old"), OK)
		var remote := {"slot_id":id, "commit_id":CloudSaveTypes.uuid(), "change_tag":"removed", "system_fields":PackedByteArray([2]), "continuation_sha256":"", "manual_sha256":"", "tombstone":true, "metadata":{}}
		# Exercise the authoritative no-asset publication boundary directly with
		# the already-revalidated inventory, independently of the asset lane.
		coordinator._page = {"items":[remote if tombstone else {"deleted":true, "slot_id":id}], "token":PackedByteArray(), "more":false, "removal_verified":id}
		coordinator._process_page()
		check_ne(cloud.slot_id, id)
		check_eq(row().manual_path, path)
		check(FileAccess.file_exists(row().manual.path))
		check_eq(row(id), {})
		check_eq(cloud.capture(&"test"), OK)

func test_continuation_only_destinations_are_reserved_across_restart_and_first_save() -> void:
	var incoming := directory.path_join("same-name.sc2d")
	host.sim.city.name = "Cloud identical title"
	check_eq(SaveFormat.save(incoming, host.sim.city, host.sim.snapshot()), OK)
	var first := cloud._local.create_slot()
	var second := cloud._local.create_slot()
	var a := cloud._local.stage(first, incoming)
	var b := cloud._local.stage(second, incoming)
	check(host.load_city(a.continuation.path))
	var first_path := host.save_path
	check(host.files.has_unsaved_changes())
	check(not FileAccess.file_exists(first_path))
	check(host.load_city(b.continuation.path))
	var second_path := host.save_path
	check(host.files.has_unsaved_changes())
	check(not FileAccess.file_exists(second_path))
	check_ne(first_path, second_path, "same-name independent continuations reserve different absent destinations")
	var reopened := CloudSaveStore.new(directory)
	check_eq(reopened.open_library(""), OK)
	for entry in reopened.slots():
		if entry.slot_id == first: check_eq(entry.manual_path, first_path)
		if entry.slot_id == second: check_eq(entry.manual_path, second_path)
	cloud._local = reopened
	check(host.load_city(a.continuation.path))
	check_eq(host.save_path, first_path)
	check(host.files.has_unsaved_changes())
	check_eq(host.files.save_city(), OK)
	check_eq(cloud.slot_id, first)
	check(host.load_city(b.continuation.path))
	check_eq(host.save_path, second_path)
	check(host.files.has_unsaved_changes())
	check_eq(host.files.save_city(), OK)
	check_eq(cloud.slot_id, second)
	paths.append_array([first_path, second_path])

func _failed_save_as_transition(replace: bool) -> void:
	var target_id := ""
	var destination := CityFileFlow.save_path_for("cloud-session-failed-target")
	if replace:
		saved("failed-target")
		target_id = cloud.slot_id
	var source := saved("failed-source")
	var source_id := cloud.slot_id
	var before := row(source_id)
	var source_bytes := FileAccess.get_file_as_bytes(source)
	var failing := FailingStore.new(directory)
	check_eq(failing.open_library(""), OK)
	cloud._local = failing
	failing.fail = true
	host.sim.city.funds -= 5
	check_eq(saved("failed-target"), destination, "optional cloud failure cannot fail local Save As")
	check_eq(host.save_path, destination)
	check(not host.files.has_unsaved_changes(), "local manual baseline remains clean")
	var destination_bytes := FileAccess.get_file_as_bytes(destination)
	host.sim.city.funds -= 7
	check_ne(cloud.capture(&"background"), OK, "capture remains blocked while destination transition cannot publish")
	failing.fail = false
	check_eq(cloud.capture(&"periodic"), OK)
	check_ne(cloud.slot_id, source_id)
	if replace: check_eq(cloud.slot_id, target_id)
	check_eq(row(source_id).continuation_sha256, before.continuation_sha256)
	check_eq(row(source_id).manual_sha256, before.manual_sha256)
	check_eq(row(source_id).manual_path, source)
	check_eq(FileAccess.get_file_as_bytes(source), source_bytes)
	check_eq(row().manual_path, destination)
	check_eq(FileAccess.get_file_as_bytes(destination), destination_bytes)
	check_eq(SaveFormat.load(row().path).city.funds, host.sim.city.funds)
	check(host.files.has_unsaved_changes(), "retry does not mark edits since local Save As saved")

func test_save_as_creation_failure_retries_destination_without_advancing_source() -> void:
	_failed_save_as_transition(false)

func test_replace_staging_failure_retries_destination_without_advancing_source() -> void:
	_failed_save_as_transition(true)

func test_failed_replace_automatically_branches_if_destination_head_advanced() -> void:
	var destination := saved("advanced-target")
	var original := cloud.slot_id
	var work := cloud._local.pending()[0]
	cloud._local.begin_upload(original, work.generation)
	check_eq(cloud._local.acknowledge(original, work.generation, work.commit_id, PackedByteArray([1]), "before"), OK)
	var source := saved("advanced-source")
	var source_id := cloud.slot_id
	var source_before := row(source_id)
	var failing := FailingStore.new(directory)
	check_eq(failing.open_library(""), OK)
	cloud._local = failing
	failing.fail = true
	host.sim.city.funds -= 5
	check_eq(saved("advanced-target"), destination)
	check(not host.files.has_unsaved_changes())
	var manual_hash := FileAccess.get_sha256(destination)
	failing.fail = false
	var other := flat_city()
	other.funds -= 700
	var incoming := directory.path_join("advanced-remote.sc2d")
	check_eq(SaveFormat.save(incoming, other, host.sim.snapshot()), OK)
	var remote := {"slot_id":original, "commit_id":CloudSaveTypes.uuid(), "change_tag":"advanced", "system_fields":PackedByteArray([2]), "continuation_sha256":FileAccess.get_sha256(incoming), "manual_sha256":"", "tombstone":false, "metadata":{}}
	check_eq(failing.publish_remote(remote, {"continuation":incoming}), OK)
	host.sim.city.funds -= 7
	var journal_before := FileAccess.get_file_as_bytes(failing.journal_path())
	failing.fail = true
	check_ne(cloud.capture(&"periodic"), OK)
	check_eq(FileAccess.get_file_as_bytes(failing.journal_path()), journal_before, "failed branch publication keeps the complete prior journal")
	failing.fail = false
	check_eq(cloud.capture(&"periodic"), OK, "recovered writes automatically retain both destination branches")
	check_ne(cloud.slot_id, original)
	check_ne(cloud.slot_id, source_id)
	check_eq(row(original).continuation_sha256, remote.continuation_sha256)
	check_eq(row(original).manual_path, "")
	check_eq(row(source_id).continuation_sha256, source_before.continuation_sha256)
	check_eq(row(source_id).manual_path, source)
	check_eq(row().manual_path, destination)
	check_eq(row().manual_sha256, manual_hash)
	check_eq(SaveFormat.load(row().path).city.funds, host.sim.city.funds)
	check(host.files.has_unsaved_changes())
	for pending in failing.pending():
		if pending.slot_id == cloud.slot_id:
			check_eq(pending.parent_commit_id, "", "independent branch never inherits the advanced remote parent")
	var reopened := CloudSaveStore.new(directory)
	check_eq(reopened.open_library(""), OK)
	var found := 0
	for entry in reopened.slots():
		if entry.slot_id in [original, source_id, cloud.slot_id]: found += 1
	check_eq(found, 3, "all three identities survive restart")
