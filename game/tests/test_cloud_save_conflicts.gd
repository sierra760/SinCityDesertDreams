# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"

class FailingStore extends CloudSaveStore:
	var fail_write := false
	func _write_journal(bytes: PackedByteArray) -> Error:
		return ERR_FILE_CANT_WRITE if fail_write else super._write_journal(bytes)

var _roots: Array[String] = []

func _root() -> String:
	var path := "user://cloud-conflict-tests/%d-%d" % [Time.get_ticks_usec(), _roots.size()]
	_roots.append(path)
	DirAccess.make_dir_recursive_absolute(path)
	return path

func _city(root: String, title: String) -> String:
	var path := root.path_join(title + ".sc2d")
	var city := flat_city()
	city.name = title
	check_eq(SaveFormat.save(path, city), OK)
	return path

func _store(root: String) -> CloudSaveStore:
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	return store

func _remote(work: Dictionary, tag: String = "remote-tag") -> Dictionary:
	return {"slot_id": work.slot_id, "commit_id": work.commit_id,
		"change_tag": tag, "system_fields": PackedByteArray([7, 8]),
		"continuation_sha256": work.continuation.get("sha256", ""),
		"manual_sha256": work.manual.get("sha256", ""), "tombstone": work.tombstone,
		"metadata": {"name": "Remote city"}}

func _pending(store: CloudSaveStore, id: String) -> Dictionary:
	for work in store.pending():
		if work.slot_id == id: return work
	return {}

func _slot(store: CloudSaveStore, id: String) -> Dictionary:
	for row in store.slots():
		if row.slot_id == id: return row
	return {}

func after_all() -> void:
	for root in _roots: _remove_tree(root)

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	for child in dir.get_directories(): _remove_tree(path.path_join(child))
	for child in dir.get_files(): DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)

func test_repeated_commit_is_acknowledged() -> void:
	var root := _root()
	var store := _store(root)
	var work := store.stage(store.create_slot(), _city(root, "Repeated"))
	check_eq(CloudSavePolicy.decide(work, _remote(work)).action, "acknowledge")

func test_same_payload_is_deduplicated() -> void:
	var root := _root()
	var store := _store(root)
	var path := _city(root, "Duplicate")
	var work := store.stage(store.create_slot(), path, path)
	var remote := _remote(work)
	remote.commit_id = CloudSaveTypes.uuid()
	check_eq(CloudSavePolicy.decide(work, remote).action, "acknowledge")
	remote.manual_sha256 = "0".repeat(64)
	check_eq(CloudSavePolicy.decide(work, remote).action, "fork", "manual differences are real divergence")
	remote = _remote(work)
	remote.continuation_sha256 = "0".repeat(64)
	check_eq(CloudSavePolicy.decide(work, remote).action, "fork", "even equal UUIDs cannot erase different contents")
	var discarded := store.stage(work.slot_id, "", "", true)
	remote = _remote(discarded)
	remote.commit_id = CloudSaveTypes.uuid()
	check_eq(CloudSavePolicy.decide(discarded, remote).action, "acknowledge")
	remote.manual_sha256 = "1".repeat(64)
	check_eq(CloudSavePolicy.decide(discarded, remote).action, "fork")

func test_conditional_upload_requires_actual_parent_tag_and_commit() -> void:
	var root := _root()
	var store := _store(root)
	var id := store.create_slot()
	var first := store.stage(id, _city(root, "Parent"))
	check_eq(CloudSavePolicy.decide(first, {}).action, "upload")
	check(not store.begin_upload(id, first.generation).is_empty())
	check_eq(store.acknowledge(id, first.generation, first.commit_id, PackedByteArray([1]), "parent-tag"), OK)
	var next := store.stage(id, _city(root, "Changed"))
	var parent := _remote(first, "parent-tag")
	parent.system_fields = PackedByteArray([99])
	check_eq(CloudSavePolicy.decide(next, parent).action, "upload", "archives do not define equality")
	parent.change_tag = "changed-elsewhere"
	check_eq(CloudSavePolicy.decide(next, parent).action, "fork")
	check_eq(CloudSavePolicy.decide(next, {}).action, "fork", "remote deletion cannot silently reset an established identity")
	parent.change_tag = "parent-tag"
	parent.commit_id = CloudSaveTypes.uuid()
	check_eq(CloudSavePolicy.decide(next, parent).action, "ignore", "await pinned parent reconciliation")

func test_library_refresh_and_invalid_rows_do_not_change_pending_baseline() -> void:
	var root := _root()
	var store := _store(root)
	var work := store.stage(store.create_slot(), _city(root, "Local"))
	var remote := _remote(work)
	remote.commit_id = CloudSaveTypes.uuid()
	remote.continuation_sha256 = "0".repeat(64)
	var before := work.duplicate(true)
	check_eq(CloudSavePolicy.decide(work, remote).action, "fork")
	check_eq(work, before, "pure decisions retain actual baseline")
	check_eq(store.publish_remote(remote, {}), ERR_BUSY)
	check_eq(_pending(store, work.slot_id), before)
	check_eq(CloudSavePolicy.decide({}, remote).action, "download")
	check_eq(CloudSavePolicy.decide({}, {}).action, "ignore")
	check_eq(CloudSavePolicy.decide(work, {"slot_id": work.slot_id}).action, "ignore")
	remote.slot_id = CloudSaveTypes.uuid()
	check_eq(CloudSavePolicy.decide(work, remote).action, "ignore")

func test_divergent_baselines_preserve_two_versions() -> void:
	var root := _root()
	var store := _store(root)
	var id := store.create_slot()
	var local := store.stage(id, _city(root, "Local branch"), _city(root, "Local manual"))
	var remote_path := _city(root, "Remote branch")
	var remote_manual := _city(root, "Remote manual")
	var remote := _remote(local)
	remote.commit_id = CloudSaveTypes.uuid()
	remote.continuation_sha256 = FileAccess.get_sha256(remote_path)
	remote.manual_sha256 = FileAccess.get_sha256(remote_manual)
	check_eq(CloudSavePolicy.decide(local, remote).action, "fork")
	var branch := store.fork_pending(id, local.generation)
	check_ne(branch, "")
	check(_pending(store, id).is_empty(), "local pending moves off the remote identity")
	check_eq(store.publish_remote(remote, {"continuation": remote_path, "manual": remote_manual}), OK)
	var reopened := _store(root)
	check_eq(reopened.slots().size(), 2)
	check_eq(_slot(reopened, id).continuation_sha256, remote.continuation_sha256)
	check_eq(_slot(reopened, branch).continuation_sha256, local.continuation.sha256)
	check_eq(_slot(reopened, id).manual_sha256, remote.manual_sha256)
	check_eq(_slot(reopened, branch).manual_sha256, local.manual.sha256)
	check_eq(_slot(reopened, branch).conflict_origin, id)
	check_eq(reopened.fork_pending(id, local.generation), branch, "remote publication retains original conflict mapping")

func test_older_ack_cannot_clear_newer_generation() -> void:
	var root := _root()
	var store := _store(root)
	var id := store.create_slot()
	var first := store.stage(id, _city(root, "In flight"))
	check(not store.begin_upload(id, first.generation).is_empty())
	var second := store.stage(id, _city(root, "Newer"))
	check_eq(second.parent_commit_id, first.commit_id, "unsent snapshots descend from durable send")
	check_eq(store.acknowledge(id, second.generation, second.commit_id, PackedByteArray([9]), "wrong"), ERR_INVALID_PARAMETER)
	check_eq(_pending(store, id).baseline_tag, "")
	check_eq(store.acknowledge(id, first.generation, first.commit_id, PackedByteArray([1]), "first-tag"), OK)
	check_eq(_pending(store, id).commit_id, second.commit_id)
	check_eq(_pending(store, id).parent_commit_id, first.commit_id)
	check_eq(_pending(store, id).baseline_tag, "first-tag")
	check_eq(_pending(store, id).baseline, PackedByteArray([1]))
	check_eq(store.inflight().size(), 0)

func test_retry_reuses_persisted_branch_id() -> void:
	var root := _root()
	var store := _store(root)
	var id := store.create_slot()
	var work := store.stage(id, _city(root, "Retry"))
	var branch := store.fork_pending(id, work.generation)
	var branch_commit: String = _pending(store, branch).commit_id
	check_eq(store.fork_pending(id, work.generation), branch)
	var reopened := _store(root)
	check_eq(reopened.fork_pending(id, work.generation), branch)
	check_eq(_pending(reopened, branch).commit_id, branch_commit)
	check_eq(reopened.slots().size(), 2)
	check_eq(reopened.pending().size(), 1)
	check_eq(_pending(reopened, branch).baseline_tag, "")
	check_eq(_pending(reopened, branch).parent_commit_id, "")

func test_fork_moves_descendants_and_preserves_uncertain_pin_until_confirmed() -> void:
	var root := _root()
	var store := _store(root)
	var id := store.create_slot()
	var first := store.stage(id, _city(root, "Rejected send"))
	check(not store.begin_upload(id, first.generation).is_empty())
	var latest := store.stage(id, _city(root, "Continued locally"))
	var branch := store.fork_pending(id, first.generation)
	check_eq(store.fork_pending(id, latest.generation), branch, "moved descendant shares the persisted conflict branch")
	check_eq(_pending(store, branch).continuation.sha256, latest.continuation.sha256)
	check(_pending(store, id).is_empty())
	check_eq(store.inflight()[0].commit_id, first.commit_id)
	check(FileAccess.file_exists(first.continuation.path))
	var remote := _remote(first)
	remote.commit_id = CloudSaveTypes.uuid()
	check_eq(store.publish_remote(remote, {"continuation": first.continuation.path}), ERR_BUSY)
	check_eq(store.retire_upload(id, first.generation), OK)
	var remote_path := _city(root, "Server preserved")
	remote.continuation_sha256 = FileAccess.get_sha256(remote_path)
	check_eq(store.publish_remote(remote, {"continuation": remote_path}), OK)
	check_eq(_pending(store, branch).baseline_tag, "")
	check_eq(_pending(store, branch).parent_commit_id, "")
	var explicit := store.stage(id, remote_path)
	check_eq(explicit.slot_id, id, "opening the original remains independent; only active session rebinds")
	check_eq(explicit.parent_commit_id, remote.commit_id)

func test_discard_conflict_keeps_remote_city() -> void:
	var root := _root()
	var store := _store(root)
	var id := store.create_slot()
	var tombstone := store.stage(id, "", "", true)
	var remote := _remote(tombstone)
	var path := _city(root, "Concurrent city")
	remote.tombstone = false
	remote.commit_id = CloudSaveTypes.uuid()
	remote.continuation_sha256 = FileAccess.get_sha256(path)
	check_eq(CloudSavePolicy.decide(tombstone, remote).action, "fork")
	var branch := store.fork_pending(id, tombstone.generation)
	check_ne(branch, "")
	check_eq(store.publish_remote(remote, {"continuation": path}), OK)
	check_eq(_store(root).slots().size(), 1)
	check_eq(_slot(store, id).continuation_sha256, remote.continuation_sha256)
	check(_pending(store, branch).tombstone)

func test_equivalent_remote_ack_adopts_server_identity_and_retains_descendant() -> void:
	var root := _root()
	var store := _store(root)
	var id := store.create_slot()
	var first := store.stage(id, _city(root, "Identical content"))
	check(not store.begin_upload(id, first.generation).is_empty())
	var newer := store.stage(id, _city(root, "Newer pending"))
	var remote := _remote(first)
	remote.commit_id = CloudSaveTypes.uuid()
	check_eq(store.acknowledge_remote(id, first.generation, remote), OK)
	check_eq(store.inflight().size(), 0)
	check_eq(_pending(store, id).commit_id, newer.commit_id)
	check_eq(_pending(store, id).parent_commit_id, remote.commit_id)
	check_eq(_pending(store, id).baseline_tag, remote.change_tag)
	check_eq(_store(root).pending()[0].parent_commit_id, remote.commit_id)

func test_remote_ack_requires_pin_and_both_matching_assets() -> void:
	var root := _root()
	var store := _store(root)
	var id := store.create_slot()
	var path := _city(root, "Manual and current")
	var work := store.stage(id, path, path)
	var remote := _remote(work)
	check_eq(store.acknowledge_remote(id, work.generation, remote), ERR_INVALID_PARAMETER)
	check(not store.begin_upload(id, work.generation).is_empty())
	remote.manual_sha256 = "0".repeat(64)
	check_eq(store.acknowledge_remote(id, work.generation, remote), ERR_INVALID_PARAMETER)
	remote = _remote(work)
	remote.continuation_sha256 = "0".repeat(64)
	check_eq(store.acknowledge_remote(id, work.generation, remote), ERR_INVALID_PARAMETER, "same UUID cannot override contradictory payload metadata")
	remote = _remote(work)
	remote.tombstone = true
	check_eq(store.acknowledge_remote(id, work.generation, remote), ERR_INVALID_PARAMETER)
	check_eq(store.inflight().size(), 1)
	check_eq(_pending(store, id).commit_id, work.commit_id)

func test_failed_fork_publication_never_moves_or_reidentifies_local_work() -> void:
	var root := _root()
	var store := FailingStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var id := store.create_slot()
	var work := store.stage(id, _city(root, "Safe fork"))
	var before := FileAccess.get_file_as_bytes(store.journal_path())
	store.fail_write = true
	check_eq(store.fork_pending(id, work.generation), "")
	check_eq(FileAccess.get_file_as_bytes(store.journal_path()), before)
	check_eq(_pending(_store(root), id).commit_id, work.commit_id)

func test_unresolved_parent_blocks_descendant_dispatch_after_restart() -> void:
	var root := _root()
	var store := _store(root)
	var id := store.create_slot()
	var first := store.stage(id, _city(root, "Pinned parent"))
	check(not store.begin_upload(id, first.generation).is_empty())
	var child := store.stage(id, _city(root, "Waiting child"))
	var reopened := _store(root)
	check(reopened.begin_upload(id, child.generation).is_empty(), "unknown parent's archive cannot be dispatched")
	check_eq(reopened.begin_upload(id, first.generation).commit_id, first.commit_id)
	check_eq(reopened.acknowledge_remote(id, first.generation, _remote(first)), OK)
	var selected := reopened.begin_upload(id, child.generation)
	check(not selected.is_empty())
	if selected.is_empty(): return
	check_eq(selected.baseline_tag, "remote-tag")
	check_eq(selected.parent_commit_id, first.commit_id)

func test_confirmed_nonapplication_restores_descendant_true_parent() -> void:
	var root := _root()
	var store := _store(root)
	var id := store.create_slot()
	var first := store.stage(id, _city(root, "Confirmed rejected"))
	check(not store.begin_upload(id, first.generation).is_empty())
	var child := store.stage(id, _city(root, "Continued without rejected send"))
	check_eq(child.parent_commit_id, first.commit_id)
	check_eq(store.retire_upload(id, first.generation), OK)
	var reopened := _store(root)
	check_eq(_pending(reopened, id).parent_commit_id, "")
	check_eq(CloudSavePolicy.decide(_pending(reopened, id), {}).action, "upload")
	check_eq(reopened.begin_upload(id, child.generation).commit_id, child.commit_id)

func test_published_row_refresh_and_pending_row_normalization() -> void:
	var root := _root()
	var store := _store(root)
	var id := store.create_slot()
	var work := store.stage(id, _city(root, "Row"))
	var remote := _remote(work)
	check_eq(CloudSavePolicy.decide({"slot_id": id, "pending": work}, remote).action, "acknowledge")
	check(not store.begin_upload(id, work.generation).is_empty())
	check_eq(store.acknowledge_remote(id, work.generation, remote), OK)
	var row := _slot(store, id)
	check_eq(CloudSavePolicy.decide(row, remote).action, "ignore")
	remote.change_tag = "changed"
	check_eq(CloudSavePolicy.decide(row, remote).action, "download")
	check_eq(CloudSavePolicy.decide({"pending": "invalid"}, remote).action, "ignore")

func test_pending_library_row_cannot_request_remote_replacement_without_snapshot() -> void:
	var root := _root()
	var store := _store(root)
	var id := store.create_slot()
	var work := store.stage(id, _city(root, "Pending library row"))
	var remote := _remote(work)
	remote.commit_id = CloudSaveTypes.uuid()
	remote.continuation_sha256 = "0".repeat(64)
	check_eq(CloudSavePolicy.decide(_slot(store, id), remote).action, "ignore", "coordinator must supply exact pending or pinned snapshot")

func test_acknowledged_original_after_fork_exposes_its_actual_payload_and_state() -> void:
	var root := _root()
	var store := _store(root)
	var id := store.create_slot()
	var sent := store.stage(id, _city(root, "Uncertain original"))
	check(not store.begin_upload(id, sent.generation).is_empty())
	var latest := store.stage(id, _city(root, "Local fork head"))
	var branch := store.fork_pending(id, sent.generation)
	check_eq(store.acknowledge_remote(id, sent.generation, _remote(sent)), OK)
	check_eq(_slot(store, id).continuation_sha256, sent.continuation.sha256)
	check_eq(_slot(store, id).sync_state, "synced")
	check_eq(_pending(store, branch).continuation.sha256, latest.continuation.sha256)
	check_eq(_pending(store, branch).baseline_tag, "")

func test_moved_local_branch_exclusively_keeps_named_manual_path() -> void:
	var root := _root()
	var store := _store(root)
	var path := _city(root, "Named manual")
	var id := store.create_slot(path)
	var work := store.stage(id, path, path)
	var branch := store.fork_pending(id, work.generation)
	var reopened := _store(root)
	check_eq(_slot(reopened, branch).manual_path, path)
	check_eq(_slot(reopened, id).manual_path, "", "remote branch must allocate its own named destination")
	check_eq(_slot(reopened, branch).manual_sha256, work.manual.sha256)
	check_eq(FileAccess.get_sha256(path), work.manual.sha256, "named player file is preserved")
