# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
class_name CloudSaveSession
extends RefCounted
## Main-thread session boundary. Captures never mark the player's file saved.
## Account journals belong to the coordinator; an unowned session has its own
## local handle; verified first-account adoption consumes durable ownership proof.
const INTERVAL := 60.0
const CAPTURE_PREFIX := "capture-"
const BASELINE_PREFIX := "discard-baseline-"
var slot_id := ""
var owner := ""
var coordinator: CloudSaveCoordinator
var store: CloudSaveStore
var _local: CloudSaveStore
var _parked: CloudSaveStore
var _discarded := false
var _host: GameHost
var _city: WeakRef
var _manual_path := ""
var _last_content: Dictionary = {}
var _elapsed := 0.0
var _revoked := false
var _removed := false
var _pending_manual: Dictionary = {}
var _capture_notice := false
var _manual_integrity_error := false
var _capture_error_owner := ""
var _capture_error_slot := ""
var _pending_recovery: Dictionary = {}
var _recovery_fallback_error: Error = OK
var _parked_owner := ""
## While sync is off or unsupported the session does no library work. A city
## opened meanwhile is remembered and joins the library when sync is enabled.
var _deferred_city: WeakRef
var _deferred_source := ""
var _deferred_replaced := true
var _missed_manual: Dictionary = {}
## The slot head this session opened (or last explicitly saved). Don't Save
## returns a pre-existing slot to exactly this state.
var _baseline: Dictionary = {}
var _baseline_copy := ""
var _discard_staged := false
var _discard_final := true
var _temporary_files_checked := false
## Don't Save chosen while sync is off: staged only if the leave commits.
var _inert_discard_pending := false

func _init(host: GameHost, service: CloudSaveCoordinator, library: CloudSaveStore) -> void:
	_host = host
	coordinator = service
	store = library
	coordinator.verified_owner_changed.connect(_owner_changed)
	coordinator.slot_forked.connect(_slot_forked)
	coordinator.slot_removed.connect(_slot_removed)
	coordinator.before_remote_update = _before_remote_update

func begin_session(source_path: String = "", requested_slot: String = "", replaced_existing: bool = true) -> void:
	end_session()
	if not _host.in_game or _host.sim.city == null: return
	var local_destination := ""
	if CityFileFlow.is_tracked_application_recovery_path(source_path):
		local_destination = CityFileFlow.recovery_destination(source_path)
	if not _cloud_active():
		# Ordinary local behavior; a recovery keeps its named destination from
		# its note (written while sync was off) or, read-only, from the receipt
		# recorded while sync was on. Nothing is copied, decoded or journaled.
		if local_destination.is_empty() and CityFileFlow.is_tracked_application_recovery_path(source_path):
			var receipt: String = store.application_recovery_source(source_path).get("entry", {}).get("manual_path", "")
			if CityFileFlow.valid_recovery_destination(receipt): local_destination = receipt
		var deferred := source_path
		if CityFileFlow.is_application_recovery_path(source_path):
			# A tracked recovery rejoins through its own receipt when sync starts.
			if not CityFileFlow.is_tracked_application_recovery_path(source_path): deferred = ""
			if not local_destination.is_empty():
				_host.save_path = local_destination
				_host.files.forget_saved()
		_deferred_city = weakref(_host.sim.city)
		_deferred_source = deferred
		_deferred_replaced = true
		return
	owner = coordinator.status().owner
	var recovery := store.application_recovery_source(source_path)
	if not recovery.is_empty(): owner = recovery.owner
	if not source_path.is_empty():
		var claim := store.path_claim(source_path)
		if recovery.is_empty() and not claim.is_empty(): owner = claim.owner
	var library: CloudSaveStore = recovery.library if not recovery.is_empty() and owner != coordinator.status().owner else _library()
	var entry: Dictionary = recovery.get("entry", {})
	if recovery.is_empty():
		entry = _find_source(library, source_path, requested_slot)
		# A slot found only through its reserved or manual file name is this
		# file's identity only when the file still holds that slot's manual
		# save. Another city written under the name starts its own slot, and
		# manual_saved moves the reservation instead of replacing that city.
		if not entry.is_empty() and entry.slot_id != requested_slot and not _same_path(source_path, entry.path) \
				and not library.file_matches(source_path, String(entry.get("manual_sha256", ""))):
			entry = {}
			replaced_existing = false
	else:
		_pending_recovery = {"path": source_path, "receipt_id": recovery.receipt_id}
		if owner == coordinator.status().owner:
			var resumed := library.resume_application_recovery(source_path, recovery.receipt_id)
			if not resumed.is_empty():
				entry = resumed
				_pending_recovery = {}
		_revoked = not _pending_recovery.is_empty()
	slot_id = entry.get("slot_id", "")
	if slot_id.is_empty(): slot_id = library.create_slot()
	_city = weakref(_host.sim.city)
	var opened: Dictionary = {}
	_manual_path = _host.save_path
	if not entry.is_empty() and (not recovery.is_empty() or _same_path(source_path, entry.path)):
		# The selected continuation can be valid while its separate manual asset
		# was replaced after publication. Validate before copying or decoding that
		# asset; keep the valid city playable without trusting a saved baseline.
		if not entry.manual.is_empty() and library.payload_metadata(entry.manual).is_empty():
			_manual_integrity_error = true
			_manual_path = ""
			_host.save_path = ""
			_host.files.forget_saved()
			_last_content = _host.files.save_content()
			_report_capture(ERR_FILE_CORRUPT)
			return
		# Immutable payload paths are never manual save destinations.
		_manual_path = entry.manual_path
		if _manual_path.is_empty() and not _revoked:
			_manual_path = _available_manual_path(_host.sim.city.name, library)
			var error: Error = OK
			if not entry.manual.is_empty():
				error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_manual_path.get_base_dir()))
				if error == OK: error = SaveFormat._write_replacement(_manual_path, FileAccess.get_file_as_bytes(entry.manual.path))
			# Even an absent future file needs a durable, exclusive reservation.
			if error != OK or library.bind_manual_path(slot_id, _manual_path) != OK:
				_manual_path = ""
		_host.save_path = _manual_path
		if entry.manual.is_empty(): _host.files.forget_saved()
		elif entry.manual_sha256 != entry.continuation_sha256:
			_host.files.set_saved_content(_loaded_content(entry.manual.path))
		opened = entry
	elif CloudSaveStore.personal_path(source_path):
		# Loading an ordinary named file establishes its explicit save point.
		manual_saved(source_path, false, replaced_existing)
	elif not local_destination.is_empty():
		# A recovery written while sync was off retains its named destination;
		# a later Save there associates the file through the ordinary flow.
		_manual_path = local_destination
		_host.save_path = local_destination
		_host.files.forget_saved()
	elif not source_path.is_empty():
		# Reserve cloud identity independently of the existing document flow:
		# recovery needs a name; ordinary selected documents keep their path.
		_manual_path = _available_manual_path(_host.sim.city.name, library)
		if library.bind_manual_path(slot_id, _manual_path) != OK: _manual_path = ""
		if _host.save_path.is_empty(): _host.files.forget_saved()
	_last_content = _host.files.save_content()
	if not opened.is_empty():
		_baseline = {"slot": slot_id, "continuation_sha256": opened.get("continuation_sha256", ""),
			"manual_sha256": opened.get("manual_sha256", ""), "content": _last_content}
	if not _pending_recovery.is_empty() and owner == coordinator.status().owner: _report_capture(ERR_CANT_CREATE)

## replaced_existing: the file already existed before this write (the player
## confirmed Replace, or reopened that file). A slot that only reserved the
## name, or whose file was absent, is another city's identity: never adopt it.
func manual_saved(path: String, explicit_save_as: bool = false, replaced_existing: bool = true) -> void:
	if path.is_empty(): return
	if not _cloud_active():
		_note_inactive_save(path, explicit_save_as, replaced_existing)
		# An explicit successful Save resumes a cancelled leave flow.
		_discarded = false
		_discard_staged = false
		_discard_final = true
		_inert_discard_pending = false
		return
	_activate()
	if not _current(): begin_session()
	_discarded = false # Explicit successful Save resumes a cancelled leave flow.
	_discard_staged = false
	_discard_final = true
	var current: String = coordinator.status().owner
	var transfer := explicit_save_as and not current.is_empty() and owner != current
	var parked_manual := _current() and not owner.is_empty() and owner != current and not _removed
	if not transfer and not _allowed() and not parked_manual: return
	var target_library := store if transfer else _library()
	var destination := _find_source(target_library, path, "", true)
	if not destination.is_empty() and destination.slot_id != slot_id and (not replaced_existing or destination.get("manual_sha256", "").is_empty()):
		# Move the other city's reservation to its own free name; this file
		# then starts or names this city's identity instead of replacing it.
		var moved := _available_manual_path(String(destination.get("name", "")), target_library)
		if moved.is_empty() or target_library.bind_manual_path(destination.slot_id, moved) != OK:
			_report_capture(ERR_CANT_CREATE)
			return
		destination = {}
	var source := _find_source(_library(), "", slot_id)
	# A reserved filename is not a manual save. Conversely, an actual local
	# Save remains manual intent while its optional cloud publication retries.
	var has_manual: bool = not source.get("manual", {}).is_empty() or not _pending_manual.is_empty()
	_pending_manual = {"intent_id": CloudSaveTypes.uuid(), "path": path, "sha256": FileAccess.get_sha256(path), "content": _host.files.saved_content().duplicate(true),
		"source": slot_id, "unnamed": not has_manual and not transfer,
		"same_path": _same_path(path, _manual_path) and not transfer,
		"owner": current if transfer else owner, "transfer": transfer,
		"target": destination.get("slot_id", ""), "target_head": {}}
	if not destination.is_empty(): _pending_manual.target_head = _identity_head(destination)
	# Receipt failure never changes successful local Save semantics. The named
	# file remains independently visible if optional journal staging also fails.
	(store if transfer else _library()).record_manual_intent(_pending_manual)
	_report_capture(_retry_manual_saved())

## A successful local Save As changes the host before optional cloud work.
## Until its identity transition is durable, no capture may advance the source.
func _retry_manual_saved() -> Error:
	if _pending_manual.is_empty(): return OK
	var transition := _pending_manual
	if transition.get("transfer", false) and transition.owner != coordinator.status().owner: return ERR_UNAUTHORIZED
	var library := store if transition.get("transfer", false) else _library()
	var target := library.recover_manual_save(transition)
	if target.is_empty(): return ERR_CANT_CREATE
	if transition.get("transfer", false):
		owner = transition.owner
		_revoked = false
		_removed = false
		_discarded = false
	slot_id = target
	_manual_path = transition.path
	# This is the content at the successful local write, not later live edits.
	_last_content = transition.content
	# The saved file's bytes are now both assets; Don't Save returns here.
	_set_baseline({"slot": target, "continuation_sha256": transition.sha256, "manual_sha256": transition.sha256, "content": transition.content})
	_elapsed = 0.0
	_pending_manual = {}
	_manual_integrity_error = false
	coordinator.notify_local_commit()
	return OK

static func _identity_head(entry: Dictionary) -> Dictionary:
	return CloudSaveStore.manual_identity_head(entry)

func _report_capture(error: Error) -> Error:
	if error == OK and not _capture_error_slot.is_empty():
		coordinator.report_capture(_capture_error_owner, _capture_error_slot, OK)
		_capture_error_slot = ""
	coordinator.report_capture(owner, slot_id, error)
	if error == OK:
		_capture_notice = false
	elif error not in [ERR_BUSY, ERR_UNAUTHORIZED, ERR_UNAVAILABLE]:
		_capture_error_owner = owner
		_capture_error_slot = slot_id
		if _capture_notice: return error
		_capture_notice = true
		_host.notices.show("Cloud Checkpoint Failed", "Progress could not be prepared for iCloud. Check free space and save your city before leaving. Any successful named save remains on this device.")
	return error

func capture(reason: StringName) -> Error:
	if not _cloud_active(): return ERR_UNAVAILABLE
	_activate()
	return _report_capture(_capture(reason, false))

## Background notifications may be the last engine callback before suspension.
## Start one normal nonblocking scheduler pass after the safe local capture;
## generic captures and prepublication guards never recursively advance it.
func prepare_application_recovery(path: String) -> Error:
	if not CityFileFlow.is_tracked_application_recovery_path(path): return OK
	# The local named-destination note describes only the bytes it hashed.
	CityFileFlow.clear_recovery_destination()
	_recovery_fallback_error = OK
	if not _cloud_active(): return OK
	_activate()
	# An absent account's authenticated bytes/journal stay parked. Latest local
	# progress uses the untracked fallback until exact owner proof is available.
	var error: Error = ERR_UNAUTHORIZED if not owner.is_empty() and owner != coordinator.status().owner else OK
	if error == OK and _manual_integrity_error: error = ERR_FILE_CORRUPT
	if error == OK and not _pending_recovery.is_empty(): error = _resume_recovery()
	if error == OK: error = store.clear_application_recovery()
	_recovery_fallback_error = error
	if error != OK: _report_capture(error)
	return error

func capture_background(recovery_path: String = "") -> Error:
	if not _cloud_active():
		# Sync is off: keep only the recovery's named destination, so a reopened
		# recovery still saves to the player's file. No library work.
		if CityFileFlow.is_tracked_application_recovery_path(recovery_path) and _host.in_game:
			CityFileFlow.write_recovery_destination(recovery_path, _host.save_path)
		return OK
	_activate()
	var error: Error
	if CityFileFlow.is_tracked_application_recovery_path(recovery_path):
		error = _retry_manual_saved()
		if error == OK and _manual_integrity_error: error = ERR_FILE_CORRUPT
		if error == OK and not _allowed(): error = ERR_UNAUTHORIZED
		if error == OK: _preserve_baseline(_library())
		if error == OK: error = _library().record_application_recovery(slot_id, recovery_path)
		if error == OK:
			_last_content = _host.files.save_content()
			coordinator.notify_local_commit()
		error = _report_capture(error)
	elif CityFileFlow._same_recovery_path(recovery_path, CityFileFlow.application_recovery_fallback_path()):
		error = _report_capture(_recovery_fallback_error if _recovery_fallback_error != OK else ERR_FILE_CANT_WRITE)
	else: error = capture(&"background")
	coordinator.advance(Time.get_ticks_msec())
	return error

func _capture(_reason: StringName, force: bool) -> Error:
	if not _current(): return ERR_UNAVAILABLE
	if not _pending_recovery.is_empty() and owner == coordinator.status().owner:
		var recovered := _resume_recovery()
		if recovered != OK: return recovered
	if owner.is_empty() and not coordinator.status().owner.is_empty(): _owner_changed("", coordinator.status().owner, coordinator.status().epoch)
	if not owner.is_empty() and owner == coordinator.status().owner and _find_source(store, "", slot_id).is_empty():
		if store.repair_adoptions() != OK: return ERR_CANT_CREATE
	var transition_error := _retry_manual_saved()
	if transition_error != OK: return transition_error
	if not _allowed(): return ERR_UNAUTHORIZED
	if _manual_integrity_error: return ERR_FILE_CORRUPT
	if _host.is_casino_open() and _host.casino_overlay.round_in_progress(): return ERR_BUSY
	var content := _host.files.save_content()
	if not force and content == _last_content: return OK
	var library := _library()
	_remove_stale_temporary_files(library._root)
	_preserve_baseline(library)
	# One owned temporary file; store.stage validates and publishes immutable bytes.
	var path := library._root.path_join(CAPTURE_PREFIX + CloudSaveTypes.uuid() + ".sc2d")
	var editing := _host.stage == GameHost.Stage.EDITING
	var error := SaveFormat.save(path, _host.sim.city, {} if editing else _host.sim.snapshot(), SaveFormat.STAGE_EDITING if editing else SaveFormat.STAGE_PLAY, _host.editing_params if editing else {}, _host.explore_progress_snapshot())
	if error == OK and library.stage(slot_id, path).is_empty(): error = ERR_CANT_CREATE
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	if error == OK:
		_last_content = content
		coordinator.notify_local_commit()
	return error

func tick(delta: float) -> void:
	# Drain account revocation even while unfocused; no capture/network waiting.
	coordinator.advance(Time.get_ticks_msec())
	# Don't Save was chosen, then the Load/New/Import step was cancelled: the
	# same city is still open, so its session continues unchanged.
	if _inert_discard_pending and _current() and not _host.files._city_action_blocked():
		_inert_discard_pending = false
		_discarded = false
		_discard_final = true
	if not _cloud_active(): return
	_activate()
	if _discarded and not _discard_final and _current() and not _host.files._city_action_blocked(): _undo_discard()
	if not _current() or not _host._window_in_foreground or _host._application_suspended: return
	_elapsed += maxf(0.0, delta)
	if _elapsed < INTERVAL: return
	_elapsed = 0.0
	capture(&"periodic")

## Publish the explicit choice before changing the live city or allowing exit.
## stage retains the true acknowledged parent and any uncertain upload pins.
func restore_manual() -> Error:
	if not _cloud_active(): return ERR_UNAUTHORIZED
	_activate()
	# Choosing the same city's manual save supersedes a pending Don't Save.
	if _discarded and not _discard_final:
		_discarded = false
		_discard_staged = false
		_discard_final = true
	if not _allowed(): return ERR_UNAUTHORIZED
	var error := _retry_manual_saved()
	if error != OK: return error
	var library := _library()
	var entry := _find_source(library, "", slot_id)
	if entry.get("manual", {}).is_empty(): return ERR_UNAVAILABLE
	var path: String = entry.manual.path
	if library.payload_metadata(entry.manual).is_empty(): return ERR_FILE_CORRUPT
	var id := slot_id
	var saved_owner := owner
	var named := _manual_path
	if library.stage(id, path).is_empty(): return ERR_CANT_CREATE
	# Load the published continuation without a new session identity, then
	# restore this same slot and named manual destination.
	var continuation: String = _find_source(library, "", id).path
	if not _host.session.load_city(continuation, false): return ERR_FILE_CORRUPT
	owner = saved_owner
	slot_id = id
	_city = weakref(_host.sim.city)
	_manual_path = named
	_host.save_path = named
	_host.files.mark_saved()
	_last_content = _host.files.save_content()
	var restored := _find_source(library, "", id)
	_set_baseline({"slot": id, "continuation_sha256": restored.get("continuation_sha256", ""), "manual_sha256": restored.get("manual_sha256", ""), "content": _last_content})
	_manual_integrity_error = false
	coordinator.notify_local_commit()
	return _report_capture(OK)

## Explicit library choice, including from the title screen or another city.
## The caller owns the existing save/discard prompt and captures this epoch
## before the loading screen's draw. Never load a slot from a revoked account.
func restore_selected_manual(id: String, verified_owner: String, epoch: int) -> Error:
	var status := coordinator.status()
	if verified_owner.is_empty() or status.owner != verified_owner or status.epoch != epoch or not status.enabled: return ERR_UNAUTHORIZED
	if id == slot_id and owner == verified_owner and _current(): return restore_manual()
	var entry := _find_source(store, "", id)
	var manual: Dictionary = entry.get("manual", {})
	if entry.get("owner", "") != verified_owner or manual.is_empty(): return ERR_UNAVAILABLE
	var path: String = manual.get("path", "")
	if store.payload_metadata(manual).is_empty(): return ERR_FILE_CORRUPT
	# Only a durable intentional continuation authorizes replacing the city.
	if store.stage(id, path).is_empty(): return ERR_CANT_CREATE
	var continuation: String = _find_source(store, "", id).path
	if not _host.session.load_city(continuation): return ERR_FILE_CORRUPT
	_manual_integrity_error = false
	coordinator.notify_local_commit()
	return _report_capture(OK)

## Don't Save drops only this session's changes. A slot that existed before
## the session returns to the state it was opened (or last saved) in; nothing
## is staged when it is already there. Only a slot this session created that
## was never acknowledged by the server or manually saved becomes a tombstone.
## cancellable: the leave may still be cancelled (Load/New/Import dialogs); if
## the same city is then still open, tick() continues its session.
func discard(cancellable: bool = false) -> Error:
	if not _cloud_active():
		# Nothing new is captured, but work this session already staged must
		# still be dropped. A cancellable leave stages only when it commits.
		if not _current() or _discarded: return OK
		if not cancellable: return _stage_discard(false)
		_discarded = true
		_discard_final = false
		_discard_staged = false
		_inert_discard_pending = true
		return OK
	_activate()
	if not _current() or _discarded: return OK
	return _stage_discard(cancellable)

func _stage_discard(cancellable: bool) -> Error:
	# An old owner's local choice must also be durable while that account is
	# absent; it never schedules work in the currently verified namespace.
	var error := _retry_manual_saved()
	if error != OK: return error
	var library := _library()
	var entry := _find_source(library, "", slot_id)
	if entry.is_empty(): return ERR_DOES_NOT_EXIST
	var manual: Dictionary = entry.get("manual", {})
	if not manual.is_empty() and library.payload_metadata(manual).is_empty(): return ERR_FILE_CORRUPT
	var continuation := ""
	var tombstone := false
	if not _baseline.is_empty() and _baseline.slot == slot_id and _baseline.get("forked", false):
		# A branch forked during this session holds only its changes; the
		# original slot keeps the remote state. Drop the branch, never restore it.
		if String(entry.get("commit_id", "")).is_empty(): tombstone = true
	elif not _baseline.is_empty() and _baseline.slot == slot_id:
		var unchanged: bool = entry.get("continuation_sha256", "") == _baseline.continuation_sha256 and entry.get("manual_sha256", "") == _baseline.manual_sha256
		if unchanged: pass
		elif not manual.is_empty() and _baseline.continuation_sha256 == entry.get("manual_sha256", ""): continuation = manual.path
		elif not _baseline_copy.is_empty() and FileAccess.get_sha256(_baseline_copy) == _baseline.continuation_sha256: continuation = _baseline_copy
		# Otherwise the opened state is not retained exactly; keep the slot.
	elif not manual.is_empty(): continuation = manual.path
	elif String(entry.get("commit_id", "")).is_empty(): tombstone = true
	if not continuation.is_empty() or tombstone:
		if library.stage(slot_id, continuation, "", tombstone).is_empty(): return ERR_CANT_CREATE
		coordinator.notify_local_commit()
	_discarded = true
	_discard_staged = not continuation.is_empty() or tombstone
	_discard_final = not cancellable
	return OK

## The leave was cancelled: republish the live city over the staged discard.
func _undo_discard() -> void:
	_inert_discard_pending = false
	_discarded = false
	_discard_final = true
	if not _discard_staged: return
	_discard_staged = false
	_last_content = {}
	capture(&"undo")

func end_session() -> void:
	if _inert_discard_pending:
		# The leave chosen with Don't Save while sync was off has committed.
		_inert_discard_pending = false
		if _current(): _stage_discard(false)
	# A failure belonged to the city being closed; never carry it to the title.
	if not _capture_error_slot.is_empty():
		coordinator.report_capture(_capture_error_owner, _capture_error_slot, OK)
		_capture_error_slot = ""
		_capture_error_owner = ""
	_set_baseline({})
	_deferred_city = null
	_deferred_source = ""
	_missed_manual = {}
	_discard_staged = false
	_discard_final = true
	_capture_notice = false
	_manual_integrity_error = false
	slot_id = ""
	owner = ""
	_city = null
	_manual_path = ""
	_last_content = {}
	_elapsed = 0.0
	_revoked = false
	_removed = false
	_pending_manual = {}
	_discarded = false
	_pending_recovery = {}
	_recovery_fallback_error = OK

func shutdown() -> void:
	end_session()
	coordinator.before_remote_update = Callable()
	coordinator.verified_owner_changed.disconnect(_owner_changed)
	coordinator.slot_forked.disconnect(_slot_forked)
	coordinator.slot_removed.disconnect(_slot_removed)
	coordinator.shutdown()

func _current() -> bool:
	return not slot_id.is_empty() and _city != null and _city.get_ref() == _host.sim.city and _host.in_game

func _allowed(ignore_discard: bool = false) -> bool:
	return _cloud_active() and _current() and (ignore_discard or not _discarded) and not _revoked and not _removed and (owner.is_empty() or coordinator.status().owner == owner)

## Sync is on and the platform can perform it. Otherwise the session is inert.
func _cloud_active() -> bool:
	return coordinator.enabled() and coordinator.supported()

## A city opened, or a Save made, while sync was off joins the library now.
func _activate() -> void:
	if _deferred_city != null:
		var city: Object = _deferred_city.get_ref()
		var source := _deferred_source
		_deferred_city = null
		_deferred_source = ""
		if city == null or city != _host.sim.city or not _host.in_game or _current(): return
		if CloudSaveStore.personal_path(source) and not FileAccess.file_exists(source): source = ""
		var recovered := CityFileFlow.is_tracked_application_recovery_path(source)
		if recovered and not FileAccess.file_exists(source): source = ""
		begin_session(source, "", _deferred_replaced)
		if not _current(): return
		# A receipt's opened bytes can be older than the live city; leaving must
		# still ask unless the slot holds what is open.
		if recovered and not _baseline.is_empty(): _baseline.content = {}
		_join_live_city()
	elif not _missed_manual.is_empty() and _current():
		var missed := _missed_manual
		_missed_manual = {}
		if FileAccess.file_exists(missed.path): manual_saved(missed.path, missed.explicit, missed.replaced)
		if _current(): _join_live_city()

## Edits made after the last local save while sync was off are captured at
## once, so the slot never stands only for older bytes.
func _join_live_city() -> void:
	_last_content = _host.files.saved_content()
	capture(&"join")

func _note_inactive_save(path: String, explicit_save_as: bool, replaced_existing: bool) -> void:
	if _current():
		# The first write of a path decides whether the file existed before.
		var same: bool = _same_path(path, String(_missed_manual.get("path", "")))
		_missed_manual = {"path": path, "explicit": explicit_save_as or bool(_missed_manual.get("explicit", false)),
			"replaced": bool(_missed_manual.get("replaced", true)) if same else replaced_existing}
	elif _host.in_game and _host.sim.city != null:
		var same: bool = _deferred_city != null and _deferred_city.get_ref() == _host.sim.city and _same_path(path, _deferred_source)
		if not same: _deferred_replaced = replaced_existing
		_deferred_city = weakref(_host.sim.city)
		_deferred_source = path

func _local_library() -> CloudSaveStore:
	if _local == null:
		_local = CloudSaveStore.new(store._root)
		_local.open_library("")
	return _local

func _library() -> CloudSaveStore:
	if owner.is_empty(): return _local_library()
	# The coordinator's store still holds this account until another verifies.
	if owner == coordinator.status().owner or (coordinator.status().owner.is_empty() and store._owner == owner): return store
	# One handle per parked account; reopening re-verifies every payload.
	if _parked == null or _parked_owner != owner:
		_parked = CloudSaveStore.new(store._root)
		_parked.open_library(owner)
		_parked_owner = owner
	return _parked

func _set_baseline(value: Dictionary) -> void:
	if not _baseline_copy.is_empty():
		DirAccess.remove_absolute(_baseline_copy)
		_baseline_copy = ""
	_baseline = value

## Before the first capture replaces an opened continuation that is not also
## the manual asset, keep its exact bytes so Don't Save can return to them.
func _preserve_baseline(library: CloudSaveStore) -> void:
	if _baseline.is_empty() or _baseline.slot != slot_id or not _baseline_copy.is_empty(): return
	if _baseline.continuation_sha256.is_empty() or _baseline.continuation_sha256 == _baseline.manual_sha256: return
	var entry := _find_source(library, "", slot_id)
	if entry.get("continuation_sha256", "") != _baseline.continuation_sha256 or String(entry.get("path", "")).is_empty(): return
	var copy := library._root.path_join(BASELINE_PREFIX + CloudSaveTypes.uuid() + ".sc2d")
	if DirAccess.copy_absolute(entry.path, copy) == OK: _baseline_copy = copy
	elif FileAccess.file_exists(copy): DirAccess.remove_absolute(copy)

## Captures/baselines interrupted by an earlier exit leave owned temporaries.
func _remove_stale_temporary_files(root: String) -> void:
	if _temporary_files_checked: return
	_temporary_files_checked = true
	var dir := DirAccess.open(root)
	if dir == null: return
	for name in dir.get_files():
		if not (name.begins_with(CAPTURE_PREFIX) or name.begins_with(BASELINE_PREFIX)) or not name.ends_with(".sc2d"): continue
		var path := root.path_join(name)
		if path != _baseline_copy: DirAccess.remove_absolute(path)

## Leaving would lose nothing: the open city is exactly the slot state this
## session opened or last saved, so no save-before-leaving question is needed.
func unchanged_since_opened() -> bool:
	return _allowed() and not _baseline.is_empty() and _baseline.slot == slot_id and _host.files.save_content() == _baseline.content

func _owner_changed(_previous: String, current: String, _epoch: int) -> void:
	_parked = null
	_parked_owner = ""
	if not owner.is_empty():
		_revoked = current != owner
		if not _revoked and not _pending_recovery.is_empty():
			var error := _resume_recovery()
			_revoked = error != OK
			_report_capture(error)
		return
	if current.is_empty() or not _current() or _discarded: return
	# The global consumed-slot proof is durable before destination publication.
	# Same-owner retries repair an interrupted transfer; another owner cannot.
	if _retry_manual_saved() != OK: return
	if _local_library().adopt_local(slot_id, current) != OK:
		var proof: Dictionary = _local_library()._claims().get("claims", {}).get("local:" + slot_id, {})
		if not proof.is_empty():
			owner = proof.owner
			_revoked = owner != current
		return
	if store.open_library(current) != OK: return
	owner = current
	_revoked = false

func _resume_recovery() -> Error:
	var entry := _library().resume_application_recovery(_pending_recovery.path, _pending_recovery.receipt_id)
	if entry.is_empty(): return ERR_CANT_CREATE
	slot_id = entry.slot_id
	_manual_path = entry.manual_path
	_host.save_path = _manual_path
	_pending_recovery = {}
	_revoked = false
	return OK

func _slot_forked(previous: String, replacement: String) -> void:
	if previous == slot_id and _allowed(true):
		slot_id = replacement
		if _baseline.get("slot", "") == previous:
			_baseline.slot = replacement
			_baseline.forked = true
		if not _pending_manual.is_empty() and _pending_manual.source == previous:
			_pending_manual.source = replacement

## The UI keeps its in-memory city when another device advances the slot.
## Preserve that city's actual ancestor before remote publication can prune it.
func _before_remote_update(id: String, remote: Dictionary) -> Error:
	# While Don't Save may still be cancelled, the open city's slot waits.
	if id == slot_id and _discarded and not _discard_final and _allowed(true): return ERR_BUSY
	if id != slot_id or not _allowed(): return OK
	var transition_error := _retry_manual_saved()
	if transition_error != OK: return transition_error
	if id != slot_id: return OK
	var library := _library()
	# Existing pending/pinned work already has immutable conditional ancestry.
	for work in library.pending() + library.inflight():
		if work.slot_id == id: return OK
	var entry := _find_source(library, "", id)
	if entry.is_empty(): return OK
	if not remote.is_empty() and entry.commit_id == remote.commit_id and entry.continuation_sha256 == remote.continuation_sha256 and entry.manual_sha256 == remote.manual_sha256 and not remote.tombstone:
		return OK
	if _host.is_casino_open() and _host.casino_overlay.round_in_progress():
		# Retain the last complete pre-round payload. Never serialize a stake.
		if entry.path.is_empty(): return ERR_BUSY
		return OK if not library.stage(id, entry.path).is_empty() else ERR_CANT_CREATE
	return _capture(&"remote_update", true)

func _slot_removed(removed: String) -> void:
	if removed == slot_id and not owner.is_empty(): _removed = true

func _find_source(library: CloudSaveStore, path: String, id: String, named_only: bool = false) -> Dictionary:
	for entry in library.slots():
		if not id.is_empty() and entry.slot_id == id: return entry
		if path.is_empty(): continue
		if _same_path(path, entry.manual_path) or (not named_only and _same_path(path, entry.path)): return entry
	return {}

static func _same_path(a: String, b: String) -> bool:
	return not a.is_empty() and not b.is_empty() and CloudSaveStore.path_key(a) == CloudSaveStore.path_key(b)

func _available_manual_path(city_name: String, library: CloudSaveStore) -> String:
	if library._claims().is_empty(): return ""
	var base := SaveDialog.clean_name(city_name)
	if base.is_empty(): base = "City"
	var index := 1
	while true:
		var path := CityFileFlow.save_path_for(base if index == 1 else "%s (%d)" % [base, index])
		if not FileAccess.file_exists(path) and library.path_claim(path).is_empty() and _find_source(library, path, "", true).is_empty(): return path
		index += 1
	return ""

static func _loaded_content(path: String) -> Dictionary:
	var loaded := SaveFormat.load(path)
	if not loaded.get("ok", false): return {}
	var runtime: Dictionary = loaded.snapshot.duplicate(true)
	runtime.erase("speed")
	runtime.erase("accumulator")
	return {"city": SaveFormat.encode_city(loaded.city), "runtime": runtime,
		"stage": GameHost.Stage.EDITING if loaded.stage == SaveFormat.STAGE_EDITING else GameHost.Stage.PLAY,
		"generator": loaded.generator, "explore_mods": loaded.get("explore_mods", {})}.duplicate(true)
