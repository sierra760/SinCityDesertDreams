# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
## Read-only, entry-time layout for the Mayor's House. Coordinates are shared
## with the model builder, in metres; the lot transform supplies ground and yaw.
class_name ExploreMayorsHouse
extends RefCounted

const PATH := "res://assets/desert-dreams-3d/mayors-house.json"
static var _layout: Dictionary = {}

static func layout() -> Dictionary:
	if _layout.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _layout = parsed
	return _layout

static func map_center() -> Vector3:
	return Vector3(City.WIDTH*.5,0,City.HEIGHT*.5)

## A deterministic single fleet, including imported cities with duplicate lots.
static func find(city: City) -> Dictionary:
	if city == null: return {}
	var best: Dictionary = {}
	var distance := INF
	var seen: Dictionary = {}
	# Native packed-array search avoids a GDScript loop over every map cell
	# in the overwhelmingly common no-house case. No new city-side cache.
	var next := city.building.data.find(Buildings.MAYORS_RESIDENCE)
	while next >= 0:
		var i := next
		next = city.building.data.find(Buildings.MAYORS_RESIDENCE,i+1)
		var x := i%City.WIDTH
		var y := i/City.WIDTH
		var anchor := City.footprint_anchor(city.building.data,city.zone.data,x,y)
		if seen.has(anchor): continue
		seen[anchor] = true
		var rect := Rect2i(anchor,Buildings.size(Buildings.MAYORS_RESIDENCE))
		if not Rect2i(0,0,City.WIDTH,City.HEIGHT).encloses(rect): continue
		var center := Vector3(rect.position.x+rect.size.x*.5,CityBuildings3D.base_height(city,rect,Buildings.MAYORS_RESIDENCE),rect.position.y+rect.size.y*.5)
		var d := Vector2(center.x-map_center().x,center.z-map_center().z).length_squared()
		if d >= distance: continue
		distance = d
		var yaw := CityBuildings3D.resort_yaw(city,rect)
		var facing := Vector2i(roundi(sin(yaw)),roundi(cos(yaw)))
		var road_access := CityBuildings3D._street_frontage(city,rect,facing) > 0
		best = {"road_access":road_access,"anchor":anchor,"footprint":rect,"yaw":yaw,"transform":Transform3D(Basis(Vector3.UP,yaw),center),"city":city}
	return best

static func pose(house: Dictionary, position_m: Array, yaw: float = 0.0) -> Transform3D:
	var local := Vector3(float(position_m[0]),float(layout().ground_m),float(position_m[1]))/16.0
	return (house.transform as Transform3D)*Transform3D(Basis(Vector3.UP,yaw),local)

## A tiny bounded off-road exception. Physical support and collisions still
## apply. No graph mutation, new routes, terrain-wide permission or city scan.
static func allows(house: Dictionary, body: Transform3D, size: Vector3) -> bool:
	if house.is_empty(): return false
	var city: City = house.city
	var anchor: Vector2i = house.anchor
	if city.building.atv(anchor) != Buildings.MAYORS_RESIDENCE: return false
	var local: Transform3D = (house.transform as Transform3D).affine_inverse()*body
	if absf(local.origin.y-float(layout().ground_m)/16.0) > .045: return false
	var a: Array = layout().apron
	var apron := Rect2(Vector2(float(a[0]),float(a[1]))/16.0,Vector2(float(a[2]),float(a[3]))/16.0)
	for x: float in [-size.x*.5,size.x*.5]:
		for z: float in [-size.z*.5,size.z*.5]:
			var corner := local*Vector3(x,0,z)
			if not apron.has_point(Vector2(corner.x,corner.z)):
				# Across the open front, only actual adjoining ground-level road
				# is allowed; the rest of the lot's perimeter stays bounded.
				if corner.z < 1.0: return false
				var world_corner: Vector3 = (house.transform as Transform3D)*corner
				var cell := Vector2i(floori(world_corner.x),floori(world_corner.z))
				if not city.in_bounds(cell.x,cell.y): return false
				var code := city.building.atv(cell)
				if not NetworkShapes.in_road_family(code) or NetworkShapes.is_tunnel(code) or NetworkShapes.is_road_bridge(code): return false
	return true
