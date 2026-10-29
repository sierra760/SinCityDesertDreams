# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"

func test_refresh_keeps_selected_cloud_branch() -> void:
	var dialog := LoadDialog.new()
	root.add_child(dialog)
	var first := {"name": "One", "slot_id": "one", "cloud_owned": true, "path": "user://one.sc2d"}
	var second := {"name": "Two", "slot_id": "two", "cloud_owned": true, "path": "user://two.sc2d", "conflict_origin": "one"}
	dialog.open([first, second])
	dialog.select(1)
	dialog.refresh([first, second])
	check_eq(dialog.selected_path(), "user://two.sc2d", "refresh preserves selected slot, including a conflict branch")
	dialog.close()
	dialog.queue_free()
	await process_frame

func test_manual_action_and_pending_status_are_accessible_without_private_paths() -> void:
	var dialog := LoadDialog.new()
	root.add_child(dialog)
	check(dialog.has_signal("manual_load_requested"), "manual fallback has an action")
	check(dialog.has_method("set_sync_status"), "sync state has a presentation API")
	if not dialog.has_method("set_sync_status") or not dialog.has_signal("manual_load_requested"):
		dialog.free()
		return
	var entry := {"name": "Desert Town", "slot_id": "slot-one", "cloud_owned": true,
		"path": "user://cloud-saves/private-uuid.sc2d", "sync_state": "pending",
		"continuation_sha256": "new", "manual_sha256": "old", "manual": {"path": "user://cloud-saves/private-manual.sc2d"}}
	dialog.open([entry])
	dialog.call("set_sync_status", {"supported": true, "state": "pending", "enabled": true})
	check(not dialog.details_label.text.contains("private-uuid"), "cloud detail hides checkpoint filename")
	check(not dialog.item_list.get_item_tooltip(0).contains("private-uuid"), "tooltip hides private path")
	check(dialog.get("manual_button").visible, "differing manual point is reachable")
	check(dialog.get("manual_button").focus_mode == Control.FOCUS_ALL, "manual point supports keyboard")
	check_eq(dialog.get("sync_label").text, "Saved on this device — sync pending")
	var chosen: Array[String] = []
	dialog.connect("manual_load_requested", func(id: String) -> void: chosen.append(id))
	dialog.get("manual_button").pressed.emit()
	check_eq(chosen, ["slot-one"])
	entry.manual_sha256 = "new"
	dialog.open([entry])
	check(not dialog.get("manual_button").visible, "identical manual and continuation has only primary load")
	dialog.close()
	dialog.queue_free()
	await process_frame

const MAIN := preload("res://scenes/main.tscn")
const Fake := preload("res://tests/helpers/fake_apple_cloud.gd")
class FailingStore extends CloudSaveStore:
	var fail_writes := false
	var fail_receipts := false
	func record_manual_intent(transition: Dictionary) -> Error:
		return ERR_FILE_CANT_WRITE if fail_receipts else super.record_manual_intent(transition)
	func _write_journal(bytes: PackedByteArray) -> Error:
		return ERR_FILE_CANT_WRITE if fail_writes else super._write_journal(bytes)

var host: GameHost
var store: CloudSaveStore
var service: CloudSaveCoordinator
var fake: RefCounted
var directory := ""

func setup_host(verify: bool = true) -> void:
	directory = "user://cloud-ui/" + CloudSaveTypes.uuid()
	store = FailingStore.new(directory)
	check_eq(store.open_library(""), OK)
	fake = Fake.new()
	service = CloudSaveCoordinator.new(store, fake)
	host = MAIN.instantiate()
	host.cloud_saves = CloudSaveSession.new(host, service, store)
	host.preferences_path = directory.path_join("preferences.cfg")
	root.add_child(host)
	host.set_process(false)
	host.begin_city(flat_city(), {}, 123, null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.cloud_saves.begin_session()
	if verify:
		service.set_enabled(true)
		service.advance(0)
		fake.finish(fake.last("account"), {"owner": "account-a"})
		service.advance(0)
		fake.finish(fake.last("prepare_zone"))
		service.advance(0)

func after_each() -> void:
	if is_instance_valid(host): host.free()
	host = null
	await process_frame

func remote_city(id: String, title: String = "Remote Town") -> Dictionary:
	var path := directory.path_join(id + ".sc2d")
	var city := flat_city()
	city.name = title
	check_eq(SaveFormat.save(path, city), OK)
	return {"slot_id": id, "commit_id": id + "-head", "change_tag": "tag-1", "system_fields": PackedByteArray([1]),
		"continuation_sha256": FileAccess.get_sha256(path), "manual_sha256": "", "tombstone": false, "metadata": {"name": title}}

func inventory(records: Array) -> void:
	fake.finish(fake.last("changes"), {"records": records, "deleted_ids": [], "token": PackedByteArray([9]), "more": false})
	service.advance(1)
	for frame in 4: await process_frame

func select_slot(id: String) -> void:
	var entries := service.library_entries([])
	for i in entries.size():
		if entries[i].get("slot_id") == id:
			# The browser may also have local/included rows: locate its row by public selection.
			for index in host.load_dialog.item_list.item_count:
				host.load_dialog.select(index)
				if host.load_dialog.selected_entry().get("slot_id") == id: return
	check(false, "selected slot is visible")

func test_remote_wait_cancel_preserves_current_city_and_account_swap_removes_rows() -> void:
	setup_host()
	host.files.open_load_dialog()
	var old_city := host.sim.city
	await inventory([remote_city("remote-one")])
	check(host.load_dialog.has_signal("remote_load_requested"))
	select_slot("remote-one")
	host.load_dialog.confirm()
	check(host.load_dialog.visible, "download keeps cancellable modal visible")
	check(host.load_dialog.get("progress_label").visible, "download progress visible")
	check_eq(host.sim.city, old_city)
	var request: Dictionary = fake.last("download")
	host.load_dialog.close()
	fake.finish(request, {"downloaded": {"continuation": directory.path_join("remote-one.sc2d")}})
	service.advance(2)
	for frame in 6: await process_frame
	check_eq(host.sim.city, old_city, "cancelled download cannot replace city")
	host.files.open_load_dialog()
	select_slot("remote-one")
	fake.account_changed(service.status().epoch)
	service.advance(3)
	for frame in 4: await process_frame
	check_ne(host.load_dialog.selected_entry().get("slot_id", ""), "remote-one", "old-owner row disappears")
	check_eq(host.sim.city, old_city)

func test_setting_false_stops_requests_and_persists_without_deleting_payloads() -> void:
	setup_host()
	await inventory([])
	host.sim.city.funds -= 3
	check_eq(host.cloud_saves.capture(&"test"), OK)
	var payload: String = store.slots()[0].path
	check_eq(ViewPreferences.sanitize({"icloud_saves": "false"}).get("icloud_saves"), true)
	host.prefs.set_option(&"icloud_saves", false)
	check_eq(ViewPreferences.read(host.preferences_path).get("icloud_saves"), false)
	check_eq(service.status().enabled, false)
	var count: int = fake.requests.size()
	service.advance(100000)
	check_eq(fake.requests.size(), count, "disabled switch stops transfers")
	check(FileAccess.file_exists(payload), "switch retains payload")

func test_selected_manual_restores_different_slot_and_named_clean_baseline() -> void:
	setup_host()
	await inventory([])
	check(host.cloud_saves.has_method("restore_selected_manual"), "selected restore exists independently of active slot")
	if not host.cloud_saves.has_method("restore_selected_manual"): return
	var manual := directory.path_join("manual.sc2d")
	var newer := directory.path_join("newer.sc2d")
	var city := flat_city()
	city.name = "Chosen Town"
	city.funds = 1000
	SaveFormat.save(manual, city)
	city.funds = 700
	SaveFormat.save(newer, city)
	var named := CityFileFlow.save_path_for("cloud-ui-manual-" + CloudSaveTypes.uuid())
	var id := store.create_slot()
	check(not store.stage(id, newer, manual).is_empty())
	check_eq(store.bind_manual_path(id, named), OK)
	var old := host.sim.city
	check_eq(host.cloud_saves.call("restore_selected_manual", id, "wrong-owner", service.status().epoch), ERR_UNAUTHORIZED)
	check_eq(host.sim.city, old)
	check_eq(host.cloud_saves.call("restore_selected_manual", id, service.status().owner, service.status().epoch), OK)
	check_eq(host.cloud_saves.slot_id, id)
	check_eq(host.save_path, named)
	check_eq(host.sim.city.funds, 1000)
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	check(not host.files.has_unsaved_changes(), "manual restoration is clean")
	check_eq(store.pending().filter(func(work: Dictionary) -> bool: return work.slot_id == id).size(), 1, "intentional new continuation remains pending")
	DirAccess.remove_absolute(named)

func test_visible_library_refresh_is_throttled_and_selected_download_keeps_page_durable() -> void:
	setup_host()
	await inventory([remote_city("first"), remote_city("middle"), remote_city("chosen")])
	host.files.open_load_dialog()
	select_slot("chosen")
	host.load_dialog.confirm()
	var current: Dictionary = fake.last("download")
	check_eq(current.args.remote.slot_id, "first")
	check_eq(fake.count("download"), 1)
	fake.finish(current, {"downloaded": {"continuation": directory.path_join("first.sc2d")}})
	service.advance(2)
	check_eq(fake.last("download").args.remote.slot_id, "chosen", "selection is next without adding a download lane")
	check(store.change_token().is_empty(), "unpublished page members keep prior token")
	fake.finish(fake.last("download"), {"downloaded": {"continuation": directory.path_join("chosen.sc2d")}})
	service.advance(3)
	for frame in 8: await process_frame
	check_eq(host.sim.city.name, "Remote Town")
	check_eq(host.cloud_saves.slot_id, "chosen", "only selected slot enters session")
	check_eq(host.sim.speed, GameClock.Speed.PAUSED)
	check_eq(fake.last("download").args.remote.slot_id, "middle")
	check(store.change_token().is_empty())
	fake.finish(fake.last("download"), {"downloaded": {"continuation": directory.path_join("middle.sc2d")}})
	service.advance(4)
	var count: int = fake.count("changes")
	check_eq(count, 1, "opening during a page does not schedule redundant inventory")
	host.files.open_load_dialog()
	service.advance(5)
	check_eq(fake.count("changes"), count, "reopening before 30 seconds does not refetch")
	service.advance(30001)
	check_eq(fake.count("changes"), 2)

func test_account_swap_during_presented_frame_cannot_load_cached_city() -> void:
	setup_host()
	await inventory([remote_city("cached")])
	fake.finish(fake.last("download"), {"downloaded": {"continuation": directory.path_join("cached.sc2d")}})
	service.advance(2)
	host.files.open_load_dialog()
	select_slot("cached")
	var previous := host.sim.city
	host.set_process(true)
	host.load_dialog.confirm()
	check(host.loading_screen.visible)
	fake.account_changed(service.status().epoch)
	for frame in 8: await process_frame
	check_eq(host.sim.city, previous)
	check(not host.loading_screen.visible)

func test_manual_from_title_and_invalid_manual_preserve_current_city() -> void:
	setup_host()
	await inventory([])
	var remote := remote_city("manual-title", "Title Town")
	remote.manual_sha256 = remote.continuation_sha256
	remote.continuation_sha256 = ""
	remote.tombstone = true
	# Use a normal published manual/continuation pair for the browser.
	remote.tombstone = false
	remote.continuation_sha256 = remote.manual_sha256
	var source := directory.path_join("manual-title.sc2d")
	check_eq(store.publish_remote(remote, {"manual": source, "continuation": source}), OK)
	var old := host.sim.city
	var row: Dictionary = store.slots().filter(func(entry: Dictionary) -> bool: return entry.slot_id == "manual-title")[0]
	var manual_path: String = row.manual.path
	var bytes := FileAccess.get_file_as_bytes(manual_path)
	FileAccess.open(manual_path, FileAccess.WRITE).store_string("broken")
	check_eq(host.cloud_saves.restore_selected_manual("manual-title", service.status().owner, service.status().epoch), ERR_FILE_CORRUPT)
	check_eq(host.sim.city, old)
	FileAccess.open(manual_path, FileAccess.WRITE).store_buffer(bytes)
	store.fail_writes = true
	check_eq(host.cloud_saves.restore_selected_manual("manual-title", service.status().owner, service.status().epoch), ERR_CANT_CREATE)
	check_eq(host.sim.city, old, "journal failure preserves active city")
	store.fail_writes = false
	host.in_game = false
	host.cloud_saves.end_session()
	check_eq(host.cloud_saves.restore_selected_manual("manual-title", service.status().owner, service.status().epoch), OK)
	check_eq(host.sim.city.name, "Title Town")
	check_eq(host.cloud_saves.slot_id, "manual-title")
	check(not host.files.has_unsaved_changes())
	DirAccess.remove_absolute(host.save_path)

func test_phone_tablet_controls_fit_and_unsupported_options_stay_local() -> void:
	setup_host(false)
	host.display_layout.set_ui_scale(100)
	for profile in [[Vector2i(640,1136), Rect2i(0,40,640,1096)], [Vector2i(1536,2048), Rect2i(0,48,1536,1960)]]:
		root.min_size = Vector2i(1,1)
		root.size = profile[0]
		host.display_layout.refresh_with_mobile_metrics(profile[0], 2.0, profile[1], 0, "iOS")
		var dialog := host.load_dialog
		dialog.open([{"name":"Test Town", "slot_id":"layout", "cloud_owned":true, "path":"user://private.sc2d", "continuation_sha256":"new", "manual_sha256":"old", "manual":{"path":"user://manual.sc2d"}}])
		dialog.set_sync_status({"supported":true, "state":"pending"})
		for frame in 8: await process_frame
		var usable := host.display_layout.logical_rect()
		check(usable.grow(1).encloses(dialog.panel.get_global_rect()), "panel inside usable bounds")
		for button: Button in [dialog.load_button, dialog.cancel_button, dialog.browse_button, dialog.share_button, dialog.manual_button]:
			check(button.size.y >= 44, "%s is at least 44pt" % button.text)
		check(dialog.item_list.get_item_rect(0).size.y >= 44, "save row touch target is 44pt")
		dialog.manual_button.grab_focus()
		for frame in 4: await process_frame
		check(usable.grow(1).encloses(dialog.manual_button.get_global_rect()), "focused manual action in usable bounds")
		dialog.close()
	var options := host.window_manager.open("options") as OptionsWindow
	options.set_sync_status({"supported":false, "state":"unavailable"})
	check(not (options.checks[&"icloud_saves"] as CheckBox).visible)
	check(not options.sync_label.visible)
	options.set_sync_status({"supported":true,"state":"quota"})
	check(options.sync_label.text.contains("storage is full"))
	check((options.checks[&"icloud_saves"] as CheckBox).custom_minimum_size.y >= 44)
	options.close()


func test_last_presented_frame_revokes_manual_load_without_test_driven_pump() -> void:
	setup_host()
	await inventory([])
	var source := directory.path_join("frame-manual.sc2d")
	var newer := directory.path_join("frame-new.sc2d")
	var city := flat_city()
	city.name = "Other Town"
	SaveFormat.save(source, city)
	city.funds -= 10
	SaveFormat.save(newer, city)
	var id := store.create_slot()
	check(not store.stage(id, newer, source).is_empty())
	host.files.open_load_dialog()
	select_slot(id)
	var old := host.sim.city
	var epoch: int = service.status().epoch
	var frames := [0]
	# Connected before loading's await: queues revocation at the second
	# process_frame signal, immediately before headless work resumes.
	var revoke := func() -> void:
		frames[0] += 1
		if frames[0] == 2: fake.account_changed(epoch)
	process_frame.connect(revoke)
	host.set_process(true)
	host.load_dialog.manual_button.pressed.emit()
	check(host.loading_screen.visible)
	for frame in 8: await process_frame
	process_frame.disconnect(revoke)
	check_eq(host.sim.city, old, "last-frame queued revocation preserves active city")
	check_eq(service.status().owner, "")

func test_conflict_copy_roundtrip_keeps_coarse_device_date_and_identity() -> void:
	setup_host()
	await inventory([])
	var source := directory.path_join("conflict.sc2d")
	var city := flat_city()
	city.name = "Same Name"
	SaveFormat.save(source, city)
	var original := store.create_slot()
	var pending := store.stage(original, source)
	var alternate := store.fork_pending(original, pending.generation)
	service.advance(2)
	fake.finish(fake.last("fetch_record"), {"remote": {}})
	service.advance(3)
	var upload: Dictionary = fake.last("save")
	check(not upload.is_empty())
	if upload.is_empty(): return
	check_eq(upload.args.metadata.get("conflict_origin", ""), original, "branch annotation crosses generic metadata boundary")
	check(AppleCloudPlatform.valid_request(upload), "native boundary accepts additive metadata")
	var second := CloudSaveStore.new(directory.path_join("second-device"))
	second.open_library("account-b")
	var other := Fake.new()
	var receiver := CloudSaveCoordinator.new(second, other)
	receiver.set_enabled(true)
	receiver.advance(0)
	other.finish(other.last("account"), {"owner":"account-b"})
	receiver.advance(0)
	other.finish(other.last("prepare_zone"))
	receiver.advance(0)
	# The branch arrives from a Mac whatever system runs the test; only Apple
	# platforms record a device label.
	var metadata: Dictionary = upload.args.metadata.duplicate()
	metadata.source_device_label = "macOS"
	var remote := {"slot_id":alternate,"commit_id":upload.args.pending.commit_id,"change_tag":"branch-tag","system_fields":PackedByteArray([4]),
		"continuation_sha256":upload.args.pending.continuation.sha256,"manual_sha256":"","tombstone":false,"metadata":metadata}
	other.finish(other.last("changes"), {"records":[remote],"deleted_ids":[],"token":PackedByteArray([6]),"more":false})
	receiver.advance(1)
	var waiting := receiver.library_entries([])
	check_eq(waiting.size(), 1)
	check_eq(waiting[0].slot_id, alternate)
	check_eq(waiting[0].get("conflict_origin", ""), original, "waiting branch retains conflict annotation before its assets arrive")
	check_eq(waiting[0].get("source_device_label", ""), "macOS")
	check_eq(waiting[0].path, "", "remote row has no unvalidated local path")
	host.load_dialog.open(waiting)
	check(host.load_dialog.item_list.get_item_text(0).contains("Conflict copy"))
	check(host.load_dialog.item_list.get_item_text(0).contains("Mac"))
	check(host.load_dialog.details_label.text.contains("Conflict copy · Mac"))
	check(host.load_dialog.share_button.disabled)
	host.load_dialog.close()
	other.finish(other.last("download"), {"downloaded":{"continuation":upload.args.pending.continuation.path}})
	receiver.advance(2)
	var entries := receiver.library_entries([])
	check_eq(entries.size(), 1)
	check_eq(entries[0].slot_id, alternate)
	check_eq(entries[0].get("conflict_origin", ""), original)
	check_eq(entries[0].get("source_device_label", ""), "macOS")
	var original_row := entries[0].duplicate(true)
	original_row.slot_id = original
	original_row.conflict_origin = ""
	host.load_dialog.open([original_row, entries[0]])
	host.load_dialog.select(1)
	check(host.load_dialog.item_list.get_item_text(1).contains("Mac"), "same-name alternate row identifies source")
	check(host.load_dialog.item_list.get_item_text(1).contains(LoadDialog.saved_text(entries[0]).left(10)), "alternate row identifies date")
	check(host.load_dialog.details_label.text.contains("Mac"))
	check(not host.load_dialog.details_label.text.contains(original), "raw slot identifier stays private")
	var unsafe := entries[0].duplicate(true)
	unsafe.source_device_label = "private-device-uuid-or-hardware-model"
	host.load_dialog.refresh([unsafe])
	check(not host.load_dialog.details_label.text.contains("private-device"))
	receiver.shutdown()

func test_actual_foreground_notifications_refresh_once_with_hidden_library() -> void:
	setup_host()
	await inventory([])
	var before: int = fake.count("changes")
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	service.advance(100000)
	check_eq(fake.count("changes"), before + 1, "actual focus-in requests a fresh inventory")
	host._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	service.advance(100001)
	fake.finish(fake.last("changes"), {"records": [], "deleted_ids": [], "token": PackedByteArray([10]), "more": false})
	service.advance(100002)
	check_eq(fake.count("changes"), before + 1, "paired focus/resume events coalesce")
	host.cloud_saves.end_session()
	host.in_game = false
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	# No scheduler advance occurs across suspension or before the return event.
	# The first resumed tick is far later than the last sampled scheduler time.
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	service.advance(200001)
	check_eq(fake.count("changes"), before + 2, "title-screen focus also refreshes")
	service.set_enabled(false)
	var count: int = fake.requests.size()
	host._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	service.advance(300000)
	check_eq(fake.requests.size(), count, "disabled lifecycle has no account or network work")
	fake.supported = false
	service.set_enabled(true)
	host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	service.advance(400000)
	check_eq(fake.requests.size(), count, "unsupported lifecycle has no account or network work")

func test_new_remote_overlays_old_cached_slot_until_download_cancel_or_failure() -> void:
	setup_host()
	await inventory([])
	var old := remote_city("cached-slot", "Old cached state")
	check_eq(store.publish_remote(old, {"continuation": directory.path_join("cached-slot.sc2d")}), OK)
	var old_path: String = store.slots().filter(func(entry: Dictionary) -> bool: return entry.slot_id == "cached-slot")[0].path
	var fresh := remote_city("fresh-asset", "New remote state")
	fresh.slot_id = "cached-slot"
	fresh.commit_id = "new-head"
	fresh.change_tag = "new-tag"
	host.files.open_load_dialog()
	service._page = {"items": [fresh], "token": PackedByteArray([10]), "more": false}
	service._process_page()
	host.files._refresh_cloud_library()
	select_slot("cached-slot")
	var selected := host.load_dialog.selected_entry()
	check(selected.get("pending_download", false), "known new version masks stale load intent")
	check_eq(selected.path, "")
	if not selected.get("pending_download", false): return
	var city := host.sim.city
	host.load_dialog.confirm()
	check(host.load_dialog.visible)
	check(not host.files._cloud_load_intent.is_empty())
	host.load_dialog.close()
	check(host.files._cloud_load_intent.is_empty())
	check_eq(host.sim.city, city)
	check(FileAccess.file_exists(old_path), "cancel preserves cached bytes")
	fake.finish(fake.last("download"), {}, "transient")
	service.advance(2)
	host.files.open_load_dialog()
	select_slot("cached-slot")
	check_eq(host.load_dialog.selected_entry().path, old_path, "failed download exposes validated cached fallback")
	check_ne(host.load_dialog.selected_entry().sync_state, "synced")
	fake.account_changed(service.status().epoch)
	service.advance(3)
	host.files._refresh_cloud_library()
	check_ne(host.load_dialog.selected_entry().get("slot_id", ""), "cached-slot")

func test_capture_failures_report_status_and_notice_until_durable_retry() -> void:
	setup_host()
	await inventory([])
	for trigger in ["periodic", "background", "manual"]:
		store.fail_writes = true
		host.sim.city.funds -= 1
		var named := ""
		if trigger == "periodic": host.cloud_saves.tick(60.0)
		elif trigger == "background": host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		else:
			named = host.files.save_city_as("final-stage-error-" + CloudSaveTypes.uuid())
			check(not named.is_empty(), "local Save remains successful")
		check_eq(service.status().state, "local_io", trigger + " cannot claim synced")
		check(host.notice_dialog.is_open(), trigger + " reports local staging failure")
		var queued: int = host.notices._queue.size()
		check_ne(host.cloud_saves.capture(&"repeat_failure"), OK)
		check_eq(host.notices._queue.size(), queued, "repeated local error does not queue duplicate notices")
		store.fail_writes = false
		check_eq(host.cloud_saves.capture(&"retry"), OK)
		check_ne(service.status().state, "local_io", "durable retry clears capture error")
		if host.notice_dialog.is_open(): host.notice_dialog.dismiss()
		if not named.is_empty(): DirAccess.remove_absolute(named)

func test_successful_named_save_stage_failure_restart_keeps_latest_manual_reachable() -> void:
	setup_host()
	await inventory([])
	var name := "final-manual-restart-" + CloudSaveTypes.uuid()
	var path := host.files.save_city_as(name)
	check(not path.is_empty())
	var id := host.cloud_saves.slot_id
	var work := store.pending()[0]
	store.begin_upload(id, work.generation)
	check_eq(store.acknowledge(id, work.generation, work.commit_id, PackedByteArray([1]), "ack"), OK)
	host.sim.city.funds -= 1234
	store.fail_writes = true
	check_eq(host.files.save_city(), OK)
	var latest := FileAccess.get_sha256(path)
	var latest_funds := host.sim.city.funds
	var old_hash: String = store.slots().filter(func(entry: Dictionary) -> bool: return entry.slot_id == id)[0].manual_sha256
	check_ne(latest, old_hash)
	host.free()
	host = null
	await process_frame
	var reopened := CloudSaveStore.new(directory)
	check_eq(reopened.open_library("account-a"), OK)
	check_eq(reopened.migrate_personal_file(path), OK)
	var resumed := CloudSaveCoordinator.new(reopened, Fake.new())
	resumed._owner = "account-a"
	resumed._enabled = true
	var entries := resumed.library_entries([SaveFormat.read_header(path)])
	var found := false
	for entry in entries:
		if not entry.get("path", "").is_empty() and SaveFormat.load(entry.path).city.funds == latest_funds: found = true
	check(found, "latest successful named Save survives restart in normal Load")
	check(not reopened.pending().is_empty(), "recoverable manual intent resumes syncing")
	resumed.shutdown()
	DirAccess.remove_absolute(path)

func test_save_as_failed_stage_restart_preserves_advanced_destination_and_account() -> void:
	setup_host()
	await inventory([])
	var suffix := CloudSaveTypes.uuid()
	var destination := host.files.save_city_as("final-destination-" + suffix)
	var target := host.cloud_saves.slot_id
	var work := store.pending()[0]
	store.begin_upload(target, work.generation)
	check_eq(store.acknowledge(target, work.generation, work.commit_id, PackedByteArray([1]), "ack"), OK)
	var source := host.files.save_city_as("final-source-" + suffix)
	host.sim.city.funds -= 1234
	store.fail_writes = true
	check_eq(host.files.save_city_as("final-destination-" + suffix), destination)
	var latest := FileAccess.get_sha256(destination)
	host.free()
	host = null
	await process_frame
	var reopened := CloudSaveStore.new(directory)
	check_eq(reopened.open_library("account-b"), OK)
	check_eq(reopened.migrate_personal_file(destination), OK)
	check_eq(reopened.pending().size(), 0, "old owner's receipt cannot be replayed in replacement account")
	check_eq(reopened.open_library("account-a"), OK)
	var remote_path := directory.path_join("advanced.sc2d")
	var remote_city_data := flat_city()
	remote_city_data.funds -= 5000
	check_eq(SaveFormat.save(remote_path, remote_city_data), OK)
	var digest := FileAccess.get_sha256(remote_path)
	var remote := {"slot_id": target, "commit_id": "advanced-head", "change_tag": "advanced-tag", "system_fields": PackedByteArray([3]), "continuation_sha256": digest, "manual_sha256": digest, "tombstone": false, "metadata": {}}
	check_eq(reopened.publish_remote(remote, {"continuation": remote_path, "manual": remote_path}), OK)
	check_eq(reopened.migrate_personal_file(destination), OK)
	var manual_branch: Dictionary = {}
	var original: Dictionary = {}
	for entry in reopened.slots():
		if entry.manual_sha256 == latest: manual_branch = entry
		if entry.slot_id == target: original = entry
	check(not manual_branch.is_empty(), "successful Replace becomes reachable independent branch")
	check_ne(manual_branch.get("slot_id", ""), target)
	check_eq(original.continuation_sha256, digest, "advanced destination is preserved")
	check_eq(original.manual_sha256, digest)
	check_eq(manual_branch.get("manual_path", ""), destination)
	check_eq(FileAccess.get_sha256(destination), latest)
	check_eq(reopened.migrate_personal_file(destination), OK, "repeated migration is idempotent")
	DirAccess.remove_absolute(source)
	DirAccess.remove_absolute(destination)

func test_failed_receipt_and_journal_keep_changed_named_file_visible_without_auto_upload() -> void:
	setup_host()
	await inventory([])
	var path := host.files.save_city_as("final-no-receipt-" + CloudSaveTypes.uuid())
	var id := host.cloud_saves.slot_id
	var work := store.pending()[0]
	store.begin_upload(id, work.generation)
	check_eq(store.acknowledge(id, work.generation, work.commit_id, PackedByteArray([1]), "ack"), OK)
	var size := FileAccess.get_file_as_bytes(path).size()
	host.sim.city.funds -= 1234
	store.fail_writes = true
	store.fail_receipts = true
	check_eq(host.files.save_city(), OK)
	check_eq(FileAccess.get_file_as_bytes(path).size(), size, "same-size valid named replacement")
	var digest := FileAccess.get_sha256(path)
	check_eq(service.status().state, "local_io")
	host.free()
	host = null
	await process_frame
	var reopened := CloudSaveStore.new(directory)
	check_eq(reopened.open_library("account-a"), OK)
	check_eq(reopened.migrate_personal_file(path), OK)
	check_eq(reopened.pending().size(), 0, "no receipt means no automatic mismatch upload")
	var resumed := CloudSaveCoordinator.new(reopened, Fake.new())
	resumed._enabled = true
	resumed._owner = "account-a"
	var entries := resumed.library_entries([SaveFormat.read_header(path)])
	var reachable := false
	for entry in entries:
		if entry.get("path", "") == path: reachable = FileAccess.get_sha256(entry.path) == digest
	check(reachable, "unproven named mismatch stays reachable as local save")
	check_eq(entries.size(), 2, "prior cloud branch survives independently")
	check_eq(resumed.status().state, "local_only", "restart does not claim unproven local save is synced")
	resumed.shutdown()
	DirAccess.remove_absolute(path)

func test_unchanged_capture_does_not_hide_unresolved_journal_error() -> void:
	setup_host()
	await inventory([])
	service._fail("local_io", 0)
	check_eq(host.cloud_saves.capture(&"unchanged"), OK)
	check_eq(service.status().state, "local_io", "unchanged content is not evidence a failed publication recovered")

func test_normal_continuation_load_never_uses_substituted_manual_payload() -> void:
	setup_host()
	await inventory([])
	for existing_named in [false, true]:
		var personal_before: Array[String] = []
		for header in SaveFormat.list_saves(): personal_before.append(header.path)
		var city := flat_city()
		city.name = "Alpha"
		var manual_path := directory.path_join("manual-source.sc2d")
		check_eq(SaveFormat.save(manual_path, city), OK)
		city.funds -= 1234
		var continuation_path := directory.path_join("continuation-source.sc2d")
		check_eq(SaveFormat.save(continuation_path, city), OK)
		var id := CloudSaveTypes.uuid()
		var remote := {"slot_id": id, "commit_id": CloudSaveTypes.uuid(), "change_tag": "manual-check", "system_fields": PackedByteArray([1]), "continuation_sha256": FileAccess.get_sha256(continuation_path), "manual_sha256": FileAccess.get_sha256(manual_path), "tombstone": false, "metadata": {}}
		check_eq(store.publish_remote(remote, {"continuation": continuation_path, "manual": manual_path}), OK)
		var named := ""
		if existing_named:
			named = CityFileFlow.save_path_for("final-manual-integrity-" + id)
			check_eq(SaveFormat._write_replacement(named, FileAccess.get_file_as_bytes(manual_path)), OK)
			check_eq(store.bind_manual_path(id, named), OK)
			personal_before.append(named)
		var entry: Dictionary = store.slots().filter(func(row: Dictionary) -> bool: return row.slot_id == id)[0]
		var original := FileAccess.get_file_as_bytes(entry.manual.path)
		var substituted := original.get_string_from_utf8().replace("Alpha", "Bravo").to_utf8_buffer()
		check_eq(substituted.size(), original.size())
		check_eq(SaveFormat._write_replacement(entry.manual.path, substituted), OK)
		check_eq(store.payload_metadata(entry.manual), {}, "descriptor rejects substituted valid manual bytes")
		check(host.session.load_city(entry.path), "valid requested continuation remains playable")
		check_eq(host.sim.city.funds, city.funds)
		check_eq(host.sim.city.name, "Alpha")
		check_eq(host.cloud_saves.slot_id, id)
		check_eq(host.save_path, "", "bad manual asset cannot establish a save destination")
		check(host.files._saved_content.is_empty(), "bad manual asset cannot establish the saved baseline")
		check(host.files.has_unsaved_changes())
		check_eq(service.status().state, "local_io")
		check_eq(host.cloud_saves.capture(&"unchanged_after_bad_manual"), ERR_FILE_CORRUPT, "periodic retry cannot silently clear manual-integrity failure")
		check_eq(host.cloud_saves.discard(), ERR_FILE_CORRUPT, "Discard cannot use the substituted manual payload")
		var retained: Dictionary = store.slots().filter(func(row: Dictionary) -> bool: return row.slot_id == id)[0]
		check_eq(retained.continuation_sha256, remote.continuation_sha256, "failed Discard preserves valid continuation")
		for header in SaveFormat.list_saves():
			if header.path not in personal_before:
				check(false, "normal Load must not materialize substituted manual bytes")
				DirAccess.remove_absolute(header.path)
		if not named.is_empty():
			check_eq(FileAccess.get_file_as_bytes(named), original, "existing named file remains unchanged")
			check_eq(host.files.save_city_as(named.get_file().get_basename()), named, "explicit Save repairs manual integrity")
			check_eq(host.save_path, named)
			check(not host.files.has_unsaved_changes())
			check_ne(service.status().state, "local_io", "successful explicit Save clears integrity error")
			DirAccess.remove_absolute(named)
		else:
			check_eq(SaveFormat._write_replacement(entry.manual.path, original), OK)
			check_eq(host.cloud_saves.restore_manual(), OK, "verified explicit restore repairs integrity state")
			check_eq(host.sim.city.funds, 20000)
			check(not host.files.has_unsaved_changes())
			check_ne(service.status().state, "local_io", "verified explicit restore clears integrity error")
		if host.notice_dialog.is_open(): host.notice_dialog.dismiss()
