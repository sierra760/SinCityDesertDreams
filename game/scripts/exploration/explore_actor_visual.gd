# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Imported Blender motion, advanced exclusively by the exploration session.
class_name ExploreActorVisual
extends Node3D

# Authored tires have a .24 metre radius; one tile is sixteen metres.
const WHEEL_RADIUS := .24 / 16.0
const WALK_SPEED := .09
const RUN_SPEED := .20
var _player: AnimationPlayer
var _clip := ""
var _main_rotor: Node3D
var _tail_rotor: Node3D
var _wheels: Array[Node3D] = []
var _speed := 0.0
var _steering := 0.0
var _airborne := false
var _wheel_phase := 0.0
const CROWD_GAIT := preload("res://scripts/exploration/explore_crowd_gait.gdshader")
var _crowd: MeshInstance3D
var _crowd_materials: Array[ShaderMaterial] = []
var _gait_phase := 0.0

## Reuse the crowd mesh with local gait materials. Session ticks supply the
## phase; the shared ambient meshes, materials and batch data are not modified.
func configure_crowd_variant(variant: int) -> void:
	var mesh := CityTrafficCatalog.mesh_for(&"pedestrian",variant)
	var bounds := mesh.get_aabb()
	var reach := maxf(maxf(absf(bounds.position.x),absf(bounds.end.x)),maxf(absf(bounds.position.z),absf(bounds.end.z)))
	var fit := minf(1.0,minf(.018/maxf(reach,.000001),.115/maxf(bounds.size.y,.000001)))
	_crowd = MeshInstance3D.new()
	_crowd.name = "CrowdPedestrian"
	_crowd.mesh = mesh
	_crowd.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*fit),Vector3(0,-bounds.position.y*fit,0))
	for surface: int in mesh.get_surface_count():
		var original := mesh.surface_get_material(surface) as ShaderMaterial
		var material := ShaderMaterial.new()
		material.shader = CROWD_GAIT
		material.set_shader_parameter("tint",original.get_shader_parameter("tint"))
		_crowd_materials.append(material)
		_crowd.set_surface_override_material(surface,material)
	add_child(_crowd)
	_update_gait()

func _update_gait() -> void:
	if _crowd == null: return
	var moving := 0.0 if _airborne else clampf(absf(_speed)/WALK_SPEED,0,1)
	for material: ShaderMaterial in _crowd_materials:
		material.set_shader_parameter("phase",_gait_phase)
		material.set_shader_parameter("movement",moving)

func _ready() -> void:
	var players := find_children("*","AnimationPlayer",true,false)
	if not players.is_empty():
		_player = players[0] as AnimationPlayer
		_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		# glTF has no loop flag. Keep clip policy local to this actor instance.
		for library_name in _player.get_animation_library_list():
			var library := _player.get_animation_library(library_name).duplicate(true) as AnimationLibrary
			_player.remove_animation_library(library_name)
			_player.add_animation_library(library_name,library)
		for clip in ["idle","walk","run"]:
			if _player.has_animation(clip): _player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		if _player.has_animation("jump"): _player.get_animation("jump").loop_mode = Animation.LOOP_NONE
		_select_clip()
	for joint in ["WheelFrontLeft","WheelFrontRight","WheelRearLeft","WheelRearRight"]:
		var wheel := find_child(joint,true,false) as Node3D
		if wheel != null: _wheels.append(wheel)
	_main_rotor = find_child("MainRotor",true,false) as Node3D
	_tail_rotor = find_child("TailRotor",true,false) as Node3D

func set_motion(speed: float, steering: float, airborne: bool) -> void:
	_speed = clampf(speed,-4.0,4.0) if is_finite(speed) else 0.0
	_steering = clampf(steering,-1.0,1.0) if is_finite(steering) else 0.0
	_airborne = airborne
	_update_gait()
	_select_clip()

func _select_clip() -> void:
	if _player == null: return
	var wanted := "idle"
	if _airborne: wanted = "jump"
	elif absf(_speed)>.14: wanted = "run"
	elif absf(_speed)>.0001: wanted = "walk"
	if wanted == _clip or not _player.has_animation(wanted): return
	var blend := .12 if not _clip.is_empty() else 0.0
	_clip = wanted
	_player.play(wanted,blend)
	_player.advance(0.0)

func advance_visual(delta: float) -> void:
	if not is_finite(delta): return
	var step := clampf(delta,0.0,.1)
	if step<=0.0: return
	if _crowd != null:
		_gait_phase = fposmod(_gait_phase+step*2.0*absf(_speed)/WALK_SPEED,1.0)
		_update_gait()
	if _player != null:
		var rate := 1.0
		if _clip == "walk": rate = absf(_speed)/WALK_SPEED
		elif _clip == "run": rate = absf(_speed)/RUN_SPEED
		_player.advance(step*rate)
	var blend := 1.0-exp(-step*14.0)
	if _wheels.size()==4:
		# Forward is -Z, so rolling about +X is negative. Reverse unwinds it.
		_wheel_phase = wrapf(_wheel_phase-step*_speed/WHEEL_RADIUS,-PI,PI)
		for wheel in _wheels:
			var spin := wheel.get_node_or_null("Spin") as Node3D
			if spin != null: spin.rotation.x = _wheel_phase
		for index in 2:
			_wheels[index].rotation.y = lerpf(_wheels[index].rotation.y,_steering*.45,blend)
	if _main_rotor != null:
		_main_rotor.rotation.y = wrapf(_main_rotor.rotation.y+step*24.0,-PI,PI)
	if _tail_rotor != null:
		_tail_rotor.rotation.x = wrapf(_tail_rotor.rotation.x+step*31.0,-PI,PI)
