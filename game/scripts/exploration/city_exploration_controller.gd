# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## An Explore session: its actors, input, camera and HUD. City state and
## simulation stay with Main.
class_name CityExplorationController
extends Node

signal return_requested
signal status_changed(status: Dictionary)
signal active_changed(on: bool)
signal touch_controls_changed(on: bool)
## A casino table on a resort floor was chosen; the host opens the table and
## may hold `casino_table_pose(table)` as the camera while it is open.
signal casino_table_requested(resort: StringName, game: StringName, table: Dictionary)

var controls := ControlBindings.new()
const MarinaAccess := preload("res://scripts/exploration/explore_marina_access.gd")
const ResortAccess := preload("res://scripts/exploration/resorts/resort_entrance_access.gd")
const ACTOR_SCRIPTS := [preload("res://scripts/exploration/explore_pedestrian.gd"),
	preload("res://scripts/exploration/explore_car.gd"),preload("res://scripts/exploration/explore_helicopter.gd")]

var input_blocked: Callable
var release_ui_focus: Callable
## Host policy: true while a notice or other modal owns input. A session that
## a modal suspended resumes by itself once the modal closes.
var modal_open: Callable
## Host policy: true while a Build window (Options, reports) is open. Resume
## waits until it is closed.
var window_open: Callable
var view: CityView3D
var hud: ExploreHUD
var traversal: CityTraversalWorld3D
## Inert physical projection kept between sessions for the same view and city.
## Nothing queries it outside a session; the next entry's rebuild() reuses every
## body whose faces, box and transform are unchanged instead of rebuilding them.
var _retained_world: CityTraversalWorld3D
var _retained_world_city := 0
var pedestrian: CharacterBody3D
var pedestrian_character := "woman"
var car: CharacterBody3D
var helicopter: CharacterBody3D
var selected_vehicle: CharacterBody3D
var transit_service: Node3D
var resort_service: ExploreResortService
## The table record last requested on a resort floor, until it is released.
var _casino_table: Dictionary = {}
var _traffic_claim: Dictionary = {}
var _ambient_prompt_at := 0
var _ambient_nearby: Dictionary = {}
var _ambient_claimed := false
var _marina_dock: Dictionary = {}
var _claimed_vehicle: CharacterBody3D
var occupied: CharacterBody3D
var camera_rig: CityExploreCamera3D
var mode := ExploreActorProfile.Mode.WALK
var _active := false
var _suspended := false
var _arming := true
var _held: Dictionary = {}
var _edges: Dictionary = {}
var _last_safe: Dictionary = {}
var _revision_pending := false
var _pending_recovery := false
var _helicopter_in_flight := false
var _message := ""
## Transient feedback clears after this much active (unpaused) play.
const MESSAGE_SECONDS := 4.0
var _aged_message := ""
var _message_age := 0.0
## Why Explore ended, for the host to show after returning to Build.
var _exit_message := ""
## A pause the player asked for (Escape or Menu) never resumes by itself.
var _manual_pause := false
var _resume_when_unblocked := false
var _suspended_at_frame := 0
var _escape_pressed := false
var _touch_enabled := MobilePlatform.uses_touch()
## On a desktop platform (mouse and keyboard by default) the controls follow
## the pointer actually in use: the first real screen touch turns on the touch
## controls, and the next real mouse movement turns them off again. Phones,
## tablets and mobile browsers always use touch.
var follow_pointer_kind := not MobilePlatform.uses_touch()
var _touch_hardware_quarantine: Dictionary = {}

func _enter_tree() -> void:
	# The corner minimap reads the player's position and heading from here.
	add_to_group(MiniMap.EXPLORE_MARKER_GROUP)

## Where the player is for the minimap: the occupied actor's map position
## (x,z) and its heading on the map plane, or {} outside a session.
func minimap_marker() -> Dictionary:
	if not _active or not is_instance_valid(occupied) or not occupied.is_inside_tree(): return {}
	var at := occupied.global_position
	var forward := occupied.global_basis*Vector3.FORWARD
	var heading := Vector2(forward.x,forward.z)
	if heading.length_squared() < 1e-6 and is_instance_valid(camera_rig): heading = Vector2(-sin(camera_rig.yaw),-cos(camera_rig.yaw))
	return {"position":Vector2(at.x,at.z),"heading":heading.normalized()}

func bind(value: CityView3D, interface: ExploreHUD) -> void:
	if is_instance_valid(view) and view.geometry_rebuilt.is_connected(_on_geometry_rebuilt):
		view.geometry_rebuilt.disconnect(_on_geometry_rebuilt)
	if view != value: _free_retained_world()
	view = value
	hud = interface
	view.geometry_rebuilt.connect(_on_geometry_rebuilt)
	hud.vehicle_requested.connect(select_vehicle)
	hud.destination_selected.connect(func(station: int, destination: int) -> void:
		if is_instance_valid(transit_service):
			transit_service.choose_destination(station,destination)
			# The route panel remains usable while Explore is paused. Publish
			# the accepted selection (or restore a rejected one) immediately.
			_publish_status())
	hud.resume_requested.connect(resume)
	hud.menu_requested.connect(pause)
	hud.touch_input_canceled.connect(cancel_touch_input)
	hud.set_touch_controls_enabled(_touch_enabled)
	hud.recover_requested.connect(recover)
	hud.return_requested.connect(func() -> void:
		_exit_message = ""
		return_requested.emit())
	hud.recenter_requested.connect(func() -> void:
		if is_instance_valid(camera_rig): camera_rig.recenter())

func enter(city: City, origin: Vector3) -> bool:
	if _active or city == null or city != view.city or not origin.is_finite(): return false
	var road_cells := _entry_road_cells(origin)
	if road_cells.is_empty(): return false
	var snapshot := view.traversal_snapshot()
	if snapshot.chunks.is_empty(): return false
	traversal = _acquire_world(city)
	traversal.rebuild(city,snapshot.chunks,snapshot.networks,snapshot.revision)
	var pose := _road_entry_pose(road_cells,origin)
	if pose.is_empty():
		_message = "No safe outdoor road is available for Explore mode."
		_clear_actors()
		return false
	pedestrian = _make_actor(0,pose.transform)
	pedestrian.call("set_character",pedestrian_character)
	occupied = pedestrian
	transit_service = ExploreTransitService.new()
	view.world.add_child(transit_service)
	transit_service.bind(view,traversal,pedestrian)
	pedestrian.transit_support = transit_service
	resort_service = ExploreResortService.new()
	resort_service.name = "ExploreResorts"
	view.world.add_child(resort_service)
	resort_service.bind(view,traversal,pedestrian,hud)
	resort_service.table_requested.connect(_on_casino_table)
	resort_service.ejected.connect(func(reason: String) -> void: _message = reason)
	resort_service.moved.connect(func() -> void:
		_last_safe[pedestrian.get_instance_id()] = pedestrian.global_transform
		if is_instance_valid(camera_rig): camera_rig.recenter())
	mode = ExploreActorProfile.Mode.WALK
	var car_pose := _parking_pose(pedestrian.global_position+Vector3(.4,0,0),1)
	if not car_pose.is_empty():
		car = _make_actor(1,car_pose.transform)
	var flight_pose := _parking_pose(pedestrian.global_position+Vector3(-.5,0,0),2)
	if not flight_pose.is_empty(): helicopter = _make_actor(2,flight_pose.transform)
	_message = ""
	_exit_message = ""
	_manual_pause = false
	_resume_when_unblocked = false
	if car == null or helicopter == null: _message = "Some vehicles have no safe parking space nearby."
	camera_rig = CityExploreCamera3D.new()
	view.world.add_child(camera_rig)
	camera_rig.recovery_requested.connect(func() -> void: _pending_recovery = true)
	camera_rig.configure_target(occupied,mode)
	camera_rig.update_follow(0)
	view.set_exploration_camera(camera_rig.camera)
	if view.feedback != null: view.feedback.set_exploring(true)
	_active = true
	_suspended = false
	_arming = true
	_arm_touch_hardware(false)
	_held.clear()
	_edges.clear()
	_last_safe[pedestrian.get_instance_id()] = pedestrian.global_transform
	hud.show_session(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _touch_enabled else Input.MOUSE_MODE_CAPTURED
	active_changed.emit(true)
	_publish_status()
	return true

## Reuse the retained world only for the same view tree and the same City
## object; any other retained projection is stale and is released here.
func _acquire_world(city: City) -> CityTraversalWorld3D:
	var world := _retained_world
	_retained_world = null
	if is_instance_valid(world) and world.get_parent() == view.world and _retained_world_city == city.get_instance_id():
		return world
	if is_instance_valid(world): world.free()
	world = CityTraversalWorld3D.new()
	world.name = "TraversalWorld"
	view.world.add_child(world)
	_retained_world_city = city.get_instance_id()
	return world

func _free_retained_world() -> void:
	if is_instance_valid(_retained_world): _retained_world.free()
	_retained_world = null
	_retained_world_city = 0

## The idle projection is a cache; a low-memory warning outside a session
## releases it, and the next entry simply rebuilds it from the city.
func _notification(what: int) -> void:
	if what == NOTIFICATION_OS_MEMORY_WARNING and not _active: _free_retained_world()

func _entry_road_cells(origin: Vector3) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var graph: CityTrafficGraph = view.traffic.graph
	graph.refresh()
	# has_cell includes isolated roads, crossings, bridges and highways. The
	# ambient traffic list only includes cells with reciprocal neighbors.
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:
			var cell := Vector2i(x,y)
			if graph.has_cell(cell,&"road"): cells.append(cell)
	var center := Vector2(origin.x,origin.z)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (Vector2(a)+Vector2(.5,.5)).distance_squared_to(center)
		var db := (Vector2(b)+Vector2(.5,.5)).distance_squared_to(center)
		return da<db if da!=db else a.y<b.y if a.y!=b.y else a.x<b.x)
	return cells

func _road_entry_pose(cells: Array[Vector2i], origin: Vector3) -> Dictionary:
	var no_exclusions: Array[RID] = []
	return _outdoor_road_pose(cells,origin,ExploreActorProfile.shape(ExploreActorProfile.Mode.WALK),no_exclusions)

## Nearest outdoor pavement pose whose full shape clears the physical world.
## Vehicles also try the road's own axis before the perpendicular heading.
func _outdoor_road_pose(cells: Array[Vector2i], origin: Vector3, shape: Shape3D, exclusions: Array[RID], vehicle: bool = false) -> Dictionary:
	var graph: CityTrafficGraph = view.traffic.graph
	var lift := shape.get_debug_mesh().get_aabb().size.y*.5
	var offsets: Array[Vector2] = [Vector2(.5,.5),Vector2(.25,.5),Vector2(.75,.5),
		Vector2(.5,.25),Vector2(.5,.75),Vector2(.35,.35),Vector2(.65,.35),Vector2(.35,.65),Vector2(.65,.65),
		Vector2(.5,.08),Vector2(.5,.92),Vector2(.08,.5),Vector2(.92,.5)]
	for cell: Vector2i in cells:
		var samples := offsets.duplicate()
		if cell==Vector2i(floori(origin.x),floori(origin.z)):
			samples.push_front(Vector2(origin.x-cell.x,origin.z-cell.y))
		var yaws: Array[float] = [0.0]
		if vehicle:
			var across := false
			for next: Vector2i in graph.neighbors(cell,&"road"):
				if next.y==cell.y: across = true
				elif next.x==cell.x:
					across = false
					break
			yaws.assign([PI*.5,0.0] if across else [0.0,PI*.5])
		for offset: Vector2 in samples:
			var point := graph.point(cell,&"road",offset)
			# A tight height interval admits the rendered pavement, never a
			# terrain/verge fallback, building roof or a lower tunnel floor.
			var support := traversal.support_near(point+Vector3.UP*.002,.002,.006,exclusions)
			if support.is_empty(): continue
			var feet: Vector3 = support.position+Vector3.UP*.002
			if traversal.inside_road_tunnel(feet) or traversal.touches_water(feet): continue
			for yaw: float in yaws:
				var pose := Transform3D(Basis(Vector3.UP,yaw),feet)
				var shape_pose := pose
				shape_pose.origin.y += lift
				if traversal.has_clearance(shape_pose,shape,exclusions): return {"transform":pose}
	return {}

func _parking_pose(origin: Vector3, actor_mode: int) -> Dictionary:
	var exclusions: Array[RID] = []
	var pose := traversal.safe_pose(origin,actor_mode,exclusions)
	if pose.is_empty() or _parking_clears_actors(pose.transform,actor_mode): return pose
	# Same-call body creation can precede physics broadphase registration.
	# Keep world queries, and independently reserve existing actor bounds.
	for radius: int in range(1,17):
		for index: int in 16:
			var angle := TAU*float(index)/16.0
			var candidate := origin+Vector3(cos(angle),0,sin(angle))*(float(radius)*.5)
			var support := traversal.support_near(candidate,.045,8.0,exclusions)
			if support.is_empty(): continue
			var feet: Vector3 = support.position+Vector3.UP*.002
			if traversal.touches_water(feet) or feet.y>traversal.max_flight_y(): continue
			var at := Transform3D(Basis.IDENTITY,feet)
			if not _parking_clears_actors(at,actor_mode): continue
			if traversal.has_clearance(_shape_pose(at,actor_mode),ExploreActorProfile.shape(actor_mode),exclusions): return {"transform":at}
	return {}

func _parking_clears_actors(pose: Transform3D, actor_mode: int) -> bool:
	var shape := ExploreActorProfile.shape(actor_mode)
	var bounds: AABB = _shape_pose(pose,actor_mode)*shape.get_debug_mesh().get_aabb()
	if is_instance_valid(transit_service) and transit_service.network != null:
		for station: Dictionary in transit_service.network.stations:
			var platform: Vector3 = station.platform
			if Vector2(pose.origin.x-platform.x,pose.origin.z-platform.z).length()<.85: return false
	for actor: CharacterBody3D in [pedestrian,car,helicopter,selected_vehicle]:
		if not is_instance_valid(actor): continue
		var other_pose := (actor as ExploreCar).collision_pose() if actor is ExploreCar else _actor_shape_pose(actor,actor.global_transform)
		var other_shape := _actor_shape(actor)
		var other_bounds: AABB = other_pose*other_shape.get_debug_mesh().get_aabb()
		if bounds.grow(.002).intersects(other_bounds): return false
	return true

func _make_actor(actor_mode: int, pose: Transform3D) -> CharacterBody3D:
	var actor: CharacterBody3D = ACTOR_SCRIPTS[actor_mode].new()
	actor.name = ["ExplorePedestrian","ExploreCar","ExploreHelicopter"][actor_mode]
	view.world.add_child(actor)
	actor.bind(traversal)
	if actor.has_signal("recovery_requested"):
		actor.connect("recovery_requested",func(reason: String) -> void:
			_message = reason
			_pending_recovery = true)
	if actor is ExplorePedestrian: actor.place(pose)
	else: actor.global_transform = pose
	_last_safe[actor.get_instance_id()] = pose
	return actor

func is_active() -> bool: return _active
func is_suspended() -> bool: return _suspended

func set_pedestrian_character(value: String) -> void:
	pedestrian_character = value if value in ViewPreferences.EXPLORE_CHARACTERS else "woman"
	if is_instance_valid(pedestrian): pedestrian.call("set_character",pedestrian_character)

## Override hardware touch detection, for example from a player preference.
func set_touch_controls_enabled(on: bool) -> void:
	if _touch_enabled==on: return
	_touch_enabled=on
	_reset_input()
	if is_instance_valid(hud): hud.set_touch_controls_enabled(on)
	if _active: Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if on or _suspended else Input.MOUSE_MODE_CAPTURED
	touch_controls_changed.emit(on)

func touch_controls_enabled() -> bool:
	return _touch_enabled

## Main passes every input event here first. Events the engine emulates
## (mouse from touch, touch from mouse) never switch the controls.
func note_pointer_event(event: InputEvent) -> void:
	if not follow_pointer_kind or event.device==InputEvent.DEVICE_ID_EMULATION: return
	if event is InputEventScreenTouch and event.pressed and not _touch_enabled: set_touch_controls_enabled(true)
	elif event is InputEventMouseMotion and _touch_enabled: set_touch_controls_enabled(false)

func cancel_touch_input() -> void:
	_reset_input()

## Drop all held keys, edges and touch contacts. With touch controls on, keys
## still physically held must be released before they move the actor again.
func _reset_input(stop_actor: bool = true) -> void:
	_arming = true
	_arm_touch_hardware()
	_held.clear()
	_edges.clear()
	if is_instance_valid(hud): hud.clear_touch_input()
	if stop_actor and is_instance_valid(occupied): occupied.stop_input()

## With touch controls, keyboard input comes from key events rather than
## polling. On a session transition, keys already held are quarantined until
## their release arrives, so a stale press cannot move the actor.
func _arm_touch_hardware(preserve_quarantine: bool = true) -> void:
	if not preserve_quarantine: _touch_hardware_quarantine.clear()
	if not _touch_enabled: return
	for key: int in controls.keys_for("Explore"):
		if bool(_held.get(key,false)) or Input.is_physical_key_pressed(key):
			_touch_hardware_quarantine[key]=true

## Suspend for a host reason (a menu, window, modal or lost focus). Escape
## pressed in this same input pass makes it a manual pause.
func suspend() -> void:
	if not _active: return
	_suspend(_escape_pressed)

## The player's own pause (Escape or the touch Menu). It stays paused until
## Resume, even after a notice that opens meanwhile is closed.
func pause() -> void:
	if not _active: return
	_suspend(true)

func _suspend(manual: bool, focus_resume: bool = true) -> void:
	var was_suspended := _suspended
	_suspended = true
	_escape_pressed = false
	if not was_suspended:
		_manual_pause = manual
		_resume_when_unblocked = false
		_suspended_at_frame = Engine.get_physics_frames()
	elif manual:
		_manual_pause = true
		_resume_when_unblocked = false
	_reset_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# A repeated suspension (for example a modal over the paused panel) never
	# takes keyboard focus from whatever opened.
	hud.set_suspended(true,focus_resume and not was_suspended)

func resume() -> void:
	if not _active: return
	if _suspended and window_open.is_valid() and bool(window_open.call()):
		_message = "Close the open window to resume Explore."
		_publish_status()
		return
	if release_ui_focus.is_valid(): release_ui_focus.call()
	if input_blocked.is_valid() and bool(input_blocked.call()): return
	_suspended = false
	_manual_pause = false
	_resume_when_unblocked = false
	_reset_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _touch_enabled else Input.MOUSE_MODE_CAPTURED
	hud.set_suspended(false)

## For the host after a modal closes: resume now when the suspension was not
## the player's own pause and nothing else (a modal or Build window) holds
## input; otherwise stay paused exactly as the next physics tick would.
func resume_if_unblocked() -> void:
	if _active and _suspended: _check_auto_resume()

## While suspended: a modal that caused (or immediately followed) the
## suspension arms an automatic resume for the first tick after it closes.
func _check_auto_resume() -> void:
	if _manual_pause or not modal_open.is_valid(): return
	if bool(modal_open.call()):
		if Engine.get_physics_frames()-_suspended_at_frame <= 2: _resume_when_unblocked = true
		return
	if not _resume_when_unblocked: return
	if window_open.is_valid() and bool(window_open.call()): return
	resume()

## Why the last session ended, when the controller ended it itself.
func last_exit_message() -> String:
	return _exit_message

## Return and clear the exit explanation so it is shown once.
func take_exit_message() -> String:
	var message := _exit_message
	_exit_message = ""
	return message

func _request_return(message: String) -> void:
	_message = message
	_exit_message = message
	return_requested.emit()

## Age transient feedback; a new message restarts its time.
func _tick_message(delta: float) -> void:
	if _message != _aged_message:
		_aged_message = _message
		_message_age = 0.0
		return
	if _message.is_empty(): return
	_message_age += delta
	if _message_age >= MESSAGE_SECONDS:
		_message = ""
		_aged_message = ""

func leave() -> void:
	if not _active: return
	_active = false
	_suspended = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_held.clear()
	_edges.clear()
	if is_instance_valid(hud): hud.clear_touch_input()
	view.clear_exploration_camera()
	if view.feedback != null: view.feedback.set_exploring(false)
	_clear_actors()
	hud.show_session(false)
	active_changed.emit(false)

func dispose() -> void:
	leave()
	_clear_actors()
	_free_retained_world()

func _clear_actors() -> void:
	_release_traffic_claim()
	# Station/portal cut-outs restore their visuals now; the kept physical
	# world is brought up to date by the next entry's rebuild, before any query.
	if is_instance_valid(transit_service): transit_service.clear(false)
	if is_instance_valid(resort_service): resort_service.clear()
	_casino_table = {}
	for node: Node in [camera_rig,pedestrian,car,helicopter,selected_vehicle,transit_service,resort_service]:
		if is_instance_valid(node): node.free()
	if is_instance_valid(traversal):
		if is_instance_valid(_retained_world) and _retained_world != traversal: _retained_world.free()
		_retained_world = traversal
	traversal = null
	camera_rig = null
	pedestrian = null
	car = null
	helicopter = null
	selected_vehicle = null
	transit_service = null
	resort_service = null
	occupied = null
	_last_safe.clear()
	_ambient_prompt_at = 0
	_ambient_nearby.clear()
	_marina_dock.clear()
	_revision_pending = false
	_pending_recovery = false
	_helicopter_in_flight = false

func handle_event(event: InputEvent, ui_blocked: bool = false) -> bool:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if is_instance_valid(hud): return hud.handle_touch_event(event,ui_blocked)
		return false
	if not _active: return false
	if _touch_enabled and event.device==InputEvent.DEVICE_ID_EMULATION and (event is InputEventMouseMotion or event is InputEventMouseButton): return not _suspended
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_ESCAPE and not _suspended: _escape_pressed = true
		var code: int = ControlBindings.event_code(event)
		if code not in controls.keys_for("Explore"): return code in controls.keys_for("Build")
		if event.pressed and (event.ctrl_pressed or event.meta_pressed or event.alt_pressed): return false
		if _touch_enabled:
			if not event.pressed: _touch_hardware_quarantine.erase(code)
			if _suspended or event.echo:
				if _suspended and event.pressed: _touch_hardware_quarantine[code]=true
				return true
			if _touch_hardware_quarantine.has(code): return true
		if _suspended or event.echo: return true
		if event.pressed and not bool(_held.get(code,false)): _edges[code] = true
		_held[code] = event.pressed
		return true
	if event is InputEventMouseMotion and not _suspended:
		camera_rig.orbit(event.screen_relative,hud.sensitivity,hud.invert_y)
		return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and handle_event(event):
		get_viewport().set_input_as_handled()

func _physical_keys() -> Dictionary:
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_ALT): return {}
	var keys := _held.duplicate()
	for key: int in controls.keys_for("Explore"):
		if Input.is_physical_key_pressed(key): keys[key] = true
	return keys

func _physics_process(delta: float) -> void:
	if not _active: return
	_escape_pressed = false
	if not _suspended and input_blocked.is_valid() and bool(input_blocked.call()):
		_suspend(false,false)
		if modal_open.is_valid() and bool(modal_open.call()): _resume_when_unblocked = true
		return
	if _suspended:
		_check_auto_resume()
		if _suspended: return
	_tick_message(delta)
	if not _reconcile_revision(): return
	if _pending_recovery:
		_pending_recovery = false
		if not _recover_nearby(): return
	var keys := _held.duplicate() if _touch_enabled else _physical_keys()
	if _arming and not _touch_enabled:
		var released := true
		for key: int in controls.keys_for("Explore"):
			if bool(keys.get(key,false)): released = false
		_edges.clear()
		if not released: return
		_arming = false
	var frame := ExploreInputFrame.from_keys(keys,_edges,controls)
	if _touch_enabled:
		if not _touch_hardware_quarantine.is_empty(): frame=ExploreInputFrame.idle()
		frame=ExploreInputFrame.combined(frame,hud.touch_controls.sample_frame())
		var look: Vector2= hud.touch_controls.take_look_delta()
		if look!=Vector2.ZERO: camera_rig.orbit(look,hud.sensitivity,hud.invert_y)
	_edges.clear()
	if frame.interact:
		var previous_mode := mode
		request_interaction()
		if _touch_enabled and mode!=previous_mode: frame=ExploreInputFrame.idle()
	if not _active: return
	if is_instance_valid(transit_service): transit_service.step(delta,pedestrian)
	if is_instance_valid(resort_service): resort_service.step(delta,pedestrian)
	# The walker holds still while a resort door fades.
	if not (is_instance_valid(resort_service) and resort_service.is_transitioning()): occupied.step(frame,camera_rig.yaw,delta)
	if occupied == helicopter:
		if helicopter.landed(): _helicopter_in_flight = false
		elif frame.vertical > 0: _helicopter_in_flight = true
	if not _valid_actor(occupied):
		if not _recover_nearby(): return
	elif occupied.landed(): _last_safe[occupied.get_instance_id()] = occupied.global_transform
	var transit_status: Dictionary=transit_service.status() if is_instance_valid(transit_service) else {}
	_update_camera_space(transit_status)
	camera_rig.update_follow(delta)
	_publish_status(transit_status)

func _reconcile_revision() -> bool:
	if not _revision_pending: return true
	# Geometry edits must invalidate driving before this physics tick, even
	# when Main's ambient presentation refresh has not run yet.
	var traffic: Node3D = view.get("traffic")
	if traffic != null: traffic.graph.refresh()
	var snapshot := view.traversal_snapshot()
	if is_instance_valid(transit_service):
		transit_service.refresh_geometry()
		if is_instance_valid(transit_service.world): snapshot = transit_service.world.apply_physical_projection(snapshot)
	if is_instance_valid(resort_service): resort_service.refresh_geometry()
	traversal.rebuild(view.city,snapshot.chunks,snapshot.networks,snapshot.revision)
	_revision_pending = false
	# A hall that closed around the walker: check the real outdoor pose now
	# that the physical world shows the edited city, else go to a road.
	if is_instance_valid(resort_service) and resort_service.ejection_pending() and not resort_service.settle_ejection():
		if occupied == pedestrian and not _recover_to_road():
			_request_return("No safe place remains. Returning to Build.")
			return false
	for actor: CharacterBody3D in [pedestrian,car,helicopter,selected_vehicle]:
		var invalid_manual_route: bool = actor == occupied and actor is ExploreRouteVehicle and is_instance_valid(transit_service) and transit_service.manual_route_invalidated
		if is_instance_valid(actor) and (invalid_manual_route or not _valid_actor(actor,true)):
			if not _recover_actor(actor):
				_request_return("The city changed and this route is no longer safe.")
				return false
	return true

func _valid_actor(actor: CharacterBody3D, check_obstruction: bool = false) -> bool:
	var feet: Vector3 = actor.feet_position()
	if not feet.is_finite() or feet.x < 0 or feet.z < 0 or feet.x >= City.WIDTH or feet.z >= City.HEIGHT: return false
	if actor == pedestrian and is_instance_valid(resort_service) and resort_service.contains(feet): return true
	if actor == pedestrian and is_instance_valid(transit_service) and transit_service.contains(feet): return true
	if actor is ExploreRouteVehicle: return actor.has_support()
	if feet.y < -1 or feet.y > traversal.max_flight_y()+.01 or traversal.touches_water(feet): return false
	var actor_mode := _actor_mode(actor)
	if check_obstruction:
		var clearance_pose := (actor as ExploreCar).collision_pose() if actor is ExploreCar else _shape_pose(actor.global_transform,actor_mode)
		clearance_pose.origin.y += .002
		if not traversal.has_clearance(clearance_pose,_actor_shape(actor),[actor.get_rid()]): return false
	# Parked aircraft and newly occupied aircraft must prove support. Only a
	# flight actually started by the occupied actor can survive without a floor.
	if actor_mode == 2 and actor == occupied and _helicopter_in_flight and not actor.landed(): return true
	# A jump can temporarily be unsupported while gravity returns it to its floor.
	if actor_mode == 0 and actor.velocity.y != 0: return true
	if actor is ExploreCar:
		var road := actor as ExploreCar
		if road.route_graph != null and not road.route_graph.has_cell(Vector2i(floori(feet.x),floori(feet.z)),&"road") and not traversal.inside_road_tunnel(feet): return false
		return road.has_support()
	if actor is ExploreHelicopter: return (actor as ExploreHelicopter).has_support()
	return not traversal.support_near(feet,.045,.12,[actor.get_rid()]).is_empty()

func _actor_mode(actor: CharacterBody3D) -> int:
	if actor == car or actor == selected_vehicle: return 1
	if actor == helicopter: return 2
	return 0

func _actor_shape(actor: CharacterBody3D) -> Shape3D:
	if actor.has_method("collision_shape"): return actor.collision_shape()
	return ExploreActorProfile.shape(_actor_mode(actor))

func _shape_pose(pose: Transform3D, actor_mode: int) -> Transform3D:
	pose.origin += pose.basis*Vector3.UP*float(ExploreActorProfile.geometry(actor_mode).foot_offset)
	return pose

## The visible Recover action always lands on outdoor pavement, using the same
## road search as Explore entry. A road vehicle or helicopter that fits stays
## occupied; otherwise the player leaves it and stands on the nearest road.
func recover() -> bool:
	if not _active or not is_instance_valid(occupied): return false
	# Recover is also available while suspended, before the next actor tick.
	if not _reconcile_revision():
		_publish_status()
		return false
	var ok := _recover_to_road()
	if ok: _message = "Recovered to the nearest outdoor road."
	else: _request_return("No outdoor road remains. Returning to Build.")
	_publish_status()
	return ok

## Automatic recovery after an invalid pose keeps the nearest supported floor.
func _recover_nearby() -> bool:
	var ok := _recover_actor(occupied)
	if ok: _message = "Moved you back to safe ground."
	else: _request_return("No safe place remains. Returning to Build.")
	_publish_status()
	return ok

const VEHICLE_ROAD_CELLS := 64

func _recover_to_road() -> bool:
	var origin: Vector3 = occupied.global_position
	var cells := _entry_road_cells(origin)
	if occupied is ExploreCar or occupied == helicopter:
		var exclusions: Array[RID] = [occupied.get_rid()]
		var nearby: Array[Vector2i] = cells.slice(0,VEHICLE_ROAD_CELLS)
		var pose := _outdoor_road_pose(nearby,origin,_actor_shape(occupied),exclusions,true)
		if not pose.is_empty():
			_apply_safe_actor_pose(occupied,pose.transform)
			if occupied == helicopter: _helicopter_in_flight = false
			_last_safe[occupied.get_instance_id()] = occupied.global_transform
			_reset_recovered_input()
			return true
	var walker_exclusions: Array[RID] = [pedestrian.get_rid()]
	var walk := _outdoor_road_pose(cells,origin,ExploreActorProfile.shape(ExploreActorProfile.Mode.WALK),walker_exclusions)
	if walk.is_empty(): return false
	pedestrian.clear_support_frame()
	if occupied == pedestrian:
		_apply_safe_actor_pose(pedestrian,walk.transform)
	else:
		var vehicle := occupied
		_leave_vehicle(walk.transform)
		pedestrian.stop_input()
		# A vehicle left off the road still needs its own supported parking.
		if is_instance_valid(vehicle) and not _valid_actor(vehicle): _recover_actor(vehicle)
		camera_rig.configure_target(occupied,mode)
	_last_safe[pedestrian.get_instance_id()] = pedestrian.global_transform
	_reset_recovered_input()
	return true

func _reset_recovered_input() -> void:
	_held.clear()
	_edges.clear()
	_arming = true
	if _touch_enabled: cancel_touch_input()

func _recover_actor(actor: CharacterBody3D) -> bool:
	if actor is ExploreCar and actor.route_graph != null:
		var traffic: Node3D = view.get("traffic")
		if traffic == null: return false
		var route: Dictionary = traffic.get_drive_route(actor.kind,actor.global_position)
		for point: Vector3 in route.get("points",[]):
			var support := traversal.support_near(point,.1,.2,[actor.get_rid()])
			if support.is_empty(): continue
			var pose := Transform3D(Basis.IDENTITY,support.position+Vector3.UP*.002)
			if traversal.has_clearance(_actor_shape_pose(actor,pose),_actor_shape(actor),[actor.get_rid()]):
				actor.apply_safe_pose(pose)
				return true
		return false
	if actor is ExploreRouteVehicle:
		var traffic: Node3D = view.get("traffic")
		if traffic == null: return false
		if actor.kind == &"subway" and is_instance_valid(transit_service):
			var route: Dictionary = transit_service.prepare_drive_route(actor.global_position,true)
			if route.is_empty(): return false
			route["transit"] = true
			return actor.configure(actor.kind,transit_service.network,route)
		var route: Dictionary = traffic.get_drive_route(actor.kind,actor.global_position)
		var configured: bool = actor.configure(actor.kind,traffic.graph,route)
		if configured and actor.kind == &"train" and is_instance_valid(transit_service): transit_service.begin_surface_drive_route(route.get("cells",[]))
		return configured
	if actor == pedestrian and is_instance_valid(resort_service):
		var hall_pose: Dictionary = resort_service.recover_pose(actor.global_position)
		if not hall_pose.is_empty():
			actor.clear_support_frame()
			_apply_safe_actor_pose(actor,hall_pose.transform)
			return true
	if actor == pedestrian and is_instance_valid(transit_service):
		var transit_pose: Dictionary = transit_service.recover_pose(actor.global_position)
		if not transit_pose.is_empty():
			actor.clear_support_frame()
			_apply_safe_actor_pose(actor,transit_pose.transform)
			return true
	var actor_mode := _actor_mode(actor)
	var origin: Vector3 = actor.global_position
	var saved: Variant = _last_safe.get(actor.get_instance_id())
	if saved is Transform3D:
		var point: Vector3 = saved.origin
		var support: Dictionary = traversal.support_near(point,.045,.08,[actor.get_rid()])
		if not support.is_empty():
			# Revalidate the current floor height, including a lowered support.
			var supported_pose: Transform3D = saved
			if actor is ExploreCar: supported_pose.basis = Basis(Vector3.UP,supported_pose.basis.get_euler().y)
			supported_pose.origin.y = support.position.y+.002
			if not traversal.touches_water(supported_pose.origin) and traversal.has_clearance(_actor_shape_pose(actor,supported_pose),_actor_shape(actor),[actor.get_rid()]):
				_apply_safe_actor_pose(actor,supported_pose)
				if actor == helicopter: _helicopter_in_flight = false
				_last_safe[actor.get_instance_id()] = supported_pose
				return true
	var pose: Dictionary = traversal.safe_pose(origin,actor_mode,[actor.get_rid()])
	if pose.is_empty(): return false
	if not traversal.has_clearance(_actor_shape_pose(actor,pose.transform),_actor_shape(actor),[actor.get_rid()]): return false
	_apply_safe_actor_pose(actor,pose.transform)
	if actor == helicopter: _helicopter_in_flight = false
	_last_safe[actor.get_instance_id()] = actor.global_transform
	return true

func _actor_shape_pose(actor: CharacterBody3D, pose: Transform3D) -> Transform3D:
	var shape := _actor_shape(actor)
	pose.origin += pose.basis*Vector3.UP*shape.get_debug_mesh().get_aabb().size.y*.5
	return pose

func _apply_safe_actor_pose(actor: CharacterBody3D, pose: Transform3D) -> void:
	if actor is ExploreCar:
		(actor as ExploreCar).apply_safe_pose(pose)
	else:
		actor.global_transform = pose
		actor.stop_input()

func request_interaction() -> bool:
	if not _active or _suspended: return false
	if mode == 0:
		if is_instance_valid(resort_service):
			# On a casino floor only the door and the tables respond; elevators,
			# marinas, parked and ambient vehicles are never reachable from here.
			if resort_service.is_transitioning(): return false
			if resort_service.is_inside():
				var used := resort_service.interact(pedestrian.global_position)
				_publish_status()
				return used
		if is_instance_valid(transit_service) and transit_service.interact_elevator():
			_publish_status()
			return true
		if is_instance_valid(resort_service):
			var resort := ResortAccess.nearby(view.city,pedestrian.global_position)
			if not resort.is_empty():
				var entered := resort_service.enter(resort)
				_publish_status()
				return entered
		var marina := MarinaAccess.nearby(view.city,pedestrian.global_position)
		if not marina.is_empty(): return _board_marina(&"sailboat",marina)
		var nearest := _nearest_vehicle()
		if nearest == null:
			_ambient_claimed = false
			if _board_ambient(): return true
			# A claimed vehicle that could not be boarded already explained why.
			if not _ambient_claimed: _message = "Walk closer to a vehicle, or choose one from the Explore menu (%s)." % ("Menu" if _touch_enabled else "Esc")
			_publish_status()
			return false
		pedestrian.stop_input()
		pedestrian.clear_support_frame()
		pedestrian.hide()
		pedestrian.collision_layer = 0
		pedestrian.collision_mask = 0
		occupied = nearest
		mode = _actor_mode(nearest)
	else:
		if absf(float(occupied.speed())) >= .01 or (mode == 2 and not occupied.landed()):
			_message = "Land and stop before exiting." if mode == 2 else "Stop before exiting."
			return false
		var exit_pose := _exit_pose()
		if exit_pose.is_empty():
			_message = "There is no clear place to exit."
			return false
		_leave_vehicle(exit_pose.transform)
	_message = ""
	_edges.clear()
	if _touch_enabled: cancel_touch_input()
	camera_rig.configure_target(occupied,mode)
	_publish_status()
	return true

func _leave_vehicle(pose: Transform3D) -> void:
	occupied.stop_input()
	if occupied == helicopter: _helicopter_in_flight = false
	var returned_ambient := not _traffic_claim.is_empty() and occupied == selected_vehicle
	var ended_rail_drive: bool = occupied is ExploreRouteVehicle and occupied.kind in [&"train",&"subway"]
	_release_traffic_claim()
	pedestrian.place(pose)
	pedestrian.collision_layer = ExploreActorProfile.ACTOR
	pedestrian.collision_mask = ExploreActorProfile.WORLD|ExploreActorProfile.ACTOR
	pedestrian.show()
	occupied = pedestrian
	mode = 0
	if (returned_ambient or ended_rail_drive) and is_instance_valid(selected_vehicle):
		_last_safe.erase(selected_vehicle.get_instance_id())
		selected_vehicle.free()
		selected_vehicle = null
	if ended_rail_drive and is_instance_valid(transit_service): transit_service.end_drive_route()

func _nearest_vehicle() -> CharacterBody3D:
	var nearest: CharacterBody3D
	var distance := .65
	for actor: CharacterBody3D in [car,helicopter,selected_vehicle]:
		if not is_instance_valid(actor): continue
		var gap := pedestrian.global_position.distance_to(actor.global_position)
		if gap < distance:
			distance = gap
			nearest = actor
	return nearest

func _exit_pose() -> Dictionary:
	var shape := ExploreActorProfile.shape(0)
	var size: Vector3 = occupied.vehicle_size() if occupied.has_method("vehicle_size") else ExploreActorProfile.geometry(mode).size
	for offset: Vector3 in [Vector3(size.x*.5+.06,0,0),Vector3(-size.x*.5-.06,0,0),Vector3(0,0,size.z*.5+.06),Vector3(0,0,-size.z*.5-.06)]:
		var candidate: Vector3 = occupied.global_position+occupied.global_basis*offset
		var support: Dictionary
		if is_instance_valid(transit_service): support = transit_service.support_for(candidate)
		var transit_exit := not support.is_empty()
		if support.is_empty(): support = traversal.support_near(candidate,.045,.10,[pedestrian.get_rid()])
		if support.is_empty() or (traversal.touches_water(support.position) and not transit_exit): continue
		if absf(float(support.position.y)-candidate.y)>.10: continue
		var pose := Transform3D(Basis.IDENTITY,support.position+Vector3.UP*.002)
		if traversal.has_clearance(_shape_pose(pose,0),shape,[pedestrian.get_rid()]): return {"transform":pose}
	if occupied == selected_vehicle and occupied is ExploreRouteVehicle and occupied.domain == &"water":
		return _marina_exit_pose()
	return {}

func _dry_marina_pose(candidate: Vector3, water_height: float) -> Dictionary:
	var support := traversal.support_near(candidate,.045,.10,[pedestrian.get_rid()])
	if support.is_empty() or traversal.touches_water(support.position): return {}
	# The dock's gangway joins the bank; the nearby floor and capsule still
	# pass the ordinary support and obstruction queries above/below.
	if absf(float(support.position.y)-water_height)>MarinaAccess.MAX_LANDING_RISE: return {}
	var capsule := ExploreActorProfile.shape(0) as CapsuleShape3D
	# Lift the rounded capsule just enough to clear this supported plane.
	# On slopes, placing its lowest point on the floor embeds its uphill rim.
	var skin := .002+capsule.radius*(1.0/float(support.normal.y)-1.0)
	var pose := Transform3D(Basis.IDENTITY,support.position+Vector3.UP*skin)
	if not traversal.has_clearance(_shape_pose(pose,0),capsule,[pedestrian.get_rid()]): return {}
	return {"transform":pose}

func _marina_exit_pose() -> Dictionary:
	var marina := MarinaAccess.nearby(view.city,occupied.global_position)
	if not _marina_dock.is_empty() and MarinaAccess.exists(view.city,_marina_dock.rect) and occupied.global_position.distance_to(_marina_dock.berth)<=.65:
		var remembered := _dry_marina_pose(_marina_dock.landing,occupied.global_position.y)
		if not remembered.is_empty(): return remembered
		marina={"rect":_marina_dock.rect}
	if marina.is_empty(): return {}
	var beside_berth := false
	for route: Dictionary in MarinaAccess.launch_routes(view.city,view.traffic.graph,marina.rect,occupied.global_position):
		if occupied.global_position.distance_to(route.points[0])<=.65:
			beside_berth=true
			break
	if not beside_berth: return {}
	for point: Vector3 in MarinaAccess.landings(view.city,marina.rect):
		var landing := _dry_marina_pose(point,occupied.global_position.y)
		if not landing.is_empty(): return landing
	return {}

func _board_marina(kind: StringName, marina: Dictionary) -> bool:
	view.traffic.graph.refresh()
	var landing := pedestrian.global_position
	if not traversal.touches_water(landing):
		for route: Dictionary in MarinaAccess.launch_routes(view.city,view.traffic.graph,marina.rect,landing):
			if _dry_marina_pose(landing,route.points[0].y).is_empty(): continue
			if _select_vehicle(kind,{},route):
				_marina_dock={"rect":marina.rect,"landing":landing,"berth":occupied.global_position}
				return true
	_message="This marina has no clear berth connected to navigable water."
	_publish_status()
	return false

func _on_geometry_rebuilt(_revision: int) -> void:
	if _active: _revision_pending = true

func _update_camera_space(transit_status: Dictionary) -> void:
	var subway_driver: bool=mode==1 and occupied is ExploreRouteVehicle and occupied.kind==&"subway"
	camera_rig.set_interior(subway_driver or (mode==0 and bool(transit_status.get("interior",false))) or (mode!=2 and is_instance_valid(traversal) and is_instance_valid(occupied) and traversal.inside_road_tunnel(occupied.global_position)))
	camera_rig.set_cabin(transit_status.get("cabin_bounds",AABB()),transit_status.get("cabin_transform",Transform3D.IDENTITY),mode==0 and bool(transit_status.get("passenger",false)))

func _publish_status(transit_status: Dictionary = {}) -> void:
	if not _active or not is_instance_valid(occupied): return
	var prompt := "F to exit" if mode != 0 else ""
	var inside_resort := mode == 0 and is_instance_valid(resort_service) and resort_service.is_inside()
	var resort_door: Dictionary = ResortAccess.nearby(view.city,pedestrian.global_position) if mode == 0 and not inside_resort else {}
	if inside_resort: prompt = resort_service.prompt(pedestrian.global_position)
	elif not resort_door.is_empty(): prompt = CasinoLines.enter_prompt(ResortThemes.resort_name(resort_door.key))
	elif mode == 0:
		var marina := MarinaAccess.nearby(view.city,pedestrian.global_position)
		if not marina.is_empty(): prompt="F to board a boat at the marina"
		elif _nearest_vehicle() != null: prompt = "F to enter nearby vehicle"
		else:
			var now := Time.get_ticks_msec()
			if now >= _ambient_prompt_at:
				_ambient_prompt_at = now+200
				var traffic: Node3D = view.get("traffic")
				_ambient_nearby = traffic.nearest_drivable_vehicle(pedestrian.global_position,.65) if traffic != null else {}
			if not _ambient_nearby.is_empty(): prompt = "F to enter "+CityTrafficCatalog.display_name(StringName(_ambient_nearby.kind))
	if transit_status.is_empty() and is_instance_valid(transit_service): transit_status=transit_service.status()
	if mode==0 and not inside_resort and not String(transit_status.get("elevator_prompt","")).is_empty(): prompt=String(transit_status.elevator_prompt)
	var status := {"vehicle":str(occupied.get("kind")) if occupied == selected_vehicle else "","mode":mode,"speed":occupied.velocity.length(),"altitude":float(occupied.altitude()) if mode == 2 else 0.0,"prompt":prompt,"message":_message}
	if is_instance_valid(resort_service):
		status["resort"] = resort_service.status()
		if not _casino_table.is_empty(): status["table_camera"] = casino_table_pose(_casino_table)
	hud.set_status(status)
	if is_instance_valid(transit_service):
		_update_camera_space(transit_status)
		hud.set_transit_status(transit_status)
	status_changed.emit(status)

func _exit_tree() -> void:
	dispose()

func _on_casino_table(resort: StringName, game: StringName, table: Dictionary) -> void:
	_casino_table = table
	_publish_status()
	casino_table_requested.emit(resort,game,table)

## The authored seated camera for a requested casino table (world space).
func casino_table_pose(table: Dictionary) -> Transform3D:
	return resort_service.table_camera(table) if is_instance_valid(resort_service) else Transform3D.IDENTITY

## Hold the table's seated view on the Explore camera while its game is open.
func hold_casino_table_view(table: Dictionary, seconds: float = .45) -> void:
	if is_instance_valid(camera_rig): camera_rig.set_table_view(casino_table_pose(table),seconds)

## Release the held table view; the follow camera resumes behind the walker.
func release_casino_table_view() -> void:
	_casino_table = {}
	if is_instance_valid(camera_rig): camera_rig.clear_table_view()
	_publish_status()

func select_vehicle(kind: StringName) -> bool:
	if not _active or not _suspended: return false
	var refusal := _selection_refusal(kind)
	if not refusal.is_empty():
		_message = refusal
		_publish_status()
		return false
	var ok := false
	var boarded := false
	if occupied == pedestrian and CityTrafficCatalog.domain(kind)==&"water":
		var marina := MarinaAccess.nearby(view.city,pedestrian.global_position)
		if not marina.is_empty():
			ok = _board_marina(kind,marina)
			boarded = true
	if not boarded: ok = _select_vehicle(kind)
	# Choosing a vehicle from the paused panel starts driving it right away.
	if ok: resume()
	return ok

## Furthest a parked helicopter may be from the walker to be chosen in the
## Explore menu; other vehicles likewise appear on a route within this reach.
const HELICOPTER_SELECT_REACH := 8.0

## Why the Explore menu cannot hand over `kind` here, or "" when it can.
## A passenger, a walker on a casino floor or inside a station (for anything
## other than the rail vehicle running there) must step outside first, and
## the session helicopter is only chosen near where it is parked.
func _selection_refusal(kind: StringName) -> String:
	if occupied != pedestrian or not is_instance_valid(pedestrian): return ""
	var feet := pedestrian.global_position
	if is_instance_valid(transit_service) and is_instance_valid(transit_service.train) and transit_service.train.contains(feet):
		return "Leave the train first."
	if is_instance_valid(resort_service) and (resort_service.is_inside() or resort_service.is_transitioning()):
		return "Step outside the resort first."
	if CityTrafficCatalog.domain(kind) != &"rail" and is_instance_valid(transit_service) and transit_service.indoors(feet):
		return "Step outside the station first."
	if kind == &"helicopter" and is_instance_valid(helicopter):
		# Measured across the ground (a pad on a roof or bridge is as near as
		# it looks), the same distance the message reports.
		var away := Vector2(helicopter.global_position.x-feet.x,helicopter.global_position.z-feet.z).length()
		if away > HELICOPTER_SELECT_REACH:
			return "The helicopter is parked %d tiles away. Walk back to it to fly." % roundi(away)
	return ""

func _select_vehicle(kind: StringName, claim: Dictionary = {}, marina_route: Dictionary = {}) -> bool:
	if not CityTrafficCatalog.is_drivable(kind):
		_message = "Airplanes can't be driven." if kind == &"plane" else "Unknown vehicle."
		_publish_status()
		return false
	if occupied != pedestrian:
		_message = "Exit your current vehicle before choosing another."
		_publish_status()
		return false
	if kind == &"helicopter" and is_instance_valid(helicopter):
		# The session owns one helicopter. Boarding an ambient one lands that
		# aircraft at the claimed pose; never occupy it wherever it is parked.
		if not claim.is_empty() and not _land_helicopter_at(claim):
			_message = "The helicopter has no clear landing space here."
			_publish_status()
			return false
		_release_traffic_claim()
		_traffic_claim = claim
		_claimed_vehicle = helicopter if not claim.is_empty() else null
		_occupy(helicopter)
		return true
	var traffic: Node3D = view.get("traffic")
	if traffic == null:
		_message = "No compatible traffic route is available."
		_publish_status()
		return false
	var origin: Vector3 = claim.get("position",pedestrian.global_position)
	var route: Dictionary
	var route_graph: RefCounted = traffic.graph
	if not marina_route.is_empty(): route=marina_route
	elif kind == &"subway" and is_instance_valid(transit_service):
		route = transit_service.prepare_drive_route(origin,true)
		if not route.is_empty():
			route["transit"] = true
			route_graph = transit_service.network
	else: route = traffic.get_drive_route(kind,origin)
	if route.is_empty():
		_message = _no_route_message(kind)
		_publish_status()
		return false
	var candidate: CharacterBody3D
	if CityTrafficCatalog.domain(kind) == &"road":
		var road := ExploreCar.new()
		view.world.add_child(road)
		road.bind(traversal)
		road.configure_kind(kind)
		road.route_graph = traffic.graph
		for point: Vector3 in route.points:
			if point.distance_to(origin)>8.0: continue
			var support := traversal.support_near(point,.1,.2,[pedestrian.get_rid()])
			if support.is_empty(): continue
			var pose := Transform3D(Basis.IDENTITY,support.position+Vector3.UP*.002)
			if traversal.has_clearance(_actor_shape_pose(road,pose),road.collision_shape(),[road.get_rid(),pedestrian.get_rid()]):
				road.apply_safe_pose(pose)
				candidate = road
				break
		if candidate == null: road.free()
	else:
		var route_actor := ExploreRouteVehicle.new()
		view.world.add_child(route_actor)
		if route_actor.configure(kind,route_graph,route):
			var exclude: Array[RID]=[route_actor.get_rid(),pedestrian.get_rid()]
			if is_instance_valid(selected_vehicle): exclude.append(selected_vehicle.get_rid())
			if route_actor.domain!=&"water" or traversal.has_clearance(route_actor.collision_pose(),route_actor.collision_shape(),exclude): candidate=route_actor
		if candidate == null: route_actor.free()
	if candidate == null:
		_message = "The route has no clear space for this vehicle."
		_publish_status()
		return false
	if kind == &"train" and is_instance_valid(transit_service): transit_service.begin_surface_drive_route(route.get("cells",[]))
	_release_traffic_claim()
	if is_instance_valid(selected_vehicle):
		_last_safe.erase(selected_vehicle.get_instance_id())
		selected_vehicle.free()
	selected_vehicle = candidate
	_marina_dock.clear()
	selected_vehicle.name = "ExploreSelectedVehicle"
	selected_vehicle.recovery_requested.connect(func(reason: String) -> void:
		_message = reason
		_pending_recovery = true)
	_traffic_claim = claim
	_claimed_vehicle = selected_vehicle if not claim.is_empty() else null
	_occupy(selected_vehicle)
	return true

func _land_helicopter_at(claim: Dictionary) -> bool:
	var at: Variant = claim.get("position")
	if not (at is Vector3) or not (at as Vector3).is_finite(): return false
	var exclusions: Array[RID] = [helicopter.get_rid(),pedestrian.get_rid()]
	var support := traversal.support_near(at,.1,.2,exclusions)
	if support.is_empty(): return false
	var feet: Vector3 = support.position+Vector3.UP*.002
	if traversal.touches_water(feet) or feet.y>traversal.max_flight_y(): return false
	var pose := Transform3D(Basis(Vector3.UP,float(claim.get("yaw",0.0))),feet)
	if not traversal.has_clearance(_shape_pose(pose,ExploreActorProfile.Mode.FLY),_actor_shape(helicopter),exclusions): return false
	_apply_safe_actor_pose(helicopter,pose)
	_helicopter_in_flight = false
	_last_safe[helicopter.get_instance_id()] = pose
	return true

func _occupy(actor: CharacterBody3D) -> void:
	pedestrian.stop_input()
	pedestrian.clear_support_frame()
	pedestrian.hide()
	pedestrian.collision_layer = 0
	pedestrian.collision_mask = 0
	occupied = actor
	mode = _actor_mode(actor)
	_held.clear()
	_edges.clear()
	_arming = true
	if _touch_enabled: cancel_touch_input()
	_message = ""
	camera_rig.configure_target(occupied,mode)
	_publish_status()

func _board_ambient() -> bool:
	var traffic: Node3D = view.get("traffic")
	if traffic == null or not traffic.has_method("claim_nearby_vehicle"): return false
	var claim: Dictionary = traffic.claim_nearby_vehicle(pedestrian.global_position,.65)
	if claim.is_empty(): return false
	_ambient_claimed = true
	if _select_vehicle(StringName(claim.kind),claim): return true
	traffic.release_vehicle(claim,claim.position)
	return false

func _release_traffic_claim() -> void:
	if _traffic_claim.is_empty(): return
	var traffic: Node3D = view.get("traffic") if is_instance_valid(view) else null
	if traffic != null and traffic.has_method("release_vehicle"):
		var position: Vector3 = _claimed_vehicle.global_position if is_instance_valid(_claimed_vehicle) else _traffic_claim.position
		traffic.release_vehicle(_traffic_claim,position)
	_traffic_claim.clear()
	_claimed_vehicle = null

static func _no_route_message(kind: StringName) -> String:
	var noun := CityTrafficCatalog.display_name(kind).to_lower()
	match CityTrafficCatalog.domain(kind):
		&"water": return "No navigable water nearby for the %s." % noun
		&"rail": return "No connected track nearby for the %s." % noun
		&"road": return "No connected road nearby for the %s." % noun
	return "No connected route nearby for the %s." % noun
