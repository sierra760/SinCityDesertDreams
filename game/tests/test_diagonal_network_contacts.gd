# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

var fixture: Node3D

func after_each() -> void:
	if is_instance_valid(fixture):fixture.free()
	await physics_frame

func test_diagonal_road_and_rail_floor_contacts_match_terrain_and_traffic() -> void:
	var starts := [Vector2(.5,0),Vector2(1,.5),Vector2(.5,1),Vector2(0,.5)]
	var ends := [Vector2(1,.5),Vector2(.5,1),Vector2(0,.5),Vector2(.5,0)]
	var contacts := 0
	for family: int in [NetworkShapes.Family.ROAD,NetworkShapes.Family.RAIL]:
		for terrain: int in [Terrain.FLAT,Terrain.CORNER_NE,1,3]:
			for quarter: int in 4:
				var city := flat_city();var cell := Vector2i(20,20)
				city.terrain.putv(cell,terrain)
				city.building.putv(cell,NetworkShapes.shape_id(family,[3,6,12,9][quarter]))
				var before := var_to_bytes(SaveFormat.encode_city(city))
				fixture=Node3D.new();root.add_child(fixture)
				var layer := CityNetworks3D.new();fixture.add_child(layer)
				layer._build_region(city,Rect2i(cell,Vector2i.ONE))
				var world := CityTraversalWorld3D.new();fixture.add_child(world)
				var chunks: Array[Dictionary] = [CityGeometry3D.build_chunk(city,Rect2i(cell,Vector2i.ONE))]
				world.rebuild(city,chunks,layer.physical_data(),1)
				var graph := CityTrafficGraph.new();graph.bind_city(city)
				await physics_frame
				for step: int in 17:
					var offset: Vector2 = starts[quarter].lerp(ends[quarter],(step+.5)/17.0)
					var at := graph.point(cell,&"road" if family==NetworkShapes.Family.ROAD else &"rail",offset)
					var exclusions: Array[RID] = []
					var hit := world.support_near(at,.004,.006,exclusions)
					check(not hit.is_empty(),"straight diagonal has real collision on flat/sloped ground")
					if not hit.is_empty():
						check(absf(hit.position.y-at.y)<.0001,"physical floor matches vehicle running height")
						contacts+=1
				check_eq(var_to_bytes(SaveFormat.encode_city(city)),before,"contact projection preserves save payload")
				fixture.free();await physics_frame
	check_eq(contacts,544,"all diagonal road/rail contact samples retained")

func test_alternating_diagonal_pieces_have_continuous_floor_across_tile_joins() -> void:
	for family: int in [NetworkShapes.Family.ROAD,NetworkShapes.Family.RAIL]:
		var city := flat_city();var bounds := Rect2i(20,20,5,5)
		for step: int in 4:
			city.building.put(20+step,20+step,NetworkShapes.shape_id(family,3))
			city.building.put(21+step,20+step,NetworkShapes.shape_id(family,12))
		fixture=Node3D.new();root.add_child(fixture)
		var layer := CityNetworks3D.new();fixture.add_child(layer);layer._build_region(city,bounds)
		var world := CityTraversalWorld3D.new();fixture.add_child(world)
		var chunks: Array[Dictionary] = [CityGeometry3D.build_chunk(city,bounds)]
		world.rebuild(city,chunks,layer.physical_data(),1)
		await physics_frame
		var exclusions: Array[RID] = []
		for step: int in 129:
			var p := Vector2(20.5,20)+Vector2.ONE*(step/32.0)
			var at := Vector3(p.x,4*CityGeometry3D.HEIGHT+(.04 if family==NetworkShapes.Family.ROAD else .055),p.y)
			var hit := world.support_near(at,.004,.006,exclusions)
			check(not hit.is_empty(),"alternating diagonal tiles meet along one straight physical corridor")
		fixture.free();await physics_frame
