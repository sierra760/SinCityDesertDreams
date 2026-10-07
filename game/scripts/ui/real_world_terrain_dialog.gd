# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name RealWorldTerrainDialog
extends Control
signal accepted(candidate: Dictionary)
signal closed
signal data_sources_requested

var sources_dialog: TerrainSourcesDialog
var importer: RealWorldImporter
var extent_map: TerrainExtentMap
var basemap: TerrainBasemap
var place_search: TerrainPlaceSearch
var map_config: TerrainMapConfig
var search_field: LineEdit
var search_button: Button
var search_status: Label
var search_results: VBoxContainer
var panel: PanelContainer
var fields := {}
var controls: Dictionary=TerrainImportContract.defaults().controls
var metadata := {}
var availability_label: Label
var progress_label: Label
var diagnostics_label: Label
var preview_rect: TextureRect
var retry_button: Button
var download_button: Button
var fit_button: Button
var use_button: Button
var cancel_button: Button
var source_button: Button
var clear_button: Button
var smoothing: OptionButton
var water_mode: OptionButton
var preserve_narrow: CheckBox
var selection_grid: GridContainer
var control_grid: GridContainer
var _operation := ""
var _generation := -1
var _revision := 0
var _fit_revision := -1
var _rebuild_delay := -1.0
var _packet_selection := {}
var _downloading_selection := {}
var _syncing := false
var _online := false
var _selection_valid := true
var _exaggeration_edit_dirty := false
var _exaggeration_typed_text := ""
var _exaggeration_typed_caret := 0

func _init() -> void:
 name="RealWorldTerrainDialog"
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter=Control.MOUSE_FILTER_STOP
 var shade := ColorRect.new()
 shade.color=Color(0,0,0,0.35)
 shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 add_child(shade)
 var chrome := UIFactory.make_window_chrome("Real-world terrain")
 panel=chrome.root
 panel.set_meta("preferred_size",Vector2(820,720))
 panel.set_anchors_preset(Control.PRESET_CENTER)
 panel.offset_left=-410; panel.offset_right=410
 panel.offset_top=-360; panel.offset_bottom=360
 add_child(panel)
 chrome.close_button.pressed.connect(close)
 WindowDrag.enable(chrome.title_bar,panel)
 var body: VBoxContainer=chrome.body
 availability_label=_label(body,"Checking connection…")
 var actions := UIFactory.WrappingActions.new()
 body.add_child(actions)
 retry_button=_button(actions,"Retry connection",func() -> void:
  if importer!=null: importer.set_visible(true); importer.check_online(true))
 clear_button=_button(actions,"Clear terrain cache",_clear_cache)
 source_button=_button(actions,"Data sources",func() -> void:
  sources_dialog.open()
  data_sources_requested.emit())
 _label(body,"Elevation: Mapzen / Joerd terrain providers · Water: ESA WorldCover 2021 v200 (CC BY 4.0) · Map: © OpenStreetMap contributors")
 _label(body,"Search for a place, or drag the square center to move it and a corner to resize it. Arrow keys pan; + / − zoom; F fits the selection.")
 var search_row := HBoxContainer.new()
 search_row.add_theme_constant_override("separation",8)
 body.add_child(search_row)
 search_field=LineEdit.new()
 search_field.name="PlaceSearch"
 search_field.placeholder_text="Search for a place"
 search_field.custom_minimum_size.y=44
 search_field.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 search_field.clear_button_enabled=true
 search_field.max_length=TerrainPlaceSearch.MAX_QUERY
 search_field.select_all_on_focus=true
 search_row.add_child(search_field)
 search_field.text_submitted.connect(func(_text: String) -> void: search_place())
 search_button=_button(search_row,"Search",search_place)
 search_status=_label(body,"")
 search_results=VBoxContainer.new()
 search_results.name="PlaceResults"
 body.add_child(search_results)
 basemap=TerrainBasemap.new()
 add_child(basemap)
 place_search=TerrainPlaceSearch.new()
 add_child(place_search)
 map_config=TerrainMapConfig.new()
 add_child(map_config)
 map_config.changed.connect(apply_map_config)
 place_search.results_ready.connect(_places_found)
 place_search.failed.connect(_place_search_failed)
 extent_map=TerrainExtentMap.new()
 extent_map.basemap=basemap
 body.add_child(extent_map)
 extent_map.selection_changed.connect(_selection_from_map)
 apply_map_config(map_config.config)
 var navigation := UIFactory.WrappingActions.new()
 body.add_child(navigation)
 _button(navigation,"West",func() -> void: extent_map.pan(Vector2(96,0)))
 _button(navigation,"East",func() -> void: extent_map.pan(Vector2(-96,0)))
 _button(navigation,"North",func() -> void: extent_map.pan(Vector2(0,96)))
 _button(navigation,"South",func() -> void: extent_map.pan(Vector2(0,-96)))
 _button(navigation,"−",func() -> void: extent_map.zoom_by(-1))
 _button(navigation,"+",func() -> void: extent_map.zoom_by(1))
 _button(navigation,"Fit selection",extent_map.fit_selection)
 selection_grid=GridContainer.new()
 selection_grid.columns=4
 body.add_child(selection_grid)
 _number(selection_grid,"latitude","Latitude",-60,82.75,0.0001,36.1699,_selection_from_fields)
 _number(selection_grid,"longitude","Longitude",-180,180,0.0001,-115.1398,_selection_from_fields)
 _number(selection_grid,"side_km","Side (km)",0.5,128,0.1,8,_selection_from_fields)
 _number(selection_grid,"bearing","Bearing (°)",0,359,1,0,_selection_from_fields)
 control_grid=GridContainer.new()
 control_grid.columns=2
 body.add_child(control_grid)
 _number(control_grid,"exaggeration","Vertical exaggeration",0.001,20,0.000000000001,1,_controls_changed)
 fields.exaggeration.custom_arrow_step=0.001
 fields.exaggeration.value_changed.connect(func(_value: float) -> void: _exaggeration_committed())
 var exaggeration_edit: LineEdit=fields.exaggeration.get_line_edit()
 # Match the native deferred edit callbacks, restoring precision between toggles.
 exaggeration_edit.editing_toggled.connect(_exaggeration_editing_toggled,CONNECT_DEFERRED)
 exaggeration_edit.text_submitted.connect(func(_text: String) -> void: _exaggeration_committed(),CONNECT_DEFERRED)
 exaggeration_edit.text_changed.connect(func(text: String) -> void:
  _exaggeration_edit_dirty=true
  _exaggeration_typed_text=text
  _exaggeration_typed_caret=exaggeration_edit.caret_column)
 _sync_exaggeration_display.call_deferred()
 _number(control_grid,"trees","Trees (%)",0,100,1,0,_controls_changed)
 var smooth_box := VBoxContainer.new()
 control_grid.add_child(smooth_box)
 _label(smooth_box,"Smoothing passes")
 smoothing=OptionButton.new()
 smoothing.custom_minimum_size.y=44
 for n in [0,1,3]: smoothing.add_item(str(n),n)
 smooth_box.add_child(smoothing)
 smoothing.item_selected.connect(func(_i: int) -> void: _controls_changed())
 var water_box := VBoxContainer.new()
 control_grid.add_child(water_box)
 _label(water_box,"Water type")
 water_mode=OptionButton.new()
 water_mode.custom_minimum_size.y=44
 for value in ["Automatic","Freshwater","Sea"]: water_mode.add_item(value)
 water_box.add_child(water_mode)
 water_mode.item_selected.connect(func(_i: int) -> void: _controls_changed())
 preserve_narrow=CheckBox.new()
 preserve_narrow.custom_minimum_size.y=44
 preserve_narrow.text="Preserve narrow water"
 preserve_narrow.button_pressed=true
 body.add_child(preserve_narrow)
 preserve_narrow.toggled.connect(func(_on: bool) -> void: _controls_changed())
 var conversion_actions := UIFactory.WrappingActions.new()
 body.add_child(conversion_actions)
 download_button=_button(conversion_actions,"Download terrain",download)
 fit_button=_button(conversion_actions,"Fit relief",fit_relief)
 progress_label=_label(body,"Choose a square, then download its terrain.")
 preview_rect=TextureRect.new()
 preview_rect.custom_minimum_size=Vector2(128,128)
 preview_rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
 preview_rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
 preview_rect.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 body.add_child(preview_rect)
 diagnostics_label=_label(body,"The playable preview appears here. Elevation and water are adapted to the city's terrain grid.")
 cancel_button=_button(chrome.actions,"Cancel",close)
 use_button=UIFactory.make_primary_button("Use terrain")
 chrome.actions.add_child(use_button)
 use_button.pressed.connect(_accept)
 sources_dialog=TerrainSourcesDialog.new()
 add_child(sources_dialog)
 visible=false
 resized.connect(func() -> void: apply_layout(size.x<700))
 _update_actions()

func _label(parent: Node,text: String) -> Label:
 var label := UIFactory.make_label(text,UITheme.FONT_SMALL,UITheme.TEXT_MUTED)
 label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 parent.add_child(label)
 return label
func _button(parent: Node,text: String,action: Callable) -> Button:
 var button := UIFactory.make_button(text)
 parent.add_child(button)
 button.pressed.connect(action)
 return button
func _number(parent: Node,key: String,title: String,lo: float,hi: float,step: float,value: float,action: Callable) -> void:
 var box := VBoxContainer.new()
 box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 parent.add_child(box)
 _label(box,title)
 var field := SpinBox.new()
 field.custom_minimum_size.y=44
 field.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 field.min_value=lo; field.max_value=hi; field.step=step; field.value=value
 box.add_child(field)
 fields[key]=field
 field.value_changed.connect(func(_value: float) -> void: action.call())

func _exaggeration_editing_toggled(editing: bool) -> void:
 # Native formatting runs first. Keep any user input from this same frame.
 if editing and _exaggeration_edit_dirty:
  var edit: LineEdit=fields.exaggeration.get_line_edit()
  edit.text=_exaggeration_typed_text
  edit.caret_column=_exaggeration_typed_caret
  return
 _exaggeration_committed()

func _exaggeration_committed() -> void:
 _exaggeration_edit_dirty=false
 _apply_exaggeration_display()
 _sync_exaggeration_display.call_deferred()

func _sync_exaggeration_display() -> void:
 # Let native formatting finish; a bound callback disconnects on dialog free.
 if is_inside_tree() and not get_tree().process_frame.is_connected(_apply_exaggeration_display):
  get_tree().process_frame.connect(_apply_exaggeration_display,CONNECT_ONE_SHOT)

func _apply_exaggeration_display() -> void:
 if _exaggeration_edit_dirty: return # Preserve text the user has not committed.
 # SpinBox formats very small steps as integers; show the full Fit value.
 var edit: LineEdit=fields.exaggeration.get_line_edit()
 var text := String.num(fields.exaggeration.value,12)
 if edit.text==text: return
 var caret := edit.caret_column
 var selected := edit.has_selection()
 var all_selected := selected and edit.get_selected_text()==edit.text
 var start := edit.get_selection_from_column() if selected else 0
 var end := edit.get_selection_to_column() if selected else 0
 edit.text=text
 edit.caret_column=caret
 if all_selected: edit.select_all()
 elif selected: edit.select(start,end)

func bind(value: RealWorldImporter) -> void:
 if importer==value: return
 if importer!=null:
  importer.availability_changed.disconnect(_availability)
  importer.progress_changed.disconnect(_progress)
  importer.candidate_ready.disconnect(_candidate_ready)
  importer.failed.disconnect(_failed)
  importer.relief_fitted.disconnect(_relief_fitted)
 importer=value
 importer.availability_changed.connect(_availability)
 importer.progress_changed.connect(_progress)
 importer.candidate_ready.connect(_candidate_ready)
 importer.failed.connect(_failed)
 importer.relief_fitted.connect(_relief_fitted)

func open(values: Dictionary) -> void:
 metadata=values.duplicate(true)
 visible=true
 if importer!=null: importer.set_visible(true)
 extent_map.fit_selection()
 # The street map is independent of the elevation/water readiness checks.
 basemap.set_active(true)
 # Published provider settings apply when they arrive; until then the last
 # valid copy (or the built-in default) is already in use.
 map_config.refresh()
 if not _packet_selection.is_empty(): _rebuild_delay=0.25
 _update_actions()
 UIFactory.contain_modal_focus(self,retry_button if not _online else download_button)
 _ensure_focus_visible.call_deferred()
func close() -> void:
 if not visible: return
 sources_dialog.close()
 cancel_work()
 basemap.set_active(false)
 place_search.cancel()
 map_config.cancel()
 if importer!=null: importer.set_visible(false)
 visible=false
 closed.emit()
func cancel_work() -> void:
 _revision+=1
 _fit_revision=-1
 _operation=""
 _generation=-1
 _rebuild_delay=-1
 extent_map.cancel_gesture()
 if importer!=null: importer.cancel()
 _update_actions()
func reset_session() -> void:
 cancel_work()
 _packet_selection={}
 _downloading_selection={}
 preview_rect.texture=null
 diagnostics_label.text="The playable preview appears here. Elevation and water are adapted to the city's terrain grid."
 progress_label.text="Choose a square, then download its terrain."
 _clear_places(place_search.attribution())
func suspend() -> void:
 sources_dialog.close()
 cancel_work()
 basemap.set_active(false)
 place_search.cancel()
 map_config.cancel()
 if importer!=null: importer.suspend()
func resume() -> void:
 if importer!=null:
  importer.set_visible(true)
  importer.check_online(true)
 if visible:
  basemap.set_active(true)
  extent_map.request_tiles()
  map_config.refresh()
func apply_layout(compact: bool) -> void:
 selection_grid.columns=2 if compact else 4
 control_grid.columns=1 if size.x<420 else 2
 extent_map.custom_minimum_size.y=minf(260.0,maxf(180.0,size.y*0.5))
 extent_map.cancel_gesture()

func _selection_from_map(value: Dictionary) -> void:
 _selection_valid=true
 _syncing=true
 for key in ["latitude","longitude","side_km","bearing"]: fields[key].set_value_no_signal(value[key])
 _syncing=false
 _invalidate()
 progress_label.text="Selection changed. Download terrain for this square."
func _selection_from_fields() -> void:
 if _syncing: return
 var value := {}
 for key in ["latitude","longitude","side_km","bearing"]: value[key]=fields[key].value
 _invalidate()
 var valid := TerrainGeography.validate_selection(value)
 _selection_valid=valid.ok
 if not valid.ok:
  progress_label.text=valid.error
  download_button.disabled=true
  return
 extent_map.set_selection(value)
 progress_label.text="Selection changed. Download terrain for this square."
func _controls_changed() -> void:
 if _syncing: return
 controls.exaggeration=fields.exaggeration.value
 controls.trees=int(fields.trees.value)
 controls.smoothing_passes=smoothing.get_selected_id()
 controls.water_mode=["auto","fresh","sea"][water_mode.selected]
 controls.preserve_narrow=preserve_narrow.button_pressed
 _invalidate()
 if _selection_valid and _packet_selection==extent_map.selection and not _packet_selection.is_empty():
  _rebuild_delay=0.25
  progress_label.text="Preview settings changed."
 else: progress_label.text="Download terrain for this square first."
func _invalidate() -> void:
 _revision+=1
 _fit_revision=-1
 _operation=""
 _generation=-1
 _rebuild_delay=-1
 if importer!=null: importer.invalidate_settings()
 _update_actions()
func _process(delta: float) -> void:
 if not visible or importer==null: return
 if _online and not importer.is_online_fresh():
  _online=false
  # An expired check repeats on its own; only a failed check needs Retry.
  availability_label.text="Checking…" if importer.recheck_if_expired() else "Unavailable · Select Retry connection."
  _update_actions()
 if _rebuild_delay>=0:
  _rebuild_delay-=delta
  if _rebuild_delay<0 and importer.is_online_fresh(): _rebuild()
func download() -> void:
 if importer==null: return
 _invalidate()
 var value := {}
 for key in ["latitude","longitude","side_km","bearing"]: value[key]=fields[key].value
 var valid := TerrainGeography.validate_selection(value)
 _selection_valid=valid.ok
 if not valid.ok:
  progress_label.text=valid.error
  return
 extent_map.set_selection(value)
 _downloading_selection=value.duplicate(true)
 _operation="download"
 progress_label.text="Planning terrain…"
 var generation := importer.download(value,controls,metadata)
 if _operation=="download": _generation=generation
 _update_actions()
func _rebuild() -> void:
 if importer==null or not _selection_valid or _packet_selection!=extent_map.selection: return
 _operation="rebuild"
 _generation=-1
 var generation := importer.rebuild(controls,metadata)
 if _operation=="rebuild": _generation=generation
 _update_actions()
func fit_relief() -> void:
 if importer==null or not _selection_valid or _packet_selection.is_empty() or _packet_selection!=extent_map.selection: return
 _invalidate()
 _operation="fit"
 _fit_revision=_revision
 var generation := importer.fit_relief(controls)
 if _operation=="fit": _generation=generation
 _update_actions()
func _relief_fitted(generation: int,result: Dictionary) -> void:
 if not visible or _operation!="fit" or generation!=_generation or _fit_revision!=_revision: return
 fields.exaggeration.set_value_no_signal(float(result.exaggeration))
 _sync_exaggeration_display.call_deferred()
 # Keep the 12-decimal numeric display and the subsequent build identical.
 controls.exaggeration=fields.exaggeration.value
 _operation=""
 progress_label.text="Fitted exaggeration %.3f; rebuilding preview."%controls.exaggeration
 _rebuild()
func _availability(status: String,detail: String) -> void:
 _online=status=="Online"
 availability_label.text=("Ready" if _online else "Checking" if status=="Checking" else "Unavailable")+" · "+detail
 if visible: _ensure_focus_visible.call_deferred()
 _update_actions()
func _progress(stage: String,fraction: float,detail: String) -> void:
 if visible and not _operation.is_empty(): progress_label.text="%s · %d%% · %s"%[stage,roundi(fraction*100),detail]
func _failed(generation: int,detail: String) -> void:
 if not visible or _operation.is_empty() or (_generation!=-1 and generation!=_generation): return
 _operation=""
 _fit_revision=-1
 progress_label.text="Unavailable preview · "+detail+". Retry connection or download again."
 _update_actions()
func _candidate_ready(generation: int,candidate: Dictionary) -> void:
 if not visible or _operation not in ["download","rebuild"] or generation!=_generation or not importer.is_ready(): return
 if _operation=="download": _packet_selection=_downloading_selection.duplicate(true)
 _operation=""
 preview_rect.texture=ImageTexture.create_from_image(NewCityDialog.preview_image(candidate.city))
 diagnostics_label.text=_diagnostics(candidate.diagnostics)
 progress_label.text="Ready · preview matches these settings."
 _update_actions()

## Switch street-map and search providers to validated settings.
func apply_map_config(value: Dictionary) -> void:
 basemap.configure_provider(value.tiles)
 place_search.configure_provider(value.search)
 var searchable := place_search.enabled()
 search_field.editable=searchable
 search_button.disabled=not searchable
 search_field.placeholder_text="Search for a place" if searchable else "Place search is unavailable"
 _clear_places(place_search.attribution() if searchable else "Place search is turned off. Drag the map or type coordinates instead.")
 extent_map.request_tiles()
 extent_map.queue_redraw()

## Search on explicit submit; results list below the field.
func search_place() -> void:
 if not place_search.enabled(): return
 var query := TerrainPlaceSearch.normalize(search_field.text)
 if query.length()<2:
  _clear_places("Type a place name to search.")
  return
 _clear_places("Searching for “%s”…"%query)
 search_button.disabled=true
 place_search.search(query)
func _places_found(query: String,results: Array) -> void:
 if not visible or query!=TerrainPlaceSearch.normalize(search_field.text): return
 search_button.disabled=not place_search.enabled()
 if results.is_empty():
  _clear_places("No places found for “%s”."%query)
  return
 _clear_places(place_search.attribution())
 for result in results:
  var button := UIFactory.make_button(result.name,result.name)
  button.alignment=HORIZONTAL_ALIGNMENT_LEFT
  button.clip_text=true
  button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
  button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
  search_results.add_child(button)
  button.pressed.connect(choose_place.bind(result))
 _ensure_focus_visible.call_deferred()
func _place_search_failed(query: String,detail: String) -> void:
 if not visible or query!=TerrainPlaceSearch.normalize(search_field.text): return
 search_button.disabled=not place_search.enabled()
 _clear_places(detail+". The map and square still work.")
func _clear_places(status: String) -> void:
 search_status.text=status
 for child in search_results.get_children():
  search_results.remove_child(child)
  child.queue_free()
## Center the square on a search result, keeping its size and bearing.
func choose_place(result: Dictionary) -> void:
 var next := extent_map.selection.duplicate(true)
 next.latitude=float(result.latitude)
 next.longitude=float(result.longitude)
 var place := str(result.name).get_slice(",",0)
 if not TerrainGeography.validate_selection(next).ok:
  search_status.text="%s is outside the area terrain can come from (latitude −60° to 82.75°)."%place
  return
 _clear_places("Square moved to %s."%place)
 extent_map.set_selection(next)
 _selection_from_map(next)
 extent_map.fit_selection()
 extent_map.grab_focus()
func _diagnostics(d: Dictionary) -> String:
 return "Original elevation %.1f to %.1f m\nScale %.2f m/tile · %.2f m/level · source spacing %.2f m\nClipped targets %d · normalized vertices %d · largest repair %.2f m\nWater: %d fresh · %d sea · %d widened · %d streams · %d waterfalls · %d wet tiles lost\nWorldCover water year %d\nSpherical approximation: distances and shapes are approximate. Water reflects 2021, may miss narrow channels and may differ from today. Modified for playable terrain."%[d.source_min_metres,d.source_max_metres,d.metres_per_tile,d.metres_per_level,d.sample_spacing_metres,d.initial_clipped_targets,d.repaired_vertices,d.max_repair_metres,d.fresh_tiles,d.sea_tiles,d.widened_tiles,d.stream_tiles,d.waterfall_tiles,d.lost_wet_tiles,d.water_year]
func _update_actions() -> void:
 if download_button==null: return
 var online := importer!=null and importer.is_online_fresh()
 download_button.disabled=not _selection_valid or not online or not _operation.is_empty()
 fit_button.disabled=not _selection_valid or not online or not _operation.is_empty() or _packet_selection.is_empty() or _packet_selection!=extent_map.selection
 use_button.disabled=not _selection_valid or importer==null or not importer.is_ready() or not _operation.is_empty()
func _clear_cache() -> void:
 cancel_work()
 if importer==null: return
 var result := importer.clear_cache()
 progress_label.text="Terrain cache cleared." if result.ok else "Cache could not be cleared: "+str(result.error)
 _update_actions()
func _accept() -> void:
 if importer==null or not _selection_valid or not importer.is_ready() or not _operation.is_empty(): return
 accepted.emit(importer.candidate)
 close()
func _gui_input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
  close()
  accept_event()

# Wrapped actions reparent on a deferred layout pass. Reveal the focused target
# after both that pass and status-label reflow, without stealing a newer focus.
func _ensure_focus_visible() -> void:
 if is_inside_tree(): _reveal_after_layout(weakref(self),get_tree())

static func _reveal_after_layout(target: WeakRef,tree: SceneTree) -> void:
 await tree.process_frame
 await tree.process_frame
 var dialog := target.get_ref() as RealWorldTerrainDialog
 if dialog==null or not dialog.is_visible_in_tree(): return
 var focus := dialog.get_viewport().gui_get_focus_owner()
 var chrome: Dictionary=dialog.panel.get_meta("window_chrome")
 if focus!=null and chrome.body.is_ancestor_of(focus):
  chrome.body_scroll.ensure_control_visible(focus)
