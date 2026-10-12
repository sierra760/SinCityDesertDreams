# SPDX-License-Identifier: GPL-3.0-or-later
class_name ExploreModRuntime
extends RefCounted
signal owner_disabled(owner: String, reason: String)
var tick_count := 0
var diagnostics: Array[Dictionary] = []
var logs: Array[Dictionary] = []
var _sessions: Dictionary = {}
var _commands: Array[Dictionary] = []
var _progress: ExploreModProgress
var _generation := 0
var _accumulator := 0.0
var _cursor := 0
var _suspended := false
var _active_time := 0.0
var _invalid: Dictionary = {}
var _last_tick: Dictionary = {}
var _owner_metrics: Dictionary = {}
var resource_counts: Dictionary = {}
var _transactions: Dictionary = {}
var _transaction_serial := 0

func metrics() -> Dictionary:
	var result := {"tick":_last_tick.duplicate(true),"owners":_owner_metrics.duplicate(true),"sessions":_sessions.size(),"pending_commands":_commands.size(),"resources":resource_counts.duplicate(true),"pending_transactions":0}
	# Closed owners retain diagnostic samples, not live allocation claims.
	for owner: String in result.owners:
		result.owners[owner]["sample_status"] = "live" if _sessions.has(owner) else "inactive_last_observed"
	for pending: Array in _transactions.values(): result["pending_transactions"] += pending.size()
	for owner: String in _sessions:
		if not result.owners.has(owner): result.owners[owner] = {}
		result.owners[owner]["events"] = _sessions[owner].events.size()
	return result

func invalid_command(owner: String, count: int = 1) -> void:
	if not _sessions.has(owner): return
	var times: Array = _invalid.get(owner,[])
	times = times.filter(func(value: float) -> bool: return value > _active_time-1.0)
	for i in mini(33,maxi(0,count)): times.append(_active_time)
	_invalid[owner] = times
	if times.size() > 32: _fault(owner,"invalid_command_limit")

func has_owner(owner: String) -> bool:
	return _sessions.has(owner)

func priority(owner: String) -> int:
	return int(_sessions[owner].manifest.priority) if _sessions.has(owner) else 0

func _create_vm() -> ExploreLuaBridge:
	return ExploreLuaBridge.new()

func bind(packs: Array[Dictionary], progress: ExploreModProgress, generation: int) -> void:
	stop("rebind")
	diagnostics.clear()
	logs.clear()
	_progress = progress
	_generation = generation
	_accumulator = 0
	tick_count = 0
	_active_time = 0
	_invalid.clear()
	_owner_metrics.clear()
	_last_tick.clear()
	for pack in ExploreModManifest.resolve_candidates(packs):
		if pack.get("ok",false): start_pack(pack)

## Start only an admitted owner; existing sessions and their scheduler state
## remain intact during explicit configuration changes.
func start_pack(pack: Dictionary) -> bool:
	if not pack.get("ok",false): return false
	var id: String = pack.manifest.id
	if _sessions.has(id): return false
	if _sessions.size() >= 8:
		_note(id,"session_limit")
		return false
	var manifest: Dictionary = pack.manifest
	var owner: String = manifest.id
	var state := _progress.get_state(owner,int(manifest.state_version))
	if not state.ok:
		_note(owner,state.code)
		return false
	var vm := _create_vm()
	var session := {"vm":vm,"manifest":manifest,"events":[],"queries":{},"resume":false,"handlers":[],"tick":false,"tick_delta":0.0}
	_sessions[owner] = session
	var modules: Dictionary = {}
	for path in pack.sources:
		if String(path).ends_with(".lua"): modules[String(path)] = pack.sources[path]
	var context := _context(owner,{"delta":0.0})
	var opened := vm.start(pack.sources[manifest.entry],modules,context,owner.hash())
	if not _accept(owner,opened,{"stage":"start","remaining_usec":1500,"context":context}): return false
	session["handlers"] = opened.get("handlers",[]).duplicate()
	# Entry/configuration owns initialization. Relative budgets cannot return
	# the bridge's absolute-deadline deferral, so on_start never runs later.
	if not session.handlers.has("on_start"): return true
	_accept(owner,vm.dispatch("on_start",{},context,{"instructions":20000,"remaining_usec":1500}),{"stage":"on_start","remaining_usec":1500,"context":context})
	return _sessions.has(owner)

func _context(owner: String, extra: Dictionary) -> Dictionary:
	var session: Dictionary = _sessions[owner]
	var result := extra.duplicate(true)
	result["owner"] = owner
	result["generation"] = _generation
	result["progress"] = _progress.get_state(owner,int(session.manifest.state_version)).data
	for transaction: Dictionary in _transactions.get(owner,[]):
		result["progress"].merge(transaction.writes.duplicate(true),true)
	result["queries"] = session.queries.duplicate(true)
	return result

func _note(owner: String, reason: String) -> void:
	var owned := 0
	for entry in diagnostics:
		if entry.owner == owner: owned += 1
	if owned >= 128:
		for index in diagnostics.size():
			if diagnostics[index].owner == owner:
				diagnostics.remove_at(index)
				break
	diagnostics.append({"owner":owner,"reason":reason,"time_usec":Time.get_ticks_usec()})

func _accept(owner: String, reply: Dictionary, invocation: Dictionary = {}) -> bool:
	if not reply.get("ok",false):
		_note(owner,String(reply.get("fault","unknown")))
		var diagnostic: Dictionary = diagnostics.back()
		diagnostic["diagnostic"] = ExploreLuaBridge.diagnostic_text(reply.get("diagnostic",""))
		diagnostic["stage"] = invocation.get("stage","")
		diagnostic["remaining_usec"] = invocation.get("remaining_usec",0)
		diagnostic["elapsed_usec"] = reply.get("elapsed_usec",0)
		diagnostic["instructions"] = reply.get("instructions",0)
		diagnostic["timing"] = reply.get("timing",{}).duplicate(true)
		diagnostic["context_bytes"] = JSON.stringify(invocation.get("context",{})).to_utf8_buffer().size()
		_fault(owner,String(reply.get("fault","unknown")))
		return false
	if not _sessions.has(owner): return false
	invalid_command(owner,int(reply.get("invalid_calls",0)))
	if not _sessions.has(owner): return false
	_owner_metrics[owner] = {"bytes_used":reply.get("bytes_used",0),"instructions":reply.get("instructions",0),"timing":reply.get("timing",{}).duplicate(true)}
	var count := 0
	for command in _commands:
		if command.owner == owner: count += 1
	if count+reply.commands.size() > 32:
		_fault(owner,"quota_exceeded")
		return false
	# Commands must pass synchronous host acceptance before their callback's
	# writes become durable. Ordered overlays preserve same-tick Lua reads.
	if reply.commands.is_empty() and not _transactions.has(owner):
		if not _commit_writes(owner,reply.progress_writes): return false
	else:
		_transaction_serial += 1
		var pending: Dictionary = {}
		for command: Dictionary in reply.commands: pending[command.request_id] = true
		var transactions: Array = _transactions.get(owner,[])
		transactions.append({"id":_transaction_serial,"pending":pending,"writes":reply.progress_writes.duplicate(true)})
		_transactions[owner] = transactions
		for command: Dictionary in reply.commands:
			var copied := command.duplicate(true)
			copied["_transaction"] = _transaction_serial
			_commands.append(copied)
	for message: String in reply.logs:
		var owned_logs := 0
		for entry in logs:
			if entry.owner == owner: owned_logs += 1
		if owned_logs >= 128:
			for index in logs.size():
				if logs[index].owner == owner:
					logs.remove_at(index)
					break
		logs.append({"owner":owner,"message":message})
	return true

func _commit_writes(owner: String, writes: Dictionary) -> bool:
	if writes.is_empty(): return true
	var session: Dictionary = _sessions[owner]
	var committed := _progress.commit(owner,int(session.manifest.state_version),String(session.manifest.version),writes)
	if committed.ok: return true
	_fault(owner,committed.code)
	return false

## Resolve only synchronous host acceptance. Pending engine actions are accepted
## here; a later ordinary completion failure never rolls back durable progress.
func accept_command(command: Dictionary, event: Dictionary) -> void:
	var owner: String = command.owner
	if not _sessions.has(owner): return
	if event.get("code","") in ["invalid_argument","wrong_owner"]:
		_note(owner,String(event.code))
		diagnostics.back()["command"] = String(command.kind)
		diagnostics.back()["request_id"] = int(command.request_id)
		invalid_command(owner)
		if not _sessions.has(owner): return
	var transactions: Array = _transactions.get(owner,[])
	for transaction: Dictionary in transactions:
		if transaction.id == command.get("_transaction",-1):
			transaction.pending.erase(command.request_id)
			break
	while not transactions.is_empty() and transactions[0].pending.is_empty():
		var transaction: Dictionary = transactions[0]
		if not _commit_writes(owner,transaction.writes): return
		transactions.pop_front()
	if transactions.is_empty(): _transactions.erase(owner)

func step(delta: float, suspended: bool, context: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if suspended:
		_suspended = true
		return output
	if _suspended:
		for session: Dictionary in _sessions.values(): session["resume"] = session.handlers.has("on_resume")
		_suspended = false
	_active_time += maxf(0,delta)
	_accumulator += maxf(0,delta)
	if _accumulator+.000001 < .1: return output
	var elapsed := floorf((_accumulator+.000001)/.1)*.1
	_accumulator = maxf(0,_accumulator-elapsed)
	tick_count += int(round(elapsed/.1))
	var begun := Time.get_ticks_usec()
	var deadline := begun+1500
	var instructions := 100000
	var callbacks := 0
	var preparation_usec := 0
	var native_usec := 0
	var accept_usec := 0
	# Unresolved host work from an earlier tick cannot accumulate another
	# tick of staged state: at most32 callback transactions, with32 pending
	# commands per owner, can remain outstanding.
	var awaiting_host := _transactions.keys()
	var owners := _sessions.keys()
	owners.sort()
	for session: Dictionary in _sessions.values():
		if session.handlers.has("on_tick"):
			session["tick"] = true
			session["tick_delta"] += elapsed
	# One callback per owner per round prevents an event-heavy owner from
	# consuming the entire callback budget before another gets a turn.
	var attempted := 0
	var event_counts: Dictionary = {}
	while not owners.is_empty() and callbacks < 32 and instructions > 0 and Time.get_ticks_usec() < deadline:
		var progressed := false
		for offset in owners.size():
			var owner: String = owners[(_cursor+offset)%owners.size()]
			if not _sessions.has(owner) or owner in awaiting_host: continue
			if callbacks >= 32 or instructions <= 0 or Time.get_ticks_usec() >= deadline: break
			var session: Dictionary = _sessions[owner]
			var handler := ""
			var payload: Dictionary = {}
			if session.resume: handler = "on_resume"
			elif not session.events.is_empty() and int(event_counts.get(owner,0)) < 3:
				handler = "on_event"
				payload = session.events[0]
			elif session.tick: handler = "on_tick"
			if handler.is_empty(): continue
			var prepared := Time.get_ticks_usec()
			var copied_context := _context(owner,context)
			copied_context["delta"] = session.tick_delta if handler == "on_tick" else elapsed
			preparation_usec += Time.get_ticks_usec()-prepared
			if Time.get_ticks_usec() >= deadline: break
			var remaining_usec := maxi(0,deadline-Time.get_ticks_usec())
			var dispatched := Time.get_ticks_usec()
			var reply: Dictionary = session.vm.dispatch(handler,payload,copied_context,{"instructions":mini(20000,instructions),"deadline_usec":deadline})
			native_usec += Time.get_ticks_usec()-dispatched
			attempted += 1
			if reply.get("deferred",false): break
			progressed = true
			if handler == "on_resume": session["resume"] = false
			if handler == "on_event":
				session.events.pop_front()
				event_counts[owner] = int(event_counts.get(owner,0))+1
			if handler == "on_tick":
				session["tick"] = false
				session["tick_delta"] = 0.0
			instructions -= int(reply.get("instructions",0))
			callbacks += 1
			var accepted := Time.get_ticks_usec()
			_accept(owner,reply,{"stage":handler,"remaining_usec":remaining_usec,"context":copied_context})
			accept_usec += Time.get_ticks_usec()-accepted
		if not progressed: break
	_cursor += 1
	var available := mini(64,_commands.size())
	for i in available: output.append(_commands.pop_front())
	_last_tick = {"callbacks":callbacks,"commands":available,"instructions":100000-instructions,"attempted":attempted,"preparation_usec":preparation_usec,"bridge_native_usec":native_usec,"accept_usec":accept_usec,"wall_usec":Time.get_ticks_usec()-begun}
	return output.filter(func(command: Dictionary) -> bool: return _sessions.has(command.owner))

func deliver(owner: String, event: Dictionary) -> void:
	if not _sessions.has(owner) or not _sessions[owner].handlers.has("on_event"): return
	if _sessions[owner].events.size() >= 128:
		_fault(owner,"event_queue_full")
		return
	_sessions[owner].events.append(event.duplicate(true))

func cache_query(owner: String, kind: String, args: Array, result: Dictionary) -> void:
	if not _sessions.has(owner) or kind in ["world.player","world.nearby","actor.inspect"]: return
	var cache: Dictionary = _sessions[owner].queries
	var entries: Array = cache.get(kind,[])
	if entries.size() >= 8: entries.pop_front()
	entries.append({"args":args.duplicate(true),"result":result.duplicate(true)})
	cache[kind] = entries
	if JSON.stringify(cache).to_utf8_buffer().size() > 60000: cache.clear()

func invalidate_queries() -> void:
	for session: Dictionary in _sessions.values(): session.queries.clear()

func _fault(owner: String, reason: String) -> void:
	if diagnostics.is_empty() or diagnostics.back().owner != owner or diagnostics.back().reason != reason: _note(owner,reason)
	_invalid.erase(owner)
	_transactions.erase(owner)
	if _sessions.has(owner): _sessions[owner].vm.close()
	_sessions.erase(owner)
	_commands = _commands.filter(func(command: Dictionary) -> bool: return command.owner != owner)
	owner_disabled.emit(owner,reason)

func disable(owner: String, reason: String) -> void:
	_transactions.erase(owner)
	if _sessions.has(owner):
		var session: Dictionary = _sessions[owner]
		if session.handlers.has("on_stop"):
			var reply: Dictionary = session.vm.dispatch("on_stop",{},_context(owner,{"reason":reason,"delta":0.0}),{"instructions":20000,"remaining_usec":1500})
			if reply.ok and not reply.get("deferred",false): _progress.commit(owner,int(session.manifest.state_version),String(session.manifest.version),reply.progress_writes)
	_fault(owner,reason)

func stop(reason: String) -> void:
	for owner: String in _sessions.keys(): disable(owner,reason)
	_commands.clear()
	_transactions.clear()
