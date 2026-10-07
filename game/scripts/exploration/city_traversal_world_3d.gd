# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Session-only physical projection. All returned recovery poses have been checked.
class_name CityTraversalWorld3D
extends Node3D

var revision: int = -1
var rebuild_count: int = 0
## Observational wall-clock telemetry; never used by movement or geometry.
var last_rebuild_ms: float = 0.0
var total_rebuild_ms: float = 0.0
var _water: Dictionary = {}
var _road_tunnels: Dictionary = {}
var _retained: Dictionary = {}
var _used: Dictionary = {}
var _shape_bounds: Dictionary = {}
var _used_shapes: Dictionary = {}
var _ceiling: float = 8.0
var _ready_revision := false
const MIN_NORMAL_Y := 0.573576436 # cos(55 degrees), also the vehicle floor limit.
const SKIN := .002

func clear() -> void:
	# queue_free leaves shapes in the physics space until the frame boundary.
	# Removing and freeing now is required when a supporting bridge disappears.
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_road_tunnels.clear()
	_water.clear()
	_retained.clear()
	_used.clear()
	_shape_bounds.clear()
	_used_shapes.clear()
	_ceiling = 8.0
	_ready_revision = false
	revision = -1

func rebuild(_city: City, chunks: Array[Dictionary], networks: Dictionary, revision_id: int) -> void:
	var started_usec := Time.get_ticks_usec()
	_road_tunnels = networks.get("road_tunnels",{}).duplicate(true)
	_water.clear()
	_used.clear()
	_used_shapes.clear()
	var highest := 0.0
	for index: int in chunks.size():
		var chunk := chunks[index]
		highest = maxf(highest,_retained_faces(Vector2i(index,0),chunk.get("physical_floor_faces",PackedVector3Array()),ExploreActorProfile.FLOOR))
		highest = maxf(highest,_retained_faces(Vector2i(index,1),chunk.get("physical_obstacle_faces",PackedVector3Array()),ExploreActorProfile.OBSTACLE))
		for region: Dictionary in chunk.get("water_regions",[]):
			var cell: Vector2i = region.cell
			if not _water.has(cell): _water[cell] = []
			_water[cell].append(region.duplicate(true))
	highest = maxf(highest,_retained_faces(Vector2i(-1,0),networks.get("physical_floor_faces",PackedVector3Array()),ExploreActorProfile.FLOOR))
	highest = maxf(highest,_retained_faces(Vector2i(-1,1),networks.get("physical_obstacle_faces",PackedVector3Array()),ExploreActorProfile.OBSTACLE))
	var boxes: Array = networks.get("physical_boxes",[])
	for index: int in boxes.size():
		var record: Dictionary = boxes[index]
		var key := Vector2i(index,2)
		_used[key] = true
		var retained: Dictionary = _retained.get(key,{})
		if retained.is_empty() or retained.size!=record.size or retained.transform!=record.transform:
			_remove_retained(key)
			var shape := BoxShape3D.new()
			shape.size = record.size
			var body := _add_shape(shape,record.transform,ExploreActorProfile.OBSTACLE)
			retained = {"body":body,"size":record.size,"transform":record.transform,"top":_shape_top(shape,record.transform)}
			_retained[key] = retained
		highest = maxf(highest,retained.top)
	for key: Vector2i in _retained.keys():
		if not _used.has(key): _remove_retained(key)
	# Existing mask 4 building/palm shells belong to the view, not this node.
	if get_parent() != null:
		for sibling: Node in get_parent().get_children():
			if sibling != self: highest = maxf(highest,_sibling_top(sibling))
	for shape: Shape3D in _shape_bounds.keys():
		if not _used_shapes.has(shape): _shape_bounds.erase(shape)
	_ceiling = highest+8.0
	revision = revision_id
	rebuild_count += 1
	_ready_revision = true
	last_rebuild_ms = float(Time.get_ticks_usec()-started_usec)/1000.0
	total_rebuild_ms += last_rebuild_ms

func _remove_retained(key: Vector2i) -> void:
	if not _retained.has(key): return
	var body: Node = _retained[key].body
	remove_child(body)
	body.free()
	_retained.erase(key)

func _retained_faces(key: Vector2i, points: PackedVector3Array, layer: int) -> float:
	if points.is_empty(): return 0.0
	_used[key] = true
	var retained: Dictionary = _retained.get(key,{})
	if not retained.is_empty() and retained.points==points: return retained.top
	_remove_retained(key)
	var highest := _faces(points,layer)
	_retained[key] = {"points":points.duplicate(),"top":highest,"body":get_child(get_child_count()-1)}
	return highest

func _faces(points: PackedVector3Array, layer: int) -> float:
	var highest := 0.0
	if points.is_empty(): return highest
	for point: Vector3 in points: highest = maxf(highest,point.y)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(points)
	_add_shape(shape,Transform3D.IDENTITY,layer)
	return highest

func _add_shape(shape: Shape3D, at: Transform3D, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	body.transform = at
	return body

func _shape_top(shape: Shape3D, at: Transform3D) -> float:
	# Debug mesh uses the same primitive/convex/concave shape bounds, including
	# shell shapes transformed by their building parent and rotated palm trunks.
	var bounds: AABB
	if shape is BoxShape3D:
		bounds = at*AABB(-shape.size*.5,shape.size)
	elif shape is CylinderShape3D:
		var size := Vector3(shape.radius*2.0,shape.height,shape.radius*2.0)
		bounds = at*AABB(-size*.5,size)
	elif shape is ConcavePolygonShape3D or shape is ConvexPolygonShape3D:
		_used_shapes[shape] = true
		var points: PackedVector3Array = shape.get_faces() if shape is ConcavePolygonShape3D else shape.points
		if points.is_empty(): return 0.0
		var cached: Dictionary = _shape_bounds.get(shape,{})
		if cached.is_empty() or cached.points!=points:
			var local := AABB(points[0],Vector3.ZERO)
			for point: Vector3 in points: local = local.expand(point)
			cached = {"points":points.duplicate(),"bounds":local}
			_shape_bounds[shape] = cached
		bounds = at*cached.bounds
	else:
		var mesh := shape.get_debug_mesh()
		if mesh == null: return 0.0
		bounds = at*mesh.get_aabb()
	return bounds.end.y

## Highest mask 4 shell under node, including node itself. The engine's typed
## descendant search replaces a per-node script walk of the whole city tree;
## every shape still passes the same enabled/layer test with its own transform.
## Shell tops of lots declared immutable by their owner never change while the
## node lives, so each is scanned once; other branches are scanned every time.
var _shell_tops: Dictionary = {}

func _sibling_top(sibling: Node) -> float:
	var highest := 0.0
	if sibling is CollisionShape3D: highest = _shell_top(sibling)
	var live: Dictionary = {}
	for child: Node in sibling.get_children():
		if child.get_meta("batch_immutable", false):
			var id := child.get_instance_id()
			if not _shell_tops.has(id): _shell_tops[id] = _shell_top(child)
			live[id] = true
			highest = maxf(highest, _shell_tops[id])
		else:
			highest = maxf(highest, _shell_top(child))
	if _shell_tops.size() > live.size() * 2 + 64:
		for id: int in _shell_tops.keys():
			if not live.has(id) and not is_instance_valid(instance_from_id(id)): _shell_tops.erase(id)
	return highest

func _shell_top(node: Node) -> float:
	if node == self: return 0.0
	var highest := 0.0
	var candidates: Array[Node] = node.find_children("*","CollisionShape3D",true,false)
	if node is CollisionShape3D: candidates.append(node)
	for candidate: Node in candidates:
		var collision := candidate as CollisionShape3D
		if collision.disabled or collision.shape == null: continue
		var body := collision.get_parent() as CollisionObject3D
		if body != null and body.collision_layer & 4:
			highest = maxf(highest,_shape_top(collision.shape,collision.global_transform))
	return highest

func max_flight_y() -> float:
	return _ceiling

func _inside(point: Vector3) -> bool:
	return point.is_finite() and point.x>=0.0 and point.z>=0.0 and point.x<float(City.WIDTH) and point.z<float(City.HEIGHT)

func support_near(feet: Vector3, rise: float, drop: float, exclude: Array[RID]) -> Dictionary:
	if not _ready_revision or not is_inside_tree() or not _inside(feet): return {}
	if not is_finite(rise) or not is_finite(drop) or rise<0.0 or drop<0.0 or rise+drop<=0.0: return {}
	# Godot's short segment/triangle predicate misses tiny curved-deck facets.
	# Cast a numerically stable segment, then enforce the caller's exact support
	# interval on its nearest hit. This does not enlarge the accepted step/drop.
	var cast_drop := maxf(drop,1.0-rise)
	var query := PhysicsRayQueryParameters3D.create(feet+Vector3.UP*rise,feet-Vector3.UP*cast_drop,ExploreActorProfile.WORLD,exclude)
	query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.position.is_finite() or hit.normal.y<MIN_NORMAL_Y: return {}
	if hit.position.y<feet.y-drop-.000002 or hit.position.y>feet.y+rise+.000002: return {}
	return {"position":hit.position,"normal":hit.normal,"rid":hit.rid}

func has_clearance(at: Transform3D, shape: Shape3D, exclude: Array[RID]) -> bool:
	if not _ready_revision or not is_inside_tree() or shape == null or not at.is_finite() or not _inside(at.origin): return false
	var mesh := shape.get_debug_mesh()
	if mesh == null: return false
	var bounds: AABB = at*mesh.get_aabb()
	if bounds.position.x<0 or bounds.position.z<0 or bounds.end.x>City.WIDTH or bounds.end.z>City.HEIGHT: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = at
	query.margin = .001
	query.collision_mask = ExploreActorProfile.WORLD | ExploreActorProfile.ACTOR
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func touches_water(feet: Vector3) -> bool:
	if not feet.is_finite(): return false
	# Water polygons describe the surface column. A finite, enclosed road bore
	# is dry below it; the water above its physical roof still remains wet.
	if inside_road_tunnel(feet): return false
	var cell := Vector2i(floori(feet.x),floori(feet.z))
	for region: Dictionary in _water.get(cell,[]):
		if feet.y<=float(region.top)+SKIN and Geometry2D.is_point_in_polygon(Vector2(feet.x,feet.z),region.polygon): return true
	return false

func _candidate(point: Vector3, mode: int, exclude: Array[RID], broad: bool = false) -> Dictionary:
	if not _inside(point): return {}
	var support := support_near(point,.045,8.0,exclude) if not broad else support_near(Vector3(point.x,_ceiling,point.z),0.0,_ceiling+64.0,exclude)
	if support.is_empty(): return {}
	var feet: Vector3 = support.position+Vector3.UP*SKIN
	if touches_water(feet) or feet.y>_ceiling: return {}
	var at := Transform3D(Basis.IDENTITY,feet+Vector3.UP*float(ExploreActorProfile.geometry(mode).foot_offset))
	if not has_clearance(at,ExploreActorProfile.shape(mode),exclude): return {}
	return {"transform":Transform3D(Basis.IDENTITY,feet)}

func safe_pose(origin: Vector3, mode: int, exclude: Array[RID]) -> Dictionary:
	if not _ready_revision or not _inside(origin) or mode<ExploreActorProfile.Mode.WALK or mode>ExploreActorProfile.Mode.FLY: return {}
	var result := _candidate(origin,mode,exclude)
	if not result.is_empty(): return result
	# Fixed concentric order avoids RNG and limits nearby recovery to eight tiles.
	for radius: int in range(1,9):
		for index: int in 16:
			var angle := TAU*float(index)/16.0
			var point := origin+Vector3(cos(angle),0,sin(angle))*float(radius)
			result = _candidate(point,mode,exclude)
			if not result.is_empty(): return result
	# Finite city-centre grid fallback; every result still has physical support,
	# dry feet and clearance. No unchecked origin/height-map fallback exists.
	for z: int in City.HEIGHT:
		for x: int in City.WIDTH:
			result = _candidate(Vector3(x+.5,0,z+.5),mode,exclude,true)
			if not result.is_empty(): return result
	return {}

func inside_road_tunnel(point: Vector3) -> bool:
	return preload("res://scripts/view/city_road_tunnels_3d.gd").contains(point,_road_tunnels)
