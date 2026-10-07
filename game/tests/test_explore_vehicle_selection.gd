# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/vehicle_selection_case.gd"

func test_destination_choice_refreshes_the_suspended_explore_panel_immediately() -> void:
	var city := TransitFixtures.subway_city()
	city.building.put(25,20,Buildings.SUBWAY_STATION)
	city.underground.put(25,20,Underground.STATION_LINK)
	if not await _setup(city,Vector3(20.5,.5,21.5)): return
	var service := session.transit_service
	service._prepare(service.network.route(0,1))
	session.pedestrian.global_position=service.network.station_for_route(service.route_data,0).platform+Vector3.UP*.002
	service.set_suspended(false)
	for i: int in 240:
		service.step(.1,session.pedestrian)
		if service.state=="boarding": break
	check_eq(service.state,"boarding")
	session._publish_status()
	session.suspend()
	check_eq(hud._destination_picker.get_selected_metadata(),1)
	hud.destination_selected.emit(0,2)
	check_eq(service.route_data.to,2,"service accepts the new route")
	check_eq(hud._destination_picker.get_selected_metadata(),2,"paused panel refreshes without waiting for Resume")
	check(session.is_suspended(),"selecting a destination does not release the menu or start movement")

func test_empty_network_rejects_vehicle_and_plane_without_city_changes() -> void:
	var city := flat_city()
	if not await _setup(city): return
	var saved := SaveFormat.encode_city(city)
	session.suspend()
	for kind: StringName in [&"bus",&"train",&"subway",&"ship",&"sailboat",&"plane"]:
		check(not session.select_vehicle(kind),"no compatible route "+String(kind))
		check_eq(session.occupied,session.pedestrian)
	check_eq(SaveFormat.encode_city(city),saved)
	check(session._message.contains("driven"),"plane exclusion explains why")

func test_each_road_kind_selection_exit_and_suspension_release() -> void:
	var city := flat_city()
	for x in range(18,34): city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	if not await _setup(city): return
	var saved := SaveFormat.encode_city(city)
	for kind: StringName in CityTrafficCatalog.vehicle_kinds():
		if CityTrafficCatalog.domain(kind)!=&"road": continue
		session.suspend()
		check(session.select_vehicle(kind),"selection "+String(kind))
		if session.occupied == session.pedestrian: continue
		check(not session.pedestrian.visible)
		check_eq(session.occupied.kind,kind)
		check(session._held.is_empty() and session._edges.is_empty())
		session.resume()
		await physics_frame
		var frame := ExploreInputFrame.idle()
		session.occupied.step(frame,0,.016)
		check(session.request_interaction(),"safe supported exit "+String(kind))
		check_eq(session.occupied,session.pedestrian)
		check(session.pedestrian.visible)
	check_eq(SaveFormat.encode_city(city),saved,"possession leaves city bytes untouched")
	session.suspend()
	check(session.select_vehicle(&"helicopter"),"helicopter remains selectable")
	session._held[KEY_Q] = true
	session._edges[KEY_F] = true
	session.suspend()
	check(session._held.is_empty() and session._edges.is_empty(),"modal suspension releases all held/edge input")
	check_eq(session.occupied.velocity,Vector3.ZERO)
	session.leave()
	check(session.selected_vehicle==null and session.transit_service==null,"leave disposes selection and transit service")

func test_subway_selection_uses_real_underground_route_and_platform_exit() -> void:
	var city := TransitFixtures.subway_city()
	if not await _setup(city,Vector3(20.5,.5,21.5)): return
	var saved := SaveFormat.encode_city(city)
	session.suspend()
	check(session.select_vehicle(&"subway"),"subway route can be driven")
	if session.occupied == session.pedestrian: return
	var actor: ExploreRouteVehicle = session.occupied
	check(actor.global_position.y<CityGeometry3D.ground_height(city,Vector2i(20,20))-.3,"subway is physically below terrain")
	check(session._valid_actor(actor),"underground support bypasses dry-ground recovery")
	session.resume()
	await physics_frame
	check(session.request_interaction(),"stopped subway exits onto real underground platform")
	check(session.transit_service.contains(session.pedestrian.global_position))
	check_eq(session.transit_service.state,"idle","subway exit returns passenger service to its idle scheduler")
	check(session.selected_vehicle==null,"driven subway no longer obstructs arriving service")
	session.transit_service.step(.1,session.pedestrian)
	check_eq(session.transit_service.state,"approaching","passenger service resumes while walker remains on supported platform")
	check(session.transit_service.contains(session.pedestrian.global_position))
	check_eq(SaveFormat.encode_city(city),saved)

func test_ambient_helicopter_claim_is_released_on_exit_and_leave() -> void:
	if not await _setup(flat_city()): return
	var traffic := view.traffic
	traffic._external = [{"kind":&"helicopter","presentation_position":session.pedestrian.global_position,
		"presentation_yaw":0.0,"presentation_id":-42}]
	session.car.global_position += Vector3(5,0,0)
	session.helicopter.global_position += Vector3(5,0,0)
	# Relocation from raised pavement to terrain must also move the skids down.
	var support := session.traversal.support_near(session.helicopter.global_position,.01,.1,[session.helicopter.get_rid()])
	check(not support.is_empty(),"relocated helicopter has a physical landing floor")
	if support.is_empty(): return
	session.helicopter.global_position = support.position+Vector3.UP*.002
	session._publish_status()
	check(hud._prompt_label.text.contains("Helicopter"),"read-only nearby prompt advertises ambient boarding")
	check(traffic._claims.is_empty(),"viewing the boarding hint never claims a vehicle")
	var parked := session.helicopter.global_position
	check(session._board_ambient(),"nearby helicopter can be claimed")
	check(traffic._claims.has(-42))
	check_eq(session.occupied,session.helicopter)
	check(Vector2(session.helicopter.global_position.x-session.pedestrian.global_position.x,
		session.helicopter.global_position.z-session.pedestrian.global_position.z).length()<.01,
		"the session helicopter lands at the claimed ambient pose instead of its distant parking")
	check(session.helicopter.global_position.distance_to(parked)>4.0,"distant parked helicopter is not occupied in place")
	await physics_frame
	session.helicopter.step(ExploreInputFrame.idle(),0,.016)
	check(session.request_interaction(),"landed helicopter exits safely")
	check(traffic._claims.is_empty(),"exit releases ambient helicopter claim")
	traffic._external[0].presentation_position = session.pedestrian.global_position
	check(session._board_ambient())
	session.leave()
	check(traffic._claims.is_empty(),"session teardown releases remaining claims")

func test_ambient_helicopter_without_landing_space_is_not_boarded() -> void:
	if not await _setup(flat_city()): return
	var traffic := view.traffic
	var claim_at := session.pedestrian.global_position+Vector3(.3,0,0)
	traffic._external = [{"kind":&"helicopter","presentation_position":claim_at,
		"presentation_yaw":0.0,"presentation_id":-43}]
	session.helicopter.global_position += Vector3(5,0,0)
	var parked := session.helicopter.global_position
	# The session car occupies the ambient landing pose.
	session.car.global_position = claim_at
	await physics_frame
	check(not session._board_ambient(),"blocked ambient landing pose is refused")
	check(traffic._claims.is_empty(),"refused boarding releases its claim")
	check_eq(session.occupied,session.pedestrian)
	check_eq(session.helicopter.global_position,parked,"parked session helicopter stays where it was")

func test_stopped_boat_exits_only_on_supported_dry_shore() -> void:
	var city := flat_city()
	for y in range(20,24):
		for x in range(20,24):
			city.terrain.put(x,y,Terrain.SUBMERGED)
			city.set_heights(x,y,2,4)
	if not await _setup(city,Vector3(24.5,2.5,21.5)): return
	session.suspend()
	check(session.select_vehicle(&"ship"))
	if session.occupied == session.pedestrian: return
	var boat: ExploreRouteVehicle = session.occupied
	boat.rotation = Vector3.ZERO
	boat.global_position = Vector3(21.5,boat.global_position.y,21.5)
	session.resume()
	await physics_frame
	check(not session.request_interaction(),"open water has no safe pedestrian exit")
	check_eq(session.occupied,boat)
	boat.global_position.x = 24.0-boat.vehicle_size().x*.5-.012
	check(boat.has_support(),"entire hull remains over water near shore")
	# Deliberately place the parked aircraft across the only dry exit candidate.
	session.helicopter.global_position = Vector3(24.2,4*CityGeometry3D.HEIGHT+.042,21.5)
	await physics_frame
	check(not session.request_interaction(),"parked helicopter blocks the narrow shoreline exit")
	# Clear the deliberate obstruction before testing the unoccupied shore.
	session.car.global_position += Vector3(5,0,0)
	session.helicopter.global_position += Vector3(5,0,0)
	await physics_frame
	check(session.request_interaction(),"stopped boat can exit onto adjacent dry shore")
	check_eq(session.occupied,session.pedestrian)
	check(not session.traversal.touches_water(session.pedestrian.global_position))
	check(session.pedestrian.global_position.x>=24.0)

func test_removed_occupied_road_is_revalidated_before_next_actor_step() -> void:
	var city := flat_city()
	for x in range(18,34): city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	if not await _setup(city): return
	session.suspend()
	check(session.select_vehicle(&"bus"))
	if session.occupied == session.pedestrian: return
	var position := session.occupied.global_position
	for x in range(18,34): city.building.put(x,20,Buildings.NONE)
	view._geometry_revision += 1
	view.networks.rebuild(city)
	view.sample_networks = view.networks.physical_data()
	view.sample_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,24,16))]
	session._on_geometry_rebuilt(view._geometry_revision)
	var requests: Array[bool] = []
	session.return_requested.connect(func() -> void: requests.append(true))
	check(not session._reconcile_revision(),"deleted entire occupied route cannot validate using stale graph")
	check_eq(requests.size(),1,"missing replacement route requests Return to Build")
	check_eq(session.occupied.global_position,position,"revalidation occurs before any further motion")

func test_surface_train_possession_exclusively_reserves_route_then_resumes_service() -> void:
	var city := TransitFixtures.rail_city()
	if not await _setup(city,Vector3(20.5,2.5,20.8)): return
	var service := session.transit_service
	var station: Dictionary = service.network.stations[0]
	session.pedestrian.global_position = station.platform+Vector3.UP*.003
	session.suspend()
	check(session.select_vehicle(&"train"))
	if session.occupied == session.pedestrian: return
	check_eq(service.state,"driving")
	check(service.train==null,"automatic train retires during manual control")
	check(not view.traffic._reserved_rail.is_empty(),"manual surface rail route reserves ambient cells")
	session.resume()
	await physics_frame
	check(session.request_interaction(),"stopped surface train has supported platform exit")
	check_eq(service.state,"idle")
	check(session.selected_vehicle==null,"manual train removed before automatic service resumes")
	check(view.traffic._reserved_rail.is_empty(),"manual reservation releases on exit")
	service.step(.1,session.pedestrian)
	check_eq(service.state,"approaching")

func test_recover_from_driven_train_releases_route_and_stands_on_outdoor_road() -> void:
	var city := TransitFixtures.rail_city()
	if not await _setup(city,Vector3(20.5,2.5,20.8)): return
	var service := session.transit_service
	var station: Dictionary = service.network.stations[0]
	session.pedestrian.global_position = station.platform+Vector3.UP*.003
	session.suspend()
	check(session.select_vehicle(&"train"))
	if session.occupied == session.pedestrian: return
	check(session.recover(),"Recover from a driven train succeeds")
	check_eq(session.occupied,session.pedestrian,"rail vehicles cannot stand on roads; the player walks")
	check(session.selected_vehicle==null,"manual train is removed")
	check_eq(service.state,"idle")
	check(view.traffic._reserved_rail.is_empty(),"manual rail reservation is released")
	var feet := session.pedestrian.global_position
	var cell := Vector2i(floori(feet.x),floori(feet.z))
	check(view.traffic.graph.has_cell(cell,&"road"),"player stands on a road tile")
	check(not session.traversal.inside_road_tunnel(feet) and not session.traversal.touches_water(feet),"road pose is outdoors and dry")

func test_manual_subway_survives_unrelated_geometry_then_stops_on_deleted_route() -> void:
	var city := TransitFixtures.subway_city()
	if not await _setup(city,Vector3(20.5,.5,21.5)): return
	session.suspend()
	check(session.select_vehicle(&"subway"))
	if session.occupied == session.pedestrian: return
	var actor: ExploreRouteVehicle = session.occupied
	actor._distance = 1.0
	actor.global_transform = actor._rail_pose(actor._distance)
	var position := actor.global_position
	var projected_floor: PackedVector3Array = session.traversal._retained[Vector2i(0,0)].points
	_refresh_fixture_geometry()
	check(session._reconcile_revision(),"unchanged subway route survives unrelated geometry rebuild")
	check_eq(session.traversal._retained[Vector2i(0,0)].points,projected_floor,"unrelated revision preserves open station stairs in physical terrain")
	check_eq(actor.global_position,position,"unchanged route preserves driven position")
	check_eq(session.transit_service.state,"driving")
	check(session.transit_service.world.support_for(session.transit_service.network.stations[0].platform).size()>0,"rebuild retains physical platform")
	city.underground.put(25,20,0)
	_refresh_fixture_geometry()
	var requests: Array[bool] = []
	session.return_requested.connect(func() -> void: requests.append(true))
	check(not session._reconcile_revision(),"disconnected underground route requests recovery before movement")
	check_eq(requests.size(),1)
	check_eq(actor.global_position,position,"deleted route never receives a stale movement step")

func test_transit_route_support_rejects_changed_links_and_points() -> void:
	var city := TransitFixtures.subway_city()
	if not await _setup(city,Vector3(20.5,.5,21.5)): return
	session.suspend()
	check(session.select_vehicle(&"subway"))
	if session.occupied == session.pedestrian: return
	var actor: ExploreRouteVehicle = session.occupied
	var first: Vector3i = actor._transit_route.nodes[0]
	var second: Vector3i = actor._transit_route.nodes[1]
	check(actor.has_support(),"prepared transit route is supported")
	# Validation is cached per network change; in-place edits publish themselves.
	actor.graph.nodes[first].links.erase(second)
	actor.graph.mark_changed()
	check(not actor.has_support(),"existing nodes without reciprocal link are invalid")
	actor.graph.nodes[first].links.append(second)
	actor.graph.nodes[second].point.y += .1
	actor.graph.mark_changed()
	check(not actor.has_support(),"existing nodes at changed heights invalidate old motion points")
	var network: ExploreTransitNetwork = actor.graph
	network.rebuild(network.city,network.graph,network.revision)
	check(actor.has_support(),"a rebuilt network revalidates the unchanged route")

func test_elevator_hint_and_f_control_take_priority_over_nearby_vehicle() -> void:
	var city := TransitFixtures.subway_city()
	var station_height := CityGeometry3D.ground_height(city,Vector2i(20,20))
	if not await _setup(city,Vector3(20.5,station_height+.005,20.5)): return
	var lift: Node3D=session.transit_service.world.elevators[0]
	session.pedestrian.global_position=lift.cabin.global_position+Vector3.UP*.002
	session.car.global_position=session.pedestrian.global_position+Vector3(.05,0,0)
	session._publish_status()
	check_eq(hud._prompt_label.text,"F to ride to platform","nearby vehicle cannot conceal the elevator control")
	check(session.request_interaction(),"F reaches the physical lift")
	check_eq(lift.state,"closing")
	check_eq(session.occupied,session.pedestrian,"lift rider remains a pedestrian")
	var feet := session.pedestrian.global_position
	session.camera_rig.update_follow(1.0/60.0)
	check_lt(session.camera_rig.camera.global_position.distance_to(feet+Vector3.UP*.105),.001,"station status selects a stable eye camera")
