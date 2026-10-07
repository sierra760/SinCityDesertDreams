# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func _street(developed: bool = true) -> City:
	var city := flat_city()
	for x: int in range(10,51):
		city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
		if developed:
			city.building.put(x,19,Buildings.RES_1X1_FIRST)
			city.building.put(x,21,Buildings.COM_1X1_FIRST)
	return city

func test_reciprocal_connections_and_edits() -> void:
	var city := _street()
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	check_eq(graph.neighbors(Vector2i(20,20),&"road").size(),2)
	city.building.put(21,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5))
	check(graph.refresh())
	check_eq(graph.neighbors(Vector2i(20,20),&"road"),[Vector2i(19,20)],"perpendicular neighbor cannot connect")
	city.building.put(19,20,0)
	graph.refresh()
	check(graph.neighbors(Vector2i(20,20),&"road").is_empty(),"isolated road has no route")
	check(not graph.refresh(),"unchanged graph is retained")

func test_demand_quiet_empty_and_local_land_use() -> void:
	var city := _street(false)
	var traffic := CityTraffic3D.new()
	traffic.bind_city(city)
	traffic.advance(0,true)
	check_eq(traffic.actors.size(),0,"roads alone do not invent residents")
	city.building.put(20,19,Buildings.RES_1X1_FIRST)
	city.building.put(21,19,Buildings.COM_1X1_FIRST)
	traffic.invalidate()
	traffic.advance(0,true)
	check_gt(traffic.actors.size(),0,"development supplies local demand")
	check_gt(traffic.graph.demand(Vector2i(20,20)).people,traffic.graph.demand(Vector2i(40,20)).people)
	var before: float = traffic.graph.demand(Vector2i(40,20)).cars
	city.traffic.put(20,10,255)
	traffic.invalidate()
	traffic.advance(0,true)
	check_gt(traffic.graph.demand(Vector2i(40,20)).cars,before,"congestion creates vehicle demand")
	traffic.free()

func test_pause_resume_edits_and_city_immutability() -> void:
	var city := _street()
	var before := hash([city.building.data,city.terrain.data,city.flags.data,city.zone.data,city.traffic.data,city.altitude.data])
	var traffic := CityTraffic3D.new()
	traffic.bind_city(city)
	traffic.advance(0,true)
	var poses: Array = traffic.actors.duplicate(true)
	traffic.advance(.2,true)
	check_eq(traffic.actors,poses,"pause freezes actor progression")
	traffic.advance(.2,false)
	check(traffic.actors != poses,"resume advances actors")
	check_eq(hash([city.building.data,city.terrain.data,city.flags.data,city.zone.data,city.traffic.data,city.altitude.data]),before,"presentation never writes city")
	for x: int in range(10,51): city.building.put(x,20,0)
	traffic.invalidate()
	traffic.advance(0,true)
	check_eq(traffic.actors.size(),0,"edits remove unsupported actors even paused")
	traffic.free()

func test_following_and_connected_motion() -> void:
	var traffic := CityTraffic3D.new()
	traffic.bind_city(_street())
	traffic.advance(0,true)
	var a: Dictionary = traffic.actors[0].duplicate(true)
	a.type = &"road"
	a.kind = &"car"
	a.cell = Vector2i(20,20)
	a.previous = Vector2i(19,20)
	a.next = Vector2i(21,20)
	a.id = 100
	a.t = .1
	var b := a.duplicate(true)
	b.id = 101
	b.t = .35
	traffic.actors.assign([a,b])
	traffic._step(.1)
	check_eq(float(a.t),.1,"follower waits for lead vehicle")
	check_gt(float(b.t),.35,"leader can advance")
	for i: int in 500: traffic._step(1.0/30)
	for actor: Dictionary in traffic.actors:
		check(traffic.graph.neighbors(actor.cell,actor.domain).has(actor.next),"actor stays connected")
		check(traffic.actor_pose(actor).origin.is_finite())
	traffic.free()

func test_bounded_population_claim_release_and_resources() -> void:
	var city := flat_city()
	for y: int in range(10,110,2):
		for x: int in range(5,120):
			city.building.put(x,y,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
			city.building.put(x,y+1,Buildings.COM_1X1_FIRST)
	var traffic := CityTraffic3D.new()
	traffic.bind_city(city)
	traffic.advance(0,true)
	check(traffic.actors.size() <= CityTraffic3D.MAX_VEHICLES+CityTraffic3D.MAX_PEDESTRIANS)
	check_gt(traffic.actors.size(),100)
	var a: Dictionary = traffic.actors[0]
	var at := traffic.actor_pose(a).origin
	var nearest := traffic.nearest_drivable_vehicle(at,.1)
	check(not nearest.is_empty() and traffic._claims.is_empty(),"boarding prompt query is read-only")
	var claim := traffic.claim_nearby_vehicle(at,.1)
	check(not claim.is_empty())
	check(CityTrafficCatalog.is_drivable(claim.kind))
	var old: float = a.t
	traffic._step(.1)
	check_eq(float(a.t),old,"claimed actor is suspended")
	traffic.release_vehicle(claim,at)
	check(not traffic._claims.has(claim.id))
	var batches := traffic._batches.duplicate()
	traffic.advance(0,true)
	for key: String in batches: check_eq(traffic._batches[key],batches[key],"batch node reused")
	traffic.free()

func test_ports_xy_and_crew_records() -> void:
	var record := CityEntityRecords.normalize({"kind":&"ship","x":4,"y":7,"heading":2},&"plane")
	check_eq(record.kind,&"ship")
	check_eq(record.pos,Vector2(4,7))
	check_eq(record.heading,2)

func test_bridge_height_matches_visual_deck() -> void:
	var city := flat_city()
	var bridge := 81
	city.building.put(20,20,bridge)
	city.building.put(21,20,bridge)
	city.flags.put(20,20,RotationMapper.AXIS_FLAG)
	city.flags.put(21,20,RotationMapper.AXIS_FLAG)
	city.building.put(19,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	city.building.put(22,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var helper := CityNetworks3D.new()
	helper._prepare_bridge_decks(city)
	for offset: Vector2 in [Vector2(.1,.5),Vector2(.5,.5),Vector2(.9,.5)]:
		check_eq(graph.point(Vector2i(20,20),&"road",offset),helper._point(city,Vector2i(20,20),offset,.65),"uses exact renderer bridge profile")
	helper.free()

func test_rail_ridership_and_passenger_reservation() -> void:
	var city := flat_city()
	for x: int in range(10,30): city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
	var traffic := CityTraffic3D.new()
	traffic.bind_city(city)
	traffic.riders = {&"rail":800}
	traffic.advance(0,true)
	check_gt(traffic.actors.size(),0)
	check(not traffic.get_drive_route(&"train",Vector3(15.5,0,20.5)).is_empty())
	var reserve: Array[Vector2i] = []
	for x: int in range(10,30): reserve.append(Vector2i(x,20))
	traffic.set_reserved_rail_cells(reserve)
	traffic.advance(0,true)
	check_eq(traffic.actors.size(),0,"passenger route excludes ambient trains")
	traffic.free()

func test_ramp_endpoints_follow_the_rendered_curve() -> void:
	var city := flat_city()
	var cell := Vector2i(30,30)
	city.building.putv(cell,Buildings.ONRAMP_FIRST)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var ends := NetworkShapes.onramp_endpoints(Buildings.ONRAMP_FIRST,false,0)
	var helper := CityNetworks3D.new()
	for t: float in [0.0,.25,.5,.75,1.0]:
		var expected := helper._ramp_point(city,cell,Vector2(ends[0]),Vector2(ends[1]),t,0,0)
		var offset := Vector2(expected.x-cell.x,expected.z-cell.y)
		check(graph.point(cell,&"road",offset).distance_to(expected)<.0001,"exact ramp curve height and point")
	var traffic := CityTraffic3D.new()
	traffic.bind_city(city)
	var actor := {"cell":cell,"previous":cell+Vector2i(ends[0]),"next":cell+Vector2i(ends[1]),"t":.5,"side":1.0,"domain":&"road","type":&"road"}
	var pose := traffic.actor_pose(actor)
	check(absf(pose.basis.z.y)>.05,"vehicle pitches with ramp tangent")
	traffic.free()
	helper.free()

func test_water_routes_and_external_interpolation_pause() -> void:
	var city := flat_city()
	for x: int in range(10,16): city.terrain.put(x,20,Terrain.SURFACE)
	var traffic := CityTraffic3D.new()
	traffic.bind_city(city)
	check(traffic.graph.neighbors(Vector2i(12,20),&"water").has(Vector2i(13,20)))
	check(not traffic.graph.has_cell(Vector2i(12,19),&"water"),"boats cannot use dry ground")
	traffic.advance(0,true,[{"kind":&"ship","x":12,"y":20}])
	var before: Vector3 = traffic._external[0].presentation_position
	traffic.advance(.1,false,[{"kind":&"ship","x":13,"y":20}])
	var smooth: Vector3 = traffic._external[0].presentation_position
	check(smooth.x>before.x and smooth.x<13.5,"source updates interpolate")
	traffic.advance(.1,true,[{"kind":&"ship","x":14,"y":20}])
	check_eq(traffic._external[0].presentation_position,smooth,"paused source interpolation freezes")
	var claim := traffic.claim_nearby_vehicle(smooth,.1)
	check_eq(claim.kind,&"ship","live port ships can be boarded")
	traffic.release_vehicle(claim,smooth)
	traffic.advance(0,true,[{"kind":&"plane","x":12,"y":20}])
	check(traffic.claim_nearby_vehicle(traffic._external[0].presentation_position,.1).is_empty(),"airplanes remain ambient")
	traffic.free()

func test_reserved_next_edge_and_long_vehicle_following() -> void:
	var traffic := CityTraffic3D.new()
	traffic.bind_city(_street())
	traffic.advance(0,true)
	var a: Dictionary = traffic.actors[0].duplicate(true)
	a.kind=&"bus"
	a.type=&"road"
	a.cell=Vector2i(20,20)
	a.previous=Vector2i(19,20)
	a.next=Vector2i(21,20)
	a.id=100
	a.t=.1
	a.length=.7
	var b:=a.duplicate(true)
	b.kind=&"truck"
	b.id=101
	b.t=.75
	traffic.actors.assign([a,b])
	traffic._step(.1)
	check_eq(float(a.t),.1,"long vehicles respect authored dimensions")
	a.domain=&"rail"
	traffic._reserved_rail[a.next]=true
	traffic._step(.1)
	check_eq(float(a.t),.1,"newly reserved next edge freezes before periodic refresh")
	traffic.free()

func test_surface_train_priority_at_road_crossing() -> void:
	var city:=_street()
	city.building.put(20,20,NetworkShapes.CROSS_ROAD_EW_RAIL_NS)
	for y: int in [19,21]: city.building.put(20,y,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,5))
	var traffic:=CityTraffic3D.new()
	traffic.bind_city(city)
	var car: Dictionary={"id":1,"type":&"road","kind":&"car","domain":&"road","cell":Vector2i(20,20),"previous":Vector2i(19,20),"next":Vector2i(21,20),"t":.1,"speed":1.0,"side":1.0,"turns":0,"stopped":false}
	var train:=car.duplicate(true)
	train.id=2
	train.type=&"rail"
	train.kind=&"train"
	train.domain=&"rail"
	train.previous=Vector2i(20,19)
	train.next=Vector2i(20,21)
	train.t=.3
	traffic.actors.assign([car,train])
	traffic._step(.1)
	check_eq(float(car.t),.1,"road vehicle yields to surface train")
	check_gt(float(train.t),.3,"train progresses through crossing")
	traffic.free()

func test_upper_highway_and_lower_road_crossing_remain_separate() -> void:
	var city:=flat_city()
	city.building.put(20,20,NetworkShapes.HIGHWAY_NS_ROAD_EW)
	for x: int in [19,21]: city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	for y: int in [19,21]: city.building.put(20,y,NetworkShapes.highway_id(5))
	city.traffic.put(10,10,255)
	var graph:=CityTrafficGraph.new()
	graph.bind_city(city)
	check_eq(graph.neighbors(Vector2i(20,20),&"road"),[Vector2i(21,20),Vector2i(19,20)])
	check_eq(graph.neighbors(Vector2i(20,20),&"highway"),[Vector2i(20,19),Vector2i(20,21)])
	check_gt(graph.point(Vector2i(20,20),&"highway").y,graph.point(Vector2i(20,20),&"road").y+.5,"upper and lower decks retain distinct heights")
	var traffic:=CityTraffic3D.new()
	traffic.bind_city(city)
	var route:=traffic.get_drive_route(&"car",graph.point(Vector2i(20,20),&"highway"))
	check_eq(route.domain,&"highway","drive admission chooses the closest physical deck")
	traffic.advance(0,true)
	check(traffic.actors.size()<=CityTraffic3D.MAX_VEHICLES+CityTraffic3D.MAX_PEDESTRIANS)
	traffic.free()

func test_onramp_links_road_to_upper_highway_without_deck_jump() -> void:
	var city:=flat_city()
	var cell:=Vector2i(30,30)
	var code:=Buildings.ONRAMP_FIRST
	var ends:=NetworkShapes.onramp_endpoints(code,false,0)
	var low:=cell+Vector2i(ends[0])
	var high:=cell+Vector2i(ends[1])
	city.building.putv(cell,code)
	city.building.putv(low,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10 if ends[0].x!=0 else 5))
	city.building.putv(high,NetworkShapes.highway_id(10 if ends[1].x!=0 else 5))
	var graph:=CityTrafficGraph.new()
	graph.bind_city(city)
	check(graph.neighbors(cell,&"road").has(low) and graph.neighbors(cell,&"road").has(high),"road admission spans ramp endpoints")
	check(graph.neighbors(cell,&"highway").has(low) and graph.neighbors(cell,&"highway").has(high),"highway admission spans ramp endpoints")
	check_eq(graph.continuation_domain(cell,low,&"highway"),&"road")
	check_eq(graph.continuation_domain(cell,high,&"road"),&"highway")
	var traffic:=CityTraffic3D.new()
	traffic.bind_city(city)
	var a: Dictionary={"id":10,"kind":&"car","type":&"road","domain":&"road","cell":low,"previous":low+Vector2i(ends[0]),"next":cell,"t":.99,"speed":1.0,"side":1.0,"turns":0,"stopped":false}
	var b:=a.duplicate(true)
	b.id=11
	b.type=&"highway"
	b.domain=&"highway"
	b.cell=high
	b.previous=high+Vector2i(ends[1])
	traffic.actors.assign([a,b])
	traffic._step(.03)
	check(a.cell==cell and b.cell==high,"single-lane ramp reserves opposing entrance")
	check(b.stopped)
	check(not graph.allows_pedestrians(cell),"pedestrians remain on streets rather than highway ramps")
	traffic.free()

func test_overview_cadence_preserves_elapsed_motion_and_pause() -> void:
	var traffic:=CityTraffic3D.new()
	traffic.bind_city(_street())
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=80
	root.add_child(camera)
	camera.position=Vector3(30,20,30)
	camera.look_at(Vector3(30,2.5,20))
	traffic.advance(0,true,[],camera)
	for i: int in 60: traffic.advance(1.0/60,false,[],camera)
	check_eq(traffic.statistics.simulation_hz,10,"overview logic has a bounded lower cadence")
	check(absf(traffic._elapsed-1.0)<.001,"cadence preserves elapsed simulation presentation time")
	var before:=traffic.actors.duplicate(true)
	traffic.advance(.2,true,[],camera)
	check_eq(traffic.actors,before,"pause freezes interpolation as well as logic")
	camera.size=4
	traffic.advance(0,true,[],camera)
	check_eq(traffic.statistics.simulation_hz,30,"near camera restores thirty-hertz logic")
	camera.free()
	traffic.free()

func test_service_and_congestion_updates_retain_geometry_cache() -> void:
	var city := _street(false)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var cell := Vector2i(20,20)
	var center := graph.center(cell,&"road")
	var revision := graph.revision
	city.flags.put(20,20,TileFlags.POWERED|TileFlags.WATERED)
	city.zone.put(20,19,1)
	check(not graph.refresh(),"service flags and empty zoning do not change traffic geometry or demand")
	check_eq(graph.revision,revision,"service updates retain geometry revision")
	city.traffic.put(10,10,255)
	check(graph.refresh(),"congestion is still refreshed")
	check_eq(graph.revision,revision,"congestion retains route and pose caches")
	check_eq(graph.center(cell,&"road"),center)
	check_eq(graph.demand(cell).congestion,1.0)
	check_eq(graph.demand(cell).cars,1.5,"congestion demand preserved without neighborhood rescan")
	city.traffic.put(10,10,0)
	graph.refresh()
	check_eq(graph.demand(cell).cars,0.0,"congestion can decrease to quiet")
	city.building.put(21,20,0)
	graph.refresh()
	check_gt(graph.revision,revision,"real road edit rebuilds routes")
	check(not graph.neighbors(cell,&"road").has(Vector2i(21,20)))

func test_development_refreshes_local_demand_without_route_rebuild() -> void:
	var city := _street(false)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var revision := graph.revision
	city.building.put(20,19,Buildings.COM_1X1_FIRST)
	check(graph.refresh())
	check_eq(graph.revision,revision,"dry lot development keeps connected lanes")
	check_eq(graph.developed,1)
	check_eq(graph.facilities[Buildings.COM_1X1_FIRST],1)
	check_eq(graph.demand(Vector2i(20,20)).commercial,1)
	check_gt(graph.demand(Vector2i(20,20)).people,0)
	check_eq(graph.demand(Vector2i(40,20)).people,0)
	city.building.put(20,19,0)
	graph.refresh()
	check_eq(graph.revision,revision)
	check_eq(graph.developed,0)
	check(not graph.facilities.has(Buildings.COM_1X1_FIRST))
	check_eq(graph.demand(Vector2i(20,20)).people,0)

func test_axis_height_and_flood_changes_still_rebuild_routes() -> void:
	var city := flat_city()
	var cell := Vector2i(20,20)
	city.building.putv(cell,Buildings.ONRAMP_FIRST)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var revision := graph.revision
	city.flags.putv(cell,RotationMapper.AXIS_FLAG)
	check(graph.refresh(),"ramp axis matters unlike service flags")
	check_gt(graph.revision,revision)
	var expected := NetworkShapes.onramp_endpoints(Buildings.ONRAMP_FIRST,true,0)
	check_eq(graph._nodes[&"road"][cell].ramp,expected)
	var before := graph.center(cell,&"road")
	city.set_heights(20,20,12,0)
	check(graph.refresh())
	check(graph.center(cell,&"road").y != before.y,"height change discards pose centers")
	city.flood_overlay[Vector2i(30,30)] = true
	check(graph.refresh())
	check(graph.has_cell(Vector2i(30,30),&"water"),"flood opens water route")
