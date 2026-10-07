# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Aerial orthographic presentation of the live city; construction stays in Builder.
class_name CityView3D
extends CanvasLayer

signal view_changed
signal geometry_rebuilt(revision: int)

const TERRAIN_LAYER := 1
const BUILDING_LAYER := 2
const CHUNK_SIZE := 16
const ZOOM_NAMES: Array[String] = ["far", "medium", "near", "close", "closest"]
const ZOOM_COUNT := 5
const ZOOM_HALF_WIDTHS: Array[float] = [4.0, 8.0, 16.0, 32.0, 64.0]
const INVALID_CELL := Vector2i(-1, -1)
## Logical pixels per unit of trackpad pan-gesture delta (Godot scales the
## platform's scroll points by about 1/32), so the map tracks the fingers.
const PAN_GESTURE_PIXELS := 32.0
const RenderQuality := preload("res://scripts/view/city_render_quality.gd")
const WaterStyle := preload("res://scripts/view/city_water_style_3d.gd")
const MeshBatcher := preload("res://scripts/view/city_mesh_batcher_3d.gd")
const EXPLORE_SKY := preload("res://assets/environment/desert_day_sky.tres")

var water_style := WaterStyle.new()
var tile_grid_visible := true
var render_quality := "high"
var render_scale := 100
var city: City
var container: TextureRect
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var chunks: Node3D
var buildings: CityBuildings3D
var networks: CityNetworks3D
var mesh_batches: MeshBatcher
var cursor: Node3D
var query_feedback: CityQueryFeedback3D
var feedback: CityFeedback3D
var traffic: CityTraffic3D
var active := false
var center := Vector3(64, 0, 64)
var quarter_turn := 0
var camera_size := 64.0
var input_blocked: Callable
var controls := ControlBindings.new()
var touch_input_blocked: Callable
var catalog: CityModelCatalog
var notice: Label
var street_signage: StreetSignage3D
var labels_visible := true
var _labels: Control
## Sign labels keyed by sign cell; repositioned on camera moves, rebuilt on edits.
var _label_nodes: Dictionary = {}
var _has_rendered := false
var _refresh_queued := false
var _cursor_signature := 0
var _cursor_cells: Array = []
var _cursor_valid := true
## One shared unit box and two shared materials draw every preview outline edge.
static var _cursor_box: BoxMesh
static var _cursor_materials: Array[Material] = []
var _panning := false
var display_layout: DisplayLayout
var overlay: CityOverlay3D
var underground: CityUnderground3D
var _overlay_kind: StringName = &""
var _underground := false
var aerial_controls_enabled := true
var _exploration_camera: Camera3D
var _environment: Environment
var _traversal_chunks: Array[Dictionary] = []
var _road_tunnel_state: Dictionary = {}
## The altitude, terrain, building, vertex and flood layers `_road_tunnel_state`
## was resolved from. Bores read only those layers, and buildings only through
## tunnel codes, so equal inputs resolve the same profiles.
var _road_tunnel_inputs: Array = []
var _traversal_networks: Dictionary = {}
var _traversal_networks_ready := false
var _geometry_revision := 0
var _geometry_state: Array = []
## The input layers from the previous scan, used to keep unchanged lots.
var _previous_geometry_state: Array = []
var _changed_lot_cells: Dictionary = {}
var _lot_regions: Array[Rect2i] = []
var _terrain_unchanged_growth := false
var _terrain_dirty_chunks: Dictionary = {}
var _terrain_rebuild_regions: Array[Rect2i] = []
## Chunk origin -> changed cells whose ground only needs its tint refreshed.
var _terrain_recolor_cells: Dictionary = {}
var _terrain_nodes: Dictionary = {}
var _sign_state: Dictionary = {}
## Counts describe completed work and can be sampled without timing the renderer.
var refresh_statistics: Dictionary = {}


func _ready() -> void:
	layer = -1
	set_tile_grid_visible(tile_grid_visible)
	container = TextureRect.new()
	container.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	container.stretch_mode = TextureRect.STRETCH_SCALE
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	container.size = get_viewport().get_visible_rect().size
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	container.texture = viewport.get_texture()
	_update_display_metrics({})
	catalog = CityModelCatalog.new()
	catalog.load_manifest(CityModelCatalog.ROOT + "catalog.json")
	world = Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.far = 2048.0
	camera.current = true
	world.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color.WHITE
	sun.light_energy = 0.325
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	# The backend-specific scene energy is deliberately low. Give the
	# visible sun its own brightness without adding direct or ambient lighting.
	# Parenting keeps its direction aligned when the scene sun is rotated.
	var sky_sun := DirectionalLight3D.new()
	sky_sun.name = "ExploreSkySun"
	sky_sun.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
	sky_sun.light_color = Color(1.0, 0.96, 0.88)
	sky_sun.light_energy = 1.0
	sun.add_child(sky_sun)
	world.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	_environment = environment.environment
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.16, 0.22, 0.27)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.195
	world.add_child(environment)
	chunks = Node3D.new()
	chunks.name = "Terrain"
	world.add_child(chunks)
	buildings = CityBuildings3D.new()
	buildings.name = "Buildings"
	buildings.set_meta("batch_domain", &"buildings")
	world.add_child(buildings)
	networks = CityNetworks3D.new()
	networks.name = "Networks"
	networks.set_meta("batch_domain", &"networks")
	world.add_child(networks)
	mesh_batches = MeshBatcher.new()
	mesh_batches.name = "StaticMeshBatches"
	world.add_child(mesh_batches)
	cursor = Node3D.new()
	world.add_child(cursor)
	query_feedback = CityQueryFeedback3D.new()
	query_feedback.name = "QueryTileFeedback"
	world.add_child(query_feedback)
	feedback = CityFeedback3D.new()
	feedback.catalog = catalog
	world.add_child(feedback)
	feedback.bind_city(city)
	traffic = CityTraffic3D.new()
	traffic.name = "CityTraffic"
	world.add_child(traffic)
	traffic.bind_city(city)
	geometry_rebuilt.connect(func(_revision: int) -> void: traffic.invalidate())
	_labels = Control.new()
	_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_labels)
	notice = Label.new()
	notice.position = Vector2(235, 34)
	notice.add_theme_color_override("font_color", Color(1, 0.86, 0.58))
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(notice)
	notice.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	container.resized.connect(_update_camera)
	get_viewport().size_changed.connect(_root_resized)
	RenderQuality.apply(self, render_quality)
	set_active(active)


## Attach street-name signage; the city itself is only read.
func bind_street_names(topology: StreetTopology, names: StreetNamingService) -> void:
	if street_signage == null:
		street_signage = StreetSignage3D.new()
		street_signage.name = "StreetSignage"
		world.add_child(street_signage)
	street_signage.bind(self,topology,names)
	street_signage.set_labels_visible(labels_visible)
	street_signage.set_explore_active(not aerial_controls_enabled)


func bind_city(value: City) -> void:
	if city == value:
		return
	var reuse := value != null and _has_rendered and _geometry_inputs(value) == _geometry_state
	city = value
	if query_feedback != null: query_feedback.clear()
	if street_signage != null: street_signage.refresh()
	if not reuse:
		_traversal_chunks = []
		_traversal_networks = {}
		_traversal_networks_ready = false
		_has_rendered = false
	else:
		if water_style != null: water_style.update_city(value)
		if buildings != null: buildings.rebind_station_names(value)
	clear_cursor()
	if traffic != null:
		traffic.bind_city(value)
	if feedback != null:
		feedback.bind_city(value)
	if overlay != null:
		overlay.bind_city(value)
	if underground != null:
		underground.bind_city(value)
	if city != null:
		set_center_cell(Vector2i(City.WIDTH / 2, City.HEIGHT / 2))
	if active:
		refresh()


## Enable or suspend rendering while keeping the camera state.
func set_active(value: bool) -> void:
	active = value
	visible = value
	_panning = false
	if viewport == null:
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if active:
		refresh()
		_update_camera()
	else:
		clear_cursor()
		if query_feedback != null: query_feedback.clear()


## Merge repeated edit notifications into one deferred refresh.
func queue_refresh() -> void:
	if not active or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_deferred_refresh")


func _deferred_refresh() -> void:
	_refresh_queued = false
	if active:
		refresh()


## Rebuild only when visible city geometry or signage changes.
func refresh(force_full: bool = false) -> void:
	if city == null or world == null:
		return
	# Utility markers read live service flags independently of geometry.
	feedback.sync_power()
	refresh_analytics()
	var started := Time.get_ticks_usec()
	# One read-only ground sampling scope covers change detection, water styling
	# and every geometry owner below; it ends before any public callback.
	var ground_sampling := CityGeometry3D.begin_ground_sampling(city)
	var full := force_full or not _has_rendered
	var regions := _changed_regions(full)
	if _sign_state != city.signs:
		_sign_state = city.signs.duplicate(true)
		_update_labels()
	if regions.is_empty():
		CityGeometry3D.end_ground_sampling(ground_sampling)
		refresh_statistics = {"terrain_chunks": 0, "network_chunks": 0, "lots": 0,
			"microseconds": Time.get_ticks_usec()-started}
		return
	_has_rendered = true
	water_style.update_city(city)
	if full:
		mesh_batches.clear()
		_traversal_chunks = []
		_terrain_nodes.clear()
		for child: Node in chunks.get_children():
			chunks.remove_child(child)
			child.queue_free()
		buildings.clear()
		networks.clear()
		_traversal_chunks.resize((City.WIDTH / CHUNK_SIZE) * (City.HEIGHT / CHUNK_SIZE))
	# Replacing the array leaves snapshots already handed out unchanged.
	_traversal_chunks = _traversal_chunks.duplicate()
	var terrain_started := Time.get_ticks_usec()
	for region: Rect2i in _terrain_rebuild_regions:
		_replace_terrain_chunk(region)
	var recolored := 0
	for origin: Vector2i in _terrain_recolor_cells:
		if full or _terrain_dirty_chunks.has(origin): continue
		recolored += 1
		_recolor_terrain_chunk(origin, _terrain_recolor_cells[origin].keys())
	var terrain_us := Time.get_ticks_usec()-terrain_started
	var lots_started := Time.get_ticks_usec()
	var lot_regions := buildings.update_regions(city, catalog, _lot_regions, [] if full else _previous_geometry_state, _geometry_state)
	var lots_us := Time.get_ticks_usec()-lots_started
	var networks_started := Time.get_ticks_usec()
	var network_regions := networks.update_regions(city, regions, CHUNK_SIZE)
	var networks_us := Time.get_ticks_usec()-networks_started
	# End the read-only scope before visibility/camera/public signal callbacks.
	CityGeometry3D.end_ground_sampling(ground_sampling)
	if full or not network_regions.is_empty():
		_traversal_networks = {}
		_traversal_networks_ready = false
	buildings.visible = true
	networks.visible = true
	var batch_regions: Array[Rect2i] = network_regions.duplicate()
	batch_regions.append_array(lot_regions)
	var batches_started := Time.get_ticks_usec()
	if full:
		mesh_batches.rebuild([buildings, networks])
	else:
		mesh_batches.update_regions([buildings, networks], batch_regions)
	var batches_us := Time.get_ticks_usec()-batches_started
	_apply_analytics_visibility()
	_update_notice()
	_update_camera()
	refresh_statistics = {"terrain_chunks": regions.size(), "network_chunks": network_regions.size(),
		"terrain_rebuilt_chunks": _terrain_rebuild_regions.size(), "terrain_recolored_chunks": recolored,
		"lots": buildings.last_updated_lots, "retained_lots": buildings.last_retained_lots, "microseconds": Time.get_ticks_usec()-started,
		"terrain_us": terrain_us, "lots_us": lots_us, "networks_us": networks_us, "batches_us": batches_us}
	_geometry_revision += 1
	# An unchanged preview re-reads the rebuilt ground heights.
	if _cursor_signature != 0:
		show_cells(_cursor_cells, _cursor_valid)
	geometry_rebuilt.emit(_geometry_revision)


## Copy-on-write packed snapshots detect direct simulation/import array writes.
## Scan only changed layers; POWERED/WATERED are feedback, not static geometry.
func _geometry_inputs(value: City) -> Array:
	var flags := _masked_flags(value.flags.data)
	var vertices: PackedByteArray = value.terrain_surface.vertices if value.terrain_surface is TerrainSurface else PackedByteArray()
	return [value.altitude.data.duplicate(), value.terrain.data.duplicate(), value.building.data.duplicate(), value.zone.data.duplicate(), flags, vertices.duplicate(), value.flood_overlay.duplicate(true), value.underground.data.duplicate()]


## Service bits are feedback, not geometry. Masking every byte each refresh is
## avoided by keeping the last raw/masked pair and re-masking only changed rows.
var _masked_flags_raw := PackedByteArray()
var _masked_flags_value := PackedByteArray()

func _masked_flags(raw: PackedByteArray) -> PackedByteArray:
	if raw == _masked_flags_raw and not raw.is_empty(): return _masked_flags_value.duplicate()
	var masked := raw.duplicate()
	var mask := ~(TileFlags.POWERED | TileFlags.WATERED)
	if raw.size() == _masked_flags_raw.size() and raw.size() % City.WIDTH == 0:
		masked = _masked_flags_value.duplicate()
		for i: int in _changed_indices(_masked_flags_raw, raw, City.WIDTH): masked[i] = raw[i] & mask
	else:
		for i: int in masked.size(): masked[i] &= mask
	_masked_flags_raw = raw.duplicate()
	_masked_flags_value = masked.duplicate()
	return masked


## Indices whose bytes differ, comparing whole rows before individual entries.
static func _changed_indices(before: Variant, after: Variant, width: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	if before == after: return indices
	var size := mini(before.size(), after.size())
	var start := 0
	while start < size:
		var end := mini(size, start + width)
		if before.slice(start, end) != after.slice(start, end):
			for i: int in range(start, end):
				if before[i] != after[i]: indices.append(i)
		start = end
	return indices


func _changed_regions(full: bool) -> Array[Rect2i]:
	_changed_lot_cells.clear()
	_terrain_dirty_chunks.clear()
	_terrain_rebuild_regions.clear()
	_terrain_recolor_cells.clear()
	var state := _geometry_inputs(city)
	var dirty: Dictionary = {}
	if _geometry_state.size()!=state.size(): full = true
	var changes: Array[PackedInt32Array] = []
	if not full:
		for layer: int in 6:
			var indices := PackedInt32Array()
			if state[layer] != _geometry_state[layer]:
				if state[layer].size() != _geometry_state[layer].size():
					full = true
					break
				indices = _changed_indices(_geometry_state[layer], state[layer], TerrainSurface.VERTS_X if layer == 5 else City.WIDTH)
			changes.append(indices)
	_terrain_unchanged_growth = not full and _ordinary_growth_only_indexed(_geometry_state,state,changes)
	if not full:
		for layer: int in 6:
			for i: int in changes[layer]:
				var width: int = TerrainSurface.VERTS_X if layer == 5 else City.WIDTH
				var ordinary := layer in [2,3,4] and (_terrain_unchanged_growth or _ordinary_ground_cell(_geometry_state,state,i))
				var cell := Vector2i(i % width, i / width)
				if not ordinary and layer == 4 and not _flags_affect_terrain(_geometry_state[2][i], state[2][i]):
					_mark_dirty(dirty, cell, false)
				elif not ordinary and _recolors_terrain_only(layer, _geometry_state[layer][i], state[layer][i]):
					_mark_dirty(dirty, cell, false)
					_mark_recolor(cell)
				else:
					_mark_dirty(dirty, cell, not ordinary)
		if state[6] != _geometry_state[6]:
			for cell: Vector2i in state[6]:
				if not _geometry_state[6].has(cell) or state[6][cell] != _geometry_state[6][cell]: _mark_dirty(dirty, cell)
			for cell: Vector2i in _geometry_state[6]:
				if not state[6].has(cell): _mark_dirty(dirty, cell)
		# Subway topology changes rotate station entrances and invalidate local
		# passenger routes even when no above-ground tile changes. Compare masks
		# only for edited bytes; ordinary pipe edits retain surface geometry.
		if state[7] != _geometry_state[7]:
			if state[7].size()!=_geometry_state[7].size():
				full = true
			else:
				for i: int in state[7].size():
					if state[7][i] == _geometry_state[7][i]: continue
					if NetworkShapes.underground_mask(state[7][i],NetworkShapes.Family.SUBWAY) != NetworkShapes.underground_mask(_geometry_state[7][i],NetworkShapes.Family.SUBWAY):
						_mark_dirty(dirty,Vector2i(i % City.WIDTH,i / City.WIDTH))
	if (full or state[0]!=_geometry_state[0] or state[1]!=_geometry_state[1] or state[2]!=_geometry_state[2] or state[5]!=_geometry_state[5]) \
			and (full or not _road_tunnel_inputs_match(state)):
		var tunnels := CityGeometry3D.road_tunnel_profiles(city)
		for collection: Dictionary in [_road_tunnel_state,tunnels]:
			for cell: Vector2i in collection:
				if _road_tunnel_state.get(cell,{})!=tunnels.get(cell,{}): _mark_dirty(dirty,cell)
		_road_tunnel_state = tunnels
		_road_tunnel_inputs = [state[0], state[1], state[2], state[5], state[6]]
	_previous_geometry_state = _geometry_state
	_geometry_state = state
	var result: Array[Rect2i] = []
	for y: int in range(0, City.HEIGHT, CHUNK_SIZE):
		for x: int in range(0, City.WIDTH, CHUNK_SIZE):
			var origin := Vector2i(x,y)
			if full or dirty.has(origin): result.append(Rect2i(origin, Vector2i.ONE*CHUNK_SIZE))
			if full or _terrain_dirty_chunks.has(origin): _terrain_rebuild_regions.append(Rect2i(origin,Vector2i.ONE*CHUNK_SIZE))
	# Lot updates follow the changed cells plus their dependency reach.
	# Coalesce large edits into exact rectangles; admitting whole dirty terrain
	# chunks would recreate unrelated models throughout a city during scattered
	# growth.
	_lot_regions = []
	if full:
		_lot_regions.append(Rect2i(0,0,City.WIDTH,City.HEIGHT))
	elif _changed_lot_cells.size() > 64:
		_lot_regions = _coalesced_lot_cells(_changed_lot_cells)
	else:
		for cell: Vector2i in _changed_lot_cells:
			_lot_regions.append(Rect2i(cell,Vector2i.ONE))
	return result


## Whether every input of the retained road bore profiles is unchanged: the
## altitude (heights and tunnel bits), terrain, vertex and flood layers, and the
## building layer at every cell that is or was a tunnel mouth.
func _road_tunnel_inputs_match(state: Array) -> bool:
	if _road_tunnel_inputs.size() != 5: return false
	if state[0] != _road_tunnel_inputs[0] or state[1] != _road_tunnel_inputs[1] \
			or state[5] != _road_tunnel_inputs[3] or state[6] != _road_tunnel_inputs[4]:
		return false
	var before: PackedByteArray = _road_tunnel_inputs[2]
	var after: PackedByteArray = state[2]
	if before.size() != after.size(): return false
	for i: int in _changed_indices(before, after, City.WIDTH):
		if NetworkShapes.is_tunnel(before[i]) or NetworkShapes.is_tunnel(after[i]): return false
	return true


## Occupied residential/commercial/industrial upgrades cannot change terrain
## faces, zone tint, water or portal cutouts. Every input is compared; only this
## narrow case keeps the ground, while lots and networks still update fully.
## Uses the already computed per-layer change indices instead of rescanning.
static func _ordinary_growth_only_indexed(before: Array, after: Array, changes: Array[PackedInt32Array]) -> bool:
	if before.size()!=8 or after.size()!=8 or changes.size()!=6: return false
	for layer: int in [0,1,5]:
		if not changes[layer].is_empty(): return false
	for layer: int in [6,7]:
		if before[layer]!=after[layer]: return false
	for layer: int in [2,3,4]:
		for i: int in changes[layer]:
			if not _ordinary_ground_cell(before,after,i): return false
	return true


static func _ordinary_growth_only(before: Array, after: Array) -> bool:
	if before.size()!=8 or after.size()!=8: return false
	for layer: int in [0,1,5,6,7]:
		if before[layer]!=after[layer]: return false
	for layer: int in [2,3,4]:
		if before[layer]==after[layer]: continue
		if before[layer].size()!=after[layer].size(): return false
		for i: int in after[layer].size():
			if before[layer][i]==after[layer][i]: continue
			if not _ordinary_ground_cell(before,after,i): return false
	return true


static func _ordinary_ground_cell(before: Array, after: Array, index: int) -> bool:
	return Buildings.is_zone_building(before[2][index]) and Buildings.is_zone_building(after[2][index])


## Horizontal runs merge vertically only when their x extents are identical.
## Keep vertex-border coordinates (128) intact: their neighboring lots still
## depend on them even though those vertices are outside the 128-cell grid.
static func _coalesced_lot_cells(cells: Dictionary) -> Array[Rect2i]:
	var sorted: Array = cells.keys()
	sorted.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y<b.y or (a.y==b.y and a.x<b.x))
	var result: Array[Rect2i] = []
	var previous: Dictionary = {}
	var i := 0
	while i < sorted.size():
		var start: Vector2i = sorted[i]
		var end := start.x+1
		i += 1
		while i < sorted.size() and sorted[i].y==start.y and sorted[i].x==end:
			end += 1
			i += 1
		var key := Vector2i(start.x,end-start.x)
		var slot := int(previous.get(key,-1))
		if slot>=0 and result[slot].end.y==start.y:
			result[slot].size.y += 1
		else:
			slot = result.size()
			result.append(Rect2i(start,Vector2i(end-start.x,1)))
		previous[key] = slot
	return result


## Building and zone bytes only tint the ground; tunnel mouths and subway portals
## are the codes that cut terrain. Heights, water, vertices, floods, flags and
## underground masks keep their full chunk rebuild.
static func _recolors_terrain_only(layer: int, before: int, after: int) -> bool:
	if layer == 3: return true
	if layer != 2: return false
	for code: int in [before, after]:
		if NetworkShapes.is_tunnel(code) or NetworkShapes.is_subway_portal(code): return false
	return true


## Terrain reads no service or orientation flag, except through a neighbouring
## rail bridge whose axis flag orients a subway portal mouth.
static func _flags_affect_terrain(before: int, after: int) -> bool:
	return NetworkShapes.in_rail_family(before) or NetworkShapes.in_rail_family(after)


func _mark_recolor(cell: Vector2i) -> void:
	var origin := Vector2i(cell.x / CHUNK_SIZE, cell.y / CHUNK_SIZE) * CHUNK_SIZE
	if not _terrain_recolor_cells.has(origin): _terrain_recolor_cells[origin] = {}
	_terrain_recolor_cells[origin][cell] = true


func _mark_dirty(dirty: Dictionary, cell: Vector2i, affects_terrain: bool = true) -> void:
	_changed_lot_cells[cell] = true
	# Cubic highway heights plus an odd 2x2 footprint can reach three cells.
	# Lots are additionally intersected by their own dependency rules.
	var bounds := Rect2i(cell-Vector2i(3,3), Vector2i(7,7)).intersection(Rect2i(0,0,City.WIDTH,City.HEIGHT))
	# The halo's chunks are a small range; visit each chunk once, not each cell.
	for cy: int in range(bounds.position.y / CHUNK_SIZE, (bounds.end.y - 1) / CHUNK_SIZE + 1):
		for cx: int in range(bounds.position.x / CHUNK_SIZE, (bounds.end.x - 1) / CHUNK_SIZE + 1):
			var origin := Vector2i(cx, cy) * CHUNK_SIZE
			dirty[origin] = true
			if affects_terrain: _terrain_dirty_chunks[origin] = true


func _replace_terrain_chunk(region: Rect2i) -> void:
	var origin := region.position
	var index := (origin.y / CHUNK_SIZE) * (City.WIDTH / CHUNK_SIZE) + origin.x / CHUNK_SIZE
	var order := chunks.get_child_count()
	if _terrain_nodes.has(origin):
		order = _terrain_nodes[origin][0].get_index()
		for child: Node in _terrain_nodes[origin]:
			chunks.remove_child(child)
			child.queue_free()
	var data := CityGeometry3D.build_chunk(city, region)
	_traversal_chunks[index] = data
	var mesh := MeshInstance3D.new()
	mesh.mesh = data.mesh
	if mesh.mesh.get_surface_count() > 0:
		mesh.mesh.surface_set_material(0,water_style.material)
	chunks.add_child(mesh)
	chunks.move_child(mesh, order)
	var body := StaticBody3D.new()
	body.name = "TerrainQuery"
	body.collision_layer = TERRAIN_LAYER
	body.collision_mask = 0
	body.set_meta("face_cells", data.face_cells)
	var shape := CollisionShape3D.new()
	var collision := ConcavePolygonShape3D.new()
	collision.set_faces(data.faces)
	collision.backface_collision = true
	shape.shape = collision
	body.add_child(shape)
	chunks.add_child(body)
	chunks.move_child(body, order+1)
	_terrain_nodes[origin] = [mesh, body]


## Refresh only the ground tint of `cells` in a retained chunk. Picking bodies,
## traversal faces and water regions are unchanged; a chunk without tint
## records is rebuilt instead.
func _recolor_terrain_chunk(origin: Vector2i, cells: Array) -> void:
	var index := (origin.y / CHUNK_SIZE) * (City.WIDTH / CHUNK_SIZE) + origin.x / CHUNK_SIZE
	var region := Rect2i(origin, Vector2i.ONE * CHUNK_SIZE)
	if not _terrain_nodes.has(origin) or index >= _traversal_chunks.size() or _traversal_chunks[index].is_empty():
		_replace_terrain_chunk(region)
		return
	var data: Dictionary = _traversal_chunks[index]
	var updated := CityGeometry3D.recolor_chunk(city, data, cells)
	if updated.is_empty():
		_replace_terrain_chunk(region)
		return
	if updated.mesh == data.mesh: return
	_traversal_chunks[index] = updated
	var mesh: MeshInstance3D = _terrain_nodes[origin][0]
	mesh.mesh = updated.mesh
	if mesh.mesh.get_surface_count() > 0:
		mesh.mesh.surface_set_material(0,water_style.material)


## Tagged outputs belong to the completed visible geometry revision.
func traversal_snapshot() -> Dictionary:
	# Aerial rendering never needs this expensive extraction. Physical inputs
	# belong to the completed projection and do not read later live city writes.
	# Exploration requests the complete snapshot before it reconciles movement.
	if not _traversal_networks_ready and networks != null and _has_rendered:
		_traversal_networks = networks.physical_data()
		_traversal_networks_ready = true
	return {"city": city, "chunks": _traversal_chunks, "networks": _traversal_networks, "revision": _geometry_revision}


## True when the rendered geometry matches the bound city's current data.
func is_geometry_current() -> bool:
	return city != null and _has_rendered and _geometry_state == _geometry_inputs(city)

## Increments each time the visible city geometry is rebuilt.
func geometry_revision() -> int:
	return _geometry_revision


## The visible terrain mesh of each built chunk, keyed by chunk origin.
func terrain_meshes() -> Dictionary:
	var meshes := {}
	for origin: Vector2i in _terrain_nodes:
		meshes[origin] = _terrain_nodes[origin][0]
	return meshes


## The perspective camera Explore mode renders through, or null in Build.
func exploration_camera() -> Camera3D:
	return _exploration_camera


## The data overlay currently drawn over the city, or &"" for none.
func overlay_kind() -> StringName:
	return _overlay_kind


func set_exploration_camera(value: Camera3D) -> void:
	if not is_instance_valid(value):
		return
	if street_signage != null: street_signage.set_explore_active(true)
	# The perspective camera owns its background. Keep the aerial environment
	# and the established material/interior lighting independent of the sky.
	value.environment = _environment.duplicate() as Environment
	value.environment.background_mode = Environment.BG_SKY
	value.environment.sky = EXPLORE_SKY
	value.environment.ambient_light_sky_contribution = 0.0
	value.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_exploration_camera = value
	aerial_controls_enabled = false
	_panning = false
	clear_cursor()
	_labels.hide()
	camera.current = false
	value.current = true
	RenderQuality.apply_shadow_focus(self)


func clear_exploration_camera() -> void:
	if street_signage != null: street_signage.set_explore_active(false)
	if is_instance_valid(_exploration_camera):
		_exploration_camera.current = false
		_exploration_camera.environment = null
	_exploration_camera = null
	aerial_controls_enabled = true
	camera.current = true
	_labels.show()
	_update_camera()


func _update_notice() -> void:
	var count := buildings.missing.size()
	notice.visible = count > 0 or not catalog.errors.is_empty()
	notice.text = "Missing 3D models: %d · amber roofs mark substitutes" % count if count > 0 else "Some 3D models are unavailable"


## Apply a complete camera handoff in one update.
func set_camera_state(target: Vector3, rotation: int, size: float) -> void:
	if not target.is_finite() or not is_finite(size):
		return
	center = target
	center.x = clampf(center.x, 0.0, City.WIDTH)
	center.z = clampf(center.z, 0.0, City.HEIGHT)
	quarter_turn = posmod(rotation, 4)
	camera_size = clampf(size, 0.5, 2048.0)
	_update_camera()


func _update_camera() -> void:
	if camera == null or is_instance_valid(_exploration_camera):
		return
	camera.size = camera_size
	var angle := PI / 4.0 + quarter_turn * PI / 2.0
	# A 30-degree elevation draws each tile as a 2:1 diamond.
	var distance := 160.0
	camera.position = center + Vector3(cos(angle) * distance, tan(PI / 6.0) * distance, sin(angle) * distance)
	camera.look_at(center)
	RenderQuality.apply_shadow_focus(self)
	_update_labels()
	view_changed.emit()


## Terrain-only placement uses layer 1; query tools also consider layer 2.
func pick_cell(point: Vector2, purpose: int = 0) -> Vector2i:
	if not aerial_controls_enabled or not active or city == null or camera == null or container.size.x <= 0 or container.size.y <= 0:
		return INVALID_CELL
	var local := point - container.position
	if not Rect2(Vector2.ZERO, container.size).has_point(local):
		return INVALID_CELL
	local = local * Vector2(viewport.size) / container.size
	var origin := camera.project_ray_origin(local)
	var mask := TERRAIN_LAYER | BUILDING_LAYER if purpose == 1 and not _underground and _overlay_kind == &"" else TERRAIN_LAYER
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(local) * camera.far, mask)
	query.hit_back_faces = true
	var hit := viewport.find_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return INVALID_CELL
	var body: Node = hit.collider
	if body.has_meta("cell"):
		return body.get_meta("cell")
	var cells: Array = body.get_meta("face_cells", [])
	var face: int = hit.get("face_index", -1)
	return cells[face] if face >= 0 and face < cells.size() else INVALID_CELL


## Project a tile center into the application's screen coordinates.
func project_cell(cell: Vector2i) -> Vector2:
	if city == null or camera == null or viewport.size.x <= 0 or viewport.size.y <= 0:
		return Vector2(-1, -1)
	var position := Vector3(cell.x + 0.5, CityGeometry3D.surface_height(city, cell), cell.y + 0.5)
	var pixels := camera.unproject_position(position)
	var local := pixels * container.size / Vector2(viewport.size)
	return container.position + local


## Project an arbitrary surface point into root logical coordinates at any render scale.
func project_world(point: Vector3) -> Vector2:
	if camera == null or viewport.size.x <= 0: return Vector2(-1,-1)
	return container.position+camera.unproject_position(point)*container.size/Vector2(viewport.size)


## Set one of the five ordered zoom levels.
func set_zoom_level(level: int) -> void:
	camera_size = _zoom_size(clampi(level, 0, ZOOM_HALF_WIDTHS.size() - 1))
	_update_camera()


func _zoom_size(level: int) -> float:
	var height := maxf(container.size.y if container != null else get_viewport().get_visible_rect().size.y, 1.0)
	return clampf(height / (sqrt(2.0) * ZOOM_HALF_WIDTHS[level]), 0.5, 2048.0)


## Nearest named zoom, including camera sizes received during view handoff.
func zoom_level() -> int:
	var closest := 0
	for i: int in range(1, ZOOM_HALF_WIDTHS.size()):
		if absf(camera_size - _zoom_size(i)) < absf(camera_size - _zoom_size(closest)):
			closest = i
	return closest


func zoom_in() -> void:
	camera_size = _clamped_zoom(camera_size / 1.25)
	_update_camera()


func zoom_out() -> void:
	camera_size = _clamped_zoom(camera_size * 1.25)
	_update_camera()


## Free zoom (wheel, pinch, menu steps) stays near the named levels: from three
## quarters of the closest to one and a half times the farthest. A camera that
## arrived outside that range by handoff may step back in but never further out.
func _clamped_zoom(size: float) -> float:
	var low := _zoom_size(ZOOM_HALF_WIDTHS.size() - 1) * 0.75
	var high := _zoom_size(0) * 1.5
	return clampf(clampf(size, minf(low, camera_size), maxf(high, camera_size)), 0.5, 2048.0)


## Wheel zoom keeps the ground under the pointer in place.
func _zoom_at(point: Vector2, factor: float) -> void:
	var before: Variant = _ground_point(point)
	camera_size = _clamped_zoom(camera_size * factor)
	_update_camera()
	if before == null:
		return
	var after: Variant = _ground_point(point)
	if after == null:
		return
	var shift: Vector3 = before - after
	shift.y = 0.0
	if shift.is_finite() and shift.length_squared() > 0.0:
		_pan(shift)


## Where a screen point's view ray meets the horizontal plane through the
## camera target; null when the point is off the map image.
func _ground_point(point: Vector2) -> Variant:
	if camera == null or container == null or viewport == null or container.size.x <= 0 or container.size.y <= 0 or viewport.size.x <= 0:
		return null
	var local := point - container.position
	if not Rect2(Vector2.ZERO, container.size).has_point(local):
		return null
	local = local * Vector2(viewport.size) / container.size
	var origin := camera.project_ray_origin(local)
	var normal := camera.project_ray_normal(local)
	if absf(normal.y) < 0.0001:
		return null
	var hit := origin + normal * ((center.y - origin.y) / normal.y)
	return hit if hit.is_finite() else null


## Cancel a drag immediately when a dialog or another mode takes input.
func cancel_pan() -> void:
	_panning = false

## Touch coordinates and deltas already use root logical units. The render
## viewport can be doubled by display density without changing pan distance.
func pan_screen(delta: Vector2) -> void:
	if _touch_blocked():
		return
	_pan_screen_delta(delta)

func _pan_screen_delta(delta: Vector2) -> void:
	if camera == null or container == null or not delta.is_finite():
		return
	var forward := camera.global_basis.z
	forward.y = 0
	_pan((-camera.global_basis.x * delta.x - forward.normalized() * delta.y * 2.0) * camera_size / maxf(container.size.y, 1.0))

## Use consecutive contact distances, with a bound for noisy/replaced touches.
func pinch_zoom(distance_ratio: float) -> void:
	if _touch_blocked():
		return
	_magnify(distance_ratio)


## Zoom by a spread ratio (greater than 1 zooms in), bounded per delivery.
func _magnify(ratio: float) -> void:
	if not is_finite(ratio) or ratio <= 0.0:
		return
	camera_size = _clamped_zoom(camera_size / clampf(ratio, 0.5, 2.0))
	_update_camera()


func cycle_rotation() -> void:
	quarter_turn = posmod(quarter_turn + 1, 4)
	_update_camera()


## Focus a map or minimap selection at its ground height.
func set_center_cell(cell: Vector2i) -> void:
	if city == null:
		return
	var selected := Vector2i(clampi(cell.x, 0, City.WIDTH - 1), clampi(cell.y, 0, City.HEIGHT - 1))
	center = Vector3(selected.x + 0.5, CityGeometry3D.surface_height(city, selected), selected.y + 0.5)
	_update_camera()


func recenter() -> void:
	set_center_cell(Vector2i(City.WIDTH / 2, City.HEIGHT / 2))


func _blocked() -> bool:
	return not aerial_controls_enabled or not active or city == null or (input_blocked.is_valid() and bool(input_blocked.call()))

## Focused toolbar controls reserve keyboard shortcuts, but ordinary focus is
## not a touch modal. Falls back to input_blocked until Main binds a touch check.
func _touch_blocked() -> bool:
	var checker := touch_input_blocked if touch_input_blocked.is_valid() else input_blocked
	return not aerial_controls_enabled or not active or city == null or (checker.is_valid() and bool(checker.call()))


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if _blocked():
		_panning = false
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, 1.0 / 1.25)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.25)
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		# Trackpad pinch: the same bounded zoom as a touch pinch.
		_magnify((event as InputEventMagnifyGesture).factor)
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		# Two-finger trackpad/Magic Mouse scroll moves the map with the fingers.
		_pan_screen_delta(-(event as InputEventPanGesture).delta * PAN_GESTURE_PIXELS)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _panning:
		_pan_screen_delta(event.relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and not (display_layout != null and display_layout.blocks_city_keyboard()) and event.pressed and not event.echo and not event.ctrl_pressed and not event.meta_pressed and not event.alt_pressed:
		if controls.matches(event,&"rotate"):
			cycle_rotation()
			get_viewport().set_input_as_handled()
		else:
			for level: int in 5:
				if controls.matches(event,StringName("zoom_%d" % (level+1))):
					set_zoom_level(level)
					get_viewport().set_input_as_handled()
					break


func _process(delta: float) -> void:
	if active:
		water_style.advance(delta)
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_panning = false
	if _blocked() or (display_layout != null and display_layout.blocks_city_keyboard()) or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_ALT):
		return
	var axis := Vector2(float(controls.pressed(&"pan_right")) - float(controls.pressed(&"pan_left")),
		float(controls.pressed(&"pan_back")) - float(controls.pressed(&"pan_forward")))
	if axis != Vector2.ZERO:
		var forward := camera.global_basis.z
		forward.y = 0
		_pan((camera.global_basis.x * axis.x + forward.normalized() * axis.y) * delta * camera_size * 0.6)


func _pan(offset: Vector3) -> void:
	center += offset
	center.x = clampf(center.x, 0.0, City.WIDTH)
	center.z = clampf(center.z, 0.0, City.HEIGHT)
	var cell := Vector2i(clampi(int(center.x), 0, City.WIDTH - 1), clampi(int(center.z), 0, City.HEIGHT - 1))
	center.y = CityGeometry3D.surface_height(city, cell)
	_update_camera()


## Show the exact tile list returned by construction preview.
## Every tile edge is one instance of a shared unit beam in a single MultiMesh,
## so large drag rectangles stay one node regardless of their tile count.
func show_cells(cells: Array, valid: bool) -> void:
	var signature := hash([cells, valid, _geometry_revision])
	if signature == _cursor_signature:
		return
	clear_cursor()
	_cursor_signature = signature
	_cursor_cells = cells.duplicate()
	_cursor_valid = valid
	if not active or city == null:
		return
	var corners: Dictionary = {}
	# Neighboring tiles share corner vertices; one read-only scope samples each once.
	var ground_sampling := CityGeometry3D.begin_ground_sampling(city)
	for cell: Vector2i in cells:
		if city.in_bounds(cell.x, cell.y) and not corners.has(cell):
			corners[cell] = CityGeometry3D.surface_corners(city, cell)
	CityGeometry3D.end_ground_sampling(ground_sampling)
	if corners.is_empty():
		return
	var buffer := PackedFloat32Array()
	buffer.resize(corners.size() * 4 * 12)
	var count := 0
	for cell: Vector2i in corners:
		var p: PackedVector3Array = corners[cell]
		for edge: Array in CityGeometry3D.CHUNK_EDGES:
			var a: Vector3 = p[edge[0]]
			var b: Vector3 = p[edge[1]]
			# A neighbor's identical edge draws the same beam; west/north
			# edges defer to it so shared edges are emitted once.
			var step: Vector2i = edge[2]
			if step.x + step.y < 0 and corners.has(cell + step):
				var other: PackedVector3Array = corners[cell + step]
				if other[edge[3]] == a and other[edge[4]] == b:
					continue
			a += Vector3.UP * 0.06
			b += Vector3.UP * 0.06
			var basis := Basis.looking_at(b - (a + b) / 2.0, Vector3.UP)
			basis = Basis(basis.x * 0.045, basis.y * 0.035, basis.z * a.distance_to(b))
			var origin := (a + b) / 2.0
			var offset := count * 12
			buffer[offset] = basis.x.x
			buffer[offset + 1] = basis.y.x
			buffer[offset + 2] = basis.z.x
			buffer[offset + 3] = origin.x
			buffer[offset + 4] = basis.x.y
			buffer[offset + 5] = basis.y.y
			buffer[offset + 6] = basis.z.y
			buffer[offset + 7] = origin.y
			buffer[offset + 8] = basis.x.z
			buffer[offset + 9] = basis.y.z
			buffer[offset + 10] = basis.z.z
			buffer[offset + 11] = origin.z
			count += 1
	buffer.resize(count * 12)
	if _cursor_box == null:
		_cursor_box = BoxMesh.new()
		_cursor_materials = [CityGeometry3D.material(Color(1, 0.22, 0.18)), CityGeometry3D.material(Color(0.15, 0.95, 0.6))]
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = _cursor_box
	batch.instance_count = count
	batch.buffer = buffer
	var outline := MultiMeshInstance3D.new()
	outline.name = "PreviewOutline"
	outline.multimesh = batch
	outline.material_override = _cursor_materials[1 if valid else 0]
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cursor.add_child(outline)


func clear_cursor() -> void:
	_cursor_signature = 0
	_cursor_cells = []
	if cursor == null:
		return
	for child: Node in cursor.get_children():
		cursor.remove_child(child)
		child.queue_free()


## Sign visibility follows the display preference.
func set_labels_visible(value: bool) -> void:
	labels_visible = value
	if street_signage != null: street_signage.set_labels_visible(value)
	_update_labels()


## Keep one label per sign: create/free only for added/removed signs and
## reposition the retained labels for the current camera.
func _update_labels() -> void:
	if _labels == null:
		return
	var shown := aerial_controls_enabled and labels_visible and city != null
	for cell: Vector2i in _label_nodes.keys():
		if not shown or not city.signs.has(cell):
			var stale: Label = _label_nodes[cell]
			_label_nodes.erase(cell)
			_labels.remove_child(stale)
			stale.queue_free()
	if not shown:
		return
	for cell: Vector2i in city.signs:
		var label: Label = _label_nodes.get(cell)
		if label == null:
			label = Label.new()
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
			label.add_theme_color_override("font_shadow_color", Color.BLACK)
			label.add_theme_constant_override("shadow_offset_x", 1)
			label.add_theme_constant_override("shadow_offset_y", 1)
			_labels.add_child(label)
			_label_nodes[cell] = label
		label.text = String(city.signs[cell])
		label.position = project_cell(cell) + Vector2(0, -24)


## Visible ground bounds in the minimap's current orientation.
func minimap_rect(rotation: int, scale_factor: float) -> Rect2:
	if not aerial_controls_enabled or city == null or camera == null:
		return Rect2()
	var plane := Plane(Vector3.UP, center.y)
	var points: Array[Vector2] = []
	for point: Vector2 in [Vector2.ZERO, Vector2(viewport.size.x, 0), Vector2(0, viewport.size.y), Vector2(viewport.size)]:
		var hit: Variant = plane.intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))
		if hit is Vector3:
			points.append(RotationMapper.data_to_screen(Vector2(hit.x - 0.5, hit.z - 0.5), rotation) * scale_factor)
	if points.is_empty():
		return Rect2()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


## Render resolution is independent of logical UI scaling and physical picking.
func set_render_options(quality: String, percent: int) -> void:
	water_style.set_quality(quality)
	render_quality = quality if quality in ["high", "balanced", "performance"] else "high"
	render_scale = percent if percent in [50, 75, 100] else 100
	if world != null: RenderQuality.apply(self, render_quality)
	_update_display_metrics({})


## The display layout converts root logical UI coordinates to native output.
func bind_display_layout(layout: DisplayLayout) -> void:
	if display_layout != null and display_layout.metrics_changed.is_connected(_update_display_metrics):
		display_layout.metrics_changed.disconnect(_update_display_metrics)
	display_layout = layout
	if display_layout != null:
		display_layout.metrics_changed.connect(_update_display_metrics)
	_update_display_metrics({})

func _root_resized() -> void:
	if display_layout == null:
		_update_display_metrics({})

func _update_display_metrics(_metrics: Dictionary) -> void:
	if container == null or viewport == null:
		return
	# Safe areas and keyboard occlusion constrain controls, not the city image.
	# Fill the drawable behind the home indicator instead of exposing clear gray.
	var bounds: Rect2 = display_layout.metrics.get("full_logical_rect",display_layout.logical_rect()) if display_layout != null else get_viewport().get_visible_rect()
	container.position = bounds.position
	container.size = bounds.size
	var native_size := display_layout.drawable_size() if display_layout != null else Vector2i(bounds.size)
	viewport.size = RenderQuality.scaled_size(native_size, render_scale)
	_update_camera()

## Attach the overlay and underground helpers once; no surface geometry is rebuilt.
func bind_analytics(surface: CityOverlay3D, utilities: CityUnderground3D) -> void:
	overlay = surface
	underground = utilities
	for helper: Node3D in [overlay, underground]:
		if helper != null:
			if helper.get_parent() == null:
				world.add_child(helper)
	if overlay != null:
		overlay.bind_city(city)
	if underground != null:
		underground.bind_city(city)
	set_overlay(_overlay_kind)
	set_underground(_underground)

func set_overlay(kind: StringName) -> void:
	if kind == &"none":
		kind = &""
	if kind != &"" and not CityOverlaySampler.LAYERS.has(kind):
		return
	_overlay_kind = kind
	if overlay != null:
		overlay.set_layer(kind)
	_apply_analytics_visibility()

func set_underground(on: bool) -> void:
	_underground = on
	_apply_analytics_visibility()
	refresh_analytics()

func refresh_analytics() -> void:
	if overlay != null:
		overlay.refresh()
	if underground != null and _underground:
		underground.refresh()

func _apply_analytics_visibility() -> void:
	var surface_visible := not _underground and _overlay_kind == &""
	if buildings != null:
		buildings.visible = surface_visible
	if networks != null:
		networks.visible = surface_visible
	if mesh_batches != null:
		mesh_batches.set_domain_visible(&"buildings", surface_visible)
		mesh_batches.set_domain_visible(&"networks", surface_visible)
	if traffic != null:
		traffic.visible = surface_visible
	if feedback != null:
		feedback.visible = surface_visible
	if overlay != null:
		overlay.visible = _overlay_kind != &""
	if underground != null:
		underground.visible = _underground

## Pause only the visual clock; resuming continues the same ripple phase.
func set_water_animation(on: bool) -> void:
	water_style.enabled = on


## A shared surface tint leaves terrain meshes, queries and collision intact.
func set_tile_grid_visible(on: bool) -> void:
	tile_grid_visible = on
	water_style.material.set_shader_parameter("tile_grid_enabled", on)
