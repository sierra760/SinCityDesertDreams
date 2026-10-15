# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"

const KEYS := [&"arcology_boddy", &"arcology_woolier", &"arcology_stockgrowers", &"arcology_fremont"]
const COSTS := [8000,16000,30000,45000]
const MINIMUMS := [10,15,25,40]
const CAPACITIES := [80,160,300,450]
const SIGNATURES := [&"faro",&"chuck_a_luck",&"faro",&"baccarat"]
const Access := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")

func test_append_only_building_roster_and_early_tool_availability() -> void:
	var stats := CityStats.new()
	for i: int in KEYS.size():
		var code := Buildings.id_of(KEYS[i])
		check_eq(code,262+i,"new stable native id")
		if code < 0: continue
		var size := 2 if i<2 else 3
		check_eq(Buildings.size(code),Vector2i(size,size))
		check_eq(Buildings.cost(code),COSTS[i])
		check(Buildings.is_arcology(code))
		var found := false
		for kind: int in Tools.Kind.values():
			if Tools.building_id(kind)!=code: continue
			found = true
			check(Tools.is_available(kind,City.new(),stats),"founding-year availability without inventions")
			check_eq(Tools.footprint(kind),Vector2i(size,size))
		check(found,"tool exists")
		check_eq(int(RewardParams.ARCOLOGIES.get(KEYS[i],{}).get("capacity",0)),CAPACITIES[i])
	check_eq(Buildings.ARCOLOGY_DUST,261,"existing ids retain their codes")

func test_themed_games_limits_and_variable_footprint_thresholds() -> void:
	var city := City.new()
	for i: int in KEYS.size():
		var code := 262+i
		var key: StringName = KEYS[i]
		check_eq(ResortThemes.building(key),code)
		check_eq(ResortThemes.signature(key),SIGNATURES[i])
		check_eq(CasinoParams.TABLE_LIMITS.get(key,{}),{"minimum":MINIMUMS[i],"maximum":MINIMUMS[i]*100})
		if Buildings.id_of(key)<0: continue
		var anchor := Vector2i(20,20)
		city.stamp_building(anchor.x,anchor.y,code)
		var size := Buildings.size(code).x
		city.building.put(anchor.x+size,anchor.y,Buildings.ROAD_FIRST)
		var pose := Access.threshold(city,anchor,code)
		check((pose.basis*Vector3.FORWARD).is_equal_approx(Vector3.LEFT),"small resort turns to east street")
		check_eq(Vector2(pose.origin.x,pose.origin.z),Vector2(anchor)+Vector2(size-.18,size*.5),"threshold follows footprint")
		check_eq(Access.nearby(city,pose.origin).get("code",0),code)

func test_compact_hall_has_every_game_and_clear_seats() -> void:
	for i: int in KEYS.size():
		var key: StringName = KEYS[i]
		var plan := ResortInteriorLayouts.layout(key)
		check(not plan.is_empty(),"new compact layout")
		if plan.is_empty(): continue
		check_eq(plan.bounds.size.x*16.0,24.0 if i<2 else 36.0)
		var games := {}
		for table: Dictionary in plan.tables:
			games[table.game] = true
			check(plan.bounds.has_point(table.seat),"seat remains within compact hall")
			check(plan.bounds.has_point(table.camera.origin),"camera remains within compact hall")
			for obstacle: Dictionary in plan.obstacles:
				var half: Vector2 = obstacle.half
				var rect := Rect2(Vector2(obstacle.center)-half,half*2.0).grow(.018)
				check(not rect.has_point(Vector2(table.seat.x,table.seat.z)),"seat clears "+String(obstacle.name))
		for game: StringName in [&"blackjack",&"roulette",&"slots",&"money_wheel",&"video_poker",SIGNATURES[i]]:
			check(games.has(game),"every requested game is physically present")

func test_founding_construction_demolition_and_save_v2_round_trip() -> void:
	var city := flat_city(100000)
	city.founded_year = 1900
	var stats := CityStats.new()
	var builder := Builder.new(city,stats)
	for i: int in KEYS.size():
		var anchor := Vector2i(12+i*5,12)
		var tool := Tools.Kind.ARCOLOGY_BODDY+i
		var before := city.funds
		var built := builder.apply(tool,anchor)
		check(built.ok,"affordable resort builds at city founding")
		check_eq(city.funds,before-COSTS[i],"one construction charge per whole lot")
		var size := Buildings.size(262+i)
		check_eq(city.building.atv(anchor+size-Vector2i.ONE),262+i,"whole footprint uses 16-bit id")
		check_eq(city.anchor_of(anchor.x+size.x-1,anchor.y+size.y-1),anchor)
		check(UtilityParams.draws_power(262+i))
		check(UtilityParams.draws_water(262+i))
	var sim := make_simulation(city,71)
	for i: int in KEYS.size():
		check(sim.get_system(&"rewards").arcology_available(KEYS[i]),"reward pathway agrees with early tools")
		check_eq(int(sim.tourism().venue_report(Vector2i(12+i*5,12)).capacity),CAPACITIES[i])
	var path := "user://neighborhood-resorts-v2.sc2d"
	check_eq(SaveFormat.save(path,city,sim.snapshot()),OK)
	var loaded := SaveFormat.load(path)
	check(bool(loaded.ok),"new IDs save and reload")
	if loaded.ok:
		check_eq(loaded.city.building.data,city.building.data)
		check_eq(loaded.city.facilities,city.facilities)
		check_eq(loaded.city.funds,city.funds)
	for i: int in KEYS.size():
		var size := Buildings.size(262+i)
		var result := builder.apply(Tools.Kind.BULLDOZE,Vector2i(12+i*5,12)+size-Vector2i.ONE)
		check(result.ok,"demolition from far corner resolves anchor")
		check_eq(city.building.count(262+i),0)
	sim.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_invention_schedule_retains_its_rng_and_original_keys() -> void:
	var city := flat_city(100000)
	city.founded_year = 1900
	var ctx := make_context(city,71)
	var economy := EconomySystem.new()
	economy.setup(ctx)
	var expected := SimRng.new(71)
	check_eq(ctx.stats.inventions.size(),EconomyParams.TECHNOLOGIES.size(),"neighborhood keys do not create inventions")
	for tech: StringName in EconomyParams.TECHNOLOGIES:
		var year := int(EconomyParams.TECHNOLOGIES[tech])+expected.below(EconomyParams.INVENTION_SPREAD)
		check_eq(int(ctx.stats.inventions[tech]),year,"original invention schedule retained")
	check_eq(ctx.rng.state(),expected.state(),"only the original invention draws are consumed")
	var rewards := preload("res://scripts/sim/reward_system.gd").new()
	rewards.setup(ctx)
	for key: StringName in KEYS:
		check(not ctx.stats.inventions.has(key))
		check_eq(Tools.invention_key(Tools.Kind.ARCOLOGY_BODDY+KEYS.find(key)),&"")
		check(rewards.arcology_available(key),"neighborhood design is available from founding")
	check_eq(ctx.rng.state(),expected.state(),"early resort availability consumes no RNG")


func test_machine_screens_seats_and_cameras_face_the_central_aisles() -> void:
	var checked := 0
	for key: StringName in KEYS:
		var plan := ResortInteriorLayouts.layout(key)
		for table: Dictionary in plan.tables:
			if table.game not in [&"slots",&"video_poker"]: continue
			# Both authored machine props and their reel art face local +Z.
			var front: Vector3 = table.pose.basis*Vector3.BACK
			var inward := Vector3(-signf(table.pose.origin.x),0,0)
			check_gt(front.dot(inward),.99,"%s %s screens face into the room"%[key,table.game])
			var screen: Vector3 = table.pose*Vector3(0,1.29/16.0,.204/16.0)
			check_lt(absf(screen.x),absf(table.pose.origin.x),"screen face is on the aisle side of its cabinet")
			check_gt((table.seat-table.pose.origin).dot(inward),.05,"player approaches from the interior aisle")
			check_gt((table.camera.origin-table.pose.origin).dot(inward),.08,"table camera views the front from inside the room")
			checked+=1
	check_eq(checked,12,"two slot banks and one video-poker bank per venue")


func test_limits_rise_with_cost_from_despicables_floor() -> void:
	var store := CasinoParams.table_limits(ResortThemes.STORE_KEY)
	check_eq(store,{"minimum":1,"maximum":1000},"Despicable's retains its accessible limits")
	var ranked := ResortThemes.keys()
	ranked.sort_custom(func(a: StringName,b: StringName) -> bool:return Buildings.cost(ResortThemes.building(a))<Buildings.cost(ResortThemes.building(b)))
	var previous: Dictionary = store
	var casino := CasinoSystem.new()
	for key: StringName in ranked:
		var limits := CasinoParams.table_limits(key)
		check_ge(int(limits.minimum),int(previous.minimum),"minimum increases with price: "+String(key))
		check_ge(int(limits.maximum),int(previous.maximum),"maximum increases with price: "+String(key))
		check_eq(int(limits.maximum),int(limits.minimum)*100,"resorts retain the 100x spread")
		check_eq(casino.limits(key,2000000),limits,"full treasury exposes the advertised limits")
		check_eq(int(casino.limits(key,37).maximum),mini(37,int(limits.maximum)),"treasury still caps the maximum")
		check(not bool(casino.can_play(key,int(limits.minimum)-1).ok),"below-minimum treasury is refused")
		check(bool(casino.can_play(key,int(limits.minimum)).ok),"exact minimum is playable")
		previous=limits
