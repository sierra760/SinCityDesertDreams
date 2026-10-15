# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"

func test_native_v1_v2_legacy_documents_retain_city_and_rci() -> void:
	for version in [1,2]:
		var city := flat_city()
		city.stamp_building(10,10,Buildings.RES_1X1_FIRST,Zones.RES_LOW)
		var sim := make_simulation(city,1827)
		sim.stats.disasters_enabled = false
		var snapshot := sim.snapshot()
		snapshot.systems.erase("agriculture")
		for key in ["demand_agricultural","agricultural_jobs","agricultural_lots","tax_agricultural"]: snapshot.stats.erase(key)
		var encoded := SaveFormat.encode_city(city)
		if version == 1:
			var old := PackedByteArray()
			old.resize(City.WIDTH*City.HEIGHT)
			for i in old.size(): old[i] = city.building.data[i]
			encoded.layers.building = SaveFormat.encode_bytes(old)
		var path := "user://agriculture-legacy-%d.sc2d" % version
		var doc := {"format":"sc2d","version":version,"city":encoded,"snapshot":snapshot,"stage":"play"}
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(doc));file.close()
		var loaded := SaveFormat.load(path)
		check(loaded.ok,loaded.get("error",""))
		if loaded.ok:
			check_eq(loaded.city.building.data,city.building.data)
			check_eq(loaded.city.zone.data,city.zone.data)
			var restored := Simulation.new();root.add_child(restored)
			restored.setup(loaded.city,-1,null,loaded.snapshot);restored.restore(loaded.snapshot)
			check_eq(restored.stats.demand,sim.stats.demand)
			check_eq(restored.stats.tax_agricultural,7)
			check_eq(restored.get_system(&"agriculture").current_lots().size(),0)
			check_eq(restored.rng.state(),sim.rng.state())
			restored.free()
		sim.free()

func test_missing_partial_signed_and_malformed_agriculture_records_preserve_layers() -> void:
	var city := flat_city()
	city.stamp_building(40,40,AgricultureParams.building_id(&"cattle_range"),Zones.AGR_LOW)
	city.stamp_building(50,40,AgricultureParams.building_id(&"feedlot"),Zones.AGR_HIGH)
	var sim := make_simulation(city,-1827)
	var ag := sim.get_system(&"agriculture")
	var layers := var_to_bytes([city.building.data,city.zone.data,city.flags.data,city.funds])
	var shared := sim.rng.state()
	var full: Dictionary = ag.save()
	for data: Dictionary in [{},{"lots":[full.lots[0]]},{"rng_seed":"-9223372036854775807","rng_state":"-1234567890123456789","lots":[null,"bad",{"x":{},"y":40},{"x":40,"y":40,"archetype":"missing","state":"active"}]}]:
		ag.load(data)
		check_eq(ag.current_lots().size(),2,"valid footprints inferred when snapshot is absent, partial or malformed")
		check_eq(var_to_bytes([city.building.data,city.zone.data,city.flags.data,city.funds]),layers)
		check_eq(sim.rng.state(),shared)
		if data.has("rng_seed"):
			check_eq(ag.save().rng_seed,data.rng_seed)
			check_eq(ag.save().rng_state,data.rng_state)
		for lot in ag.save().lots:
			check(lot.x in [40,50] and lot.y==40)
	sim.free()


func test_original_snapshot_precedes_low_adoption_and_lifecycle_continues() -> void:
	var city := flat_city()
	city.stamp_building(40,40,AgricultureParams.building_id(&"sheep_pasture"),Zones.AGR_LOW)
	city.stamp_building(50,40,AgricultureParams.state_id(&"prepared",3),Zones.AGR_LOW)
	var layers := var_to_bytes([city.building.data,city.zone.data])
	var saved := {"systems":{"agriculture":{"raw_demand":1,"rng_seed":"-82","rng_state":"-972",
		"demand_month":-1,"phase_months":[-1,-1],"lots":[
		{"x":40,"y":40,"archetype":"sheep_pasture","state":"active","building_id":AgricultureParams.building_id(&"sheep_pasture"),"zone_kind":Zones.AGR_LOW,"failed_months":2,"last_month":-1},
		{"x":50,"y":40,"archetype":"cattle_range","state":"prepared","building_id":AgricultureParams.state_id(&"prepared",3),"zone_kind":Zones.AGR_LOW,"failed_months":1,"last_month":-1}]}}}
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(city,42,null,saved)
	var ag := sim.get_system(&"agriculture") as AgricultureSystem
	check_eq(var_to_bytes([city.building.data,city.zone.data]),layers)
	var parcels: Array[Dictionary] = ag.call("current_parcels")
	check_eq(parcels.size(),2)
	if parcels.size() == 2:
		check_eq(parcels[0].failed_months,2)
		check_eq(parcels[1].archetype,&"cattle_range","ambiguous prepared code uses original saved archetype")
		check_eq(parcels[1].failed_months,1)
		check_eq(ag.save().lots.size(),0,"canonical lows have no duplicate lifecycle snapshot")
		var before := city.agricultural_parcels.to_dict()
		ag.load(saved.systems.agriculture)
		check_eq(city.agricultural_parcels.to_dict(),before,"repeated restore does not adopt twice")
		check_eq(ag.save().rng_state,"-972","migration does not draw private RNG")
		var ctx := make_context(city,42)
		ctx.stats = sim.stats
		ag.monthly(ctx,0)
		check_eq(city.agricultural_parcels.record(parcels[0].id).state,&"dormant","third failed month remains live after migration")
		check_eq(city.agricultural_parcels.record(parcels[0].id).failed_months,3)
		check_eq(ag.jobs(),0)
	sim.free()


func test_adjacent_legacy_low_farms_keep_individual_identity() -> void:
	var city := flat_city()
	for y in range(20,23):
		for x in range(20,23): city.stamp_building(x,y,AgricultureParams.state_id(&"prepared",1),Zones.AGR_LOW)
	for x in range(20,23): city.building.put(x,19,Buildings.ROAD_FIRST)
	var ctx := make_context(city,1827)
	var ag := AgricultureSystem.new()
	ag.setup(ctx)
	var original := ag.current_parcels()
	check_eq(original.size(),9,"nine original independent farms adopted")
	var shared := ctx.rng.state()
	for month in 12:
		ctx.clock.day = month*GameClock.DAYS_PER_MONTH
		ag.monthly(ctx,0)
		ag.monthly(ctx,1)
		check_eq(ag.current_parcels().size(),9)
		for r in original:
			var current := city.agricultural_parcels.record(r.id)
			check(not current.is_empty())
			if current.is_empty(): continue
			for key in ["id","members","identity_index","origin_index","phase","archetype","mode","layout_seed","stock_units"]:
				check_eq(current[key],r[key],"legacy identity retained: " + key)
	check_eq(ctx.rng.state(),shared)

func test_protected_existing_legacy_farm_migrates_and_round_trips() -> void:
	var city := flat_city()
	city.stamp_building(40,40,AgricultureParams.building_id(&"sheep_pasture"),Zones.AGR_LOW)
	city.flags.set_bits(40,40,TileFlags.LANDMARK,true)
	var old := SaveFormat.encode_city(city)
	old.erase("agricultural_parcels")
	var decoded := SaveFormat.decode_city(old)
	check(decoded.city != null)
	if decoded.city == null: return
	city = decoded.city
	var ctx := make_context(city,1827)
	var ag := AgricultureSystem.new()
	var layers := var_to_bytes([city.building.data,city.zone.data,city.flags.data])
	ag.setup(ctx)
	check_eq(city.agricultural_parcels.records().size(),1,"protected existing farm remains canonical")
	var before := city.agricultural_parcels.to_dict()
	ag.monthly(ctx,0)
	check_eq(city.agricultural_parcels.to_dict(),before,"protected lifecycle stays frozen")
	check_eq(var_to_bytes([city.building.data,city.zone.data,city.flags.data]),layers)
	var path := "user://protected-legacy-parcel.sc2d"
	check_eq(SaveFormat.save(path,city,{"systems":{"agriculture":ag.save()}}),OK)
	var loaded := SaveFormat.load(path)
	check(loaded.ok,loaded.error)
	if loaded.ok:
		check_eq(loaded.city.agricultural_parcels.to_dict(),before)
		check_eq(loaded.city.flags.data,city.flags.data)
	var empty := flat_city()
	empty.zone.put(20,20,Zones.AGR_LOW)
	empty.flags.set_bits(20,20,TileFlags.LANDMARK,true)
	var f := preload("res://tests/helpers/agricultural_parcel_fixture.gd")
	check_eq(empty.agricultural_parcels.put(empty,f.record(1,f.mask([[20,20]]))),ERR_INVALID_DATA,"new parcel cannot occupy protected land")
