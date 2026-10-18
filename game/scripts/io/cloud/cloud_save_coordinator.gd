# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
class_name CloudSaveCoordinator
extends RefCounted
## Called on the main thread with monotonic foreground ticks. Native callbacks
## only enqueue completion dictionaries; advance() owns all journal mutations.
signal library_changed
signal status_changed(value: Dictionary)
signal slot_forked(old_id: String, new_id: String)
signal slot_removed(slot_id: String)
## Empty current means identity was revoked; staging must stop immediately.
signal verified_owner_changed(previous: String, current: String, epoch: int)
const MAX_PAGE_RECORDS := 256
const MAX_SYSTEM_FIELDS_BYTES := 1024 * 1024
const REFRESH_INTERVAL_MS := 30000
const RETRY_CAP_MS := 60000
## Account, storage and permission failures need a person or an account change.
## Their exponential wait grows to this cap; an account change resets it, and
## foreground/library/local-save activity may retry once per minute.
const LONG_RETRY_CAP_MS := 900000
const LONG_WAIT_CODES := ["signed_out", "quota", "permission"]
const ACTIVITY_RETRY_MS := 60000
## Optional main-thread session guard, called only before verified publication.
## It may durably stage the active ancestor; normal policy then reconciles it.
## ERR_BUSY parks the page, never retains a native temporary asset path.
var before_remote_update: Callable
var jitter: Callable
var _jitter_random := RandomNumberGenerator.new()
var _store: CloudSaveStore
var _platform: RefCounted
var _enabled := false
var _closed := false
var _owner := ""
var _epoch := 0
var _now := 0
var _zone := false
var _refresh := true
var _active: Dictionary = {}
var _page: Dictionary = {}
var _fetched_remotes: Array[Dictionary] = []
var _library_visible := false
var _selected_download := ""
var _retry_at := 0
var _failures := 0
var _error := ""
var _last_refresh := 0
var _last_status: Dictionary = {}
var _initial_inventory_complete := false
var _capture_errors: Dictionary = {}
var _download_errors: Dictionary = {}
var _server_retry_at := 0
var _failed_at := 0
## Personal files already migrated in this verified epoch: path key -> stamp.
var _migrated: Dictionary = {}
var _migration_signature := ""
## A zone the person deleted in Settings is not recreated automatically: that
## would upload again the data they chose to remove. Turning iCloud saves off
## and on again is the consent; the next verified account clears the pause.
var _zone_consent := false

func _init(store: CloudSaveStore, platform: RefCounted) -> void:
	_store = store
	_platform = platform
	_jitter_random.randomize()
	jitter = _jitter_random.randf

func supported() -> bool:
	return _platform.available()

func enabled() -> bool:
	return _enabled

func set_enabled(enabled: bool) -> void:
	if _closed or enabled == _enabled: return
	if not enabled: _zone_consent = true
	_enabled = enabled
	_invalidate()
	_emit_status()

func refresh(_reason: StringName) -> void:
	if _closed: return
	if _reason in [&"foreground", &"visible"]: _activity_retry()
	if _reason == &"foreground":
		if not _enabled or not _platform.available(): return
		if _refresh or _has("changes"): return
	if _reason == &"hidden":
		_library_visible = false
		return
	if _reason == &"visible":
		_library_visible = true
		if _now - _last_refresh < REFRESH_INTERVAL_MS: return
	_refresh = true

func notify_local_commit() -> void:
	if _closed: return
	if _error == "local_io": _error = "" # A real durable publication, not an unchanged capture.
	_activity_retry()
	library_changed.emit()
	_emit_status()

func report_capture(owner: String, id: String, error: Error) -> void:
	var key := owner + ":" + id
	if error == OK:
		_capture_errors.erase(key)
	elif error not in [ERR_BUSY, ERR_UNAUTHORIZED, ERR_UNAVAILABLE]:
		_capture_errors[key] = owner
	_emit_status()

## Runs every frame through advance(); queue facts are counted without copies.
func status() -> Dictionary:
	var state := "disabled"
	var pending := _store.pending_count() if _enabled and not _owner.is_empty() else 0
	if _enabled:
		if not _platform.available(): state = "unavailable"
		# An account failure explains why no owner is verified (signed out,
		# restricted or temporarily unavailable) instead of a perpetual check.
		elif _owner.is_empty(): state = _error if not _error.is_empty() else "verifying_account"
		elif _owner in _capture_errors.values(): state = "local_io"
		elif not _store._unreconciled_manual.is_empty(): state = "local_only"
		elif not _error.is_empty(): state = _error
		elif not _active.is_empty() or not _page.is_empty(): state = "syncing"
		elif pending > 0 or _store.has_inflight(): state = "pending"
		else: state = "synced"
	return {"state": state, "enabled": _enabled, "owner": _owner, "epoch": _epoch,
		"supported": supported(), "pending": pending,
		"retry_at_ms": _retry_at, "error": _error}

func shutdown() -> void:
	if _closed: return
	_enabled = false
	_invalidate()
	_closed = true
	_emit_status()

func _invalidate() -> void:
	# Only an actually visible library change is announced; a repeated account
	# check with no verified owner and no remote rows changes nothing.
	var visible := not _owner.is_empty() or not _page.is_empty() or not _fetched_remotes.is_empty() or not _download_errors.is_empty()
	_epoch += 1
	_platform.cancel_all()
	_active.clear()
	_page.clear()
	_fetched_remotes.clear()
	_download_errors.clear()
	_selected_download = ""
	_zone = false
	_initial_inventory_complete = false
	_migrated.clear()
	_migration_signature = ""
	_refresh = true
	_retry_at = _now
	_server_retry_at = 0
	_failures = 0
	_error = ""
	_set_owner("")
	if visible: library_changed.emit()

func _set_owner(value: String) -> void:
	if _owner == value: return
	var previous := _owner
	_owner = value
	verified_owner_changed.emit(previous, value, _epoch)

func advance(now_ms: int) -> void:
	if _closed: return
	_now = maxi(_now, now_ms)
	var completions: Array[Dictionary] = _platform.drain_completions()
	# Account invalidation wins even when an old download precedes the event in
	# the same drained batch. No old-account bytes reach the replacement journal.
	for completion in completions:
		if completion.get("op") == "account_changed" and completion.get("epoch") == _epoch:
			_invalidate()
			break
	for completion in completions: _complete(completion)
	if _enabled and _platform.available() and _now >= _retry_at:
		_schedule()
	_emit_status()

func _schedule() -> void:
	if _owner.is_empty():
		if not _has("account"): _send("account", {})
		return
	if not _zone:
		if _store.zone_deleted():
			_error = "zone_deleted"
			return
		if not _has("prepare_zone"): _send("prepare_zone", {})
		return
	if _library_visible and _now - _last_refresh >= REFRESH_INTERVAL_MS: _refresh = true
	# Recovered pins are resolved before any new upload or descendant dispatch.
	if not _has("save") and not _has("fetch_record"):
		var pins: Array[Dictionary] = []
		if _store.has_inflight(): pins = _store.inflight()
		if not pins.is_empty(): _send("fetch_record", {"slot_id": pins[0].slot_id}, {"work": pins[0], "slot_id": pins[0].slot_id})
		else:
			for slot_id in _store.unresolved_remote_slots():
				var waiting := _page_has(slot_id)
				for remote in _fetched_remotes:
					if remote.slot_id == slot_id: waiting = true
				if not waiting:
					_send("fetch_record", {"slot_id": slot_id}, {"work": {}, "slot_id": slot_id})
					break
	if _page.is_empty() and not _fetched_remotes.is_empty() and not _has("changes"):
		_page = {"items": _fetched_remotes.duplicate(true), "token": _store.change_token(), "more": false}
		_fetched_remotes.clear()
	if _page.is_empty() and _refresh and not _has("changes") and not _has("fetch_record"):
		_refresh = false
		_last_refresh = _now
		_send("changes", {"token": _store.change_token(), "limit": MAX_PAGE_RECORDS})
	_process_page()
	if _now < _retry_at: return
	if not _has("save") and not _has("fetch_record") and not _store.has_inflight() and _store.pending_count() > 0:
		for work in _store.pending():
			if work.owner != _owner or _page_has(work.slot_id): continue
			var pinned := _store.begin_upload(work.slot_id, work.generation)
			if pinned.is_empty():
				_fail("local_io", 0)
				return
			var metadata := _save_metadata(pinned)
			if metadata.is_empty():
				_fail("invalid", 0)
				return
			_send("save", {"pending": pinned, "metadata": metadata}, {"work": pinned})
			break

func _has(op: String) -> bool:
	for request in _active.values():
		if request.op == op: return true
	return false

func _send(op: String, args: Dictionary, context: Dictionary = {}) -> void:
	var request_id := CloudSaveTypes.uuid()
	if request_id.is_empty():
		_fail("unavailable", 0)
		return
	var request := {"id": request_id, "epoch": _epoch, "op": op, "args": args.duplicate(true)}
	_active[request.id] = {"op": op, "context": context.duplicate(true), "epoch": _epoch}
	var error: Error = _platform.start_request(request)
	if error != OK:
		_active.erase(request.id)
		if op == "changes": _refresh = true
		# Even a synchronously refused send keeps its pin; a later authoritative
		# fetch is safe and makes transport acceptance semantics unambiguous.
		_fail("unavailable", 0)

func _complete(value: Dictionary) -> void:
	if not _enabled or value.get("epoch") != _epoch: return
	var id: Variant = value.get("id")
	if not id is String or not _active.has(id): return
	var request: Dictionary = _active[id]
	if value.get("op") != request.op: return
	_active.erase(id)
	if not value.get("ok") is bool or not value.get("result") is Dictionary:
		if request.op == "changes": _refresh = true
		_fail("invalid", 0)
		return
	var result: Dictionary = value.result
	if not value.ok:
		_failure(request, value)
		return
	match request.op:
		"account":
			if not CloudSaveTypes.valid_id(result.get("owner")):
				_fail("invalid", 0)
				return
			if _store.open_library(result.owner) != OK or _store.repair_adoptions() != OK:
				_fail("local_io", 0)
				return
			if _zone_consent:
				if _store.set_zone_deleted(false) != OK:
					_fail("local_io", 0)
					return
				_zone_consent = false
			_set_owner(result.owner)
			library_changed.emit()
		"prepare_zone": _zone = true
		"changes":
			if not _valid_page(result):
				_refresh = true
				_fail("invalid", 0)
				return
			var items: Array = result.records.duplicate(true)
			for deleted in result.deleted_ids: items.append({"deleted": true, "slot_id": deleted})
			_page = {"items": items, "token": result.token.duplicate(), "more": result.more, "inventory": true}
			library_changed.emit()
		"save":
			var work: Dictionary = request.context.work
			if result.get("commit_id") != work.commit_id or not result.get("change_tag") is String or not result.get("system_fields") is PackedByteArray or result.system_fields.size() > MAX_SYSTEM_FIELDS_BYTES:
				_fail("invalid", 0)
				return
			if _store.acknowledge(work.slot_id, work.generation, work.commit_id, result.system_fields, result.change_tag) != OK:
				_fail("local_io", 0)
				return
			library_changed.emit()
		"fetch_record":
			if not result.get("remote") is Dictionary:
				_fail("invalid", 0)
				return
			var remote: Dictionary = result.remote
			var work: Dictionary = request.context.work
			var slot_id: String = request.context.slot_id
			if not remote.is_empty() and (not _valid_remote(remote) or remote.slot_id != slot_id):
				_fail("invalid", 0)
				return
			if request.context.get("removal_check", false):
				_accept_removal_check(slot_id, remote)
			elif not work.is_empty():
				if _pin_exists(work) and not _reconcile(slot_id, remote): return
				# This same authoritative pin fetch may also settle a queued
				# removal candidate. Its result is newer than that inventory.
				if _page_removal_candidate(slot_id): _accept_removal_check(slot_id, remote)
			elif remote.is_empty():
				if not _guard_remote_update(slot_id, remote):
					# Re-fetch authoritative absence after the bounded retry.
					_fetched_remotes.append({"deleted": true, "slot_id": slot_id})
					return
				if not _reconcile(slot_id, remote): return
				if not _work(slot_id).is_empty(): return
				if _store.remove_remote(slot_id) != OK:
					_fail("local_io", 0)
					return
				slot_removed.emit(slot_id)
				library_changed.emit()
			elif not _page_has(slot_id): _fetched_remotes.append(remote.duplicate(true))
		"download":
			if _page.is_empty() or _page.items.is_empty(): return
			var remote: Dictionary = request.context.remote
			if not result.get("downloaded") is Dictionary:
				_fail("invalid", 0)
				return
			# Validate native copies before a session guard can preserve/fork work.
			for key in ["continuation", "manual"]:
				var expected: String = remote[key + "_sha256"]
				if expected.is_empty(): continue
				var path := _store._download_path(result.downloaded.get(key, ""))
				# Cheap digest first; only the requested bytes are fully decoded.
				# Identical manual/continuation bytes reuse that one validation.
				if FileAccess.get_sha256(path) != expected or _store.readable_header(path).is_empty():
					_fail("invalid", 0)
					return
			if not _guard_remote_update(remote.slot_id, remote): return
			if not _reconcile(remote.slot_id, remote): return
			if not _work(remote.slot_id).is_empty():
				_pop_page_item()
				return
			if _store.publish_remote(remote, result.downloaded) != OK:
				_fail("local_io", 0)
				return
			_pop_page_item()
			if remote.tombstone: slot_removed.emit(remote.slot_id)
			library_changed.emit()
	_error = ""
	_failures = 0

func _guard_remote_update(slot_id: String, remote: Dictionary) -> bool:
	if not before_remote_update.is_valid(): return true
	var error: Error = before_remote_update.call(slot_id, remote.duplicate(true))
	if error == OK: return true
	_page.erase("removal_verified")
	if error == ERR_BUSY:
		_retry_at = maxi(_retry_at, _now + 60000)
	else:
		_fail("local_io", 0)
	return false

func _failure(request: Dictionary, completion: Dictionary) -> void:
	var code: String = completion.get("code", "invalid") if completion.get("code") is String else "invalid"
	var retry: int = completion.get("retry_after_ms", 0) if completion.get("retry_after_ms") is int else 0
	if code == "signed_out":
		# Revoke the old identity but keep growing the wait: an account change
		# notification, not a polling loop, reports a later sign-in.
		var failures := _failures
		var server_retry := _server_retry_at
		_invalidate()
		_failures = failures
		_server_retry_at = server_retry
		_fail("signed_out", retry)
		return
	if code in ["zone_missing", "zone_deleted"]:
		# The zone and all its records are gone. Rows already listed describe
		# the old zone; pending work and pins stay durable and reconcile
		# against the zone prepared again and an inventory from an empty token.
		_zone = false
		_page.clear()
		_fetched_remotes.clear()
		_initial_inventory_complete = false
		_refresh = true
		var reset := _store.set_zone_deleted(true) if code == "zone_deleted" else _store.commit_change_token(PackedByteArray())
		_fail(code if reset == OK else "local_io", retry)
		return
	if code == "record_missing":
		# The target no longer exists, so the same request cannot succeed. A
		# save keeps its pin, which _schedule resolves with fetch_record; a
		# download turns its page item into a removal the page re-verifies.
		if request.op == "download":
			var slot_id: String = request.context.remote.slot_id
			if not _page.is_empty() and not _page.items.is_empty() and _page.items[0].slot_id == slot_id:
				_page.items[0] = {"deleted": true, "slot_id": slot_id}
				_page.erase("removal_verified")
		_fail(code, retry)
		return
	if request.op == "changes":
		_refresh = true
		if code == "token_expired":
			_initial_inventory_complete = false
			if _store.commit_change_token(PackedByteArray()) == OK: return
			code = "local_io"
	if request.op == "download" and code == "conflict":
		var changed: Variant = completion.result.get("remote")
		var expected: Dictionary = request.context.remote
		if changed is Dictionary and _valid_remote(changed) and changed.slot_id == expected.slot_id and not _page.is_empty() and not _page.items.is_empty() and _page.items[0].slot_id == expected.slot_id:
			_page.items[0] = changed.duplicate(true)
			_page.erase("removal_verified")
			return
		code = "invalid"
	if request.op == "download": _download_errors[request.context.remote.slot_id] = code
	if request.op == "save" and code == "conflict":
		var remote: Variant = completion.result.get("remote")
		var work: Dictionary = request.context.work
		if remote is Dictionary and _valid_remote(remote) and remote.slot_id == work.slot_id:
			if _reconcile(work.slot_id, remote): return
		else: code = "invalid"
	_fail(code, retry)

func _fail(code: String, server_ms: int) -> void:
	_error = code
	var cap := LONG_RETRY_CAP_MS if code in LONG_WAIT_CODES else RETRY_CAP_MS
	_failures = mini(_failures + 1, 11)
	var base := mini(1000 * (1 << (_failures - 1)), cap)
	var fraction := clampf(float(jitter.call()), 0.0, 1.0) if jitter.is_valid() else 0.0
	var delay := maxi(base + int(base * 0.25 * fraction), maxi(server_ms, 0))
	var deadline := _now + mini(delay, 9223372036854775807 - _now)
	if server_ms > 0: _server_retry_at = maxi(_server_retry_at, _now + mini(server_ms, 9223372036854775807 - _now))
	_failed_at = _now
	# Independent lanes can fail in the same batch. Neither a shorter later
	# failure nor a successful callback releases an outstanding provider delay.
	_retry_at = maxi(_retry_at, deadline)

## A person may have freed storage or changed access. Retry a long wait early,
## at most once per minute and never before a server-provided deadline.
func _activity_retry() -> void:
	if not _error in LONG_WAIT_CODES or _retry_at <= _now: return
	_retry_at = mini(_retry_at, maxi(maxi(_now, _server_retry_at), _failed_at + ACTIVITY_RETRY_MS))

func _valid_remote(value: Dictionary) -> bool:
	return CloudSaveTypes.valid_remote(value) and value.system_fields.size() <= MAX_SYSTEM_FIELDS_BYTES and value.metadata.size() <= 64

func _valid_page(value: Dictionary) -> bool:
	if not value.get("records") is Array or not value.get("deleted_ids") is Array or not value.get("token") is PackedByteArray or not value.get("more") is bool: return false
	if value.records.size() + value.deleted_ids.size() > MAX_PAGE_RECORDS or value.token.size() > CloudSaveStore.MAX_CHANGE_TOKEN_BYTES: return false
	var ids: Dictionary = {}
	for remote in value.records:
		if not remote is Dictionary or not _valid_remote(remote) or ids.has(remote.slot_id): return false
		ids[remote.slot_id] = true
	for id in value.deleted_ids:
		if not CloudSaveTypes.valid_id(id) or ids.has(id): return false
		ids[id] = true
	return true

func _pin_exists(work: Dictionary) -> bool:
	return _store.has_pin(work.slot_id, work.generation, work.commit_id)

func _work(slot_id: String) -> Dictionary:
	return _store.work_for(slot_id)

## Returns true once local reconciliation is durable. Remote payload publication
## may still require a download; those records are queued in the current page.
func _reconcile(slot_id: String, remote: Dictionary) -> bool:
	var work := _work(slot_id)
	if work.is_empty(): return true
	var action: String = CloudSavePolicy.decide(work, remote).action
	var error: Error = OK
	match action:
		"acknowledge":
			if not _pin_exists(work):
				work = _store.begin_upload(slot_id, work.generation)
				if work.is_empty():
					_fail("local_io", 0)
					return false
			error = _store.acknowledge_remote(slot_id, work.generation, remote)
		"fork":
			var fork := _store.fork_pending(slot_id, work.generation)
			if fork.is_empty():
				_fail("local_io", 0)
				return false
			slot_forked.emit(slot_id, fork)
			if _pin_exists(work): error = _store.retire_upload(slot_id, work.generation)
		"upload":
			if _pin_exists(work): error = _store.retire_upload(slot_id, work.generation)
		"ignore":
			_fail("invalid", 0)
			return false
	if error != OK:
		_fail("local_io", 0)
		return false
	library_changed.emit()
	# A fetch outside a changes page still needs to preserve the server branch.
	if action == "fork":
		if remote.is_empty() and not _page_has(slot_id):
			if _store.remove_remote(slot_id) != OK:
				_fail("local_io", 0)
				return false
			slot_removed.emit(slot_id)
		elif not remote.is_empty() and not _page_has(slot_id): _fetched_remotes.append(remote.duplicate(true))
	return true

func _page_has(slot_id: String) -> bool:
	for item in _page.get("items", []):
		if item.slot_id == slot_id: return true
	return false

func _slot_busy(slot_id: String) -> bool:
	for request in _active.values():
		if request.op in ["save", "fetch_record"] and request.context.get("slot_id", request.context.get("work", {}).get("slot_id", "")) == slot_id: return true
	return false

func _page_removal_candidate(slot_id: String) -> bool:
	if _page.is_empty() or _page.items.is_empty() or _page.items[0].slot_id != slot_id: return false
	var item: Dictionary = _page.items[0]
	return item.get("deleted", false) or (item.get("tombstone", false) and item.get("manual_sha256", "").is_empty())

func _accept_removal_check(slot_id: String, remote: Dictionary) -> void:
	if _page.is_empty() or _page.items.is_empty() or _page.items[0].slot_id != slot_id: return
	_page.items[0] = {"deleted": true, "slot_id": slot_id} if remote.is_empty() else remote.duplicate(true)
	_page["removal_verified"] = slot_id

func _pop_page_item() -> void:
	_page.items.pop_front()
	_page.erase("removal_verified")

## Selection only prioritizes this page; token publication still waits for every
## item. Cancel clears priority, not unrelated background synchronization.
func select_download(slot_id: String, owner: String, epoch: int) -> bool:
	if not _enabled or owner.is_empty() or owner != _owner or epoch != _epoch or not _page_has(slot_id): return false
	_selected_download = slot_id
	return true

func cancel_selected_download() -> void:
	_selected_download = ""

func _process_page() -> void:
	if _page.is_empty() or _has("download"): return
	if not _selected_download.is_empty():
		for i in _page.items.size():
			if _page.items[i].slot_id == _selected_download:
				var selected: Dictionary = _page.items.pop_at(i)
				_page.items.push_front(selected)
				_page.erase("removal_verified")
				break
		_selected_download = ""
	while not _page.items.is_empty():
		var item: Dictionary = _page.items[0]
		if _slot_busy(item.slot_id): return
		# Deletion inventory has no asset download whose native version check
		# could catch an intervening save. Re-fetch the actual record first.
		# The page head blocks new same-slot sends until reconciliation finishes;
		# the shared fetch/save lane also serializes the revalidation snapshot.
		if _page_removal_candidate(item.slot_id) and _page.get("removal_verified", "") != item.slot_id:
			if _has("save") or _has("fetch_record"): return
			_send("fetch_record", {"slot_id": item.slot_id}, {"work": {}, "slot_id": item.slot_id, "removal_check": true})
			return
		var remote: Dictionary = {} if item.get("deleted", false) else item
		if _page_removal_candidate(item.slot_id) and not _guard_remote_update(item.slot_id, remote): return
		if not _reconcile(item.slot_id, remote): return
		if item.get("deleted", false):
			if _work(item.slot_id).is_empty():
				if _store.remove_remote(item.slot_id) != OK:
					_fail("local_io", 0)
					return
				slot_removed.emit(item.slot_id)
			_pop_page_item()
			library_changed.emit()
			continue
		# Pending matching the actual parent remains queued for a conditional send;
		# it must never be replaced by that older remote snapshot.
		if not _work(item.slot_id).is_empty():
			_pop_page_item()
			continue
		var current := _store.published_head(item.slot_id)
		if CloudSavePolicy.decide(current, remote).action == "ignore":
			_pop_page_item()
			continue
		if remote.tombstone and remote.manual_sha256.is_empty():
			if _store.publish_remote(remote, {}) != OK:
				_fail("local_io", 0)
				return
			_pop_page_item()
			slot_removed.emit(remote.slot_id)
			library_changed.emit()
			continue
		_download_errors.erase(remote.slot_id)
		_send("download", {"remote": remote, "max_bytes": CloudSaveTypes.MAX_ASSET_BYTES}, {"remote": remote})
		return
	if _store.commit_change_token(_page.token) != OK:
		_fail("local_io", 0)
		return
	var initial_finished: bool = _page.get("inventory", false) and not _page.more
	_refresh = _refresh or _page.more
	_page.clear()
	if initial_finished:
		_initial_inventory_complete = true
		if _migrate_changed_personal_saves() != OK:
			_fail("local_io", 0)
			_refresh = true
			return
	if not _fetched_remotes.is_empty() and not _has("changes"):
		_page = {"items": _fetched_remotes.duplicate(true), "token": _store.change_token(), "more": false}
		_fetched_remotes.clear()
		_process_page()
		return
	if _refresh and not _has("changes"):
		_refresh = false
		_last_refresh = _now
		_send("changes", {"token": _store.change_token(), "limit": MAX_PAGE_RECORDS})

## Caller rows are filtered again: browser backups/share/picker paths do not
## authorize migration. Inventory completeness belongs to this verified epoch.
func migrate_personal_saves(headers: Array[Dictionary]) -> Error:
	if _owner.is_empty() or not _initial_inventory_complete: return ERR_BUSY
	for header in headers:
		var path: Variant = header.get("path", "")
		if not path is String or not CloudSaveStore.personal_path(path): continue
		var error := _store.migrate_personal_file(path)
		if error != OK: return error
	return OK

## Every changes completion is inventory. Each verified epoch migrates all
## personal saves once, then only new or changed files, unless a journal fact or
## claim that migration reads has changed. An unchanged file's stamp is trusted
## only when its modification second precedes the pass (same racy-time rule as
## the store's digest memo).
func _migrate_changed_personal_saves() -> Error:
	if _owner.is_empty() or not _initial_inventory_complete: return ERR_BUSY
	var signature := _store.migration_signature()
	if signature != _migration_signature: _migrated.clear()
	var directory := SaveFormat.default_dir()
	var candidates: Array[Dictionary] = []
	var present: Dictionary = {}
	var dir := DirAccess.open(directory)
	if dir != null:
		for name in dir.get_files():
			if name.get_extension().to_lower() != SaveFormat.EXTENSION: continue
			var path := directory.path_join(name)
			var key := CloudSaveStore.path_key(path)
			present[key] = true
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null: continue
			var stamp := "%d:%d" % [file.get_length(), FileAccess.get_modified_time(path)]
			file.close()
			if _migrated.get(key, "") != stamp: candidates.append({"path": path, "key": key, "stamp": stamp, "modified": FileAccess.get_modified_time(path)})
	for key in _migrated.keys():
		if not present.has(key): _migrated.erase(key)
	# Newest first, as the ordinary save list orders the same directory.
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.modified > b.modified or (a.modified == b.modified and a.path < b.path))
	var started := int(Time.get_unix_time_from_system())
	for candidate in candidates:
		var error := _store.migrate_personal_file(candidate.path)
		if error != OK: return error
		if candidate.modified < started: _migrated[candidate.key] = candidate.stamp
	_migration_signature = _store.migration_signature()
	return OK

## Load lists every save whose header reads, including one whose city body is
## damaged: it remains visible for inspection or sharing, and loading reports
## the damage. Cloud rows still require intact immutable payload bytes.
func library_entries(local_saves: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in local_saves:
		if row.get("path") is String and not row.path.is_empty() and FileAccess.file_exists(row.path): result.append(row.duplicate(true))
	var local_count := result.size()
	if not _enabled or _owner.is_empty(): return result
	var associated: Dictionary = {}
	for row in _store.slots():
		if row.owner != _owner: continue
		if row.sync_state == "conflict" and _work(row.slot_id).is_empty(): continue
		# Disk validation precedes exposing a readable path. Corrupt payloads stay
		# absent rather than becoming loadable library rows.
		if not row.path.is_empty() and not _store.payload_intact(row.continuation): continue
		var named: String = row.get("manual_path", "")
		# A successful local Save may outlive a failed optional cloud journal.
		# Only exact retained manual bytes can hide the ordinary named file.
		if not named.is_empty() and _store.file_matches(named, row.manual_sha256): associated[CloudSaveStore.path_key(named)] = true
		result.append(row)
	for i in range(local_count - 1, -1, -1):
		if not result[i].get("path", "").is_empty() and associated.has(CloudSaveStore.path_key(result[i].path)): result.remove_at(i)
	for item in _page.get("items", []) + _fetched_remotes:
		if item.get("deleted", false) or item.tombstone: continue
		var present := -1
		for index in result.size():
			if result[index].get("slot_id", "") == item.slot_id: present = index
		if present >= 0:
			var cached: Dictionary = result[present]
			if not _work(item.slot_id).is_empty() or cached.get("commit_id", "") == item.commit_id: continue
			if _download_errors.has(item.slot_id):
				cached.sync_state = "pending"
				cached.download_failed = true
				continue
		var row: Dictionary = item.metadata.duplicate(true)
		row.merge({"slot_id": item.slot_id, "commit_id": item.commit_id, "cloud_owned": true, "manual_path": "", "path": "",
			"sync_state": "pending_download", "conflict_origin": CloudSaveStore.metadata_conflict_origin(item.metadata.get("conflict_origin", "")),
			"source_device_label": CloudSaveStore.coarse_device_label(item.metadata.get("source_device_label", "")), "pending_download": true}, true)
		if present < 0: result.append(row)
		else: result[present] = row
	return result

func _save_metadata(work: Dictionary) -> Dictionary:
	var metadata: Dictionary = {}
	if not work.tombstone:
		# The latest row can already contain a newer generation. Read the exact
		# immutable pin's validated header, so cloud metadata describes its bytes.
		metadata = _store.payload_metadata(work.continuation)
		if metadata.is_empty(): return {}
	elif not work.manual.is_empty():
		metadata = _store.payload_metadata(work.manual)
		if metadata.is_empty(): return {}
	else:
		metadata["application_save_version"] = 0 # No asset in this tombstone.
	metadata["schema_version"] = 1
	metadata["source_device"] = _store.installation_id()
	if metadata.source_device.is_empty(): return {}
	metadata["source_device_label"] = CloudSaveStore.coarse_device_label(OS.get_name())
	for row in _store.slots():
		if row.slot_id != work.slot_id: continue
		var origin := CloudSaveStore.metadata_conflict_origin(row.get("conflict_origin", ""))
		if not origin.is_empty(): metadata["conflict_origin"] = origin
		break
	return metadata if CloudSaveTypes.valid_metadata(metadata) else {}

func _emit_status() -> void:
	var value := status()
	if value != _last_status:
		_last_status = value.duplicate(true)
		status_changed.emit(value)
