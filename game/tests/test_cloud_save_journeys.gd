# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const MAIN := preload("res://scenes/main.tscn")
const SharedService := preload("res://tests/helpers/shared_apple_cloud.gd")
## Hosts share a Godot process/user root only in this fixture. Filter migration
## to each device's named saves, emulating independent application sandboxes.
class DeviceCoordinator extends CloudSaveCoordinator:
	var personal_paths: Array[String] = []
	func migrate_personal_saves(headers: Array[Dictionary]) -> Error:
		var own: Array[Dictionary] = []
		for header in headers:
			if header.get("path", "") in personal_paths: own.append(header)
		return super.migrate_personal_saves(own)
class BoundaryStore extends CloudSaveStore:
	var boundary := ""
	func _write_journal(bytes: PackedByteArray) -> Error:
		if boundary == "payload": return ERR_CANT_CREATE
		if boundary == "staged":
			SaveFormat._write_replacement(journal_path() + ".pending", bytes)
			return ERR_CANT_CREATE
		return super._write_journal(bytes)
var service: RefCounted
var devices: Array[Dictionary] = []
var directory: String
var now := 1000
var manual_paths: Array[String] = []
var original_personal_paths: Array[String] = []
var personal_before_each: Array[String] = []
func before_all() -> void:
	for entry in SaveFormat.list_saves(): original_personal_paths.append(entry.path)
func after_all() -> void:
	for entry in SaveFormat.list_saves(): check(entry.path in original_personal_paths, "journey leaves no synthetic personal save for following suites")
func before_each() -> void:
	personal_before_each.clear()
	for entry in SaveFormat.list_saves(): personal_before_each.append(entry.path)
	directory = "user://shared-cloud-journey/" + CloudSaveTypes.uuid()
	service = SharedService.new(directory.path_join("service"))
	now = 1000
func after_each() -> void:
	for device in devices: device.host.free()
	devices.clear()
	# Hosts are stopped before cleanup. A downloaded manual file may have been
	# materialized by B without an explicit Save As in this fixture.
	for entry in SaveFormat.list_saves():
		if entry.path not in personal_before_each: DirAccess.remove_absolute(entry.path)
	manual_paths.clear()
	await process_frame
func device(name: String, existing: String = "") -> Dictionary:
	var path := directory.path_join(name) if existing.is_empty() else existing
	var store := BoundaryStore.new(path)
	check_eq(store.open_library(""), OK)
	var endpoint = service.endpoint()
	var coordinator := DeviceCoordinator.new(store, endpoint)
	coordinator.jitter = func(): return 0.0
	var host: GameHost = MAIN.instantiate()
	host.preferences_path = path.path_join("preferences.cfg")
	host.cloud_saves = CloudSaveSession.new(host, coordinator, store)
	root.add_child(host)
	host.set_process(false)
	host.begin_city(flat_city(), {}, 173, null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.save_path = ""
	host.cloud_saves.begin_session()
	var result := {"host":host, "store":store, "coordinator":coordinator, "endpoint":endpoint, "root":path}
	devices.append(result)
	coordinator.set_enabled(true)
	return result
func pump(rounds: int = 24) -> void:
	for i in rounds:
		now += 100
		for item in devices: item.coordinator.advance(now)
		service.step()
func refresh(item: Dictionary) -> void:
	item.host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	item.host._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	pump()
func row(item: Dictionary, id: String = "") -> Dictionary:
	for value in item.store.slots():
		if value.slot_id == (item.host.cloud_saves.slot_id if id.is_empty() else id): return value
	return {}
func play(item: Dictionary, amount: int) -> Dictionary:
	var host: GameHost = item.host
	host.sim.city.funds -= amount
	host.sim.city.set_heights(3, 4, 4 + amount % 8, 0)
	host.sim.advance_days(2)
	check(host.mod_progress.commit("synthetic_journey", 1, "1.0", {"deliveries":amount, "route":[1, 3, 5]}).ok)
	var expected := snapshot(host)
	check_eq(host.cloud_saves.capture(&"test"), OK)
	check_eq(snapshot(host), expected, "capture leaves exact city/runtime/mod state unchanged")
	return expected
func canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)
func snapshot(host: GameHost) -> Dictionary:
	return {"funds":host.sim.city.funds, "altitude_bytes":host.sim.city.altitude.data.duplicate(), "terrain_bytes":host.sim.city.terrain.data.duplicate(), "rng_state":host.sim.snapshot().rng_state, "city":canonical(SaveFormat.encode_city(host.sim.city)), "runtime":canonical(host.sim.snapshot()), "mods":canonical(host.explore_progress_snapshot())}
func load_slot(item: Dictionary, id: String) -> void:
	var entry := row(item, id)
	check(not entry.is_empty(), "shared-service slot is locally published")
	if entry.is_empty(): return
	check(item.host.load_city(entry.path))
	check_eq(item.host.sim.speed, GameClock.Speed.PAUSED)
func test_two_hosts_transfer_continue_then_keep_both_offline_branches() -> void:
	var a := device("a")
	pump()
	var expected := play(a, 111)
	var id: String = a.host.cloud_saves.slot_id
	pump()
	var b := device("b")
	pump()
	load_slot(b, id)
	check_eq(snapshot(b.host), expected, "funds/terrain/RNG/systems/mods transfer exactly")
	# Both restored and uninterrupted simulations take the same next days.
	a.host.sim.advance_days(3)
	b.host.sim.advance_days(3)
	check_eq(snapshot(b.host), snapshot(a.host), "three-day simulation continuation is exact")
	var continued := play(b, 222)
	pump()
	refresh(a)
	check_ne(a.host.cloud_saves.slot_id, id, "foreground keeps active ancestor independently")
	load_slot(a, id)
	check_eq(snapshot(a.host), continued)
	a.endpoint.online = false
	b.endpoint.online = false
	var a_branch := play(a, 333)
	var b_branch := play(b, 444)
	a.endpoint.online = true
	pump()
	b.endpoint.online = true
	pump()
	refresh(a)
	refresh(b)
	var seen_a := false
	var seen_b := false
	for entry in a.store.slots():
		if entry.path.is_empty(): continue
		load_slot(a, entry.slot_id)
		var value := snapshot(a.host)
		seen_a = seen_a or value == a_branch
		seen_b = seen_b or value == b_branch
	check(seen_a and seen_b, "both exact offline branches survive shared conditional writes")
	check(service.records().size() >= 2)
func test_discard_after_upload_reaches_second_host_and_keeps_named_manual() -> void:
	var a := device("a")
	pump()
	var name := "journey-manual-" + CloudSaveTypes.uuid()
	var path: String = a.host.files.save_city_as(name)
	manual_paths.append(path)
	a.coordinator.personal_paths.append(path)
	var expected := snapshot(a.host)
	var id: String = a.host.cloud_saves.slot_id
	pump()
	play(a, 555)
	pump()
	check_eq(a.host.cloud_saves.discard(), OK)
	pump()
	var b := device("b")
	pump()
	load_slot(b, id)
	check_eq(snapshot(b.host), expected, "discarded uploaded continuation never resurrects")
	check_eq(a.host.save_path, path)
	check_eq(SaveFormat.load(path).city.funds, a.host.sim.city.funds + 555)
func restart(item: Dictionary) -> Dictionary:
	var path: String = row(item).get("path", "")
	var root_path: String = item.root
	item.endpoint.online = false
	item.host.free()
	devices.erase(item)
	var next := device("restart", root_path)
	pump()
	if not path.is_empty(): check(next.host.load_city(path))
	return next
func test_uncertain_commit_restart_and_superseded_callback_keep_newer_work() -> void:
	var a := device("a")
	pump()
	a.endpoint.lose_next_save_ack = true
	play(a, 101)
	pump()
	var request: Dictionary = a.endpoint.last("save")
	check_eq(a.store.inflight().size(), 1)
	var newest := play(a, 202)
	# A late successful response must acknowledge only the old generation.
	var remote: Dictionary = service.records()[request.args.pending.slot_id].remote
	a.endpoint.finish(request, {"commit_id":remote.commit_id, "change_tag":remote.change_tag, "system_fields":remote.system_fields})
	a.coordinator.advance(now + 1)
	check_eq(a.store.pending().size(), 1)
	a.endpoint.lose_next_save_ack = true
	pump()
	a = restart(a)
	pump()
	check_eq(a.store.inflight().size(), 0)
	check_eq(a.store.pending().size(), 0)
	var id: String = a.host.cloud_saves.slot_id
	var b := device("b")
	pump()
	load_slot(b, id)
	check_eq(snapshot(b.host), newest)
func test_damaged_download_and_account_swap_cannot_publish_wrong_bytes() -> void:
	var a := device("a")
	pump()
	var expected := play(a, 909)
	var id: String = a.host.cloud_saves.slot_id
	pump()
	var b := device("b")
	b.endpoint.corrupt_next_download = true
	pump(6)
	check(row(b, id).is_empty(), "damaged bytes are absent")
	check_eq(b.coordinator.status().error, "invalid")
	pump()
	load_slot(b, id)
	check_eq(snapshot(b.host), expected)
	play(a, 808)
	pump()
	b.endpoint.hold = "download"
	b.coordinator.refresh(&"foreground")
	pump(6)
	var held: Dictionary = b.endpoint.last("download")
	check(not held.is_empty())
	b.endpoint.hold = ""
	service.step() # Real old-account asset result is queued before revocation.
	check(not b.endpoint.completions.is_empty())
	b.endpoint.owner = "replacement-account"
	b.endpoint.account_changed(b.coordinator.status().epoch)
	pump()
	check_eq(b.coordinator.status().owner, "replacement-account")
	check_eq(b.store.slots().size(), 0, "old account completion cannot enter replacement library")
	check_eq(b.host.cloud_saves.capture(&"test"), ERR_UNAUTHORIZED)
func test_restart_at_payload_staged_journal_and_published_boundaries() -> void:
	for boundary in ["payload", "staged", "published"]:
		var a := device(boundary)
		pump()
		play(a, 10)
		pump()
		var id: String = a.host.cloud_saves.slot_id
		var prior := snapshot(a.host)
		a.endpoint.online = false
		a.store.boundary = boundary
		a.host.sim.city.funds -= 123
		var newer := snapshot(a.host)
		var error: Error = a.host.cloud_saves.capture(&"test")
		check_eq(error, OK if boundary == "published" else ERR_CANT_CREATE)
		var reopened := BoundaryStore.new(a.root)
		check_eq(reopened.open_library("synthetic-account"), OK)
		var restored: Dictionary = {}
		for entry in reopened.slots():
			if entry.slot_id == id: restored = entry
		check(not restored.is_empty())
		check(a.host.load_city(restored.path))
		check_eq(snapshot(a.host), prior if boundary == "payload" else newer, boundary + " restart exact state")

func test_large_synthetic_capture_phases_are_local_and_simulation_neutral() -> void:
	var a := device("large")
	pump()
	var host: GameHost = a.host
	var random := RandomNumberGenerator.new()
	random.seed = 681
	for y in City.HEIGHT:
		for x in City.WIDTH:
			host.sim.city.set_heights(x, y, random.randi_range(1, 30), 0)
			if x % 4 == 0 and y % 4 == 0: host.sim.city.signs[Vector2i(x, y)] = "Synthetic block %d, %d" % [x, y]
	var deliveries: Array = []
	for i in 1024: deliveries.append(random.randi_range(0, 100000))
	check(host.mod_progress.commit("synthetic_journey", 1, "1.0", {"deliveries":deliveries}).ok)
	var samples: Array[Dictionary] = []
	for iteration in 3:
		host.sim.city.funds -= 1
		var before := snapshot(host)
		var request_count: int = a.endpoint.requests.size()
		var start := Time.get_ticks_usec()
		host.files.save_content()
		var capture_us := Time.get_ticks_usec() - start
		var path := directory.path_join("timing.sc2d")
		start = Time.get_ticks_usec()
		check_eq(SaveFormat.save(path, host.sim.city, host.sim.snapshot(), SaveFormat.STAGE_PLAY, {}, host.explore_progress_snapshot()), OK)
		var serialization_us := Time.get_ticks_usec() - start
		start = Time.get_ticks_usec()
		check(not a.store.stage(host.cloud_saves.slot_id, path).is_empty())
		var preparation_us := Time.get_ticks_usec() - start
		check_eq(snapshot(host), before)
		# Force genuinely new bytes for the full checkpoint measurement, so the
		# preceding preparation phase cannot warm its content-validation cache.
		host.sim.city.funds -= 1
		before = snapshot(host)
		start = Time.get_ticks_usec()
		check_eq(host.cloud_saves.capture(&"test"), OK)
		var total_us := Time.get_ticks_usec() - start
		check_eq(snapshot(host), before)
		check_eq(a.endpoint.requests.size(), request_count, "no network dispatch or wait inside local capture")
		samples.append({"capture_content_us":capture_us, "serialization_us":serialization_us, "store_preparation_us":preparation_us, "full_checkpoint_us":total_us, "asset_bytes":FileAccess.get_file_as_bytes(path).size()})
	print("CLOUD_CAPTURE_PERF ", JSON.stringify({"map_tiles":City.WIDTH * City.HEIGHT, "signs":host.sim.city.signs.size(), "mod_values":deliveries.size(), "samples":samples}))

func test_held_old_account_save_is_cancelled_or_bound_to_submitted_owner() -> void:
	for service_before_event in [false, true]:
		var a := device("held-" + str(service_before_event))
		pump()
		a.endpoint.hold = "save"
		play(a, 131)
		pump()
		var id: String = a.host.cloud_saves.slot_id
		check(not a.endpoint.last("save").is_empty())
		a.endpoint.owner = "replacement-" + str(service_before_event)
		a.endpoint.hold = ""
		if service_before_event: service.step()
		a.endpoint.account_changed(a.coordinator.status().epoch)
		pump()
		check_eq(service.records(a.endpoint.owner).size(), 0, "queued old city never enters replacement account")
		check_eq(service.records().has(id), service_before_event, "unserved work cancels; already served work stays in submitted account")
		check_eq(a.store.slots().size(), 0)
		check_eq(a.host.cloud_saves.capture(&"test"), ERR_UNAUTHORIZED)

func test_invalid_tourism_preserves_active_city_and_existing_save() -> void:
	var a := device("tourism-a")
	pump()
	play(a, 71)
	pump()
	var id: String = a.host.cloud_saves.slot_id
	var b := device("tourism-b")
	pump()
	load_slot(b, id)
	var before := snapshot(b.host)
	var old_row := row(b, id)
	var old_bytes := FileAccess.get_file_as_bytes(old_row.path)
	var old_journal := FileAccess.get_file_as_bytes(b.store.journal_path())
	var entry: Dictionary = service.records()[id]
	var damaged: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry.assets.continuation))
	damaged.snapshot.systems.tourism.schema = 999
	var path := directory.path_join("bad-tourism.sc2d")
	check_eq(SaveFormat._write_replacement(path, JSON.stringify(damaged).to_utf8_buffer()), OK)
	check(not b.host.load_city(path), "local boundary rejects before replacing active host")
	check_eq(snapshot(b.host), before)
	check(b.store.stage(id, path).is_empty(), "cloud upload staging uses full tourism validation")
	check_eq(FileAccess.get_file_as_bytes(b.store.journal_path()), old_journal)
	# A matching transport digest does not make a malformed payload valid.
	entry.assets.continuation = path
	entry.remote.continuation_sha256 = FileAccess.get_sha256(path)
	entry.remote.change_tag = "tourism-invalid-revision"
	entry.remote.commit_id = CloudSaveTypes.uuid()
	b.coordinator.refresh(&"foreground")
	pump()
	check_eq(b.coordinator.status().error, "invalid")
	check_eq(snapshot(b.host), before, "bad cloud download cannot replace running city")
	check_eq(FileAccess.get_file_as_bytes(old_row.path), old_bytes, "prior committed cloud save survives")
	check_eq(row(b, id).continuation_sha256, old_row.continuation_sha256)
