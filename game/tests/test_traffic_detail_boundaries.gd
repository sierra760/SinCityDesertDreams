# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
var host: Node3D
func after_each() -> void:
	if is_instance_valid(host): host.free()
	await process_frame
func fixture() -> Dictionary:
	host=Node3D.new()
	root.add_child(host)
	var traffic:=CityTraffic3D.new()
	host.add_child(traffic)
	var city:=flat_city()
	for x in range(4,124): city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	traffic.bind_city(city)
	traffic.actors.clear()
	traffic.set_detail_enabled(true)
	var camera:=Camera3D.new()
	host.add_child(camera)
	camera.current=true
	return {"traffic":traffic,"camera":camera}
func actor() -> Dictionary:
	return {"id":1,"type":&"road","kind":&"car","domain":&"road","cell":Vector2i(20,20),"previous":Vector2i(19,20),"next":Vector2i(21,20),"lane":0,"t":.5,"variant":0,"turns":0,"side":1.0,"speed":.5,"length":.3,"stopped":false}
func same_selection(traffic: CityTraffic3D,camera: Camera3D) -> void:
	traffic.detail_manager.clear()
	var exhaustive:=traffic.visual_states()
	var wanted: Array=traffic.detail_manager.update(exhaustive,camera).keys()
	traffic.detail_manager.clear()
	traffic._render(camera)
	check_eq(traffic.detail_manager.debug_state().ids,wanted,"filtered preparation must agree with exhaustive authoritative pose selection")
func test_ground_turn_side_endpoints_and_cameras_match_authoritative_selection() -> void:
	var f:=fixture()
	var traffic: CityTraffic3D=f.traffic
	var camera: Camera3D=f.camera
	for kind: StringName in [&"car",&"pedestrian"]:
		for next: Vector2i in [Vector2i(21,20),Vector2i(20,19),Vector2i(19,20)]:
			for side: float in [-3.0,-1.0,0.0,1.0,3.0]:
				for t: float in [0.0,.25,.5,.75,1.0]:
					var a:=actor()
					a.kind=kind
					a.type=&"pedestrian" if kind==&"pedestrian" else &"road"
					a.next=next
					a.side=side
					a.t=t
					traffic.actors.assign([a])
					var point:=traffic.actor_pose(a).origin
					for offset: Vector3 in [Vector3(0,.1,.8),Vector3(.7,.1,0),Vector3(0,.1,20)]:
						camera.position=point+offset
						camera.look_at(point)
						same_selection(traffic,camera)
func test_highway_extrapolated_and_nonfinite_records_bypass_cheap_rejection() -> void:
	var f:=fixture()
	var traffic: CityTraffic3D=f.traffic
	var camera: Camera3D=f.camera
	for t: float in [-.5,1.5]:
		var a:=actor()
		a.t=t
		traffic.actors.assign([a])
		var point:=traffic.actor_pose(a).origin
		camera.position=point+Vector3(0,.1,.8)
		camera.look_at(point)
		same_selection(traffic,camera)
		check(traffic._detail_may_be_near(a,Vector3(1000,1000,1000)),"extrapolated pose never gets tile-bound rejection")
	var a:=actor()
	a.type=&"highway"
	a.domain=&"highway"
	traffic.actors.assign([a])
	var point:=traffic.actor_pose(a).origin
	camera.position=point+Vector3(0,.1,.8)
	camera.look_at(point)
	same_selection(traffic,camera)
	check(traffic._detail_may_be_near(a,Vector3(1000,1000,1000)),"authored highway curves retain exact evaluation")
	for field: String in ["side","t"]:
		for value: float in [NAN,INF,-INF]:
			a=actor()
			a[field]=value
			check(traffic._detail_may_be_near(a,Vector3(1000,1000,1000)),"nonfinite public record bypasses geometric assumptions")
func test_demotion_clock_reentry_and_zero_delta_use_current_absolute_state() -> void:
	var f:=fixture()
	var traffic: CityTraffic3D=f.traffic
	var camera: Camera3D=f.camera
	var a:=actor()
	traffic.actors.assign([a])
	var point:=traffic.actor_pose(a).origin
	camera.position=point+Vector3(0,.1,.8)
	camera.look_at(point)
	traffic._render(camera)
	check_eq(traffic.detail_manager.debug_state().detailed_count,1)
	traffic._step(.1)
	camera.position+=Vector3(0,0,20)
	traffic._render(camera)
	check_eq(traffic.detail_manager.debug_state().detailed_count,0,"moving camera away releases selected detail")
	for i in 4: traffic._step(.1)
	var current: Dictionary=traffic.visual_states()[0]
	check(absf(float(current.visual_time)-.5)<.000001,"offscreen owner clock continues after demotion")
	check(float(current.distance)>.15,"offscreen accepted movement distance continues")
	point=traffic.actor_pose(a).origin
	camera.position=point+Vector3(0,.1,.8)
	camera.look_at(point)
	traffic._render(camera)
	check_eq(traffic.detail_manager.debug_state().detailed_count,1)
	var actual: ExploreActorVisual=traffic.detail_manager._selected["ambient:1"]
	var expected:=CityTrafficCatalog.make_nearby_visual(&"car",0)
	host.add_child(expected)
	expected.sample_owned_state(current)
	check_eq(actual.debug_state(),expected.debug_state(),"re-entry samples current accumulated absolute state rather than stale selected state")
	var states:=traffic.visual_states().duplicate(true)
	var visual:=actual.debug_state()
	# Synthetic actor is test-owned: avoid an unrelated demand reconciliation.
	traffic._dirty=false
	traffic._refresh_left=1.0
	traffic.advance(0,true,[],camera)
	check_eq(traffic.visual_states(),states,"zero delta retains owner poses/clocks")
	check_eq(actual.debug_state(),visual,"zero delta never advances reselected visual")
