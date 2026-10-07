# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Arcade car; the session owns ticks and recovery. No simulation state is read.
class_name ExploreCar
extends CharacterBody3D

signal recovery_requested(reason: String)
const VISUAL := preload("res://assets/desert-dreams-exploration/car.tscn")
const STEP := .045
var kind: StringName = &"car"
var route_graph: RefCounted
var _world: CityTraversalWorld3D
var _visual: ExploreActorVisual
var _collider: CollisionShape3D
var _speed := 0.0
var _grounded := false
var _reported := false
var _reported_pose := Vector3.ZERO

func _init() -> void:
	collision_layer = ExploreActorProfile.ACTOR
	collision_mask = ExploreActorProfile.WORLD | ExploreActorProfile.ACTOR
	safe_margin = .001
	floor_max_angle = deg_to_rad(55)
	floor_snap_length = STEP
	floor_constant_speed = true
	_collider_setup()
	set_physics_process(false)

func _collider_setup() -> void:
	_collider = CollisionShape3D.new()
	_collider.shape = ExploreActorProfile.shape(ExploreActorProfile.Mode.DRIVE)
	_collider.position.y = .04
	add_child(_collider)
	_visual = VISUAL.instantiate()
	add_child(_visual)

func configure_kind(value: StringName) -> bool:
	if not CityTrafficCatalog.is_drivable(value) or CityTrafficCatalog.domain(value) != &"road": return false
	kind = value
	var shape := BoxShape3D.new()
	shape.size = CityTrafficCatalog.dimensions(kind)
	_collider.shape = shape
	_collider.position.y = shape.size.y*.5
	_visual.free()
	_visual = ExploreActorVisual.new()
	_visual.add_child(CityTrafficCatalog.make_visual(kind))
	add_child(_visual)
	return true

func set_camera_occluded(hidden: bool) -> void:
	if is_instance_valid(_visual): _visual.visible = not hidden

func vehicle_size() -> Vector3: return (_collider.shape as BoxShape3D).size
func collision_shape() -> Shape3D: return _collider.shape

func bind(traversal: CityTraversalWorld3D) -> void:
	_world = traversal
	stop_input()

func speed() -> float: return _speed
func feet_position() -> Vector3: return global_position
func landed() -> bool: return _grounded

func collision_pose() -> Transform3D:
	return _collider.global_transform

func has_support() -> bool:
	return is_instance_valid(_world) and is_inside_tree() and global_transform.is_finite() and not _ground_support().is_empty()

func apply_safe_pose(pose: Transform3D) -> void:
	if not pose.is_finite():
		_request("nonfinite")
		return
	stop_input()
	global_transform = Transform3D(Basis(Vector3.UP,pose.basis.get_euler().y),pose.origin)
	_collider.basis = Basis.IDENTITY
	_collider.position = Vector3(0,vehicle_size().y*.5,0)
	_visual.basis = Basis.IDENTITY
	_grounded = false

func stop_input() -> void:
	_speed = 0.0
	velocity = Vector3.ZERO
	_reported = false

func _request(reason: String) -> void:
	_speed = 0.0
	velocity = Vector3.ZERO
	_grounded = false
	if _reported: return
	_reported = true
	_reported_pose = global_position
	recovery_requested.emit(reason)

func _inside() -> bool:
	var shape := _collider.shape as BoxShape3D
	var bounds: AABB = _collider.global_transform*AABB(-shape.size*.5,shape.size)
	return bounds.position.x>=0.0 and bounds.position.z>=0.0 and bounds.end.x<=City.WIDTH and bounds.end.z<=City.HEIGHT

func _support(at: Vector3, rise := .045, drop := .06) -> Dictionary:
	return _world.support_near(at,rise,drop,[get_rid()])

func _ground_support() -> Dictionary:
	# Query the actual tilted box bottom, not yaw-only projections at root Y.
	# At a slope entry those projections can start inside the deck and see its
	# underside while a raised chassis corner is in real floor contact.
	var center := _support(global_position,.003,STEP)
	if not center.is_empty(): return center
	for x: float in [-vehicle_size().x*.5,vehicle_size().x*.5]:
		for z: float in [-vehicle_size().z*.5,vehicle_size().z*.5]:
			var contact := _collider.global_transform*Vector3(x,-vehicle_size().y*.5,z)
			var corner := _support(contact,.003,STEP)
			if not corner.is_empty(): return corner
	# Curved facets may support an edge between sampled corners. Confirm the
	# full current box with a bounded downward sweep, then validate its contact
	# against current environmental geometry rather than any cached floor flag.
	var contact := KinematicCollision3D.new()
	if test_move(global_transform,Vector3.DOWN*STEP,contact,.001,true) and contact.get_normal().y>=CityTraversalWorld3D.MIN_NORMAL_Y:
		var floor_hit := _support(contact.get_position(),.003,STEP)
		if not floor_hit.is_empty(): return floor_hit
	return {}

func _align(support: Dictionary, dt: float) -> void:
	var normal: Vector3 = support.normal
	# Sample actual box bottom corners: yaw-only .11 front probes stop short
	# of the .14 nose, leaving the chassis flat against an incline entrance.
	# Keep each cast within the step budget around the current physical corner.
	var normals := normal
	var count := 1.0
	for x: float in [-vehicle_size().x*.5,vehicle_size().x*.5]:
		for z_corner: float in [-vehicle_size().z*.5,vehicle_size().z*.5]:
			var point := _collider.global_transform*Vector3(x,-vehicle_size().y*.5,z_corner)
			var hit := _support(point,STEP,STEP)
			if not hit.is_empty():
				normals += hit.normal
				count += 1.0
	normal = (normals/count).normalized()
	var z := global_basis.z.slide(normal).normalized()
	var target := Basis(normal.cross(z).normalized(),normal,z)
	var local := (global_basis.orthonormalized().inverse()*target).orthonormalized()
	_collider.basis = _collider.basis.orthonormalized().slerp(local,1.0-exp(-20.0*dt)).orthonormalized()
	_collider.position = _collider.basis.y*vehicle_size().y*.5
	_visual.basis = _visual.basis.orthonormalized().slerp(local,1.0-exp(-12.0*dt)).orthonormalized()

## Godot depenetrates a resting box before every move. Against the thin
## triangles of a finely tessellated curved incline that resting contact can
## resolve along a triangle-edge axis, shoving the chassis sideways or back by
## more than a slow tick advances. Start such a move one margin clear instead.
func _clear_lateral_rest_recovery() -> void:
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = global_transform
	parameters.margin = safe_margin
	var result := PhysicsTestMotionResult3D.new()
	PhysicsServer3D.body_test_motion(get_rid(),parameters,result)
	var recovery := result.get_travel()
	if Vector2(recovery.x,recovery.z).length()<=maxf(absf(recovery.y),safe_margin): return
	if test_move(global_transform,Vector3.UP*safe_margin): return
	global_position.y += safe_margin

func _curb(motion: Vector3) -> void:
	# A tilted chassis reaching a level landing is still traversing a slope;
	# root-to-landing height is not a discrete curb height.
	if _collider.global_basis.y.dot(Vector3.UP)<.995: return
	var current := _ground_support()
	if current.is_empty() or current.normal.y<.98: return
	if motion.length_squared()<.000000001 or not test_move(global_transform,motion): return
	var direction := motion.normalized()
	var probes: Array[Vector3] = [global_position+direction*(vehicle_size().z*.5+.015+motion.length())]
	# An oblique edge reaches a leading box corner before the centerline.
	# Probe those actual bottom corners just beyond the requested motion so
	# the curb height comes from the contacted surface, including in reverse.
	var half := (_collider.shape as BoxShape3D).size*.5
	for x: float in [-half.x,half.x]:
		for z: float in [-half.z,half.z]:
			var corner := _collider.global_transform*Vector3(x,-half.y,z)
			var offset := Vector3(corner.x-global_position.x,0,corner.z-global_position.z)
			if offset.dot(direction)<=0: continue
			corner += motion+direction*(safe_margin+.002)
			corner.y = global_position.y
			probes.append(corner)
	for probe: Vector3 in probes:
		var support := _support(probe,STEP+.002,.003)
		if support.is_empty(): continue
		# A sloped floor is handled by sliding, not by lifting the chassis like
		# a discrete curb. Otherwise repeated ramp probes launch it off support.
		if support.normal.y<.98: continue
		var rise: float = support.position.y-global_position.y
		if rise<=.002 or rise>STEP: continue
		var lifted := global_transform
		var up := Vector3.UP*(rise+.002)
		if test_move(lifted,up): continue
		lifted.origin += up
		if test_move(lifted,motion): continue
		global_transform = lifted
		return

func step(frame: ExploreInputFrame, camera_yaw: float, delta: float) -> void:
	if not is_instance_valid(_world) or not is_inside_tree(): return
	if not global_transform.is_finite() or not velocity.is_finite() or not frame.move.is_finite() or not is_finite(delta) or not is_finite(camera_yaw):
		_request("nonfinite")
		return
	if _reported:
		if global_position.is_equal_approx(_reported_pose): return
		_reported = false
	if not _inside():
		_request("bounds")
		return
	if _world.touches_water(global_position):
		_request("water")
		return
	var before := global_transform
	var dt := clampf(delta,0,.1)
	if dt<=0: return
	var support := _ground_support()
	if support.is_empty():
		_request("unsupported")
		return
	_grounded = true
	var throttle := clampf(-frame.move.y,-1,1)
	var opposing := _speed*throttle<0
	var target := 0.0 if opposing else 1.2*maxf(throttle,0)-.3*maxf(-throttle,0)
	_speed = move_toward(_speed,target,(1.1 if opposing else .55)*dt)
	if frame.brake: _speed = move_toward(_speed,0,1.5*dt)
	var steering := clampf(frame.move.x,-1,1)
	if absf(_speed)>.001:
		rotation.y -= steering*signf(_speed)*(2.5/(1.0+absf(_speed)*2.0))*dt
	global_basis = global_basis.orthonormalized()
	_align(support,dt)
	var direction := -global_basis.z
	# Preserve the uphill component of the real contact plane. Replacing Y
	# with gravity every tick continually drives a long pitched box into the
	# inner ramp facet instead of advancing along its validated floor.
	var normal: Vector3 = support.normal
	if is_on_floor() and get_floor_normal().y>=CityTraversalWorld3D.MIN_NORMAL_Y:
		normal = get_floor_normal()
	velocity = direction.slide(normal).normalized()*_speed
	velocity.y -= .613*dt
	_curb(Vector3(velocity.x,0,velocity.z)*dt)
	var physical_dt := get_physics_process_delta_time()
	var factor := dt/physical_dt if physical_dt>0 else 1.0
	velocity *= factor
	_clear_lateral_rest_recovery()
	move_and_slide()
	# Explicit snap remains bounded by STEP even when projected uphill velocity
	# is positive at the crest of a convex facet.
	apply_floor_snap()
	velocity /= factor
	if route_graph != null and not route_graph.has_cell(Vector2i(floori(global_position.x),floori(global_position.z)),&"road") and not _world.inside_road_tunnel(global_position):
		apply_safe_pose(before)
	_grounded = not _ground_support().is_empty()
	if not global_position.is_finite(): _request("nonfinite")
	elif not _inside(): _request("bounds")
	elif _world.touches_water(global_position): _request("water")
	elif not _grounded: _request("unsupported")
	_visual.set_motion(_speed,steering,false)
	_visual.advance_visual(dt)
