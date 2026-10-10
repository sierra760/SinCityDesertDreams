# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func visible(city: City, cell: Vector2i) -> Array:
	return CityGeometry3D.build_chunk(city,Rect2i(cell,Vector2i.ONE)).mesh.surface_get_arrays(0)


func test_shallow_standing_water_patch_cannot_form_an_elevated_hill() -> void:
	var city := flat_city(20000, 4)
	var surface := TerrainSurface.new(4)
	for y: int in range(10, 15):
		for x: int in range(10, 15):
			surface.set_water(x, y, 6)
	surface.project(city)
	var before := SaveFormat.encode_city(city)
	var bank_level := 4 * CityGeometry3D.HEIGHT + CityGeometry3D.BED_FILM
	# Interior, shore and neighboring chunks must all share the same plane.
	var data := CityGeometry3D.build_chunk(city, Rect2i(9, 9, 7, 7))
	var sampled := 0
	for i: int in data.faces.size():
		if not data.colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR): continue
		sampled += 1
		check(is_equal_approx(data.faces[i].y, bank_level), "standing water stays level with its low bank, including interior triangles")
	check_gt(sampled, 100)
	for cell: Vector2i in [Vector2i(10, 10), Vector2i(12, 12), Vector2i(14, 14)]:
		check(is_equal_approx(CityGeometry3D.water_surface_height(city, cell), bank_level), "water queries use the same flat plane")
		var arrays := visible(city, cell)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i: int in points.size():
			if colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR):
				check(is_equal_approx(points[i].y, bank_level), "a separate chunk finds the whole patch's bank")
	check_eq(SaveFormat.encode_city(city), before, "display correction preserves saved water and terrain")


func test_water_queries_recompute_after_raw_bank_edits() -> void:
	var city := flat_city(20000, 4)
	var surface := TerrainSurface.new(4)
	for y: int in range(10, 15):
		for x: int in range(10, 15): surface.set_water(x, y, 6)
	surface.project(city)
	var center := Vector2i(12, 12)
	check(is_equal_approx(CityGeometry3D.water_surface_height(city, center), 4 * CityGeometry3D.HEIGHT + CityGeometry3D.BED_FILM))
	surface.vertices[10 * TerrainSurface.VERTS_X + 10] = 3
	check(is_equal_approx(CityGeometry3D.water_surface_height(city, center), 3 * CityGeometry3D.HEIGHT + CityGeometry3D.BED_FILM),
		"a direct vertex write invalidates the cached whole-patch height")
	surface.vertices[10 * TerrainSurface.VERTS_X + 10] = 4
	check(is_equal_approx(CityGeometry3D.water_surface_height(city, center), 4 * CityGeometry3D.HEIGHT + CityGeometry3D.BED_FILM),
		"restoring the bank restores the water plane")

func test_streams_retain_dry_banks_and_direction() -> void:
	var city:=flat_city()
	for variant in 6:
		city.terrain.put(10,10,Terrain.STREAM+variant)
		var arrays:=visible(city,Vector2i(10,10))
		var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		var area:=0.0
		for i in range(0,points.size(),3):
			if colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR):
				area+=(points[i+1]-points[i]).cross(points[i+2]-points[i]).length()*.5
		check(area>.1 and area<.8,"stream must be a channel with exposed banks, variant %d area %f"%[variant,area])
		var low_x:=100.0;var high_x:=-100.0;var low_z:=100.0;var high_z:=-100.0
		for i in points.size():
			if colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR):
				low_x=minf(low_x,points[i].x);high_x=maxf(high_x,points[i].x)
				low_z=minf(low_z,points[i].z);high_z=maxf(high_z,points[i].z)
		if variant==0: check(high_x-low_x<.7 and is_equal_approx(high_z-low_z,1),"variant0 north/south")
		if variant==1: check(high_z-low_z<.7 and is_equal_approx(high_x-low_x,1),"variant1 west/east")

func test_submerged_shore_keeps_visible_raised_edge_without_mutating_height() -> void:
	var city:=flat_city()
	city.set_heights(10,10,4,5)
	city.terrain.put(10,10,Terrain.SHORE|Terrain.SLOPE_E)
	var before:=SaveFormat.encode_city(city)
	var arrays:=visible(city,Vector2i(10,10))
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var water:=CityGeometry3D.water_surface_height(city,Vector2i(10,10))
	var land:=false
	for i in points.size():
		if points[i].y>water and points[i].x>10.8 and not colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR): land=true
	check(land,"encoded eastern shore is visible even when seabed is below water")
	check_eq(SaveFormat.encode_city(city),before,"visual shore does not rewrite height or water data")

func test_waterfall_has_vertical_water_only_on_exposed_drop() -> void:
	var city:=flat_city()
	city.set_heights(10,10,4,5)
	city.terrain.put(10,10,Terrain.WATERFALL)
	city.set_heights(10,11,2,3)
	city.terrain.put(10,11,Terrain.SURFACE)
	var arrays:=visible(city,Vector2i(10,10))
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var cascade:=false
	for i in range(0,points.size(),3):
		if colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR) and absf((points[i+1]-points[i]).cross(points[i+2]-points[i]).normalized().y)<.1:
			cascade=true
	check(cascade,"fall displays water down exposed terrain face")

func test_imported_surface_codes_do_not_turn_water_into_dry_mountains() -> void:
	var city:=flat_city()
	city.set_heights(10,10,21,21)
	city.terrain.put(10,10,Terrain.SURFACE|Terrain.SLOPE_E)
	var before:=SaveFormat.encode_city(city)
	var arrays:=visible(city,Vector2i(10,10))
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var water:=CityGeometry3D.water_surface_height(city,Vector2i(10,10))
	for p: Vector3 in points:
		check(p.y<=water+.009,"imported wet shape selects shore mask, not an above-water hillside")
	check_eq(SaveFormat.encode_city(city),before)

func test_both_waterfall_codes_have_outward_cascades() -> void:
	var city:=flat_city()
	city.set_heights(10,10,4,5)
	for code: int in [0x2e,0x3e]:
		city.terrain.put(10,10,code)
		var arrays:=visible(city,Vector2i(10,10))
		var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		var count:=0
		for i in range(0,points.size(),3):
			var normal:=(points[i+2]-points[i]).cross(points[i+1]-points[i]).normalized()
			if colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR) and absf(normal.y)<.1:
				var center:=(points[i]+points[i+1]+points[i+2])/3
				var outward:=Vector3(center.x-10.5,0,center.z-10.5).normalized()
				check(normal.dot(outward)>.9,"waterfall normal must face away from the cell")
				count+=1
		check_eq(count,8,"both waterfall codes cascade on four lower neighboring sides")


func test_imported_waterfall_blocks_join_the_upper_water_without_square_pits() -> void:
	# Imported cities have full-block waterfalls at ground/water 4/4 beside water 5,
	# and 6/6 beside water 7. The imported water word is the block's lower baseline.
	for code: int in [0x2e, 0x3e]:
		for baseline: int in [4, 6]:
			var city := flat_city(20000, baseline + 1)
			var cell := Vector2i(10, 10)
			city.terrain.putv(cell, code)
			city.set_heights(10, 10, baseline, baseline)
			for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var neighbor := cell + direction
				city.terrain.putv(neighbor, 0x20)
				var level := 5 if baseline == 6 and direction == Vector2i.DOWN else baseline + 1
				city.set_heights(neighbor.x, neighbor.y, level - 1, level)
			var before := SaveFormat.encode_city(city)
			var data := CityGeometry3D.build_chunk(city, Rect2i(cell, Vector2i.ONE))
			var arrays: Array = data.mesh.surface_get_arrays(0)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var top := (baseline + 1) * CityGeometry3D.HEIGHT + 0.025
			var horizontal := 0
			var vertical := 0
			for i: int in range(0, points.size(), 3):
				if not colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR):
					continue
				var normal := (points[i + 2] - points[i]).cross(points[i + 1] - points[i]).normalized()
				if normal.y > 0.9:
					horizontal += 1
					for vertex: int in range(i, i + 3):
						check(is_equal_approx(points[vertex].y, top), "imported waterfall upper face joins adjacent upper water")
				elif absf(normal.y) < 0.1:
					vertical += 1
					check(normal.z > 0.9, "the cascade only faces the lower southern pool")
					var low := minf(points[i].y, minf(points[i + 1].y, points[i + 2].y))
					var high := maxf(points[i].y, maxf(points[i + 1].y, points[i + 2].y))
					check(is_equal_approx(low, 5 * CityGeometry3D.HEIGHT + 0.025), "cascade reaches the retained lower pool")
					check(is_equal_approx(high, top), "cascade begins at the actual upper water face")
			check_eq(horizontal, 2, "a full waterfall block retains its complete water diamond")
			check_eq(vertical, 2 if baseline == 6 else 0, "no faces or pits are invented between equal upper water levels")
			check(is_equal_approx(CityGeometry3D.surface_height(city, cell), top), "surface queries use the same visible upper face")
			for corner: Vector3 in CityGeometry3D.surface_corners(city, cell):
				check(is_equal_approx(corner.y, top), "cursor corners follow the visible water block")
			check_eq(data.face_cells.size() * 3, data.faces.size(), "picking triangles retain their complete cell map")
			check_eq(SaveFormat.encode_city(city), before, "water geometry cannot rewrite imported water or terrain bytes")


func test_native_waterfall_levels_and_flood_precedence_are_preserved() -> void:
	var cell := Vector2i(10, 10)
	var city := flat_city()
	var surface := TerrainSurface.new(4)
	surface.set_water(10, 10, 5, false, TerrainSurface.Feature.WATERFALL)
	surface.project(city)
	for code: int in [0x2e, 0x3e]:
		city.terrain.putv(cell, code)
		var before := SaveFormat.encode_city(city)
		check_eq(city.water_height(10, 10), 5, "native TerrainSurface stores the upper water level directly")
		check(is_equal_approx(CityGeometry3D.water_surface_height(city, cell), 4 * CityGeometry3D.HEIGHT + CityGeometry3D.BED_FILM),
			"native fall water is drawn on its bed, not a level above its banks")
		CityGeometry3D.build_chunk(city, Rect2i(cell, Vector2i.ONE))
		check_eq(SaveFormat.encode_city(city), before, "native saved water and vertices remain unchanged")
		var restored: City = SaveFormat.decode_city(before).city
		check_eq(restored.water_height(10, 10), 5, "native upper water level remains stored after save and reload")
		check(is_equal_approx(CityGeometry3D.water_surface_height(restored, cell), 4 * CityGeometry3D.HEIGHT + CityGeometry3D.BED_FILM),
			"native fall presentation is unchanged after save and reload")
	city.terrain_surface = null
	city.set_heights(10, 10, 4, 4)
	city.flood_overlay[cell] = 1
	for code: int in [0x2e, 0x3e]:
		city.terrain.putv(cell, code)
		check(is_equal_approx(CityGeometry3D.water_surface_height(city, cell), 4 * CityGeometry3D.HEIGHT + 0.12),
			"temporary flood presentation takes precedence over the imported block lift")


func test_saved_imported_waterfall_baselines_keep_their_visible_upper_faces() -> void:
	for code: int in [0x2e, 0x3e]:
		for baseline: int in [4, 6]:
			var cell := Vector2i(10, 10)
			var city := flat_city(20000, baseline + 1)
			city.terrain.putv(cell, code)
			city.set_heights(10, 10, baseline, baseline)
			for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var neighbor := cell + direction
				city.terrain.putv(neighbor, 0x20)
				city.set_heights(neighbor.x, neighbor.y, baseline, baseline + 1)
			var layers: Dictionary = SaveFormat.encode_city(city).layers
			for cycle: int in 2:
				var restored := SaveFormat.decode_city(SaveFormat.encode_city(city))
				check_eq(restored.error, "", "imported waterfall save must load")
				city = restored.city
				check(city.terrain_surface == null, "per-tile terrain loads without a lattice")
				var before := SaveFormat.encode_city(city)
				var arrays := visible(city, cell)
				var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				var top := (baseline + 1) * CityGeometry3D.HEIGHT + 0.025
				for i: int in range(0, points.size(), 3):
					if not colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR):
						continue
					var normal := (points[i + 2] - points[i]).cross(points[i + 1] - points[i]).normalized()
					if normal.y > 0.9:
						check(is_equal_approx(points[i].y, top), "saved imported waterfall keeps its upper face through reload %d" % cycle)
				check(is_equal_approx(CityGeometry3D.water_surface_height(city, cell), top), "reloading cannot lower the imported water block")
				check(is_equal_approx(CityGeometry3D.surface_height(city, cell), top), "saved imported water picking follows the rendered face")
				check_eq(SaveFormat.encode_city(city), before, "rendering the restored city is read-only")
				check_eq(before.layers, layers, "save and reload preserve all imported layer bytes")


func test_tagged_imported_water_and_banks_keep_exact_geometry_through_reload() -> void:
	var city := flat_city()
	var waterfall := Vector2i(10, 10)
	var shore := Vector2i(11, 10)
	var road_bank := Vector2i(12, 10)
	city.terrain.putv(waterfall, 0x3e)
	city.set_heights(10, 10, 4, 4)
	city.terrain.putv(shore, 0x33)
	city.set_heights(11, 10, 5, 5)
	city.terrain.putv(road_bank, 0x03)
	city.set_heights(12, 10, 5, 5)
	city.building.putv(road_bank, 30)
	var cells: Array[Vector2i] = [waterfall, shore, road_bank]
	var corners: Array[PackedVector3Array] = []
	var water: Array[float] = []
	for cell: Vector2i in cells:
		corners.append(CityGeometry3D.visible_cell_corners(city, cell))
		water.append(CityGeometry3D.water_surface_height(city, cell))
	var bounds := Rect2i(9, 9, 5, 3)
	var original := CityGeometry3D.build_chunk(city, bounds)
	var original_arrays: Array = original.mesh.surface_get_arrays(0)
	var layers: Dictionary = SaveFormat.encode_city(city).layers
	for cycle: int in 2:
		var document := SaveFormat.encode_city(city)
		check_eq(document.get("terrain_model"), "per_tile", "a raw imported city saves its terrain ownership explicitly")
		var restored := SaveFormat.decode_city(document)
		check_eq(restored.error, "", "tagged imported city must load")
		city = restored.city
		check(city.terrain_surface == null, "loading per-tile terrain cannot construct or attach a different lattice")
		var before := SaveFormat.encode_city(city)
		var chunk := CityGeometry3D.build_chunk(city, bounds)
		var arrays: Array = chunk.mesh.surface_get_arrays(0)
		check_eq(arrays[Mesh.ARRAY_VERTEX], original_arrays[Mesh.ARRAY_VERTEX], "rendered water, shore and bank faces remain exact through roundtrip %d" % cycle)
		check_eq(arrays[Mesh.ARRAY_COLOR], original_arrays[Mesh.ARRAY_COLOR], "shore and water colors remain exact after load")
		check_eq(chunk.faces, original.faces, "construction picking retains the exact imported terrain and water faces")
		check_eq(chunk.face_cells, original.face_cells, "all preserved picking faces retain their tile owners")
		for index: int in cells.size():
			check_eq(CityGeometry3D.visible_cell_corners(city, cells[index]), corners[index], "imported visible bank and water corners remain unchanged")
			check_eq(CityGeometry3D.water_surface_height(city, cells[index]), water[index], "water heights remain exact through save and reload")
		check_eq(before.layers, layers, "all raw imported layers remain exact after tagged load")
		check_eq(SaveFormat.encode_city(city), before, "rendering the tagged imported city cannot change its save data")


func test_waterfall_lift_is_bounded_to_its_encoding_and_keeps_flood_order() -> void:
	var cell := Vector2i(10, 10)
	var city := flat_city()
	city.set_heights(10, 10, 4, 4)
	for code: int in [0x10, 0x20, 0x30, 0x13, 0x23, 0x33]:
		city.terrain.putv(cell, code)
		check(is_equal_approx(CityGeometry3D.water_surface_height(city, cell), 4 * CityGeometry3D.HEIGHT + 0.025),
			"ordinary wet codes retain their stored water level")
	for code: int in [0x2e, 0x3e]:
		city.terrain.putv(cell, code)
		city.set_heights(10, 10, 6, 4)
		TerrainSurface.from_city(city)
		var before := SaveFormat.encode_city(city)
		check(is_equal_approx(CityGeometry3D.water_surface_height(city, cell), 5 * CityGeometry3D.HEIGHT + 0.025),
			"an inconsistent legacy height retains its encoded block baseline instead of adopting reconstructed water")
		check_eq(SaveFormat.encode_city(city), before, "invalid legacy heights are not silently repaired by rendering")
		city.set_heights(10, 10, 4, 6)
		city.terrain_surface = TerrainSurface.new(4)
		city.flood_overlay[cell] = 1
		check(is_equal_approx(CityGeometry3D.water_surface_height(city, cell), 6 * CityGeometry3D.HEIGHT + 0.025),
			"flood precedence preserves a stored water level already above the temporary flood height")
		city.flood_overlay.clear()


func test_wet_plateau_retains_sand_rim() -> void:
	var city:=flat_city()
	city.set_heights(10,10,4,5)
	city.terrain.put(10,10,Terrain.SHORE|Terrain.PLATEAU)
	var arrays:=visible(city,Vector2i(10,10))
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var land:=0
	var water:=CityGeometry3D.water_surface_height(city,Vector2i(10,10))
	for i in points.size():
		if points[i].y>water and not colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR): land+=1
	check(land>=24,"four-edge wet plateau preserves its visible sand rim")

func test_subway_cut_exposes_throat_and_keeps_terrain_queries() -> void:
	var city:=flat_city()
	city.building.put(10,10,Buildings.SUBWAY_PORTAL_FIRST)
	var data:=CityGeometry3D.build_chunk(city,Rect2i(10,10,1,1))
	var points: PackedVector3Array=data.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var horizontal_area:=0.0
	for i in range(0,points.size(),3):
		horizontal_area+=absf((points[i+1]-points[i]).cross(points[i+2]-points[i]).y)*.5
	check(horizontal_area<.65,"ground cannot cover descending rail mouth")
	check_eq(data.face_cells.size()*3,data.faces.size(),"construction picking retains its face-to-cell map")
	check_eq(data.faces.size(),6,"original flat terrain picking stays intact")


## Water on a native lattice must never hang above the dry bank it meets.
func _check_grounded(city: City, label: String) -> int:
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var edges := [[0, 1], [1, 3], [3, 2], [2, 0]]
	var checked := 0
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var cell := Vector2i(x, y)
			if not city.is_water(x, y): continue
			var water := CityGeometry3D.water_corners(city, cell)
			var ground := CityGeometry3D.visible_cell_corners(city, cell)
			if CityGeometry3D.is_bed_water(city, cell):
				for i: int in 4:
					check(is_equal_approx(water[i].y, ground[i].y + CityGeometry3D.BED_FILM), "%s %s flowing water follows its bed" % [label, cell])
			for e: int in 4:
				var neighbor: Vector2i = cell + directions[e]
				if not city.in_bounds(neighbor.x, neighbor.y) or city.is_water(neighbor.x, neighbor.y): continue
				for corner: int in edges[e]:
					checked += 1
					check(water[corner].y <= ground[corner].y + CityGeometry3D.BED_FILM + 0.0001,
						"%s %s water meets its dry bank instead of floating above it" % [label, cell])
	return checked


func test_generated_river_water_rests_on_its_bed_and_banks() -> void:
	for config: Array in [[1, "none"], [3, "south"]]:
		var city := TerrainGenerator.new().generate({"river": true, "coast": config[1]}, SimRng.new(config[0]))
		var flowing := 0
		for i: int in City.WIDTH * City.HEIGHT:
			if city.terrain_surface.feature[i] != TerrainSurface.Feature.NONE: flowing += 1
		check_gt(flowing, 10, "seed %d carves a river" % config[0])
		var before := SaveFormat.encode_city(city)
		check_gt(_check_grounded(city, "seed %d" % config[0]), 100, "river banks are sampled")
		# The rendered water triangles share the same corners and ground facets.
		var fall := Vector2i(-1, -1)
		for i: int in City.WIDTH * City.HEIGHT:
			if city.terrain_surface.feature[i] == TerrainSurface.Feature.WATERFALL:
				fall = Vector2i(i % City.WIDTH, i / City.WIDTH)
				break
		check(fall.x >= 0, "seed %d river has a waterfall" % config[0])
		var bounds := Rect2i(fall - Vector2i(4, 4), Vector2i(9, 9)).intersection(Rect2i(0, 0, City.WIDTH, City.HEIGHT))
		var data := CityGeometry3D.build_chunk(city, bounds)
		var water_vertices := 0
		for i: int in range(0, data.faces.size(), 3):
			if not data.colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR): continue
			var a: Vector3 = data.faces[i]
			var normal: Vector3 = (data.faces[i + 2] - a).cross(data.faces[i + 1] - a).normalized()
			if absf(normal.y) < 0.1: continue
			for k: int in 3:
				var p: Vector3 = data.faces[i + k]
				var owner: Vector2i = data.face_cells[i / 3]
				var ground := CityGeometry3D.visible_ground_height(city, owner, Vector2(p.x - owner.x, p.z - owner.y))
				if CityGeometry3D.is_bed_water(city, owner):
					water_vertices += 1
					check(absf(p.y - ground - CityGeometry3D.BED_FILM) < 0.0001, "seed %d bed water vertex %s lies on its bed" % [config[0], p])
		check_gt(water_vertices, 12, "seed %d waterfall neighborhood draws bed water" % config[0])
		check_eq(SaveFormat.encode_city(city), before, "drawing generated water never rewrites the city")


func test_generated_river_meets_the_sea_flush() -> void:
	var city := TerrainGenerator.new().generate({"river": true, "coast": "south"}, SimRng.new(3))
	var surface: TerrainSurface = city.terrain_surface
	var mouths := 0
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			if surface.feature_at(x, y) != TerrainSurface.Feature.STREAM: continue
			for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var n := Vector2i(x, y) + direction
				if not city.in_bounds(n.x, n.y) or not city.is_water(n.x, n.y) or surface.feature_at(n.x, n.y) != TerrainSurface.Feature.NONE: continue
				mouths += 1
				check_eq(surface.tile_base(x, y), city.sea_level, "the river bed reaches sea level at its mouth")
				check(absf(CityGeometry3D.water_surface_height(city, Vector2i(x, y)) - CityGeometry3D.water_surface_height(city, n)) < 0.02,
					"river water at %s meets the estuary at the same height" % Vector2i(x, y))
	check_gt(mouths, 0, "the river reaches the sea")


func test_native_waterfall_is_a_grounded_cascade_joining_both_reaches() -> void:
	var city := flat_city()
	var surface := TerrainSurface.new(4)
	var fall := Vector2i(10, 10)
	var upstream := Vector2i(10, 9)
	var downstream := Vector2i(10, 11)
	surface.set_tile_height(upstream.x, upstream.y, 5)
	surface.set_water(upstream.x, upstream.y, 6, false, TerrainSurface.Feature.STREAM)
	surface.set_water(fall.x, fall.y, 5, false, TerrainSurface.Feature.WATERFALL)
	surface.set_water(downstream.x, downstream.y, 5, false, TerrainSurface.Feature.STREAM)
	surface.project(city)
	check_eq(city.terrain.atv(fall), Terrain.WATERFALL)
	var before := SaveFormat.encode_city(city)
	var water := CityGeometry3D.water_corners(city, fall)
	var top := 5 * CityGeometry3D.HEIGHT + CityGeometry3D.BED_FILM
	var bottom := 4 * CityGeometry3D.HEIGHT + CityGeometry3D.BED_FILM
	check(is_equal_approx(water[0].y, top) and is_equal_approx(water[1].y, top), "the fall begins at the upstream water")
	check(is_equal_approx(water[2].y, bottom) and is_equal_approx(water[3].y, bottom), "the fall ends at the downstream water")
	check(is_equal_approx(CityGeometry3D.water_corners(city, upstream)[2].y, top), "upstream reach shares the fall's top edge")
	check(is_equal_approx(CityGeometry3D.water_corners(city, downstream)[0].y, bottom), "downstream reach shares the fall's foot")
	var data := CityGeometry3D.build_chunk(city, Rect2i(9, 8, 3, 5))
	var sloped := false
	for i: int in range(0, data.faces.size(), 3):
		if not data.colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR): continue
		var normal: Vector3 = (data.faces[i + 2] - data.faces[i]).cross(data.faces[i + 1] - data.faces[i]).normalized()
		check(absf(normal.y) > 0.1, "no water curtain hangs beside a grounded cascade")
		if data.face_cells[i / 3] == fall and normal.y < 0.99: sloped = true
	check(sloped, "the fall is drawn as water running down its bed")
	check_eq(SaveFormat.encode_city(city), before, "drawing never rewrites the native lattice or water")


func test_native_standing_water_meets_low_banks_and_spills_between_levels() -> void:
	# A pond in a basin whose rim stands at the water level stays level.
	var city := flat_city()
	var surface := TerrainSurface.new(6)
	for vx: int in range(11, 14):
		surface.set_vertex(vx, 11, 4)
	for x: int in range(10, 14):
		for y: int in range(10, 12):
			surface.set_water(x, y, 6 if x < 12 else 5)
	surface.project(city)
	var before := SaveFormat.encode_city(city)
	for corner: Vector3 in CityGeometry3D.water_corners(city, Vector2i(10, 10)):
		check(is_equal_approx(corner.y, 6 * CityGeometry3D.HEIGHT + 0.025), "a supported pond keeps its stored level")
	# The lower pond's rim is above its water; the higher pond pours into it.
	for corner: Vector3 in CityGeometry3D.water_corners(city, Vector2i(13, 10)):
		check(is_equal_approx(corner.y, 5 * CityGeometry3D.HEIGHT + 0.025), "the lower pond is level too")
	var data := CityGeometry3D.build_chunk(city, Rect2i(9, 9, 6, 4))
	var spill := 0
	for i: int in range(0, data.faces.size(), 3):
		if not data.colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR): continue
		var normal: Vector3 = (data.faces[i + 2] - data.faces[i]).cross(data.faces[i + 1] - data.faces[i]).normalized()
		if absf(normal.y) >= 0.1: continue
		spill += 1
		check_eq(data.face_cells[i / 3].x, 11, "only the higher pond emits the step")
		check(normal.x > 0.9, "the spill faces the lower pond")
		for k: int in 3:
			var y: float = data.faces[i + k].y
			check(is_equal_approx(y, 6 * CityGeometry3D.HEIGHT + 0.025) or is_equal_approx(y, 5 * CityGeometry3D.HEIGHT + 0.025),
				"the spill joins both water surfaces exactly")
	check_eq(spill, 4, "two edges of the higher pond pour into the lower pond")
	check_eq(SaveFormat.encode_city(city), before)
	# Water stored above low dry banks, as imported shallow beds can be, meets them.
	city = flat_city()
	surface = TerrainSurface.new(4)
	surface.set_water(10, 10, 6)
	surface.project(city)
	check_gt(_check_grounded(city, "shallow"), 3, "the shallow tile's banks are sampled")
	check(CityGeometry3D.water_surface_height(city, Vector2i(10, 10)) < 4 * CityGeometry3D.HEIGHT + 0.1,
		"queries use the grounded surface")



func test_one_tile_channels_share_one_water_width() -> void:
	var city := TerrainGenerator.new().generate({"river": true, "coast": "none"}, SimRng.new(1))
	var surface: TerrainSurface = city.terrain_surface
	var half := CityGeometry3D.CHANNEL_WIDTH * 0.5
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var kinds := {}
	var before := SaveFormat.encode_city(city)
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var cell := Vector2i(x, y)
			if not CityGeometry3D.is_bed_water(city, cell) or CityGeometry3D.fuses_with_body(city, cell): continue
			var code := city.terrain.atv(cell)
			var kind := "fall" if code == Terrain.WATERFALL else "straight" if code >= Terrain.STREAM else "bend"
			kinds[kind] = int(kinds.get(kind, 0)) + 1
			var data := CityGeometry3D.build_chunk(city, Rect2i(cell, Vector2i.ONE))
			var faces: PackedVector3Array = data.faces
			var colors: PackedColorArray = data.colors
			var reach := [[INF, -INF], [INF, -INF], [INF, -INF], [INF, -INF]]
			for i: int in range(0, faces.size(), 3):
				if not colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR): continue
				var normal: Vector3 = (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).normalized()
				if absf(normal.y) < 0.1: continue
				for k: int in 3:
					var local := Vector2(faces[i + k].x - x, faces[i + k].z - y)
					check(absf(local.x - 0.5) <= half + 0.0001 or absf(local.y - 0.5) <= half + 0.0001,
						"%s %s water stays inside the channel strip" % [kind, cell])
					var on_edge := [local.y < 0.0001, local.x > 0.9999, local.y > 0.9999, local.x < 0.0001]
					for e: int in 4:
						if not on_edge[e]: continue
						var along: float = local.x if e % 2 == 0 else local.y
						reach[e][0] = minf(reach[e][0], along)
						reach[e][1] = maxf(reach[e][1], along)
			for e: int in 4:
				var n: Vector2i = cell + directions[e]
				var wet := city.in_bounds(n.x, n.y) and city.is_water(n.x, n.y)
				if not city.in_bounds(n.x, n.y):
					# A channel running straight off the map reaches the edge.
					var inside: Vector2i = cell - directions[e]
					wet = city.in_bounds(inside.x, inside.y) and city.is_water(inside.x, inside.y)
				if wet:
					check(is_equal_approx(reach[e][1] - reach[e][0], CityGeometry3D.CHANNEL_WIDTH),
						"%s %s meets its wet neighbour with the shared channel width" % [kind, cell])
				else:
					check(reach[e][0] == INF, "%s %s leaves its dry side as bank" % [kind, cell])
	for kind: String in ["straight", "bend", "fall"]:
		check_gt(int(kinds.get(kind, 0)), 0, "the river includes %s channel tiles" % kind)
	check(surface == city.terrain_surface)
	check_eq(SaveFormat.encode_city(city), before, "drawing channels never rewrites the city")


func _water_area(data: Dictionary) -> float:
	var faces: PackedVector3Array = data.faces
	var colors: PackedColorArray = data.colors
	var area := 0.0
	for i: int in range(0, faces.size(), 3):
		if colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR):
			area += absf((faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i]).y) * 0.5
	return area


func test_river_tiles_beside_a_water_body_fuse_with_it() -> void:
	# Seed 3's river runs down the side of its estuary before entering it.
	var city := TerrainGenerator.new().generate({"river": true, "coast": "south"}, SimRng.new(3))
	var before := SaveFormat.encode_city(city)
	var fused := 0
	var bodies := 0
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var cell := Vector2i(x, y)
			if not city.is_water(x, y): continue
			if CityGeometry3D.fuses_with_body(city, cell):
				fused += 1
				var data := CityGeometry3D.build_chunk(city, Rect2i(cell, Vector2i.ONE))
				check(absf(_water_area(data) - 1.0) < 0.001, "river tile %s beside a water body is full water" % cell)
				continue
			if CityGeometry3D.is_bed_water(city, cell): continue
			# Body shoreline shelves only mark corners that touch real land.
			var shelves := CityGeometry3D.shore_shelf_mask(city, cell)
			var vertices: Array[Vector2i] = [cell + Vector2i(1, 0), cell + Vector2i(1, 1), cell + Vector2i(0, 1), cell]
			for i: int in 4:
				if not shelves & (1 << i): continue
				bodies += 1
				var land := false
				for dy: int in range(-1, 1):
					for dx: int in range(-1, 1):
						var t := vertices[i] + Vector2i(dx, dy)
						if not city.in_bounds(t.x, t.y): continue
						land = land or not city.is_water(t.x, t.y) \
							or (CityGeometry3D.is_bed_water(city, t) and not CityGeometry3D.fuses_with_body(city, t))
				check(land, "%s shelf corner %d touches land" % [cell, i])
	check_gt(fused, 2, "river tiles alongside and entering the estuary fuse with it")
	check_gt(bodies, 10, "shoreline shelves are sampled")
	# The estuary edge beside the fused river reach keeps no sand between them.
	for y: int in [91, 92]:
		var edge := Vector2i(29, y)
		check(CityGeometry3D.fuses_with_body(city, Vector2i(30, y)), "river tile beside estuary fuses")
		check_eq(CityGeometry3D.shore_shelf_mask(city, edge) & 3, 0, "no sand shelf separates the estuary from the fused river at row %d" % y)
	check_eq(SaveFormat.encode_city(city), before, "fusing is presentation only")



## Vertical water faces of one chunk along the map edge `step` points across.
func _edge_falls(data: Dictionary, step: Vector2i) -> Array[Array]:
	var falls: Array[Array] = []
	for i: int in range(0, data.faces.size(), 3):
		if not data.colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR): continue
		var normal: Vector3 = (data.faces[i + 2] - data.faces[i]).cross(data.faces[i + 1] - data.faces[i]).normalized()
		if normal.dot(Vector3(step.x, 0, step.y)) < 0.9: continue
		falls.append([data.faces[i], data.faces[i + 1], data.faces[i + 2]])
	return falls


func test_water_at_the_city_limits_falls_down_the_map_edge() -> void:
	# Imported open water on the west edge pours down to the block's base.
	var city := flat_city()
	for y: int in range(10, 13):
		city.set_heights(0, y, 2, 4)
		city.terrain.put(0, y, Terrain.SURFACE)
	var before := SaveFormat.encode_city(city)
	var data := CityGeometry3D.build_chunk(city, Rect2i(0, 9, 2, 5))
	var falls := _edge_falls(data, Vector2i.LEFT)
	check_eq(falls.size(), 6, "each of the three edge water tiles falls off the map")
	var water := CityGeometry3D.water_surface_height(city, Vector2i(0, 10))
	var low := 100.0
	var high := -100.0
	for triangle: Array in falls:
		for p: Vector3 in triangle:
			low = minf(low, p.y)
			high = maxf(high, p.y)
			check(p.x < 0.0, "the fall stands just outside the sand skirt")
	check(is_equal_approx(high, water), "the fall starts at the water surface")
	check(is_equal_approx(low, -CityGeometry3D.HEIGHT), "the fall reaches the base of the terrain block")
	check(_edge_falls(data, Vector2i.RIGHT).is_empty(), "interior edges keep their ordinary water")
	check(_edge_falls(CityGeometry3D.build_chunk(city, Rect2i(1, 9, 2, 5)), Vector2i.LEFT).is_empty(),
		"dry land beside the water gets no fall")
	check_eq(SaveFormat.encode_city(city), before, "drawing edge falls never rewrites the city")
	# A generated sea along the south edge pours over the whole coastline.
	city = TerrainGenerator.new().generate({"river": false, "coast": "south"}, SimRng.new(3))
	data = CityGeometry3D.build_chunk(city, Rect2i(0, City.HEIGHT - 1, City.WIDTH, 1))
	var wet := 0
	for x: int in City.WIDTH:
		if city.is_water(x, City.HEIGHT - 1): wet += 1
	check_gt(wet, City.WIDTH / 2, "the coast reaches the south edge")
	check_gt(_edge_falls(data, Vector2i.DOWN).size(), wet, "the sea falls over the south edge")


func test_river_running_off_the_map_reaches_its_edge_fall() -> void:
	var city := flat_city()
	var surface := TerrainSurface.new(4)
	for x: int in range(0, 4):
		surface.set_tile_height(x, 10, 3)
		surface.set_water(x, 10, 4, false, TerrainSurface.Feature.STREAM)
	surface.project(city)
	check(CityGeometry3D.is_bed_water(city, Vector2i(0, 10)) and not CityGeometry3D.fuses_with_body(city, Vector2i(0, 10)),
		"the edge tile is a one-tile channel")
	var data := CityGeometry3D.build_chunk(city, Rect2i(0, 10, 1, 1))
	var falls := _edge_falls(data, Vector2i.LEFT)
	check_eq(falls.size(), 2, "the channel pours off the map")
	for triangle: Array in falls:
		for p: Vector3 in triangle:
			check(absf(p.z - 10.5) <= CityGeometry3D.CHANNEL_WIDTH * 0.5 + 0.0001, "only the channel's width falls")
	var reaches := false
	for i: int in range(0, data.faces.size(), 3):
		if not data.colors[i].is_equal_approx(CityGeometry3D.WATER_COLOR): continue
		for k: int in 3:
			if data.faces[i + k].x < 0.001 and data.faces[i + k].y > 0.0: reaches = true
	check(reaches, "the channel surface runs to the map edge")
