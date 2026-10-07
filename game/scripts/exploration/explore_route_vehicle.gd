# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Session-only rail and water controls over the read-only traffic graph.
class_name ExploreRouteVehicle
extends CharacterBody3D

signal recovery_requested(reason: String)
var kind: StringName
var domain: StringName
var graph: RefCounted
var _points: Array[Vector3] = []
var _transit_route: Dictionary = {}
var _distance := 0.0
var _speed := 0.0
var _length := 0.0
var _size := Vector3(.2,.2,.5)
var _collider: CollisionShape3D
var _visual: Node3D
# Transit route validation depends only on the route and network nodes, so it
# is reused until the network publishes a change (or the route is replaced).
var _route_checked_network := 0
var _route_checked_serial := -1
var _route_valid := false

func _init() -> void:
	collision_layer = ExploreActorProfile.ACTOR
	collision_mask = ExploreActorProfile.ACTOR | ExploreActorProfile.OBSTACLE
	set_physics_process(false)

func configure(value: StringName, network: RefCounted, route: Dictionary) -> bool:
	if not CityTrafficCatalog.is_drivable(value): return false
	var target_domain := CityTrafficCatalog.domain(value)
	if target_domain not in [&"rail",&"water"] or network == null: return false
	var points: Array = Array(route.get("points",[]))
	if points.size()<2: return false
	for point: Vector3 in points:
		if not point.is_finite(): return false
	kind = value
	domain = target_domain
	graph = network
	_transit_route = route if bool(route.get("transit",false)) else {}
	_route_checked_serial = -1
	_points.assign(points)
	_length = 0.0
	for index in range(1,_points.size()): _length += _points[index-1].distance_to(_points[index])
	if _length <= .01: return false
	_size = CityTrafficCatalog.dimensions(kind)
	if _collider == null:
		_collider = CollisionShape3D.new()
		add_child(_collider)
	var box := BoxShape3D.new()
	box.size = _size
	_collider.shape = box
	_collider.position.y = _size.y*.5
	if is_instance_valid(_visual): _visual.free()
	_visual = CityTrafficCatalog.make_visual(kind)
	add_child(_visual)
	_distance = 0.0
	global_position = _points[0]
	look_at(_points[1],Vector3.UP)
	stop_input()
	return has_support()

func vehicle_size() -> Vector3: return _size
func set_camera_occluded(hidden: bool) -> void:
	if is_instance_valid(_visual): _visual.visible=not hidden
func collision_pose() -> Transform3D: return _collider.global_transform
func collision_shape() -> Shape3D: return _collider.shape
func feet_position() -> Vector3: return global_position
func speed() -> float: return _speed
func landed() -> bool: return has_support()
func stop_input() -> void:
	_speed = 0.0
	velocity = Vector3.ZERO

func _cell(point: Vector3) -> Vector2i: return Vector2i(floori(point.x),floori(point.z))

func has_support() -> bool:
	if graph == null or not global_transform.is_finite(): return false
	if not _transit_route.is_empty():
		if not _transit_route_valid(): return false
		return global_position.distance_to(_rail_pose(_distance).origin)<.08
	if not graph.has_cell(_cell(global_position),domain): return false
	if domain == &"water":
		# Every hull corner must float over current water, including while turning.
		for x: float in [-_size.x*.5,_size.x*.5]:
			for z: float in [-_size.z*.5,_size.z*.5]:
				if not graph.has_cell(_cell(global_transform*Vector3(x,0,z)),domain): return false
	return true

func _transit_route_valid() -> bool:
	var network := graph as ExploreTransitNetwork
	if network != null and _route_checked_serial==network.serial and _route_checked_network==network.get_instance_id(): return _route_valid
	var valid := _validate_transit_route()
	if network != null:
		_route_checked_network = network.get_instance_id()
		_route_checked_serial = network.serial
		_route_valid = valid
	return valid

func _validate_transit_route() -> bool:
	var indices: PackedInt32Array = _transit_route.get("node_point_indices",PackedInt32Array())
	if indices.is_empty():
		if _transit_route.nodes.size()!=_points.size(): return false
		for index: int in _points.size(): indices.append(index)
	if indices.size()!=_transit_route.nodes.size(): return false
	for i: int in _transit_route.nodes.size():
		var node: Vector3i = _transit_route.nodes[i]
		if not graph.nodes.has(node): return false
		var point_index := int(indices[i])
		if point_index<0 or point_index>=_points.size(): return false
		if not graph.nodes[node].point.is_equal_approx(_points[point_index]): return false
		if i>0:
			var previous: Vector3i = _transit_route.nodes[i-1]
			if not graph.nodes[previous].links.has(node) or not graph.nodes[node].links.has(previous): return false
			var edge: PackedVector3Array = graph.edge_points(previous,node)
			var previous_index := int(indices[i-1])
			if point_index-previous_index!=edge.size()-1: return false
			for middle: int in range(1,edge.size()-1):
				if not edge[middle].is_equal_approx(_points[previous_index+middle]): return false
	return true

func _rail_pose(at: float) -> Transform3D:
	if not _transit_route.is_empty(): return ExploreTransitNetwork.sample(_transit_route,at)
	var remaining := clampf(at,0,_length)
	for index in range(1,_points.size()):
		var length := _points[index-1].distance_to(_points[index])
		if remaining <= length or index == _points.size()-1:
			var position := _points[index-1].lerp(_points[index],clampf(remaining/maxf(.0001,length),0,1))
			return Transform3D(Basis.looking_at((_points[index]-_points[index-1]).normalized()),position)
		remaining -= length
	return global_transform

func step(frame: ExploreInputFrame, _camera_yaw: float, delta: float) -> void:
	if not is_finite(delta) or not frame.move.is_finite() or not has_support():
		stop_input()
		recovery_requested.emit("This vehicle's route is no longer available.")
		return
	var dt := clampf(delta,0,.1)
	if dt<=0: return
	var throttle := clampf(-frame.move.y,-1,1)
	var top_speed := .7 if domain == &"rail" else .35
	_speed = move_toward(_speed,top_speed*throttle,(.8 if frame.brake else .25)*dt)
	if frame.brake: _speed = move_toward(_speed,0,1.5*dt)
	var before := global_transform
	var old_distance := _distance
	if domain == &"rail":
		_distance = clampf(_distance+_speed*dt,0,_length)
		global_transform = _rail_pose(_distance)
	else:
		rotation.y -= frame.move.x*signf(_speed)*dt*.8
		global_position += -global_basis.z*_speed*dt
		global_position.y = graph.point(_cell(global_position),domain).y
	if not has_support() or test_move(before,global_position-before.origin):
		global_transform = before
		_distance = old_distance
		stop_input()
	# Relative approximate equality grows with world coordinates and treats
	# the first 60 Hz acceleration steps as stationary. Stop only if the
	# accepted physical position actually did not move.
	elif global_position == before.origin: stop_input()
	else: velocity = (global_position-before.origin)/dt
