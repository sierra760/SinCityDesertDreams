# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"


func test_loads_and_legacy_consumers() -> void:
	var params := UtilityParams.new()
	check(params.has_method("water_load"), "per-building water load API")
	check(params.has_method("power_load"), "per-building power load API")
	if not params.has_method("water_load") or not params.has_method("power_load"): return
	check_eq(params.call("water_load", AgricultureParams.building_id(&"vegetables")), 3)
	check_eq(params.call("water_load", AgricultureParams.building_id(&"cattle_range")), 1)
	check_eq(params.call("water_load", AgricultureParams.building_id(&"dairy")), 3)
	check_eq(params.call("power_load", AgricultureParams.building_id(&"greenhouse")), 2)
	for id in range(266):
		check_eq(params.call("water_load", id), 1 if UtilityParams.is_lot(id) and not UtilityParams.is_water_facility(id) else 0, "legacy water %d" % id)
		check_eq(params.call("power_load", id), 1 if UtilityParams.is_lot(id) and not Buildings.is_power_plant(id) else 0, "legacy power %d" % id)
	for state in [&"prepared", &"dormant"]:
		for side in range(1, 4):
			var id := AgricultureParams.state_id(state, side)
			check_eq(params.call("water_load", id), 0)
			check_eq(params.call("power_load", id), 0)


func _snapshot(c: City, ctx: SimContext, system: SimSystem) -> PackedByteArray:
	return var_to_bytes([c.flags.data, c.facilities, c.imported_power_links, c.funds,
		ctx.rng.state(), [ctx.stats.water_capacity, ctx.stats.water_demand, ctx.stats.water_stored, ctx.stats.power_capacity, ctx.stats.power_demand], system.save(), system.call("network_summary")])


func _water_fixture() -> Dictionary:
	var c := flat_city()
	c.sea_level = 0
	c.stamp_building(10, 10, Buildings.WATER_PUMP)
	c.set_flag(10, 10, TileFlags.POWERED, true)
	c.stamp_building(11, 10, AgricultureParams.state_id(&"prepared", 1))
	var ctx := make_context(c)
	var water := WaterSystem.new()
	water.setup(ctx)
	return {"city": c, "ctx": ctx, "water": water}


func test_water_preflight_full_load_and_no_side_effects() -> void:
	var f := _water_fixture()
	var c: City = f.city
	var ctx: SimContext = f.ctx
	var water: WaterSystem = f.water
	check(water.has_method("can_supply_lot"), "read-only water preflight API")
	if not water.has_method("can_supply_lot"): return
	var rect := Rect2i(11, 10, 1, 1)
	# Current source output is the established generation for the next allocation.
	c.facility(Vector2i(10, 10))["output"] = 2
	var before := _snapshot(c, ctx, water)
	check(not water.call("can_supply_lot", c, rect, 3), "capacity two cannot irrigate load three")
	check_eq(_snapshot(c, ctx, water), before)
	check(water.call("can_supply_lot", c, rect, 2), "prepared plot connected to real pump")
	check_eq(_snapshot(c, ctx, water), before)
	check(not water.call("can_supply_lot", c, Rect2i(30, 30, 1, 1), 1), "disconnected irrigation")
	check(water.call("can_supply_lot", c, Rect2i(30, 30, 1, 1), 0), "zero load needs no connection")
	check_eq(_snapshot(c, ctx, water), before)


func test_water_distribution_never_partially_funds_a_tile() -> void:
	var f := _water_fixture()
	var c: City = f.city
	var ctx: SimContext = f.ctx
	var water: WaterSystem = f.water
	c.stamp_building(11, 10, AgricultureParams.building_id(&"vegetables"))
	# Rain fallback gives seven units: only two of three load-three tiles fit.
	c.stamp_building(12, 10, AgricultureParams.building_id(&"vegetables"))
	c.stamp_building(13, 10, AgricultureParams.building_id(&"vegetables"))
	water.networks_changed(ctx, Rect2i(10, 10, 4, 1))
	check_eq(ctx.stats.water_demand, 9)
	check_eq(water.consumed(), 6)
	check(c.is_watered(11, 10) and c.is_watered(12, 10))
	check(not c.is_watered(13, 10), "remaining one cannot fund three")
	check_eq(ctx.stats.unwatered_buildings, 1)


func test_power_preflight_uses_current_generation_without_random_draws() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.SOLAR_PLANT)
	c.stamp_building(14, 10, AgricultureParams.state_id(&"prepared", 1))
	var ctx := make_context(c)
	var power := PowerSystem.new()
	power.setup(ctx)
	check(power.has_method("can_supply_lot"), "read-only power preflight API")
	if not power.has_method("can_supply_lot"): return
	var before := _snapshot(c, ctx, power)
	check(power.call("can_supply_lot", c, Rect2i(14, 10, 1, 1), 2))
	check(not power.call("can_supply_lot", c, Rect2i(14, 10, 1, 1), 10000))
	check_eq(_snapshot(c, ctx, power), before, "solar output, shared RNG, flags and summaries stay unchanged")


func test_power_distribution_reports_real_greenhouse_load() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.WIND_PLANT)
	for x in range(11, 14): c.stamp_building(x, 10, AgricultureParams.building_id(&"greenhouse"))
	var ctx := make_context(c)
	var power := PowerSystem.new()
	power.setup(ctx)
	check_eq(ctx.stats.power_demand, 6)
	check_eq(power.consumed(), 2)
	check(c.is_powered(11, 10))
	check(not c.is_powered(12, 10) and not c.is_powered(13, 10))


func test_preflight_tracks_connection_edits_and_existing_allocation_priority() -> void:
	var f := _water_fixture()
	var c: City = f.city
	var water: WaterSystem = f.water
	c.facility(Vector2i(10, 10))["output"] = 3
	c.stamp_building(10, 9, Buildings.RES_1X1_FIRST)
	check(not water.can_supply_lot(c, Rect2i(11, 10, 1, 1), 3), "north house consumes first")
	c.clear_footprint(10, 9)
	check(water.can_supply_lot(c, Rect2i(11, 10, 1, 1), 3))
	c.clear_footprint(11, 10)
	c.stamp_building(12, 10, AgricultureParams.state_id(&"prepared", 1))
	check(not water.can_supply_lot(c, Rect2i(12, 10, 1, 1), 3), "fresh conduction rejects severed path")
	c.underground.put(11, 10, UtilityParams.EW_MASK)
	check(water.can_supply_lot(c, Rect2i(12, 10, 1, 1), 3), "fresh pipe makes service available")
	c.clear_footprint(10, 10)
	check(not water.can_supply_lot(c, Rect2i(12, 10, 1, 1), 3), "removed pump cannot supply stale output")


func test_preflight_tower_storage_and_full_multitile_service() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.WATER_TOWER)
	c.stamp_building(12, 10, AgricultureParams.state_id(&"prepared", 2))
	c.set_flag(10, 10, TileFlags.WATERED, true)
	c.restored_layers["flags"] = true
	var ctx := make_context(c)
	var water := WaterSystem.new()
	water.setup(ctx)
	var before := _snapshot(c, ctx, water)
	check(water.can_supply_lot(c, Rect2i(12, 10, 2, 2), 3), "stored tower water serves the entire prepared lot")
	check(not water.can_supply_lot(c, Rect2i(12, 10, 2, 2), 30), "one hundred cannot fully serve four load-thirty tiles")
	check_eq(_snapshot(c, ctx, water), before, "tower not drained on success or refusal")
	c.set_flag(10, 10, TileFlags.WATERED, false)
	check(not water.can_supply_lot(c, Rect2i(12, 10, 2, 2), 3), "empty tower cannot seed")


func test_power_preflight_current_flags_conservation_and_stale_sources() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	c.stamp_building(14, 10, AgricultureParams.state_id(&"prepared", 1))
	var ctx := make_context(c)
	ctx.stats.ordinances[UtilityParams.CONSERVATION_ORDINANCE] = true
	var power := PowerSystem.new()
	power.setup(ctx)
	c.facility(Vector2i(10, 10))["capacity"] = 12
	check(power.can_supply_lot(c, Rect2i(14, 10, 1, 1), 13), "established conservation bonus")
	check(not power.can_supply_lot(c, Rect2i(14, 10, 1, 1), 14))
	# A stale imported link must be ignored without pruning the actual table.
	c.imported_power_links[30 * City.WIDTH + 30] = Vector2i(Buildings.RES_1X1_FIRST, 0)
	var before := _snapshot(c, ctx, power)
	check(not power.can_supply_lot(c, Rect2i(30, 30, 1, 1), 2))
	check_eq(_snapshot(c, ctx, power), before)
	c.clear_footprint(10, 10)
	check(not power.can_supply_lot(c, Rect2i(14, 10, 1, 1), 2), "removed plant cannot supply stale capacity")
	check(not PowerSystem.new().can_supply_lot(c, Rect2i(14, 10, 1, 1), 2))


func test_underground_agriculture_conduits_and_service_colors() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, AgricultureParams.building_id(&"greenhouse"))
	c.stamp_building(11, 10, AgricultureParams.state_id(&"prepared", 1))
	var view := CityUnderground3D.new()
	view.bind_city(c)
	check_eq(view._water_neighbors(Vector2i(10, 10)), UtilityParams.DIR_E)
	check(view.mesh_instance.mesh != null)
	var dry_colors: PackedColorArray = view.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(_has_color(dry_colors, CityUnderground3D.LOT_DRY), "agricultural lot dry service color")
	c.set_flag(10, 10, TileFlags.WATERED, true)
	view.refresh()
	var wet_colors: PackedColorArray = view.mesh_instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	check(_has_color(wet_colors, CityUnderground3D.LOT_WET), "agricultural lot wet service color")
	view.free()


func test_saved_summaries_preserve_agricultural_demands() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.COAL_PLANT)
	c.stamp_building(14, 10, AgricultureParams.building_id(&"greenhouse"))
	c.stamp_building(15, 10, Buildings.WATER_PUMP)
	var ctx := make_context(c)
	var power := PowerSystem.new()
	power.setup(ctx)
	var water := WaterSystem.new()
	water.setup(ctx)
	var power_demand: int = power.network_summary().demand
	var water_demand: int = water.network_summary().demand
	var flags := c.flags.data.duplicate()
	c.restored_layers["flags"] = true
	var loaded_power := PowerSystem.new()
	loaded_power.setup_from_save(ctx, power.save())
	var loaded_water := WaterSystem.new()
	loaded_water.setup(ctx)
	loaded_water.load(water.save())
	check_eq(loaded_power.network_summary().demand, power_demand)
	check_eq(loaded_water.network_summary().demand, water_demand)
	check_eq(power_demand, 3, "greenhouse two plus pump one")
	check_eq(water_demand, 18, "coal plant sixteen plus greenhouse two")
	check_eq(c.flags.data, flags)


func _has_color(colors: PackedColorArray, expected: Color) -> bool:
	for color in colors:
		if absf(color.r - expected.r) < .01 and absf(color.g - expected.g) < .01 and absf(color.b - expected.b) < .01:
			return true
	return false


class LowRain extends SimSystem:
	func precipitation() -> int: return 4


func test_two_units_cannot_supply_load_three_and_partial_lot_is_unserved() -> void:
	var f := _water_fixture()
	var c: City = f.city
	var ctx: SimContext = f.ctx
	var water: WaterSystem = f.water
	ctx.systems[&"weather"] = LowRain.new()
	c.stamp_building(11, 10, AgricultureParams.building_id(&"vegetables"))
	water.networks_changed(ctx, Rect2i(11, 10, 1, 1))
	check_eq(ctx.stats.water_capacity, 2)
	check_eq(water.consumed(), 0)
	check(not c.is_watered(11, 10))
	check_eq(ctx.stats.unwatered_buildings, 1)
	c.clear_footprint(11, 10)
	c.stamp_building(11, 10, AgricultureParams.building_id(&"dairy"))
	ctx.systems.clear()
	water.networks_changed(ctx, Rect2i(11, 10, 3, 3))
	check_eq(ctx.stats.water_demand, 27)
	check_eq(water.consumed(), 6)
	check_eq(ctx.stats.unwatered_buildings, 1, "partially served agriculture lot remains in shortage count")
