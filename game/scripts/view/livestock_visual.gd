# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
class_name LivestockVisual
extends Node3D
## Independent skeleton poses; shared immutable meshes, skins and materials.
var _animal:Node3D
var _rig:Skeleton3D
var _baseline:Array[Transform3D]=[]
var _limits:Dictionary={}
var _variant:=0.0

func configure(species:StringName,variant:int,catalog:RefCounted)->void:
	if is_instance_valid(_animal):remove_child(_animal);_animal.free()
	_rig=null;_baseline.clear();_limits.clear()
	_animal=catalog.make_animal(species)
	if _animal==null:return
	add_child(_animal);_rig=_find_rig(_animal)
	_limits=catalog.animal_profile(species)["pose_limits_degrees"]
	_variant=float(posmod(variant,97))*.731
	if _rig!=null:
		for i:int in _rig.get_bone_count():_baseline.append(_rig.get_bone_pose(i))

func apply_state(state:Dictionary,delta:float)->void:
	if _rig==null or not is_finite(delta) or delta<0.0:return
	var p:Vector3=state.get("position",Vector3.INF)
	var heading:float=state.get("heading",NAN);var phase:float=state.get("gait_phase",NAN);var speed:float=state.get("speed",NAN)
	if not p.is_finite() or not is_finite(heading) or not is_finite(phase) or not is_finite(speed):return
	position=p;rotation.y=heading
	for i:int in _baseline.size():
		_rig.set_bone_pose_position(i,_baseline[i].origin)
		_rig.set_bone_pose_rotation(i,_baseline[i].basis.get_rotation_quaternion())
		_rig.set_bone_pose_scale(i,_baseline[i].basis.get_scale())
	var activity:String=state.get("activity","idle")
	var lower:=activity in ["graze","drink"]
	# All oscillators are periodic in the wrapped gait input. Offsets vary timing
	# without an independent render clock, so a frozen state keeps every pose fixed.
	_pose("Neck",Vector3.RIGHT,(float(_limits["Neck"][1])-.8) if lower else 2.0*sin(phase+_variant+.7))
	_pose("Head",Vector3.RIGHT,14.0 if lower else 3.0*sin(phase+_variant+2.1))
	_pose("Tail",Vector3.UP,19.0*sin(phase+_variant))
	if speed>.01:
		var strength:=clampf(speed/1.2,0.0,1.0)
		var names:Array[String]=["FrontLeft","RearRight","FrontRight","RearLeft"]
		for i:int in names.size():
			# Four-beat walk: each leg swings then returns to the exact grounded rest.
			var swing:=maxf(0.0,sin(phase+float(i)*PI*.5))
			_pose(names[i]+"Upper",Vector3.RIGHT,18.0*swing*strength)
			_pose(names[i]+"Lower",Vector3.RIGHT,-28.0*swing*strength)

func _pose(bone:String,axis:Vector3,degrees:float)->void:
	var index:=_rig.find_bone(bone)
	if index<0:return
	var bounds:Array=_limits[bone]
	var angle:=deg_to_rad(clampf(degrees,bounds[0],bounds[1]))
	var local_axis:=(_rig.get_bone_global_rest(index).basis.inverse()*axis).normalized()
	_rig.set_bone_pose_rotation(index,_baseline[index].basis.get_rotation_quaternion()*Quaternion(local_axis,angle))

func _find_rig(node:Node)->Skeleton3D:
	if node is Skeleton3D:return node
	for child:Node in node.get_children():
		var found:=_find_rig(child)
		if found!=null:return found
	return null
