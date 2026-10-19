# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"

var host: Node3D

func after_each() -> void:
	if is_instance_valid(host): host.free()
	await process_frame

func fixture() -> Camera3D:
	host=Node3D.new()
	root.add_child(host)
	var camera:=Camera3D.new()
	host.add_child(camera)
	return camera

func state(id: String, kind: StringName, metres: float) -> Dictionary:
	return {"id":id,"kind":String(kind),"variant":0,"position":Vector3(0,0,-metres/16.0),"yaw":0.0,"speed":0.0,"steering":0.0,"airborne":CityTrafficCatalog.domain(kind)==&"air","phase":0.0}

func test_every_vehicle_stays_detailed_across_street_and_distant_blocks() -> void:
	var camera:=fixture()
	var manager:=ExploreActorDetailManager.new()
	manager.bind(host)
	for kind: StringName in CityTrafficCatalog.vehicle_kinds():
		for metres: float in [40.0,120.0,190.0]:
			var selected:=manager.update([state("vehicle",kind,metres)],camera)
			check(selected.has("vehicle"),String(kind)+" keeps authored detail at "+str(metres)+" metres")
			if selected.has("vehicle"):
				check(selected.vehicle.find_child("DetailedModel",true,false)!=null,"authored vehicle scene is selected")
	manager.clear()

func test_vehicle_hysteresis_only_swaps_at_long_distance() -> void:
	var camera:=fixture()
	var manager:=ExploreActorDetailManager.new()
	manager.bind(host)
	var selected:=manager.update([state("car",&"car",180.0)],camera)
	check(selected.has("car"),"distant car initially receives detail")
	if selected.has("car"):
		var visual: Node3D=selected.car
		for metres: float in [200.0,240.0,200.0,255.0]:
			check_eq(manager.update([state("car",&"car",metres)],camera).get("car"),visual,"wide hysteresis retains the same model")
	check(manager.update([state("car",&"car",257.0)],camera).is_empty(),"very distant car returns to batched model")
	check(manager.update([state("car",&"car",220.0)],camera).is_empty(),"approaching car stays batched inside hysteresis band")
	check(manager.update([state("car",&"car",180.0)],camera).has("car"),"detail returns before normal viewing distances")
	manager.clear()

func test_crowds_and_nearer_vehicles_cannot_displace_visible_vehicle_detail() -> void:
	var camera:=fixture()
	var manager:=ExploreActorDetailManager.new()
	manager.bind(host)
	var states: Array[Dictionary]=[]
	for i in 40: states.append(state("pedestrian:%03d"%i,&"pedestrian",12.0))
	for i in 48: states.append(state("car:%03d"%i,&"car",40.0+float(i)))
	var selected:=manager.update(states,camera)
	check_eq(selected.size(),64,"all 48 cars and only 16 pedestrian rigs")
	var original:=selected.duplicate()
	states.reverse()
	for record in states:
		if record.kind=="car": record.position.z-=.01
	selected=manager.update(states,camera)
	for i in 48:
		var id: String="car:%03d"%i
		check(selected.has(id),"car remains detailed in a busy street")
		if selected.has(id): check_eq(selected[id],original.get(id),"actor keeps its own model as proximity ordering changes")
	manager.update([],camera)
	check(manager.debug_state().allocated<=24,"inactive cache shrinks after a crowd leaves")
	manager.clear()

func test_render_promotes_distant_ambient_and_port_vehicles_without_duplicate_batches() -> void:
	var camera:=fixture()
	var traffic:=CityTraffic3D.new()
	host.add_child(traffic)
	var city:=flat_city()
	city.building.put(20,20,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	traffic.bind_city(city)
	traffic.actors.assign([{"id":1,"type":&"road","kind":&"car","domain":&"road","cell":Vector2i(20,20),"previous":Vector2i(19,20),"next":Vector2i(21,20),"lane":0,"t":.5,"variant":0,"turns":0,"side":1.0,"speed":0.0,"length":.3,"stopped":true}])
	var point:=traffic.actor_pose(traffic.actors[0]).origin
	var flight_basis:=Basis.from_euler(Vector3(.1,.2,.3))
	traffic._external.assign([{"presentation_id":-1,"kind":&"plane","presentation_position":point+Vector3(0,1,0),"presentation_yaw":.2,"presentation_basis":flight_basis}])
	traffic.set_detail_enabled(true)
	camera.position=point+Vector3(0,1,8)
	camera.look_at(point)
	traffic._render(camera)
	var selected: Dictionary=traffic.detail_manager._selected
	check(selected.has("ambient:1"),"broad phase admits distant street vehicles")
	check(selected.has("external:-1"),"port aircraft use the same vehicle detail policy")
	if selected.has("external:-1"):
		check(selected["external:-1"].basis.is_equal_approx(flight_basis),"detail retains aircraft bank and pitch")
	# The headless dummy renderer does not retain MultiMesh transform buffers.
	if DisplayServer.get_name()!="headless":
		for batch: MultiMeshInstance3D in traffic._batches.values():
			for i in batch.multimesh.visible_instance_count:
				check_eq(batch.multimesh.get_instance_transform(i).basis, Basis.IDENTITY.scaled(Vector3.ZERO),"promoted actor has no duplicate batched body")
	var ids: Array=selected.keys()
	traffic._render(camera)
	check_eq(traffic.detail_manager.debug_state().ids,ids,"repeated paused rendering keeps the same vehicles")
	traffic._claims[-1]=true
	traffic._render(camera)
	check(not traffic.detail_manager._selected.has("external:-1"),"boarding an external vehicle removes its ambient detailed body")
	check(traffic.detail_manager._selected.has("ambient:1"),"boarding does not displace another detailed vehicle")
	traffic._claims.clear()
	traffic._render(camera)
	check(traffic.detail_manager._selected.has("external:-1"),"unclaimed external vehicle regains detail")
	traffic._external.clear()
	traffic._render(camera)
	check(not traffic.detail_manager._selected.has("external:-1"),"removed port record releases its detailed body")
	traffic.set_detail_enabled(false)
	traffic._render(camera)
	check(traffic.detail_manager==null,"Build mode releases detail")
