# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The ordinary surface road network that streets are named on, derived
## read-only from the city. Link identities survive re-projection; the
## selectable chains come from those links and the current name assignments.
class_name StreetTopology
extends RefCounted

const Tunnels := preload("res://scripts/view/city_road_tunnels_3d.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
## Process-local selection tokens, unrelated to saved street IDs or city RNG.
static var _next_revision_token := 0
var revision := 0
var _bound_city_id := 0
var _nodes: Dictionary = {}
var _links: Dictionary = {}
var _exits: Array[Dictionary] = []
var _graph := CityTrafficGraph.new()
var _bores: Dictionary = {}
var _projection_state: Array = []
## Creation rank of every link: the scan order (see _order) of the first node
## whose scan creates it, times four, plus that scan's direction. `_links` and
## every node's `links` list are in ascending rank, as the scan appends them.
var _link_ranks: Dictionary = {}
## Road node keys that the last exit pass marked as ramp terminals.
var _ramp_keys: Array[String] = []
## False while the containers are shared with the topology they were adopted
## from; the next incremental rebuild copies them first.
var _owns_projection := true
const Highways := preload("res://scripts/traffic/city_traffic_highways.gd")
static var _onramp_codes := PackedByteArray()

## Copies of everything the street graph depends on, so rebuild() can tell when
## nothing relevant changed. Besides terrain, only network cells count: road,
## highway, rail, onramp, tunnel/portal and bridge codes with their orientation
## flags and highway corner bits. Lots, ground cover, parks, utility lines,
## power/water service and floods are left out; no pass below reads them.
static func _projection_inputs(city: City) -> Array:
	if city==null: return []
	var projected := _project_layers(city.building.data,city.zone.data,city.flags.data)
	var vertices: PackedByteArray = city.terrain_surface.vertices if city.terrain_surface is TerrainSurface else PackedByteArray()
	return [city.altitude.data.duplicate(),city.terrain.data.duplicate(),projected[0],projected[1],projected[2],vertices.duplicate(),city.sea_level]


## The last raw building/zone/flag bytes seen and their projection, so a repeat
## with few changed rows reprojects only those rows. The projection of a byte
## depends on that byte alone, so the result equals a complete pass.
static var _projected_raw: Array = []
static var _projected: Array = []

static func _project_layers(buildings_raw: PackedInt32Array, zones_raw: PackedByteArray, flags_raw: PackedByteArray) -> Array:
	var raw: Array = [buildings_raw,zones_raw,flags_raw]
	if raw == _projected_raw: return [_projected[0].duplicate(),_projected[1].duplicate(),_projected[2].duplicate()]
	var kinds := CityTrafficGraph.network_kinds()
	var buildings: PackedInt32Array
	var zones: PackedByteArray
	var flags: PackedByteArray
	var rows: Array = []
	var incremental: bool = _projected_raw.size()==3 and _projected_raw[0].size()==buildings_raw.size() and _projected_raw[1].size()==zones_raw.size() and _projected_raw[2].size()==flags_raw.size() and buildings_raw.size()%City.WIDTH==0
	if incremental:
		buildings = _projected[0].duplicate()
		zones = _projected[1].duplicate()
		flags = _projected[2].duplicate()
		var start := 0
		while start < buildings_raw.size():
			var end := mini(buildings_raw.size(),start+City.WIDTH)
			if buildings_raw.slice(start,end)!=_projected_raw[0].slice(start,end) or zones_raw.slice(start,end)!=_projected_raw[1].slice(start,end) or flags_raw.slice(start,end)!=_projected_raw[2].slice(start,end):
				rows.append(start)
			start = end
	else:
		buildings = buildings_raw.duplicate()
		zones = zones_raw.duplicate()
		flags = flags_raw.duplicate()
		var start := 0
		while start < buildings_raw.size():
			rows.append(start)
			start += City.WIDTH
	for start: int in rows:
		for i: int in range(start,mini(buildings_raw.size(),start+City.WIDTH)):
			var code: int = buildings_raw[i]
			if kinds[code]==0:
				buildings[i] = Buildings.NONE
				zones[i] = 0
				flags[i] = 0
			else:
				buildings[i] = code
				zones[i] = zones_raw[i]
				flags[i] = flags_raw[i] & ~(TileFlags.POWERED | TileFlags.WATERED)
	_projected_raw = [buildings_raw.duplicate(),zones_raw.duplicate(),flags_raw.duplicate()]
	_projected = [buildings.duplicate(),zones.duplicate(),flags.duplicate()]
	return [buildings,zones,flags]

## Source identity stays independent of the detached flood projection.
## Null denotes no active binding, including a never-built adapter.
func is_bound_to(city: City) -> bool:
	return city != null and city.get_instance_id() == _bound_city_id

static func _before(a: Vector2i, ac: StringName, b: Vector2i, bc: StringName) -> bool:
	if a.y != b.y: return a.y < b.y
	if a.x != b.x: return a.x < b.x
	return ac == &"open" and bc == &"bore"

static func _node_key(cell: Vector2i, channel: StringName) -> String:
	return "%d,%d,%s" % [cell.x, cell.y, channel]

static func link_key(a: Vector2i, a_channel: StringName, b: Vector2i, b_channel: StringName) -> String:
	if _before(b, b_channel, a, a_channel):
		return _node_key(b,b_channel) + ">" + _node_key(a,a_channel)
	return _node_key(a,a_channel) + ">" + _node_key(b,b_channel)

## Returns whether the City binding, links, ramp terminals, or departures changed.
## Same-City geometry alone preserves selection tokens; points always refresh.
func rebuild(city: City) -> bool:
	var city_id := city.get_instance_id() if city != null else 0
	var binding_changed := city_id != _bound_city_id
	_bound_city_id = city_id
	var state := _projection_inputs(city)
	var structural: City = city
	if city!=null and not city.flood_overlay.is_empty():
		structural = city.duplicate_city()
		structural.flood_overlay.clear()
	if not binding_changed and state==_projection_state:
		# Nothing relevant changed, so cached routes and corners stay valid. Point
		# the graph at the flood-free copy so it never reads a flooded city.
		_graph.city = structural
		return false
	var previous_state := _projection_state
	_projection_state = state
	var incremental := -1
	if not binding_changed: incremental = _rebuild_incremental(city, structural, previous_state, state)
	if incremental >= 0:
		if incremental == 1:
			_next_revision_token += 1
			revision = _next_revision_token
		return incremental == 1
	var old_structure := _structure_keys()
	# Fresh containers: an adopted source keeps its own projection intact.
	_nodes = {}
	_links = {}
	var no_exits: Array[Dictionary] = []
	_exits = no_exits
	_bores = {}
	_link_ranks = {}
	_owns_projection = true
	# The incremental attempt may already have projected the graph completely.
	if incremental != -2: _graph = CityTrafficGraph.new()
	if city != null:
		# Floods are temporary. The bridge helpers consult is_water(), so build
		# from a flood-free copy rather than the live city.
		if incremental != -2: _graph.bind_city(structural)
		_bores = Tunnels.profiles(structural)
		# Classify each raw building code; empty cells that are not tunnel bores
		# add no nodes.
		var kinds := CityTrafficGraph.network_kinds()
		var codes := structural.building.data
		for y: int in City.HEIGHT:
			var row := y * City.WIDTH
			for x: int in City.WIDTH:
				var code: int = codes[row + x]
				var kind: int = kinds[code]
				var cell := Vector2i(x,y)
				if kind & CityTrafficGraph.KIND_ROAD and not kind & CityTrafficGraph.KIND_ONRAMP and not NetworkShapes.is_tunnel(code):
					var mask := CityNetworks3D.network_mask(code,NetworkShapes.Family.ROAD)
					var deck := _graph.bridge_deck(cell)
					if not deck.is_empty(): mask = 10 if deck.ew else 5
					_add_node(cell,&"open",mask)
				if _bores.has(cell): _add_node(cell,&"bore",10 if _bores[cell].inward.x != 0 else 5)
		for key: String in _nodes:
			var node: Dictionary = _nodes[key]
			for i: int in 4:
				var other_key := _link_target(node,i)
				if not other_key.is_empty(): _add_link(key,other_key,_order(node)*4+i)
		_build_exits(structural)
	var changed := binding_changed or _structure_keys() != old_structure
	if changed:
		_next_revision_token += 1
		revision = _next_revision_token
	return changed

## Adopt a completed projection of `city` from another instance (for example
## the validation projection built while decoding a save) instead of
## rebuilding it. Selection-token bookkeeping matches rebuild(city) here:
## a changed binding or structure advances this instance's revision.
func adopt(source: StreetTopology, city: City) -> bool:
	if source == null or source == self or city == null or not source.is_bound_to(city):
		return rebuild(city)
	var binding_changed := city.get_instance_id() != _bound_city_id
	var old_structure := _structure_keys()
	_bound_city_id = source._bound_city_id
	_projection_state = source._projection_state
	_nodes = source._nodes
	_links = source._links
	_exits = source._exits
	_graph = source._graph
	_bores = source._bores
	_link_ranks = source._link_ranks
	_ramp_keys = source._ramp_keys
	_owns_projection = false
	source._owns_projection = false
	var changed := binding_changed or _structure_keys() != old_structure
	if changed:
		_next_revision_token += 1
		revision = _next_revision_token
	return changed

## Ordinary memberships reconcile against has_link(), independently of this
## signature: changing a ramp invalidates selection but preserves named roads.
func _structure_keys() -> Array[String]:
	var keys: Array[String] = []
	for key: String in _links: keys.append("link:"+key)
	for key: String in _nodes:
		if _nodes[key].ramp: keys.append("terminal:"+key)
	for approach: Dictionary in _exits:
		keys.append("exit:"+String(approach.key)+":"+str(approach.direction))
	keys.sort()
	return keys

func _add_node(cell: Vector2i, channel: StringName, mask: int) -> void:
	var key := _node_key(cell,channel)
	_nodes[key] = {"key":key,"cell":cell,"channel":channel,"mask":mask,"links":[],"ramp":false}

## The rendered road point at `offset` within a node's cell.
func node_point(node: Dictionary, offset: Vector2 = Vector2(.5,.5)) -> Vector3:
	var cell: Vector2i = node.cell
	if node.channel == &"bore":
		var p: Dictionary = _bores[cell]
		var depth := (offset-Vector2(p.outside)).dot(Vector2(p.inward))
		return Vector3(cell.x+offset.x,lerpf(p.floor_start,p.floor_end,depth),cell.y+offset.y)
	return _graph.point(cell,&"road",offset)

## Each half follows the rendered bend's centerline and the exact surface grade.
func _half_points(node: Dictionary, direction: Vector2i) -> PackedVector3Array:
	var result := PackedVector3Array()
	var edge := Vector2(.5,.5) + Vector2(direction)*.5
	var mask := int(node.mask)
	if node.channel == &"open" and mask in [3,6,12,9]:
		var pivot: Vector2 = {3:Vector2(1,0),6:Vector2(1,1),12:Vector2(0,1),9:Vector2(0,0)}[mask]
		var center := (Vector2(.5,.5)-pivot).normalized()*.5
		var angle := center.angle_to(edge-pivot)
		for i: int in 5: result.append(node_point(node,pivot+center.rotated(angle*i/4.0)))
	else:
		for i: int in 5: result.append(node_point(node,Vector2(.5,.5).lerp(edge,i/4.0)))
	return result

func _add_link(a_key: String, b_key: String, rank: int) -> void:
	var a: Dictionary = _nodes[a_key]
	var b: Dictionary = _nodes[b_key]
	var key := link_key(a.cell,a.channel,b.cell,b.channel)
	if _links.has(key): return
	_links[key] = _link_value(a_key,b_key)
	_link_ranks[key] = rank
	a.links.append(key)
	b.links.append(key)

## A link's record: canonical endpoints and the joined rendered centerline.
func _link_value(a_key: String, b_key: String) -> Dictionary:
	var a: Dictionary = _nodes[a_key]
	var b: Dictionary = _nodes[b_key]
	if _before(b.cell,b.channel,a.cell,a.channel):
		var swap := a_key
		a_key = b_key
		b_key = swap
		a = _nodes[a_key]
		b = _nodes[b_key]
	var direction: Vector2i = b.cell-a.cell
	var points := _half_points(a,direction)
	var tail := _half_points(b,-direction)
	tail.reverse()
	for i: int in range(1,tail.size()): points.append(tail[i])
	return {"a":a_key,"b":b_key,"points":points}

func has_link(key: String) -> bool:
	return _links.has(key)

func connection_points(key: String) -> PackedVector3Array:
	return PackedVector3Array(_links[key].points) if _links.has(key) else PackedVector3Array()

func _other(link: String, node: String) -> String:
	return _links[link].b if _links[link].a == node else _links[link].a

## The surface road node of `cell`, or {} when the cell has none.
func open_node(cell: Vector2i) -> Dictionary:
	return _nodes.get(_node_key(cell,&"open"),{})

## The node at the far end of `link` from `node`.
func linked_node(link: String, node: Dictionary) -> Dictionary:
	return _nodes[_other(link,node.key)]

## The projection state, traffic graph and revision behind `junctions()`,
## for callers that cache its result.
func junction_sources() -> Array:
	return [_projection_state, _graph, revision]

func _boundary(key: String, assignments: Dictionary) -> bool:
	var node: Dictionary = _nodes[key]
	return node.links.size() != 2 or node.ramp or int(assignments.get(node.links[0],0)) != int(assignments.get(node.links[1],0))

func _endpoint(key: String) -> Dictionary:
	var node: Dictionary = _nodes[key]
	var direction: Vector2i = _nodes[_other(node.links[0],key)].cell-node.cell
	var position := _half_points(node,direction)[0]
	return {"key":key,"cell":node.cell,"channel":node.channel,"position":position,"degree":node.links.size(),"ramp":node.ramp}

func _chain(start: String, first: String, assignments: Dictionary, visited: Dictionary) -> Dictionary:
	var at := start
	var current := first
	var links: Array[String] = []
	var points := PackedVector3Array()
	while not visited.has(current):
		visited[current] = true
		links.append(current)
		var part := connection_points(current)
		if _links[current].a != at: part.reverse()
		for i: int in range(0 if points.is_empty() else 1,part.size()): points.append(part[i])
		at = _other(current,at)
		if at == start or _boundary(at,assignments): break
		var incident: Array = _nodes[at].links
		current = incident[1] if incident[0] == current else incident[0]
	var sorted := links.duplicate()
	sorted.sort()
	return {"id":sorted[0],"links":links,"points":points,"closed":at==start,"endpoints":[_endpoint(start),_endpoint(at)]}

func segments(assignments: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var visited: Dictionary = {}
	var keys: Array = _nodes.keys()
	keys.sort()
	for key: String in keys:
		if not _boundary(key,assignments): continue
		for link: String in _incident(key):
			if not visited.has(link): result.append(_chain(key,link,assignments,visited))
	var remaining: Array = _links.keys()
	remaining.sort()
	for link: String in remaining:
		if not visited.has(link): result.append(_chain(_links[link].a,link,assignments,visited))
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.id < b.id)
	return result

func _incident(key: String) -> Array[String]:
	var links: Array[String] = []
	links.assign(_nodes[key].links)
	links.sort_custom(func(a: String,b: String) -> bool:
		var da: Vector2i = _nodes[_other(a,key)].cell-_nodes[key].cell
		var db: Vector2i = _nodes[_other(b,key)].cell-_nodes[key].cell
		return DIRECTIONS.find(da) < DIRECTIONS.find(db) if da != db else a < b)
	return links

func junctions(assignments: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in _nodes:
		var node: Dictionary = _nodes[key]
		if node.links.size() < 3: continue
		var approaches: Array[Dictionary] = []
		for link: String in _incident(key):
			var chain := _chain(key,link,assignments,{})
			approaches.append({"direction":_nodes[_other(link,key)].cell-node.cell,"links":chain.links,"street_id":int(assignments.get(link,0)),"points":chain.points})
		result.append({"key":key,"cell":node.cell,"channel":node.channel,"position":node_point(node),"approaches":approaches})
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return _before(a.cell,a.channel,b.cell,b.channel))
	return result

func _incoming(high: Vector2i, onward: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for route: Dictionary in _graph.highways.routes.get(high,[]):
		if int(route.lane) != 1: continue
		var previous: Vector2i = route.previous
		if not _graph.neighbors(high,&"highway").has(previous): continue
		if not _graph.traffic_choices(high,&"highway",previous,1).has(onward): continue
		var enters := false
		for before: Dictionary in _graph.highways.routes.get(previous,[]):
			if int(before.lane) == 1 and before.next == high: enters = true
		if enters: result.append(route)
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return _before(a.previous,&"open",b.previous,&"open"))
	return result

func _build_exits(city: City) -> void:
	for key: String in _ramp_keys:
		if _nodes.has(key): _nodes[key].ramp = false
	var no_ramps: Array[String] = []
	_ramp_keys = no_ramps
	var kinds := CityTrafficGraph.network_kinds()
	if _onramp_codes.is_empty():
		_onramp_codes.resize(kinds.size())
		for value: int in kinds.size(): _onramp_codes[value] = 1 if kinds[value] & CityTrafficGraph.KIND_ONRAMP else 0
	# Onramp cells in row-major order, as a scan of every cell visits them.
	var codes := city.building.data
	for at: int in Highways.cells_with(codes, _onramp_codes):
		var code: int = codes[at]
		var ramp := Vector2i(at % City.WIDTH, at / City.WIDTH)
		var ends := NetworkShapes.onramp_endpoints(code,bool(city.flags.atv(ramp)&RotationMapper.AXIS_FLAG))
		var road: Vector2i = ramp + Vector2i(ends[0])
		var high: Vector2i = ramp + Vector2i(ends[1])
		var road_key := _node_key(road,&"open")
		if not _nodes.has(road_key) or not _graph.neighbors(ramp,&"road").has(road): continue
		_nodes[road_key].ramp = true
		if not _ramp_keys.has(road_key): _ramp_keys.append(road_key)
		if not _graph.neighbors(ramp,&"road").has(high) or not _graph.neighbors(high,&"highway").has(ramp): continue
		var incoming := _incoming(high,ramp)
		if incoming.is_empty(): continue
		var route: Dictionary = incoming[0]
		var previous: Vector2i = route.previous
		var upstream := PackedVector3Array([_graph.point(high,&"highway")])
		var upstream_cells: Array[Vector2i] = [high]
		var at_cell := high
		for step: int in 2:
			upstream.append(_graph.point(previous,&"highway"))
			upstream_cells.append(previous)
			var before := _incoming(previous,at_cell)
			if before.is_empty(): break
			at_cell = previous
			previous = before[0].previous
		_exits.append({"key":_node_key(ramp,&"open")+">"+_node_key(high,&"open"),"ramp":ramp,"road":road,"highway":high,"road_key":road_key,"road_position":node_point(_nodes[road_key]),"highway_position":_graph.point(high,&"highway"),"direction":high-Vector2i(route.previous),"upstream_points":upstream,"upstream_cells":upstream_cells})

func exit_approaches() -> Array[Dictionary]:
	return _exits.duplicate(true)

func _junction_names(node: String, assignments: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for link: String in _incident(node):
		var id := int(assignments.get(link,0))
		if id > 0 and not result.has(id): result.append(id)
		if result.size() == 2: break
	return result

func exit_destination(exit: Dictionary, assignments: Dictionary, max_links: int = 8) -> Array[int]:
	var at: String = exit.get("road_key","")
	if not _nodes.has(at) or max_links < 0: return []
	var previous := ""
	var count := 0
	var seen: Dictionary = {}
	while not seen.has(at):
		seen[at] = true
		var incident: Array[String] = _incident(at)
		if incident.size() >= 3 or (previous.is_empty() and incident.size() > 1): return _junction_names(at,assignments)
		incident.erase(previous)
		if incident.is_empty(): return []
		var link: String = incident[0]
		var id := int(assignments.get(link,0))
		if id > 0: return [id]
		if count >= mini(max_links,8): return []
		at = _other(link,at)
		previous = link
		count += 1
	return []


## Scan position of a node: row-major cell order, the open channel before a bore.
static func _order(node: Dictionary) -> int:
	var cell: Vector2i = node.cell
	return ((cell.y * City.WIDTH + cell.x) << 1) | (1 if node.channel == &"bore" else 0)


## The node a link from `node` reaches in direction `i`, or "" when the masks,
## bore mouths or shared-edge heights do not connect.
func _link_target(node: Dictionary, i: int) -> String:
	if (int(node.mask) & (1 << i)) == 0: return ""
	var other_cell: Vector2i = node.cell + DIRECTIONS[i]
	var other_key := _node_key(other_cell,node.channel)
	if node.channel == &"bore":
		var profile: Dictionary = _bores[node.cell]
		if (profile.entrance and DIRECTIONS[i] == -Vector2i(profile.inward)) or (profile.exit and DIRECTIONS[i] == Vector2i(profile.inward)):
			other_key = _node_key(other_cell,&"open")
	elif _bores.has(other_cell):
		var profile: Dictionary = _bores[other_cell]
		if (profile.entrance and DIRECTIONS[i] == Vector2i(profile.inward)) or (profile.exit and DIRECTIONS[i] == -Vector2i(profile.inward)):
			other_key = _node_key(other_cell,&"bore")
	if not _nodes.has(other_key): return ""
	var other: Dictionary = _nodes[other_key]
	if (int(other.mask) & (1 << ((i+2)%4))) == 0: return ""
	var edge := Vector2(.5,.5) + Vector2(DIRECTIONS[i])*.5
	if absf(node_point(node,edge).y - node_point(other,Vector2.ONE-edge).y) > .09: return ""
	return other_key


## Stop sharing containers with an adopted source before editing them.
func _detach_projection() -> void:
	var graph := CityTrafficGraph.new()
	graph.copy_from(_graph)
	_graph = graph
	_nodes = _nodes.duplicate(true)
	_links = _links.duplicate(true)
	_link_ranks = _link_ranks.duplicate()
	_ramp_keys = _ramp_keys.duplicate()
	_owns_projection = true


## Keys of a table whose keys are in ascending `rank` except for the last
## `added`, which were appended in ascending rank, merged into one ascending run.
static func _merge_ranked(table: Dictionary, added: int, rank: Callable) -> Dictionary:
	if added == 0: return table
	var keys: Array = table.keys()
	var split := keys.size() - added
	if split == 0 or int(rank.call(keys[split - 1])) < int(rank.call(keys[split])): return table
	var merged: Dictionary = {}
	var i := 0
	var j := split
	while i < split or j < keys.size():
		var take_tail := i >= split
		if not take_tail and j < keys.size(): take_tail = int(rank.call(keys[j])) < int(rank.call(keys[i]))
		var key: Variant = keys[j] if take_tail else keys[i]
		if take_tail: j += 1
		else: i += 1
		merged[key] = table[key]
	return merged


## Project only what a construction edit can change, when the previous
## projection is of this same City with identical terrain. The graph refreshes
## incrementally and names the cells whose entries or points may differ; with
## changed network codes and changed tunnel bores they bound every node,
## connection and centerline that can differ. Nodes there are rebuilt, links
## touching them are tested from both ends with the full scan's rule and ranked
## by the scan position that would first create them, and the tables keep the
## complete scan's order. Returns -1 to rebuild completely, -2 to rebuild
## completely with the already current graph, else whether the structure changed.
func _rebuild_incremental(city: City, structural: City, previous: Array, state: Array) -> int:
	if city == null or structural != city or _graph == null or _graph.city != city: return -1
	if previous.size() != state.size() or state.size() != 7: return -1
	for i: int in [0, 1, 5, 6]:
		if previous[i] != state[i]: return -1
	if not _owns_projection: _detach_projection()
	_graph.refresh()
	if _graph.last_change == CityTrafficGraph.CHANGE_FULL: return -2
	var before_codes: PackedInt32Array = previous[2]
	var codes: PackedInt32Array = state[2]
	var changed := CityTrafficGraph.changed_cells(before_codes, codes, previous[4], state[4])
	if _graph.last_change == CityTrafficGraph.CHANGE_NONE and not changed.is_empty(): return -1
	var dirty: Dictionary = {}
	if _graph.last_change == CityTrafficGraph.CHANGE_INCREMENTAL:
		for cell: Vector2i in _graph.last_dirty: dirty[cell] = true
	# Nodes exist only on network cells; every changed point is in the graph's
	# dirty cells. Changes between two non-network codes touch neither.
	var kinds := CityTrafficGraph.network_kinds()
	var tunnels := false
	for at: int in changed:
		if kinds[before_codes[at]] != 0 or kinds[codes[at]] != 0: dirty[Vector2i(at % City.WIDTH, at / City.WIDTH)] = true
		if NetworkShapes.is_tunnel(before_codes[at]) or NetworkShapes.is_tunnel(codes[at]): tunnels = true
	if tunnels:
		var bores := Tunnels.profiles(structural)
		CityTrafficGraph.diff_keys(_bores, bores, dirty)
		_bores = bores
	if dirty.is_empty(): return 0
	var order := PackedInt32Array()
	for cell: Vector2i in dirty:
		if cell.x >= 0 and cell.y >= 0 and cell.x < City.WIDTH and cell.y < City.HEIGHT: order.append(cell.y * City.WIDTH + cell.x)
	order.sort()
	var old_terminals: Array[String] = _ramp_keys.duplicate()
	old_terminals.sort()
	var old_exits: Array[String] = []
	for approach: Dictionary in _exits: old_exits.append(String(approach.key)+":"+str(approach.direction))
	old_exits.sort()
	# Drop every link of the nodes being replaced.
	var removed: Dictionary = {}
	for at: int in order:
		var cell := Vector2i(at % City.WIDTH, at / City.WIDTH)
		for channel: StringName in [&"open", &"bore"]:
			var key := _node_key(cell,channel)
			if not _nodes.has(key): continue
			for link: String in _nodes[key].links: removed[link] = true
	for link: String in removed:
		_links.erase(link)
	# Nodes with the full scan's rule; additions are appended in scan order.
	var added := 0
	for at: int in order:
		var cell := Vector2i(at % City.WIDTH, at / City.WIDTH)
		var code: int = codes[at]
		var kind: int = kinds[code]
		var open_key := _node_key(cell,&"open")
		if kind & CityTrafficGraph.KIND_ROAD and not kind & CityTrafficGraph.KIND_ONRAMP and not NetworkShapes.is_tunnel(code):
			var mask := CityNetworks3D.network_mask(code,NetworkShapes.Family.ROAD)
			var deck := _graph.bridge_deck(cell)
			if not deck.is_empty(): mask = 10 if deck.ew else 5
			if not _nodes.has(open_key): added += 1
			_add_node(cell,&"open",mask)
		else: _nodes.erase(open_key)
		var bore_key := _node_key(cell,&"bore")
		if _bores.has(cell):
			if not _nodes.has(bore_key): added += 1
			_add_node(cell,&"bore",10 if _bores[cell].inward.x != 0 else 5)
		else: _nodes.erase(bore_key)
	_nodes = _merge_ranked(_nodes, added, func(key: String) -> int: return _order(_nodes[key]))
	# Links with an end in the dirty cells, from nodes there and one cell out.
	var near: Array[String] = []
	var seen: Dictionary = {}
	for at: int in order:
		var cell := Vector2i(at % City.WIDTH, at / City.WIDTH)
		for step: Vector2i in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			for channel: StringName in [&"open", &"bore"]:
				var key := _node_key(cell+step,channel)
				if _nodes.has(key) and not seen.has(key):
					seen[key] = true
					near.append(key)
	var candidates: Dictionary = {}
	for key: String in near:
		var node: Dictionary = _nodes[key]
		for i: int in 4:
			var other_key := _link_target(node,i)
			if other_key.is_empty(): continue
			var other: Dictionary = _nodes[other_key]
			if not dirty.has(node.cell) and not dirty.has(other.cell): continue
			var rank := _order(node)*4+i
			var link := link_key(node.cell,node.channel,other.cell,other.channel)
			if not candidates.has(link) or rank < int(candidates[link][0]): candidates[link] = [rank,key,other_key]
	var ranked := PackedInt64Array()
	var by_rank: Dictionary = {}
	for link: String in candidates:
		var rank: int = candidates[link][0]
		ranked.append(rank)
		by_rank[rank] = link
	ranked.sort()
	for link: String in removed:
		if not candidates.has(link): _link_ranks.erase(link)
	var appended := 0
	for rank: int in ranked:
		var link: String = by_rank[rank]
		var entry: Array = candidates[link]
		_links[link] = _link_value(entry[1],entry[2])
		_link_ranks[link] = rank
		appended += 1
	_links = _merge_ranked(_links, appended, func(link: String) -> int: return int(_link_ranks[link]))
	# Incident lists in ascending rank, as the scan appends them.
	for key: String in near:
		var node: Dictionary = _nodes[key]
		var incident: Array = []
		for link: String in node.links:
			if not removed.has(link): incident.append(link)
		for link: String in candidates:
			var entry: Array = candidates[link]
			if (entry[1] == key or entry[2] == key) and not incident.has(link): incident.append(link)
		incident.sort_custom(func(a: String, b: String) -> bool: return int(_link_ranks[a]) < int(_link_ranks[b]))
		node.links = incident
	var no_exits: Array[Dictionary] = []
	_exits = no_exits
	_build_exits(structural)
	var changed_structure := false
	for link: String in removed:
		if not candidates.has(link): changed_structure = true
	for link: String in candidates:
		if not removed.has(link): changed_structure = true
	var terminals: Array[String] = _ramp_keys.duplicate()
	terminals.sort()
	var exits: Array[String] = []
	for approach: Dictionary in _exits: exits.append(String(approach.key)+":"+str(approach.direction))
	exits.sort()
	return 1 if changed_structure or terminals != old_terminals or exits != old_exits else 0
