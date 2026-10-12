# SPDX-License-Identifier: GPL-3.0-or-later
class_name ExploreModApi
extends RefCounted
var environment := ExploreEnvironmentService.new()
var runtime: ExploreModRuntime
var actors: ExploreActorRegistry
var interactions := ExploreModInteractions.new()
var objectives := ExploreModObjectives.new()
var markers := ExploreModMarkers.new()
var queries: ExploreWorldQueries
var generation := 0
var _pending: Dictionary = {}
var _timers: Dictionary = {}
var _outstanding: Dictionary = {}

func apply(command: Dictionary) -> Dictionary:
	if command.get("generation",-1) != generation: return ExploreActorRegistry.completion(command,"stale_generation")
	var kind: String = command.get("kind","")
	var owner: String = command.get("owner","")
	var args: Dictionary = command.get("args",{})
	if not valid_arguments(kind,args): return ExploreActorRegistry.completion(command,"invalid_argument")
	var outstanding: Dictionary = _outstanding.get(owner,{})
	if outstanding.size() >= 32: return ExploreActorRegistry.completion(command,"quota_exceeded")
	if kind.begins_with("interaction.") or kind.begins_with("dialogue.") or kind.begins_with("objective.") or kind.begins_with("marker."):
		var result: Dictionary
		match kind:
			"interaction.register":
				var options: Dictionary = args.get("options",{})
				result = interactions.register(owner,args.key,options.get("target",{}),options.get("label",""))
			"interaction.unregister": result = interactions.unregister(owner,args.key)
			"dialogue.show": result = interactions.dialogue(owner,args.key,args.speaker,args.text,args.choices)
			"dialogue.dismiss": result = interactions.dismiss_owned(owner,args.key)
			"objective.set": result = objectives.set_objective(owner,args.key,args.text,args.status)
			"objective.remove": result = objectives.remove(owner,args.key)
			"marker.set":
				markers.actors = actors
				result = markers.set_marker(owner,args.key,args.options)
			"marker.remove": result = markers.remove(owner,args.key)
			_: result = {"code":"unavailable"}
		return ExploreActorRegistry.completion(command,result.code)
	if kind == "environment.clear":
		environment.clear_owner(owner)
		return ExploreActorRegistry.completion(command,"ok")
	if kind == "environment.set":
		var result := environment.apply(owner,runtime.priority(owner) if runtime != null else 0,args.channel,args.preset,args.parameters)
		return ExploreActorRegistry.completion(command,result.code)
	if kind.begins_with("actor."):
		var event := actors.apply(command)
		if event.is_empty():
			outstanding[command.get("request_id",0)] = true
			_outstanding[owner] = outstanding
		elif kind == "actor.inspect": event["kind"] = "query_completed"
		return event
	if kind.begins_with("world."):
		var result := queries.request(owner,kind,args)
		if result.code == "pending":
			_pending[result.query_id] = command.duplicate(true)
			outstanding[command.get("request_id",0)] = true
			_outstanding[owner] = outstanding
			return {}
		var event := ExploreActorRegistry.completion(command,String(result.code),result.get("data",{}))
		event["kind"] = "query_completed"
		return event
	if kind == "timer.after" or kind == "timer.cancel":
		var key: String = args.get("key","")
		var timers: Dictionary = _timers.get(owner,{})
		if kind == "timer.cancel": timers.erase(key)
		else:
			var delay: float = args.get("delay",-1)
			if not is_finite(delay) or delay < .1 or delay > 86400: return ExploreActorRegistry.completion(command,"invalid_argument")
			if timers.size() >= 16 and not timers.has(key): return ExploreActorRegistry.completion(command,"quota_exceeded")
			timers[key] = {"left":delay,"request_id":command.get("request_id",0)}
		_timers[owner] = timers
		return ExploreActorRegistry.completion(command,"ok")
	return ExploreActorRegistry.completion(command,"unavailable")

func step(delta: float, runtime: ExploreModRuntime) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for result in queries.step():
		if actors.accept_query(result): continue
		if not _pending.has(result.query_id): continue
		var command: Dictionary = _pending[result.query_id]
		_pending.erase(result.query_id)
		var event := ExploreActorRegistry.completion(command,String(result.code),result.get("data",{}))
		event["kind"] = "query_completed"
		events.append(event)
		var positional: Array = []
		if command.kind == "world.find_landmark": positional.append(command.args.kind)
		elif command.kind == "world.route": positional.assign([command.args.from,command.args.destination])
		if command.args.has("options"): positional.append(command.args.options)
		runtime.cache_query(command.owner,command.kind,positional,{"ok":result.ok,"code":result.code,"data":result.get("data",{})})
	for owner: String in _timers:
		var timers: Dictionary = _timers[owner]
		for key: String in timers.keys():
			timers[key]["left"] = maxf(0,float(timers[key].left)-delta)
			if timers[key].left == 0:
				events.append({"owner":owner,"kind":"timer","key":key,"request_id":timers[key].request_id,"code":"ok","data":{}})
				timers.erase(key)
	return events

func complete(event: Dictionary) -> void:
	if _outstanding.has(event.owner): _outstanding[event.owner].erase(event.get("request_id",0))

func clear_owner(owner: String) -> void:
	_outstanding.erase(owner)
	_timers.erase(owner)
	for id in _pending.keys():
		if _pending[id].owner == owner: _pending.erase(id)
	environment.clear_owner(owner)
	interactions.clear_owner(owner)
	objectives.clear_owner(owner)
	markers.clear_owner(owner)
	actors.clear_owner(owner)

## Native enforces copied-data bounds; semantic argument types stay at the host
## boundary before any typed actor/query adapter reads script-selected options.
static func valid_arguments(kind: String, args: Dictionary) -> bool:
	if kind == "environment.set" and (not args.get("channel") is String or not args.get("preset") is String or not args.get("parameters") is Dictionary): return false
	if args.has("options") and not args.options is Dictionary: return false
	var options: Dictionary = args.get("options",{})
	if options.has("enterable") and not options.enterable is bool: return false
	if kind.begins_with("interaction.") or kind.begins_with("dialogue.") or kind.begins_with("objective.") or kind.begins_with("marker."):
		if not args.get("key") is String: return false
	if kind == "interaction.register" and (not options.get("target") is Dictionary or not options.get("label") is String): return false
	if kind == "dialogue.show" and (not args.get("speaker") is String or not args.get("text") is String or not args.get("choices") is Array): return false
	if kind == "marker.set" and (not args.get("options") is Dictionary or not ExploreModMarkers.valid_options(args.options)): return false
	if kind == "objective.set" and (not args.get("text") is String or not args.get("status") is String): return false
	for field in ["kind","key"]:
		if options.has(field) and not options[field] is String: return false
	if options.has("near_player") and not options.near_player is bool: return false
	if options.has("position") and not ExploreWorldQueries.point(options.position).is_finite(): return false
	if options.has("radius") and (not _number(options.radius) or options.radius < 0 or options.radius > 64): return false
	for field in ["from","away_from"]:
		if options.has(field) and not ExploreWorldQueries.point(options[field]).is_finite(): return false
	if options.has("min_distance") and (not _number(options.min_distance) or options.min_distance < 0 or options.min_distance > 40): return false
	if options.has("skip") and (not options.skip is int or options.skip < 0 or options.skip > 32): return false
	if kind in ["actor.spawn","world.find_landmark"] and not args.get("kind") is String: return false
	if kind.begins_with("actor.") and kind != "actor.spawn" and not args.get("id") is String: return false
	if kind in ["actor.navigate","world.route"] and not ExploreWorldQueries.point(args.get("destination")).is_finite(): return false
	if kind == "world.route" and not ExploreWorldQueries.point(args.get("from")).is_finite(): return false
	if kind == "actor.wait" and (not _number(args.get("duration")) or args.duration < .1 or args.duration > 86400): return false
	if kind.begins_with("timer.") and not args.get("key") is String: return false
	if kind == "timer.after" and (not _number(args.get("delay")) or args.delay < .1 or args.delay > 86400): return false
	return true

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

## Host-only copied accounting; no engine handles enter runtime diagnostics.
func resource_metrics() -> Dictionary:
	var result := {"actors":actors._actors.size() if actors != null else 0,"timers":0,"interactions":0,"objectives":0,"markers":markers.count(),"queries":_pending.size(),"particles":0,"environment_owners":environment._overrides.size()}
	for entries: Dictionary in _timers.values(): result["timers"] += entries.size()
	for entries: Dictionary in interactions._owned.values(): result["interactions"] += entries.size()
	for entries: Dictionary in objectives._owned.values(): result["objectives"] += entries.size()
	if is_instance_valid(environment._particles): result["particles"] = environment._particles.multimesh.instance_count
	return result
