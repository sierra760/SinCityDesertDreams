# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends RefCounted
## One durable-in-memory service shared by independent synthetic device endpoints.
## Only explicit step() calls service requests; start_request never does work.
const EndpointBase := preload("res://tests/helpers/fake_apple_cloud.gd")
class Endpoint extends EndpointBase:
	var owner := "synthetic-account"
	var online := true
	var hold := ""
	var cursor := 0
	var lose_next_save_ack := false
	var corrupt_next_download := false
	var submitted_owners: Dictionary = {}
	func start_request(request: Dictionary) -> Error:
		var error := super.start_request(request)
		if error == OK: submitted_owners[request.id] = owner
		return error
	func cancel_all() -> void:
		super.cancel_all()
		# Retain produced completions so tests can deliver stale native callbacks.
		cursor = requests.size()
var accounts: Dictionary = {}
var endpoints: Array[Endpoint] = []
var directory: String
var revision := 0
func _init(path: String) -> void:
	directory = path
	DirAccess.make_dir_recursive_absolute(directory)
func endpoint() -> Endpoint:
	var result := Endpoint.new()
	endpoints.append(result)
	return result
func records(owner: String = "synthetic-account") -> Dictionary:
	if not accounts.has(owner): accounts[owner] = {}
	return accounts[owner]
func step() -> void:
	for endpoint_value in endpoints:
		if not endpoint_value.online: continue
		while endpoint_value.cursor < endpoint_value.requests.size():
			var request: Dictionary = endpoint_value.requests[endpoint_value.cursor]
			if request.op == endpoint_value.hold: break
			endpoint_value.cursor += 1
			_serve(endpoint_value, request)
func _serve(client: Endpoint, request: Dictionary) -> void:
	var submitted_owner: String = client.submitted_owners[request.id]
	var database := records(submitted_owner)
	match request.op:
		"account": client.finish(request, {"owner":submitted_owner})
		"prepare_zone": client.finish(request)
		"changes":
			var inventory: Array = []
			for entry in database.values(): inventory.append(entry.remote.duplicate(true))
			client.finish(request, {"records":inventory, "deleted_ids":[], "token":str(revision).to_utf8_buffer(), "more":false})
		"fetch_record": client.finish(request, {"remote":database.get(request.args.slot_id, {}).get("remote", {}).duplicate(true)})
		"save":
			var pending: Dictionary = request.args.pending
			var current: Dictionary = database.get(pending.slot_id, {})
			if (current.is_empty() and not pending.baseline_tag.is_empty()) or (not current.is_empty() and current.remote.change_tag != pending.baseline_tag):
				client.finish(request, {"remote":current.get("remote", {})}, "conflict")
				return
			revision += 1
			var assets: Dictionary = {}
			for kind in ["continuation", "manual"]:
				var descriptor: Dictionary = pending[kind]
				if not descriptor.is_empty():
					var path := directory.path_join(str(revision) + "-" + kind + ".sc2d")
					DirAccess.copy_absolute(descriptor.path, path)
					assets[kind] = path
			var remote := {"slot_id":pending.slot_id, "commit_id":pending.commit_id, "change_tag":str(revision), "system_fields":str(revision).to_utf8_buffer(), "continuation_sha256":pending.continuation.get("sha256", ""), "manual_sha256":pending.manual.get("sha256", ""), "tombstone":pending.tombstone, "metadata":request.args.metadata.duplicate(true)}
			database[pending.slot_id] = {"remote":remote, "assets":assets}
			if client.lose_next_save_ack:
				client.lose_next_save_ack = false
				return
			client.finish(request, {"commit_id":remote.commit_id, "change_tag":remote.change_tag, "system_fields":remote.system_fields})
		"download":
			var expected: Dictionary = request.args.remote
			var current: Dictionary = database.get(expected.slot_id, {})
			if current.is_empty() or current.remote.change_tag != expected.change_tag:
				client.finish(request, {"remote":current.get("remote", {})}, "conflict")
				return
			var downloaded: Dictionary = current.assets.duplicate(true)
			if client.corrupt_next_download:
				client.corrupt_next_download = false
				var damaged := directory.path_join("damaged.sc2d")
				var file := FileAccess.open(damaged, FileAccess.WRITE)
				file.store_string("damaged synthetic download")
				file.close()
				downloaded.continuation = damaged
			client.finish(request, {"downloaded":downloaded})
