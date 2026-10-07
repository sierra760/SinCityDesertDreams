# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Ownership survives GUI consumption: an ignored UI finger still takes part in
## cancellation, but can never become a city construction/navigation finger.
class_name CityBuildGestures
extends RefCounted

## Naming opts into taps; construction and Query keep the default routing.
const TAP_SLOP := 12.0
var tap_only := false
var _tap_origin := Vector2.ZERO
var _fingers: Dictionary = {}
var _drawing := -1
var _latched := false
var _pair: Array[int] = []
var _centroid := Vector2.ZERO
var _distance := 0.0

## Keep held fingers registered so a resize/modal cannot turn their release
## into a commit, nor turn the remaining navigation finger into construction.
func cancel() -> bool:
	var was_drawing := _drawing >= 0
	_drawing = -1
	_latched = not _fingers.is_empty()
	_pair.clear()
	_distance = 0.0
	return was_drawing

func handle(event: InputEvent, ui_owned: bool, blocked: bool) -> Dictionary:
	var action: Dictionary = {}
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return action
	var index: int = event.index
	var known := _fingers.has(index)
	var city_owned := known and bool(_fingers[index].city)
	action["handled"] = city_owned
	if blocked and cancel():
		action["cancel"] = true
	if event is InputEventScreenTouch:
		if event.canceled:
			if cancel(): action["cancel"] = true
			_fingers.erase(index)
			_finish_release()
			return action
		if event.pressed:
			if known: return action
			_fingers[index] = {"position":event.position, "city":not ui_owned and not blocked, "over_ui":ui_owned}
			action["handled"] = not ui_owned and not blocked
			if _fingers.size() == 1 and not _latched and not ui_owned and not blocked:
				_drawing = index
				_tap_origin = event.position
				action["begin"] = event.position
			else:
				if cancel(): action["cancel"] = true
				_latched = true
			_update_pair(blocked)
		else:
			if known and _drawing == index:
				if blocked or ui_owned or (tap_only and event.position.distance_to(_tap_origin) > TAP_SLOP):
					if cancel(): action["cancel"] = true
				else:
					_drawing = -1
					action["commit"] = event.position
			_fingers.erase(index)
			_finish_release()
			_update_pair(blocked)
	elif known:
		_fingers[index].position = event.position
		_fingers[index].over_ui = ui_owned
		if ui_owned and cancel(): action["cancel"] = true
		if tap_only and _drawing == index and event.position.distance_to(_tap_origin) > TAP_SLOP:
			if cancel(): action["cancel"] = true
		if _drawing == index and not blocked:
			action["update"] = event.position
		elif _update_pair(blocked):
			var a: Vector2 = _fingers[_pair[0]].position
			var b: Vector2 = _fingers[_pair[1]].position
			var next_centroid := (a + b) * 0.5
			var next_distance := a.distance_to(b)
			action["pan"] = next_centroid - _centroid
			# Closely overlapping contacts have no stable pinch ratio.
			if _distance >= 24.0 and next_distance >= 24.0:
				action["zoom"] = next_distance / _distance
			_centroid = next_centroid
			_distance = next_distance
	return action

func _finish_release() -> void:
	if _fingers.is_empty():
		_latched = false
		_drawing = -1
		_pair.clear()
		_distance = 0.0

## Return true only when the same eligible pair already had a baseline.
func _update_pair(blocked: bool) -> bool:
	if blocked or not _latched or _fingers.size() != 2:
		_pair.clear()
		return false
	var eligible: Array[int] = []
	for index: int in _fingers:
		if not bool(_fingers[index].city) or bool(_fingers[index].over_ui):
			_pair.clear()
			return false
		eligible.append(index)
	eligible.sort()
	if eligible == _pair: return true
	_pair = eligible
	var a: Vector2 = _fingers[_pair[0]].position
	var b: Vector2 = _fingers[_pair[1]].position
	_centroid = (a + b) * 0.5
	_distance = a.distance_to(b)
	return false
