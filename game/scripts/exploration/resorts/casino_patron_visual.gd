# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## A catalog visitor with session-driven walking and small game gestures.
## Bone poses and materials belong to this instance; imported art is immutable.
extends Node3D

var actor: ExploreActorVisual
var _skeleton: Skeleton3D
var _bones: Dictionary = {}
var _rests: Dictionary = {}
var _clock := 0.0
var _phase := 0.0

func configure(variant: int) -> void:
	actor = CityTrafficCatalog.make_nearby_visual(&"pedestrian",variant)
	_phase = float(variant)*.73
	add_child(actor)
	for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		mesh.layers = ResortInteriorWorld3D.LAYER
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _ready() -> void:
	var skeletons := actor.find_children("*","Skeleton3D",true,false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0] as Skeleton3D
		for bone: String in ["Hips","LeftThigh","RightThigh","LeftShin","RightShin","Chest","Head","LeftUpperArm","RightUpperArm","LeftForearm","RightForearm","LeftHand","RightHand"]:
			_bones[bone] = _skeleton.find_bone(bone)
			if int(_bones[bone])>=0: _rests[bone] = _skeleton.get_bone_rest(int(_bones[bone])).basis.get_rotation_quaternion()
	actor.set_gait_phase(fposmod(_phase,1.0))

func advance(delta: float, speed: float, game: StringName, playing: bool, seated: bool = false) -> void:
	_clock += delta
	actor.position.y = 0.0
	actor.set_motion(speed,0.0,false)
	actor.advance_visual(delta)
	if not playing or _skeleton == null: return
	if seated:
		for side: String in ["Left","Right"]:
			_pose(side+"Thigh",PI*.5,0.0)
			_pose(side+"Shin",-PI*.5,0.0)
		# The stool cushion tops out at .73 m. Place the pelvis above it
		# for every roster height; only the visual moves, never the route.
		var hip := _skeleton.get_bone_global_pose(int(_bones["Hips"])).origin
		actor.position.y = .83/16.0-to_local(_skeleton.to_global(hip)).y
	var cycle := fposmod(_clock+_phase,7.0)
	var reach := sin(clampf(cycle/1.8,0.0,1.0)*PI)
	var tapping := .5+.5*sin((_clock+_phase)*5.0)
	var machine := game in [&"slots",&"video_poker",&"trajectory",&"vault_circuit",&"afterglow_forecast"]
	# A button press at a machine; at a table, a hand reaches over the rail
	# and retracts after placing a bet. The left hand rests near the rail.
	_pose("LeftUpperArm",.16,-.08)
	_pose("LeftForearm",.95,0.0)
	_pose("RightUpperArm",.22+reach*.32,.07)
	_pose("RightForearm",1.05+(.25*tapping if machine else .45*reach),0.0)
	_pose("RightHand",-.12+reach*.2,0.0)
	_pose("Head",.05+reach*.07,0.0)
	# A brief pleased reaction between rounds, desynchronized across people.
	if cycle>5.6:
		var reaction := sin((cycle-5.6)/1.4*PI)
		_pose("RightForearm",1.15+reaction*.7,0.0)
		_pose("Chest",-.03*reaction,0.0)

func _pose(bone: String, bend: float, spread: float) -> void:
	var index := int(_bones.get(bone,-1))
	# Godot 4 bone poses include Bone Rest. Preserve the imported local axes
	# before adding the gesture; a bare Euler rotation distorts the skin.
	if index>=0: _skeleton.set_bone_pose_rotation(index,_rests[bone]*Quaternion.from_euler(Vector3(bend,0,spread)))
