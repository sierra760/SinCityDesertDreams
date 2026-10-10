# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/explore_session_case.gd"

const Access := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")
const MAIN := preload("res://scenes/main.tscn")
const ANCHOR := Vector2i(20,18)
const KEYS := [&"arcology_fix",&"arcology_alibi",&"arcology_velvet",&"arcology_afterglow",&"arcology_last",&"arcology_dust"]
const NAMES := ["The Fix","Six-Week Alibi","Velvet Wardrobe","The Afterglow","Last Resort","Dust Republic"]
const FLOORS := ["The Back Room","The Fresh Start","The Scarlet Salon","The Observation Lounge","The Last Bank","The Common Ground"]
const ACCENTS := ["c29b53ff","d88798ff","9c2546ff","dc874bff","4fa4a0ff","9c6ecaff"]
const SIGNATURES := [&"vault_circuit", &"alibi_route", &"velvet_encore", &"afterglow_forecast", &"last_bank", &"dust_pool"]
const MINIMUMS := [2200, 400, 1200, 4000, 50, 100]
const MAXIMUMS := [220000, 40000, 120000, 400000, 5000, 10000]
const SAVE := "user://six-resort-integration.sc2d"

func after_all() -> void:
	ExploreResortService.transition_seconds = .3
	CasinoTableOverlay.animation_scale = 1.0

func test_six_venues_play_through_host_and_persist_independent_histories() -> void:
	CasinoTableOverlay.animation_scale = 0.0
	var host: GameHost = MAIN.instantiate()
	host.preferences_path = "user://six-resort-integration.cfg"
	root.add_child(host)
	host.begin_city(flat_city(2000000),{},7,CityStats.new())
	host.sim.set_speed(GameClock.Speed.FAST)
	for i: int in KEYS.size():
		var key: StringName = KEYS[i]
		var minimum: int = MINIMUMS[i]
		check_eq(ResortThemes.building(key),256+i)
		check_eq(ResortThemes.resort_name(key),NAMES[i])
		check_eq(ResortThemes.signature(key),SIGNATURES[i])
		check_eq(ResortThemes.floor_name(key),FLOORS[i])
		check_eq(ResortThemes.theme(key).palette.accent,Color(ACCENTS[i]),"approved venue palette")
		check_eq(host.sim.casino().limits(key,minimum+17),{"minimum":minimum,"maximum":minimum+17},"treasury caps each venue")
		check(host.open_casino_table(key,&"blackjack",CasinoRng.new(3)),"new venue opens through Main")
		if not host.is_casino_open(): continue
		var overlay := host.casino_overlay
		check_eq(host.sim.speed,GameClock.Speed.PAUSED)
		check_eq(overlay.game.limits,{"minimum":minimum,"maximum":MAXIMUMS[i]})
		var funds := host.sim.city.funds
		overlay.game.rig([CasinoDeck.card(10,0),CasinoDeck.card(9,1),CasinoDeck.card(5,2),CasinoDeck.card(8,3)])
		overlay.press_chip(0)
		overlay.perform_action(&"deal")
		check_eq(host.sim.city.funds,funds-minimum,"stake debited")
		overlay.perform_action(&"stand")
		check_eq(overlay.game.state,CasinoGame.SETTLED)
		check_eq(host.sim.city.funds,funds-minimum,"known losing hand settles once")
		check_eq(int(host.sim.casino().ledger(key).rounds),1)
		check_eq(int(host.sim.casino().ledger(key).staked),minimum)
		host.escape()
		check(not host.is_casino_open())
		check_eq(host.sim.speed,GameClock.Speed.FAST)
		check(host.open_casino_table(key,SIGNATURES[i],CasinoRng.new(5)),"signature opens through Main")
		if host.is_casino_open():
			check_eq(host.casino_overlay.game.kind,SIGNATURES[i])
			check(not host.casino_overlay.rules_label.text.is_empty(),"signature explains its rules")
		host.escape()
	check_eq(SaveFormat.save(SAVE,host.sim.city,host.sim.snapshot()),OK)
	var loaded := SaveFormat.load(SAVE)
	check(bool(loaded.get("ok",false)),"save reloads")
	if bool(loaded.get("ok",false)):
		var restored := make_simulation(loaded.city,7)
		restored.restore(loaded.snapshot)
		check_eq(restored.city.funds,host.sim.city.funds)
		for key: StringName in KEYS:
			check_eq(restored.casino().ledger(key),host.sim.casino().ledger(key),"each history survives save")
		restored.free()
	host.free()
	for path: String in [SAVE,"user://six-resort-integration.cfg"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_each_new_resort_enters_from_rotated_front_and_exits_its_pocket() -> void:
	ExploreResortService.transition_seconds = 0.0
	for i: int in KEYS.size():
		var value := flat_city()
		value.stamp_building(ANCHOR.x,ANCHOR.y,256+i)
		value.building.put(24,19,Buildings.ROAD_FIRST)
		value.building.put(24,20,Buildings.ROAD_FIRST)
		if not _setup(value): continue
		if not await _enter(Vector3(24.5,GROUND,20.5)): continue
		var threshold := Access.threshold(city,ANCHOR)
		check((threshold.basis*Vector3.FORWARD).is_equal_approx(Vector3.LEFT),"east frontage rotates entrance")
		check_eq(Access.nearby(city,threshold.origin).get("code",0),256+i)
		session.pedestrian.global_position = threshold.origin+Vector3.UP*.002
		session.pedestrian.stop_input()
		await physics_frame
		check(session.request_interaction(),"door interaction enters "+NAMES[i])
		await physics_frame
		await physics_frame
		var service: ExploreResortService = session.resort_service
		check(service.is_inside(),"inside "+NAMES[i])
		check(service.contains(session.pedestrian.global_position),"entry is contained")
		check(not service.support_for(session.pedestrian.global_position).is_empty(),"pocket supports entry")
		var world := service.world_for({"anchor":ANCHOR,"code":256+i,"key":KEYS[i]})
		check(not bool(world.stats.placeholder),"registered authored hall")
		var requests: Array = []
		var listener := func(resort: StringName, game: StringName, table: Dictionary) -> void: requests.append([resort,game,table])
		session.casino_table_requested.connect(listener)
		for table: Dictionary in world.tables():
			session.pedestrian.clear_support_frame()
			session.pedestrian.global_position = table.seat+Vector3.UP*.002
			session.pedestrian.stop_input()
			await physics_frame
			check(service.contains(session.pedestrian.global_position),"seat remains in pocket")
			check(session.request_interaction(),"each table seat requests game")
		check_eq(requests.size(),world.tables().size(),"every placed table is interactive")
		session.pedestrian.clear_support_frame()
		session.pedestrian.global_position = world.mat_transform().origin+Vector3.UP*.002
		session.pedestrian.stop_input()
		await physics_frame
		check(session.request_interaction(),"mat interaction exits")
		await physics_frame
		await physics_frame
		check(not service.is_inside(),"outside "+NAMES[i])
		check(session._valid_actor(session.pedestrian,true),"exit is physically supported with full capsule clearance")
		check_lt(session.pedestrian.global_position.distance_to(threshold.origin),.35,"exit returns to rotated threshold")
		check_gt((session.pedestrian.global_basis*Vector3.FORWARD).x,.9,"exit faces east street")
		await after_each()
