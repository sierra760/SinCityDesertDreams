# SPDX-License-Identifier: GPL-3.0-or-later
class_name ExploreActorRegistry
extends RefCounted
var controller: CityExplorationController
var traffic: CityTraffic3D
var generation := 0
var queries: ExploreWorldQueries
var _actors: Dictionary = {}
var _serial := 0
var _detached: Dictionary = {}
var _events: Array[Dictionary] = []
const NEARBY_PEDESTRIAN_STEPS := 4
const NEARBY_PEDESTRIAN_NODES := 32

func bind(value: CityExplorationController, layer: CityTraffic3D, session_generation: int) -> void:
	controller = value
	traffic = layer
	generation = session_generation
	_actors.clear()
	_detached.clear()

static func completion(command: Dictionary, code: String, data: Variant = {}) -> Dictionary:
	var args: Dictionary = command.get("args",{}) if command.get("args",{}) is Dictionary else {}
	var options: Dictionary = args.get("options",{}) if args.get("options",{}) is Dictionary else {}
	var key: Variant = args.get("key",options.get("key",""))
	return {"owner":String(command.get("owner","")),"kind":"action_completed" if code == "ok" else "action_failed","request_id":command.get("request_id",0),"key":key if key is String else "","code":code,"data":data}

func apply(command: Dictionary) -> Dictionary:
	if command.get("generation",-1) != generation: return completion(command,"stale_generation")
	var owner: String = command.get("owner","")
	var args: Dictionary = command.get("args",{})
	var kind: String = command.get("kind","")
	if kind == "actor.spawn": return _spawn(command)
	var id: String = args.get("id","")
	if _detached.has(id):
		if _detached[id].owner != owner: return completion(command,"wrong_owner")
		return completion(command,"player_controlled" if traffic._claims.has(_detached[id].record.id) else "stale_id")
	if not _actors.has(id): return completion(command,"stale_id")
	var actor: Dictionary = _actors[id]
	if actor.owner != owner: return completion(command,"wrong_owner")
	var record: Dictionary = actor.record
	if not traffic.actors.has(record): return completion(command,"stale_id")
	if traffic._claims.has(record.id):
		if kind == "actor.remove": actor["remove_on_exit"] = true
		return completion(command,"player_controlled")
	match kind:
		"actor.inspect": return completion(command,"ok",_observation(id,actor))
		"actor.wave":
			if record.kind != &"pedestrian": return completion(command,"unavailable")
			_events.append_array(_cancel(actor))
			record["mod_hold"] = true
			record["stopped"] = true
			record["visual_gesture"] = "wave"
			record["visual_gesture_time"] = 0.0
			actor["gesture_command"] = command.duplicate(true)
			return {}
		"actor.remove":
			_events.append_array(_cancel(actor))
			traffic.owned_remove(record.id)
			_actors.erase(id)
			return completion(command,"ok")
		"actor.wait":
			var duration: float = args.get("duration",-1)
			if not is_finite(duration) or duration < .1 or duration > 86400: return completion(command,"invalid_argument")
			_events.append_array(_cancel(actor))
			record["mod_hold"] = true
			record["stopped"] = true
			actor["wait"] = duration
			actor["waiting_command"] = command.duplicate(true)
			actor.erase("query_id")
			actor.erase("navigation_command")
			return {}
		"actor.navigate":
			var destination := ExploreWorldQueries.point(args.get("destination"))
			if not destination.is_finite(): return completion(command,"invalid_argument")
			if record.domain == &"air": return _navigate_air(command,actor,destination)
			var next_domain := traffic.graph.continuation_domain(record.cell,record.next,record.domain)
			var start := queries.route_point(record.next,record.kind,next_domain)
			var result := queries.request(owner,"world.route",{"from":ExploreWorldQueries.copied_point(start,traffic.graph.revision),"destination":args.destination,"_kind":String(record.kind),"_domain":String(next_domain),"_previous":ExploreWorldQueries.copied_point(queries.route_point(record.cell,record.kind,record.domain),traffic.graph.revision),"_lane":1 if traffic.graph.is_ramp(record.cell) and next_domain == &"highway" else record.lane})
			if result.code != "pending": return completion(command,result.code)
			_events.append_array(_cancel(actor))
			record["mod_hold"] = true
			actor["query_id"] = result.query_id
			actor["navigation_command"] = command.duplicate(true)
			actor.erase("wait")
			return {}
	return completion(command,"unavailable")

func _spawn(command: Dictionary) -> Dictionary:
	var owner: String = command.owner
	var args: Dictionary = command.args
	var options: Dictionary = args.get("options",{})
	var kind := StringName(args.get("kind",""))
	if kind != &"pedestrian" and not CityTrafficCatalog.is_vehicle_kind(kind): return completion(command,"invalid_argument")
	var count := 0
	for actor in _actors.values():
		if actor.owner == owner:
			count += 1
			if actor.key == options.get("key",""): return completion(command,"duplicate_key")
	if count >= 16 or _actors.size() >= 64: return completion(command,"quota_exceeded")
	var shared_count := 0
	for record in traffic.actors:
		if (record.type == &"pedestrian") == (kind == &"pedestrian"): shared_count += 1
	if shared_count >= (512 if kind == &"pedestrian" else 384): return completion(command,"quota_exceeded")
	var position := ExploreWorldQueries.point(options.get("position",queries.player))
	if not position.is_finite(): return completion(command,"no_route")
	var cell := Vector2i(floori(position.x),floori(position.z))
	var domain := CityTrafficCatalog.domain(kind)
	if bool(options.get("enterable",false)) and not CityTrafficCatalog.is_drivable(kind): return completion(command,"invalid_argument")
	var variant: Variant = options.get("variant",0)
	if variant is String:
		if not variant.begins_with("pedestrian_") or not variant.trim_prefix("pedestrian_").is_valid_int(): return completion(command,"invalid_argument")
		variant = variant.trim_prefix("pedestrian_").to_int()
	if not variant is int or variant < 0 or variant >= 16: return completion(command,"invalid_argument")
	var record: Dictionary = {}
	if kind == &"pedestrian" and bool(options.get("near_player",false)):
		var admitted := _nearby_pedestrian(owner,cell,position,variant)
		if admitted.code != "ok": return completion(command,admitted.code)
		record = admitted.record
	if bool(options.get("enterable",false)):
		if not CityTrafficCatalog.is_drivable(kind): return completion(command,"invalid_argument")
		if domain == &"road" and is_instance_valid(controller):
			var found := false
			for offset: Vector2i in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.LEFT,Vector2i(2,0),Vector2i(-2,0),Vector2i.UP,Vector2i.DOWN]:
				if queries.nodes_visited_in_one_step >= 256: return completion(command,"quota_exceeded")
				queries.nodes_visited_in_one_step += 1
				var candidate := cell+offset
				if not queries.supported(candidate,kind,domain): continue
				var at := queries.route_point(candidate,kind,domain)
				if not controller._parking_clears_actors(Transform3D(Basis.IDENTITY,at),1): continue
				cell = candidate
				position = at
				found = true
				break
			if not found: return completion(command,"no_route")
	if record.is_empty():
		if domain != &"air" and not queries.supported(cell,kind,domain): return completion(command,"no_route")
		if domain != &"air" and absf(queries.route_point(cell,kind,domain).y-position.y) > .15: return completion(command,"no_route")
		record = traffic.owned_spawn(owner,kind,cell,variant,position,queries.traversal)
	if record.is_empty(): return completion(command,"no_route")
	_serial += 1
	var id := "mod:%d:%s:%d" % [generation,owner,_serial]
	record["mod_handle"] = id
	record["mod_enterable"] = bool(options.get("enterable",false))
	_actors[id] = {"owner":owner,"key":String(options.get("key","")),"record":record,"revision":traffic.graph.revision}
	return completion(command,"ok",{"id":id,"position":ExploreWorldQueries.copied_point(traffic.actor_pose(record).origin,traffic.graph.revision)})

func _nearby_pedestrian(owner: String, anchor: Vector2i, position: Vector3, variant: int) -> Dictionary:
	# Traverse only supported graph connections. Occupied cells remain traversable;
	# owned_spawn retains the shared following-distance guard at each admission.
	var frontier: Array[Dictionary] = [{"cell":anchor,"depth":0}]
	var seen := {anchor:true}
	var head := 0
	while head < frontier.size() and head < NEARBY_PEDESTRIAN_NODES:
		if queries.nodes_visited_in_one_step >= 256: return {"code":"quota_exceeded"}
		queries.nodes_visited_in_one_step += 1
		var node: Dictionary = frontier[head]
		head += 1
		var cell: Vector2i = node.cell
		if not queries.supported(cell): continue
		var feet := queries.route_point(cell,&"pedestrian",&"road")
		if node.depth == 0 and absf(feet.y-position.y) > .15: return {"code":"no_route"}
		var record := traffic.owned_spawn(owner,&"pedestrian",cell,variant,feet,queries.traversal)
		if not record.is_empty():
			# A turn's real standing pose can differ from the canonical route point.
			# Refuse that provisional owned record if its actual feet lack support.
			var actual := traffic.actor_pose(record).origin
			if queries.traversal == null or (not queries.traversal.support_near(actual,.06,.06,[]).is_empty() and not queries.traversal.touches_water(actual)):
				return {"code":"ok","record":record}
			traffic.owned_remove(record.id)
		if node.depth >= NEARBY_PEDESTRIAN_STEPS: continue
		for next: Vector2i in traffic.graph.neighbors(cell,&"road"):
			if seen.has(next) or frontier.size() >= NEARBY_PEDESTRIAN_NODES: continue
			seen[next] = true
			frontier.append({"cell":next,"depth":int(node.depth)+1})
	return {"code":"no_route"}

func accept_query(result: Dictionary) -> bool:
	for actor: Dictionary in _actors.values():
		if actor.get("query_id",-1) != result.query_id: continue
		actor.erase("query_id")
		var record: Dictionary = actor.record
		if record.domain == &"air" and result.code == "ok" and result.has("_air_destination"):
			record["air_destination"] = result._air_destination
			record["air_revision"] = result._world_revision
			record["mod_arrived"] = false
			record["mod_failed"] = false
			record["mod_hold"] = false
		elif result.code != "ok" or result.get("_cells",[]).is_empty(): actor["failure"] = String(result.code)
		else:
			record["mod_route"] = result._cells
			record["mod_destination"] = result._cells.back()
			record["mod_route_index"] = 0
			record["mod_arrived"] = false
			record["mod_failed"] = false
			record["mod_hold"] = false
			actor["revision"] = traffic.graph.revision
		return true
	return false

func _cancel(actor: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for key in ["navigation_command","waiting_command","gesture_command"]:
		if actor.has(key):
			events.append(completion(actor[key],"cancelled"))
			actor.erase(key)
	actor.record.erase("visual_gesture")
	actor.record.erase("visual_gesture_time")
	actor.erase("wait")
	actor.erase("query_id")
	return events

func _hold_after_takeover(record: Dictionary) -> void:
	# Cancellation must invalidate engine navigation as well as request bookkeeping.
	# Releasing the player's claim cannot revive a route from stale placement.
	record["mod_hold"] = true
	record["stopped"] = true
	record["mod_route"] = []
	record["mod_destination"] = CityTrafficGraph.INVALID
	record["mod_route_index"] = 0
	record["mod_arrived"] = false
	record["mod_failed"] = false

func step(delta: float) -> Array[Dictionary]:
	for id: String in _detached.keys():
		if not traffic._claims.has(_detached[id].record.id): release_detached()
	var events: Array[Dictionary] = _events
	_events = []
	for id: String in _actors.keys():
		var actor: Dictionary = _actors[id]
		var record: Dictionary = actor.record
		if traffic._claims.has(record.id):
			_hold_after_takeover(record)
			events.append_array(_cancel(actor))
			continue
		if actor.get("remove_on_exit",false):
			events.append_array(_cancel(actor))
			traffic.owned_remove(record.id)
			_actors.erase(id)
			continue
		if not traffic.actors.has(record) or actor.revision != traffic.graph.revision or (record.domain == &"air" and (not is_instance_valid(queries.traversal) or record.air_revision != queries.traversal.revision)):
			record["mod_hold"] = true
			record["stopped"] = true
			actor["failure"] = "route_failed"
			actor["revision"] = traffic.graph.revision
			actor.erase("query_id")
			events.append({"owner":String(actor.owner),"kind":"route_failed","request_id":0,"code":"stale_geometry","data":{"id":id}})
			if record.domain == &"air" or not traffic.actors.has(record) or not queries.supported(record.cell,record.kind,record.domain) or not traffic._choice_continues(record.cell,record.domain,record.previous,record.lane,record.next):
				events.append_array(_cancel(actor))
				traffic.owned_remove(record.id)
				_actors.erase(id)
				continue
		if actor.has("gesture_command"):
			record["visual_gesture_time"] = minf(1.5,float(record.get("visual_gesture_time",0.0))+maxf(0.0,delta))
			if record.visual_gesture_time>=1.5:
				events.append(completion(actor.gesture_command,"ok",{"id":id}))
				actor.erase("gesture_command")
				record.erase("visual_gesture")
				record.erase("visual_gesture_time")
		if actor.has("wait"):
			actor["wait"] = maxf(0,float(actor.wait)-delta)
			if actor.wait == 0:
				events.append(completion(actor.waiting_command,"ok",{"id":id}))
				actor.erase("wait")
				actor.erase("waiting_command")
		if actor.has("failure") or record.get("mod_failed",false) or record.get("mod_arrived",false):
			if actor.has("navigation_command"):
				events.append(completion(actor.navigation_command,String(actor.get("failure","no_route" if record.get("mod_failed",false) else "ok")),{"id":id}))
				actor.erase("navigation_command")
			actor.erase("failure")
			record["mod_arrived"] = false
	traffic.advance_owned(delta)
	return events

func detach_occupied(owner: String) -> void:
	for id: String in _actors.keys():
		var actor: Dictionary = _actors[id]
		if actor.owner != owner or not traffic._claims.has(actor.record.id): continue
		_hold_after_takeover(actor.record)
		_events.append_array(_cancel(actor))
		actor.record.erase("mod_owner")
		actor.record.erase("mod_handle")
		actor.record.erase("mod_enterable")
		_detached.clear() # Only one player claim may transfer into session ownership.
		_detached[id] = actor
		_actors.erase(id)

func clear_owner(owner: String) -> void:
	detach_occupied(owner)
	for id: String in _actors.keys():
		if _actors[id].owner == owner:
			var record: Dictionary = _actors[id].record
			if traffic._claims.has(record.id):
				# A claimed vehicle transfers to the session for a safe exit.
				record.erase("mod_owner")
				record.erase("mod_handle")
			traffic.owned_remove(record.id)
			_actors.erase(id)
	_events = _events.filter(func(event: Dictionary) -> bool: return event.owner != owner)
	if queries != null: queries.clear_owner(owner)

func _observation(id: String, actor: Dictionary) -> Dictionary:
	var pose := traffic.actor_pose(actor.record)
	return {"id":id,"kind":String(actor.record.kind),"position":ExploreWorldQueries.copied_point(pose.origin,traffic.graph.revision),"speed":0.0 if actor.record.stopped else float(actor.record.speed)}

func visual_states() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _actors:
		var actor: Dictionary = _actors[id].record
		if not traffic.actors.has(actor) or traffic._claims.has(actor.id): continue
		var pose := traffic.actor_pose(actor)
		result.append({"id":id,"kind":String(actor.kind),"variant":actor.variant,"position":pose.origin,"yaw":pose.basis.get_euler().y,"speed":0.0 if actor.stopped else float(actor.speed),"steering":0.0,"airborne":actor.domain == &"air","phase":float(actor.mod_phase),"gesture":String(actor.get("visual_gesture","")),"gesture_time":float(actor.get("visual_gesture_time",0.0))})
	return result

func _navigate_air(command: Dictionary, actor: Dictionary, destination: Vector3) -> Dictionary:
	var record: Dictionary = actor.record
	var result := queries.request(String(actor.owner),"world.route",{"from":ExploreWorldQueries.copied_point(traffic.actor_pose(record).origin,traffic.graph.revision),"destination":ExploreWorldQueries.copied_point(destination,traffic.graph.revision),"_kind":String(record.kind),"_domain":"air"})
	if result.code != "pending": return completion(command,result.code)
	_events.append_array(_cancel(actor))
	record["mod_hold"] = true
	record["stopped"] = true
	actor["query_id"] = result.query_id
	actor["navigation_command"] = command.duplicate(true)
	return {}

func release_detached() -> void:
	for id: String in _detached.keys():
		var record: Dictionary = _detached[id].record
		if traffic._claims.has(record.id): continue
		record["mod_owner"] = "session"
		traffic.owned_remove(record.id)
		_detached.erase(id)
