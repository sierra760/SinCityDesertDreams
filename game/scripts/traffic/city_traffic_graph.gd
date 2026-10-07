# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Reciprocal traffic routes and local demand, derived read-only from the city.
class_name CityTrafficGraph
extends RefCounted

const INVALID := Vector2i(-1, -1)
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
var city: City
var revision := 0
var developed := 0
var facilities: Dictionary = {}
var _signature: Variant = null
var _traffic_signature: Variant = null
var _building_signature: Variant = null
var _building_snapshot := PackedByteArray()
var _axis_cells: Array[Vector2i] = []
var _axis_signature := 0
var _nodes: Dictionary = {}
var _decks: Dictionary = {}
var _approaches: Dictionary = {}
const BridgeApproaches := preload("res://scripts/view/city_bridge_approaches_3d.gd")
const ScanTables := preload("res://scripts/sim/data/public_scan_tables.gd")
var _demand: Dictionary = {}
var _lists: Dictionary = {}
var _ground: Dictionary = {}
var _highway_stencils: Dictionary = {}
var _centers: Dictionary = {}
## What the last refresh() did to nodes, routes and sampled points: NONE (at
## most demand, facilities or congestion), INCREMENTAL (only the cells in
## `last_dirty` may differ) or FULL (a complete projection or an adoption).
const CHANGE_NONE := 0
const CHANGE_INCREMENTAL := 1
const CHANGE_FULL := 2
var last_change := CHANGE_NONE
## After an INCREMENTAL refresh: the cells whose node entries or points may
## have changed, and the raw indices whose building code or axis bit changed.
var last_dirty: Dictionary = {}
var last_changed_codes := PackedInt32Array()
## The detached raw inputs (see _raw_inputs) that the current state is the
## projection of, and the City instance they were read from.
var _state_inputs: Array = []
var _state_city_id := 0
## Above this many changed cells a complete projection is cheaper.
const INCREMENTAL_LIMIT := 4096
## Read-only default for lookups of absent nodes.
const _NO_ENTRY := {}
## Per-code classification, computed once for every building code from the
## NetworkShapes predicates.
const KIND_ONRAMP := 1
const KIND_AXIS := 2
const KIND_TUNNEL_PORTAL := 4
const KIND_ROAD := 8
const KIND_HIGHWAY := 16
const KIND_RAIL := 32
static var _code_kinds := PackedByteArray()
## KIND_* bits for every building code.
static func network_kinds() -> PackedByteArray:
	if _code_kinds.is_empty():
		_code_kinds.resize(Buildings.COUNT)
		for code: int in Buildings.COUNT:
			var kind := 0
			if NetworkShapes.is_onramp(code): kind |= KIND_ONRAMP
			if NetworkShapes.is_onramp(code) or CityNetworks3D.bridge_family(code) != NetworkShapes.Family.NONE: kind |= KIND_AXIS
			if NetworkShapes.is_tunnel(code) or NetworkShapes.is_subway_portal(code): kind |= KIND_TUNNEL_PORTAL
			if NetworkShapes.in_family(code, NetworkShapes.Family.ROAD): kind |= KIND_ROAD
			if NetworkShapes.in_family(code, NetworkShapes.Family.HIGHWAY): kind |= KIND_HIGHWAY
			if NetworkShapes.in_family(code, NetworkShapes.Family.RAIL): kind |= KIND_RAIL
			_code_kinds[code] = kind
	return _code_kinds
var highways := preload("res://scripts/traffic/city_traffic_highways.gd").new()
const HighwayHeight := preload("res://scripts/view/city_highway_height_3d.gd")

func bind_city(value: City) -> void:
	if city == value: return
	city = value
	_signature = null
	_traffic_signature = null
	_axis_cells.clear()
	_ground.clear()
	_highway_stencils.clear()
	_centers.clear()
	if city == null:
		_state_inputs = []
		_state_city_id = 0
		_nodes.clear()
		_lists.clear()
		_demand.clear()
		_decks.clear()
		_approaches.clear()
		facilities.clear()
		developed = 0
	refresh()

func refresh() -> bool:
	last_change = CHANGE_NONE
	if city == null: return false
	var vertices: PackedByteArray = city.terrain_surface.vertices if city.terrain_surface is TerrainSurface else PackedByteArray()
	# Power/water service bits and empty zoning do not affect these routes.
	# Congestion affects demand, never the expensive deck/topology/pose caches.
	var signature := hash([city.altitude.data, city.terrain.data,
		city.flood_overlay, vertices])
	var traffic_signature := hash(city.traffic.data)
	var building_signature := hash(city.building.data)
	var same_geometry: bool = _signature != null and signature == _signature and _current_axis_signature() == _axis_signature
	var land_use_changed: bool = building_signature != _building_signature
	if same_geometry and land_use_changed: same_geometry = _refresh_land_use()
	if same_geometry:
		_building_signature = building_signature
		_building_snapshot = city.building.data.duplicate()
		if land_use_changed: _note_state(2, _building_snapshot.duplicate())
		if traffic_signature == _traffic_signature: return land_use_changed
		_traffic_signature = traffic_signature
		for cell: Vector2i in _demand:
			var demand: Dictionary = _demand[cell]
			demand.congestion = float(city.traffic_at(cell.x,cell.y)) / 255.0
			demand.cars = minf(2.0, float(demand.activity)*.035 + float(demand.congestion)*1.5)
		_note_state(5, city.traffic.data.duplicate())
		return true
	_signature = signature
	_building_signature = building_signature
	_building_snapshot = city.building.data.duplicate()
	_traffic_signature = traffic_signature
	# The graph is a pure function of the raw layers below. Another graph over
	# the same city data (save validation, the naming topology, the view)
	# copies the completed graph instead of projecting it again.
	var raw_inputs := _raw_inputs(city)
	if _refresh_structure(raw_inputs):
		_axis_signature = _current_axis_signature()
		_publish_owner(raw_inputs)
		last_change = CHANGE_INCREMENTAL
		revision += 1
		return true
	last_change = CHANGE_FULL
	_state_inputs = raw_inputs
	_state_city_id = city.get_instance_id()
	if _adopt_completed(raw_inputs):
		_axis_signature = _current_axis_signature()
		revision += 1
		return true
	_axis_cells.clear()
	_nodes = {&"road": {}, &"highway": {}, &"rail": {}, &"water": {}}
	_lists = {&"road": [], &"highway": [], &"rail": [], &"water": []}
	_demand.clear()
	_ground.clear()
	_highway_stencils.clear()
	_centers.clear()
	facilities.clear()
	developed = 0
	highways.rebuild(city)
	# The rebuild samples the same ground repeatedly, so open a sampling scope
	# unless one is already open for this city. Ending it restores any
	# surrounding scope before this function returns. Bridge profiles are
	# shared with the renderer.
	var sampling: Dictionary = {}
	if not CityGeometry3D.is_sampling_ground(city):
		sampling = CityGeometry3D.begin_ground_sampling(city)
	var shared := CityNetworks3D.shared_bridge_profiles(city)
	_decks = shared[0].duplicate(true)
	_approaches = shared[1].duplicate(true)
	# One pass over the raw building bytes with per-code classification;
	# empty dry cells contribute nothing.
	var kinds := network_kinds()
	var codes := city.building.data
	for y: int in City.HEIGHT:
		var row := y * City.WIDTH
		for x: int in City.WIDTH:
			var code: int = codes[row + x]
			if code == Buildings.NONE and not city.is_water(x, y): continue
			var cell := Vector2i(x, y)
			var kind: int = kinds[code]
			if kind & KIND_AXIS:
				_axis_cells.append(cell)
			if code >= Buildings.RES_1X1_FIRST:
				developed += 1
				facilities[code] = int(facilities.get(code, 0)) + 1
			_project_cell(cell, code, kind)
	# A ramp meets the SIDE of a straight elevated carriageway. Its explicit
	# high endpoint is a reciprocal connection even without a highway side arm.
	for ramp: Vector2i in _nodes[&"highway"]:
		var ramp_entry: Dictionary = _nodes[&"highway"][ramp]
		if not ramp_entry.has("ramp"): continue
		var high: Vector2i = ramp+Vector2i(ramp_entry.ramp[1])
		if not _nodes[&"highway"].has(high): continue
		var bit := 1 << DIRECTIONS.find(ramp-high)
		_nodes[&"highway"][high].mask |= bit
		if is_upper_road(high): _nodes[&"road"][high].mask |= bit
	var demand_tables := _demand_tables()
	for domain: StringName in _nodes:
		for cell: Vector2i in _nodes[domain]:
			var entry: Dictionary = _nodes[domain][cell]
			entry.neighbors = _entry_neighbors(domain, cell, entry)
			if not entry.neighbors.is_empty(): _lists[domain].append(cell)
			if domain in [&"road",&"highway"] and not _demand.has(cell): _demand[cell] = _local_demand(cell, demand_tables)
	if not sampling.is_empty(): CityGeometry3D.end_ground_sampling(sampling)
	_axis_signature = _current_axis_signature()
	_publish_completed(raw_inputs)
	revision += 1
	return true


## Every raw city layer this projection reads, detached. A completed graph is
## shared only when these compare equal in full; refresh() uses hashes only to
## decide whether this instance needs to rebuild at all.
static func _raw_inputs(value: City) -> Array:
	var vertices: PackedByteArray = value.terrain_surface.vertices if value.terrain_surface is TerrainSurface else PackedByteArray()
	return [value.altitude.data.duplicate(), value.terrain.data.duplicate(), value.building.data.duplicate(),
		value.flags.data.duplicate(), value.zone.data.duplicate(), value.traffic.data.duplicate(),
		vertices.duplicate(), value.flood_overlay.duplicate(true), value.sea_level]


## One completed projection kept per process; a different city replaces it.
static var _completed_inputs: Array = []
static var _completed_state: Dictionary = {}
## An incrementally refreshed graph published instead of a snapshot. It is
## copied only when another graph adopts it, and only while its current state
## is still the projection of exactly the adopter's raw inputs.
static var _completed_owner: WeakRef = null
## Observational counter for tests; it does not influence any projection.
static var completed_adoptions := 0


func _snapshot() -> Dictionary:
	return {"nodes": _nodes.duplicate(true), "lists": _lists.duplicate(true), "demand": _demand.duplicate(true),
		"facilities": facilities.duplicate(true), "developed": developed, "axis_cells": _axis_cells.duplicate(),
		"decks": _decks.duplicate(true), "approaches": _approaches.duplicate(true),
		"routes": highways.routes.duplicate(true), "shape_cells": highways.shape_cells.duplicate()}


func _publish_completed(raw_inputs: Array) -> void:
	_completed_inputs = raw_inputs
	_completed_state = _snapshot()
	_completed_owner = null


func _publish_owner(raw_inputs: Array) -> void:
	_completed_inputs = raw_inputs
	_completed_state = {}
	_completed_owner = weakref(self)


func _adopt_completed(raw_inputs: Array) -> bool:
	var state: Dictionary = {}
	if not _completed_state.is_empty():
		if _completed_inputs != raw_inputs: return false
		state = _completed_state.duplicate(true)
	else:
		var owner: Variant = _completed_owner.get_ref() if _completed_owner != null else null
		if owner == null or owner == self or owner.city == null or owner._state_inputs != raw_inputs: return false
		state = owner._snapshot()
	completed_adoptions += 1
	_axis_cells.assign(state.axis_cells)
	_nodes = state.nodes
	_lists = state.lists
	_demand = state.demand
	_ground.clear()
	_highway_stencils.clear()
	_centers.clear()
	facilities = state.facilities
	developed = state.developed
	_decks = state.decks
	_approaches = state.approaches
	highways.routes = state.routes
	highways.shape_cells.assign(state.shape_cells)
	return true

## Ordinary dry-lot growth changes demand but cannot move a lane or deck.
## Validate all changes first; mixed construction edits use the full rebuild.
func _refresh_land_use() -> bool:
	var changed: Array[int] = []
	# Only network codes (and any water cell) shape nodes, links and water
	# routes. Ground cover, rubble, parks, utility lines and lots are land use.
	var kinds := network_kinds()
	for i: int in _changed_indices(_building_snapshot, city.building.data):
		var before := int(_building_snapshot[i])
		var after := int(city.building.data[i])
		var cell := Vector2i(i % City.WIDTH, i / City.WIDTH)
		if kinds[before] != 0 or kinds[after] != 0 or city.is_water(cell.x,cell.y): return false
		changed.append(i)
	var affected: Dictionary = {}
	var categories := ScanTables.categories()
	for i: int in changed:
		var before := int(_building_snapshot[i])
		var after := int(city.building.data[i])
		if before >= Buildings.RES_1X1_FIRST:
			developed -= 1
			facilities[before] = int(facilities[before])-1
			if int(facilities[before]) == 0: facilities.erase(before)
		if after >= Buildings.RES_1X1_FIRST:
			developed += 1
			facilities[after] = int(facilities.get(after,0))+1
		# Demand counts categories, not individual roster entries. Facility
		# counts still change above; refresh processes congestion separately.
		if categories[before] == categories[after]: continue
		var cell := Vector2i(i % City.WIDTH, i / City.WIDTH)
		for y: int in range(maxi(0,cell.y-3),mini(City.HEIGHT,cell.y+4)):
			for x: int in range(maxi(0,cell.x-3),mini(City.WIDTH,cell.x+4)):
				var nearby := Vector2i(x,y)
				if _demand.has(nearby): affected[nearby] = true
	for cell: Vector2i in affected: _demand[cell] = _local_demand(cell)
	if not changed.is_empty(): _order_facilities(city.building.data)
	return true

func _current_axis_signature() -> int:
	var bits := PackedByteArray()
	bits.resize(_axis_cells.size())
	for i: int in _axis_cells.size(): bits[i] = city.flags.atv(_axis_cells[i]) & RotationMapper.AXIS_FLAG
	for cell: Vector2i in highways.shape_cells: bits.append(Zones.corners(city.zone.atv(cell)))
	return hash(bits)

func continuation_domain(from: Vector2i, to: Vector2i, domain: StringName) -> StringName:
	if domain not in [&"road",&"highway"]: return domain
	var entry: Dictionary = _entry(domain, from)
	if entry.has("ramp"):
		if to == from+Vector2i(entry.ramp[1]): return &"highway"
		return &"road"
	if domain == &"road" and is_upper_road(from): return &"highway"
	return domain

func cells(domain: StringName) -> Array:
	var list: Variant = _lists.get(domain)
	return list if list != null else []

func has_cell(cell: Vector2i, domain: StringName) -> bool:
	var nodes: Variant = _nodes.get(domain)
	return nodes != null and nodes.has(cell)

func degree(cell: Vector2i, domain: StringName) -> int:
	var entry := _entry(domain, cell)
	return entry.neighbors.size() if entry.has("neighbors") else 0

func neighbors(cell: Vector2i, domain: StringName) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var entry := _entry(domain, cell)
	if entry.has("neighbors"): out.assign(entry.neighbors)
	return out

## The node entry of `cell` in `domain`, or a shared read-only empty entry.
func _entry(domain: StringName, cell: Vector2i) -> Dictionary:
	var nodes: Variant = _nodes.get(domain)
	if nodes == null: return _NO_ENTRY
	var entry: Variant = nodes.get(cell)
	return _NO_ENTRY if entry == null else entry

func traffic_choices(cell: Vector2i, domain: StringName, previous: Vector2i, lane: int) -> Array[Vector2i]:
	var connected := neighbors(cell,domain)
	if domain != &"highway" or not highways.routes.has(cell): return connected
	if is_ramp(previous) and lane != 1: return []
	var out: Array[Vector2i] = []
	for segment: Dictionary in highways.segments(cell,previous,lane):
		if connected.has(segment.next) and not out.has(segment.next): out.append(segment.next)
	for next: Vector2i in connected:
		if lane==1 and is_ramp(next) and next != previous and not out.has(next): out.append(next)
	return out

func highway_segment(cell: Vector2i, previous: Vector2i, next: Vector2i, lane: int) -> Dictionary:
	for segment: Dictionary in highways.segments(cell,previous,lane):
		if segment.next == next: return segment
	return {}

func center(cell: Vector2i, domain: StringName) -> Vector3:
	if not _centers.has(domain): _centers[domain] = {}
	if not _centers[domain].has(cell): _centers[domain][cell] = point(cell,domain)
	return _centers[domain][cell]

func point(cell: Vector2i, domain: StringName, offset: Vector2 = Vector2(.5,.5)) -> Vector3:
	if city == null or not city.in_bounds(cell.x, cell.y): return Vector3(INF, INF, INF)
	if domain == &"water": return Vector3(cell.x + offset.x, CityGeometry3D.water_surface_height(city, cell), cell.y + offset.y)
	var entry: Dictionary = _entry(domain, cell)
	if entry.has("ramp"):
		var road := Vector2(entry.ramp[0])
		var high := Vector2(entry.ramp[1])
		var pivot := Vector2(.5,.5) + (road + high) * .5
		var sweep := (-high).angle_to(-road)
		var t := clampf((-high).angle_to(offset-pivot) / sweep, 0, 1)
		var radial := (-high).rotated(sweep*t)
		var p := pivot + radial * clampf((offset-pivot).length(),.36,.64)
		return Vector3(cell.x+p.x,HighwayHeight.ramp_height(city,cell,road,high,t,(p-pivot).length(),_highway_stencil(cell),CityNetworks3D.HIGHWAY_ELEVATION,preload("res://scripts/view/city_highway_grades_3d.gd").ramp_endpoint(_approaches,_decks,cell,road,high,(p-pivot).length())),cell.y+p.y)
	var lift := .055 if domain == &"rail" else .04
	if _decks.has(cell):
		var deck: Dictionary = _decks[cell]
		return Vector3(cell.x+offset.x,CityNetworks3D.bridge_height(deck,offset.x if deck.ew else offset.y)+(.015 if domain==&"rail" else 0),cell.y+offset.y)
	if _approaches.has(cell) and int(entry.get("family",0))==int(_approaches[cell].family):
		var offset_lift := 0.0 if int(entry.family)==NetworkShapes.Family.HIGHWAY else lift-.04
		return Vector3(cell.x+offset.x,BridgeApproaches.height(_approaches[cell],offset)+offset_lift,cell.y+offset.y)
	if int(entry.get("family", 0)) == NetworkShapes.Family.HIGHWAY:
		return Vector3(cell.x+offset.x,HighwayHeight.height(_highway_stencil(cell),offset)+CityNetworks3D.HIGHWAY_ELEVATION,cell.y+offset.y)
	var facet: Array = _ground.get(cell, [])
	if facet.is_empty():
		var corners := CityGeometry3D.ground_corners(city,cell)
		facet = [corners, CityGeometry3D.uses_nw_se_diagonal(corners)]
		_ground[cell] = facet
	var out := CityGeometry3D.point_over_facet(facet[0], facet[1], cell, offset)
	out.y += lift
	return out


static var _walk_polygons: Dictionary = {}
## Feet follow the actual material under the pedestrian path.
func walk_point(cell: Vector2i, offset: Vector2) -> Vector3:
	var at := point(cell,&"road",offset)
	if _decks.has(cell): return at
	var mask := CityNetworks3D.network_mask(city.building.atv(cell),NetworkShapes.Family.ROAD)
	var lift := .024
	for width: float in [.675,.60]:
		var key := Vector2i(mask,roundi(width*1000))
		if not _walk_polygons.has(key):
			var polygons: Array[PackedVector2Array] = []
			var lo := (1-width)*.5
			if mask in [3,6,9,12]:
				var pivot: Vector2={3:Vector2(1,0),6:Vector2(1,1),12:Vector2(0,1),9:Vector2(0,0)}[mask]
				var angle: float={3:PI,6:-PI*.5,12:0.0,9:PI*.5}[mask]
				for i: int in 16:
					var a := Vector2(cos(angle-i*PI/32),sin(angle-i*PI/32))
					var b := Vector2(cos(angle-(i+1)*PI/32),sin(angle-(i+1)*PI/32))
					polygons.append(PackedVector2Array([pivot+a*lo,pivot+a*(1-lo),pivot+b*(1-lo),pivot+b*lo]))
			else:
				var rectangles: Array[Rect2]=[Rect2(lo,lo,width,width)]
				for direction: int in 4:
					if mask & (1<<direction): rectangles.append([Rect2(lo,0,width,.5),Rect2(.5,lo,.5,width),Rect2(lo,.5,width,.5),Rect2(0,lo,.5,width)][direction])
				for rect: Rect2 in rectangles:
					polygons.append(PackedVector2Array([rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]))
			_walk_polygons[key]=polygons
		for polygon: PackedVector2Array in _walk_polygons[key]:
			if Geometry2D.is_point_in_polygon(offset,polygon): lift=.032 if width>.60 else .04;break
	at.y+=lift-.04
	return at

func _highway_stencil(cell: Vector2i) -> PackedFloat64Array:
	if not _highway_stencils.has(cell): _highway_stencils[cell] = HighwayHeight.stencil(city,cell)
	return _highway_stencils[cell]

func nearest_cell(position: Vector3, domain: StringName, max_distance: float = 8.0) -> Vector2i:
	var best := INVALID
	var distance := max_distance * max_distance
	for cell: Vector2i in cells(domain):
		var d := point(cell, domain).distance_squared_to(position)
		if d <= distance:
			distance = d
			best = cell
	return best

func is_ramp(cell: Vector2i) -> bool:
	return _entry(&"road", cell).has("ramp")

func allows_pedestrians(cell: Vector2i) -> bool:
	return has_cell(cell,&"road") and not is_upper_road(cell) and not is_ramp(cell)

func is_upper_road(cell: Vector2i) -> bool:
	var entry: Dictionary = _entry(&"road", cell)
	return int(entry.get("family",0)) == NetworkShapes.Family.HIGHWAY and not entry.has("ramp")

## The smoothed bridge-approach profile for `cell`, or empty if it has none.
func bridge_approach(cell: Vector2i) -> Dictionary:
	return _approaches.get(cell,{})

func demand(cell: Vector2i) -> Dictionary:
	var found: Variant = _demand.get(cell)
	if found != null: return found
	# The empty default is built only on a miss, so hits allocate nothing.
	# Cells removed by a refresh keep every key an actor may still read.
	return {"cars": 0.0, "people": 0.0, "industrial": 0, "commercial": 0, "congestion": 0.0, "activity": 0}

## Summed-area tables of the four demand categories over the current building
## bytes: [homes, shops, industry, civic], each (WIDTH+1)*(HEIGHT+1) entries.
## A full rebuild answers every 7x7 window count from them exactly.
func _demand_tables() -> Array[PackedInt32Array]:
	var categories := ScanTables.categories()
	var codes := city.building.data
	var stride := City.WIDTH + 1
	var size := stride * (City.HEIGHT + 1)
	var homes := PackedInt32Array()
	var shops := PackedInt32Array()
	var industry := PackedInt32Array()
	var civic := PackedInt32Array()
	homes.resize(size)
	shops.resize(size)
	industry.resize(size)
	civic.resize(size)
	for y: int in City.HEIGHT:
		var home_row := 0
		var shop_row := 0
		var industry_row := 0
		var civic_row := 0
		var row := y * City.WIDTH
		for x: int in City.WIDTH:
			match categories[codes[row + x]]:
				Buildings.Category.RESIDENTIAL: home_row += 1
				Buildings.Category.COMMERCIAL: shop_row += 1
				Buildings.Category.INDUSTRIAL: industry_row += 1
				Buildings.Category.CIVIC, Buildings.Category.TRANSIT, Buildings.Category.REWARD, Buildings.Category.ARCOLOGY: civic_row += 1
			var index := (y + 1) * stride + (x + 1)
			homes[index] = homes[index - stride] + home_row
			shops[index] = shops[index - stride] + shop_row
			industry[index] = industry[index - stride] + industry_row
			civic[index] = civic[index - stride] + civic_row
	return [homes, shops, industry, civic]


static func _window_count(sums: PackedInt32Array, x0: int, y0: int, x1: int, y1: int) -> int:
	# Inclusive cell window [x0..x1] x [y0..y1] from the exclusive-prefix table.
	var stride := City.WIDTH + 1
	return sums[(y1 + 1) * stride + x1 + 1] - sums[y0 * stride + x1 + 1] - sums[(y1 + 1) * stride + x0] + sums[y0 * stride + x0]


func _local_demand(cell: Vector2i, tables: Array[PackedInt32Array] = []) -> Dictionary:
	var homes := 0
	var shops := 0
	var industry := 0
	var civic := 0
	if tables.size() == 4:
		var x0 := maxi(0, cell.x - 3)
		var y0 := maxi(0, cell.y - 3)
		var x1 := mini(City.WIDTH, cell.x + 4) - 1
		var y1 := mini(City.HEIGHT, cell.y + 4) - 1
		homes = _window_count(tables[0], x0, y0, x1, y1)
		shops = _window_count(tables[1], x0, y0, x1, y1)
		industry = _window_count(tables[2], x0, y0, x1, y1)
		civic = _window_count(tables[3], x0, y0, x1, y1)
	else:
		var categories := ScanTables.categories()
		for y: int in range(maxi(0,cell.y-3), mini(City.HEIGHT,cell.y+4)):
			for x: int in range(maxi(0,cell.x-3), mini(City.WIDTH,cell.x+4)):
				match categories[city.building.at(x,y)]:
					Buildings.Category.RESIDENTIAL: homes += 1
					Buildings.Category.COMMERCIAL: shops += 1
					Buildings.Category.INDUSTRIAL: industry += 1
					Buildings.Category.CIVIC, Buildings.Category.TRANSIT, Buildings.Category.REWARD, Buildings.Category.ARCOLOGY: civic += 1
	var activity := homes + shops + industry + civic
	var congestion := float(city.traffic_at(cell.x,cell.y)) / 255.0
	return {"cars": minf(2.0, activity * .035 + congestion * 1.5),
		"people": minf(2.0, homes * .035 + shops * .075 + civic * .055 + industry * .008),
		"industrial": industry, "commercial": shops, "congestion": congestion, "activity": activity}


## The node entries of one cell in every domain, replacing or removing what
## the tables held for it. A complete projection calls this once per occupied
## or wet cell, in row-major order, on empty tables, which fixes their order.
func _project_cell(cell: Vector2i, code: int, kind: int) -> void:
	var road: Variant = null
	var highway: Variant = null
	var rail: Variant = null
	if not kind & KIND_TUNNEL_PORTAL:
		if kind & KIND_ONRAMP:
			var axis := bool(city.flags.atv(cell) & RotationMapper.AXIS_FLAG)
			var ramps: Array = []
			for domain_index: int in 2:
				var ends := NetworkShapes.onramp_endpoints(code, axis, 0)
				var mask := 0
				for dir: Vector2i in ends: mask |= 1 << DIRECTIONS.find(dir)
				ramps.append({"mask": mask, "family": NetworkShapes.Family.HIGHWAY, "neighbors": [], "ramp": ends})
			road = ramps[0]
			highway = ramps[1]
			if kind & KIND_RAIL:
				var mask := CityNetworks3D.network_mask(code, NetworkShapes.Family.RAIL)
				if _decks.has(cell): mask = 10 if bool(_decks[cell].ew) else 5
				rail = {"mask": mask, "family": NetworkShapes.Family.RAIL, "neighbors": []}
		else:
			var deck_mask := -1
			if _decks.has(cell): deck_mask = 10 if bool(_decks[cell].ew) else 5
			if kind & KIND_ROAD:
				var mask := CityNetworks3D.network_mask(code, NetworkShapes.Family.ROAD)
				if deck_mask >= 0: mask = deck_mask
				road = {"mask": mask, "family": NetworkShapes.Family.ROAD, "neighbors": []}
			elif kind & KIND_HIGHWAY:
				var mask := highways.mask(cell, CityNetworks3D.network_mask(code, NetworkShapes.Family.HIGHWAY))
				if deck_mask >= 0: mask = deck_mask
				road = {"mask": mask, "family": NetworkShapes.Family.HIGHWAY, "neighbors": []}
			if kind & KIND_HIGHWAY:
				var mask := highways.mask(cell, CityNetworks3D.network_mask(code, NetworkShapes.Family.HIGHWAY))
				if deck_mask >= 0: mask = deck_mask
				highway = {"mask": mask, "family": NetworkShapes.Family.HIGHWAY, "neighbors": []}
			if kind & KIND_RAIL:
				var mask := CityNetworks3D.network_mask(code, NetworkShapes.Family.RAIL)
				if deck_mask >= 0: mask = deck_mask
				rail = {"mask": mask, "family": NetworkShapes.Family.RAIL, "neighbors": []}
	_place(_nodes[&"road"], cell, road)
	_place(_nodes[&"highway"], cell, highway)
	_place(_nodes[&"rail"], cell, rail)
	var water: Variant = null
	if city.is_water(cell.x, cell.y) and Terrain.water_kind(city.terrain.atv(cell)) != Terrain.STREAM:
		if code == Buildings.NONE or code <= Buildings.TREES_1 or (_decks.has(cell) and point(cell, &"road").y > CityGeometry3D.water_surface_height(city, cell) + .2):
			water = {"mask": 15, "neighbors": []}
	_place(_nodes[&"water"], cell, water)


static func _place(nodes: Dictionary, cell: Vector2i, entry: Variant) -> void:
	if entry == null: nodes.erase(cell)
	else: nodes[cell] = entry


## Reciprocal connections of one entry, in direction order.
func _entry_neighbors(domain: StringName, cell: Vector2i, entry: Dictionary) -> Array:
	var found: Array = []
	for i: int in 4:
		var other := cell + DIRECTIONS[i]
		var other_domain := continuation_domain(cell,other,domain)
		if not entry.mask & (1 << i) or not _nodes[other_domain].has(other): continue
		if not int(_nodes[other_domain][other].mask) & (1 << ((i + 2) % 4)): continue
		# Check the shared edge, including separated overpass decks.
		var a := point(cell, domain, Vector2(.5,.5) + Vector2(DIRECTIONS[i]) * .5)
		var b := point(other, other_domain, Vector2(.5,.5) - Vector2(DIRECTIONS[i]) * .5)
		if absf(a.y - b.y) <= .09: found.append(other)
	return found


## Replace one detached raw input of the current state (never edits the array
## in place: a published snapshot may hold the previous one).
func _note_state(index: int, value: Variant) -> void:
	if _state_inputs.size() != 9: return
	var inputs := _state_inputs.duplicate()
	inputs[index] = value
	_state_inputs = inputs


## Indices where two equally sized byte layers differ, comparing whole rows
## natively before looking at single bytes.
static func _changed_indices(before: PackedByteArray, after: PackedByteArray) -> PackedInt32Array:
	var found := PackedInt32Array()
	var size := after.size()
	if before.size() != size:
		for i: int in size: found.append(i)
		return found
	var start := 0
	while start < size:
		var end := mini(size, start + City.WIDTH)
		if before.slice(start, end) != after.slice(start, end):
			for i: int in range(start, end):
				if before[i] != after[i]: found.append(i)
		start = end
	return found


## Indices whose building code or orientation (axis) flag differs.
static func changed_cells(before_codes: PackedByteArray, after_codes: PackedByteArray, before_flags: PackedByteArray, after_flags: PackedByteArray) -> PackedInt32Array:
	var found := PackedInt32Array()
	var size := after_codes.size()
	var start := 0
	while start < size:
		var end := mini(size, start + City.WIDTH)
		if before_codes.slice(start, end) != after_codes.slice(start, end) or before_flags.slice(start, end) != after_flags.slice(start, end):
			for i: int in range(start, end):
				if before_codes[i] != after_codes[i] or (before_flags[i] & RotationMapper.AXIS_FLAG) != (after_flags[i] & RotationMapper.AXIS_FLAG): found.append(i)
		start = end
	return found


## Keys added, removed or changed between two keyed tables.
static func diff_keys(before: Dictionary, after: Dictionary, seeds: Dictionary) -> void:
	if before == after: return
	for key: Variant in before:
		if not after.has(key) or after[key] != before[key]: seeds[key] = true
	for key: Variant in after:
		if not before.has(key): seeds[key] = true


## Facility counts keyed in the order a row-major scan first meets each code.
func _order_facilities(codes: PackedByteArray) -> void:
	var order := PackedInt64Array()
	for code: int in facilities: order.append(codes.find(code) * 256 + code)
	order.sort()
	var ordered: Dictionary = {}
	for value: int in order: ordered[value & 255] = facilities[value & 255]
	facilities = ordered


## A cell-keyed table whose keys are in row-major order except for the last
## `added`, which were appended in row-major order, merged into the order a
## complete row-major scan inserts.
static func _merge_row_major(nodes: Dictionary, added: int) -> Dictionary:
	if added == 0: return nodes
	var keys: Array = nodes.keys()
	var split := keys.size() - added
	if split == 0: return nodes
	var last: Vector2i = keys[split - 1]
	var first: Vector2i = keys[split]
	if last.y < first.y or (last.y == first.y and last.x < first.x): return nodes
	var merged: Dictionary = {}
	var i := 0
	var j := split
	while i < split or j < keys.size():
		var take_tail := i >= split
		if not take_tail and j < keys.size():
			var a: Vector2i = keys[i]
			var b: Vector2i = keys[j]
			take_tail = b.y < a.y or (b.y == a.y and b.x < a.x)
		var key: Vector2i = keys[j] if take_tail else keys[i]
		if take_tail: j += 1
		else: i += 1
		merged[key] = nodes[key]
	return merged


## Patch the projection after construction, when the current state came from
## this City and every terrain and water input is unchanged. Node entries are
## projected again only within one cell of a changed code or axis bit, bridge
## profile or highway route, and neighbor lists within one more cell: no other
## entry, point or connection reads those inputs. Everything else is kept and
## every table keeps the order a complete projection produces, so the result
## equals a complete projection of the same raw inputs.
func _refresh_structure(raw: Array) -> bool:
	if _state_city_id != city.get_instance_id() or _state_inputs.size() != raw.size() or _nodes.size() != 4: return false
	for i: int in [0, 1, 6, 7, 8]:
		if _state_inputs[i] != raw[i]: return false
	var old_codes: PackedByteArray = _state_inputs[2]
	var codes: PackedByteArray = raw[2]
	var old_flags: PackedByteArray = _state_inputs[3]
	var flags: PackedByteArray = raw[3]
	var old_traffic: PackedByteArray = _state_inputs[5]
	var traffic: PackedByteArray = raw[5]
	if codes.size() != City.WIDTH * City.HEIGHT or old_codes.size() != codes.size() or old_flags.size() != codes.size() or flags.size() != codes.size(): return false
	if old_traffic.size() != traffic.size(): return false
	var changed := changed_cells(old_codes, codes, old_flags, flags)
	if changed.size() > INCREMENTAL_LIMIT: return false
	var sampling: Dictionary = {}
	if not CityGeometry3D.is_sampling_ground(city):
		sampling = CityGeometry3D.begin_ground_sampling(city)
	# A dry cell that is not a network cell before or after holds no node and
	# shapes no point: such changes are land use (demand and lot counts only).
	var kinds := network_kinds()
	var seeds: Dictionary = {}
	for at: int in changed:
		var x := at % City.WIDTH
		var y := at / City.WIDTH
		if kinds[old_codes[at]] != 0 or kinds[codes[at]] != 0 or city.is_water(x, y): seeds[Vector2i(x, y)] = true
	var shared := CityNetworks3D.shared_bridge_profiles(city)
	diff_keys(_decks, shared[0], seeds)
	diff_keys(_approaches, shared[1], seeds)
	# Routes read only highway cells: their codes, their zone corners and
	# whether neighbors carry the same code. Unchanged there, they are kept.
	var highway_codes: PackedByteArray = preload("res://scripts/traffic/city_traffic_highways.gd").highway_codes()
	var routes_changed := false
	for at: int in changed:
		if highway_codes[old_codes[at]] or highway_codes[codes[at]]: routes_changed = true
	if not routes_changed:
		var old_zones: PackedByteArray = _state_inputs[4]
		var zones: PackedByteArray = raw[4]
		for at: int in _changed_indices(old_zones, zones):
			if highway_codes[codes[at]]: routes_changed = true
	if routes_changed:
		var old_routes: Dictionary = highways.routes
		highways.rebuild(city)
		diff_keys(old_routes, highways.routes, seeds)
	_decks = shared[0].duplicate(true)
	_approaches = shared[1].duplicate(true)
	# Entries: every seed and its four neighbors (ramps add side arms there).
	var region: Dictionary = {}
	for cell: Vector2i in seeds:
		for step: Vector2i in [Vector2i.ZERO, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var near: Vector2i = cell + step
			if near.x >= 0 and near.y >= 0 and near.x < City.WIDTH and near.y < City.HEIGHT: region[near] = true
	var order := PackedInt32Array()
	for cell: Vector2i in region: order.append(cell.y * City.WIDTH + cell.x)
	order.sort()
	# Connections: one more ring, whose points and masks are unchanged.
	var outer: Dictionary = region.duplicate()
	for cell: Vector2i in region:
		for step: Vector2i in DIRECTIONS:
			var near: Vector2i = cell + step
			if near.x >= 0 and near.y >= 0 and near.x < City.WIDTH and near.y < City.HEIGHT: outer[near] = true
	var domains: Array = _nodes.keys()
	var listed: Dictionary = {}
	for domain: StringName in domains:
		var nodes: Dictionary = _nodes[domain]
		var members: Dictionary = {}
		for cell: Vector2i in outer:
			var entry: Variant = nodes.get(cell)
			members[cell] = entry != null and not entry.neighbors.is_empty()
		listed[domain] = members
	var had_road: Dictionary = {}
	var had_demand: Dictionary = {}
	for cell: Vector2i in region:
		had_road[cell] = _nodes[&"road"].has(cell)
		had_demand[cell] = _demand.has(cell)
	var added: Dictionary = {}
	var removed: Dictionary = {}
	for domain: StringName in domains: added[domain] = 0
	for at: int in order:
		var cell := Vector2i(at % City.WIDTH, at / City.WIDTH)
		var present: Array[bool] = []
		for domain: StringName in domains: present.append(_nodes[domain].has(cell))
		var code: int = codes[at]
		_project_cell(cell, code, kinds[code])
		for d: int in domains.size():
			var domain: StringName = domains[d]
			var now: bool = _nodes[domain].has(cell)
			if now and not present[d]: added[domain] = int(added[domain]) + 1
			elif present[d] and not now: removed[domain] = true
	# A ramp meets the side of a straight elevated carriageway (see refresh).
	var highway_nodes: Dictionary = _nodes[&"highway"]
	var road_nodes: Dictionary = _nodes[&"road"]
	for at: int in order:
		var cell := Vector2i(at % City.WIDTH, at / City.WIDTH)
		var high: Variant = highway_nodes.get(cell)
		if high == null: continue
		for step: Vector2i in DIRECTIONS:
			var ramp: Vector2i = cell + step
			var ramp_entry: Variant = highway_nodes.get(ramp)
			if ramp_entry == null or not ramp_entry.has("ramp"): continue
			if ramp + Vector2i(ramp_entry.ramp[1]) != cell: continue
			var bit := 1 << DIRECTIONS.find(ramp - cell)
			high.mask = int(high.mask) | bit
			if is_upper_road(cell): road_nodes[cell].mask = int(road_nodes[cell].mask) | bit
	for domain: StringName in domains:
		_nodes[domain] = _merge_row_major(_nodes[domain], int(added[domain]))
	for domain: Variant in _centers:
		var cached: Dictionary = _centers[domain]
		for cell: Vector2i in region: cached.erase(cell)
	var lists_dirty: Dictionary = {}
	for domain: StringName in domains:
		var nodes: Dictionary = _nodes[domain]
		var members: Dictionary = listed[domain]
		if int(added[domain]) > 0 or removed.has(domain): lists_dirty[domain] = true
		for cell: Vector2i in outer:
			var entry: Variant = nodes.get(cell)
			if entry == null: continue
			entry.neighbors = _entry_neighbors(domain, cell, entry)
			if bool(members[cell]) == entry.neighbors.is_empty(): lists_dirty[domain] = true
	for domain: StringName in lists_dirty:
		var nodes: Dictionary = _nodes[domain]
		var list: Array = []
		for cell: Vector2i in nodes:
			if not nodes[cell].neighbors.is_empty(): list.append(cell)
		_lists[domain] = list
	# Demand: the 7x7 windows of changed categories, new cells and congestion.
	road_nodes = _nodes[&"road"]
	highway_nodes = _nodes[&"highway"]
	var demand_order_changed := false
	var stale: Dictionary = {}
	for cell: Vector2i in region:
		var now_road := road_nodes.has(cell)
		var now_any := now_road or highway_nodes.has(cell)
		if now_any != bool(had_demand[cell]) or (now_any and now_road != bool(had_road[cell])): demand_order_changed = true
		if now_any and not _demand.has(cell): stale[cell] = true
	var categories := ScanTables.categories()
	for at: int in changed:
		if categories[old_codes[at]] == categories[codes[at]]: continue
		var x0 := at % City.WIDTH
		var y0 := at / City.WIDTH
		for y: int in range(maxi(0,y0-3),mini(City.HEIGHT,y0+4)):
			for x: int in range(maxi(0,x0-3),mini(City.WIDTH,x0+4)):
				var nearby := Vector2i(x,y)
				if road_nodes.has(nearby) or highway_nodes.has(nearby): stale[nearby] = true
	# Many windows (after a long growth period) read the summed-area tables,
	# which give the same counts as the window scan.
	var tables: Array[PackedInt32Array] = []
	if stale.size() > 256: tables = _demand_tables()
	var values: Dictionary = {}
	for cell: Vector2i in stale: values[cell] = _local_demand(cell, tables)
	if demand_order_changed:
		var ordered: Dictionary = {}
		for cell: Vector2i in road_nodes: ordered[cell] = values[cell] if values.has(cell) else _demand[cell]
		for cell: Vector2i in highway_nodes:
			if not ordered.has(cell): ordered[cell] = values[cell] if values.has(cell) else _demand[cell]
		_demand = ordered
	else:
		for cell: Vector2i in values: _demand[cell] = values[cell]
	if old_traffic != traffic:
		var half := city.traffic.width
		for at: int in _changed_indices(old_traffic, traffic):
			for dy: int in 2:
				for dx: int in 2:
					var cell := Vector2i((at % half) * 2 + dx, (at / half) * 2 + dy)
					if values.has(cell) or not _demand.has(cell): continue
					var demand: Dictionary = _demand[cell]
					demand.congestion = float(city.traffic_at(cell.x,cell.y)) / 255.0
					demand.cars = minf(2.0, float(demand.activity)*.035 + float(demand.congestion)*1.5)
	# Lot counts in the scan's first-occurrence order, and orientation cells.
	var axis_changed := false
	for at: int in changed:
		var before: int = old_codes[at]
		var after: int = codes[at]
		if kinds[before] & KIND_AXIS or kinds[after] & KIND_AXIS: axis_changed = true
		if before == after: continue
		if before >= Buildings.RES_1X1_FIRST:
			developed -= 1
			facilities[before] = int(facilities[before]) - 1
			if int(facilities[before]) == 0: facilities.erase(before)
		if after >= Buildings.RES_1X1_FIRST:
			developed += 1
			facilities[after] = int(facilities.get(after, 0)) + 1
	_order_facilities(codes)
	if axis_changed:
		var moved: Dictionary = {}
		for at: int in changed: moved[at] = true
		var indices := PackedInt32Array()
		for cell: Vector2i in _axis_cells:
			var at := cell.y * City.WIDTH + cell.x
			if not moved.has(at): indices.append(at)
		for at: int in changed:
			if kinds[codes[at]] & KIND_AXIS: indices.append(at)
		indices.sort()
		var axis_cells: Array[Vector2i] = []
		for at: int in indices: axis_cells.append(Vector2i(at % City.WIDTH, at / City.WIDTH))
		_axis_cells = axis_cells
	if not sampling.is_empty(): CityGeometry3D.end_ground_sampling(sampling)
	last_dirty = region
	last_changed_codes = changed
	_state_inputs = raw
	return true


## The level deck profile covering `cell`, or {} off a bridge deck.
func bridge_deck(cell: Vector2i) -> Dictionary:
	return _decks.get(cell, {})

## Become an independent copy of `other`: its projection, its raw inputs and
## its refresh bookkeeping. Point caches start empty.
func copy_from(other: CityTrafficGraph) -> void:
	city = other.city
	revision = other.revision
	developed = other.developed
	_signature = other._signature
	_traffic_signature = other._traffic_signature
	_building_signature = other._building_signature
	_building_snapshot = other._building_snapshot.duplicate()
	_axis_signature = other._axis_signature
	_state_inputs = other._state_inputs
	_state_city_id = other._state_city_id
	var state := other._snapshot()
	_axis_cells.assign(state.axis_cells)
	_nodes = state.nodes
	_lists = state.lists
	_demand = state.demand
	facilities = state.facilities
	_decks = state.decks
	_approaches = state.approaches
	highways.routes = state.routes
	highways.shape_cells.assign(state.shape_cells)
