# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
class_name CloudSavePolicy
extends RefCounted

## Accept a Pending, a store row containing `pending`, or a published library row.
## Empty remote means an authoritative missing record, never a failed fetch.
## Decisions allocate no identity and never mutate either input.
static func decide(local: Dictionary, remote: Dictionary) -> Dictionary:
	if not remote.is_empty() and not CloudSaveTypes.valid_remote(remote):
		return _decision("ignore", "invalid_remote")
	if local.is_empty():
		return _decision("ignore", "absent") if remote.is_empty() else _decision("download", "remote_only")
	var candidate: Variant = local.get("pending", local)
	if not candidate is Dictionary: return _decision("ignore", "invalid_local")
	var work: Dictionary = candidate
	if CloudSaveTypes.valid_pending(work):
		if remote.is_empty():
			return _decision("upload", "new_slot") if work.baseline_tag.is_empty() and work.parent_commit_id.is_empty() else _decision("fork", "remote_missing")
		if work.slot_id != remote.slot_id: return _decision("ignore", "different_slot")
		if same_content(work, remote):
			return _decision("acknowledge", "same_commit" if work.commit_id == remote.commit_id else "same_content")
		if work.commit_id == remote.commit_id: return _decision("fork", "commit_content_mismatch")
		if not work.baseline_tag.is_empty() and work.baseline_tag == remote.change_tag:
			return _decision("upload", "unchanged_parent") if work.parent_commit_id == remote.commit_id else _decision("ignore", "await_parent")
		return _decision("fork", "divergent_parent")
	# A published row has no pending work. Its archive bytes and display metadata
	# are deliberately irrelevant to equality; a changed remote is downloaded.
	if local.get("sync_state", "") in ["pending", "conflict"]:
		return _decision("ignore", "pending_requires_snapshot")
	if not CloudSaveTypes.valid_id(local.get("slot_id")):
		return _decision("ignore", "invalid_local")
	if remote.is_empty(): return _decision("ignore", "no_remote")
	if local.slot_id != remote.slot_id: return _decision("ignore", "different_slot")
	if local.get("commit_id", "") == remote.commit_id and local.get("baseline_tag", "") == remote.change_tag:
		return _decision("ignore", "current")
	return _decision("download", "remote_changed")

static func same_content(work: Dictionary, remote: Dictionary) -> bool:
	return CloudSaveTypes.valid_pending(work) and CloudSaveTypes.valid_remote(remote) \
		and work.tombstone == remote.tombstone \
		and work.get("continuation", {}).get("sha256", "") == remote.continuation_sha256 \
		and work.manual.get("sha256", "") == remote.manual_sha256

static func _decision(action: String, reason: String) -> Dictionary:
	return {"action": action, "reason": reason}
