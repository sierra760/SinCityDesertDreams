# SPDX-License-Identifier: GPL-3.0-or-later
## Camera-local presentation. No Simulation, weather or global RNG access.
class_name ExploreEnvironmentService
extends RefCounted
const PRESETS := {"daylight":["day","dawn","dusk","night"],"haze":["clear","desert","fog"],"wind":["calm","breeze","gust"],"precipitation":["none","dust","rain"]}
const CAPS := {"high":512,"balanced":256,"performance":128}
var _view: CityView3D
var _camera: Camera3D
var _baseline: Environment
var _overrides: Dictionary = {}
var _winners: Dictionary = {}
var _suppressed: Dictionary = {}
var _effect: Environment
var _particles: MultiMeshInstance3D
var _indoors := false
var _phase := 0.0
var _quality := ""
var _dirty := true
## A rebuilt buffer needs its first pose even if active time is frozen.
var _particles_pose_dirty := false
var _particle_buffer := PackedFloat32Array()
var ownership_log: Array[Dictionary] = []

func bind(view: CityView3D, camera: Camera3D) -> void:
	restore()
	_view = view
	_camera = camera
	if is_instance_valid(camera) and camera.environment != null:
		_baseline = camera.environment.duplicate(true) as Environment
	_dirty = true

func apply(owner: String, priority: int, channel: String, preset: String, parameters: Dictionary) -> Dictionary:
	if not PRESETS.has(channel) or not preset in PRESETS[channel] or owner.is_empty(): return {"code":"invalid_argument"}
	for key in parameters:
		if key != "intensity" or not ExploreModApi._number(parameters[key]) or parameters[key] < 0 or parameters[key] > 1: return {"code":"invalid_argument"}
	if not is_instance_valid(_camera) or _baseline == null: return {"code":"unavailable"}
	var channels: Dictionary = _overrides.get(owner,{})
	channels[channel] = {"owner":owner,"priority":priority,"preset":preset,"parameters":parameters.duplicate(true)}
	_overrides[owner] = channels
	_resolve()
	return {"code":"ok"}

func _resolve() -> void:
	var winners: Dictionary = {}
	var owners := _overrides.keys()
	owners.sort()
	for owner: String in owners:
		for channel: String in _overrides[owner]:
			var request: Dictionary = _overrides[owner][channel]
			if not winners.has(channel) or request.priority > winners[channel].priority: winners[channel] = request
	var suppressed: Dictionary = {}
	for channel: String in PRESETS:
		var winner: String = winners.get(channel,{}).get("owner","")
		for owner: String in owners:
			if owner == winner or not _overrides[owner].has(channel): continue
			var identity := owner+":"+channel
			suppressed[identity] = winner
			if _suppressed.get(identity,"") != winner:
				if ownership_log.size() >= 128: ownership_log.pop_front()
				ownership_log.append({"owner":owner,"channel":channel,"winner":winner,"reason":"suppressed"})
	_suppressed = suppressed
	var precipitation_changed := _presentation(winners,"precipitation") != _presentation(_winners,"precipitation")
	var wind_changed := _presentation(winners,"wind") != _presentation(_winners,"wind")
	var lighting_changed := _presentation(winners,"daylight") != _presentation(_winners,"daylight") or _presentation(winners,"haze") != _presentation(_winners,"haze")
	_winners = winners.duplicate(true)
	if precipitation_changed: _dirty = true
	if wind_changed and is_instance_valid(_particles): _particles_pose_dirty = true
	if lighting_changed: _render_environment()
	var quality: String = _view.render_quality if is_instance_valid(_view) else "high"
	if _dirty or _particles_pose_dirty or quality != _quality:
		step(0,_indoors)

## Ownership/priority remain in _winners, but only effective presentation
## changes require engine work. Omitted intensity and explicit 1 are equal.
static func _presentation(winners: Dictionary, channel: String) -> Array:
	if not winners.has(channel): return []
	var request: Dictionary = winners[channel]
	return [request.preset,float(request.parameters.get("intensity",1.0))]

func clear_owner(owner: String) -> void:
	_overrides.erase(owner)
	_resolve()

func _intensity(channel: String) -> float:
	return float(_winners.get(channel,{}).get("parameters",{}).get("intensity",1.0))

func _preset(channel: String, fallback: String) -> String:
	return String(_winners.get(channel,{}).get("preset",fallback))

func _render_environment() -> void:
	if not is_instance_valid(_camera) or _baseline == null: return
	_effect = _baseline.duplicate(true) as Environment
	if not _indoors:
		if _winners.has("daylight"):
			var colors := {"day":Color.WHITE,"dawn":Color(1,.72,.52),"dusk":Color(.76,.55,.72),"night":Color(.25,.32,.52)}
			var energy := {"day":1.0,"dawn":.8,"dusk":.6,"night":.22}
			var preset := _preset("daylight","day")
			_effect.ambient_light_color = _baseline.ambient_light_color.lerp(colors[preset],_intensity("daylight"))
			_effect.background_energy_multiplier = lerpf(_baseline.background_energy_multiplier,energy[preset],_intensity("daylight"))
		if _winners.has("haze"):
			var preset := _preset("haze","clear")
			_effect.fog_enabled = preset != "clear"
			_effect.fog_light_color = Color(.72,.60,.43) if preset == "desert" else Color(.63,.70,.75)
			_effect.fog_density = (.045 if preset == "desert" else .12)*_intensity("haze")
	_camera.environment = _effect

func step(delta: float, indoors: bool) -> void:
	if not is_instance_valid(_camera): return
	if _indoors != indoors:
		_indoors = indoors
		_render_environment()
	var quality: String = _view.render_quality if is_instance_valid(_view) else "high"
	if quality != _quality:
		_quality = quality
		_dirty = true
	if _dirty:
		_rebuild_particles()
		_dirty = false
	if not is_instance_valid(_particles): return
	_particles.visible = not indoors
	if indoors: return
	# Pre-draw and suspended physics steps only refresh visibility. Reuse the
	# existing transforms until time advances or a new buffer needs its pose.
	if delta<=0 and not _particles_pose_dirty: return
	_phase += maxf(0,delta)
	var rain := _preset("precipitation","none") == "rain"
	var speed: float = {"calm":0.0,"breeze":.15,"gust":.45}[_preset("wind","calm")]
	var drift := _phase*speed*_intensity("wind")
	var fall := _phase*(1.2 if rain else .08)
	_particles.position.x = sin(_phase)*speed*_intensity("wind")*.05
	# One buffer write per frame; per-instance transform calls dominate otherwise.
	# Each TRANSFORM_3D instance is three basis rows with the origin last.
	var count := _particles.multimesh.instance_count
	if _particle_buffer.size() != count*12:
		_particle_buffer.resize(count*12)
		_particle_buffer.fill(0.0)
		for i in count:
			_particle_buffer[i*12] = 1.0
			_particle_buffer[i*12+5] = 1.0
			_particle_buffer[i*12+10] = 1.0
	for i in count:
		_particle_buffer[i*12+3] = fposmod(float(i)*.61803398875+drift,1.0)*2.0-1.0
		_particle_buffer[i*12+7] = fposmod(float(i)*.41421356237-fall,1.0)-.5
		_particle_buffer[i*12+11] = -.25-fposmod(float(i)*.73205080757,1.0)*1.8
	if count > 0: _particles.multimesh.buffer = _particle_buffer
	_particles_pose_dirty = false

func _rebuild_particles() -> void:
	if is_instance_valid(_particles): _particles.free()
	_particles = null
	_particles_pose_dirty = false
	var preset := _preset("precipitation","none")
	if preset == "none" or _intensity("precipitation") == 0: return
	_particles = MultiMeshInstance3D.new()
	_particles.name = "ExploreAtmosphere"
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_particles.multimesh = MultiMesh.new()
	_particles.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(.002,.035) if preset == "rain" else Vector2(.009,.009)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(.7,.8,.9,.45) if preset == "rain" else Color(.8,.65,.43,.32)
	quad.material = material
	_particles.multimesh.mesh = quad
	_particles.multimesh.instance_count = int(CAPS.get(_quality,512)*_intensity("precipitation"))
	_camera.add_child(_particles)
	_particles_pose_dirty = true

func restore() -> void:
	if is_instance_valid(_particles): _particles.free()
	_particles = null
	_particles_pose_dirty = false
	if is_instance_valid(_camera) and _baseline != null: _camera.environment = _baseline.duplicate(true) as Environment
	_overrides.clear()
	_winners.clear()
	_suppressed.clear()
	ownership_log.clear()
	_camera = null
	_view = null
	_baseline = null
	_effect = null
	_phase = 0
	_indoors = false
	_quality = ""
