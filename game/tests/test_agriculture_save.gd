# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_agriculture_growth.gd"

func test_mid_month_restore_does_not_double_advance() -> void:
	var f := fixture()
	if f.is_empty(): return
	f.ag.monthly(f.ctx, 0)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(f.ag.save()))
	var before: int = f.ag.raw_demand()
	f.ag.load(saved)
	f.ag.monthly(f.ctx, 0)
	f.ag.monthly(f.ctx, 1)
	check_eq(f.ag.raw_demand(), before)
	check_eq(f.ag.inspect_tile(Vector2i(14, 10)).state, &"prepared")
	f.ctx.systems.clear()

func test_bad_records_pruned_without_layer_edits() -> void:
	var f := fixture()
	if f.is_empty(): return
	month(f)
	var saved: Dictionary = f.ag.save()
	f.city.clear_footprint(14, 10)
	f.city.stamp_building(14, 10, Buildings.WATER_PUMP)
	var before := var_to_bytes([f.city.building.data, f.city.zone.data, f.city.flags.data, f.city.facilities])
	f.ag.load(saved)
	check_eq(f.ag.current_lots().size(), 0)
	check_eq(var_to_bytes([f.city.building.data, f.city.zone.data, f.city.flags.data, f.city.facilities]), before)
	f.ctx.systems.clear()

func test_private_rng_round_trip() -> void:
	var f := fixture(Zones.AGR_HIGH, 3)
	if f.is_empty(): return
	month(f)
	var saved: Dictionary = f.ag.save()
	check(saved.rng_seed is String and saved.rng_state is String)
	var shared: int = f.ctx.rng.state()
	var bytes := var_to_bytes(saved)
	f.ag.load(JSON.parse_string(JSON.stringify(saved)))
	check_eq(var_to_bytes(f.ag.save()), bytes)
	check_eq(f.ctx.rng.state(), shared)
	f.ctx.systems.clear()

func test_infer_missing_records_rotation_and_phase_continuation() -> void:
	var f := fixture(Zones.AGR_HIGH, 3)
	if f.is_empty(): return
	f.city.stamp_building(14, 10, AgricultureParams.building_id(&"dairy"), Zones.AGR_HIGH)
	f.city.rotation = 3
	var before := var_to_bytes([f.city.building.data, f.city.zone.data, f.city.flags.data])
	f.ag.load({})
	check_eq(f.ag.current_lots().size(), 1)
	check_eq(f.ag.current_lots()[0].anchor, Vector2i(14, 10))
	check_eq(f.ag.current_lots()[0].archetype, &"dairy")
	check_eq(var_to_bytes([f.city.building.data, f.city.zone.data, f.city.flags.data]), before)
	f.ctx.systems.clear()

func test_uninterrupted_matches_restored_at_each_phase() -> void:
	var f := fixture(Zones.AGR_LOW, 3)
	if f.is_empty(): return
	for x in range(70, 73):
		for y in range(10, 13): f.city.zone.put(x, y, Zones.make(Zones.AGR_HIGH))
		f.city.building.put(x, 9, Buildings.ROAD_FIRST)
	for month_index in 4:
		for phase in 2:
			f.ag.monthly(f.ctx, phase)
			var clone: City = f.city.duplicate_city()
			var other_ctx := make_context(clone, 99)
			other_ctx.clock.day = f.ctx.clock.day
			var other: SimSystem = load("res://scripts/sim/agriculture_system.gd").new()
			other.setup(other_ctx)
			other.load(JSON.parse_string(JSON.stringify(f.ag.save())))
			# Replaying an already completed phase is idempotent on both.
			other.monthly(other_ctx, phase)
			check_eq(other.save(), f.ag.save())
			check_eq(clone.building.data, f.city.building.data)
		f.ctx.clock.day += GameClock.DAYS_PER_MONTH
	f.ctx.systems.clear()

func test_native_save_and_scheduled_phases_round_trip() -> void:
	var c := flat_city()
	for y in range(10,13):
		for x in range(14,17): c.zone.put(x,y,Zones.make(Zones.AGR_LOW))
	c.building.put(14, 9, Buildings.ROAD_FIRST)
	var a := make_simulation(c, 1827)
	a.stats.disasters_enabled = false
	a.advance_days(5)
	var ag := a.get_system(&"agriculture")
	check(ag != null)
	var parcels: Array[Dictionary] = ag.current_parcels()
	check_gt(parcels.size(),0,"normal scheduled growth forms an actual parcel")
	if not parcels.is_empty():
		check(parcels[0].mode in [&"generated",&"square"])
		check_eq(ag.inspect_tile(AgriculturalParcels.tile(parcels[0].members[0])).state,&"prepared")
	var path := "user://agriculture-mid-month.sc2d"
	check_eq(SaveFormat.save(path, c, a.snapshot()), OK)
	var result := SaveFormat.load(path)
	check(result.ok, result.get("error", ""))
	if result.ok:
		var b := Simulation.new()
		root.add_child(b)
		b.setup(result.city, -1, null, result.snapshot)
		b.restore(result.snapshot)
		check_eq(b.get_system(&"agriculture").save(), ag.save())
		check_eq(b.rng.state(), a.rng.state())
		for i in 60:
			a.advance_day()
			b.advance_day()
			check_eq(b.get_system(&"agriculture").save(), ag.save())
			check_eq(b.city.agricultural_parcels.to_dict(), a.city.agricultural_parcels.to_dict())
			check_eq(b.city.building.data, a.city.building.data)
			check_eq(b.rng.state(), a.rng.state())
		b.free()
	a.free()

func test_signed_rng_and_malformed_records_are_safe() -> void:
	var f := fixture()
	if f.is_empty(): return
	month(f)
	var data: Dictionary = f.ag.save()
	data.rng_seed = "-9223372036854775807"
	data.rng_state = "-1234567890123456789"
	data.lots = [null, "broken", {"x": {}, "y": 10}, {"x": 14, "y": 10, "archetype": "missing", "state": "active"}]
	var layers := var_to_bytes([f.city.building.data, f.city.zone.data, f.city.flags.data, f.city.facilities])
	var shared: int = f.ctx.rng.state()
	f.ag.load(JSON.parse_string(JSON.stringify(data)))
	check_eq(f.ag.save().rng_seed, data.rng_seed)
	check_eq(f.ag.save().rng_state, data.rng_state)
	check_eq(f.ag.current_lots().size(), 1, "valid current prepared footprint reconstructed deterministically")
	check_eq(var_to_bytes([f.city.building.data, f.city.zone.data, f.city.flags.data, f.city.facilities]), layers)
	check_eq(f.ctx.rng.state(), shared)
	f.ctx.systems.clear()

class WithoutAgriculture extends Simulation:
	func _load_systems() -> void:
		super._load_systems()
		var agriculture := get_system(&"agriculture")
		systems.erase(agriculture)
		_system_index.erase(&"agriculture")

func _legacy_snapshot(sim: Simulation) -> Dictionary:
	var data := sim.snapshot()
	data.systems.erase("agriculture")
	data.stats.erase("demand_agricultural")
	data.stats.erase("agricultural_jobs")
	data.stats.erase("agricultural_lots")
	# These newly added graph series have no legacy counterpart. Preserve
	# every pre-existing series byte-for-byte in this continuation comparison.
	for series: StringName in [&"demand_agricultural", &"agricultural_jobs", &"agricultural_lots", &"taxes_agricultural"]:
		data.stats.history.erase(String(series))
	return data

func test_zero_agriculture_matches_driver_without_new_system() -> void:
	var c := flat_city()
	c.stamp_building(10, 10, Buildings.SOLAR_PLANT)
	c.stamp_building(9, 10, Buildings.WIND_PLANT)
	c.stamp_building(14, 10, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	c.stamp_building(15, 10, Buildings.WATER_PUMP)
	c.building.put(14, 9, Buildings.ROAD_FIRST)
	var a := make_simulation(c, 5821)
	var b := WithoutAgriculture.new()
	root.add_child(b)
	# Use the same initial map, before setup registered facilities/service.
	var original := flat_city()
	original.stamp_building(10, 10, Buildings.SOLAR_PLANT)
	original.stamp_building(9, 10, Buildings.WIND_PLANT)
	original.stamp_building(14, 10, Buildings.RES_1X1_FIRST, Zones.RES_LOW)
	original.stamp_building(15, 10, Buildings.WATER_PUMP)
	original.building.put(14, 9, Buildings.ROAD_FIRST)
	b.setup(original, 5821)
	a.stats.disasters_enabled = false
	b.stats.disasters_enabled = false
	check_eq(_legacy_snapshot(a), _legacy_snapshot(b), "setup leaves every old snapshot field unchanged")
	for i in 50:
		a.advance_day()
		b.advance_day()
		check_eq(_legacy_snapshot(a), _legacy_snapshot(b), "day %d old stats, private systems, treasury and shared RNG" % i)
		check_eq(a.city.building.data, b.city.building.data)
		check_eq(a.city.flags.data, b.city.flags.data)
		check_eq(a.city.zone.data, b.city.zone.data)
	check_eq(a.city.funds, b.city.funds)
	a.free()
	b.free()
