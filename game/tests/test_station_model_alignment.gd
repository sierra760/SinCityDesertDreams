# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func _city_with_track(side: Vector2i, terminal := false) -> City:
	var city := flat_city()
	city.stamp_building(20,20,Buildings.RAIL_STATION,Zones.NONE)
	for n: int in range(20,23 if terminal else 24):
		var cell := Vector2i(19 if side.x<0 else 22,n) if side.x!=0 else Vector2i(n,19 if side.y<0 else 22)
		city.building.putv(cell,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,5 if side.x!=0 else 10))
	return city

func test_station_front_faces_real_track_on_all_four_sides() -> void:
	for side: Vector2i in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
		var city := _city_with_track(side)
		var before := SaveFormat.encode_city(city)
		var layer := CityBuildings3D.new()
		layer.rebuild(city)
		check_eq(layer.get_child_count(),1)
		var model: Node3D = layer.get_child(0)
		check((model.basis*Vector3.BACK).dot(Vector3(side.x,0,side.y))>.999,"station front follows connected track "+str(side))
		check_eq(model.get_meta("batch_region"),Rect2i(20,20,2,2))
		check_eq(SaveFormat.encode_city(city),before,"orientation never rotates stored city")
		layer.free()

func test_neighbor_edit_reorients_station_and_keeps_canonical_query() -> void:
	var city := _city_with_track(Vector2i.RIGHT,true)
	var layer := CityBuildings3D.new()
	root.add_child(layer)
	layer.rebuild(city)
	for y: int in range(20,23): city.building.put(22,y,0)
	for x: int in range(20,24): city.building.put(x,19,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
	layer.update_regions(city,null,[Rect2i(22,20,1,3),Rect2i(20,19,4,1)])
	var model: Node3D = layer.get_child(0)
	check((model.basis*Vector3.BACK).dot(Vector3.FORWARD)>.999,"neighbor rail edits reorient retained lot")
	check_eq(model.get_meta("cell"),Vector2i(20,20))
	check_eq(model.get_node("BuildingQuery").collision_layer,CityBuildings3D.QUERY_LAYER)
	layer.free()

func test_inaccessible_first_side_does_not_override_connected_station_front() -> void:
	var city := _city_with_track(Vector2i.RIGHT)
	# Row-major north track is valid rail but too high to reach this station.
	for x: int in range(20,24):
		city.building.put(x,19,NetworkShapes.shape_id(NetworkShapes.Family.RAIL,10))
		city.set_heights(x,19,8,0)
	var layer := CityBuildings3D.new()
	layer.rebuild(city)
	var model: Node3D = layer.get_child(0)
	check((model.basis*Vector3.BACK).dot(Vector3.RIGHT)>.999,"station selects accessible side regardless of first stored direction")
	layer.free()
