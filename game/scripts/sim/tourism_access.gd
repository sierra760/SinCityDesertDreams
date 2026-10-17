# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Derived exact transport evidence. Rebuilt only by simulation hooks. Strong
## components share route work across every frontage, venue and retail recipient.
class_name TourismAccess
extends RefCounted

const PortSystem := preload("res://scripts/sim/port_system.gd")

const ROUTE_WORK := 32768
const ACTIVE_SEARCHES := 8
const CACHE_ENTRIES := 1048576
const CAPACITIES := {"road":500,"highway":1500,"rail":2000,"airport":6000,"harbor":1500}
var version := 0
var _city: City
var _layers: Array = []
var _structure: Array = []
var _index_key: Array = []
static var _id_interest := PackedByteArray()
static var _graph_ids := PackedInt32Array()

static func _build_id_tables() -> void:
	if not _id_interest.is_empty(): return
	_id_interest.resize(Buildings.COUNT)
	_graph_ids.resize(Buildings.COUNT)
	for id in Buildings.COUNT:
		var key := Buildings.key(id)
		var bits := 0
		if RewardParams.ARCOLOGIES.has(key) or key == &"com_corner_store": bits |= 1
		if TransportParams.is_origin(id): bits |= 2
		_id_interest[id] = bits
		_graph_ids[id] = id if TransportParams.surface_class(id) != 0 else 0

static func _graph_layer(bld: PackedInt32Array) -> PackedInt32Array:
	_build_id_tables()
	var out := PackedInt32Array()
	out.resize(bld.size())
	for i in bld.size(): out[i] = _graph_ids[bld[i]]
	return out
var _structure_indexed := false
var _layers_version_pending := false
var _transport := TransportSystem.new()
var _ports := PortSystem.new()
var _graph := {}
var _reverse := {}
var _trip_searches := {}
var _resident_states := PackedInt32Array()
const TRIP_TREES := 8
const TRIP_CACHE_ENTRIES := 262144
var _component := {}
var _dag: Array[PackedInt32Array] = []
var _closures := {}
var _pending := {}
var _waiting := {}
var _cache_entries := 0
var _pass_budget := ROUTE_WORK
var _remaining := ROUTE_WORK
var _gateways: Array[Dictionary] = []
var _venues := {}
var _venue_rects := {}
var _frontages := {}
var _resident_components := {}
## target_entrances(rect) reads only the surface-class layer inside rect.grow(ENTRANCE_REACH);
## entries survive structure changes outside that ring.
var _entrance_cache := {}
## Edge mouths of the current graph (before port gateways); rebuilt with the graph.
var _mouths: Array[Dictionary] = []
var _stats := {"graph_builds":0,"graph_states":0,"graph_edges":0,"route_work":0,"pending_sources":0,"cache_entries":0,"trip_evictions":0}

func refresh(ctx: SimContext, work_budget: int = ROUTE_WORK) -> void:
	var city := ctx.city
	var flooded := PackedInt32Array()
	for p: Variant in city.flood_overlay:
		if p is Vector2i and city.in_bounds(p.x,p.y): flooded.append(p.y*City.WIDTH+p.x)
	flooded.sort()
	var layers: Array = [city.building.data,city.zone.data,city.underground.data,city.altitude.data,city.terrain.data,city.flags.data,flooded]
	_pass_budget = clampi(work_budget,0,ROUTE_WORK)
	_remaining = _pass_budget
	if _city == city and _layers == layers and _pending.is_empty() and _waiting.is_empty(): return
	if _city != city or _layers != layers:
		# Pure graph inputs: surface-class identity (TransportSystem reads
		# buildings only through _surface and station equality), tunnels, subway.
		var structure: Array = [_graph_layer(city.building.data),city.underground.data,city.altitude.data]
		var same_structure := _city == city and structure == _structure
		var index_key: Array = [city.building.data,city.zone.data]
		if not same_structure or index_key != _index_key:
			_index_key = index_key.duplicate(true)
			_structure_indexed = false
		_city = city
		_layers = layers.duplicate(true)
		if not same_structure:
			_invalidate_entrances(city, structure[0])
			var previous_structure := _structure
			# Packed layers are references: retain a detached copy (raw put() edits mutate in place).
			_structure = structure.duplicate(true)
			if previous_structure.size() == 3 and not _graph.is_empty():
				_graph = _transport.target_graph_update(city, _graph, previous_structure[0], previous_structure[1], previous_structure[2], _structure[0])
			else:
				_graph = _transport.target_graph(city)
			_reverse.clear()
			for state: int in _graph: _reverse[state] = PackedInt32Array()
			for state: int in _graph:
				for next: int in _graph[state]: _reverse[next].append(state)
			_frontages.clear()
			_structure_indexed = false
		_layers_version_pending = true
		_trip_searches.clear()
		_closures.clear()
		_pending.clear()
		_waiting.clear()
		_cache_entries = 0
		if not same_structure:
			_components()
			_mouths = _graph_mouths()
		# Tourism reads only port gateways; the private instance never spawns
		# vehicles, so skip PortSystem.setup's city-centre scan.
		_ports._ctx = ctx
		_ports._ports_valid = false
		_discover_gateways()
	if not _structure_indexed:
		_structure_indexed = true
		_resident_components.clear()
		_resident_states.clear()
		var resident_seen := {}
		_venue_rects.clear()
		_build_id_tables()
		var bld := city.building.data
		var zn := city.zone.data
		for i in bld.size():
			var id := bld[i]
			var interest := _id_interest[id]
			if interest == 0: continue
			if (interest & 1) != 0 and UtilityParams.is_anchor_tile(bld,zn,i):
				var at := PortSystem._tile_of(i)
				_venue_rects[at] = Rect2i(at,Buildings.size(id))
			if (interest & 2) != 0 and UtilityParams.is_anchor_tile(bld,zn,i):
				var at := PortSystem._tile_of(i)
				var rect := Rect2i(at,Buildings.size(id))
				var entrances: PackedInt32Array
				if _entrance_cache.has(rect): entrances = _entrance_cache[rect]
				else:
					entrances = _transport.target_entrances(city,rect)
					_entrance_cache[rect] = entrances
				for c in _seeds(rect,entrances): _resident_components[c] = true
				for state in entrances: resident_seen[state] = true
		_resident_states = PackedInt32Array(resident_seen.keys())
		_resident_states.sort()
	if _layers_version_pending:
		_layers_version_pending = false
		version += 1
		_stats.graph_builds += 1
	# Continue older pending searches first, before canonical new requests.
	for source: int in _pending.keys():
		_closure(source)
		if _remaining == 0: break
	for source: int in _waiting.keys():
		if _remaining == 0: break
		_closure(source)
	_venues.clear()
	for at: Vector2i in _venue_rects: _venues[at] = _access(_venue_rects[at])
	_stats.route_work = _pass_budget - _remaining
	_stats.pending_sources = _pending.size()+_waiting.size()
	_stats.cache_entries = _cache_entries

## Kosaraju's iterative passes avoid recursion on a map-length highway/rail.
func _components() -> void:
	var reverse := {}
	var visited := {}
	var order := PackedInt32Array()
	var edges := 0
	for state: int in _graph:
		if not reverse.has(state): reverse[state] = PackedInt32Array()
		for next: int in _graph[state]:
			if not reverse.has(next): reverse[next] = PackedInt32Array()
			reverse[next].append(state)
			edges += 1
	for state: int in _graph:
		if visited.has(state): continue
		var stack: Array = [[state,0]]
		visited[state] = true
		while not stack.is_empty():
			var frame: Array = stack[-1]
			var neighbors: PackedInt32Array = _graph.get(frame[0],PackedInt32Array())
			if frame[1] == neighbors.size():
				order.append(frame[0])
				stack.pop_back()
				continue
			var next := neighbors[frame[1]]
			frame[1] += 1
			if not visited.has(next):
				visited[next] = true
				stack.append([next,0])
	_component.clear()
	_dag.clear()
	order.reverse()
	for state in order:
		if _component.has(state): continue
		var id := _dag.size()
		_dag.append(PackedInt32Array())
		var stack := PackedInt32Array([state])
		_component[state] = id
		while not stack.is_empty():
			var node := stack[-1]
			stack.resize(stack.size()-1)
			for previous: int in reverse.get(node,PackedInt32Array()):
				if not _component.has(previous):
					_component[previous] = id
					stack.append(previous)
	for state: int in _graph:
		var a: int = _component[state]
		for next: int in _graph[state]:
			var b: int = _component[next]
			if a != b and not _dag[a].has(b): _dag[a].append(b)
	_stats.graph_states = _graph.size()
	_stats.graph_edges = edges

func _closure(source: int) -> Dictionary:
	if _closures.has(source): return _closures[source]
	if not _pending.has(source):
		if _pending.size() >= ACTIVE_SEARCHES or _remaining == 0:
			_waiting[source] = true
			return {}
		_waiting.erase(source)
		_pending[source] = {"queue":PackedInt32Array([source]),"head":0,"seen":{source:true}}
	var search: Dictionary = _pending[source]
	while search.head < search.queue.size() and _remaining > 0:
		var current: int = search.queue[search.head]
		search.head += 1
		_remaining -= 1
		for next in _dag[current]:
			if not search.seen.has(next):
				search.seen[next] = true
				search.queue.append(next)
	if search.head == search.queue.size():
		while _cache_entries + search.seen.size() > CACHE_ENTRIES and not _closures.is_empty():
			var oldest: int = _closures.keys()[0]
			_cache_entries -= _closures[oldest].size()
			_closures.erase(oldest)
		_closures[source] = search.seen
		_cache_entries += search.seen.size()
		_pending.erase(source)
		version += 1
		return search.seen
	return {}

func _seeds(rect: Rect2i, entrances: Variant = null) -> PackedInt32Array:
	if _frontages.has(rect): return _frontages[rect]
	var result := PackedInt32Array()
	for state in (entrances if entrances != null else _transport.target_entrances(_city,rect)):
		var c := int(_component.get(state,-1))
		if c >= 0 and not result.has(c): result.append(c)
	_frontages[rect] = result
	return result

func _invalidate_entrances(city: City, graph_layer: PackedInt32Array) -> void:
	if _city != city or _structure.is_empty() or _entrance_cache.is_empty():
		_entrance_cache.clear()
		return
	var old: PackedInt32Array = _structure[0]
	if old == graph_layer: return
	var lo := Vector2i(City.WIDTH, City.HEIGHT)
	var hi := Vector2i(-1, -1)
	for i in old.size():
		if old[i] != graph_layer[i]:
			var p := PortSystem._tile_of(i)
			lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
			hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
	var changed := Rect2i(lo, hi - lo + Vector2i.ONE)
	for rect: Rect2i in _entrance_cache.keys():
		if rect.grow(TransportParams.ENTRANCE_REACH).intersects(changed): _entrance_cache.erase(rect)

func _discover_gateways() -> void:
	_gateways.clear()
	for mouth in _mouths: _gateways.append(mouth.duplicate(true))
	_gateways.append_array(_ports.call("tourism_gateways"))
	for gateway in _gateways:
		var components := {}
		for state: int in gateway.states:
			if _component.has(state): components[_component[state]] = true
		gateway["components"] = components

func _graph_mouths() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var mouths := {}
	for state: int in _graph:
		@warning_ignore("integer_division")
		var mode := state / TransportSystem.TILES
		if mode not in [TransportSystem.MODE_CAR,TransportSystem.MODE_HIGHWAY,TransportSystem.MODE_RAIL]: continue
		var tile := PortSystem._tile_of(state % TransportSystem.TILES)
		var kind: String = ["road","highway","","rail"][mode]
		var sides: Array[String] = []
		if tile.x == 0: sides.append("west")
		if tile.x == City.WIDTH-1: sides.append("east")
		if tile.y == 0: sides.append("north")
		if tile.y == City.HEIGHT-1: sides.append("south")
		for side in sides:
			var id: String = side+":"+kind
			if not mouths.has(id): mouths[id] = {"id":id,"kind":kind,"capacity":CAPACITIES[kind],"states":PackedInt32Array(),"tiles":{}}
			mouths[id].states.append(state)
			mouths[id].tiles[tile] = true
	# A surface containing both kinds is one highway mouth, not two seats.
	for side in ["north","east","south","west"]:
		var road: Dictionary = mouths.get(side+":road",{})
		var highway: Dictionary = mouths.get(side+":highway",{})
		if road.is_empty() or highway.is_empty(): continue
		var remaining := PackedInt32Array()
		for state in road.states:
			if not highway.tiles.has(PortSystem._tile_of(state % TransportSystem.TILES)): remaining.append(state)
			else: highway.states.append(state)
		if remaining.is_empty(): mouths.erase(side+":road")
		else: road.states = remaining
	var ids := mouths.keys()
	ids.sort()
	for id: String in ids: result.append(mouths[id])
	return result

func _access(rect: Rect2i) -> Dictionary:
	var sources := _seeds(rect)
	var reachable := {}
	var pending := false
	for source in sources:
		var closure := _closure(source)
		if closure.is_empty(): pending = true
		reachable.merge(closure)
	var ids: Array[String] = []
	var kinds := {}
	var capacity := 0
	for gateway in _gateways:
		for c: int in gateway.components:
			if reachable.has(c):
				ids.append(gateway.id)
				kinds[gateway.kind] = true
				capacity += int(gateway.capacity)
				break
	var local := false
	for c: int in _resident_components:
		if reachable.has(c):
			local = true
			break
	return {"external_reachable":not ids.is_empty(),"local_reachable":local,
		"access_status":"reachable" if not ids.is_empty() else ("pending" if pending else "disconnected"),
		"access_reason":"Connected external gateway" if not ids.is_empty() else ("Route work pending" if pending else "No connected external gateway"),
		"arrival_capacity":capacity,"gateway_ids":ids,"gateway_types":kinds.keys()}

func venue_access(anchor: Vector2i) -> Dictionary:
	return _venues.get(anchor,{"external_reachable":false,"local_reachable":false,"access_status":"disconnected", "access_reason":"No venue route", "arrival_capacity":0,"gateway_ids":[],"gateway_types":[]}).duplicate(true)

func district_connected(a: Rect2i,b: Rect2i) -> bool:
	var targets := _seeds(b)
	for source in _seeds(a):
		if targets.has(source): return true
		var closure := _closure(source)
		for target in targets:
			if closure.has(target): return true
	return false

func gateways() -> Array[Dictionary]:
	return _gateways.duplicate(true)

func report() -> Dictionary:
	var result := _stats.duplicate()
	result.route_work = _pass_budget-_remaining
	result.pending_sources = _pending.size()+_waiting.size()
	result.cache_entries = _cache_entries
	result["trip_trees"] = _trip_searches.size()
	result["trip_cache_reserved"] = _trip_searches.size()*_graph.size()
	result["trip_cache_entries"] = 0
	for tree: Dictionary in _trip_searches.values(): result.trip_cache_entries += tree.parent.size()
	result["gateway_count"] = _gateways.size()
	result["arrival_capacity"] = 0
	for gateway in _gateways: result.arrival_capacity += int(gateway.capacity)
	return result

## Reusable explicit path evidence for the transport pass, never a report read.
func route(anchor: Vector2i, gateway_id: String, budget: int = 4096) -> Dictionary:
	for gateway in _gateways:
		if gateway.id == gateway_id:
			var seeds := _transport.target_entrances(_city,Rect2i(anchor,Buildings.size(_city.building_at(anchor.x,anchor.y))))
			return _transport.route_to_targets(_city,seeds,gateway.states,budget,_graph)
	return {"status":"disconnected","path":PackedInt32Array(),"work":0}


## Validate only completed identities/counts, never current graph availability.
## Old phase saves retain an empty optional ledger without changing business.
static func decode_accepted(input: Dictionary, block: Dictionary, current_month: int = -1) -> Dictionary:
	if input.is_empty(): return {"ok":true,"value":{}}
	if input.size() not in [2,3] or (input.size() == 3 and not input.has("transport")) or not TourismState._integer(input.get("month_id"),0,int(block.get("last_month",-1))): return {"ok":false}
	if int(input.month_id) != int(block.get("last_month",-1)): return {"ok":false}
	var rows: Variant = input.get("rows")
	if not rows is Array or rows.size() > TransportSystem.TILES: return {"ok":false}
	var known := {}
	for row: Dictionary in block.get("activity",{}).get("rows",[]): known[int(row.instance)] = row
	if rows.size() != known.size(): return {"ok":false}
	var seen := {}
	var clean: Array[Dictionary] = []
	var gateway_totals := {}
	for value: Variant in rows:
		if not value is Dictionary or value.size() != 5: return {"ok":false}
		if not TourismState._integer(value.get("instance"),1,TourismState.MAX_INSTANCE-1): return {"ok":false}
		var instance := int(value.instance)
		if not known.has(instance) or seen.has(instance): return {"ok":false}
		seen[instance] = true
		var business: Dictionary = known[instance]
		var key := StringName(business.key)
		if not TourismState._integer(value.get("overnight_arrivals"),0,(TourismParams.guest_capacity(key)+1)/2): return {"ok":false}
		for field in ["local_day_visitors","external_day_visitors"]:
			if not TourismState._integer(value.get(field),0,TourismParams.day_capacity(key)): return {"ok":false}
		if int(value.local_day_visitors)+int(value.external_day_visitors) != int(business.day_visitors): return {"ok":false}
		if int(value.overnight_arrivals) > int(business.guest_half_months): return {"ok":false}
		var gateways: Variant = value.get("gateways")
		if not gateways is Array or gateways.size() > TransportSystem.TILES: return {"ok":false}
		var ids := {}
		var total := 0
		var entries: Array[Dictionary] = []
		for gateway: Variant in gateways:
			if not gateway is Dictionary or gateway.size() != 2 or not gateway.get("id") is String: return {"ok":false}
			var id: String = gateway.id
			var capacity := gateway_capacity(id)
			if capacity == 0 or ids.has(id) or not TourismState._integer(gateway.get("count"),1,capacity): return {"ok":false}
			ids[id] = true
			var count := int(gateway.count)
			gateway_totals[id] = int(gateway_totals.get(id,0))+count
			if int(gateway_totals[id]) > capacity: return {"ok":false}
			total += count
			entries.append({"id":id,"count":count})
		if total != int(value.overnight_arrivals)+int(value.external_day_visitors): return {"ok":false}
		clean.append({"instance":instance,"overnight_arrivals":int(value.overnight_arrivals),
			"local_day_visitors":int(value.local_day_visitors),"external_day_visitors":int(value.external_day_visitors),"gateways":entries})
	var value := {"month_id":int(input.month_id),"rows":clean}
	if input.has("transport"):
		var trips := decode_transport(input.transport,int(input.month_id),current_month,block,gateway_totals)
		if not trips.ok: return {"ok":false}
		value["transport"] = trips.value
	return {"ok":true,"value":value}

static func gateway_capacity(id: String) -> int:
	var parts := id.split(":")
	if parts.size() != 2: return 0
	if parts[0] in ["north","east","south","west"]:
		return int(CAPACITIES.get(parts[1],0)) if parts[1] in ["road","highway","rail"] else 0
	if parts[0] not in ["airport","harbor"] or not parts[1].is_valid_int(): return 0
	var index := int(parts[1])
	if index < 0 or index >= TransportSystem.TILES or str(index) != parts[1]: return 0
	return CAPACITIES[parts[0]]


## Pass-local derived caches make a cold restore and uninterrupted play perform
## identical bounded work; sharing still amortizes every route in that pass.
func begin_trip_pass() -> void:
	_trip_searches.clear()
	_stats.trip_evictions = 0

## Shared reverse frontiers amortize explicit path work across venues. These
## derived maps never survive saves or raw layer changes; queued accepted jobs do.
@warning_ignore("integer_division")
func trip_route(anchor: Vector2i, gateway_id: String, budget: int, path_budget: int = TransportSystem.STATES) -> Dictionary:
	if path_budget <= 0: return {"status":"pending","path":PackedInt32Array(),"work":0,"edges":0,"path_work":0}
	var targets := PackedInt32Array()
	if gateway_id == "local": targets = _resident_states
	else:
		for gateway in _gateways:
			if gateway.id != gateway_id: continue
			targets = gateway.states.duplicate()
			# A bus arriving at the same physical road mouth is a real transit trip.
			for state in gateway.states:
				if state / TransportSystem.TILES == TransportSystem.MODE_CAR:
					var bus: int = TransportSystem.MODE_BUS*TransportSystem.TILES+state%TransportSystem.TILES
					if _graph.has(bus): targets.append(bus)
	if gateway_id == "local":
		for state in _resident_states:
			if state / TransportSystem.TILES == TransportSystem.MODE_CAR:
				var bus := TransportSystem.MODE_BUS*TransportSystem.TILES+state%TransportSystem.TILES
				if _graph.has(bus): targets.append(bus)
	if targets.is_empty(): return {"status":"disconnected","path":PackedInt32Array(),"work":0,"edges":0,"path_work":0}
	if not _trip_searches.has(gateway_id):
		while not _trip_searches.is_empty() and (_trip_searches.size() >= TRIP_TREES or (_trip_searches.size()+1)*_graph.size() > TRIP_CACHE_ENTRIES):
			var oldest: String = _trip_searches.keys()[0]
			_trip_searches.erase(oldest)
			_stats.trip_evictions += 1
		var parent := {}
		var queue := PackedInt32Array()
		for state in targets:
			if _graph.has(state) and not parent.has(state):
				parent[state] = -1
				queue.append(state)
		_trip_searches[gateway_id] = {"parent":parent,"queue":queue,"head":0}
	var tree: Dictionary = _trip_searches[gateway_id]
	var seeds := _transport.target_entrances(_city,Rect2i(anchor,Buildings.size(_city.building_at(anchor.x,anchor.y))))
	var stations := PackedInt32Array()
	for seed in seeds:
		if seed / TransportSystem.TILES == TransportSystem.MODE_STATION: stations.append(seed)
	var preferred := stations if not stations.is_empty() else seeds
	var work := 0
	var edges := 0
	while true:
		var found := -1
		for seed in preferred:
			if tree.parent.has(seed):
				found = seed
				break
		if found >= 0:
			var path := PackedInt32Array()
			while found >= 0:
				if path.size() >= path_budget: return {"status":"pending","path":PackedInt32Array(),"work":work,"edges":edges,"path_work":path.size()}
				path.append(found)
				found = tree.parent[found]
			return {"status":"reachable","path":path,"work":work,"edges":edges,"path_work":path.size()}
		if tree.head == tree.queue.size():
			if preferred != seeds:
				preferred = seeds
				continue
			return {"status":"disconnected","path":PackedInt32Array(),"work":work,"edges":edges,"path_work":0}
		if work >= budget: return {"status":"pending","path":PackedInt32Array(),"work":work,"edges":edges,"path_work":0}
		var state: int = tree.queue[tree.head]
		tree.head += 1
		work += 1
		for previous: int in _reverse[state]:
			edges += 1
			if not tree.parent.has(previous):
				tree.parent[previous] = state
				tree.queue.append(previous)

	return {"status":"disconnected","path":PackedInt32Array(),"work":0,"edges":0,"path_work":0}

## Detached historical queue validation. Job weights are their accepted cohort,
## never a demand forecast; only the representative route is sampled.
static func decode_transport(input: Variant, last_month: int, current_month: int = -1, block: Dictionary = {}, accepted_totals: Dictionary = {}) -> Dictionary:
	if not input is Dictionary or input.size() != 9: return {"ok":false}
	for field in ["cursor","gateway_cursor","processed_month","pass_month","pending_fare_riders"]:
		var low := -1 if field in ["processed_month","pass_month"] else 0
		var high := maxi(last_month,current_month) if field == "pass_month" else (last_month if field == "processed_month" else TourismParams.MAX_COUNT)
		if not TourismState._integer(input.get(field),low,high): return {"ok":false}
	if int(input.processed_month) > int(input.pass_month): return {"ok":false}
	if not TourismState._integer(block.get("state",{}).get("next_instance"),1,TourismState.MAX_INSTANCE): return {"ok":false}
	var rotations: Variant = input.get("rotations")
	if not rotations is Dictionary or rotations.size() > 2*TransportSystem.TILES+13: return {"ok":false}
	for id: Variant in rotations:
		if not id is String or (id != "local" and gateway_capacity(id) == 0) or not TourismState._integer(rotations[id],0,TourismParams.MAX_COUNT): return {"ok":false}
	var pending: Variant = input.get("pending")
	if not pending is Array or pending.size() > TransportSystem.TOURIST_QUEUE: return {"ok":false}
	var clean: Dictionary = input.duplicate(true)
	pending = clean.pending
	var ids := {}
	var identities := {}
	for row: Dictionary in block.get("state",{}).get("records",[]): identities[int(row.instance)] = row
	for row: Dictionary in block.get("activity",{}).get("rows",[]): identities[int(row.instance)] = row
	var local_total := 0
	for row: Dictionary in block.get("features",{}).get("access",{}).get("rows",[]): local_total += int(row.local_day_visitors)
	var prior := -1
	var cohort_totals := {}
	var pending_weight := 0
	for job: Variant in pending:
		if not job is Dictionary or job.size() != 8: return {"ok":false}
		if not TourismState._integer(job.get("period"),0,int(input.processed_month)): return {"ok":false}
		if int(job.period) < prior: return {"ok":false}
		prior = int(job.period)
		if not TourismState._integer(job.get("instance"),1,int(block.get("state",{}).get("next_instance",TourismState.MAX_INSTANCE))-1): return {"ok":false}
		if not job.get("key") is String or (StringName(job.key) != &"com_corner_store" and not RewardParams.ARCOLOGIES.has(StringName(job.key))): return {"ok":false}
		var at: Variant = job.get("anchor")
		if not at is Array or at.size() != 2: return {"ok":false}
		for v: Variant in at:
			if not TourismState._integer(v,0,City.WIDTH-1): return {"ok":false}
		var size := Buildings.size(Buildings.id_of(StringName(job.key)))
		if int(at[0])+size.x > City.WIDTH or int(at[1])+size.y > City.HEIGHT: return {"ok":false}
		if identities.has(int(job.instance)):
			var identity: Dictionary = identities[int(job.instance)]
			if not identity.get("key") is String or not identity.get("anchor") is Array or identity.anchor.size() != 2: return {"ok":false}
			for coordinate: Variant in identity.anchor:
				if not TourismState._integer(coordinate,0,City.WIDTH-1): return {"ok":false}
			if identity.key != job.key or int(identity.anchor[0]) != int(at[0]) or int(identity.anchor[1]) != int(at[1]): return {"ok":false}
		if not job.get("gateway") is String or (job.gateway != "local" and gateway_capacity(job.gateway) == 0): return {"ok":false}
		var bound := TransportSystem.TILES*TourismParams.MAX_DAY_CAPACITY if job.gateway == "local" else gateway_capacity(job.gateway)
		if not TourismState._integer(job.get("source_count"),1,bound) or not TourismState._integer(job.get("weight"),int(job.source_count),int(job.source_count)): return {"ok":false}
		if not TourismState._integer(job.get("cohort"),0,TransportSystem.TOURIST_ORIGINS-1): return {"ok":false}
		var id := str(job.period)+":"+str(job.cohort)
		if ids.has(id): return {"ok":false}
		ids[id] = true
		var cohort_id := str(job.period)+":"+String(job.gateway)
		cohort_totals[cohort_id] = int(cohort_totals.get(cohort_id,0))+int(job.weight)
		if int(cohort_totals[cohort_id]) > bound: return {"ok":false}
		if int(job.period) == last_month and int(cohort_totals[cohort_id]) > (local_total if job.gateway == "local" else int(accepted_totals.get(job.gateway,0))): return {"ok":false}
		pending_weight += int(job.weight)
		for field in ["period","instance","source_count","weight","cohort"]: job[field] = int(job[field])
		job.anchor = [int(at[0]),int(at[1])]
	if not input.get("report") is Dictionary: return {"ok":false}
	var report := TransportSystem.decode_tourism_report(input.report)
	if not report.ok: return {"ok":false}
	if report.value.month_id != int(input.pass_month) or report.value.pending != pending_weight or report.value.pending_jobs != pending.size(): return {"ok":false}
	if report.value.oldest_pending_month != (-1 if pending.is_empty() else int(pending[0].period)): return {"ok":false}
	var fares := decode_fare_evidence(input.get("fare_evidence"),int(input.pass_month),report.value)
	if not fares.ok or fares.pending != int(input.pending_fare_riders): return {"ok":false}
	if int(input.pass_month) == -1:
		if int(input.processed_month) != -1 or report.value != TransportSystem.neutral_tourism_report(): return {"ok":false}
		if int(input.cursor) != 0 or int(input.gateway_cursor) != 0 or not rotations.is_empty() or not pending.is_empty(): return {"ok":false}
	elif int(input.processed_month) < 0: return {"ok":false}
	clean.fare_evidence = fares.value
	clean.report = report.value
	for id: String in clean.rotations: clean.rotations[id] = int(clean.rotations[id])
	for field in ["cursor","gateway_cursor","processed_month","pass_month","pending_fare_riders"]: clean[field] = int(clean[field])
	return {"ok":true,"value":clean}


## The completed period ledger establishes the monetary claim before adoption.
## An older compacted interval retains exact outstanding mode/claim sums; it
## cannot overlap retained periods or replace the latest report evidence.
static func decode_fare_evidence(input: Variant, pass_month: int, report: Dictionary) -> Dictionary:
	if not input is Dictionary or input.size() != 2 or not input.get("carry") is Dictionary: return {"ok":false}
	var periods: Variant = input.get("periods")
	if not periods is Array or periods.size() > TransportSystem.TOURIST_FARE_PERIODS: return {"ok":false}
	if pass_month == -1:
		return {"ok":true,"pending":0,"value":{"carry":{},"periods":[]}} if input.carry.is_empty() and periods.is_empty() else {"ok":false}
	if periods.is_empty(): return {"ok":false}
	var entries: Array = []
	if not input.carry.is_empty(): entries.append(input.carry)
	entries.append_array(periods)
	var clean: Array[Dictionary] = []
	var previous := -1
	var pending := 0
	for index in entries.size():
		var entry: Variant = entries[index]
		if not entry is Dictionary or entry.size() != 5: return {"ok":false}
		if not TourismState._integer(entry.get("first_month"),previous+1,pass_month) or not TourismState._integer(entry.get("last_month"),int(entry.first_month),pass_month): return {"ok":false}
		var is_carry: bool = index == 0 and not input.carry.is_empty()
		if not is_carry and int(entry.first_month) != int(entry.last_month): return {"ok":false}
		if not TourismState._integer(entry.get("completed"),0,TourismParams.MAX_COUNT): return {"ok":false}
		var modes: Variant = entry.get("modes")
		if not modes is Dictionary or modes.size() != 3: return {"ok":false}
		var decoded_modes := {}
		var earned := 0
		for mode in ["bus","rail","subway"]:
			if not TourismState._integer(modes.get(mode),0,int(entry.completed)): return {"ok":false}
			decoded_modes[mode] = int(modes[mode])
			earned += int(modes[mode])
		if not TourismState._integer(entry.get("claimed"),0,earned): return {"ok":false}
		# Only the latest pass may retain fully claimed/zero-earning evidence.
		if index < entries.size()-1 and int(entry.claimed) == earned: return {"ok":false}
		pending += earned-int(entry.claimed)
		previous = int(entry.last_month)
		clean.append({"first_month":int(entry.first_month),"last_month":int(entry.last_month),
			"completed":int(entry.completed),"modes":decoded_modes,"claimed":int(entry.claimed)})
	var latest: Dictionary = clean[-1]
	if int(latest.last_month) != pass_month or int(latest.completed) != int(report.completed): return {"ok":false}
	for mode in ["bus","rail","subway"]:
		if int(latest.modes[mode]) != int(report.modes[mode]): return {"ok":false}
	var carry: Dictionary = {}
	if not input.carry.is_empty(): carry = clean.pop_front()
	return {"ok":true,"pending":pending,"value":{"carry":carry,"periods":clean}}
