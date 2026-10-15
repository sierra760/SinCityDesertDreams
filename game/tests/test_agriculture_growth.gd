# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"

func fixture(kind: int = Zones.AGR_LOW, side: int = 1, seed_value: int = 7) -> Dictionary:
	var c := flat_city()
	for y in range(10, 10 + side):
		for x in range(14, 14 + side): c.zone.put(x, y, Zones.make(kind))
	c.building.put(14, 9, Buildings.ROAD_FIRST)
	var ctx := make_context(c, seed_value)
	if not ResourceLoader.exists("res://scripts/sim/agriculture_system.gd"):
		check(false, "AgricultureSystem must exist")
		return {}
	var ag: SimSystem = load("res://scripts/sim/agriculture_system.gd").new()
	ctx.systems[&"agriculture"] = ag
	ag.setup(ctx)
	return {"city": c, "ctx": ctx, "ag": ag}

func month(f: Dictionary) -> void:
	f.ag.monthly(f.ctx, 0)
	f.ag.monthly(f.ctx, 1)
	f.ctx.clock.day += GameClock.DAYS_PER_MONTH

func supply(f: Dictionary) -> void:
	f.city.stamp_building(10, 10, Buildings.SOLAR_PLANT)
	f.city.stamp_building(9, 10, Buildings.WIND_PLANT)
	f.city.stamp_building(15, 10, Buildings.WATER_PUMP)
	f.city.sea_level = 30
	var power := PowerSystem.new()
	var water := WaterSystem.new()
	f.ctx.systems[&"power"] = power
	f.ctx.systems[&"water"] = water
	power.setup(f.ctx)
	water.setup(f.ctx)

func test_preparation_precedes_service() -> void:
	var f := fixture()
	if f.is_empty(): return
	var shared: int = f.ctx.rng.state()
	month(f)
	check_eq(f.ag.inspect_tile(Vector2i(14, 10)).state, &"prepared")
	check_eq(f.ag.jobs(), 0)
	check_eq(f.ctx.stats.agricultural_lots, 0)
	check_eq(f.ctx.rng.state(), shared)
	supply(f)
	shared = f.ctx.rng.state()
	month(f)
	check_eq(f.ag.inspect_tile(Vector2i(14, 10)).state, &"active")
	var formed: Dictionary = f.ag.current_parcels()[0]
	var expected_jobs: int = AgriculturalParcelParams.JOB_UNITS_PER_TILE[formed.archetype] * formed.members.size() / 36
	check_eq(f.ag.jobs(), expected_jobs)
	check_eq(f.ctx.stats.agricultural_lots, 1)
	check_eq(f.ag.assessed_value(), expected_jobs * 100)
	check_eq(f.ctx.rng.state(), shared, "growth refresh never rerolls solar")
	f.ctx.systems.clear()

func test_high_density_needs_power_low_does_not() -> void:
	for kind in [Zones.AGR_LOW, Zones.AGR_HIGH]:
		var f := fixture(kind)
		if f.is_empty(): return
		month(f)
		supply(f)
		f.ctx.systems.erase(&"power")
		month(f)
		check_eq(f.ag.inspect_tile(Vector2i(14, 10)).state, &"active" if kind == Zones.AGR_LOW else &"prepared")
		f.ctx.systems.clear()

func test_all_ten_archetypes_reachable() -> void:
	var reached := {}
	for kind in [Zones.AGR_LOW, Zones.AGR_HIGH]:
		for seed_value in range(1, 30):
			var f := fixture(kind, 3, seed_value)
			if f.is_empty(): return
			month(f)
			var novel := false
			for lot in f.ag.current_lots():
				if not reached.has(lot.archetype): novel = true
			if novel:
				f.city.stamp_building(10, 10, Buildings.SOLAR_PLANT)
				f.city.stamp_building(17, 10, Buildings.WATER_PUMP)
				f.city.sea_level = 30
				var power := PowerSystem.new()
				var water := WaterSystem.new()
				f.ctx.systems[&"power"] = power
				f.ctx.systems[&"water"] = water
				power.setup(f.ctx)
				water.setup(f.ctx)
				month(f)
				for lot in f.ag.current_lots():
					if lot.state == &"active": reached[lot.archetype] = true
			f.ctx.systems.clear()
	check_eq(reached.size(), 10, "ordinary initial growth selects every roster member")

func test_dormancy_after_exactly_three_months() -> void:
	var f := fixture()
	if f.is_empty(): return
	month(f)
	supply(f)
	month(f)
	f.city.clear_footprint(15, 10)
	var shared: int = f.ctx.rng.state()
	month(f)
	month(f)
	check_eq(f.ag.inspect_tile(Vector2i(14, 10)).failed_months, 2)
	check_eq(f.ag.inspect_tile(Vector2i(14, 10)).state, &"active")
	month(f)
	check_eq(f.ag.inspect_tile(Vector2i(14, 10)).failed_months, 3)
	check_eq(f.ag.inspect_tile(Vector2i(14, 10)).state, &"dormant")
	check_eq(f.ag.jobs(), 0)
	check_eq(f.ctx.stats.agricultural_lots, 0)
	check_eq(f.ctx.rng.state(), shared)
	f.ctx.systems.clear()

func test_recovery_and_density_stability() -> void:
	var f := fixture()
	if f.is_empty(): return
	month(f)
	supply(f)
	month(f)
	var original_archetype: StringName = f.ag.inspect_tile(Vector2i(14,10)).archetype
	f.city.clear_footprint(15, 10)
	for i in 3: month(f)
	supply(f)
	var shared: int = f.ctx.rng.state()
	month(f)
	var lot: Dictionary = f.ag.inspect_tile(Vector2i(14, 10))
	check_eq(lot.state, &"active")
	check_eq(lot.failed_months, 0)
	check_eq(lot.archetype, original_archetype)
	check_eq(f.ctx.rng.state(), shared)
	f.ctx.systems.clear()

func test_no_partial_or_sloped_lots() -> void:
	var f := fixture(Zones.AGR_LOW, 3)
	if f.is_empty(): return
	f.city.set_heights(14, 10, 4, 1)
	f.city.terrain.put(14, 10, Terrain.SLOPE_N)
	month(f)
	check_eq(f.city.building_at(14, 10), Buildings.NONE)
	for lot in f.ag.current_lots():
		for i in lot.members:
			var at := AgriculturalParcels.tile(i)
			check(f.city.is_flat(at.x,at.y))
			check_eq(f.city.agricultural_parcels.id_at(at),lot.parcel_id)
			check_eq(f.city.anchor_of(at.x,at.y),at,"new occupancy IDs are single-cell anchors")
	f.ctx.systems.clear()

func test_cached_refresh_preserves_towers_and_rng() -> void:
	var f := fixture(Zones.AGR_HIGH)
	if f.is_empty(): return
	month(f)
	supply(f)
	f.city.stamp_building(9, 10, Buildings.WIND_PLANT)
	f.city.stamp_building(14, 11, Buildings.WATER_TOWER)
	f.ctx.systems.power.networks_changed(f.ctx, Rect2i(9, 10, 7, 3))
	f.ctx.systems.water.networks_changed(f.ctx, Rect2i(9, 10, 7, 3))
	var shared: int = f.ctx.rng.state()
	var tower_bits: int = f.city.flags.at(14, 11) & TileFlags.WATERED
	for i in 3:
		f.ctx.systems.power.reallocate_established(f.ctx, Rect2i(14, 10, 1, 1))
		f.ctx.systems.water.reallocate_established(f.ctx, Rect2i(14, 10, 1, 1))
	check_eq(f.city.flags.at(14, 11) & TileFlags.WATERED, tower_bits)
	check_eq(f.ctx.rng.state(), shared)
	f.ctx.systems.clear()

func utility_snapshot(f: Dictionary) -> PackedByteArray:
	return var_to_bytes([f.city.building.data, f.city.zone.data, f.city.flags.data,
		f.city.underground.data, f.city.facilities, f.ctx.rng.state(),
		f.ctx.systems.power.save(), f.ctx.systems.power.network_summary(),
		f.ctx.systems.water.save(), f.ctx.systems.water.network_summary()])

func test_coupled_refusal_is_read_only() -> void:
	var f := fixture(Zones.AGR_HIGH)
	if f.is_empty(): return
	month(f)
	supply(f)
	# Solar seeds west of the farm. The load-two farm is allocated before
	# the downstream pump; two units leave no power for pumping water.
	f.city.clear_footprint(15, 10)
	f.city.stamp_building(15, 10, Buildings.WATER_PUMP)
	f.ctx.systems.power.networks_changed(f.ctx, Rect2i(15, 9, 1, 2))
	f.ctx.systems.water.networks_changed(f.ctx, Rect2i(15, 9, 1, 2))
	f.city.facility(Vector2i(10, 10))["capacity"] = 2
	f.city.facility(Vector2i(9, 10))["capacity"] = 0
	var before := utility_snapshot(f)
	month(f)
	check_eq(f.ag.inspect_tile(Vector2i(14, 10)).state, &"prepared")
	check_eq(utility_snapshot(f), before, "refused projection leaves real instances and layers intact")
	f.ctx.systems.clear()

func test_active_lots_share_service_projection() -> void:
	var f := fixture()
	if f.is_empty(): return
	for x in range(20, 40):
		f.city.stamp_building(x, 10, AgricultureParams.building_id(&"vegetables"), Zones.AGR_LOW)
		f.city.building.put(x, 9, Buildings.ROAD_FIRST)
	f.ag.networks_changed(f.ctx, Rect2i(20, 9, 20, 2))
	f.ag.monthly(f.ctx, 0)
	check(f.ag.projection_count() <= 2, "unchanged active loads share one allocation per half-city pass")
	f.ctx.systems.clear()

func test_demand_is_independent_monthly_and_tax_sensitive() -> void:
	var f := fixture()
	if f.is_empty(): return
	f.city.zone.put(14, 10, 0)
	f.ctx.stats.demand = Vector3i(10, 20, 30)
	check_eq(f.ag.raw_demand(), 1000)
	f.ag.monthly(f.ctx, 0)
	check_eq(f.ag.raw_demand(), 1160)
	f.ag.monthly(f.ctx, 1)
	check_eq(f.ag.raw_demand(), 1160)
	check_eq(f.ctx.stats.demand, Vector3i(10, 20, 30))
	f.ctx.stats.tax_agricultural = 20
	f.ctx.clock.day += GameClock.DAYS_PER_MONTH
	f.ag.monthly(f.ctx, 0)
	check_eq(f.ag.raw_demand(), clampi(1160 + 160 + ZoneParams.tax_pressure(20), -2000, 2000))
	f.ctx.systems.clear()

func test_whole_footprint_consolidation_and_no_partial_replacement() -> void:
	var f := fixture(Zones.AGR_HIGH, 3)
	if f.is_empty(): return
	for y in range(10, 13):
		for x in range(14, 17): f.city.stamp_building(x, y, AgricultureParams.state_id(&"prepared", 1), Zones.AGR_HIGH)
	f.ag.networks_changed(f.ctx, Rect2i(14, 10, 3, 3))
	var larger := false
	for i in 12:
		month(f)
		for lot in f.ag.current_lots():
			if lot.rect.size.x > 1: larger = true
	check(larger, "one-cell plots cannot permanently block larger farming lots")
	for lot in f.ag.current_lots():
		var rect: Rect2i = lot.rect
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x): check_eq(f.city.anchor_of(x, y), lot.anchor)
	f.ctx.systems.clear()

func test_waiting_lot_projections_are_bounded() -> void:
	var f := fixture()
	if f.is_empty(): return
	for x in range(20, 60):
		f.city.stamp_building(x, 10, AgricultureParams.state_id(&"prepared", 1), Zones.AGR_LOW)
		f.city.building.put(x, 9, Buildings.ROAD_FIRST)
	f.ag.networks_changed(f.ctx, Rect2i(20, 9, 40, 2))
	f.ag.monthly(f.ctx, 0)
	check(f.ag.projection_count() <= 16, "waiting farm projections capped per phase")
	f.ctx.systems.clear()

func test_later_activation_cannot_leave_new_lot_unsupplied() -> void:
	var f := fixture(Zones.AGR_HIGH)
	if f.is_empty(): return
	f.city.stamp_building(14, 9, AgricultureParams.state_id(&"prepared", 1), Zones.AGR_HIGH)
	f.city.stamp_building(14, 10, AgricultureParams.state_id(&"prepared", 1), Zones.AGR_HIGH)
	f.city.building.put(14, 8, Buildings.ROAD_FIRST)
	f.ag.networks_changed(f.ctx, Rect2i(14, 8, 1, 3))
	supply(f)
	f.city.facility(Vector2i(15, 10))["output"] = 2
	f.ag.monthly(f.ctx, 0)
	var active := 0
	for lot in f.ag.current_lots():
		if lot.state == &"active":
			active += 1
			check(f.city.is_watered(lot.anchor.x, lot.anchor.y), "newly active farms must remain supplied at publication")
	check_eq(active, 1, "two water units can activate only one load-two greenhouse")
	f.ctx.systems.clear()

func test_creation_does_not_reroll_and_empty_month_does_not_refresh() -> void:
	var f := fixture()
	if f.is_empty(): return
	supply(f)
	var shared: int = f.ctx.rng.state()
	var solar: int = f.city.facility(Vector2i(10, 10)).capacity
	var wind: int = f.city.facility(Vector2i(9, 10)).capacity
	month(f)
	check_eq(f.ctx.rng.state(), shared)
	check_eq(f.city.facility(Vector2i(10, 10)).capacity, solar)
	check_eq(f.city.facility(Vector2i(9, 10)).capacity, wind)
	f.ctx.systems.clear()

func test_empty_month_after_legacy_clear_does_not_refresh() -> void:
	var f := fixture()
	f.city.stamp_building(14,10,AgricultureParams.state_id(&"prepared",1),Zones.AGR_LOW)
	f.ag.networks_changed(f.ctx,Rect2i(14,10,1,1))
	check_eq(f.ag.current_parcels()[0].mode,&"legacy")
	supply(f)
	month(f)
	f.city.clear_footprint(14, 10)
	f.city.zone.put(14, 10, 0)
	var before := utility_snapshot(f)
	month(f)
	check_eq(utility_snapshot(f), before, "no agricultural change means no cached refresh")
	f.ctx.systems.clear()

func test_sustained_negative_demand_causes_exact_dormancy() -> void:
	var f := fixture()
	if f.is_empty(): return
	month(f)
	supply(f)
	month(f)
	var data: Dictionary = f.ag.save()
	data.raw_demand = -2000
	f.ag.load(data)
	f.ctx.stats.tax_agricultural = 20
	month(f)
	month(f)
	check_eq(f.ag.inspect_tile(Vector2i(14, 10)).state, &"active")
	check_eq(f.ag.inspect_tile(Vector2i(14, 10)).failed_months, 2)
	month(f)
	check_eq(f.ag.inspect_tile(Vector2i(14, 10)).state, &"dormant")
	f.ctx.systems.clear()

func test_half_city_seam_does_not_block_whole_lots_or_double_advance() -> void:
	var found := false
	for seed_value in range(1, 12):
		var f := fixture(Zones.AGR_LOW, 1, seed_value)
		if f.is_empty(): return
		f.city.zone.put(14, 10, 0)
		for y in range(10, 13):
			for x in range(63, 66): f.city.zone.put(x, y, Zones.make(Zones.AGR_LOW))
		f.city.building.put(63, 9, Buildings.ROAD_FIRST)
		month(f)
		for lot in f.ag.current_lots():
			if lot.rect.size.x == 3:
				found = true
				check_eq(lot.state, &"prepared")
				check_eq(lot.last_month, 0)
		f.ctx.systems.clear()
	check(found, "scan division cannot exclude a fitting farm footprint")

class Emergency extends SimSystem:
	func is_emergency() -> bool: return true
	func fires() -> Array: return []

func test_emergency_and_protection_refuse_automatic_development() -> void:
	var f := fixture()
	if f.is_empty(): return
	f.ctx.systems[&"disasters"] = Emergency.new()
	month(f)
	check_eq(f.city.building_at(14, 10), Buildings.NONE, "no new plot during active disaster")
	f.ctx.systems.erase(&"disasters")
	f.city.set_flag(14, 10, TileFlags.LANDMARK, true)
	month(f)
	check_eq(f.city.building_at(14, 10), Buildings.NONE)
	f.city.set_flag(14, 10, TileFlags.LANDMARK, false)
	month(f)
	supply(f)
	month(f)
	var protected_code: int = f.city.building_at(14,10)
	f.city.set_flag(14, 10, TileFlags.LANDMARK, true)
	f.city.clear_footprint(15, 10)
	for i in 3: month(f)
	check_eq(f.city.building_at(14, 10), protected_code, "protected building is not automatically replaced")
	f.ctx.systems.clear()

func test_detached_preflight_matches_uncoupled_utility_apis() -> void:
	var f := fixture(Zones.AGR_HIGH)
	if f.is_empty(): return
	month(f)
	supply(f)
	var rect := Rect2i(14, 10, 1, 1)
	for output in [2, 1]:
		f.city.facility(Vector2i(15, 10))["output"] = output
		var before := utility_snapshot(f)
		var ag_before: Dictionary = f.ag.save()
		var water_ok: bool = f.ctx.systems.water.can_supply_lot(f.city, rect, 2)
		var power_ok: bool = f.ctx.systems.power.can_supply_lot(f.city, rect, 2)
		var inspected: Dictionary = f.ag.inspect_tile(rect.position)
		check_eq(inspected.water_supplied, water_ok)
		check_eq(inspected.power_supplied, power_ok)
		check_eq(water_ok, output == 2)
		check_eq(utility_snapshot(f), before)
		check_eq(f.ag.save(), ag_before)
	f.ctx.systems.clear()

func test_rollback_revalidates_non_monotonic_whole_load_allocation() -> void:
	var c := flat_city()
	# Real north/west/south/east flood order reaches two grain cells, an
	# existing load-three vegetable plot, the greenhouse, then remaining grain.
	var cells := [[2,2],[2,4],[2,5],[2,6],[2,7],[2,9],[3,3],[3,4],[3,5],[3,6],[3,8],[3,9],
		[4,2],[4,3],[4,4],[4,6],[4,7],[4,8],[5,2],[5,4],[5,5],[5,6],[5,8],[6,4],[6,5],[6,6],
		[6,7],[6,8],[7,5],[7,6],[7,8],[8,2],[8,7],[8,8],[8,9],[9,2],[9,3],[9,4],[9,6],[9,8],[9,9]]
	for p in cells:
		c.underground.put(p[0], p[1], Underground.PIPE_FIRST)
		c.building.put(p[0], p[1], Buildings.POWER_LINE_FIRST)
	for x in range(7, 11): c.building.put(x, 5, Buildings.POWER_LINE_FIRST)
	c.stamp_building(10, 2, Buildings.SOLAR_PLANT)
	c.add_facility(Vector2i(10, 2), {"key": Buildings.key(Buildings.SOLAR_PLANT), "capacity": 100})
	c.stamp_building(2, 5, Buildings.WATER_PUMP)
	c.add_facility(Vector2i(2, 5), {"key": Buildings.key(Buildings.WATER_PUMP), "output": 4})
	c.stamp_building(5, 5, AgricultureParams.state_id(&"prepared", 2), Zones.AGR_LOW)
	c.stamp_building(6, 4, AgricultureParams.building_id(&"vegetables"), Zones.AGR_LOW)
	c.stamp_building(4, 8, AgricultureParams.state_id(&"prepared", 1), Zones.AGR_HIGH)
	c.building.put(7, 3, Buildings.ROAD_FIRST)
	c.building.put(3, 7, Buildings.ROAD_FIRST)
	# An independent, adequately supplied multi-tile activation must survive
	# both cascading rollbacks, so final flag assertions are not vacuous.
	c.stamp_building(24, 2, Buildings.SOLAR_PLANT)
	c.add_facility(Vector2i(24, 2), {"key": Buildings.key(Buildings.SOLAR_PLANT), "capacity": 100})
	c.stamp_building(21, 6, Buildings.WATER_PUMP)
	c.add_facility(Vector2i(21, 6), {"key": Buildings.key(Buildings.WATER_PUMP), "output": 8})
	c.stamp_building(22, 6, AgricultureParams.state_id(&"prepared", 2), Zones.AGR_HIGH)
	c.building.put(23, 5, Buildings.POWER_LINE_FIRST)
	c.building.put(22, 5, Buildings.ROAD_FIRST)
	var ctx := make_context(c)
	var power := PowerSystem.new()
	var water := WaterSystem.new()
	var ag := AgricultureSystem.new()
	ctx.systems = {&"power": power, &"water": water, &"agriculture": ag}
	power.reallocate_established(ctx, Rect2i(0, 0, 128, 128))
	water.reallocate_established(ctx, Rect2i(0, 0, 128, 128))
	ag.setup(ctx)
	ag.load({"lots": [{"x": 5, "y": 5, "archetype": "grain", "state": "prepared",
		"building_id": AgricultureParams.state_id(&"prepared", 2), "zone_kind": Zones.AGR_LOW}]})
	var shared := ctx.rng.state()
	ag.monthly(ctx, 0)
	check_eq(AgricultureSystem.MAX_PROJECTIONS_PER_PHASE, 33)
	check(ag.projection_count() <= AgricultureSystem.MAX_PROJECTIONS_PER_PHASE, "hard phase projection cap survives cascading revalidation")
	check_eq(ag.inspect_tile(Vector2i(22, 6)).state, &"active", "independent full nursery remains active")
	check_eq(ag.inspect_tile(Vector2i(5, 5)).state, &"prepared")
	check_eq(ag.inspect_tile(Vector2i(4, 8)).state, &"prepared", "grain rollback makes the earlier load-three consumer fit, displacing greenhouse")
	var retained := 0
	for lot in ag.current_lots():
		if lot.state != &"active" or lot.anchor == Vector2i(6, 4): continue
		retained += 1
		for y in range(lot.rect.position.y, lot.rect.end.y):
			for x in range(lot.rect.position.x, lot.rect.end.x):
				check(c.is_watered(x, y), "every published newly active tile has required water")
				if AgricultureParams.power_load(lot.building_id) > 0:
					check(c.is_powered(x, y), "every published newly active tile has required power")
	check_eq(retained, 1, "final service checks cover a retained newly active multi-tile footprint")
	check_eq(ctx.rng.state(), shared)
	ctx.systems.clear()

func test_legacy_low_square_preserves_codes_capacity_and_failure_lifecycle() -> void:
	var f := fixture()
	f.city.stamp_building(14,10,AgricultureParams.state_id(&"prepared",1),Zones.AGR_LOW)
	f.ag.networks_changed(f.ctx,Rect2i(14,10,1,1))
	check_eq(f.ag.current_parcels()[0].mode,&"legacy")
	month(f)
	check_eq(f.city.building_at(14,10),AgricultureParams.state_id(&"prepared",1))
	supply(f)
	month(f)
	check_eq(f.city.building_at(14,10),AgricultureParams.building_id(&"vegetables"))
	check_eq(f.ag.jobs(),4)
	check_eq(f.ag.assessed_value(),400)
	check_eq(f.ag.inspect_tile(Vector2i(14,10)).water_required,3)
	check_eq(f.ag.inspect_tile(Vector2i(14,10)).power_required,0)
	f.city.clear_footprint(15,10)
	for failed in range(1,4):
		month(f)
		check_eq(f.ag.inspect_tile(Vector2i(14,10)).failed_months,failed)
		check_eq(f.city.building_at(14,10),AgricultureParams.building_id(&"vegetables") if failed<3 else AgricultureParams.state_id(&"dormant",1))
	check_eq(f.ag.jobs(),0)
	check_eq(f.ag.current_parcels()[0].members,PackedInt32Array([10*128+14]))
	f.ctx.systems.clear()
