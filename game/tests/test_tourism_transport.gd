# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"

func trip_context(rail: bool = false, bus: bool = false) -> SimContext:
	var ctx := TourismFixture.context(flat_city())
	var at := Vector2i(20,20)
	TourismFixture.venue(ctx.city,&"arcology_boddy",at)
	TourismFixture.set_served(ctx.city,at,true,true)
	if rail:
		ctx.city.stamp_building(24,20,Buildings.RAIL_STATION)
		for x in range(26,128): ctx.city.building.put(x,20,Buildings.RAIL_FIRST)
	else:
		for x in range(20): ctx.city.building.put(x,20,Buildings.ROAD_FIRST)
	if bus: ctx.city.stamp_building(17,22,Buildings.BUS_DEPOT)
	ctx.stats.population = 10000
	var tourism := TourismSystem.new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	assert(tourism.finish_restore({}) == OK)
	ctx.clock.day = 16
	ctx.city.day = 16
	tourism.monthly(ctx)
	var transport := TransportSystem.new()
	ctx.systems[&"transport"] = transport
	ctx.clock.day = 38
	ctx.city.day = 38
	return ctx

func traffic_total(city: City) -> int:
	var total := 0
	for value in city.traffic.data: total += value
	return total

func tourist_report(transport: TransportSystem) -> Dictionary:
	check(transport.has_method("tourism_report"),"actual accepted tourists need a distinct transport report")
	return transport.call("tourism_report") if transport.has_method("tourism_report") else {}

func test_actual_accepted_visitors_use_road_without_resident_denominator() -> void:
	var ctx := trip_context()
	var transport: TransportSystem = ctx.system(&"transport")
	var rng_before := ctx.rng.state()
	transport.monthly(ctx)
	var report := tourist_report(transport)
	if not report.is_empty():
		check_gt(report.completed,0)
		check_gt(report.modes.car,0)
	check_gt(traffic_total(ctx.city),0,"real corridor carries accepted visitors")
	check_eq(transport.trips_attempted(),0,"tourists never become residential origins")
	check_eq(transport.trips_completed(),0)
	check_eq(transport.unreachable_ratio(),0.0)
	check_eq(ctx.rng.state(),rng_before)
	var once := ctx.city.traffic.data.duplicate()
	transport.monthly(ctx)
	check_eq(ctx.city.traffic.data,once,"same period cannot decay or publish tourist traffic again")
	ctx.systems.clear()

func test_rail_routes_divert_traffic_and_book_real_fares_once() -> void:
	var ctx := trip_context(true)
	var transport: TransportSystem = ctx.system(&"transport")
	transport.monthly(ctx)
	var report := tourist_report(transport)
	if not report.is_empty(): check_gt(report.modes.rail,0)
	check_eq(traffic_total(ctx.city),0)
	check_gt(int(report.get("modes",{}).get("rail",0)),0,"accepted rail visitors use existing fare path")
	var budget := BudgetSystem.new()
	ctx.systems[&"budget"] = budget
	budget.setup(ctx)
	budget.monthly(ctx)
	var once := budget.save()
	budget.monthly(ctx)
	check_eq(budget.save().carry.get("transit_fares",0),once.carry.get("transit_fares",0),"tourist fare cannot replay")
	transport.monthly(ctx)
	check_eq(transport.call("tourism_report") if transport.has_method("tourism_report") else {},report)
	ctx.systems.clear()

func test_reports_forecasts_and_lost_route_do_not_rewrite_accepted_business() -> void:
	var ctx := trip_context()
	var tourism: TourismSystem = ctx.system(&"tourism")
	var before := tourism.save()
	ctx.city.building.put(5,20,0)
	tourism.networks_changed(ctx,Rect2i(5,20,1,1))
	var transport: TransportSystem = ctx.system(&"transport")
	transport.monthly(ctx)
	var report := tourist_report(transport)
	if not report.is_empty():
		check_eq(report.completed,0)
		check_gt(report.disconnected,0)
	var traffic := ctx.city.traffic.data.duplicate()
	for i in 3:
		tourism.forecast()
		if transport.has_method("tourism_report"): transport.call("tourism_report")
	check_eq(ctx.city.traffic.data,traffic)
	check_eq(tourism.save().activity,before.activity)
	ctx.systems.clear()

func test_bus_frontage_diverts_real_road_trips() -> void:
	var ctx := trip_context(false,true)
	var transport: TransportSystem = ctx.system(&"transport")
	# Depot is a valid second frontage and joins the corridor through its west edge.
	for y in range(20,25): ctx.city.building.put(16,y,Buildings.ROAD_FIRST)
	(ctx.system(&"tourism") as TourismSystem).networks_changed(ctx,Rect2i(16,20,4,5))
	transport.monthly(ctx)
	var report := tourist_report(transport)
	if not report.is_empty(): check_gt(report.modes.bus,0,"station entrance takes an actual bus path")
	check_eq(traffic_total(ctx.city),0,"bus diverts the completed cohort away from cars")
	ctx.systems.clear()

func test_resident_origins_work_and_rng_are_independent() -> void:
	var ctx := trip_context()
	ctx.city.stamp_building(5,21,Buildings.id_of(&"res_bungalow_1"))
	var control := TourismFixture.context(flat_city())
	# Identical raw layers, including the same residential/workplace footprints.
	control.city.building.data = ctx.city.building.data.duplicate()
	control.city.zone.data = ctx.city.zone.data.duplicate()
	var residents := TransportSystem.new()
	var visitors: TransportSystem = ctx.system(&"transport")
	residents.monthly(control)
	visitors.monthly(ctx)
	check_gt(residents.trips_attempted(),0,"comparison includes actual residential origins")
	check_eq(visitors.trips_attempted(),residents.trips_attempted())
	check_eq(visitors.trips_completed(),residents.trips_completed())
	check_eq(visitors.states_searched(),residents.states_searched())
	check_eq(visitors.unreachable_ratio(),residents.unreachable_ratio())
	check_gt(traffic_total(ctx.city),traffic_total(control.city))
	ctx.systems.clear()

func test_trip_state_roundtrip_and_malformed_guard_reject_atomically() -> void:
	var ctx := trip_context(true)
	var transport: TransportSystem = ctx.system(&"transport")
	transport.monthly(ctx)
	var tourism: TourismSystem = ctx.system(&"tourism")
	var saved := tourism.save().duplicate(true)
	check_eq(tourism.finish_restore({"systems":{"tourism":JSON.parse_string(JSON.stringify(saved))}}),OK)
	check_eq(tourism.save().features.access,saved.features.access)
	check_eq(JSON.parse_string(JSON.stringify(tourism.save())),JSON.parse_string(JSON.stringify(saved)))
	var before := tourism.save()
	for field in ["cursor","processed_month","pass_month","pending_fare_riders"]:
		var bad := saved.duplicate(true)
		bad.features.access.transport[field] = -2
		check_eq(tourism.finish_restore({"systems":{"tourism":bad}}),ERR_INVALID_DATA,field)
		check_eq(tourism.save(),before,"atomic refusal")
	var report := transport.call("tourism_report") as Dictionary
	transport.monthly(ctx)
	check_eq(transport.call("tourism_report"),report,"saved period prevents replay")
	ctx.systems.clear()

@warning_ignore("integer_division")
func test_maximum_venue_sample_conserves_weights_and_rotates() -> void:
	var transport := TransportSystem.new()
	var live := {}
	var rows: Array[Dictionary] = []
	for i in 12288:
		live[i+1] = {"instance":i+1,"anchor":Vector2i(i%128,i/128),"key":&"com_corner_store"}
		rows.append({"instance":i+1,"local_day_visitors":24,"gateways":[]})
	var ledger := {"month_id":0,"rows":rows}
	var seen := {}
	var periods := ceili(12288.0/float(TransportSystem.TOURIST_ORIGINS))
	var started := Time.get_ticks_usec()
	for period in periods:
		var sample: Dictionary = transport.call("_tourist_jobs",ledger,live,period,TransportSystem.TOURIST_ORIGINS)
		check_eq(sample.represented,12288*24)
		check_eq(sample.unsampled,0)
		var total := 0
		for job: Dictionary in sample.jobs:
			total += int(job.weight)
			seen[int(job.instance)] = true
		check_eq(total,sample.represented,"cohort weights conserve actual local visitors")
	check_eq(seen.size(),12288,"every eligible venue eventually represents a cohort")
	print("TOURIST_SAMPLE origins=",TransportSystem.TOURIST_ORIGINS," venues=12288 coverage_periods=",periods," elapsed_us=",Time.get_ticks_usec()-started)

func test_dense_actual_accepted_pass_has_bounded_work_and_pending_age() -> void:
	var ctx := TourismFixture.context(flat_city())
	for y in City.HEIGHT:
		for x in City.WIDTH:
			if y%4 == 0 or x == 0: ctx.city.building.put(x,y,Buildings.ROAD_FIRST)
			else:
				TourismFixture.venue(ctx.city,&"com_corner_store",Vector2i(x,y))
				TourismFixture.set_served(ctx.city,Vector2i(x,y),true,true)
	ctx.city.building.put(1,1,Buildings.id_of(&"res_bungalow_1"))
	ctx.stats.population = 1000000
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN] = 100000 # Transport scale fixture supplies the workforce for its synthetic city.
	var tourism := TourismSystem.new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	check_eq(tourism.finish_restore({}),OK)
	ctx.clock.day = 16
	ctx.city.day = 16
	tourism.monthly(ctx)
	var transport := TransportSystem.new()
	ctx.systems[&"transport"] = transport
	ctx.clock.day = 38
	ctx.city.day = 38
	var started := Time.get_ticks_usec()
	transport.monthly(ctx)
	var elapsed := Time.get_ticks_usec()-started
	var report := tourist_report(transport)
	check_gt(report.completed,0)
	check_eq(report.pending_jobs,0,"shared reverse routes complete the dense maximum cohort")
	check_between(report.states_searched,1,TransportSystem.TOURIST_SEARCH_WORK)
	check_between(report.path_states,1,TransportSystem.TOURIST_PATH_WORK)
	check_between(report.sampled_origins,1,TransportSystem.TOURIST_ORIGINS)
	check_eq(report.attempted,report.completed+report.pending+report.disconnected+report.cancelled)
	print("TOURIST_DENSE actual_venues=",tourism.report().size()," elapsed_us=",elapsed," access=",tourism.access_routes().report()," transport=",report)
	# Compare the same frozen topology without a tourism owner, then measure
	# actual completed representative coverage over the conserved source cohorts.
	ctx.systems.erase(&"tourism")
	var empty_transport := TransportSystem.new()
	started = Time.get_ticks_usec()
	empty_transport.monthly(ctx)
	var empty_us := Time.get_ticks_usec()-started
	ctx.systems[&"tourism"] = tourism
	var live := {}
	for row: Dictionary in tourism.report(): live[int(row.instance)] = row
	var ledger := tourism.accepted_access()
	var wanted := {}
	for row: Dictionary in ledger.rows:
		if int(row.local_day_visitors) > 0: wanted[str(row.instance)+":local"] = true
		for gateway: Dictionary in row.gateways: wanted[str(row.instance)+":"+String(gateway.id)] = true
	var seen := {}
	var coverage := 0
	var max_work := 0
	for period in 64:
		tourism.access_routes().begin_trip_pass()
		var sample: Dictionary = transport.call("_tourist_jobs",ledger,live,period,TransportSystem.TOURIST_ORIGINS)
		var work := 0
		for job: Dictionary in sample.jobs:
			var at := Vector2i(int(job.anchor[0]),int(job.anchor[1]))
			var route := tourism.access_routes().trip_route(at,job.gateway,TransportSystem.TOURIST_SEARCH_WORK-work)
			work += int(route.work)
			if route.status == "reachable": seen[str(job.instance)+":"+String(job.gateway)] = true
		max_work = maxi(max_work,work)
		coverage = period+1
		if seen.size() == wanted.size(): break
	check_eq(seen.size(),wanted.size(),"actual successful representatives cover every accepted allocation")
	check_between(coverage,1,16)
	print("TOURIST_DENSE_COVERAGE accepted_allocations=",wanted.size()," completed_representatives=",seen.size()," periods=",coverage," max_states=",max_work," no_tourism_same_topology_us=",empty_us)

	ctx.systems.clear()

func test_reverse_pending_frontier_progresses_and_raw_cut_invalidates_it() -> void:
	var ctx := trip_context()
	var tourism: TourismSystem = ctx.system(&"tourism")
	var access := tourism.access_routes()
	var first := access.trip_route(Vector2i(20,20),"west:road",1)
	check_eq(first.status,"pending")
	var work := int(first.work)
	var result := first
	for i in 100:
		if result.status != "pending": break
		result = access.trip_route(Vector2i(20,20),"west:road",1)
		work += int(result.work)
	check_eq(result.status,"reachable","retained reverse search advances beyond the same first state")
	check_between(work,1,40)
	ctx.city.building.put(5,20,0)
	var transport: TransportSystem = ctx.system(&"transport")
	transport.monthly(ctx)
	check_eq(transport.call("tourism_report").completed,0,"raw edit invalidates cached successful trip")
	ctx.systems.clear()

func test_many_airports_long_routes_retain_bounded_pending_and_finish_oldest() -> void:
	var ctx := TourismFixture.context(flat_city())
	ctx.city.building.data.fill(Buildings.ROAD_FIRST)
	for y in [4,12]:
		for x in range(4,120,8):
			for dy in 4:
				for dx in 5:
					ctx.city.zone.put(x+dx,y+dy,Zones.make(Zones.AIRPORT))
					ctx.city.building.put(x+dx,y+dy,Buildings.RUNWAY if dy == 0 else Buildings.NONE)
					ctx.city.set_flag(x+dx,y+dy,TileFlags.POWERED,true)
	for y in [80,88,96,104]:
		for x in range(4,120,8):
			TourismFixture.venue(ctx.city,&"arcology_afterglow",Vector2i(x,y))
			TourismFixture.set_served(ctx.city,Vector2i(x,y),true,true)
	var tourism := TourismSystem.new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	check_eq(tourism.finish_restore({}),OK)
	ctx.stats.population = 1000000
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN] = 100000 # Transport scale fixture supplies the workforce for its synthetic city.
	ctx.clock.day = 16
	ctx.city.day = 16
	tourism.monthly(ctx)
	var transport := TransportSystem.new()
	ctx.systems[&"transport"] = transport
	var completed_gateways := {}
	var allocated_gateways := {}
	var eligible_periods := {}
	for row: Dictionary in tourism.accepted_access().rows:
		for gateway: Dictionary in row.gateways:
			allocated_gateways[gateway.id] = true
			eligible_periods[gateway.id] = 1
	var work := 0
	var max_pending := 0
	var age := 0
	var started := Time.get_ticks_usec()
	for month in range(1,34):
		ctx.clock.day = month*25+7
		ctx.city.day = ctx.clock.day
		transport.monthly(ctx)
		var report := tourist_report(transport)
		for completed: Dictionary in transport.tourism_samples(): completed_gateways[completed.gateway] = true
		work += int(report.states_searched)
		max_pending = maxi(max_pending,int(report.pending_jobs))
		check_between(report.states_searched,0,TransportSystem.TOURIST_SEARCH_WORK)
		check_between(report.path_states,0,TransportSystem.TOURIST_PATH_WORK)
		check_between(report.pending_jobs,0,TransportSystem.TOURIST_QUEUE)
		check_between(tourism.access_routes().report().trip_cache_entries,0,TourismAccess.TRIP_CACHE_ENTRIES)
		check_eq(report.attempted,report.completed+report.pending+report.disconnected+report.cancelled)

		if month == 1 and report.pending_jobs > 0:
			var saved := tourism.save().duplicate(true)
			var json: Dictionary = JSON.parse_string(JSON.stringify(saved))
			check_eq(tourism.finish_restore({"systems":{"tourism":json}}),OK,"bounded accepted pending jobs survive JSON restoration")
			check_eq(tourism.save().features.access,saved.features.access)
			for change in [{"weight":0},{"source_count":0},{"period":99},{"instance":999999},{"cohort":0.5},{"anchor":[127,127]}]:
				var bad := saved.duplicate(true)
				bad.features.access.transport.pending[0].merge(change,true)
				check_eq(tourism.finish_restore({"systems":{"tourism":bad}}),ERR_INVALID_DATA,"malformed queued source refuses atomically")
				check_eq(tourism.save().features.access,saved.features.access)
			var duplicate := saved.duplicate(true)
			duplicate.features.access.transport.pending.append(duplicate.features.access.transport.pending[0].duplicate(true))
			check_eq(tourism.finish_restore({"systems":{"tourism":duplicate}}),ERR_INVALID_DATA)
		if report.pending_jobs == 0: break
		age += 1
		# Rebuild the graph after a raw edit: no saved arbitrary frontier is needed
		# for the oldest accepted job to get a full-state allowance next month.
		ctx.city.altitude.data[0] += 16
	check_eq(tourist_report(transport).pending_jobs,0,"historical jobs finish despite repeated invalidation")
	print("TOURIST_MANY_PORTS venues=60 airports=30 max_pending_jobs=",max_pending," pending_age_periods=",age," summed_states=",work," elapsed_us=",Time.get_ticks_usec()-started," final=",tourist_report(transport))
	var budget := BudgetSystem.new()
	ctx.systems[&"budget"] = budget
	budget.setup(ctx)
	var representative_periods := 0
	var max_age := 0
	for period in 12:
		budget.monthly(ctx)
		ctx.clock.day = (period+3)*25+16
		ctx.city.day = ctx.clock.day
		tourism.monthly(ctx)
		var eligible_now := {}
		for row: Dictionary in tourism.accepted_access().rows:
			for gateway: Dictionary in row.gateways:
				allocated_gateways[gateway.id] = true
				eligible_now[gateway.id] = true
		for gateway: String in eligible_now: eligible_periods[gateway] = int(eligible_periods.get(gateway,0))+1
		ctx.clock.day = (period+4)*25+7
		ctx.city.day = ctx.clock.day
		transport.monthly(ctx)
		for completed: Dictionary in transport.tourism_samples(): completed_gateways[completed.gateway] = true
		var result := tourist_report(transport)
		check_between(result.states_searched,0,TransportSystem.TOURIST_SEARCH_WORK)
		check_between(result.pending_jobs,0,TransportSystem.TOURIST_QUEUE)
		if result.oldest_pending_month >= 0: max_age = maxi(max_age,period+4-int(result.oldest_pending_month))
		representative_periods = period+1
		if completed_gateways.size() == allocated_gateways.size() and result.pending_jobs == 0: break
	for gateway: String in allocated_gateways:
		if int(eligible_periods.get(gateway,0)) >= 4:
			check(completed_gateways.has(gateway),"budget exhaustion cannot permanently hide accepted gateway "+gateway+" eligible_periods="+str(eligible_periods.get(gateway,0)))
		elif not completed_gateways.has(gateway): print("TOURIST_TRANSIENT_UNSAMPLED gateway=",gateway," eligible_periods=",eligible_periods.get(gateway,0))
	print("TOURIST_MIXED_COVERAGE allocated_gateways=",allocated_gateways.size()," completed_gateways=",completed_gateways.size()," additional_accepted_periods=",representative_periods," maximum_queued_age=",max_age," final=",tourist_report(transport))

	ctx.systems.clear()

func test_native_local_continuation_keep_fare_and_trip_guards() -> void:
	var ctx := trip_context(true)
	var transport: TransportSystem = ctx.system(&"transport")
	transport.monthly(ctx)
	var original_budget := BudgetSystem.new()
	ctx.systems[&"budget"] = original_budget
	original_budget.setup(ctx)
	var snapshot := {"clock_day":ctx.clock.day,"stats":ctx.stats.to_dict(),
		"systems":{"tourism":ctx.system(&"tourism").save(),"transport":transport.save(),"budget":original_budget.save()}}
	var directory := "user://tourist-transport-continuation"
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("local.sc2d")
	check_eq(TourismSaveCodec.problem(snapshot,ctx.city),"","detached native tourism validation")
	check_eq(SaveFormat.validate_snapshot(snapshot),"","general snapshot shape")
	check_eq(SaveFormat.save(path,ctx.city,snapshot),OK)
	var paths := [path]
	for saved_path: String in paths:
		var loaded := SaveFormat.load(saved_path)
		check(loaded.ok,str(loaded.get("detail","")))
		if not loaded.ok: continue
		var twin := TourismFixture.context(loaded.city)
		twin.clock.day = ctx.clock.day
		twin.stats.from_dict(loaded.snapshot.stats)
		var tourism := TourismSystem.new()
		twin.systems[&"tourism"] = tourism
		tourism.setup(twin)
		check_eq(tourism.finish_restore(loaded.snapshot),OK)
		var trips := TransportSystem.new()
		twin.systems[&"transport"] = trips
		trips.setup(twin)
		trips.load(loaded.snapshot.systems.transport)
		var before := tourism.transport_state()
		var traffic := twin.city.traffic.data.duplicate()
		trips.monthly(twin)
		check_eq(tourism.transport_state(),before,"native guard prevents trip replay")
		check_eq(twin.city.traffic.data,traffic,"same pass cannot decay or publish twice")
		var budget := BudgetSystem.new()
		twin.systems[&"budget"] = budget
		budget.setup(twin)
		budget.load(loaded.snapshot.systems.budget)
		budget.monthly(twin)
		var fares := int(budget.save().carry.get("transit_fares",0))
		check_gt(fares,0,"completed rides, not a forecast, earn fares")
		check_eq(fares,int(before.pending_fare_riders)*BudgetParams.FARE_CENTS*12)
		budget.monthly(twin)
		check_eq(int(budget.save().carry.get("transit_fares",0)),fares)
		twin.systems.clear()
	remove_test_tree(directory)
	ctx.systems.clear()


func remove_test_tree(path: String) -> void:
	for folder in DirAccess.get_directories_at(path): remove_test_tree(path.path_join(folder))
	for name in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)

func test_mixed_airport_harbor_rail_and_road_allocations_finish_current_paths() -> void:
	var ctx := TourismFixture.context(flat_city())
	ctx.city.building.data.fill(Buildings.ROAD_FIRST)
	for x in [4,20,36,52]:
		for dy in 4:
			for dx in 5:
				ctx.city.zone.put(x+dx,4+dy,Zones.make(Zones.AIRPORT))
				ctx.city.building.put(x+dx,4+dy,Buildings.RUNWAY if dy == 0 else Buildings.NONE)
				ctx.city.set_flag(x+dx,4+dy,TileFlags.POWERED,true)
	for y in range(40,44):
		ctx.city.zone.put(119,y,Zones.make(Zones.SEAPORT))
		ctx.city.set_flag(119,y,TileFlags.POWERED,true)
	ctx.city.building.put(119,40,Buildings.CRANE)
	for x in range(120,124): ctx.city.building.put(x,40,Buildings.PIER)
	for x in range(124,128):
		ctx.city.building.put(x,40,Buildings.NONE)
		ctx.city.terrain.put(x,40,Terrain.make(Terrain.FLAT,Terrain.SURFACE))
		ctx.city.set_heights(x,40,2,4)
	for x in 128: ctx.city.building.put(x,64,Buildings.RAIL_FIRST)
	ctx.city.stamp_building(20,64,Buildings.RAIL_STATION)
	for y in [80,88,96,104]:
		for x in range(4,120,8):
			TourismFixture.venue(ctx.city,&"arcology_afterglow",Vector2i(x,y))
			TourismFixture.set_served(ctx.city,Vector2i(x,y),true,true)
	var tourism := TourismSystem.new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	check_eq(tourism.finish_restore({}),OK)
	ctx.stats.population = 1000000
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN] = 100000 # Transport scale fixture supplies the workforce for its synthetic city.
	ctx.clock.day = 16
	ctx.city.day = 16
	tourism.monthly(ctx)
	var gateway_kinds := {}
	for gateway: Dictionary in tourism.access_routes().gateways(): gateway_kinds[gateway.id] = gateway.kind
	var allocated := {}
	for row: Dictionary in tourism.accepted_access().rows:
		for gateway: Dictionary in row.gateways: allocated[gateway_kinds[gateway.id]] = true
	for kind in ["airport","harbor","rail","road"]: check(allocated.has(kind),"fixture actually admits through "+kind)
	var transport := TransportSystem.new()
	ctx.systems[&"transport"] = transport
	var budget := BudgetSystem.new()
	ctx.systems[&"budget"] = budget
	budget.setup(ctx)
	var completed := {}
	var summed_work := 0
	var max_pending := 0
	var elapsed := Time.get_ticks_usec()
	var passes := 0
	for month in range(1,34):
		ctx.clock.day = month*25+7
		ctx.city.day = ctx.clock.day
		transport.monthly(ctx)
		passes += 1
		var report := tourist_report(transport)
		summed_work += int(report.states_searched)
		max_pending = maxi(max_pending,int(report.pending_jobs))
		check_between(report.states_searched,0,TransportSystem.TOURIST_SEARCH_WORK)
		check_between(report.path_states,0,TransportSystem.TOURIST_PATH_WORK)
		for sample: Dictionary in transport.tourism_samples(): completed[gateway_kinds[sample.gateway]] = true

		if completed.size() == 4: break
		# An unstarted cohort was explicitly unsampled, not a historical queue.
		# A fresh accepted period exercises the saved gateway rotation and
		# proves that the late harbor remains eligible under the work cap.
		budget.monthly(ctx)
		ctx.clock.day = month*25+16
		ctx.city.day = ctx.clock.day
		tourism.monthly(ctx)
	for kind in ["airport","harbor","rail","road"]: check(completed.has(kind),"current explicit trip completed through "+kind)

	var drain_month := passes+1
	for i in 32:
		if tourist_report(transport).pending_jobs == 0: break
		ctx.clock.day = drain_month*25+7
		ctx.city.day = ctx.clock.day
		transport.monthly(ctx)
		drain_month += 1
	check_eq(tourist_report(transport).pending_jobs,0)
	print("TOURIST_MIXED_KINDS accepted=",allocated.keys()," completed=",completed.keys()," passes=",passes," max_pending=",max_pending," summed_states=",summed_work," elapsed_us=",Time.get_ticks_usec()-elapsed)
	ctx.systems.clear()

func internal_job_context(key: StringName = &"arcology_boddy", south: bool = false) -> SimContext:
	var ctx := TourismFixture.context(flat_city())
	var at := Vector2i(20,20)
	TourismFixture.venue(ctx.city,key,at)
	TourismFixture.set_served(ctx.city,at,true,true)
	var size := Buildings.size(Buildings.id_of(key))
	var road_y := 20+size.y if south else 19
	for x in range(10,21+size.x): ctx.city.building.put(x,road_y,Buildings.ROAD_FIRST)
	ctx.city.stamp_building(10,road_y-1,Buildings.id_of(&"res_bungalow_1"))
	ctx.stats.population = 1000
	ctx.stats.cohorts[PopulationParams.WORK_COHORT_MIN] = 500
	var tourism := TourismSystem.new()
	ctx.systems[&"tourism"] = tourism
	tourism.setup(ctx)
	check_eq(tourism.finish_restore({}),OK)
	ctx.clock.day = 16
	ctx.city.day = 16
	tourism.monthly(ctx)
	ctx.systems[&"transport"] = TransportSystem.new()
	ctx.clock.day = 38
	ctx.city.day = 38
	return ctx

func test_internal_resident_commute_reaches_accepted_resort_jobs() -> void:
	var ctx := internal_job_context()
	var tourism := ctx.system(&"tourism") as TourismSystem
	var transport := ctx.system(&"transport") as TransportSystem
	check_gt(tourism.jobs(),0)
	var before := [ctx.stats.population,ctx.stats.cohorts.duplicate(),ctx.rng.state(),tourism.save().activity]
	transport.monthly(ctx)
	check_eq(transport.trips_attempted(),1)
	check_eq(transport.trips_completed(),1,"internal corridor has only an accepted resort employer")
	check_eq(transport.unreachable_ratio(),0.0)
	check_eq([ctx.stats.population,ctx.stats.cohorts,ctx.rng.state(),tourism.save().activity],before)
	check_eq(transport.save().riders_month,{"bus":0,"rail":0,"subway":0})
	ctx.systems.clear()

func test_all_resorts_and_every_frontage_use_current_accepted_identity() -> void:
	var count := 0
	for code in Buildings.COUNT:
		var key := Buildings.key(code)
		if TourismParams.guest_capacity(key)==0: continue
		count += 1
		for south in [false,true]:
			var ctx := internal_job_context(key,south)
			var transport := ctx.system(&"transport") as TransportSystem
			transport.setup(ctx)
			var size := Buildings.size(code)
			var home := Vector2i(10,19+size.y if south else 18)
			check(transport.trace_trip(ctx.city,home).reached,"accepted employer "+String(key)+" south="+str(south))
			# Same code/footprint, different instance: never inherit accepted jobs.
			ctx.city.facility(Vector2i(20,20)).tourism_instance += 100000
			check(not transport.trace_trip(ctx.city,home).reached,"replacement cannot inherit accepted job destination")
			ctx.systems.clear()
	check_eq(count,14)

func test_resort_commute_closure_demolition_restore_and_growth_feedback() -> void:
	var ctx := internal_job_context()
	var tourism := ctx.system(&"tourism") as TourismSystem
	var transport := ctx.system(&"transport") as TransportSystem
	transport.setup(ctx)
	var saved := tourism.save()
	check_eq(tourism.finish_restore({"systems":{"tourism":saved}}),OK)
	transport.monthly(ctx)
	var zones := ZoneSystem.new()
	zones.setup(ctx)
	zones.monthly(ctx,1)
	zones._land_value = ctx.city.land_value.data
	zones._pollution = ctx.city.pollution.data
	zones._crime = ctx.city.crime.data
	zones._raw_demand = Vector3i(100,100,100)
	check_eq(zones._commute_success,1.0)
	check_gt(zones._growth_points(Vector2i(10,18),0,true),0,"reachable accepted jobs preserve residential growth")
	ctx.city.building.put(15,19,0)
	check(not transport.trace_trip(ctx.city,Vector2i(10,18)).reached,"disconnected employer is unreachable")
	ctx.city.building.put(15,19,Buildings.ROAD_FIRST)
	TourismFixture.set_served(ctx.city,Vector2i(20,20),false,true)
	tourism.reconcile_now()
	check_eq(tourism.jobs(),0)
	check(not transport.trace_trip(ctx.city,Vector2i(10,18)).reached,"closed employer clears dynamic frontages")
	ctx.clock.day += 25
	ctx.city.day = ctx.clock.day
	transport.monthly(ctx)
	zones.monthly(ctx,1)
	zones._land_value = ctx.city.land_value.data
	zones._pollution = ctx.city.pollution.data
	zones._crime = ctx.city.crime.data
	zones._raw_demand = Vector3i(100,100,100)
	check_eq(zones._growth_points(Vector2i(10,18),0,true),0,"failed commute applies ordinary residential penalty")
	TourismFixture.set_served(ctx.city,Vector2i(20,20),true,true)
	tourism.reconcile_now()
	check(not transport.trace_trip(ctx.city,Vector2i(10,18)).reached,"reopened venue awaits accepted jobs")
	# A real border escape remains ordinary behavior with no tourism workplace.
	for x in range(10): ctx.city.building.put(x,19,Buildings.ROAD_FIRST)
	check(transport.trace_trip(ctx.city,Vector2i(10,18)).reached)
	ctx.city.building.put(5,19,0)
	ctx.city.clear_footprint(20,20)
	tourism.reconcile_now()
	check(not transport.trace_trip(ctx.city,Vector2i(10,18)).reached)
	check_eq(tourism.job_tiles().size(),0)
	ctx.systems.clear()
