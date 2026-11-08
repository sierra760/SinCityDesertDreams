# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Hovering arcade flight using swept full-size clearance, owned by the session.
##
## Input moves the helicopter relative to the camera, like walking. Speed eases
## in and out instead of changing at a constant rate, the nose swings round to
## face forward travel (backing and sliding keep the nose where it is), the body
## leans into acceleration and turns, landings flare to a soft touchdown, and
## the rotor spools up on boarding and winds down after the pilot leaves. Lean
## and rotor are drawn only: the collision box stays upright.
class_name ExploreHelicopter
extends CharacterBody3D

signal recovery_requested(reason: String)
const VISUAL := preload("res://assets/desert-dreams-exploration/helicopter.tscn")
## Tiles a second.
const MAX_SPEED := 1.5
const MAX_CLIMB := .5
## Speed follows the stick: the gap closes at SPEED_GAIN a second, no faster
## than PUSH_ACCEL (or BRAKE_ACCEL when slowing), and acceleration itself
## settles over ACCEL_LAG seconds, so there are no sudden lurches.
const SPEED_GAIN := 3.0
const PUSH_ACCEL := 1.2
const BRAKE_ACCEL := 1.8
const CLIMB_GAIN := 4.0
const CLIMB_ACCEL := .9
const ACCEL_LAG := .08
## Below this speed with the stick released, the last drift is damped out.
const SETTLE_SPEED := .03
## The nose swings toward forward travel from WEATHERVANE_FROM tiles a second,
## fully by WEATHERVANE_FULL, at up to TURN_RATE radians a second.
const WEATHERVANE_FROM := .3
const WEATHERVANE_FULL := .9
const TURN_GAIN := 2.5
const TURN_RATE := 1.8
const TURN_ACCEL := 6.0
## Near the ground a descent flares: it slows at FLARE_DECEL tiles a second
## squared, as if braking to stop at the ground, but no slower than
## TOUCHDOWN_SPEED, so the skids meet the ground gently.
const FLARE_DECEL := .6
const TOUCHDOWN_SPEED := .06
## Drawn lean, radians: a steady tilt toward travel at full speed plus a tilt
## per tile a second squared of acceleration, fading out near the ground.
const DRAG_TILT := .12
const ACCEL_TILT := .14
const MAX_TILT := .3
const TILT_LAG := .1
const TILT_PIVOT := Vector3(0,.08,0)
const TILT_FADE_HEIGHT := .1
## Rotor speed (1 = flying) eases up over ROTOR_SPOOL_UP seconds while piloted
## and down over ROTOR_SPOOL_DOWN once no one is flying it.
const ROTOR_SPOOL_UP := .5
const ROTOR_SPOOL_DOWN := 1.0
## Below this share of full speed a winding-down rotor stops.
const ROTOR_REST := .02
var _world: CityTraversalWorld3D
var _visual: ExploreActorVisual
var _collider: CollisionShape3D
var _local_collision_bounds: AABB
var _grounded := false
var _reported := false
var _reported_pose := Vector3.ZERO
var _altitude := 0.0
var _accel := Vector3.ZERO
var _yaw_rate := 0.0
var _tilt := Vector2.ZERO
var _rotor := 0.0
var _stepped_frame := -1000

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
	_visual.rotor_rate = 0.0
	set_physics_process(false)
	set_process(false)

func bind(traversal: CityTraversalWorld3D) -> void:
	set_process(false)
	_world = traversal
	stop_input()

func speed() -> float: return velocity.length()
func altitude() -> float: return _altitude
func feet_position() -> Vector3: return global_position
func landed() -> bool: return _grounded

func stop_input() -> void:
	velocity = Vector3.ZERO
	_accel = Vector3.ZERO
	_yaw_rate = 0.0
	_reported = false

## Once no one is flying it, the rotor winds down on its own.
func _process(delta: float) -> void:
	if Engine.get_physics_frames()-_stepped_frame <= 2 or _rotor <= 0.0 or not is_finite(delta): return
	var dt := clampf(delta,0,.1)
	_rotor = _rotor*exp(-dt/ROTOR_SPOOL_DOWN)
	if _rotor < ROTOR_REST: _rotor = 0.0
	_visual.rotor_rate = _rotor
	_visual.advance_visual(dt)
	if _rotor <= 0.0: set_process(false)

func _request(reason: String) -> void:
	velocity = Vector3.ZERO
	_accel = Vector3.ZERO
	_yaw_rate = 0.0
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
	_stepped_frame = Engine.get_physics_frames()
	set_process(true)
	var input := frame.move.limit_length(1)
	var camera := Basis(Vector3.UP,camera_yaw)
	var desired := camera*Vector3(input.x,0,input.y)*MAX_SPEED
	var climb := clampf(frame.vertical,-1,1)*MAX_CLIMB
	var flare := 0.0
	if climb<0 and not _grounded:
		var braking := sqrt(2.0*FLARE_DECEL*maxf(_altitude,0.0))
		if braking < -climb:
			climb = -maxf(TOUCHDOWN_SPEED,braking)
			# The flare's own deceleration is fed forward so the descent
			# follows it instead of lagging into a hard touchdown.
			if braking > TOUCHDOWN_SPEED: flare = FLARE_DECEL
	desired.y = climb
	var before := velocity
	_fly_toward(desired,input.is_zero_approx(),is_zero_approx(frame.vertical),dt,flare)
	if _grounded and velocity.y<0: velocity.y = 0
	if velocity.y>.001: _grounded = false
	var horizontal := Vector3(velocity.x,0,velocity.z)
	_turn(horizontal,camera,dt)
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
	if _grounded:
		# A soft touchdown is detected just before contact: settle onto the skids.
		move_and_collide(Vector3.DOWN*.006,false,.001,true)
		if velocity.y<0: velocity.y = 0
		# The ground took the descent; none of it may linger into the next takeoff.
		if _accel.y<0: _accel.y = 0
	var below := _support(32.0)
	_altitude = 0.0 if _grounded else (maxf(0.0,global_position.y-float(below.position.y)) if not below.is_empty() else maxf(0.0,global_position.y))
	if not global_position.is_finite(): _request("nonfinite")
	elif not _inside(): _request("bounds")
	elif _world.touches_water(global_position): _request("water")
	_lean((velocity-before)/dt,dt)
	_rotor = 1.0-(1.0-_rotor)*exp(-dt/ROTOR_SPOOL_UP)
	_visual.rotor_rate = _rotor
	_visual.set_motion(horizontal.length(),0.0,not _grounded)
	_visual.advance_visual(dt)

## Ease velocity toward the stick: a capped gap-closing acceleration that
## itself settles over ACCEL_LAG, separately across and up.
func _fly_toward(desired: Vector3, released: bool, level: bool, dt: float, lift: float = 0.0) -> void:
	var gap := Vector3(desired.x-velocity.x,0,desired.z-velocity.z)
	var slowing := gap.dot(Vector3(velocity.x,0,velocity.z))<0.0 or released
	var across := (gap*SPEED_GAIN).limit_length(BRAKE_ACCEL if slowing else PUSH_ACCEL)
	var up := clampf((desired.y-velocity.y)*CLIMB_GAIN+lift,-CLIMB_ACCEL,CLIMB_ACCEL)
	var wanted := Vector3(across.x,up,across.z)
	_accel += (wanted-_accel)*(1.0-exp(-dt/ACCEL_LAG))
	velocity += _accel*dt
	var flat := Vector3(velocity.x,0,velocity.z)
	if flat.length()>MAX_SPEED: flat = flat.limit_length(MAX_SPEED)
	if released and flat.length()<SETTLE_SPEED: flat *= exp(-12.0*dt)
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = clampf(velocity.y,-MAX_CLIMB,MAX_CLIMB)
	if level and absf(velocity.y)<SETTLE_SPEED: velocity.y *= exp(-12.0*dt)

## Swing the nose toward forward travel at a limited, smoothly changing turn
## rate. Moving back toward the camera keeps the nose facing away from it. The
## turn waits whenever the full box would not fit at the new heading.
func _turn(horizontal: Vector3, camera: Basis, dt: float) -> void:
	var speed_now := horizontal.length()
	var want := 0.0
	if speed_now>WEATHERVANE_FROM:
		var camera_forward := -camera.z
		var wanted := atan2(-horizontal.x,-horizontal.z)
		if horizontal.dot(camera_forward)<-.35*speed_now: wanted = atan2(-camera_forward.x,-camera_forward.z)
		var weight := smoothstep(WEATHERVANE_FROM,WEATHERVANE_FULL,speed_now)
		want = clampf(angle_difference(rotation.y,wanted)*TURN_GAIN*weight,-TURN_RATE,TURN_RATE)
	_yaw_rate = move_toward(_yaw_rate,want,TURN_ACCEL*dt)
	if absf(_yaw_rate)<.0001: return
	var old := rotation.y
	rotation.y = wrapf(rotation.y+_yaw_rate*dt,-PI,PI)
	if test_move(global_transform,Vector3.ZERO) or not _inside():
		rotation.y = old
		_yaw_rate = 0.0

## Lean the drawn body toward travel and acceleration, measured along the
## nose and across it, fading to level on and near the ground.
func _lean(acceleration: Vector3, dt: float) -> void:
	var forward := -global_basis.z
	forward = Vector3(forward.x,0,forward.z).normalized()
	var right := Vector3(-forward.z,0,forward.x)
	var flat := Vector3(velocity.x,0,velocity.z)
	var pitch := DRAG_TILT*flat.dot(forward)/MAX_SPEED+ACCEL_TILT*acceleration.dot(forward)
	var bank := -(DRAG_TILT*flat.dot(right)/MAX_SPEED+ACCEL_TILT*acceleration.dot(right))
	var fade := 0.0 if _grounded else clampf(_altitude/TILT_FADE_HEIGHT,0.0,1.0)
	var target := Vector2(clampf(pitch,-MAX_TILT,MAX_TILT),clampf(bank,-MAX_TILT,MAX_TILT))*fade
	if not target.is_finite(): target = Vector2.ZERO
	_tilt = _tilt.lerp(target,1.0-exp(-dt/TILT_LAG))
	# Nose down is a negative turn about the body's right axis.
	var basis := Basis(Vector3.RIGHT,-_tilt.x)*Basis(Vector3.BACK,_tilt.y)
	_visual.transform = Transform3D(basis,TILT_PIVOT-basis*TILT_PIVOT)
