# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Arcade car; the session owns ticks and recovery. No simulation state is read.
class_name ExploreCar
extends CharacterBody3D

signal recovery_requested(reason: String)
const VISUAL := preload("res://assets/desert-dreams-exploration/car.tscn")
const STEP := .045
## Onramps are one-tile quarter turns about 8 m in radius; at full speed the
## car's turning circle is about 1.6 tiles and cannot follow them. On a ramp,
## or with one just ahead, the car eases to a speed whose circle fits the turn.
const RAMP_SPEED := .65
const RAMP_LOOKAHEAD := .55
const RAMP_BRAKING := 1.5
## Leaving the road graph restores the previous pose. A glancing exit turns the
## car along the crossed edge and scrubs this fraction of its speed once per
## contact (consecutive brushes within EDGE_CONTACT_TICKS do not compound),
## like brushing a curb; only a near head-on exit stops it.
const EDGE_SCRUB := .3
const EDGE_TURN := .6
const EDGE_CONTACT_TICKS := 30
## Distance the restored pose steps back from the crossed tile edge.
const EDGE_BACKOFF := .02
var kind: StringName = &"car"
var route_graph: RefCounted
## Read-only motor court, assigned by Explore; never added to traffic routes.
var driveway: Dictionary = {}
var _world: CityTraversalWorld3D
var _visual: ExploreActorVisual
var _collider: CollisionShape3D
var _speed := 0.0
var _grounded := false
var _reported := false
var _reported_pose := Vector3.ZERO
var _edge_contact := 0
var _minimum_normal_y := CityTraversalWorld3D.MIN_NORMAL_Y

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
	# Terrain's full height lattice can produce very steep dry slopes. Only
	# the mayor's SUV treats these as floors; ordinary cars keep 55 degrees.
	_minimum_normal_y = cos(deg_to_rad(89.0)) if kind == &"mayormobile" else CityTraversalWorld3D.MIN_NORMAL_Y
	floor_max_angle = deg_to_rad(89.0 if kind == &"mayormobile" else 55.0)
	# Tilting the long SUV at a steep slope transition can lift every bottom
	# corner just beyond the road car's snap. Keep contact within its half-body
	# diagonal, without granting the larger curb step to walls/obstacles.
	floor_snap_length = .20 if kind == &"mayormobile" else STEP
	var shape := BoxShape3D.new()
	shape.size = CityTrafficCatalog.dimensions(kind)
	_collider.shape = shape
	_collider.position.y = shape.size.y*.5
	_visual.free()
	_visual = CityTrafficCatalog.make_detailed_visual(kind)
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
	return _world.support_near(at,rise,drop,[get_rid()],_minimum_normal_y)

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
	if test_move(global_transform,Vector3.DOWN*STEP,contact,.001,true) and contact.get_normal().y>=_minimum_normal_y:
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

## RAMP_SPEED while the car is on an onramp or one lies within RAMP_LOOKAHEAD
## along its direction of travel; otherwise no limit. Several samples keep a
## turn into a ramp mouth from skipping past the ramp's inside corner.
func _ramp_speed_cap() -> float:
	if route_graph == null or not route_graph.has_method(&"is_ramp"): return INF
	var direction := -global_basis.z*(1.0 if _speed>=0 else -1.0)
	for i: int in 5:
		var point := global_position+direction*RAMP_LOOKAHEAD*i/4.0
		if route_graph.is_ramp(Vector2i(floori(point.x),floori(point.z))): return RAMP_SPEED
	return INF

## Returns to `before` after the move left the road graph. Heading components
## across each crossed tile edge are removed: a glancing exit continues along the
## edge with scrubbed speed, while a near head-on exit (or a corner) stops.
func _deflect_from_edge(before: Transform3D) -> void:
	var inside := Vector2i(floori(before.origin.x),floori(before.origin.z))
	var outside := Vector2i(floori(global_position.x),floori(global_position.z))
	var heading := Vector2(-before.basis.z.x,-before.basis.z.z).normalized()
	var along := heading
	if outside.x != inside.x: along.x = 0.0
	if outside.y != inside.y: along.y = 0.0
	global_transform = before
	velocity = Vector3.ZERO
	# Back off the crossed edge so the next move does not slide over it again.
	var back := Vector3(signf(inside.x-outside.x),0,signf(inside.y-outside.y))*EDGE_BACKOFF
	if not test_move(global_transform,back): global_position += back
	if along.length()<.3:
		_speed = 0.0
		return
	if _edge_contact<=0: _speed *= 1.0-EDGE_SCRUB
	_edge_contact = EDGE_CONTACT_TICKS
	rotation.y = lerp_angle(rotation.y,atan2(-along.x,-along.y),EDGE_TURN)

## Another vehicle or a person is a solid body, not a wall to slide along at
## speed: driving into one removes the part of the speed aimed at it (all of
## it head-on), so the car stops against it instead of grinding past.
func _absorb_actor_contacts() -> void:
	if absf(_speed) <= .0001: return
	var heading := -global_basis.z*signf(_speed)
	var flat := Vector2(heading.x,heading.z)
	if flat.length_squared() < .000001: return
	flat = flat.normalized()
	for index: int in get_slide_collision_count():
		var contact := get_slide_collision(index)
		var body := contact.get_collider() as CollisionObject3D
		if body == null or body.collision_layer & ExploreActorProfile.ACTOR == 0: continue
		var normal := Vector2(contact.get_normal().x,contact.get_normal().z)
		if normal.length_squared() < .000001: continue
		var into := -flat.dot(normal.normalized())
		if into > 0: _speed *= 1.0-into

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
	if _edge_contact>0: _edge_contact -= 1
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
	var cap := _ramp_speed_cap()
	target = clampf(target,-cap,cap)
	_speed = move_toward(_speed,target,(1.1 if opposing else .55)*dt)
	if absf(_speed)>cap: _speed = move_toward(_speed,signf(_speed)*cap,RAMP_BRAKING*dt)
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
	if is_on_floor() and get_floor_normal().y>=_minimum_normal_y:
		normal = get_floor_normal()
	velocity = direction.slide(normal).normalized()*_speed
	velocity.y -= .613*dt
	_curb(Vector3(velocity.x,0,velocity.z)*dt)
	var physical_dt := get_physics_process_delta_time()
	var factor := dt/physical_dt if physical_dt>0 else 1.0
	velocity *= factor
	_clear_lateral_rest_recovery()
	move_and_slide()
	# Explicit snap remains bounded by this vehicle's floor_snap_length even
	# when projected uphill velocity is positive at the crest of a convex facet.
	apply_floor_snap()
	velocity /= factor
	_absorb_actor_contacts()
	if not on_drivable_ground():
		if kind == &"mayormobile":
			# A shoreline is a barrier, not a recovery/teleport. Restore the last
			# dry physical pose and allow the driver to steer or reverse away.
			global_transform = before
			stop_input()
		else: _deflect_from_edge(before)
	_grounded = not _ground_support().is_empty()
	if not global_position.is_finite(): _request("nonfinite")
	elif not _inside(): _request("bounds")
	elif _world.touches_water(global_position): _request("water")
	elif not _grounded: _request("unsupported")
	_visual.set_motion(_speed,steering,false)
	_visual.advance_visual(dt)

## The mayor's unique SUV can use every dry terrain surface. Other vehicles
## retain the road rule plus the bounded ground-level motor court.
func on_drivable_ground() -> bool:
	if kind == &"mayormobile":
		return is_instance_valid(_world) and not _world.touches_water_footprint(_collider.global_transform,vehicle_size())
	if route_graph == null or route_graph.has_cell(Vector2i(floori(global_position.x),floori(global_position.z)),&"road"): return true
	if is_instance_valid(_world) and _world.inside_road_tunnel(global_position): return true
	return ExploreMayorsHouse.allows(driveway,global_transform,vehicle_size())
