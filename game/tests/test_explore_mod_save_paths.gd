# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const MAIN := preload("res://scenes/main.tscn")
var host: GameHost
var paths: Array[String] = []
func before_each() -> void:
	host = MAIN.instantiate()
	host.preferences_path = "user://f6-test.cfg"
	root.add_child(host)
	host.begin_city(flat_city(),{},173,null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
func after_each() -> void:
	host.free()
	for path in paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	paths.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://f6-test.cfg"))
	await process_frame
func test_all_save_paths_capture_committed_progress() -> void:
	var progress := host.exploration.mod_progress
	check(progress.commit("missing_pack",1,"1.0",{"accepted":true}).ok)
	var expected := progress.snapshot()
	var pack := ExploreModPack._snapshot({"manifest.json":'{"id":"pending","name":"Pending","version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"}'.to_utf8_buffer(),"main.lua":'return {on_start=function(api) api.state.set("unaccepted",true); api.objective.set("pending","Pending","active") end,on_tick=function(api) api.log("tick") end}'.to_utf8_buffer()})
	var runtime := ExploreModRuntime.new()
	runtime.bind([pack],progress,37)
	check_eq(runtime.metrics().pending_transactions,1,"real Lua creates unaccepted transaction")
	var metrics := runtime.metrics()
	var pending := runtime._transactions.duplicate(true)
	var city_before := SaveFormat.encode_city(host.sim.city)
	var sim_before := host.sim.snapshot().duplicate(true)
	var control := "user://f6-control.sc2d"
	check_eq(SaveFormat.save(control,host.sim.city,sim_before),OK)
	var control_doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(control))
	# Independently written saves may cross a wall-clock second.
	control_doc.header.erase("saved_at")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(control))
	var manual := host.files.save_city_as("f6-manual")
	check_eq(SaveFormat.load(manual).explore_mods,expected,"Save As captures progress before later Save")
	paths.append(manual)
	check_eq(host.files.save_city(),OK)
	check_eq(host.autosave(),OK)
	paths.append(CityFileFlow.autosave_path())
	var shared := host.files.prepare_city_share()
	check(shared.ok)
	if shared.ok: paths.append(shared.path)
	var recovery := CityFileFlow.application_recovery_path()
	check_eq(host.suspend_for_background(recovery),OK)
	paths.append(recovery)
	for path in paths:
		var loaded := SaveFormat.load(path)
		check(loaded.ok,path)
		check_eq(loaded.get("explore_mods",{}),expected,"committed progress at "+path)
		check_eq(SaveFormat.encode_city(loaded.city),city_before)
		check_eq(loaded.snapshot,JSON.parse_string(JSON.stringify(sim_before)))
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		document.erase("explore_mods")
		document.header.erase("saved_at")
		check_eq(document,control_doc,"city wire payload matches an actual no-mod control save")
	check_eq(host.sim.snapshot(),sim_before,"saving does not change simulation RNG")
	check(host.exploration.mod_service == null,"saving never starts missing packs")
	check_eq(runtime.metrics(),metrics,"all save paths dispatch no callbacks")
	check_eq(runtime._transactions,pending,"saving neither commits nor consumes pending host tags")
	check_eq(progress.snapshot(),expected)
	runtime.stop("test")
	check(host.load_city(recovery),"recovery/launch load uses normal host authority")
	check_eq(host.save_path,"")
	check_eq(host.explore_progress_snapshot(),expected)
	check(host.exploration.mod_service == null)
func test_damaged_progress_keeps_valid_city() -> void:
	var path := "user://f6-bad.sc2d"
	paths.append(path)
	check_eq(host.files.write_save(path),OK)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	doc["explore_mods"] = {"format_version":1,"mods":{"unknown":{"data":"broken"}}}
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(doc)); file.close()
	var loaded := SaveFormat.load(path)
	check(loaded.ok)
	check_eq(loaded.city.funds,host.sim.city.funds)
	check_eq(loaded.get("explore_mods",{}),{})
	check(not loaded.get("mod_notices",[]).is_empty(),"malformed progress gives recoverable notice")
	check(host.exploration.mod_service == null)
func test_accepted_mission_recreates_logical_actors_after_load() -> void:
	var city := flat_city()
	for x in range(18,30): city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	host.begin_city(city,{},173,null)
	host.sim.set_speed(GameClock.Speed.PAUSED)
	check(host.exploration.mod_progress.commit("desert_delivery",1,"1.0.0",{"accepted":true}).ok)
	var path := "user://f6-mission.sc2d"
	paths.append(path)
	check_eq(host.files.write_save(path),OK)
	check(host.load_city(path))
	check(host.exploration.mod_service == null,"loading never starts installed pack")
	host.exploration.mod_packs = [ExploreModPack.read("res://explore_mods/desert_delivery")]
	host.city_view_3d.set_camera_state(Vector3(22.5,4*CityGeometry3D.HEIGHT,20.5),1,12.0)
	await physics_frame
	check(host.explore_switch.enter())
	host.exploration.set_physics_process(false)
	var service := host.exploration.mod_service
	if service == null: check(false,"delivery service entered"); return
	for i in 16: service.step(.1,false)
	_check_accepted_delivery_actors(service,"load reconstructs accepted delivery roles")
	check(service.api.interactions._owned.is_empty(),"accepted phase never reoffers acceptance")
	var objectives := service.api.objectives.list_owned("desert_delivery")
	check(not objectives.is_empty())
	if not objectives.is_empty(): check_eq(objectives[0].text,"Drive to the recipient in purple farther along the road.")
	check(service.runtime.diagnostics.is_empty(),str(service.runtime.diagnostics))
	check_eq(host.exploration.mod_progress.get_state("desert_delivery",1).data,{"accepted":true},"no handles or poses persisted")
	host.explore_switch.leave()
	check(host.explore_switch.enter())
	host.exploration.set_physics_process(false)
	service = host.exploration.mod_service
	for i in 16: service.step(.1,false)
	_check_accepted_delivery_actors(service,"ordinary reentry reconstructs accepted delivery roles")
	check(service.api.interactions._owned.is_empty())
	check_eq(host.exploration.mod_progress.get_state("desert_delivery",1).data,{"accepted":true},"reentry retains accepted progress")
	var old_runtime := service.runtime
	host.begin_city(flat_city(),{},14,null)
	check(old_runtime._sessions.is_empty(),"city replacement closes old VMs")
	check(service.actors._actors.is_empty(),"city replacement releases logical actors")
	check_eq(host.explore_progress_snapshot(),{})
func test_load_and_city_replacement_use_host_authority() -> void:
	check(host.mod_progress == host.exploration.mod_progress)
	check(host.mod_progress.commit("disabled_pack",1,"1",{"phase":"accepted"}).ok)
	var path := "user://f6-load.sc2d"
	paths.append(path)
	check_eq(host.files.write_save(path),OK)
	var expected := host.explore_progress_snapshot()
	host.begin_city(flat_city(),{},44,null)
	check_eq(host.explore_progress_snapshot(),{},"new city clears previous city's progress")
	check(host.load_city(path))
	check_eq(host.explore_progress_snapshot(),expected)
	check(not host.files.has_unsaved_changes())
	check(host.exploration.mod_packs.is_empty(),"loading never enables unknown or disabled packs")
	check(host.exploration.mod_service == null)
	check(host.mod_progress.commit("disabled_pack",1,"1",{"phase":"completed"}).ok)
	check(host.files.has_unsaved_changes(),"committed progress participates in unsaved changes")
	host.session.begin_editing(flat_city(),{"seed":44})
	check_eq(host.explore_progress_snapshot(),{})
	check(host.mod_progress.commit("editing",1,"1",{"flag":true}).ok)
	check_eq(host.files.write_save(path),OK)
	check(host.load_city(path))
	check_eq(host.mod_progress.get_state("editing",1).data,{"flag":true})
	check(not host.files.has_unsaved_changes())
func test_absent_optional_field_and_selected_share() -> void:
	var path := "user://f6-old.sc2d"
	paths.append(path)
	check_eq(host.files.write_save(path),OK)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(not doc.has("explore_mods"),"empty optional field omitted")
	var loaded := SaveFormat.load(path)
	check(loaded.ok)
	check_eq(loaded.explore_mods,{})
	check_eq(loaded.mod_notices,[])
	check(host.mod_progress.commit("missing",1,"1",{"accepted":true}).ok)
	check_eq(host.files.write_save(path),OK)
	var shared := host.files.prepare_city_share(path)
	check(shared.ok)
	if shared.ok:
		paths.append(shared.path)
		check_eq(FileAccess.get_file_as_bytes(shared.path),FileAccess.get_file_as_bytes(path))
func test_interrupted_replacement_keeps_city_and_progress() -> void:
	var path := "user://f6-atomic.sc2d"
	paths.append(path)
	check(host.mod_progress.commit("atomic",1,"1",{"accepted":true}).ok)
	check_eq(host.files.write_save(path),OK)
	var bytes := FileAccess.get_file_as_bytes(path)
	var staging := ProjectSettings.globalize_path("user://f6-staging")
	DirAccess.make_dir_recursive_absolute(staging)
	# A writer interrupted before producing its document cannot replace the prior save.
	check_ne(SaveFormat._publish_staged_save(staging,ProjectSettings.globalize_path(path),true),OK)
	check_eq(FileAccess.get_file_as_bytes(path),bytes)
	check_eq(SaveFormat.load(path).explore_mods,host.explore_progress_snapshot())
	DirAccess.remove_absolute(staging.path_join("previous.sc2d"))
	DirAccess.remove_absolute(staging)
func test_version_one_save_without_progress_still_loads() -> void:
	var path := "user://f6-v1.sc2d"
	paths.append(path)
	check_eq(host.files.write_save(path),OK)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	doc["version"] = 1
	doc.city.layers["building"] = SaveFormat.encode_bytes(PackedByteArray(Array(host.sim.city.building.data)))
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(doc)); file.close()
	check(host.load_city(path))
	check_eq(host.explore_progress_snapshot(),{})
	check_eq(SaveFormat.load(path).version,1)

func _check_accepted_delivery_actors(service: ExploreModService, message: String) -> void:
	# Accept removes the courier; only the car and recipient reconstruct.
	check_eq(service.actors._actors.size(),2,"accepted delivery reconstructs exactly its car and recipient")
	var roles: Dictionary = {}
	for actor: Dictionary in service.actors._actors.values():
		roles[String(actor.owner)+":"+String(actor.key)] = String(actor.record.kind)
	check_eq(roles,{"desert_delivery:delivery_car":"car","desert_delivery:recipient":"pedestrian"},message)
	check(service.runtime.has_owner("desert_delivery"),"accepted delivery owner remains live")
