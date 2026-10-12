# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/explore_session_case.gd"
const Registry = preload("res://scripts/exploration/mods/explore_mod_registry.gd")
class PublicationFailureRegistry extends ExploreModRegistry:
	var fail_publication := false
	var candidate_validated := false
	var forced_failures := 0
	func _validate_source(snapshot: Dictionary) -> Dictionary:
		var result := super._validate_source(snapshot)
		candidate_validated = result.ok
		return result
	func _publish(snapshot: Dictionary, destination: String) -> Dictionary:
		if fail_publication:
			forced_failures += 1
			return {"ok":false,"code":"write"}
		return super._publish(snapshot,destination)

var serial := Time.get_ticks_usec()
func fixture(id: String, source: String = "return {}") -> String:
	serial += 1
	var path := "user://f7-source-%d" % serial
	DirAccess.make_dir_recursive_absolute(path)
	var f := FileAccess.open(path.path_join("manifest.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"id":id,"name":id,"version":"1.0.0","api_version":1,"state_version":1,"entry":"main.lua"})); f.close()
	f = FileAccess.open(path.path_join("main.lua"),FileAccess.WRITE)
	f.store_string(source); f.close()
	return path
func test_import_disabled_and_reload_atomic() -> void:
	var registry := Registry.new()
	registry.install_directory = "user://f7-installed-%d" % Time.get_ticks_usec()
	var source := fixture("example")
	var installed := registry.import_pack(source)
	check(installed.ok)
	check(registry.active_packs().is_empty(),"import requires explicit Enable")
	check(registry.set_enabled("example",true).ok)
	var before: Dictionary = registry.active_packs()[0]
	var f := FileAccess.open(source.path_join("main.lua"),FileAccess.WRITE)
	f.store_string("return {on_tick=function(api) api.log('new') end}"); f.close()
	check(not registry.reload("example",false).ok,"reload requires suspension")
	check(registry.reload("example",true).ok)
	check(before.content_hash != registry.active_packs()[0].content_hash)
	var accepted: Dictionary = registry.active_packs()[0]
	f = FileAccess.open(source.path_join("main.lua"),FileAccess.WRITE)
	f.store_string("return { broken syntax"); f.close()
	check(not registry.reload("example",true).ok)
	check_eq(registry.active_packs()[0].content_hash,accepted.content_hash,"malformed edit keeps validated snapshot")
	check(FileAccess.file_exists(installed.path.path_join("main.lua")),"old immutable version remains installed")
	var fresh := Registry.new()
	fresh.install_directory = registry.install_directory
	fresh.set_preferences(["example"])
	fresh.scan("user://absent-f7-bundled")
	check_eq(fresh.active_packs()[0].content_hash,accepted.content_hash,"restart reads published version despite malformed source")

func test_archive_extensions_import_disabled_and_reload_editable_source() -> void:
	serial += 1
	var original := "user://archive-contract-%d.scddmod" % serial
	var compatible := original.get_basename()+".zip"
	var source := fixture("archive_contract")
	var writer := ZIPPacker.new()
	check_eq(writer.open(original),OK)
	for name in ["manifest.json","main.lua"]:
		writer.start_file(name)
		writer.write_file(FileAccess.get_file_as_bytes(source.path_join(name)))
		writer.close_file()
	writer.close()
	check_eq(DirAccess.copy_absolute(original,compatible),OK)
	check_eq(FileAccess.get_file_as_bytes(original),FileAccess.get_file_as_bytes(compatible),"both suffixes contain the same ZIP bytes")
	for archive in [original,compatible]:
		serial += 1
		var registry := Registry.new()
		registry.install_directory = "user://archive-install-%d" % serial
		registry.set_preferences(["archive_contract"])
		var imported := registry.import_pack(archive)
		check(imported.ok,"registry accepts "+archive.get_extension())
		if not imported.ok: continue
		check_eq(imported.code,"imported_disabled")
		check(registry.active_packs().is_empty(),"archive import clears stale enabled preference")
		check(registry.enabled_ids().is_empty(),"only explicit Enable activates an archive")
		var entry: Dictionary = registry.entries()[0]
		check(not entry.enabled)
		check(entry.source_path != archive and entry.source_path != entry.path,"archive receives a separate editable source directory")
		check(DirAccess.dir_exists_absolute(entry.source_path),"editable source is an unpacked folder")
		check_eq(FileAccess.get_file_as_string(entry.source_path.path_join("main.lua")),"return {}")
		check(registry.set_enabled("archive_contract",true).ok)
		var before: Dictionary = registry.active_packs()[0]
		var replacement := "return {on_start=function(api) api.state.set('edited',true) end}"
		var file := FileAccess.open(entry.source_path.path_join("main.lua"),FileAccess.WRITE)
		file.store_string(replacement); file.close()
		check(not registry.reload("archive_contract",false).ok,"archive reload still requires suspension")
		check(registry.reload("archive_contract",true).ok,"archive reload reads its editable source")
		var accepted: Dictionary = registry.active_packs()[0]
		check_ne(accepted.content_hash,before.content_hash,"edited archive content publishes a new immutable version")
		check_eq(accepted.sources["main.lua"],replacement)
		check_eq(FileAccess.get_file_as_bytes(original),FileAccess.get_file_as_bytes(compatible),"editing source never rewrites either distributed archive")
		file = FileAccess.open(entry.source_path.path_join("main.lua"),FileAccess.WRITE)
		file.store_string("return { broken syntax"); file.close()
		check(not registry.reload("archive_contract",true).ok,"malformed archive source edit is rejected")
		check_eq(registry.active_packs()[0].content_hash,accepted.content_hash,"failed archive reload retains its accepted version")
		var restarted := Registry.new()
		restarted.install_directory = registry.install_directory
		restarted.set_preferences(["archive_contract"])
		restarted.scan("user://absent-archive-bundled")
		check_eq(restarted.active_packs()[0].content_hash,accepted.content_hash,"catalog restores archive's published version")
		check_eq(restarted.entries()[0].source_path,entry.source_path,"catalog retains editable archive source")

func test_malformed_archive_extensions_leave_registry_unchanged() -> void:
	for extension in ["scddmod","zip"]:
		serial += 1
		var archive := "user://bad-archive-%d.%s" % [serial,extension]
		var writer := ZIPPacker.new()
		check_eq(writer.open(archive),OK)
		writer.start_file("../main.lua")
		writer.write_file("return {}".to_utf8_buffer())
		writer.close_file()
		writer.close()
		var registry := Registry.new()
		registry.install_directory = "user://bad-archive-install-%d" % serial
		var result := registry.import_pack(archive)
		check(not result.ok,"malformed "+extension+" refused")
		check_eq(result.code,"archive_path","both suffixes use the same safe ZIP decoder")
		check(registry.entries().is_empty(),"malformed archive installs no registry entry")
		check(registry.enabled_ids().is_empty(),"malformed archive enables nothing")
		check(not FileAccess.file_exists(registry.install_directory.path_join("catalog.json")),"malformed archive publishes no catalog")
		var directory := DirAccess.open(registry.install_directory)
		check(directory.get_directories().is_empty(),"malformed archive leaves no version or staging folder")

func test_admission_preferences_and_bounded_diagnostics() -> void:
	var registry := Registry.new()
	registry.install_directory = "user://f7-admission-%d" % Time.get_ticks_usec()
	for i in 9:
		var id := "pack%d" % i
		check(registry.import_pack(fixture(id)).ok)
		check_eq(registry.set_enabled(id,true).ok,i < 8)
	check_eq(registry.active_packs().size(),8)
	check(not registry.import_pack(fixture("pack0")).ok,"duplicate identities refused")
	check_eq(ViewPreferences.sanitize({"explore_enabled_mods":["pack0","pack0","BAD",12,"../x"]}).explore_enabled_mods,["pack0"])
	for i in 200: registry.set_enabled("missing",true)
	check(registry.diagnostic_text().to_utf8_buffer().size() <= 16384)
	check(registry.diagnostics.size() <= 128)
	check(not registry.runtime_label().is_empty())
func test_panel_contract() -> void:
	var panel := ExploreModsPanel.new()
	panel.bind(Registry.new(),null)
	panel.open()
	check(panel.visible)
	panel.close()
	check(not panel.visible)
	panel.free()

func test_targeted_reload_keeps_other_native_sessions() -> void:
	var value := flat_city()
	for x in range(18,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	if not _setup(value) or not await _enter(): return
	session.set_physics_process(false)
	var registry := Registry.new()
	registry.install_directory = "user://f7-live-%d" % Time.get_ticks_usec()
	var sources: Array[String] = []
	for i in 8:
		var code := 'return {on_start=function(api) api.state.set("starts",api.state.get("starts",0)+1); api.timer.after("keep",300) end,on_event=function(api,event) end}'
		if i < 2: code = 'return {on_start=function(api) api.state.set("starts",api.state.get("starts",0)+1); api.actor.spawn("pedestrian",{key="walker",variant="pedestrian_03",near_player=true}); api.timer.after("keep",300) end,on_event=function(api,event) end}'
		if i < 2: code = code.replace("near_player=true", "position={x=%s,y=%s,z=20.5}" % [22.5+i*2,GROUND])
		var source := fixture("live%d" % i,code)
		sources.append(source)
		check(registry.import_pack(source).ok)
		check(registry.set_enabled("live%d" % i,true).ok)
	var service := ExploreModService.new()
	session.mod_service = service
	service.bind(session,registry.active_packs(),session.mod_progress)
	service.enter()
	registry.service = service
	var reconfigure := func() -> void: service.configure_packs(registry.active_packs())
	registry.changed.connect(reconfigure)
	for i in 5: service.step(.1,false)
	check_eq(service.runtime.metrics().sessions,8)
	var keeper: Dictionary = service.runtime._sessions.live1
	var keeper_callbacks := keeper.duplicate(true)
	var keeper_timer: Dictionary = service.api._timers.live1.duplicate(true)
	var handles := {}
	for id: String in service.actors._actors: handles[service.actors._actors[id].owner] = id
	check(handles.has("live0") and handles.has("live1"),"two native actors admitted")
	var keeper_actor: Dictionary = service.actors._actors.get(handles.get("live1",""),{}).duplicate(true)
	session._suspend(true)
	var extra := registry.import_pack(fixture("ninth"))
	check(extra.ok,"disabled import is possible with eight live VMs")
	check_eq(service.runtime.metrics().sessions,8)
	check(not registry.set_enabled("ninth",true).ok)
	var f := FileAccess.open(sources[0].path_join("main.lua"),FileAccess.WRITE)
	f.store_string('return {on_start=function(api) api.state.set("replacement",true) end}'); f.close()
	check(registry.reload("live0",true).ok)
	check_eq(service.runtime.metrics().sessions,7,"candidate VM closes before Resume")
	check(service.runtime._sessions.live1 == keeper,"unaffected VM retained")
	check_eq(service.runtime._sessions.live1,keeper_callbacks,"unaffected callback queue/query cache/tick phase retained")
	check_eq(service.api._timers.live1,keeper_timer,"other active-time timer phase retained")
	if handles.has("live0"):
		check(not service.actors._actors.has(handles.live0),"old handle destroyed")
		var stale := service.actors.apply({"owner":"live0","generation":service.generation,"request_id":999,"kind":"actor.inspect","args":{"id":handles.live0}})
		check_eq(stale.code,"stale_id")
	if handles.has("live1"):
		check(service.actors._actors.has(handles.live1),"unaffected actor remains")
		check_eq(service.actors._actors[handles.live1],keeper_actor,"unaffected actor transform/route/gait phase retained")
	check(not session.mod_progress.get_state("live0",1).data.get("replacement",false),"Enable/reload dispatch waits for Resume")
	session.resume()
	check_eq(service.runtime.metrics().sessions,8)
	check(session.mod_progress.get_state("live0",1).data.get("replacement",false))
	check_eq(session.mod_progress.get_state("live1",1).data.starts,1,"other on_start never repeats")
	check(service.runtime.diagnostics.filter(func(d: Dictionary) -> bool: return d.reason not in ["disabled"]).is_empty(),str(service.runtime.diagnostics))
	session._suspend(true)
	var snapshot_hash: String = registry.active_packs()[0].content_hash
	f = FileAccess.open(sources[0].path_join("main.lua"),FileAccess.WRITE)
	f.store_string("return { broken syntax"); f.close()
	check(not registry.reload("live0",true).ok)
	check_eq(registry.active_packs()[0].content_hash,snapshot_hash,"malformed edit retains whole prior snapshot")
	check_eq(service.runtime.metrics().sessions,7,"failed candidate leaves no replacement VM")
	check(service.runtime._sessions.live1.vm == keeper.vm)
	session.resume()
	check_eq(service.runtime.metrics().sessions,8,"Resume starts preserved snapshot")
	session._suspend(true)
	check(registry.set_enabled("live7",false).ok)
	check_eq(service.runtime.metrics().sessions,7,"Disable cleans one slot immediately")
	check(registry.set_enabled("ninth",true).ok)
	check_eq(service.runtime.metrics().sessions,7,"Enable remains inert until explicit Resume")
	check(not service.runtime.has_owner("ninth"))
	session.resume()
	check_eq(service.runtime.metrics().sessions,8)
	check(service.runtime.has_owner("ninth"))
	check(service.runtime._sessions.live1.vm == keeper.vm,"new enable preserves unaffected owner")
	registry.changed.disconnect(reconfigure)
	registry.service = null

func test_failed_version_publication_restores_only_selected_owner() -> void:
	var value := flat_city()
	for x in range(18,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	if not _setup(value) or not await _enter(): return
	session.set_physics_process(false)
	var registry := PublicationFailureRegistry.new()
	registry.install_directory = "user://f7-live-%d" % Time.get_ticks_usec()
	var sources: Array[String] = []
	for i in 8:
		var code := 'return {on_start=function(api) api.state.set("starts",api.state.get("starts",0)+1); api.timer.after("keep",300) end,on_event=function(api,event) end}'
		if i < 2: code = 'return {on_start=function(api) api.state.set("starts",api.state.get("starts",0)+1); api.actor.spawn("pedestrian",{key="walker",variant="pedestrian_03",near_player=true}); api.timer.after("keep",300) end,on_event=function(api,event) end}'
		if i < 2: code = code.replace("near_player=true", "position={x=%s,y=%s,z=20.5}" % [22.5+i*2,GROUND])
		var source := fixture("live%d" % i,code)
		sources.append(source)
		check(registry.import_pack(source).ok)
		check(registry.set_enabled("live%d" % i,true).ok)
	var service := ExploreModService.new()
	session.mod_service = service
	service.bind(session,registry.active_packs(),session.mod_progress)
	service.enter()
	registry.service = service
	var reconfigure := func() -> void: service.configure_packs(registry.active_packs())
	registry.changed.connect(reconfigure)
	for i in 5: service.step(.1,false)
	check_eq(service.runtime.metrics().sessions,8)
	var keeper: Dictionary = service.runtime._sessions.live1
	var keeper_callbacks := keeper.duplicate(true)
	var keeper_timer: Dictionary = service.api._timers.live1.duplicate(true)
	var handles := {}
	for id: String in service.actors._actors: handles[service.actors._actors[id].owner] = id
	check(handles.has("live0") and handles.has("live1"),"two native actors admitted")
	var keeper_actor: Dictionary = service.actors._actors.get(handles.get("live1",""),{}).duplicate(true)
	session._suspend(true)
	var old_hash: String = registry.active_packs()[0].content_hash
	var f := FileAccess.open(sources[0].path_join("main.lua"),FileAccess.WRITE)
	f.store_string('return {on_start=function(api) api.state.set("replacement",true) end}'); f.close()
	registry.fail_publication = true
	var result := registry.reload("live0",true)
	check(not result.ok and result.code == "write","version publication failure is reported")
	check(registry.candidate_validated,"real native candidate validation succeeded before publication")
	check_eq(registry.forced_failures,1,"version publication path was reached")
	check_eq(registry.active_packs()[0].content_hash,old_hash,"old immutable version remains selected")
	check_eq(service.runtime.metrics().sessions,7,"selected owner and candidate VM closed")
	check_eq(service._pending_start.keys(),["live0"],"only old selected owner is scheduled")
	check(not service.actors._actors.has(handles.live0),"old selected handle remains destroyed")
	check_eq(service.runtime._sessions.live1,keeper_callbacks,"keeper VM/callbacks/query cache/phase unchanged before Resume")
	check_eq(service.api._timers.live1,keeper_timer)
	check_eq(service.actors._actors[handles.live1],keeper_actor)
	session.resume()
	check_eq(service.runtime.metrics().sessions,8,"explicit Resume restores prior selected code")
	check_eq(service.runtime._context("live0",{}).progress.get("starts",0),2,"prior snapshot on_start runs once again with pending host commands")
	check(not session.mod_progress.get_state("live0",1).data.get("replacement",false),"unpublished candidate never dispatches")
	check_eq(service.runtime._sessions.live1,keeper_callbacks,"keeper VM/callbacks/query cache/phase unchanged after Resume")
	check(service.runtime._sessions.live1.vm == keeper.vm)
	check_eq(service.api._timers.live1,keeper_timer,"keeper timer identity and phase unchanged")
	check_eq(service.actors._actors[handles.live1],keeper_actor,"keeper actor identity and phase unchanged")
	check_eq(session.mod_progress.get_state("live1",1).data.starts,1,"keeper on_start not repeated")
	service.step(.1,false)
	check_eq(session.mod_progress.get_state("live0",1).data.get("starts",0),2,"prior on_start writes become durable after real host acceptance")
	check(not session.mod_progress.get_state("live0",1).data.get("replacement",false))
	check(service.runtime.diagnostics.filter(func(d: Dictionary) -> bool: return d.reason not in ["disabled"]).is_empty(),str(service.runtime.diagnostics))
	registry.changed.disconnect(reconfigure)
	registry.service = null

func test_failed_catalog_publication_does_not_replace_snapshot() -> void:
	var registry := Registry.new()
	registry.install_directory = "user://f7-atomic-%d" % Time.get_ticks_usec()
	var source := fixture("atomic")
	check(registry.import_pack(source).ok)
	check(registry.set_enabled("atomic",true).ok)
	var before: String = registry.active_packs()[0].content_hash
	var catalog := registry.install_directory.path_join("catalog.json")
	DirAccess.remove_absolute(catalog)
	DirAccess.make_dir_absolute(catalog)
	var file := FileAccess.open(source.path_join("main.lua"),FileAccess.WRITE)
	file.store_string("return {on_start=function(api) api.state.set('new',true) end}"); file.close()
	check(not registry.reload("atomic",true).ok,"unpublishable version is refused")
	check_eq(registry.active_packs()[0].content_hash,before,"prior version remains selected")

func test_scan_disables_duplicate_identity_candidates() -> void:
	var registry := Registry.new()
	registry.install_directory = "user://f7-duplicate-index-%d" % Time.get_ticks_usec()
	var folder := "user://f7-duplicates-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(folder)
	var source := fixture("duplicate")
	for name in ["first","second"]:
		var destination := folder.path_join(name)
		DirAccess.make_dir_recursive_absolute(destination)
		for file in ["manifest.json","main.lua"]: DirAccess.copy_absolute(source.path_join(file),destination.path_join(file))
	var entries := registry.scan(folder)
	check_eq(entries.size(),2)
	for entry in entries: check_eq(entry.code,"duplicate_id")
	check(not registry.set_enabled("duplicate",true).ok)
	check(registry.active_packs().is_empty())

func test_faulted_owner_does_not_restart_on_plain_resume() -> void:
	var value := flat_city()
	for x in range(18,30): value.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	if not _setup(value) or not await _enter(): return
	session.set_physics_process(false)
	var source := fixture("faulted",'return {on_start=function(api) api.state.set("starts",api.state.get("starts",0)+1) end,on_tick=function(api) error("intentional") end}')
	var service := ExploreModService.new()
	session.mod_service = service
	service.bind(session,[ExploreModPack.read(source)],session.mod_progress)
	service.enter()
	service.step(.1,false)
	check(not service.runtime.has_owner("faulted"))
	session._suspend(true)
	session.resume()
	check(not service.runtime.has_owner("faulted"),"ordinary Resume cannot revive a faulted owner")
	check_eq(session.mod_progress.get_state("faulted",1).data.starts,1)

func test_native_errors_reach_plain_text_panel_and_bounded_copy() -> void:
	check_eq(ExploreLuaBridge.diagnostic_text("author"+String.chr(1)+"\tline\n"+String.chr(31)),"author\tline\n","strip existing controls while preserving tab and newline")
	check(ExploreLuaBridge.available(),"native error regression requires the actual VM")
	if not ExploreLuaBridge.available(): return
	var registry := Registry.new()
	registry.install_directory = "user://native-error-install-%d" % Time.get_ticks_usec()
	var source := fixture("native_error","return {on_start=function(api) require('lib.broken').fail() end}")
	DirAccess.make_dir_recursive_absolute(source.path_join("lib"))
	var helper := source.path_join("lib/broken.lua")
	var file := FileAccess.open(helper,FileAccess.WRITE)
	file.store_string("return {fail=function()\nerror('[b]author reason /private/tmp/secret-build/source.cpp C:\\\\private\\\\source.cpp user://installation/source.lua')\nend}")
	file.close()
	check(registry.import_pack(source).ok)
	check(registry.set_enabled("native_error",true).ok)
	var service := ExploreModService.new()
	service.runtime.bind(registry.active_packs(),ExploreModProgress.new(),1)
	check(not service.runtime.has_owner("native_error"),"actual Lua runtime exception disables its owner")
	check_eq(service.runtime.diagnostics.size(),1)
	var diagnostic: Dictionary = service.runtime.diagnostics[0]
	check_eq(diagnostic.reason,"script_error","stable fault retained alongside detail")
	check(String(diagnostic.diagnostic).contains("lib/broken.lua:2:"),"validated relative chunk and line survive")
	check(String(diagnostic.diagnostic).contains("[b]author reason"),"native author's reason survives as plain text")
	check(String(diagnostic.diagnostic).contains("[path]"),"script-selected host paths are redacted")
	var panel := ExploreModsPanel.new()
	panel.bind(registry,service)
	var label_text := ""
	for label: Node in panel.rows.find_children("*","Label",true,false): label_text += (label as Label).text+"\n"
	check(label_text.contains("Last error: script_error: lib/broken.lua:2:"),"actual runtime diagnostic reaches last-error Label")
	check(label_text.contains("[b]author reason"),"Label keeps script-selected markup literal")
	var copied := registry.diagnostic_text()
	for private_text in [source,registry.install_directory,"secret-build","private\\source.cpp","installation/source.lua"]:
		check(not copied.contains(private_text),"copy excludes host source/install/build paths")
	check(copied.contains("lib/broken.lua:2:") and copied.contains("author reason"),"copy exposes actionable runtime detail")
	# A real compilation failure in a nested package chunk traverses reload.
	file = FileAccess.open(helper,FileAccess.WRITE)
	file.store_string("return {\n broken syntax"); file.close()
	var failed := registry.reload("native_error",true)
	check(not failed.ok and failed.code == "script_error")
	check(String(failed.diagnostic).contains("lib/broken.lua:2:"),"reload result keeps actual syntax location")
	check(String(failed.diagnostic).contains("expected"),"reload retains parser reason")
	# The newer reload error must supersede the older runtime failure.
	panel.refresh()
	label_text = ""
	for label: Node in panel.rows.find_children("*","Label",true,false): label_text += (label as Label).text+"\n"
	check(label_text.contains(String(failed.diagnostic)),"reload error appears in plain-text Label")
	check(registry.diagnostic_text().contains(String(failed.diagnostic)),"reload error reaches copy path")
	panel.free()
	# Stress the real native diagnostic ring without admitting live sessions.
	var malformed: Dictionary = registry.active_packs()[0].duplicate(true)
	malformed.sources = {"main.lua":"return { broken syntax"}
	for i in 130: check(not service.runtime.start_pack(malformed))
	check_eq(service.runtime.diagnostics.size(),128,"native failures retain the per-owner ring cap")
	check(service.runtime.diagnostics.all(func(d: Dictionary) -> bool: return String(d.diagnostic).contains("main.lua:1:")))
	registry.service = service
	for i in 128: registry._note("native_error","script_error","é".repeat(4096)+" /private/tmp/secret-build")
	check(registry.diagnostics.all(func(d: Dictionary) -> bool: return String(d.diagnostic).to_utf8_buffer().size() <= 4096))
	copied = registry.diagnostic_text()
	check(copied.to_utf8_buffer().size() <= 16384,"copy cap applies to UTF-8 bytes")
	check(not copied.contains("secret-build"))
