# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Street-level rays must meet solid material below raised road and lot surfaces.
extends "res://tests/test_case.gd"

func _hit(faces: PackedVector3Array, a: Vector3, b: Vector3) -> bool:
	for i: int in range(0,faces.size(),3):
		if Geometry3D.segment_intersects_triangle(a,b,faces[i],faces[i+1],faces[i+2]) != null: return true
	return false

func test_road_layers_close_their_exposed_edges_on_flat_and_creased_ground() -> void:
	for sloped: bool in [false,true]:
		var city := flat_city()
		var cell := Vector2i(20,20)
		if sloped:
			city.terrain_surface = TerrainSurface.new(4)
			city.terrain_surface.set_vertex(21,21,5)
		city.building.putv(cell,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5))
		var layer := CityNetworks3D.new()
		layer._build_region(city,Rect2i(cell,Vector2i.ONE))
		for z: float in [.11,.37,.63,.89]:
			for probe: Vector2 in [Vector2(0,.012),Vector2(.1625,.028),Vector2(.2,.037)]:
				var at := CityGeometry3D.point_on_ground(city,cell,Vector2(probe.x,z))+Vector3.UP*probe.y
				check(_hit(layer._faces,at-Vector3.RIGHT*.009,at+Vector3.RIGHT*.009),"visible edge closes below raised surface slope=%s x=%s z=%s"%[sloped,probe.x,z])
		layer.free()

## Hit a grounded wall facing `normal` (horizontal); tile-border walls between
## neighboring pieces cannot stand in for a missing diagonal edge.
func _wall_hit(faces: PackedVector3Array, a: Vector3, b: Vector3, normal: Vector2) -> bool:
	for i: int in range(0,faces.size(),3):
		var n := (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i])
		var flat := Vector2(n.x,n.z)
		if flat.length()<.000001 or absf(n.y)>flat.length()*.001 or absf(flat.normalized().dot(normal))<.999: continue
		if Geometry3D.segment_intersects_triangle(a,b,faces[i],faces[i+1],faces[i+2]) != null: return true
	return false

## Bend tiles are straight diagonal strips between their saved edge intercepts.
## The shoulder (.60 pavement plus .075) meets each tile border .1625 and .8375
## from the turn corner; both diagonal edges must stay solid down to the terrain.
func _shoulder_edges_closed(city: City, region: Rect2i, edges: Array, label: String) -> void:
	var layer := CityNetworks3D.new()
	layer._build_region(city,region)
	for edge: Array in edges:
		var from: Vector2 = edge[0]
		var to: Vector2 = edge[1]
		var normal := (to-from).normalized().orthogonal()
		var stops: Array[float] = [.0005,.002,.9980,.9995]
		for i: int in 48: stops.append((i+.5)/48.0)
		for join: float in edge.slice(2):
			for side: float in [-.002,-.0005,.0005,.002]: stops.append(join+side)
		for t: float in stops:
			var p := from.lerp(to,t)
			var cell := Vector2i(floori(p.x),floori(p.y)).clamp(region.position,region.end-Vector2i.ONE)
			var at := CityGeometry3D.point_on_ground(city,cell,p-Vector2(cell))+Vector3.UP*.028
			var across := Vector3(normal.x,0,normal.y)*.004
			check(_wall_hit(layer._faces,at-across,at+across,normal),"bend shoulder has continuous solid edge %s edge=%s->%s t=%.4f"%[label,from,to,t])
	layer.free()

func test_bend_shoulders_close_along_straight_diagonals() -> void:
	var cell := Vector2i(20,20)
	for sloped: bool in [false,true]:
		for mask: int in [3,6,9,12]:
			var city := flat_city()
			if sloped:
				city.terrain_surface = TerrainSurface.new(4)
				city.terrain_surface.set_vertex(21,21,5)
			city.building.putv(cell,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,mask))
			var corner: Vector2 = Vector2(cell)+{3:Vector2(1,0),6:Vector2(1,1),12:Vector2(0,1),9:Vector2(0,0)}[mask]
			var first: Vector2 = {3:Vector2.LEFT,6:Vector2.UP,12:Vector2.RIGHT,9:Vector2.DOWN}[mask]
			var last: Vector2 = {3:Vector2.DOWN,6:Vector2.LEFT,12:Vector2.UP,9:Vector2.RIGHT}[mask]
			var edges: Array = []
			for offset: float in [.1625,.8375]:
				edges.append([corner+first*offset,corner+last*offset])
			_shoulder_edges_closed(city,Rect2i(cell,Vector2i.ONE),edges,"mask=%d sloped=%s"%[mask,sloped])

func test_alternating_bends_join_into_one_closed_diagonal() -> void:
	# A south-west bend above a north-east bend: one straight diagonal whose
	# shoulder edges continue across the shared border without a gap.
	for sloped: bool in [false,true]:
		var city := flat_city()
		if sloped:
			city.terrain_surface = TerrainSurface.new(4)
			city.terrain_surface.set_vertex(21,21,5)
		city.building.put(20,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,NetworkShapes.SOUTH|NetworkShapes.WEST))
		city.building.put(20,21,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,NetworkShapes.NORTH|NetworkShapes.EAST))
		# Each line is one tile's long edge continuing as the other's short edge;
		# the extra entry is the parameter of the shared border crossing.
		_shoulder_edges_closed(city,Rect2i(20,20,1,2),[[Vector2(20,20.1625),Vector2(21,21.1625),.8375],
			[Vector2(20,20.8375),Vector2(21,21.8375),.1625]],"corridor sloped=%s"%sloped)

func test_sloping_authored_lot_has_support_below_its_actual_base() -> void:
	var city := flat_city()
	city.terrain_surface = TerrainSurface.new(4)
	city.terrain_surface.set_vertex(21,20,5)
	city.terrain_surface.set_vertex(21,21,5)
	city.stamp_building(20,20,112)
	var before := var_to_bytes(SaveFormat.encode_city(city))
	var catalog := CityModelCatalog.new()
	check_eq(catalog.load_manifest(CityModelCatalog.ROOT+"catalog.json"),OK)
	var layer := CityBuildings3D.new()
	layer.rebuild(city,catalog)
	var model := layer.get_child(0) as Node3D
	var support := model.get_node_or_null("TerrainSupport") as MeshInstance3D
	check(support!=null,"falling terrain must not leave the rigid model base in midair")
	if support!=null:
		var faces := support.mesh.get_faces()
		var x := -7.65/16.0
		var ray := Vector3(x,-.12,.1)
		check(_hit(faces,ray-Vector3.RIGHT*.02,ray+Vector3.RIGHT*.02),"support reaches down from the actual inset lot edge")
		check(support.get_child_count()>0,"support has matching physical shell")
	check_eq(var_to_bytes(SaveFormat.encode_city(city)),before,"grounding is presentation only")
	layer.free()

func test_ground_contact_support_does_not_bridge_an_authored_opening() -> void:
	var city := flat_city()
	var model := Node3D.new();model.position=Vector3(20.5,4*CityGeometry3D.HEIGHT+.2,20.5)
	for x: float in [-.35,.35]:
		var part := MeshInstance3D.new();var box := BoxMesh.new()
		box.size=Vector3(.2,.02,.9);part.mesh=box;part.position=Vector3(x,.01,0);model.add_child(part)
	preload("res://scripts/view/city_lot_support_3d.gd").add_to(model,city,112,"two-separated-ground-pads")
	var support := model.get_node_or_null("TerrainSupport") as MeshInstance3D
	check(support!=null,"disjoint authored pads receive support")
	if support!=null:
		var faces := support.mesh.get_faces()
		check(not _hit(faces,Vector3(0,.1,0),Vector3(0,-.3,0)),"the open middle stays open")
		check(_hit(faces,Vector3(-.35,.1,0),Vector3(-.35,-.3,0)),"actual left footprint stays solid")
	model.free()

func test_level_lots_and_floating_marine_models_do_not_get_fill() -> void:
	var city := flat_city()
	var catalog := CityModelCatalog.new();check_eq(catalog.load_manifest(CityModelCatalog.ROOT+"catalog.json"),OK)
	for code: int in [112,125,Buildings.PIER,Buildings.MARINA]:
		city.stamp_building(20,20,code)
		var layer := CityBuildings3D.new();layer.rebuild(city,catalog)
		var model := layer.get_child(0) as Node3D
		check(model.get_node_or_null("TerrainSupport")==null,"level or intentionally floating model %d has no fill"%code)
		layer.free()
		city=flat_city()

func test_road_grounding_has_identical_visible_and_physical_sidewalls() -> void:
	var city := flat_city()
	for mask: int in range(1,16):
		city.building.put(20,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,mask))
		var saved := var_to_bytes(SaveFormat.encode_city(city))
		var layer := CityNetworks3D.new();layer._build_region(city,Rect2i(20,20,1,1))
		var walls := 0
		var physical: Dictionary = {}
		for i: int in range(0,layer._physical_obstacles.size(),3):
			physical[Array(layer._physical_obstacles.slice(i,i+3))]=true
		for i: int in range(0,layer._faces.size(),3):
			var a: Vector3=layer._faces[i];var b: Vector3=layer._faces[i+1];var c: Vector3=layer._faces[i+2]
			var normal := (c-a).cross(b-a).normalized()
			if absf(normal.y)>.001: continue
			walls+=1
			check(physical.has([a,b,c]),"visible wall has byte-identical collision triangle mask=%d"%mask)
		check(walls>0,"every road shape has grounded edges")
		check_eq(var_to_bytes(SaveFormat.encode_city(city)),saved,"road grounding preserves city bytes")
		layer.free()

func test_utility_pole_bases_reach_terrain_on_open_ground_and_crossings() -> void:
	var city := flat_city()
	for entry: Array in [[NetworkShapes.shape_id(NetworkShapes.Family.POWER,5),1],[NetworkShapes.CROSS_POWER_EW_ROAD_NS,2]]:
		city.building.put(20,20,entry[0])
		var layer := CityNetworks3D.new();layer._build_region(city,Rect2i(20,20,1,1))
		var poles := 0
		for box: Dictionary in layer._physical_boxes:
			# Poles are the slender posts that carry the wire, whatever its height.
			if not is_equal_approx(box.size.x,CityNetworks3D.POWER_POLE_WIDTH) or box.size.y<.2: continue
			poles+=1
			var bottom: Vector3=box.transform.origin-Vector3.UP*box.size.y*.5
			var ground := CityGeometry3D.point_on_ground(city,Vector2i(20,20),Vector2(bottom.x-20,bottom.z-20))
			check(bottom.y<=ground.y+.00001,"pole extends down to terrain instead of floating on a generic road offset")
		check_eq(poles,entry[1],"pole fixture exercised")
		layer.free()
