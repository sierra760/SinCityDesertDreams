# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

func test_district_appeal_changes_real_venue_demand_without_creating_city_pool() -> void:
	var row := {"key": &"arcology_boddy", "anchor": Vector2i(10,10), "operating": true,
		"guests": 0, "district_appeal_bonus": 20}
	var inputs := {"permanent_population":10000}
	var diverse := TourismDemand.forecast([row],inputs,7,7)
	row.district_appeal_bonus = 5
	var repeated := TourismDemand.forecast([row],inputs,7,7)
	check_gt(diverse.rows[0].appeal,repeated.rows[0].appeal,"four categories beat repeated parks")
	check_gt(diverse.rows[0].target_guests,repeated.rows[0].target_guests)
	check_eq(diverse.guest_pool,repeated.guest_pool,"local preference does not invent regional visitors")

func districts() -> TourismDistricts:
	return TourismDistricts.new()

func lot(city: City, key: StringName, at: Vector2i) -> void:
	TourismFixture.venue(city,key,at)
	TourismFixture.set_served(city,at,true,true)
	city.stamp_building(at.x-1,at.y,Buildings.ROAD_FIRST)

func visitor(at: Vector2i, guests: int = 100, key: StringName = &"arcology_boddy") -> Dictionary:
	return {"anchor":at,"key":key,"code":Buildings.id_of(key),"instance":at.y*128+at.x+1,
		"guests":guests,"day_visitors":0,"operating":true}

func test_canonical_rotated_import_and_missing_metadata_are_counted_once() -> void:
	var d := districts()
	if d == null: return
	var city := flat_city()
	var at := Vector2i(20,20)
	lot(city,&"museum",at)
	city.facilities.clear()
	city.stamp_building(9,20,Buildings.ROAD_FIRST)
	# Imported clockwise ring rotated one corner; no facility metadata exists.
	for pair in [[Vector2i(0,0),Zones.CORNER_NE],[Vector2i(2,0),Zones.CORNER_SE],
		[Vector2i(2,2),Zones.CORNER_SW],[Vector2i(0,2),Zones.CORNER_NW]]:
		city.zone.put(at.x+pair[0].x,at.y+pair[0].y,pair[1])
	TourismFixture.connect_roads(city)
	var ctx := TourismFixture.context(city)
	d.refresh(ctx,[visitor(Vector2i(10,20))])
	check_eq(d.venue_inputs(Vector2i(10,20)).district_categories.culture,1)
	check_eq(d.venue_inputs(Vector2i(10,20)).district_appeal_bonus,4)
	city.building.put(22,22,0)
	d.refresh(ctx,[visitor(Vector2i(10,20))])
	check_eq(d.venue_inputs(Vector2i(10,20)).district_appeal_bonus,0,"partial lot has no attraction")

func test_diversity_diminishing_returns_and_operating_resort_identities() -> void:
	var d := districts()
	if d == null: return
	var city := flat_city()
	var at := Vector2i(20,20)
	city.stamp_building(19,20,Buildings.ROAD_FIRST)
	city.stamp_building(29,30,Buildings.ROAD_FIRST)
	city.stamp_building(29,20,Buildings.ROAD_FIRST)
	for p in [Vector2i(14,14),Vector2i(17,14),Vector2i(20,14),Vector2i(23,14)]: lot(city,&"small_park",p)
	TourismFixture.connect_roads(city)
	var ctx := TourismFixture.context(city)
	var rows: Array[Dictionary] = [visitor(at)]
	d.refresh(ctx,rows)
	check_eq(d.venue_inputs(at).district_appeal_bonus,5,"repeated outdoors caps at five")
	lot(city,&"museum",Vector2i(13,23))
	lot(city,&"zoo",Vector2i(24,23))
	lot(city,&"stadium",Vector2i(24,15))
	lot(city,&"library",Vector2i(34,20))
	rows.append(visitor(Vector2i(30,30),0,&"arcology_woolier"))
	rows.append(visitor(Vector2i(32,30),0,&"arcology_woolier"))
	rows.append(visitor(Vector2i(30,20),0,&"arcology_stockgrowers"))
	TourismFixture.connect_roads(city)
	d.refresh(ctx,rows)
	var info: Dictionary = d.venue_inputs(at)
	check_eq(info.district_categories.size(),4,"library retains civic role")
	check_eq(info.district_appeal_bonus,19,"17 attraction points and two resort identities")
	check_eq(info.resort_variety_bonus,2)
	rows[1].operating=false
	rows[2].operating=false
	d.refresh(ctx,rows)
	check_eq(d.venue_inputs(at).resort_variety_bonus,1,"closed resorts do not grant variety")

func test_unserved_staffed_attractions_dry_marina_and_inaccessible_parks_close() -> void:
	var d := districts()
	if d == null: return
	var city := flat_city()
	lot(city,&"museum",Vector2i(20,20))
	lot(city,&"marina",Vector2i(25,20))
	TourismFixture.set_served(city,Vector2i(20,20),false,true)
	var at:=Vector2i(15,20)
	city.stamp_building(14,20,Buildings.ROAD_FIRST)
	TourismFixture.connect_roads(city)
	var ctx:=TourismFixture.context(city)
	d.refresh(ctx,[visitor(at)])
	check_eq(d.venue_inputs(at).district_appeal_bonus,0,"unpowered museum and dry marina are closed")
	city.terrain.put(28,20,Terrain.SURFACE)
	TourismFixture.set_served(city,Vector2i(20,20),true,true)
	d.refresh(ctx,[visitor(at)])
	check_eq(d.venue_inputs(at).district_appeal_bonus,8)
	city.clear_footprint(19,20)
	city.clear_footprint(24,20)
	for y in range(17,26):
		for x in range(17,31):
			if city.building_at(x,y) == Buildings.ROAD_FIRST: city.building.put(x,y,0)
	d.refresh(ctx,[visitor(at)])
	check_eq(d.venue_inputs(at).district_appeal_bonus,0,"access loss invalidates cached operating benefits")

func test_retail_distribution_is_finite_spatial_and_never_city_cash() -> void:
	var d := districts()
	if d == null: return
	var city := flat_city(12345)
	for at in [Vector2i(20,20),Vector2i(24,20),Vector2i(80,80)]: lot(city,&"com_corner_store",at)
	TourismFixture.connect_roads(city)
	var ctx:=TourismFixture.context(city)
	var rows: Array[Dictionary]=[visitor(Vector2i(17,20),75)]
	d.refresh(ctx,rows)
	var summary: Dictionary=d.report()
	check_eq(summary.available_spending_cents,1522)
	check_eq(summary.recipient_capacity_cents,2000)
	check_eq(summary.allocated_spending_cents,1522)
	var total:=0
	for value in d.spending_distribution().values(): total+=int(value)
	check_eq(total,mini(summary.available_spending_cents,summary.accepted_spending_cents))
	check_gt(d.commercial_bonus(Vector2i(20,20)),0)
	check_eq(d.commercial_bonus(Vector2i(80,80)),0)
	check_eq(city.funds,12345,"retail support is not municipal revenue")
	check_eq(d.commercial_demand_bonus(),15)
	rows[0].guests=100000
	d.refresh(ctx,rows)
	check_eq(d.report().allocated_spending_cents,2000,"shops cannot each receive full visitor spending")
	check_eq(d.commercial_bonus(Vector2i(20,20)),10)
	check_eq(d.commercial_demand_bonus(),100)

func test_same_total_moving_attendance_deletion_and_pure_cached_reads() -> void:
	var d:=districts()
	if d==null: return
	var city:=flat_city()
	lot(city,&"com_corner_store",Vector2i(20,20))
	lot(city,&"com_corner_store",Vector2i(80,80))
	TourismFixture.connect_roads(city)
	var ctx:=TourismFixture.context(city)
	var rows: Array[Dictionary]=[visitor(Vector2i(17,20),100),visitor(Vector2i(77,80),0)]
	d.refresh(ctx,rows)
	check_eq(d.commercial_bonus(Vector2i(20,20)),10)
	rows[0].guests=0
	rows[1].guests=100
	d.refresh(ctx,rows)
	check_eq(d.commercial_bonus(Vector2i(20,20)),0)
	check_eq(d.commercial_bonus(Vector2i(80,80)),10)
	var before: Dictionary=d.report().duplicate(true)
	var copy: Dictionary=d.spending_distribution()
	copy.clear()
	for i in 4:
		d.venue_inputs(Vector2i(77,80))
		d.commercial_bonus(Vector2i(80,80))
	check_eq(d.report(),before,"views do not rescan or allocate again")
	city.clear_footprint(80,80)
	d.refresh(ctx,rows)
	check_eq(d.report().allocated_spending_cents,0,"removed shop cannot accept support")
	rows.clear()
	d.refresh(ctx,rows)
	check_eq(d.commercial_demand_bonus(),0)
	check_eq(d.commercial_bonus(Vector2i(80,80)),0)

func test_no_shops_preserves_market_opportunity_without_cash_or_local_payment() -> void:
	var d:=districts()
	if d==null: return
	var city:=flat_city(54321)
	city.stamp_building(9,10,Buildings.ROAD_FIRST)
	TourismFixture.connect_roads(city)
	var ctx:=TourismFixture.context(city)
	d.refresh(ctx,[visitor(Vector2i(10,10),100)])
	check_eq(d.commercial_demand_bonus(),20)
	check_eq(d.report().available_spending_cents,2035)
	check_eq(d.report().allocated_spending_cents,0)
	check_eq(d.report().unallocated_spending_cents,2035)
	check_eq(city.funds,54321)

func test_fire_ground_and_water_service_remove_attraction_without_money_or_rng() -> void:
	var d:=districts()
	var city:=flat_city()
	lot(city,&"museum",Vector2i(20,20))
	city.stamp_building(9,20,Buildings.ROAD_FIRST)
	TourismFixture.connect_roads(city)
	var ctx:=TourismFixture.context(city)
	var disasters:=DisasterSystem.new()
	ctx.systems[&"disasters"]=disasters
	disasters.setup(ctx)
	var rows: Array[Dictionary]=[visitor(Vector2i(10,20))]
	d.refresh(ctx,rows)
	check_eq(d.venue_inputs(Vector2i(10,20)).district_appeal_bonus,4)
	TourismFixture.set_served(city,Vector2i(20,20),true,false)
	d.refresh(ctx,rows)
	check_eq(d.venue_inputs(Vector2i(10,20)).district_appeal_bonus,0)
	TourismFixture.set_served(city,Vector2i(20,20),true,true)
	check(disasters._ignite(ctx,21,21),"real fire on one interior footprint tile")
	var rng:=ctx.rng.state()
	d.refresh(ctx,rows)
	check_eq(d.venue_inputs(Vector2i(10,20)).district_appeal_bonus,0)
	check_eq(ctx.rng.state(),rng)
	ctx.systems.clear()

func test_zone_consumes_demand_and_local_preference_once_without_residential_effect() -> void:
	var ctx:=TourismFixture.host_with_store(24)
	var tourism: TourismSystem=ctx.system(&"tourism")
	var zones:=ZoneSystem.new()
	zones.setup(ctx)
	zones._raw_demand=Vector3i.ZERO
	zones._update_demand(ctx)
	var base:=zones.raw_demand()
	zones._raw_demand=Vector3i.ZERO
	zones._tourism=tourism
	zones._update_demand(ctx)
	check_eq(zones.raw_demand().y-base.y,2,"240c available supports exactly two demand points")
	check_eq(zones.raw_demand().x,base.x,"resident demand has no tourism spillover nudge")
	check_eq(zones.raw_demand().z,base.z)
	zones._raw_demand=Vector3i.ZERO
	zones._bind(ctx.city)
	zones._tourism=null
	var baseline:=zones._growth_points(Vector2i(10,10),1,true)
	var residential:=zones._growth_points(Vector2i(10,10),0,true)
	zones._tourism=tourism
	check_eq(zones._growth_points(Vector2i(10,10),1,true)-baseline,2)
	check_eq(zones._growth_points(Vector2i(10,10),0,true),residential)
	check_eq(zones._growth_points(Vector2i(10,10),1,false),0)
	check_eq(ctx.city.funds,10000)
	zones._unbind()
	ctx.systems.clear()

func test_live_system_snapshot_reports_cached_support_and_restore_rebuilds_it() -> void:
	var ctx:=TourismFixture.host_with_store(24)
	var tourism: TourismSystem=ctx.system(&"tourism")
	var at:=Vector2i(10,10)
	lot(ctx.city,&"small_park",Vector2i(13,10))
	tourism.reconcile_now()
	var saved:=tourism.save().duplicate(true)
	var state:=ctx.rng.state()
	var info:=tourism.venue_report(at)
	check_eq(info.district_categories,{&"outdoors":1})
	check_eq(info.district_appeal_bonus,4)
	check_eq(info.commercial_spending_cents,227)
	check_eq(info.commercial_allocated_cents,227)
	var snapshot:=tourism.effects_snapshot()
	check_eq(snapshot.rows[0].district_appeal_bonus,4)
	check_eq(snapshot.commercial.available_spending_cents,227)
	snapshot.rows[0].district_categories.clear()
	for i in 3:
		tourism.forecast()
		tourism.extension_report()
		tourism.effects_snapshot()
	check_eq(tourism.save(),saved,"derived cache is not authoritative serialized state")
	check_eq(ctx.rng.state(),state)
	check_eq(tourism.venue_report(at).district_categories,{&"outdoors":1})
	var restored:=TourismSystem.new()
	restored.setup(ctx)
	ctx.systems[&"tourism"]=restored
	check_eq(restored.finish_restore({"systems":{"tourism":saved}}),OK)
	check_eq(restored.venue_report(at).district_appeal_bonus,4)
	check_eq(restored.commercial_bonus(at),2)
	ctx.city.clear_footprint(at.x,at.y)
	restored.reconcile_now()
	check_eq(restored.commercial_demand_bonus(),0)
	check_eq(restored.extension_report().available_spending_cents,0)
	check_eq(ctx.city.funds,10000)
	ctx.systems.clear()

func test_footprint_reach_boundaries_and_resort_lots_cannot_accept_shop_spending() -> void:
	var d:=districts()
	var city:=flat_city()
	var source:=Vector2i(10,20)
	city.stamp_building(9,20,Buildings.ROAD_FIRST)
	lot(city,&"small_park",Vector2i(27,20))
	lot(city,&"com_corner_store",Vector2i(23,20))
	lot(city,&"arcology_woolier",Vector2i(15,24))
	var rows: Array[Dictionary]=[visitor(source)]
	TourismFixture.connect_roads(city)
	var ctx:=TourismFixture.context(city)
	d.refresh(ctx,rows)
	check_eq(d.venue_inputs(source).district_appeal_bonus,4,"source 2x2 edge reaches a park sixteen tiles away")
	check_gt(d.commercial_bonus(Vector2i(23,20)),0,"twelve tiles from source edge is eligible")
	check_eq(d.commercial_bonus(Vector2i(15,24)),0,"resort is never an ordinary commercial recipient")
	city.clear_footprint(27,20)
	city.clear_footprint(23,20)
	lot(city,&"small_park",Vector2i(28,20))
	lot(city,&"com_corner_store",Vector2i(24,20))
	d.refresh(ctx,rows)
	check_eq(d.venue_inputs(source).district_appeal_bonus,0,"seventeen tiles is outside district")
	check_eq(d.commercial_bonus(Vector2i(24,20)),0,"thirteen tiles is outside local commerce")
	check_eq(d.report().unallocated_spending_cents,2035)

class CountDistricts extends TourismDistricts:
	var discoveries:=0
	var rebuilds:=0
	func _discover(city: City) -> void:
		discoveries+=1
		super._discover(city)
	func _rebuild(city: City,rows: Array[Dictionary]) -> void:
		rebuilds+=1
		super._rebuild(city,rows)

func test_shared_shop_capacity_conserves_spending_and_native_cache_reuses_census() -> void:
	var d:=CountDistricts.new()
	var city:=flat_city()
	for at in [Vector2i(20,20),Vector2i(24,20)]: lot(city,&"com_corner_store",at)
	TourismFixture.connect_roads(city)
	var ctx:=TourismFixture.context(city)
	var rows: Array[Dictionary]=[visitor(Vector2i(17,20),60),visitor(Vector2i(17,22),60)]
	d.refresh(ctx,rows)
	check_eq(d.report().available_spending_cents,2442)
	check_eq(d.report().allocated_spending_cents,2000)
	check_eq(d.report().unallocated_spending_cents,442)
	check_eq(d.spending_distribution(),{Vector2i(20,20):1000,Vector2i(24,20):1000})
	for i in 5:
		d.refresh(ctx,rows)
		d.venue_inputs(Vector2i(17,20))
		d.commercial_bonus(Vector2i(20,20))
	check_eq(d.discoveries,1,"unchanged packed layers retain canonical discovery")
	check_eq(d.rebuilds,1,"reads and identical simulation inputs do not reallocate")
	rows.reverse()
	d.refresh(ctx,rows)
	check_eq(d.spending_distribution(),{Vector2i(20,20):1000,Vector2i(24,20):1000},"allocation order is canonical")
	rows[0].guests=120
	rows[1].guests=0
	d.refresh(ctx,rows)
	check_eq(d.discoveries,1,"same-total relocation changes influence without repeating census")
	check_eq(d.rebuilds,3)
	city.flags.put(20,20,0)
	d.refresh(ctx,rows)
	check_eq(d.discoveries,2,"raw service edits invalidate operating recipients")
	check_eq(d.report().allocated_spending_cents,1000)
	check_eq(d.report().available_spending_cents,d.report().allocated_spending_cents+d.report().unallocated_spending_cents)

func test_flood_only_membership_invalidates_warm_park_and_shop_cache_then_drains() -> void:
	var d:=CountDistricts.new()
	var city:=flat_city(24680)
	var source:=Vector2i(10,10)
	var park_tile:=Vector2i(15,11)
	var shop:=Vector2i(20,10)
	city.stamp_building(9,10,Buildings.ROAD_FIRST)
	lot(city,&"large_park",Vector2i(14,10))
	lot(city,&"com_corner_store",shop)
	TourismFixture.connect_roads(city)
	var ctx:=TourismFixture.context(city)
	var disasters:=DisasterSystem.new()
	ctx.systems[&"disasters"]=disasters
	disasters.setup(ctx)
	var rows: Array[Dictionary]=[visitor(source,100)]
	var original_rows:=rows.duplicate(true)
	var layers: Array=[city.building.data.duplicate(),city.zone.data.duplicate(),
		city.flags.data.duplicate(),city.terrain.data.duplicate(),city.altitude.data.duplicate()]
	d.refresh(ctx,rows)
	check_eq(d.venue_inputs(source).district_appeal_bonus,4)
	check_eq(d.commercial_bonus(shop),10)
	check_eq(d.report().allocated_spending_cents,1000)
	d.refresh(ctx,rows)
	check_eq(d.discoveries,1)
	check_eq(d.rebuilds,1,"unchanged warm inputs reuse discovery and influence")
	# Real disaster mutation changes only transient water membership among the
	# eligibility inputs. No services/buildings/terrain/attendance change.
	disasters._flood_tile(ctx,park_tile)
	disasters._flood_tile(ctx,shop)
	d.refresh(ctx,rows)
	check_eq(d.venue_inputs(source).district_appeal_bonus,0,"flooded park ground is unusable")
	check_eq(d.commercial_bonus(shop),0,"flooded shop cannot receive support")
	check_eq(d.report().allocated_spending_cents,0)
	check_eq(d.report().unallocated_spending_cents,2035)
	check_eq(d.discoveries,2,"flood membership invalidates warm operating census")
	check_eq(d.rebuilds,2)
	# Membership is canonical and defensive: order/depth do not alter is_water.
	city.flood_overlay.erase(park_tile)
	city.flood_overlay[park_tile]=7
	d.refresh(ctx,rows)
	check_eq(d.discoveries,2,"same flooded set in another order reuses census")
	check_eq(d.rebuilds,2)
	disasters._drain_tile(ctx,park_tile)
	disasters._drain_tile(ctx,shop)
	d.refresh(ctx,rows)
	check_eq(d.venue_inputs(source).district_appeal_bonus,4,"drained park resumes attraction")
	check_eq(d.commercial_bonus(shop),10,"drained shop resumes finite support")
	check_eq(d.report().allocated_spending_cents,1000)
	check_eq(d.discoveries,3,"draining updates defensive cached membership")
	check_eq(d.rebuilds,3)
	d.refresh(ctx,rows)
	check_eq(d.discoveries,3)
	check_eq(d.rebuilds,3,"unchanged drained inputs reuse the recovered cache")
	check_eq([city.building.data,city.zone.data,city.flags.data,city.terrain.data,city.altitude.data],layers)
	check_eq(rows,original_rows,"attendance stayed identical through flood/drain")
	check_eq(city.funds,24680,"closure/recovery never creates city cash")
	ctx.systems.clear()
