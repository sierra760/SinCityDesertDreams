# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

var contexts: Array[SimContext] = []

func after_each() -> void:
	for ctx in contexts: ctx.systems.clear()
	contexts.clear()

func fixture(key: StringName = &"arcology_afterglow") -> SimContext:
	var city := flat_city()
	city.stamp_building(10,10,Buildings.id_of(key))
	city.stamp_building(9,10,Buildings.WATER_PUMP)
	city.set_flag(9,10,TileFlags.POWERED,true)
	city.stamp_building(6,6,Buildings.COAL_PLANT)
	for y in range(7,11): city.building.put(10,y,Buildings.POWER_LINE_FIRST)
	city.stamp_building(10,10,Buildings.id_of(key))
	city.building.put(10,9,Buildings.ROAD_FIRST)
	var ctx := make_context(city)
	contexts.append(ctx)
	var tourism := TourismSystem.new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	TourismFixture.set_served(city,Vector2i(10,10),true,true)
	check_eq(tourism.finish_restore({}),OK)
	var power := PowerSystem.new()
	var water := WaterSystem.new()
	ctx.systems[&"power"] = power
	ctx.systems[&"water"] = water
	power.setup(ctx)
	city.set_flag(9,10,TileFlags.POWERED,true)
	water.setup(ctx)
	return ctx

func attend(ctx: SimContext, guests: int, days: int = 0) -> void:
	var tourism := ctx.system(&"tourism") as TourismSystem
	var rows := tourism._state.records()
	rows[0].guests = guests
	rows[0].day_visitors = days
	rows[0].operating = true
	TourismFixture.segment_rows(rows)
	check_eq(tourism._state.replace_records(rows),OK)
	tourism._publish()

func test_occupied_load_reaches_real_allocator_and_summary() -> void:
	var ctx := fixture()
	var power := ctx.system(&"power") as PowerSystem
	var water := ctx.system(&"water") as WaterSystem
	var empty_power := ctx.stats.power_demand
	var empty_water := ctx.stats.water_demand
	attend(ctx,80)
	ctx.city.facility(Vector2i(9,10))["output"] = 100
	var full := Rect2i(0,0,City.WIDTH,City.HEIGHT)
	power.reallocate_established(ctx,full)
	ctx.city.set_flag(9,10,TileFlags.POWERED,true)
	water.reallocate_established(ctx,full)
	check_eq(ctx.stats.power_demand,empty_power+3,"80 premium guests consume three power units")
	check_eq(ctx.stats.water_demand,empty_water+6,"80 premium guests consume six water units")
	check_eq(water.consumed(),38,"six visitor units plus resort and coal baseline loads")
	check_eq(water.network_summary().demand,ctx.stats.water_demand)

func test_same_count_different_tier_changes_real_water_consumption() -> void:
	var budget := fixture(&"arcology_last")
	var premium := fixture()
	for ctx in [budget,premium]:
		attend(ctx,80)
		ctx.city.facility(Vector2i(9,10))["output"] = 100
		ctx.city.set_flag(9,10,TileFlags.POWERED,true)
		(ctx.system(&"water") as WaterSystem).reallocate_established(ctx,Rect2i(0,0,128,128))
	check_eq(premium.stats.water_demand-budget.stats.water_demand,2,"same sixteen baseline tiles, different accepted visitor tier")

func test_preflight_and_detached_projection_include_accepted_visitors() -> void:
	var ctx := fixture(&"com_corner_store")
	ctx.city.clear_footprint(6,6)
	ctx.systems.erase(&"power")
	attend(ctx,0,24)
	var water := ctx.system(&"water") as WaterSystem
	ctx.city.facility(Vector2i(9,10))["output"] = 1
	ctx.city.set_flag(9,10,TileFlags.POWERED,true)
	check(not water.can_supply_lot(ctx.city,Rect2i(10,10,1,1),1),"baseline fits but accepted visitor demand does not")
	var projected := AgriculturalParcelService.project(ctx)
	check(not projected.is_watered(10,10),"detached agriculture trial competes with the same accepted load")

func test_restored_summaries_rebuild_load_without_time_or_storage_tick() -> void:
	var ctx := fixture()
	attend(ctx,80)
	var power := ctx.system(&"power") as PowerSystem
	var water := ctx.system(&"water") as WaterSystem
	var before := var_to_bytes([ctx.city.flags.data,ctx.city.facilities,ctx.rng.state()])
	ctx.city.restored_layers["flags"] = true
	var restored_power := PowerSystem.new()
	restored_power.setup_from_save(ctx,power.save())
	var restored_water := WaterSystem.new()
	restored_water.setup(ctx)
	restored_water.load(water.save())
	check_eq(restored_power.network_summary().demand,20)
	check_eq(restored_water.network_summary().demand,38)
	check_eq(var_to_bytes([ctx.city.flags.data,ctx.city.facilities,ctx.rng.state()]),before)

const Rotated := preload("res://tests/test_rotated_footprints.gd")

func sum_units(values: PackedInt32Array) -> int:
	var result := 0
	for value in values: result += value
	return result

func test_fractional_guest_and_day_requests_round_together_once() -> void:
	for entry in [[&"arcology_boddy",100],[&"arcology_comstock",125],[&"arcology_afterglow",150]]:
		var row := {"key":entry[0],"guests":1,"day_visitors":1}
		check_eq(TourismUtilities.request(row,false),1,"two fractional requests do not each round up")
		check_eq(TourismUtilities.request(row,true),1)
		row.guests = 80
		row.day_visitors = 80
		check_eq(TourismUtilities.request(row,false),[3,4,5][[100,125,150].find(entry[1])])
		check_eq(TourismUtilities.request(row,true),[6,8,9][[100,125,150].find(entry[1])])
	row_request_boundaries()

func row_request_boundaries() -> void:
	var row := {"key":&"arcology_boddy","guests":20,"day_visitors":0}
	check_eq(TourismUtilities.request(row,true),1)
	row.guests = 21
	check_eq(TourismUtilities.request(row,true),2)
	row.guests = 40
	check_eq(TourismUtilities.request(row,false),1)
	row.day_visitors = 1
	check_eq(TourismUtilities.request(row,false),2)
	row.operating = false
	check_eq(TourismUtilities.request(row,false),0)

func test_all_venues_rotated_imported_footprints_conserve_requests_without_metadata() -> void:
	var keys := RewardParams.ARCOLOGIES.keys()
	keys.append(&"com_corner_store")
	for turn in 4:
		var city := flat_city()
		var rows: Array = []
		for i in keys.size():
			var anchor := Vector2i(10+(i%7)*12,10+(i/7)*12)
			var code := Buildings.id_of(keys[i])
			Rotated.stamp_rotated(city,anchor,code,Zones.NONE,turn)
			# Imported lots may have no authoring/facility footprint metadata.
			city.facilities.erase(anchor)
			rows.append({"anchor":anchor,"code":code,"key":keys[i],"guests":3 if keys[i] != &"com_corner_store" else 0,"day_visitors":17})
		for water in [false,true]:
			var values := TourismUtilities.overlay(city,rows,water)
			var expected := 0
			for row in rows:
				var units := TourismUtilities.request(row,water)
				expected += units
				var size := Buildings.size(row.code)
				var actual := 0
				for dy in size.y:
					for dx in size.x: actual += values[(row.anchor.y+dy)*City.WIDTH+row.anchor.x+dx]
				check_eq(actual,units,"each footprint owns its exact whole venue request")
			check_eq(sum_units(values),expected)
			rows.reverse()
			check_eq(TourismUtilities.overlay(city,rows,water),values,"order independent fixed remainder assignment")

func test_reports_preflight_and_established_passes_preserve_sources_storage_rng_and_earned_state() -> void:
	var ctx := fixture()
	attend(ctx,80)
	ctx.city.stamp_building(14,10,Buildings.WATER_TOWER)
	ctx.city.set_flag(14,10,TileFlags.WATERED,true)
	var water := ctx.system(&"water") as WaterSystem
	var power := ctx.system(&"power") as PowerSystem
	var tourism := ctx.system(&"tourism") as TourismSystem
	var before := var_to_bytes([ctx.city.flags.data,ctx.city.facilities,ctx.rng.state(),tourism.save()])
	for i in 3:
		water.network_summary()
		power.network_summary()
		tourism.effects_snapshot()
		water.can_supply_lot(ctx.city,Rect2i(10,10,4,4),1)
		power.can_supply_lot(ctx.city,Rect2i(10,10,4,4),1)
	check_eq(var_to_bytes([ctx.city.flags.data,ctx.city.facilities,ctx.rng.state(),tourism.save()]),before)
	var facilities := ctx.city.facilities.duplicate(true)
	var random_state := ctx.rng.state()
	var earned: Dictionary = tourism.save().activity.duplicate(true)
	for i in 2:
		power.reallocate_established(ctx,Rect2i(0,0,128,128))
		water.reallocate_established(ctx,Rect2i(0,0,128,128))
	check(ctx.city.is_watered(14,10),"established pass never drains tower contents")
	check_eq(ctx.city.facilities,facilities,"outputs and stored source records remain exact")
	check_eq(ctx.rng.state(),random_state)
	check_eq(tourism.save().activity,earned)

func test_raw_demolition_and_replaced_instance_invalidate_overlay() -> void:
	var ctx := fixture()
	attend(ctx,80)
	var rows := (ctx.system(&"tourism") as TourismSystem).utility_rows()
	var cache := TourismUtilities.new()
	cache.accept(ctx.city,rows,true)
	check_eq(cache.units,6)
	ctx.city.building.put(11,11,Buildings.NONE)
	cache.accept(ctx.city,rows,true)
	check_eq(cache.units,0,"partial raw footprint cannot carry stale attendance")
	ctx.city.building.put(11,11,Buildings.id_of(&"arcology_afterglow"))
	cache.accept(ctx.city,rows,true)
	check_eq(cache.units,6)
	ctx.city.facility(Vector2i(10,10)).tourism_instance += 1
	cache.accept(ctx.city,rows,true)
	check_eq(cache.units,0,"same geometry with new instance cannot inherit attendance")

func test_detached_network_cannot_borrow_distant_spare_source() -> void:
	var ctx := fixture(&"com_corner_store")
	ctx.city.clear_footprint(6,6)
	ctx.systems.erase(&"power")
	attend(ctx,0,24)
	ctx.city.facility(Vector2i(9,10)).output = 1
	ctx.city.stamp_building(70,70,Buildings.WATER_PUMP)
	ctx.city.set_flag(70,70,TileFlags.POWERED,true)
	ctx.city.facilities[Vector2i(70,70)] = {"key":&"water_pump","output":1000}
	var water := ctx.system(&"water") as WaterSystem
	water.reallocate_established(ctx,Rect2i(0,0,128,128))
	check_gt(water.network_summary().capacity,water.network_summary().demand)
	check(not ctx.city.is_watered(10,10),"unrelated spare capacity cannot pay this component's visitor units")
	check(not water.can_supply_lot(ctx.city,Rect2i(10,10,1,1),1))

func test_supplemental_zero_baseline_preflight_still_requires_visitor_capacity() -> void:
	var ctx := fixture(&"com_corner_store")
	ctx.city.clear_footprint(6,6)
	attend(ctx,0,24)
	ctx.city.facility(Vector2i(9,10)).output = 0
	var water := ctx.system(&"water") as WaterSystem
	check(not water.can_supply_lot(ctx.city,Rect2i(10,10,1,1),0),"zero replacement baseline does not erase accepted visitors")

func test_empty_tourism_publication_preserves_ordinary_saved_summary_semantics() -> void:
	var ctx := make_context(flat_city())
	contexts.append(ctx)
	ctx.city.restored_layers["flags"] = true
	ctx.stats.water_demand = 91 # Saved pass may predate subsequent ordinary growth.
	var water := WaterSystem.new()
	ctx.systems[&"water"] = water
	water.setup(ctx)
	water.load({"consumed":40})
	check_eq(water.network_summary().demand,91)
	var tourism := TourismSystem.new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	check_eq(tourism.finish_restore({}),OK)
	check_eq(water.network_summary().demand,91,"empty tourism does not rewrite ordinary saved allocation reporting")

func test_conservation_spare_uses_component_local_rounding_even_after_restore() -> void:
	var ctx := make_context(flat_city())
	contexts.append(ctx)
	ctx.stats.ordinances[UtilityParams.CONSERVATION_ORDINANCE] = true
	for at in [Vector2i(10,10),Vector2i(50,50)]: ctx.city.stamp_building(at.x,at.y,Buildings.WIND_PLANT)
	var power := PowerSystem.new()
	power.setup(ctx)
	for at in [Vector2i(10,10),Vector2i(50,50)]: ctx.city.facility(at).capacity = 7
	power.reallocate_established(ctx,Rect2i(0,0,128,128))
	check_eq(power.network_summary().available_capacity,14,"two seven-unit components cannot combine their fractional conservation bonus")
	check_eq(power.network_summary().spare_capacity,14)
	var restored := PowerSystem.new()
	restored.setup_from_save(ctx,power.save())
	check_eq(restored.network_summary().available_capacity,14)

func test_power_preflight_and_detached_consumption_charge_the_same_visitor_tile() -> void:
	var ctx := fixture(&"com_corner_store")
	ctx.city.clear_footprint(6,6)
	ctx.city.stamp_building(9,10,Buildings.WIND_PLANT)
	ctx.city.facilities[Vector2i(9,10)] = {"key":Buildings.key(Buildings.WIND_PLANT),"capacity":1}
	attend(ctx,0,24)
	var power := ctx.system(&"power") as PowerSystem
	check(not power.can_supply_lot(ctx.city,Rect2i(10,10,1,1),1))
	var projected := AgriculturalParcelService.project(ctx)
	check(not projected.is_powered(10,10),"baseline fits one, baseline plus visitors needs two")
	power.reallocate_established(ctx,Rect2i(0,0,128,128))
	check_eq(power.consumed(),0,"cannot partially fund a visitor-bearing tile")
	check(not ctx.city.is_powered(10,10))

func test_water_reporting_scalars_reject_malformed_restore_atomically() -> void:
	var sim := make_simulation(flat_city(),721)
	var before := var_to_bytes([sim.snapshot(),sim.city.flags.data,sim.city.facilities])
	for fields in [
		{"requested_demand":1}, {"visitor_demand":0},
		{"requested_demand":-1,"visitor_demand":0},
		{"requested_demand":1.5,"visitor_demand":0},
		{"requested_demand":true,"visitor_demand":0},
		{"requested_demand":2147483648,"visitor_demand":0},
		{"requested_demand":2,"visitor_demand":3},
		{"requested_demand":2,"visitor_demand":-1},
		{"requested_demand":2,"visitor_demand":0.5}]:
		var snapshot := sim.snapshot().duplicate(true)
		snapshot.systems.water.erase("requested_demand")
		snapshot.systems.water.erase("visitor_demand")
		snapshot.systems.water.merge(fields,true)
		check(not SaveFormat.validate_snapshot(snapshot).is_empty(),"malformed reporting scalar rejected: "+str(fields))
		check_eq(sim.restore(snapshot),ERR_INVALID_DATA)
		check_eq(var_to_bytes([sim.snapshot(),sim.city.flags.data,sim.city.facilities]),before,"rejection precedes active adoption")
	var previous := sim.snapshot().duplicate(true)
	previous.systems.water.erase("requested_demand")
	previous.systems.water.erase("visitor_demand")
	check_eq(SaveFormat.validate_snapshot(previous),"","earlier saves retain neutral defaults")
	check_eq(SaveFormat.validate_snapshot(JSON.parse_string(JSON.stringify(sim.snapshot()))),"","integral JSON numbers retain exact units")
	sim._ctx.systems.clear()
	sim.systems.clear()
	root.remove_child(sim)
	sim.free()
