# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Shared city view, HUD and session setup for Explore session tests.
extends "res://tests/exploration/async_test_case.gd"
const SESSION_PATH := "res://scripts/exploration/city_exploration_controller.gd"
const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
const GROUND := 4*CityGeometry3D.HEIGHT

class SnapshotView extends CityView3D:
	var sample_chunks: Array[Dictionary] = []
	var sample_networks: Dictionary = {}
	var revision := 1
	func traversal_snapshot() -> Dictionary:
		return {"city":city,"chunks":sample_chunks,"networks":sample_networks,"revision":revision}

var view: SnapshotView
var hud: ExploreHUD
var session: Node
var city: City
var no_exclusions: Array[RID] = []

func _setup(value: City = null) -> bool:
	check(ResourceLoader.exists(SESSION_PATH),"session controller exists")
	if not ResourceLoader.exists(SESSION_PATH): return false
	city = value if value != null else flat_city()
	if value == null: city.building.put(22,20,30)
	view = SnapshotView.new()
	root.add_child(view)
	view.bind_city(city)
	view.sample_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,16,16))]
	view.networks.rebuild(city)
	view.sample_networks = view.networks.physical_data()
	hud = ExploreHUD.new()
	root.add_child(hud)
	session = load(SESSION_PATH).new()
	root.add_child(session)
	session.bind(view,hud)
	session.input_blocked = func() -> bool: return false
	return true

func after_each() -> void:
	for key: Key in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SPACE,KEY_CTRL,KEY_SHIFT,KEY_Q,KEY_E,KEY_F]:
		Input.parse_input_event(_key(key,false))
	if is_instance_valid(session): session.free()
	if is_instance_valid(view): view.free()
	if is_instance_valid(hud): hud.free()
	session = null
	view = null
	hud = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await physics_frame

func _enter(origin: Vector3 = Vector3(22.5,GROUND,20.5)) -> bool:
	await physics_frame
	var entered: bool = session.enter(city,origin)
	check(entered,"supported dry entry succeeds")
	await physics_frame
	return entered

func _remove_bridge_and_publish() -> void:
	for x: int in range(20,24): city.building.put(x,20,0)
	view.networks.rebuild(city)
	view.sample_networks = view.networks.physical_data()
	view.sample_chunks = [CityGeometry3D.build_chunk(city,Rect2i(16,16,16,16))]
	view.revision += 1
	view.geometry_rebuilt.emit(view.revision)

func _check_supported_clear(actor: CharacterBody3D, actor_mode: int) -> void:
	var world: CityTraversalWorld3D = session.get("traversal")
	var exclude: Array[RID] = [actor.get_rid()]
	check(not world.support_near(actor.feet_position(),.01,.01,exclude).is_empty(),"recovered feet rest on current support")
	check(not world.touches_water(actor.feet_position()),"recovered feet are dry")
	var shape_pose := actor.global_transform
	shape_pose.origin += shape_pose.basis*Vector3.UP*float(ExploreActorProfile.geometry(actor_mode).foot_offset)
	check(world.has_clearance(shape_pose,ExploreActorProfile.shape(actor_mode),exclude),"recovered full body has current clearance")

func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event

func _physical_key(code: Key, pressed: bool) -> void:
	Input.parse_input_event(_key(code,pressed))
	for frame in 4:
		await process_frame
		if Input.is_physical_key_pressed(code) == pressed: break
	check_eq(Input.is_physical_key_pressed(code),pressed,"physical input precondition is applied before transition")
