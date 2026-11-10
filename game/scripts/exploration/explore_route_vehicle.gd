# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Session-only rail and water controls over the read-only traffic graph.
class_name ExploreRouteVehicle
extends CharacterBody3D

const RailPath := preload("res://scripts/exploration/explore_rail_path.gd")
var _rail_path: Dictionary = {}
var _rail_wheels: Array[Dictionary] = []
var _surface_route: Dictionary = {}
var _portal_profiles: Dictionary = {}
var _surface_points: Array = []
var _surface_revision := -1
var _surface_valid := false
var _axle_span := .2
var _fitted_span := .2
var _pose_at := INF
var _fitted_pose := Transform3D.IDENTITY
var _suspension: MultiMeshInstance3D

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
var _visual: ExploreActorVisual
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
	if not _transit_route.is_empty() and not _transit_route_valid(): return false
	_rail_path = {}
	_portal_profiles.clear()
	if network is ExploreTransitNetwork:
		for key: Vector3i in route.get("nodes",[]):
			if key.y not in [2,3]: continue
			var cell := Vector2i(key.x,key.z)
			_portal_profiles[cell] = CityPortal3D.profile(network.city,cell,CityGeometry3D.HEIGHT)
	_surface_route = {}
	if domain == &"rail" and network is CityTrafficGraph:
		_rail_path = RailPath.surface(network,route,points)
		if _rail_path.is_empty(): return false
		_surface_route = route.duplicate()
		_surface_points = points.duplicate()
		_surface_revision = network.revision
		_surface_valid = true
		points = _rail_path.movement
	elif domain == &"rail":
		var track := PackedVector3Array(points)
		# A subway itinerary may emerge onto the surface railway. Preserve the
		# service route for validation, but drive its diagonal pieces on steel.
		var transit := network as ExploreTransitNetwork
		if transit != null:
			var indices: PackedInt32Array = route.get("node_point_indices",PackedInt32Array())
			for index: int in range(1,indices.size()-1):
				var key: Vector3i = route.nodes[index]
				if key.y!=0: continue
				var cell := Vector2i(key.x,key.z)
				var mask := CityNetworks3D.network_mask(transit.city.building.atv(cell),NetworkShapes.Family.RAIL)
				if mask not in [3,6,9,12]: continue
				var before: Vector3i = route.nodes[index-1]-key
				var after: Vector3i = route.nodes[index+1]-key
				var middle := Vector2(.5,.5)+Vector2(before.x+after.x,before.z+after.z)*.25
				track[indices[index]] = transit.graph.point(cell,&"rail",middle)
		points = Array(track)
		_rail_path = RailPath.prepare(track)
	_points.assign(points)
	_length = 0.0
	for index in range(1,_points.size()): _length += _points[index-1].distance_to(_points[index])
	if _length <= .01: return false
	if not _transit_route.is_empty() and not _transit_route_valid(): return false
	_size = CityTrafficCatalog.dimensions(kind)
	if _collider == null:
		_collider = CollisionShape3D.new()
		add_child(_collider)
	var box := BoxShape3D.new()
	box.size = _size
	_collider.shape = box
	_collider.position.y = _size.y*.5
	if is_instance_valid(_visual): _visual.free()
	_visual = CityTrafficCatalog.make_detailed_visual(kind)
	add_child(_visual)
	_distance = 0.0
	_prepare_rail_wheels()
	global_position = _points[0]
	look_at(_points[1],Vector3.UP)
	if domain == &"rail":
		global_transform = _rail_pose(0.0)
		_align_rail_wheels()
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
	if is_instance_valid(_visual): _visual.set_motion(0.0,0.0,false)

func _cell(point: Vector3) -> Vector2i: return Vector2i(floori(point.x),floori(point.z))

func has_support() -> bool:
	if graph == null or not global_transform.is_finite(): return false
	if not _transit_route.is_empty():
		if not _transit_route_valid(): return false
		return global_position.distance_to(_rail_pose(_distance).origin)<.08
	if not graph.has_cell(_cell(global_position),domain): return false
	if domain == &"rail" and not _surface_route_valid(): return false
	if domain == &"water":
		# Every hull corner must float over current water, including while turning.
		for x: float in [-_size.x*.5,_size.x*.5]:
			for z: float in [-_size.z*.5,_size.z*.5]:
				if not graph.has_cell(_cell(global_transform*Vector3(x,0,z)),domain): return false
	return true

func _surface_route_valid() -> bool:
	if graph.revision!=_surface_revision:
		var updated := RailPath.surface(graph,_surface_route,_surface_points)
		_surface_valid = not updated.is_empty() and updated.points==_rail_path.points
		_surface_revision = graph.revision
	return _surface_valid

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
	var network := graph as ExploreTransitNetwork
	if network == null: return false
	var projected := network.project_nodes(_transit_route.get("nodes",[]))
	if projected.is_empty(): return false
	var points: PackedVector3Array = projected.points
	var claimed: PackedVector3Array = _transit_route.get("points",PackedVector3Array())
	if points.size()!=claimed.size(): return false
	for index: int in points.size():
		if not points[index].is_equal_approx(claimed[index]): return false
	var indices: PackedInt32Array = _transit_route.get("node_point_indices",PackedInt32Array())
	return indices.is_empty() or indices==projected.node_point_indices

func _prepare_rail_wheels() -> void:
	_rail_wheels.clear()
	_pose_at = INF
	if is_instance_valid(_suspension): _suspension.free()
	_axle_span = .2
	if domain != &"rail": return
	for entry: Dictionary in _visual._wheel_metadata:
		var wheel := _visual.find_child(String(entry.get("node","")),true,false) as Node3D
		if wheel == null: continue
		var rest := global_transform.affine_inverse()*wheel.global_transform
		_rail_wheels.append({"node":wheel,"rest":rest,"radius":float(entry.radius_m)/16.0})
	if not _rail_wheels.is_empty():
		_axle_span = 0.0
		for entry: Dictionary in _rail_wheels:
			_axle_span = maxf(_axle_span,absf(entry.rest.origin.z))
	if _rail_wheels.is_empty(): return
	_suspension = MultiMeshInstance3D.new()
	_suspension.name = "RailSuspension"
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var finish := StandardMaterial3D.new()
	finish.albedo_color = Color(.20,.23,.24)
	finish.roughness = .8
	mesh.material = finish
	_suspension.multimesh = MultiMesh.new()
	_suspension.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_suspension.multimesh.mesh = mesh
	_suspension.multimesh.instance_count = _rail_wheels.size()
	_visual.add_child(_suspension)

func _surface_graph() -> CityTrafficGraph:
	return graph as CityTrafficGraph if graph is CityTrafficGraph else (graph as ExploreTransitNetwork).graph

func _surface_height(point: Vector3, classify: bool = true) -> float:
	var surface := _surface_graph()
	var cell := _cell(point)
	if surface != null and (graph is CityTrafficGraph or surface.has_cell(cell,&"rail")):
		var height := surface.point(cell,&"rail",Vector2(point.x-cell.x,point.z-cell.y)).y
		if graph is CityTrafficGraph or not classify or absf(point.y-height)<.04: return height
	var portal: Dictionary = _portal_profiles.get(cell,{})
	if not portal.is_empty():
		var d := (Vector2(point.x-cell.x,point.z-cell.y)-Vector2(portal.outside)).dot(portal.inward)
		var route_height := lerpf(portal.floor_start,portal.floor_end,d/float(portal.depth))
		if d>=-.0001 and d<=float(portal.depth)+.03 and (not classify or absf(point.y-route_height)<.04):
			# The visible strip extends .03 beyond the mouth; its quad spans
			# that full length, matching CityNetworks3D._portal_strip.
			return lerpf(portal.floor_start,portal.floor_end,clampf(d/(float(portal.depth)+.03),0,1))
	return INF

func _steel_lift(point: Vector3) -> float:
	# Exposed rail and converter heads stand .014 above their running floor;
	# tunnel heads are .001 below the itinerary. Classify at the centreline.
	return .014 if is_finite(_surface_height(point)) else -.001

func _steel_point(point: Vector3) -> Vector3:
	var height := _surface_height(point)
	return Vector3(point.x,height+.014 if is_finite(height) else point.y-.001,point.z)

func _track_pose(at: float) -> Transform3D:
	var pose := RailPath.sample(_rail_path,float(_rail_path.offset)+at)
	pose.origin = _steel_point(pose.origin)
	return pose

## The rigid chassis bridges the grade while each wheel follows its own rail.
## Sampling either side also makes pitch and yaw continuous at grade breaks.
func _fit_span(at: float, physical: float) -> float:
	var span := physical
	for iteration: int in 4:
		var chord := _track_pose(at+span).origin.distance_to(_track_pose(at-span).origin)
		span = clampf(span*2.0*physical/maxf(chord,.0001),physical,physical*1.5)
	return span

func _rail_pose(at: float) -> Transform3D:
	if at==_pose_at: return _fitted_pose
	# The axles determine yaw and lateral placement; using the body ends here
	# pulls the middle wheels far outside the chassis on a tight subway bend.
	_fitted_span = _fit_span(at,_axle_span)
	var front := _track_pose(at+_fitted_span).origin
	var rear := _track_pose(at-_fitted_span).origin
	var center := (front+rear)*.5
	var heading := Vector3(front.x-rear.x,0,front.z-rear.z).normalized()
	# Pitch spans the whole underframe so its overhang clears the next grade.
	var body_span := _fit_span(at,maxf(_axle_span,_size.z*.5))
	var nose := _track_pose(at+body_span).origin
	var tail := _track_pose(at-body_span).origin
	var pitch := atan2(nose.y-tail.y,Vector2(nose.x-tail.x,nose.z-tail.z).length())
	var forward := heading*cos(pitch)+Vector3.UP*sin(pitch)
	center.y = (nose.y+tail.y)*.5
	var across := _rail_contact(at,CityNetworks3D.RAIL_HALF_GAUGE)-_rail_contact(at,-CityNetworks3D.RAIL_HALF_GAUGE)
	var pose := Transform3D(Basis.looking_at(forward,across.cross(forward).normalized()),center)
	# Keep the low chassis above a convex crest between the axles. The wheels
	# retain contact independently instead of rising with the rigid body.
	var clearance := .018 # Lowest rigid underframe, above the articulated wheels.
	var half_length := body_span
	var samples: Array[Vector3] = [_track_pose(at-half_length).origin,_track_pose(at+half_length).origin]
	var lengths: PackedFloat32Array = _rail_path.distances
	var points: PackedVector3Array = _rail_path.points
	var distance := float(_rail_path.offset)+at
	var index := RailPath.segment(_rail_path,distance-half_length)
	while index<points.size() and lengths[index]<=distance+half_length:
		if lengths[index]>=distance-half_length: samples.append(_steel_point(points[index]))
		index += 1
	var lift := 0.0
	for point: Vector3 in samples:
		var local := pose.affine_inverse()*point
		lift = maxf(lift,(local.y-clearance)/pose.basis.y.y)
	pose.origin.y += lift
	_pose_at = at
	_fitted_pose = pose
	return pose

func _rail_contact(at: float, side: float) -> Vector3:
	var distance := float(_rail_path.offset)+at
	var center := RailPath.sample(_rail_path,distance).origin
	var contact := RailPath.offset_point(_rail_path,distance,side)
	var lift := _steel_lift(center)
	if lift>0:
		var height := _surface_height(contact,false)
		if is_finite(height): contact.y = height
	contact.y += lift
	return contact

func _align_rail_wheels() -> void:
	_rail_pose(_distance) # Restore the cached span after a blocked movement rolls back.
	for index: int in _rail_wheels.size():
		var entry: Dictionary = _rail_wheels[index]
		var rest: Transform3D = entry.rest
		var at := _distance-rest.origin.z*_fitted_span/maxf(_axle_span,.0001)
		var contact := _rail_contact(at,rest.origin.x)
		var radius := float(entry.radius)
		var tangent := _rail_contact(at+radius,rest.origin.x)-_rail_contact(at-radius,rest.origin.x)
		var across := _rail_contact(at,CityNetworks3D.RAIL_HALF_GAUGE)-_rail_contact(at,-CityNetworks3D.RAIL_HALF_GAUGE)
		var pose := Transform3D(Basis.looking_at(tangent.normalized(),across.cross(tangent).normalized()),contact)
		var wheel: Node3D = entry.node
		wheel.global_transform = Transform3D(pose.basis*rest.basis,contact+pose.basis.y*float(entry.radius))
		# Link each articulated axle to the underframe. Without these supports,
		# a wheel following a sharp valley appears detached from the chassis.
		var top := Vector3(rest.origin.x*.72,.03,rest.origin.z)
		var bottom := to_local(wheel.global_position-pose.basis.x*rest.origin.x*.28)
		var along := bottom-top
		var up := along.normalized() if along.length_squared()>.00000001 else Vector3.DOWN
		var guide := Vector3.RIGHT if absf(up.z)>.9 else Vector3.FORWARD
		var right := guide.cross(up).normalized()
		var basis := Basis(right,up,right.cross(up))*Basis.from_scale(Vector3(.009,maxf(along.length(),.001),.009))
		_suspension.multimesh.set_instance_transform(index,Transform3D(basis,(top+bottom)*.5))

func step(frame: ExploreInputFrame, _camera_yaw: float, delta: float) -> void:
	if not is_finite(delta) or not frame.move.is_finite() or not has_support():
		stop_input()
		recovery_requested.emit("This vehicle's route is no longer available.")
		return
	var dt := clampf(delta,0,.1)
	if dt<=0: return
	var throttle := clampf(-frame.move.y,-1,1)
	var speed_scale := 3.0 if kind == &"sailboat" else 1.0
	var top_speed := (.7 if domain == &"rail" else .35)*speed_scale
	_speed = move_toward(_speed,top_speed*throttle,(.8 if frame.brake else .25)*speed_scale*dt)
	if frame.brake: _speed = move_toward(_speed,0,1.5*speed_scale*dt)
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
	if domain == &"rail": _align_rail_wheels()
	_visual.set_motion(_speed,0.0,false)
	_visual.advance_visual(dt)
