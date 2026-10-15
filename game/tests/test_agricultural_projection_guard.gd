# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")
var contexts: Array[SimContext] = []

class FullProjection extends AgricultureSystem:
	func _project_values(values: Array[Dictionary]) -> City:
		_projection_count += 1
		return AgriculturalParcelService.project(_ctx,{},values)

func after_each() -> void:
	for ctx in contexts: ctx.systems.clear()
	contexts.clear()

func fixture(dense: bool = false, full: bool = false) -> Dictionary:
	var c := flat_city()
	var m := F.square(4)
	for i in m: c.zone.put(i%128,i/128,Zones.AGR_HIGH if dense else Zones.AGR_LOW)
	c.building.put(19,20,Buildings.ROAD_FIRST)
	if dense: c.stamp_building(20,20,AgricultureParams.state_id(&"prepared",1),Zones.AGR_HIGH)
	else: check_eq(c.agricultural_parcels.put(c,F.record(1,m)),OK)
	var ctx := make_context(c,7)
	var ag: AgricultureSystem = FullProjection.new() if full else AgricultureSystem.new()
	ctx.systems[&"agriculture"]=ag
	ag.setup(ctx)
	contexts.append(ctx)
	return {"ctx":ctx,"ag":ag}

func trial(f: Dictionary) -> Array[Dictionary]:
	var lots: Array[Dictionary] = f.ag.current_lots()
	var lot: Dictionary = lots[0]
	if lot.parcel_id == 0: lot=f.ag.get("_lots")[lot.anchor].duplicate(true)
	return [f.ag._activation(lot)]

func state(f: Dictionary) -> PackedByteArray:
	return var_to_bytes([SaveFormat.encode_city(f.ctx.city),f.ag.save(),f.ctx.stats.to_dict(),f.ctx.rng.state(),f.ctx.events.news,f.ctx.events.notices,f.ctx.events.map_dirty])

func test_absent_and_sourceless_water_skip_only_nonempty_trials() -> void:
	for dense in [false,true]:
		var f := fixture(dense)
		for registered in [false,true]:
			if registered: f.ctx.systems[&"water"]=WaterSystem.new()
			var values := trial(f)
			var before := state(f)
			var attempts: int = f.ag.projection_count()
			var skipped: City = f.ag._project_values(values)
			check(skipped==null,"impossible activation avoids constructing a detached City")
			check_eq(f.ag.projection_count(),attempts+1,"logical attempts keep their existing bound")
			var baseline := AgriculturalParcelService.project(f.ctx,{},values)
			check(baseline!=null)
			check(not f.ag._proposal_served(values[0],baseline))
			check(not f.ag._proposal_served(values[0],skipped))
			var empty: Array[Dictionary] = []
			check(f.ag._project_values(empty)!=null,"empty active census retains one cacheable City")
			check(state(f)==before,"source layers, facilities, RNG and stats stay detached")

func source(f: Dictionary, output: int = 1000) -> void:
	var c: City = f.ctx.city
	c.stamp_building(16,16,Buildings.SOLAR_PLANT)
	c.add_facility(Vector2i(16,16),{"key":Buildings.key(Buildings.SOLAR_PLANT),"capacity":2000})
	c.building.put(19,19,Buildings.POWER_LINE_FIRST)
	c.stamp_building(20,19,Buildings.WATER_PUMP)
	c.add_facility(Vector2i(20,19),{"key":Buildings.key(Buildings.WATER_PUMP),"output":output})
	var power := PowerSystem.new()
	f.ctx.systems[&"power"]=power
	f.ctx.systems[&"water"]=WaterSystem.new()
	power.reallocate_established(f.ctx,Rect2i(0,0,128,128))

func test_raw_source_output_identity_and_tower_changes_are_read_each_time() -> void:
	for dense in [false,true]:
		var f := fixture(dense)
		f.ctx.systems[&"water"]=WaterSystem.new()
		var values := trial(f)
		check(f.ag._project_values(values)==null)
		source(f)
		check(f.ag._project_values(values)!=null,"a matching established positive output retains full allocation")
		f.ctx.city.flags.set_bits(20,19,TileFlags.POWERED,false)
		var supplied: City = f.ag._project_values(values)
		check(supplied!=null,"candidate conduction may restore pump power")
		if supplied!=null: check(f.ag._proposal_served(values[0],supplied))
		f.ctx.city.facility(Vector2i(20,19)).output=0
		check(f.ag._project_values(values)==null)
		f.ctx.city.facility(Vector2i(20,19)).output=1000
		f.ctx.city.facility(Vector2i(20,19)).key=&"water_treatment"
		check(f.ag._project_values(values)==null,"stale facility identity is not an output source")
		f.ctx.city.facility(Vector2i(20,19)).key=Buildings.key(Buildings.WATER_PUMP)
		f.ctx.city.building.put(20,19,Buildings.NONE)
		check(f.ag._project_values(values)==null,"raw source removal cannot leave a cached positive proof")
		f.ctx.city.building.put(20,19,Buildings.WATER_TOWER)
		f.ctx.city.flags.set_bits(20,19,TileFlags.WATERED,true)
		supplied=f.ag._project_values(values)
		check(supplied!=null,"tower storage remains a source even with no pump output")
		if supplied!=null: check(f.ag._proposal_served(values[0],supplied))
		f.ctx.city.flags.set_bits(20,19,TileFlags.WATERED,false)
		check(f.ag._project_values(values)!=null,"an empty tower conservatively keeps full refill/allocation behavior")
		f.ctx.city.building.put(20,19,Buildings.NONE)
		check(f.ag._project_values(values)==null)

func test_real_positive_sources_keep_full_projection_both_densities() -> void:
	for dense in [false,true]:
		var f := fixture(dense)
		source(f)
		var values := trial(f)
		var before := state(f)
		var actual: City = f.ag._project_values(values)
		var expected := AgriculturalParcelService.project(f.ctx,{},values)
		check(actual!=null)
		if actual!=null:
			check(SaveFormat.encode_city(actual)==SaveFormat.encode_city(expected))
			check(f.ag._proposal_served(values[0],actual))
		check(state(f)==before)

func test_empty_active_census_is_built_once_for_many_unserved_farms() -> void:
	var f := fixture()
	var c: City = f.ctx.city
	var r := c.agricultural_parcels.record(1)
	r.state=&"active";r.modules=AgriculturalParcelGeometry.plan(r).modules
	check_eq(c.agricultural_parcels.put(c,r),OK)
	var lots: Array[Dictionary] = f.ag.current_lots()
	var attempts: int = f.ag.projection_count()
	for n in 80: check(not f.ag._service(lots[0]).water_supplied)
	check_eq(f.ag.projection_count(),attempts+1,"the retained active service City prevents repeated empty projections")

func test_six_phase_continuation_matches_full_projection_with_raw_source_changes() -> void:
	for dense in [false,true]:
		var fast := fixture(dense)
		var full := fixture(dense,true)
		for month in 6:
			for f in [fast,full]:
				f.ctx.clock.day=month*GameClock.DAYS_PER_MONTH
				if month==1: f.ctx.systems[&"water"]=WaterSystem.new()
				if month==2: source(f)
				if month==3: f.ctx.city.building.put(20,19,Buildings.NONE)
				if month==4:
					f.ctx.city.building.put(20,19,Buildings.WATER_PUMP)
					f.ctx.city.flags.set_bits(20,19,TileFlags.POWERED,false)
				if month==5: f.ctx.systems.erase(&"water")
				f.ag.monthly(f.ctx,0)
				f.ag.monthly(f.ctx,1)
			check(state(fast)==state(full),"month%d density%d preserves every saved decision, RNG, flag, statistic and event"%[month,int(dense)])
			check_eq(fast.ag.work_counts(),full.ag.work_counts())
			check_eq(fast.ag.projection_count(),full.ag.projection_count())
			check(fast.ag.projection_count()<=AgricultureSystem.MAX_PROJECTIONS_PER_PHASE)

func test_desalination_requires_its_actual_matching_anchor_record() -> void:
	var f := fixture()
	f.ctx.systems[&"water"]=WaterSystem.new()
	var values := trial(f)
	f.ctx.city.stamp_building(80,80,Buildings.DESALINATION)
	f.ctx.city.add_facility(Vector2i(80,80),{"key":Buildings.key(Buildings.DESALINATION),"output":100})
	check(f.ag._project_values(values)!=null,"any possible established desalination output retains full connectivity/allocation")
	f.ctx.city.facility(Vector2i(80,80)).output=0
	f.ctx.city.add_facility(Vector2i(81,80),{"key":Buildings.key(Buildings.DESALINATION),"output":100})
	check(f.ag._project_values(values)==null,"a stale interior record is not the facility anchor used by distribution")
