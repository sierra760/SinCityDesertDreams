# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"

class FailingStore extends CloudSaveStore:
	var fail_write := false
	func _write_journal(bytes: PackedByteArray) -> Error:
		if fail_write:
			return ERR_FILE_CANT_WRITE
		return super._write_journal(bytes)

var _roots: Array[String] = []

func _root() -> String:
	var path := "user://cloud-store-tests/%d-%d" % [Time.get_ticks_usec(), _roots.size()]
	_roots.append(path)
	DirAccess.make_dir_recursive_absolute(path)
	return path

func _city(root: String, title: String = "Same city") -> String:
	var path := root.path_join("input.sc2d")
	var city := flat_city()
	city.name = title
	check_eq(SaveFormat.save(path, city), OK)
	return path

func after_all() -> void:
	for root in _roots:
		_remove_tree(root)

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	for child in dir.get_directories(): _remove_tree(path.path_join(child))
	for child in dir.get_files(): DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)

func test_slot_identity_is_not_city_name() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library(""), OK)
	var path := _city(root)
	var first := store.create_slot(path)
	var second := store.create_slot(path)
	check_ne(first, second)
	check_eq(first.length(), 36)
	check_eq(second.length(), 36)
	check_eq(store.slots().size(), 2)

func test_restart_recovers_pending_commit() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var id := store.create_slot()
	var queued := store.stage(id, _city(root))
	check(not queued.is_empty())
	var reopened := CloudSaveStore.new(root.path_join("store"))
	check_eq(reopened.open_library("account-a"), OK)
	check_eq(reopened.pending().size(), 1)
	if reopened.pending().is_empty(): return
	check_eq(reopened.pending()[0].commit_id, queued.commit_id)
	check_eq(reopened.pending()[0].continuation.sha256, queued.continuation.sha256)
	check_eq(FileAccess.get_sha256(reopened.pending()[0].continuation.path), queued.continuation.sha256)

func test_failed_journal_publish_retains_previous_library() -> void:
	var root := _root()
	var store := FailingStore.new(root.path_join("store"))
	check_eq(store.open_library(""), OK)
	var id := store.create_slot()
	var queued := store.stage(id, _city(root, "Before failure"))
	var journal := FileAccess.get_file_as_bytes(store.journal_path())
	store.fail_write = true
	check(store.stage(id, _city(root, "Failed replacement")).is_empty())
	check_eq(FileAccess.get_file_as_bytes(store.journal_path()), journal)
	check_eq(store.pending()[0].commit_id, queued.commit_id)
	var reopened := CloudSaveStore.new(root.path_join("store"))
	check_eq(reopened.open_library(""), OK)
	check_eq(reopened.pending()[0].commit_id, queued.commit_id)

func test_inflight_payload_is_immutable() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library(""), OK)
	var id := store.create_slot()
	var first := store.stage(id, _city(root, "Older queued state"))
	check(not store.begin_upload(id, first.generation).is_empty())
	var old_bytes := FileAccess.get_file_as_bytes(first.continuation.path)
	var newer := store.stage(id, _city(root, "Newer checkpoint"))
	check_eq(newer.generation, first.generation + 1)
	check_ne(first.continuation.path, newer.continuation.path)
	check_eq(FileAccess.get_file_as_bytes(first.continuation.path), old_bytes)
	check_eq(store.acknowledge(id, first.generation, first.commit_id, PackedByteArray([1]), "old-tag"), OK)
	check_eq(store.pending()[0].commit_id, newer.commit_id, "late upload cannot clear new checkpoint")

func test_asset_limit_and_traversal_are_rejected() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library(""), OK)
	var id := store.create_slot()
	var path := _city(root)
	var journal := FileAccess.get_file_as_bytes(store.journal_path())
	check(store.stage("../escape", path).is_empty())
	var large := root.path_join("large.sc2d")
	var file := FileAccess.open(large, FileAccess.WRITE)
	file.seek(67108864)
	file.store_8(0)
	file.close()
	check(store.stage(id, large).is_empty())
	check_eq(FileAccess.get_file_as_bytes(store.journal_path()), journal)

func test_complete_staged_journal_recovers_after_interrupted_publish() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library(""), OK)
	var id := store.create_slot()
	var before := FileAccess.get_file_as_bytes(store.journal_path())
	var queued := store.stage(id, _city(root))
	var complete := FileAccess.get_file_as_bytes(store.journal_path())
	var file := FileAccess.open(store.journal_path() + ".pending", FileAccess.WRITE)
	file.store_buffer(complete)
	file.close()
	file = FileAccess.open(store.journal_path(), FileAccess.WRITE)
	file.store_buffer(before)
	file.close()
	var reopened := CloudSaveStore.new(root.path_join("store"))
	check_eq(reopened.open_library(""), OK)
	check_eq(reopened.pending()[0].commit_id, queued.commit_id)

func test_accounts_are_isolated_and_local_adoption_is_explicit() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library(""), OK)
	var id := store.create_slot()
	check(not store.stage(id, _city(root)).is_empty())
	check_eq(store.adopt_local(id, "account-a"), OK)
	check_eq(store.open_library("account-b"), OK)
	check_eq(store.slots().size(), 0)
	check_eq(store.open_library("account-a"), OK)
	check_eq(store.slots().size(), 1)
	check_eq(store.pending()[0].owner, "account-a")

func test_fork_preserves_both_branches_and_validates_remote_assets() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var id := store.create_slot()
	var path := _city(root)
	var queued := store.stage(id, path)
	var fork := store.fork_pending(id, queued.generation)
	check_ne(fork, "")
	check_ne(fork, id)
	check_eq(store.pending().size(), 1, "conflicting pending moves to its independent branch")
	var remote := {"slot_id": CloudSaveTypes.uuid(), "commit_id": CloudSaveTypes.uuid(),
		"change_tag": "tag", "system_fields": PackedByteArray([2, 3]),
		"continuation_sha256": FileAccess.get_sha256(path), "manual_sha256": "", "tombstone": false,
		"metadata": {"name": "Remote city"}}
	check_eq(store.publish_remote(remote, {"continuation": path}), OK)
	check_eq(store.slots().size(), 3)
	var published: Dictionary = store.slots()[2]
	check(bool(SaveFormat.load(published.path).ok))
	remote.continuation_sha256 = "0".repeat(64)
	check_ne(store.publish_remote(remote, {"continuation": path}), OK)
	check_eq(FileAccess.get_sha256(published.path), FileAccess.get_sha256(path))

func test_corrupt_journal_and_corrupt_payload_are_not_published() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library(""), OK)
	var id := store.create_slot()
	var queued := store.stage(id, _city(root))
	var file := FileAccess.open(store.journal_path() + ".pending", FileAccess.WRITE)
	file.store_string("truncated")
	file.close()
	var reopened := CloudSaveStore.new(root.path_join("store"))
	check_eq(reopened.open_library(""), OK)
	check_eq(reopened.pending()[0].commit_id, queued.commit_id)
	file = FileAccess.open(queued.continuation.path, FileAccess.WRITE)
	file.store_string("damaged payload")
	file.close()
	check_ne(CloudSaveStore.new(root.path_join("store")).open_library(""), OK)

func test_bounded_metadata_and_invalid_source_do_not_replace_library() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library(""), OK)
	var id := store.create_slot()
	var before := FileAccess.get_file_as_bytes(store.journal_path())
	var junk := root.path_join("junk.sc2d")
	var file := FileAccess.open(junk, FileAccess.WRITE)
	file.store_string("not a city")
	file.close()
	check(store.stage(id, junk).is_empty())
	check(store.stage(id, _city(root, "é".repeat(129))).is_empty())
	check_eq(FileAccess.get_file_as_bytes(store.journal_path()), before)
	check_ne(store.open_library("../other"), OK)

func test_acknowledgement_from_replaced_baseline_cannot_promote_current_branch() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var id := store.create_slot()
	var first := store.stage(id, _city(root, "Uncertain older upload"))
	check(not store.begin_upload(id, first.generation).is_empty())
	var second := store.stage(id, _city(root, "Chosen current branch"))
	check(store.begin_upload(id, second.generation).is_empty(), "a child cannot send with an unresolved parent archive")
	check_eq(store.acknowledge(id, first.generation, first.commit_id, PackedByteArray([1]), "parent"), OK)
	check(not store.begin_upload(id, second.generation).is_empty())
	check_eq(store.acknowledge(id, second.generation, second.commit_id, PackedByteArray([2]), "chosen"), OK)
	var third := store.stage(id, _city(root, "Continued chosen branch"))
	check_ne(store.acknowledge(id, first.generation, first.commit_id, PackedByteArray([1]), "obsolete"), OK)
	check_eq(store.pending()[0].baseline_tag, "chosen")
	check_eq(store.pending()[0].parent_commit_id, second.commit_id)
	check_eq(store.pending()[0].commit_id, third.commit_id)

func _history_count(store: CloudSaveStore, id: String) -> int:
	var bytes := FileAccess.get_file_as_bytes(store.journal_path())
	var state: Dictionary = bytes_to_var(bytes.slice(72))
	return state.slots[id].history.size()

func _payload_count(store: CloudSaveStore) -> int:
	return DirAccess.open(store.journal_path().get_base_dir().path_join("payloads")).get_files().size()

func test_unsent_checkpoints_coalesce_without_unbounded_assets_or_history() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library(""), OK)
	var id := store.create_slot()
	for generation in 12:
		check(not store.stage(id, _city(root, "Checkpoint %d" % generation)).is_empty())
	check_eq(_history_count(store, id), 1, "only latest unsent generation remains")
	check_eq(_payload_count(store), 1, "superseded unsent assets are retired")

func test_acknowledged_checkpoints_retire_assets_history_and_upload_pins() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var id := store.create_slot()
	for generation in 12:
		var work := store.stage(id, _city(root, "Acknowledged %d" % generation))
		check(not store.begin_upload(id, work.generation).is_empty())
		check_eq(store.acknowledge(id, work.generation, work.commit_id, PackedByteArray([generation]), "tag-%d" % generation), OK)
	check_eq(store.inflight().size(), 0)
	check_eq(_history_count(store, id), 0)
	check_eq(_payload_count(store), 1, "only the current acknowledged continuation remains")

func test_upload_pin_survives_restart_newer_staging_and_old_acknowledgement() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var id := store.create_slot()
	var older := store.stage(id, _city(root, "Uncertain network result"))
	check(not store.begin_upload(id, older.generation).is_empty())
	var newer := store.stage(id, _city(root, "Newer unsent state"))
	var reopened := CloudSaveStore.new(root.path_join("store"))
	check_eq(reopened.open_library("account-a"), OK)
	check_eq(reopened.inflight().size(), 1)
	check_eq(reopened.inflight()[0].commit_id, older.commit_id)
	check_eq(FileAccess.get_sha256(older.continuation.path), older.continuation.sha256)
	var fork := reopened.fork_pending(id, older.generation)
	check_ne(fork, "", "recovered pin can become a conflict branch")
	check_eq(reopened.acknowledge(id, older.generation, older.commit_id, PackedByteArray([4]), "applied"), OK)
	check_eq(reopened.inflight().size(), 0)
	check_eq(reopened.pending()[0].slot_id, fork, "active local descendant moved onto its conflict branch")
	check_eq(reopened.pending()[0].continuation.sha256, newer.continuation.sha256)
	check_eq(reopened.pending()[0].baseline_tag, "", "original success cannot rebase a new independent fork")
	check(FileAccess.file_exists(older.continuation.path), "fork owns the old payload after pin retirement")

func test_pruning_preserves_manual_and_conflict_slot_payloads_and_unrelated_files() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library(""), OK)
	var id := store.create_slot()
	var work := store.stage(id, _city(root, "Manual baseline"), root.path_join("input.sc2d"))
	var manual: String = work.manual.path
	var original: String = work.continuation.path
	var fork := store.fork_pending(id, work.generation)
	check_ne(fork, "")
	var unrelated := store.journal_path().get_base_dir().path_join("payloads/keep.txt")
	var file := FileAccess.open(unrelated, FileAccess.WRITE)
	file.store_string("unrelated")
	file.close()
	for generation in 5:
		check(not store.stage(id, _city(root, "Newer %d" % generation)).is_empty())
	check(FileAccess.file_exists(manual))
	check(FileAccess.file_exists(original), "separate unresolved conflict branch survives")
	check_eq(FileAccess.get_file_as_string(unrelated), "unrelated")
	check_eq(_payload_count(store), 4, "current continuation, manual, conflict continuation, unrelated file")

func test_retiring_confirmed_nonapplication_releases_only_its_pin() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library(""), OK)
	var id := store.create_slot()
	var first := store.stage(id, _city(root, "Rejected older upload"))
	check(not store.begin_upload(id, first.generation).is_empty())
	var newer := store.stage(id, _city(root, "Latest local state"))
	check_eq(store.retire_upload(id, first.generation), OK)
	check_eq(store.inflight().size(), 0)
	check_eq(store.pending()[0].commit_id, newer.commit_id)
	check(not FileAccess.file_exists(first.continuation.path))
	check_eq(_history_count(store, id), 1)
	check_eq(_payload_count(store), 1)
	check(store.begin_upload(id, first.generation).is_empty(), "superseded unsent work cannot dispatch")
	check_ne(store.acknowledge(id, first.generation, first.commit_id, PackedByteArray(), "tag"), OK)

func test_failed_pin_and_retirement_publication_preserve_durable_ownership() -> void:
	var root := _root()
	var store := FailingStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var id := store.create_slot()
	var first := store.stage(id, _city(root, "Pin publication boundary"))
	store.fail_write = true
	check(store.begin_upload(id, first.generation).is_empty())
	check_eq(store.inflight().size(), 0)
	store.fail_write = false
	check(not store.begin_upload(id, first.generation).is_empty())
	check(not store.stage(id, _city(root, "Newer pending after pin")).is_empty())
	store.fail_write = true
	check_ne(store.retire_upload(id, first.generation), OK)
	check_eq(store.inflight().size(), 1)
	check(FileAccess.file_exists(first.continuation.path))
	var reopened := CloudSaveStore.new(root.path_join("store"))
	check_eq(reopened.open_library("account-a"), OK)
	check_eq(reopened.inflight()[0].commit_id, first.commit_id)

class DecodeCountingStore extends CloudSaveStore:
	var decodes := 0
	func _validated_version(path: String, _text: String) -> int:
		decodes += 1
		var loaded := SaveFormat.load(path)
		return int(loaded.get("version", 0)) if loaded.get("ok", false) else 0

func test_identical_payload_bytes_need_one_full_decode_across_journal_references() -> void:
	var root := _root()
	var store := DecodeCountingStore.new(root.path_join("store"))
	check_eq(store.open_library(""), OK)
	var id := store.create_slot()
	var path := _city(root)
	check(not store.stage(id, path).is_empty())
	check_eq(store.decodes, 1, "copy, slot header and three journal references share one full validation")
	var row := store.slots()[0]
	var header := store.readable_header(row.path)
	header.name = "caller mutation"
	check_eq(store.readable_header(row.path).name, "Same city")
	check_eq(store.decodes, 1, "repeated exact bytes reuse validation only")

func test_validation_cache_hashes_same_size_same_time_replacements_and_rejects_damage() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	var same_time := false
	for attempt in 4:
		var path := _city(root, "Alpha")
		var original := FileAccess.get_file_as_string(path)
		check_eq(store.readable_header(path).name, "Alpha")
		var modified := FileAccess.get_modified_time(path)
		var replacement := original.replace("Alpha", "Bravo")
		check_eq(replacement.to_utf8_buffer().size(), original.to_utf8_buffer().size())
		check_eq(SaveFormat._write_replacement(path, replacement.to_utf8_buffer()), OK)
		check_eq(store.readable_header(path).name, "Bravo", "content hash defeats equal-size/mtime stale validity")
		if FileAccess.get_modified_time(path) == modified: same_time = true; break
	check(same_time)
	var path := root.path_join("input.sc2d")
	var valid := FileAccess.get_file_as_bytes(path)
	var damaged := valid.duplicate()
	damaged[0] = 33
	check_eq(SaveFormat._write_replacement(path, damaged), OK)
	check_eq(store.readable_header(path), {}, "equal-sized corruption cannot use positive cache")
	check_eq(SaveFormat._write_replacement(path, valid), OK)
	check_eq(store.readable_header(path).name, "Bravo")
	var document: Dictionary = JSON.parse_string(valid.get_string_from_utf8())
	document.version = 99
	check_eq(SaveFormat._write_replacement(path, JSON.stringify(document).to_utf8_buffer()), OK)
	check_eq(store.readable_header(path), {}, "newer portable format remains refused")
	DirAccess.remove_absolute(path)
	check_eq(store.readable_header(path), {}, "deleted input cannot use cache")

func test_positive_validation_cache_is_bounded_and_content_based() -> void:
	var root := _root()
	var store := DecodeCountingStore.new(root.path_join("store"))
	var first := _city(root, "First")
	var first_bytes := FileAccess.get_file_as_bytes(first)
	check_eq(store.readable_header(first).name, "First")
	var second := root.path_join("same-bytes.sc2d")
	check_eq(SaveFormat._write_replacement(second, first_bytes), OK)
	check_eq(store.readable_header(second).path, second, "cached validity never caches a prior path")
	check_eq(store.decodes, 1, "identical bytes at another path do not decode again")
	for index in 32:
		var path := _city(root, "Other-" + str(index))
		check_eq(store.readable_header(path).name, "Other-" + str(index))
	check_eq(store.decodes, 33)
	check_eq(store.readable_header(second).name, "First")
	check_eq(store.decodes, 34, "32-entry bound evicts oldest content")

class ReplacingDuringDecodeStore extends CloudSaveStore:
	var replace_once := true
	func _validated_version(path: String, _text: String) -> int:
		var loaded := SaveFormat.load(path)
		if replace_once:
			replace_once = false
			var changed := FileAccess.get_file_as_string(path).replace("Alpha", "Bravo")
			SaveFormat._write_replacement(path, changed.to_utf8_buffer())
		return int(loaded.get("version", 0)) if loaded.get("ok", false) else 0

func test_replacement_during_full_decode_never_seeds_positive_cache() -> void:
	var root := _root()
	var store := ReplacingDuringDecodeStore.new(root.path_join("store"))
	var path := _city(root, "Alpha")
	check_eq(store.readable_header(path), {}, "changed bytes during cold validation fail closed")
	check_eq(store.readable_header(path).name, "Bravo", "next stable read validates actual replacement")

class ReadCountingStore extends CloudSaveStore:
	var reads := 0
	var decodes := 0
	func readable_header(path: String) -> Dictionary:
		reads += 1
		return super.readable_header(path)
	func _validated_version(path: String, text: String) -> int:
		decodes += 1
		return super._validated_version(path, text)

func test_one_city_publication_does_not_read_untouched_acknowledged_library() -> void:
	var directory := _root()
	var library := ReadCountingStore.new(directory.path_join("store"))
	check_eq(library.open_library("account-a"), OK)
	var city := flat_city()
	for y in range(0, City.HEIGHT, 4):
		for x in range(0, City.WIDTH, 4): city.signs[Vector2i(x, y)] = "Synthetic block %d, %d" % [x, y]
	var path := directory.path_join("scale.sc2d")
	var id := ""
	for index in 40:
		city.name = "Retained city %d" % index
		check_eq(SaveFormat.save(path, city), OK)
		id = library.create_slot()
		var work := library.stage(id, path)
		check(not work.is_empty())
		check(not library.begin_upload(id, work.generation).is_empty())
		check_eq(library.acknowledge(id, work.generation, work.commit_id, PackedByteArray([1]), "ack"), OK)
	city.funds -= 1
	check_eq(SaveFormat.save(path, city), OK)
	library.reads = 0
	library.decodes = 0
	var start := Time.get_ticks_usec()
	check(not library.stage(id, path).is_empty())
	print("FINAL_ACKNOWLEDGED_40_CITY_STAGE us=", Time.get_ticks_usec() - start, " reads=", library.reads, " decodes=", library.decodes)
	check(library.reads <= 4, "one-city publication must not read unrelated assets")
	check_eq(library.decodes, 1, "one changed payload requires one full city validation")

class RetainedIntentStore extends CloudSaveStore:
	func clear_manual_intent(_transition: Dictionary) -> void:
		pass # Simulated cleanup failure after successful journal publication.

func test_failed_receipt_cleanup_cannot_roll_back_later_local_or_remote_content() -> void:
	var directory := _root()
	var library := RetainedIntentStore.new(directory.path_join("store"))
	check_eq(library.open_library("account-a"), OK)
	var path := _city(directory)
	var id := library.create_slot()
	var transition := {"intent_id": CloudSaveTypes.uuid(), "owner": "account-a", "path": path, "sha256": FileAccess.get_sha256(path), "source": id, "target": id, "target_head": CloudSaveSession._identity_head(library.slots()[0]), "same_path": true, "unnamed": true, "transfer": false}
	check_eq(library.record_manual_intent(transition), OK)
	check_eq(library.recover_manual_save(transition), id)
	var new_path := directory.path_join("advanced.sc2d")
	var city := flat_city()
	city.funds -= 1
	check_eq(SaveFormat.save(new_path, city), OK)
	var work := library.stage(id, new_path)
	check(not work.is_empty())
	var reopened := CloudSaveStore.new(directory.path_join("store"))
	check_eq(reopened.open_library("account-a"), OK)
	check_eq(reopened.recover_manual_save(reopened.manual_intent(path)), id)
	check_eq(reopened.slots()[0].continuation_sha256, FileAccess.get_sha256(new_path), "cleanup replay retains later local continuation")
	check_eq(reopened.record_manual_intent(transition), OK)
	reopened.begin_upload(id, work.generation)
	check_eq(reopened.acknowledge(id, work.generation, work.commit_id, PackedByteArray([1]), "ack"), OK)
	city.funds -= 1
	check_eq(SaveFormat.save(new_path, city), OK)
	var digest := FileAccess.get_sha256(new_path)
	var remote := {"slot_id": id, "commit_id": "remote", "change_tag": "new", "system_fields": PackedByteArray([2]), "continuation_sha256": digest, "manual_sha256": digest, "tombstone": false, "metadata": {}}
	check_eq(reopened.publish_remote(remote, {"continuation": new_path, "manual": new_path}), OK)
	var final_library := CloudSaveStore.new(directory.path_join("store"))
	check_eq(final_library.open_library("account-a"), OK)
	check_eq(final_library.recover_manual_save(final_library.manual_intent(path)), id)
	check_eq(final_library.slots()[0].continuation_sha256, digest, "cleanup replay retains later remote continuation")
	check_eq(final_library.slots()[0].manual_sha256, digest)
	check_eq(final_library.record_manual_intent(transition), OK)
	check_eq(final_library.remove_remote(id), OK)
	check_eq(final_library.recover_manual_save(transition), id)
	check_eq(final_library.slots().size(), 0, "stale cleanup receipt cannot resurrect remote deletion")

func test_changed_descriptor_and_actual_use_cannot_inherit_prior_payload_trust() -> void:
	var directory := _root()
	var library := CloudSaveStore.new(directory.path_join("store"))
	check_eq(library.open_library("account-a"), OK)
	var id := library.create_slot()
	var work := library.stage(id, _city(directory, "Alpha"))
	var payload: Dictionary = work.continuation
	var bytes := FileAccess.get_file_as_bytes(payload.path)
	var replacement := bytes.get_string_from_utf8().replace("Alpha", "Bravo").to_utf8_buffer()
	check_eq(replacement.size(), bytes.size())
	check_eq(SaveFormat._write_replacement(payload.path, replacement), OK)
	check_eq(library.payload_metadata(payload), {}, "actual upload rejects even valid changed bytes")
	var service := CloudSaveCoordinator.new(library, preload("res://tests/helpers/fake_apple_cloud.gd").new())
	service._enabled = true
	service._owner = "account-a"
	check_eq(service.library_entries([]).size(), 0, "actual Load rejects mismatched immutable bytes")
	var next := library._state.duplicate(true)
	next.slots[id].continuation.sha256 = "0".repeat(64)
	check_eq(library._commit(next), ERR_FILE_CORRUPT, "changed descriptor is deeply verified")
	var reopened := CloudSaveStore.new(directory.path_join("store"))
	check_eq(reopened.open_library("account-a"), ERR_FILE_CORRUPT, "startup fully revalidates prior references")
	service.shutdown()
