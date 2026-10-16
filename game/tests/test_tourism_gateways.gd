# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

const PortSystem := preload("res://scripts/sim/port_system.gd")

func access_for(city: City) -> RefCounted:
	if not ResourceLoader.exists("res://scripts/sim/tourism_access.gd"):
		check(false,"tourism requires explicit gateway routing")
		return null
	var access: RefCounted = load("res://scripts/sim/tourism_access.gd").new()
	access.call("refresh",TourismFixture.context(city))
	return access

func test_shop_on_isolated_road_is_not_external_destination() -> void:
	var city := flat_city()
	TourismFixture.venue(city,&"arcology_boddy",Vector2i(20,20))
	TourismFixture.venue(city,&"com_corner_store",Vector2i(18,20))
	city.building.put(19,20,Buildings.ROAD_FIRST)
	var access := access_for(city)
	if access == null: return
	check(not access.venue_access(Vector2i(20,20)).external_reachable)
	check_eq(access.venue_access(Vector2i(20,20)).access_status,"disconnected")

func test_second_frontage_station_and_raw_rail_cut() -> void:
	var city := flat_city()
	var at := Vector2i(20,20)
	TourismFixture.venue(city,&"arcology_boddy",at)
	city.building.put(19,20,Buildings.ROAD_FIRST)
	city.stamp_building(24,20,Buildings.RAIL_STATION)
	for x in range(26,City.WIDTH): city.building.put(x,20,Buildings.RAIL_FIRST)
	var access := access_for(city)
	if access == null: return
	check(access.venue_access(at).external_reachable,"second frontage reaches station and rail edge")
	check_eq(access.venue_access(at).arrival_capacity,2000)
	city.building.put(80,20,0)
	access.refresh(TourismFixture.context(city))
	check(not access.venue_access(at).external_reachable,"raw rail cut invalidates graph")

func test_explicit_target_ignores_workplace_and_budget_is_pending() -> void:
	var city := flat_city()
	for x in range(0,30): city.building.put(x,10,Buildings.ROAD_FIRST)
	TourismFixture.venue(city,&"com_corner_store",Vector2i(20,11))
	var transport := TransportSystem.new()
	check(transport.has_method("route_to_targets"),"explicit target routing exists")
	if not transport.has_method("route_to_targets"): return
	var seeds := PackedInt32Array([29+10*128])
	var targets := PackedInt32Array([10*128])
	var rng := SimRng.new(7)
	var before := rng.state()
	var pending: Dictionary = transport.call("route_to_targets",city,seeds,targets,1)
	check_eq(pending.status,"pending")
	var result: Dictionary = transport.call("route_to_targets",city,seeds,targets,100)
	check_eq(result.status,"reachable")
	check_eq(result.path[-1],1280)
	check_eq(transport.trips_attempted(),0)
	check_eq(rng.state(),before)

func test_district_requires_a_real_join_not_two_nearby_roads() -> void:
	var city := flat_city()
	TourismFixture.venue(city,&"arcology_boddy",Vector2i(20,20))
	TourismFixture.venue(city,&"museum",Vector2i(30,20))
	city.building.put(19,20,Buildings.ROAD_FIRST)
	city.building.put(29,20,Buildings.ROAD_FIRST)
	var access := access_for(city)
	if access == null: return
	check(not access.district_connected(Rect2i(20,20,2,2),Rect2i(30,20,3,3)))
	for x in range(19,30): city.building.put(x,19,Buildings.ROAD_FIRST)
	access.refresh(TourismFixture.context(city))
	check(access.district_connected(Rect2i(20,20,2,2),Rect2i(30,20,3,3)))

func port_city(kind: int) -> City:
	var city := flat_city()
	for y in range(20,25):
		for x in range(30,35):
			city.zone.put(x,y,Zones.make(kind))
			city.set_flag(x,y,TileFlags.POWERED,true)
	if kind == Zones.AIRPORT:
		for x in range(30,35): city.building.put(x,20,Buildings.RUNWAY)
	else:
		city.building.put(34,20,Buildings.CRANE)
		for x in range(35,128):
			city.terrain.put(x,20,Terrain.make(Terrain.FLAT,Terrain.SURFACE))
			city.set_heights(x,20,2,4)
		for x in range(35,35+PortParams.PIER_LENGTH): city.building.put(x,20,Buildings.PIER)
	return city

func test_civilian_ports_need_landside_and_harbor_needs_open_sea() -> void:
	for kind in [Zones.AIRPORT,Zones.SEAPORT]:
		var city := port_city(kind)
		var ctx := TourismFixture.context(city)
		var ports := PortSystem.new()
		ports.setup(ctx)
		check(ports.has_method("tourism_gateways"),"pure port gateway discovery exists")
		if not ports.has_method("tourism_gateways"): continue
		var rng_before := ctx.rng.state()
		check_eq(ports.call("tourism_gateways").size(),0,"operating alone is insufficient")
		city.building.put(29,24,Buildings.ROAD_FIRST)
		check_eq(ports.call("tourism_gateways").size(),1)
		check_eq(ports.vehicles().size(),0,"discovery never spawns")
		check_eq(ctx.rng.state(),rng_before)
		if kind == Zones.SEAPORT:
			city.terrain.put(80,20,Terrain.FLAT)
			check_eq(ports.call("tourism_gateways").size(),0,"sealed water invalidates harbor")
		city.zone.data.fill(Zones.MILITARY)
		check_eq(ports.call("tourism_gateways").size(),0,"military ports excluded")

func test_gateway_seats_are_shared_arrivals_not_existing_guests() -> void:
	var rows: Array[Dictionary] = []
	for x in [10,30]:
		rows.append({"anchor":Vector2i(x,20),"key":&"arcology_afterglow","operating":true,
			"guests":2000,"external_reachable":true,"local_reachable":false,"gateway_ids":["west:road"]})
	var inputs := {"permanent_population":1000000,"gateways":[{"id":"west:road","kind":"road","capacity":500}]}
	var result := TourismDemand.forecast(rows,inputs,0,0)
	check(result.rows[0].has("arrival_reservation"),"forecast reserves shared gateway seats")
	if not result.rows[0].has("arrival_reservation"): return
	var used := 0
	for row: Dictionary in result.rows:
		used += int(row.arrival_reservation)+int(row.external_day_visitors)
		check_gt(row.arrival_reservation,0,"canonical weighted allocation serves both venues")
	check_eq(used,500)
	check_gt(result.rows[0].projected_guests,500,"arrival cap never evicts established guests")

func test_no_external_route_never_creates_overnight_but_resident_days_remain() -> void:
	var rows: Array[Dictionary] = [{"anchor":Vector2i(20,20),"key":&"arcology_boddy","operating":true,
		"guests":0,"external_reachable":false,"local_reachable":true,"gateway_ids":[]}]
	var result := TourismDemand.forecast(rows,{"permanent_population":10000,"gateways":[]},0,0)
	check_eq(result.rows[0].target_guests,0)
	check_gt(result.rows[0].target_day_visitors,0)
	rows[0].local_reachable = false
	result = TourismDemand.forecast(rows,{"permanent_population":10000,"gateways":[]},0,0)
	check_eq(result.rows[0].target_day_visitors,0)

func test_accepted_access_ledger_roundtrip_and_atomic_rejection() -> void:
	var ctx := TourismFixture.host_with_store()
	var tourism: TourismSystem = ctx.system(&"tourism")
	ctx.clock.day = 16
	ctx.city.day = 16
	tourism.monthly(ctx)
	var saved := tourism.save().duplicate(true)
	check(saved.features.access.has("month_id"),"accepted local/external arrivals have a durable ledger")
	if not saved.features.access.has("month_id"):
		ctx.systems.clear()
		return
	check_eq(saved.features.access.month_id,0)
	check_eq(saved.features.access.rows[0].local_day_visitors,0)
	check_gt(saved.features.access.rows[0].external_day_visitors,0)
	check_eq(tourism.finish_restore({"systems":{"tourism":JSON.parse_string(JSON.stringify(saved))}}),OK)
	check_eq(tourism.save().features.access,saved.features.access,"access counts normalize JSON numbers")
	check_eq(JSON.parse_string(JSON.stringify(tourism.save())),JSON.parse_string(JSON.stringify(saved)))
	saved = tourism.save().duplicate(true)
	for field in ["local_day_visitors","external_day_visitors","overnight_arrivals","instance"]:
		var bad: Dictionary = saved.duplicate(true)
		bad.features.access.rows[0][field] = 0.5
		check_eq(tourism.finish_restore({"systems":{"tourism":bad}}),ERR_INVALID_DATA)
		check_eq(tourism.save(),saved,"invalid detached ledger cannot replace active state")
	var bad: Dictionary = saved.duplicate(true)
	bad.features.access.rows.append(bad.features.access.rows[0].duplicate(true))
	check_eq(tourism.finish_restore({"systems":{"tourism":bad}}),ERR_INVALID_DATA)
	bad = saved.duplicate(true)
	bad.features.access.month_id = 1
	check_eq(tourism.finish_restore({"systems":{"tourism":bad}}),ERR_INVALID_DATA)
	for x in range(10): ctx.city.building.put(x,10,0)
	tourism.reconcile_now()
	check_eq(tourism.save().features.access,saved.features.access,"closing route preserves completed arrivals")
	check_eq(tourism.finish_restore({"systems":{"tourism":tourism.save()}}),OK,"historical gateway need not still exist")
	ctx.systems.clear()

func test_budget_pending_progresses_fairly_and_cached_reads_do_no_work() -> void:
	var city := flat_city()
	for at in [Vector2i(20,20),Vector2i(80,80)]:
		TourismFixture.venue(city,&"arcology_boddy",at)
		for x in range(at.x): city.building.put(x,at.y,Buildings.ROAD_FIRST)
	var access := access_for(city)
	if access == null: return
	# Invalidate both routes, then deliberately give this pass one SCC visit.
	city.building.put(100,100,Buildings.ROAD_FIRST)
	access.refresh(TourismFixture.context(city),1)
	check_eq(access.venue_access(Vector2i(80,80)).access_status,"pending")
	check(not access.venue_access(Vector2i(80,80)).external_reachable)
	check_eq(access.report().route_work,1)
	access.refresh(TourismFixture.context(city),1)
	check_eq(access.venue_access(Vector2i(80,80)).access_status,"reachable","older pending source progresses first")
	var before: Dictionary = access.report()
	for i in 10:
		access.venue_access(Vector2i(80,80))
		access.gateways()
	check_eq(access.report(),before)

func test_irregular_port_does_not_gain_bounding_rectangle_entrance() -> void:
	var city := flat_city()
	for x in range(20,41): city.zone.put(x,20,Zones.make(Zones.AIRPORT))
	for y in range(20,41): city.zone.put(20,y,Zones.make(Zones.AIRPORT))
	for x in range(20,25): city.building.put(x,20,Buildings.RUNWAY)
	city.set_flag(20,20,TileFlags.POWERED,true)
	city.building.put(40,39,Buildings.ROAD_FIRST)
	var ports := PortSystem.new()
	var ctx := TourismFixture.context(city)
	ports.setup(ctx)
	check_eq(ports.tourism_gateways().size(),0,"road inside remote empty bounding corner is no entrance")
	city.building.put(19,40,Buildings.ROAD_FIRST)
	check_eq(ports.tourism_gateways().size(),1)

func test_duplicate_airports_expand_pool_only_once_and_disconnected_types_never_do() -> void:
	var row := {"anchor":Vector2i(10,10),"key":&"arcology_afterglow","operating":true,"guests":0,
		"external_reachable":true,"local_reachable":false,"gateway_ids":["airport:10"]}
	var gateways: Array[Dictionary] = [{"id":"airport:10","kind":"airport","capacity":6000}]
	var first := TourismDemand.forecast([row],{"gateways":gateways},0,0)
	gateways.append({"id":"airport:20","kind":"airport","capacity":6000})
	row.gateway_ids.append("airport:20")
	var duplicate := TourismDemand.forecast([row],{"gateways":gateways},0,0)
	check_eq(first.guest_pool,duplicate.guest_pool)
	gateways.append({"id":"east:rail","kind":"rail","capacity":2000})
	var disconnected := TourismDemand.forecast([row],{"gateways":gateways},0,0)
	check_eq(first.guest_pool,disconnected.guest_pool)
	row.gateway_ids.append("east:rail")
	gateways.append({"id":"harbor:30","kind":"harbor","capacity":1500})
	row.gateway_ids.append("harbor:30")
	var all := TourismDemand.forecast([row],{"gateways":gateways},0,0)
	check_eq(all.guest_pool,262,"250 base * 150% reach * 70% appeal, truncated once")

func test_raw_bridge_removal_invalidates_a_real_resort_route() -> void:
	var city := flat_city()
	var at := Vector2i(20,20)
	TourismFixture.venue(city,&"arcology_boddy",at)
	for x in range(20): city.building.put(x,20,Buildings.ROAD_FIRST)
	city.building.put(10,20,Buildings.id_of(&"bridge_suspension_span"))
	var access := access_for(city)
	if access == null: return
	check(access.venue_access(at).external_reachable)
	city.building.put(10,20,Buildings.NONE)
	access.refresh(TourismFixture.context(city))
	check_eq(access.venue_access(at).access_status,"disconnected")

func test_dense_graph_is_bounded_and_warm_refresh_reuses_discovery() -> void:
	var city := flat_city()
	for y in City.HEIGHT:
		for x in City.WIDTH:
			city.building.put(x,y,Buildings.ROAD_FIRST if y%4 == 0 else Buildings.id_of(&"com_corner_store"))
	var began := Time.get_ticks_usec()
	var access := access_for(city)
	if access == null: return
	var cold := Time.get_ticks_usec()-began
	var before: Dictionary = access.report()
	began = Time.get_ticks_usec()
	access.refresh(TourismFixture.context(city))
	var warm := Time.get_ticks_usec()-began
	check_eq(access.report().graph_builds,before.graph_builds)
	check_eq(access.report().route_work,0)
	check_between(before.graph_states,1,98304)
	check_between(before.route_work,0,32768)
	check_between(before.cache_entries,0,1048576)
	print("TOURISM_ACCESS_DENSE cold_us=",cold," warm_us=",warm," evidence=",before)

func test_shared_road_highway_mouth_uses_stronger_capacity_with_both_modes() -> void:
	var city := flat_city()
	var at := Vector2i(20,20)
	TourismFixture.venue(city,&"arcology_boddy",at)
	for x in range(20): city.building.put(x,20,Buildings.ROAD_FIRST)
	city.building.put(0,20,Buildings.id_of(&"highway_ns_road_ew"))
	var access := access_for(city)
	if access == null: return
	check(access.venue_access(at).external_reachable,"underpass road reaches the shared mouth without a ramp")
	check_eq(access.venue_access(at).arrival_capacity,1500,"stronger shared mouth counted once")
	check_eq(access.gateways().size(),1)

func test_subway_and_tunnel_raw_edits_invalidate_external_access() -> void:
	var city := flat_city()
	var at := Vector2i(20,20)
	TourismFixture.venue(city,&"arcology_boddy",at)
	city.stamp_building(19,20,Buildings.SUBWAY_STATION)
	city.stamp_building(10,20,Buildings.SUBWAY_STATION)
	for x in range(11,19): city.underground.put(x,20,UtilityParams.SUBWAY_FIRST)
	for x in range(10): city.building.put(x,20,Buildings.ROAD_FIRST)
	var access := access_for(city)
	if access == null: return
	check(access.venue_access(at).external_reachable)
	city.underground.put(15,20,0)
	access.refresh(TourismFixture.context(city))
	check(not access.venue_access(at).external_reachable)
	city.underground.put(15,20,UtilityParams.SUBWAY_FIRST)
	city.building.put(5,20,0)
	city.altitude.data[20*128+5] |= (1 << City.TUNNEL_SHIFT)
	access.refresh(TourismFixture.context(city))
	check(access.venue_access(at).external_reachable)
	city.altitude.data[20*128+5] &= ~(31 << City.TUNNEL_SHIFT)
	access.refresh(TourismFixture.context(city))
	check(not access.venue_access(at).external_reachable)


func test_live_arrival_seats_preserve_survivors_and_history_after_raw_cut() -> void:
	var city := flat_city()
	var at := Vector2i(20,20)
	TourismFixture.venue(city,&"arcology_afterglow",at)
	TourismFixture.set_served(city,at,true,true)
	for x in range(20): city.building.put(x,20,Buildings.ROAD_FIRST)
	var ctx := TourismFixture.context(city)
	ctx.stats.population = 1000000
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN] = 10000 # Isolate gateway seats from labor.
	var tourism := TourismSystem.new()
	tourism.setup(ctx)
	check_eq(tourism.finish_restore({}),OK)
	var saved := tourism.save()
	saved.state.records[0].guests = 2000
	TourismFixture.segment_rows(saved.state.records)
	TourismFixture.reservation_rows(saved)
	check_eq(tourism.finish_restore({"systems":{"tourism":saved}}),OK)
	ctx.clock.day = 16
	ctx.city.day = 16
	tourism.monthly(ctx)
	var row := tourism.report()[0]
	check_gt(row.guests,1000,"only regular departures occur; survivors are not capped to seats")
	check(row.arrivals+row.day_visitors <= 500,"overnight and external day admissions share 500 seats")
	var accepted := tourism.accepted_access()
	var earned := tourism.pending_bases()
	city.building.put(10,20,0)
	tourism.reconcile_now()
	check_eq(tourism.report()[0].guests,row.guests,"daily route loss does not evict guests")
	check_eq(tourism.accepted_access(),accepted)
	check_eq(tourism.pending_bases(),earned)
	check_eq(tourism.forecast().rows[0].arrival_reservation,0)
	var budget := BudgetSystem.new()
	budget.setup(ctx)
	check_eq(TourismSaveCodec.problem({"clock_day":16,"systems":{"tourism":tourism.save(),"budget":budget.save()}},city),"")
	var forged := tourism.save().duplicate(true)
	forged.features.access.rows[0].gateways[0].count += 1
	check_ne(TourismSaveCodec.problem({"clock_day":16,"systems":{"tourism":forged,"budget":budget.save()}},city),"","native codec rejects inconsistent seat ledger")


func test_connected_resident_neighborhood_supplies_only_local_days() -> void:
	var city := flat_city()
	var at := Vector2i(20,20)
	TourismFixture.venue(city,&"arcology_boddy",at)
	TourismFixture.venue(city,&"res_bungalow_1",Vector2i(10,20))
	for x in range(10,20): city.building.put(x,19,Buildings.ROAD_FIRST)
	var access := access_for(city)
	if access == null: return
	check(access.venue_access(at).local_reachable)
	check(not access.venue_access(at).external_reachable)
	city.building.put(15,19,0)
	access.refresh(TourismFixture.context(city))
	check(not access.venue_access(at).local_reachable)

func test_venue_routes_to_each_real_civilian_port() -> void:
	for kind in [Zones.AIRPORT,Zones.SEAPORT]:
		var city := port_city(kind)
		var at := Vector2i(20,24)
		TourismFixture.venue(city,&"arcology_boddy",at)
		for x in range(22,30): city.building.put(x,24,Buildings.ROAD_FIRST)
		var access := access_for(city)
		if access == null: continue
		var rec: Dictionary = access.venue_access(at)
		check(rec.external_reachable)
		check_eq(rec.arrival_capacity,6000 if kind == Zones.AIRPORT else 1500)
		var route: Dictionary = access.route(at,rec.gateway_ids[0])
		check_eq(route.status,"reachable")
		check_gt(route.path.size(),0)
		city.building.put(26,24,0)
		access.refresh(TourismFixture.context(city))
		check(not access.venue_access(at).external_reachable)
