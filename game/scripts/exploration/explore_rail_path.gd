# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The drawn surface railway, including diagonal pieces and terrain facets.
## Padded endpoints support the axles without extending the driving range.
extends RefCounted

static func surface(graph: CityTrafficGraph, route: Dictionary, source: Array) -> Dictionary:
	var cells: Array[Vector2i] = []
	for value: Variant in route.get("cells",[]): cells.append(Vector2i(value))
	if cells.is_empty():
		for point: Vector3 in source:
			var cell := Vector2i(floori(point.x),floori(point.z))
			if cells.is_empty() or cell!=cells[-1]: cells.append(cell)
	if cells.size()<2: return {}
	for i: int in cells.size():
		if not graph.has_cell(cells[i],&"rail"): return {}
		if i>0 and not graph.neighbors(cells[i-1],&"rail").has(cells[i]): return {}
	var first_cell := cells[0]
	var last_cell := cells[-1]
	var before := _other_arm(_mask(graph,first_cell),cells[1]-first_cell)
	var after := _other_arm(_mask(graph,last_cell),cells[-2]-last_cell)
	if graph.neighbors(first_cell,&"rail").has(first_cell+before) and not cells.has(first_cell+before):
		cells.push_front(first_cell+before)
	if graph.neighbors(last_cell,&"rail").has(last_cell+after) and not cells.has(last_cell+after):
		cells.append(last_cell+after)
	var points := PackedVector3Array()
	var first_span := Vector2i()
	var last_span := Vector2i()
	for i: int in cells.size():
		var cell := cells[i]
		var mask := _mask(graph,cell)
		var incoming: Vector2i = cells[i-1]-cell if i>0 else _other_arm(mask,cells[i+1]-cell)
		var outgoing: Vector2i = cells[i+1]-cell if i<cells.size()-1 else _other_arm(mask,incoming)
		var entry := Vector2(.5,.5)+Vector2(incoming)*.5
		var exit := Vector2(.5,.5)+Vector2(outgoing)*.5
		var middle := entry.lerp(exit,.5) if mask in [3,6,9,12] else Vector2(.5,.5)
		var anchors: Array[Vector2] = [entry,middle,exit]
		var start := maxi(0,points.size()-1)
		var segments := 8 if NetworkShapes.is_rail_bridge(graph.city.building.atv(cell)) else 1
		var approach := graph.bridge_approach(cell)
		if not approach.is_empty():
			var divisions: Vector2i = CityNetworks3D.BridgeApproaches.subdivisions(approach)
			segments = maxi(segments,maxi(divisions.x,divisions.y)/2)
		for half: int in 2:
			for part: int in segments+1:
				var at := anchors[half].lerp(anchors[half+1],float(part)/segments)
				var point := graph.point(cell,&"rail",at)
				if points.is_empty() or points[-1].distance_to(point)>.000001: points.append(point)
		if cell==first_cell: first_span = Vector2i(start,points.size()-1)
		if cell==last_cell: last_span = Vector2i(start,points.size()-1)
	var lengths := distances(points)
	var low := nearest_distance(points,lengths,source[0],first_span)
	var high := nearest_distance(points,lengths,source[-1],last_span)
	if high-low<.01: return {}
	var path := prepare(points)
	path.offset = low
	path.length = high-low
	var movement: Array[Vector3] = [sample(path,low).origin]
	for i: int in points.size():
		if lengths[i]>low+.000001 and lengths[i]<high-.000001: movement.append(points[i])
	movement.append(sample(path,high).origin)
	path.movement = movement
	return path

static func _mask(graph: CityTrafficGraph, cell: Vector2i) -> int:
	var code := graph.city.building.atv(cell)
	if NetworkShapes.is_rail_bridge(code): return 10 if graph.city.flags.atv(cell)&RotationMapper.AXIS_FLAG else 5
	return CityNetworks3D.network_mask(code,NetworkShapes.Family.RAIL)

static func _other_arm(mask: int, toward: Vector2i) -> Vector2i:
	var opposite := -toward
	var index := NetworkShapes.DIRECTIONS.find(opposite)
	if index>=0 and mask&(1<<index): return opposite
	for i: int in 4:
		if mask&(1<<i) and NetworkShapes.DIRECTIONS[i]!=toward: return NetworkShapes.DIRECTIONS[i]
	return opposite

static func distances(points: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	for i: int in range(1,points.size()): out.append(out[-1]+points[i-1].distance_to(points[i]))
	return out

static func nearest_distance(points: PackedVector3Array, lengths: PackedFloat32Array, position: Vector3, span: Vector2i) -> float:
	var best := INF
	var found := 0.0
	for i: int in range(span.x+1,span.y+1):
		var delta := points[i]-points[i-1]
		var t := clampf((position-points[i-1]).dot(delta)/maxf(delta.length_squared(),.000000001),0,1)
		var gap := position.distance_squared_to(points[i-1]+delta*t)
		if gap<best:
			best = gap
			found = lerpf(lengths[i-1],lengths[i],t)
	return found

## Axles may extend just beyond a route endpoint on its straight station track.
static func sample(path: Dictionary, distance: float) -> Transform3D:
	var points: PackedVector3Array = path.points
	var lengths: PackedFloat32Array = path.distances
	var index := segment(path,distance)
	var delta := points[index+1]-points[index]
	var t := (distance-lengths[index])/maxf(.000001,lengths[index+1]-lengths[index])
	return Transform3D(Basis.looking_at(delta.normalized(),Vector3.UP),points[index]+delta*t)

static func segment(path: Dictionary, distance: float) -> int:
	var lengths: PackedFloat32Array = path.distances
	var low := 0
	var high := lengths.size()-2
	while low<high:
		var middle := (low+high)/2
		if lengths[middle+1]<distance: low = middle+1
		else: high = middle
	return low

## Intersect adjacent offset lines, matching the renderer's joined steel rails.
static func prepare(points: PackedVector3Array) -> Dictionary:
	var normals := PackedVector3Array()
	for i: int in points.size():
		var before := points[i]-points[maxi(0,i-1)] if i>0 else points[1]-points[0]
		var after := points[mini(i+1,points.size()-1)]-points[i] if i<points.size()-1 else before
		var a := Vector3(-before.z,0,before.x).normalized()
		var b := Vector3(-after.z,0,after.x).normalized()
		normals.append((a+b)/maxf(.01,1.0+a.dot(b)))
	return {"points":points,"distances":distances(points),"normals":normals,"offset":0.0}

static func offset_point(path: Dictionary, distance: float, side: float) -> Vector3:
	var index := segment(path,distance)
	var lengths: PackedFloat32Array = path.distances
	var points: PackedVector3Array = path.points
	var normals: PackedVector3Array = path.normals
	var t := (distance-lengths[index])/maxf(.000001,lengths[index+1]-lengths[index])
	return points[index].lerp(points[index+1],t)+normals[index].lerp(normals[index+1],t)*side
