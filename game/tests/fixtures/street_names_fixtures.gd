# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name StreetNamesFixtures
extends RefCounted
const Topology := preload("res://scripts/core/naming/street_topology.gd")
const Case := preload("res://tests/test_case.gd")
static func road(city: City, a: Vector2i, b: Vector2i) -> void:
	var result := Builder.new(city, CityStats.new()).apply(Tools.Kind.ROAD, a, b)
	assert(result.ok and result.applied, "Street fixture requires normal paid road placement")
	var direction := Vector2i(signi(b.x-a.x),signi(b.y-a.y))
	for step: int in maxi(absi(b.x-a.x),absi(b.y-a.y))+1:
		assert(NetworkShapes.is_plain_road(city.building.atv(a+direction*step)), "Street fixture drag must reach every requested cell")
static func from_city(city: City) -> Dictionary:
	var topology := Topology.new()
	topology.rebuild(city)
	return {"city": city, "topology": topology, "keys": []}
static func straight() -> Dictionary:
	var city := Case.flat_city()
	road(city, Vector2i(8,8), Vector2i(12,8))
	var f := from_city(city)
	f.keys = ["8,8,open>9,8,open", "9,8,open>10,8,open", "10,8,open>11,8,open", "11,8,open>12,8,open"]
	return f
static func junction() -> Dictionary:
	var city := Case.flat_city()
	road(city, Vector2i(8,6), Vector2i(8,10))
	road(city, Vector2i(6,8), Vector2i(10,8))
	var f := from_city(city)
	f.arms = {"north": ["8,6,open>8,7,open", "8,7,open>8,8,open"], "east": ["8,8,open>9,8,open", "9,8,open>10,8,open"], "south": ["8,8,open>8,9,open", "8,9,open>8,10,open"], "west": ["6,8,open>7,8,open", "7,8,open>8,8,open"]}
	for arm: Array in f.arms.values(): f.keys.append_array(arm)
	return f
## Synthetic layers declare highway carriageways and ramp shape, since normal
## builder drag reshapes neighboring blocks. Ordinary road uses Builder.
static func exit_city(length: int = 3, incoming_only: bool = false) -> Dictionary:
	var city := Case.flat_city()
	for y: int in range(18 if not incoming_only else 20,25):
		city.building.put(20,y,NetworkShapes.HIGHWAY_NS)
		city.building.put(21,y,NetworkShapes.HIGHWAY_NS)
	city.building.put(19,20,95)
	city.flags.put(19,20,RotationMapper.AXIS_FLAG)
	road(city, Vector2i(19,19), Vector2i(19,19-length))
	road(city, Vector2i(17,19-length), Vector2i(21,19-length))
	var f := from_city(city)
	f.road = Vector2i(19,19)
	f.junction = Vector2i(19,19-length)
	f.named = Topology.link_key(f.junction,&"open",f.junction+Vector2i.LEFT,&"open")
	return f

## Paid setup: exactly two physical stations, no train service required.
## second_rail is only a reserved site; collision tests construct it explicitly.
static func station_city() -> Dictionary:
	var city := Case.flat_city()
	var anchors := {"rail":Vector2i(7,6),"subway":Vector2i(10,8),"second_rail":Vector2i(11,6)}
	station(city,anchors.rail,false)
	station(city,anchors.subway,true)
	road(city,Vector2i(9,8),Vector2i(9,11))
	road(city,Vector2i(7,9),Vector2i(13,9))
	var f := from_city(city)
	f.anchors = anchors
	f.street_keys = {"palm":[],"fremont":[]}
	for y: int in range(8,11): f.street_keys.palm.append(Topology.link_key(Vector2i(9,y),&"open",Vector2i(9,y+1),&"open"))
	for x: int in range(7,13): f.street_keys.fremont.append(Topology.link_key(Vector2i(x,9),&"open",Vector2i(x+1,9),&"open"))
	return f

static func station(city: City, anchor: Vector2i, subway: bool) -> void:
	var stats := CityStats.new()
	stats.inventions[&"subways"] = true # Declared technology setup, normal paid Builder transaction.
	var result := Builder.new(city,stats).apply(Tools.Kind.SUBWAY_STATION if subway else Tools.Kind.RAIL_STATION,anchor)
	assert(result.ok and result.applied,"Station fixture requires normal paid placement")
