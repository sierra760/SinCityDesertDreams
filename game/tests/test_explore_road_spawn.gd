# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
const TunnelFixture := preload("res://tests/exploration/road_tunnel_fixture.gd")
const MAIN := preload("res://scenes/main.tscn")
const GROUND := 4*CityGeometry3D.HEIGHT

class SnapshotView extends CityView3D:
	var sample_chunks: Array[Dictionary] = []
	func traversal_snapshot() -> Dictionary:
		return {"chunks":sample_chunks,"networks":networks.physical_data(),"revision":1}

var view: SnapshotView
var hud: ExploreHUD
var session: CityExplorationController
var host: GameHost

func setup(city: City, regions: Array[Rect2i] = [Rect2i(16,16,16,16)]) -> void:
	view = SnapshotView.new()
	root.add_child(view)
	view.bind_city(city)
	for region: Rect2i in regions: view.sample_chunks.append(CityGeometry3D.build_chunk(city,region))
	view.networks.rebuild(city)
	hud = ExploreHUD.new()
	root.add_child(hud)
	session = CityExplorationController.new()
	root.add_child(session)
	session.bind(view,hud)
	session.input_blocked = func() -> bool: return false
	await physics_frame

func after_each() -> void:
	if is_instance_valid(session):
		session.dispose()
		session.free()
	if is_instance_valid(view): view.free()
	if is_instance_valid(hud): hud.free()
	if is_instance_valid(host):
		if host.sim._ctx != null: host.sim._ctx.systems.clear()
		host.sim.systems.clear()
		host.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_road_spawn.cfg"))
	session = null
	view = null
	hud = null
	host = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await physics_frame

func check_spawn(cell: Vector2i, height: float) -> void:
	session.set_physics_process(false)
	var feet := session.pedestrian.global_position
	check_eq(Vector2i(floori(feet.x),floori(feet.z)),cell,"player starts on the expected road tile")
	check_between(feet.y,height+.0019,height+.0021,"feet rest on pavement, never on terrain or a roof")
	check(not session.traversal.inside_road_tunnel(feet),"entry stays outside tunnel interiors")
	check(not session.traversal.touches_water(feet),"entry stays above water")
	var collider := session.pedestrian.get_child(0) as CollisionShape3D
	check(session.traversal.has_clearance(collider.global_transform,collider.shape,[session.pedestrian.get_rid()]),"entry capsule clears physical obstacles")

func test_roadless_city_rejects_dry_lots_zones_rails_and_utilities() -> void:
	var city := flat_city()
	city.zone.put(20,20,Zones.RES_LOW)
	city.building.put(21,20,Buildings.TREES_1)
	city.building.put(22,20,Buildings.POWER_LINE_FIRST)
	city.building.put(23,20,Buildings.RAIL_FIRST)
	city.building.put(24,20,Buildings.RES_1X1_FIRST)
	await setup(city)
	var saved := SaveFormat.encode_city(city)
	check(not session.enter(city,Vector3(20.5,GROUND,20.5)),"dry land without roads cannot enter Explore")
	check(not session.is_active())
	check(session.pedestrian==null and session.traversal==null,"rejected entry releases all session geometry")
	check(view.aerial_controls_enabled and view.camera.current)
	check_eq(Input.mouse_mode,Input.MOUSE_MODE_VISIBLE)
	check_eq(SaveFormat.encode_city(city),saved)

func test_distant_isolated_road_is_found_on_each_entry_without_city_changes() -> void:
	var city := flat_city()
	city.building.put(110,109,30)
	await setup(city,[Rect2i(16,16,16,16),Rect2i(104,104,16,16)])
	var saved := SaveFormat.encode_city(city)
	for visit: int in 2:
		var entered := session.enter(city,Vector3(20.5,GROUND,20.5))
		check(entered,"full-city search finds a disconnected road beyond the neighborhood")
		if not entered: return
		check_spawn(Vector2i(110,109),GROUND+.04)
		session.leave()
	check_eq(SaveFormat.encode_city(city),saved)

func test_nearest_road_replaces_building_and_wrong_camera_height_origins() -> void:
	var city := flat_city()
	city.building.put(20,20,Buildings.RES_1X1_FIRST)
	city.building.put(22,20,30)
	city.building.put(28,20,30)
	await setup(city)
	Fixture.box(view.world,Vector3(20.5,GROUND+.6,20.5),Vector3(.9,1.2,.9),4)
	await physics_frame
	check(session.enter(city,Vector3(20.5,GROUND+.7,20.5)))
	if not session.is_active(): return
	check_spawn(Vector2i(22,20),GROUND+.04)

func test_obstructed_road_never_uses_roof_or_neighboring_dry_lot() -> void:
	var city := flat_city()
	city.building.put(20,20,30)
	city.building.put(25,20,30)
	await setup(city)
	Fixture.box(view.world,Vector3(20.5,GROUND+.3,20.5),Vector3(1,.6,1),4)
	await physics_frame
	check(session.enter(city,Vector3(20.5,GROUND+.6,20.5)))
	if not session.is_active(): return
	check_spawn(Vector2i(25,20),GROUND+.04)

func test_only_obstructed_road_rejects_entry_without_dry_ground_fallback() -> void:
	var city := flat_city()
	city.building.put(20,20,30)
	await setup(city)
	Fixture.box(view.world,Vector3(20.5,GROUND+.3,20.5),Vector3(1,.6,1),4)
	await physics_frame
	check(not session.enter(city,Vector3(20.5,GROUND+.6,20.5)),"covered pavement cannot fall back to its roof or neighboring empty tiles")
	check(not session.is_active() and session.pedestrian==null and session.traversal==null)
	check(view.aerial_controls_enabled and view.camera.current)

func test_tunnel_origin_moves_to_outdoor_approach() -> void:
	await setup(TunnelFixture.city())
	check(session.enter(view.city,Vector3(23.5,GROUND+.04,20.5)))
	if not session.is_active(): return
	check_spawn(Vector2i(19,20),GROUND+.04)

func test_tunnel_only_city_cannot_enter_on_tunnel_floor_or_dry_ground() -> void:
	var city := TunnelFixture.city()
	for x: int in [17,18,19,27,28,29]: city.building.put(x,20,0)
	# Retain the valid opposed mouths and underground bore, remove surface roads.
	city.building.put(19,20,65)
	city.building.put(27,20,63)
	await setup(city)
	check(not session.enter(city,Vector3(23.5,GROUND+.04,20.5)))
	check(not session.is_active() and session.pedestrian==null)

func test_bridge_road_is_outdoors_and_stays_above_water() -> void:
	await setup(Fixture.bridge_city())
	check(session.enter(view.city,Vector3(22.5,GROUND-.2,20.5)))
	if not session.is_active(): return
	check_spawn(Vector2i(22,20),GROUND+.12)

func test_road_shapes_crossings_and_highway_have_pavement_spawns() -> void:
	for code: int in [29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,67,68,69,70,73,74,75,76]:
		var city := flat_city()
		city.building.put(22,20,code)
		await setup(city)
		check(session.enter(city,Vector3(20.5,GROUND,20.5)),"road code %d admits supported outdoor entry" % code)
		if session.is_active():
			check_spawn(Vector2i(22,20),GROUND+(.38 if code in [73,74] else .04))
		await after_each()

func check_on_road(actor: CharacterBody3D, cell: Vector2i, height: float) -> void:
	var feet := actor.global_position
	check_eq(Vector2i(floori(feet.x),floori(feet.z)),cell,"Recover lands on the nearest road tile: "+actor.name)
	check_between(feet.y,height+.0019,height+.0021,"Recover rests on pavement, never terrain or a roof: "+actor.name)
	check(not session.traversal.inside_road_tunnel(feet),"Recover stays outside tunnel interiors")
	check(not session.traversal.touches_water(feet),"Recover stays above water")
	var collider: CollisionShape3D
	for child: Node in actor.get_children():
		if child is CollisionShape3D: collider = child
	check(collider != null and session.traversal.has_clearance(collider.global_transform,collider.shape,[actor.get_rid()]),"Recover clears physical obstacles: "+actor.name)

func two_road_city() -> City:
	var city := flat_city()
	city.building.put(22,20,30)
	city.building.put(28,20,30)
	return city

func test_recover_moves_off_road_walker_to_nearest_outdoor_road() -> void:
	await setup(two_road_city())
	check(session.enter(view.city,Vector3(22.5,GROUND,20.5)))
	if not session.is_active(): return
	session.set_physics_process(false)
	# Supported dry grass is a valid walking pose, but not a road.
	session.pedestrian.global_position = Vector3(27.5,GROUND+.002,24.5)
	session.suspend()
	check(session.recover(),"Recover succeeds from ordinary dry ground")
	check_on_road(session.pedestrian,Vector2i(28,20),GROUND+.04)
	check(session.is_suspended(),"Recover preserves suspension")

func test_recover_leaves_tunnel_interior_for_outdoor_approach() -> void:
	await setup(TunnelFixture.city())
	check(session.enter(view.city,Vector3(19.5,GROUND+.04,20.5)))
	if not session.is_active(): return
	session.set_physics_process(false)
	var inside := session.traversal.support_near(Vector3(23.5,GROUND+.06,20.5),.05,.2,[session.pedestrian.get_rid()])
	check(not inside.is_empty(),"tunnel bore has a walking floor")
	if inside.is_empty(): return
	session.pedestrian.global_position = inside.position+Vector3.UP*.002
	check(session.traversal.inside_road_tunnel(session.pedestrian.global_position),"fixture places the player inside the bore")
	session.suspend()
	check(session.recover(),"Recover succeeds from a tunnel interior")
	check_on_road(session.pedestrian,Vector2i(19,20),GROUND+.04)

func test_recover_keeps_driver_in_car_on_outdoor_road() -> void:
	await setup(two_road_city())
	check(session.enter(view.city,Vector3(22.5,GROUND,20.5)))
	if not session.is_active(): return
	session.set_physics_process(false)
	check(session.request_interaction(),"player enters the parked car")
	var car: CharacterBody3D = session.car
	check_eq(session.occupied,car)
	car.global_position = Vector3(27.5,GROUND+.002,24.5)
	session.suspend()
	check(session.recover(),"Recover succeeds while driving off road")
	check_eq(session.occupied,car,"a road vehicle that fits keeps its driver")
	check_on_road(car,Vector2i(28,20),GROUND+.04)

func test_recover_lands_airborne_helicopter_on_outdoor_road() -> void:
	await setup(two_road_city())
	check(session.enter(view.city,Vector3(22.5,GROUND,20.5)))
	if not session.is_active(): return
	session.set_physics_process(false)
	session.suspend()
	check(session.select_vehicle(&"helicopter"))
	var helicopter: CharacterBody3D = session.helicopter
	check_eq(session.occupied,helicopter)
	helicopter.global_position = Vector3(27.5,GROUND+1.0,24.5)
	session._helicopter_in_flight = true
	check(session.recover(),"Recover succeeds during flight")
	check_eq(session.occupied,helicopter)
	check(not session._helicopter_in_flight,"recovered aircraft is parked rather than flying")
	check_on_road(helicopter,Vector2i(28,20),GROUND+.04)

func test_recover_dismounts_when_only_the_player_fits_the_road() -> void:
	var city := flat_city()
	city.building.put(28,20,30)
	await setup(city)
	check(session.enter(view.city,Vector3(28.5,GROUND,20.5)))
	if not session.is_active(): return
	session.set_physics_process(false)
	check(session.request_interaction(),"player enters the parked car")
	var car: CharacterBody3D = session.car
	car.global_position = Vector3(25.5,GROUND+.002,23.5)
	# Leave only a narrow opening at the tile center: a capsule fits, a car does not.
	var top := GROUND+.04
	for rect: Rect2 in [Rect2(28,20,.45,1),Rect2(28.55,20,.45,1),Rect2(28.45,20,.1,.45),Rect2(28.45,20.55,.1,.45)]:
		Fixture.box(view.world,Vector3(rect.get_center().x,top+.16,rect.get_center().y),Vector3(rect.size.x,.3,rect.size.y),ExploreActorProfile.OBSTACLE)
	await physics_frame
	session.suspend()
	check(session.recover(),"Recover still reaches the road on foot")
	check_eq(session.occupied,session.pedestrian,"the player leaves a vehicle that cannot fit")
	check_eq(session.mode,ExploreActorProfile.Mode.WALK)
	check(session.pedestrian.visible and session.pedestrian.collision_layer==ExploreActorProfile.ACTOR)
	check_on_road(session.pedestrian,Vector2i(28,20),GROUND+.04)
	check(is_instance_valid(car) and car.global_position.distance_to(Vector3(25.5,GROUND+.002,23.5))<.01,"the supported parked car stays where it was left")

func test_recover_without_any_outdoor_road_returns_to_build() -> void:
	await setup(TunnelFixture.city())
	check(session.enter(view.city,Vector3(19.5,GROUND+.04,20.5)))
	if not session.is_active(): return
	session.set_physics_process(false)
	var returned: Array[bool] = []
	session.return_requested.connect(func() -> void: returned.append(true))
	for x: int in [17,18,19,27,28,29]:
		Fixture.box(view.world,Vector3(x+.5,GROUND+.3,20.5),Vector3(1,.5,1),ExploreActorProfile.OBSTACLE)
	session.pedestrian.global_position = Vector3(31.5,GROUND+.002,24.5)
	await physics_frame
	session.suspend()
	check(not session.recover(),"Recover never falls back to dry ground, roofs or tunnel floors")
	check_eq(returned.size(),1,"no outdoor road requests Return to Build")

func setup_host() -> void:
	root.size = Vector2i(1280,800)
	host = MAIN.instantiate()
	host.preferences_path = "user://test_road_spawn.cfg"
	root.add_child(host)
	host.begin_city(flat_city(),{},4242,CityStats.new())
	host.sim.set_speed(GameClock.Speed.SLOW)
	await physics_frame

func test_main_menu_blocks_roadless_entry_with_modal_and_restores_speed() -> void:
	await setup_host()
	host.select_tool(Tools.Kind.ROAD)
	var saved := SaveFormat.encode_city(host.sim.city)
	var center := host.city_view_3d.center
	var presentation := host.presentation.capture_state()
	host.menu_bar.press(&"explore")
	for frame: int in 12:
		await process_frame
		if not host.loading_screen.visible: break
	check(host.notice_dialog.is_open(),"roadless View > Explore displays a modal dialog")
	check(host.notice_dialog.body_label.text.to_lower().contains("road"),"dialog explains the road requirement")
	check(host.is_input_blocked(),"dialog blocks Build and Explore input")
	check_eq(host.sim.speed,GameClock.Speed.PAUSED)
	check(not host.exploration.is_active() and host.exploration.pedestrian==null)
	check(host.toolbar.visible and host.city_view_3d.camera.current)
	check_eq(host.tool,Tools.Kind.ROAD)
	check_eq(host.city_view_3d.center,center)
	check_eq(host.presentation.capture_state(),presentation)
	check_eq(SaveFormat.encode_city(host.sim.city),saved)
	check(not host.enter_explore(),"repeated entry stays blocked while the dialog is open")
	check_eq(host.notices.pending(),0,"repeated entry never queues duplicate notices")
	if host.notice_dialog.is_open(): host.notice_dialog.dismiss()
	check(not host.is_input_blocked())
	check_eq(host.sim.speed,GameClock.Speed.SLOW,"acknowledging returns to the prior speed")
	check(not host.exploration.is_active(),"acknowledging never enters Explore automatically")
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.handle_drag(Vector2i(22,20),Vector2i(22,20))
	await physics_frame
	check(host.enter_explore(),"building a road enables a later explicit entry")
	if host.exploration.is_active():
		host.exploration.set_physics_process(false)
		var feet: Vector3 = host.exploration.pedestrian.global_position
		check_eq(Vector2i(floori(feet.x),floori(feet.z)),Vector2i(22,20))

func test_main_rejects_existing_road_without_safe_physical_support() -> void:
	await setup_host()
	host.sim.set_speed(GameClock.Speed.PAUSED)
	host.select_tool(Tools.Kind.ROAD)
	host.handle_drag(Vector2i(22,20),Vector2i(22,20))
	host.city_view_3d._traversal_chunks.clear()
	check(not host.enter_explore())
	check(host.notice_dialog.is_open(),"unsafe entry also explains failure in a blocking dialog")
	check(not host.exploration.is_active())
	check(host.city_view_3d.aerial_controls_enabled and host.toolbar.visible)
