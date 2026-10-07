# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Imported independent grades must form one visible, pickable, physical surface.
## Restoring per-cell corners in any consumer must break these seam checks.
extends "res://tests/test_case.gd"

static func hillside(along_z := false) -> City:
	var city := flat_city()
	for y in range(16,32):
		for x in range(16,32):
			city.terrain.put(x,y,7)
			city.set_heights(x,y,4+(y if along_z else x)-16)
	return city

func test_imported_dry_edges_share_every_endpoint_and_interior_sample() -> void:
	var city := hillside()
	var before := var_to_bytes(SaveFormat.encode_city(city))
	for y in range(18,29):
		for x in range(18,29):
			var cell := Vector2i(x,y)
			var a := CityGeometry3D.visible_cell_corners(city,cell)
			var east := CityGeometry3D.visible_cell_corners(city,cell+Vector2i.RIGHT)
			var south := CityGeometry3D.visible_cell_corners(city,cell+Vector2i.DOWN)
			check_eq(a[1],east[0],"east NW endpoint cannot leave a wall or gap")
			check_eq(a[3],east[2],"east SW endpoint cannot leave a wall or gap")
			check_eq(a[2],south[0],"south NW endpoint agrees")
			check_eq(a[3],south[1],"south NE endpoint agrees")
			for t: float in [0.0,.25,.5,.75,1.0]:
				check(absf(CityGeometry3D.point_on_ground(city,cell,Vector2(1,t)).y-CityGeometry3D.point_on_ground(city,cell+Vector2i.RIGHT,Vector2(0,t)).y)<.00001,"route heights meet along the full edge")
	check_eq(var_to_bytes(SaveFormat.encode_city(city)),before,"projection preserves every saved city field")
	check_eq(city.terrain_surface,null,"presentation cannot install a simulation lattice")

func test_chunks_have_no_internal_terrain_walls_and_pick_the_visible_floor() -> void:
	var city := hillside()
	var chunk := CityGeometry3D.build_chunk(city,Rect2i(20,20,2,2))
	check_eq(chunk.physical_obstacle_faces.size(),0,"continuous interior hills have no skirt obstacles")
	check_eq(chunk.faces,chunk.physical_floor_faces,"dry terrain picking and physical floor use exactly the visible triangles")
	var mesh_faces: PackedVector3Array = chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check_eq(mesh_faces,chunk.faces,"visible dry mesh agrees with query triangles")
	for i in range(0,chunk.faces.size(),3):
		var a: Vector3=chunk.faces[i];var b: Vector3=chunk.faces[i+1];var c: Vector3=chunk.faces[i+2]
		check((c-a).cross(b-a).normalized().y>=CityTraversalWorld3D.MIN_NORMAL_Y,"ordinary reconstructed hills remain traversable")

func test_road_graph_and_mesh_meet_across_the_imported_grade() -> void:
	var city := hillside()
	for x in range(18,26): city.building.put(x,22,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	for x in range(19,25):
		var cell := Vector2i(x,22)
		for lane: float in [-.20,0.0,.20]:
			var a := graph.point(cell,&"road",Vector2(1,.5+lane))
			var b := graph.point(cell+Vector2i.RIGHT,&"road",Vector2(0,.5+lane))
			check(a.distance_to(b)<.00001,"road and pedestrian lanes share a continuous seam")
			check(absf(a.y-CityGeometry3D.visible_ground_height(city,cell,Vector2(1,.5+lane))-.04)<.00001,"routes stay on visible pavement")
	layer.free()

func test_flat_lots_keep_level_foundations_at_sloping_neighbors() -> void:
	var city := flat_city()
	city.terrain.put(21,20,7)
	city.building.put(20,20,Buildings.RES_1X1_FIRST)
	for point: Vector3 in CityGeometry3D.visible_cell_corners(city,Vector2i(20,20)):
		check(absf(point.y-4*CityGeometry3D.HEIGHT)<.00001,"a flat lot supplies its shared boundary height")
	check_eq(CityGeometry3D.visible_cell_corners(city,Vector2i(20,20))[3],CityGeometry3D.visible_cell_corners(city,Vector2i(21,20))[2],"neighbor meets the level foundation")

func test_shared_surface_survives_save_reload_and_direct_boundary_edits() -> void:
	var city := hillside()
	for y in range(20,25):
		for x in range(30,34):
			city.terrain.put(x,y,7)
			city.set_heights(x,y,4+x-16)
	city.set_heights(31,22,18)
	city.terrain.put(32,22,7)
	city.set_heights(32,22,19)
	var before := CityGeometry3D.point_on_ground(city,Vector2i(31,22),Vector2(1,.5))
	city.set_heights(32,22,20)
	var left := CityGeometry3D.build_chunk(city,Rect2i(31,22,1,1))
	var right := CityGeometry3D.build_chunk(city,Rect2i(32,22,1,1))
	var after := CityGeometry3D.point_on_ground(city,Vector2i(31,22),Vector2(1,.5))
	check(before!=after,"direct array edits invalidate the neighboring shared edge without a stale cache")
	check_eq(after,CityGeometry3D.point_on_ground(city,Vector2i(32,22),Vector2(0,.5)),"independently rebuilt chunks still meet")
	check_eq(left.physical_obstacle_faces.size(),0)
	check_eq(right.physical_obstacle_faces.size(),0)
	var result := SaveFormat.decode_city(SaveFormat.encode_city(city))
	check_eq(result.error,"")
	var restored: City = result.city
	check_eq(CityGeometry3D.build_chunk(restored,Rect2i(31,22,2,1)).faces,CityGeometry3D.build_chunk(city,Rect2i(31,22,2,1)).faces,"native per-tile reload preserves the exact continuous presentation")

func test_diagonal_does_not_create_an_artificially_unwalkable_face() -> void:
	var city := flat_city()
	city.terrain_surface = TerrainSurface.new(5)
	# A La Presa grade has these shared heights. Splitting NE-SW
	# gives a 60-degree face; NW-SE gives two supported faces below 55 degrees.
	city.terrain_surface.set_vertex(20,20,7)
	city.terrain_surface.set_vertex(21,21,4)
	var data := CityGeometry3D.build_chunk(city,Rect2i(20,20,1,1))
	var faces: PackedVector3Array = data.physical_floor_faces
	for i in range(0,faces.size(),3):
		var normal := (faces[i+2]-faces[i]).cross(faces[i+1]-faces[i]).normalized()
		check(normal.y>=CityTraversalWorld3D.MIN_NORMAL_Y,"a suitable diagonal keeps the existing height samples walkable")
	check_eq(data.faces,faces,"visible, query and collision faces use the same safe diagonal")
	var network := CityNetworks3D.new()
	network._rect(city,Vector2i(20,20),Rect2(0,0,1,1),Color.GRAY,.04)
	for i in range(0,network._faces.size(),3):
		var center: Vector3 = (network._faces[i]+network._faces[i+1]+network._faces[i+2])/3.0
		var p := Vector2(center.x-20,center.z-20)
		var expected: float = (7*(1-p.x)+5*(p.x-p.y)+4*p.y) if p.x>=p.y else (7*(1-p.y)+5*(p.y-p.x)+4*p.x)
		check(absf(center.y-expected*CityGeometry3D.HEIGHT-.04)<.00001,"pavement is split on the same gentler diagonal")
	network.free()

func test_encoded_plateau_does_not_make_the_adjoining_grade_unwalkable() -> void:
	var city := flat_city()
	# Heights from Foothills Ranch cells 61..63,18..20. The fully raised plateau code
	# cannot pin its cap above the surrounding shared hill readings.
	var heights := [[11,10,10],[12,11,11],[13,12,12]]
	var codes := [[8,8,4],[8,8,4],[13,8,12]]
	for y in 3:
		for x in 3:
			city.set_heights(20+x,20+y,heights[y][x])
			city.terrain.put(20+x,20+y,codes[y][x])
	var faces: PackedVector3Array = CityGeometry3D.build_chunk(city,Rect2i(21,21,1,1)).physical_floor_faces
	for i in range(0,faces.size(),3):
		check((faces[i+2]-faces[i]).cross(faces[i+1]-faces[i]).normalized().y>=CityTraversalWorld3D.MIN_NORMAL_Y,"plateau joins must be as usable as the surrounding grade")
