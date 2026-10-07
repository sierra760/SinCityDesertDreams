# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const MainScene := preload("res://scenes/main.tscn")
const Fixtures := preload("res://tests/real_world/terrain_source_fixtures.gd")
const Fake := preload("res://tests/real_world/fake_terrain_transport.gd")
const SAVE := "user://saves/real-world-end-to-end.sc2d"
var host: GameHost
var fake: RefCounted
var auto_serve := true
var accepted: Dictionary

func before_each() -> void:
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
 root.content_scale_factor=1.0
 root.size=Vector2i(1440,1000)
 host=MainScene.instantiate()
 host.preferences_path="user://real-world-end-to-end.cfg"
 root.add_child(host)
 fake=Fake.new()
 fake.install_flat_objects()
 host.new_city_dialog.terrain_transport_factory=fake.make_transport
 auto_serve=true
 accepted={}
 await pump(4)

func after_each() -> void:
 host.new_city_dialog.close()
 if host.new_city_dialog.terrain_importer!=null:
  host.new_city_dialog.terrain_importer.suspend()
  while not host.new_city_dialog.terrain_importer.is_drained(): await process_frame
 host.free()
 DirAccess.remove_absolute(SAVE)
 await process_frame
 fake=null

func pump(count: int=1) -> void:
 for frame in count:
  fake.advance_clock(0)
  if auto_serve: fake.serve_pending()
  await process_frame

func click(control: Control) -> void:
 control.grab_focus()
 await pump(3)
 var scroll := UIFactory.report_scroll(control)
 if scroll!=null: scroll.ensure_control_visible(control)
 await pump(2)
 var point := control.get_global_rect().get_center()
 var motion := InputEventMouseMotion.new()
 motion.position=point; motion.global_position=point
 root.push_input(motion,true)
 var down := InputEventMouseButton.new()
 down.position=point; down.global_position=point
 down.button_index=MOUSE_BUTTON_LEFT; down.pressed=true
 root.push_input(down,true)
 var up := down.duplicate() as InputEventMouseButton
 up.pressed=false
 root.push_input(up,true)
 await pump(2)
 var until := Time.get_ticks_msec()+10000
 while host.loading_screen.visible and Time.get_ticks_msec()<until: await pump()
 check(not host.loading_screen.visible,"native action completes its loading lifecycle")

func open_import() -> RealWorldTerrainDialog:
 host.open_new_city_dialog()
 # The online check starts only once Real-world terrain is chosen.
 host.new_city_dialog.set_source("real_world")
 await pump(16)
 await click(host.new_city_dialog.import_button)
 check(host.new_city_dialog.terrain_dialog.visible,"native import button opens terrain selection")
 return host.new_city_dialog.terrain_dialog

func acquire(child: RealWorldTerrainDialog) -> bool:
 child.fields.side_km.value=0.5
 child.fields.longitude.value=-115.1367
 child.extent_map.fit_selection()
 await click(child.download_button)
 var until := Time.get_ticks_msec()+90000
 while not child.importer.is_ready() and not child._operation.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(child.importer.is_ready(),"actual decoder/conversion acquisition: "+child.progress_label.text)
 if not child.importer.is_ready(): return false
 accepted=child.importer.candidate.duplicate()
 return true

func terrain_bytes(city: City) -> PackedByteArray:
 var out: PackedByteArray=city.terrain_surface.vertices.duplicate()
 out.append_array(city.terrain_surface.water.to_byte_array())
 out.append_array(city.terrain_surface.salt)
 out.append_array(city.terrain_surface.feature)
 out.append_array(city.altitude.data.to_byte_array())
 out.append_array(city.terrain.data)
 out.append_array(city.flags.data)
 out.append_array(city.building.data)
 return out

func stable_snapshot() -> Dictionary:
 var value := host.sim.snapshot().duplicate(true)
 value.erase("accumulator") # established transient time accumulator only
 return value

# Guards against: stale/canceled online work accepted, metadata regenerates the
# candidate, or native editing/save/reset/found loses exact imported terrain.
func test_online_preview_cancel_retry_edit_save_offline_found() -> void:
 fake.deny_water_probe=true
 host.open_new_city_dialog()
 host.new_city_dialog.set_source("real_world")
 await pump(16)
 check(host.new_city_dialog.import_button.disabled)
 host.new_city_dialog.open_real_world()
 var child := host.new_city_dialog.terrain_dialog
 check(not child.visible,"failed service stays in New City")
 check(host.new_city_dialog.source_status.text.contains("Water service unavailable"),"blocked entry retains the failure detail until deliberate Retry")
 fake.deny_water_probe=false
 await click(host.new_city_dialog.source_retry)
 await pump(16)
 check(child.importer.is_online_fresh())
 check(not child.visible,"successful Retry never opens without a new entry action")
 await click(host.new_city_dialog.import_button)
 child.fields.side_km.value=0.5
 auto_serve=false
 await click(child.download_button)
 check(not child._operation.is_empty())
 var late_ids: Array=fake.nodes.keys()
 await click(child.cancel_button)
 check(not child.visible)
 while not child.importer.is_drained(): await process_frame
 for id in late_ids: fake.respond(id,{"code":200,"body":fake.objects.png})
 check(not child.importer.is_ready())
 auto_serve=true
 await click(host.new_city_dialog.source_retry)
 await pump(16)
 await click(host.new_city_dialog.import_button)
 await pump(16)
 if not await acquire(child): return
 var exact: City=accepted.city
 var bytes := terrain_bytes(exact)
 # Setting edits invalidate acceptance synchronously, before debounce rebuild.
 child.fields.trees.value=1
 check(child.use_button.disabled)
 child.fields.trees.value=0
 var until := Time.get_ticks_msec()+90000
 while not child.importer.is_ready() and Time.get_ticks_msec()<until: await pump()
 check(child.importer.is_ready())
 exact=child.importer.candidate.city
 accepted=child.importer.candidate.duplicate()
 bytes=terrain_bytes(exact)
 await click(child.use_button)
 check_eq(host.new_city_dialog.preview_city,exact)
 host.new_city_dialog.name_edit.text="Native terrain city"
 host.new_city_dialog.name_edit.text_changed.emit("Native terrain city")
 host.new_city_dialog.difficulty_button.select(2)
 host.new_city_dialog.difficulty_button.item_selected.emit(2)
 host.new_city_dialog.year_button.select(1)
 host.new_city_dialog.year_button.item_selected.emit(1)
 check_eq(host.new_city_dialog.preview_city,exact)
 await click(host.new_city_dialog.start_button)
 check_eq(host.sim.city,exact,"same accepted prebuilt object reaches Main")
 check_eq(host.stage,GameHost.Stage.EDITING)
 check_eq(terrain_bytes(host.sim.city),bytes)
 check_eq(host.sim.city.name,"Native terrain city")
 check_eq(host.sim.city.difficulty,2)
 check_eq(host.sim.city.founded_year,1950)
 check_eq(host.modal_depth,0)
 check_eq(host.sim.speed,GameClock.Speed.PAUSED)
 check(host.terrain_editor.raise(12,12).ok)
 check_ne(terrain_bytes(host.sim.city),bytes)
 host.save_path=SAVE
 check_eq(host.save_city(),OK)
 child.importer.suspend()
 while not child.importer.is_drained(): await process_frame
 check(host.new_city_dialog.terrain_cache.clear().ok)
 DirAccess.remove_absolute(TerrainTileCache.default_root())
 DirAccess.remove_absolute(TerrainTileCache.default_root().get_base_dir())
 var requests: int=fake.starts.size()
 check(host.load_city(SAVE))
 check_ne(terrain_bytes(host.sim.city),bytes,"native editing file retains deliberate edit")
 var started := Time.get_ticks_usec()
 host.refresh_toolbar()
 print("TOOLBAR_BASELINE_VALIDATE_US ",Time.get_ticks_usec()-started)
 await click(host.toolbar.regenerate_button)
 check_eq(terrain_bytes(host.sim.city),bytes,"offline reset restores exact baseline")
 check(host.found_city())
 host.sim.set_speed(GameClock.Speed.PAUSED)
 var before := SaveFormat.encode_city(host.sim.city)
 var snapshot := stable_snapshot()
 var rng_state := host.sim.rng.state()
 var funds := host.sim.city.funds
 var year: int=host.sim.city.founded_year
 var day := host.sim.city.day
 host.save_path=SAVE
 check_eq(host.save_city(),OK)
 check(host.load_city(SAVE))
 check_eq(SaveFormat.encode_city(host.sim.city),before)
 check_eq(stable_snapshot(),snapshot)
 check_eq(host.sim.rng.state(),rng_state)
 check_eq(host.sim.city.funds,funds)
 check_eq(host.sim.city.founded_year,year)
 check_eq(host.sim.city.day,day)
 check_eq(host.save_path,SAVE)
 check_eq(fake.starts.size(),requests,"completed edit/reset/found/load never requests a source")

# Guards against: reentry mutates previously handed-off City or leaks modal speed,
# save identity or late source publication into an unrelated/new session.
func test_previous_city_identity_speed_savepath_and_rng() -> void:
 var value := RealWorldTerrain.convert(Fixtures.packet(),Fixtures.controls(),Fixtures.metadata())
 check(value.ok)
 host.open_new_city_dialog()
 host.new_city_dialog.accept_real_world(value)
 host.new_city_dialog.start()
 check(host.found_city())
 host.sim.set_speed(GameClock.Speed.FAST)
 host.save_path=SAVE
 check_eq(host.save_city(),OK)
 var identity := host.sim.city
 var before := SaveFormat.encode_city(identity)
 var snapshot := stable_snapshot()
 var rng_state := host.sim.rng.state()
 var saved := FileAccess.get_file_as_bytes(SAVE)
 host.open_new_city_dialog()
 check_eq(host.new_city_dialog.preview_city,null)
 check_eq(host.sim.speed,GameClock.Speed.PAUSED)
 check_eq(host.modal_depth,1)
 host.new_city_dialog.name_edit.text="Must stay detached"
 host.new_city_dialog.name_edit.text_changed.emit("Must stay detached")
 host.new_city_dialog.set_source("real_world")
 await pump(16)
 host.new_city_dialog.open_real_world()
 await pump(4)
 auto_serve=false
 host.new_city_dialog.terrain_dialog.fields.side_km.value=0.5
 host.new_city_dialog.terrain_dialog.download()
 await pump(10)
 var ids: Array=fake.nodes.keys()
 host.escape()
 host.escape()
 check_eq(host.sim.speed,GameClock.Speed.FAST)
 check_eq(host.modal_depth,0)
 # Capture immediately; avoid advancing the restored live simulation in test time.
 check_eq(host.sim.city,identity)
 check_eq(SaveFormat.encode_city(identity),before)
 check_eq(stable_snapshot(),snapshot)
 check_eq(host.sim.rng.state(),rng_state)
 check_eq(host.save_path,SAVE)
 check_eq(FileAccess.get_file_as_bytes(SAVE),saved)
 host.open_new_city_dialog()
 for id in ids: fake.respond(id,{"code":200,"body":fake.objects.png})
 while not host.new_city_dialog.terrain_importer.is_drained(): await process_frame
 check_eq(host.new_city_dialog.preview_city,null)
 check(host.new_city_dialog.terrain_importer.candidate.is_empty())
 check_eq(host.sim.city,identity)
 check_eq(SaveFormat.encode_city(identity),before)
 check_eq(host.sim.rng.state(),rng_state)
 host.new_city_dialog.close()

# Guards against: optional corrupt provenance prevents valid native terrain load.
func test_corrupt_optional_origin_offline_load() -> void:
 var value := RealWorldTerrain.convert(Fixtures.packet(),Fixtures.controls(),Fixtures.metadata())
 check(value.ok)
 host.start_new_city(RealWorldManifest.editing_settings(value),value.city)
 var bytes := terrain_bytes(host.sim.city)
 host.save_path=SAVE
 check_eq(host.save_city(),OK)
 var document: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SAVE))
 document.city.terrain_origin={"schema_version":999,"url":"https://invalid.example/source"}
 document.generator.terrain_origin=["invalid"]
 FileAccess.open(SAVE,FileAccess.WRITE).store_string(JSON.stringify(document))
 check(host.load_city(SAVE))
 check_eq(host.sim.city.terrain_origin,{})
 check_eq(terrain_bytes(host.sim.city),bytes)
 check(host.regenerate()!=null)
 check_eq(terrain_bytes(host.sim.city),bytes)
 check(host.found_city())
 check_eq(fake.starts.size(),0)

# Guards against: completed native terrain silently acquires on editing/reset/play.
func test_completed_city_never_recontacts_sources() -> void:
 var value := RealWorldTerrain.convert(Fixtures.conversion_packet("provenance"),Fixtures.controls({"tree_seed":-9223372036854775807-1}),Fixtures.metadata())
 check(value.ok)
 host.start_new_city(RealWorldManifest.editing_settings(value),value.city)
 var bytes := terrain_bytes(host.sim.city)
 host.save_path=SAVE
 check_eq(host.save_city(),OK)
 for iteration in 2:
  check(host.load_city(SAVE))
  check_eq(host.editing_params.seed,-9223372036854775807-1)
  check(host.regenerate()!=null)
  check_eq(terrain_bytes(host.sim.city),bytes)
  check_eq(host.save_city(),OK)
 check(host.found_city())
 host.sim.set_speed(GameClock.Speed.PAUSED)
 var rng_state := host.sim.rng.state()
 check_eq(host.save_city(),OK)
 check(host.load_city(SAVE))
 check_eq(host.sim.rng.state(),rng_state)
 check_eq(fake.starts.size(),0)

# Guards against: fractional exaggeration is stored but rounded to an integer in
# the displayed/editable field, so subsequent submission can change the value.
func test_fractional_exaggeration_display_retains_selected_value() -> void:
 var child := await open_import()
 for value in [0.001,0.1,0.25,1.1,1.234567890123]:
  child.fields.exaggeration.value=value
  await pump(3)
  var shown: String=child.fields.exaggeration.get_line_edit().text
  check(absf(shown.to_float()-child.fields.exaggeration.value)<0.0000000000006,"fractional field displays actual selected value: "+shown)
  check_eq(child.controls.exaggeration,child.fields.exaggeration.value)
 child.fields.exaggeration.get_line_edit().text="0.25"
 child.fields.exaggeration.get_line_edit().text_submitted.emit("0.25")
 await pump(3)
 check_eq(child.fields.exaggeration.value,0.25)
 check_eq(child.fields.exaggeration.get_line_edit().text.to_float(),0.25)
 # Native focus and unchanged commits also reformat without value_changed.
 var edit: LineEdit=child.fields.exaggeration.get_line_edit()
 edit.grab_focus()
 await pump(3)
 check_eq(edit.text.to_float(),0.25,"focusing unchanged fractional value retains editable text")
 edit.text_submitted.emit("0.25")
 await pump(3)
 check_eq(edit.text.to_float(),0.25,"unchanged submission retains editable text")
 child.fields.latitude.get_line_edit().grab_focus()
 await pump(3)
 check_eq(child.fields.exaggeration.value,0.25,"leaving field must not commit rounded native display")
 await click(child.fields.exaggeration.get_line_edit())
 edit.text="0.35"
 edit.text_changed.emit("0.35")
 await click(child.fields.latitude.get_line_edit())
 await pump(3)
 check_eq(child.fields.exaggeration.value,0.35,"normal typed blur commits the user value")
 check_eq(edit.text.to_float(),0.35)
 await click(child.fields.exaggeration.get_line_edit())
 var rect: Rect2=child.fields.exaggeration.get_global_rect()
 for direction in [1,-1]:
  var point := Vector2(rect.end.x-4,rect.position.y+rect.size.y*(0.25 if direction==1 else 0.75))
  var press := InputEventMouseButton.new()
  press.position=point;press.global_position=point;press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
  root.push_input(press,true)
  var release := press.duplicate() as InputEventMouseButton;release.pressed=false
  root.push_input(release,true)
  await pump(3)
  var expected := 0.351 if direction==1 else 0.35
  check(absf(child.fields.exaggeration.value-expected)<0.0000000000006,"visible arrow changes exaggeration by 0.001")
  check(absf(edit.text.to_float()-expected)<0.0000000000006,"visible arrow displays its actual useful increment")

# Guards against: focus-follow sends newly opened long notices to the bottom;
# keyboard readers must begin at the first credit and retain native scrolling.
func test_sources_notice_opens_at_top_and_keyboard_scrolls() -> void:
 var child := await open_import()
 await click(child.source_button)
 var notice := child.sources_dialog
 var scroll: ScrollContainer=notice.panel.get_meta("window_chrome").body_scroll
 await pump(12)
 check_eq(scroll.scroll_vertical,0,"new source notice starts at its first credit after layout/focus settle")
 var down := InputEventKey.new()
 down.keycode=KEY_PAGEDOWN;down.pressed=true
 root.push_input(down,true)
 var up := down.duplicate() as InputEventKey;up.pressed=false
 root.push_input(up,true)
 await pump(4)
 check(scroll.scroll_vertical>0,"keyboard Page Down scrolls long source credits")
 await click(notice.done_button)
 await click(child.source_button)
 await pump(12)
 check_eq(scroll.scroll_vertical,0,"reopened source notice starts at top")
 check(notice.is_ancestor_of(root.gui_get_focus_owner()),"keyboard focus remains within the source notice")
