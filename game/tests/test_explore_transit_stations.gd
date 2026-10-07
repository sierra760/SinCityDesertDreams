# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"
const Fixtures := preload("res://tests/test_explore_transit_network.gd")

class SnapshotView extends CityView3D:
	var snapshot_chunks: Array[Dictionary] = []
	var snapshot_networks: Dictionary = {}
	func traversal_snapshot() -> Dictionary:
		return {"chunks":snapshot_chunks,"networks":snapshot_networks,"revision":_geometry_revision,"city":city}

var view: SnapshotView
var traversal: CityTraversalWorld3D
var walker: ExplorePedestrian
var service: ExploreTransitService

func after_each() -> void:
	if is_instance_valid(service): service.clear()
	if is_instance_valid(view): view.free()
	view = null
	service = null
	walker = null
	traversal = null
	await physics_frame

static func terminal_subway_city() -> City:
	var city := Fixtures.flat_city()
	for x: int in range(20,30): city.underground.put(x,20,Underground.subway_code(10))
	for x: int in [20,29]:
		city.building.put(x,20,Buildings.SUBWAY_STATION)
		city.underground.put(x,20,Underground.STATION_LINK)
	return city

func _network(city: City) -> ExploreTransitNetwork:
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var network := ExploreTransitNetwork.new()
	network.rebuild(city,graph,1)
	return network

func test_rail_station_admits_reciprocal_track_terminus() -> void:
	var city := Fixtures.flat_city()
	for x: int in range(21,32): city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
	city.stamp_building(20,21,Buildings.RAIL_STATION)
	city.stamp_building(29,21,Buildings.RAIL_STATION)
	var before := SaveFormat.encode_city(city)
	var network := _network(city)
	check_eq(network.stations.size(),2,"one-sided rail terminus serves its adjacent lot")
	if network.stations.size()!=2: return
	check_eq(network.stations[0].node,Vector3i(21,0,20))
	check(not network.route(0,1).is_empty(),"terminus has a real passenger route")
	check_eq(SaveFormat.encode_city(city),before,"station admission never rewrites tracks")
	city.building.put(22,20,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,5))
	network = _network(city)
	check_eq(network.stations.size(),1,"nonreciprocal perpendicular neighbor cannot fake a terminus connection")

func test_subway_station_admits_spur_and_endpoint_without_through_track() -> void:
	var city := terminal_subway_city()
	var before := SaveFormat.encode_city(city)
	var network := _network(city)
	check_eq(network.stations.size(),2,"both station-link termini are usable")
	if network.stations.size()!=2: return
	var path := network.route(0,1)
	check(not path.is_empty(),"station link connects to its existing single tunnel arm")
	check_eq(path.stops.size(),2)
	check_eq(network.destinations(0).size(),1)
	check_eq(network.destinations(1).size(),1)
	check_eq(SaveFormat.encode_city(city),before,"subway route leaves source grids intact")

func test_terminal_subway_has_physical_stairs_and_open_door_boarding() -> void:
	var city := terminal_subway_city()
	var preview := _network(city)
	check_eq(preview.stations.size(),2)
	if preview.stations.size()!=2: return
	view = SnapshotView.new()
	root.add_child(view)
	view.bind_city(city)
	view._geometry_revision = 1
	view.networks.rebuild(city)
	view.snapshot_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,20,16))]
	view.snapshot_networks = view.networks.physical_data()
	traversal = CityTraversalWorld3D.new()
	view.world.add_child(traversal)
	traversal.rebuild(city,view.snapshot_chunks,view.snapshot_networks,1)
	walker = ExplorePedestrian.new()
	view.world.add_child(walker)
	walker.bind(traversal)
	service = ExploreTransitService.new()
	view.world.add_child(service)
	service.bind(view,traversal,walker)
	var station: Dictionary = service.network.stations[0]
	walker.global_position = Vector3(station.anchor.x+.5,station.surface+.002,station.anchor.y+.5)
	service.step(.016,walker)
	await physics_frame
	await physics_frame
	check(is_instance_valid(service.train),"nearby terminus starts a real service")
	if not is_instance_valid(service.train): return
	walker.transit_support = service
	station = service.network.station_for_route(service.route_data,0)
	var points := service.world.access_waypoints(station)
	walker.global_position = points[0]
	var recoveries: Array = []
	walker.recovery_requested.connect(func(reason): recoveries.append(reason))
	await _walk_waypoints(points,"terminal enclosed stairs")
	check_lt(absf(walker.global_position.y-station.platform.y),.012,"actual capsule descends to platform height")
	check(recoveries.is_empty(),"stairs maintain physical support at terminus")
	walker.global_position = station.platform+Vector3.UP*.002
	walker.velocity = Vector3.ZERO
	for i: int in 1200:
		service.step(.1,walker)
		if service.state=="boarding" and service._station_id==int(station.id): break
	check(service.state=="boarding" and service._station_id==int(station.id),"carriage reaches this terminal platform and opens")
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
	if not boarded:
		print("BOARD_DIAGNOSTIC feet=",walker.global_position," station=",station.platform," train=",service.train.global_transform," state=",service.state," doors=",service.train.door_fraction," local=",service.train.global_transform.affine_inverse()*walker.global_position)
		var contact := KinematicCollision3D.new()
		if walker.test_move(walker.global_transform,move*.05,contact):
			for index in contact.get_collision_count(): print("BOARD_CONTACT ",contact.get_collider(index).get_path()," POS ",contact.get_position(index)," NORMAL ",contact.get_normal(index))
	check(boarded,"walking through open terminal doorway boards carriage")

func _setup_access(city: City, expected_stations := 2) -> bool:
	var network := _network(city)
	check_eq(network.stations.size(),expected_stations,"fixture has real station stops")
	if network.stations.size()!=expected_stations: return false
	view = SnapshotView.new()
	root.add_child(view)
	view.bind_city(city)
	view._geometry_revision = 1
	view.networks.rebuild(city)
	view.snapshot_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,20,16))]
	view.snapshot_networks = view.networks.physical_data()
	traversal = CityTraversalWorld3D.new()
	view.world.add_child(traversal)
	traversal.rebuild(city,view.snapshot_chunks,view.snapshot_networks,1)
	walker = ExplorePedestrian.new()
	view.world.add_child(walker)
	walker.bind(traversal)
	service = ExploreTransitService.new()
	view.world.add_child(service)
	service.bind(view,traversal,walker)
	var station: Dictionary = service.network.stations[0]
	walker.global_position = Vector3(station.anchor.x+.5,station.surface+.002,station.anchor.y+.5)
	service.step(.016,walker)
	await physics_frame
	await physics_frame
	walker.transit_support = service
	check(not service.route_data.is_empty(),"fixture prepares connected passenger service")
	return not service.route_data.is_empty()

func _walk_waypoints(points: PackedVector3Array, label: String, camera: CityExploreCamera3D = null) -> void:
	for destination: Vector3 in points:
		var vertical := destination.y-walker.global_position.y
		if absf(vertical)>.10 and Vector2(destination.x-walker.global_position.x,destination.z-walker.global_position.z).length()<.012 and service.world.in_elevator(walker.global_position):
			check(service.interact_elevator(),label+": passenger requests elevator floor")
		for i: int in 1200:
			var delta := Vector2(destination.x-walker.global_position.x,destination.z-walker.global_position.z)
			if delta.length()<.008 and absf(destination.y-walker.global_position.y)<.012 or walker._reported: break
			if service.world.elevator_prompt(walker.global_position)=="F to call elevator": service.interact_elevator()
			service.step(1.0/60.0,walker)
			var frame := ExploreInputFrame.idle()
			frame.move = delta.normalized()*clampf(delta.length()/.03,0,1.0) if delta.length()>.008 else Vector2.ZERO
			walker.step(frame,0,1.0/60.0)
			if camera!=null:
				camera.set_interior(service.world.indoors(walker.global_position))
				camera.yaw=atan2(-delta.x,-delta.y)
				camera.update_follow(1.0/60.0)
				check(camera._point_clear(camera.camera.global_position),label+": camera remains inside clear space")
			await physics_frame
		var end := walker.global_position
		if Vector2(destination.x-end.x,destination.z-end.z).length()>=.025 or absf(end.y-destination.y)>=.04:
			print("ACCESS_DIAGNOSTIC ",label," target=",destination," actual=",end," prompt=",service.world.elevator_prompt(end))
			for lift: Node3D in service.world.elevators: print("LIFT_DIAGNOSTIC floor=",lift.floor," state=",lift.state," local=",lift.global_transform.affine_inverse()*end," cabin=",lift.cabin.position)
		check_lt(Vector2(destination.x-end.x,destination.z-end.z).length(),.025,label+": reaches horizontal waypoint "+str(destination)+" from "+str(end))
		check_lt(absf(end.y-destination.y),.04,label+": reaches waypoint floor height")
		if walker._reported:
			check(false,label+": support requested recovery at "+str(end))
			return

func test_deep_station_switchback_walks_down_and_back_without_recovery() -> void:
	var city := terminal_subway_city()
	city.terrain_surface = TerrainSurface.new(6)
	for y: int in TerrainSurface.VERTS_Y:
		for x: int in range(24,TerrainSurface.VERTS_X): city.terrain_surface.vertices[y*TerrainSurface.VERTS_X+x] = 4
	for x: int in [22,23]:
		city.underground.put(x,20,Underground.subway_code(15))
		city.underground.put(x,19,Underground.subway_code(5))
	if not await _setup_access(city): return
	var station := service.network.station_for_route(service.route_data,0)
	check_gt(station.surface-station.position.y-.025,1.2,"fixture requires a real second stair flight")
	var points := service.world.access_waypoints(station)
	check_gt(points.size(),5)
	walker.global_position = points[0]
	var recoveries: Array = []
	walker.recovery_requested.connect(func(reason): recoveries.append(reason))
	await _walk_waypoints(points,"deep descent")
	points.reverse()
	await _walk_waypoints(points,"deep ascent")
	check(recoveries.is_empty(),"switchback surface-to-platform-to-surface stays supported")

func test_camera_follows_enclosed_flights_and_turns_without_recovery() -> void:
	var city := terminal_subway_city()
	city.terrain_surface = TerrainSurface.new(6)
	for y: int in TerrainSurface.VERTS_Y:
		for x: int in range(24,TerrainSurface.VERTS_X): city.terrain_surface.vertices[y*TerrainSurface.VERTS_X+x]=4
	for x: int in [22,23]:
		city.underground.put(x,20,Underground.subway_code(15))
		city.underground.put(x,19,Underground.subway_code(5))
	if not await _setup_access(city): return
	var station := service.network.station_for_route(service.route_data,0)
	var points := service.world.access_waypoints(station)
	walker.global_position=points[0]
	var camera := CityExploreCamera3D.new()
	view.world.add_child(camera)
	camera.configure_target(walker,0)
	var recoveries: Array = []
	camera.recovery_requested.connect(func(): recoveries.append("camera"))
	walker.recovery_requested.connect(func(reason): recoveries.append(reason))
	await _walk_waypoints(points,"enclosed camera descent",camera)
	points.reverse()
	await _walk_waypoints(points,"enclosed camera ascent",camera)
	check(recoveries.is_empty(),"camera and passenger clear every enclosed flight and landing")
	check(not camera._withheld,"supported stairwell walking retains the Explore camera")

func test_diagonal_station_walks_existing_track_access_without_inventing_rail() -> void:
	var city := Fixtures.flat_city()
	for x: int in range(21,30): city.underground.put(x,21,Underground.subway_code(10))
	for cell: Vector2i in [Vector2i(20,20),Vector2i(29,21)]:
		city.building.putv(cell,Buildings.SUBWAY_STATION)
		city.underground.putv(cell,Underground.STATION_LINK)
	var before := SaveFormat.encode_city(city)
	if not await _setup_access(city): return
	var station := service.network.station_for_route(service.route_data,0)
	check_eq(station.anchor,Vector2i(20,20))
	check_eq(station.node,Vector3i(21,1,21),"stop uses existing real diagonal track node")
	check(not service.route_data.nodes.has(Vector3i(20,1,20)),"no invented rail edge to isolated station tile")
	var points := service.world.access_waypoints(station)
	walker.global_position = points[0]
	var recoveries: Array = []
	walker.recovery_requested.connect(func(reason): recoveries.append(reason))
	await _walk_waypoints(points,"pedestrian passage descent")
	# The access corridor must end before the longitudinal platform walk lane.
	await _walk_waypoints(PackedVector3Array([
		station.platform+station.forward*.33+Vector3.UP*.002,
		station.platform-station.forward*.33+Vector3.UP*.002,
		station.platform+Vector3.UP*.002]),"diagonal platform through-walk")
	points.reverse()
	await _walk_waypoints(points,"pedestrian passage ascent")
	check(recoveries.is_empty(),"diagonal access remains physically supported")
	check_eq(SaveFormat.encode_city(city),before,"pedestrian passage changes no city grid")

func test_shared_stop_candidate_is_skipped_for_a_distinct_connected_pair() -> void:
	var network := _network(terminal_subway_city())
	var same: Dictionary = network.stations[0].duplicate(true)
	same.id = 1
	check(network._route_between(network.stations[0],same).is_empty(),"shared node has no passenger travel segment")
	network._station_options[1].push_front(same)
	var path := network.route(0,1)
	check(not path.is_empty(),"shared first candidate does not mask a distinct connected pair")
	check(path.points.size()>1)

func test_destination_change_keeps_waiting_platform_until_passenger_clears_it() -> void:
	var city := Fixtures.flat_city()
	for x: int in range(18,27): city.building.put(x,19,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
	for y: int in range(20,28): city.building.put(22,y,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,5))
	for cell: Vector2i in [Vector2i(20,20),Vector2i(24,20),Vector2i(23,25)]: city.stamp_building(cell.x,cell.y,Buildings.RAIL_STATION)
	if not await _setup_access(city,3): return
	var old_pose := service.network.station_for_route(service.route_data,0)
	var alternative := service.network.route(0,2)
	check(not alternative.is_empty(),"another side of the station serves the other existing line")
	var next_pose := service.network.station_for_route(alternative,0)
	check(old_pose.node!=next_pose.node,"fixture uses distinct real tracks")
	walker.global_position = old_pose.platform+Vector3.UP*.002
	service.state = "boarding"
	service._station_id = 0
	var body := service.train
	var old_route := service.route_data.duplicate(true)
	check(service.choose_destination(0,2))
	check_eq(service.route_data,old_route,"waiting platform route remains intact")
	check_eq(service.train,body,"waiting carriage is retained")
	check(not service.world.support_for(walker.global_position).is_empty(),"waiting pedestrian keeps a physical floor")
	walker.global_position = Vector3(20.5,old_pose.surface+.002,20.5)
	service._apply_stop_destination()
	check_eq(service.route_data.to,2,"clear entrance permits the alternate platform")
	check_eq(service.network.station_for_route(service.route_data,0).node,next_pose.node)

func test_subway_entrance_cannot_connect_upward_through_the_surface() -> void:
	var city := Fixtures.flat_city()
	city.terrain_surface = TerrainSurface.new(4)
	for y: int in TerrainSurface.VERTS_Y:
		for x: int in range(21,TerrainSurface.VERTS_X): city.terrain_surface.vertices[y*TerrainSurface.VERTS_X+x] = 12
	city.building.put(20,20,Buildings.SUBWAY_STATION)
	for x: int in range(21,27): city.underground.put(x,20,Underground.subway_code(10))
	var network := _network(city)
	check_eq(network.stations.size(),0,"a tunnel above the entrance cannot become reversed stairs")
	check_eq(network.unavailable.size(),1)

func test_rail_platform_keeps_the_station_hall_and_reaches_the_boarding_lane() -> void:
	if not await _setup_access(Fixtures.rail_city()): return
	var station := service.network.station_for_route(service.route_data,0)
	check(service.world._hidden.is_empty(),"the rail hall model stays exactly as the city shows it")
	for child: Node in service.world.get_children():
		check(not String(child.name).begins_with("Station_"),"no retired interior kit part is placed: "+String(child.name))
	var waiting: Vector3 = station.position+station.normal*.52
	waiting.y = station.surface+.002
	walker.global_position = waiting
	var recoveries: Array = []
	walker.recovery_requested.connect(func(reason): recoveries.append(reason))
	var points := service.world.access_waypoints(station)
	await _walk_waypoints(points,"rail entry")
	points.reverse()
	points.append(waiting)
	await _walk_waypoints(points,"rail exit")
	check(recoveries.is_empty(),"approach steps stay physically connected to the lot")
	var lettering: Array = service.world.get_meta("station_signs",[])
	check_gt(lettering.size(),3,"platform totem lettering survives material batching")
	var joined := ""
	for words: Variant in lettering: joined += String(words)+" "
	check(joined.contains("DESERT TRANSIT") and joined.contains(String(station.name)),"the platform totem names the station")
	var stats: Dictionary = service.world.get_meta("station_interior_stats",{})
	check_lt(int(stats.draw_surfaces),12,"furnishings, opaque plaques and finishes share a bounded material batch")

func test_subway_platform_furnishings_use_the_shared_finish_system() -> void:
	var world := ExploreTransitWorld3D.new()
	root.add_child(world)
	var at := Vector3(20.5,2,20.5)
	var basis := Basis(Vector3.UP,PI*.5)
	var station := {"id":0,"name":"Subway 20,20","anchor":Vector2i(20,20),"position":at,"access_position":at,"surface":2.825,"yaw":PI*.5,"side":1,"subway":true,"platform":at+basis*Vector3(.24,.025,0),"normal":basis*Vector3.RIGHT,"forward":basis*Vector3.FORWARD}
	var faces_before := world._physical.size()
	var interior := ExploreStationInterior.populate(world,station)
	check_gt(interior.faces.size(),0,"the bench blocks walking through it")
	var names := {}
	for child: Node in world.get_children(): names[String(child.name)] = names.get(String(child.name),0)+1
	check(names.has("StationNameBoard"),"a mounted enamel name board replaces the retired sign frame")
	check(names.has("TransitRoundel"),"the DT roundel is mounted on the platform wall")
	check(not names.has("Station_bench") and not names.has("Station_sign_frame") and not names.has("Station_ticket_panel"),"no retired kit part is placed")
	var words: Array = world.get_meta("station_signs",[])
	var joined := ""
	for text: Variant in words: joined += String(text)+" "
	check(joined.contains("DESERT TRANSIT\nSubway 20,20") and joined.contains("DT") and joined.contains("BOARD AT OPEN DOORS") and joined.contains("ELEVATOR"),"board, roundel and boarding guidance are lettered")
	# Everything furnished sits on the platform side of the room wall.
	var inverse := Transform3D(basis,at).affine_inverse()
	for child: Node in world.get_children():
		if child is MeshInstance3D and child.mesh!=null:
			for point: Vector3 in child.mesh.get_faces():
				var local: Vector3 = inverse*(child.transform*point)
				check_lt(local.x,ExploreTransitWorld3D.PLATFORM_WALL_FACE+.012,String(child.name)+" stays on the platform side of the wall")
	check_eq(world._physical.size(),faces_before,"populate returns its collision instead of writing it")
	world.free()
	await physics_frame

func test_single_isolated_fill_survives_rebuild() -> void:
	if not await _setup_access(terminal_subway_city()): return
	for repeat: int in 2:
		var count := 0
		for child: Node in service.world.get_children():
			if child is DirectionalLight3D:
				count+=1
				check(not child.shadow_enabled)
				check_eq(child.light_cull_mask,ExploreStationInterior.FURNISHING_LAYER)
		check_eq(count,1,"one isolated fill per world, never per station")
		service.world.build(service.route_data)
	var camera := Camera3D.new()
	check((camera.cull_mask & ExploreStationInterior.FURNISHING_LAYER)!=0,"default Explore camera includes furnishing layer")
	camera.free()
