# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
class CountingTraffic:
	extends CityTraffic3D
	var pose_calls := 0
	func actor_pose(actor: Dictionary) -> Transform3D:
		pose_calls += 1
		return super.actor_pose(actor)
var host: Node3D
func after_each() -> void:
	if is_instance_valid(host): host.free()
	await process_frame
func fixture() -> Dictionary:
	host=Node3D.new()
	root.add_child(host)
	var traffic:=CountingTraffic.new()
	host.add_child(traffic)
	var city:=flat_city()
	for x in range(4,124):
		city.building.put(x,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
		city.building.put(x,80,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	traffic.bind_city(city)
	traffic.actors.clear()
	for i in 81:
		var cell:=Vector2i(20,20) if i==0 else Vector2i(40+i,80)
		traffic.actors.append({"id":i+1,"type":&"road","kind":&"car","domain":&"road","cell":cell,"previous":cell-Vector2i(1,0),"next":cell+Vector2i(1,0),"lane":0,"t":.5,"variant":0,"turns":0,"side":1.0,"speed":0.0,"length":.3,"stopped":true})
	traffic.set_detail_enabled(true)
	var camera:=Camera3D.new()
	host.add_child(camera)
	camera.current=true
	var near: Transform3D=traffic.actor_pose(traffic.actors[0])
	camera.position=near.origin+Vector3(0,.3,.7)
	camera.look_at(near.origin)
	return {"traffic":traffic,"camera":camera}
func test_render_preparation_keeps_exact_selection_without_sampling_far_population() -> void:
	var f:=fixture()
	var traffic: CountingTraffic=f.traffic
	var camera: Camera3D=f.camera
	var full:=traffic.visual_states()
	var expected: Dictionary=traffic.detail_manager.update(full,camera)
	var ids: Array=expected.keys()
	check_eq(ids,["ambient:1"],"fixture has one nearby detail actor")
	traffic.detail_manager.clear()
	traffic.pose_calls=0
	traffic._render(camera)
	check_eq(traffic.detail_manager.debug_state().ids,ids,"same exact detail selection as exhaustive public state query")
	check(traffic.pose_calls<10,"offscreen population must not force full pose preparation before rendering")
	check_eq(traffic.visual_states().size(),81,"public query stays exhaustive")
func test_owner_sampling_is_selected_only_but_far_clocks_and_fresh_queries_survive() -> void:
	var f:=fixture()
	var traffic: CountingTraffic=f.traffic
	var camera: Camera3D=f.camera
	traffic._render(camera)
	var updates: int=traffic.detail_manager.debug_state().owner_updates
	traffic.pose_calls=0
	traffic._step(.1)
	check(traffic.pose_calls<=2,"owner animation preparation samples only selected detail actors")
	check_eq(traffic.detail_manager.debug_state().owner_updates,updates+1,"selected animation still advances exactly once")
	for actor: Dictionary in traffic.actors:
		check(absf(float(traffic._detail_clocks[actor.id].time)-.1)<.000001,"unselected clocks advance with the same owner")
	var far: Dictionary=traffic.actors[80]
	var before: Transform3D=traffic.actor_pose(far)
	far.t=.75
	var after: Transform3D=traffic.actor_pose(far)
	check(before.origin.distance_to(after.origin)>.1,"fresh actor query observes a raw offscreen record change")
	var states:=traffic.visual_states()
	check_eq(states.size(),81,"public query preserves every actor")
	check_eq(states[80].position,after.origin,"public query uses fresh offscreen pose")
	check(absf(float(states[80].visual_time)-.1)<.000001,"public query retains unselected clock history")
