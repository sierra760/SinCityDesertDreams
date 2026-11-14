# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Drive-in theaters at night: a public domain Western on every screen,
## moviegoers' cars parked in the rows and people watching from the chairs.
## Explore can take any of those cars. Everything here sits outside the
## batcher's source hierarchy and exists only while night mode is on. No city
## state, save data or game RNG: which spaces and chairs are filled, and by
## what, follows from each lot's position alone.
##
## It is built to cost almost nothing: one batched draw per car make and per
## moviegoer figure across every drive-in, and a single film decoder that
## runs only while a screen is on camera.
class_name DriveInNightShow
extends Node3D

const SHADER := preload("res://shaders/drive_in_screen.gdshader")
const FILM := "res://assets/drive-in/the-great-train-robbery.ogv"
## Crowd figures posed sitting, baked by tools/bake_drive_in_audience.gd.
const AUDIENCE_LIBRARY := "res://assets/drive-in/moviegoers.res"
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
## The authored chairs: two rows of six each side of the centre lane. The
## seat top is 0.84 m with the backrest on the +Z side, so sitters face the
## screen. Z is the middle of the seat.
const CHAIR_COLUMNS: Array[float] = [-12.5,-10.9,-9.3,-7.7,-6.1,-4.5,4.5,6.1,7.7,9.3,10.9,12.5]
const CHAIR_ROWS: Array[float] = [-3.31,3.89]
const SEAT_TOP := .84
## A little over half the chairs are taken.
const AUDIENCE := 55

var _view: Node
var _player: VideoStreamPlayer
var _screens: Array[ShaderMaterial] = []
## Tile cell -> slots, for nearest(); same layout as CityServiceParking.
var _cells: Dictionary = {}
## slot_key -> true for cars driven away in Explore. A rebuilt show leaves
## those spaces empty until release_claims().
var _claimed: Dictionary = {}
var _built_from: Array = []
## Screens currently inside a camera's view; the film decodes only then.
var _screens_on_camera := 0
## Make -> [{"slot", "transform"}] and figure -> [Transform3D], collected per
## rebuild and drawn as one MultiMesh each.
var _car_places: Dictionary = {}
var _audience: Dictionary = {}
## Waiting for the audience library to finish loading in the background.
var _awaiting_audience := false
static var _parked_meshes: Dictionary = {}
static var _seated_meshes: Dictionary = {}
static var _library: MeshLibrary

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
	_sync_film()

## Decode only while some screen can actually be seen.
func _sync_film() -> void:
	if is_instance_valid(_player): _player.paused = not (visible and _screens_on_camera > 0)

func _screen_seen(on: bool) -> void:
	_screens_on_camera = maxi(_screens_on_camera+(1 if on else -1),0)
	_sync_film()

func rebuild() -> void:
	_clear_lots()
	_built_from = _signature()
	for lot: Node3D in _lots(): _add_lot(lot)
	_draw_cars()
	_draw_audience()
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
	_car_places.clear()
	_audience.clear()
	_awaiting_audience = false
	_screens_on_camera = 0
	set_process(false)
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
	_sync_film()
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
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.name = "OnCamera"
	notifier.aabb = AABB(Vector3(-quad.size.x*.5,-quad.size.y*.5,-.001),Vector3(quad.size.x,quad.size.y,.002))
	notifier.screen_entered.connect(_screen_seen.bind(true))
	notifier.screen_exited.connect(_screen_seen.bind(false))
	screen.add_child(notifier)
	var list := spaces()
	for index: int in list.size():
		if not occupied(anchor,index): continue
		var slot := _add_car(wrapper,kind_at(anchor,index),list[index].position,(float(_mix(anchor,index,3)%7)-3.0)*.012)
		slot.name = "Space%d" % index
		slot.set_meta("index",index)
		slot.set_meta("anchor",anchor)
		slot.set_meta("drive_in",true)
		var kind: StringName = slot.get_meta("kind")
		if not _car_places.has(kind): _car_places[kind] = []
		_car_places[kind].append(slot)
		var cell := Vector2i(floori(slot.global_position.x),floori(slot.global_position.z))
		if not _cells.has(cell): _cells[cell] = []
		_cells[cell].append(slot)
	var chair := 0
	for row: float in CHAIR_ROWS:
		for column: float in CHAIR_COLUMNS:
			chair += 1
			if _mix(anchor,chair,4)%100 >= AUDIENCE: continue
			var figure := _mix(anchor,chair,5)%CityTrafficCatalog.pedestrian_variants()
			# The pelvis rests a little above the cushion, toward the backrest.
			var at := lot.global_transform*Transform3D(Basis.IDENTITY,Vector3(column,SEAT_TOP+.10,row+.06)/16.0)
			if not _audience.has(figure): _audience[figure] = []
			_audience[figure].append(at)

func _add_car(parent: Node3D, kind: StringName, at: Vector2, yaw: float) -> Node3D:
	var size := CityTrafficCatalog.dimensions(kind)
	var slot := Node3D.new()
	slot.position = Vector3(at.x,GRADE,at.y)/16.0
	# Vehicle meshes face -Z: toward the screen.
	slot.rotation.y = yaw
	slot.set_meta("kind",kind)
	parent.add_child(slot)
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

## One MultiMesh per make holds every parked car of that make in the city.
func _draw_cars() -> void:
	for kind: StringName in _car_places:
		var slots: Array = _car_places[kind]
		var batch := _batch("Cars_"+String(kind),parked_mesh(kind),slots.size(),true)
		for i: int in slots.size():
			var slot: Node3D = slots[i]
			slot.set_meta("batch",batch)
			slot.set_meta("instance",i)
			slot.set_meta("drawn",true)
			batch.multimesh.set_instance_transform(i,batch.global_transform.affine_inverse()*slot.global_transform)
			if _claimed.has(slot_key(slot.get_meta("anchor"),slot.get_meta("index"))): _apply_claim(slot,true)

## The first night loads the posed figures on a worker thread; the people
## sit down a moment later instead of stalling a frame.
func _draw_audience() -> void:
	if _audience.is_empty(): return
	if _library != null:
		for figure: int in _audience: _draw_figure(figure)
		return
	if not ResourceLoader.exists(AUDIENCE_LIBRARY): return
	if ResourceLoader.load_threaded_get_status(AUDIENCE_LIBRARY) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_request(AUDIENCE_LIBRARY,"MeshLibrary")
	_awaiting_audience = true
	set_process(true)

func _process(_delta: float) -> void:
	if not _awaiting_audience:
		set_process(false)
		return
	var status := ResourceLoader.load_threaded_get_status(AUDIENCE_LIBRARY)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return
	_awaiting_audience = false
	set_process(false)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_library = ResourceLoader.load_threaded_get(AUDIENCE_LIBRARY) as MeshLibrary
		_draw_audience()

func _draw_figure(figure: int) -> void:
	var mesh := _library.get_item_mesh(figure) if _library != null else null
	if mesh == null: return
	var places: Array = _audience[figure]
	var batch := _batch("Moviegoers_%d" % figure,mesh,places.size(),false)
	var inverse := batch.global_transform.affine_inverse()
	for i: int in places.size(): batch.multimesh.set_instance_transform(i,inverse*places[i])

func _batch(label: String, mesh: Mesh, count: int, shadows: bool) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count
	var batch := MultiMeshInstance3D.new()
	batch.name = label
	batch.multimesh = multimesh
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(batch)
	return batch

func audience_count() -> int:
	var count := 0
	for places: Array in _audience.values(): count += places.size()
	return count

## Moviegoers drawn so far (posing finishes over a few frames).
func seated_drawn() -> int:
	var count := 0
	for child: Node in get_children():
		if child is MultiMeshInstance3D and child.name.begins_with("Moviegoers_"): count += (child as MultiMeshInstance3D).multimesh.instance_count
	return count

## A street-crowd figure posed sitting, skinned on the CPU into a static mesh
## in tile units with its pelvis at the origin, plus distance LODs. Used by
## tools/bake_drive_in_audience.gd and tests; works without a renderer.
static func seated_mesh(figure: int, host: Node) -> Mesh:
	if _seated_meshes.has(figure): return _seated_meshes[figure]
	var visual := CityTrafficCatalog.make_nearby_visual(&"pedestrian",figure)
	host.add_child(visual)
	var mesh: Mesh = null
	var skeletons := visual.find_children("*","Skeleton3D",true,false)
	var skins := visual.find_children("*","MeshInstance3D",true,false)
	if not skeletons.is_empty() and not skins.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		for side: String in ["Left","Right"]:
			_sit(skeleton,side+"Thigh",PI*.5,0.0)
			_sit(skeleton,side+"Shin",-PI*.5,0.0)
			# Hands rest on the lap.
			_sit(skeleton,side+"UpperArm",.42,0.0)
			_sit(skeleton,side+"Forearm",.80,0.0)
		# Eyes up to the big screen.
		_sit(skeleton,"Head",-.14,0.0)
		var to_visual := visual.global_transform.affine_inverse()*skeleton.global_transform
		var hips := skeleton.find_bone("Hips")
		var pelvis := to_visual*(skeleton.get_bone_global_pose(hips).origin if hips >= 0 else Vector3.ZERO)
		mesh = _skinned(skins[0] as MeshInstance3D,skeleton,to_visual,pelvis)
	visual.free()
	_seated_meshes[figure] = mesh
	return mesh

static func _sit(skeleton: Skeleton3D, bone: String, bend: float, spread: float) -> void:
	var index := skeleton.find_bone(bone)
	# Bone poses include the rest; keep the imported local axes.
	if index >= 0: skeleton.set_bone_pose_rotation(index,skeleton.get_bone_rest(index).basis.get_rotation_quaternion()*Quaternion.from_euler(Vector3(bend,spread,0)))

static func _skinned(source: MeshInstance3D, skeleton: Skeleton3D, to_visual: Transform3D, pelvis: Vector3) -> Mesh:
	var skin := source.skin
	if skin == null or source.mesh == null: return null
	var shift := Transform3D(Basis.IDENTITY,-pelvis)*to_visual
	var binds: Array[Transform3D] = []
	for bind: int in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(skin.get_bind_name(bind))
		binds.append(shift*skeleton.get_bone_global_pose(maxi(bone,0))*skin.get_bind_pose(bind))
	var importer := ImporterMesh.new()
	for surface: int in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size()/maxi(vertices.size(),1)
		for i: int in vertices.size():
			var point := Vector3.ZERO
			var normal := Vector3.ZERO
			for k: int in per:
				var weight := weights[i*per+k]
				if weight <= 0.0: continue
				var bind := binds[bones[i*per+k]]
				point += (bind*vertices[i])*weight
				if not normals.is_empty(): normal += (bind.basis*normals[i])*weight
			vertices[i] = point
			if not normals.is_empty(): normals[i] = normal.normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if not normals.is_empty(): arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null
		arrays[Mesh.ARRAY_BONES] = null
		arrays[Mesh.ARRAY_WEIGHTS] = null
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},source.get_active_material(surface))
	# Distance LODs: from the air a moviegoer needs a few dozen triangles.
	importer.generate_lods(25.0,60.0,[])
	return importer.get_mesh()

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
	var batch := slot.get_meta("batch",null) as MultiMeshInstance3D
	if batch != null:
		var at := batch.global_transform.affine_inverse()*slot.global_transform
		if claimed: at.basis = Basis.IDENTITY.scaled(Vector3.ZERO)
		batch.multimesh.set_instance_transform(int(slot.get_meta("instance")),at)
		slot.set_meta("drawn",not claimed)

## Whether the parked car in this space is drawn.
func car_drawn(slot: Node3D) -> bool:
	return slot.get_meta("batch",null) != null and slot.get_meta("drawn",false)

## Where every moviegoer sits, in world space.
func audience_places() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for places: Array in _audience.values():
		for place: Transform3D in places: out.append(place)
	return out

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
