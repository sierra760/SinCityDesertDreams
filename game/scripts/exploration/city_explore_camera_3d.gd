# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Session-driven third-person camera. Target positions are at actor feet.
class_name CityExploreCamera3D
extends Node3D

signal recovery_requested

const FOLLOW_DISTANCE := [.35, .55, .95]
const FOLLOW_HEIGHT := [.10, .18, .30]
const FOLLOW_FOV := [65.0, 70.0, 75.0]
const CAMERA_RADIUS := .012
const MAX_PITCH := deg_to_rad(40.0)
const WORLD_MASK := 28

var cabin_active := false
var _cabin_bounds := AABB()
var _cabin_at := Transform3D.IDENTITY
var cabin_first_person := false
var interior_active := false
var camera: Camera3D
var yaw := 0.0
var pitch := 0.12
var _target: Node3D
var _mode := 0
var _since_orbit := 0.0
var _previous_target_position := Vector3.ZERO
var _has_position := false
var _recovery_notified := false
var _withheld := false
var _radial_blocked := false
var _arm_releasing := false
var _sphere := SphereShape3D.new()
var _chrome_top := 0.0
var _chrome_bottom := 0.0
# Target collision RIDs excluded from every camera query. They are collected
# when the target changes and again only after its subtree gains/loses nodes.
var _exclusions: Array[RID] = []
var _exclusions_dirty := true
var _query := PhysicsShapeQueryParameters3D.new()
var _endpoint_query := PhysicsShapeQueryParameters3D.new()

func _init() -> void:
	_sphere.radius = CAMERA_RADIUS
	for query: PhysicsShapeQueryParameters3D in [_query,_endpoint_query]:
		query.shape = _sphere
		query.collision_mask = WORLD_MASK
	camera = Camera3D.new()
	camera.name = "ExploreCamera"
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.near = .003
	camera.fov = FOLLOW_FOV[0]
	add_child(camera)

func _enter_tree() -> void:
	get_tree().node_added.connect(_on_tree_node_changed)
	get_tree().node_removed.connect(_on_tree_node_changed)
	_exclusions_dirty = true

func _exit_tree() -> void:
	get_tree().node_added.disconnect(_on_tree_node_changed)
	get_tree().node_removed.disconnect(_on_tree_node_changed)

func _on_tree_node_changed(node: Node) -> void:
	if not _exclusions_dirty and is_instance_valid(_target) and (node == _target or _target.is_ancestor_of(node)):
		_exclusions_dirty = true

func configure_target(target: Node3D, mode: int) -> void:
	if is_instance_valid(_target) and _target.has_method("set_camera_occluded"): _target.set_camera_occluded(false)
	_target = target
	_arm_releasing = false
	cabin_first_person = false
	_mode = clampi(mode, 0, 2)
	camera.fov = FOLLOW_FOV[_mode]
	if is_instance_valid(target):
		_previous_target_position = target.global_position
		if not _has_position:
			yaw = target.global_rotation.y
	_recovery_notified = false
	_exclusions_dirty = true
	# A withheld view stays withheld: update_follow makes this camera current
	# again once the new target has a clear camera point. Clearing the flag here
	# would leave the aerial camera current for the rest of the session.

## Insets are drawable pixels over the full 3D SubViewport, measured by Main.
## They affect only aim; the camera's swept position is unchanged.
func set_chrome_insets(top: float, bottom: float) -> void:
	_chrome_top = maxf(0.0, top) if is_finite(top) else 0.0
	_chrome_bottom = maxf(0.0, bottom) if is_finite(bottom) else 0.0
	if _has_position and is_instance_valid(_target):
		_frame_actor()

## relative_drawable is the physical event delta. UI backing scale is not used.
func orbit(relative_drawable: Vector2, sensitivity: float, invert_y: bool) -> void:
	if not relative_drawable.is_finite() or not is_finite(sensitivity):
		return
	var amount := clampf(sensitivity, .25, 3.0) * .003
	yaw = wrapf(yaw - relative_drawable.x * amount, -PI, PI)
	pitch = clampf(pitch + relative_drawable.y * amount * (-1.0 if invert_y else 1.0), -MAX_PITCH, MAX_PITCH)
	_since_orbit = 0.0

func recenter() -> void:
	if is_instance_valid(_target):
		yaw = _target.global_rotation.y
	pitch = 0.12
	_since_orbit = 0.0

func clear_target() -> void:
	if is_instance_valid(_target) and _target.has_method("set_camera_occluded"): _target.set_camera_occluded(false)
	_target = null
	_arm_releasing = false
	cabin_first_person = false
	cabin_active = false
	_cabin_bounds = AABB()
	interior_active = false
	_has_position = false
	_recovery_notified = false
	_exclusions_dirty = true

func update_follow(delta: float) -> void:
	if not is_instance_valid(_target) or not is_inside_tree():
		return
	var dt := clampf(delta, 0.0, .1)
	_since_orbit += dt
	var travel := _target.global_position.distance_to(_previous_target_position)
	_previous_target_position = _target.global_position
	if _mode != 0 and not interior_active and not cabin_active and _since_orbit > 1.0 and travel > .0001:
		yaw = lerp_angle(yaw, _target.global_rotation.y, 1.0 - exp(-2.5 * dt))
	if (interior_active and _mode!=2) or cabin_active:
		# Stations use an eye view deliberately. A long outside follow arm
		# otherwise alternates between opposite walls and squeezed body views.
		var eye: Vector3=_target.global_position+Vector3.UP*.105
		if cabin_active: eye=_cabin_eye(eye)
		if not _point_clear(eye): eye=_physical_focus()
		if cabin_active: eye=_cabin_eye(eye)
		if _point_clear(eye):
			camera.global_position=eye
			cabin_first_person=true
			if _target.has_method("set_camera_occluded"): _target.set_camera_occluded(true)
			if _withheld: camera.make_current(); _withheld=false
			_has_position=true
			_recovery_notified=false
			_frame_actor()
			return
		# An obstructed indoor eye must never fall through to the outdoor arm.
		if not _recovery_notified:
			_recovery_notified=true
			recovery_requested.emit()
		_withhold_view()
		return
	var focus: Vector3 = _physical_focus()
	var distance: float = .16 if cabin_active else maxf(FOLLOW_DISTANCE[_mode],_body_size().z*1.8)
	var direction: Vector3 = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	if focus.y < _target.global_position.y + float(FOLLOW_HEIGHT[_mode]) - .001:
		# The nominal high pivot was blocked. Keep the camera's stand-off under
		# that overhead surface instead of pitching its desired point into it.
		direction = Vector3(sin(yaw),minf(direction.y,-.03),cos(yaw)).normalized()
	var desired: Vector3 = focus + direction * distance
	var clear_position: Vector3 = _clear_endpoint(focus, desired)
	var old_valid := _has_position and _point_clear(camera.global_position)
	if not clear_position.is_finite() or not _point_clear(clear_position):
		if not _recovery_notified:
			_recovery_notified = true
			recovery_requested.emit()
		if not old_valid:
			_withhold_view()
		return
	if _withheld:
		camera.make_current()
		_withheld = false
	var old_visible := old_valid and _focus_reaches_old_camera(focus,camera.global_position)
	if _radial_blocked or (old_valid and not old_visible): _arm_releasing = true
	var proposed := clear_position
	if old_valid and travel <= distance and clear_position.distance_to(focus) >= camera.global_position.distance_to(focus):
		var alpha := 1.0 - exp(-8.0 * dt)
		if _arm_releasing:
			# Release length along the clear focus-side arm. Cartesian easing
			# lags behind a wall's edge; cutting to the full arm pops outward.
			var length := clear_position.distance_to(focus)
			var current_length := maxf(camera.global_position.distance_to(focus),CAMERA_RADIUS)
			# Ease relative length: a fixed fraction of the full arm changes
			# the aim sharply when starting centimetres from the avatar.
			var eased := exp(lerpf(log(current_length),log(maxf(length,CAMERA_RADIUS)),alpha))
			var radial := focus.lerp(clear_position,eased / maxf(length,.000001))
			# Cast the eased length itself: tangent contact precision can differ
			# from the longer endpoint cast. Clamp rather than pop to full arm.
			if _point_clear(focus):
				var release_query := _camera_query(focus)
				release_query.motion = radial-focus
				var release_cast := get_world_3d().direct_space_state.cast_motion(release_query)
				if release_cast.size()>0 and release_cast[0]==1.0 and _point_clear(radial):
					proposed = radial
				else:
					proposed = _sweep_camera_move(focus,radial)
		else:
			proposed = camera.global_position.lerp(clear_position, alpha)
	if travel > distance or (old_valid and not old_visible):
		# A blocked old sight line cuts to the new target side immediately,
		# keeping the eased stand-off for ordinary nearby movement.
		camera.global_position = proposed
	elif not old_valid:
		camera.global_position = clear_position
	else:
		camera.global_position = _sweep_camera_move(camera.global_position, proposed)
	if not _radial_blocked and camera.global_position.distance_to(clear_position) < .002:
		_arm_releasing = false
	# A side door can leave less than one body-length behind the passenger.
	# Keep the physical pedestrian/support visible to gameplay, but use an eye
	# view without its own mesh when third-person framing would fill the screen.
	if cabin_first_person and clear_position.distance_to(focus)>=.12: camera.global_position = clear_position
	cabin_first_person = cabin_active and clear_position.distance_to(focus)<.12
	if cabin_first_person and _point_clear(focus): camera.global_position = focus
	if _target.has_method("set_camera_occluded"): _target.set_camera_occluded(cabin_first_person)
	_has_position = true
	_frame_actor()

func _physical_focus() -> Vector3:
	var nominal: Vector3 = _target.global_position + Vector3.UP * float(FOLLOW_HEIGHT[_mode])
	var body_size: Vector3 = _body_size()
	# A pivot within the pedestrian body is used as is; recovery handles any
	# blockage there.
	if float(FOLLOW_HEIGHT[_mode]) <= body_size.y:
		return nominal
	var body_center := _target.global_position + Vector3.UP * (body_size.y * .5)
	if not _point_clear(body_center):
		return body_center
	# A point-clear nominal pivot may already be above a thin roof. The whole
	# actor-to-focus corridor must be sphere clear before the camera uses it.
	var rise := nominal - body_center
	var query := _camera_query(body_center)
	query.motion = rise
	var sweep := get_world_3d().direct_space_state.cast_motion(query)
	var fraction: float = sweep[0] if sweep.size() > 0 else 0.0
	if fraction >= .999 and _point_clear(nominal):
		return nominal
	var raised := body_center + rise * maxf(0.0, fraction - .005)
	return raised if _point_clear(raised) else body_center

func _frame_actor() -> void:
	if cabin_first_person:
		var direction := Vector3(-sin(yaw)*cos(pitch),-sin(pitch),-cos(yaw)*cos(pitch))
		camera.look_at(camera.global_position+direction,Vector3.UP)
		return
	var body_size: Vector3 = _body_size()
	var visual_target: Vector3 = _target.global_position + Vector3.UP * (body_size.y * .5)
	var offset := visual_target - camera.global_position
	if offset.length_squared() <= .000001:
		return
	if Vector2(offset.x,offset.z).length_squared() <= offset.length_squared() * .00000001:
		# A camera collapsed onto its pivot sits vertically over the body.
		# look_at cannot use UP there; aim along the orbit like the eye view.
		var direction := Vector3(-sin(yaw)*cos(pitch),-sin(pitch),-cos(yaw)*cos(pitch))
		camera.look_at(camera.global_position+direction,Vector3.UP)
		return
	camera.look_at(visual_target, Vector3.UP)
	var viewport_height := float(camera.get_viewport().get_visible_rect().size.y)
	var top := _chrome_top + 4.0
	var bottom := viewport_height - _chrome_bottom - 4.0
	if _chrome_top <= 0.0 and _chrome_bottom <= 0.0 or bottom <= top + 8.0:
		return
	var wanted_center := (top + bottom) * .5
	var wanted_y := (1.0 - 2.0 * wanted_center / viewport_height) / camera.get_camera_projection().y.y
	var elevations := Vector2(INF,-INF)
	var inverse := camera.global_basis.inverse()
	for x_sign in [-1.0,1.0]:
		for y_sign in [0.0,1.0]:
			for z_sign in [-1.0,1.0]:
				var corner := Vector3(body_size.x*.5*x_sign,body_size.y*y_sign,body_size.z*.5*z_sign)
				var local := inverse * (_target.global_position + _target.global_basis*corner - camera.global_position)
				var elevation := atan2(local.y,-local.z)
				elevations.x = minf(elevations.x,elevation)
				elevations.y = maxf(elevations.y,elevation)
	# Search pitch only where all box corners face the camera. Projecting a
	# corner through or behind the lens makes screen bounds discontinuous,
	# and a world-height search could flip the view beside a wall.
	var low := elevations.y - PI*.5 + .001
	var high := elevations.x + PI*.5 - .001
	var tilt := -atan(wanted_y)
	if low < high:
		for step in 14:
			var middle := (low + high)*.5
			var center_y := (tan(elevations.x-middle) + tan(elevations.y-middle))*.5
			if center_y > wanted_y:
				low = middle
			else:
				high = middle
		var vertical_fov := 2.0 * atan(1.0 / camera.get_camera_projection().y.y)
		var fit := 1.0 - smoothstep(vertical_fov*.75,vertical_fov,elevations.y-elevations.x)
		tilt = lerpf(tilt,(low + high)*.5,fit)
	# As the box outgrows the lens, smoothly return to its centre. A camera
	# inside the box cannot fit corners on opposite sides of the lens at all.
	camera.rotate_object_local(Vector3.RIGHT,tilt)

func _clear_endpoint(origin: Vector3, desired: Vector3) -> Vector3:
	_radial_blocked = false
	var space := get_world_3d().direct_space_state
	_refresh_exclusions()
	var query := _endpoint_query
	query.motion = Vector3.ZERO
	query.transform = Transform3D(Basis.IDENTITY, origin)
	if not space.intersect_shape(query, 1).is_empty():
		_radial_blocked = true
		# A target embedded in world geometry needs the controller's recovery.
		if not _recovery_notified:
			_recovery_notified = true
			recovery_requested.emit()
		return _nearest_free_point(origin, desired, query)
	var motion := desired - origin
	query.motion = motion
	var sweep := space.cast_motion(query)
	var fraction: float = sweep[0] if sweep.size() > 0 else 1.0
	_radial_blocked = fraction < .999
	var endpoint := origin + motion * maxf(0.0, fraction - .005)
	if fraction < .04:
		var fallback := _nearest_free_point(origin, desired, query)
		if fallback.is_finite() and fallback.distance_to(origin) > endpoint.distance_to(origin):
			endpoint = fallback
		elif not _recovery_notified:
			_recovery_notified = true
			recovery_requested.emit()
	else:
		_recovery_notified = false
	# A shape cast can stop just inside a moving door at collision precision.
	# Contract from the proven-clear focus with the same overlap-checked sweep
	# used for camera easing, instead of recovering the supported actor.
	if endpoint.is_finite() and not _point_clear(endpoint) and _point_clear(origin):
		endpoint = _sweep_camera_move(origin,endpoint)
	return endpoint

func _nearest_free_point(origin: Vector3, desired: Vector3, query: PhysicsShapeQueryParameters3D) -> Vector3:
	var space := get_world_3d().direct_space_state
	for offset in [Vector3.UP * .035, Vector3.FORWARD * .035, Vector3.BACK * .035,
		Vector3.LEFT * .035, Vector3.RIGHT * .035, Vector3.UP * .07]:
		query.transform = Transform3D(Basis.IDENTITY, origin + offset)
		if space.intersect_shape(query, 1).is_empty():
			query.motion = desired - (origin + offset)
			var sweep := space.cast_motion(query)
			var fraction: float = sweep[0] if sweep.size() > 0 else 1.0
			return origin + offset + (desired - origin - offset) * maxf(0.0, fraction - .005)
	return Vector3(INF, INF, INF)

func _sweep_camera_move(old_position: Vector3, proposed: Vector3) -> Vector3:
	var motion := proposed - old_position
	if motion.length_squared() < .00000001:
		return old_position
	var query := _camera_query(old_position)
	query.motion = motion
	var sweep := get_world_3d().direct_space_state.cast_motion(query)
	var fraction: float = sweep[0] if sweep.size() > 0 else 1.0
	var candidate := old_position + motion * maxf(0.0, fraction - .005)
	if _point_clear(candidate):
		return candidate
	# A cast beginning against a surface may report a fraction whose endpoint
	# overlaps at physics precision. Bound it with the same sphere overlap query.
	var low := 0.0
	var high := maxf(0.0, fraction - .005)
	for i in 12:
		var middle := (low + high) * .5
		if _point_clear(old_position + motion * middle):
			low = middle
		else:
			high = middle
	return old_position + motion * maxf(0.0, low - .001)

func _point_clear(position: Vector3) -> bool:
	if not position.is_finite():
		return false
	return get_world_3d().direct_space_state.intersect_shape(_camera_query(position), 1).is_empty()

func _focus_reaches_old_camera(focus: Vector3, old_position: Vector3) -> bool:
	var query := _camera_query(focus)
	query.motion = old_position - focus
	var sweep := get_world_3d().direct_space_state.cast_motion(query)
	return sweep.size() > 0 and sweep[0] >= .999

## Returns the shared query reset to a motionless sphere at position. Callers
## must finish with it (or copy its motion) before issuing another query.
func _camera_query(position: Vector3) -> PhysicsShapeQueryParameters3D:
	_refresh_exclusions()
	_query.transform = Transform3D(Basis.IDENTITY, position)
	_query.motion = Vector3.ZERO
	return _query

func _refresh_exclusions() -> void:
	if not _exclusions_dirty:
		return
	_exclusions_dirty = false
	_exclusions.clear()
	if is_instance_valid(_target):
		_collect_target_rids(_target, _exclusions)
	_query.exclude = _exclusions
	_endpoint_query.exclude = _exclusions

func _withhold_view() -> void:
	if not _withheld:
		_withheld = true
		camera.current = false

func _collect_target_rids(node: Node, output: Array[RID]) -> void:
	if node is CollisionObject3D:
		output.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		_collect_target_rids(child, output)

func _body_size() -> Vector3:
	if is_instance_valid(_target) and _target.has_method("vehicle_size"): return _target.vehicle_size()
	return ExploreActorProfile.geometry(_mode).size

func _cabin_eye(eye: Vector3) -> Vector3:
	var local: Vector3=_cabin_at.affine_inverse()*eye
	var safe := _cabin_bounds.grow(-CAMERA_RADIUS-.003)
	return _cabin_at*Vector3(clampf(local.x,safe.position.x,safe.end.x),clampf(local.y,safe.position.y,safe.end.y),clampf(local.z,safe.position.z,safe.end.z))

func set_cabin(bounds: AABB, at: Transform3D, active: bool) -> void:
	var valid := active and bounds.size.x>CAMERA_RADIUS*2+.006 and bounds.size.y>CAMERA_RADIUS*2+.006 and bounds.size.z>CAMERA_RADIUS*2+.006 and at.is_finite()
	if cabin_active and valid:
		# Carry the rider's heading with the carriage, keeping their local
		# mouse orbit. Keep the horizon upright on grades instead of rolling.
		var previous := atan2(_cabin_at.basis.z.x,_cabin_at.basis.z.z)
		var current := atan2(at.basis.z.x,at.basis.z.z)
		yaw=wrapf(yaw+wrapf(current-previous,-PI,PI),-PI,PI)
	if cabin_active!=valid:
		_has_position=false
		if not valid and not interior_active:
			cabin_first_person=false
			if is_instance_valid(_target) and _target.has_method("set_camera_occluded"): _target.set_camera_occluded(false)
	cabin_active=valid
	_cabin_bounds=bounds
	_cabin_at=at
	camera.fov=FOLLOW_FOV[0] if valid or interior_active else FOLLOW_FOV[_mode]

func set_interior(active: bool) -> void:
	if interior_active==active: return
	interior_active=active
	camera.fov=FOLLOW_FOV[0] if active or cabin_active else FOLLOW_FOV[_mode]
	_has_position=false
	if not active:
		cabin_first_person=false
		if is_instance_valid(_target) and _target.has_method("set_camera_occluded"): _target.set_camera_occluded(false)
