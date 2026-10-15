# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const F := preload("res://tests/helpers/agricultural_parcel_fixture.gd")

func farm(c: City, m: PackedInt32Array, key: StringName = &"alfalfa", state: StringName = &"prepared", id: int = 7) -> Dictionary:
	F.zone(c,m)
	var r := F.record(id,m,key,state)
	r.failed_months=2;r.last_month=13;r.layout_seed=123456789;r.phase=1
	check_eq(c.agricultural_parcels.put(c,r),OK)
	return r

func cut(c: City, m: PackedInt32Array) -> Dictionary:
	check(c.has_method("remove_agricultural_cells"),"City exposes the atomic cut transaction")
	return c.call("remove_agricultural_cells",m) if c.has_method("remove_agricultural_cells") else {}

func snapshot(c: City) -> PackedByteArray:
	return var_to_bytes([c.building.data,c.zone.data,c.flags.data,c.underground.data,c.agricultural_parcels.to_dict(),c.funds])

func test_cut_preserves_identity_counters_and_exact_units() -> void:
	var c := flat_city(1000000)
	var m := F.mask([[20,20],[21,20],[22,20],[23,20],[24,20]])
	farm(c,m)
	var revision := c.agricultural_parcels.revision
	var changes: Array = []
	c.agricultural_parcels.changed.connect(func(change: Dictionary): changes.append(change))
	var result := cut(c,F.mask([[22,20]]))
	check_eq(c.agricultural_parcels.id_at(Vector2i(20,20)),7)
	check_eq(c.agricultural_parcels.id_at(Vector2i(23,20)),8)
	check_eq(c.agricultural_parcels.records().size(),2)
	check_eq(c.agricultural_parcels.revision,revision+1)
	check_eq(changes.size(),1)
	check_eq(result.get("removed_cells"),F.mask([[22,20]]))
	var units := 0
	for r in c.agricultural_parcels.records():
		units += AgriculturalParcelParams.job_units(r.archetype,r.members.size())
		check_eq(r.failed_months,2);check_eq(r.last_month,13)
		check_eq(r.phase,1);check_eq(r.origin_index,2580);check_eq(r.layout_seed,123456789)
	check_eq(units,216)
	check(AgriculturalParcels.decode(c.agricultural_parcels.to_dict(),c).ok)

func test_identity_loss_largest_then_row_major_and_repeated_cuts() -> void:
	var c := flat_city()
	var m := F.mask([[20,20],[21,20],[22,20],[23,20],[24,20]])
	var r := farm(c,m)
	r=c.agricultural_parcels.record(7)
	# Separate fixture can assign an identity in the cut cell at creation.
	var d := flat_city()
	F.zone(d,m);r.identity_index=2582
	check_eq(d.agricultural_parcels.put(d,r),OK)
	cut(d,F.mask([[22,20]]))
	check_eq(d.agricultural_parcels.id_at(Vector2i(20,20)),7)
	check_eq(d.agricultural_parcels.id_at(Vector2i(23,20)),8)
	cut(d,F.mask([[20,20],[23,20],[23,20]]))
	check_eq(d.agricultural_parcels.record(7).members,F.mask([[21,20]]))
	check_eq(d.agricultural_parcels.record(8).get("members",PackedInt32Array()),F.mask([[24,20]]))
	cut(d,F.mask([[21,20],[24,20]]))
	check(d.agricultural_parcels.records().is_empty())
	check(AgriculturalParcels.coverage(d,d.agricultural_parcels))

func test_builder_road_preview_funds_and_selected_cell_cut_keep_pipe() -> void:
	var c := flat_city(1000)
	farm(c,F.mask([[20,20],[21,20],[22,20],[23,20],[24,20]]))
	c.underground.put(22,20,NetworkShapes.PIPE_FIRST)
	var b := Builder.new(c,CityStats.new())
	var before := snapshot(c)
	var preview := b.preview(Tools.Kind.ROAD,Vector2i(22,20))
	check(preview.ok);check_eq(preview.cost,10);check_eq(snapshot(c),before)
	c.funds=0;before=snapshot(c)
	check(not b.apply(Tools.Kind.ROAD,Vector2i(22,20)).applied)
	check_eq(snapshot(c),before)
	c.funds=1000
	var result := b.apply(Tools.Kind.ROAD,Vector2i(22,20))
	check(result.applied);check_eq(c.funds,990)
	check(NetworkShapes.in_family(c.building_at(22,20),NetworkShapes.Family.ROAD))
	check(NetworkShapes.underground_in_family(c.underground.at(22,20),NetworkShapes.Family.PIPE))
	check_eq(c.agricultural_parcels.records().size(),2)
	check_eq(c.agricultural_parcels.id_at(Vector2i(22,20)),0)
	check(result.rect.has_point(Vector2i(20,20)) and result.rect.has_point(Vector2i(24,20)))
	check(AgriculturalParcels.coverage(c,c.agricultural_parcels))

func test_builder_bulldoze_drag_is_one_transaction_and_no_arbitrary_clearability() -> void:
	var c := flat_city(1000)
	farm(c,F.square(3))
	var b := Builder.new(c,CityStats.new())
	var before := snapshot(c)
	check(not b.preview(Tools.Kind.POWER_LINE,Vector2i(20,20)).ok)
	check(not b.preview(Tools.Kind.ZONE_RES_LOW,Vector2i(20,20)).ok)
	check_eq(snapshot(c),before)
	var rev := c.agricultural_parcels.revision
	var result := b.apply(Tools.Kind.BULLDOZE,Vector2i(21,20),Vector2i(21,22))
	check(result.applied);check_eq(result.cost,3)
	check_eq(c.agricultural_parcels.revision,rev+1)
	check_eq(c.agricultural_parcels.records().size(),2)

func test_legacy_and_high_bulldoze_still_remove_entire_square() -> void:
	for key in [&"cattle_range",&"greenhouse"]:
		var c := flat_city(1000)
		var code := AgricultureParams.building_id(key)
		var side := Buildings.size(code).x
		c.stamp_building(20,20,code,Zones.AGR_LOW if key==&"cattle_range" else Zones.AGR_HIGH)
		var source := F.source(c)
		var b := Builder.new(c,CityStats.new())
		var result := b.apply(Tools.Kind.BULLDOZE,Vector2i(20+side-1,20+side-1))
		check(result.applied);check_eq(result.cost,side*side)
		for y in side:
			for x in side: check_ne(c.building_at(20+x,20+y),code)
		check(c.agricultural_parcels.records().is_empty())
		source.ctx.systems.clear()

func test_square_cut_converts_and_relocates_core_without_refilling_tokens() -> void:
	var c := flat_city()
	var m := F.square(3)
	F.zone(c,m)
	var r := F.record(7,m,&"cattle_range",&"active")
	r.mode=&"square";r.modules=[];r.legacy_code=AgricultureParams.building_id(&"cattle_range")
	r.failed_months=2
	check_eq(c.agricultural_parcels.put(c,r),OK)
	cut(c,F.mask([[21,20],[21,21]]))
	var after := c.agricultural_parcels.record(7)
	check_eq(after.mode,&"generated");check_eq(after.legacy_code,0)
	check_eq(after.members.size(),7);check_eq(after.failed_months,2)
	check_eq(after.state,&"prepared")
	check_eq(AgriculturalParcelGeometry.record_error(after),"")
	var units := 0
	for value: int in after.stock_units.values(): units+=value
	check_eq(units,56)
	check(AgriculturalParcels.decode(c.agricultural_parcels.to_dict(),c).ok)

func test_zero_stock_fragment_and_tiny_pasture_stay_prepared() -> void:
	var c := flat_city()
	var m := F.square(4)
	farm(c,m,&"cattle_range",&"active")
	var remove := m.slice(0,14)
	cut(c,remove)
	var r := c.agricultural_parcels.record(7)
	check_eq(r.members.size(),2);check_eq(r.state,&"prepared")
	for value: int in r.stock_units.values(): check_eq(value,0)
	check(AgriculturalParcelGeometry.plan(r).profile.is_empty())
	check_eq(AgriculturalParcelGeometry.record_error(r),"")

func test_public_clear_and_raw_edit_hooks_repair_without_readonly_writes() -> void:
	var c := flat_city()
	farm(c,F.l_shape())
	var source := F.source(c)
	c.clear_footprint(20,20)
	check_eq(c.agricultural_parcels.id_at(Vector2i(20,20)),0)
	c.zone.put(20,20,Zones.NONE)
	c.building.put(21,20,Buildings.NONE);c.zone.put(21,20,Zones.NONE)
	var before := snapshot(c)
	source.ag.current_lots();source.ag.inspect_tile(Vector2i(20,21));source.ag.jobs()
	check_eq(snapshot(c),before,"read-only getters never reconcile canonical ownership")
	source.ag.networks_changed(source.ctx,Rect2i(21,20,1,1))
	check_eq(c.agricultural_parcels.id_at(Vector2i(21,20)),0)
	check(AgriculturalParcels.decode(c.agricultural_parcels.to_dict(),c).ok)
	c.building.put(20,21,Buildings.NONE);c.zone.put(20,21,Zones.NONE)
	source.ag.monthly(source.ctx,0)
	check(c.agricultural_parcels.records().is_empty())
	check(AgriculturalParcels.decode(c.agricultural_parcels.to_dict(),c).ok)
	source.ctx.systems.clear()

func test_disaster_cut_can_save_before_next_month() -> void:
	var c := flat_city()
	farm(c,F.square(3))
	var source := F.source(c)
	var disasters := DisasterSystem.new()
	disasters.setup(source.ctx)
	var observed: Array = []
	var observer := func(_change: Dictionary): observed.append(Buildings.is_rubble(c.building_at(21,21)))
	c.agricultural_parcels.changed.connect(observer)
	check_eq(disasters._wreck(source.ctx,21,21),1)
	c.agricultural_parcels.changed.disconnect(observer)
	check_eq(observed,[true],"ownership publishes after the replacement rubble is written")
	check_eq(c.agricultural_parcels.record(7).members.size(),8)
	check(AgriculturalParcels.decode(c.agricultural_parcels.to_dict(),c).ok)
	var path := "user://parcel-disaster-cut.scdd"
	check_eq(SaveFormat.save(path,c,{"agriculture":source.ag.save()}),OK)
	DirAccess.remove_absolute(path)
	source.ctx.systems.clear()

func test_serviced_builder_edge_keeps_active_but_core_cut_prepares() -> void:
	var c := flat_city(100000)
	farm(c,F.square(3,Vector2i(14,10)),&"alfalfa",&"active")
	c.building.put(14,9,Buildings.ROAD_FIRST)
	c.stamp_building(10,10,Buildings.SOLAR_PLANT)
	c.stamp_building(9,10,Buildings.WIND_PLANT)
	c.stamp_building(17,10,Buildings.WATER_PUMP)
	c.sea_level=30
	var sim := Simulation.new()
	sim.setup(c,7)
	var ag := sim.get_system(&"agriculture") as AgricultureSystem
	check_eq(ag.inspect_tile(Vector2i(14,10)).blocked_reason,"")
	var b := Builder.new(c,sim.stats,sim)
	var seen: Array = []
	var observer := func(_change: Dictionary): seen.append(c.agricultural_parcels.record(7).state)
	c.agricultural_parcels.changed.connect(observer)
	check(b.apply(Tools.Kind.ROAD,Vector2i(16,12)).applied)
	check_eq(c.agricultural_parcels.record(7).state,&"active")
	check_eq(seen,[&"active"],"one publication contains final service-validated state")
	check(b.apply(Tools.Kind.ROAD,Vector2i(14,10)).applied)
	check_eq(c.agricultural_parcels.record(7).state,&"prepared")
	check_eq(c.agricultural_parcels.record(7).failed_months,2)
	check(AgriculturalParcels.decode(c.agricultural_parcels.to_dict(),c).ok)
	c.agricultural_parcels.changed.disconnect(observer)
	sim.free()

func test_generated_empty_month_has_no_utility_refresh_after_settling() -> void:
	var c := flat_city()
	farm(c,F.l_shape())
	var source := F.source(c)
	var power := PowerSystem.new()
	var water := WaterSystem.new()
	source.ctx.systems[&"power"]=power;source.ctx.systems[&"water"]=water
	power.setup(source.ctx);water.setup(source.ctx)
	for i in F.l_shape():
		c.clear_footprint(i%128,i/128);c.zone.put(i%128,i/128,Zones.NONE)
	source.ag.networks_changed(source.ctx,Rect2i(20,20,3,3))
	source.ag.monthly(source.ctx,0)
	check(c.agricultural_parcels.records().is_empty())
	var before := var_to_bytes([snapshot(c),power.save(),power.network_summary(),water.save(),water.network_summary(),source.ctx.rng.state()])
	source.ctx.clock.day+=GameClock.DAYS_PER_MONTH
	source.ag.monthly(source.ctx,0);source.ag.monthly(source.ctx,1)
	check_eq(var_to_bytes([snapshot(c),power.save(),power.network_summary(),water.save(),water.network_summary(),source.ctx.rng.state()]),before)
	source.ctx.systems.clear()

func test_bridge_choice_refusal_does_not_cut_farm_on_approach() -> void:
	var c := flat_city(100000)
	farm(c,F.l_shape())
	for x in range(23,26):
		c.terrain.put(x,20,Terrain.make(Terrain.FLAT,Terrain.SURFACE))
		c.set_heights(x,20,4,4)
	var b := Builder.new(c,CityStats.new())
	var before := snapshot(c)
	var result := b.preview(Tools.Kind.ROAD,Vector2i(20,20),Vector2i(27,20))
	check(result.get("needs_confirmation",false))
	check_eq(snapshot(c),before)
	# A rejected construction dialog never invokes apply; its refused choice
	# also cannot be used to submit a partial approach cut.
	result=b.apply(Tools.Kind.ROAD,Vector2i(20,20),Vector2i(27,20),{"choice":&"cancel"})
	check(not result.applied)
	check_eq(snapshot(c),before)

func test_exhausted_split_ids_refuse_before_builder_writes_or_charge() -> void:
	var c := flat_city(1000)
	farm(c,F.mask([[20,20],[21,20],[22,20]]))
	var data := c.agricultural_parcels.to_dict()
	data.next_id=2147483647
	var decoded := AgriculturalParcels.decode(data,c)
	check(decoded.ok)
	c.agricultural_parcels=decoded.store
	var before := snapshot(c)
	var b := Builder.new(c,CityStats.new())
	check(not b.apply(Tools.Kind.ROAD,Vector2i(21,20)).applied)
	check_eq(snapshot(c),before)

func test_wear_reconciles_raw_replacement_before_dirty_publication() -> void:
	var c := flat_city()
	farm(c,F.l_shape())
	var source := F.source(c)
	var wear := WearSystem.new()
	wear.setup(source.ctx)
	wear._to_rubble(source.ctx,20,20)
	check_eq(c.agricultural_parcels.id_at(Vector2i(20,20)),0)
	check_eq(c.agricultural_parcels.records().size(),2)
	check(AgriculturalParcels.decode(c.agricultural_parcels.to_dict(),c).ok)
	source.ctx.systems.clear()

func test_larger_fragment_inherits_removed_identity_and_neighbors_are_dirty() -> void:
	var c := flat_city()
	var m := F.mask([[20,20],[21,20],[22,20],[23,20],[24,20],[25,20]])
	var r := F.record(7,m,&"alfalfa")
	r.identity_index=2582
	F.zone(c,m);check_eq(c.agricultural_parcels.put(c,r),OK)
	farm(c,F.square(2,Vector2i(23,21)),&"grain",&"prepared",8)
	var result := cut(c,F.mask([[22,20]]))
	check_eq(c.agricultural_parcels.id_at(Vector2i(23,20)),7)
	check_eq(c.agricultural_parcels.id_at(Vector2i(20,20)),9)
	check(8 in result.get("neighbor_ids",[]))
	check(AgriculturalParcels.change_bounds(result,c.agricultural_parcels).has_point(Vector2i(24,22)))

func test_cut_around_obstacle_never_reuses_radius_unsafe_neck() -> void:
	var c := flat_city()
	var m := PackedInt32Array()
	for y in range(20,23):
		for x in range(20,25): m.append(y*128+x)
	var r := F.record(7,m,&"cattle_range",&"active")
	r.modules.append({"key":&"farm_shed","at":Vector3(40,.14,24),"yaw":0})
	F.zone(c,m);check_eq(c.agricultural_parcels.put(c,r),OK)
	cut(c,F.mask([[22,20],[22,22]]))
	var after := c.agricultural_parcels.record(7)
	check_eq(after.members,F.dumbbell())
	var layout := AgriculturalParcelGeometry.plan(after)
	check(layout.ok)
	var pen: Dictionary = layout.profile.pens[0]
	check(not AgriculturalParcelGeometry.navigation_segment(Vector2(24,24),Vector2(56,24),pen,2.64))
	for edge: Array in pen.navigation_edges:
		var a: Array = pen.navigation_nodes[edge[0]]
		var b: Array = pen.navigation_nodes[edge[1]]
		check(AgriculturalParcelGeometry.navigation_segment(Vector2(a[0],a[1]),Vector2(b[0],b[1]),pen,2.64))
	check_eq(AgriculturalParcelGeometry.record_error(after),"")

func test_terrain_disaster_batch_reconciles_every_changed_parcel() -> void:
	var c := flat_city()
	farm(c,F.square(3))
	farm(c,F.square(3,Vector2i(23,20)),&"grain",&"prepared",8)
	var source := F.source(c)
	var disaster := DisasterSystem.new()
	disaster.setup(source.ctx)
	disaster._raise_cone(source.ctx,Vector2i(22,21))
	check(AgriculturalParcels.decode(c.agricultural_parcels.to_dict(),c).ok)
	source.ctx.systems.clear()

func test_service_adapter_retains_imported_links_and_cannot_change_source_or_tokens() -> void:
	var c := flat_city()
	farm(c,F.square(3),&"cattle_range",&"active")
	c.imported_power_links[100]=Vector2i(Buildings.ROAD_FIRST,Zones.NONE)
	var original := c.agricultural_parcels.record(7)
	var called := [false]
	var validator := func(candidate: City, eligible: Array[int]) -> Array:
		called[0]=true
		check_eq(candidate.imported_power_links,c.imported_power_links)
		candidate.funds=0
		candidate.agricultural_parcels._records[7].failed_months=0
		candidate.agricultural_parcels._records[7].stock_units[2580]=99
		return eligible
	var funds := c.funds
	var result := c.agricultural_parcels.remove_cells(c,F.mask([[22,22]]),validator)
	check(result.ok);check(called[0])
	check_eq(c.funds,funds)
	var after := c.agricultural_parcels.record(7)
	check_eq(after.failed_months,2)
	check_eq(after.stock_units[2580],8)
	check_eq(after.modules,original.modules)
	check(AgriculturalParcels.decode(c.agricultural_parcels.to_dict(),c).ok)

func exhausted_city(kind: String) -> City:
	var c := flat_city(1000)
	farm(c,F.mask([[20,20],[21,20],[22,20]]))
	var data := c.agricultural_parcels.to_dict()
	if kind == "ids": data.next_id=2147483647
	elif kind == "store_revision": data.revision=2147483647
	else: data.records[0].revision=2147483647
	var decoded := AgriculturalParcels.decode(data,c)
	check(decoded.ok)
	c.agricultural_parcels=decoded.store
	return c

func test_managed_disaster_and_wear_refuse_exhausted_repairs_atomically() -> void:
	for exhaustion in ["ids","store_revision","record_revision"]:
		for operation in ["disaster","contamination","wear"]:
			var c := exhausted_city(exhaustion)
			var source := F.source(c)
			var d := DisasterSystem.new();d.setup(source.ctx)
			var w := WearSystem.new();w.setup(source.ctx)
			source.ctx.events.clear()
			var before := snapshot(c)
			var random_state: int = source.ctx.rng.state()
			var disaster_before := var_to_bytes(d.save())
			var seen: Array = []
			c.agricultural_parcels.changed.connect(func(change: Dictionary): seen.append(change))
			if operation == "disaster": check_eq(d._wreck(source.ctx,21,20),0)
			elif operation == "contamination": d._contaminate(source.ctx,Vector2i(21,20),10)
			else: w._to_rubble(source.ctx,21,20)
			check(snapshot(c)==before,"%s/%s refusal preserves all source layers, ownership and funds" % [operation,exhaustion])
			check_eq(source.ctx.rng.state(),random_state)
			check_eq(var_to_bytes(d.save()),disaster_before)
			check_eq(source.ctx.events.map_dirty,Rect2i())
			check(source.ctx.events.news.is_empty() and source.ctx.events.notices.is_empty())
			check(seen.is_empty())
			check(AgriculturalParcels.decode(c.agricultural_parcels.to_dict(),c).ok)
			check_eq(source.ag.migration_error(),OK,"managed refusal leaves an intact city usable")
			source.ctx.systems.clear()

func test_raw_repair_failure_latches_and_stops_publication_and_month_advancement() -> void:
	for exhaustion in ["ids","store_revision","record_revision"]:
		for hook in ["network","monthly"]:
			var c := exhausted_city(exhaustion)
			var source := F.source(c)
			var before: Dictionary = source.ag.save()
			c.building.put(21,20,Buildings.NONE)
			source.ctx.stats.agricultural_jobs=4321
			source.ctx.stats.agricultural_lots=4321
			source.ctx.events.clear()
			var raw := snapshot(c)
			if hook == "network": source.ag.networks_changed(source.ctx,Rect2i(21,20,1,1))
			else: source.ag.monthly(source.ctx,1)
			check_ne(source.ag.migration_error(),OK)
			check(source.ag.has_method("repair_error"),"raw failure is exposed with a useful reason")
			if source.ag.has_method("repair_error"): check(not String(source.ag.call("repair_error")).is_empty())
			var after: Dictionary = source.ag.save()
			check_ne(after.get("migration_error",OK),OK)
			after.erase("migration_error")
			check_eq(after,before,"failed raw repair consumes neither monthly guards nor RNG")
			check(snapshot(c)==raw,"raw hook neither heals nor partially commits on failure")
			check_eq(source.ctx.stats.agricultural_jobs,4321)
			check_eq(source.ctx.stats.agricultural_lots,4321)
			check_eq(source.ctx.events.map_dirty,Rect2i())
			source.ag.monthly(source.ctx,0);source.ag.networks_changed(source.ctx,Rect2i())
			after=source.ag.save();after.erase("migration_error")
			check_eq(after,before,"latched repair failure persists until explicit setup/load retry")
			source.ctx.systems.clear()

func test_terrain_disaster_revision_refusal_preserves_ground_and_events() -> void:
	for native in [false,true]:
		var c := exhausted_city("store_revision")
		if native: c.terrain_surface=TerrainSurface.from_city(c)
		var source := F.source(c)
		var d := DisasterSystem.new();d.setup(source.ctx)
		source.ctx.events.clear()
		var before := var_to_bytes([snapshot(c),c.terrain.data,c.altitude.data])
		var surface: PackedByteArray = c.terrain_surface.vertices.duplicate() if native else PackedByteArray()
		var random_state: int = source.ctx.rng.state()
		d._raise_cone(source.ctx,Vector2i(21,20))
		check(var_to_bytes([snapshot(c),c.terrain.data,c.altitude.data])==before)
		if native: check_eq(c.terrain_surface.vertices,surface)
		check_eq(source.ctx.rng.state(),random_state)
		check_eq(source.ctx.events.map_dirty,Rect2i())
		check(AgriculturalParcels.decode(c.agricultural_parcels.to_dict(),c).ok)
		source.ctx.systems.clear()

func test_real_adapter_constrained_cut_revalidates_survivors_and_competing_consumer() -> void:
	var c := flat_city()
	farm(c,F.square(2,Vector2i(14,10)),&"alfalfa",&"active",7)
	farm(c,F.square(2,Vector2i(18,10)),&"alfalfa",&"active",8)
	c.building.put(14,9,Buildings.ROAD_FIRST);c.building.put(18,9,Buildings.ROAD_FIRST)
	c.stamp_building(10,9,Buildings.WIND_PLANT)
	c.stamp_building(10,10,Buildings.WATER_PUMP)
	c.stamp_building(11,10,Buildings.RES_1X1_FIRST,Zones.RES_LOW)
	for x in range(10,20): c.underground.put(x,10,15)
	c.sea_level=30
	var source := F.source(c)
	var power := PowerSystem.new();var water := WaterSystem.new()
	source.ctx.systems[&"power"]=power;source.ctx.systems[&"water"]=water
	power.setup(source.ctx);c.facility(Vector2i(10,9)).capacity=100
	power.reallocate_established(source.ctx,Rect2i(10,9,10,3));water.setup(source.ctx)
	var initial := AgriculturalParcelService.project(source.ctx)
	for r in c.agricultural_parcels.records(): check(AgriculturalParcelService.summary(source.ctx,r,initial).blocked_reason.is_empty())
	check(initial.is_watered(11,10))
	# Wind plant and resident each use one unit; three western alfalfa cells use nine.
	c.facility(Vector2i(10,10)).output=11
	var policy := var_to_bytes([c.facilities,power.save(),water.save(),source.ctx.rng.state()])
	var cells := F.mask([[15,11],[19,11]])
	for i in cells: c.building.data[i]=Buildings.NONE
	var observed: Array = []
	var observer := func(_change: Dictionary):
		observed.append([c.agricultural_parcels.record(7).state,c.agricultural_parcels.record(8).state,AgriculturalParcels.coverage(c,c.agricultural_parcels)])
	c.agricultural_parcels.changed.connect(observer)
	var result: Dictionary = source.ag.repair_parcels(cells)
	c.agricultural_parcels.changed.disconnect(observer)
	check(result.ok)
	check_eq(observed,[[&"active",&"prepared",true]],"single publication already contains final reduced active set")
	var final_city := AgriculturalParcelService.project(source.ctx)
	var retained: Array = []
	for r in c.agricultural_parcels.records():
		if r.state != &"active": continue
		retained.append(r.id)
		check(AgriculturalParcelService.summary(source.ctx,r,final_city).blocked_reason.is_empty())
		for i in r.members: check(final_city.is_watered(i%128,i/128))
	check_eq(retained,[7])
	check(final_city.is_watered(11,10) and final_city.is_powered(11,10),"unrelated consumer retains its allocation")
	check_eq(var_to_bytes([c.facilities,power.save(),water.save(),source.ctx.rng.state()]),policy,"cut validation does not change source policy or live utility state")
	source.ctx.systems.clear()
