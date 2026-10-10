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
var _wheel_radius := WHEEL_RADIUS
var _wheel_metadata: Array = []
var _rotor_metadata: Array = []
var _gesture := ""
static var _loop_libraries: Dictionary = {}
var _owned_sample: Array = []

## Metadata uses source meters; conversion occurs here exactly once.
func configure_animation(metadata: Dictionary) -> void:
	var radius: float = float(metadata.get("wheel_radius_m",.24))
	if is_finite(radius) and radius>0.0: _wheel_radius = radius/16.0
	_wheel_metadata = metadata.get("wheels",[]).duplicate(true)
	_rotor_metadata = metadata.get("rotors",[]).duplicate(true)

func set_gait_phase(phase: float) -> void:
	if not is_finite(phase): return
	_gait_phase = fposmod(phase,1.0)
	_update_gait()
	if _player != null and _clip in ["walk","run"]:
		_player.seek(_gait_phase*_player.current_animation_length,true)

func play_gesture(name: StringName) -> bool:
	if name != &"wave" or _airborne or absf(_speed)>.0001: return false
	if _player == null or not _player.has_animation(name): return false
	_gesture = String(name)
	_clip = _gesture
	_player.play(name,.12)
	_player.advance(0.0)
	return true

func debug_state() -> Dictionary:
	return {"speed":_speed,"steering":_steering,"airborne":_airborne,
		"wheel_phase":_wheel_phase,"gait_phase":_gait_phase,"clip":_clip,
		"animation_position":_player.current_animation_position if _player != null else 0.0,
		"main_rotor_phase":_main_rotor.rotation.y if _main_rotor != null else 0.0,
		"tail_rotor_phase":_tail_rotor.rotation.x if _tail_rotor != null else 0.0,
		"wheel_phases":_part_phases(_wheel_metadata,true),
		"rotor_phases":_part_phases(_rotor_metadata,false)}

func _part_phases(entries: Array, wheel: bool) -> Dictionary:
	var phases := {}
	for entry: Dictionary in entries:
		var name: String = entry.get("node","")
		var part := find_child(name,true,false) as Node3D
		var axis := _axis_index(String(entry.get("axis","X" if wheel else "Y")))
		if part == null or axis<0: continue
		if wheel:
			var spin := _wheel_spin(part)
			if spin != null: part = spin
		phases[name] = part.rotation[axis]
	return phases

## Godot may uniquify repeated glTF names (Spin2, Spin_2, Spin.002).
## Resolve only an exact local child or one unambiguous numeric import suffix.
func _wheel_spin(wheel: Node3D) -> Node3D:
	var exact := wheel.get_node_or_null("Spin") as Node3D
	if exact != null: return exact
	var match_node: Node3D
	for child in wheel.get_children():
		if not child is Node3D or not String(child.name).begins_with("Spin"): continue
		var suffix := String(child.name).trim_prefix("Spin")
		if suffix.begins_with("_") or suffix.begins_with("."): suffix=suffix.substr(1)
		if suffix.is_empty(): continue
		var numeric := true
		for character: int in suffix.to_ascii_buffer():
			if character<48 or character>57: numeric=false
		if not numeric: continue
		if match_node != null: return null
		match_node=child as Node3D
	return match_node

func _axis_index(axis: String) -> int:
	return {"X":0,"Y":1,"Z":2}.get(axis,-1)

func _advance_metadata(step: float, blend: float) -> void:
	for entry: Dictionary in _wheel_metadata:
		var wheel := find_child(String(entry.get("node","")),true,false) as Node3D
		var axis := _axis_index(String(entry.get("axis","X")))
		var radius: float = float(entry.get("radius_m",_wheel_radius*16.0))/16.0
		if wheel == null or axis<0 or not is_finite(radius) or radius<=0.0: continue
		var spin := _wheel_spin(wheel)
		if spin == null: spin = wheel
		spin.rotation[axis] = wrapf(spin.rotation[axis]-step*_speed/radius,-PI,PI)
		if entry.get("steer",false): wheel.rotation.y = lerpf(wheel.rotation.y,_steering*.45,blend)
	for entry: Dictionary in _rotor_metadata:
		var rotor := find_child(String(entry.get("node","")),true,false) as Node3D
		var axis := _axis_index(String(entry.get("axis","Y")))
		var rate: float = float(entry.get("radians_per_second",0.0))
		if rotor != null and axis>=0 and is_finite(rate):
			rotor.rotation[axis] = wrapf(rotor.rotation[axis]+step*rate,-PI,PI)

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
		# One immutable policy copy per imported library, shared by the pool.
		# Deep-copying dense animation clips for every actor wastes memory.
		for library_name in _player.get_animation_library_list():
			var original := _player.get_animation_library(library_name)
			var key := original.get_instance_id()
			if not _loop_libraries.has(key):
				var library := original.duplicate(true) as AnimationLibrary
				for clip in ["idle","walk","run"]:
					if library.has_animation(clip): library.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
				for clip in ["jump","wave"]:
					if library.has_animation(clip): library.get_animation(clip).loop_mode=Animation.LOOP_NONE
				_loop_libraries[key]={"original":original,"library":library}
			_player.remove_animation_library(library_name)
			_player.add_animation_library(library_name,_loop_libraries[key].library)
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
	if not _gesture.is_empty() and not _airborne and absf(_speed)<=.0001 and _player.is_playing(): return
	_gesture = ""
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
	_gait_phase = fposmod(_gait_phase+step*2.0*absf(_speed)/WALK_SPEED,1.0)
	_update_gait()
	if _player != null:
		var rate := 1.0
		if _clip == "walk": rate = absf(_speed)/WALK_SPEED
		elif _clip == "run": rate = absf(_speed)/RUN_SPEED
		_player.advance(step*rate)
		if not _gesture.is_empty() and not _player.is_playing(): _select_clip()
	var blend := 1.0-exp(-step*14.0)
	_wheel_phase = wrapf(_wheel_phase-step*_speed/_wheel_radius,-PI,PI)
	_advance_metadata(step,blend)
	if _wheels.size()==4 and _wheel_metadata.is_empty():
		# Forward is -Z, so rolling about +X is negative. Reverse unwinds it.
		for wheel in _wheels:
			var spin := _wheel_spin(wheel)
			if spin != null: spin.rotation.x = _wheel_phase
		for index in 2:
			_wheels[index].rotation.y = lerpf(_wheels[index].rotation.y,_steering*.45,blend)
	if _main_rotor != null and _rotor_metadata.is_empty():
		_main_rotor.rotation.y = wrapf(_main_rotor.rotation.y+step*24.0,-PI,PI)
	if _tail_rotor != null and _rotor_metadata.is_empty():
		_tail_rotor.rotation.x = wrapf(_tail_rotor.rotation.x+step*31.0,-PI,PI)

## Absolute owner clocks survive pool reassignment and demotion. Rendering may
## resample a changed pose but never adds time or advances an AnimationPlayer.
func sample_owned_state(state: Dictionary) -> void:
	var sample: Array=[state.get("id",""),state.speed,state.steering,state.airborne,state.phase,state.get("visual_time",0.0),state.get("distance",0.0),state.get("gesture",""),state.get("gesture_time",0.0)]
	if sample==_owned_sample: return
	_owned_sample=sample
	_speed=float(state.speed)
	_steering=float(state.steering)
	_airborne=bool(state.airborne)
	_gait_phase=fposmod(float(state.phase),1.0)
	_gesture=String(state.get("gesture",""))
	_update_gait()
	var clip := "wave" if _gesture=="wave" else "jump" if _airborne else "run" if absf(_speed)>.14 else "walk" if absf(_speed)>.0001 else "idle"
	if _player!=null and _player.has_animation(clip):
		if _clip!=clip:
			_clip=clip
			_player.play(clip,0.0)
		var length := _player.get_animation(clip).length
		var at := _gait_phase*length if clip in ["walk","run"] else fposmod(float(state.get("visual_time",0.0)),length)
		if clip=="wave": at=clampf(float(state.get("gesture_time",0.0))/1.5,0.0,1.0)*length
		_player.seek(at,true)
	var distance: float=float(state.get("distance",0.0))
	_wheel_phase=wrapf(-distance/_wheel_radius,-PI,PI)
	for entry: Dictionary in _wheel_metadata:
		var wheel := find_child(String(entry.node),true,false) as Node3D
		if wheel==null: continue
		var spin := _wheel_spin(wheel)
		if spin==null: spin=wheel
		spin.rotation[_axis_index(String(entry.axis))]=wrapf(-distance/(float(entry.get("radius_m",_wheel_radius*16.0))/16.0),-PI,PI)
		if entry.get("steer",false): wheel.rotation.y=_steering*.45
	for entry: Dictionary in _rotor_metadata:
		var rotor := find_child(String(entry.node),true,false) as Node3D
		if rotor!=null: rotor.rotation[_axis_index(String(entry.axis))]=wrapf(float(state.get("visual_time",0.0))*float(entry.get("radians_per_second",0.0)),-PI,PI)
