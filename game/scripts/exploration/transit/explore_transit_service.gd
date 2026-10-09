# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## One requested local train service; pedestrian boarding is geometric, never a key.
class_name ExploreTransitService
extends Node3D

var network: ExploreTransitNetwork
var world: ExploreTransitWorld3D
var train: ExploreTransitTrain
var view: CityView3D
var traversal: CityTraversalWorld3D
var walker: ExplorePedestrian
var route_data: Dictionary = {}
var state := "idle"
var speed := 0.0
var distance := 0.0
var direction := 1
var stop_index := 0
var _timer := 0.0
var _graph: CityTrafficGraph
var _revision := -1
var _choices: Dictionary = {}
var _message := ""
var _unavailable_anchor := Vector2i(-1,-1)
var names_revision := -1
var _station_id := -1
var _suspended := false
var _door_fraction := 0.0
var _elapsed := 0.0
var _initial_preparation := true
var _retry_at := 0.0
var _station_scan_at := 0.0
var manual_route_invalidated := false
var _manual_cells: Array[Vector2i] = []
var _manual_points := PackedVector3Array()
var _topology_inputs: Array = []

func bind(value: CityView3D, physical: CityTraversalWorld3D, pedestrian: ExplorePedestrian) -> void:
	view = value
	traversal = physical
	walker = pedestrian
	# Share the ambient traffic graph when it is current for this city; that
	# avoids another whole-city graph scan on Explore entry.
	var traffic: Node3D = view.get("traffic")
	_graph = traffic.graph if traffic != null and traffic.graph.city == view.city else CityTrafficGraph.new()
	_graph.bind_city(view.city)
	_topology_inputs = ExploreTransitNetwork.topology_signature(view.city)
	network = ExploreTransitNetwork.new()
	network.rebuild(view.city,_graph,view.geometry_revision())
	_revision = view.geometry_revision()
	world = ExploreTransitWorld3D.new()
	add_child(world)
	world.bind(view,traversal,network)
	_observe(walker.global_position)
	_initial_preparation = false

func refresh_names(revision: int) -> void:
	if network == null or network.city == null: return
	network.refresh_station_names()
	network.refresh_route_names(route_data)
	if is_instance_valid(world): world.refresh_names()
	if _unavailable_anchor != Vector2i(-1,-1):
		for stop: Dictionary in network.unavailable:
			if stop.anchor == _unavailable_anchor:
				_message = String(stop.name)+": "+String(stop.reason)
				break
	names_revision = revision

func set_suspended(on: bool) -> void:
	_suspended = on

func choose_destination(station_id: int, destination_id: int) -> bool:
	if network == null or network.route(station_id,destination_id).is_empty(): return false
	if is_instance_valid(train) and train.contains(walker.global_position): return false
	if is_instance_valid(world) and world.in_elevator(walker.global_position): return false
	_choices[station_id] = destination_id
	# Keep an underground waiting passenger's platform intact. At a stop the
	# same unoccupied carriage can adopt the new route without respawning.
	if state in ["opening","boarding"]: _apply_stop_destination()
	return true

func step(delta: float, pedestrian: ExplorePedestrian = null) -> void:
	if pedestrian != null: walker = pedestrian
	if _suspended or not is_instance_valid(walker) or not is_finite(delta): return
	var dt := clampf(delta,0,.10)
	_elapsed += dt
	if view.geometry_revision() != _revision:
		_revalidate()
		return
	if is_instance_valid(world): world.step(dt,walker)
	if not walker.visible or state == "driving": return
	if state == "idle":
		_observe(walker.global_position)
		return
	if not is_instance_valid(train): return
	if _elapsed>=_station_scan_at and not train.contains(walker.global_position) and not world.contains(walker.global_position):
		_station_scan_at = _elapsed+.5
		var nearby := _nearest_station(walker.global_position)
		var served := false
		for stop: Dictionary in route_data.stops:
			if int(stop.station)==nearby: served = true
		if served and _choices.has(nearby):
			var desired := network.route(nearby,int(_choices[nearby]))
			if not desired.is_empty():
				var current_pose := network.station_for_route(route_data,nearby)
				var wanted_pose := network.station_for_route(desired,nearby)
				if current_pose.node!=wanted_pose.node or current_pose.normal!=wanted_pose.normal: served = false
		if nearby>=0 and not served and (not is_instance_valid(view.exploration_camera()) or not _spawn_visible(train.global_transform)):
			_retire()
			_observe(walker.global_position)
			return
	var current_station := network.station_for_route(route_data,int(route_data.stops[stop_index].station))
	var obstructed := train.doorway_occupied(walker.global_position)
	match state:
		"opening":
			_door_fraction = minf(1,_door_fraction+dt)
			if _door_fraction>=1:
				state = "boarding"
				_timer = 0
		"boarding":
			_apply_stop_destination()
			_timer += dt
			if _timer>=ExploreTransitTrain.DWELL and not obstructed: state = "closing"
		"closing":
			if obstructed:
				state = "opening"
			else:
				_door_fraction = maxf(0,_door_fraction-dt)
				if _door_fraction<=0:
					if stop_index == route_data.stops.size()-1: direction = -1
					elif stop_index == 0: direction = 1
					stop_index += direction
					state = "departing"
		"approaching", "departing", "braking":
			var target := float(route_data.stops[stop_index].distance)
			var remaining := absf(target-distance)
			var desired := minf(.75,sqrt(2.0*.45*remaining))
			# Unexpected track intrusion stops the vehicle before the pedestrian.
			var riding := train.contains(walker.global_position)
			if not riding and _track_intrusion(walker.global_position):
				desired = 0
				# This is an unexpected track intrusion, not a scheduled stop.
				# Ordinary deceleration needs .625 tiles at full speed, longer
				# than the remaining gap after the carriage's front overhang.
				speed = 0
				_message = "Please stand behind the platform edge."
			speed = move_toward(speed,desired,.45*dt)
			var motion := minf(remaining,speed*dt)
			distance += motion*direction
			train.global_transform = ExploreTransitNetwork.sample(route_data,distance)
			if remaining<.3: state = "braking"
			if remaining<=.002 and desired>0 or remaining<.00001:
				distance = target
				speed = 0
				train.global_transform = ExploreTransitNetwork.sample(route_data,distance)
				state = "opening"
				_timer = 0
				_station_id = int(route_data.stops[stop_index].station)
				_message = "Walk through the open doorway to board or leave."
				_apply_stop_destination()
	current_station = network.station_for_route(route_data,int(route_data.stops[stop_index].station))
	train.set_doors(_door_fraction,current_station.normal)
	train.doors = state if state in ["opening","boarding","closing"] else "closed"

func _nearest_station(position: Vector3) -> int:
	var best := -1
	var gap := 3.0
	for station: Dictionary in network.stations:
		var surface := Vector3(station.anchor.x+.5,station.surface,station.anchor.y+.5)
		var distance_to := minf(position.distance_to(surface),position.distance_to(station.platform))
		if distance_to<gap:
			best = station.id
			gap = distance_to
	return best

func _observe(position: Vector3) -> void:
	_unavailable_anchor = Vector2i(-1,-1)
	var best := _nearest_station(position)
	if best<0:
		_message = ""
		for unavailable: Dictionary in network.unavailable:
			var cell: Vector2i = unavailable.anchor
			var point := Vector3(cell.x+.5,CityGeometry3D.ground_height(view.city,cell),cell.y+.5)
			if point.distance_to(position)<3.0:
				_unavailable_anchor = cell
				_message = String(unavailable.name)+": "+String(unavailable.reason)
				break
		return
	if _elapsed < _retry_at: return
	_station_id = best
	var destinations := network.destinations(best)
	if destinations.is_empty():
		_message = "This station has no connected, usable destination."
		return
	var destination := int(_choices.get(best,destinations[0].id))
	var route := network.route(best,destination)
	if route.is_empty(): return
	_prepare(route)

func _apply_stop_destination() -> void:
	if not is_instance_valid(train) or train.contains(walker.global_position): return
	if is_instance_valid(world) and world.in_elevator(walker.global_position): return
	var destination := int(_choices.get(_station_id,-1))
	if destination<0: return
	if int(route_data.from)==_station_id and int(route_data.to)==destination: return
	var current := network.station_for_route(route_data,_station_id)
	var path := network.route_from_pose(_station_id,destination,current)
	if path.is_empty():
		if world.contains(walker.global_position) or (is_instance_valid(view.exploration_camera()) and _spawn_visible(train.global_transform)):
			_message = "This destination uses another platform. Return to the entrance to change service."
			return
		path = network.route(_station_id,destination)
	if path.is_empty(): return
	world.build(path)
	route_data = path
	stop_index = 0
	direction = 1
	distance = 0
	speed = 0
	_timer = 0
	train.global_transform = ExploreTransitNetwork.sample(path,0)
	_reserve_path(path)

## Test the nearby rail corridor itself. A rectangular look-ahead box rotates
## across a safe waiting platform when a train approaches around a bend.
func _track_intrusion(feet: Vector3) -> bool:
	var points: PackedVector3Array=route_data.get("points",PackedVector3Array())
	var lengths: PackedFloat32Array=route_data.get("distances",PackedFloat32Array())
	if lengths.size()!=points.size(): return false
	var low := maxf(0.0,distance-.65)
	var high := distance+.65
	for i: int in range(1,points.size()):
		if lengths[i]<low: continue
		if lengths[i-1]>high: break
		var span := maxf(.000001,lengths[i]-lengths[i-1])
		var a := points[i-1].lerp(points[i],clampf((low-lengths[i-1])/span,0,1))
		var b := points[i-1].lerp(points[i],clampf((high-lengths[i-1])/span,0,1))
		var delta := Vector2(b.x-a.x,b.z-a.z)
		var t := clampf(Vector2(feet.x-a.x,feet.z-a.z).dot(delta)/maxf(.000001,delta.length_squared()),0,1)
		var nearest := a.lerp(b,t)
		if absf(feet.y-nearest.y)<.24 and Vector2(feet.x-nearest.x,feet.z-nearest.z).length()<.18: return true
	return false

func _prepare(path: Dictionary) -> void:
	var spawn_distance := minf(2.5,float(path.length))
	if not _initial_preparation and is_instance_valid(view.exploration_camera()):
		spawn_distance = -1.0
		for i: int in range(2,29):
			var candidate := minf(float(i)*.5,float(path.length))
			var point := ExploreTransitNetwork.sample(path,candidate).origin
			if point.distance_to(walker.global_position)<.8: continue
			if not _spawn_visible(ExploreTransitNetwork.sample(path,candidate)):
				spawn_distance = candidate
				break
		if spawn_distance<0:
			_message = "Service is waiting for a clear approach."
			_retry_at = _elapsed+1.0
			return
	route_data = path
	world.build(path)
	train = ExploreTransitTrain.new()
	add_child(train)
	# Initial station preparation precedes Explore camera handoff. Later service
	# admits a train only on a connected approach outside the current view.
	distance = spawn_distance
	direction = -1
	stop_index = 0
	train.global_transform = ExploreTransitNetwork.sample(path,distance)
	_door_fraction = 0
	state = "approaching"
	speed = 0
	_message = "Train approaching. Wait behind the yellow edge."
	_reserve_path(path)

func _reserve_path(path: Dictionary) -> void:
	var reserved: Array[Vector2i] = []
	for id: Vector3i in path.nodes:
		if id.y==0: reserved.append(Vector2i(id.x,id.z))
	if view.get("traffic") != null and view.traffic.has_method("set_reserved_rail_cells"):
		view.traffic.set_reserved_rail_cells(reserved)

func _revalidate() -> void:
	var inputs := ExploreTransitNetwork.topology_signature(view.city)
	if inputs == _topology_inputs:
		# The route network is unchanged. The controller refreshes changed
		# building collisions; cabins, platforms and station IDs stay as they are.
		_revision = view.geometry_revision()
		network.revision = _revision
		for station_id: int in _choices.keys():
			if network.route(station_id,int(_choices[station_id])).is_empty(): _choices.erase(station_id)
		if is_instance_valid(world): world.refresh_visual_projection()
		return
	_topology_inputs = inputs
	if state == "driving":
		_refresh_manual_route()
		return
	var old := walker.global_position
	var riding := is_instance_valid(train) and train.contains(old)
	var in_transit := riding or (is_instance_valid(world) and world.contains(old))
	_retire()
	_graph.refresh()
	network.rebuild(view.city,_graph,view.geometry_revision())
	# Station IDs are rebuilt from current footprints; old numeric choices
	# must not silently select a different station or strand a new graph.
	_choices.clear()
	_revision = view.geometry_revision()
	if in_transit:
		var pose := traversal.safe_pose(Vector3(clampf(old.x,.1,127.9),maxf(old.y,0),clampf(old.z,.1,127.9)),0,[walker.get_rid()])
		if not pose.is_empty(): walker.place(pose.transform)
		_message = "The transit route changed. Service stopped; return to a station."

func refresh_geometry() -> void:
	if is_instance_valid(view) and view.geometry_revision()!=_revision: _revalidate()

func _refresh_manual_route() -> void:
	var from_anchor: Vector2i = network.station(int(route_data.from)).get("anchor",Vector2i(-1,-1)) if not route_data.is_empty() else Vector2i(-1,-1)
	var to_anchor: Vector2i = network.station(int(route_data.to)).get("anchor",Vector2i(-1,-1)) if not route_data.is_empty() else Vector2i(-1,-1)
	_graph.refresh()
	network.rebuild(view.city,_graph,view.geometry_revision())
	_revision = view.geometry_revision()
	_choices.clear()
	manual_route_invalidated = false
	if route_data.is_empty():
		for i: int in _manual_cells.size():
			var cell := _manual_cells[i]
			if not _graph.has_cell(cell,&"rail") or not _graph.point(cell,&"rail").is_equal_approx(_manual_points[i]): manual_route_invalidated = true
			if i>0 and not _graph.neighbors(_manual_cells[i-1],&"rail").has(cell): manual_route_invalidated = true
		return
	var from_id := -1
	var to_id := -1
	for station: Dictionary in network.stations:
		if station.anchor==from_anchor: from_id = station.id
		if station.anchor==to_anchor: to_id = station.id
	var updated := network.route(from_id,to_id)
	if updated.is_empty() or updated.points!=route_data.points:
		# The controller stops or recovers the occupied vehicle before its next
		# movement. Keep its current support until then.
		manual_route_invalidated = true
		return
	route_data = updated
	_station_id = from_id
	stop_index = 0
	world.build(updated)
	_reserve_path(updated)

func support_for(feet: Vector3) -> Dictionary:
	if is_instance_valid(train):
		var support := train.support_for(feet)
		if not support.is_empty(): return support
	return world.support_for(feet) if is_instance_valid(world) else {}

func contains(feet: Vector3) -> bool:
	return not support_for(feet).is_empty()

func recover_pose(_feet: Vector3) -> Dictionary:
	if _station_id>=0 and is_instance_valid(world):
		var station := network.station_for_route(route_data,_station_id)
		if not station.is_empty():
			var position: Vector3 = station.platform+Vector3.UP*.003
			var at := Transform3D(Basis.IDENTITY,position)
			var shape_at := at
			shape_at.origin.y += .0575
			if traversal.has_clearance(shape_at,ExploreActorProfile.shape(0),[walker.get_rid()]): return {"transform":at}
	return {}

func status() -> Dictionary:
	var passenger := is_instance_valid(train) and is_instance_valid(walker) and train.contains(walker.global_position)
	var station := network.station_for_route(route_data,_station_id) if network != null else {}
	var stopped := state in ["opening","boarding","closing"]
	var departure_direction := direction
	if stopped and not route_data.is_empty():
		if stop_index==0: departure_direction=1
		elif stop_index==route_data.stops.size()-1: departure_direction=-1
	var next_index := stop_index+departure_direction if stopped else stop_index
	var next := network.station_for_route(route_data,int(route_data.stops[clampi(next_index,0,route_data.stops.size()-1)].station)) if not route_data.is_empty() else {}
	var destination := network.station(int(route_data.to if departure_direction>0 else route_data.from)) if not route_data.is_empty() else {}
	var lift_prompt := world.elevator_prompt(walker.global_position) if is_instance_valid(world) and is_instance_valid(walker) else ""
	var message := _message
	match state:
		"opening": message="Doors opening. Wait until they are fully open."
		"boarding": message="Walk through the open doorway to board or leave."
		"closing": message="Doors closing. Please stand clear."
		"departing": message="Train departing. Please wait behind the yellow edge."
		"approaching", "braking": message="Train approaching. Wait behind the yellow edge."
	if _message.contains("another platform") and stopped: message=_message
	var occupied_lift := is_instance_valid(world) and is_instance_valid(walker) and world.in_elevator(walker.global_position)
	return {"active":state!="idle","station_id":_station_id,"station":station.get("name",""),
		"destination":destination.get("name",""),"next_stop":next.get("name",""),"doors":state,
		"current_stop":station.get("name","") if stopped else "","selected_destination":destination.get("id",-1),
		"can_choose_destination":not passenger and not occupied_lift,"transit_kind":"subway" if station.get("subway",false) else "train",
		"departure_seconds":maxi(0,ceili(ExploreTransitTrain.DWELL-_timer)) if state=="boarding" else -1,
		"doorway_blocked":is_instance_valid(train) and train.doorway_occupied(walker.global_position),
		"speed_mps":speed*16.0,"door_state":train.doors if is_instance_valid(train) else "closed",
		"message_literal":_unavailable_anchor!=Vector2i(-1,-1) and lift_prompt.is_empty() and message==_message,
		"message":lift_prompt if not lift_prompt.is_empty() else message,"elevator_prompt":lift_prompt,"interior":indoors(walker.global_position) if is_instance_valid(walker) else false,"passenger":passenger,"destinations":network.destinations(_station_id) if network != null and _station_id>=0 else [],
		"cabin_bounds":ExploreTransitTrain.CABIN,"cabin_transform":train.global_transform if is_instance_valid(train) else Transform3D.IDENTITY}

func indoors(feet: Vector3) -> bool:
	return (is_instance_valid(train) and train.contains(feet)) or (is_instance_valid(world) and world.indoors(feet))

func interact_elevator() -> bool:
	return is_instance_valid(world) and is_instance_valid(walker) and world.interact(walker)

func _retire(restore_physics: bool = true) -> void:
	_unavailable_anchor = Vector2i(-1,-1)
	if is_instance_valid(train): train.free()
	train = null
	if is_instance_valid(world): world.clear(restore_physics)
	route_data = {}
	state = "idle"
	speed = 0
	manual_route_invalidated = false
	_manual_cells.clear()
	_manual_points.clear()
	if is_instance_valid(view) and view.get("traffic") != null and view.traffic.has_method("set_reserved_rail_cells"):
		view.traffic.set_reserved_rail_cells([])

## restore_physics=false leaves station/portal cut-outs in the kept traversal
## world; the controller rebuilds it on the next entry.
func clear(restore_physics: bool = true) -> void:
	_retire(restore_physics)
	network = null
	names_revision = -1
	_unavailable_anchor = Vector2i(-1,-1)
	if is_instance_valid(world): world.free()
	world = null
	walker = null

func _exit_tree() -> void:
	clear()

## Driving uses the same validated tunnels and route as passenger service.
func prepare_drive_route(position: Vector3, subway: bool = true) -> Dictionary:
	var best := -1
	var gap := 8.0
	for station: Dictionary in network.stations:
		if bool(station.subway) != subway: continue
		var origin := Vector3(station.anchor.x+.5,station.surface,station.anchor.y+.5)
		var d := minf(origin.distance_to(position),station.platform.distance_to(position))
		if d<gap and not network.destinations(station.id).is_empty():
			best = station.id
			gap = d
	if best<0: return {}
	var destinations := network.destinations(best)
	var path := network.route(best,int(_choices.get(best,destinations[0].id)))
	if path.is_empty(): return {}
	_retire()
	route_data = path
	world.build(path)
	_station_id = best
	stop_index = 0
	state = "driving"
	_message = "Driving this train. Stop at a platform to leave."
	_reserve_path(path)
	return path.duplicate(true)

func begin_surface_drive_route(cells: Array) -> void:
	# A manually driven surface train owns its route instead of running
	# concurrently with the local passenger service on those same tracks.
	_retire()
	state = "driving"
	_message = "Driving this train. Stop beside clear ground to leave."
	var reserved: Array[Vector2i] = []
	for cell: Vector2i in cells: reserved.append(cell)
	_manual_cells = reserved.duplicate()
	_graph.refresh()
	for cell: Vector2i in _manual_cells: _manual_points.append(_graph.point(cell,&"rail"))
	if view.get("traffic") != null: view.traffic.set_reserved_rail_cells(reserved)

func end_drive_route() -> void:
	# Keep the platform/stairs supporting an alighting pedestrian. Preparing
	# the next service replaces this projection atomically on the next step.
	state = "idle"
	_message = "Passenger service is resuming."
	if view.get("traffic") != null: view.traffic.set_reserved_rail_cells([])

func _spawn_visible(at: Transform3D) -> bool:
	var camera: Camera3D = view.exploration_camera()
	if camera.is_position_in_frustum(at.origin+Vector3.UP*.12): return true
	for x: float in [-.14,.14]:
		for y: float in [0.0,.24]:
			for z: float in [-.34,.34]:
				if camera.is_position_in_frustum(at*Vector3(x,y,z)): return true
	return false
