# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const Fake = preload("res://tests/real_world/fake_terrain_transport.gd")
const FakeMap = preload("res://tests/real_world/fake_map_backend.gd")
var dialog: NewCityDialog
var fake: RefCounted
var maps: RefCounted
func before_each() -> void:
 root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
 root.content_scale_factor=1.0
 root.size=Vector2i(1280,900)
 dialog=NewCityDialog.new()
 fake=Fake.new()
 fake.install_flat_objects()
 dialog.terrain_transport_factory=fake.make_transport
 maps=FakeMap.new()
 dialog.terrain_dialog.basemap.request_factory=maps.factory
 dialog.terrain_dialog.basemap.configure_disk("")
 dialog.terrain_dialog.place_search.request_factory=maps.factory
 dialog.terrain_dialog.map_config.request_factory=maps.factory
 dialog.terrain_dialog.map_config.configure_cache("")
 root.add_child(dialog)
func after_each() -> void:
 dialog.close()
 if dialog.terrain_importer!=null:
  dialog.terrain_importer.suspend()
  while not dialog.terrain_importer.is_drained(): await process_frame
 dialog.free()
 await process_frame
 fake=null
 maps=null
func pump(count: int=1) -> void:
 for i in count:
  fake.advance_clock(0)
  fake.serve_pending()
  await process_frame
func _open() -> void:
 dialog.open()
 # The online check starts only once Real-world terrain is chosen.
 dialog.set_source("real_world")
 await pump(16)
func _touch(map: TerrainExtentMap,index: int,point: Vector2,pressed: bool) -> void:
 var event := InputEventScreenTouch.new()
 event.index=index; event.position=point; event.pressed=pressed
 map._gui_input(event)
func _drag(map: TerrainExtentMap,index: int,point: Vector2) -> void:
 var event := InputEventScreenDrag.new()
 event.index=index; event.position=point
 map._gui_input(event)
func _click(control: Control) -> void:
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
 await process_frame
func _acquire() -> void:
 var child := dialog.terrain_dialog
 child.fields.side_km.value=0.5
 child.fields.longitude.value=-115.1367
 child.download()
 var until := Time.get_ticks_msec()+60000
 while not dialog.terrain_importer.is_ready() and not child._operation.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(dialog.terrain_importer.is_ready(),"production acquisition ready: "+child.progress_label.text)
func test_procedural_default_and_unavailable_retry() -> void:
 check_eq(dialog.source,"procedural")
 fake.deny_water_probe=true
 dialog.open()
 await pump(16)
 check(dialog.procedural_form.visible)
 check(not dialog.start_button.disabled)
 check(fake.starts.is_empty(),"procedural New City makes no network requests")
 check(not dialog.source_status.visible and not dialog.source_retry.visible,"online status belongs to Real-world terrain only")
 dialog.set_source("real_world")
 await pump(16)
 check(dialog.source_status.visible and dialog.source_retry.visible)
 check(dialog.source_status.text.begins_with("Unavailable"),"missing water probe refuses readiness: "+dialog.source_status.text)
 check(fake.starts.any(func(item: Dictionary) -> bool: return item.url.contains("terrarium")))
 check(fake.starts.any(func(item: Dictionary) -> bool: return item.url.contains("worldcover")))
 dialog.open_real_world()
 await pump(8)
 check(not dialog.terrain_dialog.visible,"unavailable source stays in New City")
 check(dialog.import_button.disabled)
 check(dialog.source_choice.get_item_text(1).contains("Online"))
 fake.deny_water_probe=false
 dialog.source_retry.pressed.emit()
 await pump(16)
 check(dialog.terrain_importer.is_online_fresh(),"parent Retry rechecks both services")
 check(not dialog.terrain_dialog.visible,"Retry does not asynchronously open a chooser")
 dialog.open_real_world()
 await pump(8)
 check(dialog.terrain_dialog.visible)
 check(not dialog.terrain_dialog.download_button.disabled,"fresh entry enables Download")
 check_eq(dialog.terrain_dialog.controls,TerrainImportContract.defaults().controls)
 check_eq(dialog.terrain_dialog.extent_map.selection,TerrainImportContract.defaults().selection)
 # Synchronous entry failure cannot leave the dialog stuck busy.
 dialog.terrain_importer.suspend()
 dialog.terrain_dialog.download()
 check_eq(dialog.terrain_dialog._operation,"")
 check(dialog.terrain_dialog.use_button.disabled)
 check(dialog.terrain_dialog.progress_label.text.contains("Unavailable"))
func test_view_zoom_independent_extent_and_rotated_handles() -> void:
 var map := TerrainExtentMap.new()
 root.add_child(map)
 map.size=Vector2(600,400)
 var selection: Dictionary=TerrainImportContract.defaults().selection
 selection.bearing=45.0
 map.set_selection(selection)
 map.fit_selection()
 var side_before_zoom: float=map.selection.side_km
 var wheel := InputEventMouseButton.new()
 wheel.pressed=true; wheel.button_index=MOUSE_BUTTON_WHEEL_UP; wheel.position=Vector2(90,90)
 map._gui_input(wheel)
 check_eq(map.selection.side_km,side_before_zoom)
 check_eq(map.selection.bearing,45.0)
 map.fit_selection()
 var corners := map.selection_corners()
 var center := map.geo_to_screen(Vector2(selection.longitude,selection.latitude))
 _touch(map,0,corners[0],true)
 check_eq(map._gesture,"resize")
 _drag(map,0,center+(corners[0]-center)*1.2)
 check(map.selection.side_km>side_before_zoom)
 check_eq(map.selection.bearing,45.0)
 _touch(map,0,corners[0],false)
 var before := map.selection.duplicate(true)
 var key := InputEventKey.new()
 key.pressed=true; key.keycode=KEY_RIGHT
 map._gui_input(key)
 check_eq(map.selection,before)
 check(map.view.center!=Vector2(before.longitude,before.latitude))
 map.free()
func test_second_finger_focus_loss_resize_cancel() -> void:
 var map := TerrainExtentMap.new()
 root.add_child(map)
 map.size=Vector2(600,400)
 map.fit_selection()
 var corner := map.selection_corners()[0]
 _touch(map,0,corner,true)
 check_eq(map._gesture,"resize")
 var before := map.selection.duplicate(true)
 _touch(map,1,corner+Vector2(100,0),true)
 check_eq(map._handle,-1)
 check_eq(map._gesture,"pinch")
 var original_zoom: int=map.view.zoom
 for step in range(1,31): _drag(map,1,corner+Vector2(100+step,0))
 check(map.view.zoom>original_zoom,"slow pinch accumulates zoom")
 _drag(map,0,corner-Vector2(30,0))
 check_eq(map.selection,before,"second finger cancels extent resizing")
 map.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
 check(map._gesture.is_empty() and map._touches.is_empty())
 _touch(map,0,corner,true)
 map.size=Vector2(400,300)
 check(map._gesture.is_empty() and map._touches.is_empty())
 map.free()
 await _open()
 dialog.open_real_world()
 await pump(8)
 for dimensions in [Vector2i(390,844),Vector2i(640,400),Vector2i(834,1194)]:
  root.size=dimensions
  dialog.apply_layout(true)
  await pump(8)
  var child := dialog.terrain_dialog
  check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(child.panel.get_global_rect()),"import panel fits "+str(dimensions))
  check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(child.cancel_button.get_global_rect()),"Cancel remains reachable")
  check(child.cancel_button.size.y>=44)
  check(child.use_button.size.y>=44)
  check(child.extent_map._touches.is_empty())
 # First press on an action belongs to the GUI, never to the map.
 await _click(dialog.terrain_dialog.cancel_button)
 check(not dialog.terrain_dialog.visible)
 check(dialog.visible)
 check(dialog.terrain_dialog.extent_map._gesture.is_empty())
 check(root.gui_get_focus_owner()==dialog.source_retry,"Cancel returns focus to the available Retry action")
func test_preview_revision_and_metadata_only_change() -> void:
 await _open()
 dialog.open_real_world()
 await _acquire()
 var child := dialog.terrain_dialog
 if not dialog.terrain_importer.is_ready(): return
 var old: City=dialog.terrain_importer.candidate.city
 var old_texture := child.preview_rect.texture
 check(old_texture!=null)
 check(child.diagnostics_label.text.contains("WorldCover water year 2021"))
 child.fields.exaggeration.value=2.0
 check(child.use_button.disabled,"control invalidates readiness immediately")
 var until := Time.get_ticks_msec()+60000
 while not dialog.terrain_importer.is_ready() and Time.get_ticks_msec()<until: await pump()
 check(dialog.terrain_importer.is_ready(),child.progress_label.text)
 check(dialog.terrain_importer.candidate.city!=old)
 check_eq(dialog.terrain_importer.candidate.controls.exaggeration,2.0)
 child.fit_relief()
 check(child.use_button.disabled)
 until=Time.get_ticks_msec()+60000
 while not dialog.terrain_importer.is_ready() and not child._operation.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(dialog.terrain_importer.is_ready(),"Fit completes through guarded rebuild")
 check_eq(child.fields.exaggeration.value,dialog.terrain_importer.candidate.controls.exaggeration)
 # Acceptance takes the exact guarded candidate; parent-only metadata edits retain it.
 var accepted_city: City=dialog.terrain_importer.candidate.city
 child._accept()
 check_eq(dialog.preview_city,accepted_city)
 dialog.name_edit.text="Imported metadata"
 dialog.name_edit.text_changed.emit(dialog.name_edit.text)
 dialog.difficulty_button.select(2)
 dialog.difficulty_button.item_selected.emit(2)
 dialog.year_button.select(2)
 dialog.year_button.item_selected.emit(2)
 check_eq(dialog.preview_city,accepted_city)
 check_eq(accepted_city.name,"Imported metadata")
 check_eq(accepted_city.difficulty,2)
 check_eq(accepted_city.founded_year,2000)
 dialog.open_real_world()
 await pump(20)
 # Selection edits keep the old preview visible but stale and unacceptably revised.
 old_texture=child.preview_rect.texture
 child.fields.side_km.value=1.0
 check(child.use_button.disabled)
 check_eq(child.preview_rect.texture,old_texture)
 child.fit_relief()
 check(child._operation.is_empty(),"Fit cannot use a different selection's packet")

func test_invalid_numeric_selection_cannot_rebuild_old_square() -> void:
 await _open()
 dialog.open_real_world()
 await _acquire()
 var child := dialog.terrain_dialog
 if not dialog.terrain_importer.is_ready(): return
 child.fields.latitude.value=82.75
 check(child.use_button.disabled)
 child.fields.exaggeration.value=1.5
 await pump(60)
 check_eq(child._rebuild_delay,-1.0,"invalid footprint never schedules old-square rebuild")
 check(child.use_button.disabled)
 check(child.download_button.disabled)

func test_ios_parent_scroll_never_claims_extent_map_contact() -> void:
 await _open()
 dialog.open_real_world()
 await pump(12)
 var child := dialog.terrain_dialog
 var chrome: Dictionary=child.panel.get_meta("window_chrome")
 var scroll: ScrollContainer=chrome.body_scroll
 IOSGestureScroll._install(scroll)
 scroll.ensure_control_visible(child.extent_map)
 await pump(6)
 var owner: IOSGestureScroll=scroll.get_node("IOSGestureScroll")
 var point := child.extent_map.get_global_rect().get_center()
 var event := InputEventScreenTouch.new()
 event.index=7; event.position=point; event.pressed=true
 root.push_input(event,true)
 check_eq(owner._finger,-1,"iOS parent leaves map touch to explicit gesture owner")
 check(child.extent_map._touches.has(7),"viewport contact reaches map")
 var scroll_before := scroll.scroll_vertical
 var drag := InputEventScreenDrag.new()
 drag.index=7; drag.position=point+Vector2(0,30); drag.relative=Vector2(0,30)
 root.push_input(drag,true)
 check_eq(scroll.scroll_vertical,scroll_before,"map drag never scrolls parent")
 event.pressed=false
 root.push_input(event,true)
 check(child.extent_map._touches.is_empty())
 check_eq(owner._finger,-1,"iOS parent retains no stale finger after map release")
 # A second contact on chrome belongs to that GUI control, not to map pinch.
 var chrome_contacts: Array=[]
 child.cancel_button.gui_input.connect(func(input: InputEvent) -> void:
  if input is InputEventScreenTouch and input.pressed: chrome_contacts.append(input.index))
 event.pressed=true
 root.push_input(event,true)
 check(child.extent_map._touches.has(7))
 var second := InputEventScreenTouch.new()
 second.index=8; second.position=child.cancel_button.get_global_rect().get_center(); second.pressed=true
 root.push_input(second,true)
 check_eq(chrome_contacts,[8],"chrome consumes its second-finger contact")
 check(child.extent_map._touches.is_empty(),"outside-map second touch cancels the old gesture")
 second.pressed=false
 root.push_input(second,true)
 event.pressed=false
 root.push_input(event,true)

func test_fit_displays_actual_source_multiplier_and_cancel_rejects_late_result() -> void:
 await _open()
 fake.install_ramp_png()
 dialog.open_real_world()
 var child := dialog.terrain_dialog
 child.fields.exaggeration.value=0.02
 await _acquire()
 if not dialog.terrain_importer.is_ready(): return
 var diagnostics: Dictionary=dialog.terrain_importer.candidate.diagnostics
 var expected := clampf(28.0*(500.0/128.0)*CityGeometry3D.HEIGHT/(diagnostics.source_max_metres-diagnostics.source_min_metres),0.001,20.0)
 child.fit_relief()
 var until := Time.get_ticks_msec()+60000
 while not dialog.terrain_importer.is_ready() and not child._operation.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(dialog.terrain_importer.is_ready(),"source-derived Fit rebuilds guarded preview")
 check(absf(child.fields.exaggeration.value-expected)<0.000000001,"numeric field displays actual fitted E")
 check(absf(child.controls.exaggeration-expected)<0.000000001,"control retains actual fitted E")
 await pump(3)
 check(absf(child.fields.exaggeration.get_line_edit().text.to_float()-child.fields.exaggeration.value)<0.0000000000006,"editable Fit text retains the exact selected multiplier")
 var exact_fit: float=child.fields.exaggeration.value
 var changes: Array=[]
 child.fields.exaggeration.value_changed.connect(func(value: float) -> void: changes.append(value))
 var ready_candidate: City=dialog.terrain_importer.candidate.city
 var ready_revision: int=child._revision
 # A rapid Tab traversal must not transiently commit native integer formatting.
 child.fields.exaggeration.get_line_edit().grab_focus()
 child.fields.latitude.get_line_edit().grab_focus()
 check_eq(changes.size(),0,"same-frame focus/blur emits no settings change")
 check_eq(child._revision,ready_revision,"same-frame focus/blur does not invalidate settings")
 await pump(3)
 check(dialog.terrain_importer.is_ready(),"same-frame focus/blur preserves completed preview")
 check_eq(dialog.terrain_importer.candidate.city,ready_candidate)

 child.fields.exaggeration.get_line_edit().grab_focus()
 await pump(3)
 check(absf(child.fields.exaggeration.get_line_edit().text.to_float()-exact_fit)<0.0000000000006,"focusing calculated Fit keeps precise text")
 child.fields.latitude.get_line_edit().grab_focus()
 await pump(3)
 check_eq(child.fields.exaggeration.value,exact_fit,"leaving calculated Fit preserves its exact multiplier")
 check_eq(changes.size(),0,"unchanged Fit focus/blur emits no transient setting change")
 check_eq(child._revision,ready_revision)
 check(dialog.terrain_importer.is_ready())
 check_eq(dialog.terrain_importer.candidate.city,ready_candidate)
 check_eq(dialog.terrain_importer.candidate.controls.exaggeration,child.fields.exaggeration.value)
 var saved: PackedByteArray=dialog.terrain_importer.candidate.baseline.duplicate()
 child.fit_relief()
 var fit_generation: int=child._generation
 var fit_revision: int=child._revision
 child.fields.exaggeration.get_line_edit().grab_focus()
 child.fields.latitude.get_line_edit().grab_focus()
 check_eq(changes.size(),0,"in-flight Fit focus/blur emits no settings change")
 check_eq(child._generation,fit_generation)
 check_eq(child._revision,fit_revision)
 check_eq(child._operation,"fit","in-flight Fit remains active through unchanged focus")
 child.close()
 while not dialog.terrain_importer.is_drained(): await pump()
 check(not child.visible)
 check(not dialog.terrain_importer.is_ready())
 check_eq(dialog.terrain_importer.candidate.baseline,saved,"late Fit cannot replace completed terrain after Cancel")

func _hold_backend_request() -> void:
 var until := Time.get_ticks_msec()+15000
 while fake.active==0 and Time.get_ticks_msec()<until: await process_frame
 check(fake.active>0,"real worker reaches the held backend")

func _view_tiles(child: RealWorldTerrainDialog) -> Array:
 var map := child.extent_map
 var c := map._pixel_xy(map._center_lon,map._center_lat)
 return TerrainBasemap.visible_tiles(c[0],c[1],int(map.view.zoom),map.size)

func _view_loaded(child: RealWorldTerrainDialog) -> bool:
 for tile in _view_tiles(child):
  if child.basemap.texture(tile.z,tile.x,tile.y)==null: return false
 return true

func _serve_view(child: RealWorldTerrainDialog) -> bool:
 var until := Time.get_ticks_msec()+5000
 while not _view_loaded(child) and Time.get_ticks_msec()<until:
  maps.serve()
  await pump()
 return _view_loaded(child)

func test_street_map_requests_view_tiles_on_open() -> void:
 await _open()
 check(maps.starts.is_empty(),"no street-map traffic before the chooser opens")
 var elevation_gets: int=fake.starts.filter(func(item: Dictionary) -> bool: return item.url.contains("terrarium") and not item.head_only).size()
 dialog.open_real_world()
 var child := dialog.terrain_dialog
 check(not maps.tile_starts().is_empty(),"view tiles are requested on open, without a settle delay")
 check(maps.peak_tile_active>0 and maps.peak_tile_active<=4,"bounded concurrent tile requests")
 var zoom := int(child.extent_map.view.zoom)
 for start in maps.tile_starts():
  var parts: PackedStringArray=start.url.trim_prefix("https://tile.openstreetmap.org/").trim_suffix(".png").split("/")
  check_eq(int(parts[0]),zoom,"only current-zoom tiles are requested")
  check(Array(start.headers).any(func(h: String) -> bool: return h.begins_with("User-Agent: SinCityDesertDreams/")),"identifying User-Agent")
 check(await _serve_view(child),"every visible street tile loads")
 await pump(4)
 check_eq(fake.starts.filter(func(item: Dictionary) -> bool: return item.url.contains("terrarium") and not item.head_only).size(),elevation_gets,"the map no longer downloads elevation")
 # The map does not depend on the elevation/water readiness check.
 dialog.terrain_importer._online_at=-60000
 var before: int=maps.tile_starts().size()
 child.extent_map.pan(Vector2(700,0))
 check(maps.tile_starts().size()>before,"expired terrain readiness still pans the street map")
 check(await _serve_view(child))

func test_street_map_keeps_loading_during_terrain_download() -> void:
 await _open()
 dialog.open_real_world()
 var child := dialog.terrain_dialog
 check(await _serve_view(child))
 child.fields.side_km.value=0.5
 child.download()
 await _hold_backend_request()
 var before: int=maps.tile_starts().size()
 child.extent_map.pan(Vector2(400,0))
 child.extent_map.zoom_by(1)
 check(maps.tile_starts().size()>before,"busy terrain does not hold map tiles")
 check(await _serve_view(child),"current view loads while terrain downloads")
 var until := Time.get_ticks_msec()+60000
 while not child._operation.is_empty() and Time.get_ticks_msec()<until: await pump()
 check(dialog.terrain_importer.is_ready(),"terrain still finishes")

func test_street_map_close_cancels_and_reopen_resumes() -> void:
 await _open()
 dialog.open_real_world()
 var child := dialog.terrain_dialog
 check(maps.active>0)
 child.close()
 check_eq(maps.active,0,"closing aborts in-flight tiles")
 check_eq(child.basemap.pending_count(),0)
 maps.serve()
 check_eq(child.basemap.loaded_count(),0,"aborted tiles never publish")
 dialog.open_real_world()
 var until := Time.get_ticks_msec()+5000
 while not child.visible and Time.get_ticks_msec()<until: await pump()
 check(child.visible)
 check(maps.active>0,"reopening requests the view again")
 check(await _serve_view(child))

func test_street_map_failure_keeps_selection_usable() -> void:
 maps.codes["tile.openstreetmap.org"]=503
 await _open()
 dialog.open_real_world()
 var child := dialog.terrain_dialog
 for i in 4:
  maps.serve()
  await pump()
 check_eq(child.basemap.loaded_count(),0)
 check(child.basemap.last_error().contains("503"),child.basemap.last_error())
 check(not child.download_button.disabled,"terrain download does not need the street map")
 var before: int=maps.tile_starts().size()
 child.extent_map.request_tiles()
 check_eq(maps.tile_starts().size(),before,"failed tiles are not retried every frame")

func test_basemap_tile_order_wrap_and_coarse_fallback() -> void:
 var tiles := TerrainBasemap.visible_tiles(256.0,256.0,1,Vector2(1200,300))
 var keys := tiles.map(func(t: Dictionary) -> String: return TerrainBasemap.key(t.z,t.x,t.y))
 check_eq(keys.size(),4,"wrapped columns are requested once")
 check(keys.has("1/0/0") and keys.has("1/1/1"))
 var centered := TerrainBasemap.visible_tiles(300.0,300.0,4,Vector2(512,320))
 check_eq([centered[0].x,centered[0].y],[1,1],"nearest-center tile first")
 check(TerrainBasemap.decode(PackedByteArray([1,2,3]))==null,"non-PNG rejected")
 var small := Image.create(64,64,false,Image.FORMAT_RGB8)
 check(TerrainBasemap.decode(small.save_png_to_buffer())==null,"wrong-size tile rejected")
 check(TerrainBasemap.decode(maps.tile_body)!=null)

func test_basemap_disk_cache_shows_stale_tiles_while_revalidating() -> void:
 var root_path := "user://map-cache-test"
 var now := [Time.get_unix_time_from_system()]
 var clock := func() -> float: return now[0]
 var first := TerrainBasemap.new()
 first.request_factory=maps.factory
 first.configure_disk(root_path)
 first.set_clock(clock)
 root.add_child(first)
 first.set_active(true)
 first.clear_disk()
 first.request_view(300.0,300.0,4,Vector2(200,200))
 maps.serve()
 check(first.texture(4,1,1)!=null)
 first.free()
 var starts: int=maps.tile_starts().size()
 var second := TerrainBasemap.new()
 second.request_factory=maps.factory
 second.configure_disk(root_path)
 second.set_clock(clock)
 root.add_child(second)
 second.set_active(true)
 second.request_view(300.0,300.0,4,Vector2(200,200))
 check(second.texture(4,1,1)!=null,"cached tile shows at once")
 check_eq(maps.tile_starts().size(),starts,"fresh cached tile is not refetched")
 second.free()
 now[0]+=8*86400.0
 var third := TerrainBasemap.new()
 third.request_factory=maps.factory
 third.configure_disk(root_path)
 third.set_clock(clock)
 root.add_child(third)
 third.set_active(true)
 third.request_view(300.0,300.0,4,Vector2(200,200))
 check(third.texture(4,1,1)!=null,"stale tile still shows")
 check(maps.tile_starts().size()>starts,"stale tile revalidates")
 maps.serve()
 third.clear_disk()
 check(DirAccess.get_directories_at(root_path).is_empty(),"cache clears every provider folder")
 third.free()

func test_place_search_moves_square_and_respects_policy() -> void:
 await _open()
 dialog.open_real_world()
 var child := dialog.terrain_dialog
 var now := [100000]
 child.place_search.set_clock(func() -> int: return now[0])
 maps.search_json=JSON.stringify([
  {"lat":"36.0395","lon":"-114.9817","display_name":"Henderson, Clark County, Nevada, United States","boundingbox":["35.9","36.1","-115.2","-114.8"]},
  {"lat":"-77.85","lon":"166.67","display_name":"McMurdo Station, Antarctica"},
  {"lat":"oops","lon":"1","display_name":"Broken"}])
 var side: float=child.fields.side_km.value
 child.search_field.text="  Henderson   NV "
 child.search_field.text_submitted.emit(child.search_field.text)
 check(child.search_button.disabled,"busy while searching")
 check_eq(maps.search_starts().size(),1)
 var url: String=maps.search_starts()[0].url
 check(url.contains("format=jsonv2") and url.contains("q=Henderson%20NV"),url)
 check(Array(maps.search_starts()[0].headers).any(func(h: String) -> bool: return h.begins_with("User-Agent: SinCityDesertDreams/")))
 check_eq(maps.search_starts().size(),1,"typing alone never searches")
 maps.serve()
 await pump()
 check_eq(child.search_results.get_child_count(),2,"malformed results are skipped")
 check(not child.search_button.disabled)
 (child.search_results.get_child(0) as Button).pressed.emit()
 check_eq(child.extent_map.selection.latitude,36.0395)
 check_eq(child.extent_map.selection.longitude,-114.9817)
 check(absf(child.fields.latitude.value-36.0395)<1e-6,"fields follow the moved square")
 check_eq(child.fields.side_km.value,side,"search keeps the square's size")
 check(child.search_status.text.contains("Henderson"))
 check(child.progress_label.text.contains("Selection changed"),"new square needs a new download")
 # Repeat query (any case/spacing) is answered from memory.
 child.search_field.text="henderson  nv"
 child.search_place()
 await pump()
 check_eq(maps.search_starts().size(),1,"repeat query answered from memory")
 check_eq(child.search_results.get_child_count(),2)
 # A distinct query waits for the one-second interval.
 child.search_field.text="Boulder City"
 child.search_place()
 await pump()
 check_eq(maps.search_starts().size(),1,"no second request within one second")
 now[0]+=TerrainMapConfig.NOMINATIM_MIN_INTERVAL_MS
 await pump()
 check_eq(maps.search_starts().size(),2,"queued search starts after the interval")
 maps.serve()
 await pump()
 (child.search_results.get_child(1) as Button).pressed.emit()
 check(child.search_status.text.contains("outside"),"out-of-range place is refused")
 check_eq(child.extent_map.selection.latitude,36.0395,"refused place leaves the square")
 maps.codes["nominatim"]=503
 now[0]+=TerrainMapConfig.NOMINATIM_MIN_INTERVAL_MS
 child.search_field.text="Searchlight"
 child.search_place()
 maps.serve()
 await pump()
 check(child.search_status.text.contains("Search unavailable"),child.search_status.text)
 check(not child.search_button.disabled)
 check(not TerrainPlaceSearch.parse("{}").ok)

func test_stale_entry_retry_never_opens_after_close_or_procedural_switch() -> void:
 await _open()
 dialog.terrain_importer._online_at=-60000
 dialog.open_real_world()
 check(not dialog.terrain_dialog.visible,"expired Ready cannot enter")
 check(dialog.import_button.disabled)
 dialog.set_source("procedural")
 await pump(16)
 check(not dialog.terrain_dialog.visible,"late readiness never overrides procedural choice")
 dialog.terrain_importer._online_at=-60000
 dialog.open_real_world()
 dialog.close()
 await pump(16)
 check(not dialog.visible and not dialog.terrain_dialog.visible,"late readiness never reopens cancelled New City")
# Sub-pixel footprints at world zoom must not reach engine triangulation.
func test_low_zoom_selection_skips_degenerate_fill() -> void:
 var map := TerrainExtentMap.new()
 root.add_child(map)
 map.size=Vector2(600,400)
 var selection: Dictionary=TerrainImportContract.defaults().selection
 selection.side_km=0.5
 map.set_selection(selection)
 map.set_view({"center":Vector2(selection.longitude,selection.latitude),"zoom":0})
 check(not TerrainExtentMap.fill_drawable(map.selection_corners()),"sub-pixel quad is not filled")
 map.set_view({"center":Vector2(selection.longitude,selection.latitude),"zoom":15})
 check(TerrainExtentMap.fill_drawable(map.selection_corners()),"visible quad keeps its fill")
 check(not TerrainExtentMap.fill_drawable(PackedVector2Array([Vector2(0,0),Vector2(10,0),Vector2(20,0),Vector2(30,0)])),"collinear quad is not filled")
 map.free()

const SWITCHED := {"schema":1,
 "tiles":{"url":"https://tiles.example.com/streets/{z}/{x}/{y}.png","hidpi_url":"https://tiles.example.com/streets/{z}/{x}/{y}@2x.png","max_zoom":18,"max_active":2,"attribution":"© Example Maps © OpenStreetMap contributors"},
 "search":{"url":"https://search.example.com/v1/search?text={query}&size={limit}&lang={lang}","format":"geojson","min_interval_ms":0,"attribution":"Search © Example"}}

func test_map_config_validation() -> void:
 var builtin := TerrainMapConfig.validate(TerrainMapConfig.DEFAULT)
 check(builtin.ok,builtin.error)
 check_eq(builtin.config,TerrainMapConfig.DEFAULT,"built-in default round-trips")
 check(TerrainMapConfig.validate(JSON.parse_string(JSON.stringify(SWITCHED))).ok,"JSON numbers are accepted")
 var bad := [
  ["schema 2",func(c: Dictionary) -> void: c.schema=2],
  ["http tiles",func(c: Dictionary) -> void: c.tiles.url="http://tiles.example.com/{z}/{x}/{y}.png"],
  ["missing {y}",func(c: Dictionary) -> void: c.tiles.url="https://tiles.example.com/{z}/{x}.png"],
  ["credential in host",func(c: Dictionary) -> void: c.tiles.url="https://user@tiles.example.com/{z}/{x}/{y}.png"],
  ["space in url",func(c: Dictionary) -> void: c.search.url="https://search.example.com/?q={query} x"],
  ["no attribution",func(c: Dictionary) -> void: c.tiles.attribution=""],
  ["no query",func(c: Dictionary) -> void: c.search.url="https://search.example.com/v1/search"],
  ["unknown format",func(c: Dictionary) -> void: c.search.format="xml"],
  ["zoom 30",func(c: Dictionary) -> void: c.tiles.max_zoom=30],
  ["fractional",func(c: Dictionary) -> void: c.tiles.max_active=1.5],
  ["enabled string",func(c: Dictionary) -> void: c.search.enabled="yes"]]
 for case in bad:
  var copy: Dictionary=SWITCHED.duplicate(true)
  case[1].call(copy)
  check(not TerrainMapConfig.validate(copy).ok,"refuses "+case[0])
 var off: Dictionary=SWITCHED.duplicate(true)
 off.tiles={"enabled":false}
 off.search={"enabled":false}
 check(TerrainMapConfig.validate(off).ok,"either service can be turned off without other fields")
 var fast: Dictionary=TerrainMapConfig.DEFAULT.duplicate(true)
 fast.search.min_interval_ms=0
 check_eq(TerrainMapConfig.validate(fast).config.search.min_interval_ms,TerrainMapConfig.NOMINATIM_MIN_INTERVAL_MS,"public Nominatim keeps one request per second")

func test_published_settings_switch_providers_without_update() -> void:
 maps.config_json=JSON.stringify(SWITCHED)
 maps.search_json=JSON.stringify({"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[-114.73,36.01]},"properties":{"label":"Hoover Dam, NV, USA"},"bbox":[-114.74,36.0,-114.72,36.02]}]})
 await _open()
 dialog.open_real_world()
 var child := dialog.terrain_dialog
 check_eq(maps.config_starts().size(),1,"settings are fetched when the chooser opens")
 check_eq(maps.config_starts()[0].url,TerrainMapConfig.config_url())
 check(not maps.tile_starts().is_empty(),"built-in provider is used at once, before settings arrive")
 maps.serve()
 await pump()
 check_eq(child.map_config.source,"published")
 check_eq(child.basemap.attribution(),SWITCHED.tiles.attribution)
 var switched: Array=maps.tile_starts("https://tiles.example.com/")
 check(not switched.is_empty(),"published tile provider is used")
 check(maps.active<=2,"published concurrency limit applies")
 check(await _serve_view(child),"published tiles load")
 child.search_field.text="Hoover Dam"
 child.search_place()
 var searches: Array=maps.starts.filter(func(item: Dictionary) -> bool: return item.url.begins_with("https://search.example.com/"))
 check_eq(searches.size(),1)
 check(searches[0].url.contains("text=Hoover%20Dam") and searches[0].url.contains("size=5"),searches[0].url)
 maps.serve()
 await pump()
 check_eq(child.search_results.get_child_count(),1,"GeoJSON results are read")
 check_eq(child.search_status.text,"Search © Example")
 # Settings are fetched at most hourly.
 child.close()
 dialog.open_real_world()
 var until := Time.get_ticks_msec()+5000
 while not child.visible and Time.get_ticks_msec()<until: await pump()
 check_eq(maps.config_starts().size(),1,"no refetch within the hour")

func test_invalid_published_settings_are_ignored_and_valid_ones_saved() -> void:
 var path := "user://map-config-test/map_config_v1.json"
 DirAccess.remove_absolute(path)
 var first := TerrainMapConfig.new()
 first.request_factory=maps.factory
 first.configure_cache(path)
 root.add_child(first)
 var invalid: Dictionary=SWITCHED.duplicate(true)
 invalid.tiles.url="http://insecure.example.com/{z}/{x}/{y}.png"
 maps.config_json=JSON.stringify(invalid)
 first.refresh(true)
 maps.serve()
 check_eq(first.source,"built-in","invalid file is refused as a whole")
 check_eq(first.config,TerrainMapConfig.DEFAULT)
 check(not FileAccess.file_exists(path))
 maps.config_json="{not json"
 first.refresh(true)
 maps.serve()
 check_eq(first.config,TerrainMapConfig.DEFAULT,"unreadable file is refused")
 maps.config_json=JSON.stringify(SWITCHED)
 var changes: Array = []
 first.changed.connect(func(value: Dictionary) -> void: changes.append(value))
 first.refresh(true)
 maps.serve()
 check_eq(changes.size(),1)
 check_eq(first.config.tiles.url,SWITCHED.tiles.url)
 first.free()
 var second := TerrainMapConfig.new()
 second.request_factory=maps.factory
 second.configure_cache(path)
 check_eq(second.source,"saved","last valid settings apply offline at once")
 check_eq(second.config.search.format,"geojson")
 second.free()
 DirAccess.remove_absolute(path)

func test_hidpi_screens_use_sharp_tiles_when_offered() -> void:
 var map := TerrainBasemap.new()
 map.request_factory=maps.factory
 map.configure_disk("")
 root.add_child(map)
 map.set_active(true)
 map.set_hidpi(true)
 map.request_view(300.0,300.0,4,Vector2(200,200))
 check(maps.tile_starts().size()>0 and maps.tile_starts().all(func(item: Dictionary) -> bool: return not item.url.ends_with("@2x.png")),"OpenStreetMap has no @2x tiles; standard tiles are used")
 map.configure_provider(TerrainMapConfig.validate(SWITCHED).config.tiles)
 map.request_view(300.0,300.0,4,Vector2(200,200))
 var sharp: Array=maps.tile_starts("https://tiles.example.com/")
 check(not sharp.is_empty() and sharp.all(func(item: Dictionary) -> bool: return item.url.ends_with("@2x.png")),"Retina uses the @2x template")
 check(map.uses_hidpi_tiles())
 maps.serve()
 check(map.texture(4,1,1)!=null and map.texture(4,1,1).get_width()==512,"512 px tiles decode")
 check(TerrainBasemap.decode(maps.tile_body,512)==null,"a 256 px body is refused where 512 px is expected")
 map.set_hidpi(false)
 check(map.texture(4,1,1)==null,"density change drops tiles of the other size")
 map.request_view(300.0,300.0,4,Vector2(200,200))
 check(maps.tile_starts("https://tiles.example.com/").any(func(item: Dictionary) -> bool: return item.url.ends_with("/4/1/1.png")),"standard screens use the standard template")
 map.free()

func test_search_can_be_turned_off_remotely() -> void:
 var off: Dictionary=SWITCHED.duplicate(true)
 off.search={"enabled":false}
 maps.config_json=JSON.stringify(off)
 await _open()
 dialog.open_real_world()
 var child := dialog.terrain_dialog
 maps.serve()
 await pump()
 check(not child.search_field.editable and child.search_button.disabled,"search controls are disabled")
 check(child.search_status.text.contains("turned off"))
 var before: int=maps.starts.size()
 child.search_field.text="Las Vegas"
 child.search_place()
 check(maps.starts.slice(before).all(func(item: Dictionary) -> bool: return item.url.ends_with(".png")),"no search request while off")

func test_geojson_search_formats() -> void:
 var photon := TerrainPlaceSearch.parse(JSON.stringify({"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[-114.41,36.21]},"properties":{"osm_id":1,"name":"Lake Mead","state":"Nevada","country":"United States","extent":[-114.84,36.43,-114.10,36.00]}}]}),"geojson")
 check(photon.ok)
 check_eq(photon.results[0].name,"Lake Mead, Nevada, United States")
 check_eq(photon.results[0].bounds,{"west":-114.84,"north":36.43,"east":-114.10,"south":36.00})
 var maptiler := TerrainPlaceSearch.parse(JSON.stringify({"type":"FeatureCollection","features":[{"type":"Feature","place_name":"Boulder City, Nevada, United States","bbox":[-114.9,35.9,-114.8,36.0],"geometry":{"type":"Point","coordinates":[-114.83,35.97]},"properties":{}},{"type":"Feature","geometry":{"type":"Polygon","coordinates":[]},"properties":{"name":"Area"}},{"type":"Feature","geometry":{"type":"Point","coordinates":[0,95]},"properties":{"name":"Bad"}}]}),"geojson")
 check_eq(maptiler.results.size(),1,"non-point and out-of-range features are skipped")
 check_eq(maptiler.results[0].latitude,35.97)
 check(not TerrainPlaceSearch.parse("[]","geojson").ok)
