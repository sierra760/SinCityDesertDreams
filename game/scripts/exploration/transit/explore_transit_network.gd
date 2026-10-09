# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Immutable presentation routes. Never writes city grids or simulation RNG.
class_name ExploreTransitNetwork
extends RefCounted

const DIRS: Array[Vector2i] = [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
const DEPTH := .62
const MAX_ROUTE_NODES := 512
var city: City
var revision := -1
## Increments whenever nodes may have changed. rebuild() is the only production
## writer; code that edits nodes in place must call mark_changed() afterwards.
var serial := 0
var stations: Array[Dictionary] = []
var nodes: Dictionary = {}
var graph: CityTrafficGraph
var unavailable: Array[Dictionary] = []
var _routes: Dictionary = {}
var _destinations: Dictionary = {}
var _station_options: Dictionary = {}
var _departure_routes: Dictionary = {}
var _edge_cache: Dictionary = {}
static var _relevant_codes := PackedByteArray()

func rebuild(value: City, traffic_graph: CityTrafficGraph, rev: int) -> void:
	serial += 1
	city = value
	graph = traffic_graph
	revision = rev
	stations.clear()
	nodes.clear()
	unavailable.clear()
	_routes.clear()
	_destinations.clear()
	_station_options.clear()
	_departure_routes.clear()
	_edge_cache.clear()
	if city == null: return
	for cell: Vector2i in graph.cells(&"rail"):
		var id := Vector3i(cell.x,0,cell.y)
		var links: Array[Vector3i] = []
		for neighbor: Vector2i in graph.neighbors(cell,&"rail"):
			links.append(Vector3i(neighbor.x,0,neighbor.y))
		nodes[id] = {"point":graph.point(cell,&"rail"),"links":links}
	# Tunnel depth follows local terrain. Propagate only the lowering needed
	# for bounded grades; a distant coastal tile cannot sink every station.
	var masks := {}
	var heights := {}
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var mask := NetworkShapes.underground_mask(city.underground.at(x,y),NetworkShapes.Family.SUBWAY)
			if mask != 0:
				var cell := Vector2i(x,y)
				masks[cell] = mask
				heights[cell] = CityGeometry3D.ground_height(city,cell)-DEPTH
	var flat := {}
	for cell: Vector2i in masks:
		var directions: Array[Vector2i] = []
		var links: Array[Vector3i] = []
		for d: int in 4:
			var other := cell+DIRS[d]
			if int(masks[cell]) & (1<<d) and int(masks.get(other,0)) & (1<<((d+2)%4)):
				directions.append(DIRS[d])
				links.append(Vector3i(other.x,1,other.y))
		flat[cell] = city.building.atv(cell)==Buildings.SUBWAY_STATION or directions.size()>2 or (directions.size()==2 and directions[0]!=-directions[1])
		nodes[Vector3i(cell.x,1,cell.y)] = {"point":Vector3(cell.x+.5,heights[cell],cell.y+.5),"links":links}
	var queue: Array = heights.keys()
	var cursor := 0
	while cursor<queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for key: Vector3i in nodes[Vector3i(cell.x,1,cell.y)].links:
			var other := Vector2i(key.x,key.z)
			var rise := 0.0 if bool(flat[cell]) or bool(flat[other]) else .30
			var limit: float = heights[cell]+rise
			if float(heights[other])>limit+.000001:
				heights[other] = limit
				queue.append(other)
	for cell: Vector2i in heights: nodes[Vector3i(cell.x,1,cell.y)].point.y = heights[cell]
	_connect_portals()
	# Only stations need footprint resolution; collecting every developed lot
	# would dominate this projection's startup on dense imported cities.
	var station_seen := {}
	var building_codes := city.building.data
	for index in building_codes.size():
		var code := int(building_codes[index])
		if code not in [Buildings.RAIL_STATION,Buildings.SUBWAY_STATION]: continue
		var cell := Vector2i(index % City.WIDTH,index / City.WIDTH)
		var anchor := city.anchor_of(cell.x,cell.y)
		var key := Vector3i(anchor.x,anchor.y,code)
		if station_seen.has(key): continue
		station_seen[key] = true
		_station({"code":code,"anchor":anchor,"footprint":Rect2i(anchor,Buildings.size(code))})

## Tracks reciprocally connected beside a station, through platforms first and
## one-sided termini second. Also used by the static station model.
static func station_connections(value: City, rect: Rect2i, subway := false) -> Array[Dictionary]:
	return StationStreetAccess.station_connections(value,rect,subway)

func _station(record: Dictionary) -> void:
	var rect: Rect2i = record.footprint
	var subway: bool = record.code == Buildings.SUBWAY_STATION
	var candidates: Array[Dictionary] = []
	for candidate: Dictionary in station_connections(city,rect,subway):
		var cell: Vector2i = candidate.cell
		var key := Vector3i(cell.x,1 if subway else 0,cell.y)
		if not nodes.has(key): continue
		var direction: Vector2i = candidate.direction
		var reciprocal := false
		for step: Vector2i in [direction,-direction]:
			if nodes[key].links.has(Vector3i(key.x+step.x,key.y,key.z+step.y)): reciprocal = true
		if reciprocal:
			candidate.node = key
			candidates.append(candidate)
	var title := StationNameResolver.display_name(city,rect.position,subway)
	if candidates.is_empty():
		unavailable.append({"name":title,"anchor":rect.position,"subway":subway,"reason":"Trains can't reach this station. Run connected track past it." if not subway else "Trains can't reach this station. Run a connected subway tunnel past it."})
		return
	var options: Array[Dictionary] = []
	var reason := "The track beside this station is not level with its platform."
	for choice: Dictionary in candidates:
		var at: Vector3 = nodes[choice.node].point
		var direction: Vector2i = choice.direction
		var forward := Vector3(direction.x,0,direction.y)
		var right := Vector3(-direction.y,0,direction.x)
		var normal: Vector3 = right*int(choice.side)
		var yaw := atan2(-forward.x,-forward.z)
		var surface := CityGeometry3D.ground_height(city,rect.position)
		if not subway and absf(surface-at.y)>.09: continue
		if subway and surface-at.y-.025<=0:
			reason = "This entrance sits lower than the subway tunnel beside it. Move the station to higher ground."
			continue
		if subway and surface-at.y-.025>2.4:
			reason = "The platform is too deep for the station lift. Build the station where the tunnel runs shallower."
			continue
		options.append({"id":stations.size(),"name":title,"anchor":rect.position,"rect":rect,
			"subway":subway,"node":choice.node,"position":at,"forward":forward,"normal":normal,
			"yaw":yaw,"side":int(choice.side),"platform":at+normal*.24+Vector3.UP*.025,
			"surface":surface,"access_position":Vector3(rect.position.x+.5,at.y,rect.position.y+.5),"revision":revision})
	if options.is_empty():
		unavailable.append({"name":title,"anchor":rect.position,"subway":subway,"reason":reason})
		return
	_station_options[stations.size()] = options
	stations.append(options[0])

## Mutate only names in published records, including deep route-specific poses.
func refresh_station_names() -> void:
	if city == null: return
	for stop: Dictionary in stations: refresh_station_record(stop)
	for stop: Dictionary in unavailable: refresh_station_record(stop)
	for options: Array in _station_options.values():
		for stop: Dictionary in options: refresh_station_record(stop)
	for cache: Dictionary in [_routes,_departure_routes]:
		for path: Dictionary in cache.values(): refresh_route_names(path)
	for options: Array in _destinations.values():
		for option: Dictionary in options:
			option.name = station(int(option.id)).get("name",option.name)

func refresh_station_record(stop: Dictionary) -> void:
	if city != null and stop.has("anchor"):
		stop.name = StationNameResolver.display_name(city,stop.anchor,bool(stop.get("subway",false)))

func refresh_route_names(path: Dictionary) -> void:
	for stop: Dictionary in path.get("station_poses",{}).values(): refresh_station_record(stop)

func station(id: int) -> Dictionary:
	return stations[id] if id>=0 and id<stations.size() else {}

func destinations(id: int) -> Array[Dictionary]:
	if _destinations.has(id): return _destinations[id]
	var out: Array[Dictionary] = []
	for other: Dictionary in stations:
		if other.id != id and not route(id,other.id).is_empty(): out.append({"id":other.id,"name":other.name})
	_destinations[id] = out
	return out

## The presentation orientation is selected for the requested connected route,
## never used as a reason to reject another legitimate side of the station.
func route(from_id: int, to_id: int) -> Dictionary:
	var cache_key := Vector2i(from_id,to_id)
	if _routes.has(cache_key): return _routes[cache_key].duplicate(true)
	if station(from_id).is_empty() or station(to_id).is_empty() or from_id==to_id: return {}
	for from: Dictionary in _station_options[from_id]:
		for to: Dictionary in _station_options[to_id]:
			var result := _route_between(from,to)
			if not result.is_empty():
				_routes[cache_key] = result.duplicate(true)
				return result
	_routes[cache_key] = {}
	return {}

## Preserve an occupied waiting platform while changing a destination whenever
## the requested service can depart from its current physical doorway.
func route_from_pose(from_id: int, to_id: int, pose: Dictionary) -> Dictionary:
	if station(from_id).is_empty() or station(to_id).is_empty() or from_id==to_id: return {}
	var key := "%d/%d/%s/%s/%s" % [from_id,to_id,pose.node,pose.forward,pose.normal]
	if _departure_routes.has(key): return _departure_routes[key].duplicate(true)
	for candidate: Dictionary in _station_options[from_id]:
		if candidate.node!=pose.node or candidate.forward!=pose.forward or candidate.normal!=pose.normal: continue
		for destination: Dictionary in _station_options[to_id]:
			var result := _route_between(candidate,destination)
			if not result.is_empty():
				_departure_routes[key] = result.duplicate(true)
				return result
	_departure_routes[key] = {}
	return {}

## Publish an in-place edit of nodes so cached route validation re-runs.
func mark_changed() -> void:
	serial += 1

func station_for_route(path: Dictionary, id: int) -> Dictionary:
	return path.get("station_poses",{}).get(id,station(id))

## The sampled path points of the track edge from node `a` to node `b`.
func edge_points(a: Vector3i, b: Vector3i) -> PackedVector3Array:
	return _edge_data(a,b).points

## Edge profiles are cached per rebuild and reused across destination searches.
## The endpoint check catches nodes edited in place since the profile was cached.
func _edge_data(a: Vector3i, b: Vector3i) -> Dictionary:
	var first: Vector3 = nodes[a].point
	var last: Vector3 = nodes[b].point
	var cached: Dictionary = _edge_cache.get(a,{}).get(b,{})
	if not cached.is_empty() and cached.first==first and cached.last==last: return cached
	var points := PackedVector3Array([first])
	if a.y==0 and b.y==0:
		var step := Vector2(b.x-a.x,b.z-a.z)
		for half: int in 2:
			var cell := Vector2i(a.x,a.z) if half==0 else Vector2i(b.x,b.z)
			# Curved decks use the renderer's 1/16-tile physical facets.
			# Ground halves stay on one terrain triangle and need only an edge.
			var segments := 8 if NetworkShapes.is_rail_bridge(city.building.atv(cell)) else 1
			# Smoothed bridge approaches use the renderer's subdivided deck.
			# Sample each facet instead of cutting above it.
			var approach := graph.bridge_approach(cell)
			if not approach.is_empty():
				var subdivisions: Vector2i=CityNetworks3D.BridgeApproaches.subdivisions(approach)
				segments=maxi(1,(subdivisions.x if step.x!=0 else subdivisions.y)/2)
			var begin := Vector2(.5,.5) if half==0 else Vector2(.5,.5)-step*.5
			var limit := segments+1 if half==0 else segments
			for index: int in range(1,limit):
				points.append(graph.point(cell,&"rail",begin+step*.5*float(index)/segments))
	points.append(last)
	var safe := true
	for index: int in range(1,points.size()):
		var delta := points[index]-points[index-1]
		if not delta.is_finite() or absf(delta.y)>Vector2(delta.x,delta.z).length()*tan(deg_to_rad(35.0)):
			safe = false
	cached = {"first":first,"last":last,"points":points,"safe":safe}
	if not _edge_cache.has(a): _edge_cache[a] = {}
	_edge_cache[a][b] = cached
	return cached

## Curved centerline through a level right-angle subway tile, matching its
## rails. Returns an empty array for any other node.
func corner_points(key: Vector3i, first: Vector3i = Vector3i(-1,-1,-1)) -> PackedVector3Array:
	if key.y!=1 or not nodes.has(key): return PackedVector3Array()
	var links: Array=nodes[key].links
	if links.size()!=2: return PackedVector3Array()
	var center: Vector3=nodes[key].point
	var arms: Array[Vector3]=[]
	if first==links[1]: links=[links[1],links[0]]
	for next: Vector3i in links:
		if next.y!=1: return PackedVector3Array()
		var delta: Vector3=nodes[next].point-center
		if absf(delta.y)>.0001 or absf(delta.length()-1)>.0001: return PackedVector3Array()
		arms.append(delta)
	if absf(arms[0].dot(arms[1]))>.0001: return PackedVector3Array()
	var pivot := center+(arms[0]+arms[1])*.5
	var points := PackedVector3Array()
	for i: int in 25:
		var angle := float(i)/24*PI*.5
		points.append(pivot-arms[1]*cos(angle)*.5-arms[0]*sin(angle)*.5)
	return points

func _route_between(from: Dictionary, to: Dictionary) -> Dictionary:
	var start: Vector3i = from.node
	var goal: Vector3i = to.node
	if start == goal: return {}
	var queue: Array[Vector3i] = [start]
	var parents := {start:start}
	var cursor := 0
	while cursor < queue.size() and not parents.has(goal):
		var key := queue[cursor]
		cursor += 1
		for next: Vector3i in nodes[key].links:
			if parents.has(next): continue
			if not bool(_edge_data(key,next).safe): continue
			var delta: Vector3 = nodes[next].point-nodes[key].point
			if key==start and absf(delta.normalized().dot(from.forward))<.95: continue
			if next==goal and absf(delta.normalized().dot(to.forward))<.95: continue
			parents[next] = key
			queue.append(next)
	if not parents.has(goal): return {}
	var path: Array[Vector3i] = [goal]
	while path.back() != start:
		path.append(parents[path.back()])
		if path.size()>MAX_ROUTE_NODES: return {}
	path.reverse()
	# Platforms must face the route's straight stopping segment. A crossing
	# cannot turn a station's parallel platform into a perpendicular doorway.
	for pair: Array in [[from,0,1],[to,path.size()-1,path.size()-2]]:
		var station_data: Dictionary = pair[0]
		var a: Vector3 = nodes[path[pair[1]]].point
		var b: Vector3 = nodes[path[pair[2]]].point
		if absf((b-a).normalized().dot(station_data.forward))<.95: return {}
	var points := PackedVector3Array()
	# Cell centres alone cut through the convex half of a ground grade.
	# Cardinal centre-to-edge spans stay on one terrain triangle, and graph
	# sampling also preserves the authored bridge axis and deck lift.
	var node_point_indices := PackedInt32Array()
	for index: int in path.size():
		var key: Vector3i = path[index]
		if index>0:
			var edge := edge_points(path[index-1],key)
			for middle: int in range(1,edge.size()-1):
				if points.is_empty() or edge[middle].distance_to(points[-1])>.00001: points.append(edge[middle])
		var corner := corner_points(key,path[index-1]) if index>0 and index<path.size()-1 else PackedVector3Array()
		var first_index := points.size()
		if not corner.is_empty() and not points.is_empty() and corner[0].distance_to(points[-1])<.00001: first_index-=1
		node_point_indices.append(first_index+corner.size()/2 if not corner.is_empty() else first_index)
		if corner.is_empty(): points.append(nodes[key].point)
		else:
			for point: Vector3 in corner:
				if points.is_empty() or point.distance_to(points[-1])>.00001: points.append(point)
	for i: int in range(1,points.size()):
		# Reject malformed/imported grades that cannot carry the upright rider
		# safely. The authored subway entrance descends about 32 degrees.
		var delta := points[i]-points[i-1]
		if absf(delta.y)>Vector2(delta.x,delta.z).length()*tan(deg_to_rad(35.0)): return {}
	var distances := PackedFloat32Array([0.0])
	for i: int in range(1,points.size()): distances.append(distances[-1]+points[i-1].distance_to(points[i]))
	if distances[-1]<1.0: return {}
	var stops: Array[Dictionary] = []
	var poses := {int(from.id):from,int(to.id):to}
	for s: Dictionary in stations:
		var options: Array = [poses[s.id]] if poses.has(s.id) else _station_options[s.id]
		for option: Dictionary in options:
			var node_index := path.find(option.node)
			var index := int(node_point_indices[node_index]) if node_index>=0 else -1
			if index<0: continue
			var tangent: Vector3 = points[mini(index+1,points.size()-1)]-points[maxi(index-1,0)]
			if absf(tangent.normalized().dot(option.forward))<.95: continue
			poses[s.id] = option
			stops.append({"station":s.id,"distance":distances[index]})
			break
	stops.sort_custom(func(a,b): return a.distance<b.distance)
	return {"from":from.id,"to":to.id,"nodes":path,"points":points,"distances":distances,
		"length":distances[-1],"stops":stops,"station_poses":poses,"revision":revision,
		"node_point_indices":node_point_indices}

static func sample(path: Dictionary, distance: float) -> Transform3D:
	var points: PackedVector3Array = path.get("points",PackedVector3Array())
	if points.size()<2: return Transform3D.IDENTITY
	var lengths: PackedFloat32Array = path.distances
	var d := clampf(distance,0,lengths[-1])
	var index := 0
	while index<points.size()-2 and lengths[index+1]<d: index += 1
	var factor := (d-lengths[index])/maxf(.0001,lengths[index+1]-lengths[index])
	var point := points[index].lerp(points[index+1],factor)
	# Tangent smoothing turns a short car inside the rail corridor without
	# moving its centre off the validated polyline.
	var forward := (points[index+1]-points[index]).normalized()
	if index>0 and factor<.20:
		forward = (points[index]-points[index-1]).normalized().lerp(forward,.5+factor*2.5).normalized()
	if index<points.size()-2 and factor>.80:
		forward = forward.lerp((points[index+2]-points[index+1]).normalized(),(factor-.80)*2.5).normalized()
	var basis := Basis.looking_at(forward,Vector3.UP)
	return Transform3D(basis,point)

func _connect_portals() -> void:
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var cell := Vector2i(x,y)
			if not NetworkShapes.is_subway_portal(city.building.atv(cell)): continue
			var profile := CityPortal3D.profile(city,cell,CityGeometry3D.HEIGHT)
			var outside: Vector2i = profile.rail_cell
			var rail := Vector3i(outside.x,0,outside.y)
			if not nodes.has(rail): continue
			var underground: Array[Vector3i] = []
			for neighbor: Vector2i in profile.subway_cells:
				var key := Vector3i(neighbor.x,1,neighbor.y)
				if nodes.has(key): underground.append(key)
			if underground.is_empty(): continue
			var entrance := Vector2(cell)+Vector2(profile.outside)
			var end := entrance+Vector2(profile.inward)*float(profile.depth)
			var begin_key := Vector3i(x,2,y)
			var end_key := Vector3i(x,3,y)
			var portal_key := Vector3i(x,1,y)
			var links: Array[Vector3i] = [begin_key]
			links.append_array(underground)
			nodes[begin_key] = {"point":Vector3(entrance.x,profile.floor_start,entrance.y),"links":[rail,end_key]}
			nodes[end_key] = {"point":Vector3(end.x,profile.floor_end,end.y),"links":links}
			nodes[rail].links.append(begin_key)
			# Underground track joins the ramp's inner end, so no hidden tunnel
			# runs through the solid ramp beneath the portal.
			for key: Vector3i in underground:
				nodes[key].links.erase(portal_key)
				nodes[key].links.append(end_key)
			nodes.erase(portal_key)

## Inputs that can change the route network. Ordinary growth and traffic are
## excluded, so they never force a rebuild. Terrain and underground layers are
## included in full because tunnel depth, bridge banks and portal slopes depend
## on them.
static func topology_signature(value: City) -> Array:
	if value == null: return []
	if _relevant_codes.is_empty():
		_relevant_codes.resize(256)
		for code in 256:
			_relevant_codes[code] = int(NetworkShapes.in_family(code,NetworkShapes.Family.RAIL) or NetworkShapes.is_subway_portal(code) or code in [Buildings.RAIL_STATION,Buildings.SUBWAY_STATION])
	var codes := value.building.data
	var flags := value.flags.data
	var relevant := PackedByteArray()
	var relevant_flags := PackedByteArray()
	var station_corners := PackedByteArray()
	var zones := value.zone.data
	relevant.resize(codes.size())
	relevant_flags.resize(codes.size())
	station_corners.resize(codes.size())
	for index in codes.size():
		if _relevant_codes[codes[index]]!=0:
			relevant[index] = codes[index]
			relevant_flags[index] = flags[index] & RotationMapper.AXIS_FLAG
			if codes[index] in [Buildings.RAIL_STATION,Buildings.SUBWAY_STATION]: station_corners[index] = zones[index] & Zones.CORNER_MASK
	var vertices: PackedByteArray = value.terrain_surface.vertices if value.terrain_surface is TerrainSurface else PackedByteArray()
	return [value.get_instance_id(),relevant,relevant_flags,station_corners,value.underground.data.duplicate(),value.altitude.data.duplicate(),value.terrain.data.duplicate(),vertices.duplicate()]
