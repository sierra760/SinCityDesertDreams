# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
const NetworkFixture := preload("res://tests/test_explore_transit_network.gd")
class SupportOwner extends Node3D:
	var train: ExploreTransitTrain
	func support_for(feet: Vector3) -> Dictionary: return train.support_for(feet)
	func contains(feet: Vector3) -> bool: return train.contains(feet)
var fixture: Node3D
func after_each() -> void:
	if is_instance_valid(fixture): fixture.free()
	await physics_frame
static func grade_city() -> City:
	var city := NetworkFixture.rail_city()
	var terrain := TerrainSurface.new(4)
	for y: int in TerrainSurface.VERTS_Y:
		for x: int in range(26,TerrainSurface.VERTS_X):
			terrain.vertices[TerrainSurface.vertex_index(x,y)] = 5
	city.terrain_surface = terrain
	return city
func _network(city: City) -> ExploreTransitNetwork:
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var network := ExploreTransitNetwork.new()
	network.rebuild(city,graph,1)
	return network
func test_surface_route_matches_actual_grade_and_stop_distances() -> void:
	var city := grade_city()
	var network := _network(city)
	var path := network.route(0,1)
	check(not path.is_empty(),"safe authored one-level grade has a route")
	if path.is_empty(): return
	for i: int in 401:
		var pose := ExploreTransitNetwork.sample(path,float(path.length)*i/400.0)
		var cell := Vector2i(floori(pose.origin.x),floori(pose.origin.z))
		var at := Vector2(pose.origin.x-cell.x,pose.origin.z-cell.y)
		check(absf(pose.origin.y-network.graph.point(cell,&"rail",at).y)<.00002,"route follows exact running surface at "+str(pose.origin))
	for stop: Dictionary in path.stops:
		var station := network.station_for_route(path,stop.station)
		check(ExploreTransitNetwork.sample(path,stop.distance).origin.distance_to(network.nodes[station.node].point)<.00002,"mapped stop remains at physical doorway")
	var actor := ExploreRouteVehicle.new()
	root.add_child(actor)
	path.transit = true
	check(actor.configure(&"train",network,path),"manual train accepts subdivided surface route")
	check(actor.has_support(),"manual route validates graph nodes through point mapping")
	actor.free()
func test_rider_crosses_actual_ascending_and_descending_track_geometry() -> void:
	var city := grade_city()
	var network := _network(city)
	fixture = Fixture.attach(self,city)
	var support := SupportOwner.new(); fixture.add_child(support)
	support.train = ExploreTransitTrain.new(); fixture.add_child(support.train)
	var walker := ExplorePedestrian.new(); fixture.add_child(walker)
	walker.bind(fixture.get_node("traversal"))
	walker.transit_support = support
	var reports: Array[String] = []
	walker.recovery_requested.connect(func(reason): reports.append(reason))
	for reverse: bool in [false,true]:
		var path := network.route(1,0) if reverse else network.route(0,1)
		check(not path.is_empty(),"grade direction has a route")
		if path.is_empty(): continue
		reports.clear()
		walker.clear_support_frame()
		walker.stop_input()
		support.train.global_transform = ExploreTransitNetwork.sample(path,.1)
		walker.global_transform = support.train.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,.027,0))
		await physics_frame
		for i: int in 20:
			walker.step(ExploreInputFrame.idle(),0,1.0/60.0)
			await physics_frame
		var before := support.train.to_local(walker.global_position)
		var worst := 0.0
		for i: int in 500:
			support.train.global_transform = ExploreTransitNetwork.sample(path,.1+(float(path.length)-.2)*float(i+1)/500)
			walker.step(ExploreInputFrame.idle(),0,1.0/60.0)
			await physics_frame
			worst = maxf(worst,(support.train.to_local(walker.global_position)-before).length())
		check_eq(reports.size(),0,"real grade has no unsupported recovery, reverse="+str(reverse))
		check(support.train.contains(walker.global_position),"rider stays inside ascending/descending cabin")
		check(worst<.015,"physical ground cannot push rider through cabin, drift="+str(worst))

func test_surface_bridge_routes_preserve_both_deck_axes() -> void:
	for east_west: bool in [false,true]:
		var city := flat_city()
		for along: int in range(18,34):
			var cell := Vector2i(along,20) if east_west else Vector2i(20,along)
			city.building.putv(cell,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10 if east_west else 5))
			if along in [25,26]:
				city.building.putv(cell,90)
				city.flags.putv(cell,RotationMapper.AXIS_FLAG if east_west else 0)
				city.terrain.putv(cell,Terrain.SUBMERGED)
				city.set_heights(cell.x,cell.y,2,4)
		for along: int in [20,29]:
			var anchor := Vector2i(along,21) if east_west else Vector2i(21,along)
			for y: int in range(anchor.y,anchor.y+2):
				for x: int in range(anchor.x,anchor.x+2): city.building.put(x,y,Buildings.RAIL_STATION)
		var network := _network(city)
		var path := network.route(0,1)
		check(not path.is_empty(),"bridge route remains connected on both axes")
		if path.is_empty(): continue
		var renderer := CityNetworks3D.new()
		renderer.rebuild(city)
		var floors: PackedVector3Array = renderer.physical_data().physical_floor_faces
		for i: int in 101:
			var pose := ExploreTransitNetwork.sample(path,float(path.length)*i/100.0)
			var actual := _floor_height(floors,Vector2(pose.origin.x,pose.origin.z))
			check(is_finite(actual) and absf(pose.origin.y-actual)<.00002,"bridge route follows actual rendered collision facets on both axes")
		renderer.free()
		var actor := ExploreRouteVehicle.new()
		root.add_child(actor)
		path.transit = true
		check(actor.configure(&"train",network,path),"manual curved bridge route accepts full point mapping")
		check(actor.has_support(),"manual bridge edge subdivision validates")
		actor.free()
		await _ride_bridge(city,path)

func _floor_height(faces: PackedVector3Array, at: Vector2) -> float:
	var found := -INF
	for index: int in range(0,faces.size(),3):
		var a := faces[index]; var b := faces[index+1]; var c := faces[index+2]
		var ab := Vector2(b.x-a.x,b.z-a.z); var ac := Vector2(c.x-a.x,c.z-a.z)
		var area := ab.cross(ac)
		if absf(area)<.000000001: continue
		var point := at-Vector2(a.x,a.z)
		var v := point.cross(ac)/area; var w := ab.cross(point)/area
		if v>=-.00001 and w>=-.00001 and v+w<=1.00001:
			found = maxf(found,a.y+v*(b.y-a.y)+w*(c.y-a.y))
	return found

func _ride_bridge(city: City, path: Dictionary) -> void:
	fixture = Fixture.attach(self,city)
	var support := SupportOwner.new(); fixture.add_child(support)
	support.train = ExploreTransitTrain.new(); fixture.add_child(support.train)
	var walker := ExplorePedestrian.new(); fixture.add_child(walker)
	walker.bind(fixture.get_node("traversal"))
	walker.transit_support = support
	var reports: Array[String] = []
	walker.recovery_requested.connect(func(reason): reports.append(reason))
	support.train.global_transform = ExploreTransitNetwork.sample(path,.1)
	walker.global_transform = support.train.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,.027,0))
	await physics_frame
	for i: int in 20:
		walker.step(ExploreInputFrame.idle(),0,1.0/60.0)
		await physics_frame
	var before := support.train.to_local(walker.global_position)
	var worst := 0.0
	for i: int in 400:
		support.train.global_transform = ExploreTransitNetwork.sample(path,.1+(float(path.length)-.2)*float(i+1)/400)
		walker.step(ExploreInputFrame.idle(),0,1.0/60.0)
		await physics_frame
		worst = maxf(worst,(support.train.to_local(walker.global_position)-before).length())
	check_eq(reports.size(),0,"curved bridge carries physical rider without recovery")
	check(support.train.contains(walker.global_position),"rider remains in curved bridge carriage")
	check(worst<.015,"curved physical deck cannot displace rider through cabin")
	fixture.free()
	await physics_frame

func test_route_finds_safe_detour_before_rejecting_unsafe_shortcut() -> void:
	var network := ExploreTransitNetwork.new()
	var positions := [Vector3(0,0,0),Vector3(1,0,0),Vector3(2,2,0),Vector3(3,0,0),Vector3(4,0,0),Vector3(1,0,1),Vector3(2,0,1),Vector3(3,0,1)]
	var links := [[1],[0,2,5],[1,3],[2,4,7],[3],[1,6],[5,7],[6,3]]
	for i: int in positions.size():
		var edges: Array[Vector3i] = []
		for j: int in links[i]: edges.append(Vector3i(j,1,0))
		network.nodes[Vector3i(i,1,0)] = {"point":positions[i],"links":edges}
	var a := {"id":0,"node":Vector3i(0,1,0),"forward":Vector3.RIGHT}
	var b := {"id":1,"node":Vector3i(4,1,0),"forward":Vector3.RIGHT}
	network.stations.assign([a,b])
	var path := network._route_between(a,b)
	check(not path.is_empty(),"unsafe shortest path cannot hide a usable detour")
	if not path.is_empty():
		check(not path.nodes.has(Vector3i(2,1,0)),"unsafe grade is excluded during search")
		check_eq(path.nodes.size(),7,"connected longer flat route is selected")
	network.nodes[Vector3i(1,1,0)].links.erase(Vector3i(5,1,0))
	check(network._route_between(a,b).is_empty(),"no service when only unsafe shortcut remains")
