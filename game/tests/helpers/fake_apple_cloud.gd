# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends RefCounted
## Scripted transport only. No account, network, or player-file access.
var requests: Array[Dictionary] = []
var completions: Array[Dictionary] = []
var start_error: Error = OK
var supported := true
var cancellations := 0
func available() -> bool: return supported
func start_request(request: Dictionary) -> Error:
	if start_error != OK: return start_error
	requests.append(request.duplicate(true))
	return OK
func drain_completions() -> Array[Dictionary]:
	var result := completions
	completions = []
	return result
func cancel_all() -> void: cancellations += 1
func last(op: String) -> Dictionary:
	for i in range(requests.size() - 1, -1, -1):
		if requests[i].op == op: return requests[i]
	return {}
func count(op: String) -> int:
	var found := 0
	for request in requests:
		if request.op == op: found += 1
	return found
func finish(request: Dictionary, result: Dictionary = {}, code: String = "", retry_after_ms: int = 0) -> void:
	completions.append({"id": request.id, "epoch": request.epoch, "op": request.op,
		"ok": code.is_empty(), "code": code, "result": result, "retry_after_ms": retry_after_ms})
func account_changed(epoch: int) -> void:
	completions.append({"id": "", "epoch": epoch, "op": "account_changed", "ok": true,
		"code": "", "result": {}, "retry_after_ms": 0})
