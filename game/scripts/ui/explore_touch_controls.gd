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
var _joystick: VirtualJoystick
var _joystick_viewport: SubViewport
var _joystick_display: TextureRect
var _move_contact := -1
var _move_actions: Array[StringName] = []

func _enter_tree() -> void:
	# A detached HUD can be reused. Restore its private namespace before its
	# children enter, and reset the native control's prior contact ownership.
	for action: StringName in _move_actions:
		if not InputMap.has_action(action): InputMap.add_action(action,0.0)
	if is_instance_valid(_joystick): _joystick.notification(Control.NOTIFICATION_RESIZED)

func _notification(what: int) -> void:
	if what==NOTIFICATION_POST_ENTER_TREE and is_instance_valid(_joystick): _refresh()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_joystick()
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
	_release_joystick()
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
	if not is_inside_tree():
		# Retire fingers lifted during detachment without forwarding input to
		# the native control or accepting new owners outside the scene tree.
		if event is InputEventScreenTouch and (not event.pressed or event.canceled):
			_contacts.erase(event.index)
			if _contacts.is_empty(): _quarantined=false
		return false
	if event is InputEventScreenTouch:
		var contact := event as InputEventScreenTouch
		if contact.canceled:
			_release_joystick()
			_contacts.erase(contact.index)
			clear_input()
			return _active
		if not contact.pressed:
			var old: Dictionary = _contacts.get(contact.index,{})
			_contacts.erase(contact.index)
			if old.get("role",&"")==&"move":
				_release_joystick()
				_move=Vector2.ZERO
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
		if role==&"move":
			_move_contact=contact.index
			_route_joystick(contact)
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
		if role==&"move": _route_joystick(drag)
		elif role==&"look":
			if drag.screen_relative.is_finite(): _look+=drag.screen_relative
		else: entry.engaged=control_rect(role).has_point(drag.position)
		_sync_action_feedback()
		queue_redraw()
		return true
	return false

func sample_frame() -> ExploreInputFrame:
	var frame := ExploreInputFrame.idle()
	if not is_inside_tree() or not _enabled or not _active or _suspended or _quarantined: return frame
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

## The small transparent viewport gives the native control only its owning
## finger. Main consumes Explore touches before normal GUI delivery; forwarding
## here also preserves quarantine and prevents UI-origin fingers acquiring it.
func _build_joystick() -> void:
	for direction: String in ["left","right","up","down"]:
		var action := StringName("explore_touch_%d_%s" % [get_instance_id(),direction])
		InputMap.add_action(action,0.0)
		_move_actions.append(action)
	_joystick_viewport=SubViewport.new()
	_joystick_viewport.name="MovementViewport"
	_joystick_viewport.disable_3d=true
	_joystick_viewport.transparent_bg=true
	_joystick_viewport.size=Vector2i(PAD_SIZE,PAD_SIZE)
	add_child(_joystick_viewport)
	_joystick=VirtualJoystick.new()
	_joystick.name="MovementJoystick"
	_joystick.action_left=_move_actions[0]
	_joystick.action_right=_move_actions[1]
	_joystick.action_up=_move_actions[2]
	_joystick.action_down=_move_actions[3]
	_joystick.focus_mode=Control.FOCUS_NONE
	_joystick.size=Vector2(PAD_SIZE,PAD_SIZE)
	_joystick.tip_size=40.0
	# Keep the existing linear analog response; the router applies the small
	# center dead zone after sampling, without a second InputMap dead zone.
	_joystick.deadzone_ratio=0.0
	for state: String in ["normal","pressed"]:
		var base := StyleBoxFlat.new()
		base.bg_color=Color(.08,.10,.12,.46)
		base.border_color=Color(.90,.86,.72,.7)
		base.set_border_width_all(2)
		base.set_corner_radius_all(100)
		base.anti_aliasing=true
		_joystick.add_theme_stylebox_override(state+"_joystick",base)
		var tip := StyleBoxFlat.new()
		tip.bg_color=Color(.92,.86,.68,.86 if state=="normal" else 1.0)
		tip.set_corner_radius_all(100)
		tip.anti_aliasing=true
		_joystick.add_theme_stylebox_override(state+"_tip",tip)
	_joystick_viewport.add_child(_joystick)
	_joystick_display=TextureRect.new()
	_joystick_display.name="MovementPad"
	_joystick_display.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_joystick_display.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	_joystick_display.texture=_joystick_viewport.get_texture()
	add_child(_joystick_display)

func _route_joystick(event: InputEvent) -> void:
	var local := event.duplicate() as InputEvent
	local.position=event.position-control_rect(&"move").position
	_joystick_viewport.push_input(local,true)
	_move=Vector2(Input.get_axis(_move_actions[0],_move_actions[1]),Input.get_axis(_move_actions[2],_move_actions[3])).limit_length(1.0)
	if _move.length()<DEAD_ZONE: _move=Vector2.ZERO

func _release_joystick() -> void:
	if _move_contact>=0 and is_instance_valid(_joystick_viewport) and _joystick_viewport.is_inside_tree():
		var release := InputEventScreenTouch.new()
		release.index=_move_contact
		release.position=Vector2(_joystick_viewport.size)*.5
		_joystick_viewport.push_input(release,true)
	_move_contact=-1
	for action: StringName in _move_actions:
		if InputMap.has_action(action): Input.action_release(action)

func _exit_tree() -> void:
	clear_input()
	for action: StringName in _move_actions:
		if InputMap.has_action(action): InputMap.erase_action(action)

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
	if is_instance_valid(_joystick) and _joystick.is_inside_tree():
		_joystick_viewport.size=Vector2i(_pad_size,_pad_size)
		_joystick.size=Vector2(_pad_size,_pad_size)
		_joystick.joystick_size=_pad_size
		_joystick.clampzone_ratio=2.0*_pad_radius/_pad_size
		_joystick_display.position=control_rect(&"move").position
		_joystick_display.size=Vector2(_pad_size,_pad_size)
		_joystick_display.visible=not _suspended
		_joystick_viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE if visible and not _suspended else SubViewport.UPDATE_DISABLED
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
