# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## City gesture routing independent of drawing and numerical simulation.
class_name CityPresentationController
extends Node
signal street_selection_requested(point: Vector2)
signal street_hovered(point: Vector2)
signal tile_clicked(tile: Vector2i, button: int)
signal tile_hovered(tile: Vector2i)
signal drag_started(from: Vector2i, to: Vector2i)
signal drag_updated(from: Vector2i, to: Vector2i)
signal drag_ended(from: Vector2i, to: Vector2i)
signal drag_cancelled
signal overlay_changed(kind: StringName)
signal view_mode_changed(mode: int)
enum ViewMode { SURFACE, UNDERGROUND }
const UNDERGROUND_TOOLS: Array[int] = [Tools.Kind.SUBWAY, Tools.Kind.WATER_PIPE]
const BuildGestures := preload("res://scripts/view/city_build_gestures.gd")
var city: City
var view: CityView3D
var input_blocked: Callable
var pick_purpose := 0
var preview := CursorPreviewState.new()
var view_mode := ViewMode.SURFACE
var _overlay: StringName = &""
var _automatic_underground := false
var _surface_overlay: StringName = &""
var _last_hover := Vector2i(-1, -1)
var _drag_from := Vector2i(-1, -1)
var _drag_to := Vector2i(-1, -1)
var _drag_button := 0
var _exploration_suspended := false
var _touch_gestures := BuildGestures.new()
var _touch_ui_owned: Callable
var _emitting_touch_cancellation := false
var _street_names_active := false
var _street_mouse_down := false
var _street_mouse_dragged := false
var _street_mouse_origin := Vector2.ZERO
var _query_tool_active := false
var _query_touch_active := false
var _pointer_position := Vector2.ZERO
var _pointer_available := false
var _pointer_ui_scale := 1.0

func _init() -> void:
	preview.footprint_changed.connect(_sync_preview)

func bind_city(value: City) -> void:
	cancel_drag()
	preview.clear()
	city = value
	if view != null:
		view.bind_city(value)

func tile_at_screen(point: Vector2, purpose: int = -1) -> Vector2i:
	return view.pick_cell(point, pick_purpose if purpose < 0 else purpose) if view != null else Vector2i(-1, -1)

func set_overlay(kind: StringName) -> void:
	if _exploration_suspended: return
	if kind == &"none":
		kind = &""
	if kind != &"" and not CityOverlaySampler.LAYERS.has(kind):
		return
	_overlay = kind
	_surface_overlay = kind
	if view != null:
		view.set_overlay(kind)
	overlay_changed.emit(kind)

func get_overlay() -> StringName:
	return _overlay

## An explicit selection takes ownership from automatic tool entry.
func set_view_mode(mode: int) -> void:
	if _exploration_suspended: return
	_automatic_underground = false
	_apply_view_mode(clampi(mode, ViewMode.SURFACE, ViewMode.UNDERGROUND))

func _apply_view_mode(mode: int) -> void:
	view_mode = mode
	cancel_drag()
	preview.clear()
	if view != null:
		view.set_underground(is_underground())
	view_mode_changed.emit(view_mode)

func is_underground() -> bool:
	return view_mode == ViewMode.UNDERGROUND

func select_tool(tool: int) -> void:
	set_query_tool_active(tool == Tools.Kind.QUERY)
	if _exploration_suspended: return
	if UNDERGROUND_TOOLS.has(tool):
		if not is_underground():
			_surface_overlay = _overlay
			_automatic_underground = true
			_apply_view_mode(ViewMode.UNDERGROUND)
	elif _automatic_underground:
		_automatic_underground = false
		_apply_view_mode(ViewMode.SURFACE)
		set_overlay(_surface_overlay)

## Query and construction both aim at the actual viewport contact.
func set_query_tool_active(on: bool) -> void:
	_query_tool_active = on

func has_query_touch() -> bool:
	return _query_touch_active

## Re-pick only a genuine pointer after camera or GUI ownership changes.
## Starting a touch discards the old pointer until a real mouse moves again.
func refresh_query_pointer_hover() -> void:
	if _street_names_active:
		if _pointer_available:
			var street_point := _pointer_position * _pointer_ui_scale / _current_pointer_ui_scale()
			var street_blocked := _touch_blocked() or (_touch_ui_owned.is_valid() and bool(_touch_ui_owned.call(street_point)))
			street_hovered.emit(Vector2(-1,-1) if street_blocked else street_point)
		return
	if not _query_tool_active or not _pointer_available or has_query_touch(): return
	# Preserve physical points across UI scaling, excluding backing pixels.
	var point := _pointer_position * _pointer_ui_scale / _current_pointer_ui_scale()
	var blocked := _touch_blocked() or (_touch_ui_owned.is_valid() and bool(_touch_ui_owned.call(point)))
	var tile := Vector2i(-1, -1) if blocked else tile_at_screen(point)
	_last_hover = tile
	tile_hovered.emit(tile)

func _current_pointer_ui_scale() -> float:
	if view != null and view.display_layout != null:
		return maxf(0.01,float(view.display_layout.metrics.get("effective_percent",100.0))/100.0)
	return 1.0

func _sync_preview() -> void:
	if _exploration_suspended:
		if view != null: view.clear_cursor()
		return
	if view != null:
		view.show_cells(preview.tiles, preview.ok)

func _mark_handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()

func cancel_drag() -> void:
	# Main's cancellation callback also clears this owner. The gesture already
	# cancelled before the signal, so preserve its new navigation baseline.
	var cancelled_touch := false if _emitting_touch_cancellation else _touch_gestures.cancel()
	_clear_drag_state()
	if cancelled_touch:
		preview.clear()
		_emit_touch_cancelled()

func _emit_touch_cancelled() -> void:
	_emitting_touch_cancellation = true
	drag_cancelled.emit()
	_emitting_touch_cancellation = false

func _clear_drag_state() -> void:
	_street_mouse_down = false
	_query_touch_active = false
	_drag_from = Vector2i(-1, -1)
	_drag_to = Vector2i(-1, -1)
	_drag_button = 0
	_last_hover = Vector2i(-1, -1)

## Main supplies visible GUI rectangles in root logical coordinates. Mouse
## hover cannot identify independent touchscreen contacts.
func set_touch_ui_ownership_checker(checker: Callable) -> void:
	_touch_ui_owned = checker

func _touch_blocked() -> bool:
	return _exploration_suspended or city == null or (input_blocked.is_valid() and bool(input_blocked.call()))

## Observe all contacts before GUI handling so a second UI finger also cancels
## a stroke. UI contacts remain unhandled for their ordinary Control owner.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_pointer_position = event.position
		_pointer_ui_scale = _current_pointer_ui_scale()
		_pointer_available = true
	if event is InputEventScreenTouch and event.pressed:
		_pointer_available = false
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	var ui_owned := _touch_ui_owned.is_valid() and bool(_touch_ui_owned.call(event.position))
	var action := _touch_gestures.handle(event, ui_owned, _touch_blocked())
	if bool(action.get("cancel", false)):
		_clear_drag_state()
		preview.clear()
		tile_hovered.emit(Vector2i(-1, -1))
		_emit_touch_cancelled()
	if _street_names_active:
		if bool(action.get("cancel",false)): street_hovered.emit(Vector2(-1,-1))
		if action.has("begin"): street_hovered.emit(action.begin)
		if action.has("update"): street_hovered.emit(action.update)
		if action.has("commit") and not _touch_blocked(): street_selection_requested.emit(action.commit)
		if view != null:
			if action.has("pan"): view.pan_screen(action.pan)
			if action.has("zoom"): view.pinch_zoom(float(action.zoom))
		if bool(action.get("handled",false)): _mark_handled()
		return
	if action.has("begin"):
		var tile := tile_at_screen(action.begin)
		if tile.x < 0:
			cancel_drag()
		else:
			if view != null and view.display_layout != null:
				view.display_layout.release_city_focus()
			_query_touch_active = _query_tool_active
			_drag_from = tile
			_drag_to = tile
			_drag_button = MOUSE_BUTTON_LEFT
			_last_hover = tile
			tile_hovered.emit(tile)
			if not _query_tool_active:
				tile_clicked.emit(tile, MOUSE_BUTTON_LEFT)
				# Sign dialogs may have taken ownership during the click.
				if _drag_from.x >= 0 and not _touch_blocked():
					drag_started.emit(tile, tile)
	elif action.has("update") or action.has("commit"):
		var point: Vector2 = action.get("update", action.get("commit", Vector2.ZERO))
		var tile := tile_at_screen(point)
		if _query_tool_active and _drag_from.x >= 0:
			_drag_to = tile
			if tile != _last_hover:
				_last_hover = tile
				tile_hovered.emit(tile)
			if action.has("commit"):
				_clear_drag_state()
				tile_hovered.emit(Vector2i(-1, -1))
				if tile.x >= 0 and not _touch_blocked():
					tile_clicked.emit(tile, MOUSE_BUTTON_LEFT)
		elif _drag_from.x >= 0:
			if tile.x >= 0 and tile != _drag_to:
				_drag_to = tile
				_last_hover = tile
				drag_updated.emit(_drag_from, _drag_to)
			if action.has("commit"):
				drag_ended.emit(_drag_from, _drag_to)
				_clear_drag_state()
	if view != null:
		if action.has("pan"): view.pan_screen(action.pan)
		if action.has("zoom"): view.pinch_zoom(float(action.zoom))
	if bool(action.get("handled", false)):
		_mark_handled()


## Preserve automatic utility ownership separately from temporary visibility.
func capture_state() -> Dictionary:
	return {"view_mode":view_mode,"overlay":_overlay,
		"automatic_underground":_automatic_underground,"surface_overlay":_surface_overlay,
		"pick_purpose":pick_purpose}

func restore_state(state: Dictionary) -> void:
	view_mode = clampi(int(state.get("view_mode",ViewMode.SURFACE)),ViewMode.SURFACE,ViewMode.UNDERGROUND)
	_overlay = state.get("overlay",&"")
	_surface_overlay = state.get("surface_overlay",_overlay)
	_automatic_underground = bool(state.get("automatic_underground",false))
	pick_purpose = int(state.get("pick_purpose",0))
	cancel_drag()
	preview.clear()
	_apply_exploration_visibility()

func set_exploration_suspended(on: bool) -> void:
	_exploration_suspended = on
	cancel_drag()
	preview.clear()
	_apply_exploration_visibility()

func _apply_exploration_visibility() -> void:
	if view == null: return
	view.set_overlay(&"" if _exploration_suspended else _overlay)
	view.set_underground(false if _exploration_suspended else is_underground())


## Bring incident markers and ambient traffic up to date with the
## simulation's entity records. Disaster records drive the markers; crews and
## ordinary vehicles drive traffic, which shows only when `show_vehicles` is
## on and the plain surface view is up.
func sync_actors(delta: float, records: Array, transport: SimSystem, paused: bool, show_vehicles: bool) -> void:
	if view.feedback != null:
		var incidents: Array = records.filter(func(record: Dictionary) -> bool: return record.get("source", &"") == &"disasters" or not CityTrafficCatalog.is_vehicle_kind(record.kind))
		view.feedback.sync_records(incidents)
	if view.traffic != null:
		if transport != null and transport.has_method("monthly_riders_by_mode"):
			view.traffic.riders = transport.call("monthly_riders_by_mode")
		var camera: Camera3D = view.exploration_camera() if is_instance_valid(view.exploration_camera()) else view.camera
		var ambient: Array = records.filter(func(record: Dictionary) -> bool: return record.get("source", &"") != &"disasters" or String(record.kind).ends_with("_crew"))
		view.traffic.advance(delta, paused, ambient, camera,
			show_vehicles and not is_underground() and view.overlay_kind() == &"")


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if _exploration_suspended:
		cancel_drag()
		return
	if input_blocked.is_valid() and bool(input_blocked.call()):
		cancel_drag()
		return
	if city == null:
		return
	if _street_names_active and _street_mouse_event(event): return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_pointer_position = motion.position
		_pointer_ui_scale = _current_pointer_ui_scale()
		_pointer_available = true
		var tile := tile_at_screen(motion.position)
		if tile != _last_hover or _query_tool_active:
			_last_hover = tile
			tile_hovered.emit(tile)
		if _drag_from.x >= 0 and tile.x >= 0 and tile != _drag_to:
			_drag_to = tile
			drag_updated.emit(_drag_from, _drag_to)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
			return
		var tile := tile_at_screen(button.position, 1 if button.button_index == MOUSE_BUTTON_RIGHT else pick_purpose)
		if button.pressed:
			if tile.x < 0:
				return
			if view != null and view.display_layout != null:
				view.display_layout.release_city_focus()
			_drag_from = tile
			_drag_to = tile
			_drag_button = button.button_index
			tile_clicked.emit(tile, button.button_index)
			drag_started.emit(tile, tile)
			_mark_handled()
		elif _drag_from.x >= 0 and button.button_index == _drag_button:
			if tile.x >= 0:
				_drag_to = tile
			drag_ended.emit(_drag_from, _drag_to)
			_drag_from = Vector2i(-1, -1)
			_mark_handled()

func set_street_names_active(on: bool) -> void:
	cancel_drag()
	preview.clear()
	_street_names_active = on
	_touch_gestures.tap_only = on
	refresh_query_pointer_hover()

func _street_mouse_event(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		# GUI/another input owner can consume the release. Delivered button
		# state is authoritative before either navigation or click completion.
		if not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_street_mouse_down = false
			_street_mouse_dragged = false
		if _street_mouse_down:
			if event.position.distance_to(_street_mouse_origin) > BuildGestures.TAP_SLOP: _street_mouse_dragged = true
			if _street_mouse_dragged and view != null: view.pan_screen(event.relative)
		street_hovered.emit(event.position)
		return true
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_street_mouse_down = true
				_street_mouse_dragged = false
				_street_mouse_origin = event.position
				if view != null and view.display_layout != null: view.display_layout.release_city_focus()
			else:
				var select: bool = _street_mouse_down and not _street_mouse_dragged and event.position.distance_to(_street_mouse_origin) <= BuildGestures.TAP_SLOP
				_street_mouse_down = false
				if select: street_selection_requested.emit(event.position)
		_mark_handled()
		return true
	return false
