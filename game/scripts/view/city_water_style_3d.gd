# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Shared visual water material and its geometry metadata. No city writes or RNG.
extends RefCounted

var elapsed := 0.0
var enabled := true
var image: Image
var texture: ImageTexture
var material: ShaderMaterial
var _city: City
var _state: Array = []

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
func update_city(city: City) -> void:
	var vertices: PackedByteArray = city.terrain_surface.vertices if city.terrain_surface is TerrainSurface else PackedByteArray()
	var state: Array = [city.altitude.data.duplicate(),city.terrain.data.duplicate(),vertices.duplicate(),city.flood_overlay.duplicate(true)]
	if state == _state:
		_city = city
		return
	_city = city
	_state = state
	image = Image.create(City.WIDTH,City.HEIGHT,false,Image.FORMAT_RGBAF)
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var cell := Vector2i(x,y)
			var ground := CityGeometry3D.visible_ground_height(city,cell)
			var level := CityGeometry3D.water_surface_height(city,cell) if city.is_water(x,y) else -1.0
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
			image.set_pixel(x,y,Color(level,ground,float(shelf),bottom))
	if texture == null:
		texture = ImageTexture.create_from_image(image)
		material.set_shader_parameter("water_geometry",texture)
		material.set_shader_parameter("water_depth",texture)
	else:
		texture.update(image)
