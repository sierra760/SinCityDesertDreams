# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
class_name CloudSaveStore
extends RefCounted
## Local publication is independent of cloud acknowledgement. Payload files are
## immutable; journal replacement is the only operation that makes them visible.

const JOURNAL_VERSION := 1
const JOURNAL_LIMIT := 16 * 1024 * 1024
const MAX_CHANGE_TOKEN_BYTES := 1024 * 1024
const VALIDATED_CONTENT_LIMIT := 32
const INTACT_FILE_LIMIT := 4096
const PAYLOAD_HEADER_LIMIT := 256
var _root: String
var _directory := ""
var _owner := ""
var _state: Dictionary = {}
var _installation_id := ""
## Positive full-content validation only: no cached path, city or account data.
## Every use still bounds, reads and hashes current bytes before reuse.
var _validated_versions: Dictionary = {}
var _unreconciled_manual: Dictionary = {}
## Process-wide integrity memo for files whose expected digest is already bound
## by a journal or a retained manual hash: key -> {sha256, bytes, modified,
## checked}. A hit needs the same size and modification second, and that second
## must precede the second in which hashing began. A later write therefore always
## changes the observed time, and a same-second replacement is always rehashed.
static var _intact_files: Dictionary = {}
## Display metadata of immutable private payloads, keyed by path and digest.
## Populated only after a full validation of exactly those bytes.
static var _payload_headers: Dictionary = {}
static var _case_insensitive_files := -1
## Headers of payloads copied by this instance, reused by its slot publication.
var _copied_headers: Dictionary = {}

func _init(root: String) -> void:
	_root = ProjectSettings.globalize_path(root).simplify_path()

## Random app-installation identifier; shared by account namespaces, unrelated to
## hardware, CloudKit account IDs, device names, or portable city contents.
func installation_id() -> String:
	if not _installation_id.is_empty(): return _installation_id
	var path := _root.path_join("installation-id")
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null: return ""
		if file.get_length() != 36:
			file.close()
			return ""
		var value := file.get_buffer(36).get_string_from_ascii()
		file.close()
		if not _valid_installation_id(value): return ""
		_installation_id = value
		return value
	if DirAccess.make_dir_recursive_absolute(_root) != OK: return ""
	var generated := CloudSaveTypes.uuid()
	if not _valid_installation_id(generated): return ""
	if SaveFormat._write_replacement(path, generated.to_ascii_buffer()) != OK: return ""
	# The verified atomic writer publishes identity before it can be sent.
	_installation_id = generated
	return generated

func _valid_installation_id(value: String) -> bool:
	if value.length() != 36: return false
	for i in range(36):
		if i in [8, 13, 18, 23]:
			if value[i] != "-": return false
		elif not value[i] in "0123456789abcdef": return false
	return true

## Installation-wide consumed adoption proof. A claim is published BEFORE its
## account journal. A crash may leave a reservation, which only that owner may
## finish; it can never expose the source as unowned to another account.
func _claims() -> Dictionary:
	var path := _root.path_join("ownership.bin")
	if not FileAccess.file_exists(path): return {"version": 1, "claims": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > JOURNAL_LIMIT: return {}
	var bytes := file.get_buffer(file.get_length())
	if bytes.size() < 64: return {}
	var body := bytes.slice(64)
	if bytes.slice(0, 64).get_string_from_ascii() != _digest(body): return {}
	var value: Variant = bytes_to_var(body)
	if not value is Dictionary or value.get("version") != 1 or not value.get("claims") is Dictionary: return {}
	for key in value.claims:
		var claim: Variant = value.claims[key]
		if not key is String or not claim is Dictionary or not CloudSaveTypes.valid_id(claim.get("owner")) or not CloudSaveTypes.valid_id(claim.get("slot_id")): return {}
	return value

func _write_claims(value: Dictionary) -> Error:
	var body := var_to_bytes(value)
	if body.size() > JOURNAL_LIMIT - 64: return ERR_OUT_OF_MEMORY
	var bytes := _digest(body).to_ascii_buffer()
	bytes.append_array(body)
	return SaveFormat._write_replacement(_root.path_join("ownership.bin"), bytes)

static func personal_path(path: String) -> bool:
	var absolute := path_key(path)
	return absolute.get_base_dir() == path_key(SaveFormat.default_dir()) and absolute.get_extension().to_lower() == SaveFormat.EXTENSION

## Comparable identity of a local file name. Default macOS APFS ignores case, so
## "Desert" and "desert" name one file there; case-sensitive volumes keep both.
## Stored paths and claim keys keep their exact spelling; only comparisons fold.
static func path_key(path: String) -> String:
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	return absolute.to_lower() if _case_insensitive() else absolute

static func _case_insensitive() -> bool:
	if _case_insensitive_files >= 0: return _case_insensitive_files == 1
	var directory := OS.get_user_data_dir()
	var name := ".case-probe-" + CloudSaveTypes.uuid()
	var probe := directory.path_join(name)
	var file := FileAccess.open(probe, FileAccess.WRITE)
	# Without a probe, folding is the conservative choice: aliases are refused.
	if file == null:
		_case_insensitive_files = 1
		return true
	file.close()
	_case_insensitive_files = 1 if FileAccess.file_exists(directory.path_join(name.to_upper())) else 0
	DirAccess.remove_absolute(probe)
	return _case_insensitive_files == 1

static func _inside_root(path: String, root: String) -> bool:
	return path_key(path).begins_with(path_key(root) + "/")

## Existing claim key naming the same local file, or a new exact-spelling key.
static func _claim_key(claims: Dictionary, path: String) -> String:
	var exact := "path:" + ProjectSettings.globalize_path(path).simplify_path()
	if claims.has(exact): return exact
	var wanted := path_key(path)
	for key: Variant in claims:
		if key is String and key.begins_with("path:") and path_key(key.trim_prefix("path:")) == wanted: return key
	return exact

func path_claim(path: String) -> Dictionary:
	var claims := _claims()
	if claims.is_empty(): return {"owner": "invalid-ownership", "slot_id": "invalid-ownership"}
	return claims.claims.get(_claim_key(claims.claims, path), {}).duplicate(true)

func _claim(keys: Array[String], owner: String, id: String, explicit: bool = false) -> Error:
	if not CloudSaveTypes.valid_id(owner) or not CloudSaveTypes.valid_id(id): return ERR_INVALID_PARAMETER
	var claims := _claims()
	if claims.is_empty(): return ERR_FILE_CORRUPT
	var changed := false
	for requested in keys:
		# A different spelling of an already claimed file is that same claim.
		var key := _claim_key(claims.claims, requested.trim_prefix("path:")) if requested.begins_with("path:") else requested
		var prior: Dictionary = claims.claims.get(key, {})
		if not prior.is_empty() and prior.owner != owner and not explicit: return ERR_UNAUTHORIZED
		var desired := {"owner": owner, "slot_id": id}
		if prior != desired:
			claims.claims[key] = desired
			changed = true
	return _write_claims(claims) if changed else OK

func claim_manual_path(path: String, id: String, explicit: bool = false) -> Error:
	if _owner.is_empty():
		return OK if path_claim(path).is_empty() else ERR_UNAUTHORIZED
	return _claim(["path:" + ProjectSettings.globalize_path(path).simplify_path()], _owner, id, explicit)

static func manual_identity_head(entry: Dictionary) -> Dictionary:
	return {"slot_id": entry.get("slot_id", ""), "generation": entry.get("generation", -1),
		"commit_id": entry.get("commit_id", ""), "baseline_tag": entry.get("baseline_tag", ""),
		"continuation_sha256": entry.get("continuation_sha256", ""), "manual_sha256": entry.get("manual_sha256", ""),
		"manual_path": entry.get("manual_path", "")}

static func _same_manual_path(a: String, b: String) -> bool:
	return not a.is_empty() and not b.is_empty() and path_key(a) == path_key(b)

## A successful named file is independent of cloud-journal publication. This
## small digest-bound receipt survives a failed journal and belongs to one owner.
## Missing/ambiguous receipts never authorize adopting a named-file mismatch.
func _intent_path(path: String) -> String:
	return _directory.path_join("manual-intents").path_join(ProjectSettings.globalize_path(path).simplify_path().sha256_text() + ".bin")

func _valid_manual_intent(value: Variant) -> bool:
	if not value is Dictionary or value.get("owner") != _owner: return false
	if not CloudSaveTypes.valid_id(value.get("intent_id")) or not CloudSaveTypes.valid_hash(value.get("sha256")): return false
	if not value.get("path") is String or value.path.to_utf8_buffer().size() > 4096: return false
	var path := ProjectSettings.globalize_path(value.path).simplify_path()
	if _inside_root(path, _root) or not path.ends_with(".sc2d"): return false
	if not CloudSaveTypes.valid_id(value.get("source")) or not CloudSaveTypes.valid_id(value.get("target"), true): return false
	for key in ["unnamed", "same_path", "transfer"]:
		if not value.get(key) is bool: return false
	return value.get("target_head") is Dictionary

func record_manual_intent(transition: Dictionary) -> Error:
	var value := transition.duplicate(true)
	value.erase("content")
	if not _valid_manual_intent(value): return ERR_INVALID_PARAMETER
	var body := var_to_bytes(value)
	if body.size() > 16384: return ERR_OUT_OF_MEMORY
	var bytes := _digest(body).to_ascii_buffer()
	bytes.append_array(body)
	var path := _intent_path(value.path)
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return SaveFormat._write_replacement(path, bytes) if error == OK else error

func manual_intent(path: String) -> Dictionary:
	var file := FileAccess.open(_intent_path(path), FileAccess.READ)
	if file == null: return {}
	var size := file.get_length()
	if size < 65 or size > 16448:
		file.close()
		return {}
	var bytes := file.get_buffer(size)
	file.close()
	if bytes.size() != size or _digest(bytes.slice(64)) != bytes.slice(0, 64).get_string_from_ascii(): return {}
	var value: Variant = bytes_to_var(bytes.slice(64))
	if not _valid_manual_intent(value) or not _same_manual_path(value.path, path): return {}
	return value

func clear_manual_intent(transition: Dictionary) -> void:
	if manual_intent(transition.path).get("intent_id", "") == transition.intent_id:
		DirAccess.remove_absolute(_intent_path(transition.path))

## This installation receipt only routes to a journal-owned proof. It never
## authenticates city identity by itself, and portable .sc2d files are unchanged.
func clear_application_recovery() -> Error:
	var path := _root.path_join("application-recovery.bin")
	if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path): return OK
	var error := DirAccess.remove_absolute(path)
	if error == OK: return OK
	return _write_recovery_pointer({})

func _write_recovery_pointer(value: Dictionary) -> Error:
	var body := var_to_bytes(value)
	var bytes := _digest(body).to_ascii_buffer()
	bytes.append_array(body)
	return SaveFormat._write_replacement(_root.path_join("application-recovery.bin"), bytes)

func _recovery_pointer(path: String) -> Dictionary:
	if not CityFileFlow.is_tracked_application_recovery_path(path): return {}
	var file := FileAccess.open(_root.path_join("application-recovery.bin"), FileAccess.READ)
	if file == null: return {}
	var size := file.get_length()
	if size < 65 or size > 16384: return {}
	var bytes := file.get_buffer(size)
	file.close()
	if bytes.size() != size or _digest(bytes.slice(64)) != bytes.slice(0, 64).get_string_from_ascii(): return {}
	var value: Variant = bytes_to_var(bytes.slice(64))
	if not value is Dictionary or not CloudSaveTypes.valid_id(value.get("receipt_id")) or not CloudSaveTypes.valid_id(value.get("owner"), true) or not CloudSaveTypes.valid_id(value.get("slot_id")): return {}
	if value.get("path") != ProjectSettings.globalize_path(path).simplify_path() or not CloudSaveTypes.valid_hash(value.get("sha256")): return {}
	return value if FileAccess.get_sha256(path) == value.sha256 else {}

func _valid_recovery(value: Variant, directory: String, owner: String, verified: Dictionary = {}) -> bool:
	if not value is Dictionary or not CloudSaveTypes.valid_id(value.get("receipt_id")) or value.get("owner") != owner: return false
	if value.get("path") != ProjectSettings.globalize_path(CityFileFlow.application_recovery_path()).simplify_path(): return false
	if not CloudSaveTypes.valid_hash(value.get("sha256")) or not value.get("manual_path") is String or value.manual_path.to_utf8_buffer().size() > 4096: return false
	if not value.get("work") is Dictionary or not CloudSaveTypes.valid_id(value.work.get("slot_id")): return false
	if not CloudSaveTypes.valid_id(value.get("source_slot", value.work.slot_id)): return false
	if not _valid_stored_pending(value.work, value.work.slot_id, owner, directory, verified) or value.work.tombstone or value.work.continuation.sha256 != value.sha256: return false
	return CloudSaveTypes.valid_id(value.get("resumed_slot", ""), true) and CloudSaveTypes.valid_id(value.get("resumed_commit", ""), true)

func _matching_recovery(pointer: Dictionary) -> Dictionary:
	var receipt: Dictionary = _state.get("application_recovery", {})
	if receipt.is_empty() or receipt.receipt_id != pointer.receipt_id or receipt.path != pointer.path or receipt.sha256 != pointer.sha256 or receipt.get("source_slot", receipt.work.slot_id) != pointer.slot_id: return {}
	return receipt.duplicate(true)

## Resolve through a separate read-only namespace; never retarget the active
## coordinator store when a recovery belongs to an absent account.
func application_recovery_source(path: String) -> Dictionary:
	var pointer := _recovery_pointer(path)
	if pointer.is_empty(): return {}
	var owner: String = pointer.owner
	if owner.is_empty():
		var claims := _claims()
		if claims.is_empty(): return {}
		var local := _read_recovery_library("")
		if local._state.is_empty(): return {}
		var local_receipt := local._matching_recovery(pointer)
		if local_receipt.is_empty(): return {}
		# Recovery may already have durably forked before the first verified
		# account. Its actual captured branch is the consumed adoption proof.
		owner = claims.claims.get("local:" + local_receipt.work.slot_id, {}).get("owner", "")
		if owner.is_empty(): owner = claims.claims.get("local:" + pointer.slot_id, {}).get("owner", "")
	var library := _read_recovery_library(owner)
	if library._state.is_empty(): return {}
	var receipt := library._matching_recovery(pointer)
	if receipt.is_empty(): return {}
	var selected: String = receipt.get("resumed_slot", "")
	var manual_path := library._recovery_manual_path(receipt)
	if library._recovery_head_matches(selected, receipt.get("resumed_commit", ""), receipt.work):
		manual_path = library._current_recovery_manual_path(selected)
	else: selected = receipt.work.slot_id
	var entry := library._recovery_entry(selected, receipt.work, manual_path)
	return {"owner": owner, "receipt_id": receipt.receipt_id, "entry": entry, "library": library}

func _read_recovery_library(owner: String) -> CloudSaveStore:
	var library := CloudSaveStore.new(_root)
	library._owner = owner
	library._directory = library._account_directory(owner)
	library._state = library._read_journal(library.journal_path(), library._directory, owner)
	return library

func record_application_recovery(slot_id: String, path: String) -> Error:
	if not CityFileFlow.is_tracked_application_recovery_path(path): return ERR_INVALID_PARAMETER
	var error := clear_application_recovery()
	if error != OK: return error
	var work := stage(slot_id, path)
	if work.is_empty(): return ERR_CANT_CREATE
	var receipt := {"receipt_id": CloudSaveTypes.uuid(), "owner": _owner,
		"source_slot": slot_id,
		"path": ProjectSettings.globalize_path(path).simplify_path(), "sha256": work.continuation.sha256,
		"work": work.duplicate(true), "manual_path": _state.slots[slot_id].manual_path,
		"resumed_slot": "", "resumed_commit": ""}
	var next := _state.duplicate(true)
	next.application_recovery = receipt
	error = _commit(next)
	if error != OK: return error
	return _write_recovery_pointer({"receipt_id": receipt.receipt_id, "owner": _owner,
		"slot_id": slot_id, "path": receipt.path, "sha256": receipt.sha256})

func _recovery_manual_path(receipt: Dictionary) -> String:
	var path: String = receipt.manual_path
	if path.is_empty(): return ""
	var claim := path_claim(path)
	var allowed: Array = [receipt.get("source_slot", receipt.work.slot_id)]
	var resumed: String = receipt.get("resumed_slot", "")
	if _recovery_head_matches(resumed, receipt.get("resumed_commit", ""), receipt.work): allowed.append(resumed)
	if not claim.is_empty() and (claim.owner != _owner or not claim.slot_id in allowed): return ""
	for id in _state.slots:
		if not id in allowed and _same_manual_path(_state.slots[id].manual_path, path): return ""
	return path

func _current_recovery_manual_path(id: String) -> String:
	var path: String = _state.slots[id].manual_path
	if path.is_empty(): return ""
	var claim := path_claim(path)
	if not claim.is_empty() and claim.owner != _owner: return ""
	var receipt: Dictionary = _state.get("application_recovery", {})
	if not claim.is_empty() and not claim.slot_id in [id, receipt.get("source_slot", "")]: return ""
	for other in _state.slots:
		if other != id and _same_manual_path(_state.slots[other].manual_path, path): return ""
	return path

func _recovery_entry(id: String, work: Dictionary, manual_path: String) -> Dictionary:
	return {"slot_id": id, "owner": _owner, "path": work.continuation.path,
		"manual": work.manual.duplicate(true), "manual_path": manual_path,
		"continuation_sha256": work.continuation.sha256, "manual_sha256": work.manual.get("sha256", "")}

func _recovery_head_matches(id: String, commit: String, work: Dictionary) -> bool:
	if not _has_slot(id): return false
	var slot: Dictionary = _state.slots[id]
	if slot.tombstone or slot.continuation.get("sha256", "") != work.continuation.sha256 or slot.manual.get("sha256", "") != work.manual.get("sha256", ""): return false
	if not slot.pending.is_empty(): return slot.pending.commit_id == commit
	return slot.commit_id == commit and slot.uploads.is_empty()

## A pending captured commit or its proven acknowledgement can continue the
## same city. Anything newer keeps its bytes/pins and forks the exact receipt.
func resume_application_recovery(path: String, receipt_id: String) -> Dictionary:
	var pointer := _recovery_pointer(path)
	if pointer.is_empty() or pointer.receipt_id != receipt_id: return {}
	var receipt := _matching_recovery(pointer)
	if receipt.is_empty(): return {}
	var work: Dictionary = receipt.work
	var id: String = receipt.get("resumed_slot", "")
	var commit: String = receipt.get("resumed_commit", "")
	if id.is_empty():
		id = work.slot_id
		commit = work.commit_id
	if not _recovery_head_matches(id, commit, work):
		id = fork_pending(work.slot_id, work.generation, true)
		if id.is_empty(): return {}
	else:
		var next := _state.duplicate(true)
		next.application_recovery.resumed_slot = id
		next.application_recovery.resumed_commit = commit
		if next != _state and _commit(next) != OK: return {}
	# The proved resumed head can have its own replacement destination. Keep
	# that durable association on replay; a divergent head above forks first.
	return _recovery_entry(id, work, _current_recovery_manual_path(id))

func _manual_destination(path: String, id: String = "") -> Dictionary:
	for entry in slots():
		if not id.is_empty() and entry.slot_id == id: return entry
		if id.is_empty() and _same_manual_path(path, entry.manual_path): return entry
	return {}

## Replays only the successful file's exact bytes. A changed destination keeps
## its complete branch; the saved file becomes a separate root. Completed IDs
## in the same journal transaction make receipt cleanup safely retryable.
func recover_manual_save(transition: Dictionary) -> String:
	if not _valid_manual_intent(transition) or FileAccess.get_sha256(transition.path) != transition.sha256: return ""
	var claim := path_claim(transition.path)
	if not claim.is_empty() and claim.owner != _owner and not transition.transfer: return ""
	for entry in _state.slots.values():
		if entry.get("manual_intent", "") == transition.intent_id:
			clear_manual_intent(transition)
			return entry.slot_id
	var target: String = transition.target
	var branched := false
	if target.is_empty():
		target = transition.source if transition.unnamed or transition.same_path else create_slot()
		if target.is_empty(): return ""
		transition.target = target
		transition.target_head = manual_identity_head(_manual_destination("", target))
		# A failed receipt update still leaves the previous receipt recoverable.
		record_manual_intent(transition)
	else:
		var current := _manual_destination("", target)
		var destination := _manual_destination(transition.path)
		var moved: bool = not destination.is_empty() and destination.slot_id != target
		var repaired: bool = transition.target_head.get("generation", -1) == 0 and transition.target_head.get("continuation_sha256", "").is_empty() and transition.target_head.get("manual_sha256", "").is_empty() and not moved and current.get("manual_sha256", "") == transition.sha256 and current.get("continuation_sha256", "") == transition.sha256 and _same_manual_path(current.get("manual_path", ""), transition.path)
		if repaired:
			branched = not (transition.unnamed and transition.source != target)
		elif moved or manual_identity_head(current) != transition.target_head:
			var origin: String = destination.get("slot_id", target)
			target = branch_manual_save(origin, transition.path, transition.sha256, transition.source if transition.unnamed and transition.source != origin else "", transition.intent_id)
			if target.is_empty(): return ""
			branched = true
	if transition.transfer and claim_manual_path(transition.path, target, true) != OK: return ""
	if not branched and stage(target, transition.path, transition.path, false, transition.source if transition.unnamed and transition.source != target else "", transition.intent_id).is_empty(): return ""
	clear_manual_intent(transition)
	_unreconciled_manual.erase(transition.path)
	return target

## Only direct personal files qualify. Exact retained MANUAL bytes can attach
## without an upload; a continuation-only match must preserve this file's new
## manual intent as a separate root, never replace the remote manual baseline.
func migrate_personal_file(path: String) -> Error:
	# Unreadable files are skipped without side effects. Exact retained manual
	# bytes were fully validated when stored, so only new content is decoded.
	if _owner.is_empty() or not personal_path(path) or not FileAccess.file_exists(path): return OK
	var digest := _file_sha256(path)
	if digest.is_empty(): return OK
	var receipt := manual_intent(path)
	if not receipt.is_empty() and digest == receipt.sha256:
		if readable_header(path).is_empty(): return OK
		return OK if not recover_manual_save(receipt).is_empty() else ERR_CANT_CREATE
	var claim := path_claim(path)
	if not claim.is_empty() and claim.owner != _owner: return OK
	var id: String = claim.get("slot_id", "")
	for row in slots():
		if _same_manual_path(row.manual_path, path):
			if not _empty_reservation(_state.slots[row.slot_id]):
				if digest == row.manual_sha256: _unreconciled_manual.erase(path)
				elif readable_header(path).is_empty(): return OK
				else: _unreconciled_manual[path] = true
				return claim_manual_path(path, row.slot_id)
			id = row.slot_id
	if readable_header(path).is_empty(): return OK
	var repairing := not id.is_empty() and _has_slot(id) and _empty_reservation(_state.slots[id])
	if not repairing:
		for row in slots():
			if row.manual_sha256 == digest and row.manual_path.is_empty(): return bind_manual_path(row.slot_id, path)
	if id.is_empty() or (_has_slot(id) and not repairing): id = CloudSaveTypes.uuid()
	var payload := _copy_payload(path, digest)
	if payload.is_empty(): return ERR_FILE_CORRUPT
	var claimed := claim_manual_path(path, id)
	if claimed != OK: return claimed
	var next := _state.duplicate(true)
	var slot := _new_slot(id, path)
	slot.generation = 1
	slot.continuation = payload.duplicate(true)
	slot.manual = payload.duplicate(true)
	slot.sync_state = "pending"
	slot.pending = {"slot_id":id, "generation":1, "commit_id":CloudSaveTypes.uuid(), "parent_commit_id":"", "baseline":PackedByteArray(), "baseline_tag":"", "continuation":payload.duplicate(true), "manual":payload.duplicate(true), "tombstone":false, "owner":_owner}
	_set_header(slot, _payload_header(payload.path))
	next.slots[id] = slot
	return _commit(next)

## Only a never-published empty reservation may be filled in place. A real
## branch, acknowledged head or uncertain send must retain its own identity.
func _empty_reservation(slot: Dictionary) -> bool:
	return slot.generation == 0 and not slot.tombstone and slot.continuation.is_empty() and slot.manual.is_empty() and slot.pending.is_empty() and slot.uploads.is_empty() and slot.commit_id.is_empty() and slot.baseline_tag.is_empty() and slot.system_fields.is_empty() and slot.forks.is_empty()

func journal_path() -> String:
	return _directory.path_join("journal.bin")

func open_library(owner: String) -> Error:
	if not CloudSaveTypes.valid_id(owner, true): return ERR_INVALID_PARAMETER
	if _claims().is_empty(): return ERR_FILE_CORRUPT
	var directory := _account_directory(owner)
	var made := DirAccess.make_dir_recursive_absolute(directory.path_join("payloads"))
	if made != OK: return made
	var committed := _read_journal(directory.path_join("journal.bin"), directory, owner)
	var staged := _read_journal(directory.path_join("journal.bin.pending"), directory, owner)
	var chosen: Dictionary = committed
	if not staged.is_empty() and (chosen.is_empty() or staged.revision > chosen.revision):
		chosen = staged
		var recovered := DirAccess.rename_absolute(directory.path_join("journal.bin.pending"), directory.path_join("journal.bin"))
		if recovered != OK: return recovered
	if chosen.is_empty() and (FileAccess.file_exists(directory.path_join("journal.bin")) or FileAccess.file_exists(directory.path_join("journal.bin.pending"))):
		return ERR_FILE_CORRUPT
	_owner = owner
	_unreconciled_manual.clear()
	_directory = directory
	_state = chosen if not chosen.is_empty() else {"version": JOURNAL_VERSION, "owner": owner, "revision": 0, "slots": {}}
	var compacted := _state.duplicate(true)
	# Explicit cross-account Save As may transfer a filename. Repair stale
	# associations before exposing a reopened namespace; its payloads stay parked.
	for slot in compacted.slots.values():
		if slot.manual_path.is_empty(): continue
		var claim := path_claim(slot.manual_path)
		if not claim.is_empty() and claim.owner != owner: slot.manual_path = ""
	_compact_history(compacted)
	if compacted != _state: return _commit(compacted)
	_prune_payloads()
	return OK

## The cursor advances only after the coordinator durably publishes a full page.
func change_token() -> PackedByteArray:
	return _state.get("change_token", PackedByteArray()).duplicate()

func commit_change_token(token: PackedByteArray) -> Error:
	if _state.is_empty() or token.size() > MAX_CHANGE_TOKEN_BYTES: return ERR_INVALID_PARAMETER
	var next := _state.duplicate(true)
	next.change_token = token.duplicate()
	return _commit(next)

## Authoritative server deletion, after any local branch/pin is reconciled.
## Named manual files are outside the private payload store and remain intact.
func remove_remote(slot_id: String) -> Error:
	if not CloudSaveTypes.valid_id(slot_id): return ERR_INVALID_PARAMETER
	if not _has_slot(slot_id): return OK
	var slot: Dictionary = _state.slots[slot_id]
	if not slot.pending.is_empty() or not slot.uploads.is_empty(): return ERR_BUSY
	var next := _state.duplicate(true)
	next.slots[slot_id].tombstone = true
	next.slots[slot_id].continuation = {}
	next.slots[slot_id].manual = {}
	next.slots[slot_id].sync_state = "synced"
	return _commit(next)

func create_slot(manual_path: String = "") -> String:
	if _state.is_empty(): return ""
	if not manual_path.is_empty() and readable_header(manual_path).is_empty(): return ""
	var id := CloudSaveTypes.uuid()
	if id.is_empty(): return ""
	if not manual_path.is_empty() and claim_manual_path(manual_path, id) != OK: return ""
	var next := _state.duplicate(true)
	next.slots[id] = _new_slot(id, manual_path)
	return id if _commit(next) == OK else ""

## Bind a local personal destination without changing either saved payload.
## Nonexistent destinations are reservations, never advertised as readable files.
func bind_manual_path(slot_id: String, path: String) -> Error:
	if not _has_slot(slot_id) or path.is_empty(): return ERR_INVALID_PARAMETER
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	if _inside_root(absolute, _root) or not absolute.ends_with(".sc2d"): return ERR_INVALID_PARAMETER
	for id in _state.slots:
		var other: Dictionary = _state.slots[id]
		if id != slot_id and not other.tombstone and _same_manual_path(other.manual_path, absolute):
			return ERR_ALREADY_EXISTS
	var claimed := claim_manual_path(path, slot_id)
	if claimed != OK: return claimed
	if _state.slots[slot_id].manual_path == path: return OK
	var next := _state.duplicate(true)
	next.slots[slot_id].manual_path = path
	return _commit(next)

## Recover a manual Replace whose destination advanced while staging failed.
## Publish a new root and transfer only the local filename in one transaction;
## the advanced origin's payloads, conditional head and uncertain pins survive.
func branch_manual_save(origin_id: String, path: String, expected_hash: String, retire_slot: String = "", intent_id: String = "") -> String:
	if not _has_slot(origin_id) or path.is_empty() or not CloudSaveTypes.valid_hash(expected_hash): return ""
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	if _inside_root(absolute, _root) or not absolute.ends_with(".sc2d"): return ""
	for id in _state.slots:
		var existing: Dictionary = _state.slots[id]
		if id != origin_id and not existing.tombstone and _same_manual_path(existing.manual_path, absolute): return ""
	var origin: Dictionary = _state.slots[origin_id]
	if not origin.manual_path.is_empty() and not _same_manual_path(origin.manual_path, absolute): return ""
	var claimed := claim_manual_path(path, origin_id)
	if claimed != OK: return ""
	var payload := _copy_payload(path, expected_hash)
	if payload.is_empty(): return ""
	var id := CloudSaveTypes.uuid()
	var slot := _new_slot(id, path)
	slot.conflict_origin = origin_id
	if not intent_id.is_empty(): slot.manual_intent = intent_id
	slot.source_device_label = coarse_device_label(OS.get_name())
	slot.generation = 1
	slot.continuation = payload.duplicate(true)
	slot.manual = payload.duplicate(true)
	slot.sync_state = "pending"
	var work := {"slot_id": id, "generation": 1, "commit_id": CloudSaveTypes.uuid(),
		"parent_commit_id": "", "baseline": PackedByteArray(), "baseline_tag": "",
		"continuation": payload.duplicate(true), "manual": payload.duplicate(true), "tombstone": false, "owner": _owner}
	if not CloudSaveTypes.valid_pending(work): return ""
	slot.pending = work
	slot.history["1"] = work.duplicate(true)
	_set_header(slot, _payload_header(payload.path))
	var next := _state.duplicate(true)
	next.slots[origin_id].manual_path = ""
	next.slots[id] = slot
	if not retire_slot.is_empty() and not _retire_unnamed(next, retire_slot): return ""
	return id if _commit(next) == OK else ""

func stage(slot_id: String, continuation_path: String, manual_path: String = "", tombstone: bool = false, retire_slot: String = "", intent_id: String = "") -> Dictionary:
	if not _has_slot(slot_id): return {}
	if not manual_path.is_empty():
		for id in _state.slots:
			var other: Dictionary = _state.slots[id]
			if id != slot_id and not other.tombstone and _same_manual_path(other.manual_path, manual_path): return {}
		if claim_manual_path(manual_path, slot_id) != OK: return {}
	var slot: Dictionary = _state.slots[slot_id]
	var continuation: Dictionary = {}
	var manual: Dictionary = {}
	if not tombstone:
		continuation = _copy_payload(continuation_path)
		if continuation.is_empty(): return {}
	if not manual_path.is_empty():
		# A manual save identical to the continuation shares its validated payload.
		if not continuation.is_empty() and _file_sha256(manual_path) == continuation.sha256: manual = continuation.duplicate(true)
		else: manual = _copy_payload(manual_path)
		if manual.is_empty(): return {}
	elif not slot.manual.is_empty():
		manual = slot.manual.duplicate(true)
	# Snapshots created while a send is uncertain descend from that exact commit.
	# Its actual new archive/tag arrives only on acknowledgement. The coordinator
	# reconciles the pin before dispatching descendants against that baseline.
	var parent: String = slot.commit_id
	var latest_upload := -1
	for sent in slot.uploads.values():
		if sent.generation > latest_upload and sent.parent_commit_id == slot.commit_id and sent.baseline_tag == slot.baseline_tag:
			parent = sent.commit_id
			latest_upload = sent.generation
	var work := {"slot_id": slot_id, "generation": slot.generation + 1,
		"commit_id": CloudSaveTypes.uuid(), "parent_commit_id": parent,
		"baseline": slot.system_fields, "baseline_tag": slot.baseline_tag,
		"continuation": continuation, "manual": manual, "tombstone": tombstone, "owner": _owner}
	if not CloudSaveTypes.valid_pending(work): return {}
	var next := _state.duplicate(true)
	var updated: Dictionary = next.slots[slot_id]
	if not intent_id.is_empty(): updated.manual_intent = intent_id
	updated.generation = work.generation
	updated.pending = work
	updated.history[str(work.generation)] = work.duplicate(true)
	updated.continuation = continuation
	updated.manual = manual
	updated.tombstone = tombstone
	updated.sync_state = "pending"
	updated.source_device_label = coarse_device_label(OS.get_name())
	if not manual_path.is_empty(): updated.manual_path = manual_path
	if not tombstone: _set_header(updated, _payload_header(continuation.path))
	if not retire_slot.is_empty() and not _retire_unnamed(next, retire_slot): return {}
	if _commit(next) != OK: return {}
	if not manual_path.is_empty(): _unreconciled_manual.erase(manual_path)
	return work.duplicate(true)

## Used only by explicit first-save Replace, in the SAME journal publication
## as its destination. Unknown upload outcomes retain their immutable pins.
func _retire_unnamed(next: Dictionary, id: String) -> bool:
	if not next.slots.has(id): return false
	var slot: Dictionary = next.slots[id]
	if not slot.manual.is_empty(): return false
	slot.manual_path = "" # A reservation alone is not an explicit manual point.
	var parent: String = slot.commit_id
	var latest := -1
	for sent in slot.uploads.values():
		if sent.generation > latest and sent.parent_commit_id == slot.commit_id and sent.baseline_tag == slot.baseline_tag:
			parent = sent.commit_id
			latest = sent.generation
	slot.generation += 1
	slot.pending = {"slot_id":id, "generation":slot.generation, "commit_id":CloudSaveTypes.uuid(), "parent_commit_id":parent, "baseline":slot.system_fields.duplicate(), "baseline_tag":slot.baseline_tag, "continuation":{}, "manual":{}, "tombstone":true, "owner":_owner}
	slot.continuation = {}
	slot.tombstone = true
	slot.sync_state = "pending"
	return CloudSaveTypes.valid_pending(slot.pending)

func pending() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in _state.get("slots", {}).values():
		if not slot.pending.is_empty(): result.append(slot.pending.duplicate(true))
	return result

func slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in _state.get("slots", {}).values():
		if slot.tombstone: continue
		var entry: Dictionary = slot.duplicate(true)
		entry.erase("history")
		entry.erase("pending")
		entry.erase("uploads")
		entry.erase("forks")
		entry.path = slot.continuation.get("path", "")
		entry.cloud_owned = not slot.owner.is_empty()
		entry.continuation_sha256 = slot.continuation.get("sha256", "")
		entry.manual_sha256 = slot.manual.get("sha256", "")
		result.append(entry)
	return result

## Persist before dispatch. A recovered entry represents an uncertain network
## outcome and must remain pinned until acknowledgement or confirmed nonapplication.
func begin_upload(slot_id: String, generation: int) -> Dictionary:
	if not _has_slot(slot_id): return {}
	var slot: Dictionary = _state.slots[slot_id]
	var key := str(generation)
	if slot.uploads.has(key): return slot.uploads[key].duplicate(true)
	if slot.pending.is_empty() or slot.pending.generation != generation: return {}
	if slot.pending.parent_commit_id != slot.commit_id or slot.pending.baseline_tag != slot.baseline_tag: return {}
	var next := _state.duplicate(true)
	next.slots[slot_id].uploads[key] = slot.pending.duplicate(true)
	return slot.pending.duplicate(true) if _commit(next) == OK else {}

func inflight() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot in _state.get("slots", {}).values():
		for work in slot.uploads.values(): result.append(work.duplicate(true))
	return result

## Allocation-free queue summaries for per-frame status and scheduling.
func pending_count() -> int:
	var count := 0
	for slot in _state.get("slots", {}).values():
		if not slot.pending.is_empty(): count += 1
	return count

func has_pin(slot_id: String, generation: int, commit_id: String) -> bool:
	if not _has_slot(slot_id): return false
	var pin: Dictionary = _state.slots[slot_id].uploads.get(str(generation), {})
	return not pin.is_empty() and pin.commit_id == commit_id

func has_inflight() -> bool:
	for slot in _state.get("slots", {}).values():
		if not slot.uploads.is_empty(): return true
	return false

## The slot's first uncertain pin, else its pending work, else empty. Matches
## scanning inflight() then pending() without copying unrelated slots.
func work_for(slot_id: String) -> Dictionary:
	# Journal validation binds every pin and pending entry to its own slot key.
	if not _has_slot(slot_id): return {}
	var slot: Dictionary = _state.slots[slot_id]
	if not slot.uploads.is_empty(): return (slot.uploads.values()[0] as Dictionary).duplicate(true)
	return slot.pending.duplicate(true)

## Changes whenever a journal fact that personal-file migration reads changes:
## named destinations, retained manual digests and empty reservations, plus the
## installation-wide claims file. Unchanged files need no new migration pass.
func migration_signature() -> String:
	var parts: Array[String] = [_directory, _owner]
	var ids: Array = _state.get("slots", {}).keys()
	ids.sort()
	for id: String in ids:
		var slot: Dictionary = _state.slots[id]
		parts.append("%s|%s|%s|%s|%s" % [id, path_key(slot.manual_path) if not slot.manual_path.is_empty() else "", slot.manual.get("sha256", ""), slot.tombstone, _empty_reservation(slot)])
	var claims := _root.path_join("ownership.bin")
	parts.append("claims|" + (FileAccess.get_sha256(claims) if FileAccess.file_exists(claims) else ""))
	return "\n".join(parts).sha256_text()

## Fork publication leaves a durable marker on the original identity until its
## server branch is published or authoritatively removed. Include tombstones,
## which deliberately do not appear in slots(). Temporary native paths never
## enter the journal.
func unresolved_remote_slots() -> Array[String]:
	var result: Array[String] = []
	for slot in _state.get("slots", {}).values():
		if slot.sync_state == "conflict" and slot.pending.is_empty() and slot.uploads.is_empty(): result.append(slot.slot_id)
	return result

## Reconcile an uncertain send or equal-content concurrent commit. Remote content
## is checked against the immutable durable pin before adopting its canonical ID.
func acknowledge_remote(slot_id: String, generation: int, remote: Dictionary) -> Error:
	if not _has_slot(slot_id) or not CloudSaveTypes.valid_remote(remote) or remote.slot_id != slot_id:
		return ERR_INVALID_PARAMETER
	var sent: Dictionary = _state.slots[slot_id].uploads.get(str(generation), {})
	if sent.is_empty() or not CloudSavePolicy.same_content(sent, remote): return ERR_INVALID_PARAMETER
	return _acknowledge(slot_id, generation, sent.commit_id, remote.system_fields, remote.change_tag, remote.commit_id)

## The coordinator may call this only after confirmed nonapplication or explicit
## abandonment. Timeouts, sign-out and transient failures are uncertain outcomes.
func retire_upload(slot_id: String, generation: int) -> Error:
	if not _has_slot(slot_id): return ERR_INVALID_PARAMETER
	if not _state.slots[slot_id].uploads.has(str(generation)): return ERR_DOES_NOT_EXIST
	var next := _state.duplicate(true)
	var slot: Dictionary = next.slots[slot_id]
	var sent: Dictionary = slot.uploads[str(generation)]
	# Confirmed nonapplication returns an unsent child to its proven old parent.
	# Already sent snapshots are immutable, and rebased/forked branches never move.
	if not slot.pending.is_empty() and not slot.uploads.has(str(slot.pending.generation)) and slot.pending.parent_commit_id == sent.commit_id and slot.pending.baseline_tag == sent.baseline_tag and slot.pending.owner == sent.owner and slot.commit_id == sent.parent_commit_id and slot.baseline_tag == sent.baseline_tag:
		slot.pending.parent_commit_id = sent.parent_commit_id
		slot.pending.baseline = sent.baseline.duplicate()
		slot.pending.baseline_tag = sent.baseline_tag
	slot.uploads.erase(str(generation))
	return _commit(next)

func acknowledge(slot_id: String, generation: int, commit_id: String, system_fields: PackedByteArray, change_tag: String) -> Error:
	return _acknowledge(slot_id, generation, commit_id, system_fields, change_tag, commit_id)

func _acknowledge(slot_id: String, generation: int, commit_id: String, system_fields: PackedByteArray, change_tag: String, canonical_commit: String) -> Error:
	if not _has_slot(slot_id) or not CloudSaveTypes.valid_id(commit_id) or change_tag.to_utf8_buffer().size() > CloudSaveTypes.MAX_ID_BYTES:
		return ERR_INVALID_PARAMETER
	var slot: Dictionary = _state.slots[slot_id]
	# Acknowledged pins retire from history, so duplicate success is checked
	# against the acknowledged slot head rather than requiring its old payload.
	if slot.commit_id == commit_id: return OK
	var sent: Dictionary = slot.uploads.get(str(generation), {})
	if sent.is_empty() or sent.commit_id != commit_id or sent.owner != _owner: return ERR_INVALID_PARAMETER
	var next := _state.duplicate(true)
	var updated: Dictionary = next.slots[slot_id]
	updated.uploads.erase(str(generation))
	if slot.commit_id != sent.parent_commit_id or slot.baseline_tag != sent.baseline_tag:
		var retired := _commit(next)
		return ERR_BUSY if retired == OK else retired
	updated.commit_id = canonical_commit
	updated.system_fields = system_fields.duplicate()
	updated.baseline_tag = change_tag
	if not updated.pending.is_empty():
		if updated.pending.generation == generation and updated.pending.commit_id == commit_id:
			updated.pending = {}
			updated.sync_state = "synced"
		elif not updated.uploads.has(str(updated.pending.generation)) and (updated.pending.parent_commit_id == sent.commit_id or updated.pending.parent_commit_id == sent.parent_commit_id) and updated.pending.baseline_tag == sent.baseline_tag and updated.pending.owner == sent.owner:
			updated.pending.parent_commit_id = canonical_commit
			updated.pending.baseline = system_fields.duplicate()
			updated.pending.baseline_tag = change_tag
	if updated.pending.is_empty(): updated.sync_state = "synced"
	return _commit(next)

func publish_remote(remote: Dictionary, downloaded: Dictionary) -> Error:
	if _state.is_empty() or not CloudSaveTypes.valid_remote(remote): return ERR_INVALID_PARAMETER
	if _has_slot(remote.slot_id) and (not _state.slots[remote.slot_id].pending.is_empty() or not _state.slots[remote.slot_id].uploads.is_empty()): return ERR_BUSY
	var continuation: Dictionary = {}
	var manual: Dictionary = {}
	if not remote.tombstone:
		continuation = _copy_payload(_download_path(downloaded.get("continuation", "")), remote.continuation_sha256)
		if continuation.is_empty(): return ERR_FILE_CORRUPT
	if not remote.manual_sha256.is_empty():
		if remote.manual_sha256 == remote.continuation_sha256 and not continuation.is_empty(): manual = continuation.duplicate(true)
		else: manual = _copy_payload(_download_path(downloaded.get("manual", "")), remote.manual_sha256)
		if manual.is_empty(): return ERR_FILE_CORRUPT
	var next := _state.duplicate(true)
	var slot := _new_slot(remote.slot_id, "")
	if next.slots.has(remote.slot_id): slot = next.slots[remote.slot_id]
	slot.commit_id = remote.commit_id
	slot.baseline_tag = remote.change_tag
	slot.system_fields = remote.system_fields.duplicate()
	slot.continuation = continuation
	slot.manual = manual
	slot.tombstone = remote.tombstone
	slot.sync_state = "synced"
	slot.source_device_label = coarse_device_label(remote.metadata.get("source_device_label", ""))
	var origin := metadata_conflict_origin(remote.metadata.get("conflict_origin", ""))
	if not origin.is_empty(): slot.conflict_origin = origin
	if not continuation.is_empty(): _set_header(slot, _payload_header(continuation.path))
	next.slots[remote.slot_id] = slot
	return _commit(next)

func _adoption_destination() -> CloudSaveStore:
	return CloudSaveStore.new(_root)

## Finish claims whose destination journal publication was interrupted. Runs
## before exposing an account or migrating files, using immutable local bytes.
func repair_adoptions() -> Error:
	if _owner.is_empty(): return OK
	var claims := _claims()
	if claims.is_empty(): return ERR_FILE_CORRUPT
	var local := CloudSaveStore.new(_root)
	var error := local.open_library("")
	if error != OK: return error
	for key in claims.claims:
		var proof: Dictionary = claims.claims[key]
		if key.begins_with("local:") and proof.owner == _owner and not _has_slot(proof.slot_id):
			error = local.adopt_local(proof.slot_id, _owner)
			if error != OK: return error
	return open_library(_owner)

func adopt_local(slot_id: String, owner: String) -> Error:
	if _owner != "" or not _has_slot(slot_id) or not CloudSaveTypes.valid_id(owner): return ERR_INVALID_PARAMETER
	# Copy first; local originals survive a failed destination publication and
	# remain available while signed out. Adoption never transfers other owners.
	var destination := _adoption_destination()
	var opened := destination.open_library(owner)
	if opened != OK: return opened
	var source: Dictionary = _state.slots[slot_id]
	var keys: Array[String] = ["local:" + slot_id]
	if not source.manual_path.is_empty(): keys.append("path:" + ProjectSettings.globalize_path(source.manual_path).simplify_path())
	var claimed := _claim(keys, owner, slot_id)
	if claimed != OK: return claimed
	if destination._has_slot(slot_id): return OK
	var adopted := source.duplicate(true)
	# A restart may already have repaired the consumed local association.
	# Restore only this owner's reserved path, never infer it from file bytes.
	if adopted.manual_path.is_empty():
		var all_claims: Dictionary = _claims().get("claims", {})
		for key in all_claims:
			var proof: Dictionary = all_claims[key]
			if key.begins_with("path:") and proof.owner == owner and proof.slot_id == slot_id:
				adopted.manual_path = key.trim_prefix("path:")
	adopted.owner = owner
	adopted.commit_id = ""
	adopted.baseline_tag = ""
	adopted.system_fields = PackedByteArray()
	adopted.history = {}
	adopted.uploads = {}
	adopted.forks = {}
	for key in ["continuation", "manual"]:
		if not source[key].is_empty():
			adopted[key] = destination._copy_payload(source[key].path, source[key].sha256)
			if adopted[key].is_empty(): return ERR_FILE_CORRUPT
	if not source.pending.is_empty():
		adopted.pending = source.pending.duplicate(true)
		adopted.pending.owner = owner
		adopted.pending.parent_commit_id = ""
		adopted.pending.baseline = PackedByteArray()
		adopted.pending.baseline_tag = ""
		adopted.pending.continuation = adopted.continuation
		adopted.pending.manual = adopted.manual
		adopted.history[str(adopted.pending.generation)] = adopted.pending.duplicate(true)
	var next := destination._state.duplicate(true)
	next.slots[slot_id] = adopted
	var recovery: Dictionary = _state.get("application_recovery", {})
	if not recovery.is_empty() and recovery.work.slot_id == slot_id:
		recovery = recovery.duplicate(true)
		recovery.owner = owner
		recovery.work.owner = owner
		recovery.work.parent_commit_id = ""
		recovery.work.baseline = PackedByteArray()
		recovery.work.baseline_tag = ""
		for key in ["continuation", "manual"]:
			if not recovery.work[key].is_empty():
				recovery.work[key] = destination._copy_payload(recovery.work[key].path, recovery.work[key].sha256)
				if recovery.work[key].is_empty(): return ERR_FILE_CORRUPT
		next.application_recovery = recovery
	return destination._commit(next)

func fork_pending(slot_id: String, generation: int, exact_recovery: bool = false) -> String:
	if not _has_slot(slot_id): return ""
	var source: Dictionary = _state.slots[slot_id]
	# Mapping is scoped to the conflicting generation, not a global slot alias.
	# A newly loaded original remote row always retains its independent identity.
	var previous: Dictionary = source.forks.get(str(generation), {})
	if not exact_recovery and not previous.is_empty(): return previous.slot_id
	var work: Dictionary = source.history.get(str(generation), {})
	var receipt: Dictionary = _state.get("application_recovery", {})
	if exact_recovery:
		if receipt.is_empty() or receipt.work.slot_id != slot_id or receipt.work.generation != generation: return ""
		work = receipt.work
	if work.is_empty(): return ""
	var head := work
	if not exact_recovery and not source.pending.is_empty() and source.pending.owner == work.owner and source.pending.baseline_tag == work.baseline_tag and (source.pending.parent_commit_id == work.commit_id or source.pending.parent_commit_id == work.parent_commit_id):
		head = source.pending
	var id := CloudSaveTypes.uuid()
	if id.is_empty(): return ""
	var manual_path: String = _recovery_manual_path(receipt) if exact_recovery else source.manual_path
	var slot := _new_slot(id, manual_path)
	slot.conflict_origin = slot_id
	slot.source_device_label = coarse_device_label(OS.get_name())
	slot.generation = 1
	slot.continuation = head.continuation.duplicate(true)
	slot.manual = head.manual.duplicate(true)
	slot.tombstone = head.tombstone
	slot.sync_state = "pending"
	var fork := head.duplicate(true)
	fork.slot_id = id
	fork.generation = 1
	fork.commit_id = CloudSaveTypes.uuid()
	fork.parent_commit_id = ""
	fork.baseline = PackedByteArray()
	fork.baseline_tag = ""
	slot.pending = fork
	slot.history["1"] = fork.duplicate(true)
	if not slot.continuation.is_empty(): _set_header(slot, _payload_header(slot.continuation.path))
	var next := _state.duplicate(true)
	next.slots[id] = slot
	var original: Dictionary = next.slots[slot_id]
	if exact_recovery:
		next.application_recovery.resumed_slot = id
		next.application_recovery.resumed_commit = fork.commit_id
		# Keep the exact branch made by this durable fork as the captured work.
		# source_slot continues binding the unchanged installation pointer.
		next.application_recovery.work = fork.duplicate(true)
		if _same_manual_path(original.manual_path, manual_path): original.manual_path = ""
	else: original.forks[str(generation)] = {"commit_id": work.commit_id, "slot_id": id}
	if not exact_recovery and not source.pending.is_empty() and head.commit_id == source.pending.commit_id:
		original.forks[str(head.generation)] = {"commit_id": head.commit_id, "slot_id": id}
		original.pending = {}
		original.manual_path = ""
		# Original uncertain pins remain owned until confirmed, independently of
		# the new branch. Their eventual success must expose their actual bytes.
		original.continuation = work.continuation.duplicate(true)
		original.manual = work.manual.duplicate(true)
		original.tombstone = work.tombstone
		original.sync_state = "conflict"
		if not work.continuation.is_empty(): _set_header(original, _payload_header(work.continuation.path))
	return id if _commit(next) == OK else ""

func _new_slot(id: String, manual_path: String) -> Dictionary:
	return {"slot_id": id, "owner": _owner, "manual_path": manual_path, "generation": 0,
		"commit_id": "", "baseline_tag": "", "system_fields": PackedByteArray(),
		"continuation": {}, "manual": {}, "pending": {}, "history": {},
		"uploads": {}, "forks": {}, "tombstone": false, "sync_state": "local", "conflict_origin": ""}

func _has_slot(id: String) -> bool:
	return CloudSaveTypes.valid_id(id) and _state.get("slots", {}).has(id)

func _account_directory(owner: String) -> String:
	return _root.path_join("local" if owner.is_empty() else "accounts/" + owner.sha256_text())

func _download_path(value: Variant) -> String:
	if value is String: return value
	if value is Dictionary and value.get("path") is String: return value.path
	return ""

## Public bounded validator used by library publication. Returns no readable
## path for malformed, unsupported, oversized, or incomplete city documents.
func readable_header(path: String) -> Dictionary:
	if path.is_empty(): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var size := file.get_length()
	if size <= 0 or size > CloudSaveTypes.MAX_ASSET_BYTES:
		file.close()
		return {}
	var bytes := file.get_buffer(size)
	file.close()
	if bytes.size() != size: return {}
	var digest := _digest(bytes)
	var version: int = _validated_versions.get(digest, 0)
	if version == 0: version = _validated_version(path, bytes.get_string_from_utf8())
	if version == 0: return {}
	# Header fallbacks depend on this path/mtime even for identical contents.
	var header := SaveFormat.read_header(path)
	header["application_save_version"] = version
	var metadata := header.duplicate()
	metadata.erase("path")
	if not CloudSaveTypes.valid_metadata(metadata): return {}
	# A concurrent replacement during the cold decode/header read cannot install
	# a validation entry for different bytes. Immutable owned copies are normal.
	if FileAccess.get_sha256(path) != digest: return {}
	_validated_versions.erase(digest)
	while _validated_versions.size() >= VALIDATED_CONTENT_LIMIT:
		_validated_versions.erase(_validated_versions.keys()[0])
	_validated_versions[digest] = version
	return header

## Full format/city/snapshot validation remains mandatory for every new digest.
func _validated_version(path: String, text: String) -> int:
	var parsed := JSON.new()
	if parsed.parse(text) != OK or not parsed.data is Dictionary: return 0
	var loaded := SaveFormat.load(path)
	return int(loaded.get("version", 0)) if loaded.get("ok", false) else 0

## Describes the exact immutable payload, including the document's actual save
## version rather than the current writer version. Native never parses cities.
## Current bytes must match the descriptor; the full decode happens once per
## process for those exact bytes, at their first actual use.
func payload_metadata(payload: Dictionary) -> Dictionary:
	if not payload_intact(payload): return {}
	var key := path_key(payload.path)
	var known: Dictionary = _payload_headers.get(key, {})
	if known.get("sha256", "") == payload.sha256: return (known.header as Dictionary).duplicate(true)
	var header := readable_header(payload.path)
	header.erase("path")
	# The decoded bytes must still be the descriptor's bytes.
	if header.is_empty() or FileAccess.get_sha256(payload.path) != payload.sha256: return {}
	_payload_headers.erase(key)
	while _payload_headers.size() >= PAYLOAD_HEADER_LIMIT: _payload_headers.erase(_payload_headers.keys()[0])
	_payload_headers[key] = {"sha256": payload.sha256, "header": header.duplicate(true)}
	return header

## Cheap integrity check of a journal descriptor against current file bytes:
## exact size and SHA-256 (memoized by the racy-time rule above). Every journal
## payload was fully format-validated before its descriptor was published, so a
## matching digest proves these are those validated bytes.
func payload_intact(payload: Dictionary) -> bool:
	if not CloudSaveTypes.valid_payload(payload): return false
	return _file_matches(payload.path, payload.sha256, payload.bytes)

## True when a local file currently has exactly this digest.
func file_matches(path: String, sha256: String) -> bool:
	return _file_matches(path, sha256)

func _file_matches(path: String, sha256: String, expected_bytes: int = -1) -> bool:
	if path.is_empty() or not CloudSaveTypes.valid_hash(sha256): return false
	if expected_bytes >= 0:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null: return false
		var size := file.get_length()
		file.close()
		if size != expected_bytes: return false
	return _file_sha256(path) == sha256

## Current SHA-256 of a local file, or "" when it cannot be read. A memo entry is
## reused only for an unchanged size and modification second that predates the
## second in which its hash began; anything else is hashed again.
func _file_sha256(path: String) -> String:
	if path.is_empty(): return ""
	var key := path_key(path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_intact_files.erase(key)
		return ""
	var size := file.get_length()
	file.close()
	var modified := FileAccess.get_modified_time(path)
	var known: Dictionary = _intact_files.get(key, {})
	if not known.is_empty() and known.bytes == size and known.modified == modified and modified < known.checked:
		return known.sha256
	var checked := int(Time.get_unix_time_from_system())
	var digest := _hash_file(path)
	_intact_files.erase(key)
	if digest.is_empty() or FileAccess.get_modified_time(path) != modified: return digest
	while _intact_files.size() >= INTACT_FILE_LIMIT: _intact_files.erase(_intact_files.keys()[0])
	_intact_files[key] = {"sha256": digest, "bytes": size, "modified": modified, "checked": checked}
	return digest

func _hash_file(path: String) -> String:
	return FileAccess.get_sha256(path)

func _copy_payload(path: String, expected_hash: String = "") -> Dictionary:
	if path.is_empty(): return {}
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null: return {}
	var size := source.get_length()
	if size <= 0 or size > CloudSaveTypes.MAX_ASSET_BYTES:
		source.close()
		return {}
	var bytes := source.get_buffer(size)
	source.close()
	if bytes.size() != size: return {}
	var digest := _digest(bytes)
	if not expected_hash.is_empty() and digest != expected_hash: return {}
	var id := CloudSaveTypes.uuid()
	var destination := _directory.path_join("payloads").path_join(id + ".sc2d")
	var staged := destination + ".pending"
	if FileAccess.file_exists(destination) or FileAccess.file_exists(staged): return {}
	if SaveFormat._write_replacement(staged, bytes) != OK: return {}
	# The private copy is bounded and immutable before full format validation.
	var header := readable_header(staged)
	if header.is_empty():
		DirAccess.remove_absolute(staged)
		return {}
	if DirAccess.rename_absolute(staged, destination) != OK: return {}
	while _copied_headers.size() >= 8: _copied_headers.erase(_copied_headers.keys()[0])
	_copied_headers[destination] = header
	return {"path": destination, "sha256": digest, "bytes": size}


func _set_header(slot: Dictionary, header: Dictionary) -> void:
	for key in header:
		if key != "path": slot[key] = header[key]

## Header of a payload copied by this instance, without reading it again.
func _payload_header(path: String) -> Dictionary:
	if _copied_headers.has(path): return (_copied_headers[path] as Dictionary).duplicate(true)
	return readable_header(path)

func _commit(next: Dictionary) -> Error:
	_compact_history(next)
	next.revision = _state.revision + 1
	var body := var_to_bytes(next)
	if body.size() > JOURNAL_LIMIT: return ERR_OUT_OF_MEMORY
	var bytes := "SCDDCJ01".to_utf8_buffer()
	bytes.append_array(_digest(body).to_utf8_buffer())
	bytes.append_array(body)
	var error := _write_journal(bytes)
	if error == OK:
		_state = next
		_prune_payloads()
	return error

func _write_journal(bytes: PackedByteArray) -> Error:
	var staged := journal_path() + ".pending"
	var error := SaveFormat._write_replacement(staged, bytes)
	if error != OK: return error
	if _read_journal(staged, _directory, _owner, _payload_descriptors(_state)).is_empty(): return ERR_FILE_CORRUPT
	# Both files are siblings on one filesystem. On Apple platforms rename
	# atomically replaces the old journal; a completed staging file is recovery.
	return DirAccess.rename_absolute(staged, journal_path())

## Only publication supplies descriptors from its already validated prior state.
## Startup/recovery supplies none and checks every referenced asset's size and
## digest; format validation happened before the descriptor first existed.
func _read_journal(path: String, directory: String, owner: String, verified: Dictionary = {}) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var size := file.get_length()
	if size < 73 or size > JOURNAL_LIMIT + 72:
		file.close()
		return {}
	var bytes := file.get_buffer(size)
	file.close()
	if bytes.size() != size or bytes.slice(0, 8).get_string_from_utf8() != "SCDDCJ01": return {}
	var body := bytes.slice(72)
	if _digest(body) != bytes.slice(8, 72).get_string_from_utf8(): return {}
	var state: Variant = bytes_to_var(body)
	if not state is Dictionary or state.get("version") != JOURNAL_VERSION or state.get("owner") != owner: return {}
	if not state.get("revision") is int or state.revision < 1 or not state.get("slots") is Dictionary: return {}
	if not state.has("change_token"): state.change_token = PackedByteArray()
	if not state.change_token is PackedByteArray or state.change_token.size() > MAX_CHANGE_TOKEN_BYTES: return {}
	if state.has("application_recovery") and not state.application_recovery is Dictionary: return {}
	if state.has("application_recovery") and not state.application_recovery.is_empty():
		if not _valid_recovery(state.application_recovery, directory, owner, verified): return {}
	for id in state.slots:
		var slot: Variant = state.slots[id]
		if not CloudSaveTypes.valid_id(id) or not slot is Dictionary: return {}
		if slot.get("slot_id") != id or slot.get("owner") != owner: return {}
		if not slot.get("generation") is int or not slot.get("manual_path") is String: return {}
		if not CloudSaveTypes.valid_id(slot.get("manual_intent", ""), true): return {}
		if not CloudSaveTypes.valid_id(slot.get("commit_id"), true) or not slot.get("system_fields") is PackedByteArray: return {}
		if not slot.get("baseline_tag") is String or slot.baseline_tag.to_utf8_buffer().size() > CloudSaveTypes.MAX_ID_BYTES: return {}
		if not slot.get("tombstone") is bool or not slot.get("history") is Dictionary or not slot.get("pending") is Dictionary: return {}
		# Initial development journals had no uploads; they contain no dispatched
		# transport requests and are compacted on their next successful publication.
		if not slot.has("uploads"): slot.uploads = {}
		if not slot.uploads is Dictionary: return {}
		if not slot.has("forks"): slot.forks = {}
		if not slot.forks is Dictionary: return {}
		for generation in slot.forks:
			var fork: Variant = slot.forks[generation]
			if not generation is String or not generation.is_valid_int() or int(generation) < 1: return {}
			if not fork is Dictionary or not CloudSaveTypes.valid_id(fork.get("commit_id")) or not CloudSaveTypes.valid_id(fork.get("slot_id")): return {}
			if fork.slot_id == id or not state.slots.has(fork.slot_id): return {}
		for key in ["continuation", "manual"]:
			if not slot.get(key) is Dictionary: return {}
			if not slot[key].is_empty() and not _valid_stored_payload(slot[key], directory, verified): return {}
		if not slot.pending.is_empty() and not _valid_stored_pending(slot.pending, id, owner, directory, verified): return {}
		for work in slot.history.values():
			if not _valid_stored_pending(work, id, owner, directory, verified): return {}
		for key in slot.uploads:
			var work: Variant = slot.uploads[key]
			if not _valid_stored_pending(work, id, owner, directory, verified) or key != str(work.generation): return {}
	var recovery: Dictionary = state.get("application_recovery", {})
	if not recovery.is_empty():
		if not state.slots.has(recovery.work.slot_id) or recovery.work.generation > state.slots[recovery.work.slot_id].generation: return {}
	return state

func _valid_stored_pending(work: Variant, id: String, owner: String, directory: String, verified: Dictionary = {}) -> bool:
	if not CloudSaveTypes.valid_pending(work) or work.slot_id != id or work.owner != owner: return false
	if not work.tombstone and not _valid_stored_payload(work.continuation, directory, verified): return false
	return work.manual.is_empty() or _valid_stored_payload(work.manual, directory, verified)

func _valid_stored_payload(payload: Dictionary, directory: String, verified: Dictionary = {}) -> bool:
	if not CloudSaveTypes.valid_payload(payload): return false
	var path: String = payload.path
	if path.get_base_dir() != directory.path_join("payloads") or not path.ends_with(".sc2d"): return false
	if not CloudSaveTypes.valid_id(path.get_file().trim_suffix(".sc2d")): return false
	if verified.get(path, {}) == payload: return true
	# Payloads are immutable and fully validated before any descriptor can be
	# published; reopening checks that the referenced bytes are still those.
	if not payload_intact(payload): return false
	verified[path] = payload.duplicate(true)
	return true

func _payload_descriptors(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for slot in state.get("slots", {}).values():
		var entries: Array = [slot]
		entries.append_array(slot.history.values())
		entries.append_array(slot.uploads.values())
		if not slot.pending.is_empty(): entries.append(slot.pending)
		for entry in entries:
			for key in ["continuation", "manual"]:
				var payload: Dictionary = entry[key]
				if not payload.is_empty(): result[payload.path] = payload.duplicate(true)
	var recovery: Dictionary = state.get("application_recovery", {})
	if not recovery.is_empty():
		for field in ["continuation", "manual"]:
			var payload: Dictionary = recovery.work[field]
			if not payload.is_empty(): result[payload.path] = payload.duplicate(true)
	return result

func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _compact_history(state: Dictionary) -> void:
	for slot in state.slots.values():
		var retained: Dictionary = {}
		for key in slot.uploads: retained[key] = slot.uploads[key].duplicate(true)
		if not slot.pending.is_empty(): retained[str(slot.pending.generation)] = slot.pending.duplicate(true)
		slot.history = retained

func _collect_payload_paths(state: Dictionary) -> Dictionary:
	var paths: Dictionary = {}
	for slot in state.slots.values():
		for field in ["continuation", "manual"]:
			if not slot[field].is_empty(): paths[slot[field].path] = true
		var work_items: Array = slot.uploads.values()
		if not slot.pending.is_empty(): work_items.append(slot.pending)
		for work in work_items:
			for field in ["continuation", "manual"]:
				if not work.get(field, {}).is_empty(): paths[work[field].path] = true
	var recovery: Dictionary = state.get("application_recovery", {})
	if not recovery.is_empty():
		for field in ["continuation", "manual"]:
			if not recovery.work[field].is_empty(): paths[recovery.work[field].path] = true
	return paths

func _prune_payloads() -> void:
	# Called only after a verified journal has been published/recovered. A crash
	# during deletion can leave orphans, never remove a referenced payload.
	var keep := _collect_payload_paths(_state)
	var directory := _directory.path_join("payloads")
	var dir := DirAccess.open(directory)
	if dir == null: return
	# A lower/invalid staged journal must not be recovered after its assets are
	# retired. A successful publication already consumed the newer stage.
	var staged := journal_path() + ".pending"
	if FileAccess.file_exists(staged) and DirAccess.remove_absolute(staged) != OK: return
	for name in dir.get_files():
		if not _generated_payload_name(name): continue
		var path := directory.path_join(name)
		if not keep.has(path): DirAccess.remove_absolute(path)

func _generated_payload_name(name: String) -> bool:
	var id := name.trim_suffix(".pending").trim_suffix(".sc2d")
	if name != id + ".sc2d" and name != id + ".sc2d.pending": return false
	if id.length() != 36 or id[14] != "4" or not id[19] in "89ab": return false
	for index in id.length():
		if index in [8, 13, 18, 23]:
			if id[index] != "-": return false
		elif not id[index] in "0123456789abcdef": return false
	return true


## Optional display metadata is deliberately coarse; never persist a raw device
## name/model/identifier supplied by another record as player-facing copy.
static func coarse_device_label(value: Variant) -> String:
	return value if value is String and value in ["macOS", "iOS"] else ""

static func metadata_conflict_origin(value: Variant) -> String:
	if not value is String: return ""
	var pattern := RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	return value if pattern.search(value) != null else ""
