# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Dragging windows by their title bars, in logical UI coordinates. A dragged
## window stays reachable inside the usable display area; releasing the
## button anywhere, losing window focus or `cancel_all` ends the drag.
class_name WindowDrag
extends RefCounted
static var _states: Array[Dictionary] = []
static func is_dragging() -> bool:
	for state in _states:
		if state["dragging"]:
			return true
	return false
static func cancel_all() -> void:
	for state in _states:
		state["dragging"] = false
static func enable(grab: Control, target: Control, bounds: Callable = Callable()) -> void:
	grab.mouse_filter = Control.MOUSE_FILTER_STOP
	var state := {"dragging":false,"id":grab.get_instance_id()}
	_states.append(state)
	var release_guard := DragReleaseGuard.new()
	release_guard.state = state
	grab.add_child(release_guard)
	grab.tree_exiting.connect(func() -> void: _states.erase(state))
	grab.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			state["dragging"] = event.pressed
		elif event is InputEventMouseMotion and state["dragging"]:
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				state["dragging"] = false
				return
			var available: Rect2 = bounds.call() if bounds.is_valid() else target.get_meta("display_usable_rect",target.get_viewport().get_visible_rect())
			var rect := DisplayLayout.fit_window_rect(Rect2(target.position + event.relative,target.size),available,44.0)
			target.position = rect.position
		grab.accept_event())
	# Containers reflow after viewport changes, so recover moved panels afterwards.
	target.resized.connect(func() -> void:
		if target.is_inside_tree():
			var available: Rect2 = bounds.call() if bounds.is_valid() else target.get_meta("display_usable_rect",target.get_viewport().get_visible_rect())
			var fitted := DisplayLayout.fit_window_rect(Rect2(target.position,target.size),available,44.0)
			if not target.position.is_equal_approx(fitted.position):
				target.position = fitted.position)

class DragReleaseGuard:
	extends Node
	var state: Dictionary
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			state["dragging"] = false
	func _notification(what: int) -> void:
		if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			state["dragging"] = false
