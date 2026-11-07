# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## One rail or subway passenger: the street crowd's rigged model, walking,
## standing or seated. Bone poses belong to this instance; imported art and
## shared animation libraries stay unchanged.
extends Node3D

var actor: ExploreActorVisual
var _skeleton: Skeleton3D
var _bones: Dictionary = {}
var _rests: Dictionary = {}
var _clock := 0.0
var _phase := 0.0
var _hip_height := -1.0

func configure(variant: int) -> void:
	actor = CityTrafficCatalog.make_nearby_visual(&"pedestrian",variant)
	_phase = float(posmod(variant*37,97))*.13
	add_child(actor)
	for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _ready() -> void:
	var skeletons := actor.find_children("*","Skeleton3D",true,false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0] as Skeleton3D
		for bone: String in ["Hips","LeftThigh","RightThigh","LeftShin","RightShin","Chest","Head","LeftUpperArm","RightUpperArm","LeftForearm","RightForearm","LeftHand","RightHand"]:
			_bones[bone] = _skeleton.find_bone(bone)
			if int(_bones[bone])>=0: _rests[bone] = _skeleton.get_bone_rest(int(_bones[bone])).basis.get_rotation_quaternion()
	actor.set_gait_phase(fposmod(_phase,1.0))

## `seat_height` is the cushion top above this node's origin, or negative
## for a standing or walking rider. `animate` false keeps the pose only.
func advance(delta: float, speed: float, seat_height: float, animate: bool = true) -> void:
	_clock += delta
	actor.position.y = 0.0
	actor.set_motion(speed,0.0,false)
	if animate: actor.advance_visual(delta)
	if _skeleton == null: return
	var look := sin((_clock+_phase)*.37)*.35*clampf(sin((_clock+_phase)*.11)*3.0,-1.0,1.0)
	if seat_height>=0.0:
		for side: String in ["Left","Right"]:
			_pose(side+"Thigh",PI*.5,0.0)
			_pose(side+"Shin",-PI*.5,0.0)
			# Hands rest on the lap.
			_pose(side+"UpperArm",.42,0.0)
			_pose(side+"Forearm",.80,0.0)
		_pose("Head",.06,look*.6)
		if _hip_height<0.0:
			var hip := _skeleton.get_bone_global_pose(int(_bones["Hips"])).origin
			_hip_height = to_local(_skeleton.to_global(hip)).y
		# The pelvis rests a little above the cushion for every roster height.
		actor.position.y = seat_height+.10/16.0-_hip_height
	elif absf(speed)<=.0001:
		# A waiting rider glances up and down the line now and then.
		_pose("Head",0.0,look)

func seated_hip() -> Vector3:
	if _skeleton == null or int(_bones.get("Hips",-1))<0: return global_position
	return _skeleton.to_global(_skeleton.get_bone_global_pose(int(_bones["Hips"])).origin)

func _pose(bone: String, bend: float, spread: float) -> void:
	var index := int(_bones.get(bone,-1))
	# Godot 4 bone poses include Bone Rest; keep the imported local axes.
	if index>=0: _skeleton.set_bone_pose_rotation(index,_rests[bone]*Quaternion.from_euler(Vector3(bend,spread,0)))
