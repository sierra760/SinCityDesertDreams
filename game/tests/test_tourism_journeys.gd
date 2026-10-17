# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
## Actual paid-host acceptance. No attendance/service flags or mid-journey grants.
extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/helpers/host_fixture.gd")
const STARTING_FUNDS := 100000
const RESORT := Vector2i(40,40)
var host: GameHost
var paid: Array[Dictionary] = []

func before_each() -> void:
	host = Fixture.make_host(self,"tourism-journeys")
	var city := flat_city(STARTING_FUNDS)
	city.name = "Paid Tourism Acceptance"
	host.begin_city(city,{},123,null)
	host.sim.set_process(false)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.sim.stats.disasters_enabled = false
	paid.clear()

func after_each() -> void:
	for other in extra_hosts:
		if is_instance_valid(other): other.free()
	extra_hosts.clear()
	cloud_devices.clear()
	cloud_service = null
	host.free()
	await process_frame

func paint(tool: int, at: Vector2i, end := Vector2i(-1,-1)) -> void:
	if end.x < 0: end = at
	host.select_tool(tool)
	var before := host.sim.city.funds
	var result := host.handle_drag(at,end)
	check(result.get("applied",false),"paid host tool %d at %s: %s" % [tool,at,result])
	check_eq(host.sim.city.funds,before-int(result.get("cost",-1)),"exact paid delta")
	check_gt(int(result.get("cost",0)),0,"construction is paid")
	paid.append({"tool":tool,"from":[at.x,at.y],"to":[end.x,end.y],"before":before,"cost":result.get("cost",-1),"after":host.sim.city.funds})

func services(with_resort := true, with_zones := false) -> void:
	paint(Tools.Kind.COAL_PLANT,Vector2i(32,36))
	paint(Tools.Kind.POWER_LINE,Vector2i(36,37),Vector2i(55,37))
	paint(Tools.Kind.WATER_PUMP,Vector2i(38,38))
	paint(Tools.Kind.WATER_PIPE,Vector2i(38,39),Vector2i(55,39))
	for x in [40,44,48,52,55]: paint(Tools.Kind.POWER_LINE,Vector2i(x,38),Vector2i(x,39))
	paint(Tools.Kind.ROAD,Vector2i(55,43),Vector2i(0,43))
	var link_before := host.sim.city.funds
	check(host.choice_dialog.visible,"border road offers paid neighbor connection")
	host.choice_dialog.build_button.pressed.emit()
	check_eq(link_before-host.sim.city.funds,100,"accepted regional road link costs $100")
	check(Buildings.is_road_like(host.sim.city.building_at(0,43)))
	paid.append({"tool":Tools.Kind.ROAD,"from":[0,43],"to":[0,43],"before":link_before,"cost":100,"after":host.sim.city.funds})
	if with_resort: paint(Tools.Kind.ARCOLOGY_BODDY,RESORT)
	if with_zones:
		for x in range(40,56): paint(Tools.Kind.WATER_PIPE,Vector2i(x,40),Vector2i(x,46))
		paint(Tools.Kind.POWER_LINE,Vector2i(39,38),Vector2i(39,47))
		paint(Tools.Kind.POWER_LINE,Vector2i(40,47),Vector2i(55,47))
		paint(Tools.Kind.ZONE_COM_LOW,Vector2i(44,40),Vector2i(55,42))
	var expense := 0
	for item in paid: expense += int(item.cost)
	check_eq(expense,4864 + (8000 if with_resort else 0) + (568 if with_zones else 0),"literal planned infrastructure/zoning/venue costs")
	check_eq(host.sim.city.funds,STARTING_FUNDS-expense,"construction ledger reconciles to declared initial treasury")
	host.select_tool(Tools.Kind.QUERY)

func run_to(day: int) -> void:
	while host.sim.clock.day < day:
		if host.sim.budget_review_pending:
			(host.windows.budget as BudgetWindow).close()
		host.sim.advance_day()

func assert_served(at: Vector2i) -> void:
	var size := Buildings.size(host.sim.city.building.atv(at))
	for y in range(at.y,at.y+size.y):
		for x in range(at.x,at.x+size.x):
			check(host.sim.city.is_powered(x,y),"real power throughout venue")
			check(host.sim.city.is_watered(x,y),"real water throughout venue")
	check(ZoneSystem.has_access(host.sim.city,Rect2i(at,size)),"real street access")

func test_paid_store_and_resort_host_journey() -> void:
	services(true,true)
	assert_served(RESORT)
	host.city_view_3d.set_camera_state(Vector3(46,2.4,41),0,25)
	run_to(16)
	check_eq(host.sim.stats.tourists,0,"no early admissions")
	host.sim.advance_day()
	var tourism := host.sim.tourism()
	check_gt(tourism.venue_report(RESORT).guests,0,"day17 admits guests using actual networks")
	retain_host("paid-day17")
	var pending := tourism.pending_bases()
	check_gt(int(pending.get("lodging_cents",0)),0)
	var demand_occupancy := host.sim.stats.tax_occupancy
	var demand_gaming := host.sim.stats.tax_gaming
	check_eq(int(pending.get("occupancy_rate",-1)),demand_occupancy,"completed business records its demand occupancy rate")
	check_eq(int(pending.get("gaming_rate",-1)),demand_gaming,"completed business records its demand gaming rate")
	var budget := host.open_window("budget") as BudgetWindow
	budget._tax_spinners[&"occupancy"].value = 9
	budget._tax_spinners[&"gaming"].value = 11
	check_eq(host.sim.stats.tax_occupancy,9,"actual occupancy control writes rate")
	check_eq(host.sim.stats.tax_gaming,11,"actual gaming control writes rate")
	await capture_host("paid-budget-rate-controls")
	budget.close()
	host.sim.advance_day()
	var books := host.sim.get_system(&"budget")
	# Rates chosen after the visitor pass shape next month's demand; this
	# month's business is taxed at the rates its visitors responded to.
	check_eq(int(books.save().carry.taxes_occupancy),int(pending.lodging_numerator)*demand_occupancy*12/1000000,"day18 books at the demand occupancy rate")
	check_eq(int(books.save().carry.taxes_gaming),int(pending.gaming_numerator)*demand_gaming*12/1000000,"day18 books at the demand gaming rate")
	run_to(host.sim.clock.day+GameClock.DAYS_PER_MONTH-1)
	var next_pending := tourism.pending_bases()
	check_eq(int(next_pending.get("occupancy_rate",-1)),9,"selected occupancy rate applies to the next visitor month")
	check_eq(int(next_pending.get("gaming_rate",-1)),11,"selected gaming rate applies to the next visitor month")
	var store := Vector2i(-1,-1)
	while host.sim.clock.day < 1500:
		run_to(host.sim.clock.day+1)
		for row in tourism.report():
			if row.code == 126 and row.day_visitors > 0: store = row.anchor
		if store.x >= 0: break
	print("PAID_HOST_STORE day=",host.sim.clock.day," anchor=",store," rows=",tourism.report())
	check(store.x >= 0,"paid commercial zoning naturally grows an attending Despicable's")
	if store.x >= 0:
		retain_host("paid-busy-store-and-resort")
		assert_served(store)
		host.open_query(store)
		check_gt(int(host.query_panel.info.get("Tourists",0)),0,"actual Inspect has store day visitors")
		check_eq(host.query_panel.info.get("Guests",-1),0)
		await capture_host("paid-store-inspect")
		host.query_panel.close()
	host.open_query(RESORT)
	check_eq(host.query_panel.info.get("Tourists",-1),tourism.venue_report(RESORT).tourists)
	host.query_panel.close()
	var population := host.open_window("population") as PopulationWindow
	check(population.headline_text().contains(UIFactory.commafy(host.sim.stats.population)),"actual population window uses residents")
	await capture_host("paid-population-report")
	population.close()
	await Fixture.settle(self,4)
	check_eq(host.status_bar.tourists_label.text,"Tourists: "+UIFactory.commafy(host.sim.stats.tourists),"natural host status updates")
	await capture_host("paid-status-city")
	var funds_before_settlement := host.sim.city.funds
	run_to((host.sim.clock.day / 300 + 1) * 300 - 1)
	var net := 0
	for account in host.sim.stats.ledger:
		net += int(host.sim.stats.ledger[account]) * (-1 if account in BudgetParams.EXPENSE_KEYS else 1)
	host.sim.advance_day()
	check(host.sim.budget_review_pending,"actual January review")
	retain_host("paid-january-review")
	await capture_host("paid-january-review")
	check_eq(host.sim.city.funds,funds_before_settlement+net,"one annual cash settlement")
	check_gt(int(host.sim.stats.last_year_ledger.get(&"taxes_occupancy",0)),0)
	check_gt(int(host.sim.stats.last_year_ledger.get(&"taxes_gaming",0)),0)
	print("PAID_HOST_LEDGER ",JSON.stringify({"initial":STARTING_FUNDS,"paid":paid,"day":host.sim.clock.day,"funds":host.sim.city.funds,"previous":host.sim.stats.last_year_ledger,"tourism":tourism.save()}))

## Catches replacement identity transfer and loss/replay of already earned activity.
func test_same_anchor_replacement_keeps_only_old_earned_income() -> void:
	services()
	run_to(17)
	var t := host.sim.tourism()
	var old := t.venue_report(RESORT)
	var earned := t.pending_bases()
	check_gt(old.guests,0)
	paint(Tools.Kind.BULLDOZE,RESORT)
	paint(Tools.Kind.ARCOLOGY_BODDY,RESORT)
	var fresh := t.venue_report(RESORT)
	check_ne(fresh.instance,old.instance)
	check_eq(fresh.guests,0)
	check_eq(fresh.day_visitors,0)
	check_eq(fresh.lodging_cents,0,"new Inspect cannot claim predecessor activity")
	check_eq(t.pending_bases(),earned,"demolition preserves completed old business")
	var cash := host.sim.city.funds
	host.sim.advance_day()
	var b := host.sim.get_system(&"budget")
	check_eq(int(b.save().carry.taxes_occupancy),int(earned.lodging_cents)*7*12/100)
	check_eq(int(b.save().carry.taxes_gaming),int(earned.gaming_cents)*7*12/100)
	check_eq(host.sim.city.funds,cash,"accrual is not immediate treasury income")
	check(t.pending_bases().is_empty())
	var booked := b.save().duplicate(true)
	run_to(41)
	check_eq(t.venue_report(RESORT).guests,0,"new lot waits for next natural tourism day")
	check_eq(b.save(),booked,"nonbooking days cannot replay income")
	host.sim.advance_day()
	check_gt(t.venue_report(RESORT).guests,0)

const SharedService := preload("res://tests/helpers/shared_apple_cloud.gd")
class JourneyCoordinator extends CloudSaveCoordinator:
	func migrate_personal_saves(_headers: Array[Dictionary]) -> Error:
		# Independent synthetic devices must not migrate this process's other test files.
		return OK
var cloud_service: RefCounted
var cloud_devices: Array[Dictionary] = []
var cloud_now := 1000
var extra_hosts: Array[GameHost] = []

func canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)),"",true)

func economic_state(h: GameHost) -> Dictionary:
	return JSON.parse_string(JSON.stringify({"city":SaveFormat.encode_city(h.sim.city),"simulation":h.sim.snapshot()}))

func cloud_attach(h: GameHost, path: String) -> Dictionary:
	var store := CloudSaveStore.new(path)
	check_eq(store.open_library(""),OK)
	var endpoint = cloud_service.endpoint()
	var coordinator := JourneyCoordinator.new(store,endpoint)
	coordinator.jitter = func(): return 0.0
	h.cloud_saves = CloudSaveSession.new(h,coordinator,store)
	h.cloud_saves.begin_session()
	coordinator.set_enabled(true)
	var device := {"host":h,"store":store,"coordinator":coordinator,"endpoint":endpoint}
	cloud_devices.append(device)
	return device

func cloud_pump() -> void:
	for i in 24:
		cloud_now += 100
		for item in cloud_devices: item.coordinator.advance(cloud_now)
		cloud_service.step()

func restored_host(path: String, name: String) -> GameHost:
	var twin := Fixture.make_host(self,name)
	twin.set_process(false)
	twin.sim.set_process(false)
	check(twin.load_city(path),"actual host loads "+name)
	extra_hosts.append(twin)
	return twin

func close_review(h: GameHost) -> void:
	if h.sim.budget_review_pending:
		check(h.windows.has("budget"),"restored January review is presented")
		(h.windows.budget as BudgetWindow).close()
		check(not h.sim.budget_review_pending,"closing actual review releases calendar")

## Catches day17 double admission, day18 double booking and year-end double settlement
## through local SaveFormat/host and real cloud coordinator with only transport faked.
func test_local_and_cloud_restore_matches_continuous_host() -> void:
	services()
	host.set_process(false)
	var directory := "user://tourism-journeys/"+CloudSaveTypes.uuid()
	cloud_service = SharedService.new(directory.path_join("service"))
	cloud_attach(host,directory.path_join("sender"))
	cloud_pump()
	for day in [16,17,18,299,300]:
		run_to(day)
		var saved := economic_state(host)
		var path := directory.path_join("local-%d.sc2d" % day)
		check_eq(SaveFormat.save(path,host.sim.city,host.sim.snapshot()),OK)
		var local := restored_host(path,"tourism-local-%d"%day)
		check_state(economic_state(local),saved,"local boundary %d exact state"%day)
		check_eq(host.cloud_saves.capture(&"test"),OK)
		cloud_pump()
		var cloud := Fixture.make_host(self,"tourism-cloud-%d"%day)
		cloud.set_process(false)
		cloud.sim.set_process(false)
		extra_hosts.append(cloud)
		var receiver := cloud_attach(cloud,directory.path_join("receiver-%d"%day))
		cloud_pump()
		var downloaded := ""
		for row in receiver.store.slots():
			if row.slot_id == host.cloud_saves.slot_id: downloaded = row.path
		check(not downloaded.is_empty(),"cloud publishes transported tourism city")
		if not downloaded.is_empty(): check(cloud.load_city(downloaded))
		check_state(economic_state(cloud),saved,"cloud boundary %d exact state"%day)
		# Details, pause and a real hall visit are reads of attendance and earned money.
		if day == 17:
			await passive_host_visit()
			check_state(economic_state(host),saved,"pause/Details/Explore cannot alter economic state")
		for h in [host,local,cloud]: close_review(h)
		for step in 1:
			for h in [host,local,cloud]: h.sim.advance_day()
			check_state(economic_state(local),economic_state(host),"continuous/local next day %d"%day)
			check_state(economic_state(cloud),economic_state(host),"continuous/cloud next day %d"%day)
		print("HOST_CONTINUATION ",day," tourists=",host.sim.stats.tourists," funds=",host.sim.city.funds," rng=",host.sim.rng.state())
		cloud_devices.erase(receiver)
		local.free()
		cloud.free()
		extra_hosts.clear()

func passive_host_visit() -> void:
	host.status_bar.set_details_open(true)
	await Fixture.settle(self,2)
	host.status_bar.set_details_open(false)
	host.city_view_3d.set_camera_state(Vector3(40.5,2.4,43.5),0,24)
	await physics_frame
	check(host.enter_explore(),"actual Explore entry")
	if not host.is_exploring(): return
	host.exploration.set_physics_process(false)
	await physics_frame
	var prior_transition := ExploreResortService.transition_seconds
	ExploreResortService.transition_seconds = 0
	var service := host.exploration.resort_service
	var entry := {"anchor":RESORT,"code":262,"key":&"arcology_boddy"}
	check(service.enter(entry),"actual hall entry")
	var world := service.world_for(entry)
	check_gt(world.patrons.states().size(),0,"paid venue attendance supplies rendered representatives")
	check(world.patrons.states().size() <= host.sim.tourism().venue_report(RESORT).tourists)
	host.exploration.pause()
	await Fixture.settle(self,2)
	host.return_to_build()
	ExploreResortService.transition_seconds = prior_transition
	host.sim.set_speed(GameClock.Speed.PAUSED)

func check_state(actual: Dictionary, expected: Dictionary, label: String) -> void:
	var differences: Array[String] = []
	_state_diff(actual,expected,"",differences)
	check(differences.is_empty(),label+": "+str(differences))

func _state_diff(a: Variant, b: Variant, path: String, differences: Array[String]) -> void:
	if differences.size() >= 20: return
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key): differences.append(path+"/"+str(key)+" missing")
			else: _state_diff(a[key],b[key],path+"/"+str(key),differences)
		for key in b:
			if not a.has(key): differences.append(path+"/"+str(key)+" extra")
	elif a != b:
		differences.append(path+" actual="+str(a).left(100)+" expected="+str(b).left(100))

## Generated populated legacy fixture; no player files. Old residents are explicit
## migration input, never used to fake the paid-host attendance journey above.
func test_populated_legacy_host_preserves_cohorts_histories_and_old_books() -> void:
	services(true,true)
	paint(Tools.Kind.ZONE_RES_LOW,Vector2i(40,44),Vector2i(55,46))
	run_to(275)
	# This populated legacy continuation must retain real visitor water headroom
	# after housing/commercial development; pay for two additional connected pumps.
	for x in [36,37]:
		paint(Tools.Kind.WATER_PUMP,Vector2i(x,38))
		paint(Tools.Kind.WATER_PIPE,Vector2i(x,39))
	check_gt(host.sim.stats.population,0,"paid zoning creates real ordinary residents")
	var city := host.sim.city.duplicate_city()
	var snapshot := host.sim.snapshot().duplicate(true)
	snapshot.systems.erase("tourism")
	for field in snapshot.stats.keys():
		if String(field).begins_with("tourist") or field in ["tax_occupancy","tax_gaming"]:
			snapshot.stats.erase(field)
	snapshot.stats.arcology_population = 80
	for account in ["taxes_occupancy","taxes_gaming"]:
		snapshot.stats.ledger.erase(account)
		snapshot.stats.last_year_ledger.erase(account)
		snapshot.systems.budget.carry.erase(account)
		snapshot.stats.history.erase(account)
	for account in ["tourists","tourist_occupancy"]: snapshot.stats.history.erase(account)
	snapshot.systems.budget.erase("tourism_booking")
	snapshot.systems.budget.erase("tourism_booked_month")
	# A pre-tourism snapshot has no completed protection period either.
	snapshot.systems.budget.erase("tourism_program_booking")
	snapshot.systems.budget.erase("tourism_program_carry")
	snapshot.systems.budget.erase("tourism_money_profile")
	snapshot.systems.budget.erase("tourism_residue")
	for at in city.facilities:
		city.facilities[at].erase("tourism_instance")
		city.facilities[at].erase("tourism_migrated")
	city.facilities[RESORT].residents = 80
	city.facilities[RESORT].capacity = 12345
	city.facilities[RESORT].custom_legacy = {"historic_name":"Original paid resort"}
	snapshot.systems.rewards.arcologies["40,40"].residents = 80
	snapshot.systems.rewards.arcologies["40,40"].capacity = 12345
	var cohorts: Array = snapshot.stats.cohorts.duplicate()
	var history: Dictionary = snapshot.stats.history.duplicate(true)
	var ledger: Dictionary = snapshot.stats.ledger.duplicate(true)
	var previous: Dictionary = snapshot.stats.last_year_ledger.duplicate(true)
	var unlocks: Dictionary = snapshot.stats.rewards_offered.duplicate(true)
	var path := "user://tourism-journeys/generated-legacy.sc2d"
	check_eq(SaveFormat.save(path,city,snapshot),OK)
	var twin := restored_host(path,"tourism-migrated")
	check_eq(twin.sim.stats.population,host.sim.stats.population,"legacy guests never enter residents")
	check_eq(twin.sim.stats.tourist_guests,80)
	check_eq(Array(twin.sim.stats.cohorts),cohorts)
	check_eq(canonical(twin.sim.stats.history),canonical(history),"old history bytes retain their values")
	check_eq(canonical(twin.sim.stats.last_year_ledger),canonical(previous))
	for key in ledger: check_eq(int(twin.sim.stats.ledger.get(StringName(key),-1)),int(ledger[key]),"old accrued account retained")
	check_eq(canonical(twin.sim.stats.rewards_offered),canonical(unlocks))
	check_eq(twin.sim.city.facility(RESORT).capacity,12345,"supplied legacy capacity metadata retained")
	check_eq(twin.sim.tourism().venue_report(RESORT).capacity,TourismParams.guest_capacity(&"arcology_boddy"),"authoritative capacity comes from roster")
	check_eq(twin.sim.city.facility(RESORT).custom_legacy,{"historic_name":"Original paid resort"})
	check(twin.sim.tourism().pending_bases().is_empty(),"migration cannot mint retroactive business")
	var migrated := economic_state(twin)
	var current := "user://tourism-journeys/migrated-current.sc2d"
	check_eq(SaveFormat.save(current,twin.sim.city,twin.sim.snapshot()),OK)
	check(twin.load_city(current))
	check_state(economic_state(twin),migrated,"idempotent current host restore after legacy adoption")
	# Replay real calendar from preserved cohorts and historical books.
	twin.sim.advance_days(18)
	print("LEGACY_CALENDAR_SERVICE utility=",twin.sim.tourism().utility_report()," components=",twin.sim.get_system(&"water").admission_budget(twin.sim.city).components)
	check_gt(twin.sim.stats.tourists,0)
	for key in history:
		var values: Array = Array(twin.sim.stats.history[StringName(key)])
		check_eq(values.slice(0,history[key].size()),history[key],"replay only appends historical samples")
	print("HOST_MIGRATION residents=",twin.sim.stats.population," guests=",twin.sim.stats.tourist_guests," prior_history_series=",history.size()," funds=",twin.sim.city.funds)
	retain_copy(path,"generated-legacy.sc2d")
	retain_copy(current,"migrated-current.sc2d")

func retain_copy(source: String, name: String) -> void:
	var directory := OS.get_environment("TOURISM_JOURNEY_EVIDENCE_DIR")
	if directory.is_empty(): return
	check_eq(DirAccess.make_dir_recursive_absolute(directory),OK)
	check_eq(DirAccess.copy_absolute(source,directory.path_join(name)),OK)

func retain_host(name: String) -> void:
	var directory := OS.get_environment("TOURISM_JOURNEY_EVIDENCE_DIR")
	if directory.is_empty(): return
	check_eq(SaveFormat.save(directory.path_join(name+".sc2d"),host.sim.city,host.sim.snapshot()),OK)
	var file := FileAccess.open(directory.path_join(name+".json"),FileAccess.WRITE)
	check(file!=null)
	if file:
		file.store_string(JSON.stringify({"starting_funds":STARTING_FUNDS,"paid":paid,"day":host.sim.clock.day,"funds":host.sim.city.funds,"permanent_population":host.sim.stats.population,"tourism":host.sim.tourism().report()},"  "))
		file.close()

func capture_host(name: String) -> void:
	var directory := OS.get_environment("TOURISM_JOURNEY_CAPTURE_DIR")
	if directory.is_empty(): return
	check_ne(DisplayServer.get_name(),"headless","screenshots require native rendering")
	await Fixture.settle(self,8)
	RenderingServer.force_draw()
	check_eq(DirAccess.make_dir_recursive_absolute(directory),OK)
	check_eq(root.get_texture().get_image().save_png(directory.path_join(name+".png")),OK)
	print("HOST_CAPTURE ",name)

func test_paid_water_cut_preserves_earned_tax_and_recovery_waits_for_arrivals() -> void:
	services()
	run_to(17)
	var tourism := host.sim.tourism()
	var earned := tourism.pending_bases()
	check_gt(host.sim.stats.tourists,0)
	paint(Tools.Kind.BULLDOZE,Vector2i(38,38))
	check_eq(host.sim.stats.tourists,0,"real pump demolition clears current attendance immediately")
	check_eq(tourism.pending_bases(),earned,"real service loss retains earned taxable business")
	check(tourism.venue_report(RESORT).reason.contains("water"))
	paint(Tools.Kind.WATER_PUMP,Vector2i(38,38))
	assert_served(RESORT)
	check_eq(host.sim.stats.tourists,0,"repair cannot admit visitors early")
	host.sim.advance_day()
	check_eq(int(host.sim.get_system(&"budget").save().carry.taxes_gaming),int(earned.gaming_cents)*7*12/100)
	run_to(42)
	check_gt(host.sim.stats.tourists,0,"next natural day17 admits after paid repair")

## Housing is an explicit map fixture, not a claim of natural zone development.
## Residents/cohorts and classes are earned only by scheduled production census,
## immigration and promotion. No assignment to those derived values is used.
func seed_residential_buildings(h: GameHost, count: int) -> void:
	for i in count:
		h.sim.city.stamp_building(10 + (i % 7) * 3, 60 + (i / 7) * 3,
			Buildings.RES_3X3_FIRST, Zones.RES_HIGH)
	h.sim.networks_changed(Rect2i(10,60,21,12))

func advance_hosts_to(hosts: Array, day: int) -> void:
	for h: GameHost in hosts:
		while h.sim.clock.day < day:
			close_review(h)
			h.sim.advance_day()

func test_earned_class_survives_resident_decline_local_and_cloud_without_venues() -> void:
	await earned_class_continuation(false)

func test_earned_class_survives_resident_decline_local_and_cloud_after_migration() -> void:
	await earned_class_continuation(true)

func earned_class_continuation(with_legacy_resort: bool) -> void:
	services(with_legacy_resort)
	host.set_process(false)
	var directory := "user://tourism-journeys/earned-class-"+CloudSaveTypes.uuid()
	if with_legacy_resort:
		# Adopt an explicit old occupant record before earning the class below.
		var legacy := host.sim.snapshot().duplicate(true)
		legacy.systems.erase("tourism")
		legacy.stats.arcology_population = 80
		legacy.systems.rewards.arcologies["40,40"].residents = 80
		host.sim.city.facility(RESORT).erase("tourism_instance")
		host.sim.city.facility(RESORT).erase("tourism_migrated")
		host.sim.city.facility(RESORT).residents = 80
		var legacy_path := directory.path_join("legacy.sc2d")
		check_eq(SaveFormat.save(legacy_path,host.sim.city,legacy),OK)
		check(host.load_city(legacy_path))
		check(host.sim.city.facility(RESORT).tourism_migrated)
		check_eq(host.sim.stats.tourist_guests,80)
	else:
		check(host.sim.tourism().report().is_empty(),"no tourism venues in resident-only history")
	cloud_service = SharedService.new(directory.path_join("service"))
	cloud_attach(host,directory.path_join("sender"))
	cloud_pump()
	var promotions: Array = []
	host.sim.news_published.connect(func(story: Dictionary):
		if story.kind == &"status_upgrade": promotions.append(story.duplicate(true)))
	run_to(13)
	seed_residential_buildings(host,6)
	host.sim.advance_day()
	check_eq(host.sim.stats.population,2160,"scheduled census and immigration create permanent residents")
	check_eq(host.sim.city.status,1,"permanent residents earn the town class")
	check_eq(promotions.size(),1,"the first class was actually promoted")
	run_to(25)
	check(host.sim.stats.rewards_offered.get(&"mayors_residence",false),"scheduled reward is actually earned")
	var rewards := canonical(host.sim.stats.rewards_offered)
	var inventions := canonical(host.sim.stats.inventions)
	for i in 6:
		paint(Tools.Kind.BULLDOZE,Vector2i(10+i*3,60))
	run_to(39)
	check_eq(host.sim.stats.population,0,"scheduled census/migration removes residents after paid demolition")
	check_eq(host.sim.city.status,1,"normal decline retains the earned town class")
	check_eq(promotions.size(),1,"decline cannot promote")
	check_eq(canonical(host.sim.stats.rewards_offered),rewards)
	check_eq(canonical(host.sim.stats.inventions),inventions)
	var saved := economic_state(host)
	var path := directory.path_join("declined-current.sc2d")
	check_eq(SaveFormat.save(path,host.sim.city,host.sim.snapshot()),OK)
	retain_copy(path,"earned-class-%s.sc2d" % ("migrated" if with_legacy_resort else "no-venues"))
	var local := restored_host(path,"earned-class-local")
	check_state(economic_state(local),saved,"local reload preserves earned class after decline")
	check_eq(host.cloud_saves.capture(&"test"),OK)
	cloud_pump()
	var cloud := Fixture.make_host(self,"earned-class-cloud")
	cloud.set_process(false)
	cloud.sim.set_process(false)
	extra_hosts.append(cloud)
	var receiver := cloud_attach(cloud,directory.path_join("receiver"))
	cloud_pump()
	var downloaded := ""
	for row in receiver.store.slots():
		if row.slot_id == host.cloud_saves.slot_id: downloaded = row.path
	check(not downloaded.is_empty(),"cloud transports the declined current-schema city")
	if downloaded.is_empty(): return
	check(cloud.load_city(downloaded))
	check_state(economic_state(cloud),saved,"cloud reload preserves earned class after decline")
	var local_promotions: Array = []
	var cloud_promotions: Array = []
	local.sim.news_published.connect(func(story: Dictionary):
		if story.kind == &"status_upgrade": local_promotions.append(story.duplicate(true)))
	cloud.sim.news_published.connect(func(story: Dictionary):
		if story.kind == &"status_upgrade": cloud_promotions.append(story.duplicate(true)))
	promotions.clear()
	var hosts := [host,local,cloud]
	advance_hosts_to(hosts,63)
	for h: GameHost in hosts: seed_residential_buildings(h,6)
	advance_hosts_to(hosts,64)
	for h: GameHost in hosts:
		check_eq(h.sim.stats.population,2160,"production immigration recovers above the old threshold")
		check_eq(h.sim.city.status,1)
		check_eq(canonical(h.sim.stats.rewards_offered),rewards,"earned gift survives reload and recovery")
	check_eq(promotions,[],"recovery never repeats an earned promotion")
	check_eq(local_promotions,promotions,"local recovery promotion parity")
	check_eq(cloud_promotions,promotions,"cloud recovery promotion parity")
	check_state(economic_state(local),economic_state(host),"local recovered state parity")
	check_state(economic_state(cloud),economic_state(host),"cloud recovered state parity")
	advance_hosts_to(hosts,88)
	for h: GameHost in hosts: seed_residential_buildings(h,28)
	advance_hosts_to(hosts,89)
	for h: GameHost in hosts:
		check_eq(h.sim.stats.population,10080)
		check_eq(h.sim.city.status,2,"new permanent-resident threshold earns the next class")
	check_eq(promotions.size(),1,"exactly one genuinely new promotion")
	check_eq(local_promotions,promotions,"local new promotion event parity")
	check_eq(cloud_promotions,promotions,"cloud new promotion event parity")
	check_state(economic_state(local),economic_state(host),"local new-class state parity")
	check_state(economic_state(cloud),economic_state(host),"cloud new-class state parity")
	print("EARNED_CLASS_CONTINUATION migrated=",with_legacy_resort,
		" earned=2160/class1 declined=0/class1 recovered=2160/class1 new=10080/class2 local/cloud=compared promotions=",promotions)
