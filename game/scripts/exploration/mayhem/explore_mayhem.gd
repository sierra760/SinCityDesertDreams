# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Cartoon slapstick for the Explore walker. The player carries one of three
## toy weapons (ExploreWeapons). A struck ambient pedestrian pops apart into
## six pieces (ExploreLimbKit) that bounce, lie about and twitch, then after
## about fifteen seconds hop back together with a boing and walk on from the
## same spot. The same goes for visitors on the casino floor the walker is
## in (`indoor`). Nobody is hurt and nothing is saved: a knocked pedestrian
## is only held out of its crowd while its pieces are loose (knock_pedestrian
## / restore_pedestrian on CityTraffic3D or the hall's patron crowd), and
## leaving Explore puts everyone back at once. City simulation, traffic routes and the RNG are untouched;
## this node keeps its own random stream for the pieces.
##
## Every clock here advances only through step(), which the Explore session
## calls on active physics ticks, so pausing Explore pauses the mayhem too.
class_name ExploreMayhem
extends Node3D

## Seconds a pedestrian stays in pieces, plus up to SPREAD more ("or so").
const REASSEMBLE_AFTER := 15.0
const REASSEMBLE_SPREAD := 2.0
## How long the pieces take to fly home, then the springy settle.
const ASSEMBLE_SECONDS := 1.1
const BOING_SECONDS := .35
## Pedestrians in pieces at once; striking more reassembles the oldest early.
const MAX_KNOCKED := 10
const GRAVITY := .613
const BOUNCE := .38
## Height of a pedestrian's middle above its feet, for aiming and hits.
const BODY_MIDDLE := .055
const BODY_HEIGHT := .11
## Pieces fade from view this far away (tiles), like other close detail.
const PIECE_RANGE := 4.0
## A pie or piece this far (tiles) below where it started has found no
## surface; it stops there. Relative, because casino halls lie below ground.
const FALL_LIMIT := 1.0
## A vehicle pops people it runs into at this speed or faster (tiles per
## second, about 9 km/h); slower, they just block it like any other body.
const VEHICLE_HIT_SPEED := .15
## Look this many ticks of travel ahead, plus a small margin (tiles), so a
## pedestrian pops before the vehicle touches their body.
const VEHICLE_LOOKAHEAD := 1.6
const VEHICLE_MARGIN := .006

var traffic: CityTraffic3D
## The patron crowd of the casino floor the walker is on, or null outdoors.
## It answers the same calls as `traffic` (pedestrian_targets,
## knock_pedestrian, is_knocked, knocked_pose, restore_pedestrian).
var indoor: Node3D
var walker: ExplorePedestrian
var weapon: int = ExploreWeapons.Kind.NONE
var _holder: Node3D
var _holder_kind := -1
var _rig: Dictionary = {}
var _rig_model: Node3D
var _vehicle: CharacterBody3D
var _vehicle_previous := Vector3.INF
var _vehicle_velocity := Vector3.ZERO
var _swing := -1.0
var _struck := false
var _cooldown := 0.0
var _aim_yaw := 0.0
var _pies: Array[Dictionary] = []
var _knocked: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
## The host's sound player; without one the slapstick is silent.
var audio: GameAudio
var _hits := 0

func _init() -> void:
	name = "ExploreMayhem"
	_rng.seed = 2000

func bind(crowd: CityTraffic3D, actor: ExplorePedestrian) -> void:
	traffic = crowd
	walker = actor

## Switch to the next weapon in ExploreWeapons.ORDER and return its name.
func cycle_weapon() -> String:
	set_weapon(ExploreWeapons.next(weapon))
	return ExploreWeapons.display_name(weapon)

func set_weapon(kind: int) -> void:
	weapon = kind if kind in ExploreWeapons.ORDER else ExploreWeapons.Kind.NONE
	_swing = -1.0
	_cooldown = 0.0
	_sync_holder(true)

## Start a swing toward the camera's heading. False with no weapon in hand,
## while the last swing is still recovering or when the walker cannot act.
func attack(camera_yaw: float) -> bool:
	if weapon == ExploreWeapons.Kind.NONE or _swing >= 0.0 or _cooldown > 0.0: return false
	if not _walker_ready() or not is_finite(camera_yaw): return false
	_aim_yaw = camera_yaw
	_swing = 0.0
	_struck = false
	walker.face_world_yaw(camera_yaw)
	_play(&"whoosh",-8.0,_rng.randf_range(.9,1.15))
	return true

## Advance swings, pies and loose pieces. `walking` is false while the
## player drives or flies; the weapon is put out of sight then.
func step(delta: float, walking: bool) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	var dt := minf(delta,.1)
	_sync_holder(walking)
	if walking and _walker_ready(): _advance_swing(dt)
	elif _swing >= 0.0: _swing = -1.0
	_sync_holder(walking)
	if walking and _walker_ready(): _pose_holder()
	_cooldown = maxf(0.0,_cooldown-dt)
	_advance_pies(dt)
	_advance_knocked(dt)

## Pop the ambient pedestrians the player's moving vehicle is about to run
## into. Call before Explore places traffic bodies for this tick: a struck
## pedestrian then has no body, and the vehicle carries straight on. Speed
## comes from the vehicle's own movement over the last tick.
func vehicle_hits(vehicle: CharacterBody3D, delta: float) -> int:
	if not is_instance_valid(vehicle) or vehicle == walker or not vehicle.is_inside_tree() or not is_instance_valid(traffic):
		_vehicle = null
		return 0
	if not is_finite(delta) or delta <= 0.0: return 0
	var at := vehicle.global_position
	if vehicle != _vehicle or not _vehicle_previous.is_finite():
		_vehicle = vehicle
		_vehicle_previous = at
		_vehicle_velocity = Vector3.ZERO
		return 0
	var moved := (at-_vehicle_previous)/minf(delta,.1)
	_vehicle_previous = at
	# A recovery teleport or a fresh placement is not driving.
	_vehicle_velocity = moved if moved.length() < 6.0 else Vector3.ZERO
	var speed := _vehicle_velocity.length()
	if speed < VEHICLE_HIT_SPEED: return 0
	var body := _vehicle_box(vehicle)
	if body.is_empty(): return 0
	var pose: Transform3D = body.pose
	var half: Vector3 = body.half+Vector3.ONE*VEHICLE_MARGIN
	var ahead := _vehicle_velocity*minf(delta,.1)*VEHICLE_LOOKAHEAD
	var poses: Array[Transform3D] = [pose,pose.translated(ahead*.5),pose.translated(ahead)]
	var person := CityTraffic3D.body_bounds(&"pedestrian")
	var person_offset := Transform3D(Basis.IDENTITY,person.get_center())
	var direction := _vehicle_velocity.normalized()
	var spec := {"launch":clampf(speed*.35,.25,.7),"lift":clampf(.25+speed*.2,.3,.55)}
	var hits := 0
	for target: Dictionary in traffic.pedestrian_targets(pose.origin+ahead*.5,half.length()+ahead.length()+.05):
		var person_pose: Transform3D = (target.pose as Transform3D)*person_offset
		var touched := false
		for probe: Transform3D in poses:
			if CityTraffic3D.boxes_overlap(probe,half,person_pose,person.size*.5):
				touched = true
				break
		if not touched: continue
		var push := direction
		push.y = 0.0
		if _knock(target,push.normalized() if push.length_squared() > 0.0 else Vector3.FORWARD,spec): hits += 1
	if hits > 0: _play(&"bonk",-2.0,_rng.randf_range(.8,.95))
	return hits

## A vehicle's collision box in world space: {"pose" (box centre), "half"}.
func _vehicle_box(vehicle: CharacterBody3D) -> Dictionary:
	for child: Node in vehicle.get_children():
		var collider := child as CollisionShape3D
		if collider == null or collider.disabled or collider.shape == null: continue
		var bounds: AABB = collider.shape.get_debug_mesh().get_aabb()
		return {"pose":collider.global_transform*Transform3D(Basis.IDENTITY,bounds.get_center()),"half":bounds.size*.5}
	return {}

## Put every pedestrian back together immediately and drop held props.
func clear() -> void:
	for entry: Dictionary in _knocked: _finish(entry)
	_knocked.clear()
	for pie: Dictionary in _pies:
		if is_instance_valid(pie.node): pie.node.free()
	_pies.clear()
	if is_instance_valid(_holder): _holder.free()
	_holder = null
	_holder_kind = -1
	_swing = -1.0
	_cooldown = 0.0
	_vehicle = null
	indoor = null

func knocked_count() -> int:
	return _knocked.size()

func debug_state() -> Dictionary:
	var knocked: Array[Dictionary] = []
	for entry: Dictionary in _knocked:
		knocked.append({"id":entry.id,"age":entry.age,"reassemble_at":entry.reassemble_at,"assembling":entry.assembling,"pieces":entry.pieces.size()})
	return {"weapon":weapon,"swinging":_swing >= 0.0,"cooldown":_cooldown,"pies":_pies.size(),"knocked":knocked,"hits":_hits,"holder_visible":is_instance_valid(_holder) and _holder.is_visible_in_tree()}

func _walker_ready() -> bool:
	return is_instance_valid(walker) and walker.is_inside_tree() and walker.visible

# ── Held weapon ───────────────────────────────────────────────────────────

func _sync_holder(walking: bool) -> void:
	var model := walker.visual_node() if is_instance_valid(walker) else null
	if weapon == ExploreWeapons.Kind.NONE or model == null:
		if is_instance_valid(_holder): _holder.free()
		_holder = null
		_holder_kind = -1
		return
	# A new character replaces the walker's model; the grip moves with it.
	if not is_instance_valid(_holder) or _holder_kind != weapon or _holder.get_parent() != model:
		if is_instance_valid(_holder): _holder.free()
		_holder = Node3D.new()
		_holder.name = "HeldWeapon"
		_holder.add_child(ExploreWeapons.make_model(weapon))
		model.add_child(_holder)
		_holder_kind = weapon
	# The pie leaves the hand when thrown and a fresh one appears after.
	var empty_handed := weapon == ExploreWeapons.Kind.PIE and (_cooldown > .2 or (_swing >= 0.0 and _struck))
	_holder.visible = walking and not empty_handed

## Pose the right arm (on a rigged model) and put the weapon in its hand.
## Runs after the walker's own animation each tick, so the arm holds the
## weapon while the rest of the body keeps walking.
func _pose_holder() -> void:
	# The arm keeps its pose while the hand is empty, as after a pie leaves it.
	if not is_instance_valid(_holder): return
	var model := _holder.get_parent() as Node3D
	var spec: Dictionary = ExploreWeapons.SPECS[weapon]
	var pose := ExploreWeapons.arm_pose(weapon,_swing/float(spec.swing) if _swing >= 0.0 else -1.0)
	var rig := _rig_for(model)
	var hand := _rig_hand(rig,pose) if not rig.is_empty() else _crowd_hand(model,pose)
	if not _holder.visible: return
	var held := hand*Transform3D(Basis(Vector3.RIGHT,pose.w),Vector3.ZERO)*ExploreWeapons.grip(weapon)
	if weapon == ExploreWeapons.Kind.PIE:
		# A pie stays level, whatever the hand does, until it is thrown.
		held.basis = Basis.IDENTITY
		held.origin += Vector3.UP*.0015
	_holder.transform = held

## The rig of a model with a RightHand bone chain, cached per model.
func _rig_for(model: Node3D) -> Dictionary:
	if model == _rig_model and (_rig.is_empty() or is_instance_valid(_rig.get("skeleton"))): return _rig
	_rig_model = model
	_rig = {}
	var skeletons := model.find_children("*","Skeleton3D",true,false)
	if skeletons.is_empty(): return _rig
	var skeleton := skeletons[0] as Skeleton3D
	var upper := skeleton.find_bone("RightUpperArm")
	var forearm := skeleton.find_bone("RightForearm")
	var hand := skeleton.find_bone("RightHand")
	if upper < 0 or forearm < 0 or hand < 0 or skeleton.get_bone_parent(forearm) != upper or skeleton.get_bone_parent(hand) != forearm: return _rig
	_rig = {"skeleton":skeleton,"upper":upper,"forearm":forearm,"hand":hand,"parent":skeleton.get_bone_parent(upper),
		"rest_upper":skeleton.get_bone_global_rest(upper).basis.orthonormalized(),
		"rest_forearm":skeleton.get_bone_global_rest(forearm).basis.orthonormalized(),
		"hand_rest":skeleton.get_bone_rest(hand).basis.get_rotation_quaternion(),
		"to_model":_relative(model,skeleton)}
	return _rig

## Bend the rig's right arm into `pose` and return its hand in model space,
## with an orthonormal basis (+X right, +Y fingers, +Z thumb).
func _rig_hand(rig: Dictionary, pose: Vector4) -> Transform3D:
	var skeleton: Skeleton3D = rig.skeleton
	var upper: int = rig.upper
	var forearm: int = rig.forearm
	var hand: int = rig.hand
	var shoulder := Basis(Vector3.UP,pose.y)*Basis(Vector3.RIGHT,pose.x)
	var upper_basis: Basis = shoulder*(rig.rest_upper as Basis)
	var elbow := Basis(upper_basis.x.normalized(),pose.z)
	var forearm_basis: Basis = elbow*shoulder*(rig.rest_forearm as Basis)
	var parent_pose := skeleton.get_bone_global_pose(int(rig.parent)) if int(rig.parent) >= 0 else Transform3D.IDENTITY
	var upper_local := (parent_pose.basis.orthonormalized().inverse()*upper_basis).orthonormalized()
	skeleton.set_bone_pose_rotation(upper,upper_local.get_rotation_quaternion())
	var upper_pose := parent_pose*Transform3D(upper_local,skeleton.get_bone_pose_position(upper))
	var forearm_local := (upper_pose.basis.orthonormalized().inverse()*forearm_basis).orthonormalized()
	skeleton.set_bone_pose_rotation(forearm,forearm_local.get_rotation_quaternion())
	skeleton.set_bone_pose_rotation(hand,rig.hand_rest)
	var in_model: Transform3D = (rig.to_model as Transform3D)*skeleton.get_bone_global_pose(hand)
	return Transform3D(in_model.basis.orthonormalized(),in_model.origin)

## A single crowd mesh has no arm to bend. The weapon stays at its right
## hand, swaying with the same stride its gait shader draws, and the swing
## turns the weapon about that hand.
func _crowd_hand(model: Node3D, pose: Vector4) -> Transform3D:
	var crowd := (model as ExploreActorVisual).crowd_mesh() if model is ExploreActorVisual else null
	var at := Vector3(.0135,.056,0)
	if crowd != null and crowd.mesh != null:
		var bounds := crowd.transform*crowd.mesh.get_aabb()
		at = Vector3(bounds.end.x*.86,bounds.position.y+bounds.size.y*.54,0)
	if model is ExploreActorVisual:
		var gait := (model as ExploreActorVisual).gait_sample()
		at.z -= .0036*sin(gait.x*TAU)*gait.y
	# The arm hangs (fingers down, thumb forward); the whole arm motion becomes
	# a turn of the hand.
	var turn := Basis(Vector3.UP,pose.y)*Basis(Vector3.RIGHT,pose.x+pose.z)
	return Transform3D(turn*Basis(Vector3.RIGHT,PI),at)

func _advance_swing(dt: float) -> void:
	if _swing < 0.0: return
	var spec: Dictionary = ExploreWeapons.SPECS[weapon]
	_swing += dt
	# The body keeps facing the aim through the swing, even while walking.
	walker.face_world_yaw(_aim_yaw)
	if not _struck and _swing >= float(spec.strike):
		_struck = true
		_strike(spec)
	if _swing >= float(spec.swing):
		_swing = -1.0
		_cooldown = maxf(0.0,float(spec.cooldown)-float(spec.swing))

func _forward() -> Vector3:
	return Basis(Vector3.UP,_aim_yaw)*Vector3.FORWARD

func _strike(spec: Dictionary) -> void:
	var feet := walker.feet_position()
	var forward := _forward()
	if weapon == ExploreWeapons.Kind.PIE:
		var start: Vector3 = _holder.global_position+Vector3.UP*.003 if is_instance_valid(_holder) else feet+Vector3.UP*.07
		var pie := ExploreWeapons.make_pie()
		add_child(pie)
		pie.global_position = start
		_pies.append({"node":pie,"position":start,"velocity":forward*ExploreWeapons.PIE_SPEED+Vector3.UP*ExploreWeapons.PIE_LIFT,"age":0.0,"spin":_rng.randf_range(-6.0,6.0),"lowest":start.y-FALL_LIMIT})
		return
	var center := feet+forward*(.05 if weapon == ExploreWeapons.Kind.MALLET else 0.0)
	var reach := float(spec.reach)
	var hits := 0
	for target: Dictionary in _targets(center,reach+.03):
		if hits >= int(spec.targets): break
		var pose: Transform3D = target.pose
		var offset := pose.origin-center
		if absf(offset.y) > BODY_HEIGHT: continue
		var flat := Vector2(offset.x,offset.z)
		if flat.length() > reach: continue
		var arc := float(spec.arc)
		if arc > -1.0 and flat.length() > .02 and flat.normalized().dot(Vector2(forward.x,forward.z)) < arc: continue
		var push := Vector3(offset.x,0,offset.z).normalized() if flat.length() > .001 else forward
		if weapon == ExploreWeapons.Kind.CHICKEN: push = (push+forward).normalized()
		if _knock(target,push,spec): hits += 1
	if hits > 0: _play(StringName(spec.cue),-2.0,_rng.randf_range(.92,1.1))
	if weapon == ExploreWeapons.Kind.MALLET:
		# The mallet thumps the pavement whether or not anyone was close.
		_play(&"bonk",-3.0 if hits > 0 else -6.0,_rng.randf_range(.9,1.05))

# ── Pies in flight ────────────────────────────────────────────────────────

func _advance_pies(dt: float) -> void:
	for index: int in range(_pies.size()-1,-1,-1):
		var pie: Dictionary = _pies[index]
		pie.age += dt
		var from: Vector3 = pie.position
		pie.velocity += Vector3.DOWN*GRAVITY*dt
		var to: Vector3 = from+pie.velocity*dt
		var landed := false
		var target := _pie_target(from,to)
		if not target.is_empty():
			var away := Vector3(pie.velocity.x,0,pie.velocity.z)
			_knock(target,away.normalized() if away.length_squared() > 0.0 else _forward(),ExploreWeapons.SPECS[ExploreWeapons.Kind.PIE])
			_play(&"splat",-1.0,_rng.randf_range(.9,1.1))
			_play(&"pop",-4.0,_rng.randf_range(.95,1.15))
			landed = true
		elif not _ray(from,to).is_empty():
			_play(&"splat",-6.0,_rng.randf_range(.85,1.0))
			landed = true
		pie.position = to
		if landed or pie.age > ExploreWeapons.PIE_LIFETIME or to.y < float(pie.lowest):
			if is_instance_valid(pie.node): pie.node.free()
			_pies.remove_at(index)
			continue
		var node: Node3D = pie.node
		node.global_position = to
		node.rotate_y(float(pie.spin)*dt)

## The first pedestrian whose body the segment passes within PIE_RADIUS of.
func _pie_target(from: Vector3, to: Vector3) -> Dictionary:
	var middle := (from+to)*.5
	for target: Dictionary in _targets(middle,from.distance_to(to)+ExploreWeapons.PIE_RADIUS+.02):
		var feet: Vector3 = (target.pose as Transform3D).origin
		var axis_from := Vector2(from.x-feet.x,from.z-feet.z)
		var axis_to := Vector2(to.x-feet.x,to.z-feet.z)
		var segment := axis_to-axis_from
		var along := clampf(-axis_from.dot(segment)/maxf(segment.length_squared(),.0000001),0.0,1.0)
		var closest := axis_from+segment*along
		var height := lerpf(from.y,to.y,along)-feet.y
		if closest.length() <= ExploreWeapons.PIE_RADIUS and height >= -.005 and height <= BODY_HEIGHT+.01: return target
	return {}

# ── Pedestrians in pieces ─────────────────────────────────────────────────

## Street pedestrians and, on a casino floor, its visitors near `center`.
## Each target records the crowd it came from as "source".
func _targets(center: Vector3, radius: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for source: Node in [traffic,indoor]:
		if not is_instance_valid(source): continue
		for target: Dictionary in source.call("pedestrian_targets",center,radius):
			target.source = source
			found.append(target)
	return found

func _knock(target: Dictionary, push: Vector3, spec: Dictionary) -> bool:
	var id := int(target.id)
	var source: Node = target.get("source",traffic)
	if not is_instance_valid(source) or not bool(source.call("knock_pedestrian",id)): return false
	if _knocked.size() >= MAX_KNOCKED:
		_finish(_knocked[0])
		_knocked.remove_at(0)
	var pose: Transform3D = target.pose
	var kit := ExploreLimbKit.pieces(int(target.variant))
	var pieces: Array[Dictionary] = []
	for entry: Dictionary in kit:
		var node := MeshInstance3D.new()
		node.mesh = entry.mesh
		node.visibility_range_end = PIECE_RANGE
		# Pieces of a casino visitor are lit like the hall they lie in.
		if source != traffic: node.layers = ResortInteriorWorld3D.LAYER
		add_child(node)
		var rest: Transform3D = entry.rest
		var xf := pose*rest
		node.global_transform = xf
		var outward := (xf.origin-(pose.origin+Vector3.UP*BODY_MIDDLE))
		outward.y = 0.0
		outward = outward.normalized() if outward.length_squared() > .0000001 else Vector3(_rng.randf_range(-1,1),0,_rng.randf_range(-1,1)).normalized()
		var velocity := push*float(spec.launch)*_rng.randf_range(.7,1.2)+outward*_rng.randf_range(.12,.3)+Vector3.UP*float(spec.lift)*_rng.randf_range(.65,1.25)
		var half: Vector3 = entry.half
		pieces.append({"node":node,"rest":rest,"half":half,"position":xf.origin,"rotation":xf.basis.get_rotation_quaternion(),
			"velocity":velocity,"spin":Vector3(_rng.randf_range(-1,1),_rng.randf_range(-1,1),_rng.randf_range(-1,1)).normalized()*_rng.randf_range(7.0,16.0),
			"resting":false,"twitch":_rng.randf_range(2.5,7.0),"lowest":xf.origin.y-FALL_LIMIT})
	if pieces.is_empty():
		source.call("restore_pedestrian",id)
		return false
	_knocked.append({"id":id,"source":source,"pose":pose,"pieces":pieces,"age":0.0,"reassemble_at":REASSEMBLE_AFTER+_rng.randf_range(0.0,REASSEMBLE_SPREAD),
		"assembling":false,"assemble_time":0.0})
	_hits += 1
	_play(&"pop",-2.0,_rng.randf_range(.9,1.2))
	return true

func _advance_knocked(dt: float) -> void:
	for index: int in range(_knocked.size()-1,-1,-1):
		var entry: Dictionary = _knocked[index]
		# A rebuilt crowd (a new city, edited roads, a closed hall) may already
		# have dropped or released this pedestrian; its pieces are only
		# presentation.
		var source: Node = entry.source
		if not is_instance_valid(source) or not bool(source.call("is_knocked",int(entry.id))):
			_free_pieces(entry)
			_knocked.remove_at(index)
			continue
		# A casino visitor is put back at once when the walker leaves its hall.
		if source != traffic and not (source as Node3D).is_visible_in_tree():
			_finish(entry)
			_knocked.remove_at(index)
			continue
		entry.age += dt
		if not entry.assembling and entry.age >= float(entry.reassemble_at): _begin_assembly(entry)
		if entry.assembling:
			if _advance_assembly(entry,dt):
				_finish(entry)
				_knocked.remove_at(index)
			continue
		for piece: Dictionary in entry.pieces: _advance_piece(piece,dt)

func _advance_piece(piece: Dictionary, dt: float) -> void:
	if piece.resting:
		piece.twitch -= dt
		if piece.twitch > 0.0: return
		# Lying limbs wriggle now and then.
		piece.twitch = _rng.randf_range(3.0,8.0)
		piece.velocity = Vector3(_rng.randf_range(-.04,.04),_rng.randf_range(.08,.14),_rng.randf_range(-.04,.04))
		piece.spin = Vector3(_rng.randf_range(-1,1),_rng.randf_range(-1,1),_rng.randf_range(-1,1)).normalized()*_rng.randf_range(4.0,9.0)
		piece.resting = false
	var from: Vector3 = piece.position
	piece.velocity += Vector3.DOWN*GRAVITY*dt
	var to: Vector3 = from+piece.velocity*dt
	var settle := minf(float((piece.half as Vector3).x),minf(float((piece.half as Vector3).y),float((piece.half as Vector3).z)))
	var hit := _ray(from+Vector3.UP*settle,to+Vector3.DOWN*settle)
	if not hit.is_empty():
		var normal: Vector3 = hit.normal
		to = Vector3(hit.position)+normal*settle
		var velocity: Vector3 = piece.velocity
		velocity = velocity.bounce(normal)*BOUNCE
		velocity.x *= .7
		velocity.z *= .7
		piece.velocity = velocity
		piece.spin = (piece.spin as Vector3)*.55
		if velocity.length() < .05 and normal.y > .55:
			piece.velocity = Vector3.ZERO
			piece.spin = Vector3.ZERO
			piece.resting = true
	elif to.y < float(piece.lowest):
		to = from
		piece.velocity = Vector3.ZERO
		piece.resting = true
	piece.position = to
	var spin: Vector3 = piece.spin
	var rotation: Quaternion = piece.rotation
	if spin.length_squared() > 0.0:
		rotation = (Quaternion(spin.normalized(),spin.length()*dt)*rotation).normalized()
		piece.rotation = rotation
	(piece.node as Node3D).global_transform = Transform3D(Basis(rotation),to)

func _target_pose(entry: Dictionary) -> Transform3D:
	var source: Node = entry.source
	var current: Transform3D = source.call("knocked_pose",int(entry.id)) if is_instance_valid(source) else Transform3D(Basis.IDENTITY,Vector3.INF)
	return current if current.is_finite() else entry.pose

func _begin_assembly(entry: Dictionary) -> void:
	entry.assembling = true
	entry.assemble_time = 0.0
	entry.pose = _target_pose(entry)
	for piece: Dictionary in entry.pieces:
		piece.start = Transform3D(Basis(piece.rotation as Quaternion),piece.position)
	_play(&"boing",-3.0,_rng.randf_range(.95,1.08))

## True once the pieces are home and the springy settle has finished.
func _advance_assembly(entry: Dictionary, dt: float) -> bool:
	entry.assemble_time += dt
	var time: float = entry.assemble_time
	var pose: Transform3D = entry.pose
	var count: int = entry.pieces.size()
	for index: int in count:
		var piece: Dictionary = entry.pieces[index]
		var target: Transform3D = pose*(piece.rest as Transform3D)
		var start: Transform3D = piece.start
		var lag := float(index)*.07
		var u := clampf((time-lag)/maxf(.1,ASSEMBLE_SECONDS-lag-.1),0.0,1.0)
		var eased := u*u*(3.0-2.0*u)
		var at := start.origin.lerp(target.origin,eased)+Vector3.UP*sin(PI*u)*.06
		var turn := start.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(),eased)
		var xf := Transform3D(Basis(turn),at)
		if time > ASSEMBLE_SECONDS:
			# The whole body squashes and stretches about its feet as it lands.
			var settle := time-ASSEMBLE_SECONDS
			var stretch := 1.0+.22*sin(settle*26.0)*exp(-settle*9.0)
			var squash := Transform3D(Basis.IDENTITY.scaled(Vector3(1.0/sqrt(stretch),stretch,1.0/sqrt(stretch))),Vector3.ZERO)
			xf = pose*squash*(piece.rest as Transform3D)
		(piece.node as Node3D).global_transform = xf
	return time >= ASSEMBLE_SECONDS+BOING_SECONDS

func _finish(entry: Dictionary) -> void:
	_free_pieces(entry)
	var source: Node = entry.source
	if is_instance_valid(source): source.call("restore_pedestrian",int(entry.id))

func _free_pieces(entry: Dictionary) -> void:
	for piece: Dictionary in entry.pieces:
		if is_instance_valid(piece.node): (piece.node as Node).free()
	entry.pieces.clear()

# ── Helpers ───────────────────────────────────────────────────────────────

## The first city surface on the segment, ignoring actors and traffic bodies.
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	if not is_inside_tree() or from.is_equal_approx(to): return {}
	var space := get_world_3d().direct_space_state
	if space == null: return {}
	var query := PhysicsRayQueryParameters3D.create(from,to,ExploreActorProfile.WORLD)
	if is_instance_valid(walker): query.exclude = [walker.get_rid()]
	return space.intersect_ray(query)

func _play(cue: StringName, volume_db: float, pitch: float) -> void:
	if not is_instance_valid(audio): return
	audio.play_stream(StringName("explore_"+String(cue)),ExploreMayhemSounds.stream(cue),volume_db,pitch,.03)

static func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D: chain = (current as Node3D).transform*chain
		current = current.get_parent()
	return chain
