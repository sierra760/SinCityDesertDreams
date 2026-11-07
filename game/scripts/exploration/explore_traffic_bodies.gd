# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Physical stand-ins for the ambient traffic around the player in Explore.
## Ambient vehicles and pedestrians are presentation records with no physics,
## so without these the player's car, boat, train or walker passes straight
## through them. Each nearby record gets a static body on the actor layer,
## shaped like its authored model (a box for vehicles and boats, a capsule for
## people) and placed at the record's displayed pose every physics tick.
## Bodies are pooled per kind; nothing here moves or changes traffic.
class_name ExploreTrafficBodies
extends Node3D

## Tiles around the occupied actor that receive bodies: more than two
## seconds of driving at full speed.
const RANGE := 2.5
const LIMIT := 64
var traffic: CityTraffic3D
var _active: Dictionary = {}
var _spare: Dictionary = {}

func bind(value: CityTraffic3D) -> void:
	clear()
	traffic = value

## Place a body at every ground traffic record near `center`; release the rest.
func sync(center: Vector3) -> void:
	var wanted: Array[Dictionary] = []
	if is_instance_valid(traffic): wanted = traffic.collision_candidates(center,RANGE,LIMIT)
	var next: Dictionary = {}
	for candidate: Dictionary in wanted:
		var kind: StringName = candidate.kind
		var body: StaticBody3D = _active.get(candidate.key)
		if body != null and StringName(body.get_meta(&"kind")) != kind:
			_release(body)
			body = null
		if body == null: body = _take(kind)
		_active.erase(candidate.key)
		body.global_transform = candidate.pose
		next[candidate.key] = body
	for body: StaticBody3D in _active.values(): _release(body)
	_active = next

func count() -> int: return _active.size()

## Bodies in use, by traffic key ("a:<id>" ambient, "x:<id>" simulation record).
func bodies() -> Dictionary: return _active.duplicate()

func clear() -> void:
	for body: StaticBody3D in _active.values(): body.free()
	for pool: Array in _spare.values():
		for body: StaticBody3D in pool: body.free()
	_active.clear()
	_spare.clear()

func _take(kind: StringName) -> StaticBody3D:
	var pool: Array = _spare.get(kind,[])
	var body: StaticBody3D
	if not pool.is_empty():
		body = pool.pop_back()
	else:
		body = StaticBody3D.new()
		body.name = "Traffic_"+String(kind)
		body.set_meta(&"kind",kind)
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		var bounds := CityTraffic3D.body_bounds(kind)
		collider.shape = shape_for(kind,bounds)
		collider.position = bounds.get_center()
		body.add_child(collider)
		add_child(body)
	body.collision_layer = ExploreActorProfile.ACTOR
	(body.get_child(0) as CollisionShape3D).disabled = false
	return body

func _release(body: StaticBody3D) -> void:
	body.collision_layer = 0
	(body.get_child(0) as CollisionShape3D).disabled = true
	var kind: StringName = body.get_meta(&"kind")
	if not _spare.has(kind): _spare[kind] = []
	_spare[kind].append(body)

## The authored envelope as a collision shape. A person is an upright capsule
## as wide as the model's shoulders are deep; everything else is its box.
static func shape_for(kind: StringName, bounds: AABB) -> Shape3D:
	if kind == &"pedestrian":
		var capsule := CapsuleShape3D.new()
		capsule.radius = minf(bounds.size.x,bounds.size.z)*.5
		capsule.height = maxf(bounds.size.y,capsule.radius*2.0)
		return capsule
	var box := BoxShape3D.new()
	box.size = bounds.size
	return box
