# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name TerrainExtentMap
extends Control

signal selection_changed(selection: Dictionary)
signal view_changed(view: Dictionary)

const MAX_ZOOM := 17
## Coarser loaded tiles stand in for missing ones, up to this many levels.
const FALLBACK_LEVELS := 6
var selection: Dictionary = TerrainImportContract.defaults().selection
var view := {"center":Vector2(-115.1398,36.1699),"zoom":12,"size":Vector2i(512,320)}
## Street basemap drawn behind the square; null draws the plain background.
var basemap: TerrainBasemap:
 set(value):
  if basemap!=null and basemap.tiles_changed.is_connected(queue_redraw): basemap.tiles_changed.disconnect(queue_redraw)
  basemap=value
  if basemap!=null: basemap.tiles_changed.connect(queue_redraw)
  request_tiles()
# Vector2 is single precision; deep zoom needs the center in doubles.
var _center_lon := -115.1398
var _center_lat := 36.1699
var _touches := {}
var _gesture := ""
var _last := Vector2.ZERO
var _handle := -1
var _pinch_distance := 0.0
var _zoom_accumulator := 0.0

func _init() -> void:
 name="TerrainExtentMap"
 set_meta("owns_pointer_gestures",true)
 custom_minimum_size=Vector2(220,260)
 size_flags_horizontal=Control.SIZE_EXPAND_FILL
 mouse_filter=Control.MOUSE_FILTER_STOP
 focus_mode=Control.FOCUS_ALL
 clip_contents=true
 tooltip_text="Drag to pan. Pinch or scroll to zoom."
 resized.connect(func() -> void:
  cancel_gesture()
  view.size=Vector2i(clampi(int(size.x),1,1024),clampi(int(size.y),1,512))
  _view_moved())
 focus_exited.connect(cancel_gesture)
 visibility_changed.connect(func() -> void:
  if not is_visible_in_tree(): cancel_gesture())

func set_selection(value: Dictionary) -> void:
 if not TerrainGeography.validate_selection(value).ok: return
 selection=value.duplicate(true)
 queue_redraw()

func set_view(value: Dictionary) -> void:
 if not value.get("center") is Vector2: return
 _set_center(value.center.x,value.center.y)
 view.zoom=clampi(int(value.get("zoom",view.zoom)),0,MAX_ZOOM)
 view.size=Vector2i(clampi(int(size.x),1,1024),clampi(int(size.y),1,512))
 request_tiles()
 queue_redraw()

func _set_center(longitude: float, latitude: float) -> void:
 _center_lon=wrapf(longitude,-180.0,180.0)
 _center_lat=clampf(latitude,-60.0,82.75)
 view.center=Vector2(_center_lon,_center_lat)

func _view_moved() -> void:
 request_tiles()
 view_changed.emit(view.duplicate(true))
 queue_redraw()

## Ask the basemap for the tiles this view shows.
func request_tiles() -> void:
 if basemap==null: return
 basemap.set_hidpi(pixel_ratio()>=1.5)
 var center := _pixel_xy(_center_lon,_center_lat)
 basemap.request_view(center[0],center[1],int(view.zoom),size)

## Device pixels per logical map unit (UI scale × window backing scale).
func pixel_ratio() -> float:
 if not is_inside_tree(): return 1.0
 var ratio := absf(get_viewport().get_final_transform().get_scale().x*get_global_transform_with_canvas().get_scale().x)
 return ratio if is_finite(ratio) and ratio>0.0 else 1.0

func _refresh_density() -> void:
 if basemap!=null and is_inside_tree(): request_tiles()

func fit_selection() -> void:
 _set_center(selection.longitude,selection.latitude)
 for zoom in range(MAX_ZOOM,-1,-1):
  view.zoom=zoom
  var corners := selection_corners()
  var bounds := Rect2(corners[0],Vector2.ZERO)
  for corner in corners: bounds=bounds.expand(corner)
  if bounds.size.x<=maxf(80,size.x-64) and bounds.size.y<=maxf(80,size.y-80): break
 _view_moved()

## Center the view on a lon/lat box at the closest zoom that shows all of it.
func frame_bounds(west: float, south: float, east: float, north: float) -> void:
 _set_center((west+east)/2.0,(south+north)/2.0)
 for zoom in range(MAX_ZOOM,-1,-1):
  var world := float(256*(1<<zoom))
  var a := _pixel_xy(west,clampf(north,-85.0,85.0),zoom)
  var b := _pixel_xy(east,clampf(south,-85.0,85.0),zoom)
  view.zoom=zoom
  if absf(b[0]-a[0])<=maxf(80,size.x-64) and absf(b[1]-a[1])<=maxf(80,size.y-80) or world<=size.x: break
 _view_moved()

func cancel_gesture() -> void:
 _touches.clear()
 _gesture=""
 _handle=-1

func _notification(what: int) -> void:
 if what==NOTIFICATION_APPLICATION_FOCUS_OUT or what==NOTIFICATION_APPLICATION_PAUSED: cancel_gesture()
 # Moving between a standard and a Retina display changes the tile density.
 elif what==NOTIFICATION_WM_DPI_CHANGE or what==NOTIFICATION_ENTER_TREE: _refresh_density.call_deferred()

func _world_size() -> float: return float(256*(1<<int(view.zoom)))
## Web Mercator pixel (tile corner origin) as doubles.
func _pixel_xy(longitude: float, latitude: float, zoom: int = -1) -> PackedFloat64Array:
 var p := TerrainGeography._elevation_pixel_scalars(longitude,latitude,int(view.zoom) if zoom<0 else zoom)
 return PackedFloat64Array([p[0]+0.5,p[1]+0.5])
func _geo_xy(x: float, y: float) -> PackedFloat64Array:
 var world := _world_size()
 return PackedFloat64Array([wrapf(x/world*360.0-180.0,-180.0,180.0),rad_to_deg(atan(sinh(PI*(1.0-2.0*y/world))))])
func geo_to_screen(geo: Vector2) -> Vector2:
 var p := _pixel_xy(geo.x,geo.y)
 var c := _pixel_xy(_center_lon,_center_lat)
 return size/2.0+Vector2(wrapf(p[0]-c[0],-_world_size()/2.0,_world_size()/2.0),p[1]-c[1])
func screen_to_geo(point: Vector2) -> Vector2:
 var c := _pixel_xy(_center_lon,_center_lat)
 var g := _geo_xy(c[0]+point.x-size.x/2.0,c[1]+point.y-size.y/2.0)
 return Vector2(g[0],g[1])
func selection_corners() -> PackedVector2Array:
 var points := PackedVector2Array()
 for p in [Vector2(0,0),Vector2(128,0),Vector2(128,128),Vector2(0,128)]:
  points.append(geo_to_screen(TerrainGeography.city_to_geo(selection,p)))
 return points
## True when the selection quad spans at least one pixel and triangulates.
static func fill_drawable(corners: PackedVector2Array) -> bool:
 if corners.size()<3: return false
 var bounds := Rect2(corners[0],Vector2.ZERO)
 for corner in corners:
  if not corner.is_finite(): return false
  bounds=bounds.expand(corner)
 if bounds.size.x<1.0 or bounds.size.y<1.0: return false
 return not Geometry2D.triangulate_polygon(corners).is_empty()
func pan(delta: Vector2) -> void:
 var c := _pixel_xy(_center_lon,_center_lat)
 var g := _geo_xy(c[0]-delta.x,c[1]-delta.y)
 _set_center(g[0],g[1])
 _view_moved()
func zoom_by(amount: int) -> void:
 view.zoom=clampi(int(view.zoom)+amount,0,MAX_ZOOM)
 _view_moved()
## Trackpad pinches and precision-touchpad or free-spinning wheels arrive as a
## stream of fractional steps. They add up, and the map moves one whole level
## (2x) each time the total passes half a level, instead of a level per event.
func zoom_gradually(levels: float) -> void:
 if not is_finite(levels) or is_zero_approx(levels): return
 _zoom_accumulator+=levels
 var whole := 0
 while _zoom_accumulator>=0.5:
  _zoom_accumulator-=1.0
  whole+=1
 while _zoom_accumulator<=-0.5:
  _zoom_accumulator+=1.0
  whole-=1
 if whole==0: return
 var before := int(view.zoom)
 zoom_by(whole)
 # At the closest or widest level further steps would only build up.
 if int(view.zoom)==before: _zoom_accumulator=0.0
static func wheel_levels(event: InputEventMouseButton) -> float:
 var factor := event.factor
 var steps := clampf(factor,0.0,4.0) if is_finite(factor) and factor>0.0 else 1.0
 return steps if event.button_index==MOUSE_BUTTON_WHEEL_UP else -steps
func _begin_pointer(point: Vector2) -> void:
 grab_focus()
 _last=point
 _gesture="pan"
 _handle=-1
 var corners := selection_corners()
 for i in corners.size():
  if Rect2(corners[i]-Vector2(22,22),Vector2(44,44)).has_point(point):
   _handle=i
   _gesture="resize"
   return
 if Rect2(geo_to_screen(Vector2(selection.longitude,selection.latitude))-Vector2(22,22),Vector2(44,44)).has_point(point): _gesture="move"
func _drag_pointer(point: Vector2) -> void:
 if _gesture=="pan": pan(point-_last)
 elif _gesture=="resize":
  var center := geo_to_screen(Vector2(selection.longitude,selection.latitude))
  var old_corner := selection_corners()[_handle]
  var next := selection.duplicate(true)
  next.side_km=clampf(float(selection.side_km)*point.distance_to(center)/maxf(1.0,old_corner.distance_to(center)),0.5,128.0)
  _publish_selection(next)
 elif _gesture=="move":
  var next := selection.duplicate(true)
  var center := screen_to_geo(geo_to_screen(Vector2(selection.longitude,selection.latitude))+point-_last)
  next.longitude=center.x
  next.latitude=center.y
  _publish_selection(next)
 _last=point
func _publish_selection(next: Dictionary) -> void:
 if not TerrainGeography.validate_selection(next).ok: return
 set_selection(next)
 selection_changed.emit(selection.duplicate(true))

# Capture a started pointer through releases outside the rectangle. Other GUI
# controls own their first press and cannot accidentally start a map gesture.
func _input(event: InputEvent) -> void:
 if not is_visible_in_tree() or _gesture.is_empty(): return
 if event is InputEventScreenTouch and event.pressed:
  var local := make_input_local(event) as InputEventScreenTouch
  if not _point_visible(local.position):
   cancel_gesture()
   return
 if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseMotion or (event is InputEventMouseButton and not event.pressed):
  _pointer_input(make_input_local(event))
  get_viewport().set_input_as_handled()
func _point_visible(point: Vector2) -> bool:
 if not Rect2(Vector2.ZERO,size).has_point(point): return false
 var global_point := get_global_transform_with_canvas()*point
 var ancestor := get_parent()
 while ancestor!=null:
  if ancestor is Control and ancestor.clip_contents and not ancestor.get_global_rect().has_point(global_point): return false
  ancestor=ancestor.get_parent()
 return true
func _gui_input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed:
  match event.keycode:
   KEY_LEFT: pan(Vector2(64,0))
   KEY_RIGHT: pan(Vector2(-64,0))
   KEY_UP: pan(Vector2(0,64))
   KEY_DOWN: pan(Vector2(0,-64))
   KEY_PLUS, KEY_EQUAL, KEY_KP_ADD: zoom_by(1)
   KEY_MINUS, KEY_KP_SUBTRACT: zoom_by(-1)
   KEY_F: fit_selection()
   _: return
  accept_event()
 elif event is InputEventMagnifyGesture:
  if event.factor>0.0: zoom_gradually(log(event.factor)/log(2.0))
  accept_event()
 elif event is InputEventPanGesture:
  pan(-event.delta*16)
  accept_event()
 else:
  _pointer_input(event)
  accept_event()
func _pointer_input(event: InputEvent) -> void:
 if event is InputEventMouseButton:
  if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: zoom_gradually(wheel_levels(event))
  elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_LEFT,MOUSE_BUTTON_WHEEL_RIGHT]: pan(Vector2(32.0 if event.button_index==MOUSE_BUTTON_WHEEL_LEFT else -32.0,0.0)*absf(wheel_levels(event)))
  elif event.button_index==MOUSE_BUTTON_LEFT:
   if event.pressed and _touches.is_empty(): _begin_pointer(event.position)
   elif not event.pressed and _touches.is_empty(): cancel_gesture()
 elif event is InputEventMouseMotion and _touches.is_empty() and not _gesture.is_empty(): _drag_pointer(event.position)
 elif event is InputEventScreenTouch:
  if event.pressed:
   _touches[event.index]=event.position
   if _touches.size()==1: _begin_pointer(event.position)
   else:
    _handle=-1
    _gesture="pinch"
    var points: Array=_touches.values()
    _pinch_distance=points[0].distance_to(points[1])
  else:
   _touches.erase(event.index)
   if _touches.is_empty(): cancel_gesture()
   elif _touches.size()==1:
    _gesture="pan"
    _last=_touches.values()[0]
 elif event is InputEventScreenDrag and _touches.has(event.index):
  if _touches.size()==1:
   _touches[event.index]=event.position
   _drag_pointer(event.position)
  else:
   var before: Array=_touches.values()
   var old_center: Vector2=(before[0]+before[1])/2.0
   _touches[event.index]=event.position
   var after: Array=_touches.values()
   var new_distance: float=after[0].distance_to(after[1])
   pan((after[0]+after[1])/2.0-old_center)
   if new_distance>_pinch_distance*1.25:
    zoom_by(1)
    _pinch_distance=new_distance
   elif new_distance<_pinch_distance/1.25:
    zoom_by(-1)
    _pinch_distance=new_distance

func _draw() -> void:
 draw_rect(Rect2(Vector2.ZERO,size),Color("243d3a"))
 _draw_basemap()
 var corners := selection_corners()
 # At low zoom the footprint can be sub-pixel; the engine's triangulation then
 # fails every redraw. The outline, handles and center dot still mark it.
 if fill_drawable(corners): draw_colored_polygon(corners,Color(0.92,0.78,0.38,0.2))
 var outline := corners.duplicate()
 outline.append(corners[0])
 # A dark halo keeps the brass outline readable on light street tiles.
 draw_polyline(outline,Color(0.08,0.16,0.15,0.85),5.0,true)
 draw_polyline(outline,Color("e4c570"),2.0,true)
 for corner in corners:
  draw_rect(Rect2(corner-Vector2(7,7),Vector2(14,14)),Color("1d3331"))
  draw_rect(Rect2(corner-Vector2(5,5),Vector2(10,10)),Color("fff4d4"))
  draw_rect(Rect2(corner-Vector2(22,22),Vector2(44,44)),Color(0.08,0.16,0.15,0.4),false)
 var center := geo_to_screen(Vector2(selection.longitude,selection.latitude))
 draw_circle(center,8,Color("1d3331"))
 draw_circle(center,6,Color("e4c570"))
 draw_rect(Rect2(10,6,28,52),Color(0,0,0,0.55))
 draw_line(Vector2(24,52),Vector2(24,24),Color.WHITE,2)
 draw_line(Vector2(24,24),Vector2(18,34),Color.WHITE,2)
 draw_line(Vector2(24,24),Vector2(30,34),Color.WHITE,2)
 var font := ThemeDB.fallback_font
 draw_string(font,Vector2(18,18),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
 var metres := 100.0*2.0*PI*TerrainGeography.RADIUS*cos(deg_to_rad(view.center.y))/_world_size()
 draw_rect(Rect2(10,size.y-50,size.x-20,42),Color(0,0,0,0.65))
 draw_line(Vector2(18,size.y-39),Vector2(118,size.y-39),Color.WHITE,2)
 draw_string(font,Vector2(18,size.y-21),"%.2f km  ·  %.4f, %.4f"%[metres/1000.0,selection.latitude,selection.longitude],HORIZONTAL_ALIGNMENT_LEFT,size.x-36,14,Color.WHITE)
 if basemap!=null:
  # Licence credit stays on the map itself, above the scale bar.
  var credit: String=basemap.attribution() if basemap.enabled() else "Street map is turned off"
  var width := font.get_string_size(credit,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
  var box := Rect2(size.x-width-18,size.y-72,width+8,20)
  draw_rect(box,Color(1,1,1,0.82))
  draw_string(font,box.position+Vector2(4,15),credit,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("2b2b2b"))
  if basemap.loaded_count()==0 and basemap.pending_count()==0 and not basemap.last_error().is_empty():
   var message: String=basemap.last_error()+" · the square still works"
   draw_rect(Rect2(10,size.y-74,size.x-width-38,22),Color(0,0,0,0.65))
   draw_string(font,Vector2(18,size.y-58),message,HORIZONTAL_ALIGNMENT_LEFT,size.x-width-52,12,Color.WHITE)
 if has_focus(): draw_rect(Rect2(Vector2.ONE,size-Vector2(2,2)),Color("e4c570"),false,2)

## Draw each visible tile, or the nearest loaded coarser tile's matching part.
func _draw_basemap() -> void:
 if basemap==null: return
 var z := int(view.zoom)
 var c := _pixel_xy(_center_lon,_center_lat)
 for tile in TerrainBasemap.visible_tiles(c[0],c[1],z,size):
  var dx := wrapf(tile.x*256.0-c[0],-_world_size()/2.0,_world_size()/2.0)
  # Wrapped tiles keep their on-screen column near the center.
  var rect := Rect2(size/2.0+Vector2(dx,tile.y*256.0-c[1]),Vector2(256,256))
  var texture := basemap.texture(z,tile.x,tile.y)
  if texture!=null:
   draw_texture_rect(texture,rect,false)
   continue
  for up in range(1,mini(FALLBACK_LEVELS,z)+1):
   var parent := basemap.texture(z-up,tile.x>>up,tile.y>>up)
   if parent==null: continue
   var span := 256.0/float(1<<up)
   var pixels := float(parent.get_width())/256.0
   var source := Rect2((tile.x-((tile.x>>up)<<up))*span*pixels,(tile.y-((tile.y>>up)<<up))*span*pixels,span*pixels,span*pixels)
   draw_texture_rect_region(parent,rect,source)
   break
