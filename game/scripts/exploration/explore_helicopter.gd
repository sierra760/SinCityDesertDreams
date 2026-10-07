# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Hovering arcade flight using swept full-size clearance, owned by the session.
class_name ExploreHelicopter
extends CharacterBody3D

signal recovery_requested(reason: String)
const VISUAL := preload("res://assets/desert-dreams-exploration/helicopter.tscn")
var _world: CityTraversalWorld3D
var _visual: ExploreActorVisual
var _collider: CollisionShape3D
var _local_collision_bounds: AABB
var _grounded := false
var _reported := false
var _reported_pose := Vector3.ZERO
var _altitude := 0.0

func _init() -> void:
	collision_layer = ExploreActorProfile.ACTOR
	collision_mask = ExploreActorProfile.WORLD | ExploreActorProfile.ACTOR
	safe_margin = .001
	floor_max_angle = deg_to_rad(55)
	var collider := CollisionShape3D.new()
	collider.shape = ExploreActorProfile.shape(ExploreActorProfile.Mode.FLY)
	collider.position.y = .07
	add_child(collider)
	_collider = collider
	_local_collision_bounds = collider.shape.get_debug_mesh().get_aabb()
	_visual = VISUAL.instantiate()
	add_child(_visual)
	set_physics_process(false)

func bind(traversal: CityTraversalWorld3D) -> void:
	_world = traversal
	stop_input()

func speed() -> float: return velocity.length()
func altitude() -> float: return _altitude
func feet_position() -> Vector3: return global_position
func landed() -> bool: return _grounded

func stop_input() -> void:
	velocity = Vector3.ZERO
	_reported = false

func _request(reason: String) -> void:
	velocity = Vector3.ZERO
	_grounded = false
	if _reported: return
	_reported = true
	_reported_pose = global_position
	recovery_requested.emit(reason)

func _inside() -> bool:
	# Use the same transformed collision-box bounds as traversal admission.
	# A fixed any-yaw radius would reject a clear upright edge parking pose.
	var bounds: AABB = _collider.global_transform*_local_collision_bounds
	return bounds.position.x>=0 and bounds.position.z>=0 and bounds.end.x<=City.WIDTH and bounds.end.z<=City.HEIGHT

func _support(drop: float = .006) -> Dictionary:
	return _world.support_near(global_position,.003,drop,[get_rid()])

func has_support() -> bool:
	# Landing is a property of the swept aircraft box, not a single ray below
	# its centre. At a deck edge a skid can touch dry floor while that ray misses.
	if not is_instance_valid(_world) or not is_inside_tree(): return false
	var contact := move_and_collide(Vector3.DOWN*.006,true,.001,true)
	if contact == null or contact.get_normal().y<CityTraversalWorld3D.MIN_NORMAL_Y: return false
	var floor_body := contact.get_collider() as CollisionObject3D
	if floor_body == null or floor_body.collision_layer & ExploreActorProfile.WORLD == 0: return false
	return not _world.touches_water(contact.get_position()+Vector3.UP*.002)

func step(frame: ExploreInputFrame, camera_yaw: float, delta: float) -> void:
	if not is_instance_valid(_world) or not is_inside_tree(): return
	if not global_transform.is_finite() or not velocity.is_finite() or not frame.move.is_finite() or not is_finite(frame.vertical) or not is_finite(delta) or not is_finite(camera_yaw):
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
	var dt := clampf(delta,0,.1)
	if dt<=0: return
	var ceiling := _world.max_flight_y()-.14
	if global_position.y>ceiling:
		# Fit an initially protruding body with its own swept displacement.
		# This is a positional repair, never an arbitrarily large flight speed.
		move_and_collide(Vector3.DOWN*(global_position.y-ceiling),false,.001,true)
		velocity.y = 0.0
		if global_position.y>ceiling+.0001:
			_request("ceiling")
			return
	var supported := has_support()
	if _grounded and not supported:
		_request("unsupported")
		return
	_grounded = supported and velocity.y<=.001
	var input := frame.move.limit_length(1)
	var desired := Basis(Vector3.UP,camera_yaw)*Vector3(input.x,0,input.y)*1.5
	var horizontal := Vector3(velocity.x,0,velocity.z).move_toward(desired,dt*(2.0 if input.is_zero_approx() else 1.0))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = move_toward(velocity.y,clampf(frame.vertical,-1,1)*.5,dt*(2.0 if is_zero_approx(frame.vertical) else 1.0))
	if _grounded and velocity.y<0: velocity.y = 0
	if velocity.y>.001: _grounded = false
	# Rotate only if the full box remains clear at its proposed heading.
	if horizontal.length()>.01:
		var wanted := atan2(-horizontal.x,-horizontal.z)
		var old := rotation.y
		rotation.y = lerp_angle(rotation.y,wanted,1.0-exp(-8.0*dt))
		if test_move(global_transform,Vector3.ZERO) or not _inside(): rotation.y = old
	var motion := velocity*dt
	if global_position.y+motion.y>ceiling:
		motion.y = maxf(0.0,ceiling-global_position.y)
		velocity.y = 0.0
	for iteration: int in 4:
		if motion.length_squared()<.0000000001: break
		var hit := move_and_collide(motion,false,.001,true)
		if hit==null: break
		var normal := hit.get_normal()
		if normal.y>=CityTraversalWorld3D.MIN_NORMAL_Y and velocity.y<=0:
			_grounded = true
		velocity = velocity.slide(normal)
		motion = hit.get_remainder().slide(normal)
	# Support is always local for landing. A separate downward altitude query
	# measures the HUD height and never changes the actor's position or layer.
	_grounded = has_support() and velocity.y<=.001
	if _grounded and velocity.y<0: velocity.y = 0
	var below := _support(32.0)
	_altitude = 0.0 if _grounded else (maxf(0.0,global_position.y-float(below.position.y)) if not below.is_empty() else maxf(0.0,global_position.y))
	if not global_position.is_finite(): _request("nonfinite")
	elif not _inside(): _request("bounds")
	elif _world.touches_water(global_position): _request("water")
	_visual.set_motion(horizontal.length(),0.0,not _grounded)
	_visual.advance_visual(dt)
