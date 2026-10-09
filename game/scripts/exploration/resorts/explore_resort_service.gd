# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Gaming resort casino floors for one Explore session: entering through the
## front door, the floor's prompts and tables, and stepping back outside.
## Halls are built lazily the first time each resort is entered and kept for
## the session; only the occupied hall is visible, with its lamps and the one
## shared fill light. The city is only read.
class_name ExploreResortService
extends Node3D

signal table_requested(resort: StringName, game: StringName, table: Dictionary)
signal ejected(message: String)
## The walker was moved through a door; the session re-aims its camera.
signal moved

const Access := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")
const Layouts := preload("res://scripts/exploration/resorts/resort_interior_layouts.gd")
const Dresser := preload("res://scripts/exploration/resorts/resort_prop_dresser.gd")
## Whole fade-out/fade-in time of a door transition. Tests set 0.
static var transition_seconds := .3
## Shown when the occupied resort is demolished or replaced (%s: its name).
const CLOSED_MESSAGE := "%s is gone; you're back on the street."

var view: CityView3D
var traversal: CityTraversalWorld3D
var walker: ExplorePedestrian
var hud: ExploreHUD
var _worlds: Dictionary = {}
var _inside: ResortInteriorWorld3D
var _resort: Dictionary = {}
var _transitioning := false
## The single directional fill shared by every hall; on only while inside.
var fill: DirectionalLight3D
## The last hall the walker occupied, for recovery after leaving it.
var _last: ResortInteriorWorld3D
## The anchor of a hall that closed around the walker, until the session has
## rebuilt the physical world and `settle_ejection` finds a checked pose.
var _pending_ejection := Vector2i(-1,-1)
var _pending_code := -1

func bind(value: CityView3D, physical: CityTraversalWorld3D, pedestrian: ExplorePedestrian, interface: ExploreHUD) -> void:
	view = value
	traversal = physical
	walker = pedestrian
	hud = interface
	if not is_instance_valid(fill):
		fill = Dresser.make_fill()
		add_child(fill)
	_sync_presence()

## Show only the occupied hall (and so only its lamps) and the fill with it.
func _sync_presence() -> void:
	if is_instance_valid(_inside): _last = _inside
	for world: ResortInteriorWorld3D in _worlds.values():
		if is_instance_valid(world): world.visible = world == _inside
	if is_instance_valid(fill): fill.visible = is_instance_valid(_inside)

func is_inside() -> bool:
	return is_instance_valid(_inside)

func is_transitioning() -> bool:
	return _transitioning

func resort_key() -> StringName:
	return _inside.key if is_inside() else &""

## The built hall for a resort record, created on first use.
func world_for(resort: Dictionary) -> ResortInteriorWorld3D:
	var anchor: Vector2i = resort.anchor
	var code := int(resort.code)
	var world: ResortInteriorWorld3D = _worlds.get(anchor)
	if is_instance_valid(world) and world.code == code: return world
	if is_instance_valid(world):
		if world == _last: _last = null
		world.free()
	world = ResortInteriorWorld3D.new()
	add_child(world)
	world.build(StringName(resort.key),code,anchor)
	world.visible = world == _inside
	_worlds[anchor] = world
	return world

## Build (once) and walk through the door onto the entrance mat.
func enter(resort: Dictionary) -> bool:
	if _transitioning or is_inside() or resort.is_empty() or not is_instance_valid(walker): return false
	if not Access.exists(view.city,resort.anchor,int(resort.code)): return false
	var world := world_for(resort)
	_resort = resort.duplicate()
	_transition(func() -> void:
		# The hall can be closed by a city edit while the door fades.
		if not is_instance_valid(world): return
		_inside = world
		_sync_presence()
		_place(world.mat_transform()))
	return true

## Walk out through the door to the threshold, facing the street.
func leave() -> bool:
	if _transitioning or not is_inside(): return false
	var outside := _outdoor_pose()
	_transition(func() -> void:
		_inside = null
		_sync_presence()
		_place(outside))
	return true

func _transition(midpoint: Callable) -> void:
	walker.stop_input()
	if transition_seconds<=0.0 or not is_instance_valid(hud) or not hud.is_inside_tree():
		midpoint.call()
		return
	_transitioning = true
	hud.fade_through(func() -> void:
		if not is_instance_valid(walker): return
		midpoint.call()
		_transitioning = false,transition_seconds)

func _place(pose: Transform3D) -> void:
	walker.clear_support_frame()
	walker.global_transform = pose
	walker.stop_input()
	moved.emit()

## The supported outdoor pose in front of the current resort's door.
func _outdoor_pose() -> Transform3D:
	var anchor: Vector2i = _resort.get("anchor",_inside.anchor if is_inside() else Vector2i.ZERO)
	var clear := _clear_outdoor_pose(anchor)
	if not clear.is_empty(): return clear.transform
	var base := Access.threshold(view.city,anchor)
	return Transform3D(base.basis*Basis(Vector3.UP,PI),base.origin+Vector3.UP*.002)

## A supported, clear and dry pose in front of `anchor`'s door, facing the
## street, or {} when none of the probed steps qualifies.
func _clear_outdoor_pose(anchor: Vector2i, code: int = -1) -> Dictionary:
	var base := Access.threshold(view.city,anchor,code)
	# The threshold faces into the building; step out facing the street.
	var facing := base.basis*Basis(Vector3.UP,PI)
	var outward := facing*Vector3.FORWARD
	var exclude: Array[RID] = [walker.get_rid()]
	for step: float in [0.0,.08,.16,.24,.32]:
		var point := base.origin+outward*step
		var support := traversal.support_near(Vector3(point.x,point.y+.6,point.z),0.0,1.4,exclude)
		if support.is_empty(): continue
		var shape := ExploreActorProfile.shape(ExploreActorProfile.Mode.WALK) as CapsuleShape3D
		# Lift the rounded capsule clear of a sloped floor's uphill side.
		var normal: Vector3 = support.normal
		var skin := .002+shape.radius*(1.0/maxf(normal.y,.5)-1.0)
		var pose := Transform3D(facing,Vector3(point.x,float(support.position.y)+skin,point.z))
		var shape_pose := pose
		shape_pose.origin.y += float(ExploreActorProfile.geometry(ExploreActorProfile.Mode.WALK).foot_offset)
		if traversal.has_clearance(shape_pose,shape,exclude) and not traversal.touches_water(pose.origin): return {"transform": pose}
	return {}

## True when `feet` is inside the occupied hall. Hidden halls are not
## consulted; a walker outside every hall has none.
func contains(feet: Vector3) -> bool:
	return is_instance_valid(_inside) and _inside.contains(feet)

func support_for(feet: Vector3) -> Dictionary:
	if not contains(feet) or not is_instance_valid(traversal): return {}
	var exclude: Array[RID] = []
	if is_instance_valid(walker): exclude.append(walker.get_rid())
	var support := traversal.support_near(feet,.045,.12,exclude)
	if support.is_empty(): return {}
	return {"position": support.position, "frame": null}

## The entrance mat of the occupied (or last occupied) hall when `feet` lie
## in its volume.
func recover_pose(feet: Vector3) -> Dictionary:
	var world: ResortInteriorWorld3D = _inside if is_instance_valid(_inside) else _last
	if is_instance_valid(world) and world.contains(feet): return {"transform": world.mat_transform()}
	return {}

## The door or the nearest table seat within reach of `feet`, or {}.
func _target(feet: Vector3) -> Dictionary:
	if not is_inside() or not _inside.contains(feet): return {}
	var mat := _inside.mat_transform().origin
	if Vector2(feet.x-mat.x,feet.z-mat.z).length()<=Layouts.DOOR_REACH: return {"door": true}
	var best: Dictionary = {}
	var distance := Layouts.SEAT_REACH
	for table: Dictionary in _inside.tables():
		var seat: Vector3 = table.seat
		var gap := Vector2(feet.x-seat.x,feet.z-seat.z).length()
		if gap<distance and absf(feet.y-seat.y)<.06:
			distance = gap
			best = table
	return best

func prompt(feet: Vector3) -> String:
	var target := _target(feet)
	if target.is_empty(): return ""
	# The HUD swaps the leading "F to" for the bound key or "Interact".
	if target.has("door"): return CasinoLines.exit_prompt()
	return CasinoLines.play_prompt(String(target.name),Layouts.minimum(_inside.key))

func interact(feet: Vector3) -> bool:
	if _transitioning: return false
	var target := _target(feet)
	if target.is_empty(): return false
	if target.has("door"): return leave()
	walker.stop_input()
	table_requested.emit(_inside.key,StringName(target.game),target.duplicate())
	return true

## The authored seated view of a table record (world space).
func table_camera(table: Dictionary) -> Transform3D:
	return table.get("camera",Transform3D.IDENTITY)

## Containment watch: a walker who left the hall (for example by Recover)
## is simply outside again.
func step(_delta: float, pedestrian: ExplorePedestrian = null) -> void:
	if pedestrian != null: walker = pedestrian
	if _transitioning or not is_inside() or not is_instance_valid(walker): return
	if not _inside.contains(walker.global_position):
		_inside = null
		_sync_presence()

## After a city edit: a hall whose resort was demolished or replaced closes.
## A walker inside it is put outside first.
func refresh_geometry() -> void:
	for anchor: Vector2i in _worlds.keys():
		var world: ResortInteriorWorld3D = _worlds[anchor]
		if is_instance_valid(world) and Access.exists(view.city,anchor,world.code): continue
		var was_inside := world == _inside
		if _transitioning:
			# A door fade to or from this hall cannot finish: stop it here.
			if is_instance_valid(hud): hud.cancel_fade()
			_transitioning = false
		var closed_name := ResortThemes.resort_name(world.key) if is_instance_valid(world) else ""
		if closed_name.is_empty(): closed_name = "The resort"
		if was_inside:
			_inside = null
			_resort = {"anchor": anchor}
			# A provisional pose at the old door; the physical world still
			# shows the old building, so `settle_ejection` checks the real
			# pose once the session has rebuilt it.
			var code := world.code if is_instance_valid(world) else -1
			var door := Access.threshold(view.city,anchor,code)
			_place(Transform3D(door.basis*Basis(Vector3.UP,PI),door.origin+Vector3.UP*.002))
			_pending_ejection = anchor
			_pending_code = code
		if world == _last: _last = null
		_worlds.erase(anchor)
		if is_instance_valid(world): world.free()
		_sync_presence()
		if was_inside: ejected.emit(CLOSED_MESSAGE % closed_name)

func ejection_pending() -> bool:
	return _pending_ejection != Vector2i(-1,-1)

## After the physical world matches the edited city: move an ejected walker
## to a supported, clear, dry pose in front of the old door. False when there
## is none; the session then recovers the walker to the nearest road.
func settle_ejection() -> bool:
	if not ejection_pending(): return true
	var anchor := _pending_ejection
	_pending_ejection = Vector2i(-1,-1)
	if not is_instance_valid(walker) or not is_instance_valid(traversal): return false
	var pose := _clear_outdoor_pose(anchor,_pending_code)
	if pose.is_empty(): return false
	_place(pose.transform)
	return true

func status() -> Dictionary:
	var feet := walker.global_position if is_instance_valid(walker) else Vector3.ZERO
	return {"inside": is_inside(), "resort": resort_key(), "floor": String(_inside.plan.floor) if is_inside() else "",
		"prompt": prompt(feet) if is_inside() else ""}

func clear() -> void:
	_inside = null
	_last = null
	_resort = {}
	_pending_ejection = Vector2i(-1,-1)
	_transitioning = false
	if is_instance_valid(hud): hud.cancel_fade()
	for world: ResortInteriorWorld3D in _worlds.values():
		if is_instance_valid(world):
			world.visible = false
			world.free()
	_worlds.clear()
	if is_instance_valid(fill): fill.visible = false
