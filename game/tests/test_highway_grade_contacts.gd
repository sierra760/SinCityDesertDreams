# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Samples highway pavement and collision between vertices on Valle del Mar's
## long straightaways, where traffic and physical floors must agree.
extends "res://tests/exploration/async_test_case.gd"
var fixture: Node3D
func after_each() -> void:
	if is_instance_valid(fixture):fixture.free()
	await physics_frame

func test_valle_straightaways_share_visible_traffic_and_physical_floors() -> void:
	var city: City = Sc2Import.load("res://assets/cities/Valle del Mar.sc2").city
	var encoded := var_to_bytes(SaveFormat.encode_city(city))
	var graph := CityTrafficGraph.new();graph.bind_city(city)
	var contacts := 0;var missing := 0;var error := .0;var clearance := INF
	var exclusions: Array[RID] = []
	for bounds: Rect2i in [Rect2i(82,98,12,30),Rect2i(6,116,9,12)]:
		fixture=Node3D.new();root.add_child(fixture)
		var layer := CityNetworks3D.new();fixture.add_child(layer)
		layer._prepare_bridge_decks(city);layer._build_region(city,bounds)
		var world := CityTraversalWorld3D.new();fixture.add_child(world)
		var chunks: Array[Dictionary] = [CityGeometry3D.build_chunk(city,bounds)]
		world.rebuild(city,chunks,layer.physical_data(),1)
		await physics_frame
		for cell: Vector2i in graph.cells(&"highway"):
			if not bounds.has_point(cell) or not NetworkShapes.is_highway(city.building.atv(cell)) or NetworkShapes.is_onramp(city.building.atv(cell)):continue
			var mask := CityNetworks3D.network_mask(city.building.atv(cell),NetworkShapes.Family.HIGHWAY)
			if mask not in [5,10]:continue
			for across: float in [.05,.28,.72,.95]:
				for step: int in 33:
					var along := (step+.37)/33.0
					var offset := Vector2(along,across) if mask==10 else Vector2(across,along)
					var traffic := graph.point(cell,&"highway",offset)
					var hit := world.support_near(traffic,.004,.006,exclusions)
					if hit.is_empty():missing+=1;continue
					contacts+=1;error=maxf(error,absf(hit.position.y-traffic.y))
					if not city.is_water(cell.x,cell.y):clearance=minf(clearance,hit.position.y-CityGeometry3D.visible_ground_height(city,cell,offset))
		fixture.free();await physics_frame
	print("VALLE_GRADE_CONTACTS contacts=%d missing=%d error=%.9f clearance=%.6f"%[contacts,missing,error,clearance])
	check_eq(contacts,10824,"82 highway tiles, four lane/edge strips and 33 samples each")
	check_eq(missing,0,"every lane sample has physical pavement")
	check_lt(error,.0015,"visible physical deck agrees with traffic between vertices")
	check_ge(clearance,.119,"solid underside stays clear of actual dry terrain")
	check_eq(var_to_bytes(SaveFormat.encode_city(city)),encoded,"projection leaves the city bytes unchanged")
