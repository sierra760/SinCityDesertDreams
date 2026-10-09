# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

const Network := preload("res://scripts/exploration/transit/explore_transit_network.gd")

static func rail_city() -> City:
	var city := flat_city()
	for x: int in range(18,34):
		city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
	for anchor: Vector2i in [Vector2i(20,21),Vector2i(29,21)]:
		for y: int in range(anchor.y,anchor.y+2):
			for x: int in range(anchor.x,anchor.x+2):
				city.building.put(x,y,Buildings.RAIL_STATION)
	return city

static func subway_city() -> City:
	var city := flat_city()
	for x: int in range(18,34): city.underground.put(x,20,NetworkShapes.underground_code(NetworkShapes.Family.SUBWAY,10,0))
	for x: int in [20,29]:
		city.building.put(x,20,Buildings.SUBWAY_STATION)
		city.underground.put(x,20,NetworkShapes.STATION_LINK)
	return city

func _network(city: City) -> ExploreTransitNetwork:
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var network := Network.new()
	network.rebuild(city,graph,1)
	return network

func test_surface_stations_align_with_reciprocal_adjacent_track() -> void:
	var city := rail_city()
	var before := SaveFormat.encode_city(city)
	var network := _network(city)
	check_eq(network.stations.size(),2,"multi-cell station deduplicated")
	var path := network.route(0,1)
	check(not path.is_empty(),"connected station route")
	check_gt(path.length,4)
	check_eq(network.destinations(0).size(),1)
	for station: Dictionary in network.stations:
		check_eq(station.node.y,0)
		check(station.normal.dot(Vector3.FORWARD)!=0,"platform on station-facing side of EW track")
	check_eq(SaveFormat.encode_city(city),before,"graph is read-only")

func test_removed_and_nonreciprocal_track_do_not_advertise_service() -> void:
	var city := rail_city()
	city.building.put(25,20,Buildings.NONE)
	var network := _network(city)
	check(network.route(0,1).is_empty())
	city.building.put(25,20,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,5))
	network = _network(city)
	check(network.route(0,1).is_empty(),"perpendicular track cannot bridge gap")

func test_subway_station_links_and_pipe_crossing_axes() -> void:
	var city := subway_city()
	var network := _network(city)
	check_eq(network.stations.size(),2)
	var path := network.route(0,1)
	check(not path.is_empty())
	for point: Vector3 in path.points: check_lt(point.y,CityGeometry3D.ground_height(city,Vector2i(point.x,point.z))-.3)
	city.underground.put(25,20,NetworkShapes.PIPE_EW_SUBWAY_NS)
	network = _network(city)
	check(network.route(0,1).is_empty(),"pipe direction is not subway direction")

func test_unsupported_station_has_explanation_and_no_route() -> void:
	var city := flat_city()
	city.building.put(20,20,Buildings.SUBWAY_STATION)
	var network := _network(city)
	check(network.stations.is_empty())
	check_eq(network.unavailable.size(),1)
	check(not String(network.unavailable[0].reason).is_empty())
	var reason := String(network.unavailable[0].reason)
	check(reason.begins_with("Trains can't reach this station"),"the reason is plain language: "+reason)
	for jargon: String in ["reciprocal","Adjacent","travel range"]:
		check(not reason.contains(jargon),"no engine jargon: "+jargon)

func test_route_rejects_unsafe_grade_and_perpendicular_platform() -> void:
	var network := _network(rail_city())
	var key := Vector3i(25,0,20)
	network.nodes[key].point.y += 2.0
	check(network.route(0,1).is_empty(),"unsafe imported grade does not advertise a ride")
	network = _network(rail_city())
	network.stations[0].forward = Vector3.FORWARD
	var alternative := network.route(0,1)
	check(not alternative.is_empty(),"another physically valid station orientation remains available")
	if not alternative.is_empty():
		var stop := network.station_for_route(alternative,0)
		check_gt(absf((alternative.points[1]-alternative.points[0]).normalized().dot(stop.forward)),.95,"selected platform doorway follows its actual route")

func test_branches_advertise_only_reachable_stations() -> void:
	var city := rail_city()
	for y: int in range(16,21): city.building.put(25,y,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,5))
	city.building.put(25,20,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,11))
	for y: int in range(16,18):
		for x: int in range(26,28): city.building.put(x,y,Buildings.RAIL_STATION)
	var network := _network(city)
	check_eq(network.stations.size(),3)
	for station: Dictionary in network.stations:
		check_eq(network.destinations(station.id).size(),2,"branch exposes connected choices")

static func mixed_city() -> City:
	var city := flat_city()
	for x: int in range(18,24): city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
	for y: int in range(21,23):
		for x: int in range(20,22): city.building.put(x,y,Buildings.RAIL_STATION)
	# West-facing mouth leads east, down into reciprocal subway track.
	city.building.put(24,20,Buildings.SUBWAY_PORTAL_FIRST+3)
	for x: int in range(25,33): city.underground.put(x,20,NetworkShapes.underground_code(NetworkShapes.Family.SUBWAY,10,0))
	city.building.put(29,20,Buildings.SUBWAY_STATION)
	city.underground.put(29,20,NetworkShapes.STATION_LINK)
	return city

func test_authored_portal_joins_surface_and_subway_without_teleporting() -> void:
	var city := mixed_city()
	var network := _network(city)
	check_eq(network.stations.size(),2)
	var route := network.route(0,1)
	check(not route.is_empty(),"authored portal grade remains rideable")
	if route.is_empty(): return
	check(route.nodes.has(Vector3i(24,2,20)) and route.nodes.has(Vector3i(24,3,20)),"route follows both mouth boundaries")
	for i: int in range(1,route.points.size()): check_lt(route.points[i].distance_to(route.points[i-1]),1.1,"no portal jump")
	city.underground.put(25,20,NetworkShapes.underground_code(NetworkShapes.Family.SUBWAY,5,0))
	network = _network(city)
	check(network.route(0,1).is_empty(),"perpendicular underground mouth rejects service")

func test_portal_connects_reciprocal_branch_with_explicit_chamber() -> void:
	var city := mixed_city()
	city.underground.put(25,20,NetworkShapes.underground_code(NetworkShapes.Family.SUBWAY,11,0))
	city.underground.put(25,19,NetworkShapes.underground_code(NetworkShapes.Family.SUBWAY,5,0))
	var network := _network(city)
	var route := network.route(0,1)
	check(not route.is_empty(),"real converter branch remains connected through an explicit chamber")
	if not route.is_empty():
		for i: int in range(1,route.points.size()):
			var delta: Vector3 = route.points[i]-route.points[i-1]
			check(absf(delta.y)<=Vector2(delta.x,delta.z).length()*tan(deg_to_rad(35.0)),"converter grade remains bounded")
