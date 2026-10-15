# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")

func growth() -> RefCounted:
	var path := "res://scripts/sim/agricultural_parcel_growth.gd"
	check(ResourceLoader.exists(path), "bounded parcel growth implementation exists")
	return load(path).new() if ResourceLoader.exists(path) else null

func test_seeded_shapes_fit_domain_without_writes() -> void:
	var g := growth()
	if g == null: return
	var c := flat_city()
	F.zone(c,F.square(24))
	var before := var_to_bytes([c.building.data,c.zone.data,c.agricultural_parcels.to_dict()])
	var square := false
	var irregular := false
	for seed_value in range(1,31):
		var a: Dictionary = g.candidate(c,Vector2i(20,20),&"grain",0,SimRng.from_saved_seed(seed_value))
		var b: Dictionary = g.candidate(c,Vector2i(20,20),&"grain",0,SimRng.from_saved_seed(seed_value))
		check(a.ok)
		check_eq(var_to_bytes(a),var_to_bytes(b),"retained seed %d" % seed_value)
		check(a.evaluations <= 256)
		check_between(a.members.size(),1,64)
		var box := AgriculturalParcels.bounds(a.members)
		check(box.size.x <= 12 and box.size.y <= 12)
		square = square or a.mode == &"square"
		irregular = irregular or a.members.size() < box.get_area()
	check(square, "fitting authored square compositions reachable")
	check(irregular, "stepped generated fields reachable")
	check_eq(var_to_bytes([c.building.data,c.zone.data,c.agricultural_parcels.to_dict()]),before)

func test_l_ring_remnant_and_impossible_pasture() -> void:
	var g := growth()
	if g == null: return
	for members in [F.l_shape(),F.ring(),F.mask([[20,20]])]:
		var c := flat_city()
		F.zone(c,members)
		var result: Dictionary = g.candidate(c,Vector2i(20,20),&"grain",64,SimRng.from_saved_seed(7))
		check(result.ok)
		check_eq(result.members,members,"entire bounded remnant, holes excluded")
	var c := flat_city()
	F.zone(c,F.mask([[20,20],[20,21],[20,22]]))
	check(not g.candidate(c,Vector2i(20,20),&"cattle_range",64,SimRng.from_saved_seed(7)).ok)

func test_monthly_formation_is_canonical_and_budgeted() -> void:
	var c := flat_city()
	F.zone(c,F.square(24))
	for y in range(19,45): c.building.put(19,y,Buildings.ROAD_FIRST)
	var ctx := make_context(c,7)
	var ag := AgricultureSystem.new()
	ctx.systems[&"agriculture"] = ag
	ag.setup(ctx)
	var shared := ctx.rng.state()
	ag.monthly(ctx,0)
	var records := ag.current_parcels()
	check(not records.is_empty())
	for r in records: check(r.mode != &"legacy","new farms must use canonical generated/square records")
	check(ag.has_method("work_counts"),"bounded phase work is observable")
	if ag.has_method("work_counts"):
		var counts: Dictionary = ag.call("work_counts")
		check(counts.actions <= 16 and counts.evaluations <= 4096 and counts.admissions <= 4096 and counts.eligible_cells <= 16384)
	check(ag.projection_count() <= 33)
	check_eq(ctx.rng.state(),shared)
	var saved := var_to_bytes(c.agricultural_parcels.to_dict())
	ag.monthly(ctx,0)
	check_eq(var_to_bytes(c.agricultural_parcels.to_dict()),saved)
	c.building.put(100,100,Buildings.ROAD_FIRST)
	ag.networks_changed(ctx,Rect2i(100,100,1,1))
	check_eq(var_to_bytes(c.agricultural_parcels.to_dict()),saved)
	ctx.systems.clear()

func test_phase_is_stable_across_half_boundary_and_reload() -> void:
	var c := flat_city()
	var members := F.mask([[63,20],[64,20],[65,20]])
	F.zone(c,members)
	var r := F.record(1,members)
	r.phase = 1
	check_eq(c.agricultural_parcels.put(c,r),OK)
	var ctx := make_context(c,7)
	var ag := AgricultureSystem.new()
	ctx.systems[&"agriculture"] = ag
	ag.setup(ctx)
	ag.monthly(ctx,0)
	check_eq(c.agricultural_parcels.record(1).last_month,-1)
	ag.monthly(ctx,1)
	check_eq(c.agricultural_parcels.record(1).last_month,0)
	var loaded := SaveFormat.decode_city(JSON.parse_string(JSON.stringify(SaveFormat.encode_city(c))))
	check(loaded.city != null,loaded.error)
	if loaded.city == null:
		ctx.systems.clear()
		return
	var copy: City = loaded.city
	var restored := AgricultureSystem.new()
	var other := make_context(copy,7)
	other.systems[&"agriculture"] = restored
	restored.setup_from_save(other,ag.save())
	var before := var_to_bytes(copy.agricultural_parcels.to_dict())
	restored.monthly(other,1)
	check_eq(var_to_bytes(copy.agricultural_parcels.to_dict()),before)
	check_eq(copy.agricultural_parcels.to_dict(),c.agricultural_parcels.to_dict(),"native codec retains every canonical scalar/member/module")
	ctx.systems.clear()
	other.systems.clear()

func test_extension_preserves_members_modules_seed_and_phase() -> void:
	var g := growth()
	if g == null: return
	var c := flat_city()
	var initial := F.mask([[64,20],[65,20],[64,21],[65,21]])
	F.zone(c,initial)
	var r := F.record(1,initial,&"grain",&"active")
	r.target_area = 8
	check_eq(c.agricultural_parcels.put(c,r),OK)
	F.zone(c,F.mask([[63,20],[63,21],[62,20],[62,21]]))
	var before := var_to_bytes(c.agricultural_parcels.to_dict())
	var result: Dictionary = g.extension(c,c.agricultural_parcels.record(1),SimRng.from_saved_seed(12))
	check(result.ok)
	check_eq(result.record.members.size(),8)
	for i in initial: check(i in result.record.members)
	check_eq(result.record.modules,r.modules)
	check_eq(result.record.layout_seed,r.layout_seed)
	check_eq(result.record.phase,1)
	check_eq(result.record.origin_index,r.origin_index)
	check_eq(var_to_bytes(c.agricultural_parcels.to_dict()),before)
	check_eq(c.agricultural_parcels.put(c,result.record),OK)
	var source := F.source(c)
	source.ag.monthly(source.ctx,0)
	check_eq(c.agricultural_parcels.record(1).last_month,-1,"westward bounds do not change saved phase")
	source.ag.monthly(source.ctx,1)
	var once := var_to_bytes(c.agricultural_parcels.to_dict())
	source.ag.monthly(source.ctx,0)
	source.ag.monthly(source.ctx,1)
	check_eq(var_to_bytes(c.agricultural_parcels.to_dict()),once)
	source.ctx.systems.clear()

func test_square_extension_converts_once_and_legacy_remains_fixed() -> void:
	var g := growth()
	if g == null: return
	var c := flat_city()
	F.zone(c,F.square(4))
	var r := F.record(1,F.square(2),&"grain",&"active")
	r.mode = &"square"
	r.modules = []
	r.legacy_code = AgricultureParams.building_id(&"grain")
	r.target_area = 8
	check_eq(c.agricultural_parcels.put(c,r),OK)
	var result: Dictionary = g.extension(c,r,SimRng.from_saved_seed(12))
	check(result.ok)
	check_eq(result.record.mode,&"generated")
	check_eq(result.record.legacy_code,0)
	check(not result.record.modules.is_empty())
	check_eq(c.agricultural_parcels.put(c,result.record),OK)
	var legacy := flat_city()
	legacy.stamp_building(20,20,AgricultureParams.building_id(&"grain"),Zones.AGR_LOW)
	var source := F.source(legacy)
	var old: Dictionary = source.ag.current_parcels()[0]
	F.zone(legacy,F.square(5,Vector2i(22,20)))
	check(not g.extension(legacy,old,SimRng.from_saved_seed(12)).ok)
	check_eq(legacy.agricultural_parcels.record(old.id).members,old.members)
	source.ctx.systems.clear()

func test_member_barriers_and_available_id_do_not_reserve() -> void:
	var g := growth()
	if g == null: return
	var c := flat_city()
	F.zone(c,F.square(5))
	for y in range(20,25): c.building.put(22,y,Buildings.ROAD_FIRST)
	c.flags.set_bits(21,21,TileFlags.LANDMARK,true)
	c.terrain.put(20,22,Terrain.SLOPE_N)
	var a: Dictionary = g.candidate(c,Vector2i(20,20),&"grain",64,SimRng.from_saved_seed(7))
	check(a.ok)
	for i in a.members:
		check(i%128 < 22)
		check(i != 21+21*128 and i != 20+22*128)
	var source := F.source(c)
	var before := var_to_bytes(c.agricultural_parcels.to_dict())
	check_eq(c.agricultural_parcels.available_id(),1)
	check_eq(c.agricultural_parcels.available_id(),1)
	check_eq(var_to_bytes(c.agricultural_parcels.to_dict()),before)
	source.ctx.systems.clear()

func test_lot_views_include_authoritative_members_and_capacity() -> void:
	var c := flat_city()
	F.zone(c,F.l_shape())
	check_eq(c.agricultural_parcels.put(c,F.record(1,F.l_shape(),&"alfalfa",&"active")),OK)
	c.stamp_building(40,40,AgricultureParams.building_id(&"greenhouse"),Zones.AGR_HIGH)
	var source := F.source(c)
	var jobs: Dictionary = source.ag.parcel_jobs()
	check_eq(jobs[1],4)
	check_eq(source.ag.inspect_tile(Vector2i(20,21)).jobs,4)
	for lot in source.ag.current_lots():
		for key in ["source_key","parcel_id","members","mode","origin","revision"]:
			check(lot.has(key),"compatible lot view carries %s" % key)
	source.ctx.systems.clear()

func test_store_layout_proofs_keep_live_guards_and_static_validation() -> void:
	var c := flat_city()
	F.zone(c,F.square(4))
	var r := F.record(1,F.square(4),&"cattle_range",&"active")
	check_eq(c.agricultural_parcels.put(c,r),OK)
	var checks: Variant = c.agricultural_parcels.get("_layout_validations")
	check(checks is int,"store records real layout validations")
	if not checks is int: return
	for month in 3:
		r = c.agricultural_parcels.record(1)
		r.last_month = month
		r.failed_months = month
		check_eq(c.agricultural_parcels.put(c,r),OK)
	check_eq(c.agricultural_parcels.get("_layout_validations"),checks,"counter-only changes reuse detached proof")
	var detached := c.duplicate_city()
	var cloned_checks: int = detached.agricultural_parcels.get("_layout_validations")
	r.last_month = 4
	check_eq(detached.agricultural_parcels.put(detached,r),OK)
	check_eq(detached.agricultural_parcels.get("_layout_validations"),cloned_checks,"safe preview clone retains valid layout proof")
	var bad := c.agricultural_parcels.record(1)
	bad.modules[0].at = Vector3(1000,.14,1000)
	check_eq(c.agricultural_parcels.put(c,bad),ERR_INVALID_DATA)
	check(not AgriculturalParcels.validate(c,[bad]).ok,"full static validation still checks layout")
	check_gt(c.agricultural_parcels.get("_layout_validations"),checks)
	for kind in ["ground","code","protection"]:
		var copy := c.duplicate_city()
		if kind == "ground": copy.set_heights(20,20,5,0)
		elif kind == "code": copy.building.put(20,20,Buildings.NONE)
		else: copy.flags.set_bits(20,20,TileFlags.LANDMARK,true)
		check_eq(copy.agricultural_parcels.put(copy,r),ERR_INVALID_DATA,"cached proof retains raw %s guard" % kind)

func test_monthly_twin_seed_bank_and_shape_work_bound() -> void:
	var saw_square := false
	var saw_irregular := false
	var saw_pasture := false
	for seed_value in range(1,31):
		var first: PackedByteArray
		for twin in 2:
			var c := flat_city()
			F.zone(c,F.square(24))
			for y in range(19,45): c.building.put(19,y,Buildings.ROAD_FIRST)
			var ctx := make_context(c,seed_value)
			var ag := AgricultureSystem.new()
			ctx.systems[&"agriculture"] = ag
			ag.setup(ctx)
			var shared := ctx.rng.state()
			ag.monthly(ctx,0)
			check_eq(ctx.rng.state(),shared)
			var snapshot := var_to_bytes([c.agricultural_parcels.to_dict(),ag.save()])
			if twin == 0: first = snapshot
			else: check_eq(snapshot,first,"automatic development seed %d" % seed_value)
			var counts := ag.work_counts()
			check(counts.actions <= 16 and counts.evaluations <= 4096 and counts.admissions <= 4096 and counts.eligible_cells == 16384)
			check(ag.projection_count() <= 33)
			for r in ag.current_parcels():
				saw_square = saw_square or r.mode == &"square"
				saw_irregular = saw_irregular or r.members.size() < AgriculturalParcels.bounds(r.members).get_area()
				if r.archetype in [&"cattle_range",&"sheep_pasture"]:
					saw_pasture = true
					check(r.members.size() >= 4)
					check(AgriculturalParcelGeometry.plan(r).ok,"formed pasture has actual connected clearance")
			ctx.systems.clear()
	check(saw_square and saw_irregular and saw_pasture)

func test_candidate_admission_counter_includes_seed_tile() -> void:
	var g := growth()
	if g == null: return
	var c := flat_city()
	F.zone(c,F.l_shape())
	var result: Dictionary = g.candidate(c,Vector2i(20,20),&"grain",64,SimRng.from_saved_seed(7))
	check(result.ok)
	check_eq(result.admissions,result.members.size(),"seed is an admission, not free work")

func test_cut_unsafe_pasture_recovers_its_identity_and_saved_continuation() -> void:
	var fixtures: SceneTree = load("res://tests/test_agricultural_parcel_services.gd").new()
	var f: Dictionary = fixtures.supplied_farm();fixtures.free()
	var c: City = f.city
	check(c.remove_agricultural_cells(c.agricultural_parcels.record(1).members).ok)
	var initial := F.record(2,F.square(2),&"cattle_range",&"active")
	initial.target_area = 8
	F.zone(c,initial.members);check_eq(c.agricultural_parcels.put(c,initial),OK)
	check(c.remove_agricultural_cells(F.mask([[21,21]])).ok)
	# Keep the removed cell unavailable. The remnant must acquire different land.
	c.zone.put(21,21,Zones.NONE)
	var remnant := c.agricultural_parcels.record(2)
	check_eq(remnant.members.size(),3);check_eq(remnant.state,&"prepared")
	f.ag.networks_changed(f.ctx,Rect2i(19,19,5,5))
	f.ag.monthly(f.ctx,0)
	check_eq(c.agricultural_parcels.record(2).members,remnant.members,"isolated unsafe remnant stays nonproductive")
	check_eq(c.agricultural_parcels.record(2).state,&"prepared")
	F.zone(c,F.mask([[22,20],[23,20],[22,21],[23,21],[22,22]]))
	for y in range(19,23):
		for x in range(20,24): c.underground.put(x,y,UtilityParams.pipe_code(15))
	c.facilities[Vector2i(20,19)].output = 100
	f.water.reallocate_established(f.ctx,Rect2i(0,0,128,128))
	f.ag.networks_changed(f.ctx,Rect2i(19,19,5,5))
	var decoded := SaveFormat.decode_city(JSON.parse_string(JSON.stringify(SaveFormat.encode_city(c))))
	check(decoded.city != null,decoded.error)
	if decoded.city == null: f.ctx.systems.clear();return
	var twin_ctx := make_context(decoded.city,7)
	var twin := AgricultureSystem.new()
	twin_ctx.systems = {&"agriculture":twin,&"water":WaterSystem.new(),&"power":PowerSystem.new()}
	twin.setup_from_save(twin_ctx,f.ag.save())
	f.ctx.clock.day = GameClock.DAYS_PER_MONTH;twin_ctx.clock.day = f.ctx.clock.day
	f.ag.monthly(f.ctx,0);twin.monthly(twin_ctx,0)
	var after := c.agricultural_parcels.record(2)
	check_gt(after.members.size(),3,"same remnant acquires newly available acreage")
	check_eq(after.state,&"active","final safe full-service footprint recovers")
	for field in ["id","identity_index","origin_index","layout_seed","phase","target_area"]: check_eq(after[field],remnant[field])
	for index in remnant.stock_units: check_eq(after.stock_units[index],remnant.stock_units[index],"retained tokens never refill")
	check_eq(c.agricultural_parcels.to_dict(),decoded.city.agricultural_parcels.to_dict())
	check_eq(f.ag.save(),twin.save(),"saved private RNG and phases continue exactly")
	check(f.ag.work_counts().actions<=16 and f.ag.work_counts().evaluations<=4096 and f.ag.projection_count()<=33)
	f.ctx.systems.clear();twin_ctx.systems.clear()

func test_waiting_recovery_can_retain_partial_acreage_without_refilling_tokens() -> void:
	var c := flat_city()
	var r := F.record(1,F.mask([[20,20]]),&"cattle_range",&"dormant")
	r.stock_units[r.members[0]] = 0;r.failed_months = 3;r.target_area = 8
	F.zone(c,r.members);check_eq(c.agricultural_parcels.put(c,r),OK)
	c.building.put(19,20,Buildings.ROAD_FIRST)
	var source := F.source(c)
	for month in 2:
		F.zone(c,F.mask([[21+month,20]]))
		source.ctx.clock.day = month*GameClock.DAYS_PER_MONTH
		source.ag.monthly(source.ctx,0)
		var current := c.agricultural_parcels.record(1)
		check_eq(current.members.size(),month+2,"partial unsafe acreage waits under the retained identity")
		check_eq(current.stock_units[r.members[0]],0,"old exhausted entitlement stays exhausted")
		check_eq(current.failed_months,3);check_eq(current.state,&"dormant")
		check_eq(current.layout_seed,r.layout_seed);check_eq(current.phase,r.phase)
		check_eq(source.ag.jobs(),0)
	source.ctx.systems.clear()


func _add_unserved_waiting_farms(c: City) -> void:
	for i in 16:
		var at := Vector2i(5+(i%8)*6,50+(i/8)*5)
		c.stamp_building(at.x,at.y,AgricultureParams.state_id(&"prepared",1),Zones.AGR_HIGH)
		c.building.put(at.x,at.y-1,Buildings.ROAD_FIRST)


func _fair_growth_fixture(kind: int) -> Dictionary:
	var fixtures: SceneTree = load("res://tests/test_agricultural_parcel_services.gd").new()
	var f: Dictionary = fixtures.supplied_farm();fixtures.free()
	_add_unserved_waiting_farms(f.city)
	# Retain an active supplied field that competes for extension work.
	F.zone(f.city,F.mask([[21,20],[22,20],[23,20]]))
	f.city.facilities[Vector2i(20,19)].output = 100
	f.city.facilities[Vector2i(16,16)].capacity = 100
	for x in range(20,27):
		f.city.underground.put(x,20,UtilityParams.pipe_code(15))
		f.city.building.put(x,21,Buildings.ROAD_FIRST)
	for y in range(19,22):
		for x in range(24,27):
			f.city.zone.put(x,y,kind)
			f.city.underground.put(x,y,UtilityParams.pipe_code(15))
	# Farm/pump network conducts power to either density's new district.
	for x in range(20,27): f.city.building.put(x,18,Buildings.POWER_LINE_FIRST)
	f.water.reallocate_established(f.ctx,Rect2i(0,0,128,128))
	f.power.reallocate_established(f.ctx,Rect2i(0,0,128,128))
	f.ag.networks_changed(f.ctx,Rect2i(0,0,64,64))
	return f


func test_waiting_farms_cannot_starve_either_density_or_healthy_extension() -> void:
	for kind in [Zones.AGR_LOW,Zones.AGR_HIGH]:
		var f := _fair_growth_fixture(kind)
		var decoded := SaveFormat.decode_city(JSON.parse_string(JSON.stringify(SaveFormat.encode_city(f.city))))
		check(decoded.city != null,decoded.error)
		if decoded.city == null: f.ctx.systems.clear();continue
		var twin_ctx := make_context(decoded.city,7)
		var twin := AgricultureSystem.new()
		twin_ctx.systems = {&"agriculture":twin,&"water":WaterSystem.new(),&"power":PowerSystem.new()}
		twin.setup_from_save(twin_ctx,f.ag.save())
		var shared: int = f.ctx.rng.state()
		var prepared := false
		var active := false
		for month in 4:
			f.ctx.clock.day = month*GameClock.DAYS_PER_MONTH;twin_ctx.clock.day = f.ctx.clock.day
			f.ag.monthly(f.ctx,0);twin.monthly(twin_ctx,0)
			for lot in f.ag.current_lots():
				if lot.rect.position.x >= 24 and lot.rect.position.y < 22:
					prepared = true
					active = active or lot.state == &"active"
			var counts: Dictionary = f.ag.work_counts()
			check(counts.actions<=16 and counts.evaluations<=4096 and counts.admissions<=4096)
			check(f.ag.projection_count()<=33)
			check_eq(f.ctx.rng.state(),shared,"growth keeps shared RNG untouched")
			check_eq(f.city.agricultural_parcels.to_dict(),decoded.city.agricultural_parcels.to_dict())
			check_eq(f.ag.save(),twin.save(),"fair work continues exactly after save/restore")
		check(prepared,"serviced density %d prepares despite sixteen waiting farms" % kind)
		check(active,"serviced density %d activates within four scheduled months" % kind)
		check_gt(f.city.agricultural_parcels.record(1).members.size(),1,"healthy field gets an extension opportunity")
		for i in 16:
			var at := Vector2i(5+(i%8)*6,50+(i/8)*5)
			check_eq(f.ag.inspect_tile(at).state,&"prepared","unconnected competitors remain waiting")
		f.ctx.systems.clear();twin_ctx.systems.clear()


func test_contending_new_densities_each_get_a_preparation_turn() -> void:
	var f := _fair_growth_fixture(Zones.AGR_LOW)
	for y in range(20,23):
		for x in range(32,35): f.city.zone.put(x,y,Zones.AGR_HIGH)
	f.city.building.put(32,19,Buildings.ROAD_FIRST)
	var formed := {}
	for month in 2:
		f.ctx.clock.day = month*GameClock.DAYS_PER_MONTH
		f.ag.monthly(f.ctx,0)
		for lot in f.ag.current_lots():
			if lot.anchor.x >= 24 and lot.anchor.y < 24: formed[lot.zone_kind] = true
	check(formed.has(Zones.AGR_LOW),"low density gets one of the two bounded preparation turns")
	check(formed.has(Zones.AGR_HIGH),"high density gets one of the two bounded preparation turns")
	check_gt(f.city.agricultural_parcels.record(1).members.size(),1)
	f.ctx.systems.clear()
