# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
## Attendance controls real hall models without creating visitors or business.
extends "res://tests/exploration/explore_session_case.gd"

const A := Vector2i(20,18)
const B := Vector2i(24,18)
const STORE := &"com_corner_store"
const MAIN := preload("res://scenes/main.tscn")
var sim: Simulation
var hall: ResortInteriorWorld3D
var host: GameHost

func after_each() -> void:
	if is_instance_valid(hall): hall.free()
	if is_instance_valid(host): host.free()
	if is_instance_valid(sim): sim.free()
	hall = null
	host = null
	sim = null
	ExploreResortService.transition_seconds = .3
	var prefs := "user://tourism-patrons-host.cfg"
	if FileAccess.file_exists(prefs): DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs))
	await super.after_each()

func _attendance_api() -> bool:
	var probe := ResortInteriorWorld3D.new()
	var available := probe.has_method("set_attendance")
	probe.free()
	check(available,"halls accept authoritative attendance")
	return available

func _set_counts(authority: Simulation, counts: Dictionary) -> void:
	var tourism := authority.tourism()
	var state: TourismState = tourism.get("_state")
	var rows := state.records()
	for row in rows:
		if counts.has(row.anchor):
			row.guests = 0
			row.day_visitors = int(counts[row.anchor])
	TourismFixture.segment_rows(rows)
	check_eq(state.replace_records(rows),OK,"explicit fixture attendance validates")
	tourism.reconcile_now()

func _start_with_authority() -> bool:
	ExploreResortService.transition_seconds = 0.0
	var value := flat_city()
	value.stamp_building(A.x,A.y,126)
	value.stamp_building(B.x,B.y,126)
	for x in range(19,27): value.building.put(x,19,30)
	if not _setup(value): return false
	sim = Simulation.new()
	sim.setup(city,7)
	for anchor: Vector2i in [A,B]: TourismFixture.set_served(city,anchor,true,true)
	sim.tourism().reconcile_now()
	# Bind a fresh controller once, as Main does, with tourism authority.
	session.free()
	session = load(SESSION_PATH).new()
	root.add_child(session)
	session.bind(view,hud,sim)
	session.input_blocked = func() -> bool: return false
	return await _enter(Vector3(20.5,GROUND,19.5))

func _world(anchor: Vector2i = A) -> ResortInteriorWorld3D:
	return session.resort_service.world_for({"anchor":anchor,"code":126,"key":STORE})

func test_empty_venues_have_no_patrons() -> void:
	hall = ResortInteriorWorld3D.new()
	root.add_child(hall)
	hall.build(STORE,126,A)
	check_eq(hall.patrons.get_child_count(),0,"no tourism authority starts with zero models")
	if not _attendance_api(): return
	if not await _start_with_authority(): return
	check_eq(_world().patrons.states().size(),0,"empty authoritative venue stays empty")
	# Optional legacy/standalone binding must not invent a full crowd.
	var standalone := ExploreResortService.new()
	root.add_child(standalone)
	standalone.bind(view,session.traversal,session.pedestrian,hud)
	check_eq(standalone.world_for({"anchor":A,"code":126,"key":STORE}).patrons.states().size(),0)
	standalone.free()

func test_visuals_never_exceed_attendance_or_hall_budget() -> void:
	if not _attendance_api(): return
	for sample: Array in [[STORE,126,3],[&"arcology_boddy",262,6],[&"arcology_woolier",263,6],
		[&"arcology_stockgrowers",264,8],[&"arcology_fremont",265,8],[&"arcology_comstock",251,16]]:
		hall = ResortInteriorWorld3D.new()
		root.add_child(hall)
		hall.build(sample[0],sample[1],A)
		for count: int in [0,1,3,24,-5]:
			hall.call("set_attendance",count)
			var expected := mini(maxi(0,count),int(sample[2]))
			check_eq(hall.patrons.states().size(),expected,"current attendance capped by existing hall budget")
			check_eq(hall.patrons.get_child_count(),expected,"removed models free immediately")
			check_eq(hall.stats.patrons,expected)
		hall.free()
		hall = null

func test_cached_hall_updates_while_occupied_and_hidden() -> void:
	if not _attendance_api(): return
	if not await _start_with_authority(): return
	_set_counts(sim,{A:3,B:1})
	var first := _world()
	var hidden := _world(B)
	check(session.resort_service.enter({"anchor":A,"code":126,"key":STORE}))
	var survivors: Array = first.patrons.states().slice(0,1)
	var model: Node = first.patrons.get_child(0)
	var other_model: Node = hidden.patrons.get_child(0)
	var total := sim.stats.tourists
	# Equal city total; aggregate tourists_changed alone cannot refresh these.
	_set_counts(sim,{A:1,B:3})
	check_eq(sim.stats.tourists,total)
	check_eq(first.patrons.states(),survivors,"surviving position, clock and game are retained")
	check_eq(first.patrons.get_child(0),model,"surviving skeleton is retained")
	check_eq(hidden.patrons.states().size(),3,"hidden cached hall updates immediately")
	check_eq(hidden.patrons.get_child(0),other_model)
	check(not hidden.visible)
	var frozen: Array = hidden.patrons.states()
	var funds := city.funds
	var saved := sim.snapshot()
	var rng := sim.rng.state()
	seed(9812)
	var expected_random := randi()
	seed(9812)
	for tick in 10:
		session.resort_service.step(.1)
		_world(B)
	check_eq(hidden.patrons.states(),frozen,"hidden clocks stay frozen")
	check_eq(sim.snapshot(),saved,"hall reads never admit or book business")
	check_eq(city.funds,funds)
	check_eq(sim.rng.state(),rng)
	check_eq(randi(),expected_random)
	_set_counts(sim,{A:24})
	check_eq(first.patrons.states().size(),3,"removed destinations are available again")
	var targets := {}
	for person: Dictionary in first.patrons.get("_people"):
		check(not targets.has(person.target),"resized crowd owns unique destinations")
		targets[person.target] = true

func test_pause_table_play_demolition_and_city_replacement_release_safely() -> void:
	if not _attendance_api(): return
	# Actual Main wiring, actual table suspension and actual city replacement.
	host = MAIN.instantiate()
	host.preferences_path = "user://tourism-patrons-host.cfg"
	root.add_child(host)
	var value := flat_city(200000)
	value.stamp_building(A.x,A.y,126)
	for x in range(20,25): value.building.put(x,19,30)
	host.begin_city(value,{},7,CityStats.new())
	host.sim.set_speed(GameClock.Speed.PAUSED)
	TourismFixture.set_served(value,A,true,true)
	host.sim.tourism().reconcile_now()
	_set_counts(host.sim,{A:3})
	host.city_view_3d.set_camera_state(Vector3(20.5,2.4,19.5),0,48)
	await physics_frame
	check(host.enter_explore())
	if not host.is_exploring(): return
	await physics_frame
	ExploreResortService.transition_seconds = 0
	var service := host.exploration.resort_service
	var world := service.world_for({"anchor":A,"code":126,"key":STORE})
	check_eq(world.patrons.states().size(),3,"Main supplies actual tourism authority")
	check(service.enter({"anchor":A,"code":126,"key":STORE}))
	host.exploration.pause()
	var frozen: Array = world.patrons.states()
	for frame in 4: await physics_frame
	check_eq(world.patrons.states(),frozen,"manual pause freezes visitors")
	host.exploration.resume()
	check(host.open_casino_table(STORE,&"slots",CasinoRng.new(2)))
	check(host.exploration.is_suspended())
	frozen = world.patrons.states()
	for frame in 4: await physics_frame
	check_eq(world.patrons.states(),frozen,"table play freezes visitors")
	_set_counts(host.sim,{A:1})
	check_eq(world.patrons.states().size(),1,"attendance can update while table clocks freeze")
	var old_tourism := host.sim.tourism()
	host.begin_city(flat_city(30000),{},9,CityStats.new())
	check(not is_instance_valid(world),"reload while seated frees old skeletons and hall")
	check(not is_instance_valid(service),"old service freed")
	check_eq(old_tourism.attendance_changed.get_connections().size(),0,"old tourism retains no presentation")
	check(not host.is_casino_open())
	host.free()
	host = null
	if not await _start_with_authority(): return
	_set_counts(sim,{A:3})
	service = session.resort_service
	world = _world()
	ExploreResortService.transition_seconds = .3
	check(service.enter({"anchor":A,"code":126,"key":STORE}))
	check(service.is_transitioning())
	city.clear_footprint(A.x,A.y)
	sim.tourism().reconcile_now()
	service.refresh_geometry()
	check(not is_instance_valid(world),"demolition during fade frees hall")
	check(not service.is_transitioning(),"door fade cancelled")
	for frame in 4: await physics_frame
	check(not service.is_inside(),"cancelled fade cannot resurrect hall")
	var tourism := sim.tourism()
	session.leave()
	check_eq(tourism.attendance_changed.get_connections().size(),0,"Explore end disconnects attendance")

func test_hidden_hall_demolition_does_not_cancel_another_door_fade() -> void:
	if not _attendance_api(): return
	if not await _start_with_authority(): return
	_set_counts(sim,{A:3,B:3})
	var service: ExploreResortService = session.resort_service
	var hidden := _world(B)
	ExploreResortService.transition_seconds = .3
	check(service.enter({"anchor":A,"code":126,"key":STORE}))
	check(service.is_transitioning())
	city.clear_footprint(B.x,B.y)
	sim.tourism().reconcile_now()
	check(not is_instance_valid(hidden))
	check(service.is_transitioning(),"unrelated hidden demolition keeps the active fade")
	await create_timer(.6).timeout
	check(service.is_inside(),"unaffected door transition still reaches its hall")

func test_same_code_rebuild_and_authority_rebind_do_not_retain_old_visitors() -> void:
	if not _attendance_api(): return
	if not await _start_with_authority(): return
	_set_counts(sim,{A:3,B:1})
	var service: ExploreResortService = session.resort_service
	var old := _world()
	var hidden := _world(B)
	var unrelated_model := hidden.patrons.get_child(0)
	check(service.enter({"anchor":A,"code":126,"key":STORE}))
	city.clear_footprint(A.x,A.y)
	city.stamp_building(A.x,A.y,126)
	TourismFixture.set_served(city,A,true,true)
	sim.tourism().reconcile_now()
	check(not is_instance_valid(old),"same-code rebuild discards the occupied old lot")
	check(not service.is_inside())
	check_eq(_world().patrons.states().size(),0,"replacement starts empty")
	check_eq(hidden.patrons.get_child(0),unrelated_model,"other anchor retains its skeleton")
	_set_counts(sim,{A:3})
	service.bind(view,session.traversal,session.pedestrian,hud)
	check_eq(sim.tourism().attendance_changed.get_connections().size(),0)
	check_eq(_world().patrons.states().size(),0,"rebinding without authority empties cached hall")
	service.bind(view,session.traversal,session.pedestrian,hud,sim)
	check_eq(_world().patrons.states().size(),3,"rebinding reads existing counts without admissions")
	var old_tourism := sim.tourism()
	var replacement := flat_city()
	replacement.stamp_building(A.x,A.y,126)
	sim.setup(replacement,9)
	view.bind_city(replacement)
	service.bind(view,session.traversal,session.pedestrian,hud,sim)
	check_eq(old_tourism.attendance_changed.get_connections().size(),0)
	check(not is_instance_valid(hidden),"new city releases all cached halls")
	check_eq(_world().patrons.states().size(),0,"same anchor in new city has no prior visitors")
