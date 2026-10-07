# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## On-screen Explore controls for touch: a movement pad, a look area and
## action buttons. Each finger belongs to the one control it touched first.
## Events arrive in logical viewport coordinates; screen_relative stays
## unscaled for camera aiming. The controls produce input frames rather than
## simulated key presses.
class_name ExploreTouchControls
extends Control

signal menu_requested

const PAD_SIZE := 132.0
const PAD_RADIUS := 48.0
const DEAD_ZONE := .08
var _enabled := false
var _active := false
var _suspended := false
var _mode := ExploreActorProfile.Mode.WALK
var _usable := Rect2(0,0,1280,800)
var _contacts: Dictionary = {}
var _quarantined := false
var _move := Vector2.ZERO
var _look := Vector2.ZERO
var _edges: Dictionary = {}
var _rects: Dictionary = {}
var _buttons: Dictionary = {}
var _move_label: Label
var _look_label: Label
var _pad_size := PAD_SIZE
var _pad_radius := PAD_RADIUS
var _status_rect := Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for action: StringName in [&"menu",&"sprint",&"jump",&"brake",&"interact",&"ascend",&"descend"]:
		var button := UIFactory.make_button(_caption(action))
		button.name = "Touch"+str(action).capitalize()
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		# All touch buttons share the finger router, so Godot's single emulated
		# mouse cannot release a second finger's held action or start an orbit.
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if action==&"menu":
			button.mouse_filter=Control.MOUSE_FILTER_STOP
			button.pressed.connect(func() -> void:
				button.set_pressed_no_signal(false)
				menu_requested.emit())
		add_child(button)
		_buttons[action]=button
	_move_label=_make_world_caption("Move")
	add_child(_move_label)
	_look_label=_make_world_caption("Drag to look")
	add_child(_look_label)
	_refresh()

func set_enabled(on: bool) -> void:
	if _enabled == on: return
	clear_input()
	_enabled=on
	_refresh()

func set_session_active(on: bool) -> void:
	if _active == on: return
	clear_input()
	_active=on
	_refresh()

func set_suspended(on: bool) -> void:
	if _suspended == on: return
	clear_input()
	_suspended=on
	_refresh()

func set_mode(value: int) -> void:
	var next := clampi(value,0,2)
	if next == _mode: return
	clear_input()
	_mode=next
	_refresh()

func set_usable_rect(rect: Rect2) -> void:
	if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x<=0 or rect.size.y<=0: return
	if rect == _usable: return
	clear_input()
	_usable=rect
	_refresh()

func set_status_rect(rect: Rect2) -> void:
	if _status_rect == rect: return
	_status_rect = rect
	_refresh()

## Clear all input. Fingers already down stay blocked until they lift.
func clear_input() -> void:
	_move=Vector2.ZERO
	_look=Vector2.ZERO
	_edges.clear()
	for id: int in _contacts:
		_contacts[id]={"role":&"blocked","position":_contacts[id].position,"engaged":false}
	_quarantined=not _contacts.is_empty()
	_sync_action_feedback()
	queue_redraw()

func is_waiting_for_release() -> bool:
	return _quarantined

func control_rect(action: StringName) -> Rect2:
	return _rects.get(action,Rect2())

func handle_event(event: InputEvent, ui_blocked: bool = false) -> bool:
	if event is InputEventScreenTouch:
		var contact := event as InputEventScreenTouch
		if contact.canceled:
			_contacts.erase(contact.index)
			clear_input()
			return _active
		if not contact.pressed:
			var old: Dictionary = _contacts.get(contact.index,{})
			_contacts.erase(contact.index)
			if old.get("role",&"")==&"move": _move=Vector2.ZERO
			if _contacts.is_empty(): _quarantined=false
			if old.get("role",&"")==&"menu" and bool(old.get("engaged",false)) and control_rect(&"menu").has_point(contact.position):
				clear_input()
				menu_requested.emit()
			_sync_action_feedback()
			queue_redraw()
			return _active and not old.is_empty() and old.get("role",&"blocked")!=&"blocked"
		if _contacts.has(contact.index): return _active
		var role: StringName = &"blocked"
		if _enabled and _active and not _suspended and not _quarantined and not ui_blocked:
			role=_role_at(contact.position)
		_contacts[contact.index]={"role":role,"position":contact.position,"engaged":true}
		if role in [&"jump",&"interact"]: _edges[role]=true
		if role==&"move": _update_move(contact.position)
		_sync_action_feedback()
		queue_redraw()
		return _active and role!=&"blocked"
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _contacts.has(drag.index): return false
		var entry: Dictionary = _contacts[drag.index]
		var role: StringName = entry.role
		entry.position=drag.position
		if not _enabled or _suspended or _quarantined or not _active or role==&"blocked": return false
		if role==&"move": _update_move(drag.position)
		elif role==&"look":
			if drag.screen_relative.is_finite(): _look+=drag.screen_relative
		else: entry.engaged=control_rect(role).has_point(drag.position)
		_sync_action_feedback()
		queue_redraw()
		return true
	return false

func sample_frame() -> ExploreInputFrame:
	var frame := ExploreInputFrame.idle()
	if not _enabled or not _active or _suspended or _quarantined: return frame
	frame.move=_move
	frame.sprint=_held(&"sprint")
	frame.brake=_held(&"brake")
	frame.vertical=float(int(_held(&"ascend"))-int(_held(&"descend")))
	frame.jump=bool(_edges.get(&"jump",false))
	frame.interact=bool(_edges.get(&"interact",false))
	_edges.clear()
	return frame

func take_look_delta() -> Vector2:
	var result := _look
	_look=Vector2.ZERO
	return result

func _held(action: StringName) -> bool:
	for entry: Dictionary in _contacts.values():
		if entry.role==action and bool(entry.engaged): return true
	return false

## Render from the router's owners, never from Godot's single emulated mouse.
## Edge actions remain visibly held even after their one-frame edge is sampled.
func _sync_action_feedback() -> void:
	var accepting := _enabled and _active and not _suspended and not _quarantined
	for action: StringName in _buttons:
		(_buttons[action] as Button).set_pressed_no_signal(accepting and _held(action))

func _make_world_caption(text: String) -> Label:
	var label := UIFactory.make_label(text,UITheme.FONT_BODY,UITheme.TITLE_TEXT)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var backing := UITheme.button_stylebox(true)
	backing.bg_color=UITheme.TITLE_BAR_DARK
	backing.bg_color.a=.94
	backing.border_color=UITheme.ACCENT_BRASS
	backing.content_margin_left=6
	backing.content_margin_right=6
	backing.content_margin_top=2
	backing.content_margin_bottom=2
	label.add_theme_stylebox_override("normal",backing)
	return label

func _role_at(at: Vector2) -> StringName:
	if not _usable.has_point(at): return &"blocked"
	for action: StringName in _rects:
		if _rects[action].has_point(at):
			if action==&"move" or action==&"menu" or action in _mode_actions():
				for entry: Dictionary in _contacts.values():
					if entry.role==action: return &"blocked"
				return action
	if at.x>=_usable.get_center().x:
		for entry: Dictionary in _contacts.values():
			if entry.role==&"look": return &"blocked"
		return &"look"
	return &"blocked"

func _update_move(at: Vector2) -> void:
	_move=((at-control_rect(&"move").get_center())/_pad_radius).limit_length(1.0)
	if _move.length()<DEAD_ZONE: _move=Vector2.ZERO

func _mode_actions() -> Array[StringName]:
	if _mode==ExploreActorProfile.Mode.DRIVE: return [&"brake",&"interact"]
	if _mode==ExploreActorProfile.Mode.FLY: return [&"ascend",&"descend",&"interact"]
	return [&"sprint",&"jump",&"interact"]

func _refresh() -> void:
	visible=_enabled and _active
	_rects.clear()
	var short := _usable.size.y < 360.0
	_pad_size = 108.0 if short else PAD_SIZE
	_pad_radius = 40.0 if short else PAD_RADIUS
	_rects[&"menu"]=Rect2(_usable.position+Vector2(_usable.size.x-104,8),Vector2(96,48))
	_rects[&"move"]=Rect2(Vector2(_usable.position.x+16,_usable.end.y-_pad_size-16),Vector2(_pad_size,_pad_size))
	var right := _usable.end-Vector2(108,64)
	_rects[&"interact"]=Rect2(right,Vector2(100,48))
	var actions := _mode_actions()
	for index: int in actions.size()-1:
		_rects[actions[index]]=Rect2(right-Vector2(0,56*(index+1)),Vector2(100,48))
	if short:
		for index in actions.size():
			var at := Vector2(_usable.end.x-8.0-float(actions.size()-index)*92.0,_usable.end.y-60.0)
			if _usable.size.x < 440.0:
				var rows := ceili(float(actions.size())/2.0)
				var column := index%2 if index<2 else 1
				at = Vector2(_usable.end.x-184.0+float(column)*92.0,_usable.end.y-16.0-float(rows)*52.0+8.0+float(index/2)*52.0)
			_rects[actions[index]] = Rect2(at,Vector2(84,44))
	for action: StringName in _buttons:
		var button: Button = _buttons[action]
		button.visible=action==&"menu" or (action in actions and not _suspended)
		button.disabled=_suspended
		if _rects.has(action):
			button.position=_rects[action].position
			button.size=_rects[action].size
	if is_instance_valid(_move_label):
		_move_label.text=["Move","Throttle / steer","Fly"][_mode]
		_move_label.position=control_rect(&"move").position-Vector2(0,32)
		_move_label.size=Vector2(_pad_size,28)
		if _move_label.get_rect().intersects(_status_rect):
			_move_label.position.y = control_rect(&"move").position.y+8.0
		_move_label.visible=not _suspended
		var look_width := minf(200,_usable.size.x*.5-16)
		_look_label.position=Vector2(_usable.get_center().x+(_usable.size.x*.5-16-look_width)*.5,_usable.position.y+64)
		_look_label.size=Vector2(look_width,28)
		if _look_label.get_rect().intersects(_status_rect):
			_look_label.position.y = _status_rect.end.y+8.0
		_look_label.visible=not _suspended
	_sync_action_feedback()
	queue_redraw()

func _caption(action: StringName) -> String:
	return {&"menu":"Menu",&"sprint":"Sprint",&"jump":"Jump",&"brake":"Brake",&"interact":"Interact",&"ascend":"Climb",&"descend":"Descend"}.get(action,str(action))

func _draw() -> void:
	if not visible or _suspended: return
	var center := control_rect(&"move").get_center()
	draw_circle(center,_pad_size*.5,Color(.08,.10,.12,.46))
	draw_arc(center,_pad_radius,0,TAU,48,Color(.90,.86,.72,.7),2,true)
	draw_line(center-Vector2(0,10),center+Vector2(0,10),Color(.9,.86,.72,.5),2,true)
	draw_line(center-Vector2(10,0),center+Vector2(10,0),Color(.9,.86,.72,.5),2,true)
	draw_circle(center+_move*_pad_radius,20,Color(.92,.86,.68,.86))
