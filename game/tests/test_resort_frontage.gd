# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Gaming resorts turn their main entrance toward an adjacent street when the
## authored front has none, both when a city's view is built and after a
## street edit; the Explore door follows the visible front.
extends "res://tests/exploration/async_test_case.gd"

const Access := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")
const ANCHOR := Vector2i(20,18)
const ROAD := Buildings.ROAD_FIRST
const LOT := Rect2i(ANCHOR,Vector2i(4,4))

func _city(streets: Array, code: int = Buildings.ARCOLOGY_JUNCTION) -> City:
	var city := flat_city()
	city.stamp_building(ANCHOR.x,ANCHOR.y,code)
	for cell: Vector2i in streets: city.building.putv(cell,ROAD)
	return city

func _resort_model(view: CityView3D) -> Node3D:
	for child: Node in view.buildings.get_children():
		if Buildings.is_arcology(int(child.get_meta("code",0))): return child
	return null

func test_front_turns_only_when_its_side_has_no_street() -> void:
	var south: Array[Vector2i] = [Vector2i(21,22)]
	var east: Array[Vector2i] = [Vector2i(24,19),Vector2i(24,20)]
	var west: Array[Vector2i] = [Vector2i(19,18)]
	var north: Array[Vector2i] = [Vector2i(20,17),Vector2i(21,17),Vector2i(22,17)]
	check_eq(CityBuildings3D.resort_yaw(_city([]),LOT),0.0,"no street keeps the authored front")
	check_eq(CityBuildings3D.resort_yaw(_city(south+east+north),LOT),0.0,"a street at the authored front keeps it")
	check_eq(CityBuildings3D.resort_yaw(_city(east),LOT),PI/2.0,"east street turns the front east")
	check_eq(CityBuildings3D.resort_yaw(_city(west),LOT),-PI/2.0,"west street turns the front west")
	check_eq(CityBuildings3D.resort_yaw(_city(north),LOT),PI,"north street turns the front north")
	check_eq(CityBuildings3D.resort_yaw(_city(west+north),LOT),PI,"the side with more street wins")
	check_eq(CityBuildings3D.resort_yaw(_city(east+[Vector2i(19,18),Vector2i(19,19)]),LOT),PI/2.0,"ties prefer east")
	check_eq(CityBuildings3D.resort_yaw(_city([Vector2i(24,22),Vector2i(19,17)]),LOT),0.0,"diagonal corners are not adjacent")
	var buried := _city([])
	buried.building.putv(Vector2i(24,19),Buildings.TUNNEL_FIRST)
	buried.building.putv(Vector2i(24,20),Buildings.HIGHWAY_FIRST)
	check_eq(CityBuildings3D.resort_yaw(buried,LOT),0.0,"tunnels and highways are not frontage")

func test_view_turns_the_model_on_load_and_after_a_street_edit() -> void:
	var city := _city([])
	var view := CityView3D.new()
	root.add_child(view)
	view.bind_city(city)
	view.buildings.rebuild(city,view.catalog)
	var model := _resort_model(view)
	check(model != null,"resort projected")
	if model != null: check_eq(model.rotation.y,0.0,"no street: authored facing")
	city.building.putv(Vector2i(24,20),ROAD)
	view.buildings.update_regions(city,view.catalog,[Rect2i(24,20,1,1)])
	model = _resort_model(view)
	check(model != null,"resort reprojected")
	if model != null: check(is_equal_approx(model.rotation.y,PI/2.0),"street edit turns the entrance east")
	var loaded := _city([Vector2i(21,17)])
	view.bind_city(loaded)
	view.buildings.rebuild(loaded,view.catalog)
	model = _resort_model(view)
	if model != null: check(is_equal_approx(model.rotation.y,PI),"loaded city faces its north street")
	view.free()

func test_explore_door_follows_the_turned_front() -> void:
	for code: int in [Buildings.ARCOLOGY_COMSTOCK,Buildings.ARCOLOGY_ORBIT]:
		var front := 3.87 if code == Buildings.ARCOLOGY_ORBIT else 3.75
		var east: Array[Vector2i] = [Vector2i(24,19),Vector2i(24,20)]
		var city := _city(east,code)
		var pose := Access.threshold(city,ANCHOR)
		var label := str(code)
		check(is_equal_approx(pose.origin.x,ANCHOR.x+front),label+": threshold at the east front")
		check(is_equal_approx(pose.origin.z,ANCHOR.y+2.0),label+": threshold centred on that side")
		check((pose.basis*Vector3.FORWARD).is_equal_approx(Vector3(-1,0,0)),label+": faces west into the building")
		check_eq(Access.nearby(city,pose.origin+Vector3(.1,.002,.2)).get("anchor",Vector2i(-1,-1)),ANCHOR,label+": door found at the east front")
		check(Access.nearby(city,Vector3(ANCHOR.x+2.0,pose.origin.y,ANCHOR.y+3.75)).is_empty(),label+": the unused south side has no door")
	var west: Array[Vector2i] = [Vector2i(19,20)]
	var north: Array[Vector2i] = [Vector2i(22,17)]
	var west_pose := Access.threshold(_city(west),ANCHOR)
	check(is_equal_approx(west_pose.origin.x,ANCHOR.x+.25),"west threshold inside the west edge")
	check((west_pose.basis*Vector3.FORWARD).is_equal_approx(Vector3(1,0,0)),"west threshold faces east")
	var north_pose := Access.threshold(_city(north),ANCHOR)
	check(is_equal_approx(north_pose.origin.z,ANCHOR.y+.25),"north threshold inside the north edge")
	check((north_pose.basis*Vector3.FORWARD).is_equal_approx(Vector3(0,0,1)),"north threshold faces south")
	check_eq(Access.nearby(_city(north),north_pose.origin+Vector3(0,.002,-.3)).get("anchor",Vector2i(-1,-1)),ANCHOR,"north door reachable from the street side")
