# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Oro Canyon's highway curves publish the same floor to traffic and Explore.
extends "res://tests/exploration/async_test_case.gd"

const Corners := preload("res://tests/test_highway_corner_layouts.gd")
var fixture: Node3D


func after_each() -> void:
	if is_instance_valid(fixture):fixture.free()
	await physics_frame


func test_every_oro_canyon_curve_has_matching_physical_lane_floors() -> void:
	var loaded := Sc2Import.load("res://assets/cities/Oro Canyon.sc2")
	check(loaded.ok,"supplied city imports")
	if not loaded.ok:return
	var city: City = loaded.city
	var encoded := var_to_bytes(SaveFormat.encode_city(city))
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var contacts := 0
	var missing := 0
	var maximum_error := .0
	var exclusions: Array[RID] = []
	for block: Array in Corners.ORO_BLOCKS:
		if block[2]==105:continue
		var anchor := Vector2i(block[0],block[1])
		var bounds := Rect2i(anchor,Vector2i(2,2))
		fixture = Node3D.new()
		root.add_child(fixture)
		var layer := CityNetworks3D.new()
		fixture.add_child(layer)
		layer._prepare_bridge_decks(city)
		layer._build_region(city,bounds)
		var world := CityTraversalWorld3D.new()
		fixture.add_child(world)
		var chunks: Array[Dictionary] = [CityGeometry3D.build_chunk(city,bounds)]
		world.rebuild(city,chunks,layer.physical_data(),1)
		await physics_frame
		for radius: float in [.28,.72,1.28,1.72]:
			for step: int in 65:
				var p := Corners.lane_point(anchor,block[2],radius,(step+.37)/65.0)
				var cell := Vector2i(floori(p.x),floori(p.y))
				var traffic := graph.point(cell,&"highway",p-Vector2(cell))
				var hit := world.support_near(traffic,.004,.006,exclusions)
				if hit.is_empty():missing+=1;continue
				contacts+=1
				maximum_error = maxf(maximum_error,absf(hit.position.y-traffic.y))
		fixture.free()
		await physics_frame
	check_eq(missing,0,"both lanes of both carriageways have real collision through every actual corner")
	check_eq(contacts,4680,"all eighteen curves sampled throughout all four lanes")
	check_lt(maximum_error,.0015,"rendered highway and physical floor stay aligned between vertices")
	check_eq(var_to_bytes(SaveFormat.encode_city(city)),encoded,"collision projection preserves the complete city payload")
	print("ORO_CONTACTS contacts=",contacts," missing=",missing," height_error=",maximum_error)
