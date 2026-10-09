# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Tile-scale walking for the Explore session. The root transform is at the feet.
class_name ExplorePedestrian
extends CharacterBody3D

signal recovery_requested(reason: String)

var character := "woman"
const STEP := .045
const GRAVITY := .613
const SKIN := .001
var transit_support: Node3D
var _support_frame: Node3D
var _support_transform := Transform3D.IDENTITY
var _world: CityTraversalWorld3D
var _visual: ExploreActorVisual
var _shape: Shape3D
var _jump_time := 0.0
var _reported := false
var _reported_pose := Vector3.ZERO
var _grounded := false

func _init() -> void:
	collision_layer = ExploreActorProfile.ACTOR
	collision_mask = ExploreActorProfile.WORLD | ExploreActorProfile.ACTOR
	safe_margin = SKIN
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = .045
	floor_constant_speed = true
	# Riding is handled by the explicit carriage support frame, including turns.
	platform_floor_layers = 0
	platform_wall_layers = 0
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	_shape = ExploreActorProfile.shape(ExploreActorProfile.Mode.WALK)
	var collider := CollisionShape3D.new()
	collider.shape = _shape
	collider.position.y = ExploreActorProfile.geometry(ExploreActorProfile.Mode.WALK).foot_offset
	add_child(collider)
	_visual = ExploreCharacterCatalog.make_visual(character)
	add_child(_visual)
	set_physics_process(false)

## Replace only the appearance. Feet, capsule, velocity and transit state stay
## on this actor, including while it is hidden inside an occupied vehicle.
func set_character(value: String) -> void:
	var choice := ExploreCharacterCatalog.sanitize(value)
	if choice == character: return
	var previous := _visual
	_visual = ExploreCharacterCatalog.make_visual(choice)
	_visual.transform = previous.transform
	_visual.visible = previous.visible
	add_child(_visual)
	_visual.set_motion(previous._speed,previous._steering,previous._airborne)
	remove_child(previous)
	previous.free()
	character = choice

func bind(traversal: CityTraversalWorld3D) -> void:
	_world = traversal
	stop_input()

func stop_input() -> void:
	velocity = Vector3.ZERO
	_jump_time = 0.0
	_reported = false
	if is_instance_valid(_visual): _visual.set_motion(0.0,0.0,not _grounded)

## Put the walker at `pose`, standing still and with the model facing the
## pose's forward. The model keeps its own yaw while walking (it turns toward
## the motion), so a bare transform assignment leaves it facing wherever it
## last walked, on top of the body's new yaw.
func place(pose: Transform3D) -> void:
	clear_support_frame()
	global_transform = pose
	if is_instance_valid(_visual): _visual.rotation.y = 0.0
	stop_input()

func set_camera_occluded(hidden: bool) -> void:
	# Only the visible model is hidden; the controller still sees an active
	# pedestrian and keeps physical walking, doors and moving support running.
	if is_instance_valid(_visual): _visual.visible = not hidden

func clear_support_frame() -> void:
	_support_frame = null
	_support_transform = Transform3D.IDENTITY

func _apply_support_motion() -> void:
	if not is_instance_valid(_support_frame):
		clear_support_frame()
		return
	var current := _support_frame.global_transform
	if not current.is_finite():
		clear_support_frame()
		return
	var change := current*_support_transform.affine_inverse()
	global_transform = change*global_transform
	velocity = change.basis*velocity
	_support_transform = current

func _transit_contains(point: Vector3) -> bool:
	return is_instance_valid(transit_support) and transit_support.contains(point)

func _support_near(point: Vector3, rise: float, drop: float) -> Dictionary:
	if is_instance_valid(transit_support):
		var support: Dictionary = transit_support.support_for(point)
		if not support.is_empty():
			var difference := float(support.position.y)-point.y
			if difference>=-drop-.002 and difference<=rise+.002: return support
	return _world.support_near(point,rise,drop,_exclude())

func _update_support_frame() -> void:
	var frame: Node3D
	if is_instance_valid(transit_support):
		var support: Dictionary = transit_support.support_for(global_position)
		frame = support.get("frame")
	if frame != _support_frame:
		_support_frame = frame
	if is_instance_valid(frame): _support_transform = frame.global_transform
	else: clear_support_frame()

func feet_position() -> Vector3:
	return global_position

func landed() -> bool:
	return _grounded and _jump_time<=0.0

func _request(reason: String) -> void:
	velocity = Vector3.ZERO
	_grounded = false
	if _reported: return
	_reported = true
	_reported_pose = global_position
	recovery_requested.emit(reason)

func _inside(feet: Vector3) -> bool:
	return feet.x>=.018 and feet.z>=.018 and feet.x<=City.WIDTH-.018 and feet.z<=City.HEIGHT-.018

func _exclude() -> Array[RID]:
	return [get_rid()]

func _step_up(motion: Vector3) -> bool:
	if motion.length_squared()<.000000001: return false
	var obstructed := test_move(global_transform,motion)
	# move_and_slide can stop at its separation margin while the next tiny
	# acceleration step is too short to register in test_move. Also count
	# last frame's wall contacts that oppose this requested direction.
	for index: int in get_slide_collision_count():
		var normal := get_slide_collision(index).get_normal()
		if absf(normal.y)<.5 and normal.dot(motion.normalized())<-.5:
			obstructed = true
	if not obstructed: return false
	# Probe past the capsule lip, then require a real top within the step budget.
	# The short forward sweep remains bounded even on a stalled frame.
	var forward := motion.normalized()*maxf(motion.length(),.024)
	var support := _support_near(global_position+forward,STEP+.002,.003)
	if support.is_empty(): return false
	var rise: float = support.position.y-global_position.y
	if rise<=.002 or rise>STEP: return false
	var lifted := global_transform
	var lift := Vector3.UP*(rise+SKIN*2.0)
	if test_move(lifted,lift): return false
	lifted.origin += lift
	if test_move(lifted,forward): return false
	lifted.origin += forward
	var shape_at := lifted
	shape_at.origin.y += .0575
	if not _world.has_clearance(shape_at,_shape,_exclude()): return false
	if _world.touches_water(support.position) and not _transit_contains(support.position): return false
	global_transform = lifted
	velocity.y = 0.0
	return true

func step(frame: ExploreInputFrame, camera_yaw: float, delta: float) -> void:
	if not is_instance_valid(_world) or not is_inside_tree(): return
	if not global_transform.is_finite() or not velocity.is_finite():
		_request("nonfinite")
		return
	if not is_finite(delta) or not is_finite(camera_yaw) or not frame.move.is_finite():
		_request("nonfinite")
		return
	_apply_support_motion()
	if _reported:
		if global_position.is_equal_approx(_reported_pose): return
		_reported = false
	if not _inside(global_position):
		_request("bounds")
		return
	if _world.touches_water(global_position) and not _transit_contains(global_position):
		_request("water")
		return
	var dt := clampf(delta,0.0,.1)
	if dt<=0.0: return
	var support := _support_near(global_position,.004,.048)
	_grounded = not support.is_empty() and absf(global_position.y-float(support.position.y))<.005 and velocity.y<=.001
	if support.is_empty() and _jump_time<=0.0:
		_request("unsupported")
		return
	if _grounded: _jump_time = 0.0
	var desired := Basis(Vector3.UP,camera_yaw)*Vector3(frame.move.x,0,frame.move.y).limit_length(1.0)
	var speed := .20 if frame.sprint else .09
	velocity.x = move_toward(velocity.x,desired.x*speed,.8*dt)
	velocity.z = move_toward(velocity.z,desired.z*speed,.8*dt)
	if frame.jump and _grounded:
		velocity.y = .20
		_jump_time = .85
		_grounded = false
	if _jump_time>0.0: _jump_time = maxf(0.0,_jump_time-dt)
	var before := global_position
	var horizontal := Vector3(velocity.x,0,velocity.z)*dt
	if _grounded and not frame.jump: _step_up(horizontal)
	velocity.y -= GRAVITY*dt
	# move_and_slide uses the physics delta. Scale only for a bounded explicit
	# stall delta; ordinary session calls use the unmodified physical velocity.
	var physics_dt := get_physics_process_delta_time()
	var scale := dt/physics_dt if physics_dt>0.0 else 1.0
	velocity *= scale
	move_and_slide()
	velocity /= scale
	_grounded = is_on_floor()
	if _grounded: _jump_time = 0.0
	if not global_position.is_finite():
		_request("nonfinite")
		return
	if not _inside(global_position):
		_request("bounds")
		return
	if _world.touches_water(global_position) and not _transit_contains(global_position):
		_request("water")
		return
	_update_support_frame()
	var actual := global_position-before
	var planar := Vector2(actual.x,actual.z).length()/dt
	if planar>.0001:
		# The model's yaw is local to the body, which may itself face a street or
		# a door after place(); aim it at the world motion minus the body's yaw.
		var heading := atan2(-actual.x,-actual.z)-global_rotation.y
		_visual.rotation.y = lerp_angle(_visual.rotation.y,heading,1.0-exp(-12.0*dt))
	_visual.set_motion(planar,0.0,not _grounded)
	_visual.advance_visual(dt)
