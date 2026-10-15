# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")

func service() -> RefCounted:
	var path := "res://scripts/sim/agricultural_parcel_service.gd"
	check(ResourceLoader.exists(path),"exact-member service implementation exists")
	return load(path).new() if ResourceLoader.exists(path) else null

func test_membership_access_not_empty_bounding_gap() -> void:
	var s := service()
	if s == null: return
	var c := flat_city()
	var m := F.mask([[20,20],[20,21],[20,22],[20,23],[20,24],[20,25],[20,26],[21,26],[22,26],[23,26],[24,26],[25,26],[26,26]])
	F.zone(c,m)
	c.building.put(26,20,Buildings.ROAD_FIRST)
	check(not s.has_access(c,m))
	c.building.put(19,23,Buildings.ROAD_FIRST)
	check(s.has_access(c,m))

func test_hole_and_other_customer_do_not_count_as_members() -> void:
	var s := service()
	if s == null: return
	var c := flat_city()
	var m := F.ring()
	F.zone(c,m)
	c.building.put(19,20,Buildings.ROAD_FIRST)
	c.stamp_building(21,21,Buildings.RES_1X1_FIRST,Zones.RES_LOW)
	var r := F.record(1,m,&"grain",&"active")
	check_eq(c.agricultural_parcels.put(c,r),OK)
	for i in m: c.flags.set_bits(i%128,i/128,TileFlags.WATERED,true)
	var ctx := make_context(c)
	var summary: Dictionary = s.summary(ctx,r,c)
	check(summary.water_supplied)
	check(summary.power_supplied)
	check_eq(summary.water_required,8)
	check_eq(summary.power_required,0)
	c.flags.set_bits(22,22,TileFlags.WATERED,false)
	check(not s.summary(ctx,r,c).water_supplied,"one missing actual member blocks all-member service")

func test_unserved_summary_counts_parcel_once() -> void:
	var c := flat_city()
	var m := F.ring()
	F.zone(c,m)
	check_eq(c.agricultural_parcels.put(c,F.record(1,m,&"grain",&"active")),OK)
	var ctx := make_context(c)
	var water := WaterSystem.new()
	water.reallocate_established(ctx,Rect2i(0,0,128,128))
	check_eq(water.network_summary().unwatered_buildings,1,"eight member loads are one unserved farm")
	check_eq(ctx.stats.water_demand,8)

func test_preview_detaches_members_store_and_existing_customer() -> void:
	var s := service()
	if s == null: return
	var c := flat_city()
	var m := F.ring()
	F.zone(c,m)
	var r := F.record(1,m)
	check_eq(c.agricultural_parcels.put(c,r),OK)
	c.stamp_building(21,21,Buildings.RES_1X1_FIRST,Zones.RES_LOW)
	var ctx := make_context(c)
	var before := var_to_bytes([c.building.data,c.flags.data,c.facilities,c.agricultural_parcels.to_dict(),ctx.rng.state()])
	for i in 3:
		var active := c.agricultural_parcels.record(1)
		active.state = &"active"
		active.modules = AgriculturalParcelGeometry.plan(active).modules
		var preview: City = s.project(ctx,active)
		check(preview != null)
		check_eq(preview.building_at(21,21),Buildings.RES_1X1_FIRST)
		for index in m: check_eq(preview.building.data[index],284)
		check_eq(preview.agricultural_parcels.record(1).state,&"active")
	check_eq(var_to_bytes([c.building.data,c.flags.data,c.facilities,c.agricultural_parcels.to_dict(),ctx.rng.state()]),before)

func supplied_farm() -> Dictionary:
	var c := flat_city()
	var m := F.mask([[20,20]])
	F.zone(c,m)
	c.stamp_building(16,16,Buildings.SOLAR_PLANT)
	c.add_facility(Vector2i(16,16),{"key":Buildings.key(Buildings.SOLAR_PLANT),"capacity":1})
	c.stamp_building(20,19,Buildings.WATER_PUMP)
	c.add_facility(Vector2i(20,19),{"key":Buildings.key(Buildings.WATER_PUMP),"output":1})
	c.building.put(19,19,Buildings.POWER_LINE_FIRST)
	c.building.put(19,20,Buildings.ROAD_FIRST)
	var r := F.record(1,m,&"grain",&"active")
	r.target_area = 4
	check_eq(c.agricultural_parcels.put(c,r),OK)
	var ctx := make_context(c)
	var power := PowerSystem.new()
	var water := WaterSystem.new()
	var ag := AgricultureSystem.new()
	ctx.systems = {&"power":power,&"water":water,&"agriculture":ag}
	power.reallocate_established(ctx,Rect2i(0,0,128,128))
	water.reallocate_established(ctx,Rect2i(0,0,128,128))
	ag.setup(ctx)
	return {"city":c,"ctx":ctx,"ag":ag,"power":power,"water":water}

func test_failed_active_extension_keeps_existing_farm_healthy() -> void:
	var f := supplied_farm()
	check(f.city.is_watered(20,20),"fixture has actual powered pumping")
	F.zone(f.city,F.mask([[21,20],[22,20],[23,20]]))
	var original: Dictionary = f.city.agricultural_parcels.record(1)
	f.ag.monthly(f.ctx,0)
	var after: Dictionary = f.city.agricultural_parcels.record(1)
	check_eq(after.members,original.members,"unserved new acreage stays detached")
	check_eq(after.modules,original.modules)
	check_eq(after.state,&"active")
	check_eq(after.failed_months,0)
	check_eq(after.last_month,0)
	check(f.city.is_watered(20,20))
	check(f.ag.projection_count() <= 33)
	f.ctx.systems.clear()

func test_preview_reallocates_pump_power_and_preserves_live_policy() -> void:
	var s := service()
	if s == null: return
	var f := supplied_farm()
	var r: Dictionary = f.city.agricultural_parcels.record(1)
	var preview: City = s.project(f.ctx,r)
	check(preview.is_powered(20,19))
	check(s.summary(f.ctx,r,preview).water_supplied)
	f.city.facility(Vector2i(16,16)).capacity = 0
	var before := var_to_bytes([f.city.flags.data,f.city.facilities,f.ctx.rng.state(),f.power.save(),f.water.save(),f.power.network_summary(),f.water.network_summary(),f.ag.save()])
	for n in 3:
		preview = s.project(f.ctx,r)
		check(not preview.is_powered(20,19),"stale pump power is not a supply source")
		check(not s.summary(f.ctx,r,preview).water_supplied)
	check_eq(var_to_bytes([f.city.flags.data,f.city.facilities,f.ctx.rng.state(),f.power.save(),f.water.save(),f.power.network_summary(),f.water.network_summary(),f.ag.save()]),before)
	f.ctx.systems.clear()

func test_active_cell_loads_and_empty_states() -> void:
	for row in [[282,3],[283,3],[284,1],[285,1],[286,1],[287,0],[288,0]]:
		check_eq(UtilityParams.water_load(row[0]),row[1])
		check_eq(UtilityParams.power_load(row[0]),0)

func test_preparation_conduction_is_in_final_activation_allocation() -> void:
	var c := flat_city()
	c.stamp_building(16,15,Buildings.SOLAR_PLANT)
	c.add_facility(Vector2i(16,15),{"key":Buildings.key(Buildings.SOLAR_PLANT),"capacity":20})
	c.stamp_building(20,18,Buildings.WATER_PUMP)
	c.add_facility(Vector2i(20,18),{"key":Buildings.key(Buildings.WATER_PUMP),"output":1})
	c.building.put(19,18,Buildings.POWER_LINE_FIRST)
	# Water currently reaches only the waiting farm via the south pipe.
	for y in [19,20]: c.underground.put(20,y,15)
	var pending := F.mask([[20,21]])
	var established := F.mask([[22,18]])
	F.zone(c,pending)
	F.zone(c,established)
	F.zone(c,F.mask([[21,18]]))
	check_eq(c.agricultural_parcels.put(c,F.record(1,pending)),OK)
	var old := F.record(2,established,&"grain",&"active")
	old.target_area = 1
	check_eq(c.agricultural_parcels.put(c,old),OK)
	c.building.put(19,21,Buildings.ROAD_FIRST)
	c.building.put(21,17,Buildings.ROAD_FIRST)
	var ctx := make_context(c,7)
	var power := PowerSystem.new()
	var water := WaterSystem.new()
	var ag := AgricultureSystem.new()
	ctx.systems = {&"power":power,&"water":water,&"agriculture":ag}
	power.reallocate_established(ctx,Rect2i(0,0,128,128))
	water.reallocate_established(ctx,Rect2i(0,0,128,128))
	ag.setup(ctx)
	ag.monthly(ctx,0)
	check(c.agricultural_parcels.id_at(Vector2i(21,18)) != 0,"new preparation bridges the earlier customer")
	check_eq(c.agricultural_parcels.record(1).state,&"prepared","final allocation includes new zero-load conduits")
	for r in ag.current_parcels():
		if r.state == &"active" and r.id != 2:
			check(load("res://scripts/sim/agricultural_parcel_service.gd").all_members_served(c,r.members,TileFlags.WATERED))
	ctx.systems.clear()

func test_retained_ring_activation_has_real_member_supply_and_no_hole_load() -> void:
	var c := flat_city()
	var m := F.ring()
	F.zone(c,m)
	c.stamp_building(14,16,Buildings.SOLAR_PLANT)
	c.add_facility(Vector2i(14,16),{"key":Buildings.key(Buildings.SOLAR_PLANT),"capacity":10})
	c.stamp_building(19,20,Buildings.WATER_PUMP)
	c.add_facility(Vector2i(19,20),{"key":Buildings.key(Buildings.WATER_PUMP),"output":8})
	c.building.put(18,19,Buildings.POWER_LINE_FIRST)
	c.building.put(19,19,Buildings.POWER_LINE_FIRST)
	c.building.put(20,19,Buildings.ROAD_FIRST)
	c.building.put(21,21,Buildings.ROAD_FIRST)
	var r := F.record(1,m)
	r.target_area = 8
	check_eq(c.agricultural_parcels.put(c,r),OK)
	var ctx := make_context(c)
	var power := PowerSystem.new()
	var water := WaterSystem.new()
	var ag := AgricultureSystem.new()
	ctx.systems = {&"power":power,&"water":water,&"agriculture":ag}
	power.reallocate_established(ctx,Rect2i(0,0,128,128))
	water.reallocate_established(ctx,Rect2i(0,0,128,128))
	ag.setup(ctx)
	var before_rng := ctx.rng.state()
	ag.monthly(ctx,0)
	check_eq(c.agricultural_parcels.record(1).state,&"active")
	check_eq(c.agricultural_parcels.record(1).members,m)
	check(load("res://scripts/sim/agricultural_parcel_service.gd").all_members_served(c,m,TileFlags.WATERED))
	check_eq(water.network_summary().unwatered_buildings,1,"disconnected solar lot is the sole unserved consumer")
	check_eq(ctx.stats.water_demand,24,"sixteen existing solar cells plus eight actual farm members")
	check_eq(c.building_at(21,21),Buildings.ROAD_FIRST)
	check(not c.is_watered(21,21))
	check_eq(ctx.rng.state(),before_rng)
	ctx.systems.clear()
