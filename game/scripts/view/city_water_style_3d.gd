# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Shared visual water material and its geometry metadata. No city writes or RNG.
extends RefCounted

var elapsed := 0.0
var enabled := true
var image: Image
var texture: ImageTexture
## The same metadata in half floats, for the one sampler that filters it:
## 32-bit float textures cannot be filtered on every mobile GPU. Seabed
## heights stay within a fiftieth of a tile even on the highest ground, far
## less than one colour step of the depth tint. Exact per-cell reads stay on the full-precision `texture`.
var depth_image: Image
var depth_texture: ImageTexture
var material: ShaderMaterial
var _city: City
var _state: Array = []
## Native standing-water planes of the retained state (see CityGeometry3D).
var _planes := PackedFloat64Array()
## Tests may turn partial rewrites off to compare with a complete one.
var incremental := true
## Observational: texels written by the last update that found a change.
var last_rewritten := 0

func _init() -> void:
	material = CityGeometry3D.surface_material(0.025,CityGeometry3D.SurfaceKind.TERRAIN)
	material.shader = material.shader.duplicate()
	# Only this view's styled terrain enables specular. The unchanged material
	# factory remains suitable for networks, detail meshes and palette probes.
	material.shader.code = material.shader.code.replace("specular_disabled","specular_schlick_ggx")
	material.set_shader_parameter("water_style_enabled",true)

func advance(delta: float) -> void:
	if enabled and is_finite(delta) and delta > 0.0:
		elapsed += delta
		material.set_shader_parameter("water_time",elapsed)

func set_quality(quality: String) -> void:
	material.set_shader_parameter("water_quality",2 if quality == "performance" else 1 if quality == "balanced" else 0)

## Reuse one small texture; buildings and utility updates cannot regenerate it.
## A changed height, terrain code, lattice vertex or flood tile rewrites only
## the texels that can read it; the result equals rewriting all of them.
func update_city(city: City) -> void:
	var vertices: PackedByteArray = city.terrain_surface.vertices if city.terrain_surface is TerrainSurface else PackedByteArray()
	var state: Array = [city.altitude.data.duplicate(),city.terrain.data.duplicate(),vertices.duplicate(),city.flood_overlay.duplicate(true)]
	if state == _state:
		_city = city
		return
	var planes := CityGeometry3D.standing_water_planes(city)
	var stale := _stale_texels(state,planes) if incremental else PackedInt32Array([-1])
	_city = city
	_state = state
	_planes = planes
	if not stale.is_empty() and stale[0] < 0:
		last_rewritten = City.WIDTH*City.HEIGHT
		image = Image.create(City.WIDTH,City.HEIGHT,false,Image.FORMAT_RGBAF)
		for y: int in City.HEIGHT:
			for x: int in City.WIDTH:
				image.set_pixel(x,y,_texel(city,Vector2i(x,y)))
	else:
		last_rewritten = stale.size()
		if stale.is_empty() and texture != null: return
		for index: int in stale:
			image.set_pixel(index % City.WIDTH,index / City.WIDTH,_texel(city,Vector2i(index % City.WIDTH,index / City.WIDTH)))
	depth_image = image.duplicate()
	depth_image.convert(Image.FORMAT_RGBAH)
	if texture == null:
		texture = ImageTexture.create_from_image(image)
		depth_texture = ImageTexture.create_from_image(depth_image)
		material.set_shader_parameter("water_geometry",texture)
		material.set_shader_parameter("water_depth",depth_texture)
	else:
		texture.update(image)
		depth_texture.update(depth_image)


## Water level, visible ground, shoreline shelf corners and the lower level a
## waterfall block drops to, for one cell.
static func _texel(city: City, cell: Vector2i) -> Color:
	var ground := CityGeometry3D.visible_ground_height(city,cell)
	var level := CityGeometry3D.water_surface_height(city,cell) if city.is_water(cell.x,cell.y) else -1.0
	var shelf := 0
	var bottom := level
	var code := city.terrain.atv(cell)
	if level >= 0.0 and not city.flood_overlay.has(cell):
		if CityGeometry3D.is_bed_water(city,cell):
			pass # One-tile channels have no shoreline shelves.
		elif Terrain.water_kind(code) in [Terrain.SHORE,Terrain.SURFACE]:
			var raised := CityGeometry3D.shore_shelf_mask(city,cell)
			var corners := CityGeometry3D.visible_cell_corners(city,cell)
			var bits := [8,1,4,2]
			for i: int in 4:
				if raised & bits[i] and corners[i].y <= level: shelf |= bits[i]
		elif code in [0x2e,0x3e]:
			for direction: Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
				var neighbor := cell+direction
				if not city.in_bounds(neighbor.x,neighbor.y): continue
				var lower := CityGeometry3D.water_surface_height(city,neighbor) if city.is_water(neighbor.x,neighbor.y) else CityGeometry3D.ground_height(city,neighbor)
				bottom = minf(bottom,lower)
	return Color(level,ground,float(shelf),bottom)


## Row-major indices of the texels a change from the retained state to `state`
## can alter, or [-1] to rewrite them all. A texel reads heights, terrain codes
## and floods within TEXEL_REACH cells (shared dry corners one cell out,
## shoreline vertices and a waterfall block's neighbours two) and the lattice
## vertices of those cells. A native standing-water patch shares one plane
## capped by its lowest bank, which a change anywhere along the patch can move:
## its cells are found by comparing the planes, with the cells beside them for
## the waterfall blocks that drop onto the patch.
const TEXEL_REACH := 2
func _stale_texels(state: Array, planes: PackedFloat64Array) -> PackedInt32Array:
	var all := PackedInt32Array([-1])
	var total := City.WIDTH*City.HEIGHT
	if image == null or _state.size() != state.size() or planes.size() != total or _planes.size() != total: return all
	for layer: int in 3:
		if _state[layer].size() != state[layer].size(): return all
	var marked := PackedByteArray()
	marked.resize(total)
	var changed := 0
	for layer: int in 2:
		var before: Variant = _state[layer]
		var after: Variant = state[layer]
		if after.size() != total: return all
		if before == after: continue
		for y: int in City.HEIGHT:
			var row := y*City.WIDTH
			if before.slice(row,row+City.WIDTH) == after.slice(row,row+City.WIDTH): continue
			for x: int in City.WIDTH:
				if before[row+x] != after[row+x]: changed += _mark(marked,x,y,TEXEL_REACH)
	var old_vertices: PackedByteArray = _state[2]
	var vertices: PackedByteArray = state[2]
	if old_vertices != vertices:
		var columns := City.WIDTH+1
		for v: int in vertices.size():
			if old_vertices[v] == vertices[v]: continue
			# The four cells around the vertex read it directly.
			for dy: int in [-1,0]:
				for dx: int in [-1,0]:
					changed += _mark(marked,v % columns+dx,v / columns+dy,TEXEL_REACH)
	var old_flood: Dictionary = _state[3]
	var flood: Dictionary = state[3]
	if old_flood != flood:
		for collection: Dictionary in [old_flood,flood]:
			for cell: Vector2i in collection:
				if old_flood.has(cell) != flood.has(cell): changed += _mark(marked,cell.x,cell.y,TEXEL_REACH)
	if _planes != planes:
		for y: int in City.HEIGHT:
			var row := y*City.WIDTH
			if _planes.slice(row,row+City.WIDTH) == planes.slice(row,row+City.WIDTH): continue
			for x: int in City.WIDTH:
				if _planes[row+x] != planes[row+x]: changed += _mark(marked,x,y,1)
	if changed*2 > total: return all
	var stale := PackedInt32Array()
	var at := marked.find(1)
	while at >= 0:
		stale.append(at)
		at = marked.find(1,at+1)
	return stale


## Marks the in-bounds cells within `reach` of (x, y); returns how many were new.
static func _mark(marked: PackedByteArray, x: int, y: int, reach: int) -> int:
	var added := 0
	for cy: int in range(maxi(0,y-reach),mini(City.HEIGHT,y+reach+1)):
		for cx: int in range(maxi(0,x-reach),mini(City.WIDTH,x+reach+1)):
			var index := cy*City.WIDTH+cx
			if marked[index] == 0:
				marked[index] = 1
				added += 1
	return added
