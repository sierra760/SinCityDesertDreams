# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const MainScene := preload("res://scenes/main.tscn")
const Fixtures := preload("res://tests/real_world/terrain_source_fixtures.gd")
const Fake := preload("res://tests/real_world/fake_terrain_transport.gd")
const SAVE := "user://saves/real-world-host-active.sc2d"
var host: GameHost
var fake: RefCounted
var candidate: Dictionary
func before_each() -> void:
 host=MainScene.instantiate()
 host.preferences_path="user://real-world-host.cfg"
 root.add_child(host)
 fake=Fake.new()
 fake.install_flat_objects()
 host.new_city_dialog.terrain_transport_factory=fake.make_transport
 candidate=RealWorldTerrain.convert(Fixtures.packet(),Fixtures.controls(),Fixtures.metadata())
 check(candidate.ok)
func after_each() -> void:
 host.new_city_dialog.close()
 if host.new_city_dialog.terrain_importer!=null:
  host.new_city_dialog.terrain_importer.suspend()
  while not host.new_city_dialog.terrain_importer.is_drained(): await process_frame
 host.free()
 DirAccess.remove_absolute(SAVE)
 await process_frame
 fake=null
func online() -> void:
 # The online check starts only once Real-world terrain is chosen.
 host.new_city_dialog.set_source("real_world")
 for frame in 16:
  fake.advance_clock(0); fake.serve_pending()
  await process_frame
 check(host.new_city_dialog.terrain_importer.is_online_fresh())
func _active() -> void:
 host.start_new_city({"name":"Keep active", "seed":8765})
 host.found_city()
 host.sim.set_speed(GameClock.Speed.FAST)
 host.save_path=SAVE
 check_eq(host.save_city(),OK)
func test_accepted_prebuilt_identity_and_modal_speed_restore() -> void:
 _active()
 var original_active_city := host.sim.city
 host.open_new_city_dialog()
 check_eq(host.modal_depth,1)
 check_eq(host.sim.speed,GameClock.Speed.PAUSED)
 await online()
 host.new_city_dialog.open_real_world()
 check_eq(host.modal_depth,1)
 host.escape()
 check(not host.new_city_dialog.terrain_dialog.visible)
 check(host.new_city_dialog.visible)
 check_eq(host.modal_depth,1)
 check_eq(host.sim.city,original_active_city)
 host.new_city_dialog.accept_real_world(candidate)
 var accepted_preview_city := host.new_city_dialog.preview_city
 host.new_city_dialog.name_edit.text="Terrain handoff"
 host.new_city_dialog.name_edit.text_changed.emit("Terrain handoff")
 check_eq(host.sim.city,original_active_city,"preview metadata never mutates the active city")
 host.new_city_dialog.start()
 var shaped_city := host.sim.city
 check_eq(shaped_city,accepted_preview_city)
 check_eq(host.stage,GameHost.Stage.EDITING)
 check_eq(host.sim.speed,GameClock.Speed.PAUSED)
 check_eq(host.modal_depth,0)
 check_eq(host.editing_params.source,"real_world")
 check_eq(host.editing_params.baseline_base64,Marshalls.raw_to_base64(candidate.baseline))
 check_eq(host.toolbar.regenerate_button.text,"Reset imported terrain")
 check_eq(host.sim.city.name,"Terrain handoff")
func test_cancel_preserves_exact_active_save_and_rng() -> void:
 _active()
 var identity := host.sim.city
 var original_content := FileAccess.get_file_as_bytes(SAVE)
 var original_city := SaveFormat.encode_city(identity)
 var original_snapshot := host.sim.snapshot().duplicate(true)
 var original_rng := host.sim.rng.state()
 var original_path := host.save_path
 host.open_new_city_dialog()
 await online()
 host.new_city_dialog.open_real_world()
 host.new_city_dialog.terrain_dialog.download() # current Ready extraction remains cancellable
 host.escape()
 check_eq(host.modal_depth,1)
 host.escape()
 var cancelled_content := FileAccess.get_file_as_bytes(SAVE)
 check_eq(cancelled_content,original_content)
 check_eq(host.sim.city,identity)
 check_eq(SaveFormat.encode_city(identity),original_city)
 check_eq(host.sim.snapshot(),original_snapshot)
 check_eq(host.sim.rng.state(),original_rng)
 check_eq(host.save_path,original_path)
 check_eq(host.sim.speed,GameClock.Speed.FAST)
 check_eq(host.modal_depth,0)
func test_previous_imported_city_reentry_metadata_cancel_is_detached() -> void:
 host.open_new_city_dialog()
 host.new_city_dialog.accept_real_world(candidate)
 host.new_city_dialog.start()
 var identity := host.sim.city
 var encoded := SaveFormat.encode_city(identity)
 var snapshot := host.sim.snapshot().duplicate(true)
 var rng_state := host.sim.rng.state()
 host.open_new_city_dialog()
 check_eq(host.new_city_dialog.preview_city,null)
 check(host.new_city_dialog.terrain_importer.candidate.is_empty())
 host.new_city_dialog.name_edit.text="Must not reach active city"
 host.new_city_dialog.name_edit.text_changed.emit(host.new_city_dialog.name_edit.text)
 host.new_city_dialog.set_source("real_world")
 host.new_city_dialog.difficulty_button.select(2)
 host.new_city_dialog.difficulty_button.item_selected.emit(2)
 host.new_city_dialog.close()
 check_eq(host.sim.city,identity)
 check_eq(SaveFormat.encode_city(identity),encoded)
 check_eq(host.sim.snapshot(),snapshot)
 check_eq(host.sim.rng.state(),rng_state)
func test_desktop_focus_keeps_online_work_and_drops_gestures() -> void:
 _active()
 host.open_new_city_dialog()
 await online()
 host.new_city_dialog.open_real_world()
 var map := host.new_city_dialog.terrain_dialog.extent_map
 var contact := InputEventScreenTouch.new()
 contact.index=0; contact.position=Vector2(80,80); contact.pressed=true
 map._gui_input(contact)
 check(not map._touches.is_empty())
 host.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
 check(map._touches.is_empty())
 check(not host._application_suspended,"desktop focus never invokes mobile recovery policy")
 check(host.new_city_dialog.terrain_importer.is_online_fresh(),"switching windows keeps terrain work going")
 host.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
 check_eq(Engine.max_fps,0,"focus restores the full frame rate")
 check_eq(host.modal_depth,1)

func test_cancel_during_planning_drains_without_replacing_active_city() -> void:
 _active()
 var active := host.sim.city
 var encoded := SaveFormat.encode_city(active)
 var rng_state := host.sim.rng.state()
 var saved := FileAccess.get_file_as_bytes(SAVE)
 host.open_new_city_dialog()
 host.new_city_dialog.set_source("real_world")
 for frame in 16:
  fake.advance_clock(0); fake.serve_pending()
  await process_frame
 check(host.new_city_dialog.terrain_importer.is_online_fresh())
 await online()
 host.new_city_dialog.open_real_world()
 var child := host.new_city_dialog.terrain_dialog
 child.fields.side_km.value=0.5
 child.download()
 await process_frame
 check_eq(child._operation,"download")
 check_eq(host.modal_depth,1)
 host.escape()
 check(not child.visible)
 check(host.new_city_dialog.visible)
 check_eq(host.modal_depth,1)
 while not host.new_city_dialog.terrain_importer.is_drained(): await process_frame
 host.escape()
 check_eq(host.modal_depth,0)
 check_eq(host.sim.speed,GameClock.Speed.FAST)
 check_eq(host.sim.city,active)
 check_eq(SaveFormat.encode_city(active),encoded)
 check_eq(host.sim.rng.state(),rng_state)
 check_eq(FileAccess.get_file_as_bytes(SAVE),saved)

func test_damaged_imported_reset_has_touch_readable_reason() -> void:
 host.start_new_city(RealWorldManifest.editing_settings(candidate),candidate.city)
 host.editing_params.baseline_sha256="0".repeat(64)
 host.refresh_toolbar()
 check(host.toolbar.regenerate_button.disabled)
 check_eq(host.toolbar.regenerate_button.text,"Reset imported terrain")
 check("reset_reason_label" in host.toolbar,"disabled imported reset explains itself without hover")
 if not "reset_reason_label" in host.toolbar: return
 var label: Label=host.toolbar.get("reset_reason_label")
 check(label.visible)
 check(label.text.contains("baseline"))
 check_eq(label.autowrap_mode,TextServer.AUTOWRAP_WORD_SMART)
 host.toolbar.set_procedural_regeneration()
 check(not label.visible)
 check_eq(host.toolbar.regenerate_button.text,"Regenerate")

func test_imported_new_city_credits_preferred_mayor_without_rewriting_loaded_author() -> void:
 _active()
 var previous: City=host.sim.city
 var previous_bytes := SaveFormat.encode_city(previous)
 var previous_rng := host.sim.rng.state()
 var previous_state := host.sim.snapshot().duplicate(true)
 host.preferences["mayor_name"]="  River Mayor  "
 host.open_new_city_dialog()
 host.new_city_dialog.accept_real_world(candidate)
 check_eq(host.sim.rng.state(),previous_rng,"acceptance preserves previous simulation RNG")
 var paused_state := host.sim.snapshot().duplicate(true)
 paused_state["speed"]=previous_state["speed"]
 check_eq(paused_state,previous_state,"only established modal speed changes before handoff")
 host.new_city_dialog.start()
 check_eq(host.sim.city,candidate.city)
 check_eq(host.sim.city.mayor,"River Mayor","new imported Shape uses the preferred mayor")
 check_eq(SaveFormat.encode_city(previous),previous_bytes,"new imported creation never edits previous City")
 check(host.regenerate()!=null)
 check_eq(host.sim.city.mayor,"River Mayor","reset retains imported mayor")
 check(host.found_city())
 host.sim.set_speed(GameClock.Speed.PAUSED)
 check_eq(host.sim.city.mayor,"River Mayor","Found retains preferred mayor")
 host.save_path=SAVE
 check_eq(host.save_city(),OK)
 host.preferences["mayor_name"]="Another Mayor"
 check(host.load_city(SAVE))
 check_eq(host.sim.city.mayor,"River Mayor","native load retains stored author")
 check_eq(SaveFormat.encode_city(previous),previous_bytes)
