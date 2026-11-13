# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The water metadata texture rewrites only the texels a flood, height, terrain
## or lattice change can alter. After every change it equals a texture written
## completely from the same city, on imported per-tile terrain and on native
## shared-vertex terrain with standing water and stream beds.
extends "res://tests/test_case.gd"

const WaterStyle := preload("res://scripts/view/city_water_style_3d.gd")
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func _complete(city: City) -> PackedByteArray:
	var image := Image.create(City.WIDTH, City.HEIGHT, false, Image.FORMAT_RGBAF)
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			image.set_pixel(x, y, WaterStyle._texel(city, Vector2i(x, y)))
	return image.get_data()


static func _shore_cells(city: City) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			if city.is_water(x, y): continue
			for step: Vector2i in DIRS:
				if city.in_bounds(x + step.x, y + step.y) and city.is_water(x + step.x, y + step.y):
					found.append(Vector2i(x, y))
					break
	return found


func _sequence(label: String, city: City, steps: int) -> void:
	var style: RefCounted = WaterStyle.new()
	var builder := Builder.new(city, CityStats.new())
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(label)
	var shore := _shore_cells(city)
	check(not shore.is_empty(), label + ": the city has shoreline")
	var sampling := CityGeometry3D.begin_ground_sampling(city)
	style.update_city(city)
	check(style.image.get_data() == _complete(city), label + ": the first texture is complete")
	CityGeometry3D.end_ground_sampling(sampling)
	var total := City.WIDTH * City.HEIGHT
	var partial := 0
	var native := city.terrain_surface is TerrainSurface
	for step: int in steps:
		city.funds = 100000000
		var kind := step % 8
		var near: Vector2i = shore[rng.randi_range(0, shore.size() - 1)]
		var anywhere := Vector2i(rng.randi_range(1, City.WIDTH - 2), rng.randi_range(1, City.HEIGHT - 2))
		match kind:
			0, 1:
				# A flood spreading inland from the shore.
				var at := near
				for i: int in rng.randi_range(1, 6):
					if city.in_bounds(at.x, at.y): city.flood_overlay[at] = rng.randi_range(1, 3)
					at += DIRS[rng.randi_range(0, 3)]
			2:
				city.flood_overlay[anywhere] = 1
			3:
				# The flood recedes from some tiles.
				var wet: Array = city.flood_overlay.keys()
				for i: int in mini(wet.size(), rng.randi_range(1, 4)): city.flood_overlay.erase(wet[rng.randi_range(0, wet.size() - 1)])
			4:
				builder.apply(Tools.Kind.RAISE_LAND if rng.randi() % 2 == 0 else Tools.Kind.LOWER_LAND, near, near)
			5:
				if native: builder.apply(Tools.Kind.PLACE_WATER, near, near)
				else: city.altitude.put(anywhere.x, anywhere.y, (city.altitude.at(anywhere.x, anywhere.y) & ~City.ALT_MASK) | clampi((city.altitude.at(anywhere.x, anywhere.y) & City.ALT_MASK) + (1 if rng.randi() % 2 == 0 else -1), 0, City.ALT_MASK))
			6:
				builder.apply(Tools.Kind.LOWER_LAND if rng.randi() % 2 == 0 else Tools.Kind.RAISE_LAND, anywhere, anywhere)
			7:
				if step % 16 == 15: city.flood_overlay.clear()
				elif not native: city.terrain.put(near.x, near.y, Terrain.SURFACE if rng.randi() % 2 == 0 else 0)
				else: builder.apply(Tools.Kind.PLACE_WATER, anywhere, anywhere)
		sampling = CityGeometry3D.begin_ground_sampling(city)
		style.update_city(city)
		var expected := _complete(city)
		CityGeometry3D.end_ground_sampling(sampling)
		if style.last_rewritten < total: partial += 1
		var depth: Image = style.image.duplicate()
		depth.convert(Image.FORMAT_RGBAH)
		check(style.image.get_data() == expected, "%s step %d kind %d: texture equals a complete rewrite (%d texels rewritten)" % [label, step, kind, style.last_rewritten])
		check(style.depth_image.get_data() == depth.get_data(), "%s step %d: the filtered copy follows" % [label, step])
		if step % 12 == 0: shore = _shore_cells(city)
	print("    %s partial rewrites=%d of %d" % [label, partial, steps])
	check(partial * 4 >= steps * 3, label + ": most changes rewrite part of the texture (%d of %d)" % [partial, steps])
	# A complete rewrite of the final city agrees as well.
	var fresh: RefCounted = WaterStyle.new()
	fresh.incremental = false
	sampling = CityGeometry3D.begin_ground_sampling(city)
	fresh.update_city(city)
	CityGeometry3D.end_ground_sampling(sampling)
	check(fresh.image.get_data() == style.image.get_data(), label + ": the final texture equals a new style's")


func test_imported_terrain() -> void:
	_sequence("Harbor Palms", SaveFormat.load("res://assets/cities/Harbor Palms.sc2d").city, 64)
	_sequence("Oro Canyon", Sc2Import.load("res://assets/cities/Oro Canyon.sc2").city, 48)


func test_native_terrain() -> void:
	_sequence("Juniper Basin", SaveFormat.load("res://assets/cities/Juniper Basin.sc2d").city, 64)
	_sequence("Adaven", SaveFormat.load("res://assets/cities/Adaven.sc2d").city, 48)


## A flood day touches a few texels, not the whole map.
func test_flood_rewrites_few_texels() -> void:
	var city: City = SaveFormat.load("res://assets/cities/Harbor Palms.sc2d").city
	var style: RefCounted = WaterStyle.new()
	style.update_city(city)
	var shore := _shore_cells(city)
	for i: int in 4: city.flood_overlay[shore[i * 7]] = 1
	style.update_city(city)
	check(style.last_rewritten > 0 and style.last_rewritten <= 4 * 25, "four flood tiles rewrite at most their surroundings (%d)" % style.last_rewritten)
	check(style.image.get_data() == _complete(city), "and the texture equals a complete rewrite")
	for cell: Vector2i in city.flood_overlay: city.flood_overlay[cell] = 3
	style.update_city(city)
	check_eq(style.last_rewritten, 0, "a deeper flood on the same tiles rewrites nothing")
	check(style.image.get_data() == _complete(city), "and the texture is still complete")
