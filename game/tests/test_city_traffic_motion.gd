# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func _city(domain: StringName = &"road") -> City:
	var city := flat_city()
	for x: int in range(19,24):
		if domain == &"water": city.terrain.put(x,20,Terrain.SURFACE)
		else: city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.RAIL if domain == &"rail" else NetworkShapes.Family.ROAD,10))
	city.building.put(20,21,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5))
	if domain == &"road": city.building.put(20,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,15))
	return city

func _actor(domain: StringName = &"road") -> Dictionary:
	return {"id":1,"kind":&"sailboat" if domain == &"water" else &"train" if domain == &"rail" else &"car", "type":domain,"domain":domain,
		"cell":Vector2i(20,20),"previous":Vector2i(19,20),"next":Vector2i(20,21),"lane":0,"side":1.0,"t":.4,"speed":1.0,"turns":0,"stopped":false,"variant":0}

func _traffic(a: Dictionary, city: City = null) -> CityTraffic3D:
	var traffic := CityTraffic3D.new()
	traffic.bind_city(_city(a.domain) if city == null else city)
	traffic.actors.assign([a])
	traffic._dirty = false
	traffic._refresh_left = 1000
	return traffic

# Inspect the interpolation endpoints consumed by _render. Dummy headless
# MultiMesh getters do not return uploaded transforms; native coverage is separate.
func _drawn(traffic: CityTraffic3D, a: Dictionary) -> Transform3D:
	return a.get("_render_pose",a._render_from.interpolate_with(a._render_target,clampf(traffic._accumulator/traffic._step_interval,0,1)))

func test_stopped_turn_settles_without_replaying_motion() -> void:
	var a := _actor()
	var traffic := _traffic(a)
	traffic.advance(0,false)
	traffic.advance(1.0/30,false)
	a.speed = 0.0
	for frame: int in 12:
		traffic.advance(1.0/60,false)
		if frame < 2: continue
		var at := _drawn(traffic,a).origin
		check(Vector2(at.x,at.z).distance_to(Vector2(20.283111,20.667555))<.0001,"stopped car stays at the final turn position")
	traffic.free()

func test_multiple_ticks_use_the_last_tick_for_interpolation() -> void:
	var a := _actor()
	a.cell=Vector2i(21,20);a.previous=Vector2i(20,20);a.next=Vector2i(22,20);a.t=.2
	var traffic := _traffic(a)
	traffic.advance(0,false)
	traffic.advance(.1,false)
	check(absf(_drawn(traffic,a).origin.x-21.2666667)<.0001,"three-tick frame interpolates from the penultimate pose, not three ticks ago")
	traffic.free()

func test_pause_and_cadence_change_preserve_displayed_pose() -> void:
	var a := _actor()
	var traffic := _traffic(a)
	traffic.advance(0,false)
	traffic.advance(.05,false)
	var before := _drawn(traffic,a)
	traffic.advance(.2,true)
	check_eq(_drawn(traffic,a),before,"pause preserves the displayed position and heading")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=80
	camera.position=Vector3(20,30,30);camera.look_at(Vector3(20,2.5,20))
	traffic.advance(0,true,[],camera)
	check(_drawn(traffic,a).origin.distance_to(before.origin)<.0001,"changing cadence while paused cannot rewind the car")
	camera.free();traffic.free()

func test_road_and_boat_dead_ends_turn_continuously_at_overview_cadence() -> void:
	for domain: StringName in [&"road",&"water"]:
		var a := _actor(domain)
		a.cell=Vector2i(23,20);a.previous=Vector2i(22,20);a.next=a.previous;a.t=0.0
		var traffic := _traffic(a)
		var previous := traffic.actor_pose(a)
		var completed := false
		for step: int in 180:
			traffic._elapsed += .1
			traffic._step(.1)
			var pose := traffic.actor_pose(a)
			var angle := rad_to_deg(previous.basis.get_rotation_quaternion().angle_to(pose.basis.get_rotation_quaternion()))
			check(angle<20,"no abrupt dead-end spin in "+str(domain))
			check(pose.origin.distance_to(previous.origin)<.12,"bounded dead-end movement")
			check(pose.origin.is_finite())
			previous=pose
			if a.cell!=Vector2i(23,20): completed=true;break
		check(completed,"dead-end actor exits the turn")
		traffic.free()

func test_dead_end_entrance_and_exit_headings_match_the_street() -> void:
	for domain: StringName in [&"road",&"water"]:
		var a := _actor(domain)
		a.cell=Vector2i(23,20);a.previous=Vector2i(22,20);a.next=a.previous
		var traffic := _traffic(a)
		a.t=0.0
		check((-traffic.actor_pose(a).basis.z).dot(Vector3.RIGHT)>.999,"turn enters along the incoming street")
		a.t=1.0
		check((-traffic.actor_pose(a).basis.z).dot(Vector3.LEFT)>.999,"turn exits along the outgoing street")
		traffic.free()

func test_train_reverses_travel_without_spinning_its_body() -> void:
	var a := _actor(&"rail")
	a.cell=Vector2i(23,20);a.previous=Vector2i(22,20);a.next=a.previous;a.t=0.0
	var traffic := _traffic(a)
	var previous := traffic.actor_pose(a)
	var exited := false
	for step: int in 240:
		traffic._step(.1)
		var pose := traffic.actor_pose(a)
		check((-pose.basis.z).dot(Vector3.RIGHT)>.999,"train body retains heading while backing out")
		check(pose.origin.distance_to(previous.origin)<.12,"bounded terminal travel")
		previous=pose
		if a.cell==Vector2i(21,20): exited=true;break
	check(exited,"train backs out onto the connected rail")
	traffic.free()

func test_no_legal_continuation_holds_the_existing_edge() -> void:
	var a := _actor(&"rail")
	a.next=Vector2i(21,20);a.t=.99
	var traffic := _traffic(a)
	traffic._reserved_rail={Vector2i(20,20):true,Vector2i(22,20):true}
	traffic._step(.1)
	check_eq(a.cell,Vector2i(20,20),"train must not enter an edge with no permitted continuation")
	check_ne(a.cell,a.next,"waiting cannot create a zero-length self edge")
	check(a.stopped)
	traffic.free()

func test_blocked_highway_merge_never_moves_backwards() -> void:
	var city := flat_city()
	for y: int in range(10,40):
		for x: int in [20,21]: city.building.put(x,y,NetworkShapes.HIGHWAY_NS)
	city.building.put(19,20,Buildings.ONRAMP_FIRST+2)
	city.flags.put(19,20,RotationMapper.AXIS_FLAG)
	city.building.put(19,19,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5))
	var a := _actor()
	a.cell=Vector2i(19,20);a.previous=Vector2i(19,19);a.next=Vector2i(20,20);a.t=.99
	var b := _actor(&"highway")
	b.id=2;b.cell=Vector2i(20,20);b.previous=Vector2i(20,19);b.next=Vector2i(20,21);b.lane=1;b.t=.1;b.speed=0.0
	var traffic := _traffic(a,city)
	traffic.actors.append(b)
	for i: int in 20:
		var before: float=a.t
		traffic._step(.1)
		check(float(a.t)>=before,"a blocked merge must not rewind on every attempt")
		check_eq(a.cell,Vector2i(19,20))
	traffic.free()

func test_live_cadence_changes_do_not_lurch_or_rewind() -> void:
	for sizes: Array in [[80.0,4.0],[4.0,80.0]]:
		var a := _actor()
		a.cell=Vector2i(21,20);a.previous=Vector2i(20,20);a.next=Vector2i(22,20);a.t=.2
		var traffic := _traffic(a)
		var camera := Camera3D.new();root.add_child(camera)
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=sizes[0]
		camera.position=Vector3(21,30,30);camera.look_at(Vector3(21,2.5,20))
		traffic.advance(0,false,[],camera)
		for i: int in 21: traffic.advance(1.0/60,false,[],camera)
		var previous := _drawn(traffic,a)
		camera.size=sizes[1];traffic.advance(0,false,[],camera)
		check(_drawn(traffic,a).origin.distance_to(previous.origin)<.0001,"instantaneous live cadence change preserves position")
		for i: int in 45:
			traffic.advance(1.0/60,false,[],camera)
			var pose := _drawn(traffic,a)
			check(pose.origin.x>=previous.origin.x-.0001,"cadence handoff cannot rewind a forward-moving car")
			check(pose.origin.distance_to(previous.origin)<.03,"cadence handoff cannot jump more than 1.8 normal frames")
			previous=pose
		camera.free();traffic.free()

func test_cadence_handoff_allows_a_train_backing_out_of_its_terminal() -> void:
	for sizes: Array in [[80.0,4.0],[4.0,80.0]]:
		var a := _actor(&"rail")
		a.cell=Vector2i(23,20);a.previous=Vector2i(22,20);a.next=a.previous;a.t=.65
		var traffic := _traffic(a)
		var camera := Camera3D.new();root.add_child(camera)
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=sizes[0]
		camera.position=Vector3(23,30,30);camera.look_at(Vector3(23,2.5,20))
		traffic.advance(0,false,[],camera)
		for i: int in 21:traffic.advance(1.0/60,false,[],camera)
		var before:=_drawn(traffic,a)
		camera.size=sizes[1];traffic.advance(0,false,[],camera)
		for i: int in 20:traffic.advance(1.0/60,false,[],camera)
		check(_drawn(traffic,a).origin.x<before.origin.x-.01,"a reversing train must not freeze during the cadence handoff")
		check((-_drawn(traffic,a).basis.z).dot(Vector3.RIGHT)>.999,"backing train body keeps its heading")
		camera.free();traffic.free()

func test_unrendered_ticks_do_not_replay_stale_visible_history() -> void:
	var a:=_actor()
	a.cell=Vector2i(21,20);a.previous=Vector2i(20,20);a.next=Vector2i(22,20);a.t=.2
	var traffic:=_traffic(a)
	traffic.advance(0,false)
	for i: int in 10:traffic._step(1.0/30)
	traffic.advance(0,false)
	check(absf(_drawn(traffic,a).origin.x-21.5)<.0001,"an actor returning to view uses its most recent tick, not an old visible pose")
	traffic.free()

func test_released_vehicle_starts_at_its_new_route_without_a_stale_trail() -> void:
	var a:=_actor()
	a.cell=Vector2i(21,20);a.previous=Vector2i(20,20);a.next=Vector2i(22,20);a.t=.2
	var traffic:=_traffic(a)
	traffic.advance(0,false);traffic.advance(.05,false)
	var claim:=traffic.claim_nearby_vehicle(traffic.actor_pose(a).origin,.1)
	traffic.release_vehicle(claim,Vector3(22.5,2.5,20.5))
	traffic.advance(0,false)
	check(absf(_drawn(traffic,a).origin.x-22.5)<.0001,"release resets interpolation to the new location")
	traffic.free()

func test_lane_pose_cache_cannot_retain_the_neighboring_lane() -> void:
	var city:=flat_city()
	for y: int in range(10,40):
		for x: int in [20,21]:city.building.put(x,y,NetworkShapes.HIGHWAY_NS)
	var a:=_actor(&"highway")
	a.cell=Vector2i(20,20);a.previous=Vector2i(20,19);a.next=Vector2i(20,21);a.t=.5;a.lane=0
	var traffic:=_traffic(a,city)
	check(absf(traffic.actor_pose(a).origin.x-20.72)<.0001,"inner lane uses its own center")
	a.lane=1
	check(absf(traffic.actor_pose(a).origin.x-20.28)<.0001,"cache responds immediately to a lane change")
	traffic.free()

func test_active_cadence_history_is_discarded_after_a_geometry_edit() -> void:
	var a:=_actor()
	a.cell=Vector2i(21,20);a.previous=Vector2i(20,20);a.next=Vector2i(22,20);a.t=.2
	var city:=_city();var traffic:=_traffic(a,city)
	var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=80
	camera.position=Vector3(21,30,30);camera.look_at(Vector3(21,2.5,20))
	traffic.advance(0,false,[],camera)
	for i: int in 21:traffic.advance(1.0/60,false,[],camera)
	camera.size=4;traffic.advance(.05,false,[],camera)
	var before:=_drawn(traffic,a)
	for y: int in City.HEIGHT:
		for x: int in City.WIDTH:city.set_heights(x,y,5,0)
	traffic.graph.refresh()
	traffic.advance(1.0/30,false,[],camera)
	check(_drawn(traffic,a).origin.y-before.origin.y>.55,"a rebuilt route must not ease through the old ground height")
	camera.free();traffic.free()

func test_active_cadence_history_is_discarded_after_culling() -> void:
	var a:=_actor()
	a.cell=Vector2i(21,20);a.previous=Vector2i(20,20);a.next=Vector2i(22,20);a.t=.2
	var traffic:=_traffic(a)
	var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=80
	camera.position=Vector3(21,30,30);camera.look_at(Vector3(21,2.5,20))
	traffic.advance(0,false,[],camera)
	for i: int in 21:traffic.advance(1.0/60,false,[],camera)
	camera.size=4;traffic.advance(.05,false,[],camera)
	camera.position=Vector3(500,30,510);camera.look_at(Vector3(500,2.5,500))
	for i: int in 60:traffic.advance(1.0/60,false,[],camera)
	camera.position=Vector3(22,30,30);camera.look_at(Vector3(22,2.5,20))
	traffic.advance(0,false,[],camera)
	check(absf(_drawn(traffic,a).origin.x-22.5333333)<.0001,"a returning actor uses the latest preceding tick, not pre-culling cadence history")
	camera.free();traffic.free()

# An external graph.refresh() (Explore route lookup) may drop the cell under an
# actor before the next reconcile; its tick still reads neutral demand.
func test_actor_on_a_removed_cell_reads_neutral_demand() -> void:
	var a := _actor()
	var traffic := _traffic(a)
	traffic.graph.refresh()
	traffic.graph.city.building.put(20,20,0)
	traffic.graph.refresh()
	check(not traffic.graph.has_cell(Vector2i(20,20),&"road"),"the actor's cell left the graph")
	var neutral := traffic.graph.demand(Vector2i(20,20))
	check_eq(float(neutral.congestion),0.0)
	check_eq(int(neutral.activity),0)
	var before := float(a.t)
	traffic._step(1.0/30)
	check_gt(float(a.t),before,"neutral congestion leaves the actor's own speed")
	neutral.cars = 9.0
	check_eq(float(traffic.graph.demand(Vector2i(20,20)).cars),0.0,"each missing-cell default is independent")
	traffic.free()
