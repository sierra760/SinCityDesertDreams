# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Connected, catalog-sized driving: no substitute landing pads or pose recovery.
extends "res://tests/exploration/async_test_case.gd"

const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
const GROUND := 4*CityGeometry3D.HEIGHT
const SmoothFixture := preload("res://tests/test_highway_smoothness.gd")

class Driver extends Node:
	signal completed
	var car: ExploreCar
	var route: Array[Vector3] = []
	var route_index := 0
	var ticks := 0
	var throttle := .3
	var max_ticks := 540
	var positions: Array[Vector3] = []
	var maximum_pitch_step := 0.0
	var previous_up := Vector3.UP
	func _physics_process(delta: float) -> void:
		var feet := car.feet_position()
		while route_index<route.size()-1 and Vector2(feet.x-route[route_index].x,feet.z-route[route_index].z).length()<.09:
			route_index += 1
		var offset := route[route_index]-feet
		var error := wrapf(atan2(-offset.x,-offset.z)-car.rotation.y,-PI,PI)
		var frame := ExploreInputFrame.idle()
		frame.move = Vector2(clampf(-error*3,-1,1),-throttle)
		if route_index==route.size()-1 and Vector2(offset.x,offset.z).length()<.065:
			frame.move = Vector2.ZERO
			frame.brake = true
		car.step(frame,0,delta)
		positions.append(car.feet_position())
		var up := car.collision_pose().basis.y.normalized()
		maximum_pitch_step = maxf(maximum_pitch_step,rad_to_deg(previous_up.angle_to(up)))
		previous_up = up
		ticks += 1
		if ticks>=max_ticks or (frame.brake and absf(car.speed())<.001):
			set_physics_process(false)
			completed.emit()

func test_catalog_car_climbs_and_descends_all_connected_ramp_orientations() -> void:
	var pairs := [[Vector2.RIGHT,Vector2.UP],[Vector2.LEFT,Vector2.UP],[Vector2.LEFT,Vector2.DOWN],[Vector2.RIGHT,Vector2.DOWN]]
	for axis: bool in [false,true]:
		for index: int in 4:
			for descending: bool in [false,true]:
				var road: Vector2 = pairs[index][0]
				var high: Vector2 = pairs[index][1]
				if axis:
					road = Vector2(road.y,road.x)
					high = Vector2(high.y,high.x)
				var city := flat_city()
				var cell := Vector2i(22,22)
				city.building.putv(cell,93+index)
				city.flags.putv(cell,2 if axis else 0)
				city.building.putv(cell+Vector2i(road),NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10 if road.x!=0 else 5))
				city.building.putv(cell+Vector2i(high),NetworkShapes.HIGHWAY_NS if high.x!=0 else NetworkShapes.HIGHWAY_EW)
				var before := SaveFormat.encode_city(city)
				var graph := CityTrafficGraph.new()
				graph.bind_city(city)
				var center := Vector2(22.5,22.5)
				var pivot := center+(road+high)*.5
				var route: Array[Vector3] = [Vector3(center.x+road.x*.85,GROUND+.04,center.y+road.y*.85)]
				for step: int in 17:
					var p := pivot+(-high).rotated((-high).angle_to(-road)*step/16.0)*.5
					route.append(Vector3(p.x,GROUND+.04+.34*step/16.0,p.y))
				route.append(Vector3(center.x+high.x*.85,GROUND+.38,center.y+high.y*.85))
				if descending: route.reverse()
				var fixture := Fixture.attach(self,city)
				var car := ExploreCar.new()
				fixture.add_child(car)
				check(car.configure_kind(&"car"),"real Desert Cruiser collision and visual")
				car.bind(fixture.get_node("traversal"))
				car.route_graph = graph
				car.global_position = route[0]
				var direction := route[1]-route[0]
				car.rotation.y = atan2(-direction.x,-direction.z)
				var reports: Array[String] = []
				car.recovery_requested.connect(func(reason: String) -> void: reports.append(reason))
				await physics_frame
				var driver := Driver.new()
				driver.car = car
				driver.route = route
				fixture.add_child(driver)
				await driver.completed
				await process_frame
				print("CONNECTED_RAMP index=%d axis=%s descending=%s waypoint=%d feet=%s reports=%s ticks=%d" % [index,axis,descending,driver.route_index,car.position,reports,driver.ticks])
				check_eq(driver.route_index,route.size()-1,"reaches connected destination cell")
				check(car.position.distance_to(route[-1])<.12,"finishes on the actual road/highway deck")
				check(reports.is_empty(),"climb/descent needs no recovery")
				check(car.has_support(),"destination retains physical support")
				check_lt(driver.maximum_pitch_step,4.0,"ramp chassis pitch changes gradually")
				var lowest := INF
				var highest := -INF
				for feet: Vector3 in driver.positions:
					lowest = minf(lowest,feet.y)
					highest = maxf(highest,feet.y)
				check(highest-lowest>.30,"traverses the entire elevation change")
				check_eq(SaveFormat.encode_city(city),before,"driving preserves city bytes")
				fixture.free()
				await physics_frame

func test_tall_road_vehicles_clear_both_lower_underpass_axes() -> void:
	for code: int in [75,76]:
		for kind: StringName in [&"bus",&"truck",&"fire_engine"]:
			var city := flat_city()
			city.building.put(22,22,code)
			var fixture := Fixture.attach(self,city)
			var car := ExploreCar.new()
			fixture.add_child(car)
			check(car.configure_kind(kind))
			car.bind(fixture.get_node("traversal"))
			var direction := Vector3.BACK if code==76 else Vector3.RIGHT
			car.position = Vector3(22.5,GROUND+.04,22.5)-direction*.3
			car.rotation.y = atan2(-direction.x,-direction.z)
			var reports: Array[String] = []
			car.recovery_requested.connect(func(reason: String) -> void: reports.append(reason))
			await physics_frame
			var driver := Driver.new()
			driver.car = car
			driver.throttle = .2
			driver.route = [car.position,car.position+direction*.85]
			fixture.add_child(driver)
			await driver.completed
			await process_frame
			check((car.position-driver.route[-1]).length()<.12,"tall vehicle crosses under lowered deck: %s/%d" % [kind,code])
			check(reports.is_empty(),"underpass retains support")
			for feet: Vector3 in driver.positions:
				check(feet.y+car.vehicle_size().y<GROUND+.285,"roof clears actual deck underside")
			fixture.free()
			await physics_frame

func test_traffic_height_matches_physical_ramp_and_highway_floor() -> void:
	var city := flat_city()
	city.building.put(22,22,93)
	city.building.put(22,21,74)
	city.building.put(23,22,30)
	var fixture := Fixture.attach(self,city)
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var world: CityTraversalWorld3D = fixture.get_node("traversal")
	await physics_frame
	for step: int in 17:
		var angle := PI*.5*step/16.0
		var offset := Vector2(1,0)+Vector2(-sin(angle),cos(angle))*.5
		var traffic := graph.point(Vector2i(22,22),&"road",offset)
		var hit := world.support_near(traffic,.003,.003,[])
		check(not hit.is_empty(),"ambient ramp position stays on the actual floor")
		if not hit.is_empty(): check(absf(hit.position.y-traffic.y)<.0006,"traffic and collision heights agree")
	var highway := graph.point(Vector2i(22,21),&"highway")
	check(absf(highway.y-(GROUND+.38))<.00001,"traffic uses lowered deck height")
	var hit := world.support_near(highway,.003,.003,[])
	check(not hit.is_empty() and absf(hit.position.y-highway.y)<.00001,"highway traffic rests on visible collision deck")
	# A stable ray may reach farther for triangle precision, but support must
	# still obey the requested physical interval rather than snapping to it.
	var middle := graph.point(Vector2i(22,22),&"road",Vector2(1,0)+Vector2(-1,1).normalized()*.5)
	check(world.support_near(middle+Vector3.UP*.04,.003,.003,[]).is_empty(),"fine facets cannot enlarge accepted downward support")
	check(world.support_near(middle-Vector3.UP*.04,.003,.003,[]).is_empty(),"fine facets cannot enlarge accepted upward support")
	fixture.free()
	await physics_frame

func test_catalog_car_crosses_rounded_hills_and_unequal_bridge_banks() -> void:
	for ew: bool in [false,true]:
		for bridge: bool in [false,true]:
			for descending: bool in [false,true]:
				var city := SmoothFixture.uneven_bridge_city(ew) if bridge else SmoothFixture.hill_city(ew)
				var before := SaveFormat.encode_city(city)
				var graph := CityTrafficGraph.new()
				graph.bind_city(city)
				var route: Array[Vector3] = []
				var start := 16.5 if bridge else 20.5
				var length := 14.0 if bridge else 6.0
				for step: int in int(length*4)+1:
					var along := start+step*.25
					var p := Vector2(along,22.5) if ew else Vector2(22.5,along)
					var cell := Vector2i(floori(p.x),floori(p.y))
					route.append(graph.point(cell,&"road",p-Vector2(cell)))
				if descending: route.reverse()
				var fixture := Fixture.attach(self,city)
				var car := ExploreCar.new()
				fixture.add_child(car)
				check(car.configure_kind(&"car"))
				car.bind(fixture.get_node("traversal"))
				car.route_graph = graph
				car.position = route[0]
				var direction := route[1]-route[0]
				car.rotation.y = atan2(-direction.x,-direction.z)
				var reports: Array[String] = []
				car.recovery_requested.connect(func(reason: String) -> void: reports.append(reason))
				await physics_frame
				var driver := Driver.new()
				driver.car = car
				driver.route = route
				driver.throttle = .6
				driver.max_ticks = 2800 if bridge else 1600
				fixture.add_child(driver)
				await driver.completed
				await process_frame
				print("SMOOTH_JOURNEY ew=%s bridge=%s descending=%s waypoint=%d ticks=%d pitch_step=%.4f reports=%s" % [ew,bridge,descending,driver.route_index,driver.ticks,driver.maximum_pitch_step,reports])
				check_eq(driver.route_index,route.size()-1,"completes physical hill/bridge journey")
				check(car.position.distance_to(route[-1])<.12,"reaches exact adjoining destination")
				check(reports.is_empty() and car.has_support(),"retains real support without recovery")
				check_lt(driver.maximum_pitch_step,4.0,"hill/bridge chassis follows gradual grade")
				check_eq(SaveFormat.encode_city(city),before,"hill/bridge journey preserves city bytes")
				fixture.free()
				await physics_frame
