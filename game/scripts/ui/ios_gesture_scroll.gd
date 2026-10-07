# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Swipe-and-glide scrolling for ScrollContainer and ItemList on iOS. A drag
## anywhere in the scroll body, including over buttons, moves the content; a
## clean tap is replayed to the control under the finger. Text fields, sliders
## and nested scrolls keep their own handling.
class_name IOSGestureScroll
extends Node

const DEADZONE := 8.0
const DECELERATION := 1800.0
var _scroll: Control
var _finger := -1
var _origin := Vector2.ZERO
var _previous := Vector2.ZERO
var _dragged := false
var _velocity := Vector2.ZERO
var _last_motion := 0
var _double_tap := false
var _epoch := 0
var _tap_control: WeakRef
var _tap_local := Vector2.ZERO
## Gesture nodes currently in the tree. One shared tree listener routes each
## new node to the gestures above it instead of every gesture hearing every node.
static var _live := 0

static func install_tree(host: Node) -> void:
	if not MobilePlatform.is_ios() or host.has_node("IOSScrollRegistry"): return
	var registry := Registry.new()
	registry.name = "IOSScrollRegistry"
	host.add_child(registry)

static func _install(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree() or control.is_queued_for_deletion() or control.has_node("IOSGestureScroll"): return
	# PopupMenu processes window input before GUI signals, so its internal
	# ScrollContainer is left to Godot's own menu handling and touch scrolling.
	if control.get_window() is PopupMenu: return
	var gesture := IOSGestureScroll.new()
	gesture.name = "IOSGestureScroll"
	control.add_child(gesture)

static func _install_weak(target: WeakRef) -> void:
	var control := target.get_ref() as Control
	if control != null: _install(control)

class Registry:
	extends Node
	func _ready() -> void:
		get_tree().node_added.connect(_added)
		_scan(get_parent())
	func _scan(node: Node) -> void:
		if node is ScrollContainer or node is ItemList: IOSGestureScroll._install(node)
		for child: Node in node.get_children(true): _scan(child)
	func _added(node: Node) -> void:
		if get_parent().is_ancestor_of(node) and (node is ScrollContainer or node is ItemList):
			IOSGestureScroll._install_weak.call_deferred(weakref(node))

func _ready() -> void:
	_scroll = get_parent() as Control
	_scroll.visibility_changed.connect(_visibility_changed)
	_scroll.resized.connect(_cancel_scroll)
	if not get_tree().node_added.is_connected(IOSGestureScroll._route_added):
		get_tree().node_added.connect(IOSGestureScroll._route_added)
	_bind(_scroll)
	set_process(false)

func _enter_tree() -> void:
	_live += 1

func _exit_tree() -> void:
	_live -= 1

## Offer a new node to each gesture whose scroll contains it. A gesture never
## binds through an inner ScrollContainer or ItemList (see _bind), so the walk
## stops there; that scroll's own gesture, if any, is the last asked.
static func _route_added(node: Node) -> void:
	if _live <= 0: return
	var ancestor := node.get_parent()
	while ancestor != null:
		var gesture := ancestor.get_node_or_null(^"IOSGestureScroll") as IOSGestureScroll
		if gesture != null and gesture._scroll == ancestor: gesture._bind_weak.call_deferred(weakref(node))
		if ancestor is ScrollContainer or ancestor is ItemList: return
		ancestor = ancestor.get_parent()

func _bind_weak(target: WeakRef) -> void:
	var node := target.get_ref() as Node
	if node != null: _bind(node)

func _bind(node: Node) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion(): return
	if node is Window: return
	if node != _scroll:
		var ancestor := node.get_parent()
		while ancestor != null and ancestor != _scroll:
			if ancestor is ScrollContainer or ancestor is ItemList or ancestor is Range or ancestor is LineEdit or ancestor is TextEdit or ancestor.get_meta("owns_pointer_gestures", false): return
			ancestor = ancestor.get_parent()
		if ancestor != _scroll: return
	# The innermost scrolling control handles the contact. Editable fields and
	# sliders keep their own text-selection and value-drag interaction.
	if node != _scroll and (node is ScrollContainer or node is ItemList or node is Range or node is LineEdit or node is TextEdit or node.get_meta("owns_pointer_gestures", false)): return
	if node is Control:
		var callback := _route.bind(node)
		if not node.gui_input.is_connected(callback): node.gui_input.connect(callback)
	for child: Node in node.get_children(true): _bind(child)

func _route(event: InputEvent, control: Control) -> void:
	# Godot dispatches the synthesized mouse event BEFORE the raw touch event.
	# Suppress it even before a finger is registered, so only a completed tap
	# reaches the native control and a swipe cannot select on finger down.
	if event.device == InputEvent.DEVICE_ID_EMULATION and event is InputEventMouse:
		control.accept_event()
		return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag): return
	var transform := _scroll.get_global_transform_with_canvas().affine_inverse()*control.get_global_transform_with_canvas()
	var at: Vector2 = transform*event.position
	control.accept_event()
	if event is InputEventScreenTouch:
		if event.pressed:
			if _finger != -1: return
			_cancel_scroll()
			_finger = event.index
			_origin = at
			_previous = at
			_double_tap = event.double_tap
			_tap_control = weakref(control)
			_tap_local = event.position
		elif event.index == _finger:
			var tap: bool = not _dragged and not event.canceled and Rect2(Vector2.ZERO,_scroll.size).has_point(at) and Rect2(Vector2.ZERO,control.size).has_point(event.position)
			_finger = -1
			if event.canceled:
				_cancel_scroll()
			elif tap:
				_replay_tap.call_deferred(_tap_control,_tap_local,_double_tap,_epoch)
			else:
				if Time.get_ticks_msec()-_last_motion > 100: _velocity = Vector2.ZERO
				set_process(not _velocity.is_zero_approx())
	elif event.index == _finger:
		if not _dragged and at.distance_to(_origin) <= DEADZONE: return
		var motion: Vector2 = at-_previous
		_previous = at
		_dragged = true
		var now := Time.get_ticks_msec()
		var velocity: Vector2 = transform.basis_xform(event.velocity)
		_velocity = -velocity if not velocity.is_zero_approx() else -motion/maxf(float(now-_last_motion)/1000.0,1.0/120.0)
		_last_motion = now
		_scroll_by(-motion)

func _replay_tap(target: WeakRef, at: Vector2, double_tap: bool, epoch: int) -> void:
	var control := target.get_ref() as Control
	if epoch != _epoch or not is_instance_valid(control) or not control.is_visible_in_tree() or control.is_queued_for_deletion(): return
	for pressed: bool in [true,false]:
		if not is_instance_valid(control) or not control.is_visible_in_tree() or control.is_queued_for_deletion(): break
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.double_click = double_tap and pressed
		event.position = control.get_global_transform_with_canvas()*at
		event.global_position = event.position
		# The canvas transform produces viewport-local coordinates. Applying
		# window localization again divides by the iOS backing/UI scale twice.
		control.get_viewport().push_input(event,true)

func _scroll_by(amount: Vector2) -> void:
	var h: HScrollBar = _scroll.get_h_scroll_bar()
	var v: VScrollBar = _scroll.get_v_scroll_bar()
	var before := Vector2(h.value,v.value)
	if not _scroll is ScrollContainer or _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED: h.value += amount.x
	if not _scroll is ScrollContainer or _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED: v.value += amount.y
	if is_equal_approx(h.value,before.x): _velocity.x = 0.0
	if is_equal_approx(v.value,before.y): _velocity.y = 0.0

func _process(delta: float) -> void:
	_scroll_by(_velocity*delta)
	_velocity = _velocity.move_toward(Vector2.ZERO,DECELERATION*delta)
	if _velocity.is_zero_approx(): set_process(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: _cancel_scroll()

func _visibility_changed() -> void:
	if not _scroll.is_visible_in_tree(): _cancel_scroll()

func _cancel_scroll() -> void:
	_epoch += 1
	_finger = -1
	_dragged = false
	_velocity = Vector2.ZERO
	_last_motion = Time.get_ticks_msec()
	set_process(false)
