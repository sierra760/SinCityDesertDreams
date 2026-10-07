# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The physical projection outlives a session for the same view and city, so a
## repeat entry reuses unchanged bodies; it is never reused for another city.
extends "res://tests/exploration/async_test_case.gd"

const SESSION_PATH := "res://scripts/exploration/city_exploration_controller.gd"
const GROUND := 4*CityGeometry3D.HEIGHT
const ORIGIN := Vector3(22.5,GROUND,20.5)

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

func _road_city() -> City:
	var value := flat_city()
	value.building.put(22,20,30)
	return value

func _setup(value: City) -> void:
	city = value
	view = SnapshotView.new()
	root.add_child(view)
	_bind(city)
	hud = ExploreHUD.new()
	root.add_child(hud)
	session = load(SESSION_PATH).new()
	root.add_child(session)
	session.bind(view,hud)
	session.input_blocked = func() -> bool: return false

func _bind(value: City) -> void:
	view.bind_city(value)
	view.sample_chunks = [CityGeometry3D.build_chunk(value,Rect2i(16,16,16,16))]
	view.networks.rebuild(value)
	view.sample_networks = view.networks.physical_data()

func after_each() -> void:
	if is_instance_valid(session): session.free()
	if is_instance_valid(view): view.free()
	if is_instance_valid(hud): hud.free()
	session = null
	view = null
	hud = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await physics_frame

func _retained_world() -> Node:
	return view.world.get_node_or_null("TraversalWorld")

func _body_ids(world: Node) -> Array[int]:
	var ids: Array[int] = []
	for body: Node in world.get_children(): ids.append(body.get_instance_id())
	return ids

func _enter() -> bool:
	await physics_frame
	var entered: bool = session.enter(city,ORIGIN)
	check(entered,"supported dry entry succeeds")
	await physics_frame
	return entered

func test_repeat_entry_reuses_every_unchanged_body() -> void:
	_setup(_road_city())
	if not await _enter(): return
	var world: CityTraversalWorld3D = session.traversal
	var world_id := world.get_instance_id()
	var ids := _body_ids(world)
	check_eq(world.rebuild_count,1)
	var ceiling := world.max_flight_y()
	var spawn: Vector3 = session.pedestrian.global_position
	session.leave()
	check(session.traversal == null,"no session world is exposed between sessions")
	check_eq(view.world.find_children("Explore*","CharacterBody3D",true,false).size(),0,"leave frees every actor")
	var retained := _retained_world()
	check(retained != null and retained.get_instance_id() == world_id,"inert projection stays under the view between sessions")
	check_eq(_body_ids(retained),ids,"leave never rebuilds or frees unchanged bodies")
	if not await _enter(): return
	check_eq(session.traversal.get_instance_id(),world_id,"same view and city reuse the retained world")
	check_eq(_body_ids(session.traversal),ids,"unchanged faces, boxes and transforms keep their bodies")
	check_eq(session.traversal.rebuild_count,2,"re-entry still reconciles the current snapshot")
	check_eq(session.traversal.revision,view.revision)
	check_eq(session.traversal.max_flight_y(),ceiling,"ceiling is recomputed to the same value")
	check(not session.traversal.support_near(spawn,.045,.08,no_exclusions).is_empty(),"retained floor still answers support queries")
	check_eq(Vector2i(floori(session.pedestrian.global_position.x),floori(session.pedestrian.global_position.z)),Vector2i(22,20))

func test_changed_floor_between_sessions_replaces_only_its_body() -> void:
	_setup(_road_city())
	if not await _enter(): return
	var world: CityTraversalWorld3D = session.traversal
	var floor_id: int = world._retained[Vector2i(0,0)].body.get_instance_id()
	var road_id: int = world._retained[Vector2i(-1,0)].body.get_instance_id()
	var pavement_y: float = session.pedestrian.global_position.y
	session.leave()
	# Lower the terrain beneath the unchanged road: the pavement body remains
	# valid support while the chunk floor body must be replaced.
	var changed: Dictionary = view.sample_chunks[0].duplicate(true)
	var faces: PackedVector3Array = changed.physical_floor_faces
	for i: int in faces.size(): faces[i].y -= .05
	changed.physical_floor_faces = faces
	view.sample_chunks = [changed]
	view.revision += 1
	if not await _enter(): return
	world = session.traversal
	check_eq(world.revision,view.revision,"re-entry adopts the newer geometry revision")
	check_ne(world._retained[Vector2i(0,0)].body.get_instance_id(),floor_id,"changed chunk floor gets a fresh body")
	check_eq(world._retained[Vector2i(-1,0)].body.get_instance_id(),road_id,"unchanged road surface keeps its body")
	check(absf(session.pedestrian.global_position.y-pavement_y)<.0001,"entry still stands on the retained pavement, not the lowered terrain")
	var lowered := Vector3(18.5,GROUND-.05,18.5)
	var support: Dictionary = world.support_near(lowered+Vector3.UP*.01,.02,.03,no_exclusions)
	check(not support.is_empty() and absf(support.position.y-(GROUND-.05))<.0005,"queries see the replaced lowered floor")

func test_another_city_never_reuses_a_stale_world() -> void:
	_setup(_road_city())
	if not await _enter(): return
	var stale: WeakRef = weakref(session.traversal)
	session.leave()
	var other := _road_city()
	other.building.put(26,20,30)
	city = other
	_bind(other)
	if not await _enter(): return
	check(stale.get_ref() == null,"projection of a different city is released")
	check_ne(session.traversal.get_instance_id(),0)
	check_eq(session.traversal.rebuild_count,1,"the other city gets a fresh projection")
	check_eq(view.world.find_children("TraversalWorld","",true,false).size(),1,"exactly one physical projection exists")

func test_dispose_and_rebind_release_the_retained_world() -> void:
	_setup(_road_city())
	if not await _enter(): return
	var retained: WeakRef = weakref(session.traversal)
	session.leave()
	check(retained.get_ref() != null)
	session.dispose()
	check(retained.get_ref() == null,"dispose frees the retained projection")
	check(_retained_world() == null)
	if not await _enter(): return
	retained = weakref(session.traversal)
	session.leave()
	var other_view := SnapshotView.new()
	root.add_child(other_view)
	var other_hud := ExploreHUD.new()
	root.add_child(other_hud)
	session.bind(other_view,other_hud)
	check(retained.get_ref() == null,"binding another view frees the old view's projection")
	other_view.free()
	other_hud.free()

func test_rejected_entry_exposes_no_session_world() -> void:
	_setup(_road_city())
	view.sample_chunks.clear()
	check(not session.enter(city,ORIGIN))
	check(session.traversal == null and _retained_world() == null,"an entry without support creates no projection")
	_bind(city)
	if not await _enter(): return
	session.leave()
	view.sample_chunks.clear()
	check(not session.enter(city,ORIGIN),"missing support still rejects entry")
	check(session.traversal == null,"rejected entry leaves no active world")
	check(_retained_world() != null,"an earlier valid projection is retained, not rebuilt")

func test_memory_warning_releases_only_an_idle_projection() -> void:
	_setup(_road_city())
	if not await _enter(): return
	var active: WeakRef = weakref(session.traversal)
	session.notification(NOTIFICATION_OS_MEMORY_WARNING)
	check(active.get_ref() != null and session.is_active(),"an active session keeps its world")
	session.leave()
	session.notification(NOTIFICATION_OS_MEMORY_WARNING)
	check(active.get_ref() == null and _retained_world() == null,"idle projection is released under memory pressure")
	if not await _enter(): return
	check_eq(session.traversal.rebuild_count,1,"next entry rebuilds from the canonical snapshot")
	check(not session.traversal.support_near(session.pedestrian.global_position,.045,.08,no_exclusions).is_empty())
