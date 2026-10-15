# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")

func test_shapes_seed_phase_and_copy_round_trip() -> void:
	for members in [F.l_shape(), F.ring(), F.square(2)]:
		var c := flat_city()
		F.zone(c, members)
		var r := F.record(1, members)
		r.layout_seed = -9223372036854775807 - 1
		r.phase = 1
		r.origin_index = 129
		if members == F.square(2):
			r.mode = &"square"
			r.legacy_code = AgricultureParams.building_id(&"grain")
			r.origin_index = members[0]
		check_eq(c.agricultural_parcels.put(c,r),OK)
		var loaded := SaveFormat.decode_city(JSON.parse_string(JSON.stringify(SaveFormat.encode_city(c))))
		check(loaded.city != null, loaded.error)
		if loaded.city == null: continue
		check_eq(loaded.city.agricultural_parcels.to_dict(), c.agricultural_parcels.to_dict())
		var copy: City = loaded.city.duplicate_city()
		var changed: Dictionary = copy.agricultural_parcels.record(1)
		changed.failed_months = 2
		check_eq(copy.agricultural_parcels.put(copy,changed),OK)
		check_eq(c.agricultural_parcels.record(1).failed_months,0)

func test_both_ownership_directions_rejected() -> void:
	var c := flat_city()
	F.zone(c,F.l_shape())
	check_eq(c.agricultural_parcels.put(c,F.record(1,F.l_shape())),OK)
	var doc := SaveFormat.encode_city(c)
	doc.erase("agricultural_parcels")
	check(SaveFormat.decode_city(doc).city == null,"orphan occupancy rejected")
	doc = SaveFormat.encode_city(c)
	c.building.put(20,20,Buildings.NONE)
	doc.layers.building = SaveFormat.encode_bytes(c.building.to_bytes())
	check(SaveFormat.decode_city(doc).city == null,"missing occupancy rejected")

func test_malformed_wire_records_rejected() -> void:
	var c := flat_city()
	F.zone(c,F.l_shape())
	check_eq(c.agricultural_parcels.put(c,F.record(1,F.l_shape())),OK)
	var good := SaveFormat.encode_city(c)
	for field in ["id","phase","failed_months","layout_seed","members","modules","stock_units"]:
		var doc := good.duplicate(true)
		doc.agricultural_parcels.records[0][field] = true
		check(SaveFormat.decode_city(doc).city == null,"reject boolean " + field)
	for seed in ["9223372036854775808","-9223372036854775809","0001","+1","1e2",1.0]:
		var doc := good.duplicate(true)
		doc.agricultural_parcels.records[0].layout_seed = seed
		check(SaveFormat.decode_city(doc).city == null,"reject seed " + str(seed))

func test_invalid_save_preserves_good_file() -> void:
	var c := flat_city()
	F.zone(c,F.l_shape())
	check_eq(c.agricultural_parcels.put(c,F.record(1,F.l_shape())),OK)
	var path := "user://parcel-atomic.sc2d"
	check_eq(SaveFormat.save(path,c),OK)
	var before := FileAccess.get_file_as_bytes(path)
	c.building.put(20,20,Buildings.NONE)
	check_eq(SaveFormat.save(path,c),ERR_INVALID_DATA)
	check_eq(FileAccess.get_file_as_bytes(path),before)

func test_host_rejects_corrupt_replacement_with_city_and_herds_intact() -> void:
	var fixture := preload("res://tests/helpers/host_fixture.gd")
	var host := fixture.make_host(self,"parcel-save-host")
	var city := flat_city()
	city.stamp_building(40,40,AgricultureParams.building_id(&"cattle_range"),Zones.AGR_LOW)
	F.zone(city,F.l_shape())
	check_eq(city.agricultural_parcels.put(city,F.record(1,F.l_shape())),OK)
	host.begin_city(city,{},1827,null)
	host.sim.set_process(false)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.city_view_3d.set_camera_state(Vector3(41,4*CityGeometry3D.HEIGHT,41),0,10)
	await fixture.settle(self,3)
	var livestock := host.city_view_3d.livestock
	livestock.sync_source(host.sim.get_system(&"agriculture"))
	livestock.advance(.05,host.city_view_3d.camera,true)
	check_eq(livestock._herds.size(),1)
	var roots := {}
	for at in livestock._herds: roots[at] = livestock._herds[at].root.get_instance_id()
	var before := var_to_bytes([city.funds,city.building.data,city.zone.data,city.flags.data,city.agricultural_parcels.to_dict()])
	for corruption in ["missing_store","missing_cell","missing_reference"]:
		var doc := {"format":"sc2d","version":2,"stage":"play","city":SaveFormat.encode_city(city),"snapshot":host.sim.snapshot()}
		if corruption == "missing_store": doc.city.erase("agricultural_parcels")
		elif corruption == "missing_cell":
			var copy := city.duplicate_city()
			copy.building.put(20,20,Buildings.NONE)
			doc.city.layers.building = SaveFormat.encode_bytes(copy.building.to_bytes())
		else: doc.snapshot.systems.agriculture.parcel_ids = [999]
		var path := "user://parcel-corrupt-host.sc2d"
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(doc)); file.close()
		check(not host.load_city(path),corruption)
		await fixture.settle(self,2)
		check(host.sim.city == city,"active city reference unchanged")
		check_eq(var_to_bytes([city.funds,city.building.data,city.zone.data,city.flags.data,city.agricultural_parcels.to_dict()]),before)
		check_eq(livestock._herds.size(),roots.size())
		for at in roots: check_eq(livestock._herds[at].root.get_instance_id(),roots[at])
	host.free()
	await process_frame

func test_duplicate_disconnected_foreign_and_nonfinite_wire_rejected() -> void:
	var c := flat_city()
	F.zone(c,F.ring())
	check_eq(c.agricultural_parcels.put(c,F.record(1,F.ring())),OK)
	var good := SaveFormat.encode_city(c)
	for corruption in ["duplicate_id","duplicate_member","disconnected","foreign","fractional","nonfinite","large_count","bad_stock_key","bad_state","bad_mode","bad_code"]:
		var doc := good.duplicate(true)
		var r: Dictionary = doc.agricultural_parcels.records[0]
		match corruption:
			"duplicate_id": doc.agricultural_parcels.records.append(r.duplicate(true))
			"duplicate_member": r.members[1] = r.members[0]
			"disconnected": r.members[1] = 30*128+30
			"foreign":
				var copy := c.duplicate_city()
				copy.zone.put(20,20,Zones.AGR_HIGH)
				doc.layers.zone = SaveFormat.encode_bytes(copy.zone.data)
			"fractional": r.failed_months = 1.5
			"nonfinite": r.modules = [{"key":"farm_shed","at":[INF,0,0],"yaw":0}]
			"large_count": r.members.resize(65)
			"bad_stock_key": r.stock_units = {"00":0}
			"bad_state": r.state = "broken"
			"bad_mode": r.mode = "broken"
			"bad_code": r.legacy_code = 999
		check(SaveFormat.decode_city(doc).city == null,corruption)

func test_active_module_vectors_and_stock_tokens_round_trip() -> void:
	var city := flat_city()
	var members := F.square(4)
	F.zone(city,members)
	var r := F.record(1,members,&"cattle_range",&"active")
	r.layout_seed = 9223372036854775807
	check(not r.modules.is_empty(),"real planned core exercises vector codec")
	check(r.stock_units.values().has(0),"exhausted stock tokens retained")
	check_eq(city.agricultural_parcels.put(city,r),OK)
	var loaded := SaveFormat.decode_city(JSON.parse_string(JSON.stringify(SaveFormat.encode_city(city))))
	check(loaded.city != null,loaded.error)
	if loaded.city != null: check_eq(loaded.city.agricultural_parcels.to_dict(),city.agricultural_parcels.to_dict())

func test_exhausted_legacy_migration_rejects_save_and_host_replacement() -> void:
	var city := flat_city()
	F.zone(city,F.l_shape())
	check_eq(city.agricultural_parcels.put(city,F.record(1,F.l_shape())),OK)
	city.stamp_building(40,40,AgricultureParams.building_id(&"sheep_pasture"),Zones.AGR_LOW)
	var doc := SaveFormat.encode_city(city)
	doc.agricultural_parcels.next_id = 2147483647
	var exhausted := SaveFormat.decode_city(doc)
	check(exhausted.city != null,"valid existing store can exhaust future IDs")
	if exhausted.city == null: return
	var candidate: City = exhausted.city
	var original := var_to_bytes([candidate.building.data,candidate.zone.data,candidate.flags.data,candidate.agricultural_parcels.to_dict()])
	var path := "user://parcel-exhausted-atomic.sc2d"
	check_eq(SaveFormat.save(path,flat_city()),OK)
	var before := FileAccess.get_file_as_bytes(path)
	check_eq(SaveFormat.save(path,candidate),ERR_INVALID_DATA,"failed migration cannot overwrite save")
	check_eq(FileAccess.get_file_as_bytes(path),before)
	check_eq(var_to_bytes([candidate.building.data,candidate.zone.data,candidate.flags.data,candidate.agricultural_parcels.to_dict()]),original)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"format":"sc2d","version":2,"stage":"play","city":doc,"snapshot":{}})); file.close()
	check(not SaveFormat.load(path).ok,"failed migration rejected at native load boundary")
	var fixture := preload("res://tests/helpers/host_fixture.gd")
	var host := fixture.make_host(self,"parcel-exhausted-host")
	host.sim.set_process(false)
	var active := host.sim.city
	var active_before := var_to_bytes([active.funds,active.building.data,active.zone.data,active.flags.data,active.agricultural_parcels.to_dict()])
	check(not host.load_city(path))
	await fixture.settle(self,2)
	check(host.sim.city == active)
	check_eq(var_to_bytes([active.funds,active.building.data,active.zone.data,active.flags.data,active.agricultural_parcels.to_dict()]),active_before)
	host.free()
	await process_frame

func test_failed_adoption_has_no_low_lot_fallback_or_monthly_advancement() -> void:
	var city := flat_city()
	city.stamp_building(40,40,AgricultureParams.building_id(&"sheep_pasture"),Zones.AGR_LOW)
	var doc := SaveFormat.encode_city(city)
	doc.agricultural_parcels.next_id = 2147483647
	city = SaveFormat.decode_city(doc).city
	var ctx := make_context(city,1827)
	var ag := AgricultureSystem.new()
	ag.setup(ctx)
	check(ag.has_method("migration_error"),"migration error must be explicit")
	if ag.has_method("migration_error"): check_eq(ag.call("migration_error"),ERR_OUT_OF_MEMORY)
	var before := var_to_bytes([city.building.data,city.zone.data,city.flags.data,city.agricultural_parcels.to_dict()])
	var snap := ag.save()
	check_eq(SaveFormat.save("user://migration-error-marker.sc2d",flat_city(),{"systems":{"agriculture":snap}}),ERR_INVALID_DATA,"explicit failure marker cannot be saved even with another valid city")
	check_eq(snap.get("migration_error",OK),ERR_OUT_OF_MEMORY)
	check_eq(snap.lots,[],"failed low adoption cannot become secondary schema2 lifecycle")
	ag.monthly(ctx,0)
	check_eq(var_to_bytes([city.building.data,city.zone.data,city.flags.data,city.agricultural_parcels.to_dict()]),before)
	check_eq(ag.save(),snap,"failed system does not advance RNG/month/phase")

func test_successful_migration_preflight_preserves_source_and_original_snapshot() -> void:
	var city := flat_city()
	F.zone(city,F.l_shape())
	check_eq(city.agricultural_parcels.put(city,F.record(1,F.l_shape())),OK)
	city.stamp_building(40,40,AgricultureParams.state_id(&"prepared",3),Zones.AGR_LOW)
	var snapshot := {"systems":{"agriculture":{"rng_seed":"-82","rng_state":"-972","lots":[
		{"x":40,"y":40,"archetype":"sheep_pasture","state":"prepared","building_id":AgricultureParams.state_id(&"prepared",3),"zone_kind":Zones.AGR_LOW,"failed_months":2,"last_month":7}]}}}
	var before := var_to_bytes([city.building.data,city.zone.data,city.flags.data,city.agricultural_parcels.to_dict(),snapshot])
	var path := "user://migration-preflight-success.sc2d"
	check_eq(SaveFormat.save(path,city,snapshot),OK)
	check_eq(var_to_bytes([city.building.data,city.zone.data,city.flags.data,city.agricultural_parcels.to_dict(),snapshot]),before,"save preflight leaves source and snapshot exact")
	var loaded := SaveFormat.load(path)
	check(loaded.ok,loaded.error)
	if not loaded.ok: return
	check_eq(loaded.city.agricultural_parcels.to_dict(),city.agricultural_parcels.to_dict(),"load preflight does not consume next ID")
	var ctx := make_context(loaded.city,1827)
	var ag := AgricultureSystem.new()
	ag.setup_from_save(ctx,loaded.snapshot.systems.agriculture)
	check_eq(ag.migration_error(),OK)
	var migrated := ctx.city.agricultural_parcels.record(2)
	check_eq(migrated.archetype,&"sheep_pasture")
	check_eq(migrated.failed_months,2)
	check_eq(migrated.last_month,7)
	check_eq(ag.save().rng_state,"-972")
	var canonical := ctx.city.agricultural_parcels.to_dict()
	ag.load(loaded.snapshot.systems.agriculture)
	check_eq(ctx.city.agricultural_parcels.to_dict(),canonical,"actual restore adopts only once")
	check_eq(ag.save().lots,[])
