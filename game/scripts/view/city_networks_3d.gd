# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Procedural 3D road, rail, power and landscape surfaces laid over the city terrain.
class_name CityNetworks3D
extends Node3D

var _regions: Dictionary = {}
var _region_inputs: Dictionary = {}
var _region_initialized := false
var _faces := PackedVector3Array()
var _colors := PackedColorArray()
var _cells: Array[Vector2i] = []
var _deck_profiles: Dictionary = {}
var _approach_profiles: Dictionary = {}
## One detached input set for completed global profiles; clear expires it.
var _profile_state: Array = []
const HighwayGrades := preload("res://scripts/view/city_highway_grades_3d.gd")
const BridgeApproaches := preload("res://scripts/view/city_bridge_approaches_3d.gd")
var _road_tunnels: Dictionary = {}
var _drawing_tunnel := false
var _tunnel_faces := PackedVector3Array()
var _tunnel_colors := PackedColorArray()
var _tunnel_cells: Array[Vector2i] = []
var _tunnel_shell_faces := PackedVector3Array()
var _tunnel_shell_colors := PackedColorArray()
var _tunnel_shell_cells: Array[Vector2i] = []
const TUNNEL_RENDER_LAYER := 128
const RoadTunnels := preload("res://scripts/view/city_road_tunnels_3d.gd")
const TunnelFinish := preload("res://shaders/city_road_tunnel_finish.gdshader")
var _highway_stencils: Dictionary = {}
var _box_meshes: Dictionary = {}
## Box sizes this layer emitted, and (on the owner) how many live region
## layers use each shared size, so replaced regions release unused meshes.
var _box_sizes_used: Dictionary = {}
var _box_mesh_users: Dictionary = {}
var _structure_materials: Dictionary = {}
enum PhysicalRole { DETAIL, VERGE, SHOULDER, FLOOR, OBSTACLE }
## Packed physical patch records in emission order: two cell integers, one
## group, one role, one depth and three triangle points per patch. Packed
## storage avoids one Dictionary per surface triangle; physical_patches_in()
## materializes ordered records on demand.
var _physical_cells := PackedInt32Array()
var _physical_groups := PackedInt32Array()
var _physical_roles := PackedInt32Array()
var _physical_depths := PackedFloat64Array()
var _physical_triangles := PackedVector3Array()
var _physical_boxes: Array[Dictionary] = []
var _physical_obstacles := PackedVector3Array()
var _physical_cache: Dictionary = {}
## Exact incremental resolution over region layers (root only); regions rebuilt
## since the last resolution are named in _physical_dirty. Tests may disable it
## to compare with a full resolution.
const PhysicsIncremental := preload("res://scripts/view/city_network_physics_incremental.gd")
static var incremental_physics := true
var _physics_incremental: RefCounted = null
var _physical_dirty: Dictionary = {}
## Shared profile revision these decks/approaches were copied from.
var _deck_revision := -1
## Per-cell emission records of a region layer, in row-major visiting order:
## _span_index maps each visited cell to its record (-1: an empty cell that
## emits nothing); a record holds the size of every output array after the
## cell (SPAN_ARRAYS order plus the node spec list) and [entering group,
## entering depth, exit group, exit depth, highway blocks drawn]. A rebuilt region copies the spans of
## cells whose emission inputs cannot have changed and replays their node
## specs, which produces the same arrays and the same nodes as emitting them.
var _span_index := PackedInt32Array()
var _span_ends := PackedInt32Array()
var _span_states: Array = []
var _node_specs: Array = []
## Root: incremented whenever the deck, approach or tunnel profiles that
## region layers read change content; layers record their build generation.
var _profile_generation := 0
var _built_generation := -1
## Observational: cells copied and emitted by the last region rebuilds.
var reused_cells := 0
var emitted_cells := 0
## Tests may disable span reuse to compare with fresh emission.
static var cell_reuse := true
## A cell's emission reads inputs within REUSE_HALO cells (region inputs keep
## a three-cell halo; a highway block anchor reads its 2x2 block's halo).
const REUSE_HALO := 4
const SPAN_ARRAYS := 16
var _physical_group := 0
var _physical_depth := 0.0
## Pure local clipping templates: city height and transforms are sampled anew.
var _curved_templates: Dictionary = {}
## Build-local terrain facets: shared dry corners and their diagonal choice per
## cell. Filled only inside one synchronous _build_region and cleared after it,
## matching the read-only ground sampling scope.
var _facets: Dictionary = {}
## Memoized network masks; the mask of a (code, family) pair is constant.
static var _network_masks := PackedInt32Array()
const PIVOTS := {3: Vector2(1, 0), 6: Vector2(1, 1), 12: Vector2(0, 1), 9: Vector2(0, 0)}
const ANGLES := {3: PI, 6: -PI / 2.0, 12: 0.0, 9: PI / 2.0}
const PortalProfile := preload("res://scripts/view/city_portal_3d.gd")
const HighwayHeight := preload("res://scripts/view/city_highway_height_3d.gd")
const HIGHWAY_LANE_DIVIDER := Color(0.94, 0.94, 0.90)
const ROAD_WIDTH := 0.60
## Distribution poles at Explore scale (1 tile = 16 m): about 6.7 m to the
## wire over their own surface, a 0.38 m timber pole and a thin conductor.
## Highway crossings lift the same clearance above the elevated deck.
const POWER_WIRE_HEIGHT := 0.42
const POWER_POLE_WIDTH := 0.024
const POWER_WIRE_WIDTH := 0.015
## 6.08 metres at the Explore scale: clear tall traffic without cliff-like ramps.
const HIGHWAY_ELEVATION := 0.38
## Bridge drawing offsets are measured relative to the resolved span profile.
const BRIDGE_REFERENCE_ELEVATION := 0.65


## Connections encoded by one visible tile, including slopes and crossings.
static func network_mask(code: int, family: int) -> int:
	if _network_masks.is_empty():
		_network_masks.resize(Buildings.COUNT * 8)
		_network_masks.fill(-1)
	var key := (code << 3) | (family & 7)
	if code < 0 or code >= Buildings.COUNT or family < 0 or family > 7:
		return _network_mask_uncached(code, family)
	var cached := _network_masks[key]
	if cached >= 0: return cached
	var result := _network_mask_uncached(code, family)
	_network_masks[key] = result
	return result


static func _network_mask_uncached(code: int, family: int) -> int:
	if family == NetworkShapes.Family.HIGHWAY:
		match code:
			NetworkShapes.HIGHWAY_NS_ROAD_EW, NetworkShapes.HIGHWAY_NS_RAIL_EW, NetworkShapes.HIGHWAY_NS_POWER_EW, NetworkShapes.HIGHWAY_SLOPE_N, NetworkShapes.HIGHWAY_SLOPE_S:
				return NetworkShapes.NORTH | NetworkShapes.SOUTH
			NetworkShapes.HIGHWAY_EW_ROAD_NS, NetworkShapes.HIGHWAY_EW_RAIL_NS, NetworkShapes.HIGHWAY_EW_POWER_NS, NetworkShapes.HIGHWAY_SLOPE_W, NetworkShapes.HIGHWAY_SLOPE_E:
				return NetworkShapes.EAST | NetworkShapes.WEST
	var result := 0
	for mask: int in range(16):
		if NetworkShapes.shape_id(family, mask) == code:
			result = mask
	if result != 0:
		return result
	var axis := NetworkShapes.axis_for(code, family)
	if axis == NetworkShapes.AXIS_EW:
		return NetworkShapes.EAST | NetworkShapes.WEST
	if axis == NetworkShapes.AXIS_NS:
		return NetworkShapes.NORTH | NetworkShapes.SOUTH
	if family == NetworkShapes.Family.HIGHWAY:
		for mask: int in range(16):
			if NetworkShapes.highway_id(mask) == code:
				result = mask
	return result if result != 0 else NetworkShapes.NORTH | NetworkShapes.SOUTH


## Remove the last projection, leaving city data untouched.
func clear() -> void:
	_profile_state = []
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_regions.clear()
	_region_inputs.clear()
	_region_initialized = false
	_faces.clear()
	_colors.clear()
	_cells.clear()
	_tunnel_shell_faces.clear()
	_tunnel_shell_colors.clear()
	_tunnel_shell_cells.clear()
	_tunnel_faces.clear()
	_tunnel_colors.clear()
	_tunnel_cells.clear()
	_road_tunnels.clear()
	_drawing_tunnel = false
	_deck_profiles.clear()
	_approach_profiles.clear()
	_highway_stencils.clear()
	_box_meshes.clear()
	_box_sizes_used.clear()
	_box_mesh_users.clear()
	_structure_materials.clear()
	clear_physical_patches()
	_physical_boxes.clear()
	_physical_obstacles.clear()
	_physical_cache.clear()
	_physical_dirty.clear()
	if _physics_incremental != null: _physics_incremental.reset()
	_deck_revision = -1
	_physical_group = 0
	_physical_depth = 0.0
	_curved_templates.clear()
	_facets.clear()


## Project every surface network; crossings draw both families.
func rebuild(city: City) -> void:
	clear()
	_prepare_bridge_decks(city)
	_road_tunnels = RoadTunnels.profiles(city)
	_build_region(city, Rect2i(0, 0, City.WIDTH, City.HEIGHT))
	_update_tunnel_light()


func _build_region(city: City, region: Rect2i, previous: CityNetworks3D = null, changed_cells: Dictionary = {}) -> void:
	var drawn_blocks: Dictionary = {}
	var reuse := previous != null and previous._span_index.size() == region.get_area()
	_span_index = PackedInt32Array()
	_span_ends = PackedInt32Array()
	_span_states = []
	_node_specs = []
	reused_cells = 0
	emitted_cells = 0
	var visit := 0
	var affected := _affected_cells(changed_cells) if reuse else {}
	var codes := city.building.data
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			var cell := Vector2i(x, y)
			# Empty ground and developed lots without a bore emit nothing and
			# leave the drawing state untouched.
			var code: int = codes[y * City.WIDTH + x]
			if (code == Buildings.NONE or code >= Buildings.RES_1X1_FIRST) and not _road_tunnels.has(cell):
				_span_index.append(-1)
				visit += 1
				continue
			var entering := [_physical_group, _physical_depth]
			var record: int = previous._span_index[visit] if reuse else -1
			if record >= 0 and not affected.has(cell) and previous._span_states[record][0] == _physical_group and previous._span_states[record][1] == _physical_depth:
				_copy_cell(city, previous, record)
				for block: Vector2i in previous._span_states[record][4]: drawn_blocks[block] = true
				_record_cell(entering, previous._span_states[record][4])
				reused_cells += 1
				visit += 1
				continue
			emitted_cells += 1
			var blocks_before := drawn_blocks.size()
			_emit_cell(city, region, cell, drawn_blocks)
			var drawn: Array = []
			if drawn_blocks.size() != blocks_before: drawn = drawn_blocks.keys().slice(blocks_before)
			_record_cell(entering, drawn)
			visit += 1
	_finish_region()


## Size of every recorded output array, in SPAN_ARRAYS order.
func _span_arrays() -> Array:
	return [_faces, _colors, _cells, _tunnel_faces, _tunnel_colors, _tunnel_cells, _tunnel_shell_faces, _tunnel_shell_colors, _tunnel_shell_cells,
		_physical_cells, _physical_groups, _physical_roles, _physical_depths, _physical_triangles, _physical_boxes, _physical_obstacles]


func _record_cell(entering: Array, blocks: Array) -> void:
	_span_index.append(_span_states.size())
	for array: Variant in _span_arrays(): _span_ends.append(array.size())
	_span_ends.append(_node_specs.size())
	_span_states.append([entering[0], entering[1], _physical_group, _physical_depth, blocks])


## Appends one previously emitted cell record: its array spans, then its nodes.
func _copy_cell(city: City, previous: CityNetworks3D, visit: int) -> void:
	var width := SPAN_ARRAYS + 1
	var arrays := _span_arrays()
	var sources := previous._span_arrays()
	for k: int in SPAN_ARRAYS:
		var begin: int = previous._span_ends[(visit-1)*width+k] if visit > 0 else 0
		var end: int = previous._span_ends[visit*width+k]
		if end > begin: arrays[k].append_array(sources[k].slice(begin, end))
	var first: int = previous._span_ends[(visit-1)*width+SPAN_ARRAYS] if visit > 0 else 0
	for i: int in range(first, previous._span_ends[visit*width+SPAN_ARRAYS]):
		var spec: Array = previous._node_specs[i]
		match spec[0]:
			&"box": _box(spec[1], spec[2], spec[3], false)
			&"beam":
				var group := _physical_group
				_physical_group = spec[5]
				_beam(spec[1], spec[2], spec[3], spec[4], false)
				_physical_group = group
			&"palms": _palms(city, spec[1], spec[2])
	_physical_group = previous._span_states[visit][2]
	_physical_depth = previous._span_states[visit][3]


static func _affected_cells(changed_cells: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for cell: Vector2i in changed_cells:
		for dy: int in range(-REUSE_HALO, REUSE_HALO + 1):
			for dx: int in range(-REUSE_HALO, REUSE_HALO + 1): result[cell + Vector2i(dx, dy)] = true
	return result


## Cells whose region input record differs (codes, flags, corners, heights,
## terrain, floods, subway masks, or a touching terrain vertex).
static func _changed_input_cells(region: Rect2i, old: Array, now: Array) -> Dictionary:
	var result: Dictionary = {}
	var bounds := region.grow(3).intersection(Rect2i(0,0,City.WIDTH,City.HEIGHT))
	var old_cells: PackedInt32Array = old[0]
	var cells: PackedInt32Array = now[0]
	if old_cells.size() != cells.size() or (old[1] as PackedByteArray).size() != (now[1] as PackedByteArray).size():
		for y: int in range(bounds.position.y, bounds.end.y):
			for x: int in range(bounds.position.x, bounds.end.x): result[Vector2i(x, y)] = true
		return result
	var row := bounds.size.x * 7
	for y: int in bounds.size.y:
		if old_cells.slice(y*row, (y+1)*row) == cells.slice(y*row, (y+1)*row): continue
		for x: int in bounds.size.x:
			var at := (y*bounds.size.x+x)*7
			if old_cells.slice(at, at+7) != cells.slice(at, at+7): result[bounds.position + Vector2i(x, y)] = true
	var old_vertices: PackedByteArray = old[1]
	var vertices: PackedByteArray = now[1]
	if old_vertices != vertices:
		var columns := bounds.size.x + 1
		for v: int in vertices.size():
			if old_vertices[v] == vertices[v]: continue
			for dy: int in [-1, 0]:
				for dx: int in [-1, 0]: result[bounds.position + Vector2i(v % columns + dx, v / columns + dy)] = true
	return result


func _emit_cell(city: City, region: Rect2i, cell: Vector2i, drawn_blocks: Dictionary) -> void:
	var x := cell.x
	var y := cell.y
	if _road_tunnels.has(cell): _road_tunnel(city,cell,_road_tunnels[cell])
	var code := city.building.at(x, y)
	if code == Buildings.NONE or code >= Buildings.RES_1X1_FIRST:
		return
	if code < Buildings.POWER_LINE_FIRST:
		if code >= Buildings.TREES_1:
			_palms(city, cell, code)
		else:
			_rect(city, cell, Rect2(0.1, 0.1, 0.8, 0.8), Color(0.42, 0.34, 0.26), 0.04)
		return
	if NetworkShapes.is_onramp(code):
		_ramp(city, cell, code)
		return
	if NetworkShapes.is_tunnel(code) or NetworkShapes.is_subway_portal(code):
		if not _road_tunnels.has(cell): _portal(city, cell)
		return
	if code >= NetworkShapes.HIGHWAY_CORNER_NE and code <= NetworkShapes.HIGHWAY_JUNCTION:
		var block := highway_footprint(city, cell, code)
		if block.x >= 0:
			if region.has_point(block) and not drawn_blocks.has(block):
				_highway_block(city, block, code)
				drawn_blocks[block] = true
			return
	var bridge := _deck_profiles.has(cell)
	if bridge:
		_bridge_structure(city, cell, code)
	elif NetworkShapes.is_highway(code):
		_highway_supports(city, cell, code)
	for family: int in [NetworkShapes.Family.ROAD, NetworkShapes.Family.RAIL, NetworkShapes.Family.HIGHWAY, NetworkShapes.Family.POWER]:
		if not NetworkShapes.in_family(code, family):
			continue
		var mask := network_mask(code, family)
		if bridge:
			mask = NetworkShapes.EAST | NetworkShapes.WEST if _deck_profiles[cell].ew else NetworkShapes.NORTH | NetworkShapes.SOUTH
		var elevation := BRIDGE_REFERENCE_ELEVATION if bridge else HIGHWAY_ELEVATION if family == NetworkShapes.Family.HIGHWAY else 0.04
		if family == NetworkShapes.Family.RAIL:
			elevation += 0.015
		_draw_network(city, cell, family, mask, elevation)


func _finish_region() -> void:
	_facets.clear()
	if not _faces.is_empty():
		var node := MeshInstance3D.new()
		node.mesh = CityGeometry3D.mesh_from_faces(_faces, _colors, 0.025, CityGeometry3D.SurfaceKind.NETWORK)
		add_child(node)
	if not _tunnel_faces.is_empty():
		var node := MeshInstance3D.new()
		node.name = "RoadTunnelSurface"
		node.layers = TUNNEL_RENDER_LAYER
		node.mesh = CityGeometry3D.mesh_from_faces(_tunnel_faces,_tunnel_colors,.025,CityGeometry3D.SurfaceKind.NETWORK)
		add_child(node)
		_faces.append_array(_tunnel_faces)
		_colors.append_array(_tunnel_colors)
		_cells.append_array(_tunnel_cells)

	if not _tunnel_shell_faces.is_empty():
		var node := MeshInstance3D.new()
		node.name = "RoadTunnelShell"
		node.layers = TUNNEL_RENDER_LAYER
		node.mesh = CityGeometry3D.mesh_from_faces(_tunnel_shell_faces,_tunnel_shell_colors)
		# Concrete uses world-aligned texture at the Explore scale. One shared
		# finish keeps grain continuous across cells and batching boundaries.
		var material := _structure_materials.get(&"road_tunnel_shell") as ShaderMaterial
		if material == null:
			material = ShaderMaterial.new()
			material.shader = TunnelFinish
			_structure_materials[&"road_tunnel_shell"] = material
		node.material_override = material
		add_child(node)
		_faces.append_array(_tunnel_shell_faces)
		_colors.append_array(_tunnel_shell_colors)
		_cells.append_array(_tunnel_shell_cells)


func _update_tunnel_light() -> void:
	var light := get_node_or_null("RoadTunnelFill") as DirectionalLight3D
	if _road_tunnels.is_empty():
		if light != null:
			remove_child(light)
			light.queue_free()
		return
	if light != null: return
	light = DirectionalLight3D.new()
	light.name = "RoadTunnelFill"
	light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	light.light_cull_mask = TUNNEL_RENDER_LAYER
	light.light_energy = .65
	light.shadow_enabled = false
	light.rotation_degrees = Vector3(-65,25,0)
	add_child(light)


## Compare whole-span profiles before region work: a distant bank can change
## every bridge deck/cable along that span, even across several chunks.
func update_regions(city: City, requested: Array[Rect2i], chunk_size: int = 16) -> Array[Rect2i]:
	var next_profile_state := _profile_inputs(city)
	var profiles_changed := next_profile_state != _profile_state
	var old_profiles := _deck_profiles
	var old_approaches := _approach_profiles
	var old_tunnels := _road_tunnels
	if profiles_changed:
		# Own a copy: clear() empties this table while the view retains its state.
		if _profile_state.is_empty() or _tunnels_affected(_profile_state, next_profile_state):
			_road_tunnels = CityGeometry3D.road_tunnel_profiles(city).duplicate(true)
			if _road_tunnels != old_tunnels: _profile_generation += 1
		# Shared profiles reused exactly (same revision) keep this layer's
		# copies; a cleared or fresh layer always prepares its own.
		shared_bridge_profiles(city)
		if _profile_state.is_empty() or _deck_revision != _shared_profile_revision:
			old_profiles = _deck_profiles.duplicate(true)
			_deck_profiles.clear()
			_prepare_bridge_decks(city)
			if _deck_profiles != old_profiles or _approach_profiles != old_approaches: _profile_generation += 1
		_profile_state = next_profile_state
	var dirty: Dictionary = {}
	var previous_inputs: Dictionary = {}
	for region: Rect2i in requested:
		var inputs := _network_inputs(city, region)
		if _region_inputs.get(region.position, []) == inputs: continue
		if _region_inputs.has(region.position): previous_inputs[region.position] = _region_inputs[region.position]
		_region_inputs[region.position] = inputs
		var old: CityNetworks3D = _regions.get(region.position)
		if old == null or not old._faces.is_empty() or old.get_child_count() > 0 or _contains_network(city, region):
			dirty[region.position] = region
	for cell: Vector2i in old_profiles:
		if old_profiles[cell] != _deck_profiles.get(cell, {}):
			var origin := Vector2i(cell.x / chunk_size, cell.y / chunk_size) * chunk_size
			dirty[origin] = Rect2i(origin, Vector2i.ONE * chunk_size)
	for cell: Vector2i in _deck_profiles:
		if _deck_profiles[cell] != old_profiles.get(cell, {}):
			var origin := Vector2i(cell.x / chunk_size, cell.y / chunk_size) * chunk_size
			dirty[origin] = Rect2i(origin, Vector2i.ONE * chunk_size)
	for collection: Dictionary in [old_approaches,_approach_profiles]:
		for cell: Vector2i in collection:
			if old_approaches.get(cell,{}) == _approach_profiles.get(cell,{}): continue
			var origin := Vector2i(cell.x/chunk_size,cell.y/chunk_size)*chunk_size
			dirty[origin] = Rect2i(origin,Vector2i.ONE*chunk_size)
	# A broken bore or a changed distant mouth invalidates every affected cell.
	for collection: Dictionary in [old_tunnels,_road_tunnels]:
		for cell: Vector2i in collection:
			if old_tunnels.get(cell,{}) == _road_tunnels.get(cell,{}): continue
			var origin := Vector2i(cell.x/chunk_size,cell.y/chunk_size)*chunk_size
			dirty[origin] = Rect2i(origin,Vector2i.ONE*chunk_size)
	if not _region_initialized:
		_faces.clear()
		_colors.clear()
		_cells.clear()
		for child: Node in get_children():
			remove_child(child)
			child.queue_free()
		_regions.clear()
		_box_mesh_users.clear()
		_box_meshes.clear()
		for y: int in range(0, City.HEIGHT, chunk_size):
			for x: int in range(0, City.WIDTH, chunk_size):
				var origin := Vector2i(x,y)
				dirty[origin] = Rect2i(origin, Vector2i.ONE * chunk_size)
		_region_initialized = true
	if dirty.is_empty(): return []
	for origin: Vector2i in dirty:
		var region_inputs := _network_inputs(city, dirty[origin])
		if not previous_inputs.has(origin) and _region_inputs.has(origin): previous_inputs[origin] = _region_inputs[origin]
		_region_inputs[origin] = region_inputs
		var released: Dictionary = {}
		var previous: CityNetworks3D = null
		if _regions.has(origin):
			var old: CityNetworks3D = _regions[origin]
			released = old._box_sizes_used
			remove_child(old)
			old.queue_free()
			if cell_reuse and old._built_generation == _profile_generation and previous_inputs.has(origin): previous = old
		var region_layer := CityNetworks3D.new()
		region_layer.set_meta("batch_region", dirty[origin])
		# A region layer is replaced whole when its inputs change; its meshes and
		# palm shells never move afterwards, so batching and ceilings scan it once.
		region_layer.set_meta("batch_immutable", true)
		region_layer._deck_profiles = _deck_profiles
		region_layer._approach_profiles = _approach_profiles
		region_layer._road_tunnels = _road_tunnels
		# Mesh and material resources are shared across region chunks so
		# the 32-cell GPU batcher can merge equivalent neighboring structures.
		region_layer._box_meshes = _box_meshes
		region_layer._structure_materials = _structure_materials
		add_child(region_layer)
		region_layer._built_generation = _profile_generation
		var changed_cells: Dictionary = {}
		if previous != null: changed_cells = _changed_input_cells(dirty[origin], previous_inputs[origin], region_inputs)
		region_layer._build_region(city, dirty[origin], previous, changed_cells)
		_regions[origin] = region_layer
		for size: Vector3 in region_layer._box_sizes_used:
			_box_mesh_users[size] = int(_box_mesh_users.get(size, 0)) + 1
		for size: Vector3 in released:
			var users := int(_box_mesh_users.get(size, 0)) - 1
			if users > 0:
				_box_mesh_users[size] = users
			else:
				_box_mesh_users.erase(size)
				_box_meshes.erase(size)
	for origin: Vector2i in dirty: _physical_dirty[origin] = true
	# Resolve physical surfaces globally to cancel shared deck boundaries. Region
	# splitting must never introduce an invisible wall at a chunk boundary.
	var previous_patches: Array = [_physical_cells, _physical_groups, _physical_roles, _physical_depths, _physical_triangles, _physical_boxes, _physical_obstacles]
	var previous_cache := _physical_cache
	_physical_cells = PackedInt32Array()
	_physical_groups = PackedInt32Array()
	_physical_roles = PackedInt32Array()
	_physical_depths = PackedFloat64Array()
	_physical_triangles = PackedVector3Array()
	_physical_boxes = []
	_physical_obstacles = PackedVector3Array()
	_physical_cache = {}
	var origins: Array = _regions.keys()
	origins.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for origin: Vector2i in origins:
		var part: CityNetworks3D = _regions[origin]
		_physical_cells.append_array(part._physical_cells)
		_physical_groups.append_array(part._physical_groups)
		_physical_roles.append_array(part._physical_roles)
		_physical_depths.append_array(part._physical_depths)
		_physical_triangles.append_array(part._physical_triangles)
		_physical_boxes.append_array(part._physical_boxes)
		_physical_obstacles.append_array(part._physical_obstacles)
	# A region rebuilt for visual-only changes (palms, colours) leaves every
	# physical input unchanged, so the resolved surfaces stay valid.
	if not previous_cache.is_empty() and [_physical_cells, _physical_groups, _physical_roles, _physical_depths, _physical_triangles, _physical_obstacles] == [previous_patches[0], previous_patches[1], previous_patches[2], previous_patches[3], previous_patches[4], previous_patches[6]]:
		_physical_cache = previous_cache
		# Boxes pass through the resolver unchanged; floors and obstacles depend
		# only on the identical patches and obstacle inputs.
		if _physical_boxes != previous_patches[5]:
			_physical_cache = previous_cache.duplicate()
			_physical_cache["physical_boxes"] = _physical_boxes.duplicate(true)
	var changed: Array[Rect2i] = []
	for region: Rect2i in dirty.values(): changed.append(region)
	_update_tunnel_light()
	return changed


## Detached inputs, normalized to what this projection reads. A developed
## building contributes no procedural surface, so its code/lot flags are zero.
## Include the three-cell dependency halo for odd highway footprints and cubic
## corners; nonlocal bridge dependencies are compared separately above.
static func _network_inputs(city: City, region: Rect2i) -> Array:
	var bounds := region.grow(3).intersection(Rect2i(0,0,City.WIDTH,City.HEIGHT))
	var cells := PackedInt32Array()
	cells.resize(bounds.size.x*bounds.size.y*7)
	var offset := 0
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var index := y*City.WIDTH+x
			var code: int = city.building.data[index]
			if code >= Buildings.RES_1X1_FIRST: code = Buildings.NONE
			cells[offset] = code
			cells[offset+1] = city.flags.data[index] & RotationMapper.AXIS_FLAG if code != Buildings.NONE else 0
			cells[offset+2] = Zones.corners(city.zone.data[index]) if code >= NetworkShapes.HIGHWAY_CORNER_NE and code <= NetworkShapes.HIGHWAY_JUNCTION else 0
			cells[offset+3] = city.altitude.data[index]
			cells[offset+4] = city.terrain.data[index]
			cells[offset+5] = int(city.flood_overlay.has(Vector2i(x,y)))
			# Portal mouths consult neighboring subway approaches; pipe-only
			# changes have no effect on this visible/physical surface projection.
			cells[offset+6] = NetworkShapes.underground_mask(city.underground.data[index],NetworkShapes.Family.SUBWAY)
			offset += 7
	var vertices := PackedByteArray()
	if city.terrain_surface is TerrainSurface:
		for y: int in range(bounds.position.y, bounds.end.y+1):
			var start := y*TerrainSurface.VERTS_X+bounds.position.x
			vertices.append_array(city.terrain_surface.vertices.slice(start,start+bounds.size.x+1))
	return [cells,vertices]


static func _contains_network(city: City, region: Rect2i) -> bool:
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			var code := city.building.at(x,y)
			if code > Buildings.NONE and code < Buildings.RES_1X1_FIRST: return true
	return false


func _draw_network(city: City, cell: Vector2i, family: int, mask: int, elevation: float) -> void:
	_physical_group = 100 if _drawing_tunnel else family
	_physical_depth = 0.095 if _deck_profiles.has(cell) or family == NetworkShapes.Family.HIGHWAY else 0.0
	var rail := family == NetworkShapes.Family.RAIL
	var power := family == NetworkShapes.Family.POWER
	if power:
		var code := city.building.atv(cell)
		var supports: Array[Vector2] = [Vector2(0.5, 0.5)]
		var wire := elevation + POWER_WIRE_HEIGHT
		if NetworkShapes.in_family(code, NetworkShapes.Family.HIGHWAY) and not _deck_profiles.has(cell):
			wire = HIGHWAY_ELEVATION + POWER_WIRE_HEIGHT
		for transport: int in [NetworkShapes.Family.ROAD, NetworkShapes.Family.RAIL, NetworkShapes.Family.HIGHWAY]:
			if not NetworkShapes.in_family(code, transport):
				continue
			# Crossing wires stay connected through the center; only the poles
			# move onto the two verges, beyond the full width of the roadway.
			var margin := 0.02 if transport == NetworkShapes.Family.HIGHWAY else 0.10
			if mask == 10:
				supports.assign([Vector2(margin, 0.5), Vector2(1.0 - margin, 0.5)])
			else:
				supports.assign([Vector2(0.5, margin), Vector2(0.5, 1.0 - margin)])
			break
		for offset: Vector2 in supports:
			var top := _point(city, cell, offset, wire)
			var bottom := CityGeometry3D.point_on_ground(city, cell, offset).y
			_box(Vector3(top.x, (bottom + top.y) / 2.0, top.z),
				Vector3(POWER_POLE_WIDTH, maxf(0.01, top.y - bottom), POWER_POLE_WIDTH), Color(0.5, 0.43, 0.34))
		_draw_path(city, cell, mask, POWER_WIRE_WIDTH, Color(0.23, 0.22, 0.21), wire)
		return
	var bend := mask in [3, 6, 9, 12]
	if rail:
		_draw_path(city, cell, mask, 0.59, Color(0.51, 0.50, 0.45), elevation, PhysicalRole.FLOOR)
		_rail_berm(city, cell, mask, elevation)
		_rail_details(city, cell, mask, elevation + 0.008)
		return
	# Ground-level road cells carry a full-width sand verge.
	if family == NetworkShapes.Family.ROAD and elevation < 0.1 and not _drawing_tunnel:
		_rect(city, cell, Rect2(0, 0, 1, 1), Color(0.77, 0.63, 0.47), elevation - 0.016, PhysicalRole.VERGE)
	var width := 0.92 if family == NetworkShapes.Family.HIGHWAY else ROAD_WIDTH
	_draw_path(city, cell, mask, width + 0.075, Color(0.74, 0.72, 0.65), elevation - 0.008, PhysicalRole.SHOULDER)
	_draw_path(city, cell, mask, width, Color(0.34, 0.38, 0.40), elevation, PhysicalRole.FLOOR)
	if family == NetworkShapes.Family.ROAD and not _deck_profiles.has(cell) and not _drawing_tunnel:
		# Close each raised layer down to the terrain without moving its travel
		# height; top-only sheets would expose daylight at street level.
		_grounded_outline(city,cell,_rect_polygon(Rect2(0,0,1,1)),Color(.77,.63,.47),elevation-.016)
		_grounded_path(city,cell,mask,width+.075,Color(.74,.72,.65),elevation-.008)
		_grounded_path(city,cell,mask,width,Color(.34,.38,.40),elevation)
	# A highway tile is one two-lane, one-way carriageway. White separates
	# those same-direction lanes; two-way local roads use yellow centers.
	var stripe := HIGHWAY_LANE_DIVIDER if family == NetworkShapes.Family.HIGHWAY else Color(0.86, 0.72, 0.36)
	if bend:
		for i: int in range(0, 12, 3):
			_arc(city, cell, mask, 0.022, stripe, elevation + 0.006, float(i) / 12.0, float(i + 1) / 12.0)
	elif mask == 5 or mask == 10:
		for i: int in 4:
			var start := 0.06 + i * 0.25
			var dash := Rect2(0.489, start, 0.022, 0.125) if mask == 5 else Rect2(start, 0.489, 0.125, 0.022)
			_rect(city, cell, dash, stripe, elevation + 0.006)
	else:
		# Keep the center of a junction clear of lane-marking overlap.
		for direction: int in 4:
			if mask & (1 << direction):
				var dash: Rect2 = [Rect2(0.489, 0.045, 0.022, 0.13), Rect2(0.825, 0.489, 0.13, 0.022),
					Rect2(0.489, 0.825, 0.022, 0.13), Rect2(0.045, 0.489, 0.13, 0.022)][direction]
				_rect(city, cell, dash, stripe, elevation + 0.006)


func _grounded_path(city: City, cell: Vector2i, mask: int, width: float, color: Color, elevation: float) -> void:
	if mask not in [3,6,9,12]:
		_grounded_outline(city,cell,_rail_berm_outline(mask,(1-width)*.5,(1+width)*.5),color,elevation)
		return
	var pivot: Vector2 = PIVOTS[mask]
	var angle: float = ANGLES[mask]
	var outline: Array[Vector2] = []
	for i: int in range(17):
		var a := angle-i*PI/32.0
		outline.append(pivot+Vector2(cos(a),sin(a))*(.5+width*.5))
	for i: int in range(16,-1,-1):
		var a := angle-i*PI/32.0
		outline.append(pivot+Vector2(cos(a),sin(a))*(.5-width*.5))
	_grounded_outline(city,cell,outline,color,elevation)


func _grounded_outline(city: City, cell: Vector2i, outline: Array[Vector2], color: Color, elevation: float) -> void:
	var facet := _facet(city, cell)
	var corners: PackedVector3Array = facet[0]
	var diagonal: bool = facet[1]
	for i: int in outline.size():
		var a := outline[i].clamp(Vector2.ZERO,Vector2.ONE)
		var b := outline[(i+1)%outline.size()].clamp(Vector2.ZERO,Vector2.ONE)
		if a.distance_squared_to(b)<.00000001: continue
		var stops: Array[float] = [0.0,1.0]
		var da := a.x-a.y if diagonal else a.x+a.y-1.0
		var db := b.x-b.y if diagonal else b.x+b.y-1.0
		if da*db<0: stops.append(da/(da-db))
		# Bridge approach sides share the curved pavement mesh grid.
		for axis: int in 2:
			if absf(b[axis]-a[axis])<.000001: continue
			var count := 16
			if _approach_profiles.has(cell):
				var profile: Dictionary = _approach_profiles[cell]
				count = BridgeApproaches.subdivisions(profile)[axis]
			for n: int in range(1,count) if _approach_profiles.has(cell) else []:
				var t := (n/float(count)-a[axis])/(b[axis]-a[axis])
				if t>0 and t<1: stops.append(t)
		stops.sort()
		for j: int in range(stops.size()-1):
			var p := a.lerp(b,stops[j]);var q := a.lerp(b,stops[j+1])
			if p.distance_squared_to(q)<.0000000001: continue
			var low_p := CityGeometry3D.point_over_facet(corners,diagonal,cell,p)-Vector3.UP*.002
			var low_q := CityGeometry3D.point_over_facet(corners,diagonal,cell,q)-Vector3.UP*.002
			_world_quad(cell,_point(city,cell,p,elevation),_point(city,cell,q,elevation),low_p,low_q,color,PhysicalRole.OBSTACLE)


## Ground rail keeps its running height, with a solid sloping ballast shoulder
## down to the actual terrain facets. Bridge decks and wet spans stay open.
func _rail_berm(city: City, cell: Vector2i, mask: int, elevation: float) -> void:
	if _deck_profiles.has(cell) or city.is_water(cell.x,cell.y): return
	if mask in [3,6,9,12]:
		var pivot: Vector2 = PIVOTS[mask]
		var angle: float = ANGLES[mask]
		for i: int in 16:
			var a0 := angle-float(i)/16.0*PI*.5
			var a1 := angle-float(i+1)/16.0*PI*.5
			var d0 := Vector2(cos(a0),sin(a0)); var d1 := Vector2(cos(a1),sin(a1))
			for side: float in [-1.0,1.0]:
				var upper := .5+side*.295; var lower := .5+side*.395
				_rail_berm_band(city,cell,pivot+d0*upper,pivot+d1*upper,pivot+d0*lower,pivot+d1*lower,elevation)
		for at: float in [angle,angle-PI*.5]:
			var direction := Vector2(cos(at),sin(at))
			_rail_berm_band(city,cell,pivot+direction*.205,pivot+direction*.795,pivot+direction*.105,pivot+direction*.895,elevation)
		return
	var upper := _rail_berm_outline(mask,.205,.795)
	var lower := _rail_berm_outline(mask,.105,.895)
	for i: int in upper.size():
		var next := (i+1)%upper.size()
		_rail_berm_band(city,cell,upper[i],upper[next],lower[i],lower[next],elevation)


func _rail_berm_outline(mask: int, low: float, high: float) -> Array[Vector2]:
	var points: Array[Vector2] = [Vector2(low,low)]
	if mask & NetworkShapes.NORTH: points.append_array([Vector2(low,0),Vector2(high,0)])
	points.append(Vector2(high,low))
	if mask & NetworkShapes.EAST: points.append_array([Vector2(1,low),Vector2(1,high)])
	points.append(Vector2(high,high))
	if mask & NetworkShapes.SOUTH: points.append_array([Vector2(high,1),Vector2(low,1)])
	points.append(Vector2(low,high))
	if mask & NetworkShapes.WEST: points.append_array([Vector2(0,high),Vector2(0,low)])
	return points


func _rail_berm_band(city: City, cell: Vector2i, a: Vector2, b: Vector2, c: Vector2, d: Vector2, elevation: float) -> void:
	# Snap arc endpoint round-off to tile borders, never across another lot.
	a = a.clamp(Vector2.ZERO,Vector2.ONE); b = b.clamp(Vector2.ZERO,Vector2.ONE)
	c = c.clamp(Vector2.ZERO,Vector2.ONE); d = d.clamp(Vector2.ZERO,Vector2.ONE)
	var earth := Color(.44,.40,.33)
	if absf((b-a).cross(c-a))<.00000001 and absf((d-b).cross(c-b))<.00000001:
		var direction := Vector2i.ZERO
		if absf(a.x)<.00001 and absf(b.x)<.00001: direction = Vector2i.LEFT
		elif absf(a.x-1)<.00001 and absf(b.x-1)<.00001: direction = Vector2i.RIGHT
		elif absf(a.y)<.00001 and absf(b.y)<.00001: direction = Vector2i.UP
		elif absf(a.y-1)<.00001 and absf(b.y-1)<.00001: direction = Vector2i.DOWN
		var neighbor := cell+direction
		if direction!=Vector2i.ZERO and city.in_bounds(neighbor.x,neighbor.y):
			var code := city.building.atv(neighbor)
			if NetworkShapes.in_family(code,NetworkShapes.Family.RAIL):
				var other := network_mask(code,NetworkShapes.Family.RAIL)
				if NetworkShapes.is_rail_bridge(code): other = 10 if city.flags.atv(neighbor)&RotationMapper.AXIS_FLAG else 5
				var incoming := [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT].find(-direction)
				if other & (1<<incoming): return
		_world_quad(cell,_point(city,cell,a,elevation),_point(city,cell,b,elevation),
			_point(city,cell,c,-.002),_point(city,cell,d,-.002),earth,PhysicalRole.OBSTACLE)
		return
	# Interpolate the berm's lift over each triangle, splitting at the same
	# terrain crease as the rail top so no hillside slit remains underneath.
	var diagonal: bool = _facet(city, cell)[1]
	for triangle: Array in [[a,b,c,elevation,elevation,-.002],[b,d,c,elevation,-.002,-.002]]:
		var p: Vector2 = triangle[0]; var q: Vector2 = triangle[1]; var r: Vector2 = triangle[2]
		var area := (q-p).cross(r-p)
		if absf(area)<.00000001: continue
		var polygon: Array[Vector2] = [p,q,r]
		for positive: bool in [false,true]:
			var clipped := _clip_facet(polygon,diagonal,positive)
			var points: Array[Vector3] = []
			for offset: Vector2 in clipped:
				var v := (offset-p).cross(r-p)/area; var w := (q-p).cross(offset-p)/area
				var lift: float = triangle[3]+(triangle[4]-triangle[3])*v+(triangle[5]-triangle[3])*w
				points.append(_point(city,cell,offset,lift))
			for i: int in range(1,points.size()-1):
				_world_quad(cell,points[0],points[i],points[i+1],points[i+1],earth,PhysicalRole.SHOULDER)


func _rail_details(city: City, cell: Vector2i, mask: int, elevation: float) -> void:
	var steel := Color(0.72, 0.75, 0.71)
	var timber := Color(0.40, 0.33, 0.26)
	if mask in [3, 6, 9, 12]:
		for i: int in 7:
			var t := (float(i) + 0.5) / 7.0
			_arc(city, cell, mask, 0.5, timber, elevation, t - 0.012, t + 0.012)
		_arc(city, cell, mask, 0.026, steel, elevation + 0.006, 0.0, 1.0, 0.344)
		_arc(city, cell, mask, 0.026, steel, elevation + 0.006, 0.0, 1.0, 0.656)
		return
	for direction: int in 4:
		if not mask & (1 << direction):
			continue
		var vertical := direction % 2 == 0
		var half := 0.0 if direction in [0, 3] else 0.5
		for i: int in 4:
			var at := half + 0.04 + i * 0.125
			var tie := Rect2(0.25, at, 0.5, 0.026) if vertical else Rect2(at, 0.25, 0.026, 0.5)
			_rect(city, cell, tie, timber, elevation)
		for across: float in [0.344, 0.656]:
			var track := Rect2(across - 0.013, half, 0.026, 0.5) if vertical else Rect2(half, across - 0.013, 0.5, 0.026)
			_rect(city, cell, track, steel, elevation + 0.006)


func _arc(city: City, cell: Vector2i, mask: int, width: float, color: Color, elevation: float,
		start: float = 0.0, end: float = 1.0, radius: float = 0.5, role: int = PhysicalRole.DETAIL) -> void:
	var pivot: Vector2 = PIVOTS[mask]
	var angle: float = ANGLES[mask]
	var steps := maxi(1, ceili((end - start) * 16.0))
	for i: int in steps:
		var a0 := angle - (start + (end - start) * float(i) / steps) * PI / 2.0
		var a1 := angle - (start + (end - start) * float(i + 1) / steps) * PI / 2.0
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		_surface_polygon(city, cell, [pivot + d0 * (radius - width / 2.0),
			pivot + d0 * (radius + width / 2.0), pivot + d1 * (radius + width / 2.0),
			pivot + d1 * (radius - width / 2.0)], color, elevation, role)


func _point(city: City, cell: Vector2i, offset: Vector2, elevation: float) -> Vector3:
	if _drawing_tunnel:
		var profile: Dictionary = _road_tunnels[cell]
		var t: float = (offset-profile.outside).dot(profile.inward)
		return Vector3(cell.x+offset.x,lerpf(profile.floor_start,profile.floor_end,t)+elevation-.04,cell.y+offset.y)
	if _approach_profiles.has(cell) and _physical_group==int(_approach_profiles[cell].family):
		return Vector3(cell.x+offset.x,BridgeApproaches.height(_approach_profiles[cell],offset)+elevation-(HIGHWAY_ELEVATION if _physical_group==NetworkShapes.Family.HIGHWAY else .04),cell.y+offset.y)
	if _deck_profiles.has(cell):
		var profile: Dictionary = _deck_profiles[cell]
		var t: float = offset.x if profile.ew else offset.y
		return Vector3(cell.x+offset.x,bridge_height(profile,t)+elevation-BRIDGE_REFERENCE_ELEVATION,cell.y+offset.y)
	if _physical_group == NetworkShapes.Family.HIGHWAY:
		return Vector3(cell.x+offset.x,HighwayHeight.height(_highway_stencil(city,cell),offset)+elevation,cell.y+offset.y)
	var facet := _facet(city, cell)
	var result := CityGeometry3D.point_over_facet(facet[0], facet[1], cell, offset)
	result.y += elevation
	return result


## Shared dry corners and diagonal choice for one cell of the current build.
## Equal to CityGeometry3D.ground_corners/uses_nw_se_diagonal on the same
## read-only inputs; the cache lives only for the enclosing _build_region.
func _facet(city: City, cell: Vector2i) -> Array:
	var cached: Array = _facets.get(cell, [])
	if cached.is_empty():
		var corners := CityGeometry3D.ground_corners(city, cell)
		cached = [corners, CityGeometry3D.uses_nw_se_diagonal(corners)]
		_facets[cell] = cached
	return cached


func _rect(city: City, cell: Vector2i, rect: Rect2, color: Color, elevation: float, role: int = PhysicalRole.DETAIL) -> void:
	_surface_polygon(city, cell, [rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)], color, elevation, role)


## Split every surface polygon at the terrain crease before triangulating it.
## Correct corner heights alone cannot keep a road flat on both terrain faces.
func _surface_polygon(city: City, cell: Vector2i, polygon: Array[Vector2], color: Color, elevation: float, role: int = PhysicalRole.DETAIL) -> void:
	if not _drawing_tunnel and ((_approach_profiles.has(cell) and _physical_group==int(_approach_profiles[cell].family)) or (_physical_group == NetworkShapes.Family.HIGHWAY and not _deck_profiles.has(cell) and HighwayHeight.curved(_highway_stencil(city,cell)))):
		_curved_polygon(city,cell,polygon,color,elevation,role)
		return
	var diagonal: bool = _facet(city, cell)[1]
	for positive: bool in [false, true]:
		var clipped := _clip_facet(polygon, diagonal, positive)
		if clipped.size() < 3:
			continue
		var a := _point(city, cell, clipped[0], elevation)
		for i: int in range(1, clipped.size() - 1):
			var b := _point(city, cell, clipped[i], elevation)
			var c := _point(city, cell, clipped[i + 1], elevation)
			_emit_triangle(cell, a, b, c, color, role, false)


func _highway_stencil(city: City, cell: Vector2i) -> PackedFloat64Array:
	if not _highway_stencils.has(cell): _highway_stencils[cell] = HighwayHeight.stencil(city,cell)
	return _highway_stencils[cell]


## A common grid keeps curved surfaces watertight across tile/chunk boundaries.
## Only curved highway cells need subdivision; level/planar decks stay compact.
func _curved_polygon(city: City, cell: Vector2i, polygon: Array[Vector2], color: Color, elevation: float, role: int) -> void:
	var steps := Vector2i(16,16)
	if _approach_profiles.has(cell):
		var profile: Dictionary = _approach_profiles[cell]
		steps = BridgeApproaches.subdivisions(profile)
	var key: Array = [polygon,steps]
	if not _curved_templates.has(key):
		var parts: Array[Array] = []
		var bounds := Rect2(polygon[0],Vector2.ZERO)
		for p: Vector2 in polygon: bounds = bounds.expand(p)
		for y: int in range(maxi(0,floori(bounds.position.y*steps.y)),mini(steps.y,ceili(bounds.end.y*steps.y))):
			for x: int in range(maxi(0,floori(bounds.position.x*steps.x)),mini(steps.x,ceili(bounds.end.x*steps.x))):
				var clipped := polygon
				for axis: int in 2:
					var index := x if axis==0 else y
					var count := steps.x if axis==0 else steps.y
					clipped = clip_axis(clipped,axis,index/float(count),true)
					clipped = clip_axis(clipped,axis,(index+1)/float(count),false)
				if clipped.size()>=3: parts.append(clipped)
		_curved_templates[key.duplicate(true)] = parts
	var points: Dictionary = {}
	for clipped: Array in _curved_templates[key]:
		for offset: Vector2 in clipped:
			if not points.has(offset): points[offset] = _point(city,cell,offset,elevation)
		var a: Vector3 = points[clipped[0]]
		for i: int in range(1,clipped.size()-1):
			_emit_triangle(cell, a, points[clipped[i]], points[clipped[i+1]], color, role, false)


static func _clip_facet(polygon: Array[Vector2], nw_se: bool, positive: bool) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if polygon.is_empty():
		return out
	var previous := polygon[-1]
	var before := previous.x - previous.y if nw_se else previous.x + previous.y - 1.0
	if not positive:
		before = -before
	for current: Vector2 in polygon:
		var distance := current.x - current.y if nw_se else current.x + current.y - 1.0
		if not positive:
			distance = -distance
		var was_inside := before >= 0.0
		var is_inside := distance >= 0.0
		if was_inside != is_inside:
			out.append(previous.lerp(current, before / (before - distance)))
		if is_inside:
			out.append(current)
		previous = current
		before = distance
	return out


func _box(at: Vector3, size: Vector3, color: Color, physical: bool = true) -> void:
	_node_specs.append([&"box", at, size, color])
	var node := MeshInstance3D.new()
	node.mesh = _box_mesh(size)
	node.material_override = _structure_material(color)
	node.position = at
	add_child(node)
	if physical:
		_physical_boxes.append({"transform": node.transform, "size": size})
		_physical_cache.clear()


func _box_mesh(size: Vector3) -> BoxMesh:
	_box_sizes_used[size] = true
	if not _box_meshes.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		_box_meshes[size] = mesh
	return _box_meshes[size]


func _structure_material(color: Color) -> Material:
	if not _structure_materials.has(color):
		_structure_materials[color] = CityGeometry3D.material(color)
	return _structure_materials[color]




func _palms(city: City, cell: Vector2i, code: int) -> void:
	_node_specs.append([&"palms", cell, code])
	const Palm := preload("res://scripts/view/city_palm_3d.gd")
	var index := clampi(code - Buildings.TREES_1, 0, Palm.GROVE_TRUNKS.size() - 1)
	var count: int = Palm.GROVE_TRUNKS[index]
	for i: int in count:
		var offset: Vector2 = Palm.GROVE_ROOTS[i]
		var variant: int = Palm.GROVE_VARIANTS[i]
		var height: float = clampf(Palm.VARIANT_HEIGHTS[variant] * 0.075, 0.5, 0.75)
		var palm := Palm.create(height, 0.18, variant)
		var root := CityGeometry3D.point_on_ground(city, cell, offset)
		palm.position = root
		add_child(palm)


func _draw_path(city: City, cell: Vector2i, mask: int, width: float, color: Color, elevation: float, role: int = PhysicalRole.DETAIL) -> void:
	if mask in [5,10] and ((_approach_profiles.has(cell) and _physical_group==int(_approach_profiles[cell].family)) or (_physical_group == NetworkShapes.Family.HIGHWAY and not _deck_profiles.has(cell) and HighwayHeight.curved(_highway_stencil(city,cell)))):
		var lo := (1-width)*.5
		_rect(city,cell,Rect2(lo,0,width,1) if mask==5 else Rect2(0,lo,1,width),color,elevation,role)
		return
	if mask in [3, 6, 9, 12]:
		_arc(city, cell, mask, width, color, elevation, 0.0, 1.0, 0.5, role)
		return
	var lo := (1.0 - width) / 2.0
	_rect(city, cell, Rect2(lo, lo, width, width), color, elevation, role)
	for direction: int in 4:
		if mask & (1 << direction):
			var rect: Rect2 = [Rect2(lo, 0, width, 0.5), Rect2(0.5, lo, 0.5, width),
				Rect2(lo, 0.5, width, 0.5), Rect2(0, lo, 0.5, width)][direction]
			_rect(city, cell, rect, color, elevation, role)


## Footprint flags can use any of four saved corner orientations. Validate a
## complete 2x2 pattern before the unflagged even-grid fallback; partial blocks
## are never joined and city data is never rewritten. Matching ignores the
## current camera rotation.
static func highway_footprint(city: City, cell: Vector2i, code: int) -> Vector2i:
	var corners := Zones.corners(city.zone.atv(cell))
	var layouts := [[Zones.CORNER_NW, Zones.CORNER_NE, Zones.CORNER_SW, Zones.CORNER_SE],
		[0x20, 0x40, 0x10, 0x80], [0x40, 0x80, 0x20, 0x10],
		[0x80, 0x10, 0x40, 0x20]]
	for layout: Array in layouts:
		var index := layout.find(corners)
		if index < 0:
			continue
		var candidate := cell - Vector2i(index % 2, index >> 1)
		var complete := true
		for dy: int in 2:
			for dx: int in 2:
				var p := candidate + Vector2i(dx, dy)
				if not city.in_bounds(p.x, p.y) or city.building.atv(p) != code \
						or Zones.corners(city.zone.atv(p)) != layout[dy * 2 + dx]:
					complete = false
		if complete:
			return candidate
	if corners not in [0, Zones.ALL_CORNERS]:
		return Vector2i(-1, -1)
	var anchor := NetworkShapes.block_anchor(cell)
	for dy: int in 2:
		for dx: int in 2:
			var p := anchor + Vector2i(dx, dy)
			if not city.in_bounds(p.x, p.y) or city.building.atv(p) != code:
				return Vector2i(-1, -1)
			var flags := Zones.corners(city.zone.atv(p))
			if flags not in [0, Zones.ALL_CORNERS]:
				return Vector2i(-1, -1)
	return anchor


func _highway_block(city: City, anchor: Vector2i, code: int) -> void:
	_physical_group = NetworkShapes.Family.HIGHWAY
	_physical_depth = 0.095
	var mask := network_mask(code, NetworkShapes.Family.HIGHWAY)
	var pivot: Vector2 = Vector2.ZERO
	if code != NetworkShapes.HIGHWAY_JUNCTION:
		pivot = {3: Vector2(2, 0), 6: Vector2(2, 2), 12: Vector2(0, 2), 9: Vector2(0, 0)}[mask]
	for dy: int in 2:
		for dx: int in 2:
			var offset := Vector2(dx + .5, dy + .5)
			var radial := offset - pivot
			# The opposite quadrant's center lies beyond the outer bend. Place
			# its pier beneath the lane instead of leaving a freestanding pillar.
			if code != NetworkShapes.HIGHWAY_JUNCTION and radial.length_squared() > 4.0:
				offset = pivot + radial.normalized() * 1.72
			_highway_supports(city, anchor + Vector2i(dx, dy), code, offset - Vector2(dx, dy))
	if code == NetworkShapes.HIGHWAY_JUNCTION:
		# One clear crossing through the block, with two carriageways per axis.
		for across: float in [0.5, 1.5]:
			for vertical: bool in [false, true]:
				var rect := Rect2(across - 0.4975, 0, 0.995, 2) if vertical else Rect2(0, across - 0.4975, 2, 0.995)
				_block_polygon(city, anchor, _rect_polygon(rect), Color(0.74, 0.72, 0.65), HIGHWAY_ELEVATION - 0.008, PhysicalRole.SHOULDER)
		for across: float in [0.5, 1.5]:
			for vertical: bool in [false, true]:
				var rect := Rect2(across - 0.46, 0, 0.92, 2) if vertical else Rect2(0, across - 0.46, 2, 0.92)
				_block_polygon(city, anchor, _rect_polygon(rect), Color(0.34, 0.38, 0.40), HIGHWAY_ELEVATION, PhysicalRole.FLOOR)
		return
	var angle: float = {3: PI, 6: -PI / 2.0, 12: 0.0, 9: PI / 2.0}[mask]
	for radius: float in [0.5, 1.5]:
		for surface: int in 3:
			var width: float = [0.995, 0.92, 0.022][surface]
			var color: Color = [Color(0.74, 0.72, 0.65), Color(0.34, 0.38, 0.40), HIGHWAY_LANE_DIVIDER][surface]
			var elevation: float = [HIGHWAY_ELEVATION - 0.008, HIGHWAY_ELEVATION, HIGHWAY_ELEVATION + 0.006][surface]
			for i: int in 32:
				if surface == 2 and i % 4 > 1:
					continue
				var d0 := Vector2(cos(angle - i * PI / 64.0), sin(angle - i * PI / 64.0))
				var d1 := Vector2(cos(angle - (i + 1) * PI / 64.0), sin(angle - (i + 1) * PI / 64.0))
				_block_polygon(city, anchor, [pivot + d0 * (radius - width / 2), pivot + d0 * (radius + width / 2),
					pivot + d1 * (radius + width / 2), pivot + d1 * (radius - width / 2)], color, elevation,
					PhysicalRole.SHOULDER if surface == 0 else PhysicalRole.FLOOR if surface == 1 else PhysicalRole.DETAIL)


static func _rect_polygon(rect: Rect2) -> Array[Vector2]:
	return [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]


func _block_polygon(city: City, anchor: Vector2i, polygon: Array[Vector2], color: Color, elevation: float, role: int = PhysicalRole.DETAIL) -> void:
	for dy: int in 2:
		for dx: int in 2:
			var local: Array[Vector2] = []
			for p: Vector2 in polygon:
				local.append(p - Vector2(dx, dy))
			for axis: int in 2:
				local = clip_axis(local, axis, 0, true)
				local = clip_axis(local, axis, 1, false)
			if local.size() >= 3:
				_surface_polygon(city, anchor + Vector2i(dx, dy), local, color, elevation, role)


## Clip `polygon` to one side of `boundary` along `axis` (0 = x, 1 = y).
static func clip_axis(polygon: Array[Vector2], axis: int, boundary: float, above: bool) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if polygon.is_empty():
		return out
	var previous := polygon[-1]
	var before := (previous[axis] - boundary) * (1.0 if above else -1.0)
	for point: Vector2 in polygon:
		var distance := (point[axis] - boundary) * (1.0 if above else -1.0)
		if (before >= 0) != (distance >= 0):
			out.append(previous.lerp(point, before / (before - distance)))
		if distance >= 0:
			out.append(point)
		previous = point
		before = distance
	return out


func _highway_supports(city: City, cell: Vector2i, code: int, center: Vector2 = Vector2(0.5, 0.5)) -> void:
	var offsets: Array[Vector2] = [center]
	if code >= NetworkShapes.HIGHWAY_NS_ROAD_EW and code <= NetworkShapes.HIGHWAY_EW_POWER_NS:
		# Both lower transport axes stay clear through their full lane width.
		offsets = [Vector2(0.09, 0.09), Vector2(0.91, 0.09), Vector2(0.09, 0.91), Vector2(0.91, 0.91)]
	for offset: Vector2 in offsets:
		var ground := CityGeometry3D.point_on_ground(city, cell, offset)
		if _deck_profiles.has(cell):
			# Imported wet slope art can have a raw corner above its visible bed.
			ground.y = CityGeometry3D.visible_ground_height(city,cell,offset)
		var previous_group := _physical_group
		_physical_group = NetworkShapes.Family.HIGHWAY
		var lift := BRIDGE_REFERENCE_ELEVATION if _deck_profiles.has(cell) else HIGHWAY_ELEVATION
		var height := _point(city,cell,offset,lift).y-.05-ground.y
		_physical_group = previous_group
		_box(ground + Vector3(0, height / 2, 0), Vector3(0.10, height, 0.10), Color(0.57, 0.54, 0.49))


func _ramp(city: City, cell: Vector2i, code: int) -> void:
	_physical_group = NetworkShapes.Family.HIGHWAY
	_physical_depth = 0.095
	var ends := NetworkShapes.onramp_endpoints(code, bool(city.flags.atv(cell) & RotationMapper.AXIS_FLAG), 0)
	var road := Vector2(ends[0])
	var high := Vector2(ends[1])
	# Every quad corner is a (step, lateral offset) sample of the same ramp
	# surface. The radial direction depends only on the step and the height
	# profile only on the lateral offset, so evaluate each once and share them
	# instead of calling _ramp_point per corner.
	var pivot := Vector2(0.5, 0.5) + (road + high) * 0.5
	var sweep := (-high).angle_to(-road)
	var stencil := _highway_stencil(city, cell)
	var radials := PackedVector2Array()
	radials.resize(129)
	for i: int in 129:
		radials[i] = (-high).rotated(sweep * (i/128.0))
	var columns: Dictionary = {}
	for surface: int in 3:
		var color: Color = [Color(0.74, 0.72, 0.65), Color(0.34, 0.38, 0.40), Color(0.86, 0.72, 0.36)][surface]
		var lift: float = [-0.008, 0.0, 0.006][surface]
		var role := PhysicalRole.SHOULDER if surface==0 else PhysicalRole.FLOOR if surface==1 else PhysicalRole.DETAIL
		# Preserve the full adjoining road width through both mouths and turn.
		var width := 0.022 if surface == 2 else ROAD_WIDTH + (0.075 if surface == 0 else 0.0)
		# Emit only the exposed shoulder strips: no dense overlapping layer
		# under the pavement for the physical resolver to partition.
		var bands := 24 if surface==1 else 2 if surface==0 else 1
		var lows: Array[Array] = []
		var highs: Array[Array] = []
		for band: int in bands:
			var lo := -width*.5+width*band/bands
			var hi := -width*.5+width*(band+1)/bands
			if surface==0:
				lo = -width*.5 if band==0 else ROAD_WIDTH*.5
				hi = -ROAD_WIDTH*.5 if band==0 else width*.5
			lows.append(_ramp_column(columns, city, cell, road, high, pivot, radials, stencil, lo))
			highs.append(_ramp_column(columns, city, cell, road, high, pivot, radials, stencil, hi))
		for i: int in 128:
			if surface == 2 and i%16>7:
				continue
			for band: int in bands:
				var lo_offsets: PackedVector2Array = lows[band][0]
				var lo_heights: PackedFloat64Array = lows[band][1]
				var hi_offsets: PackedVector2Array = highs[band][0]
				var hi_heights: PackedFloat64Array = highs[band][1]
				_world_quad(cell,
					Vector3(cell.x+lo_offsets[i].x, lo_heights[i]+lift, cell.y+lo_offsets[i].y),
					Vector3(cell.x+hi_offsets[i].x, hi_heights[i]+lift, cell.y+hi_offsets[i].y),
					Vector3(cell.x+lo_offsets[i+1].x, lo_heights[i+1]+lift, cell.y+lo_offsets[i+1].y),
					Vector3(cell.x+hi_offsets[i+1].x, hi_heights[i+1]+lift, cell.y+hi_offsets[i+1].y),
					color, role)


## All 129 step samples of one lateral ramp offset: local surface offsets and
## unlifted heights, computed as _ramp_point does for each step.
func _ramp_column(columns: Dictionary, city: City, cell: Vector2i, road: Vector2, high: Vector2, pivot: Vector2, radials: PackedVector2Array, stencil: PackedFloat64Array, across: float) -> Array:
	if columns.has(across): return columns[across]
	var profile := HighwayHeight.ramp_profile(city,cell,road,high,.5+across,stencil,HIGHWAY_ELEVATION,HighwayGrades.ramp_endpoint(_approach_profiles,_deck_profiles,cell,road,high,.5+across))
	var offsets := PackedVector2Array()
	offsets.resize(129)
	var heights := PackedFloat64Array()
	heights.resize(129)
	for i: int in 129:
		offsets[i] = pivot + radials[i] * (0.5 + across)
		heights[i] = HighwayHeight.ramp_profile_height(profile, i/128.0)
	var column := [offsets, heights]
	columns[across] = column
	return column


func _ramp_point(city: City, cell: Vector2i, road: Vector2, high: Vector2, t: float, across: float, lift: float) -> Vector3:
	var pivot := Vector2(0.5, 0.5) + (road + high) * 0.5
	var radial := (-high).rotated((-high).angle_to(-road) * t)
	var offset := pivot + radial * (0.5 + across)
	return Vector3(cell.x+offset.x,HighwayHeight.ramp_height(city,cell,road,high,t,.5+across,_highway_stencil(city,cell),HIGHWAY_ELEVATION,HighwayGrades.ramp_endpoint(_approach_profiles,_deck_profiles,cell,road,high,.5+across))+lift,cell.y+offset.y)


## Independent structure faces do not inherit a seabed or hillside crease.
func _world_quad(cell: Vector2i, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, role: int = PhysicalRole.DETAIL) -> void:
	_emit_triangle(cell, a, b, c, color, role, true)
	_emit_triangle(cell, b, d, c, color, role, true)


## Emits one visible triangle with downward winding plus its physical record,
## without temporary arrays; degenerate triangles are skipped. An upward-facing
## input is flipped to (a, c, b), or to the full reversal (c, b, a) when
## `reverse_all` is set, as _world_quad does.
func _emit_triangle(cell: Vector2i, a: Vector3, b: Vector3, c: Vector3, color: Color, role: int, reverse_all: bool) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.000000000001:
		return
	if normal.y > 0:
		if reverse_all:
			var swap := a
			a = c
			c = swap
		else:
			var swap := b
			b = c
			c = swap
	_faces.push_back(a)
	_faces.push_back(b)
	_faces.push_back(c)
	_record_physical_points(cell, a, b, c, role)
	_colors.push_back(color)
	_colors.push_back(color)
	_colors.push_back(color)
	_cells.push_back(cell)


static var _bridge_families := PackedByteArray()
## The bridge family (`NetworkShapes.Family`) of building code `code`.
static func bridge_family(code: int) -> int:
	if code < 0 or code >= Buildings.COUNT: return _bridge_family_uncached(code)
	if _bridge_families.is_empty():
		_bridge_families.resize(Buildings.COUNT)
		for id: int in Buildings.COUNT: _bridge_families[id] = _bridge_family_uncached(id)
	return _bridge_families[code]


static func _bridge_family_uncached(code: int) -> int:
	if NetworkShapes.is_road_bridge(code):
		return NetworkShapes.Family.ROAD
	if NetworkShapes.is_rail_bridge(code):
		return NetworkShapes.Family.RAIL
	if NetworkShapes.is_power_bridge(code):
		return NetworkShapes.Family.POWER
	return NetworkShapes.Family.NONE


## Complete deck/approach/grade profiles for one city's current detached profile
## inputs, shared by the renderer parts, traffic graphs and naming topologies
## instead of each repeating the same whole-city scans. An input comparison
## guards reuse; callers duplicate before mutating.
##
## Changed inputs can still reuse the profiles exactly. The computation reads
## cell inputs only through whole-city family predicates (bridge, highway and
## ramp codes) and within PROFILE_BRIDGE_REACH cells of bridge and deck cells
## (span ends 1, approach walks 6 along, side branches 6 across, terrain
## stencils 3: at most 10) or
## PROFILE_HIGHWAY_REACH cells of highway and ramp cells, where only terrain
## is read (grade stencils, corner facets); the footprint, pairing and corridor
## code predicates of non-highway neighbours stay false. When every changed
## cell is outside the bridge reach, a terrain change is also outside the
## highway reach, and neither its old nor its new code is a bridge, highway or
## ramp, the computation reads identical values along an identical path, so
## the previous profiles are its result. A code, axis or corner change between
## two non-network codes (palms, rubble, parks, empty ground) is never read.
const PROFILE_BRIDGE_REACH := 12
const PROFILE_HIGHWAY_REACH := 4
## More changed cells than this simply recompute.
const PROFILE_REUSE_LIMIT := 64
static var _shared_profile_inputs: Array = []
static var _shared_deck_profiles: Dictionary = {}
static var _shared_approach_profiles: Dictionary = {}
## Incremented whenever the shared profiles are recomputed.
static var _shared_profile_revision := 0
## Observational: recomputations and exact reuses after changed inputs.
static var shared_profile_recomputes := 0
static var shared_profile_reuses := 0
## Tests may disable reuse to compare with a fresh computation.
static var profile_reuse := true
static func shared_bridge_profiles(city: City) -> Array:
	var inputs := _profile_inputs(city)
	if _shared_profile_inputs.is_empty() or inputs != _shared_profile_inputs:
		if not _shared_profile_inputs.is_empty() and profile_reuse and _profiles_reusable(_shared_profile_inputs, inputs, _shared_deck_profiles):
			shared_profile_reuses += 1
		else:
			var decks: Dictionary = {}
			var approaches := _build_bridge_profiles(city, decks)
			_shared_deck_profiles = decks
			_shared_approach_profiles = approaches
			_shared_profile_revision += 1
			shared_profile_recomputes += 1
		_shared_profile_inputs = inputs
	return [_shared_deck_profiles, _shared_approach_profiles]


## Changed cells between two _profile_inputs snapshots as index*4 + classes
## (1: network code/axis/corner bytes, 2: heights, terrain, vertices or flood),
## or [-1] when a global input (city, sea level) differs.
static func _profile_differences(old: Array, now: Array) -> PackedInt32Array:
	if old.is_empty() or old[0] != now[0] or old[8] != now[8]: return PackedInt32Array([-1])
	var cells: Dictionary = {}
	for layer: int in [1, 2, 3, 4, 5]:
		if old[layer] == now[layer]: continue
		var before: Variant = old[layer]
		var after: Variant = now[layer]
		for y: int in City.HEIGHT:
			var row := y * City.WIDTH
			if before.slice(row, row + City.WIDTH) == after.slice(row, row + City.WIDTH): continue
			for x: int in City.WIDTH:
				if before[row + x] != after[row + x]: cells[row + x] = int(cells.get(row + x, 0)) | (2 if layer <= 2 else 1)
	var old_vertices: PackedByteArray = old[6]
	var vertices: PackedByteArray = now[6]
	if old_vertices != vertices:
		if old_vertices.size() != vertices.size(): return PackedInt32Array([-1])
		var columns := City.WIDTH + 1
		for v: int in vertices.size():
			if old_vertices[v] == vertices[v]: continue
			for dy: int in [-1, 0]:
				for dx: int in [-1, 0]:
					var x := v % columns + dx
					var y := v / columns + dy
					if x >= 0 and y >= 0 and x < City.WIDTH and y < City.HEIGHT: cells[y * City.WIDTH + x] = int(cells.get(y * City.WIDTH + x, 0)) | 2
	var old_flood: Dictionary = old[7]
	var flood: Dictionary = now[7]
	if old_flood != flood:
		for collection: Dictionary in [old_flood, flood]:
			for cell: Vector2i in collection:
				if old_flood.has(cell) != flood.has(cell) or old_flood.get(cell) != flood.get(cell): cells[cell.y * City.WIDTH + cell.x] = int(cells.get(cell.y * City.WIDTH + cell.x, 0)) | 2
	var result := PackedInt32Array()
	for index: int in cells: result.append(index * 4 + int(cells[index]))
	return result


static func _profile_source(code: int) -> bool:
	return bridge_family(code) != NetworkShapes.Family.NONE or NetworkShapes.is_highway(code) or NetworkShapes.is_onramp(code)


## Road bores read tunnel codes, heights (tunnel bits) and terrain only: a
## change confined to non-tunnel codes, axes and corners keeps them exact.
static func _tunnels_affected(old: Array, now: Array) -> bool:
	var changed := _profile_differences(old, now)
	if not changed.is_empty() and changed[0] < 0: return true
	var codes: PackedInt32Array = old[3]
	var current: PackedInt32Array = now[3]
	for entry: int in changed:
		if entry & 2 or NetworkShapes.is_tunnel(codes[entry >> 2]) or NetworkShapes.is_tunnel(current[entry >> 2]): return true
	return false


## Whether any profile predicate can distinguish this code from empty ground:
## network families, bridges, ramps, bores and portals. Palms, rubble, parks
## and other non-network codes read exactly like an empty cell.
static func _profile_network_code(code: int) -> bool:
	return _profile_source(code) or NetworkShapes.is_tunnel(code) or NetworkShapes.is_subway_portal(code) 		or NetworkShapes.in_road_family(code) or NetworkShapes.in_rail_family(code) or NetworkShapes.in_power_family(code) 		or Buildings.category(code) == Buildings.Category.BRIDGE


## Whether profiles computed for `old` are exactly those of `now` (see above).
static func _profiles_reusable(old: Array, now: Array, decks: Dictionary) -> bool:
	var changed := _profile_differences(old, now)
	if changed.is_empty(): return true
	if changed[0] < 0 or changed.size() > PROFILE_REUSE_LIMIT: return false
	var codes: PackedInt32Array = old[3]
	var current: PackedInt32Array = now[3]
	for entry: int in changed:
		var index := entry >> 2
		# Codes, axes and corners of non-network cells are never read.
		if entry & 2 == 0 and not _profile_network_code(codes[index]) and not _profile_network_code(current[index]): continue
		if _profile_source(codes[index]) or _profile_source(current[index]): return false
		var cell := Vector2i(index % City.WIDTH, index / City.WIDTH)
		# Every bridge-family cell and highway deck holds a deck entry.
		for deck: Vector2i in decks:
			if absi(deck.x - cell.x) <= PROFILE_BRIDGE_REACH and absi(deck.y - cell.y) <= PROFILE_BRIDGE_REACH: return false
		# Highway profiles read nearby cells only through terrain; the code
		# predicates of non-highway neighbours are false before and after.
		if entry & 2 == 0: continue
		for y: int in range(maxi(cell.y - PROFILE_HIGHWAY_REACH, 0), mini(cell.y + PROFILE_HIGHWAY_REACH + 1, City.HEIGHT)):
			for x: int in range(maxi(cell.x - PROFILE_HIGHWAY_REACH, 0), mini(cell.x + PROFILE_HIGHWAY_REACH + 1, City.WIDTH)):
				if _profile_source(codes[y * City.WIDTH + x]): return false
	return true


## Adds every bridge deck missing from `decks` and returns the approach and
## highway grade profiles that depend on them.
static func _build_bridge_profiles(city: City, decks: Dictionary) -> Dictionary:
	_collect_bridge_decks(city, decks)
	decks.merge(preload("res://scripts/view/city_highway_bridges_3d.gd").profiles(city))
	var approaches := BridgeApproaches.profiles(city, decks)
	approaches.merge(HighwayGrades.profiles(city, decks), true)
	return approaches


func _prepare_bridge_decks(city: City) -> void:
	if _deck_profiles.is_empty():
		# A fresh projection can reuse the whole-city profiles; only partial
		# updates that keep earlier decks need their own collection pass.
		var shared := shared_bridge_profiles(city)
		_deck_profiles.merge(shared[0].duplicate(true))
		_approach_profiles = shared[1].duplicate(true)
		_deck_revision = _shared_profile_revision
		return
	_approach_profiles = _build_bridge_profiles(city, _deck_profiles)
	_deck_revision = -1


## Rigid level spans for every classic bridge cell not already in `decks`.
static func _collect_bridge_decks(city: City, decks: Dictionary) -> void:
	var codes := city.building.data
	for y: int in City.HEIGHT:
		var row := y * City.WIDTH
		for x: int in City.WIDTH:
			var family := bridge_family(codes[row + x])
			if family == NetworkShapes.Family.NONE:
				continue
			var cell := Vector2i(x, y)
			if decks.has(cell):
				continue
			var ew := bool(city.flags.atv(cell) & RotationMapper.AXIS_FLAG)
			var direction := Vector2i.RIGHT if ew else Vector2i.DOWN
			var start := cell
			while _same_bridge(city, start - direction, family, ew):
				start -= direction
			var span: Array[Vector2i] = []
			var p := start
			var water := -INF
			while _same_bridge(city, p, family, ew):
				span.append(p)
				water = maxf(water, city.water_height(p.x, p.y) * CityGeometry3D.HEIGHT + 0.12)
				p += direction
			# Bridge structure remains one rigid, level span. Resolve clearance
			# from both complete bank edges; curved grading belongs on dry roads.
			var deck := water
			for bank: Vector2i in [start-direction,p]:
				if not city.in_bounds(bank.x,bank.y) or city.is_water(bank.x,bank.y): continue
				var toward := direction if bank==start-direction else -direction
				for across: float in [0.0,.5,1.0]:
					var edge := Vector2(.5,.5)+Vector2(toward)*.5
					if ew: edge.y = across
					else: edge.x = across
					deck = maxf(deck,CityGeometry3D.point_on_ground(city,bank,edge).y+.04)
			var span_codes: Array[int] = []
			for at: Vector2i in span: span_codes.append(city.building.atv(at))
			var cable := suspension_cable(span_codes)
			for i: int in span.size():
				var raised := .65 if span_codes[i]==89 else .0
				decks[span[i]] = {"ew":ew,"start":deck+raised,"end":deck+raised,
					"index":i,"length":span.size(),"deck":deck+raised}
				if not cable.is_empty(): decks[span[i]]["cable"] = cable.duplicate()


## The renderer, collision mesh and ambient traffic all use this profile.
static func bridge_height(profile: Dictionary, t: float) -> float:
	return lerpf(profile.start,profile.end,t)


static func _same_bridge(city: City, cell: Vector2i, family: int, ew: bool) -> bool:
	return city.in_bounds(cell.x, cell.y) and bridge_family(city.building.atv(cell)) == family \
		and bool(city.flags.atv(cell) & RotationMapper.AXIS_FLAG) == ew


func _bridge_structure(city: City, cell: Vector2i, code: int) -> void:
	var profile: Dictionary = _deck_profiles[cell]
	var ew: bool = profile.ew
	if int(profile.get("family",0))==NetworkShapes.Family.HIGHWAY:
		# Full highway width, with guards outside both live lanes. Supports
		# reach the resolved deck instead of following the submerged ground.
		_highway_supports(city,cell,code)
		var center := _point(city,cell,Vector2(.5,.5),BRIDGE_REFERENCE_ELEVATION)
		_box(center-Vector3.UP*.05,Vector3(1,.095,1),Color(.57,.54,.49),false)
		for side: float in [-.49,.49]:
			var a := _point(city,cell,Vector2(0,.5+side) if ew else Vector2(.5+side,0),BRIDGE_REFERENCE_ELEVATION)
			var b := _point(city,cell,Vector2(1,.5+side) if ew else Vector2(.5+side,1),BRIDGE_REFERENCE_ELEVATION)
			_beam(a+Vector3.UP*.10,b+Vector3.UP*.10,.025,Color(.46,.52,.52))
			for step: int in 5 if int(profile.index)==int(profile.length)-1 else 4:
				var post := _point(city,cell,Vector2(step*.25,.5+side) if ew else Vector2(.5+side,step*.25),BRIDGE_REFERENCE_ELEVATION)
				_post_faces(cell,post,post+Vector3.UP*.10,.022,Color(.46,.52,.52))
		return
	var forward := Vector3.RIGHT if ew else Vector3.BACK
	var across := Vector3.BACK if ew else Vector3.RIGHT
	var center := _point(city, cell, Vector2(0.5, 0.5), 0.65)
	var concrete := Color(0.57, 0.54, 0.49)
	var steel := Color(0.46, 0.52, 0.52)
	if code == 92:
		# Elevated wires have pylons, without a road slab or bridge guardrail.
		return
	# A solid underside gives the deck depth; parapets leave the travel path open.
	for side: float in [-0.35, 0.35]:
		var steps := 1
		for step: int in steps:
			var t0 := step/float(steps)
			var t1 := (step+1)/float(steps)
			var a := _point(city,cell,Vector2(t0,.5+side) if ew else Vector2(.5+side,t0),.61)
			var b := _point(city,cell,Vector2(t1,.5+side) if ew else Vector2(.5+side,t1),.61)
			_beam(a,b,.095,concrete)
			_beam(a+Vector3.UP*.16,b+Vector3.UP*.16,.035,steel)
	# Guard rails stand on posts at a fixed pitch, continuous across cells.
	for side: float in [-0.35, 0.35]:
		for step: int in 5 if int(profile.index)==int(profile.length)-1 else 4:
			var post := _point(city,cell,Vector2(step*.25,.5+side) if ew else Vector2(.5+side,step*.25),BRIDGE_REFERENCE_ELEVATION)
			_post_faces(cell,post,post+Vector3.UP*.13,.026,steel)
	# Tower cells stand on their own legs, which reach the ground below.
	if code in [87, 90, 106] or (int(profile.index) % 3 == 0 and code == 83):
		for side: float in [-0.34, 0.34]:
			var top := _point(city,cell,Vector2(.5,.5+side) if ew else Vector2(.5+side,.5),.65)-Vector3.UP*.07
			var offset := Vector2(top.x - cell.x, top.z - cell.y)
			var ground := CityGeometry3D.point_on_ground(city, cell, offset)
			if top.y > ground.y:
				_beam(ground, top, 0.13, concrete)
	if code >= 81 and code <= 85:
		# Each suspension unit hangs its own main cable from its towers to the
		# deck anchorages at the unit ends; causeway cells carry no cable.
		var cable: Array = profile.get("cable", [])
		for side: float in [-0.39, 0.39]:
			for step: int in 4:
				var t0 := step / 4.0
				var t1 := (step + 1) / 4.0
				var h0 := cable_height(cable, profile.index + t0)
				var h1 := cable_height(cable, profile.index + t1)
				if h0 < 0 or h1 < 0:
					continue
				var p := _point(city,cell,Vector2(t0,.5+side) if ew else Vector2(.5+side,t0),BRIDGE_REFERENCE_ELEVATION)
				var q := _point(city,cell,Vector2(t1,.5+side) if ew else Vector2(.5+side,t1),BRIDGE_REFERENCE_ELEVATION)
				var a := p + Vector3.UP * h0
				var b := q + Vector3.UP * h1
				_beam(a, b, 0.035, steel, false)
				if h0 > CABLE_ANCHOR + 0.02:
					_beam(p, a, 0.018, steel, false)
		if code in [82, 84]:
			_bridge_tower(city,cell,ew, CABLE_TOP + 0.05, concrete)
	elif code == 86:
		_bridge_tower(city,cell,ew, 1.40, steel)
	if code in [86, 88, 89, 90, 91, 106, 107]:
		var girder_height := 0.46 if code in [90, 91] else 0.38
		var first := 0
		var last := 4
		if code == 86:
			# A lift tower carries the truss of its lift span up to its legs.
			var direction := Vector2i.RIGHT if ew else Vector2i.DOWN
			var before := city.building.atv(cell - direction) in [88, 89] and _deck_profiles.has(cell - direction)
			var after := city.building.atv(cell + direction) in [88, 89] and _deck_profiles.has(cell + direction)
			first = 0 if before else 2
			last = 4 if after else 2
		for side: float in [-0.38, 0.38]:
			for segment: int in range(first, last):
				var t0 := segment/4.0
				var t1 := (segment+1)/4.0
				var p := _point(city,cell,Vector2(t0,.5+side) if ew else Vector2(.5+side,t0),BRIDGE_REFERENCE_ELEVATION)
				var q := _point(city,cell,Vector2(t1,.5+side) if ew else Vector2(.5+side,t1),BRIDGE_REFERENCE_ELEVATION)
				_beam(p+Vector3.UP*girder_height,q+Vector3.UP*girder_height,.055,steel)
				_beam(p, q + Vector3.UP * girder_height, 0.033, steel)
				_beam(p + Vector3.UP * girder_height, q, 0.033, steel)


## Main cable height above the deck at a tower top and at a deck anchorage.
const CABLE_TOP := 1.30
const CABLE_ANCHOR := 0.14
## Lowest point of the cable between two towers, above the deck.
const CABLE_SAG := 0.30


## Cable stations for one rigid span's codes, as flattened [position, height]
## pairs along the span in cells: an anchorage at each outer edge of a
## suspension run and between two adjoining suspension units, and a tower top
## at the center of every tower tile (82/84). Empty when no unit has a tower.
static func suspension_cable(codes: Array[int]) -> Array:
	var stations: Array = []
	var towers := 0
	for i: int in codes.size():
		var hanging := codes[i] >= 81 and codes[i] <= 85
		var previous := i > 0 and codes[i-1] >= 81 and codes[i-1] <= 85
		if hanging and (not previous or (codes[i] in [81, 85] and codes[i-1] in [81, 85])):
			stations.append_array([float(i), CABLE_ANCHOR])
		elif previous and not hanging:
			stations.append_array([float(i), CABLE_ANCHOR])
		if codes[i] in [82, 84]:
			stations.append_array([i + .5, CABLE_TOP])
			towers += 1
	if not codes.is_empty() and codes[-1] >= 81 and codes[-1] <= 85:
		stations.append_array([float(codes.size()), CABLE_ANCHOR])
	return stations if towers > 0 else []


## Cable height above the deck at span position `s` (cells), or -1 where no
## cable hangs: outside every suspension run or between two anchorages.
## Between towers the cable sags to CABLE_SAG; toward an anchorage it eases
## down with its low point at the deck.
static func cable_height(stations: Array, s: float) -> float:
	for i: int in range(0, stations.size() - 2, 2):
		var s0: float = stations[i]
		var s1: float = stations[i + 2]
		if s < s0 - .00001 or s > s1 + .00001:
			continue
		var h0: float = stations[i + 1]
		var h1: float = stations[i + 3]
		var x := clampf((s - s0) / (s1 - s0), 0, 1)
		if h0 >= CABLE_TOP and h1 >= CABLE_TOP:
			return CABLE_SAG + (CABLE_TOP - CABLE_SAG) * (2*x - 1) * (2*x - 1)
		if h0 >= CABLE_TOP:
			return CABLE_ANCHOR + (CABLE_TOP - CABLE_ANCHOR) * (1 - x) * (1 - x)
		if h1 >= CABLE_TOP:
			return CABLE_ANCHOR + (CABLE_TOP - CABLE_ANCHOR) * x * x
		return -1.0
	return -1.0


## Tower legs rise from the ground beneath the deck to a crossbar at `height`
## above the deck, so the tower is also the cell's pier.
func _bridge_tower(city: City, cell: Vector2i, ew: bool, height: float, color: Color) -> void:
	for across: float in [.1, .9]:
		var offset := Vector2(.5, across) if ew else Vector2(across, .5)
		var deck := _point(city, cell, offset, BRIDGE_REFERENCE_ELEVATION)
		var ground := CityGeometry3D.point_on_ground(city, cell, offset)
		_beam(Vector3(deck.x, minf(ground.y, deck.y), deck.z), deck + Vector3.UP * height, .11, color)
	var left := _point(city,cell,Vector2(.5,.05) if ew else Vector2(.05,.5),BRIDGE_REFERENCE_ELEVATION)
	var right := _point(city,cell,Vector2(.5,.95) if ew else Vector2(.95,.5),BRIDGE_REFERENCE_ELEVATION)
	_beam(left+Vector3.UP*height,right+Vector3.UP*height,.10,color)


## A small square post emitted into the shared network surface: visible only,
## it adds no node and no physical record.
func _post_faces(cell: Vector2i, bottom: Vector3, top: Vector3, thickness: float, color: Color) -> void:
	var h := thickness * .5
	var corners: Array[Vector3] = [Vector3(-h,0,-h),Vector3(h,0,-h),Vector3(h,0,h),Vector3(-h,0,h)]
	for i: int in 4:
		var a := corners[i]
		var b := corners[(i+1)%4]
		_emit_side(cell, bottom+a, bottom+b, top+a, top+b, color)


## One outward-facing vertical quad (a,b at the bottom; c,d above them).
func _emit_side(cell: Vector2i, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	for triangle: Array in [[a, b, c], [b, d, c]]:
		_faces.push_back(triangle[0])
		_faces.push_back(triangle[1])
		_faces.push_back(triangle[2])
		_colors.push_back(color)
		_colors.push_back(color)
		_colors.push_back(color)
		_cells.push_back(cell)


func _beam(a: Vector3, b: Vector3, thickness: float, color: Color, physical: bool = true) -> void:
	var delta := b - a
	if delta.length_squared() < 0.000001:
		return
	_node_specs.append([&"beam", a, b, thickness, color, _physical_group])
	var node := MeshInstance3D.new()
	node.mesh = _box_mesh(Vector3(thickness, delta.length(), thickness))
	node.material_override = _structure_material(color)
	if _physical_group==100: node.layers=TUNNEL_RENDER_LAYER
	node.position = (a + b) / 2.0
	node.quaternion = Quaternion(Vector3.UP, delta.normalized())
	add_child(node)
	if physical:
		_physical_boxes.append({"transform": node.transform, "size": Vector3(thickness, delta.length(), thickness)})
		_physical_cache.clear()


func _road_tunnel(city: City, cell: Vector2i, profile: Dictionary) -> void:
	var previous_group := _physical_group
	var previous_depth := _physical_depth
	var first_face := _faces.size()
	var first_cell := _cells.size()
	_drawing_tunnel = true
	_draw_network(city,cell,NetworkShapes.Family.ROAD,5 if profile.inward.y!=0 else 10,.04)
	_drawing_tunnel = false
	var wall := Color(.62,.60,.54)
	var half := RoadTunnels.WIDTH*.5
	# Side walking strips share the road's shoulder height and color.
	for side: float in [-1.0,1.0]:
		_portal_strip(cell,profile,0,1,side*half,side*.3375,Color(.74,.72,.65),-.008,PhysicalRole.SHOULDER)
		var a := _portal_point(cell,profile,0,side*half)
		var b := _portal_point(cell,profile,1,side*half)
		_road_tunnel_shell_quad(cell,a,b,a+Vector3.UP*RoadTunnels.CLEAR_HEIGHT,b+Vector3.UP*RoadTunnels.CLEAR_HEIGHT,wall)
	var start := .78 if profile.entrance else 0.0
	var end := .22 if profile.exit else 1.0
	_road_tunnel_shell_quad(cell,_portal_point(cell,profile,start,-half,RoadTunnels.CLEAR_HEIGHT),
		_portal_point(cell,profile,start,half,RoadTunnels.CLEAR_HEIGHT),_portal_point(cell,profile,end,-half,RoadTunnels.CLEAR_HEIGHT),
		_portal_point(cell,profile,end,half,RoadTunnels.CLEAR_HEIGHT),Color(.38,.42,.45))
	if profile.entrance or profile.exit:
		var depth := .78 if profile.entrance else .22
		var mouth := _portal_point(cell,profile,depth,0)
		var across := Vector3(profile.across.x,0,profile.across.y)
		for side: float in [-half-.05,half+.05]:
			_beam(mouth+across*side,mouth+across*side+Vector3.UP*RoadTunnels.CLEAR_HEIGHT,.09,wall)
		_beam(mouth-across*(half+.095)+Vector3.UP*(RoadTunnels.CLEAR_HEIGHT+.05),mouth+across*(half+.095)+Vector3.UP*(RoadTunnels.CLEAR_HEIGHT+.05),.09,wall)
	_tunnel_faces.append_array(_faces.slice(first_face))
	_tunnel_colors.append_array(_colors.slice(first_face))
	_tunnel_cells.append_array(_cells.slice(first_cell))
	_faces.resize(first_face)
	_colors.resize(first_face)
	_cells.resize(first_cell)
	_physical_group = previous_group
	_physical_depth = previous_depth


func _road_tunnel_shell_quad(cell: Vector2i, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var first := _faces.size()
	var first_cell := _cells.size()
	_world_quad(cell,a,b,c,d,color,PhysicalRole.OBSTACLE)
	_tunnel_shell_faces.append_array(_faces.slice(first))
	_tunnel_shell_colors.append_array(_colors.slice(first))
	_tunnel_shell_cells.append_array(_cells.slice(first_cell))
	_faces.resize(first)
	_colors.resize(first)
	_cells.resize(first_cell)


func _portal(city: City, cell: Vector2i) -> void:
	_physical_group = NetworkShapes.Family.ROAD
	_physical_depth = 0.0
	var profile := PortalProfile.profile(city, cell, CityGeometry3D.HEIGHT)
	var depth: float = profile.depth
	var tunnel: bool = profile.tunnel
	_portal_strip(cell, profile, 0, depth + 0.03, -0.30, 0.30,
		Color(0.34, 0.38, 0.40) if tunnel else Color(0.51, 0.50, 0.45), 0.0, PhysicalRole.FLOOR)
	if not tunnel:
		for i: int in 8:
			_portal_strip(cell, profile, i * depth / 8.0, i * depth / 8.0 + 0.026,
				-0.25, 0.25, Color(0.40, 0.33, 0.26), 0.008)
		for side: float in [-0.156, 0.156]:
			_portal_strip(cell, profile, 0, depth + 0.03, side - 0.013, side + 0.013, Color(0.72, 0.75, 0.71), 0.014)
	var concrete := Color(0.62, 0.60, 0.54)
	var mouth := _portal_point(cell, profile, depth, 0)
	var across := Vector3(profile.across.x, 0, profile.across.y)
	for side: float in [-0.39, 0.39]:
		_beam(mouth + across * side, mouth + across * side + Vector3.UP * 0.48, 0.11, concrete)
	_beam(mouth - across * 0.44 + Vector3.UP * 0.49, mouth + across * 0.44 + Vector3.UP * 0.49, 0.12, concrete)
	# Dark recess is behind the mouth, with open space above the travel surface.
	_world_quad(cell, _portal_point(cell, profile, depth + 0.025, -0.335),
		_portal_point(cell, profile, depth + 0.025, 0.335),
		_portal_point(cell, profile, depth + 0.025, -0.335) + Vector3.UP * 0.43,
		_portal_point(cell, profile, depth + 0.025, 0.335) + Vector3.UP * 0.43, Color(0.07, 0.09, 0.09), PhysicalRole.OBSTACLE)
	for side: float in [-0.34, 0.34]:
		var a := _portal_point(cell, profile, 0, side)
		var b := _portal_point(cell, profile, depth, side)
		var start_local: Vector2 = profile.outside + profile.across * side
		var end_local: Vector2 = start_local + profile.inward * depth
		var top_a := CityGeometry3D.point_on_ground(city, cell, start_local) + Vector3.UP * 0.06
		var top_b := CityGeometry3D.point_on_ground(city, cell, end_local) + Vector3.UP * 0.06
		_world_quad(cell, a, b, top_a, top_b, concrete, PhysicalRole.OBSTACLE)
		_beam(top_a, top_b, 0.065, concrete)


static func _portal_point(cell: Vector2i, profile: Dictionary, depth: float, across: float, lift: float = 0.0) -> Vector3:
	var offset: Vector2 = profile.outside + profile.inward * depth + profile.across * across
	var y := lerpf(profile.floor_start, profile.floor_end, clampf(depth / float(profile.depth), 0, 1))
	return Vector3(cell.x + offset.x, y + lift, cell.y + offset.y)


func _portal_strip(cell: Vector2i, profile: Dictionary, start: float, end: float, left: float, right: float, color: Color, lift: float = 0.0, role: int = PhysicalRole.DETAIL) -> void:
	_world_quad(cell, _portal_point(cell, profile, start, left, lift), _portal_point(cell, profile, start, right, lift),
		_portal_point(cell, profile, end, left, lift), _portal_point(cell, profile, end, right, lift), color, role)


## Extraction is independent of mesh nodes, visibility and render batching.
## Callers receive detached snapshots; mutating them does not affect this layer.
func physical_data() -> Dictionary:
	if _physical_cache.is_empty():
		_resolve_physical()
	var result := _physical_cache.duplicate(true)
	result["road_tunnels"] = _road_tunnels.duplicate(true)
	return result


func _record_physical_points(cell: Vector2i, a: Vector3, b: Vector3, c: Vector3, role: int) -> void:
	if role == PhysicalRole.DETAIL: return
	_physical_cache.clear()
	if role == PhysicalRole.OBSTACLE:
		_physical_obstacles.push_back(a)
		_physical_obstacles.push_back(b)
		_physical_obstacles.push_back(c)
		# Portal recesses and retaining walls stop actors from either side.
		_physical_obstacles.push_back(c)
		_physical_obstacles.push_back(b)
		_physical_obstacles.push_back(a)
		return
	_physical_cells.push_back(cell.x)
	_physical_cells.push_back(cell.y)
	_physical_groups.push_back(_physical_group)
	_physical_roles.push_back(role)
	_physical_depths.push_back(_physical_depth)
	_physical_triangles.push_back(a)
	_physical_triangles.push_back(b)
	_physical_triangles.push_back(c)


func clear_physical_patches() -> void:
	_physical_cells.clear()
	_physical_groups.clear()
	_physical_roles.clear()
	_physical_depths.clear()
	_physical_triangles.clear()


## Detached copies of the records whose cell lies inside `region`.
func physical_patches_in(region: Rect2i) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for index: int in _physical_depths.size():
		if region.has_point(Vector2i(_physical_cells[index*2], _physical_cells[index*2+1])):
			records.append(_physical_patch_record(index))
	return records


func _physical_patch_record(index: int) -> Dictionary:
	return {"cell": Vector2i(_physical_cells[index*2], _physical_cells[index*2+1]), "group": _physical_groups[index],
		"role": _physical_roles[index], "triangle": _physical_triangles.slice(index*3, index*3+3), "depth": _physical_depths[index]}


## Partition each logical surface from the highest-priority material outward.
## Asphalt owns its footprint, shoulder owns only its exposed strips, and verge
## fills the remainder. This also removes the overlapping rectangles of junctions.
func _resolve_physical() -> void:
	if not _regions.is_empty() and incremental_physics:
		# Region layers re-resolve only what their changes can reach; the result
		# is byte-identical to the full resolution below.
		if _physics_incremental == null: _physics_incremental = PhysicsIncremental.new()
		var origins: Array[Vector2i] = []
		for origin: Vector2i in _regions: origins.append(origin)
		origins.sort_custom(func(a: Vector2i,b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
		var parts: Array = []
		for origin: Vector2i in origins:
			var part: CityNetworks3D = _regions[origin]
			parts.append([part._physical_cells, part._physical_groups, part._physical_roles, part._physical_depths, part._physical_triangles, part._physical_obstacles])
		var resolved: Array = _physics_incremental.resolve(origins, parts, [_physical_cells, _physical_groups, _physical_roles, _physical_depths, _physical_triangles, _physical_obstacles], _physical_dirty)
		_physical_dirty = {}
		_physical_cache = {"physical_floor_faces": resolved[0], "physical_obstacle_faces": resolved[1], "physical_boxes": _physical_boxes.duplicate(true)}
		return
	# The dispatcher runs the native kernel where it is available and the
	# GDScript resolver elsewhere; both produce the same surfaces.
	_physical_cache = preload("res://scripts/view/city_network_physics_native.gd").resolve_packed(_physical_cells, _physical_groups, _physical_roles, _physical_depths, _physical_triangles, _physical_boxes, _physical_obstacles)


## Everything the bridge, approach, highway and tunnel profiles read: network
## codes, axes, highway corners, heights, terrain, terrain vertices and flood
## data. Developed lots (codes >= 112) never affect those profiles, so their
## codes and flags are blanked and building growth does not invalidate them.
## The masked layers are derived per row; rows whose raw building, flag and
## zone bytes equal the previous call's snapshot keep their masked values.
static var _profile_input_cache: Array = []
static func _profile_inputs(city: City) -> Array:
	var vertices: PackedByteArray = city.terrain_surface.vertices if city.terrain_surface is TerrainSurface else PackedByteArray()
	if not _profile_input_cache.is_empty() and _profile_input_cache[0] == city.get_instance_id():
		var raw: Array = _profile_input_cache[1]
		var masked: Array = _profile_input_cache[2]
		var layers := [city.building.data, city.flags.data, city.zone.data]
		if layers != raw:
			masked = [masked[0].duplicate(), masked[1].duplicate(), masked[2].duplicate()]
			for y: int in City.HEIGHT:
				var row := y * City.WIDTH
				var same := true
				for layer: int in 3:
					if layers[layer].slice(row, row + City.WIDTH) != raw[layer].slice(row, row + City.WIDTH): same = false; break
				if same: continue
				for i: int in range(row, row + City.WIDTH):
					var code: int = layers[0][i]
					var building := Buildings.NONE if code >= Buildings.RES_1X1_FIRST else code
					masked[0][i] = building
					masked[1][i] = layers[1][i] & RotationMapper.AXIS_FLAG if building != Buildings.NONE else 0
					masked[2][i] = Zones.corners(layers[2][i]) if code >= NetworkShapes.HIGHWAY_CORNER_NE and code <= NetworkShapes.HIGHWAY_JUNCTION else 0
			_profile_input_cache = [city.get_instance_id(), [layers[0].duplicate(), layers[1].duplicate(), layers[2].duplicate()], masked]
		return [city.get_instance_id(),city.altitude.data.duplicate(),city.terrain.data.duplicate(),masked[0],masked[1],masked[2],vertices.duplicate(),city.flood_overlay.duplicate(true),city.sea_level]
	var result := _profile_inputs_full(city)
	_profile_input_cache = [city.get_instance_id(), [city.building.data.duplicate(), city.flags.data.duplicate(), city.zone.data.duplicate()], [result[3], result[4], result[5]]]
	return result


## The complete per-cell masking that _profile_inputs maintains incrementally.
static func _profile_inputs_full(city: City) -> Array:
	var buildings := city.building.data.duplicate()
	var flags := city.flags.data.duplicate()
	var corners := city.zone.data.duplicate()
	for i: int in buildings.size():
		var code: int = buildings[i]
		if code >= Buildings.RES_1X1_FIRST: buildings[i] = Buildings.NONE
		flags[i] = flags[i] & RotationMapper.AXIS_FLAG if buildings[i] != Buildings.NONE else 0
		corners[i] = Zones.corners(corners[i]) if code >= NetworkShapes.HIGHWAY_CORNER_NE and code <= NetworkShapes.HIGHWAY_JUNCTION else 0
	var vertices: PackedByteArray = city.terrain_surface.vertices if city.terrain_surface is TerrainSurface else PackedByteArray()
	return [city.get_instance_id(),city.altitude.data.duplicate(),city.terrain.data.duplicate(),buildings,flags,corners,vertices.duplicate(),city.flood_overlay.duplicate(true),city.sea_level]
