# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Night mode for the 3D city: full-moon light, a moonlit Explore sky, glow, lit
## windows, neon, vehicle lamps and street-lamp pools. Presentation only. It
## never reads or writes city data, saves or any random stream the game uses.
##
## Day is the untouched original: at amount 0 every material and environment
## property it changed is restored, and its shader terms multiply by zero.
class_name CityNightMode
extends Node

const Globals := preload("res://scripts/view/city_night_globals.gd")
const FADE_SECONDS := 1.5

## Material roles, found by material name in the authored models.
enum Role { NONE, WINDOW, WINDOW_DIM, NEON, SIGN, HEADLIGHT, TAILLIGHT, INDICATOR, STREET_LAMP }
const ROLE_NAMES := {
	"glass": Role.WINDOW, "glass_light": Role.WINDOW, "resort_glass": Role.WINDOW,
	"glass_dark": Role.WINDOW_DIM,
	"sign_neon_amber": Role.NEON, "sign_neon_ivory": Role.NEON, "sign_neon_teal": Role.NEON,
	"resort_lamp": Role.NEON, "warm_light": Role.NEON,
	"sign_ivory": Role.SIGN, "sign_gold": Role.SIGN, "sign_teal": Role.SIGN, "sign_coral": Role.SIGN,
	"sign_teal_enamel": Role.SIGN, "sign_teal_face": Role.SIGN, "resort_sign": Role.SIGN,
	"traffic_light": Role.HEADLIGHT, "Ivory lamp": Role.HEADLIGHT,
	"Red lamp": Role.TAILLIGHT, "Amber lamp": Role.INDICATOR,
	"street_lamp_glow": Role.STREET_LAMP,
}
## Emission energy at full night for each role (NEON scales its own energy).
const ENERGY := {Role.WINDOW: 1.6, Role.WINDOW_DIM: .6, Role.NEON: 2.4, Role.SIGN: .85,
	Role.HEADLIGHT: 2.6, Role.TAILLIGHT: 1.8, Role.INDICATOR: 1.1, Role.STREET_LAMP: 3.2}
const WINDOW_WARMTH := Color(1.0,.80,.52)
## World-space window cells: about two metres wide and one storey tall.
const WINDOW_SCALE := Vector3(1.0/(8.0*.125),1.0/(8.0*.21),1.0/(8.0*.125))
## Resort halls (render layer 21) keep their own interior lighting.
const INTERIOR_LAYER := 1 << 20

const DAY_BACKGROUND := Color(0.16,0.22,0.27)
const NIGHT_BACKGROUND := Color(0.025,0.035,0.075)
## A full moon over the desert: bright enough for silver-blue shadows.
const MOON := Color(0.68,0.76,1.0)
const NIGHT_AMBIENT := Color(0.56,0.64,0.95)
const SUN_NIGHT_SCALE := .40
const AMBIENT_NIGHT_SCALE := .42

signal changed(enabled: bool)

var enabled := false
## 0 by day, 1 at night; fades between them over FADE_SECONDS.
var amount := 0.0
var _view: Node
## Material instance id -> {"material", "role", "saved"}.
var _prepared: Dictionary = {}
var _pending: Array[Node] = []
var _watching := false
var _night_sky: Sky
var _applied_explore: Environment
var _applied_amount := -1.0

static var _window_texture: ImageTexture
static var _star_texture: ImageTexture
## Materials currently carrying night emission, across all views. The model
## cache must not persist them in this state.
static var _modified_count := 0

static func materials_modified() -> bool:
	return _modified_count > 0

func bind(view: Node) -> void:
	_view = view
	Globals.ensure()

## Turn night on or off. `instant` skips the dusk/dawn fade.
func set_enabled(on: bool, instant: bool = false) -> void:
	if on != enabled:
		enabled = on
		changed.emit(on)
	if instant: _set_amount(1.0 if on else 0.0)
	set_process(true)

func is_transitioning() -> bool:
	return amount != (1.0 if enabled else 0.0)

func _ready() -> void:
	set_process(true)

func _exit_tree() -> void:
	_set_amount(0.0)
	_watch(false)

func _process(delta: float) -> void:
	var target := 1.0 if enabled else 0.0
	if amount != target:
		var step := delta/FADE_SECONDS if delta > 0.0 else 0.0
		_set_amount(move_toward(amount,target,step))
	elif not _pending.is_empty():
		_prepare_pending()
	# Mods and Explore entry replace the camera environment; restate night.
	var explore := _explore_environment()
	if explore != null and explore != _applied_explore and (amount > 0.0 or _applied_explore != null):
		_apply_environment()
	if amount == target and _pending.is_empty() and amount == 0.0: set_process(false)

func _set_amount(value: float) -> void:
	value = clampf(value,0.0,1.0)
	if value > 0.0 and amount == 0.0:
		_watch(true)
		_collect(_world())
	amount = value
	_prepare_pending()
	Globals.set_night(amount)
	_apply_environment()
	for record: Dictionary in _prepared.values(): _apply_material(record)
	if amount == 0.0:
		_restore_all()
		_watch(false)
	_applied_amount = amount

## Night-related lighting factors for RenderQuality.
func sun_scale() -> float: return lerpf(1.0,SUN_NIGHT_SCALE,amount)
func ambient_scale() -> float: return lerpf(1.0,AMBIENT_NIGHT_SCALE,amount)

func _world() -> Node:
	return _view.world if _view != null and "world" in _view else null

func _explore_environment() -> Environment:
	if _view == null or not _view.has_method("exploration_camera"): return null
	var camera: Camera3D = _view.exploration_camera()
	return camera.environment if is_instance_valid(camera) else null

# --- lighting -------------------------------------------------------------

func _apply_environment() -> void:
	var world := _world()
	if world == null: return
	var mobile := RenderingServer.get_current_rendering_method() == "mobile"
	for child: Node in world.get_children():
		if child is DirectionalLight3D:
			var sun := child as DirectionalLight3D
			sun.light_color = Color.WHITE.lerp(MOON,amount)
			sun.light_energy = (0.7 if mobile else 0.325)*sun_scale()
			for part: Node in sun.get_children():
				if part is DirectionalLight3D and part.sky_mode == DirectionalLight3D.SKY_MODE_SKY_ONLY:
					# The sky's sun disc becomes the full moon.
					part.light_color = Color(1.0,.96,.88).lerp(Color(.94,.96,1.0),amount)
					part.light_energy = lerpf(1.0,.9,amount)
		elif child is WorldEnvironment and child.environment != null:
			var environment: Environment = child.environment
			environment.background_color = DAY_BACKGROUND.lerp(NIGHT_BACKGROUND,amount)
			_apply_shared(environment,mobile)
	var explore := _explore_environment()
	if explore != null:
		_apply_shared(explore,mobile)
		if amount > 0.0:
			if _night_sky == null: _night_sky = _make_night_sky()
			_tint_sky(_night_sky)
			explore.sky = _night_sky
		elif _night_sky != null and explore.sky == _night_sky:
			explore.sky = preload("res://assets/environment/desert_day_sky.tres")
		_applied_explore = explore if amount > 0.0 else null

func _apply_shared(environment: Environment, mobile: bool) -> void:
	# A mod's daylight preset owns ambient colour by day; night tints it.
	if not environment.has_meta(&"night_day_ambient"):
		environment.set_meta(&"night_day_ambient",environment.ambient_light_color)
	var day_ambient: Color = environment.get_meta(&"night_day_ambient")
	environment.ambient_light_color = day_ambient.lerp(day_ambient*NIGHT_AMBIENT,amount)
	environment.ambient_light_energy = (0.4 if mobile else 0.195)*ambient_scale()
	if amount == 0.0: environment.remove_meta(&"night_day_ambient")
	environment.glow_enabled = amount > 0.0
	if amount > 0.0:
		environment.glow_intensity = .75*amount
		environment.glow_strength = 1.0
		environment.glow_bloom = 0.0
		environment.glow_hdr_threshold = .9
		environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		for level: int in 7: environment.set_glow_level(level,1.0 if level in [1,2,3,4] else 0.0)

func _make_night_sky() -> Sky:
	var day: Sky = preload("res://assets/environment/desert_day_sky.tres")
	var sky := day.duplicate(true) as Sky
	var material := sky.sky_material as ProceduralSkyMaterial
	if material != null:
		material.resource_name = "Nevada night"
		material.sky_cover = star_texture()
	return sky

func _tint_sky(sky: Sky) -> void:
	var material := sky.sky_material as ProceduralSkyMaterial
	var day := preload("res://assets/environment/desert_day_sky.tres").sky_material as ProceduralSkyMaterial
	if material == null or day == null: return
	var t := amount
	# Moonlit sky: deep blue rather than black.
	material.sky_top_color = day.sky_top_color.lerp(Color(0.03,0.06,0.15),t)
	# The city's own glow warms just the horizon: the Las Vegas light dome.
	material.sky_horizon_color = day.sky_horizon_color.lerp(Color(0.20,0.15,0.20),t)
	material.sky_curve = lerpf(day.sky_curve,.06,t)
	material.ground_horizon_color = day.ground_horizon_color.lerp(Color(0.14,0.10,0.11),t)
	material.ground_bottom_color = day.ground_bottom_color.lerp(Color(0.03,0.025,0.03),t)
	material.sky_energy_multiplier = lerpf(day.sky_energy_multiplier,.8,t)
	material.sky_cover_modulate = Color(1,1,1,t)
	# A crisp lunar disc with a soft halo.
	material.sun_angle_max = lerpf(day.sun_angle_max,1.6,t)
	material.sun_curve = lerpf(day.sun_curve,.04,t)

# --- materials ------------------------------------------------------------

static func role_for(material_name: String) -> int:
	var base := material_name.get_slice(" • ",0).strip_edges()
	var dot := base.rfind(".")
	if dot > 0 and base.substr(dot+1).is_valid_int(): base = base.substr(0,dot)
	return int(ROLE_NAMES.get(base,Role.NONE))

func _watch(on: bool) -> void:
	if on == _watching or not is_inside_tree(): return
	_watching = on
	if on: get_tree().node_added.connect(_node_added)
	elif get_tree().node_added.is_connected(_node_added): get_tree().node_added.disconnect(_node_added)

func _node_added(node: Node) -> void:
	if node is GeometryInstance3D: _pending.append(node)
	set_process(true)

func _prepare_pending() -> void:
	if _pending.is_empty(): return
	var world := _world()
	var nodes := _pending
	_pending = []
	for node: Node in nodes:
		if is_instance_valid(node) and world != null and world.is_ancestor_of(node): _collect_instance(node)

func _collect(root: Node) -> void:
	if root == null: return
	if root is GeometryInstance3D: _collect_instance(root)
	for child: Node in root.get_children(): _collect(child)

func _collect_instance(node: Node) -> void:
	var instance := node as GeometryInstance3D
	if instance == null or instance.layers & INTERIOR_LAYER: return
	if instance.material_override != null: _consider(instance.material_override)
	var mesh: Mesh = null
	if instance is MeshInstance3D:
		mesh = (instance as MeshInstance3D).mesh
		for surface: int in (instance as MeshInstance3D).get_surface_override_material_count():
			_consider((instance as MeshInstance3D).get_surface_override_material(surface))
	elif instance is MultiMeshInstance3D and (instance as MultiMeshInstance3D).multimesh != null:
		mesh = (instance as MultiMeshInstance3D).multimesh.mesh
	if mesh != null:
		for surface: int in mesh.get_surface_count(): _consider(mesh.surface_get_material(surface))

func _consider(material: Material) -> void:
	var base := material as BaseMaterial3D
	if base == null or _prepared.has(base.get_instance_id()): return
	var role := role_for(base.resource_name)
	if role == Role.NONE: return
	var record := {"material":base,"role":role,"saved":_save(base)}
	_prepared[base.get_instance_id()] = record
	_modified_count += 1
	_setup(base,role,record.saved)
	_apply_material(record)

const _SAVED := ["emission_enabled","emission","emission_energy_multiplier","emission_operator","emission_texture",
	"uv1_triplanar","uv1_world_triplanar","uv1_scale","uv1_triplanar_sharpness"]

static func _save(material: BaseMaterial3D) -> Dictionary:
	var saved := {}
	for key: String in _SAVED: saved[key] = material.get(key)
	return saved

static func _setup(material: BaseMaterial3D, role: int, saved: Dictionary) -> void:
	match role:
		Role.WINDOW, Role.WINDOW_DIM:
			material.emission_enabled = true
			material.emission = WINDOW_WARMTH
			# Windows light by world position, so no two buildings match.
			# Glass has no other texture, so world triplanar only places these.
			if material.albedo_texture == null and material.normal_texture == null:
				material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				material.emission_texture = window_texture()
				material.uv1_triplanar = true
				material.uv1_world_triplanar = true
				material.uv1_scale = WINDOW_SCALE
				material.uv1_triplanar_sharpness = 8.0
		Role.NEON:
			material.emission_enabled = true
			if not bool(saved.emission_enabled) or material.emission == Color.BLACK:
				material.emission = material.albedo_color
		Role.HEADLIGHT:
			material.emission_enabled = true
			material.emission = Color(1.0,.93,.78)
		Role.TAILLIGHT:
			material.emission_enabled = true
			material.emission = Color(1.0,.12,.06)
		Role.INDICATOR:
			material.emission_enabled = true
			material.emission = Color(1.0,.55,.12)
		Role.STREET_LAMP:
			material.emission_enabled = true
			material.emission = Color(1.0,.82,.58)
		_:
			material.emission_enabled = true
			material.emission = material.albedo_color

func _apply_material(record: Dictionary) -> void:
	var material: BaseMaterial3D = record.material
	if not is_instance_valid(material): return
	var role: int = record.role
	if role == Role.NEON:
		var day: float = record.saved.emission_energy_multiplier if record.saved.emission_enabled else 0.0
		material.emission_energy_multiplier = lerpf(day,maxf(day,1.0)*float(ENERGY[role]),amount)
	else:
		material.emission_energy_multiplier = float(ENERGY[role])*amount

func _restore_all() -> void:
	for record: Dictionary in _prepared.values():
		var material: BaseMaterial3D = record.material
		if not is_instance_valid(material): continue
		for key: String in record.saved: material.set(key,record.saved[key])
	_modified_count -= _prepared.size()
	_prepared.clear()
	_pending.clear()

# --- textures -------------------------------------------------------------

## A tileable 8×8 block of windows: most lit warm, some cool or dark, with
## thin mullions and floor slabs. Fixed seed; never touches the game's RNG.
static func window_texture() -> ImageTexture:
	if _window_texture != null: return _window_texture
	var rng := RandomNumberGenerator.new()
	rng.seed = 6035223
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	for cy: int in 8:
		for cx: int in 8:
			var roll := rng.randf()
			var color := Color(0.04,0.04,0.05)
			if roll > .30:
				var bright := rng.randf_range(.55,1.0)
				var tint := Color(1.0,.92,.78) if roll < .82 else (Color(.72,.86,1.0) if roll < .93 else Color(.70,1.0,.90))
				color = tint*bright
			for py: int in 8:
				for px: int in 8:
					var frame := px == 0 or py == 0 or py == 7
					image.set_pixel(cx*8+px,cy*8+py,Color(color.r*.25,color.g*.25,color.b*.25) if frame else color)
	image.generate_mipmaps()
	_window_texture = ImageTexture.create_from_image(image)
	return _window_texture

## Equirectangular star field for the night sky's cover texture. Only the
## brighter stars: full moonlight washes out the faint ones.
static func star_texture() -> ImageTexture:
	if _star_texture != null: return _star_texture
	var rng := RandomNumberGenerator.new()
	rng.seed = 358949
	var width := 2048
	var height := 1024
	var image := Image.create(width,height,false,Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,0))
	for i: int in 1100:
		# Uniform over the upper sky; the lower half stays under the horizon.
		var y := int(acos(rng.randf_range(0.04,1.0))/PI*height)
		var x := rng.randi_range(0,width-1)
		var level := pow(rng.randf(),3.0)*.7+.25
		var tint := Color(1.0,.95,.85) if rng.randf() < .6 else Color(.80,.88,1.0)
		image.set_pixel(x,y,Color(tint.r,tint.g,tint.b,level))
		if level > .8 and x+1 < width: image.set_pixel(x+1,y,Color(tint.r,tint.g,tint.b,level*.5))
	_star_texture = ImageTexture.create_from_image(image)
	return _star_texture
