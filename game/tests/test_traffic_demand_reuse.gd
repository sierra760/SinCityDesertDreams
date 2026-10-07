# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

class CountedGraph extends CityTrafficGraph:
	var demand_scans := 0
	func _local_demand(cell: Vector2i, tables: Array[PackedInt32Array] = []) -> Dictionary:
		demand_scans += 1
		return super._local_demand(cell, tables)

func _city() -> City:
	var city := flat_city()
	for x: int in range(15,36): city.building.put(x,25,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	city.stamp_building(22,24,Buildings.RES_1X1_FIRST)
	city.stamp_building(24,24,Buildings.COM_1X1_FIRST)
	return city

func _compare_fresh(graph: CityTrafficGraph, city: City) -> void:
	var fresh := CityTrafficGraph.new()
	fresh.bind_city(city)
	for field: String in ["developed","facilities","_nodes","_lists","_demand","_decks","_approaches"]:
		check_eq(graph.get(field),fresh.get(field),"current raw inputs match full graph: "+field)

func test_same_category_raw_upgrade_keeps_demand_and_geometry() -> void:
	var city := _city()
	var graph := CountedGraph.new()
	graph.bind_city(city)
	graph.center(Vector2i(22,25),&"road")
	var held: Dictionary = {}
	for field: String in ["_nodes","_lists","_demand","_decks","_approaches","_ground","_highway_stencils","_centers"]:
		held[field] = graph.get(field).duplicate(true)
	var revision := graph.revision
	graph.demand_scans = 0
	city.building.data[24*City.WIDTH+22] = Buildings.RES_1X1_FIRST+1
	check(graph.refresh(),"raw upgrade reports land-use change")
	check_eq(graph.demand_scans,0,"same-category upgrade performs no demand neighborhood scan")
	check_eq(graph.revision,revision,"upgrade retains topology revision")
	check_eq(graph.developed,2,"upgrade preserves developed count")
	check(not graph.facilities.has(Buildings.RES_1X1_FIRST),"old facility roster entry removed")
	check_eq(graph.facilities.get(Buildings.RES_1X1_FIRST+1),1,"new facility roster entry inserted")
	for field: String in held: check_eq(graph.get(field),held[field],"upgrade retains exact current cache: "+field)
	_compare_fresh(graph,city)

func test_category_change_spawn_removal_and_congestion_match_full_graph() -> void:
	var city := _city()
	var graph := CountedGraph.new()
	graph.bind_city(city)
	for code: int in [Buildings.COM_1X1_FIRST,Buildings.NONE,Buildings.IND_1X1_FIRST,Buildings.IND_1X1_FIRST+1]:
		city.building.data[24*City.WIDTH+22] = code
		city.traffic.data[25*City.WIDTH+22] = (int(city.traffic.data[25*City.WIDTH+22])+71)%256
		graph.refresh()
		_compare_fresh(graph,city)
	check_eq(graph.demand(Vector2i(22,25)).congestion,float(city.traffic_at(22,25))/255.0,"congestion remains current during same-category reuse")

func test_water_network_and_terrain_changes_keep_full_invalidation() -> void:
	var city := _city()
	var graph := CountedGraph.new()
	graph.bind_city(city)
	var revision := graph.revision
	city.terrain.put(22,24,Terrain.SURFACE)
	graph.refresh()
	check_gt(graph.revision,revision,"water changes invalidate graph geometry")
	_compare_fresh(graph,city)
	revision = graph.revision
	city.building.put(22,24,Buildings.RES_1X1_FIRST+1)
	graph.refresh()
	check_gt(graph.revision,revision,"wet lot upgrades retain full invalidation")
	_compare_fresh(graph,city)
	revision = graph.revision
	city.building.put(20,25,Buildings.NONE)
	graph.refresh()
	check_gt(graph.revision,revision,"network edits retain full invalidation")
	_compare_fresh(graph,city)
