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
const CANDIDATE_STEP := .01 # tile units: only groups candidates; PLANE_STEP decides.

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
## Separation is measured inside the shared region from one triangle's own plane,
## so moving the whole scene never changes the result.
static func overlaps(triangles: Array[Dictionary]) -> Array[Dictionary]:
	var origin := Vector3.ZERO
	for triangle: Dictionary in triangles: origin += triangle.a
	if not triangles.is_empty(): origin /= triangles.size()
	var records: Array[Dictionary] = []
	var buckets := {}
	for triangle: Dictionary in triangles:
		var a: Vector3 = triangle.a
		var normal: Vector3 = (triangle.b-a).cross(triangle.c-a)
		var area2 := normal.length()
		if area2 < 1e-9: continue
		normal /= area2
		# Only same-facing surfaces fight; an opposite face is culled or hidden
		# behind the solid that owns it. Buckets only gather candidates, and
		# use the scene's own centre so a far-off scene keeps its neighbours.
		var key := Vector4i(roundi(normal.x*1000),roundi(normal.y*1000),roundi(normal.z*1000),floori(normal.dot(a-origin)/CANDIDATE_STEP))
		var basis := _plane_basis(normal)
		var record := {"index":records.size(),"owner":triangle.owner,"a":a,"normal":normal,"basis":basis,"center":(a+triangle.b+triangle.c)/3.0,"tri":[a,triangle.b,triangle.c]}
		records.append(record)
		for shift: int in [0,1]:
			var bucket := Vector4i(key.x,key.y,key.z,key.w+shift)
			if not buckets.has(bucket): buckets[bucket] = []
			buckets[bucket].append(record)
	var seen := {}
	var found := {}
	for bucket: Vector4i in buckets:
		var group: Array = buckets[bucket]
		for i: int in group.size():
			var first: Dictionary = group[i]
			for j: int in range(i+1,group.size()):
				var second: Dictionary = group[j]
				if first.owner == second.owner: continue
				var normal: Vector3 = first.normal
				if normal.dot(second.normal) < .999: continue
				var id := Vector2i(mini(first.index,second.index),maxi(first.index,second.index))
				if seen.has(id): continue
				seen[id] = true
				var near := _near_region(first,second)
				var shared := _area(near)
				if shared < MIN_AREA: continue
				var u: Vector3 = first.basis[0]
				var w: Vector3 = first.basis[1]
				var middle := Vector2.ZERO
				for point: Vector2 in near: middle += point
				middle /= near.size()
				var pair := [String(first.owner),String(second.owner)]
				pair.sort()
				var name: String = String(pair[0])+" | "+String(pair[1])
				if not found.has(name): found[name] = {"pair":name,"area":0.0,"count":0,"example":Vector3(first.a)+u*middle.x+w*middle.y,"gap":absf(_height(first,second,middle)),"normal":normal,"first":first.tri,"second":second.tri,"other":second.center}
				found[name].area += shared
				found[name].count += 1
	var out: Array[Dictionary] = []
	for key: String in found: out.append(found[key])
	out.sort_custom(func(x, y): return float(x.area) > float(y.area))
	return out

## Height of `second`'s plane above `first`'s at `point` in `first`'s plane.
static func _height(first: Dictionary, second: Dictionary, point: Vector2) -> float:
	var n1: Vector3 = first.normal
	var n2: Vector3 = second.normal
	var on_first: Vector3 = Vector3(first.a)+Vector3(first.basis[0])*point.x+Vector3(first.basis[1])*point.y
	return n2.dot(Vector3(second.a)-on_first)/n2.dot(n1)

## The part of both triangles, seen along `first`'s normal, where the planes
## lie within PLANE_STEP of each other; empty when they never come that close.
static func _near_region(first: Dictionary, second: Dictionary) -> PackedVector2Array:
	var a: Vector3 = first.a
	var n1: Vector3 = first.normal
	var low := INF
	var high := -INF
	for v: Vector3 in second.tri:
		var lift := n1.dot(v-a)
		low = minf(low,lift)
		high = maxf(high,lift)
	if low > PLANE_STEP or high < -PLANE_STEP: return PackedVector2Array()
	var u: Vector3 = first.basis[0]
	var w: Vector3 = first.basis[1]
	var one := PackedVector2Array()
	for v: Vector3 in first.tri: one.append(Vector2(u.dot(v-a),w.dot(v-a)))
	var two := PackedVector2Array()
	for v: Vector3 in second.tri: two.append(Vector2(u.dot(v-a),w.dot(v-a)))
	if Geometry2D.is_polygon_clockwise(one): one.reverse()
	if Geometry2D.is_polygon_clockwise(two): two.reverse()
	var shared := Geometry2D.intersect_polygons(one,two)
	if shared.is_empty(): return PackedVector2Array()
	# Two triangles meet in one convex polygon. Height is linear across it.
	var base := _height(first,second,Vector2.ZERO)
	var slope := Vector2(_height(first,second,Vector2.RIGHT)-base,_height(first,second,Vector2.UP)-base)
	var region: PackedVector2Array = shared[0]
	region = _clip(region,slope,PLANE_STEP-base)
	return _clip(region,-slope,PLANE_STEP+base)

## Keeps the part of a convex polygon where slope·p <= limit.
static func _clip(polygon: PackedVector2Array, slope: Vector2, limit: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in polygon.size():
		var p := polygon[i]
		var q := polygon[(i+1)%polygon.size()]
		var fp := slope.dot(p)-limit
		var fq := slope.dot(q)-limit
		if fp <= 0.0: out.append(p)
		if (fp < 0.0 and fq > 0.0) or (fp > 0.0 and fq < 0.0): out.append(p+(q-p)*(fp/(fp-fq)))
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

static func _quad(owner: String, corner: Vector3, along: Vector3, up: Vector3) -> Array[Dictionary]:
	return [{"a":corner,"b":corner+along,"c":corner+along+up,"owner":owner},{"a":corner,"b":corner+along+up,"c":corner+up,"owner":owner}]

static func _moved(triangles: Array[Dictionary], by: Transform3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for triangle: Dictionary in triangles: out.append({"a":by*Vector3(triangle.a),"b":by*Vector3(triangle.b),"c":by*Vector3(triangle.c),"owner":triangle.owner})
	return out

## Same pairs with the same shared areas, allowing float rounding of moved vertices.
func _same_scan(found: Array[Dictionary], expected: Array[Dictionary], label: String) -> void:
	check_eq(found.size(),expected.size(),label+": pair count")
	if found.size() != expected.size(): return
	for i: int in found.size():
		check_eq(found[i].pair,expected[i].pair,label)
		check(absf(float(found[i].area)-float(expected[i].area)) <= float(expected[i].area)*.01,label+": "+str(found[i].area)+" vs "+str(expected[i].area))

func test_scanner_finds_coplanar_faces_and_ignores_separated_ones() -> void:
	var far := Transform3D(Basis.IDENTITY,Vector3(41.2,3.5,-27.9))
	var together: Array[Dictionary] = _quad("wall",Vector3.ZERO,Vector3(.1,0,0),Vector3(0,.1,0))
	together.append_array(_quad("trim",Vector3(.02,.02,.0001),Vector3(.05,0,0),Vector3(0,.05,0)))
	var apart: Array[Dictionary] = _quad("wall",Vector3.ZERO,Vector3(.1,0,0),Vector3(0,.1,0))
	apart.append_array(_quad("trim",Vector3(.02,.02,.0006),Vector3(.05,0,0),Vector3(0,.05,0)))
	for by: Transform3D in [Transform3D.IDENTITY,far]:
		var found := overlaps(_moved(together,by))
		check_eq(found.size(),1,"a trim lying on a wall is found")
		if found.size() == 1: check(absf(float(found[0].area)-.0025) < 1e-6,"the whole trim area is shared: "+str(found[0].area))
		check_eq(overlaps(_moved(apart,by)).size(),0,"9.6 mm apart is not coplanar")
	# A long trim leaning slightly crosses its wall; only the strip of the crossing
	# within PLANE_STEP of the wall counts (8 of its 10 tiles here).
	var lean := .0001
	var leaning: Array[Dictionary] = _quad("wall",Vector3.ZERO,Vector3(10,0,0),Vector3(0,.1,0))
	leaning.append_array(_quad("trim",Vector3(0,0,-.0005),Vector3(10,0,10*lean),Vector3(0,.1,0)))
	var strip := overlaps(leaning)
	check_eq(strip.size(),1,"a shallow crossing still fights near the crossing")
	if strip.size() == 1: check(absf(float(strip[0].area)-.8) < .001,"only the near strip counts: "+str(strip[0].area))

func test_scanner_ignores_where_the_scene_is() -> void:
	var train := ExploreTransitTrain.new()
	root.add_child(train)
	await physics_frame
	var triangles: Array[Dictionary] = []
	collect(train,Transform3D.IDENTITY,triangles)
	# A planted trim keeps the comparison meaningful once the cabin itself is clean.
	triangles.append_array(_quad("planted wall",Vector3(0,.3,0),Vector3(.1,0,0),Vector3(0,.1,0)))
	triangles.append_array(_quad("planted trim",Vector3(.02,.32,.0001),Vector3(.05,0,0),Vector3(0,.05,0)))
	var here := overlaps(triangles)
	check(not here.is_empty(),"the planted trim is found in place")
	_same_scan(overlaps(_moved(triangles,Transform3D(Basis.IDENTITY,Vector3(29.4,2.5,21.1)))),here,"a moved cabin scans the same")
	_same_scan(overlaps(_moved(triangles,Transform3D(Basis.IDENTITY,Vector3(-12.3,.7,40.6)))),here,"a cabin moved the other way scans the same")
	train.free()
	await physics_frame
