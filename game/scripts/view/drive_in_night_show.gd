# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Drive-in theaters at night: a public domain Western on every screen and
## moviegoers' cars parked in the rows. Explore can take any of those cars.
## Everything here sits outside the batcher's source hierarchy and exists only
## while night mode is on. No city state, save data or game RNG: which spaces
## are filled, and by what, follows from each lot's position alone.
class_name DriveInNightShow
extends Node3D

const SHADER := preload("res://shaders/drive_in_screen.gdshader")
const FILM := "res://assets/drive-in/the-great-train-robbery.ogv"
## The film is 4:3; the authored screen is wider, so it is centred on it.
const FILM_ASPECT := 4.0/3.0
## Model metres, +Z frontage. The screen's front face, centre and height.
const SCREEN_CENTRE := Vector3(0.0,13.25,-14.80)
const SCREEN_HEIGHT := 17.7
## The sand slab top, which is also the collision floor.
const GRADE := .2
## Where a car may move on the lot: all of it in front of the screen, up to
## the open frontage. The snack bar, sign and screen still collide.
const APRON := Rect2(-23.9,-14.5,47.8,38.6)
## Three rows of six spaces facing the screen. The second and third rows pull
## up behind the authored speaker posts; the centre lane stays clear.
const COLUMNS: Array[float] = [-12.0,-8.6,-5.2,5.2,8.6,12.0]
const ROWS: Array[float] = [-9.0,0.0,7.1]
const KINDS: Array[StringName] = [&"car",&"sedan",&"compact",&"pickup",&"car",&"sedan",&"compact"]
## About two spaces in three are taken on any night.
const OCCUPANCY := 68

var _view: Node
var _player: VideoStreamPlayer
var _screens: Array[ShaderMaterial] = []
## Tile cell -> slots, for nearest(); same layout as CityServiceParking.
var _cells: Dictionary = {}
## slot_key -> true for cars driven away in Explore. A rebuilt show leaves
## those spaces empty until release_claims().
var _claimed: Dictionary = {}
var _built_from: Array = []
static var _parked_meshes: Dictionary = {}

static func code() -> int:
	return Buildings.id_of(&"com_drive_in")

static func slot_key(anchor: Vector2i, index: int) -> String:
	return "%d,%d:%d" % [anchor.x,anchor.y,index]

## A small integer hash of the lot and space; stable across sessions.
static func _mix(anchor: Vector2i, index: int, salt: int) -> int:
	var h := (anchor.x*73856093) ^ (anchor.y*19349663) ^ (index*83492791) ^ (salt*2654435761)
	h = (h ^ (h >> 13))*1274126177
	return posmod(h ^ (h >> 16),1 << 30)

static func occupied(anchor: Vector2i, index: int) -> bool:
	return _mix(anchor,index,1)%100 < OCCUPANCY

static func kind_at(anchor: Vector2i, index: int) -> StringName:
	return KINDS[_mix(anchor,index,2)%KINDS.size()]

## Model-metre position of each space (row-major, front row first).
static func spaces() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: float in ROWS:
		for column: float in COLUMNS:
			out.append({"position":Vector2(column,row)})
	return out

func bind(view: Node) -> void:
	_view = view
	if "buildings" in view and view.buildings != null:
		view.buildings.visibility_changed.connect(_sync_visibility)
	_sync_visibility()

func _sync_visibility() -> void:
	visible = _view != null and "buildings" in _view and _view.buildings != null and _view.buildings.visible
	if is_instance_valid(_player): _player.paused = not visible

func rebuild() -> void:
	_clear_lots()
	_built_from = _signature()
	for lot: Node3D in _lots(): _add_lot(lot)
	# A new or replaced drive-in joins the reel already showing.
	if _screens.is_empty(): _stop_film()
	elif not is_instance_valid(_player): _start_film()
	else:
		for material: ShaderMaterial in _screens: material.set_shader_parameter("film",_player.get_video_texture())
	_sync_visibility()

## Rebuild only if a drive-in lot was added, removed or replaced. Returns true
## when it rebuilt.
func refresh() -> bool:
	if _signature() == _built_from:
		_sync_visibility()
		return false
	rebuild()
	return true

func clear() -> void:
	_clear_lots()
	_stop_film()

func _clear_lots() -> void:
	_built_from = []
	_cells.clear()
	_screens.clear()
	for child: Node in get_children():
		if child != _player: child.free()

func _stop_film() -> void:
	if is_instance_valid(_player): _player.free()
	_player = null

func _lots() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _view == null or not ("buildings" in _view) or _view.buildings == null: return out
	var wanted := code()
	for lot: Node in _view.buildings.get_children():
		if lot is Node3D and int(lot.get_meta("code",-1)) == wanted and not lot.get_meta("missing_model",false):
			out.append(lot)
	return out

func _signature() -> Array:
	var out: Array = []
	for lot: Node3D in _lots(): out.append_array([lot.get_instance_id(),lot.global_transform])
	return out

# --- the picture ------------------------------------------------------------

## One decoder serves every screen. It plays hidden: only its texture is used.
func _start_film() -> void:
	if not ResourceLoader.exists(FILM): return
	_player = VideoStreamPlayer.new()
	_player.name = "Projector"
	_player.stream = load(FILM)
	_player.loop = true
	_player.visible = false
	_player.volume_db = -80.0
	add_child(_player)
	# A player outside the tree ignores play(); start it when it enters.
	if _player.is_inside_tree(): _player.play()
	else: _player.ready.connect(_player.play,CONNECT_ONE_SHOT)
	var texture := _player.get_video_texture()
	for material: ShaderMaterial in _screens: material.set_shader_parameter("film",texture)

func is_playing() -> bool:
	return is_instance_valid(_player) and _player.is_playing() and not _player.paused

func film_texture() -> Texture2D:
	return _player.get_video_texture() if is_instance_valid(_player) else null

func screen_count() -> int:
	return _screens.size()

# --- the cars -----------------------------------------------------------------

func _add_lot(lot: Node3D) -> void:
	var anchor: Vector2i = lot.get_meta("cell",Vector2i.ZERO)
	var wrapper := Node3D.new()
	wrapper.name = "DriveIn_%d_%d" % [anchor.x,anchor.y]
	add_child(wrapper)
	wrapper.global_transform = lot.global_transform
	wrapper.set_meta("driveway",{"city":_view.city if "city" in _view else null,"anchor":anchor,"code":code(),
		"transform":lot.global_transform,"apron":Rect2(APRON.position/16.0,APRON.size/16.0),"grade":GRADE/16.0})
	var quad := QuadMesh.new()
	quad.size = Vector2(SCREEN_HEIGHT*FILM_ASPECT,SCREEN_HEIGHT)/16.0
	var material := ShaderMaterial.new()
	material.shader = SHADER
	quad.material = material
	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	screen.mesh = quad
	screen.position = SCREEN_CENTRE/16.0
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	wrapper.add_child(screen)
	_screens.append(material)
	var list := spaces()
	for index: int in list.size():
		if not occupied(anchor,index): continue
		var slot := _add_car(wrapper,kind_at(anchor,index),list[index].position,(float(_mix(anchor,index,3)%7)-3.0)*.012)
		slot.name = "Space%d" % index
		slot.set_meta("index",index)
		slot.set_meta("anchor",anchor)
		slot.set_meta("drive_in",true)
		if _claimed.has(slot_key(anchor,index)): _apply_claim(slot,true)
		var cell := Vector2i(floori(slot.global_position.x),floori(slot.global_position.z))
		if not _cells.has(cell): _cells[cell] = []
		_cells[cell].append(slot)

func _add_car(parent: Node3D, kind: StringName, at: Vector2, yaw: float) -> Node3D:
	var size := CityTrafficCatalog.dimensions(kind)
	var slot := Node3D.new()
	slot.position = Vector3(at.x,GRADE,at.y)/16.0
	# Vehicle meshes face -Z: toward the screen.
	slot.rotation.y = yaw
	slot.set_meta("kind",kind)
	parent.add_child(slot)
	var mesh := MeshInstance3D.new()
	mesh.name = "Vehicle"
	mesh.mesh = parked_mesh(kind)
	slot.add_child(mesh)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = CityModelCatalog.SHELL_LAYER
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position.y = size.y*.5
	body.add_child(collider)
	slot.add_child(body)
	return slot

## The traffic mesh with its lamps switched off: moviegoers keep their lights
## out. Lamp copies are renamed so night mode never relights them.
static func parked_mesh(kind: StringName) -> Mesh:
	if _parked_meshes.has(kind): return _parked_meshes[kind]
	var source := CityTrafficCatalog.mesh_for(kind)
	if source == null: return null
	var mesh := source.duplicate() as ArrayMesh
	for surface: int in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as BaseMaterial3D
		if material == null: continue
		var role := CityNightMode.role_for(material.resource_name)
		if role not in [CityNightMode.Role.HEADLIGHT,CityNightMode.Role.TAILLIGHT,CityNightMode.Role.INDICATOR]: continue
		var dark := material.duplicate() as BaseMaterial3D
		dark.resource_name = "parked lamp"
		dark.emission_enabled = false
		mesh.surface_set_material(surface,dark)
	_parked_meshes[kind] = mesh
	return mesh

# --- Explore --------------------------------------------------------------------

## {"service": slot, "gap": metres} for the nearest parked car within reach.
func nearest(feet: Vector3, reach: float) -> Dictionary:
	if not visible: return {}
	return CityServiceParking.nearest_in(_cells,feet,reach)

func driveway(slot: Node3D) -> Dictionary:
	return slot.get_parent().get_meta("driveway",{}) if is_instance_valid(slot) else {}

## Taking a car empties its space for the rest of the visit, even if night
## falls again or the show is rebuilt.
func set_claimed(slot: Node3D, claimed: bool) -> void:
	if not is_instance_valid(slot): return
	var key := slot_key(slot.get_meta("anchor"),slot.get_meta("index"))
	if claimed: _claimed[key] = true
	else: _claimed.erase(key)
	_apply_claim(slot,claimed)

func _apply_claim(slot: Node3D, claimed: bool) -> void:
	slot.set_meta("claimed",claimed)
	(slot.get_node("Body") as StaticBody3D).collision_layer = 0 if claimed else CityModelCatalog.SHELL_LAYER
	(slot.get_node("Vehicle") as Node3D).visible = not claimed

## Leaving Explore parks every taken car back in its space.
func release_claims() -> void:
	_claimed.clear()
	for slots: Array in _cells.values():
		for slot: Node3D in slots: _apply_claim(slot,false)

func parked_slots() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for slots: Array in _cells.values():
		for slot: Node3D in slots: out.append(slot)
	return out
