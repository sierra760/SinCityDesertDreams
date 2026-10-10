# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## These fixtures catch lost building conduits, pipe-to-lot attachments,
## stale service colors and failed construction/disconnection/save wiring.
func vertices_in(renderer: CityUnderground3D, cell: Vector2i) -> PackedVector3Array:
	var found := PackedVector3Array()
	if renderer.mesh_instance.mesh == null or renderer.mesh_instance.mesh.get_surface_count() == 0: return found
	var vertices: PackedVector3Array = renderer.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for p in vertices:
		if p.x > cell.x and p.x < cell.x + 1 and p.z > cell.y and p.z < cell.y + 1: found.append(p)
	return found


func test_developed_lots_and_facilities_remain_visible_underground() -> void:
	var city := flat_city()
	city.stamp_building(10,10,Buildings.WATER_PUMP)
	city.stamp_building(12,10,Buildings.WATER_TOWER)
	city.stamp_building(16,10,Buildings.WATER_TREATMENT)
	city.stamp_building(20,10,Buildings.DESALINATION)
	city.stamp_building(25,10,Buildings.RES_1X1_FIRST)
	city.stamp_building(26,10,Buildings.RES_1X1_FIRST)
	city.building.put(30,10,Buildings.ROAD_FIRST)
	city.zone.put(31,10,Zones.make(Zones.RES_LOW))
	var ctx := make_context(city)
	WaterSystem.new().setup(ctx)
	var renderer := CityUnderground3D.new()
	var saved := SaveFormat.encode_city(city)
	renderer.bind_city(city)
	for cell: Vector2i in [Vector2i(10,10),Vector2i(12,10),Vector2i(13,11),Vector2i(16,10),Vector2i(20,10),Vector2i(25,10),Vector2i(26,10)]:
		check_gt(vertices_in(renderer,cell).size(),0,"every water-conducting tile has an underground projection at %s" % cell)
	check_eq(vertices_in(renderer,Vector2i(30,10)).size(),0,"roads have no automatic water conduit")
	check_eq(vertices_in(renderer,Vector2i(31,10)).size(),0,"undeveloped zones have no automatic water conduit")
	check_eq(SaveFormat.encode_city(city),saved,"projection preserves city data")
	renderer.free()


func test_pipe_endpoint_visibly_meets_adjacent_water_facility_without_rewriting_save() -> void:
	var city := flat_city()
	city.stamp_building(10,10,Buildings.WATER_PUMP)
	city.underground.put(11,10,2) # Legacy endpoint points east, missing the pump to its west.
	city.underground.put(12,10,8)
	var ctx := make_context(city)
	WaterSystem.new().setup(ctx)
	var before := SaveFormat.encode_city(city)
	var renderer := CityUnderground3D.new()
	renderer.bind_city(city)
	var west_attachment := false
	var vertices: PackedVector3Array = renderer.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for p in vertices:
		if is_equal_approx(p.x,11.0) and p.z > 10.4 and p.z < 10.6: west_attachment = true
	check(west_attachment,"pipe reaches the shared edge with its adjacent pump")
	check_eq(SaveFormat.encode_city(city),before,"legacy endpoint stays byte exact in storage")
	renderer.free()


func test_building_growth_removal_and_service_refresh_the_cached_projection() -> void:
	var city := flat_city()
	city.underground.put(10,10,10)
	var renderer := CityUnderground3D.new()
	renderer.bind_city(city)
	var builds := renderer.rebuild_count
	city.stamp_building(11,10,Buildings.RES_1X1_FIRST)
	renderer.refresh()
	check_eq(renderer.rebuild_count,builds+1,"new conducting building invalidates the mesh")
	check_gt(vertices_in(renderer,Vector2i(11,10)).size(),0)
	city.set_flag(11,10,TileFlags.WATERED,true)
	renderer.refresh()
	var arrays: Array = renderer.mesh_instance.mesh.surface_get_arrays(0)
	var wet_lot := false
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
		var color: Color = arrays[Mesh.ARRAY_COLOR][i]
		if p.x > 11.0 and p.x < 12.0 and p.z > 10.0 and p.z < 11.0 and color.b > color.r: wet_lot = true
	check(wet_lot,"watered developed lot becomes blue")
	city.clear_footprint(11,10)
	renderer.refresh()
	check_eq(vertices_in(renderer,Vector2i(11,10)).size(),0,"removed building retires its implicit conduit")
	check_eq(renderer.rebuild_count,builds+3)
	renderer.free()


func test_explicit_pipe_beneath_an_isolated_building_keeps_its_endpoints() -> void:
	var city := flat_city()
	city.stamp_building(10,10,Buildings.RES_1X1_FIRST)
	city.underground.put(10,10,5)
	var renderer := CityUnderground3D.new()
	renderer.bind_city(city)
	var north := false
	var south := false
	var vertices: PackedVector3Array = renderer.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for p in vertices:
		if p.x > 10.4 and p.x < 10.6:
			if is_equal_approx(p.z,10): north = true
			if is_equal_approx(p.z,11): south = true
	check(north and south,"implicit building conduit does not hide an explicit pipe beneath it")
	renderer.free()


func test_real_builder_connects_cuts_rejoins_and_saves_water_service() -> void:
	var city := flat_city(100000)
	city.stamp_building(10,10,Buildings.COAL_PLANT)
	city.stamp_building(14,10,Buildings.WATER_PUMP)
	city.stamp_building(20,10,Buildings.RES_1X1_FIRST)
	city.building.put(17,10,Buildings.ROAD_FIRST)
	var sim := make_simulation(city)
	sim.set_speed(GameClock.Speed.PAUSED)
	var builder := Builder.new(city,sim.stats,sim)
	var surface := city.building.data.duplicate()
	var funds := city.funds
	var quote := builder.preview(Tools.Kind.WATER_PIPE,Vector2i(15,10),Vector2i(19,10))
	check(quote.ok and quote.cost > 0)
	check_eq(city.funds,funds,"preview is free")
	check(builder.apply(Tools.Kind.WATER_PIPE,Vector2i(15,10),Vector2i(19,10)).applied)
	check_eq(city.funds,funds-int(quote.cost))
	check(city.is_watered(20,10),"pipe reaches the house across the road")
	check_eq(city.building.data,surface,"pipes preserve the surface city")
	check(builder.apply(Tools.Kind.BULLDOZE,Vector2i(17,10),Vector2i(17,10),{"underground":true}).applied)
	check(not city.is_watered(20,10),"cutting the pipe stops supply immediately")
	check_eq(city.building.data,surface,"underground bulldoze preserves the road")
	check(builder.apply(Tools.Kind.WATER_PIPE,Vector2i(17,10)).applied)
	check(city.is_watered(20,10),"rejoining restores supply immediately")
	var restored := SaveFormat.decode_city(SaveFormat.encode_city(city))
	check_eq(restored.error,"")
	check_eq(restored.city.underground.data,city.underground.data)
	check(restored.city.is_watered(20,10),"save retains water service")
	sim._ctx.systems.clear()
	sim.systems.clear()
	sim._system_index.clear()
	sim.free()
