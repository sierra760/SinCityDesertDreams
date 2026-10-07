# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const Fixtures := preload("res://tests/test_explore_transit_network.gd")
const Names := preload("res://tests/test_station_name_refresh.gd")
const Service := preload("res://scripts/exploration/transit/explore_transit_service.gd")
const SnapshotView := preload("res://tests/test_explore_transit_service.gd").SnapshotView
var view: SnapshotView
var traversal: CityTraversalWorld3D
var walker: ExplorePedestrian
var service: ExploreTransitService
func _setup(subway: bool = false, supplied: City = null) -> void:
	var city := supplied if supplied != null else Fixtures.subway_city() if subway else Fixtures.rail_city()
	view = SnapshotView.new()
	root.add_child(view)
	view.bind_city(city)
	view._geometry_revision = 1
	view.networks.rebuild(city)
	view.snapshot_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,24,16))]
	view.snapshot_networks = view.networks.physical_data()
	traversal = CityTraversalWorld3D.new()
	view.world.add_child(traversal)
	traversal.rebuild(city,view.snapshot_chunks,view.snapshot_networks,1)
	walker = ExplorePedestrian.new()
	view.world.add_child(walker)
	walker.bind(traversal)
	service = Service.new()
	view.world.add_child(service)
	service.bind(view,traversal,walker)
	var station: Dictionary = service.network.stations[0]
	walker.global_position = Vector3(station.anchor.x+.5,station.surface+.002,station.anchor.y+.5)
	service.step(.016,walker)
	await physics_frame
	await physics_frame

func after_each() -> void:
	if is_instance_valid(service): service.clear()
	if is_instance_valid(view): view.free()
	view = null
	service = null
	walker = null
	traversal = null
	await physics_frame

func _wait_boarding() -> bool:
	for i: int in 180:
		service.step(.1,walker)
		if service.state == "boarding": return true
	return false


func _identity(node: Node) -> Array:
	var out: Array=[node.get_instance_id()]
	for child: Node in node.get_children(): out.append_array(_identity(child))
	return out

func _snapshot() -> Array:
	var lifts: Array=[]
	for lift: Node3D in service.world.elevators:
		lifts.append([lift.state,lift.floor,lift._destination,lift._time,lift._duration,lift._door_fraction,lift.cabin.global_transform])
	return [service.network.revision,service.network.nodes.duplicate(true),service.network.stations.map(func(s: Dictionary): return s.id),
		service.route_data.nodes.duplicate(),service.route_data.length,service.route_data.stops.duplicate(true),service.route_data.points.duplicate(),service.route_data.distances.duplicate(),
		service.train.get_instance_id(),service.train.global_transform,service.train.door_fraction,service._station_id,service.speed,service.distance,service.direction,service.state,service._timer,service._door_fraction,service._choices.duplicate(true),
		view.city.building.data.duplicate(),view.city.underground.data.duplicate(),view.city.altitude.data.duplicate(),view.city.terrain.data.duplicate(),
		walker.global_transform,walker.velocity,walker._support_transform,_identity(service.world),lifts]

func _rename_and_check(prefix: String, automatic: Dictionary = {}) -> void:
	var hud := ExploreHUD.new(); root.add_child(hud); hud.set_transit_status(service.status())
	var before := _snapshot()
	var expected := [prefix+"0",prefix+"1"]
	if automatic.is_empty():
		for stop: Dictionary in service.network.stations: view.city.facilities[stop.anchor].name=prefix+str(stop.id)
		service.refresh_names(73)
	else:
		var names: StreetNamingService=automatic.names
		var topology: StreetTopology=automatic.topology
		var result := names.assign(automatic.keys,prefix.strip_edges(),topology.revision)
		check(result.ok and result.changed,"real source-street rename publishes an event while occupied")
		check_eq(service.names_revision,names.revision,"naming event reaches the active service")
		expected=[prefix.strip_edges(),prefix.strip_edges()+" 2"]
		for stop: Dictionary in service.network.stations:
			check_eq(StationNameResolver.name_mode(view.city,stop.anchor),&"automatic")
	check_eq(_snapshot(),before,"routes, state, speed, destination, passenger, lift progress, nodes and collision instance identities exactly retained")
	check_eq(service.status().station,expected[0])
	check_eq(service.status().destination,expected[1])
	check_eq(service.status().next_stop,expected[1])
	check_eq(service.network.station_for_route(service.route_data,0).name,expected[0],"deep route cache refreshed")
	hud.set_transit_status(service.status())
	check_eq(hud._destination_picker.get_item_text(0),expected[1])
	for child: Node in service.world.get_children():
		if child.has_meta("station_name_anchor"):
			var anchor: Vector2i=child.get_meta("station_name_anchor")
			check_eq(child.mesh.text,"DESERT TRANSIT\n"+StationNameResolver.display_name(view.city,anchor,true))
		elif child.has_meta("station_entry_anchor"):
			var anchor: Vector2i=child.get_meta("station_entry_anchor")
			check_eq(child.get_node("StationName").mesh.text,StationNameResolver.display_name(view.city,anchor,true).to_upper())
	hud.free()

func test_renaming_during_ride_or_lift_updates_text_only() -> void:
	await _setup(true,Names.named_city(true))
	await _exercise_occupied_names()

func test_source_street_name_event_during_ride_and_lift_updates_text_only() -> void:
	var city := Names.named_city(true)
	for record: Dictionary in city.facilities.values(): record.erase("name")
	preload("res://tests/fixtures/street_names_fixtures.gd").road(city,Vector2i(18,22),Vector2i(33,22))
	var topology := StreetTopology.new(); topology.rebuild(city)
	var names := StreetNamingService.new(); names.set_station_allocator(StationNameResolver.reconcile)
	check(names.bind_city(city,topology).ok)
	var keys: Array[String]=[]
	for x: int in range(18,33): keys.append(StreetTopology.link_key(Vector2i(x,22),&"open",Vector2i(x+1,22),&"open"))
	check(names.assign(keys,"Before Street",topology.revision).ok)
	check_eq(StationNameResolver.display_name(city,Vector2i(20,20),true),"Before Street")
	check_eq(StationNameResolver.display_name(city,Vector2i(29,20),true),"Before Street 2")
	await _setup(true,city)
	names.changed.connect(func(revision: int,_affected: Dictionary) -> void: service.refresh_names(revision))
	await _exercise_occupied_names({"names":names,"topology":topology,"keys":keys})

func _exercise_occupied_names(automatic: Dictionary = {}) -> void:
	check(_wait_boarding())
	check(service.choose_destination(0,1),"explicit destination choice precedes occupancy")
	walker.transit_support=service
	walker.global_position=service.train.global_transform*Vector3(0,.027,0)
	for i: int in 100:
		service.step(.1,walker)
		walker.step(ExploreInputFrame.idle(),0,.1)
		await physics_frame
		if service.speed>0: break
	check(service.speed>0,"train is moving at refresh")
	check(service.train.contains(walker.global_position),"passenger remains in cabin")
	_rename_and_check("Ride ",automatic)
	var lift: Node3D=service.world.elevators[0]
	walker.global_position=lift.cabin.global_position+Vector3.UP*.002
	check(lift.interact(walker))
	for i: int in 12: lift.step(.1,walker)
	check_eq(lift.state,"moving")
	check(lift._time>0,"lift has progressed")
	_rename_and_check("Lift ",automatic)

func test_unavailable_service_message_refresh_is_literal_and_in_place() -> void:
	var city := Names.named_city(true); city.underground.data.fill(0)
	view=SnapshotView.new(); root.add_child(view); view.bind_city(city)
	traversal=CityTraversalWorld3D.new(); view.world.add_child(traversal)
	walker=ExplorePedestrian.new(); view.world.add_child(walker)
	walker.global_position=Vector3(20.5,CityGeometry3D.ground_height(city,Vector2i(20,20)),20.5)
	service=Service.new(); view.world.add_child(service); service.bind(view,traversal,walker)
	check(service.status().message.begins_with("Original Station:"))
	var before := _identity(service.world)
	city.facilities[Vector2i(20,20)].name="[b]F to Plaza & C[/b]"
	service.refresh_names(74)
	check_eq(_identity(service.world),before)
	check_eq(service.state,"idle")
	check(service.status().message.begins_with("[b]F to Plaza & C[/b]:"))
	var hud := ExploreHUD.new(); root.add_child(hud); hud.set_touch_controls_enabled(true); hud.set_transit_status(service.status())
	check_eq(hud._transit_label.text,service.status().message)
	service.begin_surface_drive_route([])
	var driving_message: String = service.status().message
	service.refresh_names(75)
	check_eq(service.status().message,driving_message,"old unavailable anchor cannot replace a later driving message")
	check(not service.status().message_literal,"retired unavailable message loses literal-title ownership")
	hud.free()

func test_main_revision_reaches_live_service_and_releases_old_session() -> void:
	var host: GameHost=preload("res://scenes/main.tscn").instantiate()
	host.preferences_path="user://station-name-live-main.cfg"; root.add_child(host)
	var city := Names.named_city(true)
	for x: int in range(18,34): city.building.put(x,22,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	host.begin_city(city,{},42,CityStats.new())
	host.city_view_3d.set_center_cell(Vector2i(20,22))
	host.city_view_3d.refresh(true)
	check(host.enter_explore(),"real Main enters Explore on fixture road")
	var live: ExploreTransitService=host.exploration.transit_service
	if is_instance_valid(live):
		check(is_instance_valid(live.train),"nearby station prepares service")
		var instance_ids := _identity(live.world)
		var anchor := Vector2i(20,20)
		check(host.builder.rename_facility(anchor,"Main Renamed").ok)
		check(host.street_naming_service.refresh_station_names([anchor]).ok)
		check_eq(live.network.station(0).name,"Main Renamed")
		check_eq(live.names_revision,host.street_naming_service.revision)
		check_eq(_identity(live.world),instance_ids)
		check_eq(live.network.station_for_route(live.route_data,0).name,"Main Renamed")
		host.begin_city(Names.named_city(true),{},43,CityStats.new())
		check(not is_instance_valid(live),"city replacement releases old transit service")
		check(host.street_naming_service.refresh_station_names([anchor]).ok,"new city naming has no obsolete service target")
		check_eq(city.facilities[anchor].name,"Main Renamed")
	host.free(); await process_frame
