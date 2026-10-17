# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"
## Work bounds for library open, Load listing, inventory migration, retries and
## the native completion boundary. Counts full city decodes and file hashes
## rather than wall-clock time; integrity checks still reject changed bytes.
const Fake = preload("res://tests/helpers/fake_apple_cloud.gd")

class CountingStore extends CloudSaveStore:
	var decodes := 0
	var hashes := 0
	var copies := 0
	var reads := 0
	func readable_header(path: String) -> Dictionary:
		reads += 1
		return super.readable_header(path)
	func _validated_version(path: String, text: String) -> int:
		decodes += 1
		return super._validated_version(path, text)
	func _hash_file(path: String) -> String:
		hashes += 1
		return FileAccess.get_sha256(path)
	func pending() -> Array[Dictionary]:
		copies += 1
		return super.pending()
	func inflight() -> Array[Dictionary]:
		copies += 1
		return super.inflight()

class FakeNative extends RefCounted:
	var completions: Array = []
	func available() -> bool: return true
	func start_request(_request: Dictionary) -> Error: return OK
	func drain_completions() -> Array:
		var result := completions.duplicate(true)
		completions.clear()
		return result
	func cancel_all() -> void: pass

var _roots: Array[String] = []
var _personal: Array[String] = []

func _root() -> String:
	var path := "user://cloud-work-bounds/%d-%d" % [Time.get_ticks_usec(), _roots.size()]
	_roots.append(path)
	DirAccess.make_dir_recursive_absolute(path)
	return path

func _city(path: String, title: String, funds: int = 20000) -> String:
	var city := flat_city(funds)
	city.name = title
	check_eq(SaveFormat.save(path, city), OK)
	return path

func after_all() -> void:
	for path in _personal: DirAccess.remove_absolute(path)
	for root in _roots: _remove_tree(root)

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	for child in dir.get_directories(): _remove_tree(path.path_join(child))
	for child in dir.get_files(): DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)

## Files written in the current second are never trusted by the racy-time rule;
## age them past a second boundary before measuring reuse.
func _age_past_second_boundary() -> void:
	OS.delay_msec(1100)

func _acknowledged_library(root: String, count: int) -> CloudSaveStore:
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	for index in count:
		var path := _city(root.path_join("input.sc2d"), "Library city %d" % index, 1000 + index)
		var id := store.create_slot()
		var work := store.stage(id, path)
		check(not work.is_empty())
		check(not store.begin_upload(id, work.generation).is_empty())
		check_eq(store.acknowledge(id, work.generation, work.commit_id, PackedByteArray([1]), "ack-%d" % index), OK)
	return store

func test_reopening_a_library_never_decodes_payloads_and_still_rejects_changed_bytes() -> void:
	var root := _root()
	_acknowledged_library(root, 12)
	_age_past_second_boundary()
	var first := CountingStore.new(root.path_join("store"))
	var start := Time.get_ticks_usec()
	check_eq(first.open_library("account-a"), OK)
	print("WORK open_library 12 payloads us=", Time.get_ticks_usec() - start, " decodes=", first.decodes, " hashes=", first.hashes)
	check_eq(first.decodes, 0, "opening validates digests, not full city decodes")
	var second := CountingStore.new(root.path_join("store"))
	check_eq(second.open_library("account-a"), OK)
	check_eq(second.decodes, 0)
	check_eq(second.hashes, 0, "a second open in this process reuses unchanged-file digests")
	# Upload metadata decodes lazily, once per process for those exact bytes.
	var row := second.slots()[0]
	check(not second.payload_metadata(row.continuation).is_empty())
	var decoded := second.decodes
	check(decoded <= 1)
	var third := CountingStore.new(root.path_join("store"))
	check_eq(third.open_library("account-a"), OK)
	check(not third.payload_metadata(row.continuation).is_empty())
	check_eq(third.decodes, 0, "metadata of unchanged immutable bytes is not decoded again")
	# A changed payload of the same size is refused for upload, Load and reopen.
	var bytes := FileAccess.get_file_as_bytes(row.continuation.path)
	var changed := bytes.get_string_from_utf8().replace("Library city", "Altered city").to_utf8_buffer()
	check_eq(changed.size(), bytes.size())
	check_eq(SaveFormat._write_replacement(row.continuation.path, changed), OK)
	check_eq(third.payload_metadata(row.continuation), {}, "changed bytes cannot be uploaded")
	var service := CloudSaveCoordinator.new(third, Fake.new())
	service._enabled = true
	service._owner = "account-a"
	var listed := false
	for entry in service.library_entries([]):
		if entry.get("slot_id", "") == row.slot_id: listed = true
	check(not listed, "changed bytes are not offered by Load")
	check_eq(CloudSaveStore.new(root.path_join("store")).open_library("account-a"), ERR_FILE_CORRUPT, "reopen rejects changed bytes")
	service.shutdown()

func test_load_listing_reads_headers_only_and_keeps_damaged_personal_saves() -> void:
	var root := _root()
	var saves := root.path_join("saves")
	DirAccess.make_dir_recursive_absolute(saves)
	for index in 42: _city(saves.path_join("listed-%02d.sc2d" % index), "Listed %d" % index, 3000 + index)
	var broken := FileAccess.open(saves.path_join("broken-body.sc2d"), FileAccess.WRITE)
	broken.store_string(JSON.stringify({"format": SaveFormat.FORMAT, "version": SaveFormat.VERSION, "stage": "play", "header": {"name": "Broken Body", "population": 5, "saved_at": 1}, "city": {}}))
	broken.close()
	var store := CountingStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var service := CloudSaveCoordinator.new(store, Fake.new())
	service._enabled = true
	service._owner = "account-a"
	var rows := SaveFormat.list_saves(saves)
	check_eq(rows.size(), 43)
	for pass_index in 3:
		var start := Time.get_ticks_usec()
		var entries := service.library_entries(rows)
		print("WORK library_entries 43 local rows pass=", pass_index, " us=", Time.get_ticks_usec() - start, " decodes=", store.decodes)
		check_eq(entries.size(), 43)
	check_eq(store.decodes, 0, "listing uses headers; full validation is for files that become cloud-associated")
	var names: Array = []
	for entry in service.library_entries(rows): names.append(entry.get("name"))
	check("Broken Body" in names, "a damaged save remains listed for inspection and sharing")
	service.shutdown()

func test_inventory_refreshes_migrate_only_new_or_changed_personal_saves() -> void:
	var root := _root()
	DirAccess.make_dir_recursive_absolute(SaveFormat.default_dir())
	for index in 40:
		var path := SaveFormat.default_dir().path_join("work-bounds-%s-%d.sc2d" % [root.get_file(), index])
		_personal.append(_city(path, "Personal %d" % index, 5000 + index))
	_age_past_second_boundary()
	var store := CountingStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var fake := Fake.new()
	var service := CloudSaveCoordinator.new(store, fake)
	service.jitter = func() -> float: return 0.0
	service.set_enabled(true)
	var now := 1000
	service.advance(now)
	fake.finish(fake.last("account"), {"owner": "account-a"})
	now += 1
	service.advance(now)
	fake.finish(fake.last("prepare_zone"))
	now += 1
	service.advance(now)
	fake.finish(fake.last("changes"), {"records": [], "deleted_ids": [], "token": PackedByteArray([1]), "more": false})
	now += 1
	service.advance(now)
	var adopted := 0
	for row in store.slots():
		if _personal.has(row.manual_path) or row.manual_path.get_file().begins_with("work-bounds-%s" % root.get_file()): adopted += 1
	check_eq(adopted, 40, "the first verified inventory migrates every personal save")
	for round_index in 3:
		store.decodes = 0
		store.hashes = 0
		store.reads = 0
		var before := store.slots().size()
		now += 40000
		service.refresh(&"foreground")
		service.advance(now)
		var request := fake.last("changes")
		fake.finish(request, {"records": [], "deleted_ids": [], "token": PackedByteArray([round_index + 2]), "more": false})
		now += 1
		var start := Time.get_ticks_usec()
		service.advance(now)
		print("WORK inventory refresh 40 personal saves round=", round_index, " us=", Time.get_ticks_usec() - start, " decodes=", store.decodes, " reads=", store.reads, " hashes=", store.hashes)
		check_eq(store.decodes, 0, "unchanged personal saves are not decoded again on every refresh")
		check_eq(store.reads, 0, "unchanged personal saves are not even reread")
		check_eq(store.slots().size(), before)
	# A new file is migrated by the next refresh, without revisiting the others.
	var added := SaveFormat.default_dir().path_join("work-bounds-%s-new.sc2d" % root.get_file())
	_personal.append(_city(added, "Personal new", 7777))
	store.decodes = 0
	store.reads = 0
	now += 40000
	service.refresh(&"foreground")
	service.advance(now)
	fake.finish(fake.last("changes"), {"records": [], "deleted_ids": [], "token": PackedByteArray([9]), "more": false})
	now += 1
	service.advance(now)
	var found := false
	for row in store.slots():
		if ProjectSettings.globalize_path(row.manual_path).simplify_path() == ProjectSettings.globalize_path(added).simplify_path(): found = true
	check(found, "a new personal save is migrated")
	check_eq(store.decodes, 1, "only the new file is fully validated")
	check(store.reads <= 3, "only the new file is read")
	service.shutdown()
	for path in _personal: DirAccess.remove_absolute(path)
	_personal.clear()

func test_signed_out_account_backs_off_reports_state_and_stays_quiet() -> void:
	var store := CloudSaveStore.new(_root().path_join("store"))
	check_eq(store.open_library(""), OK)
	var fake := Fake.new()
	var service := CloudSaveCoordinator.new(store, fake)
	service.jitter = func() -> float: return 0.0
	var library := [0]
	service.library_changed.connect(func() -> void: library[0] += 1)
	service.set_enabled(true)
	var now := 1000
	var delays: Array[int] = []
	for attempt in 10:
		service.advance(now)
		fake.finish(fake.last("account"), {}, "signed_out")
		service.advance(now + 1)
		var status := service.status()
		delays.append(status.retry_at_ms - (now + 1))
		check_eq(status.state, "signed_out", "signed-out explanation is visible instead of a perpetual account check")
		now = status.retry_at_ms
	print("WORK signed_out delays=", delays, " library_changed=", library[0])
	for index in range(1, delays.size()): check(delays[index] >= delays[index - 1])
	check(delays[-1] > 60000, "signed-out checks back off past the transient cap")
	check_eq(library[0], 0, "a repeated signed-out check changes no library rows")
	check_eq(fake.count("account"), 10)
	# An actual account change starts a fresh check immediately.
	fake.account_changed(service.status().epoch)
	service.advance(now + 2)
	check_eq(fake.count("account"), 11)
	check_eq(service.status().state, "verifying_account")
	fake.finish(fake.last("account"), {}, "permission")
	service.advance(now + 3)
	check_eq(service.status().state, "permission", "restricted accounts explain the permission problem")
	service.shutdown()

func test_quota_waits_longer_and_activity_retries_at_most_once_per_minute() -> void:
	var store := CloudSaveStore.new(_root().path_join("store"))
	check_eq(store.open_library(""), OK)
	var fake := Fake.new()
	var service := CloudSaveCoordinator.new(store, fake)
	service.jitter = func() -> float: return 0.0
	service.set_enabled(true)
	var now := 0
	var delay := 0
	for attempt in 11:
		service.advance(now)
		fake.finish(fake.last("account"), {}, "quota")
		service.advance(now)
		delay = service.status().retry_at_ms - now
		now = service.status().retry_at_ms
	print("WORK quota final delay=", delay)
	check(delay >= 600000, "storage-full retries do not re-upload every minute")
	check(delay <= 1125000, "the long wait remains bounded")
	# One more failure, then foreground activity may retry after one minute.
	service.advance(now)
	fake.finish(fake.last("account"), {}, "quota")
	service.advance(now)
	var failed := now
	var requests := fake.count("account")
	service.refresh(&"foreground")
	service.advance(failed + 1000)
	check_eq(fake.count("account"), requests, "activity never retries sooner than a minute after a failure")
	service.advance(failed + 60000)
	check_eq(fake.count("account"), requests + 1, "foreground activity retries a long wait early")
	service.shutdown()

func test_status_and_idle_advances_copy_no_queued_work() -> void:
	var root := _root()
	var store := CountingStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	for index in 8: check(not store.stage(store.create_slot(), _city(root.path_join("queued.sc2d"), "Queued %d" % index)).is_empty())
	var fake := Fake.new()
	var service := CloudSaveCoordinator.new(store, fake)
	service.jitter = func() -> float: return 0.0
	service.set_enabled(true)
	service.advance(0)
	fake.finish(fake.last("account"), {"owner": "account-a"})
	service.advance(0)
	fake.finish(fake.last("prepare_zone"))
	service.advance(0)
	fake.finish(fake.last("changes"), {"records": [], "deleted_ids": [], "token": PackedByteArray([1]), "more": false})
	service.advance(0)
	fake.finish(fake.last("save"), {}, "transient")
	service.advance(1)
	check(service.status().retry_at_ms > 1)
	store.copies = 0
	for frame in 120: service.advance(1)
	check(service.status().pending >= 8)
	check_eq(store.copies, 0, "per-frame status counts queued work without copying it")
	service.shutdown()

func test_native_boundary_settles_oversized_batches_and_malformed_answers() -> void:
	var platform := AppleCloudPlatform.new()
	var native := FakeNative.new()
	platform._native = native
	for index in 70:
		check_eq(platform.start_request({"id": "request-%02d" % index, "epoch": 1, "op": "account", "args": {}}), OK)
		native.completions.append({"id": "request-%02d" % index, "epoch": 1, "op": "account", "ok": true, "code": "", "result": {"owner": "a".repeat(64)}, "retry_after_ms": 0})
	var first := platform.drain_completions()
	var second := platform.drain_completions()
	check_eq(first.size(), 64, "a bounded batch is settled now")
	check_eq(second.size(), 6, "the remainder is settled by the next drain, never dropped")
	check(platform._requests.is_empty())
	# A malformed answer to an outstanding request still releases its lane.
	check_eq(platform.start_request({"id": "malformed", "epoch": 1, "op": "account", "args": {}}), OK)
	native.completions.append({"id": "malformed", "epoch": 1, "op": "account", "ok": true, "code": "", "result": {"owner": "raw-identifier"}, "retry_after_ms": 0})
	check_eq(platform.drain_completions(), [])
	var settled := platform.drain_completions()
	check_eq(settled.size(), 1)
	if settled.size() == 1:
		check_eq(settled[0].id, "malformed")
		check_eq(settled[0].ok, false)
		check_eq(settled[0].code, "invalid")
	check(platform._requests.is_empty())
	# The same boundary drives the coordinator lane back to a retry.
	var store := CloudSaveStore.new(_root().path_join("store"))
	check_eq(store.open_library(""), OK)
	var lane := AppleCloudPlatform.new()
	var lane_native := FakeNative.new()
	lane._native = lane_native
	var service := CloudSaveCoordinator.new(store, lane)
	service.jitter = func() -> float: return 0.0
	service.set_enabled(true)
	service.advance(0)
	check(service._has("account"))
	var sent: String = lane._requests.keys()[0] if not lane._requests.is_empty() else ""
	lane_native.completions.append({"id": sent, "epoch": service.status().epoch, "op": "account", "ok": true, "code": "", "result": {}, "retry_after_ms": 0})
	service.advance(1)
	service.advance(2)
	check(not service._has("account"), "the coordinator lane is released")
	check_eq(service.status().error, "invalid")
	service.shutdown()

func test_download_hashes_before_decoding_and_shares_identical_manual_bytes() -> void:
	var root := _root()
	var expected := _city(root.path_join("expected.sc2d"), "Expected", 1111)
	var other := _city(root.path_join("other.sc2d"), "Other", 2222)
	var store := CountingStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var fake := Fake.new()
	var service := CloudSaveCoordinator.new(store, fake)
	service.jitter = func() -> float: return 0.0
	service.set_enabled(true)
	service.advance(0)
	fake.finish(fake.last("account"), {"owner": "account-a"})
	service.advance(0)
	fake.finish(fake.last("prepare_zone"))
	service.advance(0)
	# The first inventory (and its personal-save migration) completes first.
	fake.finish(fake.last("changes"), {"records": [], "deleted_ids": [], "token": PackedByteArray([2]), "more": false})
	service.advance(1)
	service.refresh(&"visible")
	service.advance(40000)
	var digest := FileAccess.get_sha256(expected)
	var remote := {"slot_id": "remote-slot", "commit_id": "remote-commit", "change_tag": "tag-1", "system_fields": PackedByteArray([1]),
		"continuation_sha256": digest, "manual_sha256": digest, "tombstone": false, "metadata": {"name": "Remote"}}
	fake.finish(fake.last("changes"), {"records": [remote], "deleted_ids": [], "token": PackedByteArray([3]), "more": false})
	service.advance(40001)
	store.decodes = 0
	var wrong := fake.last("download")
	check(not wrong.is_empty())
	fake.finish(wrong, {"downloaded": {"continuation": other, "manual": other}})
	service.advance(40002)
	check_eq(store.decodes, 0, "bytes of the wrong revision are refused before a full decode")
	check_eq(service.status().error, "invalid")
	var copy := root.path_join("manual-copy.sc2d")
	check_eq(SaveFormat._write_replacement(copy, FileAccess.get_file_as_bytes(expected)), OK)
	service.advance(50000)
	store.decodes = 0
	var download := fake.last("download")
	check(not download.is_empty() and download.id != wrong.id)
	fake.finish(download, {"downloaded": {"continuation": expected, "manual": copy}})
	service.advance(50001)
	var row := {}
	for entry in store.slots():
		if entry.slot_id == "remote-slot": row = entry
	check(not row.is_empty())
	if not row.is_empty():
		check_eq(row.continuation_sha256, digest)
		check_eq(row.manual_sha256, digest)
		check_eq(row.manual.path, row.continuation.path, "identical manual bytes share the continuation's immutable copy")
	check(store.decodes <= 1, "identical continuation and manual bytes are validated once")
	service.shutdown()

func _filesystem_ignores_case(root: String) -> bool:
	var path := ProjectSettings.globalize_path(root).path_join("case-probe-lower")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.close()
	var result := FileAccess.file_exists(ProjectSettings.globalize_path(root).path_join("CASE-PROBE-LOWER"))
	DirAccess.remove_absolute(path)
	return result

func test_case_variant_names_cannot_alias_one_file_on_a_case_insensitive_volume() -> void:
	var root := _root()
	if not _filesystem_ignores_case(root):
		print("WORK case-sensitive volume: case variants are distinct files")
		return
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var first := store.create_slot()
	var second := store.create_slot()
	var upper := ProjectSettings.globalize_path(root).path_join("Desert.sc2d")
	var lower := ProjectSettings.globalize_path(root).path_join("desert.sc2d")
	check_eq(store.bind_manual_path(first, upper), OK)
	check_eq(store.bind_manual_path(second, lower), ERR_ALREADY_EXISTS, "one file cannot have two cloud destinations")
	_city(upper, "Desert")
	check(store.stage(second, upper, lower).is_empty(), "a case variant cannot stage a second manual association")
	var other := CloudSaveStore.new(root.path_join("store"))
	check_eq(other.open_library("account-b"), OK)
	check_eq(other.path_claim(lower).get("owner", ""), "account-a", "a case variant names the claimed file")
	check_eq(other.claim_manual_path(lower, other.create_slot()), ERR_UNAUTHORIZED)

func test_stale_transport_staging_is_removed_by_generated_name_only() -> void:
	var root := ProjectSettings.globalize_path(_root()).path_join("staging")
	var outside := ProjectSettings.globalize_path(_root()).path_join("outside")
	DirAccess.make_dir_recursive_absolute(outside)
	var kept := outside.path_join("player.sc2d")
	_city(kept, "Outside")
	# Native transport names are uppercase UUIDs; accept either case.
	var stale_upper := root.path_join(CloudSaveTypes.uuid().to_upper())
	var stale_lower := root.path_join(CloudSaveTypes.uuid())
	for directory in [stale_upper, stale_lower, root.path_join("keep-me")]:
		DirAccess.make_dir_recursive_absolute(directory)
		var file := FileAccess.open(directory.path_join("asset.sc2d"), FileAccess.WRITE)
		file.store_string("staged")
		file.close()
	var named_path := root.path_join(CloudSaveTypes.uuid())
	var named_file := FileAccess.open(named_path, FileAccess.WRITE)
	named_file.store_string("not a transport directory")
	named_file.close()
	var link := root.path_join(CloudSaveTypes.uuid().to_upper())
	check_eq(OS.execute("ln", ["-s", outside, link]), 0)
	var platform := AppleCloudPlatform.new()
	check(platform.has_method("remove_stale_staging"))
	if not platform.has_method("remove_stale_staging"): return
	var removed: int = platform.call("remove_stale_staging", root)
	check_eq(removed, 3)
	check(not DirAccess.dir_exists_absolute(stale_upper))
	check(not DirAccess.dir_exists_absolute(stale_lower))
	check(DirAccess.dir_exists_absolute(root.path_join("keep-me")), "only generated names are removed")
	check(FileAccess.file_exists(root.path_join("keep-me/asset.sc2d")))
	check(FileAccess.file_exists(named_path), "regular files are left alone")
	check(not FileAccess.file_exists(link.path_join("player.sc2d")), "the link is removed")
	check(FileAccess.file_exists(kept), "a link target is never followed")
	var symlinked_root := ProjectSettings.globalize_path(_root()).path_join("linked-root")
	check_eq(OS.execute("ln", ["-s", root, symlinked_root]), 0)
	check_eq(platform.call("remove_stale_staging", symlinked_root), 0, "a symlinked staging root is refused")
	DirAccess.remove_absolute(symlinked_root)

func test_open_load_list_keeps_identical_rows_without_rebuilding() -> void:
	var dialog := LoadDialog.new()
	root.add_child(dialog)
	var saves: Array[Dictionary] = []
	for index in 3: saves.append({"name": "City %d" % index, "path": "user://saves/city-%d.sc2d" % index, "year": 1950, "population": 10})
	dialog.refresh(saves)
	dialog.visible = true
	dialog.select(1)
	dialog.item_list.set_item_tooltip(1, "sentinel")
	dialog.refresh(saves.duplicate(true))
	check_eq(dialog.item_list.get_item_tooltip(1), "sentinel", "a sync notification with identical rows does not rebuild the open list")
	check_eq(dialog.item_list.get_selected_items(), PackedInt32Array([1]))
	var changed := saves.duplicate(true)
	changed[0].name = "Renamed"
	dialog.refresh(changed)
	check(dialog.item_list.get_item_text(0).begins_with("Renamed"), "changed rows still refresh")
	check_ne(dialog.item_list.get_item_tooltip(1), "sentinel")
	check_eq(dialog.item_list.get_selected_items(), PackedInt32Array([1]), "selection follows the same save")
	dialog.free()
