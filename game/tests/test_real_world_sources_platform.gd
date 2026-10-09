# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const Fixtures := preload("res://tests/real_world/terrain_source_fixtures.gd")
const MainScene := preload("res://scenes/main.tscn")
const NOTICE := "res://data/real_world_terrain_notices.txt"
const DIALOG := "res://scripts/ui/terrain_sources_dialog.gd"
const IDS := ["aws-terrain-joerd","esa-worldcover-2021-v200"]
const PRESET_SHA := "f034a94284df44582b58e0361248344a687ce17feed5bb0df2f20ecb9eb1c647"

func test_notices_bundled_and_reachable_offline() -> void:
 check(FileAccess.file_exists(NOTICE), "offline source notices must be bundled")
 check(FileAccess.file_exists(DIALOG), "shared offline notice component must exist")
 if not FileAccess.file_exists(DIALOG) or not FileAccess.file_exists(NOTICE): return
 var text := FileAccess.get_file_as_string(NOTICE)
 for credit in IDS+["ArcticDEM","Geoscience Australia","Österreich","Canada","EU-DEM","NOAA","INEGI","Land Information New Zealand","Kartverket","Environment Agency","U.S. Geological Survey","2021 v200","Copernicus Sentinel","https://creativecommons.org/licenses/by/4.0/","10.5281/zenodo.7254221"]:
  check(text.contains(credit),"notice retains "+credit)
 var importer_dialog := RealWorldTerrainDialog.new()
 root.add_child(importer_dialog)
 importer_dialog.open(Fixtures.metadata())
 importer_dialog.source_button.pressed.emit()
 await process_frame
 var notice: Variant=importer_dialog.get("sources_dialog")
 check(notice!=null and notice.visible,"importer opens notice offline without configured importer")
 if notice!=null:
  for compact in [false,true]:
   notice.apply_layout(compact)
   await process_frame
   check(notice.done_button.size.y>=44,"Done touch target")
   check(notice.notice_text.focus_mode!=Control.FOCUS_NONE,"notice is keyboard scrollable")
   check((notice.panel.get_meta("window_chrome").body_scroll as ScrollContainer).get_v_scroll_bar().max_value>notice.notice_text.size.y,"full notice scrolls")
   check(notice.is_ancestor_of(root.get_viewport().gui_get_focus_owner()),"focus stays in notice")
  (notice.panel.get_meta("window_chrome").body_scroll as ScrollContainer).scroll_vertical=300
  notice.done_button.pressed.emit()
  check(not notice.visible,"Done closes")
  importer_dialog.source_button.pressed.emit()
  await process_frame
  check_eq((notice.panel.get_meta("window_chrome").body_scroll as ScrollContainer).scroll_vertical,0,"reopen starts at top")
  check_eq(notice.find_children("*","HTTPRequest",true,false).size(),0,"notice performs no HTTP request")
  importer_dialog.close()
  check(not notice.visible,"owner close closes notice")
 importer_dialog.free()
 var help := HelpWindow.new()
 root.add_child(help)
 help.open()
 help.get("sources_button").pressed.emit()
 await process_frame
 notice=help.get("sources_dialog")
 check(notice!=null and notice.visible,"Help opens same notice after founding offline")
 if notice!=null:
  check_eq(notice.notice_text.text,text)
  help.close()
  check(not notice.visible)
 help.free()
 await process_frame

func test_source_ids_survive_founding() -> void:
 var candidate := RealWorldTerrain.convert(Fixtures.conversion_packet("provenance"),Fixtures.controls(),Fixtures.metadata())
 check(candidate.ok)
 check_eq(candidate.origin.get("notice_ids",[]),IDS,"conversion binds attribution IDs")
 var old: Dictionary=candidate.origin.duplicate(true)
 old.erase("notice_ids")
 check_eq(RealWorldManifest.sanitize_origin(old).get("notice_ids",[]),IDS,"older origins derive known credits")
 old.notice_ids=["https://invalid.example", "unknown", IDS[1], IDS[1]]
 check_eq(RealWorldManifest.sanitize_origin(old).get("notice_ids",[]),IDS,"only applicable recognized references survive")
 var host: GameHost=MainScene.instantiate()
 host.preferences_path="user://real-world-platform-preferences.cfg"
 root.add_child(host)
 var settings := RealWorldManifest.editing_settings(candidate)
 settings.merge(Fixtures.metadata())
 host.start_new_city(settings,candidate.city)
 check(host.found_city())
 check_eq(host.sim.city.terrain_origin.get("notice_ids",[]),IDS)
 check_eq(host.sim.city.terrain_origin.sources,candidate.origin.sources)
 var path := "user://saves/real-world-platform.sc2d"
 check_eq(SaveFormat.save(path,host.sim.city,host.sim.snapshot()),OK)
 var loaded := SaveFormat.load(path)
 check(loaded.ok)
 check_eq(loaded.city.terrain_origin.get("notice_ids",[]),IDS)
 check_eq(loaded.city.terrain_origin.source_objects,candidate.origin.source_objects)
 check(not JSON.stringify(loaded.city.terrain_origin).contains("https://"))
 check(JSON.stringify(loaded.city.terrain_origin).to_utf8_buffer().size()<=262144)
 check_eq(SaveFormat.VERSION,1)
 check(host.load_city(path),"native founded city reloads offline")
 host.sim.set_speed(GameClock.Speed.FASTEST)
 check(host.sim.is_processing(),"founded native-loaded city genuinely runs before opening notice")
 var advancing_day: int=host.sim.city.day
 await create_timer(0.18).timeout
 check(host.sim.city.day>advancing_day,"fixture advances without any test-created hold")
 var before := SaveFormat.encode_city(host.sim.city)
 var state := host.sim.snapshot().duplicate(true)
 host.open_window("help")
 var help: Variant=host.windows.help
 check(host.sim.is_processing() and not host.is_input_blocked(),"ordinary Help retains nonmodal behavior")
 help.sources_button.pressed.emit()
 check(not host.sim.is_processing(),"Help notice acquires its own production process hold")
 check(host.is_input_blocked(),"Help notice owns city input independent of focus")
 await create_timer(0.18).timeout
 check(help.sources_dialog.visible,"founded/reloaded Help opens bundled credits")
 help.sources_dialog.done_button.pressed.emit()
 check_eq(SaveFormat.encode_city(host.sim.city),before,"source notice preserves founded city")
 check_eq(host.sim.snapshot(),state,"source notice preserves running simulation/RNG")
 check(host.sim.is_processing(),"Done restores prior processing")
 check(not host.is_input_blocked(),"Done releases its input ownership")
 check(host._sim_process_holds.is_empty(),"Done leaves no notice hold")
 advancing_day=host.sim.city.day
 await create_timer(0.18).timeout
 check(host.sim.city.day>advancing_day,"Done resumes real clock advancement")
 host.free()
 DirAccess.remove_absolute(path)
 await process_frame

func test_android_internet_and_macos_network_entitlement_only() -> void:
 var cfg := ConfigFile.new()
 check_eq(cfg.load("res://export_presets.cfg"),OK)
 var original := FileAccess.get_file_as_string("res://export_presets.cfg")
 var normalized := original.replace(",data/real_world_terrain_notices.txt", "")
 normalized=normalized.replace("permissions/internet=true", "permissions/internet=false")
 normalized=normalized.replace("codesign/entitlements/app_sandbox/network_client=true", "codesign/entitlements/app_sandbox/network_client=false")
 check_eq(RealWorldManifest.sha256(normalized.to_utf8_buffer()).hex_encode(),PRESET_SHA,"every other export/signing field is unchanged")
 var presets := 0
 for section in cfg.get_sections():
  var platform: String=cfg.get_value(section,"platform","")
  if platform.is_empty(): continue
  presets+=1
  check(String(cfg.get_value(section,"include_filter","")).split(",").count("data/real_world_terrain_notices.txt")==1,"each preset bundles plain-text notice once")
  var opts := section+".options"
  if platform=="Android": check_eq(cfg.get_value(opts,"permissions/internet",false),true)
  if platform=="macOS":
   check_eq(cfg.get_value(opts,"codesign/entitlements/app_sandbox/network_client",false),true)
   check_eq(cfg.get_value(opts,"codesign/entitlements/app_sandbox/enabled",true),false)
  if platform=="iOS":
   for key in cfg.get_section_keys(opts):
    check(not str(cfg.get_value(opts,key,"")).contains("NSAllowsArbitraryLoads") and not str(cfg.get_value(opts,key,"")).contains("NSExceptionAllowsInsecureHTTPLoads"),"no insecure HTTP exception")
 check_eq(presets,6)

func test_notice_uses_shared_scroll_and_safe_done() -> void:
 var notice: Variant=load(DIALOG).new()
 root.add_child(notice)
 notice.open()
 var chrome: Dictionary=notice.panel.get_meta("window_chrome")
 var scroll: ScrollContainer=chrome.body_scroll
 check(scroll.vertical_scroll_mode!=ScrollContainer.SCROLL_MODE_DISABLED,"shared body scroll supports iOS swipe/glide")
 for bounds in [Rect2(12,30,366,770),Rect2(30,12,784,315),Rect2(12,30,366,390),Rect2(24,24,976,1294)]:
  notice.panel.set_meta("display_usable_rect",bounds)
  notice.apply_layout(bounds.size.x<700)
  for i in 6: await process_frame
  var done_rect: Rect2=notice.done_button.get_global_rect()
  check(bounds.encloses(done_rect),"Done remains within injected safe/keyboard bounds")
  check(done_rect.size.y>=44 and done_rect.size.x>=44)
  scroll.scroll_vertical=100000
  await process_frame
  check(scroll.scroll_vertical>0,"full notice can scroll in each shape")
  notice.done_button.grab_focus()
  check_eq(notice.done_button.get_node(notice.done_button.focus_next),chrome.close_button,"focus wraps to notice close")
 notice.free()
 await process_frame

func test_notice_references_follow_only_applicable_sources() -> void:
 var candidate := RealWorldTerrain.convert(Fixtures.conversion_packet("provenance"),Fixtures.controls(),Fixtures.metadata())
 for entry in [["terrarium","aws-terrain-joerd"],["worldcover","esa-worldcover-2021-v200"]]:
  var origin: Dictionary=candidate.origin.duplicate(true)
  origin.erase("source_objects")
  origin.sources=origin.sources.filter(func(d: Dictionary) -> bool: return d.source==entry[0])
  origin.notice_ids=["unrecognized", "https://invalid.example", "x".repeat(262145)]
  var sanitized := RealWorldManifest.sanitize_origin(origin)
  check_eq(sanitized.get("notice_ids",[]),[entry[1]],"recognized references derive only from validated descriptors")
  check(JSON.stringify(sanitized).to_utf8_buffer().size()<=262144)
  check(not JSON.stringify(sanitized).contains("https://"))

func _notice_host() -> GameHost:
 var host: GameHost=MainScene.instantiate()
 host.preferences_path="user://real-world-platform-hold.cfg"
 root.add_child(host)
 host.start_new_city({"seed":4242},flat_city())
 check(host.found_city())
 return host

func test_help_notice_restores_pause_and_prior_process_holds() -> void:
 var host := _notice_host()
 for condition in ["paused","raw_disabled","other_hold"]:
  for owner_close in [false,true]:
   host.sim.set_speed(GameClock.Speed.PAUSED if condition=="paused" else GameClock.Speed.FASTEST)
   host.sim.set_process(condition!="raw_disabled")
   if condition=="other_hold": host.acquire_sim_process_hold(&"other_hold")
   var processing := host.sim.is_processing()
   var holds: Dictionary=host._sim_process_holds.duplicate()
   var before := SaveFormat.encode_city(host.sim.city)
   var state := host.sim.snapshot().duplicate(true)
   var help := host.open_window("help") as HelpWindow
   help.sources_button.pressed.emit()
   help.sources_dialog.open() # repeated opening cannot acquire twice
   check(not host.sim.is_processing())
   check(host.is_input_blocked())
   check_eq(host._sim_process_holds.size(),holds.size()+1,"one notice-owned hold composes with existing owners")
   await create_timer(0.12).timeout
   check_eq(SaveFormat.encode_city(host.sim.city),before)
   check_eq(host.sim.snapshot(),state)
   if owner_close: help.close()
   else: help.sources_dialog.done_button.pressed.emit()
   help.sources_dialog.close() # duplicate close cannot release another owner's hold
   check(not help.sources_dialog.visible)
   check_eq(host.sim.is_processing(),processing,"prior raw/held processing state returns exactly")
   check_eq(host._sim_process_holds,holds,"prior owner dictionary returns exactly")
   check(not host.is_input_blocked())
   check_eq(host.sim.snapshot(),state,"prior pause/speed/RNG returns exactly")
   if condition=="other_hold": host.release_sim_process_hold(&"other_hold")
 host.free()
 await process_frame

func test_help_notice_suspend_cleanup_and_importer_single_modal_owner() -> void:
 var host := _notice_host()
 host.sim.set_speed(GameClock.Speed.FASTEST)
 var help := host.open_window("help") as HelpWindow
 help.sources_button.pressed.emit()
 check(not host.sim.is_processing())
 check_eq(host.suspend_for_background("user://real-world-platform-recovery.sc2d"),OK)
 check(not help.sources_dialog.visible,"background suspension closes Help notice")
 check_eq(host._sim_process_holds.keys(),[&"background"],"only lifecycle hold remains")
 check_eq(host.modal_depth,0,"no dangling notice modal")
 host.resume_from_background()
 check(host.sim.is_processing())
 check_eq(host.sim.speed,GameClock.Speed.PAUSED,"background policy retains pause")
 check(host._sim_process_holds.is_empty())
 check(not host.is_input_blocked())
 help.sources_button.pressed.emit()
 host.escape()
 check(not help.sources_dialog.visible,"Escape closes the child first")
 check(help.visible,"Escape retains ordinary Help")
 check(host._sim_process_holds.is_empty())
 help.close()
 host.new_city_dialog.terrain_transport_factory=preload("res://tests/real_world/fake_terrain_transport.gd").new().make_transport
 host.open_new_city_dialog()
 host.new_city_dialog.open_real_world()
 var child := host.new_city_dialog.terrain_dialog
 var holds: Dictionary=host._sim_process_holds.duplicate()
 check_eq(host.modal_depth,1)
 child.source_button.pressed.emit()
 check_eq(host.modal_depth,1,"importer notice reuses parent's single modal owner")
 check_eq(host._sim_process_holds,holds,"Help hold is never installed on importer child")
 child.sources_dialog.done_button.pressed.emit()
 check_eq(host.modal_depth,1)
 child.source_button.pressed.emit()
 host.new_city_dialog.cancel_online_work()
 check(not child.sources_dialog.visible)
 check_eq(host.modal_depth,1)
 host.new_city_dialog.close()
 check_eq(host.modal_depth,0)
 if host.new_city_dialog.terrain_importer!=null:
  while not host.new_city_dialog.terrain_importer.is_drained(): await process_frame
 host.free()
 DirAccess.remove_absolute("user://real-world-platform-recovery.sc2d")
 await process_frame
