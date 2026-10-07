# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Coplanar, overlapping visible triangles from different emitters z-fight.
## This scans the prepared Explore transit world and the passenger cabin.
extends "res://tests/exploration/async_test_case.gd"
const Fixtures := preload("res://tests/test_explore_transit_network.gd")
const Stations := preload("res://tests/test_explore_transit_stations.gd")
const PLANE_STEP := .0004 # tile units: 6.4 mm; closer parallel surfaces flicker.
const MIN_AREA := .000002 # tile²: about 5 cm² of genuinely shared surface.

class EnclosedWorld extends ExploreTransitWorld3D:
	func _apply_cutouts(_cuts: Dictionary) -> void: pass

## Every visible triangle as {a,b,c,owner}; `owner` names the emitter.
static func collect(node: Node, parent: Transform3D, out: Array[Dictionary], path := "") -> void:
	var at := parent
	var label := path
	if node is Node3D:
		if not node.visible: return
		at *= node.transform
	if node.name != "" and node.name != node.get_class(): label = path+"/"+String(node.name)
	if node is MeshInstance3D and node.mesh != null:
		for surface: int in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			var key := label+"#"+(material.resource_name if material != null and material.resource_name != "" else "surface%d" % surface)
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			if arrays.is_empty(): continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for i: int in range(0,count,3):
				var ids: Array = [indices[i],indices[i+1],indices[i+2]] if not indices.is_empty() else [i,i+1,i+2]
				out.append({"a":at*vertices[ids[0]],"b":at*vertices[ids[1]],"c":at*vertices[ids[2]],"owner":key})
	for child: Node in node.get_children(): collect(child,at,out,label)

## Pairs of coplanar triangles from different owners that share surface area.
static func overlaps(triangles: Array[Dictionary]) -> Array[Dictionary]:
	var buckets := {}
	for triangle: Dictionary in triangles:
		var a: Vector3 = triangle.a
		var normal: Vector3 = (triangle.b-a).cross(triangle.c-a)
		var area2 := normal.length()
		if area2 < 1e-9: continue
		normal /= area2
		# Only same-facing surfaces fight; an opposite face is culled or hidden
		# behind the solid that owns it.
		var distance := normal.dot(a)
		var key := Vector4i(roundi(normal.x*1000),roundi(normal.y*1000),roundi(normal.z*1000),floori(distance/PLANE_STEP))
		var basis := _plane_basis(normal)
		var flat := PackedVector2Array([Vector2(basis[0].dot(a),basis[1].dot(a)),Vector2(basis[0].dot(triangle.b),basis[1].dot(triangle.b)),Vector2(basis[0].dot(triangle.c),basis[1].dot(triangle.c))])
		if Geometry2D.is_polygon_clockwise(flat): flat.reverse()
		var record := {"owner":triangle.owner,"flat":flat,"distance":distance,"normal":normal,"center":(a+triangle.b+triangle.c)/3.0,"area":area2*.5,"tri":[a,triangle.b,triangle.c]}
		for shift: int in [0,1]:
			var bucket := Vector4i(key.x,key.y,key.z,key.w+shift)
			if not buckets.has(bucket): buckets[bucket] = []
			buckets[bucket].append(record)
	var found := {}
	for bucket: Vector4i in buckets:
		var records: Array = buckets[bucket]
		for i: int in records.size():
			var first: Dictionary = records[i]
			for j: int in range(i+1,records.size()):
				var second: Dictionary = records[j]
				if first.owner == second.owner: continue
				if absf(float(first.distance)-float(second.distance)) > PLANE_STEP: continue
				if Vector3(first.normal).dot(Vector3(second.normal)) < .999: continue
				var shared := 0.0
				for polygon: PackedVector2Array in Geometry2D.intersect_polygons(first.flat,second.flat):
					shared += _area(polygon)
				if shared < MIN_AREA: continue
				var pair := [String(first.owner),String(second.owner)]
				pair.sort()
				var name: String = String(pair[0])+" | "+String(pair[1])
				if not found.has(name): found[name] = {"pair":name,"area":0.0,"count":0,"example":first.center,"gap":absf(float(first.distance)-float(second.distance)),"normal":first.normal,"first":first.tri,"second":second.tri,"other":second.center}
				found[name].area += shared
				found[name].count += 1
	var out: Array[Dictionary] = []
	for key: String in found: out.append(found[key])
	out.sort_custom(func(x, y): return float(x.area) > float(y.area))
	return out

static func _plane_basis(normal: Vector3) -> Array[Vector3]:
	var helper := Vector3.UP if absf(normal.y) < .9 else Vector3.RIGHT
	var u := helper.cross(normal).normalized()
	return [u,normal.cross(u).normalized()]

static func _area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	for i: int in polygon.size():
		var p := polygon[i]
		var q := polygon[(i+1)%polygon.size()]
		total += p.x*q.y-q.x*p.y
	return absf(total)*.5

func _report(label: String, triangles: Array[Dictionary]) -> Array[Dictionary]:
	var pairs := overlaps(triangles)
	print("OVERLAP_SCAN %s triangles=%d coplanar_pairs=%d" % [label,triangles.size(),pairs.size()])
	for pair: Dictionary in pairs:
		print("  %.6f tile² x%d gap=%.5f at %s : %s" % [pair.area,pair.count,pair.gap,str(pair.example),pair.pair])
		print("      normal=%s first=%s second=%s" % [str(pair.normal),str(pair.first),str(pair.second)])
	return pairs

func _station_world(city: City, label: String) -> void:
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var network := ExploreTransitNetwork.new()
	network.rebuild(city,graph,1)
	check_ge(network.stations.size(),2,label+" has two stations")
	if network.stations.size() < 2: return
	var world := EnclosedWorld.new()
	root.add_child(world)
	world.network = network
	world.build(network.route(0,1))
	await physics_frame
	var triangles: Array[Dictionary] = []
	collect(world,Transform3D.IDENTITY,triangles)
	var pairs := _report(label,triangles)
	check_eq(pairs.size(),0,label+" has no coplanar overlapping surfaces")
	world.free()
	await physics_frame

func test_ordinary_subway_station_has_no_coplanar_overlaps() -> void:
	await _station_world(Fixtures.subway_city(),"ordinary subway")

func test_diagonal_access_station_has_no_coplanar_overlaps() -> void:
	var city := Fixtures.flat_city()
	for x: int in range(21,30): city.underground.put(x,21,Underground.subway_code(10))
	for cell: Vector2i in [Vector2i(20,20),Vector2i(29,21)]:
		city.building.putv(cell,Buildings.SUBWAY_STATION)
		city.underground.putv(cell,Underground.STATION_LINK)
	await _station_world(city,"diagonal subway")

func test_graded_terminus_station_has_no_coplanar_overlaps() -> void:
	var city := Stations.terminal_subway_city()
	city.set_heights(21,20,5,0)
	await _station_world(city,"graded terminus subway")

func test_rail_station_platform_has_no_coplanar_overlaps() -> void:
	await _station_world(Fixtures.rail_city(),"rail")

func test_passenger_cabin_has_no_coplanar_overlaps() -> void:
	var train := ExploreTransitTrain.new()
	root.add_child(train)
	await physics_frame
	train.set_doors(1.0,Vector3.RIGHT)
	var triangles: Array[Dictionary] = []
	collect(train,Transform3D.IDENTITY,triangles)
	var pairs := _report("cabin doors open",triangles)
	check_eq(pairs.size(),0,"open cabin has no coplanar overlapping surfaces")
	train.set_doors(0.0,Vector3.RIGHT)
	triangles.clear()
	collect(train,Transform3D.IDENTITY,triangles)
	pairs = _report("cabin doors closed",triangles)
	check_eq(pairs.size(),0,"closed cabin has no coplanar overlapping surfaces")
	train.free()
	await physics_frame
