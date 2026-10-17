# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"
func test_unconfigured_adapter_never_dispatches() -> void:
	var platform := AppleCloudPlatform.new()
	check(not platform.available())
	check_eq(platform.start_request({"id": "test", "epoch": 1, "op": "account", "args": {}}), ERR_UNAVAILABLE)
	check_eq(platform.drain_completions(), [])
	platform.cancel_all()
func test_malformed_completions_fail_closed() -> void:
	check(not AppleCloudPlatform.valid_completion({}))
	check(not AppleCloudPlatform.valid_completion({"id": "x", "epoch": 1, "op": "save", "ok": true, "code": "", "result": {}, "retry_after_ms": "bad"}))

class FakeNative extends RefCounted:
	var sent: Array[Dictionary] = []
	var completions: Array = []
	var cancelled := 0
	func available() -> bool: return true
	func start_request(request: Dictionary) -> Error:
		sent.append(request.duplicate(true))
		return OK
	func drain_completions() -> Array:
		var result := completions.duplicate(true)
		completions.clear()
		return result
	func cancel_all() -> void: cancelled += 1

func _completion(id: String = "request", op: String = "account", result: Dictionary = {"owner": "a".repeat(64)}) -> Dictionary:
	return {"id": id, "epoch": 1, "op": op, "ok": true, "code": "", "result": result, "retry_after_ms": 0}

func test_boundary_filters_unmatched_and_malformed_native_results() -> void:
	var platform := AppleCloudPlatform.new()
	var native := FakeNative.new()
	platform._native = native
	check_eq(platform.start_request({"id": "request", "epoch": 1, "op": "account", "args": {}}), OK)
	native.completions = [null, "bad", {}, _completion("unknown"), _completion("request", "save"), _completion("request", "account", {"owner": "raw-cloudkit-id"})]
	check_eq(platform.drain_completions(), [])
	native.completions = [_completion(), _completion()]
	check_eq(platform.drain_completions().size(), 1)
	check_eq(native.sent.size(), 1)

func test_cancel_drops_prior_native_completion() -> void:
	var platform := AppleCloudPlatform.new()
	var native := FakeNative.new()
	platform._native = native
	platform.start_request({"id": "request", "epoch": 1, "op": "account", "args": {}})
	platform.cancel_all()
	native.completions = [_completion()]
	check_eq(platform.drain_completions(), [])
	check_eq(native.cancelled, 1)

func test_unsolicited_account_change_preserves_event_contract() -> void:
	var platform := AppleCloudPlatform.new()
	var native := FakeNative.new()
	platform._native = native
	native.completions = [_completion("", "account_changed", {}), _completion("wrong", "account_changed", {})]
	var results := platform.drain_completions()
	check_eq(results.size(), 1)
	check_eq(results[0].epoch, 1)

func test_changes_reject_duplicate_ids_and_oversized_archives() -> void:
	var result := {"records": [], "deleted_ids": ["same", "same"], "token": PackedByteArray(), "more": false}
	check(not AppleCloudPlatform.valid_completion(_completion("request", "changes", result)))
	result.deleted_ids = ["one"]
	check(AppleCloudPlatform.valid_completion(_completion("request", "changes", result)))
	result.token.resize(1048577)
	check(not AppleCloudPlatform.valid_completion(_completion("request", "changes", result)))

func test_invalid_requests_issue_zero_native_calls() -> void:
	var platform := AppleCloudPlatform.new()
	var native := FakeNative.new()
	platform._native = native
	for request: Dictionary in [{}, {"id": "request", "epoch": 1, "op": "bad", "args": {}}, {"id": "request", "epoch": 1, "op": "save", "args": {}}, {"id": "request", "epoch": 1, "op": "download", "args": {"remote": "bad", "max_bytes": 67108864}}]:
		check_eq(platform.start_request(request), ERR_INVALID_PARAMETER)
	check_eq(native.sent.size(), 0)

func test_native_boundary_requires_finite_metadata() -> void:
	var remote := {"slot_id": "slot", "commit_id": "commit", "change_tag": "tag", "system_fields": PackedByteArray([1]), "continuation_sha256": "a".repeat(64), "manual_sha256": "", "tombstone": false, "metadata": {"funds": INF}}
	check(not AppleCloudPlatform.valid_completion(_completion("request", "fetch_record", {"remote": remote})))

func _finish_native(native: FakeNative, request: Dictionary, result: Dictionary = {}, code: String = "") -> void:
	native.completions.append({"id": request.id, "epoch": request.epoch, "op": request.op, "ok": code.is_empty(), "code": code, "result": result, "retry_after_ms": 0})

func _last_native(native: FakeNative, op: String) -> Dictionary:
	for i in range(native.sent.size() - 1, -1, -1):
		if native.sent[i].op == op: return native.sent[i]
	return {}

func _remove_private_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for child in directory.get_directories(): _remove_private_tree(path.path_join(child))
	for child in directory.get_files(): DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)

func test_invalid_server_conflict_releases_adapter_and_coordinator_lane() -> void:
	var native_completion := {"ok": false, "code": "invalid", "result": {}, "retry_after_ms": 0}
	# The offline native harness can supply its actual malformed-conflict result.
	# The standalone Godot suite also verifies the terminal transport contract.
	var fixture := OS.get_environment("SCDD_NATIVE_CONFLICT_FIXTURE")
	if not fixture.is_empty():
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(fixture))
		check(decoded is Dictionary)
		if not decoded is Dictionary: return
		native_completion = decoded
	var root := "user://apple-cloud-boundary/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(root)
	var path := root.path_join("city.sc2d")
	check_eq(SaveFormat.save(path, flat_city()), OK)
	var store := CloudSaveStore.new(root.path_join("store"))
	var native := FakeNative.new()
	var platform := AppleCloudPlatform.new()
	platform._native = native
	var coordinator := CloudSaveCoordinator.new(store, platform)
	coordinator.jitter = func() -> float: return 0.0
	coordinator.set_enabled(true)
	coordinator.advance(0)
	_finish_native(native, _last_native(native, "account"), {"owner": "a".repeat(64)})
	coordinator.advance(0)
	_finish_native(native, _last_native(native, "prepare_zone"))
	coordinator.advance(0)
	var slot := store.create_slot()
	check(not store.stage(slot, path).is_empty())
	_finish_native(native, _last_native(native, "changes"), {"records": [], "deleted_ids": [], "token": PackedByteArray(), "more": false})
	coordinator.advance(0)
	var save := _last_native(native, "save")
	check(not save.is_empty())
	if save.is_empty():
		coordinator.shutdown()
		_remove_private_tree(root)
		return
	var replay := {"id": save.id, "epoch": save.epoch, "op": save.op, "ok": native_completion.ok, "code": native_completion.code, "result": native_completion.result, "retry_after_ms": int(native_completion.retry_after_ms)}
	native.completions.append(replay)
	coordinator.advance(1)
	check(not platform._requests.has(save.id), "terminal error retires adapter request")
	check(not coordinator._has("save"), "terminal error releases coordinator lane")
	check_eq(store.pending().size(), 1, "local pending work survives")
	check_eq(store.inflight().size(), 1, "uncertain save pin survives")
	coordinator.advance(2000)
	var fetch := _last_native(native, "fetch_record")
	check(not fetch.is_empty(), "lane recovers through authoritative reconciliation")
	if not fetch.is_empty():
		_finish_native(native, fetch, {"remote": {}})
		coordinator.advance(2000)
		check(_last_native(native, "save").id != save.id, "pending work is dispatched again after reconciliation")
	coordinator.shutdown()
	_remove_private_tree(root)

func test_zone_and_record_codes_cross_the_native_boundary() -> void:
	for pair: Array in [["changes", "zone_missing"], ["save", "zone_deleted"], ["save", "record_missing"], ["download", "record_missing"]]:
		var failure := {"id": "request", "epoch": 1, "op": pair[0], "ok": false, "code": pair[1], "result": {}, "retry_after_ms": 0}
		check(AppleCloudPlatform.valid_completion(failure), "%s %s" % pair)
	check(not AppleCloudPlatform.valid_completion({"id": "request", "epoch": 1, "op": "save", "ok": false, "code": "zone_gone", "result": {}, "retry_after_ms": 0}))
