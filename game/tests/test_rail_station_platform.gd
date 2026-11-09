# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
const Alignment := preload("res://tests/test_station_model_alignment.gd")
const Fixtures := preload("res://tests/test_explore_transit_network.gd")

class SnapshotView extends CityView3D:
	var snapshot_chunks: Array[Dictionary] = []
	var snapshot_networks: Dictionary = {}
	func traversal_snapshot() -> Dictionary:
		return {"chunks":snapshot_chunks,"networks":snapshot_networks,"revision":_geometry_revision,"city":city}

func test_platform_survives_service_start_retirement_and_explore_exit() -> void:
	var city := Fixtures.rail_city()
	var view := SnapshotView.new()
	root.add_child(view)
	view.bind_city(city)
	view._geometry_revision = 1
	var catalog := CityModelCatalog.new()
	check_eq(catalog.load_manifest(CityModelCatalog.ROOT+"catalog.json"),OK)
	view.buildings.rebuild(city,catalog)
	view.networks.rebuild(city)
	view.snapshot_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,24,16))]
	view.snapshot_networks = view.networks.physical_data()
	var traversal := CityTraversalWorld3D.new()
	view.world.add_child(traversal)
	traversal.rebuild(city,view.snapshot_chunks,view.snapshot_networks,1)
	var walker := ExplorePedestrian.new()
	view.world.add_child(walker)
	walker.bind(traversal)
	walker.global_position = Vector3(21,4.0*CityGeometry3D.HEIGHT+.002,22)
	await physics_frame
	await physics_frame
	var floor_point := Vector3(20.5,4.0*CityGeometry3D.HEIGHT+.080,20.74)
	var query := PhysicsRayQueryParameters3D.create(floor_point+Vector3.UP*.01,floor_point-Vector3.UP*.01,CityModelCatalog.SHELL_LAYER)
	var original := view.viewport.find_world_3d().direct_space_state.intersect_ray(query)
	check(not original.is_empty(),"platform is physically present before there is a train service")
	var service := ExploreTransitService.new()
	view.world.add_child(service)
	service.bind(view,traversal,walker)
	check(is_instance_valid(service.train),"fixture starts a real approaching train")
	check(not _has_top(service.world,Transform3D.IDENTITY,Vector3(20.5,0,20.74),floor_point.y),"service adds no duplicate platform mesh over the permanent station")
	var active := view.viewport.find_world_3d().direct_space_state.intersect_ray(query)
	check_eq(active.get("collider"),original.get("collider"),"same platform collider while the train approaches")
	var station := service.network.station_for_route(service.route_data,0)
	walker.transit_support = service
	# Cross the joint between the two track cells at the hall's central door.
	walker.global_position = Vector3(21,4.0*CityGeometry3D.HEIGHT+.025,21.08)
	var from_hall := ExploreInputFrame.idle()
	from_hall.move = Vector2(0,-1)
	for i: int in 180:
		service.step(1.0/60.0,walker)
		walker.step(from_hall,0,1.0/60.0)
		await physics_frame
		if walker.global_position.z<20.79: break
	check(walker.global_position.z<20.79,"player walks from the central entrance across continuous approach steps")
	check(absf(walker.global_position.y-floor_point.y)<.012,"centre entrance reaches the real platform floor")
	for person: Dictionary in service.riders.states():
		if person.in_train: continue
		var feet: Vector3 = person.position
		var underfoot := PhysicsRayQueryParameters3D.create(feet+Vector3.UP*.01,feet-Vector3.UP*.01,CityModelCatalog.SHELL_LAYER)
		check(not view.viewport.find_world_3d().direct_space_state.intersect_ray(underfoot).is_empty(),"waiting passengers stay on the fitted physical platform")
	walker.global_position = station.platform+Vector3.UP*.002
	for i: int in 180:
		service.step(.1,walker)
		if service.state == "boarding": break
	check_eq(service.state,"boarding","train opens beside the permanent platform")
	var move := -Vector3(station.normal)
	var frame := ExploreInputFrame.idle()
	frame.move = Vector2(move.x,move.z)
	var boarded := false
	for i: int in 180:
		service.step(1.0/60.0,walker)
		walker.step(frame,0,1.0/60.0)
		await physics_frame
		if service.train.contains(walker.global_position):
			boarded = true
			break
	check(boarded,"actual walking boards across the permanent platform doorway")
	walker.global_position = station.platform+Vector3.UP*.002
	service._retire()
	await physics_frame
	var retired := view.viewport.find_world_3d().direct_space_state.intersect_ray(query)
	check_eq(retired.get("collider"),original.get("collider"),"retiring service cannot remove the station platform")
	service.clear()
	service.free()
	await physics_frame
	var exited := view.viewport.find_world_3d().direct_space_state.intersect_ray(query)
	check_eq(exited.get("collider"),original.get("collider"),"leaving Explore keeps the same physical platform")
	view.free()
	await physics_frame

func test_platform_exists_without_a_train_on_each_track_side() -> void:
	for side: Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
		var fixture := Alignment.new()
		var city := fixture._city_with_track(side)
		fixture.free()
		var before := SaveFormat.encode_city(city)
		var buildings := CityBuildings3D.new()
		buildings.rebuild(city)
		var model: Node3D = buildings.get_child(0)
		var platform := model.get_node_or_null("RailPlatforms") as Node3D
		check(platform != null,"station has a permanent platform before Explore or train service: "+str(side))
		if platform != null:
			var cell := Vector2i(19 if side.x<0 else 22,20) if side.x!=0 else Vector2i(20,19 if side.y<0 else 22)
			var point := Vector3(cell.x+.5,0,cell.y+.5)-Vector3(side.x,0,side.y)*.24
			check(_has_top(platform,model.transform,point,4.0*CityGeometry3D.HEIGHT+.080),"visible platform floor is beside the rails at carriage floor height")
			var middle := Vector3(21,0,21)+Vector3(side.x,0,side.y)*1.26
			var along := Vector3(-side.y,0,side.x)
			check(_has_top(platform,model.transform,middle,4.0*CityGeometry3D.HEIGHT+.080),"platform is continuous opposite the station entrance")
			for end: float in [-1.0,1.0]:
				check(_has_top(platform,model.transform,middle+along*end*.80,4.0*CityGeometry3D.HEIGHT+.080),"platform reaches the apron ends")
				check(not _has_top(platform,model.transform,middle+along*end*.85,4.0*CityGeometry3D.HEIGHT+.080),"platform stops at the 26.4 metre apron instead of overshooting it")
			check(not platform.find_children("*","CollisionShape3D",true,false).is_empty(),"permanent platform is physical without service")
		check_eq(SaveFormat.encode_city(city),before,"platform projection never edits the city")
		buildings.free()

func test_platform_follows_track_edits_and_disappears_with_track() -> void:
	var fixture := Alignment.new()
	var city := fixture._city_with_track(Vector2i.RIGHT,true)
	fixture.free()
	var buildings := CityBuildings3D.new()
	buildings.rebuild(city)
	for y: int in range(20,23): city.building.put(22,y,0)
	for x: int in range(20,24): city.building.put(x,19,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
	buildings.update_regions(city,null,[Rect2i(22,20,1,3),Rect2i(20,19,4,1)])
	var model: Node3D = buildings.get_child(0)
	var platform := model.get_node_or_null("RailPlatforms") as Node3D
	check(platform != null,"neighboring track edits rebuild the permanent platform")
	if platform != null:
		check(_has_top(platform,model.transform,Vector3(20.5,0,19.74),4.0*CityGeometry3D.HEIGHT+.080),"new platform follows north track")
		check(not _has_top(platform,model.transform,Vector3(22.26,0,20.5),4.0*CityGeometry3D.HEIGHT+.080),"old east platform is gone")
	for x: int in range(20,24): city.building.put(x,19,0)
	buildings.update_regions(city,null,[Rect2i(20,19,4,1)])
	check(buildings.get_child(0).get_node_or_null("RailPlatforms")==null,"no platform across disconnected or removed track")
	buildings.free()

func test_platform_floor_matches_bridge_and_approach_train_height() -> void:
	for east_west: bool in [false,true]:
		for along: int in [24,25]:
			var city := flat_city()
			for i: int in range(18,34):
				var cell := Vector2i(i,20) if east_west else Vector2i(20,i)
				city.building.putv(cell,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10 if east_west else 5))
				if i in [25,26]:
					city.building.putv(cell,90)
					city.flags.putv(cell,RotationMapper.AXIS_FLAG if east_west else 0)
					city.terrain.putv(cell,Terrain.SUBMERGED)
					city.set_heights(cell.x,cell.y,2,3)
			var anchor := Vector2i(along,21) if east_west else Vector2i(21,along)
			city.stamp_building(anchor.x,anchor.y,Buildings.RAIL_STATION,Zones.NONE)
			var graph := CityTrafficGraph.new()
			graph.bind_city(city)
			var network := ExploreTransitNetwork.new()
			network.rebuild(city,graph,1)
			check_eq(network.stations.size(),1,"fixture admits a station beside the bridge or approach")
			var buildings := CityBuildings3D.new()
			buildings.rebuild(city)
			var model: Node3D = buildings.get_child(0)
			var platform := model.get_node_or_null("RailPlatforms") as Node3D
			check(platform != null,"bridge station has a permanent platform")
			if platform != null and not network.stations.is_empty():
				var station: Dictionary = network.stations[0]
				check(_has_top(platform,model.transform,Vector3(station.platform.x,0,station.platform.z),station.platform.y),"platform meets the actual train floor on both bridge axes and approaches")
			buildings.free()

static func _has_top(node: Node3D, parent: Transform3D, point: Vector3, height: float) -> bool:
	var at := parent*node.transform
	if node is MeshInstance3D and node.mesh != null:
		var faces: PackedVector3Array = node.mesh.get_faces()
		for i: int in range(0,faces.size(),3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(point+Vector3.UP*(height+.01),point+Vector3.UP*(height-.01),at*faces[i],at*faces[i+1],at*faces[i+2])
			if hit != null and absf(hit.y-height)<.001: return true
	for child: Node in node.get_children():
		if child is Node3D and _has_top(child,at,point,height): return true
	return false
