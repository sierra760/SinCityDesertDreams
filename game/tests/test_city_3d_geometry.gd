# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Terrain projection, public network geometry and read-only city ownership.
extends "res://tests/test_case.gd"

const Palm := preload("res://scripts/view/city_palm_3d.gd")


func test_encoded_slopes_keep_their_four_corner_heights() -> void:
	var city := flat_city()
	for shape: int in range(Terrain.PLATEAU + 1):
		city.terrain.put(10, 10, shape)
		var points := CityGeometry3D.cell_corners(city, Vector2i(10, 10))
		var raised := Terrain.raised_corners(shape)
		var corner_bits: Array[int] = [8, 1, 4, 2]
		for i: int in 4:
			var height := 4 + (1 if raised & corner_bits[i] else 0)
			check(is_equal_approx(points[i].y, height * CityGeometry3D.HEIGHT), "slope %d corner %d" % [shape, i])


func test_shared_vertices_are_used_without_rebuilding_the_city() -> void:
	var city := flat_city()
	var surface := TerrainSurface.new(4)
	surface.set_vertex(11, 10, 5)
	surface.set_vertex(10, 11, 6)
	city.terrain_surface = surface
	var before := surface.vertices.duplicate()
	var points := CityGeometry3D.cell_corners(city, Vector2i(10, 10))
	check(is_equal_approx(points[1].y, 5 * CityGeometry3D.HEIGHT))
	check(is_equal_approx(points[2].y, 6 * CityGeometry3D.HEIGHT))
	check(is_equal_approx(points[3].y, 4 * CityGeometry3D.HEIGHT))
	check_eq(points[1], CityGeometry3D.cell_corners(city, Vector2i(11, 10))[0])
	check_eq(surface.vertices, before)
	check_eq(city.ground_height(10, 10), 4, "the projection never repairs or rewrites heights")


func test_chunks_map_every_triangle_to_a_valid_cell_and_join_imported_heights() -> void:
	var city := flat_city()
	city.set_heights(10, 10, 8)
	var chunk := CityGeometry3D.build_chunk(city, Rect2i(9, 9, 3, 3))
	check_eq(chunk.faces.size(), 9 * 6, "imported height disagreements become shared grades without internal walls")
	check_eq(chunk.physical_obstacle_faces.size(),0,"dry interior edges cannot trap an actor against a skirt")
	check_eq(chunk.face_cells.size() * 3, chunk.faces.size())
	for cell: Vector2i in chunk.face_cells:
		check(Rect2i(9, 9, 3, 3).has_point(cell))
	for point: Vector3 in chunk.faces:
		check(point.is_finite())
	var outside := CityGeometry3D.build_chunk(city, Rect2i(-1, -1, 2, 2))
	for cell: Vector2i in outside.face_cells:
		check_eq(cell, Vector2i.ZERO, "chunk bounds clip at the city edge")


func test_water_and_flood_surfaces_remain_visible() -> void:
	var city := flat_city()
	city.terrain.put(10, 10, Terrain.SURFACE)
	city.set_heights(10, 10, 2, 5)
	var chunk := CityGeometry3D.build_chunk(city, Rect2i(10, 10, 1, 1))
	var faces: PackedVector3Array = chunk.faces
	check(is_equal_approx(faces[-1].y, 5 * CityGeometry3D.HEIGHT + 0.025))
	city.flood_overlay[Vector2i(20, 20)] = 1
	var flooded := CityGeometry3D.build_chunk(city, Rect2i(20, 20, 1, 1))
	check_gt(flooded.faces[-1].y, CityGeometry3D.ground_height(city, Vector2i(20, 20)))


func test_ground_is_continuous_in_color_and_zone_tint_is_read_only() -> void:
	var city := flat_city()
	city.zone.put(10, 10, Zones.make(Zones.RES_LOW))
	var before := var_to_bytes([city.altitude.data, city.terrain.data, city.zone.data, city.building.data, city.flags.data])
	var dry := CityGeometry3D.build_chunk(city, Rect2i(20, 20, 2, 1))
	var mesh: ArrayMesh = dry.mesh
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check_eq(colors[0], colors[6], "adjacent flat sand has no tile checker pattern")
	CityGeometry3D.build_chunk(city, Rect2i(10, 10, 1, 1))
	var networks := CityNetworks3D.new()
	networks.rebuild(city)
	networks.free()
	check_eq(var_to_bytes([city.altitude.data, city.terrain.data, city.zone.data, city.building.data, city.flags.data]), before)


func test_road_and_rail_bends_follow_the_public_network_shapes() -> void:
	for family: int in [NetworkShapes.Family.ROAD, NetworkShapes.Family.RAIL, NetworkShapes.Family.POWER]:
		for mask: int in [3, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15]:
			var code := NetworkShapes.shape_id(family, mask)
			check_eq(CityNetworks3D.network_mask(code, family), mask)
	check_eq(CityNetworks3D.network_mask(Buildings.id_of(&"rail_slope_w"), NetworkShapes.Family.RAIL), 10)
	check_eq(CityNetworks3D.network_mask(Buildings.id_of(&"road_slope_n"), NetworkShapes.Family.ROAD), 5)
	check_eq(CityNetworks3D.network_mask(NetworkShapes.CROSS_ROAD_NS_RAIL_EW, NetworkShapes.Family.ROAD), 5)
	check_eq(CityNetworks3D.network_mask(NetworkShapes.CROSS_ROAD_NS_RAIL_EW, NetworkShapes.Family.RAIL), 10)


func test_palms_have_full_height_and_isolated_trunk_collision() -> void:
	var palm := preload("res://scripts/view/city_palm_3d.gd").create(1.6, 0.38)
	var trunk: StaticBody3D = palm.get_node("PalmTrunk")
	check_eq(trunk.collision_layer, 4)
	check_eq(trunk.collision_mask, 0)
	var shape: CollisionShape3D = trunk.get_child(0)
	check(is_equal_approx(shape.shape.height, 1.6))
	check_gt(palm.get_child_count(), 2, "trunk and arching canopy are separate geometry")
	palm.free()


func test_imported_stream_directions_do_not_become_ground_slopes() -> void:
	var city := flat_city()
	for direction: int in 6:
		city.terrain.put(10, 10, Terrain.STREAM + direction)
		var points := CityGeometry3D.cell_corners(city, Vector2i(10, 10))
		for point: Vector3 in points:
			check(is_equal_approx(point.y, 4 * CityGeometry3D.HEIGHT), "direction %d stays level" % direction)
		check_gt(CityGeometry3D.surface_height(city, Vector2i(10, 10)), points[0].y)


func test_highway_crossings_and_slopes_keep_their_own_axes() -> void:
	for code: int in [NetworkShapes.HIGHWAY_NS_ROAD_EW, NetworkShapes.HIGHWAY_NS_RAIL_EW, NetworkShapes.HIGHWAY_NS_POWER_EW,
		NetworkShapes.HIGHWAY_SLOPE_N, NetworkShapes.HIGHWAY_SLOPE_S]:
		check_eq(CityNetworks3D.network_mask(code, NetworkShapes.Family.HIGHWAY), 5)
	for code: int in [NetworkShapes.HIGHWAY_EW_ROAD_NS, NetworkShapes.HIGHWAY_EW_RAIL_NS, NetworkShapes.HIGHWAY_EW_POWER_NS,
		NetworkShapes.HIGHWAY_SLOPE_W, NetworkShapes.HIGHWAY_SLOPE_E]:
		check_eq(CityNetworks3D.network_mask(code, NetworkShapes.Family.HIGHWAY), 10)
	for family: int in [NetworkShapes.Family.ROAD, NetworkShapes.Family.RAIL, NetworkShapes.Family.POWER]:
		var i := family - NetworkShapes.Family.ROAD
		var north_south: int = [NetworkShapes.HIGHWAY_EW_ROAD_NS, NetworkShapes.HIGHWAY_EW_RAIL_NS, NetworkShapes.HIGHWAY_EW_POWER_NS][i]
		var east_west: int = [NetworkShapes.HIGHWAY_NS_ROAD_EW, NetworkShapes.HIGHWAY_NS_RAIL_EW, NetworkShapes.HIGHWAY_NS_POWER_EW][i]
		check_eq(CityNetworks3D.network_mask(north_south, family), 5)
		check_eq(CityNetworks3D.network_mask(east_west, family), 10)


func test_curved_roads_stay_in_the_tile_and_rail_has_two_tracks() -> void:
	var city := flat_city()
	var layer := CityNetworks3D.new()
	for mask: int in [3, 6, 9, 12]:
		layer.clear()
		layer._draw_network(city, Vector2i(10, 10), NetworkShapes.Family.ROAD, mask, 0.04)
		check_gt(layer._faces.size(), 6 * 16, "bend is a segmented arc with shoulders")
		for point: Vector3 in layer._faces:
			check(point.x >= 10.0 - 0.00001 and point.x <= 11.0 + 0.00001)
			check(point.z >= 10.0 - 0.00001 and point.z <= 11.0 + 0.00001)
		for i: int in range(0, layer._faces.size(), 3):
			var a: Vector3 = layer._faces[i]
			var b: Vector3 = layer._faces[i + 1]
			var c: Vector3 = layer._faces[i + 2]
			check((b - a).cross(c - a).y <= 0.0, "arc faces follow Godot clockwise winding")
	layer.clear()
	layer._draw_network(city, Vector2i(10, 10), NetworkShapes.Family.RAIL, 5, 0.04)
	check(layer._colors.has(Color(0.72, 0.75, 0.71)), "steel rails have their own material")
	check(layer._colors.has(Color(0.40, 0.33, 0.26)), "rail sleepers are visible")
	layer.free()


func test_corner_facets_and_network_heights_match_canonical_terrain() -> void:
	var city := flat_city()
	var cell := Vector2i(10, 10)
	var samples: Array[Vector2] = [Vector2(0.5, 0.5), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.2, 0.3)]
	# Fixed canonical facet samples; no historical drawing script is loaded.
	var lifts: Array = [[0.0, 0.0, 0.0, 0.0], [0.5, 0.25, 0.75, 0.8], [0.5, 0.75, 0.25, 0.7], [0.5, 0.75, 0.25, 0.2], [0.5, 0.25, 0.75, 0.3], [1.0, 1.0, 1.0, 1.0], [1.0, 1.0, 0.5, 0.9], [1.0, 1.0, 1.0, 0.5], [1.0, 0.5, 1.0, 1.0], [0.0, 0.0, 0.0, 0.5], [0.0, 0.5, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.5, 0.1], [1.0, 1.0, 1.0, 1.0]]
	for shape: int in range(Terrain.PLATEAU + 1):
		city.terrain.putv(cell, shape)
		for index: int in samples.size():
			var sample: Vector2 = samples[index]
			var expected := (4.0 + float(lifts[shape][index])) * CityGeometry3D.HEIGHT
			check(is_equal_approx(CityGeometry3D.point_over_corners(CityGeometry3D.cell_corners(city,cell),cell,sample).y, expected), "encoded shape %d at %s remains unchanged" % [shape, sample])
	city.terrain.putv(cell, Terrain.CORNER_NE)
	# A real shared editing lattice still keeps its authored corner facet.
	city.terrain_surface = TerrainSurface.new(4)
	city.terrain_surface.set_vertex(11,10,5)
	check(is_equal_approx(CityGeometry3D.ground_height(city, cell), 4 * CityGeometry3D.HEIGHT), "the center lies on the flat diagonal, not the average of all four corners")
	var chunk := CityGeometry3D.build_chunk(city, Rect2i(cell, Vector2i.ONE))
	var corners := CityGeometry3D.cell_corners(city, cell)
	check_eq(chunk.faces[1], corners[3], "NE-corner terrain chooses the NW-SE diagonal")
	check_eq(chunk.faces[2], corners[0])
	var layer := CityNetworks3D.new()
	var offset := Vector2(0.75, 0.25)
	check(is_equal_approx(layer._point(city, cell, offset, 0.04).y, (4.0 + 0.5) * CityGeometry3D.HEIGHT + 0.04))
	layer.free()


func test_every_emitted_road_triangle_follows_one_terrain_face() -> void:
	var city := flat_city()
	var cell := Vector2i(10, 10)
	var layer := CityNetworks3D.new()
	var elevation := 0.04
	for shape: int in range(Terrain.PLATEAU + 1):
		city.terrain.putv(cell, shape)
		layer.clear()
		layer._rect(city, cell, Rect2(0.2, 0.2, 0.6, 0.6), Color.GRAY, elevation)
		for mask: int in [3, 6, 9, 12]:
			layer._arc(city, cell, mask, 0.6, Color.GRAY, elevation)
		for i: int in range(0, layer._faces.size(), 3):
			var a: Vector3 = layer._faces[i]
			var b: Vector3 = layer._faces[i + 1]
			var c: Vector3 = layer._faces[i + 2]
			# Centroids and edge midpoints catch a face that bridges across a crease.
			for sample: Vector3 in [(a + b + c) / 3.0, (a + b) / 2.0, (b + c) / 2.0, (a + c) / 2.0]:
				var offset := Vector2(sample.x - cell.x, sample.z - cell.y)
				var expected := CityGeometry3D.point_on_ground(city, cell, offset).y + elevation
				check(absf(sample.y - expected) < 0.00001, "shape %d face %d stays on the terrain plane" % [shape, i / 3])
			check((b - a).cross(c - a).y <= 0.0, "split faces follow Godot clockwise winding")
	layer.free()


func test_front_facing_meshes_store_upward_shading_normals() -> void:
	var city := flat_city()
	var chunk := CityGeometry3D.build_chunk(city, Rect2i(10, 10, 1, 1))
	var terrain_mesh: ArrayMesh = chunk.mesh
	# Godot octahedrally packs normals; native PlaneMesh also returns a 0.000015 Z residual.
	var terrain_normals: PackedVector3Array = terrain_mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for normal: Vector3 in terrain_normals:
		check(normal.distance_to(Vector3.UP) < 0.00004, "flat terrain is lit from above within packed-normal precision")
	var layer := CityNetworks3D.new()
	layer._draw_network(city, Vector2i(10, 10), NetworkShapes.Family.ROAD, 3, 0.04)
	var road_mesh := CityGeometry3D.mesh_from_faces(layer._faces, layer._colors)
	var road_normals: PackedVector3Array = road_mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var top_count := 0
	var side_count := 0
	for i: int in range(0,layer._faces.size(),3):
		var geometric := (layer._faces[i+2]-layer._faces[i]).cross(layer._faces[i+1]-layer._faces[i]).normalized()
		var side := absf(geometric.y)<.00001
		if side: side_count+=1
		else:
			top_count+=1
			check(geometric.distance_to(Vector3.UP)<.00004,"curved road top retains upward winding")
		for j: int in 3:
			if side:
				# Diagonal normals have angle-dependent decoded error. Test in
				# Godot's octahedral domain: at most one 16-bit storage step.
				var error := (road_normals[i+j].octahedron_encode()-geometric.octahedron_encode()).abs()
				check(maxf(error.x,error.y)<=1.0/65535.0,"curb normal stays within one encoded normal unit")
			else:
				check(road_normals[i+j].distance_to(Vector3.UP)<.00004,
					"curved pavement keeps its original upward-normal bound")
	check(top_count>0 and side_count>0,"the curved road exercises top and solid side normals")
	var native_plane := PlaneMesh.new()
	var native_arrays := native_plane.get_mesh_arrays()
	var native_vertices: PackedVector3Array = native_arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = native_arrays[Mesh.ARRAY_INDEX]
	var a := native_vertices[indices[0]]
	var b := native_vertices[indices[1]]
	var c := native_vertices[indices[2]]
	check((b - a).cross(c - a).y < 0.0, "Godot's native upward-facing plane establishes clockwise winding")
	layer.free()


func test_boundary_skirts_face_outward_on_all_four_sides() -> void:
	var city := flat_city()
	var cells: Array[Vector2i] = [Vector2i(10, 0), Vector2i(City.WIDTH - 1, 10),
		Vector2i(10, City.HEIGHT - 1), Vector2i(0, 10)]
	var outward: Array[Vector3] = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	for side: int in 4:
		var cell := cells[side]
		var chunk := CityGeometry3D.build_chunk(city, Rect2i(cell, Vector2i.ONE))
		var faces: PackedVector3Array = chunk.faces
		var mesh: ArrayMesh = chunk.mesh
		var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		check_eq(faces.size(), 12, "one flat top and one exposed boundary skirt")
		for i: int in range(6, faces.size(), 3):
			var geometric := (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).normalized()
			check(geometric.dot(outward[side]) > 0.9999, "side %d has outward clockwise triangles" % side)
			for vertex: int in range(i, i + 3):
				check(normals[vertex].distance_to(outward[side]) < 0.00004,
					"side %d stores outward normals within packed-normal precision" % side)
			check_eq(chunk.face_cells[i / 3], cell, "skirt picking retains its boundary cell")


## Face meshes share one material per (grain, kind); palm crowns keep their own
## registered materials so generic surfaces never qualify as static crowns.
func test_face_meshes_share_materials_but_crowns_stay_distinct() -> void:
	var tri := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.BACK])
	var colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	var a := CityGeometry3D.mesh_from_faces(tri, colors, 0.025, CityGeometry3D.SurfaceKind.TERRAIN)
	var b := CityGeometry3D.mesh_from_faces(tri, colors, 0.025, CityGeometry3D.SurfaceKind.TERRAIN)
	var c := CityGeometry3D.mesh_from_faces(tri, colors, 0.025, CityGeometry3D.SurfaceKind.NETWORK)
	var d := CityGeometry3D.mesh_from_faces(tri, colors)
	check(a.surface_get_material(0) == b.surface_get_material(0), "identical parameters share one material")
	check(a.surface_get_material(0) != c.surface_get_material(0), "surface kinds keep separate materials")
	var shared := d.surface_get_material(0) as ShaderMaterial
	check_eq(shared.get_shader_parameter("surface_kind"), CityGeometry3D.SurfaceKind.DETAIL)
	check_eq(shared.get_shader_parameter("grain_strength"), 0.0)
	var palm := Palm.create(0.73, 0.21, 3)
	var crown: Material = null
	for node: MeshInstance3D in palm.find_children("*", "MeshInstance3D", true, false): crown = node.mesh.surface_get_material(0)
	check(crown != null and crown != shared, "crowns keep their own material")
	check(Palm.is_static_crown_material(crown), "crown material remains registered for batching")
	check(not Palm.is_static_crown_material(shared), "the shared generic material never qualifies as a crown")
	palm.free()
