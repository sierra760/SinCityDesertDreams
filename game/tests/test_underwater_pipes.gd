# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"


func test_pipe_drags_cross_water_in_both_axes_and_directions() -> void:
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var city := flat_city()
		var start := Vector2i(50,50)
		var water_codes := [Terrain.SURFACE, Terrain.SUBMERGED, Terrain.SHORE | Terrain.SLOPE_W, Terrain.STREAM, Terrain.WATERFALL]
		for i in water_codes.size():
			var cell := start + direction * (i + 1)
			city.terrain.putv(cell,water_codes[i])
			city.set_heights(cell.x,cell.y,1,6)
		var terrain := city.terrain.data.duplicate()
		var altitude := city.altitude.data.duplicate()
		var buildings := city.building.data.duplicate()
		var builder := Builder.new(city,CityStats.new())
		var before := SaveFormat.encode_city(city)
		var quote := builder.preview(Tools.Kind.WATER_PIPE,start,start + direction * 6)
		check(quote.ok,quote.reason)
		check_eq(quote.tiles.size(),7,"drag reaches the opposite bank")
		check_eq(quote.cost,21,"seven ordinary pipe tiles")
		check_eq(SaveFormat.encode_city(city),before,"preview is read-only")
		var built := builder.apply(Tools.Kind.WATER_PIPE,start,start + direction * 6)
		check(built.applied)
		check_eq(city.funds,19979)
		for i in 7:
			var cell := start + direction * i
			check(city.conducts_water(cell.x,cell.y),"continuous pipe at %s" % cell)
		check_eq(city.terrain.data,terrain,"water and shore stay intact")
		check_eq(city.altitude.data,altitude,"no draining or terraforming")
		check_eq(city.building.data,buildings,"surface is untouched")


func test_single_underwater_pipe_obeys_funds_and_protected_land() -> void:
	var city := flat_city(2)
	city.terrain.put(50,50,Terrain.SUBMERGED)
	var builder := Builder.new(city,CityStats.new())
	var poor := builder.apply(Tools.Kind.WATER_PIPE,Vector2i(50,50))
	check_eq(poor.reason,Builder.REASON_FUNDS)
	check(not poor.applied)
	check_eq(city.underground.at(50,50),0)
	city.funds = 100
	city.set_flag(50,50,TileFlags.LANDMARK,true)
	var protected := builder.apply(Tools.Kind.WATER_PIPE,Vector2i(50,50))
	check_eq(protected.reason,"protected land")
	check(not protected.applied)
	city.set_flag(50,50,TileFlags.LANDMARK,false)
	check(builder.apply(Tools.Kind.WATER_PIPE,Vector2i(50,50)).applied)
	check_eq(city.funds,97)
	check(city.conducts_water(50,50))
	check(not builder.preview(Tools.Kind.WATER_PIPE,Vector2i(50,50)).ok,"existing pipe is not charged again")


func test_subway_still_stops_at_open_water() -> void:
	var city := flat_city()
	city.founded_year = 2000
	city.terrain.put(50,50,Terrain.SURFACE)
	var builder := Builder.new(city,CityStats.new())
	var quote := builder.preview(Tools.Kind.SUBWAY,Vector2i(50,50))
	check(not quote.ok)
	check_eq(quote.reason,"cannot dig under open water")
	check_eq(city.underground.at(50,50),0)


func test_underwater_pipe_supplies_far_bank_and_survives_save_and_repair() -> void:
	var city := flat_city(100000)
	city.stamp_building(10,10,Buildings.COAL_PLANT)
	city.stamp_building(14,10,Buildings.WATER_PUMP)
	city.stamp_building(20,10,Buildings.RES_1X1_FIRST)
	for x in range(16,19):
		city.terrain.put(x,10,Terrain.SUBMERGED)
		city.set_heights(x,10,1,4)
	var sim := make_simulation(city)
	sim.set_speed(GameClock.Speed.PAUSED)
	var builder := Builder.new(city,sim.stats,sim)
	check(not city.is_watered(20,10),"far bank starts disconnected")
	check(builder.apply(Tools.Kind.WATER_PIPE,Vector2i(15,10),Vector2i(19,10)).applied)
	check(city.is_watered(20,10),"water reaches the far bank")
	var restored := SaveFormat.decode_city(SaveFormat.encode_city(city))
	check_eq(restored.error,"")
	check_eq(restored.city.underground.data,city.underground.data)
	check_eq(restored.city.terrain.data,city.terrain.data)
	check(restored.city.is_watered(20,10),"saved crossing retains service")
	check(builder.apply(Tools.Kind.BULLDOZE,Vector2i(17,10),Vector2i(17,10),{"underground":true}).applied)
	check(not city.is_watered(20,10),"cutting the underwater pipe stops supply")
	check(city.is_open_water(17,10),"digging up a pipe preserves water")
	check(builder.apply(Tools.Kind.WATER_PIPE,Vector2i(17,10)).applied)
	check(city.is_watered(20,10),"repair restores service")
	sim._ctx.systems.clear()
	sim.systems.clear()
	sim._system_index.clear()
	sim.free()
