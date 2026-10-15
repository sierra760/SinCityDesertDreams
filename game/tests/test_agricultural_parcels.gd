# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")
const STORE := "res://scripts/core/agricultural_parcels.gd"
const PARAMS := "res://scripts/sim/data/agricultural_parcel_params.gd"
const CAPACITY := "res://scripts/sim/agricultural_parcel_capacity.gd"

func available() -> bool:
	var ok := ResourceLoader.exists(STORE) and ResourceLoader.exists(PARAMS) and ResourceLoader.exists(CAPACITY)
	check(ok, "authoritative parcel store, params and allocator must exist")
	return ok

func test_l_shape_is_not_its_bounding_box() -> void:
	if not available(): return
	var city = flat_city()
	var m := F.mask([[20,20],[21,20],[20,21]])
	F.zone(city,m)
	check_eq(city.agricultural_parcels.put(city,F.record(1,m)),OK)
	check_eq(city.agricultural_parcels.id_at(Vector2i(21,21)),0)
	check_eq(city.building_at(21,21),Buildings.NONE)
	check_eq(city.anchor_of(20,21),Vector2i(20,21))
	check_eq(load(STORE).bounds(m), Rect2i(20,20,2,2))
	var copy = city.duplicate_city()
	check_eq(copy.agricultural_parcels.to_dict(),city.agricultural_parcels.to_dict())
	check(copy.agricultural_parcels != city.agricultural_parcels)

func test_invalid_members_are_atomic() -> void:
	if not available(): return
	var city = flat_city()
	var bad := [F.mask([[20,20],[20,20]]), F.mask([[20,20],[21,21]]),
		F.mask([[20,20],[22,20]]), PackedInt32Array([-1]), PackedInt32Array([16384]),
		F.mask([[0,0]]), F.mask([[126,20]]), F.mask([[20,127]])]
	var long := PackedInt32Array()
	for x in range(20,33): long.append(20*128+x)
	bad.append(long)
	var big := PackedInt32Array()
	for y in range(20,29):
		for x in range(20,28): big.append(y*128+x)
	bad.append(big)
	for members in bad:
		F.zone(city,members)
		var before = city.building.data.duplicate()
		check_ne(city.agricultural_parcels.put(city,F.record(1,members)), OK)
		check_eq(city.agricultural_parcels.records(), [])
		check_eq(city.building.data,before)
	check_eq(city.agricultural_parcels.id_at(Vector2i(-1,20)),0)
	check_eq(city.agricultural_parcels.id_at(Vector2i(128,20)),0)
	check_eq(load(STORE).cell(Vector2i.ZERO),0)
	check_eq(load(STORE).tile(0),Vector2i.ZERO)

func test_members_are_sorted_and_getters_detached() -> void:
	if not available(): return
	var city = flat_city()
	var m := PackedInt32Array([2708,2581,2580])
	F.zone(city,m)
	var r := F.record(7,m)
	r.identity_index = 2580
	check_eq(city.agricultural_parcels.put(city,r),OK)
	r.members[0] = 3
	var got: Dictionary = city.agricultural_parcels.record(7)
	check_eq(got.members,PackedInt32Array([2580,2581,2708]))
	got.modules.append({"key": &"fake"})
	got.stock_units[2580] = 100
	var all: Array = city.agricultural_parcels.records()
	all[0].members[0] = 0
	check_eq(city.agricultural_parcels.record(7).members[0],2580)
	check_eq(city.agricultural_parcels.record(7).modules,[])
	check_eq(city.agricultural_parcels.record(7).stock_units,{})

func test_overlap_and_bad_land_reject_without_overwrite() -> void:
	if not available(): return
	var city = flat_city()
	var m := F.mask([[20,20],[21,20]])
	F.zone(city,m)
	check_eq(city.agricultural_parcels.put(city,F.record(1,m)),OK)
	check_ne(city.agricultural_parcels.put(city,F.record(2,m)),OK)
	check_eq(city.agricultural_parcels.id_at(Vector2i(20,20)),1)
	for kind in ["unzone","water","slope","height","building"]:
		var c = flat_city()
		F.zone(c,m)
		match kind:
			"unzone": c.zone.put(20,20,Zones.AGR_HIGH)
			"water": c.terrain.put(20,20,Terrain.make(Terrain.FLAT,Terrain.SURFACE))
			"slope": c.terrain.put(20,20,Terrain.SLOPE_N)
			"height": c.set_heights(20,20,5)
			"building": c.building.put(20,20,Buildings.COAL_PLANT)
		check_ne(c.agricultural_parcels.put(c,F.record(1,m)),OK,kind)

func test_record_numbers_and_shape_are_validated_before_casts() -> void:
	if not available(): return
	var c = flat_city()
	var m := F.mask([[20,20]])
	F.zone(c,m)
	for pair in [["id",0],["id",1.5],["id",2147483648],["id","1"],
		["identity_index",2581],["origin_index",-1],["phase",2],["height",4.5],
		["target_area",65],["failed_months",-1],["last_month",-2],
		["revision",0],["layout_seed",1.5],["archetype",&"feedlot"],
		["state",&"unknown"],["mode",&"unknown"],["modules",{}]]:
		var r := F.record(1,m)
		r[pair[0]] = pair[1]
		check_ne(c.agricultural_parcels.put(c,r),OK,str(pair))

func test_cardinal_components_do_not_wrap_or_join_diagonals() -> void:
	if not available(): return
	check_eq(load(STORE).components(PackedInt32Array([128,127,0,129,258])),
		[PackedInt32Array([0,128,129]),PackedInt32Array([127]),PackedInt32Array([258])])

func test_cell_codes_have_zero_jobs_and_exact_active_loads() -> void:
	if not available(): return
	var p = load(PARAMS)
	var keys := [&"vegetables",&"alfalfa",&"grain",&"cattle_range",&"sheep_pasture"]
	for i in keys.size():
		var id: int = p.cell_id(keys[i],&"active")
		check_eq(id,282+i)
		check(load("res://scripts/core/buildings.gd").is_agricultural_cell(id))
		check_eq(Buildings.size(id),Vector2i.ONE)
		check_eq(AgricultureParams.jobs_of(id),0)
		check_eq(AgricultureParams.water_load(id),[3,3,1,1,1][i])
		check_eq(AgricultureParams.power_load(id),0)
	for state in [&"prepared",&"dormant"]:
		var id: int = p.cell_id(&"grain",state)
		check_eq(id,287 if state == &"prepared" else 288)
		check_eq(AgricultureParams.water_load(id),0)
	check(not load("res://scripts/core/buildings.gd").is_agricultural_cell(281))
	check_eq(p.cell_id(&"missing",&"active"),0)
	check_eq(p.job_units(&"alfalfa",1),54)
	check_eq(p.stock_rate(&"sheep_pasture"),10)

func test_largest_remainders_allocate_three_jobs_stably() -> void:
	if not available(): return
	var a := F.record(1,F.mask([[20,20]]),&"alfalfa",&"active")
	var b := F.record(2,F.mask([[22,20]]),&"alfalfa",&"active")
	var allocator = load(CAPACITY)
	var rows: Array[Dictionary] = [a,b]
	var before := rows.duplicate(true)
	check_eq(allocator.allocate(rows),{"jobs":3,"by_id":{1:2,2:1},"active_count":2})
	rows.reverse()
	check_eq(allocator.allocate(rows),{"jobs":3,"by_id":{1:2,2:1},"active_count":2})
	check_eq(a,before[0])
	b.state = &"dormant"
	check_eq(allocator.allocate(rows),{"jobs":1,"by_id":{1:1,2:0},"active_count":1})

func test_legacy_capacity_keeps_canonical_jobs_and_stock() -> void:
	if not available(): return
	var r := F.record(1,F.mask([[20,20],[21,20],[20,21],[21,21]]),&"alfalfa",&"active")
	r.mode = &"legacy"
	r.modules = []
	r.legacy_code = 267
	var rows: Array[Dictionary] = [r]
	check_eq(load(CAPACITY).allocate(rows),{"jobs":6,"by_id":{1:6},"active_count":1})

func test_stock_entitlement_is_capped_and_survives_state_and_growth() -> void:
	if not available(): return
	var c = flat_city()
	var members := PackedInt32Array()
	for y in range(20,24):
		for x in range(20,24): members.append(y*128+x)
	F.zone(c,members)
	var r := F.record(1,members,&"cattle_range",&"active")
	check_eq(c.agricultural_parcels.put(c,r),OK)
	var units: Dictionary = c.agricultural_parcels.record(1).stock_units
	check_eq(units.values().reduce(func(a,b): return a+b,0),108)
	for i in units: check_between(units[i],0,8)
	r = c.agricultural_parcels.record(1)
	r.state = &"dormant"
	check_eq(c.agricultural_parcels.put(c,r),OK)
	check_eq(c.agricultural_parcels.record(1).stock_units,units)
	check_eq(load(CAPACITY).allocate(c.agricultural_parcels.records()).jobs,0)
	var invalid := r.duplicate(true)
	invalid.stock_units[members[0]] = 9
	check_ne(c.agricultural_parcels.put(c,invalid),OK)
	invalid = r.duplicate(true)
	invalid.stock_units[0] = 1
	check_ne(c.agricultural_parcels.put(c,invalid),OK)

func test_snapshot_serializes_seed_and_is_detached() -> void:
	if not available(): return
	var c = flat_city()
	var m := F.mask([[20,20],[21,20]])
	F.zone(c,m)
	var r := F.record(1,m)
	r.layout_seed = -9223372036854775807
	check_eq(c.agricultural_parcels.put(c,r),OK)
	var encoded: Dictionary = c.agricultural_parcels.to_dict()
	check_eq(encoded.schema,1)
	check_eq(encoded.next_id,2)
	check_eq(encoded.records[0].layout_seed,"-9223372036854775807")
	check_eq(encoded.records[0].members,[2580,2581])
	encoded.records[0].members[0] = 0
	check_eq(c.agricultural_parcels.record(1).members[0],2580)

func test_replacement_cannot_mint_tokens_or_reset_identity() -> void:
	if not available(): return
	var c = flat_city()
	var m := F.mask([[20,20],[21,20],[20,21],[21,21]])
	F.zone(c,m)
	var r := F.record(1,m,&"cattle_range",&"active")
	r.stock_units[2580] = 2
	check_eq(c.agricultural_parcels.put(c,r),OK)
	for pair in [["identity_index",2581],["origin_index",2581],["phase",1],["layout_seed",2],
		["archetype",&"sheep_pasture"],["members",PackedInt32Array([2580,2581,2708])]]:
		var invalid := r.duplicate(true)
		invalid[pair[0]] = pair[1]
		check_ne(c.agricultural_parcels.put(c,invalid),OK,str(pair))
	var mint := r.duplicate(true)
	mint.stock_units[2580] = 8
	check_ne(c.agricultural_parcels.put(c,mint),OK)
	var grown := r.duplicate(true)
	grown.members.append(2582)
	grown.stock_units[2582] = 8
	F.zone(c,PackedInt32Array([2582]))
	check_eq(c.agricultural_parcels.put(c,grown),OK)
	check_eq(c.agricultural_parcels.record(1).stock_units[2580],2)
	check_eq(c.agricultural_parcels.record(1).stock_units[2582],8)

func test_change_signal_and_city_copy_preserve_revisions() -> void:
	if not available(): return
	var c = flat_city()
	var a := F.mask([[20,20]])
	var b := F.mask([[21,20]])
	F.zone(c,a)
	F.zone(c,b)
	var changes: Array = []
	c.agricultural_parcels.changed.connect(func(change): changes.append(change))
	check_eq(c.agricultural_parcels.put(c,F.record(1,a)),OK)
	check_eq(c.agricultural_parcels.put(c,F.record(2,b)),OK)
	check_eq(changes.size(),2)
	check_eq(changes[1].neighbor_ids,[1])
	check_eq(changes[1].old_bounds,Rect2i())
	check_eq(changes[1].new_bounds,Rect2i(21,20,1,1))
	check_eq(c.agricultural_parcels.revision,2)
	var copy = c.duplicate_city()
	check_eq(copy.agricultural_parcels.revision,2)
	var next: Dictionary = copy.agricultural_parcels.record(1)
	next.state = &"active"
	next.modules = AgriculturalParcelGeometry.plan(next).modules
	check_eq(copy.agricultural_parcels.put(copy,next),OK)
	check_eq(c.agricultural_parcels.record(1).state,&"prepared")
	check_eq(c.building_at(20,20),287)
	check_eq(copy.building_at(20,20),284)

func test_id_exhaustion_does_not_wrap() -> void:
	if not available(): return
	var c = flat_city()
	var m := F.mask([[20,20]])
	F.zone(c,m)
	check_ne(c.agricultural_parcels.put(c,F.record(2147483647,m)),OK)
	check_eq(c.agricultural_parcels.to_dict().next_id,1)

func test_invalid_stock_values_reject_before_casting() -> void:
	if not available(): return
	var c = flat_city()
	var m := F.mask([[20,20]])
	F.zone(c,m)
	for value in [-1,1.5,"1",9]:
		var r := F.record(1,m,&"cattle_range")
		r.stock_units[2580] = value
		check_ne(c.agricultural_parcels.put(c,r),OK)
	var crop := F.record(1,m)
	crop.stock_units[2580] = 1
	check_ne(c.agricultural_parcels.put(c,crop),OK)

func test_stock_allocator_retains_zero_and_never_refills_old_cells() -> void:
	if not available(): return
	var p = load(PARAMS)
	var m := F.mask([[20,20],[21,20],[20,21]])
	check_eq(p.stock_units(&"cattle_range",m),{2580:8,2581:8,2708:8})
	check_eq(p.stock_units(&"cattle_range",m,{2580:0,2581:2}),{2580:0,2581:2,2708:8})
	check_eq(p.stock_units(&"cattle_range",PackedInt32Array([2581]),{2580:8,2581:0}),{2581:0})
	check_eq(p.stock_units(&"grain",m),{})
	var big := PackedInt32Array()
	for x in range(20,36): big.append(2580+x-20)
	var tokens: Dictionary = p.stock_units(&"sheep_pasture",big)
	check_eq(tokens.values().reduce(func(a,b): return a+b,0),108)
	check_eq(tokens[2590],8)
	check_eq(tokens[2591],0)

func test_legacy_stock_cannot_lose_canonical_entitlement() -> void:
	if not available(): return
	var c = flat_city()
	var m := F.mask([[20,20],[21,20],[22,20],[20,21],[21,21],[22,21],[20,22],[21,22],[22,22]])
	F.zone(c,m)
	var r := F.record(1,m,&"cattle_range",&"active")
	r.mode = &"legacy"
	r.modules = []
	r.legacy_code = 269
	var invalid := r.duplicate(true)
	invalid.stock_units[2580] = 6
	check_ne(c.agricultural_parcels.put(c,invalid),OK)
	check_eq(c.agricultural_parcels.put(c,r),OK)
	check_eq(c.agricultural_parcels.record(1).stock_units.values().reduce(func(a,b): return a+b,0),72)

func test_opaque_extra_fields_cannot_enter_detached_snapshots() -> void:
	if not available(): return
	for is_module in [false,true]:
		var c = flat_city()
		var m := F.mask([[20,20]])
		F.zone(c,m)
		var r := F.record(1,m)
		if is_module:
			r.modules = [{"key":&"trough","at":Vector3.ZERO,"yaw":0,"opaque":RefCounted.new()}]
		else:
			r.opaque = RefCounted.new()
		check_ne(c.agricultural_parcels.put(c,r),OK)
		check_eq(c.agricultural_parcels.records(),[])

func test_adjacent_legacy_farms_keep_corners_and_whole_lot_anchors() -> void:
	if not available(): return
	var c = flat_city()
	var farms: Array[Dictionary] = []
	for index in 2:
		var x := 20 + index * 3
		c.stamp_building(x,20,269,Zones.AGR_LOW)
		var members := PackedInt32Array()
		for y in range(20,23):
			for xx in range(x,x+3): members.append(y*128+xx)
		var r := F.record(index+1,members,&"cattle_range",&"active")
		r.mode = &"legacy"
		r.modules = []
		r.legacy_code = 269
		farms.append(r)
	var zones_before: PackedByteArray = c.zone.data.duplicate()
	for r in farms: check_eq(c.agricultural_parcels.put(c,r),OK)
	check(c.zone.data == zones_before,"adoption must preserve every legacy zone byte")
	for r in farms:
		var expected := Vector2i(20+(r.id-1)*3,20)
		for i in r.members: check_eq(c.anchor_of(i%128,i/128),expected)
	for state in [&"prepared",&"dormant",&"active"]:
		for id in [1,2]:
			var r: Dictionary = c.agricultural_parcels.record(id)
			r.state = state
			r.legacy_code = 269 if state == &"active" else AgricultureParams.state_id(state,3)
			check_eq(c.agricultural_parcels.put(c,r),OK)
		check(c.zone.data == zones_before,"lifecycle update must preserve legacy corners")
		for r in farms:
			var expected := Vector2i(20+(r.id-1)*3,20)
			for i in r.members: check_eq(c.anchor_of(i%128,i/128),expected)
	check_eq(c.clear_footprint(23,21),Rect2i(23,20,3,3))
	for i in farms[0].members:
		check_eq(c.building_at(i%128,i/128),269,"neighboring farm survives")
		check_eq(c.anchor_of(i%128,i/128),Vector2i(20,20))
		check_eq(c.zone.data[i],zones_before[i],"neighbor corner byte survives")
	for i in farms[1].members:
		check_eq(c.building_at(i%128,i/128),Buildings.NONE,"selected whole farm clears")
