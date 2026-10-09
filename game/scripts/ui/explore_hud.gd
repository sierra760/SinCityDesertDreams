# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The Explore heads-up display: status, controls hint, vehicle and transit
## choices and the pause panel, laid out in logical UI coordinates. Pointer
## motion for looking around is handled by the Explore session.
class_name ExploreHUD
extends CanvasLayer

signal vehicle_requested(kind: StringName)
signal destination_selected(station_id: int, destination_id: int)
signal resume_requested
signal menu_requested
signal touch_input_canceled
signal recover_requested
signal return_requested
signal recenter_requested
signal settings_requested

var sensitivity := 1.0
var invert_y := false
var _chrome_top := 0.0
var _chrome_bottom := 0.0
var _layout: DisplayLayout
var _status_panel: PanelContainer
var _status_scroll: ScrollContainer
var _critical_scroll: ScrollContainer
var _panel: PanelContainer
var _scroll: ScrollContainer
var _actor_label: Label
var _speed_label: Label
var _altitude_label: Label
var _prompt_label: Label
var _message_label: Label
var _transit_label: Label
var _destination_picker: OptionButton
var _transit_station := -1
var _destinations: Array = []
var touch_controls: ExploreTouchControls
var _touch_enabled := false
var _suspended := false
var controls := ControlBindings.new()
var _base_actor_text := "Walking"
var _base_speed_text := "Speed: 0.0 m/s"
var _transit_passenger := false
## Controls hint: shown briefly after entering Explore and after each change
## between walking, driving, flying and riding, and always in the paused panel.
const HINT_MSEC := 8000
var _hint_panel: PanelContainer
var _hint_label: Label
var _panel_hint_label: Label
var _hint_context := ""
var _hint_until_msec := 0
var _mode := 0
var _vehicle_kind := &""
var _resume_button: Button
var _destination_header: Label
## Full-screen black used for door transitions.
var _fade: ColorRect
var _fade_tween: Tween

func _ready() -> void:
	_build()
	_reflow()
	show_session(false)

func bind_layout(layout: DisplayLayout) -> void:
	if is_instance_valid(_layout) and _layout.metrics_changed.is_connected(_on_metrics_changed):
		_layout.metrics_changed.disconnect(_on_metrics_changed)
	_layout = layout
	if is_instance_valid(_layout):
		_layout.metrics_changed.connect(_on_metrics_changed)
	_reflow()

func set_touch_controls_enabled(on: bool) -> void:
	_touch_enabled=on
	if is_instance_valid(touch_controls): touch_controls.set_enabled(on)
	_update_hint()
	_reflow()

func clear_touch_input() -> void:
	if is_instance_valid(touch_controls): touch_controls.clear_input()

## Main calls this before GUI delivery. Fingers that begin on a HUD panel stay
## with that panel and never turn into camera swipes.
func handle_touch_event(event: InputEvent, ui_blocked: bool = false) -> bool:
	if not is_instance_valid(touch_controls): return false
	var at: Vector2 = event.position if event is InputEventScreenTouch or event is InputEventScreenDrag else Vector2.ZERO
	var blocked := ui_blocked or (_status_panel.visible and _status_panel.get_global_rect().has_point(at)) or (_panel.visible and _panel.get_global_rect().has_point(at))
	return touch_controls.handle_event(event,blocked)

## Insets are logical UI units measured by Main's menu and city-status chrome.
func set_chrome_insets(top: float, bottom: float) -> void:
	var next_top := maxf(0.0, top) if is_finite(top) else 0.0
	var next_bottom := maxf(0.0, bottom) if is_finite(bottom) else 0.0
	if _touch_enabled and (next_top!=_chrome_top or next_bottom!=_chrome_bottom): touch_input_canceled.emit()
	_chrome_top = next_top
	_chrome_bottom = next_bottom
	_reflow()

func show_session(on: bool) -> void:
	visible = on
	if is_instance_valid(touch_controls): touch_controls.set_session_active(on)
	if on:
		_hint_until_msec = Time.get_ticks_msec()+HINT_MSEC
		set_suspended(false)

## `focus_resume` gives Resume keyboard focus so Enter/Space resumes; it is
## off when a modal took the input, so the modal keeps its own focus.
func set_suspended(on: bool, focus_resume: bool = true) -> void:
	_suspended=on
	if is_instance_valid(touch_controls): touch_controls.set_suspended(on)
	if is_instance_valid(_panel):
		_panel.visible = on
	_update_hint()
	_reflow()
	if on and focus_resume and not _touch_enabled and is_instance_valid(_resume_button) and _resume_button.is_visible_in_tree():
		_resume_button.grab_focus()

## The one-line controls summary for the current activity, built from the live
## bindings so rebinding keeps it correct.
func controls_hint() -> String:
	var interact := controls.caption(&"interact",0)
	var esc := "Esc menu"
	match _hint_context:
		"ride":
			return "%s walk · Mouse look · %s" % [_move_caption(),esc]
		"fly":
			return "%s move · Mouse look · %s climb · %s descend · %s exit (landed) · %s" % [_move_caption(),
				controls.caption(&"ascend",0),controls.caption(&"descend",0),interact,esc]
		"drive":
			return "%s/%s throttle · %s/%s steer · %s brake · %s exit · %s" % [controls.caption(&"move_forward",0),
				controls.caption(&"move_back",0),controls.caption(&"move_left",0),controls.caption(&"move_right",0),
				controls.caption(&"brake",0),interact,esc]
		"rail":
			return "%s/%s throttle · %s brake · %s exit · %s" % [controls.caption(&"move_forward",0),
				controls.caption(&"move_back",0),controls.caption(&"brake",0),interact,esc]
	return "%s move · Mouse look · %s sprint · %s jump · %s interact · %s" % [_move_caption(),
		controls.caption(&"sprint",0),controls.caption(&"jump",0),interact,esc]

func _move_caption() -> String:
	var keys := PackedStringArray()
	var single := true
	for action: StringName in [&"move_forward",&"move_left",&"move_back",&"move_right"]:
		var key := controls.caption(action,0)
		single = single and key.length() == 1
		keys.append(key)
	return "".join(keys) if single else "/".join(keys)

func _current_hint_context() -> String:
	if _transit_passenger and _mode == ExploreActorProfile.Mode.WALK: return "ride"
	if _mode == ExploreActorProfile.Mode.FLY: return "fly"
	if _mode == ExploreActorProfile.Mode.DRIVE:
		return "rail" if CityTrafficCatalog.domain(_vehicle_kind) == &"rail" else "drive"
	return "walk"

## Restart the hint on a change of activity and refresh its labels. Touch play
## has its own on-screen controls, so keyboard hints stay hidden there.
func _update_hint() -> void:
	if not is_instance_valid(_hint_label): return
	var context := _current_hint_context()
	if context != _hint_context:
		_hint_context = context
		_hint_until_msec = Time.get_ticks_msec()+HINT_MSEC
	var timed := not _touch_enabled and not _suspended and Time.get_ticks_msec() < _hint_until_msec
	var paused := not _touch_enabled and _suspended
	# Captions are only formatted while a hint is actually on screen.
	var text := controls_hint() if timed or paused else ""
	var moved := _set_label_text(_hint_label,text) if timed else false
	moved = _set_visible(_hint_panel,timed) or moved
	if paused: _set_label_text(_panel_hint_label,text)
	_set_visible(_panel_hint_label,not _touch_enabled)
	if moved: _place_hint()

func _place_hint() -> void:
	if not is_instance_valid(_hint_panel) or not _hint_panel.visible: return
	var available := _usable_rect()
	var width := minf(640.0,maxf(0.0,available.size.x-16.0))
	_hint_label.custom_minimum_size.x = maxf(0.0,width-UITheme.MARGIN*2.0)
	_hint_label.size.x = _hint_label.custom_minimum_size.x
	_hint_panel.size = Vector2(width,0)
	_hint_panel.position = Vector2(available.position.x+(available.size.x-width)*.5,available.end.y-8.0-_hint_panel.size.y)

func set_status(status: Dictionary) -> void:
	if not is_instance_valid(_actor_label):
		return
	var mode := clampi(int(status.get("mode", 0)), 0, 2)
	if is_instance_valid(touch_controls): touch_controls.set_mode(mode)
	_base_actor_text = ["Walking", "Driving", "Flying"][mode]
	var kind := StringName(status.get("vehicle",""))
	_mode = mode
	_vehicle_kind = kind
	_update_hint()
	if not kind.is_empty(): _base_actor_text = CityTrafficCatalog.display_name(kind)
	var speed := float(status.get("speed", 0.0))
	var altitude := float(status.get("altitude", 0.0))
	_base_speed_text = "Speed: %.1f m/s" % (maxf(0.0, speed) * ExploreActorProfile.METRES_PER_TILE)
	var changed := false
	# Passenger text belongs to the transit status. Keep it between the
	# controller's paired updates instead of flipping to Walking every tick.
	if not _transit_passenger or mode != ExploreActorProfile.Mode.WALK:
		changed = _set_label_text(_actor_label,_base_actor_text) or changed
		changed = _set_label_text(_speed_label,_base_speed_text) or changed
	changed = _set_label_text(_altitude_label,"Altitude: %.1f m" % (maxf(0.0, altitude) * ExploreActorProfile.METRES_PER_TILE)) or changed
	changed = _set_visible(_altitude_label,mode == ExploreActorProfile.Mode.FLY) or changed
	changed = _set_label_text(_prompt_label,_touch_caption(str(status.get("prompt", "")))) or changed
	changed = _set_label_text(_message_label,str(status.get("message", ""))) or changed
	changed = _set_visible(_prompt_label,not _prompt_label.text.is_empty()) or changed
	changed = _set_visible(_message_label,not _message_label.text.is_empty()) or changed
	changed = _set_visible(_status_scroll,_message_label.visible) or changed
	if changed: _reflow()

static func _set_label_text(label: Label, text: String) -> bool:
	if label.text == text: return false
	label.text = text
	return true

static func _set_visible(control: Control, on: bool) -> bool:
	if control.visible == on: return false
	control.visible = on
	return true

func _build() -> void:
	_status_panel = UIFactory.make_panel()
	_status_panel.name = "ExploreStatus"
	add_child(_status_panel)
	# Captured movement cannot scroll: keep actor metrics and the E action outside
	# the message viewport. Only optional, potentially long feedback scrolls.
	var status_column := VBoxContainer.new()
	status_column.name = "ExploreCriticalStatus"
	status_column.add_theme_constant_override("separation", 4)
	status_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_critical_scroll = ScrollContainer.new()
	_critical_scroll.name = "PhoneStatusScroll"
	_critical_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_critical_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_critical_scroll.follow_focus = true
	_status_panel.add_child(_critical_scroll)
	_critical_scroll.add_child(status_column)
	_actor_label = UIFactory.make_section_header("Walking")
	_speed_label = UIFactory.make_label("Speed: 0.0 m/s")
	_altitude_label = UIFactory.make_label("Altitude: 0.0 m")
	_prompt_label = UIFactory.make_label("")
	for label in [_actor_label, _speed_label, _altitude_label, _prompt_label]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status_column.add_child(label)
	_status_scroll = ScrollContainer.new()
	_status_scroll.name = "ExploreStatusScroll"
	_status_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_status_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_status_scroll.follow_focus = true
	status_column.add_child(_status_scroll)
	_message_label = UIFactory.make_label("")
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_scroll.add_child(_message_label)
	_status_panel.minimum_size_changed.connect(_reflow)
	_panel = UIFactory.make_panel()
	_panel.name = "ExplorePanel"
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.name = "ExploreControlsScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	_panel.add_child(_scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UITheme.VSEP)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(column)
	column.add_child(UIFactory.make_section_header("Explore"))
	for row in [["Resume", "resume_requested"], ["Recover", "recover_requested"],
		["Return to Build", "return_requested"], ["Reset camera", "recenter_requested"]]:
		var button := UIFactory.make_button(row[0])
		button.pressed.connect(func() -> void: emit_signal(row[1]))
		column.add_child(button)
		if row[0] == "Resume": _resume_button = button
	_panel_hint_label = UIFactory.make_label("",UITheme.FONT_SMALL)
	_panel_hint_label.name = "ExplorePanelControlsHint"
	_panel_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_panel_hint_label)
	column.add_child(UIFactory.make_section_header("Choose a vehicle"))
	var picker := OptionButton.new()
	picker.name = "VehicleChoice"
	picker.custom_minimum_size.y = 44
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item = false
	picker.theme = UITheme.control_theme()
	for kind: StringName in CityTrafficCatalog.vehicle_kinds():
		if not CityTrafficCatalog.is_drivable(kind): continue
		picker.add_item(CityTrafficCatalog.display_name(kind))
		picker.set_item_metadata(picker.item_count-1,kind)
	column.add_child(picker)
	var use_vehicle := UIFactory.make_button("Drive selected vehicle")
	use_vehicle.name = "DriveSelectedVehicle"
	use_vehicle.pressed.connect(func() -> void: vehicle_requested.emit(StringName(picker.get_item_metadata(picker.selected))))
	column.add_child(use_vehicle)
	var vehicle_help := UIFactory.make_label("Choose while walking outdoors, not riding a train or inside a station or resort. A connected route and clear space must be nearby, and the helicopter flies from where it is parked. At a marina, use Interact to board a boat. Stop beside the marina or a clear shoreline to exit. Airplanes can't be driven.")
	vehicle_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(vehicle_help)
	_transit_label = UIFactory.make_label("",UITheme.FONT_SMALL)
	_transit_label.name = "TransitStatus"
	_transit_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_column.add_child(_transit_label)
	_destination_header = UIFactory.make_section_header("Destination")
	_destination_header.name = "TransitDestinationHeader"
	column.add_child(_destination_header)
	_destination_header.hide()
	_destination_picker = OptionButton.new()
	_destination_picker.name = "TransitDestination"
	_destination_picker.custom_minimum_size.y = 44
	_destination_picker.fit_to_longest_item = false
	_destination_picker.theme = UITheme.control_theme()
	_destination_picker.item_selected.connect(func(index: int) -> void:
		destination_selected.emit(_transit_station,int(_destination_picker.get_item_metadata(index))))
	column.add_child(_destination_picker)
	_destination_picker.hide()
	_destination_picker.tooltip_text="Choose your destination while waiting at a station."
	var settings := UIFactory.make_button("Control settings")
	settings.pressed.connect(func() -> void: settings_requested.emit())
	column.add_child(settings)
	touch_controls=ExploreTouchControls.new()
	touch_controls.name="ExploreTouchControls"
	add_child(touch_controls)
	touch_controls.set_enabled(_touch_enabled)
	touch_controls.menu_requested.connect(func() -> void: menu_requested.emit())
	_hint_panel = UIFactory.make_panel()
	_hint_panel.name = "ExploreControlsHint"
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_hint_panel)
	_hint_label = UIFactory.make_label("",UITheme.FONT_SMALL)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.add_child(_hint_label)
	_hint_panel.hide()
	_update_hint()

## Fade to black over half of `seconds`, call `midpoint`, then fade back in.
func fade_through(midpoint: Callable, seconds: float = .3) -> void:
	cancel_fade()
	if seconds<=0.0 or not is_inside_tree():
		midpoint.call()
		return
	if not is_instance_valid(_fade):
		_fade = ColorRect.new()
		_fade.name = "ExploreDoorFade"
		_fade.color = Color.BLACK
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_fade)
	move_child(_fade,get_child_count()-1)
	_fade.modulate.a = 0.0
	_fade.show()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade,"modulate:a",1.0,seconds*.5)
	_fade_tween.tween_callback(midpoint)
	_fade_tween.tween_property(_fade,"modulate:a",0.0,seconds*.5)
	_fade_tween.tween_callback(_fade.hide)

func cancel_fade() -> void:
	if _fade_tween != null: _fade_tween.kill()
	_fade_tween = null
	if is_instance_valid(_fade): _fade.hide()

func _touch_caption(caption: String) -> String:
	return caption.replace("F to ","Interact to " if _touch_enabled else controls.caption(&"interact")+" to ")

func _on_metrics_changed(_metrics: Dictionary) -> void:
	clear_touch_input()
	if _touch_enabled: touch_input_canceled.emit()
	_reflow()

func _usable_rect() -> Rect2:
	var available := _layout.logical_rect() if is_instance_valid(_layout) else Rect2(0, 0, 1280, 800)
	var reserved_top := minf(_chrome_top, maxf(0.0, available.size.y - 80.0))
	var reserved_bottom := minf(_chrome_bottom, maxf(0.0, available.size.y - reserved_top - 80.0))
	available.position.y += reserved_top
	available.size.y -= reserved_top + reserved_bottom
	return available

func _reflow() -> void:
	if not is_instance_valid(_panel) or not is_instance_valid(_status_panel):
		return
	var available := _usable_rect()
	_place_hint()
	if is_instance_valid(touch_controls): touch_controls.set_usable_rect(available)
	var margin := 8.0
	var phone := is_instance_valid(_layout) and DisplayLayout.is_phone(_layout.metrics)
	_critical_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if phone else ScrollContainer.SCROLL_MODE_DISABLED
	# Put the current interaction directly after actor identity on phones;
	# metrics and longer transit feedback remain in the same touch scroll.
	var status_column := _actor_label.get_parent()
	status_column.move_child(_prompt_label,1 if phone else 3)
	_status_panel.position = available.position + Vector2(margin, margin)
	# Hidden controls do not consume the captured player's critical status space.
	var status_height := minf(150.0, maxf(0.0, available.size.y - margin * 2.0))
	var status_width := minf(330.0, available.size.x * .39)
	if _touch_enabled:
		# Portrait uses a readable compact summary above both thumbs. The
		# suspended menu starts below it, leaving Resume visible immediately.
		status_width=minf(330.0,maxf(200.0,available.size.x-128.0))
		status_height=minf(status_height,maxf(0.0,available.size.y-200.0))
		if phone:
			status_height = minf(150.0,maxf(44.0,available.size.y-180.0))
	# Wrapped labels need the intended content width before their minimum height
	# is queried; otherwise their first layout can count one character per line.
	for label in [_actor_label, _speed_label, _altitude_label, _prompt_label, _transit_label]:
		label.size.x = maxf(0.0,status_width - UITheme.MARGIN * 2.0)
	# Without a scrolling message the card fits its lines instead of leaving
	# an empty band below them.
	if not _status_scroll.visible:
		var status_style := _status_panel.get_theme_stylebox(&"panel")
		var status_chrome := status_style.get_minimum_size().y if status_style != null else 0.0
		status_height = minf(status_height,maxf(44.0,(status_column as Control).get_combined_minimum_size().y+status_chrome))
	_status_panel.size = Vector2(status_width, status_height)
	if is_instance_valid(touch_controls): touch_controls.set_status_rect(_status_panel.get_rect())
	var width := minf(390.0, available.size.x - margin * 2.0)
	# The paused panel is as tall as its content, up to the usable height;
	# only what does not fit scrolls.
	var height := minf(_panel_content_height(width), available.size.y - margin * 2.0)
	if _touch_enabled:
		panel_touch_reflow(available,margin,width,height)
		return
	var panel_position := available.position + (available.size - Vector2(width, height)) * .5
	var status_rect := _status_panel.get_rect()
	if Rect2(panel_position, Vector2(width, height)).intersects(status_rect):
		var below_height := available.end.y - margin - status_rect.end.y - margin
		var heading := _scroll.get_child(0).get_child(0) as Label
		var resume_height := heading.get_combined_minimum_size().y + UITheme.VSEP + 44.0 + UITheme.MARGIN * 2.0
		if below_height >= resume_height:
			panel_position.y = status_rect.end.y + margin
			height = minf(below_height,_panel_content_height(width))
		else:
			# A wrapped Main footer can leave only 185 logical units. Beside the
			# critical status, Resume retains its full 44-unit target and controls
			# scroll independently without pushing flight instructions offscreen.
			panel_position = Vector2(status_rect.end.x + margin, available.position.y + margin)
			width = available.end.x - margin - panel_position.x
	_scroll.custom_minimum_size = Vector2(width - UITheme.MARGIN * 2.0, minf(height - UITheme.MARGIN * 2.0, 100.0))
	_panel.position = panel_position
	_panel.size = Vector2(width, height)

## Full height of the paused panel's column at `width`, with wrapped labels
## measured at the column's width.
func _panel_content_height(width: float) -> float:
	var column := _scroll.get_child(0) as Control
	var inner := maxf(0.0,width - UITheme.MARGIN * 2.0)
	for child: Node in column.get_children():
		if child is Label and (child as Label).autowrap_mode != TextServer.AUTOWRAP_OFF: (child as Label).size.x = inner
	var chrome := 0.0
	var style := _panel.get_theme_stylebox(&"panel")
	if style != null: chrome = style.get_minimum_size().y
	return column.get_combined_minimum_size().y + chrome

func panel_touch_reflow(available: Rect2, margin: float, width: float, height: float) -> void:
	var top := _status_panel.get_rect().end.y+margin
	var room := maxf(0.0,available.end.y-margin-top)
	height=minf(height,room)
	# Usable iPad portrait and narrow canvases have room below status. On
	# exceptionally short canvases use the right column, as on desktop.
	var at := Vector2(available.position.x+(available.size.x-width)*.5,top)
	if room<100.0:
		at=Vector2(_status_panel.get_rect().end.x+margin,available.position.y+64.0)
		width=maxf(0.0,available.end.x-margin-at.x)
		height=maxf(0.0,available.end.y-margin-at.y)
	_scroll.custom_minimum_size=Vector2(maxf(0.0,width-UITheme.MARGIN*2.0),minf(maxf(0.0,height-UITheme.MARGIN*2.0),100.0))
	_panel.position=at
	_panel.size=Vector2(width,height)

func set_transit_status(status: Dictionary) -> void:
	if not is_instance_valid(_transit_label): return
	var text := str(status.get("message","")) if bool(status.get("message_literal",false)) else _touch_caption(str(status.get("message","")))
	if text==_prompt_label.text or text==_touch_caption(str(status.get("elevator_prompt",""))): text=""
	var actor_text := _base_actor_text
	var speed_text := _base_speed_text
	# Only a walker rides as a passenger; a driver or pilot keeps their own
	# vehicle's name and speed even while a service train is nearby.
	_transit_passenger = bool(status.get("passenger",false)) and _mode == ExploreActorProfile.Mode.WALK
	if _transit_passenger:
		actor_text = "Riding subway" if status.get("transit_kind","")=="subway" else "Riding train"
		speed_text = "Speed: %.1f m/s" % maxf(0.0,float(status.get("speed_mps",0.0)))
		var doors := str(status.get("door_state",status.get("doors","closed")))
		if doors == "boarding": doors = "open"
		elif doors in ["departing","approaching","braking"]: doors = "closed"
		var current := str(status.get("current_stop",""))
		# The final stop shares the Next line, so compact ride status keeps its height.
		var next_stop := str(status.get("next_stop",""))
		var final_stop := str(status.get("destination",""))
		if not final_stop.is_empty() and final_stop != next_stop: next_stop += " · To: "+final_stop
		text = ("At: %s\n" % current if not current.is_empty() else "")+"Next: %s\nDoors: %s" % [next_stop,doors]
		if doors=="open":
			var seconds := int(status.get("departure_seconds",-1))
			if bool(status.get("doorway_blocked",false)): text+=" · Keep doorway clear"
			elif seconds>=0: text+=" · Departs in %ds" % seconds
	elif int(status.get("station_id",-1)) >= 0 and (status.get("destinations",[]) as Array).size() > 1 \
			and bool(status.get("can_choose_destination",true)):
		# Waiting on a platform: name the chosen service and how to change it.
		var chosen := _destination_name(status)
		if not chosen.is_empty():
			var line := "To: %s — %s to change" % [chosen,"Menu" if _touch_enabled else "Esc"]
			text = line if text.is_empty() else text+"\n"+line
	_update_hint()
	var changed := _set_label_text(_actor_label,actor_text)
	changed = _set_label_text(_speed_label,speed_text) or changed
	changed = _set_label_text(_transit_label,text) or changed
	changed = _set_visible(_transit_label,not text.is_empty()) or changed
	var destinations: Array = status.get("destinations",[])
	var station := int(status.get("station_id",-1))
	if destinations != _destinations or station != _transit_station:
		changed = true
		_destinations = destinations.duplicate(true)
		_transit_station = station
		_destination_picker.clear()
		for destination: Dictionary in destinations:
			_destination_picker.add_item(str(destination.get("name","Station")))
			_destination_picker.set_item_metadata(_destination_picker.item_count-1,int(destination.get("id",-1)))
	changed = _set_visible(_destination_picker,destinations.size()>1) or changed
	changed = _set_visible(_destination_header,destinations.size()>1) or changed
	_destination_picker.disabled=not bool(status.get("can_choose_destination",not bool(status.get("passenger",false))))
	var selected := int(status.get("selected_destination",-1))
	for index: int in _destination_picker.item_count:
		if int(_destination_picker.get_item_metadata(index))==selected:
			_destination_picker.select(index)
			break
	if changed: _reflow()

static func _destination_name(status: Dictionary) -> String:
	var selected := int(status.get("selected_destination",-1))
	for destination: Variant in status.get("destinations",[]):
		if destination is Dictionary and int(destination.get("id",-1)) == selected:
			return str(destination.get("name",""))
	return str(status.get("destination",""))
