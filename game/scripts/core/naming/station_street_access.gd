# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Which nearby streets a pedestrian can reach from a station's entrance,
## judged from the ground alone: train service and temporary closures such as
## floods do not change the answer.
class_name StationStreetAccess
extends RefCounted
const RADIUS := 2
const STEP := .045 # ExplorePedestrian's bounded physical step.
const MIN_NORMAL_Y := CityTraversalWorld3D.MIN_NORMAL_Y
const DIRS: Array[Vector2i] = [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]

static func surface_entrance(city: City, anchor: Vector2i) -> Dictionary:
	var code := city.building.atv(anchor)
	var rect := Rect2i(anchor,Buildings.size(code))
	var yaw := station_yaw(city,rect,code)
	var facing := Vector2i(roundi(sin(yaw)),roundi(cos(yaw)))
	var center := Vector2(rect.position)+Vector2(rect.size)*.5
	var front := center+Vector2(facing)*Vector2(rect.size)*.5
	return {"footprint":rect,"position":Vector3(front.x,_station_floor(city,rect),front.y),"yaw":yaw,"subway":code==Buildings.SUBWAY_STATION}

## The existing rigid station foundation clears every visible footprint corner.
static func _station_floor(city: City, rect: Rect2i) -> float:
	var height := CityGeometry3D.surface_height(city,rect.position)
	for y: int in range(rect.position.y,rect.end.y):
		for x: int in range(rect.position.x,rect.end.x):
			if not city.in_bounds(x,y): continue
			for corner: Vector3 in CityGeometry3D.visible_cell_corners(city,Vector2i(x,y)): height=maxf(height,corner.y)
	return height

static func _walkable(city: City, cell: Vector2i, rect: Rect2i) -> bool:
	if not city.in_bounds(cell.x,cell.y) or rect.has_point(cell) or city.is_water(cell.x,cell.y): return false
	var code := city.building.atv(cell)
	if Buildings.is_developed(code) or NetworkShapes.is_highway(code) or NetworkShapes.is_onramp(code) or NetworkShapes.is_tunnel(code): return false
	# Rubble, contamination, palms and small parks are open ground in Explore;
	# only their thin trunks collide, so they never wall off an entrance.
	var ground_cover := code>=Buildings.RUBBLE_1 and code<=Buildings.SMALL_PARK
	if code!=0 and not ground_cover and not NetworkShapes.in_road_family(code) and not NetworkShapes.in_rail_family(code) and not NetworkShapes.in_power_family(code): return false
	var corners := CityGeometry3D.ground_corners(city,cell)
	var diagonal := CityGeometry3D.uses_nw_se_diagonal(corners)
	var triangles: Array = [[0,1,3],[0,3,2]] if diagonal else [[0,1,2],[1,3,2]]
	for tri: Array in triangles:
		var a: Vector3 = corners[tri[0]]
		var b: Vector3 = corners[tri[1]]
		var c: Vector3 = corners[tri[2]]
		if absf((b-a).cross(c-a).normalized().y)<MIN_NORMAL_Y: return false
	return true

static func _passage(city: City, a: Vector2i, b: Vector2i) -> bool:
	var direction := Vector2(b-a)
	# Shared facets must meet within the existing controller step, throughout
	# the central walking passage; no jump to a road on another grade.
	for across: float in [.35,.5,.65]:
		var offset := Vector2(.5,.5)+direction*.5+Vector2(-direction.y,direction.x)*(across-.5)
		var first := CityGeometry3D.point_on_ground(city,a,offset)
		var second := CityGeometry3D.point_on_ground(city,b,offset-direction)
		if absf(first.y-second.y)>STEP+.00001: return false
	return true

static func neighbors(city: City, topology: StreetTopology, anchor: Vector2i, metadata: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if city==null or not topology.is_bound_to(city): return result
	# Temporary flooding is a closure, not a different permanent name source.
	var surface_city := city
	if not city.flood_overlay.is_empty():
		surface_city = city.duplicate_city()
		surface_city.flood_overlay.clear()
	var entrance := surface_entrance(surface_city,anchor)
	var rect: Rect2i = entrance.footprint
	var bounds := rect.grow(RADIUS)
	var position: Vector3 = entrance.position
	var facing := Vector2i(roundi(sin(float(entrance.yaw))),roundi(cos(float(entrance.yaw))))
	var reached: Dictionary = {}
	var queue: Array[Vector2i] = []
	# A two-tile facade's central passage can straddle a cell boundary.
	# Inspect its actual walking width rather than selecting one arbitrary
	# half with floor(). Enclosed fronts never seed a path through the lot.
	for across: float in [-.15,0.0,.15]:
		var front_point := Vector2(position.x,position.z)+Vector2(facing)*.001+Vector2(-facing.y,facing.x)*across
		var front := Vector2i(floori(front_point.x),floori(front_point.y))
		if reached.has(front) or not _walkable(surface_city,front,rect): continue
		var point := CityGeometry3D.point_on_ground(surface_city,front,front_point-Vector2(front))
		if absf(point.y-position.y)>STEP+.00001: continue
		reached[front] = true
		queue.append(front)
	var cursor := 0
	while cursor<queue.size():
		var cell := queue[cursor]
		cursor += 1
		for direction: Vector2i in DIRS:
			var other := cell+direction
			if reached.has(other) or not bounds.has_point(other) or not _walkable(surface_city,other,rect): continue
			if not _passage(surface_city,cell,other): continue
			reached[other] = true
			queue.append(other)
	# Topology's structural open nodes and rendered points are authoritative.
	# Only the reached cells' open nodes, in the topology's own (row-major) order.
	var reached_cells: Array = reached.keys()
	reached_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y<b.y or (a.y==b.y and a.x<b.x))
	for cell: Vector2i in reached_cells:
		var node := topology.open_node(cell)
		if node.is_empty(): continue
		var node_position: Vector3 = topology.node_point(node)
		if absf(node_position.y-CityGeometry3D.ground_height(surface_city,node.cell))>STEP+.00001: continue
		for key: String in node.links:
			var id := int(metadata.links.get(key,0))
			if id==0 or not metadata.streets.has(id): continue
			var other := topology.linked_node(key,node)
			var direction: Vector2i = other.cell-node.cell
			var points := topology.connection_points(key)
			var distance := INF
			for sample: Vector3 in points:
				var sample_cell := Vector2i(floori(sample.x),floori(sample.z))
				if reached.has(sample_cell): distance=minf(distance,Vector2(sample.x-position.x,sample.z-position.z).length_squared())
			var approach := Vector2(node.cell)+Vector2(.5,.5)+Vector2(direction)*.25
			result.append({"key":key,"street_id":id,"cell":node.cell,"direction":DIRS.find(direction),"degree":node.links.size(),"distance":distance,"junction_distance":Vector2(node_position.x-position.x,node_position.z-position.z).length_squared(),"approach_distance":approach.distance_squared_to(Vector2(position.x,position.z))})
	return result

static func station_connections(value: City, rect: Rect2i, subway := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cells: Array[Vector2i] = []
	var deck_profiles: Dictionary = {}
	var decks_ready := false
	var surface := CityGeometry3D.ground_height(value,rect.position)
	if subway:
		cells.append(rect.position)
		for step: Vector2i in DIRS: cells.append(rect.position+step)
		for step: Vector2i in [Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]: cells.append(rect.position+step)
	else:
		for y: int in range(rect.position.y-1,rect.end.y+1):
			for x: int in range(rect.position.x-1,rect.end.x+1):
				if not rect.has_point(Vector2i(x,y)): cells.append(Vector2i(x,y))
	for cell: Vector2i in cells:
		if not value.in_bounds(cell.x,cell.y): continue
		var mask := _station_mask(value,cell,subway)
		if mask==0: continue
		if not subway:
			var height := CityGeometry3D.ground_height(value,cell)+.055
			if NetworkShapes.is_rail_bridge(value.building.atv(cell)):
				if not decks_ready:
					deck_profiles = CityNetworks3D.shared_bridge_profiles(value)[0]
					decks_ready = true
				if deck_profiles.has(cell): height = (float(deck_profiles[cell].start)+float(deck_profiles[cell].end))*.5+.015
			if absf(surface-height)>.09: continue
		for direction: Vector2i in [Vector2i.UP,Vector2i.RIGHT]:
			var links := 0
			for step: Vector2i in [direction,-direction]:
				var neighbor := cell+step
				if not value.in_bounds(neighbor.x,neighbor.y): continue
				var d := DIRS.find(step)
				if mask & (1<<d) and _station_mask(value,neighbor,subway) & (1<<((d+2)%4)): links += 1
			if links==0: continue
			if subway:
				var toward := Vector2(-direction.y,direction.x).dot(Vector2(rect.position-cell))
				out.append({"cell":cell,"direction":direction,"side":-1 if toward<0 else 1,"links":links})
			else:
				var right := Vector2i(-direction.y,direction.x)
				for side: int in [1,-1]:
					if rect.has_point(cell+right*side): out.append({"cell":cell,"direction":direction,"side":side,"links":links})
	var ranked: Array[Dictionary] = []
	for own: bool in [true,false]:
		for links: int in [2,1]:
			for candidate: Dictionary in out:
				if int(candidate.links)!=links: continue
				if (not subway or candidate.cell==rect.position)==own: ranked.append(candidate)
	return ranked

static func _station_mask(value: City, cell: Vector2i, subway: bool) -> int:
	if subway: return NetworkShapes.underground_mask(value.underground.atv(cell),NetworkShapes.Family.SUBWAY)
	var code := value.building.atv(cell)
	if NetworkShapes.is_subway_portal(code): return 0
	if NetworkShapes.is_rail_bridge(code): return 10 if value.flags.atv(cell)&RotationMapper.AXIS_FLAG else 5
	return CityNetworks3D.network_mask(code,NetworkShapes.Family.RAIL) if NetworkShapes.in_family(code,NetworkShapes.Family.RAIL) else 0


static func station_yaw(city: City, rect: Rect2i, code: int) -> float:
	var subway := code == Buildings.SUBWAY_STATION
	var connections := station_connections(city, rect, subway)
	if connections.is_empty(): return 0.0
	var selected: Dictionary = connections[0]
	var direction: Vector2i = selected.direction
	var facing := direction if subway else -Vector2i(-direction.y,direction.x)*int(selected.side)
	if subway: facing=-direction*int(selected.side)
	return atan2(float(facing.x),float(facing.y))

