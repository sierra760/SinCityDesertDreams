# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const MAIN := preload("res://scenes/main.tscn")
var host: GameHost
func before_each() -> void:
	host = MAIN.instantiate()
	host.preferences_path = "user://f8-boundary.cfg"
	root.add_child(host)
func after_each() -> void:
	host.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://f8-boundary.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CityFileFlow.autosave_path()))
	await process_frame
func _begin(enabled: bool) -> bool:
	var city := flat_city()
	for x in range(18,34): city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	host.begin_city(city,{},173,null)
	host.sim.set_process(false)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	if enabled:
		for id in ["desert_stroll","desert_atmosphere"]:
			host.exploration.mod_packs.append(ExploreModPack.read("res://explore_mods/"+id))
	host.city_view_3d.set_camera_state(Vector3(22.5,4*CityGeometry3D.HEIGHT,20.5),1,12.0)
	await physics_frame
	var entered := host.explore_switch.enter()
	check(entered,"actual Main supported entry")
	host.exploration.set_physics_process(false)
	return entered
func _state() -> Dictionary:
	return {"city":SaveFormat.encode_city(host.sim.city).duplicate(true),"simulation":host.sim.snapshot().duplicate(true)}
func _events() -> void:
	var service := host.exploration.mod_service
	if service == null: return
	for i in 10: service.step(.1,false)
	service.runtime.deliver("desert_stroll",{"kind":"interaction","key":"greet1","code":"ok","data":{}})
	for i in 3: service.step(.1,false)
	if not service.api.interactions._dialogue.is_empty(): service.api.interactions.choose("hello")
	service.api.environment.step(.1,true)
	service.api.environment.step(.1,false)
func test_running_city_continuation_with_mods_matches_control() -> void:
	var control: Array[Dictionary] = []
	for enabled in [false,true]:
		if not await _begin(enabled): return
		host.sim.set_speed(GameClock.Speed.SLOW)
		for day in 32:
			# Identical player edit and explicit day stepping isolate simulation from wall time.
			if day == 3:
				host.sim.city.building.put(34,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
				host.sim.networks_changed(Rect2i(34,20,1,1))
			_events()
			host.sim.advance_day()
			if enabled: check_eq(_state(),control[day],"all city layers/metadata/stats/systems/RNG on day %d" % day)
			else: control.append(_state())
		if enabled:
			check(host.exploration.mod_service.runtime.has_owner("desert_stroll"))
			check(host.exploration.mod_service.runtime.has_owner("desert_atmosphere"))
			check(host.exploration.mod_progress.get_state("desert_stroll",1).data.get("strolls",0) >= 1)
		host.explore_switch.leave()
func test_paused_city_interactions_environment_save_teardown_reentry() -> void:
	if not await _begin(true): return
	var before := _state()
	for cycle in 3:
		for i in 25: _events()
		check_eq(_state(),before,"paused state invariant")
		var service := host.exploration.mod_service
		check(service.runtime.has_owner("desert_stroll"))
		check(service.runtime.has_owner("desert_atmosphere"))
		check_eq(host.autosave(),OK)
		var saved := SaveFormat.load(CityFileFlow.autosave_path())
		check(saved.ok)
		check_eq(SaveFormat.encode_city(saved.city),before.city)
		check_eq(saved.snapshot,JSON.parse_string(JSON.stringify(before.simulation)))
		host.explore_switch.leave()
		check(service.runtime._sessions.is_empty())
		check(service.actors._actors.is_empty())
		check(service.api._timers.is_empty())
		check_eq(_state(),before,"teardown leaves simulation exact")
		check(host.explore_switch.enter())
		host.exploration.set_physics_process(false)
func test_sixty_four_air_records_have_bounded_allocation_and_pose_work() -> void:
	if not await _begin(false): return
	var service := host.exploration.mod_service
	# Bind the real service to the actual Main controller for host-only allocation checks.
	if service == null:
		service = ExploreModService.new()
		host.exploration.mod_service = service
		service.bind(host.exploration,[],host.exploration.mod_progress)
		service.enter()
	var before := _state()
	var memory_before := OS.get_static_memory_usage()
	for i in 64:
		var position := ExploreWorldQueries.copied_point(Vector3(18+(i%8)*2,4*CityGeometry3D.HEIGHT+2,18+(i/8)*2),0)
		var result := service.api.apply({"owner":"air%d"%(i/8),"generation":service.generation,"request_id":i+1,"kind":"actor.spawn","args":{"kind":"helicopter","options":{"key":str(i),"position":position}}})
		check_eq(result.code,"ok","air record %d"%i)
	check_eq(service.actors.visual_states().size(),64)
	var capped := service.api.apply({"owner":"ninth","generation":service.generation,"request_id":70,"kind":"actor.spawn","args":{"kind":"plane","options":{"key":"extra","position":ExploreWorldQueries.copied_point(Vector3(50,4*CityGeometry3D.HEIGHT+2,50),0)}}})
	check_eq(capped.code,"quota_exceeded")
	var allocated := OS.get_static_memory_usage()
	var durations: Array[int] = []
	for i in 600:
		var begun := Time.get_ticks_usec()
		service.step(.1,false)
		var poses := service.actors.visual_states()
		check_eq(poses.size(),64)
		for record: Dictionary in service.actors._actors.values(): host.city_view_3d.traffic.actor_pose(record.record)
		durations.append(Time.get_ticks_usec()-begun)
	durations.sort()
	print("AIR64_PROFILE "+JSON.stringify({"count":600,"p50_usec":durations[299],"p99_usec":durations[593],"max_usec":durations.back(),"allocation_bytes":allocated-memory_before,"scan_memory_delta":OS.get_static_memory_usage()-allocated,"records":service.actors._actors.size(),"external_cap":CityTraffic3D.MAX_EXTERNAL}))
	# Exercise the real per-flight swept shape and bounded separation scans,
	# including allocation churn, independently of the held-record fast path.
	var swept: Array[int] = []
	var swept_before := OS.get_static_memory_usage()
	for sample in 30:
		var begun := Time.get_ticks_usec()
		for actor: Dictionary in service.actors._actors.values():
			var record: Dictionary = actor.record
			var at: Vector3 = record.air_position
			check(ExploreAirWaypoints.clear_segment(host.exploration.traversal,record.kind,at,at+Vector3(.01,0,0)))
			check(ExploreAirWaypoints.separated(host.city_view_3d.traffic,record.kind,record.id,at,at+Vector3(.01,0,0)))
		swept.append(Time.get_ticks_usec()-begun)
	swept.sort()
	print("AIR64_SWEPT_PROFILE "+JSON.stringify({"count":30,"records":64,"p50_usec":swept[14],"p99_usec":swept[28],"max_usec":swept.back(),"memory_delta":OS.get_static_memory_usage()-swept_before,"shape_calls_per_sample":64,"separation_pose_scan_cap":64}))
	check_eq(_state(),before)
	host.explore_switch.leave()
	check(service.actors._actors.is_empty())
	check(service.runtime._sessions.is_empty())

class CountingTraffic extends CityTraffic3D:
	var owned_steps := 0
	var filtered_scans := 0
	func _step_clock(delta: float, owned: bool) -> void:
		if owned: owned_steps += 1
		super._step_clock(delta,owned)
	func visual_states(owner_filter: int = -1) -> Array[Dictionary]:
		if owner_filter == 1: filtered_scans += 1
		return super.visual_states(owner_filter)
func test_no_owned_traffic_skips_simulation_but_retains_cleanup() -> void:
	var traffic := CountingTraffic.new()
	root.add_child(traffic)
	var city := flat_city()
	for x in range(18,34): city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	traffic.bind_city(city)
	traffic.set_detail_enabled(true)
	traffic._render_paused = true
	var camera := Camera3D.new()
	traffic.add_child(camera)
	for cycle in 4:
		var actor := traffic.owned_spawn("cleanup",&"pedestrian",Vector2i(22,20),0)
		check(not actor.is_empty(),"real owned record spawned")
		if actor.is_empty(): break
		camera.position = traffic.actor_pose(actor).origin+Vector3(0,.02,1)
		traffic.advance_owned(1.0/60.0)
		traffic._render(camera)
		check_eq(traffic.detail_manager.debug_state().detailed_count,1,"normal draw promotes owner")
		# Same-count replacement must invalidate full membership, not just size.
		var old_id: int = actor.id
		traffic.owned_remove(old_id)
		actor = traffic.owned_spawn("replacement",&"pedestrian",Vector2i(22,20),0)
		traffic._render(camera)
		check(not traffic.detail_manager.debug_state().ids.has("ambient:"+str(old_id)))
		check(traffic.detail_manager.debug_state().ids.has("ambient:"+str(actor.id)))
		traffic._claims[actor.id] = {}
		traffic._render(camera)
		check_eq(traffic.detail_manager.debug_state().detailed_count,0,"claim removes detail on first draw")
		traffic._claims.clear()
		traffic._render(camera)
		check_eq(traffic.detail_manager.debug_state().detailed_count,1)
		traffic.graph.revision += 1
		traffic._render(camera)
		check_eq(traffic._paused_render_state,traffic._render_state(camera),"revision refreshes cache")
		camera.rotation.y = PI
		traffic._render(camera)
		check_eq(traffic.detail_manager.debug_state().detailed_count,0,"camera change releases detail")
		camera.rotation.y = 0
		traffic._render(camera)
		traffic.owned_remove(actor.id)
		traffic.advance_owned(1.0/60.0)
		traffic._render(camera)
		check_eq(traffic.detail_manager.debug_state().detailed_count,0,"last removal released on first normal draw")
		for batch: MultiMeshInstance3D in traffic._batches.values():
			check_eq(batch.multimesh.visible_instance_count,0,"last removal clears batch on first draw")
		check(traffic._detail_clocks.is_empty(),"repeated removals prune all stale clocks")
		# An unchanged empty paused draw can reuse its completed cache.
		traffic._render(camera)
		var hits := int(traffic.statistics.get("render_cache_hits",0))
		var scans := traffic.filtered_scans
		var steps := traffic.owned_steps
		traffic.advance_owned(1.0/60.0)
		traffic._render(camera)
		check_eq(traffic.owned_steps,steps,"no ambient occupancy rebuild")
		check_eq(traffic.filtered_scans,scans,"no redundant owned visual scan")
		check_eq(int(traffic.statistics.get("render_cache_hits",0)),hits+1,"unchanged paused draw reuses cache")
	traffic.set_detail_enabled(false)
	traffic.free()
