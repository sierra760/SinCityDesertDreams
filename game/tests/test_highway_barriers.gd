# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Elevated highway slabs, barriers and ramp edges: piers meet a visible
## soffit, open edges and medians stop vehicles, ramp mouths stay open, road
## end skirts never share a plane, and a car at full throttle keeps to a ramp.
extends "res://tests/exploration/async_test_case.gd"

const Fixture := preload("res://tests/exploration/traversal_fixture.gd")
const GROUND := 4*CityGeometry3D.HEIGHT
const RAMP := Vector2i(22,22)
const SmoothFixture := preload("res://tests/test_highway_smoothness.gd")

## Paired east-west carriageways on rows 20/21, a road on row 22 from the west
## and an onramp at RAMP climbing from that road onto row 21.
static func interchange() -> City:
	var city := flat_city()
	for x: int in range(10,34):
		city.building.put(x,20,NetworkShapes.HIGHWAY_EW)
		city.building.put(x,21,NetworkShapes.HIGHWAY_EW)
	for x: int in range(10,22):
		city.building.put(x,22,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,10))
	city.building.putv(RAMP,94)
	return city

## Obstacle triangles whose centroid lies in the XZ rectangle and height band.
static func obstacles_in(layer: CityNetworks3D, area: Rect2, low: float, high: float) -> int:
	var faces: PackedVector3Array = layer.physical_data().physical_obstacle_faces
	var count := 0
	for i: int in range(0,faces.size(),3):
		var c := (faces[i]+faces[i+1]+faces[i+2])/3.0
		if area.has_point(Vector2(c.x,c.z)) and c.y>=low and c.y<=high: count += 1
	return count

static func colored(layer: CityNetworks3D, color: Color) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i: int in range(0,layer._faces.size(),3):
		if layer._colors[i].is_equal_approx(color):
			points.append(layer._faces[i]); points.append(layer._faces[i+1]); points.append(layer._faces[i+2])
	return points

func test_piers_meet_a_visible_deck_soffit() -> void:
	var city := interchange()
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	var deck := GROUND+CityNetworks3D.HIGHWAY_ELEVATION
	var soffit := colored(layer,CityNetworks3D.DECK_SOFFIT)
	check_gt(soffit.size(),0,"elevated decks draw an underside")
	var lowest := INF
	var highest := -INF
	for p: Vector3 in soffit:
		if p.z<20 or p.z>21.9 or p.x<12 or p.x>32: continue
		lowest = minf(lowest,p.y)
		highest = maxf(highest,p.y)
	check(is_equal_approx(lowest,deck-.008-CityNetworks3D.DECK_DEPTH) and is_equal_approx(highest,lowest),"straight soffit lies one deck depth below the shoulder")
	var piers := 0
	for box: Dictionary in layer.physical_data().physical_boxes:
		var t: Transform3D = box.transform
		var size: Vector3 = box.size
		if t.origin.z<20 or t.origin.z>22 or t.origin.x<12 or t.origin.x>32: continue
		piers += 1
		var top := t.origin.y+size.y*.5
		check(top>=lowest-.0001 and top<=deck-.008,"pier top %s reaches into the slab" % t.origin)
	check_gt(piers,10,"highway piers sampled")
	layer.free()

func test_open_edges_and_median_carry_barriers_with_a_ramp_mouth_gap() -> void:
	var city := interchange()
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	var deck := GROUND+CityNetworks3D.HIGHWAY_ELEVATION
	var low := deck
	var high := deck+CityNetworks3D.BARRIER_GUARD_HEIGHT
	# North edge of row 20, median on the row 20/21 boundary, south edge of row 21.
	check_gt(obstacles_in(layer,Rect2(14,19.99,1,.04),low,high),0,"outer north barrier")
	check_gt(obstacles_in(layer,Rect2(14,20.97,1,.06),low,high),0,"median between paired carriageways")
	check_gt(obstacles_in(layer,Rect2(14,21.95,1,.05),low,high),0,"outer south barrier")
	# The ramp mouth on row 21's south edge spans x 22.1625..22.8375.
	check_eq(obstacles_in(layer,Rect2(22.2,21.9,.6,.1),low,high),0,"no barrier across the ramp mouth")
	check_gt(obstacles_in(layer,Rect2(22.86,21.95,.12,.05),low,high),0,"barrier resumes beside the mouth")
	# No barrier on the open slit between the paired decks other than the median.
	check_eq(obstacles_in(layer,Rect2(14,20.6,1,.3),low,high),0,"travel lanes stay clear")
	layer.free()

func test_ramp_edges_carry_barriers_on_both_sides() -> void:
	var city := interchange()
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	var faces: PackedVector3Array = layer.physical_data().physical_obstacle_faces
	var inner := 0
	var outer := 0
	var pivot := Vector2(22,22)
	for i: int in range(0,faces.size(),3):
		var c := (faces[i]+faces[i+1]+faces[i+2])/3.0
		var p := Vector2(c.x,c.z)
		# Guard walls stand taller than the slab's own below-deck boundary walls.
		var rise := maxf(faces[i].y,maxf(faces[i+1].y,faces[i+2].y))-minf(faces[i].y,minf(faces[i+1].y,faces[i+2].y))
		if p.x<22 or p.y<22 or rise<CityNetworks3D.BARRIER_GUARD_HEIGHT: continue
		var radius := p.distance_to(pivot)
		if radius>.15 and radius<.2: inner += 1
		if radius>.8 and radius<.84: outer += 1
	check_gt(inner,30,"inner ramp barrier")
	check_gt(outer,30,"outer ramp barrier")
	layer.free()

func test_road_end_skirts_beside_a_ramp_mouth_do_not_share_heights() -> void:
	var city := interchange()
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	# Vertical faces of the road cell west of the ramp in the plane x = 22.
	var bands: Dictionary = {}
	for i: int in range(0,layer._faces.size(),3):
		var a: Vector3 = layer._faces[i]
		var b: Vector3 = layer._faces[i+1]
		var c: Vector3 = layer._faces[i+2]
		if layer._cells[i/3] != Vector2i(21,22): continue
		if not (is_equal_approx(a.x,22) and is_equal_approx(b.x,22) and is_equal_approx(c.x,22)): continue
		var key := layer._colors[i].to_html()
		var band: Vector2 = bands.get(key,Vector2(INF,-INF))
		bands[key] = Vector2(minf(band.x,minf(a.y,minf(b.y,c.y))),maxf(band.y,maxf(a.y,maxf(b.y,c.y))))
	check_eq(bands.size(),3,"verge, shoulder and pavement each close the exposed end")
	var ranges: Array = bands.values()
	for i: int in ranges.size():
		for j: int in range(i+1,ranges.size()):
			var overlap: float = minf(ranges[i].y,ranges[j].y)-maxf(ranges[i].x,ranges[j].x)
			check_lt(overlap,.0011,"skirt bands %s and %s overlap only by the hairline" % [ranges[i],ranges[j]])
	layer.free()

## Highest physical floor under `p`, or -INF.
static func floor_height(faces: PackedVector3Array, p: Vector2) -> float:
	var best := -INF
	for i: int in range(0,faces.size(),3):
		var a := faces[i]
		var b := faces[i+1]
		var c := faces[i+2]
		var ab := Vector2(b.x-a.x,b.z-a.z)
		var ac := Vector2(c.x-a.x,c.z-a.z)
		var area := ab.cross(ac)
		if absf(area)<.000000000001: continue
		var ap := p-Vector2(a.x,a.z)
		var v := ap.cross(ac)/area
		var w := ab.cross(ap)/area
		if v<-.000001 or w<-.000001 or v+w>1.000001: continue
		best = maxf(best,a.y+(b.y-a.y)*v+(c.y-a.y)*w)
	return best

func test_ramp_mouth_floor_runs_continuously_onto_the_highway_lanes() -> void:
	var city := interchange()
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	var faces: PackedVector3Array = layer.physical_data().physical_floor_faces
	for x: float in [22.25,22.5,22.75]:
		var missing := 0
		var step := 0.0
		var previous := NAN
		for i: int in 201:
			var h := floor_height(faces,Vector2(x,21.9+.2*i/200.0))
			if h == -INF:
				missing += 1
				continue
			if not is_nan(previous): step = maxf(step,absf(h-previous))
			previous = h
		check_eq(missing,0,"no slit between ramp and highway at x=%.2f" % x)
		check_lt(step,.002,"no shoulder dip across the mouth at x=%.2f" % x)
		var surface := SmoothFixture.pavement_hit(layer,Vector2(x,21.98))
		check(not surface.is_empty() and absf(float(surface.height)-(GROUND+CityNetworks3D.HIGHWAY_ELEVATION))<.0001,"visible pavement reaches the edge at x=%.2f" % x)
	layer.free()

func test_ramp_collision_floor_is_coarse_and_follows_the_visible_surface() -> void:
	var city := interchange()
	var layer := CityNetworks3D.new()
	layer.rebuild(city)
	var faces: PackedVector3Array = layer.physical_data().physical_floor_faces
	var triangles := 0
	for i: int in range(0,faces.size(),3):
		var c := (faces[i]+faces[i+1]+faces[i+2])/3.0
		if floori(c.x)==RAMP.x and floori(c.z)==RAMP.y: triangles += 1
	# The visible grid is 128 steps x 24 bands; driving on it cost 5-15 ms a tick.
	check_lt(triangles,700,"ramp collision floor stays coarse")
	var worst := 0.0
	for ri: int in 13:
		for si: int in 64:
			var p := Vector2(RAMP)+Vector2.DOWN.rotated(Vector2.DOWN.angle_to(Vector2.RIGHT)*(si+.5)/64.0)*(.21+.58*ri/12.0)
			var visible := SmoothFixture.pavement_hit(layer,p)
			if visible.is_empty(): continue
			worst = maxf(worst,absf(floor_height(faces,p)-float(visible.height)))
	check_lt(worst,.0015,"collision floor within 2.4 cm of the visible pavement")
	layer.free()

class Driver extends Node:
	signal completed
	var car: ExploreCar
	var route: Array[Vector3] = []
	var route_index := 0
	var ticks := 0
	var stalled := 0
	var ramp_speed := 0.0
	func _physics_process(delta: float) -> void:
		var feet := car.feet_position()
		var best := route_index
		var best_d := INF
		for j: int in range(route_index,mini(route.size(),route_index+8)):
			var d := Vector2(feet.x,feet.z).distance_to(Vector2(route[j].x,route[j].z))
			if d<best_d: best_d = d; best = j
		route_index = best
		var offset := route[mini(route.size()-1,route_index+3)]-feet
		var frame := ExploreInputFrame.idle()
		frame.move = Vector2(clampf(-wrapf(atan2(-offset.x,-offset.z)-car.rotation.y,-PI,PI)*3,-1,1),-1.0)
		car.step(frame,0,delta)
		var moved := Vector2(car.feet_position().x-feet.x,car.feet_position().z-feet.z).length()
		if ticks>90 and moved<.0005: stalled += 1
		if Vector2i(floori(feet.x),floori(feet.z))==RAMP: ramp_speed = maxf(ramp_speed,moved/delta)
		ticks += 1
		if ticks>=1200 or route_index>=route.size()-2:
			set_physics_process(false)
			completed.emit.call_deferred()

## Full throttle with path steering between the road at x 14.5 and the highway
## at x 28, through RAMP; returns [driver, reports, final feet].
func drive_ramp(descending: bool) -> Array:
	var city := interchange()
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var route: Array[Vector3] = []
	for i: int in 30: route.append(Vector3(14.5+i*.25,GROUND+.04,22.5))
	var pivot := Vector2(22,22)
	for step: int in 17:
		var p := pivot+Vector2.DOWN.rotated(Vector2.DOWN.angle_to(Vector2.RIGHT)*step/16.0)*.5
		route.append(Vector3(p.x,GROUND+.04+.34*step/16.0,p.y))
	for i: int in range(1,24): route.append(Vector3(22.5+i*.25,GROUND+.38,21.5))
	if descending: route.reverse()
	var fixture := Fixture.attach(self,city)
	var car := ExploreCar.new()
	fixture.add_child(car)
	check(car.configure_kind(&"car"),"catalog car")
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
	var feet := car.feet_position()
	print("FULL_THROTTLE_RAMP descending=%s waypoint=%d/%d ticks=%d stalled=%d ramp_speed=%.3f feet=%s reports=%s" % [descending,driver.route_index,route.size()-1,driver.ticks,driver.stalled,driver.ramp_speed,feet,reports])
	check(reports.is_empty(),"no fall from the ramp edge")
	check_ge(driver.route_index,route.size()-2,"reaches the far end")
	# 14 tiles at the 1.2 tile/s cap is ~700 ticks plus acceleration and the ramp.
	check_lt(driver.ticks,950,"keeps moving instead of stalling")
	check_lt(driver.stalled,20,"at most a brief scrape at the ramp mouth")
	check_lt(driver.ramp_speed,ExploreCar.RAMP_SPEED+.1,"eases to the ramp speed on the curve")
	fixture.free()
	await physics_frame
	return [driver,reports,feet]

func test_full_throttle_climb_eases_onto_the_highway() -> void:
	var result: Array = await drive_ramp(false)
	check(Vector3(result[2]).y>GROUND+.37,"finishes on the elevated deck")

func test_full_throttle_descent_reaches_the_road_without_stalling() -> void:
	var result: Array = await drive_ramp(true)
	check(absf(Vector3(result[2]).y-(GROUND+.04))<.01,"finishes on the road")

class FixedDriver extends Node:
	signal completed
	var car: ExploreCar
	var ticks := 0
	func _physics_process(delta: float) -> void:
		var frame := ExploreInputFrame.idle()
		frame.move = Vector2(0,-1)
		car.step(frame,0,delta)
		ticks += 1
		if ticks>=300:
			set_physics_process(false)
			completed.emit.call_deferred()

## Drives straight at full throttle from the road on row 22, `angle` radians
## south of east, toward the road's south edge; returns [feet, speed].
func drive_at_edge(angle: float) -> Array:
	var city := interchange()
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	var fixture := Fixture.attach(self,city)
	var car := ExploreCar.new()
	fixture.add_child(car)
	car.configure_kind(&"car")
	car.bind(fixture.get_node("traversal"))
	car.route_graph = graph
	car.global_position = Vector3(12.5,GROUND+.04,22.5)
	car.rotation.y = atan2(-cos(angle),-sin(angle))
	await physics_frame
	var driver := FixedDriver.new()
	driver.car = car
	fixture.add_child(driver)
	await driver.completed
	await process_frame
	var result := [car.feet_position(),car.speed()]
	fixture.free()
	await physics_frame
	return result

func test_glancing_road_edge_exit_slides_along_instead_of_stalling() -> void:
	var glancing: Array = await drive_at_edge(deg_to_rad(20))
	var feet: Vector3 = glancing[0]
	print("EDGE glancing feet=%s speed=%.3f" % [feet,glancing[1]])
	check_lt(feet.z,23.0,"stays on the road")
	# Accelerating from rest reaches the edge near x 14 after about 135 ticks.
	check_gt(feet.x,16.0,"keeps travelling along the road")
	check_gt(float(glancing[1]),.5,"keeps most of its speed")
	var head_on: Array = await drive_at_edge(deg_to_rad(90))
	print("EDGE head_on feet=%s speed=%.3f" % [head_on[0],head_on[1]])
	check_lt(Vector3(head_on[0]).z,23.0,"head-on exit stays on the road")
	check_lt(float(head_on[1]),.2,"head-on exit stops the car")
