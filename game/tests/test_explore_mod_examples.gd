# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/explore_session_case.gd"
func test_actual_example_sources_initialize() -> void:
	for id in ["desert_stroll","desert_delivery","desert_atmosphere","neon_rally","crooner_hunt"]:
		var pack := ExploreModPack.read("res://explore_mods/"+id)
		check(pack.ok,id)
		var runtime := ExploreModRuntime.new()
		runtime.bind([pack],ExploreModProgress.new(),7)
		check(runtime.has_owner(id),id+" starts")
		check(not runtime._commands.is_empty(),id+" exercises host API")
		runtime.stop("test")
func test_public_author_guide_exists() -> void:
	check(FileAccess.file_exists("res://explore_mods/API.md"),"source distribution contains public author guide")

func test_stroll_offers_several_distinct_walkers() -> void:
	var value := flat_city()
	for x in range(18,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	if not _setup(value) or not await _enter(): return
	session.set_physics_process(false)
	var service := ExploreModService.new()
	service.bind(session,[ExploreModPack.read("res://explore_mods/desert_stroll")],ExploreModProgress.new())
	service.enter()
	for i in 3: service.step(.1,false)
	check_eq(service.actors._actors.size(),1,"only the leading walker starts before arrival")
	for i in 900: service.step(.1,false)
	var variants := {}
	for actor: Dictionary in service.actors._actors.values(): variants[actor.record.variant] = true
	check_eq(variants.size(),3,"real sequential routines admit all three distinct variants")
	check_eq(service._progress.get_state("desert_stroll",1).data.get("strolls",0),3)
	service.leave("test")

func test_actual_stroll_walk_wait_greet_and_safe_wave_fallback() -> void:
	var value := flat_city()
	for x in range(18,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	if not _setup(value) or not await _enter(): return
	session.set_physics_process(false)
	var service := ExploreModService.new()
	session.mod_service = service
	service.bind(session,[ExploreModPack.read("res://explore_mods/desert_stroll")],session.mod_progress)
	service.enter()
	for i in 900: service.step(.1,false)
	var variants := {}
	for actor: Dictionary in service.actors._actors.values(): variants[actor.record.variant] = true
	check_eq(variants.size(),3,"actual source admits three distinct walkers; "+str(service.runtime.diagnostics))
	check(session.mod_progress.get_state("desert_stroll",1).data.get("strolls",0) >= 1,"arrival and wait finish")
	check_eq(service.api.interactions._owned.get("desert_stroll",{}).size(),3,"all admitted walkers offer greetings")
	check(service.runtime.has_owner("desert_stroll"),"unavailable wave does not fault routine")
	var frozen := service.actors.visual_states().duplicate(true)
	service.step(10,true)
	check_eq(service.actors.visual_states(),frozen)
	service.runtime.deliver("desert_stroll",{"kind":"interaction","key":"greet1","code":"ok","data":{}})
	for i in 5: service.step(.1,false)
	check(not service.api.interactions._dialogue.is_empty(),"actual greeting uses dialogue")
	service.api.interactions.choose("hello")

func test_examples_idle_when_landmarks_are_absent() -> void:
	if not _setup() or not await _enter(): return
	session.set_physics_process(false)
	for id in ["desert_stroll","desert_delivery"]:
		var service := ExploreModService.new()
		service.bind(session,[ExploreModPack.read("res://explore_mods/"+id)],ExploreModProgress.new())
		service.enter()
		for i in 400: service.step(.1,false)
		check(service.runtime.has_owner(id),id+" remains safely idle")
		check(service.queries.pending_count() == 0)
		check(not service.api.objectives.list_owned(id).is_empty(),id+" explains unavailable route")
		check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
		service.leave("test")
