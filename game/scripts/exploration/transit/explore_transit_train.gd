# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Short passenger carriage: physical floor, cabin walls and platform-side doors.
class_name ExploreTransitTrain
extends Node3D

const FLOOR_Y := .025
const CABIN := AABB(Vector3(-.10625,FLOOR_Y,-.28),Vector3(.2125,.205,.56))
const DWELL := 8.0
## Authored carriage materials and the cabin finish each one receives.
const FINISHES := {"traffic_floor":0,"traffic_panel":1,"traffic_cream":1,"traffic_teal":2,"traffic_seat":3,"traffic_copper":3,
	"traffic_gold":4,"traffic_metal":5,"traffic_light":6,"traffic_ceiling":7,"traffic_walnut":8,"traffic_rubber":9}
static var _finish_materials: Dictionary = {}
var door_side := 1
var doors := "closed"
var door_fraction := 0.0
var _body: AnimatableBody3D
var _door_bodies: Array[AnimatableBody3D] = []

func _ready() -> void:
	_body = AnimatableBody3D.new()
	_body.sync_to_physics = false
	_body.collision_layer = ExploreActorProfile.FLOOR | ExploreActorProfile.OBSTACLE
	_body.collision_mask = 0
	add_child(_body)
	# The authored carriage model is the visual; these boxes match its floor,
	# roof, end walls and window apertures for collision.
	_collision(_body,Vector3(0,.015,0),Vector3(.25,.02,.625))
	_collision(_body,Vector3(0,.225,0),Vector3(.25,.018,.625))
	for z: float in [-.302,.302]:
		_collision(_body,Vector3(0,.124,z),Vector3(.25,.20,.02))
	for side: int in [-1,1]:
		for z: float in [-.192,.192]:
			# Below-window panel and window frame leave genuine scenery apertures.
			_collision(_body,Vector3(side*.119,.07,z),Vector3(.012,.09,.225))
			_collision(_body,Vector3(side*.119,.204,z),Vector3(.012,.028,.225))
			for end: float in [-.105,.105]:
				_collision(_body,Vector3(side*.119,.153,z+end),Vector3(.012,.11,.015))
			# Invisible glass collision prevents escape through a window.
			_collision(_body,Vector3(side*.119,.154,z),Vector3(.012,.09,.225))
		var door := AnimatableBody3D.new()
		door.sync_to_physics = false
		door.collision_layer = ExploreActorProfile.OBSTACLE
		door.collision_mask = 0
		add_child(door)
		_collision(door,Vector3.ZERO,Vector3(.014,.19,.15))
		var windowed_door := (load("res://assets/desert-dreams-traffic/transit/passenger_door.glb") as PackedScene).instantiate()
		windowed_door.scale=Vector3.ONE/16.0
		windowed_door.position.y=-.12
		windowed_door.set_meta("authored_passenger_door",true)
		dress(windowed_door)
		door.add_child(windowed_door)
		door.position = Vector3(side*.121,.12,0)
		_door_bodies.append(door)
	var visual := (load("res://assets/desert-dreams-traffic/transit/passenger_carriage.glb") as PackedScene).instantiate()
	visual.scale = Vector3.ONE/16.0
	dress(visual)
	add_child(visual)
	# Operator lettering on both end headers, facing the riders.
	for end: float in [-1.0,1.0]:
		var at := Transform3D(Basis(Vector3.UP,PI if end>0 else 0.0),Vector3(0,.189,end*.2975))
		ExploreStationInterior.add_plaque(self,at,"DESERT TRANSIT",.00030,Color(.025,.24,.23),Vector2(.125,.024))

## Replace the authored flat colours with the procedural cabin finishes. The
## same shared ShaderMaterial serves every carriage and door surface of a kind.
static func dress(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for surface: int in node.mesh.get_surface_count():
			var source: Material = node.get_active_material(surface)
			if source == null: continue
			var key := source.resource_name
			if not FINISHES.has(key): continue
			node.set_surface_override_material(surface,finish_material(key,source))
	for child: Node in node.get_children(): dress(child)

static func finish_material(key: String, source: Material) -> ShaderMaterial:
	if not _finish_materials.has(key):
		var material := ShaderMaterial.new()
		material.resource_name = "carriage_finish_"+key.trim_prefix("traffic_")
		material.shader = preload("res://scripts/exploration/transit/carriage_finish.gdshader")
		material.set_shader_parameter("finish",int(FINISHES[key]))
		var color := Color(.9,.86,.76)
		if source is BaseMaterial3D: color = (source as BaseMaterial3D).albedo_color
		material.set_shader_parameter("base_color",Vector3(color.r,color.g,color.b))
		_finish_materials[key] = material
	return _finish_materials[key]

func _collision(parent: Node3D, center: Vector3, size: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	parent.add_child(shape)
	return shape

func set_doors(fraction: float, platform_normal: Vector3) -> void:
	door_side = 1 if global_basis.x.dot(platform_normal)>=0 else -1
	door_fraction = clampf(fraction,0,1)
	for i: int in _door_bodies.size():
		var side := -1 if i==0 else 1
		var amount := door_fraction if side==door_side else 0.0
		_door_bodies[i].position.z = amount*.17
		# The sliding physical panel moves aside; only fully open doorway is
		# admitted as a support bridge by support_for below.

func doorway_occupied(feet: Vector3) -> bool:
	var local := global_transform.affine_inverse()*feet
	return absf(local.x-door_side*.12)<.065 and absf(local.z)<.105 and local.y>=.015 and local.y<.25

func contains(feet: Vector3) -> bool:
	var local := global_transform.affine_inverse()*feet
	return local.x>=-.111 and local.x<=.111 and absf(local.z)<=.287 and local.y>=FLOOR_Y-.012 and local.y<=.245

func support_for(feet: Vector3) -> Dictionary:
	var local := global_transform.affine_inverse()*feet
	var inside := contains(feet)
	var bridge := door_fraction>=.999 and absf(local.z)<.075 and local.x*door_side>=.10 and local.x*door_side<=.15 and local.y>=.013 and local.y<.25
	if not inside and not bridge: return {}
	var result := {"position":global_transform*Vector3(local.x,FLOOR_Y,local.z),"normal":global_basis.y}
	if inside: result.frame = self
	return result

func cabin_transform() -> Transform3D:
	return global_transform
