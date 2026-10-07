# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

func _highway_city() -> City:
	var city := flat_city()
	for y: int in range(10,40):
		for x: int in [20,21]: city.building.put(x,y,NetworkShapes.HIGHWAY_NS)
		city.building.put(19,y,Buildings.COM_1X1_FIRST)
		city.traffic.put(10,y/2,255)
	return city

func test_paired_carriageways_have_two_us_direction_lanes() -> void:
	var traffic := CityTraffic3D.new()
	traffic.bind_city(_highway_city())
	traffic.advance(0,true)
	var lanes: Dictionary = {}
	for a: Dictionary in traffic.actors:
		if a.domain != &"highway": continue
		check_eq(a.next.y-a.cell.y,1 if a.cell.x==20 else -1,"each carriageway is one-way, US right-hand travel")
		lanes[Vector2i(a.cell.x,int(a.get("lane",-1)))] = true
	for x: int in [20,21]:
		for lane: int in [0,1]: check(lanes.has(Vector2i(x,lane)),"both lanes used on both carriageways")
	traffic.free()

func test_four_corner_orientations_follow_exact_lane_arcs() -> void:
	for quarter: int in 4:
		var city := flat_city()
		var anchor := Vector2i(30,30)
		var code: int = [NetworkShapes.HIGHWAY_CORNER_NE,NetworkShapes.HIGHWAY_CORNER_SE,NetworkShapes.HIGHWAY_CORNER_SW,NetworkShapes.HIGHWAY_CORNER_NW][quarter]
		for dy: int in 2:
			for dx: int in 2: city.building.putv(anchor+Vector2i(dx,dy),code)
		# Continue both ends sufficiently far that no path can use an isolated stub.
		var mask := CityNetworks3D.network_mask(code,NetworkShapes.Family.HIGHWAY)
		for direction: int in 4:
			if not mask & (1<<direction): continue
			for length: int in range(1,5):
				for across: int in 2:
					var cell := anchor+Vector2i(across,-length) if direction==0 else anchor+Vector2i(1+length,across) if direction==1 else anchor+Vector2i(across,1+length) if direction==2 else anchor+Vector2i(-length,across)
					city.building.putv(cell,NetworkShapes.HIGHWAY_NS if direction%2==0 else NetworkShapes.HIGHWAY_EW)
		var traffic := CityTraffic3D.new()
		traffic.bind_city(city)
		var graph := traffic.graph
		var pivots: Array[Vector2] = [Vector2(2,0),Vector2(2,2),Vector2(0,2),Vector2.ZERO]
		var tested := 0
		for cell: Vector2i in graph.highways.routes:
			for segment: Dictionary in graph.highways.routes[cell]:
				if not segment.has("radius"): continue
				tested += 1
				check(graph.neighbors(cell,&"highway").has(segment.previous),"arc entrance is physically connected")
				check(graph.traffic_choices(cell,&"highway",segment.previous,segment.lane).has(segment.next),"arc leaves on same lane/carriageway")
				var a := {"id":tested,"kind":&"car","type":&"highway","domain":&"highway","cell":cell,"previous":segment.previous,"next":segment.next,"lane":segment.lane,"side":1.0,"t":.5}
				for t: float in [0.0,.5,1.0]:
					a.t = t
					var pose := traffic.actor_pose(a)
					var p := Vector2(pose.origin.x,pose.origin.z)
					check(absf(p.distance_to(Vector2(anchor)+pivots[quarter])-float(segment.radius))<.0001,"vehicles follow the exact authored pavement arc")
					check(p.x>=cell.x-.001 and p.x<=cell.x+1.001 and p.y>=cell.y-.001 and p.y<=cell.y+1.001,"lane stays within its route cell")
				# Neighboring segment endpoints join without a lateral teleport.
				a.t = 1.0
				var end := traffic.actor_pose(a).origin
				var choices := graph.traffic_choices(segment.next,&"highway",cell,segment.lane)
				check(not choices.is_empty())
				if not choices.is_empty():
					var b := a.duplicate(true)
					b.cell=segment.next; b.previous=cell; b.next=choices[0]; b.t=0.0
					check(end.distance_to(traffic.actor_pose(b).origin)<.0001,"lane endpoints are continuous across cells and straights")
		check_eq(tested,8,"four lanes comprise two short and six outer-cell segments")
		var traversed := 0
		for cell: Vector2i in graph.highways.routes:
			for segment: Dictionary in graph.highways.routes[cell]:
				if not segment.has("radius") or (segment.radius>1 and not is_zero_approx(segment.start)) or (segment.radius<1 and not is_equal_approx(segment.start,PI*.5)): continue
				var start: Vector2i = segment.previous
				var a := {"id":1000,"kind":&"car","type":&"highway","domain":&"highway","cell":start,"previous":start+(start-cell),"next":cell,"lane":segment.lane,"side":1.0,"t":.5,"speed":1.0,"turns":0,"stopped":false}
				traffic.actors.assign([a])
				var prior := traffic.actor_pose(a).origin
				var entered := false
				var exited := false
				for step: int in 300:
					traffic._step(.02)
					var current := traffic.actor_pose(a).origin
					check(current.distance_to(prior)<=.0201,"cell transitions preserve physical distance including short curve segments")
					check(graph.traffic_choices(a.cell,&"highway",a.previous,a.lane).has(a.next),"sustained route stays on directed lane")
					prior = current
					var on_arc := graph.highway_segment(a.cell,a.previous,a.next,a.lane).has("radius")
					if on_arc: entered=true
					if entered and not on_arc and a.t>.5:
						exited=true
						break
				check(entered and exited,"car completes straight-to-curve-to-straight traversal")
				traversed += 1
		check_eq(traversed,4,"both lanes of both carriageways traverse corner")
		traffic.free()

func test_real_side_ramp_merges_in_carriageway_direction() -> void:
	var city := _highway_city()
	var ramp := Vector2i(19,20)
	city.building.putv(ramp,Buildings.ONRAMP_FIRST+2)
	city.flags.putv(ramp,RotationMapper.AXIS_FLAG)
	var ends := NetworkShapes.onramp_endpoints(Buildings.ONRAMP_FIRST+2,true)
	var low := ramp+Vector2i(ends[0])
	var high := ramp+Vector2i(ends[1])
	city.building.putv(low,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5))
	var graph := CityTrafficGraph.new()
	graph.bind_city(city)
	check_eq(high,Vector2i(20,20))
	check(graph.neighbors(ramp,&"road").has(high),"side ramp reaches actual straight elevated highway")
	check(graph.neighbors(high,&"highway").has(ramp),"ramp connection reciprocal")
	check_eq(graph.traffic_choices(high,&"highway",ramp,1),[high+Vector2i.DOWN],"joining car uses the outside lane facing with traffic")
	check(graph.traffic_choices(high,&"highway",ramp,0).is_empty(),"ramp cannot cut straight across to median lane")
	check(graph.traffic_choices(high,&"highway",high+Vector2i.UP,1).has(ramp),"outer lane permits exit ramp")
	check(not graph.traffic_choices(high,&"highway",high+Vector2i.UP,0).has(ramp),"inner lane cannot cut across outer lane")

func test_lane_following_is_separate_and_claim_release_retains_direction() -> void:
	var traffic := CityTraffic3D.new()
	traffic.bind_city(_highway_city())
	traffic.advance(0,true)
	var a: Dictionary = traffic.actors[0].duplicate(true)
	a.cell=Vector2i(20,20);a.previous=Vector2i(20,19);a.next=Vector2i(20,21);a.domain=&"highway";a.type=&"highway";a.lane=0;a.id=500;a.t=.1
	var b := a.duplicate(true)
	b.id=501;b.lane=1;b.t=.2
	traffic.actors.assign([a,b])
	traffic._step(.01)
	check_gt(a.t,.1,"parallel lane does not queue behind neighboring lane")
	var claim := traffic.claim_nearby_vehicle(traffic.actor_pose(a).origin,.1)
	check(not claim.is_empty())
	traffic.release_vehicle(claim,Vector3(20.5,traffic.graph.center(a.cell,&"highway").y,20.5))
	check_eq(a.next-a.cell,Vector2i.DOWN,"release preserves carriageway direction")
	traffic.free()

func test_ramp_yields_then_merges_only_to_outer_lane() -> void:
	var city := _highway_city()
	var ramp := Vector2i(19,20)
	city.building.putv(ramp,Buildings.ONRAMP_FIRST+2)
	city.flags.putv(ramp,RotationMapper.AXIS_FLAG)
	city.building.put(19,19,NetworkShapes.shape_id(NetworkShapes.Family.ROAD,5))
	var traffic := CityTraffic3D.new()
	traffic.bind_city(city)
	var a := {"id":1,"kind":&"car","type":&"road","domain":&"road","cell":ramp,"previous":Vector2i(19,19),"next":Vector2i(20,20),"lane":0,"side":1.0,"t":.99,"speed":1.0,"turns":0,"stopped":false}
	var b := {"id":2,"kind":&"car","type":&"highway","domain":&"highway","cell":Vector2i(20,20),"previous":Vector2i(20,19),"next":Vector2i(20,21),"lane":1,"side":1.0,"t":.1,"speed":0.0,"turns":0,"stopped":false}
	traffic.actors.assign([a,b])
	traffic._step(.05)
	check_eq(a.cell,ramp,"ramp waits for an occupied shoulder lane")
	check(a.stopped)
	traffic.actors.assign([a])
	traffic._step(.1)
	check_eq(a.cell,Vector2i(20,20),"ramp enters when lane clears")
	check_eq(a.domain,&"highway")
	check_eq(a.lane,1,"entry uses shoulder lane")
	check_eq(a.next,Vector2i(20,21),"entry moves with US carriageway traffic")
	traffic.free()
