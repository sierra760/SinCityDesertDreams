# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## A build-local cache must be observationally identical to live terrain sampling.
extends "res://tests/exploration/async_test_case.gd"

var view: CityView3D
var callback_count := 0

func after_each() -> void:
	if is_instance_valid(view): view.free()
	view = null
	check(CityGeometry3D._ground_sampling_city == null,"every completed scope releases its City")
	check(CityGeometry3D._ground_vertex_cache.is_empty(),"every completed scope releases its samples")
	await process_frame

func _city(base := 4) -> City:
	var city := City.new()
	city.altitude.data.fill(base)
	return city

func _samples(city: City, cells: Array[Vector2i]) -> Array:
	var result: Array = []
	for cell: Vector2i in cells:
		result.append(CityGeometry3D.ground_corners(city,cell))
		result.append(CityGeometry3D.visible_cell_corners(city,cell))
		for offset: Vector2 in [Vector2(.1,.2),Vector2(.5,.5),Vector2(.9,.7)]:
			result.append(CityGeometry3D.point_on_ground(city,cell,offset))
	return result

func test_exact_sampling_across_slopes_water_flood_and_city_edges() -> void:
	var city := _city()
	var cells: Array[Vector2i] = [Vector2i.ZERO,Vector2i(127,0),Vector2i(0,127),Vector2i(127,127)]
	for slope: int in 16:
		var cell := Vector2i(20+slope,20)
		city.terrain.putv(cell,slope)
		city.altitude.put(cell.x,cell.y,3+slope%4)
		cells.append(cell)
	city.terrain.put(21,19,Terrain.SURFACE)
	city.set_heights(21,19,1,5)
	city.terrain.put(24,19,Terrain.STREAM)
	city.set_heights(24,19,2,3)
	city.flood_overlay[Vector2i(27,19)] = 1
	cells.append_array([Vector2i(21,19),Vector2i(24,19),Vector2i(27,19)])
	var before := _samples(city,cells)
	var untouched := CityGeometry3D.ground_corners(city,Vector2i(45,45))
	var original_altitude := city.altitude.data.duplicate()
	var original_terrain := city.terrain.data.duplicate()
	var scope := CityGeometry3D.begin_ground_sampling(city)
	check_eq(_samples(city,cells),before,"cached ground, visible facets and interpolation are exact")
	var entries := CityGeometry3D._ground_vertex_cache.size()
	check_gt(entries,0,"imported dry vertices populate the active cache")
	check_eq(_samples(city,cells),before,"repeat samples stay exact")
	check_eq(CityGeometry3D._ground_vertex_cache.size(),entries,"repeat samples reuse the same vertices")
	var canonical := CityGeometry3D.ground_corners(city,cells[0]).duplicate()
	var edited := CityGeometry3D.ground_corners(city,cells[0])
	edited[0].y += 100
	check_eq(CityGeometry3D.ground_corners(city,cells[0]),canonical,"mutating a returned packed array cannot corrupt stored corners")
	var other := CityGeometry3D.ground_corners(city,cells[0])
	other.resize(0)
	check_eq(CityGeometry3D.ground_corners(city,cells[0]),canonical,"resizing a returned packed array cannot corrupt stored corners")
	var first_return := CityGeometry3D.ground_corners(city,Vector2i(45,45))
	first_return[0].y += 100
	check_eq(CityGeometry3D.ground_corners(city,Vector2i(45,45)),untouched,"first returned value is detached from stored cache")
	CityGeometry3D.end_ground_sampling(scope)
	check_eq(city.altitude.data,original_altitude,"sampling does not alter altitude")
	check_eq(city.terrain.data,original_terrain,"sampling does not alter terrain codes")

func test_city_identity_nested_context_and_native_lattice_bypass() -> void:
	var first := _city(3)
	var second := _city(9)
	var cell := Vector2i(16,16)
	var expected_first := CityGeometry3D.ground_corners(first,cell)
	var expected_second := CityGeometry3D.ground_corners(second,cell)
	var outer := CityGeometry3D.begin_ground_sampling(first)
	check_eq(CityGeometry3D.ground_corners(first,cell),expected_first)
	var samples := CityGeometry3D._ground_vertex_cache.duplicate()
	check_eq(CityGeometry3D.ground_corners(second,cell),expected_second,"other City falls through to its own live inputs")
	check_eq(CityGeometry3D._ground_vertex_cache,samples,"other City cannot contaminate active cache")
	var inner := CityGeometry3D.begin_ground_sampling(second)
	check_eq(CityGeometry3D.ground_corners(second,cell),expected_second)
	CityGeometry3D.end_ground_sampling(inner)
	check(CityGeometry3D._ground_sampling_city == first,"nested scope restores previous owner")
	check_eq(CityGeometry3D._ground_vertex_cache,samples,"nested scope restores previous samples")
	CityGeometry3D.end_ground_sampling(outer)
	first.terrain_surface = TerrainSurface.new(5)
	first.terrain_surface.vertices[16*TerrainSurface.VERTS_X+16] = 8
	var native := CityGeometry3D.cell_corners(first,cell)
	outer = CityGeometry3D.begin_ground_sampling(first)
	check_eq(CityGeometry3D.ground_corners(first,cell),native,"native shared lattice passes through exactly")
	check(CityGeometry3D._ground_vertex_cache.is_empty(),"native terrain does not fill imported-vertex cache")
	CityGeometry3D.end_ground_sampling(outer)

func test_completed_scope_does_not_hide_in_place_input_changes() -> void:
	var city := _city()
	var cell := Vector2i(20,20)
	var cells: Array[Vector2i] = [cell]
	var scope := CityGeometry3D.begin_ground_sampling(city)
	var original := _samples(city,cells)
	CityGeometry3D.end_ground_sampling(scope)
	city.altitude.data[20*City.WIDTH+20] = 10
	var elevated := _samples(city,cells)
	check(elevated!=original,"live altitude edit changes dry boundary")
	scope = CityGeometry3D.begin_ground_sampling(city)
	check_eq(_samples(city,cells),elevated,"new scope reads edited altitude")
	CityGeometry3D.end_ground_sampling(scope)
	city.terrain.data[20*City.WIDTH+20] = Terrain.SLOPE_W
	var sloped := _samples(city,cells)
	check(sloped!=elevated,"live slope edit changes dry boundary")
	scope = CityGeometry3D.begin_ground_sampling(city)
	check_eq(_samples(city,cells),sloped,"new scope reads edited slope")
	CityGeometry3D.end_ground_sampling(scope)
	city.flood_overlay[cell] = 1
	var flooded := _samples(city,cells)
	check(flooded!=sloped,"live flood changes sampling and visible water boundary")
	scope = CityGeometry3D.begin_ground_sampling(city)
	check_eq(_samples(city,cells),flooded,"new scope reads flood membership")
	CityGeometry3D.end_ground_sampling(scope)
	city.flood_overlay.clear()
	check_eq(_samples(city,cells),sloped,"removing flood restores prior exact samples")

func _callback_probe(_revision := -1) -> void:
	callback_count += 1
	check(CityGeometry3D._ground_sampling_city == null,"view signal runs outside sampling scope")
	check(CityGeometry3D._ground_vertex_cache.is_empty(),"view signal cannot see retained samples")
	var cell := Vector2i(15,15)
	var before := CityGeometry3D.ground_corners(view.city,cell)
	var retained: Array[int] = []
	for y: int in range(14,17):
		for x: int in range(14,17):
			retained.append(view.city.altitude.at(x,y))
			view.city.altitude.put(x,y,view.city.altitude.at(x,y)+4)
	check(CityGeometry3D.ground_corners(view.city,cell)!=before,"callback query sees freshly edited terrain")
	var index := 0
	for y: int in range(14,17):
		for x: int in range(14,17):
			view.city.altitude.put(x,y,retained[index])
			index += 1

func _triangles(faces: PackedVector3Array) -> Array:
	var values: Array = []
	for i: int in range(0,faces.size(),3): values.append(var_to_bytes(faces.slice(i,i+3)).hex_encode())
	values.sort()
	return values

func test_refresh_callbacks_and_partial_chunk_boundary_match_full_build() -> void:
	var city := _city()
	for x: int in range(13,19): city.building.put(x,15,30)
	view = CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	callback_count = 0
	view.view_changed.connect(_callback_probe)
	view.geometry_rebuilt.connect(_callback_probe)
	view.set_active(true)
	check_gt(callback_count,1,"both camera and geometry callbacks were exercised")
	var revision := view._geometry_revision
	view.refresh()
	check_eq(view._geometry_revision,revision,"no-change refresh does not rebuild")
	check(CityGeometry3D._ground_sampling_city == null,"early return leaves no cache owner")
	city.altitude.data[15*City.WIDTH+15] = 6
	city.terrain.data[15*City.WIDTH+15] = Terrain.SLOPE_W
	view.refresh()
	check_eq(view.refresh_statistics.terrain_chunks,4,"chunk-corner edit rebuilds all dependent terrain chunks")
	var partial := view.traversal_snapshot()
	var floors := _triangles(partial.networks.physical_floor_faces)
	var obstacles := _triangles(partial.networks.physical_obstacle_faces)
	view.refresh(true)
	var full := view.traversal_snapshot()
	var equal := true
	for index: int in full.chunks.size():
		for key: String in full.chunks[index]:
			if key != "mesh" and full.chunks[index][key]!=partial.chunks[index][key]: equal = false
	check(equal,"partial cached terrain/query/physical output equals forced full build")
	check_eq(_triangles(full.networks.physical_floor_faces),floors,"network floors equal forced full build")
	check_eq(_triangles(full.networks.physical_obstacle_faces),obstacles,"network obstacles equal forced full build")
