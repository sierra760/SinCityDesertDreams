# SPDX-License-Identifier: GPL-3.0-or-later
## Explore navigation and screen-space overhead markers share one snapshot.
## No simulation writes, scene-object handles in Lua, or polling by scripts.
class_name ExploreNavigation
extends Control

signal toggle_requested
var controller: CityExplorationController
var overview: MiniMap
var expanded := false
var map_visible := true
var _active := false
var _usable := Rect2(0,0,1280,800)
var _status_rect := Rect2()
var _touch := false
var _compact: PanelContainer
var _expanded: PanelContainer
var _shade: ColorRect
var _world: Control
var _open_button: Button
var _close_button: Button
var _caption: Label
var _legend: Label
var _small_map: ExploreNavigationMap
var _large_map: ExploreNavigationMap
var _markers: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world = Control.new()
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world.draw.connect(_draw_world)
	add_child(_world)
	_compact = UIFactory.make_panel()
	_compact.name = "ExploreMinimap"
	add_child(_compact)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",0)
	_compact.add_child(column)
	_small_map = ExploreNavigationMap.new()
	_small_map.custom_minimum_size = Vector2(144,144)
	_small_map.expand_requested.connect(func() -> void: toggle_requested.emit())
	column.add_child(_small_map)
	_open_button = UIFactory.make_button("Map")
	_open_button.pressed.connect(func() -> void: toggle_requested.emit())
	column.add_child(_open_button)
	_shade = ColorRect.new()
	_shade.color = Color(0.035,0.08,0.09,.78)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_expanded = UIFactory.make_panel()
	_expanded.name = "ExploreExpandedMap"
	add_child(_expanded)
	var full := VBoxContainer.new()
	full.add_theme_constant_override("separation",6)
	_expanded.add_child(full)
	var header := HBoxContainer.new()
	full.add_child(header)
	var title := UIFactory.make_section_header("Explore Map")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_close_button = UIFactory.make_button("Close")
	_close_button.pressed.connect(func() -> void: toggle_requested.emit())
	header.add_child(_close_button)
	_caption = UIFactory.make_label("Explore paused · Drag to pan",UITheme.FONT_SMALL)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	full.add_child(_caption)
	_large_map = ExploreNavigationMap.new()
	_large_map.browsing = true
	_large_map.span = 128
	full.add_child(_large_map)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",6)
	full.add_child(actions)
	for item: Array in [["−",func() -> void: _large_map.set_span(_large_map.span*1.25)], ["+",func() -> void: _large_map.set_span(_large_map.span*.8)], ["Find me",recenter], ["Whole city",whole_city]]:
		var button := UIFactory.make_button(item[0])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(item[1])
		actions.add_child(button)
	_legend = UIFactory.make_label("Arrow: you · Diamond: objective\nCircle: person · Box: vehicle · Ring: checkpoint",UITheme.FONT_SMALL)
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	full.add_child(_legend)
	set_expanded(false)
	set_session_active(false)

func bind(session: CityExplorationController, city_map: MiniMap) -> void:
	controller = session
	overview = city_map

func set_session_active(on: bool) -> void:
	_active = on
	visible = on
	if not on:
		_markers.clear()
		set_expanded(false)
	_refresh_visibility()

func set_expanded(on: bool) -> void:
	expanded = on
	if _large_map == null: return
	_small_map.reset_gestures()
	_large_map.reset_gestures()
	if on:
		whole_city()
	_refresh_visibility()
	apply_layout(_usable,_status_rect,_touch)
	if on and not _touch: _close_button.grab_focus()

func _refresh_visibility() -> void:
	if _compact == null: return
	_compact.visible = _active and not expanded
	_expanded.visible = _active and expanded
	_shade.visible = _active and expanded
	_world.visible = _active and not expanded
	apply_layout(_usable,_status_rect,_touch)

func apply_layout(usable: Rect2, status_rect: Rect2, touch: bool) -> void:
	_usable = usable
	_status_rect = status_rect
	_touch = touch
	if _compact == null: return
	_shade.position = usable.position
	_shade.size = usable.size
	var compact_margin := 4.0 if touch and usable.size.y < 360 else float(UITheme.MARGIN)
	var style := UITheme.window_stylebox()
	style.set_content_margin_all(compact_margin)
	_compact.add_theme_stylebox_override("panel",style)
	var right_room := maxf(0,usable.end.x-status_rect.end.x-24)
	var side := clampf(right_room-UITheme.MARGIN*2,72,144)
	side = minf(side,maxf(32,usable.size.y-80))
	_small_map.custom_minimum_size = Vector2(side,side)
	_small_map.size = Vector2(side,side)
	# A 44-unit target remains available even on the narrowest phone. On very
	# short views the card reduces to its button rather than covering a thumb.
	_small_map.visible = map_visible and (not touch or usable.size.y >= side+324) and right_room >= 80
	_compact.size = Vector2(side+compact_margin*2,0)
	_compact.position = Vector2(usable.end.x-_compact.size.x-8,usable.position.y+(64 if touch else 8))
	var width := minf(720,maxf(1,usable.size.x-16))
	_caption.visible = usable.size.y >= 300
	_legend.visible = usable.size.y >= 360
	for label: Label in [_caption,_legend]:
		label.size.x = maxf(1,width-UITheme.MARGIN*2)
		# Refresh deferred 4.7 text shaping before reserving the map's height.
		label.get_minimum_size()
	(_expanded.get_child(0) as Control).size.x = maxf(1,width-UITheme.MARGIN*2)
	var header_height := 124.0
	if _caption.visible: header_height += _caption.get_combined_minimum_size().y+6
	if _legend.visible: header_height += _legend.get_combined_minimum_size().y+6
	var map_side := maxf(32,minf(width-UITheme.MARGIN*2,usable.size.y-16-header_height))
	_large_map.custom_minimum_size = Vector2(map_side,map_side)
	_large_map.size = Vector2(map_side,map_side)
	_large_map.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_expanded.size = Vector2(width,0)
	_expanded.position = usable.position+Vector2((usable.size.x-width)*.5,8)
	_caption.visible = usable.size.y >= 300
	_legend.visible = usable.size.y >= 360
	if is_instance_valid(controller):
		var key := controller.controls.caption(&"explore_map",0)
		_open_button.text = "Map" if touch else "Map (%s)" % key
		_close_button.text = "Close" if touch else "Close (%s / Esc)" % key

func owns_touch(point: Vector2) -> bool:
	return _active and (expanded or (_compact.visible and _compact.get_global_rect().has_point(point)))

func recenter() -> void:
	if not is_instance_valid(controller): return
	var player := controller.minimap_marker()
	if not player.is_empty(): _large_map.center = player.position
	_large_map.set_span(32)

func whole_city() -> void:
	if _large_map == null: return
	_large_map.center = Vector2(City.WIDTH,City.HEIGHT)*.5
	_large_map.set_span(128)

func _process(_delta: float) -> void:
	if not _active or not is_instance_valid(controller) or not controller.is_active(): return
	var player := controller.minimap_marker()
	if player.is_empty(): return
	_markers = controller.navigation_markers()
	_markers.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.distance < b.distance)
	var map_texture: Texture2D = overview.navigation_texture() if is_instance_valid(overview) else null
	for map: ExploreNavigationMap in [_small_map,_large_map]:
		map.texture = map_texture
		map.player = player
		map.markers = _markers
		map.queue_redraw()
	_small_map.center = player.position
	_small_map.span = 32.0 if controller.mode == ExploreActorProfile.Mode.FLY else 24.0 if controller.mode == ExploreActorProfile.Mode.DRIVE else 16.0
	_world.queue_redraw()

## Always legible overhead badges; the camera projects their supported height.
## Behind-camera targets stay on the map. Nearest-first label placement keeps
## crowded objectives from obscuring each other or the HUD.
func _draw_world() -> void:
	if not _active or expanded or not is_instance_valid(controller) or controller.is_suspended(): return
	if not is_instance_valid(controller.camera_rig): return
	var camera := controller.camera_rig.camera
	if not is_instance_valid(camera): return
	var font := ThemeDB.fallback_font
	var drawn: Array[Rect2] = []
	var reserved: Array[Rect2] = []
	if _touch and is_instance_valid(controller.hud.touch_controls):
		for action: StringName in controller.hud.touch_controls._rects:
			reserved.append(controller.hud.touch_controls.control_rect(action))
	for entry: Dictionary in _markers:
		if not entry.world or camera.is_position_behind(entry.anchor): continue
		var point := world_point(entry.anchor)
		if not _usable.grow(-12).has_point(point) or _status_rect.grow(8).has_point(point) or (_compact.visible and _compact.get_global_rect().grow(8).has_point(point)): continue
		if reserved.any(func(rect: Rect2) -> bool: return rect.grow(4).has_point(point)): continue
		ExploreNavigationMap.draw_pin(_world,point,entry.icon,7)
		var text := String(entry.label).replace("\n"," ").replace("\r"," ").left(40)
		text += (" · " if not text.is_empty() else "")+ExploreNavigationMap.distance_text(entry.distance)
		var width := minf(280,minf(_usable.size.x-24,font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+12))
		var rect := Rect2((point+Vector2(-width*.5,-36)).clamp(_usable.position+Vector2(4,4),_usable.end-Vector2(width+4,26)),Vector2(width,22))
		if drawn.size() < 12 and not rect.intersects(_status_rect) and not (_compact.visible and rect.intersects(_compact.get_global_rect())) and not reserved.any(func(other: Rect2) -> bool: return other.intersects(rect)) and not drawn.any(func(other: Rect2) -> bool: return other.intersects(rect)):
			_world.draw_rect(rect,ExploreNavigationMap.INK)
			_world.draw_string(font,rect.position+Vector2(6,16),text,HORIZONTAL_ALIGNMENT_LEFT,width-12,14,ExploreNavigationMap.PAPER)
			drawn.append(rect)

## Convert the Explore render viewport to the root logical HUD canvas.
func world_point(anchor: Vector3) -> Vector2:
	var view := controller.view
	if view.viewport.size.x <= 0 or view.viewport.size.y <= 0: return Vector2(-1,-1)
	return view.container.position+controller.camera_rig.camera.unproject_position(anchor)*view.container.size/Vector2(view.viewport.size)
