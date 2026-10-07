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
var service: ExploreTransitService
var walker: ExplorePedestrian
var traversal: CityTraversalWorld3D

func _setup(subway := false) -> void:
	var city := Fixtures.subway_city() if subway else Fixtures.rail_city()
	view = SnapshotView.new()
	root.add_child(view)
	view.bind_city(city)
	view.traffic.bind_city(city)
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
	service = ExploreTransitService.new()
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
	service = null
	view = null
	await physics_frame

func test_ordinary_growth_retains_carriage_and_support_projection() -> void:
	await _setup(true)
	check(service._graph==view.traffic.graph,"already-owned traffic graph reused")
	var train_id := service.train.get_instance_id()
	var children: Array[int] = []
	for child in service.world.get_children(): children.append(child.get_instance_id())
	var old_route := service.route_data.duplicate(true)
	view.city.building.put(4,4,Buildings.TREES_1)
	view.city.traffic.put(20,20,200)
	view._geometry_revision += 1
	service.refresh_geometry()
	check_eq(service.train.get_instance_id(),train_id,"unrelated edit does not retire moving train")
	check_eq(service.route_data,old_route,"route stays identical")
	for i in children.size(): check_eq(service.world.get_child(i).get_instance_id(),children[i],"transit geometry retained")
	var snapshot := view.traversal_snapshot()
	var projected := service.world.apply_physical_projection(snapshot)
	var repeated := service.world.apply_physical_projection(snapshot)
	check_eq(projected,repeated,"repeat projection exactly cached")
	var stop := service.network.station_for_route(service.route_data,0)
	var lift_pose := ExploreTransitWorld3D.Elevator.pose_for(stop)
	var shaft := lift_pose*Vector3(.415,float(stop.surface)-lift_pose.origin.y,-.07)
	var plaza := lift_pose*Vector3(-.25,float(stop.surface)-lift_pose.origin.y,-.25)
	check(not _floor_at(projected.chunks[0].physical_floor_faces,shaft),"only enclosed shaft is removed from terrain")
	check(_floor_at(projected.chunks[0].physical_floor_faces,plaza),"solid exterior ground survives canonical refresh")
	check_eq(snapshot.chunks[0].physical_floor_faces,view.snapshot_chunks[0].physical_floor_faces,"source snapshot stays intact")
	traversal.rebuild(view.city,projected.chunks,projected.networks,view._geometry_revision)
	check(service.world.contains(service.network.stations[0].platform),"platform support remains live")

func test_real_rail_edit_still_retires_invalid_route() -> void:
	await _setup()
	view.city.building.put(25,20,Buildings.NONE)
	view._geometry_revision += 1
	service.refresh_geometry()
	check_eq(service.state,"idle")
	check(service.train==null)
	check(service.network.destinations(0).is_empty(),"removed rail invalidates actual connectivity")

func test_signature_covers_station_footprints_and_height_inputs() -> void:
	var city := Fixtures.rail_city()
	var before := ExploreTransitNetwork.topology_signature(city)
	city.traffic.put(20,20,200)
	city.building.put(4,4,Buildings.TREES_1)
	check(ExploreTransitNetwork.topology_signature(city)==before,"presentation-independent demand/building ignored")
	city.zone.put(20,21,city.zone.at(20,21)^Zones.CORNER_NW)
	check(ExploreTransitNetwork.topology_signature(city)!=before,"station anchor corner changes remain authoritative")
	city.zone.put(20,21,city.zone.at(20,21)^Zones.CORNER_NW)
	check(ExploreTransitNetwork.topology_signature(city)==before)
	city.flags.put(20,20,city.flags.at(20,20)^RotationMapper.AXIS_FLAG)
	check(ExploreTransitNetwork.topology_signature(city)!=before,"network orientation included")
	city.flags.put(20,20,city.flags.at(20,20)^RotationMapper.AXIS_FLAG)
	city.altitude.put(25,20,city.altitude.at(25,20)+1)
	check(ExploreTransitNetwork.topology_signature(city)!=before,"rail surface height included")

func test_projection_refreshes_changed_arrays_without_mutating_input() -> void:
	await _setup(true)
	var original := view.traversal_snapshot()
	var first := service.world.apply_physical_projection(original)
	var changed := original.duplicate(true)
	var floor_faces: PackedVector3Array = changed.chunks[0].physical_floor_faces
	floor_faces.append_array(PackedVector3Array([Vector3(17,0,17),Vector3(18,0,17),Vector3(17,0,18)]))
	changed.chunks[0].physical_floor_faces = floor_faces
	var updated := service.world.apply_physical_projection(changed)
	check_eq(updated.chunks[0].physical_floor_faces.size(),first.chunks[0].physical_floor_faces.size()+3,"new outside-cut floor survives refresh")
	check_eq(changed.chunks[0].physical_floor_faces.size(),original.chunks[0].physical_floor_faces.size()+3,"caller array remains canonical")

func _floor_at(faces: PackedVector3Array, point: Vector3) -> bool:
	for i: int in range(0,faces.size(),3):
		var hit: Variant=Geometry3D.ray_intersects_triangle(point+Vector3.UP*.1,Vector3.DOWN,faces[i],faces[i+1],faces[i+2])
		if hit!=null and absf(hit.y-point.y)<.1: return true
	return false
