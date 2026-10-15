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
