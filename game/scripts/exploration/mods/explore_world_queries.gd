# SPDX-License-Identifier: GPL-3.0-or-later
class_name ExploreWorldQueries
extends RefCounted
var graph: CityTrafficGraph
var traversal: CityTraversalWorld3D
var traffic: CityTraffic3D
var player: Dictionary = {}
var observations: Array[Dictionary] = []
var reserved_rail: Dictionary = {}
var nodes_visited_in_one_step := 0
var _queue: Array[Dictionary] = []
var _cache: Dictionary = {}
var _serial := 0
var _revision := -1

func bind(value: CityTrafficGraph, world: CityTraversalWorld3D) -> void:
	graph = value
	traversal = world
	_queue.clear()
	_cache.clear()
	_revision = graph.revision if graph != null else -1

static func point(value: Variant) -> Vector3:
	if not value is Dictionary: return Vector3(INF,INF,INF)
	for key in ["x","y","z"]:
		if not (value.get(key) is float or value.get(key) is int): return Vector3(INF,INF,INF)
	return Vector3(value.x,value.y,value.z)

static func copied_point(value: Vector3, revision: int) -> Dictionary:
	return {"x":value.x,"y":value.y,"z":value.z,"coordinate_space":"tile","geometry_revision":revision}

func supported(cell: Vector2i, kind: StringName = &"pedestrian", domain: StringName = &"road") -> bool:
	if graph == null or not graph.has_cell(cell,domain) or (kind == &"pedestrian" and not graph.allows_pedestrians(cell)): return false
	if domain == &"rail" and reserved_rail.has(cell): return false
	if domain == &"water": return true
	if traversal == null: return true
	var feet := route_point(cell,kind,domain)
	var exclusions: Array[RID] = []
	return not traversal.support_near(feet,.06,.06,exclusions).is_empty() and not traversal.touches_water(feet)

func route_point(cell: Vector2i, kind: StringName, domain: StringName) -> Vector3:
	return graph.walk_point(cell,Vector2(.5,.9)) if kind == &"pedestrian" else graph.point(cell,domain)

func request(owner: String, kind: String, args: Dictionary) -> Dictionary:
	if graph == null: return {"ok":false,"code":"unavailable"}
	var key := JSON.stringify([kind,args])
	var cache: Dictionary = _cache.get(owner,{})
	if CityTrafficCatalog.domain(StringName(args.get("options",{}).get("kind","pedestrian"))) != &"air" and not args.has("_kind") and kind not in ["world.player","world.nearby"] and _revision == graph.revision and cache.has(key): return cache[key].duplicate(true)
	var count := 0
	for job in _queue:
		if job.owner == owner: count += 1
	if count >= 32 or _queue.size() >= 256: return {"ok":false,"code":"quota_exceeded"}
	_serial += 1
	var job := {"owner":owner,"kind":kind,"args":args.duplicate(true),"key":key,"query_id":_serial,"revision":graph.revision,"world_revision":traversal.revision if is_instance_valid(traversal) else -1,"frontier":[],"head":0,"parents":{},"visited":0}
	job["actor_kind"] = String(args.get("_kind",args.get("options",{}).get("kind","pedestrian")))
	job["domain"] = String(args.get("_domain",CityTrafficCatalog.domain(StringName(job.actor_kind))))
	var start := point(args.get("from",player))
	if kind == "world.route" or kind == "world.find_landmark":
		if start.is_finite():
			var cell := Vector2i(floori(start.x),floori(start.z))
			if supported(cell,StringName(job.actor_kind),StringName(job.domain)) and absf(route_point(cell,StringName(job.actor_kind),StringName(job.domain)).y-start.y) < .15:
				var previous_point := point(args.get("_previous",{}))
				var previous := Vector2i(floori(previous_point.x),floori(previous_point.z)) if previous_point.is_finite() else CityTrafficGraph.INVALID
				var node := {"cell":cell,"previous":previous,"domain":StringName(job.domain),"lane":int(args.get("_lane",0)),"parent":-1}
				job.frontier.append(node)
				job.parents[_node_key(node)] = true
	_queue.append(job)
	return {"ok":true,"code":"pending","query_id":_serial}

func pending_count() -> int: return _queue.size()

func clear_owner(owner: String) -> void:
	_queue = _queue.filter(func(job: Dictionary) -> bool: return job.owner != owner)
	_cache.erase(owner)

func step() -> Array[Dictionary]:
	nodes_visited_in_one_step = 0
	var results: Array[Dictionary] = []
	if graph == null: return results
	if _revision != graph.revision:
		_cache.clear()
		_revision = graph.revision
	while not _queue.is_empty() and nodes_visited_in_one_step < 256:
		var job: Dictionary = _queue[0]
		var result: Dictionary = {}
		if job.revision != graph.revision: result = {"ok":false,"code":"stale_geometry"}
		elif job.domain == "air" and job.kind == "world.route":
			var start := point(job.args.get("from",{}))
			var destination := point(job.args.get("destination",{}))
			if not is_instance_valid(traversal) or job.world_revision != traversal.revision: result = {"ok":false,"code":"stale_geometry"}
			elif not start.is_finite() or not destination.is_finite() or start.distance_to(destination) > ExploreAirWaypoints.MAX_DISTANCE: result = {"ok":false,"code":"no_route"}
			else:
				# At most 256 swept segments per route, sharing the surface query
				# budget. A queued remainder resumes next active service step.
				var segments := maxi(1,ceili(start.distance_to(destination)/ExploreAirWaypoints.SEGMENT_LENGTH))
				while job.head < segments and nodes_visited_in_one_step < 256:
					var from := start.lerp(destination,float(job.head)/segments)
					var to := start.lerp(destination,float(job.head+1)/segments)
					job.head += 1
					job.visited += 1
					nodes_visited_in_one_step += 1
					if not ExploreAirWaypoints.clear_segment(traversal,StringName(job.actor_kind),from,to):
						result = {"ok":false,"code":"no_route"}
						break
				if result.is_empty() and job.head >= segments: result = {"ok":true,"code":"ok","data":copied_point(destination,graph.revision),"_air_destination":destination,"_world_revision":traversal.revision}
		elif job.kind == "world.player": result = {"ok":not player.is_empty(),"code":"ok" if not player.is_empty() else "unavailable","data":player.duplicate(true)}
		elif job.kind == "world.nearby": result = _nearby(job)
		elif job.kind not in ["world.route","world.find_landmark"]: result = {"ok":false,"code":"unavailable"}
		else:
			while job.head < job.frontier.size() and job.visited < 4096 and nodes_visited_in_one_step < 256:
				var index: int = job.head
				var node: Dictionary = job.frontier[index]
				var cell: Vector2i = node.cell
				job.head += 1
				job.visited += 1
				nodes_visited_in_one_step += 1
				if not supported(cell,StringName(job.actor_kind),node.domain): continue
				var destination := point(job.args.get("destination",{}))
				var found := destination.is_finite() and cell == Vector2i(floori(destination.x),floori(destination.z)) and absf(destination.y-route_point(cell,StringName(job.actor_kind),node.domain).y) < .15
				if job.kind == "world.find_landmark":
					var landmark: String = job.args.get("kind","")
					var origin: Vector2i = job.frontier[0].cell
					found = landmark in ["road_destination","sidewalk","road"] and cell.distance_squared_to(origin) >= 9
					if landmark in ["park","station"]:
						for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
							var neighbor: Vector2i = cell+offset
							if graph.city.in_bounds(neighbor.x,neighbor.y):
								var code: int = graph.city.building.at(neighbor.x,neighbor.y)
								if (landmark == "station" and code in [Buildings.SUBWAY_STATION,Buildings.RAIL_STATION]) or (landmark == "park" and code in [Buildings.SMALL_PARK,Buildings.LARGE_PARK]): found = true
				if found:
					var route: Array[Vector2i] = []
					var trace := index
					while trace >= 0:
						route.append(job.frontier[trace].cell)
						trace = job.frontier[trace].parent
					route.reverse()
					var data := copied_point(route_point(cell,StringName(job.actor_kind),node.domain),graph.revision)
					data["distance"] = route.size()-1
					result = {"ok":true,"code":"ok","data":data,"_cells":route}
					break
				var choices := graph.traffic_choices(cell,node.domain,node.previous,node.lane)
				if choices.size() > 1: choices.erase(node.previous)
				if choices.size() > 1 and node.domain == &"highway" and cell-node.previous != node.previous-job.frontier[maxi(0,int(node.parent))].previous:
					var straight: Vector2i = cell+(cell-node.previous)
					if choices.has(straight): choices.assign([straight])
				for next: Vector2i in choices:
					if job.parents.size() >= 4096: break
					var domain := graph.continuation_domain(cell,next,node.domain)
					var following := {"cell":next,"previous":cell,"domain":domain,"lane":1 if graph.is_ramp(cell) and domain == &"highway" else node.lane,"parent":index}
					var key := _node_key(following)
					if not job.parents.has(key):
						job.parents[key] = true
						job.frontier.append(following)
			if result.is_empty() and (job.head >= job.frontier.size() or job.visited >= 4096): result = {"ok":false,"code":"no_route"}
		if result.is_empty(): break
		_queue.pop_front()
		result["query_id"] = job.query_id
		result["owner"] = job.owner
		result["args"] = job.args
		result["kind"] = job.kind
		results.append(result)
		var cache: Dictionary = _cache.get(job.owner,{})
		if cache.size() >= 32: cache.erase(cache.keys()[0])
		var public_result := result.duplicate(true)
		for field in ["_cells","_air_destination","_world_revision","owner","args","kind","query_id"]: public_result.erase(field)
		cache[job.key] = public_result
		_cache[job.owner] = cache
	return results

static func _node_key(node: Dictionary) -> String:
	return "%s:%s:%s:%s" % [node.cell,node.previous,node.domain,node.lane]

func _nearby(job: Dictionary) -> Dictionary:
	if traffic == null: return {"ok":true,"code":"ok","data":observations.slice(0,64).duplicate(true)}
	if not job.has("nearby"):
		job["nearby"] = []
		job["origin"] = point(player)
	var options: Dictionary = job.args.get("options",{})
	var radius := clampf(float(options.get("radius",8.0)),0,64)
	var total := traffic.actors.size()+traffic._external.size()
	while job.head < total and nodes_visited_in_one_step < 256:
		var index: int = job.head
		job.head += 1
		nodes_visited_in_one_step += 1
		var observation: Dictionary
		var position: Vector3
		if index < traffic.actors.size():
			var actor: Dictionary = traffic.actors[index]
			position = traffic.actor_pose(actor).origin
			observation = {"id":String(actor.get("mod_handle","ambient:"+str(actor.id))),"kind":String(actor.kind),"position":copied_point(position,graph.revision),"speed":0.0 if actor.stopped else float(actor.speed)}
		else:
			var actor: Dictionary = traffic._external[index-traffic.actors.size()]
			position = actor.presentation_position
			observation = {"id":"external:"+str(actor.presentation_id),"kind":String(actor.kind),"position":copied_point(position,graph.revision),"speed":0.0}
		var distance: float = job.origin.distance_squared_to(position)
		if distance > radius*radius or (options.has("kind") and options.kind != observation.kind): continue
		job.nearby.append({"distance":distance,"observation":observation})
		job.nearby.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.distance < b.distance)
		if job.nearby.size() > 64: job.nearby.pop_back()
	if job.head < total: return {}
	var data: Array[Dictionary] = []
	var bytes := 2
	for entry: Dictionary in job.nearby:
		var size := JSON.stringify(entry.observation).to_utf8_buffer().size()+1
		if bytes+size > 6500: break
		data.append(entry.observation)
		bytes += size
	return {"ok":true,"code":"ok","data":data}
