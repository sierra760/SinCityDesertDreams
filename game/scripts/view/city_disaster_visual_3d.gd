# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Editable Blender incident art. Presentation owns no collision or simulation RNG.
class_name CityDisasterVisual3D
extends Node3D

const KINDS: Array[StringName] = [&"tornado", &"monster", &"hurricane", &"beam", &"riot"]
const METRES_PER_TILE := 16.0
const MODEL_ROOT := "res://assets/desert-dreams-disasters/"
## City presentation loads before an incident exists. Retain each authored
## resource only after first use, including fire's large vertex-motion atlases.
static var _fire_material: ShaderMaterial
static var _fire_playback: Animation
static var _model_scenes: Dictionary = {}
static var _fire_mesh: ArrayMesh
const MODELS := {
	&"tornado": MODEL_ROOT + "tornado.glb",
	&"monster": MODEL_ROOT + "monster.glb",
	&"hurricane": MODEL_ROOT + "hurricane.glb",
	&"beam": MODEL_ROOT + "beam.glb",
	&"riot": MODEL_ROOT + "riot.glb",
	&"plane": MODEL_ROOT + "plane.glb",
	&"fire": MODEL_ROOT + "fire.glb",
}
var kind: StringName
var _animation_player: AnimationPlayer
var _animation_name: StringName
var _phase := 0.0


static func fire_material() -> ShaderMaterial:
	if _fire_material == null:
		_fire_material = load(MODEL_ROOT + "fire.tres") as ShaderMaterial
	return _fire_material


static func fire_playback() -> Animation:
	if _fire_playback == null:
		_fire_playback = load(MODEL_ROOT + "fire-playback.tres") as Animation
	return _fire_playback


## Blender owns local bones, morphs and effect motion; the simulation owns this root.
func build(value: StringName) -> void:
	for child: Node in get_children(): child.free()
	_animation_player = null
	_animation_name = &""
	_phase = 0.0
	kind = value
	name = String(value).capitalize()
	if has_meta("authored_model"): remove_meta("authored_model")
	if has_meta("animation_clip"): remove_meta("animation_clip")
	set_process(false)
	if not MODELS.has(kind): return
	var model: Node3D = _build_fire() if kind == &"fire" else _model_scene(kind).instantiate()
	model.scale = Vector3.ONE / METRES_PER_TILE
	add_child(model)
	set_meta("authored_model", MODEL_ROOT + String(kind) + ".glb")
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty(): return
	_animation_player = players[0] as AnimationPlayer
	for clip: StringName in _animation_player.get_animation_list():
		if clip == &"RESET": continue
		_animation_name = clip
		break
	if _animation_name == &"": return
	_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_animation_player.play(_animation_name)
	set_meta("animation_clip", _animation_name)
	if is_inside_tree(): _animation_player.advance(0.0)
	set_process(true)


func _ready() -> void:
	if _animation_player != null:
		_animation_player.advance(0.0)
		set_animation_phase(_phase)


## Deterministic per-location phase prevents rows of fires from moving in unison.
## This changes playback only and never modifies shared mesh/animation resources.
func set_animation_phase(value: float) -> void:
	if not is_finite(value): return
	_phase = fposmod(value, 1.0)
	if _animation_player == null or not is_inside_tree() or _animation_name == &"": return
	var animation := _animation_player.get_animation(_animation_name)
	_animation_player.seek(_phase * animation.length, true)


func _process(delta: float) -> void:
	if _animation_player != null and is_finite(delta) and delta >= 0.0:
		_animation_player.advance(delta)


static func _model_scene(value: StringName) -> PackedScene:
	if not _model_scenes.has(value):
		_model_scenes[value] = load(MODELS[value]) as PackedScene
	return _model_scenes[value]


## Fire's Blender vertex timeline bypasses Compatibility transform-feedback stalls.
## Geometry and atlas textures are shared; each material holds only its own time.
func _build_fire() -> Node3D:
	if _fire_mesh == null:
		var source: Node3D = _model_scene(&"fire").instantiate()
		var source_mesh: Mesh = (source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		_fire_mesh = ArrayMesh.new()
		for surface in source_mesh.get_surface_count():
			var arrays := source_mesh.surface_get_arrays(surface)
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
			_fire_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		source.free()
	var model := Node3D.new()
	var surface := MeshInstance3D.new()
	surface.name = "FireSurface"
	surface.mesh = _fire_mesh
	surface.material_override = fire_material().duplicate() as ShaderMaterial
	surface.custom_aabb = fire_material().get_meta("motion_bounds") as AABB
	model.add_child(surface)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	library.add_animation(&"Incident_loop", fire_playback())
	player.add_animation_library(&"", library)
	model.add_child(player)
	return model
