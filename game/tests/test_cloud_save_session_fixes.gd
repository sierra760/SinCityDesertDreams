# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
## Don't Save, reserved names, inert disabled sync, parked handles and cleanup.
const MAIN := preload("res://scenes/main.tscn")
const Fake := preload("res://tests/helpers/fake_apple_cloud.gd")
const DESTINATION_NOTE := "user://recovery/suspended-destination.json"
class CountingFiles extends CityFileFlow:
	var snapshots := 0
	func save_content() -> Dictionary:
		snapshots += 1
		return super.save_content()
class FailingStore extends CloudSaveStore:
	var fail := false
	func _write_journal(bytes: PackedByteArray) -> Error:
		return ERR_CANT_CREATE if fail else super._write_journal(bytes)
var host: GameHost
var store: CloudSaveStore
var coordinator: CloudSaveCoordinator
var cloud: CloudSaveSession
var fake
var directory: String
var paths: Array[String] = []

func before_each() -> void:
	directory = "user://cloud-session-fixes/" + CloudSaveTypes.uuid()
	store = FailingStore.new(directory)
	check_eq(store.open_library(""), OK)
	fake = Fake.new()
	coordinator = CloudSaveCoordinator.new(store, fake)
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

func after_each() -> void:
	if is_instance_valid(host): host.free()
	for path in paths: DirAccess.remove_absolute(path)
	paths.clear()
	DirAccess.remove_absolute(CityFileFlow.application_recovery_path())
	DirAccess.remove_absolute(DESTINATION_NOTE)
	await process_frame

func _verify(value: String = "a".repeat(64)) -> void:
	coordinator.set_enabled(true)
	coordinator.advance(Time.get_ticks_msec())
	fake.finish(fake.last("account"), {"owner": value})
	coordinator.advance(Time.get_ticks_msec())
	check_eq(coordinator.status().owner, value)

func _row(id: String) -> Dictionary:
	if not store._state.get("slots", {}).has(id): return {}
	return store._state.slots[id]

func _visible(id: String) -> Dictionary:
	for entry in store.slots():
		if entry.slot_id == id: return entry
	return {}

func _saved(name: String) -> String:
	var path := host.files.save_city_as("cloud-fix-" + name)
	paths.append(path)
	return path

## An owned continuation-only city: no manual asset, a published checkpoint.
func _continuation_city(name: String, acknowledge: bool = true) -> String:
	host.begin_city(flat_city(), {}, 123, null)
	host.sim.city.name = name
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.save_path = ""
	cloud.begin_session()
	host.sim.city.funds -= 100
	check_eq(cloud.capture(&"test"), OK)
	var id := cloud.slot_id
	if acknowledge: _acknowledge(id)
	return id

func _acknowledge(id: String) -> void:
	for work in store.pending():
		if work.slot_id != id: continue
		check(not store.begin_upload(id, work.generation).is_empty())
		check_eq(store.acknowledge(id, work.generation, work.commit_id, PackedByteArray([1]), "tag-" + str(work.generation)), OK)

func _open_continuation(id: String) -> void:
	var continuation: String = _visible(id).path
	host.begin_city(flat_city(), {}, 9, null)
	check(host.session.load_city(continuation))
	check_eq(cloud.slot_id, id)

func _settle_loading() -> void:
	await process_frame
	while host.loading_screen.visible: await process_frame
	await process_frame

# Finding 1: merely opening a continuation-only city and choosing Don't Save
# must not delete it from every device.
func test_unchanged_continuation_leaves_without_prompt_or_tombstone() -> void:
	_verify()
	var id := _continuation_city("Desert view")
	var before: Dictionary = _row(id).duplicate(true)
	_open_continuation(id)
	host.files.request_city_action(&"new")
	check(not host.notice_dialog.is_open(), "an unchanged reopened continuation needs no save question")
	check(host.new_city_dialog.is_open(), "leaving proceeds directly")
	if host.new_city_dialog.is_open(): host.new_city_dialog.close()
	if host.notice_dialog.is_open(): host.notice_dialog.dismiss(&"cancel")
	check_eq(cloud.discard(), OK)
	check(not _row(id).tombstone, "Don't Save after viewing never deletes the city")
	check_eq(_row(id).continuation.get("sha256", ""), before.continuation.sha256)
	check_eq(_row(id).generation, before.generation, "nothing is staged when nothing changed")
	check(_row(id).pending.is_empty())

# Finding 1: with a manual save, a newer continuation from another device
# survives Don't Save when this session changed nothing.
func test_unchanged_newer_continuation_is_not_replaced_by_manual() -> void:
	_verify()
	var manual := _saved("newer-continuation")
	var id := cloud.slot_id
	host.sim.city.funds -= 250
	check_eq(cloud.capture(&"test"), OK)
	_acknowledge(id)
	var newer: String = _row(id).continuation.sha256
	check_ne(newer, FileAccess.get_sha256(manual))
	_open_continuation(id)
	check(host.files.has_unsaved_changes(), "the older manual baseline still differs")
	check_eq(cloud.discard(), OK)
	check_eq(_row(id).continuation.sha256, newer, "the newer continuation is retained")
	check(_row(id).pending.is_empty())

# Finding 1: Don't Save after real changes returns a pre-existing slot to the
# exact continuation that was opened, never a tombstone.
func test_changed_continuation_returns_to_opened_state() -> void:
	_verify()
	var id := _continuation_city("Changed view")
	var opened: String = _row(id).continuation.sha256
	_open_continuation(id)
	host.sim.city.funds -= 777
	check_eq(cloud.capture(&"test"), OK)
	check_ne(_row(id).continuation.sha256, opened)
	_acknowledge(id)
	host.sim.city.funds -= 1
	check_eq(cloud.capture(&"test"), OK)
	host.files.request_city_action(&"new")
	check(host.notice_dialog.is_open(), "changed city asks before leaving")
	host.notice_dialog.dismiss(&"discard")
	check(not _row(id).tombstone, "a pre-existing city is never deleted by Don't Save")
	check_eq(_row(id).continuation.sha256, opened, "slot returns to the state it was opened in")
	check_eq(_row(id).pending.get("parent_commit_id", ""), _row(id).commit_id, "restoration is conditional on the acknowledged checkpoint")
	if host.new_city_dialog.is_open(): host.new_city_dialog.close()

# Only a slot created in this session, never acknowledged nor manually saved,
# becomes a tombstone; an acknowledged new city is kept.
func test_only_unpublished_new_city_is_tombstoned() -> void:
	_verify()
	var unpublished := _continuation_city("Fresh", false)
	check_eq(cloud.discard(), OK)
	check(_row(unpublished).tombstone, "a never-published new city is dropped")
	var published := _continuation_city("Published", true)
	host.sim.city.funds -= 3
	check_eq(cloud.capture(&"test"), OK)
	var head: String = _row(published).continuation.sha256
	check_eq(cloud.discard(), OK)
	check(not _row(published).tombstone, "an acknowledged city stays")
	check_eq(_row(published).continuation.sha256, head)

# Finding 8: Don't Save then Cancel in the Load browser keeps the same city's
# session: no tombstone remains and checkpoints continue.
func test_dont_save_then_cancel_load_restores_session() -> void:
	_verify()
	var id := _continuation_city("Cancelled leave", false)
	host.sim.city.funds -= 5
	host.files.request_city_action(&"load")
	check(host.notice_dialog.is_open())
	host.notice_dialog.dismiss(&"discard")
	await _settle_loading()
	check(host.load_dialog.is_open(), "load browser opened")
	check(_row(id).tombstone, "discard is staged while the leave is pending")
	check_eq(coordinator._guard_remote_update(id, {}), false, "remote updates to the open city wait while the leave is pending")
	host.load_dialog.close()
	await process_frame
	cloud.tick(0.0)
	check(cloud._allowed(), "cancelled leave continues the session")
	check(not _row(id).tombstone, "the cancelled discard is undone")
	check_eq(SaveFormat.load(_row(id).continuation.path).city.funds, host.sim.city.funds)
	var generation: int = _row(id).generation
	host.sim.city.funds -= 500
	cloud.tick(61.0)
	check_eq(_row(id).generation, generation + 1, "periodic checkpoints continue after the cancelled leave")

# Finding 8: when the leave commits (another city loads), the discard stays.
func test_dont_save_then_load_commits_discard() -> void:
	_verify()
	var other := directory.path_join("other.sc2d")
	check_eq(SaveFormat.save(other, flat_city()), OK)
	var id := _continuation_city("Committed leave", false)
	host.sim.city.funds -= 5
	host.files.request_city_action(&"load")
	host.notice_dialog.dismiss(&"discard")
	await _settle_loading()
	host.load_dialog.close()
	check(host.load_city(other))
	cloud.tick(0.0)
	check(_row(id).tombstone, "the committed leave keeps the discard")
	check_ne(cloud.slot_id, id)

# Finding 2: Save As onto another city's reserved, absent filename must not
# adopt or overwrite that city's slot.
func test_save_as_onto_other_reservation_keeps_other_city() -> void:
	_verify()
	var name := "cloud-fix-reserved-" + CloudSaveTypes.uuid().left(8)
	var a := _continuation_city(name)
	var a_hash: String = _row(a).continuation.sha256
	_open_continuation(a)
	var reserved := host.save_path
	check(not FileAccess.file_exists(reserved))
	check_eq(reserved, CityFileFlow.save_path_for(name))
	host.begin_city(flat_city(), {}, 2, null)
	host.sim.city.name = "Other"
	host.sim.city.funds = 1
	host.save_path = ""
	cloud.begin_session()
	var b := cloud.slot_id
	var path := host.files.save_city_as(name)
	paths.append(path)
	check_eq(path, reserved)
	check_eq(cloud.slot_id, b, "B keeps its own identity")
	check_eq(_row(a).continuation.sha256, a_hash, "A's continuation is untouched")
	check(_row(a).pending.is_empty(), "nothing is staged onto A")
	check_ne(_row(a).manual_path, path, "A's reservation moved to a free name")
	check(not _row(a).manual_path.is_empty())
	check_eq(_row(b).manual_path, path)
	check_eq(_row(b).manual.get("sha256", ""), FileAccess.get_sha256(path))
	# Reopening A targets its new free name, never B's file.
	_open_continuation(a)
	check_eq(host.save_path, _row(a).manual_path)
	check_ne(host.save_path, path)

# Finding 3: with sync off (or unsupported) the session does no capture,
# serialization, copy or journal work, then joins when sync is enabled.
func test_disabled_sync_is_inert_until_enabled() -> void:
	for unsupported in [false, true]:
		if unsupported:
			fake.supported = false
			coordinator.set_enabled(true)
		else:
			coordinator.set_enabled(false)
		var files: CountingFiles = host.files
		var journal := store._root.path_join("local/journal.bin")
		var journal_before := FileAccess.get_sha256(journal)
		var payloads := DirAccess.get_files_at(store._root.path_join("local/payloads")).size() if DirAccess.dir_exists_absolute(store._root.path_join("local/payloads")) else 0
		host.begin_city(flat_city(), {}, 5, null)
		host.save_path = ""
		cloud.begin_session()
		check_eq(cloud.slot_id, "", "no slot is created while sync is off")
		var count := files.snapshots
		host.sim.city.funds -= 9
		cloud.tick(61.0)
		host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		check_eq(cloud.capture(&"test"), ERR_UNAVAILABLE)
		check_eq(files.snapshots, count, "no city serialization for checkpoints or focus changes")
		var manual := _saved("inert-" + str(unsupported))
		check_eq(files.snapshots, count + 1, "Save serializes only for its own dirty baseline")
		check_eq(cloud._local, null, "local library is never opened")
		check_eq(FileAccess.get_sha256(journal), journal_before, "no journal is written")
		var payloads_after := DirAccess.get_files_at(store._root.path_join("local/payloads")).size() if DirAccess.dir_exists_absolute(store._root.path_join("local/payloads")) else 0
		check_eq(payloads_after, payloads, "no payload is copied")
		check_eq(cloud.discard(), OK)
		check_eq(cloud.slot_id, "")
		check(not host.files.has_unsaved_changes())
		# Enabling sync later records the city and its manual save.
		fake.supported = true
		coordinator.set_enabled(true)
		host.sim.city.funds -= 4
		cloud.tick(0.0)
		check_ne(cloud.slot_id, "", "the open city joins the library when sync starts")
		var entry: Dictionary = {}
		for row in cloud._local.slots():
			if row.slot_id == cloud.slot_id: entry = row
		check_eq(entry.get("manual_path", ""), manual)
		check_eq(entry.get("manual_sha256", ""), FileAccess.get_sha256(manual))
		cloud.tick(61.0)
		check_eq(SaveFormat.load(cloud._library()._state.slots[cloud.slot_id].continuation.path).city.funds, host.sim.city.funds, "changes since the save are checkpointed")
		cloud.end_session()
		cloud._local = null

# Finding 3: a Save made while sync is off in an existing session is recorded
# when sync is turned back on.
func test_save_while_disabled_joins_existing_session() -> void:
	cloud.begin_session()
	var id := cloud.slot_id
	check_ne(id, "")
	coordinator.set_enabled(false)
	var manual := _saved("missed")
	coordinator.set_enabled(true)
	cloud.tick(0.0)
	check_eq(cloud.slot_id, id)
	var entry: Dictionary = cloud._local._state.slots[id]
	check_eq(entry.manual_path, manual)
	check_eq(entry.manual.get("sha256", ""), FileAccess.get_sha256(manual))

# Finding 3: a recovery written while sync is off still reopens to its named
# destination, without library work; replaced bytes never borrow it.
func test_disabled_recovery_keeps_named_destination() -> void:
	coordinator.set_enabled(false)
	var manual := _saved("recovery")
	var manual_bytes := FileAccess.get_file_as_bytes(manual)
	host.sim.city.funds -= 42
	var funds := host.sim.city.funds
	check_eq(host.suspend_for_background(), OK)
	host.resume_from_background()
	check(not FileAccess.file_exists(CityFileFlow.application_recovery_path()), "a clean return removes the recovery copy")
	check(not FileAccess.file_exists(DESTINATION_NOTE), "and its destination note")
	check_eq(host.suspend_for_background(), OK)
	host.free()
	await process_frame
	host = MAIN.instantiate()
	cloud = CloudSaveSession.new(host, coordinator, store)
	host.cloud_saves = cloud
	host.preferences_path = directory.path_join("preferences.cfg")
	root.add_child(host)
	host.set_process(false)
	coordinator.set_enabled(false)
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_eq(host.save_path, manual, "recovery keeps its named destination while sync is off")
	check_eq(host.sim.city.funds, funds)
	check(host.files.has_unsaved_changes(), "recovered progress is newer than the named save")
	check_eq(FileAccess.get_file_as_bytes(manual), manual_bytes)
	check_eq(cloud._local, null)
	check_eq(host.files.save_city(), OK)
	check(not FileAccess.file_exists(CityFileFlow.application_recovery_path()), "named save supersedes the recovery")
	# Other bytes at the recovery path never borrow the old destination.
	check_eq(host.suspend_for_background(), OK)
	var city := flat_city()
	city.funds = 3
	check_eq(SaveFormat.save(CityFileFlow.application_recovery_path(), city), OK)
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_eq(host.save_path, "")

# Finding 5: a parked account's library is opened once, not on every Save.
func test_parked_owner_library_handle_is_reused() -> void:
	_verify("b".repeat(64))
	cloud.begin_session()
	var manual := _saved("parked")
	coordinator.set_enabled(false)
	coordinator.set_enabled(true) # signed in again but not yet verified: account parked
	check_eq(coordinator.status().owner, "")
	check(host.load_city(manual))
	check_eq(cloud.owner, "b".repeat(64))
	var handle := cloud._library()
	check(handle == store, "no other account verified: the coordinator's handle still holds this account")
	for i in 3:
		host.sim.city.funds -= 1
		check_eq(host.files.save_city(), OK)
		check(cloud._library() == handle, "the handle is reused")
	# Another account verifies: the old one gets one parked handle, reused.
	_verify("c".repeat(64))
	check(host.load_city(manual))
	check_eq(cloud.owner, "b".repeat(64))
	var parked := cloud._library()
	check(parked != store)
	for i in 3:
		host.sim.city.funds -= 1
		check_eq(host.files.save_city(), OK)
		check(cloud._library() == parked, "the parked handle is reused")
	var reopened := CloudSaveStore.new(directory)
	check_eq(reopened.open_library("b".repeat(64)), OK)
	var found := false
	for entry in reopened.slots():
		if entry.slot_id == cloud.slot_id:
			found = true
			check_eq(entry.manual_sha256, FileAccess.get_sha256(manual), "parked saves stay durable")
	check(found)
	check(cloud._parked != null)
	coordinator.set_enabled(false)
	check(cloud._parked == null, "account change drops the parked handle")

# Finding 10: an error from a closed city is not shown on the title screen, and
# capture temporaries left by an interrupted exit are removed.
func test_end_session_clears_error_and_stale_temporaries() -> void:
	_verify()
	cloud.begin_session()
	var stale := store._root.path_join("capture-" + CloudSaveTypes.uuid() + ".sc2d")
	var stale_baseline := store._root.path_join("discard-baseline-" + CloudSaveTypes.uuid() + ".sc2d")
	check_eq(SaveFormat.save(stale, host.sim.city), OK)
	check_eq(SaveFormat.save(stale_baseline, host.sim.city), OK)
	(store as FailingStore).fail = true
	host.sim.city.funds -= 1
	check_ne(cloud.capture(&"test"), OK)
	check_eq(coordinator.status().state, "local_io")
	check(not FileAccess.file_exists(stale), "stale capture temporaries are removed")
	check(not FileAccess.file_exists(stale_baseline))
	(store as FailingStore).fail = false
	if host.notice_dialog.is_open(): host.notice_dialog.dismiss()
	host.in_game = false
	cloud.end_session()
	check_ne(coordinator.status().state, "local_io", "the closed city's failure does not persist")

func _slot_funds(id: String) -> int:
	var row: Dictionary = cloud._library()._state.slots[id]
	return SaveFormat.load(row.continuation.path).city.funds

# Review 1: a city loaded while sync was off, then edited, must still ask
# before leaving after sync starts, and its slot must hold the live city.
func test_deferred_join_keeps_prompt_and_captures_live_city() -> void:
	coordinator.set_enabled(false)
	var path := _saved("deferred-join")
	host.begin_city(flat_city(), {}, 9, null)
	check(host.session.load_city(path))
	host.sim.city.funds -= 1234
	var edited := host.sim.city.funds
	coordinator.set_enabled(true)
	cloud.tick(0.0)
	check_ne(cloud.slot_id, "")
	check(not cloud.unchanged_since_opened(), "the opened state is the saved file, not the edited city")
	check_eq(_slot_funds(cloud.slot_id), edited, "joining captures the live city at once")
	check_eq(cloud._library()._state.slots[cloud.slot_id].manual.sha256, FileAccess.get_sha256(path))
	host.files.request_city_action(&"new")
	check(host.notice_dialog.is_open(), "unsaved edits still ask before leaving")
	if host.notice_dialog.is_open(): host.notice_dialog.dismiss(&"cancel")

# Review 1: Save while sync is off, edit more, then enable sync.
func test_missed_save_then_edits_keep_prompt() -> void:
	cloud.begin_session()
	coordinator.set_enabled(false)
	var path := _saved("missed-edits")
	host.sim.city.funds -= 777
	var edited := host.sim.city.funds
	coordinator.set_enabled(true)
	cloud.tick(0.0)
	check(not cloud.unchanged_since_opened())
	check_eq(_slot_funds(cloud.slot_id), edited)
	check_eq(cloud._library()._state.slots[cloud.slot_id].manual.sha256, FileAccess.get_sha256(path))
	host.files.request_city_action(&"new")
	check(host.notice_dialog.is_open(), "unsaved edits still ask before leaving")
	if host.notice_dialog.is_open(): host.notice_dialog.dismiss(&"cancel")

# Review 2: Don't Save with sync off still drops this session's staged work
# when the leave commits; a cancelled leave keeps it.
func test_dont_save_while_sync_off_drops_staged_progress() -> void:
	_verify()
	var path := _saved("off-discard")
	var saved_funds := host.sim.city.funds
	host.sim.city.funds -= 4321
	check_eq(cloud.capture(&"test"), OK)
	var id := cloud.slot_id
	coordinator.set_enabled(false)
	host.files.request_city_action(&"new")
	check(host.notice_dialog.is_open())
	host.notice_dialog.dismiss(&"discard")
	check(host.new_city_dialog.is_open())
	host.new_city_dialog.close()
	cloud.tick(0.0)
	check_eq(SaveFormat.load(store._state.slots[id].continuation.path).city.funds, saved_funds - 4321, "cancelled leave keeps the session's progress")
	host.files.request_city_action(&"new")
	host.notice_dialog.dismiss(&"discard")
	host.new_city_dialog.close()
	host.begin_city(flat_city(), {}, 3, null) # the leave commits
	check_eq(SaveFormat.load(store._state.slots[id].continuation.path).city.funds, saved_funds, "committed Don't Save returns the slot to the saved state")
	check_eq(FileAccess.get_sha256(path), store._state.slots[id].manual.sha256)

# Review 3: a recovery recorded with sync on keeps its named destination when
# reopened with sync off, and rejoins its own slot when sync starts again.
func test_recovery_recorded_with_sync_on_reopens_with_sync_off() -> void:
	var path := _saved("on-off-recovery")
	var id := cloud.slot_id
	host.sim.city.funds -= 50
	check_eq(host.suspend_for_background(), OK)
	host.free()
	await process_frame
	host = MAIN.instantiate()
	cloud = CloudSaveSession.new(host, coordinator, store)
	host.cloud_saves = cloud
	host.preferences_path = directory.path_join("preferences.cfg")
	root.add_child(host)
	host.set_process(false)
	# The previous host's exit closed this coordinator: sync is off now.
	check(not coordinator.enabled())
	check(host.load_city(CityFileFlow.application_recovery_path()))
	check_eq(host.save_path, path, "named destination kept with sync off")
	check_eq(cloud.slot_id, "")
	# Sync on again (fresh coordinator over the same store): the receipt resumes.
	var service := CloudSaveCoordinator.new(store, Fake.new())
	cloud.shutdown()
	cloud = CloudSaveSession.new(host, service, store)
	host.cloud_saves = cloud
	cloud.begin_session(CityFileFlow.application_recovery_path())
	check_eq(cloud.slot_id, "", "inert until enabled")
	service.set_enabled(true)
	cloud.tick(0.0)
	check_eq(cloud.slot_id, id, "the recovery rejoins its original slot instead of a duplicate")
	check_eq(host.save_path, path)

# Review 4: a Save As made while sync was off onto another city's name whose
# file is gone must not adopt that city's slot when sync starts.
func test_save_as_while_off_never_adopts_other_city() -> void:
	var name := "cloud-fix-off-" + CloudSaveTypes.uuid().left(6)
	var path := host.files.save_city_as(name)
	paths.append(path)
	var a := cloud.slot_id
	check_ne(a, "")
	var a_hash: String = cloud._local_library()._state.slots[a].continuation.sha256
	DirAccess.remove_absolute(path)
	host.begin_city(flat_city(), {}, 2, null)
	host.sim.city.name = "Bee"
	host.sim.city.funds = 77
	host.save_path = ""
	cloud.begin_session()
	var b := cloud.slot_id
	coordinator.set_enabled(false)
	check_eq(host.files.save_city_as(name), path)
	coordinator.set_enabled(true)
	cloud.tick(0.0)
	check_eq(cloud.slot_id, b, "B keeps its identity")
	var a_row: Dictionary = cloud._local_library()._state.slots[a]
	check_eq(a_row.continuation.sha256, a_hash, "A is untouched")
	check_ne(a_row.manual_path, path, "A's binding moved to a free name")
	check_eq(cloud._local_library()._state.slots[b].manual_path, path)

# Review 5: the destination note never names a cloud payload or a
# non-personal location, even with matching recovery bytes.
func test_recovery_destination_note_rejects_unsafe_paths() -> void:
	coordinator.set_enabled(false)
	var recovery := CityFileFlow.application_recovery_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(recovery.get_base_dir()))
	check_eq(SaveFormat.save(recovery, host.sim.city), OK)
	var sha := FileAccess.get_sha256(recovery)
	for unsafe in ["user://cloud-saves/local/payloads/x.sc2d", directory.path_join("elsewhere.sc2d"), CityFileFlow.autosave_path(), "user://saves/not-a-save.txt"]:
		var note := {"version": 1, "recovery": ProjectSettings.globalize_path(recovery).simplify_path(), "sha256": sha, "manual": unsafe}
		check_eq(SaveFormat._write_replacement(DESTINATION_NOTE, JSON.stringify(note).to_utf8_buffer()), OK)
		check_eq(CityFileFlow.recovery_destination(recovery), "", "rejects " + unsafe)
	var good := CityFileFlow.save_path_for("cloud-fix-note")
	CityFileFlow.write_recovery_destination(recovery, good)
	check_eq(CityFileFlow.recovery_destination(recovery), good)
	CityFileFlow.write_recovery_destination(recovery, "user://cloud-saves/local/payloads/x.sc2d")
	check(not FileAccess.file_exists(DESTINATION_NOTE), "unsafe destinations are never written")

# Review 7: Don't Save after a remote conflict forked this session's work
# retires the fork instead of restoring a duplicate city.
func test_dont_save_retires_session_fork() -> void:
	_verify()
	var id := _continuation_city("Forked")
	_open_continuation(id)
	host.sim.city.funds -= 9
	check_eq(cloud.capture(&"test"), OK)
	var work: Dictionary = _row(id).pending
	var fork := store.fork_pending(id, work.generation)
	check_ne(fork, "")
	coordinator.slot_forked.emit(id, fork)
	check_eq(cloud.slot_id, fork)
	check_eq(cloud.discard(), OK)
	check(_row(fork).tombstone, "the session's fork is retired")
	check(not _row(id).tombstone, "the original slot stays")
	check(_row(id).pending.is_empty(), "nothing is restored onto the original")

# Review 7: abandoned transport directories are removed even with dotfiles.
func test_stale_staging_with_hidden_files_is_removed() -> void:
	var root_dir := ProjectSettings.globalize_path(directory.path_join("staging"))
	var stale := root_dir.path_join(CloudSaveTypes.uuid())
	DirAccess.make_dir_recursive_absolute(stale.path_join(".nested"))
	var file := FileAccess.open(stale.path_join(".partial"), FileAccess.WRITE)
	file.store_string("x")
	file.close()
	file = FileAccess.open(stale.path_join(".nested/.inner"), FileAccess.WRITE)
	file.store_string("y")
	file.close()
	check_eq(AppleCloudPlatform.remove_stale_staging(root_dir), 1)
	check(not DirAccess.dir_exists_absolute(stale), "hidden entries do not keep the directory alive")

func _any_row(id: String) -> Dictionary:
	for library: CloudSaveStore in [store, cloud._local_library()]:
		if library._state.get("slots", {}).has(id): return library._state.slots[id]
	return {}

## A continuation-only city reopened from the library reserves its name with
## no file. Another city saved under that name while sync is off keeps its own
## identity when sync turns on, and when that file is loaded later.
func _reserve_name_then_save_other_city_while_off(name: String, funds: int) -> Dictionary:
	host.begin_city(flat_city(), {}, 123, null)
	host.sim.city.name = name
	host.save_path = ""
	cloud.begin_session()
	host.sim.city.funds = funds
	check_eq(cloud.capture(&"test"), OK)
	var a := cloud.slot_id
	var a_hash: String = _any_row(a).continuation.sha256
	host.begin_city(flat_city(), {}, 9, null)
	check(host.session.load_city(_any_row(a).continuation.path))
	check_eq(cloud.slot_id, a)
	check(not host.save_path.is_empty() and not FileAccess.file_exists(host.save_path), "the reopened city reserves its name without a file")
	coordinator.set_enabled(false)
	host.begin_city(flat_city(), {}, 2, null)
	host.sim.city.name = "Bee"
	host.sim.city.funds = 77
	host.save_path = ""
	cloud.begin_session()
	var path := host.files.save_city_as(name)
	paths.append(path)
	return {"a": a, "a_hash": a_hash, "path": path}

func test_deferred_join_never_adopts_a_reserved_slot() -> void:
	var setup := _reserve_name_then_save_other_city_while_off("deferred-res-" + CloudSaveTypes.uuid().left(6), 1111)
	coordinator.set_enabled(true)
	cloud.tick(0.0)
	check_ne(cloud.slot_id, setup.a, "the other city keeps its own slot")
	check_eq(_any_row(setup.a).continuation.get("sha256", ""), setup.a_hash, "the reserving city's continuation is untouched")

func test_loading_a_file_at_a_reserved_name_never_adopts_that_slot() -> void:
	var setup := _reserve_name_then_save_other_city_while_off("loaded-res-" + CloudSaveTypes.uuid().left(6), 2222)
	host.begin_city(flat_city(), {}, 3, null)
	coordinator.set_enabled(true)
	host.begin_city(flat_city(), {}, 4, null)
	cloud.begin_session()
	check(host.session.load_city(setup.path))
	check_ne(cloud.slot_id, setup.a, "the loaded city keeps its own slot")
	check_eq(_any_row(setup.a).continuation.get("sha256", ""), setup.a_hash, "the reserving city's continuation is untouched")

## Don't Save on Load while sync is off, then a native close prompts again and
## the player saves: the save wins and quitting stages no discard.
func test_save_after_inert_dont_save_cancels_the_discard() -> void:
	cloud.begin_session()
	var path := host.files.save_city_as("inert-discard-" + CloudSaveTypes.uuid().left(6))
	paths.append(path)
	var id := cloud.slot_id
	host.sim.city.funds -= 100
	check_eq(cloud.capture(&"test"), OK)
	coordinator.set_enabled(false)
	host.sim.city.funds -= 50
	check_eq(cloud.discard(true), OK)
	check_eq(host.files.save_city(), OK)
	check(not cloud._inert_discard_pending, "an explicit save cancels the pending Don't Save")
	var before: String = _any_row(id).continuation.get("sha256", "")
	cloud.end_session()
	check_eq(_any_row(id).continuation.get("sha256", ""), before, "quitting after the save stages no discard")
	check(not bool(_any_row(id).get("tombstone", false)))
