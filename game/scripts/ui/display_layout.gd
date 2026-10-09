# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Display metrics for the whole UI: the one place drawable pixels become
## logical UI coordinates. Scale changes and reflow never touch city state.
class_name DisplayLayout
extends Node
signal metrics_changed(metrics: Dictionary)
const SCALES := [0,100,125,150,175,200]
var metrics: Dictionary = {}
var ui_scale := 0
var fullscreen := false
## Desktop OS maximized state, persisted so restoration reopens maximized.
var maximized := false
var windowed_size := Vector2(1280,800)
## Smallest desktop window in points: the UI never drops below 100% scale.
const MIN_WINDOW_POINTS := Vector2(640,400)
var _window: Window
var _pending := false
var _injected := false
var _registered: Array[Dictionary] = []
var _popups: Array[Window] = []
var _popup_candidates: Array[WeakRef] = []
var _applying_popups := false
var _last_screen := -1
var _last_backing := 0.0
var _last_mode := -1
var _mobile := false
var _safe_area_px := Rect2i()
var _keyboard_height_px := 0
const PLATFORM := preload("res://scripts/platform/mobile_platform.gd")

## Classify the display in physical points, before keyboard or user scaling.
## A keyboard on an iPad must not switch the app into its phone presentation.
static func is_phone(metrics_value: Dictionary) -> bool:
	if not bool(metrics_value.get("mobile",false)):
		return false
	var points := Vector2(metrics_value.get("drawable_size",Vector2i.ZERO)) / maxf(1.0,float(metrics_value.get("backing_scale",1.0)))
	return minf(points.x,points.y) < 600.0

static func resolve_scale(drawable_px: Vector2i, backing_scale: float, requested_percent: int, safe_area_px: Rect2i = Rect2i(), keyboard_height_px: int = 0, mobile: bool = false) -> Dictionary:
	if drawable_px.x <= 0 or drawable_px.y <= 0:
		return {}
	var backing := backing_scale if is_finite(backing_scale) and backing_scale > 0 else 1.0
	var requested := requested_percent if requested_percent in SCALES else 0
	var points := Vector2(drawable_px) / backing
	var desired := float(requested) / 100.0 if requested > 0 else 1.0
	var multiplier := minf(desired,minf(points.x / 640.0,points.y / 400.0))
	# Mobile layouts reflow and scroll at their actual point width. Shrinking
	# the canvas below 100% would turn a 44-unit target into fewer than 44pt.
	if mobile:
		multiplier = maxf(1.0,multiplier)
	var scale := backing * multiplier
	var logical := Vector2(drawable_px) / scale
	var full_px := Rect2i(Vector2i.ZERO,drawable_px)
	var usable_px := full_px
	if safe_area_px.size.x > 0 and safe_area_px.size.y > 0:
		usable_px = full_px.intersection(safe_area_px)
		if usable_px.size.x <= 0 or usable_px.size.y <= 0:
			usable_px = full_px
	# Keyboard is measured from the drawable bottom, rather than subtracted
	# from the safe bottom again (which would double-count the home inset).
	var visible_bottom := maxi(0,drawable_px.y - maxi(0,keyboard_height_px))
	usable_px.size.y = maxi(0,mini(usable_px.end.y,visible_bottom) - usable_px.position.y)
	var usable := Rect2(Vector2(usable_px.position) / scale,Vector2(usable_px.size) / scale)
	return {"drawable_size":drawable_px,"logical_rect":usable,"full_logical_rect":Rect2(Vector2.ZERO,logical),"usable_rect_px":usable_px,"safe_area_px":safe_area_px,"keyboard_height_px":maxi(0,keyboard_height_px),"requested_percent":requested,"effective_percent":multiplier * 100.0,"scale":scale,"backing_scale":backing,"mobile":mobile,"compact":usable.size.x < 1000.0 or usable.size.y < 640.0}

## Godot 4.6 implements screen_get_scale() only on macOS, iOS, Android, Web and
## Wayland; Windows and X11 always report 1.0 although they are DPI aware and
## size windows in physical pixels. On Windows the effective DPI (the player's
## display-scaling choice) is the scale reading, snapped to 25% steps.
## X11 reports the monitor's physical EDID DPI instead, which says nothing about
## the desktop's scaling: an ordinary 14" 1080p laptop reads ~160 dpi yet runs
## at 100%. There an explicit GDK_SCALE/QT_SCALE_FACTOR wins; otherwise only a
## genuinely dense, tall screen doubles (the Godot editor's rule), and the
## result never leaves fewer than 720 points of height. Other platforms keep
## their native backing scale.
static func backing_from_readings(os_name: String, display_server: String, screen_scale: float, dpi: int, screen_height_px: int = 0, environment_scale: float = 0.0) -> float:
	var scale := screen_scale if is_finite(screen_scale) and screen_scale > 0.0 else 1.0
	if not is_equal_approx(scale,1.0):
		return scale
	if os_name == "Windows" and display_server == "Windows":
		return clampf(snappedf(float(dpi) / 96.0,0.25),1.0,3.0) if dpi > 0 else scale
	if os_name in ["Linux","FreeBSD","NetBSD","OpenBSD","BSD"] and display_server == "X11":
		var x11 := 1.0
		if is_finite(environment_scale) and environment_scale > 0.0:
			x11 = clampf(snappedf(environment_scale,0.25),1.0,3.0)
		elif dpi >= 192 and (screen_height_px <= 0 or screen_height_px >= 1400):
			x11 = 2.0
		elif screen_height_px >= 1700:
			x11 = 1.5
		if screen_height_px > 0:
			x11 = maxf(1.0,minf(x11,floorf(float(screen_height_px) / 720.0 * 4.0) / 4.0))
		return x11
	return scale

## The desktop's own scale request on X11 (GDK_SCALE, then QT_SCALE_FACTOR);
## 0 when neither is set or readable.
static func x11_environment_scale() -> float:
	for key: String in ["GDK_SCALE","QT_SCALE_FACTOR"]:
		var text := OS.get_environment(key).strip_edges()
		if text.is_valid_float() and text.to_float() > 0.0:
			return text.to_float()
	return 0.0

## Live backing scale of a screen, before any window exists (first-run defaults).
static func screen_backing(screen: int = -1) -> float:
	var height := DisplayServer.screen_get_size(screen).y if DisplayServer.get_name() == "X11" else 0
	var environment_scale := x11_environment_scale() if DisplayServer.get_name() == "X11" else 0.0
	return backing_from_readings(OS.get_name(),DisplayServer.get_name(),DisplayServer.screen_get_scale(screen),DisplayServer.screen_get_dpi(screen),height,environment_scale)

## Centered placement of a restored window inside the screen's usable area.
## Sizes and positions are the client area's, as Window.size/position are;
## `frame_offset` is where the client sits inside the decorated frame
## (position - position_with_decorations) and `frame_extra` the frame's added
## size (size_with_decorations - size). Windows and X11 draw the title bar
## outside the client area, so the decorated frame is what must fit and center.
static func centered_window_rect(window_px: Vector2i, usable_px: Rect2i, frame_offset: Vector2i = Vector2i.ZERO, frame_extra: Vector2i = Vector2i.ZERO) -> Rect2i:
	if usable_px.size.x <= 0 or usable_px.size.y <= 0:
		return Rect2i(Vector2i.ZERO,window_px)
	var extra := frame_extra.max(Vector2i.ZERO)
	var offset := frame_offset.clamp(Vector2i.ZERO,extra)
	var size := window_px.min((usable_px.size - extra).max(Vector2i.ONE))
	var outer := usable_px.position + (usable_px.size - (size + extra)) / 2
	return Rect2i(outer + offset,size)

static func fit_window_rect(rect: Rect2, available: Rect2, title_height: float) -> Rect2:
	var inset := available.grow(-8.0)
	if inset.size.x <= 0 or inset.size.y <= 0:
		return available
	var fitted := Rect2(rect.position,Vector2(minf(rect.size.x,inset.size.x),minf(rect.size.y,inset.size.y)))
	fitted.size.y = minf(inset.size.y,maxf(title_height,fitted.size.y))
	fitted.position.x = clampf(fitted.position.x,inset.position.x,inset.end.x-fitted.size.x)
	fitted.position.y = clampf(fitted.position.y,inset.position.y,inset.end.y-fitted.size.y)
	return fitted

static func clamp_caption_rect(rect: Rect2, available: Rect2, margin: float = 8.0) -> Rect2:
	var inset := available.grow(-margin)
	if inset.size.x <= 0 or inset.size.y <= 0:
		return available
	var result := Rect2(rect.position,rect.size.min(inset.size.max(Vector2.ZERO)))
	result.position = result.position.clamp(inset.position,inset.end-result.size)
	return result

func bind(window: Window) -> void:
	_disconnect_popup_index()
	if is_instance_valid(_window):
		if _window.size_changed.is_connected(_schedule_refresh):
			_window.size_changed.disconnect(_schedule_refresh)
		if _window.focus_exited.is_connected(_cancel_drag):
			_window.focus_exited.disconnect(_cancel_drag)
	_window = window
	_window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_window.content_scale_size = Vector2i.ZERO
	_window.size_changed.connect(_schedule_refresh)
	_window.focus_exited.connect(_cancel_drag)
	_connect_popup_index()
	set_process(true)
	refresh_metrics()

func _enter_tree() -> void:
	if is_instance_valid(_window):
		_connect_popup_index()

func _exit_tree() -> void:
	_disconnect_popup_index()

func _connect_popup_index() -> void:
	if not is_inside_tree() or not is_instance_valid(_window):
		return
	_popup_candidates.clear()
	_collect_popup_candidates(_window)
	var tree := get_tree()
	if not tree.node_added.is_connected(_on_scene_node_added):
		tree.node_added.connect(_on_scene_node_added)
	if not tree.node_removed.is_connected(_on_scene_node_removed):
		tree.node_removed.connect(_on_scene_node_removed)

func _disconnect_popup_index() -> void:
	if is_inside_tree():
		var tree := get_tree()
		if tree.node_added.is_connected(_on_scene_node_added):
			tree.node_added.disconnect(_on_scene_node_added)
		if tree.node_removed.is_connected(_on_scene_node_removed):
			tree.node_removed.disconnect(_on_scene_node_removed)
	_popup_candidates.clear()

func _collect_popup_candidates(node: Node) -> void:
	for child in node.get_children(true):
		if child is Window:
			_popup_candidates.append(weakref(child))
		_collect_popup_candidates(child)

func _on_scene_node_added(node: Node) -> void:
	if node is Window and is_instance_valid(_window) and _is_descendant_of(node,_window):
		_popup_candidates.append(weakref(node))

func _on_scene_node_removed(node: Node) -> void:
	if not node is Window:
		return
	for i in range(_popup_candidates.size() - 1,-1,-1):
		var candidate: Window = _popup_candidates[i].get_ref() as Window
		if candidate == null or candidate == node:
			_popup_candidates.remove_at(i)

func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent == ancestor:
			return true
		parent = parent.get_parent()
	return false

## Called only for startup/restoration. Runtime UI scale never resizes the OS window.
func restore_window(values: Dictionary) -> void:
	var clean := ViewPreferences.sanitize(values)
	ui_scale = clean["ui_scale"]
	windowed_size = clean["windowed_size"]
	if _window != null and not _mobile:
		var backing := _backing()
		var usable := DisplayServer.screen_get_usable_rect(_window.current_screen)
		if usable.size.x > 0 and usable.size.y > 0:
			# The OS centered the project's default size; recenter the restored
			# size so no edge or title bar starts outside the usable area.
			var frame_extra := _window.get_size_with_decorations() - _window.size
			var frame_offset := _window.position - _window.get_position_with_decorations()
			var placed := centered_window_rect(Vector2i(windowed_size * backing),usable,frame_offset,frame_extra)
			_window.size = placed.size
			_window.position = placed.position
		else:
			_window.size = Vector2i(windowed_size * backing)
		# Fullscreen returns to the maximized window it was entered from.
		maximized = bool(clean.get("maximized",false))
		if maximized and not bool(clean["fullscreen"]):
			_window.mode = Window.MODE_MAXIMIZED
	set_fullscreen(clean["fullscreen"])
	if _injected and not metrics.is_empty():
		_update(metrics["drawable_size"],metrics["backing_scale"])
	else:
		refresh_metrics()

func set_ui_scale(percent: int) -> void:
	ui_scale = percent if percent in SCALES else 0
	if _injected and not metrics.is_empty():
		_update(metrics["drawable_size"],metrics["backing_scale"])
	else:
		refresh_metrics()

func set_fullscreen(enabled: bool) -> void:
	if _mobile:
		fullscreen = false
		return
	if enabled == fullscreen:
		return
	fullscreen = enabled
	if _window != null:
		# Leaving fullscreen returns to the maximized or windowed state it was
		# entered from; `maximized` keeps that state while fullscreen.
		_window.mode = Window.MODE_FULLSCREEN if enabled else restored_mode()
		if not enabled and not maximized:
			_window.size = Vector2i(windowed_size * _backing())
	_schedule_refresh()

## The window state a minimized (or fullscreen-ending) window returns to.
func restored_mode() -> int:
	if fullscreen: return Window.MODE_FULLSCREEN
	return Window.MODE_MAXIMIZED if maximized else Window.MODE_WINDOWED

## The OS window mode; `mode_override` (>= 0) stands in for it in tests, since
## headless windows cannot be minimized.
var mode_override := -1
func window_mode() -> int:
	if mode_override >= 0: return mode_override
	return _window.mode if _window != null else Window.MODE_WINDOWED

## Bring a minimized desktop window back to its remembered state so a prompt
## queued for it (the save question on quit) can be seen. Returns the mode it
## restored, or -1 when the window was not minimized.
func restore_from_minimized() -> int:
	if _window == null or _mobile or window_mode() != Window.MODE_MINIMIZED:
		return -1
	var target := restored_mode()
	_window.mode = target
	if mode_override >= 0: mode_override = target
	return target

func _backing() -> float:
	if _window == null:
		return 1.0
	return screen_backing(_window.current_screen)

func _process(_delta: float) -> void:
	if _window == null or _injected:
		return
	var backing := _backing()
	var readings: Dictionary = PLATFORM.display_readings(_window)
	if _last_screen != _window.current_screen or not is_equal_approx(_last_backing,backing) or _last_mode != _window.mode or readings.safe_area_px != _safe_area_px or readings.keyboard_height_px != _keyboard_height_px:
		_last_screen = _window.current_screen
		_last_backing = backing
		_last_mode = _window.mode
		_schedule_refresh()

func _schedule_refresh() -> void:
	if _pending or not is_inside_tree():
		return
	_pending = true
	call_deferred("_refresh_deferred")
func _refresh_deferred() -> void:
	_pending = false
	refresh_metrics()

func refresh_metrics() -> void:
	if _window == null or _injected:
		return
	var readings: Dictionary = PLATFORM.display_readings(_window)
	_mobile = readings.mobile
	_safe_area_px = readings.safe_area_px
	_keyboard_height_px = readings.keyboard_height_px
	var mode := window_mode()
	# A minimized window's drawable says nothing about the window the player
	# restores to: keep the last fullscreen/maximized state, restore size and metrics.
	if not _mobile and mode == Window.MODE_MINIMIZED:
		return
	fullscreen = not _mobile and mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN]
	# While fullscreen, `maximized` keeps the state fullscreen returns to.
	if not fullscreen:
		maximized = not _mobile and mode == Window.MODE_MAXIMIZED
	var backing := _backing()
	_apply_min_size(backing)
	_update(_window.size,backing)

## Desktop OS windows cannot shrink below 640×400 points at the current backing
## scale. Headless/injected/mobile windows keep their size (tests and iOS).
func _apply_min_size(backing: float) -> void:
	if _window == null or _mobile or _injected or DisplayServer.get_name() == "headless":
		return
	var minimum := Vector2i((MIN_WINDOW_POINTS * backing).ceil())
	if _window.min_size != minimum:
		_window.min_size = minimum

## Injectable display readings allow deterministic DPI/fullscreen tests.
func refresh_with_metrics(drawable_px: Vector2i, backing_scale: float, safe_area_px: Rect2i = Rect2i(), keyboard_height_px: int = 0, mobile: bool = false) -> void:
	_injected = true
	_mobile = mobile
	_safe_area_px = safe_area_px
	_keyboard_height_px = keyboard_height_px
	_update(drawable_px,backing_scale)

func refresh_with_mobile_metrics(drawable_px: Vector2i, backing_scale: float, safe_area_px: Rect2i, keyboard_height_px: int = 0) -> void:
	refresh_with_metrics(drawable_px,backing_scale,safe_area_px,keyboard_height_px,true)

func _update(drawable_px: Vector2i, backing_scale: float) -> void:
	var next := resolve_scale(drawable_px,backing_scale,ui_scale,_safe_area_px,_keyboard_height_px,_mobile)
	if next.is_empty():
		return
	# A maximized or fullscreen drawable is not the size to restore later.
	if not fullscreen and not maximized and not _mobile:
		windowed_size = Vector2(drawable_px) / float(next["backing_scale"])
	if _window != null:
		_window.content_scale_factor = float(next["scale"])
	var changed := next != metrics
	metrics = next
	if changed:
		WindowDrag.cancel_all()
		_fit_registered()
		for popup in _popups.duplicate():
			if not is_instance_valid(popup):
				_popups.erase(popup)
			elif popup.visible:
				apply_popup(popup)
		metrics_changed.emit(metrics)

func logical_rect() -> Rect2:
	return metrics.get("logical_rect",Rect2(0,0,1280,800))
func drawable_size() -> Vector2i:
	return metrics.get("drawable_size",Vector2i(1280,800))
func ui_to_drawable(point: Vector2) -> Vector2:
	return point * float(metrics.get("scale",1.0))
func drawable_to_ui(point: Vector2) -> Vector2:
	return point / float(metrics.get("scale",1.0))
func register_window(chrome: Dictionary, preferred_size: Vector2) -> void:
	for old in _registered:
		if old["root"] == chrome["root"]:
			return
	var entry := chrome.duplicate()
	entry["preferred_size"] = preferred_size
	(chrome["root"] as Control).set_meta("preferred_size",preferred_size)
	_registered.append(entry)
	_fit_registered()
func _fit_registered() -> void:
	for entry in _registered:
		var panel: Control = entry["root"]
		if not is_instance_valid(panel):
			continue
		var preferred: Vector2 = entry["preferred_size"]
		panel.set_meta("display_usable_rect",logical_rect())
		var rect := fit_window_rect(Rect2(panel.position,preferred),logical_rect(),44.0)
		panel.position = rect.position
		panel.size = rect.size

func register_popup(popup: Window) -> void:
	if popup in _popups:
		return
	_popups.append(popup)
	popup.about_to_popup.connect(func() -> void:
		apply_popup(popup)
		# Window.popup applies its requested geometry after about_to_popup.
		_fit_open_popup.call_deferred(popup))
	popup.size_changed.connect(func() -> void:
		if not _applying_popups and popup.visible and not popup.is_embedded():
			var previous_scale: float = popup.get_meta("display_applied_scale",popup.content_scale_factor)
			popup.set_meta("display_logical_size",Vector2(popup.size) / previous_scale)
			popup.set_meta("display_applied_size",popup.size))
	if popup.visible:
		apply_popup(popup)

func _fit_open_popup(popup: Window) -> void:
	if is_instance_valid(popup) and popup.visible:
		apply_popup(popup)

func apply_popup(popup: Window) -> void:
	_applying_popups = true
	if popup.is_embedded():
		popup.content_scale_factor = 1.0
		if popup is PopupMenu:
			# The menu's internal scroll container needs a height limit before
			# Window.size can fit a long list with touch-sized rows.
			var original_max: Vector2i = popup.get_meta("display_original_max_size", popup.max_size)
			popup.set_meta("display_original_max_size", original_max)
			var available_max := Vector2i(logical_rect().size - Vector2(16, 16))
			var fitted_max := Vector2i(mini(original_max.x, available_max.x) if original_max.x > 0 else available_max.x, mini(original_max.y, available_max.y) if original_max.y > 0 else available_max.y)
			# PopupMenu caches its content minimum when opening. An already-open
			# menu must lower that minimum as well when its display shrinks.
			popup.min_size = popup.min_size.min(fitted_max)
			popup.max_size = fitted_max
		var fitted := clamp_caption_rect(Rect2(Vector2(popup.position),Vector2(popup.size)),logical_rect())
		popup.position = Vector2i(fitted.position)
		popup.size = Vector2i(fitted.size)
	else:
		var scale := float(metrics.get("scale",_backing()))
		var logical_size: Vector2 = popup.get_meta("display_logical_size",Vector2(popup.size))
		var last_size: Vector2i = popup.get_meta("display_applied_size",Vector2i.ZERO)
		if last_size != popup.size:
			logical_size = Vector2(popup.size)
		popup.set_meta("display_logical_size",logical_size)
		var usable := DisplayServer.screen_get_usable_rect(_window.current_screen if _window != null else -1)
		var available := Rect2(usable) if usable.size.x > 0 and usable.size.y > 0 else Rect2(Vector2.ZERO,Vector2(drawable_size()))
		if _mobile:
			available = Rect2(metrics.get("usable_rect_px",Rect2i(Vector2i.ZERO,drawable_size())))
			if _window != null:
				available.position += Vector2(_window.position)
		var fitted := clamp_caption_rect(Rect2(Vector2(popup.position),logical_size * scale),available)
		popup.content_scale_factor = scale
		popup.position = Vector2i(fitted.position)
		popup.size = Vector2i(fitted.size)
		popup.set_meta("display_applied_size",popup.size)
		popup.set_meta("display_applied_scale",scale)
	_applying_popups = false

## A focused toolbar or Resume button owns keyboard shortcuts, but it cannot
## own a different finger's contact in the city. Popup/drag/focus loss do.
func blocks_city_touch() -> bool:
	if WindowDrag.is_dragging(): return true
	if not is_instance_valid(_window): return false
	return _has_popup(_window) or (DisplayServer.get_name() != "headless" and not _window.has_focus())

func blocks_city_keyboard() -> bool:
	if not is_instance_valid(_window):
		return WindowDrag.is_dragging()
	return keyboard_is_blocked(_window.gui_get_focus_owner(),_has_popup(_window),WindowDrag.is_dragging(),_window.has_focus() or DisplayServer.get_name() == "headless")

func _has_popup(node: Node) -> bool:
	for i in range(_popup_candidates.size() - 1,-1,-1):
		var candidate := _popup_candidates[i].get_ref() as Window
		if not is_instance_valid(candidate):
			_popup_candidates.remove_at(i)
		elif candidate.visible and _is_descendant_of(candidate,node):
			return true
	return false
func release_city_focus() -> void:
	if _window != null:
		var focus := _window.gui_get_focus_owner()
		if focus != null:
			focus.release_focus()

func _cancel_drag() -> void:
	WindowDrag.cancel_all()

static func keyboard_is_blocked(focused_control: Control, has_popup: bool, dragging: bool, window_active: bool) -> bool:
	return not window_active or has_popup or dragging or (focused_control != null and focused_control.is_visible_in_tree())
