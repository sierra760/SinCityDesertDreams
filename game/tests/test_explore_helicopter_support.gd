# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The helicopter's landing state must follow physical full-box support.
extends "res://tests/exploration/async_test_case.gd"

const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
const GROUND := 4 * CityGeometry3D.HEIGHT
var fixture: Node3D
var helicopter: ExploreHelicopter
var session: CityExplorationController
var reports: Array[String] = []
var old_physics_ticks: int

func before_all() -> void:
	old_physics_ticks = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 60

func after_all() -> void:
	Engine.physics_ticks_per_second = old_physics_ticks

func after_each() -> void:
	# The session is a query-only fixture here. Detach borrowed siblings before
	# its _exit_tree cleanup so it never frees nodes owned by the fixture.
	if is_instance_valid(session):
		session.occupied = null
		session.helicopter = null
		session.pedestrian = null
		session.traversal = null
	if is_instance_valid(fixture): fixture.free()
	fixture = null
	helicopter = null
	session = null
	reports.clear()
	await physics_frame

func setup(city: City, feet: Vector3) -> void:
	fixture = Fixture.attach(self,city)
	helicopter = ExploreHelicopter.new()
	fixture.add_child(helicopter)
	helicopter.bind(fixture.get_node("traversal"))
	helicopter.position = feet
	helicopter.recovery_requested.connect(func(reason: String) -> void: reports.append(reason))
	session = CityExplorationController.new()
	fixture.add_child(session)
	session.traversal = fixture.get_node("traversal")
	session.helicopter = helicopter
	session.occupied = helicopter
	session.mode = ExploreActorProfile.Mode.FLY

func descend(ticks: int) -> void:
	for tick in ticks:
		var frame := ExploreInputFrame.idle()
		frame.vertical = -1.0
		helicopter.step(frame,0.0,1.0/60.0)
		await physics_frame

func test_deck_nose_contact_counts_as_supported_landing() -> void:
	# Body centre Z21.07 is beyond the deck's edge at Z21; the front of the
	# physical box rests on the code 75 deck at tile (22,20).
	setup(Fixture.underpass_city(),Vector3(22.5,GROUND+1.2,21.07))
	await physics_frame
	await descend(120)
	var world: CityTraversalWorld3D = fixture.get_node("traversal")
	var centre := world.support_near(helicopter.position,.003,.006,[helicopter.get_rid()])
	var nose := world.support_near(helicopter.position+Vector3(0,0,-.125),.045,.2,[helicopter.get_rid()])
	var contact := helicopter.move_and_collide(Vector3.DOWN*.006,true,.001,true)
	check(centre.is_empty(),"a single centre landing ray misses this deck")
	check(not nose.is_empty() and nose.normal.y>=CityTraversalWorld3D.MIN_NORMAL_Y,"front of the full box touches the upper dry deck")
	check(contact!=null and contact.get_normal().y>=CityTraversalWorld3D.MIN_NORMAL_Y,"a test-only full-box sweep proves an upward contact")
	check(not world.touches_water(helicopter.position) and not world.touches_water(nose.position),"contact is dry")
	check(helicopter.velocity.length()<.001 and reports.is_empty(),"deck contact stops descent without recovery")
	check(helicopter.landed(),"full-box deck contact is a landing")
	check(bool(session.call("_valid_actor",helicopter)),"session accepts the same physically supported landing")
	var stopped := helicopter.position
	await descend(30)
	check(helicopter.landed() and helicopter.position.distance_to(stopped)<.001 and reports.is_empty(),"edge landing remains valid across subsequent physics ticks")
	var pedestrian := ExplorePedestrian.new()
	fixture.add_child(pedestrian)
	pedestrian.bind(world)
	pedestrian.position = Vector3(24.5,GROUND,21.5)
	session.pedestrian = pedestrian
	var exit_pose: Dictionary = session.call("_exit_pose")
	check(not exit_pose.is_empty(),"the upper deck has a clear, supported exit beside the aircraft")
	if not exit_pose.is_empty():
		var at: Transform3D = exit_pose.transform
		var shape_at := at.translated_local(Vector3.UP*float(ExploreActorProfile.geometry(0).foot_offset))
		check(not world.support_near(at.origin,.045,.10,[pedestrian.get_rid()]).is_empty(),"exit candidate has actual floor")
		check(world.has_clearance(shape_at,ExploreActorProfile.shape(0),[pedestrian.get_rid()]),"exit candidate is physically clear")
	world.clear()
	helicopter.step(ExploreInputFrame.idle(),0.0,1.0/60.0)
	helicopter.step(ExploreInputFrame.idle(),0.0,1.0/60.0)
	check(reports==["unsupported"],"removed deck contact requests recovery exactly once")
	await after_each()

func test_unsupported_hover_and_blocked_under_deck_do_not_land() -> void:
	setup(Fixture.underpass_city(),Vector3(22.5,GROUND+.04,20.5))
	await physics_frame
	var frame := ExploreInputFrame.idle()
	frame.vertical = 1.0
	for tick in 180:
		helicopter.step(frame,0.0,1.0/60.0)
		await physics_frame
	check(not helicopter.landed(),"underside contact cannot become upward floor support")
	check(helicopter.position.y+.14<GROUND+.285,"full box remains below the lowered highway underside")
	check(reports.is_empty(),"blocking the underside does not demand recovery")
	await after_each()
	setup(flat_city(),Vector3(22.5,GROUND+.8,22.5))
	await physics_frame
	check(not helicopter.landed() and not bool(session.call("_valid_actor",helicopter)),"unsupported parked air pose is invalid")
	await after_each()

func test_centered_upper_deck_and_flat_takeoff_remain_supported() -> void:
	setup(Fixture.underpass_city(),Vector3(22.5,GROUND+1.2,20.5))
	await physics_frame
	await descend(240)
	check(helicopter.landed() and bool(session.call("_valid_actor",helicopter)),"centered upper-deck landing remains valid")
	check(helicopter.position.y>GROUND+.379 and reports.is_empty(),"lowered highway deck does not snap to lower road")
	await after_each()
	setup(flat_city(),Vector3(22.5,GROUND+.002,22.5))
	await physics_frame
	helicopter.step(ExploreInputFrame.idle(),0.0,1.0/60.0)
	check(helicopter.landed(),"ordinary flat-ground parking has physical support")
	var ascend := ExploreInputFrame.idle()
	ascend.vertical = 1.0
	for tick in 120:
		helicopter.step(ascend,0.0,1.0/60.0)
		await physics_frame
	check(not helicopter.landed() and helicopter.position.y>GROUND+.6 and reports.is_empty(),"takeoff can leave support without false recovery")
	await descend(220)
	check(helicopter.landed() and bool(session.call("_valid_actor",helicopter)) and reports.is_empty(),"ordinary re-landing remains supported")
	await after_each()

func test_wet_contact_never_authorizes_exit() -> void:
	var city := flat_city()
	city.terrain.put(22,22,Terrain.SUBMERGED)
	city.set_heights(22,22,2,4)
	setup(city,Vector3(22.5,GROUND+.8,22.5))
	await physics_frame
	await descend(180)
	check(not helicopter.landed(),"wet floor cannot count as a supported landing")
	check(not bool(session.call("_valid_actor",helicopter)),"wet aircraft pose is invalid for session and exit")
	check(reports.size()==1 and reports[0]=="water","water contact requests one bounded recovery")
	await after_each()

func test_actor_layer_top_is_not_a_world_landing() -> void:
	setup(flat_city(),Vector3(22.5,GROUND+1.2,22.5))
	# A separate actor-layer body blocks the swept helicopter but is not a
	# traversable floor. Its top is far above the actual dry ground below.
	Fixture.box(fixture,Vector3(22.5,GROUND+.35,22.5),Vector3(.7,.7,.7),ExploreActorProfile.ACTOR)
	await physics_frame
	await descend(180)
	var contact := helicopter.move_and_collide(Vector3.DOWN*.006,true,.001,true)
	check(contact!=null and contact.get_normal().y>=CityTraversalWorld3D.MIN_NORMAL_Y,"full box physically rests on actor-only top")
	check(not helicopter.landed(),"actor-only collision cannot authorize a landing")
	check(not bool(session.call("_valid_actor",helicopter)),"session rejects actor-only support")
	await after_each()
