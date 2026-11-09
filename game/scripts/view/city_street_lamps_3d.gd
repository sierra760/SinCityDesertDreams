# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Street lamps along roads and highway medians. Presentation only: lamps are
## derived from the drawn road network, never saved, and have no collision.
## Each lens also writes one texel of the night light-pool table, which the
## ground shader reads (see shaders/city_night_lights.gdshaderinc).
class_name CityStreetLamps3D
extends Node3D

const Globals := preload("res://scripts/view/city_night_globals.gd")
const ROOT := "res://assets/desert-dreams-street-lamps/"
## Post centre from the tile edge, in the sand verge beyond the sidewalk
## (the walking line is 0.10 from the edge), like the street-name blades.
const INSET := .145
## Steeper verges than this lose their lamp rather than float a corner.
const MAX_SPREAD := .02
const POOL_STRENGTH := 1.0

var placements: Array[Dictionary] = []
var _metadata: Dictionary = {}
var _meshes: Dictionary = {}
var _batches: Dictionary = {}
var _graph: CityTrafficGraph
var _signature: Array = []
## The current placements by cell, one table per kind of lamp, so an
## incremental graph refresh replans only the cells it can have changed.
var _road_lamps: Dictionary = {}
var _median_lamps: Dictionary = {}
## Whether the last rebuild replanned only an incremental refresh's cells.
var last_sync_incremental := false
var _image: Image
var _texture: ImageTexture

func _ready() -> void:
	Globals.ensure()
	visibility_changed.connect(_publish_pools)
	_metadata = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"street-lamps.json")) if FileAccess.file_exists(ROOT+"street-lamps.json") else {}
	for kind: String in ["street_lamp","street_lamp_double"]:
		var mesh := _load_mesh(ROOT+kind+".glb")
		if mesh == null: continue
		_meshes[kind] = mesh
		var instance := MultiMeshInstance3D.new()
		instance.name = "Lamps_"+kind
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = mesh
		instance.multimesh = batch
		add_child(instance)
		_batches[kind] = instance

func _exit_tree() -> void:
	if _texture != null: Globals.set_lamps(null)

## The terrain must lose the light pools whenever the lamp meshes are hidden.
func _publish_pools() -> void:
	Globals.set_lamps(_texture if is_visible_in_tree() else null)

static func _load_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path): return null
	var scene := load(path) as PackedScene
	if scene == null: return null
	var root := scene.instantiate()
	var found: Mesh = null
	var stack: Array[Node] = [root]
	while not stack.is_empty() and found == null:
		var node: Node = stack.pop_back()
		if node is MeshInstance3D: found = (node as MeshInstance3D).mesh
		stack.append_array(node.get_children())
	root.free()
	return found

## Rebuild when the road graph has changed. Cheap when it has not.
func sync(graph: CityTrafficGraph) -> void:
	if graph == null or graph.city == null:
		if not placements.is_empty():
			_road_lamps.clear()
			_median_lamps.clear()
			_signature = []
			_publish([])
		return
	var signature: Array = [graph.get_instance_id(),graph.city.get_instance_id(),graph.revision]
	if signature == _signature: return
	var incremental: bool = _graph == graph and _signature.size() == 3 and signature[1] == _signature[1] \
		and graph.revision == int(_signature[2])+1 and graph.last_change == CityTrafficGraph.CHANGE_INCREMENTAL
	_signature = signature
	_graph = graph
	last_sync_incremental = incremental
	if incremental: _replan(graph)
	else: _index(plan(graph))
	_publish(_ordered())

## Replan the cells an incremental graph refresh can have changed. A road lamp
## reads its own cell's code, deck, points and route membership; membership
## also changes one ring outside the graph's dirty cells, and a median lamp
## reads the neighbouring carriageway, so two rings around them are replanned.
func _replan(graph: CityTrafficGraph) -> void:
	var city := graph.city
	var region: Dictionary = {}
	for cell: Vector2i in graph.last_dirty: region[cell] = true
	for at: int in graph.last_changed_codes: region[Vector2i(at % City.WIDTH, at / City.WIDTH)] = true
	for ring: int in 2:
		var grown: Dictionary = region.duplicate()
		for cell: Vector2i in region:
			for step: Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
				var near := cell+step
				if city.in_bounds(near.x,near.y): grown[near] = true
		region = grown
	for cell: Vector2i in region:
		_road_lamps.erase(cell)
		_median_lamps.erase(cell)
		if graph.degree(cell,&"road") > 0:
			var placed := _road_lamp(graph,city,cell)
			if not placed.is_empty(): _road_lamps[cell] = placed
		if graph.degree(cell,&"highway") > 0:
			var median := _median_lamp(graph,city,cell)
			if not median.is_empty(): _median_lamps[cell] = median

func _index(records: Array[Dictionary]) -> void:
	_road_lamps.clear()
	_median_lamps.clear()
	for record: Dictionary in records:
		if record.kind == "street_lamp": _road_lamps[record.cell] = record
		else: _median_lamps[record.cell] = record

## The indexed placements in plan()'s order: road lamps, then median lamps,
## each by cell.
func _ordered() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for table: Dictionary in [_road_lamps,_median_lamps]:
		var keys: Array = table.keys()
		keys.sort()
		for cell: Vector2i in keys: out.append(table[cell])
	return out

## Lamp records {kind, transform, cell} for the graph's city, in a stable order.
func plan(graph: CityTrafficGraph) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var city := graph.city
	var road_cells: Array = graph.cells(&"road").duplicate()
	road_cells.sort()
	for cell: Vector2i in road_cells:
		var placed := _road_lamp(graph,city,cell)
		if not placed.is_empty(): out.append(placed)
	var highway_cells: Array = graph.cells(&"highway").duplicate()
	highway_cells.sort()
	for cell: Vector2i in highway_cells:
		var placed := _median_lamp(graph,city,cell)
		if not placed.is_empty(): out.append(placed)
	return out

func _road_lamp(graph: CityTrafficGraph, city: City, cell: Vector2i) -> Dictionary:
	var code := city.building.atv(cell)
	if not NetworkShapes.is_plain_road(code) or city.is_water(cell.x,cell.y) or graph._decks.has(cell): return {}
	var mask := CityNetworks3D.network_mask(code,NetworkShapes.Family.ROAD)
	var uv: Vector2
	var bits := 0
	for bit: int in [1,2,4,8]: if mask & bit: bits += 1
	if bits >= 3:
		# Junctions: one lamp in the far corner, leaning over the crossing.
		uv = Vector2(1.0-INSET,1.0-INSET)
	elif mask in [NetworkShapes.NORTH,NetworkShapes.SOUTH,NetworkShapes.NORTH|NetworkShapes.SOUTH]:
		# Every second tile, alternating sides: about 32 m apart, staggered.
		if posmod(cell.y,2) != 0: return {}
		uv = Vector2(INSET if posmod(cell.y/2+cell.x,2) == 0 else 1.0-INSET,.5)
	elif mask in [NetworkShapes.EAST,NetworkShapes.WEST,NetworkShapes.EAST|NetworkShapes.WEST]:
		if posmod(cell.x,2) != 0: return {}
		uv = Vector2(.5,INSET if posmod(cell.x/2+cell.y,2) == 0 else 1.0-INSET)
	else:
		return {} # Diagonal pieces run through their corners.
	var foot := _seat(func(offset: Vector2) -> Vector3: return graph.walk_point(cell,offset),uv)
	if not foot.is_finite(): return {}
	var toward := Vector2(.5,.5)-uv
	return {"kind":"street_lamp","cell":cell,"transform":Transform3D(_facing(Vector3(toward.x,0,toward.y)),foot)}

## Highway medians: a double lamp on the line between paired carriageways.
func _median_lamp(graph: CityTrafficGraph, city: City, cell: Vector2i) -> Dictionary:
	var code := city.building.atv(cell)
	if city.is_water(cell.x,cell.y): return {}
	if code in [NetworkShapes.HIGHWAY_NS_ROAD_EW,NetworkShapes.HIGHWAY_EW_ROAD_NS,NetworkShapes.HIGHWAY_NS_RAIL_EW,
			NetworkShapes.HIGHWAY_EW_RAIL_NS,NetworkShapes.HIGHWAY_NS_POWER_EW,NetworkShapes.HIGHWAY_EW_POWER_NS]: return {}
	var mask := CityNetworks3D.network_mask(code,NetworkShapes.Family.HIGHWAY)
	var across: Vector2i
	var along: int
	if mask == NetworkShapes.NORTH|NetworkShapes.SOUTH:
		across = Vector2i(1,0)
		along = cell.y
	elif mask == NetworkShapes.EAST|NetworkShapes.WEST:
		across = Vector2i(0,1)
		along = cell.x
	else: return {}
	if posmod(along,2) != 0: return {}
	var other := cell+across
	if not city.in_bounds(other.x,other.y) or not graph.has_cell(other,&"highway") or city.building.atv(other) != code or city.is_water(other.x,other.y): return {}
	var edge := Vector2(.5,.5)+Vector2(across)*.5
	var mine := graph.point(cell,&"highway",edge-Vector2(across)*.02)
	var theirs := graph.point(other,&"highway",Vector2(.5,.5)-Vector2(across)*.48)
	if not mine.is_finite() or not theirs.is_finite() or absf(mine.y-theirs.y) > MAX_SPREAD: return {}
	var foot := Vector3(cell.x+edge.x,minf(mine.y,theirs.y),cell.y+edge.y)
	return {"kind":"street_lamp_double","cell":cell,"transform":Transform3D(_facing(Vector3(across.x,0,across.y)),foot)}

## Seat the post on the lowest of four samples around its foot.
static func _seat(surface: Callable, uv: Vector2) -> Vector3:
	var lowest := INF
	var highest := -INF
	var center: Vector3 = surface.call(uv)
	for delta: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var p: Vector3 = surface.call(uv+delta*.008)
		lowest = minf(lowest,p.y)
		highest = maxf(highest,p.y)
	if not is_finite(lowest) or highest-lowest > MAX_SPREAD: return Vector3(INF,INF,INF)
	center.y = lowest
	return center

## The model's arm reaches along -Z; turn it toward `direction`.
static func _facing(direction: Vector3) -> Basis:
	if direction.length_squared() < 1e-8: return Basis.IDENTITY
	return Basis.looking_at(direction.normalized(),Vector3.UP)

## World lens positions of a placement.
func lenses(record: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for lens: Array in _metadata.get(record.kind,{}).get("lens",[]):
		out.append(record.transform*Vector3(float(lens[0]),float(lens[1]),float(lens[2])))
	return out

func _publish(records: Array[Dictionary]) -> void:
	placements = records
	var grouped: Dictionary = {}
	for record: Dictionary in records:
		if not grouped.has(record.kind): grouped[record.kind] = []
		grouped[record.kind].append(record.transform)
	for kind: String in _batches:
		var batch: MultiMesh = _batches[kind].multimesh
		var transforms: Array = grouped.get(kind,[])
		batch.instance_count = transforms.size()
		for i: int in transforms.size(): batch.set_instance_transform(i,transforms[i])
	if _image == null: _image = Image.create(City.WIDTH,City.HEIGHT,false,Image.FORMAT_RGBAF)
	_image.fill(Color(0,0,0,0))
	for record: Dictionary in records:
		for lens: Vector3 in lenses(record):
			var tile := Vector2i(floori(lens.x),floori(lens.z))
			if tile.x < 0 or tile.y < 0 or tile.x >= City.WIDTH or tile.y >= City.HEIGHT: continue
			if _image.get_pixelv(tile).a > 0.0: continue
			_image.set_pixelv(tile,Color(lens.x-tile.x,lens.z-tile.y,lens.y,POOL_STRENGTH))
	if _texture == null: _texture = ImageTexture.create_from_image(_image)
	else: _texture.update(_image)
	_publish_pools()
