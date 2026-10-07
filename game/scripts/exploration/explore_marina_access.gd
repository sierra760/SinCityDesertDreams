# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Read-only marina access. Floating lots remain obstacles in the traffic graph;
## launch berths use connected open water immediately outside their footprint.
extends RefCounted

# A marina transfers across its gangway to a nearby bank. Ordinary roadside
# exits keep their small step bound; a cliff is not a marina landing.
const MAX_LANDING_RISE := CityGeometry3D.HEIGHT*2.0

static func exists(city: City, rect: Rect2i) -> bool:
	if city == null or rect.size != Buildings.size(Buildings.MARINA): return false
	for y: int in range(rect.position.y,rect.end.y):
		for x: int in range(rect.position.x,rect.end.x):
			if not city.in_bounds(x,y) or city.building.at(x,y)!=Buildings.MARINA: return false
	return city.anchor_of(rect.position.x,rect.position.y)==rect.position

static func nearby(city: City, position: Vector3) -> Dictionary:
	if city == null or not position.is_finite(): return {}
	var cell := Vector2i(floori(position.x),floori(position.z))
	var point := Vector2(position.x,position.z)
	var seen: Dictionary = {}
	var best: Dictionary = {}
	var distance := .65*.65
	for y: int in range(cell.y-1,cell.y+2):
		for x: int in range(cell.x-1,cell.x+2):
			if not city.in_bounds(x,y) or city.building.at(x,y)!=Buildings.MARINA: continue
			var anchor := city.anchor_of(x,y)
			if seen.has(anchor): continue
			seen[anchor]=true
			var rect := Rect2i(anchor,Buildings.size(Buildings.MARINA))
			var gap := point.distance_squared_to(point.clamp(Vector2(rect.position),Vector2(rect.end)))
			if gap>distance or not exists(city,rect): continue
			distance=gap
			best={"rect":rect}
	return best

static func launch_routes(city: City, graph: CityTrafficGraph, rect: Rect2i, near_position: Vector3) -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	if not exists(city,rect): return routes
	for y: int in range(rect.position.y-1,rect.end.y+1):
		for x: int in range(rect.position.x-1,rect.end.x+1):
			var cell := Vector2i(x,y)
			if rect.has_point(cell) or not graph.has_cell(cell,&"water"): continue
			var joins_marina := false
			for direction: Vector2i in CityTrafficGraph.DIRECTIONS:
				var inside := cell+direction
				if rect.has_point(inside) and city.is_water(inside.x,inside.y) and Terrain.water_kind(city.terrain.atv(inside))!=Terrain.STREAM:
					if absf(CityGeometry3D.water_surface_height(city,inside)-graph.point(cell,&"water").y)<=.09:
						joins_marina=true
			if not joins_marina: continue
			for next: Vector2i in graph.neighbors(cell,&"water"):
				routes.append({"points":[graph.point(cell,&"water"),graph.point(next,&"water")],"cells":[cell,next],"domain":&"water","revision":graph.revision})
	routes.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return a.points[0].distance_squared_to(near_position)<b.points[0].distance_squared_to(near_position))
	return routes

static func landings(city: City, rect: Rect2i) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if not exists(city,rect): return points
	for i: int in rect.size.x:
		for point: Vector2 in [Vector2(rect.position.x+i+.5,rect.position.y-.18),Vector2(rect.position.x+i+.5,rect.end.y+.18),Vector2(rect.position.x-.18,rect.position.y+i+.5),Vector2(rect.end.x+.18,rect.position.y+i+.5)]:
			var cell := Vector2i(floori(point.x),floori(point.y))
			if not city.in_bounds(cell.x,cell.y) or city.is_water(cell.x,cell.y): continue
			points.append(Vector3(point.x,CityGeometry3D.visible_ground_height(city,cell,point-Vector2(cell)),point.y))
	return points
