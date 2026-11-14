# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## One resident of the Mirage Menagerie (the Zoo, building 218).
## Presentation only: its motion follows its own clock and a phase taken from
## the lot's position. No city state, save data or game random stream.
##
## Positions are lot-model metres (+Z toward the gate), the units
## tools/blender_exploration/build_zoo.py uses. Each species keeps to its own
## railed pen; paths below avoid that pen's authored rocks, posts and trees.
class_name ZooAnimal
extends Node3D

const RAIL := 5.0
## Wall inner face.
const INNER := 30.45
## Plaque on the north-south promenade, |z|; visitors read it from |x| < RAIL.
const PLAQUE_Z := 17.95
const PLAQUE_X := 4.3
const TRICK_SECONDS := 3.0

const SPECIES := {
	&"saguaroo": {"name":"Saguaroo","quadrant":Vector2(1,1),
		"model":"res://assets/desert-dreams-zoo/saguaroo.glb",
		"fact":"Saguaroo (Macropus saguaro). Hops nine metres in one bound and keeps a week of water in its tail. Hugging is not recommended."},
	&"flamingoat": {"name":"Flamingoat","quadrant":Vector2(-1,1),
		"model":"res://assets/desert-dreams-zoo/flamingoat.glb",
		"fact":"Flamingoat (Capra rosea). Spends all day on one leg. Nobody, the Flamingoat included, knows which leg is the spare."},
	&"periscope_tortoise": {"name":"Periscope Tortoise","quadrant":Vector2(-1,-1),
		"model":"res://assets/desert-dreams-zoo/periscope_tortoise.glb",
		"fact":"Periscope Tortoise (Testudo vigilans). Raises its neck three metres to keep an eye on visitors. It has never once been surprised."},
	&"tumbleweasel": {"name":"Tumbleweasel","quadrant":Vector2(1,-1),
		"model":"res://assets/desert-dreams-zoo/tumbleweasel.glb",
		"fact":"Tumbleweasel (Mustela ventosa). Rolls forty kilometres on a windy day and is always home in time for supper."},
}
const ORDER: Array[StringName] = [&"saguaroo",&"flamingoat",&"periscope_tortoise",&"tumbleweasel"]

## Paths in the pen's positive quadrant (|x|, |z|); mirrored by `quadrant`.
const SAGUAROO_LOOP: Array[Vector2] = [Vector2(10,19),Vector2(16,22),Vector2(22,19),Vector2(23,11),Vector2(16,8),Vector2(8,12)]
const FLAMINGOAT_SPOTS: Array[Vector2] = [Vector2(8.5,17.5),Vector2(18,11.5),Vector2(24.5,15),Vector2(14,22)]
const TORTOISE_CENTRE := Vector2(18,16)
const TORTOISE_RADII := Vector2(7,4.5)
const TUMBLE_CENTRE := Vector2(18,18)
const TUMBLE_RADIUS := 6.2

const HOP_LENGTH := 1.8
const HOP_SECONDS := .5
const HOP_HEIGHT := .7
const WADE_SPEED := .7
const TORTOISE_SPEED := .3
const TUMBLE_SPEED := 3.0
const BALL_RADIUS := .55
const NECK_REACH := .5
const WATCH_METRES := 14.0
## The models are drawn a little larger than life so they read from the rails.
const MODEL_SCALE := 1.25

var species: StringName
var quadrant := Vector2.ONE
## Bone name -> index in this animal's skeleton.
var _bones: Dictionary = {}
var _rest: Array[Transform3D] = []
## This frame's local bone poses, built from the rest poses.
var _pose: Array[Transform3D] = []
var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
## Per species, built once and shared by every zoo: one skinned surface with
## the authored part colours in its vertices, the bone hierarchy and the skin.
static var _rigs: Dictionary = {}
static var _material: StandardMaterial3D
var _clock := 0.0
var _trick := 0.0
var _phase := 0.0
## Species state: travel distance, current leg, pause, poses.
var _state: Dictionary = {}

static func pen_point(q: Vector2, p: Vector2) -> Vector3:
	return Vector3(q.x*p.x,0.2,q.y*p.y)

## True when a lot-local point (metres) lies inside `q`'s pen, past its rails.
static func inside_pen(q: Vector2, local: Vector3) -> bool:
	var x := local.x*q.x
	var z := local.z*q.y
	return x > RAIL and x < INNER and z > RAIL and z < INNER

## The walkway point where a visitor reads this pen's plaque.
static func plaque_point(q: Vector2) -> Vector3:
	return Vector3(q.x*PLAQUE_X,0.2,q.y*PLAQUE_Z)

func setup(kind: StringName, phase: float) -> void:
	species = kind
	name = String(kind)
	quadrant = SPECIES[kind].quadrant
	_phase = phase
	var rig := rig_for(kind)
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Model"
	_skeleton.scale = Vector3.ONE*MODEL_SCALE
	var names: PackedStringArray = rig.names
	var parents: PackedInt32Array = rig.parents
	for i: int in names.size():
		_skeleton.add_bone(names[i])
		_skeleton.set_bone_parent(i,parents[i])
		_skeleton.set_bone_rest(i,rig.rests[i])
		_bones[StringName(names[i])] = i
	_rest.assign(rig.rests)
	_pose.assign(rig.rests)
	add_child(_skeleton)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Body"
	_mesh.mesh = rig.mesh
	_mesh.skin = rig.skin
	_skeleton.add_child(_mesh)
	_mesh.skeleton = _mesh.get_path_to(_skeleton)
	_state = {"distance":phase*7.0,"leg":0,"pause":0.0,"spot":0,"wait":0.0,"stance":0}
	_clock = phase*13.0
	advance(0.0)

## Merge an animal GLB's jointed parts into one skinned mesh: each part becomes
## a bone with its authored joint as rest, and each material's colour moves into
## the vertices, so the whole animal is one draw (plus its shadow).
static func rig_for(kind: StringName) -> Dictionary:
	if _rigs.has(kind): return _rigs[kind]
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.resource_name = "zoo_animal"
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = .75
	var scene := (load(SPECIES[kind].model) as PackedScene).instantiate() as Node3D
	var names := PackedStringArray()
	var parents := PackedInt32Array()
	var rests: Array[Transform3D] = []
	var globals: Array[Transform3D] = []
	var index_of: Dictionary = {}
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	# Pre-order, so a parent always precedes its children.
	var stack: Array[Node] = []
	for child: Node in scene.get_children(): stack.push_front(child)
	while not stack.is_empty():
		var node := stack.pop_front() as Node
		if not node is Node3D: continue
		var bone := names.size()
		index_of[node] = bone
		names.append(String(node.name))
		var parent: int = index_of.get(node.get_parent(),-1)
		parents.append(parent)
		var local := (node as Node3D).transform
		rests.append(local)
		globals.append(local if parent < 0 else globals[parent]*local)
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var source := (node as MeshInstance3D).mesh
			var at: Transform3D = globals[bone]
			for surface: int in source.get_surface_count():
				var arrays := source.surface_get_arrays(surface)
				var material := source.surface_get_material(surface) as BaseMaterial3D
				var color := material.albedo_color if material != null else Color.WHITE
				var offset := verts.size()
				var sv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var sn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for v: int in sv.size():
					verts.append(at*sv[v])
					normals.append((at.basis*sn[v]).normalized())
					colors.append(color)
					bones.append_array([bone,0,0,0])
					weights.append_array([1.0,0.0,0.0,0.0])
				var si = arrays[Mesh.ARRAY_INDEX]
				if si == null:
					for v: int in sv.size(): indices.append(offset+v)
				else:
					for v: int in (si as PackedInt32Array): indices.append(offset+v)
		var children := node.get_children()
		children.reverse()
		for child: Node in children: stack.push_front(child)
	scene.free()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,_material)
	var skin := Skin.new()
	for i: int in names.size(): skin.add_bind(i,globals[i].affine_inverse())
	var rig := {"mesh":mesh,"skin":skin,"names":names,"parents":parents,"rests":rests}
	_rigs[kind] = rig
	return rig

func display_name() -> String:
	return SPECIES[species].name

func fact() -> String:
	return SPECIES[species].fact

func has_part(part_name: StringName) -> bool:
	return _bones.has(part_name)

## This frame's local pose of a part, relative to its parent joint.
func part_pose(part_name: StringName) -> Transform3D:
	return _pose[_bones[part_name]] if _bones.has(part_name) else Transform3D.IDENTITY

## The single skinned mesh that draws the whole animal.
func mesh_instance() -> MeshInstance3D:
	return _mesh

## Drawn at all, and with a shadow, as the zoo decides from its screen size.
func set_detail(drawn: bool, shadow: bool) -> void:
	if visible != drawn: visible = drawn
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _mesh.cast_shadow != mode: _mesh.cast_shadow = mode

func tricking() -> bool:
	return _trick > 0.0

func start_trick() -> void:
	_trick = TRICK_SECONDS

## `player` is the visitor's lot-local position (metres), or INF when absent.
func advance(delta: float, player: Vector3 = Vector3.INF) -> void:
	_clock += delta
	_trick = maxf(0.0,_trick-delta)
	for i: int in _rest.size(): _pose[i] = _rest[i]
	match species:
		&"saguaroo": _saguaroo(delta,player)
		&"flamingoat": _flamingoat(delta,player)
		&"periscope_tortoise": _tortoise(delta,player)
		&"tumbleweasel": _tumbleweasel(delta,player)
	for i: int in _pose.size(): _skeleton.set_bone_pose(i,_pose[i])

func _face(direction: Vector2) -> float:
	return atan2(direction.x,direction.y)

func _rotate(key: StringName, axis: Vector3, angle: float) -> void:
	var i: int = _bones.get(key,-1)
	if i >= 0: _pose[i].basis = _pose[i].basis * Basis(axis,angle)

func _shift(key: StringName, offset: Vector3) -> void:
	var i: int = _bones.get(key,-1)
	if i >= 0: _pose[i].origin += offset

## Turn a head toward the visitor, within `limit` radians of straight ahead.
func _look(key: StringName, player: Vector3, limit: float) -> void:
	if not player.is_finite(): return
	if not _bones.has(key): return
	var to := player-position
	if Vector2(to.x,to.z).length() > WATCH_METRES: return
	var want := wrapf(atan2(to.x,to.z)-rotation.y,-PI,PI)
	_rotate(key,Vector3.UP,clampf(want,-limit,limit))

func _mirror(p: Vector2) -> Vector2:
	return Vector2(p.x*quadrant.x,p.y*quadrant.y)

# --- Saguaroo: hops round its pen in strings of bounds, pausing to look about.
func _saguaroo(delta: float, player: Vector3) -> void:
	var points: Array[Vector2] = []
	for p: Vector2 in SAGUAROO_LOOP: points.append(_mirror(p))
	var lengths: Array[float] = []
	var total := 0.0
	for i: int in points.size():
		var length := points[i].distance_to(points[(i+1)%points.size()])
		lengths.append(length)
		total += length
	if _trick > 0.0:
		var t := 1.0-_trick/TRICK_SECONDS
		position.y = .2+maxf(0.0,sin(t*PI))*2.2
		rotation.y = float(_state.get("yaw",0.0))+t*TAU
		_rotate(&"ArmL",Vector3.FORWARD,-.9*sin(t*TAU*3.0))
		_rotate(&"ArmR",Vector3.FORWARD,.9*sin(t*TAU*3.0))
		_rotate(&"Tail",Vector3.RIGHT,.5*sin(t*PI))
		_tuck_legs(sin(t*PI))
		return
	# A string of bounds covers one leg of the loop, then the animal rests.
	if float(_state.pause) > 0.0:
		_state.pause = maxf(0.0,float(_state.pause)-delta)
	else:
		_state.distance = float(_state.distance)+delta*HOP_LENGTH/HOP_SECONDS
	var along := fposmod(float(_state.distance),total)
	var leg := 0
	while along > lengths[leg]:
		along -= lengths[leg]
		leg += 1
	if leg != int(_state.leg):
		_state.leg = leg
		_state.pause = 1.5+fposmod(_phase*7.0+float(leg)*1.37,1.5)
	var a := points[leg]
	var b := points[(leg+1)%points.size()]
	var at := a.lerp(b,along/lengths[leg])
	var hop := fposmod(along,HOP_LENGTH)/HOP_LENGTH
	var airborne := float(_state.pause) <= 0.0
	position = Vector3(at.x,.2+(sin(hop*PI)*HOP_HEIGHT if airborne else 0.0),at.y)
	rotation.y = _face(b-a)
	_state.yaw = rotation.y
	if airborne:
		_tuck_legs(sin(hop*PI))
		_rotate(&"Tail",Vector3.RIGHT,.35*sin(hop*PI))
		_rotate(&"Body",Vector3.RIGHT,-.08*sin(hop*PI))
	else:
		_rotate(&"ArmL",Vector3.FORWARD,-.25*sin(_clock*2.0))
		_rotate(&"ArmR",Vector3.FORWARD,.25*sin(_clock*2.0+1.0))
		_rotate(&"Head",Vector3.UP,.5*sin(_clock*.9))
		_look(&"Head",player,1.1)

func _tuck_legs(amount: float) -> void:
	_rotate(&"LegL",Vector3.RIGHT,-.55*amount)
	_rotate(&"LegR",Vector3.RIGHT,-.55*amount)

# --- Flamingoat: wades between three spots, then stands on one leg grazing.
func _flamingoat(delta: float, player: Vector3) -> void:
	var spots: Array[Vector2] = []
	for p: Vector2 in FLAMINGOAT_SPOTS: spots.append(_mirror(p))
	var from := int(_state.spot)%spots.size()
	var to := (from+1)%spots.size()
	var a := spots[from]
	var b := spots[to]
	if _trick > 0.0:
		var t := 1.0-_trick/TRICK_SECONDS
		position.y = .2+.1*sin(t*PI)
		rotation.y = float(_state.get("yaw",0.0))+t*TAU*2.0
		_fold_leg(&"R",1.0)
		_rotate(&"Neck",Vector3.RIGHT,-.35)
		_rotate(&"Tail",Vector3.UP,.6*sin(t*TAU*4.0))
		return
	var length := a.distance_to(b)
	if float(_state.wait) > 0.0:
		# Standing: one leg tucked, the neck dipping to graze now and then.
		_state.wait = maxf(0.0,float(_state.wait)-delta)
		position = Vector3(a.x,.2,a.y)
		var side := &"R" if int(_state.stance)%2 == 0 else &"L"
		_fold_leg(side,1.0)
		var graze := clampf(sin(_clock*.7+_phase*5.0)*1.6-.4,0.0,1.0)
		_rotate(&"Neck",Vector3.RIGHT,.95*graze)
		_rotate(&"Head",Vector3.RIGHT,.3*graze)
		_rotate(&"Tail",Vector3.UP,.4*sin(_clock*5.0))
		if graze < .05: _look(&"Head",player,1.0)
		rotation.y = float(_state.get("yaw",_face(b-a)))
		if float(_state.wait) <= 0.0: _state.distance = 0.0
		return
	_state.distance = float(_state.distance)+delta*WADE_SPEED
	var t := clampf(float(_state.distance)/length,0.0,1.0)
	var at := a.lerp(b,t)
	position = Vector3(at.x,.2,at.y)
	rotation.y = _face(b-a)
	_state.yaw = rotation.y
	var stride := sin(float(_state.distance)*PI/.55)
	_rotate(&"LegL",Vector3.RIGHT,.35*stride)
	_rotate(&"LegR",Vector3.RIGHT,-.35*stride)
	_rotate(&"Body",Vector3.FORWARD,.04*stride)
	if t >= 1.0:
		_state.spot = to
		_state.stance = int(_state.stance)+1
		_state.wait = 6.0+fposmod(_phase*11.0+float(to)*2.3,4.0)

func _fold_leg(side: StringName, amount: float) -> void:
	_rotate(StringName("Leg"+side),Vector3.RIGHT,-.5*amount)
	_rotate(StringName("Shin"+side),Vector3.RIGHT,2.4*amount)

# --- Periscope Tortoise: plods round its meadow; raises its periscope to watch.
func _tortoise(delta: float, player: Vector3) -> void:
	var centre := _mirror(TORTOISE_CENTRE)
	var watching := false
	if player.is_finite():
		watching = Vector2(player.x-position.x,player.z-position.z).length() <= WATCH_METRES
	var reach := float(_state.get("reach",0.0))
	var goal := 1.0 if watching or _trick > 0.0 else 0.0
	reach = move_toward(reach,goal,delta*.8)
	_state.reach = reach
	if not watching and _trick <= 0.0 and reach < .5:
		_state.distance = float(_state.distance)+delta*TORTOISE_SPEED
	var angle := float(_state.distance)/((TORTOISE_RADII.x+TORTOISE_RADII.y)*.5)
	var spin := quadrant.x*quadrant.y
	var at := centre+Vector2(TORTOISE_RADII.x*cos(angle*spin),TORTOISE_RADII.y*sin(angle*spin))
	var tangent := Vector2(-TORTOISE_RADII.x*sin(angle*spin),TORTOISE_RADII.y*cos(angle*spin))*spin
	position = Vector3(at.x,.2,at.y)
	rotation.y = _face(tangent)
	var walking := not watching and _trick <= 0.0 and reach < .5
	if walking:
		var stride := sin(float(_state.distance)*TAU/.6)
		for i: int in 4:
			_rotate(StringName("Leg%d" % i),Vector3.RIGHT,.35*stride*(1.0 if i in [0,3] else -1.0))
		_shift(&"Shell",Vector3(0,.02*absf(stride),0))
	# Retracted, the periscope tips forward and its segments nest.
	_rotate(&"NeckA",Vector3.RIGHT,(1.0-reach)*1.05)
	_shift(&"NeckB",Vector3(0,-NECK_REACH*(1.0-reach),0))
	_shift(&"NeckC",Vector3(0,-NECK_REACH*(1.0-reach),0))
	if _trick > 0.0:
		var t := 1.0-_trick/TRICK_SECONDS
		_rotate(&"Head",Vector3.UP,t*TAU*2.0)
		_rotate(&"NeckC",Vector3.FORWARD,.25*sin(t*TAU*2.0))
	elif watching and reach > .2:
		_look(&"Head",player,PI)
	else:
		_rotate(&"Head",Vector3.UP,.4*sin(_clock*.6))

# --- Tumbleweasel: rolls laps of its track, sitting up now and then.
func _tumbleweasel(delta: float, player: Vector3) -> void:
	var centre := _mirror(TUMBLE_CENTRE)
	var cycle := fposmod(_clock+_phase*9.0,12.0)
	var sitting := cycle > 9.0 and _trick <= 0.0
	if not sitting:
		var speed := TUMBLE_SPEED*(2.0 if _trick > 0.0 else 1.0)
		_state.distance = float(_state.distance)+delta*speed
	var angle := float(_state.distance)/TUMBLE_RADIUS
	var spin := quadrant.x*quadrant.y
	var at := centre+Vector2(cos(angle*spin),sin(angle*spin))*TUMBLE_RADIUS
	var tangent := Vector2(-sin(angle*spin),cos(angle*spin))*spin
	position = Vector3(at.x,.2,at.y)
	rotation.y = _face(tangent)
	_rotate(&"Ball",Vector3.RIGHT,float(_state.distance)/BALL_RADIUS)
	_rotate(&"Tail",Vector3.UP,.5*sin(_clock*6.0))
	if _trick > 0.0:
		var t := 1.0-_trick/TRICK_SECONDS
		position.y += absf(sin(t*PI*3.0))*.9
		_rotate(&"Head",Vector3.RIGHT,-.3)
	elif sitting:
		var up := sin(clampf((cycle-9.0)/3.0,0.0,1.0)*PI)
		position.y += .18*up
		_rotate(&"Head",Vector3.RIGHT,-.45*up)
		_rotate(&"Head",Vector3.UP,.8*sin((cycle-9.0)*2.4)*up)
		_look(&"Head",player,1.2)
	else:
		_rotate(&"Head",Vector3.RIGHT,.08*sin(float(_state.distance)*3.0))
